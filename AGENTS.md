# Repository Guidelines

## Project Overview

This repository is the Factorio 2.0 **Cashflow** mod; the repository root is the mod root (`info.json`, `control.lua`, `data.lua`, ...). It adds player-placeable, Account-owned personal-finance stations to ordinary Freeplay worlds:

- Iron plates represent $10 cash.
- Copper plates represent $10 bills/debt.
- Passive Income and Expense stations emit monthly cash and bills (passive income needs no player action).
- Active Income stations are earned income: each month the player carries a 50-coal batch from an unlinked Coal Supply into a linked Active Income station, which smelts it for 2 seconds and emits its configured salary as iron plates.
- Cashflow, Debt, and Investment Account stations process belt traffic.
- Each Account owns an independent set of linked stations.

Player-facing names differ from internal IDs, which stay unchanged so existing saves load: Account = `controller`, Passive Income = `income`, Active Income = `smelter`, Investment Account = `vault`. `script/labels.lua` holds the display-name table; change names there and in `locale/en/`.

## Layout

```
info.json  changelog.txt  control.lua  data.lua  settings.lua   mod entry points (shipped)
locale/  migrations/  script/  graphics/  THIRD_PARTY_LICENSES.md   shipped
tests/      fake Factorio runtime, test suites, and the manual in-game checklist (README.md); not shipped
scripts/    package.sh, install-latest.sh, and build-install-local.sh; not shipped
README.md  AGENTS.md  package.json                              not shipped
```

`scripts/package.sh` copies an explicit list of shipped files into `dist/cashflow-freeplay_<version>/`; add new top-level shipped files to that list.

## Architecture

- **Data stage:** `data.lua` declares placeable controller/station prototypes. The controller is a 3×3 `market` (no inventory) drawn with Sosciencity's CC BY 4.0 Computing Center art; the five storage stations are chests with licensed Warehousing art; the Smelter (1-slot chest) and Coal Supply (20-slot chest) reuse vanilla electric-furnace and electric-mining-drill art.
- **Runtime stage:** `control.lua` registers entities, links stations to controllers, owns persistent accounts in `storage.cf_freeplay`, and drives the monthly simulation without restricting vanilla Freeplay content.
- **Station layout:** `script/station_layout.lua` creates hidden helper ports outside building footprints: Passive Income, Expense, Debt, and Active Income are 3×3 Storehouse-sized; Cashflow and Investment Account are 6×6 Warehouses. The Account and Coal Supply have no ports; Coal Supply is not a linkable role and is tracked only in `storage.cf_freeplay.coal_supplies` for refilling.
- **Domain boundary:** `script/accounting.lua` has no Factorio API dependency and owns integer-cent money math, month close calculations, and the yearly report summary. Keep Factorio integration in `control.lua`, `stations.lua`, `pulse.lua`, and `rules.lua`.
- **Settings:** `settings.lua` declares the runtime-global `cf-freeplay-month-seconds` (default 60). `script/rules.lua` is the only reader. Income, Active Income and Expense stations are capped at a fixed `accounting.MAX_STATION_CENTS` ($20,000) at any month length. There is no win condition; the game is free play.
- **Reports and alerts:** `pulse.lua` closes a yearly report every 12th month (stored in `cf.year_reports`, shown in the Account panel and chat). `stations.sweep` tracks `cf.unpaid_blocked_ticks`; `control.lua` alerts when unpaid bills cannot leave `UNPAID OUT` for `accounting.UNPAID_ALERT_TICKS`.
- **Presentation:** `script/labels.lua` renders station/port labels (port labels use plate icons and alt-mode only), hover-pane status, and controller account status. `script/gui.lua` owns configuration UI: the Account is a centered `gui.screen` dialog registered as `player.opened` and refreshed in place by `gui.refresh_player` (called from the 30-tick label loop); station and Percent Splitter panels dock in `gui.left` and close via `on_gui_closed`. Every panel is `titlebar` + `body`, with validation shown in `body.error` through `gui.show_error`. Panel captions are locale keys in `locale/en` section `[cf-gui]`; the fake runtime's `fake.localise` resolves them against that file so a missing key fails a test.
- **Percent Splitter:** `cf-freeplay-percent-splitter` is a tinted copy of the vanilla splitter that links to no Account. `control.lua` keeps `storage.cf_freeplay.splitters[unit_number] = { entity, percent, label }` and sets `splitter_output_priority` every tick from `script/split.lua`, a pure 100-tick-window schedule (one contiguous left block per window; interleaving aliased against belt item spacing in real-engine measurements). `remote.call("cashflow-freeplay", "set_splitter_percent", entity, percent)` sets it from scripts.

