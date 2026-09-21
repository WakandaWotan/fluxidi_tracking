# Fluxidi Customer Dev — zelfstandige klantenapp (fase 1)

Technische basis voor een aparte Fluxidi-klantenapp. Deze app staat volledig los
van de bestaande gecombineerde app en is naast Internal 30 te installeren.

In deze fase is er **geen** serververbinding, **geen** aangemelde klant en
**geen** betaalfunctie. Alleen opstart, navigatie en eigen deeplinkafhandeling.

## Herkomst

| Item | Waarde |
|------|--------|
| Golden broncommit | `9df7e7b92ecc86a11184ee995e255da7b8f6fb68` |
| Golden branch | `release/client-internal-v26` (Play Internal 30 — 1.0.6+30) |
| Deze ontwikkellijn | branch `feature/customer-app-bootstrap`, gestart vanaf die commit |
| Worktree | `D:\Projecten\_flutter_work\fluxidi_customer_dev` |
| Projectlocatie | `apps/fluxidi_customer/` |

De bestaande app in de repositoryroot is niet gewijzigd. Bouw altijd vanuit
`apps/fluxidi_customer`, nooit vanuit de root.

## Development-identiteit

Voorlopige waarden. Dit is **geen** definitieve Play-identiteit.

| Item | Waarde |
|------|--------|
| Appnaam | `Fluxidi Customer Dev` |
| Android applicationId / namespace | `com.fluxidi.customer.dev` |
| MainActivity | `com.fluxidi.customer.dev.MainActivity` |
| Betaalterugkeerlink | `fluxidicustomerdev://pay/return` |
| Versie | `0.1.0+1` (losstaand van 1.0.6+30) |

De bestaande app houdt `com.fluxidi.tracking` en `fluxidi://pay/return`. Dit
project declareert dat scheme bewust **niet**, zodat beide apps naast elkaar
kunnen staan zonder om dezelfde link te concurreren.

Alle identiteitswaarden staan op één plek: `lib/app/customer_app_config.dart`.

## Publieke API-configuratie

De basis-URL van de publieke booking-API is **niet** ingebouwd. Er is geen
verborgen productiefallback: zonder define meldt het Taxi-scherm expliciet dat
de API niet geconfigureerd is.

```
--dart-define=FLUXIDI_PUBLIC_BOOKING_BASE_URL=<https://...>
```

## Bouwen en starten

```powershell
cd D:\Projecten\_flutter_work\fluxidi_customer_dev\apps\fluxidi_customer

flutter pub get
flutter analyze
flutter test

# Debug-APK met publieke API
flutter build apk --debug `
  --dart-define=FLUXIDI_PUBLIC_BOOKING_BASE_URL=https://fluxidi-booking-api.fluxidi.workers.dev
# resultaat: build\app\outputs\flutter-apk\app-debug.apk

# Op een aangesloten toestel
flutter run
```

Eigen deeplink testen op een toestel, zonder betaling:

```powershell
adb shell am start -a android.intent.action.VIEW -d "fluxidicustomerdev://pay/return"
```

Dat opent een neutraal scherm. Het bevestigt niets.

## Wat is gecontroleerd

| Controle | Resultaat |
|----------|-----------|
| `flutter analyze` | Geen meldingen |
| `flutter test` | 45 tests groen (navigatie, layoutmaten, deeplink, API-contract, zoekflow) |
| `flutter build apk --debug` | Geslaagd |
| Publieke read-only GET-controle | `/partners/nearby?postcode=9600` → 200; zonder parameters → 400; `/partners/profile` → 200 |
| APK-identiteit (`aapt2 dump badging`) | `com.fluxidi.customer.dev`, label `Fluxidi Customer Dev` |
| APK-manifest | intent filter `fluxidicustomerdev` / `pay` / `/return`, `autoVerify=false` |
| APK-manifest | legacy `fluxidi://` scheme is afwezig |
| Afhankelijkheden | alleen `flutter`, `app_links`; geen import uit de bestaande app |
| Toestelcontrole | **Nog uit te voeren** — geen toestel of emulator beschikbaar bij oplevering |

Geteste layoutmaten zijn widget-testmaten (telefoon portret/landschap, tablet
portret/landschap, plus grote systeemtekst), geen fysieke toestellen.

## Architectuur

