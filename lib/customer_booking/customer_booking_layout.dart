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
