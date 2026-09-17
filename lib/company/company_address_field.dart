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

const LocalizedText kCompanyAddressNeedsConfirm = LocalizedText(
  nl: 'Dit adres kon niet tot op huisnummer worden geplaatst. Controleer straat, huisnummer en de pin op de kaart.',
  en: 'This address could not be placed to house-number accuracy. Check the street, house number and map pin.',
  fr: 'Cette adresse n’a pas pu être placée au numéro de maison. Vérifiez la rue, le numéro et l’épingle de la carte.',
  es: 'Esta dirección no se pudo situar hasta el número de casa. Comprueba la calle, el número y el pin del mapa.',
);

const LocalizedText kCompanyAddressConfirmMap = LocalizedText(
  nl: 'Bevestig deze kaartlocatie',
  en: 'Confirm this map location',
  fr: 'Confirmer cet emplacement',
  es: 'Confirmar esta ubicación',
);

Key companyAddressConfirmKey(String fieldId) =>
    Key('company_address_confirm_$fieldId');

Key companyAddressConfirmMapKey(String fieldId) =>
    Key('company_address_confirm_map_$fieldId');

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
  final street = address.line1.trim().isNotEmpty
      ? address.line1
      : companyCustomerStreetFromLabel(address.label);
  return companyPlanCanonicalAddressLine(
    street: street,
    line2: address.line2,
    postalCode: address.postalCode,
    city: address.city,
    country: address.countryCode,
    fallback: address.label,
  );
}

/// A dossier label such as "Thuis" is not a street. A label that already
/// names a numbered street may fill in a record that only stored locality.
String companyCustomerStreetFromLabel(String raw) {
  final label = raw.trim();
  if (label.isEmpty) return '';
  if (limousineAddressLooksLikeLocalityOnly(label)) return '';
  if (!limousineAddressHasStreetNumber(label)) return '';
  return label;
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

String companyAddressNormalizedToken(String raw) {
  return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

bool companyAddressSuggestionMatchesQuery(String query, String suggestion) {
  final original = companyAddressNormalizedToken(query);
  final label = companyAddressNormalizedToken(suggestion);
  if (original.isEmpty || label.isEmpty) return false;
  if (label.contains(original) || original.contains(label)) return true;
  final street = original.split(RegExp(r'\d')).first.trim();
  return street.length >= 4 && label.contains(street);
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
  CompanyCustomerAddress address, {
  bool trustStoredCoordinates = true,
}) {
  final line = companyCustomerAddressLine(address);
  final label = line.isEmpty ? address.label.trim() : line;
  final hasCoords = trustStoredCoordinates &&
      address.lat != null &&
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

Future<LimousineOwnedAddressResolution> companyAddressGeocodeIfNeeded(
  LimousineAddressFieldController controller,
) async {
  final value = controller.value;
  final query = value.routeText.trim().isEmpty
      ? value.displayText.trim()
      : value.routeText.trim();
  if (query.length < kLimousineAddressMinQueryLength) {
    return LimousineOwnedAddressResolution(value: value);
  }
  if (value.hasCoordinates && !controller.locationNeedsConfirm) {
    return LimousineOwnedAddressResolution(value: value);
  }
  final result = await controller.lookup.search(
    query,
    language: controller.language,
  );
  if (controller.textController.text.trim() != query) {
    return LimousineOwnedAddressResolution(value: controller.value);
  }
  final resolved = limousineResolveOwnedAddress(query: query, result: result);
  controller.applyOwnedResolution(resolved);
  return resolved;
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
    widget.controller.acceptCopy(
      companyAddressValueFromSaved(address, trustStoredCoordinates: false),
    );
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
              if (widget.controller.locationNeedsConfirm)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kCompanyAddressNeedsConfirm.of(widget.language),
                        key: companyAddressConfirmKey(widget.controller.fieldId),
                        style: TextStyle(
                          color: tokens.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.controller.locationCandidate != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: companyAddressConfirmMapKey(
                              widget.controller.fieldId,
                            ),
                            onPressed: () {
                              widget.controller.confirmCandidateLocation();
                            },
                            child: Text(
                              kCompanyAddressConfirmMap.of(widget.language),
                            ),
                          ),
                        ),
                    ],
                  ),
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
