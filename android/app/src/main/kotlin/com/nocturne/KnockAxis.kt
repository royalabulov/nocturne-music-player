package com.nocturne

import kotlin.math.abs
import kotlin.math.sqrt

/// A knock pushes the phone straight through its flat face (screen/back = the sensor's z axis);
/// a step spreads the jolt over several axes. Peak strength can't tell them apart: steps reached
/// ~26 m/s² in the pocket, as strong as knocks. In the real log (2026-11-05) knocks had a z share
/// of 0.99, jolts of a walk 0.81; the 11 skips of a morning walk without any knock all had at
/// least one jolt below 0.90.
object KnockAxis {
    /// Walking shakes the phone all the time, so the bar is higher than on a still phone.
    const val MIN_SHARE_WALKING = 0.90
    const val MIN_SHARE_STILL = 0.85

    /// Part of the jolt (0..1) along the axis through the phone's flat face.
    fun share(x: Double, y: Double, z: Double): Double {
        val size = sqrt(x * x + y * y + z * z)
        return if (size == 0.0) 0.0 else abs(z) / size
    }

    fun isOnAxis(share: Double, walking: Boolean): Boolean =
        share >= if (walking) MIN_SHARE_WALKING else MIN_SHARE_STILL
}
