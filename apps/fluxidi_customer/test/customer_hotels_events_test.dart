import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/events/event_data_source.dart';
import 'package:fluxidi_tracking/events/event_models.dart';
import 'package:fluxidi_tracking/events/event_category_results_page.dart';
import 'package:fluxidi_tracking/hotels/event_stay_search.dart';
import 'package:fluxidi_tracking/hotels/hotel_data_source.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';

HotelStay get _stay => const HotelStay(
      id: 'stay-1',
      name: 'Leopold Hotel Oudenaarde',
      type: HotelStayType.hotel,
      city: 'Oudenaarde',
      region: 'Oost-Vlaanderen',
      country: 'Belgium',
      address: 'Markt 1, Oudenaarde',
      description: 'Hotel in Oudenaarde.',
      imageRef: 'places:1',
      lat: 50.8449,
      lng: 3.6052,
      latitude: 50.8449,
      longitude: 3.6052,
      source: 'google-places',
      isRealApproved: true,
      rating: 4.3,
    );

HotelStay get _radisson => const HotelStay(
      id: 'stay-radisson',
      name: 'Radisson Blu Hotel, Hamburg',
      type: HotelStayType.hotel,
      city: 'Hamburg',
      region: 'Hamburg',
      country: 'Germany',
      address: 'Congressplatz 2, Hamburg',
      description: 'Live place discovery - Radisson Blu Hotel, Hamburg',
      imageRef: '',
      lat: 53.562,
      lng: 9.986,
      latitude: 53.562,
      longitude: 9.986,
      imageUrl: 'https://places.example/photo?maxwidth=400&maxheight=240',
      providerType: HotelStayProviderType.googlePlaces,
      providerLabel: 'Real place discovery',
      source: 'google-places',
      isRealApproved: true,
      rating: 4.4,
    );

class _StaticEvents implements EventDataSource {
  const _StaticEvents(this.events);

  final List<EventDetailData> events;

  @override
  List<EventDetailData> getInitialEvents() => events;

  @override
  Future<List<EventDetailData>> loadEvents() async => events;

  @override
  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    return EventFeedResult(
      events: events,
      source: 'test',
      receivedAtUtc: DateTime.utc(2026, 9, 21),
    );
  }
}

EventDetailData get _event => const EventDetailData(
      id: 'event-1',
      title: 'Zomerconcert op de Markt',
      category: 'Muziek',
      dateTimeLabel: 'za 21 jun · 20:00',
      locationName: 'Stadsschouwburg',
      city: 'Oudenaarde',
      address: 'Markt 1, Oudenaarde',
      lat: 50.8449,
      lng: 3.6052,
      distanceOrStatus: '',
      gradient: <Color>[Color(0xFF1A1A1A), Color(0xFF333333)],
      sourceUrl: 'https://example.test/tickets',
      marketCode: 'be',
      countryCode: 'BE',
    );

