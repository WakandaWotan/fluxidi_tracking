// NAV-PRESTART-FIELD-BLOCKER-3 (Problem C + Problem D)
//
// Pre-start-only camera-presentation preset chip.
//
// The active-ride cockpit already has a view-mode cycle chip in the secondary
// row, but it is gated on `inFollowNav` (only reachable after START). Before
// this widget existed the pre-start driver had no way to switch between
// overview and street-level, so the map surface stayed on overview / bounds-fit
// even after the driver picked a destination.
//
// This chip is a small, self-contained toggle:
//   * Overview  -> cube outlined icon (route framed inside the viewport);
//   * Streetlevel -> filled cube (driver cockpit view, low above KPI panel).
// It mirrors the older tablet build's dedicated camera-presentation icon and
// stays visually distinct from the map-style icon (sun / moon / apartment
// buildings / satellite) so no two controls carry the same glyph.

import 'package:flutter/material.dart';

import '../nav_engine/nav_prestart_presentation.dart';

typedef PreviewPresentationModeChanged =
    void Function(NavPreviewPresentationMode next);

/// Compact preview-only chip exposing the overview <-> streetlevel toggle.
class NavigationDriverPreStartPresentationChip extends StatelessWidget {
  const NavigationDriverPreStartPresentationChip({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    required this.tooltipOverview,
    required this.tooltipStreetlevel,
    this.buttonSize = 44,
    this.iconSize = 22,
  });

  final NavPreviewPresentationMode mode;
  final PreviewPresentationModeChanged onModeChanged;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final String tooltipOverview;
  final String tooltipStreetlevel;
  final double buttonSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isStreetLevel = mode == NavPreviewPresentationMode.streetLevel;
    final icon = isStreetLevel
        ? Icons.view_in_ar
        : Icons.view_in_ar_outlined;
    final tooltip = isStreetLevel ? tooltipStreetlevel : tooltipOverview;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        toggled: isStreetLevel,
        child: Material(
          color: surfaceColor.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          elevation: 2,
          child: InkWell(
            onTap: () => onModeChanged(
              isStreetLevel
                  ? NavPreviewPresentationMode.overview
                  : NavPreviewPresentationMode.streetLevel,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: isStreetLevel
                    ? Color.alphaBlend(
                        accentColor.withValues(alpha: 0.22),
                        surfaceColor.withValues(alpha: 0.94),
                      )
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isStreetLevel
                      ? accentColor
                      : accentColor.withValues(alpha: 0.72),
                  width: isStreetLevel ? 2 : 1.1,
                ),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: isStreetLevel ? accentColor : textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
