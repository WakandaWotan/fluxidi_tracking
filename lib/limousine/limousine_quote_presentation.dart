// User-facing limousine quote presentation. IDs, ISO timestamps and cents
// stay on the models; this layer never invents a second quote engine.

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_offers.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

const String kLimousineQuoteVatIncl = 'incl';
const String kLimousineQuoteVatExcl = 'excl';
const String kLimousineQuoteVatNone = 'none';

const Set<String> kLimousineKnownVatTreatments = <String>{
  kLimousineQuoteVatIncl,
  kLimousineQuoteVatExcl,
  kLimousineQuoteVatNone,
};

const String kLimousineDefaultQuoteCurrency = 'EUR';
const int kLimousineDefaultQuoteValidityDays = 7;

final RegExp _rawIsoTimestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');

bool limousineLooksLikeRawIsoTimestamp(String text) {
  return _rawIsoTimestamp.hasMatch(text.trim());
}

bool limousineLooksLikeRawVehicleOrOfferId(String text) {
  final token = text.trim();
  if (token.isEmpty) return false;
  return token.startsWith('vh_') ||
      token.startsWith('offer_') ||
      token.startsWith('off_') ||
      token.startsWith('limo_');
}

bool limousineLooksLikeRawServiceClassId(String text) {
  final token = text.trim();
  if (token.isEmpty || !token.contains('_')) return false;
  return limousineServiceClassById(token) != null;
}

DateTime limousineDefaultQuoteValidUntilDate([DateTime? now]) {
  final base = (now ?? DateTime.now()).toLocal();
  final start = DateTime(base.year, base.month, base.day);
  return start.add(const Duration(days: kLimousineDefaultQuoteValidityDays));
}

String limousineQuoteExpiresAtIsoFromDate(DateTime date) {
  final local = DateTime(date.year, date.month, date.day, 23, 59, 59);
  return local.toUtc().toIso8601String();
}

DateTime? limousineDateFromQuoteExpiresAt(String iso) {
  final parsed = DateTime.tryParse(iso.trim());
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return DateTime(local.year, local.month, local.day);
}

int nextLimousineTermsRevision(int existing) {
  return existing > 0 ? existing + 1 : 1;
}

LimousineCompanyQuoteDraft completeLimousineCompanyQuoteDraft(
  LimousineCompanyQuoteDraft draft, {
  int existingTermsRevision = 0,
  DateTime? now,
}) {
  final currency = limousineCurrencyOf(draft.currency).isEmpty
      ? kLimousineDefaultQuoteCurrency
      : limousineCurrencyOf(draft.currency);
  var expiresAt = draft.expiresAt.trim();
  if (expiresAt.isEmpty || DateTime.tryParse(expiresAt) == null) {
    expiresAt = limousineQuoteExpiresAtIsoFromDate(
      limousineDefaultQuoteValidUntilDate(now),
    );
  }
  final revision = (draft.termsRevision != null && draft.termsRevision! > 0)
      ? draft.termsRevision!
      : nextLimousineTermsRevision(existingTermsRevision);
  return LimousineCompanyQuoteDraft(
    totalInclVatCents: draft.totalInclVatCents,
    currency: currency,
    vatTreatment: draft.vatTreatment.trim(),
    vatRate: draft.vatRate,
    expiresAt: expiresAt,
    termsRevision: revision,
    cancellationDeadlineHours: draft.cancellationDeadlineHours ?? 0,
    cancellationPenaltyPercent: draft.cancellationPenaltyPercent ?? 0,
    waitingTimeIncludedMinutes: draft.waitingTimeIncludedMinutes ?? 0,
    waitingTimeOverageCentsPerMinute:
        draft.waitingTimeOverageCentsPerMinute ?? 0,
    noShowPenaltyPercent: draft.noShowPenaltyPercent ?? 0,
    overtimeCentsPerHour: draft.overtimeCentsPerHour ?? 0,
    publicText: draft.publicText,
    includedServices: draft.includedServices,
    paidExtras: draft.paidExtras,
    mobilisationDisclosure: draft.mobilisationDisclosure,
    customerObligations: draft.customerObligations,
    importantInformation: draft.importantInformation,
    unknownCriticalKeys: draft.unknownCriticalKeys,
  );
}

