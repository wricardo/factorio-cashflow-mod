local M = {}
local IRON, PAYLOAD = "iron-plate", "cashflow-rocket-payload"
local FIRST_TARGET, GROWTH = 100000, 1.04

function M.target(launches) return math.ceil(FIRST_TARGET * GROWTH ^ (launches or 0)) end

local function inventory(entity) return entity and entity.valid and entity.get_inventory(defines.inventory.chest) or nil end

function M.refresh(record, state)
  if record.label and record.label.valid then record.label.destroy() end
  local target = M.target(state.rocket_launches)
  local funded = state.rocket_fund_plates or 0
  record.label = rendering.draw_text {
    text = "Rocket Fund\n" .. funded .. "/" .. target .. " iron ($" .. target * 10 .. ")",
    surface = record.entity.surface, target = record.entity, target_offset = { 0, -1.8 },
    alignment = "center", color = { 1, 0.85, 0.35 },
  }
end

function M.sweep(state)
  state.rocket_fund_plates = state.rocket_fund_plates or 0
  state.rocket_launches = state.rocket_launches or 0
  local target = M.target(state.rocket_launches)
  for unit, record in pairs(state.rocket_funds or {}) do
    local inv = inventory(record.entity)
    if not inv then state.rocket_funds[unit] = nil
    elseif inv.get_item_count(PAYLOAD) == 0 then
      local needed = target - state.rocket_fund_plates
      local paid = math.min(needed, inv.get_item_count(IRON))
      if paid > 0 then inv.remove({ name = IRON, count = paid }); state.rocket_fund_plates = state.rocket_fund_plates + paid end
      if state.rocket_fund_plates >= target then inv.insert({ name = PAYLOAD, count = 1 }) end
      M.refresh(record, state)
    end
  end
end

function M.launched(state, rocket)
  local inv = rocket and rocket.valid and rocket.get_inventory(defines.inventory.rocket)
  if not inv or inv.get_item_count(PAYLOAD) == 0 then return false end
  state.rocket_launches = (state.rocket_launches or 0) + 1
  state.rocket_fund_plates = 0
  return true
end

return M
