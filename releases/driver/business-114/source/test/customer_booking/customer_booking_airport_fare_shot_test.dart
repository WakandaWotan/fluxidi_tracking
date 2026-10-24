import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_airport_fare.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';

void main() {
  testWidgets('writes the airport contact notice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 390,
              child: RepaintBoundary(
                key: const Key('airport_fare_shot'),
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CustomerBookingAirportFareNotice(
                      language: AppLanguage.nl,
                      companyName: 'Zuid Luchthavenrit',
                      leadTimeLabel: 'Minimaal 24 uur vooraf',
                      showLeadTime: true,
                      onContact: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(kCustomerBookingAirportFareNoticeKey), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('airport_fare_shot')),
    );
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
    final bytes = await tester.runAsync(() async {
      final data = await image!.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final dir = Directory('.device-check/airport-fare');
    dir.createSync(recursive: true);
    File('${dir.path}/prijs-op-aanvraag.png').writeAsBytesSync(bytes!);
  });
}
