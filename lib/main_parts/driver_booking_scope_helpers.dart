part of '../main.dart';

String get kDriverId => resolvedDriverTrackingId;

const bool kDriverAllowAllCompanyRidesDebug = false;
const bool kDriverCanSeeUnassignedRides = false;

/// When non-empty, overrides [_resolvedActiveDriverIdForScope] for ride
/// visibility filtering. DriverHomePage sets this to the effective preview /
/// session driver id while a driver UI surface is mounted.
final ValueNotifier<String> driverRideScopeActiveDriverIdOverride =
    ValueNotifier<String>('');

/// Optional vehicle override for ride-scope filtering (business preview).
final ValueNotifier<String> driverRideScopeActiveVehicleIdOverride =
    ValueNotifier<String>('');

bool _shouldEnforceDriverRideScopeFilter() {
  if (appRoleNotifier.value == AppRole.driver) return true;
  if (driverRideScopeActiveDriverIdOverride.value.trim().isNotEmpty) {
    return true;
  }
  return false;
}

String _resolvedActiveDriverIdForScope() {
  final overrideId = driverRideScopeActiveDriverIdOverride.value.trim();
  if (overrideId.isNotEmpty) return overrideId;
  final sessionId = activeDriverSessionNotifier.value?.driverId.trim() ?? '';
  if (sessionId.isNotEmpty) return sessionId;
  final resolvedId = resolvedDriverTrackingId.trim();
  if (resolvedId.isNotEmpty) return resolvedId;
  return kDriverId.trim();
}

String _driverOwnershipBlockedMessage() => _tr(
  nl: 'Deze rit is niet aan jou of jouw voertuig toegewezen.',
  en: 'This ride is not assigned to you or your vehicle.',
  fr: 'This ride is not assigned to you or your vehicle.',
  es: 'This ride is not assigned to you or your vehicle.',
);

String? _bookingScopeAssignedDriverId(Map<String, dynamic> booking) {
  return _bookingScopeFirstText(booking, const [
    ['assigned_driver_id'],
    ['assignedDriverId'],
    ['assigned_driver', 'driver_id'],
    ['assigned_driver', 'driverId'],
    ['assigned_driver', 'id'],
    ['assignedDriver', 'driver_id'],
    ['assignedDriver', 'driverId'],
    ['assignedDriver', 'id'],
    ['booking', 'assigned_driver_id'],
    ['booking', 'assignedDriverId'],
    ['booking', 'assigned_driver', 'driver_id'],
    ['booking', 'assigned_driver', 'driverId'],
    ['booking', 'assigned_driver', 'id'],
    ['booking', 'assignedDriver', 'driver_id'],
    ['booking', 'assignedDriver', 'driverId'],
    ['booking', 'assignedDriver', 'id'],
    ['record', 'booking', 'assigned_driver_id'],
    ['record', 'booking', 'assignedDriverId'],
    ['record', 'booking', 'assigned_driver', 'driver_id'],
    ['record', 'booking', 'assigned_driver', 'driverId'],
    ['record', 'booking', 'assigned_driver', 'id'],
    ['record', 'booking', 'assignedDriver', 'driver_id'],
    ['record', 'booking', 'assignedDriver', 'driverId'],
    ['record', 'booking', 'assignedDriver', 'id'],
  ]);
}

String? _bookingScopeAssignedVehicleId(Map<String, dynamic> booking) {
  return _bookingScopeFirstText(booking, const [
    ['assigned_vehicle_id'],
    ['assignedVehicleId'],
    ['booking', 'assigned_vehicle_id'],
    ['booking', 'assignedVehicleId'],
    ['record', 'booking', 'assigned_vehicle_id'],
    ['record', 'booking', 'assignedVehicleId'],
  ]);
}

({bool allowed, String reason}) _driverRideScopeVisibilityDecision(
  Map<String, dynamic> booking, {
  required String segment,
}) {
  if (kDriverAllowAllCompanyRidesDebug) {
    return (allowed: true, reason: 'debug_allow_all');
  }
  if (_bookingBelongsToActiveDriver(booking)) {
    return (allowed: true, reason: 'assigned_to_active_driver_or_vehicle');
  }
  if (kDriverCanSeeUnassignedRides && _bookingIsUnassigned(booking)) {
    return (allowed: true, reason: 'unassigned_pool_flag');
  }
  if (_bookingIsBackendAvailableUnassigned(booking)) {
    if (segment == 'available' || segment == 'scope_open') {
      return (allowed: true, reason: 'available_unassigned');
    }
    return (allowed: false, reason: 'available_unassigned_not_my_rides');
  }
  return (allowed: false, reason: 'not_assigned_to_active_scope');
}

