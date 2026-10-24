import 'dart:convert';
import 'package:http/http.dart' as http;

class DriverRideOffer {
  const DriverRideOffer({
    required this.id,
    required this.version,
    required this.vehicleId,
    required this.deadlineMs,
    required this.pickup,
    required this.destination,
    this.price,
    this.bookingId,
    this.requestedVehicleLabel,
    this.requestedChoiceKind,
    this.responseTimeoutMs,
    this.displayedAtMs,
    this.pickupTime,
    this.stops = const [],
    this.returnInfo,
    this.requirements,
  });
  final String id, vehicleId, pickup, destination;
  final int version, deadlineMs;
  final double? price;
  // Explicit canonical owner from the existing offer protocol; never parse offer_id.
  final String? bookingId;
  final String? requestedVehicleLabel, requestedChoiceKind;
  final int? responseTimeoutMs, displayedAtMs;
  final DateTime? pickupTime;
  final List<String> stops;
  final Map<String, dynamic>? returnInfo, requirements;
  static DriverRideOffer parse(
    Map<String, dynamic> row,
    String vehicleId, {
    String? driverId,
    String? tenantId,
    String? companyId,
  }) {
    if (row['human_acceptance_required'] != true ||
        (driverId != null && row['driver_id'] != driverId) ||
        (tenantId != null && row['tenant_id'] != tenantId) ||
        (companyId != null && row['company_id'] != companyId) ||
        row['vehicle_id'] != vehicleId ||
        row['offer_id'] is! String ||
        (row['offer_id'] as String).isEmpty ||
        row['version'] is! int ||
        row['version'] < 1 ||
        row['ack_deadline_ms'] is! int ||
        row['currency'] != 'EUR')
      throw const FormatException('invalid_offer');
    final owner = row['owner_id'];
    if (owner != null && (owner is! String || owner.trim().isEmpty || owner.length > 160)) {
      throw const FormatException('invalid_offer_owner');
    }
    final pickupIso = row['pickup_iso'];
    final pickupTime = pickupIso is String
        ? DateTime.tryParse(pickupIso)
        : null;
    if (pickupIso != null &&
        (pickupTime == null ||
            !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(pickupIso as String))) {
      throw const FormatException('invalid_offer_pickup_time');
    }
    final label = row['requested_vehicle_label'];
    final kind = row['requested_choice_kind'];
    if ((label != null &&
            (label is! String || label.trim().isEmpty || label.length > 100)) ||
        (kind != null && !['type', 'exact'].contains(kind))) {
      throw const FormatException('invalid_offer_context');
    }
    final stops = row['stops'] ?? <String>[];
    if (stops is! List ||
        stops.length > 6 ||
        stops.any((x) => x is! String || x.length > 500) ||
        row['return_info'] != null &&
            row['return_info'] is! Map<String, dynamic> ||
        row['requirements'] != null &&
            row['requirements'] is! Map<String, dynamic>)
      throw const FormatException('invalid_offer_itinerary');
    final price = row['price_incl_vat'];
    final displayTimer = row['response_starts_on_display'] == true;
    if (displayTimer &&
        (row['response_timeout_ms'] is! int ||
            row['response_timeout_ms'] <= 0 ||
            row['displayed_at_ms'] != null && row['displayed_at_ms'] is! int)) {
      throw const FormatException('invalid_offer');
    }
    if (price != null && (price is! num || !price.isFinite || price < 0))
      throw const FormatException('invalid_offer');
    return DriverRideOffer(
      stops: List<String>.unmodifiable(stops.cast<String>()),
      returnInfo: row['return_info'] as Map<String, dynamic>?,
      requirements: row['requirements'] as Map<String, dynamic>?,
      bookingId: owner as String?,
      id: row['offer_id'],
      version: row['version'],
      vehicleId: vehicleId,
      deadlineMs: row['ack_deadline_ms'],
      pickup: row['pickup_address'] is String ? row['pickup_address'] : '',
      destination: row['dropoff_address'] is String
          ? row['dropoff_address']
          : '',
      price: (price as num?)?.toDouble(),
      requestedVehicleLabel: label as String?,
      requestedChoiceKind: kind as String?,
      responseTimeoutMs: displayTimer ? row['response_timeout_ms'] : null,
      displayedAtMs: displayTimer ? row['displayed_at_ms'] : null,
      pickupTime: pickupTime,
    );
  }

  int secondsRemaining(int nowMs) {
    if (nowMs >= deadlineMs) return 0;
    if (responseTimeoutMs != null && displayedAtMs == null) {
      return (responseTimeoutMs! / 1000).ceil().clamp(0, 86400);
    }
    return ((deadlineMs - nowMs) / 1000).ceil().clamp(0, 86400);
  }
}

class DriverScheduledReadiness {
  const DriverScheduledReadiness(this.offerId, this.version, this.deadlineMs);
  final String offerId;
  final int version, deadlineMs;

  static DriverScheduledReadiness parse(Map<String,dynamic> row, {
    required String vehicleId, required String? driverId,
    required String? tenantId, required String? companyId,
  }) {
    final pickup = row['pickup_iso'] is String ? DateTime.tryParse(row['pickup_iso']) : null;
    if (row['schema'] != 'fluxidi-scheduled-readiness-v1' ||
        row['readiness_type'] != 'scheduled_readiness' ||
        row['human_acceptance_required'] != false ||
        driverId == null || tenantId == null || companyId == null ||
        row['driver_id'] != driverId || row['tenant_id'] != tenantId ||
        row['company_id'] != companyId || row['vehicle_id'] != vehicleId ||
        row['booking_id'] is! String || (row['booking_id'] as String).isEmpty ||
        row['offer_id'] is! String || (row['offer_id'] as String).isEmpty ||
        row['version'] is! int || row['version'] < 1 ||
        row['ack_deadline_ms'] is! int || row['ack_deadline_ms'] < 0 || pickup == null) {
      throw const FormatException('invalid_scheduled_readiness');
    }
    return DriverScheduledReadiness(row['offer_id'], row['version'], row['ack_deadline_ms']);
  }
}

