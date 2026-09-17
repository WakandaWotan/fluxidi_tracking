import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_plan_assignment.dart';
import 'package:fluxidi_tracking/company/company_plan_presence.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

class CustomerBookingVehicleOffer {
  const CustomerBookingVehicleOffer({
    required this.vehicle,
    this.driver,
    this.available = true,
    this.reason = '',
    this.passengerSeats,
  });

  final Map<String, dynamic> vehicle;
  final Map<String, dynamic>? driver;
  final bool available;
  final String reason;
  final int? passengerSeats;

  String get vehicleId => companyAgendaVehicleId(vehicle);
  String get driverId =>
      driver == null ? '' : companyAgendaDriverId(driver!);
}

List<Map<String, dynamic>> customerBookingDriversFromVehicles(
  List<Map<String, dynamic>> vehicles,
) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final vehicle in vehicles) {
    final embedded = vehicle['assigned_driver'] ?? vehicle['assignedDriver'];
    if (embedded is! Map) continue;
    final driver = Map<String, dynamic>.from(embedded);
    final id = companyAgendaDriverId(driver);
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(driver);
  }
  return out;
}

List<CustomerBookingVehicleOffer> customerBookingVehicleOffers({
  required List<Map<String, dynamic>> vehicles,
  List<Map<String, dynamic>> drivers = const <Map<String, dynamic>>[],
  required int passengers,
  DateTime? pickupUtc,
  int durationMin = 30,
  bool durationKnown = true,
  bool rideReady = true,
  Set<String> availableVehicleIds = const <String>{},
  Set<String> unavailableVehicleIds = const <String>{},
  Map<String, String> unavailableReasons = const <String, String>{},
  Map<String, String> proposedDriverIds = const <String, String>{},
  bool availabilityResolved = false,
  bool availabilityFailed = false,
}) {
  final mergedDrivers = <Map<String, dynamic>>[
    ...drivers,
    ...customerBookingDriversFromVehicles(vehicles),
  ];
  final schedules = companyDriverSchedulesFromRecords(mergedDrivers);
  final seen = <String>{};
  final offers = <CustomerBookingVehicleOffer>[];
  for (final vehicle in vehicles) {
    final id = companyAgendaVehicleId(vehicle);
    if (id.isEmpty || !seen.add(id)) continue;
    final seats = companyAgendaVehiclePassengerSeats(vehicle);
    if (seats != null && seats > 0 && passengers > seats) {
      offers.add(
        CustomerBookingVehicleOffer(
          vehicle: vehicle,
          available: false,
          reason: 'assignment_capacity',
          passengerSeats: seats,
        ),
      );
      continue;
    }
    if (!rideReady) {
      offers.add(
        CustomerBookingVehicleOffer(
          vehicle: vehicle,
          available: false,
          reason: 'need_ride',
          passengerSeats: seats,
        ),
      );
      continue;
    }
    if (availabilityFailed) {
      offers.add(
        CustomerBookingVehicleOffer(
          vehicle: vehicle,
          available: false,
          reason: 'availability_load_failed',
          passengerSeats: seats,
        ),
      );
      continue;
    }
    if (durationKnown && unavailableVehicleIds.contains(id)) {
      offers.add(
        CustomerBookingVehicleOffer(
          vehicle: vehicle,
          driver: _driverById(mergedDrivers, proposedDriverIds[id] ?? ''),
          available: false,
          reason: unavailableReasons[id] ?? 'unavailable',
          passengerSeats: seats,
        ),
      );
      continue;
    }
    final linked = [
      for (final driver in mergedDrivers)
        if (_driverUsesVehicle(driver, vehicle)) driver,
    ];
    Map<String, dynamic>? onDuty;
    var blockedReason = '';
    if (pickupUtc != null && linked.isNotEmpty) {
      for (final driver in linked) {
        final presence = resolveCompanyPlanPresence(
          driver: driver,
          whenNow: false,
          vehicles: [vehicle],
          passengers: passengers,
          schedule: schedules[companyAgendaDriverId(driver)],
          rideStartUtc: pickupUtc,
          rideEndUtc: durationKnown
              ? pickupUtc.add(Duration(minutes: durationMin))
              : pickupUtc,
        );
        if (presence.suitable) {
          onDuty = driver;
          blockedReason = '';
          break;
        }
        blockedReason = presence.code;
      }
    }
    final proposedId = (proposedDriverIds[id] ?? '').trim();
    final proposed = _driverById(mergedDrivers, proposedId) ?? onDuty;
    if (!durationKnown &&
        !availabilityResolved &&
        blockedReason != 'assignment_driver_outside_hours' &&
        blockedReason != 'assignment_driver_not_scheduled' &&
        blockedReason != 'assignment_driver_planned_break' &&
        blockedReason != 'assignment_driver_absent') {
      offers.add(
        CustomerBookingVehicleOffer(
          vehicle: vehicle,
          driver: proposed,
          available: false,
          reason: 'need_duration',
          passengerSeats: seats,
        ),
      );
      continue;
    }
    final serverKnown = durationKnown &&
        (availabilityResolved ||
            availableVehicleIds.isNotEmpty ||
            unavailableVehicleIds.isNotEmpty);
    final available = serverKnown
        ? availableVehicleIds.contains(id)
        : pickupUtc == null || (linked.isNotEmpty && onDuty != null);
    offers.add(
      CustomerBookingVehicleOffer(
        vehicle: vehicle,
        driver: proposed,
        available: available,
        reason: available
            ? ''
            : (unavailableReasons[id] ??
                (blockedReason.isNotEmpty ? blockedReason : 'unavailable')),
        passengerSeats: seats,
      ),
    );
  }
  return offers;
}

