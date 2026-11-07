package com.nocturne

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/// What the app reads from and adds to the phone's media index.
class MediaLibrary(context: Context) {
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
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 OR ${MediaStore.Audio.Media.DURATION} > 30000"
        val cursor = resolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, null, null
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

    /// Writes a file to the shared Download folder; result: the visible path ("Download/name.csv").
    /// Android 10+: MediaStore.Downloads (no permission needed); older versions write the file directly.
    fun saveToDownloads(name: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("MediaStore insert failed")
            resolver.openOutputStream(uri)!!.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Download/$name"
        }
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        val f = File(dir, name)
        f.writeBytes(bytes)
        return f.path
    }
}
