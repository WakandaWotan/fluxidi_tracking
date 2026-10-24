# Open toestelcontrole voor volgende release

Dit document registreert de vervolgcontrole na Internal Bedrijf 49 / Klanten 26.
De eerdere handoffs bevatten historische releasebewijzen; die bewijzen gelden
niet automatisch voor onderstaande nieuwe lokale wijzigingen.

## Bronnen

- Bedrijf: `D:/Projecten/_flutter_work/fluxidi_business_internal47`
- Klanten: `D:/Projecten/_flutter_work/fluxidi_customer_dev/apps/fluxidi_customer`, met root-bridge.
- Booking: `D:/Projecten/_flutter_work/fluxidi_booking_live_9af4c215_rc`

## Nog af te tekenen

| Punt | Lokale stand | Nog vereist |
| --- | --- | --- |
| Privéchauffeur klanttekst | Interne partner-ID en lange uitleg uit scherm gehaald; korte offerte-/prijsintro | Nieuwe testapp op gsm bekijken |
| Privéchauffeur invoer | Adreszoeker en datum-/tijdkiezer aanwezig | Kiezers en adresselectie op toestel |
| Offerteaanvraag | Geldige klantsessie meegestuurd; HTTP-fout toont geen vals succes | Offerteketen controleren met geschikte testgegevens |
| Mollie | Checkout openen en hervatten met dezelfde ontvangen boeking; gerichte tests groen | Veilige betaalflow met testbetaling; geen echte betaling uitgevoerd |
| Volg je rit | Foto-/categorie-/neutrale fallback in lokale code | Voor vertrek, onderweg, ontbrekende foto en netwerkfout op toestel |
| Tesla naam | Foto behouden; voertuigkaart gebruikt voertuignaam | Tesla Model Y-kaart op klantenapp |
| Voertuigeditor | Fallbackillustratie en eigen foto zijn afzonderlijke velden | Selectie, hoofdfoto, verwijderen, opslaan en heropenen op tablet |
| Bedrijfsheader | Cover/logo en aparte bedrijfsvlag verbonden; gerichte tests groen | Opslaan, dashboard en heropenen op tablet |
| Chauffeurheader | Gedeelde header aanwezig | Eerste laadduur meten; oorzaak nog niet bevestigd |
| Clean Professional | Instellingen en offertekeuzes hebben expliciete contrastkleuren; tests groen | Airportmenu, eigen offerte, taalkeuze en voertuigeditor op tablet |
| Abonnementen | EU, €19 voertuig, €9 chauffeur; basis en inbegrepen capaciteit behouden; elk max 9 extra | UI/checkoutgrenzen en bestaande klanten controleren |
| Mario luchthaven | Screenshots tonen Maarkedal en prijs op aanvraag | 48-uursgrens, werkgebied, vaste tarieven en rooster afzonderlijk controleren |

## Toestelstand 1 oktober, circa 19:13 Brussel

- Samsung `R52Y808CN2M`: aparte debugapp `com.fluxidi.tracking.qa`
  geïnstalleerd en geopend. Staat op rolkeuze; gebruiker moet zelf aanmelden.
- Xiaomi `SG7XLZ7TKRLZOJTG`: bestaande `com.fluxidi.customer` staat op
  Privéchauffeur. Installatie van aparte `com.fluxidi.customer.dev` is door
  Android geweigerd met `INSTALL_FAILED_USER_RESTRICTED`; nog niet geïnstalleerd.
- De screenshots van de bestaande Play-app tonen de oude lange uitleg en zijn
  geen bewijs van de aangepaste bron.
- Nieuwe klantgerichte tests: 18/18 groen; QA-runtimeconfiguratie 15/15 groen.
  Gerichte klantenanalyse schoon. Bedrijfsheader-/contrasttests 8/8 groen.
- Geen nieuwe AAB, Play-upload, backenddeploy, productieboeking of betaling in
  deze vervolgcontrole. De releasepoort blijft open tot toestelbewijs aanwezig is.

## Nieuwe stand na gebruikersopdracht voor Play-test

Bedrijf/Chauffeur 1.0.7 (50) en Klanten 1.0.7 (27) zijn gebouwd, ondertekend, geüpload en onafhankelijk teruggelezen als Internal completed. De open toestelpunten hierboven blijven open; lokale test- en bundelbewijzen zijn geen toestelbewijs. De gebruiker test de officiële Play-updates. De aparte QA-APK-route is verlaten. Geen backenddeploy in deze releasebeurt.
