import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'driver_theme_palette.dart';

const DriverThemeVariant _kDefaultCompanyDriverViewTheme =
    DriverThemeVariant.nightGold;

final ValueNotifier<DriverThemeVariant> companyDriverViewThemeNotifier =
    ValueNotifier<DriverThemeVariant>(_kDefaultCompanyDriverViewTheme);

const String _companyThemeStateDirName = 'business_state';
const String _companyThemeFileName = 'company_driver_view_theme_v1.json';

Future<File> _companyDriverViewThemeFile() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}$_companyThemeStateDirName',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$_companyThemeFileName');
}

DriverThemeVariant _companyDriverViewThemeVariantFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in DriverThemeVariant.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultCompanyDriverViewTheme;
}

Future<void> loadCompanyDriverViewThemePreference() async {
  try {
    final file = await _companyDriverViewThemeFile();
    if (!await file.exists()) {
      companyDriverViewThemeNotifier.value = _kDefaultCompanyDriverViewTheme;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      companyDriverViewThemeNotifier.value = _kDefaultCompanyDriverViewTheme;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      companyDriverViewThemeNotifier.value = _kDefaultCompanyDriverViewTheme;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    companyDriverViewThemeNotifier.value =
        _companyDriverViewThemeVariantFromStorage(variantRaw);
  } catch (_) {
    companyDriverViewThemeNotifier.value = _kDefaultCompanyDriverViewTheme;
  }
}

Future<void> saveCompanyDriverViewThemePreference(
  DriverThemeVariant variant,
) async {
  companyDriverViewThemeNotifier.value = variant;
  try {
    final file = await _companyDriverViewThemeFile();
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}
