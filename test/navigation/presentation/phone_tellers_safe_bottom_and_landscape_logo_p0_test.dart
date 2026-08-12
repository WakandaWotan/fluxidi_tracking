// PHONE-TELLERS-SAFE-BOTTOM + PHONE-NAV-LANDSCAPE-LOGO-P0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';
import 'package:fluxidi_tracking/navigation/presentation/phone_nav_landscape_logo_metrics.dart';

void main() {
  group('phone Tellers controlsRect safe bottom', () {
    test('portrait active controls stay inside safe content with breathing', () {
      const vp = Size(407, 904);
      const safeBottom = 20.0;
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: vp,
        safeTop: 32,
        safeBottom: safeBottom,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
        reservePhasePill: true,
      );
      final contentBottom = vp.height - safeBottom - kTellersPhoneBottomBreathing;
      expect(g.controlsRect.height, greaterThanOrEqualTo(48));
      expect(g.controlsRect.height, closeTo(kTellersPhoneControlsH, 0.5));
      expect(g.controlsRect.bottom, lessThanOrEqualTo(contentBottom + 0.5));
      expect(
        g.controlsRect.bottom,
        closeTo(contentBottom, 0.5),
      );
      expect(
        contentBottom - g.controlsRect.bottom,
        lessThanOrEqualTo(0.5),
      );
      expect(g.controlsRect.bottom, lessThan(vp.height - safeBottom));
      expect(g.metersPanelRect.overlaps(g.controlsRect), isFalse);
    });

    test('landscape active controls stay inside safe content with breathing', () {
      const vp = Size(904, 407);
      const safeBottom = 12.0;
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: vp,
        safeTop: 12,
        safeBottom: safeBottom,
        safeLeft: 32,
        safeRight: 32,
        isLandscape: true,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
        reservePhasePill: true,
      );
      final contentBottom = vp.height - safeBottom - kTellersPhoneBottomBreathing;
      expect(g.controlsRect.height, greaterThanOrEqualTo(48));
      expect(g.controlsRect.bottom, lessThanOrEqualTo(contentBottom + 0.5));
      expect(g.controlsRect.bottom, lessThan(vp.height - safeBottom));
      expect(g.metersPanelRect.overlaps(g.controlsRect), isFalse);
    });

    test('pre-START estimate and active controls use mutual bottom ownership', () {
      const vp = Size(407, 904);
      final prepared = DriverTellersLayoutGeometry.resolve(
        viewportSize: vp,
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: false,
        reservePriceSummary: true,
      );
      final active = DriverTellersLayoutGeometry.resolve(
        viewportSize: vp,
        safeTop: 32,
        safeBottom: 20,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: false,
        reserveActionBar: true,
        reservePriceSummary: false,
      );
      expect(prepared.priceSummaryRect.height, greaterThan(0));
      expect(prepared.controlsRect, Rect.zero);
      expect(prepared.priceSummaryRect.bottom, lessThanOrEqualTo(904 - 20 - 12 + 0.5));
      expect(active.priceSummaryRect, Rect.zero);
      expect(active.controlsRect.height, greaterThanOrEqualTo(48));
      expect(active.controlsRect.bottom, lessThanOrEqualTo(904 - 20 - 12 + 0.5));
    });

    test('no overflow geometry at 407×904 and 904×407', () {
      for (final entry in <(Size, bool)>[
        (const Size(407, 904), false),
        (const Size(904, 407), true),
      ]) {
        final g = DriverTellersLayoutGeometry.resolve(
          viewportSize: entry.$1,
          safeTop: 24,
          safeBottom: 16,
          safeLeft: entry.$2 ? 24 : 0,
          safeRight: entry.$2 ? 24 : 0,
          isLandscape: entry.$2,
          isTablet: false,
          reserveActionBar: true,
          reservePriceSummary: false,
          reservePhasePill: true,
        );
        expect(g.controlsRect.left, greaterThanOrEqualTo(0));
        expect(g.controlsRect.right, lessThanOrEqualTo(entry.$1.width + 0.5));
        expect(g.controlsRect.bottom, lessThanOrEqualTo(entry.$1.height + 0.5));
        expect(g.controlsRect.top, greaterThanOrEqualTo(0));
      }
    });

    test('tablet controls geometry unchanged by phone bottom breathing', () {
      final g = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(800, 1280),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
        reserveActionBar: true,
      );
      // Tablet still uses its own 12 lp bottom pad, not phone breathing alone.
      expect(g.controlsRect.bottom, lessThanOrEqualTo(1280 - 16 - 12 + 0.5));
      expect(g.isTablet, isTrue);
    });
  });

  group('phone ordinary landscape logo metrics', () {
    test('wide landscape selects enlarged logo (~35–45%)', () {
      final m = PhoneNavLandscapeLogoMetrics.resolve(
        isPhoneHost: true,
        isLandscape: true,
        availableRowWidth: 860,
        hasInlineBanner: true,
      )!;
      expect(m.enlarged, isTrue);
      expect(
        m.slotWidth / kPhoneNavLandscapeLogoCompactSlotW,
        inInclusiveRange(1.35, 1.45),
      );
      expect(
        m.paintHeight / kPhoneNavLandscapeLogoCompactPaintH,
        inInclusiveRange(1.35, 1.45),
      );
      // Banner share remains ≥52% of the row after menu/gaps/logo.
      const menuGaps = 44.0 + 16.0;
      final bannerShare = (860 - menuGaps - m.slotWidth) / 860;
      expect(bannerShare, greaterThanOrEqualTo(0.52));
      final logoShare = m.slotWidth / 860;
      expect(logoShare, inInclusiveRange(0.16, 0.28));
    });

    test('portrait / compact / tablet retain existing metrics', () {
      expect(
        PhoneNavLandscapeLogoMetrics.resolve(
          isPhoneHost: true,
          isLandscape: false,
          availableRowWidth: 400,
          hasInlineBanner: true,
        ),
        isNull,
      );
      expect(
        PhoneNavLandscapeLogoMetrics.resolve(
          isPhoneHost: false,
          isLandscape: true,
          availableRowWidth: 900,
          hasInlineBanner: true,
        ),
        isNull,
      );
      final compact = PhoneNavLandscapeLogoMetrics.resolve(
        isPhoneHost: true,
        isLandscape: true,
        availableRowWidth: 400,
        hasInlineBanner: true,
      )!;
      expect(compact.enlarged, isFalse);
      expect(compact.slotWidth, kPhoneNavLandscapeLogoCompactSlotW);
      expect(compact.paintHeight, kPhoneNavLandscapeLogoCompactPaintH);
    });
  });
}
