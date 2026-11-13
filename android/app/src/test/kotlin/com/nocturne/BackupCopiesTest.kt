package com.nocturne

import android.content.ContentProvider
import android.content.ContentUris
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.provider.MediaStore
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream

/// Download as this app sees it: the files it wrote, newest first by the order added.
class FakeDownloads : ContentProvider() {
    companion object {
        /// (id, folder, name), oldest first
        val files = ArrayList<Triple<Long, String, String>>()

        /// id → size in bytes; a file not named here is 100 bytes
        val sizes = HashMap<Long, Long>()
        val inserted = ArrayList<ContentValues>()
        val deleted = ArrayList<Long>()
        var lastSelectionArgs: List<String> = emptyList()

        fun reset() {
            files.clear()
            sizes.clear()
            inserted.clear()
            deleted.clear()
            lastSelectionArgs = emptyList()
        }
    }

    override fun onCreate() = true
    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri {
        inserted.add(ContentValues(values))
        return ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, 999)
    }

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 1

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        deleted.add(ContentUris.parseId(uri))
        return 1
    }

    /// Answers "in this folder, starting with this" like MediaStore, newest first.
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        lastSelectionArgs = selectionArgs?.toList() ?: emptyList()
        val (folder, like) = lastSelectionArgs
        return MatrixCursor(arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.SIZE)).apply {
            for ((id, f, name) in files.reversed()) {
                if (f == folder && name.startsWith(like.removeSuffix("%"))) addRow(arrayOf(id, sizes[id] ?: 100L))
            }
        }
    }
}

/// The weekly automatic backup goes to Download/Nocturne and only the newest copies stay.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class BackupCopiesTest {
    private val context get() = RuntimeEnvironment.getApplication()

    @Before
    fun setUp() {
        FakeDownloads.reset()
        Robolectric.setupContentProvider(FakeDownloads::class.java, MediaStore.AUTHORITY)
    }

    @Test
    fun `a copy is written into its own folder in Download`() {
        val written = ByteArrayOutputStream()
        shadowOf(context.contentResolver).registerOutputStream(
            ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, 999), written,
        )
        val path = MediaLibrary(context).saveToDownloads("nocturne-auto-backup-1.json", "application/json", "{}".toByteArray(), "Nocturne")

        assertEquals("Download/Nocturne/nocturne-auto-backup-1.json", path)
        assertEquals("Download/Nocturne", FakeDownloads.inserted.single().getAsString(MediaStore.Downloads.RELATIVE_PATH))
        assertEquals("{}", written.toString())
    }

    @Test
    fun `only the newest copies are kept, and nothing else in the folder is touched`() {
        FakeDownloads.files += listOf(
            Triple(1L, "Download/Nocturne/", "nocturne-auto-backup-1.json"),
            Triple(2L, "Download/Nocturne/", "my-notes.txt"),
            Triple(3L, "Download/Nocturne/", "nocturne-auto-backup-2.json"),
            Triple(4L, "Download/", "nocturne-auto-backup-0.json"),
            Triple(5L, "Download/Nocturne/", "nocturne-auto-backup-3.json"),
        )

        val removed = MediaLibrary(context).keepNewestInDownloads("Nocturne", "nocturne-auto-backup-", 2)

        assertEquals(1, removed)
        assertEquals(listOf(1L), FakeDownloads.deleted)
        assertEquals(listOf("Download/Nocturne/", "nocturne-auto-backup-%"), FakeDownloads.lastSelectionArgs)
    }

    private fun backups(vararg sizes: Long) {
        sizes.forEachIndexed { i, size ->
            val id = i + 1L
            FakeDownloads.files += Triple(id, "Download/Nocturne/", "nocturne-auto-backup-$id.json")
            FakeDownloads.sizes[id] = size
        }
    }

    /// A damaged database was set aside: the new copies are nearly empty. The good one stays.
    @Test
    fun `an older copy bigger than the kept ones stays`() {
        backups(200_000, 210_000, 3_000, 3_100) // oldest first

        val removed = MediaLibrary(context).keepNewestInDownloads("Nocturne", "nocturne-auto-backup-", 2)

        assertEquals(1, removed)
        assertEquals(listOf(1L), FakeDownloads.deleted)
    }

    /// History only grows: the newest copies are the biggest, and the old ones go as before.
    @Test
    fun `when the newest copies are the biggest, only they stay`() {
        backups(100_000, 110_000, 120_000, 130_000)

        MediaLibrary(context).keepNewestInDownloads("Nocturne", "nocturne-auto-backup-", 2)

        assertEquals(listOf(2L, 1L), FakeDownloads.deleted)
    }

    @Test
    fun `copies of the same size leave only the newest`() {
        backups(500, 500, 500, 500)

        MediaLibrary(context).keepNewestInDownloads("Nocturne", "nocturne-auto-backup-", 2)

        assertEquals(listOf(2L, 1L), FakeDownloads.deleted)
    }

    @Test
    fun `never more than one extra copy is kept`() {
        backups(900, 800, 700, 600, 5, 4)

        MediaLibrary(context).keepNewestInDownloads("Nocturne", "nocturne-auto-backup-", 2)

        // The two newest (6, 5) and the biggest older one (1) stay
        assertEquals(listOf(4L, 3L, 2L), FakeDownloads.deleted)
    }
}
