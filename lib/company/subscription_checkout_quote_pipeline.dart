import 'dart:convert';

/// Shared authoritative quote/checkout seam for every subscription CTA.
///
/// The deployed booking Worker exposes checkout *start* routes. It does not
/// expose `/company/subscription/checkout/quote` or `/quotes`. Flutter must
/// not treat that 404 as a generic "quote unavailable", and must not invent
/// a local price to start Mollie. Confirmation uses the already-fetched
/// server subscription profile cents; checkout start remains the charge
/// authority.

const String kSubscriptionProductBase = 'fluxidi_pro';
const String kSubscriptionProductExtraVehicle = 'extra_vehicle';
const String kSubscriptionProductExtraDriver = 'extra_driver';
const String kSubscriptionProductPdf500 = 'pdf_500';
const String kSubscriptionProductPdf1000 = 'pdf_1000';
const String kSubscriptionProductPdf5000 = 'pdf_5000';

const Set<String> kSupportedSubscriptionPurchaseCodes = {
  kSubscriptionProductBase,
  kSubscriptionProductExtraVehicle,
  kSubscriptionProductExtraDriver,
  kSubscriptionProductPdf500,
  kSubscriptionProductPdf1000,
  kSubscriptionProductPdf5000,
};

enum SubscriptionQuoteFailureKind {
  none,
  fiscalBlocked,
  unauthorized,
  forbidden,
  routeMissing,
  unknownProduct,
  invalidQuantity,
  parseError,
  httpError,
  networkError,
  missingAmount,
}

enum SubscriptionQuoteSource { none, live, profile }

class SubscriptionQuoteFetchVerdict {
  const SubscriptionQuoteFetchVerdict({
    required this.kind,
    this.statusCode = 0,
    this.errorToken = '',
    this.quoteId = '',
    this.unitExclVatCents,
    this.subtotalExclVatCents,
    this.vatAmountCents,
    this.totalInclVatCents,
    this.mollieAmountCents,
    this.taxTreatment = '',
    this.currency = 'EUR',
  });

  final SubscriptionQuoteFailureKind kind;
  final int statusCode;
  final String errorToken;
  final String quoteId;
  final int? unitExclVatCents;
  final int? subtotalExclVatCents;
  final int? vatAmountCents;
  final int? totalInclVatCents;
  final int? mollieAmountCents;
  final String taxTreatment;
  final String currency;

  bool get isLiveQuote =>
      kind == SubscriptionQuoteFailureKind.none && hasConfirmableAmount;

  bool get hasConfirmableAmount {
    final amount =
        mollieAmountCents ?? subtotalExclVatCents ?? unitExclVatCents;
    return amount != null && amount > 0;
  }
}

class SubscriptionProfilePriceSlice {
  const SubscriptionProfilePriceSlice({
    required this.baseExclCents,
    required this.extraVehicleExclCents,
    required this.extraDriverExclCents,
    required this.pdfBundleExclCents,
    this.currency = 'EUR',
  });

  final int baseExclCents;
  final int extraVehicleExclCents;
  final int extraDriverExclCents;
  final Map<String, int> pdfBundleExclCents;
  final String currency;
}

class AuthoritativePurchaseQuote {
  const AuthoritativePurchaseQuote({
    required this.productCode,
    required this.quantity,
    required this.unitExclVatCents,
    required this.subtotalExclVatCents,
    required this.taxTreatment,
    required this.source,
    this.currency = 'EUR',
    this.vatAmountCents,
    this.totalInclVatCents,
    this.mollieAmountCents,
    this.quoteId = '',
  });

  final String productCode;
  final int quantity;
  final int unitExclVatCents;
  final int subtotalExclVatCents;
  final String taxTreatment;
  final SubscriptionQuoteSource source;
  final String currency;
  final int? vatAmountCents;
  final int? totalInclVatCents;
  final int? mollieAmountCents;
  final String quoteId;

  bool get canConfirm => unitExclVatCents > 0 && subtotalExclVatCents > 0;
}

