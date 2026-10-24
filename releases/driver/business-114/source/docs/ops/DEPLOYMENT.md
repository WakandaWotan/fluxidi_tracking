# Fluxidi Deployment

## Canonical Repository

Use only this repository for deployment operations:

`C:\_flutter_work\fluxidi_tracking`

Legacy Desktop folders are archive-only and must not be used for deployment.

## Booking Worker

Run:

`.\scripts\deploy-booking-worker.ps1`

The script deploys from:

`C:\_flutter_work\fluxidi_tracking\workers\booking`

Preflight check:

- `node --check .\fluxidi_booking_worker.js`

Deploy command:

`wrangler deploy --config ".\wrangler.toml" --keep-vars`

## Tracking Worker

Run:

`.\scripts\deploy-tracking-worker.ps1`

The script deploys from:

`C:\_flutter_work\fluxidi_tracking\workers\tracking`

Preflight check:

- `node --check .\fluxidi_tracking_api_worker_V2_1_with_route_index.js`

Deploy command:

`wrangler deploy --config ".\wrangler.toml" --keep-vars`

## Post-Deploy Checks

After deployment, verify:

- Worker URL is correct and reachable.
- Version ID is returned by Wrangler output.
- No deployment was executed from legacy/archive folders.

## Command Hygiene

- Never paste terminal prompt text (for example `PS C:\...>`) into commands.
