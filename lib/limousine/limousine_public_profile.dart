// Standalone public limousine company profile. Never a taxi partner-page
// variant. Reads only the already-loaded public projection.

import '../app_strings.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_service_capability.dart';

class LimousinePublicProfileData {
  const LimousinePublicProfileData({
    required this.showroom,
    this.ratingAverage,
    this.ratingCount,
    this.websiteUrl = '',
    this.publicPhone = '',
    this.bookingEmail = '',
    this.serviceRegion = '',
  });

  final LimousineProviderShowroomData showroom;
  final double? ratingAverage;
  final int? ratingCount;
  final String websiteUrl;
  final String publicPhone;
  final String bookingEmail;
  final String serviceRegion;

  bool get hasPublicRating => ratingAverage != null && (ratingCount ?? 0) > 0;

  bool get hasPublicContact =>
      websiteUrl.isNotEmpty ||
      publicPhone.isNotEmpty ||
      bookingEmail.isNotEmpty;
}

double? _publicRatingAverage(Map<String, dynamic> source) {
  for (final key in const [
    'rating_avg',
    'ratingAvg',
    'average_rating',
    'averageRating',
  ]) {
    final raw = source[key];
    if (raw is num && raw.isFinite && raw > 0 && raw <= 5) {
      return raw.toDouble();
    }
    final parsed = double.tryParse((raw ?? '').toString().trim());
    if (parsed != null && parsed > 0 && parsed <= 5) return parsed;
  }
  return null;
}

int? _publicRatingCount(Map<String, dynamic> source) {
  for (final key in const ['rating_count', 'ratingCount', 'review_count']) {
    final raw = source[key];
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0) return raw.round();
    final parsed = int.tryParse((raw ?? '').toString().trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

String _httpsOrPublicHost(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.startsWith('https://')) return text;
  if (RegExp(r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/.*)?$').hasMatch(text)) {
    return 'https://$text';
  }
  return '';
}

String _publicPhone(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return '';
  if (!RegExp(r'^[+\d][\d\s().-]{5,}$').hasMatch(text)) return '';
  return text;
}

String _publicEmail(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty || !text.contains('@') || text.contains(' ')) return '';
  return text;
}

String _publicServiceRegion(Map<String, dynamic> profile) {
  final coverage = asStringKeyedMap(profile['coverage']);
  for (final value in <Object?>[
    coverage['region_label'],
    coverage['regionLabel'],
    coverage['region'],
    profile['service_region'],
    profile['serviceRegion'],
    profile['public_city'],
    profile['publicCity'],
    coverage['public_city'],
    coverage['city'],
  ]) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) continue;
    final token = normalizePublicServiceToken(text);
    if (kLimousineShowroomForbiddenKeys.contains(token)) continue;
    if (token.contains('operating_base') || token.contains('tenant')) {
      continue;
    }
    return text;
  }
  return '';
}

LimousinePublicProfileData buildLimousinePublicProfileData({
  required Map<String, dynamic> profile,
  String partnerIdFallback = '',
  String companyNameFallback = '',
  double? distanceKm,
  LimousineDiscoveryCard? discoveryCard,
  AppLanguage language = AppLanguage.nl,
}) {
  final showroom = buildLimousineProviderShowroomData(
    profile: profile,
    partnerIdFallback: partnerIdFallback,
    companyNameFallback: companyNameFallback,
    distanceKm: distanceKm,
    discoveryCard: discoveryCard,
    language: language,
  );
  final trust = asStringKeyedMap(profile['trust']);
  final contact = asStringKeyedMap(profile['public_contact']);
  return LimousinePublicProfileData(
    showroom: showroom,
    ratingAverage: _publicRatingAverage(profile) ?? _publicRatingAverage(trust),
    ratingCount: _publicRatingCount(profile) ?? _publicRatingCount(trust),
    websiteUrl: _httpsOrPublicHost(contact['website'] ?? profile['website']),
    publicPhone: _publicPhone(
      contact['public_phone'] ?? contact['publicPhone'],
    ),
    bookingEmail: _publicEmail(
      contact['booking_email'] ?? contact['bookingEmail'],
    ),
    serviceRegion: () {
      final region = _publicServiceRegion(profile);
      if (region.isNotEmpty) return region;
      return discoveryCard?.publicCity ?? '';
    }(),
  );
}
