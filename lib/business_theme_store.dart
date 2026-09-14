import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'business_theme/brand_signature_palette.dart';
import 'business_theme_company_scope.dart';
import 'business_theme_cycle.dart';
import 'business_theme_palette.dart';
import 'business_theme_persist.dart';
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

const String _businessThemeFileName = 'business_theme_v1.json';
const String _businessAppearanceFileName = 'business_appearance_v1.json';
const String _publishedCustomerThemeFileName =
    'business_published_customer_theme_v1.json';
const String _businessHomeMobileLayoutFileName =
    'business_home_mobile_layout_v1.json';
const String _driverHomeMobileLayoutFileName =
    'driver_home_mobile_layout_v1.json';

Future<String?> _readBusinessThemeFile(String fileName) {
  return readBusinessThemeFileContents(fileName);
}

Future<void> _writeBusinessThemeFile(String fileName, String contents) {
  return writeBusinessThemeFileContents(fileName, contents);
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

BusinessThemeVariant _legacyGlobalBusinessTheme = _kDefaultBusinessTheme;
final Map<String, BusinessThemeVariant> _businessThemeByCompanyId =
    <String, BusinessThemeVariant>{};
final Map<String, BrandSignaturePalette> _brandSignaturePaletteByCompanyId =
    <String, BrandSignaturePalette>{};
final Map<String, CustomerThemeVariant> _publishedCustomerThemeByCompanyId =
    <String, CustomerThemeVariant>{};
final Map<String, DateTime> _themeUpdatedAtByCompanyId = <String, DateTime>{};
String? _themeCompanyScopeOverride;
bool _suppressCompanyThemeRemoteSync = false;

typedef BusinessThemeCompanyRemoteSync =
    Future<void> Function(
      String companyId,
      Map<String, dynamic> themeDocument,
    );

/// Optional hook so a theme apply can write the same company-profile document
/// the Worker already stores. Omitted profile saves must not wipe this.
BusinessThemeCompanyRemoteSync? businessThemeCompanyRemoteSync;

bool _businessThemePreviewActive = false;
BusinessThemeVariant? _previewCheckpointTheme;
BrandSignaturePalette? _previewCheckpointPalette;
String? _previewCompanyId;
bool _companyThemeListenerAttached = false;

/// True only while a dashboard/settings selector is showing an uncommitted
/// live preview. Restarts never restore this flag.
bool get isBusinessThemePreviewActive => _businessThemePreviewActive;

String? currentBusinessThemeCompanyId() {
  final override = (_themeCompanyScopeOverride ?? '').trim();
  if (override.isNotEmpty) return override;
  return readActiveCompanySessionId();
}

/// Binds the shared theme store to a company without a second preference model.
void bindBusinessThemeCompanyScope(String? companyId) {
  final next = (companyId ?? '').trim();
  _themeCompanyScopeOverride = next.isEmpty ? null : next;
  if (!_businessThemePreviewActive) {
    syncBusinessThemeForActiveCompany();
  }
}

BusinessThemeVariant resolveStoredBusinessThemeForCompany(String? companyId) {
  final id = (companyId ?? '').trim();
  if (id.isNotEmpty) {
    final scoped = _businessThemeByCompanyId[id];
    if (scoped != null) return scoped;
  }
  return _legacyGlobalBusinessTheme;
}

BrandSignaturePalette resolveStoredBrandSignaturePalette(String? companyId) {
  final id = (companyId ?? '').trim();
  if (id.isNotEmpty) {
    final scoped = _brandSignaturePaletteByCompanyId[id];
    if (scoped != null) return scoped;
  }
  return BrandSignaturePalette.defaults;
}

CustomerThemeVariant resolveStoredPublishedCustomerTheme(String? companyId) {
  final id = (companyId ?? '').trim();
  if (id.isNotEmpty) {
    final scoped = _publishedCustomerThemeByCompanyId[id];
    if (scoped != null) return scoped;
  }
  return businessPublishedCustomerThemeNotifier.value;
}

void _attachCompanyThemeListener() {
  if (_companyThemeListenerAttached) return;
  _companyThemeListenerAttached = true;
  listenToActiveCompanySession(syncBusinessThemeForActiveCompany);
}

/// Cancels any leaked preview and activates the stored theme for the live
/// company. Existing companies without a scoped entry keep the legacy global
/// variant — they are never auto-migrated to Brand Signature Gold.
void syncBusinessThemeForActiveCompany() {
  final companyId = currentBusinessThemeCompanyId();
  if (_businessThemePreviewActive &&
      _previewCompanyId != null &&
      _previewCompanyId != companyId) {
    cancelBusinessThemePreview();
  }
  if (_businessThemePreviewActive) return;
  final resolved = resolveStoredBusinessThemeForCompany(companyId);
  businessThemeNotifier.value = resolved;
  businessAppearanceNotifier.value = resolved;
  brandSignaturePaletteNotifier.value = resolveStoredBrandSignaturePalette(
    companyId,
  );
  businessPublishedCustomerThemeNotifier.value =
      resolveStoredPublishedCustomerTheme(companyId);
}

/// Starts a reversible live preview. Persistence is unchanged until apply.
void previewBusinessTheme(BusinessThemeVariant variant) {
  if (!_businessThemePreviewActive) {
    _previewCheckpointTheme = businessThemeNotifier.value;
    _previewCheckpointPalette = brandSignaturePaletteNotifier.value;
    _previewCompanyId = currentBusinessThemeCompanyId();
    _businessThemePreviewActive = true;
  }
  businessThemeNotifier.value = variant;
  businessAppearanceNotifier.value = variant;
}

void previewBrandSignaturePalette(BrandSignaturePalette palette) {
  if (!_businessThemePreviewActive) {
    _previewCheckpointTheme = businessThemeNotifier.value;
    _previewCheckpointPalette = brandSignaturePaletteNotifier.value;
    _previewCompanyId = currentBusinessThemeCompanyId();
    _businessThemePreviewActive = true;
  }
  brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
    palette.base,
  );
}

