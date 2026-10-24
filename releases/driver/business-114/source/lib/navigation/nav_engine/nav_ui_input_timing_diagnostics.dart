// NAV-ANNOTATION-LIFECYCLE-REPAIR-1
//
// Minimal sanitized timing diagnostics for Ter plaatse / View zoom / route
// annotation delete. No coordinates, booking ids, tokens, or addresses.

import 'package:flutter/foundation.dart';

/// Supported diagnostic actions (low-cardinality).
enum NavUiInputTimingAction {
  terPlaatse,
  viewZoom,
  routeAnnotationDelete,
}

String navUiInputTimingActionLabel(NavUiInputTimingAction action) {
  switch (action) {
    case NavUiInputTimingAction.terPlaatse:
      return 'ter_plaatse';
    case NavUiInputTimingAction.viewZoom:
      return 'view_zoom';
    case NavUiInputTimingAction.routeAnnotationDelete:
      return 'route_annotation_delete';
  }
}

/// Phase of a timed UI / annotation operation.
enum NavUiInputTimingPhase {
  inputReceived,
  completed,
  failed,
  deleteStart,
  deleteCompleted,
  deleteFailed,
}

String navUiInputTimingPhaseLabel(NavUiInputTimingPhase phase) {
  switch (phase) {
    case NavUiInputTimingPhase.inputReceived:
      return 'input_received';
    case NavUiInputTimingPhase.completed:
      return 'completed';
    case NavUiInputTimingPhase.failed:
      return 'failed';
    case NavUiInputTimingPhase.deleteStart:
      return 'delete_start';
    case NavUiInputTimingPhase.deleteCompleted:
      return 'delete_completed';
    case NavUiInputTimingPhase.deleteFailed:
      return 'delete_failed';
  }
}

/// Emit one PII-free `[NAV_UI_INPUT]` diagnostic line.
void logNavUiInputTiming({
  required NavUiInputTimingAction action,
  required NavUiInputTimingPhase phase,
  int? managerGeneration,
  int? renderEpoch,
  int? sessionGeneration,
  int? styleGeneration,
  int? durationMs,
  String? reason,
  void Function(String line)? emit,
}) {
  final buf = StringBuffer('[NAV_UI_INPUT] ')
    ..write('action=${navUiInputTimingActionLabel(action)} ')
    ..write('phase=${navUiInputTimingPhaseLabel(phase)}');
  if (managerGeneration != null) {
    buf.write(' managerGeneration=$managerGeneration');
  }
  if (renderEpoch != null) buf.write(' renderEpoch=$renderEpoch');
  if (sessionGeneration != null) {
    buf.write(' sessionGeneration=$sessionGeneration');
  }
  if (styleGeneration != null) buf.write(' styleGeneration=$styleGeneration');
  if (durationMs != null) buf.write(' durationMs=$durationMs');
  if (reason != null && reason.trim().isNotEmpty) {
    buf.write(' reason=${reason.trim()}');
  }
  final line = buf.toString();
  if (emit != null) {
    emit(line);
  } else {
    debugPrint(line);
  }
}
