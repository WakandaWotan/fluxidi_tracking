import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'navigation_route_warnings.dart';

/// Optional child of the existing navigation overlay. Reuses the existing
/// route/progress/expiry lifecycle; no map, GPS, polling, ETA or routing owner.
class NavigationRouteWarningBanner extends StatelessWidget {
  const NavigationRouteWarningBanner({
    super.key,
    required this.snapshot,
    required this.progressMeters,
    required this.progressTrusted,
    this.now,
    this.translate,
  });
  final RouteWarnings snapshot;
  final double progressMeters;
  final bool progressTrusted;
  final DateTime? now;
  final String Function(String kind)? translate;

  @override
  Widget build(BuildContext context) {
    final warning = snapshot.ahead(
      progressMeters: progressMeters,
      trusted: progressTrusted,
      now: now ?? DateTime.now(),
    );
    if (warning == null) return const SizedBox.shrink();
    final distance = math.max(0, warning.start - progressMeters);
    final text = translate?.call(warning.kind) ?? warning.label;
    final distanceText = distance < 10
        ? ''
        : distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${(distance / (distance < 100 ? 10 : 100)).round() * (distance < 100 ? 10 : 100)} m';
    final label = distanceText.isEmpty ? text : '$text · $distanceText';
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                warning.kind == 'closure'
                    ? Icons.block
                    : Icons.warning_amber_rounded,
                color: theme.colorScheme.onSurface,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
