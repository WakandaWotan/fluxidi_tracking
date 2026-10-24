class AffiliateBalance {
  const AffiliateBalance(
    this.currency,
    this.balanceCents,
    this.reservedCents,
    this.availableCents,
    this.paidCents,
  );
  final String currency;
  final int balanceCents, reservedCents, availableCents, paidCents;
}

/// Actual applicant details returned by this person's private server overview.
/// Missing legacy identifiers remain unknown; company-admin data is not used.
class AffiliateApplicantProfile {
  const AffiliateApplicantProfile({
    required this.applicantType,
    required this.companyRegistrationNumber,
    required this.vatNumber,
  });
  final String applicantType, companyRegistrationNumber, vatNumber;

  factory AffiliateApplicantProfile.parse(Map<String, dynamic> json) {
    final type = json['applicant_type'] ?? 'person';
    if (!const ['person', 'business'].contains(type)) {
      throw const FormatException('Invalid applicant type');
    }
    final registration = affiliateIdentifier(
      json['company_registration_number'],
    );
    final vat = affiliateIdentifier(json['vat_number']);
    if (type != 'business' && (registration.isNotEmpty || vat.isNotEmpty)) {
      throw const FormatException('Invalid personal identifiers');
    }
    return AffiliateApplicantProfile(
      applicantType: type as String,
      companyRegistrationNumber: registration,
      vatNumber: vat,
    );
  }
}

String affiliateIdentifier(dynamic value) {
  if (value == null) return '';
  if (value is! String ||
      value.length > 64 ||
      RegExp(r'[\x00-\x1F\x7F-\x9F\u2028\u2029]').hasMatch(value)) {
    throw const FormatException('Invalid applicant identifier');
  }
  return value;
}

class AffiliateOverview {
  const AffiliateOverview({
    required this.affiliateId,
    required this.status,
    required this.revision,
    required this.balances,
    required this.mayApply,
    required this.termsVersion,
    required this.termsText,
    required this.heldReceipts,
    required this.referredCompanies,
    required this.referralCode,
    required this.bankVerified,
    required this.canAdminister,
    required this.bankRevision,
    this.profile,
  });
  final String affiliateId, status, termsVersion, termsText;
  final int revision, heldReceipts, referredCompanies, bankRevision;
  final List<AffiliateBalance> balances;
  final bool mayApply, bankVerified, canAdminister;
  final String? referralCode;
  final AffiliateApplicantProfile? profile;

  factory AffiliateOverview.parse(Map<String, dynamic> json, String personId) {
    if (json['ok'] != true ||
        json['affiliate_id'] != personId ||
        json['program_enabled'] != true ||
        json['commission_rate_bps'] != 500 ||
        json['revenue_basis'] !=
            'verified_paid_ex_vat_subscriptions_and_addons' ||
        json['automatic_bank_transfers'] != false ||
        !const [
          'not_enrolled',
          'pending',
          'active',
          'rejected',
          'suspended',
        ].contains(json['status'])) {
      throw const FormatException('Invalid affiliate overview');
    }
    final rows = json['balances'];
    if (rows is! List || rows.length > 20)
      throw const FormatException('Invalid balances');
    final currencies = <String>{};
    final balances = <AffiliateBalance>[];
    for (final raw in rows) {
      if (raw is! Map) throw const FormatException('Invalid balance');
      final currency = affiliateText(raw['currency'], 3);
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
          !currencies.add(currency)) {
        throw const FormatException('Invalid currency');
      }
      balances.add(
        AffiliateBalance(
          currency,
          affiliateInt(raw['balance_cents'], negativeAllowed: true),
          affiliateInt(raw['reserved_cents']),
          affiliateInt(raw['available_cents']),
          affiliateInt(raw['paid_cents']),
        ),
      );
    }
    final version = affiliateText(json['terms_version'], 80, optional: true);
    final terms = affiliateText(json['terms_text'], 12000, optional: true);
    if (json['may_apply'] == true && (version.isEmpty || terms.isEmpty)) {
      throw const FormatException('Missing terms');
    }
    final code = affiliateText(json['referral_code'], 40, optional: true);
    final rawProfile = json['profile'];
    if (rawProfile != null && rawProfile is! Map<String, dynamic>) {
      throw const FormatException('Invalid applicant profile');
    }
    return AffiliateOverview(
      affiliateId: personId,
      status: json['status'] as String,
      revision: affiliateInt(json['revision']),
      balances: List.unmodifiable(balances),
      mayApply: json['may_apply'] == true,
      termsVersion: version,
      termsText: terms,
      heldReceipts: affiliateInt(json['held_receipts'] ?? 0),
      referredCompanies: affiliateInt(json['referred_companies'] ?? 0),
      referralCode: json['status'] == 'active' && code.isNotEmpty ? code : null,
      bankVerified: json['bank_verified'] == true,
      canAdminister: json['can_administer'] == true,
      bankRevision: affiliateInt(json['bank_revision'] ?? 0),
      profile: rawProfile == null
          ? null
          : AffiliateApplicantProfile.parse(rawProfile as Map<String, dynamic>),
    );
  }
}

