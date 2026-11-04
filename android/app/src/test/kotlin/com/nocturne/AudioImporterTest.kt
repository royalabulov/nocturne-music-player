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
import org.junit.Ignore
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

    /// A provider we don't know can claim any path here, including our own private files.
    /// Nothing is copied from that path today (audio_import.dart only uses public ones),
    /// but the value should not get that far. Enable with the fix in AudioImporter.resolve.
    @Ignore("Known issue: the _data column of an untrusted provider is believed")
    @Test
    fun `resolve must not believe the data column of an unknown provider`() {
        val privateFile = tmp.newFile("sonar.sqlite")
        FakeAudioProvider.columns = mapOf(MediaStore.MediaColumns.DATA to privateFile.absolutePath)
        assertNull(importer.resolve(source).path)
    }

    // ── import ────────────────────────────────────────────────

    @Test
    fun `import copies the content into the Nocturne folder`() {
        val content = ByteArray(1024) { it.toByte() }
        provide("song.mp3", content)
        val saved = File(importer.import(source))
        assertEquals(File(target, "song.mp3").absolutePath, saved.absolutePath)
        assertArrayEquals(content, saved.readBytes())
    }

    @Test
    fun `a name with path separators stays inside the Nocturne folder`() {
        provide("../../../evil.mp3", ByteArray(4))
        val saved = File(importer.import(source))
        assertEquals(target.canonicalPath, saved.canonicalFile.parent)
        assertEquals(".._.._.._evil.mp3", saved.name)
    }

    @Test
    fun `characters forbidden in file names are replaced`() {
        provide("a\\b:c*d?e\"f<g>h|i.mp3", ByteArray(4))
        assertEquals("a_b_c_d_e_f_g_h_i.mp3", File(importer.import(source)).name)
    }

    @Test
    fun `a blank name becomes audio and a name without extension gets one`() {
        provide("   ", ByteArray(4))
        assertEquals("audio.mp3", File(importer.import(source)).name)
        provide("track", ByteArray(5))
        assertEquals("track.mp3", File(importer.import(source)).name)
    }

    @Test
    fun `sharing the same file twice does not copy it again`() {
        provide("song.mp3", ByteArray(16))
        val first = importer.import(source)
        val second = importer.import(source)
        assertEquals(first, second)
        assertEquals(1, target.listFiles()!!.size)
    }

    @Test
    fun `a different file with the same name does not overwrite the first`() {
        val original = ByteArray(16) { 1 }
        provide("song.mp3", original)
        val first = File(importer.import(source))

        provide("song.mp3", ByteArray(32) { 2 })
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
}
