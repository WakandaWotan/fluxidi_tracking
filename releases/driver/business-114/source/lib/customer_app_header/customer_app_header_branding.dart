/// Company header branding read from public resolve / settings, never from a
/// hardcoded Taxi Mario asset and never using FLX-00028 as a booking id.
library;

import 'customer_app_header_media.dart';
import 'header_local_cache.dart';
import 'customer_app_header_mode.dart';

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

String _text(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = (source[key] ?? '').toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') continue;
    return value;
  }
  return '';
}

String _https(Map<String, dynamic> source, List<String> keys) {
  final value = _text(source, keys);
  return customerAppHeaderImageIsUsable(value) ? value : '';
}

/// Logo, cover, display mode and cache revision for one company's own app.
class CustomerAppHeaderBranding {
  const CustomerAppHeaderBranding({
    this.mode = CustomerAppHeaderMode.logoOnly,
    this.logoPosition = CustomerAppHeaderLogoPosition.topLeft,
    this.hasExplicitMode = false,
    this.logoUrl = '',
    this.coverUrl = '',
    this.companyName = '',
    this.mediaRevision = '',
    this.useOnDriverApp = false,
    this.useOnBusinessApp = false,
  });

  final CustomerAppHeaderMode mode;
  final CustomerAppHeaderLogoPosition logoPosition;
  final bool hasExplicitMode;
  final String logoUrl;
  final String coverUrl;
  final String companyName;
  final String mediaRevision;

  /// Company choice. Off keeps the driver's own header.
  final bool useOnDriverApp;
  final bool useOnBusinessApp;

  bool get hasLogo => customerAppHeaderImageIsUsable(logoUrl);

  bool get hasCover => customerAppHeaderImageIsUsable(coverUrl);

  CustomerAppHeaderMode get effectiveMode => effectiveCustomerAppHeaderMode(
    requested: mode,
    hasLogo: hasLogo,
    hasCover: hasCover,
  );

  String get displayLogoUrl =>
      customerAppHeaderCacheBustedUrl(logoUrl, revision: mediaRevision);

  String get displayCoverUrl =>
      customerAppHeaderCacheBustedUrl(coverUrl, revision: mediaRevision);

  CustomerAppHeaderBranding copyWith({
    CustomerAppHeaderMode? mode,
    CustomerAppHeaderLogoPosition? logoPosition,
    bool? hasExplicitMode,
    String? logoUrl,
    String? coverUrl,
    String? companyName,
    String? mediaRevision,
    bool? useOnDriverApp,
    bool? useOnBusinessApp,
  }) {
    return CustomerAppHeaderBranding(
      mode: mode ?? this.mode,
      logoPosition: logoPosition ?? this.logoPosition,
      hasExplicitMode: hasExplicitMode ?? this.hasExplicitMode,
      logoUrl: logoUrl ?? this.logoUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      companyName: companyName ?? this.companyName,
      mediaRevision: mediaRevision ?? this.mediaRevision,
      useOnDriverApp: useOnDriverApp ?? this.useOnDriverApp,
      useOnBusinessApp: useOnBusinessApp ?? this.useOnBusinessApp,
    );
  }

  /// Reads public resolve, partner profile, or an authorized settings echo.
  ///
  /// Unknown fields are ignored. A missing mode is [CustomerAppHeaderMode.logoOnly].
  factory CustomerAppHeaderBranding.fromJson(Map<String, dynamic> json) {
    final media = _asMap(json['media']);
    final logo = _firstHttps(<String>[
      _https(media, const <String>['logo_url', 'logoUrl']),
      _https(json, const <String>[
        'public_logo_url',
        'publicLogoUrl',
        'logo_url',
        'logoUrl',
      ]),
    ]);
    final cover = _firstHttps(<String>[
      _https(json, const <String>[
        'public_hero_photo_url',
        'publicHeroPhotoUrl',
        'cover_url',
        'coverUrl',
        'header_image_url',
        'headerImageUrl',
      ]),
      _https(media, const <String>[
        'hero_photo_url',
        'heroPhotoUrl',
        'cover_url',
        'coverUrl',
      ]),
    ]);
    final hasMode =
        json.containsKey(kCustomerAppHeaderModeField) ||
        json.containsKey(kCustomerAppHeaderModeFieldCamel);
    return CustomerAppHeaderBranding(
      mode: hasMode
          ? parseCustomerAppHeaderMode(
              json[kCustomerAppHeaderModeField] ??
                  json[kCustomerAppHeaderModeFieldCamel],
            )
          : CustomerAppHeaderMode.logoOnly,
      logoPosition: parseCustomerAppHeaderLogoPosition(
        json[kCustomerAppHeaderLogoPositionField] ??
            json[kCustomerAppHeaderLogoPositionFieldCamel],
      ),
      hasExplicitMode: hasMode,
      logoUrl: logo,
      coverUrl: cover,
      companyName: _text(json, const <String>[
        'display_name',
        'displayName',
        'company_name',
        'companyName',
      ]),
      mediaRevision: _text(json, const <String>[
        kCustomerAppHeaderMediaRevisionField,
        'customerAppHeaderMediaRevision',
        'media_revision',
        'updated_at',
        'updatedAt',
      ]),
      useOnDriverApp: parseDriverAppUseCompanyHeader(
        json[kDriverAppUseCompanyHeaderField] ??
            json[kDriverAppUseCompanyHeaderFieldCamel],
      ),
      useOnBusinessApp: parseBusinessAppUseCompanyHeader(
        json[kBusinessAppUseCompanyHeaderField] ??
            json[kBusinessAppUseCompanyHeaderFieldCamel],
      ),
    );
  }

  static String _firstHttps(List<String> urls) {
    for (final url in urls) {
      if (url.isNotEmpty) return url;
    }
    return '';
  }
}

Future<CustomerAppHeaderBranding?> loadCachedHeaderBranding(
  String scope,
) async {
  final raw = await readHeaderPresentation(scope);
  return raw == null ? null : CustomerAppHeaderBranding.fromJson(raw);
}

Future<void> cacheHeaderBranding(String scope, CustomerAppHeaderBranding b) =>
    saveHeaderPresentation(scope, {
      'customer_app_header_mode': switch (b.mode) {
        CustomerAppHeaderMode.logoOnly => 'logo',
        CustomerAppHeaderMode.coverOnly => 'header_image',
        CustomerAppHeaderMode.coverAndLogo => 'header_and_logo',
      },
      'customer_app_header_logo_position':
          b.logoPosition == CustomerAppHeaderLogoPosition.topRight
          ? 'top_right'
          : 'top_left',
      'public_logo_url': b.logoUrl,
      'public_hero_photo_url': b.coverUrl,
      'company_name': b.companyName,
      'customer_app_header_media_revision': b.mediaRevision,
      'driver_app_use_company_header': b.useOnDriverApp,
    });
