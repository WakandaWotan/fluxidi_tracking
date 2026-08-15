import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'business_theme/brand_signature_palette.dart';
import 'company_driver_view_theme_store.dart';
import 'driver_theme/driver_custom_huis_stijl.dart';
import 'driver_theme_cycle.dart';
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
      driverBrandSignaturePaletteNotifier.value =
          BrandSignaturePalette.defaults;
      return;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
      driverBrandSignaturePaletteNotifier.value =
          BrandSignaturePalette.defaults;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
      driverBrandSignaturePaletteNotifier.value =
          BrandSignaturePalette.defaults;
      return;
    }
    final variantRaw = (decoded['variant'] ?? '').toString();
    driverAppThemeNotifier.value = _driverAppThemeVariantFromStorage(
      variantRaw,
    );
    driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.fromJson(
      decoded['customHuisstijlPalette'],
    );
  } catch (_) {
    driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
    driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
  }
}

bool _driverCustomPreviewActive = false;
DriverThemeVariant? _driverCustomPreviewTheme;
BrandSignaturePalette? _driverCustomPreviewPalette;

void _clearDriverCustomPreviewCheckpoint() {
  _driverCustomPreviewActive = false;
  _driverCustomPreviewTheme = null;
  _driverCustomPreviewPalette = null;
}

void previewDriverCustomHuisstijlColor(Color color) {
  if (!_driverCustomPreviewActive) {
    _driverCustomPreviewTheme = driverAppThemeNotifier.value;
    _driverCustomPreviewPalette = driverBrandSignaturePaletteNotifier.value;
    _driverCustomPreviewActive = true;
  }
  driverAppThemeNotifier.value = DriverThemeVariant.customHuisstijl;
  driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
    color,
  );
}

void cancelDriverCustomHuisstijlPreview() {
  if (!_driverCustomPreviewActive) return;
  driverAppThemeNotifier.value =
      _driverCustomPreviewTheme ?? _kDefaultDriverAppTheme;
  driverBrandSignaturePaletteNotifier.value =
      _driverCustomPreviewPalette ?? BrandSignaturePalette.defaults;
  _clearDriverCustomPreviewCheckpoint();
}

Future<void> applyDriverCustomHuisstijlPalette(
  BrandSignaturePalette palette,
) async {
  _clearDriverCustomPreviewCheckpoint();
  driverAppThemeNotifier.value = DriverThemeVariant.customHuisstijl;
  driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
    palette.base,
  );
  await _persistActiveDriverAppTheme();
}

bool _chauffeurSelectorPreviewActive = false;
DriverThemeVariant? _chauffeurSelectorPreviewStandalone;
DriverThemeVariant? _chauffeurSelectorPreviewCompany;

void previewChauffeurTheme(
  DriverThemeVariant variant, {
  required bool companyDriverView,
}) {
  if (!_chauffeurSelectorPreviewActive) {
    _chauffeurSelectorPreviewStandalone = driverAppThemeNotifier.value;
    _chauffeurSelectorPreviewCompany = companyDriverViewThemeNotifier.value;
    _chauffeurSelectorPreviewActive = true;
  }
  if (companyDriverView) {
    companyDriverViewThemeNotifier.value = variant;
  } else {
    driverAppThemeNotifier.value = variant;
  }
}

void cancelChauffeurThemePreview({required bool companyDriverView}) {
  if (!_chauffeurSelectorPreviewActive) return;
  if (companyDriverView) {
    companyDriverViewThemeNotifier.value =
        _chauffeurSelectorPreviewCompany ?? _kDefaultDriverAppTheme;
  } else {
    driverAppThemeNotifier.value =
        _chauffeurSelectorPreviewStandalone ?? _kDefaultDriverAppTheme;
  }
  _chauffeurSelectorPreviewActive = false;
  _chauffeurSelectorPreviewStandalone = null;
  _chauffeurSelectorPreviewCompany = null;
}

Future<void> applyChauffeurTheme(
  DriverThemeVariant variant, {
  required bool companyDriverView,
}) async {
  _chauffeurSelectorPreviewActive = false;
  _chauffeurSelectorPreviewStandalone = null;
  _chauffeurSelectorPreviewCompany = null;
  if (companyDriverView) {
    await applyCompanyDriverViewThemePreference(variant);
    return;
  }
  await applyDriverAppThemePreference(variant);
}

