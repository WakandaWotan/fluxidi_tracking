import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'business_theme_palette.dart';
import 'customer_theme_palette.dart';

const BusinessThemeVariant _kDefaultBusinessTheme =
    BusinessThemeVariant.executiveGold;
const CustomerThemeVariant _kDefaultPublishedCustomerTheme =
    CustomerThemeVariant.premiumLight;

final ValueNotifier<BusinessThemeVariant> businessThemeNotifier =
    ValueNotifier<BusinessThemeVariant>(_kDefaultBusinessTheme);

final ValueNotifier<CustomerThemeVariant>
businessPublishedCustomerThemeNotifier = ValueNotifier<CustomerThemeVariant>(
  _kDefaultPublishedCustomerTheme,
);

const String _businessThemeStateDirName = 'business_state';
const String _businessThemeFileName = 'business_theme_v1.json';
const String _publishedCustomerThemeFileName =
    'business_published_customer_theme_v1.json';

Future<File> _businessThemeFile(String fileName) async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(
    '${base.path}${Platform.pathSeparator}$_businessThemeStateDirName',
  );
  if (!await root.exists()) {
    await root.create(recursive: true);
  }
  return File('${root.path}${Platform.pathSeparator}$fileName');
}

BusinessThemeVariant _businessThemeVariantFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in BusinessThemeVariant.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultBusinessTheme;
}

CustomerThemeVariant _customerThemeVariantFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in CustomerThemeVariant.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultPublishedCustomerTheme;
}

Future<void> loadBusinessThemePreference() async {
  try {
    final file = await _businessThemeFile(_businessThemeFileName);
    if (!await file.exists()) {
      businessThemeNotifier.value = _kDefaultBusinessTheme;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      businessThemeNotifier.value = _kDefaultBusinessTheme;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      businessThemeNotifier.value = _kDefaultBusinessTheme;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    businessThemeNotifier.value = _businessThemeVariantFromStorage(variantRaw);
  } catch (_) {
    businessThemeNotifier.value = _kDefaultBusinessTheme;
  }
}

Future<void> saveBusinessThemePreference(BusinessThemeVariant variant) async {
  businessThemeNotifier.value = variant;
  try {
    final file = await _businessThemeFile(_businessThemeFileName);
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

Future<void> loadBusinessPublishedCustomerThemePreference() async {
  try {
    final file = await _businessThemeFile(_publishedCustomerThemeFileName);
    if (!await file.exists()) {
      businessPublishedCustomerThemeNotifier.value =
          _kDefaultPublishedCustomerTheme;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      businessPublishedCustomerThemeNotifier.value =
          _kDefaultPublishedCustomerTheme;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      businessPublishedCustomerThemeNotifier.value =
          _kDefaultPublishedCustomerTheme;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    businessPublishedCustomerThemeNotifier.value =
        _customerThemeVariantFromStorage(variantRaw);
  } catch (_) {
    businessPublishedCustomerThemeNotifier.value =
        _kDefaultPublishedCustomerTheme;
  }
}

Future<void> saveBusinessPublishedCustomerThemePreference(
  CustomerThemeVariant variant,
) async {
  businessPublishedCustomerThemeNotifier.value = variant;
  try {
    final file = await _businessThemeFile(_publishedCustomerThemeFileName);
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}
