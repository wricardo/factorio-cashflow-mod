-- Data stage: declares the six placeable cf-freeplay-* stations plus their hidden/locked
-- helper belt/splitter/chest prototypes. The five storage stations are Warehousing-derived
-- art and the controller is Sosciencity's Computing Center (see THIRD_PARTY_LICENSES.md);
-- hidden helpers reuse vanilla belt/chest graphics unmodified.
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
-- Copies `source` prototype as a hidden, unselectable, non-upgradeable helper entity (the
-- port belts/splitter/buffers station_layout.lua places around each station's footprint).

-- Warehousing artwork by David-John Miller (Anoyomouse), used with permission.
-- Full MIT notice: THIRD_PARTY_LICENSES.md.
-- Builds a station's two-layer (sprite + shadow) picture from one of the Warehousing sheets.
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

-- Per-building-size collision/selection boxes and shadow metrics: 3x3 Storehouse for
-- income/expense/debt, 6x6 Warehouse for cashflow/vault (its belt ports need room).
local STOREHOUSE = { collision = 1.2, selection = 1.5, scale = 0.4, width = 256, height = 256, shadow = "storehouse-shadow.png", shadow_shift = { 0, 0 } }
local WAREHOUSE = { collision = 2.7, selection = 3.0, scale = 0.38, width = 520, height = 480, shadow = "warehouse-shadow.png", shadow_shift = { 0.76, 0 } }
local STATIONS = {
  income = { art = "storehouse-passive-provider.png", spec = STOREHOUSE },
  expense = { art = "storehouse-requester.png", spec = STOREHOUSE },
  cashflow = { art = "warehouse-storage.png", spec = WAREHOUSE },
  debt = { art = "storehouse-active-provider.png", spec = STOREHOUSE },
  vault = { art = "warehouse-basic.png", spec = WAREHOUSE },
}

-- Builds one station's placeable entity/item/recipe triplet from a vanilla container/chest,
-- re-skinned with Warehousing art and sized per STATIONS[role]. Recipe cost is fixed at
-- 10 iron plates regardless of role; the "z[cashflow-freeplay]-N" order keeps stations
-- grouped together, after vanilla items, in the crafting menu.
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

-- Prefer turbo-tier belt/splitter art if the Factorio version/mod set provides it, else
-- fall back to express-tier (both versions ship the same sprite at the port's draw scale).
local belt_source = data.raw["transport-belt"]["turbo-transport-belt"] and "turbo-transport-belt" or "express-transport-belt"
local splitter_source = data.raw.splitter["turbo-splitter"] and "turbo-splitter" or "express-splitter"

-- Cashflow Controller: a 3x3 `market` (no inventory, still opens via on_gui_opened; control.lua
-- closes the empty vanilla market window and shows the account panel instead).
-- Computing Center art from Sosciencity by tirisabella, Johanna Spieker and _traum, CC BY 4.0;
-- see THIRD_PARTY_LICENSES.md. Sosciencity draws it as a 5x5 building at scale 0.5 with shift
-- {0.5, -0.2}; both are multiplied by 3/5 here for the 3x3 footprint.
local CONTROLLER_ART = "__cashflow-freeplay__/graphics/computing-center/computing-center"
local function controller_layer(suffix, flag)
  local layer = { filename = CONTROLLER_ART .. suffix .. ".png", width = 640, height = 448, shift = { 0.3, -0.12 }, scale = 0.3 }
  if flag then layer[flag] = true end
  return layer
end
local function controller()
  local name, order = "cf-freeplay-controller", "z[cashflow-freeplay]-1"
  local icon = CONTROLLER_ART .. "-icon.png"
  local entity = {
    type = "market", name = name, icon = icon, icon_size = 64,
    flags = { "placeable-player", "player-creation" },
    minable = { mining_time = 0.2, result = name },
    max_health = 150, corpse = "small-remnants", order = order,
    allow_access_to_all_forces = false,
    collision_box = { { -1.2, -1.2 }, { 1.2, 1.2 } },
    selection_box = { { -1.5, -1.5 }, { 1.5, 1.5 } },
    localised_name = { "entity-name." .. name },
    picture = { layers = {
      controller_layer(""),
      controller_layer("-shadowmap", "draw_as_shadow"),
      controller_layer("-lightmap", "draw_as_light"),
      controller_layer("-glow", "draw_as_glow"),
    } },
  }
  local item = table.deepcopy(data.raw.item["iron-chest"])
  item.name, item.place_result, item.order = name, name, order
  item.icon, item.icon_size, item.icons = icon, 64, nil
  item.localised_name = { "item-name." .. name }
  local recipe = {
    type = "recipe", name = name, enabled = true,
    ingredients = { { type = "item", name = "iron-plate", amount = 10 } },
    results = { { type = "item", name = name, amount = 1 } },
  }
  return entity, item, recipe
end

-- Hidden helper prototypes: hub belt + splitter for station ports, three legacy/compat buffer
-- chests (landmark/ledger/vault-chest) retained for save migration in station_layout.lua, and
-- the pre-0.2.23 chest controller, which migrations/cashflow-freeplay_0.2.23.json renames to
-- cf-freeplay-legacy-controller so control.lua can swap it for the new controller in place.
local prototypes = {
  locked_copy("transport-belt", belt_source, "cf-freeplay-belt"),
  locked_copy("splitter", splitter_source, "cf-freeplay-splitter"),
  locked_copy("container", "iron-chest", "cf-freeplay-landmark", { inventory_size = 1 }),
  locked_copy("container", "iron-chest", "cf-freeplay-ledger", { inventory_size = 1000 }),
  locked_copy("container", "steel-chest", "cf-freeplay-vault-chest", { inventory_size = 2000 }),
  locked_copy("container", "iron-chest", "cf-freeplay-legacy-controller", { inventory_size = 2000 }),
}

do
  local entity, item, recipe = controller()
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end
-- One entity/item/recipe triplet per storage station role, built atop a vanilla chest
-- (steel-chest for the two 6x6 buildings, iron-chest for the three 3x3 ones).
for index, role in ipairs({ "income", "expense", "cashflow", "debt", "vault" }) do
  local source = (role == "cashflow" or role == "vault") and "steel-chest" or "iron-chest"
  local entity, item, recipe = anchor("cf-freeplay-" .. role, source, "z[cashflow-freeplay]-" .. (index + 1), role)
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end

data:extend(prototypes)
