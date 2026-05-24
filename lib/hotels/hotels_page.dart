import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
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
import 'hotel_geo_taxonomy.dart';
import 'hotel_model.dart';
import 'hotel_seed_data.dart';

class HotelsPage extends StatefulWidget {
  const HotelsPage({
    this.stays,
    this.onTaxiToStay,
    this.onTaxiToDestination,
    this.onOpenAirportFlow,
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
  final String? tenantId;
  final String? companyId;

  @override
  State<HotelsPage> createState() => _HotelsPageState();
}

class _HotelsPageState extends State<HotelsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  final TextEditingController _searchController = TextEditingController();
  final DiscoveryLocalSavedStore _savedStore = const DiscoveryLocalSavedStore(
    namespace: 'hotels',
  );
  static const String _allKey = 'all';

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
    _allStays = List<HotelStay>.from(widget.stays ?? kBelgiumHotelSeedData);
    _searchController.addListener(_onSearchChanged);
    _loadSavedStayIds();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
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

  List<HotelStay> get _visibleStays {
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
    return _allStays
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

  String get _saveStayLabel {
    return _t(nl: 'Opslaan', en: 'Save', fr: 'Enregistrer', es: 'Guardar');
  }

  String get _savedStayLabel {
    return _t(nl: 'Opgeslagen', en: 'Saved', fr: 'Enregistré', es: 'Guardado');
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_saveSyncFailedLabel)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextSaved
              ? _staySavedMessage(stay.name)
              : _stayUnsavedMessage(stay.name),
        ),
      ),
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

  Uri? _preferredStayUri(HotelStay stay) {
    final candidate = (stay.effectiveBookingUrl ?? '').trim();
    if (candidate.isEmpty) return null;
    return Uri.tryParse(candidate);
  }

