import 'dart:math' as math;

import '../nearby/public_partner_bookability.dart';
import 'limousine_service_capability.dart';

/// Why a company is not a limousine provider. Missing evidence fails closed.
enum LimousineEligibilityDenial {
  missingCapability,
  companyInactive,
  companyDeleted,
  profileNotPublished,
  notBookable,
  noEligibleVehicle,
  marketMismatch,
}

class LimousineMarketRequest {
  const LimousineMarketRequest({
    this.postcode,
    this.countryCode,
    this.lat,
    this.lng,
  });

  final String? postcode;
  final String? countryCode;
  final double? lat;
  final double? lng;

  bool get hasConstraint {
    final pc = (postcode ?? '').trim();
    final cc = (countryCode ?? '').trim();
    return pc.isNotEmpty || cc.isNotEmpty || (lat != null && lng != null);
  }
}

class LimousineProviderEligibility {
  const LimousineProviderEligibility._({required this.eligible, this.denial});

  const LimousineProviderEligibility.allowed() : this._(eligible: true);

  const LimousineProviderEligibility.denied(LimousineEligibilityDenial denial)
    : this._(eligible: false, denial: denial);

  final bool eligible;
  final LimousineEligibilityDenial? denial;
}

/// Pure limousine provider gate.
///
/// A company is included only when every authoritative requirement is
/// present and consistent. Historical rides, premium tier, and a vehicle
/// named "limousine" never enable the company. No FLX company-code allowlist.
LimousineProviderEligibility evaluateLimousineProviderEligibility(
  Map<String, dynamic> company, {
  LimousineMarketRequest? request,
}) {
  if (_companyIsDeletedOrSuspended(company)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.companyDeleted,
    );
  }
  if (!_companyIsActive(company)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.companyInactive,
    );
  }
  if (!_publicProfilePublished(company)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.profileNotPublished,
    );
  }
  if (!isPublicPartnerBookable(company)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.notBookable,
    );
  }
  if (!partnerHasExplicitLimousineCapability(company)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.missingCapability,
    );
  }
  if (!_hasEligibleActiveLimousineVehicleOrService(company)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.noEligibleVehicle,
    );
  }
  if (request != null &&
      request.hasConstraint &&
      !_marketMatches(company, request)) {
    return const LimousineProviderEligibility.denied(
      LimousineEligibilityDenial.marketMismatch,
    );
  }
  return const LimousineProviderEligibility.allowed();
}

bool isEligibleLimousineProvider(
  Map<String, dynamic> company, {
  LimousineMarketRequest? request,
}) {
  return evaluateLimousineProviderEligibility(
    company,
    request: request,
  ).eligible;
}

List<Map<String, dynamic>> filterLimousineEligibleProviders(
  Iterable<Map<String, dynamic>> companies, {
  LimousineMarketRequest? request,
}) {
  return companies
      .where(
        (company) => isEligibleLimousineProvider(company, request: request),
      )
      .toList(growable: false);
}

bool isEligibleLimousineVehicle(Map<String, dynamic> vehicle) {
  if (_recordIsDeletedOrSuspended(vehicle)) return false;
  final hasExplicitLimousineConfig =
      // LIMOUSINE-MARKETPLACE-P2A: authoritative configured classification.
      isLimousineServiceToken(vehicle['service_category']?.toString()) ||
      isLimousineServiceToken(vehicle['serviceCategory']?.toString()) ||
      partnerHasExplicitLimousineCapability(vehicle) ||
      serviceCollectionContainsLimousine(vehicle['features']) ||
      serviceCollectionContainsLimousine(vehicle['service_ids']) ||
      serviceCollectionContainsLimousine(vehicle['serviceIds']) ||
      isLimousineServiceToken(vehicle['category']?.toString()) ||
      isLimousineServiceToken(vehicle['service']?.toString()) ||
      isLimousineServiceToken(vehicle['service_id']?.toString()) ||
      isLimousineServiceToken(vehicle['tierId']?.toString());
  if (!hasExplicitLimousineConfig) return false;
  // Published public vehicles often omit is_active; an explicit limousine
  // token may pass unless the row is explicitly inactive.
  return _recordIsActive(vehicle, missingMeansActive: true);
}

bool _hasEligibleActiveLimousineVehicleOrService(Map<String, dynamic> company) {
  if (_explicitServiceConfigurationsIncludeLimousine(company)) {
    return true;
  }
  final vehicles = _vehiclesFrom(company);
  if (vehicles == null) return false;
  for (final vehicle in vehicles) {
    if (isEligibleLimousineVehicle(vehicle)) return true;
  }
  return false;
}

bool _explicitServiceConfigurationsIncludeLimousine(
  Map<String, dynamic> company,
) {
  for (final key in const [
    'limousine_service_configurations',
    'limousineServiceConfigurations',
    'service_configurations',
    'serviceConfigurations',
  ]) {
    final raw = company[key];
    if (raw is! List) continue;
    for (final item in raw) {
      final row = asStringKeyedMap(item);
      if (row.isEmpty) continue;
      if (_recordIsDeletedOrSuspended(row)) continue;
      if (!_recordIsActive(row, missingMeansActive: true)) continue;
      if (partnerHasExplicitLimousineCapability(row) ||
          isLimousineServiceToken(row['service']?.toString()) ||
          isLimousineServiceToken(row['id']?.toString())) {
        return true;
      }
    }
  }
  return false;
}

