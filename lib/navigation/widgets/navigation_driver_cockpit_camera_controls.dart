import 'package:flutter/material.dart';

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
  });

  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final Color accentColor;
  final Color textColor;
  final Color surfaceColor;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceColor.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.72)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CockpitCameraControlButton(
              icon: Icons.add,
              tooltip: 'Closer cockpit camera',
              onPressed: onPlus,
              accentColor: accentColor,
              textColor: textColor,
              surfaceColor: surfaceColor,
              size: buttonSize,
            ),
            const SizedBox(height: 4),
            _CockpitCameraControlButton(
              icon: Icons.remove,
              tooltip: 'Wider cockpit camera',
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
