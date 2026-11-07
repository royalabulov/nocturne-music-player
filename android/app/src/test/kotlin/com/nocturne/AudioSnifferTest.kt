package com.nocturne

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioSnifferTest {
    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }
    private fun text(s: String) = s.toByteArray(Charsets.ISO_8859_1)

    @Test
    fun `tagged and container formats are recognized`() {
        for (head in listOf("ID3\u0004\u0000", "fLaC\u0000\u0000", "OggS\u0000", "MAC \u0096\u000F", "#!AMR\n", "MThd\u0000")) {
            assertTrue(head, AudioSniffer.looksLikeAudio(text(head)))
        }
    }

    @Test
    fun `WAV and AIFF need their form type too`() {
        assertTrue(AudioSniffer.looksLikeAudio(text("RIFF1234WAVEfmt ")))
        assertTrue(AudioSniffer.looksLikeAudio(text("FORM1234AIFFCOMM")))
        // RIFF is also AVI and WebP
        assertFalse(AudioSniffer.looksLikeAudio(text("RIFF1234AVI LIST")))
        assertFalse(AudioSniffer.looksLikeAudio(text("RIFF1234WEBPVP8 ")))
    }

    @Test
    fun `M4A is recognized although it starts with zeros`() {
        assertTrue(AudioSniffer.looksLikeAudio(bytes(0, 0, 0, 0x20) + text("ftypM4A ")))
    }

    @Test
    fun `MP3 and AAC without tags are recognized by their frame header`() {
        assertTrue(AudioSniffer.looksLikeAudio(bytes(0xFF, 0xFB, 0x90, 0x64))) // MPEG-1 layer 3
        assertTrue(AudioSniffer.looksLikeAudio(bytes(0xFF, 0xF1, 0x50, 0x80))) // ADTS AAC
    }

    @Test
    fun `an MP3 with padding before its first frame is recognized`() {
        assertTrue(AudioSniffer.looksLikeAudio(ByteArray(128) + bytes(0xFF, 0xFB, 0x90, 0x64)))
    }

    @Test
    fun `a sync word with reserved values is not a frame`() {
        assertFalse(AudioSniffer.looksLikeAudio(bytes(0xFF, 0xFB, 0xF0, 0x64))) // bitrate 1111
        assertFalse(AudioSniffer.looksLikeAudio(bytes(0xFF, 0xFB, 0x9C, 0x64))) // sample rate 11
        assertFalse(AudioSniffer.looksLikeAudio(bytes(0xFF, 0xEB, 0x90, 0x64))) // version 01
    }

    @Test
    fun `other file types are refused`() {
        val others = listOf(
            bytes(0x50, 0x4B, 0x03, 0x04, 0x14, 0x00), // ZIP, APK
            bytes(0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01), // ELF
            bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A), // PNG
            bytes(0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10), // JPEG
            text("SQLite format 3\u0000"),
            text("%PDF-1.7\n"),
            text("<html><body>"),
            text("{\"format\":\"sonar-backup\"}"),
        )
        for (head in others) assertFalse(String(head, Charsets.ISO_8859_1), AudioSniffer.looksLikeAudio(head))
    }

    @Test
    fun `empty, all-zero and truncated files are refused`() {
        assertFalse(AudioSniffer.looksLikeAudio(ByteArray(0)))
        assertFalse(AudioSniffer.looksLikeAudio(ByteArray(4096)))
        assertFalse(AudioSniffer.looksLikeAudio(text("ID")))
        assertFalse(AudioSniffer.looksLikeAudio(bytes(0xFF, 0xFB)))
    }

    @Test
    fun `only the bytes actually read count`() {
        val buffer = text("ID3") + ByteArray(10)
        assertTrue(AudioSniffer.looksLikeAudio(buffer, 3))
        assertFalse(AudioSniffer.looksLikeAudio(buffer, 2))
    }
}