Map<String, dynamic>? _driverById(
  List<Map<String, dynamic>> drivers,
  String driverId,
) {
  final id = driverId.trim();
  if (id.isEmpty) return null;
  for (final driver in drivers) {
    if (companyAgendaDriverId(driver) == id) return driver;
  }
  return null;
}

bool _driverUsesVehicle(
  Map<String, dynamic> driver,
  Map<String, dynamic> vehicle,
) {
  final vehicleId = companyAgendaVehicleId(vehicle);
  if (vehicleId.isEmpty) return false;
  final linked = companyAgendaDriverLinkedVehicleIds(driver);
  if (linked.contains(vehicleId)) return true;
  final owner = (vehicle['assigned_driver_id'] ??
          vehicle['assignedDriverId'] ??
          vehicle['driver_id'] ??
          '')
      .toString()
      .trim();
  return owner.isNotEmpty && owner == companyAgendaDriverId(driver);
}

String customerBookingVehicleOfferTitle({
  required CustomerBookingVehicleOffer offer,
  required AppLanguage language,
}) {
  final name = companyAgendaVehicleName(offer.vehicle);
  if (name.isNotEmpty && !companyPlanLooksLikeInternalId(name)) return name;
  final category = classifyCompanyPlanVehicleCategory(offer.vehicle);
  if (category == null) {
    return language == AppLanguage.en ? 'Vehicle' : 'Voertuig';
  }
  return companyPlanVehicleCategoryLabel(category, language);
}

enum CustomerBookingVehicleOfferState {
  needCompany,
  incompleteRide,
  loading,
  checking,
  loadFailed,
  noneSuitable,
  ready,
}

bool customerBookingRideDetailsReady({
  required bool pickupFilled,
  required bool dropoffFilled,
  bool airportMode = false,
  bool toAirport = false,
  bool hasAirport = false,
}) {
  if (airportMode && hasAirport) {
    return toAirport ? pickupFilled : dropoffFilled;
  }
  return pickupFilled && dropoffFilled;
}

CustomerBookingVehicleOfferState customerBookingVehicleOfferState({
  required bool hasCompany,
  required bool rideReady,
  required bool loading,
  required bool loadFailed,
  required List<CustomerBookingVehicleOffer> offers,
  bool availabilityLoading = false,
}) {
  if (!hasCompany) return CustomerBookingVehicleOfferState.needCompany;
  if (loading && offers.isEmpty) {
    return CustomerBookingVehicleOfferState.loading;
  }
  if (loadFailed && offers.isEmpty) {
    return CustomerBookingVehicleOfferState.loadFailed;
  }
  if (!rideReady) {
    return CustomerBookingVehicleOfferState.incompleteRide;
  }
  if (availabilityLoading) {
    return CustomerBookingVehicleOfferState.checking;
  }
  if (loadFailed) return CustomerBookingVehicleOfferState.loadFailed;
  if (offers.isEmpty) return CustomerBookingVehicleOfferState.noneSuitable;
  return CustomerBookingVehicleOfferState.ready;
}

bool customerBookingVehicleReasonIsPending(String reason) {
  return reason == 'need_ride' ||
      reason == 'need_duration' ||
      reason == 'pending';
}

bool customerBookingVehicleReasonIsLoadFailed(String reason) {
  return reason == 'availability_load_failed';
}

String customerBookingVehicleOfferCapacityLabel({
  required CustomerBookingVehicleOffer offer,
  required AppLanguage language,
}) {
  final seats = offer.passengerSeats;
  if (seats == null || seats <= 0) {
    return language == AppLanguage.en
        ? 'Capacity unknown'
        : 'Capaciteit onbekend';
  }
  return language == AppLanguage.en
      ? '$seats passengers'
      : '$seats passagiers';
}
