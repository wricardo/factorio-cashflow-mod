local fake = require("fake_factorio")
local MONTH = 3600
local function eq(actual, expected, message) if actual ~= expected then error((message or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end end
local function setup()
  local h = fake.install({ level = { level_name = "freeplay" } })
  h.init()
  local a, b = h.add_player(), h.add_player()
  return h, a, b
end
local L = fake.localise
local function find(element, name)
  for _, child in ipairs(element.children) do
    if child.valid then
      if child.name == name then return child end
      local deep = find(child, name)
      if deep then return deep end
    end
  end
end
-- The player's open panel (Account dialog on screen, station panels docked left). Elements are
-- looked up by name anywhere inside it, since panels group fields into rows and sections.
local function panel(player)
  local root = player.gui.screen.cf_freeplay_panel or player.gui.left.cf_freeplay_panel
  if not root then return nil end
  return setmetatable({}, { __index = function(_, key) local v = root[key]; if v ~= nil then return v end; return find(root, key) end })
end
local function edit(h, player, element, text) element.text = text; h.confirm(player, element) end
local function link(h, player, entity, index)
  h.open(player, entity)
  h.select(player, panel(player).account, index or 2)
end
local function stations(h, player)
  return h.build("cf-freeplay-income", player), h.build("cf-freeplay-expense", player), h.build("cf-freeplay-cashflow", player), h.build("cf-freeplay-debt", player), h.build("cf-freeplay-vault", player)
end
local T = {}
function T.freeplay_init_does_not_change_world()
  local h, player = setup()
  eq(game.surfaces.nauvis.name, "nauvis"); eq(player.surface.name, "nauvis"); eq(game.speed, 1); eq(next(storage.cf_freeplay.accounts), nil)
end

function T.telemetry_reports_account_interest_state()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  cf.out.interest = 7
  local telemetry = remote.call("cashflow-freeplay", "telemetry")
  local account = telemetry[controller.unit_number]
  eq(account.name, cf.name)
  eq(account.configuration.starting_debt_cents, 1800000)
  eq(account.configuration.starting_assets_cents, 1200000)
  eq(account.debt_accounts, 0)
  eq(account.asset_accounts, 0)
  eq(account.assets_cents, 0)
  eq(account.interest_out_plates, 7)
  eq(account.interest_carry_cents, 0)
end
function T.station_ports_are_east_facing_and_migrate_existing_accounts()
  local h, player = setup()
  local income = h.build("cf-freeplay-income", player)
  local port = storage.cf_freeplay.machines[income.unit_number].entities.out
  eq(port.direction, defines.direction.east)
  port.direction = defines.direction.north
  h.configuration_changed({})
  eq(port.direction, defines.direction.east)
end
function T.station_values_stay_editable_while_running_but_linking_is_locked()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, cashflow, debt, vault }) do link(h, player, entity, 2) end
  local machine = storage.cf_freeplay.machines[income.unit_number]
  eq(machine.port_labels.out.valid, true)
  h.open(player, income)
  h.text(player, panel(player).amount, "10000")
  eq(machine.config.monthly_cents, 1000000)

  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.open(player, income)
  eq(panel(player).amount.enabled, true, "values can change while the account runs")
  eq(panel(player).account.enabled, false, "linking and unlinking wait for a pause")
  eq(panel(player).next_month_note.visible, true, "the panel says when the change applies")
  h.select(player, panel(player).account, 1)
  eq(storage.cf_freeplay.machines[income.unit_number].controller_unit_number, controller.unit_number, "unlinking a running account's station is refused")
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  eq(storage.cf_freeplay.accounts[controller.unit_number].running, false)
end
function T.income_and_expense_amounts_are_capped_at_the_blue_belt_limit()
  local h, player = setup()
  local income, expense = h.build("cf-freeplay-income", player), h.build("cf-freeplay-expense", player)
  local mi, me = storage.cf_freeplay.machines[income.unit_number], storage.cf_freeplay.machines[expense.unit_number]
  h.open(player, income)
  h.text(player, panel(player).amount, "20000")
  eq(mi.config.monthly_cents, 2000000, "exactly $20,000 is allowed")
  h.text(player, panel(player).amount, "25000")
  eq(mi.config.monthly_cents, 2000000, "typing past the cap clamps instead of keeping a stale partial value")
  h.open(player, expense)
  local field = panel(player).amount
  edit(h, player, field, "99999.99")
  eq(me.config.monthly_cents, 2000000)
  eq(field.text, "20000")
  eq(panel(player).error.visible, true, "the cap is explained inline in the panel")
  eq(panel(player).error.caption:find("$20,000", 1, true) ~= nil, true)
  me.config.monthly_cents = 5000000
  h.configuration_changed({})
  eq(me.config.monthly_cents, 2000000, "saves with an over-cap amount are clamped on load")
end
function T.legacy_chest_controller_is_replaced_in_place_keeping_its_account()
  local h, player = setup()
  local old = h.build("cf-freeplay-controller", player, { x = 7, y = 9 })
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, old); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.run_ticks(MONTH + 30)
  local cf = storage.cf_freeplay.accounts[old.unit_number]
  eq(cf.month, 2)
  old.get_inventory().insert({ name = "iron-plate", count = 25 })
  h.open(player, old)
  -- migrations/cashflow-freeplay_0.2.23.json renames the pre-0.2.23 chest before control.lua runs.
  old.name = "cf-freeplay-legacy-controller"
  h.configuration_changed({})
  local new = cf.controller
  eq(old.valid, false)
  eq(new.valid, true); eq(new.name, "cf-freeplay-controller")
  eq(new.position.x, 7); eq(new.position.y, 9)
  eq(storage.cf_freeplay.accounts[old.unit_number], nil)
  eq(storage.cf_freeplay.accounts[new.unit_number], cf, "account is re-keyed, not recreated")
  eq(cf.month, 2); eq(cf.running, true); eq(cf.started, true)
  for _, machine in pairs(cf.machines) do eq(machine.controller_unit_number, new.unit_number) end
  local spilled = game.surfaces.nauvis.spilled[1]
  eq(spilled.stack.name, "iron-plate"); eq(spilled.stack.count, 25)
  eq(panel(player), nil, "a panel tagged with the destroyed controller is closed")
  cf.entities.cashflow[1].entities.cash_in.get_transport_line(1).put("iron-plate", 3)
  h.run_ticks(2)
  eq(cf.stats.cash_in, 3, "the migrated account keeps running its linked stations")
  h.open(player, new)
  eq(L(panel(player).title.caption), "Account: " .. cf.name)
