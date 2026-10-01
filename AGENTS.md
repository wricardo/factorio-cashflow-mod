# Repository Guidelines

## Project Overview

This repository's primary game module is the Factorio 2.0 **Cashflow Freeplay** mod in `factorio/cashflow-freeplay/`. It adds player-placeable, controller-owned personal-finance stations to ordinary Freeplay worlds:

- Iron plates represent $10 cash.
- Copper plates represent $10 bills/debt.
- Income and Expense stations emit monthly cash and bills.
- Cashflow, Debt, and Asset Warehouse stations process belt traffic.
- Each Cashflow Controller owns an independent account.

The root browser simulator is separate and shares no code with the mod.

## Architecture

- **Data stage:** `factorio/cashflow-freeplay/data.lua` declares placeable controller/station prototypes, hidden helper belts, and the licensed Warehouse artwork used by Asset Warehouse.
- **Runtime stage:** `control.lua` registers entities, links stations to controllers, owns persistent accounts in `storage.cf_freeplay`, validates construction, and drives the monthly simulation.
- **Station layout:** `script/station_layout.lua` creates hidden helper ports around each placeable station. Asset Warehouse is a 3×3 building with belt ports two tiles from its centre.
- **Domain boundary:** `script/accounting.lua` has no Factorio API dependency and owns integer-cent money math and month close calculations. Keep Factorio integration in `control.lua`, `stations.lua`, and `pulse.lua`.
- **Presentation:** `script/labels.lua` renders station/port labels and controller account status. `script/gui.lua` owns configuration UI.

## Key Files

- `factorio/cashflow-freeplay/control.lua` — lifecycle, entity registration, account linking, events.
- `factorio/cashflow-freeplay/data.lua` — placeable prototypes and Warehouse sprite setup.
- `factorio/cashflow-freeplay/script/station_layout.lua` — helper-port placement and cleanup.
- `factorio/cashflow-freeplay/script/accounting.lua` — pure finance engine.
- `factorio/cashflow-freeplay/script/stations.lua`, `pulse.lua`, `account.lua` — simulation orchestration.
- `factorio/cashflow-freeplay/script/labels.lua`, `gui.lua` — player-facing presentation.
- `factorio/cashflow-freeplay/THIRD_PARTY_LICENSES.md` — required Warehousing artwork attribution and MIT notice.
- `factorio/tests/accounting_test.lua`, `freeplay_test.lua`, `fake_factorio.lua`, `run.lua` — local tests.
- `factorio/cashflow-freeplay/TESTING.md` — in-game manual acceptance checklist.

## Development Commands

From repository root:

```bash
npm run test:factorio
npm run package:factorio
```

The test command runs `accounting_test.lua` and `freeplay_test.lua` against `factorio/cashflow-freeplay`. Packaging produces `factorio/dist/cashflow-freeplay_<version>.zip` with a top-level versioned mod directory.

The local machine has no installed Factorio runtime. The fake-Factorio suite is the local smoke proof; perform the relevant manual steps in `factorio/cashflow-freeplay/TESTING.md` on Factorio 2.0.x for in-game rendering, collision, and belt verification.

## Conventions

- Target Factorio 2.0 and Lua 5.2 compatibility; do not use Lua 5.3+ syntax.
- Store money as integer cents; one plate is 1,000 cents.
- Preserve account isolation: controllers only link stations on the same surface and force.
- Player-facing stations are placeable; only helper entities are hidden/locked.
- Belt traffic is the accounting interface. Do not bypass routing with direct inventory transfers except the existing per-station monthly buffers.
- Warehouse art is from Warehousing and must retain the notice in `THIRD_PARTY_LICENSES.md` and source comment if copied or changed.
- No formatter or linter is configured.
