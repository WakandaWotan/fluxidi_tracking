package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverDutyWithdrawalTest {
  private class Fixture(var result: DriverDutyWithdrawalResult = DriverDutyWithdrawalResult(200)) {
    var now = 0L
    val jobs = mutableListOf<Pair<Long, () -> Unit>>()
    val calls = mutableListOf<DriverDutyLease>()
    val queue = DriverDutyWithdrawal({ now }, { delay, job -> jobs.add(delay to job) }, { lease -> calls.add(lease); result })
    fun runNext() { val (delay, job) = jobs.removeAt(0); now += delay; job() }
  }
  private fun lease(id: String = "A", token: String = "fixture-A") =
    DriverDutyLifecycle().begin(id, token, "https://booking.example", "https://tracking.example", "device-A")

  @Test fun oldActivationIsWithdrawnOnceWithItsOriginalCredentials() {
    val f = Fixture()
    val a = lease()
    f.queue.retire(a)
    f.queue.retire(a)
    assertEquals(1, f.jobs.size)
    f.runNext()
    assertSame(a, f.calls.single())
    assertEquals("fixture-A", f.calls.single().token)
    assertEquals("A", f.calls.single().activationId)
    assertEquals("device-A", f.calls.single().nativeDeviceId)
    assertTrue(f.jobs.isEmpty())
  }

  @Test fun failedOldWithdrawalCannotMutateNewDutyOrUseItsToken() {
    val f = Fixture(DriverDutyWithdrawalResult(503))
    val gate = DriverDutyLifecycle()
    val a = gate.begin("A", "fixture-A", "https://booking.example", "https://tracking.example", "device-A")
    gate.ready(a)
    gate.cancel("A", "requested_stop")
    f.queue.retire(a)
    val b = gate.begin("B", "fixture-B", "https://booking.example", "https://tracking.example", "device-A")
    gate.ready(b)
    f.runNext()
    f.result = DriverDutyWithdrawalResult(200)
    f.runNext()
    assertEquals(listOf("fixture-A", "fixture-A"), f.calls.map { it.token })
    assertTrue(gate.isCurrent(b))
    assertTrue(gate.status("B").running)
  }

  @Test fun retryCountAndLifetimeStayBoundedDuringNetworkFailure() {
    val f = Fixture(DriverDutyWithdrawalResult(503))
    f.queue.retire(lease())
    while (f.jobs.isNotEmpty()) f.runNext()
    assertEquals(4, f.calls.size)
    assertTrue(f.now < 180_000)
  }

  @Test fun serverBackoffCannotExtendBeyondTheExistingGpsExpiry() {
    val f = Fixture(DriverDutyWithdrawalResult(429, 120))
    f.queue.retire(lease())
    while (f.jobs.isNotEmpty()) f.runNext()
    assertEquals(2, f.calls.size)
    assertEquals(120_000, f.now)
  }

  @Test fun staleQueuedRetirementNeverSendsAfterItsDeadline() {
    val f = Fixture()
    f.queue.retire(lease())
    f.now = 180_000
    f.runNext()
    assertTrue(f.calls.isEmpty())
  }

  @Test fun authenticationAndOwnerMismatchResponsesAreTerminal() {
    for (code in listOf(200, 400, 401, 403, 404, 409)) {
      val f = Fixture(DriverDutyWithdrawalResult(code))
      f.queue.retire(lease())
      f.runNext()
      assertEquals(1, f.calls.size)
      assertTrue(f.jobs.isEmpty())
    }
  }

  @Test fun burstOfRetirementsHasBoundedMemoryAndNetworkWork() {
    val f = Fixture()
    repeat(100) { f.queue.retire(lease("A_$it")) }
    assertEquals(32, f.jobs.size)
  }
}
