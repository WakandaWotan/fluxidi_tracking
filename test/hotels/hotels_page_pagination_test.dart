import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/hotels/hotel_data_source.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotel_places_pagination.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_hotelpage.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';
import 'package:fluxidi_tracking/hotels/stay22_search.dart';

HotelStay _stay(String id, {String country = 'PT', String name = ''}) {
  return HotelStay(
    id: 'google_places:$id',
    name: name.isEmpty ? 'Stay $id' : name,
    type: HotelStayType.hotel,
    city: 'Lisbon',
    region: 'Lisbon District',
    country: country,
    address: 'Lisbon, Portugal',
    description: 'Featured stay',
    imageRef: '',
    lat: 38.7,
    lng: -9.1,
    imageUrl: 'https://example.com/$id.jpg',
    provider: 'google-places',
    providerType: HotelStayProviderType.googlePlaces,
    source: 'google-places',
    isRealApproved: true,
  );
}

class PagedHotelSource implements HotelPagedDataSource {
  PagedHotelSource({
    this.page2Status = HotelStaySearchStatus.ok,
    this.page2Delay = Duration.zero,
  });

  HotelStaySearchStatus page2Status;
  Duration page2Delay;
  int page1Calls = 0;
  int page2Calls = 0;
  final List<HotelStayQuery> calls = <HotelStayQuery>[];

  @override
  Future<List<HotelStay>> fetchStays({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    final page = await fetchStayPage(query: query);
    return page.stays;
  }

  @override
  Future<HotelStaySearchPage> fetchStayPage({
    HotelStayQuery query = const HotelStayQuery(),
  }) async {
    calls.add(query);
    if ((query.pageCursor ?? '').isNotEmpty) {
      page2Calls += 1;
      if (page2Delay > Duration.zero) {
        await Future<void>.delayed(page2Delay);
      }
      if (page2Status == HotelStaySearchStatus.cursorNotReady) {
        return const HotelStaySearchPage(
          stays: <HotelStay>[],
          status: HotelStaySearchStatus.cursorNotReady,
          retryAfterMs: 1500,
        );
      }
      if (page2Status != HotelStaySearchStatus.ok) {
        return HotelStaySearchPage(
          stays: const <HotelStay>[],
          status: page2Status,
        );
      }
      return HotelStaySearchPage(
        stays: <HotelStay>[
          _stay('p2-a', name: 'Page two A'),
          _stay('p1-1', name: 'Duplicate first page'),
          _stay('p2-b', name: 'Page two B'),
        ],
      );
    }
    page1Calls += 1;
    return HotelStaySearchPage(
      stays: List<HotelStay>.generate(
        20,
        (index) => _stay('p1-$index', name: 'Page one $index'),
      ),
      pagination: const HotelPlacesPaginationMeta(
        page: 1,
        hasMore: true,
        maxPages: 2,
        nextCursor: 'opaque-cursor-value-1234',
      ),
    );
  }
}

Widget _page(HotelPagedDataSource source, {String? country}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 1800)),
      child: HotelsPage(
        hotelDataSource: source,
        ratehawkSearchSubmitEnabled: false,
        ratehawkSearchClient: RecordingRatehawkHotelSearchClient(),
        ratehawkHotelpageClient: RecordingRatehawkHotelpageClient(),
        initialCountryCode: country,
        externalUrlLauncher: (uri) async => true,
      ),
    ),
  );
}

Finder _moreButton() =>
    find.byKey(const Key('google_places_more_featured_stays'));

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

  testWidgets('page 2 never loads automatically and appears only for has_more', (
    tester,
  ) async {
    final source = PagedHotelSource();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(source, country: 'PT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.page1Calls, 1);
    expect(source.page2Calls, 0);
    expect(_moreButton(), findsOneWidget);
    expect(find.textContaining('20 uitgelichte verblijven'), findsWidgets);
    expect(find.text(stay22MoreFeaturedStaysLabel('nl')), findsOneWidget);
  });

  testWidgets('double tap sends one page-2 request and appends unique cards', (
    tester,
  ) async {
    final source = PagedHotelSource(page2Delay: const Duration(milliseconds: 40));
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(source, country: 'PT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(_moreButton());
    await tester.tap(_moreButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(source.page2Calls, 1);
    expect(find.text('Page two A'), findsOneWidget);
    expect(find.text('Page two B'), findsOneWidget);
    expect(find.textContaining('21 uitgelichte verblijven'), findsWidgets);
    expect(_moreButton(), findsNothing);
    expect(source.calls.last.pageCursor, 'opaque-cursor-value-1234');
    expect(source.calls.last.countryCode, 'PT');
  });

  testWidgets('page 1 remains when page 2 is not ready and query change drops cursor', (
    tester,
  ) async {
    final source = PagedHotelSource(
      page2Status: HotelStaySearchStatus.cursorNotReady,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(source, country: 'PT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(_moreButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Page one 0'), findsWidgets);
    expect(find.text(stay22MoreFeaturedStaysRetryLabel('nl')), findsOneWidget);
    tester.state<HotelsPageState>(find.byType(HotelsPage)).selectCountryForTest('ES');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls.last.countryCode, 'ES');
    expect(source.calls.last.pageCursor, isNull);
    expect(
      tester.state<HotelsPageState>(find.byType(HotelsPage)).page2SnapshotForTest.phase,
      isNot(HotelPlacesPage2Phase.loading),
    );
  });

  testWidgets('city selection sends canonical English query metadata', (
    tester,
  ) async {
    final source = PagedHotelSource();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(source, country: 'PT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    tester.state<HotelsPageState>(find.byType(HotelsPage)).selectCityForTest('lisbon');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls.last.city, 'Lisbon');
    expect(source.calls.last.region, 'Lisbon District');
    expect(source.calls.last.country, 'Portugal');
    expect(source.calls.last.countryCode, 'PT');
  });
}
