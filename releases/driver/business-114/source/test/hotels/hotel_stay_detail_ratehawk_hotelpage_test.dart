import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_hotelpage.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';

HotelStay _localStay() {
  return const HotelStay(
    id: 'approved-warwick-brussels',
    name: 'Warwick Brussels',
    type: HotelStayType.hotel,
    city: 'Brussel',
    region: 'Brussels',
    country: 'Belgium',
    address: 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
    description: 'Local approved stay',
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

HotelStay _ratehawkStay({RatehawkViewStaySnapshot? viewStay}) {
  return HotelStay(
    id: 'ratehawk:8473727',
    name: 'Warwick Brussels',
    type: HotelStayType.hotel,
    city: 'Brussel',
    region: 'Brussels',
    country: 'Belgium',
    address: 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
    description: 'RateHawk stay',
    imageRef: '',
    lat: 50.845,
    lng: 4.3543,
    imageUrl: 'https://example.com/warwick.jpg',
    provider: 'ratehawk',
    source: 'ratehawk',
    hid: 8473727,
    isRealApproved: true,
    viewStay: viewStay,
  );
}

RatehawkViewStaySnapshot _context() {
  return const RatehawkViewStaySnapshot(
    contextToken: 'rhctx1.payload.sig',
    hid: 8473727,
    checkin: '2026-09-03',
    checkout: '2026-09-04',
    residency: 'be',
    currency: 'EUR',
    guests: <RatehawkGuestRoom>[RatehawkGuestRoom(adults: 2)],
  );
}

RatehawkHotelpageOffer _offer({bool bookable = true}) {
  return RatehawkHotelpageOffer(
    offerRef: 'rh1.aaa.bbb',
    roomName: 'Deluxe Room',
    roomDescription: 'City view',
    occupancy: '2 adults',
    beds: '1 king',
    mealPlan: 'breakfast',
    breakfastIncluded: true,
    remainingAvailability: '3',
    customerTotal: '180.00',
    customerTotalLabel: 'EUR 180.00',
    currency: 'EUR',
    includedTaxes: const <RatehawkMoneyLine>[
      RatehawkMoneyLine(name: 'VAT', amount: '20.00'),
    ],
    excludedTaxes: const <RatehawkMoneyLine>[
      RatehawkMoneyLine(
        name: 'City tax',
        amount: '4.50',
        payableWhere: 'property',
      ),
    ],
    vatIncluded: true,
    payment: const RatehawkPaymentDisclosure(
      type: 'hotel',
      recipient: 'hotel',
      timing: 'at_property',
    ),
    cardDataRequired: true,
    deposit: const RatehawkHotelDepositDisclosure(
      disclosed: true,
      amount: '50.00',
      currency: 'EUR',
      refundable: true,
      recipient: 'hotel',
      timing: 'at_checkin',
    ),
    cancellation: const RatehawkCancellationDisclosure(
      refundable: true,
      freeCancellationBefore: '2026-09-01T12:00:00Z',
    ),
    noShow: const RatehawkNoShowDisclosure(
      disclosed: true,
      amount: '180.00',
      currency: 'EUR',
      fromTime: '18:00',
      timezoneContext: 'hotel_local_time',
    ),
    bookable: bookable,
  );
}

Widget _page({
  required HotelStay stay,
  required RatehawkHotelpageClient hotelpageClient,
  RatehawkHotelSearchClient? searchClient,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 1800)),
      child: HotelsPage(
        stays: <HotelStay>[stay],
        ratehawkSearchClient:
            searchClient ?? RecordingRatehawkHotelSearchClient(),
        ratehawkHotelpageClient: hotelpageClient,
      ),
    ),
  );
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

  testWidgets(
    'existing detail opens with no RateHawk request for a non-RateHawk stay',
    (tester) async {
      final hotelpage = RecordingRatehawkHotelpageClient();
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(stay: _localStay(), hotelpageClient: hotelpage),
      );
      await tester.pump();
      await tester.tap(find.text('Bekijk verblijf').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hotelpage.calls, isEmpty);
      expect(find.text('Taxi naar dit verblijf'), findsWidgets);
      expect(find.text('Luchthaven transfer'), findsWidgets);
      expect(find.text('Evenementen in de buurt'), findsWidgets);
      expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
    },
  );

  testWidgets(
    'RateHawk stay with valid context requests Hotelpage only after View stay',
    (tester) async {
      final hotelpage = RecordingRatehawkHotelpageClient(
        response: RatehawkHotelpageResponse(
          ok: true,
          offers: <RatehawkHotelpageOffer>[_offer()],
          retrievedAt: DateTime.utc(2026, 8, 17, 10),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          stay: _ratehawkStay(viewStay: _context()),
          hotelpageClient: hotelpage,
        ),
      );
      await tester.pump();
      expect(hotelpage.calls, isEmpty);
      await tester.tap(find.text('Bekijk verblijf').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hotelpage.calls, hasLength(1));
      expect(find.text('Deluxe Room'), findsWidgets);
      expect(find.text('EUR 180.00'), findsWidgets);
      expect(find.textContaining('hotel'), findsWidgets);
      expect(find.textContaining('50.00'), findsWidgets);
      expect(find.text('Taxi naar dit verblijf'), findsWidgets);
      expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
    },
  );

  testWidgets('retryable Hotelpage failure retains Stay22 and mobility', (
    tester,
  ) async {
    final hotelpage = RecordingRatehawkHotelpageClient();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        stay: _ratehawkStay(viewStay: _context()),
        hotelpageClient: hotelpage,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Bekijk verblijf').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Opnieuw'), findsWidgets);
    expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
    expect(find.text('Taxi naar dit verblijf'), findsWidgets);
    expect(find.text('Luchthaven transfer'), findsWidgets);
    expect(find.text('Evenementen in de buurt'), findsWidgets);
  });

  testWidgets(
    'missing context opens existing detail without Hotelpage request',
    (tester) async {
      final hotelpage = RecordingRatehawkHotelpageClient();
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(stay: _ratehawkStay(), hotelpageClient: hotelpage),
      );
      await tester.pump();
      await tester.tap(find.text('Bekijk verblijf').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hotelpage.calls, isEmpty);
      expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
      expect(find.text('Taxi naar dit verblijf'), findsWidgets);
    },
  );
}