void main() {
  setUp(() {
    setAppLanguage(AppLanguage.nl);
  });

  testWidgets('compact hotels show results after search, not a long form', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    var taxi = 0;
    var transfer = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HotelsPage(
          compactCustomerLayout: true,
          stays: <HotelStay>[_stay],
          ratehawkSearchSubmitEnabled: false,
          onTaxiToStay: (_) => taxi += 1,
          onOpenAirportFlow: (_) async => transfer += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hotels & B&B'), findsOneWidget);
    expect(find.byKey(const Key('customer_hotels_filters')), findsOneWidget);
    expect(find.byKey(const Key('customer_hotels_stay_search')), findsOneWidget);
    expect(find.text('Leopold Hotel Oudenaarde'), findsOneWidget);
    expect(find.text('Real place discovery'), findsNothing);
    expect(find.textContaining('Taxi naar dit verblijf'), findsNothing);
    await tester.tap(find.byKey(const Key('customer_hotels_taxi_stay-1')));
    await tester.pump();
    expect(taxi, 1);
    await tester.tap(find.byKey(const Key('customer_hotels_transfer_stay-1')));
    await tester.pump();
    expect(transfer, 1);
  });

  testWidgets('compact events put taxi, hotels and tickets on the card', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    var taxi = 0;
    var hotels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EventCategoryResultsPage(
          title: 'Evenementen',
          dataSource: _StaticEvents(<EventDetailData>[_event]),
          marketKey: 'be',
          dateMode: EventDateMode.all,
          sortMode: 'default',
          compactCustomerLayout: true,
          onBookEvent: (_) => taxi += 1,
          onOpenHotels: (_) => hotels += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zomerconcert op de Markt'), findsOneWidget);
    expect(find.textContaining('Stadsschouwburg'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer_events_taxi_event-1')));
    await tester.pump();
    expect(taxi, 1);
    await tester.tap(find.byKey(const Key('customer_events_hotels_event-1')));
    await tester.pump();
    expect(hotels, 1);
    expect(find.byKey(const Key('customer_events_tickets_event-1')), findsOneWidget);
  });

  testWidgets('hotel detail shows the full photo and drops discovery copy', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: HotelsPage(
          compactCustomerLayout: true,
          stays: <HotelStay>[_radisson],
          ratehawkSearchSubmitEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer_hotels_stay_name_stay-radisson')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer_hotel_detail_photo')), findsOneWidget);
    expect(find.text('Radisson Blu Hotel, Hamburg'), findsWidgets);
    expect(find.text('Taxi naar dit verblijf'), findsOneWidget);
    expect(find.text('Bekijk beschikbaarheid'), findsOneWidget);
    expect(find.text('Luchthaven transfer'), findsOneWidget);
    expect(find.text('Real place discovery'), findsNothing);
    expect(find.textContaining('Live place discovery'), findsNothing);
    expect(find.textContaining('uitgelichte inspiratie'), findsNothing);
    expect(find.textContaining('Stay22-partners'), findsNothing);
  });

  testWidgets('event detail shows the full photo and drops mobility copy', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: EventCategoryResultsPage(
          title: 'Evenementen',
          dataSource: _StaticEvents(<EventDetailData>[_event]),
          marketKey: 'be',
          dateMode: EventDateMode.all,
          sortMode: 'default',
          compactCustomerLayout: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer_events_card_event-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer_event_detail_photo')), findsOneWidget);
    expect(find.text('Zomerconcert op de Markt'), findsWidgets);
    expect(find.textContaining('Stadsschouwburg'), findsWidgets);
    expect(find.text('Taxi naar dit event boeken'), findsOneWidget);
    expect(find.text('Tickets bekijken'), findsOneWidget);
    expect(find.text('Mobiliteitsadvies'), findsNothing);
    expect(find.text('Verwachte mobiliteitsvraag'), findsNothing);
    expect(find.textContaining('uitgelichte inspiratie'), findsNothing);
    expect(find.textContaining('extern getoond'), findsNothing);
  });

  testWidgets('event detail hotels follow the selected event', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    EventDetailData? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: EventCategoryResultsPage(
          title: 'Evenementen',
          dataSource: _StaticEvents(<EventDetailData>[_event]),
          marketKey: 'be',
          dateMode: EventDateMode.all,
          sortMode: 'default',
          compactCustomerLayout: true,
          onOpenHotels: (event) => opened = event,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customer_events_card_event-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Verblijven rond dit event'),
      200,
    );
    await tester.tap(find.text('Verblijven rond dit event'));
    await tester.pump();

    expect(opened?.id, 'event-1');
    expect(opened?.locationName, 'Stadsschouwburg');
  });

  testWidgets('event hotels on a phone use the venue, not its name as a filter', (
    tester,
  ) async {
    await _expectEventHotels(tester, const Size(390, 844));
  });

  testWidgets('event hotels on a tablet refresh when the event changes', (
    tester,
  ) async {
    await _expectEventHotels(tester, const Size(800, 1280));
  });

  testWidgets(
    'event hotels use the places search centred on the venue',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      final source = _VenuePlacesSource();
      await tester.pumpWidget(
        MaterialApp(
          home: HotelsPage(
            compactCustomerLayout: true,
            hotelDataSource: source,
            ratehawkSearchSubmitEnabled: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MEININGER Hotel Bruxelles City Center'), findsOneWidget);
      expect(source.queries, hasLength(1));
      expect(source.queries.single.source, 'google-places');
      expect(source.queries.single.lat, isNull);
      expect(source.queries.single.lng, isNull);
      expect(source.queries.single.radiusKm, isNull);
      expect(source.queries.single.destination, isNull);
      expect(source.queries.single.searchText, isNull);

      final spirit = _locatedEvent(
        id: 'spirit-66',
        locationName: 'Spirit of 66',
        city: 'Verviers',
        address: 'Place du Martyr, 16',
        lat: 50.59353,
        lng: 5.86109,
        startAtUtc: _concertUtc(),
      );
      final spiritSearch = EventStaySearch.fromEvent(spirit);
      final hostKey = GlobalKey<_SearchingEventHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _SearchingEventHost(
            key: hostKey,
            event: spirit,
            source: source,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(source.queries, hasLength(2));
      final spiritQuery = source.queries.last;
      expect(spiritQuery.source, 'google-places');
      expect(spiritQuery.lat, closeTo(50.59353, 0.000001));
      expect(spiritQuery.lng, closeTo(5.86109, 0.000001));
      expect(spiritQuery.radiusKm, kEventStayNearbyRadiusKm);
      expect(spiritQuery.destination, isNull);
      expect(spiritQuery.searchText, isNull);
      expect(spiritQuery.city, isNull);
      expect(find.text('Hotels nabij Spirit of 66'), findsOneWidget);
      expect(find.textContaining(spiritSearch.checkinYmd!), findsWidgets);
      expect(find.byKey(const Key('customer_hotels_stay_search')), findsNothing);
      expect(find.byKey(const Key('stay22_live_search_cta')), findsNothing);
      expect(find.byKey(const Key('customer_event_stay_provider_note')), findsOneWidget);
      await _bringIntoView(tester, find.text('Van der Valk Hotel Verviers'));
      expect(find.text('Hotel des Ardennes'), findsOneWidget);
      expect(find.text('MEININGER Hotel Bruxelles City Center'), findsNothing);
      expect(find.textContaining('Geen uitgelichte inspiratie'), findsNothing);
      expect(find.byKey(const Key('customer_hotels_stay_photo_vdv')), findsNothing);
      expect(find.byKey(const Key('customer_event_stay_distance_vdv')), findsOneWidget);
      expect(find.textContaining('van de evenementlocatie'), findsWidgets);
      expect(
        tester.getTopLeft(find.text('Van der Valk Hotel Verviers')).dy,
        lessThan(tester.getTopLeft(find.text('Hotel des Ardennes')).dy),
      );
      await _bringIntoView(
        tester,
        find.byKey(const Key('customer_hotels_view_stay_vdv')),
      );

      final brussels = _locatedEvent(
        id: 'ancienne-belgique',
        locationName: 'Ancienne Belgique',
        city: 'Brussels',
        address: 'Boulevard Anspach 110',
        lat: 50.847232,
        lng: 4.348831,
        startAtUtc: _concertUtc().add(const Duration(days: 51)),
      );
      final brusselsSearch = EventStaySearch.fromEvent(brussels);
      hostKey.currentState!.show(brussels);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(source.queries, hasLength(3));
      final brusselsQuery = source.queries.last;
      expect(brusselsQuery.source, 'google-places');
      expect(brusselsQuery.lat, closeTo(50.847232, 0.000001));
      expect(brusselsQuery.lng, closeTo(4.348831, 0.000001));
      expect(brusselsQuery.radiusKm, kEventStayNearbyRadiusKm);
      expect(brusselsQuery.destination, isNull);
      expect(brusselsQuery.searchText, isNull);
      await _returnToListStart(tester);
      expect(find.text('Hotels nabij Ancienne Belgique'), findsOneWidget);
      expect(find.textContaining(brusselsSearch.checkinYmd!), findsWidgets);
      await _bringIntoView(tester, find.text('La Bourse Hotel'));
      expect(find.text('Aparthotel Adagio Brussels Grand Place'), findsOneWidget);
      expect(find.text('Van der Valk Hotel Verviers'), findsNothing);
      expect(find.byKey(const Key('customer_event_stay_distance_bourse')), findsOneWidget);
      expect(find.textContaining('van de evenementlocatie'), findsWidgets);
      await _bringIntoView(
        tester,
        find.byKey(const Key('customer_hotels_view_stay_bourse')),
      );
    },
  );

  testWidgets('an empty inspiration list is not shown as no hotels', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final start = DateTime.now().toUtc().add(const Duration(days: 40));
    await tester.pumpWidget(
      MaterialApp(
        home: HotelsPage(
          compactCustomerLayout: true,
          eventStay: EventStaySearch.fromEvent(
            _locatedEvent(
              id: 'spirit-empty',
              locationName: 'Spirit of 66',
              city: 'Verviers',
              address: 'Place du Martyr, 16',
              lat: 50.59353,
              lng: 5.86109,
              startAtUtc: DateTime.utc(start.year, start.month, start.day, 16),
            ),
          ),
          stays: const <HotelStay>[],
          ratehawkSearchSubmitEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hotels nabij Spirit of 66'), findsOneWidget);
    expect(find.byKey(const Key('customer_event_stay_provider_note')), findsOneWidget);
    expect(find.byKey(const Key('customer_hotels_filters')), findsOneWidget);
    expect(find.byKey(const Key('customer_hotels_stay_search')), findsNothing);
    expect(find.byKey(const Key('stay22_live_search_cta')), findsNothing);
    expect(find.byKey(const Key('customer_event_stay_empty')), findsOneWidget);
    expect(find.textContaining('geen hotels'), findsNothing);
    expect(find.textContaining('Geen hotels'), findsNothing);
    expect(find.textContaining('uitgelichte inspiratie'), findsNothing);
  });
}

DateTime _concertUtc() {
  final day = DateTime.now().toUtc().add(const Duration(days: 40));
  return DateTime.utc(day.year, day.month, day.day, 16);
}

EventDetailData _locatedEvent({
  required String id,
  required String locationName,
  required String city,
  required String address,
  required double lat,
  required double lng,
  required DateTime startAtUtc,
}) {
  return EventDetailData(
    id: id,
    title: 'Concert',
    category: 'Muziek',
    dateTimeLabel: 'gepland',
    locationName: locationName,
    city: city,
    address: address,
    lat: lat,
    lng: lng,
    distanceOrStatus: '',
    gradient: const <Color>[Color(0xFF1A1A1A), Color(0xFF333333)],
    countryCode: 'BE',
    startAtUtc: startAtUtc,
    timeZone: 'Europe/Brussels',
  );
}

HotelStay _geoStay({
  required String id,
  required String name,
  required String city,
  required double latitude,
  required double longitude,
}) {
  return HotelStay(
    id: id,
    name: name,
    type: HotelStayType.hotel,
    city: city,
    region: city,
    country: 'Belgium',
    address: city,
    description: name,
    imageRef: 'places:$id',
    lat: latitude,
    lng: longitude,
    latitude: latitude,
    longitude: longitude,
    source: 'google-places',
    isRealApproved: true,
    rating: 4.2,
  );
}

class _VenuePlacesSource implements HotelPagedDataSource {
  final queries = <HotelStayQuery>[];

  @override
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    return (await fetchStayPage(query: query)).stays;
  }

  @override
  Future<HotelStaySearchPage> fetchStayPage({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    queries.add(query);
    if (query.source != 'google-places' ||
        (query.destination ?? '').trim().isNotEmpty ||
        (query.searchText ?? '').trim().isNotEmpty) {
      return const HotelStaySearchPage(stays: <HotelStay>[]);
    }
    final lat = query.lat;
    final lng = query.lng;
    if (lat == null || lng == null || query.radiusKm == null) {
      return HotelStaySearchPage(
        stays: <HotelStay>[
          _geoStay(
            id: 'meininger',
            name: 'MEININGER Hotel Bruxelles City Center',
            city: 'Belgium',
            latitude: 50.8512504,
            longitude: 4.347,
          ),
        ],
      );
    }
    if ((lat - 50.59353).abs() < 0.01 && (lng - 5.86109).abs() < 0.01) {
      return HotelStaySearchPage(
        stays: <HotelStay>[
          _geoStay(
            id: 'vdv',
            name: 'Van der Valk Hotel Verviers',
            city: 'Verviers',
            latitude: 50.5918,
            longitude: 5.8634,
          ),
          _geoStay(
            id: 'ardennes',
            name: 'Hotel des Ardennes',
            city: 'Verviers',
            latitude: 50.5886,
            longitude: 5.87,
          ),
        ],
      );
    }
    if ((lat - 50.847232).abs() < 0.01 && (lng - 4.348831).abs() < 0.01) {
      return HotelStaySearchPage(
        stays: <HotelStay>[
          _geoStay(
            id: 'bourse',
            name: 'La Bourse Hotel',
            city: 'Brussels',
            latitude: 50.8486,
            longitude: 4.3498,
          ),
          _geoStay(
            id: 'adagio',
            name: 'Aparthotel Adagio Brussels Grand Place',
            city: 'Brussels',
            latitude: 50.8462,
            longitude: 4.3528,
          ),
        ],
      );
    }
    return const HotelStaySearchPage(stays: <HotelStay>[]);
  }
}

class _SearchingEventHost extends StatefulWidget {
  const _SearchingEventHost({
    required this.event,
    required this.source,
    super.key,
  });

  final EventDetailData event;
  final _VenuePlacesSource source;

  @override
  State<_SearchingEventHost> createState() => _SearchingEventHostState();
}

class _SearchingEventHostState extends State<_SearchingEventHost> {
  late EventDetailData _event;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
  }

  void show(EventDetailData event) => setState(() => _event = event);

  @override
  Widget build(BuildContext context) {
    return HotelsPage(
      key: const ValueKey<String>('event-hotels-search'),
      compactCustomerLayout: true,
      eventStay: EventStaySearch.fromEvent(_event),
      hotelDataSource: widget.source,
      ratehawkSearchSubmitEnabled: false,
    );
  }
}

class _EventHotelsHost extends StatefulWidget {
  const _EventHotelsHost({
    required this.event,
    required this.onLaunch,
    super.key,
  });

  final EventDetailData event;
  final HotelsExternalUrlLauncher onLaunch;

  @override
  State<_EventHotelsHost> createState() => _EventHotelsHostState();
}

class _EventHotelsHostState extends State<_EventHotelsHost> {
  late EventDetailData _event;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
  }

  void show(EventDetailData event) => setState(() => _event = event);

  @override
  Widget build(BuildContext context) {
    return HotelsPage(
      key: const ValueKey<String>('event-hotels'),
      compactCustomerLayout: true,
      eventStay: EventStaySearch.fromEvent(_event),
      initialSearchQuery: 'Verviers Spirit of 66',
      stays: <HotelStay>[
        _geoStay(
          id: 'brussels',
          name: 'Hotel Brussel',
          city: 'Brussels',
          latitude: 50.847232,
          longitude: 4.348831,
        ),
        _geoStay(
          id: 'verviers',
          name: 'Hotel des Ardennes',
          city: 'Verviers',
          latitude: 50.589,
          longitude: 5.87,
        ),
      ],
      ratehawkSearchSubmitEnabled: false,
      externalUrlLauncher: widget.onLaunch,
    );
  }
}

Future<void> _bringIntoView(WidgetTester tester, Finder target) async {
  final list = find.byType(ListView).first;
  Future<void> drag(Offset offset) async {
    for (var i = 0; i < 24 && target.evaluate().isEmpty; i++) {
      await tester.drag(list, offset);
      await tester.pump();
    }
  }

  await drag(const Offset(0, -280));
  if (target.evaluate().isEmpty) {
    await drag(const Offset(0, 500));
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await tester.pump();
}

Future<void> _returnToListStart(WidgetTester tester) async {
  final list = find.byType(ListView).first;
  for (var i = 0; i < 20; i++) {
    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
  }
}

Future<void> _expectEventHotels(WidgetTester tester, Size size) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  final hostKey = GlobalKey<_EventHotelsHostState>();
  final opened = <Uri>[];
  final spirit = _locatedEvent(
    id: 'spirit-66',
    locationName: 'Spirit of 66',
    city: 'Verviers',
    address: 'Place du Martyr, 16',
    lat: 50.59353,
    lng: 5.86109,
    startAtUtc: _concertUtc(),
  );
  final spiritSearch = EventStaySearch.fromEvent(spirit);
  final brussels = _locatedEvent(
    id: 'ancienne-belgique',
    locationName: 'Ancienne Belgique',
    city: 'Brussels',
    address: 'Boulevard Anspach 110',
    lat: 50.847232,
    lng: 4.348831,
    startAtUtc: _concertUtc().add(const Duration(days: 7)),
  );
  final brusselsSearch = EventStaySearch.fromEvent(brussels);

  await tester.pumpWidget(
    MaterialApp(
      home: _EventHotelsHost(
        key: hostKey,
        event: spirit,
        onLaunch: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Hotels nabij Spirit of 66'), findsOneWidget);
  expect(find.text('Verviers Spirit of 66'), findsNothing);
  expect(find.textContaining('coördinaten'), findsNothing);
  expect(find.textContaining('Place du Martyr, 16'), findsOneWidget);
  expect(find.byKey(const Key('customer_hotels_filters')), findsOneWidget);
  expect(find.byKey(const Key('customer_hotels_stay_search')), findsNothing);
  expect(find.byKey(const Key('stay22_live_search_cta')), findsNothing);
  expect(find.byKey(const Key('customer_event_stay_provider_note')), findsOneWidget);
  expect(find.textContaining(spiritSearch.checkinYmd!), findsWidgets);
  expect(find.textContaining(spiritSearch.checkoutYmd!), findsWidgets);

  await tester.ensureVisible(find.byKey(const Key('hotel_stay_checkin')));
  await tester.tap(find.byKey(const Key('hotel_stay_checkin')));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
  await tester.pumpAndSettle();

  await _bringIntoView(
    tester,
    find.byKey(const Key('customer_hotels_view_stay_verviers')),
  );
  await tester.tap(find.byKey(const Key('customer_hotels_view_stay_verviers')));
  await tester.pumpAndSettle();

  expect(opened, hasLength(1));
  expect(find.byKey(const Key('customer_hotel_detail_photo')), findsNothing);
  expect(opened.single.host, 'www.stay22.com');
  expect(opened.single.path, '/allez/searchbar');
  expect(opened.single.queryParameters['aid'], 'fluxidi');
  expect(opened.single.queryParameters['campaign'], 'fluxidi_featured_stay');
  expect(opened.single.queryParameters['lat'], '50.589000');
  expect(opened.single.queryParameters['lng'], '5.870000');
  expect(opened.single.queryParameters['checkin'], spiritSearch.checkinYmd);
  expect(opened.single.queryParameters['checkout'], spiritSearch.checkoutYmd);
  expect(opened.single.queryParameters['address'], contains('Hotel des Ardennes'));
  expect(
    opened.single.queryParameters['address'],
    isNot(contains('Spirit of 66')),
  );

  await _bringIntoView(tester, find.text('Hotel Brussel'));
  expect(find.text('Hotel des Ardennes'), findsOneWidget);
  expect(
    tester.getTopLeft(find.text('Hotel des Ardennes')).dy,
    lessThan(tester.getTopLeft(find.text('Hotel Brussel')).dy),
  );

  await _returnToListStart(tester);
  hostKey.currentState!.show(brussels);
  await tester.pumpAndSettle();

  expect(find.text('Hotels nabij Ancienne Belgique'), findsOneWidget);
  expect(find.textContaining('Place du Martyr'), findsNothing);
  expect(find.textContaining('Boulevard Anspach'), findsWidgets);
  expect(find.textContaining(brusselsSearch.checkinYmd!), findsWidgets);
  await _bringIntoView(tester, find.text('Hotel des Ardennes'));
  expect(
    tester.getTopLeft(find.text('Hotel Brussel')).dy,
    lessThan(tester.getTopLeft(find.text('Hotel des Ardennes')).dy),
  );

  await _bringIntoView(
    tester,
    find.byKey(const Key('customer_hotels_view_stay_brussels')),
  );
  await tester.tap(find.byKey(const Key('customer_hotels_view_stay_brussels')));
  await tester.pumpAndSettle();

  expect(opened, hasLength(2));
  expect(opened.last.queryParameters['aid'], 'fluxidi');
  expect(opened.last.queryParameters['campaign'], 'fluxidi_featured_stay');
  expect(opened.last.queryParameters['lat'], '50.847232');
  expect(opened.last.queryParameters['lng'], '4.348831');
  expect(opened.last.queryParameters['checkin'], brusselsSearch.checkinYmd);
  expect(opened.last.queryParameters['address'], contains('Hotel Brussel'));
  expect(opened.last.queryParameters['address'], isNot(contains('Place du Martyr')));
  expect(opened.last.queryParameters['address'], isNot(contains('Hotel des Ardennes')));
}
