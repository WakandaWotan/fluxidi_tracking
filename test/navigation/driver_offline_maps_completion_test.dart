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

  test('completed but StylePack proven incomplete → completedWithErrors', () {
    expect(
      resolve(verified: false),
      DriverOfflineMapCompletionStatus.completedWithErrors,
    );
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
