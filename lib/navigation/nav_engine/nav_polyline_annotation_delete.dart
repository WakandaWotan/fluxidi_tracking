// NAV-ANNOTATION-LIFECYCLE-REPAIR-1
//
// Idempotent, serialized, epoch-aware polyline annotation deletion.
// Field failure (2026-07-27): overlapping delete against the same
// PolylineAnnotation id after style swap / route replace threw
// PlatformException("Annotation has not been added on the map") through
// DartMessenger as an unhandled async error.

import 'dart:async';

import 'package:flutter/services.dart';

/// Outcome of one guarded polyline delete attempt (PII-free).
enum NavPolylineDeleteOutcome {
  /// Native delete ran successfully.
  deleted,

  /// Annotation id was already deleted or was never on the map (idempotent).
  alreadyGone,

  /// Manager generation advanced (style reload / recreate); native skipped.
  staleSkipped,

  /// Unexpected failure — logged by caller, never rethrown from this helper.
  unexpectedFailure,
}

/// Classifies Mapbox/Flutter annotation delete failures.
///
/// Only proven stale/already-deleted/disposed lifecycle cases are non-fatal.
enum NavPolylineDeleteErrorClass {
  /// "Annotation has not been added on the map" / already removed.
  alreadyDeleted,

  /// Native manager removed ("No manager found").
  managerLost,

  /// Anything else — must stay visible in diagnostics.
  unexpected,
}

/// True when [error] is a proven stale/already-deleted/disposed lifecycle case.
bool isStalePolylineAnnotationDeleteError(Object error) {
  return classifyPolylineAnnotationDeleteError(error) !=
      NavPolylineDeleteErrorClass.unexpected;
}

NavPolylineDeleteErrorClass classifyPolylineAnnotationDeleteError(
  Object error,
) {
  final blob = error.toString().toLowerCase();
  String message = '';
  String details = '';
  if (error is PlatformException) {
    message = (error.message ?? '').toLowerCase();
    details = (error.details?.toString() ?? '').toLowerCase();
  }
  final haystack = '$blob $message $details';
  if (haystack.contains('annotation has not been added on the map') ||
      haystack.contains('already deleted') ||
      haystack.contains('annotation not found')) {
    return NavPolylineDeleteErrorClass.alreadyDeleted;
  }
  if (haystack.contains('no manager found')) {
    return NavPolylineDeleteErrorClass.managerLost;
  }
  return NavPolylineDeleteErrorClass.unexpected;
}

/// Sanitized error token for diagnostics (no geometry / booking ids).
String navPolylineDeleteErrorToken(Object error) {
  final klass = classifyPolylineAnnotationDeleteError(error);
  switch (klass) {
    case NavPolylineDeleteErrorClass.alreadyDeleted:
      return 'already_deleted';
    case NavPolylineDeleteErrorClass.managerLost:
      return 'manager_lost';
    case NavPolylineDeleteErrorClass.unexpected:
      if (error is PlatformException) {
        final code = (error.code).trim();
        return code.isEmpty ? 'platform_exception' : 'platform:$code';
      }
      return 'unexpected:${error.runtimeType}';
  }
}

/// Ownership captured at delete enqueue time.
///
/// Native delete is skipped only when [managerGeneration] no longer matches
/// (manager recreated / style reload). Render/session/style epochs are kept so
/// callers can refuse to mutate the *current* route after a newer install —
/// delete completion itself must never clear current route handles.
class NavPolylineDeleteOwnership {
  const NavPolylineDeleteOwnership({
    required this.managerGeneration,
    required this.renderEpoch,
    required this.sessionGeneration,
    required this.styleGeneration,
  });

  final int managerGeneration;
  final int renderEpoch;
  final int sessionGeneration;
  final int styleGeneration;
}

/// Result of a coordinated delete.
class NavPolylineDeleteResult {
  const NavPolylineDeleteResult({
    required this.outcome,
    required this.ownershipStillCurrent,
    this.errorClass,
    this.errorToken,
  });

  final NavPolylineDeleteOutcome outcome;

  /// True only when manager + render + session + style all still match the
  /// capture. Used to forbid post-completion mutation of the current route.
  final bool ownershipStillCurrent;
  final NavPolylineDeleteErrorClass? errorClass;
  final String? errorToken;
}

/// Tracks deleted annotation ids and serializes overlapping deletes so a
/// second delete against the same id cannot race the native annotationMap.
class NavPolylineDeleteCoordinator {
  Future<void> _serial = Future<void>.value();
  final Set<String> _deletedIds = <String>{};
  int _managerGeneration = 0;

  int get managerGeneration => _managerGeneration;
  int get trackedDeletedCount => _deletedIds.length;

