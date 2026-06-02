import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/discovery/discovery_models.dart';
import 'package:fluxidi_tracking/discovery/discovery_labels.dart';
import 'package:fluxidi_tracking/events/event_models.dart';
import 'package:fluxidi_tracking/events/event_seed_data.dart';
import 'package:fluxidi_tracking/events/events_detail_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluxidi_tracking/calculator_page.dart';
import 'package:path_provider/path_provider.dart';

import '../discovery/discovery_geo.dart';
import '../discovery/discovery_nearby.dart';
import '../customer_profile_store.dart';
import '../nearby_partners_page.dart';
import 'approved_hotel_data.dart';
import 'hotel_geo_taxonomy.dart';
import 'hotel_model.dart';

enum _HotelExternalProvider { stay22Allez, bookingComFallback }

class HotelsPage extends StatefulWidget {
  const HotelsPage({
    this.stays,
    this.onTaxiToStay,
    this.onTaxiToDestination,
    this.onOpenAirportFlow,
    this.onManualHotelTaxi,
    this.onOpenAirportReturnFlow,
    this.tenantId,
    this.companyId,
    super.key,
  });

  /// Optional data injection for later phases (API/provider).
  final List<HotelStay>? stays;

  /// Optional CTA callback for later taxi-prefill integration.
  final void Function(HotelStay stay)? onTaxiToStay;
  final void Function(DiscoveryDestination destination)? onTaxiToDestination;
  final Future<void> Function(DiscoveryDestination destination)?
  onOpenAirportFlow;
  final Future<void> Function()? onManualHotelTaxi;
  final Future<void> Function()? onOpenAirportReturnFlow;
  final String? tenantId;
  final String? companyId;

  @override
  State<HotelsPage> createState() => _HotelsPageState();
}

class _HotelsPageState extends State<HotelsPage> {
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _themePalette.isDark;
  Color get _bgBlack => _themePalette.background;
  Color get _panelBlack => _themePalette.surface;
  Color get _gold => _themePalette.gold;
  Color get _softText => _themePalette.textMuted;
  Color get _textPrimary => _themePalette.textPrimary;
  Color get _border => _themePalette.border;
  Color get _shadow => _themePalette.shadow;
  Color get _actionOnGold =>
      _isDarkTheme ? Colors.black : const Color(0xFF1F1706);

  final TextEditingController _searchController = TextEditingController();
  final DiscoveryLocalSavedStore _savedStore = const DiscoveryLocalSavedStore(
    namespace: 'hotels',
  );
  static const String _allKey = 'all';
  static const String _stay22Aid = 'fluxidi';

  late final List<HotelStay> _allStays;
  Set<String> _savedStayIds = <String>{};
  String _selectedCountryCode = _allKey;
  String _selectedSettlementKey = _allKey;
  String _selectedRegionKey = _allKey;
  String _selectedType = _allKey;

