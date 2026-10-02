-- Anchor-relative helper belts sit outside each station's building footprint.
-- M.roles declares each role's helper ports (relative x/y offset from the anchor, port label,
-- and whether it's an output/input) so labels.lua and stations.lua can address them by key.
local M = {}

M.roles = {
  controller = { helpers = { { key = "landmark", name = "cashflow-landmark", x = 2, y = 0 } } },
  income = { helpers = { { key = "out", name = "cashflow-belt", x = 2, y = 0, label = "CASH OUT", cash = true, output = true } }, ports = { "out" } },
  expense = { helpers = { { key = "out", name = "cashflow-belt", x = 2, y = 0, label = "COPPER OUT", output = true } }, ports = { "out" } },
  smelter = { helpers = { { key = "out", name = "cashflow-belt", x = 2, y = 0, label = "CASH OUT", cash = true, output = true } }, ports = { "out" } },
  cashflow = { helpers = {
    { key = "cash_in", name = "cashflow-belt", x = -4, y = -2, label = "CASH IN", cash = true, output = false }, { key = "cash_in_2", name = "cashflow-belt", x = -4, y = -4, label = "CASH IN", cash = true, output = false },
    { key = "bills_in", name = "cashflow-belt", x = -4, y = 2, label = "BILLS IN", output = false }, { key = "bills_in_2", name = "cashflow-belt", x = -4, y = 4, label = "BILLS IN", output = false },
    { key = "surplus_out", name = "cashflow-belt", x = 4, y = -2, label = "SURPLUS OUT", cash = true, output = true }, { key = "unpaid_out", name = "cashflow-belt", x = 4, y = 2, label = "UNPAID OUT", copper = true, output = true },
  }, ports = { "cash_in", "cash_in_2", "bills_in", "bills_in_2", "surplus_out", "unpaid_out" } },
  debt = { helpers = {
    { key = "pay_in", name = "cashflow-belt", x = -2, y = -1, label = "PAY IN", cash = true, output = false }, { key = "borrow_in", name = "cashflow-belt", x = -2, y = 1, label = "BORROW IN", output = false },
    { key = "interest_out", name = "cashflow-belt", x = 2, y = 0, label = "INTEREST OUT", copper = true, output = true },
  }, ports = { "pay_in", "borrow_in", "interest_out" } },
  vault = { helpers = {
    { key = "deposit_in", name = "cashflow-belt", x = -4, y = 0, label = "DEPOSIT IN", cash = true, output = false }, { key = "return_out", name = "cashflow-belt", x = 4, y = 0, label = "RETURN OUT", cash = true, output = true },
  }, ports = { "deposit_in", "return_out" } },
}

local EAST = defines.direction.east
-- Creates every helper-port entity for `role` around `anchor` (hidden/locked belts, see
-- data.lua's locked_copy). Rolls back and returns nil + a reason if any port doesn't fit.

function M.build(anchor, role)
  local entities, spec = {}, M.roles[role]
  for _, helper in ipairs(spec.helpers) do
    local entity = anchor.surface.create_entity { name = helper.name, position = { x = anchor.position.x + helper.x, y = anchor.position.y + helper.y }, direction = EAST, force = anchor.force }
    if not entity then
      for _, made in pairs(entities) do if made.valid then made.destroy() end end
      return nil, "Not enough room for station ports."
    end
    entity.minable = false
    entity.operable = false
    entity.rotatable = false
    entities[helper.key] = entity
  end
  return entities
end

-- Re-assert EAST direction on every helper belt. Called from control.lua's normalize_layouts.
function M.normalize(machine)
  M.ensure_ports(machine)
  for _, entity in pairs(machine.entities or {}) do
    if entity.valid and entity.name == "cashflow-belt" then entity.direction = EAST end
  end
end
-- Creates any helper-port entity declared in M.roles[machine.role] that machine.entities is
-- still missing (e.g. a second cash/bills line added by a mod update). Best-effort: silently
-- skips a port if there's no room, same as a fresh M.build would reject the whole station.
function M.ensure_ports(machine)
  local spec = machine.anchor and machine.anchor.valid and M.roles[machine.role]
  if not spec then return end
  for _, helper in ipairs(spec.helpers) do
    local existing = machine.entities[helper.key]
    if not (existing and existing.valid) then
      local entity = machine.anchor.surface.create_entity { name = helper.name, position = { x = machine.anchor.position.x + helper.x, y = machine.anchor.position.y + helper.y }, direction = EAST, force = machine.anchor.force }
      if entity then
        entity.minable = false
        entity.operable = false
        entity.rotatable = false
        machine.entities[helper.key] = entity
      end
    end
  end
end

-- Destroys every helper-port entity owned by `machine` (called when its anchor is removed).
function M.destroy(machine)
  for _, entity in pairs(machine.entities or {}) do if entity.valid then entity.destroy() end end
end

return M
