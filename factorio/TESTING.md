# Cashflow Factory — in-game test checklist

Target: Factorio 2.0.x (tested against 2.0.77). Base game only; Space Age can be on or off.

## Install

1. On the dev machine: `npm run package:factorio` → `factorio/dist/cashflow_<version>.zip`.
2. Copy the zip (don't unzip) into the mods folder, and delete any older `cashflow_*.zip`:
   - Windows: `%APPDATA%\Factorio\mods\`
   - macOS: `~/Library/Application Support/factorio/mods/`
   - Linux: `~/.factorio/mods/`
3. Start Factorio → Mods → make sure **Cashflow Factory** is enabled → restart if asked.

If the game refuses to load, the error names the file and line. Send that text back.

## How money moves

- **Iron plate = $10 cash. Copper plate = $10 bill.**
- **PAYCHECK** emits iron. **NEEDS** and **WANTS** emit copper, spread evenly across the month.
- **CASHFLOW** takes iron and copper on either input. One iron + one copper disappear together (a bill paid). At month end, leftover iron comes out **SURPLUS OUT** and leftover copper comes out **UNPAID OUT**.
- **DEBT**: copper into **BORROW IN** or **PAY IN** adds $10 of debt each. Iron into **BORROW IN** or **PAY IN** pays $10 off while there's debt. With no debt, iron on PAY IN backs up and the splitter sends it out **PASS OUT**. Each month **INTEREST OUT** emits the interest as copper bills.
- **VAULT**: iron into **DEPOSIT IN** becomes assets. Each month **RETURNS OUT** emits the return as iron.
- Copper that can't get onto a belt by month end (Needs, Wants, Interest or Unpaid outputs backed up or unconnected) is added to debt. Iron that can't get onto a belt just waits as idle cash.

## A working first factory

```
PAYCHECK OUT ─┐
NEEDS OUT ────┼─► CASHFLOW CASH IN / BILLS IN
WANTS OUT ────┘
DEBT INTEREST OUT ──► CASHFLOW BILLS IN        (pay interest with cash)
CASHFLOW SURPLUS OUT ──► DEBT PAY IN ; DEBT PASS OUT ──► VAULT DEPOSIT IN
CASHFLOW UNPAID OUT ──► DEBT BORROW IN         (borrow to cover a bad month)
VAULT RETURNS OUT ──► VAULT DEPOSIT IN         (reinvest)  or  CASHFLOW CASH IN (withdraw)
```

## Checklist

| # | Do | Expect |
|---|---|---|
| 1 | Start the scenario (Play → Scenarios → Cashflow Factory) | Concrete financial district. Six colour-framed stations: PAYCHECK, NEEDS, WANTS (left column), CASHFLOW (middle), DEBT (top right), VAULT (bottom right). Hazard lanes mark the Needs, Wants, and Debt routes. The centre-bottom **FINANCIAL LEDGER** shows Month 1 READY, cashflow, debt, vault, paid, borrowed, and deposited totals. Gray port labels (`CASH IN >`, `SURPLUS OUT >`…). Left panel says Month 0 PAUSED. Inventory: 400 belts, 50 undergrounds, 50 splitters, 1 Cashflow meter. |
| 2 | Try to mine or rotate a station belt or splitter | Not possible. |
| 3 | Press **Start**, build nothing, wait one month | Iron comes out of PAYCHECK and copper out of NEEDS/WANTS; each stub fills and stops. Labels show "unbelted $… -> debt at month end". At month 1, debt goes from $18,000 to $20,640 (the $2,640 of bills that never got onto a belt). The DEBT label shows the interest waiting. |
| 4 | Belt PAYCHECK, NEEDS and WANTS into CASHFLOW | Copper and iron vanish in pairs at CASHFLOW. Its label shows cash building up (income > bills) and "paid" climbing. |
| 5 | Wait for month end | About $2,200 of iron streams out of SURPLUS OUT over ~15 seconds. |
| 6 | Belt SURPLUS OUT into DEBT PAY IN | Debt drops $10 per plate. Opening the ledger chest isn't allowed, but the DEBT label and panel match. |
| 7 | Leave DEBT INTEREST OUT unconnected for a month | Its stub fills; the rest of the interest is added to debt (compounding). Then belt it into CASHFLOW BILLS IN; interest is paid with cash instead. |
| 8 | Raise Wants to 5000 in mod settings | Next month CASHFLOW runs out of cash; copper comes out UNPAID OUT. Belt it into DEBT BORROW IN; debt rises by that amount. |
| 9 | Place the **Cashflow meter** on any belt | A METER label counts cash and bills passing this month. |
| 10 | Belt iron into VAULT DEPOSIT IN | VAULT label rises $10 per plate. Next month iron comes out of RETURNS OUT ($70/month at $12,000). |
| 11 | Pick up plates by hand (F) or mine a belt carrying plates | Iron goes back to PAYCHECK ("Cash only moves on belts"). Copper is added to debt ("Bills only move on belts"). |
| 12 | Settings → Mod settings → Map → Game speed = 10 | A month lasts about 6 seconds. |
| 13 | Quick win: new game with Starting debt 0, Starting assets 480000; belt Needs + Wants + Paycheck into Cashflow | After month 1: "Financial independence!" and a **Quit job** button. Pressing it stops the paycheck. |

## What to send back when something is off

- The step number and what you saw (a screenshot of any station that looks wrong helps).
- `factorio-current.log` (next to the mods folder). Each month writes one line, in plates unless noted:
  `[cashflow] month=… debt=(cents) assets=(cents) paycheck=… bills=… cash_in=… bills_in=… paid=… surplus=… unpaid=… borrowed=… debt_paid=… collected=… interest=(cents) return=(cents) deposits=…`

## Known uncertainties, verify first

- The PAY IN splitter sends iron to the drain side first, and sends everything out PASS OUT once debt is zero and the drain stub backs up.
- Station belts line up (splitter input, sinks, sources). If a stub looks disconnected, send a screenshot.
- Output stubs fill at full belt speed (step 5 should take ~15 s, not a minute).
- The meter counts (step 9). It uses `LuaTransportLine.get_detailed_contents`; if it stays at $0 while plates pass, that API behaves differently than expected.
