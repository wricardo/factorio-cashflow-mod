local acc = require("script.accounting")
local M = {}
local IRON, COPPER, P, ALL = "iron-plate", "copper-plate", acc.CENTS_PER_PLATE, 100000
local LINES = { 1, 2 }
M.IRON, M.COPPER = IRON, COPPER

function M.new_outputs() return { surplus = 0, unpaid = 0, interest = 0, returns = 0 } end
function M.new_month_stats() return { cash_in = 0, bills_in = 0, paid = 0, borrowed = 0, debt_paid = 0, deposits = 0 } end
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
function M.take(belt, item, n)
  local taken = 0
  if not (belt and belt.valid) then return 0 end
  for _, lane in ipairs(LINES) do if taken < n then taken = taken + belt.get_transport_line(lane).remove_item({ name = item, count = n - taken }) end end
  return taken
end
local function inventory(entity) return entity and entity.valid and entity.get_inventory(defines.inventory.chest) or nil end

function M.refresh_totals(cf)
  local debt, assets = 0, 0
  for _, machine in ipairs(cf.entities.debt or {}) do debt = debt + (machine.debt_cents or 0) end
  for _, machine in ipairs(cf.entities.vault or {}) do
    local inv = inventory(machine.anchor)
    assets = assets + (inv and inv.get_item_count(IRON) or 0) * P
  end
  cf.debt_cents, cf.opening_debt_cents, cf.opening_principal_cents = debt, debt, assets
  return debt, assets
end

function M.sync_ledger(cf)
  for _, machine in ipairs(cf.entities.debt or {}) do
    local inv = inventory(machine.anchor)
    if inv then
      local target, have = math.floor((machine.debt_cents or 0) / P), inv.get_item_count(COPPER)
      if have < target then inv.insert({ name = COPPER, count = target - have }) elseif have > target then inv.remove({ name = COPPER, count = have - target }) end
    end
  end
  M.refresh_totals(cf)
end

function M.vault_plates(cf)
  local plates = 0
  for _, machine in ipairs(cf.entities.vault or {}) do local inv = inventory(machine.anchor); plates = plates + (inv and inv.get_item_count(IRON) or 0) end
  return plates
end

local function distribute(total, machines, field)
  local count = #machines
  if count == 0 or total <= 0 then return end
  local each, remainder = math.floor(total / count), total % count
  for i, machine in ipairs(machines) do machine[field] = (machine[field] or 0) + each + (i <= remainder and 1 or 0) end
end

function M.distribute_debt(cf, cents)
  distribute(cents, cf.entities.debt, "debt_cents")
  M.refresh_totals(cf)
end

function M.seed_vault(cf, plates)
  local vaults = cf.entities.vault
  local count = #vaults
  if count == 0 or plates <= 0 then return end
  local each, remainder = math.floor(plates / count), plates % count
  for i, machine in ipairs(vaults) do
    local inv = inventory(machine.anchor)
    if inv then inv.insert({ name = IRON, count = each + (i <= remainder and 1 or 0) }) end
  end
end

function M.capture_opening_balances(cf)
  for _, machine in ipairs(cf.entities.debt) do machine.opening_debt_cents = machine.debt_cents or 0 end
  for _, machine in ipairs(cf.entities.vault) do
    local inv = inventory(machine.anchor)
    machine.opening_principal_cents = (inv and inv.get_item_count(IRON) or 0) * P
  end
  M.refresh_totals(cf)
end

function M.monthly_returns_cents(cf)
  local total = 0
  for _, machine in ipairs(cf.entities.vault) do
    local inv = inventory(machine.anchor)
    total = total + acc.monthly_amount((inv and inv.get_item_count(IRON) or 0) * P, machine.config.asset_return)
  end
  return total
end

function M.close_finance(cf, waiting)
  M.distribute_debt(cf, waiting * P)
  local interest_cents, interest_plates, return_cents, return_plates = 0, 0, 0, 0
  for _, machine in ipairs(cf.entities.debt) do
    local cents = acc.monthly_amount(machine.opening_debt_cents or 0, machine.config.apr)
    local plates, carry = acc.to_plates(cents, machine.interest_carry_cents or 0)
    machine.interest_carry_cents, machine.pending_interest = carry, (machine.pending_interest or 0) + plates
    machine.opening_debt_cents = machine.debt_cents or 0
    interest_cents, interest_plates = interest_cents + cents, interest_plates + plates
  end
  for _, machine in ipairs(cf.entities.vault) do
    local cents = acc.monthly_amount(machine.opening_principal_cents or 0, machine.config.asset_return)
    local plates, carry = acc.to_plates(cents, machine.return_carry_cents or 0)
    machine.return_carry_cents, machine.pending_returns = carry, (machine.pending_returns or 0) + plates
    local inv = inventory(machine.anchor)
    machine.opening_principal_cents = (inv and inv.get_item_count(IRON) or 0) * P
    return_cents, return_plates = return_cents + cents, return_plates + plates
  end
  M.refresh_totals(cf)
  return interest_cents, interest_plates, return_cents, return_plates
