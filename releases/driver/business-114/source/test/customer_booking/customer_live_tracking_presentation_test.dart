import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking_panel.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'customer_live_tracking_reassignment_test.dart' as fixture;

const palette = CustomerThemePalette(
  background: Colors.black,
  surface: Colors.black,
  surfaceAlt: Colors.black,
  textPrimary: Colors.white,
  textMuted: Colors.grey,
  gold: Colors.yellow,
  bronze: Colors.brown,
  border: Colors.grey,
  danger: Colors.red,
  success: Colors.green,
  shadow: Colors.black,
  isDark: true,
);
void main() {
  for (final metadata in [
    null,
    <String, dynamic>{},
    <String, dynamic>{
      'display_name': '',
      'label': '',
      'color': '',
      'license_plate': '',
    },
  ]) {
    testWidgets(
      'current empty public metadata clears previous panel labels: $metadata',
      (tester) async {
        final server = fixture.Server(tester);
        var clear = false;
        final controller = CustomerLiveTrackingController(
          bookingBaseUrl: 'https://booking.test',
          trackingBaseUrl: 'https://tracking.test',
          customerToken: () async => 'owner',
          now: tester.binding.clock.now,
          send:
              ({
                required method,
                required uri,
                required headers,
                jsonBody,
              }) async {
                final result = await server.send(
                  method: method,
                  uri: uri,
                  headers: headers,
                  jsonBody: jsonBody,
                );
                return method == 'GET' && clear
                    ? CustomerLiveHttpResult(
                        statusCode: 200,
                        body: {
                          ...result.body,
                          'driver': metadata,
                          'vehicle': metadata,
                        },
                      )
                    : result;
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
        Future<void> render() => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomerLiveTrackingPanel(
                view: controller.view,
                language: AppLanguage.nl,
                palette: palette,
                mapToken: '',
              ),
            ),
          ),
        );
        await render();
        expect(find.text('Alice'), findsOneWidget);
        expect(find.textContaining('Taxi 1'), findsOneWidget);
        clear = true;
        await tester.pump(const Duration(seconds: 10));
        await render();
        expect(controller.view.driverName, isEmpty);
        expect(controller.view.snapshot.vehicleLabel, isEmpty);
        expect(find.text('Alice'), findsNothing);
        expect(find.textContaining('Taxi 1'), findsNothing);
        expect(controller.view.showLivePosition, true);
        expect(controller.view.showEta, isNotNull);
        expect(tester.takeException(), isNull);
        expect(server.maxInFlight, 1);
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
