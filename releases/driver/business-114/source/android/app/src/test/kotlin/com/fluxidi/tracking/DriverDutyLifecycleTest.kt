package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverDutyLifecycleTest {
  @Test fun authenticatedTrackingWrapperReasonRetiresTheActualLease() {
    // Actual /track/driver/location response:409, ok:false, applied:false,
    // mode:presence, reason:location_owner_retired (no error property).
    assertEquals("location_owner_retired", DriverDutyLocationPolicy.terminationReason(409, "", false, "location_owner_retired"))
    assertNull(DriverDutyLocationPolicy.terminationReason(409, "", false, "location_scope_conflict"))
    assertNull(DriverDutyLocationPolicy.terminationReason(200, "", false, "location_owner_retired"))
    assertEquals("location_owner_retired", DriverDutyLocationPolicy.terminationReason(409, "location_owner_retired", false))
  }
  @Test fun locationRetirementStopsOnlyItsLeaseAndCannotResurrectIt() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    assertTrue(gate.ready(a))
    val reason = DriverDutyLocationPolicy.terminationReason(409, "location_owner_retired", false)!!
    assertTrue(gate.finish(a, reason))
    assertFalse(gate.status("A").running)
    assertEquals("location_owner_retired", gate.status("A").reason)
    assertNull(gate.acceptCommand("A", a.generation, a.token, a.booking, a.tracking))
    val b = begin(gate, "B")
    assertTrue(gate.ready(b))
    assertFalse(gate.finish(a, reason))
    assertTrue(gate.isCurrent(b))
  }

  @Test fun locationErrorsDoNotGuessRetirementFromUntrustedOrTemporaryResponses() {
    for (code in listOf(200, 408, 429, 500, 503))
      assertNull(DriverDutyLocationPolicy.terminationReason(code, "location_owner_retired", false))
    assertNull(DriverDutyLocationPolicy.terminationReason(409, "different_conflict", false))
    assertEquals("availability_ended", DriverDutyLocationPolicy.terminationReason(200, "", true))
    for (code in listOf(401, 403))
      assertEquals("session_revoked", DriverDutyLocationPolicy.terminationReason(code, "", false))
  }
  private fun begin(gate: DriverDutyLifecycle, id: String = "A", token: String = "fixture-A") =
    gate.begin(id, token, "https://booking.example", "https://tracking.example")

  @Test fun enqueueIsNotReadyAndOnlyMatchingCommandCanApplyConfiguration() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    assertFalse(gate.status("A").running)
    assertNull(gate.current())
    assertNull(gate.acceptCommand("A", a.generation, "wrong-token", a.booking, a.tracking))
    assertSame(a, gate.acceptCommand("A", a.generation, a.token, a.booking, a.tracking))
    assertTrue(gate.ready(a))
    assertTrue(gate.status("A").running)
    assertFalse(gate.status("B").running)
  }

  @Test fun stopBeforeQueuedStartCannotBeRevivedByTheOldIntent() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    assertSame(a, gate.cancel("A", "requested_stop"))
    assertNull(gate.acceptCommand("A", a.generation, a.token, a.booking, a.tracking))
    assertFalse(gate.ready(a))
  }

  @Test fun lateReadyFailureOrStopFromAAlwaysPreservesNewB() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    gate.ready(a)
    val b = begin(gate, "B", "fixture-B")
    assertFalse(gate.ready(a))
    assertFalse(gate.finish(a, "start_timeout", true))
    assertNull(gate.cancel("A", "requested_stop"))
    assertNull(gate.acceptCommand("A", a.generation, a.token, a.booking, a.tracking))
    assertSame(b, gate.current(false))
    assertTrue(gate.ready(b))
    assertTrue(gate.status("B").running)
  }

  @Test fun requestsKeepTheirOwnCredentialsAcrossIdentityReplacement() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    gate.ready(a)
    val b = begin(gate, "B", "fixture-B")
    gate.ready(b)
    assertEquals("fixture-A", a.token)
    assertEquals("fixture-B", b.token)
    assertFalse(gate.isCurrent(a))
    assertTrue(gate.isCurrent(b))
  }

  @Test fun reusedActivationLabelStillCannotReviveAnOlderGeneration() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    gate.ready(a)
    val newer = begin(gate, "A", "fixture-new")
    gate.ready(newer)
    assertFalse(gate.isCurrent(a))
    assertFalse(gate.finish(a, "start_timeout", true))
    assertTrue(gate.isCurrent(newer))
  }

  @Test fun revokedOrFailedActivationCannotRemainReady() {
    for (reason in listOf("session_revoked", "location_permission_missing", "location_disabled", "start_failed")) {
      val gate = DriverDutyLifecycle()
      val a = begin(gate)
      gate.ready(a)
      assertTrue(gate.finish(a, reason, true))
      assertFalse(gate.status("A").running)
      assertEquals(reason, gate.status("A").reason)
      assertNull(gate.current(false))
    }
  }

  @Test fun legacyStopRemainsGlobalButOwnedStopCannotCancelAnotherActivation() {
    val gate = DriverDutyLifecycle()
    val a = begin(gate)
    gate.ready(a)
    assertNull(gate.cancel("B", "requested_stop"))
    assertTrue(gate.status().running)
    assertSame(a, gate.cancel(null, "requested_stop"))
    assertFalse(gate.status().running)
  }

  @Test fun onlyANewProcessMayRestoreAnAndroidRedeliveredIntent() {
    val gate = DriverDutyLifecycle()
    val restored = gate.acceptCommand("A", 42, "fixture-A", "https://booking.example", "https://tracking.example")!!
    assertFalse(gate.status("A").running)
    assertTrue(gate.ready(restored))
    gate.cancel("A", "requested_stop")
    assertNull(gate.acceptCommand("A", 42, restored.token, restored.booking, restored.tracking))
  }

  @Test fun expectedStatusRequiresExactBearerActorVehicleAndEndpoints() {
    val gate = DriverDutyLifecycle()
    val actor = DriverDutyActor("tenant-A", "company-A", "driver-A", "vehicle-A")
    val a = gate.begin("A", "fixture-A", "https://booking.example", "https://tracking.example", "device-A", actor)
    gate.ready(a)
    val expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor)
    assertTrue(gate.status(expected = expected).running)
    assertEquals("A", gate.status(expected = expected).activationId)
    assertEquals("device-A", gate.status(expected = expected).nativeDeviceId)
    for (wrong in listOf(
      DriverDutyExpectedConfig("fixture-B", a.booking, a.tracking, actor),
      DriverDutyExpectedConfig(a.token, "https://other-booking.example", a.tracking, actor),
      DriverDutyExpectedConfig(a.token, a.booking, "https://other-tracking.example", actor),
      DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor.copy(tenantId = "tenant-B")),
      DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor.copy(companyId = "company-B")),
      DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor.copy(driverId = "driver-B")),
      DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor.copy(vehicleId = "vehicle-B")),
    )) {
      val status = gate.status(expected = wrong)
      assertFalse(status.running)
      assertEquals("", status.activationId)
      assertEquals("", status.nativeDeviceId)
      assertEquals("owner_not_current", status.reason)
    }
    assertTrue(gate.isCurrent(a))
  }

  @Test fun sameBearerVehicleSwitchRejectsOldStatusAndDelayedStopAfterNewReady() {
    val gate = DriverDutyLifecycle()
    val actor = DriverDutyActor("tenant-A", "company-A", "driver-A", "vehicle-A")
    val a = gate.begin("A", "fixture-A", "https://booking.example", "https://tracking.example", "device-A", actor)
    gate.ready(a)
    val b = gate.begin("B", a.token, a.booking, a.tracking, a.nativeDeviceId, actor.copy(vehicleId = "vehicle-B"))
    gate.ready(b)
    assertFalse(gate.status(expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor)).running)
    assertNull(gate.cancel("A", "requested_stop"))
    assertTrue(gate.status(expected = DriverDutyExpectedConfig(b.token, b.booking, b.tracking, b.actor)).running)
    assertTrue(gate.isCurrent(b))
  }

  @Test fun restoredServiceOnlyExposesActivationToItsExactExpectedOwner() {
    val gate = DriverDutyLifecycle()
    val actor = DriverDutyActor("tenant-A", "company-A", "driver-A", "vehicle-A")
    val a = gate.acceptCommand("restore-A", 42, "fixture-A", "https://booking.example", "https://tracking.example", "device-A", actor)!!
    gate.ready(a)
    assertEquals("restore-A", gate.status(expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor)).activationId)
    assertEquals("", gate.status(expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor.copy(driverId = "driver-B"))).activationId)
    assertNull(gate.acceptCommand(a.activationId, a.generation, a.token, a.booking, a.tracking, "device-B", actor))
    assertSame(a, gate.acceptCommand(a.activationId, a.generation, a.token, a.booking, a.tracking, "device-A", actor))
  }

  @Test fun optionalNotificationExpectationDoesNotBlockColdOwnedStop() {
    val gate = DriverDutyLifecycle()
    val actor = DriverDutyActor("tenant-A", "company-A", "driver-A", "vehicle-A")
    val a = gate.begin("A", "fixture-A", "https://booking.example", "https://tracking.example", "device-A", actor, "Fluxidi", "Beschikbaar")
    gate.ready(a)
    assertTrue(gate.status(expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor)).running)
    assertTrue(gate.status(expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor, "Fluxidi", "Beschikbaar")).running)
    assertFalse(gate.status(expected = DriverDutyExpectedConfig(a.token, a.booking, a.tracking, actor, "Fluxidi", "Available")).running)
  }

  @Test fun expectedConfigCannotSilentlyDefaultMissingOrMalformedActorFields() {
    val map = mapOf<String, Any>("token" to "fixture-A", "tenant_id" to "tenant-A", "company_id" to "company-A",
      "driver_id" to "driver-A", "vehicle_id" to "vehicle-A", "booking" to "https://booking.example", "tracking" to "https://tracking.example")
    assertNotNull(DriverDutyExpectedConfig.fromMap(map))
    for (key in map.keys) {
      assertNull(DriverDutyExpectedConfig.fromMap(map - key))
      assertNull(DriverDutyExpectedConfig.fromMap(map + (key to "")))
      assertNull(DriverDutyExpectedConfig.fromMap(map + (key to 42)))
    }
    assertNull(DriverDutyExpectedConfig.fromMap(null))
    assertNull(DriverDutyExpectedConfig.fromMap(map + ("title" to 42)))
    assertNull(DriverDutyExpectedConfig.fromMap(map + ("text" to 42)))
  }
}
