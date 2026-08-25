import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_hotelpage.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';
import 'package:fluxidi_tracking/hotels/stay22_search.dart';

HotelStay _featuredStay() {
  return const HotelStay(
    id: 'approved-warwick-brussels',
    name: 'Warwick Brussels',
    type: HotelStayType.hotel,
    city: 'Brussel',
    region: 'Brussels',
    country: 'Belgium',
    address: 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
    description: 'Featured stay',
    imageRef: '',
    lat: 50.845,
    lng: 4.3543,
    imageUrl: 'https://example.com/warwick.jpg',
    provider: 'google-places',
    providerType: HotelStayProviderType.googlePlaces,
    source: 'google-places',
    isRealApproved: true,
  );
}

RatehawkSearchCriteria _validCriteria({
  String destination = 'Paris, France',
  int rooms = 1,
  int adults = 2,
  List<int> childAges = const <int>[],
}) {
  return RatehawkSearchCriteria(
    destination: destination,
    checkin: DateTime(2099, 8, 20),
    checkout: DateTime(2099, 8, 22),
    rooms: rooms,
    adults: adults,
    childAges: childAges,
  );
}

Widget _page({
  required RecordingRatehawkHotelSearchClient client,
  HotelsExternalUrlLauncher? launcher,
  RatehawkSearchCriteria? criteria,
  List<HotelStay>? stays,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 1800)),
      child: HotelsPage(
        stays: stays ?? <HotelStay>[_featuredStay()],
        ratehawkSearchClient: client,
        ratehawkHotelpageClient: RecordingRatehawkHotelpageClient(),
        initialRatehawkCriteria: criteria,
        externalUrlLauncher: launcher,
      ),
    ),
  );
}

void _assertNoSensitiveLeak(Uri uri) {
  expect(uri.queryParameters.containsKey('aid'), isTrue);
  final redacted = redactStay22Sensitive(uri.toString());
  expect(redacted.contains('aid=${uri.queryParameters['aid']}'), isFalse);
  expect(redacted, contains('[REDACTED_AID]'));
}

