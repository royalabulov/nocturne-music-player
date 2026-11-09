package com.nocturne

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/// Keeps what Dart would talk to, by channel name.
private class Messenger : BinaryMessenger {
    val handlers = HashMap<String, BinaryMessenger.BinaryMessageHandler?>()

    override fun send(channel: String, message: ByteBuffer?) {}
    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}
    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        handlers[channel] = handler
    }

    /// Calls [method] on [channel] like Dart; the decoded answer, or the error code.
    fun call(channel: String, method: String, args: Any? = null): Any? {
        var answer: Any? = "no answer"
        val handler = handlers[channel] ?: return "no channel"
        handler.onMessage(StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, args)).apply { rewind() }) { reply ->
            answer = runCatching { StandardMethodCodec.INSTANCE.decodeEnvelope(reply!!.apply { rewind() }) }
                .fold({ it }, { (it as io.flutter.plugin.common.FlutterException).code })
        }
        return answer
    }
}

/// audio_service starts the Flutter engine with no window when a Bluetooth button wakes the
/// closed app. The channels used to be set up by the window, so scan, analysis and pocket
/// knock found nothing, and the analysis recorded every waiting song as failed.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class EngineChannelsTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val messenger = Messenger()

    @After
    fun tearDown() = EngineChannels.detach()

    @Test
    fun `an engine with no window gets every channel`() {
        EngineChannels.activity = null
        EngineChannels.attach(context, messenger)
        for (name in listOf(
            "com.nocturne/media_store",
            "com.nocturne/audio_analysis",
            "com.nocturne/knock",
            "com.nocturne/playback_service",
        )) {
            assertTrue(name, messenger.handlers[name] != null)
        }
    }

    @Test
    fun `deleting needs the window and says so`() {
        EngineChannels.activity = null
        EngineChannels.attach(context, messenger)
        assertEquals(CALL_FAILED, messenger.call("com.nocturne/media_store", "deleteAudio", mapOf("path" to "/m/a.mp3")))
    }

    @Test
    fun `files handed over before Dart asked are given once`() {
        EngineChannels.attach(context, messenger)
        OpenedFiles.add(listOf("content://a/1", "content://a/2"))
        assertEquals(listOf("content://a/1", "content://a/2"), messenger.call("com.nocturne/media_store", "takeOpenedUris"))
        assertEquals(emptyList<String>(), messenger.call("com.nocturne/media_store", "takeOpenedUris"))
    }

    @Test
    fun `the playback service calls answer even before the service exists`() {
        EngineChannels.attach(context, messenger)
        assertEquals(false, messenger.call("com.nocturne/playback_service", "paused"))
        assertEquals(false, messenger.call("com.nocturne/playback_service", "stopped"))
    }
}
