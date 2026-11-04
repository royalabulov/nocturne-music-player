package com.nocturne

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream

/// Records what the importer asks of MediaStore (the path real phones take, Android 10+).
class FakeMediaProvider : ContentProvider() {
    companion object {
        val row: Uri = Uri.parse("content://media/external_primary/audio/media/1")
        const val PATH = "/storage/emulated/0/Music/Nocturne/song.mp3"

        val inserted = ArrayList<ContentValues>()
        val updated = ArrayList<ContentValues>()
        val deleted = ArrayList<Uri>()

        fun reset() {
            inserted.clear()
            updated.clear()
            deleted.clear()
        }
    }

    override fun onCreate() = true

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri {
        inserted.add(ContentValues(values))
        return row
    }

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int {
        updated.add(ContentValues(values))
        return 1
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        deleted.add(uri)
        return 1
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor = MatrixCursor(arrayOf(MediaStore.MediaColumns.DATA)).apply { addRow(arrayOf(PATH)) }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class AudioImporterMediaStoreTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val context get() = RuntimeEnvironment.getApplication()
    private val source = FakeAudioProvider.uri.toString()

    @Before
    fun setUp() {
        FakeMediaProvider.reset()
        FakeAudioProvider.reset(tmp.newFolder())
        Robolectric.setupContentProvider(FakeAudioProvider::class.java, FakeAudioProvider.AUTHORITY)
        Robolectric.setupContentProvider(FakeMediaProvider::class.java, MediaStore.AUTHORITY)
        FakeAudioProvider.columns = mapOf(OpenableColumns.DISPLAY_NAME to "song.mp3", OpenableColumns.SIZE to 4L)
        FakeAudioProvider.mime = "audio/flac"
        FakeAudioProvider.bytes = byteArrayOf(1, 2, 3, 4)
    }

    private fun writesGoTo(stream: OutputStream) =
        shadowOf(context.contentResolver).registerOutputStream(FakeMediaProvider.row, stream)

    @Test
    fun `import inserts a pending row in Music-Nocturne, writes, then publishes it`() {
        val written = ByteArrayOutputStream()
        writesGoTo(written)

        val path = AudioImporter(context).import(source)

        assertEquals(FakeMediaProvider.PATH, path)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), written.toByteArray())
        val row = FakeMediaProvider.inserted.single()
        assertEquals("song.mp3", row.getAsString(MediaStore.Audio.Media.DISPLAY_NAME))
        assertEquals("Music/Nocturne", row.getAsString(MediaStore.Audio.Media.RELATIVE_PATH))
        assertEquals("audio/flac", row.getAsString(MediaStore.Audio.Media.MIME_TYPE))
        assertEquals(1, row.getAsInteger(MediaStore.Audio.Media.IS_PENDING))
        assertEquals(0, FakeMediaProvider.updated.single().getAsInteger(MediaStore.Audio.Media.IS_PENDING))
        assertTrue(FakeMediaProvider.deleted.isEmpty())
    }

    @Test
    fun `a non-audio type from the provider is not stored as is`() {
        FakeAudioProvider.mime = "application/vnd.android.package-archive"
        writesGoTo(ByteArrayOutputStream())

        AudioImporter(context).import(source)

        assertTrue(FakeMediaProvider.inserted.single().getAsString(MediaStore.Audio.Media.MIME_TYPE).startsWith("audio/"))
    }

    @Test
    fun `a failed write removes the half-created row`() {
        writesGoTo(object : OutputStream() {
            override fun write(b: Int): Unit = throw IOException("disk full")
        })

        assertThrows(IOException::class.java) { AudioImporter(context).import(source) }

        assertEquals(listOf(FakeMediaProvider.row), FakeMediaProvider.deleted)
        assertTrue(FakeMediaProvider.updated.isEmpty())
    }
}
