// GOOGLE-MAPS-PIP-LIVE-METER-P0
//
// Proves the compact PiP meter observes the same authoritative
// [DriverRideMetersNotifier] as Tellers — not a frozen enter-time snapshot.
// Does NOT create a second fare engine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters_notifier.dart';

import 'dart:io';

String _read(String relativePath) =>
    File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

DriverRideMetersSnapshot _snap({
  String fare = '€ 10,00',
  String km = '2.0 km',
  String duration = '00:05:00',
  String wait = '00:00:00',
  String eta = '',
  String remaining = '',
}) {
  return DriverRideMetersSnapshot(
    fareText: fare,
    distanceTravelledText: km,
    rideDurationText: duration,
    waitingTimeText: wait,
    statusText: 'Rit actief',
    etaText: eta,
    remainingDistanceText: remaining,
  );
}

void main() {
  group('PiP projects authoritative meter snapshot (no second engine)', () {
    test('street live tariff follows fare/km/duration from snapshot', () {
      final m1 = buildExternalNavPipMeterModelFromRideMeters(
        snapshot: _snap(fare: '€ 12,40', km: '3.2 km', duration: '00:08:10'),
        phase: ExternalNavPhase.activeRide,
        isStreetRide: true,
        isFixedPrice: false,
        language: AppLanguage.en,
      );
      expect(m1.kind, PipMeterKind.liveTariff);
      expect(m1.primaryValue, '€ 12,40');
      expect(m1.kmText, '3.2 km');
      expect(m1.durationText, '00:08:10');

      final m2 = buildExternalNavPipMeterModelFromRideMeters(
        snapshot: _snap(fare: '€ 18,90', km: '5.1 km', duration: '00:14:22'),
        phase: ExternalNavPhase.activeRide,
        isStreetRide: true,
        isFixedPrice: false,
        language: AppLanguage.en,
      );
      expect(m2.primaryValue, '€ 18,90');
      expect(m2.kmText, '5.1 km');
      expect(m2.durationText, '00:14:22');
    });

    test('fixed-price PiP keeps fixed primary; duration still advances', () {
      final early = buildExternalNavPipMeterModelFromRideMeters(
        snapshot: _snap(
          fare: '€ 22,00',
          km: '1.0 km',
          duration: '00:02:00',
          remaining: '4.0 km',
        ),
        phase: ExternalNavPhase.activeRide,
        isStreetRide: false,
        isFixedPrice: true,
        fixedPriceText: '€ 22,00',
        language: AppLanguage.en,
      );
      final later = buildExternalNavPipMeterModelFromRideMeters(
        snapshot: _snap(
          fare: '€ 22,00',
          km: '3.5 km',
          duration: '00:09:30',
          remaining: '1.5 km',
        ),
        phase: ExternalNavPhase.activeRide,
        isStreetRide: false,
        isFixedPrice: true,
        fixedPriceText: '€ 22,00',
        language: AppLanguage.en,
      );
      expect(early.kind, PipMeterKind.fixedPrice);
      expect(early.primaryValue, '€ 22,00');
      expect(later.primaryValue, '€ 22,00');
      expect(later.durationText, isNot(early.durationText));
      expect(later.kmText, '1.5 km'); // remaining preferred for destination
    });

    test('ride identity fields progress without reset across PiP ticks', () {
      // Simulates START → PiP progression → resume → PiP again using one
      // continuous notifier (no duplicate subscription, no reset).
      final notifier = DriverRideMetersNotifier(emptyDriverRideMetersSnapshot());
      final seen = <String>[];
      notifier.addListener(() {
        final m = buildExternalNavPipMeterModelFromRideMeters(
          snapshot: notifier.value,
          phase: ExternalNavPhase.activeRide,
          isStreetRide: true,
          isFixedPrice: false,
          language: AppLanguage.en,
        );
        seen.add('${m.primaryValue}|${m.kmText}|${m.durationText}');
      });

      notifier.publish(
        _snap(fare: '€ 5,00', km: '1.0 km', duration: '00:03:00'),
      );
      notifier.publish(
        _snap(fare: '€ 8,50', km: '2.4 km', duration: '00:06:00'),
      );
      // "return to foreground" then second Maps/PiP — same notifier.
      notifier.publish(
        _snap(fare: '€ 11,20', km: '3.8 km', duration: '00:09:00'),
      );
      notifier.publish(
        _snap(fare: '€ 14,00', km: '5.0 km', duration: '00:12:00'),
      );

      expect(seen.length, 4);
      expect(seen.first, '€ 5,00|1.0 km|00:03:00');
      expect(seen.last, '€ 14,00|5.0 km|00:12:00');
      // Monotonic progression — no reset to empty / zero.
      expect(seen.toSet().length, 4);
      notifier.dispose();
    });

    test('STOP totals use last authoritative snapshot once', () {
      final progression = <DriverRideMetersSnapshot>[
        _snap(fare: '€ 4,00', km: '0.8 km', duration: '00:02:00'),
        _snap(fare: '€ 9,00', km: '2.5 km', duration: '00:07:00'),
        _snap(fare: '€ 13,50', km: '4.2 km', duration: '00:11:00'),
      ];
      final finalSnap = progression.last;
      final m = buildExternalNavPipMeterModelFromRideMeters(
        snapshot: finalSnap,
        phase: ExternalNavPhase.activeRide,
        isStreetRide: true,
        isFixedPrice: false,
        language: AppLanguage.en,
      );
      expect(m.primaryValue, '€ 13,50');
      expect(m.kmText, '4.2 km');
      expect(m.durationText, '00:11:00');
      // Whole interval represented exactly once in the final projection.
      expect(progression.where((s) => s.fareText == finalSnap.fareText).length, 1);
    });
  });

  group('PiP widget rebuilds from notifier without parent setState', () {
    testWidgets('card text updates when notifier publishes', (tester) async {
      final notifier = DriverRideMetersNotifier(
        _snap(fare: '€ 7,00', km: '1.5 km', duration: '00:04:00'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<DriverRideMetersSnapshot>(
            valueListenable: notifier,
            builder: (context, snap, _) {
              return ExternalNavPipMeterCard(
                model: buildExternalNavPipMeterModelFromRideMeters(
                  snapshot: snap,
                  phase: ExternalNavPhase.activeRide,
                  isStreetRide: true,
                  isFixedPrice: false,
                  language: AppLanguage.en,
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('€ 7,00'), findsOneWidget);
      expect(find.textContaining('1.5 km'), findsWidgets);

      notifier.publish(
        _snap(fare: '€ 16,25', km: '4.7 km', duration: '00:10:15'),
      );
      await tester.pump();

      expect(find.text('€ 16,25'), findsOneWidget);
      expect(find.text('€ 7,00'), findsNothing);
      expect(find.textContaining('4.7 km'), findsWidgets);

      notifier.dispose();
    });
  });

  group('source contract — driver home PiP wiring', () {
    late String homeSource;

    setUpAll(() {
      homeSource = _read('lib/main_parts/driver_home_page_state.dart');
    });

    test('PiP overlay uses ValueListenableBuilder on meter notifier', () {
      expect(homeSource, contains('GOOGLE-MAPS-PIP-LIVE-METER-P0'));
      expect(homeSource, contains('ValueListenableBuilder<DriverRideMetersSnapshot>'));
      expect(homeSource, contains('valueListenable: _driverRideMetersNotifier'));
      expect(homeSource, contains('ValueListenableBuilder<AppLanguage>'));
      expect(homeSource, contains('valueListenable: appLanguageNotifier'));
      expect(
        homeSource,
        contains('buildExternalNavPipMeterModelFromRideMeters'),
      );
      // Preserve prior PiP crash protection: MapWidget kept Offstage-mounted.
      expect(homeSource, contains('Offstage(offstage: true, child: driverBody)'));
      expect(homeSource, contains('map_kept_mounted=true'));
    });

    test('meter ticker publishes without setState (no MapWidget rebuild)', () {
      expect(homeSource, contains('_publishDriverRideMetersSnapshot()'));
      expect(homeSource, contains('rebuilding the MapWidget subtree'));
      expect(homeSource, contains('if (_externalNavigationSession?.pipActive == true) return;'));
    });
  });
}
