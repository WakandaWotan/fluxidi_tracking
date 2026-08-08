/// DRIVER-HISTORY-PENDING-FLICKER-MONOTONICITY-P1
///
/// Pure presentation/merge helpers for driver Historiek.
///
/// Offline STOP durability still persists local pending rows; these helpers
/// only decide what the history page may paint during sync so a trip_id that
/// was already backend-authoritative never visually regresses to
/// "Lokaal opgeslagen — niet bevestigd".
library;

/// True when a local history row is the offline-STOP pending projection that
/// may be superseded once the same [tripId] exists on the backend.
bool isOfflineStopPendingFinalizeRecord(Map<String, dynamic> row) {
  final source = (row['history_source'] ?? '').toString().trim().toLowerCase();
  if (source == 'offline_stop_pending_finalize') return true;
  final nested = row['booking_details'];
  if (nested is Map) {
    final nestedSource =
        (nested['history_source'] ?? '').toString().trim().toLowerCase();
    if (nestedSource == 'offline_stop_pending_finalize') return true;
  }
  final pending = row['finalize_pending'];
  if (pending == true) return true;
  if (pending is String && pending.trim().toLowerCase() == 'true') return true;
  return false;
}

/// Local paint plan for the history local-first phase.
class TripHistoryLocalPaintPlan<T> {
  const TripHistoryLocalPaintPlan({
    required this.items,
    required this.retainAuthoritativeSummary,
    required this.summaryNeutral,
  });

  /// Rows to show during sync (before remote merge completes).
  final List<T> items;

  /// When true, keep the last authoritative KPI summary while syncing.
  final bool retainAuthoritativeSummary;

  /// When true (cold start), do not treat [items] as final KPI truth.
  final bool summaryNeutral;
}

/// Builds the local-phase list without downgrading authoritative trip_ids.
///
/// - With a prior authoritative snapshot: keep those rows and overlay only
///   genuine local-unconfirmed rows whose trip_id is absent from that set.
/// - Cold start: surface only genuine local-unconfirmed rows (immediate
///   offline visibility) and mark summary as neutral until remote merge.
TripHistoryLocalPaintPlan<T> planTripHistoryLocalPaintPhase<T>({
  required List<T> priorAuthoritativeItems,
  required bool hasAuthoritativeSnapshot,
  required List<T> localItems,
  required String Function(T item) tripIdOf,
  required bool Function(T item) isLocalUnconfirmed,
}) {
  final pendingLocals = <T>[];
  for (final item in localItems) {
    if (!isLocalUnconfirmed(item)) continue;
    final id = tripIdOf(item).trim();
    if (id.isEmpty) continue;
    pendingLocals.add(item);
  }

  if (hasAuthoritativeSnapshot && priorAuthoritativeItems.isNotEmpty) {
    final authById = <String, T>{};
    for (final item in priorAuthoritativeItems) {
      final id = tripIdOf(item).trim();
      if (id.isEmpty) continue;
      authById.putIfAbsent(id, () => item);
    }
    final authIds = authById.keys.toSet();
    for (final pending in pendingLocals) {
      final id = tripIdOf(pending).trim();
      if (authIds.contains(id)) continue; // never downgrade
      authById.putIfAbsent(id, () => pending);
    }
    return TripHistoryLocalPaintPlan<T>(
      items: List<T>.unmodifiable(authById.values),
      retainAuthoritativeSummary: true,
      summaryNeutral: false,
    );
  }

  // Cold start: only genuine pending/unconfirmed locals — not a fake full history.
  final byId = <String, T>{};
  for (final pending in pendingLocals) {
    final id = tripIdOf(pending).trim();
    byId.putIfAbsent(id, () => pending);
  }
  return TripHistoryLocalPaintPlan<T>(
    items: List<T>.unmodifiable(byId.values),
    retainAuthoritativeSummary: false,
    summaryNeutral: true,
  );
}

/// Trip ids whose local offline-STOP pending projection is superseded by
/// an authoritative backend row with the same trip_id.
Set<String> supersededOfflineStopPendingTripIds({
  required Iterable<Map<String, dynamic>> localRecords,
  required Iterable<String> backendTripIds,
}) {
  final backend = backendTripIds
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  if (backend.isEmpty) return const <String>{};
  final out = <String>{};
  for (final row in localRecords) {
    if (!isOfflineStopPendingFinalizeRecord(row)) continue;
    final id = (row['trip_id'] ?? row['tripId'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    if (backend.contains(id)) out.add(id);
  }
  return out;
}

/// Returns JSONL rows with superseded offline-STOP pending projections removed.
///
/// Keeps unrelated local history (including genuine still-pending rows and
/// `local_only_direct_fallback` rows).
List<Map<String, dynamic>> filterSupersededOfflineStopPendingRows({
  required List<Map<String, dynamic>> rows,
  required Set<String> supersededTripIds,
}) {
  if (supersededTripIds.isEmpty) {
    return List<Map<String, dynamic>>.unmodifiable(rows);
  }
  final drop = supersededTripIds
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  final kept = <Map<String, dynamic>>[];
  for (final row in rows) {
    final id = (row['trip_id'] ?? row['tripId'] ?? '').toString().trim();
    if (id.isNotEmpty &&
        drop.contains(id) &&
        isOfflineStopPendingFinalizeRecord(row)) {
      continue;
    }
    kept.add(row);
  }
  return List<Map<String, dynamic>>.unmodifiable(kept);
}
