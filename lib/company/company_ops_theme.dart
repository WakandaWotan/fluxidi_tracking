// COMPANY-CUSTOMER-OPS-P0 — existing business palette on customer-ops pages.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/company/company_dashboard_layout.dart';

ThemeData companyOpsMaterialTheme(BusinessThemePalette palette) {
  final scheme = palette.isDark
      ? ColorScheme.dark(
          primary: palette.accent,
          surface: palette.surface,
          error: palette.danger,
        )
      : ColorScheme.light(
          primary: palette.accent,
          surface: palette.surface,
          error: palette.danger,
        );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      onSurface: palette.textPrimary,
      onPrimary: palette.textOnAccent,
    ),
    scaffoldBackgroundColor: palette.background,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.textPrimary,
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

class CompanyOpsThemedSurface extends StatelessWidget {
  const CompanyOpsThemedSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: brandSignaturePaletteNotifier,
      child: child,
      builder: (context, _, pageChild) {
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        return Theme(
          data: companyOpsMaterialTheme(palette),
          child: pageChild!,
        );
      },
    );
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

BoxDecoration companyOpsRootBoxDecoration() {
  final preset = BusinessThemeVariant.brandSignatureGold;
  final palette = paletteForBusinessTheme(preset);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[palette.background, palette.background, palette.surfaceAlt],
    ),
    border: Border.all(color: palette.accent.withOpacity(0.34), width: 1.2),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: palette.accent.withOpacity(0.16),
        blurRadius: 16,
        spreadRadius: 0.2,
      ),
    ],
  );
}
