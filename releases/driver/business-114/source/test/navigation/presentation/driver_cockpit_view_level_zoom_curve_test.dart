import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

/// NAV-ZOOM-FIELD-REPAIR-1 — visible View steps.
///
/// Field defect: above the default View 7 the level-to-zoom curve was
/// arithmetically dead (L7 -> L8 = +0.0081 zoom, L8 -> L9 = +0.0662 zoom).
/// The camera commands were issued and applied correctly, but the driver saw
/// no change and concluded the control was broken.
void main() {
  const phone = _Profile(
    label: 'phone',
    isTablet: false,
    isLandscape: false,
    golden: <double>[
      16.8000,
      17.0239,
      17.3514,
      17.7341,
      18.1577,
      18.6146,
      19.1000,
      19.3434,
      19.6994,
      20.1153,
      20.5758,
      21.0724,
      21.6000,
    ],
  );

  const tablet = _Profile(
    label: 'tablet',
    isTablet: true,
    isLandscape: false,
    golden: <double>[
      16.5000,
      16.6850,
      16.9555,
      17.2716,
      17.6216,
      17.9991,
      18.4000,
      18.6629,
      19.0473,
      19.4965,
      19.9938,
      20.5302,
      21.1000,
    ],
  );

  const profiles = <_Profile>[phone, tablet];

  group('NAV-ZOOM-FIELD-REPAIR-1 level-to-zoom curve', () {
    test('anchors, default level and overall range are preserved', () {
      expect(kDriverCockpitViewLevelMin, 1);
      expect(kDriverCockpitViewLevelMax, 13);
      expect(kDriverCockpitViewLevelDefault, 7);

      for (final p in profiles) {
        expect(p.zoom(1), closeTo(p.golden.first, 1e-9), reason: p.label);
        expect(p.zoom(7), closeTo(p.golden[6], 1e-9), reason: p.label);
        expect(p.zoom(13), closeTo(p.golden.last, 1e-9), reason: p.label);
      }

      // Level 1 / 7 / 13 remain the untouched product anchors.
      expect(phone.zoom(1), kDriverCockpitPro2PhoneZoomL1);
      expect(phone.zoom(7), kDriverCockpitPro2PhoneZoomL7);
      expect(phone.zoom(13), kDriverCockpitPro2PhoneZoomL13);
      expect(tablet.zoom(1), kDriverCockpitPro2CompactZoomL1);
      expect(tablet.zoom(7), kDriverCockpitPro2CompactZoomL7);
      expect(tablet.zoom(13), kDriverCockpitPro2CompactZoomL13);
    });

    test('mapping table is deterministic across repeated resolution', () {
      for (final p in profiles) {
        for (var level = 1; level <= 13; level++) {
          expect(
            p.zoom(level),
            closeTo(p.golden[level - 1], 5e-5),
            reason: '${p.label} L$level',
          );
          expect(
            p.zoom(level),
            p.zoom(level),
            reason: '${p.label} L$level must be a pure function of the level',
          );
        }
      }
    });

    test('levels 1..13 are strictly increasing', () {
      for (final p in profiles) {
        for (var level = 2; level <= 13; level++) {
          expect(
            p.zoom(level),
            greaterThan(p.zoom(level - 1)),
            reason: '${p.label} L${level - 1} -> L$level',
          );
        }
      }
    });

    test('no adjacent step is below the approved visibility threshold', () {
      for (final p in profiles) {
        for (var level = 2; level <= 13; level++) {
          final delta = p.zoom(level) - p.zoom(level - 1);
          expect(
            delta,
            greaterThanOrEqualTo(kDriverCockpitViewLevelMinVisibleZoomDelta),
            reason:
                '${p.label} L${level - 1} -> L$level delta '
                '${delta.toStringAsFixed(4)} is visually meaningless',
          );
        }
      }
    });

    test('no adjacent step exceeds the approved maximum step', () {
      for (final p in profiles) {
        for (var level = 2; level <= 13; level++) {
          final delta = p.zoom(level) - p.zoom(level - 1);
          expect(
            delta,
            lessThanOrEqualTo(kDriverCockpitViewLevelMaxVisibleZoomDelta),
            reason:
                '${p.label} L${level - 1} -> L$level delta '
                '${delta.toStringAsFixed(4)} jumps too far',
          );
        }
      }
    });

    test('the dead zone above the default View 7 is gone', () {
      for (final p in profiles) {
        final l7l8 = p.zoom(8) - p.zoom(7);
        final l8l9 = p.zoom(9) - p.zoom(8);

        // The exact field-reported dead deltas must not reappear.
        expect(l7l8, greaterThan(0.05 + 0.0081), reason: p.label);
        expect(l8l9, greaterThan(0.05 + 0.0662), reason: p.label);

        expect(
          l7l8,
          greaterThanOrEqualTo(kDriverCockpitViewLevelMinVisibleZoomDelta),
          reason: p.label,
        );

        // L7 -> L8 must be comparable to its neighbouring manual steps rather
        // than an order of magnitude smaller.
        final l6l7 = p.zoom(7) - p.zoom(6);
        expect(l7l8 / l6l7, greaterThan(0.45), reason: p.label);
        expect(l7l8 / l8l9, greaterThan(0.5), reason: p.label);
      }
    });

    test('no discontinuous step-size jump at the low/high segment boundary', () {
      for (final p in profiles) {
        final beforeBoundary = p.zoom(7) - p.zoom(6);
        final afterBoundary = p.zoom(8) - p.zoom(7);
        final ratio = afterBoundary / beforeBoundary;
        expect(ratio, greaterThan(0.45), reason: p.label);
        expect(ratio, lessThan(2.0), reason: p.label);
      }
    });

    test('passive follow smoothing can reach any selected level in one tick', () {
      // Every adjacent step must fit inside the follow smoothing budget,
      // otherwise passive follow lags behind the level the driver selected.
      for (final p in profiles) {
        for (var level = 2; level <= 13; level++) {
          final delta = p.zoom(level) - p.zoom(level - 1);
          expect(
            delta,
            lessThanOrEqualTo(kDriverCockpitCameraFollowMaxZoomStep),
            reason: '${p.label} L${level - 1} -> L$level',
          );
        }
      }
    });

    test('passive follow targets the selected view level, not the default', () {
      for (final p in profiles) {
        for (final level in <int>[1, 5, 7, 8, 11, 13]) {
          final out = resolveDriverCockpitCameraProfile(
            DriverCockpitCameraProfileInput(
              isTablet: p.isTablet,
              isLandscape: p.isLandscape,
              screenHeight: p.isTablet ? 1280 : 2340,
              safeTop: 24,
              safeBottom: 24,
              currentZoom: p.zoom(level),
              currentPitch: driverCockpitViewLevelTargetPitch(
                isTablet: p.isTablet,
                isLandscape: p.isLandscape,
                level: level,
              ),
            ),
            viewLevel: level,
          );
          expect(
            out.zoom,
            closeTo(p.zoom(level), 1e-9),
            reason: '${p.label} follow L$level',
          );
        }
      }
    });
  });

  group('NAV-ZOOM-FIELD-REPAIR-1 View +/- stepping', () {
    test('repeated + presses advance exactly one level each', () {
      var level = kDriverCockpitViewLevelDefault;
      final seen = <int>[level];
      for (var i = 0; i < 6; i++) {
        final next = stepDriverCockpitViewLevel(level, increase: true);
        expect(next, level + 1);
        level = next;
        seen.add(level);
      }
      expect(seen, <int>[7, 8, 9, 10, 11, 12, 13]);
    });

    test('repeated - presses decrease exactly one level each', () {
      var level = kDriverCockpitViewLevelDefault;
      final seen = <int>[level];
      for (var i = 0; i < 6; i++) {
        final next = stepDriverCockpitViewLevel(level, increase: false);
        expect(next, level - 1);
        level = next;
        seen.add(level);
      }
      expect(seen, <int>[7, 6, 5, 4, 3, 2, 1]);
    });

    test('every single press produces a visible zoom change', () {
      for (final p in profiles) {
        for (var level = 1; level < 13; level++) {
          final up = stepDriverCockpitViewLevel(level, increase: true);
          final delta = (p.zoom(up) - p.zoom(level)).abs();
          expect(
            delta,
            greaterThanOrEqualTo(kDriverCockpitViewLevelMinVisibleZoomDelta),
            reason: '${p.label} press + at L$level',
          );
        }
      }
    });

    test('default View 7 plus one press produces a meaningful target', () {
      for (final p in profiles) {
        final up = stepDriverCockpitViewLevel(
          kDriverCockpitViewLevelDefault,
          increase: true,
        );
        expect(up, 8);
        expect(
          p.zoom(up) - p.zoom(kDriverCockpitViewLevelDefault),
          greaterThanOrEqualTo(kDriverCockpitViewLevelMinVisibleZoomDelta),
          reason: p.label,
        );
      }
    });

    test('bounds clamp safely at levels 1 and 13', () {
      expect(stepDriverCockpitViewLevel(1, increase: false), 1);
      expect(stepDriverCockpitViewLevel(13, increase: true), 13);
      expect(clampDriverCockpitViewLevel(-5), 1);
      expect(clampDriverCockpitViewLevel(99), 13);

      for (final p in profiles) {
        expect(p.zoom(0), p.zoom(1), reason: p.label);
        expect(p.zoom(99), p.zoom(13), reason: p.label);
      }
    });

    test('+ then - returns to the original level and zoom target', () {
      for (final p in profiles) {
        for (var level = 1; level <= 13; level++) {
          final before = p.zoom(level);
          final up = stepDriverCockpitViewLevel(level, increase: true);
          final back = stepDriverCockpitViewLevel(up, increase: false);
          if (level < 13) {
            expect(back, level, reason: '${p.label} L$level');
            expect(p.zoom(back), before, reason: '${p.label} L$level');
          }

          final down = stepDriverCockpitViewLevel(level, increase: false);
          final backUp = stepDriverCockpitViewLevel(down, increase: true);
          if (level > 1) {
            expect(backUp, level, reason: '${p.label} L$level');
            expect(p.zoom(backUp), before, reason: '${p.label} L$level');
          }
        }
      }
    });

    test('phone and tablet profiles both stay inside the camera clamps', () {
      for (final p in profiles) {
        for (var level = 1; level <= 13; level++) {
          expect(
            p.zoom(level),
            inInclusiveRange(
              kDriverCockpitCameraMinZoom,
              kDriverCockpitCameraMaxZoom,
            ),
            reason: '${p.label} L$level',
          );
          final pitch = driverCockpitViewLevelTargetPitch(
            isTablet: p.isTablet,
            isLandscape: p.isLandscape,
            level: level,
          );
          expect(
            pitch,
            inInclusiveRange(
              kDriverCockpitCameraMinPitch,
              kDriverCockpitCameraMaxPitch,
            ),
            reason: '${p.label} L$level pitch',
          );
        }
      }
    });

    test('pitch curve is monotonic and never dead above View 7', () {
      for (final p in profiles) {
        double pitch(int level) => driverCockpitViewLevelTargetPitch(
          isTablet: p.isTablet,
          isLandscape: p.isLandscape,
          level: level,
        );
        for (var level = 2; level <= 13; level++) {
          expect(
            pitch(level),
            greaterThan(pitch(level - 1)),
            reason: '${p.label} pitch L${level - 1} -> L$level',
          );
        }
        // The old high-segment exponent moved pitch by 0.02 degrees here.
        expect(pitch(8) - pitch(7), greaterThan(0.25), reason: p.label);
      }
    });
  });
}

class _Profile {
  const _Profile({
    required this.label,
    required this.isTablet,
    required this.isLandscape,
    required this.golden,
  });

  final String label;
  final bool isTablet;
  final bool isLandscape;
  final List<double> golden;

  double zoom(int level) => driverCockpitViewLevelTargetZoom(
    isTablet: isTablet,
    isLandscape: isLandscape,
    level: level,
  );
}
