package com.nocturne

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KnockAxisTest {
    @Test
    fun `a jolt straight through the flat face is all on the axis`() {
        assertEquals(1.0, KnockAxis.share(0.0, 0.0, 30.0), 1e-9)
        assertEquals(1.0, KnockAxis.share(0.0, 0.0, -30.0), 1e-9)
    }

    @Test
    fun `a jolt along the phone is off the axis`() {
        assertEquals(0.0, KnockAxis.share(12.0, 25.0, 0.0), 1e-9)
    }

    @Test
    fun `no jolt at all counts as off the axis`() {
        assertEquals(0.0, KnockAxis.share(0.0, 0.0, 0.0), 1e-9)
    }

    @Test
    fun `walking needs a purer knock than a still phone`() {
        val share = 0.87 // a soft real knock on a still phone (log, 2026-11-04 21:52:56)
        assertTrue(KnockAxis.isOnAxis(share, walking = false))
        assertFalse(KnockAxis.isOnAxis(share, walking = true))
    }

    @Test
    fun `values from the real log land on the right side`() {
        assertTrue(KnockAxis.isOnAxis(0.99, walking = true)) // 3 knocks while walking
        assertFalse(KnockAxis.isOnAxis(0.81, walking = true)) // typical jolt of a walk
    }
}
