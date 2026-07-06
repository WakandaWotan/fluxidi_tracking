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

/// Derives UI state from local nav readiness only (no network detection).
class NavR9OfflineReadiness {
  static const double _predictionLowConfidence = 55.0;

  static ({
    NavR9OfflineUiState state,
    String reason,
    bool showTunnelChip,
    bool showGpsReacquireChip,
  }) derive({
    required bool liveRideActive,
    required bool followNavActive,
    required bool localRouteReady,
    required bool predictionActive,
    required double? predictionConfidence,
    required bool weakGps,
  }) {
    if (!liveRideActive || !followNavActive) {
      return (
        state: NavR9OfflineUiState.placeholder,
        reason: 'inactive_nav',
        showTunnelChip: false,
        showGpsReacquireChip: false,
      );
    }

    if (predictionActive) {
      final lowConfidence =
          (predictionConfidence ?? 0.0) < _predictionLowConfidence || weakGps;
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
        reason: 'r7_prediction_active',
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
