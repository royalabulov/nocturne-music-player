package com.nocturne

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.acos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sqrt

/// Pocket knock: knock on the phone 2 times = next song, 3 times = previous song.
/// Works only while music plays (Dart turns it on/off) and only with the screen off — the
/// touchscreen is dead in the pocket, the accelerometer still hears the knock.
///
/// Walking, a bus shaking, putting the phone in the pocket must never count. So a sequence
/// is accepted only if ALL of these hold (otherwise it is dropped silently):
///  * every knock is a strong, sharp spike: above the threshold, and its top half (≥ 50 % of
///    the peak) lasts ≤ 45 ms — a step or a bump is a weaker, wide hump,
///  * before the first knock the phone was still for 600 ms (no low-frequency motion, and the
///    spike is ≥ 6× louder than the background vibration),
///  * every knock pushes straight through the phone's flat face ([KnockAxis]) — steps don't,
///  * knocks are 160–500 ms apart and evenly spaced,
///  * after the last knock nothing shakes for a while (the next step of a walk would),
///  * the phone didn't turn during the sequence (gravity direction),
///  * exactly 2 or 3 knocks — 4+ is dropped,
///  * nothing suggests the count is wrong: a strong jolt just before the first knock, or a weak
///    one after the last, may be a knock that wasn't counted. 3 knocks read as 2 skipped the
///    wrong way, so such a sequence does nothing — better no skip than the wrong direction.
/// Pocket test (2026-11-03, Samsung): knocks peak 10–22 m/s², 250–275 ms apart, and the
/// phone bounces back in the cloth ~100–120 ms after each knock (peak ~4) — so motion right
/// after a knock is ignored. Walking peaked at 2.5–8.4 m/s², 100–535 ms wide.
///
/// Walking mode: while walking the phone is never still, so "still before" can't hold. Then a
/// knock counts only if it is a STRONG spike — above [strongThresholds] and ≥ 2× the strongest
/// jolt of the 600 ms before the sequence (the steps). Steps between the knocks are ignored as
/// long as they stay well below the knocks; a jolt near knock strength drops the sequence.
/// Pocket test 2 (walking): knocks peaked 14–60 m/s², 210–306 ms apart.
/// Every decision is logged for tuning: permanently in [KnockLog] (with the raw samples of
/// sequences and strong spikes), and to logcat: adb logcat -s NocturneKnock
object KnockDetector : SensorEventListener {
    private const val TAG = "NocturneKnock"
    private const val MS = 1_000_000L // ns

