import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_agenda_scope_io.dart'
    if (dart.library.html) 'package:fluxidi_tracking/company/company_agenda_scope_web.dart';

const String kCompanyAgendaRidesPath = '/company/agenda/rides';
const String kCompanyAgendaOverlapPath = '/company/agenda/overlap';
const String kCompanyAgendaQuotePathAlias = '/company/agenda/quote';

/// Period page size advertised to the Worker. Never inferred from item count.
const int kCompanyAgendaHttpPageLimit = 200;

/// Hard cap for one period load. Prevents an unbounded history download.
const int kCompanyAgendaHttpMaxPages = 5;

class CompanyAgendaRideCollection {
  const CompanyAgendaRideCollection({
    required this.rides,
    this.incomplete = false,
  });

  final List<CompanyAgendaRide> rides;
  final bool incomplete;
}

class CompanyAgendaRidesPage {
  const CompanyAgendaRidesPage({
    required this.items,
    required this.unscheduled,
    required this.hasMore,
    this.nextCursor,
  });

  final List<CompanyAgendaRide> items;
  final List<CompanyAgendaRide> unscheduled;
  final bool hasMore;
  final String? nextCursor;
}

CompanyAgendaRidesPage parseCompanyAgendaRidesPage(Map<String, dynamic> decoded) {
  List<CompanyAgendaRide> parseList(Object? raw) {
    if (raw is! List) return const <CompanyAgendaRide>[];
    return <CompanyAgendaRide>[
      for (final row in raw.whereType<Map>())
        CompanyAgendaRide.fromMap(Map<String, dynamic>.from(row)),
    ];
  }

  final cursor = decoded['next_cursor']?.toString().trim() ?? '';
  final hasMore = decoded['has_more'] == true && cursor.isNotEmpty;
  return CompanyAgendaRidesPage(
    items: parseList(decoded['items']),
    unscheduled: parseList(decoded['unscheduled']),
    hasMore: hasMore,
    nextCursor: hasMore ? cursor : null,
  );
}

Future<CompanyAgendaRideCollection> collectCompanyAgendaRidePages({
  required Future<CompanyAgendaRidesPage> Function(String cursor) fetchPage,
  int maxPages = kCompanyAgendaHttpMaxPages,
}) async {
  final seen = <String>{};
  final rides = <CompanyAgendaRide>[];
  var cursor = '';
  var incomplete = false;
  for (var pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
    final page = await fetchPage(cursor);
    void addAll(List<CompanyAgendaRide> rows) {
      for (final ride in rows) {
        final id = ride.collectionId;
        if (id.isEmpty || !seen.add(id)) continue;
        rides.add(ride);
      }
    }

    addAll(page.items);
    addAll(page.unscheduled);
    final next = page.nextCursor?.trim() ?? '';
    if (!page.hasMore || next.isEmpty || next == cursor) {
      incomplete = false;
      break;
    }
    cursor = next;
    if (pageIndex == maxPages - 1) {
      incomplete = true;
    }
  }
  return CompanyAgendaRideCollection(
    rides: List<CompanyAgendaRide>.unmodifiable(rides),
    incomplete: incomplete,
  );
}

class CompanyAgendaOverlapCheck {
  const CompanyAgendaOverlapCheck.ok()
    : code = '',
      conflictingBookingId = '';

  const CompanyAgendaOverlapCheck.error(
    this.code, {
    this.conflictingBookingId = '',
  });

  final String code;
  final String conflictingBookingId;

  bool get hasConflict => code.isNotEmpty;
}

typedef CompanyAgendaOverlapTransport =
    Future<CompanyAgendaOverlapCheck> Function({
      required String driverId,
      String vehicleId,
      required String pickupIso,
      int? durationMin,
      String excludeBookingId,
      String returnPickupIso,
      int? returnDurationMin,
      String roundtripMode,
    });

class CompanyAgendaException implements Exception {
  const CompanyAgendaException(this.code, {this.offline = false});
  final String code;
  final bool offline;

  @override
  String toString() => 'CompanyAgendaException($code)';
}

bool companyAgendaErrorLooksOffline(Object error) {
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('failed host lookup') ||
      text.contains('timed out') ||
      text.contains('timeout');
}

Never throwCompanyAgendaHttpError(Object error) {
  if (error is CompanyAgendaException) throw error;
  throw CompanyAgendaException(
    'transport_failed',
    offline: companyAgendaErrorLooksOffline(error),
  );
}

