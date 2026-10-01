-- Anchor-relative helper belts sit outside each station's building footprint.
local M = {}

M.roles = {
  controller = { helpers = { { key = "landmark", name = "cf-freeplay-landmark", x = 2, y = 0 } } },
  income = { helpers = { { key = "out", name = "cf-freeplay-belt", x = 2, y = 0, label = "IRON OUT", output = true } }, ports = { "out" } },
  expense = { helpers = { { key = "out", name = "cf-freeplay-belt", x = 2, y = 0, label = "COPPER OUT", output = true } }, ports = { "out" } },
  cashflow = { helpers = {
    { key = "cash_in", name = "cf-freeplay-belt", x = -4, y = -2, label = "CASH IN", output = false }, { key = "bills_in", name = "cf-freeplay-belt", x = -4, y = 2, label = "BILLS IN", output = false },
    { key = "surplus_out", name = "cf-freeplay-belt", x = 4, y = -2, label = "SURPLUS OUT", output = true }, { key = "unpaid_out", name = "cf-freeplay-belt", x = 4, y = 2, label = "UNPAID OUT", output = true },
  }, ports = { "cash_in", "bills_in", "surplus_out", "unpaid_out" } },
  debt = { helpers = {
    { key = "borrow_in", name = "cf-freeplay-belt", x = -2, y = -1, label = "BORROW IN", output = false }, { key = "pay_in", name = "cf-freeplay-belt", x = -2, y = 1, label = "PAY IN", output = false },
    { key = "interest_out", name = "cf-freeplay-belt", x = 2, y = 0, label = "INTEREST OUT", output = true },
  }, ports = { "borrow_in", "pay_in", "interest_out" } },
  vault = { helpers = {
    { key = "deposit_in", name = "cf-freeplay-belt", x = -4, y = 0, label = "DEPOSIT IN", output = false }, { key = "return_out", name = "cf-freeplay-belt", x = 4, y = 0, label = "RETURN OUT", output = true },
  }, ports = { "deposit_in", "return_out" } },
}

local EAST = defines.direction.east

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

local function migrate_legacy_buffer(machine, key, item)
  local legacy = machine.entities and machine.entities[key]
  if not (legacy and legacy.valid and machine.anchor and machine.anchor.valid) then return end
  local source = legacy.get_inventory(defines.inventory.chest)
  local target = machine.anchor.get_inventory(defines.inventory.chest)
  local count = source.get_item_count(item)
  if count > 0 then
    local moved = target.insert({ name = item, count = count })
    if moved > 0 then source.remove({ name = item, count = moved }) end
  end
  if source.get_item_count(item) == 0 then legacy.destroy(); machine.entities[key] = nil end
end
function M.normalize(machine)
  migrate_legacy_buffer(machine, "landmark", "copper-plate")
  migrate_legacy_buffer(machine, "chest", "iron-plate")
  for _, entity in pairs(machine.entities or {}) do
    if entity.valid and entity.name == "cf-freeplay-belt" then entity.direction = EAST end
  end
end

function M.destroy(machine)
  for _, entity in pairs(machine.entities or {}) do if entity.valid then entity.destroy() end end
end

return M
