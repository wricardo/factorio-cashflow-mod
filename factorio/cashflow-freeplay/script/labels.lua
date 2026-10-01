local acc = require("script.accounting")
local layout = require("script.station_layout")
local M = {}

local function destroy(machine)
  if machine.label and machine.label.valid then machine.label.destroy() end
  for _, label in pairs(machine.port_labels or {}) do if label.valid then label.destroy() end end
  machine.label, machine.port_labels = nil, {}
end
local function title(role)
  if role == "vault" then return "Asset Warehouse" end
  return role:sub(1, 1):upper() .. role:sub(2)
end

local COLORS = {
  controller = { 1, 0.85, 0.4 },
  income = { 0.4, 1, 0.4 },
  expense = { 1, 0.5, 0.3 },
  cashflow = { 0.45, 0.8, 1 },
  debt = { 1, 0.4, 0.35 },
  vault = { 1, 0.85, 0.4 },
}

local function label_offset(role)
  if role == "cashflow" or role == "vault" then return { 0, -3.4 } end
  return { 0, -1.8 }
end
local function port_offset(port)
  if port.x < 0 then return { -0.8, 0 }, "right" end
  if port.x > 0 then return { 0.8, 0 }, "left" end
  return { 0, -0.8 }, "center"
end
local function monthly_cashflow(cf)
  local income, expenses = 0, 0
  for _, machine in ipairs(cf.entities.income) do income = income + machine.config.monthly_cents end
  for _, machine in ipairs(cf.entities.expense) do expenses = expenses + machine.config.monthly_cents end
  return income - expenses
end
local function assets(cf)
  local cents = 0
  for _, vault in ipairs(cf.entities.vault or {}) do
    local inv = vault.anchor.valid and vault.anchor.get_inventory(defines.inventory.chest)
    cents = cents + (inv and inv.get_item_count("iron-plate") or 0) * acc.CENTS_PER_PLATE
  end
  return cents
end
function M.machine(machine)
  destroy(machine)
  if machine.anchor.valid then
    local detail = (machine.role == "income" or machine.role == "expense") and "\n" .. acc.money(machine.config.monthly_cents) .. "/month" or ""
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
function M.account(cf)
  if cf.label and cf.label.valid then cf.label.destroy() end
  if cf.controller.valid then
    local cashflow = monthly_cashflow(cf)
    local cashflow_text = (cashflow >= 0 and "+" or "") .. acc.money(cashflow)
    cf.label = rendering.draw_text {
      text = cf.name .. " • " .. (cf.running and "Running" or "Paused") .. "\nCashflow " .. cashflow_text .. "/month\nAssets " .. acc.money(assets(cf)) .. " • Debt " .. acc.money(cf.debt_cents),
      surface = cf.controller.surface, target = cf.controller, target_offset = { 0, -2.5 }, alignment = "center",
      color = cf.running and { 0.4, 1, 0.4 } or { 1, 1, 1 },
    }
  end
end
function M.destroy_machine(machine) destroy(machine) end
function M.destroy_account(cf) if cf.label and cf.label.valid then cf.label.destroy() end end
return M
