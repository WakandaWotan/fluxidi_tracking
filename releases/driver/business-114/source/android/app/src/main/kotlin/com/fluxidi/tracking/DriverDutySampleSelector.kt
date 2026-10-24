package com.fluxidi.tracking

import kotlin.math.*

/** Original measurement and its local delivery metadata; never a synthetic fix. */
internal data class DriverDutyLocationSample<T>(
  val value: T,
  val latitude: Double,
  val longitude: Double,
  val capturedAtMillis: Long,
  val elapsedRealtimeNanos: Long,
  val accuracyMeters: Float,
  val source: String,
  val receivedAtMillis: Long,
  val deliveryKind: String = "callback",
) {
  fun ageMillis(nowMillis: Long, nowElapsedNanos: Long): Long =
    maxOf(nowMillis - capturedAtMillis, (nowElapsedNanos - elapsedRealtimeNanos) / 1_000_000L)

  fun quality(nowMillis: Long, nowElapsedNanos: Long): String = when {
    ageMillis(nowMillis, nowElapsedNanos) > DriverDutySampleSelector.FRESH_MS -> "unavailable"
    accuracyMeters <= 25f -> "high"
    accuracyMeters <= 50f -> "medium"
    else -> "low"
  }
}

/** One owner-local chosen fix, plus at most one newer real fallback for expiry. */
internal class DriverDutySampleSelector<T> {
  companion object {
    // Existing Smart freshness and native ingress/cache limits, not new road gates.
    const val FRESH_MS = 30_000L
    const val MAX_AGE_MS = 150_000L
  }
  data class Decision<T>(
    val before: DriverDutyLocationSample<T>?,
    val selected: DriverDutyLocationSample<T>?,
    val reason: String,
    val accepted: Boolean,
  )
  private var best: DriverDutyLocationSample<T>? = null
  private var fallback: DriverDutyLocationSample<T>? = null

  private fun valid(sample: DriverDutyLocationSample<T>, wall: Long, elapsed: Long): Boolean =
    sample.latitude.isFinite() && sample.latitude in -90.0..90.0 &&
      sample.longitude.isFinite() && sample.longitude in -180.0..180.0 &&
      sample.accuracyMeters.isFinite() && sample.accuracyMeters in 0f..150f &&
      sample.capturedAtMillis > 0 && sample.capturedAtMillis <= wall &&
      sample.elapsedRealtimeNanos >= 0 && sample.elapsedRealtimeNanos <= elapsed &&
      sample.ageMillis(wall, elapsed) <= MAX_AGE_MS

  private fun newer(a: DriverDutyLocationSample<T>, b: DriverDutyLocationSample<T>): Boolean =
    a.capturedAtMillis > b.capturedAtMillis && a.elapsedRealtimeNanos > b.elapsedRealtimeNanos

  fun selected(wall: Long, elapsed: Long): DriverDutyLocationSample<T>? {
    val old = best
    val next = fallback
    if (old != null && next != null && newer(next, old) && valid(next, wall, elapsed) &&
        (!valid(old, wall, elapsed) || old.ageMillis(wall, elapsed) > FRESH_MS)) best = next
    return best?.takeIf { valid(it, wall, elapsed) }
  }

  fun offer(sample: DriverDutyLocationSample<T>, wall: Long, elapsed: Long): Decision<T> {
    val before = selected(wall, elapsed)
    if (!valid(sample, wall, elapsed)) return Decision(before, before, "invalid_or_expired", false)
    // Keep the capture watermark even after its selected fix expires. Never go back.
    val previous = fallback ?: best
    if (previous != null && !newer(sample, previous)) {
      val duplicate = sample.capturedAtMillis == previous.capturedAtMillis &&
        sample.elapsedRealtimeNanos == previous.elapsedRealtimeNanos
      return Decision(before, before, if (duplicate) "duplicate_capture" else "out_of_order_capture", false)
    }
    if (fallback == null || newer(sample, fallback!!)) fallback = sample
    if (before == null) {
      best = sample
      return Decision(before, sample, "first_usable_fix", true)
    }
    val freshBefore = before.ageMillis(wall, elapsed) <= FRESH_MS
    val freshNew = sample.ageMillis(wall, elapsed) <= FRESH_MS
    val reason = when {
      !freshBefore -> "newer_fix_after_expiry"
      !freshNew -> return Decision(before, before, "retain_recent_fix", true)
      sample.accuracyMeters <= before.accuracyMeters -> "newer_equal_or_better_accuracy"
      distanceMeters(before, sample) > before.accuracyMeters + sample.accuracyMeters -> "newer_disjoint_position"
      else -> return Decision(before, before, "retain_recent_better_accuracy", true)
    }
    best = sample
    return Decision(before, sample, reason, true)
  }

  /** Arm only the existing callback deadline, including a retained real fallback. */
  fun pendingSelectionDelayMs(attemptedElapsed: Long?, wall: Long, elapsed: Long): Long? {
    val current = selected(wall, elapsed) ?: return null
    if (attemptedElapsed == null || current.elapsedRealtimeNanos > attemptedElapsed) return 0L
    val next = fallback ?: return null
    if (!newer(next, current) || next.elapsedRealtimeNanos <= attemptedElapsed || !valid(next, wall, elapsed)) return null
    return (FRESH_MS + 1L - current.ageMillis(wall, elapsed)).coerceAtLeast(0L)
  }

  private fun distanceMeters(a: DriverDutyLocationSample<T>, b: DriverDutyLocationSample<T>): Double {
    val latA = Math.toRadians(a.latitude)
    val latB = Math.toRadians(b.latitude)
    val dLat = latB - latA
    val dLon = Math.toRadians(b.longitude - a.longitude)
    val h = sin(dLat / 2).pow(2) + cos(latA) * cos(latB) * sin(dLon / 2).pow(2)
    return 6_371_000.0 * 2.0 * asin(sqrt(h.coerceIn(0.0, 1.0)))
  }
}
