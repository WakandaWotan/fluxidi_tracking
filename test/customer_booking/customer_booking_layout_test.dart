import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_route_camera.dart';

void main() {
  test('wide split needs leftover width after text scale', () {
    expect(customerBookingUseWideSplit(width: 390, height: 844), isFalse);
    expect(customerBookingUseWideSplit(width: 800, height: 1280), isTrue);
    expect(
      customerBookingUseWideSplit(width: 800, height: 1280, textScale: 1.6),
      isFalse,
    );
    expect(customerBookingUseWideSplit(width: 1280, height: 800), isTrue);
  });

  test('phone sheet has min third, half initial and full-under-app-bar', () {
    final phone = customerBookingSheetSizes(height: 844, keyboardOpen: false);
    expect(phone.max, greaterThanOrEqualTo(0.90));
    expect(phone.min, closeTo(0.34, 0.05));
    expect(phone.half, closeTo(0.50, 0.04));
    expect(phone.half, greaterThan(phone.min));
    expect(phone.snaps, hasLength(3));
    expect(phone.initial, phone.half);
    expect(
      customerBookingSheetLevel(phone.min, phone),
      CustomerBookingSheetLevel.compact,
    );
    expect(
      customerBookingSheetLevel(phone.half, phone),
      CustomerBookingSheetLevel.half,
    );
    expect(
      customerBookingSheetLevel(phone.max, phone),
      CustomerBookingSheetLevel.expanded,
    );
    expect(customerBookingSheetShowsDetails(phone.min, phone), isTrue);
    expect(customerBookingSheetAllowsScroll(phone.min, phone), isFalse);
    expect(customerBookingSheetAllowsScroll(phone.max, phone), isTrue);
    final landscape = customerBookingSheetSizes(
      height: 334,
      keyboardOpen: false,
    );
    expect(landscape.max, lessThan(0.80));
    expect(landscape.min, lessThan(landscape.max));
    expect(landscape.max, greaterThan(landscape.min));
    final insets = customerBookingMapFitInsets(
      wide: false,
      height: 844,
      sheetExtent: phone.min,
    );
    expect(insets.bottom, greaterThan(200));
    expect(insets.bottom, lessThan(500));
    final keyboard = customerBookingSheetSizes(height: 844, keyboardOpen: true);
    expect(keyboard.min, closeTo(phone.min, 0.001));
    expect(keyboard.max, closeTo(phone.max, 0.001));
  });

  test(
    'metrics badge sits bottom-left of the live map hole above the sheet',
    () {
      const size = Size(390, 844);
      final phone = customerBookingSheetSizes(height: 844, keyboardOpen: false);
      final insets = customerBookingMapFitInsets(
        wide: false,
        height: 844,
        sheetExtent: phone.half,
      );
      final placement = customerBookingMetricsBadgePlacement(
        size: size,
        visibleInsets: insets,
        badgeSize: const Size(148, 32),
      );
      expect(placement.visible, isTrue);
      final hole = customerBookingVisibleMapHole(size, insets);
      expect(placement.offset.dx, closeTo(hole.left + 8, 0.1));
      expect(placement.offset.dy, lessThan(hole.bottom));
      expect(placement.offset.dy + 32, lessThanOrEqualTo(hole.bottom - 8));
      expect(placement.offset.dy, greaterThan(hole.top));
      final raised = customerBookingMapFitInsets(
        wide: false,
        height: 844,
        sheetExtent: phone.min,
      );
      final lower = customerBookingMetricsBadgePlacement(
        size: size,
        visibleInsets: raised,
        badgeSize: const Size(148, 32),
      );
      expect(lower.visible, isTrue);
      expect(lower.offset.dy, greaterThan(placement.offset.dy));
      final covered = customerBookingMetricsBadgePlacement(
        size: size,
        visibleInsets: const EdgeInsets.fromLTRB(20, 64, 20, 800),
        badgeSize: const Size(148, 32),
      );
      expect(covered.visible, isFalse);
    },
  );

  test('confirm bar stays pinned with keyboard so price remains reachable', () {
    expect(
      customerBookingPinConfirmBar(height: 844, keyboardOpen: false),
      isTrue,
    );
    expect(
      customerBookingPinConfirmBar(height: 500, keyboardOpen: true),
      isTrue,
    );
    expect(
      customerBookingPinConfirmBar(
        height: 844,
        keyboardOpen: false,
        textScale: 1.4,
      ),
      isTrue,
    );
  });

  test('sheet snaps only at compact, half and expanded extents', () {
    final phone = customerBookingSheetSizes(height: 844, keyboardOpen: false);
    expect(customerBookingSheetIsSnapped(phone.min, phone), isTrue);
    expect(customerBookingSheetIsSnapped(phone.half, phone), isTrue);
    expect(customerBookingSheetIsSnapped(phone.max, phone), isTrue);
    expect(
      customerBookingSheetIsSnapped((phone.min + phone.half) / 2, phone),
      isFalse,
    );
    for (final width in <double>[360, 390, 430]) {
      final insets = customerBookingMapFitInsets(
        wide: false,
        height: 844,
        sheetExtent: phone.min,
      );
      expect(insets.bottom, greaterThan(width * 0.4));
    }
  });

  test('metrics badge stays bottom-left and readable on tablet', () {
    for (final size in const <Size>[Size(800, 1280), Size(1280, 800)]) {
      const badge = Size(168, 36);
      final placement = customerBookingMetricsBadgePlacement(
        size: size,
        visibleInsets: const EdgeInsets.fromLTRB(24, 72, 24, 28),
        badgeSize: badge,
      );
      expect(placement.visible, isTrue, reason: '${size.width}x${size.height}');
      expect(placement.offset.dx, lessThan(size.width / 2));
      expect(
        placement.offset.dy + badge.height,
        lessThanOrEqualTo(size.height - 28),
      );
    }
  });
}
