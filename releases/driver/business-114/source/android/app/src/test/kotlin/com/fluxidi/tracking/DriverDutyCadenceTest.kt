package com.fluxidi.tracking
import org.junit.Assert.*
import org.junit.Test
class DriverDutyCadenceTest {
  @Test fun stationaryDriverDoesNotUploadOnEveryGpsCallback() {
    val policy = DriverDutyCadence()
    assertTrue(policy.due(0)); policy.completed(0,0f)
    assertFalse(policy.due(24999)); assertTrue(policy.due(25000))
  }
  @Test fun movingDriverUpdatesAtTwentyFiveSecondsAndHonorsBackoff() {
    val policy=DriverDutyCadence(); policy.completed(10000,3f)
    assertFalse(policy.due(34999)); assertTrue(policy.due(35000))
    policy.completed(35000,3f,300)
    assertFalse(policy.due(334999)); assertTrue(policy.due(335000))
  }
  @Test fun invalidSpeedUsesStationaryCadence() {
    val policy=DriverDutyCadence(); policy.completed(0,Float.NaN)
    assertFalse(policy.due(24999)); assertTrue(policy.due(25000))
  }
  @Test fun uploadLatencyDoesNotSkipTheNextRealGpsCallback() {
    val policy=DriverDutyCadence()
    policy.completed(2000,0f,startedAt=0)
    assertFalse(policy.due(24999)); assertTrue(policy.due(25000))
    policy.completed(28000,0f,startedAt=25000)
    assertFalse(policy.due(49999)); assertTrue(policy.due(50000))
  }
  @Test fun rateLimitBackoffStillStartsAtResponseTime() {
    val policy=DriverDutyCadence()
    policy.completed(28000,0f,300,startedAt=25000)
    assertFalse(policy.due(327999)); assertTrue(policy.due(328000))
  }
  @Test fun earlyCallbackCanWaitOnlyForTheExistingDeadline() {
    val policy = DriverDutyCadence()
    policy.completed(200, 0f, startedAt = 100)
    assertEquals(50L, policy.remainingDelayMs(25050))
    assertEquals(0L, policy.remainingDelayMs(25100))
    assertEquals(0L, policy.remainingDelayMs(50000))
  }
  @Test fun invalidOrOlderCallbackCannotReplaceTheNewestActualFix() {
    fun accept(accuracy: Float = 6f, hasAccuracy: Boolean = true, latitude: Double = 50.7, elapsed: Long = 26) =
      DriverDutyCadence.acceptsRealFix(hasAccuracy, accuracy, latitude, 3.6, elapsed, 25)
    assertTrue(accept())
    assertFalse(accept(elapsed = 25)); assertFalse(accept(elapsed = 24))
    assertFalse(accept(hasAccuracy = false)); assertFalse(accept(accuracy = Float.NaN))
    assertFalse(accept(accuracy = -1f)); assertFalse(accept(accuracy = 151f))
    assertFalse(accept(latitude = Double.NaN)); assertTrue(accept(accuracy = 150f))
  }
}
