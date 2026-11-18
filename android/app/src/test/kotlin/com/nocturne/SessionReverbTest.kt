package com.nocturne

import android.media.audiofx.EnvironmentalReverb
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/// Slowed + reverb: one reverb per player session, released when it is turned off, and a
/// phone that can't make one says no instead of crashing.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SessionReverbTest {
    @Test
    fun `a reverb that can't be made is a no, not a crash`() {
        assertFalse(SessionReverb.works { throw RuntimeException("Cannot initialize effect engine") })
        val reverb = SessionReverb { throw UnsupportedOperationException("Effect library not loaded") }
        assertFalse(reverb.set(7, 0.5))
        assertTrue(reverb.sessions.isEmpty())
    }

    @Test
    fun `each session gets its own reverb, made once, and off releases it`() {
        val made = mutableListOf<Int>()
        val reverb = SessionReverb { session -> made.add(session); EnvironmentalReverb(0, session) }

        assertTrue(reverb.set(7, 0.5))
        assertTrue(reverb.set(7, 0.8)) // the same one, retuned
        assertTrue(reverb.set(9, 0.5))
        assertEquals(listOf(7, 9), made)
        assertEquals(setOf(7, 9), reverb.sessions)

        assertTrue(reverb.set(7, 0.0))
        assertEquals(setOf(9), reverb.sessions)
        reverb.releaseAll()
        assertTrue(reverb.sessions.isEmpty())
    }

    @Test
    fun `more reverb is a longer and louder tail, within Android's ranges`() {
        val low = SessionReverb.settings(0.1)
        val high = SessionReverb.settings(1.0)
        assertTrue(high.decayTime > low.decayTime)
        assertTrue(high.reverbLevel > low.reverbLevel)
        for (s in listOf(SessionReverb.settings(-1.0), low, high, SessionReverb.settings(5.0))) {
            assertTrue(s.decayTime in 100..20000)
            assertTrue(s.reverbLevel in -9000..2000)
            assertTrue(s.roomLevel in -9000..0)
        }
    }
}
