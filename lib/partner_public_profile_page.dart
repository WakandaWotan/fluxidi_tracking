import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'app_strings.dart';
import 'airport/airport_page.dart';
import 'calculator_page.dart';
import 'customer_profile_store.dart';
import 'customer_session_store.dart';
import 'customer_theme_palette.dart';
import 'customer_theme_store.dart';
import 'payment/payment_method_catalog.dart';
import 'payment/payment_method_logo.dart';
import 'payment/payment_method_resolver.dart';

class PartnerPublicProfilePage extends StatefulWidget {
  final String partnerId;
  final String companyNameFallback;
  final WidgetBuilder customerHomeBuilder;

  const PartnerPublicProfilePage({
    super.key,
    required this.partnerId,
    required this.companyNameFallback,
    required this.customerHomeBuilder,
  });

  @override
  State<PartnerPublicProfilePage> createState() =>
      _PartnerPublicProfilePageState();
}

class _PartnerPublicProfilePageState extends State<PartnerPublicProfilePage> {
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _themePalette.isDark;
  Color get _bg => _themePalette.background;
  Color get _card => _themePalette.surface;
  Color get _gold => _themePalette.gold;
  Color get _bronze => _themePalette.bronze;
  Color get _textPrimary => _themePalette.textPrimary;
  Color get _textMuted => _themePalette.textMuted;
  Color get _surfaceAlt => _themePalette.surfaceAlt;
  Color get _border => _themePalette.border;
  Color get _shadow => _themePalette.shadow;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  bool _showAllCoveragePostcodes = false;
  Set<String> _favoritePartnerIds = <String>{};
  bool _favoriteBusy = false;

