// LIMOUSINE-MARKETPLACE-P0 — public service vertical token and normalization.
//
// Reuses the existing public-partner `services[]` catalog (the field that
// survives booking-worker persist). This is not a second booking engine and
// is not inferred from taxi, airport, premium tier, or vehicle names.

/// Canonical public-profile service token for the limousine vertical.
const String kLimousinePublicServiceId = 'limousine';

/// Accepted aliases that normalize to [kLimousinePublicServiceId].
/// Keep this set narrow so taxi / airport / hourly / premium never match.
const Set<String> kLimousinePublicServiceAliases = <String>{
  'limousine',
  'limousine_service',
};

/// Customer-home hero/card asset. Directory `assets/fluxidi/` is already
/// registered in pubspec.yaml, so no per-file entry is required.
const String kLimousineMarketplaceHeroAsset =
    'assets/fluxidi/customer_home_limousine_banner.webp';

/// Shared ride/quote seam. P0 does not add a calculator service or wizard.
const String kLimousineSharedEngineSeam =
    'CalculatorPage + POST /quote (existing ride lifecycle)';

String normalizePublicServiceToken(String? raw) {
  return (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
}

/// Returns [kLimousinePublicServiceId] when [raw] is an explicit limousine
/// token; otherwise null. Taxi, airport, premium, hourly, and display names
/// never match.
String? normalizeLimousineServiceId(String? raw) {
  final token = normalizePublicServiceToken(raw);
  if (token.isEmpty) return null;
  if (kLimousinePublicServiceAliases.contains(token)) {
    return kLimousinePublicServiceId;
  }
  return null;
}

bool isLimousineServiceToken(String? raw) =>
    normalizeLimousineServiceId(raw) != null;

bool looksTruthyPublicFlag(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  return text == 'true' ||
      text == '1' ||
      text == 'yes' ||
      text == 'on' ||
      text == 'enabled';
}

bool looksFalseyPublicFlag(dynamic value) {
  if (value == null) return false;
  if (value is bool) return !value;
  if (value is num) return value == 0;
  final text = value.toString().trim().toLowerCase();
  return text == 'false' ||
      text == '0' ||
      text == 'no' ||
      text == 'off' ||
      text == 'disabled';
}

Map<String, dynamic> asStringKeyedMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

List<String> publicServiceTokensFrom(dynamic raw) {
  if (raw is List) {
    return raw
        .map((item) => normalizePublicServiceToken(item?.toString()))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }
  if (raw is Map) {
    return raw.keys
        .map((key) => normalizePublicServiceToken(key.toString()))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }
  final single = normalizePublicServiceToken(raw?.toString());
  if (single.isEmpty) return const <String>[];
  return <String>[single];
}

bool serviceCollectionContainsLimousine(dynamic raw) {
  if (raw is Map) {
    for (final entry in raw.entries) {
      if (!isLimousineServiceToken(entry.key.toString())) continue;
      if (looksFalseyPublicFlag(entry.value)) return false;
      if (entry.value == null || looksTruthyPublicFlag(entry.value)) {
        return true;
      }
    }
    return false;
  }
  for (final token in publicServiceTokensFrom(raw)) {
    if (isLimousineServiceToken(token)) return true;
  }
  return false;
}

/// Authoritative company-level limousine opt-in.
///
/// The durable opt-in is a `services[]` limousine token. A defaulted
/// `booking_capabilities.limousine=false` must not hide that token.
/// Premium tier, vehicle names, and historical rides are ignored here.
bool partnerHasExplicitLimousineCapability(Map<String, dynamic> source) {
  if (serviceCollectionContainsLimousine(source['services'])) {
    return true;
  }
  var sawExplicitBoolean = false;
  var explicitTrue = false;
  var explicitFalse = false;

  void consider(dynamic value) {
    if (value == null) return;
    sawExplicitBoolean = true;
    if (looksTruthyPublicFlag(value)) {
      explicitTrue = true;
    } else if (looksFalseyPublicFlag(value)) {
      explicitFalse = true;
    }
  }

  consider(source['limousine_service_enabled']);
  consider(source['limousineServiceEnabled']);

  final capabilities = asStringKeyedMap(source['capabilities']);
  consider(capabilities['limousine']);
  consider(capabilities['limousine_service']);
  consider(capabilities['limousine_service_enabled']);
  consider(capabilities['limousineServiceEnabled']);

  final bookingCapabilities = asStringKeyedMap(
    source['booking_capabilities'] ?? source['bookingCapabilities'],
  );
  consider(bookingCapabilities['limousine']);
  consider(bookingCapabilities['limousine_service']);
  consider(bookingCapabilities['limousine_service_enabled']);
  consider(bookingCapabilities['limousineServiceEnabled']);

  final servicesMap = asStringKeyedMap(source['services']);
  if (servicesMap.isNotEmpty) {
    consider(servicesMap['limousine']);
    consider(servicesMap['limousine_service']);
  }

  if (explicitTrue) return true;
  if (explicitFalse || sawExplicitBoolean) return false;
  return false;
}
