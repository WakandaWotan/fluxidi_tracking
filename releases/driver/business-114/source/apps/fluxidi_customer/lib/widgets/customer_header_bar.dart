import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import '../app/customer_theme.dart';
import '../bridge/customer_flows.dart';
import '../bridge/customer_language.dart';
import 'customer_language_sheet.dart';

/// Tight crops of the horizontal mark. Both header assets keep a measured
/// 2 px transparent margin on every side, so the visible F + FLUXIDI centre
/// matches the widget centre. Do not invent a screenshot-specific shift.
const String kCustomerHeaderLogoGold = 'assets/fluxidi/fluxidi_logo_header_gold.png';
const String kCustomerHeaderLogoDark = 'assets/fluxidi/fluxidi_logo_header_dark.png';

/// Visible width / height of the cropped horizontal Fluxidi mark.
const double kCustomerHeaderLogoAspect = 639 / 137;

/// Gap between the left-aligned mark and the language / theme cluster.
const double kCustomerHeaderLogoClearance = 8;

/// Top of the customer screens: the real Fluxidi logo, the language choice and
/// the palette button that opens the full existing theme picker.
class CustomerHeaderBar extends StatelessWidget {
  const CustomerHeaderBar({
    super.key,
    this.config = kCustomerAppConfig,
    this.showEnvironmentLabel = true,
  });

  final CustomerAppConfig config;
  final bool showEnvironmentLabel;

  @override
  Widget build(BuildContext context) {
    return CustomerLanguageBuilder(
      builder: (context, language) {
        final palette = activeCustomerPalette();
        final size = MediaQuery.sizeOf(context);
        final trailing = _HeaderTrailing(
          config: config,
          palette: palette,
          language: language,
          showEnvironmentLabel: showEnvironmentLabel,
        );
        final barHeight = headerBarHeight(
          width: size.width,
          height: size.height,
        );
        return SizedBox(
          height: barHeight,
          child: CustomMultiChildLayout(
            delegate: _LeftAlignedHeaderDelegate(
              screenWidth: size.width,
              screenHeight: size.height,
              barHeight: barHeight,
            ),
            children: <Widget>[
              LayoutId(
                id: _HeaderSlot.trailing,
                child: trailing,
              ),
              LayoutId(
                id: _HeaderSlot.logo,
                child: KeyedSubtree(
                  key: const Key('customer_header_logo_slot'),
                  child: Image.asset(
                    key: const Key('customer_header_logo'),
                    palette.isDark
                        ? kCustomerHeaderLogoGold
                        : kCustomerHeaderLogoDark,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _HeaderSlot { logo, trailing }

/// Puts the full mark on the left, above the page title. Trailing chips stay
/// on the right and only limit the width that is actually left over.
class _LeftAlignedHeaderDelegate extends MultiChildLayoutDelegate {
  _LeftAlignedHeaderDelegate({
    required this.screenWidth,
    required this.screenHeight,
    required this.barHeight,
  });

  final double screenWidth;
  final double screenHeight;
  final double barHeight;

  @override
  void performLayout(Size size) {
    final trailingSize = layoutChild(
      _HeaderSlot.trailing,
      BoxConstraints.loose(size),
    );
    positionChild(
      _HeaderSlot.trailing,
      Offset(
        size.width - trailingSize.width,
        (size.height - trailingSize.height) / 2,
      ),
    );

    final availableWidth = math.max(
      0.0,
      size.width - trailingSize.width - kCustomerHeaderLogoClearance,
    );
    final logoHeight = headerLogoHeight(
      availableWidth: availableWidth,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      barHeight: barHeight,
    );
    final logoWidth = math.min(
      availableWidth,
      logoHeight * kCustomerHeaderLogoAspect,
    );
    final fittedHeight = logoWidth / kCustomerHeaderLogoAspect;
    layoutChild(
      _HeaderSlot.logo,
      BoxConstraints.tight(Size(logoWidth, fittedHeight)),
    );
    positionChild(
      _HeaderSlot.logo,
      Offset(0, (size.height - fittedHeight) / 2),
    );
  }

  @override
  bool shouldRelayout(covariant _LeftAlignedHeaderDelegate oldDelegate) {
    return oldDelegate.screenWidth != screenWidth ||
        oldDelegate.screenHeight != screenHeight ||
        oldDelegate.barHeight != barHeight;
  }
}

/// Compact header row. A phone grows just enough for a readable wordmark;
/// the chips on the right stay small.
double headerBarHeight({required double width, required double height}) {
  final shortest = math.min(width, height);
  if (shortest < 600) return width < 340 ? 44.0 : 48.0;
  return 56.0;
}

/// Logo height for the width left of the trailing chips.
///
/// The header assets are 639×137 with a 2 px transparent margin, so the
/// visible mark is essentially the whole image. Height follows that aspect
/// ratio and is capped by the bar, never stretched.
double headerLogoHeight({
  required double availableWidth,
  required double screenWidth,
  required double screenHeight,
  double? barHeight,
}) {
  final shortest = math.min(screenWidth, screenHeight);
  final bar = barHeight ??
      headerBarHeight(width: screenWidth, height: screenHeight);
  final maxByBar = math.max(28.0, bar - 4);
  final maxByDevice = shortest < 600 ? 44.0 : 52.0;
  final maxByWidth = availableWidth / kCustomerHeaderLogoAspect;
  return math.min(maxByBar, math.min(maxByDevice, maxByWidth));
}

class _HeaderTrailing extends StatelessWidget {
  const _HeaderTrailing({
    required this.config,
    required this.palette,
    required this.language,
    required this.showEnvironmentLabel,
  });

  final CustomerAppConfig config;
  final CustomerThemePalette palette;
  final AppLanguage language;
  final bool showEnvironmentLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showEnvironmentLabel &&
            config.environmentLabel.trim().isNotEmpty) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: palette.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.gold.withValues(alpha: 0.5)),
            ),
            child: Text(
              config.environmentLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: palette.gold,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        _HeaderChip(
          chipKey: const Key('customer_header_language'),
          palette: palette,
          onTap: () => unawaited(showCustomerLanguageSheet(context)),
          child: Text(
            kCustomerLanguageShortLabels[language] ??
                language.name.toUpperCase(),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _HeaderChip(
          chipKey: const Key('customer_header_palette'),
          palette: palette,
          onTap: () => unawaited(openThemePicker(context)),
          child: Icon(
            Icons.palette_outlined,
            size: 20,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Compact control that stays readable on every customer palette.
///
/// A bare TextButton on cream used the gold link colour and disappeared
/// against the status bar. The chip uses the palette surface and a real
/// border so language and theme stay visible on both light and dark pages.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.chipKey,
    required this.palette,
    required this.onTap,
    required this.child,
  });

  final Key chipKey;
  final CustomerThemePalette palette;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border, width: 1.2),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
