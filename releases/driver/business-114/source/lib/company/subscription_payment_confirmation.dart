// The server checkout result is the only payment-display authority.
// Profile/catalog quotes describe intent; they cannot authorize a payment URL.
class SubscriptionPaymentConfirmation {
  const SubscriptionPaymentConfirmation._({
    required this.tenantId,
    required this.companyId,
    required this.productCode,
    required this.currency,
    required this.netCents,
    required this.vatCents,
    required this.grossCents,
    required this.treatment,
    required this.validUntil,
    required this.recordedAt,
    required this.checkoutUri,
  });
  final String tenantId, companyId, productCode, currency, treatment;
  final int netCents, vatCents, grossCents;
  final DateTime validUntil, recordedAt;
  final Uri checkoutUri;

  bool validFor({
    required String companyId,
    required String productCode,
    DateTime? now,
  }) {
    final instant = (now ?? DateTime.now()).toUtc();
    return this.companyId == companyId &&
        tenantId == companyId &&
        this.productCode == productCode &&
        !instant.isBefore(recordedAt) &&
        instant.isBefore(validUntil);
  }

  static SubscriptionPaymentConfirmation? fromCheckoutJson(
    Map<String, dynamic> response,
  ) {
    final raw = response['payment_confirmation'];
    if (response['ok'] != true ||
        raw is! Map ||
        raw['version'] != 'subscription_payment_confirmation_v1')
      return null;
    int? cents(dynamic value) =>
        value is int && value >= 0 && value <= 9007199254740991 ? value : null;
    String? text(dynamic value) =>
        value is String &&
            value.isNotEmpty &&
            value == value.trim() &&
            !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
        ? value
        : null;
    DateTime? date(dynamic value) {
      if (value is! String ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
          ).hasMatch(value))
        return null;
      final parsed = DateTime.tryParse(value);
      return parsed != null && parsed.toUtc().toIso8601String() == value
          ? parsed
          : null;
    }

    final net = cents(raw['ex_vat_cents']), vat = cents(raw['vat_cents']);
    final gross = cents(raw['gross_cents']);
    final treatment = text(raw['treatment']);
    final tenant = text(raw['tenant_id']), company = text(raw['company_id']);
    final product = text(raw['product_code']), currency = text(raw['currency']);
    final recorded = date(raw['recorded_at']), until = date(raw['valid_until']);
    final uri = Uri.tryParse(
      response['checkout_url'] is String ? response['checkout_url'] : '',
    );
    final activation = text(raw['activation_id']),
        payment = text(raw['provider_payment_id']);
    if (net == null ||
        net == 0 ||
        vat == null ||
        gross == null ||
        gross == 0 ||
        net + vat != gross ||
        gross != cents(response['expected_amount_cents']) ||
        net != cents(response['amount_excl_vat_cents']) ||
        vat != cents(response['vat_amount_cents']) ||
        currency != response['currency'] ||
        currency == null ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        tenant == null ||
        company == null ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(tenant) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(company) ||
        !const {
          'fluxidi_pro',
          'extra_vehicle',
          'extra_driver',
          'pdf_500',
          'pdf_1000',
          'pdf_5000',
        }.contains(product) ||
        raw['quantity'] != 1 ||
        raw['quantity'] is! int ||
        (product != 'fluxidi_pro' &&
            (response['addon_code'] != product ||
                response['quantity'] != 1 ||
                response['quantity'] is! int)) ||
        activation == null ||
        activation != response['activation_id'] ||
        payment == null ||
        payment != response['provider_payment_id'] ||
        !RegExp(r'^tr_[A-Za-z0-9_]+$').hasMatch(payment) ||
        recorded == null ||
        until == null ||
        !recorded.isBefore(until) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !const {
          'reviewed_taxable',
          'eu_b2b_reverse_charge',
          'reviewed_zero_rate',
        }.contains(treatment) ||
        (treatment != 'reviewed_taxable' && vat != 0))
      return null;
    final totals = response['tax_totals'];
    if (totals is! Map ||
        cents(totals['ex_vat_cents']) != net ||
        cents(totals['vat_cents']) != vat ||
        cents(totals['gross_cents']) != gross ||
        totals['treatment'] != treatment)
      return null;
    return SubscriptionPaymentConfirmation._(
      tenantId: tenant,
      companyId: company,
      productCode: product!,
      currency: currency,
      netCents: net,
      vatCents: vat,
      grossCents: gross,
      treatment: treatment!,
      validUntil: until,
      recordedAt: recorded,
      checkoutUri: uri,
    );
  }
}
