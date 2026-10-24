package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverDutySampleSelectorTest {
  private val wall = 1_800_000_000_000L
  private val elapsed = 1_000_000_000_000L
  private fun fix(age: Long = 2_000, accuracy: Float = 10f, source: String = "gps",
    latitude: Double = 50.7, longitude: Double = 3.6, kind: String = "callback", value: String = source) =
    DriverDutyLocationSample(value, latitude, longitude, wall-age, elapsed-age*1_000_000L,
      accuracy, source, wall, kind)
  private fun choose(vararg samples: DriverDutyLocationSample<String>): DriverDutySampleSelector<String> =
    DriverDutySampleSelector<String>().also { policy -> samples.forEach { policy.offer(it, wall, elapsed) } }

  @Test fun goodGpsThenWorseNetworkRetainsBestRecentFix() {
    val gps = fix(8_000,10f); val network = fix(2_000,100f,"network")
    val p = choose(gps); val d = p.offer(network,wall,elapsed)
    assertTrue(d.accepted); assertSame(gps,d.before); assertSame(gps,d.selected)
    assertEquals("retain_recent_better_accuracy",d.reason)
  }
  @Test fun worseNetworkThenNewerGoodGpsReplacesIt() {
    val p=choose(fix(12_000,100f,"network")); val gps=fix(5_000,10f)
    assertSame(gps,p.offer(gps,wall,elapsed).selected)
  }
  @Test fun oldAccurateThenFreshAcceptableReplacesIt() {
    val p=choose(fix(40_000,10f)); val fresh=fix(3_000,25f)
    assertSame(fresh,p.offer(fresh,wall,elapsed).selected)
  }
  @Test fun staleAccurateThenFreshCoarseKeepsOriginalCoarseAccuracy() {
    val p=choose(fix(40_000,10f)); val fresh=fix(3_000,100f,"network")
    val selected=p.offer(fresh,wall,elapsed).selected!!
    assertSame(fresh,selected); assertEquals(100f,selected.accuracyMeters,0f)
    assertEquals("low",selected.quality(wall,elapsed))
  }
  @Test fun outOfOrderBetterCallbackCannotRewindCapture() {
    val current=fix(15_000,20f); val p=choose(current)
    val d=p.offer(fix(20_000,8f),wall,elapsed)
    assertFalse(d.accepted); assertEquals("out_of_order_capture",d.reason); assertSame(current,d.selected)
  }
  @Test fun delayedCallbackCannotRewindNewerAcceptedFallbackWatermark() {
    val p=choose(fix(12_000,10f),fix(5_000,100f,"network"))
    val d=p.offer(fix(7_000,5f),wall,elapsed)
    assertFalse(d.accepted); assertEquals("out_of_order_capture",d.reason)
    assertEquals(wall-12_000,d.selected!!.capturedAtMillis)
  }
  @Test fun duplicateCallbackCannotMutateAccuracyOrCapture() {
    val current=fix(5_000,20f); val p=choose(current)
    val d=p.offer(fix(5_000,8f),wall,elapsed)
    assertFalse(d.accepted); assertEquals("duplicate_capture",d.reason); assertSame(current,d.selected)
  }
  @Test fun coldStartLastKnownIsTemporaryAndFreshGoodFixWins() {
    val cached=fix(100_000,10f,"network",kind="last_known")
    val p=choose(cached); assertEquals("unavailable",p.selected(wall,elapsed)!!.quality(wall,elapsed))
    val good=fix(3_000,10f); assertSame(good,p.offer(good,wall,elapsed).selected)
    assertSame(good,p.offer(fix(1_000,100f,"network"),wall,elapsed).selected)
  }
  @Test fun coldStartWithoutFixHasNoSyntheticOrigin() {
    assertNull(DriverDutySampleSelector<String>().selected(wall,elapsed))
  }
  @Test fun foregroundToBackgroundUsesTheSameOwnedSelection() {
    val p=choose(fix(8_000,10f)); val chosen=p.selected(wall,elapsed)
    // The service remains the owner in either UI mode; no second weaker policy.
    assertSame(chosen,p.offer(fix(2_000,100f,"network"),wall,elapsed).selected)
  }
  @Test fun backgroundToForegroundUsesTheSameOwnedSelection() {
    val p=choose(fix(8_000,10f,"gps",value="background-fix"))
    val next=fix(1_000,8f,"gps",value="foreground-fix")
    assertSame(next,p.offer(next,wall,elapsed).selected)
  }
  @Test fun heartbeatReadsChosenFixInsteadOfLastCallback() {
    val good=fix(8_000,10f); val p=choose(good,fix(2_000,100f,"network"))
    val heartbeat=p.selected(wall+5_000,elapsed+5_000_000_000L)!!
    assertSame(good,heartbeat); assertEquals(wall-8_000,heartbeat.capturedAtMillis)
    assertEquals(13_000L,heartbeat.ageMillis(wall+5_000,elapsed+5_000_000_000L))
  }
  @Test fun bestFixSurvivesMultipleLaterWorseCallbacks() {
    val good=fix(15_000,10f); val p=choose(good)
    for (age in listOf(12_000L,8_000L,2_000L))
      assertSame(good,p.offer(fix(age,100f,"network"),wall,elapsed).selected)
  }
  @Test fun capturedAtAndCoordinatesAreNeverLaundered() {
    val good=fix(12_000,10f); val p=choose(good,fix(5_000,100f,"network"))
    val selected=p.selected(wall+1_000,elapsed+1_000_000_000L)!!
    assertEquals(good,selected); assertEquals(wall-12_000,selected.capturedAtMillis)
    assertEquals(50.7,selected.latitude,0.0); assertEquals(3.6,selected.longitude,0.0)
  }
  @Test fun expiryPromotesTheRetainedRealFallbackWithoutNewCallback() {
    val good=fix(12_000,10f); val coarse=fix(5_000,100f,"network"); val p=choose(good,coarse)
    assertSame(good,p.selected(wall+18_000,elapsed+18_000_000_000L))
    assertSame(coarse,p.selected(wall+18_001,elapsed+18_001_000_000L))
    assertEquals(wall-5_000,p.selected(wall+18_001,elapsed+18_001_000_000L)!!.capturedAtMillis)
  }
  @Test fun expiryWaitIsBoundedAndDoesNotCreateCachedPeriodicRetries() {
    val good=fix(12_000,10f); val p=choose(good,fix(5_000,100f,"network"))
    assertEquals(18_001L,p.pendingSelectionDelayMs(good.elapsedRealtimeNanos,wall,elapsed))
    val promoted=p.selected(wall+18_001,elapsed+18_001_000_000L)!!
    assertEquals(0L,p.pendingSelectionDelayMs(good.elapsedRealtimeNanos,wall+18_001,elapsed+18_001_000_000L))
    assertNull(p.pendingSelectionDelayMs(promoted.elapsedRealtimeNanos,wall+18_001,elapsed+18_001_000_000L))
    assertNull(choose(good).pendingSelectionDelayMs(good.elapsedRealtimeNanos,wall,elapsed))
  }
  @Test fun expiredFixWithoutNewCallbackNeverBecomesFreshAgain() {
    val good=fix(12_000,10f); val p=choose(good)
    val old=p.selected(wall+20_000,elapsed+20_000_000_000L)!!
    assertEquals("unavailable",old.quality(wall+20_000,elapsed+20_000_000_000L))
    assertEquals(good.capturedAtMillis,old.capturedAtMillis)
    assertNull(p.selected(wall+140_000,elapsed+140_000_000_000L))
  }
  @Test fun newerDisjointReportedPositionSupersedesOldAccuracy() {
    val p=choose(fix(8_000,10f)); val moved=fix(2_000,100f,"network",latitude=50.71)
    val d=p.offer(moved,wall,elapsed)
    assertSame(moved,d.selected); assertEquals("newer_disjoint_position",d.reason)
    assertEquals(100f,d.selected!!.accuracyMeters,0f)
  }
  @Test fun providerDoesNotOverrideActualAgeAndQuality() {
    val network=fix(8_000,10f,"network"); val p=choose(network)
    assertSame(network,p.offer(fix(2_000,100f,"gps"),wall,elapsed).selected)
    val betterFused=fix(1_000,8f,"fused")
    assertSame(betterFused,p.offer(betterFused,wall,elapsed).selected)
  }
  @Test fun invalidAccuracyCoordinatesOrFutureCaptureCannotReplace() {
    val good=fix(8_000,10f); val p=choose(good)
    for (bad in listOf(fix(1_000,151f),fix(1_000,-1f),fix(1_000,Float.NaN),
      fix(1_000,10f,latitude=Double.NaN),fix(1_000,10f,longitude=181.0),
      fix(-1,10f),fix(151_000,10f))) {
      assertFalse(p.offer(bad,wall,elapsed).accepted); assertSame(good,p.selected(wall,elapsed))
    }
  }
  @Test fun existingOneHundredFiftyMetreBoundaryIsPreserved() {
    val sample=fix(2_000,150f); assertSame(sample,choose(sample).selected(wall,elapsed))
  }
  @Test fun staleMaximumAgeBoundaryPreservesOriginalTime() {
    val atLimit=fix(150_000,20f); val p=choose(atLimit)
    assertSame(atLimit,p.selected(wall,elapsed)); assertNull(p.selected(wall+1,elapsed+1_000_000))
  }
  @Test fun actorResetHasNoCrossDriverSelectedOrFallbackReuse() {
    val a=choose(fix(8_000,10f),fix(2_000,100f,"network"))
    assertNotNull(a.selected(wall,elapsed))
    val b=DriverDutySampleSelector<String>(); assertNull(b.selected(wall,elapsed))
  }
  @Test fun wallClockAndMonotonicClockMustBothAdvance() {
    val good=fix(8_000,10f); val p=choose(good)
    val conflict=fix(2_000,8f).copy(elapsedRealtimeNanos=good.elapsedRealtimeNanos-1)
    assertFalse(p.offer(conflict,wall,elapsed).accepted); assertSame(good,p.selected(wall,elapsed))
  }
  @Test fun expiredCaptureWatermarkStillRejectsDelayedOlderSample() {
    val p=choose(fix(2_000,10f))
    assertNull(p.selected(wall+151_000,elapsed+151_000_000_000L))
    assertFalse(p.offer(fix(3_000,8f),wall+151_000,elapsed+151_000_000_000L).accepted)
  }
}
