// FLUXIDI-BUSINESS-THEME-COHERENT-PRESET-REPAIR-P0-1
//
// One canonical mapping from the active business theme preset to the artwork
// Fluxidi owns for it.
//
// A business theme is a complete preset: palette, borders, typography, system
// overlay AND artwork. Resolving artwork from a second, separately advanced
// owner is what allowed Clean Professional colors to render Neon Rush images.
// Every artwork lookup therefore goes through this file, keyed by the same
// preset value the palette is derived from.
//
// This file covers Fluxidi theme-owned artwork only. The company's uploaded
// logo and company identity are company-owned branding, live in the tenant
// settings state, and are never resolved here.

import 'business_theme/brand_signature_gold_assets.dart';
import 'business_theme_palette.dart';

/// Resolves the Fluxidi theme-owned artwork asset for [preset].
///
/// [executiveGold] is the required baseline. A preset without a dedicated asset
/// falls back to that baseline rather than keeping the previously selected
/// preset's artwork, so artwork can never lag behind the colors.
String businessThemePresetAsset({
  required BusinessThemeVariant preset,
  required String executiveGold,
  String? corporateBlue,
  String? cleanProfessional,
  String? emeraldIvory,
  String? fluxidiNeonRush,
  String? brandSignatureGold,
}) {
  switch (preset) {
    case BusinessThemeVariant.executiveGold:
      return executiveGold;
    case BusinessThemeVariant.corporateBlue:
      return corporateBlue ?? executiveGold;
    case BusinessThemeVariant.cleanProfessional:
      return cleanProfessional ?? executiveGold;
    case BusinessThemeVariant.emeraldIvory:
      return emeraldIvory ?? executiveGold;
    case BusinessThemeVariant.fluxidiNeonRush:
      return fluxidiNeonRush ?? executiveGold;
    case BusinessThemeVariant.brandSignatureGold:
      return brandSignatureGold ?? kBrandSignatureGoldSettingsAsset;
  }
}

/// Asset-path fragment that identifies each preset's own artwork pack.
///
/// Used by contract tests to prove a preset never renders another preset's
/// images. Executive Gold ships from the shared `assets/fluxidi/` folder, so its
/// marker is that folder rather than a preset-specific one.
const Map<BusinessThemeVariant, String> kBusinessThemeArtworkPackMarkers =
    <BusinessThemeVariant, String>{
      BusinessThemeVariant.executiveGold: 'assets/fluxidi/',
      BusinessThemeVariant.corporateBlue: 'corporate_blue',
      BusinessThemeVariant.cleanProfessional: 'clean_professional',
      BusinessThemeVariant.emeraldIvory: 'emerald_ivory',
      BusinessThemeVariant.fluxidiNeonRush: 'neon_rush',
      BusinessThemeVariant.brandSignatureGold: kBrandSignatureGoldPackMarker,
    };

/// Whether [asset] belongs to [preset]'s own artwork pack.
bool businessThemeAssetMatchesPreset({
  required String asset,
  required BusinessThemeVariant preset,
}) {
  final marker = kBusinessThemeArtworkPackMarkers[preset];
  if (marker == null || marker.isEmpty) return false;
  return asset.toLowerCase().contains(marker.toLowerCase());
}
