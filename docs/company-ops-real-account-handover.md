# Company-ops — overdracht FLX-00001 / Fluxidi

Tussenresultaat. Geen merge naar main.

## Voortgang

- **Productie-uitrol:** uitgevoerd 14 sep 2026. Live Worker `fluxidi-booking-api` versie **`b7b71779-be08-4287-a355-51aed9586d41`** (100%). Config `wrangler.real-account-release.toml`, `--keep-vars`, dezelfde KV/R2. Geen nieuwe RateHawk-integratie; bestaande `RATEHAWK_HOTELS`-binding behouden.
- **Herstel:** vorige versie **`ac663ed5-7aa4-496a-a244-3f16d435fe38`**. `scripts/rollback_real_account_booking_worker.ps1`. Code-rollback wist geen KV en draait de DO-migratie niet terug.
- **Aangemelde controle FLX-00001:** `GET /company/customers` **200** (`ok=true`, 0 klanten in deze store). `GET /company/agenda/rides` **200** (`ok=true`, 17 ritten in september 2026). Zonder sessie blijft agenda **401**.
- **Windows:** productiestartkopie **Fluxidi** van `2026-09-14T15:15:59+02:00` blijft de start. Venster staat klaar voor pincode. Geen testboekingen gemaakt.
- **APK:** niet geïnstalleerd. Play-installaties niet verwijderen.
- **Driver View:** geparkeerd.

## Open

1. Christophe ontgrendelt **Fluxidi** en neemt de praktijktest over.
2. Geen sideload over Play tot een Play-gesigneerde build bestaat.
