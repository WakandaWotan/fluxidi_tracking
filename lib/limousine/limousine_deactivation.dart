// LIMOUSINE-MARKETPLACE-P0 (addendum) — deactivation semantics contract.
//
// Deactivation stops NEW Limousine discovery and bookings without destroying
// existing data. Mirrors the platform's existing non-destructive patterns
// (suspension gates only new bookings; fleet/driver tombstones drop active
// lists only; monotonic `source_revision` so older state never overwrites a
// newer disable/suspension).

/// What deactivation stops and what it must preserve. Every preserve* flag is
/// intentionally true; a change here is a semantic regression.
class LimousineDeactivationDecision {
  const LimousineDeactivationDecision();

  // Stops:
  bool get stopNewMarketplaceVisibility => true;
  bool get stopNewBookings => true;

  // Preserves (non-destructive):
  bool get preserveExistingBookings => true;
  bool get preserveBookingCompletionFlow => true;
  bool get preserveCustomers => true;
  bool get preserveVehicles => true;
  bool get preserveDrivers => true;
  bool get preserveAssignments => true;
  bool get preservePayments => true;
  bool get preserveDocuments => true;
  bool get preserveInvoices => true;
  bool get preserveAudit => true;
  bool get preserveHistory => true;
  bool get preserveLimousineConfigForReactivation => true;
  bool get preservePricingSnapshots => true;

  // Must never happen:
  bool get disablesUnrelatedTaxiOrAirport => false;
  bool get erasesHistoricalPricingSnapshots => false;
}

const LimousineDeactivationDecision kLimousineDeactivationDecision =
    LimousineDeactivationDecision();

/// A control-plane command against Limousine public availability.
enum LimousineAvailabilityCommand { enable, disable, suspend }

class LimousineAvailabilityTransition {
  const LimousineAvailabilityTransition({
    required this.applied,
    required this.effectiveCommand,
    required this.effectiveRevision,
    this.ignoredReason,
  });

  final bool applied;
  final LimousineAvailabilityCommand effectiveCommand;
  final int effectiveRevision;
  final String? ignoredReason;
}

/// Monotonic transition: an incoming command applies only when its revision is
/// strictly newer than the current one. An older payload can never overwrite a
/// newer disable/suspension; a newer valid reactivation may restore
/// availability. Equal revisions are treated as idempotent replays and ignored.
LimousineAvailabilityTransition resolveLimousineAvailabilityTransition({
  required LimousineAvailabilityCommand currentCommand,
  required int currentRevision,
  required LimousineAvailabilityCommand incomingCommand,
  required int incomingRevision,
}) {
  if (incomingRevision <= currentRevision) {
    return LimousineAvailabilityTransition(
      applied: false,
      effectiveCommand: currentCommand,
      effectiveRevision: currentRevision,
      ignoredReason: incomingRevision == currentRevision
          ? 'idempotent_replay'
          : 'stale_revision',
    );
  }
  return LimousineAvailabilityTransition(
    applied: true,
    effectiveCommand: incomingCommand,
    effectiveRevision: incomingRevision,
  );
}
