package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverHeartbeatOfferReceiptsTest {
  @Test fun humanProposalNeverStartsResponseTimerWithoutPresentation() {
    val sent = mutableListOf<String>()
    acknowledgeHeartbeatOffers(listOf(
      DriverHeartbeatOfferReceipt("human", 4, true),
      DriverHeartbeatOfferReceipt("legacy-readiness", 3, false),
    ), { true }, { id, _ -> sent.add(id); 200 }, { fail("unexpected revocation") })
    assertEquals(listOf("legacy-readiness"), sent)
  }

  @Test fun ownerChangeDuringDeliveryStopsRemainingOldActorReceipts() {
    var current = true
    val sent = mutableListOf<String>()
    acknowledgeHeartbeatOffers(listOf(
      DriverHeartbeatOfferReceipt("one", 1, false), DriverHeartbeatOfferReceipt("two", 1, false),
    ), { current }, { id, _ -> sent.add(id); current = false; 200 }, { fail("unexpected revocation") })
    assertEquals(listOf("one"), sent)
  }

  @Test fun revokedBearerStopsBatchAndRetiresCapturedSession() {
    for (status in listOf(401, 403)) {
      var calls = 0; var retired = 0
      acknowledgeHeartbeatOffers(List(2) { DriverHeartbeatOfferReceipt("offer-$it", 1, false) },
        { true }, { _, _ -> calls++; status }, { retired++ })
      assertEquals(1, calls); assertEquals(1, retired)
    }
  }

  @Test fun malformedAndOversizedBatchesCannotSubmitInvalidReceipts() {
    val sent = mutableListOf<String>()
    val offers = listOf(DriverHeartbeatOfferReceipt("", 1, false),
      DriverHeartbeatOfferReceipt("x".repeat(201), 1, false),
      DriverHeartbeatOfferReceipt("bad-version", 0, false)) +
      List(10) { DriverHeartbeatOfferReceipt("valid-$it", 7, false) }
    acknowledgeHeartbeatOffers(offers, { true }, { id, version ->
      assertEquals(7, version); sent.add(id); 200
    }, { fail("unexpected revocation") })
    assertEquals((0..4).map { "valid-$it" }, sent)
  }
}
