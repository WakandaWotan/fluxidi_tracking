import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_lane_guidance_strip.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_tablet_portrait_nav_layout.dart';

class DriverTurnInstructionBanner extends StatelessWidget {
  final bool compact;
  final bool isTablet;
  final bool topRowLandscape;
  final bool _rawIsArrival;
  final bool _rawIsHighwayLike;
  final String _rawDistancePrefix;
  final String _rawDistanceText;
  final String _rawPrimaryText;
  final String _rawSecondaryText;
  final String? subText;
  final IconData _rawIcon;
  final List<DriverNavLaneGuidance> lanes;
  final String _rawManeuverModifier;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  /// NAV-RESPONSIVE-MANEUVER-BANNER-V1: normalized presentation model.
  ///
  /// When non-null, all string/icon/booleans below are derived from the model
  /// and secondary suppression rules relax so roundabout exit lines stay
  /// visible in landscape.
  final ResponsiveManeuverPresentation? presentation;

  const DriverTurnInstructionBanner({
    super.key,
    required this.compact,
    required this.isTablet,
    this.topRowLandscape = false,
    required bool isArrival,
    required bool isHighwayLike,
    required String distancePrefix,
    required String distanceText,
    required String primaryText,
    required String secondaryText,
    this.subText,
    required IconData icon,
    this.lanes = const <DriverNavLaneGuidance>[],
    String maneuverModifier = '',
    this.themeListenable,
    this.portraitTabletMetrics,
    this.presentation,
  }) : _rawIsArrival = isArrival,
       _rawIsHighwayLike = isHighwayLike,
       _rawDistancePrefix = distancePrefix,
       _rawDistanceText = distanceText,
       _rawPrimaryText = primaryText,
       _rawSecondaryText = secondaryText,
       _rawIcon = icon,
       _rawManeuverModifier = maneuverModifier;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: optional tablet portrait banner metrics.
  final DriverNavBannerPortraitTabletLayout? portraitTabletMetrics;

  bool get isArrival => presentation?.isArrival ?? _rawIsArrival;
  bool get isHighwayLike => presentation?.isHighwayLike ?? _rawIsHighwayLike;
  String get distancePrefix => presentation != null ? '' : _rawDistancePrefix;
  String get distanceText => presentation?.distanceLabel ?? _rawDistanceText;
  String get primaryText => presentation?.primaryInstruction ?? _rawPrimaryText;
  String get secondaryText =>
      presentation?.secondaryInstruction ?? _rawSecondaryText;
  IconData get icon => presentation != null
      ? driverManeuverVisualIconData(presentation!.maneuverVisual)
      : _rawIcon;
  String get maneuverModifier => _rawManeuverModifier;

  /// True when the distance chip should be visible.
  bool get _hasDistanceChip => distanceText.trim().isNotEmpty;

  bool get _usePhonePortraitStack => !compact && !isTablet;

  bool get _useLandscapeTopRow => compact && topRowLandscape;

  bool get _useLandscapeCompactRow => compact && !topRowLandscape;

  bool get _usePortraitTabletPolish =>
      portraitTabletMetrics != null &&
      !compact &&
      isTablet &&
      !_useLandscapeTopRow &&
      !_useLandscapeCompactRow &&
      !_usePhonePortraitStack;

  // NAV-PARKING-2 Commit 3: larger, driving-readable maneuver icon. Height stays
  // content-adaptive (soft floor + tight padding), so the bigger glyph improves
  // legibility without restoring an oversized fixed band.
  double get _iconBoxSize {
    if (_usePortraitTabletPolish) return portraitTabletMetrics!.iconBoxSize;
    if (_useLandscapeTopRow) return isTablet ? 38 : 34;
    if (_useLandscapeCompactRow) return isTablet ? 48 : 44;
    if (compact) return isTablet ? 54 : 48;
    if (_usePhonePortraitStack) return 52;
    return isTablet ? 68 : 60;
  }

  double get _iconSize {
    if (_usePortraitTabletPolish) return portraitTabletMetrics!.iconSize;
    if (_useLandscapeTopRow) return isTablet ? 22 : 20;
    if (_useLandscapeCompactRow) return isTablet ? 27 : 24;
    if (compact) return isTablet ? 33 : 29;
    if (_usePhonePortraitStack) return 31;
    return isTablet ? 42 : 36;
  }

  double get _distanceFontSize {
    if (_useLandscapeTopRow) return isTablet ? 13 : 12;
    if (_useLandscapeCompactRow) return isTablet ? 14 : 13;
    if (compact) return isTablet ? 15 : 14;
    if (_usePhonePortraitStack) return 16;
    return isTablet ? 19 : 17;
  }

  // NAV-PARKING-2 Commit 3: primary maneuver text enlarged for daylight-driving
  // readability. Two-line ceiling + ellipsis keep it overflow-safe.
  double get _primaryFontSize {
    if (_useLandscapeTopRow) return isTablet ? 15 : 14;
    if (_useLandscapeCompactRow) return isTablet ? 17 : 16;
    if (compact) return isTablet ? 19 : 18;
    if (_usePhonePortraitStack) return 20;
    return isTablet ? 25 : 22;
  }

