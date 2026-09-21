/// Typed models for the public partner endpoints.
///
/// Field names follow the existing client contract at golden commit 9df7e7b9.
/// Only fields the new app actually shows are modelled; unknown fields are
/// ignored rather than guessed.
library;

import 'public_company_presentation.dart';
import 'public_partner_visibility.dart';

Map<String, dynamic> asStringKeyedMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

String readText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = (source[key] ?? '').toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') continue;
    return value;
  }
  return '';
}

List<String> readTextList(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final raw = source[key];
    if (raw is! List) continue;
    final out = <String>[];
    for (final item in raw) {
      final value = (item ?? '').toString().trim();
      if (value.isEmpty) continue;
      out.add(value);
    }
    if (out.isNotEmpty) return out;
  }
  return const <String>[];
}

double? readDouble(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final raw = source[key];
    if (raw is num) return raw.toDouble();
    final parsed = double.tryParse((raw ?? '').toString().trim());
    if (parsed != null) return parsed;
  }
  return null;
}

String readHttpsUrl(Map<String, dynamic> source, List<String> keys) {
  final value = readText(source, keys);
  return publicPartnerImageIsRenderable(value) ? value : '';
}

/// One entry from `GET /partners/nearby` → `partners[]`.
class PublicPartnerSummary {
  const PublicPartnerSummary({
    required this.partnerId,
    required this.companyName,
    required this.companyCode,
    required this.city,
    required this.postcode,
    required this.countryCode,
    required this.supportedPostcodes,
    required this.logoUrl,
    required this.heroPhotoUrl,
    required this.serviceBadges,
    required this.bookable,
    required this.presentation,
    this.distanceKm,
  });

  factory PublicPartnerSummary.fromJson(Map<String, dynamic> json) {
    var country = readText(json, const <String>[
      'country_code',
      'countryCode',
      'country',
    ]);
    if (country.length == 2) country = country.toUpperCase();

    var postcode = readText(json, const <String>[
      'postcode',
      'postal_code',
      'postalCode',
      'zip',
      'zip_code',
      'zipCode',
    ]);
    final supported = readTextList(json, const <String>[
      'supported_postcodes',
      'supportedPostcodes',
    ]);
    if (postcode.isEmpty && supported.isNotEmpty) postcode = supported.first;

    return PublicPartnerSummary(
      partnerId: readText(json, const <String>['partner_id', 'partnerId']),
      // An explicitly published company_name is a real name. Only when it is
      // missing do we fall back to a code, and a fallback may never be the
      // platform brand.
      companyName: publicPartnerRealName(
            readText(json, const <String>['company_name', 'companyName']),
          ).isNotEmpty
          ? publicPartnerRealName(
              readText(json, const <String>['company_name', 'companyName']),
            )
          : sanitizePublicPartnerFallbackName(
              readText(json, const <String>[
                'public_company_code',
                'publicCompanyCode',
                'company_code',
                'companyCode',
              ]),
            ),
      companyCode: readText(json, const <String>[
        'public_company_code',
        'publicCompanyCode',
        'company_code',
        'companyCode',
      ]),
      city: readText(json, const <String>[
        'city',
        'municipality',
        'locality',
        'place',
      ]),
      postcode: postcode,
      countryCode: country,
      supportedPostcodes: supported,
      logoUrl: readHttpsUrl(json, const <String>['logo_url', 'logoUrl']),
      heroPhotoUrl: readHttpsUrl(json, const <String>[
        'hero_photo_url',
        'heroPhotoUrl',
      ]),
      serviceBadges: readTextList(json, const <String>[
        'service_badges',
        'serviceBadges',
      ]),
      bookable: isPublicPartnerBookable(json),
      presentation: publicCompanyPresentationFrom(json),
      distanceKm: readDouble(json, const <String>['distance_km', 'distanceKm']),
    );
  }

  final String partnerId;

  /// Empty when the server only exposed an internal or platform name.
  final String companyName;
  final String companyCode;
  final String city;
  final String postcode;
  final String countryCode;
  final List<String> supportedPostcodes;
  final String logoUrl;
  final String heroPhotoUrl;
  final List<String> serviceBadges;

  /// Server-stated bookability. Never defaulted to true.
  final bool bookable;

  /// Example / review marking, so a demo company is never shown as ordinary.
  final PublicCompanyPresentation presentation;

  /// Only present when the server returned it (geo queries).
  final double? distanceKm;

  bool get hasIdentity => partnerId.isNotEmpty;

  /// `city · postcode · COUNTRY`, skipping parts the server did not send.
  String get locationLabel => <String>[
    city,
    postcode,
    countryCode,
  ].where((part) => part.trim().isNotEmpty).join(' · ');

  /// Name to show. Falls back to a public code and finally to the partner id,
  /// but a fallback is never the platform brand.
  String get displayName {
    if (companyName.isNotEmpty) return companyName;
    final code = sanitizePublicPartnerFallbackName(companyCode);
    return code.isNotEmpty ? code : partnerId;
  }
}

/// `GET /partners/nearby` response envelope.
class PublicPartnerSearchResult {
  const PublicPartnerSearchResult({
    required this.partners,
    required this.postcode,
    required this.count,
  });

