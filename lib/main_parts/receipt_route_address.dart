// Ordinary ritbon / betaalbewijs route-address + logo sizing helpers.
// Pure / sync — no network. Reverse-geocode freeze lives in the booking worker.

/// Previous receipt PDF logo box was 82×82. Target ~4× linear width while
/// preserving aspect via [BoxFit.contain] in the upper-left header.
const double kReceiptPdfLogoBoxWidth = 328;

/// Height sized for wide Branding & support logos (~4.5:1) inside [kReceiptPdfLogoBoxWidth].
const double kReceiptPdfLogoBoxHeight = 90;

/// True when [value] looks like a raw lat/lon pair (customer-facing forbid).
bool receiptLooksLikeCoordinatePair(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return false;
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
  final match = RegExp(
    r'^([+-]?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d{1,3}(?:\.\d+)?)$',
  ).firstMatch(normalized);
  if (match == null) return false;
  final a = double.tryParse(match.group(1)!);
  final b = double.tryParse(match.group(2)!);
  if (a == null || b == null) return false;
  // Accept either lat,lon or lon,lat ordering.
  final latLon = a.abs() <= 90.0 && b.abs() <= 180.0;
  final lonLat = a.abs() <= 180.0 && b.abs() <= 90.0;
  return latLon || lonLat;
}

/// Placeholders that must not win over a real stored / frozen address.
bool receiptIsNonAddressRoutePlaceholder(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return true;
  if (text == '-' || text == '—') return true;
  final lower = text.toLowerCase();
  if (lower == 'null' || lower == 'undefined') return true;
  if (lower == 'straatrit' ||
      lower == 'street ride' ||
      lower == 'directe rit' ||
      lower == 'direct ride') {
    return true;
  }
  if (receiptLooksLikeCoordinatePair(text)) return true;
  if ((text.startsWith('{') && text.endsWith('}')) ||
      (text.startsWith('[') && text.endsWith(']'))) {
    return true;
  }
  return false;
}

String? receiptPickCustomerVisibleAddress(Iterable<String?> candidates) {
  for (final candidate in candidates) {
    final text = candidate?.trim() ?? '';
    if (text.isEmpty) continue;
    if (receiptIsNonAddressRoutePlaceholder(text)) continue;
    return text;
  }
  return null;
}

