# Herkomst van de geëxtraheerde kerncode

Alles in `lib/src/` is overgenomen uit de bestaande Fluxidi-app op golden commit
**`9df7e7b92ecc86a11184ee995e255da7b8f6fb68`** (branch `release/client-internal-v26`,
Play Internal 30 / 1.0.6+30).

Doel: één kern die de algemene Fluxidi-klantenapp en een latere white-label
klantenapp samen gebruiken. Er is **geen tweede prijsengine**: prijzen komen
uitsluitend van de server. Deze kern bouwt de aanvraag en leest het antwoord.

Namen zijn neutraal gemaakt (`Fluxidi…` in plaats van `CompanyPlan…`), het
**gedrag en het wire-contract zijn ongewijzigd**. De tabel hieronder is de
mapping die een latere diff tegen de golden bron mogelijk houdt.

| Nieuw bestand | Nieuw symbool | Golden bronbestand | Golden symbool |
|---------------|---------------|--------------------|----------------|
| `src/address_value.dart` | `FluxidiAddressAcceptance` | `lib/limousine/limousine_address_lookup.dart` | `LimousineAddressAcceptance` |
| `src/address_value.dart` | `FluxidiAddressValue` | `lib/limousine/limousine_address_lookup.dart` | `LimousineAddressValue` |
| `src/address_value.dart` | `fluxidiAddressIsQuoteReady` | `lib/company/company_plan_quote.dart` | `companyPlanAddressIsQuoteReady` |
| `src/address_value.dart` | `fluxidiPostcodeFromAddress` | `lib/company/company_plan_quote.dart` | `companyPlanPostcodeFromAddress` |
| `src/ride_options.dart` | `FluxidiRideOptions` | `lib/company/company_ride_options.dart` | `CompanyRideOptions` |
| `src/ride_options.dart` | `fluxidiStripWaitFields` | `lib/company/company_ride_options.dart` | `companyRideOptionsStripWaitFields` |
| `src/ride_options.dart` | `kFluxidiRideWaitPayloadKeys` | `lib/company/company_ride_options.dart` | `kCompanyRideWaitPayloadKeys` |
| `src/schedule.dart` | `fluxidiZoneUtcToLocal` / `fluxidiZoneLocalToUtc` | `lib/company/company_timezone.dart` | `companyTimezoneUtcToLocal` / `companyTimezoneLocalToUtc` |
| `src/schedule.dart` | `kFluxidiDefaultTimezone` | `lib/company/company_timezone.dart` | `kCompanyDefaultTimezone` |
| `src/schedule.dart` | `fluxidiPickupIso` | `lib/company/company_plan_when.dart` | `companyPlanPickupIso` |
| `src/schedule.dart` | `fluxidiWhenWireFields` | `lib/company/company_plan_when.dart` | `companyPlanWhenWireFields` |
| `src/schedule.dart` | `fluxidiStripClientScheduleFields` | `lib/company/company_plan_when.dart` | `companyPlanStripClientScheduleFields` |
| `src/schedule.dart` | `fluxidiPickupIsEpoch` / `fluxidiWallClock` | `lib/company/company_plan_when.dart` | `companyPlanPickupIsEpoch` / `companyPlanWallClock` |
| `src/schedule.dart` | `fluxidiWhenIsNow` | `lib/company/company_plan_when.dart` | `companyAgendaWhenIsNow` |
| `src/quote_request.dart` | `FluxidiQuoteRequest` | `lib/company/company_plan_quote.dart` | `CompanyPlanQuoteRequest` |
| `src/quote_request.dart` | `fluxidiQuoteFingerprint` | `lib/company/company_plan_quote.dart` | `companyPlanQuoteFingerprint` |
| `src/quote_request.dart` | `buildFluxidiQuoteRequest` | `lib/company/company_plan_quote.dart` | `companyPlanQuoteRequestFromAddresses` |
| `src/quote_wire.dart` | `fluxidiEnsurePublicScheduleFields` | `lib/customer_booking/customer_booking_quote_wire.dart` | `customerBookingEnsurePublicScheduleFields` |
| `src/partner_scope.dart` | `FluxidiPartnerScope.decorate` | `lib/customer_booking/customer_booking_quote.dart` | `CustomerBookingQuoteClient.decorateBody` |
| `src/quote_result.dart` | `FluxidiQuoteResult` | `lib/company/company_plan_quote.dart` | `CompanyPlanQuoteResult` |
| `src/quote_result.dart` | `parseFluxidiQuote` | `lib/company/company_plan_quote.dart` | `parseCompanyPlanQuote` |
| `src/quote_result.dart` | `FluxidiQuoteTotalCheck` / `fluxidiQuoteTotalCheck` | `lib/company/company_plan_quote.dart` | `CompanyPlanQuoteTotalCheck` / `companyPlanQuoteTotalCheck` |
| `src/quote_result.dart` | `fluxidiParseMoney` / `fluxidiParseDurationMin` | `lib/company/company_booking_metrics.dart` | `parseCompanyBookingMoney` / `parseCompanyBookingDurationMin` |
| `src/quote_result.dart` | `fluxidiCanonicalDurationMin` | `lib/company/company_plan_when.dart` | `companyPlanCanonicalDurationMin` |
| `src/availability.dart` | `FluxidiAvailabilitySnapshot` | `lib/customer_booking/customer_booking_company_vehicles.dart` | `CustomerBookingAvailabilitySnapshot` |
| `src/availability.dart` | `parseFluxidiAvailability` | `lib/customer_booking/customer_booking_company_vehicles.dart` | `parseCustomerBookingAvailability` |
| `src/vehicle_offer.dart` | `FluxidiVehicleOffer` | `lib/customer_booking/customer_booking_vehicle_offers.dart` | `customerBookingVehicleOffers` (aanbodsamenstelling) |

