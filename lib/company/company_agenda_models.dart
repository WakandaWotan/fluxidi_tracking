import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';

enum CompanyAgendaView { day, week, byDriver }

class CompanyAgendaRide {
  const CompanyAgendaRide({
    required this.bookingId,
    required this.customerId,
    required this.customerName,
    required this.fromAddress,
    required this.toAddress,
    required this.pickupIso,
    required this.status,
    required this.assignedDriverId,
    required this.assignedVehicleId,
    required this.durationUnknown,
    this.durationMin,
    this.doNotDispatch = false,
    this.assignmentAccepted = false,
    this.revision = 1,
    this.phoneConfirmedAt = '',
    this.phoneConfirmedBy = '',
    this.source = '',
    this.passengers = 1,
    this.priceInclVat,
    this.currency = 'EUR',
    this.rideOptions = const CompanyRideOptions(),
    this.agendaItemId = '',
    this.parentBookingId = '',
    this.legId = '',
    this.legType = '',
    this.linkedAgendaItemId = '',
    this.roundtripChoice = CompanyRoundtripChoice.single,
    this.occupancyWaitMin,
    this.occupancyUnknown = false,
    this.returnPickupIso = '',
  });

  final String bookingId;
  final String customerId;
  final String customerName;
  final String fromAddress;
  final String toAddress;
  final String pickupIso;
  final String status;
  final String assignedDriverId;
  final String assignedVehicleId;
  final bool durationUnknown;
  final int? durationMin;
  final bool doNotDispatch;
  final bool assignmentAccepted;
  final int revision;
  final String phoneConfirmedAt;
  final String phoneConfirmedBy;
  final String source;
  final int passengers;
  final num? priceInclVat;
  final String currency;
  final CompanyRideOptions rideOptions;
  final String agendaItemId;
  final String parentBookingId;
  final String legId;
  final String legType;
  final String linkedAgendaItemId;
  final CompanyRoundtripChoice roundtripChoice;
  final int? occupancyWaitMin;
  final bool occupancyUnknown;
  final String returnPickupIso;

  String get collectionId {
    final row = agendaItemId.trim();
    if (row.isNotEmpty) return row;
    if (legType.trim().isNotEmpty) {
      return '${bookingId.trim()}:${legType.trim()}';
    }
    return bookingId.trim();
  }

  bool get isUnassigned =>
      assignedDriverId.trim().isEmpty && assignedVehicleId.trim().isEmpty;

  bool get isUnscheduled => pickupUtc == null;

  DateTime? get pickupUtc {
    final parsed = DateTime.tryParse(pickupIso);
    return parsed?.toUtc();
  }

  DateTime? get dropoffUtc {
    final start = pickupUtc;
    if (start == null || durationUnknown || durationMin == null) return null;
    return start.add(Duration(minutes: durationMin!));
  }

  bool get isPhoneConfirmed => phoneConfirmedAt.trim().isNotEmpty;

