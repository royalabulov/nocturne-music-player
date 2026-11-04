package com.nocturne

import android.net.Uri
import java.io.File

/// Only URIs another app may legitimately hand us. Any app can send our exported activity
/// a file:// URI pointing into our own storage: the importer can read it and would copy it
/// to the public Music/Nocturne folder (e.g. the library database).
/// So: content:// from other apps' providers, file:// only on shared storage.
internal object IncomingUriPolicy {
    /// [canonicalize] resolves ".." and symlinks before the prefix check.
    fun isSafe(
        uri: Uri,
        packageName: String,
        canonicalize: (String) -> String = { File(it).canonicalPath },
    ): Boolean = when (uri.scheme) {
        "content" -> uri.authority?.startsWith(packageName) != true
        "file" -> {
            val path = uri.path?.let { runCatching { canonicalize(it) }.getOrNull() }
            path != null && path.startsWith("/storage/") &&
                !path.contains("/Android/data/$packageName") &&
                !path.contains("/Android/obb/$packageName")
        }
        else -> false
    }
}