String? _bookingScopeText(Map<String, dynamic> booking, List<String> path) {
  dynamic cursor = booking;
  for (final segment in path) {
    if (cursor is! Map || !cursor.containsKey(segment)) return null;
    cursor = cursor[segment];
  }
  final text = cursor?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

String? _bookingScopeFirstText(
  Map<String, dynamic> booking,
  List<List<String>> paths,
) {
  for (final path in paths) {
    final value = _bookingScopeText(booking, path);
    if (value != null) return value;
  }
  return null;
}

Set<String> _activeDriverLinkedVehicleIds() {
  final activeDriverId = _resolvedActiveDriverIdForScope().trim();
  if (activeDriverId.isEmpty) return const <String>{};
  final activeCompany = resolvedCompanyId.trim().isNotEmpty
      ? resolvedCompanyId.trim()
      : kOutboundTenantId.trim();
  final ids = <String>{};
  for (final vehicle in vehiclesNotifier.value) {
    if (!vehicle.isActive) continue;
    final vehicleId = vehicle.id.trim();
    if (vehicleId.isEmpty) continue;
    final driverId = vehicle.driverId?.trim() ?? '';
    if (driverId != activeDriverId) continue;
    final vehicleCompany = vehicle.companyId?.trim() ?? '';
    if (vehicleCompany.isNotEmpty &&
        activeCompany.isNotEmpty &&
        vehicleCompany != activeCompany) {
      continue;
    }
    ids.add(vehicleId);
  }
  return ids;
}

String _activeDriverSessionVehicleIdForScope() {
  final overrideVehicleId = driverRideScopeActiveVehicleIdOverride.value.trim();
  if (overrideVehicleId.isNotEmpty) return overrideVehicleId;
  final sessionVehicleId =
      activeDriverSessionNotifier.value?.assignedVehicleId?.trim() ?? '';
  return sessionVehicleId;
}

bool _bookingBelongsToActiveDriver(Map<String, dynamic> booking) {
  final activeDriverId = _resolvedActiveDriverIdForScope().trim();
  if (activeDriverId.isEmpty) return false;
  final linkedVehicleIds = _activeDriverLinkedVehicleIds();
  final activeSessionVehicleId = _activeDriverSessionVehicleIdForScope();
  final assignedDriverId = _bookingScopeAssignedDriverId(booking);
  if (assignedDriverId != null &&
      assignedDriverId.isNotEmpty &&
      assignedDriverId == activeDriverId) {
    return true;
  }

  final assignedVehicleId = _bookingScopeAssignedVehicleId(booking);
  if (assignedVehicleId != null && assignedVehicleId.isNotEmpty) {
    if (activeSessionVehicleId.isNotEmpty &&
        assignedVehicleId == activeSessionVehicleId) {
      return true;
    }
    if (linkedVehicleIds.contains(assignedVehicleId)) {
      return true;
    }
  }
  return false;
}

bool _bookingIsUnassigned(Map<String, dynamic> booking) {
  final assignedDriverId = _bookingScopeAssignedDriverId(booking);
  final assignedVehicleId = _bookingScopeAssignedVehicleId(booking);
  return (assignedDriverId == null || assignedDriverId.isEmpty) &&
      (assignedVehicleId == null || assignedVehicleId.isEmpty);
}

bool _bookingIsBackendAvailableUnassigned(Map<String, dynamic> booking) {
  final raw = booking['available_unassigned'] ?? booking['availableUnassigned'];
  if (raw == true) return true;
  if (raw is num) return raw == 1;
  if (raw is String) {
    final token = raw.trim().toLowerCase();
    if (token == 'true' || token == '1' || token == 'yes') return true;
  }
  return false;
}

bool _bookingItemIsBackendAvailableUnassigned(BookingItem item) {
  return _bookingIsBackendAvailableUnassigned(
    _driverBookingItemScopeView(item),
  );
}

bool _bookingIsMyAssignedDriverRide(Map<String, dynamic> booking) {
  return _bookingBelongsToActiveDriver(booking);
}

bool _shouldUseDriverBookingsRefreshEndpoint({
  bool driverUiContext = false,
  bool hubVisible = false,
  String? previewDriverId,
  String? effectiveDriverId,
  bool businessPreviewMode = false,
}) {
  // Business preview uses company/admin bookings refresh — never a standalone
  // chauffeur session token.
  if (businessPreviewMode) return false;
  // F3-E: any of these signals are sufficient to prefer the /driver/bookings
  // endpoint over /bookings. The token is still required at call-time to
  // actually authenticate against /driver/bookings; when the token is
  // missing the caller must also block the company /bookings refresh to
  // avoid losing available_unassigned semantics.
  if (appRoleNotifier.value == AppRole.driver) return true;
  final hasToken = (activeDriverSessionNotifier.value?.driverSessionToken ?? '')
      .trim()
      .isNotEmpty;
  if (hasToken) return true;
  if (driverUiContext) return true;
  if (hubVisible) return true;
  if ((previewDriverId ?? '').trim().isNotEmpty) return true;
  if ((effectiveDriverId ?? '').trim().isNotEmpty) return true;
  return false;
}

bool _shouldBlockCompanyBookingsListRefreshInDriverContext({
  required bool bookingsHubVisible,
  bool driverUiContext = false,
  String? previewDriverId,
  String? effectiveDriverId,
  bool businessPreviewMode = false,
}) {
  if (businessPreviewMode) return false;
  if (appRoleNotifier.value == AppRole.driver) return true;
  if (bookingsHubVisible) return true;
  // F3-E: also block while previewing a driver from business_home and any
  // other driver UI context, even before the bookings hub is opened.
  if (driverUiContext) return true;
  if ((previewDriverId ?? '').trim().isNotEmpty) return true;
  if ((effectiveDriverId ?? '').trim().isNotEmpty) return true;
  return _shouldUseDriverBookingsRefreshEndpoint(
    driverUiContext: driverUiContext,
    hubVisible: bookingsHubVisible,
    previewDriverId: previewDriverId,
    effectiveDriverId: effectiveDriverId,
    businessPreviewMode: businessPreviewMode,
  );
}

BookingItem _mergeDriverBookingRefreshItem(
  BookingItem incoming,
  BookingItem? previous,
) {
  if (previous == null) return incoming;
  final incomingView = _driverBookingItemScopeView(incoming);
  if (_bookingIsBackendAvailableUnassigned(incomingView)) return incoming;
  final previousView = _driverBookingItemScopeView(previous);
  if (!_bookingIsBackendAvailableUnassigned(previousView)) return incoming;
  final mergedDetails = Map<String, dynamic>.from(incoming.details)
    ..['available_unassigned'] = true
    ..['availableUnassigned'] = true;
  return incoming.copyWith(details: mergedDetails);
}

bool _canDriverSeeBookingInRidesList(
  Map<String, dynamic> booking, {
  String segment = 'scope_open',
}) {
  final decision = _driverRideScopeVisibilityDecision(
    booking,
    segment: segment,
  );
  if (decision.allowed && decision.reason == 'available_unassigned') {
    final bookingId =
        _bookingScopeFirstText(booking, const [
          ['booking_id'],
          ['bookingId'],
          ['id'],
          ['booking', 'booking_id'],
          ['booking', 'bookingId'],
        ]) ??
        'unknown';
    debugPrint(
      '[DRIVER_SCOPE][AVAILABLE_UNASSIGNED_ALLOW] booking_id=$bookingId',
    );
  }
  return decision.allowed;
}

bool _isDriverCanonicalBookingNumber(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  return RegExp(r'^\d{4}-\d{2}-\d{3,}$').hasMatch(text);
}

bool _isDriverPaymentShadowBookingId(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(text);
}

Map<String, dynamic> _driverBookingItemScopeView(BookingItem item) {
  return <String, dynamic>{
    ...item.details,
    'booking_id': item.bookingId,
    'bookingId': item.bookingId,
    if (item.details['booking'] is! Map)
      'booking': <String, dynamic>{...item.details},
  };
}

bool _isDriverPlanningReferenceId(String value) {
  final text = value.trim();
  if (text.isEmpty) return false;
  return RegExp(r'^PLN-\d{4}-\d+$', caseSensitive: false).hasMatch(text);
}

String _driverBookingPickupMinuteToken(String? pickupIso) {
  final raw = (pickupIso ?? '').trim();
  if (raw.isEmpty) return '';
  try {
    final dt = DateTime.parse(raw).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}T${two(dt.hour)}:${two(dt.minute)}';
  } catch (_) {
    return raw.length >= 16 ? raw.substring(0, 16) : raw;
  }
}

