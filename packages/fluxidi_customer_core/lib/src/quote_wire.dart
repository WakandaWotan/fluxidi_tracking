/// Public `/quote` and `/book` also require `from`, `to`, `date` and `time`.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/customer_booking/customer_booking_quote_wire.dart` —
/// `customerBookingEnsurePublicScheduleFields` and its helpers.
///
/// Never invents a date: it copies the schedule already chosen.
library;

import 'schedule.dart';

String fluxidiFormatDateYmd(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String fluxidiFormatTimeHm(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

DateTime? fluxidiParsePickupIso(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

bool fluxidiBodyHasWhenNow(Map<String, dynamic> body) =>
    fluxidiWhenIsNow(body['when_now']) || fluxidiWhenIsNow(body['when']);

bool fluxidiBodyHasDateTime(Map<String, dynamic> body) {
  final date = body['date']?.toString().trim() ?? '';
  final time = body['time']?.toString().trim() ?? '';
  return date.isNotEmpty && time.isNotEmpty;
}

void _applyLocalDateTime(
  Map<String, dynamic> body,
  DateTime value, {
  required String dateKey,
  required String timeKey,
}) {
  body[dateKey] = fluxidiFormatDateYmd(value);
  body[timeKey] = fluxidiFormatTimeHm(value);
}

/// Copies the existing pickup schedule onto the public wire.
///
/// Uses `pickup_iso` or the explicit `when_now` choice. Never invents a default
/// date and never fills missing coordinates.
void fluxidiEnsurePublicScheduleFields(
  Map<String, dynamic> body, {
  DateTime Function()? clock,
}) {
  if (!fluxidiBodyHasDateTime(body)) {
    final pickup = fluxidiParsePickupIso(body['pickup_iso'] ?? body['pickupIso']);
    if (pickup != null && !fluxidiPickupIsEpoch(pickup)) {
      _applyLocalDateTime(body, pickup, dateKey: 'date', timeKey: 'time');
    } else if (fluxidiBodyHasWhenNow(body)) {
      final now = (clock ?? DateTime.now)().toLocal();
      _applyLocalDateTime(body, now, dateKey: 'date', timeKey: 'time');
      if ((body['pickup_iso'] ?? '').toString().trim().isEmpty) {
        body['pickup_iso'] = now.toUtc().toIso8601String();
      }
    }
  }
  final returnIso = fluxidiParsePickupIso(
    body['return_pickup_iso'] ?? body['returnPickupIso'],
  );
  final hasReturnDateTime =
      (body['return_date']?.toString().trim().isNotEmpty ?? false) &&
      (body['return_time']?.toString().trim().isNotEmpty ?? false);
  if (returnIso != null && !hasReturnDateTime) {
    _applyLocalDateTime(
      body,
      returnIso,
      dateKey: 'return_date',
      timeKey: 'return_time',
    );
  }
}
