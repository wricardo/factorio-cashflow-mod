local fake = require("fake_factorio")
local MONTH = 3600
local function eq(actual, expected, message) if actual ~= expected then error((message or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end end
local function setup()
  local h = fake.install({ level = { level_name = "freeplay" } })
  h.init()
  local a, b = h.add_player(), h.add_player()
  return h, a, b
end
local function panel(player) return player.gui.left.cf_freeplay_panel end
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
function T.station_ports_are_labeled_and_amounts_save_while_paused()
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
  eq(panel(player).amount.enabled, false)
  h.open(player, controller)
  h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  eq(storage.cf_freeplay.accounts[controller.unit_number].running, false)
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
  cf.entities.cashflow.entities.cash_in.get_transport_line(1).put("iron-plate", 3)
  cf.entities.cashflow.entities.bills_in.get_transport_line(1).put("copper-plate", 1)
  h.run_ticks(2)
  eq(cf.entities.cashflow.anchor.get_inventory().get_item_count("iron-plate"), 2)
  eq(cf.entities.cashflow.anchor.get_inventory().get_item_count("copper-plate"), 0)
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
function T.account_and_port_labels_show_balances_without_station_account_names()
  local h, player = setup()
  local controller = h.build("cf-freeplay-controller", player)
  local income, expense, cashflow, debt, vault = stations(h, player)
  for _, entity in ipairs({ income, expense, cashflow, debt, vault }) do link(h, player, entity, 2) end
  h.open(player, income); edit(h, player, panel(player).amount, "500")
  h.open(player, expense); edit(h, player, panel(player).amount, "200")
  h.open(player, controller); h.fire("on_gui_click", { player_index = player.index, element = panel(player).toggle })
  local cf = storage.cf_freeplay.accounts[controller.unit_number]
  eq(cf.label.text:find("Cashflow +$300/month", 1, true) ~= nil, true)
  eq(cf.label.text:find("Assets $12,000 • Debt $18,000", 1, true) ~= nil, true)
  local machine = storage.cf_freeplay.machines[cashflow.unit_number]
  eq(machine.label.text, "Cashflow")
  eq(machine.port_labels.cash_in.alignment, "right")
  eq(machine.port_labels.surplus_out.alignment, "left")
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
  storage.cf_freeplay.accounts[controller.unit_number].entities.cashflow.entities.cash_in.get_transport_line(1).insert_at_back({ name = "iron-plate", count = 10 })
  h.run_ticks(MONTH)
  eq(storage.cf_freeplay.accounts[controller.unit_number].out.surplus, 10)
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
  eq(cashflow_ports.unpaid_out.position.x, 34)
  eq(cashflow_ports.unpaid_out.position.y, 32)
  local debt_ports = storage.cf_freeplay.machines[debt.unit_number].entities
  eq(debt_ports.borrow_in.position.x, 48)
  eq(debt_ports.interest_out.position.x, 52)
  local warehouse = storage.cf_freeplay.machines[vault.unit_number]
  eq(warehouse.label.text, "Asset Warehouse")
  eq(warehouse.entities.deposit_in.position.x, 66)
  eq(warehouse.entities.return_out.position.x, 74)
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
  eq(cf.entities.debt[1].debt_cents, 900000)
  eq(cf.entities.debt[2].debt_cents, 900000)
  eq(cf.entities.vault[1].anchor.get_inventory().get_item_count("iron-plate"), 600)
  eq(cf.entities.vault[2].anchor.get_inventory().get_item_count("iron-plate"), 600)
  eq(cf.entities.debt[2].config.apr, 12)
  eq(cf.entities.vault[2].config.asset_return, 6)
  eq(cf.debt_cents, 1800000)
  eq(cf.label.text:find("Assets $12,000 • Debt $18,000", 1, true) ~= nil, true)
end
return T
