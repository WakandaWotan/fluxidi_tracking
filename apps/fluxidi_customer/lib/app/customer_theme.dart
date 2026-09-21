import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';

import 'customer_app_config.dart';

/// App theme for the active customer theme variant.
///
/// The palette comes from the existing customer theme catalogue, so the theme
/// picker in Profile changes this app exactly like it changes the bridged
/// screens. The build-time brand colours stay as the seed for anything the
/// palette does not describe.
ThemeData buildCustomerTheme(
  CustomerAppConfig config, {
  CustomerThemeVariant? variant,
}) {
  final palette = paletteForCustomerTheme(
    variant ?? customerThemeNotifier.value,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: palette.isDark ? Brightness.dark : Brightness.light,
  );
  return themeForCustomerPalette(base, palette);
}

/// Palette the screens in this app read directly for photography overlays and
/// separators, which a [ThemeData] does not express.
CustomerThemePalette activeCustomerPalette() =>
    paletteForCustomerTheme(customerThemeNotifier.value);
