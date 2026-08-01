# RELEASE-P0 — Human booking ID allocator (Option A′)

## Goal

Atomic allocation of planned booking IDs `YYYY-MM-NNN` without renaming
`booking:{id}` keys or changing the public ID format.

## Lifecycle

### Old (legacy KV)

1. Read `seq:YYYY-MM` from `BOOKING_KV`
2. Increment and put
3. Form `YYYY-MM-NNN`
4. Optionally check `booking:{id}` existence (racy)
5. Unconditional `BOOKING_KV.put(booking:{id}, …)`

### New (DO, flag on)

1. Resolve Brussels-local `YYYY-MM` from pickup ISO
2. Lazy/admin seed DO `next = max(current, legacy seq, max booking suffix)`
3. Atomically allocate via Durable Object `HUMAN_BOOKING_ID_SEQUENCE` named `YYYY-MM`
4. Re-check `booking:{id}` empty; on collision allocate again (bounded)
5. Persist with create-if-absent (`persistNewBookingRecord`)
6. Intent-key idempotency unchanged (`booking_intent:…`)

Street rides (`street_*`), payment shadows, Chiron ritnummers, and public
booking references (`BOOKING_REFERENCE_SEQUENCE`) are unchanged.

## Feature flag

| Var | Meaning |
|-----|---------|
| `HUMAN_BOOKING_ID_DO_ALLOCATOR=0` | Legacy KV sequence (default / rollback) |
| `HUMAN_BOOKING_ID_DO_ALLOCATOR=1` | Durable Object allocator |

Create-if-absent protection stays active on both paths.

## Staged rollout

1. Deploy worker with DO binding/migration and flag **off**
2. Seed current month (admin):
   ```bash
   curl -X POST "$BASE/admin/booking-id-allocator/seed?year_month=YYYY-MM" \
     -H "x-admin-token: $ADMIN_TOKEN" -H "content-type: application/json" -d "{}"
   ```
3. Verify:
   ```bash
   curl "$BASE/admin/booking-id-allocator/status?year_month=YYYY-MM" \
     -H "x-admin-token: $ADMIN_TOKEN"
   ```
   Require `seed_floor >= max_existing_suffix` and DO `next >= seed_floor`.
4. Set `HUMAN_BOOKING_ID_DO_ALLOCATOR=1` and redeploy
5. Controlled concurrent sandbox creates → distinct IDs, both records readable
6. Keep rollback ready

## Rollback

1. Set `HUMAN_BOOKING_ID_DO_ALLOCATOR=0` and redeploy
2. Restore KV sequence:
   ```bash
   curl -X POST "$BASE/admin/booking-id-allocator/rollback-prepare" \
     -H "x-admin-token: $ADMIN_TOKEN" -H "content-type: application/json" \
     -d '{"year_month":"YYYY-MM","apply":true}'
   ```
   This writes `seq:YYYY-MM = max(DO next, legacy seq, max booking suffix)`.
3. Do **not** delete DO data or rewrite historical `booking:{id}` rows
4. Create-if-absent remains enabled

## Admin endpoints

| Method | Path | Auth |
|--------|------|------|
| GET | `/admin/booking-id-allocator/status` | admin token |
| POST | `/admin/booking-id-allocator/seed` | admin token |
| POST | `/admin/booking-id-allocator/rollback-prepare` | admin token |
| POST | `/admin/booking-id-allocator/allocate-probe` | admin token |

## Tests

```bash
node --test workers/booking/human_booking_id_allocator_p0.test.mjs
```
