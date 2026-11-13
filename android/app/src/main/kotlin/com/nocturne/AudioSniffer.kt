package com.nocturne

/// Does this look like an audio file? Checked before a file from another app is copied to
/// the shared Music folder. It stops accidents and lazy abuse (an APK or a ZIP shared as
/// audio), not a determined attacker: anything can start with the right bytes. That's fine,
/// because the file is only ever played, and the name always gets an audio extension.
internal object AudioSniffer {
    /// How much of the file is needed to decide.
    const val HEAD_BYTES = 4096

    private val magic = listOf(
        "ID3", "fLaC", "OggS", "MAC ", "ADIF", "#!AMR", "MThd", "wvpk", "TTA1", "MPCK", "MP+",
        "DSD ", "FRM8", "caff", "APETAGEX",
    ).map { it.toByteArray(Charsets.US_ASCII) }

    private val asf = intArrayOf(0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11)
    private val matroska = intArrayOf(0x1A, 0x45, 0xDF, 0xA3)
    private val ac3 = intArrayOf(0x0B, 0x77)

    fun looksLikeAudio(head: ByteArray, size: Int = head.size): Boolean {
        // MP4/M4A: the box size comes first (it starts with zeros), then "ftyp"
        if (head.hasText(4, "ftyp", size)) return true
        // Some MP3s start with padding
        var i = 0
        while (i < size && head[i] == 0.toByte()) i++
        if (i == size) return false
        return magic.any { head.startsWith(it, i, size) } ||
            head.hasText(i, "RIFF", size) && (head.hasText(i + 8, "WAVE", size) || head.hasText(i + 8, "RMP3", size)) ||
            head.hasText(i, "RF64", size) && head.hasText(i + 8, "WAVE", size) ||
            head.hasText(i, "FORM", size) && (head.hasText(i + 8, "AIFF", size) || head.hasText(i + 8, "AIFC", size)) ||
            head.hasBytes(i, asf, size) || head.hasBytes(i, matroska, size) || head.hasBytes(i, ac3, size) ||
            isMpegFrame(head, i, size) || isAdtsFrame(head, i, size)
    }

    /// MP3 without tags: 11 sync bits, then values that aren't "reserved".
    private fun isMpegFrame(b: ByteArray, i: Int, size: Int): Boolean {
        if (i + 2 >= size || b[i].toInt() and 0xFF != 0xFF) return false
        val b1 = b[i + 1].toInt() and 0xFF
        val b2 = b[i + 2].toInt() and 0xFF
        val version = (b1 shr 3) and 0x3
        val layer = (b1 shr 1) and 0x3
        val bitrate = b2 shr 4
        val sampleRate = (b2 shr 2) and 0x3
        return b1 and 0xE0 == 0xE0 && version != 1 && layer != 0 && bitrate != 15 && sampleRate != 3
    }

    /// Raw AAC: 12 sync bits, layer 0, a known sample rate.
    private fun isAdtsFrame(b: ByteArray, i: Int, size: Int): Boolean {
        if (i + 2 >= size || b[i].toInt() and 0xFF != 0xFF) return false
        val b1 = b[i + 1].toInt() and 0xFF
        val sampleRate = ((b[i + 2].toInt() and 0xFF) shr 2) and 0xF
        return b1 and 0xF6 == 0xF0 && sampleRate < 13
    }

    private fun ByteArray.startsWith(prefix: ByteArray, at: Int, size: Int): Boolean {
        if (at + prefix.size > size) return false
        return prefix.indices.all { this[at + it] == prefix[it] }
    }

    private fun ByteArray.hasText(at: Int, text: String, size: Int) =
        startsWith(text.toByteArray(Charsets.US_ASCII), at, size)

    private fun ByteArray.hasBytes(at: Int, bytes: IntArray, size: Int): Boolean {
        if (at + bytes.size > size) return false
        return bytes.indices.all { this[at + it].toInt() and 0xFF == bytes[it] }
    }
}
