-- Per-controller account lifecycle: config defaults, save-format migration (M.normalize),
-- Start/Pause gating, and the monthly income/expense planning + buffer fill/restore used by
-- control.lua's sweep loop. Actual belt/inventory work is delegated to stations.lua.
local acc = require("script.accounting")
local labels = require("script.labels")
local stations = require("script.stations")
local M = {}

-- Fills in config fields with factory defaults; `defaults(cf.config)` round-trips existing values.
local function defaults(config)
  config = config or {}
  return {
    starting_debt_cents = config.starting_debt_cents or 1800000,
    starting_assets_cents = config.starting_assets_cents or 1200000,
    debt_apr = config.debt_apr or 18,
    asset_return = config.asset_return or 7,
  }
end
-- Fresh account record for a newly placed controller entity; `config` seeds starting
-- debt/assets and (legacy) controller-wide debt APR / asset return.

function M.new(controller, config)
  return {
    controller = controller, surface_index = controller.surface.index, force_index = controller.force.index,
    name = "Account " .. controller.unit_number, running = false, started = false, month = 1, tick_in_month = 0,
    config = defaults(config), machines = {}, entities = { income = {}, expense = {}, cashflow = {}, debt = {}, vault = {}, smelter = {} }, plan = {}, emitted = {}, out = {},
    node = { iron = 0, copper = 0 }, stats = {}, meters = {}, renderings = {}, year_totals = { cash_in = 0, bills_in = 0 }, year_reports = {},
    debt_cents = 0, opening_debt_cents = 0, opening_principal_cents = 0,
    consumed_total_cents = 0, goals = {},
  }
end
-- Upgrades a stored account to the current shape: migrates single-station cashflow/debt/vault
-- entries into per-station lists, backfills new per-station config fields (APR, return, carries) from
-- the old controller-wide rates, and recovers a pre-multi-station legacy debt balance onto the
-- first debt station. Called on load and after every config_changed.

function M.normalize(cf)
  local legacy_debt = cf.debt_cents or 0
  local legacy_single_debt = cf.entities and cf.entities.debt and cf.entities.debt.anchor
  cf.entities = cf.entities or {}
  for _, role in ipairs({ "income", "expense", "cashflow", "debt", "vault", "smelter" }) do
    local value = cf.entities[role]
    if value and value.anchor then cf.entities[role] = { value }
    elseif not value then cf.entities[role] = {} end
  end
  cf.config = defaults(cf.config)
  for _, machine in ipairs(cf.entities.debt) do
    machine.config = machine.config or {}
    machine.config.apr = machine.config.apr or cf.config.debt_apr or 18
    machine.debt_cents = nil
    machine.opening_debt_cents = machine.opening_debt_cents or 0
    machine.interest_carry_cents = machine.interest_carry_cents or 0
    machine.pending_interest = machine.pending_interest or 0
  end
  if legacy_single_debt and cf.entities.debt[1] and legacy_debt > 0 then
    local machine = cf.entities.debt[1]
    local inv = machine.anchor and machine.anchor.valid and machine.anchor.get_inventory(defines.inventory.chest)
    if inv and inv.get_item_count("copper-plate") == 0 then
      inv.insert({ name = "copper-plate", count = math.floor(legacy_debt / acc.CENTS_PER_PLATE) })
    end
    machine.opening_debt_cents = cf.opening_debt_cents or legacy_debt
    machine.interest_carry_cents = cf.interest_carry_cents or 0
  end
  for _, machine in ipairs(cf.entities.vault) do
    machine.config = machine.config or {}
    machine.config.asset_return = machine.config.asset_return or cf.config.asset_return or 7
    machine.opening_principal_cents = machine.opening_principal_cents or 0
    machine.return_carry_cents = machine.return_carry_cents or 0
    machine.pending_returns = machine.pending_returns or 0
  end
  for _, machine in ipairs(cf.entities.smelter) do machine.pending_salary = machine.pending_salary or 0 end
  cf.out = cf.out or stations.new_outputs()
  cf.year_totals = cf.year_totals or { cash_in = 0, bills_in = 0 }
  cf.year_reports = cf.year_reports or {}
  cf.won = nil
  stations.refresh_totals(cf)
end
-- Start is blocked unless at least one Cashflow Station, Debt Station, and Investment Account is
-- linked. Returns false + a human-readable reason naming the missing stations.

function M.can_start(cf)
  local missing = {}
  for _, role in ipairs({ "cashflow", "debt", "vault" }) do if #cf.entities[role] == 0 then missing[#missing + 1] = labels.display_name(role) end end
  if #missing > 0 then return false, "Missing linked " .. table.concat(missing, ", ") .. "." end
  return true
end
-- Plates each income/expense station must emit this month, rounded up from its monthly cents.

function M.plan_month(cf)
  local plan = { income = {}, expense = {} }
  for _, role in ipairs({ "income", "expense" }) do
    for _, machine in ipairs(cf.entities[role]) do plan[role][machine.unit_number] = math.ceil(machine.config.monthly_cents / acc.CENTS_PER_PLATE) end
  end
  return plan
end
-- Clears this month's emitted/node/stats counters; `preserve_outputs` keeps cf.out (pending
-- surplus/unpaid/interest/returns not yet pushed onto belts) instead of zeroing it.

function M.reset_month(cf, preserve_outputs)
  cf.emitted = { income = {}, expense = {} }
  if not preserve_outputs then cf.out = stations.new_outputs() end
  for _, role in ipairs({ "income", "expense" }) do
    for _, machine in ipairs(cf.entities[role]) do cf.emitted[role][machine.unit_number] = 0 end
  end
  cf.node = { iron = 0, copper = 0 }
  cf.stats = stations.new_month_stats()
end
-- Deposits the full month's planned income/expense plates into each station's chest up
-- front; `sweep`/`emit` then only trickles them onto the belt over the month.

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
-- After a save/reload mid-month, re-tops-up any station whose chest was drained (e.g. by a
-- player) but whose planned plates for this month haven't all been emitted yet. No-op if the
-- account hasn't started or buffers were already filled for the current month.

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
-- Validates required stations, and on the very first Start seeds opening debt/assets across
-- the linked stations, captures opening balances, and plans + buffers month 1. Subsequent
-- Starts (after a Pause) just resume; they don't reseed or replan.

function M.start(cf, station_api)
  local ok, reason = M.can_start(cf)
  if not ok then return false, reason end
  if not cf.started then
    cf.started = true
    station_api.distribute_debt(cf, math.floor(cf.config.starting_debt_cents / acc.CENTS_PER_PLATE))
    station_api.seed_vault(cf, math.floor(cf.config.starting_assets_cents / acc.CENTS_PER_PLATE))
    station_api.capture_opening_balances(cf)
    cf.plan = M.plan_month(cf)
    M.reset_month(cf)
    M.fill_month_buffers(cf)
  end
  cf.running = true
  return true
end

return M
