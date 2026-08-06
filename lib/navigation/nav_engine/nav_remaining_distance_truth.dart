// NAVIGATION-SINGLE-ACTIVE-TARGET-TRUTH-P0-5
//
// ETA / remaining KM must come from the current route to the active target.
// Missing route distance never becomes 0.0 km or <1 min.

/// Resolved remaining distance for HUD / PiP / arrival.
class NavRemainingDistanceTruth {
  const NavRemainingDistanceTruth({
    required this.routeReady,
    this.remainingMeters,
    this.remainingSeconds,
    this.source = 'none',
  });

  final bool routeReady;
  final double? remainingMeters;
  final int? remainingSeconds;
  final String source;

  double? get remainingKm {
    final m = remainingMeters;
    if (m == null || !m.isFinite || m < 0) return null;
    return m / 1000.0;
  }
}

/// Prefer along-route remaining when route + progress belong to the active
/// target. Never invent 0 from null.
NavRemainingDistanceTruth resolveNavRemainingDistanceTruth({
  required bool activeTargetValid,
  required String? activeRouteId,
  required String? progressRouteId,
  required double? routeLengthMeters,
  required double? distanceAlongRouteMeters,
  required double? fallbackRemainingKmFromOdometer,
  required int? routeDurationSec,
  required double? kmDriven,
  required bool trackingCountdownStarted,
}) {
  if (!activeTargetValid) {
    return const NavRemainingDistanceTruth(routeReady: false, source: 'no_target');
  }

  final routeLen = routeLengthMeters;
  final routeId = (activeRouteId ?? '').trim();
  final progressId = (progressRouteId ?? '').trim();
  final progressBelongs =
      routeId.isEmpty || progressId.isEmpty || routeId == progressId;

  if (routeLen != null &&
      routeLen.isFinite &&
      routeLen > 1.0 &&
      progressBelongs &&
      distanceAlongRouteMeters != null &&
      distanceAlongRouteMeters.isFinite) {
    final remainingM =
        (routeLen - distanceAlongRouteMeters).clamp(0.0, routeLen);
    int? remainingSec;
    if (routeDurationSec != null &&
        routeDurationSec > 0 &&
        routeLen > 1.0) {
      final frac = (remainingM / routeLen).clamp(0.0, 1.0);
      remainingSec = (routeDurationSec * frac).round();
    }
    return NavRemainingDistanceTruth(
      routeReady: true,
      remainingMeters: remainingM,
      remainingSeconds: remainingSec,
      source: 'route_progress',
    );
  }

  if (routeLen != null && routeLen.isFinite && routeLen > 1.0) {
    // Route known but progress not yet — full remaining, never 0.
    final drivenM = ((kmDriven ?? 0.0).clamp(0.0, double.infinity)) * 1000.0;
    final remainingM = trackingCountdownStarted
        ? (routeLen - drivenM).clamp(0.0, routeLen)
        : routeLen;
    int? remainingSec;
    if (routeDurationSec != null && routeDurationSec > 0) {
      final frac = (remainingM / routeLen).clamp(0.0, 1.0);
      remainingSec = (routeDurationSec * frac).round();
    }
    return NavRemainingDistanceTruth(
      routeReady: true,
      remainingMeters: remainingM,
      remainingSeconds: remainingSec,
      source: 'route_length',
    );
  }

  final fallbackKm = fallbackRemainingKmFromOdometer;
  if (fallbackKm != null && fallbackKm.isFinite && fallbackKm > 0.05) {
    return NavRemainingDistanceTruth(
      routeReady: true,
      remainingMeters: fallbackKm * 1000.0,
      remainingSeconds: routeDurationSec,
      source: 'odometer_fallback',
    );
  }

  return const NavRemainingDistanceTruth(
    routeReady: false,
    source: 'missing_route',
  );
}

/// HUD KM text. Missing route → em-dash / empty, never fake 0.0.
String formatNavRemainingKmText(NavRemainingDistanceTruth truth) {
  if (!truth.routeReady) return '';
  final km = truth.remainingKm;
  if (km == null || !km.isFinite) return '';
  if (km < 0.05) return '0.0';
  return km.toStringAsFixed(1);
}

/// HUD ETA text. Missing route → empty (callers show —). Never `<1 min` while
/// loading.
String formatNavEtaText(NavRemainingDistanceTruth truth) {
  if (!truth.routeReady) return '';
  final sec = truth.remainingSeconds;
  if (sec == null || sec < 0) return '';
  if (sec < 60) return '<1 min';
  final minutes = (sec / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
