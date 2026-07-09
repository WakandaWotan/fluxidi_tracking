import 'package:flutter/material.dart';

import '../driver_navigation_map_config.dart';
import '../presentation/navigation_driver_cockpit_camera.dart';

/// NAV-PRES-2A: screen-fixed driver vehicle HUD (visual foundation only).
///
/// No GPS, route, camera, or Mapbox dependencies. Parent positions this
/// above the bottom cockpit bar inside the navigation [Stack].
class NavigationDriverHudOverlay extends StatelessWidget {
  const NavigationDriverHudOverlay({
    super.key,
    this.iconSize = 56.0,
  });

  /// NAV-PRES-3D-PRO2: responsive HUD vehicle sizing (screen-fixed, no map deps).
  static double resolveIconSize({
    required double screenWidth,
    required bool cockpitBoost,
    int viewLevel = kDriverCockpitViewLevelDefault,
  }) {
    final isTablet = screenWidth >= 600;
    if (!cockpitBoost) {
      return isTablet ? 80.0 : 72.0;
    }
    // NAV-PRES-3M: HUD grows with cockpit view level (deterministic, no GPS scaling).
    return driverCockpitViewLevelHudIconSize(
      isTablet: isTablet,
      level: viewLevel,
    );
  }

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        label: 'Driver navigation vehicle',
        child: Image.asset(
          kDriverTaxiMarkerAssetPath,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _NavigationDriverHudFallback(iconSize: iconSize);
          },
        ),
      ),
    );
  }
}

class _NavigationDriverHudFallback extends StatelessWidget {
  const _NavigationDriverHudFallback({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFD21F).withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          Icons.navigation,
          color: const Color(0xFF0B1326),
          size: iconSize * 0.55,
        ),
      ),
    );
  }
}
