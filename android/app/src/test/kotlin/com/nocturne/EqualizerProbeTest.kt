package com.nocturne

import android.media.audiofx.AudioEffect
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/// A phone that can't make a system equalizer must not stop every song from playing.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class EqualizerProbeTest {
    @Test
    fun `an equalizer that can't be made is a no, not a crash`() {
        assertFalse(EqualizerProbe.works { throw RuntimeException("Cannot initialize effect engine") })
        assertFalse(EqualizerProbe.works { throw UnsupportedOperationException("Effect library not loaded") })
    }

    @Test
    fun `one that can be made is a yes`() {
        // Robolectric's own Equalizer: the real constructor path, released again
        assertTrue(EqualizerProbe.works { android.media.audiofx.Equalizer(0, 1) as AudioEffect })
    }
}
