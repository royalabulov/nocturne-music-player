package com.nocturne

import android.content.ClipData
import android.content.Intent
import android.net.Uri

/// Wrapped → Share: the system share sheet with the card as a picture (Instagram, a messenger:
/// the user picks the app). The image is one this app saved to the gallery (MediaLibrary
/// .saveImage); the receiving app may read only that one, and only for this share.
object ShareImage {
    fun chooser(uri: Uri, title: String): Intent {
        val send = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // ClipData too: Android hands the read permission over through it
        send.clipData = ClipData.newRawUri(title, uri)
        return Intent.createChooser(send, title)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}