    // Thresholds (m/s²) by sensitivity: 0 = low, 1 = medium, 2 = high
    private val spikeThresholds = doubleArrayOf(12.0, 9.0, 7.0)
    // Walking mode. Was 30/22/15: walking knocks then had to be very hard (user, test 3).
    // Steps reached 7–17 m/s² but never two of them ≥ 2× the jolts before, 160–450 ms apart,
    // with nothing near that strength after.
    private val strongThresholds = doubleArrayOf(22.0, 15.0, 11.0)
    private const val WALK_RATIO = 2.0       // walking knock ≥ 2× the strongest recent step
    private const val WALK_NOISE = 0.6       // a jolt ≥ 60 % of the weakest knock drops it
    private const val SNR = 6.0              // spike ≥ 6× background vibration (RMS)
    private const val MOTION_MAX = 1.2       // low-frequency motion (walking, swinging)
    private const val MAX_SPIKE_NS = 250 * MS // whole spike incl. the bounce-back merged into it
    private const val MAX_TOP_NS = 45 * MS   // time spent above half of the peak
    private const val MIN_GAP_NS = 160 * MS  // closer than this = the bounce-back of the same knock
    private const val MIN_QUICK_KNOCK_NS = 80 * MS // closer than MIN_GAP but strong = maybe a knock
    private const val MAX_GAP_NS = 500 * MS
    private const val PRE_QUIET_NS = 600 * MS
    private const val RAW_BEFORE_SPIKE_NS = 300 * MS // raw samples logged before a lone strong spike
    private const val SETTLE_NS = 250 * MS   // the phone bounces/moves right after a knock
    private const val POST_QUIET_NS = 650 * MS // sequence ends this long after the last knock
    private const val COOLDOWN_NS = 1200 * MS
    private const val ARM_DELAY_MS = 1500L   // after the screen goes off (putting it in the pocket)
    private const val MAX_TURN_DEG = 15.0

    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())
    private var thread: HandlerThread? = null
    private var sensorHandler: Handler? = null
    private var sensors: SensorManager? = null
    private var accel: Sensor? = null

    /// 2 → next, 3 → previous. Called on the main thread.
    var onKnock: ((Int) -> Unit)? = null

    private var active = false
    private var listening = false
    private var receiverOn = false
    // Written on main, read on the sensor thread
    @Volatile private var threshold = spikeThresholds[1]
    @Volatile private var strong = strongThresholds[1]

    fun init(context: Context) {
        if (!::app.isInitialized) app = context.applicationContext
        KnockLog.init(app)
    }

    /// From Dart: on = setting enabled && music playing.
    fun update(on: Boolean, sensitivity: Int) {
        threshold = spikeThresholds[sensitivity.coerceIn(0, 2)]
        strong = strongThresholds[sensitivity.coerceIn(0, 2)]
        if (on == active) return
        active = on
        if (on) {
            registerScreenReceiver()
            if (!isInteractive()) armLater() else stopListening()
        } else {
            main.removeCallbacks(armRunnable)
            unregisterScreenReceiver()
            stopListening()
        }
        Log.i(TAG, "active=$on threshold=$threshold")
        KnockLog.write(JSONObject().put("event", "active").put("on", on).put("sensitivity", sensitivity))
    }

    // ── screen on/off ─────────────────────────────────────────

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> armLater()
                Intent.ACTION_SCREEN_ON -> {
                    main.removeCallbacks(armRunnable)
                    stopListening()
                }
            }
        }
    }

    private val armRunnable = Runnable { if (active && !isInteractive()) startListening() }

    private fun armLater() {
        main.removeCallbacks(armRunnable)
        main.postDelayed(armRunnable, ARM_DELAY_MS)
    }

    private fun isInteractive() =
        (app.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive

    private fun registerScreenReceiver() {
        if (receiverOn) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            app.registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            app.registerReceiver(screenReceiver, filter)
        }
        receiverOn = true
    }

    private fun unregisterScreenReceiver() {
        if (!receiverOn) return
        runCatching { app.unregisterReceiver(screenReceiver) }
        receiverOn = false
    }

    // ── sensor ────────────────────────────────────────────────

    private fun startListening() {
        if (listening) return
        val sm = sensors ?: (app.getSystemService(Context.SENSOR_SERVICE) as SensorManager).also { sensors = it }
        val a = accel ?: sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.also { accel = it } ?: return
        if (thread == null) {
            thread = HandlerThread("knock").also { it.start() }
            sensorHandler = Handler(thread!!.looper)
        }
        resetSignal()
        // 5000 µs = 200 Hz: a knock lasts ~10–30 ms; higher rates need an extra permission
        listening = sm.registerListener(this, a, 5000, sensorHandler)
        Log.i(TAG, "listening=$listening")
        KnockLog.write(JSONObject().put("event", "listening").put("on", listening))
    }

    private fun stopListening() {
        if (!listening) return
        sensors?.unregisterListener(this)
        listening = false
        Log.i(TAG, "listening=false")
        KnockLog.write(JSONObject().put("event", "listening").put("on", false))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ── signal ────────────────────────────────────────────────

    // Filters: fast (τ 30 ms) − raw = the knock / vibration; smooth (τ 150 ms) − gravity (τ 1 s)
    // = slow body motion (steps, swinging, braking)
    private var lastT = 0L
    private var startT = 0L
    private val fast = DoubleArray(3)
    private val smooth = DoubleArray(3)
    private val gravity = DoubleArray(3)

    // Last ~2.5 s: hp / motion for the "was it still before?" check, raw values for KnockLog
    private const val RING = 512
    private val ringT = LongArray(RING)
    private val ringHp = DoubleArray(RING)
    private val ringMotion = DoubleArray(RING)
    private val ringRaw = FloatArray(RING * 3)
    private var ringPos = 0
    private var ringCount = 0

    // Current spike (its samples, to measure how long it stays above half of the peak)
    private var inSpike = false
    private var spikeStart = 0L
    private var spikePeak = 0.0
    private var spikeAxis = 0.0 // KnockAxis.share at the peak
    private const val SPIKE_MAX_SAMPLES = 128
    private val spikeT = LongArray(SPIKE_MAX_SAMPLES)
    private val spikeHp = DoubleArray(SPIKE_MAX_SAMPLES)
    private var spikeN = 0

    // Current sequence
    private var knocks = 0
    private val knockTimes = LongArray(4)
    private val knockPeaks = DoubleArray(4)
    private var walking = false   // sequence started while the phone wasn't still
    private var weakest = 0.0     // weakest knock peak of the sequence
    private var background = 0.0  // strongest jolt of the 600 ms before the sequence
    private var doubt: String? = null // why the knock count may be wrong (→ no skip)
    private var lastStrongRejected = 0L // when a strong spike last failed to become a knock
    private val startDir = DoubleArray(3)
    private var cooldownUntil = 0L

    private fun resetSignal() {
        lastT = 0L
        ringPos = 0
        ringCount = 0
        inSpike = false
        knocks = 0
        noisy = 0
        doubt = null
        lastStrongRejected = 0L
    }

    private class Spike(val start: Long, val peak: Double, val width: Long, val top: Long, val axis: Double) {
        val desc get() = "peak=${f(peak)} width=${width / MS} top=${top / MS} ms axis=${f(axis)}"
    }

    override fun onSensorChanged(e: SensorEvent) {
        val t = e.timestamp
        val x = e.values[0].toDouble()
        val y = e.values[1].toDouble()
        val z = e.values[2].toDouble()
        if (lastT == 0L) {
            for (i in 0..2) {
                fast[i] = e.values[i].toDouble()
                smooth[i] = fast[i]
                gravity[i] = fast[i]
            }
            lastT = t
            startT = t
            return
        }
        val dt = ((t - lastT) / 1e9).coerceIn(0.0, 0.05)
        lastT = t
        val aF = 1 - exp(-dt / 0.03)
        val aS = 1 - exp(-dt / 0.15)
        val aG = 1 - exp(-dt / 1.0)
        val v = doubleArrayOf(x, y, z)
        var hp2 = 0.0
        var mo2 = 0.0
        for (i in 0..2) {
            fast[i] += aF * (v[i] - fast[i])
            smooth[i] += aS * (v[i] - smooth[i])
            gravity[i] += aG * (v[i] - gravity[i])
            val h = v[i] - fast[i]
            val m = smooth[i] - gravity[i]
            hp2 += h * h
            mo2 += m * m
        }
        val hp = sqrt(hp2)
        val motion = sqrt(mo2)

        ringT[ringPos] = t
        ringHp[ringPos] = hp
        ringMotion[ringPos] = motion
        for (i in 0..2) ringRaw[ringPos * 3 + i] = e.values[i]
        ringPos = (ringPos + 1) % RING
        if (ringCount < RING) ringCount++

        trackSpike(t, hp, KnockAxis.share(x - fast[0], y - fast[1], z - fast[2]))
        if (knocks > 0) watchSequence(t, hp)
    }

    private fun trackSpike(t: Long, hp: Double, axis: Double) {
        if (!inSpike) {
            if (hp >= threshold) {
                inSpike = true
                spikeStart = t
                spikePeak = hp
                spikeAxis = axis
                spikeN = 0
                addSpikeSample(t, hp)
            }
            return
        }
        if (hp > spikePeak) {
            spikePeak = hp
            spikeAxis = axis
        }
        addSpikeSample(t, hp)
        // Ends at 25 % of its own peak too: while walking hp never drops near the threshold,
        // and a quick 2nd knock (~190 ms) merged into the 1st one (test 4: "single knock", 143 ms)
        if (hp < max(threshold * 0.35, spikePeak * 0.25)) {
            inSpike = false
            val spike = Spike(spikeStart, spikePeak, t - spikeStart, topDuration(), spikeAxis)
            val sharp = spike.width <= MAX_SPIKE_NS && spike.top <= MAX_TOP_NS
            when {
                sharp -> onSpike(spike, t)
                // A wide hump inside a sequence = the body moved → drop it (walking: only one
                // through the flat face and near knock strength — ordinary steps are expected)
                knocks > 0 && spike.start - knockTimes[knocks - 1] >= MIN_GAP_NS &&
                    (!walking || (spike.peak >= weakest * WALK_NOISE && KnockAxis.isOnAxis(spike.axis, true))) ->
                    abort("wide_spike", spike, t)
                knocks == 0 -> rejected(spike, "wide_spike", t)
            }
        }
    }

    private fun addSpikeSample(t: Long, hp: Double) {
        if (spikeN >= SPIKE_MAX_SAMPLES) return
        spikeT[spikeN] = t
        spikeHp[spikeN] = hp
        spikeN++
    }

    /// From the first to the last sample at ≥ 50 % of the peak: short for a knock even when
    /// the bounce-back keeps the spike open, long for a step's hump.
    private fun topDuration(): Long {
        val half = spikePeak * 0.5
        var first = -1
        var last = -1
        for (i in 0 until spikeN) {
            if (spikeHp[i] >= half) {
                if (first < 0) first = i
                last = i
            }
        }
        if (spikeN >= SPIKE_MAX_SAMPLES) return Long.MAX_VALUE / 2 // didn't fit → certainly long
        return if (first < 0) 0 else spikeT[last] - spikeT[first]
    }

    private fun onSpike(spike: Spike, t: Long) {
        val start = spike.start
        val peak = spike.peak
        if (start < cooldownUntil) {
            logSpike("ignored", "cooldown", spike)
            return
        }
        if (knocks == 0) {
            if (start - startT < PRE_QUIET_NS) {
                rejected(spike, "sensor_just_started", t)
                return
            }
            val s = statsBetween(start - PRE_QUIET_NS, start - 30 * MS)
            val still = peak >= s.rms * SNR && s.maxMotion <= MOTION_MAX
            val strongKnock = peak >= strong && peak >= s.maxHp * WALK_RATIO
            if (!still && !strongKnock) {
                rejected(spike, "not_still_not_strong", t, s)
                return
            }
            if (!KnockAxis.isOnAxis(spike.axis, walking = !still)) {
                rejected(spike, "off_axis", t, s)
                return
            }
            walking = !still
            weakest = peak
            background = s.maxHp
            noisy = 0
            // A strong jolt right before: maybe a knock that wasn't counted (3 read as 2)
            doubt = if (lastStrongRejected != 0L && start - lastStrongRejected <= POST_QUIET_NS)
                "strong_spike_before" else null
            knocks = 1
            knockTimes[0] = start
            knockPeaks[0] = peak
            // Direction before the knock (the smoothed value just before it)
            for (i in 0..2) startDir[i] = smooth[i]
            logSpike("knock", "knock_1", spike, s)
            return
        }
        val gap = start - knockTimes[knocks - 1]
        val onAxis = KnockAxis.isOnAxis(spike.axis, walking)
        if (gap < MIN_GAP_NS) {
            // The bounce-back of the same knock — unless it is as strong as the knock itself
            if (onAxis && gap >= MIN_QUICK_KNOCK_NS && peak >= knockPeaks[knocks - 1] * WALK_NOISE) doubt = "quick_knock"
            logSpike("ignored", "bounce_back", spike)
            return
        }
        if (!onAxis) {
            // Walking: a step, however strong, says nothing about the knocks.
            // Still phone: something moved it → the sequence can't be trusted.
            if (walking) logSpike("ignored", "off_axis", spike) else abort("off_axis", spike, t)
            return
        }
        if (walking && (peak < strong || peak < background * WALK_RATIO)) {
            // A step between/after the knocks: fine while clearly weaker than the knocks
            if (peak >= weakest * WALK_NOISE) {
                abort("jolt_near_knock_strength", spike, t)
                return
            }
            // Stands out from the steps, though: maybe a weak knock that wasn't counted
            if (gap <= MAX_GAP_NS && peak >= background * WALK_RATIO) doubt = "weak_knock"
            logSpike("ignored", "too_weak_while_walking", spike)
            return
        }
        if (gap > MAX_GAP_NS) {
            // Too late for this sequence — but it may be the first knock of a new one
            val previous = knockTimes[knocks - 1]
            abort("knock_too_late", spike, t)
            lastStrongRejected = previous
            onSpike(spike, t)
            return
        }
        if (knocks == 3) {
            abort("more_than_3_knocks", spike, t)
            return
        }
        weakest = minOf(weakest, peak)
        noisy = 0
        knockTimes[knocks] = start
        knockPeaks[knocks] = peak
        knocks++
        logSpike("knock", "knock_$knocks", spike)
    }

    /// A spike that could not start a sequence.
    private fun rejected(spike: Spike, reason: String, t: Long, s: Stats? = null) {
        val isStrong = spike.peak >= strong
        // Only a jolt through the flat face can be an uncounted knock, not a strong step
        if (isStrong && KnockAxis.isOnAxis(spike.axis, walking = true)) lastStrongRejected = spike.start
        // Raw samples only for strong ones: the steps of a walk would fill the file
        logSpike("ignored", reason, spike, s, if (isStrong) spike.start - RAW_BEFORE_SPIKE_NS else null, t)
    }

    /// While a sequence is open. Right after a knock the phone bounces and moves in the
    /// pocket — that is ignored (SETTLE_NS). After that, smaller shaking that isn't a knock
    /// (a step, a bump) drops the sequence; POST_QUIET_NS after the last knock it is complete.
    private var noisy = 0

    private fun watchSequence(t: Long, hp: Double) {
        if (inSpike) return
        val sinceLast = t - knockTimes[knocks - 1]
        // Walking: steps shake the phone all the time — only shaking near knock strength counts
        val noiseLevel = if (walking) weakest * WALK_NOISE else threshold * 0.4
        if (sinceLast > SETTLE_NS && hp > noiseLevel && ++noisy > 4) {
            abort("shaking_after_knock", null, t)
            return
        }
        if (sinceLast < POST_QUIET_NS) return
        finish(t)
    }

    private fun finish(t: Long) {
        val count = knocks
        val turn = angleDeg(startDir, smooth)
        val gaps = (1 until count).map { knockTimes[it] - knockTimes[it - 1] }
        val reason = when {
            count < 2 -> "single_knock"
            // Walking turns the leg (and the phone) all the time → no turn check there
            !walking && turn > MAX_TURN_DEG -> "phone_turned"
            gaps.size == 2 && max(gaps[0], gaps[1]) > 2 * minOf(gaps[0], gaps[1]) -> "uneven_rhythm"
            doubt != null -> doubt
            // Still phone: a jolt too weak to be a knock may be a soft 3rd knock
            !walking && noisy >= 2 -> "weak_jolt_after_last_knock"
            else -> null
        }
        val decision = if (reason != null) "ignored" else if (count == 2) "next" else "previous"
        logDecision(decision, reason, count, turn, t)
        knocks = 0
        noisy = 0
        doubt = null
        if (reason != null) return
        cooldownUntil = t + COOLDOWN_NS
        vibrate(count)
        main.post { onKnock?.invoke(count) }
    }

    private fun abort(reason: String, spike: Spike?, t: Long) {
        logDecision("ignored", reason, knocks, angleDeg(startDir, smooth), t, spike)
        knocks = 0
        noisy = 0
        doubt = null
    }

    // ── log ───────────────────────────────────────────────────

    private fun logSpike(
        event: String, reason: String, spike: Spike, s: Stats? = null, rawFrom: Long? = null, t: Long = 0L,
    ) {
        Log.d(TAG, "$event $reason ${spike.desc}" +
            (if (s != null) " rms=${f(s.rms)} motion=${f(s.maxMotion)} maxBefore=${f(s.maxHp)}" else ""))
        val o = JSONObject().put("event", event).put("reason", reason)
            .put("threshold", threshold).put("strong", strong)
        putSpike(o, spike)
        if (s != null && s.rms != Double.MAX_VALUE) {
            o.put("rms", round(s.rms)).put("motion", round(s.maxMotion)).put("maxBefore", round(s.maxHp))
        }
        if (rawFrom != null) o.put("raw", rawSamples(rawFrom, t))
        KnockLog.write(o)
    }

    /// The outcome of a sequence, with the raw samples from just before its first knock.
    private fun logDecision(decision: String, reason: String?, count: Int, turn: Double, t: Long, spike: Spike? = null) {
        val gaps = (1 until count.coerceAtMost(3)).map { (knockTimes[it] - knockTimes[it - 1]) / MS }
        val peaks = (0 until count.coerceAtMost(3)).map { round(knockPeaks[it]) }
        Log.i(TAG, "DECISION $decision ${reason ?: ""} knocks=$count${if (walking) " (walking)" else ""} " +
            "gaps=$gaps peaks=$peaks turn=${f(turn)}° ${spike?.desc ?: ""}")
        val o = JSONObject().put("event", "decision").put("decision", decision)
            .put("reason", reason ?: JSONObject.NULL).put("knocks", count).put("walking", walking)
            .put("gapsMs", JSONArray(gaps)).put("peaks", JSONArray(peaks)).put("turn", round(turn))
            .put("background", round(background)).put("noisy", noisy)
            .put("threshold", threshold).put("strong", strong)
        if (spike != null) putSpike(o, spike)
        o.put("raw", rawSamples(knockTimes[0] - PRE_QUIET_NS, t))
        KnockLog.write(o)
    }

    private fun putSpike(o: JSONObject, spike: Spike) {
        o.put("peak", round(spike.peak)).put("widthMs", spike.width / MS).put("topMs", spike.top / MS)
            .put("axis", round(spike.axis))
    }

    /// Ring buffer samples in [from, to], oldest first: [ms since the first, x, y, z, filtered].
    private fun rawSamples(from: Long, to: Long): JSONArray {
        val out = JSONArray()
        var first = 0L
        for (k in ringCount - 1 downTo 0) {
            val i = (ringPos - 1 - k + RING) % RING
            val t = ringT[i]
            if (t < from || t > to) continue
            if (first == 0L) first = t
            out.put(
                JSONArray()
                    .put((t - first) / MS)
                    .put(round(ringRaw[i * 3].toDouble()))
                    .put(round(ringRaw[i * 3 + 1].toDouble()))
                    .put(round(ringRaw[i * 3 + 2].toDouble()))
                    .put(round(ringHp[i]))
            )
        }
        return out
    }

    private fun round(d: Double) = Math.round(d * 100) / 100.0

    private class Stats(val rms: Double, val maxMotion: Double, val maxHp: Double)

    /// RMS and max of hp, and max motion over [from, to] from the ring buffer.
    private fun statsBetween(from: Long, to: Long): Stats {
        var sum = 0.0
        var n = 0
        var maxMotion = 0.0
        var maxHp = 0.0
        for (k in 0 until ringCount) {
            val i = (ringPos - 1 - k + RING) % RING
            val t = ringT[i]
            if (t < from) break
            if (t > to) continue
            sum += ringHp[i] * ringHp[i]
            maxMotion = max(maxMotion, ringMotion[i])
            maxHp = max(maxHp, ringHp[i])
            n++
        }
        // Too few samples (sensor just started) → neither "still" nor "strong"
        if (n < 20) return Stats(Double.MAX_VALUE, Double.MAX_VALUE, Double.MAX_VALUE)
        return Stats(sqrt(sum / n), maxMotion, maxHp)
    }

    private fun angleDeg(a: DoubleArray, b: DoubleArray): Double {
        val na = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
        val nb = sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2])
        if (na < 1e-6 || nb < 1e-6) return 0.0
        val c = ((a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (na * nb)).coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(c))
    }

    /// 1 short buzz = next, 2 = previous — so it's felt in the pocket that it worked.
    private fun vibrate(count: Int) {
        val vib: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
            (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            app.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vib == null || !vib.hasVibrator()) return
        val pattern = if (count == 2) longArrayOf(0, 40) else longArrayOf(0, 40, 120, 40)
        if (Build.VERSION.SDK_INT >= 26) {
            vib.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, -1)
        }
    }

    private fun f(d: Double) = if (d == Double.MAX_VALUE) "∞" else String.format(java.util.Locale.US, "%.2f", d)
}
