import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/airport/airport_booking_review_page.dart';
import 'package:fluxidi_tracking/airport/airport_catalog.generated.dart';
import 'package:fluxidi_tracking/effective_tenant_company_scope.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

enum _TransferMode { toAirport, fromAirport }

typedef AirportPartnerSelectionCallback =
    Future<Map<String, String>?> Function(BuildContext context);

class _AirportOption {
  const _AirportOption({
    required this.id,
    required this.countryCode,
    required this.countryName,
    required this.city,
    required this.name,
    required this.iata,
    this.latitude,
    this.longitude,
    this.preciseAddress,
  });

  final String id;
  final String countryCode;
  final String countryName;
  final String city;
  final String name;
  final String iata;
  final double? latitude;
  final double? longitude;
  final String? preciseAddress;
}

class AirportPage extends StatefulWidget {
  const AirportPage({
    super.key,
    required this.bookingBaseUrl,
    this.selectedTenantId,
    this.selectedCompanyId,
    this.selectedCompanyCode,
    this.selectedCompanyName,
    this.selectedPartnerId,
    this.allowPartnerChange = false,
    this.onChangePartnerRequested,
    this.allowAdminScopeFallback = false,
  });

  final String bookingBaseUrl;
  final String? selectedTenantId;
  final String? selectedCompanyId;
  final String? selectedCompanyCode;
  final String? selectedCompanyName;
  final String? selectedPartnerId;
  final bool allowPartnerChange;
  final AirportPartnerSelectionCallback? onChangePartnerRequested;
  final bool allowAdminScopeFallback;

  @override
  State<AirportPage> createState() => _AirportPageState();
}

class _AirportPageState extends State<AirportPage> {
  static const Color _bg = Color(0xFF07080C);
  static const Color _panel = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _soft = Color(0xFFB4B4B4);
  static const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
  static const Set<String> _supportedCountryCodes = <String>{
    'BE',
    'NL',
    'FR',
    'DE',
    'LU',
    'ES',
    'GB',
  };
  static const Set<String> _requiredAirportIata = <String>{
    'AMS',
    'DUS',
    'BER',
    'MAD',
    'IBZ',
    'LYS',
  };

  static const List<_AirportOption> _airports = <_AirportOption>[
    _AirportOption(
      id: 'bru',
      countryCode: 'BE',
      countryName: 'België',
      city: 'Brussel',
      name: 'Brussels Airport',
      iata: 'BRU',
    ),
    _AirportOption(
      id: 'crl',
      countryCode: 'BE',
      countryName: 'België',
      city: 'Charleroi',
      name: 'Brussels South Charleroi Airport',
      iata: 'CRL',
    ),
    _AirportOption(
      id: 'anr',
      countryCode: 'BE',
      countryName: 'België',
      city: 'Antwerpen',
      name: 'Antwerp Airport',
      iata: 'ANR',
    ),
    _AirportOption(
      id: 'ost',
      countryCode: 'BE',
      countryName: 'België',
      city: 'Oostende/Brugge',
      name: 'Ostend-Bruges Airport',
      iata: 'OST',
    ),
    _AirportOption(
      id: 'lgg',
      countryCode: 'BE',
      countryName: 'België',
      city: 'Luik',
      name: 'Liège Airport',
      iata: 'LGG',
    ),
    _AirportOption(
      id: 'ams',
      countryCode: 'NL',
      countryName: 'Nederland',
      city: 'Amsterdam',
      name: 'Amsterdam Schiphol',
      iata: 'AMS',
      latitude: 52.308601,
      longitude: 4.763890,
      preciseAddress:
          'Evert van de Beekstraat 202, 1118 CP Schiphol, Nederland',
    ),
    _AirportOption(
      id: 'ein',
      countryCode: 'NL',
      countryName: 'Nederland',
      city: 'Eindhoven',
      name: 'Eindhoven Airport',
      iata: 'EIN',
    ),
    _AirportOption(
      id: 'rtm',
      countryCode: 'NL',
      countryName: 'Nederland',
      city: 'Rotterdam/Den Haag',
      name: 'Rotterdam The Hague Airport',
      iata: 'RTM',
    ),
    _AirportOption(
      id: 'mst',
      countryCode: 'NL',
      countryName: 'Nederland',
      city: 'Maastricht',
      name: 'Maastricht Aachen Airport',
      iata: 'MST',
    ),
    _AirportOption(
      id: 'grq',
      countryCode: 'NL',
      countryName: 'Nederland',
      city: 'Groningen',
      name: 'Groningen Airport Eelde',
      iata: 'GRQ',
    ),
    _AirportOption(
      id: 'cdg',
      countryCode: 'FR',
      countryName: 'Frankrijk',
      city: 'Parijs',
      name: 'Paris Charles de Gaulle',
      iata: 'CDG',
    ),
    _AirportOption(
      id: 'ory',
      countryCode: 'FR',
      countryName: 'Frankrijk',
      city: 'Parijs',
      name: 'Paris Orly',
      iata: 'ORY',
    ),
    _AirportOption(
      id: 'bva',
      countryCode: 'FR',
      countryName: 'Frankrijk',
      city: 'Beauvais',
      name: 'Paris Beauvais',
      iata: 'BVA',
    ),
    _AirportOption(
      id: 'lys',
      countryCode: 'FR',
      countryName: 'Frankrijk',
      city: 'Lyon',
      name: 'Lyon-Saint Exupéry Airport',
      iata: 'LYS',
      latitude: 45.725996,
      longitude: 5.090139,
      preciseAddress: '69125 Colombier-Saugnieu, Frankrijk',
    ),
    _AirportOption(
      id: 'mrs',
      countryCode: 'FR',
      countryName: 'Frankrijk',
      city: 'Marseille',
      name: 'Marseille Provence Airport',
      iata: 'MRS',
    ),
    _AirportOption(
      id: 'nce',
      countryCode: 'FR',
      countryName: 'Frankrijk',
      city: 'Nice',
      name: 'Nice Côte d’Azur Airport',
      iata: 'NCE',
    ),
    _AirportOption(
      id: 'fra',
      countryCode: 'DE',
      countryName: 'Duitsland',
      city: 'Frankfurt',
      name: 'Frankfurt Airport',
      iata: 'FRA',
    ),
    _AirportOption(
      id: 'muc',
      countryCode: 'DE',
      countryName: 'Duitsland',
      city: 'München',
      name: 'Munich Airport',
      iata: 'MUC',
    ),
    _AirportOption(
      id: 'dus',
      countryCode: 'DE',
      countryName: 'Duitsland',
      city: 'Düsseldorf',
      name: 'Düsseldorf Airport',
      iata: 'DUS',
      latitude: 51.289501,
      longitude: 6.766780,
      preciseAddress: 'Flughafenstraße 105, 40474 Düsseldorf, Duitsland',
    ),
    _AirportOption(
      id: 'cgn',
      countryCode: 'DE',
      countryName: 'Duitsland',
      city: 'Keulen/Bonn',
      name: 'Cologne Bonn Airport',
      iata: 'CGN',
    ),
    _AirportOption(
      id: 'ber',
      countryCode: 'DE',
      countryName: 'Duitsland',
      city: 'Berlijn',
      name: 'Berlin Brandenburg Airport',
      iata: 'BER',
      latitude: 52.361738,
      longitude: 13.502341,
      preciseAddress: 'Willy-Brandt-Platz, 12529 Schönefeld, Duitsland',
    ),
    _AirportOption(
      id: 'ham',
      countryCode: 'DE',
      countryName: 'Duitsland',
      city: 'Hamburg',
      name: 'Hamburg Airport',
      iata: 'HAM',
    ),
    _AirportOption(
      id: 'lux',
      countryCode: 'LU',
      countryName: 'Luxemburg',
      city: 'Luxemburg',
      name: 'Luxembourg Airport',
      iata: 'LUX',
    ),
    _AirportOption(
      id: 'mad',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Madrid',
      name: 'Madrid Barajas Airport',
      iata: 'MAD',
      latitude: 40.493407,
      longitude: -3.572249,
      preciseAddress: 'Av de la Hispanidad, s/n, 28042 Madrid, Spanje',
    ),
    _AirportOption(
      id: 'bcn',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Barcelona',
      name: 'Barcelona El Prat Airport',
      iata: 'BCN',
    ),
    _AirportOption(
      id: 'agp',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Málaga',
      name: 'Málaga-Costa del Sol Airport',
      iata: 'AGP',
    ),
    _AirportOption(
      id: 'alc',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Alicante',
      name: 'Alicante-Elche Miguel Hernández Airport',
      iata: 'ALC',
    ),
    _AirportOption(
      id: 'vlc',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Valencia',
      name: 'Valencia Airport',
      iata: 'VLC',
    ),
    _AirportOption(
      id: 'svq',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Sevilla',
      name: 'Seville Airport',
      iata: 'SVQ',
    ),
    _AirportOption(
      id: 'pmi',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Palma de Mallorca',
      name: 'Palma de Mallorca Airport',
      iata: 'PMI',
    ),
    _AirportOption(
      id: 'ibz',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Ibiza',
      name: 'Ibiza Airport',
      iata: 'IBZ',
      latitude: 38.872898,
      longitude: 1.373120,
      preciseAddress: '07820 Sant Jordi de ses Salines, Ibiza, Spanje',
    ),
    _AirportOption(
      id: 'tfs',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Tenerife',
      name: 'Tenerife South Airport',
      iata: 'TFS',
    ),
    _AirportOption(
      id: 'lpa',
      countryCode: 'ES',
      countryName: 'Spanje',
      city: 'Gran Canaria',
      name: 'Gran Canaria Airport',
      iata: 'LPA',
    ),
    _AirportOption(
      id: 'lhr',
      countryCode: 'GB',
      countryName: 'Verenigd Koninkrijk',
      city: 'Londen',
      name: 'London Heathrow',
      iata: 'LHR',
    ),
    _AirportOption(
      id: 'lgw',
      countryCode: 'GB',
      countryName: 'Verenigd Koninkrijk',
      city: 'Londen',
      name: 'London Gatwick',
      iata: 'LGW',
    ),
    _AirportOption(
      id: 'stn',
      countryCode: 'GB',
      countryName: 'Verenigd Koninkrijk',
      city: 'Londen',
      name: 'London Stansted',
      iata: 'STN',
    ),
    _AirportOption(
      id: 'ltn',
      countryCode: 'GB',
      countryName: 'Verenigd Koninkrijk',
      city: 'Londen',
      name: 'London Luton',
      iata: 'LTN',
    ),
    _AirportOption(
      id: 'man',
      countryCode: 'GB',
      countryName: 'Verenigd Koninkrijk',
      city: 'Manchester',
      name: 'Manchester Airport',
      iata: 'MAN',
    ),
    _AirportOption(
      id: 'bhx',
      countryCode: 'GB',
      countryName: 'Verenigd Koninkrijk',
      city: 'Birmingham',
      name: 'Birmingham Airport',
      iata: 'BHX',
    ),
  ];
  static final List<_AirportOption> _catalogAirports = _buildCatalogAirports();

