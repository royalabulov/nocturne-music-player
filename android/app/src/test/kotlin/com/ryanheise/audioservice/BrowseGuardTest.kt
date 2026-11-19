package com.ryanheise.audioservice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/// Browsing the library (Android Auto) answers only the callers that need it.
class BrowseGuardTest {
    private val own = "com.nocturne"

    @Test
    fun `Android Auto, the system, Assistant and this app may browse`() {
        for (p in listOf(own, "com.google.android.projection.gearhead", "com.android.systemui", "com.google.android.googlequicksearchbox")) {
            assertTrue(p, BrowseGuard.allows(p, own))
        }
    }

    @Test
    fun `any other app, or an unknown caller, may not`() {
        for (p in listOf("com.example.spy", "com.nocturne.fake", "", null)) {
            assertFalse("$p", BrowseGuard.allows(p, own))
        }
    }

    @Test
    fun `the plugin still has the field the guard wraps`() {
        // A plugin update that renames it fails here, not silently on the phone
        assertNotNull(BrowseGuard.listenerField())
    }
}
