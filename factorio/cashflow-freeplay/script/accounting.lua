-- Pure money math. No Factorio API here so it can be unit-tested with plain Lua.
-- Money is integer cents. One plate is $10: iron plates are cash, copper plates are bills/debt.

local M = {}

M.CENTS_PER_PLATE = 1000
M.TICKS_PER_MONTH = 3600
-- Largest monthly amount one Income, Active Income or Expense station may be configured with,
-- whatever the month length: 2,000 plates ($20,000).
M.MAX_STATION_CENTS = 2000000
-- Unpaid bills that cannot leave any UNPAID OUT belt for this many ticks (5 seconds) raise an alert.
M.UNPAID_ALERT_TICKS = 300
-- Smelter stations: each month's salary needs one hand-delivered batch of this much coal, and
-- smelting it takes SMELT_TICKS (2 seconds) before the salary plates start leaving CASH OUT.
M.SMELTER_COAL_PER_MONTH = 50
M.SMELT_TICKS = 120

-- Matches Math.round in simulation.js for the non-negative values used here.
function M.round(v)
  return math.floor(v + 0.5)
end

-- Cents owed/earned this month at a flat annual_pct/12 rate.
function M.monthly_amount(cents, annual_pct)
  return M.round(cents * (annual_pct / 100 / 12))
end

-- Dollars rounded up to whole $10 plates.
function M.plates(dollars)
  return math.ceil(dollars / 10)
end

-- One iron plate pays one copper bill.
function M.match(iron, copper)
  local paired = math.min(iron, copper)
  return paired, iron - paired, copper - paired
end

-- Whole plates from cents, carrying the fraction into next month.
function M.to_plates(cents, carry_cents)
  local total = cents + carry_cents
  local plates = math.floor(total / M.CENTS_PER_PLATE)
  return plates, total - plates * M.CENTS_PER_PLATE
end

-- Single-account month-close reference implementation, exercised directly by
-- accounting_test.lua. The runtime (multi debt/vault station) equivalent lives in
-- stations.close_finance; the two must stay numerically consistent.
-- state:  debt_cents, opening_debt_cents, opening_principal_cents, interest_carry_cents, return_carry_cents
-- inputs: copper_waiting (bills that never made it onto a belt), node_iron, node_copper, vault_plates
-- rates:  debt_apr, asset_return (annual percent)
function M.close_month(state, inputs, rates)
  local debt_cents = state.debt_cents + inputs.copper_waiting * M.CENTS_PER_PLATE

  local interest_cents = M.monthly_amount(state.opening_debt_cents, rates.debt_apr)
  local interest_plates, interest_carry = M.to_plates(interest_cents, state.interest_carry_cents)

  local return_cents = M.monthly_amount(state.opening_principal_cents, rates.asset_return)
  local return_plates, return_carry = M.to_plates(return_cents, state.return_carry_cents)

  return {
    debt_cents = debt_cents,
    opening_debt_cents = debt_cents,
    opening_principal_cents = inputs.vault_plates * M.CENTS_PER_PLATE,
    interest_carry_cents = interest_carry,
    return_carry_cents = return_carry,
    report = {
      collected_plates = inputs.copper_waiting,
      surplus_plates = inputs.node_iron,
      unpaid_plates = inputs.node_copper,
      interest_cents = interest_cents,
      interest_plates = interest_plates,
      return_cents = return_cents,
      return_plates = return_plates,
    },
  }
end
-- Closes a year of month reports into one summary. `totals` holds plates of cash and bills that
-- settled at the Account's Cashflow Stations during the year; assets and debt are year-end
-- balances in cents. Income and expenses are therefore what actually moved through settlement.
function M.year_report(year, totals, assets_cents, debt_cents)
  return {
    year = year,
    income_cents = totals.cash_in * M.CENTS_PER_PLATE,
    expense_cents = totals.bills_in * M.CENTS_PER_PLATE,
    assets_cents = assets_cents,
    debt_cents = debt_cents,
    net_worth_cents = assets_cents - debt_cents,
  }
end

-- Converts the 1-based month counter (cf.month) into a 12-month calendar: month 1 is
-- Year 1 Month 1, month 13 is Year 2 Month 1.
function M.calendar(month)
  local m = month - 1
  return math.floor(m / 12) + 1, (m % 12) + 1
end
-- Formats cents as a signed, thousands-grouped dollar string, e.g. -123456 -> "-$1,234".
function M.money(cents)
  local negative = cents < 0
  local dollars = math.floor(math.abs(cents) / 100)
  local out = tostring(dollars):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (negative and "-$" or "$") .. out
end

return M
