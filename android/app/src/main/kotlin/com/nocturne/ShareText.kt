package com.nocturne

import android.content.Intent

/// Settings → Error log → Share: the system share sheet with the log as text, so the user can
/// send it to the developer (mail, messenger) with an app of their own choice. Nothing is sent
/// without that choice.
object ShareText {
    /// An Intent travels through a Binder transaction of about 1 MB (UTF-16: 2 bytes a char);
    /// a bigger log made startActivity throw. The newest part is the useful one.
    const val MAX_CHARS = 100_000

    fun chooser(text: String, title: String): Intent {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, title)
            .putExtra(Intent.EXTRA_TEXT, newest(text))
        // Started from the engine's context, which may not be an Activity
        return Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /// The last [MAX_CHARS] characters, not starting in the middle of an emoji.
    fun newest(text: String): String {
        if (text.length <= MAX_CHARS) return text
        var start = text.length - MAX_CHARS
        if (Character.isLowSurrogate(text[start])) start++
        return text.substring(start)
    }
}