class SubscriptionPurchaseQuoteResolution {
  const SubscriptionPurchaseQuoteResolution({
    required this.failure,
    this.quote,
    this.errorToken = '',
    this.statusCode = 0,
    this.quoteCallReached = false,
  });

  final SubscriptionQuoteFailureKind failure;
  final AuthoritativePurchaseQuote? quote;
  final String errorToken;
  final int statusCode;
  final bool quoteCallReached;

  bool get canConfirm =>
      failure == SubscriptionQuoteFailureKind.none &&
      quote != null &&
      quote!.canConfirm;
}

class SubscriptionPurchaseSession {
  SubscriptionPurchaseSession({
    required this.productCode,
    required this.startingMetric,
  }) : metric = startingMetric;

  final String productCode;
  final int startingMetric;
  int metric;
  bool busy = false;
  bool confirmationAccepted = false;
  bool checkoutStarted = false;
  bool activated = false;
  int checkoutStartCount = 0;

  bool get mayMutateEntitlement => activated && metric != startingMetric;

  bool beginCheckoutIfConfirmed() {
    if (!confirmationAccepted || busy || checkoutStarted || activated) {
      return false;
    }
    busy = true;
    checkoutStarted = true;
    checkoutStartCount += 1;
    return true;
  }

  void cancel() {
    if (activated) return;
    confirmationAccepted = false;
    busy = false;
    checkoutStarted = false;
  }

  void markFailure() {
    if (activated) return;
    busy = false;
    checkoutStarted = false;
  }

  void markActivated({required int nextMetric}) {
    if (!confirmationAccepted || !checkoutStarted) return;
    if (nextMetric == startingMetric) {
      markFailure();
      return;
    }
    metric = nextMetric;
    activated = true;
    busy = false;
  }
}

bool isSupportedSubscriptionPurchaseCode(String productCode) {
  return kSupportedSubscriptionPurchaseCodes.contains(productCode.trim());
}

int? authoritativeUnitExclCentsForProduct({
  required String productCode,
  required SubscriptionProfilePriceSlice prices,
}) {
  switch (productCode.trim()) {
    case kSubscriptionProductBase:
      return prices.baseExclCents > 0 ? prices.baseExclCents : null;
    case kSubscriptionProductExtraVehicle:
      return prices.extraVehicleExclCents > 0
          ? prices.extraVehicleExclCents
          : null;
    case kSubscriptionProductExtraDriver:
      return prices.extraDriverExclCents > 0
          ? prices.extraDriverExclCents
          : null;
    case kSubscriptionProductPdf500:
    case kSubscriptionProductPdf1000:
    case kSubscriptionProductPdf5000:
      final cents = prices.pdfBundleExclCents[productCode.trim()] ?? 0;
      return cents > 0 ? cents : null;
    default:
      return null;
  }
}

