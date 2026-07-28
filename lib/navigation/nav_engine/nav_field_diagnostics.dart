// NAV-MOBILE-DATA-MINIMAL-SAFE-RELEASE-P0-1 — Part G
//
// PII-free field diagnostics for the mobile-data navigation freeze
// investigation. Every helper prints a bounded, fixed-shape line into
// [debugPrint]; nothing here ever accepts or interpolates coordinates,
// addresses, tokens, IDs or raw worker payloads.
//
// The events emitted here augment (never replace) the existing
// [_logNavBounded] / NAV_LATENCY diagnostics. They exist so the next field
// drive can attribute a stall to the exact dispatcher stage or blocked
// interaction, without waiting for a full logcat capture of the surrounding
// Flutter tree.

import 'package:flutter/foundation.dart';

import 'nav_background_dispatcher.dart' show NavBackgroundDispatchEvent;

/// Bounded label vocabulary for background dispatcher owners. Kept small so
/// downstream grep patterns can be exact.
enum NavFieldDispatcherLabel {
  ping,
  routePresentation,
}

/// Bounded token for the blocked-active-ride interactions.
enum NavFieldBlockedInteraction {
  styleTap,
  zoomIn,
  zoomOut,
}

String _dispatcherToken(NavFieldDispatcherLabel label) {
  switch (label) {
    case NavFieldDispatcherLabel.ping:
      return 'ping';
    case NavFieldDispatcherLabel.routePresentation:
      return 'route_presentation';
  }
}

String _dispatchEventToken(NavBackgroundDispatchEvent event) {
  switch (event) {
    case NavBackgroundDispatchEvent.enqueuedStart:
      return 'enqueued_start';
    case NavBackgroundDispatchEvent.enqueuedPending:
      return 'enqueued_pending';
    case NavBackgroundDispatchEvent.replacedPending:
      return 'replaced_pending';
    case NavBackgroundDispatchEvent.rejectedDisposed:
      return 'rejected_disposed';
    case NavBackgroundDispatchEvent.rejectedIneligible:
      return 'rejected_ineligible';
    case NavBackgroundDispatchEvent.started:
      return 'started';
    case NavBackgroundDispatchEvent.completed:
      return 'completed';
    case NavBackgroundDispatchEvent.failed:
      return 'failed';
    case NavBackgroundDispatchEvent.timedOut:
      return 'timed_out';
    case NavBackgroundDispatchEvent.disposed:
      return 'disposed';
  }
}

String _blockedInteractionToken(NavFieldBlockedInteraction interaction) {
  switch (interaction) {
    case NavFieldBlockedInteraction.styleTap:
      return 'style_tap';
    case NavFieldBlockedInteraction.zoomIn:
      return 'zoom_in';
    case NavFieldBlockedInteraction.zoomOut:
      return 'zoom_out';
  }
}

/// Bounded printer indirection so tests can capture output without stubbing
/// `debugPrint` globally.
@visibleForTesting
void Function(String message) navFieldDiagnosticsPrinter =
    (msg) => debugPrint(msg);

@visibleForTesting
void resetNavFieldDiagnosticsPrinter() {
  navFieldDiagnosticsPrinter = (msg) => debugPrint(msg);
}

/// Emits a single PII-free line documenting a background-dispatcher event.
///
/// Example lines (fixed prefix, bounded key=value pairs):
///
///   [NAV_MOBILE_SAFE][DISPATCH] owner=ping event=enqueued_pending seq=42
///   [NAV_MOBILE_SAFE][DISPATCH] owner=route_presentation event=timed_out seq=41
void logNavBackgroundDispatch({
  required NavFieldDispatcherLabel owner,
  required NavBackgroundDispatchEvent event,
  int? sequence,
  int? monotonicMs,
}) {
  final buffer = StringBuffer('[NAV_MOBILE_SAFE][DISPATCH] ');
  buffer
    ..write('owner=')
    ..write(_dispatcherToken(owner))
    ..write(' event=')
    ..write(_dispatchEventToken(event));
  if (sequence != null) {
    buffer
      ..write(' seq=')
      ..write(sequence);
  }
  if (monotonicMs != null) {
    buffer
      ..write(' monoMs=')
      ..write(monotonicMs);
  }
  navFieldDiagnosticsPrinter(buffer.toString());
}

/// Emits a single PII-free line documenting one accepted-GPS meter tick.
void logNavAcceptedGpsMeter({
  required int sequence,
  required int monotonicMs,
  required int meterCoreMicros,
}) {
  navFieldDiagnosticsPrinter(
    '[NAV_MOBILE_SAFE][GPS_METER] seq=$sequence monoMs=$monotonicMs '
    'meterCoreUs=$meterCoreMicros',
  );
}

/// Emits a single PII-free line documenting a blocked active-ride
/// interaction (style tap, +/- zoom). Used both for UI-gated blocks and
/// programmatic guardrails.
void logNavActiveRideBlocked({
  required NavFieldBlockedInteraction interaction,
  required String reason,
}) {
  navFieldDiagnosticsPrinter(
    '[NAV_MOBILE_SAFE][ACTIVE_RIDE_BLOCKED] '
    'interaction=${_blockedInteractionToken(interaction)} reason=$reason',
  );
}

/// Emits a single PII-free line documenting the START → fixed style →
/// Street Level transition.
void logNavActiveRideStart({
  required String style,
  required bool enterStreetLevel,
  required bool discardPreviewZoom,
  required int styleGeneration,
}) {
  navFieldDiagnosticsPrinter(
    '[NAV_MOBILE_SAFE][ACTIVE_RIDE_START] style=$style '
    'streetLevel=$enterStreetLevel discardPreviewZoom=$discardPreviewZoom '
    'styleGen=$styleGeneration',
  );
}

/// Emits a single PII-free line documenting style preparation lifecycle
/// (`start` / `end` / `failed`).
void logNavStyleLifecycle({
  required String style,
  required String phase,
  int? styleGeneration,
  int? durationMs,
}) {
  final buffer = StringBuffer('[NAV_MOBILE_SAFE][STYLE_LIFECYCLE] ');
  buffer
    ..write('style=')
    ..write(style)
    ..write(' phase=')
    ..write(phase);
  if (styleGeneration != null) {
    buffer
      ..write(' styleGen=')
      ..write(styleGeneration);
  }
  if (durationMs != null) {
    buffer
      ..write(' durationMs=')
      ..write(durationMs);
  }
  navFieldDiagnosticsPrinter(buffer.toString());
}

/// Emits the required/completed/errored counts observed for one offline
/// resource batch (StylePack or TileRegion).
void logNavOfflineTruth({
  required String kind, // 'style_pack' | 'tile_region'
  required String regionId, // opaque region id, no PII
  required int requiredCount,
  required int completedCount,
  required int erroredCount,
  bool? verified,
}) {
  final buffer = StringBuffer('[NAV_MOBILE_SAFE][OFFLINE_TRUTH] ');
  buffer
    ..write('kind=')
    ..write(kind)
    ..write(' region=')
    ..write(regionId)
    ..write(' required=')
    ..write(requiredCount)
    ..write(' completed=')
    ..write(completedCount)
    ..write(' errored=')
    ..write(erroredCount);
  if (verified != null) {
    buffer
      ..write(' verified=')
      ..write(verified);
  }
  navFieldDiagnosticsPrinter(buffer.toString());
}
