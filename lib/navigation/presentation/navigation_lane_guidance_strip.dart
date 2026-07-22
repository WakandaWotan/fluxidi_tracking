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

  /// Phone portrait / default non-compact.
  static const DriverNavLaneStripMetrics phone = DriverNavLaneStripMetrics(
    rowHeight: 44,
    pillMinWidth: 40,
    arrowFontSize: 24,
    gap: 6,
    compact: false,
  );

  /// Tablet portrait — larger, glanceable at driving distance.
  static const DriverNavLaneStripMetrics tablet = DriverNavLaneStripMetrics(
    rowHeight: 52,
    pillMinWidth: 48,
    arrowFontSize: 28,
    gap: 7,
    compact: false,
  );

  /// Phone landscape top-row — still readable, not tiny mini-icons.
  static const DriverNavLaneStripMetrics phoneLandscape =
      DriverNavLaneStripMetrics(
        rowHeight: 32,
        pillMinWidth: 32,
        arrowFontSize: 18,
        gap: 5,
        compact: true,
      );

  /// Tablet landscape top-row.
  static const DriverNavLaneStripMetrics tabletLandscape =
      DriverNavLaneStripMetrics(
        rowHeight: 38,
        pillMinWidth: 38,
        arrowFontSize: 22,
        gap: 6,
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
          padding: EdgeInsets.only(left: metrics.compact ? 2 : 4),
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

    // Recommended lanes: strong filled accent. Non-recommended: subdued.
    // Do not rely on subtle color alone — border width + fill + weight differ.
    final Color bg;
    final Color borderColor;
    final Color textColor;
    final double borderWidth;
    final FontWeight weight;

    if (isPreferred) {
      bg = accent.withOpacity(palette.isDark ? 0.55 : 0.42);
      borderColor = accent.withOpacity(0.98);
      textColor = palette.isDark ? Colors.white : palette.textPrimary;
      borderWidth = 2.4;
      weight = FontWeight.w900;
    } else if (isUsable) {
      bg = accent.withOpacity(palette.isDark ? 0.22 : 0.16);
      borderColor = accent.withOpacity(palette.isDark ? 0.55 : 0.48);
      textColor = palette.textPrimary.withOpacity(0.88);
      borderWidth = 1.5;
      weight = FontWeight.w700;
    } else if (isUnavailable) {
      bg = palette.textPrimary.withOpacity(palette.isDark ? 0.06 : 0.04);
      borderColor = palette.textPrimary.withOpacity(palette.isDark ? 0.18 : 0.14);
      textColor = palette.textPrimary.withOpacity(0.36);
      borderWidth = 1.0;
      weight = FontWeight.w500;
    } else {
      bg = palette.textPrimary.withOpacity(palette.isDark ? 0.10 : 0.07);
      borderColor = palette.textPrimary.withOpacity(palette.isDark ? 0.28 : 0.20);
      textColor = palette.textPrimary.withOpacity(0.55);
      borderWidth = 1.1;
      weight = FontWeight.w600;
    }

    return Semantics(
      label: semanticLabel,
      child: Container(
        constraints: BoxConstraints(
          minWidth: metrics.pillMinWidth,
          minHeight: metrics.rowHeight - 2,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.compact ? 7 : 9,
          vertical: metrics.compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(metrics.compact ? 8 : 10),
          border: Border.all(color: borderColor, width: borderWidth),
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
