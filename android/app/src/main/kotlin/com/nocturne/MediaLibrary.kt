package com.nocturne

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/// What the app reads from and adds to the phone's media index.
class MediaLibrary(context: Context) {
    companion object {
        /// Music, or anything long enough to be a song, whatever the system thinks it is. Except
        /// voice recordings, which are the person's own (Android 12 and later can tell).
        fun audioSelection(sdk: Int = Build.VERSION.SDK_INT): String {
            val songs = "${MediaStore.Audio.Media.IS_MUSIC} != 0 OR ${MediaStore.Audio.Media.DURATION} > 30000"
            return if (sdk >= Build.VERSION_CODES.S) "($songs) AND ${MediaStore.Audio.Media.IS_RECORDING} = 0" else songs
        }

        /// One volume's songs as [generation] sees them, from rows of (generation added,
        /// generation modified): a removed song lowers the count, a new one raises the newest
        /// "added", a changed one the newest "modified".
        fun songsStamp(volume: String, rows: Cursor): String {
            var added = 0L
            var modified = 0L
            while (rows.moveToNext()) {
                added = maxOf(added, rows.getLong(0))
                modified = maxOf(modified, rows.getLong(1))
            }
            return "$volume=${rows.count}/$added/$modified"
        }
    }

    private val context = context.applicationContext
    private val resolver get() = context.contentResolver

    /// path + size + dateModified of every audio file in MediaStore.
    /// Tags aren't read here — the Dart side does that (audio_metadata_reader).
    fun queryAudio(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
        )
        val cursor = resolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, audioSelection(), null, null
        ) ?: return out
        cursor.use { c ->
            val dataCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val modCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            while (c.moveToNext()) {
                val path = c.getString(dataCol) ?: continue
                out.add(
                    mapOf(
                        "path" to path,
                        "size" to c.getLong(sizeCol),
                        "dateModified" to c.getLong(modCol) * 1000, // sec → ms
                    )
                )
            }
        }
        return out
    }

    /// A value that changes whenever a song is added, changed or removed in the media index, on
    /// every storage volume (SD card too). Null before Android 11, which has no generations,
    /// or when the index can't be read.
    ///
    /// Songs only: the index's own counter (MediaStore.getGeneration) also moves for every
    /// photo taken and every WhatsApp picture, and each of those cost a full library scan on the
    /// next return to the app.
    fun generation(): String? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) songsGeneration() else null

    @RequiresApi(Build.VERSION_CODES.R)
    private fun songsGeneration(): String? {
        val parts = ArrayList<String>()
        // The version changes when the index is rebuilt (generations start again from zero)
        parts.add(MediaStore.getVersion(context))
        // Generations are counted per volume, so each one is read on its own
        for (volume in MediaStore.getExternalVolumeNames(context).sorted()) {
            val cursor = resolver.query(
                MediaStore.Audio.Media.getContentUri(volume),
                arrayOf(MediaStore.MediaColumns.GENERATION_ADDED, MediaStore.MediaColumns.GENERATION_MODIFIED),
                audioSelection(), null, null,
            ) ?: return null
            parts.add(cursor.use { songsStamp(volume, it) })
        }
        return parts.joinToString(";")
    }

    fun scan(paths: List<String>) {
        MediaScannerConnection.scanFile(context, paths.toTypedArray(), null, null)
    }

    /// Calls [finished] once MediaScanner is done (max 5 s), so the following
    /// MediaStore enumerate sees the new files.
    fun scanAndWait(paths: List<String>, finished: () -> Unit) {
        if (paths.isEmpty()) {
            finished()
            return
        }
        val main = Handler(Looper.getMainLooper())
        val left = AtomicInteger(paths.size)
        val done = AtomicBoolean(false)
        val finish = { if (done.compareAndSet(false, true)) main.post(finished) }
        MediaScannerConnection.scanFile(context, paths.toTypedArray(), null) { _, _ ->
            if (left.decrementAndGet() == 0) finish()
        }
        main.postDelayed({ finish() }, 5000)
    }

    /// Writes a file to the shared Download folder (in [folder] inside it, if given); result: the
    /// visible path ("Download/name.csv"). Android 10+: MediaStore.Downloads (no permission
    /// needed); older versions write the file directly.
    fun saveToDownloads(name: String, mime: String, bytes: ByteArray, folder: String? = null): String {
        val shown = if (folder == null) "Download/$name" else "Download/$folder/$name"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
                if (folder != null) put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$folder")
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("MediaStore insert failed")
            try {
                (resolver.openOutputStream(uri) ?: error("cannot write")).use { it.write(bytes) }
            } catch (e: Exception) {
                // Otherwise a half-written, never-published entry stays in Download
                runCatching { resolver.delete(uri, null, null) }
                throw e
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return shown
        }
        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = if (folder == null) downloads else File(downloads, folder)
        dir.mkdirs()
        val f = File(dir, name)
        f.writeBytes(bytes)
        return f.path
    }

    /// Of the files named [prefix]… in Download/[folder], keeps the [keep] newest and deletes the
    /// rest, so weekly copies don't pile up. Android 10+ lists only the files this install
    /// wrote: one left by an earlier install isn't touched. Returns how many were deleted.
    fun keepNewestInDownloads(folder: String, prefix: String, keep: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val old = ArrayList<android.net.Uri>()
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.RELATIVE_PATH} = ? AND ${MediaStore.Downloads.DISPLAY_NAME} LIKE ?",
                arrayOf("${Environment.DIRECTORY_DOWNLOADS}/$folder/", "$prefix%"),
                "${MediaStore.Downloads.DATE_ADDED} DESC",
            )?.use { c ->
                var seen = 0
                while (c.moveToNext()) {
                    if (++seen > keep) old.add(ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, c.getLong(0)))
                }
            }
            return old.count { runCatching { resolver.delete(it, null, null) > 0 }.getOrDefault(false) }
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folder)
        val files = dir.listFiles { f -> f.name.startsWith(prefix) }?.sortedByDescending { it.lastModified() } ?: return 0
        return files.drop(keep).count { it.delete() }
    }
}
