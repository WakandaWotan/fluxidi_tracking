import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'app_strings.dart';
import 'calculator_page.dart';
import 'customer_profile_store.dart';
import 'customer_theme_palette.dart';
import 'customer_theme_store.dart';
import 'partner_public_profile_page.dart';

typedef CustomerProfileBackendSync =
    Future<CustomerProfile?> Function({required String reason});

class NearbyPartnersPage extends StatefulWidget {
  final WidgetBuilder customerHomeBuilder;
  final WidgetBuilder regionRegistrationBuilder;
  final CustomerProfileBackendSync syncCustomerProfileFromBackend;
  final bool selectionMode;

  const NearbyPartnersPage({
    super.key,
    required this.customerHomeBuilder,
    required this.regionRegistrationBuilder,
    required this.syncCustomerProfileFromBackend,
    this.selectionMode = false,
  });

  @override
  State<NearbyPartnersPage> createState() => _NearbyPartnersPageState();
}

class _NearbyPartnersPageState extends State<NearbyPartnersPage> {
  final TextEditingController _postalCodeCtrl = TextEditingController();
  static const List<int> _gpsRadiusOptionsKm = <int>[5, 10, 20, 30];
  static const int _favoritePartnersDisplayLimit = 12;
  bool _searching = false;
  bool _searchingByLocation = false;
  bool _searched = false;
  bool _lastSearchUsedLocation = false;
  int _selectedGpsRadiusKm = 20;
  String _normalizedPostcode = '';
  String _locationSearchLabel = '';
  List<Map<String, dynamic>> _partners = const <Map<String, dynamic>>[];
  Set<String> _favoritePartnerIds = <String>{};
  List<Map<String, dynamic>> _favoritePartnerProfiles =
      const <Map<String, dynamic>>[];
  bool _favoritesLoading = false;
  String? _favoritesError;
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _themePalette.isDark;
  Color get _bg => _themePalette.background;
  Color get _card => _themePalette.surface;
  Color get _panel => _themePalette.surfaceAlt;
  Color get _gold => _themePalette.gold;
  Color get _bronze => _themePalette.bronze;
  Color get _textPrimary => _themePalette.textPrimary;
  Color get _textMuted => _themePalette.textMuted;
  Color get _border => _themePalette.border;
  Color get _shadow => _themePalette.shadow;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) return en;
    if (lang == AppLanguage.fr) return fr;
    if (lang == AppLanguage.es) return es;
    return nl;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshFavoritePartners(reason: 'nearby_init'));
  }

  @override
  void dispose() {
    _postalCodeCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Set<String> _favoritePartnerIdsFromAnyMap(Map<String, dynamic> source) {
    const keys = <String>[
      'favorite_partner_ids',
      'favoritePartnerIds',
      'favourite_partner_ids',
      'favouritePartnerIds',
    ];
    for (final key in keys) {
      final raw = source[key];
      if (raw is! List) continue;
      final out = <String>{};
      for (final item in raw) {
        final value = item.toString().trim();
        if (value.isEmpty) continue;
        out.add(value);
      }
      return out;
    }
    return <String>{};
  }

  Future<Map<String, dynamic>?> _fetchFavoritePartnerProfile(
    String partnerId,
  ) async {
    final safePartnerId = partnerId.trim();
    if (safePartnerId.isEmpty) return null;
    try {
      final uri = Uri.parse('$kBookingBaseUrl/partners/profile').replace(
        queryParameters: <String, String>{
          'partner_id': safePartnerId,
          'ts': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      final root = _safeMap(decoded);
      final profile = _safeMap(root['profile']);
      if (profile.isEmpty) return null;
      final coverage = _safeMap(profile['coverage']);
      final media = _safeMap(profile['media']);
      final city = _mapTextAny(coverage, const [
        'city',
        'municipality',
        'locality',
        'place',
      ]);
      final postcode = _mapTextAny(coverage, const [
        'postcode',
        'postal_code',
        'postalCode',
        'zip',
        'zip_code',
        'zipCode',
      ]);
      final countryCode = _mapTextAny(coverage, const [
        'country_code',
        'countryCode',
        'country',
      ]);
      return <String, dynamic>{
        'partner_id':
            _mapTextAny(profile, const [
              'partner_id',
              'partnerId',
            ]).trim().isNotEmpty
            ? _mapTextAny(profile, const ['partner_id', 'partnerId']).trim()
            : safePartnerId,
        'company_name': _mapTextAny(profile, const [
          'company_name',
          'companyName',
        ]),
        'is_active':
            profile['is_active'] == true || profile['isActive'] == true,
        'logo_url': _mapTextAny(media, const ['logo_url', 'logoUrl']),
        'hero_photo_url': _mapTextAny(media, const [
          'hero_photo_url',
          'heroPhotoUrl',
        ]),
        'supported_postcodes': coverage['postcodes'] is List
            ? List<dynamic>.from(coverage['postcodes'] as List)
            : const <dynamic>[],
        'region_label': _mapTextAny(coverage, const [
          'region_label',
          'regionLabel',
        ]),
        'city': city,
        'postcode': postcode,
        'country_code': countryCode,
        'services': profile['services'],
        'capabilities': profile['capabilities'],
        'booking_capabilities': profile['booking_capabilities'],
        'airport_service_enabled':
            profile['airport_service_enabled'] ??
            profile['airportServiceEnabled'],
        'airport_transfer_enabled':
            profile['airport_transfer_enabled'] ??
            profile['airportTransferEnabled'],
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshFavoritePartners({required String reason}) async {
    if (!mounted) return;
    setState(() {
      _favoritesLoading = true;
      _favoritesError = null;
    });
    CustomerProfile? resolvedProfile = await widget
        .syncCustomerProfileFromBackend(reason: 'favorite_partners_$reason');
    resolvedProfile ??= await CustomerProfileStore.instance.load();
    final ids = resolvedProfile?.favoritePartnerIds.toSet() ?? <String>{};
    final limitedIds = ids
        .take(_favoritePartnersDisplayLimit)
        .toList(growable: false);
    debugPrint('[FAVORITE_PARTNERS][LOAD] ids=${limitedIds.length}');
    if (limitedIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _favoritePartnerIds = ids;
        _favoritePartnerProfiles = const <Map<String, dynamic>>[];
        _favoritesLoading = false;
        _favoritesError = null;
      });
      return;
    }
    final loaded = await Future.wait(
      limitedIds.map(_fetchFavoritePartnerProfile),
    );
    final okProfiles = loaded.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
    final failCount = loaded.length - okProfiles.length;
    debugPrint('[FAVORITE_PARTNERS][PROFILE_OK] count=${okProfiles.length}');
    debugPrint('[FAVORITE_PARTNERS][PROFILE_FAIL] count=$failCount');
    if (!mounted) return;
    setState(() {
      _favoritePartnerIds = ids;
      _favoritePartnerProfiles = okProfiles;
      _favoritesLoading = false;
      _favoritesError = failCount > 0 && okProfiles.isEmpty
          ? _t(
              nl: 'Sommige favorieten zijn tijdelijk niet beschikbaar.',
              en: 'Some favorites are temporarily unavailable.',
              fr: 'Certains favoris sont temporairement indisponibles.',
              es: 'Algunos favoritos no están disponibles temporalmente.',
            )
          : null;
    });
  }

  Future<void> _searchPartners() async {
    final raw = _postalCodeCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Vul eerst een postcode in.',
              en: 'Enter a postal code first.',
              fr: 'Entrez d abord un code postal.',
              es: 'Introduce primero un codigo postal.',
            ),
          ),
        ),
      );
      return;
    }
    final postcode = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    setState(() {
      _searching = true;
      _searchingByLocation = false;
      _searched = false;
      _lastSearchUsedLocation = false;
      _normalizedPostcode = postcode;
      _locationSearchLabel = '';
      _partners = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/partners/nearby?postcode=${Uri.encodeQueryComponent(postcode)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final partnersRaw =
          decoded is Map<String, dynamic> && decoded['partners'] is List
          ? (decoded['partners'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchingByLocation = false;
        _searched = true;
        _lastSearchUsedLocation = false;
        _locationSearchLabel = '';
        _partners = partnersRaw;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchingByLocation = false;
        _searched = true;
        _lastSearchUsedLocation = false;
        _locationSearchLabel = '';
        _partners = const <Map<String, dynamic>>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Zoeken van partners is momenteel niet beschikbaar.',
              en: 'Partner search is currently unavailable.',
              fr: 'La recherche de partenaires est actuellement indisponible.',
              es: 'La busqueda de socios no esta disponible actualmente.',
            ),
          ),
        ),
      );
    }
  }

  Future<bool> _ensureNearbyLocationPermission() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    return permission != geo.LocationPermission.denied &&
        permission != geo.LocationPermission.deniedForever;
  }

  Future<void> _searchPartnersByCurrentLocation() async {
    final hasPermission = await _ensureNearbyLocationPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Locatietoegang is vereist voor zoeken op afstand.',
              en: 'Location access is required for radius search.',
              fr: 'L’accès à la localisation est requis pour la recherche par rayon.',
              es: 'Se requiere acceso a la ubicación para la búsqueda por radio.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _searching = true;
      _searchingByLocation = true;
      _searched = false;
      _lastSearchUsedLocation = true;
      _normalizedPostcode = '';
      _locationSearchLabel = '';
      _partners = const <Map<String, dynamic>>[];
    });
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      final lat = pos.latitude;
      final lng = pos.longitude;
      final radiusKm = _selectedGpsRadiusKm;
      final uri = Uri.parse(
        '$kBookingBaseUrl/partners/nearby?lat=${Uri.encodeQueryComponent(lat.toStringAsFixed(6))}&lng=${Uri.encodeQueryComponent(lng.toStringAsFixed(6))}&radius_km=$radiusKm',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final partnersRaw =
          decoded is Map<String, dynamic> && decoded['partners'] is List
          ? (decoded['partners'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchingByLocation = false;
        _searched = true;
        _lastSearchUsedLocation = true;
        _locationSearchLabel =
            '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)} • $radiusKm km';
        _partners = partnersRaw;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchingByLocation = false;
        _searched = true;
        _lastSearchUsedLocation = true;
        _locationSearchLabel = '';
        _partners = const <Map<String, dynamic>>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Zoeken op huidige locatie is momenteel niet beschikbaar.',
              en: 'Search by current location is currently unavailable.',
              fr: 'La recherche par position actuelle est momentanément indisponible.',
              es: 'La búsqueda por ubicación actual no está disponible en este momento.',
            ),
          ),
        ),
      );
    }
  }

  Widget _premiumCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDarkTheme ? _gold.withOpacity(0.28) : _border,
        ),
        boxShadow: [
          BoxShadow(
            color: _shadow.withOpacity(_isDarkTheme ? 0.18 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoChip(String label, {IconData? icon, Color? color}) {
    final accent = color ?? _gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: accent),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyStateCard(String text, {Widget? action}) {
    return _premiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(color: _textMuted, fontSize: 13)),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  String _mapText(Map<String, dynamic> p, String key) =>
      (p[key] ?? '').toString().trim();

  String _mapTextAny(Map<String, dynamic> p, List<String> keys) {
    for (final key in keys) {
      final text = _mapText(p, key);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _sanitizePartnerSubtitleText(String input) {
    var text = input;
    text = text.replaceAll('â€¢', '·');
    text = text.replaceAll('Â·', '·');
    text = text.replaceAll('Â ', ' ');
    text = text.replaceAll('Â', '');
    text = text.replaceAll(RegExp(r'\s*[•·]\s*'), ' · ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(RegExp(r'(?:\s*·\s*){2,}'), ' · ');
    text = text.replaceAll(RegExp(r'^(?:·\s*)+|(?:\s*·)+$'), '').trim();
    return text;
  }

  List<String> _locationSubtitleParts(String input) {
    final normalized = _sanitizePartnerSubtitleText(input);
    if (normalized.isEmpty) return const <String>[];
    return normalized
        .split(RegExp(r'\s*·\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  String _fallbackPostalFromLocationParts(List<String> parts) {
    for (final part in parts) {
      if (RegExp(r'\d').hasMatch(part)) return part;
    }
    return '';
  }

  String _favoritePartnerSubtitle(Map<String, dynamic> partner) {
    final city = _sanitizePartnerSubtitleText(
      _mapTextAny(partner, const ['city', 'municipality', 'locality', 'place']),
    );
    var postcode = _sanitizePartnerSubtitleText(
      _mapTextAny(partner, const [
        'postcode',
        'postal_code',
        'postalCode',
        'zip',
        'zip_code',
        'zipCode',
      ]),
    );
    if (postcode.isEmpty) {
      final supportedPostcodes = _mapTextListAny(partner, const [
        'supported_postcodes',
        'supportedPostcodes',
      ]);
      if (supportedPostcodes.isNotEmpty) {
        postcode = _sanitizePartnerSubtitleText(supportedPostcodes.first);
      }
    }
    var country = _sanitizePartnerSubtitleText(
      _mapTextAny(partner, const ['country_code', 'countryCode', 'country']),
    );
    if (country.length == 2) country = country.toUpperCase();
    final fallbackParts = _locationSubtitleParts(
      _mapTextAny(partner, const [
        'region_label',
        'regionLabel',
        'subtitle',
        'location',
        'location_label',
        'locationLabel',
      ]),
    );
    final fallback = fallbackParts.join(' · ');

    if (city.isNotEmpty && postcode.isNotEmpty && country.isNotEmpty) {
      return '$city · $postcode · $country';
    }

    if (fallbackParts.isNotEmpty) {
      final fallbackCity = fallbackParts.isNotEmpty ? fallbackParts.first : '';
      final fallbackCountry = fallbackParts.length >= 3
          ? fallbackParts.last
          : '';
      final fallbackPostcode = _fallbackPostalFromLocationParts(fallbackParts);
      final mergedParts = <String>[
        city.isNotEmpty ? city : fallbackCity,
        postcode.isNotEmpty ? postcode : fallbackPostcode,
        country.isNotEmpty ? country : fallbackCountry,
      ].where((part) => part.trim().isNotEmpty).toList(growable: false);
      if (mergedParts.length == 3) {
        return mergedParts.join(' · ');
      }
      // Prefer a richer sanitized fallback over partial structured output.
      if (fallbackParts.length >= 2) return fallback;
      if (mergedParts.isNotEmpty) return mergedParts.join(' · ');
    }

    final structuredParts = <String>[
      city,
      postcode,
      country,
    ].where((part) => part.trim().isNotEmpty).toList(growable: false);
    if (structuredParts.isNotEmpty) {
      return structuredParts.join(' · ');
    }
    return fallback;
  }

  bool _looksTruthy(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  bool _servicesListIncludesAirport(dynamic value) {
    if (value is! List) return false;
    for (final item in value) {
      final token = item.toString().trim().toLowerCase();
      if (token == 'airport' ||
          token == 'airport_transfer' ||
          token == 'airport_service' ||
          token == 'airportservice') {
        return true;
      }
    }
    return false;
  }

  bool _airportServiceEnabledFromPartner(Map<String, dynamic> source) {
    var hasExplicitSignal = false;
    for (final value in <dynamic>[
      source['airport_service_enabled'],
      source['airportServiceEnabled'],
      source['airport_transfer_enabled'],
      source['airportTransferEnabled'],
    ]) {
      if (value == null) continue;
      hasExplicitSignal = true;
      if (_looksTruthy(value)) return true;
    }

    final capabilities = _safeMap(source['capabilities']);
    for (final value in <dynamic>[
      capabilities['airport'],
      capabilities['airport_transfer'],
      capabilities['airport_service_enabled'],
      capabilities['airportServiceEnabled'],
      capabilities['airport_transfer_enabled'],
      capabilities['airportTransferEnabled'],
    ]) {
      if (value == null) continue;
      hasExplicitSignal = true;
      if (_looksTruthy(value)) return true;
    }

    final bookingCapabilities = _safeMap(source['booking_capabilities']);
    for (final value in <dynamic>[
      bookingCapabilities['airport'],
      bookingCapabilities['airport_transfer'],
      bookingCapabilities['airport_service_enabled'],
      bookingCapabilities['airportServiceEnabled'],
      bookingCapabilities['airport_transfer_enabled'],
      bookingCapabilities['airportTransferEnabled'],
    ]) {
      if (value == null) continue;
      hasExplicitSignal = true;
      if (_looksTruthy(value)) return true;
    }

    final servicesMap = _safeMap(source['services']);
    for (final value in <dynamic>[
      servicesMap['airport'],
      servicesMap['airport_transfer'],
    ]) {
      if (value == null) continue;
      hasExplicitSignal = true;
      if (_looksTruthy(value)) return true;
    }

    if (hasExplicitSignal) return false;
    // Legacy fallback for profiles without explicit capability booleans.
    return _servicesListIncludesAirport(source['services']);
  }

  List<String> _mapTextList(Map<String, dynamic> p, String key) {
    final raw = p[key];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  List<String> _mapTextListAny(Map<String, dynamic> p, List<String> keys) {
    for (final key in keys) {
      final items = _mapTextList(p, key);
      if (items.isNotEmpty) return items;
    }
    return const <String>[];
  }

  double? _mapDoubleAny(Map<String, dynamic> p, List<String> keys) {
    for (final key in keys) {
      final raw = p[key];
      if (raw == null) continue;
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw.toString().trim());
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  bool _isPublicHttpsUrl(String value) {
    final clean = value.trim().toLowerCase();
    return clean.startsWith('https://');
  }

  Future<void> _openPartnerProfile(Map<String, dynamic> p) async {
    final partnerId = _mapTextAny(p, const ['partner_id', 'partnerId']);
    final companyName = _mapTextAny(p, const ['company_name', 'companyName']);
    if (partnerId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartnerPublicProfilePage(
          partnerId: partnerId,
          companyNameFallback: companyName,
          customerHomeBuilder: widget.customerHomeBuilder,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshFavoritePartners(reason: 'after_partner_profile');
  }

  void _openPartnerBooking(Map<String, dynamic> p) {
    if (widget.selectionMode) {
      _selectAirportPartner(p);
      return;
    }
    final partnerId = _mapTextAny(p, const ['partner_id', 'partnerId']);
    if (partnerId.isEmpty) return;
    final companyName = _mapTextAny(p, const ['company_name', 'companyName']);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          persistToCustomerBookings: true,
          onGoToStartPage: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: widget.customerHomeBuilder),
              (route) => false,
            );
          },
          publicPartnerId: partnerId,
          publicPartnerName: companyName,
        ),
      ),
    );
  }

  Map<String, String>? _partnerSelectionResult(Map<String, dynamic> p) {
    final partnerId = _mapTextAny(p, const ['partner_id', 'partnerId']);
    if (partnerId.isEmpty) return null;
    final companyName = _mapTextAny(p, const ['company_name', 'companyName']);
    final companyCode = _mapTextAny(p, const [
      'public_company_code',
      'publicCompanyCode',
      'company_code',
      'companyCode',
    ]);
    return <String, String>{
      'partner_id': partnerId,
      'tenant_id': partnerId,
      'company_id': partnerId,
      'company_name': companyName,
      'company_code': companyCode.isNotEmpty ? companyCode : partnerId,
    };
  }

  void _selectAirportPartner(Map<String, dynamic> partner) {
    final result = _partnerSelectionResult(partner);
    if (result == null) return;
    Navigator.of(context).pop<Map<String, String>>(result);
  }

  Widget _partnerCard(Map<String, dynamic> p) {
    final company = _mapTextAny(p, const ['company_name', 'companyName']);
    final partnerId = _mapTextAny(p, const ['partner_id', 'partnerId']);
    final isActive = p['is_active'] == true || p['isActive'] == true;
    final supported = _mapTextListAny(p, const [
      'supported_postcodes',
      'supportedPostcodes',
    ]);
    final logoCandidate = _mapTextAny(p, const ['logo_url', 'logoUrl']);
    final heroCandidate = _mapTextAny(p, const [
      'hero_photo_url',
      'heroPhotoUrl',
    ]);
    final logoUrl = _isPublicHttpsUrl(logoCandidate) ? logoCandidate : '';
    final heroUrl = _isPublicHttpsUrl(heroCandidate) ? heroCandidate : '';
    final badgeList = _mapTextListAny(p, const [
      'service_badges',
      'serviceBadges',
    ]);
    final distanceKm = _mapDoubleAny(p, const ['distance_km', 'distanceKm']);

    Widget fallbackStrip({double height = 66}) {
      return Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _panel,
              _card,
              _gold.withOpacity(_isDarkTheme ? 0.20 : 0.14),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _gold.withOpacity(_isDarkTheme ? 0.16 : 0.10),
                border: Border.all(
                  color: _gold.withOpacity(_isDarkTheme ? 0.5 : 0.34),
                ),
              ),
              child: Icon(
                Icons.local_taxi_outlined,
                size: 17,
                color: _isDarkTheme ? _gold.withOpacity(0.96) : _bronze,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t(
                  nl: 'Fluxidi partner',
                  en: 'Fluxidi partner',
                  fr: 'Partenaire Fluxidi',
                  es: 'Socio Fluxidi',
                ),
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openPartnerProfile(p),
          borderRadius: BorderRadius.circular(14),
          child: _premiumCard(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: heroUrl.isNotEmpty
                      ? Stack(
                          children: [
                            Image.network(
                              heroUrl,
                              height: 90,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  fallbackStrip(height: 90),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.black.withOpacity(0.12),
                                      Colors.black.withOpacity(0.55),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                            if (logoUrl.isNotEmpty)
                              Positioned(
                                left: 10,
                                bottom: 8,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.black.withOpacity(
                                    0.82,
                                  ),
                                  foregroundImage: NetworkImage(logoUrl),
                                ),
                              ),
                          ],
                        )
                      : logoUrl.isNotEmpty
                      ? Container(
                          height: 90,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _panel,
                                _card,
                                _gold.withOpacity(_isDarkTheme ? 0.20 : 0.14),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Image.network(
                            logoUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                fallbackStrip(height: 90),
                          ),
                        )
                      : fallbackStrip(),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.business_outlined,
                      color: _gold.withOpacity(0.95),
                      size: 18,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        company.isEmpty ? partnerId : company,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isActive)
                      _infoChip(
                        _t(
                          nl: 'Actieve partner',
                          en: 'Active partner',
                          fr: 'Partenaire actif',
                          es: 'Socio activo',
                        ),
                        icon: Icons.verified_outlined,
                        color: const Color(0xFF34D29A),
                      ),
                    if (supported.isNotEmpty)
                      _infoChip(
                        _t(
                          nl: supported.take(4).join(", "),
                          en: supported.take(4).join(", "),
                          fr: supported.take(4).join(", "),
                          es: supported.take(4).join(", "),
                        ),
                        icon: Icons.location_on_outlined,
                      ),
                    if (badgeList.isNotEmpty)
                      _infoChip(
                        _t(
                          nl: '${badgeList.length} services',
                          en: '${badgeList.length} services',
                          fr: '${badgeList.length} services',
                          es: '${badgeList.length} servicios',
                        ),
                        icon: Icons.local_offer_outlined,
                      ),
                    if (distanceKm != null)
                      _infoChip(
                        '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km',
                        icon: Icons.near_me_outlined,
                        color: const Color(0xFF6CCBFF),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _openPartnerBooking(p),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isDarkTheme ? _gold : _bronze,
                          foregroundColor: _isDarkTheme
                              ? Colors.black
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                        child: Text(
                          _t(
                            nl: widget.selectionMode
                                ? 'Selecteer partner'
                                : 'Boek rit',
                            en: widget.selectionMode
                                ? 'Select partner'
                                : 'Book ride',
                            fr: widget.selectionMode
                                ? 'Choisir partenaire'
                                : 'Réserver un trajet',
                            es: widget.selectionMode
                                ? 'Seleccionar socio'
                                : 'Reservar viaje',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _openPartnerProfile(p),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _isDarkTheme
                              ? _gold.withOpacity(0.98)
                              : _bronze,
                          side: BorderSide(
                            color: _isDarkTheme
                                ? _gold.withOpacity(0.34)
                                : _border,
                          ),
                          backgroundColor: _isDarkTheme
                              ? _gold.withOpacity(0.10)
                              : _panel.withOpacity(0.70),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _t(
                                  nl: 'Bekijk profiel',
                                  en: 'View profile',
                                  fr: 'Voir le profil',
                                  es: 'Ver perfil',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: _isDarkTheme
                                  ? _gold.withOpacity(0.98)
                                  : _bronze,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (partnerId.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    '${_t(nl: "Referentie", en: "Reference", fr: "Référence", es: "Referencia")}: $partnerId',
                    style: TextStyle(
                      color: _textMuted.withOpacity(0.72),
                      fontSize: 9.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _favoritePartnerCard(Map<String, dynamic> p, {double? width}) {
    final company = _mapTextAny(p, const ['company_name', 'companyName']);
    final partnerId = _mapTextAny(p, const ['partner_id', 'partnerId']);
    final logoCandidate = _mapTextAny(p, const ['logo_url', 'logoUrl']);
    final logoUrl = _isPublicHttpsUrl(logoCandidate) ? logoCandidate : '';
    final subtitle = _favoritePartnerSubtitle(p);
    return SizedBox(
      width: width,
      child: _premiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _gold.withOpacity(
                    _isDarkTheme ? 0.14 : 0.10,
                  ),
                  foregroundImage: logoUrl.isNotEmpty
                      ? NetworkImage(logoUrl)
                      : null,
                  child: logoUrl.isEmpty
                      ? Icon(
                          Icons.local_taxi_outlined,
                          size: 18,
                          color: _isDarkTheme
                              ? _gold.withOpacity(0.96)
                              : _bronze,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.isEmpty ? partnerId : company,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.8,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(color: _textMuted, fontSize: 11.2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _openPartnerProfile(p),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isDarkTheme
                          ? _gold.withOpacity(0.98)
                          : _bronze,
                      side: BorderSide(
                        color: _isDarkTheme ? _gold.withOpacity(0.34) : _border,
                      ),
                      backgroundColor: _isDarkTheme
                          ? _gold.withOpacity(0.10)
                          : _panel.withOpacity(0.70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    child: Text(
                      _t(
                        nl: 'Bekijk profiel',
                        en: 'View profile',
                        fr: 'Voir le profil',
                        es: 'Ver perfil',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _openPartnerBooking(p),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isDarkTheme ? _gold : _bronze,
                      foregroundColor: _isDarkTheme
                          ? Colors.black
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    child: Text(
                      _t(
                        nl: widget.selectionMode ? 'Selecteer' : 'Boek rit',
                        en: widget.selectionMode ? 'Select' : 'Book ride',
                        fr: widget.selectionMode ? 'Choisir' : 'Réserver',
                        es: widget.selectionMode ? 'Seleccionar' : 'Reservar',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _favoritePartnersSection() {
    final visibleFavoritePartners = widget.selectionMode
        ? _favoritePartnerProfiles
              .where(_airportServiceEnabledFromPartner)
              .toList(growable: false)
        : _favoritePartnerProfiles;
    return _premiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: "Mijn favoriete taxi's",
              en: 'My favorite taxis',
              fr: 'Mes taxis favoris',
              es: 'Mis taxis favoritos',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13.8,
            ),
          ),
          const SizedBox(height: 8),
          if (_favoritesLoading)
            Text(
              _t(
                nl: 'Favorieten laden...',
                en: 'Loading favorites...',
                fr: 'Chargement des favoris...',
                es: 'Cargando favoritos...',
              ),
              style: TextStyle(color: _textMuted, fontSize: 12.3),
            )
          else if (_favoritePartnerIds.isEmpty)
            Text(
              _t(
                nl: 'Nog geen favoriete taxibedrijven. Open een partnerprofiel en tik op Favoriet.',
                en: 'No favorite taxi companies yet. Open a partner profile and tap Favorite.',
                fr: 'Aucune compagnie de taxi favorite pour le moment. Ouvrez un profil partenaire et touchez Favori.',
                es: 'Aún no tienes taxis favoritos. Abre un perfil de socio y toca Favorito.',
              ),
              style: TextStyle(color: _textMuted, fontSize: 12.3),
            )
          else ...[
            if (_favoritesError != null &&
                _favoritesError!.trim().isNotEmpty) ...[
              Text(
                _favoritesError!,
                style: TextStyle(color: _textMuted, fontSize: 11.6),
              ),
              const SizedBox(height: 8),
            ],
            if (visibleFavoritePartners.isEmpty)
              Text(
                widget.selectionMode
                    ? _t(
                        nl: 'Geen luchthaven-geschikte favoriete partners beschikbaar.',
                        en: 'No airport-capable favorite partners available.',
                        fr: 'Aucun partenaire favori compatible aéroport disponible.',
                        es: 'No hay socios favoritos aptos para aeropuerto.',
                      )
                    : _t(
                        nl: 'Favoriete partnerprofielen worden nog bijgewerkt.',
                        en: 'Favorite partner profiles are still being refreshed.',
                        fr: 'Les profils favoris sont encore en cours d’actualisation.',
                        es: 'Los perfiles favoritos todavía se están actualizando.',
                      ),
                style: TextStyle(color: _textMuted, fontSize: 12.1),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final useGrid = constraints.maxWidth >= 720;
                  if (!useGrid) {
                    return Column(
                      children: visibleFavoritePartners
                          .map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: _favoritePartnerCard(p),
                            ),
                          )
                          .toList(growable: false),
                    );
                  }
                  final itemWidth = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: visibleFavoritePartners
                        .map((p) => _favoritePartnerCard(p, width: itemWidth))
                        .toList(growable: false),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visiblePartners = widget.selectionMode
        ? _partners
              .where(_airportServiceEnabledFromPartner)
              .toList(growable: false)
        : _partners;
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, _, __) => ValueListenableBuilder<AppLanguage>(
        valueListenable: appLanguageNotifier,
        builder: (context, _, __) => Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            foregroundColor: _textPrimary,
            surfaceTintColor: Colors.transparent,
            title: Text(
              widget.selectionMode
                  ? _t(
                      nl: 'Kies taxipartner',
                      en: 'Choose taxi partner',
                      fr: 'Choisir un partenaire taxi',
                      es: 'Elige socio de taxi',
                    )
                  : _t(
                      nl: "Taxi's in de buurt",
                      en: 'Taxis nearby',
                      fr: 'Taxis à proximité',
                      es: 'Taxis cercanos',
                    ),
              style: TextStyle(color: _textPrimary),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _premiumCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _gold.withOpacity(0.14),
                          border: Border.all(color: _gold.withOpacity(0.48)),
                        ),
                        child: Icon(
                          Icons.location_searching_outlined,
                          size: 18,
                          color: _gold.withOpacity(0.95),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _t(
                            nl: 'Zoek actieve Fluxidi-partners op postcode of op basis van je huidige locatie.',
                            en: 'Search active Fluxidi partners by postal code or by your current location.',
                            fr: 'Recherchez des partenaires Fluxidi actifs par code postal ou via votre position actuelle.',
                            es: 'Busca socios activos de Fluxidi por código postal o con tu ubicación actual.',
                          ),
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _favoritePartnersSection(),
                const SizedBox(height: 12),
                _premiumCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: _postalCodeCtrl,
                        style: TextStyle(color: _textPrimary, fontSize: 14),
                        cursorColor: _gold,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchPartners(),
                        decoration: InputDecoration(
                          labelText: _t(
                            nl: 'Postcode',
                            en: 'Postal code',
                            fr: 'Code postal',
                            es: 'Código postal',
                          ),
                          labelStyle: TextStyle(
                            color: _isDarkTheme
                                ? _gold.withOpacity(0.84)
                                : _textMuted,
                          ),
                          hintText: _t(
                            nl: 'Bijv. 2000',
                            en: 'e.g. 2000',
                            fr: 'ex. 2000',
                            es: 'p. ej. 2000',
                          ),
                          hintStyle: TextStyle(
                            color: _textMuted.withOpacity(0.72),
                          ),
                          filled: true,
                          fillColor: _panel,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _isDarkTheme
                                  ? _gold.withOpacity(0.28)
                                  : _border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _gold.withOpacity(0.78),
                              width: 1.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _searching ? null : _searchPartners,
                          style: FilledButton.styleFrom(
                            backgroundColor: _isDarkTheme ? _gold : _bronze,
                            foregroundColor: _isDarkTheme
                                ? Colors.black
                                : Colors.white,
                            disabledBackgroundColor:
                                (_isDarkTheme ? _gold : _bronze).withOpacity(
                                  0.45,
                                ),
                            disabledForegroundColor: _isDarkTheme
                                ? Colors.black87
                                : Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _searching
                                  ? _t(
                                      nl: 'Zoeken...',
                                      en: 'Searching...',
                                      fr: 'Recherche...',
                                      es: 'Buscando...',
                                    )
                                  : _t(
                                      nl: 'Zoek actieve partners',
                                      en: 'Search active partners',
                                      fr: 'Rechercher des partenaires actifs',
                                      es: 'Buscar socios activos',
                                    ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _searching
                              ? null
                              : _searchPartnersByCurrentLocation,
                          icon: _searchingByLocation
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location_outlined),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _isDarkTheme
                                ? _gold.withOpacity(0.98)
                                : _bronze,
                            side: BorderSide(
                              color: _isDarkTheme
                                  ? _gold.withOpacity(0.42)
                                  : _border,
                            ),
                            backgroundColor: _panel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          label: Text(
                            _t(
                              nl: 'Gebruik mijn locatie',
                              en: 'Use my location',
                              fr: 'Utiliser ma position',
                              es: 'Usar mi ubicación',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _t(
                            nl: 'Zoekstraal',
                            en: 'Search radius',
                            fr: 'Rayon de recherche',
                            es: 'Radio de búsqueda',
                          ),
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 12.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _gpsRadiusOptionsKm
                            .map((radiusKm) {
                              final selected = _selectedGpsRadiusKm == radiusKm;
                              return ChoiceChip(
                                label: Text('$radiusKm km'),
                                selected: selected,
                                onSelected: _searching
                                    ? null
                                    : (_) => setState(() {
                                        _selectedGpsRadiusKm = radiusKm;
                                      }),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? (_isDarkTheme
                                            ? Colors.black
                                            : Colors.white)
                                      : (_isDarkTheme
                                            ? _gold.withOpacity(0.98)
                                            : _textPrimary),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.6,
                                ),
                                selectedColor: _isDarkTheme ? _gold : _bronze,
                                backgroundColor: _panel,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  side: BorderSide(
                                    color: selected
                                        ? (_isDarkTheme ? _gold : _bronze)
                                        : (_isDarkTheme
                                              ? _gold.withOpacity(0.40)
                                              : _border),
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                              );
                            })
                            .toList(growable: false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                !_searched
                    ? _emptyStateCard(
                        _t(
                          nl: 'Voer je postcode in of gebruik je locatie om te controleren welke partners actief zijn.',
                          en: 'Enter your postal code or use your location to check which partners are active.',
                          fr: 'Saisissez votre code postal ou utilisez votre position pour vérifier quels partenaires sont actifs.',
                          es: 'Ingresa tu código postal o usa tu ubicación para comprobar qué socios están activos.',
                        ),
                      )
                    : visiblePartners.isNotEmpty
                    ? _premiumCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: widget.selectionMode
                                    ? (_lastSearchUsedLocation
                                          ? 'Luchthavenpartners in de buurt van je locatie'
                                          : 'Luchthavenpartners in $_normalizedPostcode')
                                    : (_lastSearchUsedLocation
                                          ? 'Actieve partners in de buurt van je locatie'
                                          : 'Actieve partners in $_normalizedPostcode'),
                                en: widget.selectionMode
                                    ? (_lastSearchUsedLocation
                                          ? 'Airport-capable partners near your location'
                                          : 'Airport-capable partners in $_normalizedPostcode')
                                    : (_lastSearchUsedLocation
                                          ? 'Active partners near your location'
                                          : 'Active partners in $_normalizedPostcode'),
                                fr: widget.selectionMode
                                    ? (_lastSearchUsedLocation
                                          ? 'Partenaires aéroport près de votre position'
                                          : 'Partenaires aéroport dans $_normalizedPostcode')
                                    : (_lastSearchUsedLocation
                                          ? 'Partenaires actifs à proximité de votre position'
                                          : 'Partenaires actifs dans $_normalizedPostcode'),
                                es: widget.selectionMode
                                    ? (_lastSearchUsedLocation
                                          ? 'Socios aptos para aeropuerto cerca de tu ubicación'
                                          : 'Socios aptos para aeropuerto en $_normalizedPostcode')
                                    : (_lastSearchUsedLocation
                                          ? 'Socios activos cerca de tu ubicación'
                                          : 'Socios activos en $_normalizedPostcode'),
                              ),
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            if (_lastSearchUsedLocation &&
                                _locationSearchLabel.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _locationSearchLabel,
                                style: TextStyle(
                                  color: _textMuted.withOpacity(0.9),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            ...visiblePartners.map(_partnerCard),
                          ],
                        ),
                      )
                    : _emptyStateCard(
                        _t(
                          nl: widget.selectionMode
                              ? (_lastSearchUsedLocation
                                    ? 'Geen luchthavenpartners gevonden voor je huidige locatie.'
                                    : 'Geen luchthavenpartners gevonden voor $_normalizedPostcode.')
                              : (_lastSearchUsedLocation
                                    ? 'Geen partners gevonden voor je huidige locatie of servicegebied.'
                                    : 'Geen partners gevonden voor postcode of servicegebied $_normalizedPostcode.'),
                          en: widget.selectionMode
                              ? (_lastSearchUsedLocation
                                    ? 'No airport-capable partners found for your current location.'
                                    : 'No airport-capable partners found for $_normalizedPostcode.')
                              : (_lastSearchUsedLocation
                                    ? 'No partners found for your current location or service area.'
                                    : 'No partners found for postcode or service area $_normalizedPostcode.'),
                          fr: widget.selectionMode
                              ? (_lastSearchUsedLocation
                                    ? 'Aucun partenaire compatible aéroport trouvé pour votre position actuelle.'
                                    : 'Aucun partenaire compatible aéroport trouvé pour $_normalizedPostcode.')
                              : (_lastSearchUsedLocation
                                    ? 'Aucun partenaire trouvé pour votre position actuelle ou zone de service.'
                                    : 'Aucun partenaire trouvé pour le code postal ou la zone de service $_normalizedPostcode.'),
                          es: widget.selectionMode
                              ? (_lastSearchUsedLocation
                                    ? 'No se encontraron socios aptos para aeropuerto para tu ubicación actual.'
                                    : 'No se encontraron socios aptos para aeropuerto para $_normalizedPostcode.')
                              : (_lastSearchUsedLocation
                                    ? 'No se encontraron socios para tu ubicación actual o zona de servicio.'
                                    : 'No se encontraron socios para el código postal o zona de servicio $_normalizedPostcode.'),
                        ),
                        action: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: widget.regionRegistrationBuilder,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _isDarkTheme
                                ? _gold.withOpacity(0.97)
                                : _bronze,
                            side: BorderSide(
                              color: _isDarkTheme
                                  ? _gold.withOpacity(0.45)
                                  : _border,
                            ),
                            backgroundColor: _panel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            _t(
                              nl: 'Open Regio Radar',
                              en: 'Open Region Radar',
                              fr: 'Ouvrir Radar régional',
                              es: 'Abrir Radar regional',
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
