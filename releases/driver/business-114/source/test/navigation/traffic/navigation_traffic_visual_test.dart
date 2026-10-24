import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_banner.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_controller.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_traffic_model.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';
import 'traffic_fixtures.dart';

const reviewRoute = [
  DriverLonLat(4.4, 51.2),
  DriverLonLat(4.404, 51.202),
  DriverLonLat(4.408, 51.2),
  DriverLonLat(4.412, 51.205),
];

class _ReviewMap extends CustomPainter {
  _ReviewMap(this.spans);
  final List<NavigationTrafficSpan> spans;
  Offset position(DriverLonLat p, Size size) => Offset(
    28 + (p.lon - 4.4) / .012 * (size.width - 56),
    size.height - 70 - (p.lat - 51.2) / .005 * (size.height - 125),
  );
  Path path(List<DriverLonLat> points, Size size) {
    final result = Path();
    final first = position(points.first, size);
    result.moveTo(first.dx, first.dy);
    for (final point in points.skip(1)) {
      final p = position(point, size);
      result.lineTo(p.dx, p.dy);
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9EEE9),
    );
    final road = Paint()
      ..color = const Color(0xFFD0D9D2)
      ..strokeWidth = 7;
    for (var x = 30.0; x < size.width; x += 75) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
    for (var y = 30.0; y < size.height; y += 80) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      path(reviewRoute, size),
      line
        ..color = const Color(0xCC0F172A)
        ..strokeWidth = 14.5,
    );
    canvas.drawPath(
      path(reviewRoute, size),
      line
        ..color = const Color(0xFF2B6CB0)
        ..strokeWidth = 11,
    );
    for (final span in spans) {
      canvas.drawPath(
        path(span.coordinates, size),
        line
          ..color = Color(span.color)
          ..strokeWidth = span.traffic == NavigationTrafficClass.closed
              ? 13
              : 11,
      );
    }
    final start = position(reviewRoute.first, size),
        finish = position(reviewRoute.last, size);
    canvas.drawCircle(start, 10, Paint()..color = Colors.white);
    canvas.drawCircle(start, 6, Paint()..color = const Color(0xFF111827));
    canvas.drawCircle(finish, 8, Paint()..color = const Color(0xFFE5B641));
  }

  @override
  bool shouldRepaint(covariant _ReviewMap oldDelegate) =>
      !identical(spans, oldDelegate.spans);
}

