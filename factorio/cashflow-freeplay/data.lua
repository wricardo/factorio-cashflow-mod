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

-- Warehousing artwork by David-John Miller (Anoyomouse), used with permission.
-- Full MIT notice: THIRD_PARTY_LICENSES.md.
local function picture(filename, shadow, width, height, scale, shadow_shift)
  return {
    layers = {
      {
        filename = "__cashflow-freeplay__/graphics/warehouse/" .. filename,
        width = width,
        height = height,
        scale = scale,
      },
      {
        filename = "__cashflow-freeplay__/graphics/warehouse/" .. shadow,
        width = width,
        height = height,
        shift = shadow_shift,
        scale = scale,
        draw_as_shadow = true,
      },
    },
  }
end

local STOREHOUSE = { collision = 1.2, selection = 1.5, scale = 0.4, width = 256, height = 256, shadow = "storehouse-shadow.png", shadow_shift = { 0, 0 } }
local WAREHOUSE = { collision = 2.7, selection = 3.0, scale = 0.38, width = 520, height = 480, shadow = "warehouse-shadow.png", shadow_shift = { 0.76, 0 } }
local STATIONS = {
  controller = { art = "storehouse-basic.png", spec = STOREHOUSE },
  income = { art = "storehouse-passive-provider.png", spec = STOREHOUSE },
  expense = { art = "storehouse-requester.png", spec = STOREHOUSE },
  cashflow = { art = "warehouse-storage.png", spec = WAREHOUSE },
  debt = { art = "storehouse-active-provider.png", spec = STOREHOUSE },
  vault = { art = "warehouse-basic.png", spec = WAREHOUSE },
}

local function anchor(name, source, order, role)
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
  local station = STATIONS[role]
  entity.picture = picture(station.art, station.spec.shadow, station.spec.width, station.spec.height, station.spec.scale, station.spec.shadow_shift)
  entity.collision_box = { { -station.spec.collision, -station.spec.collision }, { station.spec.collision, station.spec.collision } }
  entity.selection_box = { { -station.spec.selection, -station.spec.selection }, { station.spec.selection, station.spec.selection } }

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
  local source = (role == "cashflow" or role == "vault") and "steel-chest" or "iron-chest"
  local entity, item, recipe = anchor("cf-freeplay-" .. role, source, "z[cashflow-freeplay]-" .. index, role)
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end

data:extend(prototypes)
