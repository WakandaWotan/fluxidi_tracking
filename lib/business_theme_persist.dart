import 'package:flutter/foundation.dart';

import 'business_theme_persist_stub.dart'
    if (dart.library.io) 'business_theme_persist_io.dart' as impl;

/// Reads one business-theme document. Same file names as the existing store.
Future<String?> readBusinessThemeFileContents(String fileName) {
  return impl.readBusinessThemeFileContents(fileName);
}

/// Writes one business-theme document. Same file names as the existing store.
Future<void> writeBusinessThemeFileContents(String fileName, String contents) {
  return impl.writeBusinessThemeFileContents(fileName, contents);
}

@visibleForTesting
void resetBusinessThemeFilePersistForTest() {
  impl.resetBusinessThemeFilePersistForTest();
}