String? _asTrimmedString(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
  if (value is Map) {
    for (final key in const <String>[
      'label',
      'address',
      'formatted_address',
      'formattedAddress',
      'full_address',
      'fullAddress',
      'name',
      'text',
      'value',
    ]) {
      final inner = value[key];
      if (inner is String) {
        final t = inner.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }
  if (value is Iterable) return null;
  final t = value.toString().trim();
  if (t.isEmpty || t == 'null') return null;
  return t;
}

dynamic _mapPath(Map<String, dynamic>? root, List<String> path) {
  dynamic current = root;
  for (final segment in path) {
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

/// Authoritative customer-facing pickup/dropoff for ordinary receipt PDFs.
///
/// Precedence (mirrors worker `resolveHumanRouteAddress`):
/// 1. frozen invoice_* / route_address_snapshot
/// 2. *_full_address / *_label
/// 3. booking / trip route labels
/// 4. common pickup/destination aliases
/// Never returns coordinate pairs or "Straatrit" placeholders.
({String? from, String? to, String source}) resolveReceiptRouteAddresses({
  Map<String, dynamic>? rawSource,
  Map<String, dynamic>? bookingDetails,
  String? origin,
  String? destination,
}) {
  final roots = <Map<String, dynamic>>[
    if (rawSource != null) rawSource,
    if (bookingDetails != null) bookingDetails,
  ];

  String? pickSide({required bool isFrom}) {
    final pathSets = isFrom
        ? const <List<String>>[
            ['route_address_snapshot', 'from_address'],
            ['route_address_snapshot', 'invoice_from_address'],
            ['invoice_from_address'],
            ['from_full_address'],
            ['from_label'],
            ['pickup_address'],
            ['pickupAddress'],
            ['pickup_label'],
            ['pickupLabel'],
            ['requested_from'],
            ['requestedFrom'],
            ['start_address'],
            ['startAddress'],
            ['origin'],
            ['pickup'],
            ['from'],
            ['booking', 'route_address_snapshot', 'from_address'],
            ['booking', 'route_address_snapshot', 'invoice_from_address'],
            ['booking', 'invoice_from_address'],
            ['booking', 'from_full_address'],
            ['booking', 'from_label'],
            ['booking', 'pickup_address'],
            ['booking', 'pickupAddress'],
            ['booking', 'pickup_label'],
            ['booking', 'requested_from'],
            ['booking', 'from'],
            ['record', 'invoice_from_address'],
            ['record', 'from_full_address'],
            ['record', 'from_label'],
            ['record', 'route_address_snapshot', 'from_address'],
            ['record', 'route_address_snapshot', 'invoice_from_address'],
            ['record', 'booking', 'invoice_from_address'],
            ['record', 'booking', 'from_full_address'],
            ['record', 'booking', 'from_label'],
            ['record', 'booking', 'from'],
            ['record', 'from'],
            ['booking_details', 'invoice_from_address'],
            ['booking_details', 'from_full_address'],
            ['booking_details', 'from_label'],
            ['booking_details', 'from'],
          ]
        : const <List<String>>[
            ['route_address_snapshot', 'to_address'],
            ['route_address_snapshot', 'invoice_to_address'],
            ['invoice_to_address'],
            ['to_full_address'],
            ['to_label'],
            ['destination_address'],
            ['destinationAddress'],
            ['dropoff_address'],
            ['dropoffAddress'],
            ['dropoff_label'],
            ['dropoffLabel'],
            ['requested_to'],
            ['requestedTo'],
            ['end_address'],
            ['endAddress'],
            ['destination'],
            ['dropoff'],
            ['to'],
            ['booking', 'route_address_snapshot', 'to_address'],
            ['booking', 'route_address_snapshot', 'invoice_to_address'],
            ['booking', 'invoice_to_address'],
            ['booking', 'to_full_address'],
            ['booking', 'to_label'],
            ['booking', 'destination_address'],
            ['booking', 'dropoff_address'],
            ['booking', 'dropoff_label'],
            ['booking', 'requested_to'],
            ['booking', 'to'],
            ['record', 'invoice_to_address'],
            ['record', 'to_full_address'],
            ['record', 'to_label'],
            ['record', 'route_address_snapshot', 'to_address'],
            ['record', 'route_address_snapshot', 'invoice_to_address'],
            ['record', 'booking', 'invoice_to_address'],
            ['record', 'booking', 'to_full_address'],
            ['record', 'booking', 'to_label'],
            ['record', 'booking', 'to'],
            ['record', 'to'],
            ['booking_details', 'invoice_to_address'],
            ['booking_details', 'to_full_address'],
            ['booking_details', 'to_label'],
            ['booking_details', 'to'],
          ];

    final candidates = <String?>[];
    for (final root in roots) {
      for (final path in pathSets) {
        candidates.add(_asTrimmedString(_mapPath(root, path)));
      }
    }
    // Normalized trip-history fields last (often coords for street rides).
    candidates.add(isFrom ? origin : destination);
    return receiptPickCustomerVisibleAddress(candidates);
  }

  final from = pickSide(isFrom: true);
  final to = pickSide(isFrom: false);
  final source = (from != null || to != null) ? 'resolved' : 'missing';
  return (from: from, to: to, source: source);
}

/// Copy frozen / human route address fields from a booking GET payload into
/// receipt source maps so PDF resolve can see them.
void mergeReceiptRouteAddressFields({
  required Map<String, dynamic> target,
  required Map<String, dynamic> authoritative,
}) {
  void copyKey(String key) {
    final value = authoritative[key];
    if (value == null) return;
    if (value is String && receiptIsNonAddressRoutePlaceholder(value)) return;
    target[key] = value;
  }

  copyKey('invoice_from_address');
  copyKey('invoice_to_address');
  copyKey('invoice_from_address_source');
  copyKey('invoice_to_address_source');
  copyKey('from_full_address');
  copyKey('to_full_address');
  copyKey('from_label');
  copyKey('to_label');
  copyKey('pickup_address');
  copyKey('destination_address');
  copyKey('dropoff_address');
  copyKey('from');
  copyKey('to');

  final snap = authoritative['route_address_snapshot'];
  if (snap is Map) {
    target['route_address_snapshot'] = Map<String, dynamic>.from(snap);
  }

  final booking = authoritative['booking'];
  if (booking is Map) {
    final nested = target['booking'] is Map
        ? Map<String, dynamic>.from(target['booking'] as Map)
        : <String, dynamic>{};
    final bookingMap = Map<String, dynamic>.from(booking);
    mergeReceiptRouteAddressFields(target: nested, authoritative: bookingMap);
    target['booking'] = nested;
  }

  final record = authoritative['record'];
  if (record is Map) {
    final nested = target['record'] is Map
        ? Map<String, dynamic>.from(target['record'] as Map)
        : <String, dynamic>{};
    final recordMap = Map<String, dynamic>.from(record);
    mergeReceiptRouteAddressFields(target: nested, authoritative: recordMap);
    target['record'] = nested;
  }
}