String _normalizeDriverBookingRouteToken(String? value) {
  return (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String? _driverBookingPlanningReference(BookingItem item) {
  final view = _driverBookingItemScopeView(item);
  for (final path in const [
    ['planning_reference'],
    ['planningReference'],
    ['linked_order_reference'],
    ['linkedOrderReference'],
    ['public_booking_reference'],
    ['publicBookingReference'],
    ['booking_reference'],
    ['bookingReference'],
    ['booking', 'planning_reference'],
    ['booking', 'planningReference'],
    ['booking', 'linked_order_reference'],
    ['booking', 'linkedOrderReference'],
  ]) {
    final ref = _bookingScopeFirstText(view, [path]);
    if (ref == null || ref.isEmpty) continue;
    if (_isDriverPlanningReferenceId(ref) ||
        _isDriverCanonicalBookingNumber(ref)) {
      return ref;
    }
  }
  return null;
}

String? _driverBookingOperationalSignature(BookingItem item) {
  final pickupMinute = _driverBookingPickupMinuteToken(item.pickupIso);
  final from = _normalizeDriverBookingRouteToken(item.from);
  final to = _normalizeDriverBookingRouteToken(item.to);
  if (pickupMinute.isEmpty || from.isEmpty || to.isEmpty) return null;
  final price = item.price != null ? item.price!.toStringAsFixed(2) : '';
  return '$pickupMinute|$from|$to|$price';
}

String _driverBookingDedupeIdentityKey(BookingItem item) {
  final signature = _driverBookingOperationalSignature(item);
  if (signature != null) return 'sig:$signature';

  final view = _driverBookingItemScopeView(item);
  for (final path in const [
    ['parent_booking_id'],
    ['parentBookingId'],
    ['canonical_booking_id'],
    ['canonicalBookingId'],
    ['linked_booking_id'],
    ['linkedBookingId'],
    ['booking', 'canonical_booking_id'],
    ['booking', 'canonicalBookingId'],
  ]) {
    final linked = _bookingScopeFirstText(view, [path]);
    if (linked != null && _isDriverCanonicalBookingNumber(linked)) {
      return linked;
    }
  }

  final planningRef = _driverBookingPlanningReference(item);
  if (planningRef != null) return 'plan:${planningRef.toUpperCase()}';

  final bookingId = item.bookingId.trim();
  if (_isDriverCanonicalBookingNumber(bookingId)) return bookingId;
  return bookingId.isNotEmpty ? bookingId : item.rowKey;
}

int _driverVisibleBookingDuplicateRank(BookingItem item) {
  var rank = 0;
  final view = _driverBookingItemScopeView(item);
  final bookingId = item.bookingId.trim();

  if (_isDriverCanonicalBookingNumber(bookingId)) rank += 64;
  final planningRef = _driverBookingPlanningReference(item);
  if (planningRef != null && _isDriverPlanningReferenceId(planningRef)) {
    rank += 32;
  } else if (planningRef != null && planningRef.isNotEmpty) {
    rank += 16;
  }
  if (!_isDriverPaymentShadowBookingId(bookingId)) rank += 8;

  final customerName = _bookingScopeFirstText(view, const [
    ['customer_name'],
    ['customerName'],
    ['customer', 'name'],
    ['booking', 'customer_name'],
    ['booking', 'customerName'],
    ['booking', 'customer', 'name'],
  ]);
  if (customerName != null && customerName.isNotEmpty) rank += 4;
  final customerPhone = _bookingScopeFirstText(view, const [
    ['customer_phone'],
    ['customerPhone'],
    ['customer', 'phone'],
    ['booking', 'customer_phone'],
    ['booking', 'customerPhone'],
    ['booking', 'customer', 'phone'],
  ]);
  if (customerPhone != null && customerPhone.isNotEmpty) rank += 4;
  final customerEmail = _bookingScopeFirstText(view, const [
    ['customer_email'],
    ['customerEmail'],
    ['customer', 'email'],
    ['booking', 'customer_email'],
    ['booking', 'customerEmail'],
    ['booking', 'customer', 'email'],
  ]);
  if (customerEmail != null && customerEmail.isNotEmpty) rank += 4;

  if (item.pax != null) rank += 2;
  if (item.bags != null) rank += 2;
  if ((item.tier ?? '').trim().isNotEmpty) rank += 2;
  final service = _bookingScopeFirstText(view, const [
    ['service'],
    ['booking', 'service'],
  ]);
  if (service != null && service.isNotEmpty) rank += 2;
  if (_bookingIsBackendAvailableUnassigned(view)) rank += 1;

  return rank;
}

BookingItem _mergeAvailableUnassignedFlags(
  BookingItem primary,
  BookingItem other,
) {
  if (_bookingItemIsBackendAvailableUnassigned(primary)) return primary;
  if (!_bookingItemIsBackendAvailableUnassigned(other)) return primary;
  final mergedDetails = Map<String, dynamic>.from(primary.details)
    ..['available_unassigned'] = true
    ..['availableUnassigned'] = true;
  return primary.copyWith(details: mergedDetails);
}

BookingItem _preferDriverVisibleBookingDuplicate(BookingItem a, BookingItem b) {
  final rankA = _driverVisibleBookingDuplicateRank(a);
  final rankB = _driverVisibleBookingDuplicateRank(b);
  final winner = rankA == rankB ? a : (rankA > rankB ? a : b);
  final loser = identical(winner, a) ? b : a;
  return _mergeAvailableUnassignedFlags(winner, loser);
}

List<BookingItem> buildDriverAvailableUnassignedVisibleBookings(
  List<BookingItem> openBookings,
) {
  final flaggedKeys = <String>{};
  for (final item in openBookings) {
    if (!_bookingItemIsBackendAvailableUnassigned(item)) continue;
    if (_bookingIsMyAssignedDriverRide(_driverBookingItemScopeView(item))) {
      continue;
    }
    flaggedKeys.add(_driverBookingDedupeIdentityKey(item));
  }

  final pool = openBookings
      .where((item) {
        final booking = _driverBookingItemScopeView(item);
        if (_bookingIsMyAssignedDriverRide(booking)) return false;
        if (_bookingItemIsBackendAvailableUnassigned(item)) return true;
        if (flaggedKeys.isEmpty) return false;
        return flaggedKeys.contains(_driverBookingDedupeIdentityKey(item));
      })
      .toList(growable: false);

  return _dedupeDriverVisibleBookingItems(pool);
}

List<BookingItem> _dedupeDriverVisibleBookingItems(List<BookingItem> items) {
  if (items.length < 2) return items;
  final bestByKey = <String, BookingItem>{};
  final keyOrder = <String>[];
  for (final item in items) {
    final key = _driverBookingDedupeIdentityKey(item);
    if (!bestByKey.containsKey(key)) {
      keyOrder.add(key);
      bestByKey[key] = item;
      continue;
    }
    final previous = bestByKey[key]!;
    final chosen = _preferDriverVisibleBookingDuplicate(previous, item);
    final dropped = identical(chosen, previous) ? item : previous;
    if (_isDriverPaymentShadowBookingId(dropped.bookingId.trim())) {
      debugPrint(
        '[DRIVER_RIDES][DEDUPED_SHADOW] kept=${chosen.bookingId} dropped=${dropped.bookingId} key=$key',
      );
    }
    bestByKey[key] = chosen;
  }
  return keyOrder.map((key) => bestByKey[key]!).toList(growable: false);
}

bool _canActiveDriverOperateBooking(Map<String, dynamic> booking) {
  final role = appRoleNotifier.value;
  if (role == AppRole.companyAdmin || role == AppRole.dispatcher) return true;
  if (role != AppRole.driver) return true;
  if (kDriverAllowAllCompanyRidesDebug) return true;
  return _bookingBelongsToActiveDriver(booking);
}

Map<String, dynamic> _driverMutationActorFields({
  String? actorDriverId,
  String? actorVehicleId,
}) {
  if (appRoleNotifier.value != AppRole.driver) return const <String, dynamic>{};
  final driverId = (actorDriverId ?? _resolvedActiveDriverIdForScope()).trim();
  final vehicleId = (actorVehicleId ?? '').trim();
  return <String, dynamic>{
    'actor_role': 'driver',
    'actorRole': 'driver',
    if (driverId.isNotEmpty) ...{
      'actor_driver_id': driverId,
      'actorDriverId': driverId,
      'driver_id': driverId,
      'driverId': driverId,
    },
    if (vehicleId.isNotEmpty) ...{
      'actor_vehicle_id': vehicleId,
      'actorVehicleId': vehicleId,
    },
  };
}

bool _outboundTenantFallbackLogged = false;
String _lastDriverScopeLogKey = '';

/// Tenant id for outbound ride/trip Worker payloads.
///
/// Prefer local [CompanyProfile.companyId] ([resolvedCompanyId]) when available.
/// This value is still MVP/provisional client state: backend must later issue
/// the authoritative tenant id for production compliance (including Chiron).
String get kOutboundTenantId {
  final localCompanyId = companyProfileNotifier.value?.companyId.trim();
  if (localCompanyId != null && localCompanyId.isNotEmpty) {
    return localCompanyId;
  }
  if (!_outboundTenantFallbackLogged) {
    _outboundTenantFallbackLogged = true;
    debugPrint(
      '[TENANT][OUTBOUND][FALLBACK] Using default tenant id (no local company profile id).',
    );
  }
  return kTenantId;
}

Map<String, String> _legacyReadOnlyBookingScopeQueryWithFallback() {
  final activeDriverSession = activeDriverSessionNotifier.value;
  final driverTenantId = (activeDriverSession?.tenantId ?? '').trim();
  final driverCompanyId = (activeDriverSession?.companyId ?? '').trim();
  final hasValidCompanyContext =
      CompanySessionStore.instance.hasValidCompanyContext;
  final canUseVerifiedDriverScope =
      !hasValidCompanyContext &&
      driverTenantId.isNotEmpty &&
      driverCompanyId.isNotEmpty &&
      ((activeDriverSession?.isVerifiedPairingSession ?? false) ||
          appRoleNotifier.value == AppRole.driver);
  if (canUseVerifiedDriverScope) {
    final logKey = 'active::$driverTenantId::$driverCompanyId';
    if (_lastDriverScopeLogKey != logKey) {
      _lastDriverScopeLogKey = logKey;
      debugPrint(
        '[DRIVER_SCOPE][ACTIVE] tenant=$driverTenantId company=$driverCompanyId',
      );
    }
    return <String, String>{
      'tenant_id': driverTenantId,
      'company_id': driverCompanyId,
      'tenantId': driverTenantId,
      'companyId': driverCompanyId,
    };
  }

  final tenantId = kOutboundTenantId.trim();
  final companyIdRaw = resolvedCompanyId.trim();
  final companyId = companyIdRaw.isNotEmpty ? companyIdRaw : tenantId;
  final fallbackReason = hasValidCompanyContext
      ? 'company_context'
      : 'default_scope';
  final logKey = 'fallback::$fallbackReason::$tenantId::$companyId';
  if (_lastDriverScopeLogKey != logKey) {
    _lastDriverScopeLogKey = logKey;
    debugPrint(
      '[DRIVER_SCOPE][FALLBACK] reason=$fallbackReason tenant=$tenantId company=$companyId',
    );
  }
  return <String, String>{
    'tenant_id': tenantId,
    'company_id': companyId,
    'tenantId': tenantId,
    'companyId': companyId,
  };
}

/// Legacy read-only compatibility scope.
///
/// Mutation/write paths must use [_strictActiveBookingScopeQuery].
Map<String, String> _activeBookingScopeQuery() {
  return _legacyReadOnlyBookingScopeQueryWithFallback();
}

/// Strict scope for booking/trip mutations.
///
/// This helper is fail-closed and never falls back to default tenant ids.
Map<String, String>? _strictActiveBookingScopeQuery() {
  final activeDriverSession = activeDriverSessionNotifier.value;
  final driverTenantId = (activeDriverSession?.tenantId ?? '').trim();
  final driverCompanyId = (activeDriverSession?.companyId ?? '').trim();
  final canUseVerifiedDriverScope =
      driverTenantId.isNotEmpty &&
      driverCompanyId.isNotEmpty &&
      ((activeDriverSession?.isVerifiedPairingSession ?? false) ||
          appRoleNotifier.value == AppRole.driver);
  if (canUseVerifiedDriverScope) {
    return <String, String>{
      'tenant_id': driverTenantId,
      'company_id': driverCompanyId,
      'tenantId': driverTenantId,
      'companyId': driverCompanyId,
    };
  }

  final profileCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  final hasCompanyContext = CompanySessionStore.instance.hasValidCompanyContext;
  if (hasCompanyContext &&
      profileCompanyId.isNotEmpty &&
      sessionCompanyId.isNotEmpty &&
      profileCompanyId == sessionCompanyId) {
    return <String, String>{
      'tenant_id': sessionCompanyId,
      'company_id': sessionCompanyId,
      'tenantId': sessionCompanyId,
      'companyId': sessionCompanyId,
    };
  }
  return null;
}
