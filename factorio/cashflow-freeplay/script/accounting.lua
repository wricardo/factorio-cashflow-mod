-- Pure money math. No Factorio API here so it can be unit-tested with plain Lua.
-- Money is integer cents. One plate is $10: iron plates are cash, copper plates are bills/debt.

local M = {}

M.CENTS_PER_PLATE = 1000
M.TICKS_PER_MONTH = 3600
-- Income/Expense stations emit through one blue (express) belt port: 45 plates/s caps it at
-- $27,000/month, so configured amounts are limited to $20,000 (2,000 plates) per station.
M.MAX_STATION_MONTHLY_CENTS = 2000000

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

-- How many of `total` plates should have been emitted by this tick, spread evenly over the month.
function M.due_by_tick(total, tick_in_month, ticks_per_month)
  ticks_per_month = ticks_per_month or M.TICKS_PER_MONTH
  local t = math.min(math.max(tick_in_month, 0), ticks_per_month)
  return math.floor(total * t / ticks_per_month)
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
-- Debt-free and principal's monthly return at least covers monthly needs+wants: the
-- Rich Dad "financial independence" win condition.

function M.is_financially_independent(debt_cents, principal_cents, asset_return, needs_dollars, wants_dollars)
  if debt_cents > 0 then return false end
  local expenses_cents = (needs_dollars + wants_dollars) * 100
  return M.monthly_amount(principal_cents, asset_return) >= expenses_cents
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
