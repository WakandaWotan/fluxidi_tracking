import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme_cycle.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';

/// Compact one-tap control that cycles the complete company/business theme.
///
/// Applies one full preset per press through [applyBusinessThemePreset] — the
/// same canonical path the settings selector uses — so palette, system overlay
/// and Quick Actions artwork always move together.
/// Single tap only; no menu, dialog, or SnackBar loop.
class BusinessThemeCycleButton extends StatelessWidget {
  const BusinessThemeCycleButton({
    super.key,
    this.heroOverlay = false,
    this.onCycled,
  });

  /// When true (tablet hero header), keep a slightly stronger frosted chip so
  /// the control stays readable on photographic backgrounds.
  final bool heroOverlay;

  /// Optional test/hook callback after a successful cycle (not used for UX).
  final ValueChanged<BusinessThemeVariant>? onCycled;

  static const Key buttonKey = Key('business_theme_cycle_button');

  Future<void> _onTap() async {
    final next = nextBusinessThemeVariant(businessThemeNotifier.value);
    await applyBusinessThemePreset(next);
    onCycled?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForBusinessTheme(variant);
        final bg = heroOverlay
            ? palette.surface.withOpacity(palette.isDark ? 0.82 : 0.92)
            : palette.surfaceAlt.withOpacity(palette.isDark ? 0.92 : 1.0);
        final fg = palette.accent;
        final border = palette.accent.withOpacity(0.55);

        return Tooltip(
          message: kBusinessThemeCycleSemanticLabel,
          waitDuration: const Duration(milliseconds: 450),
          child: Semantics(
            button: true,
            label: kBusinessThemeCycleSemanticLabel,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: buttonKey,
                onTap: () => unawaited(_onTap()),
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: 20,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Structural header region used by Business Home and layout tests.
///
/// Places the theme-cycle control at the lower-right of the header, above the
/// KPI slot, without growing header height when [fixedHeight] is set.
class BusinessHomeHeaderThemeRegion extends StatelessWidget {
  const BusinessHomeHeaderThemeRegion({
    super.key,
    required this.mode,
    required this.topBar,
    required this.greeting,
    required this.subtitle,
    this.fixedHeight,
    this.contentPadding = const EdgeInsets.fromLTRB(12, 12, 12, 14),
    this.greetingStyle,
    this.subtitleStyle,
    this.textGap = 3.0,
    this.heroBackground,
    this.heroDecoration,
  });

  /// `hero` = tablet image header; `panel` = phone (portrait/landscape) panel.
  final BusinessHomeHeaderThemeMode mode;
  final Widget topBar;
  final String greeting;
  final String subtitle;
  final double? fixedHeight;
  final EdgeInsets contentPadding;
  final TextStyle? greetingStyle;
  final TextStyle? subtitleStyle;
  final double textGap;
  final Widget? heroBackground;
  final BoxDecoration? heroDecoration;

  static const Key regionKey = Key('business_home_header_theme_region');
  static const Key greetingKey = Key('business_home_header_greeting');
  static const Key companyChipKey = Key('business_home_header_company_chip');
  static const Key kpiSlotKey = Key('business_home_kpi_below_header');

  /// Right reserve so greeting/subtitle never collide with the cycle button.
  static const double textRightReserve = 48;

  @override
  Widget build(BuildContext context) {
    final cycleButton = BusinessThemeCycleButton(
      heroOverlay: mode == BusinessHomeHeaderThemeMode.hero,
    );

    if (mode == BusinessHomeHeaderThemeMode.hero) {
      return SizedBox(
        key: regionKey,
        height: fixedHeight,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: heroDecoration,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (heroBackground != null) Positioned.fill(child: heroBackground!),
              Positioned.fill(
                child: Padding(
                  padding: contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KeyedSubtree(key: companyChipKey, child: topBar),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: textRightReserve),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              greeting,
                              key: greetingKey,
                              style: greetingStyle,
                            ),
                            SizedBox(height: textGap),
                            Text(subtitle, style: subtitleStyle),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: contentPadding.right,
                bottom: contentPadding.bottom,
                child: cycleButton,
              ),
            ],
          ),
        ),
      );
    }

    // Phone panel: top bar outside the greeting panel (matches Business Home).
    return Column(
      key: regionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: companyChipKey, child: topBar),
        const SizedBox(height: 12),
        Container(
          decoration: heroDecoration,
          padding: contentPadding,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: textRightReserve),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      key: greetingKey,
                      style: greetingStyle,
                    ),
                    SizedBox(height: textGap),
                    Text(subtitle, style: subtitleStyle),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: cycleButton,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum BusinessHomeHeaderThemeMode { hero, panel }
