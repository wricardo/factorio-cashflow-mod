-- Cashflow Freeplay permits the logistics and construction infrastructure needed to wire accounts.
-- Production, mining, power generation, combat, vehicles, and rail remain disabled.
local M = {}

local allowed = {
  ["cf-freeplay-controller"] = true, ["cf-freeplay-income"] = true, ["cf-freeplay-expense"] = true,
  ["cf-freeplay-cashflow"] = true, ["cf-freeplay-debt"] = true, ["cf-freeplay-vault"] = true,
  ["transport-belt"] = true, ["fast-transport-belt"] = true, ["express-transport-belt"] = true, ["turbo-transport-belt"] = true,
  ["underground-belt"] = true, ["fast-underground-belt"] = true, ["express-underground-belt"] = true, ["turbo-underground-belt"] = true,
  ["splitter"] = true, ["fast-splitter"] = true, ["express-splitter"] = true, ["turbo-splitter"] = true,
  ["burner-inserter"] = true, ["inserter"] = true, ["long-handed-inserter"] = true, ["fast-inserter"] = true,
  ["bulk-inserter"] = true, ["stack-inserter"] = true, ["stack-filter-inserter"] = true, ["filter-inserter"] = true,
  ["wooden-chest"] = true, ["iron-chest"] = true, ["steel-chest"] = true,
  ["logistic-chest-active-provider"] = true, ["logistic-chest-passive-provider"] = true,
  ["logistic-chest-storage"] = true, ["logistic-chest-buffer"] = true, ["logistic-chest-requester"] = true,
  ["small-electric-pole"] = true, ["medium-electric-pole"] = true, ["big-electric-pole"] = true, ["substation"] = true,
  ["roboport"] = true, ["construction-robot"] = true, ["logistic-robot"] = true,
  ["electric-energy-interface"] = true,
}

local function prototype_name(entity)
  if entity.name == "entity-ghost" then return entity.ghost_name end
  return entity.name
end

function M.is_allowed_name(name) return allowed[name] == true end
function M.allow_entity(entity)
  return entity and entity.valid and M.is_allowed_name(prototype_name(entity))
end

local function disabled_recipe(recipe)
  for _, product in ipairs(recipe.products or {}) do
    if product.type == "item" then
      local item = prototypes.item[product.name]
      if item and item.place_result and not M.is_allowed_name(product.name) then return true end
    end
  end
  return false
end

function M.apply(force)
  for _, recipe in pairs(force.recipes) do
    if disabled_recipe(recipe) then recipe.enabled = false end
  end
end

function M.apply_all()
  for _, force in pairs(game.forces) do M.apply(force) end
end

function M.reject(event, entity)
  if not entity or not entity.valid or M.allow_entity(entity) then return false end
  if entity.name == "entity-ghost" then
    entity.destroy({ raise_destroy = false })
    return true
  end
  local name, position, surface, force = entity.name, entity.position, entity.surface, entity.force
  local player = event.player_index and game.get_player(event.player_index)
  local remaining = 1
  if player and player.valid then
    remaining = remaining - player.get_main_inventory().insert({ name = name, count = remaining })
    player.print("This Freeplay sandbox only allows Cashflow logistics and construction infrastructure.")
  end
  if remaining > 0 then surface.spill_item_stack(position, { name = name, count = remaining }, true, force) end
  entity.destroy({ raise_destroy = false })
  return true
end

return M
