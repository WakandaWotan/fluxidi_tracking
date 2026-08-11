// FLUXIDI-HOST-FORM-FACTOR-P0: tablet host identity survives split-screen.
// Window geometry may shrink; product family (header + camera L7) must not
// flip to phone. Phone hosts must remain phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/fluxidi_host_form_factor.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/external/external_navigation_pip_meter.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_stationary_bearing_hold.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_tablet_branded_header.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

void main() {
  const hostTablet = Size(880, 1408);
  const verticalSplit = Size(420, 880);
  const horizontalNarrow = Size(1280, 420);
  const horizontalTall = Size(1280, 700);
  const phoneWindow = Size(390, 844);

  group('resolveFluxidiHostIsTablet', () {
    test('TEST1: host latch + display survive window shrink to 420x880', () {
      expect(hostTablet.shortestSide, greaterThanOrEqualTo(600));
      expect(verticalSplit.shortestSide, lessThan(600));

      expect(
        resolveFluxidiHostIsTablet(
          deviceSize: hostTablet,
          windowSize: verticalSplit,
        ),
        isTrue,
      );
      expect(
        resolveFluxidiHostIsTablet(
          latchedHostIsTablet: true,
          windowSize: verticalSplit,
        ),
        isTrue,
      );
      // Sticky latch never demotes.
      expect(
        latchFluxidiHostIsTablet(
          previousLatch: true,
          resolvedIsTablet: false,
        ),
        isTrue,
      );
    });

    test('TEST8: phone host stays phone even if a wide pane appears', () {
      expect(
        resolveFluxidiHostIsTablet(
          deviceSize: phoneWindow,
          windowSize: const Size(900, 390),
        ),
        isFalse,
      );
      expect(
        latchFluxidiHostIsTablet(
          previousLatch: false,
          resolvedIsTablet: false,
        ),
        isFalse,
      );
    });
  });

  group('header identity vs window geometry', () {
    test('TEST2: vertical split keeps tablet signage gate with hostIsTablet', () {
      expect(
        isNavSignageTabletLayout(verticalSplit),
        isFalse,
        reason: 'window-only gate would wrongly pick phone',
      );
      expect(
        isNavSignageTabletLayout(
          verticalSplit,
          hostIsTablet: true,
        ),
        isTrue,
      );
    });

    test('TEST2: narrow pane branded metrics fit without inventing width', () {
      const available = 340.0; // ~420 pane minus insets/compass
      final header = NavTabletBrandedHeaderMetrics.resolve(
        availableWidth: available,
        isLandscape: false,
        cardHeight: 176,
      );
      final total = header.menuSize +
          header.gap * 2 +
          header.brandWidth +
          header.maneuverMaxWidth;
      expect(total, lessThanOrEqualTo(available + 0.5));
      expect(header.zonesAreEqualWidth, isTrue);
      expect(header.cardHeight, lessThanOrEqualTo(152));
    });

    test('TEST4: horizontal split window shapes keep host gate + adapt band', () {
      for (final window in [horizontalNarrow, horizontalTall]) {
        expect(
          isNavSignageTabletLayout(window, hostIsTablet: true),
          isTrue,
          reason: '${window.width}x${window.height}',
        );
        final header = NavTabletBrandedHeaderMetrics.resolve(
          availableWidth: window.width - 24,
          isLandscape: window.width > window.height,
          cardHeight: 160,
        );
        expect(header.brandWidth, greaterThan(0));
        expect(header.maneuverMaxWidth, greaterThan(0));
      }
    });
  });

  group('camera family stays tablet on host tablet', () {
    ({double zoom, double pitch}) family({
      required bool hostIsTablet,
      required bool windowLandscape,
      required DriverCockpitMapVisualStyle style,
    }) {
      return resolveDriverCockpitStreetlevelL7Targets(
        isTablet: hostIsTablet,
        isLandscape: windowLandscape,
        mapVisualStyle: style,
      );
    }

    test('TEST3: vertical split portrait pane keeps tablet L7 families', () {
      // Window is portrait (880>420) but host is tablet → compact family.
      for (final style in [
        DriverCockpitMapVisualStyle.light,
        DriverCockpitMapVisualStyle.dark,
        DriverCockpitMapVisualStyle.satellite,
      ]) {
        final t = family(
          hostIsTablet: true,
          windowLandscape: false,
          style: style,
        );
        expect(t.zoom, 17.0, reason: style.name);
        expect(t.pitch, 62.0, reason: style.name);
      }
      final d3 = family(
        hostIsTablet: true,
        windowLandscape: false,
        style: DriverCockpitMapVisualStyle.standard3d,
      );
      expect(d3.zoom, 18.4);
      expect(d3.pitch, 75.0);

      // Regression: window-only phone classification would have selected these.
      final phoneFlat = family(
        hostIsTablet: false,
        windowLandscape: false,
        style: DriverCockpitMapVisualStyle.light,
      );
      expect(phoneFlat.zoom, 17.7);
      expect(phoneFlat.pitch, 64.0);
      final phone3d = family(
        hostIsTablet: false,
        windowLandscape: false,
        style: DriverCockpitMapVisualStyle.standard3d,
      );
      expect(phone3d.zoom, 19.1);
      expect(phone3d.pitch, 77.0);
    });

    test('TEST4/5: horizontal + resize sequence keeps tablet family', () {
      final shapes = <(Size, bool)>[
        (hostTablet, hostTablet.width > hostTablet.height),
        (verticalSplit, false),
        (horizontalNarrow, true),
        (horizontalTall, true),
        (hostTablet, false),
      ];
      for (final (size, landscape) in shapes) {
        final host = resolveFluxidiHostIsTablet(
          latchedHostIsTablet: true,
          deviceSize: hostTablet,
          windowSize: size,
        );
        expect(host, isTrue, reason: '${size.width}x${size.height}');
        final flat = family(
          hostIsTablet: host,
          windowLandscape: landscape,
          style: DriverCockpitMapVisualStyle.dark,
        );
        final d3 = family(
          hostIsTablet: host,
          windowLandscape: landscape,
          style: DriverCockpitMapVisualStyle.standard3d,
        );
        expect(flat.zoom, 17.0);
        expect(flat.pitch, 62.0);
        expect(d3.zoom, 18.4);
        expect(d3.pitch, 75.0);
      }
    });

    test('preview and follow agree on host isTablet input', () {
      // Both writers must consume hostIsTablet — not width>=600 vs ss>767.
      const host = true;
      final preview = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: host,
        isLandscape: false,
        mapVisualStyle: DriverCockpitMapVisualStyle.satellite,
      );
      final follow = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: host,
        isLandscape: false,
        mapVisualStyle: DriverCockpitMapVisualStyle.satellite,
      );
      expect(preview.zoom, follow.zoom);
      expect(preview.pitch, follow.pitch);
      expect(preview.zoom, 17.0);
    });
  });

  group('preservation of prior P0 holds + PiP', () {
    test('TEST6: prestart route-replace hold still green', () {
      const held = 90.0;
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(
        routeTangentBearingDeg: held,
        routeSegmentIndex: 0,
      );
      expect(
        shouldPreservePrestartHeldBearingAcrossRouteReplace(
          liveRideActive: false,
          preparedRouteDraft: true,
          hasHeldBearing: true,
          speedKmh: 0.0,
          displacementM: 0.2,
          accuracyM: 8.0,
        ),
        isTrue,
      );
      expect(gate.acceptedBearing, closeTo(held, 1e-9));
    });

    test('TEST7: liveRideActive still disables prestart preserve', () {
      expect(
        shouldPreservePrestartHeldBearingAcrossRouteReplace(
          liveRideActive: true,
          preparedRouteDraft: false,
          hasHeldBearing: true,
          speedKmh: 0.0,
          displacementM: 0.2,
          accuracyM: 8.0,
        ),
        isFalse,
      );
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: true,
          preparedRouteDraft: false,
          force: false,
          cameraReason: 'normal_follow',
        ),
        isFalse,
      );
    });

    test('TEST9: PiP helpers delegate to shared host primitive', () {
      expect(kPipMeterTabletShortestSide, kFluxidiHostTabletShortestSide);
      expect(
        resolvePipMeterHostIsTablet(
          latchedHostIsTablet: true,
          windowSize: const Size(352, 198),
        ),
        isTrue,
      );
      expect(
        resolvePipMeterHostIsTablet(
          deviceSize: hostTablet,
          windowSize: const Size(352, 198),
        ),
        isTrue,
      );
    });
  });
}
