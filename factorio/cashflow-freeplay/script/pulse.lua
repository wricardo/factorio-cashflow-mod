-- Month-boundary close: collects unsettled copper (unpaid bills, un-pushed interest, and
-- whatever's still in each expense/debt chest), applies it to debt and accrues this month's
-- interest/returns, records a report for the GUI, and rolls over to the next month's plan and
-- buffers. Every 12th month it also closes a yearly report. Triggered once per account from
-- control.lua's sweep loop when tick_in_month reaches the configured month length.
local acc = require("script.accounting")
local stations = require("script.stations")
local labels = require("script.labels")
local gui = require("script.gui")
local account = require("script.account")
local M = {}

local MAX_YEAR_REPORTS = 20

-- Closes the year that just ended: snapshots year-end assets and debt next to the cash and bills
-- accumulated since the last report, stores it (newest last), and tells the account's players.
local function close_year(cf)
  local year = acc.calendar(cf.month - 1)
  local report = acc.year_report(year, cf.year_totals, stations.vault_plates(cf) * acc.CENTS_PER_PLATE, cf.debt_cents)
  cf.year_reports[#cf.year_reports + 1] = report
  if #cf.year_reports > MAX_YEAR_REPORTS then table.remove(cf.year_reports, 1) end
  cf.year_totals = { cash_in = 0, bills_in = 0 }
  local text = "[color=yellow]" .. cf.name .. " • Year " .. year .. " report[/color]\n" .. labels.year_report_text(report)
  for _, player in pairs(game.connected_players) do
    if player.force.index == cf.force_index then player.print(text) end
    gui.refresh_player(player)
  end
end

-- Runs the full month-close sequence described above for one running account.
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
  cf.year_totals.cash_in, cf.year_totals.bills_in = cf.year_totals.cash_in + report.cash_in, cf.year_totals.bills_in + report.bills_in
  cf.out.surplus = cf.out.surplus + node_iron
  cf.out.unpaid = cf.out.unpaid + node_copper
  for _, machine in ipairs(cf.entities.smelter) do machine.batch_done = nil end
  cf.month, cf.tick_in_month = cf.month + 1, 0
  cf.plan = account.plan_month(cf)
  account.reset_month(cf, true)
  account.fill_month_buffers(cf)
  if (cf.month - 1) % 12 == 0 then close_year(cf) end
end
return M
