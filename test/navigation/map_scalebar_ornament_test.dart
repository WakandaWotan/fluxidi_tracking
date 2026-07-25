// NAV-HIDE-MAPBOX-SCALEBAR-P0-1
//
// Field-proven defect: the Mapbox measurement scale bar (a Mapbox ornament,
// distinct from `attribution` and `logo`) was visible on the driver map
// during active turn-by-turn navigation because Fluxidi never configured it
// and Mapbox enables it by default.
//
// The Mapbox plugin's `ScaleBarSettingsInterface.updateSettings` is a pigeon
// method that only round-trips through a real map instance. Full behavior
// mocking is heavy for a surgical validation, so this suite is a NARROW
// SOURCE-CONTRACT test:
//
//   * `_onMapCreated` disables the scale bar via the Mapbox `scaleBar`
//     ornament with `enabled: false`;
//   * the helper is best-effort (try/catch) so a channel hiccup cannot
//     break map creation;
//   * the file never re-enables the scale bar anywhere;
//   * the file never touches `mapboxMap.attribution.updateSettings(...)`
//     or `mapboxMap.logo.updateSettings(...)` — attribution and logo
//     remain at Mapbox defaults so terms compliance is preserved.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _driverMapStatePath =
    'lib/main_parts/driver_home_page_state.dart';

String _readDriverMapState() {
  final file = File(_driverMapStatePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'driver_home_page_state.dart must exist at $_driverMapStatePath',
  );
  return file.readAsStringSync();
}

/// Extracts the `_onMapCreated(...) { ... }` method body via brace-balanced
/// scanning. Fails the test if the method cannot be located — a rename or
/// removal is meaningful signal, not silent test drift.
String _extractOnMapCreatedBody(String source) {
  final signatureStart = source.indexOf(
    'Future<void> _onMapCreated(mb.MapboxMap mapboxMap) async {',
  );
  expect(
    signatureStart,
    greaterThanOrEqualTo(0),
    reason: '_onMapCreated method must be present in driver_home_page_state',
  );
  final bodyStart = source.indexOf('{', signatureStart);
  expect(bodyStart, greaterThanOrEqualTo(0));
  var depth = 0;
  for (var i = bodyStart; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        return source.substring(bodyStart, i + 1);
      }
    }
  }
  fail('Unterminated _onMapCreated method body');
}

/// Extracts the `_hideMapboxScaleBarBestEffort(...)` helper body.
String _extractHideScaleBarHelperBody(String source) {
  final signatureStart = source.indexOf(
    'Future<void> _hideMapboxScaleBarBestEffort(mb.MapboxMap mapboxMap) async {',
  );
  expect(
    signatureStart,
    greaterThanOrEqualTo(0),
    reason:
        '_hideMapboxScaleBarBestEffort helper must exist in the same file '
        'that owns _onMapCreated (surgical, no cross-file plumbing)',
  );
  final bodyStart = source.indexOf('{', signatureStart);
  expect(bodyStart, greaterThanOrEqualTo(0));
  var depth = 0;
  for (var i = bodyStart; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        return source.substring(bodyStart, i + 1);
      }
    }
  }
  fail('Unterminated _hideMapboxScaleBarBestEffort helper body');
}

void main() {
  group('NAV-HIDE-MAPBOX-SCALEBAR-P0-1 source contract', () {
    late final String source;
    late final String onMapCreatedBody;
    late final String helperBody;

    setUpAll(() {
      source = _readDriverMapState();
      onMapCreatedBody = _extractOnMapCreatedBody(source);
      helperBody = _extractHideScaleBarHelperBody(source);
    });

    test('_onMapCreated invokes the scale-bar hide helper', () {
      expect(
        onMapCreatedBody,
        contains('_hideMapboxScaleBarBestEffort(mapboxMap)'),
        reason:
            'Scale bar must be disabled as part of the authoritative map '
            'creation callback so it is off before the first frame.',
      );
    });

    test(
      'helper calls scaleBar.updateSettings(mb.ScaleBarSettings(enabled: '
      'false))',
      () {
        expect(helperBody, contains('mapboxMap.scaleBar.updateSettings('));
        expect(helperBody, contains('mb.ScaleBarSettings'));
        expect(helperBody, contains('enabled: false'));
      },
    );

    test('helper is best-effort — any channel failure is caught, never '
        'propagates', () {
      expect(helperBody, contains('try {'));
      expect(helperBody, contains('} catch ('));
      // Diagnostic emitted, but never thrown.
      expect(helperBody, contains('[MAP][SCALEBAR]'));
      // The helper body must NOT re-throw.
      expect(
        helperBody,
        isNot(contains('rethrow')),
        reason:
            'Scale bar wiring is decorative; must never break map creation.',
      );
      expect(
        helperBody,
        isNot(contains('throw ')),
        reason: 'Same — never throw from ornament setup.',
      );
    });

    test('file never re-enables the scale bar anywhere', () {
      expect(
        source,
        isNot(contains('mb.ScaleBarSettings(enabled: true)')),
        reason:
            'A second call re-enabling the scale bar would defeat this fix.',
      );
      expect(
        source,
        isNot(contains('ScaleBarSettings(enabled: true)')),
      );
    });

    test('attribution.updateSettings is never called from the driver map '
        'lifecycle — Mapbox terms compliance preserved', () {
      expect(
        source,
        isNot(contains('.attribution.updateSettings(')),
        reason:
            'Attribution ornament must remain at Mapbox default — required '
            'for Mapbox terms compliance.',
      );
    });

    test('logo.updateSettings is never called from the driver map '
        'lifecycle — Mapbox logo remains visible', () {
      expect(
        source,
        isNot(contains('.logo.updateSettings(')),
        reason:
            'Mapbox logo must remain visible — required for Mapbox terms '
            'compliance.',
      );
    });

    test('scale-bar hide runs before _applyMapStyleForMode in _onMapCreated',
        () {
      final hideIndex = onMapCreatedBody.indexOf(
        '_hideMapboxScaleBarBestEffort(',
      );
      final applyStyleIndex = onMapCreatedBody.indexOf(
        '_applyMapStyleForMode(',
      );
      expect(hideIndex, greaterThanOrEqualTo(0));
      expect(applyStyleIndex, greaterThanOrEqualTo(0));
      expect(
        hideIndex,
        lessThan(applyStyleIndex),
        reason:
            'Hiding the scale bar before the first style apply guarantees '
            'the ornament is off from the very first paint.',
      );
    });

    test('scale-bar hide is not awaited so map creation is never blocked '
        'on the ornament channel', () {
      // The call site uses `unawaited(...)` so a slow pigeon reply on the
      // ornament channel cannot delay the rest of _onMapCreated.
      expect(
        onMapCreatedBody,
        contains('unawaited(_hideMapboxScaleBarBestEffort(mapboxMap))'),
      );
    });
  });
}
