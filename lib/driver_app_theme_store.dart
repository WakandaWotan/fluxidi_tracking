import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'driver_theme_palette.dart';

const DriverThemeVariant _kDefaultDriverAppTheme = DriverThemeVariant.nightGold;

final ValueNotifier<DriverThemeVariant> driverAppThemeNotifier =
    ValueNotifier<DriverThemeVariant>(_kDefaultDriverAppTheme);

const String _driverAppThemeStateDirName = 'driver_app_state';
const String _driverAppThemeFileName = 'driver_app_theme_v1.json';

Future<File> _driverAppThemeFile() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}$_driverAppThemeStateDirName',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$_driverAppThemeFileName');
}

DriverThemeVariant _driverAppThemeVariantFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in DriverThemeVariant.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultDriverAppTheme;
}

Future<void> loadDriverAppThemePreference() async {
  try {
    final file = await _driverAppThemeFile();
    if (!await file.exists()) {
      driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    driverAppThemeNotifier.value = _driverAppThemeVariantFromStorage(
      variantRaw,
    );
  } catch (_) {
    driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
  }
}

Future<void> saveDriverAppThemePreference(DriverThemeVariant variant) async {
  driverAppThemeNotifier.value = variant;
  try {
    final file = await _driverAppThemeFile();
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}
