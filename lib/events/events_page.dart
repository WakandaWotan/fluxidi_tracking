import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'events_detail_page.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({this.onBookEvent, super.key});

  final EventBookCallback? onBookEvent;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  static const List<String> _filters = <String>[
    'Alles',
    'Vandaag',
    'Dit weekend',
    'Muziek',
    'Zakelijk',
    'Sport',
  ];
  static const List<String> _markets = <String>[
    'België',
    'Nederland',
    'Frankrijk',
    'VK',
  ];

  final TextEditingController _searchController = TextEditingController();
  int _selectedMarketIndex = 0;
  int _selectedFilterIndex = 0;
  int _selectedTabIndex = 0;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.nl:
        return nl;
    }
  }

  String get _ctaCardLabel => _t(
    nl: 'Taxi naar dit event',
    en: 'Taxi to this event',
    fr: 'Taxi vers cet événement',
    es: 'Taxi a este evento',
  );

  final List<EventDetailData> _events = const <EventDetailData>[
    EventDetailData(
      id: 'evt_antwerp_jazz_2026',
      title: 'Antwerp Jazz Nights 2026',
      category: 'Muziek',
      dateTimeLabel: 'Vrijdag • 19:30',
      locationName: 'Stadspark Arena',
      city: 'Antwerpen',
      address: 'Van Eycklei 1, 2018 Antwerpen, België',
      lat: 51.208186,
      lng: 4.418731,
      distanceOrStatus: '2.1 km',
      gradient: <Color>[Color(0xFF2A1F08), Color(0xFF15120A)],
      sourceLabel: 'Fluxidi Curated',
    ),
    EventDetailData(
      id: 'evt_brussels_mobility_summit_2026',
      title: 'Brussels Mobility Summit',
      category: 'Zakelijk',
      dateTimeLabel: 'Dinsdag • 09:00',
      locationName: 'Brussels Expo Hall 7',
      city: 'Brussel',
      address: 'Belgiëplein 1, 1020 Brussel, België',
      lat: 50.897227,
      lng: 4.338472,
      distanceOrStatus: 'Gepland',
      gradient: <Color>[Color(0xFF2A260E), Color(0xFF12110A)],
      sourceLabel: 'Fluxidi Curated',
    ),
    EventDetailData(
      id: 'evt_ghent_night_run_2026',
      title: 'Ghent Night Run',
      category: 'Sport',
      dateTimeLabel: 'Zaterdag • 20:30',
      locationName: 'Sport Vlaanderen Gent',
      city: 'Gent',
      address: 'Zuiderlaan 14, 9000 Gent, België',
      lat: 51.026364,
      lng: 3.703992,
      distanceOrStatus: '5.4 km',
      gradient: <Color>[Color(0xFF1F1A0C), Color(0xFF100F0A)],
      sourceLabel: 'Fluxidi Curated',
    ),
    EventDetailData(
      id: 'evt_leuven_food_market_2026',
      title: 'Leuven Food & Culture Market',
      category: 'Vandaag',
      dateTimeLabel: 'Vandaag • 17:00',
      locationName: 'Grote Markt Leuven',
      city: 'Leuven',
      address: 'Grote Markt 1, 3000 Leuven, België',
      lat: 50.879842,
      lng: 4.700517,
      distanceOrStatus: 'Actief',
      gradient: <Color>[Color(0xFF2E220B), Color(0xFF141108)],
      sourceLabel: 'Fluxidi Curated',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EventDetailData> get _visibleEvents {
    final query = _searchController.text.trim().toLowerCase();
    final selectedFilter = _filters[_selectedFilterIndex];
    return _events
        .where((event) {
          final matchesSearch =
              query.isEmpty ||
              event.title.toLowerCase().contains(query) ||
              event.locationName.toLowerCase().contains(query) ||
              event.city.toLowerCase().contains(query) ||
              event.address.toLowerCase().contains(query) ||
              event.category.toLowerCase().contains(query);
          if (!matchesSearch) return false;
          if (selectedFilter == 'Alles') return true;
          if (selectedFilter == 'Dit weekend') {
            return event.dateTimeLabel.toLowerCase().contains('zaterdag') ||
                event.dateTimeLabel.toLowerCase().contains('zondag') ||
                event.dateTimeLabel.toLowerCase().contains('vrijdag');
          }
          return event.category.toLowerCase() == selectedFilter.toLowerCase() ||
              event.dateTimeLabel.toLowerCase().contains(
                selectedFilter.toLowerCase(),
              );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentPadding = screenWidth < 360 ? 11.0 : 14.0;
    final events = _visibleEvents;
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  contentPadding,
                  6,
                  contentPadding,
                  14,
                ),
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 6),
                  _buildMarketChips(),
                  const SizedBox(height: 7),
                  _buildFilterChips(),
                  const SizedBox(height: 9),
                  _buildSegmentedToggle(),
                  const SizedBox(height: 10),
                  if (_selectedTabIndex == 0) ...[
                    if (events.isEmpty)
                      _buildEmptyState()
                    else
                      _buildEventList(events),
                  ] else
                    _buildMapPlaceholder(),
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
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: _gold,
            tooltip: _t(nl: 'Terug', en: 'Back', fr: 'Retour', es: 'Volver'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Evenementen',
                      en: 'Events',
                      fr: 'Événements',
                      es: 'Eventos',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _t(
                      nl: 'Evenementen en vervoer in uw regio',
                      en: 'Events and transport in your area',
                      fr: 'Événements et transport dans votre région',
                      es: 'Eventos y transporte en tu región',
                    ),
                    style: const TextStyle(
                      color: _softText,
                      fontSize: 11.4,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
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

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Zoek evenement of locatie',
        hintStyle: const TextStyle(color: Color(0xFF8C8C8C)),
        prefixIcon: const Icon(Icons.search_rounded, color: _gold, size: 20),
        filled: true,
        fillColor: _panelBlack,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withOpacity(0.24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.2),
        ),
      ),
    );
  }

  Widget _buildMarketChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(_markets.length, (index) {
          final selected = index == _selectedMarketIndex;
          return Padding(
            padding: EdgeInsets.only(
              right: index == _markets.length - 1 ? 0 : 7,
            ),
            child: ChoiceChip(
              label: Text(
                _markets[index],
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.2,
                ),
              ),
              selected: selected,
              onSelected: (_) => setState(() => _selectedMarketIndex = index),
              selectedColor: _gold,
              backgroundColor: _panelBlack,
              shape: StadiumBorder(
                side: BorderSide(
                  color: _gold.withOpacity(selected ? 0.15 : 0.34),
                ),
              ),
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(
                horizontal: -1.4,
                vertical: -1.8,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 7),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(_filters.length, (index) {
          final selected = index == _selectedFilterIndex;
          return Padding(
            padding: EdgeInsets.only(
              right: index == _filters.length - 1 ? 0 : 8,
            ),
            child: ChoiceChip(
              label: Text(
                _filters[index],
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.6,
                ),
              ),
              selected: selected,
              onSelected: (_) => setState(() => _selectedFilterIndex = index),
              selectedColor: _gold,
              backgroundColor: _panelBlack,
              shape: StadiumBorder(
                side: BorderSide(
                  color: _gold.withOpacity(selected ? 0.1 : 0.32),
                ),
              ),
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(
                horizontal: -1.4,
                vertical: -1.8,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 7),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSegmentedToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              label: 'Lijst',
              icon: Icons.view_list_rounded,
              selected: _selectedTabIndex == 0,
              onTap: () => setState(() => _selectedTabIndex = 0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildSegmentButton(
              label: 'Kaart',
              icon: Icons.map_outlined,
              selected: _selectedTabIndex == 1,
              onTap: () => setState(() => _selectedTabIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _gold : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.black : _gold.withOpacity(0.92),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventList(List<EventDetailData> events) {
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          _buildEventCard(events[i]),
          if (i != events.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'muziek':
        return Icons.graphic_eq_rounded;
      case 'zakelijk':
        return Icons.apartment_rounded;
      case 'sport':
        return Icons.sports_soccer_rounded;
      case 'vandaag':
        return Icons.schedule_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Widget _buildEventCard(EventDetailData event) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<EventDetailPage>(
              builder: (_) => EventDetailPage(
                event: event,
                onBookEvent: widget.onBookEvent,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: _panelBlack,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withOpacity(0.24)),
            boxShadow: [
              BoxShadow(
                color: _gold.withOpacity(0.05),
                blurRadius: 12,
                spreadRadius: 0.4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 94,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: event.gradient,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 14,
                      top: 14,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _gold.withOpacity(0.20),
                              _gold.withOpacity(0.04),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 44,
                      top: 18,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.35),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 65,
                      top: 31,
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.24),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 56,
                      top: 46,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _gold.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _gold.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _categoryIcon(event.category),
                              color: _gold,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              event.category,
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 10.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.34),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _gold.withOpacity(0.32)),
                        ),
                        child: Text(
                          event.locationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _gold.withOpacity(0.95),
                            fontSize: 10.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 6,
                      child: IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.favorite_border_rounded),
                        iconSize: 18,
                        color: Colors.white.withOpacity(0.92),
                        tooltip: _t(
                          nl: 'Favoriet',
                          en: 'Favorite',
                          fr: 'Favori',
                          es: 'Favorito',
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.8,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: _gold.withOpacity(0.95),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            event.dateTimeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _softText,
                              fontSize: 11.9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: _gold.withOpacity(0.95),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${event.locationName}, ${event.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _softText,
                              fontSize: 11.9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.pin_drop_outlined,
                          size: 13,
                          color: _gold.withOpacity(0.9),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            event.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _softText,
                              fontSize: 11.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _gold.withOpacity(0.4)),
                          ),
                          child: Text(
                            event.distanceOrStatus,
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF15120A),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _gold.withOpacity(0.5)),
                          ),
                          child: Text(
                            _ctaCardLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 10.9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      constraints: const BoxConstraints(minHeight: 280),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold.withOpacity(0.28)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0F0F0F), Color(0xFF07080C)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_rounded, color: _gold.withOpacity(0.96), size: 44),
            const SizedBox(height: 12),
            Text(
              _t(
                nl: 'Kaartmodus komt binnenkort',
                en: 'Map mode is coming soon',
                fr: 'Le mode carte arrive bientôt',
                es: 'El modo mapa estará disponible pronto',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                nl: 'Kaart- en locatiemodus wordt later gekoppeld. Gebruik voorlopig de lijstweergave voor een overzicht.',
                en: 'Map and location mode will be connected later. For now, use the list view for an overview.',
                fr: 'Le mode carte et localisation sera connecté plus tard. Utilisez la vue liste en attendant.',
                es: 'El modo mapa y ubicación se conectará más adelante. Por ahora, usa la vista de lista.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _softText,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _gold.withOpacity(0.45)),
              ),
              child: const Text(
                'Fluxidi Event Locator',
                style: TextStyle(
                  color: _gold,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Text(
        _t(
          nl: 'Geen evenementen gevonden voor je zoekopdracht of filter.',
          en: 'No events found for your search or filter.',
          fr: 'Aucun événement trouvé pour votre recherche ou filtre.',
          es: 'No se encontraron eventos para tu búsqueda o filtro.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: _softText, fontSize: 13),
      ),
    );
  }
}
