-- Data stage: declares the eight placeable cf-freeplay-* stations plus their hidden/locked
-- helper belt/splitter/chest prototypes. The five storage stations are Warehousing-derived
-- art, the controller is Sosciencity's Computing Center (see THIRD_PARTY_LICENSES.md), and the
-- Smelter/Coal Supply reuse vanilla electric-furnace/electric-mining-drill art unmodified;
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
-- income/expense/debt/smelter/coal, 6x6 Warehouse for cashflow/vault (its belt ports need room).
local STOREHOUSE = { collision = 1.2, selection = 1.5, scale = 0.4, width = 256, height = 256, shadow = "storehouse-shadow.png", shadow_shift = { 0, 0 } }
local WAREHOUSE = { collision = 2.7, selection = 3.0, scale = 0.38, width = 520, height = 480, shadow = "warehouse-shadow.png", shadow_shift = { 0.76, 0 } }
-- Smelter: the vanilla electric furnace's static base layers (its working glow becomes the
-- cf-freeplay-smelter-heater animation below, drawn by script only while a batch smelts).
local furnace = data.raw.furnace["electric-furnace"]
-- Coal Supply: first frame of the vanilla electric mining drill facing north (body, output
-- chute, shadow); `x`/`y` default to 0, which selects frame 1 of each sheet.
local DRILL = "__base__/graphics/entity/electric-mining-drill/electric-mining-drill-N"
local drill_picture = { layers = {
  { filename = DRILL .. ".png", width = 190, height = 208, shift = { 0, -4 / 32 }, scale = 0.5 },
  { filename = DRILL .. "-output.png", width = 60, height = 66, shift = { -3 / 32, -44 / 32 }, scale = 0.5 },
  { filename = DRILL .. "-shadow.png", width = 212, height = 204, shift = { 6 / 32, -3 / 32 }, scale = 0.5, draw_as_shadow = true },
} }
-- Every station has its own 64px inventory icon. Seven original station assets in
-- graphics/icons/ share a compact, top-down industrial visual language; the Controller retains
-- its licensed Computing Center icon. No badge layering or vanilla item icon is reused.
local ICONS = "__cashflow-freeplay__/graphics/icons/"
local function station_icon(role) return { { icon = ICONS .. role .. ".png", icon_size = 64 } } end
-- Crafting-menu row for all eight Cashflow items, right after vanilla Storage ("a").
local SUBGROUP = { type = "item-subgroup", name = "cf-freeplay-stations", group = "logistics", order = "a[cashflow-freeplay]" }
-- `inventory_size` defaults to 2000 slots. The Smelter holds exactly one month's coal batch
-- (one 50-coal stack); Coal Supply holds 20 stacks, refilled by control.lua.
local STATIONS = {
  income = { art = "storehouse-passive-provider.png", spec = STOREHOUSE, icons = station_icon("income") },
  expense = { art = "storehouse-requester.png", spec = STOREHOUSE, icons = station_icon("expense") },
  cashflow = { art = "warehouse-storage.png", spec = WAREHOUSE, icons = station_icon("cashflow") },
  debt = { art = "storehouse-active-provider.png", spec = STOREHOUSE, icons = station_icon("debt") },
  vault = { art = "warehouse-basic.png", spec = WAREHOUSE, icons = station_icon("vault") },
  smelter = { picture = table.deepcopy(furnace.graphics_set.animation), icons = station_icon("smelter"), spec = STOREHOUSE, inventory_size = 1 },
  coal = { picture = drill_picture, icons = station_icon("coal"), spec = STOREHOUSE, inventory_size = 20 },
}

