package com.nocturne

import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File
import java.io.FileNotFoundException

/// Android 9: import writes real files to the app's own Music folder, so everything
/// except the MediaStore calls runs for real here (AudioImporterMediaStoreTest has those).
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class AudioImporterTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val context get() = RuntimeEnvironment.getApplication()
    private val importer get() = AudioImporter(context)
    private val source = FakeAudioProvider.uri.toString()

    private val target: File
        get() = File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), "Nocturne")

    @Before
    fun setUp() {
        FakeAudioProvider.reset(tmp.newFolder())
        Robolectric.setupContentProvider(FakeAudioProvider::class.java, FakeAudioProvider.AUTHORITY)
    }

    /// Bytes of [size] that pass as an MP3, the rest filled with [fill].
    private fun audio(size: Int, fill: Byte = 7): ByteArray =
        ByteArray(size) { fill }.also { "ID3".toByteArray().copyInto(it) }

    private fun provide(name: String?, bytes: ByteArray?, size: Long? = bytes?.size?.toLong()) {
        FakeAudioProvider.columns = buildMap {
            if (name != null) put(OpenableColumns.DISPLAY_NAME, name)
            if (size != null) put(OpenableColumns.SIZE, size)
        }
        FakeAudioProvider.bytes = bytes
    }

    /// Paths on a phone start with "/"; this one does too and still opens on a Windows machine.
    private fun File.asPhonePath() = "/" + absolutePath.replace('\\', '/').trimStart('/')

    // ── resolve ───────────────────────────────────────────────

    @Test
    fun `resolve takes name and size from the provider`() {
        provide("song.mp3", ByteArray(10))
        val info = importer.resolve(source)
        assertEquals("song.mp3", info.name)
        assertEquals(10L, info.size)
        assertNull(info.path)
    }

    @Test
    fun `resolve falls back to the last path segment when the provider names nothing`() {
        provide(null, null, size = null)
        val info = importer.resolve(source)
        assertEquals("1", info.name)
        assertEquals(-1L, info.size)
    }

    @Test
    fun `resolve of a readable path returns it`() {
        val file = tmp.newFile("song.mp3").apply { writeBytes(ByteArray(7)) }
        val info = importer.resolve(file.asPhonePath())
        assertEquals(file.absolutePath, info.path)
        assertEquals("song.mp3", info.name)
        assertEquals(7L, info.size)
    }

    @Test
    fun `resolve of a readable file URI returns its path`() {
        val file = tmp.newFile("song.mp3").apply { writeBytes(ByteArray(7)) }
        val info = importer.resolve("file://${file.asPhonePath()}")
        assertEquals(file.absolutePath, info.path)
        assertEquals(7L, info.size)
    }

    @Test
    fun `resolve of a missing path has no path`() {
        assertNull(importer.resolve(File(tmp.root, "missing.mp3").asPhonePath()).path)
    }

    @Test
    fun `resolve ignores a data column pointing at nothing`() {
        FakeAudioProvider.columns = mapOf(MediaStore.MediaColumns.DATA to File(tmp.root, "missing.mp3").absolutePath)
        assertNull(importer.resolve(source).path)
    }

    /// A provider we don't know can claim any path, including our own private files.
    @Test
    fun `resolve must not believe the data column of an unknown provider`() {
        val privateFile = tmp.newFile("sonar.sqlite")
        FakeAudioProvider.columns = mapOf(MediaStore.MediaColumns.DATA to privateFile.absolutePath)
        assertNull(importer.resolve(source).path)
    }

    // ── import: the copy ──────────────────────────────────────

    @Test
    fun `import copies the content into the Nocturne folder`() {
        val content = audio(1024)
        provide("song.mp3", content)
        val saved = File(importer.import(source))
        assertEquals(File(target, "song.mp3").absolutePath, saved.absolutePath)
        assertArrayEquals(content, saved.readBytes())
    }

    @Test
    fun `sharing the same file twice does not copy it again`() {
        provide("song.mp3", audio(16))
        val first = importer.import(source)
        val second = importer.import(source)
        assertEquals(first, second)
        assertEquals(1, target.listFiles()!!.size)
    }

    @Test
    fun `a different file with the same name does not overwrite the first`() {
        val original = audio(16, fill = 1)
        provide("song.mp3", original)
        val first = File(importer.import(source))

        provide("song.mp3", audio(32, fill = 2))
        val second = File(importer.import(source))

        assertEquals("song (1).mp3", second.name)
        assertArrayEquals(original, first.readBytes())
        assertEquals(32L, second.length())
    }

    @Test
    fun `a file that cannot be opened fails and leaves nothing behind`() {
        provide("song.mp3", null, size = 16)
        assertThrows(FileNotFoundException::class.java) { importer.import(source) }
        assertTrue(target.listFiles().isNullOrEmpty())
    }

    // ── import: limits ────────────────────────────────────────

    @Test
    fun `a file declared too big is refused without reading it`() {
        provide("huge.mp3", null, size = 101)
        val failure = assertThrows(Exception::class.java) { AudioImporter(context, maxBytes = 100).import(source) }
        assertTrue(failure.message, failure !is FileNotFoundException)
        assertTrue(target.listFiles().isNullOrEmpty())
    }

    @Test
    fun `a stream longer than it claims stops at the limit and leaves nothing behind`() {
        provide("endless.mp3", audio(5000), size = 16)
        assertThrows(Exception::class.java) { AudioImporter(context, maxBytes = 1000).import(source) }
        assertTrue(target.listFiles().isNullOrEmpty())
    }

    @Test
    fun `a stream that doesn't say its size stops at the limit too`() {
        provide("endless.mp3", audio(5000), size = null)
        assertThrows(Exception::class.java) { AudioImporter(context, maxBytes = 1000).import(source) }
        assertTrue(target.listFiles().isNullOrEmpty())
    }

    @Test
    fun `a file exactly at the limit is accepted`() {
        provide("song.mp3", audio(1000))
        assertEquals(1000L, File(AudioImporter(context, maxBytes = 1000).import(source)).length())
    }

    @Test
    fun `content that isn't audio is refused and leaves nothing behind`() {
        val apk = byteArrayOf(0x50, 0x4B, 0x03, 0x04) + ByteArray(100)
        provide("song.mp3", apk)
        assertThrows(Exception::class.java) { importer.import(source) }
        assertTrue(target.listFiles().isNullOrEmpty())
    }

    // ── import: the file name ─────────────────────────────────

    private fun nameFor(name: String): String {
        provide(name, audio(4))
        return File(importer.import(source)).name
    }

    @Test
    fun `a name with path separators stays inside the Nocturne folder`() {
        provide("../../../evil.mp3", audio(4))
        val saved = File(importer.import(source))
        assertEquals(target.canonicalPath, saved.canonicalFile.parent)
        assertEquals("_.._.._evil.mp3", saved.name)
    }

    @Test
    fun `characters forbidden in file names are replaced`() {
        assertEquals("a_b_c_d_e_f_g_h_i.mp3", nameFor("a\\b:c*d?e\"f<g>h|i.mp3"))
    }

    @Test
    fun `control and text-direction characters can't disguise a name`() {
        assertEquals("a_b.mp3", nameFor("a\u0007b.mp3"))
        assertEquals("song_3pm.exe.mp3", nameFor("song‮3pm.exe"))
    }

    @Test
    fun `a blank name becomes audio and a name without extension gets one`() {
        assertEquals("audio.mp3", nameFor("   "))
        assertEquals("track.mp3", nameFor("track"))
    }

    @Test
    fun `a name made of dots becomes audio`() {
        assertEquals("audio.mp3", nameFor(".."))
        assertEquals("audio.mp3", nameFor("..."))
    }

    @Test
    fun `leading and trailing dots are dropped so nothing hides`() {
        assertEquals("hidden.mp3", nameFor(".hidden.mp3"))
        assertEquals("song.mp3", nameFor("song."))
    }

    @Test
    fun `a non-audio extension can't survive`() {
        assertEquals("evil.apk.mp3", nameFor("evil.apk"))
        assertEquals("Mr. Brown.mp3", nameFor("Mr. Brown"))
    }

    @Test
    fun `audio extensions are kept whatever their case`() {
        assertEquals("a.flac", nameFor("a.flac"))
        assertEquals("b.OPUS", nameFor("b.OPUS"))
        assertEquals("c.m4a", nameFor("c.m4a"))
    }

    @Test
    fun `a very long name is cut to what a file system accepts, keeping the extension`() {
        val name = nameFor("ə".repeat(400) + ".flac")
        assertTrue(name.endsWith(".flac"))
        assertTrue("${name.toByteArray().size} bytes", name.toByteArray().size <= 240)
    }
}
