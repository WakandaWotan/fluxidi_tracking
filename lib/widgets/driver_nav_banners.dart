import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';

class DriverTurnInstructionBanner extends StatelessWidget {
  final bool compact;
  final bool isTablet;
  final bool topRowLandscape;
  final bool isArrival;
  final bool isHighwayLike;
  final String distancePrefix;
  final String distanceText;
  final String primaryText;
  final String secondaryText;
  final String? subText;
  final IconData icon;
  final List<DriverNavLaneGuidance> lanes;
  final String maneuverModifier;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverTurnInstructionBanner({
    super.key,
    required this.compact,
    required this.isTablet,
    this.topRowLandscape = false,
    required this.isArrival,
    required this.isHighwayLike,
    required this.distancePrefix,
    required this.distanceText,
    required this.primaryText,
    required this.secondaryText,
    this.subText,
    required this.icon,
    this.lanes = const <DriverNavLaneGuidance>[],
    this.maneuverModifier = '',
    this.themeListenable,
  });

  bool get _usePhonePortraitStack => !compact && !isTablet;

  bool get _useLandscapeTopRow => compact && topRowLandscape;

  bool get _useLandscapeCompactRow => compact && !topRowLandscape;

  double get _iconBoxSize {
    if (_useLandscapeTopRow) return isTablet ? 36 : 32;
    if (_useLandscapeCompactRow) return isTablet ? 44 : 40;
    if (compact) return isTablet ? 50 : 44;
    if (_usePhonePortraitStack) return 48;
    return isTablet ? 64 : 56;
  }

  double get _iconSize {
    if (_useLandscapeTopRow) return isTablet ? 20 : 18;
    if (_useLandscapeCompactRow) return isTablet ? 24 : 22;
    if (compact) return isTablet ? 30 : 26;
    if (_usePhonePortraitStack) return 28;
    return isTablet ? 38 : 32;
  }

  double get _distanceFontSize {
    if (_useLandscapeTopRow) return isTablet ? 12 : 11;
    if (_useLandscapeCompactRow) return isTablet ? 13 : 12;
    if (compact) return isTablet ? 14 : 13;
    if (_usePhonePortraitStack) return 15;
    return isTablet ? 18 : 16;
  }

  double get _primaryFontSize {
    if (_useLandscapeTopRow) return isTablet ? 14 : 13;
    if (_useLandscapeCompactRow) return isTablet ? 16 : 15;
    if (compact) return isTablet ? 17 : 16;
    if (_usePhonePortraitStack) return 18;
    return isTablet ? 22 : 20;
  }

  double get _secondaryFontSize {
    if (_useLandscapeCompactRow) return isTablet ? 11 : 10;
    if (compact) return isTablet ? 13 : 12;
    if (_usePhonePortraitStack) return 12;
    return isTablet ? 16 : 14;
  }

  int get _primaryMaxLines {
    if (_usePhonePortraitStack ||
        _useLandscapeCompactRow ||
        _useLandscapeTopRow) {
      return 1;
    }
    if (compact) return 2;
    return isTablet ? 2 : 2;
  }

  int get _secondaryMaxLines {
    if (_usePhonePortraitStack ||
        _useLandscapeCompactRow ||
        _useLandscapeTopRow) {
      return 1;
    }
    return compact ? 1 : 2;
  }

  double get _minBannerHeight {
    if (_useLandscapeTopRow) return isTablet ? 60 : 52;
    if (_useLandscapeCompactRow) return isTablet ? 80 : 72;
    if (compact) return isTablet ? 88 : 80;
    if (_usePhonePortraitStack) return 76;
    return isTablet ? 112 : 96;
  }

  List<DriverNavLaneGuidance> get _displayLanes =>
      driverNavLanesForBannerDisplay(lanes);

  bool get _showLaneGuidance => _displayLanes.isNotEmpty;

  double get _laneRowHeight {
    if (_useLandscapeTopRow) return isTablet ? 22 : 20;
    if (_useLandscapeCompactRow) return isTablet ? 24 : 22;
    if (compact) return isTablet ? 26 : 24;
    return isTablet ? 28 : 26;
  }

