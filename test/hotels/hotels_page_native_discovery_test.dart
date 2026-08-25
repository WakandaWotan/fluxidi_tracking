import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/hotels/hotel_data_source.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_hotelpage.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';
import 'package:fluxidi_tracking/hotels/stay22_search.dart';

HotelStay _stay({
  required String id,
  required String country,
  String city = 'City',
  String name = 'Featured stay',
}) {
  return HotelStay(
    id: id,
    name: name,
    type: HotelStayType.hotel,
    city: city,
    region: '',
    country: country,
    address: '$city, $country',
    description: 'Featured stay',
    imageRef: '',
    lat: 50.0,
    lng: 4.0,
    imageUrl: 'https://example.com/$id.jpg',
    provider: 'google-places',
    providerType: HotelStayProviderType.googlePlaces,
    source: 'google-places',
    isRealApproved: true,
  );
}

class RecordingHotelDataSource implements HotelDataSource {
  RecordingHotelDataSource({this.delay = Duration.zero});

  Duration delay;
  final List<HotelStayQuery> calls = <HotelStayQuery>[];

  @override
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    calls.add(query);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final iso = (query.countryCode ?? '').toUpperCase();
    return <HotelStay>[
      _stay(
        id: 'google_places:$iso',
        country: iso.isEmpty ? 'BE' : iso,
        city: query.destination?.isNotEmpty == true
            ? query.destination!
            : (query.city ?? iso),
        name: 'Stay $iso',
      ),
    ];
  }
}

class CompleterHotelDataSource implements HotelDataSource {
  final List<HotelStayQuery> calls = <HotelStayQuery>[];
  final List<Completer<List<HotelStay>>> _pending =
      <Completer<List<HotelStay>>>[];

  @override
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  }) {
    calls.add(query);
    final completer = Completer<List<HotelStay>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeAt(int index) {
    final query = calls[index];
    final iso = (query.countryCode ?? 'BE').toUpperCase();
    _pending[index].complete(<HotelStay>[
      _stay(id: 'google_places:$iso', country: iso, name: 'Stay $iso'),
    ]);
  }
}

Widget _page({
  List<HotelStay>? stays,
  HotelDataSource? hotelDataSource,
  bool? ratehawkSearchSubmitEnabled,
  RatehawkSearchCriteria? criteria,
  String? initialCountryCode,
  Size size = const Size(1200, 1800),
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: HotelsPage(
        stays: stays,
        hotelDataSource: hotelDataSource,
        ratehawkSearchSubmitEnabled: ratehawkSearchSubmitEnabled,
        ratehawkSearchClient: RecordingRatehawkHotelSearchClient(),
        ratehawkHotelpageClient: RecordingRatehawkHotelpageClient(),
        initialRatehawkCriteria: criteria,
        initialCountryCode: initialCountryCode,
        externalUrlLauncher: (uri) async => true,
      ),
    ),
  );
}

Finder _liveCta() => find.byKey(const Key('stay22_live_search_cta'));

