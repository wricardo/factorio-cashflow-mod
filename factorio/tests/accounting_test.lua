local acc = require("script.accounting")

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local T = {}

-- Same numbers as the default scenario in simulation.js / readme.md.
function T.debt_interest_matches_simulation()
  eq(acc.monthly_amount(1800000, 18), 27000)
end

function T.asset_return_matches_simulation()
  eq(acc.monthly_amount(1200000, 7), 7000)
end

function T.plates_round_up()
  eq(acc.plates(2000), 200)
  eq(acc.plates(805), 81)
  eq(acc.plates(0), 0)
end
function T.calendar_rolls_year_every_twelve_months()
  local y1, m1 = acc.calendar(1)
  eq(y1, 1); eq(m1, 1)
  local y12, m12 = acc.calendar(12)
  eq(y12, 1); eq(m12, 12)
  local y13, m13 = acc.calendar(13)
  eq(y13, 2); eq(m13, 1)
  local y25, m25 = acc.calendar(25)
  eq(y25, 3); eq(m25, 1)
end

function T.emission_spreads_evenly_and_hits_total()
  eq(acc.due_by_tick(500, 0), 0)
  eq(acc.due_by_tick(500, 1800), 250)
  eq(acc.due_by_tick(500, 3600), 500)
  eq(acc.due_by_tick(500, 9999), 500)
  local prev = 0
  for t = 2, 3600, 2 do
    local due = acc.due_by_tick(500, t)
    assert(due >= prev, "emission must never go backwards")
    prev = due
  end
end

function T.one_iron_pays_one_copper()
  local paired, iron, copper = acc.match(10, 4)
  eq(paired, 4)
  eq(iron, 6)
  eq(copper, 0)
  paired, iron, copper = acc.match(3, 7)
  eq(paired, 3)
  eq(iron, 0)
  eq(copper, 4)
end

function T.fractions_carry_into_next_month()
  local plates, carry = acc.to_plates(500, 0)
  eq(plates, 0)
  eq(carry, 500)
  plates, carry = acc.to_plates(500, carry)
  eq(plates, 1)
  eq(carry, 0)
end

local function default_state()
  return {
    debt_cents = 1800000,
    opening_debt_cents = 1800000,
    opening_principal_cents = 1200000,
    interest_carry_cents = 0,
    return_carry_cents = 0,
  }
end

local rates = { debt_apr = 18, asset_return = 7 }

function T.interest_is_a_bill_not_added_to_debt()
  local r = acc.close_month(default_state(), { copper_waiting = 0, node_iron = 0, node_copper = 0, vault_plates = 1200 }, rates)
  eq(r.debt_cents, 1800000, "debt only grows when copper reaches it")
  eq(r.report.interest_plates, 27)
  eq(r.report.return_plates, 7)
end

function T.unbelted_copper_is_charged_to_debt()
  local r = acc.close_month(default_state(), { copper_waiting = 130, node_iron = 0, node_copper = 0, vault_plates = 1200 }, rates)
  eq(r.debt_cents, 1800000 + 130000)
  eq(r.opening_debt_cents, 1930000)
  eq(r.report.collected_plates, 130)
end

function T.node_leftovers_become_surplus_and_unpaid()
  local r = acc.close_month(default_state(), { copper_waiting = 0, node_iron = 220, node_copper = 0, vault_plates = 1200 }, rates)
  eq(r.report.surplus_plates, 220)
  eq(r.report.unpaid_plates, 0)
end

function T.interest_uses_opening_debt()
  local s = default_state()
  s.debt_cents = 0
  local r = acc.close_month(s, { copper_waiting = 0, node_iron = 0, node_copper = 0, vault_plates = 1200 }, rates)
  eq(r.report.interest_cents, 27000)
end

function T.deposits_start_earning_next_month()
  local r = acc.close_month(default_state(), { copper_waiting = 0, node_iron = 0, node_copper = 0, vault_plates = 1400 }, rates)
  eq(r.report.return_cents, 7000)
  eq(r.opening_principal_cents, 1400000)
end

function T.financial_independence_requires_zero_debt()
  -- $480,000 at 7% returns exactly $2,800/month
  eq(acc.is_financially_independent(0, 48000000, 7, 2000, 800), true)
  eq(acc.is_financially_independent(0, 47990000, 7, 2000, 800), false)
  eq(acc.is_financially_independent(1000, 48000000, 7, 2000, 800), false)
end

function T.money_formatting()
  eq(acc.money(0), "$0")
  eq(acc.money(99), "$0")
  eq(acc.money(100000), "$1,000")
  eq(acc.money(1823456789), "$18,234,567")
  eq(acc.money(-50000), "-$500")
end

return T
