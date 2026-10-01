# Cashflow Freeplay manual acceptance

## Install

```bash
npm run package:factorio
```

Copy `factorio/dist/cashflow-freeplay_0.2.16.zip` to Factorio's `mods` directory, enable it, and create or load an ordinary Freeplay save. Enabling the mod must leave the terrain, player location, inventory, and game speed unchanged.
## Unrestricted Freeplay

Cashflow Freeplay does not disable, reject, or change availability of any vanilla building, item, recipe, ghost, research, power system, vehicle, combat entity, or rail infrastructure. The finance stations coexist with an ordinary Factorio base.

## Building visual upgrade

Version `0.2.15` makes every Cashflow station a Warehousing-derived building. Existing compact stations must be mined and re-placed before reconnecting their perimeter belt ports:

- Controller, Income, Expense, and Debt are 3×3 Storehouses.
- Cashflow and Asset Warehouse are 6×6 Warehouses.

Version `0.2.16` adds multiple linked Debt and Asset Warehouse stations per controller. Existing one-station accounts migrate automatically; new station APR and return settings default to the former controller-wide values.


## One account

1. Craft and place one Cashflow Controller, Income Station, Expense Station, Cashflow Station, Debt Station, and Asset Warehouse. Leave clear space around each building: Storehouse ports are two tiles from centre; Warehouse ports are four tiles from centre.
2. Open each station and select the controller. Cashflow plus at least one Debt and Asset Warehouse are required before Start; Income and Expense are optional. Configure Income and Expense amounts, each Debt station's APR, and each Asset Warehouse's return while the controller is paused.
3. A controller may link any number of Debt stations and Asset Warehouses. On first Start, opening debt and assets are split evenly across the linked stations; any indivisible cents or plates go to the earliest linked stations. The controller totals every linked debt and asset balance.
4. Every helper belt has a colored port label. Green labels are outputs; orange labels are inputs. Route `IRON OUT` to `CASH IN`, `COPPER OUT` to `BILLS IN`, `SURPLUS OUT` to `DEPOSIT IN`, `UNPAID OUT` to `BORROW IN`, `INTEREST OUT` to `BILLS IN`, and `RETURN OUT` to `CASH IN`.
5. Start the controller. Income and Expense chests fill with the month’s planned plates; each Debt chest displays its own copper balance and emits interest at its own APR; each Asset Warehouse displays its iron assets and emits returns at its own rate. The controller label aggregates every linked asset and debt balance.

Iron and copper have no account identity. A plate emitted by any controller can enter another account's station; the receiving account processes it.

## Two accounts and lifecycle

1. Place a second complete station set away from the first. Configure A as `$5,000` income, `$2,000` Needs, with Debt and Asset Warehouse rates of `18%` and `7%`; configure B as `$1,000` income, `$100` Wants, with `0%` debt APR. Wire their belts separately and run a month. Each controller must retain its own balances, reports, station rates, debt, assets, and carries.
2. Feed copper only to A's Debt input and iron only to A's Asset Warehouse input. At the next month boundary only A's debt, interest, assets, returns, and carries change.
3. Connect A's iron output to B's Cashflow cash input. B must settle the received iron as B cash; neither controller ledger is merged.
4. Pause A, change a Debt APR, Asset Warehouse return, or station amount, and restart it. B must continue unchanged. Attempting a configuration change while running must be rejected.
5. Delete one linked station, pause the account, and verify Start reports the missing role. Delete A's controller: its stations remain in the world but become unlinked and inert; B continues unchanged.
6. Save/reload, then have two players open and configure different controllers. Each GUI action must affect only its selected same-force, same-surface account.
