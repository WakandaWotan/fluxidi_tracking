import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search_panel.dart';

void main() {
  testWidgets('search strip does not request until criteria are complete', (
    tester,
  ) async {
    final client = RecordingRatehawkHotelSearchClient();
    final controller = RatehawkSearchController(client: client);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RatehawkSearchStrip(
            controller: controller,
            languageCode: 'nl',
            palette: paletteForCustomerTheme(CustomerThemeVariant.nightGold),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kamers zoeken'));
    await tester.pump();
    expect(client.calls, isEmpty);
  });

  testWidgets('status panel shows retry when unavailable', (tester) async {
    final controller = RatehawkSearchController(
      client: RecordingRatehawkHotelSearchClient(),
    );
    controller.setCriteria(
      RatehawkSearchCriteria(
        destination: 'Brussel, Belgium',
        checkin: DateTime.utc(2026, 9, 3),
        checkout: DateTime.utc(2026, 9, 4),
      ),
    );
    await controller.submit();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RatehawkSearchStatusPanel(
            controller: controller,
            languageCode: 'nl',
            palette: paletteForCustomerTheme(CustomerThemeVariant.nightGold),
          ),
        ),
      ),
    );
    expect(find.text('Live beschikbaarheid niet beschikbaar'), findsOneWidget);
    expect(find.text('Opnieuw'), findsOneWidget);
    expect(find.text('Annuleren / bewerken'), findsOneWidget);
  });
}
