import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

enum _TransferMode { toAirport, fromAirport }

class _AirportOption {
  const _AirportOption({
    required this.id,
    required this.countryCode,
    required this.countryName,
    required this.city,
    required this.name,
    required this.iata,
  });

  final String id;
  final String countryCode;
  final String countryName;
  final String city;
  final String name;
  final String iata;
}

class AirportPage extends StatefulWidget {
  const AirportPage({super.key});

  @override
  State<AirportPage> createState() => _AirportPageState();
}

class _AirportPageState extends State<AirportPage> {
  static const Color _bg = Color(0xFF07080C);
  static const Color _panel = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _soft = Color(0xFFB4B4B4);
  static const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

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

  _TransferMode _selectedMode = _TransferMode.toAirport;
  String _selectedCountryCode = _airports.first.countryCode;
  String _selectedAirportId = _airports.first.id;
  int _passengers = 1;
  int _bags = 0;
  bool _meetAndGreet = false;
  bool _isResolvingPickupLocation = false;
  double? _pickupLatitude;
  double? _pickupLongitude;

  List<String> get _availableCountryCodes {
    final unique = <String>{};
    final codes = <String>[];
    for (final airport in _airports) {
      if (unique.add(airport.countryCode)) {
        codes.add(airport.countryCode);
      }
    }
    return codes;
  }

  List<_AirportOption> get _filteredAirports => _airports
      .where((airport) => airport.countryCode == _selectedCountryCode)
      .toList(growable: false);

  _AirportOption get _selectedAirport {
    final filtered = _filteredAirports;
    if (filtered.isEmpty) {
      return _airports.first;
    }
    return filtered.firstWhere(
      (airport) => airport.id == _selectedAirportId,
      orElse: () => filtered.first,
    );
  }

