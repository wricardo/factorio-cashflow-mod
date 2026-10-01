local function locked_copy(proto_type, source, name, overrides)
  local p = table.deepcopy(data.raw[proto_type][source])
  p.name = name
  p.minable = nil
  p.next_upgrade = nil
  p.fast_replaceable_group = nil
  p.hidden = true
  p.selectable_in_game = false
  for k, v in pairs(overrides or {}) do p[k] = v end
  return p
end

local function anchor(name, source, order)
  local entity = table.deepcopy(data.raw["container"][source])
  entity.name = name
  entity.minable = { mining_time = 0.2, result = name }
  entity.inventory_size = 2000
  entity.next_upgrade = nil
  entity.fast_replaceable_group = nil
  entity.allow_copy_paste = false
  entity.rotatable = false
  entity.corpse = "small-remnants"
  entity.order = order
  entity.localised_name = { "entity-name." .. name }

  local item = table.deepcopy(data.raw.item["iron-chest"])
  item.name = name
  item.place_result = name
  item.order = order
  item.localised_name = { "item-name." .. name }

  local recipe = {
    type = "recipe", name = name, enabled = true,
    ingredients = { { type = "item", name = "iron-plate", amount = 10 } },
    results = { { type = "item", name = name, amount = 1 } },
  }
  return entity, item, recipe
end

local belt_source = data.raw["transport-belt"]["turbo-transport-belt"] and "turbo-transport-belt" or "express-transport-belt"
local splitter_source = data.raw.splitter["turbo-splitter"] and "turbo-splitter" or "express-splitter"

local prototypes = {
  locked_copy("transport-belt", belt_source, "cf-freeplay-belt"),
  locked_copy("splitter", splitter_source, "cf-freeplay-splitter"),
  locked_copy("container", "iron-chest", "cf-freeplay-landmark", { inventory_size = 1 }),
  locked_copy("container", "iron-chest", "cf-freeplay-ledger", { inventory_size = 1000 }),
  locked_copy("container", "steel-chest", "cf-freeplay-vault-chest", { inventory_size = 2000 }),
}

for index, role in ipairs({ "controller", "income", "expense", "cashflow", "debt", "vault" }) do
  local entity, item, recipe = anchor("cf-freeplay-" .. role, role == "vault" and "steel-chest" or "iron-chest", "z[cashflow-freeplay]-" .. index)
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end

data:extend(prototypes)
