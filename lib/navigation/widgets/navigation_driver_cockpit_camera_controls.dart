import 'package:flutter/material.dart';

import 'navigation_driver_cockpit_camera_controls_layout.dart';
import 'navigation_driver_tablet_portrait_nav_layout.dart';

/// NAV-PRES-3C: live +/- cockpit camera intensity controls (field test only).
///
/// No Mapbox/GPS dependencies. Parent gates visibility via presentation state.
class NavigationDriverCockpitCameraControls extends StatelessWidget {
  const NavigationDriverCockpitCameraControls({
    super.key,
    required this.onPlus,
    required this.onMinus,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    this.buttonSize = 40.0,
    this.levelLabel,
    this.debugSubLabel,
    this.compactLandscape = false,
    this.portraitPanelLayout,
  });

  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final double buttonSize;

  /// NAV-PRES-3D-PRO: optional compact view level indicator (`View 7/13`).
  final String? levelLabel;

  /// NAV-PRES-3D-PRO2: field-test debug line (`Z21.6 P84 A0.82`).
  final String? debugSubLabel;

  /// NAV-PRES-3E-FIX1: tighter label/debug typography in landscape.
  final bool compactLandscape;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: portrait tablet panel typography/padding.
  final DriverCockpitViewPanelPortraitLayout? portraitPanelLayout;

  /// NAV-PRES-3E-FIX1: panel size estimate for safe viewport clamping.
  Size get estimatedPanelSize => estimateDriverCockpitCameraControlsPanelSize(
    buttonSize: buttonSize,
    hasLevelLabel: levelLabel != null,
    hasDebugSubLabel: debugSubLabel != null,
    compactLandscape: compactLandscape,
    panelWidthExtra: portraitPanelLayout?.panelWidthExtra ?? 0,
    panelHorizontalPadding: portraitPanelLayout?.panelHorizontalPadding ?? 4,
    levelLabelFontSize: portraitPanelLayout?.levelLabelFontSize,
    debugLabelFontSize: portraitPanelLayout?.debugLabelFontSize,
  );

  @override
  Widget build(BuildContext context) {
    final levelFontSize =
        portraitPanelLayout?.levelLabelFontSize ??
        (compactLandscape ? 9.0 : 10.0);
    final debugFontSize =
        portraitPanelLayout?.debugLabelFontSize ??
        (compactLandscape ? 7.0 : 8.0);
    final debugOpacity = portraitPanelLayout?.debugLabelOpacity ?? 0.65;
    final horizontalPad = portraitPanelLayout?.panelHorizontalPadding ?? 4;
    return Material(
      color: surfaceColor.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.72)),
        ),
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: horizontalPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CockpitCameraControlButton(
              icon: Icons.add,
              tooltip: 'Closer driver perspective',
              onPressed: onPlus,
              accentColor: accentColor,
              textColor: textColor,
              surfaceColor: surfaceColor,
              size: buttonSize,
            ),
            if (levelLabel != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      levelLabel!,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.85),
                        fontSize: levelFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (debugSubLabel != null)
                      Text(
                        debugSubLabel!,
                        style: TextStyle(
                          color: textColor.withValues(alpha: debugOpacity),
                          fontSize: debugFontSize,
                          fontWeight: FontWeight.w500,
                          height: 1.05,
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 4),
            _CockpitCameraControlButton(
              icon: Icons.remove,
              tooltip: 'Wider driver perspective',
              onPressed: onMinus,
              accentColor: accentColor,
              textColor: textColor,
              surfaceColor: surfaceColor,
              size: buttonSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _CockpitCameraControlButton extends StatelessWidget {
  const _CockpitCameraControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.accentColor,
    required this.textColor,
    required this.surfaceColor,
    required this.size,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.72),
                width: 1.1,
              ),
            ),
            child: Icon(icon, size: 20, color: textColor),
          ),
        ),
      ),
    );
  }
}
