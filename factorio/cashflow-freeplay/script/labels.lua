-- Floating rendering.draw_text labels above every station/controller and its helper ports.
-- Pure presentation: reads account/machine state but never mutates it.
local acc = require("script.accounting")
local layout = require("script.station_layout")
local M = {}

-- Destroys a machine's compact world label and every port label before rebuilding them.
local function destroy(machine)
  if machine.label and machine.label.valid then machine.label.destroy() end
  for _, label in pairs(machine.port_labels or {}) do if label.valid then label.destroy() end end
  machine.label, machine.port_labels = nil, {}
end
-- Short world-label title for a role, and the full entity name used for panel captions.
-- Internal role keys (controller/income/vault/smelter) are unchanged so existing saves load.
local TITLES = { income = "Passive Income", smelter = "Active Income", vault = "Investment Account" }
local DISPLAY_NAMES = { controller = "Account", income = "Passive Income", expense = "Expense Station", cashflow = "Cashflow Station", debt = "Debt Station", vault = "Investment Account", smelter = "Active Income", ["percent-splitter"] = "Percent Splitter" }
local function title(role)
  return TITLES[role] or role:sub(1, 1):upper() .. role:sub(2)
end
function M.display_name(role) return DISPLAY_NAMES[role] end
-- Two-line summary of a yearly report, shared by the chat announcement and the Account panel.
function M.year_report_text(report)
  return "Income " .. acc.money(report.income_cents) .. " • Expenses " .. acc.money(report.expense_cents) .. "\nAssets " .. acc.money(report.assets_cents) .. " • Debt " .. acc.money(report.debt_cents) .. " • Net worth " .. acc.money(report.net_worth_cents)
end
-- "Left 30% • Right 70%" for a Percent Splitter's share, used by its panel.
function M.split_summary(percent) return "Left " .. percent .. "% • Right " .. (100 - percent) .. "%" end
-- Per-role label tint.

local COLORS = {
  controller = { 1, 0.85, 0.4 },
  income = { 0.4, 1, 0.4 },
  expense = { 1, 0.5, 0.3 },
  cashflow = { 0.45, 0.8, 1 },
  debt = { 1, 0.4, 0.35 },
  vault = { 1, 0.85, 0.4 },
  smelter = { 1, 0.65, 0.25 },
  coal = { 0.75, 0.75, 0.75 },
  splitter = { 0.55, 0.85, 1 },
}
-- Title label is pushed higher above the bigger 6x6 cashflow/vault buildings.

local function label_offset(role)
  if role == "cashflow" or role == "vault" then return { 0, -3.4 } end
  return { 0, -1.8 }
end
-- Port labels sit to the side the port is offset toward (east ports read from the left).
local function port_offset(port)
  if port.x < 0 then return { -0.8, 0 }, "right" end
  if port.x > 0 then return { 0.8, 0 }, "left" end
  return { 0, -0.8 }, "center"
end
-- Last closed month's actual net cashflow through the Cashflow station (cash in minus bills
-- in), so returns routed back as cash count the same as salary. Before the first month closes
-- (no last_report yet), falls back to the planned income-minus-expense for this month.
local function monthly_cashflow(cf)
  if cf.last_report then return (cf.last_report.cash_in - cf.last_report.bills_in) * acc.CENTS_PER_PLATE end
  local income, expenses = 0, 0
  for _, machine in ipairs(cf.entities.income) do income = income + machine.config.monthly_cents end
  for _, machine in ipairs(cf.entities.expense) do expenses = expenses + machine.config.monthly_cents end
  return income - expenses
end
-- Total iron-plate assets across every linked vault station, in cents.
local function assets(cf)
  local cents = 0
  for _, vault in ipairs(cf.entities.vault or {}) do
    local inv = vault.anchor.valid and vault.anchor.get_inventory(defines.inventory.chest)
    cents = cents + (inv and inv.get_item_count("iron-plate") or 0) * acc.CENTS_PER_PLATE
  end
  return cents
