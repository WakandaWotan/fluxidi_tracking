package com.fluxidi.tracking

// Only the notification adapter is under test here. Native duty ownership is
// a synthetic fixture; the real service is separately compiled against SDK 36.
internal data class DriverDutyActor(val tenantId:String="",val companyId:String="",val driverId:String="",val vehicleId:String="")
internal data class DriverDutyLease(val actor:DriverDutyActor)
internal object DriverDutyService {
  var ready=true
  var notifications:DriverRideNotifications?=null
  fun notificationReady(token:String)=ready
  fun refreshOffers(token:String)=ready
  fun retainsOfferAttention(key:List<String>)=ready
  fun clearOffer(id:String){notifications?.clearOffer(id)}
}