Map<String, dynamic>? tryDecodeCompanyAgendaJson(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

Future<CompanyAgendaRideCollection> fetchCompanyAgendaRides({
  required CompanyAgendaPeriod period,
  Future<Map<String, String>> Function()? headers,
  Map<String, String>? Function()? scopeResolver,
}) async {
  final scope = (scopeResolver ?? resolveCompanyAgendaScopeQuery)();
  if (scope == null) {
    throw const CompanyAgendaException('missing_company_scope');
  }
  try {
    final resolvedHeaders = await (headers ?? resolveCompanyAgendaHeaders)();
    return collectCompanyAgendaRidePages(
      fetchPage: (cursor) async {
        final uri = Uri.parse('$kBookingBaseUrl$kCompanyAgendaRidesPath').replace(
          queryParameters: <String, String>{
            ...scope,
            'from': period.fromUtc.toIso8601String(),
            'to': period.toUtc.toIso8601String(),
            'limit': '$kCompanyAgendaHttpPageLimit',
            if (cursor.isNotEmpty) 'cursor': cursor,
          },
        );
        final res = await http
            .get(uri, headers: resolvedHeaders)
            .timeout(const Duration(seconds: 12));
        final decoded = tryDecodeCompanyAgendaJson(res.bodyBytes);
        if (res.statusCode != 200 || decoded == null || decoded['ok'] != true) {
          throw CompanyAgendaException(
            decoded?['error']?.toString().trim().isNotEmpty == true
                ? decoded!['error'].toString()
                : 'http_${res.statusCode}',
          );
        }
        return parseCompanyAgendaRidesPage(decoded);
      },
    );
  } catch (error) {
    throwCompanyAgendaHttpError(error);
  }
}

Future<CompanyAgendaRide> createCompanyAgendaRide({
  required CompanyRidePlanDraft draft,
  required String idempotencyKey,
  Future<Map<String, String>> Function()? headers,
  Map<String, String>? Function()? scopeResolver,
}) async {
  final scope = (scopeResolver ?? resolveCompanyAgendaScopeQuery)();
  if (scope == null) {
    throw const CompanyAgendaException('missing_company_scope');
  }
  final price = num.tryParse(draft.priceText.trim());
  final duration = int.tryParse(draft.durationText.trim());
  final body = <String, dynamic>{
    ...scope,
    'customer_id': draft.customer.customerId,
    'customer_name': draft.customer.displayName,
    'customer_email': draft.customer.email,
    'customer_phone': draft.customer.phone,
    'from': draft.fromAddress.trim(),
    'to': draft.toAddress.trim(),
    if (draft.fromLat != null && draft.fromLat!.isFinite) 'pickup_lat': draft.fromLat,
    if (draft.fromLon != null && draft.fromLon!.isFinite) 'pickup_lon': draft.fromLon,
    if (draft.fromPlaceId.trim().isNotEmpty) 'pickup_place_id': draft.fromPlaceId.trim(),
    if (draft.toLat != null && draft.toLat!.isFinite) 'dropoff_lat': draft.toLat,
    if (draft.toLon != null && draft.toLon!.isFinite) 'dropoff_lon': draft.toLon,
    if (draft.toPlaceId.trim().isNotEmpty) 'dropoff_place_id': draft.toPlaceId.trim(),
    'pickup_iso': draft.pickupLocal.toUtc().toIso8601String(),
    'passengers': draft.passengers,
    if (price != null) 'price_incl_vat': price,
    if (duration != null && duration > 0) 'duration_min': duration,
    if (draft.durationRouteMin != null && draft.durationRouteMin! > 0)
      'duration_route_min': draft.durationRouteMin,
    if (draft.distanceKm != null && draft.distanceKm! > 0)
      'distance_km': draft.distanceKm,
    if (draft.pricingSource.trim().isNotEmpty)
      'pricing_source': draft.pricingSource.trim(),
    if (draft.currency.trim().isNotEmpty) 'currency': draft.currency.trim(),
    if (draft.driverId.trim().isNotEmpty)
      'assigned_driver_id': draft.driverId.trim(),
    if (draft.vehicleId.trim().isNotEmpty)
      'assigned_vehicle_id': draft.vehicleId.trim(),
    if (draft.publicNote.trim().isNotEmpty) 'note': draft.publicNote.trim(),
    'ride_options': draft.rideOptions.toJson(),
    if (draft.rideOptions.service.isNotEmpty)
      'service': draft.rideOptions.service,
    if (draft.rideOptions.tier.isNotEmpty) 'tier': draft.rideOptions.tier,
    if (draft.rideOptions.bags > 0) 'bags': draft.rideOptions.bags,
    if (draft.rideOptions.waitMin > 0 &&
        draft.roundtripChoice == CompanyRoundtripChoice.single)
      'wait_min': draft.rideOptions.waitMin,
    if (draft.rideOptions.flightNumber.isNotEmpty)
      'flight_number': draft.rideOptions.flightNumber,
    if (draft.rideOptions.airportDirection.isNotEmpty)
      'airport_direction': draft.rideOptions.airportDirection,
    if (draft.rideOptions.extra.isNotEmpty) 'extra': draft.rideOptions.extra,
    if (draft.rideOptions.meetAndGreet) 'meet_and_greet': true,
    if (draft.rideOptions.nameBoard.isNotEmpty)
      'name_board': draft.rideOptions.nameBoard,
    'return_enabled':
        draft.roundtripChoice != CompanyRoundtripChoice.single,
    'roundtrip_dispatch_mode': companyRoundtripChoiceWire(draft.roundtripChoice),
    if (draft.returnPickupLocal != null)
      'return_pickup_iso': draft.returnPickupLocal!.toUtc().toIso8601String(),
    if (draft.returnFromAddress.trim().isNotEmpty)
      'return_from': draft.returnFromAddress.trim(),
    if (draft.returnToAddress.trim().isNotEmpty)
      'return_to': draft.returnToAddress.trim(),
    if (int.tryParse(draft.returnDurationText.trim()) != null &&
        int.parse(draft.returnDurationText.trim()) > 0)
      'return_duration_min': int.parse(draft.returnDurationText.trim()),
    if (draft.returnDriverId.trim().isNotEmpty)
      'return_assigned_driver_id': draft.returnDriverId.trim(),
    if (draft.returnVehicleId.trim().isNotEmpty)
      'return_assigned_vehicle_id': draft.returnVehicleId.trim(),
    if (draft.returnFromLat != null && draft.returnFromLat!.isFinite)
      'return_pickup_lat': draft.returnFromLat,
    if (draft.returnFromLon != null && draft.returnFromLon!.isFinite)
      'return_pickup_lon': draft.returnFromLon,
    if (draft.returnFromPlaceId.trim().isNotEmpty)
      'return_pickup_place_id': draft.returnFromPlaceId.trim(),
    if (draft.returnToLat != null && draft.returnToLat!.isFinite)
      'return_dropoff_lat': draft.returnToLat,
    if (draft.returnToLon != null && draft.returnToLon!.isFinite)
      'return_dropoff_lon': draft.returnToLon,
    if (draft.returnToPlaceId.trim().isNotEmpty)
      'return_dropoff_place_id': draft.returnToPlaceId.trim(),
    if (draft.rideOptions.airportIata.isNotEmpty)
      'airport_iata': draft.rideOptions.airportIata,
    if (draft.rideOptions.flightAt.isNotEmpty)
      'flight_at': draft.rideOptions.flightAt,
    if (draft.rideOptions.pickupArrangement.isNotEmpty)
      'pickup_arrangement': draft.rideOptions.pickupArrangement,
    if (draft.rideOptions.returnAirportIata.isNotEmpty)
      'return_airport_iata': draft.rideOptions.returnAirportIata,
    if (draft.rideOptions.returnFlightNumber.isNotEmpty)
      'return_flight_number': draft.rideOptions.returnFlightNumber,
    if (draft.rideOptions.returnFlightAt.isNotEmpty)
      'return_flight_at': draft.rideOptions.returnFlightAt,
    if (draft.fixedPriceSnapshot != null &&
        (draft.fixedPriceSnapshot!['fixed_fare_rule_id']
                ?.toString()
                .isNotEmpty ??
            false))
      'fixed_price_snapshot': draft.fixedPriceSnapshot,
  };
  try {
    final resolved = await (headers ?? resolveCompanyAgendaHeaders)();
    final res = await http
        .post(
          Uri.parse('$kBookingBaseUrl$kCompanyAgendaRidesPath').replace(
            queryParameters: scope,
          ),
          headers: <String, String>{
            ...resolved,
            'Content-Type': 'application/json',
            'Idempotency-Key': idempotencyKey,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = tryDecodeCompanyAgendaJson(res.bodyBytes);
    if (decoded == null || decoded['ok'] != true) {
      throw CompanyAgendaException(
        decoded?['error']?.toString().trim().isNotEmpty == true
            ? decoded!['error'].toString()
            : 'http_${res.statusCode}',
      );
    }
    final item = decoded['item'];
    final warning = decoded['assignment_warning'];
    final warningCode = warning is Map
        ? (warning['error']?.toString() ?? '')
        : '';
    if (item is Map) {
      return CompanyAgendaRide.fromMap(
        Map<String, dynamic>.from(item),
      ).copyWithAssignmentWarning(warningCode);
    }
    final bookingId = decoded['booking_id']?.toString() ?? '';
    if (bookingId.isEmpty) {
      throw const CompanyAgendaException('invalid_payload');
    }
    return CompanyAgendaRide(
      bookingId: bookingId,
      customerId: draft.customer.customerId,
      customerName: draft.customer.displayName,
      fromAddress: draft.fromAddress,
      toAddress: draft.toAddress,
      pickupIso: draft.pickupLocal.toUtc().toIso8601String(),
      status: 'PENDING',
      assignedDriverId: draft.driverId,
      assignedVehicleId: draft.vehicleId,
      durationUnknown: duration == null || duration <= 0,
      durationMin: duration,
      assignmentWarning: warningCode,
    );
  } catch (error) {
    throwCompanyAgendaHttpError(error);
  }
}

Future<CompanyAgendaRide> mutateCompanyAgendaRide({
  required String bookingId,
  required String action,
  Map<String, dynamic> body = const <String, dynamic>{},
  Future<Map<String, String>> Function()? headers,
  Map<String, String>? Function()? scopeResolver,
}) async {
  final scope = (scopeResolver ?? resolveCompanyAgendaScopeQuery)();
  if (scope == null) {
    throw const CompanyAgendaException('missing_company_scope');
  }
  final id = bookingId.trim();
  if (id.isEmpty) {
    throw const CompanyAgendaException('booking_required');
  }
  try {
    final resolved = await (headers ?? resolveCompanyAgendaHeaders)();
    final res = await http
        .post(
          Uri.parse(
            '$kBookingBaseUrl$kCompanyAgendaRidesPath/$id/$action',
          ).replace(queryParameters: scope),
          headers: <String, String>{
            ...resolved,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{...scope, ...body}),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = tryDecodeCompanyAgendaJson(res.bodyBytes);
    if (decoded == null || decoded['ok'] != true) {
      throw CompanyAgendaException(
        decoded?['error']?.toString().trim().isNotEmpty == true
            ? decoded!['error'].toString()
            : 'http_${res.statusCode}',
      );
    }
    final item = decoded['item'];
    if (item is Map) {
      return CompanyAgendaRide.fromMap(Map<String, dynamic>.from(item));
    }
    throw const CompanyAgendaException('invalid_payload');
  } catch (error) {
    throwCompanyAgendaHttpError(error);
  }
}

Future<CompanyAgendaOverlapCheck> checkCompanyAgendaOverlap({
  required String driverId,
  String vehicleId = '',
  required String pickupIso,
  int? durationMin,
      String excludeBookingId = '',
  String returnPickupIso = '',
  int? returnDurationMin,
  String roundtripMode = '',
  Future<Map<String, String>> Function()? headers,
  Map<String, String>? Function()? scopeResolver,
}) async {
  final scope = (scopeResolver ?? resolveCompanyAgendaScopeQuery)();
  if (scope == null) {
    throw const CompanyAgendaException('missing_company_scope');
  }
  try {
    final query = <String, String>{
      ...scope,
      if (driverId.trim().isNotEmpty) 'driver_id': driverId.trim(),
      if (vehicleId.trim().isNotEmpty) 'vehicle_id': vehicleId.trim(),
      'pickup_iso': pickupIso.trim(),
      if (durationMin != null && durationMin > 0)
        'duration_min': '$durationMin',
      if (excludeBookingId.trim().isNotEmpty)
        'exclude_booking_id': excludeBookingId.trim(),
      if (returnPickupIso.trim().isNotEmpty)
        'return_pickup_iso': returnPickupIso.trim(),
      if (returnDurationMin != null && returnDurationMin > 0)
        'return_duration_min': '$returnDurationMin',
      if (roundtripMode.trim().isNotEmpty)
        'roundtrip_dispatch_mode': roundtripMode.trim(),
    };
    final res = await http
        .get(
          Uri.parse('$kBookingBaseUrl$kCompanyAgendaOverlapPath').replace(
            queryParameters: query,
          ),
          headers: await (headers ?? resolveCompanyAgendaHeaders)(),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = tryDecodeCompanyAgendaJson(res.bodyBytes);
    if (res.statusCode == 200 && decoded != null && decoded['ok'] == true) {
      return const CompanyAgendaOverlapCheck.ok();
    }
    final code = decoded?['error']?.toString().trim() ?? '';
    final bookingId = decoded?['booking_id']?.toString().trim() ??
        decoded?['bookingId']?.toString().trim() ??
        '';
    if (code.isNotEmpty) {
      return CompanyAgendaOverlapCheck.error(
        code,
        conflictingBookingId: bookingId,
      );
    }
    throw CompanyAgendaException(
      'http_${res.statusCode}',
    );
  } catch (error) {
    throwCompanyAgendaHttpError(error);
  }
}

typedef CompanyAgendaListTransport =
    Future<List<CompanyAgendaRide>> Function(CompanyAgendaPeriod period);
typedef CompanyAgendaCreateTransport =
    Future<CompanyAgendaRide> Function({
      required CompanyRidePlanDraft draft,
      required String idempotencyKey,
    });
typedef CompanyAgendaMutateTransport =
    Future<CompanyAgendaRide> Function({
      required String bookingId,
      required String action,
      required Map<String, dynamic> body,
    });

class CompanyAgendaRepository {
  CompanyAgendaRepository({
    this.headers,
    this.scopeResolver,
    this.listTransport,
    this.createTransport,
    this.mutateTransport,
    this.overlapTransport,
  });

  final Future<Map<String, String>> Function()? headers;
  final Map<String, String>? Function()? scopeResolver;
  final CompanyAgendaListTransport? listTransport;
  final CompanyAgendaCreateTransport? createTransport;
  final CompanyAgendaMutateTransport? mutateTransport;
  final CompanyAgendaOverlapTransport? overlapTransport;

  final Map<String, List<CompanyAgendaRide>> _periodCache =
      <String, List<CompanyAgendaRide>>{};
  final Map<String, bool> _periodIncomplete = <String, bool>{};
  String? _boundCompanyId;

  Map<String, String>? get scope =>
      (scopeResolver ?? resolveCompanyAgendaScopeQuery)();

  String? get companyId => scope?['company_id'];

  String _cacheKey(CompanyAgendaPeriod period) =>
      '${_boundCompanyId ?? ''}|${period.cacheKey}';

  void _bindCompany() {
    final id = companyId;
    if (id != _boundCompanyId) {
      _periodCache.clear();
      _periodIncomplete.clear();
      _boundCompanyId = id;
    }
  }

  void clearCompanyScoped() {
    _periodCache.clear();
    _periodIncomplete.clear();
    _boundCompanyId = companyId;
  }

  bool isPeriodIncomplete(CompanyAgendaPeriod period) {
    _bindCompany();
    return _periodIncomplete[_cacheKey(period)] == true;
  }

  bool hasCachedPeriod(CompanyAgendaPeriod period) {
    _bindCompany();
    return _periodCache.containsKey(_cacheKey(period));
  }

  Future<List<CompanyAgendaRide>> listPeriod(
    CompanyAgendaPeriod period, {
    bool force = false,
  }) async {
    _bindCompany();
    final key = _cacheKey(period);
    if (!force && _periodCache.containsKey(key)) {
      return _periodCache[key]!;
    }
    if (listTransport != null) {
      final rides = await listTransport!(period);
      _periodCache[key] = rides;
      _periodIncomplete[key] = false;
      return rides;
    }
    final collected = await fetchCompanyAgendaRides(
      period: period,
      headers: headers,
      scopeResolver: scopeResolver,
    );
    _periodCache[key] = collected.rides;
    _periodIncomplete[key] = collected.incomplete;
    return collected.rides;
  }

  Future<CompanyAgendaRide> createRide({
    required CompanyRidePlanDraft draft,
    required String idempotencyKey,
  }) async {
    _bindCompany();
    final ride = createTransport != null
        ? await createTransport!(
            draft: draft,
            idempotencyKey: idempotencyKey,
          )
        : await createCompanyAgendaRide(
            draft: draft,
            idempotencyKey: idempotencyKey,
            headers: headers,
            scopeResolver: scopeResolver,
          );
    _invalidateCompanyCache();
    return ride;
  }

  void _invalidateCompanyCache() {
    _periodCache.removeWhere(
      (key, _) => key.startsWith('${_boundCompanyId ?? ''}|'),
    );
    _periodIncomplete.removeWhere(
      (key, _) => key.startsWith('${_boundCompanyId ?? ''}|'),
    );
  }

  Future<CompanyAgendaRide> _mutate({
    required String bookingId,
    required String action,
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    _bindCompany();
    final ride = mutateTransport != null
        ? await mutateTransport!(
            bookingId: bookingId,
            action: action,
            body: body,
          )
        : await mutateCompanyAgendaRide(
            bookingId: bookingId,
            action: action,
            body: body,
            headers: headers,
            scopeResolver: scopeResolver,
          );
    _invalidateCompanyCache();
    return ride;
  }

  Future<CompanyAgendaRide> assignRide({
    required String bookingId,
    required String driverId,
    String vehicleId = '',
    int? revision,
    String legId = '',
    String legType = '',
  }) {
    return _mutate(
      bookingId: bookingId,
      action: 'assign',
      body: <String, dynamic>{
        if (driverId.trim().isNotEmpty) 'assigned_driver_id': driverId.trim(),
        if (vehicleId.trim().isNotEmpty) 'assigned_vehicle_id': vehicleId.trim(),
        if (revision != null) 'revision': revision,
        if (legId.trim().isNotEmpty) 'leg_id': legId.trim(),
        if (legType.trim().isNotEmpty) 'leg_type': legType.trim(),
      },
    );
  }

  Future<CompanyAgendaRide> unassignRide({
    required String bookingId,
    int? revision,
  }) {
    return _mutate(
      bookingId: bookingId,
      action: 'unassign',
      body: <String, dynamic>{
        if (revision != null) 'revision': revision,
      },
    );
  }

  Future<CompanyAgendaRide> rescheduleRide({
    required String bookingId,
    required DateTime pickupLocal,
    int? revision,
    String legId = '',
    String legType = '',
  }) {
    return _mutate(
      bookingId: bookingId,
      action: 'reschedule',
      body: <String, dynamic>{
        'pickup_iso': pickupLocal.toUtc().toIso8601String(),
        if (revision != null) 'revision': revision,
        if (legId.trim().isNotEmpty) 'leg_id': legId.trim(),
        if (legType.trim().isNotEmpty) 'leg_type': legType.trim(),
      },
    );
  }

  Future<CompanyAgendaRide> phoneConfirmRide({
    required String bookingId,
    String actor = 'company_admin',
  }) {
    return _mutate(
      bookingId: bookingId,
      action: 'phone-confirm',
      body: <String, dynamic>{'actor': actor},
    );
  }

  Future<CompanyAgendaOverlapCheck> checkOverlap({
    required String driverId,
    String vehicleId = '',
    required String pickupIso,
    int? durationMin,
    String excludeBookingId = '',
    String returnPickupIso = '',
    int? returnDurationMin,
    String roundtripMode = '',
  }) async {
    _bindCompany();
    if (overlapTransport != null) {
      return overlapTransport!(
        driverId: driverId,
        vehicleId: vehicleId,
        pickupIso: pickupIso,
        durationMin: durationMin,
        excludeBookingId: excludeBookingId,
        returnPickupIso: returnPickupIso,
        returnDurationMin: returnDurationMin,
        roundtripMode: roundtripMode,
      );
    }
    if (listTransport != null || mutateTransport != null) {
      return const CompanyAgendaOverlapCheck.ok();
    }
    return checkCompanyAgendaOverlap(
      driverId: driverId,
      vehicleId: vehicleId,
      pickupIso: pickupIso,
      durationMin: durationMin,
      excludeBookingId: excludeBookingId,
      returnPickupIso: returnPickupIso,
      returnDurationMin: returnDurationMin,
      roundtripMode: roundtripMode,
      headers: headers,
      scopeResolver: scopeResolver,
    );
  }
}
