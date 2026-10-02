# Repository Guidelines

## Project Overview

This repository's primary game module is the Factorio 2.0 **Cashflow Freeplay** mod in `factorio/cashflow-freeplay/`. It adds player-placeable, Account-owned personal-finance stations to ordinary Freeplay worlds:

- Iron plates represent $10 cash.
- Copper plates represent $10 bills/debt.
- Passive Income and Expense stations emit monthly cash and bills (passive income needs no player action).
- Active Income stations are earned income: each month the player carries a 50-coal batch from an unlinked Coal Supply into a linked Active Income station, which smelts it for 2 seconds and emits its configured salary as iron plates.
- Cashflow, Debt, and Investment Account stations process belt traffic.
- Each Account owns an independent set of linked stations.

Player-facing names differ from internal IDs, which stay unchanged so existing saves load: Account = `controller`, Passive Income = `income`, Active Income = `smelter`, Investment Account = `vault`. `script/labels.lua` holds the display-name table; change names there and in `locale/en/`.

The root browser simulator is separate and shares no code with the mod.

## Architecture

- **Data stage:** `factorio/cashflow-freeplay/data.lua` declares placeable controller/station prototypes. The controller is a 3×3 `market` (no inventory) drawn with Sosciencity's CC BY 4.0 Computing Center art; the five storage stations are chests with licensed Warehousing art; the Smelter (1-slot chest) and Coal Supply (20-slot chest) reuse vanilla electric-furnace and electric-mining-drill art.
- **Runtime stage:** `control.lua` registers entities, links stations to controllers, owns persistent accounts in `storage.cf_freeplay`, and drives the monthly simulation without restricting vanilla Freeplay content.
- **Station layout:** `script/station_layout.lua` creates hidden helper ports outside building footprints: Passive Income, Expense, Debt, and Active Income are 3×3 Storehouse-sized; Cashflow and Investment Account are 6×6 Warehouses. The Account and Coal Supply have no ports; Coal Supply is not a linkable role and is tracked only in `storage.cf_freeplay.coal_supplies` for refilling.
- **Domain boundary:** `script/accounting.lua` has no Factorio API dependency and owns integer-cent money math, month close calculations, and the yearly report summary. Keep Factorio integration in `control.lua`, `stations.lua`, `pulse.lua`, and `rules.lua`.
- **Settings:** `settings.lua` declares the runtime-global `cf-freeplay-month-seconds` (default 60). `script/rules.lua` is the only reader; income/expense station caps scale with it (`accounting.max_station_cents`) because the cap is a belt-throughput limit. There is no win condition; the game is free play.
- **Reports and alerts:** `pulse.lua` closes a yearly report every 12th month (stored in `cf.year_reports`, shown in the Account panel and chat). `stations.sweep` tracks `cf.unpaid_blocked_ticks`; `control.lua` alerts when unpaid bills cannot leave `UNPAID OUT` for `accounting.UNPAID_ALERT_TICKS`.
- **Presentation:** `script/labels.lua` renders station/port labels, hover-pane status, and controller account status. `script/gui.lua` owns configuration UI.

## Key Files

- `factorio/cashflow-freeplay/control.lua` — lifecycle, entity registration, account linking, events.
- `factorio/cashflow-freeplay/data.lua` — placeable prototypes and Warehouse sprite setup.
- `factorio/cashflow-freeplay/script/station_layout.lua` — helper-port placement and cleanup.
- `factorio/cashflow-freeplay/script/accounting.lua` — pure finance engine.
- `factorio/cashflow-freeplay/script/stations.lua`, `pulse.lua`, `account.lua` — simulation orchestration.
- `factorio/cashflow-freeplay/script/rules.lua`, `settings.lua` — month-length setting and its derived limits.
- `factorio/cashflow-freeplay/script/labels.lua`, `gui.lua` — player-facing presentation.
- `factorio/cashflow-freeplay/THIRD_PARTY_LICENSES.md` — required Sosciencity (CC BY 4.0) and Warehousing (MIT) artwork attribution.
- `factorio/cashflow-freeplay/migrations/` — JSON prototype renames for saves from older versions; `control.lua` finishes each one in `on_configuration_changed`.
- `factorio/tests/accounting_test.lua`, `freeplay_test.lua`, `fake_factorio.lua`, `run.lua` — local tests.
- `factorio/cashflow-freeplay/TESTING.md` — in-game manual acceptance checklist.

## Development Commands

From repository root:

```bash
npm run test:factorio
npm run package:factorio
```

The test command runs `accounting_test.lua` and `freeplay_test.lua` against `factorio/cashflow-freeplay`. Packaging produces `factorio/dist/cashflow-freeplay_<version>.zip` with a top-level versioned mod directory.

**Always install after finishing a change to the mod.** Bump `info.json`'s version, package, then copy the new zip into the user's mods folder and delete any other `cashflow-freeplay_*.zip` there, so Factorio loads exactly one version:

```bash
MODS="$HOME/Library/Application Support/factorio/mods"
cp factorio/dist/cashflow-freeplay_<version>.zip "$MODS/"
find "$MODS" -name 'cashflow-freeplay_*.zip' ! -name 'cashflow-freeplay_<version>.zip' -delete
```

`cashflow-freeplay` must stay `"enabled": true` in `$MODS/mod-list.json`. Report the installed version to the user.

The fake-Factorio suite is the primary local proof. Factorio 2.0.x is also installed at `/Applications/factorio.app`: for data-stage or save-migration changes, run it headless with an isolated `--config` (write-data under `/tmp`) and `--mod-directory`, using `--create <save>` and `--benchmark <save> --benchmark-ticks N`. A throwaway probe mod can `log()` state. Apart from installing the mod zip as above, never touch the user's real Factorio profile (saves, settings, other mods). Perform the relevant manual steps in `factorio/cashflow-freeplay/TESTING.md` for rendering, GUI, collision, and belt verification.

## Conventions

- Target Factorio 2.0 and Lua 5.2 compatibility; do not use Lua 5.3+ syntax.
- Store money as integer cents; one plate is 1,000 cents.
- Preserve account isolation: controllers only link stations on the same surface and force.
- Player-facing stations are placeable; only helper entities are hidden/locked.
- Belt traffic is the accounting interface. Do not bypass routing with direct inventory transfers except the existing per-station monthly buffers.
- Station art is from Warehousing (MIT) and controller art from Sosciencity (CC BY 4.0); both must keep their notices in `THIRD_PARTY_LICENSES.md` and the source comment in `data.lua` if copied or changed.
- Do not restrict vanilla entities, recipes, ghosts, research, or infrastructure; this is normal Freeplay with finance stations.
- No formatter or linter is configured.