  double get _lanePillMinWidth {
    if (_useLandscapeTopRow) return isTablet ? 24 : 22;
    if (compact) return isTablet ? 28 : 26;
    return isTablet ? 32 : 28;
  }

  double get _laneArrowFontSize {
    if (_useLandscapeTopRow) return isTablet ? 13 : 12;
    if (compact) return isTablet ? 15 : 14;
    return isTablet ? 17 : 16;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        final borderColor = isHighwayLike
            ? const Color(0xFFFFD36A).withOpacity(palette.isDark ? 0.82 : 0.95)
            : palette.border.withOpacity(palette.isDark ? 0.68 : 0.9);
        final secondaryLine = _secondaryLine();
        final showSecondary = _shouldShowSecondaryLine(secondaryLine);
        final displayLanes = _displayLanes;
        final showLaneGuidance = displayLanes.isNotEmpty;
        if (showLaneGuidance && kDebugMode) {
          final recommendedCount = displayLanes
              .where(driverLaneIsRecommended)
              .length;
          debugPrint(
            '[NAV_E4] lanes=${displayLanes.length} '
            'recommended=$recommendedCount source=snapshot',
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(
            _useLandscapeTopRow || _useLandscapeCompactRow
                ? 14
                : (compact ? 16 : 18),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: compact ? 10 : 12,
              sigmaY: compact ? 10 : 12,
            ),
            child: Container(
              constraints: BoxConstraints(
                minHeight:
                    _minBannerHeight +
                    (showLaneGuidance ? (_laneRowHeight + 4) : 0),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: _useLandscapeTopRow
                    ? 6
                    : (_useLandscapeCompactRow
                          ? 8
                          : (compact
                                ? 10
                                : (_usePhonePortraitStack ? 12 : 14))),
                vertical: _useLandscapeTopRow
                    ? 4
                    : (_useLandscapeCompactRow
                          ? 6
                          : (compact ? 8 : (_usePhonePortraitStack ? 8 : 10))),
              ),
              decoration: BoxDecoration(
                color: palette.surface.withOpacity(
                  palette.isDark ? 0.90 : 0.96,
                ),
                borderRadius: BorderRadius.circular(
                  _useLandscapeTopRow || _useLandscapeCompactRow
                      ? 14
                      : (compact ? 16 : 18),
                ),
                border: Border.all(
                  color: borderColor,
                  width: isHighwayLike ? 1.8 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withOpacity(
                      palette.isDark ? 0.62 : 0.34,
                    ),
                    blurRadius: isHighwayLike ? 16 : 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildManeuverIcon(palette),
                      SizedBox(
                        width: _useLandscapeTopRow
                            ? 6
                            : (_useLandscapeCompactRow
                                  ? 8
                                  : (compact
                                        ? 10
                                        : (_usePhonePortraitStack ? 10 : 12))),
                      ),
                      Expanded(
                        child: _usePhonePortraitStack
                            ? _buildPhonePortraitTextColumn(
                                palette: palette,
                                secondaryLine: secondaryLine,
                                showSecondary: showSecondary,
                              )
                            : _useLandscapeTopRow
                            ? _buildLandscapeTopRowTextBlock(palette: palette)
                            : _useLandscapeCompactRow
                            ? _buildLandscapeCompactTextBlock(
                                palette: palette,
                                secondaryLine: secondaryLine,
                                showSecondary: showSecondary,
                              )
                            : _buildDefaultTextColumn(
                                palette: palette,
                                secondaryLine: secondaryLine,
                                showSecondary: showSecondary,
                              ),
                      ),
                    ],
                  ),
                  if (showLaneGuidance) ...[
                    SizedBox(height: _useLandscapeTopRow ? 3 : 4),
                    _LaneGuidanceRow(
                      lanes: displayLanes,
                      palette: palette,
                      isHighwayLike: isHighwayLike,
                      maneuverModifier: maneuverModifier,
                      rowHeight: _laneRowHeight,
                      pillMinWidth: _lanePillMinWidth,
                      arrowFontSize: _laneArrowFontSize,
                      compact: compact || _useLandscapeTopRow,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildManeuverIcon(DriverThemePalette palette) {
    return Container(
      width: _iconBoxSize,
      height: _iconBoxSize,
      decoration: BoxDecoration(
        color: isHighwayLike ? const Color(0xFFFFD36A) : palette.accent,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(
          color: palette.textPrimary.withOpacity(0.80),
          width: 1.4,
        ),
      ),
      child: Icon(
        icon,
        size: _iconSize,
        color: palette.isDark ? Colors.black : Colors.white,
      ),
    );
  }

  Widget _buildDistanceChip(DriverThemePalette palette) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : (_usePhonePortraitStack ? 9 : 10),
        vertical: compact ? 4 : (_usePhonePortraitStack ? 4 : 5),
      ),
      decoration: BoxDecoration(
        color: palette.accent.withOpacity(isHighwayLike ? 0.30 : 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.textPrimary.withOpacity(0.20)),
      ),
      child: Text(
        '$distancePrefix $distanceText',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: _distanceFontSize,
          fontWeight: FontWeight.w900,
          color: palette.textPrimary.withOpacity(0.98),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildPrimaryText(DriverThemePalette palette, {int? maxLines}) {
    return Text(
      primaryText,
      maxLines: maxLines ?? _primaryMaxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _primaryFontSize,
        fontWeight: FontWeight.w900,
        color: palette.textPrimary,
        height: 1.08,
      ),
    );
  }

  Widget _buildSecondaryText(
    DriverThemePalette palette,
    String secondaryLine, {
    int? maxLines,
  }) {
    return Text(
      secondaryLine,
      maxLines: maxLines ?? _secondaryMaxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _secondaryFontSize,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary.withOpacity(0.82),
        height: 1.10,
      ),
    );
  }

  Widget _buildPhonePortraitTextColumn({
    required DriverThemePalette palette,
    required String secondaryLine,
    required bool showSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isArrival) _buildDistanceChip(palette),
        if (isArrival) _buildPrimaryText(palette, maxLines: 2),
        if (!isArrival) ...[
          const SizedBox(height: 4),
          _buildPrimaryText(palette, maxLines: 1),
        ],
        if (showSecondary) ...[
          const SizedBox(height: 2),
          _buildSecondaryText(palette, secondaryLine, maxLines: 1),
        ],
      ],
    );
  }

  Widget _buildLandscapeTopRowTextBlock({required DriverThemePalette palette}) {
    if (isArrival) {
      return _buildPrimaryText(palette, maxLines: 1);
    }
    return Row(
      children: [
        _buildDistanceChip(palette),
        const SizedBox(width: 6),
        Expanded(child: _buildPrimaryText(palette, maxLines: 1)),
      ],
    );
  }

  Widget _buildLandscapeCompactTextBlock({
    required DriverThemePalette palette,
    required String secondaryLine,
    required bool showSecondary,
  }) {
    final showLandscapeSecondary = showSecondary && secondaryLine.length <= 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isArrival)
          Row(
            children: [
              _buildDistanceChip(palette),
              const SizedBox(width: 8),
              Expanded(child: _buildPrimaryText(palette, maxLines: 1)),
            ],
          )
        else
          _buildPrimaryText(palette, maxLines: 1),
        if (showLandscapeSecondary) ...[
          const SizedBox(height: 2),
          _buildSecondaryText(palette, secondaryLine, maxLines: 1),
        ],
      ],
    );
  }

  Widget _buildDefaultTextColumn({
    required DriverThemePalette palette,
    required String secondaryLine,
    required bool showSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isArrival)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDistanceChip(palette),
              SizedBox(width: compact ? 8 : 10),
              Expanded(child: _buildPrimaryText(palette)),
            ],
          )
        else
          _buildPrimaryText(palette),
        if (showSecondary) ...[
          SizedBox(height: compact ? 3 : 4),
          _buildSecondaryText(palette, secondaryLine),
        ],
      ],
    );
  }

  bool _shouldShowSecondaryLine(String secondaryLine) {
    if (secondaryLine.isEmpty) return false;
    if (_useLandscapeTopRow) return false;
    if (_usePhonePortraitStack || _useLandscapeCompactRow) {
      final primary = primaryText.trim();
      if (secondaryLine.length > 28) return false;
      if (primary.length > 34 && secondaryLine.length > 16) return false;
    }
    return true;
  }

  String _secondaryLine() {
    final parts = <String>[];
    final secondary = secondaryText.trim();
    final sub = (subText ?? '').trim();
    if (secondary.isNotEmpty) parts.add(secondary);
    if (sub.isNotEmpty && sub != secondary) parts.add(sub);
    return parts.join(' • ');
  }
}

