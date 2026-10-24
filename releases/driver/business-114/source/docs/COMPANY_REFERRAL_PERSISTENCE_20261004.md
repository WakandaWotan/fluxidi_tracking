# Guarded affiliate company registration persistence — 2026-10-04

## Scope and caller contract

The only production changes owned by this subtask are each authoritative app's `lib/company_session_store.dart`: a typed exception, a new private guarded persistence path, and the optional `bool Function()? isCurrentRegistration` argument to `savePublicCompanyRegistrationSession`. Existing callers omitting the callback retain their previous method body and behavior. No onboarding, affiliate HTTP client, app_config, authentication, booking, tariff, hotel or backend source was edited here.

The referral caller must capture its personal owner and company context **before the registration HTTP request** and supply an exact ownership callback, including allowed adoption of this returned company session. The store snapshots company session/profile objects at method entry; this alone does not solve a company switch that happened before store entry. Parent owns that client/onboarding gate and the subsequent independent whole-flow review.

Successful guarded return means scoped profile and returned company bearer were staged, read back, committed and adopted while the callback and captured company identity remained current. Failure throws `CompanyRegistrationPersistenceException` with only `session_changed`, `registration_storage_failed`, or `invalid_registration_scope`. The caller must retain its durable referral retry intent on these failures; the store never removes that intent. The registration allocator actually sets tenant_id == company_id; the guarded path rejects mismatched or unsafe scopes instead of sanitizing them into another path.

## Implementation

- No globally adopting `loadProfileForCompany`, `loadSession`, `persistProfile`, backend-cache or bootstrap-hydration helpers are used by the guarded path. Existing scoped profile/session are read directly and never borrow another company's credentials.
- Asynchronous directory and staged-file operations are fenced after every await, against both the caller's personal owner proof and the captured company notifier identities.
- Stage files have unique `.registration_pending_...` suffixes and do not use discoverable canonical profile/session names. Writes are flushed and read back before final adoption.
- The small final target snapshots and renames are synchronous, with no await between the final ownership check and commit. Business's existing active-company pointer is committed last. Customer's older store has no active-pointer reader; its guarded path leaves that legacy behavior unchanged.
- Exceptions restore only target bytes still exactly equal to this operation's published bytes, and only notifiers/memory still exactly owned by this operation. A newer company's pointer or notifier is preserved. Checks after each ValueNotifier publication handle synchronous reentrant listeners before further adoption.
- Guarded success deliberately leaves business settings and backend-profile cache untouched. The legacy `applyProfileToBusinessNotifier` starts unguarded tenant-state persistence and pricing sync; the normal hub hydrates those later under its own existing flow.

## Actual local proof

Baseline actual Business save with the previous caller's outer ownership checks produced three behavioral failures and one positive pass: an owner change during the path-provider await still adopted A, a real session-target filesystem failure returned apparent success, and a reentrant B session listener still received A's profile. The baseline additionally had unfinished legacy cache writes during teardown; those cleanup errors are separately visible and are not counted as new behavioral regressions. Log: `TEMP/fluxidi-referral-store-before-20261004.log`.

Final new suite has ten actual production-store cases in each app: path-provider await owner switch; real filesystem failure; reentrant session listener; successful scoped persistence; same-person bearer renewal using CustomerSessionStore revision; company-only switch with personal callback still true; owner switch after a real staged file write; a fault-injected second rename restoring the first committed real profile file; reentrant profile listener/memory rollback; guarded invalid-scope rejection with legacy empty-response no-op. The positive also verifies business settings/backend-profile cache remain untouched. Only isolated temporary directories and fixture bearers are used; no actual user tokens or provider calls.

Business gate: **22/22 PASS**, including the existing startup-scope, company-ops and local-synthetic suites. Customer gate: **17/17 PASS**, including existing company-ops and local-synthetic suites. Each two-file scoped analyzer: **No issues**.

Commands (from the corresponding authoritative root):

```text
C:/dev/flutter/bin/flutter.bat test --no-pub test/company/company_referral_persistence_test.dart test/company/company_session_startup_scope_test.dart test/company/company_ops_session_test.dart test/company/local_synthetic_company_session_test.dart --reporter expanded
C:/dev/flutter/bin/flutter.bat test --no-pub test/company/company_referral_persistence_test.dart test/company/company_ops_session_test.dart test/company/local_synthetic_company_session_test.dart --reporter expanded
C:/dev/flutter/bin/flutter.bat analyze --no-pub lib/company_session_store.dart test/company/company_referral_persistence_test.dart
```

First command is Business only, second Customer only. Final logs are `TEMP/fluxidi-referral-store-business-gate-20261004.log`, `TEMP/fluxidi-referral-store-customer-gate-20261004.log` and corresponding `-analyze-` files. Removing only this subtask's guarded additions from current Customer store reproduces the exact pre-edit SHA256 `A2CEF15EC879B4C9CFBC167219DBA28357E240AA808A76C6EA38794C8A870EE2`; existing Customer source was preserved.

## Frozen SHA256

| Authoritative file | SHA256 |
| --- | --- |
| Business lib/company_session_store.dart | 6BD975E3FB6D73F3333C7574274B1184BC42563E354BD924C8A46152C592555B |
| Business test/company/company_referral_persistence_test.dart | 0A53533112D92D5EE54D889540A8386D751035A9A2EBAF23B40D640787048705 |
| Customer lib/company_session_store.dart | 95B53F1C61EEE60FC2BF6E8A4B2BBB699680D2C91770C3B204538D4038491412 |
| Customer test/company/company_referral_persistence_test.dart | DB0931A010285A35FDFCE8CB8583577ACD0FE83817A6DCA7A42336F11DA55E59 |

## Limits and acceptance

This is a main-isolate ownership/IO fence, **not** an OS-wide multi-file database transaction or a cross-process lock. Process death/power loss between synchronous renames and rollback failure on a damaged filesystem remain recovery limits; such durability is not certified here. The method fails visibly and does not claim successful persistence on a detected failure. Files use the existing company's credential storage format; this task does not redesign or migrate that format.

Client idempotency/precommit-validation policy, whole-operation HTTP ownership, form/dialog behavior, server registration/ledger completion, release/build/upload/install and real authenticated device acceptance are separate gates owned by parent/reviewer. No build, upload, sideload, device UI, deploy, secret read, provider request, financial/profile server write or Git mutation was performed by this subtask. Source and local fixture tests alone do not establish end-to-end signup completion.
