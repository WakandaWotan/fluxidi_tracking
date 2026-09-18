import 'package:flutter/painting.dart';

/// Layout rules for the customer booking sheet.
///
/// Split form/map only when both width and text scale leave two usable panes.
bool customerBookingUseWideSplit({
  required double width,
  required double height,
  double textScale = 1,
}) {
  final scale = textScale.clamp(1.0, 2.0);
  final neededWidth = 720 * (scale > 1.2 ? scale : 1.0);
  return width >= neededWidth && height >= 420 && scale <= 1.55;
}

/// Keep price + confirm on screen, including when the keyboard is open.
bool customerBookingPinConfirmBar({
  required double height,
  required bool keyboardOpen,
  double textScale = 1,
}) {
  if (textScale >= 1.7 && height < 420) return false;
  if (keyboardOpen) return height >= 280;
  if (textScale >= 1.55) return height >= 420;
  return height >= 360;
}

double customerBookingStackedMapHeight({
  required double width,
  required double height,
  double textScale = 1,
}) {
  if (height < 480) return 180;
  final share = width < 520 ? 0.34 : 0.38;
  final scaled = height * share / textScale.clamp(1.0, 1.4);
  return scaled.clamp(200, 360);
}

double customerBookingAirplaneHeight({
  required bool wide,
  required bool short,
}) {
  if (short) return 0;
  return wide ? 56 : 48;
}

enum CustomerBookingSheetLevel { compact, half, expanded }

class CustomerBookingSheetSizes {
  const CustomerBookingSheetSizes({
    required this.min,
    required this.half,
    required this.max,
    required this.initial,
  });

  final double min;
  final double half;
  final double max;
  final double initial;

  List<double> get snaps {
    final values = <double>{min, half, max}.toList()..sort();
    return values;
  }
}

/// Phone sheet: about one third collapsed, half initially, max under the app bar.
///
/// Sizes stay independent of the keyboard so opening it does not lock or reset
/// the sheet. The scaffold already shrinks the body with view insets.
CustomerBookingSheetSizes customerBookingSheetSizes({
  required double height,
  required bool keyboardOpen,
  double textScale = 1,
}) {
  final scale = textScale.clamp(1.0, 1.6);
  final safeHeight = height < 1 ? 1.0 : height;
  final short = safeHeight < 520;
  final reservedMap = short ? (safeHeight * 0.30).clamp(72.0, 130.0) : 8.0;
  final maxSize = (1.0 - reservedMap / safeHeight).clamp(
    short ? 0.68 : 0.88,
    1.0,
  );
  var minSize = (0.34 * scale).clamp(0.30, maxSize - 0.18);
  if (minSize > maxSize - 0.18) {
    minSize = (maxSize - 0.18).clamp(0.28, maxSize);
  }
  final halfSize = 0.50.clamp(minSize + 0.04, maxSize - 0.08);
  return CustomerBookingSheetSizes(
    min: minSize,
    half: halfSize,
    max: maxSize,
    initial: halfSize,
  );
}

CustomerBookingSheetLevel customerBookingSheetLevel(
  double extent,
  CustomerBookingSheetSizes sizes,
) {
  final compactCut = (sizes.min + sizes.half) / 2;
  final expandCut = (sizes.half + sizes.max) / 2;
  if (extent < compactCut) return CustomerBookingSheetLevel.compact;
  if (extent < expandCut) return CustomerBookingSheetLevel.half;
  return CustomerBookingSheetLevel.expanded;
}

bool customerBookingSheetShowsDetails(
  double extent,
  CustomerBookingSheetSizes sizes,
) {
  return true;
}

bool customerBookingSheetAllowsScroll(
  double extent,
  CustomerBookingSheetSizes sizes,
) {
  return extent >= sizes.max - 0.04;
}

double customerBookingSheetSnapForLevel(
  CustomerBookingSheetLevel level,
  CustomerBookingSheetSizes sizes,
) {
  switch (level) {
    case CustomerBookingSheetLevel.compact:
      return sizes.min;
    case CustomerBookingSheetLevel.half:
      return sizes.half;
    case CustomerBookingSheetLevel.expanded:
      return sizes.max;
  }
}

CustomerBookingSheetLevel customerBookingSheetNextLevel(
  CustomerBookingSheetLevel level,
) {
  switch (level) {
    case CustomerBookingSheetLevel.compact:
      return CustomerBookingSheetLevel.half;
    case CustomerBookingSheetLevel.half:
      return CustomerBookingSheetLevel.expanded;
    case CustomerBookingSheetLevel.expanded:
      return CustomerBookingSheetLevel.compact;
  }
}

EdgeInsets customerBookingMapFitInsets({
  required bool wide,
  required double height,
  required double sheetExtent,
}) {
  if (wide) {
    return const EdgeInsets.fromLTRB(40, 64, 40, 72);
  }
  final bottom = (height * sheetExtent).clamp(72.0, height - 96.0);
  return EdgeInsets.fromLTRB(20, 64, 20, bottom + 12);
}

String customerBookingCompactAddressLabel(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  final comma = trimmed.split(',');
  return comma.first.trim();
}