class _LaneGuidanceRow extends StatelessWidget {
  const _LaneGuidanceRow({
    required this.lanes,
    required this.palette,
    required this.isHighwayLike,
    required this.maneuverModifier,
    required this.rowHeight,
    required this.pillMinWidth,
    required this.arrowFontSize,
    required this.compact,
  });

  final List<DriverNavLaneGuidance> lanes;
  final DriverThemePalette palette;
  final bool isHighwayLike;
  final String maneuverModifier;
  final double rowHeight;
  final double pillMinWidth;
  final double arrowFontSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: lanes.length > 6
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(left: compact ? 2 : 4),
        itemCount: lanes.length,
        separatorBuilder: (_, __) => SizedBox(width: compact ? 4 : 5),
        itemBuilder: (context, index) {
          return _LanePill(
            lane: lanes[index],
            palette: palette,
            isHighwayLike: isHighwayLike,
            maneuverModifier: maneuverModifier,
            minWidth: pillMinWidth,
            arrowFontSize: arrowFontSize,
            compact: compact,
          );
        },
      ),
    );
  }
}

class _LanePill extends StatelessWidget {
  const _LanePill({
    required this.lane,
    required this.palette,
    required this.isHighwayLike,
    required this.maneuverModifier,
    required this.minWidth,
    required this.arrowFontSize,
    required this.compact,
  });

