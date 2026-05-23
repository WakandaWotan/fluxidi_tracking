import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';

import 'event_data_source.dart';
import 'event_models.dart';
import 'events_detail_page.dart';

class EventCategoryResultsPage extends StatefulWidget {
  const EventCategoryResultsPage({
    required this.title,
    required this.dataSource,
    required this.marketKey,
    required this.dateMode,
    required this.sortMode,
    this.categoryKey = 'all',
    this.searchQuery = '',
    this.monthStartUtc,
    this.monthEndUtc,
    this.onBookEvent,
    super.key,
  });

  final String title;
  final EventDataSource dataSource;
  final String marketKey;
  final String dateMode;
  final DateTime? monthStartUtc;
  final DateTime? monthEndUtc;
  final String categoryKey;
  final String sortMode;
  final String searchQuery;
  final EventBookCallback? onBookEvent;

  @override
  State<EventCategoryResultsPage> createState() =>
      _EventCategoryResultsPageState();
}

class _EventCategoryResultsPageState extends State<EventCategoryResultsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  final EventLocalSavedStore _savedStore = const EventLocalSavedStore();
  List<EventDetailData> _events = const <EventDetailData>[];
  Map<String, SavedEventRecord> _savedEventByKey =
      const <String, SavedEventRecord>{};
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

  @override
  void initState() {
    super.initState();
    _loadSavedEvents();
    _loadEvents();
  }

  Future<void> _loadSavedEvents() async {
    final records = await _savedStore.loadAll();
    if (!mounted) return;
    setState(() => _savedEventByKey = records);
  }

  Future<void> _loadEvents() async {
    final feed = await widget.dataSource.loadEventFeed(
      query: _buildEventFeedQuery(),
    );
    if (!mounted) return;
    setState(() => _events = List<EventDetailData>.from(feed.events));
    _prefetchTopThumbnails();
  }

  void _prefetchTopThumbnails() {
    final urls = <String>[];
    for (final event in _visibleEvents) {
      final url = _cardImageUrl(event);
      if (url.isEmpty || urls.contains(url)) continue;
      urls.add(url);
      if (urls.length >= 5) break;
    }
    for (final url in urls) {
      final provider = ResizeImage(NetworkImage(url), width: 1024);
      precacheImage(provider, context).catchError((_) {});
    }
  }

  EventFeedQuery _buildEventFeedQuery() {
    final isMonth = widget.dateMode == EventDateMode.month;
    return EventFeedQuery(
      countryCode: widget.marketKey.toUpperCase(),
      marketCode: widget.marketKey,
      dateMode: widget.dateMode,
      startAtUtc: isMonth ? widget.monthStartUtc : null,
      endAtUtc: isMonth ? widget.monthEndUtc : null,
      categoryKey: widget.categoryKey == 'all' ? null : widget.categoryKey,
      searchQuery: widget.searchQuery.trim(),
      limit: 50,
    );
  }

  String _marketLabel(String key) {
    switch (key) {
      case 'be':
        return _t(nl: 'België', en: 'Belgium', fr: 'Belgique', es: 'Bélgica');
      case 'nl':
        return _t(
          nl: 'Nederland',
          en: 'Netherlands',
          fr: 'Pays-Bas',
          es: 'Países Bajos',
        );
      case 'fr':
        return _t(nl: 'Frankrijk', en: 'France', fr: 'France', es: 'Francia');
      case 'uk':
        return _t(
          nl: 'Verenigd Koninkrijk',
          en: 'United Kingdom',
          fr: 'Royaume-Uni',
          es: 'Reino Unido',
        );
      case 'es':
        return _t(nl: 'Spanje', en: 'Spain', fr: 'Espagne', es: 'España');
      default:
        return key.toUpperCase();
    }
  }

  String _dateFilterLabel(String key) {
    switch (key) {
      case EventDateMode.all:
        return _t(nl: 'Alles', en: 'All', fr: 'Tout', es: 'Todo');
      case EventDateMode.today:
        return _t(nl: 'Vandaag', en: 'Today', fr: 'Aujourd’hui', es: 'Hoy');
      case EventDateMode.weekend:
        return _t(
          nl: 'Dit weekend',
          en: 'This weekend',
          fr: 'Ce week-end',
          es: 'Este fin de semana',
        );
      case EventDateMode.month:
        if (widget.monthStartUtc == null) {
          return _t(nl: 'Maand', en: 'Month', fr: 'Mois', es: 'Mes');
        }
        final local = widget.monthStartUtc!.toLocal();
        return '${local.month.toString().padLeft(2, '0')}-${local.year}';
      default:
        return key;
    }
  }

  String _sortModeLabel(String key) {
    switch (key) {
      case 'soonest':
        return _t(
          nl: 'Eerstkomend',
          en: 'Soonest first',
          fr: 'Plus proche',
          es: 'Mas cercano',
        );
      case 'latest':
        return _t(
          nl: 'Later/laatst',
          en: 'Latest first',
          fr: 'Plus tard',
          es: 'Mas tarde',
        );
      case 'popular':
        return _t(
          nl: 'Populair',
          en: 'Popular',
          fr: 'Populaire',
          es: 'Popular',
        );
      case 'default':
      default:
        return _t(
          nl: 'Standaard',
          en: 'Default',
          fr: 'Defaut',
          es: 'Predeterminado',
        );
    }
  }

  String get _filterSummary {
    final parts = <String>[
      _marketLabel(widget.marketKey),
      _dateFilterLabel(widget.dateMode),
      _sortModeLabel(widget.sortMode),
    ];
    return parts.join(' · ');
  }

  List<EventDetailData> get _visibleEvents {
    final normalizedSearch = widget.searchQuery.trim().toLowerCase();
    final filtered = _events
        .where((event) {
          if (!_marketMatchesEvent(event, widget.marketKey)) return false;
          if (widget.categoryKey != 'all' &&
              event.resolvedCategoryKey != widget.categoryKey) {
            return false;
          }
          if (!_matchesDateMode(event)) return false;
          if (normalizedSearch.isNotEmpty) {
            final matches =
                event.title.toLowerCase().contains(normalizedSearch) ||
                event.locationName.toLowerCase().contains(normalizedSearch) ||
                event.city.toLowerCase().contains(normalizedSearch) ||
                event.address.toLowerCase().contains(normalizedSearch) ||
                event.category.toLowerCase().contains(normalizedSearch);
            if (!matches) return false;
          }
          return true;
        })
        .toList(growable: false);
    final sorted = List<EventDetailData>.from(filtered);
    switch (widget.sortMode) {
      case 'latest':
        sorted.sort((a, b) => _compareSoonestFirst(b, a));
        break;
      case 'soonest':
      case 'popular':
      case 'default':
      default:
        sorted.sort(_compareSoonestFirst);
        break;
    }
    return sorted;
  }

  static int _compareSoonestFirst(EventDetailData a, EventDetailData b) {
    final aUtc = a.startAtUtc;
    final bUtc = b.startAtUtc;
    if (aUtc == null && bUtc == null) return a.title.compareTo(b.title);
    if (aUtc == null) return 1;
    if (bUtc == null) return -1;
    return aUtc.compareTo(bUtc);
  }

  bool _matchesDateMode(EventDetailData event) {
    switch (widget.dateMode) {
      case EventDateMode.today:
        return _matchesTodayFilter(event);
      case EventDateMode.weekend:
        return _matchesWeekendFilter(event);
      case EventDateMode.month:
        return _matchesMonthFilter(event);
      case EventDateMode.all:
      default:
        return _matchesUpcomingYearFilter(event);
    }
  }

  bool _matchesMonthFilter(EventDetailData event) {
    final start = event.startAtUtc;
    final monthStart = widget.monthStartUtc;
    final monthEnd = widget.monthEndUtc;
    if (start == null || monthStart == null || monthEnd == null) return true;
    final startUtc = start.toUtc();
    return !startUtc.isBefore(monthStart) && !startUtc.isAfter(monthEnd);
  }

  static bool _matchesUpcomingYearFilter(EventDetailData event) {
    final start = event.startAtUtc?.toLocal();
    if (start == null) return true;
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 365));
    return !start.isBefore(now) && !start.isAfter(horizon);
  }

  static bool _matchesTodayFilter(EventDetailData event) {
    final start = event.startAtUtc?.toLocal();
    if (start == null) {
      final dateLabel = event.dateTimeLabel.toLowerCase();
      return dateLabel.contains('vandaag') ||
          dateLabel.contains('today') ||
          dateLabel.contains('aujourd') ||
          dateLabel.contains('hoy');
    }
    final now = DateTime.now();
    if (start.isBefore(now)) return false;
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }

  static bool _matchesWeekendFilter(EventDetailData event) {
    final start = event.startAtUtc?.toLocal();
    if (start == null) {
      final dateLabel = event.dateTimeLabel.toLowerCase();
      return dateLabel.contains('zaterdag') ||
          dateLabel.contains('zondag') ||
          dateLabel.contains('vrijdag') ||
          dateLabel.contains('sábado') ||
          dateLabel.contains('domingo') ||
          dateLabel.contains('friday') ||
          dateLabel.contains('saturday') ||
          dateLabel.contains('sunday');
    }
    final now = DateTime.now();
    if (start.isBefore(now)) return false;
    final weekendRange = _upcomingWeekendRange(now);
    if (weekendRange == null) return false;
    final weekendStart = weekendRange.$1;
    final weekendEndExclusive = weekendRange.$2;
    return !start.isBefore(weekendStart) && start.isBefore(weekendEndExclusive);
  }

  static (DateTime, DateTime)? _upcomingWeekendRange(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final int daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
    final weekendStart = startOfToday.add(Duration(days: daysUntilSaturday));
    final weekendEndExclusive = weekendStart.add(const Duration(days: 2));
    if (weekendEndExclusive.isBefore(now)) return null;
    return (weekendStart, weekendEndExclusive);
  }

  bool _marketMatchesEvent(EventDetailData event, String marketKey) {
    final aliasValues = <String>{
      _normalizedMarketValue(event.marketCode),
      _normalizedMarketValue(event.countryCode),
      _normalizedMarketValue(event.city),
      _normalizedMarketValue(event.address),
    }..removeWhere((value) => value.isEmpty);
    final haystack = _normalizedMarketValue(
      '${event.city} ${event.address} ${event.countryCode ?? ''} ${event.marketCode ?? ''}',
    );
    switch (marketKey) {
      case 'be':
        return _matchesMarketAliases(
          aliasValues: aliasValues,
          haystack: haystack,
          aliases: const <String>[
            'be',
            'belgium',
            'belgie',
            'belgië',
            'belgique',
          ],
        );
      case 'nl':
        return _matchesMarketAliases(
          aliasValues: aliasValues,
          haystack: haystack,
          aliases: const <String>['nl', 'netherlands', 'nederland', 'pays-bas'],
        );
      case 'fr':
        return _matchesMarketAliases(
          aliasValues: aliasValues,
          haystack: haystack,
          aliases: const <String>['fr', 'france', 'frankrijk'],
        );
      case 'uk':
        return _matchesMarketAliases(
          aliasValues: aliasValues,
          haystack: haystack,
          aliases: const <String>[
            'uk',
            'gb',
            'united kingdom',
            'verenigd koninkrijk',
          ],
        );
      case 'es':
        return _matchesMarketAliases(
          aliasValues: aliasValues,
          haystack: haystack,
          aliases: const <String>['es', 'spain', 'spanje', 'espana', 'españa'],
        );
      default:
        return true;
    }
  }

  static bool _matchesMarketAliases({
    required Set<String> aliasValues,
    required String haystack,
    required List<String> aliases,
  }) {
    for (final alias in aliases) {
      final normalizedAlias = _normalizedMarketValue(alias);
      if (normalizedAlias.isEmpty) continue;
      if (aliasValues.contains(normalizedAlias)) return true;
      if (haystack.contains(normalizedAlias)) return true;
    }
    return false;
  }

  static String _normalizedMarketValue(String? raw) {
    final text = (raw ?? '').trim().toLowerCase();
    if (text.isEmpty) return '';
    return text.replaceAll('ï', 'i').replaceAll('é', 'e');
  }

  bool _isFavorite(EventDetailData event) {
    final key = buildSavedEventIdentityKey(event);
    return _savedEventByKey[key]?.favorite == true;
  }

  Future<void> _toggleFavorite(EventDetailData event) async {
    final favorite = !_isFavorite(event);
    final key = buildSavedEventIdentityKey(event);
    final optimistic = Map<String, SavedEventRecord>.from(_savedEventByKey);
    final existing = optimistic[key];
    if (favorite) {
      optimistic[key] = SavedEventRecord.fromEvent(
        event,
        favorite: true,
        saved: existing?.saved ?? false,
        savedAtUtc: existing?.savedAtUtc,
      );
    } else if (existing != null) {
      if (existing.saved) {
        optimistic[key] = existing.copyWith(favorite: false);
      } else {
        optimistic.remove(key);
      }
    }
    setState(() => _savedEventByKey = optimistic);
    _showInfoSnackBar(
      favorite
          ? _t(
              nl: 'Toegevoegd aan favorieten',
              en: 'Added to favorites',
              fr: 'Ajoute aux favoris',
              es: 'Anadido a favoritos',
            )
          : _t(
              nl: 'Verwijderd uit favorieten',
              en: 'Removed from favorites',
              fr: 'Retire des favoris',
              es: 'Eliminado de favoritos',
            ),
    );
    final updated = await _savedStore.toggleFavorite(event, favorite: favorite);
    if (!mounted) return;
    setState(() => _savedEventByKey = updated);
  }

  Future<void> _openEventDetails(EventDetailData event) async {
    await Navigator.of(context).push(
      MaterialPageRoute<EventDetailPage>(
        builder: (_) =>
            EventDetailPage(event: event, onBookEvent: widget.onBookEvent),
      ),
    );
    if (!mounted) return;
    _loadSavedEvents();
  }

  void _bookEvent(EventDetailData event) {
    if (widget.onBookEvent != null) {
      widget.onBookEvent!.call(event);
      return;
    }
    _showInfoSnackBar(
      _t(
        nl: 'Boekingsflow voor dit event is binnenkort beschikbaar.',
        en: 'Booking flow for this event is coming soon.',
        fr: 'Le flux de réservation pour cet événement arrive bientôt.',
        es: 'El flujo de reserva para este evento estará disponible pronto.',
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _cardImageUrl(EventDetailData event) {
    return (event.thumbnailUrl ?? event.imageUrl ?? event.heroImageUrl ?? '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final events = _visibleEvents;
    return Scaffold(
      backgroundColor: _bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                children: [
                  _buildSummaryPanel(),
                  const SizedBox(height: 12),
                  _buildSegmentedToggle(),
                  const SizedBox(height: 12),
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
              widget.title,
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

  Widget _buildSummaryPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withOpacity(0.24)),
      ),
      child: Text(
        _filterSummary,
        style: const TextStyle(
          color: _gold,
          fontSize: 11.6,
          fontWeight: FontWeight.w700,
        ),
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
              label: _t(nl: 'Lijst', en: 'List', fr: 'Liste', es: 'Lista'),
              icon: Icons.view_list_rounded,
              selected: _selectedTabIndex == 0,
              onTap: () => setState(() => _selectedTabIndex = 0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildSegmentButton(
              label: _t(nl: 'Kaart', en: 'Map', fr: 'Carte', es: 'Mapa'),
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

  IconData _categoryIcon(EventDetailData event) {
    if (event.category.toLowerCase() == 'vandaag') {
      return Icons.schedule_rounded;
    }
    return eventCategoryMetaByKey(event.resolvedCategoryKey)?.icon ??
        Icons.event_rounded;
  }

  Widget _buildEventCard(EventDetailData event) {
    final cardImageUrl = _cardImageUrl(event);
    final isFavorite = _isFavorite(event);
    return Container(
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
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openEventDetails(event),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 158,
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
                        if (cardImageUrl.isNotEmpty)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              child: Image.network(
                                cardImageUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 1024,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        if (cardImageUrl.isNotEmpty)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Colors.black.withOpacity(0.26),
                                    Colors.black.withOpacity(0.54),
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
                                  _categoryIcon(event),
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
                              border: Border.all(
                                color: _gold.withOpacity(0.32),
                              ),
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
                            onPressed: () => _toggleFavorite(event),
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                            ),
                            iconSize: 18,
                            color: isFavorite
                                ? _gold
                                : Colors.white.withOpacity(0.92),
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
                    padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.4,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _metaRow(
                          Icons.calendar_today_outlined,
                          event.dateTimeLabel,
                        ),
                        const SizedBox(height: 3),
                        _metaRow(
                          Icons.location_on_outlined,
                          '${event.locationName}, ${event.city}',
                        ),
                        const SizedBox(height: 8),
                        _metaRow(Icons.pin_drop_outlined, event.address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _bookEvent(event),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF171209),
                  foregroundColor: _gold,
                  side: BorderSide(color: _gold.withOpacity(0.55)),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                icon: const Icon(Icons.local_taxi_rounded, size: 17),
                label: Text(
                  _t(
                    nl: 'Taxi naar dit event',
                    en: 'Taxi to this event',
                    fr: 'Taxi vers cet événement',
                    es: 'Taxi a este evento',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _gold.withOpacity(0.95)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _softText, fontSize: 11.9),
          ),
        ),
      ],
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
          nl: 'Geen evenementen gevonden voor deze selectie.',
          en: 'No events found for this selection.',
          fr: 'Aucun evenement trouve pour cette selection.',
          es: 'No se encontraron eventos para esta seleccion.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: _softText, fontSize: 13),
      ),
    );
  }
}