String formatLimousineEuroAmount(int cents) {
  return '€ ${limousineCentsToMajorUnits(cents).replaceAll('.', ',')}';
}

String formatLimousineUserDate(String iso, AppLanguage language) {
  final parsed = DateTime.tryParse(iso.trim());
  if (parsed == null) return '';
  return _formatLocalDate(parsed.toLocal(), language);
}

String formatLimousineUserDateTime(String iso, AppLanguage language) {
  final parsed = DateTime.tryParse(iso.trim());
  if (parsed == null) return '';
  final local = parsed.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${_formatLocalDate(local, language)} · $hh:$mm';
}

final RegExp _rawDartDateTime = RegExp(
  r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?',
);

bool limousineLooksLikeRawDartDateTime(String text) {
  return _rawDartDateTime.hasMatch(text);
}

String formatLimousineOwnCustomerDateTime(
  DateTime when,
  AppLanguage language,
) {
  final local = when.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${_formatOwnCustomerDate(local, language)} · $hh:$mm';
}

String _formatOwnCustomerDate(DateTime local, AppLanguage language) {
  if (language == AppLanguage.es) {
    return '${local.day} de ${_monthName(local, language)} de ${local.year}';
  }
  return _formatLocalDate(local, language);
}

String limousineQuoteDisplayOrEmpty(String iso, AppLanguage language) {
  final formatted = formatLimousineUserDateTime(iso, language);
  if (formatted.isNotEmpty) return formatted;
  if (limousineLooksLikeRawIsoTimestamp(iso)) return '';
  return iso.trim();
}

String _monthName(DateTime local, AppLanguage language) {
  final months = switch (language) {
    AppLanguage.fr => const [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ],
    AppLanguage.es => const [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ],
    AppLanguage.en => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
    _ => const [
      'januari',
      'februari',
      'maart',
      'april',
      'mei',
      'juni',
      'juli',
      'augustus',
      'september',
      'oktober',
      'november',
      'december',
    ],
  };
  return months[local.month - 1];
}

String _formatLocalDate(DateTime local, AppLanguage language) {
  return '${local.day} ${_monthName(local, language)} ${local.year}';
}

String limousineQuoteEnteredAmountLabel(String raw, AppLanguage language) {
  switch (raw.trim().toLowerCase()) {
    case kLimousineQuoteVatExcl:
      return kLimousineQuoteAmountExclVat.of(language);
    case kLimousineQuoteVatIncl:
      return kLimousineQuoteAmountInclVat.of(language);
    case kLimousineQuoteVatNone:
      return kLimousineQuoteAmountNoVat.of(language);
    default:
      return kLimousineQuoteTotal.of(language);
  }
}

double? limousineQuoteSubmittedVatRate(
  String treatment, {
  ActiveVatConfig? vat,
}) {
  switch (treatment.trim().toLowerCase()) {
    case kLimousineQuoteVatNone:
      return 0;
    case kLimousineQuoteVatIncl:
    case kLimousineQuoteVatExcl:
      final config = vat ?? resolveActiveVatConfig();
      return config.vatEnabled ? config.vatRate : 0;
    default:
      return null;
  }
}

String limousineVatWord(AppLanguage language) {
  switch (language) {
    case AppLanguage.en:
    case AppLanguage.de:
      return 'VAT';
    case AppLanguage.fr:
      return 'TVA';
    case AppLanguage.es:
      return 'IVA';
    case AppLanguage.nl:
      return 'BTW';
  }
}

