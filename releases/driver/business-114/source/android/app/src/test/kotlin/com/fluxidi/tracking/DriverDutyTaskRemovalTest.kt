package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverDutyTaskRemovalTest {
  private fun begin(gate: DriverDutyLifecycle, id: String = "A") =
    gate.begin(id, "fixture-$id", "https://booking.example", "https://tracking.example", "install",
      DriverDutyActor("tenant-$id", "company-$id", "driver-$id", "vehicle-$id"))

  @Test fun removedTaskStopsReadyPublisherAndRetiresOnlyCapturedOwner() {
    val gate = DriverDutyLifecycle()
    val old = begin(gate); assertTrue(gate.ready(old))
    val jobs = mutableListOf<() -> Unit>(); val calls = mutableListOf<DriverDutyLease>()
    val queue = DriverDutyWithdrawal({ 0L }, { _, job -> jobs.add(job) }, {
      calls.add(it); DriverDutyWithdrawalResult(200)
    })
    if (gate.finish(old, "task_removed")) queue.retire(old)
    assertFalse(gate.status().running)
    assertEquals("task_removed", gate.status().reason)
    assertFalse(gate.isCurrent(old)) // queued heartbeat/GPS can no longer publish
    assertNull(gate.acceptCommand(old.activationId, old.generation, old.token, old.booking, old.tracking))
    val next = begin(gate, "B"); assertTrue(gate.ready(next))
    jobs.single().invoke()
    assertSame(old, calls.single())
    assertEquals("company-A", calls.single().actor.companyId)
    assertTrue(gate.isCurrent(next))
  }

  @Test fun removalBeforeFirstFixAlsoFencesQueuedStart() {
    val gate = DriverDutyLifecycle(); val queued = begin(gate)
    assertTrue(gate.finish(queued, "task_removed"))
    assertNull(gate.current(false))
    assertFalse(gate.ready(queued))
    assertNull(gate.acceptCommand(queued.activationId, queued.generation, queued.token, queued.booking, queued.tracking))
  }

  @Test fun oldTaskCannotStopReplacementEvenWithReusedActivationLabel() {
    val gate = DriverDutyLifecycle(); val old = begin(gate)
    assertTrue(gate.ready(old))
    val replacement = begin(gate); assertTrue(gate.ready(replacement))
    assertFalse(gate.finish(old, "task_removed"))
    assertTrue(gate.isCurrent(replacement))
  }

  @Test fun reopenRequiresNewActivationAndDuplicateRemovalCannotRetireIt() {
    val gate = DriverDutyLifecycle(); val old = begin(gate)
    assertTrue(gate.ready(old)); assertTrue(gate.finish(old, "task_removed"))
    val reopened = begin(gate, "reopened"); assertTrue(gate.ready(reopened))
    assertFalse(gate.finish(old, "task_removed"))
    assertTrue(gate.isCurrent(reopened))
    assertEquals("reopened", gate.status().activationId)
  }
}