  static List<_AirportOption> _buildCatalogAirports() {
    final generated = kAirportCatalog
        .where(
          (entry) =>
              _supportedCountryCodes.contains(entry.countryCode) &&
              entry.iata.trim().length == 3,
        )
        .map(
          (entry) => _AirportOption(
            id: entry.iata.toLowerCase(),
            countryCode: entry.countryCode,
            countryName: entry.countryName,
            city: entry.municipality,
            name: entry.name,
            iata: entry.iata,
            latitude: entry.latitude,
            longitude: entry.longitude,
            preciseAddress: entry.preciseAddress,
          ),
        )
        .toList(growable: false);

    if (generated.isEmpty) {
      debugPrint(
        '[AIRPORT_CATALOG] generated catalog empty in supported scope; using fallback list.',
      );
      return _airports;
    }
    final iataSet = generated.map((airport) => airport.iata).toSet();
    final missingRequired = _requiredAirportIata
        .where((iata) => !iataSet.contains(iata))
        .toList(growable: false);
    if (missingRequired.isNotEmpty) {
      debugPrint(
        '[AIRPORT_CATALOG] missing required generated airports ${missingRequired.join(", ")}; using fallback list.',
      );
      return _airports;
    }
    return generated;
  }

  _TransferMode _selectedMode = _TransferMode.toAirport;
  String _selectedCountryCode = _catalogAirports.first.countryCode;
  String _selectedAirportId = _catalogAirports.first.id;
  int _passengers = 1;
  int _bags = 0;
  bool _meetAndGreet = false;
  bool _isResolvingPickupLocation = false;
  bool _isResolvingDestinationLocation = false;
  bool _isRequestingQuote = false;
  double? _pickupLatitude;
  double? _pickupLongitude;
  double? _destinationLatitude;
  double? _destinationLongitude;
  Map<String, dynamic>? _airportQuote;
  String? _airportQuoteError;

  String get _lang => appConfig.currentLanguage.name.toLowerCase();

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
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

  List<String> get _availableCountryCodes {
    final unique = <String>{};
    final codes = <String>[];
    for (final airport in _catalogAirports) {
      if (unique.add(airport.countryCode)) {
        codes.add(airport.countryCode);
      }
    }
    return codes;
  }

  List<_AirportOption> get _filteredAirports => _catalogAirports
      .where((airport) => airport.countryCode == _selectedCountryCode)
      .toList(growable: false);

  _AirportOption get _selectedAirport {
    final filtered = _filteredAirports;
    if (filtered.isEmpty) {
      return _catalogAirports.first;
    }
    return filtered.firstWhere(
      (airport) => airport.id == _selectedAirportId,
      orElse: () => filtered.first,
    );
  }

  String _countryLabelForCode(String countryCode) {
    switch (countryCode) {
      case 'BE':
        return _t(nl: 'België', en: 'Belgium', fr: 'Belgique', es: 'Bélgica');
      case 'NL':
        return _t(
          nl: 'Nederland',
          en: 'Netherlands',
          fr: 'Pays-Bas',
          es: 'Países Bajos',
        );
      case 'FR':
        return _t(nl: 'Frankrijk', en: 'France', fr: 'France', es: 'Francia');
      case 'DE':
        return _t(
          nl: 'Duitsland',
          en: 'Germany',
          fr: 'Allemagne',
          es: 'Alemania',
        );
      case 'LU':
        return _t(
          nl: 'Luxemburg',
          en: 'Luxembourg',
          fr: 'Luxembourg',
          es: 'Luxemburgo',
        );
      case 'ES':
        return _t(nl: 'Spanje', en: 'Spain', fr: 'Espagne', es: 'España');
      case 'GB':
        return _t(
          nl: 'Verenigd Koninkrijk',
          en: 'United Kingdom',
          fr: 'Royaume-Uni',
          es: 'Reino Unido',
        );
      default:
        final fallback = _catalogAirports
            .where((airport) => airport.countryCode == countryCode)
            .map((airport) => airport.countryName)
            .firstWhere((_) => true, orElse: () => countryCode);
        final separator = fallback.indexOf('/');
        if (separator >= 0 && separator < fallback.length - 1) {
          return fallback.substring(separator + 1);
        }
        return fallback;
    }
  }

  void _setCountry(String countryCode) {
    final firstAirport = _catalogAirports.firstWhere(
      (airport) => airport.countryCode == countryCode,
      orElse: () => _catalogAirports.first,
    );
    _clearAirportQuote();
    setState(() {
      _selectedCountryCode = countryCode;
      _selectedAirportId = firstAirport.id;
    });
  }

  void _setAirport(String airportId) {
    _clearAirportQuote();
    setState(() {
      _selectedAirportId = airportId;
    });
  }

