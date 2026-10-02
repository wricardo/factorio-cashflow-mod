# Cashflow Freeplay manual acceptance

## Install

```bash
npm run package
```

Copy `factorio/dist/cashflow-freeplay_0.2.45.zip` to Factorio's `mods` directory, enable it, and create or load an ordinary Freeplay save. Enabling the mod must leave the terrain, player location, inventory, and game speed unchanged.
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

Version `0.2.38` renames stations for players: the Cashflow Controller is **Account**, the Income Station is **Passive Income**, the Smelter is **Active Income**, and the Asset Vault/Asset Warehouse is **Investment Account**. Only display text changed; internal entity IDs are unchanged, so existing saves and placed stations keep working. Debt `INTEREST OUT` is now orange (copper). The hover pane also shows each Debt Station's configured `APR` and each Investment Account's configured `Return rate`, so neither requires opening the station.

Version `0.2.39` removes the unused win condition (the game is free play), adds a **yearly report** and an **alert for stuck unpaid bills**, and makes the **month length configurable**. A yearly report closes every 12th month with total income (cash plates settled at the Account's Cashflow Stations), total expenses (bill plates settled), and year-end assets, debt and net worth. It is announced in chat and kept in the Account panel (latest five). When unpaid bills cannot leave any `UNPAID OUT` belt for 5 seconds, every player on the Account's force gets an alert on its Cashflow Stations, and each station's hover pane shows `UNPAID OUT blocked` with a red light; such bills are added to debt at month end. The runtime-global setting `Month length (seconds)` (10–3600, default 60) sets the month; income/expense station limits scale with it ($20,000 per 60 seconds), and shortening the month caps existing stations.

Version `0.2.40` adds the **Percent Splitter**: a vanilla splitter (blue tint, vanilla art and recipe, in the Cashflow crafting row) with an adjustable share. Open it and set the percent of items that leave the **left** output (left relative to the direction items travel); the right output gets the rest. It works for any item at full belt speed and links to no Account. If one output is blocked, items use the other. The mod does this by driving the splitter's output priority on a 100-tick window (`script/split.lua`); measured on Factorio 2.0.77 the split stays within about 2 percentage points of the setting on a saturated belt and within about 1 point on sparse feeds. The splitter's own priority setting is managed by the mod and will be overwritten. Settings are not carried by blueprints yet: a placed or pasted Percent Splitter starts at 50%.

Version `0.2.41` puts a Debt Station's `PAY IN` on top and `BORROW IN` below it. Only newly placed Debt Stations get the new order: existing ones keep their ports where they are, because moving them would silently swap what the belts players already connected do. Mine and re-place a Debt Station to get the new layout.

Version `0.2.42` makes Passive Income and Expense stations release their whole planned monthly total as soon as the month starts, instead of pacing it across the month. The belt then carries the plates away as fast as it can, so a large amount still takes belt time to leave (one yellow belt moves about 15 plates per second, so 1,000 plates take about a minute); any plates still waiting at month end are handled as before (unsent bills are added to debt). Active Income is unchanged: its salary is paid after its 2-second smelt.

Version `0.2.43` reworks the panels and labels:

- **Account dialog.** Opening an Account shows a centered, draggable dialog (not a left-side panel) that Esc, E, or its `X` button closes. It is a live dashboard: month progress bar, `Assets`, `Debt`, `Net worth`, monthly `Cashflow`, and a bar showing how much of the monthly expenses the Investment Accounts' returns cover (informational; there is still no winning condition). It refreshes in place twice a second, so a field you are typing in is never rebuilt.
- **Start checklist.** Until a Cashflow Station, Debt Station, and Investment Account are linked, the dialog lists each as `linked`/`missing` and `Start` is disabled. After the first Start, starting debt and assets show as plain locked text.
- **Station panels** stay docked beside the vanilla window and now close when that window closes (Esc/E). Number fields accept only digits (and a decimal point) with a `$`/`%` suffix; income and expense show their cap under the field. Validation errors appear in red inside the panel instead of chat. Expense `Needs`/`Wants` is a switch. The Account picker lists each account with its position (`Name (x, y)`) so equal names can be told apart, and `Locate` prints a clickable map link in chat. A `Show/Hide how to connect` section explains each station's ports; the choice is remembered per player.
- **Yearly reports** are a table (Year, Income, Expenses, Assets, Debt, Net worth), newest five.
- **World.** Port labels carry the plate icon (iron for cash, copper for bills) and show only in alt mode. Passive Income and Expense labels show `N plates left to send` while the account runs and the belt is still taking plates, then `All plates sent`. Closing a month floats `Year Y Month M closed` with cash in, bills, and paid above each Cashflow Station for 4 seconds. World labels use the same names as panels (`Cashflow Station`, `Debt Station`, `Expense Station`).
- Panel text lives in `locale/en` (section `[cf-gui]`); world labels and chat messages are still built in code.

Version `0.2.44` lets you edit station values without pausing the Account. Monthly amounts, Active Income salary, Debt APR, Investment return, Expense `Needs`/`Wants`, and the Account name can change while it runs; amounts and rates apply from the next month (the month already in progress closes at the plan and rates it started with, and the panel says so). Linking and unlinking a station, and the starting debt and assets, still require a pause. Edits made while paused apply to the current month as before.

Version `0.2.45` fixes the per-station limit at `$20,000` a month for Passive Income, Active Income, and Expense stations, whatever the `Month length (seconds)` setting. Before, it shrank with shorter months. Plates still leave a station at belt speed (a blue belt moves about 45 plates a second), so in a month shorter than about 45 seconds a full `$20,000` station cannot move all its plates in time: leftover income plates carry into the next month, and unsent bills are added to debt at month end.

## Earned income

1. Place a Coal Supply and an Active Income station apart from each other. Opening the Coal Supply must show only its chest window, with no Cashflow panel. Its label reads `Coal Supply`.
2. Link the Active Income station to a paused Account, set its salary to `$500`, and route its `CASH OUT` to a Cashflow `CASH IN`. It accepts at most 50 coal. While the account is paused, loaded coal is not consumed.
3. Start the account. With 49 coal the label reads `Coal 49/50` and nothing happens. Adding the 50th coal empties the station and the heater glows; 2 seconds later 50 iron plates start leaving `CASH OUT`, and the label reads `Paid this month`.
4. Load another 50 coal in the same month: it stays in the station until the month closes, then smelts again.
5. Take coal out of the Coal Supply; it returns to 1,000 within half a second even with no Account running.

## One account

1. Craft and place one Account, Passive Income, Expense Station, Cashflow Station, Debt Station, and Investment Account. Leave clear space around each building: Storehouse ports are two tiles from centre; Warehouse ports are four tiles from centre. The Account has no ports. Opening it must show only the Account panel, with no empty market or chest window.
2. Open each station and select the Account. At least one Cashflow Station, Debt Station, and Investment Account is required before Start (the Account dialog's checklist shows whichever is missing and keeps `Start` disabled); Passive Income, Active Income, and Expense are optional. Configure income and expense amounts, each Debt Station's APR, and each Investment Account's return while the Account is paused.
3. An Account may link any number of Cashflow Stations, Debt Stations, and Investment Accounts. On first Start, opening debt and assets are split evenly across the linked stations; any indivisible cents or plates go to the earliest linked stations. The Account totals every linked debt and asset balance. With two Cashflow Stations, feed cash into one and bills into the other: they must settle against each other, and month-end surplus must leave through both stations' `SURPLUS OUT`.
4. Cash labels (`CASH IN`, `CASH OUT`, `PAY IN`, `DEPOSIT IN`, `RETURN OUT`, `SURPLUS OUT`) are white; copper `BILLS IN`, `BORROW IN`, `UNPAID OUT`, and `INTEREST OUT` are orange. Route `CASH OUT` to `CASH IN`, `COPPER OUT` to `BILLS IN`, `SURPLUS OUT` to `DEPOSIT IN`, `UNPAID OUT` to `BORROW IN`, `INTEREST OUT` to `BILLS IN`, and `RETURN OUT` to `CASH IN`.
5. Start the Account. Passive Income and Expense chests fill with the month’s planned plates; each linked Cashflow Station shows the signed monthly cashflow; each Debt chest displays its own copper balance and emits interest at its own APR; each Investment Account displays its iron assets and emits returns at its own rate. World labels remain compact on one line. Hovering any station must show its live metrics in the hover pane's status row, replacing `Normal`: Debt Stations include `APR`, Investment Accounts include `Return rate`. The Account label aggregates every linked asset and debt balance, but does not show monthly cashflow. Every custom panel must close with its `X` button, and Esc/E must close the Account dialog and any station panel together with its vanilla window.

Iron and copper have no account identity. A plate emitted by any Account's stations can enter another account's station; the receiving account processes it.

## Percent Splitter

1. Craft and place a Percent Splitter. Its label reads `Split 50% left • 50% right`; hovering shows `Left 50%` and `Right 50%`. Feed one belt of iron plates into one input and run belts away from both outputs: about half must go to each side.
2. Open it. A `Percent Splitter` panel appears beside Factorio's own splitter window. Enter `30`: the label and the panel summary change to `Left 30% • Right 70%`, and over a minute about 30% of items leave the left output (left is the output on your left as items travel).
3. Enter `0` and `100`: everything leaves the right, then everything leaves the left. Enter `250`: it clamps to 100. Enter text: nothing changes and the panel shows `Enter a percent from 0 to 100.` in red.
4. Block one output belt: all items leave through the other output. Unblock it: the configured split resumes.
5. Mine the splitter: its label disappears. A normal vanilla splitter next to it is unaffected.

## Yearly report, alerts, and month length

1. Run an Account for 12 months (or lower `Month length` in Settings → Map). At the end of month 12 chat shows `<Account> • Year 1 report` with `Income`, `Expenses`, `Assets`, `Debt`, and `Net worth`. Open the Account: a `Yearly reports` list shows the same figures. Income and expenses must equal the cash and bill plates that reached the Cashflow Stations during the year.
2. Disconnect or block a Cashflow Station's `UNPAID OUT` belt (or leave it unconnected) while bills go unpaid. Within a few seconds an alert with a copper-plate icon appears for that station, and hovering it shows `UNPAID OUT blocked` with a red status light. Reconnect the belt: the alert stops appearing and the light returns to green. A belt that is merely slow, but still moving, must not alert.
3. Change `Month length (seconds)` mid-game. The next month closes at the new length. Station amounts and their `$20,000` limit do not change.

## Two accounts and lifecycle

1. Place a second complete station set away from the first. Configure A as `$5,000` income, `$2,000` Needs, with Debt and Investment Account rates of `18%` and `7%`; configure B as `$1,000` income, `$100` Wants, with `0%` debt APR. Wire their belts separately and run a month. Each Account must retain its own balances, reports, station rates, debt, assets, and carries.
2. Feed copper only to A's Debt input and iron only to A's Investment Account input. At the next month boundary only A's debt, interest, assets, returns, and carries change.
3. Connect A's iron output to B's Cashflow cash input. B must settle the received iron as B cash; neither Account's ledger is merged.
4. While A runs, change a Debt APR, Investment Account return, and station amount: the open month must close with the old values and the next month use the new ones, and B must be unaffected. Then try to unlink one of A's stations from its station panel: the picker is disabled while A runs and works once A is paused.
5. Delete one linked station, pause the account, and verify Start reports the missing station. Delete A's Account: its stations remain in the world but become unlinked and inert; B continues unchanged.
6. Save/reload, then have two players open and configure different Accounts. Each GUI action must affect only its selected same-force, same-surface account.
