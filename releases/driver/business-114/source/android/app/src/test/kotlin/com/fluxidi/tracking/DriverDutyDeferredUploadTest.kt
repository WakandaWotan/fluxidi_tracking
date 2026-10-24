package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.RejectedExecutionException

class DriverDutyDeferredUploadTest {
  private class Task(val at: Long, val run: () -> Unit) { var canceled = false }
  private class Clock {
    var now = 0L
    val tasks = mutableListOf<Task>()
    var closed = false
    fun schedule(delay: Long, run: () -> Unit): () -> Unit {
      if (closed) throw RejectedExecutionException()
      val task = Task(now + delay, run)
      tasks += task
      return { task.canceled = true }
    }
    fun advance(at: Long) {
      now = at
      for (task in tasks.filter { !it.canceled && it.at <= at }.sortedBy { it.at }) {
        task.canceled = true
        task.run()
      }
    }
    fun active() = tasks.count { !it.canceled }
  }
  private data class Fix(val elapsed: Long, val capturedAt: Long, val accuracy: Float = 6f)
  private class Publisher {
    val clock = Clock()
    val life = DriverDutyLifecycle()
    var owner = begin("A")
    var policy = DriverDutyCadence()
    var latest: Fix? = null
    var attempted: Fix? = null
    var queuedOwner: DriverDutyLease? = null
    val sent = mutableListOf<Pair<Long, Fix>>()
    val deferred = DriverDutyDeferredUpload<DriverDutyLease>(life::isCurrent, clock::schedule, ::attempt)
    private fun begin(id: String) = life.begin(id, "fixture", "https://booking.example", "https://tracking.example").also { life.ready(it) }
    fun replace(id: String): DriverDutyLease {
      deferred.cancelPending()
      owner = begin(id); policy = DriverDutyCadence(); latest = null; attempted = null; queuedOwner = null
      return owner
    }
    fun stop() { life.cancel(owner.activationId, "requested_stop"); deferred.cancelPending() }
    fun seedFirstUpload() {
      latest = Fix(0, 1000000); attempted = latest
      policy.completed(200, 0f, startedAt = 100)
    }
    fun callback(fix: Fix, hasAccuracy: Boolean = true, actor: DriverDutyLease = owner) {
      if (!life.isCurrent(actor) || !DriverDutyCadence.acceptsRealFix(hasAccuracy, fix.accuracy, 50.7, 3.6,
          fix.elapsed, latest?.elapsed)) return
      latest = fix
      if (queuedOwner === actor) return
      if (policy.due(clock.now)) attempt(actor)
      else if (attempted == null || fix.elapsed > attempted!!.elapsed) deferred.defer(actor, policy.remainingDelayMs(clock.now))
    }
    @Synchronized fun releaseQueuedAndRetainNewest(actor: DriverDutyLease) {
      if (queuedOwner !== actor) return
      queuedOwner = null
      if (!life.isCurrent(actor)) return
      val fix = latest ?: return
      if (attempted == null || fix.elapsed > attempted!!.elapsed) deferred.defer(actor, policy.remainingDelayMs(clock.now))
    }
    fun attempt(actor: DriverDutyLease) {
      if (!life.isCurrent(actor) || !policy.due(clock.now)) return
      val fix = latest ?: return
      deferred.cancelPending(actor)
      attempted = fix; sent += clock.now to fix
      policy.completed(clock.now, 0f, startedAt = clock.now)
    }
  }

