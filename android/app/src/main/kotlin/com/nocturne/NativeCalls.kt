package com.nocturne

import android.app.Activity
import io.flutter.plugin.common.MethodChannel

/// A failed call reaches Dart as a PlatformException with this code, never as a normal result
/// that Dart has to recognise by its text.
const val CALL_FAILED = "failed"

fun MethodChannel.Result.fail(reason: String, details: Any? = null) = error(CALL_FAILED, reason, details)

fun Throwable.reason(): String = "${javaClass.simpleName}: $message"

/// Runs [work] off the UI thread (file copying, analysis) and answers on it.
fun Activity.background(result: MethodChannel.Result, work: () -> Any?) {
    Thread {
        val outcome = runCatching(work)
        runOnUiThread {
            outcome.fold(result::success) { result.fail(it.reason()) }
        }
    }.start()
}
