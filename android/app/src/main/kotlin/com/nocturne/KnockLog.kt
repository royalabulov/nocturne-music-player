package com.nocturne

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/// Permanent record of the knock detector's decisions (logcat keeps only ~20 minutes on the
/// phone). One JSON object per line in <filesDir>/logs/knock.log; never leaves the phone unless
/// the user exports it. A separate file, not the library database: no migration, and shaking
/// data can never touch the user's songs/playlists.
object KnockLog {
    /// knock.log is renamed to knock.old.log at this size → at most twice this on disk.
    private const val MAX_FILE_BYTES = 4L * 1024 * 1024

    private val writer = Executors.newSingleThreadExecutor()
    private val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private var dir: File? = null

    fun init(context: Context) {
        if (dir == null) dir = File(context.filesDir, "logs")
    }

    /// Safe from any thread; the file is written on its own thread, never the sensor's.
    fun write(event: JSONObject) {
        val now = System.currentTimeMillis()
        writer.execute {
            runCatching {
                val d = dir ?: return@execute
                d.mkdirs()
                val current = File(d, "knock.log")
                if (current.length() > MAX_FILE_BYTES) {
                    val old = File(d, "knock.old.log")
                    old.delete()
                    current.renameTo(old)
                }
                event.put("ts", time.format(Date(now)))
                current.appendText("$event\n")
            }
        }
    }

    /// Everything recorded, oldest first (waits for queued writes). Null if there is nothing.
    fun export(): ByteArray? = writer.submit<ByteArray?> {
        val d = dir ?: return@submit null
        val bytes = listOf("knock.old.log", "knock.log")
            .map { File(d, it) }
            .filter { it.exists() }
            .fold(ByteArray(0)) { all, f -> all + f.readBytes() }
        if (bytes.isEmpty()) null else bytes
    }.get()
}
