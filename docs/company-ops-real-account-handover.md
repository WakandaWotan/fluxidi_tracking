# Company-ops — overdracht FLX-00001 / Fluxidi

Tussenresultaat. Geen merge naar main. Geen productie-uitrol vanuit deze notitie.

## Voortgang

- **Agenda, chauffeurtoewijzing, offertes, vaste prijzen:** client- en Worker-bron zijn lokaal bewezen tegen de debug-Worker (`127.0.0.1:8788`, demo). Contrast- en scrollcorrecties zitten in de clientbron. Op productie ontbreken de API-routes nog (`GET /company/agenda/rides` en verwanten: HTTP 404).
- **Windows:** productiestartkopie **Fluxidi** van deze worktree is niet gebouwd. **Fluxidi — lokale test** blijft demo op localhost; niet gebruiken voor het echte account.
- **APK:** `C:\_flutter_work\fluxidi_customer_ops_client_p0\.qa-local\real-account\Fluxidi-real-account-2026-09-14.apk` (1.0.1+4, 14/09/2026 09:27, productiehost). Niet geïnstalleerd. Play-app op Xiaomi en Samsung is ondertekend door Google (`e5572fb5…`); deze APK door Fluxidi Upload (`b8479589…`). Bijwerken met behoud van appgegevens is met dit bestand niet mogelijk. Play-installaties niet verwijderen.
- **Productie-uitrol:** niet uitgevoerd. Live Worker `fluxidi-booking-api` blijft `ac663ed5-7aa4-496a-a244-3f16d435fe38` (11 sep 2026, 100%). Herstel na een latere uitrol: `scripts/rollback_real_account_booking_worker.ps1` naar die versie. Code-rollback wist geen KV en draait de DO-migratie niet terug.
- **RateHawk:** geen nieuwe integratie, testvlaggen of TEST-service in het uitrolpakket. Bestaande live `RATEHAWK_HOTELS`-binding alleen behouden zodat die niet verdwijnt.
- **Driver View:** geparkeerd; geen uitbreiding in deze overgang.
- **Praktijktest:** Christophe neemt over op Windows (na uitrol + productiestartkopie **Fluxidi**), gsm en tablet (Play laten staan).

## Open

1. Gericht akkoord voor `scripts/deploy_real_account_booking_worker.ps1 -IApproveProductionDeploy`.
2. Daarna korte API-controle (agenda 401 i.p.v. 404) en Windows-**Fluxidi**-startkopie.
3. Geen sideload over Play tot een Play-gesigneerde build bestaat.