void previewBrandSignatureColor(Color color) {
  previewBrandSignaturePalette(BrandSignaturePalette.fromColor(color));
}

void previewBrandSignatureRailPosition(double position) {
  previewBrandSignaturePalette(BrandSignaturePalette.fromPosition(position));
}

void cancelBusinessThemePreview() {
  if (!_businessThemePreviewActive) return;
  final theme = _previewCheckpointTheme ?? _legacyGlobalBusinessTheme;
  final palette = _previewCheckpointPalette ?? BrandSignaturePalette.defaults;
  _clearPreviewCheckpoint();
  businessThemeNotifier.value = theme;
  businessAppearanceNotifier.value = theme;
  brandSignaturePaletteNotifier.value = palette;
}

void cancelBrandSignaturePalettePreview() {
  if (_previewCheckpointPalette != null) {
    brandSignaturePaletteNotifier.value = _previewCheckpointPalette!;
  }
  if (_previewCheckpointTheme == businessThemeNotifier.value) {
    _clearPreviewCheckpoint();
  }
}

void _clearPreviewCheckpoint() {
  _businessThemePreviewActive = false;
  _previewCheckpointTheme = null;
  _previewCheckpointPalette = null;
  _previewCompanyId = null;
}

Future<void> _writeBusinessThemeVariantFile(
  String fileName,
  BusinessThemeVariant variant,
) async {
  try {
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeBusinessThemeFile(fileName, jsonEncode(payload));
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

Map<String, String> _encodeThemeByCompany() {
  return <String, String>{
    for (final entry in _businessThemeByCompanyId.entries)
      entry.key: entry.value.name,
  };
}

Map<String, Map<String, Object>> _encodeBrandSignaturePalettes() {
  return <String, Map<String, Object>>{
    for (final entry in _brandSignaturePaletteByCompanyId.entries)
      entry.key: entry.value.toJson(),
  };
}

Map<String, String> _encodePublishedCustomerThemes() {
  return <String, String>{
    for (final entry in _publishedCustomerThemeByCompanyId.entries)
      entry.key: entry.value.name,
  };
}

Map<String, String> _encodeThemeUpdatedAtByCompany() {
  return <String, String>{
    for (final entry in _themeUpdatedAtByCompanyId.entries)
      entry.key: entry.value.toUtc().toIso8601String(),
  };
}

Future<void> _writeBusinessThemeDocument({
  required BusinessThemeVariant liveVariant,
  required bool updateLegacyGlobal,
}) async {
  try {
    if (updateLegacyGlobal) {
      _legacyGlobalBusinessTheme = liveVariant;
    }
    final payload = <String, dynamic>{
      'variant': _legacyGlobalBusinessTheme.name,
      'byCompanyId': _encodeThemeByCompany(),
      'brandSignaturePalettes': _encodeBrandSignaturePalettes(),
      'publishedCustomerThemes': _encodePublishedCustomerThemes(),
      'updatedAtByCompanyId': _encodeThemeUpdatedAtByCompany(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeBusinessThemeFile(_businessThemeFileName, jsonEncode(payload));
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
  _clearPreviewCheckpoint();
  businessThemeNotifier.value = variant;
  businessAppearanceNotifier.value = variant;
  final companyId = currentBusinessThemeCompanyId();
  if (companyId != null) {
    _businessThemeByCompanyId[companyId] = variant;
    _themeUpdatedAtByCompanyId[companyId] = DateTime.now().toUtc();
  }
  await _persistActiveBusinessThemePreset();
  await _syncCompanyThemeRemote(companyId);
}

Future<void> applyBrandSignaturePalette(BrandSignaturePalette palette) async {
  final safe = BrandSignaturePalette.fromColor(palette.base);
  _clearPreviewCheckpoint();
  brandSignaturePaletteNotifier.value = safe;
  final companyId = currentBusinessThemeCompanyId();
  if (companyId != null) {
    _brandSignaturePaletteByCompanyId[companyId] = safe;
    _themeUpdatedAtByCompanyId[companyId] = DateTime.now().toUtc();
  }
  await _persistActiveBusinessThemePreset();
  await _syncCompanyThemeRemote(companyId);
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
      await _writeBusinessThemeDocument(
        liveVariant: preset,
        updateLegacyGlobal: currentBusinessThemeCompanyId() == null,
      );
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
  _clearPreviewCheckpoint();
  _legacyGlobalBusinessTheme = _kDefaultBusinessTheme;
  _businessThemeByCompanyId.clear();
  _brandSignaturePaletteByCompanyId.clear();
  _publishedCustomerThemeByCompanyId.clear();
  _themeUpdatedAtByCompanyId.clear();
  _themeCompanyScopeOverride = null;
  _suppressCompanyThemeRemoteSync = false;
  businessThemeCompanyRemoteSync = null;
  resetBusinessThemeFilePersistForTest();
  businessThemeNotifier.value = _kDefaultBusinessTheme;
  businessAppearanceNotifier.value = _kDefaultBusinessTheme;
  brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
  businessPublishedCustomerThemeNotifier.value =
      _kDefaultPublishedCustomerTheme;
}

Future<void> loadBusinessThemePreference() async {
  _attachCompanyThemeListener();
  var restored = _kDefaultBusinessTheme;
  _businessThemeByCompanyId.clear();
  _brandSignaturePaletteByCompanyId.clear();
  _publishedCustomerThemeByCompanyId.clear();
  _themeUpdatedAtByCompanyId.clear();
  try {
    final raw = await _readBusinessThemeFile(_businessThemeFileName);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        restored = _businessThemeVariantFromStorage(
          (decoded['variant'] ?? '').toString(),
        );
        final byCompany = decoded['byCompanyId'];
        if (byCompany is Map) {
          byCompany.forEach((key, value) {
            final id = key.toString().trim();
            if (id.isEmpty) return;
            _businessThemeByCompanyId[id] = _businessThemeVariantFromStorage(
              value.toString(),
            );
          });
        }
        final palettes = decoded['brandSignaturePalettes'];
        if (palettes is Map) {
          palettes.forEach((key, value) {
            final id = key.toString().trim();
            if (id.isEmpty) return;
            _brandSignaturePaletteByCompanyId[id] =
                BrandSignaturePalette.fromJson(value);
          });
        }
        final publishedThemes = decoded['publishedCustomerThemes'];
        if (publishedThemes is Map) {
          publishedThemes.forEach((key, value) {
            final id = key.toString().trim();
            if (id.isEmpty) return;
            _publishedCustomerThemeByCompanyId[id] =
                _customerThemeVariantFromStorage(value.toString());
          });
        }
        final updatedAtByCompany = decoded['updatedAtByCompanyId'];
        if (updatedAtByCompany is Map) {
          updatedAtByCompany.forEach((key, value) {
            final id = key.toString().trim();
            final parsed = DateTime.tryParse(value.toString());
            if (id.isEmpty || parsed == null) return;
            _themeUpdatedAtByCompanyId[id] = parsed.toUtc();
          });
        }
      }
    }
  } catch (_) {
    restored = _kDefaultBusinessTheme;
  }
  _legacyGlobalBusinessTheme = restored;
  _clearPreviewCheckpoint();
  // Restore the complete preset: artwork can never come back stale.
  // Companies without a scoped entry keep [restored] — no auto-migration.
  final scoped = resolveStoredBusinessThemeForCompany(
    currentBusinessThemeCompanyId(),
  );
  businessThemeNotifier.value = scoped;
  businessAppearanceNotifier.value = scoped;
  brandSignaturePaletteNotifier.value = resolveStoredBrandSignaturePalette(
    currentBusinessThemeCompanyId(),
  );
  businessPublishedCustomerThemeNotifier.value =
      resolveStoredPublishedCustomerTheme(currentBusinessThemeCompanyId());
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
    final raw = await _readBusinessThemeFile(_businessAppearanceFileName);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
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
    final raw = await _readBusinessThemeFile(_publishedCustomerThemeFileName);
    if (raw == null || raw.trim().isEmpty) {
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
  final companyId = currentBusinessThemeCompanyId();
  if (companyId != null) {
    _publishedCustomerThemeByCompanyId[companyId] = variant;
    _themeUpdatedAtByCompanyId[companyId] = DateTime.now().toUtc();
  }
  try {
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeBusinessThemeFile(
      _publishedCustomerThemeFileName,
      jsonEncode(payload),
    );
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
  await _persistActiveBusinessThemePreset();
  await _syncCompanyThemeRemote(companyId);
}

Future<void> loadBusinessHomeMobileLayoutPreference() async {
  try {
    final raw = await _readBusinessThemeFile(_businessHomeMobileLayoutFileName);
    if (raw == null || raw.trim().isEmpty) {
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
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeBusinessThemeFile(
      _businessHomeMobileLayoutFileName,
      jsonEncode(payload),
    );
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

Future<void> loadDriverHomeMobileLayoutPreference() async {
  try {
    final raw = await _readBusinessThemeFile(_driverHomeMobileLayoutFileName);
    if (raw == null || raw.trim().isEmpty) {
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
    final payload = <String, dynamic>{
      'variant': variant.name,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeBusinessThemeFile(
      _driverHomeMobileLayoutFileName,
      jsonEncode(payload),
    );
  } catch (_) {
    // Keep in-memory value when persistence temporarily fails.
  }
}

Map<String, dynamic> encodeBusinessThemeForCompanyProfile([String? companyId]) {
  final id = (companyId ?? currentBusinessThemeCompanyId() ?? '').trim();
  final variant = id.isEmpty
      ? businessThemeNotifier.value
      : resolveStoredBusinessThemeForCompany(id);
  final palette = id.isEmpty
      ? brandSignaturePaletteNotifier.value
      : resolveStoredBrandSignaturePalette(id);
  final published = id.isEmpty
      ? businessPublishedCustomerThemeNotifier.value
      : resolveStoredPublishedCustomerTheme(id);
  final updatedAt =
      (id.isNotEmpty ? _themeUpdatedAtByCompanyId[id] : null) ??
      DateTime.now().toUtc();
  return <String, dynamic>{
    'business_theme': <String, dynamic>{
      'variant': variant.name,
      'updatedAt': updatedAt.toIso8601String(),
      'brandSignaturePalette': palette.toJson(),
      'publishedCustomerTheme': published.name,
    },
    'business_theme_variant': variant.name,
    'business_theme_updated_at': updatedAt.toIso8601String(),
    'published_customer_theme': published.name,
  };
}

/// Adopts a company-profile theme when it is newer than the local scoped value.
///
/// An empty profile theme never overwrites a conscious local choice.
Future<bool> hydrateBusinessThemeFromCompanyProfile({
  required String companyId,
  required Map<String, dynamic> profile,
}) async {
  final id = companyId.trim();
  if (id.isEmpty) return false;
  final document = _companyThemeDocumentFromProfile(profile);
  if (document == null) return false;
  final incomingAt = document.updatedAt;
  final localAt = _themeUpdatedAtByCompanyId[id];
  if (localAt != null &&
      incomingAt != null &&
      !incomingAt.isAfter(localAt)) {
    return false;
  }
  if (localAt != null && incomingAt == null) return false;
  _suppressCompanyThemeRemoteSync = true;
  try {
    _businessThemeByCompanyId[id] = document.variant;
    if (document.palette != null) {
      _brandSignaturePaletteByCompanyId[id] = document.palette!;
    }
    if (document.publishedCustomerTheme != null) {
      _publishedCustomerThemeByCompanyId[id] = document.publishedCustomerTheme!;
    }
    if (incomingAt != null) {
      _themeUpdatedAtByCompanyId[id] = incomingAt;
    }
    if (currentBusinessThemeCompanyId() == id && !_businessThemePreviewActive) {
      businessThemeNotifier.value = document.variant;
      businessAppearanceNotifier.value = document.variant;
      brandSignaturePaletteNotifier.value = resolveStoredBrandSignaturePalette(
        id,
      );
      businessPublishedCustomerThemeNotifier.value =
          resolveStoredPublishedCustomerTheme(id);
    }
    await _persistActiveBusinessThemePreset();
  } finally {
    _suppressCompanyThemeRemoteSync = false;
  }
  return true;
}

Future<void> _syncCompanyThemeRemote(String? companyId) async {
  if (_suppressCompanyThemeRemoteSync) return;
  final id = (companyId ?? '').trim();
  final sync = businessThemeCompanyRemoteSync;
  if (id.isEmpty || sync == null) return;
  try {
    await sync(id, encodeBusinessThemeForCompanyProfile(id));
  } catch (_) {
    // Local store remains the live value when the profile write fails.
  }
}

_CompanyThemeDocument? _companyThemeDocumentFromProfile(
  Map<String, dynamic> profile,
) {
  final nested = profile['business_theme'];
  final source = nested is Map
      ? Map<String, dynamic>.from(nested)
      : profile;
  final variantRaw = (source['variant'] ??
          source['business_theme_variant'] ??
          profile['business_theme_variant'] ??
          '')
      .toString()
      .trim();
  if (variantRaw.isEmpty) return null;
  final variant = _businessThemeVariantFromStorage(variantRaw);
  if (variant.name != variantRaw &&
      variant == _kDefaultBusinessTheme &&
      variantRaw != BusinessThemeVariant.executiveGold.name) {
    return null;
  }
  DateTime? updatedAt;
  for (final key in const <String>[
    'updatedAt',
    'updated_at',
    'business_theme_updated_at',
  ]) {
    final parsed = DateTime.tryParse(
      (source[key] ?? profile[key] ?? '').toString(),
    );
    if (parsed != null) {
      updatedAt = parsed.toUtc();
      break;
    }
  }
  final paletteRaw =
      source['brandSignaturePalette'] ?? source['brand_signature_palette'];
  final publishedRaw =
      source['publishedCustomerTheme'] ??
      source['published_customer_theme'] ??
      profile['published_customer_theme'];
  final publishedText = (publishedRaw ?? '').toString().trim();
  return _CompanyThemeDocument(
    variant: variant,
    updatedAt: updatedAt,
    palette: paletteRaw == null
        ? null
        : BrandSignaturePalette.fromJson(paletteRaw),
    publishedCustomerTheme: publishedText.isEmpty
        ? null
        : _customerThemeVariantFromStorage(publishedText),
  );
}

class _CompanyThemeDocument {
  const _CompanyThemeDocument({
    required this.variant,
    required this.updatedAt,
    required this.palette,
    required this.publishedCustomerTheme,
  });

  final BusinessThemeVariant variant;
  final DateTime? updatedAt;
  final BrandSignaturePalette? palette;
  final CustomerThemeVariant? publishedCustomerTheme;
}
