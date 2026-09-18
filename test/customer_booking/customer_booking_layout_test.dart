import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';

void main() {
  test('wide split needs leftover width after text scale', () {
    expect(
      customerBookingUseWideSplit(width: 390, height: 844),
      isFalse,
    );
    expect(
      customerBookingUseWideSplit(width: 800, height: 1280),
      isTrue,
    );
    expect(
      customerBookingUseWideSplit(width: 800, height: 1280, textScale: 1.6),
      isFalse,
    );
    expect(
      customerBookingUseWideSplit(width: 1280, height: 800),
      isTrue,
    );
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
}
