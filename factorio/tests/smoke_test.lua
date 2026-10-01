local fake = require("fake_factorio")

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local MONTH = 3600

local function start(opts)
  local h = fake.install(opts)
  h.init()
  local cf = storage.cf
  local player = h.add_player()
  return h, cf, player
end

local function press(h, player, name)
  h.fire("on_gui_click", { player_index = player.index, element = { name = name } })
end

local function line(belt, i, cap)
  local l = belt.get_transport_line(i or 1)
  l.cap = cap or 100000
  return l
end

local function ledger(cf)
  return cf.entities.debt.landmark.get_inventory().get_item_count("copper-plate")
end

local function tile_count(surface, name)
  local count = 0
  for _, tile in ipairs(surface.tiles) do
    if tile.name == name then
      count = count + 1
    end
  end
  return count
end

local function entity_count(surface, name)
  local count = 0
  for _, entity in ipairs(surface.entities) do
    if entity.name == name then
      count = count + 1
    end
  end
  return count
end

local T = {}

function T.inert_outside_scenario()
  local h = fake.install({ level = { level_name = "freeplay" } })
  h.init()
  eq(storage.cf, nil)
  h.run_ticks(60)
end

function T.setup_seeds_vault_ledger_and_player()
  local _, cf, player = start()
  eq(cf.entities.vault.chest.get_inventory().get_item_count("iron-plate"), 1200)
  eq(ledger(cf), 1800)
  eq(cf.entities.debt.splitter.splitter_output_priority, "right")
  assert(player.gui.left.cf_panel, "panel created")
  eq(player.inventory.get_item_count("transport-belt"), 400)
  eq(player.inventory.get_item_count("cf-meter-belt"), 1)
  eq(player.surface.name, "cashflow")
end

