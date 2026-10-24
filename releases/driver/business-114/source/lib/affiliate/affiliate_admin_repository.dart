import 'affiliate_admin_models.dart';
import 'affiliate_repository.dart';

class AffiliateAdminRepository {
  const AffiliateAdminRepository(this.repository, this.overview);
  final AffiliateRepository repository;
  final OwnedAffiliateOverview overview;
  bool get owns =>
      overview.data.canAdminister && repository.owns(overview.owner);
  Future<T> _parse<T>(
    Future<Map<String, dynamic>> request,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final json = await request;
    try {
      return parse(json);
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String? cursor,
    Map<String, String>? query,
  }) => repository.administrativeRequest(
    overview,
    path,
    query: {'limit': '20', if (cursor != null) 'cursor': cursor, ...?query},
  );
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      repository.administrativeRequest(overview, path, body: body);
  Future<AffiliateAdminList<AffiliateApplication>> applications({
    String? cursor,
  }) => _parse(
    _get('applications', cursor: cursor),
    (json) => AffiliateAdminList(
      affiliateRows(
        json,
      ).map(AffiliateApplication.parse).toList(growable: false),
      affiliateCursor(json),
    ),
  );
  Future<AffiliateAdminList<AffiliateReceiptReview>> receipts({
    String? cursor,
  }) => _parse(
    _get('receipts/review', cursor: cursor),
    (json) => AffiliateAdminList(
      affiliateRows(
        json,
      ).map(AffiliateReceiptReview.parse).toList(growable: false),
      affiliateCursor(json),
    ),
  );
  Future<AffiliateAdminList<AffiliateBatch>> batches({String? cursor}) =>
      _parse(
        _get('batches', cursor: cursor),
        (json) => AffiliateAdminList(
          affiliateRows(json).map(AffiliateBatch.parse).toList(growable: false),
          affiliateCursor(json),
        ),
      );
  Future<AffiliateAdminList<AffiliateRegistrationReview>> registrations({
    String? cursor,
  }) => _parse(
    _get('registrations', cursor: cursor),
    (json) => AffiliateAdminList(
      affiliateRows(
        json,
      ).map(AffiliateRegistrationReview.parse).toList(growable: false),
      affiliateCursor(json),
    ),
  );
  Future<void> completeRegistration(
    AffiliateRegistrationReview row,
    String reference,
  ) async {
    if (reference.trim().isEmpty)
      throw const AffiliateException(AffiliateFailure.termsChanged);
    final json = await _post('registrations/complete', {
      'registration_id': row.id,
      'expected_revision': row.revision,
      'payload_hash': row.payloadHash,
      'review_reference': reference.trim(),
    });
    if (json['registration_id'] != row.id ||
        json['state'] != 'completed' ||
        json['revision'] != row.revision + 1) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  Future<void> reviewApplication(
    AffiliateApplication row,
    String status,
    String reference,
  ) async {
    if (!const ['active', 'rejected', 'suspended'].contains(status) ||
        reference.trim().isEmpty) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    final json = await _post('applications/review', {
      'affiliate_id': row.id,
      'expected_revision': row.revision,
      'status': status,
      'review_reference': reference.trim(),
    });
    if (json['status'] != status || json['revision'] != row.revision + 1)
      throw const AffiliateException(AffiliateFailure.unavailable);
  }

  Future<void> verifyBank(AffiliateApplication row, String reference) async {
    if (row.bankRevision == 0 || reference.trim().isEmpty)
      throw const AffiliateException(AffiliateFailure.termsChanged);
    final json = await _post('bank-accounts/verify', {
      'affiliate_id': row.id,
      'expected_revision': row.revision,
      'bank_revision': row.bankRevision,
      'verification_reference': reference.trim(),
    });
    if (json['bank_verified'] != true || json['revision'] != row.revision + 1)
      throw const AffiliateException(AffiliateFailure.unavailable);
  }

  Future<void> reviewBasis(
    AffiliateReceiptReview row, {
    required String reference,
    required int net,
    required int vat,
    required int refundedNet,
    required int refundedVat,
    required String creditReference,
    required bool correctionApproved,
  }) async {
    if (!row.mayReviewBasis ||
        reference.trim().isEmpty ||
        net < 0 ||
        vat < 0 ||
        refundedNet < 0 ||
        refundedVat < 0 ||
        net + vat != row.gross ||
        refundedNet + refundedVat != row.refunded ||
        refundedNet > net ||
        refundedVat > vat ||
        (row.refunded > 0 &&
            (!correctionApproved || creditReference.trim().isEmpty))) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    await _post('receipts/basis', {
      'payment_id': row.paymentId,
      'expected_revision': row.revision,
      if (row.refunded > 0) 'correction_policy_approved': correctionApproved,
      'basis': {
        'source': 'reviewed_invoice',
        'reference': reference.trim(),
        'currency': row.currency,
        'ex_vat_cents': net,
        'vat_cents': vat,
        'refunded_ex_vat_cents': refundedNet,
        'refunded_vat_cents': refundedVat,
        if (creditReference.trim().isNotEmpty)
          'credit_reference': creditReference.trim(),
      },
    });
  }

  Future<void> retryReceipt(AffiliateReceiptReview row) async =>
      _post('receipts/retry', {'payment_id': row.paymentId});
  Future<void> recoverReceipt({
    required String paymentId,
    required String tenant,
    required String company,
  }) async {
    if (!RegExp(r'^tr_[A-Za-z0-9]+$').hasMatch(paymentId) ||
        tenant.trim().isEmpty ||
        company.trim().isEmpty) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    await _post('receipts/recover', {
      'payment_id': paymentId,
      'tenant_id': tenant.trim(),
      'company_id': company.trim(),
    });
  }

  Future<void> reviewOwner({
    required String tenant,
    required String company,
    required String personId,
    required String reference,
  }) async {
    if ([
      tenant,
      company,
      personId,
      reference,
    ].any((value) => value.trim().isEmpty)) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    final json = await _post('owners/review', {
      'tenant_id': tenant.trim(),
      'company_id': company.trim(),
      'person_id': personId.trim(),
      'proof_reference': reference.trim(),
    });
    if (json['state'] != 'verified' && json['idempotent'] != true)
      throw const AffiliateException(AffiliateFailure.unavailable);
  }

  Future<void> cancelBatch(AffiliateBatch batch, String reference) async {
    if (reference.trim().isEmpty)
      throw const AffiliateException(AffiliateFailure.termsChanged);
    final json = await _post('batches/cancel', {
      'batch_id': batch.id,
      'manifest_hash': batch.manifest,
      'review_reference': reference.trim(),
    });
    if (json['batch_id'] != batch.id || json['state'] != 'cancelled')
      throw const AffiliateException(AffiliateFailure.unavailable);
  }

  Future<AffiliateManifest> createBatch({
    required String id,
    required String period,
    required String currency,
    required List<AffiliateApplication> affiliates,
  }) {
    if (id.trim().isEmpty ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        affiliates.isEmpty ||
        affiliates.length > 100 ||
        affiliates.any((row) => row.status != 'active' || !row.bankVerified)) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    return _parse(
      _post('batches', {
        'batch_id': id.trim(),
        'period': period,
        'currency': currency,
        'affiliate_ids': affiliates.map((row) => row.id).toList(),
      }),
      (json) {
        final result = AffiliateManifest.parse(json, exported: false);
        if (result.batchId != id.trim() ||
            result.items.isEmpty ||
            result.items.map((item) => item.payoutId).toSet().length !=
                result.items.length ||
            result.items.any(
              (item) =>
                  item.currency != currency ||
                  !affiliates.any(
                    (row) =>
                        row.id == item.affiliateId &&
                        row.bankRevision == item.bankRevision,
                  ),
            )) {
          throw const FormatException('Wrong batch members');
        }
        return result;
      },
    );
  }

  Future<AffiliateManifest> exportBatch(AffiliateBatch batch) => _parse(
    _post('batches/export', {
      'batch_id': batch.id,
      'manifest_hash': batch.manifest,
    }),
    (json) {
      final result = AffiliateManifest.parse(json, exported: true);
      if (result.batchId != batch.id || result.proof != batch.manifest)
        throw const FormatException('Wrong batch proof');
      return result;
    },
  );
  Future<void> reconcile(
    AffiliateManifest manifest,
    AffiliateManifestItem item, {
    required String reference,
    required String evidence,
    required String executedAt,
    required String status,
  }) async {
    if (!manifest.exported ||
        !manifest.items.contains(item) ||
        reference.trim().isEmpty ||
        evidence.trim().isEmpty ||
        DateTime.tryParse(executedAt) == null ||
        !executedAt.endsWith('Z') ||
        !const ['paid', 'failed'].contains(status))
      throw const AffiliateException(AffiliateFailure.termsChanged);
    final json = await _post('batches/reconcile', {
      'batch_id': manifest.batchId,
      'manifest_hash': manifest.proof,
      'executions': [
        {
          'payout_id': item.payoutId,
          'bank_execution_reference': reference.trim(),
          'evidence_reference': evidence.trim(),
          'executed_at': executedAt,
          'status': status,
          'amount_cents': item.cents,
          'currency': item.currency,
        },
      ],
    });
    final rows = affiliateRows(json);
    if (json['batch_id'] != manifest.batchId ||
        rows.length != 1 ||
        rows.single['payout_id'] != item.payoutId ||
        rows.single['state'] != status) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }
}
