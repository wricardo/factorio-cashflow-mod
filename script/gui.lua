-- Configuration panels (all named cashflow_panel; exactly one per player at a time).
--   * Account (controller): a centered, draggable dialog in gui.screen registered as player.opened,
--     so Esc/E close it like any vanilla window. It is a live dashboard plus the account setup.
--   * Stations and the Percent Splitter: a panel docked in gui.left beside the vanilla entity
--     window (whose inventory stays usable); control.lua closes it on on_gui_closed.
-- Every panel has the same shape: titlebar (title + close button) and `body`, whose last child
-- `error` shows validation messages inline. Root `tags` say which controller/machine/splitter
-- the panel is bound to, so control.lua's gui_* handlers know where edits go.
-- All captions are locale keys (locale/en, section [cashflow-gui]); only money and names are passed in.
local acc = require("script.accounting")
local labels = require("script.labels")
local rules = require("script.rules")
local account = require("script.account")
local stations = require("script.stations")
local M = {}
local ROOT = "cashflow_panel"
local ERROR_COLOR = { 1, 0.45, 0.3 }
local MUTED_COLOR = { 0.7, 0.7, 0.7 }
M.ROOT = ROOT

-- The single persistent state table (shared with control.lua/account.lua/stations.lua).
local function state()
  return storage.cashflow
end
-- True when `record` (a controller or machine) is on the same surface/force as `p`.
local function valid_target(p, record)
  return record and record.surface_index == p.surface.index and record.force_index == p.force.index
end
local function find_root(p)
  return p.gui.screen[ROOT] or p.gui.left[ROOT]
end
-- Destroys the player's open panel, if any.
local function close(p)
  for _, area in ipairs({ p.gui.screen, p.gui.left }) do
    local root = area[ROOT]
    if root then root.destroy() end
  end
end

