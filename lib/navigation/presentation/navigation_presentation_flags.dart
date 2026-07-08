/// Dart-define key for the NAV-PRES-2A driver HUD overlay.
const String kNavigationDriverHudOverlayDefineKey =
    'FLUXIDI_NAV_DRIVER_HUD_OVERLAY';

/// NAV-PRES-2A: screen-fixed driver cockpit HUD overlay (default off).
///
/// Enable at build time:
/// `--dart-define=FLUXIDI_NAV_DRIVER_HUD_OVERLAY=true`
const bool kNavigationDriverHudOverlayEnabled = bool.fromEnvironment(
  kNavigationDriverHudOverlayDefineKey,
  defaultValue: false,
);
