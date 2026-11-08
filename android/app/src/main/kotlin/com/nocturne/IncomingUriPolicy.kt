package com.nocturne

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import java.io.File

/// What we accept from other apps. Our activity is exported: any app can send it a file://
/// URI pointing into our own storage, and the importer can read that and would copy it to
/// the public Music/Nocturne folder (e.g. the library database). So: content:// from other
/// apps' providers, file:// only on shared storage.
internal object IncomingUriPolicy {
    /// Files waiting to be imported at most. Sharing a whole album still fits; one intent
    /// (or a stream of them) can't queue thousands of copies.
    const val MAX_PENDING = 500

    /// Before Android 13 the first look at any extra reads them all, so a value of a class this
    /// app doesn't have crashes whoever looks first: FlutterActivity, before our own code. Call
    /// this before the activity hands the intent to anyone.
    fun dropUnreadableExtras(intent: Intent?) {
        try {
            intent?.hasExtra(Intent.EXTRA_STREAM)
        } catch (e: RuntimeException) {
            intent?.replaceExtras(null as Bundle?)
        }
    }

    /// What an intent says it brings. Another app chose what's inside: a value of the wrong type
    /// or one that can't be read means no file, not a crash that stops the music.
    fun urisOf(intent: Intent): List<Uri> = try {
        when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(stream(intent))
            Intent.ACTION_SEND_MULTIPLE -> streams(intent)
            else -> emptyList()
        }
    } catch (e: RuntimeException) {
        emptyList()
    }

    @Suppress("DEPRECATION")
    private fun stream(i: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableExtra<Parcelable>(Intent.EXTRA_STREAM) as? Uri

    /// filterIsInstance: the type of a list isn't checked on its way in, so each item is.
    @Suppress("DEPRECATION")
    private fun streams(i: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableArrayListExtra<Parcelable>(Intent.EXTRA_STREAM))
            ?.filterIsInstance<Uri>() ?: emptyList()

    /// The URIs of one intent that we take, with [pending] already waiting.
    fun accept(uris: List<Uri>, packageName: String, pending: Int): List<Uri> =
        uris.filter { isSafe(it, packageName) }.take((MAX_PENDING - pending).coerceAtLeast(0))

    /// [canonicalize] resolves ".." and symlinks before the prefix check.
    fun isSafe(
        uri: Uri,
        packageName: String,
        canonicalize: (String) -> String = { File(it).canonicalPath },
    ): Boolean = when (uri.scheme) {
        // "0@com.nocturne.x" is the same provider to Android: the part before @ names the user
        "content" -> uri.authority?.substringAfterLast('@')?.startsWith(packageName) != true
        "file" -> uri.path?.let { resolved(it, canonicalize) }?.let { isSharedStorage(it, packageName) } == true
        else -> false
    }

    /// The path a content provider claims for its file (the _data column). Any app can claim
    /// anything there, so it counts only if it really is a readable file on shared storage.
    fun trustedPath(
        claimed: String?,
        packageName: String,
        canonicalize: (String) -> String = { File(it).canonicalPath },
        canRead: (String) -> Boolean = { File(it).canRead() },
    ): String? = claimed?.let { resolved(it, canonicalize) }
        ?.takeIf { isSharedStorage(it, packageName) && canRead(it) }

    private fun resolved(path: String, canonicalize: (String) -> String): String? =
        runCatching { canonicalize(path) }.getOrNull()

    private fun isSharedStorage(path: String, packageName: String) =
        path.startsWith("/storage/") &&
            !path.contains("/Android/data/$packageName") &&
            !path.contains("/Android/obb/$packageName")
}
