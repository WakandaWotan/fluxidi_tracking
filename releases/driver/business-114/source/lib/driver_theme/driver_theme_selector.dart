import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/company_driver_view_theme_store.dart';
import 'package:fluxidi_tracking/driver_app_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme/driver_custom_huis_stijl.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_style_dock.dart';

const Key kDriverThemeSelectorSheetKey = Key('driver_theme_selector_sheet');
const Key kDriverHomeThemeMenuTileKey = Key('driver_home_theme_menu_tile');

Key driverThemeSelectorTileKey(DriverThemeVariant variant) =>
    Key('driver_theme_selector_tile_${variant.name}');

/// Runtime chauffeur theme list. Brand Signature Gold is last.
List<DriverThemeVariant> get kDriverThemeSelectorVariants =>
    List<DriverThemeVariant>.unmodifiable(DriverThemeVariant.values);

ValueListenable<DriverThemeVariant> chauffeurThemeListenable({
  required bool companyDriverView,
}) {
  return companyDriverView
      ? companyDriverViewThemeNotifier
      : driverAppThemeNotifier;
}

/// Studio binding for the active chauffeur view. Never writes the business Gold store.
BrandSignatureStyleController chauffeurCustomStyleController({
  required bool companyDriverView,
}) {
  return BrandSignatureStyleController(
    paletteListenable: driverBrandSignaturePaletteNotifier,
    onPreviewColor: (color) => previewChauffeurCustomHuisstijlColor(
      color,
      companyDriverView: companyDriverView,
    ),
    onApply: (palette) => applyChauffeurCustomHuisstijlPalette(
      palette,
      companyDriverView: companyDriverView,
    ),
    onCancel: () => cancelChauffeurCustomHuisstijlPreview(
      companyDriverView: companyDriverView,
    ),
  );
}
