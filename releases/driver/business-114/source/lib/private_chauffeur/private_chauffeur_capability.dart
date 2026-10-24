// Privéchauffeur is its own public service. It is not limousine and not taxi.
//
// No earlier canonical code exists in this repo: the company catalog, the
// nearby service filter and the quote/book bodies only know `limousine`.
// `private_chauffeur` is therefore the code this app reads and keeps.
//
// A missing or false flag means the company does not offer the service.
// Taxi, airport and limousine tokens never count as an offer.

import '../limousine/limousine_service_capability.dart';

const String kPrivateChauffeurServiceCode = 'private_chauffeur';

/// Ride quote and booking cannot carry [kPrivateChauffeurServiceCode] yet.
/// Limousine quote/book hardcodes `service_category: limousine`, and the
/// worker resolver rejects every other category. Do not submit those calls.
const bool kPrivateChauffeurBookingContractReady = false;

bool partnerExplicitlyOffersPrivateChauffeur(Map<String, dynamic> partner) {
  if (_hasExplicitPrivateChauffeurFalse(partner)) return false;
  if (_hasExplicitPrivateChauffeurTrue(partner)) return true;
  final services = partner['services'];
  if (services is List) {
    return publicServiceTokensFrom(
      services,
    ).contains(kPrivateChauffeurServiceCode);
  }
  return false;
}

bool privateChauffeurPartnerPassesAccountGates(Map<String, dynamic> partner) {
  if (looksFalseyPublicFlag(partner['is_active']) ||
      looksFalseyPublicFlag(partner['isActive'])) {
    return false;
  }
  if (looksTruthyPublicFlag(partner['deleted']) ||
      looksTruthyPublicFlag(partner['is_deleted']) ||
      looksTruthyPublicFlag(partner['suspended'])) {
    return false;
  }
  if (looksFalseyPublicFlag(partner['profile_enabled']) ||
      looksFalseyPublicFlag(partner['profileEnabled'])) {
    return false;
  }
  final status =
      (partner['subscription_status'] ?? partner['subscriptionStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  if (status.isNotEmpty && status != 'active' && status != 'valid') {
    return false;
  }
  return true;
}

/// Listable only with a public id, the existing account gates, and an
/// explicit Privéchauffeur offer. Region coverage stays on the nearby query.
bool privateChauffeurPartnerIsListable(Map<String, dynamic> partner) {
  final id = privateChauffeurPartnerId(partner);
  if (id.isEmpty) return false;
  if (!privateChauffeurPartnerPassesAccountGates(partner)) return false;
  return partnerExplicitlyOffersPrivateChauffeur(partner);
}

String privateChauffeurPartnerId(Map<String, dynamic> partner) {
  return (partner['public_partner_id'] ??
          partner['publicPartnerId'] ??
          partner['partner_id'] ??
          partner['partnerId'] ??
          '')
      .toString()
      .trim();
}

String privateChauffeurCompanyName(Map<String, dynamic> partner) {
  return (partner['company_name'] ??
          partner['companyName'] ??
          partner['public_trading_name'] ??
          partner['publicTradingName'] ??
          '')
      .toString()
      .trim();
}

bool _isPrivateChauffeurKey(String key) {
  final compact = normalizePublicServiceToken(key).replaceAll('_', '');
  return compact == 'privatechauffeur' || compact == 'privatechauffeurenabled';
}

bool _hasExplicitPrivateChauffeurFalse(Map<String, dynamic> partner) {
  if (_mapHasExplicitFalse(partner)) return true;
  for (final nested in _nestedMaps(partner)) {
    if (_mapHasExplicitFalse(nested)) return true;
  }
  return false;
}

bool _hasExplicitPrivateChauffeurTrue(Map<String, dynamic> partner) {
  if (_mapHasExplicitTrue(partner)) return true;
  for (final nested in _nestedMaps(partner)) {
    if (_mapHasExplicitTrue(nested)) return true;
  }
  return false;
}

List<Map<String, dynamic>> _nestedMaps(Map<String, dynamic> partner) {
  final maps = <Map<String, dynamic>>[];
  for (final key in const <String>[
    'services',
    'capabilities',
    'booking_capabilities',
    'bookingCapabilities',
  ]) {
    final value = partner[key];
    if (value is Map) maps.add(asStringKeyedMap(value));
  }
  return maps;
}

bool _mapHasExplicitFalse(Map<String, dynamic> map) {
  for (final entry in map.entries) {
    if (!_isPrivateChauffeurKey(entry.key)) continue;
    if (looksFalseyPublicFlag(entry.value)) return true;
  }
  return false;
}

bool _mapHasExplicitTrue(Map<String, dynamic> map) {
  for (final entry in map.entries) {
    if (!_isPrivateChauffeurKey(entry.key)) continue;
    if (looksTruthyPublicFlag(entry.value)) return true;
  }
  return false;
}
