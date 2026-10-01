local acc = require("script.accounting")
local stations = require("script.stations")
local M = {}

local function defaults(config)
  config = config or {}
  return {
    starting_debt_cents = config.starting_debt_cents or 1800000,
    starting_assets_cents = config.starting_assets_cents or 1200000,
    debt_apr = config.debt_apr or 18,
    asset_return = config.asset_return or 7,
  }
end

function M.new(controller, config)
  return {
    controller = controller, surface_index = controller.surface.index, force_index = controller.force.index,
    name = "Account " .. controller.unit_number, running = false, started = false, month = 1, tick_in_month = 0,
    config = defaults(config), machines = {}, entities = { income = {}, expense = {} }, plan = {}, emitted = {}, out = {},
    node = { iron = 0, copper = 0 }, stats = {}, meters = {}, renderings = {},
    debt_cents = 0, opening_debt_cents = 0, opening_principal_cents = 0, interest_carry_cents = 0, return_carry_cents = 0,
    consumed_total_cents = 0, goals = {}, won = false,
  }
end

function M.can_start(cf)
  local missing = {}
  for _, role in ipairs({ "cashflow", "debt", "vault" }) do if not cf.entities[role] then missing[#missing + 1] = role end end
  if #missing > 0 then return false, "Missing linked " .. table.concat(missing, ", ") .. " station." end
  return true
end

function M.plan_month(cf)
  local plan = { income = {}, expense = {} }
  for _, role in ipairs({ "income", "expense" }) do
    for _, machine in ipairs(cf.entities[role]) do
      plan[role][machine.unit_number] = math.ceil(machine.config.monthly_cents / acc.CENTS_PER_PLATE)
    end
  end
  return plan
end

function M.reset_month(cf, preserve_outputs)
  cf.emitted = { income = {}, expense = {} }
  if not preserve_outputs then cf.out = stations.new_outputs() end
  for _, role in ipairs({ "income", "expense" }) do
    for _, machine in ipairs(cf.entities[role]) do cf.emitted[role][machine.unit_number] = 0 end
  end
  cf.node = { iron = 0, copper = 0 }
  cf.stats = stations.new_month_stats()
end
function M.fill_month_buffers(cf)
  for _, role in ipairs({ "income", "expense" }) do
    local item = role == "income" and "iron-plate" or "copper-plate"
    for _, machine in ipairs(cf.entities[role]) do
      local planned = cf.plan[role][machine.unit_number] or 0
      if planned > 0 then machine.anchor.get_inventory(defines.inventory.chest).insert({ name = item, count = planned }) end
    end
  end
  cf.buffered_month = cf.month
end
function M.restore_month_buffers(cf)
  if not cf.started or cf.buffered_month == cf.month then return end
  for _, role in ipairs({ "income", "expense" }) do
    local item = role == "income" and "iron-plate" or "copper-plate"
    for _, machine in ipairs(cf.entities[role]) do
      local planned = cf.plan[role][machine.unit_number] or 0
      local emitted = cf.emitted[role] and cf.emitted[role][machine.unit_number] or 0
      local remaining = planned - emitted
      local inv = machine.anchor.get_inventory(defines.inventory.chest)
      if remaining > 0 and inv.get_item_count(item) == 0 then inv.insert({ name = item, count = remaining }) end
    end
  end
  cf.buffered_month = cf.month
end

function M.start(cf, stations)
  local ok, reason = M.can_start(cf)
  if not ok then return false, reason end
  if not cf.started then
    cf.started = true
    cf.debt_cents = cf.config.starting_debt_cents
    cf.opening_debt_cents = cf.debt_cents
    cf.opening_principal_cents = cf.config.starting_assets_cents
    stations.seed_vault(cf, math.floor(cf.config.starting_assets_cents / acc.CENTS_PER_PLATE))
    cf.plan = M.plan_month(cf)
    M.reset_month(cf)
    M.fill_month_buffers(cf)
    stations.sync_ledger(cf)
  end
  cf.running = true
  return true
end

return M
