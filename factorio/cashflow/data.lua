-- Station entities are copies of vanilla ones that the player cannot mine, upgrade or fast-replace.
local function locked_copy(proto_type, source, name, overrides)
  local p = table.deepcopy(data.raw[proto_type][source])
  p.name = name
  p.minable = nil
  p.next_upgrade = nil
  p.fast_replaceable_group = nil
  p.hidden = true
  for k, v in pairs(overrides or {}) do
    p[k] = v
  end
  return p
end

local meter = table.deepcopy(data.raw["transport-belt"]["transport-belt"])
meter.name = "cf-meter-belt"
meter.minable = { mining_time = 0.1, result = "cf-meter-belt" }
meter.next_upgrade = nil

local meter_item = table.deepcopy(data.raw["item"]["transport-belt"])
meter_item.name = "cf-meter-belt"
meter_item.place_result = "cf-meter-belt"
meter_item.stack_size = 10
meter_item.order = "a[transport-belt]-z[cf-meter-belt]"

data:extend({
  locked_copy("transport-belt", "transport-belt", "cf-belt"),
  locked_copy("splitter", "splitter", "cf-splitter"),
  locked_copy("container", "iron-chest", "cf-landmark", { inventory_size = 1 }),
  locked_copy("container", "iron-chest", "cf-ledger", { inventory_size = 1000 }),
  locked_copy("container", "steel-chest", "cf-vault", { inventory_size = 2000 }),
  locked_copy("container", "steel-chest", "cf-facade", { inventory_size = 1, operable = false }),
  meter,
  meter_item,
})
