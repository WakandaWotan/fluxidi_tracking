import 'dart:io';

import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:path_provider/path_provider.dart';

const String _businessThemeStateDirName = 'business_state';

Future<File> _businessThemeFile(String fileName) async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}${fluxidiRuntimeStateDirName(_businessThemeStateDirName)}',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$fileName');
}

Future<String?> readBusinessThemeFileContents(String fileName) async {
  try {
    final file = await _businessThemeFile(fileName);
    if (!await file.exists()) return null;
    return file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> writeBusinessThemeFileContents(
  String fileName,
  String contents,
) async {
  try {
    final file = await _businessThemeFile(fileName);
    await file.writeAsString(contents, flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

void resetBusinessThemeFilePersistForTest() {}
