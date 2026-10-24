# Subscription price audit and Play notice repair — 2026-10-04

## Scope and authority

Authoritative Business source: `D:/Projecten/_flutter_work/fluxidi_business_internal47`, detached HEAD `fef8a2f3b25c4ea2e8f6d818d8829ea6207f3aa8`; existing dirty changes preserved. Backend source: `D:/Projecten/_flutter_work/fluxidi_booking_live_9af4c215_rc`.

The parent verified a human instruction in the linked hotel chat: Standard €69/month, Smart €89/month, no new founder offer. Extra vehicle €19/month and extra driver €9/month excluding VAT remain the stated add-on prices. The full Standard/Smart entitlement and market matrix is not yet established. No Free or WhiteLabel price is inferred.

The financial audit was read-only. No checkout, payment, mandate, refund, subscription creation/PATCH/cancellation, contract migration, secret modification or source pricing change was executed. Direct Cloudflare KV reads were used because the existing subscription GET handlers can materialize cancellation/suspension and write profiles. The separate central taxi Mollie key was not reused for SaaS billing.

## App and checkout findings

| Surface | Currently observed | Required next decision |
| --- | --- | --- |
| Business app catalog | `fluxidi_pro`; BE normal 6900 cents, founder 5900 cents/100 slots; other supported EU markets 4900 cents | Establish the real Standard/Smart entitlement and market matrix before replacing catalog |
| App plan presentation | “Fluxidi Pro België”, no implemented Smart €89 plan choice | New plan presentation must follow authoritative plan identity, preserve existing locked contracts |
| New backend checkout | Uses stored profile normal/founder prices before catalog; still reserves founder slots and can charge 5900 cents | Remove the new-founder path and select an authoritative confirmed tier; changing only display/catalog is insufficient |
| Extra vehicle/driver | App and backend catalogs 1900/900 cents | Correct catalog amounts; real provider parity not proven |
| Existing recurring contracts | Saved base locks and add-on unit locks are the authority; existing provider subscription reconciliation does not reprice an existing subscription automatically | Retain all existing contract locks; no automatic €69/€89 migration or provider PATCH |
| Tax/total display | Fallback quote supplies excluding-VAT cents and no provider total; source base checkout converts selected cents directly to Mollie amount | Exact fiscal quote/checkout amount parity remains unresolved; do not invent a VAT percentage or claim a verified provider total |

Relevant Business files:

- `lib/app_config.dart`: `SubscriptionPlanCatalogEntry`, `resolveSubscriptionCatalogEntryForMarket`, backend profile defaults, checkout quote calls.
- `lib/main_parts/company_subscription_billing_state.dart`: plan display name, founder copy, hero price, locked price priority, add-on labels.
- `lib/company/subscription_checkout_quote_pipeline.dart`: current missing-quote-route fallback uses server profile cents; no invented VAT/Mollie total.
- `lib/company/fluxidi_play_distribution.dart`: Play builds prohibit company SaaS purchases while allowing entitlement/status reads; physical ride payments remain separate.

Relevant Backend files:

- `workers/booking/fluxidi_booking_worker.js`: `SUBSCRIPTION_MARKET_CATALOG`, `SUBSCRIPTION_ADDON_CATALOG`, `/company/subscription/checkout/start`, `/company/subscription/add-ons/checkout/start`, `loadFluxidiSubscriptionMollieConfig`, `_syncFluxidiConsolidatedRecurringAmount`, `_reconcileFluxidiRecurringSubscriptionForProfile`.
- `workers/booking/modules/recurring_billing.mjs`: consolidated amount and proration helpers; explicit saved add-on lock requirement.
- `workers/booking/modules/subscription_operator_contract_change.mjs`: explicit confirmed contract snapshots; catalog proposals must not silently become existing locks.

## Read-only live inventory

Cloudflare deployment metadata observed on 2026-10-04, before this report: Booking version `78103b58-7e5d-4be2-a21a-193fb389026c`. Direct KV inventory completed in two bounded key-list pages: 20 scoped `:subscription:v1` records, wrapped under `subscription_profile`; 14 trialing, 4 active, 2 payment_required. No raw tokens, keys, emails, provider identifiers or full records were printed.

- 16 records have stored normal price 6900 cents, 2 have 4900 cents, 2 have no normal price.
- Taxi Mario: trialing, stored normal 6900/founder 5900, no base lock, no saved Mollie customer/subscription/mandate identifiers. The screenshot's 7 vehicles/21 drivers does not prove a paid add-on or charge.
- Four active records contain saved provider identifiers and locked bases 5900, 4900, 4900 and 6900 cents. These are stored contract evidence, not proof that real provider objects exist or were charged in live mode.
- The Fluxidi scoped record contains base lock 6900 and recurring amount 13500 cents, with 3 extra vehicles and 1 extra driver: 6900 + 3 × 1900 + 900 = 13500. Its saved add-on unit locks are null. Current-source recurring synchronization fails closed when those locks are missing; silently backfilling from catalog would change contract authority and was not done.
- No authoritative inclusive-VAT recurring snapshot was present in these four active records.

Live metadata has secret bindings named `FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY`, `FLUXIDI_SUBSCRIPTION_MOLLIE_MODE`, and `FLUXIDI_SUBSCRIPTION_WEBHOOK_SECRET`. Binding presence does not reveal value, test/live mode or provider price. No dedicated local SaaS key/helper was available in the known authorized configuration. Actual Mollie GET verification was therefore not possible; central ride/Connect credentials were deliberately not substituted. Worker source download through the current OAuth read scope returned 401, so this audit distinguishes authoritative local source from live metadata/KV evidence.

