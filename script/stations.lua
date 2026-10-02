-- Factorio-side station I/O: belt push/take helpers, per-station inventories, and the
-- debt/vault balance math that turns accounting.lua's cent math into plates on belts.
-- One controller can own many cashflow/debt/vault stations; balances are summed across all of them.
-- Debt and assets are both "what's physically in the chest" — a debt station's copper-plate
-- count *is* its debt, exactly like a vault station's iron-plate count *is* its assets. There
-- is no separate ledger field kept in sync behind the scenes: paying removes matching copper
-- from the chest (and discards the paying iron), borrowing inserts copper into the chest, and
-- manually editing a chest's contents genuinely changes the balance, same as a vault.
local acc = require("script.accounting")
local layout = require("script.station_layout")
local M = {}
local IRON, COPPER, COAL, P, ALL = "iron-plate", "copper-plate", "coal", acc.CENTS_PER_PLATE, 100000
local LINES = { 1, 2 }
M.IRON, M.COPPER = IRON, COPPER

-- Per-month output/input counters reset by account.reset_month.
function M.new_outputs() return { surplus = 0, unpaid = 0, interest = 0, returns = 0 } end
-- Per-month belt-traffic counters surfaced in pulse.close_month's report.
function M.new_month_stats() return { cash_in = 0, bills_in = 0, paid = 0, borrowed = 0, debt_paid = 0, deposits = 0 } end
-- Inserts up to `n` of `item` onto `belt`'s two transport lines, one item at a time so each
-- lane stays sparsely packed. Returns the number actually placed (belt may be full sooner).
function M.push(belt, item, n)
  local placed = 0
  while placed < n do
    local progressed = false
    for _, lane in ipairs(LINES) do
      if placed < n and belt.valid and belt.get_transport_line(lane).insert_at_back({ name = item, count = 1 }) then placed, progressed = placed + 1, true end
    end
    if not progressed then break end
  end
  return placed
end
-- Removes up to `n` of `item` from `belt`'s two transport lines combined. Returns the count taken.
function M.take(belt, item, n)
  local taken = 0
  if not (belt and belt.valid) then return 0 end
  for _, lane in ipairs(LINES) do if taken < n then taken = taken + belt.get_transport_line(lane).remove_item({ name = item, count = n - taken }) end end
  return taken
end
-- A machine's single chest inventory, or nil if its anchor entity is gone/invalid.
local function inventory(entity) return entity and entity.valid and entity.get_inventory(defines.inventory.chest) or nil end

