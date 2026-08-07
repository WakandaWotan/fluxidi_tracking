// FLUXIDI-OFFLINE-MAP-DOWNLOAD-SILENT-NOOP-P0-1
//
// The offline download CTA used to fail silently. These tests pin the feedback
// contract: every failure maps to one bounded localized message, diagnostics
// stay PII-safe, and no CTA state is a no-op.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_download_feedback.dart';

void main() {
  group('failure classification', () {
    test('a stalled estimate is reported as estimate-unavailable', () {
      expect(
        classifyDriverOfflineMapFailure(
          error: TimeoutException('x'),
          phase: 'estimate',
        ),
        DriverOfflineMapFailureCategory.estimateUnavailable,
      );
    });

    test('a stalled init is reported as a configuration problem', () {
      expect(
        classifyDriverOfflineMapFailure(
          error: TimeoutException('x'),
          phase: 'init',
        ),
        DriverOfflineMapFailureCategory.mapboxConfiguration,
      );
    });

    test('a stalled download is reported as interrupted', () {
      expect(
        classifyDriverOfflineMapFailure(
          error: TimeoutException('x'),
          phase: 'download',
        ),
        DriverOfflineMapFailureCategory.interrupted,
      );
    });

    test('a socket failure is reported as no internet', () {
      expect(
        classifyDriverOfflineMapFailure(
          error: const SocketException('no route'),
          phase: 'estimate',
        ),
        DriverOfflineMapFailureCategory.noInternet,
      );
    });

    test('a missing Mapbox token wins over every other signal', () {
      expect(
        classifyDriverOfflineMapFailure(
          error: const SocketException('no route'),
          phase: 'download',
          mapboxConfigured: false,
        ),
        DriverOfflineMapFailureCategory.mapboxConfiguration,
      );
    });

    test('SDK messages map onto their own categories', () {
      final cases = <String, DriverOfflineMapFailureCategory>{
        'HTTP 401 Unauthorized access token':
            DriverOfflineMapFailureCategory.mapboxConfiguration,
        'Failed host lookup: api.mapbox.com':
            DriverOfflineMapFailureCategory.noInternet,
        'ENOSPC: no space left on device':
            DriverOfflineMapFailureCategory.insufficientStorage,
        'tile count exceeds the allowed limit':
            DriverOfflineMapFailureCategory.regionTooLarge,
        'invalid coordinate in geometry':
            DriverOfflineMapFailureCategory.invalidGeometry,
        'network restriction disallows expensive connections':
            DriverOfflineMapFailureCategory.wifiOnlyRestricted,
        'StylePack load failed': DriverOfflineMapFailureCategory.stylePackFailure,
        'TileRegion resource error':
            DriverOfflineMapFailureCategory.tileRegionResourceError,
        'operation was cancelled': DriverOfflineMapFailureCategory.interrupted,
      };
      cases.forEach((message, expected) {
        expect(
          classifyDriverOfflineMapFailure(error: message, phase: 'download'),
          expected,
          reason: 'message "$message" must classify as $expected',
        );
      });
    });

    test('an unrecognized failure still maps to a phase-appropriate category', () {
      expect(
        classifyDriverOfflineMapFailure(error: Object(), phase: 'estimate'),
        DriverOfflineMapFailureCategory.estimateUnavailable,
      );
      expect(
        classifyDriverOfflineMapFailure(error: Object(), phase: ''),
        DriverOfflineMapFailureCategory.unknown,
      );
    });

    test('nested phase=stylePack / tileRegion beat wrapper download phase', () {
      expect(
        classifyDriverOfflineMapFailure(
          error:
              'DriverOfflineMapsException: StylePack load failed. phase=stylePack',
          phase: 'download',
        ),
        DriverOfflineMapFailureCategory.stylePackFailure,
      );
      expect(
        classifyDriverOfflineMapFailure(
          error:
              'DriverOfflineMapsException: TileRegion load failed. phase=tileRegion',
          phase: 'download',
        ),
        DriverOfflineMapFailureCategory.tileRegionResourceError,
      );
    });
  });

  group('localized messages', () {
    test('the no-selection instruction is the exact approved NL wording', () {
      expect(
        driverOfflineMapFailureMessage(
          category: DriverOfflineMapFailureCategory.noSelection,
          language: AppLanguage.nl,
        ),
        'Selecteer eerst een plaats.',
      );
    });

    test('every category has a bounded non-empty message in every language', () {
      for (final category in DriverOfflineMapFailureCategory.values) {
        for (final language in AppLanguage.values) {
          final message = driverOfflineMapFailureMessage(
            category: category,
            language: language,
          );
          expect(message.trim(), isNotEmpty, reason: '$category/$language');
          expect(
            message.length,
            lessThanOrEqualTo(160),
            reason: '$category/$language must stay bounded',
          );
        }
      }
    });

    test('the Wi-Fi-only message explains why the download did not start', () {
      final message = driverOfflineMapFailureMessage(
        category: DriverOfflineMapFailureCategory.wifiOnlyRestricted,
        language: AppLanguage.nl,
      );
      expect(message, contains('niet gestart'));
      expect(message, contains('wifi'));
    });

    test('no message leaks a token, a path or an exception class name', () {
      for (final category in DriverOfflineMapFailureCategory.values) {
        for (final language in AppLanguage.values) {
          final message = driverOfflineMapFailureMessage(
            category: category,
            language: language,
          );
          expect(message, isNot(contains('pk.')));
          expect(message, isNot(contains('sk.')));
          expect(message, isNot(contains('access_token')));
          expect(message, isNot(contains('Exception')));
          expect(message, isNot(contains('mapbox')));
          expect(message, isNot(contains('/')));
        }
      }
    });
  });

  group('diagnostic redaction', () {
    test('access tokens are redacted from any diagnostic text', () {
      final redacted = redactDriverOfflineMapDiagnostic(
        'GET https://api.mapbox.com/v1?access_token=pk.eyJhbGciOiJIUzI1NiJ9abc',
      );
      expect(redacted, isNot(contains('pk.eyJ')));
      expect(redacted, contains('[redacted]'));
    });

    test('bearer tokens and secret keys are redacted', () {
      expect(
        redactDriverOfflineMapDiagnostic('Authorization: Bearer abc.def-123'),
        isNot(contains('abc.def-123')),
      );
      expect(
        redactDriverOfflineMapDiagnostic('sk.secretvalue12345'),
        contains('[redacted-token]'),
      );
    });
  });

  group('PII-safe diagnostics', () {
    test('the region id is hashed, never emitted verbatim', () {
      const regionId = 'fluxidi_driver_region_ronse_be_r20_n5075_e357_11_16';
      final line = buildDriverOfflineMapDiagnostic(
        phase: 'download_start',
        regionId: regionId,
        radiusKm: 20,
      );
      expect(line, isNot(contains('ronse')));
      expect(line, contains(driverOfflineMapRegionIdHash(regionId)));
      expect(line, contains('radius=20km'));
    });

    test('the hash is deterministic and distinguishes regions', () {
      const a = 'fluxidi_driver_region_ronse_be_r20_n5075_e357_11_16';
      const b = 'fluxidi_driver_region_ronse_be_r40_n5075_e357_11_16';
      expect(driverOfflineMapRegionIdHash(a), driverOfflineMapRegionIdHash(a));
      expect(
        driverOfflineMapRegionIdHash(a),
        isNot(driverOfflineMapRegionIdHash(b)),
      );
      expect(driverOfflineMapRegionIdHash(''), 'none');
    });

    test('the line carries phase, category, counts and completion state', () {
      final line = buildDriverOfflineMapDiagnostic(
        phase: 'download_done',
        regionId: 'region_x',
        radiusKm: 40,
        category: DriverOfflineMapFailureCategory.tileRegionResourceError,
        completedResourceCount: 120,
        requiredResourceCount: 120,
        erroredResourceCount: 3,
        completionState: 'completed_with_errors',
      );
      expect(line, contains('phase=download_done'));
      expect(line, contains('category=tile_region_resource_error'));
      expect(line, contains('completed=120'));
      expect(line, contains('required=120'));
      expect(line, contains('errored=3'));
      expect(line, contains('completion=completed_with_errors'));
    });

    test('missing values render as placeholders, never as null text', () {
      final line = buildDriverOfflineMapDiagnostic(
        phase: 'cta',
        regionId: '',
      );
      expect(line, isNot(contains('null')));
      expect(line, contains('radius=-'));
      expect(line, contains('category=-'));
      expect(line, contains('completion=-'));
    });

    test('every failure category has a stable snake_case token', () {
      final tokens = <String>{};
      for (final category in DriverOfflineMapFailureCategory.values) {
        final token = driverOfflineMapFailureCategoryToken(category);
        expect(token, matches(RegExp(r'^[a-z][a-z_]*$')));
        expect(tokens.add(token), isTrue, reason: 'duplicate token $token');
      }
    });
  });

  group('CTA state', () {
    test('no selection is tappable so it can explain itself', () {
      final state = resolveDriverOfflineMapCtaState(
        hasSelection: false,
        estimateInProgress: false,
        downloadInProgress: false,
      );
      expect(state, DriverOfflineMapCtaState.needsSelection);
      expect(driverOfflineMapCtaIsTappable(state), isTrue);
    });

    test('a selection makes the CTA ready', () {
      expect(
        resolveDriverOfflineMapCtaState(
          hasSelection: true,
          estimateInProgress: false,
          downloadInProgress: false,
        ),
        DriverOfflineMapCtaState.ready,
      );
    });

    test('in-flight work reports progress and is not tappable', () {
      final estimating = resolveDriverOfflineMapCtaState(
        hasSelection: true,
        estimateInProgress: true,
        downloadInProgress: false,
      );
      final downloading = resolveDriverOfflineMapCtaState(
        hasSelection: true,
        estimateInProgress: false,
        downloadInProgress: true,
      );
      expect(estimating, DriverOfflineMapCtaState.estimating);
      expect(downloading, DriverOfflineMapCtaState.downloading);
      expect(driverOfflineMapCtaIsTappable(estimating), isFalse);
      expect(driverOfflineMapCtaIsTappable(downloading), isFalse);
    });

    test('downloading outranks estimating', () {
      expect(
        resolveDriverOfflineMapCtaState(
          hasSelection: true,
          estimateInProgress: true,
          downloadInProgress: true,
        ),
        DriverOfflineMapCtaState.downloading,
      );
    });
  });

  group('stale selection detection', () {
    test('a selection present in fresh results is kept', () {
      expect(
        driverOfflineMapSelectionStillListed(
          selectedFeatureId: 'place.123',
          selectedPrimaryName: 'Ronse',
          resultFeatureIds: const <String>['place.999', 'place.123'],
          resultPrimaryNames: const <String>['Roeselare', 'Ronse'],
        ),
        isTrue,
      );
    });

    test('a selection absent from fresh results is dropped', () {
      expect(
        driverOfflineMapSelectionStillListed(
          selectedFeatureId: 'place.123',
          selectedPrimaryName: 'Ronse',
          resultFeatureIds: const <String>['place.999'],
          resultPrimaryNames: const <String>['Roeselare'],
        ),
        isFalse,
      );
    });

    test('falls back to the place name when no feature id exists', () {
      expect(
        driverOfflineMapSelectionStillListed(
          selectedFeatureId: '',
          selectedPrimaryName: 'ronse',
          resultFeatureIds: const <String>[],
          resultPrimaryNames: const <String>['Ronse'],
        ),
        isTrue,
      );
      expect(
        driverOfflineMapSelectionStillListed(
          selectedFeatureId: '',
          selectedPrimaryName: '',
          resultFeatureIds: const <String>[],
          resultPrimaryNames: const <String>['Ronse'],
        ),
        isFalse,
      );
    });

    test('an empty result list always drops the selection', () {
      expect(
        driverOfflineMapSelectionStillListed(
          selectedFeatureId: 'place.123',
          selectedPrimaryName: 'Ronse',
          resultFeatureIds: const <String>[],
          resultPrimaryNames: const <String>[],
        ),
        isFalse,
      );
    });
  });

  group('timeout bounds', () {
    test('the estimate and init waits are bounded and short', () {
      expect(kDriverOfflineMapEstimateTimeout.inSeconds, inInclusiveRange(5, 20));
      expect(kDriverOfflineMapInitTimeout.inSeconds, inInclusiveRange(3, 15));
    });
  });
}
