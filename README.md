# Cashflow

A Factorio 2.0 mod that adds a personal-finance game to ordinary Freeplay. Iron plates are cash, copper plates are bills and debt, and you run your money with belts.

Place an **Account**, link income, expense, debt and investment stations to it, and watch cashflow, debt and net worth change month by month. Each Account is independent, you can run several, and nothing in vanilla Freeplay is restricted.
## Quick install — macOS

Paste this into Terminal to install the newest published mod release:

```bash
curl -fsSL https://raw.githubusercontent.com/wricardo/factorio-cashflow-mod/main/scripts/install-latest.sh | bash
```

It replaces older Cashflow zips, enables the mod, and prints the installed version. Start or restart Factorio afterward.


## How it works

- One **iron plate is $10 cash**. One **copper plate is a $10 bill or $10 of debt**.
- Income stations put cash on a belt, expense stations put bills on a belt, and a **Cashflow Station** cancels one iron against one copper. What is left over is surplus (iron) or unpaid bills (copper).
- Unpaid bills are borrowed into a **Debt Station**, which charges interest every month. Surplus cash can be deposited into an **Investment Account**, which pays returns every month.
- A month lasts 60 seconds by default and a year is 12 months. Every 12th month you get a yearly report.

## Stations

| Station | Size | Ports |
|---|---|---|
| Account | 3×3 | none; opens the dashboard |
| Passive Income | 3×3 | `CASH OUT` |
| Active Income | 3×3 | `CASH OUT`; load 50 coal a month and it pays a salary after a 2-second smelt |
| Expense Station | 3×3 | `COPPER OUT` |
| Cashflow Station | 6×6 | `CASH IN` ×2, `BILLS IN` ×2, `SURPLUS OUT`, `UNPAID OUT` |
| Debt Station | 3×3 | `PAY IN`, `BORROW IN`, `INTEREST OUT` |
| Investment Account | 6×6 | `DEPOSIT IN`, `RETURN OUT` |
| Coal Supply | 3×3 | none; endless coal for Active Income |
| Percent Splitter | splitter | a splitter with an adjustable left/right share |

Every station is placed and crafted like any other building, in its own row of the Logistics tab.

### Wiring
```
Passive Income  CASH OUT        → Cashflow CASH IN
Active Income   CASH OUT        → Cashflow CASH IN
Expense         COPPER OUT      → Cashflow BILLS IN
Cashflow        SURPLUS OUT     → Investment Account DEPOSIT IN
Cashflow        UNPAID OUT      → Debt BORROW IN
Debt            INTEREST OUT    → Cashflow BILLS IN
Investment      RETURN OUT      → Cashflow CASH IN
```

Feed iron into a Debt Station's `PAY IN` to pay debt down. Opening a station shows a "how to connect" reminder for its ports, and alt mode shows the port labels in the world.

### Setting up an Account

1. Place an Account and open it: it shows the dashboard and a checklist of what is still missing.
2. Open each station and pick the Account from the drop-down.
3. Set monthly amounts, Debt APR, and Investment return. Stations are limited to $20,000 a month.
4. An Account needs at least one Cashflow Station, Debt Station and Investment Account before **Start**.
5. Amounts, rates, salary and category can be edited while it runs and apply from next month. Linking and unlinking needs a pause.

Defaults: $18,000 starting debt at 18% APR, $12,000 starting assets at 7% return. Interest and returns are the annual rate divided by 12, applied to the balance at the start of the month.

## Settings

| Setting | Scope | Default | Description |
|---|---|---|---|
| Month length (seconds) | runtime, global | 60 | How long one game month lasts. |

## Installing

For details, the command above downloads the public installer from this repository's `main` branch. It requires the built-in `curl` and `unzip` commands, queries GitHub for the newest published release, validates that the downloaded zip is a Cashflow archive, then installs it in `~/Library/Application Support/factorio/mods`. Set `FACTORIO_MODS_DIR` first to use a different Factorio mods directory. Requires Factorio 2.0 and the base game; Space Age is not needed.

To inspect the script before running it, open [`scripts/install-latest.sh`](scripts/install-latest.sh). To build from source instead, run `npm run package` and copy `dist/cashflow-freeplay_<version>.zip` to Factorio's `mods` folder.

## Development

```bash
npm test                  # plain-Lua tests against a fake Factorio runtime
npm run package           # builds dist/cashflow-freeplay_<version>.zip
npm run install:local     # builds, removes older local zips, installs, and enables the mod
```

Both need `lua` (5.4 is fine; the mod itself sticks to Lua 5.2 syntax) and `jq` and `zip` for packaging. The in-game acceptance checklist is in [`tests/README.md`](tests/README.md); [`AGENTS.md`](AGENTS.md) describes the architecture.

### Publishing a release

1. Bump `info.json` and add the matching `changelog.txt` entry.
2. Commit the release, then create and push a tag matching the version: `git tag v<version> && git push origin v<version>`.
3. The [release workflow](.github/workflows/release.yml) runs the Lua tests, verifies that the tag matches `info.json`, packages the mod, and attaches the zip to a GitHub release. The installer always downloads that newest published release.


```
info.json  changelog.txt  control.lua  data.lua  settings.lua
locale/      English strings, including every panel caption
migrations/  prototype renames for old saves
script/      accounting (pure money math), stations, account, pulse, labels, gui, rules, split, station_layout
graphics/    icons and building art
tests/       fake Factorio runtime and test suites, plus the manual checklist
scripts/     package.sh, install-latest.sh, and build-install-local.sh
```

## Credits

Station art is adapted from [Warehousing](https://github.com/Warehousing/Warehousing) by David-John Miller (MIT, used with permission) and the Account's Computing Center art from Sosciencity (CC BY 4.0). The full notices are in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).