end
local function belt_count(belt, item) return belt.get_transport_line(1).get_item_count(item) + belt.get_transport_line(2).get_item_count(item) end
function T.smelter_pays_its_salary_once_per_month_two_seconds_after_a_full_coal_batch()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  local smelter = h.build("cf-freeplay-smelter", player)
  for _, entity in ipairs({ cashflow, debt, vault, smelter }) do link(h, player, entity, 2) end
  h.open(player, smelter); edit(h, player, panel(player).amount, "500")
  local machine, coal = storage.cf_freeplay.machines[smelter.unit_number], smelter.get_inventory()
  local out = machine.entities.out
  eq(coal.insert({ name = "coal", count = 60 }), 50, "the smelter holds exactly one month's batch")
  h.run_ticks(10)
  eq(coal.get_item_count("coal"), 50, "a paused account does not smelt")
  coal.remove({ name = "coal", count = 1 })
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  h.run_ticks(30)
  eq(coal.get_item_count("coal"), 49, "49 coal is not a batch")
  eq(machine.label.text:find("Coal 49/50", 1, true) ~= nil, true)
  coal.insert({ name = "coal", count = 1 })
  h.run_ticks(2)
  eq(coal.get_item_count("coal"), 0, "the batch is consumed when smelting starts")
  h.run_ticks(118)
  eq(belt_count(out, "iron-plate"), 0, "no salary before 2 seconds of smelting")
  h.run_ticks(2)
  eq(belt_count(out, "iron-plate") > 0, true)
  eq(belt_count(out, "iron-plate") + machine.pending_salary, 50, "$500 salary is 50 plates")
  coal.insert({ name = "coal", count = 50 })
  h.run_ticks(1000)
  eq(coal.get_item_count("coal"), 50, "only one batch per month")
  eq(machine.label.text:find("Paid this month", 1, true) ~= nil, true)
  h.run_ticks(MONTH)
  eq(cf.month, 2)
  eq(coal.get_item_count("coal"), 0, "next month smelts the waiting batch")
  eq(belt_count(out, "iron-plate") + machine.pending_salary, 100)
end
function T.coal_supply_is_unlinked_and_refills_without_an_account()
  local h, player = setup()
  local supply = h.build("cf-freeplay-coal", player)
  local inv = supply.get_inventory()
  eq(inv.get_item_count("coal"), 1000, "placed full")
  h.open(player, supply)
  eq(panel(player), nil, "opening it shows only the vanilla chest window")
  eq(storage.cf_freeplay.machines[supply.unit_number], nil)
  inv.remove({ name = "coal", count = 300 })
  h.run_ticks(30)
  eq(inv.get_item_count("coal"), 1000, "refilled with no controller in the world")
  h.mine(supply, player)
  eq(storage.cf_freeplay.coal_supplies[supply.unit_number], nil)
  h.run_ticks(30)
end

function T.paused_apr_edits_apply_before_resuming_without_confirming()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.open(player, debt)
  h.text(player, panel(player).apr, "0")
  eq(cf.entities.debt[1].config.apr, 0)
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.run_ticks(MONTH)
  eq(cf.last_report.interest_plates, 0)
end
function T.station_chests_hold_monthly_buffers_and_live_balances()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "5000")
  h.open(player, expense); edit(h, player, panel(player).amount, "2000")
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(cf.entities.income[1].anchor.get_inventory().get_item_count("iron-plate"), 500)
  eq(cf.entities.expense[1].anchor.get_inventory().get_item_count("copper-plate"), 200)
  eq(cf.entities.debt[1].anchor.get_inventory().get_item_count("copper-plate"), 1800)
  eq(cf.entities.vault[1].anchor.get_inventory().get_item_count("iron-plate"), 1200)
  cf.entities.cashflow[1].entities.cash_in.get_transport_line(1).put("iron-plate", 3)
  cf.entities.cashflow[1].entities.bills_in.get_transport_line(1).put("copper-plate", 1)
  h.run_ticks(2)
  eq(cf.entities.cashflow[1].anchor.get_inventory().get_item_count("iron-plate"), 2)
  eq(cf.entities.cashflow[1].anchor.get_inventory().get_item_count("copper-plate"), 0)
end
function T.configuration_change_moves_hidden_ledgers_into_station_chests()
  local h, player = setup()
  local debt = h.build("cf-freeplay-debt", player)
  local vault = h.build("cf-freeplay-vault", player)
  local debt_machine = storage.cf_freeplay.machines[debt.unit_number]
  local vault_machine = storage.cf_freeplay.machines[vault.unit_number]
  local ledger = game.surfaces.nauvis.create_entity({ name = "cf-freeplay-ledger", position = debt.position })
  local chest = game.surfaces.nauvis.create_entity({ name = "cf-freeplay-vault-chest", position = vault.position })
  ledger.get_inventory().insert({ name = "copper-plate", count = 12 })
  chest.get_inventory().insert({ name = "iron-plate", count = 34 })
  debt_machine.entities.landmark, vault_machine.entities.chest = ledger, chest
  h.configuration_changed({})
  eq(ledger.valid, false); eq(chest.valid, false)
  eq(debt_machine.anchor.get_inventory().get_item_count("copper-plate"), 12)
  eq(vault_machine.anchor.get_inventory().get_item_count("iron-plate"), 34)
end
function T.empty_cashflow_inputs_do_not_crash_the_sweep()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.run_ticks(2)
  eq(storage.cf_freeplay.accounts[controller.unit_number].running, true)
end
function T.configuration_change_restores_missing_legacy_emitter_buffers()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "500")
  h.open(player, expense); edit(h, player, panel(player).amount, "200")
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  local income_inv, expense_inv = cf.entities.income[1].anchor.get_inventory(), cf.entities.expense[1].anchor.get_inventory()
  income_inv.remove({ name = "iron-plate", count = income_inv.get_item_count("iron-plate") })
  expense_inv.remove({ name = "copper-plate", count = expense_inv.get_item_count("copper-plate") })
  cf.buffered_month = nil
  h.configuration_changed({})
  eq(income_inv.get_item_count("iron-plate"), 50)
  eq(expense_inv.get_item_count("copper-plate"), 20)
