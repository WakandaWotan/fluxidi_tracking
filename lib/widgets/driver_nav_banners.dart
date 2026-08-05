import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/maneuver_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_maneuver_sign.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_signage_tablet_readability.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_lane_guidance_strip.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_tablet_portrait_nav_layout.dart';

/// NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1: content-aware width contract
/// for the driver navigation banners.
///
/// The maneuver card used to have no width contract at all — it simply took
/// whatever horizontal constraint its parent handed down. A two-word
/// instruction such as "Over 643 m linksaf" / "naar N454" therefore still
/// painted a near-full-width dark bar across the top of the map, which on a
/// tablet hides considerably more road than the instruction is worth.
///
/// The card now hugs its content and may grow only up to a form-factor
/// maximum. Landscape is deliberately the tightest: map height is scarcest
/// there, so a wide banner costs the driver the most.
class DriverNavBannerWidthPolicy {
  const DriverNavBannerWidthPolicy._();

  /// Fraction of the viewport width the card may never exceed.
  static const double phonePortraitFraction = 0.92;
  static const double phoneLandscapeFraction = 0.72;
  static const double tabletPortraitFraction = 0.76;
  static const double tabletLandscapeFraction = 0.58;

  /// Absolute ceilings so a very wide display never scales the card forever.
  /// These match the caps the driver page already applied in portrait, so no
  /// form factor becomes wider than before.
  static const double phoneAbsoluteMax = 700;
  static const double tabletAbsoluteMax = 820;

  /// Floors that keep the maneuver icon plus a useful amount of instruction
  /// text on the row. Always clamped to the maximum, so a narrow viewport can
  /// never produce an impossible `minWidth > maxWidth`.
  static const double phoneMinWidth = 208;
  static const double tabletMinWidth = 248;

  static double fractionFor({
    required bool isTablet,
    required bool isLandscape,
  }) {
    if (isTablet) {
      return isLandscape ? tabletLandscapeFraction : tabletPortraitFraction;
    }
    return isLandscape ? phoneLandscapeFraction : phonePortraitFraction;
  }

  static double minWidthFor({required bool isTablet}) =>
      isTablet ? tabletMinWidth : phoneMinWidth;

  /// Largest width the card may occupy. Degrades to the absolute ceiling when
  /// the viewport width is unknown (zero, infinite or NaN), so a host without
  /// a sane MediaQuery still gets a bounded banner instead of a full-bleed
  /// bar.
  static double maxWidthFor({
    required double viewportWidth,
    required bool isTablet,
    required bool isLandscape,
  }) {
    final absolute = isTablet ? tabletAbsoluteMax : phoneAbsoluteMax;
    if (!viewportWidth.isFinite || viewportWidth <= 0) return absolute;
    final fraction = fractionFor(isTablet: isTablet, isLandscape: isLandscape);
    return math.min(viewportWidth * fraction, absolute);
  }

  static BoxConstraints constraintsFor({
    required double viewportWidth,
    required bool isTablet,
    required bool isLandscape,
  }) {
    final maxWidth = maxWidthFor(
      viewportWidth: viewportWidth,
      isTablet: isTablet,
      isLandscape: isLandscape,
    );
    return BoxConstraints(
      minWidth: math.min(minWidthFor(isTablet: isTablet), maxWidth),
      maxWidth: maxWidth,
    );
  }
}

/// NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1: applies the width contract to a
/// finished banner card.
///
/// [Align] absorbs a tight parent constraint — the landscape top row hands the
/// banner an `Expanded`, and the complexity-caution wrapper uses
/// `CrossAxisAlignment.stretch` — and hands the card a loose one so it can
/// shrink to its content. `ConstrainedBox` then also clamps the cap down to
/// whatever the parent actually allows, because `BoxConstraints.enforce`
/// intersects with the incoming constraints; the card can therefore never
/// overflow its parent even on an unexpectedly narrow viewport.
Widget _constrainNavBannerWidth({
  required BuildContext context,
  required bool compact,
  required bool isTablet,
  required Widget child,
  NavSignageTabletReadabilityMetrics? tabletReadability,
}) {
  final media = MediaQuery.maybeOf(context);
  // `compact` is only ever set by the landscape collapsed top row, so it stays
  // a reliable landscape signal even for a host that supplies no MediaQuery.
  final isLandscape = compact || media?.orientation == Orientation.landscape;
  final BoxConstraints constraints;
  if (tabletReadability != null) {
    // NAV-SIGNAGE-TABLET-READABILITY-1: hug content inside the tablet
    // readability width band (clamped by LayoutBuilder upstream).
    constraints = BoxConstraints(
      minWidth: tabletReadability.bannerMinWidth,
      maxWidth: tabletReadability.bannerMaxWidth,
    );
  } else {
    constraints = DriverNavBannerWidthPolicy.constraintsFor(
      viewportWidth: media?.size.width ?? 0,
      isTablet: isTablet,
      isLandscape: isLandscape,
    );
  }
  return Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: constraints,
      child: child,
    ),
  );
}

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
    this.tabletReadability,
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

  /// NAV-SIGNAGE-TABLET-READABILITY-1: larger tablet driving metrics. When set,
  /// these override icon/text/height floors for both tablet portrait (inline
  /// top row) and tablet landscape. Phones never pass this.
  final NavSignageTabletReadabilityMetrics? tabletReadability;

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
    if (tabletReadability != null) return tabletReadability!.iconBoxSize;
    if (_usePortraitTabletPolish) return portraitTabletMetrics!.iconBoxSize;
    if (_useLandscapeTopRow) return isTablet ? 38 : 34;
    if (_useLandscapeCompactRow) return isTablet ? 48 : 44;
    if (compact) return isTablet ? 54 : 48;
    if (_usePhonePortraitStack) return 52;
    return isTablet ? 68 : 60;
  }

  double get _iconSize {
    if (tabletReadability != null) {
      // Legacy Material icon path only; PNG signs use [tabletReadability.signSize].
      return tabletReadability!.signSize;
    }
    if (_usePortraitTabletPolish) return portraitTabletMetrics!.iconSize;
    if (_useLandscapeTopRow) return isTablet ? 22 : 20;
    if (_useLandscapeCompactRow) return isTablet ? 27 : 24;
    if (compact) return isTablet ? 33 : 29;
    if (_usePhonePortraitStack) return 31;
    return isTablet ? 42 : 36;
  }

  double get _distanceFontSize {
    if (tabletReadability != null) return tabletReadability!.distanceFontSize;
    if (_useLandscapeTopRow) return isTablet ? 13 : 12;
    if (_useLandscapeCompactRow) return isTablet ? 14 : 13;
    if (compact) return isTablet ? 15 : 14;
    if (_usePhonePortraitStack) return 16;
    return isTablet ? 19 : 17;
  }

  // NAV-PARKING-2 Commit 3: primary maneuver text enlarged for daylight-driving
  // readability. Two-line ceiling + ellipsis keep it overflow-safe.
  double get _primaryFontSize {
    if (tabletReadability != null) return tabletReadability!.primaryFontSize;
    if (_useLandscapeTopRow) return isTablet ? 15 : 14;
    if (_useLandscapeCompactRow) return isTablet ? 17 : 16;
    if (compact) return isTablet ? 19 : 18;
    if (_usePhonePortraitStack) return 20;
    return isTablet ? 25 : 22;
  }

  double get _secondaryFontSize {
    if (tabletReadability != null) return tabletReadability!.secondaryFontSize;
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
    if (tabletReadability != null) {
      return tabletReadability!.horizontalPadding;
    }
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
    if (tabletReadability != null) {
      return tabletReadability!.verticalPadding;
    }
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
    if (tabletReadability != null) return tabletReadability!.bannerMinHeight;
    if (_useLandscapeTopRow) return isTablet ? 40 : 36;
    return 0;
  }

  double get _signPlateInsetResolved =>
      tabletReadability?.signPlateInset ?? _signPlateInset;

  double get _signPaintSize =>
      tabletReadability?.signSize ??
      (_iconBoxSize - (_signPlateInsetResolved * 2));

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
                // NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1: a touch less
                // opaque in dark mode so the card reads as a panel over the
                // map rather than a solid wall. Text/border contrast is
                // unchanged; light mode stays at 0.96.
                color: palette.surface.withOpacity(
                  palette.isDark ? 0.88 : 0.96,
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
                // NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1: `start` instead
                // of `stretch`. Stretch forced the column — and therefore the
                // whole card — to the full incoming width even for a two-word
                // instruction. The lane strip still fills the card because a
                // horizontal ListView takes its bounded maximum, so lanes may
                // widen the card up to the form-factor cap, never past it.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                      // Loose `Flexible` rather than tight `Expanded`: the
                      // text block still receives exactly the same maxWidth,
                      // so wrapping, ellipsis and height are unchanged, but a
                      // short instruction no longer stretches the card.
                      Flexible(
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
        final labelled = acc.isEmpty
            ? banner
            : Semantics(
                container: true,
                label: acc,
                excludeSemantics: true,
                child: banner,
              );
        // NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1: constrain outside the
        // Semantics node so the announced region still hugs the visible card.
        return _constrainNavBannerWidth(
          context: context,
          compact: compact,
          isTablet: isTablet,
          tabletReadability: tabletReadability,
          child: labelled,
        );
      },
    );
  }

  // NAV-SIGNAGE-VISUAL-RELEASE-GATE: the sign plates are drawn as a gold arrow
  // over a light plate, so they need a light surface. Painting one on the gold
  // accent would hide the arrow entirely. The box keeps its size and radius so
  // banner layout is unchanged; only the fill differs.
  static const Color _signPlateSurface = Color(0xFFFFFFFF);

  double get _signPlateInset => compact ? 2 : 3;

  Widget _buildManeuverIcon(DriverThemePalette palette) {
    final presentation = this.presentation;
    final radius = BorderRadius.circular(
      tabletReadability != null ? 16 : (compact ? 12 : 14),
    );
    if (presentation != null) {
      final inset = _signPlateInsetResolved;
      return Container(
        width: _iconBoxSize,
        height: _iconBoxSize,
        padding: EdgeInsets.all(inset),
        decoration: BoxDecoration(
          color: _signPlateSurface,
          borderRadius: radius,
          // The highway cue moves to the border now that the fill is fixed.
          border: Border.all(
            color: isHighwayLike
                ? const Color(0xFFFFD36A)
                : palette.textPrimary.withOpacity(0.80),
            width: isHighwayLike ? 2.0 : 1.4,
          ),
        ),
        alignment: Alignment.center,
        // NAV-SIGNAGE-TABLET-READABILITY-1: enlarge the loaded plate itself,
        // not only the outer container.
        child: NavManeuverSign(
          maneuver: presentation.signManeuver,
          languageCode: presentation.signLanguageCode,
          size: _signPaintSize,
        ),
      );
    }
    // Legacy callers that pass a raw IconData without a presentation model.
    final iconGlyphColor = palette.isDark ? Colors.black : Colors.white;
    return Container(
      width: _iconBoxSize,
      height: _iconBoxSize,
      decoration: BoxDecoration(
        color: isHighwayLike ? const Color(0xFFFFD36A) : palette.accent,
        borderRadius: radius,
        border: Border.all(
          color: palette.textPrimary.withOpacity(0.80),
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: _iconSize, color: iconGlyphColor),
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
      // NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31: the distance chip must
      // NEVER truncate. Distance labels are always short (e.g. "400 m",
      // "1.2 km", "In 400 m") so `TextOverflow.visible` + `softWrap: false`
      // preserves the whole label and lets the chip grow to its natural
      // intrinsic width. On the extreme edge of a narrow phone we fall
      // back to visible overflow rather than an ellipsis, so the driver
      // always sees the full distance.
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: _distanceFontSize,
          fontWeight: FontWeight.w900,
          color: palette.textPrimary.withOpacity(0.98),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // NAV-SIGNAGE-FIELD-QUALITY-P0-1: the external primary line is the only
  // textual instruction (sign plates are captionless). Never ellipsize the
  // main maneuver — including arrival ("Bestemming bereikt") and ordinary
  // turns. Only the secondary street/destination line may truncate.
  bool get _isRoundaboutPrimary =>
      presentation != null &&
      presentation!.maneuverVisual == ManeuverVisual.roundabout;

  Widget _buildPrimaryText(DriverThemePalette palette, {int? maxLines}) {
    final base = maxLines ?? _primaryMaxLines;
    final resolvedMaxLines = (isArrival || _isRoundaboutPrimary)
        ? math.max(2, base)
        : base;
    return Text(
      primaryText,
      maxLines: resolvedMaxLines,
      softWrap: true,
      overflow: TextOverflow.visible,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasDistanceChip) ...[
            _buildDistanceChip(palette),
            const SizedBox(width: 6),
          ],
          Flexible(child: _buildPrimaryText(palette, maxLines: 1)),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDistanceChip(palette),
        const SizedBox(width: 6),
        Flexible(child: _buildPrimaryText(palette, maxLines: 1)),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasDistanceChip) ...[
                _buildDistanceChip(palette),
                const SizedBox(width: 8),
              ],
              Flexible(
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasDistanceChip) ...[
                _buildDistanceChip(palette),
                SizedBox(width: compact ? 8 : 10),
              ],
              Flexible(
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
        final card = ClipRRect(
          key: const ValueKey<String>('nav_complexity_caution_banner'),
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: topRowLandscape ? 18 : (compact ? 20 : 22),
                    color: caution,
                  ),
                  SizedBox(width: topRowLandscape ? 6 : 8),
                  Flexible(
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
        // NAV-MANEUVER-BANNER-COMPACT-WIDTH-POLISH-1: the caution sits directly
        // under the maneuver card in a stretching Column, so it obeys the same
        // width contract — otherwise a compact maneuver card would sit above a
        // full-width caution bar.
        return _constrainNavBannerWidth(
          context: context,
          compact: compact,
          isTablet: isTablet,
          child: card,
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
