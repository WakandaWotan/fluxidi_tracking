import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'airport_catalog_repository.dart';

const LocalizedText kAirportSelectorCountry = LocalizedText(
  nl: 'Land',
  en: 'Country',
  fr: 'Pays',
  es: 'País',
);

const LocalizedText kAirportSelectorAirport = LocalizedText(
  nl: 'Luchthaven',
  en: 'Airport',
  fr: 'Aéroport',
  es: 'Aeropuerto',
);

String airportCountryLabel(String countryCode, AppLanguage language) {
  switch (countryCode.trim().toUpperCase()) {
    case 'BE':
      return LocalizedText(
        nl: 'België',
        en: 'Belgium',
        fr: 'Belgique',
        es: 'Bélgica',
      ).of(language);
    case 'NL':
      return LocalizedText(
        nl: 'Nederland',
        en: 'Netherlands',
        fr: 'Pays-Bas',
        es: 'Países Bajos',
      ).of(language);
    case 'FR':
      return LocalizedText(
        nl: 'Frankrijk',
        en: 'France',
        fr: 'France',
        es: 'Francia',
      ).of(language);
    case 'DE':
      return LocalizedText(
        nl: 'Duitsland',
        en: 'Germany',
        fr: 'Allemagne',
        es: 'Alemania',
      ).of(language);
    case 'LU':
      return LocalizedText(
        nl: 'Luxemburg',
        en: 'Luxembourg',
        fr: 'Luxembourg',
        es: 'Luxemburgo',
      ).of(language);
    case 'ES':
      return LocalizedText(
        nl: 'Spanje',
        en: 'Spain',
        fr: 'Espagne',
        es: 'España',
      ).of(language);
    case 'GB':
      return LocalizedText(
        nl: 'Verenigd Koninkrijk',
        en: 'United Kingdom',
        fr: 'Royaume-Uni',
        es: 'Reino Unido',
      ).of(language);
    default:
      final match = airportsForCountry(countryCode);
      if (match.isEmpty) return countryCode.trim().toUpperCase();
      return match.first.countryName.trim();
  }
}

const Key kSharedAirportCountryDropdownKey = ValueKey<String>(
  'shared_airport_country_dropdown',
);
const Key kSharedAirportAirportDropdownKey = ValueKey<String>(
  'shared_airport_airport_dropdown',
);

class AirportCountryAirportSelector extends StatelessWidget {
  const AirportCountryAirportSelector({
    super.key,
    required this.language,
    required this.countryCode,
    required this.airportIata,
    required this.onCountryChanged,
    required this.onAirportChanged,
    this.airports,
    this.fillColor,
    this.dropdownColor,
    this.iconColor,
    this.textColor,
    this.enabled = true,
  });

  final AppLanguage language;
  final String countryCode;
  final String airportIata;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<AirportCatalogAirport> onAirportChanged;
  final List<AirportCatalogAirport>? airports;
  final Color? fillColor;
  final Color? dropdownColor;
  final Color? iconColor;
  final Color? textColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final catalog = airports ?? publishedAirportCatalog();
    final countries = publishedAirportCountryCodes(catalog);
    final selectedCountry = countries.contains(countryCode)
        ? countryCode
        : (countries.isEmpty ? '' : countries.first);
    final countryAirports = airportsForCountry(selectedCountry, catalog);
    final selectedAirport = airportByIata(
          airportIata,
          countryCode: selectedCountry,
          airports: countryAirports,
        ) ??
        (countryAirports.isEmpty ? null : countryAirports.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          key: kSharedAirportCountryDropdownKey,
          decoration: InputDecoration(
            labelText: kAirportSelectorCountry.of(language),
            prefixIcon: const Icon(Icons.public_rounded),
            filled: fillColor != null,
            fillColor: fillColor,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedCountry.isEmpty ? null : selectedCountry,
              isDense: true,
              isExpanded: true,
              dropdownColor: dropdownColor,
              iconEnabledColor: iconColor,
              style: TextStyle(color: textColor, fontSize: 13),
              items: countries
                  .map(
                    (code) => DropdownMenuItem<String>(
                      value: code,
                      child: Text(airportCountryLabel(code, language)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled
                  ? (value) {
                      if (value == null || value == selectedCountry) return;
                      onCountryChanged(value);
                    }
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        InputDecorator(
          key: kSharedAirportAirportDropdownKey,
          decoration: InputDecoration(
            labelText: kAirportSelectorAirport.of(language),
            prefixIcon: const Icon(Icons.flight_rounded),
            filled: fillColor != null,
            fillColor: fillColor,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedAirport?.iata,
              isDense: true,
              isExpanded: true,
              dropdownColor: dropdownColor,
              iconEnabledColor: iconColor,
              style: TextStyle(color: textColor, fontSize: 13),
              selectedItemBuilder: (context) => countryAirports
                  .map(
                    (airport) => Text(
                      airport.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                  .toList(growable: false),
              items: countryAirports
                  .map(
                    (airport) => DropdownMenuItem<String>(
                      value: airport.iata,
                      child: Text(
                        airport.displayLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: enabled
                  ? (value) {
                      if (value == null) return;
                      final next = airportByIata(
                        value,
                        countryCode: selectedCountry,
                        airports: countryAirports,
                      );
                      if (next != null) onAirportChanged(next);
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
