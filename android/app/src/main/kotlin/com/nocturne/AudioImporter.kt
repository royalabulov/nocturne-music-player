package com.nocturne

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/// "Open with Nocturne", Share and "Import files": brings a file into the library.
///
/// * [resolve]: if the content:// URI is already a readable file on the phone
///   (file manager, MediaStore) returns its path — no copy needed.
/// * [import]: otherwise (a messenger's FileProvider, file_picker cache) copies the file
///   to `Music/Nocturne/` (MediaStore insert — needs no permission) and returns
///   the new file's path. If the same name + size already exists, it isn't copied again.
class AudioImporter(
    private val context: Context,
    private val maxBytes: Long = MAX_IMPORT_BYTES,
    private val freeBytes: () -> Long = { context.getExternalFilesDir(null)?.usableSpace ?: Long.MAX_VALUE },
) {
    companion object {
        /// A long FLAC mix fits; an endless stream from a hostile app doesn't.
        const val MAX_IMPORT_BYTES = 2L * 1024 * 1024 * 1024

        /// A copy stops short of this. Another app can send one big file after another without
        /// anyone confirming, and a phone with no space left stops working properly.
        const val MIN_FREE_BYTES = 200L * 1024 * 1024
        private const val FREE_CHECK_EVERY_BYTES = 1024L * 1024

        /// File systems allow 255 bytes; this leaves room for " (12)".
        private const val MAX_NAME_BYTES = 240

        /// The name is another app's word too: separators, and characters that make it look
        /// like something else (control characters, text-direction marks).
        private val UNSAFE_NAME_CHARS = Regex("[\\\\/:*?\"<>|\\p{Cntrl}\\u202A-\\u202E\\u2066-\\u2069]")

        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "m4a", "m4b", "mp4", "aac", "wav", "ogg", "oga", "opus", "aiff", "aif",
            "ape", "wma", "amr", "mid", "midi", "mka", "webm", "wv", "ac3", "3gp",
        )
    }

    private val resolver get() = context.contentResolver
    private val folder = Environment.DIRECTORY_MUSIC + "/Nocturne"

    data class Info(val path: String?, val name: String, val size: Long)

    fun resolve(source: String): Info {
        if (source.startsWith("/")) {
            val f = File(source)
            return Info(if (f.canRead()) f.absolutePath else null, f.name, f.length())
        }
        val uri = Uri.parse(source)
        if (uri.scheme == "file") {
            val f = File(uri.path ?: "")
            return Info(if (f.canRead()) f.absolutePath else null, f.name, f.length())
        }
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "audio"
        var size = -1L
        var data: String? = null
        runCatching {
            resolver.query(uri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }
                        ?.let { c.getString(it) }?.let { name = it }
                    c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }
                        ?.let { if (!c.isNull(it)) size = c.getLong(it) }
                    c.getColumnIndex(MediaStore.MediaColumns.DATA).takeIf { it >= 0 }
                        ?.let { data = c.getString(it) }
                }
            }
        }
        return Info(IncomingUriPolicy.trustedPath(data, context.packageName), name, size)
    }

    /// Copy the file to Music/Nocturne; path of the new (or already existing identical) file.
    fun import(source: String): String {
        val info = resolve(source)
        if (info.size > maxBytes) error("file too large")
        val name = safeName(info.name)
        existing(name, info.size)?.let { return it }
        requireSpaceFor(info.size.coerceAtLeast(0))
        return openInput(source).buffered().use { input ->
            requireAudio(input)
            write(name, mimeOf(source, name), input)
        }
    }

    private fun openInput(source: String): InputStream =
        if (source.startsWith("/")) File(source).inputStream()
        else resolver.openInputStream(Uri.parse(source)) ?: error("cannot open file")

    /// Looks at the start of the stream and leaves it where it was.
    private fun requireAudio(input: BufferedInputStream) {
        val head = ByteArray(AudioSniffer.HEAD_BYTES)
        input.mark(head.size)
        var size = 0
        while (size < head.size) {
            val n = input.read(head, size, head.size - size)
            if (n < 0) break
            size += n
        }
        input.reset()
        if (!AudioSniffer.looksLikeAudio(head, size)) error("not an audio file")
    }

    private fun requireSpaceFor(bytes: Long) {
        if (freeBytes() - bytes < MIN_FREE_BYTES) error("not enough storage")
    }

    /// What a provider says about the size means nothing: the real limits are here.
    private fun copyLimited(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        var sinceCheck = 0L
        while (true) {
            val n = input.read(buffer)
            if (n < 0) return
            total += n
            sinceCheck += n
            if (total > maxBytes) error("file too large")
            if (sinceCheck >= FREE_CHECK_EVERY_BYTES) {
                sinceCheck = 0
                requireSpaceFor(0)
            }
            output.write(buffer, 0, n)
        }
    }

    private fun write(name: String, mime: String, input: InputStream): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Android 9 and older: writing to a public folder needs permission → the app's own
            // Music folder; the Dart side then notifies MediaScanner so
            // MediaStore enumerate finds it
            val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "Nocturne").apply { mkdirs() }
            val out = uniqueFile(dir, name)
            try {
                out.outputStream().use { copyLimited(input, it) }
            } catch (e: Exception) {
                out.delete()
                throw e
            }
            return out.absolutePath
        }
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, name)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, folder)
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val item = resolver.insert(collection, values) ?: error("MediaStore insert failed")
        try {
            resolver.openOutputStream(item)?.use { copyLimited(input, it) } ?: error("cannot write")
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(item, values, null, null)
        } catch (e: Exception) {
            runCatching { resolver.delete(item, null, null) }
            throw e
        }
        return dataOf(item) ?: error("imported file has no path")
    }

    /// Same name + size in Music/Nocturne → that file (when shared a second time).
    private fun existing(name: String, size: Long): String? {
        if (size <= 0) return null
        val dir = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
            File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "Nocturne")
        else File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "Nocturne")
        val f = File(dir, name)
        return if (f.exists() && f.length() == size) f.absolutePath else null
    }

    private fun dataOf(uri: Uri): String? =
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    private fun mimeOf(source: String, name: String): String {
        if (!source.startsWith("/")) {
            runCatching { resolver.getType(Uri.parse(source)) }.getOrNull()
                ?.takeIf { it.startsWith("audio/") }?.let { return it }
        }
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "audio/mpeg"
    }

    /// Stays in the folder ("..", "a/b"), isn't hidden, and always ends in an audio extension.
    private fun safeName(n: String): String {
        val cleaned = n.replace(UNSAFE_NAME_CHARS, "_").trim().trim('.').trim().ifEmpty { "audio" }
        val ext = cleaned.substringAfterLast('.', "")
        val hasAudioExt = ext.lowercase() in AUDIO_EXTENSIONS
        // Cut first: the name is another app's word, and it can be megabytes long
        var base = (if (hasAudioExt) cleaned.substringBeforeLast('.') else cleaned).take(MAX_NAME_BYTES)
        val suffix = if (hasAudioExt) ".$ext" else ".mp3"
        while ((base + suffix).toByteArray().size > MAX_NAME_BYTES) base = base.dropLast(1)
        if (base.lastOrNull()?.isHighSurrogate() == true) base = base.dropLast(1)
        return base + suffix
    }

    private fun uniqueFile(dir: File, name: String): File {
        var f = File(dir, name)
        var i = 1
        val base = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.', "")
        while (f.exists()) f = File(dir, "$base ($i).$ext").also { i++ }
        return f
    }
}
