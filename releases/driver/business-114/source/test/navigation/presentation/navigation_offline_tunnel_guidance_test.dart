import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_nav_readiness.dart';

({NavR9OfflineUiState state, String reason, bool showTunnelChip,
    bool showGpsReacquireChip})
readiness({
  required bool usableInternetConnection,
  required bool predictionActive,
  required double? predictionConfidence,
  required bool weakGps,
  bool localRouteReady = true,
  int gapSinceLastEngineMs = 500,
}) {
  return NavR9OfflineReadiness.derive(
    usableInternetConnection: usableInternetConnection,
    liveRideActive: true,
    followNavActive: true,
    localRouteReady: localRouteReady,
    predictionActive: predictionActive,
    predictionConfidence: predictionConfidence,
    weakGps: weakGps,
    gapSinceLastEngineMs: gapSinceLastEngineMs,
  );
}

void main() {
  group('NAV-OFFLINE-TUNNEL-GUIDANCE-NETWORK-GATE-1', () {
    test('1. usable internet plus tunnel signal keeps offline guidance off', () {
      final result = readiness(
        usableInternetConnection: true,
        predictionActive: true,
        predictionConfidence: 90,
        weakGps: true,
      );
      expect(result.showTunnelChip, isFalse);
      expect(result.showGpsReacquireChip, isFalse);
      expect(result.reason, 'usable_internet');
    });

    test('2. usable internet plus low confidence keeps guidance off', () {
      final result = readiness(
        usableInternetConnection: true,
        predictionActive: true,
        predictionConfidence: 10,
        weakGps: true,
      );
      expect(result.showTunnelChip, isFalse);
      expect(result.showGpsReacquireChip, isFalse);
      expect(result.reason, 'usable_internet');
    });

    test('3. no internet plus tunnel conditions may activate guidance', () {
      final result = readiness(
        usableInternetConnection: false,
        predictionActive: true,
        predictionConfidence: 90,
        weakGps: true,
      );
      expect(result.showTunnelChip, isTrue);
      expect(result.showGpsReacquireChip, isFalse);
      expect(result.reason, 'r7_tunnel_or_weak_gps');
    });

    test('4. no internet on a normal route follows existing local rules', () {
      final result = readiness(
        usableInternetConnection: false,
        predictionActive: false,
        predictionConfidence: null,
        weakGps: false,
      );
      expect(result.state, NavR9OfflineUiState.ready);
      expect(result.showTunnelChip, isFalse);
      expect(result.reason, 'local_route_guidance');
    });

    test('5. internet restoration stops guidance immediately', () {
      final offline = readiness(
        usableInternetConnection: false,
        predictionActive: true,
        predictionConfidence: 90,
        weakGps: true,
      );
      final restored = readiness(
        usableInternetConnection: true,
        predictionActive: true,
        predictionConfidence: 90,
        weakGps: true,
      );
      expect(offline.showTunnelChip, isTrue);
      expect(restored.showTunnelChip, isFalse);
      expect(restored.reason, 'usable_internet');
    });

    test('6. backend timeout signals cannot activate guidance while online', () {
      // No backend status is an input: only authoritative reachability may
      // open the offline gate, so an otherwise degraded local prediction
      // remains suppressed while internet is usable.
      final result = readiness(
        usableInternetConnection: true,
        predictionActive: true,
        predictionConfidence: 90,
        weakGps: true,
        gapSinceLastEngineMs: 10 * 1000,
      );
      expect(result.showTunnelChip, isFalse);
      expect(result.reason, 'usable_internet');
    });
  });
}
