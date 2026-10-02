-- Left-side configuration panel (cf_freeplay_panel), opened from control.lua's on_gui_opened.
-- Exactly one panel is shown per player at a time; its `tags` identify whether it's bound to
-- a controller or a machine so control.lua's gui_* event handlers know where edits go.
local acc = require("script.accounting")
local M = {}
local ROOT = "cf_freeplay_panel"

-- The single persistent state table (shared with control.lua/account.lua/stations.lua).
local function state()
  return storage.cf_freeplay
end
local function player(event) return game.get_player(event.player_index) end
-- True when `record` (a controller or machine) is on the same surface/force as `p`.
local function valid_target(p, record)
  return record and record.surface_index == p.surface.index and record.force_index == p.force.index
end
-- Destroys the player's open panel, if any.
local function close(p)
  local root = p.gui.left[ROOT]
  if root then root.destroy() end
end
-- Adds a captioned textfield row, tagged so on_gui_confirmed/text_changed can route edits.
local function add_field(root, name, caption, text, tag, enabled)
  root.add { type = "label", caption = caption }
  root.add { type = "textfield", name = name, text = text, tags = tag, enabled = enabled }
end
-- Every custom panel has an explicit close button; tags prevent unrelated Factorio GUI buttons
-- named "close" from being handled by control.lua.
local function add_close(root)
  root.add { type = "button", name = "close", caption = "Close", tags = { cf_freeplay_close = true } }
end
-- Controller panel: account name, starting debt/assets (locked after first Start), and the
-- Start/Pause button. Fields are read-only while the account is running.
function M.open_controller(p, cf)
  close(p)
  local root = p.gui.left.add { type = "frame", name = ROOT, direction = "vertical", caption = "Cashflow: " .. cf.name, tags = { controller_unit_number = cf.controller.unit_number } }
  add_close(root)
  local editable = not cf.running
  add_field(root, "account_name", "Account name", cf.name, root.tags, editable)
  add_field(root, "debt", "Starting debt ($)", tostring(cf.config.starting_debt_cents / 100), root.tags, editable and not cf.started)
  add_field(root, "assets", "Starting assets ($)", tostring(cf.config.starting_assets_cents / 100), root.tags, editable and not cf.started)
  if cf.running then root.add { type = "label", caption = "Pause this account before changing its configuration." }
  elseif cf.started then root.add { type = "label", caption = "Starting debt and assets are locked after first Start." } end
  root.add { type = "button", name = "toggle", caption = cf.running and "Pause" or "Start", tags = root.tags }
  local year, month = acc.calendar(cf.month)
  root.add { type = "label", name = "summary", caption = "Year " .. year .. " Month " .. month .. "  Debt " .. acc.money(cf.debt_cents), tags = root.tags }
end
-- Machine panel: an account picker plus whatever fields the station's role needs (monthly
-- amount for income/expense, salary for smelter, APR for debt, return for vault, needs/wants
-- for expense). Disabled while the linked controller is running.
function M.open_machine(p, machine, controllers)
  close(p)
  local root = p.gui.left.add { type = "frame", name = ROOT, direction = "vertical", caption = machine.role .. " station", tags = { machine_unit_number = machine.unit_number } }
  add_close(root)
  local owner = machine.controller_unit_number and controllers[machine.controller_unit_number]
  local editable = not owner or not owner.running
  local selected, names, candidates = 1, { "Unlinked" }, {}
  for _, cf in pairs(controllers) do candidates[#candidates + 1] = cf end
  table.sort(candidates, function(a, b) return a.name < b.name end)
  for _, cf in ipairs(candidates) do
    names[#names + 1] = cf.name
    if machine.controller_unit_number == cf.controller.unit_number then selected = #names end
  end
  root.add { type = "label", caption = "Account" }
  root.add { type = "drop-down", name = "account", items = names, selected_index = selected, tags = root.tags, enabled = editable }
  if machine.role == "income" or machine.role == "expense" then add_field(root, "amount", "Monthly " .. machine.role .. " ($, max " .. acc.money(acc.MAX_STATION_MONTHLY_CENTS) .. ")", tostring(machine.config.monthly_cents / 100), root.tags, editable) end
  if machine.role == "smelter" then
    add_field(root, "amount", "Monthly salary ($, max " .. acc.money(acc.MAX_STATION_MONTHLY_CENTS) .. ")", tostring(machine.config.monthly_cents / 100), root.tags, editable)
    root.add { type = "label", caption = "Load " .. acc.SMELTER_COAL_PER_MONTH .. " coal each month; smelting takes 2 seconds." }
  end
  if machine.role == "debt" then add_field(root, "apr", "Debt APR (%)", tostring(machine.config.apr), root.tags, editable) end
  if machine.role == "vault" then add_field(root, "return", "Asset return (%)", tostring(machine.config.asset_return), root.tags, editable) end
  if machine.role == "expense" then
    root.add { type = "label", caption = "Expense category" }
    root.add { type = "drop-down", name = "category", items = { "needs", "wants" }, selected_index = machine.config.category == "wants" and 2 or 1, tags = root.tags, enabled = editable }
  end
  if not editable then root.add { type = "label", caption = "Pause " .. owner.name .. " before changing this station." } end
end

-- Re-renders an open controller panel after account state changes elsewhere (e.g. month
-- close); closes it if the bound controller became invalid or moved out of reach.
function M.refresh_player(p)
  local root = p.gui.left[ROOT]
  if not root or not root.tags then return end
  local unit = root.tags.controller_unit_number
  if unit then
    local cf = state().accounts[unit]
    if not valid_target(p, cf) then close(p) else M.open_controller(p, cf) end
  end
end
-- Closes `p`'s panel (used by control.lua when its target entity disappears).
function M.close(p) close(p) end
return M
