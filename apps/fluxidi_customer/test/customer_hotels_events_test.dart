import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/events/event_data_source.dart';
import 'package:fluxidi_tracking/events/event_models.dart';
import 'package:fluxidi_tracking/events/event_category_results_page.dart';
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
}
