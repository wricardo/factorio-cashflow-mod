# Cashflow Freeplay manual acceptance

## Install

```bash
npm run package:factorio
```

Copy `factorio/dist/cashflow-freeplay_0.2.37.zip` to Factorio's `mods` directory, enable it, and create or load an ordinary Freeplay save. Enabling the mod must leave the terrain, player location, inventory, and game speed unchanged.
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

Version `0.2.24` adds earned income. A **Coal Supply** (3×3, electric-mining-drill art) holds 1,000 coal and refills itself every half second; it links to no account and opens as a plain chest. A **Smelter** (3×3, electric-furnace art) links to a controller like an Income Station and has a monthly salary setting (capped at `$20,000`). It holds exactly one batch: 50 coal. While its account is running, a full batch is consumed, the furnace glows for 2 seconds, then the salary leaves `IRON OUT` as iron plates. Each Smelter pays at most once per month; coal loaded after that waits for the next month. Inserters are allowed.

Version `0.2.25` gives every station its own icon and its own crafting row. In the Logistics tab, a row directly below vanilla Storage holds, in order: Controller (Computing Center), Income (green Storehouse + iron plate), Expense (blue Storehouse + copper plate), Cashflow (Warehouse + `=`), Debt (red Storehouse + `−`), Asset Warehouse (Warehouse + `+`), Smelter (electric furnace + iron plate), and Coal Supply (electric mining drill + coal). No two icons match each other or a vanilla item.

Version `0.2.26` replaces the seven non-controller icons with original, generated industrial artwork: green income drawer, blue expense tray, cyan Cashflow settlement unit, red Debt ledger, gold Asset Warehouse, orange Smelter, and coal hopper. They contain no derived Warehousing or vanilla Factorio pixels. Each remains in the Cashflow crafting row added in `0.2.25`.

Version `0.2.27` calls iron-plate routing **cash**: Income and Smelter `IRON OUT` are now white `CASH OUT`, and both Cashflow `CASH IN` labels are white. `BILLS IN` (copper) remains orange; the other named outputs retain their existing green labels. Each linked Cashflow Station now displays the same signed monthly cashflow as its controller label. Every custom controller/station configuration panel has a `Close` button.

Version `0.2.28` adds **Net worth** to the controller account label: total Asset Warehouse iron value minus total Debt Station copper value. It is signed, so an account with `$12,000` assets and `$18,000` debt displays `Net worth -$6,000`.

Version `0.2.29` applies the white cash-label rule to Debt `PAY IN`, Asset Warehouse `DEPOSIT IN`, and Asset Warehouse `RETURN OUT`. `PAY IN` and `DEPOSIT IN` consume iron/cash; `RETURN OUT` emits iron/cash. Debt `BORROW IN` remains orange because it consumes copper/debt.

Version `0.2.30` removes monthly cashflow from the Cashflow Controller label. It remains displayed on every linked Cashflow Station, avoiding duplicate account-level and station-level cashflow labels.

Version `0.2.31` colors Cashflow `SURPLUS OUT` white because it emits iron/cash, and `UNPAID OUT` orange because it emits copper/debt.

Version `0.2.32` separates every station title from its statistics with a blank line. Individual metrics remain one per line.

Version `0.2.33` renders every station title and statistic as separate floating text objects because Factorio renders embedded newlines as spaces. Each detail now occupies its own visible line.

Version `0.2.34` moves the separate title/statistic stack above each building rather than down across its artwork. The last statistic retains the prior label position; preceding lines stack upward.

Version `0.2.35` restored compact one-line station labels.

Version `0.2.37` shows each station's live metrics in the status row of Factorio's hover pane (the panel with the entity preview and `Storage`/`Health`), because Factorio offers mods no anchor for that pane: Account, then monthly amount (Income, Expense plus category), cashflow, debt and interest, assets and return, Smelter salary and coal status, or Coal Supply stock. The status light is green when linked and yellow when unlinked. The anchored-frame approach of `0.2.35`/`0.2.36` is removed.

## Earned income

