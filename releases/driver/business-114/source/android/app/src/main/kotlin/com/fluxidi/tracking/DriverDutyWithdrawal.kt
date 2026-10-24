package com.fluxidi.tracking

internal data class DriverDutyWithdrawalResult(val status: Int, val retryAfterSeconds: Long = 0)

/** Process-local retirement queue. Never persists credentials or changes duty state. */
internal class DriverDutyWithdrawal(
  private val nowMs: () -> Long,
  private val schedule: (Long, () -> Unit) -> Unit,
  private val send: (DriverDutyLease) -> DriverDutyWithdrawalResult,
) {
  private class Pending(val lease: DriverDutyLease, val deadline: Long, var attempts: Int = 0)
  private val pending = LinkedHashMap<DriverDutyLease, Pending>()

  @Synchronized fun retire(lease: DriverDutyLease) {
    if (lease.token.isEmpty() || lease.tracking.isEmpty() || pending.containsKey(lease)) return
    val now = nowMs()
    pending.entries.removeAll { it.value.deadline <= now }
    // A burst of switches must not retain unbounded credential snapshots.
    if (pending.size >= 32) return
    val item = Pending(lease, now + 180_000)
    pending[lease] = item
    schedule(0) { attempt(item) }
  }

  private fun attempt(item: Pending) {
    synchronized(this) {
      if (pending[item.lease] !== item) return
      if (nowMs() >= item.deadline) { pending.remove(item.lease); return }
      item.attempts++
    }
    val result = try { send(item.lease) } catch (_: Exception) { DriverDutyWithdrawalResult(503) }
    synchronized(this) {
      if (pending[item.lease] !== item) return
      val retryable = result.status == 429 || result.status >= 500
      if (!retryable || item.attempts >= 4) { pending.remove(item.lease); return }
      val delay = maxOf(listOf(5_000L, 15_000L, 45_000L)[item.attempts - 1],
        result.retryAfterSeconds.coerceIn(0, 120) * 1000)
      if (nowMs() + delay >= item.deadline) { pending.remove(item.lease); return }
      schedule(delay) { attempt(item) }
    }
  }
}