  /// Call when a new native PolylineAnnotationManager generation is activated.
  void onManagerActivated(int managerGeneration) {
    _managerGeneration = managerGeneration;
    _deletedIds.clear();
  }

  bool wasDeleted(String annotationId) {
    final id = annotationId.trim();
    if (id.isEmpty) return true;
    return _deletedIds.contains(id);
  }

  /// True when a delete completion is still allowed to mutate shared route
  /// handles. Prefer nulling refs *before* enqueue; this is a safety gate so a
  /// stale route-A delete completion cannot clear route B.
  bool mayMutateCurrentRoute(
    NavPolylineDeleteOwnership ownership, {
    required int currentManagerGeneration,
    required int currentRenderEpoch,
    required int currentSessionGeneration,
    required int currentStyleGeneration,
  }) {
    return ownership.managerGeneration == currentManagerGeneration &&
        ownership.renderEpoch == currentRenderEpoch &&
        ownership.sessionGeneration == currentSessionGeneration &&
        ownership.styleGeneration == currentStyleGeneration;
  }

  /// Serialized, idempotent delete. Never throws.
  Future<NavPolylineDeleteResult> delete({
    required String annotationId,
    required NavPolylineDeleteOwnership ownership,
    required int Function() currentManagerGeneration,
    required int Function() currentRenderEpoch,
    required int Function() currentSessionGeneration,
    required int Function() currentStyleGeneration,
    required Future<void> Function() nativeDelete,
  }) {
    final id = annotationId.trim();
    final started = Completer<NavPolylineDeleteResult>();
    _serial = _serial
        .then((_) async {
          final result = await _deleteUnlocked(
            annotationId: id,
            ownership: ownership,
            currentManagerGeneration: currentManagerGeneration,
            currentRenderEpoch: currentRenderEpoch,
            currentSessionGeneration: currentSessionGeneration,
            currentStyleGeneration: currentStyleGeneration,
            nativeDelete: nativeDelete,
          );
          if (!started.isCompleted) started.complete(result);
        })
        .catchError((Object e, StackTrace st) {
          if (!started.isCompleted) {
            started.complete(
              NavPolylineDeleteResult(
                outcome: NavPolylineDeleteOutcome.unexpectedFailure,
                ownershipStillCurrent: false,
                errorClass: NavPolylineDeleteErrorClass.unexpected,
                errorToken: navPolylineDeleteErrorToken(e),
              ),
            );
          }
        });
    return started.future;
  }

  Future<NavPolylineDeleteResult> _deleteUnlocked({
    required String annotationId,
    required NavPolylineDeleteOwnership ownership,
    required int Function() currentManagerGeneration,
    required int Function() currentRenderEpoch,
    required int Function() currentSessionGeneration,
    required int Function() currentStyleGeneration,
    required Future<void> Function() nativeDelete,
  }) async {
    bool stillCurrent() =>
        ownership.managerGeneration == currentManagerGeneration() &&
        ownership.renderEpoch == currentRenderEpoch() &&
        ownership.sessionGeneration == currentSessionGeneration() &&
        ownership.styleGeneration == currentStyleGeneration();

    // Manager recreated — annotations of the old generation are gone with it.
    if (ownership.managerGeneration != currentManagerGeneration()) {
      return const NavPolylineDeleteResult(
        outcome: NavPolylineDeleteOutcome.staleSkipped,
        ownershipStillCurrent: false,
      );
    }

    if (annotationId.isEmpty || _deletedIds.contains(annotationId)) {
      return NavPolylineDeleteResult(
        outcome: NavPolylineDeleteOutcome.alreadyGone,
        ownershipStillCurrent: stillCurrent(),
        errorClass: NavPolylineDeleteErrorClass.alreadyDeleted,
        errorToken: 'already_deleted',
      );
    }

    try {
      await nativeDelete();
      _deletedIds.add(annotationId);
      return NavPolylineDeleteResult(
        outcome: NavPolylineDeleteOutcome.deleted,
        ownershipStillCurrent: stillCurrent(),
      );
    } catch (e) {
      final klass = classifyPolylineAnnotationDeleteError(e);
      if (klass != NavPolylineDeleteErrorClass.unexpected) {
        _deletedIds.add(annotationId);
        return NavPolylineDeleteResult(
          outcome: NavPolylineDeleteOutcome.alreadyGone,
          ownershipStillCurrent: stillCurrent(),
          errorClass: klass,
          errorToken: navPolylineDeleteErrorToken(e),
        );
      }
      return NavPolylineDeleteResult(
        outcome: NavPolylineDeleteOutcome.unexpectedFailure,
        ownershipStillCurrent: stillCurrent(),
        errorClass: klass,
        errorToken: navPolylineDeleteErrorToken(e),
      );
    }
  }
}
