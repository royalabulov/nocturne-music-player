package com.nocturne

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import android.os.Looper

private class Answer : MethodChannel.Result {
    var value: Any? = null
    var code: String? = null
    var reason: String? = null
    var details: Any? = null
    var calls = 0

    override fun success(result: Any?) {
        calls++
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        calls++
        code = errorCode
        reason = errorMessage
        details = errorDetails
    }

    override fun notImplemented() {
        calls++
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NativeCallsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val activity: Activity = Robolectric.buildActivity(Activity::class.java).setup().get()

    @Test
    fun `background work that throws is an error, not a result`() {
        val answer = Answer()
        val done = java.util.concurrent.CountDownLatch(1)
        activity.background(answer) {
            done.countDown()
            error("disk full")
        }
        done.await()
        for (i in 0 until 50) {
            Thread.sleep(10)
            shadowOf(Looper.getMainLooper()).idle()
            if (answer.calls > 0) break
        }
        assertEquals(CALL_FAILED, answer.code)
        assertEquals("IllegalStateException: disk full", answer.reason)
        assertNull(answer.value)
    }

    @Test
    fun `deleting a file that is already gone counts as deleted`() {
        val answer = Answer()
        AudioDeleter(activity).delete("/storage/emulated/0/Music/gone.mp3", answer)
        assertEquals("deleted", answer.value)
        assertEquals(1, answer.calls)
    }

    @Test
    fun `a batch reports the files it removed`() {
        val file = tmp.newFile("song.mp3")
        val answer = Answer()
        AudioDeleter(activity).deleteBatch(listOf(file.path), answer)
        assertEquals(mapOf("status" to "deleted", "deleted" to listOf(file.path)), answer.value)
        assertFalse(file.exists())
    }

    private fun dialog() = PendingIntent.getActivity(activity, 0, Intent(), PendingIntent.FLAG_IMMUTABLE).intentSender

    /// Android can recreate the activity while the system delete dialog is open: the answer
    /// then reaches a new activity with a new deleter, and the call must still be answered.
    @Test
    fun `the dialog's answer reaches the call even after the activity was recreated`() {
        val answer = Answer()
        AudioDeleter(activity).askUser(dialog(), "/storage/emulated/0/Music/gone.mp3", answer)
        assertEquals(0, answer.calls)

        val recreated = Robolectric.buildActivity(Activity::class.java).setup().get()
        AudioDeleter(recreated).onActivityResult(4711, Activity.RESULT_CANCELED)

        assertEquals("cancelled", answer.value)
        assertEquals(1, answer.calls)
    }

    @Test
    fun `an activity closing for good answers the waiting call, so the next delete isn't busy`() {
        val waiting = Answer()
        AudioDeleter(activity).askUser(dialog(), "/storage/emulated/0/Music/a.mp3", waiting)

        AudioDeleter.abandon()
        assertEquals("cancelled", waiting.value)

        val next = Answer()
        AudioDeleter(activity).delete("/storage/emulated/0/Music/gone.mp3", next)
        assertEquals("deleted", next.value)
    }

    @Test
    fun `a closed dialog nobody waits for answers nothing`() {
        AudioDeleter(activity).onActivityResult(4711, Activity.RESULT_OK)
        AudioDeleter(activity).onActivityResult(1, Activity.RESULT_OK)
    }
}