SubscriptionQuoteFetchVerdict classifySubscriptionQuoteHttp({
  required int statusCode,
  String contentType = '',
  String body = '',
}) {
  final type = contentType.toLowerCase();
  final trimmed = body.trim();
  Map<String, dynamic>? jsonMap;
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        jsonMap = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      jsonMap = null;
    }
  }

  String token = '';
  if (jsonMap != null) {
    token = (jsonMap['error'] ?? jsonMap['errorToken'] ?? '').toString().trim();
  }

  if (statusCode == 401 || token == 'unauthorized') {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.unauthorized,
      statusCode: statusCode,
      errorToken: token.isEmpty ? 'unauthorized' : token,
    );
  }
  if (statusCode == 403) {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.forbidden,
      statusCode: statusCode,
      errorToken: token.isEmpty ? 'forbidden' : token,
    );
  }
  if (token == 'invalid_addon_code' || token == 'unknown_product') {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.unknownProduct,
      statusCode: statusCode,
      errorToken: token,
    );
  }
  if (token == 'invalid_quantity') {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.invalidQuantity,
      statusCode: statusCode,
      errorToken: token,
    );
  }
  if (statusCode == 404 ||
      (!type.contains('json') && trimmed.toLowerCase() == 'not found')) {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.routeMissing,
      statusCode: statusCode,
      errorToken: 'quote_route_missing',
    );
  }
  if (statusCode >= 500) {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.httpError,
      statusCode: statusCode,
      errorToken: token.isEmpty ? 'http_$statusCode' : token,
    );
  }
  if (statusCode < 200 || statusCode >= 300) {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.httpError,
      statusCode: statusCode,
      errorToken: token.isEmpty ? 'http_$statusCode' : token,
    );
  }
  if (jsonMap == null) {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.parseError,
      statusCode: statusCode,
      errorToken: 'invalid_quote_payload',
    );
  }
  final quoteMap = jsonMap['quote'] is Map
      ? Map<String, dynamic>.from(jsonMap['quote'] as Map)
      : jsonMap;
  int? readInt(String snake, String camel) {
    final raw = quoteMap[snake] ?? quoteMap[camel];
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  final verdict = SubscriptionQuoteFetchVerdict(
    kind: SubscriptionQuoteFailureKind.none,
    statusCode: statusCode,
    quoteId: (quoteMap['quote_id'] ?? quoteMap['quoteId'] ?? '')
        .toString()
        .trim(),
    unitExclVatCents: readInt('unit_excl_vat_cents', 'unitExclVatCents'),
    subtotalExclVatCents: readInt(
      'subtotal_excl_vat_cents',
      'subtotalExclVatCents',
    ),
    vatAmountCents: readInt('vat_amount_cents', 'vatAmountCents'),
    totalInclVatCents: readInt('total_incl_vat_cents', 'totalInclVatCents'),
    mollieAmountCents: readInt('mollie_amount_cents', 'mollieAmountCents'),
    taxTreatment: (quoteMap['tax_treatment'] ?? quoteMap['taxTreatment'] ?? '')
        .toString()
        .trim(),
    currency: (quoteMap['currency'] ?? 'EUR').toString().trim().toUpperCase(),
  );
  if (!verdict.hasConfirmableAmount) {
    return SubscriptionQuoteFetchVerdict(
      kind: SubscriptionQuoteFailureKind.missingAmount,
      statusCode: statusCode,
      errorToken: 'missing_quote_amount',
      quoteId: verdict.quoteId,
      taxTreatment: verdict.taxTreatment,
      currency: verdict.currency,
    );
  }
  return verdict;
}

