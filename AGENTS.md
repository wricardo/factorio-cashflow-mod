# Repository Guidelines

## Project Overview

This repository's primary game module is the Factorio 2.0 **Cashflow Factory** mod in `factorio/`. It models personal cashflow as a belt-driven factory:

- Iron plates represent $10 cash.
- Copper plates represent $10 bills/debt.
- The Cashflow station matches cash against bills.
- The Debt station handles borrowing and repayment.
- The Vault stores surplus cash/assets.

The repository also contains a separate, framework-free browser simulator at the root. It shares the domain concept but does not share code with the Factorio mod.

## Architecture & Data Flow

Factorio has two stages:

1. **Data stage** — `factorio/cashflow/settings.lua` declares runtime-global settings; `data.lua` defines locked station/belt/splitter/chest prototypes and the player-placeable meter belt.
2. **Runtime stage** — `control.lua` owns lifecycle, events, persistent state, and the simulation loop.

Runtime flow:

1. `control.lua` activates only for the `cashflow` scenario/mod, initializes `storage.cf`, reads settings through `script/config.lua`, and builds the dedicated surface through `script/world.lua`.
2. `script/stations.lua` moves iron/copper on belts, emits income and expenses, matches cash to bills, handles debt borrowing/paydown, deposits vault cash, and syncs the debt ledger.
3. `control.lua` runs station and meter sweeps every 2 ticks and refreshes GUI/labels every 30 ticks.
4. At `accounting.TICKS_PER_MONTH` (3,600 ticks), `script/pulse.lua` closes the month. It charges unbelted copper as debt, calls the pure accounting module, emits the next month's outputs, resets monthly state, advances the month, checks goals, and logs a report.
5. `script/gui.lua`, `labels.lua`, and `meter.lua` expose current balances, progress, and traffic to the player.

`factorio/cashflow/script/accounting.lua` is the domain boundary. It has no Factorio API dependencies and owns integer-cent money math, monthly rate conversion, plate rounding, emission timing, plate matching, fractional carry, month close, financial-independence checks, and money formatting. Keep game API integration in the surrounding modules.

## Key Directories

- `factorio/cashflow/` — packaged mod root.
- `factorio/cashflow/script/` — runtime modules: accounting, stations, pulse, world, layout, config, GUI, labels, guard, and meter.
- `factorio/cashflow/scenarios/cashflow/` — Factorio scenario files; its `control.lua` is intentionally empty because the mod root `control.lua` owns behavior.
- `factorio/tests/` — plain-Lua accounting tests, fake-Factorio smoke tests, and the custom test runner.
- `factorio/scripts/` — packaging helpers.
- `factorio/dist/` — generated release archives; do not treat generated archives as source.

## Development Commands

From the repository root:

```bash
npm run test:factorio      # accounting and fake-Factorio smoke tests
npm run package:factorio   # create factorio/dist/<name>_<version>.zip
```

The test command is equivalent to:

```bash
lua factorio/tests/run.lua
```

Packaging uses `bash`, `jq`, and `zip`; the archive name and version come from `factorio/cashflow/info.json`, and the archive contains a top-level versioned mod directory.

For the separate browser simulator:

```bash
npm test
python3 -m http.server 4173
```

There is no repository-wide build step, bundler, lint configuration, or formatter configuration.

## Code Conventions & Common Patterns

- Write Factorio code for **Lua 5.2** compatibility. Do not use Lua 5.3+ syntax such as `//` or `<const>`.
- Store money as integer cents in accounting code. Convert to plates or display strings only at explicit boundaries; one $10 plate is 1,000 cents.
- Keep accounting deterministic and Factorio-API-free. Put money rules in `script/accounting.lua`, orchestration in `pulse.lua`, and game entities/events in the integration modules.
- Use the persistent `storage.cf` state established by `control.lua`; preserve its month, debt, asset, node, buffer, and reporting state when changing runtime behavior.
- Respect the fixed monthly boundary and processing order. Month-close behavior must account for opening-balance interest/returns, unbelted copper, debt changes, surplus/unpaid outputs, state reset, and next-month planning.
- Use existing `cf-` prototype/entity names and the fixed layout in `script/layout.lua`; world construction belongs in `script/world.lua`.
- Belt movement is the accounting interface. Do not bypass belt routing with ad hoc inventory transfers except where the existing guard or station behavior explicitly requires it.
- Event registration and player/game lifecycle handling belong in `control.lua`. UI presentation belongs in `gui.lua` and `labels.lua`; player inventory enforcement belongs in `guard.lua`.
- Follow the existing defensive style at Factorio API boundaries. The meter code uses guarded API calls for version-sensitive detailed belt contents; preserve safe handling of missing or invalid entities.

## Important Files

- `factorio/cashflow/control.lua` — main runtime entry point, event handlers, tick loop, initialization, and persistent state.
- `factorio/cashflow/script/accounting.lua` — pure money engine and constants.
- `factorio/cashflow/script/stations.lua` — belt-level cashflow, matching, debt, and vault behavior.
- `factorio/cashflow/script/pulse.lua` — month planning and month-close coordinator.
- `factorio/cashflow/script/config.lua` — reads `settings.global` into runtime configuration.
- `factorio/cashflow/script/world.lua` and `layout.lua` — dedicated surface and station topology.
- `factorio/cashflow/script/gui.lua`, `labels.lua`, `meter.lua`, `guard.lua` — player-facing state and enforcement.
- `factorio/cashflow/settings.lua`, `data.lua`, `info.json` — mod settings, prototypes, metadata, Factorio version, and release version.
- `factorio/tests/accounting_test.lua` — pure accounting behavior.
- `factorio/tests/smoke_test.lua` and `fake_factorio.lua` — runtime behavior without an installed Factorio game.
- `factorio/TESTING.md` — installation and manual in-game QA checklist.

## Runtime/Tooling Preferences

- Target runtime: Factorio 2.0; `info.json` requires `base >= 2.0`.
- Factorio executes Lua 5.2-compatible code. Local tests use Lua 5.4, so passing local tests does not authorize newer syntax.
- Root `package.json` is private, uses ES modules for the separate browser app, and has no application dependencies or lockfile-driven package workflow.
- Use the repository's existing Bash/Lua/npm commands rather than introducing a build system. No JavaScript or Lua formatter/linter is configured.
- Factorio is not installed on the development machine used for local tests. Validate actual game behavior on Factorio 2.0.x using `factorio/TESTING.md`.

## Testing & QA

Run the complete local Factorio suite with:

```bash
npm run test:factorio
```

`factorio/tests/run.lua` loads both test modules, sorts exported `T.*` tests for deterministic order, runs each under `pcall`, reports pass/fail counts, and exits nonzero on failure.

- `accounting_test.lua` covers monthly rates, plate conversion/rounding, emissions, matching, fractional carry, month close, opening-balance interest/returns, financial independence, and money formatting.
- `smoke_test.lua` exercises initialization, scenario gating, tick timing, emissions, Cashflow pairing, borrowing/paydown, interest, unpaid bills, vault deposits, inventory guards, and win/quit-job flow through `fake_factorio.lua`.
- There is no configured coverage threshold or coverage command.
- Manual in-game QA remains required for belt wiring, station behavior, GUI, logs, and Factorio-version compatibility. Follow the 13-step checklist in `factorio/TESTING.md`; it was tested against Factorio 2.0.77.

After runtime changes, run both the local suite and the relevant manual checklist steps. After metadata or packaging changes, run `npm run package:factorio` and inspect the generated archive layout.