-- Titlebar (title, drag handle, close button) plus the inner `body` frame every panel fills.
-- The close button is tagged so control.lua doesn't confuse it with unrelated GUI buttons.
local function add_frame(root, title, draggable)
  local bar = root.add { type = "flow", name = "titlebar", direction = "horizontal" }
  bar.style.horizontal_spacing = 8
  if draggable then bar.drag_target = root end
  bar.add { type = "label", name = "title", caption = title, style = "frame_title", ignored_by_interaction = true }
  local filler = bar.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  bar.add { type = "sprite-button", name = "close", style = "frame_action_button", sprite = "utility/close", hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black", tooltip = { "gui.close-instruction" }, tags = { cashflow_close = true } }
  return root.add { type = "frame", name = "body", style = "inside_shallow_frame_with_padding", direction = "vertical" }
end
-- Hidden until show_error fills it; the last child of `body`.
local function add_error(body)
  local label = body.add { type = "label", name = "error", visible = false }
  label.style.font_color = ERROR_COLOR
  label.style.single_line = false
  label.style.maximal_width = 380
end
local function add_note(parent, name, caption, muted)
  local label = parent.add { type = "label", name = name, caption = caption }
  label.style.single_line = false
  label.style.maximal_width = 380
  if muted then label.style.font_color = MUTED_COLOR end
  return label
end
-- Captioned textfield row, tagged so on_gui_confirmed/text_changed can route edits. Number
-- fields reject letters and minus signs as the player types; the handlers still validate.
-- opts: numeric, decimal (allow a fraction), suffix (unit shown after the field).
local function add_field(parent, name, caption, text, tags, enabled, opts)
  opts = opts or {}
  local row = parent.add { type = "flow", name = "row_" .. name, direction = "horizontal" }
  row.style.vertical_align = "center"
  local label = row.add { type = "label", caption = caption }
  label.style.minimal_width = 170
  local spec = { type = "textfield", name = name, text = text, tags = tags, enabled = enabled }
  if opts.numeric then spec.numeric, spec.allow_decimal, spec.allow_negative = true, opts.decimal or false, false end
  local field = row.add(spec)
  field.style.width = 120
  if opts.suffix then row.add { type = "label", caption = opts.suffix } end
  return field
end
local function field_of(section, name)
  local row = section["row_" .. name]
  return row and row[name]
end

-- Shows `message` (string or LocalisedString) in the open panel; falls back to chat when the
-- player has no panel open.
function M.show_error(p, message)
  local root = find_root(p)
  local label = root and root.body and root.body.error
  if label then
    label.caption = message
    label.visible = true
  else
    p.print(message)
  end
end
function M.clear_error(p)
  local root = find_root(p)
  local label = root and root.body and root.body.error
  if label then label.visible = false end
end

-- Accounts a machine may link to (same surface and force), in the order the drop-down lists
-- them; control.lua maps the selected index back through the same list.
function M.account_choices(machine, accounts)
  local list = {}
  for _, cf in pairs(accounts) do
    if cf.surface_index == machine.anchor.surface.index and cf.force_index == machine.anchor.force.index then list[#list + 1] = cf end
  end
  table.sort(list, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.controller.unit_number < b.controller.unit_number
  end)
  return list
end

-- ---------------------------------------------------------------- Account dashboard

local function signed_money(cents)
  return (cents >= 0 and "+" or "") .. acc.money(cents)
end
local function add_dashboard(body)
  local status = body.add { type = "flow", name = "status", direction = "vertical" }
  status.add { type = "label", name = "month_text", style = "bold_label" }
  status.add { type = "progressbar", name = "month_bar" }.style.horizontally_stretchable = true
  local figures = status.add { type = "table", name = "figures", column_count = 2 }
  for _, key in ipairs({ "assets", "debt", "networth", "cashflow" }) do
    figures.add { type = "label", caption = { "cashflow-gui.stat-" .. key } }
    figures.add { type = "label", name = "stat_" .. key }
  end
  status.add { type = "label", name = "coverage_text" }
  status.add { type = "progressbar", name = "coverage_bar" }.style.horizontally_stretchable = true
end
local function add_checklist(body, cf)
  local list = body.add { type = "flow", name = "checklist", direction = "vertical" }
  list.add { type = "label", caption = { "cashflow-gui.needed-to-start" }, style = "bold_label" }
  for _, requirement in ipairs(account.requirements(cf)) do list.add { type = "label", name = "req_" .. requirement.role } end
end
local function add_reports(body)
  local section = body.add { type = "flow", name = "reports", direction = "vertical", visible = false }
  section.add { type = "label", caption = { "cashflow-gui.reports" }, style = "bold_label" }
  section.add { type = "table", name = "reports_table", column_count = 6, tags = { signature = "" } }
end
-- Newest five yearly reports, rebuilt only when a new one has been closed.
local function sync_reports(body, cf)
  local reports = cf.year_reports or {}
  local section = body.reports
  section.visible = #reports > 0
  local grid = section.reports_table
  local signature = #reports > 0 and (#reports .. ":" .. reports[#reports].year) or "0"
  if grid.tags.signature == signature then return end
  grid.tags = { signature = signature }
  grid.clear()
  if #reports == 0 then return end
  for _, key in ipairs({ "year", "income", "expenses", "assets", "debt", "networth" }) do grid.add { type = "label", caption = { "cashflow-gui.col-" .. key }, style = "bold_label" } end
  for i = #reports, math.max(1, #reports - 4), -1 do
    local report = reports[i]
    grid.add { type = "label", caption = tostring(report.year) }
    for _, cents in ipairs({ report.income_cents, report.expense_cents, report.assets_cents, report.debt_cents, report.net_worth_cents }) do grid.add { type = "label", caption = acc.money(cents) } end
  end
end
-- Updates every live element of an open Account panel in place, so a textfield being edited is
-- never rebuilt under the player.
local function sync_controller(root, cf)
  local body = root.body
  root.titlebar.title.caption = { "cashflow-gui.account-title", cf.name }
  local status = body.status
  local year, month = acc.calendar(cf.month)
  status.month_text.caption = { "cashflow-gui.month-line", year, month, { cf.running and "cashflow-gui.state-running" or "cashflow-gui.state-paused" } }
  status.month_bar.value = math.min(1, cf.tick_in_month / rules.month_ticks())
  local assets = stations.vault_plates(cf) * acc.CENTS_PER_PLATE
  local figures = status.figures
  figures.stat_assets.caption = acc.money(assets)
  figures.stat_debt.caption = acc.money(cf.debt_cents)
  figures.stat_networth.caption = acc.money(assets - cf.debt_cents)
  figures.stat_cashflow.caption = signed_money(labels.monthly_cashflow(cf))
  local expenses = account.monthly_expenses_cents(cf)
  local returns = account.monthly_returns_cents(cf)
  status.coverage_text.caption = expenses > 0 and { "cashflow-gui.coverage", acc.money(returns), acc.money(expenses) } or { "cashflow-gui.coverage-none", acc.money(returns) }
  status.coverage_bar.visible = expenses > 0
  status.coverage_bar.value = expenses > 0 and math.min(1, returns / expenses) or 0

  local complete = true
  for _, requirement in ipairs(account.requirements(cf)) do
    complete = complete and requirement.linked
    body.checklist["req_" .. requirement.role].caption = { "cashflow-gui.req-line", { "entity-name.cashflow-" .. requirement.role }, { requirement.linked and "cashflow-gui.req-linked" or "cashflow-gui.req-missing" } }
  end
  body.checklist.visible = not cf.running
  local setup = body.setup
  local toggle = body.toggle
  toggle.caption = { cf.running and "cashflow-gui.pause" or "cashflow-gui.start" }
  toggle.enabled = cf.running or complete
  toggle.style = cf.running and "red_button" or "confirm_button"
  sync_reports(body, cf)
end

-- Account panel: live dashboard (month progress, assets/debt/net worth/cashflow, investment
-- coverage of expenses), the start checklist, account setup, the Start/Pause button, and the
-- yearly report table. The name can change any time; starting debt and assets become plain
-- text after the first Start.
function M.open_controller(p, cf)
  close(p)
  local tags = { controller_unit_number = cf.controller.unit_number }
  local root = p.gui.screen.add { type = "frame", name = ROOT, direction = "vertical", tags = tags }
  root.auto_center = true
  local body = add_frame(root, { "cashflow-gui.account-title", cf.name }, true)
  body.style.minimal_width = 380
  add_dashboard(body)
  body.add { type = "line" }
  add_checklist(body, cf)
  local setup = body.add { type = "flow", name = "setup", direction = "vertical" }
  setup.add { type = "label", caption = { "cashflow-gui.setup" }, style = "bold_label" }
  add_field(setup, "account_name", { "cashflow-gui.account-name" }, cf.name, tags, true)
  if cf.started then
    setup.add { type = "label", caption = { "cashflow-gui.locked-debt", acc.money(cf.config.starting_debt_cents) } }
    setup.add { type = "label", caption = { "cashflow-gui.locked-assets", acc.money(cf.config.starting_assets_cents) } }
  else
    add_field(setup, "debt", { "cashflow-gui.starting-debt" }, tostring(cf.config.starting_debt_cents / 100), tags, true, { numeric = true, decimal = true, suffix = "$" })
    add_field(setup, "assets", { "cashflow-gui.starting-assets" }, tostring(cf.config.starting_assets_cents / 100), tags, true, { numeric = true, decimal = true, suffix = "$" })
  end
  body.add { type = "button", name = "toggle", tags = tags }
  add_reports(body)
  add_error(body)
  sync_controller(root, cf)
  p.opened = root
end

-- ---------------------------------------------------------------- Station panels

-- How each station's ports connect; text lives in locale as cashflow-gui.hint-<role>.
local HINT_ROLES = { income = true, expense = true, smelter = true, cashflow = true, debt = true, vault = true }
local function add_hints(body, p, role)
  if not HINT_ROLES[role] then return end
  local s = state()
  s.hints_hidden = s.hints_hidden or {}
  local hidden = s.hints_hidden[p.index] or false
  local section = body.add { type = "flow", name = "hints_section", direction = "vertical" }
  section.add { type = "button", name = "hints_toggle", caption = { hidden and "cashflow-gui.hints-show" or "cashflow-gui.hints-hide" }, tags = { cashflow_hints = true } }
  add_note(section, "hints_text", { "cashflow-gui.hint-" .. role }, true).visible = not hidden
end
-- Collapses or expands the "how to connect" text; remembered per player across panels.
function M.toggle_hints(p)
  local root = find_root(p)
  local section = root and root.body and root.body.hints_section
  if not section then return end
  local s = state()
  s.hints_hidden = s.hints_hidden or {}
  local hidden = not s.hints_hidden[p.index]
  s.hints_hidden[p.index] = hidden
  section.hints_text.visible = not hidden
  section.hints_toggle.caption = { hidden and "cashflow-gui.hints-show" or "cashflow-gui.hints-hide" }
end

-- Machine panel: an account picker (with a locate button) plus whatever fields the station's
-- role needs: monthly amount (income/expense), salary (smelter), APR (debt), return (vault),
-- needs/wants switch (expense). Values stay editable while the account runs and apply from
-- the next month; only (un)linking is locked until the account is paused.
function M.open_machine(p, machine, controllers)
  close(p)
  local tags = { machine_unit_number = machine.unit_number }
  local root = p.gui.left.add { type = "frame", name = ROOT, direction = "vertical", tags = tags }
  local body = add_frame(root, { "entity-name.cashflow-" .. machine.role }, false)
  local owner = machine.controller_unit_number and controllers[machine.controller_unit_number]
  local linkable = not owner or not owner.running
  local selected, items = 1, { { "cashflow-gui.unlinked" } }
  for _, cf in ipairs(M.account_choices(machine, controllers)) do
    local position = cf.controller.position
    items[#items + 1] = { "cashflow-gui.choice", cf.name, math.floor(position.x), math.floor(position.y) }
    if machine.controller_unit_number == cf.controller.unit_number then selected = #items end
  end
  body.add { type = "label", caption = { "cashflow-gui.account" }, style = "bold_label" }
  local row = body.add { type = "flow", name = "account_row", direction = "horizontal" }
  row.add { type = "drop-down", name = "account", items = items, selected_index = selected, tags = tags, enabled = linkable }
  row.add { type = "button", name = "locate", caption = { "cashflow-gui.locate" }, tooltip = { "cashflow-gui.locate-tooltip" }, tags = { cashflow_locate = true, machine_unit_number = machine.unit_number } }
  local cap = acc.money(acc.MAX_STATION_CENTS)
  local amount_caption = { income = "cashflow-gui.field-income", expense = "cashflow-gui.field-expense", smelter = "cashflow-gui.field-salary" }
  if amount_caption[machine.role] then
    add_field(body, "amount", { amount_caption[machine.role] }, tostring(machine.config.monthly_cents / 100), tags, true, { numeric = true, decimal = true, suffix = "$" })
    add_note(body, "cap_hint", { "cashflow-gui.cap-hint", cap }, true)
  end
  if machine.role == "smelter" then add_note(body, "coal_note", { "cashflow-gui.smelter-note", acc.SMELTER_COAL_PER_MONTH }, true) end
  if machine.role == "debt" then add_field(body, "apr", { "cashflow-gui.field-apr" }, tostring(machine.config.apr), tags, true, { numeric = true, decimal = true, suffix = "%" }) end
  if machine.role == "vault" then add_field(body, "return", { "cashflow-gui.field-return" }, tostring(machine.config.asset_return), tags, true, { numeric = true, decimal = true, suffix = "%" }) end
  if machine.role == "expense" then
    body.add { type = "label", caption = { "cashflow-gui.category" } }
    body.add { type = "switch", name = "category", switch_state = machine.config.category == "wants" and "right" or "left", left_label_caption = { "cashflow-gui.needs" }, right_label_caption = { "cashflow-gui.wants" }, tags = tags }
  end
  if owner and owner.running then
    add_note(body, "next_month_note", { "cashflow-gui.applies-next-month" }, true)
    add_note(body, "locked_note", { "cashflow-gui.pause-to-relink", owner.name }, true)
  end
  add_hints(body, p, machine.role)
  add_error(body)
end

-- Percent Splitter panel: the share of items that leave the left output; the right output gets
-- the rest. Opens next to Factorio's own splitter window, which keeps its filter controls.
function M.open_splitter(p, rec)
  close(p)
  local tags = { splitter_unit_number = rec.entity.unit_number }
  local root = p.gui.left.add { type = "frame", name = ROOT, direction = "vertical", tags = tags }
  local body = add_frame(root, { "entity-name.cashflow-percent-splitter" }, false)
  add_field(body, "percent", { "cashflow-gui.left-share" }, tostring(rec.percent), tags, true, { numeric = true, suffix = "%" })
  body.add { type = "label", name = "summary", caption = labels.split_summary(rec.percent), tags = tags }
  add_note(body, "split_note", { "cashflow-gui.left-explainer" }, true)
  add_error(body)
end

-- Refreshes an open Account panel in place after account state changes (every label refresh and
-- month close); closes it if the bound controller became invalid or moved out of reach.
function M.refresh_player(p)
  local root = find_root(p)
  if not root or not root.tags then return end
  local unit = root.tags.controller_unit_number
  if not unit then return end
  local cf = state().accounts[unit]
  if not valid_target(p, cf) then close(p) else sync_controller(root, cf) end
end
-- Closes `p`'s panel (used by control.lua when its target entity disappears).
function M.close(p) close(p) end
-- Closes a docked panel when the vanilla window of the entity it belongs to is closed (Esc/E).
function M.close_for_entity(p, entity)
  local root = p.gui.left[ROOT]
  local tags = root and root.tags
  if not (tags and entity.valid and entity.unit_number) then return end
  if tags.machine_unit_number == entity.unit_number or tags.splitter_unit_number == entity.unit_number then close(p) end
end
-- Updates the Percent Splitter panel's "Left x% • Right y%" line after a valid edit.
function M.set_splitter_summary(p, text)
  local root = find_root(p)
  local label = root and root.body and root.body.summary
  if label then label.caption = text end
end
return M
