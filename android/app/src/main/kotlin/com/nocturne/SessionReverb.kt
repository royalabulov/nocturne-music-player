package com.nocturne

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.EnvironmentalReverb

/// Slowed + reverb: a reverb on one player's audio session. Made on a session other than 0,
/// Android picks its "insert" reverb, mixed into that player only and not into the phone's
/// other sound. just_audio's effect list has no reverb, so the Dart side hands the session
/// ids of its two players here.
///
/// [make] builds a reverb on a session (tests stand in for the phone).
class SessionReverb(private val make: (Int) -> EnvironmentalReverb = { EnvironmentalReverb(0, it) }) {
    private val bySession = HashMap<Int, EnvironmentalReverb>()

    /// Sessions that have a reverb now (for tests).
    internal val sessions: Set<Int> get() = bySession.keys

    /// [amount] 0..1; 0 takes the reverb off that session and releases it. False when the
    /// phone can't make one (no effect library, effect slots used up).
    fun set(session: Int, amount: Double): Boolean {
        if (amount <= 0.0) {
            bySession.remove(session)?.let { runCatching { it.release() } }
            return true
        }
        val reverb = bySession[session]
            ?: runCatching { make(session) }.getOrNull()?.also { bySession[session] = it }
            ?: return false
        return runCatching {
            reverb.properties = settings(amount)
            reverb.enabled = true
        }.isSuccess
    }

    /// Every reverb released (the engine is going away).
    fun releaseAll() {
        bySession.values.forEach { runCatching { it.release() } }
        bySession.clear()
    }

    companion object {
        /// Whether this phone can make the reverb at all; asked once for the effect screen.
        fun works(context: Context): Boolean = works {
            val audio = context.getSystemService(AudioManager::class.java)
            EnvironmentalReverb(0, audio.generateAudioSessionId())
        }

        internal fun works(make: () -> EnvironmentalReverb): Boolean =
            runCatching { make().release() }.isSuccess

        /// The sound of a big, soft room, growing with [amount] (0..1): a longer tail and a
        /// louder echo. Highs fade fast in it (roomHFLevel, decayHFRatio), the warm, washed
        /// sound of "slowed + reverb" edits. Units: millibels and milliseconds.
        internal fun settings(amount: Double): EnvironmentalReverb.Settings {
            val a = amount.coerceIn(0.0, 1.0)
            return EnvironmentalReverb.Settings().apply {
                roomLevel = 0
                roomHFLevel = -1000
                decayTime = (1200 + 2800 * a).toInt() // 1.2 to 4 s
                decayHFRatio = 600
                reflectionsLevel = -1500
                reflectionsDelay = 20
                reverbLevel = (-2500 + 2000 * a).toInt().toShort() // -25 to -5 dB
                reverbDelay = 40
                diffusion = 1000
                density = 1000
            }
        }
    }
}
