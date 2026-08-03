// FLUXIDI-OFFLINE-MAP-NONFINITE-ESTIMATE-DIALOG-P0-2
//
// Field crash: `(errorMargin * 100).round()` threw
// "Unsupported operation: Infinity or NaN toInt" while building the Europe
// confirmation dialog. These unit tests lock the safe formatters.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_download_feedback.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_estimate_format.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

void main() {
  group('classifyOfflineMapEstimateNumber', () {
    test('classifies finite / nan / infinity / negative / missing', () {
      expect(
        classifyOfflineMapEstimateNumber(0.15),
        OfflineMapEstimateFiniteClass.finite,
      );
      expect(
        classifyOfflineMapEstimateNumber(double.nan),
        OfflineMapEstimateFiniteClass.nan,
      );
      expect(
        classifyOfflineMapEstimateNumber(double.infinity),
        OfflineMapEstimateFiniteClass.infinity,
      );
      expect(
        classifyOfflineMapEstimateNumber(double.negativeInfinity),
        OfflineMapEstimateFiniteClass.infinity,
      );
      expect(
        classifyOfflineMapEstimateNumber(-1),
        OfflineMapEstimateFiniteClass.negative,
      );
      expect(
        classifyOfflineMapEstimateNumber(null),
        OfflineMapEstimateFiniteClass.missing,
      );
    });
  });

  group('safe conversions never throw', () {
    test('safeOfflineMapErrorMargin rejects NaN and ±Infinity', () {
      expect(safeOfflineMapErrorMargin(0.15), 0.15);
      expect(safeOfflineMapErrorMargin(double.nan), isNull);
      expect(safeOfflineMapErrorMargin(double.infinity), isNull);
      expect(safeOfflineMapErrorMargin(double.negativeInfinity), isNull);
      expect(safeOfflineMapErrorMargin(-0.1), isNull);
    });

    test('safeOfflineMapNonNegativeInt rejects invalid and huge overflow', () {
      expect(safeOfflineMapNonNegativeInt(41943040), 41943040);
      expect(safeOfflineMapNonNegativeInt(-1), isNull);
      expect(safeOfflineMapNonNegativeInt(double.nan), isNull);
      expect(safeOfflineMapNonNegativeInt(double.infinity), isNull);
      // Above maxBytes → null (never overflow int conversion path).
      expect(safeOfflineMapNonNegativeInt((1 << 50) + 1), isNull);
    });

    test('zero required resources cannot divide by zero', () {
      const progress = DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.estimate,
        regionId: 'r',
        completedResourceCount: 0,
        requiredResourceCount: 0,
      );
      expect(progress.fraction, isNull);
      expect(safeOfflineMapPercent(progress.fraction), isNull);
      expect(safeOfflineMapPercent(0), 0);
      expect(safeOfflineMapPercent(double.nan), isNull);
      expect(safeOfflineMapPercent(double.infinity), isNull);
    });

    test('huge finite estimate formats without overflow', () {
      // 2 TiB transfer — still finite and below the formatter cap.
      const bytes = 2 * 1024 * 1024 * 1024 * 1024;
      final line = formatOfflineMapEstimateConfirmLine(
        language: AppLanguage.en,
        transferSizeBytes: bytes,
        storageSizeBytes: bytes,
        errorMargin: 0.1,
      );
      expect(line, contains('GB'));
      expect(line, isNot(contains('Infinity')));
      expect(line, isNot(contains('NaN')));
    });
  });

  group('formatOfflineMapEstimateConfirmLine', () {
    test('1) finite estimate renders correctly', () {
      final line = formatOfflineMapEstimateConfirmLine(
        language: AppLanguage.nl,
        transferSizeBytes: 40 * 1024 * 1024,
        storageSizeBytes: 50 * 1024 * 1024,
        errorMargin: 0.15,
      );
      expect(line, contains('Geschatte download'));
      expect(line, contains('40.0 MB'));
      expect(line, contains('50.0 MB'));
      expect(line, contains('±15%'));
    });

    test('2) NaN estimated bytes → unavailable text', () {
      expect(
        formatOfflineMapEstimateConfirmLine(
          language: AppLanguage.nl,
          transferSizeBytes: null,
          storageSizeBytes: null,
          errorMargin: double.nan,
        ),
        'Geschatte downloadgrootte niet beschikbaar',
      );
    });

    test('3) positive Infinity margin opens safely without ±%', () {
      final line = formatOfflineMapEstimateConfirmLine(
        language: AppLanguage.nl,
        transferSizeBytes: 40 * 1024 * 1024,
        storageSizeBytes: 50 * 1024 * 1024,
        errorMargin: double.infinity,
      );
      expect(line, contains('Geschatte download'));
      expect(line, isNot(contains('±')));
      expect(line, isNot(contains('Infinity')));
    });

    test('4) negative Infinity margin opens safely', () {
      final line = formatOfflineMapEstimateConfirmLine(
        language: AppLanguage.nl,
        transferSizeBytes: 40 * 1024 * 1024,
        storageSizeBytes: 50 * 1024 * 1024,
        errorMargin: double.negativeInfinity,
      );
      expect(line, contains('Geschatte download'));
      expect(line, isNot(contains('±')));
    });

    test('5) negative estimate opens safely', () {
      expect(
        formatOfflineMapEstimateConfirmLine(
          language: AppLanguage.nl,
          transferSizeBytes: -1,
          storageSizeBytes: -100,
          errorMargin: 0.15,
        ),
        'Geschatte downloadgrootte niet beschikbaar',
      );
    });

    test('6) null/missing estimate opens safely', () {
      expect(
        formatOfflineMapEstimateConfirmLine(
          language: AppLanguage.nl,
          transferSizeBytes: null,
          storageSizeBytes: null,
          errorMargin: null,
        ),
        'Geschatte downloadgrootte niet beschikbaar',
      );
    });

    test('7) zero estimate cannot produce a crash / divide-by-zero', () {
      expect(
        formatOfflineMapEstimateConfirmLine(
          language: AppLanguage.nl,
          transferSizeBytes: 0,
          storageSizeBytes: 0,
          errorMargin: 0,
        ),
        'Geschatte downloadgrootte niet beschikbaar',
      );
    });

    test('17) localized NL/EN/FR/ES fallback wording', () {
      expect(
        offlineMapEstimateUnavailableLabel(AppLanguage.nl),
        'Geschatte downloadgrootte niet beschikbaar',
      );
      expect(
        offlineMapEstimateUnavailableLabel(AppLanguage.en),
        'Estimated download size unavailable',
      );
      expect(
        offlineMapEstimateUnavailableLabel(AppLanguage.fr),
        'Taille de téléchargement estimée indisponible',
      );
      expect(
        offlineMapEstimateUnavailableLabel(AppLanguage.es),
        'Tamaño de descarga estimado no disponible',
      );
    });
  });

  group('fromSdk normalization', () {
    test('non-finite margin becomes NaN; negative bytes collapse to 0', () {
      final nan = DriverOfflineMapEstimate.fromSdk(
        mb.TileRegionEstimateResult(
          errorMargin: double.nan,
          transferSize: 100,
          storageSize: 200,
        ),
      );
      expect(nan.errorMargin.isNaN, isTrue);
      expect(nan.transferSizeBytes, 100);

      final inf = DriverOfflineMapEstimate.fromSdk(
        mb.TileRegionEstimateResult(
          errorMargin: double.infinity,
          transferSize: -5,
          storageSize: -9,
        ),
      );
      expect(inf.errorMargin.isNaN, isTrue);
      expect(inf.transferSizeBytes, 0);
      expect(inf.storageSizeBytes, 0);
    });
  });

  group('diagnostics stay PII-safe', () {
    test('18) no secrets or raw SDK errors appear', () {
      final line = buildDriverOfflineMapDiagnostic(
        phase: 'confirm_estimate',
        regionId: 'fluxidi_driver_region_europe_ronse_be_40',
        radiusKm: 40,
        estimateAvailable: true,
        estimateFinite: 'finite',
        marginFinite: 'nan',
      );
      expect(line, contains('phase=confirm_estimate'));
      expect(line, contains('margin_finite=nan'));
      expect(line, contains('estimate=yes'));
      expect(line, isNot(contains('pk.')));
      expect(line, isNot(contains('sk.')));
      expect(line, isNot(contains('http')));
      expect(line, isNot(contains('TileRegionEstimateResult')));
      expect(line, isNot(contains('access token')));
    });
  });

  group('source guard', () {
    test('9) no unguarded toInt/round on estimate margin in confirm path', () {
      final page = File('lib/navigation/driver_offline_maps_page.dart')
          .readAsStringSync();
      final format = File(
        'lib/navigation/driver_offline_maps_estimate_format.dart',
      ).readAsStringSync();
      expect(
        page.contains('estimate.errorMargin * 100'),
        isFalse,
        reason: 'field crash site must be gone from the page',
      );
      expect(
        page.contains('.errorMargin * '),
        isFalse,
        reason: 'page must not arithmetically touch errorMargin',
      );
      expect(
        page.contains('.errorMargin).round'),
        isFalse,
      );
      expect(format.contains('safeOfflineMapErrorMargin'), isTrue);
      expect(format.contains('(margin * 100).round()'), isTrue);
      expect(page.contains('formatOfflineMapEstimateConfirmLine'), isTrue);
      expect(page.contains('safeOfflineMapPercent'), isTrue);
    });
  });
}