void _selectCountry(WidgetTester tester, String code) {
  tester
      .state<HotelsPageState>(find.byType(HotelsPage))
      .selectCountryForTest(code);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLanguage previousLanguage;

  setUp(() {
    previousLanguage = appLanguageNotifier.value;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  tearDown(() {
    appLanguageNotifier.value = previousLanguage;
  });

  testWidgets('structured ISO and English country name are sent', (
    tester,
  ) async {
    final source = RecordingHotelDataSource();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(hotelDataSource: source));
    await tester.pump();
    expect(source.calls, isNotEmpty);
    expect(source.calls.first.countryCode, 'BE');
    expect(source.calls.first.country, 'Belgium');
    _selectCountry(tester, 'ES');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls.last.countryCode, 'ES');
    expect(source.calls.last.country, 'Spain');
    expect(source.calls.last.country, isNot('Spanje'));
  });

  testWidgets('ISO country results remain visible after filtering', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        stays: <HotelStay>[
          _stay(id: 'es-1', country: 'ES', name: 'Madrid stay'),
          _stay(id: 'de-1', country: 'DE', name: 'Berlin stay'),
          _stay(id: 'nl-1', country: 'NL', name: 'Amsterdam stay'),
          _stay(id: 'gb-1', country: 'GB', name: 'London stay'),
          _stay(id: 'pt-1', country: 'PT', name: 'Lisbon stay'),
          _stay(id: 'dk-1', country: 'DK', name: 'Copenhagen stay'),
        ],
      ),
    );
    await tester.pump();

    Future<void> expectOnly(String visible, List<String> hidden) async {
      expect(find.text(visible), findsWidgets);
      for (final name in hidden) {
        expect(find.text(name), findsNothing);
      }
    }

    _selectCountry(tester, 'ES');
    await tester.pump();
    await expectOnly('Madrid stay', [
      'Berlin stay',
      'Amsterdam stay',
      'London stay',
      'Lisbon stay',
      'Copenhagen stay',
    ]);
    _selectCountry(tester, 'DE');
    await tester.pump();
    await expectOnly('Berlin stay', ['Madrid stay']);
    _selectCountry(tester, 'NL');
    await tester.pump();
    await expectOnly('Amsterdam stay', ['Berlin stay']);
    _selectCountry(tester, 'GB');
    await tester.pump();
    await expectOnly('London stay', ['Amsterdam stay']);
    _selectCountry(tester, 'PT');
    await tester.pump();
    await expectOnly('Lisbon stay', ['London stay']);
    _selectCountry(tester, 'DK');
    await tester.pump();
    await expectOnly('Copenhagen stay', ['Lisbon stay']);
  });

  testWidgets('stale Belgium response cannot replace a newer Spain query', (
    tester,
  ) async {
    final source = RecordingHotelDataSource(
      delay: const Duration(milliseconds: 250),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(hotelDataSource: source));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    _selectCountry(tester, 'ES');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stay ES'), findsWidgets);
    expect(find.text('Stay BE'), findsNothing);
    expect(source.calls.last.countryCode, 'ES');
  });

  testWidgets('newer query is executed after an active older request', (
    tester,
  ) async {
    final source = CompleterHotelDataSource();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(hotelDataSource: source));
    await tester.pump();
    expect(source.calls, hasLength(1));
    expect(source.calls.first.countryCode, 'BE');
    _selectCountry(tester, 'ES');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls.last.countryCode, 'ES');
    expect(source.calls.length, greaterThanOrEqualTo(2));
    final belgiumIndex = source.calls.indexWhere(
      (query) => query.countryCode == 'BE',
    );
    final spainIndex = source.calls.lastIndexWhere(
      (query) => query.countryCode == 'ES',
    );
    source.completeAt(belgiumIndex);
    await tester.pump();
    await tester.pump();
    expect(find.text('Stay BE'), findsNothing);
    source.completeAt(spainIndex);
    await tester.pump();
    await tester.pump();
    expect(find.text('Stay ES'), findsWidgets);
    expect(find.text('Stay BE'), findsNothing);
  });

  testWidgets('seeded countries keep selectors and unseeded use free text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        stays: <HotelStay>[_stay(id: 'be-1', country: 'BE')],
        initialCountryCode: 'ES',
      ),
    );
    await tester.pump();
    expect(find.textContaining('Regio:'), findsOneWidget);
    expect(find.textContaining('Stad:'), findsOneWidget);
    await tester.tap(find.textContaining('Regio:'));
    await tester.pumpAndSettle();
    expect(find.text('Catalonië'), findsWidgets);
    await tester.tap(find.text('Alle regio\'s'));
    await tester.pumpAndSettle();

    _selectCountry(tester, 'PT');
    await tester.pump();
    expect(find.textContaining('Regio:'), findsNothing);
    expect(find.textContaining('Stad:'), findsNothing);
    expect(find.text(stay22CityRegionGuidance('nl')), findsWidgets);
    expect(find.text(stay22UnseededGeoControlHint('nl')), findsWidgets);
    expect(find.text('Alle regio\'s'), findsNothing);
  });

  testWidgets('search UX has one Stay22 CTA and no gated RateHawk submit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(stays: const <HotelStay>[]));
    await tester.pump();
    expect(_liveCta(), findsOneWidget);
    expect(find.text('Kamers zoeken'), findsNothing);
    expect(
      find.text(
        'Booking.com wordt geactiveerd zodra de partneraanvraag is goedgekeurd.',
      ),
      findsNothing,
    );
    expect(find.text(stay22EmptyFeaturedTitle('nl')), findsOneWidget);
    expect(find.text(stay22EmptyFeaturedBody('nl')), findsOneWidget);
    expect(find.text(stay22FeaturedExplanation('nl')), findsWidgets);
  });

  testWidgets('RateHawk submit remains available when its UI gate is on', (
    tester,
  ) async {
    final client = RecordingRatehawkHotelSearchClient();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 1800)),
          child: HotelsPage(
            stays: <HotelStay>[_stay(id: 'be-1', country: 'BE')],
            ratehawkSearchSubmitEnabled: true,
            ratehawkSearchClient: client,
            ratehawkHotelpageClient: RecordingRatehawkHotelpageClient(),
            initialRatehawkCriteria: RatehawkSearchCriteria(
              destination: 'Brussels, Belgium',
              checkin: DateTime(2099, 8, 20),
              checkout: DateTime(2099, 8, 22),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Kamers zoeken'), findsOneWidget);
    await tester.tap(find.text('Kamers zoeken'));
    await tester.pump();
    expect(client.calls, isNotEmpty);
  });

  testWidgets('country picker does not open an empty region dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        stays: <HotelStay>[_stay(id: 'be-1', country: 'BE')],
      ),
    );
    await tester.pump();
    await tester.tap(find.textContaining('Land:'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Oostenrijk'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Oostenrijk'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Regio:'), findsNothing);
    expect(find.text('Alle regio\'s'), findsNothing);
    expect(find.text(stay22CityRegionGuidance('nl')), findsWidgets);
  });

  testWidgets(
    'filter sheet hides empty region selectors for unseeded countries',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          stays: <HotelStay>[_stay(id: 'pt-1', country: 'PT')],
          initialCountryCode: 'PT',
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Regio'), findsNothing);
      expect(find.text('Stad'), findsNothing);
      expect(find.text('Alle regio\'s'), findsNothing);
      expect(find.text(stay22UnseededGeoControlHint('nl')), findsWidgets);
      expect(find.text('Type'), findsOneWidget);
    },
  );

  testWidgets('phone and tablet native layouts do not overflow', (
    tester,
  ) async {
    for (final size in <Size>[const Size(390, 844), const Size(834, 1194)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _page(
          stays: <HotelStay>[
            _stay(id: 'es-1', country: 'ES', name: 'Madrid stay'),
          ],
          size: size,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_liveCta(), findsOneWidget);
      expect(find.text('Kamers zoeken'), findsNothing);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