end
function T.account_labels_omit_cashflow_while_cashflow_station_displays_it()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "500")
  h.open(player, expense); edit(h, player, panel(player).amount, "200")
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.run_ticks(30)
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(cf.label.text:find("Cashflow", 1, true), nil)
  eq(cf.label.text:find("Assets $12,000 • Debt $18,000 • Net worth -$6,000", 1, true) ~= nil, true)
  local cashflow_machine = storage.cf_freeplay.machines[cashflow.unit_number]
  local debt_machine = storage.cf_freeplay.machines[debt.unit_number]
  local vault_machine = storage.cf_freeplay.machines[vault.unit_number]
  eq(cashflow_machine.label.text, "Cashflow Station • Cashflow +$300/month")
  eq(debt_machine.label.text, "Debt Station • Debt $18,000 • Interest $270/month")
  eq(vault_machine.label.text, "Investment Account • Assets $12,000 • Return $70/month")
  eq(cashflow_machine.port_labels.cash_in.text, "[item=iron-plate] CASH IN")
  eq(cashflow_machine.port_labels.bills_in.text, "[item=copper-plate] BILLS IN")
  eq(cashflow_machine.port_labels.cash_in.use_rich_text, true)
  eq(cashflow_machine.port_labels.cash_in.only_in_alt_mode, true, "port labels only show in alt mode")
  eq(cashflow_machine.label.only_in_alt_mode, nil, "station titles always show")
  eq(cashflow_machine.port_labels.cash_in.color[1], 1)
  eq(cashflow_machine.port_labels.cash_in.color[2], 1)
  eq(cashflow_machine.port_labels.bills_in.color[1], 1)
  eq(cashflow_machine.port_labels.bills_in.color[2], 0.5)
  eq(cashflow_machine.port_labels.surplus_out.color[1], 1)
  eq(cashflow_machine.port_labels.surplus_out.color[2], 1)
  eq(cashflow_machine.port_labels.unpaid_out.color[1], 1)
  eq(cashflow_machine.port_labels.unpaid_out.color[2], 0.5)
  eq(storage.cf_freeplay.machines[income.unit_number].port_labels.out.text, "[item=iron-plate] CASH OUT")
  eq(storage.cf_freeplay.machines[income.unit_number].port_labels.out.color[1], 1)
  eq(storage.cf_freeplay.machines[income.unit_number].port_labels.out.color[2], 1)
  eq(debt_machine.port_labels.pay_in.color[1], 1)
  eq(debt_machine.port_labels.pay_in.color[2], 1)
  eq(debt_machine.port_labels.borrow_in.color[1], 1)
  eq(debt_machine.port_labels.borrow_in.color[2], 0.5)
  eq(vault_machine.port_labels.deposit_in.color[1], 1)
  eq(vault_machine.port_labels.deposit_in.color[2], 1)
  eq(vault_machine.port_labels.return_out.color[1], 1)
  eq(vault_machine.port_labels.return_out.color[2], 1)
  eq(debt_machine.port_labels.interest_out.color[1], 1)
  eq(debt_machine.port_labels.interest_out.color[2], 0.5)
  eq(cashflow_machine.port_labels.cash_in.alignment, "right")
  eq(cashflow_machine.port_labels.surplus_out.alignment, "left")
end

function T.station_hover_status_shows_role_specific_metrics()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  local smelter, coal = h.build("cf-freeplay-smelter", player), h.build("cf-freeplay-coal", player)
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(income.custom_status.label, "Account: Unlinked \n$0/month")
  eq(income.custom_status.diode, defines.entity_status_diode.yellow, "unlinked stations are flagged")
  for _, entity in ipairs({ income, expense, cashflow, debt, vault, smelter }) do link(h, player, entity, 2) end
  eq(income.custom_status.diode, defines.entity_status_diode.green)
  eq(income.custom_status.label, "Account: " .. cf.name .. " \n$0/month")
  eq(expense.custom_status.label, "Account: " .. cf.name .. " \n$0/month \nCategory: needs")
  eq(cashflow.custom_status.label, "Account: " .. cf.name .. " \nCashflow +$0/month")
  eq(debt.custom_status.label, "Account: " .. cf.name .. " \nDebt $0 \nAPR 18% \nInterest $0/month")
  eq(vault.custom_status.label, "Account: " .. cf.name .. " \nAssets $0 \nReturn rate 7% \nReturn $0/month")
  eq(smelter.custom_status.label, "Account: " .. cf.name .. " \n$0 salary/month \nCoal 0/50")
  eq(coal.custom_status.label, "Coal 1000/1000")
  h.open(player, income); edit(h, player, panel(player).amount, "500")
  eq(income.custom_status.label, "Account: " .. cf.name .. " \n$500/month", "status follows configuration edits")
  coal.get_inventory().remove({ name = "coal", count = 400 })
  h.run_ticks(30)
  eq(coal.custom_status.label, "Coal 1000/1000", "the refill loop restocks and refreshes the status")
end
function T.configuration_panels_have_close_buttons()
  local h, player = setup()
  local controller, income = h.build("cf-freeplay-controller", player), h.build("cf-freeplay-income", player)
  h.open(player, controller)
  eq(panel(player).close.tags.cf_freeplay_close, true)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).close })
  eq(panel(player), nil, "controller panel closes")
  h.open(player, income)
  eq(panel(player).close.tags.cf_freeplay_close, true)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).close })
  eq(panel(player), nil, "machine panel closes")
end

function T.panels_start_errors_and_rates_use_the_new_names()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, smelter, vault, debt = h.build("cf-freeplay-income", player), h.build("cf-freeplay-smelter", player), h.build("cf-freeplay-vault", player), h.build("cf-freeplay-debt", player)
  local captions = { [income] = "Passive Income", [smelter] = "Active Income", [vault] = "Investment Account", [debt] = "Debt Station" }
  for entity, caption in pairs(captions) do
    h.open(player, entity)
    eq(L(panel(player).title.caption), caption)
  end
  link(h, player, debt, 2); link(h, player, vault, 2)
  h.open(player, debt); edit(h, player, panel(player).apr, "12")
  eq(debt.custom_status.label:find("APR 12%", 1, true) ~= nil, true, "the configured APR is shown in the hover pane")
  h.open(player, vault); edit(h, player, panel(player)["return"], "5.5")
  eq(vault.custom_status.label:find("Return rate 5.5%", 1, true) ~= nil, true, "the configured return is shown in the hover pane")
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  eq(panel(player).error.caption, "Missing linked Cashflow Station.")
end
function T.freeplay_allows_normal_buildings_and_items()
  local h, player = setup()
  local ghost = { valid = true, name = "entity-ghost", ghost_name = "assembling-machine-1" }
  function ghost.destroy() ghost.valid = false end
  h.fire("on_built_entity", { player_index = player.index, entity = ghost })
  eq(ghost.valid, true)
  eq(h.build("assembling-machine-1", player).valid, true)
  eq(h.build("roboport", player).valid, true)
  eq(h.build("electric-energy-interface", player).valid, true)
  local income = h.build_robot("cf-freeplay-income")
  eq(storage.cf_freeplay.machines[income.unit_number].role, "income")
end
function T.required_station_removal_pauses_the_account()
  local h, player = setup()

  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.mine(debt, player)
  h.run_ticks(2)
  eq(storage.cf_freeplay.accounts[controller.unit_number].running, false)
end

function T.month_close_keeps_pending_station_outputs()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  storage.cf_freeplay.accounts[controller.unit_number].entities.cashflow[1].entities.cash_in.get_transport_line(1).insert_at_back({ name = "iron-plate", count = 10 })
  h.run_ticks(MONTH)
  eq(storage.cf_freeplay.accounts[controller.unit_number].out.surplus, 10)
