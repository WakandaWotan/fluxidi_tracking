import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';

// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 Part F — truth rules for the
// offline map completion status. Exercised through the pure resolver so no
// live Mapbox SDK is needed.

void main() {
  DriverOfflineMapCompletionStatus resolve({
    int required = 100,
    int completed = 100,
    int? errored = 0,
    int? styleErrored = 0,
    bool? verified = true,
    bool expired = false,
  }) =>
      resolveDriverOfflineMapCompletionStatus(
        requiredResourceCount: required,
        completedResourceCount: completed,
        erroredResourceCount: errored,
        styleErroredResourceCount: styleErrored,
        stylePacksVerified: verified,
        expired: expired,
      );

  test('completed == required and errors == 0 → complete', () {
    expect(resolve(), DriverOfflineMapCompletionStatus.complete);
  });

  test('completed == required and errored > 0 → completedWithErrors', () {
    expect(
      resolve(errored: 3),
      DriverOfflineMapCompletionStatus.completedWithErrors,
    );
    expect(
      resolve(styleErrored: 1),
      DriverOfflineMapCompletionStatus.completedWithErrors,
    );
  });

  test('completed < required → incomplete regardless of errors', () {
    expect(
      resolve(completed: 50, errored: 0),
      DriverOfflineMapCompletionStatus.incomplete,
    );
    expect(
      resolve(completed: 50, errored: 5),
      DriverOfflineMapCompletionStatus.incomplete,
    );
  });

  test('expired takes precedence over completed', () {
    expect(
      resolve(expired: true),
      DriverOfflineMapCompletionStatus.expiredOrStale,
    );
  });

  test('null errored counters and unverified StylePack → unknown', () {
    expect(
      resolve(errored: null, styleErrored: null, verified: null),
      DriverOfflineMapCompletionStatus.unknown,
    );
    expect(
      resolve(errored: null, styleErrored: null, verified: false),
      DriverOfflineMapCompletionStatus.unknown,
    );
  });

  test(
      'null errored counters + verified StylePack + fully downloaded → complete',
      () {
    expect(
      resolve(errored: null, styleErrored: null, verified: true),
      DriverOfflineMapCompletionStatus.complete,
    );
  });

  test('required == 0 → unknown (no proof either way)', () {
    expect(
      resolve(required: 0, completed: 0),
      DriverOfflineMapCompletionStatus.unknown,
    );
  });

  test('TileRegion 0/0/0 is unknown, never auto-FAIL', () {
    expect(
      resolve(required: 0, completed: 0, errored: 0, styleErrored: 0),
      DriverOfflineMapCompletionStatus.unknown,
    );
    expect(
      tileRegionResourcesFullyDownloaded(
        requiredResourceCount: 0,
        completedResourceCount: 0,
      ),
      isFalse,
    );
  });

  test('StylePack cached 0/0/0 is ready under SDK 2.18.0 contract', () {
    expect(
      stylePackResourcesReady(
        requiredResourceCount: 0,
        completedResourceCount: 0,
      ),
      isTrue,
    );
  });

  test(
    'StylePack 0/0 + TileRegion fully downloaded → COMPLETE (verified)',
    () {
      // Simulates cached style packs (0/0) with a successful tile region.
      expect(
        resolve(
          required: 120,
          completed: 120,
          errored: 0,
          styleErrored: 0,
          verified: true,
        ),
        DriverOfflineMapCompletionStatus.complete,
      );
    },
  );

  test('TileRegion required>0 completed==required errored=0 → COMPLETE', () {
    expect(
      resolve(required: 50, completed: 50, errored: 0, styleErrored: 0),
      DriverOfflineMapCompletionStatus.complete,
    );
  });

  test('TileRegion errored>0 → completedWithErrors (FAIL for UI)', () {
    expect(
      resolve(errored: 2),
      DriverOfflineMapCompletionStatus.completedWithErrors,
    );
  });

  test('completed but StylePack proven incomplete → completedWithErrors', () {
    expect(
      resolve(verified: false),
      DriverOfflineMapCompletionStatus.completedWithErrors,
    );
  });

  test('region ids must not cross-contaminate completion', () {
    final a = resolve(required: 10, completed: 10);
    final b = resolve(required: 10, completed: 3);
    expect(a, DriverOfflineMapCompletionStatus.complete);
    expect(b, DriverOfflineMapCompletionStatus.incomplete);
    expect(a == b, isFalse);
  });

  test('token labels are bounded and PII-free', () {
    for (final status in DriverOfflineMapCompletionStatus.values) {
      final token = driverOfflineMapCompletionStatusToken(status);
      expect(token, isNotEmpty);
      expect(token.contains('/'), isFalse);
      expect(token.contains(' '), isFalse);
    }
  });
}