  factory CompanyAgendaRide.fromMap(Map<String, dynamic> raw) {
    String first(List<String> keys) {
      for (final key in keys) {
        final value = raw[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final duration = resolveCompanyBookingDurationMin(raw);
    final unknown = duration == null;
    final price = resolveCompanyBookingPriceInclVat(raw);
    return CompanyAgendaRide(
      bookingId: first(const ['booking_id', 'bookingId']),
      customerId: first(const ['customer_id', 'customerId']),
      customerName: first(const ['customer_name', 'customerName']),
      fromAddress: first(const ['from', 'pickup']),
      toAddress: first(const ['to', 'dropoff']),
      pickupIso: first(const ['pickup_iso', 'pickupIso']),
      status: first(const ['status']) == '' ? 'PENDING' : first(const ['status']),
      assignedDriverId: first(const ['assigned_driver_id', 'assignedDriverId']),
      assignedVehicleId: first(const [
        'assigned_vehicle_id',
        'assignedVehicleId',
      ]),
      durationUnknown: unknown,
      durationMin: duration,
      doNotDispatch: raw['do_not_dispatch'] == true,
      assignmentAccepted:
          raw['assignment_accepted'] == true || raw['driver_accepted'] == true,
      revision: int.tryParse(first(const ['revision'])) ?? 1,
      phoneConfirmedAt: first(const [
        'phone_confirmed_at',
        'phoneConfirmedAt',
      ]),
      phoneConfirmedBy: first(const [
        'phone_confirmed_by',
        'phoneConfirmedBy',
      ]),
      source: first(const ['source']),
      passengers: int.tryParse(first(const ['passengers', 'pax'])) ?? 1,
      priceInclVat: price,
      currency: resolveCompanyBookingCurrency(raw),
      rideOptions: parseCompanyRideOptions(
        raw['ride_options'] ?? raw['rideOptions'] ?? raw,
      ),
      agendaItemId: first(const ['agenda_item_id', 'agendaItemId']),
      parentBookingId: first(const [
        'parent_booking_id',
        'parentBookingId',
      ]),
      legId: first(const ['leg_id', 'legId']),
      legType: first(const ['leg_type', 'legType']),
      linkedAgendaItemId: first(const [
        'linked_agenda_item_id',
        'linkedAgendaItemId',
      ]),
      roundtripChoice: parseCompanyRoundtripChoice(
        raw['roundtrip_dispatch_mode'] ??
            raw['roundtripDispatchMode'] ??
            raw['roundtrip_choice'],
      ),
      occupancyWaitMin: int.tryParse(
        first(const ['occupancy_wait_min', 'occupancyWaitMin']),
      ),
      occupancyUnknown: raw['occupancy_unknown'] == true,
      returnPickupIso: first(const [
        'return_pickup_iso',
        'returnPickupIso',
      ]),
    );
  }
}

class CompanyAgendaPeriod {
  const CompanyAgendaPeriod({
    required this.view,
    required this.anchor,
    required this.fromUtc,
    required this.toUtc,
  });

  final CompanyAgendaView view;
  final DateTime anchor;
  final DateTime fromUtc;
  final DateTime toUtc;

  String get cacheKey =>
      '${view.name}|${fromUtc.toIso8601String()}|${toUtc.toIso8601String()}';
}

class CompanyRidePlanDraft {
  const CompanyRidePlanDraft({
    required this.customer,
    required this.pickupLocal,
    this.fromAddress = '',
    this.toAddress = '',
    this.passengers = 1,
    this.priceText = '',
    this.durationText = '',
    this.driverId = '',
    this.vehicleId = '',
    this.rideOptions = const CompanyRideOptions(),
    this.publicNote = '',
    this.idempotencyKey,
    this.fromLat,
    this.fromLon,
    this.fromPlaceId = '',
    this.toLat,
    this.toLon,
    this.toPlaceId = '',
    this.roundtripChoice = CompanyRoundtripChoice.single,
    this.returnPickupLocal,
    this.returnFromAddress = '',
    this.returnToAddress = '',
    this.returnDurationText = '',
    this.returnDriverId = '',
    this.returnVehicleId = '',
    this.returnFromLat,
    this.returnFromLon,
    this.returnFromPlaceId = '',
    this.returnToLat,
    this.returnToLon,
    this.returnToPlaceId = '',
    this.fixedPriceSnapshot,
  });

  final CompanyCustomer customer;
  final DateTime pickupLocal;
  final String fromAddress;
  final String toAddress;
  final int passengers;
  final String priceText;
  final String durationText;
  final String driverId;
  final String vehicleId;
  final CompanyRideOptions rideOptions;
  final String publicNote;
  final String? idempotencyKey;
  final double? fromLat;
  final double? fromLon;
  final String fromPlaceId;
  final double? toLat;
  final double? toLon;
  final String toPlaceId;
  final CompanyRoundtripChoice roundtripChoice;
  final DateTime? returnPickupLocal;
  final String returnFromAddress;
  final String returnToAddress;
  final String returnDurationText;
  final String returnDriverId;
  final String returnVehicleId;
  final double? returnFromLat;
  final double? returnFromLon;
  final String returnFromPlaceId;
  final double? returnToLat;
  final double? returnToLon;
  final String returnToPlaceId;
  final Map<String, dynamic>? fixedPriceSnapshot;

  CompanyRidePlanDraft copyWith({
    DateTime? pickupLocal,
    String? fromAddress,
    String? toAddress,
    int? passengers,
    String? priceText,
    String? durationText,
    String? driverId,
    String? vehicleId,
    CompanyRideOptions? rideOptions,
    String? publicNote,
    String? idempotencyKey,
    double? fromLat,
    double? fromLon,
    String? fromPlaceId,
    double? toLat,
    double? toLon,
    String? toPlaceId,
    bool clearFromCoords = false,
    bool clearToCoords = false,
    CompanyRoundtripChoice? roundtripChoice,
    DateTime? returnPickupLocal,
    String? returnFromAddress,
    String? returnToAddress,
    String? returnDurationText,
    String? returnDriverId,
    String? returnVehicleId,
    double? returnFromLat,
    double? returnFromLon,
    String? returnFromPlaceId,
    double? returnToLat,
    double? returnToLon,
    String? returnToPlaceId,
    bool clearReturnCoords = false,
    bool clearReturnPickup = false,
    Map<String, dynamic>? fixedPriceSnapshot,
    bool clearFixedPriceSnapshot = false,
  }) {
    return CompanyRidePlanDraft(
      customer: customer,
      pickupLocal: pickupLocal ?? this.pickupLocal,
      fromAddress: fromAddress ?? this.fromAddress,
      toAddress: toAddress ?? this.toAddress,
      passengers: passengers ?? this.passengers,
      priceText: priceText ?? this.priceText,
      durationText: durationText ?? this.durationText,
      driverId: driverId ?? this.driverId,
      vehicleId: vehicleId ?? this.vehicleId,
      rideOptions: rideOptions ?? this.rideOptions,
      publicNote: publicNote ?? this.publicNote,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      fromLat: clearFromCoords ? null : (fromLat ?? this.fromLat),
      fromLon: clearFromCoords ? null : (fromLon ?? this.fromLon),
      fromPlaceId: clearFromCoords ? '' : (fromPlaceId ?? this.fromPlaceId),
      toLat: clearToCoords ? null : (toLat ?? this.toLat),
      toLon: clearToCoords ? null : (toLon ?? this.toLon),
      toPlaceId: clearToCoords ? '' : (toPlaceId ?? this.toPlaceId),
      roundtripChoice: roundtripChoice ?? this.roundtripChoice,
      returnPickupLocal: clearReturnPickup
          ? null
          : (returnPickupLocal ?? this.returnPickupLocal),
      returnFromAddress: returnFromAddress ?? this.returnFromAddress,
      returnToAddress: returnToAddress ?? this.returnToAddress,
      returnDurationText: returnDurationText ?? this.returnDurationText,
      returnDriverId: returnDriverId ?? this.returnDriverId,
      returnVehicleId: returnVehicleId ?? this.returnVehicleId,
      returnFromLat: clearReturnCoords
          ? null
          : (returnFromLat ?? this.returnFromLat),
      returnFromLon: clearReturnCoords
          ? null
          : (returnFromLon ?? this.returnFromLon),
      returnFromPlaceId: clearReturnCoords
          ? ''
          : (returnFromPlaceId ?? this.returnFromPlaceId),
      returnToLat: clearReturnCoords ? null : (returnToLat ?? this.returnToLat),
      returnToLon: clearReturnCoords ? null : (returnToLon ?? this.returnToLon),
      returnToPlaceId: clearReturnCoords
          ? ''
          : (returnToPlaceId ?? this.returnToPlaceId),
      fixedPriceSnapshot: clearFixedPriceSnapshot
          ? null
          : (fixedPriceSnapshot ?? this.fixedPriceSnapshot),
    );
  }
}

CompanyAgendaPeriod companyAgendaLinkedBookingsPeriod([DateTime? now]) {
  final today = now ?? DateTime.now();
  final start = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 21));
  final end = DateTime(today.year, today.month, today.day)
      .add(const Duration(days: 21));
  return CompanyAgendaPeriod(
    view: CompanyAgendaView.week,
    anchor: DateTime(today.year, today.month, today.day),
    fromUtc: start.toUtc(),
    toUtc: end.toUtc(),
  );
}

CompanyAgendaPeriod companyAgendaPeriodFor({
  required CompanyAgendaView view,
  required DateTime anchorLocal,
}) {
  final date = DateTime(anchorLocal.year, anchorLocal.month, anchorLocal.day);
  if (view == CompanyAgendaView.day || view == CompanyAgendaView.byDriver) {
    final from = date;
    return CompanyAgendaPeriod(
      view: view,
      anchor: date,
      fromUtc: from.toUtc(),
      toUtc: from.add(const Duration(days: 1)).toUtc(),
    );
  }
  final monday = date.subtract(Duration(days: date.weekday - 1));
  return CompanyAgendaPeriod(
    view: view,
    anchor: date,
    fromUtc: monday.toUtc(),
    toUtc: monday.add(const Duration(days: 7)).toUtc(),
  );
}

String companyCustomerAddressLine(CompanyCustomerAddress address) {
  return <String>[
    address.label,
    address.line1,
    address.city,
  ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(' · ');
}
