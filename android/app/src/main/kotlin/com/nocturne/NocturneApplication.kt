package com.nocturne

import android.app.Application
import com.nocturne.enginehook.EngineHookPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
class NocturneApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Before any Flutter engine exists: each one gets the app's channels the moment it is made
        EngineHookPlugin.setListener(object : EngineHookPlugin.Listener {
            override fun onAttached(binding: FlutterPlugin.FlutterPluginBinding) =
                EngineChannels.attach(binding.applicationContext, binding.binaryMessenger)

            override fun onDetached(binding: FlutterPlugin.FlutterPluginBinding) = EngineChannels.detach()
        })
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                val dir = File(filesDir, "logs").apply { mkdirs() }
                val sw = StringWriter()
                error.printStackTrace(PrintWriter(sw))
                val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                val log = File(dir, "native_crash.log")
                // A crash loop must not fill the phone
                if (log.length() > 256 * 1024) log.delete()
                log.appendText("$time  CRASH in thread '${thread.name}'\n$sw\n")
            }
            previous?.uncaughtException(thread, error)
        }
    }
}
