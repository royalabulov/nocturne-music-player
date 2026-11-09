package com.ryanheise.audioservice

import android.os.PowerManager
import android.util.Log
import androidx.core.app.ServiceCompat

/// What audio_service 0.18 doesn't do on its own with androidStopForegroundOnPause = false
/// (app_runner.dart says why it is off). It lets go of the foreground, the notification and
/// its wake lock only in AudioService.onDestroy, and the app's own MediaBrowser connection
/// keeps the service from being destroyed while the activity lives. So after Stop the
/// notification stayed with nothing playing, and the CPU was kept awake the whole time a
/// song sat paused.
///
/// In the plugin's package because AudioService.instance is package-private: a plugin update
/// that renames it fails the build instead of silently doing nothing.
object PlaybackServiceControl {
    private const val TAG = "PlaybackService"

    /// Paused, still in the foreground (so resuming after a call is allowed): the CPU may
    /// sleep. The plugin takes the wake lock again itself when playback starts.
    fun paused(): Boolean = paused(AudioService.instance)

    /// Stopped: out of the foreground, notification gone, wake lock released.
    fun stopped(): Boolean = stopped(AudioService.instance)

    internal fun paused(service: AudioService?): Boolean {
        if (service == null || service.isPlaying) return false
        return releaseWakeLock(service)
    }

    internal fun stopped(service: AudioService?): Boolean {
        if (service == null || service.isPlaying) return false
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
        releaseWakeLock(service)
        return true
    }

    /// The plugin keeps its wake lock private. Its name is kept through R8 by
    /// android/app/proguard-rules.pro, and PlaybackServiceControlTest fails if a new plugin
    /// version no longer has it.
    internal fun wakeLockOf(service: AudioService): PowerManager.WakeLock? =
        runCatching {
            AudioService::class.java.getDeclaredField("wakeLock").apply { isAccessible = true }.get(service)
                as PowerManager.WakeLock?
        }.onFailure { Log.w(TAG, "no wake lock field: $it") }.getOrNull()

    private fun releaseWakeLock(service: AudioService): Boolean {
        val lock = wakeLockOf(service) ?: return false
        if (lock.isHeld) lock.release()
        return true
    }
}
