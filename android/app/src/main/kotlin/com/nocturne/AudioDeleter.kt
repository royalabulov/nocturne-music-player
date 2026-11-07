package com.nocturne

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.IntentSender
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Deletes files from the phone. Scoped storage (Android 10+): a file written by another app
/// (downloader, messenger) can't be deleted directly → MediaStore delete request, and the
/// system shows a one-time confirmation dialog, so the activity has to pass its result back.
///
/// Every call is answered: a result on success or refusal, [fail] with the reason otherwise.
class AudioDeleter(private val activity: Activity) {
    private val resolver get() = activity.contentResolver
    private var pending: MethodChannel.Result? = null
    private var pendingPath: String? = null
    private var pendingBatch: List<String>? = null

    /// Result: "deleted" | "cancelled".
    fun delete(path: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.fail(BUSY)
            return
        }
        try {
            val f = File(path)
            val uri = mediaStoreUriFor(path)
            if (uri != null) {
                deleteUri(uri, path, result)
                return
            }
            if (!f.exists()) {
                result.success("deleted")
                return
            }
            // MediaStore doesn't know this file (found by the folder walk) →
            // index it to get a URI, then delete the normal way.
            MediaScannerConnection.scanFile(activity.applicationContext, arrayOf(path), null) { _, scanned ->
                activity.runOnUiThread {
                    when {
                        scanned != null -> deleteUri(scanned, path, result)
                        f.delete() -> result.success("deleted")
                        else -> result.fail("file is not in MediaStore and cannot be deleted")
                    }
                }
            }
        } catch (e: Exception) {
            result.fail(e.reason())
        }
    }

    private fun deleteUri(uri: Uri, path: String, result: MethodChannel.Result) {
        try {
            // 1) Try without a dialog: works for our own files, otherwise SecurityException
            try {
                if (resolver.delete(uri, null, null) > 0 && !File(path).exists()) {
                    result.success("deleted")
                    return
                }
            } catch (e: SecurityException) {
                // 2) Android 10: ask the user for permission
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                    askUser(e.userAction.actionIntent.intentSender, path, result)
                    return
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.fail(e.reason())
                    return
                }
            }
            // 3) Android 11+: system confirmation dialog ("Allow Nocturne to delete this file?")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pi = MediaStore.createDeleteRequest(resolver, listOf(uri))
                askUser(pi.intentSender, path, result)
                return
            }
            if (File(path).delete() || !File(path).exists()) result.success("deleted")
            else result.fail("delete refused")
        } catch (e: Exception) {
            result.fail(e.reason())
        }
    }

    /// Bulk delete. Result map: status ("deleted" | "cancelled" | "unsupported") + deleted
    /// (paths actually deleted). A failure carries the paths already gone as its details.
    /// Android 11+: our own files without a dialog, the rest in **one** system
    /// dialog. Android 10 and older: "unsupported" → Dart deletes each file separately.
    fun deleteBatch(paths: List<String>, result: MethodChannel.Result) {
        val done = ArrayList<String>()
        if (pending != null) {
            result.fail(BUSY, done)
            return
        }
        try {
            val uris = ArrayList<Uri>()
            for (p in paths) {
                val uri = mediaStoreUriFor(p)
                if (uri == null) {
                    val f = File(p)
                    if (!f.exists() || f.delete()) done.add(p)
                    continue
                }
                val direct = try {
                    resolver.delete(uri, null, null) > 0 && !File(p).exists()
                } catch (e: SecurityException) {
                    false
                }
                if (direct) done.add(p) else uris.add(uri)
            }
            if (uris.isEmpty()) {
                result.success(mapOf("status" to "deleted", "deleted" to done))
                return
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                result.success(mapOf("status" to "unsupported", "deleted" to done))
                return
            }
            val pi = MediaStore.createDeleteRequest(resolver, uris)
            pendingBatch = paths
            askUser(pi.intentSender, null, result)
        } catch (e: Exception) {
            pendingBatch = null
            result.fail(e.reason(), done)
        }
    }

    private fun askUser(sender: IntentSender, path: String?, result: MethodChannel.Result) {
        pending = result
        pendingPath = path
        try {
            activity.startIntentSenderForResult(sender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            pending = null
            pendingPath = null
            pendingBatch = null
            result.fail("could not open system dialog: ${e.message}")
        }
    }

    private fun mediaStoreUriFor(path: String): Uri? {
        val cursor = resolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Audio.Media._ID),
            "${MediaStore.Audio.Media.DATA} = ?",
            arrayOf(path),
            null,
        ) ?: return null
        cursor.use { c ->
            if (!c.moveToFirst()) return null
            return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, c.getLong(0))
        }
    }

    /// The system dialog closed.
    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != REQUEST_CODE) return
        val result = pending
        val batch = pendingBatch
        val path = pendingPath
        pending = null
        pendingBatch = null
        pendingPath = null
        val approved = resultCode == Activity.RESULT_OK
        when {
            batch != null -> result?.success(
                mapOf(
                    "status" to if (approved) "deleted" else "cancelled",
                    "deleted" to batch.filter { !File(it).exists() },
                )
            )
            !approved -> result?.success("cancelled")
            path != null && File(path).exists() -> result?.fail("system approved but the file still exists")
            else -> result?.success("deleted")
        }
    }

    private companion object {
        const val REQUEST_CODE = 4711
        const val BUSY = "another delete is waiting for confirmation"
    }
}
