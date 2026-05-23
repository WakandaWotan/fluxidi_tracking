import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'event_data_source.dart';
import 'event_models.dart';
import 'events_detail_page.dart';

EventDataSource buildDefaultEventLocatorDataSource({required String baseUrl}) {
  return RemoteEventDataSource(
    baseUrl: baseUrl,
    fallbackDataSource: const LocalSeedEventDataSource(),
  );
}

class EventsPage extends StatefulWidget {
  const EventsPage({this.onBookEvent, this.dataSource, super.key});

  final EventBookCallback? onBookEvent;
  final EventDataSource? dataSource;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  static const Color _bgBlack = Color(0xFF07080C);
  static const Color _panelBlack = Color(0xFF101010);
  static const Color _gold = Color(0xFFE5B641);
  static const Color _softText = Color(0xFFB4B4B4);

  static const List<String> _dateFilterKeys = <String>[
    EventDateMode.all,
    EventDateMode.today,
    EventDateMode.weekend,
    EventDateMode.month,
  ];
  static const List<String> _categoryFilterKeys = <String>[
    'all',
    EventCategoryKey.music,
    EventCategoryKey.sport,
    EventCategoryKey.culture,
    EventCategoryKey.theater,
    EventCategoryKey.comedy,
    EventCategoryKey.business,
    EventCategoryKey.family,
    EventCategoryKey.other,
  ];
  static const List<String> _marketKeys = <String>[
    'be',
    'nl',
    'fr',
    'uk',
    'es',
  ];

