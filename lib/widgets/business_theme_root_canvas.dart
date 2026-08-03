import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/business_theme_system_ui.dart';

/// Canonical business-dashboard root background color.
///
/// Every preset — including Corporate Blue — resolves through
/// [paletteForBusinessTheme]. There is no separate hardcoded navy owner.
Color businessThemeRootBackground(BusinessThemeVariant preset) =>
    paletteForBusinessTheme(preset).background;

/// Canonical business-dashboard page gradient (top → bottom).
List<Color> businessThemeRootGradientColors(BusinessThemeVariant preset) {
  final palette = paletteForBusinessTheme(preset);
  return <Color>[
    palette.background,
    palette.background,
    palette.surfaceAlt,
  ];
}

/// Full root [BoxDecoration] (gradient + outer frame accents) for one preset.
BoxDecoration businessThemeRootBoxDecoration(BusinessThemeVariant preset) {
  final palette = paletteForBusinessTheme(preset);
  final isExecutiveGold = preset == BusinessThemeVariant.executiveGold;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: businessThemeRootGradientColors(preset),
    ),
    border: Border.all(
      color: !isExecutiveGold
          ? palette.accent.withOpacity(0.34)
          : Colors.transparent,
      width: !isExecutiveGold ? 1.2 : 0,
    ),
    boxShadow: !isExecutiveGold
        ? <BoxShadow>[
            BoxShadow(
              color: palette.accent.withOpacity(0.16),
              blurRadius: 16,
              spreadRadius: 0.2,
            ),
          ]
        : null,
  );
}

/// Legacy Corporate Blue root hardcodes that must never own the canvas again.
const Set<int> kForbiddenCorporateBlueRootColorValues = <int>{
  0xFF0A1324,
  0xFF13213A,
};

bool isForbiddenCorporateBlueRootColor(Color color) =>
    kForbiddenCorporateBlueRootColorValues.contains(color.value);

/// Production root chrome for Business Home: Scaffold + page gradient owned by
/// [activeBusinessThemePreset] / [businessThemeNotifier].
///
/// Cards, Quick Actions artwork and this canvas must rebuild from the same
/// notifier so a theme press can never leave a stale Corporate Blue root.
class BusinessThemeRootCanvas extends StatelessWidget {
  const BusinessThemeRootCanvas({
    super.key,
    required this.child,
    this.wrapSafeArea = true,
  });

  static const Key scaffoldKey = ValueKey<String>('business_theme_root_scaffold');
  static const Key gradientKey = ValueKey<String>('business_theme_root_gradient');

  final Widget child;
  final bool wrapSafeArea;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, _, __) {
        final preset = activeBusinessThemePreset();
        final palette = paletteForBusinessTheme(preset);
        final gradient = DecoratedBox(
          key: gradientKey,
          decoration: businessThemeRootBoxDecoration(preset),
          child: child,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: systemUiOverlayStyleForBusinessTheme(palette),
          child: Scaffold(
            key: scaffoldKey,
            backgroundColor: businessThemeRootBackground(preset),
            body: wrapSafeArea ? SafeArea(child: gradient) : gradient,
          ),
        );
      },
    );
  }
}
