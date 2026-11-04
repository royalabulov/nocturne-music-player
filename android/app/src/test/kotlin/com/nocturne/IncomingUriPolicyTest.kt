package com.nocturne

import android.net.Uri
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class IncomingUriPolicyTest {
    private val pkg = "com.nocturne"

    /// What File.canonicalPath gives on a phone, whichever OS runs the tests.
    private fun phoneCanonicalPath(path: String): String {
        val parts = ArrayDeque<String>()
        for (part in path.split('/')) {
            when (part) {
                "", "." -> Unit
                ".." -> parts.removeLastOrNull()
                else -> parts.addLast(part)
            }
        }
        return "/" + parts.joinToString("/")
    }

    private fun isSafe(uri: String) = IncomingUriPolicy.isSafe(Uri.parse(uri), pkg, ::phoneCanonicalPath)

    @Test
    fun `content from another app is accepted`() {
        assertTrue(isSafe("content://com.whatsapp.provider.media/item/1"))
        assertTrue(isSafe("content://media/external/audio/media/42"))
    }

    @Test
    fun `content from our own providers is refused`() {
        assertFalse(isSafe("content://com.nocturne/anything"))
        assertFalse(isSafe("content://com.nocturne.androidx-startup/anything"))
    }

    @Test
    fun `file on shared storage is accepted`() {
        assertTrue(isSafe("file:///storage/emulated/0/Music/song.mp3"))
        assertTrue(isSafe("file:///storage/1234-ABCD/Music/song.mp3"))
    }

    @Test
    fun `file in private storage is refused`() {
        assertFalse(isSafe("file:///data/user/0/com.nocturne/databases/sonar.sqlite"))
        assertFalse(isSafe("file:///data/data/com.nocturne/files/logs/sonar.log"))
    }

    @Test
    fun `file in our own external folders is refused`() {
        assertFalse(isSafe("file:///storage/emulated/0/Android/data/com.nocturne/files/a.mp3"))
        assertFalse(isSafe("file:///storage/emulated/0/Android/obb/com.nocturne/a.mp3"))
    }

    @Test
    fun `path traversal out of shared storage is refused`() {
        assertFalse(isSafe("file:///storage/emulated/0/../../../data/user/0/com.nocturne/databases/sonar.sqlite"))
        assertFalse(isSafe("file:///storage/emulated/0/Music/../Android/data/com.nocturne/files/a.mp3"))
    }

    @Test
    fun `percent-encoded path traversal is refused`() {
        assertFalse(isSafe("file:///storage/emulated/0/%2e%2e/%2e%2e/%2e%2e/data/user/0/com.nocturne/databases/sonar.sqlite"))
        assertFalse(isSafe("file:///storage/emulated/0/..%2f..%2f..%2fdata/user/0/com.nocturne/databases/sonar.sqlite"))
    }

    @Test
    fun `a look-alike shared storage prefix is refused`() {
        assertFalse(isSafe("file:///storage_fake/emulated/0/a.mp3"))
    }

    @Test
    fun `a path that cannot be resolved is refused`() {
        val failing: (String) -> String = { throw java.io.IOException("bad path") }
        assertFalse(IncomingUriPolicy.isSafe(Uri.parse("file:///storage/emulated/0/a.mp3"), pkg, failing))
    }

    @Test
    fun `other schemes and bare paths are refused`() {
        assertFalse(isSafe("http://example.com/song.mp3"))
        assertFalse(isSafe("https://example.com/song.mp3"))
        assertFalse(isSafe("javascript:alert(1)"))
        assertFalse(isSafe("/storage/emulated/0/Music/song.mp3"))
        assertFalse(isSafe(""))
    }
}
