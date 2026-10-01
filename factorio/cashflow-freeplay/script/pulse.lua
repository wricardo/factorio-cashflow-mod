local acc = require("script.accounting")
local stations = require("script.stations")
local account = require("script.account")
local M = {}

function M.close_month(cf)
  local waiting = cf.out.unpaid + cf.out.interest
  for _, machine in ipairs(cf.entities.expense) do
    local inv = machine.anchor.get_inventory(defines.inventory.chest)
    local copper = inv.get_item_count("copper-plate")
    waiting = waiting + copper
    if copper > 0 then inv.remove({ name = "copper-plate", count = copper }) end
    machine.out = 0
  end
  for _, machine in ipairs(cf.entities.debt) do
    waiting = waiting + (machine.pending_interest or 0)
    machine.pending_interest = 0
  end
  cf.out.unpaid, cf.out.interest = 0, 0
  local node_iron, node_copper = stations.cashflow_plates(cf)
  stations.clear_cashflow(cf)
  local interest_cents, interest_plates, return_cents, return_plates = stations.close_finance(cf, waiting)
  local report = {
    collected_plates = waiting,
    surplus_plates = node_iron,
    unpaid_plates = node_copper,
    interest_cents = interest_cents,
    interest_plates = interest_plates,
    return_cents = return_cents,
    return_plates = return_plates,
  }
  report.cash_in, report.bills_in, report.paid = cf.stats.cash_in, cf.stats.bills_in, cf.stats.paid
  report.borrowed, report.debt_paid, report.deposits = cf.stats.borrowed, cf.stats.debt_paid, cf.stats.deposits
  cf.last_report = report
  cf.out.surplus = cf.out.surplus + node_iron
  cf.out.unpaid = cf.out.unpaid + node_copper
  cf.month, cf.tick_in_month = cf.month + 1, 0
  cf.plan = account.plan_month(cf)
  account.reset_month(cf, true)
  account.fill_month_buffers(cf)
  stations.sync_ledger(cf)
  local needs, wants = 0, 0
  for _, machine in ipairs(cf.entities.expense) do
    local dollars = machine.config.monthly_cents / 100
    if machine.config.category == "needs" then needs = needs + dollars else wants = wants + dollars end
  end
  cf.won = acc.is_financially_independent(cf.debt_cents, stations.vault_plates(cf) * acc.CENTS_PER_PLATE, 0, needs, wants)
  if cf.debt_cents == 0 then cf.won = stations.monthly_returns_cents(cf) >= (needs + wants) * 100 end
end
return M
