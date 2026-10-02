-- Runtime entry point: entity registry, controller<->station linking, GUI event wiring, and the
-- two recurring tick loops (fast belt sweep + slow label refresh). All persistent state lives
-- under storage.cf_freeplay; `accounting.lua` and `stations.lua` do the actual money math.
local acc = require("script.accounting")
local account = require("script.account")
local stations = require("script.stations")
local pulse = require("script.pulse")
local layout = require("script.station_layout")
local labels = require("script.labels")
local gui = require("script.gui")
local SWEEP_TICKS, REFRESH_TICKS = 2, 30 -- belt sweep cadence (ticks); label/account refresh cadence (ticks)
local PREFIX, STATION_LAYOUT_VERSION = "cf-freeplay-", 2 -- entity name prefix; bump to force normalize_layouts() migration

-- Lazily creates and returns the mod's single persistent state table.
local function state()
  storage.cf_freeplay = storage.cf_freeplay or { schema_version = 1, station_layout_version = STATION_LAYOUT_VERSION, accounts = {}, machines = {} }
  return storage.cf_freeplay
end
-- Returns the station role ("controller", "income", "expense", "cashflow", "debt", "vault")
-- for one of our entities, or nil if the entity isn't ours or has no role suffix.
local function role_of(entity)
  if not (entity and entity.valid and entity.name:sub(1, #PREFIX) == PREFIX) then return nil end
  local role = entity.name:sub(#PREFIX + 1)
  return ({ controller = true, income = true, expense = true, cashflow = true, debt = true, vault = true })[role] and role or nil
end
-- True when both records sit on the same surface and force (accounts never cross either).
local function same_place(a, b) return a.surface_index == b.surface.index and a.force_index == b.force.index end
-- Detaches a machine from its controller: removes it from cf.entities[role]/cf.machines and
-- clears machine.controller_unit_number. Safe to call on an already-unlinked machine.
local function unlink(machine)
  local unit = machine.controller_unit_number
  if not unit then return end
  local cf = state().accounts[unit]
  if cf then
    for i, item in ipairs(cf.entities[machine.role]) do if item == machine then table.remove(cf.entities[machine.role], i); break end end
    cf.machines[machine.unit_number] = nil
    labels.account(cf)
  end
  machine.controller_unit_number = nil
  labels.machine(machine)
end
-- Links `machine` to the controller identified by `controller_unit`. Rejects running
-- controllers and mismatched surface/force. Every role may link any number of stations.
local function link(machine, controller_unit)
  local cf = state().accounts[controller_unit]
  if not cf then return false, "Select a controller." end
  if cf.running then return false, "Pause the controller before linking stations." end
  if not same_place(cf, machine.anchor) then return false, "Controllers must be on the same force and surface." end
  unlink(machine)
  machine.controller_unit_number = controller_unit
  cf.machines[machine.unit_number] = machine
  cf.entities[machine.role][#cf.entities[machine.role] + 1] = machine
  labels.machine(machine, cf.name); labels.account(cf)
  return true
end
-- on_built handler: creates the controller account or machine record for a freshly placed
-- cf-freeplay-* entity, building its hidden helper-port belts via station_layout.build.
-- Destroys-and-drops the entity if there isn't room for its ports.
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
  local config = { monthly_cents = 0, category = role == "expense" and "needs" or nil }
  if role == "debt" then config.apr = 18 elseif role == "vault" then config.asset_return = 7 end
  local machine = { unit_number = entity.unit_number, anchor = entity, role = role, entities = entities, config = config, out = 0, opening_debt_cents = 0, interest_carry_cents = 0, pending_interest = 0, opening_principal_cents = 0, return_carry_cents = 0, pending_returns = 0 }
  s.machines[machine.unit_number] = machine
  labels.machine(machine)
end
-- on_mined/on_died handler: tears down a controller (unlinking every owned machine) or a
-- machine (force-pausing its controller if it was a live financial station, then destroying
-- its helper ports and labels).
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
-- Player must share the account's surface/force to view it, and the account must be paused
-- to change its configuration.
local function player_can_access(player, cf) return cf and same_place(cf, player) end
local function player_can_change(player, cf) return player_can_access(player, cf) and not cf.running end
-- Parses a nonnegative decimal from a GUI textfield; `cents` requests integer-cent rounding.
-- Returns nil (rejected) for NaN, negative, or infinite input.
local function decimal(text, cents)
  local number = tonumber(text)
  if not number or number ~= number or number < 0 or number == math.huge then return nil end
  return cents and math.floor(number * 100 + 0.5) or number
end
local function controller_from_tags(tags) return tags and state().accounts[tags.controller_unit_number] end
local function machine_from_tags(tags) return tags and state().machines[tags.machine_unit_number] end
local function show_error(player, text) player.print(text) end

-- Script-interface query surface for external telemetry tools: per-account snapshot of
-- balances, rates, and running/pending interest state. Read-only; no mutation.
remote.add_interface("cashflow-freeplay", {
  telemetry = function()
    local accounts = {}
    for unit, cf in pairs(state().accounts) do
      local interest_carry, interest_out = 0, cf.out.interest or 0
      for _, machine in ipairs(cf.entities.debt) do
        interest_carry = interest_carry + (machine.interest_carry_cents or 0)
        interest_out = interest_out + (machine.pending_interest or 0)
      end
      accounts[unit] = {
        name = cf.name,
        running = cf.running,
        month = cf.month,
        tick_in_month = cf.tick_in_month,
        debt_cents = cf.debt_cents,
        assets_cents = stations.vault_plates(cf) * acc.CENTS_PER_PLATE,
        debt_accounts = #cf.entities.debt,
        asset_accounts = #cf.entities.vault,
        opening_debt_cents = cf.opening_debt_cents,
        configuration = {
          starting_debt_cents = cf.config.starting_debt_cents,
          starting_assets_cents = cf.config.starting_assets_cents,
        },
        interest_carry_cents = interest_carry,
        interest_out_plates = interest_out,
      }
    end
    return accounts
  end,
})

-- Re-derives hidden port geometry/direction and config defaults for every machine/account,
-- then re-fills any owed income/expense buffers. Runs on load and after config changes so
-- saves made with an older station_layout_version or account.normalize shape self-heal.
local function normalize_layouts()
  local s = state()
  for _, machine in pairs(s.machines) do
    layout.normalize(machine)
    if machine.config and machine.config.monthly_cents then machine.config.monthly_cents = math.min(machine.config.monthly_cents, acc.MAX_STATION_MONTHLY_CENTS) end
    local owner = machine.controller_unit_number and s.accounts[machine.controller_unit_number]
    labels.machine(machine, owner and owner.name)
  end
  for _, cf in pairs(s.accounts) do
    account.normalize(cf)
    account.restore_month_buffers(cf)
    stations.refresh_totals(cf)
  end
end
-- Pre-0.2.23 controllers were 2000-slot chests. migrations/cashflow-freeplay_0.2.23.json renames
-- them to cf-freeplay-legacy-controller (Factorio cannot change an entity's type in place); this
-- swaps each for the market-type controller at the same position, re-keys its account by the
-- new unit_number, relinks its stations, and spills anything a player had stored in the chest.
local function migrate_legacy_controllers()
  local s, legacy = state(), {}
  for unit, cf in pairs(s.accounts) do
    if cf.controller and cf.controller.valid and cf.controller.name == PREFIX .. "legacy-controller" then legacy[#legacy + 1] = unit end
  end
  for _, unit in ipairs(legacy) do
    local cf = s.accounts[unit]
    local old = cf.controller
    local surface, position, force = old.surface, old.position, old.force
    local inv = old.get_inventory(defines.inventory.chest)
    local contents = inv and inv.get_contents() or {}
    old.destroy()
    for _, stack in ipairs(contents) do surface.spill_item_stack { position = position, stack = { name = stack.name, count = stack.count, quality = stack.quality }, enable_looted = true } end
    local controller = surface.create_entity { name = PREFIX .. "controller", position = position, force = force }
    if controller then
      s.accounts[unit] = nil
      s.accounts[controller.unit_number] = cf
      cf.controller = controller
      for _, machine in pairs(cf.machines) do machine.controller_unit_number = controller.unit_number end
      labels.account(cf)
    else
      game.print("[color=red]Cashflow Freeplay could not rebuild the controller for " .. cf.name .. "; place a new controller and relink its stations.[/color]")
    end
  end
  if #legacy > 0 then for _, player in pairs(game.players) do gui.refresh_player(player) end end
end

-- Fresh save: stamp the current layout version (no migration warning needed).
script.on_init(function()
  local s = state()
  s.station_layout_version = STATION_LAYOUT_VERSION
  normalize_layouts()
end)
-- Existing save loaded under mismatched compatibility: warn players that every station
-- building changed footprint and must be mined/re-placed, then normalize in place.
script.on_configuration_changed(function()
  local s = state()
  if s.station_layout_version ~= STATION_LAYOUT_VERSION then
    s.station_layout_version = STATION_LAYOUT_VERSION
    game.print("[color=yellow]Cashflow Freeplay station buildings are larger now. Mine and re-place every station before reconnecting its perimeter belt ports.[/color]")
  end
  migrate_legacy_controllers()
  normalize_layouts()
end)
-- Placing any cf-freeplay-* entity (build, blueprint, robot, script-revive, or clone)
-- goes through `register`, which builds its hidden helper ports or creates its account.
local build_events = { defines.events.on_built_entity, defines.events.on_robot_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive }
for _, event in ipairs(build_events) do
  script.on_event(event, function(e)
    register(e.created_entity or e.entity)
  end)
end
script.on_event(defines.events.on_entity_cloned, function(e)
  register(e.destination)
end)
-- Mining/killing/destroying a cf-freeplay-* entity tears it down via `remove`.
local remove_events = { defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity, defines.events.on_entity_died, defines.events.script_raised_destroy }
for _, event in ipairs(remove_events) do script.on_event(event, function(e) remove(e.entity) end) end
-- Opening a controller or machine entity shows its configuration panel. A controller is a
-- `market` with no offers, so its empty vanilla market window is closed immediately.
script.on_event(defines.events.on_gui_opened, function(e)
  local entity, p = e.entity, game.get_player(e.player_index)
  local role = role_of(entity)
  if not role then return end
  if role == "controller" then
    local cf = state().accounts[entity.unit_number]
    p.opened = nil
    if cf then gui.open_controller(p, cf) end
  else local machine = state().machines[entity.unit_number]; if machine then gui.open_machine(p, machine, state().accounts) end end
end)
-- "Start"/"Pause" button: Start validates required linked stations via account.start;
-- Pause just flips the flag so configuration can be edited again.
script.on_event(defines.events.on_gui_click, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid and el.name == "toggle") then return end
  local cf = controller_from_tags(el.tags)
  if not player_can_access(p, cf) then return show_error(p, "Controller is unavailable.") end
  if cf.running then cf.running = false else local ok, reason = account.start(cf, stations); if not ok then return show_error(p, reason) end end
  labels.account(cf); gui.open_controller(p, cf)
end)
-- Enter/confirm on a textfield: validates and commits name/starting-debt/starting-assets
-- (controller, only before first Start) or per-machine amount/APR/return (machine, only
-- while its owner is paused or unlinked).
script.on_event(defines.events.on_gui_confirmed, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid) then return end
  local cf = controller_from_tags(el.tags)
  if cf then
    if not player_can_change(p, cf) then return show_error(p, "Pause the controller before changing configuration.") end
    local value = el.text
    if el.name == "account_name" then if value == "" or #value > 64 then return show_error(p, "Name must contain 1-64 characters.") end; cf.name = value
    elseif el.name == "debt" and not cf.started then local n = decimal(value, true); if not n then return show_error(p, "Starting debt must be a nonnegative number.") end; cf.config.starting_debt_cents = n
    elseif el.name == "assets" and not cf.started then local n = decimal(value, true); if not n then return show_error(p, "Starting assets must be a nonnegative number.") end; cf.config.starting_assets_cents = n end
    labels.account(cf); return gui.open_controller(p, cf)
  end
  local machine = machine_from_tags(el.tags)
  local owner = machine and state().accounts[machine.controller_unit_number]
  if not (machine and (not owner or player_can_change(p, owner))) then return end
  local n = el.name == "amount" and decimal(el.text, true) or decimal(el.text)
  if not n then return show_error(p, "Enter a nonnegative number.") end
  if el.name == "amount" then
    if n > acc.MAX_STATION_MONTHLY_CENTS then
      n = acc.MAX_STATION_MONTHLY_CENTS
      el.text = tostring(math.floor(n / 100))
      show_error(p, "Monthly amount is capped at " .. acc.money(n) .. " per station (blue belt limit).")
    end
    machine.config.monthly_cents = n
  elseif el.name == "apr" and machine.role == "debt" then machine.config.apr = n
  elseif el.name == "return" and machine.role == "vault" then machine.config.asset_return = n
  else return end
  labels.machine(machine, owner and owner.name)
end)
-- Live textfield edits mirror on_gui_confirmed's per-machine validation so the label
-- updates as the player types, but silently ignore invalid input instead of erroring.
script.on_event(defines.events.on_gui_text_changed, function(e)
  local p, el = game.get_player(e.player_index), e.element
  if not (el and el.valid) then return end
  local machine = machine_from_tags(el.tags)
  local owner = machine and state().accounts[machine.controller_unit_number]
  if not (machine and (not owner or not owner.running)) then return end
  local n = el.name == "amount" and decimal(el.text, true) or decimal(el.text)
  if not n then return end
  if el.name == "amount" then machine.config.monthly_cents = math.min(n, acc.MAX_STATION_MONTHLY_CENTS)
  elseif el.name == "apr" and machine.role == "debt" then machine.config.apr = n
  elseif el.name == "return" and machine.role == "vault" then machine.config.asset_return = n
  else return end
  labels.machine(machine, owner and owner.name)
end)
-- Dropdown changes: expense needs/wants category, or re-linking a machine to a different
-- controller (index 1 is "Unlinked"). Rejects link attempts while the target is running.
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
-- Fast loop: advances each running account's belt I/O by SWEEP_TICKS and closes the month
-- once a full TICKS_PER_MONTH has elapsed. Auto-pauses an account whose linked stations no
-- longer satisfy account.can_start (e.g. a required station was removed).
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
-- Slow loop: refreshes the floating controller/debt/vault labels so displayed balances and
-- rates stay current without redrawing them every sweep tick.
script.on_nth_tick(REFRESH_TICKS, function()
  for _, cf in pairs(state().accounts) do
    if cf.running then labels.account(cf) end
    for _, machine in ipairs(cf.entities.debt) do labels.machine(machine) end
    for _, machine in ipairs(cf.entities.vault) do labels.machine(machine) end
  end
end)
