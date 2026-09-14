# Company-ops — overdracht FLX-00001 / Fluxidi

Tussenresultaat. Geen merge naar main. Geen productie-uitrol vanuit deze notitie.

## Voortgang

- **Agenda, chauffeurtoewijzing, offertes, vaste prijzen:** Worker-bron (routes `/company/customers`, `/company/agenda/*`, `/company/fixed-prices`, `/company/customer-quotes`) is lokaal bewezen. Live productie heeft die routes nog niet (HTTP 404).
- **Uitrolpakket:** `workers/booking/wrangler.real-account-release.toml` plus client-scripts `prepare_` / `deploy_` / `rollback_real_account_booking_worker.ps1`. `--keep-vars`. Geen demodata, geen localhost-koppeling van FLX-00001.
- **Durable Object:** migratie `company-customer-import-coordinator-v1` is additief. Rollback van code herstelt de vorige Worker-versie; opgeslagen import-/klantkeys blijven liggen.
- **Windows / APK:** zie dezelfde notitie op `feat/company-customer-ops-client-p0`. Play-handtekening ≠ upload-APK.
- **Productie-uitrol:** niet uitgevoerd. Live versie `ac663ed5-7aa4-496a-a244-3f16d435fe38`.
- **RateHawk:** geen nieuwe integratie in dit pakket.
- **Driver View:** geparkeerd.
- **Praktijktest:** Christophe.

## Open

1. Akkoord voor de afgebakende productie-uitrol.
2. Geen push naar main; deze branch is alleen bewaring van Worker-bron.
