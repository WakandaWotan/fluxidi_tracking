package com.fluxidi.tracking

import org.junit.Assert.*
import org.junit.Test

class DriverRideAlertClaimCacheTest {
  private fun key(driver: String = "D", company: String = "C", tenant: String = "T", offer: String = "O") =
    listOf(tenant, company, driver, "V", offer, "1")
  @Test fun foregroundAndHeartbeatCanClaimTheSameOfferOnlyOnce() {
    val cache = DriverRideAlertClaimCache()
    assertTrue(cache.take(key(), 5000, 1000))
    assertFalse(cache.take(key(), 5000, 1001))
  }
  @Test fun identicalIdsRemainIsolatedAcrossDriversCompaniesAndTenants() {
    val cache = DriverRideAlertClaimCache()
    assertTrue(cache.take(key(), 5000, 1000))
    assertTrue(cache.take(key(driver = "OTHER"), 5000, 1000))
    assertTrue(cache.take(key(company = "OTHER"), 5000, 1000))
    assertTrue(cache.take(key(tenant = "OTHER"), 5000, 1000))
  }
  @Test fun expiredOrIncompleteEvidenceCannotClaimAttention() {
    val cache = DriverRideAlertClaimCache()
    assertFalse(cache.take(key(), 1000, 1000))
    assertFalse(cache.take(key(driver = ""), 5000, 1000))
    assertFalse(cache.take(emptyList(), 5000, 1000))
    assertTrue(cache.take(key(), 5000, 1000))
    assertFalse(cache.take(key(), 8000, 5000))
    assertTrue(cache.take(key(offer = "NEW"), 8000, 5000))
  }
  @Test fun boundedCacheNeverEvictsAnUnexpiredClaimToReplayItsSound() {
    val cache = DriverRideAlertClaimCache()
    for (i in 0 until 64) assertTrue(cache.take(key(offer = "O$i"), 5000, 1000))
    assertFalse(cache.take(key(offer = "overflow"), 5000, 1000))
    assertFalse(cache.take(key(offer = "O0"), 5000, 1000))
    assertTrue(cache.take(key(offer = "fresh"), 309000, 301000))
  }
}
