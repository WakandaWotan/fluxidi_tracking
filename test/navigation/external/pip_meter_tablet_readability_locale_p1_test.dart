// PIP-TABLET-READABILITY-LOCALE-P1
//
// Focused coverage for tablet PiP meter density + driver-locale contract.
// Does not exercise Google Maps routing, fare engines, or PiP lifecycle natives.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_session.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters_notifier.dart';

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

Future<void> _pumpMeter(
  WidgetTester tester, {
  required Size size,
  required ExternalNavPipMeterModel model,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: ExternalNavPipMeterCard(model: model),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('locale normalize + resolve', () {
    test('supports nl/en/fr/es and regional variants', () {
      expect(normalizePipMeterLanguageCode('nl'), AppLanguage.nl);
      expect(normalizePipMeterLanguageCode('nl-BE'), AppLanguage.nl);
      expect(normalizePipMeterLanguageCode('en_US'), AppLanguage.en);
      expect(normalizePipMeterLanguageCode('fr-FR'), AppLanguage.fr);
      expect(normalizePipMeterLanguageCode('es-ES'), AppLanguage.es);
    });

    test('unsupported / empty falls back to English', () {
      expect(normalizePipMeterLanguageCode(null), AppLanguage.en);
      expect(normalizePipMeterLanguageCode(''), AppLanguage.en);
      expect(normalizePipMeterLanguageCode('de'), AppLanguage.en);
      expect(normalizePipMeterLanguageCode('pt-BR'), AppLanguage.en);
      expect(
        resolvePipMeterLanguage(appLanguage: AppLanguage.de),
        AppLanguage.en,
      );
    });

    test('explicit app language wins over device locale', () {
      expect(
        resolvePipMeterLanguage(
          appLanguage: AppLanguage.fr,
          deviceLocaleCode: 'nl-BE',
        ),
        AppLanguage.fr,
      );
    });
  });

  group('localized chrome NL/EN/FR/ES', () {
    test('route phase + KPI labels for all four languages', () {
      final cases = <AppLanguage, ({
        String pickup,
        String dest,
        String distance,
        String time,
        String price,
        String live,
      })>{
        AppLanguage.nl: (
          pickup: 'Naar ophaalpunt',
          dest: 'Naar bestemming',
          distance: 'Afstand',
          time: 'Tijd',
          price: 'Prijs',
          live: 'Actueel',
        ),
        AppLanguage.en: (
          pickup: 'To pickup',
          dest: 'To destination',
          distance: 'Distance',
          time: 'Time',
          price: 'Price',
          live: 'Current',
        ),
        AppLanguage.fr: (
          pickup: 'Vers le lieu de prise en charge',
          dest: 'Vers la destination',
          distance: 'Distance',
          time: 'Temps',
          price: 'Prix',
          live: 'Actuel',
        ),
        AppLanguage.es: (
          pickup: 'Hacia el punto de recogida',
          dest: 'Hacia el destino',
          distance: 'Distancia',
          time: 'Tiempo',
          price: 'Precio',
          live: 'Actual',
        ),
      };

      for (final entry in cases.entries) {
        final lang = entry.key;
        final expect_ = entry.value;
        final pickup = buildExternalNavPipMeterModel(
          phase: ExternalNavPhase.toPickup,
          isStreetRide: false,
          isFixedPrice: false,
          language: lang,
          etaText: '5 min',
          remainingDistanceText: '1.2 km',
        );
        expect(pickup.title, expect_.pickup, reason: '$lang pickup title');
        expect(pickup.primaryLabel, 'ETA');
        expect(pickup.metrics.single.label, expect_.distance);

        final fixed = buildExternalNavPipMeterModel(
          phase: ExternalNavPhase.activeRide,
          isStreetRide: false,
          isFixedPrice: true,
          language: lang,
          fixedPriceText: '€20,00',
          kmText: '3.0 km',
          durationText: '00:10:00',
        );
        expect(fixed.title, expect_.dest, reason: '$lang dest title');
        expect(fixed.primaryLabel, expect_.price);
        expect(fixed.metrics[0].label, expect_.distance);
        expect(fixed.metrics[1].label, expect_.time);

        final live = buildExternalNavPipMeterModel(
          phase: ExternalNavPhase.activeRide,
          isStreetRide: true,
          isFixedPrice: false,
          language: lang,
          liveFareText: '€11,00',
          kmText: '2.0 km',
          durationText: '00:04:00',
        );
        expect(live.primaryLabel, expect_.live);
      }
    });

    test('no hard-coded Dutch when language is English', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.toPickup,
        isStreetRide: false,
        isFixedPrice: false,
        language: AppLanguage.en,
        etaText: '4 min',
        remainingDistanceText: '900 m',
      );
      expect(m.title, 'To pickup');
      expect(m.title, isNot(contains('Naar')));
      expect(m.metrics.single.label, 'Distance');
      expect(m.metrics.single.label, isNot('Afstand'));
    });

    test('unknown primary renders em dash, not false zero', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.toPickup,
        isStreetRide: false,
        isFixedPrice: false,
        language: AppLanguage.en,
      );
      expect(m.primaryValue, '—');
      expect(m.primaryValue, isNot('0'));
      expect(m.primaryValue, isNot('00:00'));
    });

    test('time value never pairs under distance label', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.activeRide,
        isStreetRide: true,
        isFixedPrice: false,
        language: AppLanguage.nl,
        liveFareText: '€9,00',
        // Remaining distance preferred for distance KPI.
        remainingDistanceText: '1.5 km',
        durationText: '00:07:30',
        // ETA must not overwrite duration (legacy pairing bug).
        etaText: '3 min',
      );
      final distance = m.metrics.firstWhere((e) => e.label == 'Afstand');
      final time = m.metrics.firstWhere((e) => e.label == 'Tijd');
      expect(distance.value, '1.5 km');
      expect(time.value, '00:07:30');
      expect(time.value, isNot('3 min'));
      expect(distance.value, isNot('00:07:30'));
    });
  });

  group('responsive layout', () {
    final activeModel = buildExternalNavPipMeterModel(
      phase: ExternalNavPhase.activeRide,
      isStreetRide: true,
      isFixedPrice: false,
      language: AppLanguage.en,
      liveFareText: '€14,25',
      kmText: '4.1 km',
      durationText: '00:11:00',
      waitText: '00:01:00',
    );

    testWidgets('tablet portrait: large KPIs, labeled columns, no overflow', (
      tester,
    ) async {
      const size = Size(800, 1280);
      await _pumpMeter(tester, size: size, model: activeModel);
      expect(tester.takeException(), isNull);
      expect(find.text('To destination'), findsOneWidget);
      expect(find.text('€14,25'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('4.1 km'), findsOneWidget);
      expect(find.text('00:11:00'), findsOneWidget);

      final typo = PipMeterTypography.forSize(size, compact: true);
      expect(typo.metricSize, greaterThanOrEqualTo(32));
      expect(typo.titleSize, greaterThanOrEqualTo(24));
      expect(typo.verticalPadding, lessThanOrEqualTo(12));
    });

    testWidgets('tablet landscape: no overflow, labeled metrics retained', (
      tester,
    ) async {
      const size = Size(1280, 800);
      await _pumpMeter(tester, size: size, model: activeModel);
      expect(tester.takeException(), isNull);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
    });

    testWidgets('phone regression: typography unchanged, no overflow', (
      tester,
    ) async {
      const size = Size(390, 844);
      final phoneTypo = PipMeterTypography.forSize(size, compact: true);
      expect(phoneTypo.primarySize, 34);
      expect(phoneTypo.titleSize, 14);
      expect(phoneTypo.metricSize, 16);
      expect(phoneTypo.frameWidth, 0);

      await _pumpMeter(tester, size: size, model: activeModel);
      expect(tester.takeException(), isNull);
      expect(find.text('€14,25'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
    });

    testWidgets('increased text scale does not overflow tablet card', (
      tester,
    ) async {
      const size = Size(800, 1280);
      await _pumpMeter(
        tester,
        size: size,
        model: activeModel,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('To destination'), findsOneWidget);
    });
  });

  group('live values + language handoff', () {
    testWidgets('notifier updates keep PiP values live', (tester) async {
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
      notifier.publish(
        _snap(fare: '€ 16,25', km: '4.7 km', duration: '00:10:15'),
      );
      await tester.pump();
      expect(find.text('€ 16,25'), findsOneWidget);
      expect(find.text('€ 7,00'), findsNothing);
      notifier.dispose();
    });

    testWidgets('pickup → destination phase transition updates title', (
      tester,
    ) async {
      var phase = ExternalNavPhase.toPickup;
      late void Function(void Function()) setPhaseState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setPhaseState = setState;
              return ExternalNavPipMeterCard(
                model: buildExternalNavPipMeterModelFromRideMeters(
                  snapshot: _snap(
                    eta: phase == ExternalNavPhase.toPickup ? '6 min' : '',
                    remaining: '2.0 km',
                    fare: '€ 0,00',
                    duration: '00:00:00',
                  ),
                  phase: phase,
                  isStreetRide: true,
                  isFixedPrice: false,
                  language: AppLanguage.en,
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('To pickup'), findsOneWidget);
      expect(find.text('ETA'), findsOneWidget);

      setPhaseState(() => phase = ExternalNavPhase.activeRide);
      await tester.pump();
      expect(find.text('To destination'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets('app language change rebuilds overlay chrome', (tester) async {
      final previous = appLanguageNotifier.value;
      addTearDown(() => appLanguageNotifier.value = previous);
      appLanguageNotifier.value = AppLanguage.nl;

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<AppLanguage>(
            valueListenable: appLanguageNotifier,
            builder: (context, lang, _) {
              return ExternalNavPipMeterCard(
                model: buildExternalNavPipMeterModelFromRideMeters(
                  snapshot: _snap(fare: '€ 8,00', km: '1.0 km'),
                  phase: ExternalNavPhase.activeRide,
                  isStreetRide: true,
                  isFixedPrice: false,
                  language: lang,
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Naar bestemming'), findsOneWidget);
      expect(find.text('Afstand'), findsOneWidget);

      appLanguageNotifier.value = AppLanguage.fr;
      await tester.pump();
      expect(find.text('Vers la destination'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Naar bestemming'), findsNothing);
    });
  });

  group('source contract — driver home PiP locale wiring', () {
    late String homeSource;
    late String meterSource;

    setUpAll(() {
      homeSource = _read('lib/main_parts/driver_home_page_state.dart');
      meterSource = _read(
        'lib/navigation/external/external_navigation_pip_meter.dart',
      );
    });

    test('PiP listens to appLanguageNotifier and meter notifier', () {
      expect(homeSource, contains('PIP-TABLET-READABILITY-LOCALE-P1'));
      expect(homeSource, contains('ValueListenableBuilder<AppLanguage>'));
      expect(homeSource, contains('valueListenable: appLanguageNotifier'));
      expect(homeSource, contains('ValueListenableBuilder<DriverRideMetersSnapshot>'));
      expect(homeSource, contains('valueListenable: _driverRideMetersNotifier'));
      expect(homeSource, contains('language: language ?? appConfig.currentLanguage'));
    });

    test('meter source owns localized strings (no scattered Dutch literals only)', () {
      expect(meterSource, contains('pipMeterToPickupTitle'));
      expect(meterSource, contains('To pickup'));
      expect(meterSource, contains('Vers le lieu de prise en charge'));
      expect(meterSource, contains('Hacia el punto de recogida'));
      expect(meterSource, contains('normalizePipMeterLanguageCode'));
      // Builder no longer hard-codes Dutch titles as bare string literals.
      expect(
        meterSource.contains("title: 'Naar ophaalpunt'"),
        isFalse,
      );
      expect(
        meterSource.contains("title: 'Naar bestemming'"),
        isFalse,
      );
    });
  });
}