The existing `/admin/subscription/profile` GET and company subscription-profile GET were not called: they can materialize cancellation/suspension or trial state. No truly read-only exposed SaaS provider-amount diagnostic route was found. A subsequent authenticated read-only provider inventory requires the exact SaaS credential or a separately reviewed diagnostic handler, not a financial mutation.

## User screenshot and narrow UI repair

User screenshot `C:/Users/cvanr/AppData/Local/Temp/codex-clipboard-f8e1b9c6-5ce9-4e23-8e6e-55868e6d8060.png` shows “Fluxidi Pro België €69/month excl. btw”, trial state and add-on prices €19/€9. The add-on and PDF-section Play informational notices are cut off horizontally. This is real user-reported Business58 acceptance evidence; it is not proof of Mollie parity.

After the parent independently confirmed Business59 Internal completed and authorized this UI-only repair, `_playSaasManagedOutsideNotice` stopped using the compact single-line `_chip`. It now uses `FluxidiPlaySaasManagedOutsideNotice`: bounded full card width, expanded wrapping text, natural height and a top-aligned info icon. NL/EN/FR/ES copy, colors, purchase blocking, entitlement reads and financial logic are retained. No URL or payment action was added.

Files owned by this repair:

- `lib/company/fluxidi_play_distribution.dart`: wrapping informational widget added; existing gates/copy unchanged.
- `lib/main_parts/company_subscription_billing_state.dart`: only the notice-builder body changed by this subtask; earlier unrelated dirty work preserved.
- `test/company/play_saas_notice_layout_test.dart`: 24 actual widget layouts across NL/EN/FR/ES, 240/540/1100 px card widths and text scales 1/2. Full visible-word boxes and final content fit; following content starts below the notice; no purchase actions.

Evidence: relevant Play/layout/catalog/quote/add-on suites **71/71 PASS**. Explicit analysis of the notice module, billing state part and new widget suite: **no issues**. The first selection-box check included invisible trailing spaces at wrap boundaries; it was corrected to check every visible word, including the final word, without relaxing the layout bounds.

Logs:

- `C:/Users/cvanr/AppData/Local/Temp/fluxidi-business60-play-notice-tests.log`
- `C:/Users/cvanr/AppData/Local/Temp/fluxidi-business60-play-notice-analyze.log`

This subtask performed no AAB build, Play upload, installation, backend deploy or Git mutation. Parent owns the subsequent controlled Business60 release. Actual installed Business60 notice acceptance remains to be observed.

## Minimal next financial scope

1. Obtain the existing confirmed Standard/Smart feature and market matrix; do not invent allowances or Free/WhiteLabel prices.
2. Implement new-tier catalog/selection and disable new founder reservations across backend and app, including persisted trial-profile price compatibility. Keep legacy active locks and founder contract display where genuinely applicable.
3. Resolve fiscal quote/checkout/recurring amount semantics and verify actual Mollie objects with the dedicated SaaS credential using GET only.
4. Add focused new-signup, stale-trial-price, no-founder, €19/€9 add-on, fiscal total and existing-contract-preservation tests before any financial release. No existing provider amount change is implicitly authorized by a catalog or UI repair.

## Business60 Internal completion — 2026-10-04

Ordinary com.fluxidi.tracking 1.0.7(60), min24/target36, includes59native duty repairs plus the narrow wrapped billing notices. 71 relevant Play/layout/catalog/quote/add-on tests PASS; explicit notice/billing/test analyzer no issues. AAB399996879bytes, SHA25674e40e527b5db95124f9057ab0fd4ebb224e649eb68108e8552d5e25ba61b25a, immutable TEMP/fluxidi-business60-verified-release.aab. Existing B8479589...A33FE upload certificate verified, assets420 PASS, source1780files/HEAD/staged fixed/no drift. Play Internal completed edit06306435737237688108; independent fresh readback60completed, public production4 unchanged. Tablet Play download is in progress; installation and real native-GPS/notice acceptance have not yet been inferred from that download. No subscription price/entitlement/contract/charge change included.


## Subsequent installed and provider diagnostic evidence

Business60 tablet package installation through GooglePlay confirmed lastUpdateTime2026-10-04 15:38:33. Foreground DriverDutyService and25s GPS/network provider registration observed15:41; this is not proof of server GPS acceptance or screen-off survival. Billing notice visual acceptance remains pending.

Booking GET-only admin provider diagnostic deployed separately as efb4df0e-b0ef-4492-a65d-8e2c4422ec43; root independently verified66focused/3049fullBookingPASS, exactcandidate/live SHAe0abd3272ead72d6f0e777eb22f2ea8ebabf3fe7f417b2981ef9bbd9e6646297, originalbindings/runtime unchanged. Actual four exact active-scope GETs authenticated but returned502 provider_network_error/customer; real provider prices/mode remain unverified. Local workerd reproduction identified unsupported fetch redirect:error before outbound; narrowly repairing manualredirect+failclosed3xx is in progress. No financial or profile mutation occurred.

## 2026-10-04 16:50 — verified test-provider amounts and status mismatch

The ordinary Bookingworker diagnostic is now deployed as cf37a433-433e-45e3-9c65-25c92330fead (83 diagnostic tests and 3066 complete Booking tests PASS). Four actual exact-scope provider GET checks returned200. All saved recurring amounts match Mollie:59EUR founder-test,49EUR patch32-test,49EUR Prometheus,135EUR Fluxidi. Every provider subscription is TESTMODE/CANCELED; all four saved statuses say ACTIVE. This is not proof of live billing or successful collection. No financial/status migration was made. Fluxidi addon unit locks and all four VAT-inclusive snapshots remain absent. Full evidence is the Backend docs/SUBSCRIPTION_PROVIDER_DIAGNOSTIC_20261004.md and safe TEMP provider projection. Standard69/Smart89/no-new-founders instruction remains separate from the incomplete plan entitlement/market/fiscal contract.
