package com.nocturne

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer

/// Whether this phone can give a player a system equalizer. just_audio makes one for every
/// player with no try, so on a phone that can't ("Cannot initialize effect engine": no effect
/// library, or the system's effect slots used up) no song played at all. Asked once before
/// the players exist; without it they are built with no equalizer.
object EqualizerProbe {
    /// No log here (release builds write none); the Dart side notes a no in the error log.
    fun works(context: Context): Boolean = works {
        val audio = context.getSystemService(AudioManager::class.java)
        Equalizer(0, audio.generateAudioSessionId())
    }

    /// [make] builds one equalizer; it is released at once.
    internal fun works(make: () -> AudioEffect): Boolean =
        runCatching { make().release() }.isSuccess
}