end
function T.account_label_shows_year_and_month_and_rolls_over()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(cf.label.text:find("Year 1 Month 1", 1, true) ~= nil, true)
  h.run_ticks(MONTH + 30)
  eq(cf.month, 2)
  eq(cf.label.text:find("Year 1 Month 2", 1, true) ~= nil, true)
  h.run_ticks(MONTH * 11)
  eq(cf.month, 13)
  eq(cf.label.text:find("Year 2 Month 1", 1, true) ~= nil, true)
end
function T.cashflow_station_label_counts_returns_routed_back_as_cash_not_just_income_minus_expense()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local cashflow = h.build("cf-freeplay-cashflow", player)
  local debt = h.build("cf-freeplay-debt", player)
  local vault = h.build("cf-freeplay-vault", player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  h.run_ticks(MONTH)
  h.run_ticks(2)
  local vault_machine = cf.entities.vault[1]
  local function drain(line)
    local n = line.get_item_count("iron-plate")
    if n > 0 then line.remove_item({ name = "iron-plate", count = n }) end
    return n
  end
  local returned = drain(vault_machine.entities.return_out.get_transport_line(1)) + drain(vault_machine.entities.return_out.get_transport_line(2))
  eq(returned, 7, "default 7% on $12,000 starting assets")
  cf.entities.cashflow[1].entities.cash_in.get_transport_line(1).put("iron-plate", returned)
  h.run_ticks(MONTH - 2)
  eq(cf.last_report.cash_in, 7)
  eq(cf.last_report.bills_in, 0)
  eq(cf.entities.cashflow[1].label.text:find("Cashflow +$70/month", 1, true) ~= nil, true, "no income station at all, yet returns routed to CASH IN must show as cashflow")
end
function T.controllers_are_independent_and_configuration_is_player_routed()
  local h, a, b = setup()
  local ca, cb = h.build("cf-freeplay-controller", a), h.build("cf-freeplay-controller", b)
  h.open(a, ca); edit(h, a, panel(a).account_name, "Alpha")
  h.open(b, cb); edit(h, b, panel(b).account_name, "Beta")
  eq(storage.cf_freeplay.accounts[ca.unit_number].name, "Alpha"); eq(storage.cf_freeplay.accounts[cb.unit_number].name, "Beta")
  local ai, ae, ac, ad, av = stations(h, a)
  local bi, be, bc, bd, bv = stations(h, b)
  for _, entity in ipairs({ ai, ae, ac, ad, av }) do link(h, a, entity, 2) end
  for _, entity in ipairs({ bi, be, bc, bd, bv }) do link(h, b, entity, 3) end
  h.open(a, ai); edit(h, a, panel(a).amount, "5000")
  h.open(b, bi); edit(h, b, panel(b).amount, "1000")
  h.open(a, ca); h.fire("on_gui_click", { player_index = a.index, element = panel(a).toggle })
  h.open(b, cb); h.fire("on_gui_click", { player_index = b.index, element = panel(b).toggle })
  h.run_ticks(MONTH)
  eq(storage.cf_freeplay.accounts[ca.unit_number].last_report ~= nil, true)
  eq(storage.cf_freeplay.accounts[cb.unit_number].last_report ~= nil, true)
  eq(storage.cf_freeplay.accounts[ca.unit_number].plan.income[ai.unit_number], 500)
  eq(storage.cf_freeplay.accounts[cb.unit_number].plan.income[bi.unit_number], 100)
end
function T.debt_and_vault_inputs_are_account_local()
  local h, a, b = setup()
  local ca, cb = h.build("cf-freeplay-controller", a), h.build("cf-freeplay-controller", b)
  local _, _, ac, ad, av = stations(h, a)
  local _, _, bc, bd, bv = stations(h, b)
  for _, entity in ipairs({ ac, ad, av }) do link(h, a, entity, 2) end
  for _, entity in ipairs({ bc, bd, bv }) do link(h, b, entity, 3) end
  h.open(a, ca); h.fire("on_gui_click", { player_index = a.index, element = panel(a).toggle })
  h.open(b, cb); h.fire("on_gui_click", { player_index = b.index, element = panel(b).toggle })
  storage.cf_freeplay.accounts[ca.unit_number].entities.debt[1].entities.borrow_in.get_transport_line(1).insert_at_back({ name = "copper-plate", count = 3 })
  storage.cf_freeplay.accounts[ca.unit_number].entities.vault[1].entities.deposit_in.get_transport_line(1).insert_at_back({ name = "iron-plate", count = 4 })
  h.run_ticks(2)
  eq(storage.cf_freeplay.accounts[ca.unit_number].debt_cents, 1803000)
  eq(storage.cf_freeplay.accounts[cb.unit_number].debt_cents, 1800000)
  eq(storage.cf_freeplay.accounts[ca.unit_number].entities.debt[1].anchor.get_inventory().get_item_count("copper-plate"), 1803)
  eq(storage.cf_freeplay.accounts[ca.unit_number].entities.vault[1].anchor.get_inventory().get_item_count("iron-plate"), 1204)
end
function T.invalid_configuration_preserves_prior_value_and_deleted_controller_unlinks_stations()

  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income = h.build("cf-freeplay-income", player)
  local debt = h.build("cf-freeplay-debt", player)
  link(h, player, income, 2)
  link(h, player, debt, 2)
  h.open(player, debt); local old = storage.cf_freeplay.machines[debt.unit_number].config.apr
  edit(h, player, panel(player).apr, "not-a-number")
  eq(storage.cf_freeplay.machines[debt.unit_number].config.apr, old)
  h.mine(controller, player)
  eq(storage.cf_freeplay.machines[income.unit_number].controller_unit_number, nil)
end
function T.copper_on_pay_in_does_not_increase_debt()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  cf.entities.debt[1].entities.pay_in.get_transport_line(1).insert_at_back({ name = "copper-plate", count = 3 })
  h.run_ticks(2)
  eq(cf.debt_cents, 1800000)
end

function T.station_buildings_keep_every_port_outside_its_footprint()
  local h, player = setup()
  local income = h.build("cf-freeplay-income", player, { x = 10, y = 10 })
  local cashflow = h.build("cf-freeplay-cashflow", player, { x = 30, y = 30 })
  local debt = h.build("cf-freeplay-debt", player, { x = 50, y = 50 })
  local vault = h.build("cf-freeplay-vault", player, { x = 70, y = 70 })
  eq(storage.cf_freeplay.machines[income.unit_number].entities.out.position.x, 12)
  local cashflow_ports = storage.cf_freeplay.machines[cashflow.unit_number].entities
  eq(cashflow_ports.cash_in.position.x, 26)
  eq(cashflow_ports.cash_in.position.y, 28)
  eq(cashflow_ports.cash_in_2.position.x, 26)
  eq(cashflow_ports.cash_in_2.position.y, 26)
  eq(cashflow_ports.bills_in_2.position.x, 26)
  eq(cashflow_ports.bills_in_2.position.y, 34)
  eq(cashflow_ports.unpaid_out.position.x, 34)
  eq(cashflow_ports.unpaid_out.position.y, 32)
  local debt_ports = storage.cf_freeplay.machines[debt.unit_number].entities
  eq(debt_ports.borrow_in.position.x, 48)
  eq(debt_ports.pay_in.position.y, 49, "PAY IN is the top input")
  eq(debt_ports.borrow_in.position.y, 51, "BORROW IN is the bottom input")
  eq(debt_ports.interest_out.position.x, 52)
  local warehouse = storage.cf_freeplay.machines[vault.unit_number]
  eq(warehouse.label.text, "Investment Account • Assets $0 • Return $0/month")
  eq(warehouse.entities.deposit_in.position.x, 66)
  eq(warehouse.entities.return_out.position.x, 74)
end

function T.existing_debt_stations_keep_their_wired_ports_when_the_layout_changes()
  local h, player = setup()
  local debt = h.build("cf-freeplay-debt", player, { x = 50, y = 50 })
  local ports = storage.cf_freeplay.machines[debt.unit_number].entities
  -- A station built before the swap has BORROW IN on top and PAY IN below.
  ports.borrow_in.position.y, ports.pay_in.position.y = 49, 51
  h.configuration_changed({})
  eq(ports.borrow_in.position.y, 49, "belts players already connected must not change meaning")
  eq(ports.pay_in.position.y, 51)
end

function T.station_building_upgrade_notifies_existing_saves()
  local h = setup()
  storage.cf_freeplay.station_layout_version = 1
  h.configuration_changed({})
  eq(storage.cf_freeplay.station_layout_version, 2)
  assert(h.logs[#h.logs]:match("Mine and re%-place every station"), "migration notice")
end

function T.multiple_debt_and_asset_accounts_split_opening_balances()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local cashflow = h.build("cf-freeplay-cashflow", player)
  local debt_a, debt_b = h.build("cf-freeplay-debt", player), h.build("cf-freeplay-debt", player)
  local vault_a, vault_b = h.build("cf-freeplay-vault", player), h.build("cf-freeplay-vault", player)
  for _, entity in ipairs({ cashflow, debt_a, debt_b, vault_a, vault_b }) do link(h, player, entity, 2) end
  h.open(player, debt_b); edit(h, player, panel(player).apr, "12")
  h.open(player, vault_b); edit(h, player, panel(player)["return"], "6")
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(#cf.entities.debt, 2)
  eq(#cf.entities.vault, 2)
  eq(cf.entities.debt[1].anchor.get_inventory().get_item_count("copper-plate"), 900)
  eq(cf.entities.debt[2].anchor.get_inventory().get_item_count("copper-plate"), 900)
  eq(cf.entities.vault[1].anchor.get_inventory().get_item_count("iron-plate"), 600)
  eq(cf.entities.vault[2].anchor.get_inventory().get_item_count("iron-plate"), 600)
  eq(cf.entities.debt[2].config.apr, 12)
  eq(cf.entities.vault[2].config.asset_return, 6)
  eq(cf.debt_cents, 1800000)
  eq(cf.label.text:find("Assets $12,000 • Debt $18,000", 1, true) ~= nil, true)
end
function T.cashflow_station_has_a_second_cash_and_bills_line()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  local entities = cf.entities.cashflow[1].entities
  entities.cash_in.get_transport_line(1).put("iron-plate", 3)
  entities.cash_in_2.get_transport_line(1).put("iron-plate", 4)
  entities.bills_in.get_transport_line(1).put("copper-plate", 1)
  entities.bills_in_2.get_transport_line(1).put("copper-plate", 2)
  h.run_ticks(2)
  eq(cf.entities.cashflow[1].anchor.get_inventory().get_item_count("iron-plate"), 4)
  eq(cf.entities.cashflow[1].anchor.get_inventory().get_item_count("copper-plate"), 0)
  eq(cf.stats.cash_in, 7)
  eq(cf.stats.bills_in, 3)
end
function T.multiple_cashflow_stations_pool_settlement_and_share_outputs()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local a, b = h.build("cf-freeplay-cashflow", player), h.build("cf-freeplay-cashflow", player)
  local debt, vault = h.build("cf-freeplay-debt", player), h.build("cf-freeplay-vault", player)
  for _, entity in ipairs({ a, b, debt, vault }) do link(h, player, entity, 2) end
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(#cf.entities.cashflow, 2, "a second Cashflow station links to the same controller")
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  eq(cf.running, true)
  local ma, mb = cf.entities.cashflow[1], cf.entities.cashflow[2]
  ma.entities.cash_in.get_transport_line(1).put("iron-plate", 12)
  mb.entities.bills_in.get_transport_line(1).put("copper-plate", 2)
  h.run_ticks(2)
  eq(cf.stats.paid, 2, "cash in station A pays bills in station B")
  eq(ma.anchor.get_inventory().get_item_count("iron-plate"), 10)
  eq(mb.anchor.get_inventory().get_item_count("copper-plate"), 0)
  h.run_ticks(MONTH - 2)
  eq(cf.last_report.cash_in, 12); eq(cf.last_report.bills_in, 2); eq(cf.last_report.surplus_plates, 10)
  h.run_ticks(2)
  local function belt(machine) local e = machine.entities.surplus_out; return e.get_transport_line(1).get_item_count("iron-plate") + e.get_transport_line(2).get_item_count("iron-plate") end
  eq(belt(ma), 5, "surplus is spread round-robin across every station's SURPLUS OUT")
  eq(belt(mb), 5)
  eq(cf.out.surplus, 0)
end
function T.legacy_single_cashflow_station_migrates_to_a_list()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  local machine = cf.entities.cashflow[1]
  cf.entities.cashflow = machine
  h.configuration_changed({})
  eq(#cf.entities.cashflow, 1); eq(cf.entities.cashflow[1], machine)
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  eq(cf.running, true)
  machine.entities.cash_in.get_transport_line(1).put("iron-plate", 3)
  h.run_ticks(2)
  eq(cf.stats.cash_in, 3)
end
function T.configuration_change_recreates_a_missing_second_input_line()
  local h, player = setup()
  local cashflow = h.build("cf-freeplay-cashflow", player)
  local machine = storage.cf_freeplay.machines[cashflow.unit_number]
  machine.entities.cash_in_2.destroy()
  machine.entities.cash_in_2 = nil
  h.configuration_changed({})
  eq(machine.entities.cash_in_2.valid, true)
  eq(machine.entities.cash_in_2.direction, defines.direction.east)
  eq(machine.entities.cash_in_2.position.x, machine.anchor.position.x - 4)
  eq(machine.entities.cash_in_2.position.y, machine.anchor.position.y - 4)
end
function T.debt_chest_copper_is_the_real_balance_manual_edits_stick()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  local debt_machine = cf.entities.debt[1]
  local inv = debt_machine.anchor.get_inventory()
  eq(inv.get_item_count("copper-plate"), 1800)
  inv.remove({ name = "copper-plate", count = 500 })
  h.run_ticks(2)
  eq(inv.get_item_count("copper-plate"), 1300, "manual removal must not be resynced back")
  eq(cf.debt_cents, 1300000)
end
function T.pay_in_iron_cannot_exceed_existing_debt()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  local debt_machine = cf.entities.debt[1]
  local inv = debt_machine.anchor.get_inventory()
  inv.remove({ name = "copper-plate", count = inv.get_item_count("copper-plate") })
  local pay_line = debt_machine.entities.pay_in.get_transport_line(1)
  pay_line.put("iron-plate", 10)
  h.run_ticks(2)
  eq(inv.get_item_count("copper-plate"), 0)
  eq(cf.stats.debt_paid, 0, "no debt, so no iron should be consumed")
  eq(pay_line.get_item_count("iron-plate"), 10)
  inv.insert({ name = "copper-plate", count = 5 })
  h.run_ticks(2)
  eq(inv.get_item_count("copper-plate"), 0, "iron pays off exactly the existing debt")
  eq(cf.stats.debt_paid, 5)
  eq(pay_line.get_item_count("iron-plate"), 5, "iron beyond the existing debt stays on the belt")
end

-- A running account with the three required stations; returns everything the tests below poke at.
local function running_account(h, player)
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(cf.running, true)
  return cf, cashflow
end

function T.a_yearly_report_closes_every_twelfth_month_and_nothing_wins()
  local h, player = setup()
  local cf = running_account(h, player)
  local station = cf.entities.cashflow[1].entities
  for _ = 1, 11 do
    station.cash_in.get_transport_line(1).put("iron-plate", 10)
    station.bills_in.get_transport_line(1).put("copper-plate", 4)
    h.run_ticks(MONTH)
  end
  eq(cf.month, 12)
  eq(#cf.year_reports, 0, "no report before the year ends")
  station.cash_in.get_transport_line(1).put("iron-plate", 10)
  station.bills_in.get_transport_line(1).put("copper-plate", 4)
  h.run_ticks(MONTH)
  eq(cf.month, 13)
  eq(#cf.year_reports, 1)
  local report = cf.year_reports[1]
  eq(report.year, 1)
  eq(report.income_cents, 12 * 10 * 1000, "twelve months of 10 settled cash plates")
  eq(report.expense_cents, 12 * 4 * 1000, "twelve months of 4 settled bill plates")
  eq(report.assets_cents, 1200000)
  eq(report.debt_cents, cf.debt_cents)
  eq(report.net_worth_cents, report.assets_cents - report.debt_cents)
  eq(cf.year_totals.cash_in, 0, "the next year starts from zero")
  eq(cf.won, nil, "there is no winning condition")
  local announced = player.prints[#player.prints]
  eq(announced:find("Year 1 report", 1, true) ~= nil, true)
  eq(announced:find("Income $1,200 • Expenses $480", 1, true) ~= nil, true)
  eq(announced:find("Net worth", 1, true) ~= nil, true)
  h.open(player, cf.controller)
  local cells = {}
  for _, child in ipairs(panel(player).reports_table.children) do cells[#cells + 1] = child.caption end
  eq(cells[7], "1"); eq(cells[8], "$1,200"); eq(cells[9], "$480")
  eq(panel(player).reports.visible, true, "the Account panel lists the yearly report")
end

function T.unpaid_bills_stuck_on_a_blocked_unpaid_out_raise_an_alert()
  local h, player = setup()
  local cf, cashflow = running_account(h, player)
  cf.out.unpaid = 40
  h.run_ticks(400)
  eq(#player.alerts > 0, true, "an alert fires once nothing can leave UNPAID OUT for 5 seconds")
  local alert = player.alerts[1]
  eq(alert.entity, cashflow)
  eq(alert.icon.name, "copper-plate")
  eq(alert.message:find("UNPAID OUT is blocked", 1, true) ~= nil, true)
  eq(cashflow.custom_status.diode, defines.entity_status_diode.red)
  eq(cashflow.custom_status.label:find("UNPAID OUT blocked", 1, true) ~= nil, true)
end

function T.unpaid_bills_that_keep_flowing_do_not_alert()
  local h, player = setup()
  local cf = running_account(h, player)
  -- A backlog far larger than the belt: pending bills stay above zero the whole time, but every
  -- sweep some of them leave, so this is slow traffic rather than a blockage.
  cf.out.unpaid = 4000
  local belt = cf.entities.cashflow[1].entities.unpaid_out
  for _ = 1, 200 do
    h.run_ticks(2)
    for lane = 1, 2 do belt.get_transport_line(lane).remove_item({ name = "copper-plate", count = 99 }) end
  end
  eq(cf.out.unpaid > 0 and cf.out.unpaid < 4000, true, "bills are still pending and still moving")
  eq(#player.alerts, 0)
end

function T.month_length_setting_sets_the_month_but_not_the_station_cap()
  local h = fake.install({ level = { level_name = "freeplay" }, settings = { ["cf-freeplay-month-seconds"] = 30 } })
  h.init()
  local player = h.add_player()
  local controller = h.build("cf-freeplay-controller", player)
  local income, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "1000")
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  h.run_ticks(1798)
  eq(cf.month, 1, "a 30 second month is still open at 1798 ticks")
  eq(cf.emitted.income[income.unit_number], 100, "all 100 planned plates were released when the month started")
  h.run_ticks(2)
  eq(cf.month, 2, "and the month closes at 1800 ticks")
  local spare = h.build("cf-freeplay-income", player)
  local machine = storage.cf_freeplay.machines[spare.unit_number]
  h.open(player, spare)
  h.text(player, panel(player).amount, "15000")
  eq(machine.config.monthly_cents, 1500000, "a 30 second month still allows amounts up to $20,000")
  h.text(player, panel(player).amount, "25000")
  eq(machine.config.monthly_cents, 2000000, "and the cap is $20,000 whatever the month length")
  settings.global["cf-freeplay-month-seconds"].value = 15
  h.fire("on_runtime_mod_setting_changed", { setting = "cf-freeplay-month-seconds" })
  eq(machine.config.monthly_cents, 2000000, "shortening the month later does not clamp existing stations")
end

function T.percent_splitter_drives_its_priority_from_the_configured_share()
  local h, player = setup()
  local splitter = h.build("cf-freeplay-percent-splitter", player)
  local rec = storage.cf_freeplay.splitters[splitter.unit_number]
  eq(rec.percent, 50, "defaults to an even split")
  eq(rec.label.text, "Split 50% left • 50% right")
  eq(splitter.custom_status.label, "Left 50% \nRight 50%")
  h.open(player, splitter)
  edit(h, player, panel(player).percent, "30")
  eq(rec.percent, 30)
  eq(panel(player).summary.caption, "Left 30% • Right 70%")
  eq(splitter.custom_status.label, "Left 30% \nRight 70%")
  local lefts = 0
  for _ = 1, 100 do
    h.run_ticks(1)
    if splitter.splitter_output_priority == "left" then lefts = lefts + 1 end
  end
  eq(lefts, 30, "30% of any 100 consecutive ticks favour the left output")
  edit(h, player, panel(player).percent, "250")
  eq(rec.percent, 100, "shares clamp to 100")
  eq(panel(player).percent.text, "100")
  edit(h, player, panel(player).percent, "abc")
  eq(rec.percent, 100, "invalid text leaves the share alone")
  eq(panel(player).error.caption, "Enter a percent from 0 to 100.")
  h.run_ticks(1)
  eq(splitter.splitter_output_priority, "left", "100% always prioritises the left")
end

function T.percent_splitter_cleans_up_and_is_settable_through_the_remote_interface()
  local h, player = setup()
  local splitter, income = h.build("cf-freeplay-percent-splitter", player), h.build("cf-freeplay-income", player)
  local rec = storage.cf_freeplay.splitters[splitter.unit_number]
  eq(remote.call("cashflow-freeplay", "set_splitter_percent", splitter, 20), true)
  eq(rec.percent, 20)
  eq(remote.call("cashflow-freeplay", "set_splitter_percent", income, 20), false, "only Percent Splitters qualify")
  local label = rec.label
  h.mine(splitter, player)
  eq(storage.cf_freeplay.splitters[splitter.unit_number], nil)
  eq(label.valid, false, "its world label is destroyed with it")
  local other = h.build("cf-freeplay-percent-splitter", player)
  other.valid = false
  h.run_ticks(1)
  eq(next(storage.cf_freeplay.splitters), nil, "a splitter removed without an event is dropped on the next tick")
end

function T.income_and_expense_release_the_whole_month_as_soon_as_it_starts()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "30")
  h.open(player, expense); edit(h, player, panel(player).amount, "20")
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.run_ticks(2)
  local mi, me = storage.cf_freeplay.machines[income.unit_number], storage.cf_freeplay.machines[expense.unit_number]
  eq(belt_count(mi.entities.out, "iron-plate"), 3, "3 planned income plates are on the belt after the first sweep")
  eq(belt_count(me.entities.out, "copper-plate"), 2, "2 planned expense plates are on the belt after the first sweep")
  eq(income.get_inventory().get_item_count("iron-plate"), 0, "the income chest is already empty")
end

function T.a_month_larger_than_the_belt_drains_at_belt_speed_not_month_pace()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "1000")
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  h.run_ticks(2)
  local machine = storage.cf_freeplay.machines[income.unit_number]
  local belt = machine.entities.out
  eq(belt_count(belt, "iron-plate"), 8, "the belt is full after the first sweep")
  eq(machine.out, 92, "the other 92 plates are owed and wait for room")
  for lane = 1, 2 do belt.get_transport_line(lane).remove_item({ name = "iron-plate", count = 99 }) end
  h.run_ticks(2)
  eq(belt_count(belt, "iron-plate"), 8, "as soon as the belt has room it takes more, with no per-tick pacing")
  eq(machine.out, 84)
end

local function click(h, player, element) h.fire("on_gui_click", { player_index = player.index, element = element }) end

function T.escape_closes_the_account_dialog_and_docked_station_panels()
  local h, player = setup()
  local controller, income, expense = h.build("cf-freeplay-controller", player), h.build("cf-freeplay-income", player), h.build("cf-freeplay-expense", player)
  h.open(player, controller)
  local dialog = player.gui.screen.cf_freeplay_panel
  eq(dialog ~= nil, true, "the Account is a dialog, and closing its own market window did not close it")
  eq(player.opened, dialog, "it is registered as the open GUI so Esc and E close it")
  h.escape(player)
  eq(panel(player), nil, "Esc closes the Account dialog")
  h.open(player, income)
  eq(player.gui.left.cf_freeplay_panel ~= nil, true, "station panels dock beside the vanilla window")
  h.escape(player)
  eq(panel(player), nil, "closing the vanilla station window closes its panel")
  h.open(player, income); h.open(player, expense)
  eq(L(panel(player).title.caption), "Expense Station", "opening another station replaces the panel")
  h.open(player, controller)
  eq(player.gui.left.cf_freeplay_panel, nil, "opening the Account closes a docked station panel")
  eq(panel(player) ~= nil, true)
end

function T.account_dashboard_shows_the_start_checklist_and_tracks_the_month_live()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  h.open(player, controller)
  eq(panel(player).toggle.enabled, false, "Start is disabled until the required stations are linked")
  eq(L(panel(player).req_debt.caption):find("missing", 1, true) ~= nil, true)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "500")
  h.open(player, expense); edit(h, player, panel(player).amount, "200")
  h.open(player, controller)
  eq(panel(player).toggle.enabled, true)
  eq(L(panel(player).req_debt.caption):find("linked", 1, true) ~= nil, true)
  click(h, player, panel(player).toggle)
  eq(panel(player).checklist.visible, false, "the checklist is only for getting started")
  local name_field = panel(player).account_name
  h.run_ticks(1800)
  eq(panel(player).account_name, name_field, "the live refresh updates in place and never rebuilds a field being edited")
  eq(name_field.valid, true)
  eq(name_field.enabled, true, "the name is cosmetic and can change any time")
  edit(h, player, name_field, "Renamed")
  eq(storage.cf_freeplay.accounts[controller.unit_number].name, "Renamed")
  eq(L(panel(player).title.caption), "Account: Renamed")
  local bar = panel(player).month_bar.value
  eq(bar > 0.45 and bar < 0.55, true, "half the month has elapsed, got " .. tostring(bar))
  eq(L(panel(player).month_text.caption), "Year 1 • Month 1 • Running")
  eq(panel(player).stat_assets.caption, "$12,000")
  eq(panel(player).stat_debt.caption, "$18,000")
  eq(panel(player).stat_networth.caption, "-$6,000")
  eq(panel(player).stat_cashflow.caption, "+$300")
  eq(L(panel(player).coverage_text.caption), "Investment returns cover $70 of $200 monthly expenses")
  eq(math.abs(panel(player).coverage_bar.value - 0.35) < 0.001, true)
  eq(L(panel(player).toggle.caption), "Pause")
  click(h, player, panel(player).toggle)
  eq(panel(player).debt, nil, "after the first Start the starting debt is a fact, not an editable field")
  local locked = false
  for _, child in ipairs(panel(player).setup.children) do
    if type(child.caption) == "table" and L(child.caption) == "Starting debt: $18,000 (locked after first Start)" then locked = true end
  end
  eq(locked, true)
end

function T.accounts_with_the_same_name_are_told_apart_in_the_picker_and_can_be_located()
  local h, player = setup()
  local controllers = {}
  for i = 0, 7 do
    controllers[#controllers + 1] = h.build("cf-freeplay-controller", player, { x = i * 10, y = 0 })
    storage.cf_freeplay.accounts[controllers[#controllers].unit_number].name = "Same"
  end
  local income = h.build("cf-freeplay-income", player)
  local machine = storage.cf_freeplay.machines[income.unit_number]
  h.open(player, income)
  local items = panel(player).account.items
  eq(#items, 9)
  for i = 0, 7 do eq(L(items[i + 2]), "Same (" .. i * 10 .. ", 0)", "equal names list in placement order") end
  click(h, player, panel(player).locate)
  eq(L(panel(player).error.caption), "Select an account first.")
  h.select(player, panel(player).account, 5)
  eq(machine.controller_unit_number, controllers[4].unit_number, "the fourth entry is the account at (30, 0), not a name match")
  click(h, player, panel(player).locate)
  eq(L(player.prints[#player.prints]), "Same is at [gps=30,0,nauvis]")
end

function T.expense_category_is_a_switch_that_stays_editable_while_running()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  local machine = storage.cf_freeplay.machines[expense.unit_number]
  h.open(player, expense)
  eq(panel(player).category.switch_state, "left", "needs by default")
  h.switch(player, panel(player).category, "right")
  eq(machine.config.category, "wants")
  eq(expense.custom_status.label:find("Category: wants", 1, true) ~= nil, true, "the hover pane follows the switch")
  h.open(player, controller); click(h, player, panel(player).toggle)
  h.open(player, expense)
  eq(panel(player).category.enabled, true)
  h.switch(player, panel(player).category, "left")
  eq(machine.config.category, "needs", "a running account accepts the change")
end

function T.amounts_and_rates_edited_while_running_apply_from_next_month()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "500")
  h.open(player, controller); click(h, player, panel(player).toggle)
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  h.open(player, income); edit(h, player, panel(player).amount, "1000")
  h.open(player, debt); h.text(player, panel(player).apr, "0")
  h.open(player, vault); h.text(player, panel(player)["return"], "0")
  eq(cf.plan.income[income.unit_number], 50, "this month's plan is already fixed")
  h.run_ticks(MONTH)
  eq(cf.last_report.interest_cents, 27000, "the month that just ended still used its 18% APR")
  eq(cf.last_report.return_cents, 7000, "and its 7% return")
  eq(cf.plan.income[income.unit_number], 100, "the new amount plans next month")
  h.run_ticks(MONTH)
  eq(cf.last_report.interest_cents, 0, "the 0% APR applies from the second close")
  eq(cf.last_report.return_cents, 0)
end

function T.rate_edits_made_while_paused_still_apply_to_this_month()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local _, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller); click(h, player, panel(player).toggle)
  click(h, player, panel(player).toggle)
  h.open(player, debt); h.text(player, panel(player).apr, "0")
  h.open(player, controller); click(h, player, panel(player).toggle)
  h.run_ticks(MONTH)
  eq(storage.cf_freeplay.accounts[controller.unit_number].last_report.interest_cents, 0)
end

function T.connection_hints_collapse_and_are_remembered_per_player()
  local h, a, b = setup()
  local cashflow, debt = h.build("cf-freeplay-cashflow", a), h.build("cf-freeplay-debt", a)
  h.open(a, cashflow)
  eq(panel(a).hints_text.visible, true, "hints are open for new players")
  eq(L(panel(a).hints_text.caption):find("SURPLUS OUT", 1, true) ~= nil, true)
  click(h, a, panel(a).hints_toggle)
  eq(panel(a).hints_text.visible, false)
  eq(L(panel(a).hints_toggle.caption), "Show how to connect")
  h.open(a, debt)
  eq(panel(a).hints_text.visible, false, "the choice carries over to other stations")
  h.open(b, cashflow)
  eq(panel(b).hints_text.visible, true, "other players are unaffected")
end

function T.closing_a_month_floats_a_summary_above_each_cashflow_station()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local cashflow, debt, vault = h.build("cf-freeplay-cashflow", player), h.build("cf-freeplay-debt", player), h.build("cf-freeplay-vault", player)
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, controller); click(h, player, panel(player).toggle)
  storage.cf_freeplay.accounts[controller.unit_number].entities.cashflow[1].entities.cash_in.get_transport_line(1).put("iron-plate", 7)
  h.run_ticks(MONTH)
  eq(#player.flying_texts, 1)
  eq(player.flying_texts[1].position, cashflow.position)
  eq(player.flying_texts[1].text:find("Year 1 Month 1 closed\nCash in $70", 1, true) ~= nil, true, player.flying_texts[1].text)
end

function T.income_labels_show_how_many_plates_still_wait_for_the_belt()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, _, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "10000")
  local machine = storage.cf_freeplay.machines[income.unit_number]
  h.open(player, controller); click(h, player, panel(player).toggle)
  h.run_ticks(60)
  eq(machine.label.text:find("992 plates left to send", 1, true) ~= nil, true, machine.label.text)
  local belt = machine.entities.out
  for lane = 1, 2 do belt.get_transport_line(lane).remove_item({ name = "iron-plate", count = 99 }) end
  h.run_ticks(60)
  eq(machine.label.text:find("984 plates left to send", 1, true) ~= nil, true, "the label follows the belt draining")
  h.open(player, controller); click(h, player, panel(player).toggle)
  h.run_ticks(30)
  eq(machine.label.text:find("plates left", 1, true), nil, "a paused account shows no send status")
end

local function resolve_captions(element)
  if type(element.caption) == "table" then L(element.caption) end
  if type(element.tooltip) == "table" and element.tooltip[1] ~= "gui.close-instruction" then L(element.tooltip) end
  for _, item in ipairs(element.items or {}) do L(item) end
  for _, key in ipairs({ "left_label_caption", "right_label_caption" }) do if element[key] then L(element[key]) end end
  for _, child in ipairs(element.children) do resolve_captions(child) end
end
function T.every_panel_caption_resolves_to_a_real_locale_string()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  local smelter, splitter = h.build("cf-freeplay-smelter", player), h.build("cf-freeplay-percent-splitter", player)
  local all = { income, expense, cashflow, debt, vault, smelter }
  local function check(entity) h.open(player, entity); resolve_captions(player.gui.screen.cf_freeplay_panel or player.gui.left.cf_freeplay_panel) end
  check(controller); check(splitter)
  for _, entity in ipairs(all) do check(entity) end
  for _, entity in ipairs({ cashflow, debt, vault }) do link(h, player, entity, 2) end
  check(controller)
  h.open(player, controller); click(h, player, panel(player).toggle)
  resolve_captions(panel(player))
  h.run_ticks(MONTH)
  h.open(player, controller)
  resolve_captions(panel(player))
  for _, entity in ipairs(all) do check(entity) end
end
return T