  final DriverNavLaneGuidance lane;
  final DriverThemePalette palette;
  final bool isHighwayLike;
  final String maneuverModifier;
  final double minWidth;
  final double arrowFontSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final recommended = driverLaneIsRecommended(lane);
    final indication = driverLaneIndicationForDisplay(
      lane,
      maneuverModifier: maneuverModifier,
    );
    final hasArrow = (indication ?? '').trim().isNotEmpty;
    if (!hasArrow && !recommended) {
      return const SizedBox.shrink();
    }
    final arrow = hasArrow ? driverLaneIndicationArrow(indication!) : '—';
    final semanticLabel = driverLaneSemanticLabel(
      lane,
      maneuverModifier: maneuverModifier,
    );
    final accent = isHighwayLike ? const Color(0xFFFFD36A) : palette.accent;
    final bgOpacity = recommended
        ? (palette.isDark ? 0.34 : 0.28)
        : (palette.isDark ? 0.10 : 0.08);
    final borderOpacity = recommended
        ? (isHighwayLike ? 0.92 : 0.78)
        : (palette.isDark ? 0.22 : 0.18);
    final textOpacity = recommended ? 0.98 : 0.42;

    return Semantics(
      label: semanticLabel,
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: accent.withOpacity(bgOpacity),
          borderRadius: BorderRadius.circular(compact ? 6 : 7),
          border: Border.all(
            color: accent.withOpacity(borderOpacity),
            width: recommended ? 1.4 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          arrow,
          style: TextStyle(
            fontSize: arrowFontSize,
            fontWeight: recommended ? FontWeight.w900 : FontWeight.w600,
            color: palette.textPrimary.withOpacity(textOpacity),
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class DriverNavLoadingBanner extends StatelessWidget {
  final bool compact;
  final bool isTablet;
  final bool topRowLandscape;
  final String text;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverNavLoadingBanner({
    super.key,
    required this.compact,
    this.isTablet = false,
    this.topRowLandscape = false,
    this.text = 'Route-instructies worden geladen...',
    this.themeListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        return ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: compact ? 8 : 10,
              sigmaY: compact ? 8 : 10,
            ),
            child: Container(
              constraints: BoxConstraints(
                minHeight: topRowLandscape
                    ? (isTablet ? 56 : 52)
                    : (compact ? 52 : (isTablet ? 64 : 56)),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: topRowLandscape ? 8 : (compact ? 12 : 14),
                vertical: topRowLandscape ? 6 : (compact ? 8 : 10),
              ),
              decoration: BoxDecoration(
                color: palette.surfaceAlt.withOpacity(
                  palette.isDark ? 0.84 : 0.95,
                ),
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(
                  color: palette.border.withOpacity(
                    palette.isDark ? 0.55 : 0.85,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: topRowLandscape ? 16 : (compact ? 18 : 20),
                    height: topRowLandscape ? 16 : (compact ? 18 : 20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: palette.accent,
                    ),
                  ),
                  SizedBox(width: topRowLandscape ? 8 : (compact ? 10 : 12)),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: topRowLandscape ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: topRowLandscape
                            ? (isTablet ? 12 : 11)
                            : (compact ? 13 : (isTablet ? 16 : 14)),
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary.withOpacity(0.94),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// NAV-R14: calm local caution when Fluxidi OS detects a complex zone.
class DriverNavComplexityCautionBanner extends StatelessWidget {
  final bool compact;
  final bool isTablet;
  final bool topRowLandscape;
  final String title;
  final String body;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverNavComplexityCautionBanner({
    super.key,
    required this.compact,
    this.isTablet = false,
    this.topRowLandscape = false,
    required this.title,
    required this.body,
    this.themeListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        const caution = Color(0xFFFFB020);
        return ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: compact ? 8 : 10,
              sigmaY: compact ? 8 : 10,
            ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: topRowLandscape ? 8 : (compact ? 10 : 12),
                vertical: topRowLandscape ? 5 : (compact ? 6 : 8),
              ),
              decoration: BoxDecoration(
                color: palette.surface.withOpacity(
                  palette.isDark ? 0.92 : 0.96,
                ),
                borderRadius: BorderRadius.circular(compact ? 12 : 14),
                border: Border.all(
                  color: caution.withOpacity(palette.isDark ? 0.85 : 0.95),
                  width: 1.4,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: topRowLandscape ? 18 : (compact ? 20 : 22),
                    color: caution,
                  ),
                  SizedBox(width: topRowLandscape ? 6 : 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: topRowLandscape
                                ? (isTablet ? 11 : 10)
                                : (compact ? 12 : (isTablet ? 14 : 13)),
                            fontWeight: FontWeight.w900,
                            color: palette.textPrimary,
                          ),
                        ),
                        if (!topRowLandscape) ...[
                          const SizedBox(height: 2),
                          Text(
                            body,
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact
                                  ? (isTablet ? 11 : 10)
                                  : (isTablet ? 12 : 11),
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                              color: palette.textPrimary.withOpacity(0.86),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class DriverNoNavInstructionsBanner extends StatelessWidget {
  final bool compact;
  final bool isTablet;
  final bool topRowLandscape;
  final String text;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverNoNavInstructionsBanner({
    super.key,
    required this.compact,
    this.isTablet = false,
    this.topRowLandscape = false,
    this.text = 'Geen route-instructies beschikbaar',
    this.themeListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        return ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: compact ? 8 : 10,
              sigmaY: compact ? 8 : 10,
            ),
            child: Container(
              constraints: BoxConstraints(
                minHeight: topRowLandscape
                    ? (isTablet ? 56 : 52)
                    : (compact ? 52 : (isTablet ? 64 : 56)),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: topRowLandscape ? 8 : (compact ? 12 : 14),
                vertical: topRowLandscape ? 6 : (compact ? 8 : 10),
              ),
              decoration: BoxDecoration(
                color: palette.surfaceAlt.withOpacity(
                  palette.isDark ? 0.84 : 0.95,
                ),
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(color: palette.border.withOpacity(0.55)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: topRowLandscape ? 18 : (compact ? 20 : 22),
                    color: palette.textPrimary.withOpacity(0.82),
                  ),
                  SizedBox(width: topRowLandscape ? 8 : (compact ? 10 : 12)),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: topRowLandscape ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: topRowLandscape
                            ? (isTablet ? 12 : 11)
                            : (compact ? 13 : (isTablet ? 16 : 14)),
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary.withOpacity(0.92),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