function T.financial_district_has_marked_lanes_and_live_ledger()
  local h, cf = start()
  local surface = game.surfaces.cashflow
  assert(tile_count(surface, "concrete") > 2000, "campus concrete pad")
  assert(tile_count(surface, "refined-concrete") > 0, "ledger and vault pads")
  assert(tile_count(surface, "hazard-concrete-left") > 0, "liability lane")
  eq(#h.frames, 6, "one station frame per financial station")
  eq(entity_count(surface, "cf-facade"), 31, "processing facades and warehouse enclosure")
  eq(cf.labels.ledger_title.text, "FINANCIAL LEDGER")
  assert(cf.labels.ledger_status.text:match("^MONTH 1  READY"), "ledger starts ready for month one")
  assert(cf.labels.ledger_balances.text:match("DEBT %$18,000"), "ledger displays debt balance")
  assert(cf.labels.vault.text:match("^ASSET WAREHOUSE"), "warehouse label")
end

function T.clock_paused_until_start()
  local h, cf = start()
  h.run_ticks(MONTH * 2)
  eq(cf.month, 0)
  eq(cf.emitted.paycheck, 0)
end

function T.emitters_put_cash_and_bills_on_belts()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  h.run_ticks(MONTH / 2)
  eq(cf.entities.paycheck.out.get_transport_line(1).get_item_count("iron-plate"), 4)
  eq(cf.entities.needs.out.get_transport_line(1).get_item_count("copper-plate"), 4)
  eq(cf.entities.wants.out.get_transport_line(2).get_item_count("copper-plate"), 4)
end

function T.unbelted_bills_are_charged_to_debt()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  h.run_ticks(MONTH)
  eq(cf.month, 1)
  -- 8 copper fit on each stub; the rest of $2,000 needs + $800 wants couldn't be placed
  eq(cf.last_report.collected_plates, 192 + 72)
  eq(cf.debt_cents, 1800000 + 264000)
  eq(ledger(cf), 2064)
  -- interest is a copper bill waiting at the Debt station, not added to debt yet
  eq(cf.out.interest, 27)
  eq(cf.out.returns, 7)
  eq(cf.out.paycheck, 492, "cash that couldn't be placed stays idle, never charged")
  assert(h.logs[#h.logs]:match("^%[cashflow%] month=1 "), "pulse logged")
end

function T.unbelted_interest_compounds_next_month()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  h.run_ticks(MONTH * 2)
  -- 8 of the 27 interest plates fit on INTEREST OUT, 19 were charged; needs/wants stubs already full
  eq(cf.last_report.collected_plates, 200 + 80 + 19)
end

function T.cashflow_pairs_iron_with_copper()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  line(cf.entities.cashflow.cash_in).put("iron-plate", 250)
  line(cf.entities.cashflow.cash_in, 2).put("copper-plate", 20)
  line(cf.entities.cashflow.bills_in).put("copper-plate", 100)
  h.run_ticks(2)
  eq(cf.stats.paid, 120)
  eq(cf.node.iron, 130)
  eq(cf.node.copper, 0)
  eq(cf.consumed_total_cents, 120000)
  h.run_ticks(MONTH - 2)
  eq(cf.last_report.surplus_plates, 130)
  eq(cf.out.surplus, 130)
  eq(cf.node.iron, 0)
end

function T.cashflow_leftover_bills_come_out_unpaid()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  line(cf.entities.cashflow.bills_in).put("copper-plate", 50)
  h.run_ticks(MONTH)
  eq(cf.last_report.unpaid_plates, 50)
  eq(cf.out.unpaid, 50)
end

function T.copper_borrows_and_iron_pays_down()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  line(cf.entities.debt.borrow_in).put("copper-plate", 10)
  line(cf.entities.debt.pay_in).put("iron-plate", 30)
  h.run_ticks(2)
  eq(cf.debt_cents, 1800000 + 10000 - 30000)
  eq(ledger(cf), 1780)
  eq(cf.stats.borrowed, 10)
  eq(cf.stats.debt_paid, 30)
end

function T.no_debt_leaves_iron_on_pay_belt()
  local h, cf, player = start({ settings = { ["cf-starting-debt"] = 0 } })
  press(h, player, "cf_toggle")
  local pay = line(cf.entities.debt.pay_in)
  pay.put("iron-plate", 5)
  h.run_ticks(4)
  eq(pay.get_item_count("iron-plate"), 5)
  eq(cf.debt_cents, 0)
end

function T.vault_deposits_move_into_chest()
  local h, cf, player = start()
  press(h, player, "cf_toggle")
  line(cf.entities.vault.deposit_in, 2).put("iron-plate", 4)
  h.run_ticks(2)
  eq(cf.entities.vault.chest.get_inventory().get_item_count("iron-plate"), 1204)
  assert(cf.goals.first_deposit)
end

function T.hand_picked_plates()
  local h, cf, player = start()
  player.inventory.insert({ name = "iron-plate", count = 5 })
  player.inventory.insert({ name = "copper-plate", count = 3 })
  h.fire("on_player_main_inventory_changed", { player_index = player.index })
  eq(player.inventory.get_item_count("iron-plate"), 0)
  eq(player.inventory.get_item_count("copper-plate"), 0)
  eq(cf.out.paycheck, 5)
  eq(cf.debt_cents, 1800000 + 3000)
end

function T.win_and_quit_job()
  local h, cf, player = start({ settings = { ["cf-starting-debt"] = 0, ["cf-starting-assets"] = 480000 } })
  -- pretend Needs and Wants are belted somewhere so no bills are charged to debt
  for _, key in ipairs({ "needs", "wants" }) do
    line(cf.entities[key].out, 1)
    line(cf.entities[key].out, 2)
  end
  press(h, player, "cf_toggle")
  h.run_ticks(MONTH)
  assert(cf.won, "financially independent with $480k at 7% and $2,800 bills")
  assert(player.gui.left.cf_panel.cf_buttons.cf_quit_job.visible, "quit button shown")
  press(h, player, "cf_quit_job")
  h.run_ticks(MONTH)
  eq(cf.last_report.paycheck, 0)
end

return T
