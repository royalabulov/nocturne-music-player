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
        val inserted = ArrayList<ContentValues>()
        val deleted = ArrayList<Long>()
        var lastSelectionArgs: List<String> = emptyList()

        fun reset() {
            files.clear()
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
        return MatrixCursor(arrayOf(MediaStore.Downloads._ID)).apply {
            for ((id, f, name) in files.reversed()) {
                if (f == folder && name.startsWith(like.removeSuffix("%"))) addRow(arrayOf(id))
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
}
