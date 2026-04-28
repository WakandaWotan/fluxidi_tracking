# Fluxidi Project Structure

## Single Source Of Truth

The single source of truth for Fluxidi is:

`C:\_flutter_work\fluxidi_tracking`

All active development, checks, and deployments must be run from this repository.

## Structure Overview

- `lib/` - Flutter application source code.
- `workers/booking/` - Active Booking Worker backup.
- `workers/tracking/` - Active Tracking Worker backup.
- `scripts/` - Safe operational PowerShell commands.
- `docs/ops/` - Operational documentation and runbooks.

## Operational Rules

- Old Desktop Codes folders are legacy/archive only.
- Do not deploy from old Desktop folders.
- Always run scripts and commands from the canonical repository path above.
- Do not copy terminal prompt text (for example `PS C:\...>`) into commands.
