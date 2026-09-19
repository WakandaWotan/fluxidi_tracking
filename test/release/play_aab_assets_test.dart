import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_play_aab_assets.dart';

ArchiveFile _file(String name, List<int> bytes) {
  return ArchiveFile(name, bytes.length, bytes);
}

List<int> _bundleWith(Map<String, List<int>> flutterAssets) {
  final archive = Archive();
  flutterAssets.forEach((name, bytes) {
    archive.addFile(_file('base/assets/flutter_assets/$name', bytes));
  });
  archive.addFile(_file('base/assets/mlkit_barcode_models/x', <int>[1]));
  return _zip(archive);
}

List<int> _zip(Archive archive) {
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null || encoded.isEmpty) {
    throw StateError('zip encode failed');
  }
  return encoded;
}

void main() {
  test('AAB 24-shaped bundle without flutter_assets fails the Play gate', () {
    final bytes = _zip(
      Archive()
        ..addFile(_file('base/assets.pb', utf8.encode('mlkit-only')))
        ..addFile(_file('base/assets/mlkit_barcode_models/x', <int>[1])),
    );
    final report = inspectPlayBundleBytes(bytes);
    expect(report.ok, isFalse);
    expect(report.flutterAssetCount, 0);
    expect(report.missing, contains('AssetManifest.bin'));
    expect(report.missing, contains('fonts/MaterialIcons-Regular.otf'));
    expect(report.missing, contains('assets/fluxidi/role_customer_bg.webp'));
  });

  test('complete flutter_assets payload passes the Play gate', () {
    final bytes = _bundleWith(<String, List<int>>{
      for (final name in kRequiredFlutterAssetSuffixes)
        name: Uint8List.fromList(List<int>.filled(2048, 7)),
      'FontManifest.json': utf8.encode(
        '[{"family":"MaterialIcons","fonts":[{"asset":"fonts/MaterialIcons-Regular.otf"}]}]',
      ),
    });
    final report = inspectPlayBundleBytes(bytes);
    expect(report.missing, isEmpty, reason: '${report.missing}');
    expect(report.ok, isTrue);
    expect(report.fontFamilies, contains('MaterialIcons'));
    expect(report.materialIconsBytes, greaterThan(0));
  });

  test('known broken AAB 24 fails the same inspector', () {
    const path = r'.qa-local\real-account\Fluxidi-internal-test-1.0.4+24.aab';
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'AAB 24 must remain for comparison',
    );
    final report = inspectPlayBundleFile(file);
    expect(report.ok, isFalse);
    expect(report.flutterAssetCount, 0);
    expect(report.missing, contains('AssetManifest.bin'));
    expect(report.missing, contains('fonts/MaterialIcons-Regular.otf'));
  });

  test('working AAB 23 still contains fonts and role images', () {
    const path = r'.qa-local\real-account\Fluxidi-internal-test-1.0.4+23.aab';
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'AAB 23 must remain for comparison',
    );
    final report = inspectPlayBundleFile(file);
    expect(report.ok, isTrue, reason: '${report.missing}');
    expect(report.flutterAssetCount, greaterThan(400));
    expect(report.materialIconsBytes, greaterThan(1000));
  });

  test(
    'welcome assets are declared in the application AssetManifest',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final manifest = jsonDecode(
        await rootBundle.loadString('AssetManifest.json'),
      );
      expect(manifest, isA<Map>());
      final keys = (manifest as Map).keys.cast<String>().toList();
      for (final asset in const <String>[
        'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
        'assets/fluxidi/role_customer_bg.webp',
        'assets/fluxidi/role_business_bg.webp',
        'assets/fluxidi/role_driver_bg.webp',
      ]) {
        expect(keys, contains(asset), reason: asset);
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(0), reason: asset);
      }
      final fonts = jsonDecode(await rootBundle.loadString('FontManifest.json'));
      expect(fonts, isA<List>());
      final families = (fonts as List)
          .whereType<Map>()
          .map((item) => '${item['family'] ?? ''}')
          .toList();
      expect(families, contains('MaterialIcons'));
      final iconFont = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      expect(iconFont.lengthInBytes, greaterThan(1000));
    },
  );
}
