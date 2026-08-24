// One paid/unpaid resolver for chauffeur receipt, Historiek, and booking views.
// Booking paid wins. A paid trip/history row is retained against a stale unpaid
// booking overlay (same monotonic rule as Ritbon). Terminal non-paid booking
// states such as refunded still win.

enum CanonicalRidePaidDisplay { paid, unpaid, unknown }

const List<List<String>> kCanonicalRidePaidStatusPaths = <List<String>>[
  ['payment_status'],
  ['paymentStatus'],
  ['payment_state'],
  ['paymentState'],
  ['paid'],
  ['is_paid'],
  ['isPaid'],
  ['booking', 'payment_status'],
  ['booking', 'paymentStatus'],
  ['booking', 'payment_state'],
  ['booking', 'paymentState'],
  ['booking', 'paid'],
  ['booking', 'is_paid'],
  ['booking', 'isPaid'],
  ['record', 'payment_status'],
  ['record', 'paymentStatus'],
  ['record', 'payment_state'],
  ['record', 'paymentState'],
  ['record', 'paid'],
  ['record', 'is_paid'],
  ['record', 'isPaid'],
  ['record', 'booking', 'payment_status'],
  ['record', 'booking', 'paymentStatus'],
  ['record', 'booking', 'paid'],
  ['record', 'booking', 'is_paid'],
  ['record', 'booking', 'isPaid'],
  ['payment', 'status'],
  ['payment', 'paid'],
  ['booking', 'payment', 'status'],
  ['booking', 'payment', 'paid'],
  ['record', 'payment', 'status'],
  ['record', 'payment', 'paid'],
  ['record', 'booking', 'payment', 'status'],
  ['record', 'booking', 'payment', 'paid'],
  ['mollie', 'status'],
  ['record', 'mollie', 'status'],
];

const List<List<String>> kCanonicalRidePaidAtPaths = <List<String>>[
  ['paid_at'],
  ['paidAt'],
  ['booking', 'paid_at'],
  ['booking', 'paidAt'],
  ['record', 'paid_at'],
  ['record', 'paidAt'],
  ['record', 'booking', 'paid_at'],
  ['record', 'booking', 'paidAt'],
];

bool isCanonicalPaidStatusValue(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty || text == 'null') return false;
  return text == 'paid' ||
      text == 'settled' ||
      text == 'confirmed' ||
      text == 'completed' ||
      text == 'success' ||
      text == 'succeeded' ||
      text == 'captured';
}

bool isCanonicalUnpaidStatusValue(Object? value) {
  if (value == null) return false;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty || text == 'null') return false;
  return text == 'unpaid' ||
      text == 'not_paid' ||
      text == 'open' ||
      text == 'pending' ||
      text == 'authorized' ||
      text == 'authorised' ||
      text == 'processing';
}

bool isCanonicalTerminalNonPaidStatusValue(Object? value) {
  if (value == null) return false;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return false;
  return text == 'refunded' ||
      text == 'reversed' ||
      text == 'cancelled' ||
      text == 'canceled' ||
      text == 'rejected' ||
      text == 'failed' ||
      text == 'declined' ||
      text == 'error';
}

dynamic _valueAt(Map<String, dynamic>? map, List<String> path) {
  dynamic current = map;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  return current;
}

bool _hasPaidAt(Map<String, dynamic>? map) {
  if (map == null) return false;
  for (final path in kCanonicalRidePaidAtPaths) {
    final value = _valueAt(map, path);
    if (value == null) continue;
    if (value is Map || value is Iterable) continue;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null' || text == '—') continue;
    return true;
  }
  return false;
}

bool mapLooksCanonicallyPaid(Map<String, dynamic>? map) {
  if (map == null || map.isEmpty) return false;
  for (final path in kCanonicalRidePaidStatusPaths) {
    if (isCanonicalPaidStatusValue(_valueAt(map, path))) return true;
  }
  return _hasPaidAt(map);
}

Object? firstCanonicalPaymentStatus(Map<String, dynamic>? map) {
  if (map == null) return null;
  for (final path in kCanonicalRidePaidStatusPaths) {
    final value = _valueAt(map, path);
    if (value == null) continue;
    if (value is Map || value is Iterable) continue;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') continue;
    return value;
  }
  return null;
}

