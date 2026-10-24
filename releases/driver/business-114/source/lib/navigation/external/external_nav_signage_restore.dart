// GOOGLE-MAPS-NAV-RETURN-SIGNAGE-RESTORE-P1
//
// Pure decision helpers for restoring Fluxidi maneuver signage when the driver
// returns from Google Maps / PiP to full NAV FLX. Network/UI I/O stays in
// DriverHomePageState.

import 'external_navigation_session.dart';

/// Why Fluxidi NAV signage must be restored.
enum ExternalNavSignageRestoreTrigger {
  /// Android PiP expanded / driver returned to full Fluxidi UI.
  pipReturnToFluxidi,

  /// External Google Maps session ended (switch back to Fluxidi NAV).
  endExternalSession,
}

/// Plan applied on return from Google Maps → NAV FLX.
class ExternalNavSignageRestoreDecision {
  const ExternalNavSignageRestoreDecision({
    required this.unsuppressNativeGuidance,
    required this.restoreNavigationGuidanceActive,
    required this.rehydrateManeuverFromCurrentState,
  });

  /// Clear [ExternalNavigationSession.nativeGuidanceSuppressed] so
  /// [shouldSuppressNativeGuidance] no longer hides the banner HUD.
  final bool unsuppressNativeGuidance;

  /// Re-enable `_navigationGuidanceActive` without recreating MapWidget /
  /// clearing the route.
  final bool restoreNavigationGuidanceActive;

  /// Immediately rebuild presentation from current route + last GPS.
  final bool rehydrateManeuverFromCurrentState;
}

/// While Google Maps owns guidance, Fluxidi must hide the banner — but must
/// NOT wipe `_navInstructionSnapshot` / owner progress. Clearing those fields
/// is what left NAV FLX without signage after return.
bool shouldClearManeuverPresentationWhileSuppressed() => false;

/// Whether returning from external navigation should restore Fluxidi signage.
ExternalNavSignageRestoreDecision decideExternalNavSignageRestore({
  required ExternalNavSignageRestoreTrigger trigger,
  required bool liveRideActive,
  required bool cameraFollow,
  required bool hadExternalSession,
}) {
  if (!hadExternalSession) {
    return const ExternalNavSignageRestoreDecision(
      unsuppressNativeGuidance: false,
      restoreNavigationGuidanceActive: false,
      rehydrateManeuverFromCurrentState: false,
    );
  }
  final restoreGuidance = liveRideActive || cameraFollow;
  switch (trigger) {
    case ExternalNavSignageRestoreTrigger.pipReturnToFluxidi:
      return ExternalNavSignageRestoreDecision(
        unsuppressNativeGuidance: true,
        restoreNavigationGuidanceActive: restoreGuidance,
        rehydrateManeuverFromCurrentState: restoreGuidance,
      );
    case ExternalNavSignageRestoreTrigger.endExternalSession:
      return ExternalNavSignageRestoreDecision(
        // Session is cleared entirely; suppression ends with it.
        unsuppressNativeGuidance: false,
        restoreNavigationGuidanceActive: restoreGuidance,
        rehydrateManeuverFromCurrentState: restoreGuidance,
      );
  }
}

/// Applies [decideExternalNavSignageRestore] onto a session copy.
ExternalNavigationSession? applyExternalNavSignageRestoreToSession({
  required ExternalNavigationSession? session,
  required ExternalNavSignageRestoreDecision decision,
}) {
  if (session == null) return null;
  if (!decision.unsuppressNativeGuidance) return session;
  return session.copyWith(
    pipActive: false,
    nativeGuidanceSuppressed: false,
  );
}
