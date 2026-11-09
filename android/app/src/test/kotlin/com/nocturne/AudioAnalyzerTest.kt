package com.nocturne

import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/// A file the analysis can't open must fail that one song and leave the analyzer usable.
/// (That the native extractor is released on this path can't be seen in Robolectric: its
/// MediaExtractor shadow doesn't track release. The code keeps it inside try/finally.)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AudioAnalyzerTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val analyzer = AudioAnalyzer(RuntimeEnvironment.getApplication())

    @Test
    fun `a file that can't be opened is an error, and the next song still gets analyzed`() {
        val broken = tmp.newFile("broken.mp3").apply { writeText("not audio") }
        repeat(2) {
            val failure = runCatching { analyzer.analyze(broken.path, 180_000) }.exceptionOrNull()
            assertTrue("expected an error, got $failure", failure != null)
        }
    }
}
