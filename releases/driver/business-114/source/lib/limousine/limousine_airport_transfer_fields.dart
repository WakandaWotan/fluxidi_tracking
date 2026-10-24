import 'package:flutter/material.dart';

import '../airport/airport_catalog_repository.dart';
import '../airport/airport_selector.dart';
import '../app_strings.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_transfer_endpoint.dart';

const LocalizedText kLimousineAirportToDirection = LocalizedText(
  nl: 'Naar de luchthaven',
  en: 'To the airport',
  fr: 'Vers l’aéroport',
  es: 'Al aeropuerto',
);

const LocalizedText kLimousineAirportFromDirection = LocalizedText(
  nl: 'Van de luchthaven',
  en: 'From the airport',
  fr: 'Depuis l’aéroport',
  es: 'Desde el aeropuerto',
);

const LocalizedText kLimousineHotelToDirection = LocalizedText(
  nl: 'Naar het hotel',
  en: 'To the hotel',
  fr: 'Vers l’hôtel',
  es: 'Al hotel',
);

const LocalizedText kLimousineHotelFromDirection = LocalizedText(
  nl: 'Van het hotel',
  en: 'From the hotel',
  fr: 'Depuis l’hôtel',
  es: 'Desde el hotel',
);

const LocalizedText kLimousineHotelFieldLabel = LocalizedText(
  nl: 'Hotel',
  en: 'Hotel',
  fr: 'Hôtel',
  es: 'Hotel',
);

const LocalizedText kLimousineSelectedAirportCard = LocalizedText(
  nl: 'Gekozen luchthaven',
  en: 'Selected airport',
  fr: 'Aéroport sélectionné',
  es: 'Aeropuerto seleccionado',
);

const Key kLimousineAirportToDirectionKey = ValueKey<String>(
  'limousine_airport_to_direction',
);
const Key kLimousineAirportFromDirectionKey = ValueKey<String>(
  'limousine_airport_from_direction',
);
const Key kLimousineHotelToDirectionKey = ValueKey<String>(
  'limousine_hotel_to_direction',
);
const Key kLimousineHotelFromDirectionKey = ValueKey<String>(
  'limousine_hotel_from_direction',
);
const Key kLimousineSelectedAirportCardKey = ValueKey<String>(
  'limousine_selected_airport_card',
);

class LimousineDirectionChip extends StatelessWidget {
  const LimousineDirectionChip({
    super.key,
    required this.tokens,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final LimousineUxTokens tokens;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: tokens.gold.withOpacity(0.28),
    );
  }
}

class LimousineAirportTransferPanel extends StatelessWidget {
  const LimousineAirportTransferPanel({
    super.key,
    required this.language,
    required this.tokens,
    required this.direction,
    required this.countryCode,
    required this.airport,
    required this.onDirectionChanged,
    required this.onCountryChanged,
    required this.onAirportChanged,
  });

  final AppLanguage language;
  final LimousineUxTokens tokens;
  final String direction;
  final String countryCode;
  final AirportCatalogAirport? airport;
  final ValueChanged<String> onDirectionChanged;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<AirportCatalogAirport> onAirportChanged;

  @override
  Widget build(BuildContext context) {
    final toAirport = direction != 'from_airport';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LimousineDirectionChip(
              key: kLimousineAirportToDirectionKey,
              tokens: tokens,
              label: kLimousineAirportToDirection.of(language),
              selected: toAirport,
              onTap: () => onDirectionChanged('to_airport'),
            ),
            LimousineDirectionChip(
              key: kLimousineAirportFromDirectionKey,
              tokens: tokens,
              label: kLimousineAirportFromDirection.of(language),
              selected: !toAirport,
              onTap: () => onDirectionChanged('from_airport'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AirportCountryAirportSelector(
          language: language,
          countryCode: countryCode,
          airportIata: airport?.iata ?? '',
          onCountryChanged: onCountryChanged,
          onAirportChanged: onAirportChanged,
          fillColor: tokens.fieldFill,
          dropdownColor: tokens.surface,
          iconColor: tokens.gold,
          textColor: tokens.onSurface,
        ),
        if (airport != null) ...[
          const SizedBox(height: 10),
          Container(
            key: kLimousineSelectedAirportCardKey,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.gold.withOpacity(0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kLimousineSelectedAirportCard.of(language),
                  style: TextStyle(color: tokens.muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  airport!.displayLabel,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  airport!.formattedAddress,
                  style: TextStyle(color: tokens.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

LimousineTransferEndpoint? limousineAirportEndpointOf(
  LimousineItineraryEndpoints itinerary,
) {
  if (itinerary.to?.kind == LimousineTransferEndpointKind.airport) {
    return itinerary.to;
  }
  if (itinerary.from?.kind == LimousineTransferEndpointKind.airport) {
    return itinerary.from;
  }
  return null;
}

LimousineTransferEndpoint? limousineHotelEndpointOf(
  LimousineItineraryEndpoints itinerary,
) {
  if (itinerary.to?.kind == LimousineTransferEndpointKind.hotel) {
    return itinerary.to;
  }
  if (itinerary.from?.kind == LimousineTransferEndpointKind.hotel) {
    return itinerary.from;
  }
  return null;
}
