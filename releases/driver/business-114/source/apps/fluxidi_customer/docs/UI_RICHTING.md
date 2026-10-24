# Afgesproken UI-richting voor de klantenapp

Vastgelegd in fase 2B. Dit is de richting voor de latere UI-aansluiting; er is in
deze fase **geen** aparte redesignronde van de startpagina gedaan.

## Boekingspagina

- Grote kaart met een **sleepbaar paneel** erover. Dit is de referentie voor
  gsm én tablet, in portret en landschap.
- **Geen** plannerachtige tweekolomsindeling voor de boekingspagina. Op brede
  tablets wordt de inhoud van het paneel in breedte begrensd, niet naast de
  kaart gezet.
- Geïmplementeerd in `lib/widgets/ride_map_sheet_shell.dart`. De kaart zelf is
  aangesloten in `lib/widgets/customer_route_map.dart`: Mapbox-tiles, markers
  voor vertrek en bestemming, de echte routegeometrie en een camera die de route
  past in het deel dat het paneel vrij laat.

## Startpagina (later)

- Compacte Fluxidi-header.
- Taalkeuze en een paletknop die naar de **volledige bestaande themalijst** gaat.
- Direct een rit kunnen voorbereiden op de startpagina zelf.
- Fotokaarten voor luchthaven, hotels, evenementen en limousine.
- Regio Radar.
- Onderaan drie bestemmingen: **Home, Boekingen, Profiel**.
- Onder Profiel: gegevensbeheer en account verwijderen.
- **Geen** afzonderlijke knoppen "Zakelijke rit" of "Taxi in de buurt".
- Zakelijke rit blijft een **optie binnen de boekingsflow** (staat al zo in
  `customer_ride_prepare_screen.dart`).

## Tijdelijke ingang in deze fase

De bedrijvenlijst uit fase 2A is nu de ingang naar de prijsopgave, omdat een
prijs een `public_partner_id` nodig heeft. Dat is een **integratie-ingang**, geen
vastgelegde productkeuze: de afgesproken startpagina laat de klant direct een rit
voorbereiden, en de bedrijfskeuze hoort daar later in de flow te passen (of
vooraf gekozen te zijn bij een white-labelapp).

## Varianten

- **Algemene Fluxidi-klantenapp**: klant kiest een taxibedrijf.
- **White-label klantenapp**: vast aan één bedrijf, nog niet gebouwd. Zolang die
  variant niet ondersteund is, weigert de app expliciet de platformbrede
  bedrijvenlijst te tonen in plaats van er stil op terug te vallen.
