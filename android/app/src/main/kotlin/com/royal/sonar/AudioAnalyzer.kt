package com.royal.sonar

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/// Smart groups: decodes a few parts of a song to PCM and runs them through YAMNet
/// (fully offline). Result: mean scores of music-related classes +
/// loudness (RMS dBFS). Genre/mood decisions are made on the Dart side (vibe_classifier).
class AudioAnalyzer(private val context: Context) {
    companion object {
        private const val MODEL = "yamnet.tflite"
        private const val LABELS = "yamnet_labels.txt"
        private const val SAMPLE_RATE = 16000
        private const val SEGMENT_SECONDS = 10
        private const val FRAMES_PER_SEGMENT = 3
        private val EXTRA = setOf("Speech", "Singing", "Rapping", "Music")
    }

    private val labels: List<String> by lazy {
        context.assets.open(LABELS).bufferedReader().readLines()
    }

    /// Only music genres/moods (Pop music … Scary music) + a few extras.
    private val wanted: List<Int> by lazy {
        val first = labels.indexOf("Pop music")
        val last = labels.indexOf("Scary music")
        labels.indices.filter { (it in first..last) || labels[it] in EXTRA }
    }

    private var interp: Interpreter? = null

    private val interpreter: Interpreter
        get() = interp ?: run {
            val fd = context.assets.openFd(MODEL)
            val model = FileInputStream(fd.fileDescriptor).channel
                .map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
            Interpreter(model, Interpreter.Options().setNumThreads(2))
        }.also { interp = it }

    private val frameLen by lazy { interpreter.getInputTensor(0).shape().last() } // 15600 = 0.975 s
    private val classes by lazy { interpreter.getOutputTensor(0).shape().last() } // 521

    /// Result: YAMNet scores + RMS + the segments themselves (16 kHz mono) —
    /// tempo/key analysis happens on the Dart side (music_features.dart).
    @Synchronized
    fun analyze(path: String, durationMs: Long): Map<String, Any> {
        val segments = decodeSegments(path, durationMs)
        if (segments.isEmpty()) error("no audio decoded")

        val input = ByteBuffer.allocateDirect(frameLen * 4).order(ByteOrder.nativeOrder())
        val output = ByteBuffer.allocateDirect(classes * 4).order(ByteOrder.nativeOrder())
        val sum = DoubleArray(classes)
        var frames = 0
        var sq = 0.0
        var n = 0L
        for (seg in segments) {
            for (s in seg) sq += s * s
            n += seg.size
            // FRAMES_PER_SEGMENT YAMNet windows spread evenly across each segment
            val count = max(1, min(FRAMES_PER_SEGMENT, seg.size / frameLen))
            val span = max(seg.size - frameLen, 0)
            for (f in 0 until count) {
                val start = if (count == 1) 0 else (span.toLong() * f / (count - 1)).toInt()
                input.clear()
                for (i in 0 until frameLen) input.putFloat(if (start + i < seg.size) seg[start + i] else 0f)
                input.rewind()
                output.clear()
                interpreter.run(input, output)
                output.rewind()
                for (c in 0 until classes) sum[c] += output.float.toDouble()
                frames++
            }
        }
        val rms = sqrt(sq / max(n, 1L))
        val scores = HashMap<String, Double>()
        for (i in wanted) scores[labels[i]] = sum[i] / frames
        return mapOf(
            "scores" to scores,
            "rmsDb" to 20 * log10(max(rms, 1e-6)),
            "windows" to frames,
            "sampleRate" to SAMPLE_RATE,
            "segments" to segments,
        )
    }