  factory PublicPartnerSearchResult.fromJson(Map<String, dynamic> json) {
    final raw = json['partners'];
    final partners = <PublicPartnerSummary>[];
    if (raw is List) {
      for (final item in raw) {
        final summary = PublicPartnerSummary.fromJson(asStringKeyedMap(item));
        if (summary.hasIdentity) partners.add(summary);
      }
    }
    final count = readDouble(json, const <String>['count'])?.round();
    return PublicPartnerSearchResult(
      partners: partners,
      postcode: readText(json, const <String>['postcode']),
      count: count ?? partners.length,
    );
  }

  /// Server order is preserved.
  final List<PublicPartnerSummary> partners;
  final String postcode;
  final int count;

  bool get isEmpty => partners.isEmpty;
}

/// `GET /partners/profile` → `profile`.
class PublicPartnerProfile {
  const PublicPartnerProfile({
    required this.partnerId,
    required this.companyName,
    required this.tagline,
    required this.about,
    required this.regionLabel,
    required this.postcodes,
    required this.website,
    required this.publicPhone,
    required this.bookingEmail,
    required this.logoUrl,
    required this.heroPhotoUrl,
    required this.services,
    required this.paymentMethods,
    required this.verifiedPartner,
    required this.bookable,
    required this.presentation,
    required this.vehicles,
  });

  factory PublicPartnerProfile.fromJson(
    Map<String, dynamic> profile, {
    required String partnerId,
  }) {
    final coverage = asStringKeyedMap(profile['coverage']);
    final contact = asStringKeyedMap(profile['public_contact']);
    final media = asStringKeyedMap(profile['media']);
    final trust = asStringKeyedMap(profile['trust']);

    var heroUrl = readHttpsUrl(profile, const <String>[
      'public_hero_photo_url',
      'publicHeroPhotoUrl',
    ]);
    if (heroUrl.isEmpty) {
      heroUrl = readHttpsUrl(media, const <String>[
        'hero_photo_url',
        'heroPhotoUrl',
      ]);
    }
    if (heroUrl.isEmpty) {
      heroUrl = readHttpsUrl(profile, const <String>[
        'hero_photo_url',
        'heroPhotoUrl',
      ]);
    }

    final about = readText(profile, const <String>['about_long', 'aboutLong']);

    return PublicPartnerProfile(
      partnerId: partnerId.trim(),
      companyName: publicPartnerRealName(
        readText(profile, const <String>['company_name', 'companyName']),
      ),
      tagline: readText(profile, const <String>['tagline']),
      about: about.isNotEmpty
          ? about
          : readText(profile, const <String>['about_short', 'aboutShort']),
      regionLabel: readText(coverage, const <String>[
        'region_label',
        'regionLabel',
      ]),
      postcodes: readTextList(coverage, const <String>['postcodes']),
      website: readText(contact, const <String>['website']),
      publicPhone: readText(contact, const <String>[
        'public_phone',
        'publicPhone',
      ]),
      bookingEmail: readText(contact, const <String>[
        'booking_email',
        'bookingEmail',
      ]),
      logoUrl: readHttpsUrl(media, const <String>['logo_url', 'logoUrl']),
      heroPhotoUrl: heroUrl,
      services: _taxiServices(profile['services']),
      paymentMethods: readTextList(profile, const <String>[
        'payment_methods',
        'paymentMethods',
      ]),
      verifiedPartner:
          trust['verified_partner'] == true || trust['verifiedPartner'] == true,
      bookable: isPublicPartnerBookable(profile),
      presentation: publicCompanyPresentationFrom(profile),
      vehicles: <Map<String, dynamic>>[
        if (profile['vehicles'] is List)
          for (final item in profile['vehicles'] as List)
            if (item is Map) asStringKeyedMap(item),
      ],
    );
  }

  final String partnerId;
  final String companyName;
  final String tagline;
  final String about;
  final String regionLabel;
  final List<String> postcodes;
  final String website;
  final String publicPhone;
  final String bookingEmail;
  final String logoUrl;
  final String heroPhotoUrl;
  final List<String> services;
  final List<String> paymentMethods;
  final bool verifiedPartner;
  final bool bookable;
  final PublicCompanyPresentation presentation;

  /// Raw published vehicles, used to name the availability offers.
  final List<Map<String, dynamic>> vehicles;

  /// Tenant and company parsed from a `company:<tenant>:<company>` partner id.
  String get scopedTenantId {
    final parts = partnerId.split(':');
    return parts.length == 3 && parts[0] == 'company' ? parts[1].trim() : '';
  }

  String get scopedCompanyId {
    final parts = partnerId.split(':');
    return parts.length == 3 && parts[0] == 'company' ? parts[2].trim() : '';
  }

  bool get hasContactDetails =>
      regionLabel.isNotEmpty ||
      postcodes.isNotEmpty ||
      website.isNotEmpty ||
      publicPhone.isNotEmpty ||
      bookingEmail.isNotEmpty;

  /// Services come from a list or from a map of booleans, as the server sends
  /// either shape. Limousine tokens are dropped: this app has no limousine
  /// surface yet.
  static List<String> _taxiServices(Object? raw) {
    final tokens = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final token = (item ?? '').toString().trim();
        if (token.isNotEmpty) tokens.add(token);
      }
    } else if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value == true) tokens.add(entry.key.toString().trim());
      }
    }
    return tokens
        .where((token) => !token.toLowerCase().contains('limousine'))
        .toList(growable: false);
  }
}