  Future<void> _openStayLink(HotelStay stay) async {
    final uri = _preferredStayUri(stay);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Verblijflink is nog niet beschikbaar.',
              en: 'Stay link is not available yet.',
              fr: 'Le lien du séjour n’est pas encore disponible.',
              es: 'El enlace del alojamiento aún no está disponible.',
            ),
          ),
        ),
      );
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Kon verblijflink niet openen.',
            en: 'Could not open stay link.',
            fr: 'Impossible d’ouvrir le lien du séjour.',
            es: 'No se pudo abrir el enlace del alojamiento.',
          ),
        ),
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

    final destinationText = destination.prefillDestinationText;
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
              initialServiceId: 'hotel',
            ),
          ),
        )
        .catchError((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_taxiNavigationFallbackLabel)));
        });
  }

  String _eventTaxiPreparedMessage(String eventTitle) {
    return _t(
      nl: 'Taxi handoff voorbereid voor event: $eventTitle',
      en: 'Taxi handoff prepared for event: $eventTitle',
      fr: 'Transfert taxi prêt pour l’événement : $eventTitle',
      es: 'Transferencia de taxi preparada para evento: $eventTitle',
    );
  }

  List<EventDetailData> _nearbyEventsForStay(HotelStay stay) {
    final stayCity = normalizeDiscoveryText(stay.city);
    final stayRegion = normalizeDiscoveryText(stay.region);

    final sameCity = <EventDetailData>[
      for (final event in kEventSeedData)
        if (normalizeDiscoveryText(event.city) == stayCity) event,
    ];

    final regionCities = _allStays
        .where((item) => normalizeDiscoveryText(item.region) == stayRegion)
        .map((item) => normalizeDiscoveryText(item.city))
        .where((city) => city.isNotEmpty)
        .toSet();
    final sameRegion = <EventDetailData>[
      for (final event in kEventSeedData)
        if (regionCities.contains(normalizeDiscoveryText(event.city))) event,
    ];

    final belgiumCities = _allStays
        .where((item) => normalizeDiscoveryText(item.country) == 'belgium')
        .map((item) => normalizeDiscoveryText(item.city))
        .where((city) => city.isNotEmpty)
        .toSet();
    final belgiumFallback = <EventDetailData>[
      for (final event in kEventSeedData)
        if (belgiumCities.contains(normalizeDiscoveryText(event.city))) event,
    ];

    final merged = <EventDetailData>[
      ...sameCity,
      ...sameRegion,
      ...belgiumFallback,
    ];
    return topUniqueById(items: merged, idOf: (event) => event.id, limit: 3);
  }

  void _onNearbyEventTaxiTap(EventDetailData event) {
    debugPrint(
      '[hotels.nearby_event_handoff] eventId=${event.id} title="${event.title}" city="${event.city}"',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_eventTaxiPreparedMessage(event.title))),
    );
  }

  void _openStayDetail(HotelStay stay) {
    final nearbyEvents = _nearbyEventsForStay(stay);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HotelStayDetailPage(
          stay: stay,
          nearbyEvents: nearbyEvents,
          isSaved: _isSaved(stay),
          saveLabel: _saveStayLabel,
          savedLabel: _savedStayLabel,
          onToggleSaved: () => _toggleSaved(stay),
          onNearbyEventTaxiTap: _onNearbyEventTaxiTap,
          onAirportTransferTap: () {
            _onAirportTransferTap(stay);
          },
          onTaxiTap: () => _onTaxiCtaTap(stay),
          onViewStayTap: () => _openStayLink(stay),
        ),
      ),
    );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_airportFlowFallbackLabel)));
  }

  @override
  Widget build(BuildContext context) {
    final stays = _visibleStays;

    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 10),
                  _buildFilterPanel(),
                  const SizedBox(height: 12),
                  _buildResultSummary(stays.length),
                  const SizedBox(height: 10),
                  _buildCardsGrid(stays),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: _gold,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          Expanded(
            child: Text(
              'Hotels & B&B',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: _t(
          nl: 'Zoek hotel, stad of regio',
          en: 'Search hotel, city, or region',
          fr: 'Rechercher un hôtel, une ville ou une région',
          es: 'Buscar hotel, ciudad o región',
        ),
        hintStyle: const TextStyle(color: Color(0xFF8C8C8C)),
        prefixIcon: Icon(Icons.search_rounded, color: _gold),
        filled: true,
        fillColor: _panelBlack,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.2),
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
        border: Border.all(color: _gold.withOpacity(0.24)),
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
                        color: isSelected
                            ? const Color(0xFF1A1307)
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: const Color(0xFF151515),
                    selectedColor: _gold,
                    side: BorderSide(
                      color: isSelected ? _gold : _gold.withOpacity(0.26),
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
        color: enabled ? Colors.white : _softText.withOpacity(0.8),
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
        fillColor: const Color(0xFF151515),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _gold.withOpacity(0.24)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _gold.withOpacity(0.24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _gold, width: 1.1),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _gold,
          fontWeight: FontWeight.w700,
          fontSize: 12.2,
        ),
      ),
    );
  }

  Widget _buildCardsGrid(List<HotelStay> stays) {
    if (stays.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panelBlack,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withOpacity(0.24)),
        ),
        child: Text(
          _t(
            nl: 'Geen verblijven gevonden voor deze selectie.',
            en: 'No stays found for this selection.',
            fr: 'Aucun séjour trouvé pour cette sélection.',
            es: 'No se encontraron alojamientos para esta selección.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _softText, fontSize: 13),
        ),
      );
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
                if (i != stays.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final safeMainAxisExtent = (422.0 * textScale).clamp(422.0, 520.0);
        const spacing = 10.0;
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
    final hasExternalLink = _preferredStayUri(stay) != null;
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
            border: Border.all(color: _gold.withOpacity(0.22)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _gold.withOpacity(0.06),
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
                height: 132,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF23304A), Color(0xFF111827)],
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
                    if (imageUrl.isNotEmpty)
                      Positioned.fill(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
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
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
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
                    Center(
                      child: Icon(
                        Icons.hotel_rounded,
                        size: 50,
                        color: _gold.withOpacity(0.92),
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
                          style: const TextStyle(
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
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
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
                              : Colors.white.withOpacity(0.9),
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
                            style: const TextStyle(
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
                  padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stay.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.8,
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
                        stay.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _softText,
                          fontSize: 11.8,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                    color: const Color(0xFF171717),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _gold.withOpacity(0.32),
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.78),
                                      fontSize: 10.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      if (displayPrice.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          displayPrice,
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 11.7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _onTaxiCtaTap(stay),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: const Color(0xFF141414),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          icon: const Icon(Icons.local_taxi_rounded, size: 16),
                          label: Text(
                            _t(
                              nl: 'Taxi naar dit verblijf',
                              en: 'Taxi to this stay',
                              fr: 'Taxi vers cet hébergement',
                              es: 'Taxi a este alojamiento',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (hasExternalLink) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openStayLink(stay),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFF121212),
                              foregroundColor: Colors.white.withOpacity(0.92),
                              side: BorderSide(color: _gold.withOpacity(0.28)),
                              minimumSize: const Size.fromHeight(38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              Icons.open_in_new_rounded,
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

class HotelStayDetailPage extends StatelessWidget {
  const HotelStayDetailPage({
    required this.stay,
    required this.nearbyEvents,
    required this.isSaved,
    required this.saveLabel,
    required this.savedLabel,
    required this.onToggleSaved,
    required this.onNearbyEventTaxiTap,
    required this.onAirportTransferTap,
    required this.onTaxiTap,
    required this.onViewStayTap,
    super.key,
  });

  final HotelStay stay;
  final List<EventDetailData> nearbyEvents;
  final bool isSaved;
  final String saveLabel;
  final String savedLabel;
  final VoidCallback onToggleSaved;
  final void Function(EventDetailData event) onNearbyEventTaxiTap;
  final VoidCallback onAirportTransferTap;
  final VoidCallback onTaxiTap;
  final VoidCallback onViewStayTap;

  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

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

  String get _viewStayLabel {
    return _t(
      nl: 'Bekijk verblijf',
      en: 'View stay',
      fr: 'Voir le séjour',
      es: 'Ver alojamiento',
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
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold.withOpacity(0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
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
                style: const TextStyle(
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
                    backgroundColor: const Color(0xFF121212),
                    foregroundColor: Colors.white.withOpacity(0.93),
                    side: BorderSide(color: _gold.withOpacity(0.32)),
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
    final hasExternalLink = (stay.effectiveBookingUrl ?? '').trim().isNotEmpty;
    final displayPrice = _displayPriceHint();
    final highlights = _highlights();
    return Scaffold(
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
                      border: Border.all(color: _gold.withOpacity(0.24)),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Color(0xFF22314C), Color(0xFF101828)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (imageUrl.isNotEmpty)
                          Positioned.fill(
                            child: Image.network(
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
                                  const SizedBox.shrink(),
                            ),
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
                        Center(
                          child: Icon(
                            Icons.hotel_rounded,
                            color: _gold.withOpacity(0.95),
                            size: 64,
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
                              style: const TextStyle(
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
                                style: const TextStyle(
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
                      border: Border.all(color: _gold.withOpacity(0.22)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stay.name,
                                style: const TextStyle(
                                  color: Colors.white,
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
                                    : Colors.white.withOpacity(0.92),
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF161616),
                                side: BorderSide(
                                  color: _gold.withOpacity(0.32),
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
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          stay.description,
                          style: const TextStyle(
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
                                      color: const Color(0xFF171717),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _gold.withOpacity(0.28),
                                      ),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.82),
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
                  if (nearbyEvents.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: _panelBlack,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _gold.withOpacity(0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nearbyEventsLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < nearbyEvents.length; i++) ...[
                            _buildNearbyEventCard(context, nearbyEvents[i]),
                            if (i != nearbyEvents.length - 1)
                              const SizedBox(height: 8),
                          ],
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onTaxiTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: const Color(0xFF161616),
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAirportTransferTap,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFF111111),
                        foregroundColor: Colors.white.withOpacity(0.94),
                        side: BorderSide(color: _gold.withOpacity(0.3)),
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
                  if (hasExternalLink) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onViewStayTap,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFF111111),
                          foregroundColor: Colors.white.withOpacity(0.94),
                          side: BorderSide(color: _gold.withOpacity(0.3)),
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
                          _viewStayLabel,
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
