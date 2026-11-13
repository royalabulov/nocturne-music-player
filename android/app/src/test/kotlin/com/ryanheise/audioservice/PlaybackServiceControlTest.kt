package com.ryanheise.audioservice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import org.robolectric.RuntimeEnvironment
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/// After Stop the notification stayed and the CPU was kept awake; while paused the wake lock
/// was held the whole time (seen on the phone: 6+ minutes with nothing playing).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlaybackServiceControlTest {
    private val context: Context = RuntimeEnvironment.getApplication()

    /// The service as the plugin leaves it while playing: in the foreground, holding its wake
    /// lock. Not created (onCreate starts a Flutter engine), only given the two things.
    private fun playingService(): Pair<AudioService, PowerManager.WakeLock> {
        val service = Robolectric.buildService(AudioService::class.java).get()
        val lock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "test")
        lock.acquire()
        AudioService::class.java.getDeclaredField("wakeLock").apply { isAccessible = true }.set(service, lock)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("t", "t", NotificationManager.IMPORTANCE_LOW))
        val n: Notification = NotificationCompat.Builder(context, "t").setSmallIcon(android.R.drawable.ic_media_play).build()
        service.startForeground(1124, n)
        return service to lock
    }

    @Test
    fun `the plugin still has the wake lock this releases`() {
        val service = Robolectric.buildService(AudioService::class.java).get()
        assertNotNull(AudioService::class.java.getDeclaredField("wakeLock"))
        // Not made yet (onCreate makes it): no crash, nothing to release
        assertFalse(PlaybackServiceControl.paused(service))
    }

    @Test
    fun `paused lets the CPU sleep and keeps the notification`() {
        val (service, lock) = playingService()
        assertTrue(PlaybackServiceControl.paused(service))
        assertFalse(lock.isHeld)
        assertFalse(shadowOf(service).isForegroundStopped)
    }

    @Test
    fun `stopped takes the service out of the foreground and removes the notification`() {
        val (service, lock) = playingService()
        assertTrue(PlaybackServiceControl.stopped(service))
        assertFalse(lock.isHeld)
        assertTrue(shadowOf(service).isForegroundStopped)
        assertTrue(shadowOf(service).notificationShouldRemoved)
    }

    @Test
    fun `no service, nothing to do`() {
        assertFalse(PlaybackServiceControl.paused(null))
        assertFalse(PlaybackServiceControl.stopped(null))
    }
}
