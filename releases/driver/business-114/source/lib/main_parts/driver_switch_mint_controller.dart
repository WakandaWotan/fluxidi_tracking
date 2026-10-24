// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix)
//
// Pure state machine for the in-page A -> B driver-switch mint. Extracted
// from `_DriverHomePageState` so the concurrency invariants can be exercised
// by unit tests that run the same production code, with a stub `mintFn` in
// place of the real `mintOperatorDriverSession` HTTP call.
//
// This file is included via `part 'main_parts/driver_switch_mint_controller.dart';`
// in `lib/main.dart`, so it participates in the main.dart umbrella library and
// has direct access to `OperatorMintedDriverSession`, `OperatorMintException`,
// `mintOperatorDriverSession`, `DriverProfile`, `ActiveDriverSession`,
// `ActiveCompanySession`, `activeCompanySessionNotifier`,
// `activeDriverSessionNotifier`, `kOperatorMintDriverLinkMethod`, and the
// other public symbols declared elsewhere in the umbrella library.

part of '../main.dart';

/// Injectable seam used by production and by tests. Production wires this to
/// [mintOperatorDriverSession] from `lib/app_config.dart`; tests inject stubs
/// that return controllable futures backed by [Completer]s.
typedef MintOperatorDriverSessionFn =
    Future<OperatorMintedDriverSession> Function({
      required String bookingBaseUrl,
      required String companySessionToken,
      required String targetDriverId,
      String? tenantId,
      String? companyId,
    });

/// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix)
///
/// Test-only override for the operator-mint seam used by
/// `_DriverHomePageState`. Widget tests set this before pumping
/// [DriverHomePage] and reset it in `tearDown` so the real HTTP call is
/// never invoked. Never set from production code.
@visibleForTesting
MintOperatorDriverSessionFn? debugMintOperatorDriverSessionOverride;

/// Resolves the mint function for a new [DriverSwitchMintController]
/// instance. Returns [debugMintOperatorDriverSessionOverride] when set and
/// [mintOperatorDriverSession] otherwise.
MintOperatorDriverSessionFn _resolveMintFnForController() {
  final override = debugMintOperatorDriverSessionOverride;
  if (override != null) return override;
  return mintOperatorDriverSession;
}

/// Outcome of a completed (settled) mint call. Public so tests can construct
/// success/failure fixtures directly without any private type.
class DriverSwitchMintOutcome {
  const DriverSwitchMintOutcome._({
    required this.isSuccess,
    this.minted,
    this.failureReason,
    this.httpStatus,
  });

  /// Success outcome carrying the raw server response.
  const DriverSwitchMintOutcome.success(OperatorMintedDriverSession minted)
    : this._(isSuccess: true, minted: minted);

  /// Failure outcome carrying a stable machine-readable reason token
  /// (`unauthorized`, `forbidden`, `driver_not_found`, `driver_inactive`,
  /// `invalid_body`, `mint_failed`, `network`, `timeout`, `invalid_response`,
  /// `scope_mismatch_driver`, `scope_mismatch_tenant`, `scope_mismatch_company`,
  /// `empty_token`, `invalid_expiry`, `expired_token`,
  /// `company_session_changed`, `scope_changed_during_mint`).
  const DriverSwitchMintOutcome.failure({
    required String reason,
    int? httpStatus,
  }) : this._(isSuccess: false, failureReason: reason, httpStatus: httpStatus);

  final bool isSuccess;
  final OperatorMintedDriverSession? minted;
  final String? failureReason;
  final int? httpStatus;

  bool get isFailure => !isSuccess;
}

/// Discriminated result returned by [DriverSwitchMintController.beginSwitch].
class DriverSwitchMintBeginResult {
  const DriverSwitchMintBeginResult({
    required this.capturedGeneration,
    required this.outcomeFuture,
  });

  /// The switch generation captured at request time. The caller passes this
  /// value back to [DriverSwitchMintController.resolveResponse] so a late
  /// response for a superseded generation can be dropped.
  final int capturedGeneration;

