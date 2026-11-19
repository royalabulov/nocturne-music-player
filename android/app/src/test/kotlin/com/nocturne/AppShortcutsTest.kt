package com.nocturne

import android.content.Intent
import android.content.pm.ShortcutManager
import org.robolectric.RuntimeEnvironment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/// Long-press shortcuts: our four, in order, and a tap's intent carries only one of them.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppShortcutsTest {
    private val context: android.content.Context = RuntimeEnvironment.getApplication()

    @Test
    fun `the four shortcuts are set in order, an unknown one is left out`() {
        AppShortcuts.set(
            context,
            listOf(
                mapOf("id" to "shuffle", "label" to "Shuffle all", "longLabel" to "Shuffle all songs"),
                mapOf("id" to "continue", "label" to "Continue", "longLabel" to "Continue: Keşke"),
                mapOf("id" to "delete-everything", "label" to "?"),
                mapOf("id" to "radio", "label" to "Radio"),
                mapOf("id" to "search", "label" to "Search"),
            ),
        )
        val set = context.getSystemService(ShortcutManager::class.java).dynamicShortcuts.sortedBy { it.rank }
        assertEquals(listOf("shuffle", "continue", "radio", "search"), set.map { it.id })
        assertEquals("Continue: Keşke", set[1].longLabel)
        assertEquals("Radio", set[2].longLabel, "no long label: the short one")
        assertEquals("continue", AppShortcuts.idOf(set[1].intent))
    }

    @Test
    fun `an intent is a shortcut only with our action and a known id`() {
        assertEquals("radio", AppShortcuts.idOf(AppShortcuts.intent(context, "radio")))
        assertNull(AppShortcuts.idOf(Intent(AppShortcuts.ACTION).putExtra(AppShortcuts.EXTRA_ID, "wipe")))
        assertNull(AppShortcuts.idOf(Intent(Intent.ACTION_MAIN).putExtra(AppShortcuts.EXTRA_ID, "radio")))
        assertNull(AppShortcuts.idOf(null))
    }

    @Test
    fun `a pending shortcut is taken once`() {
        PendingShortcut.set("search")
        assertEquals("search", PendingShortcut.take())
        assertNull(PendingShortcut.take())
    }

    private fun assertEquals(expected: Any?, actual: Any?, @Suppress("UNUSED_PARAMETER") reason: String) =
        assertEquals(expected, actual)
}
