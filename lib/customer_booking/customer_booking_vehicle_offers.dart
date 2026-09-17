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
  Set<String> availableVehicleIds = const <String>{},
  Set<String> unavailableVehicleIds = const <String>{},
  Map<String, String> unavailableReasons = const <String, String>{},
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
    if (unavailableVehicleIds.contains(id)) {
      offers.add(
        CustomerBookingVehicleOffer(
          vehicle: vehicle,
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
          rideEndUtc: pickupUtc.add(Duration(minutes: durationMin)),
        );
        if (presence.suitable) {
          onDuty = driver;
          blockedReason = '';
          break;
        }
        blockedReason = presence.code;
      }
    } else if (linked.isNotEmpty) {
      onDuty = linked.first;
    }
    final serverKnown = availableVehicleIds.isNotEmpty;
    final available = serverKnown
        ? availableVehicleIds.contains(id)
        : pickupUtc == null || linked.isEmpty || onDuty != null;
    offers.add(
      CustomerBookingVehicleOffer(
        vehicle: vehicle,
        driver: onDuty,
        available: available,
        reason: available ? '' : (unavailableReasons[id] ?? blockedReason),
        passengerSeats: seats,
      ),
    );
  }
  return offers;
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
}) {
  if (!hasCompany) return CustomerBookingVehicleOfferState.needCompany;
  if (loading && offers.isEmpty) {
    return CustomerBookingVehicleOfferState.loading;
  }
  if (loadFailed && offers.isEmpty) {
    return CustomerBookingVehicleOfferState.loadFailed;
  }
  if (offers.isEmpty) {
    return rideReady
        ? CustomerBookingVehicleOfferState.noneSuitable
        : CustomerBookingVehicleOfferState.incompleteRide;
  }
  return CustomerBookingVehicleOfferState.ready;
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