/// Booking paid wins. History/trip paid is retained against a stale unpaid
/// booking overlay. Terminal non-paid booking states still win.
CanonicalRidePaidDisplay resolveCanonicalRidePaidDisplay({
  Map<String, dynamic>? historyRaw,
  Map<String, dynamic>? historyDetails,
  Map<String, dynamic>? bookingRecord,
}) {
  if (mapLooksCanonicallyPaid(bookingRecord)) {
    return CanonicalRidePaidDisplay.paid;
  }
  final bookingStatus = firstCanonicalPaymentStatus(bookingRecord);
  if (isCanonicalTerminalNonPaidStatusValue(bookingStatus)) {
    return CanonicalRidePaidDisplay.unpaid;
  }

  if (mapLooksCanonicallyPaid(historyDetails) ||
      mapLooksCanonicallyPaid(historyRaw)) {
    return CanonicalRidePaidDisplay.paid;
  }

  if (isCanonicalUnpaidStatusValue(bookingStatus) &&
      bookingRecord != null &&
      bookingRecord.isNotEmpty) {
    return CanonicalRidePaidDisplay.unpaid;
  }

  final historyStatus =
      firstCanonicalPaymentStatus(historyDetails) ??
      firstCanonicalPaymentStatus(historyRaw);
  if (isCanonicalUnpaidStatusValue(historyStatus)) {
    return CanonicalRidePaidDisplay.unpaid;
  }
  if (isCanonicalTerminalNonPaidStatusValue(historyStatus)) {
    return CanonicalRidePaidDisplay.unpaid;
  }
  return CanonicalRidePaidDisplay.unknown;
}

bool resolveCanonicalRideIsPaid({
  Map<String, dynamic>? historyRaw,
  Map<String, dynamic>? historyDetails,
  Map<String, dynamic>? bookingRecord,
}) {
  return resolveCanonicalRidePaidDisplay(
        historyRaw: historyRaw,
        historyDetails: historyDetails,
        bookingRecord: bookingRecord,
      ) ==
      CanonicalRidePaidDisplay.paid;
}

/// Flatten payment fields from a booking GET body onto a history row.
/// A paid target is never overwritten by a stale unpaid overlay.
Map<String, dynamic> overlayCanonicalPaymentFields(
  Map<String, dynamic> target,
  Map<String, dynamic> bookingFields,
) {
  final next = Map<String, dynamic>.from(target);
  void copy(String key) {
    final value = bookingFields[key];
    if (value == null) return;
    next[key] = value;
  }

  final incomingStatus = firstCanonicalPaymentStatus(bookingFields);
  final incomingTerminal = isCanonicalTerminalNonPaidStatusValue(
    incomingStatus,
  );
  final shouldCopyStatus =
      mapLooksCanonicallyPaid(bookingFields) ||
      incomingTerminal ||
      !mapLooksCanonicallyPaid(next);
  if (shouldCopyStatus) {
    copy('payment_status');
    copy('paymentStatus');
    copy('paid_at');
    copy('paidAt');
    copy('paid');
    copy('is_paid');
    copy('isPaid');
  }
  copy('payment_method');
  copy('paymentMethod');
  copy('payment_source');
  copy('paymentSource');
  copy('payment_provider');
  copy('paymentProvider');
  return next;
}

Map<String, dynamic> extractCanonicalPaymentFields(Map<String, dynamic> root) {
  Map<String, dynamic> asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String? text(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  final data = asMap(root['data']);
  final record = asMap(root['record']);
  final booking = asMap(root['booking']);
  final recordBooking = asMap(record['booking']);

  String? firstHit(String snake, String camel) {
    return text(root[snake] ?? root[camel]) ??
        text(record[snake] ?? record[camel]) ??
        text(recordBooking[snake] ?? recordBooking[camel]) ??
        text(booking[snake] ?? booking[camel]) ??
        text(data[snake] ?? data[camel]);
  }

  final out = <String, dynamic>{};
  final status = firstHit('payment_status', 'paymentStatus');
  final paidAt = firstHit('paid_at', 'paidAt');
  final paid = firstHit('paid', 'isPaid') ?? firstHit('is_paid', 'isPaid');
  if (status != null) {
    out['payment_status'] = status;
    out['paymentStatus'] = status;
  }
  if (paidAt != null) {
    out['paid_at'] = paidAt;
    out['paidAt'] = paidAt;
  }
  if (paid != null) {
    out['paid'] = paid;
    out['is_paid'] = paid;
    out['isPaid'] = paid;
  }
  final method = firstHit('payment_method', 'paymentMethod');
  if (method != null) {
    out['payment_method'] = method;
    out['paymentMethod'] = method;
  }
  return out;
}