class DriverRideOfferClient {
  DriverRideOfferClient({
    required this.baseUrl,
    required this.token,
    required this.vehicleId,
    this.driverId,
    this.tenantId,
    this.companyId,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl, token, vehicleId;
  final String? driverId, tenantId, companyId;
  final http.Client _client;
  int pollAfterMs =
      2000; // Legacy paired cockpit contract when no hint is sent.
  List<DriverScheduledReadiness> scheduledReadiness = const [];
  void close() => _client.close();
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (token.isEmpty || vehicleId.isEmpty)
      throw StateError('personal_driver_required');
    final response = await _client
        .post(
          Uri.parse('$baseUrl/public/driver/dispatch/$path'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));
    final dynamic result = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        result is! Map<String, dynamic> ||
        result['ok'] != true)
      throw StateError('offer_request_unconfirmed');
    return result;
  }

  Future<List<DriverRideOffer>> offers() async {
    scheduledReadiness = const [];
    final result = await _post('offers', {});
    final poll = result['poll_after_ms'];
    if (poll != null && (poll is! int || !const [2000, 10000].contains(poll))) {
      throw const FormatException('invalid_offer_poll_policy');
    }
    pollAfterMs = poll as int? ?? 2000;
    if (result['vehicle_id'] != vehicleId || result['offers'] is! List)
      throw const FormatException('invalid_offers');
    final offers = (result['offers'] as List)
        .map(
          (row) => DriverRideOffer.parse(
            Map<String, dynamic>.from(row as Map),
            vehicleId,
            driverId: driverId,
            tenantId: tenantId,
            companyId: companyId,
          ),
        )
        .toList();
    final raw = result['legacy_receipts'] ?? const [];
    if (raw is! List || raw.length > 20) throw const FormatException('invalid_scheduled_readiness');
    final seen = <String>{};
    final parsed = <DriverScheduledReadiness>[];
    for (final row in raw) {
      if (row is! Map) throw const FormatException('invalid_scheduled_readiness');
      final receipt = DriverScheduledReadiness.parse(Map<String,dynamic>.from(row),
          vehicleId: vehicleId, driverId: driverId, tenantId: tenantId, companyId: companyId);
      if (!seen.add('${receipt.offerId}:${receipt.version}')) throw const FormatException('duplicate_scheduled_readiness');
      parsed.add(receipt);
    }
    scheduledReadiness = List.unmodifiable(parsed);
    return offers;
  }

  Future<void> acknowledgeScheduledReadiness(DriverScheduledReadiness receipt, {
    required bool Function() isCurrent,
  }) async {
    if (!scheduledReadiness.contains(receipt) || !isCurrent() ||
        receipt.deadlineMs <= DateTime.now().millisecondsSinceEpoch) return;
    // Transport readiness only. Human proposals use displayed/decision instead.
    await _post('ack', {'offer_id':receipt.offerId,'version':receipt.version});
  }

  Future<void> stopOffers() async => _post('offers', {'visible': false});

  Future<DriverRideOffer?> received(DriverRideOffer offer) async {
    final result = await _post('ack', {
      'offer_id': offer.id,
      'version': offer.version,
    });
    if (offer.responseTimeoutMs == null) return null;
    final raw = result['offer'];
    if (raw == null && driverId == null)
      return null; // Legacy injected transport.
    if (raw is! Map ||
        raw['offer_id'] != offer.id ||
        raw['version'] != offer.version ||
        (tenantId != null && raw['tenant_id'] != tenantId) ||
        (companyId != null && raw['company_id'] != companyId) ||
        (driverId != null && raw['driver_id'] != driverId) ||
        raw['vehicle_id'] != vehicleId ||
        raw['ack_deadline_ms'] is! int) {
      throw const FormatException('invalid_offer_receipt');
    }
    final receipts = raw['receipts'];
    final receipt = receipts is Map
        ? receipts[driverId ?? raw['driver_id']]
        : null;
    final displayed = receipt is Map ? receipt['displayed_at_ms'] : null;
    final deadline = raw['ack_deadline_ms'] as int;
    if (displayed is! int ||
        displayed < 0 ||
        deadline < displayed ||
        deadline > displayed + offer.responseTimeoutMs! ||
        deadline > offer.deadlineMs + offer.responseTimeoutMs!) {
      throw const FormatException('invalid_offer_receipt_timer');
    }
    return DriverRideOffer(
      bookingId: offer.bookingId,
      id: offer.id,
      version: offer.version,
      vehicleId: offer.vehicleId,
      deadlineMs: deadline,
      pickup: offer.pickup,
      destination: offer.destination,
      price: offer.price,
      requestedVehicleLabel: offer.requestedVehicleLabel,
      requestedChoiceKind: offer.requestedChoiceKind,
      responseTimeoutMs: offer.responseTimeoutMs,
      displayedAtMs: displayed,
      pickupTime: offer.pickupTime,
      stops: offer.stops,
      returnInfo: offer.returnInfo,
      requirements: offer.requirements,
    );
  }

  Future<void> decide(DriverRideOffer offer, String action) async {
    if (!['accept', 'decline'].contains(action) || offer.vehicleId != vehicleId)
      throw ArgumentError('invalid_decision');
    await _post('decision', {
      'offer_id': offer.id,
      'version': offer.version,
      'action': action,
    });
  }
}
