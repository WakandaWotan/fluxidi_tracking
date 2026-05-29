import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'customer_theme_palette.dart';

const CustomerThemeVariant _kDefaultCustomerTheme =
    CustomerThemeVariant.premiumLight;

final ValueNotifier<CustomerThemeVariant> customerThemeNotifier =
    ValueNotifier<CustomerThemeVariant>(_kDefaultCustomerTheme);

const String _customerThemeStateDirName = 'customer_state';
const String _customerThemeFileName = 'customer_theme_v1.json';

Future<File> _customerThemeFile() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}$_customerThemeStateDirName',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$_customerThemeFileName');
}

String _customerThemeVariantToStorage(CustomerThemeVariant variant) {
  return variant.name;
}

CustomerThemeVariant _customerThemeVariantFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in CustomerThemeVariant.values) {
    if (variant.name == normalized) {
      return variant;
    }
  }
  return _kDefaultCustomerTheme;
}

Future<void> loadCustomerThemePreference() async {
  try {
    final file = await _customerThemeFile();
    if (!await file.exists()) {
      customerThemeNotifier.value = _kDefaultCustomerTheme;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      customerThemeNotifier.value = _kDefaultCustomerTheme;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      customerThemeNotifier.value = _kDefaultCustomerTheme;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    customerThemeNotifier.value = _customerThemeVariantFromStorage(variantRaw);
  } catch (_) {
    customerThemeNotifier.value = _kDefaultCustomerTheme;
  }
}

Future<void> saveCustomerThemePreference(CustomerThemeVariant variant) async {
  customerThemeNotifier.value = variant;
  try {
    final file = await _customerThemeFile();
    final payload = <String, dynamic>{
      'variant': _customerThemeVariantToStorage(variant),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value if persistence is temporarily unavailable.
  }
}
