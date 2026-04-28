# Fluxidi Tracking

Fluxidi mobile + worker backups repository.

## Single Source Of Truth

The canonical repository path is:

`C:\_flutter_work\fluxidi_tracking`

All active work must happen from this path.

## Project Overview

- Flutter app source lives in `lib/`.
- Active Booking Worker backup lives in `workers/booking/`.
- Active Tracking Worker backup lives in `workers/tracking/`.
- Operational scripts live in `scripts/`.
- Operational docs live in `docs/ops/`.

## Quick Start Commands

From repository root:

- `powershell -ExecutionPolicy Bypass -File .\scripts\check-flutter.ps1`
- `powershell -ExecutionPolicy Bypass -File .\scripts\status-all.ps1`
- `powershell -ExecutionPolicy Bypass -File .\scripts\deploy-booking-worker.ps1`
- `powershell -ExecutionPolicy Bypass -File .\scripts\deploy-tracking-worker.ps1`

## Operations Documentation

- [Project Structure](docs/ops/PROJECT_STRUCTURE.md)
- [Deployment](docs/ops/DEPLOYMENT.md)

## Do / Don't

Do:

- Use this repository as the only active source.
- Use scripts in `scripts/` for checks and deployment steps.

Don't:

- Do not deploy from old Desktop Codes folders (legacy/archive only).
- Do not copy terminal prompt text such as `PS C:\...>` into commands.
