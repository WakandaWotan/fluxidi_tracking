/// Layout numbers for the company customer-app header.
///
/// Marketplace Fluxidi branding does not use this file.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'customer_app_header_mode.dart';

const Size kCustomerAppHeaderLogoTablet = Size(480, 160);
const Size kCustomerAppHeaderLogoPhone = Size(280, 94);
const Size kCustomerAppHeaderLogoCompactTablet = Size(300, 100);
const Size kCustomerAppHeaderLogoCompactPhone = Size(210, 70);
const Size kCustomerAppHeaderLogoOverlayTablet = Size(168, 56);
const Size kCustomerAppHeaderLogoOverlayPhone = Size(128, 42);
const double kCustomerAppHeaderLogoOverlayInset = 10;
const Size kCustomerAppHeaderChipSize = Size(48, 48);
const double kCustomerAppHeaderChipReserve = 168;
const double kCustomerAppHeaderPad = 4;
const double kCustomerAppHeaderGutter = 12;
const double kCustomerAppHeaderLogoAspect = 3;

enum CustomerAppHeaderChipPlacement {
  /// Same row as the large logo, top-right.
  endTop,

  /// Under the large logo on a narrow phone.
  belowLogo,

  /// Right-hand column next to a logo-only header.
  endColumn,

  /// Language and theme stay on their own row; the cover sits underneath.
  aboveCover,
}

@immutable
class CustomerAppHeaderMetrics {
  const CustomerAppHeaderMetrics({
    required this.mode,
    required this.logoFrame,
    required this.coverSlot,
    required this.height,
    required this.chipPlacement,
    required this.coverLetterbox,
  });

  final CustomerAppHeaderMode mode;
  final Size logoFrame;
  final Size coverSlot;
  final double height;
  final CustomerAppHeaderChipPlacement chipPlacement;
  final bool coverLetterbox;
}

bool customerAppHeaderIsPhone(Size screen) =>
    math.min(screen.width, screen.height) < 600;

bool customerAppHeaderIsLandscape(Size screen) => screen.width > screen.height;

Size customerAppHeaderLogoFrame({
  required Size screen,
  bool compact = false,
  bool overlay = false,
}) {
  final phone = customerAppHeaderIsPhone(screen);
  if (overlay) {
    return phone
        ? kCustomerAppHeaderLogoOverlayPhone
        : kCustomerAppHeaderLogoOverlayTablet;
  }
  if (compact) {
    return phone
        ? kCustomerAppHeaderLogoCompactPhone
        : kCustomerAppHeaderLogoCompactTablet;
  }
  return phone ? kCustomerAppHeaderLogoPhone : kCustomerAppHeaderLogoTablet;
}

Size customerAppHeaderFitLogo({
  required Size frame,
  required double availableWidth,
}) {
  if (availableWidth <= 0) return Size.zero;
  final scale = math.min(1.0, availableWidth / frame.width);
  return Size(frame.width * scale, frame.height * scale);
}

/// Height cap that keeps a short landscape screen scrollable. Portrait keeps
/// enough room for an 8:3 company banner at full width so text is not cropped.
double customerAppHeaderMaxCoverHeight(Size screen) {
  final landscape = customerAppHeaderIsLandscape(screen);
  if (landscape) {
    return math.min(128.0, math.max(72.0, screen.height * 0.38));
  }
  if (customerAppHeaderIsPhone(screen)) {
    return math.min(200.0, math.max(148.0, screen.height * 0.24));
  }
  return math.min(360.0, math.max(240.0, screen.height * 0.30));
}

Size customerAppHeaderContainSize({
  required Size slot,
  required double aspectRatio,
}) {
  final aspect = aspectRatio <= 0 ? 8 / 3 : aspectRatio;
  if (slot.width <= 0 || slot.height <= 0) return Size.zero;
  final byWidth = Size(slot.width, slot.width / aspect);
  if (byWidth.height <= slot.height + 0.5) {
    return Size(slot.width, math.min(slot.height, byWidth.height));
  }
  return Size(slot.height * aspect, slot.height);
}

CustomerAppHeaderChipPlacement customerAppHeaderChipPlacement({
  required CustomerAppHeaderMode mode,
  required Size screen,
}) {
  switch (mode) {
    case CustomerAppHeaderMode.logoOnly:
    case CustomerAppHeaderMode.coverOnly:
    case CustomerAppHeaderMode.coverAndLogo:
      return CustomerAppHeaderChipPlacement.aboveCover;
  }
}

CustomerAppHeaderMetrics customerAppHeaderMetrics({
  required Size screen,
  required CustomerAppHeaderMode mode,
  double coverAspectRatio = 8 / 3,
}) {
  final chips = customerAppHeaderChipPlacement(mode: mode, screen: screen);
  final pad = kCustomerAppHeaderPad;
  final gutter = kCustomerAppHeaderGutter;
  final chipH = kCustomerAppHeaderChipSize.height;

  if (mode == CustomerAppHeaderMode.logoOnly) {
    final frame = customerAppHeaderLogoFrame(screen: screen);
    final available = screen.width - gutter * 2;
    final logo = customerAppHeaderFitLogo(
      frame: frame,
      availableWidth: available,
    );
    return CustomerAppHeaderMetrics(
      mode: mode,
      logoFrame: logo,
      coverSlot: Size.zero,
      height: chipH + 6 + logo.height + pad,
      chipPlacement: chips,
      coverLetterbox: false,
    );
  }

  final coverWidth = math.max(0.0, screen.width - gutter * 2);
  final maxCoverH = customerAppHeaderMaxCoverHeight(screen);
  final rawCover = customerAppHeaderContainSize(
    slot: Size(coverWidth, maxCoverH),
    aspectRatio: coverAspectRatio,
  );
  final letterbox = rawCover.width + 1 < coverWidth;
  final height = chipH + 6 + rawCover.height + pad;
  var logo = Size.zero;
  if (mode == CustomerAppHeaderMode.coverAndLogo) {
    logo = customerAppHeaderFitLogo(
      frame: customerAppHeaderLogoFrame(screen: screen, overlay: true),
      availableWidth: math.max(
        80,
        coverWidth - kCustomerAppHeaderLogoOverlayInset * 2,
      ),
    );
  }
  return CustomerAppHeaderMetrics(
    mode: mode,
    logoFrame: logo,
    coverSlot: rawCover,
    height: height,
    chipPlacement: chips,
    coverLetterbox: letterbox,
  );
}
