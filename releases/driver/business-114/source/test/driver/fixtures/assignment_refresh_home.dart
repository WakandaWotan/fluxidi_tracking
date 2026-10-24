import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_duty_bridge.dart';
class BookingItem {
 BookingItem(this.details);
 final Map<String,dynamic> details;
 String get bookingId=>(details['booking_id']??details['id']??'').toString();
 String get legId=>(details['leg_id']??'').toString();
 bool get isOperationalLeg=>legId.isNotEmpty;
}
enum _DriverRidesHubSegment {available,myRides,history}
class AssignmentHarness extends StatefulWidget {
 const AssignmentHarness({super.key,this.openedFromBusinessHome=false});
 final bool openedFromBusinessHome;
 @override AssignmentHarnessState createState()=>AssignmentHarnessState();
}
class AssignmentHarnessState extends State<AssignmentHarness> {
 bool _liveRideActive=false,_standaloneDriverSwitchInProgress=false;
 bool _bookingsHubVisible=true;
 var _ridesHubSegment=_DriverRidesHubSegment.available;
 Route<void>? _rideOfferInboxRoute;
 int reads=0,navigations=0;
 final triggers=<String>[];
 List<BookingItem> page=[];
 Future<void> Function()? readGate;
 bool get myRides=>_ridesHubSegment==_DriverRidesHubSegment.myRides;
 int get pending=>_pendingOfferAssignments.length;
 bool _canAccessDriverOpsScreens()=>true;
 bool _isClosedRideStatus(String? s)=>['CANCELLED','COMPLETED','DECLINED','EXPIRED'].contains(s);
 String? _effectiveStatusFor(BookingItem b)=>b.details['status'] as String?;
 bool _bookingItemIsBackendAvailableUnassigned(BookingItem b)=>b.details['available_unassigned']==true||b.details['availableUnassigned']==true;
 void _markBookingsUiDirty() {navigations++;}
 void _openBookingsHubFromDashboard({required _DriverRidesHubSegment initialSegment}){_ridesHubSegment=initialSegment;navigations++;}
 Future<void> _refreshBookings({bool force=false,String trigger='unknown'}) async {
  if(!force)throw StateError('must bypass refresh cooldown');
  reads++;triggers.add(trigger);
  await readGate?.call();
  if(mounted){_confirmPendingOfferAssignments(page);setState((){});}
 }
 void accept(ActiveDriverSession owner,DriverRideOffer offer)=>_onRideOfferAcceptanceReceived(owner,offer);
 @override void dispose(){_acceptedOfferRefreshTimer?.cancel();super.dispose();}
 @override Widget build(BuildContext context)=>const SizedBox();
  Timer? _acceptedOfferRefreshTimer;
  int _acceptedOfferReadsRemaining = 0;
  bool _acceptedOfferReadInFlight = false;
  final _pendingOfferAssignments = <String, ({ActiveDriverSession owner, DriverRideOffer offer})>{};

  void _onRideOfferAcceptanceReceived(ActiveDriverSession owner, DriverRideOffer offer) {
    if (!mounted || widget.openedFromBusinessHome ||
        !DriverDutyBridge.sameAuthenticatedActor(owner, activeDriverSessionNotifier.value) ||
        owner.assignedVehicleId != offer.vehicleId) return;
    _pendingOfferAssignments.removeWhere((_, p) =>
        !DriverDutyBridge.sameAuthenticatedActor(p.owner, owner));
    _pendingOfferAssignments['${offer.id}:${offer.version}'] = (owner: owner, offer: offer);
    _acceptedOfferReadsRemaining = 15;
    _acceptedOfferRefreshTimer?.cancel();
    _acceptedOfferRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshPendingOfferAssignments());
    });
    unawaited(_refreshPendingOfferAssignments());
  }

  Future<void> _refreshPendingOfferAssignments() async {
    if (!mounted || widget.openedFromBusinessHome || _acceptedOfferReadInFlight) return;
    _pendingOfferAssignments.removeWhere((_, p) =>
        !DriverDutyBridge.sameAuthenticatedActor(p.owner, activeDriverSessionNotifier.value));
    if (_pendingOfferAssignments.isEmpty || _acceptedOfferReadsRemaining <= 0) {
      _acceptedOfferRefreshTimer?.cancel();
      return;
    }
    if (_standaloneDriverSwitchInProgress ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _acceptedOfferReadInFlight = true;
    _acceptedOfferReadsRemaining--;
    try {
      // Existing queue, auth, pagination, stale-response and UI guards apply.
      // Bypass the repository cache until canonical assignment is visible.
      await _refreshBookings(force: true, trigger: 'ride_offer_assignment');
    } finally {
      _acceptedOfferReadInFlight = false;
      if (_pendingOfferAssignments.isEmpty || _acceptedOfferReadsRemaining <= 0) {
        _acceptedOfferRefreshTimer?.cancel();
      }
    }
  }

  void _confirmPendingOfferAssignments(List<BookingItem> serverItems) {
    ActiveDriverSession? confirmedOwner;
    _pendingOfferAssignments.removeWhere((_, p) {
      if (!DriverDutyBridge.sameAuthenticatedActor(p.owner, activeDriverSessionNotifier.value)) return true;
      if ((p.offer.bookingId ?? '').isEmpty) return false;
      final confirmed = serverItems.any((b) => b.bookingId == p.offer.bookingId &&
          b.isOperationalLeg && b.legId.isNotEmpty &&
          !_isClosedRideStatus(_effectiveStatusFor(b)) &&
          !_bookingItemIsBackendAvailableUnassigned(b) &&
          (b.details['assigned_driver_id'] ?? b.details['assignedDriverId']) == p.owner.driverId &&
          (b.details['assigned_vehicle_id'] ?? b.details['assignedVehicleId']) == p.offer.vehicleId);
      if (confirmed) confirmedOwner = p.owner;
      return confirmed;
    });
    if (_pendingOfferAssignments.isEmpty) _acceptedOfferRefreshTimer?.cancel();
    final owner = confirmedOwner;
    if (owner != null) WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _liveRideActive ||
          !DriverDutyBridge.sameAuthenticatedActor(owner, activeDriverSessionNotifier.value) ||
          !_canAccessDriverOpsScreens()) return;
      final inbox = _rideOfferInboxRoute;
      if (inbox != null && inbox.isActive) Navigator.of(context).removeRoute(inbox);
      if (_bookingsHubVisible) {
        setState(() => _ridesHubSegment = _DriverRidesHubSegment.myRides);
        _markBookingsUiDirty();
      } else {
        _openBookingsHubFromDashboard(initialSegment: _DriverRidesHubSegment.myRides);
      }
    });
  }

}