class AffiliatePayout {
  const AffiliatePayout(
    this.id,
    this.period,
    this.currency,
    this.cents,
    this.state,
  );
  final String id, period, currency, state;
  final int cents;
}

class AffiliatePayoutPage {
  const AffiliatePayoutPage(this.items, this.nextCursor);
  final List<AffiliatePayout> items;
  final String? nextCursor;
  factory AffiliatePayoutPage.parse(Map<String, dynamic> json) {
    final rows = json['items'];
    if (json['ok'] != true || rows is! List || rows.length > 50) {
      throw const FormatException('Invalid payout history');
    }
    final items = <AffiliatePayout>[];
    for (final raw in rows) {
      if (raw is! Map ||
          !const [
            'approved',
            'exported',
            'paid',
            'failed',
            'cancelled',
          ].contains(raw['state'])) {
        throw const FormatException('Invalid payout');
      }
      final currency = affiliateText(raw['currency'], 3);
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency))
        throw const FormatException('Invalid currency');
      items.add(
        AffiliatePayout(
          affiliateText(raw['id'], 500),
          affiliateText(raw['period'], 7),
          currency,
          affiliateInt(raw['cents']),
          raw['state'] as String,
        ),
      );
    }
    final cursor = affiliateText(json['next_cursor'], 500, optional: true);
    return AffiliatePayoutPage(
      List.unmodifiable(items),
      cursor.isEmpty ? null : cursor,
    );
  }
}

class AffiliateEntry {
  const AffiliateEntry(
    this.id,
    this.currency,
    this.cents,
    this.kind,
    this.period,
    this.createdAt,
  );
  final int id, cents;
  final String currency, kind, period, createdAt;
}

class AffiliateReferral {
  const AffiliateReferral(this.id, this.state, this.createdAt);
  final String id, state, createdAt;
}

class AffiliateReferralPage {
  const AffiliateReferralPage(this.items, this.nextCursor);
  final List<AffiliateReferral> items;
  final String? nextCursor;
  factory AffiliateReferralPage.parse(Map<String, dynamic> json) {
    final rows = json['items'];
    if (json['ok'] != true || rows is! List || rows.length > 50)
      throw const FormatException('Invalid referrals');
    final items = <AffiliateReferral>[];
    for (final raw in rows) {
      if (raw is! Map ||
          !const ['active', 'held_owner_review'].contains(raw['state']))
        throw const FormatException('Invalid referral');
      items.add(
        AffiliateReferral(
          affiliateText(raw['referral_id'], 500),
          raw['state'] as String,
          affiliateText(raw['created_at'], 40),
        ),
      );
    }
    final cursor = affiliateText(json['next_cursor'], 500, optional: true);
    return AffiliateReferralPage(
      List.unmodifiable(items),
      cursor.isEmpty ? null : cursor,
    );
  }
}

class AffiliateEntryPage {
  const AffiliateEntryPage(this.items, this.nextCursor);
  final List<AffiliateEntry> items;
  final String? nextCursor;
  factory AffiliateEntryPage.parse(Map<String, dynamic> json) {
    final rows = json['items'];
    if (json['ok'] != true || rows is! List || rows.length > 50) {
      throw const FormatException('Invalid balance history');
    }
    final items = <AffiliateEntry>[];
    for (final raw in rows) {
      if (raw is! Map ||
          !const [
            'commission',
            'correction',
            'bank_payout',
          ].contains(raw['kind'])) {
        throw const FormatException('Invalid balance entry');
      }
      final currency = affiliateText(raw['currency'], 3);
      final period = affiliateText(raw['period'], 7);
      final createdAt = affiliateText(raw['created_at'], 40);
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period) ||
          !createdAt.endsWith('Z') ||
          DateTime.tryParse(createdAt) == null) {
        throw const FormatException('Invalid balance entry');
      }
      items.add(
        AffiliateEntry(
          affiliateInt(raw['id']),
          currency,
          affiliateInt(raw['cents'], negativeAllowed: true),
          raw['kind'] as String,
          period,
          createdAt,
        ),
      );
    }
    final cursor = affiliateText(json['next_cursor'], 500, optional: true);
    return AffiliateEntryPage(
      List.unmodifiable(items),
      cursor.isEmpty ? null : cursor,
    );
  }
}

int affiliateInt(dynamic value, {bool negativeAllowed = false}) {
  if (value is! int ||
      value.abs() > 9007199254740991 ||
      (!negativeAllowed && value < 0)) {
    throw const FormatException('Invalid monetary integer');
  }
  return value;
}

String affiliateText(dynamic value, int max, {bool optional = false}) {
  if (optional && value == null) return '';
  if (value is! String ||
      value.length > max ||
      (!optional && value.trim().isEmpty)) {
    throw const FormatException('Invalid text');
  }
  return value.trim();
}