Widget reviewScene(
  NavigationTrafficController controller,
  ValueNotifier<DriverThemeVariant> theme, {
  bool isTablet = false,
}) {
  final presentation = buildResponsiveManeuverPresentation(
    snapshot: const NavInstructionSnapshot(
      distanceToManeuverMeters: 400,
      primaryText: 'Rechtsaf',
      secondaryText: 'Stationsstraat',
      maneuverType: 'turn',
      maneuverModifier: 'right',
      roadName: 'Stationsstraat',
      isHighwayLike: false,
      lanes: [],
      source: NavInstructionSource.step,
    ),
    tr: ({required nl, required en, required fr, required es}) => nl,
    languageCode: 'nl',
    useCaptionedSign: false,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Roboto'),
    home: Scaffold(
      backgroundColor: const Color(0xFF07080C),
      body: RepaintBoundary(
        key: const Key('traffic-review'),
        child: Column(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              color: const Color(0xFF07080C),
              alignment: Alignment.centerLeft,
              child: Image.asset(
                'assets/fluxidi/fluxidi_logo_horizontal_gold.png',
                width: 150,
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ReviewMap(controller.spansAt(trafficNow)),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: NavigationTrafficBannerHost(
                      alertListenable: controller.alert,
                      themeListenable: theme,
                      languageCode: 'nl',
                      child: DriverTurnInstructionBanner(
                        themeListenable: theme,
                        compact: !isTablet,
                        isTablet: isTablet,
                        topRowLandscape: false,
                        isArrival: false,
                        isHighwayLike: false,
                        distancePrefix: 'Over',
                        distanceText: '400 m',
                        primaryText: 'Rechtsaf',
                        secondaryText: 'Stationsstraat',
                        icon: Icons.turn_right,
                        lanes: const [],
                        maneuverModifier: 'right',
                        presentation: presentation,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 76,
              color: const Color(0xFF101113),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    '10:22',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '12 min',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  Text(
                    '6,8 km',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    // Bundled Flutter fonts; no network or external map service in goldens.
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(
        'C:/dev/flutter/bin/cache/artifacts/material_fonts/${entry.value}',
      );
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
  final scenarios = <String, Map<String, dynamic>?>{
    'normal_route': null,
    'green_orange_red': trafficWire(
      geometry: reviewRoute,
      segments: [
        trafficSegment(start: 0, end: 1, traffic: 'normal', delay: null),
        trafficSegment(start: 1, end: 2, traffic: 'light', delay: null),
        trafficSegment(start: 2, end: 3, traffic: 'heavy', delay: 240),
      ],
    ),
    'traffic_jam': trafficWire(geometry: reviewRoute),
    'closure': trafficWire(
      geometry: reviewRoute,
      segments: [
        trafficSegment(traffic: 'closed', event: 'closure', delay: null),
      ],
    ),
    'stale_fallback': trafficWire(geometry: reviewRoute, state: 'STALE'),
  };
  for (final scenario in scenarios.entries) {
    testWidgets('golden ${scenario.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = NavigationTrafficController();
      final theme = ValueNotifier(DriverThemeVariant.nightGold);
      addTearDown(controller.dispose);
      addTearDown(theme.dispose);
      controller.install(
        geometry: reviewRoute,
        snapshot: decodeFixture(scenario.value, geometry: reviewRoute),
        now: trafficNow,
      );
      controller.updateProgress(0, trusted: true, now: trafficNow);
      await tester.pumpWidget(reviewScene(controller, theme));
      // Wait for the actual visible Image providers (including resized signs),
      // rather than accepting a first frame with empty asset placeholders.
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('traffic-review')),
        matchesGoldenFile('goldens/${scenario.key}.png'),
      );
    });
  }
  testWidgets(
    'fallback returns identical maneuver child and traffic updates do not rebuild the map',
    (tester) async {
      final controller = NavigationTrafficController();
      final theme = ValueNotifier(DriverThemeVariant.nightGold);
      addTearDown(controller.dispose);
      addTearDown(theme.dispose);
      var builds = 0, mapBuilds = 0;
      final child = Builder(
        builder: (_) {
          builds++;
          return const SizedBox(height: 40, child: Text('manoeuvre'));
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (_) {
                    mapBuilds++;
                    return const SizedBox(height: 100);
                  },
                ),
                NavigationTrafficBannerHost(
                  alertListenable: controller.alert,
                  themeListenable: theme,
                  languageCode: 'nl',
                  child: child,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(NavigationTrafficBanner), findsNothing);
      expect(builds, 1);
      expect(mapBuilds, 1);
      controller.install(
        geometry: trafficRoute,
        snapshot: decodeFixture(trafficWire()),
        now: trafficNow,
      );
      controller.updateProgress(0, trusted: true, now: trafficNow);
      await tester.pump();
      expect(find.textContaining('File ·'), findsOneWidget);
      expect(builds, 2);
      expect(mapBuilds, 1);
      controller.updateProgress(120, trusted: true, now: trafficNow);
      await tester.pump();
      expect(builds, 2);
      expect(mapBuilds, 1);
      controller.expire(trafficNow.add(const Duration(minutes: 2)));
      await tester.pump();
      expect(find.byType(NavigationTrafficBanner), findsNothing);
      expect(builds, 3);
      expect(mapBuilds, 1);
    },
  );
  for (final width in [220.0, 390.0, 800.0]) {
    for (final language in ['nl', 'en', 'fr', 'es', 'de', 'pt']) {
      testWidgets(
        'compact banner fits width $width language $language at text scale 2',
        (tester) async {
          final theme = ValueNotifier(DriverThemeVariant.nightGold);
          addTearDown(theme.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: NavigationTrafficBanner(
                      alert: const NavigationTrafficAlert(
                        event: NavigationTrafficEvent.roadworks,
                        traffic: NavigationTrafficClass.light,
                        distanceMeters: 2300,
                        delaySeconds: 240,
                      ),
                      themeListenable: theme,
                      languageCode: language,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byType(RichText).last,
          );
          expect(paragraph.didExceedMaxLines, isFalse);
        },
      );
    }
  }
  test('normal traffic uses the existing blue route color', () {
    expect(navigationTrafficColor(NavigationTrafficClass.normal), 0xFF2B6CB0);
  });
  for (final width in [390.0, 800.0]) {
    testWidgets('traffic pill hugs readable content at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = ValueNotifier(DriverThemeVariant.nightGold);
      addTearDown(theme.dispose);
      final alert = ValueNotifier<NavigationTrafficAlert?>(
        const NavigationTrafficAlert(
          event: NavigationTrafficEvent.congestion,
          traffic: NavigationTrafficClass.light,
          distanceMeters: 400,
          delaySeconds: 120,
        ),
      );
      addTearDown(alert.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: NavigationTrafficBannerHost(
                alertListenable: alert,
                themeListenable: theme,
                languageCode: 'nl',
                child: const SizedBox(height: 40, child: Text('manoeuvre')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationTrafficBanner), findsOneWidget);
      expect(find.text('Druk verkeer · 400 m · +2 min'), findsOneWidget);
      final pill = tester.getSize(
        find.byKey(const Key('navigation-traffic-pill')),
      );
      expect(pill.width, lessThan(360));
      expect(pill.width, lessThan(width * .9));
      expect(pill.height, lessThan(32));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText).last,
      );
      expect(paragraph.didExceedMaxLines, isFalse);
    });
  }
}