  @Test fun callbackJustBeforeDuePublishesAtDeadlineWithoutWaitingAnotherGpsPeriod() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000))
    assertEquals(1, p.clock.active()); assertTrue(p.sent.isEmpty())
    p.clock.advance(25099); assertTrue(p.sent.isEmpty())
    p.clock.advance(25100)
    assertEquals(listOf(25100L), p.sent.map { it.first })
    assertEquals(1025000L, p.sent.single().second.capturedAt)
    assertEquals(0, p.clock.active())
  }
  @Test fun pendingAttemptUsesNewestActualFixAndDoesNotMoveItsDeadline() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); p.clock.now = 25080
    p.callback(Fix(25075, 1025075))
    assertEquals(1, p.clock.active()); assertEquals(25100L, p.clock.tasks.single().at)
    p.clock.advance(25100)
    assertEquals(1025075L, p.sent.single().second.capturedAt)
  }
  @Test fun heartbeatWinsTheTimerRaceWithoutAnotherUploadOrTimerRenewal() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); p.clock.now = 25100
    p.attempt(p.owner); p.clock.advance(25100)
    assertEquals(1, p.sent.size); assertEquals(0, p.clock.active())
    p.clock.advance(50100); assertEquals(1, p.sent.size)
  }
  @Test fun absentInvalidOrOldFixDoesNotQueueOrReplaceThePendingRealSample() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000, 151f)); p.callback(Fix(25000, 1025000), hasAccuracy = false)
    assertEquals(0, p.clock.active())
    p.callback(Fix(25000, 1025000)); p.callback(Fix(24000, 1024000))
    p.callback(Fix(25000, 1099999))
    p.clock.advance(25100)
    assertEquals(1025000L, p.sent.single().second.capturedAt)
    val empty = Publisher(); empty.attempt(empty.owner)
    assertEquals(0, empty.clock.active()); assertTrue(empty.sent.isEmpty())
  }
  @Test fun stopCancelsTheTimerAndLateRunnableCannotPublish() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); val task = p.clock.tasks.single()
    p.stop(); assertTrue(task.canceled)
    p.clock.now = 25100; task.run()
    assertTrue(p.sent.isEmpty()); assertEquals(0, p.clock.active())
  }
  @Test fun lateOldRunnableCannotClearOrPublishTheReplacementOwnersTimer() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); val old = p.clock.tasks.single(); val a = p.owner
    p.replace("B"); p.policy.completed(25060, 0f, startedAt = 25060)
    p.clock.now = 50040; p.callback(Fix(50030, 1050030))
    assertEquals(1, p.clock.active()); old.run()
    p.callback(Fix(60000, 1060000), actor = a)
    assertEquals(1, p.clock.active()); assertTrue(p.sent.isEmpty())
    p.clock.advance(50060)
    assertEquals(1, p.sent.size); assertEquals(1050030L, p.sent.single().second.capturedAt)
  }
  @Test fun staleLeaseWithReusedActivationLabelCannotArmATimer() {
    val p = Publisher(); val old = p.owner; p.replace("A")
    assertFalse(p.deferred.defer(old, 50)); assertEquals(0, p.clock.active())
  }
  @Test fun uploadAdvancingCadenceCancelsItsOldTimerBeforeRetainingANewerFix() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); val old = p.clock.tasks.single()
    p.clock.now = 25100; p.attempt(p.owner)
    assertTrue(old.canceled); p.clock.now = 26000
    p.callback(Fix(25990, 1025990))
    assertEquals(50100L, p.clock.tasks.last().at)
    old.run(); assertEquals(1, p.clock.active()); assertEquals(1, p.sent.size)
    p.clock.advance(50100)
    assertEquals(2, p.sent.size); assertEquals(1025990L, p.sent.last().second.capturedAt)
  }
  @Test fun oldOwnerCancelCannotRemoveTheNewOwnersPendingTimer() {
    val p = Publisher(); val old = p.owner; p.replace("B")
    assertTrue(p.deferred.defer(p.owner, 50)); p.deferred.cancelPending(old)
    assertEquals(1, p.clock.active())
  }
  @Test fun realCallbackAfterUploadFinalCheckBeforeQueueReleaseIsStillPublished() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25100
    p.queuedOwner = p.owner; p.attempt(p.owner)
    // The request's finally check saw no newer fix, then the main looper
    // delivered one before the outer worker released its queue claim.
    assertEquals(0, p.clock.active()); p.clock.now = 26000
    p.callback(Fix(25990, 1025990))
    assertEquals(0, p.clock.active()); assertEquals(1, p.sent.size)
    p.releaseQueuedAndRetainNewest(p.owner)
    assertNull(p.queuedOwner); assertEquals(50100L, p.clock.tasks.last().at)
    p.clock.advance(50100)
    assertEquals(2, p.sent.size); assertEquals(1025990L, p.sent.last().second.capturedAt)
  }
  @Test fun oldQueuedCompletionCannotReleaseOrRearmTheReplacementOwnersWork() {
    val p = Publisher(); val old = p.owner; p.replace("B")
    p.seedFirstUpload(); p.queuedOwner = p.owner; p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); p.releaseQueuedAndRetainNewest(old)
    assertSame(p.owner, p.queuedOwner); assertEquals(0, p.clock.active())
    p.releaseQueuedAndRetainNewest(p.owner); p.clock.advance(25100)
    assertEquals(1, p.sent.size); assertEquals(1025000L, p.sent.single().second.capturedAt)
  }
  @Test fun rejectedSchedulerDoesNotLeaveAnUncancelablePendingSlot() {
    val p = Publisher(); p.clock.closed = true
    assertFalse(p.deferred.defer(p.owner, 50)); p.clock.closed = false
    assertTrue(p.deferred.defer(p.owner, 50)); assertEquals(1, p.clock.active())
    p.deferred.cancelPending(); assertEquals(0, p.clock.active())
  }
  @Test fun executorShutdownAndOwnershipRevocationSuppressPendingWork() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); val old = p.clock.tasks.single()
    p.stop(); p.clock.closed = true; p.clock.now = 25100; old.run()
    assertTrue(p.sent.isEmpty()); assertFalse(p.deferred.defer(p.owner, 0))
  }
  @Test fun rateLimitAndFailureBackoffRemainCompletionBased() {
    for (retry in listOf(120L, 300L)) {
      val p = Publisher(); p.policy.completed(28000, 0f, retry, startedAt = 25000)
      p.clock.now = 50000; p.callback(Fix(50000, 1050000))
      val due = 28000 + retry * 1000
      assertEquals(due, p.clock.tasks.single().at)
      p.clock.advance(due - 1); assertTrue(p.sent.isEmpty())
      p.callback(Fix(due - 1, 1000000 + due - 1))
      p.clock.advance(due); assertEquals(1, p.sent.size)
      assertEquals(1000000 + due - 1, p.sent.single().second.capturedAt)
    }
  }
  @Test fun deferredPublicationNeverIncreasesTheTwentyFiveSecondRate() {
    val p = Publisher(); p.seedFirstUpload(); p.clock.now = 25050
    p.callback(Fix(25000, 1025000)); p.clock.advance(25100)
    p.clock.now = 50050; p.callback(Fix(50000, 1050000)); p.clock.advance(50100)
    p.clock.now = 75050; p.callback(Fix(75000, 1075000)); p.clock.advance(75100)
    assertEquals(listOf(25100L, 50100L, 75100L), p.sent.map { it.first })
    assertTrue(p.sent.zipWithNext().all { (a, b) -> b.first - a.first >= 25000 })
  }
  @Test fun alreadyDueDeferredAttemptMayRunOnceWithoutCreatingAPeriodicLoop() {
    val p = Publisher(); p.latest = Fix(0, 1000000)
    assertTrue(p.deferred.defer(p.owner, 0)); p.clock.advance(0)
    assertEquals(1, p.sent.size); assertEquals(0, p.clock.active())
    p.clock.advance(100000); assertEquals(1, p.sent.size)
  }
}
