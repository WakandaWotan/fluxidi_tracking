import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_sign_resolver.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: proves all 136 plates are registered in
/// `pubspec.yaml` and readable through the real Flutter asset bundle.
///
/// These tests load bytes, not path strings — a sign that is on disk but not
/// bundled fails here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  ({int width, int height}) readPngSize(ByteData data) {
    // IHDR is the first chunk: width at byte 16, height at byte 20, both
    // big-endian uint32.
    return (width: data.getUint32(16), height: data.getUint32(20));
  }

  group('136 language-asset cases', () {
    for (final language in kNavSignLanguageCodes) {
      for (final maneuver in NavSignManeuver.values) {
        final path = navSignAssetPath(
          languageCode: language,
          maneuver: maneuver,
        );
        test('$language/${maneuver.id} loads from the bundle', () async {
          final data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(0), reason: path);
          final header = Uint8List.view(
            data.buffer,
            data.offsetInBytes,
            pngMagic.length,
          );
          expect(header, pngMagic, reason: '$path is not a PNG');
          final size = readPngSize(data);
          expect(size.width, kNavSignSourceEdgePixels, reason: path);
          expect(size.height, kNavSignSourceEdgePixels, reason: path);
        });
      }
    }
  });

  group('asset set integrity', () {
    test('exactly 136 distinct paths are declared', () {
      final paths = navSignAllAssetPaths();
      expect(paths, hasLength(136));
      expect(paths.toSet(), hasLength(136));
      expect(kNavSignLanguageCodes, hasLength(4));
      expect(NavSignManeuver.values, hasLength(34));
    });

    test('every path sits under the registered png/<language>/ root', () {
      for (final path in navSignAllAssetPaths()) {
        expect(path.startsWith('$kNavSignAssetRoot/'), isTrue, reason: path);
        expect(path.endsWith('.png'), isTrue, reason: path);
        final parts = path.split('/');
        expect(kNavSignLanguageCodes, contains(parts[parts.length - 2]));
      }
    });

    test('all 136 load, and every miss is reported at once', () async {
      final paths = navSignAllAssetPaths();
      final missing = <String>[];
      var loaded = 0;
      for (final path in paths) {
        try {
          final data = await rootBundle.load(path);
          if (data.lengthInBytes > 0) {
            loaded++;
          } else {
            missing.add('$path (empty)');
          }
        } on Object {
          missing.add(path);
        }
      }
      expect(missing, isEmpty, reason: 'unloadable: ${missing.join(', ')}');
      expect(loaded, 136);
    });

    test('each language ships the same 34 maneuver ids', () async {
      for (final language in kNavSignLanguageCodes) {
        for (final maneuver in NavSignManeuver.values) {
          final path = navSignAssetPath(
            languageCode: language,
            maneuver: maneuver,
          );
          expect(path.endsWith('/${maneuver.id}.png'), isTrue, reason: path);
          await rootBundle.load(path);
        }
      }
    });
  });

  group('1024x1024 sources are decoded within budget', () {
    test('decode edge tracks the painted physical size, not the source', () {
      // A 60 dp plate on a 3x screen needs 180 px, not 1024.
      expect(navSignDecodeEdge(size: 60, devicePixelRatio: 3), 180);
      expect(navSignDecodeEdge(size: 34, devicePixelRatio: 2), 68);
    });

    test('decode never exceeds the native source edge', () {
      expect(
        navSignDecodeEdge(size: 900, devicePixelRatio: 4),
        kNavSignSourceEdgePixels,
      );
      expect(
        navSignDecodeEdge(
          size: kNavSignSourceEdgePixels.toDouble(),
          devicePixelRatio: 1,
        ),
        kNavSignSourceEdgePixels,
      );
    });

    test('degenerate sizes and ratios stay valid', () {
      expect(navSignDecodeEdge(size: 0, devicePixelRatio: 3), 1);
      expect(navSignDecodeEdge(size: -5, devicePixelRatio: 3), 1);
      expect(navSignDecodeEdge(size: 60, devicePixelRatio: 0), 60);
      expect(navSignDecodeEdge(size: 60, devicePixelRatio: double.nan), 60);
      expect(navSignDecodeEdge(size: double.nan, devicePixelRatio: 2), 1);
    });

    test('the banner-sized decode is a small fraction of a full plate', () {
      // RGBA bytes for the largest banner plate versus the raw 1024 source.
      const bannerEdge = 68.0;
      final decoded = navSignDecodeEdge(size: bannerEdge, devicePixelRatio: 3);
      final decodedBytes = decoded * decoded * 4;
      const sourceBytes =
          kNavSignSourceEdgePixels * kNavSignSourceEdgePixels * 4;
      expect(decodedBytes, lessThan(sourceBytes ~/ 5));
    });
  });
}
