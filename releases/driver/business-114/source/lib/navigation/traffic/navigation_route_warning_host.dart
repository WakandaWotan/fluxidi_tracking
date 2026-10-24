import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'navigation_route_warning_banner.dart';
import 'navigation_route_warning_controller.dart';
import 'navigation_traffic_controller.dart';

/// Preserve the established traffic banner when it is present; the optional
/// warning occupies the same presentation slot only when that slot is free.
/// This does not merge traffic evidence or modify routing, ETA or progress.
class NavigationRouteWarningHost extends StatelessWidget {
  const NavigationRouteWarningHost({
    super.key,
    required this.controller,
    required this.existingAlertListenable,
    required this.child,
    this.translate,
    this.clock,
  });
  final NavigationRouteWarningController controller;
  final ValueListenable<NavigationTrafficAlert?> existingAlertListenable;
  final Widget child;
  final String Function(String kind)? translate;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, existingAlertListenable]),
    child: child,
    builder: (context, child) {
      final now = clock?.call() ?? DateTime.now();
      final snapshot = controller.current(now);
      if (existingAlertListenable.value != null ||
          snapshot.ahead(
                progressMeters: controller.progressMeters,
                trusted: controller.progressTrusted,
                now: now,
              ) ==
              null)
        return child!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NavigationRouteWarningBanner(
            snapshot: snapshot,
            progressMeters: controller.progressMeters,
            progressTrusted: controller.progressTrusted,
            now: now,
            translate: translate,
          ),
          const SizedBox(height: 8),
          child!,
        ],
      );
    },
  );
}