Finder _liveSearchCta() => find.byKey(const Key('stay22_live_search_cta'));

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

  testWidgets('native cards are labelled featured and not complete inventory', (
    tester,
  ) async {
    final client = RecordingRatehawkHotelSearchClient();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(client: client));
    await tester.pump();
    expect(find.text('1 uitgelichte verblijven'), findsOneWidget);
    expect(find.textContaining('verblijven gevonden'), findsNothing);
    expect(find.textContaining('Stay22-partners'), findsWidgets);
    expect(find.text('Live verblijven zoeken'), findsWidgets);
    expect(find.text('Kamers zoeken'), findsOneWidget);
    expect(client.calls, isEmpty);
  });

  testWidgets(
    'live search CTA stays disabled until destination and dates exist',
    (tester) async {
      final client = RecordingRatehawkHotelSearchClient();
      final launched = <Uri>[];
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          client: client,
          launcher: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      );
      await tester.pump();
    await tester.ensureVisible(_liveSearchCta());
    final button = tester.widget<FilledButton>(_liveSearchCta());
    expect(button.onPressed, isNull);
      expect(launched, isEmpty);
    },
  );

  testWidgets(
    'valid general search launches Stay22 with dates guests and campaign',
    (tester) async {
      final client = RecordingRatehawkHotelSearchClient();
      final launched = <Uri>[];
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          client: client,
          criteria: _validCriteria(
            rooms: 3,
            adults: 2,
            childAges: const <int>[8],
          ),
          launcher: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      );
      await tester.pump();
      await tester.ensureVisible(_liveSearchCta());
      await tester.tap(
        _liveSearchCta(),
      );
      await tester.pump();
      expect(launched, hasLength(1));
      final uri = launched.single;
      expect(uri.host, 'www.stay22.com');
      expect(uri.path, '/allez/searchbar');
      expect(uri.queryParameters['address'], 'Paris, France');
      expect(uri.queryParameters['checkin'], '2099-08-20');
      expect(uri.queryParameters['checkout'], '2099-08-22');
      expect(uri.queryParameters['adults'], '2');
      expect(uri.queryParameters['children'], '1');
      expect(uri.queryParameters['lang'], 'nl');
      expect(uri.queryParameters['currency'], 'EUR');
      expect(uri.queryParameters['campaign'], kStay22CampaignHotelsSearch);
      expect(uri.queryParameters.containsKey('rooms'), isFalse);
      expect(client.calls, isEmpty);
      _assertNoSensitiveLeak(uri);
      expect(
        find.text('Het aantal kamers bevestig je bij de aanbieder.'),
        findsWidgets,
      );
    },
  );

  testWidgets('global destination is not blocked by the country picker', (
    tester,
  ) async {
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        client: RecordingRatehawkHotelSearchClient(),
        criteria: _validCriteria(destination: 'Tokyo, Japan'),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.ensureVisible(_liveSearchCta());
    await tester.tap(_liveSearchCta());
    await tester.pump();
    expect(launched, hasLength(1));
    expect(launched.single.queryParameters['address'], 'Tokyo, Japan');
    expect(
      launched.single.queryParameters['campaign'],
      kStay22CampaignHotelsSearch,
    );
  });

  testWidgets('non-priority European country remains searchable', (
    tester,
  ) async {
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        client: RecordingRatehawkHotelSearchClient(),
        criteria: _validCriteria(destination: 'Vienna, Austria'),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.textContaining('Land:'));
    await tester.pumpAndSettle();
    expect(find.text('Alle landen'), findsWidgets);
    expect(find.text('België'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Oostenrijk'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Oostenrijk'), findsWidgets);
    await tester.tap(find.text('Oostenrijk'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_liveSearchCta());
    await tester.tap(_liveSearchCta());
    await tester.pump();
    expect(launched, hasLength(1));
    expect(launched.single.queryParameters['address'], contains('Vienna'));
    expect(launched.single.queryParameters['address'], contains('Austria'));
    expect(launched.single.queryParameters['currency'], 'EUR');
    expect(
      launched.single.queryParameters['address'],
      isNot(contains('Austria, Austria')),
    );
  });

  testWidgets('featured stay uses property destination and featured campaign', (
    tester,
  ) async {
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        client: RecordingRatehawkHotelSearchClient(),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Bekijk verblijf').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Bekijk beschikbaarheid').first);
    await tester.pump();
    expect(launched, hasLength(1));
    final uri = launched.single;
    expect(uri.path, '/allez/searchbar');
    expect(uri.queryParameters['address'], contains('Warwick Brussels'));
    expect(uri.queryParameters['campaign'], kStay22CampaignFeaturedStay);
    expect(uri.queryParameters.containsKey('checkin'), isFalse);
    expect(uri.queryParameters.containsKey('checkout'), isFalse);
    expect(uri.queryParameters['lat'], isNotNull);
    expect(uri.queryParameters.containsKey('rooms'), isFalse);
    _assertNoSensitiveLeak(uri);
  });

  testWidgets('saved stay uses its own campaign', (tester) async {
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        client: RecordingRatehawkHotelSearchClient(),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).last);
    await tester.pump();
    await tester.tap(find.text('Bekijk verblijf').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Bekijk beschikbaarheid').first);
    await tester.pump();
    expect(launched, hasLength(1));
    expect(
      launched.single.queryParameters['campaign'],
      kStay22CampaignSavedStay,
    );
  });

  testWidgets('repeated taps do not open multiple searches', (tester) async {
    final completer = Completer<bool>();
    var calls = 0;
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        client: RecordingRatehawkHotelSearchClient(),
        criteria: _validCriteria(),
        launcher: (uri) async {
          calls += 1;
          return completer.future;
        },
      ),
    );
    await tester.pump();
    final cta = _liveSearchCta();
    await tester.ensureVisible(cta);
    await tester.tap(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pump();
    expect(calls, 1);
    completer.complete(true);
    await tester.pump();
  });

  testWidgets(
    'launch failure shows a localized message without the affiliate URL',
    (tester) async {
      Uri? failed;
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          client: RecordingRatehawkHotelSearchClient(),
          criteria: _validCriteria(),
          launcher: (uri) async {
            failed = uri;
            return false;
          },
        ),
      );
      await tester.pump();
      await tester.ensureVisible(_liveSearchCta());
      await tester.tap(
        _liveSearchCta(),
      );
      await tester.pump();
      expect(failed, isNotNull);
      expect(
        find.text(
          'Kon de partnerbeschikbaarheid niet openen. Controleer je browser en probeer opnieuw.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(failed!.queryParameters['aid']!),
        findsNothing,
      );
      expect(find.textContaining('www.stay22.com'), findsNothing);
    },
  );

  testWidgets('RateHawk Kamers zoeken stays isolated from Stay22 launch', (
    tester,
  ) async {
    final client = RecordingRatehawkHotelSearchClient();
    final launched = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        client: client,
        criteria: _validCriteria(),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Kamers zoeken'));
    await tester.pump();
    expect(launched, isEmpty);
    expect(client.calls, isNotEmpty);
  });

  testWidgets('phone and tablet layouts do not overflow', (tester) async {
    for (final size in <Size>[const Size(390, 844), const Size(834, 1194)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: HotelsPage(
              stays: <HotelStay>[_featuredStay()],
              ratehawkSearchClient: RecordingRatehawkHotelSearchClient(),
              ratehawkHotelpageClient: RecordingRatehawkHotelpageClient(),
              initialRatehawkCriteria: _validCriteria(),
              externalUrlLauncher: (uri) async => true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Live verblijven zoeken'), findsWidgets);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
