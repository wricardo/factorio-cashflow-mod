local acc = require("script.accounting")
local account = require("script.account")
local stations = require("script.stations")
local pulse = require("script.pulse")
local layout = require("script.station_layout")
local labels = require("script.labels")
local gui = require("script.gui")
local SWEEP_TICKS, REFRESH_TICKS = 2, 30
local PREFIX, STATION_LAYOUT_VERSION = "cf-freeplay-", 2

local function state()
  storage.cf_freeplay = storage.cf_freeplay or { schema_version = 1, station_layout_version = STATION_LAYOUT_VERSION, accounts = {}, machines = {} }
  return storage.cf_freeplay
end
local function role_of(entity)
  if not (entity and entity.valid and entity.name:sub(1, #PREFIX) == PREFIX) then return nil end
  local role = entity.name:sub(#PREFIX + 1)
  return ({ controller = true, income = true, expense = true, cashflow = true, debt = true, vault = true })[role] and role or nil
end
local function same_place(a, b) return a.surface_index == b.surface.index and a.force_index == b.force.index end
local function unlink(machine)
  local unit = machine.controller_unit_number
  if not unit then return end
  local cf = state().accounts[unit]
  if cf then
    if machine.role == "income" or machine.role == "expense" then
      for i, item in ipairs(cf.entities[machine.role]) do if item == machine then table.remove(cf.entities[machine.role], i); break end end
    elseif cf.entities[machine.role] == machine then cf.entities[machine.role] = nil end
    cf.machines[machine.unit_number] = nil
    labels.account(cf)
  end
  machine.controller_unit_number = nil
  labels.machine(machine)
end
local function link(machine, controller_unit)
  local cf = state().accounts[controller_unit]
  if not cf then return false, "Select a controller." end
  if cf.running then return false, "Pause the controller before linking stations." end
  if not same_place(cf, machine.anchor) then return false, "Controllers must be on the same force and surface." end
  if machine.role == "cashflow" or machine.role == "debt" or machine.role == "vault" then
    if cf.entities[machine.role] and cf.entities[machine.role] ~= machine then return false, "That controller already has a linked " .. machine.role .. " station." end
  end
  unlink(machine)
  machine.controller_unit_number = controller_unit
  cf.machines[machine.unit_number] = machine
  if machine.role == "income" or machine.role == "expense" then cf.entities[machine.role][#cf.entities[machine.role] + 1] = machine else cf.entities[machine.role] = machine end
  labels.machine(machine, cf.name); labels.account(cf)
  return true
end
local function register(entity)
  local role = role_of(entity)
  if not role or not entity.unit_number then return end
  local s = state()
  if role == "controller" then
    if not s.accounts[entity.unit_number] then
      local cf = account.new(entity)
      s.accounts[entity.unit_number] = cf
      labels.account(cf)
    end
    return
  end
  if s.machines[entity.unit_number] then return end
  local entities, err = layout.build(entity, role)
  if not entities then entity.surface.create_entity { name = "item-on-ground", position = entity.position, stack = { name = entity.name, count = 1 } }; entity.destroy(); return end
  local machine = { unit_number = entity.unit_number, anchor = entity, role = role, entities = entities, config = { monthly_cents = 0, category = role == "expense" and "needs" or nil }, out = 0 }
  s.machines[machine.unit_number] = machine
  labels.machine(machine)
end
local function remove(entity)
  if not entity or not entity.unit_number then return end
  local s, cf = state(), state().accounts[entity.unit_number]
  if cf then
    for _, machine in pairs(cf.machines) do machine.controller_unit_number = nil; labels.machine(machine) end
    labels.destroy_account(cf); s.accounts[entity.unit_number] = nil
    for _, player in pairs(game.players) do gui.refresh_player(player) end
    return
  end
  local machine = s.machines[entity.unit_number]
  if machine then
    local owner = machine.controller_unit_number and s.accounts[machine.controller_unit_number]
    if owner and owner.running and (machine.role == "cashflow" or machine.role == "debt" or machine.role == "vault") then
      owner.running = false
    end
    unlink(machine)
    labels.destroy_machine(machine)
    layout.destroy(machine)
    s.machines[machine.unit_number] = nil
  end
end
local function player_can_access(player, cf) return cf and same_place(cf, player) end
local function player_can_change(player, cf) return player_can_access(player, cf) and not cf.running end
local function decimal(text, cents)
  local number = tonumber(text)
  if not number or number ~= number or number < 0 or number == math.huge then return nil end
  return cents and math.floor(number * 100 + 0.5) or number
end
local function controller_from_tags(tags) return tags and state().accounts[tags.controller_unit_number] end
local function machine_from_tags(tags) return tags and state().machines[tags.machine_unit_number] end
local function show_error(player, text) player.print(text) end

remote.add_interface("cashflow-freeplay", {
  telemetry = function()
    local accounts = {}
    for unit, cf in pairs(state().accounts) do
      accounts[unit] = {
        name = cf.name,
        running = cf.running,
        month = cf.month,
        tick_in_month = cf.tick_in_month,
        debt_cents = cf.debt_cents,
        opening_debt_cents = cf.opening_debt_cents,
        configuration = {
          starting_debt_cents = cf.config.starting_debt_cents,
          starting_assets_cents = cf.config.starting_assets_cents,
          debt_apr = cf.config.debt_apr,
          asset_return = cf.config.asset_return,
        },
        interest_carry_cents = cf.interest_carry_cents,
        interest_out_plates = cf.out.interest or 0,
      }
    end
    return accounts
  end,
})

local function normalize_layouts()
  local s = state()
  for _, machine in pairs(s.machines) do
    layout.normalize(machine)
    local owner = machine.controller_unit_number and s.accounts[machine.controller_unit_number]
    labels.machine(machine, owner and owner.name)
  end
  for _, cf in pairs(s.accounts) do
    account.restore_month_buffers(cf)
    stations.sync_ledger(cf)
  end
end

script.on_init(function()
  local s = state()
  s.station_layout_version = STATION_LAYOUT_VERSION
  normalize_layouts()
end)
script.on_configuration_changed(function()
  local s = state()
  if s.station_layout_version ~= STATION_LAYOUT_VERSION then
    s.station_layout_version = STATION_LAYOUT_VERSION
    game.print("[color=yellow]Cashflow Freeplay station buildings are larger now. Mine and re-place every station before reconnecting its perimeter belt ports.[/color]")
  end
  normalize_layouts()
end)
local build_events = { defines.events.on_built_entity, defines.events.on_robot_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive }
for _, event in ipairs(build_events) do
  script.on_event(event, function(e)
    register(e.created_entity or e.entity)
  end)
end
script.on_event(defines.events.on_entity_cloned, function(e)
  register(e.destination)
end)
local remove_events = { defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity, defines.events.on_entity_died, defines.events.script_raised_destroy }
for _, event in ipairs(remove_events) do script.on_event(event, function(e) remove(e.entity) end) end
script.on_event(defines.events.on_gui_opened, function(e)
  local entity, p = e.entity, game.get_player(e.player_index)
  local role = role_of(entity)
  if not role then return end
  if role == "controller" then local cf = state().accounts[entity.unit_number]; if cf then gui.open_controller(p, cf) end else local machine = state().machines[entity.unit_number]; if machine then gui.open_machine(p, machine, state().accounts) end end
end)
script.on_event(defines.events.on_gui_click, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid and el.name == "toggle") then return end
  local cf = controller_from_tags(el.tags)
  if not player_can_access(p, cf) then return show_error(p, "Controller is unavailable.") end
  if cf.running then cf.running = false else local ok, reason = account.start(cf, stations); if not ok then return show_error(p, reason) end end
  labels.account(cf); gui.open_controller(p, cf)
end)
script.on_event(defines.events.on_gui_confirmed, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid) then return end
  local cf = controller_from_tags(el.tags)
  if cf then
    if not player_can_change(p, cf) then return show_error(p, "Pause the controller before changing configuration.") end
    local value = el.text
    if el.name == "account_name" then if value == "" or #value > 64 then return show_error(p, "Name must contain 1-64 characters.") end; cf.name = value
    elseif el.name == "debt" and not cf.started then local n = decimal(value, true); if not n then return show_error(p, "Starting debt must be a nonnegative number.") end; cf.config.starting_debt_cents = n
    elseif el.name == "assets" and not cf.started then local n = decimal(value, true); if not n then return show_error(p, "Starting assets must be a nonnegative number.") end; cf.config.starting_assets_cents = n
    elseif el.name == "apr" then local n = decimal(value); if not n then return show_error(p, "APR must be a nonnegative number.") end; cf.config.debt_apr = n
    elseif el.name == "return" then local n = decimal(value); if not n then return show_error(p, "Return must be a nonnegative number.") end; cf.config.asset_return = n end
    labels.account(cf); return gui.open_controller(p, cf)
  end
  local machine = machine_from_tags(el.tags)
  local owner = machine and state().accounts[machine.controller_unit_number]
  if machine and (not owner or player_can_change(p, owner)) and el.name == "amount" then
    local n = decimal(el.text, true)
    if not n then return show_error(p, "Amount must be a nonnegative number.") end
    machine.config.monthly_cents = n
    labels.machine(machine, owner and owner.name)
  end
end)
script.on_event(defines.events.on_gui_text_changed, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid) then return end
  local cf = controller_from_tags(el.tags)
  if cf and (el.name == "apr" or el.name == "return") then
    if not player_can_change(p, cf) then return end
    local n = decimal(el.text)
    if n then
      if el.name == "apr" then cf.config.debt_apr = n else cf.config.asset_return = n end
      labels.account(cf)
    end
    return
  end
  if el.name ~= "amount" then return end
  local machine = machine_from_tags(el.tags)
  local owner = machine and state().accounts[machine.controller_unit_number]
  if not (machine and (not owner or not owner.running)) then return end
  local n = decimal(el.text, true)
  if n then
    machine.config.monthly_cents = n
    labels.machine(machine, owner and owner.name)
  end
end)
script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid) then return end
  local machine = machine_from_tags(el.tags)
  if not machine then return end
  local owner = state().accounts[machine.controller_unit_number]
  if owner and not player_can_change(p, owner) then return show_error(p, "Pause the controller before changing configuration.") end
  if el.name == "category" then machine.config.category = el.selected_index == 2 and "wants" or "needs"; return end
  if el.name == "account" then
    if el.selected_index == 1 then unlink(machine); return end
    local candidates = {}
    for _, cf in pairs(state().accounts) do if same_place(cf, machine.anchor) then candidates[#candidates + 1] = cf end end
    table.sort(candidates, function(a, b) return a.name < b.name end)
    local selected = candidates[el.selected_index - 1]
    if selected then local ok, err = link(machine, selected.controller.unit_number); if not ok then show_error(p, err) end end
  end
end)
script.on_nth_tick(SWEEP_TICKS, function()
  for _, cf in pairs(state().accounts) do
    if cf.running then
      if account.can_start(cf) then
        stations.sweep(cf, SWEEP_TICKS)
        if cf.tick_in_month >= acc.TICKS_PER_MONTH then pulse.close_month(cf) end
      else
        cf.running = false
        labels.account(cf)
      end
    end
  end
end)
script.on_nth_tick(REFRESH_TICKS, function() for _, cf in pairs(state().accounts) do if cf.running then labels.account(cf) end end end)
