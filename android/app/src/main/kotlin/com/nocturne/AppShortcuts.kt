package com.nocturne

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon

/// Long press on the app icon: Shuffle all, Continue (the last song), Radio, Search. Made by
/// the app at start (dynamic, so the labels follow the app's language and Continue can name
/// the song); a tap opens the window with the shortcut's id, and Dart does the rest.
object AppShortcuts {
    const val ACTION = "com.nocturne.SHORTCUT"
    const val EXTRA_ID = "shortcut"

    /// The only ids a shortcut intent may carry: any app can start the window with one.
    val IDS = setOf("shuffle", "continue", "radio", "search")

    private val icons = mapOf(
        "shuffle" to R.drawable.ic_shortcut_shuffle,
        "continue" to R.drawable.ic_shortcut_play,
        "radio" to R.drawable.ic_shortcut_radio,
        "search" to R.drawable.ic_shortcut_search,
    )

    /// [items]: {id, label, longLabel} in the order to show them. Unknown ids are left out.
    fun set(context: Context, items: List<Map<String, String>>) {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val shortcuts = items.mapIndexedNotNull { rank, item ->
            val id = item["id"]?.takeIf { it in IDS } ?: return@mapIndexedNotNull null
            ShortcutInfo.Builder(context, id)
                .setShortLabel(item["label"].orEmpty().take(25).ifEmpty { id })
                .setLongLabel(item["longLabel"].orEmpty().take(60).ifEmpty { item["label"].orEmpty().ifEmpty { id } })
                .setIcon(Icon.createWithResource(context, icons.getValue(id)))
                .setRank(rank)
                .setIntent(intent(context, id))
                .build()
        }
        val max = manager.maxShortcutCountPerActivity
        manager.dynamicShortcuts = shortcuts.take(max)
    }

    fun intent(context: Context, id: String): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA_ID, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    /// The shortcut an intent asks for; null when it isn't one of ours.
    fun idOf(intent: Intent?): String? =
        intent?.takeIf { it.action == ACTION }?.getStringExtra(EXTRA_ID)?.takeIf { it in IDS }
}

/// A shortcut tapped before Dart could take it (the app was starting).
object PendingShortcut {
    private var id: String? = null

    @Synchronized
    fun set(value: String) {
        id = value
    }

    @Synchronized
    fun take(): String? = id.also { id = null }
}
