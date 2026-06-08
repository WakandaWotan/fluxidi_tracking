import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/compliance_ledger_reader.dart';

enum ComplianceRegisterReceiptAction {
  viewDetails,
  downloadReceipt,
  downloadInvoice,
  shareReceipt,
}

typedef ComplianceRegisterReceiptHandler =
    Future<void> Function(
      BuildContext context,
      ComplianceLedgerEntry entry, {
      required ComplianceRegisterReceiptAction action,
    });

ComplianceRegisterReceiptHandler? complianceRegisterReceiptHandler;

void registerComplianceRegisterReceiptHandler(
  ComplianceRegisterReceiptHandler handler,
) {
  complianceRegisterReceiptHandler = handler;
}

/// Builds a trip-history shaped JSON payload from a compliance ledger entry.
/// Used by the main app receipt/PDF pipeline via [registerComplianceRegisterReceiptHandler].
Map<String, dynamic> tripHistoryJsonFromLedgerEntry(
  ComplianceLedgerEntry entry,
) {
  Map<String, dynamic> asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String text(Object? value) => (value ?? '').toString().trim();
  String? nullableText(Object? value) {
    final out = text(value);
    return out.isEmpty ? null : out;
  }

  final raw = entry.raw;
  final payment = asMap(raw['payment']);
  final fare = asMap(raw['fare']);
  final references = asMap(raw['references']);
  final bookingId = entry.bookingId.trim();
  final tripId = entry.tripId.trim();
  final rideType = entry.rideType.trim().isEmpty
      ? 'planned'
      : entry.rideType.trim();
  final kind = rideType.toLowerCase() == 'direct' ? 'direct' : 'planned';

  final bookingDetails = <String, dynamic>{
    if (bookingId.isNotEmpty) 'booking_id': bookingId,
    if (tripId.isNotEmpty) 'trip_id': tripId,
    'payment_status': entry.paymentStatus.isNotEmpty
        ? entry.paymentStatus
        : payment['status'],
    'payment_method': entry.paymentMethod.isNotEmpty
        ? entry.paymentMethod
        : payment['method'],
    'payment_source': entry.paymentSource.isNotEmpty
        ? entry.paymentSource
        : payment['source'],
    'payment_provider': entry.paymentProvider.isNotEmpty
        ? entry.paymentProvider
        : payment['provider'],
    if (entry.paymentId.isNotEmpty) 'payment_id': entry.paymentId,
    if (entry.paidAtUtc != null)
      'paid_at': entry.paidAtUtc!.toUtc().toIso8601String(),
    if (entry.receiptReference.isNotEmpty)
      'receipt_reference': entry.receiptReference,
    if (entry.planningReference.isNotEmpty)
      'planning_reference': entry.planningReference,
    if (entry.publicBookingReference.isNotEmpty)
      'public_booking_reference': entry.publicBookingReference,
    if (entry.invoiceReference.isNotEmpty)
      'invoice_reference': entry.invoiceReference,
    if (entry.tenantId.isNotEmpty) 'tenant_id': entry.tenantId,
    if (entry.companyId.isNotEmpty) 'company_id': entry.companyId,
    if (entry.fareTotalEur != null) 'total_eur': entry.fareTotalEur,
    if (entry.distanceKm != null) 'km_total': entry.distanceKm,
    if (entry.distanceKm != null) 'distance_km': entry.distanceKm,
    if (entry.waitSecondsTotal != null)
      'wait_seconds_total': entry.waitSecondsTotal,
    if (entry.currency.isNotEmpty) 'currency': entry.currency,
  };

  for (final key in references.keys) {
    final value = references[key];
    if (value == null) continue;
    final asText = text(value);
    if (asText.isEmpty) continue;
    bookingDetails.putIfAbsent(key, () => value);
  }

  final startedAt =
      entry.startedAtUtc?.toUtc().toIso8601String() ??
      nullableText(raw['started_at_utc']) ??
      nullableText(asMap(raw['timestamps'])['started_at_utc']);
  final stoppedAt =
      entry.endedAtUtc?.toUtc().toIso8601String() ??
      entry.finalizedAtUtc?.toUtc().toIso8601String() ??
      nullableText(raw['ended_at_utc']) ??
      nullableText(asMap(raw['timestamps'])['stopped_at_utc']) ??
      nullableText(asMap(raw['timestamps'])['event_at_utc']);

  return <String, dynamic>{
    'trip_id': tripId,
    'kind': kind,
    if (bookingId.isNotEmpty) 'booking_id': bookingId,
    'driver_id': entry.driverId,
    if (entry.vehicleId.isNotEmpty) 'vehicle_id': entry.vehicleId,
    if (startedAt != null) 'started_at': startedAt,
    if (stoppedAt != null) 'stopped_at': stoppedAt,
    'origin': <String, dynamic>{'label': entry.pickupLabel},
    'destination': <String, dynamic>{'label': entry.dropoffLabel},
    if (entry.distanceKm != null) 'km_total': entry.distanceKm,
    if (entry.waitSecondsTotal != null)
      'wait_seconds_total': entry.waitSecondsTotal,
    if (entry.fareTotalEur != null) 'total_eur': entry.fareTotalEur,
    'status': entry.lifecycleStatus.isNotEmpty
        ? entry.lifecycleStatus
        : 'completed',
    'currency': entry.currency.isNotEmpty
        ? entry.currency
        : text(fare['currency']).isEmpty
        ? 'EUR'
        : text(fare['currency']),
    'booking_details': bookingDetails,
    ...raw,
  };
}

Future<void> runComplianceRegisterReceiptAction({
  required BuildContext context,
  required ComplianceLedgerEntry entry,
  required ComplianceRegisterReceiptAction action,
}) async {
  final handler = complianceRegisterReceiptHandler;
  if (handler == null) {
    debugPrint(
      '[LOCAL_RIDE_REGISTER][EXPORT_RECEIPT] key=${ComplianceLedgerReader.groupKeyFor(entry)} source=register status=handler_missing',
    );
    return;
  }
  await handler(context, entry, action: action);
}
