// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Field Failure Fix, Blocker Fix)
//
// Unit tests for [DriverSwitchMintController] and [validateMintedScope]
// declared in `lib/main_parts/driver_switch_mint_controller.dart`
// (`part of '../main.dart';`). The controller owns the in-page A → B
// driver-switch mint state machine — generation counter, latest-wins
// resolution, strict scope/token/expiry validation, and exit-request
// invalidation. Tests execute the same production logic used by
// `_DriverHomePageState._performInPageDriverSwitchMint`.
//
// Run:
//   flutter test test/main_parts/driver_switch_mint_controller_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/main.dart';

// -------------------------------------------------------------------------
// Fixtures
// -------------------------------------------------------------------------

const String _kBookingBaseUrl = 'https://fake.fluxidi.workers.dev';
const String _kCompanyToken = 'cst_test';
const String _kTenant = 'tenant_a';
const String _kCompany = 'company_a';
const String _kDriverA = 'driver_a';
const String _kDriverB = 'driver_b';
const String _kDriverC = 'driver_c';

DriverProfile _driverProfile({
  required String id,
  String fullName = 'Test Driver',
  String employeeNumber = 'E001',
  String phone = '+31000000000',
}) => DriverProfile(
      id: id,
      fullName: fullName,
      employeeNumber: employeeNumber,
      phone: phone,
      isActive: true,
    );

OperatorMintedDriverSession _minted({
  String driverId = _kDriverB,
  String tenantId = _kTenant,
  String companyId = _kCompany,
  String token = 'dst_op_BB',
  String expiresAt = '2099-01-01T00:00:00Z',
  int expiresIn = 3600,
  String driverName = 'B',
  String? assignedVehicleId = 'veh_B',
}) => OperatorMintedDriverSession(
      driverSessionToken: token,
      driverSessionExpiresAtUtc: expiresAt,
      expiresInSeconds: expiresIn,
      tenantId: tenantId,
      companyId: companyId,
      driverId: driverId,
      driverName: driverName,
      assignedVehicleId: assignedVehicleId,
    );

// -------------------------------------------------------------------------
// Stub mint seam. Test-controlled per-driver Completer so we can drive
// arbitrary A → B → C interleavings deterministically.
// -------------------------------------------------------------------------

class _MintStub {
  final Map<String, Completer<OperatorMintedDriverSession>> pending =
      <String, Completer<OperatorMintedDriverSession>>{};
  final List<String> beginOrder = <String>[];

  Future<OperatorMintedDriverSession> call({
    required String bookingBaseUrl,
    required String companySessionToken,
    required String targetDriverId,
    String? tenantId,
    String? companyId,
  }) {
    beginOrder.add(targetDriverId);
    final completer = pending.putIfAbsent(
      targetDriverId,
      () => Completer<OperatorMintedDriverSession>(),
    );
    return completer.future;
  }

  void completeWith(String driverId, OperatorMintedDriverSession value) {
    pending[driverId]!.complete(value);
  }

