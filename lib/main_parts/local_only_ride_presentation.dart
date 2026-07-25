// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Commit 5)
//
// Truthful "local/unconfirmed" ride presentation.
//
// A ride record that was persisted locally after the tracking worker rejected
// /trip/start-direct (401/403) must never be surfaced to the driver or the
// company owner as an ordinary "Completed / Afgerond / Terminée / Finalizada"
// ride. Two independent signals identify such a record:
//
//   1. `history_source == 'local_only_direct_fallback'` — written by
//      `_buildLocalOnlyDirectHistoryRecord` in `driver_home_page_state.dart`
//      at BOTH the root and `booking_details` levels of the persisted map.
//   2. `backend_confirmed == false` — same origin, but also potentially
//      emitted for planned rides where the worker did not confirm the stop
//      (e.g. planned session stop returned a non-2xx response).
//
// This helper is intentionally pure Dart: it takes plain `Map<String,
// dynamic>` values and returns either an enum or a `LocalizedText` constant
// from `app_strings.dart`. No Flutter widgets, no `BuildContext`, no
// `debugPrint`, no service-locator lookups. All UI wiring lives in the
// call sites (`trip_history_page.dart`, `receipt_pdf_action_runner.dart`).
//
// The centralized constants below (`kLocalOnlyUnconfirmedBadge`, etc.) are
// the single source of truth for the four locales — no widget is allowed
// to hardcode "Lokaal opgeslagen" / "Saved locally" / etc. directly.

part of '../main.dart';

/// Truthful confirmation state for a persisted trip-history record.
///
/// - [backendConfirmed]: the server acknowledged the ride
///   (`backend_confirmed=true` or the record was fetched from the trips
///   worker; the default assumption for legacy rows that do not carry
///   the flag).
/// - [localOnlyUnconfirmed]: the ride was persisted locally after a
///   backend failure or without server confirmation. Must render with
///   the "Lokaal opgeslagen — niet bevestigd" family of labels and must
///   never be counted in the normal "Completed" aggregate.
/// - [unknown]: neither signal was present in the record; the caller
///   should default to backend-confirmed rendering (legacy safe path)
///   because the local-only fallback always writes an explicit signal.
enum RideConfirmationState { backendConfirmed, localOnlyUnconfirmed, unknown }

/// Pure resolver used by both the widget layer (`trip_history_page.dart`,
/// `receipt_pdf_action_runner.dart` via `_TripHistoryItem.shouldRenderAsLocalOnlyUnconfirmed`)
/// and the unit tests. The two-map API mirrors `_TripHistoryItem.rawSource`
/// and `_TripHistoryItem.bookingDetails` exactly so a test can construct a
/// synthetic record without instantiating any Flutter widget.
///
/// Precedence (all safe, deterministic, order-independent):
///   1. Any `history_source == 'local_only_direct_fallback'` in either
///      map => localOnlyUnconfirmed.
///   2. Any explicit `backend_confirmed == false` in either map =>
///      localOnlyUnconfirmed (broader safe rule approved for Commit 5).
///   3. Any explicit `backend_confirmed == true` in either map =>
///      backendConfirmed.
///   4. Otherwise => unknown (caller renders normal-completed).
RideConfirmationState resolveRideConfirmationStateFromMaps({
  required Map<String, dynamic> rawSource,
  required Map<String, dynamic> bookingDetails,
}) {
  bool historyIsLocalOnlyFallback(Map<String, dynamic> m) {
    final v = (m['history_source'] ?? '').toString().trim().toLowerCase();
    return v == 'local_only_direct_fallback';
  }

  if (historyIsLocalOnlyFallback(rawSource) ||
      historyIsLocalOnlyFallback(bookingDetails)) {
    return RideConfirmationState.localOnlyUnconfirmed;
  }

  bool? readBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return null;
  }

  final bcRoot = readBool(rawSource['backend_confirmed']);
  final bcDetails = readBool(bookingDetails['backend_confirmed']);
  if (bcRoot == false || bcDetails == false) {
    return RideConfirmationState.localOnlyUnconfirmed;
  }
  if (bcRoot == true || bcDetails == true) {
    return RideConfirmationState.backendConfirmed;
  }
  return RideConfirmationState.unknown;
}

/// Primary status-chip label — used by the driver ride-history tile and by
/// the ride receipt "Rit status / Ride status" row.
const LocalizedText kLocalOnlyUnconfirmedBadge = LocalizedText(
  nl: 'Lokaal opgeslagen — niet bevestigd',
  en: 'Saved locally — unconfirmed',
  fr: 'Enregistré localement — non confirmé',
  es: 'Guardado localmente — sin confirmar',
);

/// Compact form for tight tile layouts — replaces the old hardcoded
/// ' • Lokaal' Dutch-only suffix on the tile subtitle.
const LocalizedText kLocalOnlyUnconfirmedShort = LocalizedText(
  nl: 'Lokaal',
  en: 'Local',
  fr: 'Local',
  es: 'Local',
);

/// Explanatory sentence rendered below the status chip on any surface
/// showing an unconfirmed ride — makes the Company Bookings visibility
/// gap explicit so the operator does not assume the ride reached the
/// backend.
const LocalizedText kLocalOnlyUnconfirmedDescription = LocalizedText(
  nl: 'Deze rit is niet bevestigd door de server. '
      'Mogelijk verschijnt hij niet in Bedrijfsritten.',
  en: 'This ride was not confirmed by the backend. '
      'It may not appear in Company Bookings.',
  fr: 'Cette course n’a pas été confirmée par le serveur. '
      'Elle peut ne pas apparaître dans Réservations entreprise.',
  es: 'Este viaje no fue confirmado por el servidor. '
      'Puede que no aparezca en Reservas de empresa.',
);

/// ARGB constant so this pure-Dart library stays widget-independent.
/// Amber-500, visually distinct from the "Completed" green
/// (`0xFF4ADE80`) currently used by `_statusChipColor` for
/// backend-confirmed rides.
const int kLocalOnlyUnconfirmedBadgeColorArgb = 0xFFF59E0B;
