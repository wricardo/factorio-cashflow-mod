-- Minimal stand-in for the Factorio runtime API, enough to load both mods and run months.
local host_require = require
local F = {}
-- Item capacity of the fixed-size station chests (data.lua: slots x 50-item coal stacks);
-- every other fake inventory is effectively unlimited.
F.inventory_limits = { ["cashflow-smelter"] = 50, ["cashflow-coal"] = 1000 }
local function new_inventory(limit)
  local inv = { items = {} }
  local function total() local n = 0; for _, count in pairs(inv.items) do n = n + count end; return n end
  function inv.get_item_count(name) return inv.items[name] or 0 end
  function inv.insert(stack) if stack.count <= 0 then error("count must be positive") end; local n = limit and math.min(stack.count, limit - total()) or stack.count; if n <= 0 then return 0 end; inv.items[stack.name] = (inv.items[stack.name] or 0) + n; return n end
  function inv.remove(stack) if stack.count <= 0 then error("count must be positive") end; local n = math.min(inv.items[stack.name] or 0, stack.count); inv.items[stack.name] = (inv.items[stack.name] or 0) - n; return n end
  function inv.get_insertable_count() return limit and limit - total() or 1000000 end
  function inv.get_contents() local out = {}; for name, count in pairs(inv.items) do if count > 0 then out[#out + 1] = { name = name, count = count, quality = "normal" } end end; return out end
  return inv
end
local function new_line(cap)
  local line = { items = {}, cap = cap }
  function line.insert_at_back(stack)
    if (line.items[stack.name] or 0) >= line.cap then return false end
    line.items[stack.name] = (line.items[stack.name] or 0) + stack.count
    return true
  end
  function line.remove_item(stack) local n = math.min(line.items[stack.name] or 0, stack.count); line.items[stack.name] = (line.items[stack.name] or 0) - n; return n end
  function line.put(name, count) line.items[name] = (line.items[name] or 0) + count end
  function line.get_item_count(name) return line.items[name] or 0 end
  return line
end
local next_unit = 1
local function new_entity(surface, spec)
  local e = { name = spec.name, position = spec.position or { x = 0, y = 0 }, direction = spec.direction or 2, surface = surface, force = spec.force or { index = 1 }, valid = true, unit_number = next_unit, minable = true, operable = true, rotatable = true }
  next_unit = next_unit + 1
  local lines, inv = { new_line(4), new_line(4) }, new_inventory(F.inventory_limits[spec.name])
  function e.get_transport_line(i) return lines[i] end
  function e.get_inventory() return inv end
  function e.destroy() e.valid = false end
  surface.entities[#surface.entities + 1] = e
  return e
end
local function new_surface(name, index)
  local s = { name = name, index = index, entities = {}, spilled = {}, tiles = {} }
  function s.request_to_generate_chunks() end
  function s.force_generate_chunk_requests() end
  function s.set_tiles(tiles) s.tiles = tiles end
  function s.destroy_decoratives() end
  function s.find_entities_filtered() return {} end
  function s.find_non_colliding_position(_, pos) return pos end
  function s.create_entity(spec) return new_entity(s, spec) end
  function s.spill_item_stack(params) s.spilled[#s.spilled + 1] = params end
  return s
end
local function new_gui_element(spec)
  local el = { valid = true, children = {}, style = {} }
  for k, v in pairs(spec) do el[k] = v end
  el.style_name, el.enabled, el.visible = spec.style, spec.enabled ~= false, spec.visible ~= false
  el.style = {}
  function el.add(child_spec)
    if child_spec.name == "name" then error("LuaGuiElement contains a property or method with the same name.") end
    local child = new_gui_element(child_spec)
    child.parent = el
    el.children[#el.children + 1] = child
    if child.name then el[child.name] = child end
    return child
  end
  function el.clear()
    for _, child in ipairs(el.children) do child.valid = false; if child.name then el[child.name] = nil end end
    el.children = {}
  end
  function el.destroy() el.valid = false; if el.parent and el.name then el.parent[el.name] = nil end end
  return el
end
-- Resolves a LocalisedString against the mod's real en locale file, so tests read the same text
-- players see and a misspelled key fails instead of passing silently.
local locale
local function load_locale()
  locale = {}
  local path = ((arg and arg[1]) or ".") .. "/locale/en/cashflow.cfg"
  local file = assert(io.open(path, "r"))
  local section
  for line in file:lines() do
    local name = line:match("^%[(.+)%]$")
    if name then section = name
    else
      local key, text = line:match("^([^=#]+)=(.*)$")
      if key then locale[section .. "." .. key] = text end
    end
  end
  file:close()
end
function F.localise(value)
  if type(value) ~= "table" then return tostring(value) end
  if value[1] == "" then
    local parts = {}
    for i = 2, #value do parts[#parts + 1] = F.localise(value[i]) end
    return table.concat(parts)
  end
  if not locale then load_locale() end
  local text = locale[value[1]]
  if not text then error("missing locale key " .. tostring(value[1])) end
  return (text:gsub("__(%d+)__", function(i) return F.localise(value[tonumber(i) + 1]) end))
end
function F.new_player(index, surface)
  local p = { index = index, valid = true, prints = {}, inventory = new_inventory(), surface = surface, position = { x = 0, y = 0 }, force = { index = 1 }, flying_texts = {} }
  p.gui = { left = new_gui_element({ type = "flow" }), screen = new_gui_element({ type = "flow" }) }
  -- Like the engine, replacing the open GUI asks the previous one to close (on_gui_closed).
  local opened
  setmetatable(p, {
    __index = function(_, key) if key == "opened" then return opened end end,
    __newindex = function(t, key, value)
      if key ~= "opened" then return rawset(t, key, value) end
      local previous = opened
      opened = value
      if previous and previous ~= value and t.on_closed then t.on_closed(previous) end
    end,
  })
  function p.get_main_inventory() return p.inventory end
  function p.teleport(pos, target) p.position, p.surface = pos, target end
  p.alerts = {}
  function p.print(msg) p.prints[#p.prints + 1] = msg end
  function p.add_custom_alert(entity, icon, message, show_on_map) p.alerts[#p.alerts + 1] = { entity = entity, icon = icon, message = message, show_on_map = show_on_map } end
  function p.create_local_flying_text(spec) p.flying_texts[#p.flying_texts + 1] = spec end
  return p
end
local default_settings = { ["cashflow-month-seconds"] = 60 }
function F.install(opts)
  opts = opts or {}; local h = { events = {}, nth = {}, logs = {}, tick = 0 }; local event_ids = {}
  local names = { "on_player_created", "on_chunk_generated", "on_gui_click", "on_runtime_mod_setting_changed", "on_player_main_inventory_changed", "on_built_entity", "on_player_mined_entity", "on_robot_mined_entity", "on_robot_built_entity", "on_entity_died", "script_raised_built", "script_raised_revive", "script_raised_destroy", "on_entity_cloned", "on_research_finished", "on_force_created", "on_gui_opened", "on_gui_confirmed", "on_gui_text_changed", "on_gui_selection_state_changed", "on_gui_closed", "on_gui_switch_state_changed", "on_rocket_launched" }
  for i, name in ipairs(names) do event_ids[name] = i end
  _G.defines = { events = event_ids, direction = { north = 0, east = 4, south = 8, west = 12 }, inventory = { chest = 1 }, entity_status_diode = { green = 1, yellow = 2, red = 3 } }
  local g = {}; for k, v in pairs(default_settings) do g[k] = { value = (opts.settings and opts.settings[k]) or v } end; _G.settings = { global = g }
  _G.storage = opts.storage or {}
  _G.remote = {
    interfaces = {},
    add_interface = function(name, functions) _G.remote.interfaces[name] = functions end,
    call = function(name, function_name, ...) return _G.remote.interfaces[name][function_name](...) end,
  }
  _G.script = { level = opts.level or { mod_name = "cashflow", level_name = "cashflow" }, on_init = function(fn) h.init = fn end, on_configuration_changed = function(fn) h.configuration_changed = fn end, on_event = function(id, fn) h.events[id] = fn end, on_nth_tick = function(n, fn) h.nth[n] = fn end }
  local surfaces = { nauvis = new_surface("nauvis", 1) }
  _G.game = { surfaces = surfaces, players = {}, connected_players = {}, forces = { player = { recipes = {} } }, speed = 1, create_surface = function(name) local s = new_surface(name, #surfaces + 1); surfaces[name] = s; return s end, get_player = function(i) return _G.game.players[i] end, print = function(msg) h.logs[#h.logs + 1] = msg end }
  _G.prototypes = { item = {} }
  h.frames = {}
  _G.rendering = {
    draw_text = function(spec) local obj = { text = spec.text, color = spec.color, target_offset = spec.target_offset, alignment = spec.alignment, use_rich_text = spec.use_rich_text, only_in_alt_mode = spec.only_in_alt_mode, valid = true }; function obj.destroy() obj.valid = false end; return obj end,
    draw_rectangle = function(spec) h.frames[#h.frames + 1] = spec; local obj = { valid = true }; function obj.destroy() obj.valid = false end; return obj end,
    draw_animation = function() local obj = { valid = true }; function obj.destroy() obj.valid = false end; return obj end,
  }
  _G.log = function(msg) h.logs[#h.logs + 1] = msg end
  for name in pairs(package.loaded) do if name == "control" or name:match("^script%.") then package.loaded[name] = nil end end
  _G.require = host_require
  host_require("control")
  _G.require = function() error("Require can't be used outside of control.lua parsing.") end
  function h.fire(name, event) event = event or {}; event.name = event_ids[name]; local fn = h.events[event_ids[name]]; if fn then fn(event) end end
  function h.add_player()
    local p = F.new_player(#_G.game.players + 1, surfaces.nauvis)
    p.on_closed = function(previous) h.fire("on_gui_closed", { player_index = p.index, element = previous.type and previous or nil, entity = not previous.type and previous or nil }) end
    _G.game.players[p.index] = p; _G.game.connected_players[#_G.game.connected_players + 1] = p; h.fire("on_player_created", { player_index = p.index }); return p
  end
  function h.build(name, player, position) local e = new_entity(surfaces.nauvis, { name = name, position = position, force = player.force }); h.fire("on_built_entity", { player_index = player.index, entity = e }); return e end
  function h.build_robot(name, position) local e = new_entity(surfaces.nauvis, { name = name, position = position }); h.fire("on_robot_built_entity", { entity = e }); return e end
  function h.mine(entity, player) entity.valid = false; h.fire("on_player_mined_entity", { player_index = player.index, entity = entity }) end
  function h.open(player, entity) player.opened = entity; h.fire("on_gui_opened", { player_index = player.index, entity = entity }) end
  function h.confirm(player, element) h.fire("on_gui_confirmed", { player_index = player.index, element = element }) end
  function h.text(player, element, text) element.text = text; h.fire("on_gui_text_changed", { player_index = player.index, element = element }) end
  function h.select(player, element, index) element.selected_index = index; h.fire("on_gui_selection_state_changed", { player_index = player.index, element = element }) end
  function h.switch(player, element, state) element.switch_state = state; h.fire("on_gui_switch_state_changed", { player_index = player.index, element = element }) end
  -- Esc/E: the engine asks whatever GUI is open to close.
  function h.escape(player) player.opened = nil end
  function h.run_ticks(n) for _ = 1, n do h.tick = h.tick + 1; for every, fn in pairs(h.nth) do if h.tick % every == 0 then fn({ tick = h.tick }) end end end end
  return h
end
return F
