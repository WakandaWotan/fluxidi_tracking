import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:url_launcher/url_launcher.dart';

import 'hotel_geo_taxonomy.dart';
import 'hotel_model.dart';
import 'hotel_seed_data.dart';

class HotelsPage extends StatefulWidget {
  const HotelsPage({this.stays, this.onTaxiToStay, super.key});

  /// Optional data injection for later phases (API/provider).
  final List<HotelStay>? stays;

  /// Optional CTA callback for later taxi-prefill integration.
  final void Function(HotelStay stay)? onTaxiToStay;

  @override
  State<HotelsPage> createState() => _HotelsPageState();
}

class _HotelsPageState extends State<HotelsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  final TextEditingController _searchController = TextEditingController();
  static const String _allKey = 'all';

  late final List<HotelStay> _allStays;
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

  String _normalizeGeo(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
  }

  Set<String> _normalizedSet(Iterable<String> values) {
    return values.map(_normalizeGeo).where((value) => value.isNotEmpty).toSet();
  }

  @override
  void initState() {
    super.initState();
    _allStays = List<HotelStay>.from(widget.stays ?? kBelgiumHotelSeedData);
    _searchController.addListener(_onSearchChanged);
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
        : _normalizedSet(hotelGeoCountryMatchValues(_selectedCountryCode));
    final regionMatchValues =
        (_selectedCountryCode == _allKey || _selectedRegionKey == _allKey)
        ? const <String>{}
        : _normalizedSet(
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
        : _normalizedSet(
            hotelGeoSettlementMatchValues(
              countryCode: _selectedCountryCode,
              regionKey: _selectedRegionKey,
              settlementKey: _selectedSettlementKey,
            ),
          );
    return _allStays
        .where((stay) {
          if (countryMatchValues.isNotEmpty &&
              !countryMatchValues.contains(_normalizeGeo(stay.country))) {
            return false;
          }
          if (regionMatchValues.isNotEmpty &&
              !regionMatchValues.contains(_normalizeGeo(stay.region))) {
            return false;
          }
          if (settlementMatchValues.isNotEmpty &&
              !settlementMatchValues.contains(_normalizeGeo(stay.city))) {
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
    switch (typeKey) {
      case _allKey:
        return _t(
          nl: 'Alle types',
          en: 'All types',
          fr: 'Tous les types',
          es: 'Todos los tipos',
        );
      case HotelStayType.hotel:
        return 'Hotel';
      case HotelStayType.bedAndBreakfast:
        return 'B&B';
      case HotelStayType.aparthotel:
        return _t(
          nl: 'Aparthotel',
          en: 'Aparthotel',
          fr: 'Aparthotel',
          es: 'Aparthotel',
        );
      case HotelStayType.guesthouse:
        return _t(
          nl: 'Guesthouse',
          en: 'Guesthouse',
          fr: 'Guesthouse',
          es: 'Guesthouse',
        );
      default:
        return typeKey;
    }
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
    final raw = (stay.priceHint ?? '').trim();
    if (raw.isEmpty) return '';
    final normalized = raw.toLowerCase();
    if (normalized.startsWith('vanaf ') ||
        normalized.startsWith('from ') ||
        normalized.startsWith('desde ') ||
        normalized.startsWith('à partir')) {
      return raw;
    }
    return '$_fromLabel $raw';
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
    final booking = (stay.bookingUrl ?? '').trim();
    final website = (stay.websiteUrl ?? '').trim();
    final candidate = booking.isNotEmpty ? booking : website;
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
    final callback = widget.onTaxiToStay;
    if (callback != null) {
      callback(stay);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Taxi-prefill wordt gekoppeld in de volgende stap.',
            en: 'Taxi prefill will be connected in the next step.',
            fr: 'Le préremplissage taxi sera connecté à la prochaine étape.',
            es: 'El prellenado de taxi se conectará en el siguiente paso.',
          ),
        ),
      ),
    );
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
    return Container(
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
                    right: 10,
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
    );
  }
}
