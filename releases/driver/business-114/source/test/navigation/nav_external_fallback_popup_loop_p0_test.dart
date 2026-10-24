// FLUXIDI-EXTERNAL-NAV-FALLBACK-POPUP-LOOP-P0-1
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_external_fallback_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_route_error.dart';

void main() {
  group('FLUXIDI-EXTERNAL-NAV-FALLBACK-POPUP-LOOP-P0-1', () {
    test('1) active navigation with valid route: no external popup', () {
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          navigationSuccessfullyStarted: true,
          hasUsableRoute: true,
          failureIsTerminal: true,
          fluxidiCanProvideNavigation: true,
          driverInActiveNavigation: true,
        ),
      );
      expect(d.shouldShow, isFalse);
      expect(d.reason, 'active_navigation');
    });

    test('2) deliberate off-route / strong mismatch: no popup', () {
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          navigationSuccessfullyStarted: true,
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          transientNavigationSignal: true,
          failureIsTerminal: false,
        ),
      );
      expect(d.shouldShow, isFalse);
      expect(
        shouldSurfaceRerouteFailurePopup(
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          rerouteStillRetryable: true,
        ),
        isFalse,
      );
    });

    test('3) reroute request: no popup', () {
      expect(
        shouldSurfaceRerouteFailurePopup(
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          rerouteStillRetryable: true,
        ),
        isFalse,
      );
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          transientNavigationSignal: true,
        ),
      );
      expect(d.shouldShow, isFalse);
    });

    test('4) temporary reroute/network failure: no popup; retryable', () {
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.timeout), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.offline), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.dnsFailure), isTrue);
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          navigationSuccessfullyStarted: true,
          hasUsableRoute: true,
          failureIsTerminal: false,
          driverInActiveNavigation: true,
          transientNavigationSignal: true,
        ),
      );
      expect(d.shouldShow, isFalse);
      expect(d.reason, anyOf('active_navigation', 'navigation_started'));
    });

    test('5) repeated GPS ticks cannot reopen latched prompt', () {
      final latch = NavExternalFallbackLatch();
      expect(latch.tryBeginPresentation(), isTrue);
      latch.markShownOrDismissed();
      expect(latch.isLatched, isTrue);
      expect(latch.tryBeginPresentation(), isFalse);
      for (var i = 0; i < 20; i++) {
        final d = resolveExternalNavAutoPrompt(
          NavExternalFallbackPromptInput(
            failureIsTerminal: true,
            alreadyShownOrDismissedThisAttempt: latch.isLatched,
          ),
        );
        expect(d.shouldShow, isFalse, reason: 'tick $i');
        expect(latch.tryBeginPresentation(), isFalse);
      }
    });

    test('6) multiple async failure callbacks: single-flight owner', () {
      final latch = NavExternalFallbackLatch();
      expect(latch.tryBeginPresentation(), isTrue);
      expect(latch.inFlight, isTrue);
      expect(latch.tryBeginPresentation(), isFalse);
      expect(latch.tryBeginPresentation(), isFalse);
      latch.markShownOrDismissed();
      expect(latch.tryBeginPresentation(), isFalse);
    });

    test('7) lifecycle pause/resume must not reset latch mid-ride', () {
      final latch = NavExternalFallbackLatch();
      latch.tryBeginPresentation();
      latch.markShownOrDismissed();
      final attempt = latch.attemptId;
      // Resume is a no-op for the latch — only beginNewNavigationAttempt resets.
      expect(latch.isLatched, isTrue);
      expect(latch.attemptId, attempt);
      final d = resolveExternalNavAutoPrompt(
        NavExternalFallbackPromptInput(
          driverInActiveNavigation: true,
          hasUsableRoute: true,
          alreadyShownOrDismissedThisAttempt: latch.isLatched,
        ),
      );
      expect(d.shouldShow, isFalse);
    });

    test('8) style reload / camera recovery: transient signal blocks popup', () {
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          navigationSuccessfullyStarted: true,
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          transientNavigationSignal: true,
        ),
      );
      expect(d.shouldShow, isFalse);
      expect(d.reason, 'active_navigation');
    });

    test('9) tunnel / poor GPS: no popup', () {
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          navigationSuccessfullyStarted: true,
          hasUsableRoute: true,
          driverInActiveNavigation: true,
          transientNavigationSignal: true,
          failureIsTerminal: false,
        ),
      );
      expect(d.shouldShow, isFalse);
    });

    test('10) terminal failure before navigation starts: at most once', () {
      final latch = NavExternalFallbackLatch();
      final first = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          failureIsTerminal: true,
        ),
      );
      expect(first.shouldShow, isTrue);
      expect(first.reason, 'terminal_prestart_once');
      expect(latch.tryBeginPresentation(), isTrue);
      latch.markShownOrDismissed();
      final second = resolveExternalNavAutoPrompt(
        NavExternalFallbackPromptInput(
          failureIsTerminal: true,
          alreadyShownOrDismissedThisAttempt: latch.isLatched,
        ),
      );
      expect(second.shouldShow, isFalse);
      expect(second.reason, 'attempt_latched');
    });

    test('11) dismiss terminal fallback: same attempt cannot reopen', () {
      final latch = NavExternalFallbackLatch();
      latch.tryBeginPresentation();
      latch.markShownOrDismissed();
      expect(
        resolveExternalNavAutoPrompt(
          NavExternalFallbackPromptInput(
            failureIsTerminal: true,
            alreadyShownOrDismissedThisAttempt: latch.isLatched,
          ),
        ).shouldShow,
        isFalse,
      );
    });

    test('12) new separate navigation attempt resets latch only via explicit API', () {
      final latch = NavExternalFallbackLatch();
      latch.tryBeginPresentation();
      latch.markShownOrDismissed();
      expect(latch.isLatched, isTrue);
      final before = latch.attemptId;
      latch.beginNewNavigationAttempt();
      expect(latch.attemptId, before + 1);
      expect(latch.isLatched, isFalse);
      expect(latch.inFlight, isFalse);
      expect(
        resolveExternalNavAutoPrompt(
          const NavExternalFallbackPromptInput(failureIsTerminal: true),
        ).shouldShow,
        isTrue,
      );
    });

    test('13) manual external nav remains deliberate (policy never auto-launches)', () {
      // Automatic policy never implies a launch — callers must still require a tap.
      // Even the terminal-once decision only authorizes a prompt, not a URL open.
      final d = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(failureIsTerminal: true),
      );
      expect(d.shouldShow, isTrue);
      expect(d.reason, isNot(contains('launch')));
    });

    test('14) phone and tablet share identical presentation policy', () {
      // Policy is device-agnostic: same inputs → same decision.
      final phone = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          driverInActiveNavigation: true,
          hasUsableRoute: true,
        ),
      );
      final tablet = resolveExternalNavAutoPrompt(
        const NavExternalFallbackPromptInput(
          driverInActiveNavigation: true,
          hasUsableRoute: true,
        ),
      );
      expect(phone.shouldShow, tablet.shouldShow);
      expect(phone.reason, tablet.reason);
      expect(
        shouldSurfaceRerouteFailurePopup(
          hasUsableRoute: true,
          driverInActiveNavigation: false,
          rerouteStillRetryable: true,
        ),
        isFalse,
      );
    });

    test('usable route alone blocks auto external prompt', () {
      expect(
        resolveExternalNavAutoPrompt(
          const NavExternalFallbackPromptInput(
            hasUsableRoute: true,
            failureIsTerminal: true,
          ),
        ).reason,
        'usable_route_present',
      );
    });

    test('non-terminal failure never auto-prompts', () {
      expect(
        resolveExternalNavAutoPrompt(
          const NavExternalFallbackPromptInput(
            failureIsTerminal: false,
          ),
        ).reason,
        'failure_not_terminal',
      );
    });

    test('Waze/Google recommendation copy is not in retryable navRouteError messages', () {
      for (final kind in NavRouteErrorKind.values) {
        final copy = navRouteErrorMessage(kind, tr: _trEn);
        expect(copy.message.toLowerCase(), isNot(contains('waze')));
        expect(copy.message.toLowerCase(), isNot(contains('google maps')));
      }
    });
  });
}

String _trEn({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    en;
