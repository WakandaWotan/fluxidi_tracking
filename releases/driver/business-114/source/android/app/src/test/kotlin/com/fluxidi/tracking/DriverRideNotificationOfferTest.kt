package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverRideNotificationOfferTest {
  private val actor = DriverDutyActor("tenant", "company", "driver", "vehicle")
  private fun row() = mapOf<String, Any?>("tenant_id" to "tenant", "company_id" to "company",
    "driver_id" to "driver", "vehicle_id" to "vehicle", "human_acceptance_required" to true,
    "offer_id" to "offer", "version" to 4, "ack_deadline_ms" to 151000L,
    "currency" to "EUR",
    "pickup_address" to "Fixture pickup", "dropoff_address" to "Fixture destination")

  @Test fun genuineOwnedHumanOfferMapsWithoutSendingReceiptOrDecision() {
    val offer = DriverRideNotificationOffer.read(row(), actor, 1000)!!
    assertEquals("offer", offer.id); assertEquals(4, offer.version)
    assertEquals("Fixture pickup", offer.pickup); assertEquals(151000L, offer.deadlineMs)
  }
  @Test fun tenantCompanyDriverAndVehicleMustAllMatchIncludingSharedVehicleSwitch() {
    for (field in listOf("tenant_id", "company_id", "driver_id", "vehicle_id")) {
      assertNull(DriverRideNotificationOffer.read(row() + (field to "other"), actor, 1000))
    }
    assertNull(DriverRideNotificationOffer.read(row(), DriverDutyActor(), 1000))
  }
  @Test fun expiredNonHumanOrMalformedOfferCannotTriggerNotification() {
    for (change in listOf("ack_deadline_ms" to 1000L, "human_acceptance_required" to false,
      "version" to 0, "version" to 4.5, "offer_id" to "", "pickup_address" to "",
      "dropoff_address" to "x".repeat(501), "currency" to "other", "price_incl_vat" to Double.NaN)) {
      assertNull(DriverRideNotificationOffer.read(row() + change, actor, 1000))
    }
  }
}
