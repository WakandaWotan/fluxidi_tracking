// Phone ordinary Navigatie landscape logo balance (not Tellers, not tablet).

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// Compact phone-landscape logo used when the pane is too narrow to enlarge.
const double kPhoneNavLandscapeLogoCompactSlotW = 112.0;
const double kPhoneNavLandscapeLogoCompactPaintH = 40.0;

/// Enlarged phone-landscape logo (~40% over the compact baseline).
const double kPhoneNavLandscapeLogoEnlargedScale = 1.40;

/// Minimum row width (logical) that may host the enlarged landscape logo.
const double kPhoneNavLandscapeLogoEnlargeMinRowW = 520.0;

/// Resolved phone ordinary-Navigatie landscape logo slot + paint height.
@immutable
class PhoneNavLandscapeLogoMetrics {
  const PhoneNavLandscapeLogoMetrics({
    required this.slotWidth,
    required this.paintHeight,
    required this.enlarged,
  });

  final double slotWidth;
  final double paintHeight;
  final bool enlarged;

  /// Phone host + ordinary Navigatie landscape only.
  ///
  /// Returns null when the caller must keep portrait / tablet / Tellers paths
  /// (caller should ignore and use its existing constants).
  static PhoneNavLandscapeLogoMetrics? resolve({
    required bool isPhoneHost,
    required bool isLandscape,
    required double availableRowWidth,
    required bool hasInlineBanner,
  }) {
    if (!isPhoneHost || !isLandscape) return null;

    final compactW = hasInlineBanner
        ? kPhoneNavLandscapeLogoCompactSlotW
        : 128.0;
    final compactH = hasInlineBanner
        ? kPhoneNavLandscapeLogoCompactPaintH
        : 44.0;

    if (!availableRowWidth.isFinite ||
        availableRowWidth < kPhoneNavLandscapeLogoEnlargeMinRowW) {
      return PhoneNavLandscapeLogoMetrics(
        slotWidth: compactW,
        paintHeight: compactH,
        enlarged: false,
      );
    }

    // ~40% larger than the compact-with-banner baseline.
    final targetW = kPhoneNavLandscapeLogoCompactSlotW *
        kPhoneNavLandscapeLogoEnlargedScale;
    final targetH = kPhoneNavLandscapeLogoCompactPaintH *
        kPhoneNavLandscapeLogoEnlargedScale;

    // Visual allocation: logo group ~24–28%, banner ~52–58%, clear gaps.
    const menuW = 44.0;
    const gaps = 8.0 + 8.0;
    final maxLogoByShare = availableRowWidth * 0.28;
    final minBannerShare = availableRowWidth * 0.52;
    final maxLogoForBanner =
        availableRowWidth - menuW - gaps - minBannerShare;

    final slotW = math
        .min(targetW, math.min(maxLogoByShare, maxLogoForBanner))
        .clamp(compactW, targetW)
        .toDouble();
    final scale = slotW / kPhoneNavLandscapeLogoCompactSlotW;
    final paintH = (kPhoneNavLandscapeLogoCompactPaintH * scale)
        .clamp(compactH, targetH)
        .toDouble();

    return PhoneNavLandscapeLogoMetrics(
      slotWidth: slotW,
      paintHeight: paintH,
      enlarged: slotW > compactW + 0.5,
    );
  }
}
