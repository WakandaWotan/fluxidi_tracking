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

  test('confirm bar unpins for keyboard and large text', () {
    expect(
      customerBookingPinConfirmBar(height: 844, keyboardOpen: false),
      isTrue,
    );
    expect(
      customerBookingPinConfirmBar(height: 844, keyboardOpen: true),
      isFalse,
    );
    expect(
      customerBookingPinConfirmBar(
        height: 844,
        keyboardOpen: false,
        textScale: 1.4,
      ),
      isFalse,
    );
  });
}
