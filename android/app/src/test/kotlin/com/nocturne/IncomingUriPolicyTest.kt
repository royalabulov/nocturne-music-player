package com.nocturne

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    // ── how many files one app can hand us ────────────────────

    private fun contentUris(n: Int) = List(n) { Uri.parse("content://com.other.app/$it") }

    @Test
    fun `unsafe URIs are dropped and the safe ones kept in order`() {
        val uris = listOf(
            Uri.parse("content://com.other.app/1"),
            Uri.parse("file:///data/user/0/com.nocturne/databases/sonar.sqlite"),
            Uri.parse("content://com.other.app/2"),
        )
        assertEquals(
            listOf("content://com.other.app/1", "content://com.other.app/2"),
            IncomingUriPolicy.accept(uris, pkg, pending = 0).map { it.toString() },
        )
    }

    @Test
    fun `a flood of URIs is cut at the limit`() {
        assertEquals(IncomingUriPolicy.MAX_PENDING, IncomingUriPolicy.accept(contentUris(5000), pkg, pending = 0).size)
    }

    @Test
    fun `files still waiting count toward the limit`() {
        val limit = IncomingUriPolicy.MAX_PENDING
        assertEquals(1, IncomingUriPolicy.accept(contentUris(50), pkg, pending = limit - 1).size)
        assertEquals(0, IncomingUriPolicy.accept(contentUris(50), pkg, pending = limit).size)
    }

    // ── the path a content provider claims ────────────────────

    private fun claimed(path: String?, readable: Boolean = true) =
        IncomingUriPolicy.trustedPath(path, pkg, ::phoneCanonicalPath) { readable }

    @Test
    fun `a claimed path on shared storage is used`() {
        assertEquals("/storage/emulated/0/Music/song.mp3", claimed("/storage/emulated/0/Music/song.mp3"))
    }

    @Test
    fun `a claimed path is returned resolved`() {
        assertEquals("/storage/emulated/0/Music/song.mp3", claimed("/storage/emulated/0/Other/../Music/song.mp3"))
    }

    @Test
    fun `a claimed path into private storage is not believed`() {
        assertNull(claimed("/data/user/0/com.nocturne/databases/sonar.sqlite"))
        assertNull(claimed("/storage/emulated/0/../../../data/user/0/com.nocturne/databases/sonar.sqlite"))
        assertNull(claimed("/storage/emulated/0/Android/data/com.nocturne/files/a.mp3"))
    }

    @Test
    fun `a claimed path that is missing or unreadable is not used`() {
        assertNull(claimed(null))
        assertNull(claimed("/storage/emulated/0/Music/song.mp3", readable = false))
    }

    @Test
    fun `a claimed path that cannot be resolved is not used`() {
        val failing: (String) -> String = { throw java.io.IOException("bad path") }
        assertNull(IncomingUriPolicy.trustedPath("/storage/emulated/0/a.mp3", pkg, failing) { true })
    }
}
