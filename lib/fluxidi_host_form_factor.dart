// FLUXIDI-HOST-FORM-FACTOR-P0
//
// Separates physical HOST form-factor from CURRENT WINDOW geometry.
//
// Field failure (SM-X400 + Android split-screen / PiP):
// classifying tablet vs phone from MediaQuery.window.shortestSide flipped the
// product onto the phone header + phone camera family when the pane shrank
// below 600dp — even though the physical tablet never changed.
//
// Host identity comes from FlutterView.display (logical) and/or a sticky latch.
// Window MediaQuery remains for layout widths, padding, and overflow.

import 'package:flutter/widgets.dart';

/// Logical shortest-side threshold for tablet host identity (device class).
/// Shared by native nav header/camera and external-nav PiP meter.
const double kFluxidiHostTabletShortestSide = 600;

/// Device/display logical size — independent of the current window / multi-
/// window / PiP bounds.
///
/// Field sequence on SM-X400:
/// 1) fullscreen MediaQuery ≈ sw880dp → tablet
/// 2) split/PiP window MediaQuery often shortestSide << 600 → would falsely
///    select phone if window size were used as host identity
Size fluxidiHostDeviceLogicalSizeOf(BuildContext context) {
  final view = View.of(context);
  final dpr = view.devicePixelRatio;
  if (!dpr.isFinite || dpr <= 0) {
    return MediaQuery.sizeOf(context);
  }
  final physical = view.display.size;
  if (!physical.width.isFinite ||
      !physical.height.isFinite ||
      physical.width <= 0 ||
      physical.height <= 0) {
    return MediaQuery.sizeOf(context);
  }
  return Size(physical.width / dpr, physical.height / dpr);
}

/// Resolve whether the physical host device is a tablet.
///
/// Precedence:
/// 1. sticky latched host flag (once true, stays true for the surface lifetime)
/// 2. device/display shortestSide
/// 3. window size only as last-resort unit-test / no-view fallback —
///    never prefer a shrunk multi-window pane over a proven host latch
bool resolveFluxidiHostIsTablet({
  bool? latchedHostIsTablet,
  Size? deviceSize,
  Size? windowSize,
}) {
  if (latchedHostIsTablet == true) return true;
  if (deviceSize != null) {
    return deviceSize.shortestSide >= kFluxidiHostTabletShortestSide;
  }
  if (latchedHostIsTablet == false) return false;
  if (windowSize != null) {
    return windowSize.shortestSide >= kFluxidiHostTabletShortestSide;
  }
  return false;
}

/// Sticky latch helper: once a host is known to be a tablet, never demote it
/// because the Android window shrank.
bool latchFluxidiHostIsTablet({
  required bool? previousLatch,
  required bool resolvedIsTablet,
}) {
  if (previousLatch == true) return true;
  return resolvedIsTablet;
}

/// Pure inputs for tests and call sites that already have sizes.
@immutable
class FluxidiHostFormFactor {
  const FluxidiHostFormFactor({
    required this.isTablet,
    required this.deviceLogicalSize,
  });

  final bool isTablet;
  final Size deviceLogicalSize;

  /// Window-independent tablet product identity.
  bool get hostIsTablet => isTablet;
}
