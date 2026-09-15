// COMPANY-CUSTOMER-OPS-P0 — company address field on the existing Mapbox seam.
// Saved addresses appear only as focus suggestions, never as chips or labels.

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

Key companySavedAddressSuggestionKey(String fieldId, int index) =>
    Key('company_saved_address_${fieldId}_$index');

LimousineUxTokens companyLimousineUxTokens() {
  return LimousineUxTokens.fromBusiness(
    paletteForBusinessTheme(businessThemeNotifier.value),
  );
}

String companyCustomerAddressLine(CompanyCustomerAddress address) {
  return companyPlanCanonicalAddressLine(
    street: address.line1,
    line2: address.line2,
    postalCode: address.postalCode,
    city: address.city,
    country: address.countryCode,
    fallback: address.label,
  );
}

class CompanyPlanCanonicalAddress {
  const CompanyPlanCanonicalAddress({
    this.street = '',
    this.houseNumber = '',
    this.postalCode = '',
    this.city = '',
    this.country = '',
    this.lat,
    this.lon,
    this.placeId = '',
    this.displayText = '',
  });

  final String street;
  final String houseNumber;
  final String postalCode;
  final String city;
  final String country;
  final double? lat;
  final double? lon;
  final String placeId;
  final String displayText;

  String get fullLine => displayText.trim().isNotEmpty
      ? displayText.trim()
      : companyPlanCanonicalAddressLine(
          street: street,
          houseNumber: houseNumber,
          postalCode: postalCode,
          city: city,
          country: country,
        );
}