-- Recomputes cf.debt_cents/opening_debt_cents (sum of every debt station's copper-plate count)
-- and cf.opening_principal_cents (sum of every vault station's iron-plate count).
function M.refresh_totals(cf)
  local debt, assets = 0, 0
  for _, machine in ipairs(cf.entities.debt or {}) do
    local inv = inventory(machine.anchor)
    debt = debt + (inv and inv.get_item_count(COPPER) or 0) * P
  end
  for _, machine in ipairs(cf.entities.vault or {}) do
    local inv = inventory(machine.anchor)
    assets = assets + (inv and inv.get_item_count(IRON) or 0) * P
  end
  cf.debt_cents, cf.opening_debt_cents, cf.opening_principal_cents = debt, debt, assets
  return debt, assets
end

-- Total iron plates held across every linked vault station (= assets in plates).
function M.vault_plates(cf)
  local plates = 0
  for _, machine in ipairs(cf.entities.vault or {}) do local inv = inventory(machine.anchor); plates = plates + (inv and inv.get_item_count(IRON) or 0) end
  return plates
end

-- Spreads `count` of `item` evenly across `machines`' chests; any remainder (indivisible
-- plates) goes to the earliest machines in list order.
local function distribute_item(machines, item, count)
  local n = #machines
  if n == 0 or count <= 0 then return end
  local each, remainder = math.floor(count / n), count % n
  for i, machine in ipairs(machines) do
    local inv = inventory(machine.anchor)
    if inv then inv.insert({ name = item, count = each + (i <= remainder and 1 or 0) }) end
  end
end

-- Splits `plates` of starting/overflow copper (debt) evenly into every linked debt station's chest.
function M.distribute_debt(cf, plates)
  distribute_item(cf.entities.debt, COPPER, plates)
  M.refresh_totals(cf)
end

-- Splits `plates` of starting iron assets evenly into every linked vault station's chest.
function M.seed_vault(cf, plates)
  distribute_item(cf.entities.vault, IRON, plates)
end

-- Snapshots each debt/vault station's opening-of-month balance (read straight from its chest),
-- used as the interest/return base for the month that's about to run. Called once on first Start.
function M.capture_opening_balances(cf)
  for _, machine in ipairs(cf.entities.debt) do
    local inv = inventory(machine.anchor)
    machine.opening_debt_cents = (inv and inv.get_item_count(COPPER) or 0) * P
  end
  for _, machine in ipairs(cf.entities.vault) do
    local inv = inventory(machine.anchor)
    machine.opening_principal_cents = (inv and inv.get_item_count(IRON) or 0) * P
  end
  M.refresh_totals(cf)
end

-- Month close: feeds `waiting` copper (unpaid bills + prior interest) into debt stations'
-- chests, accrues interest per debt station and returns per vault station (each with its own
-- carried fraction), and refreshes totals. Returns combined interest/return cents and plates.
-- A rate edited while the account was running is held in `applied_apr`/`applied_return` so the
-- month that just ended uses the rate it started with; closing clears it, so the edit applies
-- to the next close.
function M.close_finance(cf, waiting)
  M.distribute_debt(cf, waiting)
  local interest_cents, interest_plates, return_cents, return_plates = 0, 0, 0, 0
  for _, machine in ipairs(cf.entities.debt) do
    local cents = acc.monthly_amount(machine.opening_debt_cents or 0, machine.applied_apr or machine.config.apr)
    machine.applied_apr = nil
    local plates, carry = acc.to_plates(cents, machine.interest_carry_cents or 0)
    machine.interest_carry_cents, machine.pending_interest = carry, (machine.pending_interest or 0) + plates
    local inv = inventory(machine.anchor)
    machine.opening_debt_cents = (inv and inv.get_item_count(COPPER) or 0) * P
    interest_cents, interest_plates = interest_cents + cents, interest_plates + plates
  end
  for _, machine in ipairs(cf.entities.vault) do
    local cents = acc.monthly_amount(machine.opening_principal_cents or 0, machine.applied_return or machine.config.asset_return)
    machine.applied_return = nil
    local plates, carry = acc.to_plates(cents, machine.return_carry_cents or 0)
    machine.return_carry_cents, machine.pending_returns = carry, (machine.pending_returns or 0) + plates
    local inv = inventory(machine.anchor)
    machine.opening_principal_cents = (inv and inv.get_item_count(IRON) or 0) * P
    return_cents, return_plates = return_cents + cents, return_plates + plates
  end
  M.refresh_totals(cf)
  return interest_cents, interest_plates, return_cents, return_plates
end

-- Iron/copper plate counts currently sitting across every linked Cashflow station chest.
function M.cashflow_plates(cf)
  local iron, copper = 0, 0
  for _, machine in ipairs(cf.entities.cashflow) do
    local inv = inventory(machine.anchor)
    if inv then iron, copper = iron + inv.get_item_count(IRON), copper + inv.get_item_count(COPPER) end
  end
  return iron, copper
end
-- Empties every Cashflow station chest at month close (unsettled iron/copper become surplus/unpaid).
function M.clear_cashflow(cf)
  for _, machine in ipairs(cf.entities.cashflow) do
    local inv = inventory(machine.anchor)
    if inv then
      for _, item in ipairs({ IRON, COPPER }) do local count = inv.get_item_count(item); if count > 0 then inv.remove({ name = item, count = count }) end end
    end
  end
end

-- Releases each income/expense station's whole planned monthly total as soon as the month starts:
-- in the month's first sweep the plates become owed to the belt (`machine.out`), and the belt
-- then takes them as fast as it can carry them.
local function emit(cf, role, item)
  for _, machine in ipairs(cf.entities[role]) do
    local planned, emitted = cf.plan[role][machine.unit_number] or 0, cf.emitted[role][machine.unit_number] or 0
    machine.out = (machine.out or 0) + planned - emitted
    cf.emitted[role][machine.unit_number] = planned
    local inv = inventory(machine.anchor)
    local placed = M.push(machine.entities.out, item, math.min(machine.out, inv and inv.get_item_count(item) or 0))
    if placed > 0 then inv.remove({ name = item, count = placed }); machine.out = machine.out - placed end
  end
end

-- Removes `n` of `item` from `invs` in list order. Caller guarantees the combined count suffices.
local function remove_across(invs, item, n)
  for _, inv in ipairs(invs) do
    if n == 0 then return end
    local got = math.min(n, inv.get_item_count(item))
    if got > 0 then inv.remove({ name = item, count = got }); n = n - got end
  end
end
-- Each Cashflow station pulls cash/bills off its own input belts (every port that
-- station_layout.roles.cashflow declares with output=false) into its own chest. Settlement is
-- then pooled per account: one iron plate pays one copper plate across all of the account's
-- Cashflow chests, so cash landing in one station pays bills waiting in another.
local function cashflow(cf)
  local stats, invs, iron_total, copper_total = cf.stats, {}, 0, 0
  for _, machine in ipairs(cf.entities.cashflow) do
    local inv = inventory(machine.anchor)
    if inv then
      for _, port in ipairs(layout.roles.cashflow.helpers) do
        if not port.output then
          local belt = machine.entities[port.key]
          local iron, copper = M.take(belt, IRON, inv.get_insertable_count(IRON)), M.take(belt, COPPER, inv.get_insertable_count(COPPER))
          if iron > 0 then inv.insert({ name = IRON, count = iron }) end
          if copper > 0 then inv.insert({ name = COPPER, count = copper }) end
          stats.cash_in, stats.bills_in = stats.cash_in + iron, stats.bills_in + copper
        end
      end
      invs[#invs + 1] = inv
      iron_total, copper_total = iron_total + inv.get_item_count(IRON), copper_total + inv.get_item_count(COPPER)
    end
  end
  local paid = math.min(iron_total, copper_total)
  if paid > 0 then
    remove_across(invs, IRON, paid); remove_across(invs, COPPER, paid)
    stats.paid, cf.consumed_total_cents = stats.paid + paid, cf.consumed_total_cents + paid * P
  end
end

-- Pushes up to `n` of `item` round-robin, one plate at a time, onto the `key` output belt of
-- every machine, so a backed-up belt never stalls the others. Returns the count placed.
local function push_spread(machines, key, item, n)
  local placed, progressed = 0, true
  while placed < n and progressed do
    progressed = false
    for _, machine in ipairs(machines) do
      if placed < n and M.push(machine.entities[key], item, 1) == 1 then placed, progressed = placed + 1, true end
    end
  end
  return placed
end

-- Each debt station takes borrowed copper off its belt straight into its chest (grows debt,
-- same as a vault deposit), then takes iron off its pay belt capped at the chest's *current*
-- copper count (so a station with zero debt accepts zero pay-in iron — it just backs up on the
-- belt) and removes that many copper plates. The paying iron is discarded, not stored: paying
-- down debt spends cash, it doesn't bank it.
local function debt(cf)
  for _, machine in ipairs(cf.entities.debt) do
    local inv = inventory(machine.anchor)
    if inv then
      local borrowed = M.take(machine.entities.borrow_in, COPPER, inv.get_insertable_count(COPPER))
      if borrowed > 0 then inv.insert({ name = COPPER, count = borrowed }); cf.stats.borrowed = cf.stats.borrowed + borrowed end
      local paid = M.take(machine.entities.pay_in, IRON, inv.get_item_count(COPPER))
      if paid > 0 then inv.remove({ name = COPPER, count = paid }); cf.stats.debt_paid = cf.stats.debt_paid + paid end
    end
  end
end

-- Each vault station takes deposited iron off its belt into its chest (grows assets).
local function vault(cf)
  for _, machine in ipairs(cf.entities.vault) do
    local inv = inventory(machine.anchor)
    if inv then
      local got = M.take(machine.entities.deposit_in, IRON, inv.get_insertable_count(IRON))
      if got > 0 then inv.insert({ name = IRON, count = got }); cf.stats.deposits = cf.stats.deposits + got end
    end
  end
end

-- Each Smelter turns one hand-delivered batch of SMELTER_COAL_PER_MONTH coal into its configured
-- salary, at most once per month: the coal is consumed when smelting starts, the furnace glows
-- for SMELT_TICKS, then the salary (rounded up to whole plates) queues on its CASH OUT belt.
-- `batch_done` is cleared by pulse.close_month; a batch started late in a month still finishes.
local function smelter(cf, ticks)
  for _, machine in ipairs(cf.entities.smelter) do
    if machine.smelt_ticks then
      machine.smelt_ticks = machine.smelt_ticks - ticks
      if machine.smelt_ticks <= 0 then
        if machine.smelt_glow and machine.smelt_glow.valid then machine.smelt_glow.destroy() end
        machine.smelt_ticks, machine.smelt_glow = nil, nil
        machine.pending_salary = machine.pending_salary + math.ceil(machine.config.monthly_cents / P)
      end
    elseif not machine.batch_done then
      local inv = inventory(machine.anchor)
      if inv and inv.get_item_count(COAL) >= acc.SMELTER_COAL_PER_MONTH then
        inv.remove({ name = COAL, count = acc.SMELTER_COAL_PER_MONTH })
        machine.batch_done, machine.smelt_ticks = true, acc.SMELT_TICKS
        machine.smelt_glow = rendering.draw_animation { animation = "cashflow-smelter-heater", surface = machine.anchor.surface, target = machine.anchor }
      end
    end
    machine.pending_salary = machine.pending_salary - M.push(machine.entities.out, IRON, machine.pending_salary)
  end
end

-- Tops a Coal Supply chest back up to full. It belongs to no account and runs while paused.
function M.refill_coal(entity)
  local inv = inventory(entity)
  local room = inv and inv.get_insertable_count(COAL) or 0
  if room > 0 then inv.insert({ name = COAL, count = room }) end
end

-- Called every SWEEP_TICKS for a running account: advances the month clock, runs every
-- station's belt I/O, then flushes any pending surplus/unpaid/interest/returns onto their
-- output belts (capped by what each push actually accepts) and refreshes account totals.
-- `cf.unpaid_blocked_ticks` counts consecutive ticks in which unpaid bills were waiting but not
-- a single plate fit on any UNPAID OUT belt; control.lua turns that into an alert.
function M.sweep(cf, ticks)
  cf.tick_in_month = cf.tick_in_month + ticks
  emit(cf, "income", IRON); emit(cf, "expense", COPPER); cashflow(cf); debt(cf); vault(cf); smelter(cf, ticks)
  local e = cf.entities
  cf.out.surplus = cf.out.surplus - push_spread(e.cashflow, "surplus_out", IRON, cf.out.surplus)
  local unpaid_pushed = push_spread(e.cashflow, "unpaid_out", COPPER, cf.out.unpaid)
  cf.out.unpaid = cf.out.unpaid - unpaid_pushed
  cf.unpaid_blocked_ticks = (cf.out.unpaid > 0 and unpaid_pushed == 0) and (cf.unpaid_blocked_ticks or 0) + ticks or 0
  for _, machine in ipairs(e.debt) do machine.pending_interest = machine.pending_interest - M.push(machine.entities.interest_out, COPPER, machine.pending_interest) end
  for _, machine in ipairs(e.vault) do machine.pending_returns = machine.pending_returns - M.push(machine.entities.return_out, IRON, machine.pending_returns) end
  M.refresh_totals(cf)
end
return M