String limousineFormatVatPercentNumber(num? rate) {
  final value = rate ?? 0;
  final percent = value <= 1 ? value * 100 : value;
  if (percent == percent.roundToDouble()) return percent.round().toString();
  return percent
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String limousineVatPercentSuffix(AppLanguage language) {
  return language == AppLanguage.fr || language == AppLanguage.es ? ' %' : '%';
}

class LimousineQuoteMoneyLine {
  const LimousineQuoteMoneyLine({
    required this.label,
    required this.cents,
    this.emphasize = false,
  });

  final String label;
  final int cents;
  final bool emphasize;
}

List<LimousineQuoteMoneyLine> limousineQuoteMoneyLines({
  required LimousineCanonicalMoney money,
  required AppLanguage language,
}) {
  final treatment = money.vatTreatment.trim().toLowerCase();
  final vatLabel = limousineVatRatePercentLabel(
    money.vatRate,
    language,
    inclusive: treatment == kLimousineQuoteVatIncl,
  );
  final entered = money.enteredCents;
  if (treatment == kLimousineQuoteVatIncl) {
    return <LimousineQuoteMoneyLine>[
      LimousineQuoteMoneyLine(
        label: kLimousineQuoteAmountInclVat.of(language),
        cents: (entered != null && entered > 0) ? entered : money.grossCents,
        emphasize: true,
      ),
      if (money.vatCents != null)
        LimousineQuoteMoneyLine(label: vatLabel, cents: money.vatCents!),
      if (money.netCents != null)
        LimousineQuoteMoneyLine(
          label: kLimousineQuoteNetAmount.of(language),
          cents: money.netCents!,
        ),
    ];
  }
  if (treatment == kLimousineQuoteVatNone) {
    return <LimousineQuoteMoneyLine>[
      LimousineQuoteMoneyLine(
        label: kLimousineQuoteAmountNoVat.of(language),
        cents: (entered != null && entered > 0) ? entered : money.grossCents,
        emphasize: true,
      ),
      LimousineQuoteMoneyLine(label: vatLabel, cents: money.vatCents ?? 0),
    ];
  }
  return <LimousineQuoteMoneyLine>[
    if (money.netCents != null)
      LimousineQuoteMoneyLine(
        label: kLimousineQuoteNetAmount.of(language),
        cents: money.netCents!,
      ),
    if (money.vatCents != null)
      LimousineQuoteMoneyLine(label: vatLabel, cents: money.vatCents!),
    LimousineQuoteMoneyLine(
      label: kLimousineQuoteGrossAmount.of(language),
      cents: money.grossCents,
      emphasize: true,
    ),
  ];
}

class LimousineCanonicalMoney {
  const LimousineCanonicalMoney({
    required this.grossCents,
    this.netCents,
    this.vatCents,
    this.enteredCents,
    this.vatRate,
    this.vatTreatment = '',
    this.currency = '',
  });

  final int grossCents;
  final int? netCents;
  final int? vatCents;
  final int? enteredCents;
  final num? vatRate;
  final String vatTreatment;
  final String currency;

  bool get hasSplit => netCents != null && vatCents != null;
}

LimousineCanonicalMoney? limousineCanonicalMoneyFromRequest(
  LimousineQuoteRequest record,
) {
  return limousineCanonicalMoneyFromStored(
    quotationGrossCents: record.quotationTotalInclVatCents,
    quotationNetCents: record.quotationTotalExVatCents,
    quotationVatCents: record.quotationVatAmountCents,
    quotationEnteredCents: record.quotationEnteredAmountCents,
    quotationVatRate: record.quotationVatRate,
    quotationVatTreatment: record.quotationVatTreatment,
    quotationCurrency: record.quotationCurrency,
    quoteGrossCents: record.quote?.totalInclVatCents,
    quoteNetCents: record.quote?.totalExVatCents,
    quoteVatCents: record.quote?.vatAmountCents,
    quoteEnteredCents: record.quote?.enteredAmountCents,
    quoteVatRate: record.quote?.vatRate,
    quoteVatTreatment: record.quote?.vatTreatment ?? '',
    quoteCurrency: record.quote?.currency ?? '',
  );
}

LimousineCanonicalMoney? limousineCanonicalMoneyFromStored({
  int? quotationGrossCents,
  int? quotationNetCents,
  int? quotationVatCents,
  int? quotationEnteredCents,
  num? quotationVatRate,
  String quotationVatTreatment = '',
  String quotationCurrency = '',
  int? quoteGrossCents,
  int? quoteNetCents,
  int? quoteVatCents,
  int? quoteEnteredCents,
  num? quoteVatRate,
  String quoteVatTreatment = '',
  String quoteCurrency = '',
}) {
  final gross = quotationGrossCents ?? quoteGrossCents;
  if (gross == null || gross <= 0) return null;
  return LimousineCanonicalMoney(
    grossCents: gross,
    netCents: quotationNetCents ?? quoteNetCents,
    vatCents: quotationVatCents ?? quoteVatCents,
    enteredCents: quotationEnteredCents ?? quoteEnteredCents,
    vatRate: quotationVatRate ?? quoteVatRate,
    vatTreatment: quotationVatTreatment.trim().isNotEmpty
        ? quotationVatTreatment
        : quoteVatTreatment,
    currency: quotationCurrency.trim().isNotEmpty
        ? quotationCurrency
        : quoteCurrency,
  );
}

Map<String, dynamic> _asLooseMap(Object? raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

num? limousineReadVatRate(Object? raw) {
  num? parsed;
  if (raw is num && raw.isFinite) {
    parsed = raw;
  } else if (raw is String) {
    parsed = num.tryParse(raw.trim().replaceAll(',', '.'));
  }
  if (parsed == null || !parsed.isFinite) return null;
  return parsed > 1 ? parsed / 100 : parsed;
}

int? limousineReadCents(Object? cents, [Object? euro]) {
  if (cents is int) return cents;
  if (cents is num && cents.isFinite) return cents.round();
  if (cents is String) {
    final parsed = int.tryParse(cents.trim());
    if (parsed != null) return parsed;
  }
  num? major;
  if (euro is num && euro.isFinite) {
    major = euro;
  } else if (euro is String) {
    major = num.tryParse(euro.trim().replaceAll(',', '.'));
  }
  if (major == null || !major.isFinite) return null;
  return (major * 100).round();
}

bool limousineBookingHasFrozenAcceptedPrice(Map<String, dynamic> details) {
  final service = (details['service_type'] ?? details['serviceType'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (service == 'limousine') return true;
  final quote = _asLooseMap(details['quote']);
  return quote['limousine_accepted_price'] is Map ||
      details['limousine_accepted_price'] is Map;
}

LimousineCanonicalMoney? limousineCanonicalMoneyFromBookingDetails(
  Map<String, dynamic> details,
) {
  final quote = _asLooseMap(details['quote']);
  final booking = _asLooseMap(details['booking']);
  final record = _asLooseMap(details['record']);
  final accepted = _asLooseMap(
    quote['limousine_accepted_price'] ??
        details['limousine_accepted_price'] ??
        booking['limousine_accepted_price'] ??
        _asLooseMap(booking['quote'])['limousine_accepted_price'] ??
        _asLooseMap(record['quote'])['limousine_accepted_price'],
  );
  final pricing = _asLooseMap(quote['pricing']);
  final src = accepted.isNotEmpty
      ? accepted
      : (pricing.isNotEmpty ? pricing : details);
  final gross = limousineReadCents(
    src['total_incl_vat_cents'] ?? src['totalInclVatCents'],
    src['price_incl_vat'] ??
        src['priceInclVat'] ??
        details['price_incl_vat'] ??
        details['total'],
  );
  if (gross == null || gross <= 0) return null;
  return LimousineCanonicalMoney(
    grossCents: gross,
    netCents: limousineReadCents(
      src['total_ex_vat_cents'] ?? src['totalExVatCents'],
      src['price_ex_vat'] ??
          src['priceExVat'] ??
          details['price_ex_vat'] ??
          details['subtotal_ex_vat'],
    ),
    vatCents: limousineReadCents(
      src['vat_amount_cents'] ?? src['vatAmountCents'],
      src['price_vat'] ??
          src['priceVat'] ??
          details['price_vat'] ??
          details['vat_amount'],
    ),
    enteredCents: limousineReadCents(
      src['entered_amount_cents'] ?? src['enteredAmountCents'],
    ),
    vatRate: limousineReadVatRate(
      src['vat_rate'] ??
          src['vatRate'] ??
          details['vat_rate'] ??
          details['vatRate'] ??
          quote['vat_rate'],
    ),
    vatTreatment:
        (src['vat_treatment'] ??
                src['vatTreatment'] ??
                details['vat_treatment'] ??
                quote['vat_treatment'] ??
                '')
            .toString(),
    currency: (src['currency'] ?? details['currency'] ?? 'EUR').toString(),
  );
}

bool limousineDisplayedVatMatchesFrozenRate(LimousineCanonicalMoney money) {
  final rate = money.vatRate;
  final net = money.netCents;
  final vat = money.vatCents;
  final gross = money.grossCents;
  if (rate == null || net == null || vat == null) return false;
  if (net + vat != gross) return false;
  final expectedVat = ((net / 100.0) * rate * 100).round();
  return expectedVat == vat;
}

String limousineVatRatePercentLabel(
  num? rate,
  AppLanguage language, {
  bool inclusive = false,
}) {
  final shown = limousineFormatVatPercentNumber(rate);
  final rateText =
      '${limousineVatWord(language)} $shown${limousineVatPercentSuffix(language)}';
  if (!inclusive) return rateText;
  switch (language) {
    case AppLanguage.en:
    case AppLanguage.de:
      return 'Of which $rateText';
    case AppLanguage.fr:
      return 'Dont $rateText';
    case AppLanguage.es:
      return 'De los cuales $rateText';
    case AppLanguage.nl:
      return 'Waarvan $rateText';
  }
}

String limousineVatTreatmentLabel(String raw, AppLanguage language) {
  switch (raw.trim().toLowerCase()) {
    case kLimousineQuoteVatIncl:
      return kLimousineQuoteVatInclLabel.of(language);
    case kLimousineQuoteVatExcl:
      return kLimousineQuoteVatExclLabel.of(language);
    case kLimousineQuoteVatNone:
      return kLimousineQuoteVatNoneLabel.of(language);
    default:
      return '';
  }
}

String limousineQuoteServiceClassDisplay(
  String serviceClassId,
  AppLanguage language,
) {
  return limousineServiceClassLabel(serviceClassId, language);
}

String limousineQuoteVehicleDisplay(
  LimousineQuoteRequest record,
  AppLanguage language,
) {
  if (record.publicVehicleName.trim().isNotEmpty) {
    return record.publicVehicleName.trim();
  }
  return limousineQuoteServiceClassDisplay(record.serviceClassId, language);
}

String limousineQuoteOfferDisplay(
  LimousineQuoteRequest record,
  AppLanguage language,
) {
  final snap = record.pricingSnapshot;
  final titleRaw = snap['title'] ?? snap['public_title'] ?? snap['publicTitle'];
  if (titleRaw is Map) {
    final localized = localizedLimousineText(
      titleRaw.map((key, value) => MapEntry(key.toString(), '$value')),
      languageCode: language.name,
    );
    if (localized.isNotEmpty) return localized;
  }
  final name = (snap['name'] ?? snap['offer_title'] ?? '').toString().trim();
  if (name.isNotEmpty && !limousineLooksLikeRawVehicleOrOfferId(name)) {
    return name;
  }
  return '';
}

String limousineQuoteFieldErrorLabel(String key, AppLanguage language) {
  switch (key) {
    case 'total_incl_vat_cents':
      return kLimousineQuoteTotalRequired.of(language);
    case 'vat_treatment':
      return kLimousineQuoteVatRequired.of(language);
    case 'expires_at':
      return kLimousineQuoteExpiresRequired.of(language);
    case 'currency':
      return kLimousineQuoteCurrencyRequired.of(language);
    default:
      return kLimousineQuoteFieldLabels[key]?.of(language) ?? key;
  }
}

String limousineCustomerRequestReceivedLabel(
  AppLanguage language, {
  String companyName = '',
}) {
  final name = companyName.trim();
  if (name.isEmpty) {
    return kLimousineQuoteSubmittedReceivedFallback.of(language);
  }
  return kLimousineQuoteSubmittedReceived
      .of(language)
      .replaceAll('{company}', name);
}

String limousineCustomerQuoteFromCompanyLabel(
  AppLanguage language, {
  String companyName = '',
}) {
  final name = companyName.trim();
  if (name.isEmpty) {
    return kLimousineCustomerQuoteFromCompanyFallback.of(language);
  }
  return kLimousineCustomerQuoteFromCompany
      .of(language)
      .replaceAll('{company}', name);
}

bool limousineOptionalTermIsSet(int? value) => value != null && value > 0;
