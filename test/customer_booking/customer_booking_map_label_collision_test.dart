// Dossier 04 — pickup and destination labels must never overlap each other,
// the route markers or the metrics badge.

import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';

const List<double> kPhoneWidths = <double>[360, 390, 412];
const List<double> kTextScales = <double>[1.0, 1.3];

const String kPickupLabel = 'Koekamerstraat 48A, 9688 Louise-Marie';
const String kDropoffLabel = 'Brussels South Charleroi Airport';

Rect rectFor(Offset pos, Size size) =>
    Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);

EdgeInsets holeInsets({
  required double height,
  required bool wide,
  double sheetExtent = 0.42,
}) {
  return customerBookingMapFitInsets(
    wide: wide,
    height: height,
    sheetExtent: sheetExtent,
  );
}

void main() {
  group('measured chip size', () {
    test('a longer address is wider, and the cap is respected', () {
      final short = customerBookingEndpointChipSize(text: 'Gent');
      final long = customerBookingEndpointChipSize(text: kPickupLabel);
      expect(short.width, lessThan(long.width));
      expect(long.width, lessThanOrEqualTo(168));
      expect(short.height, greaterThanOrEqualTo(28));
    });

    test('a larger text scale widens the chip and eventually heightens it', () {
      final normal = customerBookingEndpointChipSize(text: 'Gent');
      final scaled = customerBookingEndpointChipSize(
        text: 'Gent',
        textScale: 1.3,
      );
      expect(scaled.width, greaterThan(normal.width));
      // Height only grows once the scaled text is taller than the 16 px icon.
      final veryLarge = customerBookingEndpointChipSize(
        text: 'Gent',
        textScale: 2.0,
      );
      expect(veryLarge.height, greaterThan(normal.height));
    });

    test('the edit affordance is part of the measured width', () {
      final plain = customerBookingEndpointChipSize(text: 'Gent');
      final editable = customerBookingEndpointChipSize(
        text: 'Gent',
        hasEditIcon: true,
      );
      expect(editable.width, greaterThan(plain.width));
    });
  });

  group('two labels never overlap', () {
    for (final width in kPhoneWidths) {
      for (final textScale in kTextScales) {
        for (final orientation in <String>['portrait', 'landscape']) {
          for (final keyboard in <String>['closed', 'open']) {
            test(
              '${width.toInt()} dp $orientation, text scale $textScale, keyboard $keyboard',
              () {
                final portrait = orientation == 'portrait';
                final size = portrait
                    ? Size(width, 844)
                    : Size(844, width);
                // An open keyboard shrinks the usable map hole.
                final sheetExtent = keyboard == 'open' ? 0.72 : 0.42;
                final insets = holeInsets(
                  height: size.height,
                  wide: size.width >= kCustomerBookingRouteWideBreakpoint,
                  sheetExtent: sheetExtent,
                );
                final pickupSize = customerBookingEndpointChipSize(
                  text: kPickupLabel,
                  textScale: textScale,
                  hasEditIcon: true,
                );
                final dropoffSize = customerBookingEndpointChipSize(
                  text: kDropoffLabel,
                  textScale: textScale,
                  hasEditIcon: true,
                );
                final hole = customerBookingVisibleMapHole(size, insets);
                // Two anchors far enough apart to expect two full chips.
                final pickupAnchor = Offset(
                  hole.left + hole.width * 0.25,
                  hole.top + hole.height * 0.35,
                );
                final dropoffAnchor = Offset(
                  hole.left + hole.width * 0.75,
                  hole.top + hole.height * 0.7,
                );
                final metricsAvoid = Rect.fromLTWH(
                  hole.left + 4,
                  hole.bottom - 34,
                  120,
                  30,
                );

                final placement = customerBookingPlaceEndpointLabels(
                  pickupAnchor: pickupAnchor,
                  dropoffAnchor: dropoffAnchor,
                  pickupSize: pickupSize,
                  dropoffSize: dropoffSize,
                  size: size,
                  visibleInsets: insets,
                  avoid: metricsAvoid,
                );

                if (placement.useCompactMarkers) {
                  // Falling back to A/B markers is a valid, collision-free
                  // answer when the hole is too small for two chips.
                  return;
                }

                final pickupRect = rectFor(placement.pickup!, pickupSize);
                final dropoffRect = rectFor(placement.dropoff!, dropoffSize);
                expect(
                  pickupRect.overlaps(dropoffRect),
                  isFalse,
                  reason: 'pickup $pickupRect overlaps dropoff $dropoffRect',
                );
                expect(
                  pickupRect.contains(pickupAnchor),
                  isFalse,
                  reason: 'pickup chip covers its own marker',
                );
                expect(
                  dropoffRect.contains(dropoffAnchor),
                  isFalse,
                  reason: 'dropoff chip covers its own marker',
                );
                final deflatedHole = hole.deflate(4);
                expect(
                  deflatedHole.contains(pickupRect.topLeft) &&
                      deflatedHole.contains(
                        Offset(pickupRect.right, pickupRect.bottom),
                      ),
                  isTrue,
                  reason: 'pickup chip $pickupRect leaves the hole $hole',
                );
                expect(
                  deflatedHole.contains(dropoffRect.topLeft) &&
                      deflatedHole.contains(
                        Offset(dropoffRect.right, dropoffRect.bottom),
                      ),
                  isTrue,
                  reason: 'dropoff chip $dropoffRect leaves the hole $hole',
                );
              },
            );
          }
        }
      }
    }
  });

  group('short routes switch to A/B markers plus a legend', () {
    test('anchors closer than the minimum separation use compact markers', () {
      const size = Size(390, 844);
      final insets = holeInsets(height: size.height, wide: false);
      final placement = customerBookingPlaceEndpointLabels(
        pickupAnchor: const Offset(200, 400),
        dropoffAnchor: const Offset(212, 418),
        pickupSize: customerBookingEndpointChipSize(text: kPickupLabel),
        dropoffSize: customerBookingEndpointChipSize(text: kDropoffLabel),
        size: size,
        visibleInsets: insets,
      );
      expect(placement.useCompactMarkers, isTrue);
      expect(placement.pickup, isNull);
      expect(placement.dropoff, isNull);
    });

    test('well separated anchors keep the two address chips', () {
      const size = Size(390, 844);
      final insets = holeInsets(height: size.height, wide: false);
      final placement = customerBookingPlaceEndpointLabels(
        pickupAnchor: const Offset(120, 180),
        dropoffAnchor: const Offset(280, 380),
        pickupSize: customerBookingEndpointChipSize(text: kPickupLabel),
        dropoffSize: customerBookingEndpointChipSize(text: kDropoffLabel),
        size: size,
        visibleInsets: insets,
      );
      expect(placement.useCompactMarkers, isFalse);
      expect(placement.pickup, isNotNull);
      expect(placement.dropoff, isNotNull);
    });
  });

  test('one known endpoint still places a single chip', () {
    const size = Size(390, 844);
    final insets = holeInsets(height: size.height, wide: false);
    final onlyPickup = customerBookingPlaceEndpointLabels(
      pickupAnchor: const Offset(180, 300),
      dropoffAnchor: null,
      pickupSize: customerBookingEndpointChipSize(text: kPickupLabel),
      dropoffSize: customerBookingEndpointChipSize(text: kDropoffLabel),
      size: size,
      visibleInsets: insets,
    );
    expect(onlyPickup.pickup, isNotNull);
    expect(onlyPickup.dropoff, isNull);
    expect(onlyPickup.useCompactMarkers, isFalse);

    final onlyDropoff = customerBookingPlaceEndpointLabels(
      pickupAnchor: null,
      dropoffAnchor: const Offset(180, 300),
      pickupSize: customerBookingEndpointChipSize(text: kPickupLabel),
      dropoffSize: customerBookingEndpointChipSize(text: kDropoffLabel),
      size: size,
      visibleInsets: insets,
    );
    expect(onlyDropoff.pickup, isNull);
    expect(onlyDropoff.dropoff, isNotNull);
  });

  test('labels stay clear of the metrics badge', () {
    const size = Size(390, 844);
    final insets = holeInsets(height: size.height, wide: false);
    final hole = customerBookingVisibleMapHole(size, insets);
    final metricsAvoid = Rect.fromLTWH(hole.left + 4, hole.bottom - 34, 140, 30);
    final pickupSize = customerBookingEndpointChipSize(text: kPickupLabel);
    final dropoffSize = customerBookingEndpointChipSize(text: kDropoffLabel);
    final placement = customerBookingPlaceEndpointLabels(
      pickupAnchor: Offset(hole.left + 30, hole.bottom - 60),
      dropoffAnchor: Offset(hole.right - 40, hole.top + 60),
      pickupSize: pickupSize,
      dropoffSize: dropoffSize,
      size: size,
      visibleInsets: insets,
      avoid: metricsAvoid,
    );
    if (placement.useCompactMarkers) return;
    expect(
      rectFor(placement.pickup!, pickupSize).overlaps(metricsAvoid),
      isFalse,
    );
    expect(
      rectFor(placement.dropoff!, dropoffSize).overlaps(metricsAvoid),
      isFalse,
    );
  });
}
