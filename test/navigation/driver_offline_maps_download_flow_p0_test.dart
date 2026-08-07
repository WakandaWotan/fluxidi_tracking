// FLUXIDI-OFFLINE-MAP-DOWNLOAD-SILENT-NOOP-P0-1
//
// Field failure: tapping "Voorbeeld & downloaden" (and the legacy "Downloaden"
// shortcuts) appeared to do nothing — no preview, no progress, no error. The
// cause was an unbounded await on the Mapbox size estimate: the page went busy,
// rendered nothing for that state, and never reached the confirmation dialog.
//
// These tests drive the real page against an injected port, so every tap is
// proven to end in progress, a preview, a disabled reason or an actionable error.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_download_feedback.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_europe_selection.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_page.dart';
import 'package:fluxidi_tracking/navigation/driver_offline_maps_service.dart';

const DriverOfflineEuropePlace _ronse = DriverOfflineEuropePlace(
  primaryName: 'Ronse',
  countryCode: 'be',
  countryName: 'België',
  latitude: 50.7456,
  longitude: 3.6003,
  mapboxFeatureId: 'place.ronse',
  placeType: 'place',
);

const DriverOfflineEuropePlace _lille = DriverOfflineEuropePlace(
  primaryName: 'Lille',
  countryCode: 'fr',
  countryName: 'Frankrijk',
  latitude: 50.6292,
  longitude: 3.0573,
  mapboxFeatureId: 'place.lille',
  placeType: 'place',
);

/// Records every service interaction and lets each phase be scripted.
class _FakeOfflinePort implements DriverOfflineMapsDownloadPort {
  _FakeOfflinePort({
    this.estimateError,
    this.downloadError,
    this.estimateDelay = Duration.zero,
    this.downloadDelay = Duration.zero,
    this.hangEstimate = false,
    this.completionStatus = DriverOfflineMapCompletionStatus.complete,
    this.erroredResourceCount = 0,
    this.estimateOverride,
  });

  Object? estimateError;
  Object? downloadError;
  Duration estimateDelay;
  Duration downloadDelay;
  bool hangEstimate;
  DriverOfflineMapCompletionStatus completionStatus;
  int erroredResourceCount;
  /// When set, returned instead of the finite default (tests non-finite margins).
  DriverOfflineMapEstimate? estimateOverride;

  int initCalls = 0;
  final List<DriverOfflineMapRegionRequest> estimateRequests =
      <DriverOfflineMapRegionRequest>[];
  final List<DriverOfflineMapRegionRequest> downloadRequests =
      <DriverOfflineMapRegionRequest>[];
  final List<DriverOfflineMapProgressPhase> observedPhases =
      <DriverOfflineMapProgressPhase>[];
  List<DriverOfflineMapRegionInfo> regions = const <DriverOfflineMapRegionInfo>[];

  @override
  Future<void> ensureInitialized() async {
    initCalls += 1;
  }

  @override
  Future<DriverOfflineMapEstimate> estimateRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    estimateRequests.add(request);
    if (hangEstimate) {
      // Reproduces the field no-op: a platform call that never completes.
      return Completer<DriverOfflineMapEstimate>().future;
    }
    if (estimateDelay > Duration.zero) await Future<void>.delayed(estimateDelay);
    if (estimateError != null) throw estimateError!;
    return estimateOverride ??
        const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: 0.15,
        );
  }

  @override
  Future<DriverOfflineMapRegionInfo> downloadRegion(
    DriverOfflineMapRegionRequest request, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    downloadRequests.add(request);
    // Mirrors the real service order: one style pack per style URI, then tiles.
    for (final styleUri in request.styleUris) {
      observedPhases.add(DriverOfflineMapProgressPhase.stylePack);
      onProgress?.call(
        DriverOfflineMapProgress(
          phase: DriverOfflineMapProgressPhase.stylePack,
          regionId: request.regionId,
          styleUri: styleUri,
          completedResourceCount: 5,
          requiredResourceCount: 10,
          status: 'progress',
        ),
      );
    }
    observedPhases.add(DriverOfflineMapProgressPhase.tileRegion);
    onProgress?.call(
      DriverOfflineMapProgress(
        phase: DriverOfflineMapProgressPhase.tileRegion,
        regionId: request.regionId,
        completedResourceCount: 60,
        requiredResourceCount: 120,
        status: 'progress',
      ),
    );
    if (downloadDelay > Duration.zero) await Future<void>.delayed(downloadDelay);
    if (downloadError != null) throw downloadError!;
    final info = DriverOfflineMapRegionInfo(
      id: request.regionId,
      displayName: request.displayName,
      minZoom: request.minZoom,
      maxZoom: request.maxZoom,
      styleUris: request.styleUris,
      requiredResourceCount: 120,
      completedResourceCount: 120,
      completedResourceSize: 52428800,
      completionStatus: completionStatus,
      erroredResourceCount: erroredResourceCount,
    );
    regions = <DriverOfflineMapRegionInfo>[...regions, info];
    return info;
  }

  @override
  Future<List<DriverOfflineMapRegionInfo>> listDownloadedRegions() async =>
      regions;

  @override
  Future<void> deleteRegion(
    String regionId, {
    DriverOfflineMapProgressCallback? onProgress,
  }) async {
    regions = regions.where((r) => r.id != regionId).toList();
  }
}