  String get _languageCode => appConfig.currentLanguage.name;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_languageCode) {
      case 'en':
        return en;
      case 'fr':
        return fr;
      case 'es':
        return es;
      case 'nl':
      default:
        return nl;
    }
  }

  @override
  void initState() {
    super.initState();
    customerThemeNotifier.addListener(_onThemeChanged);
    _allStays = List<HotelStay>.from(widget.stays ?? kApprovedBelgiumHotelData);
    _searchController.addListener(_onSearchChanged);
    _loadSavedStayIds();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    customerThemeNotifier.removeListener(_onThemeChanged);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _showThemedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _panelBlack,
        content: Text(message, style: TextStyle(color: _textPrimary)),
      ),
    );
  }

  void _onSearchChanged() {
    setState(() {});
  }

  List<HotelGeoOption> get _settlementOptions {
    if (_selectedCountryCode == _allKey || _selectedRegionKey == _allKey) {
      return const <HotelGeoOption>[];
    }
    return hotelGeoSettlementOptions(
      countryCode: _selectedCountryCode,
      regionKey: _selectedRegionKey,
      languageCode: _languageCode,
    );
  }

  List<HotelGeoOption> get _regionOptions {
    if (_selectedCountryCode == _allKey) return const <HotelGeoOption>[];
    return hotelGeoRegionOptions(
      countryCode: _selectedCountryCode,
      languageCode: _languageCode,
    );
  }

  List<HotelGeoOption> get _countryOptions {
    return hotelGeoCountryOptions(_languageCode);
  }

  List<HotelStay> _filterStays(List<HotelStay> sourceStays) {
    final query = _searchController.text.trim().toLowerCase();
    final countryMatchValues = _selectedCountryCode == _allKey
        ? const <String>{}
        : normalizedDiscoveryTextSet(
            hotelGeoCountryMatchValues(_selectedCountryCode),
          );
    final regionMatchValues =
        (_selectedCountryCode == _allKey || _selectedRegionKey == _allKey)
        ? const <String>{}
        : normalizedDiscoveryTextSet(
            hotelGeoRegionMatchValues(
              countryCode: _selectedCountryCode,
              regionKey: _selectedRegionKey,
            ),
          );
    final settlementMatchValues =
        (_selectedCountryCode == _allKey ||
            _selectedRegionKey == _allKey ||
            _selectedSettlementKey == _allKey)
        ? const <String>{}
        : normalizedDiscoveryTextSet(
            hotelGeoSettlementMatchValues(
              countryCode: _selectedCountryCode,
              regionKey: _selectedRegionKey,
              settlementKey: _selectedSettlementKey,
            ),
          );
    return sourceStays
        .where((stay) {
          if (countryMatchValues.isNotEmpty &&
              !countryMatchValues.contains(
                normalizeDiscoveryText(stay.country),
              )) {
            return false;
          }
          if (regionMatchValues.isNotEmpty &&
              !regionMatchValues.contains(
                normalizeDiscoveryText(stay.region),
              )) {
            return false;
          }
          if (settlementMatchValues.isNotEmpty &&
              !settlementMatchValues.contains(
                normalizeDiscoveryText(stay.city),
              )) {
            return false;
          }
          if (_selectedType != _allKey && stay.type != _selectedType)
            return false;
          if (query.isEmpty) return true;

          final searchBlob = <String>[
            stay.name,
            stay.type,
            stay.city,
            stay.region,
            stay.country,
            stay.address,
            stay.description,
            ...stay.tags,
          ].join(' ').toLowerCase();
          return searchBlob.contains(query);
        })
        .toList(growable: false);
  }

  List<HotelStay> get _visibleStays => _filterStays(_allStays);

  List<HotelStay> get _discoveryRegionStays => _filterStays(const <HotelStay>[
    HotelStay(
      id: 'discovery-vlaamse-ardennen',
      name: "Hotels & B&B's in de Vlaamse Ardennen",
      type: HotelStayType.guesthouse,
      city: 'Vlaamse Ardennen',
      region: 'Oost-Vlaanderen',
      country: 'Belgium',
      address: 'Vlaamse Ardennen, Belgium',
      description: 'Ontdek verblijven en plan je rit.',
      imageRef: 'approved_asset:assets/fluxidi/Hotel&B&B_background.png',
      lat: 50.7655,
      lng: 3.6231,
      provider: 'fluxidi-discovery',
      source: 'discovery',
      sourceId: 'discovery-vlaamse-ardennen',
    ),
    HotelStay(
      id: 'discovery-boutique-gent',
      name: 'Boutique stays rond Gent',
      type: HotelStayType.hotel,
      city: 'Gent',
      region: 'Oost-Vlaanderen',
      country: 'Belgium',
      address: 'Gent, Belgium',
      description: 'Ontdek verblijven en plan je rit.',
      imageRef:
          'approved_asset:assets/fluxidi/customer_home_hotel_bb_banner.png',
      lat: 51.0543,
      lng: 3.7174,
      provider: 'fluxidi-discovery',
      source: 'discovery',
      sourceId: 'discovery-boutique-gent',
    ),
    HotelStay(
      id: 'discovery-brussels-airport',
      name: 'Hotels bij Brussels Airport',
      type: HotelStayType.hotel,
      city: 'Brussel',
      region: 'Brussels Hoofdstedelijk Gewest',
      country: 'Belgium',
      address: 'Brussels Airport, Belgium',
      description: 'Ontdek verblijven en plan je rit.',
      imageRef:
          'approved_asset:assets/fluxidi/customer_home_airport_banner.png',
      lat: 50.9014,
      lng: 4.4844,
      provider: 'fluxidi-discovery',
      source: 'discovery',
      sourceId: 'discovery-brussels-airport',
    ),
    HotelStay(
      id: 'discovery-city-brugge',
      name: 'City hotels in Brugge',
      type: HotelStayType.hotel,
      city: 'Brugge',
      region: 'West-Vlaanderen',
      country: 'Belgium',
      address: 'Brugge, Belgium',
      description: 'Ontdek verblijven en plan je rit.',
      imageRef:
          'approved_asset:assets/fluxidi/customer_home_business_banner.png',
      lat: 51.2093,
      lng: 3.2247,
      provider: 'fluxidi-discovery',
      source: 'discovery',
      sourceId: 'discovery-city-brugge',
    ),
    HotelStay(
      id: 'discovery-coast-stays',
      name: 'Verblijven aan de kust',
      type: HotelStayType.bedAndBreakfast,
      city: 'Kust',
      region: 'West-Vlaanderen',
      country: 'Belgium',
      address: 'Belgische kust, Belgium',
      description: 'Ontdek verblijven en plan je rit.',
      imageRef: 'approved_asset:assets/fluxidi/customer_home_events_banner.png',
      lat: 51.2301,
      lng: 2.9196,
      provider: 'fluxidi-discovery',
      source: 'discovery',
      sourceId: 'discovery-coast-stays',
    ),
  ]);

  bool _isApprovedImageUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) return false;
    return parsed.scheme == 'http' || parsed.scheme == 'https';
  }

  bool _isApprovedCustomerFacingStay(HotelStay stay) {
    if (!stay.isRealApproved) return false;
    final imageRef = stay.imageRef.trim();
    if (imageRef.startsWith('seed:')) return false;
    final imageUrl = (stay.imageUrl ?? '').trim();
    if (imageUrl.isNotEmpty && _isApprovedImageUrl(imageUrl)) return true;
    if (imageRef.startsWith('approved_asset:')) {
      final pathSuffix = imageRef.substring('approved_asset:'.length).trim();
      return pathSuffix.isNotEmpty;
    }
    return false;
  }

  String _approvedAssetPath(HotelStay stay) {
    final imageRef = stay.imageRef.trim();
    if (!imageRef.startsWith('approved_asset:')) return '';
    final pathSuffix = imageRef.substring('approved_asset:'.length).trim();
    return pathSuffix;
  }

  String _typeLabel(String typeKey) {
    if (typeKey == _allKey) {
      return _t(
        nl: 'Alle types',
        en: 'All types',
        fr: 'Tous les types',
        es: 'Todos los tipos',
      );
    }
    if (typeKey == HotelStayType.aparthotel) {
      return _t(
        nl: 'Aparthotel',
        en: 'Aparthotel',
        fr: 'Aparthotel',
        es: 'Aparthotel',
      );
    }
    if (typeKey == HotelStayType.guesthouse) {
      return _t(
        nl: 'Guesthouse',
        en: 'Guesthouse',
        fr: 'Guesthouse',
        es: 'Guesthouse',
      );
    }
    if (typeKey == HotelStayType.hotel) return 'Hotel';
    if (typeKey == HotelStayType.bedAndBreakfast) {
      return discoveryStayTypeLabel(
        HotelStayType.bedAndBreakfast,
        (nl, en, fr, es) => _t(nl: nl, en: en, fr: fr, es: es),
      );
    }
    return typeKey;
  }

  String get _recommendedLabel {
    return _t(
      nl: 'Aanbevolen',
      en: 'Recommended',
      fr: 'Recommandé',
      es: 'Recomendado',
    );
  }

  String get _fromLabel {
    return _t(nl: 'Vanaf', en: 'From', fr: 'À partir de', es: 'Desde');
  }

  String get _viewStayLabel {
    return _t(
      nl: 'Bekijk verblijf',
      en: 'View stay',
      fr: 'Voir le séjour',
      es: 'Ver alojamiento',
    );
  }

  String get _viewOptionsLabel {
    return _t(
      nl: 'Bekijk opties',
      en: 'View options',
      fr: 'Voir les options',
      es: 'Ver opciones',
    );
  }

  String get _saveStayLabel {
    return _t(nl: 'Opslaan', en: 'Save', fr: 'Enregistrer', es: 'Guardar');
  }

  String get _savedStayLabel {
    return _t(nl: 'Opgeslagen', en: 'Saved', fr: 'Enregistré', es: 'Guardado');
  }

  String get _externalAvailabilityLabel {
    return _t(
      nl: 'Bekijk beschikbaarheid extern',
      en: 'Check availability externally',
      fr: 'Voir les disponibilités externes',
      es: 'Ver disponibilidad externa',
    );
  }

  String get _safeDiscoveryCopy {
    return _t(
      nl: 'Zoek een hotel, B&B, stad of regio. Beschikbaarheid en prijzen worden extern getoond.',
      en: 'Search a hotel, B&B, city or region. Availability and prices are shown externally.',
      fr: 'Recherchez un hôtel, B&B, ville ou région. Les disponibilités et les prix sont affichés en externe.',
      es: 'Busca un hotel, B&B, ciudad o región. La disponibilidad y los precios se muestran externamente.',
    );
  }

  String get _planTaxiToStayLabel {
    return _t(
      nl: 'Taxi naar verblijf plannen',
      en: 'Plan taxi to stay',
      fr: 'Planifier un taxi vers l’hébergement',
      es: 'Planificar taxi al alojamiento',
    );
  }

  String get _returnFlowTitle {
    return _t(
      nl: 'Heb je al een verblijf gekozen?',
      en: 'Already picked a stay?',
      fr: 'Vous avez déjà choisi un hébergement ?',
      es: '¿Ya elegiste un alojamiento?',
    );
  }

  String get _returnFlowSubtitle {
    return _t(
      nl: 'Plan je rit naar je hotel/B&B.',
      en: 'Plan your ride to your hotel/B&B.',
      fr: 'Planifiez votre trajet vers votre hôtel/B&B.',
      es: 'Planifica tu viaje a tu hotel/B&B.',
    );
  }

  String get _returnFlowEnterAddressLabel {
    return _t(
      nl: 'Adres invullen',
      en: 'Enter address',
      fr: 'Saisir l’adresse',
      es: 'Introducir dirección',
    );
  }

  String get _returnFlowAirportToStayLabel {
    return _t(
      nl: 'Luchthaven → verblijf',
      en: 'Airport → stay',
      fr: 'Aéroport → hébergement',
      es: 'Aeropuerto → alojamiento',
    );
  }

  String get _destinationQueryRequiredLabel {
    return _t(
      nl: 'Voer eerst een bestemming in om taxi te plannen.',
      en: 'Enter a destination first to plan taxi.',
      fr: 'Saisissez d’abord une destination pour planifier le taxi.',
      es: 'Introduce primero un destino para planificar el taxi.',
    );
  }

  bool _canShowStayTaxiCta(HotelStay stay) {
    if (!stay.isRealApproved) return false;
    if (stay.source == 'discovery') return false;
    final hasAddress =
        stay.address.trim().isNotEmpty || stay.city.trim().isNotEmpty;
    final lat = stay.latitude ?? stay.lat;
    final lng = stay.longitude ?? stay.lng;
    final hasCoordinates =
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    return hasAddress || hasCoordinates;
  }

  String _staySavedMessage(String name) {
    return _t(
      nl: '$name opgeslagen.',
      en: '$name saved.',
      fr: '$name enregistré.',
      es: '$name guardado.',
    );
  }

  String _stayUnsavedMessage(String name) {
    return _t(
      nl: '$name verwijderd uit opgeslagen verblijven.',
      en: '$name removed from saved stays.',
      fr: '$name retiré des séjours enregistrés.',
      es: '$name eliminado de alojamientos guardados.',
    );
  }

  String get _saveSyncFailedLabel {
    return _t(
      nl: 'Kon opslaan lokaal niet bijwerken.',
      en: 'Could not update local saved state.',
      fr: 'Impossible de mettre à jour l’état enregistré local.',
      es: 'No se pudo actualizar el estado guardado local.',
    );
  }

  bool _isSaved(HotelStay stay) => _savedStayIds.contains(stay.id);

  Future<void> _loadSavedStayIds() async {
    final ids = await _savedStore.loadSavedIds();
    if (!mounted) return;
    setState(() => _savedStayIds = ids);
  }

  Future<void> _toggleSaved(HotelStay stay) async {
    final previous = Set<String>.from(_savedStayIds);
    final currentlySaved = _isSaved(stay);
    final nextSaved = !currentlySaved;
    final next = Set<String>.from(_savedStayIds);
    if (nextSaved) {
      next.add(stay.id);
    } else {
      next.remove(stay.id);
    }
    setState(() => _savedStayIds = next);
    try {
      await _savedStore.setSaved(stay.id, saved: nextSaved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _savedStayIds = previous);
      _showThemedSnackBar(_saveSyncFailedLabel);
      return;
    }
    if (!mounted) return;
    _showThemedSnackBar(
      nextSaved ? _staySavedMessage(stay.name) : _stayUnsavedMessage(stay.name),
    );
  }

  String get _taxiNavigationFallbackLabel {
    return _t(
      nl: 'Taxi-handoff gebruikt fallbackmodus.',
      en: 'Taxi handoff is using fallback mode.',
      fr: 'Le transfert taxi utilise le mode de secours.',
      es: 'La transferencia de taxi usa el modo de respaldo.',
    );
  }

  String get _airportFlowFallbackLabel {
    return _t(
      nl: 'Luchthavenflow is hier nog niet gekoppeld.',
      en: 'Airport flow is not connected here yet.',
      fr: 'Le flux aeroport n est pas encore connecte ici.',
      es: 'El flujo de aeropuerto aun no esta conectado aqui.',
    );
  }

  bool _isPremiumStay(HotelStay stay) {
    if ((stay.rating ?? 0) >= 4.7) return true;
    final joined = <String>[
      ...stay.tags,
      ...stay.travelStyles,
      ...stay.popularFor,
      stay.ambience ?? '',
    ].join(' ').toLowerCase();
    const premiumKeywords = <String>[
      'premium',
      'luxury',
      'luxe',
      'wellness',
      'resort',
      'boutique',
      'spa',
    ];
    for (final keyword in premiumKeywords) {
      if (joined.contains(keyword)) return true;
    }
    return false;
  }

  String _displayPriceHint(HotelStay stay) {
    return formatDiscoveryPriceHint(stay.priceHint, fromLabel: _fromLabel);
  }

  List<String> _semanticHighlights(HotelStay stay) {
    final values = <String>[
      ...stay.tags,
      ...stay.travelStyles,
      ...stay.popularFor,
    ];
    final seen = <String>{};
    final highlights = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (!seen.add(key)) continue;
      highlights.add(trimmed);
      if (highlights.length >= 2) break;
    }
    return highlights;
  }

  String _bookingLanguageCode() {
    switch (_languageCode) {
      case 'fr':
        return 'fr';
      case 'es':
        return 'es';
      case 'en':
        return 'en-gb';
      case 'nl':
      default:
        return 'nl';
    }
  }

  String _hotelExternalSearchQuery({HotelStay? stay, String? query}) {
    final preferredQuery = (query ?? '').trim();
    if (preferredQuery.isNotEmpty) return preferredQuery;
    if (stay != null) {
      final fromStay = <String>[
        stay.name.trim(),
        stay.city.trim(),
        stay.country.trim(),
      ].where((segment) => segment.isNotEmpty).join(', ');
      if (fromStay.isNotEmpty) return fromStay;
    }
    final typedQuery = _searchController.text.trim();
    if (typedQuery.isNotEmpty) return typedQuery;
    final settlementLabel = _settlementOptions
        .where((option) => option.value == _selectedSettlementKey)
        .map((option) => option.label.trim())
        .firstWhere((label) => label.isNotEmpty, orElse: () => '');
    if (settlementLabel.isNotEmpty) return settlementLabel;
    final regionLabel = _regionOptions
        .where((option) => option.value == _selectedRegionKey)
        .map((option) => option.label.trim())
        .firstWhere((label) => label.isNotEmpty, orElse: () => '');
    if (regionLabel.isNotEmpty) return regionLabel;
    final countryLabel = _countryOptions
        .where((option) => option.value == _selectedCountryCode)
        .map((option) => option.label.trim())
        .firstWhere((label) => label.isNotEmpty, orElse: () => '');
    if (countryLabel.isNotEmpty) return countryLabel;
    return _t(nl: 'België', en: 'Belgium', fr: 'Belgique', es: 'Bélgica');
  }

  Uri _hotelProviderSearchUri({
    required _HotelExternalProvider provider,
    HotelStay? stay,
    String? query,
    String? campaign,
  }) {
    final resolvedQuery = _hotelExternalSearchQuery(stay: stay, query: query);
    final resolvedCampaign = (campaign ?? '').trim().isNotEmpty
        ? campaign!.trim()
        : (stay == null ? 'fluxidi_hotels_discovery' : 'fluxidi_hotels_detail');
    switch (provider) {
      case _HotelExternalProvider.stay22Allez:
        // TODO(H1-F): Verify exact Stay22 AID from the Stay22 Hub before production rollout.
        // TODO(H1-F): Stay22 Map can later power event/venue accommodation map surfaces.
        return Uri.https('www.stay22.com', '/allez', <String, String>{
          'aid': _stay22Aid,
          'address': resolvedQuery,
          'campaign': resolvedCampaign,
          'product_medium': 'apps',
        });
      case _HotelExternalProvider.bookingComFallback:
        // TODO(H1-F): Keep as fallback only; Stay22 is the primary external availability layer.
        return Uri.https(
          'www.booking.com',
          '/searchresults.html',
          <String, String>{
            'ss': resolvedQuery,
            'lang': _bookingLanguageCode(),
            'group_adults': '2',
            'group_children': '0',
            'no_rooms': '1',
          },
        );
    }
  }

  Uri _hotelExternalAvailabilityUri({
    HotelStay? stay,
    String? query,
    String? campaign,
  }) {
    // TODO(H1-F): Verify exact customer-facing Stay22 deep-link pattern/AID from Hub.
    // Until verified, do not route customers to /allez generator-style links.
    return _hotelProviderSearchUri(
      provider: _HotelExternalProvider.bookingComFallback,
      stay: stay,
      query: query,
      campaign: campaign,
    );
  }

  Future<void> _openExternalHotelSearch({
    HotelStay? stay,
    String? query,
    String? campaign,
  }) async {
    final primaryUri = _hotelExternalAvailabilityUri(
      stay: stay,
      query: query,
      campaign: campaign,
    );
    var opened = await launchUrl(
      primaryUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      final fallbackUri = _hotelProviderSearchUri(
        provider: _HotelExternalProvider.bookingComFallback,
        stay: stay,
        query: query,
        campaign: campaign,
      );
      if (fallbackUri.toString() != primaryUri.toString()) {
        opened = await launchUrl(
          fallbackUri,
          mode: LaunchMode.externalApplication,
        );
      }
    }
    if (opened) return;
    if (!mounted) return;
    _showThemedSnackBar(
      _t(
        nl: 'Kon externe hotellijst niet openen.',
        en: 'Could not open external hotel search.',
        fr: 'Impossible d’ouvrir la recherche d’hôtels externe.',
        es: 'No se pudo abrir la búsqueda externa de hoteles.',
      ),
    );
  }

  String get _allCountriesLabel {
    return _t(
      nl: 'Alle landen',
      en: 'All countries',
      fr: 'Tous les pays',
      es: 'Todos los países',
    );
  }

  String get _allRegionsLabel {
    return _t(
      nl: 'Alle regio\'s',
      en: 'All regions',
      fr: 'Toutes les régions',
      es: 'Todas las regiones',
    );
  }

  String get _allCitiesLabel {
    return _t(
      nl: 'Alle steden',
      en: 'All cities',
      fr: 'Toutes les villes',
      es: 'Todas las ciudades',
    );
  }

  String _formatRoutePrefillAddress({
    required String rawAddress,
    required String label,
    required String city,
    required String region,
    required String country,
  }) {
    final raw = rawAddress.trim();
    final safeLabel = label.trim();
    final safeCity = city.trim();
    final safeRegion = region.trim();
    final safeCountry = country.trim();
    final normalizedRaw = normalizeDiscoveryText(raw);
    final normalizedCity = normalizeDiscoveryText(safeCity);
    final normalizedRegion = normalizeDiscoveryText(safeRegion);
    final normalizedCountry = normalizeDiscoveryText(safeCountry);

    bool containsNormalized(String value) {
      final normalized = normalizeDiscoveryText(value);
      return normalized.isNotEmpty && normalizedRaw.contains(normalized);
    }

    if (raw.isEmpty) {
      if (safeLabel.isNotEmpty) return safeLabel;
      final locality = <String>[
        if (safeCity.isNotEmpty) safeCity,
        if (safeRegion.isNotEmpty &&
            normalizeDiscoveryText(safeRegion) !=
                normalizeDiscoveryText(safeCity))
          safeRegion,
        if (safeCountry.isNotEmpty) safeCountry,
      ];
      return locality.join(', ');
    }

    if ((normalizedCity.isNotEmpty && containsNormalized(safeCity)) ||
        (normalizedCountry.isNotEmpty && containsNormalized(safeCountry))) {
      return raw;
    }

    final segments = <String>[raw];
    void addIfUseful(String segment) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) return;
      final normalized = normalizeDiscoveryText(trimmed);
      if (normalized.isEmpty) return;
      if (segments.any(
        (item) => normalizeDiscoveryText(item).contains(normalized),
      )) {
        return;
      }
      segments.add(trimmed);
    }

    addIfUseful(safeCity);
    addIfUseful(safeRegion);
    addIfUseful(safeCountry);
    return segments.join(', ');
  }

  String _partnerSelectionValue(Map<String, String>? map, String key) {
    if (map == null) return '';
    return (map[key] ?? '').trim();
  }

  Future<Map<String, String>?> _selectTaxiPartnerForHotelsEvent() async {
    // TODO(H1-F): Add dedicated hotel/event partner prefill in NearbyPartnersPage.
    final selected = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => NearbyPartnersPage(
          customerHomeBuilder: (_) => const HotelsPage(),
          regionRegistrationBuilder: (_) => const HotelsPage(),
          syncCustomerProfileFromBackend: ({required String reason}) async {
            return await CustomerProfileStore.instance.load();
          },
          selectionMode: true,
        ),
      ),
    );
    if (selected == null || !mounted) return null;
    final partnerId = _partnerSelectionValue(selected, 'partner_id');
    if (partnerId.isEmpty) {
      _showThemedSnackBar(
        _t(
          nl: 'Kies eerst een taxipartner.',
          en: 'Select a taxi partner first.',
          fr: "Sélectionnez d'abord un partenaire taxi.",
          es: 'Selecciona primero un socio de taxi.',
        ),
      );
      return null;
    }
    return selected;
  }

  void _onTaxiCtaTap(HotelStay stay) {
    final destination = stay.toDiscoveryDestination(
      tenantId: widget.tenantId,
      companyId: widget.companyId,
    );
    debugPrint(
      '[hotels.discovery_handoff] type=${destination.discoveryType} '
      'name="${destination.destinationName}" '
      'provider="${destination.provider}" providerId="${destination.providerId}" '
      'lat=${destination.latitude} lng=${destination.longitude} '
      'city="${destination.city}" region="${destination.region}" country="${destination.country}"',
    );

    final destinationCallback = widget.onTaxiToDestination;
    if (destinationCallback != null) {
      destinationCallback(destination);
      return;
    }

    final callback = widget.onTaxiToStay;
    if (callback != null) {
      callback(stay);
      return;
    }

    final destinationText = _formatRoutePrefillAddress(
      rawAddress: destination.prefillDestinationText,
      label: destination.destinationName,
      city: destination.city,
      region: destination.region,
      country: destination.country,
    );
    final nav = Navigator.of(context);
    nav
        .push(
          MaterialPageRoute(
            builder: (_) => CalculatorPage(
              bookingBaseUrl: appConfig.bookingBaseUrl,
              mapboxToken: kMapboxToken,
              initialToAddress: destinationText,
              initialToLat: destination.latitude,
              initialToLng: destination.longitude,
              initialDestinationLabel: destination.destinationName,
              initialServiceId: 'passenger',
            ),
          ),
        )
        .catchError((_) {
          if (!mounted) return;
          _showThemedSnackBar(_taxiNavigationFallbackLabel);
        });
  }

  Future<void> _onNearbyEventTaxiTap(
    HotelStay stay,
    EventDetailData event,
  ) async {
    final origin = stay.toDiscoveryDestination(
      tenantId: widget.tenantId,
      companyId: widget.companyId,
    );
    final providerValue = (event.provider ?? '').trim();
    final provider = providerValue.isNotEmpty ? providerValue : 'event';
    final providerId = (event.sourceEventId ?? '').trim().isNotEmpty
        ? event.sourceEventId!.trim()
        : event.id;
    final title = event.title.trim();
    final locationName = event.locationName.trim();
    final destinationName = title.isNotEmpty
        ? title
        : (locationName.isNotEmpty ? locationName : providerId);
    final address = event.address.trim();
    final destinationAddress = address.isNotEmpty
        ? address
        : (locationName.isNotEmpty ? locationName : destinationName);
    final countryCode = (event.countryCode ?? '').trim();
    final destination = DiscoveryDestination(
      discoveryType: 'event',
      destinationName: destinationName,
      destinationAddress: destinationAddress,
      latitude: event.lat,
      longitude: event.lng,
      city: event.city,
      region: '',
      country: countryCode,
      provider: provider,
      providerId: providerId,
      tenantId: widget.tenantId,
      companyId: widget.companyId,
    );
    final originAddress = _formatRoutePrefillAddress(
      rawAddress: origin.prefillDestinationText,
      label: origin.destinationName,
      city: origin.city,
      region: origin.region,
      country: origin.country,
    );
    final formattedDestinationAddress = _formatRoutePrefillAddress(
      rawAddress: destination.prefillDestinationText,
      label: destination.destinationName,
      city: destination.city,
      region: destination.region,
      country: destination.country,
    );
    final selectedPartner = await _selectTaxiPartnerForHotelsEvent();
    if (selectedPartner == null || !mounted) return;
    final partnerId = _partnerSelectionValue(selectedPartner, 'partner_id');
    final partnerName = _partnerSelectionValue(selectedPartner, 'company_name');
    debugPrint(
      '[hotels.nearby_event_handoff] eventId=${event.id} title="${event.title}" city="${event.city}"',
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CalculatorPage(
              bookingBaseUrl: appConfig.bookingBaseUrl,
              mapboxToken: kMapboxToken,
              initialFromAddress: originAddress,
              initialFromLabel: origin.destinationName,
              initialFromLat: origin.latitude,
              initialFromLng: origin.longitude,
              initialToAddress: formattedDestinationAddress,
              initialToLat: destination.latitude,
              initialToLng: destination.longitude,
              initialDestinationLabel: destination.destinationName,
              initialServiceId: 'event',
              publicPartnerId: partnerId.isEmpty ? null : partnerId,
              publicPartnerName: partnerName.isEmpty ? null : partnerName,
            ),
          ),
        )
        .catchError((_) {
          if (!mounted) return;
          _showThemedSnackBar(_taxiNavigationFallbackLabel);
        });
  }

  void _openStayDetail(HotelStay stay) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HotelStayDetailPage(
          stay: stay,
          allStays: _allStays,
          isSaved: _isSaved(stay),
          saveLabel: _saveStayLabel,
          savedLabel: _savedStayLabel,
          onToggleSaved: () => _toggleSaved(stay),
          onNearbyEventTaxiTap: (event) {
            unawaited(_onNearbyEventTaxiTap(stay, event));
          },
          onAirportTransferTap: () {
            _onAirportTransferTap(stay);
          },
          onTaxiTap: () => _onTaxiCtaTap(stay),
          onProviderSearchTap: () => _openExternalHotelSearch(
            stay: stay,
            campaign: stay.source == 'discovery'
                ? 'fluxidi_hotels_discovery_detail'
                : 'fluxidi_hotels_real_stay_detail',
          ),
          externalAvailabilityLabel: _externalAvailabilityLabel,
        ),
      ),
    );
  }

  void _onPlanTaxiToSearchQueryTap() {
    final destinationQuery = _searchController.text.trim();
    if (destinationQuery.isEmpty) {
      _showThemedSnackBar(_destinationQueryRequiredLabel);
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CalculatorPage(
              bookingBaseUrl: appConfig.bookingBaseUrl,
              mapboxToken: kMapboxToken,
              initialToAddress: destinationQuery,
              initialServiceId: 'hotel',
            ),
          ),
        )
        .catchError((_) {
          if (!mounted) return;
          _showThemedSnackBar(_taxiNavigationFallbackLabel);
        });
  }

  Future<void> _onReturnFlowEnterAddressTap() async {
    final callback = widget.onManualHotelTaxi;
    if (callback != null) {
      await callback();
      return;
    }
    final selectedPartner = await _selectTaxiPartnerForHotelsEvent();
    if (selectedPartner == null || !mounted) return;
    final partnerId = _partnerSelectionValue(selectedPartner, 'partner_id');
    final partnerName = _partnerSelectionValue(selectedPartner, 'company_name');
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CalculatorPage(
              bookingBaseUrl: appConfig.bookingBaseUrl,
              mapboxToken: kMapboxToken,
              initialServiceId: 'hotel',
              publicPartnerId: partnerId.isEmpty ? null : partnerId,
              publicPartnerName: partnerName.isEmpty ? null : partnerName,
            ),
          ),
        )
        .catchError((_) {
          if (!mounted) return;
          _showThemedSnackBar(_taxiNavigationFallbackLabel);
        });
  }

  Future<void> _onReturnFlowAirportTap() async {
    final returnFlowCallback = widget.onOpenAirportReturnFlow;
    if (returnFlowCallback != null) {
      await returnFlowCallback();
      return;
    }
    if (!mounted) return;
    _showThemedSnackBar(_airportFlowFallbackLabel);
  }

  Future<void> _onAirportTransferTap(HotelStay stay) async {
    final callback = widget.onOpenAirportFlow;
    if (callback != null) {
      final destination = stay.toDiscoveryDestination(
        tenantId: widget.tenantId,
        companyId: widget.companyId,
      );
      await callback(destination);
      return;
    }
    if (!mounted) return;
    _showThemedSnackBar(_airportFlowFallbackLabel);
  }

  @override
  Widget build(BuildContext context) {
    final stays = _visibleStays;
    // TODO(H1-F): Real customer cards require provider API/widget or partner-approved photos.
    final approvedRealStays = stays
        .where(_isApprovedCustomerFacingStay)
        .toList(growable: false);
    final displayCards = approvedRealStays.isNotEmpty
        ? approvedRealStays
        : _discoveryRegionStays;

    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 5, 14, 18),
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 8),
                  _buildCompactFilterChips(),
                  const SizedBox(height: 8),
                  _buildResultSummary(approvedRealStays.length),
                  const SizedBox(height: 8),
                  _buildReturnFlowPanel(),
                  const SizedBox(height: 8),
                  _buildCardsGrid(displayCards),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final logoAsset = _isDarkTheme
        ? 'assets/fluxidi/fluxidi_logo_horizontal_gold.png'
        : 'assets/fluxidi/fluxidi_logo_horizontal_dark.png';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 1),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            color: _gold,
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            splashRadius: 19,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Center(
              child: Image.asset(
                logoAsset,
                height: 21,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          IconButton(
            onPressed: _openFiltersSheet,
            icon: Icon(Icons.tune_rounded, size: 18, color: _gold),
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            splashRadius: 18,
            tooltip: _t(
              nl: 'Filters',
              en: 'Filters',
              fr: 'Filtres',
              es: 'Filtros',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        hintText: _t(
          nl: 'Zoek hotel, stad of regio',
          en: 'Search hotel, city, or region',
          fr: 'Rechercher un hôtel, une ville ou une région',
          es: 'Buscar hotel, ciudad o región',
        ),
        hintStyle: TextStyle(color: _softText),
        prefixIcon: Icon(Icons.search_rounded, color: _gold),
        suffixIcon: IconButton(
          onPressed: _openFiltersSheet,
          icon: Icon(Icons.tune_rounded, color: _gold, size: 18),
          tooltip: _t(
            nl: 'Filters',
            en: 'Filters',
            fr: 'Filtres',
            es: 'Filtros',
          ),
        ),
        filled: true,
        fillColor: _panelBlack,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold, width: 1.2),
        ),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _selectedCountryCode != _allKey ||
      _selectedRegionKey != _allKey ||
      _selectedSettlementKey != _allKey ||
      _selectedType != _allKey;

  String get _selectedCountryLabel {
    if (_selectedCountryCode == _allKey) return _allCountriesLabel;
    for (final option in _countryOptions) {
      if (option.value == _selectedCountryCode) return option.label;
    }
    return _allCountriesLabel;
  }

  String get _selectedRegionLabel {
    if (_selectedRegionKey == _allKey) return _allRegionsLabel;
    for (final option in _regionOptions) {
      if (option.value == _selectedRegionKey) return option.label;
    }
    return _allRegionsLabel;
  }

  String get _selectedCityLabel {
    if (_selectedSettlementKey == _allKey) return _allCitiesLabel;
    for (final option in _settlementOptions) {
      if (option.value == _selectedSettlementKey) return option.label;
    }
    return _allCitiesLabel;
  }

  Future<void> _openCountryPicker() async {
    final options = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _allCountriesLabel),
      ..._countryOptions,
    ];
    final selected = await _openFilterPicker(
      title: _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
      options: options,
      currentValue: _selectedCountryCode,
    );
    if (selected == null) return;
    setState(() {
      _selectedCountryCode = selected;
      _selectedRegionKey = _allKey;
      _selectedSettlementKey = _allKey;
    });
  }

  Future<void> _openRegionPicker() async {
    if (_selectedCountryCode == _allKey) return;
    final options = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _allRegionsLabel),
      ..._regionOptions,
    ];
    final selected = await _openFilterPicker(
      title: _t(nl: 'Regio', en: 'Region', fr: 'Région', es: 'Región'),
      options: options,
      currentValue: _selectedRegionKey,
    );
    if (selected == null) return;
    setState(() {
      _selectedRegionKey = selected;
      _selectedSettlementKey = _allKey;
    });
  }

  Future<void> _openSettlementPicker() async {
    if (_selectedCountryCode == _allKey || _selectedRegionKey == _allKey)
      return;
    final options = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _allCitiesLabel),
      ..._settlementOptions,
    ];
    final selected = await _openFilterPicker(
      title: _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad'),
      options: options,
      currentValue: _selectedSettlementKey,
    );
    if (selected == null) return;
    setState(() => _selectedSettlementKey = selected);
  }

  Future<void> _openTypePicker() async {
    final options = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _typeLabel(_allKey)),
      HotelGeoOption(
        value: HotelStayType.hotel,
        label: _typeLabel(HotelStayType.hotel),
      ),
      HotelGeoOption(
        value: HotelStayType.bedAndBreakfast,
        label: _typeLabel(HotelStayType.bedAndBreakfast),
      ),
      HotelGeoOption(
        value: HotelStayType.aparthotel,
        label: _typeLabel(HotelStayType.aparthotel),
      ),
      HotelGeoOption(
        value: HotelStayType.guesthouse,
        label: _typeLabel(HotelStayType.guesthouse),
      ),
    ];
    final selected = await _openFilterPicker(
      title: _t(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo'),
      options: options,
      currentValue: _selectedType,
    );
    if (selected == null) return;
    setState(() => _selectedType = selected);
  }

  Future<String?> _openFilterPicker({
    required String title,
    required List<HotelGeoOption> options,
    required String currentValue,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => Divider(
                      color: _border.withOpacity(_isDarkTheme ? 0.3 : 0.95),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected = option.value == currentValue;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          option.label,
                          style: TextStyle(
                            color: isSelected ? _gold : _textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(option.value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFiltersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Filters',
                    en: 'Filters',
                    fr: 'Filtres',
                    es: 'Filtros',
                  ),
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: Icon(
                    Icons.public_rounded,
                    color: _gold.withOpacity(0.95),
                  ),
                  title: Text(
                    _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
                    style: TextStyle(color: _textPrimary),
                  ),
                  subtitle: Text(
                    _selectedCountryLabel,
                    style: TextStyle(color: _softText.withOpacity(0.9)),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _openCountryPicker();
                  },
                ),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: Icon(
                    Icons.map_outlined,
                    color: _gold.withOpacity(0.95),
                  ),
                  title: Text(
                    _t(nl: 'Regio', en: 'Region', fr: 'Région', es: 'Región'),
                    style: TextStyle(color: _textPrimary),
                  ),
                  subtitle: Text(
                    _selectedRegionLabel,
                    style: TextStyle(color: _softText.withOpacity(0.9)),
                  ),
                  onTap: _selectedCountryCode == _allKey
                      ? null
                      : () async {
                          Navigator.of(sheetContext).pop();
                          await _openRegionPicker();
                        },
                ),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: Icon(
                    Icons.location_city_rounded,
                    color: _gold.withOpacity(0.95),
                  ),
                  title: Text(
                    _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad'),
                    style: TextStyle(color: _textPrimary),
                  ),
                  subtitle: Text(
                    _selectedCityLabel,
                    style: TextStyle(color: _softText.withOpacity(0.9)),
                  ),
                  onTap:
                      (_selectedCountryCode == _allKey ||
                          _selectedRegionKey == _allKey)
                      ? null
                      : () async {
                          Navigator.of(sheetContext).pop();
                          await _openSettlementPicker();
                        },
                ),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  leading: Icon(
                    Icons.hotel_rounded,
                    color: _gold.withOpacity(0.95),
                  ),
                  title: Text(
                    _t(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo'),
                    style: TextStyle(color: _textPrimary),
                  ),
                  subtitle: Text(
                    _typeLabel(_selectedType),
                    style: TextStyle(color: _softText.withOpacity(0.9)),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _openTypePicker();
                  },
                ),
                if (_hasActiveFilters) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _resetAllFilters();
                      },
                      icon: Icon(Icons.restart_alt_rounded, color: _gold),
                      label: Text(
                        _t(
                          nl: 'Filters wissen',
                          en: 'Clear filters',
                          fr: 'Effacer filtres',
                          es: 'Borrar filtros',
                        ),
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _resetAllFilters() {
    setState(() {
      _selectedCountryCode = _allKey;
      _selectedRegionKey = _allKey;
      _selectedSettlementKey = _allKey;
      _selectedType = _allKey;
    });
  }

  Widget _buildCompactFilterChips() {
    final hasCountrySelection = _selectedCountryCode != _allKey;
    final hasRegionSelection =
        hasCountrySelection && _selectedRegionKey != _allKey;
    return LayoutBuilder(
      builder: (context, constraints) {
        final landChip = _buildFilterChip(
          label: _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
          value: _selectedCountryLabel,
          onTap: _openCountryPicker,
        );
        final cityChip = _buildFilterChip(
          label: _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad'),
          value: _selectedCityLabel,
          onTap: hasRegionSelection ? _openSettlementPicker : null,
        );
        final regionChip = _buildFilterChip(
          label: _t(nl: 'Regio', en: 'Region', fr: 'Région', es: 'Región'),
          value: _selectedRegionLabel,
          onTap: hasCountrySelection ? _openRegionPicker : null,
        );
        final typeChip = _buildFilterChip(
          label: _t(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo'),
          value: _typeLabel(_selectedType),
          onTap: _openTypePicker,
          emphasize: _selectedType != _allKey,
        );

        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: landChip),
                  const SizedBox(width: 6),
                  Expanded(child: cityChip),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: regionChip),
                  const SizedBox(width: 6),
                  Expanded(child: typeChip),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: landChip),
            const SizedBox(width: 6),
            Expanded(child: cityChip),
            const SizedBox(width: 6),
            Expanded(child: regionChip),
            const SizedBox(width: 6),
            Expanded(child: typeChip),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required VoidCallback? onTap,
    bool emphasize = false,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: emphasize ? _gold : _panelBlack,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: emphasize
                ? _gold
                : _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                '$label: $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: emphasize
                      ? _actionOnGold
                      : (enabled ? _textPrimary : _softText.withOpacity(0.8)),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.4,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: emphasize
                  ? _actionOnGold
                  : (enabled ? _gold : _softText.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    final hasCountrySelection = _selectedCountryCode != _allKey;
    final hasRegionSelection =
        hasCountrySelection && _selectedRegionKey != _allKey;
    final countryOptions = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _allCountriesLabel),
      ..._countryOptions,
    ];
    final regionOptions = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _allRegionsLabel),
      ..._regionOptions,
    ];
    final settlementOptions = <HotelGeoOption>[
      HotelGeoOption(value: _allKey, label: _allCitiesLabel),
      ..._settlementOptions,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _shadow.withOpacity(_isDarkTheme ? 0.18 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdownFilter(
                  label: _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
                  value: _selectedCountryCode,
                  options: countryOptions,
                  onChanged: (value) {
                    setState(() {
                      _selectedCountryCode = value ?? _allKey;
                      if (_selectedCountryCode == _allKey) {
                        _selectedRegionKey = _allKey;
                        _selectedSettlementKey = _allKey;
                      } else {
                        _selectedRegionKey = _allKey;
                        _selectedSettlementKey = _allKey;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownFilter(
                  label: _t(
                    nl: 'Regio',
                    en: 'Region',
                    fr: 'Région',
                    es: 'Región',
                  ),
                  value: _selectedRegionKey,
                  options: regionOptions,
                  enabled: hasCountrySelection,
                  onChanged: (value) {
                    setState(() {
                      _selectedRegionKey = value ?? _allKey;
                      _selectedSettlementKey = _allKey;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDropdownFilter(
            label: _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad'),
            value: _selectedSettlementKey,
            options: settlementOptions,
            enabled: hasRegionSelection,
            onChanged: (value) =>
                setState(() => _selectedSettlementKey = value ?? _allKey),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children:
                <String>[
                  _allKey,
                  HotelStayType.hotel,
                  HotelStayType.bedAndBreakfast,
                  HotelStayType.aparthotel,
                  HotelStayType.guesthouse,
                ].map((typeKey) {
                  final isSelected = _selectedType == typeKey;
                  return ChoiceChip(
                    selected: isSelected,
                    label: Text(
                      _typeLabel(typeKey),
                      style: TextStyle(
                        color: isSelected ? _actionOnGold : _textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: _panelBlack,
                    selectedColor: _gold,
                    side: BorderSide(
                      color: isSelected
                          ? _gold
                          : _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
                    ),
                    onSelected: (_) => setState(() => _selectedType = typeKey),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<HotelGeoOption> options,
    required void Function(String? value) onChanged,
    bool enabled = true,
  }) {
    final effectiveValue = options.any((option) => option.value == value)
        ? value
        : _allKey;
    return DropdownButtonFormField<String>(
      value: effectiveValue,
      isExpanded: true,
      dropdownColor: _panelBlack,
      iconEnabledColor: enabled ? _gold : _softText.withOpacity(0.7),
      style: TextStyle(
        color: enabled ? _textPrimary : _softText.withOpacity(0.8),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: _softText.withOpacity(0.95),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        isDense: true,
        filled: true,
        fillColor: _panelBlack,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _gold, width: 1.1),
        ),
      ),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.value,
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _buildResultSummary(int count) {
    final text = _t(
      nl: '$count verblijven gevonden',
      en: '$count stays found',
      fr: '$count séjours trouvés',
      es: '$count alojamientos encontrados',
    );
    return Row(
      children: [
        Icon(Icons.hotel_rounded, size: 14, color: _gold.withOpacity(0.95)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: _gold.withOpacity(0.95),
              fontWeight: FontWeight.w700,
              fontSize: 11.8,
            ),
          ),
        ),
        if (_hasActiveFilters)
          TextButton(
            onPressed: _resetAllFilters,
            style: TextButton.styleFrom(
              foregroundColor: _gold,
              visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _t(nl: 'Wis', en: 'Clear', fr: 'Effacer', es: 'Borrar'),
              style: const TextStyle(
                fontSize: 11.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReturnFlowPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.route_rounded,
                color: _gold.withOpacity(0.95),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _returnFlowTitle,
                      style: TextStyle(
                        color: _textPrimary.withOpacity(0.96),
                        fontSize: 13.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _returnFlowSubtitle,
                      style: TextStyle(
                        color: _softText.withOpacity(0.96),
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => unawaited(_onReturnFlowEnterAddressTap()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _actionOnGold,
                minimumSize: const Size.fromHeight(39),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
              label: Text(
                _returnFlowEnterAddressLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_onReturnFlowAirportTap()),
              style: OutlinedButton.styleFrom(
                backgroundColor: _panelBlack,
                foregroundColor: _textPrimary.withOpacity(0.92),
                side: BorderSide(
                  color: _border.withOpacity(_isDarkTheme ? 0.4 : 1),
                ),
                minimumSize: const Size.fromHeight(36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(
                Icons.flight_land_rounded,
                size: 15,
                color: _gold.withOpacity(0.92),
              ),
              label: Text(
                _returnFlowAirportToStayLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeDiscoveryPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                color: _gold.withOpacity(0.95),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _safeDiscoveryCopy,
                  style: TextStyle(
                    color: _textPrimary.withOpacity(0.96),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _onPlanTaxiToSearchQueryTap,
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _actionOnGold,
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.local_taxi_rounded, size: 18),
              label: Text(
                _planTaxiToStayLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openExternalHotelSearch(
                campaign: 'fluxidi_hotels_discovery',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _textPrimary,
                side: BorderSide(color: _gold.withOpacity(0.42)),
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(Icons.open_in_new_rounded, size: 16, color: _gold),
              label: Text(
                _externalAvailabilityLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsGrid(List<HotelStay> stays) {
    if (stays.isEmpty) {
      return _buildSafeDiscoveryPanel();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : (constraints.maxWidth >= 620 ? 2 : 1);
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < stays.length; i++) ...[
                _buildStayCard(stays[i]),
                if (i != stays.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final safeMainAxisExtent = (392.0 * textScale).clamp(392.0, 500.0);
        const spacing = 8.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stays.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: safeMainAxisExtent,
          ),
          itemBuilder: (_, index) => _buildStayCard(stays[index]),
        );
      },
    );
  }

  Widget _buildStayCard(HotelStay stay) {
    final premium = _isPremiumStay(stay);
    final displayPrice = _displayPriceHint(stay);
    final highlights = _semanticHighlights(stay);
    final imageUrl = (stay.imageUrl ?? '').trim();
    final approvedAssetPath = _approvedAssetPath(stay);
    final isDiscoveryCard = stay.source == 'discovery';
    final canShowTaxiCta = _canShowStayTaxiCta(stay);
    final isSaved = _isSaved(stay);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openStayDetail(stay),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _panelBlack,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _shadow.withOpacity(_isDarkTheme ? 0.2 : 0.1),
                blurRadius: 14,
                spreadRadius: 0.2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF2C394E), Color(0xFF162033)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.black.withOpacity(0.12),
                              Colors.black.withOpacity(0.24),
                              Colors.black.withOpacity(0.58),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _gold.withOpacity(0.9),
                                        ),
                                      ),
                                    );
                                  },
                              errorBuilder: (_, __, ___) =>
                                  approvedAssetPath.isNotEmpty
                                  ? Image.asset(
                                      approvedAssetPath,
                                      fit: BoxFit.cover,
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.hotel_rounded,
                                        size: 50,
                                        color: _gold.withOpacity(0.92),
                                      ),
                                    ),
                            )
                          : (approvedAssetPath.isNotEmpty
                                ? Image.asset(
                                    approvedAssetPath,
                                    fit: BoxFit.cover,
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.hotel_rounded,
                                      size: 50,
                                      color: _gold.withOpacity(0.92),
                                    ),
                                  )),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.black.withOpacity(0.16),
                              Colors.black.withOpacity(0.34),
                              Colors.black.withOpacity(0.62),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _gold.withOpacity(0.45)),
                        ),
                        child: Text(
                          _typeLabel(stay.type),
                          style: TextStyle(
                            color: _gold,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (stay.rating != null)
                      Positioned(
                        right: 52,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.38),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _gold.withOpacity(0.44)),
                          ),
                          child: Text(
                            '★ ${stay.rating!.toStringAsFixed(1)}',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (!isDiscoveryCard)
                      Positioned(
                        right: 8,
                        top: 6,
                        child: IconButton(
                          onPressed: () => _toggleSaved(stay),
                          tooltip: isSaved ? _savedStayLabel : _saveStayLabel,
                          icon: Icon(
                            isSaved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isSaved
                                ? _gold
                                : _textPrimary.withOpacity(0.9),
                            size: 22,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.35),
                            side: BorderSide(color: _gold.withOpacity(0.34)),
                          ),
                        ),
                      ),
                    if (premium)
                      Positioned(
                        left: 10,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _gold.withOpacity(0.62)),
                          ),
                          child: Text(
                            _recommendedLabel,
                            style: TextStyle(
                              color: _gold,
                              fontSize: 10.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stay.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stay.city}, ${stay.region}, ${stay.country}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _gold.withOpacity(0.92),
                          fontSize: 11.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isDiscoveryCard
                            ? _t(
                                nl: 'Ontdek verblijven en plan je rit.',
                                en: 'Discover stays and plan your ride.',
                                fr: 'Découvrez des hébergements et planifiez votre trajet.',
                                es: 'Descubre alojamientos y planifica tu trayecto.',
                              )
                            : stay.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _softText,
                          fontSize: 11.4,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      if (highlights.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: highlights
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _panelBlack,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _border.withOpacity(
                                        _isDarkTheme ? 0.4 : 1,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _textPrimary.withOpacity(0.82),
                                      fontSize: 10.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      if (displayPrice.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          displayPrice,
                          style: TextStyle(
                            color: _gold,
                            fontSize: 11.7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isDiscoveryCard || !canShowTaxiCta)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _openStayDetail(stay),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _actionOnGold,
                              minimumSize: const Size.fromHeight(39),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            icon: const Icon(
                              Icons.visibility_rounded,
                              size: 16,
                            ),
                            label: Text(
                              isDiscoveryCard
                                  ? _viewOptionsLabel
                                  : _viewStayLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _onTaxiCtaTap(stay),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _actionOnGold,
                              minimumSize: const Size.fromHeight(39),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            icon: const Icon(
                              Icons.local_taxi_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _t(
                                nl: 'Taxi naar dit verblijf',
                                en: 'Taxi to this stay',
                                fr: 'Taxi vers cet hébergement',
                                es: 'Taxi a este alojamiento',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openStayDetail(stay),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _panelBlack,
                              foregroundColor: _textPrimary.withOpacity(0.92),
                              side: BorderSide(
                                color: _border.withOpacity(
                                  _isDarkTheme ? 0.4 : 1,
                                ),
                              ),
                              minimumSize: const Size.fromHeight(36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              Icons.visibility_rounded,
                              size: 15,
                              color: _gold.withOpacity(0.92),
                            ),
                            label: Text(
                              _viewStayLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HotelNearbyEventRadiusMode { auto, km15, km30, km50, wider }

class HotelStayDetailPage extends StatelessWidget {
  const HotelStayDetailPage({
    required this.stay,
    required this.allStays,
    required this.isSaved,
    required this.saveLabel,
    required this.savedLabel,
    required this.onToggleSaved,
    required this.onNearbyEventTaxiTap,
    required this.onAirportTransferTap,
    required this.onTaxiTap,
    required this.onProviderSearchTap,
    required this.externalAvailabilityLabel,
    super.key,
  });

  final HotelStay stay;
  final List<HotelStay> allStays;
  final bool isSaved;
  final String saveLabel;
  final String savedLabel;
  final VoidCallback onToggleSaved;
  final void Function(EventDetailData event) onNearbyEventTaxiTap;
  final VoidCallback onAirportTransferTap;
  final VoidCallback onTaxiTap;
  final VoidCallback onProviderSearchTap;
  final String externalAvailabilityLabel;
  CustomerThemePalette get _themePalette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _themePalette.isDark;
  Color get _bgBlack => _themePalette.background;
  Color get _panelBlack => _themePalette.surface;
  Color get _gold => _themePalette.gold;
  Color get _softText => _themePalette.textMuted;
  Color get _textPrimary => _themePalette.textPrimary;
  Color get _border => _themePalette.border;
  Color get _shadow => _themePalette.shadow;
  Color get _actionOnGold =>
      _isDarkTheme ? Colors.black : const Color(0xFF1F1706);

  String get _languageCode => appConfig.currentLanguage.name;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_languageCode) {
      case 'en':
        return en;
      case 'fr':
        return fr;
      case 'es':
        return es;
      case 'nl':
      default:
        return nl;
    }
  }

  String _typeLabel(String typeKey) {
    if (typeKey == HotelStayType.aparthotel) {
      return _t(
        nl: 'Aparthotel',
        en: 'Aparthotel',
        fr: 'Aparthotel',
        es: 'Aparthotel',
      );
    }
    if (typeKey == HotelStayType.guesthouse) {
      return _t(
        nl: 'Guesthouse',
        en: 'Guesthouse',
        fr: 'Guesthouse',
        es: 'Guesthouse',
      );
    }
    if (typeKey == HotelStayType.hotel) return 'Hotel';
    if (typeKey == HotelStayType.bedAndBreakfast) {
      return discoveryStayTypeLabel(
        HotelStayType.bedAndBreakfast,
        (nl, en, fr, es) => _t(nl: nl, en: en, fr: fr, es: es),
      );
    }
    return typeKey;
  }

  String get _fromLabel {
    return _t(nl: 'Vanaf', en: 'From', fr: 'À partir de', es: 'Desde');
  }

  String get _externalAvailabilityHint {
    return _t(
      nl: 'Beschikbaarheid en prijzen worden extern getoond.',
      en: 'Availability and prices are shown externally.',
      fr: 'Les disponibilités et les prix sont affichés en externe.',
      es: 'La disponibilidad y los precios se muestran externamente.',
    );
  }

  String get _taxiLabel {
    return _t(
      nl: 'Taxi naar dit verblijf',
      en: 'Taxi to this stay',
      fr: 'Taxi vers cet hébergement',
      es: 'Taxi a este alojamiento',
    );
  }

  String get _airportTransferLabel {
    return _t(
      nl: 'Luchthaven transfer',
      en: 'Airport transfer',
      fr: 'Transfert aeroport',
      es: 'Transfer al aeropuerto',
    );
  }

  String get _highlightsLabel {
    return _t(
      nl: 'Highlights',
      en: 'Highlights',
      fr: 'Points forts',
      es: 'Destacados',
    );
  }

  String get _providerLabel {
    return _t(nl: 'Bron', en: 'Source', fr: 'Source', es: 'Fuente');
  }

  String get _nearbyEventsLabel {
    return _t(
      nl: 'Evenementen in de buurt',
      en: 'Nearby events',
      fr: 'Événements à proximité',
      es: 'Eventos cercanos',
    );
  }

  String get _eventTaxiLabel {
    return _t(
      nl: 'Taxi naar dit event',
      en: 'Taxi to this event',
      fr: 'Taxi vers cet événement',
      es: 'Taxi a este evento',
    );
  }

  String _distanceLabel(EventDetailData event) {
    if (event.isDistanceLabelTrusted) {
      final trusted = (event.distanceLabel ?? '').trim();
      if (trusted.isNotEmpty) return trusted;
    }
    return '';
  }

  bool _hasValidCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    return true;
  }

  double _degToRad(double value) => value * (math.pi / 180.0);

  double _distanceKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(toLat - fromLat);
    final dLng = _degToRad(toLng - fromLng);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(fromLat)) *
            math.cos(_degToRad(toLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  String _radiusModeLabel(_HotelNearbyEventRadiusMode mode) {
    switch (mode) {
      case _HotelNearbyEventRadiusMode.auto:
        return _t(nl: 'Auto', en: 'Auto', fr: 'Auto', es: 'Auto');
      case _HotelNearbyEventRadiusMode.km15:
        return '15 km';
      case _HotelNearbyEventRadiusMode.km30:
        return '30 km';
      case _HotelNearbyEventRadiusMode.km50:
        return '50 km';
      case _HotelNearbyEventRadiusMode.wider:
        return _t(
          nl: 'België / Breder',
          en: 'Belgium / Wider',
          fr: 'Belgique / Plus large',
          es: 'Bélgica / Más amplio',
        );
    }
  }

  String get _noNearbyEventsLabel {
    return _t(
      nl: 'Geen events binnen deze straal.',
      en: 'No events within this radius.',
      fr: 'Aucun événement dans ce rayon.',
      es: 'No hay eventos dentro de este radio.',
    );
  }

  List<EventDetailData> _nearbyEventsForRadiusMode(
    _HotelNearbyEventRadiusMode mode,
  ) {
    final stayCity = normalizeDiscoveryText(stay.city);
    final stayRegion = normalizeDiscoveryText(stay.region);
    final stayCountry = normalizeDiscoveryText(stay.country);
    final stayLat = stay.latitude ?? stay.lat;
    final stayLng = stay.longitude ?? stay.lng;
    final canDistanceRank = _hasValidCoordinates(stayLat, stayLng);

    final sameCity = <EventDetailData>[
      for (final event in kEventSeedData)
        if (normalizeDiscoveryText(event.city) == stayCity) event,
    ];

    final regionCities = allStays
        .where((item) => normalizeDiscoveryText(item.region) == stayRegion)
        .map((item) => normalizeDiscoveryText(item.city))
        .where((city) => city.isNotEmpty)
        .toSet();
    final sameRegion = <EventDetailData>[
      for (final event in kEventSeedData)
        if (regionCities.contains(normalizeDiscoveryText(event.city))) event,
    ];

    final distanceRanked = <({EventDetailData event, double km})>[
      for (final event in kEventSeedData)
        if (canDistanceRank && _hasValidCoordinates(event.lat, event.lng))
          (
            event: event,
            km: _distanceKm(
              fromLat: stayLat,
              fromLng: stayLng,
              toLat: event.lat,
              toLng: event.lng,
            ),
          ),
    ]..sort((a, b) => a.km.compareTo(b.km));
    List<EventDetailData> withinKm(double maxKm) {
      return <EventDetailData>[
        for (final item in distanceRanked)
          if (item.km <= maxKm) item.event,
      ];
    }

    final countryRanked =
        <({EventDetailData event, double? km})>[
          for (final event in kEventSeedData)
            if (normalizeDiscoveryText(event.countryCode ?? '') ==
                    stayCountry ||
                (stayCountry == 'belgium' &&
                    normalizeDiscoveryText(event.address).contains('belg')))
              (
                event: event,
                km:
                    (canDistanceRank &&
                        _hasValidCoordinates(event.lat, event.lng))
                    ? _distanceKm(
                        fromLat: stayLat,
                        fromLng: stayLng,
                        toLat: event.lat,
                        toLng: event.lng,
                      )
                    : null,
              ),
        ]..sort((a, b) {
          final left = a.km ?? double.infinity;
          final right = b.km ?? double.infinity;
          return left.compareTo(right);
        });
    final countryFallback = <EventDetailData>[
      for (final item in countryRanked) item.event,
    ];

    switch (mode) {
      case _HotelNearbyEventRadiusMode.auto:
        final localOnly = <EventDetailData>[
          ...sameCity,
          ...sameRegion,
          ...withinKm(25),
          ...withinKm(50),
        ];
        final localResults = topUniqueById(
          items: localOnly,
          idOf: (event) => event.id,
          limit: 3,
        );
        if (localResults.isNotEmpty) return localResults;
        return topUniqueById(
          items: countryFallback,
          idOf: (event) => event.id,
          limit: 3,
        );
      case _HotelNearbyEventRadiusMode.km15:
        if (!canDistanceRank) {
          return topUniqueById(
            items: <EventDetailData>[...sameCity, ...sameRegion],
            idOf: (event) => event.id,
            limit: 3,
          );
        }
        return topUniqueById(
          items: withinKm(15),
          idOf: (event) => event.id,
          limit: 3,
        );
      case _HotelNearbyEventRadiusMode.km30:
        if (!canDistanceRank) {
          return topUniqueById(
            items: <EventDetailData>[...sameCity, ...sameRegion],
            idOf: (event) => event.id,
            limit: 3,
          );
        }
        return topUniqueById(
          items: withinKm(30),
          idOf: (event) => event.id,
          limit: 3,
        );
      case _HotelNearbyEventRadiusMode.km50:
        if (!canDistanceRank) {
          return topUniqueById(
            items: <EventDetailData>[...sameCity, ...sameRegion],
            idOf: (event) => event.id,
            limit: 3,
          );
        }
        return topUniqueById(
          items: withinKm(50),
          idOf: (event) => event.id,
          limit: 3,
        );
      case _HotelNearbyEventRadiusMode.wider:
        return topUniqueById(
          items: <EventDetailData>[
            ...sameCity,
            ...sameRegion,
            ...withinKm(50),
            ...countryFallback,
          ],
          idOf: (event) => event.id,
          limit: 3,
        );
    }
  }

  List<String> _highlights() {
    final values = <String>[...stay.tags, ...stay.travelStyles];
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isEmpty) continue;
      final key = normalized.toLowerCase();
      if (!seen.add(key)) continue;
      result.add(normalized);
      if (result.length >= 8) break;
    }
    return result;
  }

  String _displayPriceHint() {
    return formatDiscoveryPriceHint(stay.priceHint, fromLabel: _fromLabel);
  }

  String _approvedAssetPath() {
    final imageRef = stay.imageRef.trim();
    if (!imageRef.startsWith('approved_asset:')) return '';
    return imageRef.substring('approved_asset:'.length).trim();
  }

  Widget _buildNearbyEventCard(BuildContext context, EventDetailData event) {
    final distance = _distanceLabel(event);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EventDetailPage(
                event: event,
                onBookEvent: onNearbyEventTaxiTap,
              ),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: _panelBlack,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${event.category} • ${event.dateTimeLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _gold.withOpacity(0.95),
                  fontSize: 11.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${event.locationName}, ${event.city}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _softText,
                  fontSize: 11.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (distance.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  distance,
                  style: TextStyle(
                    color: _softText.withOpacity(0.9),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onNearbyEventTaxiTap(event),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _panelBlack,
                    foregroundColor: _textPrimary.withOpacity(0.93),
                    side: BorderSide(
                      color: _border.withOpacity(_isDarkTheme ? 0.4 : 1),
                    ),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(
                    Icons.local_taxi_rounded,
                    size: 16,
                    color: _gold.withOpacity(0.92),
                  ),
                  label: Text(
                    _eventTaxiLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = (stay.imageUrl ?? '').trim();
    final isDiscoveryCard = stay.source == 'discovery';
    final canShowTaxiCta =
        stay.isRealApproved &&
        !isDiscoveryCard &&
        (stay.address.trim().isNotEmpty ||
            stay.city.trim().isNotEmpty ||
            (((stay.latitude ?? stay.lat).isFinite &&
                    (stay.longitude ?? stay.lng).isFinite) &&
                (stay.latitude ?? stay.lat) >= -90 &&
                (stay.latitude ?? stay.lat) <= 90 &&
                (stay.longitude ?? stay.lng) >= -180 &&
                (stay.longitude ?? stay.lng) <= 180));
    final canShowAirportTransferCta = canShowTaxiCta;
    final approvedAssetPath = _approvedAssetPath();
    final displayPrice = _displayPriceHint();
    final highlights = _highlights();
    final hasAnyNearbyEvents = _nearbyEventsForRadiusMode(
      _HotelNearbyEventRadiusMode.wider,
    ).isNotEmpty;
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (_, __, ___) => Scaffold(
        backgroundColor: _bgBlack,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: _gold,
                          tooltip: _t(
                            nl: 'Terug',
                            en: 'Back',
                            fr: 'Retour',
                            es: 'Volver',
                          ),
                        ),
                      ],
                    ),
                    Container(
                      height: 248,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: _panelBlack,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _border.withOpacity(
                            _isDarkTheme ? 0.35 : 0.95,
                          ),
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0xFF22314C), Color(0xFF101828)],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Center(
                                        child: SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: _gold.withOpacity(0.9),
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) =>
                                        approvedAssetPath.isNotEmpty
                                        ? Image.asset(
                                            approvedAssetPath,
                                            fit: BoxFit.cover,
                                          )
                                        : Center(
                                            child: Icon(
                                              Icons.hotel_rounded,
                                              color: _gold.withOpacity(0.95),
                                              size: 64,
                                            ),
                                          ),
                                  )
                                : (approvedAssetPath.isNotEmpty
                                      ? Image.asset(
                                          approvedAssetPath,
                                          fit: BoxFit.cover,
                                        )
                                      : Center(
                                          child: Icon(
                                            Icons.hotel_rounded,
                                            color: _gold.withOpacity(0.95),
                                            size: 64,
                                          ),
                                        )),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Colors.black.withOpacity(0.16),
                                    Colors.black.withOpacity(0.34),
                                    Colors.black.withOpacity(0.66),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.34),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _gold.withOpacity(0.44),
                                ),
                              ),
                              child: Text(
                                _typeLabel(stay.type),
                                style: TextStyle(
                                  color: _gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          if (stay.rating != null)
                            Positioned(
                              right: 12,
                              top: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.36),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _gold.withOpacity(0.44),
                                  ),
                                ),
                                child: Text(
                                  '★ ${stay.rating!.toStringAsFixed(1)}',
                                  style: TextStyle(
                                    color: _gold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: _panelBlack,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _border.withOpacity(
                            _isDarkTheme ? 0.35 : 0.95,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  stay.name,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: onToggleSaved,
                                tooltip: isSaved ? savedLabel : saveLabel,
                                icon: Icon(
                                  isSaved
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: isSaved
                                      ? _gold
                                      : _textPrimary.withOpacity(0.92),
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: _panelBlack,
                                  side: BorderSide(
                                    color: _border.withOpacity(
                                      _isDarkTheme ? 0.4 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${stay.city}, ${stay.region}, ${stay.country}',
                            style: TextStyle(
                              color: _gold.withOpacity(0.92),
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (displayPrice.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              displayPrice,
                              style: TextStyle(
                                color: _gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            stay.description,
                            style: TextStyle(
                              color: _softText,
                              fontSize: 13.2,
                              height: 1.3,
                            ),
                          ),
                          if (highlights.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _highlightsLabel,
                              style: TextStyle(
                                color: _gold.withOpacity(0.9),
                                fontSize: 12.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 7,
                              runSpacing: 6,
                              children: highlights
                                  .map(
                                    (tag) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _panelBlack,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: _border.withOpacity(
                                            _isDarkTheme ? 0.4 : 1,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          color: _textPrimary.withOpacity(0.82),
                                          fontSize: 11.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            '$_providerLabel: ${stay.effectiveProvider}',
                            style: TextStyle(
                              color: _softText.withOpacity(0.95),
                              fontSize: 11.7,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasAnyNearbyEvents) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: BoxDecoration(
                          color: _panelBlack,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _border.withOpacity(
                              _isDarkTheme ? 0.35 : 0.95,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nearbyEventsLabel,
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 16.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _HotelNearbyEventsSection(
                              modeLabelBuilder: _radiusModeLabel,
                              noEventsText: _noNearbyEventsLabel,
                              eventsForMode: _nearbyEventsForRadiusMode,
                              buildCard: (event) =>
                                  _buildNearbyEventCard(context, event),
                              gold: _gold,
                              softText: _softText,
                              panelColor: _panelBlack,
                              textPrimary: _textPrimary,
                              borderColor: _border,
                              actionOnGold: _actionOnGold,
                              isDarkTheme: _isDarkTheme,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: [
                    if (canShowTaxiCta) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onTaxiTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: _actionOnGold,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.local_taxi_rounded, size: 17),
                          label: Text(
                            _taxiLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onProviderSearchTap,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _panelBlack,
                          foregroundColor: _textPrimary.withOpacity(0.94),
                          side: BorderSide(
                            color: _border.withOpacity(_isDarkTheme ? 0.4 : 1),
                          ),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          size: 16,
                          color: _gold.withOpacity(0.92),
                        ),
                        label: Text(
                          externalAvailabilityLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _externalAvailabilityHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _softText.withOpacity(0.9),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (canShowAirportTransferCta) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onAirportTransferTap,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _panelBlack,
                            foregroundColor: _textPrimary.withOpacity(0.94),
                            side: BorderSide(
                              color: _border.withOpacity(
                                _isDarkTheme ? 0.4 : 1,
                              ),
                            ),
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            Icons.flight_takeoff_rounded,
                            size: 16,
                            color: _gold.withOpacity(0.92),
                          ),
                          label: Text(
                            _airportTransferLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotelNearbyEventsSection extends StatefulWidget {
  const _HotelNearbyEventsSection({
    required this.modeLabelBuilder,
    required this.noEventsText,
    required this.eventsForMode,
    required this.buildCard,
    required this.gold,
    required this.softText,
    required this.panelColor,
    required this.textPrimary,
    required this.borderColor,
    required this.actionOnGold,
    required this.isDarkTheme,
  });

  final String Function(_HotelNearbyEventRadiusMode mode) modeLabelBuilder;
  final String noEventsText;
  final List<EventDetailData> Function(_HotelNearbyEventRadiusMode mode)
  eventsForMode;
  final Widget Function(EventDetailData event) buildCard;
  final Color gold;
  final Color softText;
  final Color panelColor;
  final Color textPrimary;
  final Color borderColor;
  final Color actionOnGold;
  final bool isDarkTheme;

  @override
  State<_HotelNearbyEventsSection> createState() =>
      _HotelNearbyEventsSectionState();
}

class _HotelNearbyEventsSectionState extends State<_HotelNearbyEventsSection> {
  _HotelNearbyEventRadiusMode _selectedMode = _HotelNearbyEventRadiusMode.auto;

  @override
  Widget build(BuildContext context) {
    final events = widget.eventsForMode(_selectedMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: _HotelNearbyEventRadiusMode.values.map((mode) {
            final isSelected = _selectedMode == mode;
            return ChoiceChip(
              label: Text(widget.modeLabelBuilder(mode)),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedMode = mode;
                });
              },
              backgroundColor: widget.panelColor,
              selectedColor: widget.gold,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: isSelected
                      ? widget.gold
                      : widget.borderColor.withOpacity(
                          widget.isDarkTheme ? 0.35 : 1,
                        ),
                ),
              ),
              labelStyle: TextStyle(
                color: isSelected
                    ? widget.actionOnGold
                    : widget.textPrimary.withOpacity(0.92),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              visualDensity: const VisualDensity(
                horizontal: -2.0,
                vertical: -2.0,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          Text(
            widget.noEventsText,
            style: TextStyle(
              color: widget.softText.withOpacity(0.9),
              fontSize: 12.2,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          for (var i = 0; i < events.length; i++) ...[
            widget.buildCard(events[i]),
            if (i != events.length - 1) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// Generic local saved-ID store for discovery modules.
class DiscoveryLocalSavedStore {
  const DiscoveryLocalSavedStore({required this.namespace});

  final String namespace;
  static const String _fileName = 'saved_ids_v1.json';

  Future<Set<String>> loadSavedIds() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return <String>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
      }
      if (decoded is Map) {
        return decoded.keys
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
      }
      return <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> setSaved(String id, {required bool saved}) async {
    final key = id.trim();
    if (key.isEmpty) return;
    final all = await loadSavedIds();
    if (saved) {
      all.add(key);
    } else {
      all.remove(key);
    }
    await _saveAll(all);
  }

  Future<void> _saveAll(Set<String> ids) async {
    final file = await _storeFile();
    final sorted = ids.toList()..sort();
    await file.writeAsString(jsonEncode(sorted), flush: true);
  }

  Future<File> _storeFile() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}fluxidi'
      '${Platform.pathSeparator}discovery'
      '${Platform.pathSeparator}$namespace',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
