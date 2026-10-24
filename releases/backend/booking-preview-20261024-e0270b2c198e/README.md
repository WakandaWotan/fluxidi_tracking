# Live Booking preview and confirmed ASAP source

Exact full backend source closure for booking-b113-preview-current-20261024-e0270b2c198e; 403 original source files retain their sealed bytes. This is the backend release snapshot in the existing Fluxidi repository, not a partial patch on an older Worker. Merge this commit into the Driver integration branch before building the next Driver AAB. Mobile source is owned by Agent 1 and is not modified here.

The active artifacts and runtime IDs are in RELEASE.json. The preview formatter is the sole source difference from the live ASAP parent. Existing financial, tenant, authorization and reservation behavior is preserved. Booking/Tracking production readback passed; the unchanged Navigation relay is included for provenance.

No production bindings, environment files, secret values, R2 publications, customer records or request captures are included. Runtime configuration remains managed separately. The active/ directory is only the previous Booking artifact used by claim-security regression tests; it is not the current active runtime.

With Node 24 and esbuild 0.27.0 installed, npm run verify:runtime reconstructs the existing Booking and Tracking artifact bytes in memory and compares all hashes; it does not deploy or write Worker artifacts. npm test runs the applicable local backend matrix using synthetic data. The separately developed, unactivated missionDirections finance-contract test remains present but excluded from this release matrix; it is not reported as green. The additional native and published-mobile contract results are recorded in RELEASE.json and the original seal.

Physical acceptance is OPEN. Ride 487 assignment_driver_no_vehicle, the exact device navigation failure and roughly 9.8 seconds of booking confirmation time remain unresolved. A successful deployment or source commit does not prove physical route rendering or a complete trip. Existing persisted list rows are only updated through normal authorized projection publication; no ride state was manually changed.
