import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_layout.dart';
import 'package:fluxidi_tracking/customer_app_header/customer_app_header_mode.dart';

void main() {
  test('logo-only keeps the large wordmark and tightens the gap under it', () {
    final tablet = customerAppHeaderMetrics(
      screen: const Size(800, 1280),
      mode: CustomerAppHeaderMode.logoOnly,
    );
    expect(tablet.logoFrame, kCustomerAppHeaderLogoTablet);
    expect(tablet.height, lessThan(230));
    expect(tablet.chipPlacement, CustomerAppHeaderChipPlacement.aboveCover);

    final phone = customerAppHeaderMetrics(
      screen: const Size(390, 844),
      mode: CustomerAppHeaderMode.logoOnly,
    );
    expect(phone.logoFrame, kCustomerAppHeaderLogoPhone);
    expect(phone.chipPlacement, CustomerAppHeaderChipPlacement.aboveCover);
  });

  test('cover stays contained on phone and tablet in both orientations', () {
    const aspect = 3.2;
    for (final screen in const <Size>[
      Size(390, 844),
      Size(844, 390),
      Size(800, 1280),
      Size(1280, 800),
    ]) {
      final metrics = customerAppHeaderMetrics(
        screen: screen,
        mode: CustomerAppHeaderMode.coverOnly,
        coverAspectRatio: aspect,
      );
      expect(metrics.coverSlot.height, lessThanOrEqualTo(customerAppHeaderMaxCoverHeight(screen)));
      expect(
        (metrics.coverSlot.width / metrics.coverSlot.height - aspect).abs(),
        lessThan(0.05),
      );
      expect(metrics.chipPlacement, CustomerAppHeaderChipPlacement.aboveCover);
    }
  });

  test('short landscape caps height without changing the image ratio', () {
    const aspect = 16 / 5;
    final metrics = customerAppHeaderMetrics(
      screen: const Size(844, 390),
      mode: CustomerAppHeaderMode.coverOnly,
      coverAspectRatio: aspect,
    );
    expect(metrics.coverSlot.height, lessThanOrEqualTo(128));
    expect(
      (metrics.coverSlot.width / metrics.coverSlot.height - aspect).abs(),
      lessThan(0.05),
    );
    expect(metrics.coverLetterbox, isTrue);
  });

  test('8:3 company banner keeps full width on tablet portrait', () {
    const aspect = 8 / 3;
    final tablet = customerAppHeaderMetrics(
      screen: const Size(800, 1280),
      mode: CustomerAppHeaderMode.coverOnly,
      coverAspectRatio: aspect,
    );
    expect(tablet.coverSlot.width, 776);
    expect(tablet.coverSlot.height, closeTo(776 / aspect, 0.5));
    expect(tablet.coverLetterbox, isFalse);
  });

  test('header + logo adds a compact logo under the cover', () {
    final tablet = customerAppHeaderMetrics(
      screen: const Size(800, 1280),
      mode: CustomerAppHeaderMode.coverAndLogo,
      coverAspectRatio: 16 / 5,
    );
    expect(tablet.coverSlot.height, greaterThan(80));
    expect(tablet.logoFrame, kCustomerAppHeaderLogoOverlayTablet);
    expect(tablet.height, lessThan(tablet.coverSlot.height + 80));
  });
}
