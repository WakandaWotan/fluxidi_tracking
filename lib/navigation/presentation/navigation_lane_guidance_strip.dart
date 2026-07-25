// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 2
//
// Public, testable lane-guidance strip. Accepts ONLY resolved
// `DriverNavLaneGuidance` columns — never secondary maneuver previews,
// upcoming-step chevrons, or invented arrows.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_formatters.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';

/// Combines multiple Mapbox indications for ONE physical lane into a single
/// glyph string (e.g. straight+right → `↑→`). Never splits into two columns.
String driverLaneCombinedArrowGlyph(
  DriverNavLaneGuidance lane, {
  String? maneuverModifier,
}) {
  final indications = lane.indications;
  if (indications.isEmpty) return '·';

  // Prefer the display indication (valid/active/modifier match) first, then
  // append any remaining distinct direction glyphs in Mapbox order.
  final preferred = driverLaneIndicationForDisplay(
    lane,
    maneuverModifier: maneuverModifier,
  );
  final ordered = <String>[];
  if (preferred != null && preferred.trim().isNotEmpty) {
    ordered.add(preferred);
  }
  for (final indication in indications) {
    if (preferred != null &&
        indication.trim().toLowerCase() == preferred.trim().toLowerCase()) {
      continue;
    }
    ordered.add(indication);
  }

  final seen = <String>{};
  final parts = <String>[];
  for (final indication in ordered) {
    final arrow = driverLaneIndicationArrow(indication);
    if (arrow == '·') continue;
    if (seen.add(arrow)) parts.add(arrow);
  }
  if (parts.isEmpty) return '·';
  return parts.join();
}

/// Metrics for a driving-readable lane strip.
class DriverNavLaneStripMetrics {
  const DriverNavLaneStripMetrics({
    required this.rowHeight,
    required this.pillMinWidth,
    required this.arrowFontSize,
    required this.gap,
    required this.compact,
  });

  final double rowHeight;
  final double pillMinWidth;
  final double arrowFontSize;
  final double gap;
  final bool compact;

  /// NAV-LANE-GUIDANCE-RELEASE-ENABLE-AND-READABILITY-1 metric floors.
  ///
  /// Sizes chosen at the low end of each readable range so the lane strip fits
  /// safely under the maneuver banner while remaining glanceable at driving
  /// distance. Never let arrows shrink below these floors — the resolver
  /// already prevents fabricated cells, so the display must not compensate
  /// by inflating count or by shrinking arrows into unreadable dots.

  /// Phone portrait / default non-compact.
  static const DriverNavLaneStripMetrics phone = DriverNavLaneStripMetrics(
    rowHeight: 54,
    pillMinWidth: 48,
    arrowFontSize: 29,
    gap: 8,
    compact: false,
  );

  /// Tablet portrait — larger, glanceable at driving distance.
  static const DriverNavLaneStripMetrics tablet = DriverNavLaneStripMetrics(
    rowHeight: 62,
    pillMinWidth: 56,
    arrowFontSize: 34,
    gap: 9,
    compact: false,
  );

  /// Phone landscape top-row — still readable, not tiny mini-icons.
  static const DriverNavLaneStripMetrics phoneLandscape =
      DriverNavLaneStripMetrics(
        rowHeight: 42,
        pillMinWidth: 38,
        arrowFontSize: 23,
        gap: 6,
        compact: true,
      );

  /// Tablet landscape top-row.
  static const DriverNavLaneStripMetrics tabletLandscape =
      DriverNavLaneStripMetrics(
        rowHeight: 48,
        pillMinWidth: 44,
        arrowFontSize: 27,
        gap: 7,
        compact: true,
      );
}

/// Clearly separated lane row beneath the maneuver content.
///
/// Renders nothing when [lanes] is empty. Preserves Mapbox left-to-right order.
/// One column per physical lane; multiple indications stay in that column.
class DriverNavLaneGuidanceStrip extends StatelessWidget {
  const DriverNavLaneGuidanceStrip({
    super.key,
    required this.lanes,
    required this.palette,
    required this.metrics,
    this.isHighwayLike = false,
    this.maneuverModifier = '',
  });

  final List<DriverNavLaneGuidance> lanes;
  final DriverThemePalette palette;
  final DriverNavLaneStripMetrics metrics;
  final bool isHighwayLike;
  final String maneuverModifier;

