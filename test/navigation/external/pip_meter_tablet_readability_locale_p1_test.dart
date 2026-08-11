// PIP-TABLET-READABILITY-LOCALE-P1
// PIP-TABLET-KPI-DENSITY-P1
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
  String speed = '',
}) {
  return DriverRideMetersSnapshot(
    fareText: fare,
    distanceTravelledText: km,
    rideDurationText: duration,
    waitingTimeText: wait,
    statusText: 'Rit actief',
    etaText: eta,
    remainingDistanceText: remaining,
    speedText: speed,
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

    test('speed unit follows language (nl km/u, others km/h)', () {
      expect(formatPipMeterSpeedKmh(50, AppLanguage.nl), '50 km/u');
      expect(formatPipMeterSpeedKmh(50, AppLanguage.en), '50 km/h');
      expect(formatPipMeterSpeedKmh(null, AppLanguage.en), '—');
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
        String ride,
      })>{
        AppLanguage.nl: (
          pickup: 'Naar ophaalpunt',
          dest: 'Naar bestemming',
          distance: 'Afstand',
          time: 'Tijd',
          price: 'Prijs',
          live: 'Actueel',
          ride: 'Ritduur',
        ),
        AppLanguage.en: (
          pickup: 'To pickup point',
          dest: 'To destination',
          distance: 'Distance',
          time: 'Time',
          price: 'Fare',
          live: 'Current',
          ride: 'Ride time',
        ),
        AppLanguage.fr: (
          pickup: 'Vers le lieu de prise en charge',
          dest: 'Vers la destination',
          distance: 'Distance',
          time: 'Temps',
          price: 'Prix',
          live: 'Actuel',
          ride: 'Durée',
        ),
        AppLanguage.es: (
          pickup: 'Hacia el punto de recogida',
          dest: 'Hacia el destino',
          distance: 'Distancia',
          time: 'Tiempo',
          price: 'Precio',
          live: 'Actual',
          ride: 'Duración',
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
          speedText: formatPipMeterSpeedKmh(40, lang),
          liveFareText: '€18,40',
          durationText: '00:28:00',
        );
        expect(pickup.title, expect_.pickup, reason: '$lang pickup title');
        expect(pickup.primaryMetrics.length, 2);
        expect(pickup.primaryMetrics[0].label, expect_.distance);
        expect(pickup.primaryMetrics[0].value, '1.2 km');
        expect(pickup.primaryMetrics[1].label, expect_.time);
        expect(pickup.primaryMetrics[1].value, '5 min');
        expect(pickup.secondaryMetrics.length, 3);
        expect(pickup.secondaryMetrics[0].label, expect_.live);
        expect(pickup.secondaryMetrics[1].label, expect_.price);
        expect(pickup.secondaryMetrics[2].label, expect_.ride);

        final fixed = buildExternalNavPipMeterModel(
          phase: ExternalNavPhase.activeRide,
          isStreetRide: false,
          isFixedPrice: true,
          language: lang,
          fixedPriceText: '€20,00',
          remainingDistanceText: '3.0 km',
          etaText: '8 min',
          durationText: '00:10:00',
          speedText: formatPipMeterSpeedKmh(50, lang),
        );
        expect(fixed.title, expect_.dest, reason: '$lang dest title');
        expect(fixed.primaryLabel, expect_.price);
        expect(fixed.primaryMetrics[0].label, expect_.distance);
        expect(fixed.primaryMetrics[1].label, expect_.time);
        expect(fixed.secondaryMetrics[1].value, '€20,00');
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
      expect(m.title, 'To pickup point');
      expect(m.title, isNot(contains('Naar')));
      expect(m.primaryMetrics[0].label, 'Distance');
      expect(m.primaryMetrics[0].label, isNot('Afstand'));
    });

    test('unknown primary renders em dash, not false zero', () {
      final m = buildExternalNavPipMeterModel(
        phase: ExternalNavPhase.toPickup,
        isStreetRide: false,
        isFixedPrice: false,
        language: AppLanguage.en,
      );
      expect(m.primaryValue, '—');
      expect(m.primaryMetrics[0].value, '—');
      expect(m.primaryMetrics[1].value, '—');
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
        remainingDistanceText: '1.5 km',
        durationText: '00:07:30',
        etaText: '3 min',
        speedText: '45 km/u',
      );
      final distance =
          m.primaryMetrics.firstWhere((e) => e.label == 'Afstand');
      final time = m.primaryMetrics.firstWhere((e) => e.label == 'Tijd');
      final ride =
          m.secondaryMetrics.firstWhere((e) => e.label == 'Ritduur');
      expect(distance.value, '1.5 km');
      expect(time.value, '3 min');
      expect(ride.value, '00:07:30');
      expect(distance.value, isNot('00:07:30'));
      expect(distance.value, isNot('3 min'));
      expect(time.value, isNot('1.5 km'));
    });
  });

  group('PiP window shrink must not flip tablet → phone', () {
    test('resolvePipMeterHostIsTablet prefers latch/device over tiny window', () {
      const pipWindow = Size(352, 198); // typical 16:9 PiP on SM-X400
      const device = Size(880, 1408); // fullscreen logical class
      expect(pipWindow.shortestSide, lessThan(600));
      expect(device.shortestSide, greaterThanOrEqualTo(600));

      expect(
        resolvePipMeterHostIsTablet(
          latchedHostIsTablet: true,
          deviceSize: device,
          windowSize: pipWindow,
        ),
        isTrue,
      );
      expect(
        resolvePipMeterHostIsTablet(
          deviceSize: device,
          windowSize: pipWindow,
        ),
        isTrue,
      );
      // Window-only fallback (unit tests) — tiny PiP alone is phone.
      expect(
        resolvePipMeterHostIsTablet(windowSize: pipWindow),
        isFalse,
      );
    });

    test('tablet typography stays tablet after PiP-sized window', () {
      final fullscreen = PipMeterTypography.forSize(
        const Size(800, 1280),
        compact: true,
        hostIsTablet: true,
      );
      final pipWindow = PipMeterTypography.forSize(
        const Size(352, 198),
        compact: true,
        hostIsTablet: true,
      );
      expect(fullscreen.isTablet, isTrue);
      expect(pipWindow.isTablet, isTrue);
      expect(pipWindow.primaryValueSize, greaterThan(30));
      expect(pipWindow.frameWidth, greaterThan(0));
      // Phone path must remain distinct when host is not tablet.
      final phonePip = PipMeterTypography.forSize(
        const Size(352, 198),
        compact: true,
        hostIsTablet: false,
      );
      expect(phonePip.isTablet, isFalse);
      expect(phonePip.primarySize, 34);
      expect(phonePip.frameWidth, 0);
    });

    testWidgets(
      'first large frame then PiP shrink keeps tablet taxi-meter body',
      (tester) async {
        final model = buildExternalNavPipMeterModel(
          phase: ExternalNavPhase.activeRide,
          isStreetRide: true,
          isFixedPrice: false,
          language: AppLanguage.en,
          liveFareText: '€14,25',
          remainingDistanceText: '4.1 km',
          etaText: '11 min',
          durationText: '00:11:00',
          speedText: '50 km/h',
        );

        // Frame 1: fullscreen tablet (pre-PiP / transitional).
        await _pumpMeter(
          tester,
          size: const Size(800, 1280),
          model: model,
        );
        expect(find.text('Distance'), findsOneWidget);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Ride time'), findsOneWidget);

        // Frame 2: PiP window shrink — same latched hostIsTablet=true.
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(352, 198)),
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 352,
                  height: 198,
                  child: ExternalNavPipMeterCard(
                    model: model,
                    hostIsTablet: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Still taxi-meter columns — NOT the phone compact-only presentation.
        expect(find.text('Distance'), findsOneWidget);
        expect(find.text('Time'), findsOneWidget);
        expect(find.text('Current'), findsOneWidget);
        expect(find.text('Fare'), findsOneWidget);
        expect(find.text('Ride time'), findsOneWidget);
        final typo = PipMeterTypography.forSize(
          const Size(352, 198),
          compact: true,
          hostIsTablet: true,
        );
        expect(typo.isTablet, isTrue);
      },
    );
  });

  group('responsive layout', () {
    final activeModel = buildExternalNavPipMeterModel(
      phase: ExternalNavPhase.activeRide,
      isStreetRide: true,
      isFixedPrice: false,
      language: AppLanguage.en,
      liveFareText: '€14,25',
      remainingDistanceText: '4.1 km',
      etaText: '11 min',
      durationText: '00:11:00',
      speedText: '50 km/h',
    );

    testWidgets('tablet portrait: taxi-meter hierarchy fills width', (
      tester,
    ) async {
      const size = Size(800, 1280);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: size),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: ExternalNavPipMeterCard(
                  model: activeModel,
                  hostIsTablet: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('To destination'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('4.1 km'), findsOneWidget);
      expect(find.text('11 min'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Fare'), findsOneWidget);
      expect(find.text('Ride time'), findsOneWidget);
      expect(find.text('€14,25'), findsOneWidget);
      expect(find.text('50 km/h'), findsOneWidget);
      expect(find.text('00:11:00'), findsOneWidget);

      final typo = PipMeterTypography.forSize(
        size,
        compact: true,
        hostIsTablet: true,
      );
      expect(typo.isTablet, isTrue);
      expect(typo.titleSize, inInclusiveRange(28, 32));
      expect(typo.primaryValueSize, inInclusiveRange(44, 52));
      expect(typo.primaryLabelSize, inInclusiveRange(20, 24));
      expect(typo.secondaryValueSize, inInclusiveRange(32, 40));
      expect(typo.secondaryLabelSize, inInclusiveRange(18, 22));
      expect(typo.horizontalPadding, inInclusiveRange(20, 28));
      expect(typo.verticalPadding, lessThanOrEqualTo(18));

      // Content uses nearly full card width (not a tiny centered cluster).
      final distance = tester.getRect(find.text('Distance'));
      final time = tester.getRect(find.text('Time'));
      expect(distance.left, lessThan(size.width * 0.35));
      expect(time.right, greaterThan(size.width * 0.65));
      expect(time.left - distance.right, greaterThan(40));
    });

    testWidgets('tablet landscape: large hierarchy, no overflow', (
      tester,
    ) async {
      const size = Size(1280, 800);
      await _pumpMeter(tester, size: size, model: activeModel);
      expect(tester.takeException(), isNull);
      final typo = PipMeterTypography.forSize(size, compact: true);
      expect(typo.primaryValueSize, inInclusiveRange(44, 52));
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
      expect(phoneTypo.horizontalPadding, 12);
      expect(phoneTypo.isTablet, isFalse);

      await _pumpMeter(tester, size: size, model: activeModel);
      expect(tester.takeException(), isNull);
      // Phone keeps compact yellow primary fare presentation.
      expect(find.text('€14,25'), findsOneWidget);
      expect(find.text('Fare'), findsOneWidget);
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

      expect(find.text('To pickup point'), findsOneWidget);

      setPhaseState(() => phase = ExternalNavPhase.activeRide);
      await tester.pump();
      expect(find.text('To destination'), findsOneWidget);
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
                  snapshot: _snap(
                    fare: '€ 8,00',
                    remaining: '1.0 km',
                    eta: '4 min',
                    speed: '30 km/u',
                  ),
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
      expect(homeSource, contains('formatPipMeterSpeedKmh'));
    });

    test('meter source owns tablet taxi-meter density layout', () {
      expect(meterSource, contains('PIP-TABLET-KPI-DENSITY-P1'));
      expect(meterSource, contains('PIP-TABLET-FORM-FACTOR-STABLE-P1'));
      expect(meterSource, contains('_TabletTaxiMeterBody'));
      expect(meterSource, contains('_PhonePipMeterBody'));
      expect(meterSource, contains('primaryMetrics'));
      expect(meterSource, contains('secondaryMetrics'));
      expect(meterSource, contains('pipMeterDeviceLogicalSizeOf'));
      expect(meterSource, contains('resolvePipMeterHostIsTablet'));
      expect(meterSource, contains('To pickup point'));
      expect(
        meterSource.contains("title: 'Naar ophaalpunt'"),
        isFalse,
      );
    });

    test('driver home latches hostIsTablet before PiP and passes it to card', () {
      expect(homeSource, contains('PIP-TABLET-FORM-FACTOR-STABLE-P1'));
      expect(homeSource, contains('hostIsTablet: hostIsTablet'));
      expect(homeSource, contains('hostIsTablet:'));
      expect(
        homeSource,
        contains('_externalNavigationSession?.hostIsTablet'),
      );
    });
  });
}
