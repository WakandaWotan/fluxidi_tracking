// Removes unused fluxidi_tracking package assets from a Flutter asset tree.
// Does not touch repo-root source artwork.
//
// Usage:
//   dart run tool/strip_unused_bridge_package_assets.dart [flutter_assets_dir]

import 'dart:io';

import 'unused_bridge_package_assets.dart';

void main(List<String> args) {
  final flutterAssets = Directory(
    args.isEmpty
        ? 'build/app/intermediates/flutter/release/flutter_assets'
        : args.first,
  );
  if (!flutterAssets.existsSync()) {
    stderr.writeln('flutter_assets not found: ${flutterAssets.path}');
    exit(2);
  }

  var removed = 0;
  var bytes = 0;
  var kept = 0;

  final packageRoot = Directory(
    '${flutterAssets.path}/packages/fluxidi_tracking',
  );
  if (packageRoot.existsSync()) {
    for (final entity in packageRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(packageRoot.path.length + 1)
          .replaceAll('\\', '/');
      if (isUnusedBridgePackageAsset(relative)) {
        bytes += entity.lengthSync();
        entity.deleteSync();
        removed++;
      } else {
        kept++;
      }
    }
    _deleteEmptyDirectories(packageRoot);
  }

  for (final entity in flutterAssets.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(flutterAssets.path.length + 1)
        .replaceAll('\\', '/');
    if (relative.startsWith('packages/')) continue;
    if (isUnusedCustomerAppAsset(relative)) {
      bytes += entity.lengthSync();
      entity.deleteSync();
      removed++;
    }
  }

  stdout.writeln(
    'strip unused bridge assets: $removed removed, $kept package files kept, '
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB deleted from bundle tree',
  );
}

void _deleteEmptyDirectories(Directory root) {
  final dirs = root
      .listSync(recursive: true)
      .whereType<Directory>()
      .toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final dir in dirs) {
    if (dir.listSync().isEmpty) {
      dir.deleteSync();
    }
  }
}
