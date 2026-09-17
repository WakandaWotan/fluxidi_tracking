import 'dart:convert';
import 'dart:io';

import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:path_provider/path_provider.dart';

/// Persists an explicitly confirmed map pin with the owned address label.
/// Billing/legal profile fields stay unchanged.
class CustomerConfirmedLocation {
  const CustomerConfirmedLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  bool get isUsable =>
      label.trim().isNotEmpty && latitude.isFinite && longitude.isFinite;
}

String customerConfirmedLocationKey(String label) {
  final parts = limousineParseStreetHouse(label);
  final postcode = limousineAddressQueryPostcode(label) ?? '';
  final street = limousineFoldAddressToken(parts.street);
  if (street.isEmpty || !parts.hasNumber || postcode.isEmpty) return '';
  return '$street|${parts.number}|${parts.letter}|$postcode';
}

bool customerConfirmedLocationMatches(String label, CustomerConfirmedLocation stored) {
  final left = customerConfirmedLocationKey(label);
  final right = customerConfirmedLocationKey(stored.label);
  return left.isNotEmpty && left == right;
}

/// Quote coordinates may be reused only for the same house (street, number,
/// letter, postcode). 48A Schorisse must not inherit 48 Maarkedal or Ronse.
bool customerBookingQuotedLabelMatches(String currentLabel, String quotedLabel) {
  final current = currentLabel.trim();
  final quoted = quotedLabel.trim();
  if (current.isEmpty || quoted.isEmpty) return false;
  if (current == quoted) return true;
  final left = customerConfirmedLocationKey(current);
  final right = customerConfirmedLocationKey(quoted);
  return left.isNotEmpty && left == right;
}

double? customerBookingReuseQuotedCoordinate({
  required String currentLabel,
  required String quotedLabel,
  double? current,
  double? quoted,
}) {
  if (current != null && current.isFinite) return current;
  if (quoted == null || !quoted.isFinite) return null;
  if (!customerBookingQuotedLabelMatches(currentLabel, quotedLabel)) {
    return null;
  }
  return quoted;
}

class CustomerConfirmedLocationStore {
  CustomerConfirmedLocationStore._();
  static final CustomerConfirmedLocationStore instance =
      CustomerConfirmedLocationStore._();

  Map<String, CustomerConfirmedLocation>? _memory;
  Future<Map<String, CustomerConfirmedLocation>>? _loading;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/fluxidi_confirmed_addresses_v1.json');
  }

  Future<Map<String, CustomerConfirmedLocation>> _load() async {
    if (_memory != null) return _memory!;
    if (_loading != null) return _loading!;
    _loading = () async {
      try {
        final file = await _file();
        if (!await file.exists()) {
          _memory = <String, CustomerConfirmedLocation>{};
          return _memory!;
        }
        final decoded = jsonDecode(await file.readAsString());
        final out = <String, CustomerConfirmedLocation>{};
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is! Map) return;
            final label = (value['label'] ?? '').toString().trim();
            final lat = double.tryParse('${value['lat']}');
            final lon = double.tryParse('${value['lon']}');
            if (label.isEmpty || lat == null || lon == null) return;
            final item = CustomerConfirmedLocation(
              label: label,
              latitude: lat,
              longitude: lon,
            );
            final id = customerConfirmedLocationKey(label);
            if (id.isNotEmpty && item.isUsable) out[id] = item;
          });
        }
        _memory = out;
        return out;
      } catch (_) {
        _memory = <String, CustomerConfirmedLocation>{};
        return _memory!;
      }
    }();
    try {
      return await _loading!;
    } finally {
      _loading = null;
    }
  }

  Future<CustomerConfirmedLocation?> readFor(String label) async {
    final key = customerConfirmedLocationKey(label);
    if (key.isEmpty) return null;
    final all = await _load();
    final stored = all[key];
    if (stored == null || !customerConfirmedLocationMatches(label, stored)) {
      return null;
    }
    return stored;
  }

  Future<void> save({
    required String label,
    required double latitude,
    required double longitude,
  }) async {
    final item = CustomerConfirmedLocation(
      label: label.trim(),
      latitude: latitude,
      longitude: longitude,
    );
    final key = customerConfirmedLocationKey(item.label);
    if (key.isEmpty || !item.isUsable) return;
    final all = await _load();
    all[key] = item;
    _memory = all;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          for (final entry in all.entries)
            entry.key: <String, dynamic>{
              'label': entry.value.label,
              'lat': entry.value.latitude,
              'lon': entry.value.longitude,
            },
        }),
      );
    } catch (_) {}
  }

  Future<void> forget(String label) async {
    final key = customerConfirmedLocationKey(label);
    if (key.isEmpty) return;
    final all = await _load();
    all.remove(key);
    _memory = all;
  }
}
