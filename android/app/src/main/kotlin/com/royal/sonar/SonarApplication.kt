package com.royal.sonar

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Writes native (Java/Kotlin) crashes to a file before the process dies:
/// <filesDir>/logs/native_crash.log — the Dart side (CrashLog) shows it in Settings →
/// Diagnostics. E.g. the background startForeground ban, ExoPlayer
/// native errors.
class SonarApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                val dir = File(filesDir, "logs").apply { mkdirs() }
                val sw = StringWriter()
                error.printStackTrace(PrintWriter(sw))
                val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                File(dir, "native_crash.log").appendText(
                    "$time  CRASH in thread '${thread.name}'\n$sw\n"
                )
            }
            previous?.uncaughtException(thread, error)
        }
    }
}
