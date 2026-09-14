// COMPANY-CUSTOMER-OPS-P0 — existing business palette on customer-ops pages.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_dashboard_layout.dart';

const double kCompanyOpsTextContrastRatio = 4.5;
const double kCompanyOpsChromeContrastRatio = 3.0;

Color companyOpsEnsureContrast({
  required Color color,
  required Color background,
  required double minRatio,
  required Color toward,
}) {
  var current = color;
  for (var i = 0; i < 24; i += 1) {
    if (brandSignatureContrastRatio(current, background) >= minRatio) {
      return current;
    }
    current = Color.lerp(current, toward, 0.08)!;
  }
  return toward;
}

Color companyOpsReadableOn(Color background, BusinessThemePalette palette) {
  final candidates = <Color>[
    palette.textPrimary,
    palette.textOnAccent,
    palette.textSecondary,
    const Color(0xFFFFFFFF),
    const Color(0xFF101010),
  ];
  Color best = candidates.first;
  var bestRatio = brandSignatureContrastRatio(best, background);
  for (final candidate in candidates.skip(1)) {
    final ratio = brandSignatureContrastRatio(candidate, background);
    if (ratio > bestRatio) {
      best = candidate;
      bestRatio = ratio;
    }
  }
  if (bestRatio >= kCompanyOpsTextContrastRatio) return best;
  return companyOpsEnsureContrast(
    color: best,
    background: background,
    minRatio: kCompanyOpsTextContrastRatio,
    toward: background.computeLuminance() > 0.5
        ? const Color(0xFF101010)
        : const Color(0xFFFFFFFF),
  );
}

ColorScheme companyOpsColorScheme(BusinessThemePalette palette) {
  final brightness = palette.isDark ? Brightness.dark : Brightness.light;
  final outline = companyOpsEnsureContrast(
    color: palette.border,
    background: palette.surface,
    minRatio: kCompanyOpsChromeContrastRatio,
    toward: palette.textPrimary,
  );
  final outlineOnBackground = companyOpsEnsureContrast(
    color: outline,
    background: palette.background,
    minRatio: kCompanyOpsChromeContrastRatio,
    toward: palette.textPrimary,
  );
  final outlineOnAlt = companyOpsEnsureContrast(
    color: outline,
    background: palette.surfaceAlt,
    minRatio: kCompanyOpsChromeContrastRatio,
    toward: palette.textPrimary,
  );
  final chromeOutline = [
    outline,
    outlineOnBackground,
    outlineOnAlt,
  ].reduce((a, b) {
    final aMin = [
      brandSignatureContrastRatio(a, palette.surface),
      brandSignatureContrastRatio(a, palette.background),
      brandSignatureContrastRatio(a, palette.surfaceAlt),
    ].reduce((x, y) => x < y ? x : y);
    final bMin = [
      brandSignatureContrastRatio(b, palette.surface),
      brandSignatureContrastRatio(b, palette.background),
      brandSignatureContrastRatio(b, palette.surfaceAlt),
    ].reduce((x, y) => x < y ? x : y);
    return aMin <= bMin ? b : a;
  });
  final primaryContainer = Color.lerp(
    palette.surface,
    palette.accent,
    palette.isDark ? 0.34 : 0.18,
  )!;
  final onPrimaryContainer = companyOpsReadableOn(primaryContainer, palette);
  final lowest = palette.isDark
      ? Color.lerp(palette.background, const Color(0xFF000000), 0.18)!
      : palette.surface;
  final low = palette.isDark ? palette.background : palette.surface;
  final high = palette.surfaceAlt;
  final highest = Color.lerp(
    palette.surfaceAlt,
    palette.accent,
    palette.isDark ? 0.08 : 0.04,
  )!;
  return ColorScheme(
    brightness: brightness,
    primary: palette.accent,
    onPrimary: palette.textOnAccent,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondary: palette.accent,
    onSecondary: palette.textOnAccent,
    secondaryContainer: palette.accent,
    onSecondaryContainer: palette.textOnAccent,
    tertiary: palette.success,
    onTertiary: palette.textOnAccent,
    tertiaryContainer: Color.lerp(palette.surface, palette.success, 0.22)!,
    onTertiaryContainer: companyOpsReadableOn(
      Color.lerp(palette.surface, palette.success, 0.22)!,
      palette,
    ),
    error: palette.danger,
    onError: palette.textOnAccent,
    errorContainer: Color.lerp(palette.surface, palette.danger, 0.22)!,
    onErrorContainer: companyOpsReadableOn(
      Color.lerp(palette.surface, palette.danger, 0.22)!,
      palette,
    ),
    surface: palette.surface,
    onSurface: palette.textPrimary,
    onSurfaceVariant: palette.textSecondary,
    surfaceDim: palette.isDark ? palette.background : palette.surfaceAlt,
    surfaceBright: palette.isDark ? palette.surfaceAlt : palette.surface,
    surfaceContainerLowest: lowest,
    surfaceContainerLow: low,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: high,
    surfaceContainerHighest: highest,
    outline: chromeOutline,
    outlineVariant: chromeOutline,
    shadow: palette.shadow,
    scrim: const Color(0x99000000),
    inverseSurface: palette.textPrimary,
    onInverseSurface: palette.surface,
    inversePrimary: palette.accent,
    surfaceTint: Colors.transparent,
  );
}

