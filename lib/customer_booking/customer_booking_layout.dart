import 'package:flutter/painting.dart';

/// Layout rules for the customer booking sheet.
///
/// Split form/map only when both width and text scale leave two usable panes.
/// A short window or an open keyboard must not pin the confirm action.
bool customerBookingUseWideSplit({
  required double width,
  required double height,
  double textScale = 1,
}) {
  final scale = textScale.clamp(1.0, 2.0);
  final neededWidth = 720 * (scale > 1.2 ? scale : 1.0);
  return width >= neededWidth && height >= 420 && scale <= 1.55;
}

bool customerBookingPinConfirmBar({
  required double height,
  required bool keyboardOpen,
  double textScale = 1,
}) {
  if (keyboardOpen) return false;
  if (textScale >= 1.35) return false;
  return height >= 560;
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

class CustomerBookingSheetSizes {
  const CustomerBookingSheetSizes({
    required this.min,
    required this.max,
    required this.initial,
  });

  final double min;
  final double max;
  final double initial;

  List<double> get snaps => <double>[min, max];
}

/// Phone sheet keeps about 25–30% of the usable height for the map.
CustomerBookingSheetSizes customerBookingSheetSizes({
  required double height,
  required bool keyboardOpen,
  double textScale = 1,
}) {
  final scale = textScale.clamp(1.0, 1.6);
  final safeHeight = height < 1 ? 1.0 : height;
  final mapShare = keyboardOpen
      ? 0.18
      : (scale >= 1.35 ? 0.26 : 0.28);
  final maxSize = (1 - mapShare).clamp(0.55, 0.75);
  final compactPx = (keyboardOpen ? 280.0 : 430.0) * scale;
  final minSize = (compactPx / safeHeight).clamp(0.36, maxSize - 0.10);
  return CustomerBookingSheetSizes(
    min: minSize,
    max: maxSize,
    initial: minSize,
  );
}

bool customerBookingSheetShowsDetails(double extent, CustomerBookingSheetSizes sizes) {
  return extent >= (sizes.min + sizes.max) / 2;
}

EdgeInsets customerBookingMapFitInsets({
  required bool wide,
  required double height,
  required double sheetExtent,
}) {
  if (wide) {
    return const EdgeInsets.fromLTRB(48, 72, 48, 72);
  }
  final bottom = (height * sheetExtent).clamp(96.0, height * 0.78);
  return EdgeInsets.fromLTRB(36, 88, 36, bottom + 16);
}