    /// Contiguous SEGMENT_SECONDS-long parts from the 25% / 50% / 75% points of the
    /// song (one part for short songs), 16 kHz mono. 1-second windows are too short
    /// for tempo and key — hence contiguous segments.
    private fun decodeSegments(path: String, durationMs: Long): List<FloatArray> {
        val ex = MediaExtractor()
        ex.setDataSource(path)
        val track = (0 until ex.trackCount).firstOrNull {
            ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: run { ex.release(); error("no audio track") }
        ex.selectTrack(track)
        val fmt = ex.getTrackFormat(track)
        val durUs = if (fmt.containsKey(MediaFormat.KEY_DURATION)) fmt.getLong(MediaFormat.KEY_DURATION)
        else durationMs * 1000
        val codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
        val out = ArrayList<FloatArray>()
        try {
            codec.configure(fmt, null, null, 0)
            codec.start()
            val pcm = PcmState(
                rate = fmt.getIntOr(MediaFormat.KEY_SAMPLE_RATE, 44100),
                channels = fmt.getIntOr(MediaFormat.KEY_CHANNEL_COUNT, 2),
            )
            val positions = if (durUs < 40_000_000) listOf(0.1) else listOf(0.25, 0.5, 0.75)
            for (p in positions) {
                ex.seekTo((durUs * p).toLong(), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                codec.flush()
                val mono = readMono(ex, codec, pcm, SEGMENT_SECONDS) ?: continue
                out.add(resample(mono, pcm.rate))
            }
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
            ex.release()
        }
        return out
    }

    private class PcmState(var rate: Int, var channels: Int, var float: Boolean = false)

    /// [seconds] of mono PCM from the seek point (at the source sample rate).
    private fun readMono(ex: MediaExtractor, codec: MediaCodec, pcm: PcmState, seconds: Int): FloatArray? {
        val info = MediaCodec.BufferInfo()
        var acc = FloatArray(0)
        var size = 0
        var inputDone = false
        var spins = 0
        fun needed() = pcm.rate * seconds
        while (size < needed() && spins++ < 20_000) {
            if (!inputDone) {
                val ii = codec.dequeueInputBuffer(10_000)
                if (ii >= 0) {
                    val buf = codec.getInputBuffer(ii)!!
                    val n = ex.readSampleData(buf, 0)
                    if (n < 0) {
                        codec.queueInputBuffer(ii, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(ii, 0, n, ex.sampleTime, 0)
                        ex.advance()
                    }
                }
            }
            val oi = codec.dequeueOutputBuffer(info, 10_000)
            if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val of = codec.outputFormat
                pcm.rate = of.getIntOr(MediaFormat.KEY_SAMPLE_RATE, pcm.rate)
                pcm.channels = of.getIntOr(MediaFormat.KEY_CHANNEL_COUNT, pcm.channels)
                pcm.float = of.getIntOr(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT) ==
                    AudioFormat.ENCODING_PCM_FLOAT
            } else if (oi >= 0) {
                val ob = codec.getOutputBuffer(oi)!!
                ob.position(info.offset)
                ob.limit(info.offset + info.size)
                ob.order(ByteOrder.LITTLE_ENDIAN)
                val ch = max(pcm.channels, 1)
                val frames = info.size / (ch * if (pcm.float) 4 else 2)
                if (size + frames > acc.size) acc = acc.copyOf(max(acc.size * 2, size + frames))
                if (pcm.float) {
                    val fb = ob.asFloatBuffer()
                    for (f in 0 until frames) {
                        var s = 0f
                        for (c in 0 until ch) s += fb.get()
                        acc[size++] = s / ch
                    }
                } else {
                    val sb = ob.asShortBuffer()
                    for (f in 0 until frames) {
                        var s = 0f
                        for (c in 0 until ch) s += sb.get() / 32768f
                        acc[size++] = s / ch
                    }
                }
                codec.releaseOutputBuffer(oi, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        }
        return if (size == 0) null else acc.copyOf(size)
    }

    /// To 16 kHz: first a ~7 kHz low-pass (windowed-sinc FIR) — otherwise sounds above
    /// 8 kHz (cymbals, hi-hats) "fold" into lower frequencies and spoil the key
    /// analysis — then linear interpolation.
    private fun resample(src: FloatArray, srcRate: Int): FloatArray {
        val filtered = if (srcRate > SAMPLE_RATE) lowPass(src, 7000.0 / srcRate) else src
        val outLen = (filtered.size.toLong() * SAMPLE_RATE / srcRate).toInt()
        val out = FloatArray(outLen)
        val step = srcRate.toDouble() / SAMPLE_RATE
        for (i in 0 until outLen) {
            val pos = i * step
            val j = pos.toInt()
            if (j >= filtered.size - 1) {
                if (j < filtered.size) out[i] = filtered[j]
                break
            }
            val frac = (pos - j).toFloat()
            out[i] = (filtered[j] * (1 - frac) + filtered[j + 1] * frac).coerceIn(-1f, 1f)
        }
        return out
    }

    /// [cutoff] = cutoff frequency / sample rate (0..0.5). 31 taps, Hann window.
    private fun lowPass(x: FloatArray, cutoff: Double): FloatArray {
        val taps = 31
        val mid = taps / 2
        val h = FloatArray(taps) { i ->
            val k = i - mid
            val sinc = if (k == 0) 2 * cutoff else kotlin.math.sin(2 * Math.PI * cutoff * k) / (Math.PI * k)
            val w = 0.5 - 0.5 * kotlin.math.cos(2 * Math.PI * i / (taps - 1))
            (sinc * w).toFloat()
        }
        val norm = h.sum()
        for (i in h.indices) h[i] /= norm
        val y = FloatArray(x.size)
        for (n in x.indices) {
            var acc = 0f
            for (t in 0 until taps) {
                val idx = n - t + mid
                if (idx in x.indices) acc += h[t] * x[idx]
            }
            y[n] = acc
        }
        return y
    }

    private fun MediaFormat.getIntOr(key: String, def: Int) =
        if (containsKey(key)) getInteger(key) else def

    @Synchronized
    fun close() {
        interp?.close()
        interp = null
    }
}
