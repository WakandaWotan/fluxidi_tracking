// NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1
//
// The maneuver banner had no width contract at all: it consumed whatever
// horizontal constraint its parent handed down, so a two-word instruction
// ("Over 643 m linksaf" / "naar N454") still painted a near-full-width dark
// bar across the top of the map. On a tablet that hides far more road than the
// instruction is worth.
//
// These tests pin the new contract: the card hugs its content and may grow
// only up to a form-factor maximum — even when the parent forces full width,
// which is exactly what production does (landscape `Expanded`, portrait
// `CrossAxisAlignment.stretch`).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_tablet_portrait_nav_layout.dart';
import 'package:fluxidi_tracking/widgets/driver_nav_banners.dart';

typedef _Form = ({
  String name,
  Size size,
  bool isTablet,
  bool compact,
  bool topRowLandscape,
  // The ceiling the product rule mandates for this form factor.
  double requiredMaxFraction,
});

const _Form _phonePortrait = (
  name: 'phone portrait',
  size: Size(390, 844),
  isTablet: false,
  compact: false,
  topRowLandscape: false,
  requiredMaxFraction: 0.94,
);

const _Form _phoneLandscape = (
  name: 'phone landscape',
  size: Size(844, 390),
  isTablet: false,
  compact: true,
  topRowLandscape: true,
  requiredMaxFraction: 0.78,
);

const _Form _tabletPortrait = (
  name: 'tablet portrait',
  size: Size(834, 1194),
  isTablet: true,
  compact: false,
  topRowLandscape: false,
  requiredMaxFraction: 0.82,
);

const _Form _tabletLandscape = (
  name: 'tablet landscape',
  size: Size(1194, 834),
  isTablet: true,
  compact: true,
  topRowLandscape: true,
  requiredMaxFraction: 0.65,
);

const List<_Form> _allForms = <_Form>[
  _phonePortrait,
  _phoneLandscape,
  _tabletPortrait,
  _tabletLandscape,
];