  final TextEditingController _searchController = TextEditingController();
  late String _selectedMarketKey;
  late String _selectedMarketCode;
  String _selectedDateMode = EventDateMode.all;
  DateTime? _selectedMonthStartUtc;
  DateTime? _selectedMonthEndUtc;
  String _selectedCategoryKey = 'all';
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
        return _selectedDateMode == EventDateMode.month &&
                _selectedMonthStartUtc != null
            ? _formatMonthLabel(_selectedMonthStartUtc!)
            : _t(nl: 'Maand', en: 'Month', fr: 'Mois', es: 'Mes');
      default:
        return key;
    }
  }

  String _categoryFilterLabel(String key) {
    switch (key) {
      case 'all':
        return _t(
          nl: 'Alle categorieën',
          en: 'All categories',
          fr: 'Toutes catégories',
          es: 'Todas categorías',
        );
      case EventCategoryKey.music:
        return _t(nl: 'Muziek', en: 'Music', fr: 'Musique', es: 'Música');
      case EventCategoryKey.business:
        return _t(
          nl: 'Zakelijk',
          en: 'Business',
          fr: 'Business',
          es: 'Negocios',
        );
      case EventCategoryKey.sport:
        return _t(nl: 'Sport', en: 'Sport', fr: 'Sport', es: 'Deporte');
      case EventCategoryKey.culture:
        return _t(nl: 'Cultuur', en: 'Culture', fr: 'Culture', es: 'Cultura');
      case EventCategoryKey.food:
        return _t(nl: 'Eten', en: 'Food', fr: 'Cuisine', es: 'Comida');
      case EventCategoryKey.theater:
        return _t(nl: 'Theater', en: 'Theater', fr: 'Théâtre', es: 'Teatro');
      case EventCategoryKey.comedy:
        return _t(nl: 'Comedy', en: 'Comedy', fr: 'Comédie', es: 'Comedia');
      case EventCategoryKey.family:
        return _t(nl: 'Familie', en: 'Family', fr: 'Famille', es: 'Familia');
      case EventCategoryKey.airport:
        return _t(
          nl: 'Luchthaven',
          en: 'Airport',
          fr: 'Aéroport',
          es: 'Aeropuerto',
        );
      case EventCategoryKey.other:
        return _t(nl: 'Overig', en: 'Other', fr: 'Autre', es: 'Otro');
      default:
        return key;
    }
  }

  String _eventCategoryBadgeLabel(EventDetailData event) {
    return _categoryFilterLabel(event.resolvedCategoryKey);
  }

  String _monthName(int month) {
    switch (month) {
      case 1:
        return _t(nl: 'Januari', en: 'January', fr: 'Janvier', es: 'Enero');
      case 2:
        return _t(nl: 'Februari', en: 'February', fr: 'Février', es: 'Febrero');
      case 3:
        return _t(nl: 'Maart', en: 'March', fr: 'Mars', es: 'Marzo');
      case 4:
        return _t(nl: 'April', en: 'April', fr: 'Avril', es: 'Abril');
      case 5:
        return _t(nl: 'Mei', en: 'May', fr: 'Mai', es: 'Mayo');
      case 6:
        return _t(nl: 'Juni', en: 'June', fr: 'Juin', es: 'Junio');
      case 7:
        return _t(nl: 'Juli', en: 'July', fr: 'Juillet', es: 'Julio');
      case 8:
        return _t(nl: 'Augustus', en: 'August', fr: 'Août', es: 'Agosto');
      case 9:
        return _t(
          nl: 'September',
          en: 'September',
          fr: 'Septembre',
          es: 'Septiembre',
        );
      case 10:
        return _t(nl: 'Oktober', en: 'October', fr: 'Octobre', es: 'Octubre');
      case 11:
        return _t(
          nl: 'November',
          en: 'November',
          fr: 'Novembre',
          es: 'Noviembre',
        );
      case 12:
        return _t(
          nl: 'December',
          en: 'December',
          fr: 'Décembre',
          es: 'Diciembre',
        );
      default:
        return month.toString();
    }
  }

  String _formatMonthLabel(DateTime monthStartUtc) {
    final local = monthStartUtc.toLocal();
    return '${_monthName(local.month)} ${local.year}';
  }

  late final EventDataSource _dataSource;
  List<EventDetailData> _events = const <EventDetailData>[];

  @override
  void initState() {
    super.initState();
    _selectedMarketKey = _marketKeys.first;
    _selectedMarketCode = _selectedMarketKey.toUpperCase();
    _dataSource = widget.dataSource ?? const LocalSeedEventDataSource();
    _events = List<EventDetailData>.from(
      _dataSource.getInitialEvents() ?? const <EventDetailData>[],
    );
    _searchController.addListener(_onSearchChanged);
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadEvents() async {
    final feed = await _dataSource.loadEventFeed(query: _buildEventFeedQuery());
    if (!mounted) return;
    setState(() {
      _events = List<EventDetailData>.from(feed.events);
    });
  }

  EventFeedQuery _buildEventFeedQuery() {
    final dateRange = _resolveDateRangeForMode();
    return EventFeedQuery(
      countryCode: _selectedMarketCode,
      marketCode: _selectedMarketKey,
      dateMode: _selectedDateMode,
      startAtUtc: dateRange?.$1,
      endAtUtc: dateRange?.$2,
      categoryKey: _selectedCategoryKey == 'all' ? null : _selectedCategoryKey,
      searchQuery: _searchController.text.trim(),
      limit: 50,
    );
  }

  List<EventDetailData> get _visibleEvents {
    final query = _searchController.text.trim().toLowerCase();
    return _events
        .where((event) {
          if (!_marketMatchesEvent(event, _selectedMarketKey)) return false;
          final matchesSearch =
              query.isEmpty ||
              event.title.toLowerCase().contains(query) ||
              event.locationName.toLowerCase().contains(query) ||
              event.city.toLowerCase().contains(query) ||
              event.address.toLowerCase().contains(query) ||
              event.category.toLowerCase().contains(query);
          if (!matchesSearch) return false;
          if (_selectedCategoryKey != 'all' &&
              event.resolvedCategoryKey != _selectedCategoryKey) {
            return false;
          }
          return _matchesDateMode(event);
        })
        .toList(growable: false);
  }

  bool _matchesDateMode(EventDetailData event) {
    switch (_selectedDateMode) {
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

  bool _matchesMonthFilter(EventDetailData event) {
    final start = event.startAtUtc;
    final monthStart = _selectedMonthStartUtc;
    final monthEnd = _selectedMonthEndUtc;
    if (start == null || monthStart == null || monthEnd == null) return true;
    final startUtc = start.toUtc();
    return !startUtc.isBefore(monthStart) && !startUtc.isAfter(monthEnd);
  }

  static (DateTime, DateTime)? _upcomingWeekendRange(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final int daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
    final weekendStart = startOfToday.add(Duration(days: daysUntilSaturday));
    final weekendEndExclusive = weekendStart.add(const Duration(days: 2));
    if (weekendEndExclusive.isBefore(now)) return null;
    return (weekendStart, weekendEndExclusive);
  }

  (DateTime, DateTime)? _resolveDateRangeForMode() {
    if (_selectedDateMode != EventDateMode.month) return null;
    final monthStart = _selectedMonthStartUtc;
    final monthEnd = _selectedMonthEndUtc;
    if (monthStart == null || monthEnd == null) return null;
    return (monthStart, monthEnd);
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
            'belgïe',
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
            'royaume-uni',
          ],
        );
      case 'es':
        return _matchesMarketAliases(
          aliasValues: aliasValues,
          haystack: haystack,
          aliases: const <String>[
            'es',
            'spain',
            'spanje',
            'espana',
            'españa',
            'espagne',
          ],
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

  List<_MonthFilterOption> _nextTwelveMonthOptions() {
    final nowLocal = DateTime.now().toLocal();
    final firstMonthLocal = DateTime(nowLocal.year, nowLocal.month, 1);
    return List<_MonthFilterOption>.generate(12, (index) {
      final monthStartLocal = DateTime(
        firstMonthLocal.year,
        firstMonthLocal.month + index,
        1,
      );
      final nextMonthStartLocal = DateTime(
        monthStartLocal.year,
        monthStartLocal.month + 1,
        1,
      );
      return _MonthFilterOption(
        startUtc: monthStartLocal.toUtc(),
        endUtc: nextMonthStartLocal
            .subtract(const Duration(milliseconds: 1))
            .toUtc(),
      );
    });
  }

  Future<void> _openMonthPicker() async {
    final options = _nextTwelveMonthOptions();
    final selectedStartUtc = _selectedMonthStartUtc;
    final chosen = await showModalBottomSheet<_MonthFilterOption>(
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
                  _t(
                    nl: 'Selecteer maand',
                    en: 'Select month',
                    fr: 'Sélectionner le mois',
                    es: 'Seleccionar mes',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: _gold.withOpacity(0.16), height: 1),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected =
                          selectedStartUtc != null &&
                          option.startUtc.isAtSameMomentAs(selectedStartUtc);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        title: Text(
                          _formatMonthLabel(option.startUtc),
                          style: TextStyle(
                            color: isSelected ? _gold : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: _gold)
                            : null,
                        onTap: () => Navigator.of(context).pop(option),
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
    if (!mounted || chosen == null) return;
    setState(() {
      _selectedDateMode = EventDateMode.month;
      _selectedMonthStartUtc = chosen.startUtc;
      _selectedMonthEndUtc = chosen.endUtc;
    });
    _loadEvents();
  }

  void _openEventDetails(EventDetailData event) {
    Navigator.of(context).push(
      MaterialPageRoute<EventDetailPage>(
        builder: (_) =>
            EventDetailPage(event: event, onBookEvent: widget.onBookEvent),
      ),
    );
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
                  10,
                  contentPadding,
                  18,
                ),
                children: [
                  _buildSearchField(),
                  const SizedBox(height: 8),
                  _buildMarketChips(),
                  const SizedBox(height: 9),
                  _buildDateFilterChips(),
                  const SizedBox(height: 9),
                  _buildCategoryChips(),
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
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 4),
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
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _panelBlack.withOpacity(0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withOpacity(0.2)),
              ),
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
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _t(
                      nl: 'Evenementen en vervoer in uw regio',
                      en: 'Events and transport in your area',
                      fr: 'Événements et transport dans votre région',
                      es: 'Eventos y transporte en tu región',
                    ),
                    style: const TextStyle(
                      color: _softText,
                      fontSize: 11.6,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _marketKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final marketKey = _marketKeys[index];
          final selected = marketKey == _selectedMarketKey;
          return ChoiceChip(
            label: Text(
              _marketLabel(marketKey),
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedMarketKey = marketKey;
                _selectedMarketCode = marketKey.toUpperCase();
              });
              _loadEvents();
            },
            selectedColor: _gold,
            backgroundColor: _panelBlack,
            shape: StadiumBorder(
              side: BorderSide(
                color: _gold.withOpacity(selected ? 0.15 : 0.34),
              ),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 11),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          );
        },
      ),
    );
  }

  Widget _buildDateFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _dateFilterKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final dateKey = _dateFilterKeys[index];
          final selected = dateKey == _selectedDateMode;
          return ChoiceChip(
            label: Text(
              _dateFilterLabel(dateKey),
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            selected: selected,
            onSelected: (_) {
              if (dateKey == EventDateMode.month) {
                _openMonthPicker();
                return;
              }
              setState(() => _selectedDateMode = dateKey);
              _loadEvents();
            },
            selectedColor: _gold,
            backgroundColor: _panelBlack,
            shape: StadiumBorder(
              side: BorderSide(color: _gold.withOpacity(selected ? 0.1 : 0.32)),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 11),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _categoryFilterKeys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final categoryKey = _categoryFilterKeys[index];
          final selected = categoryKey == _selectedCategoryKey;
          return ChoiceChip(
            label: Text(
              _categoryFilterLabel(categoryKey),
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            selected: selected,
            onSelected: (_) {
              setState(() => _selectedCategoryKey = categoryKey);
              _loadEvents();
            },
            selectedColor: _gold,
            backgroundColor: _panelBlack,
            shape: StadiumBorder(
              side: BorderSide(color: _gold.withOpacity(selected ? 0.1 : 0.32)),
            ),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 11),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          );
        },
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

  IconData _categoryIcon(EventDetailData event) {
    if (event.category.toLowerCase() == 'vandaag') {
      return Icons.schedule_rounded;
    }
    return eventCategoryMetaByKey(event.resolvedCategoryKey)?.icon ??
        Icons.event_rounded;
  }

  String _cardImageUrl(EventDetailData event) {
    return (event.heroImageUrl ?? event.thumbnailUrl ?? event.imageUrl ?? '')
        .trim();
  }

  Widget _buildEventCard(EventDetailData event) {
    final cardImageUrl = _cardImageUrl(event);
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
                        if (cardImageUrl.isNotEmpty)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              child: Image.network(
                                cardImageUrl,
                                fit: BoxFit.cover,
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
                                  _categoryIcon(event),
                                  color: _gold,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _eventCategoryBadgeLabel(event),
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
                            onPressed: () => _showInfoSnackBar(
                              _t(
                                nl: 'Favorieten voor events komen binnenkort.',
                                en: 'Event favorites are coming soon.',
                                fr: 'Les favoris événement arrivent bientôt.',
                                es: 'Los favoritos de eventos estarán disponibles pronto.',
                              ),
                            ),
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
                        const SizedBox(height: 9),
                        _buildEventMetaChips(event),
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
                  _ctaCardLabel,
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
              child: Text(
                _t(
                  nl: 'Fluxidi Event Locator',
                  en: 'Fluxidi Event Locator',
                  fr: 'Fluxidi Event Locator',
                  es: 'Fluxidi Event Locator',
                ),
                style: const TextStyle(
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

  Widget _buildEventMetaChips(EventDetailData event) {
    final statusLabel = event.customerTicketStatusLabel;
    final distanceLabel = event.isDistanceLabelTrusted
        ? (event.distanceLabel ?? '').trim()
        : '';
    final chips = <Widget>[
      if ((statusLabel ?? '').isNotEmpty) _buildMetaChip(label: statusLabel!),
      if (distanceLabel.isNotEmpty) _buildMetaChip(label: distanceLabel),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }

  Widget _buildMetaChip({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _gold,
          fontSize: 10.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MonthFilterOption {
  const _MonthFilterOption({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;
}
