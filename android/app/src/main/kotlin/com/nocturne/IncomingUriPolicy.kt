package com.nocturne

import android.net.Uri
import java.io.File

/// What we accept from other apps. Our activity is exported: any app can send it a file://
/// URI pointing into our own storage, and the importer can read that and would copy it to
/// the public Music/Nocturne folder (e.g. the library database). So: content:// from other
/// apps' providers, file:// only on shared storage.
internal object IncomingUriPolicy {
    /// Files waiting to be imported at most. Sharing a whole album still fits; one intent
    /// (or a stream of them) can't queue thousands of copies.
    const val MAX_PENDING = 500

    /// The URIs of one intent that we take, with [pending] already waiting.
    fun accept(uris: List<Uri>, packageName: String, pending: Int): List<Uri> =
        uris.filter { isSafe(it, packageName) }.take((MAX_PENDING - pending).coerceAtLeast(0))

    /// [canonicalize] resolves ".." and symlinks before the prefix check.
    fun isSafe(
        uri: Uri,
        packageName: String,
        canonicalize: (String) -> String = { File(it).canonicalPath },
    ): Boolean = when (uri.scheme) {
        "content" -> uri.authority?.startsWith(packageName) != true
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
