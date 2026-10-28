package com.royal.sonar

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.IntentSender
import android.database.ContentObserver
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.royal.sonar/media_store"
    private val deleteRequestCode = 4711
    private var pendingDelete: MethodChannel.Result? = null
    private var pendingDeletePath: String? = null
    private var pendingBatchPaths: List<String>? = null

    /// Files arriving via "Open with Nocturne" / Share — kept until Dart picks them up.
    private val openedUris = ArrayList<String>()
    private var channel: MethodChannel? = null
    private val importer by lazy { AudioImporter(applicationContext) }
    private val analyzer by lazy { AudioAnalyzer(applicationContext) }

    /// Tells Dart when a new song lands on the phone while the app is open (download, copy).
    /// The Dart side collects the events (debounce) and runs one scan.
    private val audioObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            channel?.invokeMethod("mediaChanged", null)
        }
    }

    override fun onDestroy() {
        contentResolver.unregisterContentObserver(audioObserver)
        analyzer.close()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, audioObserver
        )
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "queryAudio" -> result.success(queryAudio())
                    "scanFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        MediaScannerConnection.scanFile(
                            applicationContext, paths.toTypedArray(), null, null
                        )
                        result.success(null)
                    }
                    "deleteAudio" -> {
                        val path = call.argument<String>("path")
                        if (path == null) result.success("error: no path") else deleteAudio(path, result)
                    }
                    "deleteAudioBatch" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        deleteAudioBatch(paths, result)
                    }
                    "scanFilesAndWait" -> {
                        // Wait for MediaScanner to finish (max 5 s) — so the following
                        // MediaStore enumerate sees the new file
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        if (paths.isEmpty()) { result.success(null); return@setMethodCallHandler }
                        val left = java.util.concurrent.atomic.AtomicInteger(paths.size)
                        val done = java.util.concurrent.atomic.AtomicBoolean(false)
                        val finish = { if (done.compareAndSet(false, true)) runOnUiThread { result.success(null) } }
                        MediaScannerConnection.scanFile(applicationContext, paths.toTypedArray(), null) { _, _ ->
                            if (left.decrementAndGet() == 0) finish()
                        }
                        android.os.Handler(mainLooper).postDelayed({ finish() }, 5000)
                    }
                    "takeOpenedUris" -> {
                        result.success(ArrayList(openedUris))
                        openedUris.clear()
                    }
                    "resolveAudio" -> background(result) {
                        val i = importer.resolve(call.argument<String>("source")!!)
                        mapOf("path" to i.path, "name" to i.name, "size" to i.size)
                    }
                    "importAudio" -> background(result) {
                        importer.import(call.argument<String>("source")!!)
                    }
                    // Export file goes straight to Download without a dialog (MediaStore)
                    "saveToDownloads" -> background(result) {
                        saveToDownloads(
                            call.argument<String>("name")!!,
                            call.argument<String>("mime")!!,
                            call.argument<ByteArray>("bytes")!!,
                        )
                    }
                    // Smart groups: YAMNet analysis of one song (~0.2–0.5 s, on a background thread)
                    "analyzeAudio" -> background(result) {
                        analyzer.analyze(
                            call.argument<String>("path")!!,
                            call.argument<Number>("durationMs")?.toLong() ?: 0L,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── open with / share ─────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // On recreate (rotation etc.) don't handle the same intent twice
        if (savedInstanceState == null) collectOpened(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (collectOpened(intent)) channel?.invokeMethod("openedUrisAvailable", null)
    }

    /// VIEW (tap a file → "Open with") and SEND/SEND_MULTIPLE (Share) URIs.
    private fun collectOpened(intent: Intent?): Boolean {
        if (intent == null) return false
        val uris = ArrayList<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            Intent.ACTION_SEND -> streamExtra(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent)?.let { uris.addAll(it) }
        }
        if (uris.isEmpty()) return false
        openedUris.addAll(uris.map { it.toString() })
        // Handle it once (so it doesn't come back when the app is reopened)
        intent.action = Intent.ACTION_MAIN
        return true
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(i: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(i: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableArrayListExtra(Intent.EXTRA_STREAM)

    /// File copying must not block the UI thread; errors go to Dart as "error: ...".
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            val out = try {
                work()
            } catch (e: Exception) {
                "error: ${e.javaClass.simpleName}: ${e.message}"
            }
            runOnUiThread { result.success(out) }
        }.start()
    }

    /// Writes a file to the shared Download folder; result: the visible path ("Download/name.csv").
    /// Android 10+: MediaStore.Downloads (no permission needed); older versions write the file directly.
    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("MediaStore insert failed")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return "Download/$name"
        }
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        val f = File(dir, name)
        f.writeBytes(bytes)
        return f.path
    }

    /// path + size + dateModified of every audio file in MediaStore.
    /// Tags aren't read here — the Dart side does that (audio_metadata_reader).
    private fun queryAudio(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.DURATION,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 OR ${MediaStore.Audio.Media.DURATION} > 30000"
        val cursor = contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection, selection, null, null
        ) ?: return out
        cursor.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val dataCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val modCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            val durCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            while (c.moveToNext()) {
                val path = c.getString(dataCol) ?: continue
                val id = c.getLong(idCol)
                out.add(
                    mapOf(
                        "path" to path,
                        "uri" to ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                        ).toString(),
                        "size" to c.getLong(sizeCol),
                        "dateModified" to c.getLong(modCol) * 1000, // sec → ms
                        "durationMs" to c.getLong(durCol),
                    )
                )
            }
        }
        return out
    }

    // ── delete ────────────────────────────────────────────────

    /// Delete a file from the phone. Scoped storage (Android 10+): a file written by
    /// another app (Snaptube, Telegram) can't be deleted directly → MediaStore
    /// delete request — the system shows a one-time confirmation dialog.
    ///
    /// Result (String, Dart writes it to the error log):
    /// "deleted" | "cancelled" | "error: <reason>". Never throws, and
    /// result is always answered (before, some paths silently returned false).
    private fun deleteAudio(path: String, result: MethodChannel.Result) {
        if (pendingDelete != null) {
            result.success("error: another delete is waiting for confirmation")
            return
        }
        try {
            val f = File(path)
            val uri = mediaStoreUriFor(path)
            if (uri != null) {
                deleteUri(uri, path, result)
                return
            }
            if (!f.exists()) {
                result.success("deleted")
                return
            }
            // MediaStore doesn't know this file (found by the folder walk) →
            // index it to get a URI, then delete the normal way.
            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null) { _, scanned ->
                runOnUiThread {
                    when {
                        scanned != null -> deleteUri(scanned, path, result)
                        f.delete() -> result.success("deleted")
                        else -> result.success("error: file is not in MediaStore and cannot be deleted")
                    }
                }
            }
        } catch (e: Exception) {
            result.success("error: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun deleteUri(uri: Uri, path: String, result: MethodChannel.Result) {
        try {
            // 1) Try without a dialog: works for our own files, otherwise SecurityException
            try {
                if (contentResolver.delete(uri, null, null) > 0 && !File(path).exists()) {
                    result.success("deleted")
                    return
                }
            } catch (e: SecurityException) {
                // 2) Android 10: ask the user for permission
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                    askUser(e.userAction.actionIntent.intentSender, path, result)
                    return
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.success("error: ${e.message}")
                    return
                }
            }
            // 3) Android 11+: system confirmation dialog ("Allow Nocturne to delete this file?")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pi = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                askUser(pi.intentSender, path, result)
                return
            }
            result.success(if (File(path).delete() || !File(path).exists()) "deleted" else "error: delete refused")
        } catch (e: Exception) {
            result.success("error: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    /// Bulk delete. Result map: status ("deleted" | "cancelled" |
    /// "unsupported" | "error: ...") + deleted (paths actually deleted).
    /// Android 11+: our own files without a dialog, the rest in **one** system
    /// dialog. Android 10 and older: "unsupported" → Dart deletes each file separately.
    private fun deleteAudioBatch(paths: List<String>, result: MethodChannel.Result) {
        val done = ArrayList<String>()
        if (pendingDelete != null) {
            result.success(mapOf("status" to "error: another delete is waiting for confirmation", "deleted" to done))
            return
        }
        try {
            val uris = ArrayList<Uri>()
            for (p in paths) {
                val uri = mediaStoreUriFor(p)
                if (uri == null) {
                    val f = File(p)
                    if (!f.exists() || f.delete()) done.add(p)
                    continue
                }
                val direct = try {
                    contentResolver.delete(uri, null, null) > 0 && !File(p).exists()
                } catch (e: SecurityException) {
                    false
                }
                if (direct) done.add(p) else uris.add(uri)
            }
            if (uris.isEmpty()) {
                result.success(mapOf("status" to "deleted", "deleted" to done))
                return
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                result.success(mapOf("status" to "unsupported", "deleted" to done))
                return
            }
            val pi = MediaStore.createDeleteRequest(contentResolver, uris)
            pendingBatchPaths = paths
            askUser(pi.intentSender, null, result)
        } catch (e: Exception) {
            pendingBatchPaths = null
            result.success(mapOf("status" to "error: ${e.javaClass.simpleName}: ${e.message}", "deleted" to done))
        }
    }

    private fun askUser(sender: IntentSender, path: String?, result: MethodChannel.Result) {
        pendingDelete = result
        pendingDeletePath = path
        try {
            startIntentSenderForResult(sender, deleteRequestCode, null, 0, 0, 0)
        } catch (e: Exception) {
            pendingDelete = null
            pendingDeletePath = null
            val msg = "error: could not open system dialog: ${e.message}"
            if (pendingBatchPaths != null) {
                pendingBatchPaths = null
                result.success(mapOf("status" to msg, "deleted" to emptyList<String>()))
            } else {
                result.success(msg)
            }
        }
    }

    private fun mediaStoreUriFor(path: String): Uri? {
        val cursor = contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Audio.Media._ID),
            "${MediaStore.Audio.Media.DATA} = ?",
            arrayOf(path),
            null,
        ) ?: return null
        cursor.use { c ->
            if (!c.moveToFirst()) return null
            return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, c.getLong(0))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == deleteRequestCode && pendingBatchPaths != null) {
            val paths = pendingBatchPaths!!
            val deleted = paths.filter { !File(it).exists() }
            val status = if (resultCode == Activity.RESULT_OK) "deleted" else "cancelled"
            pendingDelete?.success(mapOf("status" to status, "deleted" to deleted))
            pendingDelete = null
            pendingBatchPaths = null
            return
        }
        if (requestCode == deleteRequestCode) {
            val path = pendingDeletePath
            val status = when {
                resultCode != Activity.RESULT_OK -> "cancelled"
                path != null && File(path).exists() -> "error: system approved but the file still exists"
                else -> "deleted"
            }
            pendingDelete?.success(status)
            pendingDelete = null
            pendingDeletePath = null
        }
    }
}
