import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'business_theme_cycle.dart';
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

/// Compatibility mirror of [businessThemeNotifier], never an independent owner.
///
/// A business theme is one complete preset: palette, borders, typography,
/// system overlay and artwork. Advancing colors and artwork separately is what
/// let Clean Professional render Neon Rush artwork, so this notifier now only
/// ever holds the same value as [businessThemeNotifier]. It is kept so existing
/// readers keep compiling; new code should read [businessThemeNotifier] or call
/// [activeBusinessThemePreset].
final ValueNotifier<BusinessThemeVariant> businessAppearanceNotifier =
    ValueNotifier<BusinessThemeVariant>(_kDefaultBusinessTheme);

/// The single owner of the complete active preset (colors *and* artwork).
BusinessThemeVariant activeBusinessThemePreset() => businessThemeNotifier.value;

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
const String _businessAppearanceFileName = 'business_appearance_v1.json';
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

Future<void> _writeBusinessThemeVariantFile(
  String fileName,
  BusinessThemeVariant variant,
) async {
  try {
    final file = await _businessThemeFile(fileName);
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

/// Canonical, atomic application of one complete business theme preset.
///
/// Both notifiers move in the same synchronous step *before* any await, so no
/// frame and no rapid second press can observe one preset's colors alongside
/// another preset's artwork. Persistence writes the value that is live at write
/// time, so however concurrent writes interleave they converge on the preset the
/// user actually ended on.
///
/// Company-owned branding is out of scope here: the uploaded company logo,
/// company name, identity, booking/KPI, pricing and subscription state are
/// never read or written by this path.
Future<void> applyBusinessThemePreset(BusinessThemeVariant variant) async {
  businessThemeNotifier.value = variant;
  businessAppearanceNotifier.value = variant;
  await _persistActiveBusinessThemePreset();
}

bool _businessThemeWriteInFlight = false;
bool _businessThemeWriteSuperseded = false;

/// Serialized, coalescing persistence of the live preset.
///
/// Rapid presses used to run overlapping writes against the same file, which
/// interleaved their JSON and left a corrupt preset on disk. Only one write runs
/// at a time; a press that arrives during a write marks the result superseded, so
/// one more pass runs afterwards and persists whatever preset is live then. The
/// stored value therefore converges on the preset the user actually ended on.
Future<void> _persistActiveBusinessThemePreset() async {
  if (_businessThemeWriteInFlight) {
    _businessThemeWriteSuperseded = true;
    return;
  }
  _businessThemeWriteInFlight = true;
  try {
    do {
      _businessThemeWriteSuperseded = false;
      final preset = businessThemeNotifier.value;
      await _writeBusinessThemeVariantFile(_businessThemeFileName, preset);
      await _writeBusinessThemeVariantFile(_businessAppearanceFileName, preset);
    } while (_businessThemeWriteSuperseded);
  } finally {
    _businessThemeWriteInFlight = false;
  }
}

/// Clears the in-flight write latch between tests.
@visibleForTesting
void resetBusinessThemePersistenceLatchForTest() {
  _businessThemeWriteInFlight = false;
  _businessThemeWriteSuperseded = false;
}

Future<void> loadBusinessThemePreference() async {
  var restored = _kDefaultBusinessTheme;
  try {
    final file = await _businessThemeFile(_businessThemeFileName);
    if (await file.exists()) {
      final raw = await file.readAsString();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          restored = _businessThemeVariantFromStorage(
            (decoded['variant'] ?? '').toString(),
          );
        }
      }
    }
  } catch (_) {
    restored = _kDefaultBusinessTheme;
  }
  // Restore the complete preset: artwork can never come back stale.
  businessThemeNotifier.value = restored;
  businessAppearanceNotifier.value = restored;
}

/// Applies [variant] as a complete preset.
///
/// Retained name for existing callers; colors and artwork are inseparable, so
/// this is [applyBusinessThemePreset].
Future<void> saveBusinessThemePreference(BusinessThemeVariant variant) =>
    applyBusinessThemePreset(variant);

/// Kept for startup ordering compatibility.
///
/// The appearance file is no longer an independent truth source. It converges
/// onto the restored preset and is healed on disk, so a legacy stale artwork
/// value from the colors-only split cannot survive a restart.
Future<void> loadBusinessAppearancePreference() async {
  final preset = businessThemeNotifier.value;
  businessAppearanceNotifier.value = preset;
  var storedMatchesPreset = false;
  try {
    final file = await _businessThemeFile(_businessAppearanceFileName);
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      storedMatchesPreset =
          decoded is Map &&
          _businessThemeVariantFromStorage(
                (decoded['variant'] ?? '').toString(),
              ) ==
              preset;
    }
  } catch (_) {
    storedMatchesPreset = false;
  }
  if (!storedMatchesPreset) {
    await _persistActiveBusinessThemePreset();
  }
}

/// Applies [variant] as a complete preset.
///
/// Retained name for existing callers; artwork is not separately selectable.
Future<void> saveBusinessAppearancePreference(BusinessThemeVariant variant) =>
    applyBusinessThemePreset(variant);

/// Settings-page preset selection. Same canonical path as the header shortcut.
Future<void> saveBusinessThemeAndAppearancePreset(
  BusinessThemeVariant variant,
) => applyBusinessThemePreset(variant);

/// One-tap advance for the business header theme shortcut.
///
/// Applies the next complete preset — palette, overlay and artwork together.
Future<BusinessThemeVariant> cycleBusinessThemePreference() async {
  final next = nextBusinessThemeVariant(businessThemeNotifier.value);
  await applyBusinessThemePreset(next);
  return next;
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