-- Builds one station's placeable entity/item/recipe triplet from a vanilla container/chest,
-- re-skinned with Warehousing art (or a vanilla `picture`) and sized per STATIONS[role].
-- Recipe cost is fixed at 10 iron plates regardless of role; the "z[cashflow-freeplay]-N"
-- order keeps stations in a fixed sequence within their own SUBGROUP row.
local function anchor(name, source, order, role)
  local entity = table.deepcopy(data.raw["container"][source])
  entity.name = name
  entity.minable = { mining_time = 0.2, result = name }
  local station = STATIONS[role]
  entity.inventory_size = station.inventory_size or 2000
  if station.inventory_size then entity.quality_affects_inventory_size = false end
  entity.next_upgrade = nil
  entity.fast_replaceable_group = nil
  entity.allow_copy_paste = false
  entity.rotatable = false
  entity.corpse = "small-remnants"
  entity.order = order
  entity.localised_name = { "entity-name." .. name }
  entity.picture = station.picture or picture(station.art, station.spec.shadow, station.spec.width, station.spec.height, station.spec.scale, station.spec.shadow_shift)
  entity.collision_box = { { -station.spec.collision, -station.spec.collision }, { station.spec.collision, station.spec.collision } }
  entity.selection_box = { { -station.spec.selection, -station.spec.selection }, { station.spec.selection, station.spec.selection } }

  local item = table.deepcopy(data.raw.item["iron-chest"])
  item.name = name
  item.place_result = name
  item.order, item.subgroup = order, SUBGROUP.name
  item.localised_name = { "item-name." .. name }
  entity.icon, entity.icons, item.icon, item.icons = nil, station.icons, nil, table.deepcopy(station.icons)

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
  item.name, item.place_result, item.order, item.subgroup = name, name, order, SUBGROUP.name
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
  SUBGROUP,
  locked_copy("transport-belt", belt_source, "cf-freeplay-belt"),
  locked_copy("splitter", splitter_source, "cf-freeplay-splitter"),
  locked_copy("container", "iron-chest", "cf-freeplay-landmark", { inventory_size = 1 }),
  locked_copy("container", "iron-chest", "cf-freeplay-ledger", { inventory_size = 1000 }),
  locked_copy("container", "steel-chest", "cf-freeplay-vault-chest", { inventory_size = 2000 }),
  locked_copy("container", "iron-chest", "cf-freeplay-legacy-controller", { inventory_size = 2000 }),
}
-- Smelter's 2-second working glow: the vanilla electric furnace heater + light layers.
local heater = table.deepcopy(furnace.graphics_set.working_visualisations[1].animation)
heater.type, heater.name = "animation", "cf-freeplay-smelter-heater"
prototypes[#prototypes + 1] = heater

do
  local entity, item, recipe = controller()
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end
-- One entity/item/recipe triplet per storage station role, built atop a vanilla chest
-- (steel-chest for the two 6x6 buildings, iron-chest for the 3x3 ones).
for index, role in ipairs({ "income", "expense", "cashflow", "debt", "vault", "smelter", "coal" }) do
  local source = (role == "cashflow" or role == "vault") and "steel-chest" or "iron-chest"
  local entity, item, recipe = anchor("cf-freeplay-" .. role, source, "z[cashflow-freeplay]-" .. (index + 1), role)
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end

-- Percent Splitter: a vanilla splitter (same size, belts, and art, tinted blue) whose output
-- priority control.lua drives on a 100-tick duty cycle, so the chosen share of items leaves the
-- left output. It links to no Account and needs no helper ports. Costs the vanilla splitter recipe.
do
  local name, order = "cf-freeplay-percent-splitter", "z[cashflow-freeplay]-9"
  local TINT = { 0.55, 0.85, 1 }
  -- Tints every non-shadow sprite layer under `node` (the splitter's own body, not its belts).
  local function tint_layers(node)
    if type(node) ~= "table" then return end
    if node.filename and not node.draw_as_shadow then node.tint = TINT end
    for _, child in pairs(node) do tint_layers(child) end
  end
  local vanilla_item = data.raw.item.splitter
  local entity = table.deepcopy(data.raw.splitter.splitter)
  entity.name = name
  entity.minable = { mining_time = 0.1, result = name }
  entity.fast_replaceable_group, entity.next_upgrade = nil, nil
  entity.order = order
  entity.localised_name = { "entity-name." .. name }
  tint_layers(entity.structure)
  tint_layers(entity.structure_patch)
  entity.icon, entity.icons = nil, { { icon = vanilla_item.icon, icon_size = vanilla_item.icon_size or 64, tint = TINT } }
  local item = table.deepcopy(vanilla_item)
  item.name, item.place_result, item.order, item.subgroup = name, name, order, SUBGROUP.name
  item.localised_name = { "item-name." .. name }
  item.icon, item.icons = nil, table.deepcopy(entity.icons)
  local recipe = {
    type = "recipe", name = name, enabled = true, energy_required = 1,
    ingredients = table.deepcopy(data.raw.recipe.splitter.ingredients),
    results = { { type = "item", name = name, amount = 1 } },
  }
  prototypes[#prototypes + 1] = entity
  prototypes[#prototypes + 1] = item
  prototypes[#prototypes + 1] = recipe
end

data:extend(prototypes)
