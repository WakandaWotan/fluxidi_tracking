import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

/// The custom chauffeur footer uses one opaque surface for both its background
/// and its inactive labels, including when the company chooses a light colour.
class DriverGoldBottomNavBar extends StatelessWidget {
  const DriverGoldBottomNavBar({
    super.key,
    required this.palette,
    required this.child,
  });

  final DriverThemePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: palette.border),
    ),
    child: child,
  );
}

class DriverGoldBottomNavItem extends StatelessWidget {
  const DriverGoldBottomNavItem({
    super.key,
    required this.palette,
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final DriverThemePalette palette;
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? const Color(0xFF141414)
        : driverReadableTextOn(palette.surface, palette.textPrimary);
    final labelHeight = MediaQuery.textScalerOf(context).scale(10.1) * 2.4;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: active ? const Color(0xFFE8C57E) : palette.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: active ? driverSelectedGoldGradient : null,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 25, height: 25, child: icon),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: labelHeight,
                    child: Center(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 10.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
