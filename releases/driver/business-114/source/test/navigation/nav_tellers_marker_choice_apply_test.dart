// NAV-TELLERS-MARKER-CHOICE-APPLY-1
//
// Since bf23d7b the SINGLE Mapbox PointAnnotation is the only vehicle-marker
// owner (no Flutter overlay). Tapping Car/Arrow must switch that one on-map
// bitmap. These tests pin the pure, deterministic pieces of that path:
//
//   * icon-source mapping (Car -> taxi PNG, Arrow -> rasterised arrow glyph);
//   * idempotent recreate decision (only a genuine choice change swaps);
//   * the Arrow glyph actually rasterises to real, non-empty PNG bytes that
//     differ from an unrelated glyph (so Car and Arrow never share bytes).
//
// The end-to-end annotation manager update is exercised by the app at runtime
// (it needs a live Mapbox map); the widget-level single-owner invariant is in
// nav_tellers_single_map_marker_owner_test.dart.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_arrow_marker.dart';

void main() {
  group('driverNavigationMarkerIconSourceFor', () {
    test('Car -> taxi PNG', () {
      expect(
        driverNavigationMarkerIconSourceFor(DriverNavigationMarkerChoice.car),
        DriverNavigationMarkerIconSource.taxiPng,
      );
    });

    test('Arrow -> arrow glyph when available', () {
      expect(
        driverNavigationMarkerIconSourceFor(
          DriverNavigationMarkerChoice.arrow,
          arrowAvailable: true,
        ),
        DriverNavigationMarkerIconSource.arrowGlyph,
      );
    });

    test('Arrow falls back to taxi PNG when glyph bytes unavailable', () {
      expect(
        driverNavigationMarkerIconSourceFor(
          DriverNavigationMarkerChoice.arrow,
          arrowAvailable: false,
        ),
        DriverNavigationMarkerIconSource.taxiPng,
      );
    });

    test('Car ignores arrowAvailable', () {
      expect(
        driverNavigationMarkerIconSourceFor(
          DriverNavigationMarkerChoice.car,
          arrowAvailable: true,
        ),
        DriverNavigationMarkerIconSource.taxiPng,
      );
    });
  });

  group('driverNavigationMarkerNeedsIconSwap (idempotent recreate decision)', () {
    test('no live annotation yet (applied == null) -> swap needed', () {
      expect(
        driverNavigationMarkerNeedsIconSwap(
          applied: null,
          selected: DriverNavigationMarkerChoice.car,
        ),
        isTrue,
      );
    });

    test('Car -> Arrow needs swap', () {
      expect(
        driverNavigationMarkerNeedsIconSwap(
          applied: DriverNavigationMarkerChoice.car,
          selected: DriverNavigationMarkerChoice.arrow,
        ),
        isTrue,
      );
    });

    test('Arrow -> Car needs swap', () {
      expect(
        driverNavigationMarkerNeedsIconSwap(
          applied: DriverNavigationMarkerChoice.arrow,
          selected: DriverNavigationMarkerChoice.car,
        ),
        isTrue,
      );
    });

    test('same choice is idempotent -> no swap (no new annotation)', () {
      expect(
        driverNavigationMarkerNeedsIconSwap(
          applied: DriverNavigationMarkerChoice.car,
          selected: DriverNavigationMarkerChoice.car,
        ),
        isFalse,
      );
      expect(
        driverNavigationMarkerNeedsIconSwap(
          applied: DriverNavigationMarkerChoice.arrow,
          selected: DriverNavigationMarkerChoice.arrow,
        ),
        isFalse,
      );
    });

    test('repeated Car<->Arrow switching always resolves to a single swap '
        'decision per transition', () {
      // Model the applied-choice bookkeeping the state performs: after each
      // swap the applied choice equals the selected one, so the immediate
      // re-evaluation is false (no thrash / no second annotation).
      var applied = DriverNavigationMarkerChoice.car;
      for (final selected in <DriverNavigationMarkerChoice>[
        DriverNavigationMarkerChoice.arrow,
        DriverNavigationMarkerChoice.car,
        DriverNavigationMarkerChoice.arrow,
      ]) {
        final needs = driverNavigationMarkerNeedsIconSwap(
          applied: applied,
          selected: selected,
        );
        expect(needs, isTrue);
        applied = selected; // create path records the new applied choice
        // Immediate re-evaluation must be idempotent.
        expect(
          driverNavigationMarkerNeedsIconSwap(
            applied: applied,
            selected: selected,
          ),
          isFalse,
        );
      }
    });
  });

  group('renderNavigationDriverArrowMarkerPngBytes (Arrow bitmap for Mapbox)',
      () {
    testWidgets('produces real, non-empty PNG bytes', (tester) async {
      Uint8List? bytes;
      await tester.runAsync(() async {
        bytes = await renderNavigationDriverArrowMarkerPngBytes();
      });
      expect(bytes, isNotNull);
      expect(bytes!.isNotEmpty, isTrue);
      // PNG signature: 89 50 4E 47 0D 0A 1A 0A.
      expect(bytes!.sublist(0, 8),
          <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      // A 490px glyph is comfortably more than a few hundred bytes.
      expect(bytes!.length, greaterThan(200));
    });

    testWidgets('invalid sizes return null (never a broken image)',
        (tester) async {
      Uint8List? zero;
      Uint8List? negative;
      Uint8List? badLogical;
      await tester.runAsync(() async {
        zero = await renderNavigationDriverArrowMarkerPngBytes(pixelSize: 0);
        negative =
            await renderNavigationDriverArrowMarkerPngBytes(pixelSize: -10);
        badLogical = await renderNavigationDriverArrowMarkerPngBytes(
          logicalSize: 0,
        );
      });
      expect(zero, isNull);
      expect(negative, isNull);
      expect(badLogical, isNull);
    });

    testWidgets('different fill colors yield different bytes (distinct icons)',
        (tester) async {
      Uint8List? a;
      Uint8List? b;
      await tester.runAsync(() async {
        a = await renderNavigationDriverArrowMarkerPngBytes(
          fillColor: const Color(0xFFFFD21F),
        );
        b = await renderNavigationDriverArrowMarkerPngBytes(
          fillColor: const Color(0xFF00A3FF),
        );
      });
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(equals(b)));
    });

    testWidgets('rendering is deterministic (stable cached bytes)',
        (tester) async {
      Uint8List? a;
      Uint8List? b;
      await tester.runAsync(() async {
        a = await renderNavigationDriverArrowMarkerPngBytes();
        b = await renderNavigationDriverArrowMarkerPngBytes();
      });
      expect(a, equals(b));
    });
  });
}