/// Shared resolver for every billing CTA.
///
/// [quoteCallReached] is true only when fiscal data is known so a Belgian
/// VAT profile actually reaches the quote HTTP call.
SubscriptionPurchaseQuoteResolution resolveSubscriptionPurchaseQuote({
  required String productCode,
  required int quantity,
  required bool fiscalKnown,
  required String fiscalTreatment,
  required List<String> fiscalMissingFields,
  required SubscriptionProfilePriceSlice profilePrices,
  required SubscriptionQuoteFetchVerdict live,
  bool quoteCallReached = false,
}) {
  final code = productCode.trim();
  if (!fiscalKnown) {
    return SubscriptionPurchaseQuoteResolution(
      failure: SubscriptionQuoteFailureKind.fiscalBlocked,
      errorToken: fiscalMissingFields.isEmpty
          ? 'fiscal_unknown'
          : fiscalMissingFields.join(','),
      quoteCallReached: false,
    );
  }
  if (!isSupportedSubscriptionPurchaseCode(code)) {
    return const SubscriptionPurchaseQuoteResolution(
      failure: SubscriptionQuoteFailureKind.unknownProduct,
      errorToken: 'invalid_addon_code',
      quoteCallReached: true,
    );
  }
  if (quantity != 1) {
    return const SubscriptionPurchaseQuoteResolution(
      failure: SubscriptionQuoteFailureKind.invalidQuantity,
      errorToken: 'invalid_quantity',
      quoteCallReached: true,
    );
  }
  if (live.kind == SubscriptionQuoteFailureKind.unauthorized ||
      live.kind == SubscriptionQuoteFailureKind.forbidden ||
      live.kind == SubscriptionQuoteFailureKind.unknownProduct ||
      live.kind == SubscriptionQuoteFailureKind.invalidQuantity ||
      live.kind == SubscriptionQuoteFailureKind.httpError ||
      live.kind == SubscriptionQuoteFailureKind.networkError ||
      live.kind == SubscriptionQuoteFailureKind.parseError) {
    return SubscriptionPurchaseQuoteResolution(
      failure: live.kind,
      errorToken: live.errorToken,
      statusCode: live.statusCode,
      quoteCallReached: quoteCallReached,
    );
  }
  if (live.isLiveQuote) {
    return SubscriptionPurchaseQuoteResolution(
      failure: SubscriptionQuoteFailureKind.none,
      quoteCallReached: quoteCallReached,
      quote: AuthoritativePurchaseQuote(
        productCode: code,
        quantity: quantity,
        unitExclVatCents: live.unitExclVatCents ?? live.subtotalExclVatCents!,
        subtotalExclVatCents:
            live.subtotalExclVatCents ?? live.unitExclVatCents!,
        taxTreatment: live.taxTreatment.isNotEmpty
            ? live.taxTreatment
            : fiscalTreatment,
        source: SubscriptionQuoteSource.live,
        currency: live.currency,
        vatAmountCents: live.vatAmountCents,
        totalInclVatCents: live.totalInclVatCents,
        mollieAmountCents: live.mollieAmountCents,
        quoteId: live.quoteId,
      ),
    );
  }

  // Deployed Worker has no quote route. Confirm from the server profile
  // cents already loaded with GET /company/subscription/profile. Checkout
  // start remains the charge authority and ignores any client price.
  if (live.kind == SubscriptionQuoteFailureKind.routeMissing ||
      live.kind == SubscriptionQuoteFailureKind.missingAmount ||
      live.kind == SubscriptionQuoteFailureKind.none) {
    final unit = authoritativeUnitExclCentsForProduct(
      productCode: code,
      prices: profilePrices,
    );
    if (unit == null) {
      return SubscriptionPurchaseQuoteResolution(
        failure: SubscriptionQuoteFailureKind.missingAmount,
        errorToken: 'missing_profile_amount',
        quoteCallReached: quoteCallReached,
      );
    }
    return SubscriptionPurchaseQuoteResolution(
      failure: SubscriptionQuoteFailureKind.none,
      quoteCallReached: quoteCallReached,
      quote: AuthoritativePurchaseQuote(
        productCode: code,
        quantity: quantity,
        unitExclVatCents: unit,
        subtotalExclVatCents: unit * quantity,
        taxTreatment: fiscalTreatment,
        source: SubscriptionQuoteSource.profile,
        currency: profilePrices.currency,
      ),
    );
  }

  return SubscriptionPurchaseQuoteResolution(
    failure: live.kind,
    errorToken: live.errorToken,
    statusCode: live.statusCode,
    quoteCallReached: quoteCallReached,
  );
}

