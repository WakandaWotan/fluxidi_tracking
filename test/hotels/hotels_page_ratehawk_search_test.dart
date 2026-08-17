import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/hotels_page.dart';
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

Widget _hotelsPage(RatehawkHotelSearchClient client) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 1800)),
      child: HotelsPage(
        stays: <HotelStay>[_localStay()],
        ratehawkSearchClient: client,
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

  testWidgets('existing cards render before RateHawk and no request on open', (
    tester,
  ) async {
    final client = RecordingRatehawkHotelSearchClient();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_hotelsPage(client));
    await tester.pump();
    expect(find.text('Warwick Brussels'), findsWidgets);
    expect(client.calls, isEmpty);
    expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
    expect(find.textContaining('Stay22'), findsNothing);
    expect(find.text('Taxi naar dit verblijf'), findsWidgets);
    expect(find.text('Bekijk verblijf'), findsWidgets);
    expect(find.text('Opgeslagen'), findsWidgets);
  });

  testWidgets('RateHawk unavailable keeps current hotel and mobility flow', (
    tester,
  ) async {
    final client = RecordingRatehawkHotelSearchClient();
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_hotelsPage(client));
    await tester.pump();
    expect(find.text('Warwick Brussels'), findsWidgets);
    expect(find.text('Evenementen in de buurt'), findsNothing);
    await tester.tap(find.text('Bekijk verblijf').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Taxi naar dit verblijf'), findsWidgets);
    expect(find.text('Luchthaven transfer'), findsWidgets);
    expect(find.text('Evenementen in de buurt'), findsWidgets);
    expect(find.text('Bekijk beschikbaarheid'), findsWidgets);
    expect(client.calls, isEmpty);
  });
}
