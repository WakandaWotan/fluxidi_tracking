/// Company bookings list ordering: newest canonical creation timestamp first.
///
/// Sort key priority (descending):
/// 1. Canonical creation ISO (`created_at` / `createdAt` / aliases)
/// 2. Stable fallback timestamp extracted from the booking id when possible
/// 3. Booking id (descending) as deterministic tie-breaker
/// 4. Leg id (descending) so roundtrip legs stay stable across refresh
///
/// Never uses pickup/ride date, `updated_at`, or status-change time.
library;

/// Minimal sort fields for company booking overview rows.
class CompanyBookingCreatedSortFields {
  const CompanyBookingCreatedSortFields({
    required this.bookingId,
    this.createdAtIso = '',
    this.legId = '',
  });

  final String bookingId;
  final String createdAtIso;
  final String legId;
}

/// Tolerant extraction of the canonical creation timestamp from a list row map.
String extractCompanyBookingCreatedAtIso(Map<String, dynamic> raw) {
  for (final key in const <String>[
    'created_at',
    'createdAt',
    'booking_created_at',
    'bookingCreatedAt',
    'inserted_at',
    'insertedAt',
    'booking.created_at',
    'booking.createdAt',
    'record.created_at',
    'record.createdAt',
    'record.booking.created_at',
    'record.booking.createdAt',
  ]) {
    final value = _pathText(raw, key);
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Parse creation ISO to epoch ms. Invalid/empty → null (caller applies fallback).
int? companyBookingCreatedAtMs(String? createdAtIso) {
  final text = (createdAtIso ?? '').trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.toUtc().millisecondsSinceEpoch;
}

/// Deterministic fallback ms when creation timestamp is missing.
///
/// Prefers a leading `YYYY-MM-DD` / `YYYYMMDD` prefix on the booking id when
/// present (common Fluxidi canonical ids). Otherwise returns 0 so missing
/// timestamps sort after real ones, with booking-id as the stable orderer.
int companyBookingCreatedFallbackMs(String bookingId) {
  final id = bookingId.trim();
  if (id.isEmpty) return 0;
  final dashed = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(id);
  if (dashed != null) {
    final y = int.tryParse(dashed.group(1)!);
    final m = int.tryParse(dashed.group(2)!);
    final d = int.tryParse(dashed.group(3)!);
    if (y != null && m != null && d != null) {
      try {
        return DateTime.utc(y, m, d).millisecondsSinceEpoch;
      } catch (_) {
        // fall through
      }
    }
  }
  final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(id);
  if (compact != null) {
    final y = int.tryParse(compact.group(1)!);
    final m = int.tryParse(compact.group(2)!);
    final d = int.tryParse(compact.group(3)!);
    if (y != null && m != null && d != null) {
      try {
        return DateTime.utc(y, m, d).millisecondsSinceEpoch;
      } catch (_) {
        // fall through
      }
    }
  }
  return 0;
}

int companyBookingCreatedSortMs(CompanyBookingCreatedSortFields fields) {
  return companyBookingCreatedAtMs(fields.createdAtIso) ??
      companyBookingCreatedFallbackMs(fields.bookingId);
}

/// Comparator: newest created first; stable on equal timestamps via ids DESC.
int compareCompanyBookingsNewestCreatedFirst(
  CompanyBookingCreatedSortFields a,
  CompanyBookingCreatedSortFields b,
) {
  final msA = companyBookingCreatedSortMs(a);
  final msB = companyBookingCreatedSortMs(b);
  if (msA != msB) return msB.compareTo(msA);
  final idCmp = b.bookingId.trim().compareTo(a.bookingId.trim());
  if (idCmp != 0) return idCmp;
  return b.legId.trim().compareTo(a.legId.trim());
}

/// Sort [items] newest-created-first after merge/dedupe. Returns a new list.
List<T> sortCompanyBookingsNewestCreatedFirst<T>(
  Iterable<T> items,
  CompanyBookingCreatedSortFields Function(T item) fieldsOf,
) {
  final out = items.toList(growable: true);
  out.sort(
    (a, b) => compareCompanyBookingsNewestCreatedFirst(fieldsOf(a), fieldsOf(b)),
  );
  return List<T>.unmodifiable(out);
}

String _pathText(Map<String, dynamic> root, String path) {
  dynamic cursor = root;
  for (final rawPart in path.split('.')) {
    final part = rawPart.trim();
    if (part.isEmpty) continue;
    if (cursor is Map && cursor.containsKey(part)) {
      cursor = cursor[part];
    } else {
      return '';
    }
  }
  final text = cursor?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}