  @override
  Widget build(BuildContext context) {
    if (lanes.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Lane guidance',
      child: SizedBox(
        key: const ValueKey<String>('nav_lane_guidance_strip'),
        height: metrics.rowHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: lanes.length > 6
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.only(left: metrics.compact ? 3 : 5),
          itemCount: lanes.length,
          separatorBuilder: (_, __) => SizedBox(width: metrics.gap),
          itemBuilder: (context, index) {
            return _DriverNavLaneColumn(
              key: ValueKey<String>('nav_lane_column_$index'),
              lane: lanes[index],
              palette: palette,
              isHighwayLike: isHighwayLike,
              maneuverModifier: maneuverModifier,
              metrics: metrics,
            );
          },
        ),
      ),
    );
  }
}

class _DriverNavLaneColumn extends StatelessWidget {
  const _DriverNavLaneColumn({
    super.key,
    required this.lane,
    required this.palette,
    required this.isHighwayLike,
    required this.maneuverModifier,
    required this.metrics,
  });

  final DriverNavLaneGuidance lane;
  final DriverThemePalette palette;
  final bool isHighwayLike;
  final String maneuverModifier;
  final DriverNavLaneStripMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final kind = driverLaneDisplayKind(lane);
    final arrow = driverLaneCombinedArrowGlyph(
      lane,
      maneuverModifier: maneuverModifier,
    );
    final semanticLabel = driverLaneSemanticLabel(
      lane,
      maneuverModifier: maneuverModifier,
    );
    final accent = isHighwayLike ? const Color(0xFFFFD36A) : palette.accent;
    final isPreferred = kind == DriverLaneDisplayKind.preferred;
    final isUsable = kind == DriverLaneDisplayKind.usable;
    final isUnavailable = kind == DriverLaneDisplayKind.unavailable;

    // NAV-LANE-GUIDANCE-RELEASE-ENABLE-AND-READABILITY-1:
    //
    // Preferred lanes: strong filled accent, thicker border, subtle outer
    // glow, high-contrast arrow. Never rely on color alone — border weight
    // and fill also differ so preferred lanes remain unmistakable in dark
    // mode and for colorblind drivers.
    //
    // Usable lanes: visible and readable, clearly weaker than preferred.
    // Unavailable lanes: subdued but retain enough arrow contrast that the
    // physical lane layout is still understandable.
    // Unknown lanes: conservative neutral, never look recommended.
    final Color bg;
    final Color borderColor;
    final Color textColor;
    final double borderWidth;
    final FontWeight weight;
    final List<BoxShadow> shadows;

    if (isPreferred) {
      bg = accent.withOpacity(palette.isDark ? 0.66 : 0.52);
      borderColor = accent.withOpacity(0.98);
      textColor = palette.isDark ? Colors.white : palette.textPrimary;
      borderWidth = 3.0;
      weight = FontWeight.w900;
      shadows = <BoxShadow>[
        BoxShadow(
          color: accent.withOpacity(palette.isDark ? 0.55 : 0.42),
          blurRadius: 10,
          spreadRadius: 0.5,
          offset: Offset.zero,
        ),
      ];
    } else if (isUsable) {
      bg = accent.withOpacity(palette.isDark ? 0.24 : 0.18);
      borderColor = accent.withOpacity(palette.isDark ? 0.60 : 0.52);
      textColor = palette.textPrimary.withOpacity(0.94);
      borderWidth = 1.6;
      weight = FontWeight.w700;
      shadows = const <BoxShadow>[];
    } else if (isUnavailable) {
      bg = palette.textPrimary.withOpacity(palette.isDark ? 0.08 : 0.05);
      borderColor = palette.textPrimary.withOpacity(
        palette.isDark ? 0.24 : 0.18,
      );
      textColor = palette.textPrimary.withOpacity(palette.isDark ? 0.52 : 0.48);
      borderWidth = 1.0;
      weight = FontWeight.w500;
      shadows = const <BoxShadow>[];
    } else {
      bg = palette.textPrimary.withOpacity(palette.isDark ? 0.11 : 0.08);
      borderColor = palette.textPrimary.withOpacity(
        palette.isDark ? 0.30 : 0.22,
      );
      textColor = palette.textPrimary.withOpacity(0.62);
      borderWidth = 1.1;
      weight = FontWeight.w600;
      shadows = const <BoxShadow>[];
    }

    return Semantics(
      label: semanticLabel,
      child: Container(
        constraints: BoxConstraints(
          minWidth: metrics.pillMinWidth,
          minHeight: metrics.rowHeight - 2,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.compact ? 8 : 10,
          vertical: metrics.compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(metrics.compact ? 9 : 12),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: shadows,
        ),
        alignment: Alignment.center,
        child: Text(
          arrow,
          style: TextStyle(
            fontSize: metrics.arrowFontSize,
            fontWeight: weight,
            color: textColor,
            height: 1.0,
            letterSpacing: arrow.length > 1 ? -1.0 : 0.0,
          ),
        ),
      ),
    );
  }
}
