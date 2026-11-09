package com.nocturne

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.PlaybackServiceControl
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// The app's channels, set up on the Flutter engine itself (see EngineHookPlugin), so they
/// work with no window too: audio_service starts the engine without the activity when a
/// Bluetooth button wakes the closed app. Only deleting (a system dialog) and the files
/// handed over by "Open with" need the activity; [activity] answers those.
class EngineChannels(private val context: Context, messenger: BinaryMessenger) {
    private val library = MediaLibrary(context)
    private val importer = AudioImporter(context)
    private val analyzer = AudioAnalyzer(context)
    private val media = MethodChannel(messenger, "com.nocturne/media_store")

    /// Tells Dart when a new song lands on the phone (download, copy). The Dart side collects
    /// the events (debounce) and runs one scan.
    private val audioObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            media.invokeMethod("mediaChanged", null)
        }
    }

    init {
        media.setMethodCallHandler(::onMediaCall)
        context.contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, true, audioObserver
        )
        setUpAnalysisChannel(messenger)
        setUpKnockChannel(messenger)
        setUpServiceChannel(messenger)
    }

    fun close() {
        context.contentResolver.unregisterContentObserver(audioObserver)
        analyzer.close()
    }

    /// "Open with" brought new files while the app runs.
    fun openedFilesArrived() = media.invokeMethod("openedUrisAvailable", null)

    private fun onMediaCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Every song on the phone: a big library or a MediaStore busy re-indexing after an
            // update takes long enough to freeze the screen (Dart shares this thread)
            "queryAudio" -> background(result) { library.queryAudio() }
            "mediaGeneration" -> background(result) { library.generation() }
            "scanFiles" -> {
                library.scan(call.argument<List<String>>("paths") ?: emptyList())
                result.success(null)
            }
            "scanFilesAndWait" -> library.scanAndWait(call.argument<List<String>>("paths") ?: emptyList()) {
                result.success(null)
            }
            "takeOpenedUris" -> result.success(OpenedFiles.take())
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
            "deleteAudio", "deleteAudioBatch" -> {
                val window = activity
                if (window == null) result.fail("no window") else window.onDeleteCall(call, result)
            }
            else -> result.notImplemented()
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

    /// Pocket knock. The detector is a process-wide object: it keeps going when the window
    /// is gone, as long as the engine lives.
    private fun setUpKnockChannel(messenger: BinaryMessenger) {
        val knock = MethodChannel(messenger, "com.nocturne/knock")
        KnockDetector.init(context)
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

    /// The playback service lets go of the CPU while nothing plays (see PlaybackServiceControl).
    private fun setUpServiceChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.nocturne/playback_service").setMethodCallHandler { call, result ->
            when (call.method) {
                "paused" -> result.success(PlaybackServiceControl.paused())
                "stopped" -> result.success(PlaybackServiceControl.stopped())
                "equalizerWorks" -> background(result) { EqualizerProbe.works(context) }
                else -> result.notImplemented()
            }
        }
    }

    /// What only the window can do. Set while MainActivity exists.
    interface Window {
        fun onDeleteCall(call: MethodCall, result: MethodChannel.Result)
    }

    companion object {
        /// The engine's channels; null before the engine exists and after it is gone.
        var current: EngineChannels? = null
            private set
        var activity: Window? = null

        /// A Flutter engine was made (EngineHookPlugin): with a window or without one.
        fun attach(context: Context, messenger: BinaryMessenger) {
            current?.close()
            current = EngineChannels(context, messenger)
        }

        fun detach() {
            current?.close()
            current = null
        }
    }
}

/// Files that arrived via "Open with Nocturne" / Share, kept until Dart picks them up.
/// Process-wide, so a file is not lost when the window is recreated before Dart asks.
object OpenedFiles {
    private val uris = ArrayList<String>()

    val count: Int
        @Synchronized get() = uris.size

    @Synchronized
    fun add(list: List<String>) {
        uris.addAll(list)
    }

    @Synchronized
    fun take(): List<String> = ArrayList(uris).also { uris.clear() }
}
