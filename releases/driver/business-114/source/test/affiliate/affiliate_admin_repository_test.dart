import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_models.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_admin_repository.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_repository.dart';
import 'package:fluxidi_tracking/affiliate/affiliate_form_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'affiliate_fixture.dart';

http.Response reply(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(jsonEncode(data), status, headers: affiliatePrivateHeaders);
Matcher denied(AffiliateFailure value) => throwsA(
  isA<AffiliateException>().having((e) => e.failure, 'failure', value),
);
Map<String, dynamic> application({
  String status = 'active',
  bool verified = true,
}) => {
  'id': 'person_fixture',
  'status': status,
  'revision': 4,
  'profile': {'display_name': 'Applicant Fixture'},
  'bank_revision': 2,
  'bank_verified': verified ? 1 : 0,
};
Map<String, dynamic> receipt({
  int chargeback = 0,
  int refund = 1210,
  bool verified = true,
}) => {
  'id': 'receipt_fixture',
  'state': 'held_review',
  'reason': 'net_vat_basis_review',
  'revision': 7,
  'affiliate_id': 'person_fixture',
  'target': 0,
  'receipt': {
    'payment_id': 'tr_fixture',
    'verified': verified,
    'currency': 'EUR',
    'gross_cents': 12100,
    'refunded_gross_cents': refund,
    'charged_back_gross_cents': chargeback,
    'mode': 'live',
    'payment_status': 'paid',
  },
};
Map<String, dynamic> manifest({
  bool exported = false,
  String proof = 'server_opaque_proof',
}) => {
  'ok': true,
  'batch_id': 'batch_fixture',
  'manifest_hash': proof,
  if (exported) 'format': 'review_manifest_v1',
  if (exported) 'bank_format_validated': false,
  'items': [
    {
      'payout_id': 'payout_fixture',
      'affiliate_id': 'person_fixture',
      'cents': 1250,
      'currency': 'EUR',
      'bank_revision': 2,
      if (exported)
        'bank_account': {
          'iban': 'BE68539007547034',
          'account_holder': 'Applicant Fixture',
        },
    },
  ],
};
Future<AffiliateAdminRepository> admin(AffiliateFixture fixture) async =>
    AffiliateAdminRepository(
      fixture.repository,
      await fixture.repository.loadOverview(),
    );
AffiliateFixture setup(
  Future<http.Response> Function(http.Request) callback, {
  bool ceo = true,
}) => AffiliateFixture(
  http: MockClient((r) async {
    if (r.url.path == '/affiliate/me')
      return reply(
        affiliateOverview(status: 'active')..['can_administer'] = ceo,
      );
    expect(r.headers['Authorization'], 'Bearer personal_fixture_A');
    expect(r.headers.containsKey('x-admin-token'), false);
    return callback(r);
  }),
);

void main() {
  test(
    'ordinary member cannot invoke admin endpoint or arbitrary endpoint',
    () async {
      var calls = 0;
      final fixture = setup((_) async {
        calls++;
        return reply({'ok': true});
      }, ceo: false);
      addTearDown(fixture.dispose);
      final repository = await admin(fixture);
      await expectLater(
        repository.applications(),
        denied(AffiliateFailure.signInRequired),
      );
      await expectLater(
        fixture.repository.administrativeRequest(
          repository.overview,
          '../capabilities',
          body: {},
        ),
        denied(AffiliateFailure.signInRequired),
      );
      expect(calls, 0);
    },
  );
  for (final status in [200, 401, 403]) {
    test(
      'late CEO A $status does not expose data or clear personal B',
      () async {
        final started = Completer<void>(), pending = Completer<http.Response>();
        final fixture = setup((_) {
          started.complete();
          return pending.future;
        });
        addTearDown(fixture.dispose);
        final repository = await admin(fixture);
        final load = repository.applications();
        await started.future;
        fixture.replace(affiliateSession('B'));
        pending.complete(
          reply({
            'ok': true,
            'items': [application()],
            'next_cursor': null,
          }, status),
        );
        await expectLater(load, denied(AffiliateFailure.sessionChanged));
        expect(fixture.current!.customerId, 'B');
      },
    );
  }
  test(
    'server capability revocation is denied on next actual personal request',
    () async {
      final fixture = setup((r) async {
        expect(r.url.path, '/affiliate/admin/applications');
        return reply({'ok': false, 'error': 'affiliate_ceo_required'}, 403);
      });
      addTearDown(fixture.dispose);
      await expectLater(
        (await admin(fixture)).applications(),
        denied(AffiliateFailure.signInRequired),
      );
    },
  );
  test(
    'application and bank review carry exact captured revisions and references',
    () async {
      final calls = <Map<String, dynamic>>[];
      final fixture = setup((r) async {
        calls.add(jsonDecode(r.body));
        return reply(
          r.url.path.endsWith('applications/review')
              ? {'ok': true, 'status': 'active', 'revision': 5}
              : {'ok': true, 'bank_verified': true, 'revision': 5},
        );
      });
      addTearDown(fixture.dispose);
      final repository = await admin(fixture),
          row = AffiliateApplication.parse(
            application(status: 'pending', verified: false),
          );
      await repository.reviewApplication(
        row,
        'active',
        ' reviewed application ',
      );
      await repository.verifyBank(row, ' independent bank evidence ');
      expect(calls, [
        {
          'affiliate_id': 'person_fixture',
          'expected_revision': 4,
          'status': 'active',
          'review_reference': 'reviewed application',
        },
        {
          'affiliate_id': 'person_fixture',
          'expected_revision': 4,
          'bank_revision': 2,
          'verification_reference': 'independent bank evidence',
        },
      ]);
    },
  );
  test(
    'basis only uses actual receipt gross/refund and reviewed credit proof',
    () async {
      var calls = 0;
      final fixture = setup((r) async {
        calls++;
        expect(r.url.path, '/affiliate/admin/receipts/basis');
        expect(jsonDecode(r.body), {
          'payment_id': 'tr_fixture',
          'expected_revision': 7,
          'correction_policy_approved': true,
          'basis': {
            'source': 'reviewed_invoice',
            'reference': 'invoice',
            'currency': 'EUR',
            'ex_vat_cents': 10000,
            'vat_cents': 2100,
            'refunded_ex_vat_cents': 1000,
            'refunded_vat_cents': 210,
            'credit_reference': 'credit',
          },
        });
        return reply({'ok': true});
      });
      addTearDown(fixture.dispose);
      final repository = await admin(fixture);
      Future<void> check(
        AffiliateReceiptReview row, {
        int net = 10000,
        bool correction = true,
        String credit = 'credit',
      }) => repository.reviewBasis(
        row,
        reference: 'invoice',
        net: net,
        vat: 2100,
        refundedNet: 1000,
        refundedVat: 210,
        creditReference: credit,
        correctionApproved: correction,
      );
      for (final bad in [
        () => check(AffiliateReceiptReview.parse(receipt()), net: 9999),
        () => check(AffiliateReceiptReview.parse(receipt()), correction: false),
        () => check(AffiliateReceiptReview.parse(receipt()), credit: ''),
        () => check(AffiliateReceiptReview.parse(receipt(chargeback: 1))),
        () => check(AffiliateReceiptReview.parse(receipt(verified: false))),
      ]) {
        await expectLater(bad(), denied(AffiliateFailure.termsChanged));
      }
      expect(calls, 0);
      await check(AffiliateReceiptReview.parse(receipt()));
      expect(calls, 1);
    },
  );
  test(
    'monthly create/export keeps server proof and does not invent payment',
    () async {
      final fixture = setup((r) async {
        final body = jsonDecode(r.body);
        if (r.url.path == '/affiliate/admin/batches') {
          expect(body, {
            'batch_id': 'batch_fixture',
            'period': '2026-10',
            'currency': 'EUR',
            'affiliate_ids': ['person_fixture'],
          });
          return reply(manifest());
        }
        expect(body, {
          'batch_id': 'batch_fixture',
          'manifest_hash': 'server_opaque_proof',
        });
        return reply(manifest(exported: true));
      });
      addTearDown(fixture.dispose);
      final repository = await admin(fixture);
      final prepared = await repository.createBatch(
        id: 'batch_fixture',
        period: '2026-10',
        currency: 'EUR',
        affiliates: [AffiliateApplication.parse(application())],
      );
      expect(prepared.exported, false);
      expect(prepared.items.single.cents, 1250);
      expect(prepared.items.single.iban, isNull);
      final exported = await repository.exportBatch(
        const AffiliateBatch(
          'batch_fixture',
          '2026-10',
          'EUR',
          'server_opaque_proof',
        ),
      );
      expect(exported.exported, true);
      expect(exported.items.single.cents, 1250);
      expect(exported.items.single.iban, 'BE68539007547034');
    },
  );
  for (final malformed in ['wrongproof', 'bankvalidated', 'wrongbatch']) {
    test('reject $malformed export before any reconciliation', () async {
      final json = manifest(exported: true);
      if (malformed == 'wrongproof') json['manifest_hash'] = 'foreign';
      if (malformed == 'wrongbatch') json['batch_id'] = 'foreign';
      if (malformed == 'bankvalidated') json['bank_format_validated'] = true;
      final fixture = setup((_) async => reply(json));
      addTearDown(fixture.dispose);
      await expectLater(
        (await admin(fixture)).exportBatch(
          const AffiliateBatch(
            'batch_fixture',
            '2026-10',
            'EUR',
            'server_opaque_proof',
          ),
        ),
        denied(AffiliateFailure.unavailable),
      );
    });
  }
  test(
    'reconcile submits immutable item amount plus genuine execution references only',
    () async {
      var calls = 0;
      final fixture = setup((r) async {
        calls++;
        expect(r.url.path, '/affiliate/admin/batches/reconcile');
        expect(jsonDecode(r.body), {
          'batch_id': 'batch_fixture',
          'manifest_hash': 'server_opaque_proof',
          'executions': [
            {
              'payout_id': 'payout_fixture',
              'bank_execution_reference': 'bank evidence',
              'evidence_reference': 'statement',
              'executed_at': '2026-10-04T12:00:00Z',
              'status': 'paid',
              'amount_cents': 1250,
              'currency': 'EUR',
            },
          ],
        });
        return reply({
          'ok': true,
          'batch_id': 'batch_fixture',
          'items': [
            {'payout_id': 'payout_fixture', 'state': 'paid'},
          ],
        });
      });
      addTearDown(fixture.dispose);
      final repository = await admin(fixture),
          exported = AffiliateManifest.parse(
            manifest(exported: true),
            exported: true,
          );
      final foreign = AffiliateManifest.parse(
        manifest(exported: true),
        exported: true,
      ).items.single;
      await expectLater(
        repository.reconcile(
          exported,
          foreign,
          reference: 'bank evidence',
          evidence: 'statement',
          executedAt: '2026-10-04T12:00:00Z',
          status: 'paid',
        ),
        denied(AffiliateFailure.termsChanged),
      );
      expect(calls, 0);
      await repository.reconcile(
        exported,
        exported.items.single,
        reference: 'bank evidence',
        evidence: 'statement',
        executedAt: '2026-10-04T12:00:00Z',
        status: 'paid',
      );
      expect(calls, 1);
    },
  );
  test(
    'cancellation is server scoped and does not accept exported shortcut',
    () async {
      final fixture = setup((r) async {
        expect(jsonDecode(r.body), {
          'batch_id': 'batch_fixture',
          'manifest_hash': 'server_opaque_proof',
          'review_reference': 'reviewed cancelled preparation',
        });
        return reply({
          'ok': false,
          'error': 'exported_batch_cancellation_requires_bank_proof',
        }, 409);
      });
      addTearDown(fixture.dispose);
      await expectLater(
        (await admin(fixture)).cancelBatch(
          const AffiliateBatch(
            'batch_fixture',
            '2026-10',
            'EUR',
            'server_opaque_proof',
          ),
          'reviewed cancelled preparation',
        ),
        denied(AffiliateFailure.termsChanged),
      );
    },
  );
  test(
    'registration recovery passes exact server hash and revision, no company credential',
    () async {
      final hash = 'a' * 64;
      final fixture = setup((r) async {
        expect(r.url.path, '/affiliate/admin/registrations/complete');
        expect(jsonDecode(r.body), {
          'registration_id': 'registration_fixture',
          'expected_revision': 3,
          'payload_hash': hash,
          'review_reference': 'registry proof',
        });
        return reply({
          'ok': true,
          'registration_id': 'registration_fixture',
          'state': 'completed',
          'revision': 4,
        });
      });
      addTearDown(fixture.dispose);
      final row = AffiliateRegistrationReview.parse({
        'registration_id': 'registration_fixture',
        'person_id': 'person_fixture',
        'payload_hash': hash,
        'scope': {
          'tenant_id': 'tenant_fixture',
          'company_id': 'company_fixture',
        },
        'state': 'writing',
        'revision': 3,
      });
      await (await admin(fixture)).completeRegistration(row, 'registry proof');
    },
  );
  test(
    'payment recovery and ownership review have typed scope and human evidence',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final fixture = setup((r) async {
        bodies.add(jsonDecode(r.body));
        return reply({'ok': true, 'state': 'verified'});
      });
      addTearDown(fixture.dispose);
      final repository = await admin(fixture);
      await repository.recoverReceipt(
        paymentId: 'tr_fixture',
        tenant: 'tenant_fixture',
        company: 'company_fixture',
      );
      await repository.reviewOwner(
        tenant: 'tenant_fixture',
        company: 'company_fixture',
        personId: 'person_fixture',
        reference: 'reviewed deed',
      );
      expect(bodies, [
        {
          'payment_id': 'tr_fixture',
          'tenant_id': 'tenant_fixture',
          'company_id': 'company_fixture',
        },
        {
          'tenant_id': 'tenant_fixture',
          'company_id': 'company_fixture',
          'person_id': 'person_fixture',
          'proof_reference': 'reviewed deed',
        },
      ]);
    },
  );
  test(
    'money input parses decimal cents without float rounding or negative corrections',
    () {
      expect(affiliateCentsInput('115,05'), 11505);
      expect(affiliateCentsInput('1.1'), 110);
      expect(affiliateCentsInput('-1'), isNull);
      expect(affiliateCentsInput('1.999'), isNull);
    },
  );
}
