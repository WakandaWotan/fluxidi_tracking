// PHONE — final Tellers geometry: post-KPI status|selector row + raised
// landscape banner with owned rectangles.

import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_guidance.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';

DriverTellersLayoutGeometry _phone({
  required Size viewport,
  required bool landscape,
  required bool active,
}) {
  return DriverTellersLayoutGeometry.resolve(
    viewportSize: viewport,
    safeTop: landscape ? 16 : 44,
    safeBottom: landscape ? 16 : 34,
    safeLeft: landscape ? 44 : 0,
    safeRight: landscape ? 44 : 0,
    isLandscape: landscape,
    isTablet: false,
    reserveActionBar: true,
    reservePriceSummary: !active,
    reservePhasePill: active,
  );
}

DriverTellersLayoutGeometry _tablet({
  required Size viewport,
  required bool landscape,
}) {
  return DriverTellersLayoutGeometry.resolve(
    viewportSize: viewport,
    safeTop: 24,
    safeBottom: 24,
    safeLeft: 0,
    safeRight: 0,
    isLandscape: landscape,
    isTablet: true,
    reserveActionBar: true,
    reservePriceSummary: true,
  );
}

void main() {
  const port = Size(406.7, 904);
  const land = Size(904, 406.7);

  group('phone portrait post-KPI status|selector row', () {
    test('active: status and selector do not intersect', () {
      final g = _phone(viewport: port, landscape: false, active: true);
      expect(g.statusRect.width, greaterThan(0));
      expect(g.selectorRect.width, greaterThan(0));
      expect(g.statusRect.overlaps(g.selectorRect), isFalse);
      expect(
        g.selectorRect.left - g.statusRect.right,
        greaterThanOrEqualTo(kTellersPhoneStatusSelectorGap - 0.5),
      );
    });

    test('active: selector sits directly below the KPI grid', () {
      final g = _phone(viewport: port, landscape: false, active: true);
      expect(
        g.selectorRect.top,
        closeTo(g.metersPanelRect.bottom + kTellersPhonePostKpiGap, 0.5),
      );
      expect(g.selectorRect.height, closeTo(kTellersPhoneSelectorH, 0.5));
      expect(g.selectorRect.width, closeTo(kTellersPhoneSelectorW, 0.5));
      expect(g.selectorRect.height, greaterThanOrEqualTo(48));
    });

    test('pre-START: selector still owns the post-KPI row (no phase pill)', () {
      final g = _phone(viewport: port, landscape: false, active: false);
      expect(g.statusRect, Rect.zero);
      expect(
        g.selectorRect.top,
        closeTo(g.metersPanelRect.bottom + kTellersPhonePostKpiGap, 0.5),
      );
      expect(g.priceSummaryRect.height, greaterThan(0));
      expect(g.bannerRect, Rect.zero);
    });

    test('bottom controls stay above effective safeBottom + breathing', () {
      final g = _phone(viewport: port, landscape: false, active: true);
      final contentBottom = port.height - 34 - kTellersPhoneBottomBreathing;
      expect(g.controlsRect.bottom, lessThanOrEqualTo(contentBottom + 0.5));
      expect(g.controlsRect.height, closeTo(kTellersPhoneControlsH, 0.5));
      expect(g.controlsRect.overlaps(g.selectorRect), isFalse);
      expect(g.controlsRect.overlaps(g.statusRect), isFalse);
    });
  });

  group('phone landscape owned banner + selector', () {
    test('banner occupies the reserved upper live band', () {
      final g = _phone(viewport: land, landscape: true, active: true);
      expect(g.bannerRect.width, greaterThan(0));
      expect(g.liveWindowRect.contains(g.bannerRect.topLeft), isTrue);
      expect(
        g.bannerRect.top,
        closeTo(g.liveWindowRect.top + kTellersPhoneBannerInset, 0.5),
      );
      expect(
        g.bannerRect.left,
        closeTo(g.liveWindowRect.left + kTellersPhoneBannerInset, 0.5),
      );
      final layout = resolveDriverTellersGuidanceLayout(
        geometry: g,
        selectorVisible: true,
      );
      expect(layout.fits, isTrue);
      expect(layout.top, closeTo(kTellersPhoneBannerInset, 0.5));
      // Prior baseline placed guidance below the live-window selector (~72).
      expect(layout.top, lessThan(40));
    });

    test('banner does not intersect KPI, selector, compass reserve or controls',
        () {
      final g = _phone(viewport: land, landscape: true, active: true);
      expect(g.bannerRect.overlaps(g.metersPanelRect), isFalse);
      expect(g.bannerRect.overlaps(g.selectorRect), isFalse);
      expect(g.bannerRect.overlaps(g.statusRect), isFalse);
      expect(g.bannerRect.overlaps(g.controlsRect), isFalse);
      expect(
        g.bannerRect.right,
        lessThanOrEqualTo(
          g.liveWindowRect.right - kTellersPhoneBannerCompassReserve + 0.5,
        ),
      );
    });

    test('selector owns left post-KPI row; not live top-right', () {
      final g = _phone(viewport: land, landscape: true, active: true);
      expect(g.liveWindowRect.overlaps(g.selectorRect), isFalse);
      expect(
        g.selectorRect.top,
        closeTo(g.metersPanelRect.bottom + kTellersPhonePostKpiGap, 0.5),
      );
      expect(g.statusRect.overlaps(g.selectorRect), isFalse);
    });

    test('pre-START and active both settle valid geometry', () {
      final pre = _phone(viewport: land, landscape: true, active: false);
      final active = _phone(viewport: land, landscape: true, active: true);
      expect(pre.isValid, isTrue);
      expect(active.isValid, isTrue);
      expect(pre.bannerRect.width, greaterThan(0));
      expect(active.bannerRect.width, greaterThan(0));
      expect(pre.selectorRect.height, greaterThanOrEqualTo(48));
      expect(active.controlsRect.bottom, lessThanOrEqualTo(land.height - 16));
    });
  });

  group('tablet + ordinary Navigatie isolation', () {
    test('tablet geometry fixtures remain bit-identical vs live-top selector',
        () {
      final g = _tablet(viewport: const Size(1024, 768), landscape: true);
      expect(g.bannerRect, Rect.zero);
      expect(g.liveWindowRect.contains(g.selectorRect.center), isTrue);
      expect(g.selectorRect.width, closeTo(168.0, 0.01));
      expect(g.selectorRect.height, closeTo(40.0, 0.01));
      expect(
        g.selectorRect.top,
        closeTo(g.liveWindowRect.top + 8, 0.01),
      );
      expect(
        g.selectorRect.right,
        closeTo(g.liveWindowRect.right - 8, 0.01),
      );
    });

    test('ordinary Navigatie landscape banner geometry file untouched owner',
        () {
      final src = File(
        'lib/navigation/presentation/phone_nav_landscape_banner_geometry.dart',
      ).readAsStringSync();
      expect(src, contains('resolvePhoneOrdinaryNavCollapsedChromeTop'));
      expect(src, isNot(contains('DriverTellersLayoutGeometry')));
    });

    test('phone Tellers keeps single MapWidget identity (no second map)', () {
      final src = File('lib/navigation/presentation/driver_ride_meters.dart')
          .readAsStringSync();
      expect(src, contains('NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1'));
      expect(src, isNot(contains('MapWidget(')));
    });

    test('no duplicate Live navigatie / generic phase labels on phone path', () {
      final src = File('lib/navigation/presentation/driver_ride_meters.dart')
          .readAsStringSync();
      // Phone must not paint the live-window badge; tablet may.
      expect(src, contains('if (isTablet &&'));
      expect(src, contains('driver_tellers_live_label'));
      expect(src, contains('resolveTellersPhasePillVisible'));
    });
  });
}
