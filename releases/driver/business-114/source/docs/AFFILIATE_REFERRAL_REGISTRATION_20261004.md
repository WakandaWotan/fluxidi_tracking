# Affiliate referral at company registration — 4 October 2026

## Current source candidate

The optional referral flow is integrated in both authoritative apps and uses the ordinary Booking route `/public/company/register`. It authenticates with the genuine personal global Customer OTP session, never the current company administrator bearer. It supplies a server-supported immutable registration request ID and normalized referral code. No programme activation, deployment, AAB, upload, bank/payment/provider action or real-device acceptance is represented by this report.

The new optional field and existing personal recovery route are in `lib/company_onboarding_page.dart`. Both apps share the exact onboarding prefix; the Customer's existing `CompanyProfileEditPage` tail remains byte-identical to its previous source (SHA256 `3cb5fd60bcfac9400e147806f8316ef541a1d8cca6b2f8c635fe5d1b1a696c45`). Business's separately repaired profile editor is preserved. Only the audited prefix was ported; no whole legacy file replacement was used.

## Duplicate and ownership protection

- Secure persisted intent contains only SHA256 owner/form digests, a random request ID and attempt count. Names, email, referral code, company and personal tokens and the full form are not persisted here.
- Intent write is read back before sending a request. A lost response, app-client recreation, server completion-pending or local save failure retains the exact ID; edited ambiguous forms cannot silently allocate a different company.
- Removing a referral code cannot bypass a pending same-owner registration via anonymous signup. Another genuine person has a separate owner digest and is not shown the previous person's metadata.
- The optional ownership callback captures the company/profile context before OTP load or POST, is checked after awaits, and is retained through session save and intent clear. A company-only switch during HTTP cannot become the captured store owner of a late reply.
- The store entry follows the HTTP/company check synchronously. During the store's own expected adoption, its captured company references guard every async IO and synchronous notifier publication. Immediately after return the page checks the exact returned company and bearer, then records the exact adopted references for completion. Personal ownership remains guarded throughout.
- Only an exact first, private/no-store pre-commit refusal can unlock correction of an invalid VAT/form or unavailable programme/code. A similar refusal after ambiguous delivery retains the ID.
- Intent removal has readback and restores only its exact owned entry after a late owner change or failed removal. Failed restoration surfaces a storage error; it is not reported as completed. Global intent operations are serialized and preserve other owners.
- Backend attribution remains `held_owner_review` until actual legal owner proof. Personal OTP and the typed contact name do not establish beneficial ownership or entitlement.

## Verification

`test/affiliate/company_referral_registration_test.dart`: 13/13 PASS in each app. Cases include guest zero HTTP, actual personal bearer and privacy of persisted metadata, ambiguous retry using the same ID, edited request rejection, exact first pre-commit refusal, uncached refusal protection, anonymous pending bypass, storage failure, company-only switch during POST, delayed intent-clear logout/restore, restore failure, late A200/401 under B and concurrent edited forms.

`test/company/company_referral_persistence_test.dart`: 10/10 actual production-store temporary-IO cases in each app. Scope, asynchronous owner switches, partial rename rollback and synchronous notifier reentrancy are documented separately in `COMPANY_REFERRAL_PERSISTENCE_20261004.md`.

Combined current candidate: Customer `flutter test --no-pub test/affiliate test/company/company_referral_persistence_test.dart` 82/82 PASS; Business same command 84/84 PASS. Actual nested Customer Profile -> Affiliate -> Back 1/1 PASS. These counts overlap; do not add them as unique regressions.

Scoped analysis of affiliate, onboarding, company store and owned tests is clean in both apps. Business additionally includes its personal CustomerSessionStore. Existing unrelated whole-main warnings remain documented separately.

Independent source review matched both shared client/test bytes and the onboarding prefix, preserved Customer editor tail and all four store/test freeze hashes. Independent Business client13 + actual IO10 reruns passed. Logs are under `C:/Users/cvanr/AppData/Local/Temp/`: `fluxidi-affiliate-{customer,business}-integrated-20261004.log`, `fluxidi-affiliate-{customer,business}-root-analyze-20261004.log`, `fluxidi-affiliate-customer-nested-entry-final-20261004.log`, and `fluxidi-referral-{client,store}-independent-business-20261004.log`.

## Durability and release limits

This is an in-process owner fence and a narrowly guarded existing session store, not an OS-wide transaction across secure storage, profile/session files and processes. Power loss, forced process death between renames and a damaged filesystem are not certified crash-atomic. Server partial-registration recovery remains an evidence-reviewed operation; no blind local profile repair or reallocation is performed.

The current website/Command Centre owner, actual forward net/VAT producer and correction policy, bank export/import format, approved terms, encrypted bank key and genuine CEO capability remain activation/release gates. See `AFFILIATE_CLIENT_INTEGRATION_20261004.md` and backend `AFFILIATE_BACKEND_CONTRACT_20261004.md`. The human has explicitly paused new AAB/Internal releases until integration and testing are complete.

## Exact source candidate hashes

| Root | File | SHA256 |
| --- | --- | --- |
| fluxidi_customer_dev | lib/affiliate/company_referral_registration.dart | ce89a2c0d074e8eaa15cb82badd8f98cdc65c95e0e8c123e94ec382d81bb13ac |
| fluxidi_customer_dev | lib/company_onboarding_page.dart | f26c2221a6db61092434f7880ddd4446c7e2b85d0a9289d60fd9fa609276e8cd |
| fluxidi_customer_dev | test/affiliate/company_referral_registration_test.dart | d8e8a35541342f253e4c359ed1e5f88f7a020859fe6ad89097ad634b66fd4f7b |
| fluxidi_business_internal47 | lib/affiliate/company_referral_registration.dart | ce89a2c0d074e8eaa15cb82badd8f98cdc65c95e0e8c123e94ec382d81bb13ac |
| fluxidi_business_internal47 | lib/company_onboarding_page.dart | 9c13ff3fd76669955e3f5f5a290e33ae4cd172412ed7f61f212dc98042b21099 |
| fluxidi_business_internal47 | test/affiliate/company_referral_registration_test.dart | d8e8a35541342f253e4c359ed1e5f88f7a020859fe6ad89097ad634b66fd4f7b |

## Final combined gate after identifiers integration

With the separately frozen shared applicant identifiers integration, the parent reran the complete `test/affiliate` directory and `test/company/company_referral_persistence_test.dart`: Customer **117/117 PASS**, Business **119/119 PASS**. The real nested Customer profile -> Affiliate -> back entry remains **1/1 PASS**. Scoped analyses of affiliate/onboarding/session-store sources and their tests report **No issues found** in both roots. All client/test and guarded store/test hashes above remain unchanged. Logs: `%TEMP%/fluxidi-affiliate-{customer,business}-identifiers-joint-final-20261004.log`, matching `-analyze-final-20261004.log`, and `fluxidi-affiliate-customer-nested-identifiers-final-20261004.log`.

Backend combined gate is **4239/4239 PASS**, including the affiliate60 cases. The identifiers app/backend independent review found no blocker in scope. Current overall inventory: `D:/Projecten/_flutter_work/fluxidi_booking_live_9af4c215_rc/docs/INTEGRATION_OPEN_ITEMS_20261004.md`. Source/local tests remain separate from website integration, deployment, physical acceptance and programme activation; no new AAB or live action.
