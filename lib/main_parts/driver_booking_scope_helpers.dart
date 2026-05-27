part of '../main.dart';

String get kDriverId => resolvedDriverTrackingId;

const bool kDriverAllowAllCompanyRidesDebug = false;
const bool kDriverCanSeeUnassignedRides = false;

String _driverOwnershipBlockedMessage() => _tr(
  nl: 'Deze rit is niet aan jou of jouw voertuig toegewezen.',
  en: 'This ride is not assigned to you or your vehicle.',
  fr: 'This ride is not assigned to you or your vehicle.',
  es: 'This ride is not assigned to you or your vehicle.',
);

String _resolvedActiveDriverIdForScope() {
  final sessionId = activeDriverSessionNotifier.value?.driverId.trim() ?? '';
  if (sessionId.isNotEmpty) return sessionId;
  final resolvedId = resolvedDriverTrackingId.trim();
  if (resolvedId.isNotEmpty) return resolvedId;
  return kDriverId.trim();
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
  final sessionVehicleId =
      activeDriverSessionNotifier.value?.assignedVehicleId?.trim() ?? '';
  return sessionVehicleId;
}

bool _bookingBelongsToActiveDriver(Map<String, dynamic> booking) {
  final activeDriverId = _resolvedActiveDriverIdForScope().trim();
  if (activeDriverId.isEmpty) return false;
  final linkedVehicleIds = _activeDriverLinkedVehicleIds();
  final activeSessionVehicleId = _activeDriverSessionVehicleIdForScope();
  final assignedDriverId = _bookingScopeFirstText(booking, const [
    ['assigned_driver', 'driver_id'],
    ['assigned_driver', 'driverId'],
    ['assigned_driver', 'id'],
    ['assignedDriver', 'driver_id'],
    ['assignedDriver', 'driverId'],
    ['assignedDriver', 'id'],
    ['driver_id'],
    ['driverId'],
    ['booking', 'assigned_driver', 'driver_id'],
    ['booking', 'assigned_driver', 'driverId'],
    ['booking', 'assigned_driver', 'id'],
    ['booking', 'assignedDriver', 'driver_id'],
    ['booking', 'assignedDriver', 'driverId'],
    ['booking', 'assignedDriver', 'id'],
    ['booking', 'driver_id'],
    ['booking', 'driverId'],
    ['record', 'booking', 'assigned_driver', 'driver_id'],
    ['record', 'booking', 'assigned_driver', 'driverId'],
    ['record', 'booking', 'assigned_driver', 'id'],
    ['record', 'booking', 'assignedDriver', 'driver_id'],
    ['record', 'booking', 'assignedDriver', 'driverId'],
    ['record', 'booking', 'assignedDriver', 'id'],
    ['record', 'booking', 'driver_id'],
    ['record', 'booking', 'driverId'],
  ]);
  if (assignedDriverId == activeDriverId) return true;

  final assignedVehicleId = _bookingScopeFirstText(booking, const [
    ['assigned_vehicle_id'],
    ['assignedVehicleId'],
    ['vehicle_id'],
    ['vehicleId'],
    ['booking', 'assigned_vehicle_id'],
    ['booking', 'assignedVehicleId'],
    ['booking', 'vehicle_id'],
    ['booking', 'vehicleId'],
    ['record', 'booking', 'assigned_vehicle_id'],
    ['record', 'booking', 'assignedVehicleId'],
    ['record', 'booking', 'vehicle_id'],
    ['record', 'booking', 'vehicleId'],
  ]);
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
  final assignedDriverId = _bookingScopeFirstText(booking, const [
    ['assigned_driver', 'driver_id'],
    ['assigned_driver', 'driverId'],
    ['assigned_driver', 'id'],
    ['assignedDriver', 'driver_id'],
    ['assignedDriver', 'driverId'],
    ['assignedDriver', 'id'],
    ['driver_id'],
    ['driverId'],
    ['booking', 'assigned_driver', 'driver_id'],
    ['booking', 'assigned_driver', 'driverId'],
    ['booking', 'assigned_driver', 'id'],
    ['booking', 'assignedDriver', 'driver_id'],
    ['booking', 'assignedDriver', 'driverId'],
    ['booking', 'assignedDriver', 'id'],
    ['booking', 'driver_id'],
    ['booking', 'driverId'],
  ]);
  final assignedVehicleId = _bookingScopeFirstText(booking, const [
    ['assigned_vehicle_id'],
    ['assignedVehicleId'],
    ['vehicle_id'],
    ['vehicleId'],
    ['booking', 'assigned_vehicle_id'],
    ['booking', 'assignedVehicleId'],
    ['booking', 'vehicle_id'],
    ['booking', 'vehicleId'],
  ]);
  return (assignedDriverId == null || assignedDriverId.isEmpty) &&
      (assignedVehicleId == null || assignedVehicleId.isEmpty);
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
