import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking_panel.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/ride/operational_route_labels.dart';
import 'customer_live_tracking_stale_test.dart' as fixture;

Map<String, dynamic> live(DateTime now) => {
  ...fixture.live(now).body,
  'tracking_phase': 'in_progress',
  'response_version': 8,
  'assignment_version': 2,
  'destination': {'latitude': 51.3, 'longitude': 4.3},
  'pickup': {'latitude': 51.1, 'longitude': 4.1},
  'eta': {
    'target': 'destination',
    'duration_seconds': 120,
    'valid_until': now.add(const Duration(seconds: 5)).toIso8601String(),
  },
  'operational_route': {
    'destination_address': 'Nieuw adres',
    'expected_end_iso': '2026-10-03T12:00:00Z',
    'actor_driver_id': 'private-driver',
    'update_id': 'private-id',
  },
};
void main() {
  test(
    'public route parser keeps only customer-visible metadata and new destination',
    () {
      final parsed = parseCustomerLiveSnapshot(live(DateTime.now()));
      expect(parsed.destination!.latitude, 51.3);
      expect(parsed.operationalRouteMetadata, {
        'destination_address': 'Nieuw adres',
        'expected_end_iso': '2026-10-03T12:00:00Z',
      });
      expect(
        () => parsed.operationalRouteMetadata['actor_driver_id'] = 'bad',
        throwsUnsupportedError,
      );
      for (final phase in [
        'assigned',
        'stopped',
        'completed',
        'cancelled',
        'expired',
      ]) {
        expect(
          parseCustomerLiveSnapshot({
            ...live(DateTime.now()),
            'tracking_phase': phase,
          }).operationalRouteMetadata,
          isEmpty,
        );
      }
      expect(
        parseCustomerLiveSnapshot({
          ...live(DateTime.now()),
          'operational_route': {
            'destination_address': 'a',
            'expected_end_iso': 'bad',
          },
        }).operationalRouteMetadata,
        isEmpty,
      );
    },
  );
  testWidgets(
    'ETA expiry never removes the changed destination or route notice',
    (tester) async {
      var reads = 0;
      final controller = CustomerLiveTrackingController(
        bookingBaseUrl: 'https://booking.test',
        trackingBaseUrl: 'https://tracking.test',
        customerToken: () async => 'customer',
        now: tester.binding.clock.now,
        send:
            ({
              required method,
              required uri,
              required headers,
              jsonBody,
            }) async {
              if (method == 'POST') return fixture.boot;
              reads++;
              return CustomerLiveHttpResult(
                statusCode: 200,
                body: live(tester.binding.clock.now()),
              );
            },
      );
      controller.bind(
        const CustomerLiveTrackingIdentity(
          tenantId: 'T',
          companyId: 'C',
          bookingId: 'B',
        ),
      );
      controller.setForeground(true);
      await tester.pump();
      expect(controller.view.snapshot.destination!.latitude, 51.3);
      await tester.pump(const Duration(seconds: 6));
      expect(controller.view.snapshot.eta, isNull);
      expect(controller.view.snapshot.destination!.latitude, 51.3);
      expect(controller.view.snapshot.pickup!.latitude, 51.1);
      expect(
        controller
            .view
            .snapshot
            .operationalRouteMetadata['destination_address'],
        'Nieuw adres',
      );
      expect(reads, 1, reason: 'route display adds no polling');
      controller.dispose();
    },
  );
  for (final language in AppLanguage.values) {
    testWidgets('customer changed destination is translated ${language.name}', (
      tester,
    ) async {
      final snapshot = parseCustomerLiveSnapshot(live(DateTime.now()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerLiveTrackingPanel(
              view: CustomerLiveTrackingView(
                availability: CustomerLiveTrackingAvailability.tracking,
                snapshot: snapshot,
              ),
              language: language,
              palette: paletteForCustomerTheme(CustomerThemeVariant.nightGold),
              mapToken: '',
            ),
          ),
        ),
      );
      expect(
        find.text('${kOperationalRouteChanged.of(language)}: Nieuw adres'),
        findsOneWidget,
      );
      expect(
        find.textContaining(kOperationalRouteEnd.of(language)),
        findsOneWidget,
      );
      expect(find.textContaining('private-driver'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