end

function M.cashflow_plates(cf)
  local inv = cf.entities.cashflow and inventory(cf.entities.cashflow.anchor)
  return inv and inv.get_item_count(IRON) or 0, inv and inv.get_item_count(COPPER) or 0
end
function M.clear_cashflow(cf)
  local inv = cf.entities.cashflow and inventory(cf.entities.cashflow.anchor)
  if not inv then return end
  for _, item in ipairs({ IRON, COPPER }) do local count = inv.get_item_count(item); if count > 0 then inv.remove({ name = item, count = count }) end end
end

local function emit(cf, role, item)
  for _, machine in ipairs(cf.entities[role]) do
    local planned, emitted = cf.plan[role][machine.unit_number] or 0, cf.emitted[role][machine.unit_number] or 0
    local due = acc.due_by_tick(planned, cf.tick_in_month)
    machine.out = (machine.out or 0) + due - emitted
    cf.emitted[role][machine.unit_number] = due
    local inv = inventory(machine.anchor)
    local placed = M.push(machine.entities.out, item, math.min(machine.out, inv and inv.get_item_count(item) or 0))
    if placed > 0 then inv.remove({ name = item, count = placed }); machine.out = machine.out - placed end
  end
end

local function cashflow(cf)
  local entity, stats, inv = cf.entities.cashflow.entities, cf.stats, inventory(cf.entities.cashflow.anchor)
  if not inv then return end
  for _, belt in ipairs({ entity.cash_in, entity.bills_in }) do
    local iron, copper = M.take(belt, IRON, inv.get_insertable_count(IRON)), M.take(belt, COPPER, inv.get_insertable_count(COPPER))
    if iron > 0 then inv.insert({ name = IRON, count = iron }) end
    if copper > 0 then inv.insert({ name = COPPER, count = copper }) end
    stats.cash_in, stats.bills_in = stats.cash_in + iron, stats.bills_in + copper
  end
  local paid = math.min(inv.get_item_count(IRON), inv.get_item_count(COPPER))
  if paid > 0 then inv.remove({ name = IRON, count = paid }); inv.remove({ name = COPPER, count = paid }); stats.paid, cf.consumed_total_cents = stats.paid + paid, cf.consumed_total_cents + paid * P end
end

local function debt(cf)
  for _, machine in ipairs(cf.entities.debt) do
    local inv = inventory(machine.anchor)
    if inv then
      local borrowed = M.take(machine.entities.borrow_in, COPPER, inv.get_insertable_count(COPPER))
      machine.debt_cents, cf.stats.borrowed = (machine.debt_cents or 0) + borrowed * P, cf.stats.borrowed + borrowed
      local paid = M.take(machine.entities.pay_in, IRON, math.floor((machine.debt_cents or 0) / P))
      machine.debt_cents, cf.stats.debt_paid = machine.debt_cents - paid * P, cf.stats.debt_paid + paid
    end
  end
end

local function vault(cf)
  for _, machine in ipairs(cf.entities.vault) do
    local inv = inventory(machine.anchor)
    if inv then
      local got = M.take(machine.entities.deposit_in, IRON, inv.get_insertable_count(IRON))
      if got > 0 then inv.insert({ name = IRON, count = got }); cf.stats.deposits = cf.stats.deposits + got end
    end
  end
end

function M.sweep(cf, ticks)
  cf.tick_in_month = cf.tick_in_month + ticks
  emit(cf, "income", IRON); emit(cf, "expense", COPPER); cashflow(cf); debt(cf); vault(cf)
  local e = cf.entities
  cf.out.surplus = cf.out.surplus - M.push(e.cashflow.entities.surplus_out, IRON, cf.out.surplus)
  cf.out.unpaid = cf.out.unpaid - M.push(e.cashflow.entities.unpaid_out, COPPER, cf.out.unpaid)
  for _, machine in ipairs(e.debt) do machine.pending_interest = machine.pending_interest - M.push(machine.entities.interest_out, COPPER, machine.pending_interest) end
  for _, machine in ipairs(e.vault) do machine.pending_returns = machine.pending_returns - M.push(machine.entities.return_out, IRON, machine.pending_returns) end
  M.sync_ledger(cf)
end
return M
