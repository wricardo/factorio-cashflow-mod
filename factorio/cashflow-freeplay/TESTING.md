# Cashflow Freeplay manual acceptance

## Install

```bash
npm run package:factorio
```

Copy `factorio/dist/cashflow-freeplay_0.2.14.zip` to Factorio's `mods` directory, enable it, and create or load an ordinary Freeplay save. Enabling the mod must leave the terrain, player location, inventory, and game speed unchanged.
## Construction policy

Enabled vanilla entities:

- Cashflow Controller, Income, Expense, Cashflow, Debt, and Asset Vault.
- Transport belts, underground belts, splitters, and inserters.
- Wooden, iron, steel, and logistic chests.
- Small, medium, and big electric poles, substations, and the Electric Energy Interface.
- Roboports, construction robots, and logistic robots, so approved ghosts can be built automatically.

Disabled vanilla categories:

- Assemblers, furnaces, miners, labs, beacons, radars, and other production/research machines.
- Steam, solar, nuclear, and other power-generation entities.
- Combat, vehicles, equipment, rails, trains, and other unrelated infrastructure.

Ghosts follow the same policy: approved logistics/robot infrastructure ghosts survive and can be revived; disabled-category ghosts are removed. Recipes for disabled placeable entities are disabled, while researched technology still controls approved recipes.

Upgrading from `0.2.8` restores recipe defaults, reapplies researched technology effects, and then reapplies this policy once.


## One account

1. Craft and place one Cashflow Controller, Income Station, Expense Station, Cashflow Station, Debt Station, and Asset Warehouse. The Asset Warehouse is a 3×3 Warehouse building with `DEPOSIT IN` and `RETURN OUT` ports two tiles from its centre.
2. Open each station and select the controller. Cashflow, Debt, and Asset Warehouse are required before Start; Income and Expense are optional. Configure them while the controller is paused; fields are locked while it runs. Set Income to `$5,000`, Expense to `$2,000` with `Needs`, and set the controller's debt APR and asset return.
3. Every helper belt has a colored port label. Green labels are outputs; orange labels are inputs. Route `IRON OUT` to `CASH IN`, `COPPER OUT` to `BILLS IN`, `SURPLUS OUT` to `DEPOSIT IN`, `UNPAID OUT` to `BORROW IN`, `INTEREST OUT` to `BILLS IN`, and `RETURN OUT` to `CASH IN`.
4. Start the controller. The Income and Expense chests fill with the month’s planned plates; the Debt chest displays copper debt; the Asset Warehouse displays iron assets; and the Cashflow chest retains any unmatched iron or copper. Verify that the controller label updates monthly and iron/copper emit proportionally through the month.

Iron and copper have no account identity. A plate emitted by any controller can enter another account's station; the receiving account processes it.

## Two accounts and lifecycle

1. Place a second complete station set away from the first. Configure A as `$5,000` income, `$2,000` Needs, `18%` APR and B as `$1,000` income, `$100` Wants, `0%` APR. Wire their belts separately and run a month. Each controller must retain its own balances, reports, rates, debt, asset return, and carry values.
2. Feed copper only to A's Debt input and iron only to A's Vault input. At the next month boundary only A's debt, interest, assets, returns, and carries change.
3. Connect A's iron output to B's Cashflow cash input. B must settle the received iron as B cash; neither controller ledger is merged.
4. Pause A, change its rate or station amount, and restart it. B must continue unchanged. Attempting a configuration change while running must be rejected.
5. Delete one linked station, pause the account, and verify Start reports the missing role. Delete A's controller: its stations remain in the world but become unlinked and inert; B continues unchanged.
6. Save/reload, then have two players open and configure different controllers. Each GUI action must affect only its selected same-force, same-surface account.
