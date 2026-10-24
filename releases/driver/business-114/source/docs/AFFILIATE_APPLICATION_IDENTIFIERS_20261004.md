# Affiliate application identifiers — 2026-10-04

## Confirmed requirement and actual before failure

The original `fluxidi_ratehawk_hotels_p0/docs/AFFILIATE_INTEGRATION_HANDOFF.md:93–96` requires applicable business/tax identifiers. The previous shared affiliate application had only person/business type, name/legal name, address and country. It did not read the personal CustomerProfile's existing VAT/registration fields; it never borrowed a company administrator profile. The old request whitelist and stored affiliate profile also omitted identifiers.

Before the repair, the actual Flutter widget regressions failed twice: the business application had no identifier inputs, and the CEO review did not show supplied identifiers. Log: `%TEMP%/fluxidi-affiliate-identifiers-before-20261004.log`.

## Narrow shared app change

Authoritative sources are `D:/Projecten/_flutter_work/fluxidi_business_internal47` and `D:/Projecten/_flutter_work/fluxidi_customer_dev`. Seven changed shared source files and the new test are byte-identical in both roots; the Customer originals were checked against the prior frozen hashes before copying these exact files. Referral registration/client/onboarding/session-store and hotel/booking/native/pricing sources were not changed by this task.

- Business applicants can enter optional `company_registration_number` and `vat_number`. The client preserves actual case/spaces, accepts empty/unknown values, bounds strings to 64 UTF-16 code units and rejects C0/C1/DEL plus U+2028/U+2029 consistently with the backend. No country format, VAT validity, registration eligibility, company-profile inference or monetary assumption is added.
- Creation posts those supplied fields using the captured personal Customer bearer and existing terms version.
- The private own overview parses a typed applicant profile; absent legacy identifiers remain unknown. Own and CEO views show the actual identifiers or a localized “not provided” indication.
- Only a pending business application offers the owned edit dialog. Active/rejected/suspended applications remain read-only; personal/unknown applicant profiles have no update route in the UI. The repository independently rejects these states before a POST.
- The amendment is `POST /affiliate/application/identifiers` with the captured `expected_revision` and exactly the two entered strings. A blank string deliberately clears that field. The server remains responsible for current owner/revision/pending-business enforcement.
- The existing protected form handles logout/session changes, including covered-dialog removal without dismissing an unrelated covering route. Identifiers opt into preserving whitespace; existing other fields keep their former trim behavior. Late 200/401/409 for another account or a renewed bearer cannot enter the new session.
- All new form labels/help/unknown/error/edit text exists in Dutch, English, French, Spanish and German. Identifier errors have a dedicated localized message; existing other 400/409 handling is preserved.

The companion backend contract is in the authoritative Booking `docs/AFFILIATE_BACKEND_CONTRACT_20261004.md`, “Shared app contract.” Backend identifier-only updates leave status, bank data/revisions, programme terms and money unchanged. Backend implementation/review/deployment evidence belongs to the parent/backend agent and is distinct from the app fixture proof here.

## Local verification

Run from EACH app root:

```powershell
C:/dev/flutter/bin/flutter.bat test --no-pub test/affiliate/affiliate_identifiers_test.dart test/affiliate/affiliate_repository_test.dart test/affiliate/affiliate_page_test.dart test/affiliate/affiliate_admin_repository_test.dart test/affiliate/affiliate_personal_flows_test.dart test/affiliate/affiliate_admin_page_test.dart --reporter expanded
C:/dev/flutter/bin/flutter.bat analyze --no-pub lib/affiliate/affiliate_models.dart lib/affiliate/affiliate_repository.dart lib/affiliate/affiliate_page.dart lib/affiliate/affiliate_labels.dart lib/affiliate/affiliate_admin_models.dart lib/affiliate/affiliate_admin_page.dart lib/affiliate/affiliate_form_dialog.dart test/affiliate/affiliate_identifiers_test.dart
```

Business **94/94 PASS**; Customer **94/94 PASS**. Each contains the original 59 shared regressions and 35 new identifiers tests. Eight-item analysis: **No issues found** in each root. Logs: `%TEMP%/fluxidi-affiliate-identifiers-{business,customer}-gate-20261004.log` and matching `-analyze-20261004.log`.

New actual HTTP/repository/widget cases cover exact create/amend payloads, real form-to-request connection, personal-only bearer, optional/legacy values, malformed DTOs, string bounds/controls, explicit blank clearing, revision conflict, server bank/terms/balance preservation, pending-business gating, late A→B and same-person renewed-bearer 200/401/409, five-language phone dialog, captured server values, covered logout, late edit rendering and creation draft eviction.

This task performed no live affiliate request, provider call, build, deployment, upload, installation, payment or account/settings change. Source/local fixture success does not prove Android UI/OTP, production programme activation, provider reconciliation or bank execution. Independent read-only review is separately coordinated by the parent.

## Frozen shared source hashes

| File | SHA256 (same in both roots) |
| --- | --- |
| `lib/affiliate/affiliate_models.dart` | `4D441B02E5388C10C8080F3EF28F732489D956EC0CA6AF5FF2236CC295F6F67F` |
| `lib/affiliate/affiliate_repository.dart` | `5E624EBCF543864A03EE0A6334C98ABC9CAD3EAB8F54C92108E230F8F39610A3` |
| `lib/affiliate/affiliate_page.dart` | `C69215D11D85D91C734F4BE6E53758862467B4688C26762359997F295A598F8A` |
| `lib/affiliate/affiliate_labels.dart` | `7BA3DD3D74B206ABD4C60F91F74E810891EADF27500C775A5429252F9673F3C3` |
| `lib/affiliate/affiliate_admin_models.dart` | `C3596C476B1978F17F36852F078E308B86CE379CCC7C056CC4A163802C7BAD28` |
| `lib/affiliate/affiliate_admin_page.dart` | `F2B32B4C96991F27FA8B79379D1C3D6B41FA4951496A8F16E94E494C336B93BC` |
| `lib/affiliate/affiliate_form_dialog.dart` | `71070EA8D1D5B3F05B78F70137362D99AEA4C4A856492F7C99B1C032087F85B1` |
| `test/affiliate/affiliate_identifiers_test.dart` | `8D044486EE626AB9FE36585AF1898142F82B5A8EA325DA586D407740C1B87F47` |


## Independent app review

Reviewer release_readiness reported NO BLOCKER after exact final hash/parity checks and an independent Business35/35 identifiers regression run. Log: %TEMP%/fluxidi-affiliate-identifiers-app-independent-final-20261004.log. This review does not certify live/device acceptance.