Future<List<DriverOfflineEuropePlace>> Function({
  required String query,
  String languageCode,
})
_searchReturning(List<DriverOfflineEuropePlace> places) {
  return ({required String query, String languageCode = 'en'}) async => places;
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeOfflinePort port,
  List<DriverOfflineEuropePlace> results = const <DriverOfflineEuropePlace>[
    _ronse,
    _lille,
  ],
  // Tall by default so the whole page is mounted and no assertion depends on
  // ListView culling. Real device sizes are exercised by the layout group.
  Size surface = const Size(400, 2600),
  bool mapboxConfigured = true,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: DriverOfflineMapsPage(
        service: port,
        mapboxConfigured: mapboxConfigured,
        placeSearch: _searchReturning(results),
        searchDebounce: Duration.zero,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Brings [finder] on screen. The offline page is a long lazily built list, so a
/// widget below the fold is neither hit-testable nor even mounted.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView),
      const Offset(0, -120),
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await _reveal(tester, finder);
  await tester.tap(finder, warnIfMissed: false);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final Finder _cta = find.byKey(const Key('offline_europe_cta'));
final Finder _confirmDownload = find.byKey(
  const Key('offline_confirm_download'),
);

Future<void> _searchAndSelectRonse(WidgetTester tester) async {
  final field = find.byKey(const Key('offline_europe_search_field'));
  await _reveal(tester, field);
  await tester.enterText(field, 'ronse');
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(const Key('offline_europe_result_Ronse')));
}

String _nl(DriverOfflineMapFailureCategory category) =>
    driverOfflineMapFailureMessage(
      category: category,
      language: AppLanguage.nl,
    );

void main() {
  setUp(() => appLanguageNotifier.value = AppLanguage.nl);
  tearDown(() => appLanguageNotifier.value = AppLanguage.en);

  group('selection is unambiguous', () {
    testWidgets('tapping a result visibly selects Ronse, België', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);

      expect(
        find.byKey(const Key('offline_europe_selection_empty')),
        findsOneWidget,
      );

      await _searchAndSelectRonse(tester);

      final summary = find.byKey(
        const Key('offline_europe_selection_summary'),
      );
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('Ronse · België')),
        findsOneWidget,
      );
      final tile = tester.widget<ListTile>(
        find.byKey(const Key('offline_europe_result_Ronse')),
      );
      expect(tile.selected, isTrue, reason: 'selected card needs a selected state');
    });

    testWidgets('the selection stays visible next to the radius controls', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      // 40 km sits below the summary; both must be describable together.
      await _tap(tester, find.text('40 km'));

      final summary = find.byKey(
        const Key('offline_europe_selection_summary'),
      );
      expect(
        find.descendant(of: summary, matching: find.text('Ronse · België')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('Straal 40 km')),
        findsOneWidget,
      );
    });

    testWidgets('the selection survives scrolling to the shortcuts', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('offline_europe_selection_summary')),
        findsOneWidget,
      );
    });

    testWidgets('changing the query clears a stale selection safely', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var results = <DriverOfflineEuropePlace>[_ronse, _lille];
      await tester.binding.setSurfaceSize(const Size(400, 2600));
      await tester.pumpWidget(
        MaterialApp(
          home: DriverOfflineMapsPage(
            service: port,
            mapboxConfigured: true,
            placeSearch:
                ({required String query, String languageCode = 'en'}) async =>
                    results,
            searchDebounce: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _searchAndSelectRonse(tester);
      expect(
        find.byKey(const Key('offline_europe_selection_summary')),
        findsOneWidget,
      );

      results = <DriverOfflineEuropePlace>[_lille];
      await tester.enterText(
        find.byKey(const Key('offline_europe_search_field')),
        'lille',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('offline_europe_selection_summary')),
        findsNothing,
        reason: 'a place absent from fresh results must not stay selected',
      );
      expect(
        find.byKey(const Key('offline_europe_selection_empty')),
        findsOneWidget,
      );
    });

    testWidgets('clearing the query clears the selection', (tester) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await tester.enterText(
        find.byKey(const Key('offline_europe_search_field')),
        '',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('offline_europe_selection_empty')),
        findsOneWidget,
      );
    });
  });

  group('the CTA can never silently return', () {
    testWidgets('with no selection it states the exact instruction', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);

      final cta = find.byKey(const Key('offline_europe_cta'));
      expect(cta, findsOneWidget, reason: 'the CTA must always be visible');
      expect(
        tester.widget<FilledButton>(cta).onPressed,
        isNotNull,
        reason: 'it must be tappable so it can explain itself',
      );

      await _tap(tester, cta, settle: false);

      expect(find.text('Selecteer eerst een plaats.'), findsWidgets);
      expect(port.estimateRequests, isEmpty);
      expect(port.downloadRequests, isEmpty);
    });

    testWidgets('a hung estimate still ends in a visible outcome', (
      tester,
    ) async {
      final port = _FakeOfflinePort(hangEstimate: true);
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await _tap(tester, _cta, settle: false);

      // While bounded work runs the driver sees progress, not a dead button.
      expect(find.byKey(const Key('offline_preparing_card')), findsOneWidget);
      expect(find.text('Voorbeeld voorbereiden…'), findsWidgets);

      await tester.pump(kDriverOfflineMapEstimateTimeout + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // The timeout releases the page and the preview still opens.
      expect(find.byKey(const Key('offline_preparing_card')), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.estimateUnavailable)),
        findsOneWidget,
      );
    });

    testWidgets('a missing Mapbox configuration is explained, not swallowed', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port, mapboxConfigured: false);
      await _searchAndSelectRonse(tester);

      await _tap(tester, _cta, settle: false);

      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.mapboxConfiguration)),
        findsWidgets,
      );
      expect(port.estimateRequests, isEmpty);
    });
  });

  group('preview and download flow', () {
    testWidgets('a valid selection opens a preview naming place, country and radius', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, find.text('40 km'));

      await _tap(tester, _cta);

      expect(find.byType(AlertDialog), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Ronse')),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('België')),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('40 km')),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Geschatte download')),
        findsWidgets,
      );
      expect(port.estimateRequests.length, 1, reason: 'estimate runs exactly once');
    });

    testWidgets(
      'confirming invokes style packs then the tile region with radius geometry',
      (tester) async {
        final port = _FakeOfflinePort();
        await _pumpPage(tester, port: port);
        await _searchAndSelectRonse(tester);
        await _tap(tester, _cta);

        await _tap(tester, _confirmDownload);

        expect(port.estimateRequests.length, 1);
        expect(port.downloadRequests.length, 1);

        // StylePack per style URI, then exactly one TileRegion.
        final request = port.downloadRequests.single;
        expect(request.styleUris.length, 2);
        expect(
          port.observedPhases
              .where((p) => p == DriverOfflineMapProgressPhase.stylePack)
              .length,
          2,
        );
        expect(
          port.observedPhases
              .where((p) => p == DriverOfflineMapProgressPhase.tileRegion)
              .length,
          1,
        );
        expect(
          port.observedPhases.last,
          DriverOfflineMapProgressPhase.tileRegion,
          reason: 'tiles are loaded after their styles',
        );

        // Geometry is the bounded radius box around the selected place.
        final expected = DriverOfflineEuropeSelection(
          place: _ronse,
          radiusKm: kDriverOfflineEuropeDefaultRadiusKm,
        );
        expect(request.geometry, expected.geometry);
        expect(request.regionId, expected.regionId);
        expect(request.minZoom, expected.minZoom);
        expect(request.maxZoom, expected.maxZoom);
      },
    );

    testWidgets('progress becomes visible and a verified download reports success', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        downloadDelay: const Duration(milliseconds: 300),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload, settle: false);

      expect(
        find.byKey(const Key('offline_download_progress_card')),
        findsOneWidget,
      );
      // With countable progress → determinate label; indeterminate uses
      // "Kaartgebied downloaden…".
      expect(find.textContaining('downloaden'), findsWidgets);
      expect(port.observedPhases, contains(DriverOfflineMapProgressPhase.tileRegion));
      expect(
        port.observedPhases.where((p) => p == DriverOfflineMapProgressPhase.stylePack).length,
        greaterThanOrEqualTo(2),
      );

      // Bounded pumps: pumpAndSettle would run past the SnackBar auto-dismiss.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(
        find.text('Kaartgebied gedownload. Status: Volledig.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Download mislukt of onderbroken'),
        findsNothing,
      );
      expect(
        find.byKey(const Key('offline_download_progress_card')),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('unknown completion is not interrupted failure snackbar', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        completionStatus: DriverOfflineMapCompletionStatus.unknown,
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload);

      expect(
        find.textContaining('Download mislukt of onderbroken'),
        findsNothing,
      );
      expect(
        find.textContaining('Status wordt geverifieerd'),
        findsOneWidget,
      );
    });

    testWidgets('resource errors prevent a clean success message', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        completionStatus: DriverOfflineMapCompletionStatus.completedWithErrors,
        erroredResourceCount: 4,
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload);

      expect(
        find.text('Kaartgebied gedownload. Status: Volledig.'),
        findsNothing,
      );
      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.tileRegionResourceError)),
        findsWidgets,
      );
    });

    testWidgets('light+dark styles are requested and tile phase is reached', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload);

      expect(port.downloadRequests, hasLength(1));
      expect(port.downloadRequests.single.styleUris, hasLength(2));
      expect(
        port.observedPhases,
        contains(DriverOfflineMapProgressPhase.tileRegion),
      );
      // Silent no-op forbidden: download must have been invoked.
      expect(port.downloadRequests, isNotEmpty);
    });

    testWidgets('a duplicate region is reported visibly and skips download', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      final existing = DriverOfflineEuropeSelection(
        place: _ronse,
        radiusKm: kDriverOfflineEuropeDefaultRadiusKm,
      );
      port.regions = <DriverOfflineMapRegionInfo>[
        DriverOfflineMapRegionInfo(
          id: existing.regionId,
          displayName: existing.displayName,
          minZoom: existing.minZoom,
          maxZoom: existing.maxZoom,
          requiredResourceCount: 120,
          completedResourceCount: 120,
          completedResourceSize: 1024,
          completionStatus: DriverOfflineMapCompletionStatus.complete,
          erroredResourceCount: 0,
        ),
      ];
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await _tap(tester, _cta, settle: false);

      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.duplicateRegion)),
        findsWidgets,
      );
      expect(port.estimateRequests, isEmpty);
      expect(port.downloadRequests, isEmpty);
    });
  });

  group('error surfacing', () {
    testWidgets('an estimate failure explains itself but still allows download', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateError: const DriverOfflineMapsException(
          'Could not estimate offline map region.',
          phase: 'estimate',
        ),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.estimateUnavailable)),
        findsOneWidget,
      );

      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1);
    });

    testWidgets('a network failure is actionable and stops before the preview', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateError: const SocketException('Failed host lookup'),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.noInternet)),
        findsWidgets,
      );
      expect(port.downloadRequests, isEmpty);
    });

    testWidgets('a Wi-Fi-only restriction explains why nothing started', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        downloadError: const DriverOfflineMapsException(
          'network restriction disallows expensive connections',
          phase: 'download',
        ),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload);

      final message = _nl(
        DriverOfflineMapFailureCategory.wifiOnlyRestricted,
      );
      expect(find.text(message), findsWidgets);
      expect(message, contains('niet gestart'));
    });

    testWidgets('insufficient storage is surfaced as its own reason', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        downloadError: const DriverOfflineMapsException(
          'ENOSPC: no space left on device',
          phase: 'download',
        ),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload);

      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.insufficientStorage)),
        findsWidgets,
      );
    });

    testWidgets('no token or raw exception text reaches the screen', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        downloadError: const DriverOfflineMapsException(
          'GET https://api.mapbox.com/v1?access_token=pk.eyJsecret123 failed',
          phase: 'download',
        ),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload);

      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final value = text.data ?? '';
        expect(value, isNot(contains('pk.eyJ')));
        expect(value, isNot(contains('access_token')));
        expect(value, isNot(contains('DriverOfflineMapsException')));
        expect(value, isNot(contains('api.mapbox.com')));
      }
    });
  });

  group('single flight and state', () {
    testWidgets('rapid taps start exactly one flow', (tester) async {
      final port = _FakeOfflinePort(
        estimateDelay: const Duration(milliseconds: 400),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await _tap(tester, _cta, settle: false);
      // Subsequent taps land while the estimate is in flight.
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(port.estimateRequests.length, 1);
      expect(find.byType(AlertDialog), findsOneWidget);

      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1, reason: 'no duplicate regions');
    });

    testWidgets('the in-flight CTA reports progress and is not tappable', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateDelay: const Duration(milliseconds: 400),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await _tap(tester, _cta, settle: false);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('offline_europe_cta')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Voorbeeld voorbereiden…'), findsWidgets);

      await tester.pumpAndSettle();
    });

    testWidgets('pause and resume preserve truthful state', (tester) async {
      final port = _FakeOfflinePort(
        downloadDelay: const Duration(milliseconds: 400),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
      await _tap(tester, _confirmDownload, settle: false);

      expect(
        find.byKey(const Key('offline_download_progress_card')),
        findsOneWidget,
      );

      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }

      expect(
        find.byKey(const Key('offline_download_progress_card')),
        findsOneWidget,
        reason: 'resume must not lose an active download',
      );
      expect(port.downloadRequests.length, 1);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(
        find.text('Kaartgebied gedownload. Status: Volledig.'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  });

  group('legacy shortcuts stay compatible', () {
    testWidgets('the Belgium button reaches estimate and download', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port, surface: const Size(390, 1600));

      await _tap(tester, find.byKey(const Key('offline_preset_download_belgium_base')));
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, _confirmDownload);

      expect(port.estimateRequests.length, 1);
      expect(port.downloadRequests.length, 1);
      expect(
        port.downloadRequests.single.regionId,
        'fluxidi_driver_region_belgium_base_6_10',
        reason: 'legacy region ids must stay deterministic',
      );
    });

    testWidgets('the Maarkedal button reaches estimate and download', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(tester, port: port, surface: const Size(390, 1600));

      await _tap(tester, find.byKey(const Key('offline_preset_download_maarkedal_vlaamse_ardennen')));
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, _confirmDownload);

      expect(port.downloadRequests.single.regionId,
          'fluxidi_driver_region_maarkedal_vlaamse_ardennen_11_16');
      expect(
        port.observedPhases
            .where((p) => p == DriverOfflineMapProgressPhase.stylePack)
            .length,
        2,
      );
      expect(
        port.observedPhases
            .where((p) => p == DriverOfflineMapProgressPhase.tileRegion)
            .length,
        1,
      );
    });

    testWidgets('a legacy button never silently returns without configuration', (
      tester,
    ) async {
      final port = _FakeOfflinePort();
      await _pumpPage(
        tester,
        port: port,
        surface: const Size(390, 1600),
        mapboxConfigured: false,
      );

      await _tap(tester, find.byKey(const Key('offline_preset_download_belgium_base')), settle: false);

      expect(
        find.text(_nl(DriverOfflineMapFailureCategory.mapboxConfiguration)),
        findsWidgets,
      );
      expect(port.estimateRequests, isEmpty);
    });
  });

  group('layouts', () {
    for (final layout in <String, Size>{
      'phone portrait': Size(390, 844),
      'phone landscape': Size(844, 390),
      'tablet portrait': Size(834, 1194),
      'tablet landscape': Size(1194, 834),
    }.entries) {
      testWidgets('${layout.key}: selection and CTA render without overflow', (
        tester,
      ) async {
        final port = _FakeOfflinePort();
        await _pumpPage(tester, port: port, surface: layout.value);
        await _searchAndSelectRonse(tester);

        expect(
          find.byKey(const Key('offline_europe_selection_summary')),
          findsOneWidget,
        );
        // Reachable by scrolling on every real device size.
        await _reveal(tester, _cta);
        expect(_cta, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // FLUXIDI-OFFLINE-MAP-NONFINITE-ESTIMATE-DIALOG-P0-2
  group('non-finite estimate confirmation stays open', () {
    Future<void> openEuropeConfirm(
      WidgetTester tester,
      _FakeOfflinePort port,
    ) async {
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);
      await _tap(tester, _cta);
    }

    testWidgets('NaN errorMargin opens dialog and allows confirmed download', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: double.nan,
        ),
      );
      await openEuropeConfirm(tester, port);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Geschatte download'), findsWidgets);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
      expect(_confirmDownload, findsOneWidget);

      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('positive Infinity errorMargin opens dialog safely', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: double.infinity,
        ),
      );
      await openEuropeConfirm(tester, port);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('±'), findsNothing);
      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1);
    });

    testWidgets('negative Infinity errorMargin opens dialog safely', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: double.negativeInfinity,
        ),
      );
      await openEuropeConfirm(tester, port);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('negative byte estimate shows unavailable and still confirms', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: -1,
          storageSizeBytes: -1,
          errorMargin: 0.15,
        ),
      );
      await openEuropeConfirm(tester, port);
      expect(tester.takeException(), isNull);
      expect(
        find.text('Geschatte downloadgrootte niet beschikbaar'),
        findsOneWidget,
      );
      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1);
      expect(
        port.downloadRequests.single.regionId,
        isNot(equals('complete')),
        reason: 'unavailable estimate must not fake a completed download',
      );
    });

    testWidgets('missing estimate opens dialog; busy state is released', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateError: TimeoutException('estimate hung'),
      );
      await openEuropeConfirm(tester, port);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('offline_preparing_card')), findsNothing);

      // Dismiss and prove CTA is usable again (busy released).
      await _tap(tester, find.text('Annuleren'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<FilledButton>(_cta).onPressed, isNotNull);
    });

    testWidgets('11+12) rapid second tap remains single-flight after NaN margin', (
      tester,
    ) async {
      final port = _FakeOfflinePort(
        estimateDelay: const Duration(milliseconds: 400),
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: double.nan,
        ),
      );
      await _pumpPage(tester, port: port);
      await _searchAndSelectRonse(tester);

      await _tap(tester, _cta, settle: false);
      await _tap(tester, _cta, settle: false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(port.estimateRequests.length, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('14) legacy Belgium handles Infinity margin', (tester) async {
      final port = _FakeOfflinePort(
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: double.infinity,
        ),
      );
      await _pumpPage(tester, port: port, surface: const Size(390, 1600));
      await _tap(
        tester,
        find.byKey(const Key('offline_preset_download_belgium_base')),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1);
    });

    testWidgets('15) legacy Maarkedal handles NaN margin', (tester) async {
      final port = _FakeOfflinePort(
        estimateOverride: const DriverOfflineMapEstimate(
          transferSizeBytes: 41943040,
          storageSizeBytes: 52428800,
          errorMargin: double.nan,
        ),
      );
      await _pumpPage(tester, port: port, surface: const Size(390, 1600));
      await _tap(
        tester,
        find.byKey(
          const Key('offline_preset_download_maarkedal_vlaamse_ardennen'),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, _confirmDownload);
      expect(port.downloadRequests.length, 1);
    });

    testWidgets('16) phone and tablet confirm dialogs survive Infinity margin', (
      tester,
    ) async {
      for (final size in <Size>[
        const Size(390, 844),
        const Size(834, 1194),
      ]) {
        final port = _FakeOfflinePort(
          estimateOverride: const DriverOfflineMapEstimate(
            transferSizeBytes: 41943040,
            storageSizeBytes: 52428800,
            errorMargin: double.infinity,
          ),
        );
        await _pumpPage(tester, port: port, surface: size);
        await _searchAndSelectRonse(tester);
        await _tap(tester, _cta);
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
        await _tap(tester, find.text('Annuleren'));
      }
    });
  });
}
