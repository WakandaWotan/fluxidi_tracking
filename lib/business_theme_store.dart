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

/// Phone-portrait Business Home dashboard layout preference.
///
/// - [compact]: existing default phone-portrait layout (2-column compact
///   tiles, no image background). Preserves current production behavior.
/// - [visual]: opt-in single-column wide image cards on phone portrait only.
///   Tablet portrait/landscape and phone landscape are unaffected.
enum BusinessHomeMobileLayout { compact, visual }

const BusinessHomeMobileLayout _kDefaultBusinessHomeMobileLayout =
    BusinessHomeMobileLayout.compact;

/// Phone-portrait Driver Home dashboard layout preference.
///
/// - [compact]: existing default phone-portrait driver home (no image
///   background quick action cards). Preserves current production behavior.
/// - [visual]: opt-in single-column wide image cards on phone portrait only.
///   Tablet portrait/landscape and phone landscape are unaffected.
enum DriverHomeMobileLayout { compact, visual }

const DriverHomeMobileLayout _kDefaultDriverHomeMobileLayout =
    DriverHomeMobileLayout.compact;

final ValueNotifier<BusinessThemeVariant> businessThemeNotifier =
    ValueNotifier<BusinessThemeVariant>(_kDefaultBusinessTheme);

/// Selected mobile (phone-portrait) Business Home layout. Defaults to
/// [BusinessHomeMobileLayout.compact] so existing installs keep the current
/// behavior until the user opts in to the visual layout.
final ValueNotifier<BusinessHomeMobileLayout> businessHomeMobileLayoutNotifier =
    ValueNotifier<BusinessHomeMobileLayout>(_kDefaultBusinessHomeMobileLayout);

/// Selected mobile (phone-portrait) Driver Home layout. Defaults to
/// [DriverHomeMobileLayout.compact] so existing installs keep the current
/// behavior until the user opts in to the visual layout.
final ValueNotifier<DriverHomeMobileLayout> driverHomeMobileLayoutNotifier =
    ValueNotifier<DriverHomeMobileLayout>(_kDefaultDriverHomeMobileLayout);

/// True only while a business owner / company admin page is mounted on the
/// route stack. When false, [FluxidiFrame] must not consume the business
/// theme accent, otherwise the accent leaks globally onto PIN/unlock, login,
/// role entry, customer pages, and standalone driver shells. Each business
/// shell entry point flips this on in `initState` and back off in `dispose`.
final ValueNotifier<bool> businessShellFrameActiveNotifier =
    ValueNotifier<bool>(false);

final ValueNotifier<CustomerThemeVariant>
businessPublishedCustomerThemeNotifier = ValueNotifier<CustomerThemeVariant>(
  _kDefaultPublishedCustomerTheme,
);

const String _businessThemeStateDirName = 'business_state';
const String _businessThemeFileName = 'business_theme_v1.json';
const String _publishedCustomerThemeFileName =
    'business_published_customer_theme_v1.json';
const String _businessHomeMobileLayoutFileName =
    'business_home_mobile_layout_v1.json';
const String _driverHomeMobileLayoutFileName =
    'driver_home_mobile_layout_v1.json';

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

BusinessHomeMobileLayout _businessHomeMobileLayoutFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in BusinessHomeMobileLayout.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultBusinessHomeMobileLayout;
}

DriverHomeMobileLayout _driverHomeMobileLayoutFromStorage(String raw) {
  final normalized = raw.trim();
  for (final variant in DriverHomeMobileLayout.values) {
    if (variant.name == normalized) return variant;
  }
  return _kDefaultDriverHomeMobileLayout;
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

Future<void> loadBusinessHomeMobileLayoutPreference() async {
  try {
    final file = await _businessThemeFile(_businessHomeMobileLayoutFileName);
    if (!await file.exists()) {
      businessHomeMobileLayoutNotifier.value =
          _kDefaultBusinessHomeMobileLayout;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      businessHomeMobileLayoutNotifier.value =
          _kDefaultBusinessHomeMobileLayout;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      businessHomeMobileLayoutNotifier.value =
          _kDefaultBusinessHomeMobileLayout;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    businessHomeMobileLayoutNotifier.value =
        _businessHomeMobileLayoutFromStorage(variantRaw);
  } catch (_) {
    businessHomeMobileLayoutNotifier.value = _kDefaultBusinessHomeMobileLayout;
  }
}

Future<void> saveBusinessHomeMobileLayoutPreference(
  BusinessHomeMobileLayout variant,
) async {
  businessHomeMobileLayoutNotifier.value = variant;
  try {
    final file = await _businessThemeFile(_businessHomeMobileLayoutFileName);
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

Future<void> loadDriverHomeMobileLayoutPreference() async {
  try {
    final file = await _businessThemeFile(_driverHomeMobileLayoutFileName);
    if (!await file.exists()) {
      driverHomeMobileLayoutNotifier.value = _kDefaultDriverHomeMobileLayout;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      driverHomeMobileLayoutNotifier.value = _kDefaultDriverHomeMobileLayout;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      driverHomeMobileLayoutNotifier.value = _kDefaultDriverHomeMobileLayout;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    driverHomeMobileLayoutNotifier.value = _driverHomeMobileLayoutFromStorage(
      variantRaw,
    );
  } catch (_) {
    driverHomeMobileLayoutNotifier.value = _kDefaultDriverHomeMobileLayout;
  }
}

Future<void> saveDriverHomeMobileLayoutPreference(
  DriverHomeMobileLayout variant,
) async {
  driverHomeMobileLayoutNotifier.value = variant;
  try {
    final file = await _businessThemeFile(_driverHomeMobileLayoutFileName);
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}