  bool get _isFavorite {
    final partnerId = widget.partnerId.trim();
    if (partnerId.isEmpty) return false;
    return _favoritePartnerIds.contains(partnerId);
  }

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
    _load();
    unawaited(_loadFavoritePartnerIds());
  }

  Future<void> _loadFavoritePartnerIds() async {
    try {
      final profile = await CustomerProfileStore.instance.load();
      if (!mounted) return;
      setState(() {
        _favoritePartnerIds = profile?.favoritePartnerIds.toSet() ?? <String>{};
      });
    } catch (_) {
      // Keep profile view resilient when local customer profile is unavailable.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$kBookingBaseUrl/partners/profile').replace(
        queryParameters: <String, String>{
          'partner_id': widget.partnerId.trim(),
          'ts': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final root = _profileMap(decoded);
      final p = _profileMap(root['profile']);
      if (p.isEmpty) throw Exception('invalid_profile_payload');
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          nl: 'Publiek partnerprofiel is momenteel niet beschikbaar.',
          en: 'Public partner profile is currently unavailable.',
          fr: 'Le profil public du partenaire est actuellement indisponible.',
          es: 'El perfil publico del socio no esta disponible actualmente.',
        );
      });
    }
  }

  Set<String> _favoritePartnerIdsFromAnyMap(Map<String, dynamic> source) {
    final candidates = <dynamic>[
      source['favorite_partner_ids'],
      source['favoritePartnerIds'],
      source['favourite_partner_ids'],
      source['favouritePartnerIds'],
    ];
    for (final candidate in candidates) {
      if (candidate is! List) continue;
      final out = <String>{};
      for (final item in candidate) {
        final value = item.toString().trim();
        if (value.isEmpty) continue;
        out.add(value);
      }
      return out;
    }
    return <String>{};
  }

  Future<void> _toggleFavoritePartner() async {
    final partnerId = widget.partnerId.trim();
    if (partnerId.isEmpty || _favoriteBusy) return;

    final nextFavorites = _favoritePartnerIds.toSet();
    if (nextFavorites.contains(partnerId)) {
      nextFavorites.remove(partnerId);
    } else {
      nextFavorites.add(partnerId);
    }

    if (!mounted) return;
    setState(() {
      _favoriteBusy = true;
      _favoritePartnerIds = nextFavorites;
    });

    var localSaved = false;
    var remoteSaved = false;
    var hasValidSession = false;
    try {
      final session = await CustomerSessionStore.instance.loadValidSession();
      final sessionToken = (session?.customerSessionToken ?? '').trim();
      hasValidSession = session != null && sessionToken.isNotEmpty;
      debugPrint(
        '[FAVORITE_SYNC][REQUEST] requested_count=${nextFavorites.length} session=$hasValidSession',
      );

      final existingProfile = await CustomerProfileStore.instance.load();
      final sessionCustomerId = hasValidSession
          ? session.customerId.trim()
          : '';
      final savedProfile = await CustomerProfileStore.instance.save(
        name: existingProfile?.name ?? '',
        phone: existingProfile?.phone ?? '',
        email: existingProfile?.email ?? '',
        preferredPostcode: existingProfile?.preferredPostcode ?? '',
        companyName: existingProfile?.companyName ?? '',
        vatNumber: existingProfile?.vatNumber ?? '',
        sessionCustomerId: sessionCustomerId.isNotEmpty
            ? sessionCustomerId
            : null,
        favoritePartnerIds: nextFavorites,
      );
      localSaved = true;
      if (mounted) {
        setState(() {
          _favoritePartnerIds = savedProfile.favoritePartnerIds.toSet();
        });
      }

      if (hasValidSession) {
        final remoteProfile = await upsertPublicCustomerProfile(
          customerSessionToken: sessionToken,
          payload: <String, dynamic>{
            'name': savedProfile.name,
            'phone': savedProfile.phone,
            'email': savedProfile.email,
            'preferred_postcode': savedProfile.preferredPostcode,
            'company_name': savedProfile.companyName,
            'vat_number': savedProfile.vatNumber,
            'favorite_partner_ids': savedProfile.favoritePartnerIds,
            'favoritePartnerIds': savedProfile.favoritePartnerIds,
          },
        );
        if (remoteProfile != null) {
          final remoteFavorites = _favoritePartnerIdsFromAnyMap(remoteProfile);
          final remoteFavoriteKeys = remoteProfile.keys
              .where(
                (k) =>
                    k == 'favorite_partner_ids' ||
                    k == 'favoritePartnerIds' ||
                    k == 'favourite_partner_ids' ||
                    k == 'favouritePartnerIds',
              )
              .toList(growable: false);
          remoteSaved =
              remoteFavorites.length == nextFavorites.length &&
              remoteFavorites.containsAll(nextFavorites) &&
              nextFavorites.containsAll(remoteFavorites);
          debugPrint(
            '[FAVORITE_SYNC][RESPONSE] remote_count=${remoteFavorites.length} matched=$remoteSaved keys=${remoteFavoriteKeys.join(",")}',
          );
          if (remoteFavoriteKeys.isEmpty) {
            debugPrint('[FAVORITE_SYNC][NO_FAVORITE_KEYS]');
          }
        }
      }
    } catch (_) {
      // Local persistence already handled best-effort above.
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }

    if (!mounted || !localSaved) return;

    if (!hasValidSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Favoriet bewaard op deze gsm. Log in met gsm om je favorieten ook online te bewaren.',
              en: 'Favorite saved on this phone. Log in with your phone to keep your favorites online too.',
              fr: 'Favori enregistré sur ce gsm. Connectez-vous avec votre gsm pour conserver vos favoris en ligne.',
              es: 'Favorito guardado en este móvil. Inicia sesión con tu móvil para conservar tus favoritos en línea.',
            ),
          ),
        ),
      );
      return;
    }
    if (!remoteSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Favoriet lokaal bewaard. Synchronisatie volgt later.',
              en: 'Favorite saved locally. Sync will follow later.',
              fr: 'Favori enregistré localement. La synchronisation suivra plus tard.',
              es: 'Favorito guardado localmente. La sincronización llegará más tarde.',
            ),
          ),
        ),
      );
    }
  }

  void _openPartnerBooking({required String companyName}) {
    final partnerId = widget.partnerId.trim();
    if (partnerId.isEmpty) return;
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

  void _openPartnerAirportBooking({required String companyName}) {
    final partnerId = widget.partnerId.trim();
    if (partnerId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AirportPage(
          bookingBaseUrl: kBookingBaseUrl,
          selectedTenantId: partnerId,
          selectedCompanyId: partnerId,
          selectedCompanyCode: partnerId,
          selectedCompanyName: companyName,
          selectedPartnerId: partnerId,
        ),
      ),
    );
  }

  Map<String, dynamic> _profileMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _profileMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList(growable: false);
    }
    return <Map<String, dynamic>>[];
  }

  String _profileTextAny(dynamic source, List<String> keys) {
    final map = _profileMap(source);
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _sanitizeLocationDisplayText(String input) {
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

  String _profileHttpsUrl(dynamic source, List<String> keys) {
    final text = _profileTextAny(source, keys);
    if (text.toLowerCase().startsWith('https://')) return text;
    return '';
  }

  List<String> _profileTextListAny(dynamic source, List<String> keys) {
    final map = _profileMap(source);
    for (final key in keys) {
      final raw = map[key];
      if (raw is! List) continue;
      final out = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (out.isNotEmpty) return out;
    }
    return const <String>[];
  }

  bool _looksTruthy(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  bool _isAirportServiceToken(String token) {
    final normalized = token.trim().toLowerCase();
    return normalized == 'airport' ||
        normalized == 'airport_transfer' ||
        normalized == 'airport_service' ||
        normalized == 'airportservice';
  }

  bool _airportServiceEnabledFromProfile(Map<String, dynamic> profile) {
    var hasExplicitSignal = false;
    for (final value in <dynamic>[
      profile['airport_service_enabled'],
      profile['airportServiceEnabled'],
      profile['airport_transfer_enabled'],
      profile['airportTransferEnabled'],
    ]) {
      if (value == null) continue;
      hasExplicitSignal = true;
      if (_looksTruthy(value)) return true;
    }

    final capabilities = _profileMap(profile['capabilities']);
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

    final bookingCapabilities = _profileMap(profile['booking_capabilities']);
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

    final servicesMap = _profileMap(profile['services']);
    for (final value in <dynamic>[
      servicesMap['airport'],
      servicesMap['airport_transfer'],
    ]) {
      if (value == null) continue;
      hasExplicitSignal = true;
      if (_looksTruthy(value)) return true;
    }

    if (hasExplicitSignal) return false;

    // Legacy fallback for older published profiles that have no explicit
    // capability booleans yet. Any explicit false/true signal above wins.
    final servicesList = _profileTextListAny(profile, const ['services']);
    return servicesList.any(_isAirportServiceToken);
  }

  double? _asDoubleRating(dynamic value) {
    if (value is num) {
      final candidate = value.toDouble();
      return candidate.isFinite ? candidate : null;
    }
    final parsed = double.tryParse((value ?? '').toString().trim());
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  int? _asIntCount(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString().trim());
  }

  double? _ratingAverageFromMap(Map item) {
    final candidates = <dynamic>[
      item['rating_avg'],
      item['ratingAvg'],
      item['average_rating'],
      item['averageRating'],
      item['driver_rating_avg'],
      item['driverRatingAvg'],
    ];
    for (final value in candidates) {
      final parsed = _asDoubleRating(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _ratingCountFromMap(Map item) {
    final candidates = <dynamic>[
      item['rating_count'],
      item['ratingCount'],
      item['reviews_count'],
      item['reviewsCount'],
      item['driver_rating_count'],
      item['driverRatingCount'],
    ];
    for (final value in candidates) {
      final parsed = _asIntCount(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _localizedRatingDisplay({required double? avg, required int? count}) {
    final safeCount = count == null ? 0 : (count < 0 ? 0 : count);
    if (avg != null && safeCount > 0) {
      final rounded = avg.toStringAsFixed(1);
      final value = (appConfig.currentLanguage == AppLanguage.en)
          ? rounded
          : rounded.replaceAll('.', ',');
      final reviewWord = _t(
        nl: safeCount == 1 ? 'beoordeling' : 'beoordelingen',
        en: safeCount == 1 ? 'review' : 'reviews',
        fr: safeCount == 1 ? 'avis' : 'avis',
        es: safeCount == 1 ? 'reseña' : 'reseñas',
      );
      return '★ $value · $safeCount $reviewWord';
    }
    return _t(
      nl: '★ Nog geen score',
      en: '★ No rating yet',
      fr: '★ Pas encore de note',
      es: '★ Sin puntuación todavía',
    );
  }

  String _publicProfileLabel(String key) {
    switch (key) {
      case 'profile':
        return _t(
          nl: 'Partnerprofiel',
          en: 'Partner profile',
          fr: 'Profil partenaire',
          es: 'Perfil del socio',
        );
      case 'reference':
        return _t(
          nl: 'Referentie',
          en: 'Reference',
          fr: 'Référence',
          es: 'Referencia',
        );
      case 'about':
        return _t(
          nl: 'Over deze partner',
          en: 'About this partner',
          fr: 'À propos de ce partenaire',
          es: 'Sobre este socio',
        );
      case 'vehicles':
        return _t(
          nl: 'Voertuigen',
          en: 'Vehicles',
          fr: 'Véhicules',
          es: 'Vehículos',
        );
      case 'drivers':
        return _t(
          nl: 'Chauffeurs',
          en: 'Drivers',
          fr: 'Chauffeurs',
          es: 'Conductores',
        );
      case 'coverage':
        return _t(
          nl: 'Bereikbaarheid & details',
          en: 'Coverage & details',
          fr: 'Zone desservie & détails',
          es: 'Cobertura y detalles',
        );
      case 'region':
        return _t(nl: 'Regio', en: 'Region', fr: 'Région', es: 'Región');
      case 'website':
        return _t(
          nl: 'Website',
          en: 'Website',
          fr: 'Site web',
          es: 'Sitio web',
        );
      case 'phone':
        return _t(nl: 'Telefoon', en: 'Phone', fr: 'Téléphone', es: 'Teléfono');
      case 'booking_email':
        return _t(
          nl: 'Boeking e-mail',
          en: 'Booking email',
          fr: 'E-mail de réservation',
          es: 'Correo de reservas',
        );
      case 'passengers':
        return _t(
          nl: 'Passagiers',
          en: 'Passengers',
          fr: 'Passagers',
          es: 'Pasajeros',
        );
      case 'luggage':
        return _t(nl: 'Bagage', en: 'Luggage', fr: 'Bagages', es: 'Equipaje');
      case 'public_vehicle':
        return _t(
          nl: 'Publiek voertuigprofiel',
          en: 'Public vehicle profile',
          fr: 'Profil véhicule public',
          es: 'Perfil público de vehículo',
        );
      case 'public_partner':
        return _t(
          nl: 'Fluxidi partner',
          en: 'Fluxidi partner',
          fr: 'Partenaire Fluxidi',
          es: 'Socio Fluxidi',
        );
      default:
        return key;
    }
  }

  String _localizePublicDefaultText(String value) {
    final normalized = value.trim().toLowerCase();
    const aboutShortDefaults = <String>{
      'betrouwbare ritten voor particulieren en bedrijven.',
      'reliable rides for private and business customers.',
      'trayectos fiables para particulares y empresas.',
      'des trajets fiables pour particuliers et entreprises.',
    };
    const aboutLongDefaults = <String>{
      'dit publiek profiel bevat enkel veilige bedrijfsinformatie. gevoelige interne gegevens worden niet gepubliceerd.',
      'dit publieke profiel bevat enkel veilige bedrijfsinformatie. gevoelige interne gegevens worden niet gepubliceerd.',
      'this public profile only contains safe company information. sensitive internal data is not published.',
      'este perfil público solo contiene información empresarial segura. los datos internos sensibles no se publican.',
      'ce profil public contient uniquement des informations d’entreprise sûres. les données internes sensibles ne sont pas publiées.',
      "ce profil public contient uniquement des informations d'entreprise sures. les donnees internes sensibles ne sont pas publiees.",
    };
    if (aboutShortDefaults.contains(normalized)) {
      return _t(
        nl: 'Betrouwbare ritten voor particulieren en bedrijven.',
        en: 'Reliable rides for private and business customers.',
        fr: 'Des trajets fiables pour particuliers et entreprises.',
        es: 'Trayectos fiables para particulares y empresas.',
      );
    }
    if (aboutLongDefaults.contains(normalized)) {
      return _t(
        nl: 'Dit publiek profiel bevat enkel veilige bedrijfsinformatie. Gevoelige interne gegevens worden niet gepubliceerd.',
        en: 'This public profile only contains safe company information. Sensitive internal data is not published.',
        fr: 'Ce profil public contient uniquement des informations professionnelles sûres. Les données internes sensibles ne sont pas publiées.',
        es: 'Este perfil público solo contiene información segura de la empresa. Los datos internos sensibles no se publican.',
      );
    }
    return value;
  }

  String _localizePublicDefaultTagline(String value) {
    final normalized = value.trim().toLowerCase();
    const defaults = <String>{
      'premium mobiliteit in jouw regio',
      'premium mobility in your region',
      'mobilité premium dans votre région',
      'movilidad premium en tu región',
    };
    if (!defaults.contains(normalized)) return value;
    return _t(
      nl: 'Premium mobiliteit in jouw regio',
      en: 'Premium mobility in your region',
      fr: 'Mobilité premium dans votre région',
      es: 'Movilidad premium en tu región',
    );
  }

  String _verifiedPartnerTrustLabel() {
    return _t(
      nl: 'Geverifieerde Fluxidi-partner',
      en: 'Verified Fluxidi partner',
      fr: 'Partenaire Fluxidi vérifié',
      es: 'Socio Fluxidi verificado',
    );
  }

  String _friendlyPartnerAboutFallback() {
    return _t(
      nl: 'Betrouwbare ritten voor particulieren, bedrijven en geplande verplaatsingen in jouw regio.',
      en: 'Reliable rides for private customers, businesses and planned trips in your region.',
      fr: 'Des trajets fiables pour particuliers, entreprises et déplacements planifiés dans votre région.',
      es: 'Viajes fiables para particulares, empresas y traslados planificados en tu región.',
    );
  }

  bool _isTechnicalDefaultAbout(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    const technicalDefaults = <String>{
      'dit publiek profiel bevat enkel veilige bedrijfsinformatie. gevoelige interne gegevens worden niet gepubliceerd.',
      'dit publieke profiel bevat enkel veilige bedrijfsinformatie. gevoelige interne gegevens worden niet gepubliceerd.',
      'this public profile only contains safe company information. sensitive internal data is not published.',
      'ce profil public contient uniquement des informations professionnelles sûres. les données internes sensibles ne sont pas publiées.',
      'ce profil public contient uniquement des informations d’entreprise sûres. les données internes sensibles ne sont pas publiées.',
      "ce profil public contient uniquement des informations d'entreprise sures. les donnees internes sensibles ne sont pas publiees.",
      'este perfil público solo contiene información segura de la empresa. los datos internos sensibles no se publican.',
      'este perfil público solo contiene información empresarial segura. los datos internos sensibles no se publican.',
    };
    return technicalDefaults.contains(normalized);
  }

  String _resolvedAboutCopy({
    required String aboutShort,
    required String aboutLong,
  }) {
    final shortText = aboutShort.trim();
    final longText = aboutLong.trim();
    if (shortText.isNotEmpty && !_isTechnicalDefaultAbout(shortText)) {
      return shortText;
    }
    if (longText.isNotEmpty && !_isTechnicalDefaultAbout(longText)) {
      return longText;
    }
    return _friendlyPartnerAboutFallback();
  }

  Future<void> _launchWebsiteUrl(String website) async {
    final text = website.trim();
    if (text.isEmpty) return;
    final prefixed = text.toLowerCase().startsWith('http')
        ? text
        : 'https://$text';
    final uri = Uri.tryParse(prefixed);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchPublicPhone(String phone) async {
    final text = phone.trim();
    if (text.isEmpty) return;
    final uri = Uri.parse('tel:${Uri.encodeComponent(text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchBookingEmail(String email) async {
    final text = email.trim();
    if (text.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: text);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _contactActionButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onPressed,
  }) {
    return FilledButton.tonalIcon(
      onPressed: () => unawaited(onPressed()),
      style: FilledButton.styleFrom(
        backgroundColor: _surfaceAlt,
        foregroundColor: _isDarkTheme ? _textPrimary : _textPrimary,
        side: BorderSide(
          color: _isDarkTheme ? _gold.withOpacity(0.26) : _border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      ),
      icon: Icon(
        icon,
        size: 16,
        color: _isDarkTheme ? _gold.withOpacity(0.95) : _bronze,
      ),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _localizeVehicleName(String value) {
    if (value.trim().toLowerCase() != 'hoofdwagen') return value;
    return _t(
      nl: 'Hoofdwagen',
      en: 'Main vehicle',
      fr: 'Véhicule principal',
      es: 'Vehículo principal',
    );
  }

  String _featureLabel(String id) => _serviceLabel(id);

  String _badgeLabel(String id) => _serviceLabel(id);

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _isDarkTheme ? _gold.withOpacity(0.24) : _border,
        ),
        boxShadow: [
          BoxShadow(
            color: _shadow.withOpacity(_isDarkTheme ? 0.14 : 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _isDarkTheme ? _gold.withOpacity(0.95) : _bronze,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  Widget _chip(String text, {IconData? icon, Color? color, Widget? leading}) {
    final accent = color ?? (_isDarkTheme ? _gold : _bronze);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(_isDarkTheme ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withOpacity(_isDarkTheme ? 0.45 : 0.34),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: accent),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _serviceLabel(String id) {
    switch (id) {
      case 'taxi_vvb':
        return _t(
          nl: 'Taxi & VVB',
          en: 'Taxi & VVB',
          fr: 'Taxi & VVB',
          es: 'Taxi y VVB',
        );
      case 'airport_transfer':
        return _t(
          nl: 'Luchthavenvervoer',
          en: 'Airport transfer',
          fr: 'Transfert aéroport',
          es: 'Traslado aeropuerto',
        );
      case 'business_rides':
        return _t(
          nl: 'Zakelijke ritten',
          en: 'Business rides',
          fr: 'Trajets professionnels',
          es: 'Viajes de negocios',
        );
      case 'hotel_bnb_pickup':
        return _t(
          nl: 'Hotels & B&B',
          en: 'Hotels & B&B',
          fr: 'Hôtels & B&B',
          es: 'Hoteles y B&B',
        );
      case 'event_mobility':
        return _t(
          nl: 'Evenementen',
          en: 'Event mobility',
          fr: 'Événements',
          es: 'Eventos',
        );
      case 'ev_available':
        return _t(
          nl: 'Elektrisch vervoer',
          en: 'Electric vehicle',
          fr: 'Véhicule électrique',
          es: 'Vehículo eléctrico',
        );
      case 'online_payments':
        return _t(
          nl: 'Online betalen',
          en: 'Online payments',
          fr: 'Paiement en ligne',
          es: 'Pagos en línea',
        );
      case 'comfort':
        return _t(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
      case 'verified_professional':
        return _t(
          nl: 'Geverifieerde professional',
          en: 'Verified professional',
          fr: 'Professionnel vérifié',
          es: 'Profesional verificado',
        );
      default:
        return id.replaceAll('_', ' ');
    }
  }

  String _paymentLabel(String id) {
    switch (_normalizePublicPaymentMethodId(id)) {
      case 'cash':
        return _t(nl: 'Cash', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'qr_code':
        return _t(nl: 'QR-code', en: 'QR code', fr: 'Code QR', es: 'Código QR');
      case 'bancontact':
        return 'Bancontact';
      case 'payconiq_wero':
        return 'Payconiq / Wero';
      case 'ideal':
        return 'iDEAL';
      case 'cartes_bancaires':
        return 'Carte Bancaire / CB';
      case 'bizum':
        return 'Bizum';
      case 'card_payment':
        return _t(
          nl: 'Kaartbetaling',
          en: 'Card payment',
          fr: 'Paiement par carte',
          es: 'Pago con tarjeta',
        );
      case 'apple_pay':
        return 'Apple Pay';
      case 'google_pay':
        return 'Google Pay';
      case 'paypal':
        return 'PayPal';
      case 'online_payment':
        return _t(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago online',
        );
      case 'bank_transfer_bacs':
        return _t(
          nl: 'Bankoverschrijving',
          en: 'Bank transfer',
          fr: 'Virement bancaire',
          es: 'Transferencia bancaria',
        );
      default:
        return _serviceLabel(id);
    }
  }

  String _normalizePublicPaymentMethodId(String id) =>
      normalizePaymentMethodId(id);

  String _partnerCountryCodeForPaymentResolver(Map<String, dynamic> profile) {
    final explicit = normalizeCountryCode(
      _profileTextAny(profile, const [
        'country',
        'country_code',
        'countryCode',
      ]),
    );
    if (explicit.isNotEmpty &&
        PaymentCountryCodes.supported.contains(explicit)) {
      return explicit == PaymentCountryCodes.unitedKingdom
          ? PaymentCountryCodes.greatBritain
          : explicit;
    }
    final coverage = _profileMap(profile['coverage']);
    final fromCoverage = normalizeCountryCode(
      _profileTextAny(coverage, const [
        'country',
        'country_code',
        'countryCode',
      ]),
    );
    if (fromCoverage.isNotEmpty &&
        PaymentCountryCodes.supported.contains(fromCoverage)) {
      return fromCoverage == PaymentCountryCodes.unitedKingdom
          ? PaymentCountryCodes.greatBritain
          : fromCoverage;
    }
    final postcodes = <String>[
      ..._profileTextListAny(coverage, const ['postcodes']),
      _profileTextAny(coverage, const ['primary_postcode', 'primaryPostcode']),
    ];
    final inferred = _inferCountryCodeFromPostcodeTokens(postcodes);
    if (inferred.isNotEmpty) return inferred;
    return PaymentCountryCodes.belgium;
  }

  String _inferCountryCodeFromPostcodeTokens(Iterable<String> postcodes) {
    for (final raw in postcodes) {
      final token = raw.trim().toUpperCase().replaceAll(' ', '');
      if (token.isEmpty) continue;
      if (RegExp(r'^\d{4}[A-Z]{2}$').hasMatch(token)) {
        return PaymentCountryCodes.netherlands;
      }
      if (RegExp(r'^[A-Z]{1,2}\d').hasMatch(token)) {
        return PaymentCountryCodes.greatBritain;
      }
    }
    return '';
  }

  List<String> _resolvedPublicPaymentMethods(
    List<String> methods,
    String countryCode,
  ) {
    final known = filterPublicPartnerPaymentOptionIds(methods);
    if (known.isEmpty) return const <String>[];
    return PaymentMethodResolver.reorderByCountryProfile(
      countryCode: countryCode,
      candidateIds: known,
    );
  }

  Widget _paymentOptionLogoTile({
    required String paymentId,
    required String semanticLabel,
  }) {
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        label: semanticLabel,
        button: false,
        child: Container(
          width: 72,
          height: 64,
          decoration: BoxDecoration(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _isDarkTheme ? _gold.withOpacity(0.32) : _border,
            ),
            boxShadow: [
              BoxShadow(
                color: _shadow.withOpacity(_isDarkTheme ? 0.28 : 0.12),
                blurRadius: 9,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: buildPaymentMethodLogo(
            methodId: paymentId,
            fallbackIconColor: _gold.withOpacity(0.95),
            plateWidth: 60,
            plateHeight: 46,
            imageMaxWidth: 52,
            imageMaxHeight: 38,
            fallbackIconSize: 28,
            plateBorderRadius: 9,
            platePadding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentOptionLogoWrap(List<String> paymentIds) {
    return Wrap(
      spacing: 11,
      runSpacing: 11,
      children: paymentIds
          .map(
            (m) => _paymentOptionLogoTile(
              paymentId: _normalizePublicPaymentMethodId(m),
              semanticLabel: _paymentLabel(m),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _paymentOptionsWithMollieBadgeSection(List<String> paymentMethods) {
    final lastMollieIdx = lastMollieCheckoutMethodIndex(paymentMethods);
    final leadingIds = lastMollieIdx == null
        ? paymentMethods
        : paymentMethods.sublist(0, lastMollieIdx + 1);
    final trailingIds = lastMollieIdx == null
        ? const <String>[]
        : paymentMethods.sublist(lastMollieIdx + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paymentOptionLogoWrap(leadingIds),
        if (lastMollieIdx != null) ...[
          const SizedBox(height: 10),
          buildPaymentsByMollieTrustBadge(isDarkSurface: _isDarkTheme),
        ],
        if (trailingIds.isNotEmpty) ...[
          const SizedBox(height: 11),
          _paymentOptionLogoWrap(trailingIds),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profileMap(_profile);
    final companyRatingAvg = _ratingAverageFromMap(p);
    final companyRatingCount = _ratingCountFromMap(p);
    final hasCompanyRating =
        companyRatingAvg != null && (companyRatingCount ?? 0) > 0;
    final companyRatingLabel = _localizedRatingDisplay(
      avg: companyRatingAvg,
      count: companyRatingCount,
    );
    final companyName =
        _profileTextAny(p, const ['company_name', 'companyName']).isNotEmpty
        ? _profileTextAny(p, const ['company_name', 'companyName'])
        : widget.companyNameFallback;
    final tagline = _localizePublicDefaultTagline(
      _profileTextAny(p, const ['tagline']),
    );
    final aboutShort = _localizePublicDefaultText(
      _profileTextAny(p, const ['about_short', 'aboutShort']),
    );
    final aboutLong = _localizePublicDefaultText(
      _profileTextAny(p, const ['about_long', 'aboutLong']),
    );
    final coverage = _profileMap(p['coverage']);
    final regionLabel = _sanitizeLocationDisplayText(
      _profileTextAny(coverage, const ['region_label', 'regionLabel']),
    );
    final postcodes = _profileTextListAny(coverage, const ['postcodes']);
    final contact = _profileMap(p['public_contact']);
    final website = _profileTextAny(contact, const ['website']);
    final publicPhone = _profileTextAny(contact, const [
      'public_phone',
      'publicPhone',
    ]);
    final bookingEmail = _profileTextAny(contact, const [
      'booking_email',
      'bookingEmail',
    ]);
    final media = _profileMap(p['media']);
    final logoUrl = _profileHttpsUrl(media, const ['logo_url', 'logoUrl']);
    final heroPhotoUrl = _profileHttpsUrl(media, const [
      'hero_photo_url',
      'heroPhotoUrl',
    ]);
    final gallery = _profileTextListAny(media, const ['gallery']);
    final services = _profileTextListAny(p, const ['services']);
    final airportServiceEnabled = _airportServiceEnabledFromProfile(p);
    final visibleServices = airportServiceEnabled
        ? services
        : services
              .where((serviceId) => !_isAirportServiceToken(serviceId))
              .toList(growable: false);
    final paymentMethods = _resolvedPublicPaymentMethods(
      _profileTextListAny(p, const ['payment_methods', 'paymentMethods']),
      _partnerCountryCodeForPaymentResolver(p),
    );
    final aboutCopy = _resolvedAboutCopy(
      aboutShort: aboutShort,
      aboutLong: aboutLong,
    );
    final trust = _profileMap(p['trust']);
    final verified =
        trust['verified_partner'] == true || trust['verifiedPartner'] == true;
    final professionalBadge =
        trust['professional_badge'] == true ||
        trust['professionalBadge'] == true;
    final bookingCapabilities = _profileMap(p['booking_capabilities']);
    final onlinePayments =
        bookingCapabilities['online_payments'] == true ||
        bookingCapabilities['onlinePayments'] == true;
    final hasExplicitOnlinePaymentMethod = paymentMethods.any(
      (m) =>
          m == 'online_payment' ||
          m == 'card_payment' ||
          m == 'apple_pay' ||
          m == 'google_pay' ||
          m == 'paypal' ||
          m == 'bizum' ||
          m == 'bancontact' ||
          m == 'payconiq_wero' ||
          m == 'ideal' ||
          m == 'cartes_bancaires',
    );
    final instantQuote =
        bookingCapabilities['instant_quote'] == true ||
        bookingCapabilities['instantQuote'] == true;
    final vehicles = _profileMapList(p['vehicles']);
    final drivers = _profileMapList(p['drivers'])
        .where((d) {
          final displayName = _profileTextAny(d, const [
            'display_name',
            'displayName',
          ]);
          final languages = _profileTextListAny(d, const ['languages']);
          final badges = _profileTextListAny(d, const ['badges']);
          final portrait = _profileHttpsUrl(d, const [
            'portrait_url',
            'portraitUrl',
          ]);
          return displayName.trim().isNotEmpty ||
              languages.isNotEmpty ||
              badges.isNotEmpty ||
              portrait.isNotEmpty;
        })
        .toList(growable: false);
    final hasBookCta = widget.partnerId.trim().isNotEmpty;
    const int postcodePreviewLimit = 8;
    final visiblePostcodes =
        _showAllCoveragePostcodes || postcodes.length <= postcodePreviewLimit
        ? postcodes
        : postcodes.take(postcodePreviewLimit).toList(growable: false);
    final hiddenPostcodeCount = postcodes.length - visiblePostcodes.length;
    final showContactSection =
        regionLabel.isNotEmpty ||
        postcodes.isNotEmpty ||
        website.isNotEmpty ||
        publicPhone.isNotEmpty ||
        bookingEmail.isNotEmpty ||
        instantQuote ||
        gallery.isNotEmpty;

    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, __) {
        final palette = paletteForCustomerTheme(themeVariant);
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: appLanguageNotifier,
          builder: (context, _, __) => Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              backgroundColor: palette.background,
              foregroundColor: _textPrimary,
              surfaceTintColor: Colors.transparent,
              title: Text(
                _publicProfileLabel('profile'),
                style: TextStyle(color: _textPrimary),
              ),
              actions: [
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TextButton.icon(
                      onPressed: _favoriteBusy ? null : _toggleFavoritePartner,
                      style: TextButton.styleFrom(
                        foregroundColor: _isFavorite
                            ? const Color(0xFFFF7A90)
                            : (_isDarkTheme
                                  ? _gold.withOpacity(0.95)
                                  : _bronze),
                      ),
                      icon: Icon(
                        _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 17,
                      ),
                      label: Text(
                        _t(
                          nl: 'Favoriet',
                          en: 'Favorite',
                          fr: 'Favori',
                          es: 'Favorito',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: !_loading && _error == null && hasBookCta
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: _card.withOpacity(_isDarkTheme ? 0.98 : 0.96),
                      border: Border(
                        top: BorderSide(
                          color: _isDarkTheme
                              ? _gold.withOpacity(0.20)
                              : _border,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _openPartnerBooking(companyName: companyName),
                              style: FilledButton.styleFrom(
                                backgroundColor: _isDarkTheme ? _gold : _bronze,
                                foregroundColor: _isDarkTheme
                                    ? Colors.black
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                minimumSize: const Size.fromHeight(54),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(
                                Icons.local_taxi_outlined,
                                size: 22,
                              ),
                              label: Text(
                                _t(
                                  nl: 'Taxi',
                                  en: 'Taxi',
                                  fr: 'Taxi',
                                  es: 'Taxi',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          if (airportServiceEnabled) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openPartnerAirportBooking(
                                  companyName: companyName,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _isDarkTheme
                                      ? _gold.withOpacity(0.98)
                                      : _bronze,
                                  side: BorderSide(
                                    color: _isDarkTheme
                                        ? _gold.withOpacity(0.38)
                                        : _border,
                                  ),
                                  backgroundColor: _surfaceAlt,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  minimumSize: const Size.fromHeight(54),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.flight_takeoff_rounded,
                                  size: 21,
                                ),
                                label: Text(
                                  _t(
                                    nl: 'Luchthaven',
                                    en: 'Airport',
                                    fr: 'Aéroport',
                                    es: 'Aeropuerto',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : null,
            body: SafeArea(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: _gold))
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textMuted),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
                      children: [
                        if (heroPhotoUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              children: [
                                Image.network(
                                  heroPhotoUrl,
                                  height: 244,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Container(
                                      height: 244,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _surfaceAlt,
                                            _card,
                                            _gold.withOpacity(0.18),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.black.withOpacity(0.06),
                                          Colors.black.withOpacity(0.74),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: logoUrl.isNotEmpty ? 94 : 0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          companyName,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _textPrimary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        ),
                                        if (tagline.isNotEmpty)
                                          Text(
                                            tagline,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _textMuted,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        const SizedBox(height: 5),
                                        _chip(
                                          _verifiedPartnerTrustLabel(),
                                          icon: Icons.verified_outlined,
                                          color: const Color(0xFF34D29A),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (logoUrl.isNotEmpty)
                                  Positioned(
                                    left: 12,
                                    bottom: 10,
                                    child: Container(
                                      width: 82,
                                      height: 82,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.72),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: _gold.withOpacity(0.62),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.30,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(7),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          logoUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                color: _surfaceAlt,
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  Icons.business_outlined,
                                                  color: _gold.withOpacity(
                                                    0.95,
                                                  ),
                                                  size: 28,
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              gradient: LinearGradient(
                                colors: [
                                  _surfaceAlt,
                                  _card,
                                  _gold.withOpacity(0.18),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: _isDarkTheme
                                    ? _gold.withOpacity(0.24)
                                    : _border,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _shadow.withOpacity(
                                    _isDarkTheme ? 0.14 : 0.08,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                if (logoUrl.isNotEmpty)
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.black,
                                    foregroundImage: NetworkImage(logoUrl),
                                  )
                                else
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: _gold.withOpacity(0.2),
                                    child: Icon(
                                      Icons.local_taxi_outlined,
                                      color: _gold.withOpacity(0.95),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        companyName,
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                        ),
                                      ),
                                      if (tagline.isNotEmpty)
                                        Text(
                                          tagline,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (hasCompanyRating)
                              _chip(
                                companyRatingLabel,
                                color: _isDarkTheme
                                    ? const Color(0xFFE0BE64)
                                    : _bronze,
                              ),
                            if (verified || professionalBadge)
                              _chip(
                                _verifiedPartnerTrustLabel(),
                                icon: Icons.verified_outlined,
                                color: const Color(0xFF34D29A),
                              ),
                            if (professionalBadge)
                              _chip(
                                _serviceLabel('verified_professional'),
                                icon: Icons.workspace_premium_outlined,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (hasBookCta)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _openPartnerBooking(
                                    companyName: companyName,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _isDarkTheme
                                        ? _gold
                                        : _bronze,
                                    foregroundColor: _isDarkTheme
                                        ? Colors.black
                                        : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    minimumSize: const Size.fromHeight(52),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.local_taxi_outlined,
                                    size: 21,
                                  ),
                                  label: Text(
                                    _t(
                                      nl: 'Taxi',
                                      en: 'Taxi',
                                      fr: 'Taxi',
                                      es: 'Taxi',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                              ),
                              if (airportServiceEnabled) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openPartnerAirportBooking(
                                      companyName: companyName,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _isDarkTheme
                                          ? _gold.withOpacity(0.98)
                                          : _bronze,
                                      side: BorderSide(
                                        color: _isDarkTheme
                                            ? _gold.withOpacity(0.36)
                                            : _border,
                                      ),
                                      backgroundColor: _surfaceAlt,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      minimumSize: const Size.fromHeight(52),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.flight_takeoff_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      _t(
                                        nl: 'Luchthaven',
                                        en: 'Airport',
                                        fr: 'Aéroport',
                                        es: 'Aeropuerto',
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        const SizedBox(height: 9),
                        _section(
                          _publicProfileLabel('about'),
                          Text(
                            aboutCopy,
                            style: TextStyle(
                              color: _textMuted,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (visibleServices.isNotEmpty)
                          _section(
                            _t(
                              nl: 'Services',
                              en: 'Services',
                              fr: 'Services',
                              es: 'Servicios',
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: visibleServices
                                  .map(
                                    (s) => _chip(
                                      _serviceLabel(s),
                                      icon: Icons.check_circle_outline,
                                      color: _isDarkTheme
                                          ? const Color(0xFFDFC16A)
                                          : _bronze,
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        if (vehicles.isNotEmpty)
                          _section(
                            _t(
                              nl: 'Voertuigen',
                              en: 'Vehicles',
                              fr: 'Véhicules',
                              es: 'Vehículos',
                            ),
                            Column(
                              children: vehicles
                                  .map((v) {
                                    final vName = _localizeVehicleName(
                                      _profileTextAny(v, const ['name']),
                                    );
                                    final vBrand = _profileTextAny(v, const [
                                      'brand_model',
                                      'brandModel',
                                    ]);
                                    final vCategory = _profileTextAny(v, const [
                                      'category',
                                    ]);
                                    final vehiclePhotoUrl = _profileHttpsUrl(
                                      v,
                                      const ['photo_url', 'photoUrl'],
                                    );
                                    final vFeatures = _profileTextListAny(
                                      v,
                                      const ['features'],
                                    );
                                    final vPax = v['pax'];
                                    final vLuggage = v['luggage'];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _surfaceAlt,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: _isDarkTheme
                                              ? _gold.withOpacity(0.2)
                                              : _border,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (vehiclePhotoUrl.isNotEmpty)
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                vehiclePhotoUrl,
                                                height: 168,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) {
                                                  return Container(
                                                    height: 168,
                                                    width: double.infinity,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          _surfaceAlt,
                                                          _gold.withOpacity(
                                                            0.16,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .directions_car_outlined,
                                                          color: _gold
                                                              .withOpacity(
                                                                0.95,
                                                              ),
                                                          size: 18,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          _t(
                                                            nl: 'Publiek voertuigprofiel',
                                                            en: 'Public vehicle profile',
                                                            fr: 'Profil véhicule public',
                                                            es: 'Perfil público de vehículo',
                                                          ),
                                                          style: TextStyle(
                                                            color: _textMuted,
                                                            fontSize: 11.3,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          else
                                            Container(
                                              height: 54,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                gradient: LinearGradient(
                                                  colors: [
                                                    _surfaceAlt,
                                                    _gold.withOpacity(0.16),
                                                  ],
                                                ),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .directions_car_outlined,
                                                    color: _gold.withOpacity(
                                                      0.95,
                                                    ),
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    _t(
                                                      nl: 'Publiek voertuigprofiel',
                                                      en: 'Public vehicle profile',
                                                      fr: 'Profil véhicule public',
                                                      es: 'Perfil público de vehículo',
                                                    ),
                                                    style: TextStyle(
                                                      color: _textMuted,
                                                      fontSize: 11.3,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 7),
                                          Text(
                                            vName,
                                            style: TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (vBrand.isNotEmpty ||
                                              vCategory.isNotEmpty)
                                            Text(
                                              [vBrand, vCategory]
                                                  .where(
                                                    (e) => e.trim().isNotEmpty,
                                                  )
                                                  .join(' • '),
                                              style: TextStyle(
                                                color: _textMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              if (vPax != null)
                                                _chip(
                                                  '${_publicProfileLabel("passengers")}: $vPax',
                                                  icon:
                                                      Icons.people_alt_outlined,
                                                ),
                                              if (vLuggage != null)
                                                _chip(
                                                  '${_publicProfileLabel("luggage")}: $vLuggage',
                                                  icon: Icons.luggage_outlined,
                                                ),
                                              ...vFeatures.map(
                                                (f) => _chip(_featureLabel(f)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          ),
                        if (drivers.isNotEmpty)
                          _section(
                            _publicProfileLabel('drivers'),
                            Column(
                              children: drivers
                                  .map((d) {
                                    final displayName = _profileTextAny(
                                      d,
                                      const ['display_name', 'displayName'],
                                    );
                                    final languages = _profileTextListAny(
                                      d,
                                      const ['languages'],
                                    );
                                    final badges = _profileTextListAny(
                                      d,
                                      const ['badges'],
                                    );
                                    final portrait = _profileHttpsUrl(d, const [
                                      'portrait_url',
                                      'portraitUrl',
                                    ]);
                                    final ratingAvg = _ratingAverageFromMap(d);
                                    final ratingCount = _ratingCountFromMap(d);
                                    final ratingLabel = _localizedRatingDisplay(
                                      avg: ratingAvg,
                                      count: ratingCount,
                                    );
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _surfaceAlt,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: _isDarkTheme
                                              ? _gold.withOpacity(0.2)
                                              : _border,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 20,
                                            backgroundColor: _gold.withOpacity(
                                              0.2,
                                            ),
                                            foregroundImage: portrait.isNotEmpty
                                                ? NetworkImage(portrait)
                                                : null,
                                            child: portrait.isEmpty
                                                ? Icon(
                                                    Icons
                                                        .person_outline_rounded,
                                                    color: _gold.withOpacity(
                                                      0.96,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  displayName,
                                                  style: TextStyle(
                                                    color: _textPrimary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  ratingLabel,
                                                  style: TextStyle(
                                                    color: _textMuted,
                                                    fontSize: 12.0,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                if (languages.isNotEmpty)
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: languages
                                                        .map(
                                                          (l) => _chip(
                                                            l,
                                                            icon: Icons
                                                                .translate_rounded,
                                                          ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                  ),
                                                if (badges.isNotEmpty) ...[
                                                  const SizedBox(height: 5),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: badges
                                                        .map(
                                                          (b) => _chip(
                                                            _badgeLabel(b),
                                                            icon: Icons
                                                                .verified_outlined,
                                                          ),
                                                        )
                                                        .toList(
                                                          growable: false,
                                                        ),
                                                  ),
                                                ],
                                                if (badges.isEmpty) ...[
                                                  const SizedBox(height: 5),
                                                  _chip(
                                                    _serviceLabel(
                                                      'verified_professional',
                                                    ),
                                                    icon:
                                                        Icons.verified_outlined,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          ),
                        if (showContactSection)
                          _section(
                            _publicProfileLabel('coverage'),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (regionLabel.isNotEmpty)
                                  Text(
                                    '${_publicProfileLabel("region")}: $regionLabel',
                                    style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 12.7,
                                    ),
                                  ),
                                if (postcodes.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: visiblePostcodes
                                        .map(
                                          (z) => _chip(
                                            z,
                                            icon: Icons.location_on_outlined,
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                  if (hiddenPostcodeCount > 0) ...[
                                    const SizedBox(height: 7),
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _showAllCoveragePostcodes =
                                              !_showAllCoveragePostcodes;
                                        });
                                      },
                                      icon: Icon(
                                        _showAllCoveragePostcodes
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _showAllCoveragePostcodes
                                            ? _t(
                                                nl: 'Minder tonen',
                                                en: 'Show less',
                                                fr: 'Afficher moins',
                                                es: 'Mostrar menos',
                                              )
                                            : _t(
                                                nl: 'Toon alle regio’s (+$hiddenPostcodeCount)',
                                                en: 'Show all areas (+$hiddenPostcodeCount)',
                                                fr: 'Afficher toutes les zones (+$hiddenPostcodeCount)',
                                                es: 'Mostrar todas las zonas (+$hiddenPostcodeCount)',
                                              ),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _isDarkTheme
                                            ? _gold.withOpacity(0.96)
                                            : _bronze,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                                if (website.isNotEmpty ||
                                    publicPhone.isNotEmpty ||
                                    bookingEmail.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (website.isNotEmpty)
                                        _contactActionButton(
                                          label: _t(
                                            nl: 'Website',
                                            en: 'Website',
                                            fr: 'Site web',
                                            es: 'Sitio web',
                                          ),
                                          icon: Icons.language_outlined,
                                          onPressed: () =>
                                              _launchWebsiteUrl(website),
                                        ),
                                      if (publicPhone.isNotEmpty)
                                        _contactActionButton(
                                          label: _t(
                                            nl: 'Bel',
                                            en: 'Call',
                                            fr: 'Appeler',
                                            es: 'Llamar',
                                          ),
                                          icon: Icons.call_outlined,
                                          onPressed: () =>
                                              _launchPublicPhone(publicPhone),
                                        ),
                                      if (bookingEmail.isNotEmpty)
                                        _contactActionButton(
                                          label: _t(
                                            nl: 'E-mail',
                                            en: 'Email',
                                            fr: 'E-mail',
                                            es: 'E-mail',
                                          ),
                                          icon: Icons.email_outlined,
                                          onPressed: () =>
                                              _launchBookingEmail(bookingEmail),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (website.isNotEmpty)
                                    Text(
                                      '${_publicProfileLabel("website")}: $website',
                                      style: TextStyle(color: _textMuted),
                                    ),
                                  if (publicPhone.isNotEmpty)
                                    Text(
                                      '${_publicProfileLabel("phone")}: $publicPhone',
                                      style: TextStyle(color: _textMuted),
                                    ),
                                  if (bookingEmail.isNotEmpty)
                                    Text(
                                      '${_publicProfileLabel("booking_email")}: $bookingEmail',
                                      style: TextStyle(color: _textMuted),
                                    ),
                                ],
                                if (onlinePayments ||
                                    instantQuote ||
                                    gallery.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (onlinePayments)
                                        if (!hasExplicitOnlinePaymentMethod)
                                          _chip(
                                            _t(
                                              nl: 'Online betalen',
                                              en: 'Online payments',
                                              fr: 'Paiement en ligne',
                                              es: 'Pagos en línea',
                                            ),
                                            icon: Icons.credit_card_outlined,
                                          ),
                                      if (instantQuote)
                                        _chip(
                                          _t(
                                            nl: 'Directe prijsindicatie',
                                            en: 'Instant quote',
                                            fr: 'Devis instantané',
                                            es: 'Presupuesto instantáneo',
                                          ),
                                          icon: Icons.flash_on_outlined,
                                        ),
                                      if (gallery.isNotEmpty)
                                        _chip(
                                          _t(
                                            nl: '${gallery.length} galerijfoto\'s',
                                            en: '${gallery.length} gallery photos',
                                            fr: '${gallery.length} photos de galerie',
                                            es: '${gallery.length} fotos de galería',
                                          ),
                                          icon: Icons.photo_library_outlined,
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (paymentMethods.isNotEmpty)
                          _section(
                            _t(
                              nl: 'Betaalopties',
                              en: 'Payment options',
                              fr: 'Moyens de paiement',
                              es: 'Opciones de pago',
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _paymentOptionsWithMollieBadgeSection(
                                  paymentMethods,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
