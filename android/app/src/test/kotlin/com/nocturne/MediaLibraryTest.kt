package com.nocturne

import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class MediaLibraryTest {
    @Test
    fun `voice recordings stay out where the system can tell them apart`() {
        val selection = MediaLibrary.audioSelection(Build.VERSION_CODES.S)
        assertTrue(selection, selection.endsWith("AND is_recording = 0"))
    }

    /// Without the brackets the AND would bind only to the length check, and recordings marked
    /// as music would come back.
    @Test
    fun `the songs part is kept together`() {
        assertEquals(
            "(is_music != 0 OR duration > 30000) AND is_recording = 0",
            MediaLibrary.audioSelection(Build.VERSION_CODES.TIRAMISU),
        )
    }

    /// The column doesn't exist there: asking for it would fail the whole scan.
    @Test
    fun `older Android is not asked about a column it doesn't have`() {
        val selection = MediaLibrary.audioSelection(Build.VERSION_CODES.R)
        assertFalse(selection, selection.contains("is_recording"))
        assertEquals("is_music != 0 OR duration > 30000", selection)
    }
}
