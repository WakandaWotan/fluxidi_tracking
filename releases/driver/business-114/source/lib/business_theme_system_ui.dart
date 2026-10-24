import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';

/// Android/iOS status-bar contrast for the active business color palette.
///
/// Light page backgrounds → dark status-bar icons.
/// Dark page backgrounds → light status-bar icons.
SystemUiOverlayStyle systemUiOverlayStyleForBusinessTheme(
  BusinessThemePalette palette,
) {
  if (palette.isDark) {
    return const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    );
  }
  return const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );
}

/// Applies [systemUiOverlayStyleForBusinessTheme] immediately (e.g. on resume).
void applyBusinessThemeSystemUiOverlay(BusinessThemePalette palette) {
  SystemChrome.setSystemUIOverlayStyle(
    systemUiOverlayStyleForBusinessTheme(palette),
  );
}
