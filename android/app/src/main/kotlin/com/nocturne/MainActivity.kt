package com.nocturne

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// The window. The channels live on the engine (EngineChannels), which can run without it;
/// the activity adds only what needs a window: the delete dialog and "Open with" / Share.
class MainActivity : AudioServiceActivity(), EngineChannels.Window {
    private val deleter by lazy { AudioDeleter(this) }

    override fun onDeleteCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deleteAudio" -> {
                val path = call.argument<String>("path")
                if (path == null) result.fail("no path") else deleter.delete(path, result)
            }
            "deleteAudioBatch" -> deleter.deleteBatch(call.argument<List<String>>("paths") ?: emptyList(), result)
            else -> result.notImplemented()
        }
    }

    override fun onDestroy() {
        // Recreated (not finishing): the dialog's answer comes to the new activity instead
        if (isFinishing) AudioDeleter.abandon()
        if (EngineChannels.activity === this) EngineChannels.activity = null
        super.onDestroy()
    }

    // ── open with / share ─────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        IncomingUriPolicy.dropUnreadableExtras(intent)
        EngineChannels.activity = this
        super.onCreate(savedInstanceState)
        // On recreate (rotation etc.) don't handle the same intent twice
        if (savedInstanceState == null) collectOpened(intent)
    }

    override fun onNewIntent(intent: Intent) {
        IncomingUriPolicy.dropUnreadableExtras(intent)
        super.onNewIntent(intent)
        setIntent(intent)
        if (collectOpened(intent)) EngineChannels.current?.openedFilesArrived()
    }

    /// VIEW (tap a file → "Open with") and SEND/SEND_MULTIPLE (Share) URIs.
    private fun collectOpened(intent: Intent?): Boolean {
        if (intent == null) return false
        val safe = IncomingUriPolicy.accept(IncomingUriPolicy.urisOf(intent), packageName, pending = OpenedFiles.count)
        if (safe.isEmpty()) return false
        OpenedFiles.add(safe.map { it.toString() })
        // Handle it once (so it doesn't come back when the app is reopened)
        intent.action = Intent.ACTION_MAIN
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        deleter.onActivityResult(requestCode, resultCode)
    }
}
