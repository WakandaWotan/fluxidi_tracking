// Inspect a Play AAB or APK and fail when Flutter assets were not packaged.
//
// AAB 24 shipped libapp.so/libflutter.so without `flutter_assets`, so the
// welcome page rendered Image/Icon error boxes while text still loaded.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const List<String> kRequiredFlutterAssetSuffixes = <String>[
  'AssetManifest.bin',
  'AssetManifest.json',
  'FontManifest.json',
  'fonts/MaterialIcons-Regular.otf',
  'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
  'assets/fluxidi/role_customer_bg.webp',
  'assets/fluxidi/role_business_bg.webp',
  'assets/fluxidi/role_driver_bg.webp',
  'assets/booking/modes/v1/fluxidi_mode_airport_ride_v1.webp',
  'assets/booking/airports/v1/fluxidi_airport_bru_brussels_zaventem_v1.webp',
];

class PlayBundleAssetReport {
  const PlayBundleAssetReport({
    required this.path,
    required this.flutterAssetCount,
    required this.missing,
    required this.fontFamilies,
    required this.materialIconsBytes,
  });

  final String path;
  final int flutterAssetCount;
  final List<String> missing;
  final List<String> fontFamilies;
  final int materialIconsBytes;

  bool get ok =>
      missing.isEmpty &&
      fontFamilies.contains('MaterialIcons') &&
      materialIconsBytes > 0;
}

PlayBundleAssetReport inspectPlayBundleBytes(
  List<int> bytes, {
  String path = '',
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final flutterFiles = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.replaceAll('\\', '/');
    final marker = '/flutter_assets/';
    final index = name.indexOf(marker);
    if (index < 0) continue;
    flutterFiles[name.substring(index + marker.length)] = file;
  }

  final missing = <String>[];
  for (final suffix in kRequiredFlutterAssetSuffixes) {
    final file = flutterFiles[suffix];
    if (file == null || file.size <= 0) missing.add(suffix);
  }

  var fontFamilies = const <String>[];
  final fontManifest = flutterFiles['FontManifest.json'];
  if (fontManifest != null && fontManifest.size > 0) {
    final raw = utf8.decode(_archiveBytes(fontManifest));
    final parsed = jsonDecode(raw);
    if (parsed is List) {
      fontFamilies = parsed
          .whereType<Map>()
          .map((item) => '${item['family'] ?? ''}')
          .where((family) => family.isNotEmpty)
          .toList();
    }
    if (!fontFamilies.contains('MaterialIcons')) {
      missing.add('FontManifest.json:MaterialIcons');
    }
  }

  final icons = flutterFiles['fonts/MaterialIcons-Regular.otf'];
  return PlayBundleAssetReport(
    path: path,
    flutterAssetCount: flutterFiles.length,
    missing: missing,
    fontFamilies: fontFamilies,
    materialIconsBytes: icons?.size ?? 0,
  );
}

List<int> _archiveBytes(ArchiveFile file) {
  final content = file.content;
  if (content is List<int>) return content;
  throw StateError('unexpected archive content for ${file.name}');
}

PlayBundleAssetReport inspectPlayBundleFile(File file) {
  return inspectPlayBundleBytes(file.readAsBytesSync(), path: file.path);
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

void main(List<String> args) {
  if (args.isEmpty) {
    _fail(
      'usage: dart run tool/check_play_aab_assets.dart <app-release.aab|apk>',
    );
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    _fail('missing bundle: ${file.path}');
  }
  final report = inspectPlayBundleFile(file);
  stdout.writeln('bundle=${report.path}');
  stdout.writeln('bytes=${file.lengthSync()}');
  stdout.writeln('flutter_assets=${report.flutterAssetCount}');
  stdout.writeln('material_icons_bytes=${report.materialIconsBytes}');
  stdout.writeln('font_families=${report.fontFamilies.join(',')}');
  if (!report.ok) {
    _fail(
      'FLUTTER_ASSETS_MISSING: ${report.missing.join(', ')}. '
      'Refusing to ship a Play bundle without Material Icons and Fluxidi images.',
    );
  }
  stdout.writeln('play_aab_assets=ok');
}