bool _companyCustomPreviewActive = false;
DriverThemeVariant? _companyCustomPreviewTheme;

void previewChauffeurCustomHuisstijlColor(
  Color color, {
  required bool companyDriverView,
}) {
  previewDriverCustomHuisstijlColor(color);
  if (!companyDriverView) return;
  if (!_companyCustomPreviewActive) {
    _companyCustomPreviewTheme = companyDriverViewThemeNotifier.value;
    _companyCustomPreviewActive = true;
  }
  companyDriverViewThemeNotifier.value = DriverThemeVariant.customHuisstijl;
}

void cancelChauffeurCustomHuisstijlPreview({
  required bool companyDriverView,
}) {
  cancelDriverCustomHuisstijlPreview();
  if (!companyDriverView || !_companyCustomPreviewActive) return;
  companyDriverViewThemeNotifier.value =
      _companyCustomPreviewTheme ?? _kDefaultDriverAppTheme;
  _companyCustomPreviewActive = false;
  _companyCustomPreviewTheme = null;
}

Future<void> applyChauffeurCustomHuisstijlPalette(
  BrandSignaturePalette palette, {
  required bool companyDriverView,
}) async {
  await applyDriverCustomHuisstijlPalette(palette);
  if (!companyDriverView) return;
  _companyCustomPreviewActive = false;
  _companyCustomPreviewTheme = null;
  await applyCompanyDriverViewThemePreference(
    DriverThemeVariant.customHuisstijl,
  );
}

bool _driverAppThemeWriteInFlight = false;
bool _driverAppThemeWriteSuperseded = false;

/// Applies [variant] immediately in memory, then persists with a serialized
/// coalescing write so rapid one-tap cycles cannot finish out of order.
Future<void> applyDriverAppThemePreference(DriverThemeVariant variant) async {
  driverAppThemeNotifier.value = variant;
  await _persistActiveDriverAppTheme();
}

/// Retained name for existing callers (settings sheet, etc.).
Future<void> saveDriverAppThemePreference(DriverThemeVariant variant) =>
    applyDriverAppThemePreference(variant);

/// Serialized, coalescing persistence of the live driver app theme.
///
/// Only one write runs at a time; a press that arrives during a write marks the
/// result superseded so one more pass persists whatever theme is live then.
Future<void> _persistActiveDriverAppTheme() async {
  if (_driverAppThemeWriteInFlight) {
    _driverAppThemeWriteSuperseded = true;
    return;
  }
  _driverAppThemeWriteInFlight = true;
  try {
    do {
      _driverAppThemeWriteSuperseded = false;
      final preset = driverAppThemeNotifier.value;
      try {
        final file = await _driverAppThemeFile();
        final payload = <String, dynamic>{
          'variant': preset.name,
          'customHuisstijlPalette':
              driverBrandSignaturePaletteNotifier.value.toJson(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await file.writeAsString(jsonEncode(payload), flush: true);
      } catch (_) {
        // Keep in-memory value when persistence temporarily fails.
      }
    } while (_driverAppThemeWriteSuperseded);
  } finally {
    _driverAppThemeWriteInFlight = false;
  }
}

/// Clears the in-flight write latch between tests.
@visibleForTesting
void resetDriverAppThemePersistenceLatchForTest() {
  _driverAppThemeWriteInFlight = false;
  _driverAppThemeWriteSuperseded = false;
  _clearDriverCustomPreviewCheckpoint();
  _companyCustomPreviewActive = false;
  _companyCustomPreviewTheme = null;
  _chauffeurSelectorPreviewActive = false;
  _chauffeurSelectorPreviewStandalone = null;
  _chauffeurSelectorPreviewCompany = null;
  driverAppThemeNotifier.value = _kDefaultDriverAppTheme;
  driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
}

/// One-tap advance for the driver header theme shortcut.
Future<DriverThemeVariant> cycleDriverAppThemePreference() async {
  final next = nextDriverThemeVariant(driverAppThemeNotifier.value);
  await applyDriverAppThemePreference(next);
  return next;
}
