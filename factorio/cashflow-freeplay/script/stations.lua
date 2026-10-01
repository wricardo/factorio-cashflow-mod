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
local function inventory(entity)
  return entity and entity.valid and entity.get_inventory(defines.inventory.chest) or nil
end
function M.sync_ledger(cf)
  local debt = cf.entities.debt
  local inv = debt and inventory(debt.anchor)
  if not inv then return end
  local target, have = math.floor(cf.debt_cents / P), inv.get_item_count(COPPER)
  if have < target then inv.insert({ name = COPPER, count = target - have }) elseif have > target then inv.remove({ name = COPPER, count = have - target }) end
end
function M.vault_plates(cf)
  local vault = cf.entities.vault
  local inv = vault and inventory(vault.anchor)
  return inv and inv.get_item_count(IRON) or 0
end
function M.seed_vault(cf, plates)
  local vault = cf.entities.vault
  local inv = vault and inventory(vault.anchor)
  if inv and plates > 0 then inv.insert({ name = IRON, count = plates }) end
end
function M.cashflow_plates(cf)
  local cashflow = cf.entities.cashflow
  local inv = cashflow and inventory(cashflow.anchor)
  return inv and inv.get_item_count(IRON) or 0, inv and inv.get_item_count(COPPER) or 0
end
function M.clear_cashflow(cf)
  local cashflow = cf.entities.cashflow
  local inv = cashflow and inventory(cashflow.anchor)
  if not inv then return end
  local iron, copper = inv.get_item_count(IRON), inv.get_item_count(COPPER)
  if iron > 0 then inv.remove({ name = IRON, count = iron }) end
  if copper > 0 then inv.remove({ name = COPPER, count = copper }) end
end
local function emit(cf, role, item)
  for _, machine in ipairs(cf.entities[role]) do
    local planned, emitted = cf.plan[role][machine.unit_number] or 0, cf.emitted[role][machine.unit_number] or 0
    local due = acc.due_by_tick(planned, cf.tick_in_month)
    machine.out = (machine.out or 0) + due - emitted
    cf.emitted[role][machine.unit_number] = due
    local inv = inventory(machine.anchor)
    local available = inv and inv.get_item_count(item) or 0
    local placed = M.push(machine.entities.out, item, math.min(machine.out, available))
    if placed > 0 then inv.remove({ name = item, count = placed }); machine.out = machine.out - placed end
  end
end
local function cashflow(cf)
  local entity, stats = cf.entities.cashflow.entities, cf.stats
  local inv = inventory(cf.entities.cashflow.anchor)
  if not inv then return end
  for _, belt in ipairs({ entity.cash_in, entity.bills_in }) do
    local iron = M.take(belt, IRON, inv.get_insertable_count(IRON))
    local copper = M.take(belt, COPPER, inv.get_insertable_count(COPPER))
    if iron > 0 then inv.insert({ name = IRON, count = iron }) end
    if copper > 0 then inv.insert({ name = COPPER, count = copper }) end
    stats.cash_in, stats.bills_in = stats.cash_in + iron, stats.bills_in + copper
  end
  local paid = math.min(inv.get_item_count(IRON), inv.get_item_count(COPPER))
  if paid > 0 then
    inv.remove({ name = IRON, count = paid }); inv.remove({ name = COPPER, count = paid })
    stats.paid, cf.consumed_total_cents = stats.paid + paid, cf.consumed_total_cents + paid * P
  end
end
local function debt(cf)
  local entity, stats = cf.entities.debt.entities, cf.stats
  local inv = inventory(cf.entities.debt.anchor)
  if not inv then return end
  local borrowed = M.take(entity.borrow_in, COPPER, inv.get_insertable_count(COPPER))
  cf.debt_cents, stats.borrowed = cf.debt_cents + borrowed * P, stats.borrowed + borrowed
  if cf.debt_cents > 0 then
    local paid = M.take(entity.pay_in, IRON, math.floor(cf.debt_cents / P))
    cf.debt_cents, stats.debt_paid = cf.debt_cents - paid * P, stats.debt_paid + paid
  end
end
local function vault(cf)
  local entity, inv = cf.entities.vault.entities, inventory(cf.entities.vault.anchor)
  if not inv then return end
  local got = M.take(entity.deposit_in, IRON, inv.get_insertable_count(IRON))
  if got > 0 then inv.insert({ name = IRON, count = got }); cf.stats.deposits = cf.stats.deposits + got end
end
function M.sweep(cf, ticks)
  cf.tick_in_month = cf.tick_in_month + ticks
  emit(cf, "income", IRON); emit(cf, "expense", COPPER); cashflow(cf); debt(cf); vault(cf)
  local e = cf.entities
  for _, output in ipairs({ { "surplus", e.cashflow.entities.surplus_out, IRON }, { "unpaid", e.cashflow.entities.unpaid_out, COPPER }, { "interest", e.debt.entities.interest_out, COPPER }, { "returns", e.vault.entities.return_out, IRON } }) do
    cf.out[output[1]] = cf.out[output[1]] - M.push(output[2], output[3], cf.out[output[1]])
  end
  M.sync_ledger(cf)
end
return M
