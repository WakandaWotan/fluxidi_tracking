import 'package:fluxidi_tracking/payment/invoice_pdf_pending.dart';

/// How View PDF should finish. Copying receipt text is never a success.
enum RegisterPdfViewOutcome {
  openExisting,
  generateLocal,
  pending,
  missing,
  unreachable,
}

/// Anonymized register shapes used by tests. Field names match the live
/// ledger / trip-history merge; values are replaced.
class RegisterReceiptCase {
  const RegisterReceiptCase({
    required this.id,
    required this.ledger,
    required this.tripHistory,
  });

  final String id;
  final Map<String, dynamic> ledger;
  final Map<String, dynamic> tripHistory;
}

/// Planned ride whose invoice PDF is already on the worker (HTTP 200).
RegisterReceiptCase registerReceiptWorkingPdfCase() {
  return const RegisterReceiptCase(
    id: 'working_pdf',
    ledger: <String, dynamic>{
      'event_type': 'ride_completed',
      'ride_type': 'planned',
      'lifecycle_status': 'completed',
      'booking_id': 'BK-ANON-021',
      'trip_id': 'planned_anon_out_021',
      'planning_reference': 'PLN-ANON-000418',
      'driver_id': 'drv_anon',
      'vehicle_id': 'veh_anon',
      'payment': <String, dynamic>{
        'status': 'unpaid',
        'method': 'unknown',
        'provider': 'manual',
      },
      'fare': <String, dynamic>{'total_eur': 42.0, 'currency': 'EUR'},
      'documents': <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'invoice_pdf',
          'available': true,
          'http_status': 200,
        },
      ],
    },
    tripHistory: <String, dynamic>{
      'trip_id': 'planned_anon_out_021',
      'kind': 'planned',
      'booking_id': 'BK-ANON-021',
      'planning_reference': 'PLN-ANON-000418',
      'status': 'completed',
      'total_eur': 42.0,
      'payment_status': 'unpaid',
      'booking_details': <String, dynamic>{
        'booking_total_eur': 42.0,
        'leg_type': 'outbound',
        'leg_id': 'leg_anon_out',
      },
    },
  );
}

/// Street / direct ride: details open, invoice PDF is 202 pending, no
/// stored document. Live counterpart: 11 Sep 15:52 draft street ride.
RegisterReceiptCase registerReceiptPendingInvoicePdfCase() {
  return const RegisterReceiptCase(
    id: 'pending_invoice_pdf',
    ledger: <String, dynamic>{
      'event_type': 'ride_completed',
      'ride_type': 'direct',
      'lifecycle_status': 'completed',
      'booking_id': 'street_anon_1152',
      'trip_id': 'direct_anon_1152',
      'receipt_reference': '',
      'driver_id': '',
      'vehicle_id': '',
      'started_at_utc': '2026-09-11T13:52:00.000Z',
      'ended_at_utc': '2026-09-11T13:52:00.000Z',
      'payment': <String, dynamic>{'status': 'unknown'},
      'fare': <String, dynamic>{'total_eur': 5.30, 'currency': 'EUR'},
      'documents': <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'invoice_pdf',
          'available': false,
          'http_status': 202,
        },
      ],
    },
    tripHistory: <String, dynamic>{
      'trip_id': 'direct_anon_1152',
      'kind': 'direct',
      'booking_id': 'street_anon_1152',
      'status': 'completed',
      'started_at': '2026-09-11T13:52:00.000Z',
      'stopped_at': '2026-09-11T13:52:00.000Z',
      'total_eur': 5.30,
      'currency': 'EUR',
      'payment_status': 'unknown',
      'driver_id': '',
      'vehicle_id': '',
    },
  );
}

/// Planned historical row without `planned_` trip id / leg keys. Live
/// counterpart: 12 Sep planned cards. Details used to grey out because
/// leg detection called the receipt total helper recursively.
RegisterReceiptCase registerReceiptHistoricalPlannedCase() {
  return const RegisterReceiptCase(
    id: 'historical_planned_details',
    ledger: <String, dynamic>{
      'event_type': 'ride_completed',
      'ride_type': 'planned',
      'lifecycle_status': 'completed',
      'booking_id': 'BK-ANON-011',
      'trip_id': 'trip_anon_0912',
      'planning_reference': 'PLN-ANON-000414',
      'driver_id': 'drv_anon_b',
      'vehicle_id': 'veh_anon_b',
      'payment': <String, dynamic>{
        'status': 'unpaid',
        'method': 'QR',
        'provider': 'manual',
      },
      'fare': <String, dynamic>{'currency': 'EUR'},
    },
    tripHistory: <String, dynamic>{
      'trip_id': 'trip_anon_0912',
      'kind': 'planned',
      'booking_id': 'BK-ANON-011',
      'planning_reference': 'PLN-ANON-000414',
      'status': 'completed',
      'payment_status': 'unpaid',
      'payment_method': 'QR',
      'driver_id': 'drv_anon_b',
      'vehicle_id': 'veh_anon_b',
      'booking_details': <String, dynamic>{
        'booking_total_eur': 80.0,
      },
    },
  );
}

