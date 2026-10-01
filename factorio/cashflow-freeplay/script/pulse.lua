local acc = require("script.accounting")
local stations = require("script.stations")
local account = require("script.account")
local M = {}

function M.close_month(cf)
  local waiting = cf.out.unpaid + cf.out.interest
  for _, machine in ipairs(cf.entities.expense) do
    local inv = machine.anchor.get_inventory(defines.inventory.chest)
    local waiting_copper = inv.get_item_count("copper-plate")
    waiting = waiting + waiting_copper
    if waiting_copper > 0 then inv.remove({ name = "copper-plate", count = waiting_copper }) end
    machine.out = 0
  end
  cf.out.unpaid, cf.out.interest = 0, 0
  local node_iron, node_copper = stations.cashflow_plates(cf)
  local vault_plates = stations.vault_plates(cf)
  local result = acc.close_month(cf, { copper_waiting = waiting, node_iron = node_iron, node_copper = node_copper, vault_plates = vault_plates }, cf.config)
  stations.clear_cashflow(cf)
  for key, value in pairs(result) do if key ~= "report" then cf[key] = value end end
  local report = result.report
  report.cash_in, report.bills_in, report.paid = cf.stats.cash_in, cf.stats.bills_in, cf.stats.paid
  report.borrowed, report.debt_paid, report.deposits = cf.stats.borrowed, cf.stats.debt_paid, cf.stats.deposits
  cf.last_report = report
  cf.out.surplus = cf.out.surplus + report.surplus_plates
  cf.out.unpaid = cf.out.unpaid + report.unpaid_plates
  cf.out.interest = cf.out.interest + report.interest_plates
  cf.out.returns = cf.out.returns + report.return_plates
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
  cf.won = acc.is_financially_independent(cf.debt_cents, vault_plates * acc.CENTS_PER_PLATE, cf.config.asset_return, needs, wants)
end
return M
