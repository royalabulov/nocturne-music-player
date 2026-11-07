package com.nocturne

import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Connects the channels to the classes that do the work, and receives "Open with" / Share.
class MainActivity : AudioServiceActivity() {
    /// Files arriving via "Open with Nocturne" / Share — kept until Dart picks them up.
    private val openedUris = ArrayList<String>()
    private var channel: MethodChannel? = null
    private val library by lazy { MediaLibrary(applicationContext) }
    private val deleter by lazy { AudioDeleter(this) }
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
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        setUpMediaChannel(messenger)
        setUpAnalysisChannel(messenger)
        setUpKnockChannel(messenger)
    }

    private fun setUpMediaChannel(messenger: BinaryMessenger) {
        val media = MethodChannel(messenger, "com.nocturne/media_store")
        channel = media
        media.setMethodCallHandler { call, result ->
            when (call.method) {
                "queryAudio" -> result.success(library.queryAudio())
                "scanFiles" -> {
                    library.scan(call.argument<List<String>>("paths") ?: emptyList())
                    result.success(null)
                }
                "scanFilesAndWait" -> library.scanAndWait(call.argument<List<String>>("paths") ?: emptyList()) {
                    result.success(null)
                }
                "deleteAudio" -> {
                    val path = call.argument<String>("path")
                    if (path == null) result.fail("no path") else deleter.delete(path, result)
                }
                "deleteAudioBatch" -> deleter.deleteBatch(call.argument<List<String>>("paths") ?: emptyList(), result)
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
                    library.saveToDownloads(
                        call.argument<String>("name")!!,
                        call.argument<String>("mime")!!,
                        call.argument<ByteArray>("bytes")!!,
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Smart groups: YAMNet analysis of one song (~0.2–0.5 s, on a background thread).
    private fun setUpAnalysisChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.nocturne/audio_analysis").setMethodCallHandler { call, result ->
            when (call.method) {
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

    /// Pocket knock. The detector lives outside the activity (the audio_service engine
    /// keeps running when the activity is gone), so onDestroy doesn't stop it.
    private fun setUpKnockChannel(messenger: BinaryMessenger) {
        val knock = MethodChannel(messenger, "com.nocturne/knock")
        KnockDetector.init(applicationContext)
        KnockDetector.onKnock = { count -> knock.invokeMethod("knock", count) }
        knock.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    KnockDetector.update(
                        call.argument<Boolean>("on") ?: false,
                        call.argument<Int>("sensitivity") ?: 1,
                    )
                    result.success(null)
                }
                // Permanent knock log → Download folder. Null = nothing recorded yet.
                "exportLog" -> background(result) {
                    KnockLog.export()?.let {
                        library.saveToDownloads(call.argument<String>("name")!!, "text/plain", it)
                    }
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
        val safe = IncomingUriPolicy.accept(uris, packageName, pending = openedUris.size)
        if (safe.isEmpty()) return false
        openedUris.addAll(safe.map { it.toString() })
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        deleter.onActivityResult(requestCode, resultCode)
    }
}
