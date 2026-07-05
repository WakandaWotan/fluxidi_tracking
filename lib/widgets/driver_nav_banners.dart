import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

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
              constraints: BoxConstraints(minHeight: _minBannerHeight),
              padding: EdgeInsets.symmetric(
                horizontal: _useLandscapeTopRow
                    ? 6
                    : (_useLandscapeCompactRow
                          ? 8
                          : (compact ? 10 : (_usePhonePortraitStack ? 12 : 14))),
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
              child: Row(
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
        border: Border.all(
          color: palette.textPrimary.withOpacity(0.20),
        ),
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

  Widget _buildPrimaryText(
    DriverThemePalette palette, {
    int? maxLines,
  }) {
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

  Widget _buildLandscapeTopRowTextBlock({
    required DriverThemePalette palette,
  }) {
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
    final showLandscapeSecondary =
        showSecondary && secondaryLine.length <= 24;
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
