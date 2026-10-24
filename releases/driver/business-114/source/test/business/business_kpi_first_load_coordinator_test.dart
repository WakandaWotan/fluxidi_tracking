// BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1
//
// Pure-Dart coverage for the Business KPI first-load coordinator helpers:
// scope-ready gate, per-leg outcome classification, single bounded
// automatic-retry decision, and PII-free diagnostic formatter.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business/business_dashboard_kpi_loading.dart';

void main() {
  group('BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 scope-ready gate', () {
    // Test 1 — company scope initially absent → no incorrect request.
    test('1. nothing ready → gate is false', () {
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: null,
          sessionCompanyId: null,
          scopeTenantId: null,
          scopeCompanyId: null,
          hasAdminAuthShortcut: false,
        ),
        isFalse,
      );
    });

    test('1b. only scope fallback populated (fluxidi/fluxidi) with no session '
        '→ gate is false', () {
      // Simulates the pre-hydration state where `_activeBookingScopeQuery`
      // returns the default `kTenantId` fallback but no session/profile is
      // available yet. The coordinator must not fire a request.
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: '',
          sessionCompanyId: '',
          scopeTenantId: 'fluxidi',
          scopeCompanyId: 'fluxidi',
          hasAdminAuthShortcut: false,
        ),
        isFalse,
      );
    });

    // Test 2 — scope becomes ready → automatic first load.
    test('2. matching profile+session+scope → gate is true', () {
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: 'company-abc',
          sessionCompanyId: 'company-abc',
          scopeTenantId: 'company-abc',
          scopeCompanyId: 'company-abc',
          hasAdminAuthShortcut: false,
        ),
        isTrue,
      );
    });

    // Test 3 — valid company session is never paired with fallback fluxidi.
    test('3. session belongs to company-abc but scope is fluxidi fallback '
        '→ gate is false (never pair company-session bearer with fluxidi)', () {
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: 'company-abc',
          sessionCompanyId: 'company-abc',
          scopeTenantId: 'fluxidi',
          scopeCompanyId: 'fluxidi',
          hasAdminAuthShortcut: false,
        ),
        isFalse,
      );
    });

    test(
      '3b. profile/session mismatch → gate is false even with matching scope',
      () {
        expect(
          businessDashboardKpiScopeIsReady(
            profileCompanyId: 'company-abc',
            sessionCompanyId: 'company-xyz',
            scopeTenantId: 'company-abc',
            scopeCompanyId: 'company-abc',
            hasAdminAuthShortcut: false,
          ),
          isFalse,
        );
      },
    );

    test('3c. admin token bypass requires non-empty scope but skips session '
        'checks (dev/ops)', () {
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: null,
          sessionCompanyId: null,
          scopeTenantId: 'company-abc',
          scopeCompanyId: 'company-abc',
          hasAdminAuthShortcut: true,
        ),
        isTrue,
      );
      // Empty scope still fails even with admin shortcut.
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: null,
          sessionCompanyId: null,
          scopeTenantId: '',
          scopeCompanyId: '',
          hasAdminAuthShortcut: true,
        ),
        isFalse,
      );
    });

    test('3d. whitespace-only scope is treated as empty', () {
      expect(
        businessDashboardKpiScopeIsReady(
          profileCompanyId: 'company-abc',
          sessionCompanyId: 'company-abc',
          scopeTenantId: '   ',
          scopeCompanyId: 'company-abc',
          hasAdminAuthShortcut: false,
        ),
        isFalse,
      );
    });
  });

  group('BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 leg outcome classification', () {
    test('HTTP 200 with ok:true → success', () {
      expect(
        classifyBusinessKpiLegHttpOutcome(statusCode: 200, decodedOk: true),
        BusinessKpiLegOutcome.success,
      );
    });

    test('HTTP 200 with ok:false → invalidPayload (permanent)', () {
      final outcome = classifyBusinessKpiLegHttpOutcome(
        statusCode: 200,
        decodedOk: false,
      );
      expect(outcome, BusinessKpiLegOutcome.invalidPayload);
      expect(businessKpiLegOutcomeIsPermanentFailure(outcome), isTrue);
      expect(businessKpiLegOutcomeIsTransient(outcome), isFalse);
    });

    test('HTTP 400/401/403 → permanent (no auto-retry)', () {
      for (final status in const <int>[400, 401, 403]) {
        final outcome = classifyBusinessKpiLegHttpOutcome(
          statusCode: status,
          decodedOk: false,
        );
        expect(
          businessKpiLegOutcomeIsPermanentFailure(outcome),
          isTrue,
          reason: 'status=$status must classify as permanent',
        );
        expect(businessKpiLegOutcomeIsTransient(outcome), isFalse);
      }
    });

    test('HTTP 429 → transient', () {
      final outcome = classifyBusinessKpiLegHttpOutcome(
        statusCode: 429,
        decodedOk: false,
      );
      expect(outcome, BusinessKpiLegOutcome.http429);
      expect(businessKpiLegOutcomeIsTransient(outcome), isTrue);
      expect(businessKpiLegOutcomeIsPermanentFailure(outcome), isFalse);
    });

    test('HTTP 500..599 → transient', () {
      for (final status in const <int>[500, 502, 503, 504, 599]) {
        final outcome = classifyBusinessKpiLegHttpOutcome(
          statusCode: status,
          decodedOk: false,
        );
        expect(
          outcome,
          BusinessKpiLegOutcome.http5xx,
          reason: 'status=$status must classify as http5xx',
        );
        expect(businessKpiLegOutcomeIsTransient(outcome), isTrue);
      }
    });

    test('HTTP 301/302/418 → httpOther (permanent, not auto-retried)', () {
      for (final status in const <int>[301, 302, 418, 451]) {
        final outcome = classifyBusinessKpiLegHttpOutcome(
          statusCode: status,
          decodedOk: false,
        );
        expect(
          outcome,
          BusinessKpiLegOutcome.httpOther,
          reason: 'status=$status must classify as httpOther',
        );
        expect(businessKpiLegOutcomeIsPermanentFailure(outcome), isTrue);
      }
    });

    test('exception runtime type "TimeoutException" → timeout (transient)', () {
      final outcome = classifyBusinessKpiLegExceptionOutcome(
        errorRuntimeType: 'TimeoutException',
      );
      expect(outcome, BusinessKpiLegOutcome.timeout);
      expect(businessKpiLegOutcomeIsTransient(outcome), isTrue);
    });

    test('exception runtime type "SocketException" → network (transient)', () {
      final outcome = classifyBusinessKpiLegExceptionOutcome(
        errorRuntimeType: 'SocketException',
      );
      expect(outcome, BusinessKpiLegOutcome.network);
      expect(businessKpiLegOutcomeIsTransient(outcome), isTrue);
    });

    test('status labels are bounded and PII-free', () {
      // Every enum value must have a fixed bounded label, none containing
      // company/tenant IDs, URLs, tokens or freeform data.
      final labels = <String>{};
      for (final outcome in BusinessKpiLegOutcome.values) {
        final label = businessKpiLegOutcomeStatusLabel(outcome);
        expect(
          label,
          matches(RegExp(r'^[a-z0-9_]{1,32}$')),
          reason: 'label "$label" is not bounded PII-free lowercase',
        );
        labels.add(label);
      }
      // Distinct labels (no accidental collisions).
      expect(labels.length, BusinessKpiLegOutcome.values.length);
    });
  });

  group('BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 retry decision', () {
    // Test 5 — one leg timeout → exactly one automatic retry.
    test(
      '5. bookings timeout, trip success, attempt 1 → autoRetryTransient',
      () {
        expect(
          resolveBusinessKpiRetryDecision(
            bookingsOutcome: BusinessKpiLegOutcome.timeout,
            tripOutcome: BusinessKpiLegOutcome.success,
            attempt: 1,
          ),
          BusinessKpiRetryDecision.autoRetryTransient,
        );
      },
    );

    test(
      '5b. bookings success, trip timeout, attempt 1 → autoRetryTransient',
      () {
        expect(
          resolveBusinessKpiRetryDecision(
            bookingsOutcome: BusinessKpiLegOutcome.success,
            tripOutcome: BusinessKpiLegOutcome.timeout,
            attempt: 1,
          ),
          BusinessKpiRetryDecision.autoRetryTransient,
        );
      },
    );

    // Test 6 — HTTP 500 → exactly one automatic retry.
    test('6. bookings 5xx, trip success, attempt 1 → autoRetryTransient', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.http5xx,
          tripOutcome: BusinessKpiLegOutcome.success,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.autoRetryTransient,
      );
    });

    // Test 7 — HTTP 401/403 → no automatic retry.
    test('7. bookings 401, trip success → noRetryTerminalFailure', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.http401,
          tripOutcome: BusinessKpiLegOutcome.success,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.noRetryTerminalFailure,
      );
    });

    test('7b. bookings success, trip 403 → noRetryTerminalFailure', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.success,
          tripOutcome: BusinessKpiLegOutcome.http403,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.noRetryTerminalFailure,
      );
    });

    test('7c. invalidPayload never auto-retries', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.invalidPayload,
          tripOutcome: BusinessKpiLegOutcome.timeout,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.noRetryTerminalFailure,
      );
    });

    test('7d. HTTP 400 never auto-retries even with transient other leg', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.http400,
          tripOutcome: BusinessKpiLegOutcome.http5xx,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.noRetryTerminalFailure,
      );
    });

    // Test 8 — first attempt fails, second succeeds → success (no more retry).
    test('8. attempt 2 with both legs success → noRetryAllOk', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.success,
          tripOutcome: BusinessKpiLegOutcome.success,
          attempt: 2,
        ),
        BusinessKpiRetryDecision.noRetryAllOk,
      );
    });

    // Test 9 — both attempts fail → manual Retry appears (attempts exhausted).
    test('9. attempt 2 with transient failure → noRetryAttemptsExhausted', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.timeout,
          tripOutcome: BusinessKpiLegOutcome.http5xx,
          attempt: 2,
        ),
        BusinessKpiRetryDecision.noRetryAttemptsExhausted,
      );
    });

    test('all-success at attempt 1 → noRetryAllOk', () {
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.success,
          tripOutcome: BusinessKpiLegOutcome.success,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.noRetryAllOk,
      );
    });

    test('permanent + transient at attempt 1 → terminal (no retry)', () {
      // Mixed classification: if any leg is permanent, never auto-retry.
      expect(
        resolveBusinessKpiRetryDecision(
          bookingsOutcome: BusinessKpiLegOutcome.http403,
          tripOutcome: BusinessKpiLegOutcome.timeout,
          attempt: 1,
        ),
        BusinessKpiRetryDecision.noRetryTerminalFailure,
      );
    });

    test('auto-retry delay is bounded to the documented 400–800 ms window', () {
      expect(kBusinessKpiAutoRetryDelayMs, inInclusiveRange(400, 800));
    });

    test('total automatic attempts is exactly 2 (initial + one retry)', () {
      expect(kBusinessKpiMaxAutomaticAttempts, 2);
    });
  });

  group('BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 diagnostics', () {
    test('formatter emits bounded PII-free line', () {
      final line = formatBusinessKpiLoadDiagnostic(
        cycleGeneration: 7,
        reason: BusinessKpiCycleReason.autoRetry,
        leg: BusinessKpiLegLabel.trip,
        attempt: 2,
        status: 'success',
        elapsedMs: 345,
        scopeReady: true,
        authMode: 'company_session',
      );
      expect(
        line,
        '[BUSINESS_KPI_LOAD] cycle=7 reason=auto_retry leg=trip attempt=2 '
        'status=success elapsed_ms=345 scope_ready=true '
        'auth_mode=company_session',
      );
    });

    test('formatter clamps out-of-range integers', () {
      final line = formatBusinessKpiLoadDiagnostic(
        cycleGeneration: -3,
        reason: BusinessKpiCycleReason.init,
        leg: BusinessKpiLegLabel.combined,
        attempt: 0,
        status: 'success',
        elapsedMs: -1,
        scopeReady: false,
        authMode: 'none',
      );
      // Bounded: negative cycle/elapsed → 0, attempt < 1 → 1.
      expect(line, contains('cycle=0'));
      expect(line, contains('attempt=1'));
      expect(line, contains('elapsed_ms=0'));
      expect(line, contains('scope_ready=false'));
      expect(line, contains('auth_mode=none'));
    });

    test('reason tokens are the documented bounded set', () {
      expect(BusinessKpiCycleReason.init, 'init');
      expect(BusinessKpiCycleReason.scopeReady, 'scope_ready');
      expect(BusinessKpiCycleReason.autoRetry, 'auto_retry');
      expect(BusinessKpiCycleReason.manualRetry, 'manual_retry');
      expect(BusinessKpiCycleReason.manualRefresh, 'manual_refresh');
      expect(BusinessKpiCycleReason.resume, 'resume');
      expect(BusinessKpiCycleReason.routeReturn, 'route_return');
      expect(BusinessKpiCycleReason.scopeChangedRerun, 'scope_changed_rerun');
    });

    test('leg labels are the documented bounded set', () {
      expect(BusinessKpiLegLabel.bookings, 'bookings');
      expect(BusinessKpiLegLabel.bookingsFallback, 'bookings_fallback');
      expect(BusinessKpiLegLabel.trip, 'trip');
      expect(BusinessKpiLegLabel.combined, 'combined');
    });

    test('combined-status tokens are the documented bounded set', () {
      expect(BusinessKpiCombinedStatus.success, 'success');
      expect(
        BusinessKpiCombinedStatus.transientWillRetry,
        'transient_will_retry',
      );
      expect(BusinessKpiCombinedStatus.terminal, 'terminal');
      expect(BusinessKpiCombinedStatus.stale, 'stale');
      expect(
        BusinessKpiCombinedStatus.skippedScopeNotReady,
        'skipped_scope_not_ready',
      );
      expect(BusinessKpiCombinedStatus.coalesced, 'coalesced');
      expect(BusinessKpiCombinedStatus.skippedFresh, 'skipped_fresh');
      expect(BusinessKpiCombinedStatus.degraded, 'degraded');
    });

    test('auth-mode label maps to admin | company_session | none', () {
      expect(
        businessKpiAuthModeLabel(hasAdminToken: true, hasCompanySession: true),
        'admin',
      );
      expect(
        businessKpiAuthModeLabel(hasAdminToken: false, hasCompanySession: true),
        'company_session',
      );
      expect(
        businessKpiAuthModeLabel(
          hasAdminToken: false,
          hasCompanySession: false,
        ),
        'none',
      );
    });
  });

  group('BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 presentation invariants '
      '(regression fences)', () {
    // Test 12 — previous successful values remain during refresh.
    test('12. refreshing preserves the previous successful snapshot', () {
      final previous = BusinessDashboardKpiSnapshot(
        tenantId: 't1',
        companyId: 'c1',
        openBookingsCount: 3,
        completedRidesCount: 137,
        unpaidCompletedRidesCount: 5,
        monthlyIncomeCents: 120239,
        currency: 'EUR',
        responseGeneration: 2,
      );
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: previous,
        requestInFlight: true,
        lastRequestFailed: false,
      );
      expect(view.phase, BusinessDashboardKpiPhase.refreshing);
      expect(view.snapshot, same(previous));
      expect(view.showRefreshIndicator, isTrue);
      expect(view.showRetry, isFalse);
    });

    // Test 13 — zero values are accepted as valid.
    test('13. valid successful response with zero totals is authoritative', () {
      final zeroSnapshot = BusinessDashboardKpiSnapshot(
        tenantId: 't1',
        companyId: 'c1',
        openBookingsCount: 0,
        completedRidesCount: 0,
        unpaidCompletedRidesCount: 0,
        monthlyIncomeCents: 0,
        currency: 'EUR',
        responseGeneration: 4,
      );
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: zeroSnapshot,
        requestInFlight: false,
        lastRequestFailed: false,
      );
      expect(view.phase, BusinessDashboardKpiPhase.ready);
      expect(view.hasAuthoritativeValues, isTrue);
      expect(view.snapshot!.openBookingsCount, 0);
      expect(view.snapshot!.completedRidesCount, 0);
      expect(view.snapshot!.unpaidCompletedRidesCount, 0);
      expect(view.snapshot!.monthlyIncomeCents, 0);
      // Zero is rendered as the string "0", never as "—".
      expect(
        businessDashboardKpiCountText(
          snapshot: view.snapshot,
          select: (s) => s.openBookingsCount,
        ),
        '0',
      );
    });

    // Test 14 — partial result is not presented as complete.
    test('14. partial-leg result never becomes an authoritative snapshot', () {
      // The completeness gate requires both legs — a partial response
      // must not construct a snapshot.
      expect(
        businessDashboardKpiResponseIsComplete(
          bookingsOk: true,
          tripKpisOk: false,
        ),
        isFalse,
      );
      expect(
        businessDashboardKpiResponseIsComplete(
          bookingsOk: false,
          tripKpisOk: true,
        ),
        isFalse,
      );
    });

    // Test 15 — all four values apply atomically.
    test('15. one generation = one atomic snapshot with all four fields', () {
      final snapshot = BusinessDashboardKpiSnapshot(
        tenantId: 't1',
        companyId: 'c1',
        openBookingsCount: 1,
        completedRidesCount: 2,
        unpaidCompletedRidesCount: 3,
        monthlyIncomeCents: 456,
        currency: 'EUR',
        responseGeneration: 9,
      );
      expect(snapshot.openBookingsCount, 1);
      expect(snapshot.completedRidesCount, 2);
      expect(snapshot.unpaidCompletedRidesCount, 3);
      expect(snapshot.monthlyIncomeCents, 456);
      expect(snapshot.responseGeneration, 9);
    });

    // Test 16 — cache remains scope-safe.
    test('16. cache never returns a snapshot for another scope', () {
      final cache = BusinessDashboardKpiCache();
      cache.put(
        BusinessDashboardKpiSnapshot(
          tenantId: 't1',
          companyId: 'c1',
          openBookingsCount: 99,
          completedRidesCount: 0,
          unpaidCompletedRidesCount: 0,
          monthlyIncomeCents: 0,
          currency: 'EUR',
          responseGeneration: 1,
        ),
      );
      expect(cache.get(tenantId: 't1', companyId: 'c2'), isNull);
      expect(cache.get(tenantId: 't9', companyId: 'c1'), isNull);
      expect(cache.get(tenantId: 't1', companyId: 'c1')!.openBookingsCount, 99);
    });

    // Test 10 — stale-generation rejection contract.
    test('10. stale generation response is discarded (no apply)', () {
      expect(
        businessDashboardKpiMayApplyResponse(
          requestGeneration: 1,
          currentGeneration: 2,
          requestTenantId: 't1',
          requestCompanyId: 'c1',
          activeTenantId: 't1',
          activeCompanyId: 'c1',
        ),
        isFalse,
      );
    });
  });
}