String subscriptionQuoteFailureMessage({
  required String languageCode,
  required SubscriptionQuoteFailureKind kind,
  List<String> missingFiscalFields = const [],
}) {
  switch (kind) {
    case SubscriptionQuoteFailureKind.none:
      return '';
    case SubscriptionQuoteFailureKind.fiscalBlocked:
      final fields = missingFiscalFields.isEmpty
          ? ''
          : ' ${missingFiscalFields.join(', ')}';
      return _t(
        languageCode,
        nl: 'Fiscale behandeling onbekend. Checkout is geblokkeerd.$fields',
        en: 'Tax treatment unknown. Checkout is blocked.$fields',
        fr: 'Traitement fiscal inconnu. Le paiement est bloqué.$fields',
        es: 'Tratamiento fiscal desconocido. El pago está bloqueado.$fields',
      );
    case SubscriptionQuoteFailureKind.unauthorized:
    case SubscriptionQuoteFailureKind.forbidden:
      return _t(
        languageCode,
        nl: 'Je sessie is verlopen. Meld opnieuw aan.',
        en: 'Your session has expired. Please sign in again.',
        fr: 'Votre session a expiré. Veuillez vous reconnecter.',
        es: 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
      );
    case SubscriptionQuoteFailureKind.unknownProduct:
      return _t(
        languageCode,
        nl: 'Dit product kan niet worden gekocht.',
        en: 'This product cannot be purchased.',
        fr: 'Ce produit ne peut pas être acheté.',
        es: 'Este producto no se puede comprar.',
      );
    case SubscriptionQuoteFailureKind.invalidQuantity:
      return _t(
        languageCode,
        nl: 'Ongeldige hoeveelheid. Checkout is geblokkeerd.',
        en: 'Invalid quantity. Checkout is blocked.',
        fr: 'Quantité invalide. Le paiement est bloqué.',
        es: 'Cantidad no válida. El pago está bloqueado.',
      );
    case SubscriptionQuoteFailureKind.parseError:
      return _t(
        languageCode,
        nl: 'De prijsopgave kon niet worden gelezen. Probeer opnieuw.',
        en: 'The checkout quote could not be read. Please try again.',
        fr: 'Le devis n’a pas pu être lu. Réessayez.',
        es: 'No se pudo leer el presupuesto. Inténtalo de nuevo.',
      );
    case SubscriptionQuoteFailureKind.httpError:
    case SubscriptionQuoteFailureKind.networkError:
    case SubscriptionQuoteFailureKind.missingAmount:
    case SubscriptionQuoteFailureKind.routeMissing:
      return _t(
        languageCode,
        nl: 'Prijsopgave niet beschikbaar. Probeer later opnieuw.',
        en: 'Checkout quote unavailable. Please try again later.',
        fr: 'Devis indisponible. Réessayez plus tard.',
        es: 'Presupuesto no disponible. Inténtalo más tarde.',
      );
  }
}

class SubscriptionPurchaseConfirmationView {
  const SubscriptionPurchaseConfirmationView({
    required this.exclCents,
    required this.taxTreatment,
    required this.source,
    this.vatAmountCents,
    this.totalCents,
  });

  final int exclCents;
  final String taxTreatment;
  final SubscriptionQuoteSource source;
  final int? vatAmountCents;
  final int? totalCents;

  bool get showsVatAmount =>
      vatAmountCents != null || taxTreatment == 'eu_reverse_charge';

  bool get showsTotal => totalCents != null;

  bool get inventsBelgianVatAmount => false;

  bool get inventsMollieTotal => false;
}

SubscriptionPurchaseConfirmationView confirmationViewForQuote(
  AuthoritativePurchaseQuote quote,
) {
  final reverse = quote.taxTreatment == 'eu_reverse_charge';
  return SubscriptionPurchaseConfirmationView(
    exclCents: quote.subtotalExclVatCents,
    taxTreatment: quote.taxTreatment,
    source: quote.source,
    vatAmountCents: reverse ? (quote.vatAmountCents ?? 0) : quote.vatAmountCents,
    totalCents: quote.totalInclVatCents ?? quote.mollieAmountCents,
  );
}

String subscriptionConfirmTreatmentLine({
  required String languageCode,
  required String taxTreatment,
}) {
  if (taxTreatment == 'eu_reverse_charge') {
    return _t(
      languageCode,
      nl: 'Btw-behandeling: btw verlegd',
      en: 'VAT treatment: reverse charge',
      fr: 'TVA : autoliquidation',
      es: 'IVA: inversión del sujeto pasivo',
    );
  }
  return _t(
    languageCode,
    nl: 'Btw-behandeling: Belgische btw',
    en: 'VAT treatment: Belgian VAT',
    fr: 'TVA : TVA belge',
    es: 'IVA: IVA belga',
  );
}

bool isGenericQuoteUnavailableMessage(String message) {
  return message.contains('Prijsopgave niet beschikbaar') ||
      message.contains('Checkout quote unavailable');
}

String _t(
  String languageCode, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return en;
    case 'fr':
      return fr;
    case 'es':
      return es;
    case 'nl':
    default:
      return nl;
  }
}
