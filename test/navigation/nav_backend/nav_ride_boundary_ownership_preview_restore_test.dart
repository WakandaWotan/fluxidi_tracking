import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/nav_ride_boundary_ownership.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 (Problem A) unit tests.
//
// Pins the widened `evaluateStyleRouteRestore` contract: a pre-start preview
// draft that owns the current route is restore-eligible after a style swap
// even though `navigationLive` is false. Every other guard (session, style,
// render-epoch, route-version, package owner) must keep rejecting exactly as
// before so live-ride ownership is never widened by the preview path.

NavRouteOwnershipCapture _capture({
  int sessionGeneration = 1,
  int styleGeneration = 1,
  int routeVersion = 1,
  int renderEpoch = 1,
  bool navigationLive = false,
  int routeCoordCount = 12,
  bool previewRestoreEligible = false,
}) {
  return NavRouteOwnershipCapture(
    sessionGeneration: sessionGeneration,
    styleGeneration: styleGeneration,
    routeVersion: routeVersion,
    renderEpoch: renderEpoch,
    navigationLive: navigationLive,
    routeCoordCount: routeCoordCount,
    previewRestoreEligible: previewRestoreEligible,
  );
}

NavRouteOwnershipSnapshot _snapshot({
  int sessionGeneration = 1,
  int styleGeneration = 1,
  int routeVersion = 1,
  int renderEpoch = 1,
  bool navigationLive = false,
  int? activePackageSessionGeneration,
  int? activePackageRenderEpoch,
  bool previewRestoreEligible = false,
}) {
  return NavRouteOwnershipSnapshot(
    sessionGeneration: sessionGeneration,
    styleGeneration: styleGeneration,
    routeVersion: routeVersion,
    renderEpoch: renderEpoch,
    navigationLive: navigationLive,
    activePackageSessionGeneration: activePackageSessionGeneration,
    activePackageRenderEpoch: activePackageRenderEpoch,
    previewRestoreEligible: previewRestoreEligible,
  );
}

void main() {
  group('evaluateStyleRouteRestore - preview draft eligibility', () {
    test('legacy pre-start non-eligible capture still rejects (regression)', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(),
        current: _snapshot(),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.navigationNotLive);
    });

    test('preview-eligible on both sides: restore allowed', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(previewRestoreEligible: true),
        current: _snapshot(previewRestoreEligible: true),
      );
      expect(decision.allowed, isTrue);
      expect(decision.reason, isNull);
    });

    test('capture preview-eligible but live snapshot no-longer valid: reject', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(previewRestoreEligible: true),
        current: _snapshot(previewRestoreEligible: false),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.navigationNotLive);
    });

    test('live navigation still allowed regardless of preview flag', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(navigationLive: true),
        current: _snapshot(navigationLive: true),
      );
      expect(decision.allowed, isTrue);
    });

    test('preview + live mixture still allowed', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(navigationLive: true),
        current: _snapshot(previewRestoreEligible: true),
      );
      expect(decision.allowed, isTrue);
    });

    test('preview eligible but session generation mismatch: reject', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          sessionGeneration: 1,
          previewRestoreEligible: true,
        ),
        current: _snapshot(
          sessionGeneration: 2,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.sessionMismatch);
    });

    test('preview eligible but style generation mismatch: reject', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          styleGeneration: 1,
          previewRestoreEligible: true,
        ),
        current: _snapshot(
          styleGeneration: 2,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.styleMismatch);
    });

    test('preview eligible but render epoch bumped mid-swap: reject', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          renderEpoch: 1,
          previewRestoreEligible: true,
        ),
        current: _snapshot(
          renderEpoch: 2,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.renderEpochMismatch);
    });

    test('preview eligible but route version bumped mid-swap: reject', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          routeVersion: 1,
          previewRestoreEligible: true,
        ),
        current: _snapshot(
          routeVersion: 2,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.routeVersionMismatch);
    });

    test('preview eligible but empty geometry: reject with emptyGeometry', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          routeCoordCount: 1,
          previewRestoreEligible: true,
        ),
        current: _snapshot(previewRestoreEligible: true),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.emptyGeometry);
    });

    test('preview eligible but package owner mismatch: reject', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          sessionGeneration: 1,
          renderEpoch: 1,
          previewRestoreEligible: true,
        ),
        current: _snapshot(
          sessionGeneration: 1,
          renderEpoch: 1,
          activePackageSessionGeneration: 2,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.packageOwnerMismatch);
    });

    // NAV-PIP-PLANNED-COMPLETION-EVIDENCE-FIX-P0 (C): prepared_route style
    // swaps must restore via the same previewRestoreEligible gate used for
    // fixed street-level booking drafts (not live-only).
    test('prepared_route 2D→3D style swap keeps restore eligible', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          navigationLive: false,
          previewRestoreEligible: true,
          routeCoordCount: 12,
        ),
        current: _snapshot(
          navigationLive: false,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isTrue);
    });

    test('prepared_route 3D→satellite style swap keeps restore eligible', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          navigationLive: false,
          previewRestoreEligible: true,
          routeCoordCount: 8,
        ),
        current: _snapshot(
          navigationLive: false,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isTrue);
    });

    test('satellite→navigation style keeps restore eligible in prepared_route', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          navigationLive: false,
          previewRestoreEligible: true,
          routeCoordCount: 20,
        ),
        current: _snapshot(
          navigationLive: false,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isTrue);
    });

    test('stale prior-session prepared restore remains rejected', () {
      final decision = evaluateStyleRouteRestore(
        capture: _capture(
          sessionGeneration: 3,
          previewRestoreEligible: true,
          routeCoordCount: 10,
        ),
        current: _snapshot(
          sessionGeneration: 4,
          previewRestoreEligible: true,
        ),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, StyleRestoreRejectReason.sessionMismatch);
    });
  });
}