1. Place a Coal Supply and a Smelter apart from each other. Opening the Coal Supply must show only its chest window, with no Cashflow panel. Its label reads `Coal Supply`.
2. Link the Smelter to a paused controller, set its salary to `$500`, and route its `CASH OUT` to a Cashflow `CASH IN`. The Smelter accepts at most 50 coal. While the account is paused, loaded coal is not consumed.
3. Start the account. With 49 coal the label reads `Coal 49/50` and nothing happens. Adding the 50th coal empties the Smelter and the heater glows; 2 seconds later 50 iron plates start leaving `CASH OUT`, and the label reads `Paid this month`.
4. Load another 50 coal in the same month: it stays in the Smelter until the month closes, then smelts again.
5. Take coal out of the Coal Supply; it returns to 1,000 within half a second even with no controller running.

## One account

1. Craft and place one Cashflow Controller, Income Station, Expense Station, Cashflow Station, Debt Station, and Asset Warehouse. Leave clear space around each building: Storehouse ports are two tiles from centre; Warehouse ports are four tiles from centre. The Controller has no ports. Opening it must show only the Cashflow panel, with no empty market or chest window.
2. Open each station and select the controller. At least one Cashflow, Debt, and Asset Warehouse station is required before Start; Income and Expense are optional. Configure Income and Expense amounts, each Debt station's APR, and each Asset Warehouse's return while the controller is paused.
3. A controller may link any number of Cashflow, Debt, and Asset Warehouse stations. On first Start, opening debt and assets are split evenly across the linked stations; any indivisible cents or plates go to the earliest linked stations. The controller totals every linked debt and asset balance. With two Cashflow stations, feed cash into one and bills into the other: they must settle against each other, and month-end surplus must leave through both stations' `SURPLUS OUT`.
4. Cash labels (`CASH IN`, `CASH OUT`, `PAY IN`, `DEPOSIT IN`, `RETURN OUT`, `SURPLUS OUT`) are white; copper `BILLS IN`, `BORROW IN`, and `UNPAID OUT` are orange; other outputs are green. Route `CASH OUT` to `CASH IN`, `COPPER OUT` to `BILLS IN`, `SURPLUS OUT` to `DEPOSIT IN`, `UNPAID OUT` to `BORROW IN`, `INTEREST OUT` to `BILLS IN`, and `RETURN OUT` to `CASH IN`.
5. Start the controller. Income and Expense chests fill with the month’s planned plates; each linked Cashflow Station shows the signed monthly cashflow; each Debt chest displays its own copper balance and emits interest at its own APR; each Asset Warehouse displays its iron assets and emits returns at its own rate. World labels remain compact on one line. Hovering Income, Expense, Cashflow, Debt, Asset Warehouse, Smelter, or Coal Supply must show its role-specific live metrics in the hover pane's status row, replacing `Normal`. The controller label aggregates every linked asset and debt balance, but does not show monthly cashflow. Every custom panel must close when its `Close` button is pressed.

Iron and copper have no account identity. A plate emitted by any controller can enter another account's station; the receiving account processes it.

## Two accounts and lifecycle

1. Place a second complete station set away from the first. Configure A as `$5,000` income, `$2,000` Needs, with Debt and Asset Warehouse rates of `18%` and `7%`; configure B as `$1,000` income, `$100` Wants, with `0%` debt APR. Wire their belts separately and run a month. Each controller must retain its own balances, reports, station rates, debt, assets, and carries.
2. Feed copper only to A's Debt input and iron only to A's Asset Warehouse input. At the next month boundary only A's debt, interest, assets, returns, and carries change.
3. Connect A's iron output to B's Cashflow cash input. B must settle the received iron as B cash; neither controller ledger is merged.
4. Pause A, change a Debt APR, Asset Warehouse return, or station amount, and restart it. B must continue unchanged. Attempting a configuration change while running must be rejected.
5. Delete one linked station, pause the account, and verify Start reports the missing role. Delete A's controller: its stations remain in the world but become unlinked and inert; B continues unchanged.
6. Save/reload, then have two players open and configure different controllers. Each GUI action must affect only its selected same-force, same-surface account.