String companyPlanCanonicalAddressLine({
  String street = '',
  String houseNumber = '',
  String line2 = '',
  String postalCode = '',
  String city = '',
  String country = '',
  String fallback = '',
}) {
  final streetLine = <String>[
    street.trim(),
    houseNumber.trim(),
    line2.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  final locality = <String>[
    postalCode.trim(),
    city.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  final line = <String>[
    if (streetLine.isNotEmpty) streetLine,
    if (locality.isNotEmpty) locality,
    if (country.trim().isNotEmpty) country.trim(),
  ].join(', ');
  return line.isEmpty ? fallback.trim() : line;
}

CompanyPlanCanonicalAddress parseCompanyPlanCanonicalAddress(
  String raw, {
  double? lat,
  double? lon,
  String placeId = '',
}) {
  final text = raw.trim();
  if (text.isEmpty) {
    return CompanyPlanCanonicalAddress(lat: lat, lon: lon, placeId: placeId);
  }
  final parts = text.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  var street = '';
  var houseNumber = '';
  var postalCode = '';
  var city = '';
  var country = '';
  if (parts.isNotEmpty) {
    final streetMatch = RegExp(
      r'^(.*?)[\s,]+(\d+[A-Za-z]?)$',
    ).firstMatch(parts.first);
    if (streetMatch != null) {
      street = streetMatch.group(1)!.trim();
      houseNumber = streetMatch.group(2)!.trim();
    } else {
      street = parts.first;
    }
  }
  if (parts.length >= 2) {
    final locality = RegExp(r'^(\d{4})\s+(.+)$').firstMatch(parts[1]);
    if (locality != null) {
      postalCode = locality.group(1)!;
      city = locality.group(2)!.trim();
    } else if (RegExp(r'^\d{4}$').hasMatch(parts[1])) {
      postalCode = parts[1];
      if (parts.length >= 3) city = parts[2];
    } else {
      city = parts[1];
    }
  }
  if (parts.length >= 3 && country.isEmpty && postalCode.isNotEmpty) {
    country = parts.last;
  } else if (parts.length >= 3 && city.isNotEmpty && parts.last != city) {
    country = parts.last;
  }
  return CompanyPlanCanonicalAddress(
    street: street,
    houseNumber: houseNumber,
    postalCode: postalCode,
    city: city,
    country: country,
    lat: lat,
    lon: lon,
    placeId: placeId,
    displayText: text,
  );
}

String companyCustomerAddressChoiceLabel(CompanyCustomerAddress address) {
  final line = companyCustomerAddressLine(address);
  if (line.isEmpty) return address.label.trim();
  if (address.label.trim().isEmpty) return line;
  return '${address.label.trim()} · $line';
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
  final line = companyCustomerAddressLine(address);
  final label = line.isEmpty ? address.label.trim() : line;
  final hasCoords = address.lat != null &&
      address.lon != null &&
      address.lat!.isFinite &&
      address.lon!.isFinite;
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: label,
    lat: hasCoords ? address.lat : null,
    lon: hasCoords ? address.lon : null,
    acceptance: hasCoords
        ? LimousineAddressAcceptance.selected
        : LimousineAddressAcceptance.manualFallback,
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
      lat != null && lon != null && lat.isFinite && lon.isFinite;
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

LimousineAddressValue companyAddressWithCoords(
  LimousineAddressValue value, {
  double? lat,
  double? lon,
}) {
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
    return value;
  }
  final text = value.routeText.isEmpty ? value.displayText : value.routeText;
  return LimousineAddressValue(
    displayText: text,
    canonicalLabel: value.canonicalLabel.trim().isEmpty
        ? text
        : value.canonicalLabel,
    lat: lat,
    lon: lon,
    placeId: value.placeId,
    acceptance: LimousineAddressAcceptance.selected,
    fromCurrentLocation: value.fromCurrentLocation,
  );
}

Future<void> companyAddressGeocodeIfNeeded(
  LimousineAddressFieldController controller,
) async {
  final value = controller.value;
  if (value.lat != null && value.lon != null) return;
  final query = value.routeText.trim().isEmpty
      ? value.displayText.trim()
      : value.routeText.trim();
  if (query.length < kLimousineAddressMinQueryLength) return;
  final result = await controller.lookup.search(
    query,
    language: controller.language,
  );
  if (controller.textController.text.trim() != query) return;
  final best = limousinePreferStreetLevelSuggestion(query, result.suggestions);
  if (best == null || !best.hasCoordinates) return;
  final kept = limousinePreferCanonicalLabel(
    original: query,
    suggestion: best.label,
  );
  controller.acceptCopy(
    LimousineAddressValue(
      displayText: kept,
      canonicalLabel: kept,
      lat: best.lat,
      lon: best.lon,
      placeId: best.placeId,
      acceptance: LimousineAddressAcceptance.selected,
    ),
  );
}

class CompanyAddressField extends StatefulWidget {
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
  State<CompanyAddressField> createState() => _CompanyAddressFieldState();
}

class _CompanyAddressFieldState extends State<CompanyAddressField> {
  bool _focused = false;

  List<CompanyCustomerAddress> get _visibleSaved {
    if (!_focused || widget.savedAddresses.isEmpty) {
      return const <CompanyCustomerAddress>[];
    }
    if (widget.controller.suggestions.isNotEmpty) {
      return const <CompanyCustomerAddress>[];
    }
    final needle = widget.controller.textController.text.trim().toLowerCase();
    if (needle.isEmpty) return widget.savedAddresses;
    return [
      for (final address in widget.savedAddresses)
        if (companyCustomerAddressChoiceLabel(address)
            .toLowerCase()
            .contains(needle))
          address,
    ];
  }

  Future<void> _pickSaved(CompanyCustomerAddress address) async {
    widget.controller.acceptCopy(companyAddressValueFromSaved(address));
    setState(() => _focused = false);
    await companyAddressGeocodeIfNeeded(widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = companyLimousineUxTokens();
    return Focus(
      onFocusChange: (hasFocus) {
        if (!mounted) return;
        setState(() => _focused = hasFocus);
      },
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final saved = _visibleSaved;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LimousineAddressField(
                controller: widget.controller,
                label: widget.label,
                tokens: tokens,
                language: widget.language,
                inputKey: widget.inputKey,
                showCanonicalEcho: false,
              ),
              if (saved.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    border: Border.all(color: tokens.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: saved.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: tokens.border),
                    itemBuilder: (context, index) {
                      final address = saved[index];
                      return ListTile(
                        key: companySavedAddressSuggestionKey(
                          widget.controller.fieldId,
                          index,
                        ),
                        dense: true,
                        title: Text(companyCustomerAddressLine(address).isEmpty
                            ? address.label
                            : companyCustomerAddressLine(address)),
                        onTap: () => _pickSaved(address),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
