// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix)
//
// Focused widget test that exercises the exact PopScope wiring used by
// `_DriverHomePageState.build()` in `lib/main_parts/driver_home_page_state.dart`.
// The DriverHomePage widget itself boots Mapbox, geolocator, and a
// number of native plugin channels that are not available in the
// flutter_test environment, so this test pumps a small `_PopScopeHarness`
// widget which:
//
//   * owns a REAL [DriverSwitchMintController] driven by an injected
//     mint stub (the same production controller class from
//     `lib/main_parts/driver_switch_mint_controller.dart`),
//   * declares three real bool flags (`_liveRideActive`,
//     `_stopTeardownInProgress`, `_directStopFinalizePending`) that
//     mirror the widget-scope semantics of `_DriverHomePageState`,
//   * embeds a real [PopScope] with the same
//     `canPop: !openedFromBusinessHome` and the same
//     `onPopInvokedWithResult` callback shape,
//   * invokes the exact production predicate
//     [DriverSwitchMintController.resolveExitRequest] from that callback,
//   * pops the enclosing route (or leaves it in place) using the same
//     decision.
//
// This proves the following invariants using the production controller,
// which is what the user requested ("Use the production controller /
// injected mint seam, not a separate mirror").
//
//   A. System back during a live ride, STOP teardown or direct-trip
//      finalize is BLOCKED — the harness route stays on top.
//   B. System back during an idle pending switch invalidates every
//      pending mint response, transitions the controller to idle, clears
//      the owned session and allows the pop.
//   C. A late B mint response arriving after the route has exited
//      cannot publish — [DriverSwitchMintController.resolveResponse]
//      returns [DriverSwitchMintDropStale] for the (now stale) captured
//      generation.
//
// The DriverHomePage-side wiring (`return PopScope(...)`,
// `canPop: !widget.openedFromBusinessHome`,
// `onPopInvokedWithResult: (didPop, _) { … }`,
// `_attemptBusinessPreviewRouteExit`) is exercised by the source-contract
// tests in `business_preview_operator_mint_hydration_test.dart`.
//
// Run:
//   flutter test test/main_parts/business_preview_pop_scope_widget_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/main.dart';

// -------------------------------------------------------------------------
// Stub mint seam.
// -------------------------------------------------------------------------

class _MintStub {
  final Completer<OperatorMintedDriverSession> next =
      Completer<OperatorMintedDriverSession>();
  bool called = false;

  Future<OperatorMintedDriverSession> call({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String targetDriverId,
    String? tenantId,
    String? companyId,
  }) {
    called = true;
    return next.future;
  }

  void completeWith(OperatorMintedDriverSession value) => next.complete(value);
}

OperatorMintedDriverSession _minted({
  String driverId = 'driver_b',
  String tenantId = 'tenant_a',
  String companyId = 'company_a',
}) => OperatorMintedDriverSession(
      driverSessionToken: 'dst_op_BB',
      driverSessionExpiresAtUtc: '2099-01-01T00:00:00Z',
      expiresInSeconds: 3600,
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
      driverName: 'B',
    );

DriverProfile _driverProfile({String id = 'driver_b'}) => DriverProfile(
      id: id,
      fullName: 'B',
      employeeNumber: 'E002',
      phone: '+3100',
      isActive: true,
    );

// -------------------------------------------------------------------------
// Harness widget.
// -------------------------------------------------------------------------

class _PopScopeHarness extends StatefulWidget {
  const _PopScopeHarness({
    required this.controller,
    required this.liveRideActive,
    required this.stopTeardownInProgress,
    required this.directStopFinalizePending,
    required this.ownsOperatorMintedSession,
    required this.openedFromBusinessHome,
    required this.onExitAllowedClear,
    required this.onExitBlocked,
  });

  final DriverSwitchMintController controller;
  final bool liveRideActive;
  final bool stopTeardownInProgress;
  final bool directStopFinalizePending;
  final bool ownsOperatorMintedSession;
  final bool openedFromBusinessHome;
  final void Function(bool shouldClear) onExitAllowedClear;
  final VoidCallback onExitBlocked;

  @override
  State<_PopScopeHarness> createState() => _PopScopeHarnessState();
}