  void failWith(String driverId, Object error) {
    pending[driverId]!.completeError(error);
  }
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

void main() {
  group('validateMintedScope', () {
    final now = DateTime.utc(2027, 1, 1, 12, 0, 0);
    test('accepts an exact scope + valid token + future expiry', () {
      expect(
        validateMintedScope(
          minted: _minted(expiresAt: '2027-06-01T00:00:00Z'),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        isNull,
      );
    });

    test('rejects a mismatched driver id', () {
      expect(
        validateMintedScope(
          minted: _minted(driverId: _kDriverC),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('scope_mismatch_driver'),
      );
    });

    test('rejects an empty minted driver id', () {
      expect(
        validateMintedScope(
          minted: _minted(driverId: ''),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('scope_mismatch_driver'),
      );
    });

    test('rejects an empty minted tenant id (no fallback to requested)', () {
      expect(
        validateMintedScope(
          minted: _minted(tenantId: ''),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('scope_mismatch_tenant'),
      );
    });

    test('rejects an empty minted company id (no fallback to requested)', () {
      expect(
        validateMintedScope(
          minted: _minted(companyId: ''),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('scope_mismatch_company'),
      );
    });

    test('rejects a mismatched tenant id', () {
      expect(
        validateMintedScope(
          minted: _minted(tenantId: 'wrong_tenant'),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('scope_mismatch_tenant'),
      );
    });

    test('rejects a mismatched company id', () {
      expect(
        validateMintedScope(
          minted: _minted(companyId: 'wrong_company'),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('scope_mismatch_company'),
      );
    });

    test('rejects an empty driver bearer', () {
      expect(
        validateMintedScope(
          minted: _minted(token: ''),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('empty_token'),
      );
    });

    test('rejects an unparseable expiry string', () {
      expect(
        validateMintedScope(
          minted: _minted(expiresAt: 'not-a-date'),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('invalid_expiry'),
      );
    });

    test('rejects an empty expiry string', () {
      expect(
        validateMintedScope(
          minted: _minted(expiresAt: ''),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('invalid_expiry'),
      );
    });

    test('rejects a strictly-past expiry', () {
      expect(
        validateMintedScope(
          minted: _minted(expiresAt: '2020-01-01T00:00:00Z'),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('expired_token'),
      );
    });

    test('rejects an expiry equal to now (must be strictly after now)', () {
      expect(
        validateMintedScope(
          minted: _minted(expiresAt: now.toIso8601String()),
          requestedDriverId: _kDriverB,
          requestedTenantId: _kTenant,
          requestedCompanyId: _kCompany,
          now: now,
        ),
        equals('expired_token'),
      );
    });
  });

  group('DriverSwitchMintController — successful A → B publish', () {
    test(
      'increments generation on beginSwitch and returns a publish decision '
      'on successful, in-scope mint',
      () async {
        final stub = _MintStub();
        final controller = DriverSwitchMintController(
          mintFn: stub.call,
          clock: () => DateTime.utc(2027, 1, 1),
        );
        expect(controller.generation, 0);
        expect(controller.pendingGeneration, 0);
        expect(controller.isMinting, isFalse);
        final begin = controller.beginSwitch(
          driverB: _driverProfile(id: _kDriverB),
          companySessionToken: _kCompanyToken,
          bookingBaseUrl: _kBookingBaseUrl,
          tenantId: _kTenant,
          companyId: _kCompany,
        );
        expect(begin.capturedGeneration, 1);
        expect(controller.generation, 1);
        expect(controller.pendingGeneration, 1);
        expect(controller.pendingDriverId, _kDriverB);
        expect(controller.isMinting, isTrue);
        stub.completeWith(_kDriverB, _minted());
        final outcome = await begin.outcomeFuture;
        expect(outcome.isSuccess, isTrue);
        final decision = controller.resolveResponse(
          capturedGeneration: begin.capturedGeneration,
          outcome: outcome,
        );
        expect(decision, isA<DriverSwitchMintPublish>());
        expect(controller.isMinting, isFalse);
        expect(controller.pendingGeneration, 0);
        expect(controller.pendingDriverId, isNull);
      },
    );
  });

  group('DriverSwitchMintController — A remains paired while B pending', () {
    test('response for A generation is dropped after supersession by B', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final beginA = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverA),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      final beginB = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.completeWith(_kDriverA, _minted(driverId: _kDriverA));
      final outcomeA = await beginA.outcomeFuture;
      final decisionA = controller.resolveResponse(
        capturedGeneration: beginA.capturedGeneration,
        outcome: outcomeA,
      );
      expect(decisionA, isA<DriverSwitchMintDropStale>());
      expect(controller.pendingGeneration, beginB.capturedGeneration);
      expect(controller.pendingDriverId, _kDriverB);
      stub.completeWith(_kDriverB, _minted(driverId: _kDriverB));
      final outcomeB = await beginB.outcomeFuture;
      final decisionB = controller.resolveResponse(
        capturedGeneration: beginB.capturedGeneration,
        outcome: outcomeB,
      );
      expect(decisionB, isA<DriverSwitchMintPublish>());
    });
  });

  group('DriverSwitchMintController — A → B → C drops late B', () {
    test('B response arriving after C begin is dropped as stale', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final beginA = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverA),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      final beginB = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      final beginC = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverC),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.completeWith(_kDriverA, _minted(driverId: _kDriverA));
      stub.completeWith(_kDriverB, _minted(driverId: _kDriverB));
      final outcomeA = await beginA.outcomeFuture;
      final outcomeB = await beginB.outcomeFuture;
      final decisionA = controller.resolveResponse(
        capturedGeneration: beginA.capturedGeneration,
        outcome: outcomeA,
      );
      final decisionB = controller.resolveResponse(
        capturedGeneration: beginB.capturedGeneration,
        outcome: outcomeB,
      );
      expect(decisionA, isA<DriverSwitchMintDropStale>());
      expect(decisionB, isA<DriverSwitchMintDropStale>());
      expect(controller.pendingGeneration, beginC.capturedGeneration);
      stub.completeWith(_kDriverC, _minted(driverId: _kDriverC));
      final outcomeC = await beginC.outcomeFuture;
      final decisionC = controller.resolveResponse(
        capturedGeneration: beginC.capturedGeneration,
        outcome: outcomeC,
      );
      expect(decisionC, isA<DriverSwitchMintPublish>());
      final publish = decisionC as DriverSwitchMintPublish;
      expect(publish.minted.driverId, _kDriverC);
    });

    // FIELD-RELEASE-BLOCKER v6 — direct ordering proof.
    //
    // A late B response for ANY outcome type (success, failure, scope
    // mismatch, company-session mismatch) resolved through
    // `DriverSwitchMintController.resolveResponse` must be dropped by the
    // stale-generation gate BEFORE it can touch pending state. After each
    // resolution the controller's pending slot must still describe C:
    //   pendingGeneration == C.capturedGeneration
    //   pendingDriverId   == _kDriverC
    //   isMinting         == true
    void assertPendingStillC(
      DriverSwitchMintController controller,
      DriverSwitchMintBeginResult beginC,
    ) {
      expect(controller.pendingGeneration, beginC.capturedGeneration);
      expect(controller.pendingDriverId, _kDriverC);
      expect(controller.isMinting, isTrue);
      expect(controller.generation, beginC.capturedGeneration);
    }

    void arrange({
      required _MintStub stub,
      required DriverSwitchMintController controller,
      required void Function(DriverSwitchMintBeginResult beginB,
              DriverSwitchMintBeginResult beginC)
          finish,
    }) {
      final beginB = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      final beginC = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverC),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      finish(beginB, beginC);
    }

    test(
        'late B (SUCCESS outcome) is dropped stale before pending is cleared; '
        'C pending slot remains intact', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      late DriverSwitchMintBeginResult beginB;
      late DriverSwitchMintBeginResult beginC;
      arrange(
        stub: stub,
        controller: controller,
        finish: (b, c) {
          beginB = b;
          beginC = c;
        },
      );
      // Late B settles with a SUCCESS payload; C is still pending.
      stub.completeWith(_kDriverB, _minted(driverId: _kDriverB));
      final outcomeB = await beginB.outcomeFuture;
      final decisionB = controller.resolveResponse(
        capturedGeneration: beginB.capturedGeneration,
        outcome: outcomeB,
      );
      expect(decisionB, isA<DriverSwitchMintDropStale>());
      assertPendingStillC(controller, beginC);
    });

    test(
        'late B (FAILURE outcome — OperatorMintException) is dropped stale '
        'before failure handling; C pending slot remains intact', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      late DriverSwitchMintBeginResult beginB;
      late DriverSwitchMintBeginResult beginC;
      arrange(
        stub: stub,
        controller: controller,
        finish: (b, c) {
          beginB = b;
          beginC = c;
        },
      );
      stub.failWith(
        _kDriverB,
        const OperatorMintException(
          reason: 'unauthorized',
          httpStatus: 401,
        ),
      );
      final outcomeB = await beginB.outcomeFuture;
      final decisionB = controller.resolveResponse(
        capturedGeneration: beginB.capturedGeneration,
        outcome: outcomeB,
      );
      expect(decisionB, isA<DriverSwitchMintDropStale>());
      assertPendingStillC(controller, beginC);
    });

    test(
        'late B (SCOPE-MISMATCH outcome — minted driverId != requested) is '
        'dropped stale before validateMintedScope runs at the widget layer; '
        'C pending slot remains intact', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      late DriverSwitchMintBeginResult beginB;
      late DriverSwitchMintBeginResult beginC;
      arrange(
        stub: stub,
        controller: controller,
        finish: (b, c) {
          beginB = b;
          beginC = c;
        },
      );
      // The mint returns a driverId that does not match B's requested id —
      // this WOULD trigger a scope_mismatch failure at the widget layer.
      // The controller's staleness check runs first and returns
      // `DriverSwitchMintDropStale` before validation is even attempted.
      stub.completeWith(_kDriverB, _minted(driverId: 'wrong_driver'));
      final outcomeB = await beginB.outcomeFuture;
      final decisionB = controller.resolveResponse(
        capturedGeneration: beginB.capturedGeneration,
        outcome: outcomeB,
      );
      expect(decisionB, isA<DriverSwitchMintDropStale>());
      assertPendingStillC(controller, beginC);
    });

    test(
        'late B, invoked with a stale capturedGeneration (simulates late '
        'response after C also began) MUST be dropped stale before pending '
        'is cleared; C pending slot remains intact', () async {
      // Extra defence-in-depth: simulate the WIDGET calling `resolveResponse`
      // with an incorrectly-preserved generation counter. The controller
      // MUST still reject the response.
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      late DriverSwitchMintBeginResult beginB;
      late DriverSwitchMintBeginResult beginC;
      arrange(
        stub: stub,
        controller: controller,
        finish: (b, c) {
          beginB = b;
          beginC = c;
        },
      );
      stub.completeWith(_kDriverB, _minted(driverId: _kDriverB));
      final outcomeB = await beginB.outcomeFuture;
      final decisionB = controller.resolveResponse(
        capturedGeneration: beginB.capturedGeneration - 999999,
        outcome: outcomeB,
      );
      expect(decisionB, isA<DriverSwitchMintDropStale>());
      assertPendingStillC(controller, beginC);
    });
  });

  group('DriverSwitchMintController — failure retains A completely', () {
    test('OperatorMintException converts to a failure decision', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.failWith(
        _kDriverB,
        const OperatorMintException(reason: 'unauthorized', httpStatus: 401),
      );
      final outcome = await begin.outcomeFuture;
      expect(outcome.isFailure, isTrue);
      expect(outcome.failureReason, equals('unauthorized'));
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintFailed>());
      final failed = decision as DriverSwitchMintFailed;
      expect(failed.reason, equals('unauthorized'));
      expect(failed.httpStatus, equals(401));
      expect(controller.isMinting, isFalse);
      expect(controller.pendingGeneration, 0);
    });

    test('non-OperatorMintException maps to a `network` failure', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.failWith(_kDriverB, StateError('io'));
      final outcome = await begin.outcomeFuture;
      expect(outcome.isFailure, isTrue);
      expect(outcome.failureReason, equals('network'));
    });
  });

