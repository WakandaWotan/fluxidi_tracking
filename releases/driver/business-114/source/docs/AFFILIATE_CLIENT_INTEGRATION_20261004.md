# Affiliate app integration — 4 October 2026

## Scope and evidence boundary

Locally integrated and frozen for independent source review. No AAB build,
upload, installation, deployment, programme activation, provider/bank call,
historical financial mutation or real-device acceptance was performed by this
agent. Existing dirty files and other agents' work are preserved.

The authoritative source is this Customer root and
`D:/Projecten/_flutter_work/fluxidi_business_internal47`. Nine shared
`lib/affiliate` files are identical in both roots. The parent separately owns
`company_referral_registration.dart` and the CompanyOnboardingPage hookup;
that module was not overwritten.

Backend contract: ordinary Booking routes from
`fluxidi_booking_live_9af4c215_rc/docs/AFFILIATE_BACKEND_CONTRACT_20261004.md`.
No `/admin/affiliate/*` secret route is embedded in a client. The actual
`/affiliate/admin/*` surface requires a genuine personal bearer and the server's
durable CEO capability on every request and mutation transaction.

## Implemented user flows

- Visible ordinary Customer Profile entry and Business account-menu entry.
- Personal account recovery uses existing genuine Customer OTP; company-admin
  credentials never authenticate as an affiliate person. Business new-person
  recovery returns with a clear instruction to create the personal account in
  the Customer app, without replacing the active company home or credential.
- Actual server terms and accepted version, person/business application,
  pending/active/rejected/suspended status, active-only referral-code copy.
  No invented signup URL or unsolicited message/share.
- Actual server currency/cent balances, held receipt count, signed ledger
  corrections, paginated payout history and lazy personal referrals.
  Prepared/exported/cancelled payouts remain distinct from paid payouts;
  unavailable is never a fabricated zero balance.
- Bank-account addition/change uses normalized IBAN, account holder and exact
  captured affiliate revision. Server storage is encrypted, and a change must
  return verification false and increment account/affiliate revisions. No
  microcharge or bank/provider request originates in the client.
- Dutch, English, French, Spanish and German labels; bounded phone/tablet layout.

## Implemented CEO flows

- Server-proved `can_administer` opens a dedicated shared administration page.
- Applications review with exact revision, legal/profile details, human review
  reference and evidence confirmation; bank ownership verification is separate.
- Held payment review shows a localized reason. Invoice/VAT basis requires exact
  verified live paid receipt gross and refunded gross; reviewed credit note and
  correction policy are required for refunds. Chargebacks/unverified receipts
  have no invoice-basis shortcut.
- Known-ID receipt recovery and company-owner review use typed exact scoped
  requests and human evidence. No arbitrary endpoint or raw JSON UI.
- Monthly batch creation uses selected approved affiliates with verified bank
  accounts. Amounts and immutable manifest proof come only from the server.
- Export shows only the server review manifest and its actual bank/cent fields.
  It explicitly remains an unvalidated bank review, not an execution or payment.
- Cancellation submits the exact server proof and human reference; server refuses
  exported/paid shortcuts. Reconciliation requires evidence, bank execution
  reference, date/time picker and exact immutable item amount/currency.
- Incomplete company-registration recovery submits the captured server
  registration ID, payload hash, revision and review reference. It neither
  writes company profiles nor grants personal ownership.

## Ownership and lifecycle

Repository captures the genuine personal session/bearer/revision before async
work, checks the exact current owner before/after requests and parses only
private/no-store responses. Late A success, 401 or 403 cannot display A under B
or clear B. Disposal/expiry/logout discard private rows, draft fields, bank
details and manifests; no polling or personal-data persistence is added.

Owned dialogs scrub private fields and remove their own retained ModalRoute on
identity change. An unrelated covering route is preserved. Every dialog/picker
continuation checks mounted and exact owner before submitting.