ThemeData companyOpsMaterialTheme(BusinessThemePalette palette) {
  final brightness = palette.isDark ? Brightness.dark : Brightness.light;
  final scheme = companyOpsColorScheme(palette);
  final baseText = ThemeData(brightness: brightness).textTheme.apply(
    bodyColor: palette.textPrimary,
    displayColor: palette.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    applyElevationOverlayColor: false,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    cardColor: palette.surface,
    dividerColor: scheme.outline,
    textTheme: baseText,
    primaryTextTheme: baseText,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: palette.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: palette.shadow,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surface,
      selectedColor: palette.accent,
      disabledColor: palette.surfaceAlt,
      labelStyle: TextStyle(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: palette.textOnAccent,
        fontWeight: FontWeight.w700,
      ),
      secondarySelectedColor: palette.accent,
      checkmarkColor: palette.textOnAccent,
      side: BorderSide(color: scheme.outline),
      brightness: brightness,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.textOnAccent,
        disabledBackgroundColor: palette.surfaceAlt,
        disabledForegroundColor: palette.textMuted,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        disabledForegroundColor: palette.textMuted.withValues(alpha: 0.64),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: companyOpsEnsureContrast(
          color: palette.accent,
          background: palette.surface,
          minRatio: kCompanyOpsTextContrastRatio,
          toward: palette.textPrimary,
        ),
        disabledForegroundColor: palette.textMuted.withValues(alpha: 0.64),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.textPrimary,
        disabledForegroundColor: palette.textMuted.withValues(alpha: 0.55),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.accent, width: 1.4),
      ),
      filled: true,
      fillColor: palette.surfaceAlt,
      labelStyle: TextStyle(
        color: companyOpsEnsureContrast(
          color: palette.textSecondary,
          background: palette.surfaceAlt,
          minRatio: kCompanyOpsTextContrastRatio,
          toward: palette.textPrimary,
        ),
      ),
      hintStyle: TextStyle(
        color: companyOpsEnsureContrast(
          color: palette.textMuted,
          background: palette.surfaceAlt,
          minRatio: kCompanyOpsTextContrastRatio,
          toward: palette.textPrimary,
        ),
      ),
      helperMaxLines: 4,
      errorMaxLines: 3,
      alignLabelWithHint: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      titleTextStyle: baseText.titleLarge,
      contentTextStyle: baseText.bodyMedium,
    ),
    dividerTheme: DividerThemeData(color: scheme.outline),
    iconTheme: IconThemeData(color: palette.textPrimary),
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      trackVisibility: const WidgetStatePropertyAll(true),
      interactive: true,
      thickness: const WidgetStatePropertyAll(10),
      radius: const Radius.circular(8),
      thumbColor: WidgetStatePropertyAll(
        companyOpsEnsureContrast(
          color: palette.textSecondary,
          background: palette.surface,
          minRatio: kCompanyOpsChromeContrastRatio,
          toward: palette.textPrimary,
        ),
      ),
      trackColor: WidgetStatePropertyAll(palette.surfaceAlt),
      trackBorderColor: WidgetStatePropertyAll(scheme.outline),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.accent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? palette.textOnAccent : palette.textPrimary,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: palette.textPrimary,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
        );
      }),
    ),
  );
}

class CompanyOpsSelectableChip extends StatelessWidget {
  const CompanyOpsSelectableChip({
    super.key,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.avatar,
    this.showCheckmark = true,
  });

  final bool selected;
  final String label;
  final ValueChanged<bool> onSelected;
  final Widget? avatar;
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      showCheckmark: showCheckmark,
      checkmarkColor: scheme.onSecondaryContainer,
      avatar: avatar,
      label: Text(
        label,
        style: TextStyle(
          color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      selectedColor: scheme.secondaryContainer,
      backgroundColor: scheme.surface,
      disabledColor: scheme.surfaceContainerHigh,
      side: BorderSide(color: selected ? scheme.primary : scheme.outline),
      onSelected: onSelected,
    );
  }
}

class CompanyOpsThemedSurface extends StatelessWidget {
  const CompanyOpsThemedSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      child: child,
      builder: (context, variant, pageChild) {
        return ValueListenableBuilder<BrandSignaturePalette>(
          valueListenable: brandSignaturePaletteNotifier,
          child: pageChild,
          builder: (context, _, themedChild) {
            final palette = paletteForBusinessTheme(variant);
            return Theme(
              data: companyOpsMaterialTheme(palette),
              child: DefaultTextStyle(
                style: TextStyle(color: palette.textPrimary, fontSize: 14),
                child: themedChild!,
              ),
            );
          },
        );
      },
    );
  }
}

/// Use inside [CompanyOpsThemedSurface] so Theme.of sees the business palette.
class CompanyOpsThemedScope extends StatelessWidget {
  const CompanyOpsThemedScope({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(child: Builder(builder: builder));
  }
}

class CompanyOpsBoundedForm extends StatelessWidget {
  const CompanyOpsBoundedForm({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kCompanyDashboardFormMaxWidth,
        ),
        child: child,
      ),
    );
  }
}

BusinessThemePalette companyOpsCurrentPalette() {
  return paletteForBusinessTheme(businessThemeNotifier.value);
}

ColorScheme companyOpsCurrentScheme() {
  return companyOpsColorScheme(companyOpsCurrentPalette());
}

BoxDecoration companyOpsRootBoxDecoration() {
  final palette = paletteForBusinessTheme(businessThemeNotifier.value);
  final scheme = companyOpsColorScheme(palette);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        palette.background,
        palette.background,
        palette.surfaceAlt,
      ],
    ),
    border: Border.all(color: scheme.outline, width: 1.2),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: palette.accent.withValues(alpha: 0.16),
        blurRadius: 16,
        spreadRadius: 0.2,
      ),
    ],
  );
}
