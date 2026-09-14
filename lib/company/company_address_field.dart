// COMPANY-CUSTOMER-OPS-P0 — company address field on the existing Mapbox seam.
// Reuses LimousineAddressField: debounce, request id, stale skip, loading /
// empty / error, and manual fallback that is never marked selected.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';

const LocalizedText kCompanySavedAddresses = LocalizedText(
  nl: 'Opgeslagen adressen',
  en: 'Saved addresses',
  fr: 'Adresses enregistrées',
  es: 'Direcciones guardadas',
);

LimousineUxTokens companyLimousineUxTokens() {
  return LimousineUxTokens.fromBusiness(
    paletteForBusinessTheme(businessThemeNotifier.value),
  );
}

String companyCustomerAddressChoiceLabel(CompanyCustomerAddress address) {
  final street = <String>[
    address.line1.trim(),
    address.line2.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  final locality = <String>[
    address.postalCode.trim(),
    address.city.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  final parts = <String>[
    if (street.isNotEmpty) street,
    if (locality.isNotEmpty) locality,
    if (address.countryCode.trim().isNotEmpty) address.countryCode.trim(),
  ];
  if (parts.isEmpty) return address.label.trim();
  if (address.label.trim().isEmpty) return parts.join(', ');
  return '${address.label.trim()} · ${parts.join(', ')}';
}

bool companyAddressIsComplete(LimousineAddressValue value) {
  return value.acceptance == LimousineAddressAcceptance.selected ||
      value.acceptance == LimousineAddressAcceptance.manualFallback;
}

LocalizedText companyAddressAcceptanceLabel(LimousineAddressAcceptance acceptance) {
  switch (acceptance) {
    case LimousineAddressAcceptance.selected:
      return kCompanyCustomerQuoteAddressSuggested;
    case LimousineAddressAcceptance.manualFallback:
      return kCompanyCustomerQuoteAddressManual;
    case LimousineAddressAcceptance.incomplete:
    case LimousineAddressAcceptance.empty:
      return kCompanyCustomerQuoteAddressIncomplete;
  }
}

String companyAddressReviewLine(
  LimousineAddressValue value,
  AppLanguage language,
) {
  final text = value.displayText.trim();
  final kind = companyAddressAcceptanceLabel(value.acceptance).of(language);
  if (text.isEmpty) return kind;
  return '$text · $kind';
}

LimousineAddressValue companyAddressValueFromSaved(
  CompanyCustomerAddress address,
) {
  final label = companyCustomerAddressChoiceLabel(address);
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: label,
    acceptance: LimousineAddressAcceptance.manualFallback,
  );
}

LimousineAddressValue companyAddressValueFromStored({
  required String text,
  double? lat,
  double? lon,
  String? placeId,
}) {
  final display = text.trim();
  if (display.isEmpty) return const LimousineAddressValue();
  final hasCoords =
      lat != null &&
      lon != null &&
      lat.isFinite &&
      lon.isFinite;
  return LimousineAddressValue(
    displayText: display,
    canonicalLabel: display,
    lat: hasCoords ? lat : null,
    lon: hasCoords ? lon : null,
    placeId: (placeId ?? '').trim().isEmpty ? null : placeId!.trim(),
    acceptance: hasCoords
        ? LimousineAddressAcceptance.selected
        : limousineAddressAllowsManualFallback(display)
            ? LimousineAddressAcceptance.manualFallback
            : LimousineAddressAcceptance.incomplete,
  );
}

class CompanyAddressField extends StatelessWidget {
  const CompanyAddressField({
    super.key,
    required this.controller,
    required this.label,
    required this.language,
    this.inputKey,
    this.savedAddresses = const <CompanyCustomerAddress>[],
  });

  final LimousineAddressFieldController controller;
  final String label;
  final AppLanguage language;
  final Key? inputKey;
  final List<CompanyCustomerAddress> savedAddresses;

  @override
  Widget build(BuildContext context) {
    final tokens = companyLimousineUxTokens();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (savedAddresses.isNotEmpty) ...[
          Text(
            kCompanySavedAddresses.of(language),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final address in savedAddresses)
                ActionChip(
                  label: Text(companyCustomerAddressChoiceLabel(address)),
                  onPressed: () =>
                      controller.acceptCopy(companyAddressValueFromSaved(address)),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        LimousineAddressField(
          controller: controller,
          label: label,
          tokens: tokens,
          language: language,
          inputKey: inputKey,
        ),
      ],
    );
  }
}
