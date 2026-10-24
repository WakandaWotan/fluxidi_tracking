/// NAV-R9: honest offline / data-off readiness states (no network package).
enum NavR9OfflineUiState {
  /// Local route + engine context available; normal GPS guidance.
  ready,

  /// NAV-R7 prediction bridging a GPS gap.
  prediction,

  /// Prediction active but confidence weak — reacquiring GPS.
  gpsReacquire,

  /// Offline map packs / full offline nav not product-ready yet.
  placeholder,
}

/// Derives local offline/tunnel readiness.
///
/// Tunnel/offline guidance is strictly internet-gated: local prediction,
/// weak GPS and low confidence can describe why offline guidance would help,
/// but they can never surface the offline/tunnel UI while usable internet is
/// available.
class NavR9OfflineReadiness {
  static const double _predictionLowConfidence = 55.0;
  static const int _minGapForChipMs = 320;

  static ({
    NavR9OfflineUiState state,
    String reason,
    bool showTunnelChip,
    bool showGpsReacquireChip,
  }) derive({
    required bool usableInternetConnection,
    required bool liveRideActive,
    required bool followNavActive,
    required bool localRouteReady,
    required bool predictionActive,
    required double? predictionConfidence,
    required bool weakGps,
    int gapSinceLastEngineMs = 0,
  }) {
    if (!liveRideActive || !followNavActive) {
      return (
        state: NavR9OfflineUiState.placeholder,
        reason: 'inactive_nav',
        showTunnelChip: false,
        showGpsReacquireChip: false,
      );
    }

    // NAV-OFFLINE-TUNNEL-GUIDANCE-NETWORK-GATE-1: an online device must
    // never claim tunnel/offline guidance. GPS recovery remains a distinct
    // local-status signal and is intentionally not represented as a tunnel
    // chip.
    if (usableInternetConnection) {
      return (
        state: NavR9OfflineUiState.ready,
        reason: 'usable_internet',
        showTunnelChip: false,
        showGpsReacquireChip: false,
      );
    }

    if (predictionActive) {
      // Only surface chips when GPS/route trust is degraded — not during good GPS.
      if (!weakGps) {
        return (
          state: NavR9OfflineUiState.prediction,
          reason: 'r7_gap_bridge_good_gps',
          showTunnelChip: false,
          showGpsReacquireChip: false,
        );
      }
      if (gapSinceLastEngineMs < _minGapForChipMs) {
        return (
          state: NavR9OfflineUiState.ready,
          reason: 'r7_gap_too_short',
          showTunnelChip: false,
          showGpsReacquireChip: false,
        );
      }
      final lowConfidence =
          (predictionConfidence ?? 0.0) < _predictionLowConfidence;
      if (lowConfidence) {
        return (
          state: NavR9OfflineUiState.gpsReacquire,
          reason: 'prediction_low_confidence',
          showTunnelChip: false,
          showGpsReacquireChip: true,
        );
      }
      return (
        state: NavR9OfflineUiState.prediction,
        reason: 'r7_tunnel_or_weak_gps',
        showTunnelChip: true,
        showGpsReacquireChip: false,
      );
    }

    if (localRouteReady) {
      return (
        state: NavR9OfflineUiState.ready,
        reason: 'local_route_guidance',
        showTunnelChip: false,
        showGpsReacquireChip: false,
      );
    }

    return (
      state: NavR9OfflineUiState.placeholder,
      reason: 'awaiting_local_route',
      showTunnelChip: false,
      showGpsReacquireChip: false,
    );
  }

  static String logStateLabel(NavR9OfflineUiState state) {
    switch (state) {
      case NavR9OfflineUiState.ready:
        return 'ready';
      case NavR9OfflineUiState.prediction:
        return 'prediction';
      case NavR9OfflineUiState.gpsReacquire:
        return 'gps_reacquire';
      case NavR9OfflineUiState.placeholder:
        return 'placeholder';
    }
  }
}