Business CustomerSessionStore change is limited to revision notification at
save/remember/load/clear and protection against adopting a delayed old disk
owner. Company role/session store is untouched. This is not a broad legacy
session disk-serialization port; unrelated pre-existing store callers retain
their original scope and are not claimed repaired here.

## Meaningful local verification

- Customer `flutter test test/affiliate --no-pub --reporter expanded`: **59/59 PASS**.
- Ordinary nested Customer actual Profile → Affiliate → Back:
  `flutter test test/customer_affiliate_entry_test.dart --no-pub --reporter expanded`
  from `apps/fluxidi_customer`: **1/1 PASS**; no new fingerprint/back navigation.
- Business same shared tests plus actual personal disk/session/company-credential
  boundaries and personal-recovery navigation: **70/70 PASS**. This total includes
  the parent's eight company-referral-registration cases; own shared59 + own3.
- Customer `flutter analyze lib/affiliate test/affiliate
  apps/fluxidi_customer/lib/screens/customer_profile_screen.dart --no-pub`:
  **No issues**.
- Business `flutter analyze lib/affiliate test/affiliate
  lib/customer_session_store.dart --no-pub`: **No issues**.
- Business main-wide analysis has pre-existing findings outside affiliate
  imports/menu; it is not represented as globally clean.

Logs under `C:/Users/cvanr/AppData/Local/Temp/`:
`fluxidi-affiliate-customer-final-20261004.log`,
`fluxidi-affiliate-business-final-20261004.log`,
`fluxidi-affiliate-customer-entry-final-20261004.log`,
`fluxidi-affiliate-customer-analysis-20261004.log`,
`fluxidi-affiliate-business-analysis-20261004.log`,
`fluxidi-affiliate-business-main-analysis-20261004.log`.

Cases use actual widgets and actual HTTP request bodies with in-memory fake
transport, never live endpoints: guest zero requests; server capability denial;
late A200/401/403 after B; exact application terms; bank revision and revoked
verification; held/referral state; immutable server batch amounts/proof; no
chargeback shortcut; exact reconciliation evidence; incomplete registration
proof; phone/tablet evidence dialog; covered dialog logout; server failure retry.

## Source SHA-256 freeze

The nine shared files have identical bytes in both authoritative roots:

| File | SHA-256 |
| --- | --- |
| lib/affiliate/affiliate_models.dart | c98e05aa9af2d5a7c5474cfef1d71b0a1dc8a327aaf296a00ac8ba1007ae0f07 |
| lib/affiliate/affiliate_repository.dart | 9d15f19d4a596c5c5ca2ecbbc109e1a5b9771ad1d5b74f82c5487b39a7a7a086 |
| lib/affiliate/affiliate_labels.dart | e875616cf47fd60d9685a54506e58dc8b8a00f74ef7def86680f1124caa2d61b |
| lib/affiliate/affiliate_page.dart | 74687bae44d7eba1b290ccbd9c418f93f7fed30ac151cb17da3e7da6cf545b87 |
| lib/affiliate/affiliate_open.dart | fdb19b805b186cd8d0055b4e2e0342dbd82fb63358ee54d40be59cbc49478f43 |
| lib/affiliate/affiliate_form_dialog.dart | ec638deb0b2834222f7bc020d6e050d13183bb3e0408579e1867a18163202601 |
| lib/affiliate/affiliate_admin_models.dart | 3ccf2e04864979d6f5283f44d31c6c8afe9d3c0d128bb50215abffaaab674b6b |
| lib/affiliate/affiliate_admin_repository.dart | 8366ceb83e7df1a2efc32c1c189da62a4e46015f9df0426a1db60f21aefdfc08 |
| lib/affiliate/affiliate_admin_page.dart | 106abd72005c196903bfdabfa70481f0c62bac33135fcd7e2e3580eab06f1066 |

Own Customer integration/test hashes:

| File | SHA-256 |
| --- | --- |
| apps/fluxidi_customer/lib/screens/customer_profile_screen.dart | b971385952cafad70d155b962f5eeaec8cc83ad13789a104e485472e1470b560 |
| test/affiliate/affiliate_fixture.dart | e2cdf83d813fd21ecd6ca0161b0012627a6fdf32b9549e69efcf76403d471c90 |
| test/affiliate/affiliate_repository_test.dart | 2bbbd2b3000202e6253550e68ed5b5934e4e0afebc49a097d04aa0a6bad1cc80 |
| test/affiliate/affiliate_page_test.dart | da8ee82c751ddd141b22da1d9e4b114cce0565390f627f0f68afab0978136367 |
| test/affiliate/affiliate_admin_repository_test.dart | f988e3dadfec849d07cb0ec5392bd0d2556e119498c2e5dde0e01f21a4932693 |
| test/affiliate/affiliate_personal_flows_test.dart | 6c78db744ed2c290f127e598618a53f32c958012257517a22d90562c473cc3be |
| test/affiliate/affiliate_admin_page_test.dart | 9b47bfce73d3f429cf36e60bd6697b32fbd0390198a84901f747b8ce814a9eca |
| apps/fluxidi_customer/test/customer_affiliate_entry_test.dart | c2aa17a26c98b78e24d1715bf6869fd5adfe4ffed206e54a6b7a1c53ccead621 |

Business-specific hashes (main/part also contain preserved other owners' work):

| File | SHA-256 |
| --- | --- |
| lib/customer_session_store.dart | 8558562e698b9f7d4cec7db15b5a1adc7ea202d1e77d4962fe6b47d6816c9501 |
| lib/main.dart | 1a0913fdb9794592b721b456256186094f1f8c3b42c52cb87bac07eaa34d5434 |
| lib/main_parts/business_home_page_state.dart | a1eee6770dc25b5de297c3c727bad46cbc2e5c9df55f8032f70e45575c64f466 |
| test/affiliate/personal_session_boundaries_test.dart | 7e6e040b8ece25b885a14c0473844a244f9569b7fb8e8482e80298f3c976d311 |
| test/affiliate/personal_signin_navigation_test.dart | 16621c94a618fcd94b7936f0297220e77c45dbd71e9f5b07835c415e617ddfff |

## Website and remaining release prerequisites

Bounded local read-only discovery found Shopify source candidates in
`C:/Users/cvanr/.codex/.chatgpt-projects/g-p-6ac09370c358819196238ffa31dd6df3`
but no existing affiliate/CEO client in the searched UI/private-web files.
`fluxidi_command_center_unknown_status_p0/apps/web` is a local GET-only
foundation whose README forbids API/UI production cutover and production
admin-token reuse. Neither is verified as the current live CEO website. No
adjacent website project was edited or published, and shared Flutter source
alone is not website integration proof.

Programme remains fail-closed until separately approved server configuration:
terms/policy, encrypted bank key, SQLite binding/migration and CEO capability.
Actual automatic net/VAT producer, correction-policy and Fortis bank-format /
execution import evidence remain parent/backend release prerequisites. Source
and fixture completion does not prove real-person OTP/device/live finance UI.

## Subsequent shared identifiers candidate and final joint gate

The missing confirmed business/tax identifier requirement is now implemented in both authoritative app roots. Seven shared files and the new identifiers test supersede those files' earlier hashes in this document; the exact new hashes,35 new actual request/widget cases and independent no-blocker review are in `AFFILIATE_APPLICATION_IDENTIFIERS_20261004.md`. Application creation, typed own/CEO views and pending-business-only owner/revision amendments use actual supplied optional values. No company-admin profile autofill, status/bank/terms or monetary change.

Final parent combined suites: Customer117/117, Business119/119, nestedCustomer entry1/1 PASS; scoped analyses clean. Backend4239/4239 PASS, including affiliate60/60. Evidence paths and remaining external/device activation gates are in `AFFILIATE_REFERRAL_REGISTRATION_20261004.md` and the authoritative backend `docs/INTEGRATION_OPEN_ITEMS_20261004.md`. No build/deploy/upload/install or financial action occurred.