  Widget _buildCountryDropdown() {
    return InputDecorator(
      decoration: _fieldDecoration(
        label: _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
        prefixIcon: Icons.public_rounded,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCountryCode,
          isDense: true,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A1A),
          iconEnabledColor: _gold,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: _availableCountryCodes
              .map(
                (countryCode) => DropdownMenuItem<String>(
                  value: countryCode,
                  child: Text(_countryLabelForCode(countryCode)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null || value == _selectedCountryCode) {
              return;
            }
            _setCountry(value);
          },
        ),
      ),
    );
  }

  Widget _buildAirportOnlyDropdown() {
    final filteredAirports = _filteredAirports;
    return InputDecorator(
      decoration: _fieldDecoration(
        label: _t(
          nl: 'Luchthaven',
          en: 'Airport',
          fr: 'Aéroport',
          es: 'Aeropuerto',
        ),
        prefixIcon: Icons.flight_rounded,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedAirport.id,
          isDense: true,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A1A),
          iconEnabledColor: _gold,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          selectedItemBuilder: (context) => filteredAirports
              .map(
                (airport) => Text(
                  airport.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
              .toList(growable: false),
          items: filteredAirports
              .map(
                (airport) => DropdownMenuItem<String>(
                  value: airport.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          airport.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        airport.iata,
                        style: TextStyle(
                          color: _gold.withOpacity(0.95),
                          fontSize: 11.6,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            _setAirport(value);
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedTenantId = _safeText(widget.selectedTenantId);
    _selectedCompanyId = _safeText(widget.selectedCompanyId);
    _selectedCompanyCode = _safeText(widget.selectedCompanyCode);
    _selectedCompanyName = _safeText(widget.selectedCompanyName);
    _selectedPartnerId = _safeText(widget.selectedPartnerId);
    if (_filteredAirports.every(
      (airport) => airport.id != _selectedAirportId,
    )) {
      _selectedAirportId = _filteredAirports.first.id;
    }
    _pickupAddressController.addListener(_handleSummaryInputChanged);
    _destinationAddressController.addListener(_handleSummaryInputChanged);
    _pickupDateTimeController.addListener(_handleSummaryInputChanged);
    _landingDateTimeController.addListener(_handleSummaryInputChanged);
    _flightNumberController.addListener(_handleSummaryInputChanged);
    _noteController.addListener(_handleSummaryInputChanged);
    _nameBoardController.addListener(_handleSummaryInputChanged);
  }

  final TextEditingController _pickupAddressController =
      TextEditingController();
  final TextEditingController _destinationAddressController =
      TextEditingController();
  final TextEditingController _pickupDateTimeController =
      TextEditingController();
  final TextEditingController _landingDateTimeController =
      TextEditingController();
  final TextEditingController _flightNumberController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _nameBoardController = TextEditingController();
  late String _selectedTenantId;
  late String _selectedCompanyId;
  late String _selectedCompanyCode;
  late String _selectedCompanyName;
  late String _selectedPartnerId;

  String _safeText(String? value) => (value ?? '').trim();

  bool get _hasSelectedPartnerScope =>
      _selectedTenantId.isNotEmpty && _selectedCompanyId.isNotEmpty;

  String get _selectedCompanyLabel {
    if (_selectedCompanyName.isNotEmpty) return _selectedCompanyName;
    if (_selectedCompanyCode.isNotEmpty) return _selectedCompanyCode;
    if (_selectedPartnerId.isNotEmpty) return _selectedPartnerId;
    return _selectedCompanyId;
  }

  @override
  void dispose() {
    _pickupAddressController.removeListener(_handleSummaryInputChanged);
    _destinationAddressController.removeListener(_handleSummaryInputChanged);
    _pickupDateTimeController.removeListener(_handleSummaryInputChanged);
    _landingDateTimeController.removeListener(_handleSummaryInputChanged);
    _flightNumberController.removeListener(_handleSummaryInputChanged);
    _noteController.removeListener(_handleSummaryInputChanged);
    _nameBoardController.removeListener(_handleSummaryInputChanged);
    _pickupAddressController.dispose();
    _destinationAddressController.dispose();
    _pickupDateTimeController.dispose();
    _landingDateTimeController.dispose();
    _flightNumberController.dispose();
    _noteController.dispose();
    _nameBoardController.dispose();
    super.dispose();
  }

  Future<void> _changePartner() async {
    final callback = widget.onChangePartnerRequested;
    if (callback == null) return;
    final selected = await callback(context);
    if (!mounted || selected == null) return;
    final tenantId = (selected['tenant_id'] ?? '').trim();
    final companyId = (selected['company_id'] ?? '').trim();
    if (tenantId.isEmpty || companyId.isEmpty) return;
    setState(() {
      _selectedTenantId = tenantId;
      _selectedCompanyId = companyId;
      _selectedCompanyCode = (selected['company_code'] ?? '').trim();
      _selectedCompanyName = (selected['company_name'] ?? '').trim();
      _selectedPartnerId = (selected['partner_id'] ?? '').trim();
      _airportQuote = null;
      _airportQuoteError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : 14.0;
    final compactHero = width < 380;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  16,
                ),
                children: [
                  _buildHero(compact: compactHero),
                  const SizedBox(height: 10),
                  _buildDirectionActions(),
                  const SizedBox(height: 10),
                  _buildIntakePanel(),
                  const SizedBox(height: 10),
                  _buildRideSummaryCard(),
                  if (_airportQuote != null || _airportQuoteError != null) ...[
                    const SizedBox(height: 10),
                    _buildAirportQuoteCard(),
                  ],
                  const SizedBox(height: 12),
                  _buildCtaButton(context),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: _gold,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Luchthavenvervoer',
                    en: 'Airport transfers',
                    fr: 'Transferts aéroport',
                    es: 'Traslados al aeropuerto',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  _t(
                    nl: 'Premium transfers voor comfortabele ritten van en naar de luchthaven',
                    en: 'Premium transfers for comfortable rides to and from the airport',
                    fr: "Transferts premium pour des trajets confortables vers et depuis l'aéroport",
                    es: 'Traslados premium para viajes cómodos hacia y desde el aeropuerto',
                  ),
                  style: TextStyle(color: _soft, fontSize: 11.5, height: 1.2),
                ),
                if (_hasSelectedPartnerScope) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_t(nl: "Boeking bij", en: "Booking with", fr: "Réservation chez", es: "Reserva con")}: $_selectedCompanyLabel',
                    style: TextStyle(
                      color: _gold.withOpacity(0.95),
                      fontSize: 11.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.allowPartnerChange &&
              widget.onChangePartnerRequested != null) ...[
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: _changePartner,
              style: TextButton.styleFrom(
                foregroundColor: _gold.withOpacity(0.96),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: Text(
                _t(
                  nl: 'Wijzig partner',
                  en: 'Change partner',
                  fr: 'Changer partenaire',
                  es: 'Cambiar socio',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHero({required bool compact}) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.28)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF12110A), Color(0xFF07080C)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 48 : 54,
            height: compact ? 48 : 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.45)),
              color: _gold.withOpacity(0.14),
            ),
            child: Icon(
              Icons.local_taxi_rounded,
              color: _gold,
              size: compact ? 26 : 30,
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Zakelijk en privé luchthavenvervoer',
                    en: 'Business and private airport transfers',
                    fr: 'Transferts aéroport professionnels et privés',
                    es: 'Traslados al aeropuerto para empresas y particulares',
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 13.6 : 14.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: compact ? 3 : 4),
                Text(
                  _t(
                    nl: 'Plan binnenkort direct uw transfer met heldere serviceopties en betrouwbare chauffeurs.',
                    en: 'Plan your transfer soon with clear service options and reliable drivers.',
                    fr: 'Planifiez bientôt votre transfert avec des options claires et des chauffeurs fiables.',
                    es: 'Planifica pronto tu traslado con opciones claras y conductores fiables.',
                  ),
                  style: TextStyle(
                    color: _soft,
                    fontSize: compact ? 11.3 : 11.8,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionActions() {
    const cardGap = 10.0;
    const minCardWidth = 230.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final first = _actionCard(
          title: _t(
            nl: 'Naar de luchthaven',
            en: 'To the airport',
            fr: "Vers l'aéroport",
            es: 'Al aeropuerto',
          ),
          subtitle: _t(
            nl: 'Vertrek naar uw vlucht',
            en: 'Departure to your flight',
            fr: 'Départ vers votre vol',
            es: 'Salida hacia tu vuelo',
          ),
          icon: Icons.flight_takeoff_rounded,
          mode: _TransferMode.toAirport,
        );
        final second = _actionCard(
          title: _t(
            nl: 'Van de luchthaven',
            en: 'From the airport',
            fr: "Depuis l'aéroport",
            es: 'Desde el aeropuerto',
          ),
          subtitle: _t(
            nl: 'Aankomst op de luchthaven',
            en: 'Arrival at the airport',
            fr: "Arrivée à l'aéroport",
            es: 'Llegada al aeropuerto',
          ),
          icon: Icons.flight_land_rounded,
          mode: _TransferMode.fromAirport,
        );
        final canShowSideBySide =
            constraints.maxWidth >= (minCardWidth * 2) + cardGap;
        if (!canShowSideBySide) {
          return Column(
            children: [
              first,
              const SizedBox(height: cardGap),
              second,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: cardGap),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required _TransferMode mode,
  }) {
    final isSelected = _selectedMode == mode;
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? _gold : _gold.withOpacity(0.26),
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: isSelected
            ? <BoxShadow>[
                BoxShadow(
                  color: _gold.withOpacity(0.28),
                  blurRadius: 14,
                  spreadRadius: 0.2,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _clearAirportQuote();
            setState(() {
              _selectedMode = mode;
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? _gold.withOpacity(0.22)
                            : _gold.withOpacity(0.14),
                        border: Border.all(
                          color: isSelected
                              ? _gold.withOpacity(0.72)
                              : _gold.withOpacity(0.4),
                        ),
                      ),
                      child: Icon(icon, color: _gold, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        style: TextStyle(
                          color: isSelected ? _gold : Colors.white,
                          fontSize: 13.2,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 11.2,
                    height: 1.2,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _gold.withOpacity(0.7)),
                    ),
                    child: Text(
                      _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo'),
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 10.6,
                        fontWeight: FontWeight.w800,
                      ),
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

  Widget _sectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gold.withOpacity(0.96), size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: _soft,
                fontSize: 11.7,
                height: 1.25,
              ),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }

  Widget _buildIntakePanel() {
    final isToAirport = _selectedMode == _TransferMode.toAirport;
    return _sectionCard(
      title: isToAirport
          ? _t(
              nl: 'Intake: naar de luchthaven',
              en: 'Intake: to the airport',
              fr: "Saisie : vers l'aéroport",
              es: 'Datos: al aeropuerto',
            )
          : _t(
              nl: 'Intake: van de luchthaven',
              en: 'Intake: from the airport',
              fr: "Saisie : depuis l'aéroport",
              es: 'Datos: desde el aeropuerto',
            ),
      icon: isToAirport
          ? Icons.directions_car_filled_rounded
          : Icons.local_taxi_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isToAirport) ...[
            _buildTextField(
              label: _t(
                nl: 'Ophaaladres',
                en: 'Pickup address',
                fr: 'Adresse de prise en charge',
                es: 'Dirección de recogida',
              ),
              controller: _pickupAddressController,
              hint: _t(
                nl: 'Straat, nummer, postcode, stad',
                en: 'Street, number, postal code, city',
                fr: 'Rue, numéro, code postal, ville',
                es: 'Calle, número, código postal, ciudad',
              ),
              icon: Icons.pin_drop_outlined,
              suffixIcon: IconButton(
                onPressed: _isResolvingPickupLocation
                    ? null
                    : _useCurrentPickupLocation,
                tooltip: _t(
                  nl: 'Huidige locatie gebruiken',
                  en: 'Use current location',
                  fr: 'Utiliser la position actuelle',
                  es: 'Usar ubicación actual',
                ),
                icon: _isResolvingPickupLocation
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _gold.withOpacity(0.96),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.my_location_rounded,
                        color: _gold.withOpacity(0.92),
                        size: 18,
                      ),
              ),
            ),
            const SizedBox(height: 10),
            _buildAirportDropdown(),
            const SizedBox(height: 10),
            _buildTextField(
              label: _t(
                nl: 'Ophaaldatum en tijd',
                en: 'Pickup date and time',
                fr: 'Date et heure de prise en charge',
                es: 'Fecha y hora de recogida',
              ),
              controller: _pickupDateTimeController,
              hint: _t(
                nl: 'Bijv. 21/06/2026 - 05:45',
                en: 'E.g. 21/06/2026 - 05:45',
                fr: 'Ex. 21/06/2026 - 05:45',
                es: 'Ej. 21/06/2026 - 05:45',
              ),
              icon: Icons.schedule_rounded,
              readOnly: true,
              onTap: () => _pickAirportDateTime(_pickupDateTimeController),
              suffixIcon: IconButton(
                onPressed: () =>
                    _pickAirportDateTime(_pickupDateTimeController),
                tooltip: _t(
                  nl: 'Datum en tijd kiezen',
                  en: 'Choose date and time',
                  fr: "Choisir la date et l'heure",
                  es: 'Elegir fecha y hora',
                ),
                icon: Icon(
                  Icons.calendar_month_rounded,
                  color: _gold.withOpacity(0.92),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: _t(
                nl: 'Passagiers',
                en: 'Passengers',
                fr: 'Passagers',
                es: 'Pasajeros',
              ),
              value: _passengers,
              min: 1,
              max: 8,
              icon: Icons.groups_2_outlined,
              onChanged: (value) {
                _clearAirportQuote();
                setState(() => _passengers = value);
              },
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: _t(
                nl: 'Bagage',
                en: 'Luggage',
                fr: 'Bagages',
                es: 'Equipaje',
              ),
              value: _bags,
              min: 0,
              max: 12,
              icon: Icons.luggage_outlined,
              onChanged: (value) {
                _clearAirportQuote();
                setState(() => _bags = value);
              },
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: _t(
                nl: 'Opmerking (optioneel)',
                en: 'Note (optional)',
                fr: 'Remarque (optionnel)',
                es: 'Nota (opcional)',
              ),
              controller: _noteController,
              hint: _t(
                nl: 'Extra info voor de chauffeur',
                en: 'Extra information for the driver',
                fr: 'Informations supplémentaires pour le chauffeur',
                es: 'Información adicional para el conductor',
              ),
              icon: Icons.edit_note_rounded,
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                nl: 'Prijsberekening en boeking worden in een volgende stap gekoppeld.',
                en: 'Price calculation and booking are connected in the next step.',
                fr: 'Le calcul du prix et la réservation seront reliés à l’étape suivante.',
                es: 'El cálculo del precio y la reserva se conectarán en el siguiente paso.',
              ),
              style: TextStyle(
                color: _soft.withOpacity(0.95),
                fontSize: 11.4,
                height: 1.25,
              ),
            ),
          ] else ...[
            _buildAirportDropdown(),
            const SizedBox(height: 10),
            _buildTextField(
              label: _t(
                nl: 'Bestemmingsadres',
                en: 'Destination address',
                fr: 'Adresse de destination',
                es: 'Dirección de destino',
              ),
              controller: _destinationAddressController,
              hint: _t(
                nl: 'Straat, nummer, postcode, stad',
                en: 'Street, number, postal code, city',
                fr: 'Rue, numéro, code postal, ville',
                es: 'Calle, número, código postal, ciudad',
              ),
              icon: Icons.location_on_outlined,
              suffixIcon: IconButton(
                onPressed: _isResolvingDestinationLocation
                    ? null
                    : _useCurrentDestinationLocation,
                tooltip: _t(
                  nl: 'Huidige locatie gebruiken',
                  en: 'Use current location',
                  fr: 'Utiliser la position actuelle',
                  es: 'Usar ubicación actual',
                ),
                icon: _isResolvingDestinationLocation
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _gold.withOpacity(0.96),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.my_location_rounded,
                        color: _gold.withOpacity(0.92),
                        size: 18,
                      ),
              ),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: _t(
                nl: 'Vluchtnummer (optioneel)',
                en: 'Flight number (optional)',
                fr: 'Numéro de vol (optionnel)',
                es: 'Número de vuelo (opcional)',
              ),
              controller: _flightNumberController,
              hint: _t(
                nl: 'Bijv. SN204',
                en: 'E.g. SN204',
                fr: 'Ex. SN204',
                es: 'Ej. SN204',
              ),
              icon: Icons.confirmation_number_outlined,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: _t(
                nl: 'Landingsdatum en tijd',
                en: 'Landing date and time',
                fr: "Date et heure d'atterrissage",
                es: 'Fecha y hora de aterrizaje',
              ),
              controller: _landingDateTimeController,
              hint: _t(
                nl: 'Bijv. 21/06/2026 - 18:20',
                en: 'E.g. 21/06/2026 - 18:20',
                fr: 'Ex. 21/06/2026 - 18:20',
                es: 'Ej. 21/06/2026 - 18:20',
              ),
              icon: Icons.schedule_rounded,
              readOnly: true,
              onTap: () => _pickAirportDateTime(_landingDateTimeController),
              suffixIcon: IconButton(
                onPressed: () =>
                    _pickAirportDateTime(_landingDateTimeController),
                tooltip: _t(
                  nl: 'Datum en tijd kiezen',
                  en: 'Choose date and time',
                  fr: "Choisir la date et l'heure",
                  es: 'Elegir fecha y hora',
                ),
                icon: Icon(
                  Icons.calendar_month_rounded,
                  color: _gold.withOpacity(0.92),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildMeetAndGreetToggle(),
            if (_meetAndGreet) ...[
              const SizedBox(height: 10),
              _buildTextField(
                label: _t(
                  nl: 'Naam op bordje',
                  en: 'Name on sign',
                  fr: 'Nom sur pancarte',
                  es: 'Nombre en cartel',
                ),
                controller: _nameBoardController,
                hint: _t(
                  nl: 'Bijv. Mevr. Van Dijk',
                  en: 'E.g. Mrs. Smith',
                  fr: 'Ex. Mme Dupont',
                  es: 'Ej. Sra. García',
                ),
                icon: Icons.badge_outlined,
              ),
            ],
            const SizedBox(height: 10),
            _buildStepperRow(
              label: _t(
                nl: 'Passagiers',
                en: 'Passengers',
                fr: 'Passagers',
                es: 'Pasajeros',
              ),
              value: _passengers,
              min: 1,
              max: 8,
              icon: Icons.groups_2_outlined,
              onChanged: (value) {
                _clearAirportQuote();
                setState(() => _passengers = value);
              },
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: _t(
                nl: 'Bagage',
                en: 'Luggage',
                fr: 'Bagages',
                es: 'Equipaje',
              ),
              value: _bags,
              min: 0,
              max: 12,
              icon: Icons.luggage_outlined,
              onChanged: (value) {
                _clearAirportQuote();
                setState(() => _bags = value);
              },
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                nl: 'Vluchttracking en boeking worden in een volgende stap gekoppeld.',
                en: 'Flight tracking and booking are connected in the next step.',
                fr: 'Le suivi de vol et la réservation seront reliés à l’étape suivante.',
                es: 'El seguimiento de vuelo y la reserva se conectarán en el siguiente paso.',
              ),
              style: TextStyle(
                color: _soft.withOpacity(0.95),
                fontSize: 11.4,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAirportDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCountryDropdown(),
        const SizedBox(height: 10),
        _buildAirportOnlyDropdown(),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    bool readOnly = false,
    VoidCallback? onTap,
    int maxLines = 1,
    int minLines = 1,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      maxLines: maxLines,
      minLines: minLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: _fieldDecoration(
        label: label,
        hintText: hint,
        prefixIcon: icon,
        suffixIcon: suffixIcon,
      ),
    );
  }

  DateTime? _parseAirportDateTime(String value) {
    final input = value.trim();
    if (input.isEmpty) {
      return null;
    }
    final split = input.split(' ');
    if (split.length != 2) {
      return null;
    }
    final dateParts = split.first.split('/');
    final timeParts = split.last.split(':');
    if (dateParts.length != 3 || timeParts.length != 2) {
      return null;
    }
    final day = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final year = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    try {
      final parsed = DateTime(year, month, day, hour, minute);
      if (parsed.year != year ||
          parsed.month != month ||
          parsed.day != day ||
          parsed.hour != hour ||
          parsed.minute != minute) {
        return null;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAirportDateTime(TextEditingController controller) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parsed = _parseAirportDateTime(controller.text);
    final initialDate = parsed != null && !parsed.isBefore(today)
        ? DateTime(parsed.year, parsed.month, parsed.day)
        : today;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (selectedDate == null || !mounted) {
      return;
    }

    final initialTime = parsed != null
        ? TimeOfDay(hour: parsed.hour, minute: parsed.minute)
        : TimeOfDay.fromDateTime(now);
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (selectedTime == null || !mounted) {
      return;
    }

    final dd = selectedDate.day.toString().padLeft(2, '0');
    final mm = selectedDate.month.toString().padLeft(2, '0');
    final yyyy = selectedDate.year.toString();
    final hh = selectedTime.hour.toString().padLeft(2, '0');
    final min = selectedTime.minute.toString().padLeft(2, '0');
    controller.text = '$dd/$mm/$yyyy $hh:$min';
    setState(() {});
  }

  Widget _buildStepperRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required IconData icon,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.32)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _gold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.remove_rounded,
            enabled: value > min,
            onTap: () => onChanged(value - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$value',
              style: const TextStyle(
                color: _gold,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add_rounded,
            enabled: value < max,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: enabled ? _gold.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? _gold.withOpacity(0.72) : _soft.withOpacity(0.3),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? _gold : _soft.withOpacity(0.55),
          ),
        ),
      ),
    );
  }

  Widget _buildMeetAndGreetToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _meetAndGreet
              ? _gold.withOpacity(0.7)
              : _gold.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.support_agent_rounded,
            color: _meetAndGreet ? _gold : _soft,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t(
                nl: 'Meet & greet',
                en: 'Meet & greet',
                fr: 'Accueil personnalisé',
                es: 'Recepción personalizada',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: _meetAndGreet,
            activeColor: _gold,
            inactiveThumbColor: _soft,
            inactiveTrackColor: const Color(0xFF2E2E2E),
            onChanged: (value) {
              _clearAirportQuote();
              setState(() {
                _meetAndGreet = value;
                if (!value) {
                  _nameBoardController.clear();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _useCurrentPickupLocation() async {
    if (_isResolvingPickupLocation) {
      return;
    }
    setState(() {
      _isResolvingPickupLocation = true;
    });
    try {
      final enabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatieservices staan uit op dit toestel.',
                en: 'Location services are turned off on this device.',
                fr: 'Les services de localisation sont désactivés sur cet appareil.',
                es: 'Los servicios de ubicación están desactivados en este dispositivo.',
              ),
            ),
          ),
        );
        return;
      }
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang geweigerd.',
                en: 'Location access denied.',
                fr: 'Accès à la localisation refusé.',
                es: 'Acceso a la ubicación denegado.',
              ),
            ),
          ),
        );
        return;
      }
      if (permission == geo.LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang is permanent geweigerd. Pas dit aan in instellingen.',
                en: 'Location access is permanently denied. Adjust this in settings.',
                fr: 'L’accès à la localisation est refusé de façon permanente. Modifiez cela dans les paramètres.',
                es: 'El acceso a la ubicación está denegado permanentemente. Ajústalo en la configuración.',
              ),
            ),
          ),
        );
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );

      if (!mounted) return;
      final lat = pos.latitude;
      final lng = pos.longitude;
      final resolvedAddress = await _reverseGeocodePickup(lat, lng);
      if (!mounted) return;
      final fallbackAddress =
          '${_t(nl: "Huidige locatie", en: "Current location", fr: "Position actuelle", es: "Ubicación actual")} (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
      setState(() {
        _pickupLatitude = lat;
        _pickupLongitude = lng;
        _pickupAddressController.text =
            (resolvedAddress != null && resolvedAddress.trim().isNotEmpty)
            ? resolvedAddress
            : fallbackAddress;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (resolvedAddress != null && resolvedAddress.trim().isNotEmpty)
                ? _t(
                    nl: 'Huidig adres ingevuld.',
                    en: 'Current address filled in.',
                    fr: 'Adresse actuelle renseignée.',
                    es: 'Dirección actual completada.',
                  )
                : _t(
                    nl: 'Huidige locatie ingevuld.',
                    en: 'Current location filled in.',
                    fr: 'Position actuelle renseignée.',
                    es: 'Ubicación actual completada.',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Huidige locatie kon niet worden opgehaald.',
              en: 'Could not fetch current location.',
              fr: 'Impossible de récupérer la position actuelle.',
              es: 'No se pudo obtener la ubicación actual.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingPickupLocation = false;
        });
      }
    }
  }

  Future<String?> _reverseGeocodePickup(double lat, double lng) async {
    if (_mapboxToken.trim().isEmpty) {
      return null;
    }
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/${lng.toStringAsFixed(6)},${lat.toStringAsFixed(6)}.json'
      '?access_token=${Uri.encodeComponent(_mapboxToken)}'
      '&language=${Uri.encodeComponent(_lang)}'
      '&limit=1',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final features = data['features'];
      if (features is! List || features.isEmpty) {
        return null;
      }
      final first = features.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final placeName = first['place_name'];
      if (placeName is! String) {
        return null;
      }
      final trimmed = placeName.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _useCurrentDestinationLocation() async {
    if (_isResolvingDestinationLocation) {
      return;
    }
    setState(() {
      _isResolvingDestinationLocation = true;
    });
    try {
      final enabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatieservices staan uit op dit toestel.',
                en: 'Location services are turned off on this device.',
                fr: 'Les services de localisation sont désactivés sur cet appareil.',
                es: 'Los servicios de ubicación están desactivados en este dispositivo.',
              ),
            ),
          ),
        );
        return;
      }
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang geweigerd.',
                en: 'Location access denied.',
                fr: 'Accès à la localisation refusé.',
                es: 'Acceso a la ubicación denegado.',
              ),
            ),
          ),
        );
        return;
      }
      if (permission == geo.LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang is permanent geweigerd. Pas dit aan in instellingen.',
                en: 'Location access is permanently denied. Adjust this in settings.',
                fr: 'L’accès à la localisation est refusé de façon permanente. Modifiez cela dans les paramètres.',
                es: 'El acceso a la ubicación está denegado permanentemente. Ajústalo en la configuración.',
              ),
            ),
          ),
        );
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );

      if (!mounted) return;
      final lat = pos.latitude;
      final lng = pos.longitude;
      final resolvedAddress = await _reverseGeocodePickup(lat, lng);
      if (!mounted) return;
      final fallbackAddress =
          '${_t(nl: "Huidige locatie", en: "Current location", fr: "Position actuelle", es: "Ubicación actual")} (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
      setState(() {
        _destinationLatitude = lat;
        _destinationLongitude = lng;
        _destinationAddressController.text =
            (resolvedAddress != null && resolvedAddress.trim().isNotEmpty)
            ? resolvedAddress
            : fallbackAddress;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (resolvedAddress != null && resolvedAddress.trim().isNotEmpty)
                ? _t(
                    nl: 'Huidig adres ingevuld.',
                    en: 'Current address filled in.',
                    fr: 'Adresse actuelle renseignée.',
                    es: 'Dirección actual completada.',
                  )
                : _t(
                    nl: 'Huidige locatie ingevuld.',
                    en: 'Current location filled in.',
                    fr: 'Position actuelle renseignée.',
                    es: 'Ubicación actual completada.',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Huidige locatie kon niet worden opgehaald.',
              en: 'Could not fetch current location.',
              fr: 'Impossible de récupérer la position actuelle.',
              es: 'No se pudo obtener la ubicación actual.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingDestinationLocation = false;
        });
      }
    }
  }

  void _clearAirportQuote() {
    if (!mounted) {
      return;
    }
    if (_airportQuote == null && _airportQuoteError == null) {
      return;
    }
    setState(() {
      _airportQuote = null;
      _airportQuoteError = null;
    });
  }

  void _handleSummaryInputChanged() {
    if (!mounted) {
      return;
    }
    _clearAirportQuote();
    setState(() {});
  }

  String _valueOrFallback(
    TextEditingController controller, {
    String? fallback,
  }) {
    final effectiveFallback =
        fallback ??
        _t(
          nl: 'Nog niet ingevuld',
          en: 'Not filled in yet',
          fr: 'Non renseigné',
          es: 'No completado',
        );
    final text = controller.text.trim();
    return text.isEmpty ? effectiveFallback : text;
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    int maxLines = 2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _gold.withOpacity(0.92), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: _soft.withOpacity(0.92),
                  fontSize: 10.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.4,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRideSummaryCard() {
    final isToAirport = _selectedMode == _TransferMode.toAirport;
    final selectedAirport = _selectedAirport;
    final flightNumber = _flightNumberController.text.trim();
    final note = _noteController.text.trim();
    final nameBoard = _nameBoardController.text.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.26)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _gold.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: _gold, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _t(
                    nl: 'Ritoverzicht',
                    en: 'Ride overview',
                    fr: 'Aperçu du trajet',
                    es: 'Resumen del viaje',
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _gold.withOpacity(0.58)),
                ),
                child: Text(
                  _t(nl: 'Lokaal', en: 'Local', fr: 'Local', es: 'Local'),
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 10.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _buildSummaryRow(
            icon: Icons.swap_horiz_rounded,
            label: _t(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo'),
            value: isToAirport
                ? _t(
                    nl: 'Naar de luchthaven',
                    en: 'To the airport',
                    fr: "Vers l'aéroport",
                    es: 'Al aeropuerto',
                  )
                : _t(
                    nl: 'Van de luchthaven',
                    en: 'From the airport',
                    fr: "Depuis l'aéroport",
                    es: 'Desde el aeropuerto',
                  ),
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            icon: Icons.public_rounded,
            label: _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
            value: selectedAirport.countryName,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            icon: Icons.flight_rounded,
            label: _t(
              nl: 'Luchthaven',
              en: 'Airport',
              fr: 'Aéroport',
              es: 'Aeropuerto',
            ),
            value: '${selectedAirport.name} (${selectedAirport.iata})',
          ),
          const SizedBox(height: 8),
          if (isToAirport) ...[
            _buildSummaryRow(
              icon: Icons.pin_drop_outlined,
              label: _t(
                nl: 'Ophaaladres',
                en: 'Pickup address',
                fr: 'Adresse de prise en charge',
                es: 'Dirección de recogida',
              ),
              value: _valueOrFallback(_pickupAddressController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.schedule_rounded,
              label: _t(
                nl: 'Ophaaldatum/tijd',
                en: 'Pickup date and time',
                fr: 'Date et heure de prise en charge',
                es: 'Fecha y hora de recogida',
              ),
              value: _valueOrFallback(_pickupDateTimeController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.groups_2_outlined,
              label: _t(
                nl: 'Passagiers',
                en: 'Passengers',
                fr: 'Passagers',
                es: 'Pasajeros',
              ),
              value: '$_passengers',
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.luggage_outlined,
              label: _t(
                nl: 'Bagage',
                en: 'Luggage',
                fr: 'Bagages',
                es: 'Equipaje',
              ),
              value: '$_bags',
              maxLines: 1,
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(
                icon: Icons.edit_note_rounded,
                label: _t(
                  nl: 'Opmerking',
                  en: 'Note',
                  fr: 'Remarque',
                  es: 'Nota',
                ),
                value: note,
              ),
            ],
          ] else ...[
            _buildSummaryRow(
              icon: Icons.location_on_outlined,
              label: _t(
                nl: 'Bestemming',
                en: 'Destination',
                fr: 'Destination',
                es: 'Destino',
              ),
              value: _valueOrFallback(_destinationAddressController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.confirmation_number_outlined,
              label: _t(
                nl: 'Vluchtnummer',
                en: 'Flight number',
                fr: 'Numéro de vol',
                es: 'Número de vuelo',
              ),
              value: flightNumber.isEmpty
                  ? _t(
                      nl: 'Optioneel',
                      en: 'Optional',
                      fr: 'Optionnel',
                      es: 'Opcional',
                    )
                  : flightNumber,
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.schedule_rounded,
              label: _t(
                nl: 'Landingsdatum/tijd',
                en: 'Landing date and time',
                fr: "Date et heure d'atterrissage",
                es: 'Fecha y hora de aterrizaje',
              ),
              value: _valueOrFallback(_landingDateTimeController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.support_agent_rounded,
              label: _t(
                nl: 'Meet & greet',
                en: 'Meet & greet',
                fr: 'Accueil personnalisé',
                es: 'Recepción personalizada',
              ),
              value: _meetAndGreet
                  ? _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Sí')
                  : _t(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
              maxLines: 1,
            ),
            if (_meetAndGreet) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(
                icon: Icons.badge_outlined,
                label: _t(
                  nl: 'Naam bordje',
                  en: 'Name on sign',
                  fr: 'Nom sur pancarte',
                  es: 'Nombre en cartel',
                ),
                value: nameBoard.isEmpty
                    ? _valueOrFallback(_nameBoardController)
                    : nameBoard,
              ),
            ],
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.groups_2_outlined,
              label: _t(
                nl: 'Passagiers',
                en: 'Passengers',
                fr: 'Passagers',
                es: 'Pasajeros',
              ),
              value: '$_passengers',
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.luggage_outlined,
              label: _t(
                nl: 'Bagage',
                en: 'Luggage',
                fr: 'Bagages',
                es: 'Equipaje',
              ),
              value: '$_bags',
              maxLines: 1,
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _gold.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: _gold, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t(
                      nl: 'Status: Klaar voor prijsberekening',
                      en: 'Status: Ready for price calculation',
                      fr: 'Statut : prêt pour le calcul du prix',
                      es: 'Estado: listo para calcular el precio',
                    ),
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 11.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _isRequestingQuote ? null : _prepareAirportBookingDetails,
        child: Text(
          _isRequestingQuote
              ? _t(
                  nl: 'Prijs berekenen...',
                  en: 'Calculating price...',
                  fr: 'Calcul du prix...',
                  es: 'Calculando precio...',
                )
              : _t(
                  nl: 'Ritgegevens voorbereiden',
                  en: 'Prepare ride details',
                  fr: 'Préparer les détails du trajet',
                  es: 'Preparar detalles del viaje',
                ),
        ),
      ),
    );
  }

  String? _validatePrepareRideDetailsMessage() {
    final isToAirport = _selectedMode == _TransferMode.toAirport;
    if (isToAirport) {
      if (_pickupAddressController.text.trim().isEmpty) {
        return _t(
          nl: 'Vul eerst het ophaaladres in.',
          en: 'Enter the pickup address first.',
          fr: "Saisissez d'abord l'adresse de prise en charge.",
          es: 'Primero introduce la dirección de recogida.',
        );
      }
      if (_pickupDateTimeController.text.trim().isEmpty) {
        return _t(
          nl: 'Kies eerst de ophaaldatum en tijd.',
          en: 'Select pickup date and time first.',
          fr: "Choisissez d'abord la date et l'heure de prise en charge.",
          es: 'Primero selecciona la fecha y hora de recogida.',
        );
      }
      if (_filteredAirports.isEmpty) {
        return _t(
          nl: 'Kies eerst een luchthaven.',
          en: 'Select an airport first.',
          fr: "Choisissez d'abord un aéroport.",
          es: 'Primero selecciona un aeropuerto.',
        );
      }
      if (_passengers < 1) {
        return _t(
          nl: 'Kies minstens 1 passagier.',
          en: 'Select at least 1 passenger.',
          fr: 'Sélectionnez au moins 1 passager.',
          es: 'Selecciona al menos 1 pasajero.',
        );
      }
    } else {
      if (_destinationAddressController.text.trim().isEmpty) {
        return _t(
          nl: 'Vul eerst de bestemming in.',
          en: 'Enter the destination first.',
          fr: "Saisissez d'abord la destination.",
          es: 'Primero introduce el destino.',
        );
      }
      if (_landingDateTimeController.text.trim().isEmpty) {
        return _t(
          nl: 'Kies eerst de landingsdatum en tijd.',
          en: 'Select landing date and time first.',
          fr: "Choisissez d'abord la date et l'heure d'atterrissage.",
          es: 'Primero selecciona la fecha y hora de aterrizaje.',
        );
      }
      if (_filteredAirports.isEmpty) {
        return _t(
          nl: 'Kies eerst een luchthaven.',
          en: 'Select an airport first.',
          fr: "Choisissez d'abord un aéroport.",
          es: 'Primero selecciona un aeropuerto.',
        );
      }
      if (_passengers < 1) {
        return _t(
          nl: 'Kies minstens 1 passagier.',
          en: 'Select at least 1 passenger.',
          fr: 'Sélectionnez au moins 1 passager.',
          es: 'Selecciona al menos 1 pasajero.',
        );
      }
      if (_meetAndGreet && _nameBoardController.text.trim().isEmpty) {
        return _t(
          nl: 'Vul de naam voor het bordje in.',
          en: 'Enter the name for the sign.',
          fr: 'Saisissez le nom pour la pancarte.',
          es: 'Introduce el nombre para el cartel.',
        );
      }
    }
    return null;
  }

  void _handlePrepareRideDetails() {
    final errorMessage = _validatePrepareRideDetailsMessage();
    final snackBarMessage =
        errorMessage ??
        _t(
          nl: 'Ritgegevens voorbereid. Prijsberekening wordt in de volgende stap gekoppeld.',
          en: 'Ride details prepared. Price calculation is connected in the next step.',
          fr: 'Détails du trajet préparés. Le calcul du prix est relié à l’étape suivante.',
          es: 'Detalles del viaje preparados. El cálculo del precio se conectará en el siguiente paso.',
        );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(snackBarMessage)));
  }

  String _fmtDateYmd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _fmtTimeHm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _isoLikeLocal(DateTime dt) =>
      '${_fmtDateYmd(dt)}T${_fmtTimeHm(dt)}:00';

  bool _hasValidCoordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) {
      return false;
    }
    if (!latitude.isFinite || !longitude.isFinite) {
      return false;
    }
    if (latitude < -90 || latitude > 90) {
      return false;
    }
    if (longitude < -180 || longitude > 180) {
      return false;
    }
    return true;
  }

  Map<String, dynamic>? _buildAirportQuotePayload() {
    final selectedAirport = _selectedAirport;
    final isToAirport = _selectedMode == _TransferMode.toAirport;
    final dateSource = isToAirport
        ? _pickupDateTimeController.text
        : _landingDateTimeController.text;
    final parsedDate = _parseAirportDateTime(dateSource);
    if (parsedDate == null) {
      return null;
    }
    String tenantId = _selectedTenantId;
    String companyId = _selectedCompanyId;
    if ((tenantId.isEmpty || companyId.isEmpty) &&
        widget.allowAdminScopeFallback) {
      final effectiveScope = resolveEffectiveTenantCompanyScope(
        allowDriverFallback: true,
      );
      tenantId = effectiveScope.tenantId;
      companyId = effectiveScope.companyId;
    }
    if (tenantId.isEmpty || companyId.isEmpty) {
      return null;
    }
    final fromText = isToAirport
        ? _pickupAddressController.text.trim()
        : '${selectedAirport.name}, ${selectedAirport.countryName}';
    final toText = isToAirport
        ? '${selectedAirport.name}, ${selectedAirport.countryName}'
        : _destinationAddressController.text.trim();
    if (fromText.isEmpty || toText.isEmpty) {
      return null;
    }
    final note = _noteController.text.trim();
    final flightNumber = _flightNumberController.text.trim();
    final nameBoard = _nameBoardController.text.trim();
    final hasAirportCoordinates = _hasValidCoordinates(
      selectedAirport.latitude,
      selectedAirport.longitude,
    );
    debugPrint(
      '[AIRPORT_QUOTE] airport=${selectedAirport.id}/${selectedAirport.iata} '
      'direction=${isToAirport ? "to_airport" : "from_airport"} '
      'airport_coords=$hasAirportCoordinates',
    );
    return <String, dynamic>{
      'from': fromText,
      'to': toText,
      'date': _fmtDateYmd(parsedDate),
      'time': _fmtTimeHm(parsedDate),
      'pickup_iso': _isoLikeLocal(parsedDate),
      'tier': 'COMFORT',
      'service': 'AIRPORT',
      'pax': _passengers,
      'bags': _bags,
      'tenant_id': tenantId,
      'company_id': companyId,
      'tenantId': tenantId,
      'companyId': companyId,
      if (_selectedCompanyCode.isNotEmpty) ...{
        'company_code': _selectedCompanyCode,
        'companyCode': _selectedCompanyCode,
      },
      if (_selectedCompanyName.isNotEmpty) ...{
        'public_partner_name': _selectedCompanyName,
        'publicPartnerName': _selectedCompanyName,
      },
      if (_selectedPartnerId.isNotEmpty) ...{
        'public_partner_id': _selectedPartnerId,
        'publicPartnerId': _selectedPartnerId,
        'partner_id': _selectedPartnerId,
        'partnerId': _selectedPartnerId,
      },
      'airport_direction': isToAirport ? 'to_airport' : 'from_airport',
      'airport_id': selectedAirport.id,
      'airport_iata': selectedAirport.iata,
      'airport_name': selectedAirport.name,
      'airport_country': selectedAirport.countryName,
      if (note.isNotEmpty) 'note': note,
      if (hasAirportCoordinates && isToAirport) ...{
        'to_lat': selectedAirport.latitude,
        'to_lng': selectedAirport.longitude,
      },
      if (hasAirportCoordinates && !isToAirport) ...{
        'from_lat': selectedAirport.latitude,
        'from_lng': selectedAirport.longitude,
      },
      if (isToAirport) ...{
        if (_pickupLatitude != null) 'pickup_lat': _pickupLatitude,
        if (_pickupLongitude != null) 'pickup_lng': _pickupLongitude,
      } else ...{
        if (_destinationLatitude != null)
          'destination_lat': _destinationLatitude,
        if (_destinationLongitude != null)
          'destination_lng': _destinationLongitude,
        if (flightNumber.isNotEmpty) 'flight_number': flightNumber,
        'meet_and_greet': _meetAndGreet,
        if (nameBoard.isNotEmpty) 'name_board': nameBoard,
      },
    };
  }

  Future<Map<String, dynamic>?> _requestAirportQuoteForReview({
    required bool showSuccessSnackbar,
  }) async {
    if (_isRequestingQuote) {
      return _airportQuote;
    }
    final validationError = _validatePrepareRideDetailsMessage();
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return null;
    }
    final payload = _buildAirportQuotePayload();
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kies eerst een taxipartner voor luchthavenvervoer.',
              en: 'Select a taxi partner first for airport rides.',
              fr: "Choisissez d'abord un partenaire taxi pour les transferts aéroport.",
              es: 'Selecciona primero un socio de taxi para traslados al aeropuerto.',
            ),
          ),
        ),
      );
      return null;
    }
    setState(() {
      _isRequestingQuote = true;
      _airportQuoteError = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('${widget.bookingBaseUrl}/quote'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      final dynamic decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : null;
      final isOk =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data?['ok'] == true;
      if (!mounted) {
        return null;
      }
      if (isOk && data != null) {
        setState(() {
          _airportQuote = data;
          _airportQuoteError = null;
        });
        if (showSuccessSnackbar) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  nl: 'Prijsberekening opgehaald.',
                  en: 'Price calculation retrieved.',
                  fr: 'Calcul du prix récupéré.',
                  es: 'Cálculo del precio obtenido.',
                ),
              ),
            ),
          );
        }
        return data;
      }
      setState(() {
        _airportQuote = null;
        _airportQuoteError = _t(
          nl: 'Prijsberekening kon niet worden opgehaald.',
          en: 'Price calculation could not be retrieved.',
          fr: "Le calcul du prix n'a pas pu être récupéré.",
          es: 'No se pudo obtener el cálculo del precio.',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_airportQuoteError!)));
      return null;
    } catch (_) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _airportQuote = null;
        _airportQuoteError = _t(
          nl: 'Prijsberekening kon niet worden opgehaald.',
          en: 'Price calculation could not be retrieved.',
          fr: "Le calcul du prix n'a pas pu être récupéré.",
          es: 'No se pudo obtener el cálculo del precio.',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_airportQuoteError!)));
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingQuote = false;
        });
      }
    }
  }

  Future<void> _prepareAirportBookingDetails() async {
    final payload = _buildAirportQuotePayload();
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Ritgegevens zijn nog niet volledig ingevuld.',
              en: 'Ride details are not complete yet.',
              fr: 'Les détails du trajet ne sont pas encore complets.',
              es: 'Los datos del viaje aún no están completos.',
            ),
          ),
        ),
      );
      return;
    }
    var quote = _airportQuote;
    quote ??= await _requestAirportQuoteForReview(showSuccessSnackbar: false);
    if (quote == null || !mounted) {
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AirportBookingReviewPage(
          bookingBaseUrl: widget.bookingBaseUrl,
          quote: Map<String, dynamic>.from(quote!),
          payload: Map<String, dynamic>.from(payload),
          languageCode: appConfig.currentLanguage.name,
          currencySymbol: '€',
        ),
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _requestAirportQuote() async {
    await _requestAirportQuoteForReview(showSuccessSnackbar: true);
  }

  double? _quoteNum(dynamic value) {
    if (value is num) {
      final n = value.toDouble();
      return n.isFinite ? n : null;
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text.replaceAll(',', '.'));
  }

  bool _isFixedAirportFareQuote(Map<String, dynamic> quote) {
    bool asBool(dynamic value) {
      if (value is bool) {
        return value;
      }
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    String asText(dynamic value) {
      return value?.toString().trim().toLowerCase() ?? '';
    }

    if (asBool(quote['fixed_fare_applied'])) {
      return true;
    }
    if (asText(quote['pricing_source']) == 'airport_fixed_fare') {
      return true;
    }
    final breakdownRaw = quote['breakdown'];
    if (breakdownRaw is Map) {
      final breakdown = Map<String, dynamic>.from(breakdownRaw);
      if (asText(breakdown['kind']) == 'airport_fixed_fare') {
        return true;
      }
    }
    return false;
  }

  String? _fixedFareRuleIdFromQuote(Map<String, dynamic> quote) {
    String? nonEmpty(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final topLevel = nonEmpty(quote['fixed_fare_rule_id']);
    if (topLevel != null) {
      return topLevel;
    }
    final breakdownRaw = quote['breakdown'];
    if (breakdownRaw is Map) {
      return nonEmpty(breakdownRaw['fixed_fare_rule_id']);
    }
    return null;
  }

  Widget _buildAirportQuoteCard() {
    final quote = _airportQuote;
    final error = _airportQuoteError;
    final totalIncl = _quoteNum(quote?['total_price_incl_vat']);
    final mainIncl = _quoteNum(quote?['price_incl_vat']);
    final displayPrice = totalIncl ?? mainIncl;
    final distance = _quoteNum(quote?['distance_km']);
    final duration = _quoteNum(quote?['duration_min']);
    final hasFixedFare =
        quote != null &&
        _isFixedAirportFareQuote(Map<String, dynamic>.from(quote));
    final fixedFareRuleId = quote == null
        ? null
        : _fixedFareRuleIdFromQuote(Map<String, dynamic>.from(quote));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_rounded, color: _gold, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _t(
                    nl: 'Prijsindicatie',
                    en: 'Price indication',
                    fr: 'Indication de prix',
                    es: 'Indicación de precio',
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (error != null)
            Text(error, style: const TextStyle(color: _soft, fontSize: 12))
          else if (quote != null) ...[
            Row(
              children: [
                Text(
                  _t(
                    nl: 'Geschatte prijs',
                    en: 'Estimated price',
                    fr: 'Prix estimé',
                    es: 'Precio estimado',
                  ),
                  style: TextStyle(
                    color: _soft.withOpacity(0.95),
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  displayPrice != null
                      ? '€ ${displayPrice.toStringAsFixed(2)}'
                      : '—',
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (hasFixedFare) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _gold.withOpacity(0.48)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: _gold.withOpacity(0.96),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _t(
                          nl: 'Vast tarief volgens bedrijfsregel',
                          en: 'Fixed fare by company rule',
                          fr: 'Tarif fixe selon la règle d’entreprise',
                          es: 'Tarifa fija según regla de empresa',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 11.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  nl: 'Deze prijs komt uit de ingestelde luchthavenregels van het bedrijf.',
                  en: 'This price comes from the company’s configured airport rules.',
                  fr: 'Ce prix provient des règles aéroport configurées par l’entreprise.',
                  es: 'Este precio proviene de las reglas de aeropuerto configuradas por la empresa.',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _soft.withOpacity(0.9),
                  fontSize: 10.8,
                  height: 1.2,
                ),
              ),
              if (fixedFareRuleId != null) ...[
                const SizedBox(height: 3),
                Text(
                  '${_t(nl: "Tariefregel", en: "Fare rule", fr: "Règle tarifaire", es: "Regla de tarifa")}: $fixedFareRuleId',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _soft.withOpacity(0.93),
                    fontSize: 10.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    distance != null
                        ? '${_t(nl: "Afstand", en: "Distance", fr: "Distance", es: "Distancia")}: ${distance.toStringAsFixed(1)} km'
                        : '${_t(nl: "Afstand", en: "Distance", fr: "Distance", es: "Distancia")}: —',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.84),
                      fontSize: 11.6,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    duration != null
                        ? '${_t(nl: "Duur", en: "Duration", fr: "Durée", es: "Duración")}: ${duration.toStringAsFixed(0)} min'
                        : '${_t(nl: "Duur", en: "Duration", fr: "Durée", es: "Duración")}: —',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.84),
                      fontSize: 11.6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: TextStyle(color: _soft.withOpacity(0.95), fontSize: 12.2),
      hintStyle: TextStyle(color: _soft.withOpacity(0.55), fontSize: 12),
      prefixIcon: Icon(prefixIcon, color: _gold.withOpacity(0.92), size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF181818),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withOpacity(0.32)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.2),
      ),
    );
  }
}
