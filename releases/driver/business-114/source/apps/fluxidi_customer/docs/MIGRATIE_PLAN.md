# Volledige klantmigratie — bridge-eerst

Afgesproken op 2026-09-21. Doel: het **volledige** bestaande klantengedeelte van
Internal 30 werkt zelfstandig in `com.fluxidi.customer.dev`, met Home en Profiel
volgens de twee goedgekeurde ontwerpen.

Golden bron blijft ongewijzigd: `release/client-internal-v26` op
`9df7e7b92ecc86a11184ee995e255da7b8f6fb68`.

## Waarom bridge-eerst

De klantschermen zijn `part of '../main.dart'`. Die library is 2.757 regels met
**42 parts**, waarvan 11 klant; in dezelfde eenheid zitten
`driver_home_page_state.dart` (38.075 regels), `business_home_page_state.dart`,
Chiron, Billit en de ritbon-PDF-runner. `app_config.dart` is 11.783 regels met de
bedrijfs- en chauffeursnotifiers. De 28 bestanden in `customer_booking/`
importeren `lib/company/*`. Een bestand-voor-bestand extractie is een migratie in
tientallen stappen voordat de eerste volledige flow weer draait.

Bridge-eerst zet die orde om: eerst **werkend**, dan **schoon**.

## Stap 1 — brug leggen

1. Path-dependency van `apps/fluxidi_customer` naar de golden worktree als
   package `fluxidi_tracking` (read-only gebruikt, niet gewijzigd).
2. Eigen `main()` in de nieuwe app die **alleen** klantstate boot: geen
   `CompanySessionStore.bootstrap()`, geen `DriverSessionStore.bootstrap()`, geen
   fleet-sync, geen E2E-autologin.
3. Assets uit de golden `pubspec.yaml` die de klantflow nodig heeft opnemen
   (`assets/fluxidi/`, `assets/booking/modes/v1/`, `assets/booking/airports/v1/`,
   `assets/payment/**`, `assets/vehicles/fallback/v1/`, themamappen).
4. Dart-defines: `MAPBOX_TOKEN`, `BOOKING_BASE_URL`/`WORKER_BASE_URL`,
   `FLUXIDI_PUBLIC_BOOKING_BASE_URL`. Token via `~/.fluxidi/fluxidi-dev-env.ps1`,
   nooit committen.
5. Payment-return: eigen scheme `fluxidicustomerdev://pay/return` blijft; de
   bestaande `PaymentReturnCoordinator` verwacht `fluxidi://pay/return`, dus de
   nieuwe app zet zijn eigen constante door in de book-payload en handelt de
   terugkeer zelf af. Serverstatus blijft leidend.

## Stap 2 — nieuwe Home en Profiel

Echte Flutter-schermen, geen achtergrondafbeelding, geen carousel.

- Boven: echt Fluxidi-logo, taalkeuze (bestaande talen), paletknop die de
  **volledige bestaande themakiezer** opent (`CustomerThemeVariant`, 11 varianten).
- "Waar wil je naartoe?", bestemmingsveld met adressuggesties, "Boek een taxi".
- Fotokaarten Luchthavenritten, Hotels & B&B, Evenementen, Limousine met de
  bestaande losse foto-assets. Gsm: onder elkaar. Tablet: twee kolommen, portret
  en landschap.
- Regio Radar onder de diensten.
- Onderbalk Home, Boekingen, Profiel.
- Profiel: Mijn gegevens, Mijn boekingen, Taal, Thema kiezen, Mijn gegevens &
  account verwijderen (bestaande bevestiging).
- Geen tegel "Zakelijke rit" of "Taxi in de buurt"; die horen in de boekingsflow.
- Een op Home gekozen bestemming gaat **met coördinaten** mee naar de flow.

## Stap 3 — afpellen

Per onderdeel de golden klantcode uit de `part`-library naar een eigen library
tillen, company-imports vervangen door de gedeelde kern in
`packages/fluxidi_customer_core`, en `app_config` splitsen in een klantdeel. Pas
afsluiten wanneer de bridge niets meer nodig heeft uit driver/company.

## Werklijst en verificatie

| Bestaande klantfunctie | Aansluiting | Verificatie |
|---|---|---|
| Bedrijven zoeken + publiek profiel | klaar (eigen implementatie) | toestel |
| Rit voorbereiden, quote, beschikbaarheid, voertuigaanbod | klaar (eigen implementatie) | toestel |
| Kaart, markers, echte route, camera | klaar | toestel |
| Sleepbaar paneel: grip, inhoud, inklappen, met toetsenbord | deels | **nog expliciet op toestel** |
| Adressuggesties, huisnummer, coördinaten | klaar | toestel |
| Opgeslagen adres, huidige locatie | via bridge | nog |
| Aanmelden, klantaccount, sessieherstel, eigen gegevens | via bridge | nog |
| Taxi volledige flow incl. tussenstops en privé/zakelijk | via bridge | nog |
| Luchthavenvervoer incl. vluchtopties en vaste prijs | via bridge | nog |
| Hotels/B&B, evenementen, limousine | via bridge | nog |
| Boeken, betalen, terugkeer, bevestiging | via bridge | testmodus vereist |
| Mijn boekingen, detail, vervolgacties | via bridge | nog |
| Regio Radar | via bridge | nog |
| Alle talen en thema's | via bridge | nog |
| Mijn gegevens & account verwijderen | via bridge | nog, niet echt uitvoeren |

## Grenzen

- Golden bron niet wijzigen; geen push, publicatie of deployment.
- Geen echte betaling, boeking of accountverwijdering als test. Betalen alleen in
  een aantoonbare testmodus; `status=paid` in een terugkeerlink is nooit bewijs.
- Bedrijfs- en chauffeursfuncties blijven in de bestaande app.
- Nodige serverwijziging: onderbouwen en apart voorbereiden, niet doorvoeren.
