package com.nocturne

import android.provider.MediaStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream

/// Exports (CSV, knock log) go to Download through MediaStore: a pending row first, then the
/// bytes, then the row is published.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class MediaLibraryDownloadsTest {
    private val context get() = RuntimeEnvironment.getApplication()

    @Before
    fun setUp() {
        FakeMediaProvider.reset()
        Robolectric.setupContentProvider(FakeMediaProvider::class.java, MediaStore.AUTHORITY)
    }

    private fun writesGoTo(stream: OutputStream) =
        shadowOf(context.contentResolver).registerOutputStream(FakeMediaProvider.row, stream)

    @Test
    fun `an export is written and then published`() {
        val written = ByteArrayOutputStream()
        writesGoTo(written)

        val path = MediaLibrary(context).saveToDownloads("vibes.csv", "text/csv", "a,b".toByteArray())

        assertEquals("Download/vibes.csv", path)
        assertEquals("a,b", written.toString())
        assertEquals(0, FakeMediaProvider.updated.single().getAsInteger(MediaStore.Downloads.IS_PENDING))
        assertTrue(FakeMediaProvider.deleted.isEmpty())
    }

    @Test
    fun `a failed write removes the half-created entry`() {
        writesGoTo(object : OutputStream() {
            override fun write(b: Int): Unit = throw IOException("disk full")
        })

        assertThrows(IOException::class.java) {
            MediaLibrary(context).saveToDownloads("vibes.csv", "text/csv", "a,b".toByteArray())
        }

        assertEquals(listOf(FakeMediaProvider.row), FakeMediaProvider.deleted)
        assertTrue(FakeMediaProvider.updated.isEmpty())
    }
}
