package com.royal.sonar

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.InputStream

/// "Open with Nocturne", Share and "Import files": brings a file into the library.
///
/// * [resolve]: if the content:// URI is already a readable file on the phone
///   (file manager, MediaStore) returns its path — no copy needed.
/// * [import]: otherwise (Telegram FileProvider, file_picker cache) copies the file
///   to `Music/Sonar/` (MediaStore insert — needs no permission) and returns
///   the new file's path. If the same name + size already exists, it isn't copied again.
class AudioImporter(private val context: Context) {
    private val resolver get() = context.contentResolver
    private val folder = Environment.DIRECTORY_MUSIC + "/Sonar"

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
        val path = data?.takeIf { File(it).canRead() }
        return Info(path, name, size)
    }

    /// Copy the file to Music/Sonar; path of the new (or already existing identical) file.
    fun import(source: String): String {
        val info = resolve(source)
        val name = safeName(info.name)
        existing(name, info.size)?.let { return it }
        return openInput(source).use { input -> write(name, mimeOf(source, name), input) }
    }

    private fun openInput(source: String): InputStream =
        if (source.startsWith("/")) File(source).inputStream()
        else resolver.openInputStream(Uri.parse(source)) ?: error("cannot open $source")

    private fun write(name: String, mime: String, input: InputStream): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Android 9 and older: writing to a public folder needs permission → the app's own
            // Music folder; the Dart side then notifies MediaScanner so
            // MediaStore enumerate finds it
            val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "Sonar").apply { mkdirs() }
            val out = uniqueFile(dir, name)
            out.outputStream().use { input.copyTo(it) }
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
            resolver.openOutputStream(item)?.use { input.copyTo(it) } ?: error("cannot write")
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(item, values, null, null)
        } catch (e: Exception) {
            runCatching { resolver.delete(item, null, null) }
            throw e
        }
        return dataOf(item) ?: error("imported file has no path")
    }

    /// Same name + size in Music/Sonar → that file (when shared a second time).
    private fun existing(name: String, size: Long): String? {
        if (size <= 0) return null
        val dir = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
            File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "Sonar")
        else File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "Sonar")
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

    private fun safeName(n: String): String {
        val cleaned = n.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "audio" }
        return if (cleaned.contains('.')) cleaned else "$cleaned.mp3"
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