```
lib/
  main.dart                              eigen opstart, alleen runApp
  api/
    public_partner_api.dart              dunne client: nearby + profile
    public_partner_models.dart           getypeerde velden die we tonen
    public_partner_visibility.dart       boekbaarheid, naam, beeldregels
    public_company_presentation.dart     voorbeeld-/reviewmarkering
  app/
    customer_app_config.dart             naam, dev-identiteit, API-URL, variant
    customer_theme.dart                  Fluxidi-paletwaarden
    customer_routes.dart                 klantrouter (named routes)
    fluxidi_customer_app.dart            app-root en deeplinkkoppeling
  deeplinks/
    customer_deep_link.dart              pure resolver voor eigen scheme
    customer_deep_link_source.dart       linkbron, app_links achter een interface
  screens/
    customer_home_screen.dart            klantstartscherm, responsieve tegels
    customer_taxi_search_screen.dart     bedrijven zoeken op postcode
    customer_partner_profile_screen.dart publiek bedrijfsprofiel
    customer_placeholder_screen.dart     "nog niet aangesloten"
    customer_payment_return_screen.dart  neutraal terugkeerscherm
  widgets/
    partner_media.dart                   hero/logo met neutrale fallback
```

## Aangesloten contracten (fase 2A)

Read-only, zonder authenticatie. Vastgesteld tegen de clientbron op golden
commit 9df7e7b9 en daarna live geverifieerd met publieke GET-controles.

| Contract | Gebruik |
|----------|---------|
| `GET /partners/nearby?postcode=<code>` | Bedrijven zoeken. Antwoord: `ok`, `postcode`, `count`, `partners[]` |
| `GET /partners/profile?partner_id=<id>` | Publiek bedrijfsprofiel. Antwoord: `ok`, `profile{}` |

Het endpoint accepteert daarnaast `lat` + `lng` (samen verplicht) met optionele
`radius_km`, en een optionele `service`-filter. Zonder parameters antwoordt het
met HTTP 400. **Land is geen requestparameter**: `country_code` komt alleen in
het antwoord voor en wordt in de resultaatregel getoond.

Overgenomen betekenis uit de bestaande flow: boekbaarheid komt uitsluitend van
de server (`bookable`, `availability_status`, `is_active`), de platformnaam
Fluxidi is nooit een bedrijfsnaam, alleen https-afbeeldingen worden getoond, en
een voorbeeld- of reviewbedrijf houdt zijn badge en toelichting.

De linkbron zit achter `CustomerDeepLinkSource` zodat tests de app kunnen
aandrijven zonder platformkanaal.

## Bewust niet overgenomen

De zichtbaarheids-, identiteits- en presentatieregels zijn opnieuw
geïmplementeerd in `lib/api/`, met de bestaande betekenis als referentie. De
quote-, prijs-, booking- en payment-engines zijn **niet** overgenomen.

Uit de bestaande app is niets geïmporteerd, gekopieerd of herschreven:

- `lib/main.dart` en de bijbehorende `part`-library
- `lib/app_config.dart`
- bedrijfs-, chauffeurs- en plannerbootstrap
- synthetische bedrijfssessies
- de bestaande payment-returncoordinator
- quote-, prijs-, booking- en payment-engines

Branding is hergebruikt als **waarden** (paletkleuren), niet als code. Het
bestaande logo-asset van 2,3 MB is niet gedupliceerd; het startscherm gebruikt
voorlopig een eenvoudig merkvlak.

## Nog niet aangesloten

| Onderdeel | Status |
|-----------|--------|
| Registreren en aanmelden als klant | niet aangesloten |
| Klantprofiel | niet aangesloten |
| Taxibedrijf zoeken en profiel bekijken | **aangesloten (fase 2A)** |
| Taxi boeken | niet aangesloten |
| Luchthavenvervoer | niet aangesloten |
| Retourritten | niet aangesloten |
| Kaart en route | niet aangesloten |
| Bedrijf, voertuig en chauffeur kiezen | niet aangesloten |
| Prijsopgave | niet aangesloten |
| Online betalen en hervatten | niet aangesloten |
| Mijn boekingen en boekingsdetail | niet aangesloten |
| Annuleren, rit volgen, beoordeling | niet aangesloten |
| Klantmeldingen | niet aangesloten |
| Taal en thema | niet aangesloten |

Hotels en Events staan als navigatiebestemming in de shell, maar zijn evenmin
aangesloten.

## Twee toekomstige varianten

`CustomerAppVariant` benoemt beide richtingen zonder ze te implementeren:

- `fluxidiMarketplace` — één klantenapp, de klant kiest een taxibedrijf.
- `whiteLabelSingleCompany` — dezelfde app gebonden aan één bedrijf via
  build-time configuratie.

Deze fase bouwt geen white-label buildmatrix en geen bedrijfsselectielogica.

## Grenzen

Geen wijzigingen aan Worker, Mollie, Firebase, Billit, Chiron, Shopify of Play
Console. Geen echte boekingen, betalingen, annuleringen of OTP-verzoeken. De
klantfunctionaliteit in Internal 30 blijft volledig intact.