  group('DriverSwitchMintController — scope validation gates publish', () {
    test('mismatched minted driverId yields scope_mismatch_driver failure', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      // Server-side bug: mint responded with a different driver.
      stub.completeWith(_kDriverB, _minted(driverId: _kDriverC));
      final outcome = await begin.outcomeFuture;
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintFailed>());
      expect(
        (decision as DriverSwitchMintFailed).reason,
        equals('scope_mismatch_driver'),
      );
    });

    test('empty minted tenant yields scope_mismatch_tenant failure', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.completeWith(_kDriverB, _minted(tenantId: ''));
      final outcome = await begin.outcomeFuture;
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintFailed>());
      expect(
        (decision as DriverSwitchMintFailed).reason,
        equals('scope_mismatch_tenant'),
      );
    });

    test('empty minted bearer yields empty_token failure', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.completeWith(_kDriverB, _minted(token: ''));
      final outcome = await begin.outcomeFuture;
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintFailed>());
      expect(
        (decision as DriverSwitchMintFailed).reason,
        equals('empty_token'),
      );
    });

    test('expired minted expiry yields expired_token failure', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      stub.completeWith(_kDriverB, _minted(expiresAt: '2020-01-01T00:00:00Z'));
      final outcome = await begin.outcomeFuture;
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintFailed>());
      expect(
        (decision as DriverSwitchMintFailed).reason,
        equals('expired_token'),
      );
    });
  });

  group('DriverSwitchMintController — resolveExitRequest', () {
    test('blocks exit when a live ride is active', () {
      final controller = DriverSwitchMintController(mintFn: _MintStub().call);
      final decision = controller.resolveExitRequest(
        liveRideActive: true,
        stopTeardownInProgress: false,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: true,
      );
      expect(decision, isA<BusinessPreviewExitBlocked>());
      expect(
        (decision as BusinessPreviewExitBlocked).reason,
        equals(BusinessPreviewExitBlockReason.liveRide),
      );
    });

    test('blocks exit when a stop teardown is in progress', () {
      final controller = DriverSwitchMintController(mintFn: _MintStub().call);
      final decision = controller.resolveExitRequest(
        liveRideActive: false,
        stopTeardownInProgress: true,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: true,
      );
      expect(decision, isA<BusinessPreviewExitBlocked>());
      expect(
        (decision as BusinessPreviewExitBlocked).reason,
        equals(BusinessPreviewExitBlockReason.stopTeardown),
      );
    });

    test('blocks exit when a direct-trip finalize is pending', () {
      final controller = DriverSwitchMintController(mintFn: _MintStub().call);
      final decision = controller.resolveExitRequest(
        liveRideActive: false,
        stopTeardownInProgress: false,
        directStopFinalizePending: true,
        ownsOperatorMintedSession: true,
      );
      expect(decision, isA<BusinessPreviewExitBlocked>());
      expect(
        (decision as BusinessPreviewExitBlocked).reason,
        equals(BusinessPreviewExitBlockReason.directFinalize),
      );
    });

    test('idle: allows exit and does not touch generation when no pending', () {
      final controller = DriverSwitchMintController(mintFn: _MintStub().call);
      final beforeGen = controller.generation;
      final decision = controller.resolveExitRequest(
        liveRideActive: false,
        stopTeardownInProgress: false,
        directStopFinalizePending: false,
        ownsOperatorMintedSession: true,
      );
      expect(decision, isA<BusinessPreviewExitAllowed>());
      final allowed = decision as BusinessPreviewExitAllowed;
      expect(allowed.invalidatedPendingSwitch, isFalse);
      expect(allowed.shouldClearOwnedSession, isTrue);
      expect(controller.generation, beforeGen);
    });

    test(
      'pending: invalidates pending switch, transitions to idle, and allows exit',
      () async {
        final stub = _MintStub();
        final controller = DriverSwitchMintController(
          mintFn: stub.call,
          clock: () => DateTime.utc(2027, 1, 1),
        );
        final begin = controller.beginSwitch(
          driverB: _driverProfile(id: _kDriverB),
          companySessionToken: _kCompanyToken,
          bookingBaseUrl: _kBookingBaseUrl,
          tenantId: _kTenant,
          companyId: _kCompany,
        );
        final capturedGen = begin.capturedGeneration;
        expect(controller.isMinting, isTrue);
        final decision = controller.resolveExitRequest(
          liveRideActive: false,
          stopTeardownInProgress: false,
          directStopFinalizePending: false,
          ownsOperatorMintedSession: true,
        );
        expect(decision, isA<BusinessPreviewExitAllowed>());
        final allowed = decision as BusinessPreviewExitAllowed;
        expect(allowed.invalidatedPendingSwitch, isTrue);
        expect(allowed.shouldClearOwnedSession, isTrue);
        expect(controller.isMinting, isFalse);
        expect(controller.pendingGeneration, 0);
        // The pending mint completes AFTER exit. Its captured generation is
        // now stale.
        stub.completeWith(_kDriverB, _minted());
        final outcome = await begin.outcomeFuture;
        final laterDecision = controller.resolveResponse(
          capturedGeneration: capturedGen,
          outcome: outcome,
        );
        expect(laterDecision, isA<DriverSwitchMintDropStale>());
      },
    );

    test(
      'exit does NOT report shouldClearOwnedSession when caller has no ownership',
      () {
        final controller = DriverSwitchMintController(mintFn: _MintStub().call);
        final decision = controller.resolveExitRequest(
          liveRideActive: false,
          stopTeardownInProgress: false,
          directStopFinalizePending: false,
          ownsOperatorMintedSession: false,
        );
        expect(decision, isA<BusinessPreviewExitAllowed>());
        expect(
          (decision as BusinessPreviewExitAllowed).shouldClearOwnedSession,
          isFalse,
        );
      },
    );
  });

  group('DriverSwitchMintController — invalidatePendingResponses', () {
    test('drops a pending response and is idempotent', () async {
      final stub = _MintStub();
      final controller = DriverSwitchMintController(
        mintFn: stub.call,
        clock: () => DateTime.utc(2027, 1, 1),
      );
      final begin = controller.beginSwitch(
        driverB: _driverProfile(id: _kDriverB),
        companySessionToken: _kCompanyToken,
        bookingBaseUrl: _kBookingBaseUrl,
        tenantId: _kTenant,
        companyId: _kCompany,
      );
      controller.invalidatePendingResponses();
      controller.invalidatePendingResponses(); // Idempotent, no error.
      expect(controller.isMinting, isFalse);
      expect(controller.pendingGeneration, 0);
      stub.completeWith(_kDriverB, _minted());
      final outcome = await begin.outcomeFuture;
      final decision = controller.resolveResponse(
        capturedGeneration: begin.capturedGeneration,
        outcome: outcome,
      );
      expect(decision, isA<DriverSwitchMintDropStale>());
    });
  });
}
