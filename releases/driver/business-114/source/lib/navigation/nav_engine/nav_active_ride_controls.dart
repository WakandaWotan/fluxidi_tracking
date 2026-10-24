// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 — Part D
//
// Pure decision helpers for the active-ride control gates. Kept side-effect
// free so the product rules ("Street Level always on START", "no manual zoom
// or style switching during an active ride") are testable independently of
// the driver page's state machine.
//
// These helpers own no widget state, no Mapbox handle, no camera lifecycle.
// They exist to say "yes/no" and "which style should we lock to for the next
// active ride" — the caller performs the actual mutation.

import 'nav_annotation_manager_lifecycle.dart' show kNavActiveRideStyleSwitchEnabled;

/// Selected active-ride navigation style (a stable, safe pair — never
/// Standard, Satellite, or a user's preview override).
///
/// The exact URI strings are owned by driver_navigation_map_config; the
/// decision here is which of the two variants to lock to.
enum NavActiveRideStyle {
  navigationDay,
  navigationNight,
}

/// PII-free label for diagnostics.
String navActiveRideStyleLabel(NavActiveRideStyle style) {
  switch (style) {
    case NavActiveRideStyle.navigationDay:
      return 'navigation-day-v1';
    case NavActiveRideStyle.navigationNight:
      return 'navigation-night-v1';
  }
}

/// Decides which fixed style the next active ride must lock to.
///
/// [prefersDark] is the current app/theme preference. The Standard/Satellite
/// preview options a driver may have chosen pre-START are DISCARDED here —
/// only the safe navigation-day/navigation-night pair is ever returned.
NavActiveRideStyle chooseNavActiveRideStyle({required bool prefersDark}) {
  return prefersDark
      ? NavActiveRideStyle.navigationNight
      : NavActiveRideStyle.navigationDay;
}

/// Outcome of the START transition style selection: which style was chosen,
/// whether the caller must ignore any prior preview zoom/camera state, and
/// whether the caller must always seed Street Level on entry.
class NavActiveRideStartDecision {
  const NavActiveRideStartDecision({
    required this.style,
    required this.enterStreetLevel,
    required this.discardPreviewZoom,
  });

  final NavActiveRideStyle style;

  /// Street Level MUST always be entered exactly once on START.
  final bool enterStreetLevel;

  /// Any pre-start manual zoom is not the active camera state.
  final bool discardPreviewZoom;
}

/// Product rule: every active ride always enters Street Level and always
/// discards any pre-start manual preview zoom. This helper returns a stable
///, testable decision object.
NavActiveRideStartDecision decideNavActiveRideStart({required bool prefersDark}) {
  return NavActiveRideStartDecision(
    style: chooseNavActiveRideStyle(prefersDark: prefersDark),
    enterStreetLevel: true,
    discardPreviewZoom: true,
  );
}

/// PII-free reason token returned by [navActiveRideStyleTapAllowed] /
/// [navActiveRideZoomAllowed] when an interaction is blocked, so field
/// diagnostics can attribute the block without printing the coordinates.
enum NavActiveRideBlockReason {
  none,
  liveRideActive,
}

/// Whether a map-style change (Satellite ↔ Street, Light ↔ Dark) is allowed
/// right now.
///
/// Product rule (final release navigation flow):
///   - not in a live ride → allowed (pre-start preview remains available);
///   - in a live ride with the kill-switch engaged
///     ([activeRideStyleSwitchEnabled] == false, the current default) →
///     blocked with reason [NavActiveRideBlockReason.liveRideActive];
///   - in a live ride with the kill-switch explicitly disabled by a test
///     ([activeRideStyleSwitchEnabled] == true) → allowed (legacy tests).
NavActiveRideBlockReason navActiveRideStyleTapAllowed({
  required bool liveRideActive,
  bool activeRideStyleSwitchEnabled = kNavActiveRideStyleSwitchEnabled,
}) {
  if (!liveRideActive) return NavActiveRideBlockReason.none;
  if (activeRideStyleSwitchEnabled) return NavActiveRideBlockReason.none;
  return NavActiveRideBlockReason.liveRideActive;
}

/// Whether a manual +/- zoom input is allowed right now.
///
/// Final release navigation flow: no manual +/- zoom before or during
/// navigation. The fixed streetlevel profile owns zoom exclusively.
NavActiveRideBlockReason navActiveRideZoomAllowed({
  required bool liveRideActive,
}) {
  // liveRideActive is retained for API stability; zoom is never allowed.
  return NavActiveRideBlockReason.liveRideActive;
}
