-- Floating rendering.draw_text labels above every station/controller and its helper ports.
-- Pure presentation: reads account/machine state but never mutates it.
local acc = require("script.accounting")
local layout = require("script.station_layout")
local M = {}

-- Destroys a machine's title label and every port label, resetting port_labels to empty.
local function destroy(machine)
  if machine.label and machine.label.valid then machine.label.destroy() end
  for _, label in pairs(machine.port_labels or {}) do if label.valid then label.destroy() end end
  machine.label, machine.port_labels = nil, {}
end
-- Display title for a role; "vault" stations are branded Asset Warehouse.
local function title(role)
  if role == "vault" then return "Asset Warehouse" end
  return role:sub(1, 1):upper() .. role:sub(2)
end
-- Per-role label tint.

local COLORS = {
  controller = { 1, 0.85, 0.4 },
  income = { 0.4, 1, 0.4 },
  expense = { 1, 0.5, 0.3 },
  cashflow = { 0.45, 0.8, 1 },
  debt = { 1, 0.4, 0.35 },
  vault = { 1, 0.85, 0.4 },
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
-- Extra detail lines for debt (balance + monthly interest) or vault (assets + monthly return)
-- stations; empty for every other role.
local function finance_detail(machine)
  if machine.role == "debt" then
    local debt = debt_cents(machine)
    return "\nDebt " .. acc.money(debt) .. "\nInterest " .. acc.money(acc.monthly_amount(debt, machine.config.apr)) .. "/month"
  end
  if machine.role == "vault" then
    local held = vault_cents(machine)
    return "\nAssets " .. acc.money(held) .. "\nReturn " .. acc.money(acc.monthly_amount(held, machine.config.asset_return)) .. "/month"
  end
  return ""
end
-- (Re)draws a machine's title label and any labeled helper-port labels. Income/expense show
-- their fixed monthly amount; debt/vault show live balance + projected interest/return.
function M.machine(machine)
  destroy(machine)
  if machine.anchor.valid then
    local detail = (machine.role == "income" or machine.role == "expense") and "\n" .. acc.money(machine.config.monthly_cents) .. "/month" or finance_detail(machine)
    machine.label = rendering.draw_text { text = title(machine.role) .. detail, surface = machine.anchor.surface, target = machine.anchor, target_offset = label_offset(machine.role), alignment = "center", color = COLORS[machine.role] }
    for _, port in ipairs(layout.roles[machine.role].helpers) do
      local entity = machine.entities[port.key]
      if port.label and entity and entity.valid then
        local offset, alignment = port_offset(port)
        machine.port_labels[port.key] = rendering.draw_text {
          text = port.label, surface = entity.surface, target = entity, target_offset = offset, alignment = alignment,
          color = port.output and { 0.4, 1, 0.4 } or { 1, 0.5, 0.3 },
        }
      end
    end
  end
end
-- (Re)draws a controller's status label: name, running state, monthly cashflow, total assets
-- and debt across every linked station.
function M.account(cf)
  if cf.label and cf.label.valid then cf.label.destroy() end
  if cf.controller.valid then
    local cashflow = monthly_cashflow(cf)
    local cashflow_text = (cashflow >= 0 and "+" or "") .. acc.money(cashflow)
    local year, month = acc.calendar(cf.month)
    cf.label = rendering.draw_text {
      text = cf.name .. " • " .. (cf.running and "Running" or "Paused") .. " • Year " .. year .. " Month " .. month .. "\nCashflow " .. cashflow_text .. "/month\nAssets " .. acc.money(assets(cf)) .. " • Debt " .. acc.money(cf.debt_cents),
      surface = cf.controller.surface, target = cf.controller, target_offset = { 0, -2.5 }, alignment = "center",
      color = cf.running and { 0.4, 1, 0.4 } or { 1, 1, 1 },
    }
  end
end
-- Thin wrappers so control.lua doesn't need to reach into `destroy` directly.
function M.destroy_machine(machine) destroy(machine) end
function M.destroy_account(cf) if cf.label and cf.label.valid then cf.label.destroy() end end
return M
