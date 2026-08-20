// LIMOUSINE-OPERATIONAL-HANDOFF-P3B — presentation helpers on existing
// quote-inbox, company-bookings and customer-booking surfaces.

import '../app_strings.dart';
import 'limousine_unified_intent.dart';

const LocalizedText kLimousineOperationalOccasion = LocalizedText(
  nl: 'Gelegenheid',
  en: 'Occasion',
  fr: 'Occasion',
  es: 'Ocasión',
);

const LocalizedText kLimousineOperationalDuration = LocalizedText(
  nl: 'Duur',
  en: 'Duration',
  fr: 'Durée',
  es: 'Duración',
);

const LocalizedText kLimousineOperationalPricingMode = LocalizedText(
  nl: 'Prijsmode',
  en: 'Pricing mode',
  fr: 'Mode de tarif',
  es: 'Modo de precio',
);

const LocalizedText kLimousineOperationalFromPriceAudit = LocalizedText(
  nl: 'Vanafprijs (informatief)',
  en: 'From-price (informational)',
  fr: 'Prix à partir de (indicatif)',
  es: 'Precio desde (informativo)',
);

const LocalizedText kLimousineOperationalRequestPending = LocalizedText(
  nl: 'Boekingsaanvraag in behandeling',
  en: 'Booking request pending',
  fr: 'Demande de réservation en cours',
  es: 'Solicitud de reserva pendiente',
);

const LocalizedText kLimousineOperationalConfirmRequest = LocalizedText(
  nl: 'Bevestig aanvraag',
  en: 'Confirm request',
  fr: 'Confirmer la demande',
  es: 'Confirmar solicitud',
);

const LocalizedText kLimousineOperationalServiceBadge = LocalizedText(
  nl: 'Limousine',
  en: 'Limousine',
  fr: 'Limousine',
  es: 'Limusina',
);

const LocalizedText kLimousineOperationalSnapshotKept = LocalizedText(
  nl: 'Onveranderlijke prijssnapshot',
  en: 'Immutable pricing snapshot',
  fr: 'Snapshot de prix immuable',
  es: 'Snapshot de precio inmutable',
);

const LocalizedText kLimousinePricingModeQuoteRequired = LocalizedText(
  nl: 'Prijs op aanvraag',
  en: 'Quote required',
  fr: 'Sur devis',
  es: 'Presupuesto requerido',
);

const LocalizedText kLimousinePricingModeFromPrice = LocalizedText(
  nl: 'Vanafprijs',
  en: 'From-price',
  fr: 'À partir de',
  es: 'Desde',
);

const LocalizedText kLimousinePricingModeExactFixed = LocalizedText(
  nl: 'Vaste prijs',
  en: 'Fixed price',
  fr: 'Prix fixe',
  es: 'Precio fijo',
);

const LocalizedText kLimousinePricingModeHourly = LocalizedText(
  nl: 'Uurprijs',
  en: 'Hourly',
  fr: 'Horaire',
  es: 'Por hora',
);

const LocalizedText kLimousinePricingModePackage = LocalizedText(
  nl: 'Pakket',
  en: 'Package',
  fr: 'Forfait',
  es: 'Paquete',
);

bool isLimousineServiceType(String? raw) {
  return (raw ?? '').trim().toLowerCase() == kLimousineServiceType;
}

bool limousineCompanyConfirmationRequired(Map<String, dynamic>? raw) {
  if (raw == null) return false;
  return raw['company_confirmation_required'] == true ||
      raw['companyConfirmationRequired'] == true;
}

int? limousineSnapshotFromPriceCents(Map<String, dynamic>? snapshot) {
  if (snapshot == null) return null;
  final value =
      snapshot['from_price_cents'] ??
      snapshot['fromPriceCents'] ??
      snapshot['display_amount_cents'] ??
      snapshot['displayAmountCents'];
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

String limousinePricingModeLabel(String raw, AppLanguage language) {
  switch (raw.trim().toLowerCase()) {
    case 'from_price':
    case 'fromprice':
    case 'indicative':
      return kLimousinePricingModeFromPrice.of(language);
    case 'exact_fixed':
    case 'fixed':
      return kLimousinePricingModeExactFixed.of(language);
    case 'hourly':
      return kLimousinePricingModeHourly.of(language);
    case 'package':
      return kLimousinePricingModePackage.of(language);
    case 'quote_required':
    case 'manual_quote':
    case 'quote':
      return kLimousinePricingModeQuoteRequired.of(language);
    default:
      return raw.trim();
  }
}

String limousineDurationLabel(int? minutes, AppLanguage language) {
  if (minutes == null || minutes <= 0) return '';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours > 0 && rest == 0) return '${hours}u';
  if (hours > 0) return '${hours}u ${rest}m';
  return '${minutes}m';
}

class LimousineCompanyBookingPresentation {
  const LimousineCompanyBookingPresentation({
    required this.serviceType,
    required this.pricingMode,
    required this.occasion,
    this.requestedDurationMinutes,
    required this.companyConfirmationRequired,
    this.pricingSnapshot = const <String, dynamic>{},
  });

  final String serviceType;
  final String pricingMode;
  final String occasion;
  final int? requestedDurationMinutes;
  final bool companyConfirmationRequired;
  final Map<String, dynamic> pricingSnapshot;

  bool get isLimousine => isLimousineServiceType(serviceType);
  bool get canConfirmOnExistingStatus =>
      isLimousine && companyConfirmationRequired;

  factory LimousineCompanyBookingPresentation.fromMap(Map<String, dynamic> raw) {
    Object? at(String key) => raw[key] ?? raw[_camel(key)];
    String text(Object? value) => value?.toString().trim() ?? '';
    final snapshotRaw = at('pricing_snapshot') ?? at('limousine_accepted_price');
    return LimousineCompanyBookingPresentation(
      serviceType: text(at('service_type')),
      pricingMode: text(at('pricing_mode')),
      occasion: text(at('occasion')),
      requestedDurationMinutes: _asInt(at('requested_duration_minutes')),
      companyConfirmationRequired:
          at('company_confirmation_required') == true,
      pricingSnapshot: snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : const <String, dynamic>{},
    );
  }

  static String _camel(String key) {
    final parts = key.split('_');
    if (parts.length < 2) return key;
    return parts.first +
        parts.skip(1).map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}').join();
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

String limousineMoneyCents(int? cents, {String currency = 'EUR'}) {
  if (cents == null) return '';
  final amount = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
  final symbol = currency.toUpperCase() == 'EUR' ? '€' : '$currency ';
  return '$symbol$amount';
}
