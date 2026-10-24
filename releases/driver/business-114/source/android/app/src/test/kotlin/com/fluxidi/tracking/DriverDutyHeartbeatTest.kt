package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverDutyHeartbeatTest {
  private fun ready(gate: DriverDutyLifecycle, id: String = "A"): DriverDutyLease {
    val actor = DriverDutyActor("T", "C", "D", "V")
    val lease = gate.begin(id, "fixture-$id", "https://booking.example", "https://tracking.example", "install", actor)
    assertTrue(gate.ready(lease))
    return lease
  }

  @Test fun actualBookingBusyHeartbeatRetainsSameReadyGpsOwnerAndSchedulesNoWithdrawal() {
    // Captured from the real local Booking Worker HTTP handler with the native
    // dispatch_protocol=1 request. No credential or position is in this fixture.
    val json = checkNotNull(javaClass.getResourceAsStream("/driver_duty_busy_heartbeat.json"))
      .bufferedReader().use { it.readText() }
    val active = checkNotNull(Regex("\"is_active\"\\s*:\\s*(true|false)").find(json)).groupValues[1].toBooleanStrict()
    val availability = checkNotNull(Regex("\"availability_status\"\\s*:\\s*\"([^\"]+)\"").find(json)).groupValues[1]
    assertTrue(active); assertEquals("busy", availability)
    val gate = DriverDutyLifecycle()
    val lease = ready(gate)
    val jobs = mutableListOf<() -> Unit>()
    val withdrawals = DriverDutyWithdrawal({ 0L }, { _, job -> jobs.add(job) }, { DriverDutyWithdrawalResult(200) })
    val reason = DriverDutyHeartbeatPolicy.terminationReason(200, active, availability)
    if (reason != null && gate.finish(lease, reason, true)) withdrawals.retire(lease)
    assertTrue("canonical busy is an active ride, not the end of this GPS owner", gate.isCurrent(lease))
    assertTrue(jobs.isEmpty())
    assertTrue(gate.status(expected = DriverDutyExpectedConfig(lease.token, lease.booking, lease.tracking, lease.actor)).running)
    assertEquals("A", gate.status().activationId); assertEquals("install", gate.status().nativeDeviceId)
    assertEquals("receiving busy does not convert driver availability to available", "busy", availability)
  }

  @Test fun availableAndLegacyOnTripContinueButPausedOfflineInactiveAndRevokedWithdrawOnlyTheirOwner() {
    for (availability in listOf("available", "on_trip")) {
      assertNull(DriverDutyHeartbeatPolicy.terminationReason(200, true, availability))
    }
    val cases = listOf(Triple(200, true, "paused"), Triple(200, true, "offline"), Triple(200, false, "busy"),
      Triple(200, true, "inactive"), Triple(200, true, ""), Triple(200, true, "unknown"),
      Triple(401, true, "busy"), Triple(403, true, "busy"))
    for ((code, active, availability) in cases) {
      val gate = DriverDutyLifecycle(); val lease = ready(gate)
      val calls = mutableListOf<DriverDutyLease>(); val jobs = mutableListOf<() -> Unit>()
      val withdrawals = DriverDutyWithdrawal({ 0L }, { _, job -> jobs.add(job) }, { old -> calls.add(old); DriverDutyWithdrawalResult(200) })
      val reason = checkNotNull(DriverDutyHeartbeatPolicy.terminationReason(code, active, availability))
      assertEquals(if (code == 401 || code == 403) "session_revoked" else "availability_ended", reason)
      assertTrue(gate.finish(lease, reason, true)); withdrawals.retire(lease)
      assertFalse(gate.status().running)
      val replacement = ready(gate, "B")
      jobs.single().invoke()
      assertSame(lease, calls.single()); assertEquals("fixture-A", calls.single().token)
      assertTrue(gate.isCurrent(replacement)); assertEquals("B", gate.status().activationId)
    }
  }

  @Test fun temporaryHttpFailureDoesNotTreatAnUntrustedBodyAsAvailabilityOrRevocation() {
    for (code in listOf(408, 429, 500, 502, 503)) {
      assertNull(DriverDutyHeartbeatPolicy.terminationReason(code, false, "offline"))
      assertNull(DriverDutyHeartbeatPolicy.terminationReason(code, true, "busy"))
    }
  }
}
