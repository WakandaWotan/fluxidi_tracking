import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';

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

  late final List<HotelStay> _allStays;
  String _selectedCity = 'all';
  String _selectedRegion = 'all';
  String _selectedType = 'all';

  String _t({required String nl, required String en}) {
    return appConfig.currentLanguage.name == 'en' ? en : nl;
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

  List<String> get _cityOptions {
    final values = _allStays.map((stay) => stay.city).toSet().toList()..sort();
    return <String>['all', ...values];
  }

  List<String> get _regionOptions {
    final values = _allStays.map((stay) => stay.region).toSet().toList()
      ..sort();
    return <String>['all', ...values];
  }

  List<HotelStay> get _visibleStays {
    final query = _searchController.text.trim().toLowerCase();
    return _allStays
        .where((stay) {
          if (_selectedCity != 'all' && stay.city != _selectedCity)
            return false;
          if (_selectedRegion != 'all' && stay.region != _selectedRegion) {
            return false;
          }
          if (_selectedType != 'all' && stay.type != _selectedType)
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
      case 'all':
        return _t(nl: 'Alle types', en: 'All types');
      case HotelStayType.hotel:
        return 'Hotel';
      case HotelStayType.bedAndBreakfast:
        return 'B&B';
      case HotelStayType.aparthotel:
        return _t(nl: 'Aparthotel', en: 'Aparthotel');
      case HotelStayType.guesthouse:
        return _t(nl: 'Guesthouse', en: 'Guesthouse');
      default:
        return typeKey;
    }
  }

  String _cityLabel(String city) {
    return city == 'all' ? _t(nl: 'Alle steden', en: 'All cities') : city;
  }

  String _regionLabel(String region) {
    return region == 'all'
        ? _t(nl: 'Alle regio\'s', en: 'All regions')
        : region;
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
            tooltip: _t(nl: 'Terug', en: 'Back'),
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
                  label: _t(nl: 'Stad', en: 'City'),
                  value: _selectedCity,
                  options: _cityOptions,
                  itemLabelBuilder: _cityLabel,
                  onChanged: (value) =>
                      setState(() => _selectedCity = value ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdownFilter(
                  label: _t(nl: 'Regio', en: 'Region'),
                  value: _selectedRegion,
                  options: _regionOptions,
                  itemLabelBuilder: _regionLabel,
                  onChanged: (value) =>
                      setState(() => _selectedRegion = value ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children:
                <String>[
                  'all',
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
    required List<String> options,
    required String Function(String value) itemLabelBuilder,
    required void Function(String? value) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: options.contains(value) ? value : 'all',
      isExpanded: true,
      dropdownColor: _panelBlack,
      iconEnabledColor: _gold,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
              value: option,
              child: Text(
                itemLabelBuilder(option),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildResultSummary(int count) {
    final text = _t(nl: '$count verblijven gevonden', en: '$count stays found');
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
        const spacing = 10.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stays.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: 315,
          ),
          itemBuilder: (_, index) => _buildStayCard(stays[index]),
        );
      },
    );
  }

  Widget _buildStayCard(HotelStay stay) {
    return Container(
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 118,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF1D2538), Color(0xFF101522)],
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.hotel_rounded,
                    size: 46,
                    color: _gold.withOpacity(0.85),
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
                      fontSize: 15.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stay.city}, ${stay.region}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _gold.withOpacity(0.92),
                      fontSize: 11.8,
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
                  const SizedBox(height: 7),
                  if (stay.tags.isNotEmpty)
                    Text(
                      stay.tags.take(3).join('  |  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (stay.priceHint != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      stay.priceHint!,
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _onTaxiCtaTap(stay),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFF171209),
                        foregroundColor: _gold,
                        side: BorderSide(color: _gold.withOpacity(0.5)),
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
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
