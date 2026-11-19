package com.ryanheise.audioservice

import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import androidx.media.MediaBrowserServiceCompat

/// Android Auto browses the library through audio_service's MediaBrowserService, and that
/// service is exported: any app on the phone could connect and read the playlists, the
/// favorites and what was played recently. audio_service answers every caller and gives Dart
/// no way to tell who asks, so the plugin's listener is wrapped here: browsing answers only
/// the callers that need it (Android Auto and the car, the system's media controls and
/// Assistant, Bluetooth, this app), everyone else gets an empty list. Playback controls
/// through the media session are not touched.
///
/// In the plugin's package and by the field's name ("listener", private): a plugin update that
/// renames it makes [install] return false, and browsing stays answered by no one but this app's
/// own connection — closed, not open (BrowseGuardTest).
object BrowseGuard {
    /// Packages allowed to browse, besides this app.
    val ALLOWED = setOf(
        "com.google.android.projection.gearhead", // Android Auto
        "com.google.android.carassistant", // Android Auto's Assistant
        "com.google.android.googlequicksearchbox", // Assistant ("play … on Nocturne")
        "com.android.car.media", // Android Automotive
        "com.android.systemui", // media controls, resuming the last song
        "com.android.bluetooth", // car stereos browsing over Bluetooth
        "com.google.android.bluetooth",
    )

    /// Whether [caller] may browse; null (not known) may not.
    fun allows(caller: String?, ownPackage: String): Boolean = caller != null && (caller == ownPackage || caller in ALLOWED)

    /// The plugin's field this wraps; null when a plugin update renamed or removed it.
    internal fun listenerField() = runCatching {
        AudioService::class.java.getDeclaredField("listener").apply { isAccessible = true }
    }.getOrNull()

    /// Wraps the plugin's listener once it is set (after AudioService.init on the Dart side).
    /// False when there is none yet or the field can't be reached.
    fun install(ownPackage: String): Boolean = runCatching {
        val field = listenerField() ?: return false
        when (val current = field.get(null)) {
            is Guarded -> true
            is AudioService.ServiceListener -> {
                AudioService.init(Guarded(current, ownPackage) { AudioService.instance?.currentBrowserInfo?.packageName })
                true
            }
            else -> false
        }
    }.getOrDefault(false)

    /// [caller]: the package browsing now (MediaBrowserServiceCompat knows it only during the
    /// call).
    class Guarded(
        private val inner: AudioService.ServiceListener,
        private val ownPackage: String,
        private val caller: () -> String?,
    ) : AudioService.ServiceListener by inner {
        private fun allowed(): Boolean = allows(caller(), ownPackage)

        override fun onLoadChildren(
            parentMediaId: String,
            result: MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>>,
            options: Bundle?,
        ) {
            if (allowed()) inner.onLoadChildren(parentMediaId, result, options) else result.sendResult(ArrayList())
        }

        override fun onLoadItem(itemId: String, result: MediaBrowserServiceCompat.Result<MediaBrowserCompat.MediaItem>) {
            if (allowed()) inner.onLoadItem(itemId, result) else result.sendResult(null)
        }

        override fun onSearch(
            query: String,
            extras: Bundle?,
            result: MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>>,
        ) {
            if (allowed()) inner.onSearch(query, extras, result) else result.sendResult(ArrayList())
        }
    }
}