List<Map<String, dynamic>>? _vehiclesFrom(Map<String, dynamic> company) {
  for (final key in const [
    'vehicles',
    'fleet',
    'public_vehicles',
    'publicVehicles',
  ]) {
    if (!company.containsKey(key)) continue;
    final raw = company[key];
    if (raw == null) return const <Map<String, dynamic>>[];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(asStringKeyedMap).toList(growable: false);
  }
  return null;
}

bool _companyIsDeletedOrSuspended(Map<String, dynamic> company) {
  if (_recordIsDeletedOrSuspended(company)) return true;
  final status = normalizePublicServiceToken(
    (company['status'] ?? company['company_status'] ?? company['companyStatus'])
        ?.toString(),
  );
  return status == 'deleted' ||
      status == 'suspended' ||
      status == 'tombstoned' ||
      status == 'tombstone';
}

bool _recordIsDeletedOrSuspended(Map<String, dynamic> record) {
  for (final key in const [
    'deleted',
    'is_deleted',
    'isDeleted',
    'tombstoned',
    'is_tombstoned',
    'isTombstoned',
    'suspended',
    'is_suspended',
    'isSuspended',
  ]) {
    if (looksTruthyPublicFlag(record[key])) return true;
  }
  return false;
}

bool _companyIsActive(Map<String, dynamic> company) {
  if (looksFalseyPublicFlag(company['is_active']) ||
      looksFalseyPublicFlag(company['isActive'])) {
    return false;
  }
  final availability = normalizePublicServiceToken(
    (company['availability_status'] ?? company['availabilityStatus'])
        ?.toString(),
  );
  if (availability == 'inactive' ||
      availability == 'deleted' ||
      availability == 'suspended') {
    return false;
  }
  if (looksTruthyPublicFlag(company['is_active']) ||
      looksTruthyPublicFlag(company['isActive'])) {
    return true;
  }
  if (availability == 'active') return true;
  return false;
}

bool _recordIsActive(
  Map<String, dynamic> record, {
  required bool missingMeansActive,
}) {
  if (looksFalseyPublicFlag(record['is_active']) ||
      looksFalseyPublicFlag(record['isActive'])) {
    return false;
  }
  if (looksTruthyPublicFlag(record['is_active']) ||
      looksTruthyPublicFlag(record['isActive'])) {
    return true;
  }
  return missingMeansActive;
}

bool _publicProfilePublished(Map<String, dynamic> company) {
  if (looksFalseyPublicFlag(company['profile_enabled']) ||
      looksFalseyPublicFlag(company['profileEnabled'])) {
    return false;
  }
  if (looksTruthyPublicFlag(company['profile_enabled']) ||
      looksTruthyPublicFlag(company['profileEnabled']) ||
      looksTruthyPublicFlag(company['public_profile_published']) ||
      looksTruthyPublicFlag(company['publicProfilePublished'])) {
    return true;
  }
  for (final key in const [
    'published_at',
    'publishedAt',
    'public_partner_profile_published_at',
    'publicPartnerProfilePublishedAt',
  ]) {
    if ((company[key] ?? '').toString().trim().isNotEmpty) return true;
  }
  return false;
}

bool _marketMatches(
  Map<String, dynamic> company,
  LimousineMarketRequest request,
) {
  final coverage = asStringKeyedMap(company['coverage']);
  final requestPostcode = _normalizePostcode(request.postcode);
  if (requestPostcode.isNotEmpty) {
    final companyPostcodes = <String>{
      _normalizePostcode(coverage['primary_postcode']?.toString()),
      _normalizePostcode(coverage['primaryPostcode']?.toString()),
      _normalizePostcode(company['primary_postcode']?.toString()),
      ..._postcodeList(coverage['postcodes']),
      ..._postcodeList(company['postcodes']),
    }..removeWhere((item) => item.isEmpty);
    if (companyPostcodes.isEmpty) return false;
    if (!companyPostcodes.contains(requestPostcode)) return false;
  }

  final requestCountry = _normalizeCountry(request.countryCode);
  if (requestCountry.isNotEmpty) {
    final companyCountry = _normalizeCountry(
      (coverage['country'] ??
              coverage['country_code'] ??
              coverage['countryCode'] ??
              company['country'] ??
              company['country_code'] ??
              company['countryCode'])
          ?.toString(),
    );
    if (companyCountry.isEmpty || companyCountry != requestCountry) {
      return false;
    }
  }

  if (request.lat != null && request.lng != null) {
    final lat = _asFiniteDouble(coverage['lat'] ?? company['lat']);
    final lng = _asFiniteDouble(coverage['lng'] ?? company['lng']);
    final radiusKm = _asFiniteDouble(
      coverage['service_radius_km'] ??
          coverage['serviceRadiusKm'] ??
          company['service_radius_km'] ??
          company['serviceRadiusKm'],
    );
    if (lat == null || lng == null || radiusKm == null || radiusKm <= 0) {
      return false;
    }
    if (_haversineKm(request.lat!, request.lng!, lat, lng) > radiusKm) {
      return false;
    }
  }
  return true;
}

String _normalizePostcode(String? raw) {
  return (raw ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

String _normalizeCountry(String? raw) {
  return (raw ?? '').trim().toUpperCase();
}

Iterable<String> _postcodeList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw.map((item) => _normalizePostcode(item?.toString()));
}

double? _asFiniteDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse((raw ?? '').toString().trim());
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      (math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2));
  return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degToRad(double deg) => deg * math.pi / 180.0;
