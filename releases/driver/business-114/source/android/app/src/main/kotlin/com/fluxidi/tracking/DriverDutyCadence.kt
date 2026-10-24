package com.fluxidi.tracking
/** Dispatch uploads follow real GPS callbacks, separate from active ride GPS. */
class DriverDutyCadence {
  companion object {
    internal fun acceptsRealFix(hasAccuracy: Boolean, accuracy: Float, latitude: Double, longitude: Double,
      elapsedNanos: Long, previousElapsedNanos: Long?): Boolean =
      hasAccuracy && accuracy.isFinite() && accuracy >= 0 && accuracy <= 150 && latitude.isFinite() && longitude.isFinite()
        && (previousElapsedNanos == null || elapsedNanos > previousElapsedNanos)
  }
  private var nextAt = 0L
  fun due(now: Long) = now >= nextAt
  fun remainingDelayMs(now: Long) = (nextAt - now).coerceAtLeast(0L)
  fun completed(now: Long, speed: Float, retrySeconds: Long = 0, startedAt: Long = now) {
    // Smart road-access proof expires after 30s, also at standstill.
    // Publish a real fix every 25s; never re-date an older GPS sample.
    val interval = 25L
    val retry = retrySeconds.coerceIn(0, 3600)
    // A successful request must not push the next 25s GPS callback past due.
    // Server backoff still starts after completion, without early retries.
    val base = if (retry > 0) now else minOf(startedAt, now)
    nextAt = base + maxOf(interval, retry) * 1000
  }
}

/** One cancelable callback retry on the publisher's existing executor. */
internal class DriverDutyDeferredUpload<Owner : Any>(
  private val isCurrent: (Owner) -> Boolean,
  private val scheduleTask: (Long, () -> Unit) -> (() -> Unit),
  private val attempt: (Owner) -> Unit,
) {
  private class Pending<Owner>(val owner: Owner) {
    var cancel: (() -> Unit)? = null
  }
  private var pending: Pending<Owner>? = null

  @Synchronized fun defer(owner: Owner, delayMs: Long): Boolean {
    if (delayMs < 0 || !isCurrent(owner)) return false
    if (pending?.owner === owner) return true
    cancelPending()
    val slot = Pending(owner)
    pending = slot
    try {
      val cancel = scheduleTask(delayMs) { fire(slot) }
      if (pending === slot) slot.cancel = cancel else cancel()
    } catch (_: java.util.concurrent.RejectedExecutionException) {
      if (pending === slot) pending = null
      return false
    }
    return true
  }

  private fun fire(slot: Pending<Owner>) {
    val current = synchronized(this) {
      if (pending !== slot) false else {
        pending = null
        isCurrent(slot.owner)
      }
    }
    // The upload itself also checks ownership before every network write.
    if (current) attempt(slot.owner)
  }

  @Synchronized fun cancelPending(owner: Owner? = null) {
    val previous = pending
    if (owner != null && previous?.owner !== owner) return
    pending = null
    previous?.cancel?.invoke()
  }
}
