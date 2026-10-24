import 'package:flutter/material.dart';

import '../driver/driver_duty_bridge.dart';
import '../driver_session_store.dart';
import '../driver_theme_palette.dart';

enum DriverHeaderAvailabilityStatus {
  unknown,
  available,
  paused,
  offline,
  inactive,
  busy,
}

/// Presentation evidence only: never grants GPS, dispatch or session rights.
/// Kept in memory for this Home instance, never restored from a local profile.
class DriverHeaderAvailabilityConfirmation {
  const DriverHeaderAvailabilityConfirmation({
    required this.owner,
    required this.driverId,
    required this.rawStatus,
  });

  final ActiveDriverSession owner;
  final String driverId;
  final String rawStatus;

  DriverHeaderAvailabilityStatus forDisplay({
    required ActiveDriverSession? session,
    required String displayedDriverId,
  }) {
    final expiry = DateTime.tryParse(session?.driverSessionExpiresAtUtc ?? '');
    if (session == null ||
        !driverDutyIdentity(session).complete ||
        (session.driverSessionToken ?? '').trim().isEmpty ||
        (expiry != null && !expiry.isAfter(DateTime.now())) ||
        displayedDriverId.trim().isEmpty ||
        driverId != displayedDriverId.trim() ||
        !DriverDutyBridge.sameAuthenticatedActor(owner, session)) {
      return DriverHeaderAvailabilityStatus.unknown;
    }
    return switch (rawStatus.trim().toLowerCase()) {
      'available' ||
      'ready' ||
      'online' => DriverHeaderAvailabilityStatus.available,
      'paused' ||
      'pause' ||
      'not_available' ||
      'unavailable' => DriverHeaderAvailabilityStatus.paused,
      'offline' => DriverHeaderAvailabilityStatus.offline,
      'inactive' => DriverHeaderAvailabilityStatus.inactive,
      'busy' ||
      'on_trip' ||
      'on_the_way' ||
      'waiting' => DriverHeaderAvailabilityStatus.busy,
      _ => DriverHeaderAvailabilityStatus.unknown,
    };
  }
}

class DriverHeaderAvailabilityIndicator extends StatelessWidget {
  const DriverHeaderAvailabilityIndicator({
    super.key,
    required this.status,
    required this.palette,
    required this.label,
  });

  final DriverHeaderAvailabilityStatus status;
  final DriverThemePalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DriverHeaderAvailabilityStatus.available => palette.success,
      DriverHeaderAvailabilityStatus.offline =>
        palette.isDark ? Colors.grey.shade400 : Colors.grey.shade700,
      DriverHeaderAvailabilityStatus.inactive => palette.danger,
      // Semantic warning color; the general interface uses the active palette.
      DriverHeaderAvailabilityStatus.paused ||
      DriverHeaderAvailabilityStatus.busy =>
        palette.isDark ? Colors.orange.shade300 : Colors.orange.shade900,
      DriverHeaderAvailabilityStatus.unknown => palette.textMuted,
    };
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: Container(
          key: const ValueKey('driver-header-availability-dot'),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: driverReadableTextOn(color, palette.surface),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
