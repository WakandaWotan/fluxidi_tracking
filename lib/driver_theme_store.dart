import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'driver_theme_palette.dart';

const DriverThemeVariant _kDefaultDriverTheme = DriverThemeVariant.nightGold;

final ValueNotifier<DriverThemeVariant> driverThemeNotifier =
    ValueNotifier<DriverThemeVariant>(_kDefaultDriverTheme);

const String _driverThemeStateDirName = 'driver_state';
const String _driverThemeFileName = 'driver_theme_v1.json';

Future<File> _driverThemeFile() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}$_driverThemeStateDirName',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$_driverThemeFileName');
}

DriverThemeVariant _driverThemeVariantFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in DriverThemeVariant.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultDriverTheme;
}

Future<void> loadDriverThemePreference() async {
  try {
    final file = await _driverThemeFile();
    if (!await file.exists()) {
      driverThemeNotifier.value = _kDefaultDriverTheme;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      driverThemeNotifier.value = _kDefaultDriverTheme;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      driverThemeNotifier.value = _kDefaultDriverTheme;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    driverThemeNotifier.value = _driverThemeVariantFromStorage(variantRaw);
  } catch (_) {
    driverThemeNotifier.value = _kDefaultDriverTheme;
  }
}

Future<void> saveDriverThemePreference(DriverThemeVariant variant) async {
  driverThemeNotifier.value = variant;
  try {
    final file = await _driverThemeFile();
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}