class _PopScopeHarnessState extends State<_PopScopeHarness> {
  @override
  Widget build(BuildContext context) {
    // The same PopScope shape as `_DriverHomePageState.build()`.
    return PopScope(
      canPop: !widget.openedFromBusinessHome,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        if (!widget.openedFromBusinessHome) return;
        // Mirror `_attemptBusinessPreviewRouteExit(source: 'pop_scope_system_back')`.
        final decision = widget.controller.resolveExitRequest(
          liveRideActive: widget.liveRideActive,
          stopTeardownInProgress: widget.stopTeardownInProgress,
          directStopFinalizePending: widget.directStopFinalizePending,
          ownsOperatorMintedSession: widget.ownsOperatorMintedSession,
        );
        switch (decision) {
          case BusinessPreviewExitBlocked():
            widget.onExitBlocked();
            return;
          case BusinessPreviewExitAllowed(
            shouldClearOwnedSession: final shouldClear,
          ):
            widget.onExitAllowedClear(shouldClear);
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
            return;
        }
      },
      child: const Scaffold(
        body: Center(child: Text('DRIVER_HOME_HARNESS')),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Test scaffold. Pushes a first route ("root") and then pushes the
// harness on top of it, so `Navigator.pop()` from within the harness has
// somewhere to pop to.
// -------------------------------------------------------------------------

Future<void> _pumpHarness(
  WidgetTester tester, {
  required DriverSwitchMintController controller,
  required bool liveRideActive,
  required bool stopTeardownInProgress,
  required bool directStopFinalizePending,
  required bool ownsOperatorMintedSession,
  bool openedFromBusinessHome = true,
  required void Function(bool) onExitAllowedClear,
  required VoidCallback onExitBlocked,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (rootContext) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(rootContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PopScopeHarness(
                      controller: controller,
                      liveRideActive: liveRideActive,
                      stopTeardownInProgress: stopTeardownInProgress,
                      directStopFinalizePending: directStopFinalizePending,
                      ownsOperatorMintedSession: ownsOperatorMintedSession,
                      openedFromBusinessHome: openedFromBusinessHome,
                      onExitAllowedClear: onExitAllowedClear,
                      onExitBlocked: onExitBlocked,
                    ),
                  ),
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  expect(find.text('DRIVER_HOME_HARNESS'), findsOneWidget);
}

/// Simulates a system-back gesture on the current route. `Navigator.maybePop`
/// funnels the request through the route's PopScope callback exactly like
/// Android hardware back does.
Future<void> _pressSystemBack(WidgetTester tester) async {
  final NavigatorState nav = tester.state<NavigatorState>(
    find.byType(Navigator).last,
  );
  await nav.maybePop();
  await tester.pumpAndSettle();
}

// -------------------------------------------------------------------------
// Tests.
// -------------------------------------------------------------------------

void main() {
  testWidgets(
    'A: system back is blocked while a live ride is active',
    (tester) async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(mintFn: stub.call);
      var blockedCount = 0;
      var allowedCount = 0;
      await _pumpHarness(
        tester,
        controller: controller,
        liveRideActive: true,
        stopTeardownInProgress: false,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: true,
        onExitAllowedClear: (_) => allowedCount++,
        onExitBlocked: () => blockedCount++,
      );
      await _pressSystemBack(tester);
      expect(blockedCount, 1);
      expect(allowedCount, 0);
      expect(find.text('DRIVER_HOME_HARNESS'), findsOneWidget);
    },
  );

  testWidgets(
    'A: system back is blocked while a STOP teardown is in progress',
    (tester) async {
      final controller =
          DriverSwitchMintController(mintFn: _MintStub().call);
      var blockedCount = 0;
      await _pumpHarness(
        tester,
        controller: controller,
        liveRideActive: false,
        stopTeardownInProgress: true,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: true,
        onExitAllowedClear: (_) {},
        onExitBlocked: () => blockedCount++,
      );
      await _pressSystemBack(tester);
      expect(blockedCount, 1);
      expect(find.text('DRIVER_HOME_HARNESS'), findsOneWidget);
    },
  );

  testWidgets(
    'A: system back is blocked while a direct-trip finalize is pending',
    (tester) async {
      final controller =
          DriverSwitchMintController(mintFn: _MintStub().call);
      var blockedCount = 0;
      await _pumpHarness(
        tester,
        controller: controller,
        liveRideActive: false,
        stopTeardownInProgress: false,
        directStopFinalizePending: true,
        ownsOperatorMintedSession: true,
        onExitAllowedClear: (_) {},
        onExitBlocked: () => blockedCount++,
      );
      await _pressSystemBack(tester);
      expect(blockedCount, 1);
      expect(find.text('DRIVER_HOME_HARNESS'), findsOneWidget);
    },
  );

  testWidgets(
    'B: system back during an idle pending switch invalidates the '
    'generation, clears the owned A session and allows the pop',
    (tester) async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(mintFn: stub.call);
      // Begin a switch to B — controller is now `isMinting`.
      final begin = controller.beginSwitch(
        driverB: _driverProfile(),
        companySessionToken: 'cst',
        bookingBaseUrl: 'https://fake',
        tenantId: 'tenant_a',
        companyId: 'company_a',
      );
      expect(controller.isMinting, isTrue);
      var blockedCount = 0;
      var allowedShouldClear = <bool>[];
      await _pumpHarness(
        tester,
        controller: controller,
        liveRideActive: false,
        stopTeardownInProgress: false,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: true,
        onExitAllowedClear: allowedShouldClear.add,
        onExitBlocked: () => blockedCount++,
      );
      await _pressSystemBack(tester);
      expect(blockedCount, 0);
      expect(allowedShouldClear, <bool>[true]);
      expect(controller.isMinting, isFalse);
      expect(controller.pendingGeneration, 0);
      // Harness route was popped — the root route with 'OPEN' is now visible.
      expect(find.text('DRIVER_HOME_HARNESS'), findsNothing);
      expect(find.text('OPEN'), findsOneWidget);
      // C — late B response arriving after route exit is dropped by the
      // real production `resolveResponse` for that captured generation.
      stub.completeWith(_minted());
      final outcome = await begin.outcomeFuture;
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintDropStale>());
    },
  );

  testWidgets(
    'standalone driver mode (openedFromBusinessHome=false): PopScope uses '
    'default behaviour — system back pops without invoking the guard',
    (tester) async {
      final controller =
          DriverSwitchMintController(mintFn: _MintStub().call);
      var blockedCount = 0;
      var allowedCount = 0;
      await _pumpHarness(
        tester,
        controller: controller,
        liveRideActive: true, // Guard would have blocked in business preview.
        stopTeardownInProgress: false,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: false,
        openedFromBusinessHome: false,
        onExitAllowedClear: (_) => allowedCount++,
        onExitBlocked: () => blockedCount++,
      );
      await _pressSystemBack(tester);
      expect(blockedCount, 0);
      expect(allowedCount, 0);
      expect(find.text('DRIVER_HOME_HARNESS'), findsNothing);
    },
  );
}