String _trNl({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => nl;

NavInstructionSnapshot _snap({
  required double distance,
  String type = 'turn',
  String modifier = '',
  String primary = '',
  String secondary = '',
  String roadName = '',
  String? roadRef,
  String? exitNumber,
  List<DriverNavLaneGuidance> lanes = const <DriverNavLaneGuidance>[],
}) {
  return NavInstructionSnapshot(
    distanceToManeuverMeters: distance,
    primaryText: primary,
    secondaryText: secondary,
    maneuverType: type,
    maneuverModifier: modifier,
    roadName: roadName,
    exitNumber: exitNumber,
    roadRef: roadRef,
    isHighwayLike: false,
    lanes: lanes,
    source: NavInstructionSource.banner,
  );
}

ResponsiveManeuverPresentation _build(NavInstructionSnapshot snap) =>
    buildResponsiveManeuverPresentation(snapshot: snap, tr: _trNl);

/// The field case: a short instruction that used to fill the whole width.
ResponsiveManeuverPresentation get _shortTurn => _build(
  _snap(distance: 643, modifier: 'left', primary: 'Turn left', roadRef: 'N454'),
);

ResponsiveManeuverPresentation get _longTurn => _build(
  _snap(
    distance: 643,
    modifier: 'left',
    primary: 'Turn left',
    roadRef:
        'Rijksweg N454 richting Koekamerstraat Zuid / Autoroute direction '
        'Centre-Ville Zonnestraat Noordwijkerhoutseweg',
  ),
);

DriverTurnInstructionBanner _banner(
  ResponsiveManeuverPresentation p, {
  required _Form form,
  List<DriverNavLaneGuidance> lanes = const <DriverNavLaneGuidance>[],
  DriverNavBannerPortraitTabletLayout? metrics,
}) {
  return DriverTurnInstructionBanner(
    compact: form.compact,
    isTablet: form.isTablet,
    topRowLandscape: form.topRowLandscape,
    isArrival: p.isArrival,
    isHighwayLike: p.isHighwayLike,
    distancePrefix: '',
    distanceText: p.distanceLabel,
    primaryText: p.primaryInstruction,
    secondaryText: p.secondaryInstruction,
    icon: driverManeuverVisualIconData(p.maneuverVisual),
    lanes: lanes,
    presentation: p,
    portraitTabletMetrics: metrics,
  );
}

/// Deliberately hostile host: a **tight, full-viewport-width** parent inside a
/// stretching column — precisely what `_wrapNavBannerWithComplexityCaution`
/// and the landscape top row hand the banner in production. If the banner did
/// not own its width, every measurement below would equal the viewport width.
Widget _wrap(List<Widget> children, {required Size size}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<Widget> children, {
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(_wrap(children, size: size));
  await tester.pump();
}

Finder get _bannerFinder =>
    find.byKey(const ValueKey<String>('nav_maneuver_banner'));

Finder get _cautionFinder =>
    find.byKey(const ValueKey<String>('nav_complexity_caution_banner'));

double _bannerWidth(WidgetTester tester) {
  expect(_bannerFinder, findsOneWidget);
  return tester.getSize(_bannerFinder).width;
}

double _capFor(_Form form) => DriverNavBannerWidthPolicy.maxWidthFor(
  viewportWidth: form.size.width,
  isTablet: form.isTablet,
  isLandscape: form.compact,
);

double _maxIconGlyph(WidgetTester tester) => tester
    .widgetList<Icon>(find.byType(Icon))
    .map((i) => i.size ?? 0)
    .reduce((a, b) => a > b ? a : b);

List<DriverNavLaneGuidance> _lanes(int count) {
  return List<DriverNavLaneGuidance>.generate(
    count,
    (i) => DriverNavLaneGuidance(
      indications: <String>[i == 0 ? 'left' : 'straight'],
      valid: i == 0,
      active: i == 0,
    ),
  );
}

void main() {
  setUpAll(() {
    driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
  });

  tearDown(() {
    debugDriverNavLaneGuidanceOverride = null;
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 width policy', () {
    test('every form-factor fraction sits inside the mandated range', () {
      // Phone portrait 92–94%, phone landscape 72–78%,
      // tablet portrait 75–82%, tablet landscape 55–65%.
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: false,
          isLandscape: false,
        ),
        inInclusiveRange(0.92, 0.94),
      );
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: false,
          isLandscape: true,
        ),
        inInclusiveRange(0.72, 0.78),
      );
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: true,
          isLandscape: false,
        ),
        inInclusiveRange(0.75, 0.82),
      );
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: true,
          isLandscape: true,
        ),
        inInclusiveRange(0.55, 0.65),
      );
    });

    test('landscape is always tighter than portrait — map height is scarcest '
        'there', () {
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: false,
          isLandscape: true,
        ),
        lessThan(
          DriverNavBannerWidthPolicy.fractionFor(
            isTablet: false,
            isLandscape: false,
          ),
        ),
      );
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: true,
          isLandscape: true,
        ),
        lessThan(
          DriverNavBannerWidthPolicy.fractionFor(
            isTablet: true,
            isLandscape: false,
          ),
        ),
      );
      // A tablet never gives the banner a larger share than a phone: the
      // bigger the screen, the more map the driver should keep.
      expect(
        DriverNavBannerWidthPolicy.fractionFor(
          isTablet: true,
          isLandscape: false,
        ),
        lessThan(
          DriverNavBannerWidthPolicy.fractionFor(
            isTablet: false,
            isLandscape: false,
          ),
        ),
      );
    });

    test('absolute ceiling caps very wide displays', () {
      expect(
        DriverNavBannerWidthPolicy.maxWidthFor(
          viewportWidth: 4000,
          isTablet: true,
          isLandscape: false,
        ),
        DriverNavBannerWidthPolicy.tabletAbsoluteMax,
      );
      expect(
        DriverNavBannerWidthPolicy.maxWidthFor(
          viewportWidth: 4000,
          isTablet: false,
          isLandscape: false,
        ),
        DriverNavBannerWidthPolicy.phoneAbsoluteMax,
      );
    });

    test('degenerate viewport width degrades to the absolute ceiling, never '
        'to a full-bleed bar', () {
      for (final w in <double>[0, -1, double.nan, double.infinity]) {
        expect(
          DriverNavBannerWidthPolicy.maxWidthFor(
            viewportWidth: w,
            isTablet: false,
            isLandscape: false,
          ),
          DriverNavBannerWidthPolicy.phoneAbsoluteMax,
          reason: 'viewportWidth=$w must not disable the cap',
        );
      }
    });

    test('constraints are always satisfiable, even on a tiny viewport', () {
      for (final w in <double>[80, 120, 240, 390, 834, 1194]) {
        for (final tablet in <bool>[false, true]) {
          final c = DriverNavBannerWidthPolicy.constraintsFor(
            viewportWidth: w,
            isTablet: tablet,
            isLandscape: false,
          );
          expect(
            c.minWidth,
            lessThanOrEqualTo(c.maxWidth),
            reason: 'minWidth must never exceed maxWidth (w=$w)',
          );
          expect(c.maxWidth, greaterThan(0));
        }
      }
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 short instruction', () {
    for (final form in _allForms) {
      testWidgets(
        '${form.name}: short instruction stays within '
        '${(form.requiredMaxFraction * 100).round()}% of the viewport',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await _pump(
            tester,
            [
              _banner(
                _shortTurn,
                form: form,
                metrics: form == _tabletPortrait
                    ? kDriverNavBannerPortraitTabletLayout
                    : null,
              ),
            ],
            size: form.size,
          );

          final width = _bannerWidth(tester);
          expect(
            width,
            lessThanOrEqualTo(form.size.width * form.requiredMaxFraction),
            reason:
                '${form.name} banner is ${width.toStringAsFixed(1)} of '
                '${form.size.width} — over the mandated ceiling',
          );
          // And it never even reaches its own cap for short content.
          expect(width, lessThanOrEqualTo(_capFor(form) + 0.5));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('tablet: short instruction leaves materially more map visible '
        'than the old full-width bar', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        [
          _banner(
            _shortTurn,
            form: _tabletPortrait,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ],
        size: _tabletPortrait.size,
      );

      final width = _bannerWidth(tester);
      final cap = _capFor(_tabletPortrait);
      // Genuinely content-aware: comfortably short of its own maximum, not
      // merely clipped at the cap.
      expect(
        width,
        lessThan(cap - 60),
        reason: 'short content must not saturate the maximum width',
      );
      // Before this commit the card spanned essentially the full tablet width.
      expect(
        width / _tabletPortrait.size.width,
        lessThan(0.70),
        reason: 'a two-word instruction must not dominate a tablet',
      );
    });

    testWidgets('a parent narrower than the cap still wins — the banner never '
        'overflows its host', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const size = Size(834, 1194);
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: size),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: size),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  // Far narrower than the 0.76 tablet-portrait cap.
                  width: 300,
                  child: _banner(_longTurn, form: _tabletPortrait),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_bannerWidth(tester), lessThanOrEqualTo(300));
      expect(tester.takeException(), isNull);
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 long instruction', () {
    for (final form in _allForms) {
      testWidgets(
        '${form.name}: long text grows to the maximum and stops there',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final metrics = form == _tabletPortrait
              ? kDriverNavBannerPortraitTabletLayout
              : null;

          await _pump(
            tester,
            [_banner(_shortTurn, form: form, metrics: metrics)],
            size: form.size,
          );
          final shortWidth = _bannerWidth(tester);

          await _pump(
            tester,
            [_banner(_longTurn, form: form, metrics: metrics)],
            size: form.size,
          );
          final longWidth = _bannerWidth(tester);

          expect(
            longWidth,
            greaterThanOrEqualTo(shortWidth),
            reason: 'long text must be allowed to use at least as much width',
          );
          // It reaches the maximum...
          expect(
            longWidth,
            closeTo(_capFor(form), 1.0),
            reason: 'long text must be allowed to use the whole maximum',
          );
          // ...and stops exactly there.
          expect(
            longWidth,
            lessThanOrEqualTo(form.size.width * form.requiredMaxFraction),
            reason: 'but never beyond the form-factor maximum',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('where the viewport leaves headroom, longer text genuinely '
        'widens the card', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Tablet portrait is the form factor with real slack, so it is the one
      // that can prove growth rather than saturation.
      const form = _tabletPortrait;
      await _pump(
        tester,
        [
          _banner(
            _shortTurn,
            form: form,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ],
        size: form.size,
      );
      final shortWidth = _bannerWidth(tester);

      await _pump(
        tester,
        [
          _banner(
            _longTurn,
            form: form,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ],
        size: form.size,
      );
      final longWidth = _bannerWidth(tester);

      expect(longWidth, greaterThan(shortWidth));
      expect(longWidth, closeTo(_capFor(form), 1.0));
    });

    testWidgets('primary and secondary text ellipsize instead of overflowing', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final form in _allForms) {
        await _pump(
          tester,
          [_banner(_longTurn, form: form)],
          size: form.size,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${form.name}',
        );
        final texts = tester.widgetList<Text>(find.byType(Text));
        expect(texts, isNotEmpty);
        for (final t in texts) {
          expect(
            t.overflow,
            TextOverflow.ellipsis,
            reason: '${form.name}: every banner Text must be ellipsis-safe',
          );
          expect(t.maxLines, isNotNull);
          expect(t.maxLines, lessThanOrEqualTo(2));
        }
      }
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 preserved content', () {
    testWidgets('maneuver icon glyph sizes are unchanged on every form factor',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Exactly the pre-existing `_iconSize` ladder — narrowing the card must
      // not shrink the glyph the driver reads at a glance.
      final expected = <_Form, double>{
        _phonePortrait: 31,
        _phoneLandscape: 20,
        _tabletPortrait: 42,
        _tabletLandscape: 22,
      };
      for (final entry in expected.entries) {
        await _pump(
          tester,
          [_banner(_shortTurn, form: entry.key)],
          size: entry.key.size,
        );
        expect(
          _maxIconGlyph(tester),
          entry.value,
          reason: '${entry.key.name} icon glyph changed',
        );
      }

      // Tablet portrait polish metrics still win when supplied.
      await _pump(
        tester,
        [
          _banner(
            _shortTurn,
            form: _tabletPortrait,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ],
        size: _tabletPortrait.size,
      );
      expect(
        _maxIconGlyph(tester),
        kDriverNavBannerPortraitTabletLayout.iconSize,
      );
    });

    testWidgets('roundabout instruction keeps its exit number and still fits', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final p = _build(
        _snap(
          distance: 643,
          type: 'roundabout',
          primary: 'Take the 2nd exit',
          exitNumber: '2',
          roadRef: 'N454',
        ),
      );
      for (final form in <_Form>[_phonePortrait, _tabletPortrait]) {
        await _pump(tester, [_banner(p, form: form)], size: form.size);
        expect(find.textContaining('afslag'), findsOneWidget);
        expect(
          _bannerWidth(tester),
          lessThanOrEqualTo(form.size.width * form.requiredMaxFraction),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('distance, primary and secondary lines all survive the width '
        'contract', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        [
          _banner(
            _shortTurn,
            form: _tabletPortrait,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ],
        size: _tabletPortrait.size,
      );
      expect(find.textContaining('643'), findsOneWidget);
      expect(find.textContaining('linksaf'), findsOneWidget);
      expect(find.text('naar N454'), findsOneWidget);
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 lane strip', () {
    testWidgets('3 lanes stay attached inside the same card', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugDriverNavLaneGuidanceOverride = true;
      await _pump(
        tester,
        [
          _banner(
            _shortTurn,
            form: _tabletPortrait,
            lanes: _lanes(3),
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
        ],
        size: _tabletPortrait.size,
      );

      // Exactly the resolver output — no padding, no fabricated lanes.
      expect(find.byKey(const ValueKey('nav_lane_column_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_lane_column_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_lane_column_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_lane_column_3')), findsNothing);

      // Still one card: the strip is painted inside the banner, not detached.
      final bannerRect = tester.getRect(_bannerFinder);
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('nav_lane_guidance_strip')),
      );
      expect(bannerRect.top, lessThanOrEqualTo(stripRect.top));
      expect(bannerRect.bottom, greaterThanOrEqualTo(stripRect.bottom));
      expect(bannerRect.left, lessThanOrEqualTo(stripRect.left));
      expect(bannerRect.right, greaterThanOrEqualTo(stripRect.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('6 lanes may widen the card but never past the maximum', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      debugDriverNavLaneGuidanceOverride = true;
      for (final form in _allForms) {
        await _pump(
          tester,
          [_banner(_shortTurn, form: form, lanes: _lanes(6))],
          size: form.size,
        );
        expect(find.byKey(const ValueKey('nav_lane_column_5')), findsOneWidget);
        expect(find.byKey(const ValueKey('nav_lane_column_6')), findsNothing);
        expect(
          _bannerWidth(tester),
          lessThanOrEqualTo(form.size.width * form.requiredMaxFraction),
          reason: '${form.name}: lanes must not fabricate a full-width bar',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow with 6 lanes at ${form.name}',
        );
      }
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 complexity caution', () {
    testWidgets('caution stacks below the banner without overlapping, and '
        'obeys the same width contract', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const form = _tabletPortrait;
      await _pump(
        tester,
        [
          _banner(
            _shortTurn,
            form: form,
            metrics: kDriverNavBannerPortraitTabletLayout,
          ),
          const SizedBox(height: 6),
          const DriverNavComplexityCautionBanner(
            compact: false,
            isTablet: true,
            title: 'Complexe verkeerssituatie',
            body: 'Fluxidi OS is minder zeker. Volg de borden en belijning.',
          ),
        ],
        size: form.size,
      );

      final bannerRect = tester.getRect(_bannerFinder);
      final cautionRect = tester.getRect(_cautionFinder);
      expect(
        bannerRect.bottom,
        lessThanOrEqualTo(cautionRect.top),
        reason: 'caution must never overlap the maneuver card',
      );
      // Both cards share the same ceiling, so the stack reads as one column
      // rather than a compact card above a full-width bar.
      final ceiling = form.size.width * form.requiredMaxFraction;
      expect(bannerRect.width, lessThanOrEqualTo(ceiling));
      expect(cautionRect.width, lessThanOrEqualTo(ceiling));
      expect(tester.takeException(), isNull);
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 rotation', () {
    testWidgets('rotating tablet portrait → landscape adopts the landscape '
        'ceiling, never a stale portrait one', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(
        tester,
        [_banner(_longTurn, form: _tabletPortrait)],
        size: _tabletPortrait.size,
      );
      final portraitWidth = _bannerWidth(tester);
      expect(
        portraitWidth,
        lessThanOrEqualTo(_tabletPortrait.size.width * 0.82),
      );

      await _pump(
        tester,
        [_banner(_longTurn, form: _tabletLandscape)],
        size: _tabletLandscape.size,
      );
      final landscapeWidth = _bannerWidth(tester);
      expect(
        landscapeWidth,
        lessThanOrEqualTo(_tabletLandscape.size.width * 0.65),
        reason: 'landscape must not inherit the portrait share',
      );

      // Back to portrait — the constraint must recover, not stay landscape.
      await _pump(
        tester,
        [_banner(_longTurn, form: _tabletPortrait)],
        size: _tabletPortrait.size,
      );
      expect(_bannerWidth(tester), portraitWidth);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone portrait → landscape adopts the landscape ceiling', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        [_banner(_longTurn, form: _phonePortrait)],
        size: _phonePortrait.size,
      );
      expect(_bannerWidth(tester), lessThanOrEqualTo(390 * 0.94));

      await _pump(
        tester,
        [_banner(_longTurn, form: _phoneLandscape)],
        size: _phoneLandscape.size,
      );
      expect(_bannerWidth(tester), lessThanOrEqualTo(844 * 0.78));
      expect(tester.takeException(), isNull);
    });
  });

  group('NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1 scope guard', () {
    test('this visual commit cannot have touched the Mapbox scale bar, '
        'attribution or logo', () {
      final source = File(
        'lib/widgets/driver_nav_banners.dart',
      ).readAsStringSync();
      expect(source.contains('scaleBar'), isFalse);
      expect(source.contains('ScaleBar'), isFalse);
      expect(source.contains('attribution'), isFalse);
      expect(source.contains('logo.updateSettings'), isFalse);
    });

    test('the banner never fabricates a lane count', () {
      final source = File(
        'lib/widgets/driver_nav_banners.dart',
      ).readAsStringSync();
      // Lanes come from the resolver output only — the banner may filter to
      // empty, never pad or generate.
      expect(source.contains('driverNavLanesForBannerDisplay'), isTrue);
      expect(source.contains('List.generate'), isFalse);
      expect(source.contains('List<DriverNavLaneGuidance>.filled'), isFalse);
    });
  });
}