end
-- Iron-plate assets held in a single vault station's chest, in cents.

local function vault_cents(machine)
  local inv = machine.anchor.valid and machine.anchor.get_inventory(defines.inventory.chest)
  return (inv and inv.get_item_count("iron-plate") or 0) * acc.CENTS_PER_PLATE
end
-- Copper-plate debt held in a single debt station's chest, in cents.
local function debt_cents(machine)
  local inv = machine.anchor.valid and machine.anchor.get_inventory(defines.inventory.chest)
  return (inv and inv.get_item_count("copper-plate") or 0) * acc.CENTS_PER_PLATE
end
local EMPTY_DETAILS = {}

-- Smelter salary plus batch status, returned as pane rows.
local function smelter_details(machine)
  local status
  if machine.smelt_ticks then status = "Smelting..."
  elseif machine.batch_done then status = "Paid this month"
  else
    local inv = machine.anchor.get_inventory(defines.inventory.chest)
    status = "Coal " .. (inv and inv.get_item_count("coal") or 0) .. "/" .. acc.SMELTER_COAL_PER_MONTH
  end
  return { acc.money(machine.config.monthly_cents) .. " salary/month", status }
end

-- Details shared by the anchored station pane and the compact world label.
local function finance_details(machine)
  if machine.role == "debt" then
    local debt = debt_cents(machine)
    return { "Debt " .. acc.money(debt), "Interest " .. acc.money(acc.monthly_amount(debt, machine.config.apr)) .. "/month" }
  end
  if machine.role == "vault" then
    local held = vault_cents(machine)
    return { "Assets " .. acc.money(held), "Return " .. acc.money(acc.monthly_amount(held, machine.config.asset_return)) .. "/month" }
  end
  if machine.role == "smelter" then return smelter_details(machine) end
  return EMPTY_DETAILS
end

function M.machine_details(machine, cf)
  if machine.role == "income" or machine.role == "expense" then return { acc.money(machine.config.monthly_cents) .. "/month" } end
  if machine.role == "cashflow" then
    if not cf then return EMPTY_DETAILS end
    local cashflow = monthly_cashflow(cf)
    return { "Cashflow " .. (cashflow >= 0 and "+" or "") .. acc.money(cashflow) .. "/month" }
  end
  return finance_details(machine)
end

-- Factorio's hover pane has a status row ("Normal") that mods may override per entity through
-- LuaEntity::custom_status. A trailing space precedes each newline so the rows stay readable
-- even where the pane flattens line breaks.
local function set_status(entity, diode, lines)
  entity.custom_status = { diode = diode, label = table.concat(lines, " \n") }
end

