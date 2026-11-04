package com.nocturne

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/// Stands in for another app's FileProvider: it answers with whatever a test sets here,
/// which is exactly what a hostile app could answer too.
class FakeAudioProvider : ContentProvider() {
    companion object {
        const val AUTHORITY = "com.other.app.provider"
        val uri: Uri = Uri.parse("content://$AUTHORITY/shared/1")

        var columns: Map<String, Any?> = emptyMap()
        var mime: String? = null

        /// Null: the file can't be opened.
        var bytes: ByteArray? = null
        lateinit var scratch: File

        fun reset(scratchDir: File) {
            columns = emptyMap()
            mime = null
            bytes = null
            scratch = scratchDir
        }
    }

    override fun onCreate() = true

    override fun getType(uri: Uri) = mime

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor = MatrixCursor(columns.keys.toTypedArray()).apply { addRow(columns.values.toTypedArray()) }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val content = bytes ?: throw FileNotFoundException(uri.toString())
        val file = File.createTempFile("provider", null, scratch).apply { writeBytes(content) }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
}