  String _countryLabelForCode(String countryCode) {
    switch (countryCode) {
      case 'BE':
        return 'België';
      case 'NL':
        return 'Nederland';
      case 'FR':
        return 'Frankrijk';
      case 'GB':
        return 'Verenigd Koninkrijk';
      default:
        final fallback = _airports
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
    final firstAirport = _airports.firstWhere(
      (airport) => airport.countryCode == countryCode,
      orElse: () => _airports.first,
    );
    setState(() {
      _selectedCountryCode = countryCode;
      _selectedAirportId = firstAirport.id;
    });
  }

  void _setAirport(String airportId) {
    setState(() {
      _selectedAirportId = airportId;
    });
  }

  Widget _buildCountryDropdown() {
    return InputDecorator(
      decoration: _fieldDecoration(
        label: 'Land',
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
        label: 'Luchthaven',
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
            tooltip: 'Terug',
          ),
          const SizedBox(width: 2),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Luchthavenvervoer',
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
                  'Premium transfers voor comfortabele ritten van en naar de luchthaven',
                  style: TextStyle(color: _soft, fontSize: 11.5, height: 1.2),
                ),
              ],
            ),
          ),
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
                  'Zakelijk en privé luchthavenvervoer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 13.6 : 14.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: compact ? 3 : 4),
                Text(
                  'Plan binnenkort direct uw transfer met heldere serviceopties en betrouwbare chauffeurs.',
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
          title: 'Naar de luchthaven',
          subtitle: 'Vertrek naar uw vlucht',
          icon: Icons.flight_takeoff_rounded,
          mode: _TransferMode.toAirport,
        );
        final second = _actionCard(
          title: 'Van de luchthaven',
          subtitle: 'Aankomst op de luchthaven',
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
                    child: const Text(
                      'Actief',
                      style: TextStyle(
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
          ? 'Intake: naar de luchthaven'
          : 'Intake: van de luchthaven',
      icon: isToAirport
          ? Icons.directions_car_filled_rounded
          : Icons.local_taxi_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isToAirport) ...[
            _buildTextField(
              label: 'Ophaaladres',
              controller: _pickupAddressController,
              hint: 'Straat, nummer, postcode, stad',
              icon: Icons.pin_drop_outlined,
              suffixIcon: IconButton(
                onPressed: _isResolvingPickupLocation
                    ? null
                    : _useCurrentPickupLocation,
                tooltip: 'Huidige locatie gebruiken',
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
              label: 'Ophaaldatum en tijd',
              controller: _pickupDateTimeController,
              hint: 'Bijv. 21/06/2026 - 05:45',
              icon: Icons.schedule_rounded,
              readOnly: true,
              onTap: () => _pickAirportDateTime(_pickupDateTimeController),
              suffixIcon: IconButton(
                onPressed: () =>
                    _pickAirportDateTime(_pickupDateTimeController),
                tooltip: 'Datum en tijd kiezen',
                icon: Icon(
                  Icons.calendar_month_rounded,
                  color: _gold.withOpacity(0.92),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Passagiers',
              value: _passengers,
              min: 1,
              max: 8,
              icon: Icons.groups_2_outlined,
              onChanged: (value) => setState(() => _passengers = value),
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Bagage',
              value: _bags,
              min: 0,
              max: 12,
              icon: Icons.luggage_outlined,
              onChanged: (value) => setState(() => _bags = value),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Opmerking (optioneel)',
              controller: _noteController,
              hint: 'Extra info voor de chauffeur',
              icon: Icons.edit_note_rounded,
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            Text(
              'Prijsberekening en boeking worden in een volgende stap gekoppeld.',
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
              label: 'Bestemmingsadres',
              controller: _destinationAddressController,
              hint: 'Straat, nummer, postcode, stad',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Vluchtnummer (optioneel)',
              controller: _flightNumberController,
              hint: 'Bijv. SN204',
              icon: Icons.confirmation_number_outlined,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              label: 'Landingsdatum en tijd',
              controller: _landingDateTimeController,
              hint: 'Bijv. 21/06/2026 - 18:20',
              icon: Icons.schedule_rounded,
              readOnly: true,
              onTap: () => _pickAirportDateTime(_landingDateTimeController),
              suffixIcon: IconButton(
                onPressed: () =>
                    _pickAirportDateTime(_landingDateTimeController),
                tooltip: 'Datum en tijd kiezen',
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
                label: 'Naam op bordje',
                controller: _nameBoardController,
                hint: 'Bijv. Mevr. Van Dijk',
                icon: Icons.badge_outlined,
              ),
            ],
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Passagiers',
              value: _passengers,
              min: 1,
              max: 8,
              icon: Icons.groups_2_outlined,
              onChanged: (value) => setState(() => _passengers = value),
            ),
            const SizedBox(height: 10),
            _buildStepperRow(
              label: 'Bagage',
              value: _bags,
              min: 0,
              max: 12,
              icon: Icons.luggage_outlined,
              onChanged: (value) => setState(() => _bags = value),
            ),
            const SizedBox(height: 10),
            Text(
              'Vluchttracking en boeking worden in een volgende stap gekoppeld.',
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
          const Expanded(
            child: Text(
              'Meet & greet',
              style: TextStyle(
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
          const SnackBar(
            content: Text('Locatieservices staan uit op dit toestel.'),
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
          const SnackBar(content: Text('Locatietoegang geweigerd.')),
        );
        return;
      }
      if (permission == geo.LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Locatietoegang is permanent geweigerd. Pas dit aan in instellingen.',
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
          'Huidige locatie (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
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
                ? 'Huidig adres ingevuld.'
                : 'Huidige locatie ingevuld.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Huidige locatie kon niet worden opgehaald.'),
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
      '&language=nl'
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

  void _handleSummaryInputChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  String _valueOrFallback(
    TextEditingController controller, {
    String fallback = 'Nog niet ingevuld',
  }) {
    final text = controller.text.trim();
    return text.isEmpty ? fallback : text;
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
              const Expanded(
                child: Text(
                  'Ritoverzicht',
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
                child: const Text(
                  'Lokaal',
                  style: TextStyle(
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
            label: 'Type',
            value: isToAirport ? 'Naar de luchthaven' : 'Van de luchthaven',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            icon: Icons.public_rounded,
            label: 'Land',
            value: selectedAirport.countryName,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            icon: Icons.flight_rounded,
            label: 'Luchthaven',
            value: '${selectedAirport.name} (${selectedAirport.iata})',
          ),
          const SizedBox(height: 8),
          if (isToAirport) ...[
            _buildSummaryRow(
              icon: Icons.pin_drop_outlined,
              label: 'Ophaaladres',
              value: _valueOrFallback(_pickupAddressController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.schedule_rounded,
              label: 'Ophaaldatum/tijd',
              value: _valueOrFallback(_pickupDateTimeController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.groups_2_outlined,
              label: 'Passagiers',
              value: '$_passengers',
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.luggage_outlined,
              label: 'Bagage',
              value: '$_bags',
              maxLines: 1,
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(
                icon: Icons.edit_note_rounded,
                label: 'Opmerking',
                value: note,
              ),
            ],
          ] else ...[
            _buildSummaryRow(
              icon: Icons.location_on_outlined,
              label: 'Bestemming',
              value: _valueOrFallback(_destinationAddressController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Vluchtnummer',
              value: flightNumber.isEmpty ? 'Optioneel' : flightNumber,
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.schedule_rounded,
              label: 'Landingsdatum/tijd',
              value: _valueOrFallback(_landingDateTimeController),
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.support_agent_rounded,
              label: 'Meet & greet',
              value: _meetAndGreet ? 'Ja' : 'Nee',
              maxLines: 1,
            ),
            if (_meetAndGreet) ...[
              const SizedBox(height: 8),
              _buildSummaryRow(
                icon: Icons.badge_outlined,
                label: 'Naam bordje',
                value: nameBoard.isEmpty ? 'Nog niet ingevuld' : nameBoard,
              ),
            ],
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.groups_2_outlined,
              label: 'Passagiers',
              value: '$_passengers',
              maxLines: 1,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              icon: Icons.luggage_outlined,
              label: 'Bagage',
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
            child: const Row(
              children: [
                Icon(Icons.verified_rounded, color: _gold, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Status: Klaar voor prijsberekening',
                    style: TextStyle(
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
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Deze flow koppelt in de volgende fase met prijsberekening en boeking.',
              ),
            ),
          );
        },
        child: const Text('Ritgegevens voorbereiden'),
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