bool receiptHasExplicitLegToken(String? token) {
  final norm = (token ?? '').trim().toLowerCase();
  return norm == 'outbound' ||
      norm == 'main' ||
      norm == 'heenrit' ||
      norm == 'aller' ||
      norm == 'return' ||
      norm == 'terugrit' ||
      norm == 'retour';
}

bool receiptBookingIdLooksLikeReturnLeg(String? bookingId) {
  return (bookingId ?? '').trim().toLowerCase().endsWith('-r');
}

/// Signal 3 without calling receipt-total helpers (those helpers call
/// back into leg detection).
bool receiptTotalLooksLikeLegSlice({
  required double? itemTotalEur,
  required double? parentBookingTotalEur,
}) {
  final receiptTotal = itemTotalEur;
  final bookingTotal = parentBookingTotalEur;
  return receiptTotal != null &&
      receiptTotal > 0 &&
      bookingTotal != null &&
      bookingTotal > receiptTotal + 0.01;
}

bool classifyReceiptAsLegItem({
  required String? legToken,
  required String? bookingId,
  required double? itemTotalEur,
  required double? parentBookingTotalEur,
}) {
  if (receiptHasExplicitLegToken(legToken)) return true;
  if (receiptBookingIdLooksLikeReturnLeg(bookingId)) return true;
  return receiptTotalLooksLikeLegSlice(
    itemTotalEur: itemTotalEur,
    parentBookingTotalEur: parentBookingTotalEur,
  );
}

bool registerReceiptDetailsShouldOpen(Map<String, dynamic> tripHistory) {
  final kind = (tripHistory['kind'] ?? '').toString().trim();
  if (kind.isEmpty) return false;
  classifyReceiptAsLegItem(
    legToken: (tripHistory['leg_type'] ??
            tripHistory['legType'] ??
            (tripHistory['booking_details'] is Map
                ? (tripHistory['booking_details'] as Map)['leg_type']
                : null))
        ?.toString(),
    bookingId: tripHistory['booking_id']?.toString(),
    itemTotalEur: _asDouble(tripHistory['total_eur']),
    parentBookingTotalEur: _asDouble(
      tripHistory['booking_details'] is Map
          ? (tripHistory['booking_details'] as Map)['booking_total_eur']
          : null,
    ),
  );
  return true;
}

RegisterPdfViewOutcome classifyRegisterPdfView({
  required InvoicePdfFetchState backendState,
  required bool generatedLocalPdf,
}) {
  if (backendState == InvoicePdfFetchState.ready) {
    return RegisterPdfViewOutcome.openExisting;
  }
  if (generatedLocalPdf) return RegisterPdfViewOutcome.generateLocal;
  if (backendState == InvoicePdfFetchState.pending) {
    return RegisterPdfViewOutcome.pending;
  }
  if (backendState == InvoicePdfFetchState.failure) {
    return RegisterPdfViewOutcome.unreachable;
  }
  return RegisterPdfViewOutcome.missing;
}

bool registerPdfViewCopiesText(RegisterPdfViewOutcome outcome) => false;

/// Ride facts a receipt needs before it can render an honest document.
///
/// The local register always merges the full `GET /bookings/:id` record, so
/// its receipts carry amount, status, pickup time and real route labels. The
/// chauffeur History used to stop at business references, which left the same
/// ride showing "Niet beschikbaar" / "Onbekend" and generic endpoints.
bool receiptNeedsBookingRecordHydration({
  required double? totalEur,
  required String status,
  required String? startedAt,
  required bool routeLabelsResolved,
}) {
  if (totalEur == null || totalEur <= 0) return true;
  if (!receiptStatusIsKnown(status)) return true;
  if ((startedAt ?? '').trim().isEmpty) return true;
  return !routeLabelsResolved;
}

/// A ride status the receipt may present as-is. Blank and placeholder values
/// are what surfaced as "Onbekend".
bool receiptStatusIsKnown(String status) {
  final norm = status.trim().toLowerCase();
  if (norm.isEmpty) return false;
  return norm != 'unknown' &&
      norm != 'onbekend' &&
      norm != 'null' &&
      norm != '-';
}

/// Anonymized chauffeur-History shape of the ride on the screenshot
/// (PLN-2026-000418): references are present, ride facts are not.
RegisterReceiptCase driverHistoryReferenceOnlyCase() {
  return const RegisterReceiptCase(
    id: 'driver_history_reference_only',
    ledger: <String, dynamic>{
      'event_type': 'ride_completed',
      'ride_type': 'planned',
      'lifecycle_status': 'completed',
      'booking_id': 'BK-ANON-021',
      'trip_id': 'planned_anon_out_021',
      'planning_reference': 'PLN-ANON-000418',
    },
    tripHistory: <String, dynamic>{
      'trip_id': 'planned_anon_out_021',
      'kind': 'planned',
      'booking_id': 'BK-ANON-021',
      'planning_reference': 'PLN-ANON-000418',
      'status': '',
      'booking_details': <String, dynamic>{
        'planning_reference': 'PLN-ANON-000418',
      },
    },
  );
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
}
