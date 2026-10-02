# Tests

## Automated

```bash
npm test
```

Runs `accounting_test.lua`, `split_test.lua` and `freeplay_test.lua` on plain Lua against `tests/fake_factorio.lua`, a minimal stand-in for the Factorio runtime. It is the local smoke proof; it cannot render panels or simulate belts, so the checklist below is performed in-game. Version history is in `changelog.txt`.

## Manual acceptance

```bash
npm run package
```

Copy `dist/cashflow-freeplay_<version>.zip` to Factorio's `mods` directory, enable it, and create or load an ordinary Freeplay save. Enabling the mod must leave the terrain, player location, inventory, and game speed unchanged.

## Unrestricted Freeplay

Cashflow Freeplay does not disable, reject, or change availability of any vanilla building, item, recipe, ghost, research, power system, vehicle, combat entity, or rail infrastructure. The finance stations coexist with an ordinary Factorio base.

## Panels, labels, and editing

1. **Account dialog.** Opening an Account shows a centered, draggable dialog that Esc, E, or its `X` button closes, with no empty market window behind it. It shows a month progress bar, `Assets`, `Debt`, `Net worth`, monthly `Cashflow`, and a bar for how much of the monthly expenses the Investment Accounts' returns cover (informational; there is no winning condition). It refreshes in place twice a second, so a field you are typing in is never rebuilt.
2. **Start checklist.** Until a Cashflow Station, Debt Station, and Investment Account are linked, the dialog lists each as `linked`/`missing` and `Start` is disabled. After the first Start, starting debt and assets show as plain locked text.
3. **Station panels** dock beside the vanilla window and close when that window closes (Esc/E). Number fields accept only digits and a decimal point, with a `$`/`%` suffix; income, expense, and salary show their `$20,000` cap under the field. Validation errors appear in red inside the panel, not chat. Expense `Needs`/`Wants` is a switch. The Account picker lists each account as `Name (x, y)` so equal names can be told apart, and `Locate` prints a clickable map link. `Show/Hide how to connect` explains each station's ports and is remembered per player.
4. **Yearly reports** are a table (Year, Income, Expenses, Assets, Debt, Net worth), newest five.
5. **World labels.** Port labels carry the plate icon (iron for cash, copper for bills) and show only in alt mode. Passive Income and Expense labels show `N plates left to send` while the account runs and the belt is still taking plates, then `All plates sent`. Closing a month floats `Year Y Month M closed` with cash in, bills, and paid above each Cashflow Station for 4 seconds. Labels and panels use the same names (`Cashflow Station`, `Debt Station`, `Expense Station`).
6. **Editing while running.** Monthly amounts, Active Income salary, Debt APR, Investment return, Expense `Needs`/`Wants`, and the Account name can change while the Account runs. Amounts and rates apply from the next month: the open month closes at the plan and rates it started with, and the panel says so. Linking and unlinking a station, and the starting debt and assets, need a pause. Edits made while paused apply to the current month.
7. **Month release.** Passive Income and Expense stations put their whole planned monthly total on the belt as soon as the month starts. A yellow belt moves about 15 plates a second, so 1,000 plates take about a minute to leave. Plates still waiting at month end are handled as before (unsent bills are added to debt).
8. **Station limit.** Each Passive Income, Active Income, and Expense station is limited to `$20,000` a month at any `Month length (seconds)`. A blue belt moves about 45 plates a second, so in a month shorter than about 45 seconds a full `$20,000` station cannot move all its plates in time: leftover income plates carry into the next month.
9. **Debt chest is the debt.** A Debt Station's copper-plate count is its debt. `BORROW IN` inserts copper into the chest; `PAY IN` iron is capped at the chest's copper count and removes that many copper plates (extra iron backs up on the belt). Adding or removing copper by hand changes the debt, as iron does for an Investment Account.
10. **Existing saves.** Loading a save from an older version must keep Accounts, linked stations, and configuration. Stations from before `0.2.15` must be mined and re-placed; existing Debt Stations keep their `PAY IN`/`BORROW IN` ports where they were (`0.2.41`).

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