## Bewust niet overgenomen

- De quote-**coördinator** met debounce (`CompanyPlanQuoteCoordinator`): de
  nieuwe app doet een expliciete berekening op verzoek van de klant en heeft een
  eigen, simpeler bescherming tegen verlate antwoorden.
- Alles rond luchthavenvluchten, limousine, agenda, roosters en facturatie.
- Prijsopbouw (`CompanyPlanQuoteBreakdown`): pas nodig zodra we een detailuitleg
  van de prijs tonen.
- Legmerge (`companyPlanMergeLegQuotes`) en de tweede-leg-fallback: de server
  levert voor deze flow één antwoord met heen- en terugprijs.

## Behouden regels

- `fluxidiAddressIsQuoteReady` eist nog steeds een geaccepteerd adres **met**
  coördinaten. Zonder coördinaten wordt geen aanvraag opgebouwd.
- Bij een luchthavenrit worden wachttijdvelden gestript, precies zoals in de
  bestaande flow.
- `pickup_iso` is altijd de Europe/Brussels-wandklok omgezet naar UTC, nooit de
  toestelzone.
- Een retourrit stuurt `return_enabled`, `return_pickup_iso` en de retouradressen
  met dezelfde veldnamen als de bestaande flow.

## Kaart en adres (fase 2B, kaartaansluiting)

| Nieuw bestand | Nieuw symbool | Golden bronbestand | Golden symbool |
|---------------|---------------|--------------------|----------------|
| `src/lon_lat.dart` | `FluxidiLonLat`, `downsampleFluxidiRoute` | `lib/maps/fluxidi_static_route_preview.dart` | `FluxidiMapLonLat`, `downsampleFluxidiRoute` |
| `src/lon_lat.dart` | `fluxidiLonLat`, `fluxidiRouteFingerprint` | `lib/customer_booking/customer_booking_route_camera.dart` | `customerBookingLonLat`, `customerBookingRouteFingerprint` |
| `src/route_geometry.dart` | `FluxidiRouteGeometry`, `FluxidiRouteGeometryClient` | `lib/customer_booking/customer_booking_route_geometry.dart` | `CustomerBookingRouteGeometry`, `CustomerBookingRouteGeometryClient` |
| `src/address_search.dart` | `FluxidiAddressSuggestion`, `FluxidiAddressSearchClient`, `fluxidiNormalizeAddressQuery` | `lib/limousine/limousine_address_lookup.dart` | `LimousinePlaceSuggestion`, `LimousinePlaceLookup.search` / `_searchMapbox`, `limousineNormalizeAddressQuery` |

De kaartweergave zelf hoort bij Flutter en staat daarom in de app, niet in deze
pure-Dart kern: `apps/fluxidi_customer/lib/widgets/customer_route_map.dart`
neemt `CustomerBookingMapCamera`, `customerBookingMercatorX/Y`,
`customerBookingProject`, `customerBookingPanCamera`, `customerBookingFitCamera`
en `_zoomForSpan` over uit
`lib/customer_booking/customer_booking_route_camera.dart`, plus
`_MapboxTileLayer` en de routepainter uit
`lib/customer_booking/customer_booking_route_map.dart`.

Zelfde provider als de bestaande app: Mapbox raster-tiles (`streets-v12`),
Mapbox Geocoding v5 places en Mapbox Directions v5 met
`geometries=geojson&overview=full`. Zonder routeantwoord wordt er **geen** lijn
getekend; een rechte lijn is nooit een vervanging.
