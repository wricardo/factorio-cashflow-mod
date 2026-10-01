local layout = require("script.layout")

local M = {}

local CLEAR_TYPES = { "tree", "simple-entity", "resource", "unit-spawner", "turret", "unit", "cliff", "fish" }

function M.clean_area(surface, area)
  local tiles = {}
  for x = area.left_top.x, area.right_bottom.x - 1 do
    for y = area.left_top.y, area.right_bottom.y - 1 do
      local dark = (math.floor(x) + math.floor(y)) % 2 == 0
      tiles[#tiles + 1] = { name = dark and "lab-dark-1" or "lab-dark-2", position = { x, y } }
    end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered({ area = area, type = CLEAR_TYPES })) do
    e.destroy()
  end
  surface.destroy_decoratives({ area = area })
end

local function place(surface, name, x, y, direction)
  local e = surface.create_entity({ name = name, position = { x, y }, direction = direction, force = "player" })
  e.destructible = false
  e.operable = false
  e.rotatable = false
  return e
end

local function belt(surface, tx, ty)
  return place(surface, "cf-belt", tx + 0.5, ty + 0.5, defines.direction.east)
end

local function chest(surface, name, tx, ty)
  return place(surface, name, tx + 0.5, ty + 0.5)
end

local function facade_span(surface, tx, ty, length)
  for x = tx, tx + length - 1 do
    chest(surface, "cf-facade", x, ty)
  end
end

local function add_tile(tiles, name, x, y)
  tiles[#tiles + 1] = { name = name, position = { x = x, y = y } }
end

local function fill(tiles, name, left, top, right, bottom)
  for x = left, right do
    for y = top, bottom do
      add_tile(tiles, name, x, y)
    end
  end
end

local function hazard_lane(tiles, left, right, y)
  for x = left, right do
    local name = ((x - left) % 2 == 0) and "hazard-concrete-left" or "hazard-concrete-right"
    add_tile(tiles, name, x, y)
  end
end

-- Vanilla concrete keeps the financial district readable without shipping third-party art.
-- Hazard lanes mark liabilities; refined pads mark durable assets and the central ledger.
local function decorate_financial_district(surface)
  local tiles = {}
  fill(tiles, "concrete", -52, -18, 14, 18)
  fill(tiles, "refined-concrete", -31, 9, -15, 17)
  hazard_lane(tiles, -46, -18, -4)
  hazard_lane(tiles, -46, -18, 4)
  hazard_lane(tiles, 0, 7, -14)
  surface.set_tiles(tiles, true, false, false)
end

-- Three belts ending at (tx+2, ty). The script removes plates from the last one.
local function sink(surface, tx, ty)
  belt(surface, tx, ty)
  belt(surface, tx + 1, ty)
  return belt(surface, tx + 2, ty)
end

-- Three belts starting at (tx, ty). The script places plates at the back of the first one.
local function source(surface, tx, ty)
  local first = belt(surface, tx, ty)
  belt(surface, tx + 1, ty)
  belt(surface, tx + 2, ty)
  return first
end

-- Input at (tx, ty); a splitter sends plates to the drain end at (tx+5, ty+1) first and
-- everything else out at (tx+5, ty) once the drain stops taking plates and backs up.
local function sink_with_pass(surface, tx, ty)
  belt(surface, tx, ty)
  belt(surface, tx + 1, ty)
  local splitter = place(surface, "cf-splitter", tx + 2.5, ty + 1, defines.direction.east)
  splitter.splitter_output_priority = "right"
  belt(surface, tx + 3, ty)
  belt(surface, tx + 4, ty)
  belt(surface, tx + 3, ty + 1)
  belt(surface, tx + 4, ty + 1)
  return belt(surface, tx + 5, ty + 1), splitter
end

local builders = {}

function builders.emitter(surface, s)
  return {
    landmark = chest(surface, "cf-landmark", s.x, s.y),
    out = source(surface, s.x + 1, s.y),
    ports = { { s.x + 4, s.y, "OUT >" } },
  }
end

function builders.cashflow(surface, s)
  local x, y = s.x, s.y
  local station = {
    cash_in = sink(surface, x, y),
    bills_in = sink(surface, x, y + 2),
    landmark = chest(surface, "cf-landmark", x + 3, y + 1),
    surplus_out = source(surface, x + 4, y),
    unpaid_out = source(surface, x + 4, y + 2),
    ports = {
      { x, y, "CASH IN >" },
      { x, y + 2, "BILLS IN >" },
      { x + 7, y, "SURPLUS OUT >" },
      { x + 7, y + 2, "UNPAID OUT >" },
    },
  }
  facade_span(surface, x, y + 1, 3)
  facade_span(surface, x + 4, y + 1, 4)
  return station
end

function builders.debt(surface, s)
  local x, y = s.x, s.y
  local pay_in, splitter = sink_with_pass(surface, x, y + 2)
  local station = {
    borrow_in = sink(surface, x, y),
    landmark = chest(surface, "cf-ledger", x + 3, y),
    interest_out = source(surface, x + 4, y),
    pay_in = pay_in,
    splitter = splitter,
    ports = {
      { x, y, "BORROW IN >" },
      { x + 7, y, "INTEREST OUT >" },
      { x, y + 2, "PAY IN >" },
      { x + 5, y + 2, "PASS OUT >" },
    },
  }
  facade_span(surface, x, y - 1, 8)
  return station
end

function builders.vault(surface, s)
  local x, y = s.x, s.y
  local vault = {
    deposit_in = sink(surface, x, y),
    return_out = source(surface, x + 4, y),
    ports = { { x, y, "DEPOSIT IN >" }, { x + 7, y, "RETURNS OUT >" } },
  }
  vault.chest = chest(surface, "cf-vault", x + 3, y)
  -- Keep the real vault beside the belt. The large licensed facade sits beyond
  -- the output port, leaving every prebuilt belt cell unobstructed.
  vault.landmark = chest(surface, "cf-warehouse-facade", x + 11, y)
  facade_span(surface, x, y - 1, 8)
  facade_span(surface, x, y + 1, 8)
  return vault
end

function M.create_surface()
  local surface = game.surfaces[layout.surface] or game.create_surface(layout.surface)
  surface.always_day = true
  surface.request_to_generate_chunks({ 0, 0 }, 3)
  surface.force_generate_chunk_requests()
  M.clean_area(surface, { left_top = { x = -96, y = -96 }, right_bottom = { x = 96, y = 96 } })
  decorate_financial_district(surface)
  return surface
end

function M.build_stations(surface)
  local entities = {}
  for _, s in ipairs(layout.stations) do
    entities[s.key] = builders[s.kind](surface, s)
  end
  return entities
end

return M
