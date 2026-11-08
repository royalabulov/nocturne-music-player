package com.nocturne

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Parcel
import android.os.Parcelable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/// Any installed app can send our activity any intent, without a permission and without anyone
/// noticing. A value of the wrong type used to crash the app and stop the music.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 34], manifest = Config.NONE)
class IncomingIntentTest {
    private val song = Uri.parse("content://com.other.app/1")
    private val other = Uri.parse("content://com.other.app/2")

    private fun send() = Intent(Intent.ACTION_SEND)
    private fun sendMany() = Intent(Intent.ACTION_SEND_MULTIPLE)

    @Test
    fun `the three ways a file arrives`() {
        assertEquals(listOf(song), IncomingUriPolicy.urisOf(Intent(Intent.ACTION_VIEW, song)))
        assertEquals(listOf(song), IncomingUriPolicy.urisOf(send().putExtra(Intent.EXTRA_STREAM, song)))
        assertEquals(
            listOf(song, other),
            IncomingUriPolicy.urisOf(sendMany().putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(song, other))),
        )
    }

    @Test
    fun `an intent that brings nothing`() {
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(Intent(Intent.ACTION_VIEW)))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(send()))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(sendMany()))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(Intent(Intent.ACTION_MAIN)))
    }

    @Test
    fun `one value of the wrong type is no file`() {
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(send().putExtra(Intent.EXTRA_STREAM, Bundle())))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(send().putExtra(Intent.EXTRA_STREAM, "text")))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(send().putExtra(Intent.EXTRA_STREAM, 42)))
    }

    @Test
    fun `a list of the wrong type is no file`() {
        assertEquals(
            emptyList<Uri>(),
            IncomingUriPolicy.urisOf(sendMany().putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(Bundle()))),
        )
        assertEquals(
            emptyList<Uri>(),
            IncomingUriPolicy.urisOf(sendMany().putStringArrayListExtra(Intent.EXTRA_STREAM, arrayListOf("a", "b"))),
        )
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(sendMany().putExtra(Intent.EXTRA_STREAM, song)))
    }

    @Test
    fun `from a mixed list the real files are kept`() {
        val mixed = arrayListOf<Parcelable>(song, Bundle(), other)
        assertEquals(
            listOf(song, other),
            IncomingUriPolicy.urisOf(sendMany().putParcelableArrayListExtra(Intent.EXTRA_STREAM, mixed)),
        )
    }

    // ── a value this app has no class for ─────────────────────

    /// Written by "another app": here, a class that the loader reading it can't find.
    class Foreign : Parcelable {
        override fun describeContents() = 0
        override fun writeToParcel(dest: Parcel, flags: Int) = Unit
    }

    private fun unreadable(action: String): Intent {
        val written = Bundle().apply { putParcelable(Intent.EXTRA_STREAM, Foreign()) }
        val parcel = Parcel.obtain()
        written.writeToParcel(parcel, 0)
        parcel.setDataPosition(0)
        val received = Bundle().apply { readFromParcel(parcel) }
        parcel.recycle()
        return Intent(action).apply {
            replaceExtras(received)
            setExtrasClassLoader(object : ClassLoader(null) {})
        }
    }

    /// Otherwise the tests below would prove nothing.
    @Test
    @Suppress("DEPRECATION")
    fun `this value really can't be read`() {
        val intent = unreadable(Intent.ACTION_SEND)
        assertTrue(runCatching { intent.getParcelableExtra<Parcelable>(Intent.EXTRA_STREAM) }.isFailure)
    }

    @Test
    fun `reading an unreadable value is no file`() {
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(unreadable(Intent.ACTION_SEND)))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(unreadable(Intent.ACTION_SEND_MULTIPLE)))
    }

    @Test
    fun `extras nobody can read are dropped before the activity looks at them`() {
        val intent = unreadable(Intent.ACTION_SEND)
        IncomingUriPolicy.dropUnreadableExtras(intent)
        assertFalse(intent.hasExtra("anything"))
        assertEquals(emptyList<Uri>(), IncomingUriPolicy.urisOf(intent))
    }

    @Test
    fun `extras that can be read stay where they are`() {
        val intent = send().putExtra(Intent.EXTRA_STREAM, song).putExtra("other", "x")
        IncomingUriPolicy.dropUnreadableExtras(intent)
        assertTrue(intent.hasExtra("other"))
        assertEquals(listOf(song), IncomingUriPolicy.urisOf(intent))
    }

    @Test
    fun `no intent at all`() {
        IncomingUriPolicy.dropUnreadableExtras(null)
    }
}
