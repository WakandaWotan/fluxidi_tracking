import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

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

  final EventLocalSavedStore _savedStore = const EventLocalSavedStore();
  List<EventDetailData> _events = const <EventDetailData>[];
  Map<String, SavedEventRecord> _savedEventByKey =
      const <String, SavedEventRecord>{};
  int _selectedTabIndex = 0;
  mb.MapboxMap? _mapboxMap;
  mb.CircleAnnotationManager? _mapCircleManager;
  mb.Cancelable? _mapTapCancelable;
  final Map<String, EventDetailData> _mapEventByAnnotationId =
      <String, EventDetailData>{};
  EventDetailData? _selectedMapEvent;
  late final ValueKey<String> _mapWidgetKey;
  bool _isClearingEmptyMapState = false;

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
    case AppLanguage.de:
      return en;
    }
  }

  @override
  void initState() {
    super.initState();
    customerThemeNotifier.addListener(_onThemeChanged);
    _loadSavedEvents();
    _loadEvents();
    _mapWidgetKey = ValueKey<String>(
      'results_map_${widget.marketKey}_${widget.categoryKey}_${widget.dateMode}_${widget.searchQuery}',
    );
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    customerThemeNotifier.removeListener(_onThemeChanged);
    try {
      _mapTapCancelable?.cancel();
    } catch (_) {}
    _mapTapCancelable = null;
    super.dispose();
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
    _syncMapData();
    _prefetchTopThumbnails();
  }

  List<EventDetailData> get _mappableEvents {
    return _visibleEvents
        .where((event) {
          return _isValidMapCoordinate(event.lat, event.lng);
        })
        .toList(growable: false);
  }

  bool _isValidMapCoordinate(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    return true;
  }

  mb.Point _mbPoint(double lon, double lat) {
    return mb.Point(coordinates: mb.Position(lon, lat));
  }

  mb.Point _marketFallbackCenter() {
    switch (widget.marketKey.trim().toLowerCase()) {
      case 'nl':
        return _mbPoint(5.2913, 52.1326);
      case 'fr':
        return _mbPoint(2.2137, 46.2276);
      case 'uk':
      case 'gb':
        return _mbPoint(-3.4360, 55.3781);
      case 'es':
        return _mbPoint(-3.7038, 40.4168);
      case 'be':
      default:
        return _mbPoint(4.4699, 50.5039);
    }
  }

  mb.Point _initialMapCenter() {
    final events = _mappableEvents;
    if (events.isNotEmpty) {
      final first = events.first;
      return _mbPoint(first.lng, first.lat);
    }
    return _marketFallbackCenter();
  }

  ({double minLat, double maxLat, double minLng, double maxLng}) _mapBounds(
    List<EventDetailData> events,
  ) {
    var minLat = events.first.lat;
    var maxLat = events.first.lat;
    var minLng = events.first.lng;
    var maxLng = events.first.lng;
    for (var i = 1; i < events.length; i++) {
      final event = events[i];
      if (event.lat < minLat) minLat = event.lat;
      if (event.lat > maxLat) maxLat = event.lat;
      if (event.lng < minLng) minLng = event.lng;
      if (event.lng > maxLng) maxLng = event.lng;
    }
    return (minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }

  double _zoomForBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final span = latSpan > lngSpan ? latSpan : lngSpan;
    if (span < 0.03) return 12.8;
    if (span < 0.08) return 12.2;
    if (span < 0.16) return 11.6;
    if (span < 0.35) return 10.9;
    if (span < 0.70) return 10.2;
    if (span < 1.20) return 9.6;
    if (span < 2.00) return 8.8;
    if (span < 3.50) return 8.1;
    if (span < 6.00) return 7.4;
    return 6.6;
  }

  ({mb.Point center, double zoom}) _cameraTargetForEvents(
    List<EventDetailData> events,
  ) {
    if (events.isEmpty) {
      return (center: _marketFallbackCenter(), zoom: 5.8);
    }
    if (events.length == 1) {
      final first = events.first;
      return (center: _mbPoint(first.lng, first.lat), zoom: 11.8);
    }
    final bounds = _mapBounds(events);
    final centerLat = (bounds.minLat + bounds.maxLat) / 2.0;
    final centerLng = (bounds.minLng + bounds.maxLng) / 2.0;
    final zoom = _zoomForBounds(
      minLat: bounds.minLat,
      maxLat: bounds.maxLat,
      minLng: bounds.minLng,
      maxLng: bounds.maxLng,
    );
    return (center: _mbPoint(centerLng, centerLat), zoom: zoom);
  }

  Future<void> _onMapCreated(mb.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _mapCircleManager = await mapboxMap.annotations
        .createCircleAnnotationManager();
    try {
      _mapTapCancelable?.cancel();
    } catch (_) {}
    _mapTapCancelable = null;
    _mapTapCancelable = _mapCircleManager!.tapEvents(
      onTap: (annotation) {
        debugPrint('[EVENT_MAP] markerTapped id=${annotation.id}');
        final event = _mapEventByAnnotationId[annotation.id];
        if (event == null || !mounted) return;
        setState(() => _selectedMapEvent = event);
        _openEventDetails(event);
      },
    );
    await _syncMapData(forceCameraReset: true);
  }

  Future<void> _syncMapData({bool forceCameraReset = false}) async {
    final map = _mapboxMap;
    final manager = _mapCircleManager;
    if (map == null || manager == null) return;

    final visibleEvents = _visibleEvents;
    debugPrint('[EVENT_MAP] visibleEvents=${visibleEvents.length}');
    final events = <EventDetailData>[];
    for (final event in visibleEvents) {
      final lat = event.lat;
      final lng = event.lng;
      final valid = _isValidMapCoordinate(lat, lng);
      debugPrint(
        '[EVENT_MAP] eventCoord title=${event.title} lat=${lat.toStringAsFixed(6)} lng=${lng.toStringAsFixed(6)} valid=$valid',
      );
      if (valid) events.add(event);
    }
    final market = widget.marketKey.trim().toLowerCase();
    final category = widget.categoryKey.trim().toLowerCase();
    final visibleCount = visibleEvents.length;
    debugPrint(
      '[EVENT_MAP] market=$market category=$category visibleEvents=$visibleCount validMarkers=${events.length}',
    );
    if (market == 'fr') {
      debugPrint(
        '[EVENT_MAP] market=fr visibleEvents=$visibleCount validMarkers=${events.length}',
      );
    }
    if (events.isEmpty) {
      debugPrint('[EVENT_MAP] noValidCoordinates market=$market');
    }
    _mapEventByAnnotationId.clear();
    await manager.deleteAll();
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      debugPrint(
        '[EVENT_MAP] circleMarkerCreate title=${event.title} lat=${event.lat.toStringAsFixed(6)} lng=${event.lng.toStringAsFixed(6)}',
      );
      final annotation = await manager.create(
        mb.CircleAnnotationOptions(
          geometry: _mbPoint(event.lng, event.lat),
          circleColor: 0xFFE5B641,
          circleRadius: 10.5,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2.5,
        ),
      );
      _mapEventByAnnotationId[annotation.id] = event;
    }

    if (events.isNotEmpty) {
      final bounds = _mapBounds(events);
      debugPrint(
        '[EVENT_MAP] bounds minLat=${bounds.minLat.toStringAsFixed(6)} maxLat=${bounds.maxLat.toStringAsFixed(6)} minLng=${bounds.minLng.toStringAsFixed(6)} maxLng=${bounds.maxLng.toStringAsFixed(6)}',
      );
    }

    final selected = _selectedMapEvent;
    if (events.isEmpty) {
      if (mounted && selected != null) {
        setState(() => _selectedMapEvent = null);
      }
    } else if (selected != null) {
      final stillVisible = events.any((event) => event.id == selected.id);
      if (!stillVisible && mounted) {
        setState(() => _selectedMapEvent = null);
      }
    } else if (events.isNotEmpty && mounted) {
      setState(() => _selectedMapEvent = events.first);
    }
    final cameraTarget = _cameraTargetForEvents(events);
    final center = cameraTarget.center;
    final zoom = cameraTarget.zoom;
    final centerLon = center.coordinates.lng.toStringAsFixed(6);
    final centerLat = center.coordinates.lat.toStringAsFixed(6);
    debugPrint(
      '[EVENT_MAP] camera centerLat=$centerLat centerLng=$centerLon zoom=${zoom.toStringAsFixed(2)}',
    );
    await map.flyTo(
      mb.CameraOptions(center: center, zoom: zoom),
      mb.MapAnimationOptions(duration: 500),
    );
  }

  void _ensureMapClearedForNoMappableEvents() {
    if (_isClearingEmptyMapState) return;
    _isClearingEmptyMapState = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        _mapEventByAnnotationId.clear();
        if (_selectedMapEvent != null && mounted) {
          setState(() => _selectedMapEvent = null);
        }
        final manager = _mapCircleManager;
        if (manager != null) {
          await manager.deleteAll();
        }
      } finally {
        _isClearingEmptyMapState = false;
      }
    });
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
    final providerCountryCode = _providerCountryCodeFromMarketKey(
      widget.marketKey,
    );
    final providerMarketCode = _providerMarketCodeFromMarketKey(
      widget.marketKey,
    );
    return EventFeedQuery(
      countryCode: providerCountryCode,
      marketCode: providerMarketCode,
      dateMode: widget.dateMode,
      startAtUtc: isMonth ? widget.monthStartUtc : null,
      endAtUtc: isMonth ? widget.monthEndUtc : null,
      categoryKey: widget.categoryKey == 'all' ? null : widget.categoryKey,
      searchQuery: widget.searchQuery.trim(),
      limit: 50,
    );
  }

  String _providerCountryCodeFromMarketKey(String marketKey) {
    switch (marketKey.trim().toLowerCase()) {
      case 'be':
        return 'BE';
      case 'nl':
        return 'NL';
      case 'fr':
        return 'FR';
      case 'uk':
      case 'gb':
        return 'GB';
      case 'es':
        return 'ES';
      default:
        return marketKey.trim().toUpperCase();
    }
  }

  String _providerMarketCodeFromMarketKey(String marketKey) {
    switch (marketKey.trim().toLowerCase()) {
      case 'uk':
      case 'gb':
        return 'gb';
      default:
        return marketKey.trim().toLowerCase();
    }
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
              child: _selectedTabIndex == 0
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                      children: [
                        _buildSummaryPanel(),
                        const SizedBox(height: 12),
                        _buildSegmentedToggle(),
                        const SizedBox(height: 12),
                        if (events.isEmpty)
                          _buildEmptyState()
                        else
                          _buildEventList(events),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                      child: Column(
                        children: [
                          _buildSummaryPanel(),
                          const SizedBox(height: 12),
                          _buildSegmentedToggle(),
                          const SizedBox(height: 12),
                          Expanded(child: _buildMapPlaceholder()),
                        ],
                      ),
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
              style: TextStyle(
                color: _textPrimary,
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
        border: Border.all(
          color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
        ),
      ),
      child: Text(
        _filterSummary,
        style: TextStyle(
          color: _isDarkTheme ? _gold : _themePalette.bronze,
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
        border: Border.all(color: _border.withOpacity(_isDarkTheme ? 0.4 : 1)),
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
                color: selected ? _actionOnGold : _gold.withOpacity(0.92),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _actionOnGold : _textPrimary,
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
        border: Border.all(
          color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
        ),
        boxShadow: [
          BoxShadow(
            color: _shadow.withOpacity(_isDarkTheme ? 0.2 : 0.1),
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
                                  style: TextStyle(
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
                          style: TextStyle(
                            color: _textPrimary,
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
                  backgroundColor: _panelBlack,
                  foregroundColor: _gold,
                  side: BorderSide(
                    color: _border.withOpacity(_isDarkTheme ? 0.6 : 1),
                  ),
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
            style: TextStyle(color: _softText, fontSize: 11.9),
          ),
        ),
      ],
    );
  }

  Widget _buildMapPlaceholder() {
    final mappableEvents = _mappableEvents;
    final noMappableEvents = mappableEvents.isEmpty;
    final market = widget.marketKey.trim().toLowerCase();
    final visibleCount = _visibleEvents.length;
    if (market == 'fr') {
      debugPrint(
        '[EVENT_MAP] market=fr visibleEvents=$visibleCount mappableEvents=${mappableEvents.length}',
      );
    }
    if (noMappableEvents) {
      if (market == 'fr') {
        debugPrint(
          '[EVENT_MAP] fallbackMarketMap market=fr reason=no_mappable_events',
        );
      }
      _ensureMapClearedForNoMappableEvents();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = MediaQuery.of(context).size.height;
        final preferredHeight = (viewportHeight * 0.62)
            .clamp(520.0, 620.0)
            .toDouble();
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : preferredHeight;
        final mapHeight = availableHeight < preferredHeight
            ? availableHeight
            : availableHeight.clamp(520.0, 760.0).toDouble();
        debugPrint('[EVENT_MAP] mapHeight=${mapHeight.toStringAsFixed(1)}');
        return SizedBox(
          height: mapHeight,
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _border.withOpacity(_isDarkTheme ? 0.4 : 1),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: mb.MapWidget(
                    key: _mapWidgetKey,
                    onMapCreated: _onMapCreated,
                    textureView: true,
                    styleUri: _isDarkTheme
                        ? mb.MapboxStyles.DARK
                        : mb.MapboxStyles.LIGHT,
                    cameraOptions: mb.CameraOptions(
                      center: _marketFallbackCenter(),
                      zoom: 5.8,
                    ),
                  ),
                ),
                if (noMappableEvents)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: _buildNoMappableEventsOverlay(),
                  ),
                if (!noMappableEvents)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: _buildMapPreviewCard(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoMappableEventsOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _panelBlack.withOpacity(_isDarkTheme ? 0.9 : 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withOpacity(_isDarkTheme ? 0.5 : 1)),
      ),
      child: Text(
        _t(
          nl: 'Geen exacte eventlocaties gevonden voor deze selectie.',
          en: 'No exact event locations found for this selection.',
          fr: 'Aucun emplacement exact trouvé pour cette sélection.',
          es: 'No se encontraron ubicaciones exactas para esta selección.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _textPrimary,
          fontSize: 12.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMapPreviewCard() {
    final event = _selectedMapEvent;
    if (event == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _panelBlack.withOpacity(_isDarkTheme ? 0.86 : 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _border.withOpacity(_isDarkTheme ? 0.45 : 1),
          ),
        ),
        child: Text(
          _t(
            nl: 'Tik op een marker om dit event te bekijken.',
            en: 'Tap a marker to preview this event.',
            fr: 'Touchez un marqueur pour prévisualiser cet événement.',
            es: 'Pulsa un marcador para previsualizar este evento.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _panelBlack.withOpacity(_isDarkTheme ? 0.88 : 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withOpacity(_isDarkTheme ? 0.45 : 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            event.dateTimeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _softText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${event.locationName}, ${event.city}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _softText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _bookEvent(event),
              style: OutlinedButton.styleFrom(
                backgroundColor: _panelBlack,
                foregroundColor: _gold,
                side: BorderSide(
                  color: _border.withOpacity(_isDarkTheme ? 0.6 : 1),
                ),
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.local_taxi_rounded, size: 16),
              label: Text(
                _t(
                  nl: 'Taxi naar dit event',
                  en: 'Taxi to this event',
                  fr: 'Taxi vers cet événement',
                  es: 'Taxi a este evento',
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelBlack,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _border.withOpacity(_isDarkTheme ? 0.35 : 0.95),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: _gold.withOpacity(0.5)),
            ),
            child: Icon(
              Icons.confirmation_number_outlined,
              color: _gold.withOpacity(0.95),
              size: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              nl: 'Geen evenementen gevonden',
              en: 'No events found',
              fr: 'Aucun evenement trouve',
              es: 'No se encontraron eventos',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 14.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              nl: 'Probeer een andere zoekopdracht of wijzig je filters.',
              en: 'Try another search query or adjust your filters.',
              fr: 'Essayez une autre recherche ou modifiez vos filtres.',
              es: 'Prueba otra búsqueda o ajusta tus filtros.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _softText, fontSize: 12.8),
          ),
        ],
      ),
    );
  }
}
