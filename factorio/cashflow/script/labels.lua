local acc = require("script.accounting")
local layout = require("script.layout")

local M = {}

local WHITE = { r = 1, g = 1, b = 1 }
local GREEN = { r = 0.45, g = 0.9, b = 0.5 }
local RED = { r = 1, g = 0.55, b = 0.35 }
local GOLD = { r = 1, g = 0.85, b = 0.4 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }

local COLORS = { paycheck = GREEN, needs = RED, wants = RED, cashflow = GOLD, debt = RED, vault = GREEN }

local function text_at(surface, target, text, color, scale)
  return rendering.draw_text({
    text = text,
    surface = surface,
    target = target,
    color = color,
    scale = scale or 1.4,
    alignment = "center",
    vertical_alignment = "middle",
  })
end

local function on_entity(e, dy)
  return { entity = e, offset = { 0, dy } }
end

local function frame_station(surface, entity, color)
  local position = entity.position
  local x, y = position.x or position[1], position.y or position[2]
  rendering.draw_rectangle({
    color = color,
    width = 3,
    filled = false,
    left_top = { x - 4.5, y - 2.0 },
    right_bottom = { x + 4.5, y + 2.0 },
    surface = surface,
    draw_on_ground = true,
  })
end

function M.create(cf, surface)
  local ledger = layout.ledger
  cf.labels = {
    ledger_title = text_at(surface, { ledger.x, ledger.y }, "FINANCIAL LEDGER", GOLD, 1.8),
    ledger_status = text_at(surface, { ledger.x, ledger.y + 1.1 }, "", WHITE, 1.2),
    ledger_balances = text_at(surface, { ledger.x, ledger.y + 2.1 }, "", WHITE, 1.1),
    ledger_flow = text_at(surface, { ledger.x, ledger.y + 3.1 }, "", GREY, 1.0),
  }
  for key, s in pairs(cf.entities) do
    frame_station(surface, s.landmark, COLORS[key] or WHITE)
    cf.labels[key] = text_at(surface, on_entity(s.landmark, -1.4), "", COLORS[key] or WHITE)
    for _, port in ipairs(s.ports) do
      text_at(surface, { port[1] + 0.5, port[2] - 0.4 }, port[3], GREY, 0.9)
    end
  end
end

local function d(plates)
  return acc.money(plates * acc.CENTS_PER_PLATE)
end

-- Copper stuck in an output buffer is added to debt at month end.
local function overdue(plates)
  if plates <= 0 then
    return ""
  end
  return "  unbelted " .. d(plates) .. " -> debt at month end"
end

function M.refresh(cf, vault_plates)
  local L, p, out, node = cf.labels, cf.plan, cf.out, cf.node
  if not L then
    return
  end
  L.paycheck.text = "PAYCHECK cash " .. d(p.paycheck) .. "/mo" .. (out.paycheck > 0 and ("  waiting " .. d(out.paycheck)) or "")
  L.needs.text = "NEEDS bills " .. d(p.needs) .. "/mo" .. overdue(out.needs)
  L.wants.text = "WANTS bills " .. d(p.wants) .. "/mo" .. overdue(out.wants)
  L.cashflow.text = "CASHFLOW cash " .. d(node.iron) .. "  bills " .. d(node.copper) .. "  paid " .. d(cf.stats.paid) .. overdue(out.unpaid)
  L.debt.text = "DEBT " .. acc.money(cf.debt_cents) .. overdue(out.interest)
  L.vault.text = "VAULT " .. d(vault_plates) .. (out.returns > 0 and ("  returns waiting " .. d(out.returns)) or "")
  L.ledger_status.text = "MONTH " .. tostring(cf.month + 1) .. (cf.running and "  RUNNING" or "  READY — start simulation from the panel")
  L.ledger_balances.text = "CASHFLOW " .. d(node.iron) .. "  |  DEBT " .. acc.money(cf.debt_cents) .. "  |  VAULT " .. d(vault_plates)
  L.ledger_flow.text = "PAID " .. d(cf.stats.paid) .. "  |  BORROWED " .. d(cf.stats.borrowed) .. "  |  DEPOSITED " .. d(cf.stats.deposits)
  for _, m in pairs(cf.meters) do
    if m.entity.valid then
      local text = "METER cash " .. d(m.count.iron) .. " bills " .. d(m.count.copper) .. " (last month " .. d(m.last.iron) .. " / " .. d(m.last.copper) .. ")"
      if m.label and m.label.valid then
        m.label.text = text
      else
        m.label = text_at(m.entity.surface, on_entity(m.entity, -0.8), text, WHITE, 1.1)
      end
    end
  end
end

return M
