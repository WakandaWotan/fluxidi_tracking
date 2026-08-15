import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

const Key kChauffeurGoldStatusBarRegionKey = Key(
  'chauffeur_gold_status_bar_region',
);

/// Light chauffeur pages (Gold/Custom, Light Emerald) need dark status-bar
/// icons. Dark chauffeur pages keep light icons.
SystemUiOverlayStyle systemUiOverlayStyleForDriverTheme(
  DriverThemePalette palette,
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
