import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';

import 'customer_app_config.dart';

/// App theme for the active customer theme variant.
///
/// Colours come from the existing customer catalogue via
/// [themeForCustomerPalette], so the picker keeps the original eleven
/// palettes. This wrapper only fills the Material 3 slots that catalogue
/// helper does not set — NavigationBar, surface containers and the system
/// bars — which otherwise fall back to a dark default and ignore the choice.
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
  final themed = themeForCustomerPalette(base, palette);
  final overlay = systemUiOverlayStyleForCustomerTheme(palette);
  final onGold = customerOnGold(palette);

  return themed.copyWith(
    colorScheme: themed.colorScheme.copyWith(
      surface: palette.surface,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceAlt,
      surfaceContainerHighest: palette.surfaceAlt,
    ),
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    appBarTheme: themed.appBarTheme.copyWith(
      backgroundColor: palette.background,
      foregroundColor: palette.textPrimary,
      systemOverlayStyle: overlay,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.gold.withValues(
        alpha: palette.isDark ? 0.32 : 0.22,
      ),
      elevation: 0,
      shadowColor: palette.shadow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? palette.gold : palette.textMuted,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? palette.textPrimary : palette.textMuted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          fontSize: 12,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceAlt,
      contentTextStyle: TextStyle(color: palette.textPrimary),
      actionTextColor: palette.gold,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      titleTextStyle: TextStyle(
        color: palette.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      modalBackgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: palette.border),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.gold),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.gold,
      foregroundColor: onGold,
    ),
  );
}

/// Palette the screens in this app read directly for photography overlays and
/// separators, which a [ThemeData] does not express.
CustomerThemePalette activeCustomerPalette() =>
    paletteForCustomerTheme(customerThemeNotifier.value);

/// Status-bar and system-navigation contrast for the active customer palette.
///
/// Light page → dark status icons. Dark page → light status icons. Same
/// contract as the existing business and driver helpers.
SystemUiOverlayStyle systemUiOverlayStyleForCustomerTheme(
  CustomerThemePalette palette,
) {
  if (palette.isDark) {
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: palette.surface,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: palette.border,
    );
  }
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: palette.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: palette.border,
  );
}

void applyCustomerThemeSystemUiOverlay(CustomerThemePalette palette) {
  SystemChrome.setSystemUIOverlayStyle(
    systemUiOverlayStyleForCustomerTheme(palette),
  );
}
