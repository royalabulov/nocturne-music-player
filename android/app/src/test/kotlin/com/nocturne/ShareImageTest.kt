package com.nocturne

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/// Wrapped's card goes to the share sheet as a picture the receiving app may read.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShareImageTest {
    @Test
    fun `the picture goes along with a read permission for that one picture`() {
        val uri = Uri.parse("content://media/external/images/media/42")
        val chooser = ShareImage.chooser(uri, "November 2026")
        val send = chooser.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)!!

        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("image/png", send.type)
        assertEquals(uri, send.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
        assertEquals(uri, send.clipData!!.getItemAt(0).uri)
        assertTrue(send.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertTrue(chooser.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }
}
