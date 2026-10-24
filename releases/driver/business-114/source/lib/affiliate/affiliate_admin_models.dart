import 'affiliate_models.dart';

Map<String, dynamic> affiliateObject(dynamic value) {
  if (value is! Map<String, dynamic>)
    throw const FormatException('Invalid record');
  return value;
}

List<Map<String, dynamic>> affiliateRows(Map<String, dynamic> json) {
  final rows = json['items'];
  if (json['ok'] != true || rows is! List || rows.length > 100)
    throw const FormatException('Invalid list');
  return rows.map(affiliateObject).toList(growable: false);
}

String? affiliateCursor(Map<String, dynamic> json) {
  final cursor = affiliateText(json['next_cursor'], 500, optional: true);
  return cursor.isEmpty ? null : cursor;
}

String affiliateCurrency(dynamic value) {
  final currency = affiliateText(value, 3);
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency))
    throw const FormatException('Invalid currency');
  return currency;
}

class AffiliateApplication {
  const AffiliateApplication(
    this.id,
    this.name,
    this.status,
    this.revision,
    this.bankRevision,
    this.bankVerified, {
    this.legalName = '',
    this.address = '',
    this.country = '',
    this.applicantType = 'person',
    this.companyRegistrationNumber = '',
    this.vatNumber = '',
  });
  final String id, name, status;
  final int revision, bankRevision;
  final bool bankVerified;
  final String legalName, address, country, applicantType;
  final String companyRegistrationNumber, vatNumber;
  factory AffiliateApplication.parse(Map<String, dynamic> json) {
    final profile = affiliateObject(json['profile']);
    final status = affiliateText(json['status'], 30);
    if (!const ['pending', 'active', 'rejected', 'suspended'].contains(status))
      throw const FormatException('Invalid application');
    return AffiliateApplication(
      affiliateText(json['id'], 160),
      affiliateText(profile['display_name'], 200),
      status,
      affiliateInt(json['revision']),
      affiliateInt(json['bank_revision']),
      json['bank_verified'] == 1 || json['bank_verified'] == true,
      legalName: affiliateText(profile['legal_name'], 200, optional: true),
      address: affiliateText(profile['address'], 500, optional: true),
      country: affiliateText(profile['country'], 2, optional: true),
      applicantType: affiliateText(profile['applicant_type'] ?? 'person', 20),
      companyRegistrationNumber: affiliateIdentifier(
        profile['company_registration_number'],
      ),
      vatNumber: affiliateIdentifier(profile['vat_number']),
    );
  }
}

class AffiliateReceiptReview {
  const AffiliateReceiptReview(
    this.id,
    this.paymentId,
    this.revision,
    this.currency,
    this.gross,
    this.refunded,
    this.chargedBack,
    this.reason,
    this.mode,
    this.paymentStatus,
    this.verified,
  );
  final String id, paymentId, currency, reason, mode, paymentStatus;
  final int revision, gross, refunded, chargedBack;
  final bool verified;
  factory AffiliateReceiptReview.parse(Map<String, dynamic> json) {
    final receipt = affiliateObject(json['receipt']);
    if (json['state'] != 'held_review')
      throw const FormatException('Invalid review state');
    return AffiliateReceiptReview(
      affiliateText(json['id'], 500),
      affiliateText(receipt['payment_id'], 160),
      affiliateInt(json['revision']),
      affiliateCurrency(receipt['currency']),
      affiliateInt(receipt['gross_cents']),
      affiliateInt(receipt['refunded_gross_cents']),
      affiliateInt(receipt['charged_back_gross_cents'] ?? 0),
      affiliateText(json['reason'], 160, optional: true),
      affiliateText(receipt['mode'], 20),
      affiliateText(receipt['payment_status'], 40),
      receipt['verified'] == true,
    );
  }
  bool get mayReviewBasis =>
      verified && mode == 'live' && paymentStatus == 'paid' && chargedBack == 0;
}

class AffiliateBatch {
  const AffiliateBatch(this.id, this.period, this.currency, this.manifest);
  final String id, period, currency, manifest;
  factory AffiliateBatch.parse(Map<String, dynamic> json) => AffiliateBatch(
    affiliateText(json['id'], 160),
    affiliateText(json['period'], 7),
    affiliateCurrency(json['currency']),
    affiliateText(json['manifest_hash'], 160),
  );
}

class AffiliateManifestItem {
  const AffiliateManifestItem(
    this.payoutId,
    this.affiliateId,
    this.cents,
    this.currency,
    this.bankRevision,
    this.iban,
    this.accountHolder,
  );
  final String payoutId, affiliateId, currency;
  final int cents, bankRevision;
  final String? iban, accountHolder;
  factory AffiliateManifestItem.parse(
    Map<String, dynamic> json, {
    required bool exported,
  }) {
    final bank = exported ? affiliateObject(json['bank_account']) : null;
    return AffiliateManifestItem(
      affiliateText(json['payout_id'], 500),
      affiliateText(json['affiliate_id'], 160),
      affiliateInt(json['cents']),
      affiliateCurrency(json['currency']),
      affiliateInt(json['bank_revision']),
      bank == null ? null : affiliateText(bank['iban'], 80),
      bank == null ? null : affiliateText(bank['account_holder'], 200),
    );
  }
}

class AffiliateManifest {
  const AffiliateManifest(this.batchId, this.proof, this.items, this.exported);
  final String batchId, proof;
  final List<AffiliateManifestItem> items;
  final bool exported;
  factory AffiliateManifest.parse(
    Map<String, dynamic> json, {
    required bool exported,
  }) {
    if (exported &&
        (json['format'] != 'review_manifest_v1' ||
            json['bank_format_validated'] != false)) {
      throw const FormatException('Unsupported bank format');
    }
    return AffiliateManifest(
      affiliateText(json['batch_id'], 160),
      affiliateText(json['manifest_hash'], 160),
      List.unmodifiable(
        affiliateRows(
          json,
        ).map((row) => AffiliateManifestItem.parse(row, exported: exported)),
      ),
      exported,
    );
  }
}

class AffiliateAdminList<T> {
  const AffiliateAdminList(this.items, this.cursor);
  final List<T> items;
  final String? cursor;
}

class AffiliateRegistrationReview {
  const AffiliateRegistrationReview(
    this.id,
    this.personId,
    this.payloadHash,
    this.tenant,
    this.company,
    this.revision,
  );
  final String id, personId, payloadHash, tenant, company;
  final int revision;
  factory AffiliateRegistrationReview.parse(Map<String, dynamic> json) {
    final scope = affiliateObject(json['scope']);
    final hash = affiliateText(json['payload_hash'], 64);
    if (json['state'] != 'writing' || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      throw const FormatException('Invalid registration proof');
    return AffiliateRegistrationReview(
      affiliateText(json['registration_id'], 500),
      affiliateText(json['person_id'], 160),
      hash,
      affiliateText(scope['tenant_id'], 80),
      affiliateText(scope['company_id'], 80),
      affiliateInt(json['revision']),
    );
  }
}
