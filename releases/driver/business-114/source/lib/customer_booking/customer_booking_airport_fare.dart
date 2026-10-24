import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';

/// Public contact of the company currently chosen for this ride.
class CustomerBookingPublicContact {
  const CustomerBookingPublicContact({
    this.phone = '',
    this.email = '',
    this.website = '',
  });

  final String phone;
  final String email;
  final String website;

  bool get hasAny =>
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      website.trim().isNotEmpty;
}

String _publicText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = (source[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

Map<String, dynamic> _publicContactMap(Map<String, dynamic> profile) {
  final raw = profile['public_contact'] ?? profile['publicContact'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

/// Reads only the published contact block. Private company or customer
/// numbers are not a fallback.
CustomerBookingPublicContact customerBookingPublicContactFromProfile(
  Map<String, dynamic> profile,
) {
  final contact = _publicContactMap(profile);
  final phone = _publicText(contact, const <String>[
    'public_phone',
    'publicPhone',
  ]);
  final email = _publicText(contact, const <String>[
    'booking_email',
    'bookingEmail',
    'public_email',
    'publicEmail',
  ]);
  final website = _publicText(contact, const <String>['website']);
  final usableEmail = email.contains('@') ? email : '';
  final usableWebsite =
      website.startsWith('https://') || website.startsWith('http://')
      ? website
      : '';
  return CustomerBookingPublicContact(
    phone: phone,
    email: usableEmail,
    website: usableWebsite,
  );
}

String customerBookingAirportFareBody(
  AppLanguage language,
  String companyName, {
  String quoteReason = '',
}) {
  final name = companyName.trim().isEmpty
      ? kCustomerBookingAirportFareCompanyFallback.of(language)
      : companyName.trim();
  final copy = quoteReason == 'taxi_outside_work_area'
      ? kCustomerBookingOutsideAreaFareBody
      : quoteReason == 'taxi_work_area_unverified'
      ? kCustomerBookingUnknownAreaFareBody
      : kCustomerBookingAirportFareBody;
  return copy.of(language).replaceAll('{company}', name);
}

/// Keeps the route and drops every amount after the server refuses an old quote.
CompanyPlanQuoteResult customerBookingAirportContactQuote(
  CompanyPlanQuoteResult? previous, {
  String quoteReason = '',
}) {
  final prior = previous;
  return companyPlanQuoteDropBillableFare(
    CompanyPlanQuoteResult(
      fingerprint: prior?.fingerprint ?? 'request_quote_required',
      distanceKm: prior?.distanceKm,
      durationMin: prior?.durationMin,
      currency: prior == null || prior.currency.trim().isEmpty
          ? 'EUR'
          : prior.currency,
      requestQuoteRequired: true,
      quoteReason: quoteReason.isNotEmpty
          ? quoteReason
          : prior == null || prior.quoteReason.trim().isEmpty
          ? kCompanyPlanNoFixedAirportFare
          : prior.quoteReason,
      customerAction: prior == null || prior.customerAction.trim().isEmpty
          ? kCompanyPlanContactCompanyAction
          : prior.customerAction,
      priceLabel: prior == null || prior.priceLabel.trim().isEmpty
          ? 'Prijs op aanvraag'
          : prior.priceLabel,
      conditionCodes: prior?.conditionCodes ?? const <String>[],
      leadTimeLabel: prior?.leadTimeLabel ?? '',
      pickupLat: prior?.pickupLat,
      pickupLon: prior?.pickupLon,
      dropoffLat: prior?.dropoffLat,
      dropoffLon: prior?.dropoffLon,
      returnDistanceKm: prior?.returnDistanceKm,
      returnDurationMin: prior?.returnDurationMin,
      returnPickupLat: prior?.returnPickupLat,
      returnPickupLon: prior?.returnPickupLon,
      returnDropoffLat: prior?.returnDropoffLat,
      returnDropoffLon: prior?.returnDropoffLon,
    ),
  );
}

String customerBookingAirportFareCompactBody(
  AppLanguage language,
  String reason,
) {
  final text = reason == 'taxi_outside_work_area'
      ? const LocalizedText(
          nl: 'Buiten het werkgebied',
          en: 'Outside the service area',
          fr: 'Hors zone de service',
          es: 'Fuera de la zona de servicio',
          de: 'Außerhalb des Servicegebiets',
        )
      : reason == 'taxi_work_area_unverified'
      ? const LocalizedText(
          nl: 'Werkgebied nog niet bevestigd',
          en: 'Service area not confirmed',
          fr: 'Zone de service non confirmée',
          es: 'Zona de servicio sin confirmar',
          de: 'Servicegebiet nicht bestätigt',
        )
      : const LocalizedText(
          nl: 'Geen vast luchthaventarief',
          en: 'No fixed airport fare',
          fr: 'Pas de tarif aéroport fixe',
          es: 'Sin tarifa fija de aeropuerto',
          de: 'Kein fester Flughafentarif',
        );
  return text.of(language);
}

class CustomerBookingAirportFareNotice extends StatelessWidget {
  const CustomerBookingAirportFareNotice({
    super.key,
    required this.language,
    required this.companyName,
    required this.onContact,
    this.leadTimeLabel = '',
    this.showLeadTime = false,
    this.quoteReason = '',
  });
  final AppLanguage language;
  final String companyName;
  final VoidCallback onContact;
  final String leadTimeLabel;
  final bool showLeadTime;
  final String quoteReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lead = leadTimeLabel.trim().isNotEmpty
        ? leadTimeLabel.trim()
        : kCustomerBookingAirportLeadTime.of(language);
    final contact = const LocalizedText(
      nl: 'Contact',
      en: 'Contact',
      fr: 'Contact',
      es: 'Contacto',
      de: 'Kontakt',
    ).of(language);
    final body = customerBookingAirportFareBody(
      language,
      companyName,
      quoteReason: quoteReason,
    );
    return Column(
      key: kCustomerBookingAirportFareNoticeKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kCustomerBookingPriceOnRequest.of(language),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(body),
                          if (showLeadTime) ...[
                            const SizedBox(height: 8),
                            Text(lead),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kCustomerBookingPriceOnRequest.of(language),
                        key: kCustomerBookingPriceKey,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              customerBookingAirportFareCompactBody(
                                language,
                                quoteReason,
                              ),
                              key: kCustomerBookingAirportFareBodyKey,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: kCustomerBookingAirportContactKey,
              onPressed: onContact,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 44),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(contact),
            ),
          ],
        ),
        if (showLeadTime) ...[
          const SizedBox(height: 4),
          Text(
            lead,
            key: kCustomerBookingAirportLeadTimeKey,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
          ),
        ],
      ],
    );
  }
}
