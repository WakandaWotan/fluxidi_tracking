import 'package:flutter/material.dart';
import '../business_theme_palette.dart';

/// Preserve system text scaling while fitting whole words in compact tiles.
/// Only reduce the base font when a single word would otherwise break apart.
Widget driverManagementReadableText(String value, {TextStyle? style}) =>
    LayoutBuilder(
      builder: (context, constraints) {
        final base = DefaultTextStyle.of(context).style.merge(style);
        var font = base.fontSize ?? 14.0;
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        bool fits() {
          for (final word in value.split(RegExp(r'\s+'))) {
            painter.text = TextSpan(
              text: word,
              style: base.copyWith(fontSize: font),
            );
            painter.layout();
            if (painter.width > constraints.maxWidth - 2) return false;
          }
          return true;
        }

        while (!fits() && font > 8) {
          font -= 0.25;
        }
        painter.dispose();
        return Text(value, style: base.copyWith(fontSize: font));
      },
    );

ThemeData driverManagementTheme(BusinessThemePalette p) => ThemeData(
  fontFamily: 'Roboto',
  brightness: p.isDark ? Brightness.dark : Brightness.light,
  scaffoldBackgroundColor: p.background,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: p.isDark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: p.accent,
        onPrimary: p.textOnAccent,
        surface: p.surface,
        onSurface: p.textPrimary,
        onSurfaceVariant: p.textSecondary,
        outline: p.textMuted,
      ),
  appBarTheme: AppBarTheme(
    backgroundColor: p.background,
    foregroundColor: p.textPrimary,
    surfaceTintColor: p.background,
  ),
  iconTheme: IconThemeData(color: p.accent),
  dividerColor: p.border,
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(disabledForegroundColor: p.textMuted),
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: p.surface,
    surfaceTintColor: p.surface,
    modalBarrierColor: p.shadow,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: p.surface,
    surfaceTintColor: p.surface,
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: p.surface,
    surfaceTintColor: p.surface,
    textStyle: TextStyle(color: p.textPrimary),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: p.surface,
    selectedColor: p.surfaceAlt,
    labelStyle: TextStyle(color: p.textPrimary, fontFamily: 'Roboto'),
    side: BorderSide(color: p.border),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: p.surface,
    hintStyle: TextStyle(color: p.textMuted),
    labelStyle: TextStyle(color: p.textSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.textMuted),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: p.textMuted),
    ),
  ),
);

Map<String, String> driverManagementThemeValues(BusinessThemePalette p) {
  String css(Color c) {
    final v = c.toARGB32();
    return '#${(v & 0xffffff).toRadixString(16).padLeft(6, '0')}${(v >> 24).toRadixString(16).padLeft(2, '0')}';
  }

  return {
    'background': css(p.background),
    'surface': css(p.surface),
    'surface-alt': css(p.surfaceAlt),
    'text': css(p.textPrimary),
    'muted': css(p.textMuted),
    'accent': css(p.accent),
    'on-accent': css(p.textOnAccent),
    'border': css(p.border),
    'shadow': css(p.shadow),
  };
}
