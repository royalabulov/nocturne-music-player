package com.nocturne

import android.database.MatrixCursor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/// Returning to the app scans only when the songs changed. Android 10 has no generations:
/// null there, so the Dart side scans every time, as before.
@RunWith(RobolectricTestRunner::class)
class MediaGenerationTest {
    @Test
    @Config(sdk = [29])
    fun `Android 10 has no counter, so the answer is unknown`() {
        assertNull(MediaLibrary(RuntimeEnvironment.getApplication()).generation())
    }

    /// (generation added, generation modified) per song.
    private fun stamp(vararg songs: Pair<Long, Long>) = MediaLibrary.songsStamp(
        "external_primary",
        MatrixCursor(arrayOf("generation_added", "generation_modified")).apply {
            for ((added, modified) in songs) addRow(arrayOf(added, modified))
        },
    )

    private val library = arrayOf(10L to 10L, 20L to 25L, 30L to 30L)

    @Test
    fun `the same songs give the same answer`() {
        assertEquals(stamp(*library), stamp(*library))
    }

    @Test
    fun `a new song, a changed song and a removed song each change it`() {
        val before = stamp(*library)
        assertNotEquals(before, stamp(*library, 40L to 40L))
        assertNotEquals(before, stamp(10L to 10L, 20L to 41L, 30L to 30L))
        assertNotEquals(before, stamp(10L to 10L, 30L to 30L))
    }

    /// The newest song removed and another added in its place: same count, newer "added".
    @Test
    fun `a song swapped for another still changes it`() {
        assertNotEquals(stamp(*library), stamp(10L to 10L, 20L to 25L, 31L to 31L))
    }
}
