import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke-loads every photographic asset converted in the lossless WebP pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('converted lossless WebP assets decode via rootBundle', () async {
    final allowlist = File('test/assets/lossless_webp_allowlist.json');
    expect(allowlist.existsSync(), isTrue);
    final paths = (jsonDecode(allowlist.readAsStringSync()) as List)
        .cast<String>();
    expect(paths.length, 139);

    var loaded = 0;
    for (final assetPath in paths) {
      final data = await rootBundle.load(assetPath);
      expect(data.lengthInBytes, greaterThan(32), reason: assetPath);
      final head = data.buffer.asUint8List(data.offsetInBytes, 12);
      expect(String.fromCharCodes(head.sublist(0, 4)), 'RIFF', reason: assetPath);
      expect(String.fromCharCodes(head.sublist(8, 12)), 'WEBP', reason: assetPath);
      loaded++;
    }
    expect(loaded, 139);
  });
}
