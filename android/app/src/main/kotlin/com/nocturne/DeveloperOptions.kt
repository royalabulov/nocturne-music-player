package com.nocturne

import android.content.Context
import android.provider.Settings

/// The phone's own Developer options (Settings → About → tap Build number 7 times).
/// The app's developer mode opens only while they are on, so nobody turns it on by accident.
object DeveloperOptions {
    fun isOn(context: Context): Boolean =
        Settings.Global.getInt(context.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
}