  double get _secondaryFontSize {
    if (_useLandscapeCompactRow) return isTablet ? 12 : 11;
    if (compact) return isTablet ? 14 : 13;
    if (_usePhonePortraitStack) return 14;
    return isTablet ? 18 : 16;
  }

  /// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1:
  /// Principal instruction/road block is at most two text lines total.
  /// Primary takes one line when a secondary/subtitle is present; otherwise
  /// it may wrap to two. Never shrink font to fit.
  int get _primaryMaxLines {
    final secondary = _secondaryLine();
    if (_shouldShowSecondaryLine(secondary)) return 1;
    return 2;
  }

  int get _secondaryMaxLines => 1;

  double get _horizontalPadding {
    if (_useLandscapeTopRow) return 6;
    if (_useLandscapeCompactRow) return 8;
    if (compact) return 10;
    if (_usePhonePortraitStack) return 12;
    if (_usePortraitTabletPolish) {
      return portraitTabletMetrics!.horizontalPadding;
    }
    return 12;
  }

  double get _verticalPadding {
    if (_useLandscapeTopRow) return 4;
    if (_useLandscapeCompactRow) return 5;
    if (compact) return 6;
    if (_usePhonePortraitStack) return 6;
    if (_usePortraitTabletPolish) {
      return portraitTabletMetrics!.verticalPadding;
    }
    return 7;
  }

  /// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1:
  /// No fixed oversized band. Height hugs icon + text (+ optional lane row).
  /// Kept only as a tiny touch-target floor for landscape top-row chrome.
  double get _minBannerHeight {
    if (_useLandscapeTopRow) return isTablet ? 40 : 36;
    return 0;
  }

  List<DriverNavLaneGuidance> get _displayLanes =>
      driverNavLanesForBannerDisplay(lanes);

  bool get _showLaneGuidance => _displayLanes.isNotEmpty;

  /// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 2:
  /// Driving-readable lane strip metrics. Tiny mini-icons are gone.
  DriverNavLaneStripMetrics get _laneStripMetrics {
    if (_useLandscapeTopRow) {
      return isTablet
          ? DriverNavLaneStripMetrics.tabletLandscape
          : DriverNavLaneStripMetrics.phoneLandscape;
    }
    if (compact || _useLandscapeCompactRow) {
      // NAV-LANE-GUIDANCE-RELEASE-ENABLE-AND-READABILITY-1: unify the
      // in-banner compact rows with the landscape floors so the compact
      // path can never render smaller arrows than the readable minimum.
      return isTablet
          ? DriverNavLaneStripMetrics.tabletLandscape
          : DriverNavLaneStripMetrics.phoneLandscape;
    }
    return isTablet
        ? DriverNavLaneStripMetrics.tablet
        : DriverNavLaneStripMetrics.phone;
  }

  double get _laneRowHeight => _laneStripMetrics.rowHeight;

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

