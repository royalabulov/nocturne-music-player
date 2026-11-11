package com.nocturne

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/// Before this the error log could only be copied: a user who hit a bug had no plain way to
/// send it, and Dart errors never reach Play's crash reports.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class ShareTextTest {
    @Suppress("DEPRECATION")
    private fun inner(chooser: Intent): Intent = chooser.getParcelableExtra(Intent.EXTRA_INTENT)!!

    @Test
    fun `the share sheet carries the log as text`() {
        val chooser = ShareText.chooser("line 1\nline 2", "Nocturne error log")
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        val send = inner(chooser)
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("text/plain", send.type)
        assertEquals("line 1\nline 2", send.getStringExtra(Intent.EXTRA_TEXT))
        assertEquals("Nocturne error log", send.getStringExtra(Intent.EXTRA_SUBJECT))
    }

    /// The engine's context may not be an Activity: without NEW_TASK startActivity throws
    @Test
    fun `it can be started from a context that is not an Activity`() {
        val chooser = ShareText.chooser("x", "t")
        assertTrue(chooser.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }

    /// A log near 1 MB made the Intent too big for the system to take
    @Test
    fun `a long log keeps its newest part`() {
        val text = "old".repeat(50_000) + "NEWEST"
        val sent = inner(ShareText.chooser(text, "t")).getStringExtra(Intent.EXTRA_TEXT)!!
        assertEquals(ShareText.MAX_CHARS, sent.length)
        assertTrue(sent.endsWith("NEWEST"))
    }

    @Test
    fun `the cut never starts in the middle of an emoji`() {
        // 100 002 chars: the plain cut would start on the second half of the first emoji
        val text = "x" + "😀".repeat(ShareText.MAX_CHARS / 2) + "y"
        val cut = ShareText.newest(text)
        assertTrue(!Character.isLowSurrogate(cut[0]))
        assertEquals(ShareText.MAX_CHARS - 1, cut.length)
    }
}
