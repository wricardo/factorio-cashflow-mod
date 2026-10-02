# Cashflow Freeplay manual acceptance

## Install

```bash
npm run package:factorio
```

Copy `factorio/dist/cashflow-freeplay_0.2.23.zip` to Factorio's `mods` directory, enable it, and create or load an ordinary Freeplay save. Enabling the mod must leave the terrain, player location, inventory, and game speed unchanged.
## Unrestricted Freeplay

Cashflow Freeplay does not disable, reject, or change availability of any vanilla building, item, recipe, ghost, research, power system, vehicle, combat entity, or rail infrastructure. The finance stations coexist with an ordinary Factorio base.

## Building visual upgrade

Version `0.2.15` makes every Cashflow station a Warehousing-derived building. Existing compact stations must be mined and re-placed before reconnecting their perimeter belt ports:

- Income, Expense, and Debt are 3×3 Storehouses (the Controller was too until `0.2.23`).
- Cashflow and Asset Warehouse are 6×6 Warehouses.

Version `0.2.16` adds multiple linked Debt and Asset Warehouse stations per controller. Existing one-station accounts migrate automatically; new station APR and return settings default to the former controller-wide values.

Version `0.2.17` labels each Debt Station with its debt and monthly interest, and each Asset Warehouse with its held assets and monthly return.

Version `0.2.18` gives the Cashflow Station a second `CASH IN` and a second `BILLS IN` line (four input ports total, two output ports unchanged) so one belt of each kind is no longer a throughput ceiling. Existing Cashflow Stations gain the new ports automatically in place on load; nothing needs to be mined or moved. Wire a second belt into each new port the same way as the first; either, both, or neither cash/bills line may be used.

Version `0.2.19` makes a Debt Station's copper-plate count *be* its debt, the same way an Asset Warehouse's iron-plate count is its assets — no hidden ledger syncing the chest behind your back. `BORROW IN` inserts copper straight into the chest; `PAY IN` iron is capped at the chest's current copper count and removes that many copper plates (the paying iron is spent, not stored, so you can't pre-pay debt that doesn't exist yet, and feeding more iron than the balance just backs the extra up on the belt). Because the chest is now the real balance, manually adding or removing copper plates genuinely changes the debt, exactly like a vault's iron.

Version `0.2.20` shows elapsed game time as a 12-month calendar (`Year 1 Month 1`, rolling to `Year 2 Month 1` after month 12) instead of a raw running month count, in both the floating controller label and the controller's configuration panel.

Version `0.2.21` fixes the controller label's monthly cashflow figure: it now shows last month's actual net settlement through the Cashflow station (cash in minus bills in), not just planned income minus expense. An account living entirely off Asset Warehouse returns routed into `CASH IN` — no Income station at all — now shows that as positive cashflow instead of `$0`. Before the first month closes there is no settlement yet, so the label falls back to the planned income-minus-expense figure.

Version `0.2.22` allows any number of Cashflow stations per controller. Existing one-station accounts migrate automatically. Each station pulls from its own input belts into its own chest, but settlement is pooled per account: iron in any of the account's Cashflow stations pays copper in any other. Pending surplus and unpaid plates are pushed round-robin across every station's `SURPLUS OUT` and `UNPAID OUT`, so one backed-up output belt does not stall the rest.

Version `0.2.23` makes the Cashflow Controller a 3×3 Computing Center with no inventory, instead of a 2,000-slot Storehouse chest (art: Sosciencity, CC BY 4.0). Opening it shows only the account panel. Existing controllers are replaced in place on load: same position, same account (name, month, running state, configuration), and the same linked stations. Anything that had been stored in an old controller chest is spilled on the ground beside it. The same version caps each Income and Expense station at `$20,000`/month (2,000 plates, under a blue belt's `$27,000`/month); larger amounts are clamped when typed or confirmed, and on load for existing saves.

## One account

1. Craft and place one Cashflow Controller, Income Station, Expense Station, Cashflow Station, Debt Station, and Asset Warehouse. Leave clear space around each building: Storehouse ports are two tiles from centre; Warehouse ports are four tiles from centre. The Controller has no ports. Opening it must show only the Cashflow panel, with no empty market or chest window.
2. Open each station and select the controller. At least one Cashflow, Debt, and Asset Warehouse station is required before Start; Income and Expense are optional. Configure Income and Expense amounts, each Debt station's APR, and each Asset Warehouse's return while the controller is paused.
3. A controller may link any number of Cashflow, Debt, and Asset Warehouse stations. On first Start, opening debt and assets are split evenly across the linked stations; any indivisible cents or plates go to the earliest linked stations. The controller totals every linked debt and asset balance. With two Cashflow stations, feed cash into one and bills into the other: they must settle against each other, and month-end surplus must leave through both stations' `SURPLUS OUT`.
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
