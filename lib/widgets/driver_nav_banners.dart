import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';

class DriverTurnInstructionBanner extends StatelessWidget {
  final bool compact;
  final bool isArrival;
  final String distanceText;
  final String line1;
  final String street;
  final IconData icon;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverTurnInstructionBanner({
    super.key,
    required this.compact,
    required this.isArrival,
    required this.distanceText,
    required this.line1,
    required this.street,
    required this.icon,
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
              sigmaX: compact ? 7 : 9,
              sigmaY: compact ? 7 : 9,
            ),
            child: Container(
              constraints: BoxConstraints(maxHeight: compact ? 58 : 64),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 4 : 5,
              ),
              decoration: BoxDecoration(
                color: palette.surface.withOpacity(
                  palette.isDark ? 0.88 : 0.95,
                ),
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(
                  color: palette.border.withOpacity(
                    palette.isDark ? 0.68 : 0.9,
                  ),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withOpacity(
                      palette.isDark ? 0.6 : 0.35,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 34 : 38,
                    height: compact ? 34 : 38,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(compact ? 10 : 12),
                      border: Border.all(
                        color: palette.textPrimary.withOpacity(0.80),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: compact ? 22 : 24,
                      color: palette.isDark ? Colors.black : Colors.white,
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  if (!isArrival)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 7,
                        vertical: compact ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accent.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: palette.textPrimary.withOpacity(0.18),
                        ),
                      ),
                      child: Text(
                        distanceText,
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary.withOpacity(0.96),
                        ),
                      ),
                    ),
                  if (!isArrival) SizedBox(width: compact ? 6 : 8),
                  Expanded(
                    child: Text(
                      street.isNotEmpty ? '$line1 • $street' : line1,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                        height: 1.12,
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

class DriverNavLoadingBanner extends StatelessWidget {
  final bool compact;
  final String text;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverNavLoadingBanner({
    super.key,
    required this.compact,
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
          borderRadius: BorderRadius.circular(compact ? 9 : 10),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: compact ? 7 : 8,
              sigmaY: compact ? 7 : 8,
            ),
            child: Container(
              constraints: BoxConstraints(maxHeight: compact ? 44 : 48),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 9,
                vertical: compact ? 3 : 4,
              ),
              decoration: BoxDecoration(
                color: palette.surfaceAlt.withOpacity(
                  palette.isDark ? 0.82 : 0.95,
                ),
                borderRadius: BorderRadius.circular(compact ? 9 : 10),
                border: Border.all(
                  color: palette.border.withOpacity(
                    palette.isDark ? 0.55 : 0.85,
                  ),
                ),
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary.withOpacity(0.92),
                ),
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
  final String text;
  final ValueListenable<DriverThemeVariant>? themeListenable;

  const DriverNoNavInstructionsBanner({
    super.key,
    required this.compact,
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
          borderRadius: BorderRadius.circular(compact ? 9 : 10),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: compact ? 7 : 8,
              sigmaY: compact ? 7 : 8,
            ),
            child: Container(
              constraints: BoxConstraints(maxHeight: compact ? 44 : 48),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 9,
                vertical: compact ? 3 : 4,
              ),
              decoration: BoxDecoration(
                color: palette.surfaceAlt.withOpacity(
                  palette.isDark ? 0.82 : 0.95,
                ),
                borderRadius: BorderRadius.circular(compact ? 9 : 10),
                border: Border.all(color: palette.danger.withOpacity(0.55)),
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary.withOpacity(0.92),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
