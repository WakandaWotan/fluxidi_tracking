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

final RegExp _rawIsoTimestamp = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}',
);

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

String limousineQuoteDisplayOrEmpty(String iso, AppLanguage language) {
  final formatted = formatLimousineUserDateTime(iso, language);
  if (formatted.isNotEmpty) return formatted;
  if (limousineLooksLikeRawIsoTimestamp(iso)) return '';
  return iso.trim();
}

String _formatLocalDate(DateTime local, AppLanguage language) {
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
  return '${local.day} ${months[local.month - 1]} ${local.year}';
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
