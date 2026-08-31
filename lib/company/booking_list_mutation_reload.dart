// BOOKINGS-LIST-PAGINATION-CLIENT-P0C
//
// One chauffeur/company-preview path after a successful booking/leg mutation.
// Invalidation is never skipped by refresh cooldown. Visible reload is
// coalesced and never prefetches the other actor.

import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';

/// Trigger used only for the visible first-page reload after invalidation.
const String kBookingListMutationReloadTrigger = 'booking_mutation';

/// Whether a driver-list refresh must bypass the 45 s repository cache.
/// Successful mutations use [BookingListMutationReloadCoordinator] instead of
/// relying on this list alone.
bool bookingListRefreshBypassesRepositoryCache(String trigger) {
  switch (trigger) {
    case kBookingListMutationReloadTrigger:
    case 'list_manual':
    case 'drawer_manual':
    case 'status_change':
    case 'status_change_verified':
    case 'planned_stop_bridge_handled_leg':
    case 'delete_action':
    case 'calculator_created':
    case 'leg_status_change':
    case 'street_stop_retry':
    case 'street_reopen_retry':
    case 'street_recovery_finalize_ok':
      return true;
    default:
      return trigger.startsWith('street_');
  }
}

/// Cross-actor invalidate + one coalesced visible first-page reload.
class BookingListMutationReloadCoordinator {
  BookingListMutationReloadCoordinator({
    required BookingListPageRepository repository,
    void Function()? onAdvanceGeneration,
    DateTime Function()? clock,
    this.coalesceWindow = const Duration(seconds: 8),
  }) : _repository = repository,
       _onAdvanceGeneration = onAdvanceGeneration,
       _clock = clock ?? DateTime.now;

  final BookingListPageRepository _repository;
  final void Function()? _onAdvanceGeneration;
  final DateTime Function() _clock;
  final Duration coalesceWindow;
  Future<void>? _inFlight;
  String? _lastMutationKey;
  String? _lastScopeKey;
  DateTime? _completedAt;

  bool get isReloadInFlight => _inFlight != null;

  /// 1. Invalidate every company/driver page for [tenantId]/[companyId].
  /// 2. Advance the caller generation so a late pre-mutation result cannot win.
  /// 3. Reload only the currently visible surface, coalesced.
  ///
  /// Concurrent calls join the in-flight reload. A later confirmation for the
  /// same [mutationKey] inside [coalesceWindow] does not invalidate the fresh
  /// page or issue a second GET.
  Future<void> reloadVisibleAfterSuccessfulMutation({
    required String tenantId,
    required String companyId,
    required Future<void> Function() reloadVisibleFirstPage,
    String mutationKey = '',
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final tenant = tenantId.trim();
    final company = companyId.trim();
    final key = mutationKey.trim();
    final scope = '$tenant|$company';
    if (key.isNotEmpty &&
        _lastMutationKey == key &&
        _lastScopeKey == scope &&
        _completedAt != null &&
        _clock().difference(_completedAt!) < coalesceWindow) {
      return Future<void>.value();
    }
    late final Future<void> task;
    task = Future<void>(() async {
      var succeeded = false;
      try {
        _repository.invalidateBookingListsForAffectedCompany(
          tenantId: tenant,
          companyId: company,
        );
        _onAdvanceGeneration?.call();
        await reloadVisibleFirstPage();
        succeeded = true;
      } finally {
        if (succeeded) {
          _lastMutationKey = key;
          _lastScopeKey = scope;
          _completedAt = _clock();
        }
        if (identical(_inFlight, task)) {
          _inFlight = null;
        }
      }
    });
    _inFlight = task;
    return task;
  }
}