        final banner = ClipRRect(
          key: const ValueKey<String>('nav_maneuver_banner'),
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
              // NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1:
              // Soft floor only. Height follows content; missing subtitle /
              // lanes consume zero extra space (no fixed oversized band).
              constraints: BoxConstraints(
                minHeight:
                    _minBannerHeight +
                    (showLaneGuidance ? (_laneRowHeight + 4) : 0),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: _horizontalPadding,
                vertical: _verticalPadding,
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
                            ? _buildLandscapeTopRowTextBlock(
                                palette: palette,
                                secondaryLine: secondaryLine,
                                showSecondary: showSecondary,
                              )
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
                    // Clearly separated row — never tiny icons inside the
                    // maneuver text. Absent when lane data is empty/gated.
                    SizedBox(height: _useLandscapeTopRow ? 4 : 6),
                    DriverNavLaneGuidanceStrip(
                      lanes: displayLanes,
                      palette: palette,
                      metrics: _laneStripMetrics,
                      isHighwayLike: isHighwayLike,
                      maneuverModifier: maneuverModifier,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
        // NAV-RESPONSIVE-MANEUVER-BANNER-V1: single announcement per banner
        // update ("Over 400 meter de rotonde op. Neem de tweede afslag."), so
        // TalkBack reads a complete instruction instead of each Text child.
        final acc = presentation?.accessibilityLabel.trim() ?? '';
        if (acc.isEmpty) return banner;
        return Semantics(
          container: true,
          label: acc,
          excludeSemantics: true,
          child: banner,
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
    final label = distancePrefix.trim().isEmpty
        ? distanceText
        : '$distancePrefix $distanceText';
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
        label,
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
    // NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1:
    // Principal block ≤ 2 lines. Missing subtitle collapses (zero height).
    if (presentation != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasDistanceChip && !isArrival) ...[
            _buildDistanceChip(palette),
            const SizedBox(height: 3),
          ],
          _buildPrimaryText(
            palette,
            maxLines: showSecondary ? 1 : 2,
          ),
          if (showSecondary) ...[
            const SizedBox(height: 2),
            _buildSecondaryText(palette, secondaryLine, maxLines: 1),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isArrival) _buildDistanceChip(palette),
        if (isArrival) _buildPrimaryText(palette, maxLines: 2),
        if (!isArrival) ...[
          const SizedBox(height: 3),
          _buildPrimaryText(
            palette,
            maxLines: showSecondary ? 1 : 2,
          ),
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
    required String secondaryLine,
    required bool showSecondary,
  }) {
    if (isArrival) {
      return _buildPrimaryText(palette, maxLines: 1);
    }
    // NAV-RESPONSIVE-MANEUVER-BANNER-V1: presentation-driven landscape
    // renders a 2-line compact banner so roundabout exit context and road ref
    // remain visible. Legacy path preserves the single-line inline row.
    if (presentation != null) {
      final primaryRow = Row(
        children: [
          if (_hasDistanceChip) ...[
            _buildDistanceChip(palette),
            const SizedBox(width: 6),
          ],
          Expanded(child: _buildPrimaryText(palette, maxLines: 1)),
        ],
      );
      if (!showSecondary) return primaryRow;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          primaryRow,
          const SizedBox(height: 2),
          _buildSecondaryText(palette, secondaryLine, maxLines: 1),
        ],
      );
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
        showSecondary && (presentation != null || secondaryLine.length <= 24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isArrival)
          Row(
            children: [
              if (_hasDistanceChip) ...[
                _buildDistanceChip(palette),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _buildPrimaryText(
                  palette,
                  maxLines: showLandscapeSecondary ? 1 : 2,
                ),
              ),
            ],
          )
        else
          _buildPrimaryText(palette, maxLines: 2),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isArrival)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasDistanceChip) ...[
                _buildDistanceChip(palette),
                SizedBox(width: compact ? 8 : 10),
              ],
              Expanded(
                child: _buildPrimaryText(
                  palette,
                  maxLines: showSecondary ? 1 : 2,
                ),
              ),
            ],
          )
        else
          _buildPrimaryText(palette, maxLines: 2),
        if (showSecondary) ...[
          SizedBox(height: compact ? 2 : 3),
          _buildSecondaryText(palette, secondaryLine, maxLines: 1),
        ],
      ],
    );
  }

  bool _shouldShowSecondaryLine(String secondaryLine) {
    if (secondaryLine.isEmpty) return false;
    // NAV-RESPONSIVE-MANEUVER-BANNER-V1: normalized presentation controls
    // wording length upstream (roundabout exit, "naar N454", etc.). Keep the
    // line visible in every layout, including landscape, so critical
    // WHERE-context is never dropped.
    if (presentation != null) return true;
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

/// NAV-DIRECTIONS-FAILURE-SECURITY-AND-RECOVERY-1: compact, sanitized
/// connectivity/retry banner shown when an initial route request failed and no
/// valid route exists. It NEVER contains a raw exception, token, URI or
/// coordinates — only localized copy + a manual Retry action. It deliberately
/// replaces the generic "Follow the route" banner in the no-route failure state.
class DriverNavRouteUnavailableBanner extends StatelessWidget {
  final bool compact;
  final bool isTablet;
  final bool topRowLandscape;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverNavRouteUnavailableBanner({
    super.key,
    required this.compact,
    this.isTablet = false,
    this.topRowLandscape = false,
    required this.message,
    required this.retryLabel,
    this.onRetry,
    this.themeListenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriverThemeVariant>(
      valueListenable: themeListenable ?? driverThemeNotifier,
      builder: (context, variant, _) {
        final palette = paletteForDriverTheme(variant);
        const warn = Color(0xFFFFB020);
        return ClipRRect(
          key: const ValueKey<String>('nav_route_unavailable_banner'),
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
                color: palette.surface.withOpacity(
                  palette.isDark ? 0.92 : 0.96,
                ),
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(
                  color: warn.withOpacity(palette.isDark ? 0.85 : 0.95),
                  width: 1.4,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: topRowLandscape ? 18 : (compact ? 20 : 22),
                    color: warn,
                  ),
                  SizedBox(width: topRowLandscape ? 8 : (compact ? 10 : 12)),
                  Expanded(
                    child: Text(
                      message,
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
                  if (onRetry != null) ...[
                    SizedBox(width: topRowLandscape ? 6 : 8),
                    _RetryChip(
                      label: retryLabel,
                      palette: palette,
                      compact: compact || topRowLandscape,
                      onTap: onRetry!,
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
}

class _RetryChip extends StatelessWidget {
  const _RetryChip({
    required this.label,
    required this.palette,
    required this.compact,
    required this.onTap,
  });
  final String label;
  final DriverThemePalette palette;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            color: palette.accent.withOpacity(0.24),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.textPrimary.withOpacity(0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh_rounded,
                size: compact ? 15 : 17,
                color: palette.textPrimary.withOpacity(0.95),
              ),
              SizedBox(width: compact ? 5 : 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w900,
                  color: palette.textPrimary.withOpacity(0.98),
                ),
              ),
            ],
          ),
        ),
      ),
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