## Key Files

- `control.lua` — lifecycle, entity registration, account linking, events.
- `data.lua` — placeable prototypes and Warehouse sprite setup.
- `script/station_layout.lua` — helper-port placement and cleanup.
- `script/accounting.lua` — pure finance engine.
- `script/stations.lua`, `pulse.lua`, `account.lua` — simulation orchestration.
- `script/rules.lua`, `settings.lua` — month-length setting.
- `script/labels.lua`, `gui.lua` — player-facing presentation.
- `THIRD_PARTY_LICENSES.md` — required Sosciencity (CC BY 4.0) and Warehousing (MIT) artwork attribution.
- `migrations/` — JSON prototype renames for saves from older versions; `control.lua` finishes each one in `on_configuration_changed`.
- `changelog.txt` — player-facing version history in Factorio's changelog format.
- `tests/accounting_test.lua`, `split_test.lua`, `freeplay_test.lua`, `fake_factorio.lua`, `run.lua` — local tests.
- `tests/README.md` — in-game manual acceptance checklist.
- `.github/workflows/release.yml` — tag-triggered test, package, and GitHub release publication.

## Development Commands

From repository root:

```bash
npm test
npm run package
npm run install:local
```

The test command runs `accounting_test.lua`, `split_test.lua` and `freeplay_test.lua` against the repository root. Packaging produces `dist/cashflow-freeplay_<version>.zip` with a top-level versioned mod directory. `npm run install:local` builds the working tree, removes older `cashflow-freeplay_*.zip` files from the macOS Factorio mods directory, installs the current zip, and enables it in `mod-list.json`; set `FACTORIO_MODS_DIR` to target an isolated mods directory. `scripts/install-latest.sh` queries the newest GitHub release and installs the matching zip on macOS. Pushing a `v<info.json version>` tag runs `.github/workflows/release.yml`, which tests, packages, and publishes that zip.

**Always run `npm run install:local` after finishing a change to the mod.** Bump `info.json`'s version and add a matching `changelog.txt` entry before player-facing releases. `cashflow-freeplay` must remain enabled in `$HOME/Library/Application Support/factorio/mods/mod-list.json`. Report the installed version to the user.

The fake-Factorio suite is the primary local proof. Factorio 2.0.x is also installed at `/Applications/factorio.app`: for data-stage or save-migration changes, run it headless with an isolated `--config` (write-data under `/tmp`) and `--mod-directory`, using `--create <save>` and `--benchmark <save> --benchmark-ticks N`. A throwaway probe mod can `log()` state. Apart from installing the mod zip as above, never touch the user's real Factorio profile (saves, settings, other mods). Perform the relevant manual steps in `tests/README.md` for rendering, GUI, collision, and belt verification.

## Conventions

- Target Factorio 2.0 and Lua 5.2 compatibility; do not use Lua 5.3+ syntax.
- Store money as integer cents; one plate is 1,000 cents.
- Preserve account isolation: controllers only link stations on the same surface and force.
- Player-facing stations are placeable; only helper entities are hidden/locked.
- Belt traffic is the accounting interface. Do not bypass routing with direct inventory transfers except the existing per-station monthly buffers.
- Station art is from Warehousing (MIT) and controller art from Sosciencity (CC BY 4.0); both must keep their notices in `THIRD_PARTY_LICENSES.md` and the source comment in `data.lua` if copied or changed.
- Do not restrict vanilla entities, recipes, ghosts, research, or infrastructure; this is normal Freeplay with finance stations.
- No formatter or linter is configured.
