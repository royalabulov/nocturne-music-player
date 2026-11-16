package com.nocturne

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

/// The knock log is a developer tool: other users' phones must keep no sensor readings,
/// and turning developer mode off deletes what was kept.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class KnockLogTest {
    private lateinit var logs: File

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        KnockLog.init(context)
        logs = File(context.filesDir, "logs")
        KnockLog.setEnabled(false)
        KnockLog.export() // waits for the delete
    }

    private fun event(name: String) = JSONObject().put("event", name)

    @Test
    fun `off by default and while developer mode is off, nothing is written`() {
        KnockLog.write(event("decision"))
        assertNull(KnockLog.export())
        assertFalse(File(logs, "knock.log").exists())
    }

    @Test
    fun `in developer mode the decisions are kept`() {
        KnockLog.setEnabled(true)
        KnockLog.write(event("decision"))
        val text = String(KnockLog.export()!!)
        assertTrue(text, text.contains("\"event\":\"decision\""))
    }

    @Test
    fun `turning developer mode off deletes the log`() {
        KnockLog.setEnabled(true)
        KnockLog.write(event("decision"))
        // The write above is queued: the folder may not exist yet
        logs.mkdirs()
        File(logs, "knock.old.log").writeText("{\"event\":\"older\"}\n")
        KnockLog.setEnabled(false)
        assertNull(KnockLog.export())
        assertFalse(File(logs, "knock.log").exists())
        assertFalse(File(logs, "knock.old.log").exists())
    }
}