-- Live, role-specific metrics for the station's hover pane: linked account plus its own figures.
local function update_status(machine, cf)
  local lines = { "Account: " .. (cf and cf.name or "Unlinked") }
  local details = M.machine_details(machine, cf)
  local rate = machine.role == "debt" and "APR " .. machine.config.apr .. "%" or machine.role == "vault" and "Return rate " .. machine.config.asset_return .. "%" or nil
  for i, detail in ipairs(details) do
    lines[#lines + 1] = detail
    if i == 1 and rate then lines[#lines + 1] = rate end
  end
  if machine.role == "expense" then lines[#lines + 1] = "Category: " .. machine.config.category end
  local diode = cf and defines.entity_status_diode.green or defines.entity_status_diode.yellow
  if machine.role == "cashflow" and cf and (cf.unpaid_blocked_ticks or 0) >= acc.UNPAID_ALERT_TICKS then
    lines[#lines + 1] = "UNPAID OUT blocked: " .. cf.out.unpaid .. " bills waiting"
    diode = defines.entity_status_diode.red
  end
  set_status(machine.anchor, diode, lines)
end

-- (Re)draws a compact world label plus helper-port labels, and refreshes the hover-pane status.
function M.machine(machine, cf)
  destroy(machine)
  if machine.anchor.valid then
    local details = M.machine_details(machine, cf)
    local text = title(machine.role) .. (#details > 0 and " • " .. table.concat(details, " • ") or "")
    machine.label = rendering.draw_text { text = text, surface = machine.anchor.surface, target = machine.anchor, target_offset = label_offset(machine.role), alignment = "center", color = COLORS[machine.role] }
    update_status(machine, cf)
    for _, port in ipairs(layout.roles[machine.role].helpers) do
      local entity = machine.entities[port.key]
      if port.label and entity and entity.valid then
        local port_offset_value, alignment = port_offset(port)
        machine.port_labels[port.key] = rendering.draw_text {
          text = port.label, surface = entity.surface, target = entity, target_offset = port_offset_value, alignment = alignment,
          color = port.cash and { 1, 1, 1 } or (port.copper and { 1, 0.5, 0.3 } or (port.output and { 0.4, 1, 0.4 } or { 1, 0.5, 0.3 })),
        }
      end
    end
  end
end
-- (Re)draws a controller's status label: name, running state, total assets, debt, and net worth
-- (assets minus debt) across every linked station. Cashflow is displayed by Cashflow Stations.
function M.account(cf)
  if cf.label and cf.label.valid then cf.label.destroy() end
  if cf.controller.valid then
    local year, month = acc.calendar(cf.month)
    local asset_cents = assets(cf)
    cf.label = rendering.draw_text {
      text = cf.name .. " • " .. (cf.running and "Running" or "Paused") .. " • Year " .. year .. " Month " .. month .. "\nAssets " .. acc.money(asset_cents) .. " • Debt " .. acc.money(cf.debt_cents) .. " • Net worth " .. acc.money(asset_cents - cf.debt_cents),
      surface = cf.controller.surface, target = cf.controller, target_offset = { 0, -2.5 }, alignment = "center",
      color = cf.running and { 0.4, 1, 0.4 } or { 1, 1, 1 },
    }
  end
end
-- Coal Supply's fixed title; the render object dies with the entity, so nothing is stored.
function M.coal_supply(entity)
  rendering.draw_text { text = "Coal Supply", surface = entity.surface, target = entity, target_offset = label_offset("coal"), alignment = "center", color = COLORS.coal }
  M.refresh_coal(entity)
end
-- Coal Supply hover-pane status: current stock out of its capacity.
function M.refresh_coal(entity)
  local inventory = entity.get_inventory(defines.inventory.chest)
  local coal = inventory and inventory.get_item_count("coal") or 0
  local capacity = coal + (inventory and inventory.get_insertable_count("coal") or 0)
  set_status(entity, defines.entity_status_diode.green, { "Coal " .. coal .. "/" .. capacity })
end
-- Percent Splitter: compact world label plus hover-pane status. `rec` is its record in
-- storage.cf_freeplay.splitters ({ entity, percent, label }); the render object is kept so a
-- change of percent replaces it instead of stacking labels.
function M.splitter(rec)
  if rec.label and rec.label.valid then rec.label.destroy() end
  rec.label = nil
  local entity = rec.entity
  if not entity.valid then return end
  local left, right = rec.percent, 100 - rec.percent
  rec.label = rendering.draw_text { text = "Split " .. left .. "% left • " .. right .. "% right", surface = entity.surface, target = entity, target_offset = { 0, -1.5 }, alignment = "center", color = COLORS.splitter }
  set_status(entity, defines.entity_status_diode.green, { "Left " .. left .. "%", "Right " .. right .. "%" })
end
function M.destroy_splitter(rec) if rec.label and rec.label.valid then rec.label.destroy() end end
-- Thin wrappers so control.lua doesn't need to reach into `destroy` directly.
function M.destroy_machine(machine) destroy(machine) end
function M.destroy_account(cf) if cf.label and cf.label.valid then cf.label.destroy() end end
return M
