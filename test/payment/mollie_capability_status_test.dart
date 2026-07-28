// MOLLIE-ONBOARDING-STATUS-P1 — the three status models are independent:
// account connection, online payment methods, in-person terminals. Online
// payment methods are resolved primarily from Mollie's own authoritative
// `canReceivePayments` signal, never from a guess, and a failed lookup is a
// distinct state that must never be confused with a genuinely bad status.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/mollie_capability_status.dart';

void main() {
  group('MollieAccountConnection', () {
    test('connected + live -> connectedLive (never activation pending)', () {
      expect(
        resolveMollieAccountConnection(
          connected: true,
          statusCode: 'connected',
          mollieMode: 'live',
        ),
        MollieAccountConnection.connectedLive,
      );
    });

    test('connected + test -> connectedTest', () {
      expect(
        resolveMollieAccountConnection(
          connected: true,
          statusCode: 'connected',
          mollieMode: 'test',
        ),
        MollieAccountConnection.connectedTest,
      );
    });

    test('not connected -> disconnected', () {
      expect(
        resolveMollieAccountConnection(connected: false, statusCode: 'disconnected'),
        MollieAccountConnection.disconnected,
      );
    });

    test('failed/auth_required/scope_missing -> reconnectRequired', () {
      for (final s in ['failed', 'auth_required', 'terminals_scope_missing']) {
        expect(
          resolveMollieAccountConnection(connected: true, statusCode: s, mollieMode: 'live'),
          MollieAccountConnection.reconnectRequired,
          reason: s,
        );
      }
    });

    test('mollieAccountIsConnected helper', () {
      expect(mollieAccountIsConnected(MollieAccountConnection.connectedLive), isTrue);
      expect(mollieAccountIsConnected(MollieAccountConnection.connectedTest), isTrue);
      expect(mollieAccountIsConnected(MollieAccountConnection.disconnected), isFalse);
      expect(mollieAccountIsConnected(MollieAccountConnection.reconnectRequired), isFalse);
    });
  });

  group('OnlinePaymentMethodsStatus — canReceivePayments is authoritative', () {
    // MOLLIE-ONBOARDING-STATUS-P1 required scenario: connected LIVE + active
    // method -> Complete.
    test('connected LIVE + canReceivePayments true -> active (Complete)', () {
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          onboardingStatus: 'completed',
          canReceivePayments: true,
        ),
        OnlinePaymentMethodsStatus.active,
      );
    });

    test('canReceivePayments true wins even if onboardingStatus text is stale/odd', () {
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          onboardingStatus: 'unexpected_value',
          canReceivePayments: true,
        ),
        OnlinePaymentMethodsStatus.active,
      );
    });

    // MOLLIE-ONBOARDING-STATUS-P1 required scenario: connected LIVE + no
    // supported active methods -> Action required.
    test(
      'connected LIVE + canReceivePayments false + onboarding completed -> actionRequired',
      () {
        expect(
          resolveOnlinePaymentMethods(
            connected: true,
            onboardingStatus: 'completed',
            canReceivePayments: false,
          ),
          OnlinePaymentMethodsStatus.actionRequired,
        );
      },
    );

    // MOLLIE-ONBOARDING-STATUS-P1 required scenario: genuinely pending
    // verification (Mollie in-review) -> Activation pending.
    test(
      'connected + canReceivePayments false + onboarding in-review -> activationPending',
      () {
        for (final s in ['in-review', 'in_review', 'inreview']) {
          expect(
            resolveOnlinePaymentMethods(
              connected: true,
              onboardingStatus: s,
              canReceivePayments: false,
            ),
            OnlinePaymentMethodsStatus.activationPending,
            reason: s,
          );
        }
      },
    );

    // MOLLIE-ONBOARDING-STATUS-P1 required scenario: needs-data is merchant
    // action, NOT Activation pending.
    test(
      'connected + canReceivePayments false + onboarding needs-data -> actionRequired',
      () {
        for (final s in ['needs-data', 'needs_data', 'needsdata']) {
          expect(
            resolveOnlinePaymentMethods(
              connected: true,
              onboardingStatus: s,
              canReceivePayments: false,
            ),
            OnlinePaymentMethodsStatus.actionRequired,
            reason: s,
          );
        }
      },
    );

    test(
      'connected + canReceivePayments false + unknown onboarding text -> actionRequired (not pending)',
      () {
        expect(
          resolveOnlinePaymentMethods(
            connected: true,
            onboardingStatus: null,
            canReceivePayments: false,
          ),
          OnlinePaymentMethodsStatus.actionRequired,
        );
      },
    );

    // MOLLIE-ONBOARDING-STATUS-P1 required scenario: disconnected -> Not
    // connected (online-methods bucket mirrors this with noneActive; the
    // account-level badge is the authoritative "Not connected" label).
    test('disconnected -> noneActive regardless of other signals', () {
      expect(
        resolveOnlinePaymentMethods(
          connected: false,
          onboardingStatus: 'completed',
          canReceivePayments: true,
        ),
        OnlinePaymentMethodsStatus.noneActive,
      );
    });

    // MOLLIE-ONBOARDING-STATUS-P1 required scenario: refresh/API lookup
    // failure is its own truthful state, never silently mapped onto a good
    // or bad status.
    test('lookupFailed short-circuits everything else', () {
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          onboardingStatus: 'completed',
          canReceivePayments: true,
          lookupFailed: true,
        ),
        OnlinePaymentMethodsStatus.lookupFailed,
      );
    });

    // MOLLIE-ONBOARDING-READ-SCOPE-P0-1
    test(
      'permission missing + known canReceivePayments true -> active (not activationPending)',
      () {
        expect(
          resolveOnlinePaymentMethods(
            connected: true,
            onboardingStatus: null,
            canReceivePayments: true,
            statusCheckPermissionMissing: true,
          ),
          OnlinePaymentMethodsStatus.active,
        );
      },
    );

    test(
      'permission missing without canReceivePayments -> statusCheckPermissionMissing (not activationPending)',
      () {
        expect(
          resolveOnlinePaymentMethods(
            connected: true,
            onboardingStatus: 'in-review',
            canReceivePayments: null,
            statusCheckPermissionMissing: true,
          ),
          OnlinePaymentMethodsStatus.statusCheckPermissionMissing,
        );
        expect(
          resolveOnlinePaymentMethods(
            connected: true,
            onboardingStatus: null,
            canReceivePayments: false,
            statusCheckPermissionMissing: true,
          ),
          OnlinePaymentMethodsStatus.statusCheckPermissionMissing,
        );
      },
    );
  });

  group('OnlinePaymentMethodsStatus — legacy fallback (canReceivePayments unknown)', () {
    test('connected + onboarding not complete, no canReceivePayments -> activationPending', () {
      expect(
        resolveOnlinePaymentMethods(connected: true, onboardingStatus: 'in_review'),
        OnlinePaymentMethodsStatus.activationPending,
      );
      expect(
        resolveOnlinePaymentMethods(connected: true, onboardingStatus: null),
        OnlinePaymentMethodsStatus.activationPending,
      );
    });

    test('connected + onboarding completed, no canReceivePayments -> active', () {
      for (final o in ['completed', 'complete', 'active', 'live']) {
        expect(
          resolveOnlinePaymentMethods(connected: true, onboardingStatus: o),
          OnlinePaymentMethodsStatus.active,
          reason: o,
        );
      }
    });

    test('explicit method counts drive partial/actionRequired/active', () {
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          activeMethodCount: 0,
          totalMethodCount: 5,
        ),
        OnlinePaymentMethodsStatus.actionRequired,
      );
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          onboardingStatus: 'in-review',
          activeMethodCount: 0,
          totalMethodCount: 5,
        ),
        OnlinePaymentMethodsStatus.activationPending,
      );
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          activeMethodCount: 2,
          totalMethodCount: 5,
        ),
        OnlinePaymentMethodsStatus.partiallyActive,
      );
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          activeMethodCount: 5,
          totalMethodCount: 5,
        ),
        OnlinePaymentMethodsStatus.active,
      );
    });

    test('canReceivePayments (when present) takes priority over explicit counts', () {
      expect(
        resolveOnlinePaymentMethods(
          connected: true,
          canReceivePayments: true,
          activeMethodCount: 0,
          totalMethodCount: 5,
        ),
        OnlinePaymentMethodsStatus.active,
      );
    });
  });

  group('InPersonTerminalStatus (snapshot only)', () {
    final now = DateTime.utc(2026, 7, 19, 12);
    final fresh = now.subtract(const Duration(minutes: 5));
    final old = now.subtract(const Duration(days: 3));

    test('one active terminal -> activeTerminal', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 1,
          activeTerminalCount: 1,
          syncedAt: fresh,
          now: now,
        ),
        InPersonTerminalStatus.activeTerminal,
      );
    });

    test('no snapshot / not synced -> noTerminal', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'not_synced',
          terminalCount: 0,
          activeTerminalCount: 0,
        ),
        InPersonTerminalStatus.noTerminal,
      );
    });

    test('synced but zero terminals -> noTerminal', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 0,
          activeTerminalCount: 0,
          syncedAt: fresh,
          now: now,
        ),
        InPersonTerminalStatus.noTerminal,
      );
    });

    test('synced, terminals present but none active -> connectedNoActiveTerminal', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 2,
          activeTerminalCount: 0,
          syncedAt: fresh,
          now: now,
        ),
        InPersonTerminalStatus.connectedNoActiveTerminal,
      );
    });

    test('multiple active without default -> multipleTerminalsNeedDefault', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 3,
          activeTerminalCount: 2,
          hasDefault: false,
          syncedAt: fresh,
          now: now,
        ),
        InPersonTerminalStatus.multipleTerminalsNeedDefault,
      );
    });

    test('multiple active WITH default -> activeTerminal', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 3,
          activeTerminalCount: 2,
          hasDefault: true,
          syncedAt: fresh,
          now: now,
        ),
        InPersonTerminalStatus.activeTerminal,
      );
    });

    test('stale snapshot -> snapshotStale (never silently active)', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 1,
          activeTerminalCount: 1,
          syncedAt: old,
          now: now,
        ),
        InPersonTerminalStatus.snapshotStale,
      );
    });

    test('fetch_failed / scope_missing / errorFlag -> error', () {
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'fetch_failed',
          terminalCount: 0,
          activeTerminalCount: 0,
        ),
        InPersonTerminalStatus.error,
      );
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'terminals_scope_missing',
          terminalCount: 0,
          activeTerminalCount: 0,
        ),
        InPersonTerminalStatus.error,
      );
      expect(
        resolveInPersonTerminalStatus(
          snapshotStatus: 'synced',
          terminalCount: 1,
          activeTerminalCount: 1,
          errorFlag: true,
        ),
        InPersonTerminalStatus.error,
      );
    });
  });

  group('independence rules', () {
    test('connected LIVE account is never activation_pending at the account level', () {
      final account = resolveMollieAccountConnection(
        connected: true,
        statusCode: 'connected',
        mollieMode: 'live',
      );
      expect(account, MollieAccountConnection.connectedLive);
      // activation pending is an online-method concept only:
      expect(
        OnlinePaymentMethodsStatus.values.contains(OnlinePaymentMethodsStatus.activationPending),
        isTrue,
      );
    });

    test('terminal availability is not blocked by online-method status', () {
      // A live active terminal is available even if online methods are pending.
      final terminal = resolveInPersonTerminalStatus(
        snapshotStatus: 'synced',
        terminalCount: 1,
        activeTerminalCount: 1,
      );
      expect(inPersonTerminalPaymentAvailable(terminal), isTrue);
      final online = resolveOnlinePaymentMethods(
        connected: true,
        onboardingStatus: 'in_review',
        canReceivePayments: false,
      );
      expect(online, OnlinePaymentMethodsStatus.activationPending);
    });

    test('pending verification and no-active-methods never collapse into one bucket', () {
      final pending = resolveOnlinePaymentMethods(
        connected: true,
        onboardingStatus: 'in-review',
        canReceivePayments: false,
      );
      final actionRequired = resolveOnlinePaymentMethods(
        connected: true,
        onboardingStatus: 'completed',
        canReceivePayments: false,
      );
      expect(pending, OnlinePaymentMethodsStatus.activationPending);
      expect(actionRequired, OnlinePaymentMethodsStatus.actionRequired);
      expect(pending, isNot(equals(actionRequired)));
    });
  });
}
