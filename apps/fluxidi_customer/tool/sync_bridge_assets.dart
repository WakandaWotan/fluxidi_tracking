// Mirrors the customer asset files listed in tool/bridge_assets.txt from the
// repo root into this app's own assets/ tree.
//
// The bridge reuses the existing customer screens from the fluxidi_tracking
// package. Those screens load artwork with keys like 'assets/fluxidi/...'.
// Flutter only bundles a dependency package's assets when they live under that
// package's lib/, and the golden app's assets sit next to its pubspec, so the
// keys would not resolve here. Copying the files under the same relative paths
// keeps every existing asset key working without touching the golden app.
//
// Run from apps/fluxidi_customer:  dart run tool/sync_bridge_assets.dart

import 'dart:io';

void main(List<String> args) {
  final appDir = Directory.current;
  final repoRoot = appDir.parent.parent;
  final manifest = File('${appDir.path}/tool/bridge_assets.txt');
  if (!manifest.existsSync()) {
    stderr.writeln('bridge_assets.txt not found. Run this from apps/fluxidi_customer.');
    exit(2);
  }

  var copied = 0;
  var skipped = 0;
  var missing = 0;

  for (final rawLine in manifest.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final space = line.indexOf(RegExp(r'\s'));
    if (space < 0) {
      stderr.writeln('Malformed manifest line: $rawLine');
      exit(2);
    }
    final kind = line.substring(0, space).trim();
    final relative = line.substring(space).trim();

    switch (kind) {
      case 'file':
        final source = File('${repoRoot.path}/$relative');
        if (!source.existsSync()) {
          stderr.writeln('MISSING $relative');
          missing++;
          continue;
        }
        if (_copyIfChanged(source, File('${appDir.path}/$relative'))) {
          copied++;
        } else {
          skipped++;
        }
      case 'dir':
        final source = Directory('${repoRoot.path}/$relative');
        if (!source.existsSync()) {
          stderr.writeln('MISSING $relative');
          missing++;
          continue;
        }
        for (final entity in source.listSync(recursive: true)) {
          if (entity is! File) continue;
          final tail = entity.path
              .substring(source.path.length)
              .replaceAll(r'\', '/');
          final target = File('${appDir.path}/$relative$tail');
          if (_copyIfChanged(entity, target)) {
            copied++;
          } else {
            skipped++;
          }
        }
      default:
        stderr.writeln('Unknown manifest kind "$kind" in: $rawLine');
        exit(2);
    }
  }

  stdout.writeln('bridge assets: $copied copied, $skipped unchanged, $missing missing');
  if (missing > 0) exit(1);
}

bool _copyIfChanged(File source, File target) {
  if (target.existsSync() && target.lengthSync() == source.lengthSync()) {
    return false;
  }
  target.parent.createSync(recursive: true);
  source.copySync(target.path);
  return true;
}
