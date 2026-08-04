part of '../main.dart';

/// Shared chauffeur KPI data pipeline.
///
/// Both driver-home ("Mijn prestaties") and company Drivers → Rapporten open
/// [DriverKpiPage] with a fetcher that calls [fetchDriverKpiRidesFromTripsHistory].
/// That keeps one source of truth: scoped `/trips/history` rows, street-history
/// canonicalization, and the same payment/status mapping — no second KPI store.

String _driverKpiMaskScopeForLog(String value) {
  final text = value.trim();
  if (text.isEmpty) return '—';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

DriverKpiPaymentState _driverKpiPaymentStateForTripHistoryItem(
  _TripHistoryItem item,
) {
  final details = item.bookingDetails;
  String pick(List<String> keys) {
    for (final key in keys) {
      final value = details[key];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  final invoiceStatus = pick(<String>[
    'business_invoice_status',
    'businessInvoiceStatus',
    'billit_sync_status',
    'billitSyncStatus',
    'invoice_status',
    'invoiceStatus',
  ]).toUpperCase();
  final paymentStatus = pick(<String>['payment_status', 'paymentStatus']);

  // "Invoice created" is not automatically "paid": a business invoice still
  // syncing/awaiting settlement is reported separately as in-processing.
  final invoiceProcessing =
      invoiceStatus.contains('SYNC') ||
      invoiceStatus.contains('PENDING') ||
      invoiceStatus.contains('PROCESSING') ||
      invoiceStatus.contains('QUEUED');
  if (invoiceProcessing &&
      !_CompanyBookingOverviewItem.isPaidPaymentStatus(paymentStatus)) {
    return DriverKpiPaymentState.invoiceInProcessing;
  }
  if (_CompanyBookingOverviewItem.isPaidPaymentStatus(paymentStatus)) {
    return DriverKpiPaymentState.paid;
  }
  if (_CompanyBookingOverviewItem.isExplicitNotPaidPaymentStatus(
    paymentStatus,
  )) {
    return DriverKpiPaymentState.outstanding;
  }
  return DriverKpiPaymentState.unknown;
}

DriverKpiRideRecord _driverKpiRideRecordFromTripHistoryItem(
  _TripHistoryItem item,
) {
  DateTime? parseIso(String? iso) {
    final text = iso?.trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  final cancelled = _CompanyBookingOverviewItem._isCancelledStatus(item.status);
  return DriverKpiRideRecord(
    rideId: item.tripId.trim(),
    startedAt: parseIso(item.startedAt),
    stoppedAt: parseIso(item.stoppedAt),
    amountEur: item.totalEur ?? 0.0,
    kmTotal: item.kmTotal,
    isCompleted: !cancelled,
    isCancelled: cancelled,
    paymentState: _driverKpiPaymentStateForTripHistoryItem(item),
  );
}

/// Fetches canonical KPI rides for [driverId] within [tenantId]/[companyId].
///
/// Uses the same `/trips/history` endpoint and street-history canonicalization
/// as the chauffeur History / driver-home KPI path. Period filtering stays in
/// [DriverKpiController] / [aggregateDriverKpi].
Future<List<DriverKpiRideRecord>> fetchDriverKpiRidesFromTripsHistory({
  required String tenantId,
  required String companyId,
  required String driverId,
  required String scopeSource,
  String fetchContext = 'driver_kpi_page',
}) async {
  final scopedTenant = tenantId.trim();
  final scopedCompany = companyId.trim();
  final scopedDriver = driverId.trim();
  if (scopedTenant.isEmpty || scopedCompany.isEmpty) {
    throw StateError('driver_kpi_scope_missing');
  }
  if (scopedDriver.isEmpty) {
    return const <DriverKpiRideRecord>[];
  }

  final preferDriverSession = scopeSource.trim() == 'driver_session';
  final auth = await resolveTripsHistoryAuthHeaders(
    json: false,
    preferDriverSession: preferDriverSession,
  );
  final scopeLabel = switch (scopeSource.trim()) {
    'company_profile' || 'company_session' => 'company',
    'driver_session' => 'driver_session',
    _ => scopeSource.trim().isEmpty ? 'unknown' : scopeSource.trim(),
  };
  debugPrint(
    '[DRIVER_HISTORY][FETCH] context=$fetchContext '
    'auth_mode=${auth.fetchLogAuthMode} scope_source=$scopeLabel '
    'driver=${_driverKpiMaskScopeForLog(scopedDriver)} '
    'tenant=${_driverKpiMaskScopeForLog(scopedTenant)} '
    'company=${_driverKpiMaskScopeForLog(scopedCompany)}',
  );

  final uri = Uri.parse(
    '$kWorkerBaseUrl$kTripsHistoryPath'
    '?tenant_id=${Uri.encodeQueryComponent(scopedTenant)}'
    '&company_id=${Uri.encodeQueryComponent(scopedCompany)}'
    '&tenantId=${Uri.encodeQueryComponent(scopedTenant)}'
    '&companyId=${Uri.encodeQueryComponent(scopedCompany)}'
    '&driver_id=${Uri.encodeQueryComponent(scopedDriver)}'
    '&limit=300',
  );
  final res = await http
      .get(uri, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map || decoded['ok'] != true) {
    throw Exception('invalid_driver_kpi_response');
  }
  final trips = decoded['trips'];
  if (trips is! List) return const <DriverKpiRideRecord>[];
  final tripItems = trips
      .whereType<Map>()
      .map((e) => _TripHistoryItem.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => e.tripId.trim().isNotEmpty)
      // Hard driver-scope guard: never mix another driver's rides into KPIs.
      .where(
        (e) => e.driverId.trim().isEmpty || e.driverId.trim() == scopedDriver,
      )
      .toList(growable: false);
  // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1A: a street ride's planned
  // operational-leg shadow must not count as a second KPI ride.
  final canonicalTripItems = canonicalizeStreetHistory<_TripHistoryItem>(
    tripItems,
    tripId: (item) => item.tripId,
    kind: (item) => item.kind,
    bookingId: (item) => item.bookingId ?? '',
    parentBookingId: (item) => item.parentBookingId,
    linkedTrackingTripId: (item) => item.linkedTrackingTripId,
    isOperationalLeg: (item) => item.isOperationalLeg,
    workerShadowHint: (item) => item.workerOperationalShadowHint,
    onLog: (log) => debugPrint(log.toLogLine()),
  );
  return canonicalTripItems
      .map(_driverKpiRideRecordFromTripHistoryItem)
      .toList(growable: false);
}