  /// Completes with the settled outcome of the mint call (success or a
  /// classified failure reason). Never throws.
  final Future<DriverSwitchMintOutcome> outcomeFuture;
}

/// Decision produced by [DriverSwitchMintController.resolveResponse] and
/// consumed by the widget layer. Discriminated union so the widget can
/// exhaustively `switch` on the outcome.
sealed class DriverSwitchMintDecision {
  const DriverSwitchMintDecision();
}

class DriverSwitchMintPublish extends DriverSwitchMintDecision {
  const DriverSwitchMintPublish({
    required this.minted,
    required this.requestedDriverProfile,
    required this.requestedTenantId,
    required this.requestedCompanyId,
  });

  final OperatorMintedDriverSession minted;
  final DriverProfile requestedDriverProfile;
  final String requestedTenantId;
  final String requestedCompanyId;
}

class DriverSwitchMintDropStale extends DriverSwitchMintDecision {
  const DriverSwitchMintDropStale();
}

class DriverSwitchMintFailed extends DriverSwitchMintDecision {
  const DriverSwitchMintFailed({required this.reason, this.httpStatus});
  final String reason;
  final int? httpStatus;
}

/// Reason that a route-exit request from business preview was refused.
enum BusinessPreviewExitBlockReason {
  liveRide,
  stopTeardown,
  directFinalize,
}

/// Discriminated decision produced by
/// [DriverSwitchMintController.resolveExitRequest].
sealed class BusinessPreviewExitDecision {
  const BusinessPreviewExitDecision();
}

class BusinessPreviewExitBlocked extends BusinessPreviewExitDecision {
  const BusinessPreviewExitBlocked({required this.reason});
  final BusinessPreviewExitBlockReason reason;
}

class BusinessPreviewExitAllowed extends BusinessPreviewExitDecision {
  const BusinessPreviewExitAllowed({
    required this.invalidatedPendingSwitch,
    required this.shouldClearOwnedSession,
  });
  final bool invalidatedPendingSwitch;
  final bool shouldClearOwnedSession;
}

/// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix)
///
/// State machine that owns the in-page driver-switch mint concurrency
/// invariants:
///
///   - Latest-wins response gating via a monotonic `_generation` counter.
///   - Strict scope + token + expiry validation via [validateMintedScope]
///     before signalling a publish decision.
///   - Idempotent exit-request handling that invalidates every in-flight
///     mint response so a late future cannot publish after the widget has
///     left the surface.
///
/// The controller does not touch [activeDriverSessionNotifier] or any
/// external state. It returns decisions; the widget layer applies the
/// side effects atomically (see `_atomicallyPublishBAsCurrent`).
class DriverSwitchMintController {
  DriverSwitchMintController({
    required this.mintFn,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final MintOperatorDriverSessionFn mintFn;
  final DateTime Function() _clock;

  int _generation = 0;
  int _pendingGeneration = 0;
  String? _pendingDriverId;
  DriverProfile? _pendingDriverProfile;
  ({String tenantId, String companyId})? _pendingScope;
  bool _isMinting = false;

  /// Monotonic counter incremented at every [beginSwitch] and at every
  /// exit-invalidation.
  int get generation => _generation;

  /// The generation of the currently in-flight switch, or 0 when idle.
  int get pendingGeneration => _pendingGeneration;

  /// The requested target driver id while a switch is in flight.
  String? get pendingDriverId => _pendingDriverId;

  /// True while a mint request is in flight and its response has not yet
  /// been consumed by [resolveResponse] or superseded by an exit.
  bool get isMinting => _isMinting;

  /// Begin a switch. Increments [_generation] and captures the new value as
  /// the pending generation. Returns the captured generation plus a future
  /// that resolves to a settled [DriverSwitchMintOutcome] (never throws).
  ///
  /// The caller MUST hand the captured generation back on [resolveResponse]
  /// so the latest-wins gate can drop stale responses.
  DriverSwitchMintBeginResult beginSwitch({
    required DriverProfile driverB,
    required String companySessionToken,
    required String bookingBaseUrl,
    required String tenantId,
    required String companyId,
  }) {
    _generation += 1;
    final my = _generation;
    _pendingGeneration = my;
    _pendingDriverId = driverB.id.trim();
    _pendingDriverProfile = driverB;
    _pendingScope = (tenantId: tenantId.trim(), companyId: companyId.trim());
    _isMinting = true;
    final future = _runMint(
      driverB: driverB,
      companySessionToken: companySessionToken,
      bookingBaseUrl: bookingBaseUrl,
      tenantId: tenantId,
      companyId: companyId,
    );
    return DriverSwitchMintBeginResult(
      capturedGeneration: my,
      outcomeFuture: future,
    );
  }

  Future<DriverSwitchMintOutcome> _runMint({
    required DriverProfile driverB,
    required String companySessionToken,
    required String bookingBaseUrl,
    required String tenantId,
    required String companyId,
  }) async {
    try {
      final minted = await mintFn(
        bookingBaseUrl: bookingBaseUrl,
        companySessionToken: companySessionToken,
        targetDriverId: driverB.id,
        tenantId: tenantId,
        companyId: companyId,
      );
      return DriverSwitchMintOutcome.success(minted);
    } on OperatorMintException catch (e) {
      return DriverSwitchMintOutcome.failure(
        reason: e.reason,
        httpStatus: e.httpStatus,
      );
    } catch (_) {
      return const DriverSwitchMintOutcome.failure(reason: 'network');
    }
  }

  /// Resolve a settled mint response with its captured generation.
  ///
  /// Order of gates:
  ///   1. Latest-wins generation check (drops stale responses without any
  ///      state mutation).
  ///   2. Failure passthrough (does clear pending state).
  ///   3. Strict scope + token + expiry validation via
  ///      [validateMintedScope] (converts a validation failure into a
  ///      [DriverSwitchMintFailed] result).
  ///   4. Publish decision carrying the requested driver profile so the
  ///      widget can build the [ActiveDriverSession] atomically without
  ///      re-reading intermediate widget state.
  DriverSwitchMintDecision resolveResponse({
    required int capturedGeneration,
    required DriverSwitchMintOutcome outcome,
  }) {
    if (capturedGeneration != _generation) {
      return const DriverSwitchMintDropStale();
    }
    void clearPending() {
      _pendingGeneration = 0;
      _pendingDriverId = null;
      _pendingDriverProfile = null;
      _pendingScope = null;
      _isMinting = false;
    }
    if (outcome.isFailure) {
      final reason = outcome.failureReason ?? 'network';
      clearPending();
      return DriverSwitchMintFailed(
        reason: reason,
        httpStatus: outcome.httpStatus,
      );
    }
    final minted = outcome.minted!;
    final requestedDriverId = _pendingDriverId!;
    final requestedScope = _pendingScope!;
    final profile = _pendingDriverProfile!;
    final validation = validateMintedScope(
      minted: minted,
      requestedDriverId: requestedDriverId,
      requestedTenantId: requestedScope.tenantId,
      requestedCompanyId: requestedScope.companyId,
      now: _clock(),
    );
    if (validation != null) {
      clearPending();
      return DriverSwitchMintFailed(reason: validation);
    }
    clearPending();
    return DriverSwitchMintPublish(
      minted: minted,
      requestedDriverProfile: profile,
      requestedTenantId: requestedScope.tenantId,
      requestedCompanyId: requestedScope.companyId,
    );
  }

  /// Route-exit request. Applies ride/teardown/finalize gates first, then —
  /// if the exit is allowed — invalidates every pending switch response by
  /// bumping [_generation] and clearing pending state. Returns a decision;
  /// the widget layer applies the side effects (owned-clear, `Navigator.pop`).
  BusinessPreviewExitDecision resolveExitRequest({
    required bool liveRideActive,
    required bool stopTeardownInProgress,
    required bool directStopFinalizePending,
    required bool ownsOperatorMintedSession,
  }) {
    if (liveRideActive) {
      return const BusinessPreviewExitBlocked(
        reason: BusinessPreviewExitBlockReason.liveRide,
      );
    }
    if (stopTeardownInProgress) {
      return const BusinessPreviewExitBlocked(
        reason: BusinessPreviewExitBlockReason.stopTeardown,
      );
    }
    if (directStopFinalizePending) {
      return const BusinessPreviewExitBlocked(
        reason: BusinessPreviewExitBlockReason.directFinalize,
      );
    }
    final hadPending = _isMinting || _pendingGeneration != 0;
    if (hadPending) {
      _generation += 1;
      _pendingGeneration = 0;
      _pendingDriverId = null;
      _pendingDriverProfile = null;
      _pendingScope = null;
      _isMinting = false;
    }
    return BusinessPreviewExitAllowed(
      invalidatedPendingSwitch: hadPending,
      shouldClearOwnedSession: ownsOperatorMintedSession,
    );
  }

  /// dispose-side helper. Idempotent. Invalidates pending switches without
  /// consulting ride/teardown/finalize gates (those are checked upstream).
  void invalidatePendingResponses() {
    if (_isMinting || _pendingGeneration != 0) {
      _generation += 1;
      _pendingGeneration = 0;
      _pendingDriverId = null;
      _pendingDriverProfile = null;
      _pendingScope = null;
      _isMinting = false;
    }
  }
}

/// Pure predicate that verifies a mint response's scope, token, and expiry
/// exactly. Public so it can be exercised by tests without instantiating a
/// controller.
///
/// Returns `null` when the response is safe to publish. Otherwise returns a
/// stable machine-readable failure reason:
///
///   - `scope_mismatch_driver`  — minted.driverId empty or != requested
///   - `scope_mismatch_tenant`  — minted.tenantId empty or != requested
///   - `scope_mismatch_company` — minted.companyId empty or != requested
///   - `empty_token`            — minted.driverSessionToken empty
///   - `invalid_expiry`         — minted expiry missing or unparseable
///   - `expired_token`          — minted expiry not strictly in the future
///
/// The requested identifiers are trimmed before comparison. Comparisons are
/// exact (no case folding). Empty minted tenant/company values are treated
/// as validation failures — the caller must NOT fall back to the requested
/// scope for publication.
String? validateMintedScope({
  required OperatorMintedDriverSession minted,
  required String requestedDriverId,
  required String requestedTenantId,
  required String requestedCompanyId,
  required DateTime now,
}) {
  final mintedDriver = minted.driverId.trim();
  final wantedDriver = requestedDriverId.trim();
  if (mintedDriver.isEmpty || mintedDriver != wantedDriver) {
    return 'scope_mismatch_driver';
  }
  final mintedTenant = minted.tenantId.trim();
  final wantedTenant = requestedTenantId.trim();
  if (mintedTenant.isEmpty || mintedTenant != wantedTenant) {
    return 'scope_mismatch_tenant';
  }
  final mintedCompany = minted.companyId.trim();
  final wantedCompany = requestedCompanyId.trim();
  if (mintedCompany.isEmpty || mintedCompany != wantedCompany) {
    return 'scope_mismatch_company';
  }
  final token = minted.driverSessionToken.trim();
  if (token.isEmpty) {
    return 'empty_token';
  }
  final expiryRaw = minted.driverSessionExpiresAtUtc.trim();
  if (expiryRaw.isEmpty) {
    return 'invalid_expiry';
  }
  final expiry = DateTime.tryParse(expiryRaw)?.toUtc();
  if (expiry == null) {
    return 'invalid_expiry';
  }
  final nowUtc = now.toUtc();
  if (expiry.isBefore(nowUtc) || expiry.isAtSameMomentAs(nowUtc)) {
    return 'expired_token';
  }
  return null;
}
