-- Reads the map's runtime settings. Kept apart from accounting.lua, which must stay free of
-- Factorio API calls so it can be unit-tested with plain Lua.
local acc = require("script.accounting")
local M = {}

-- Length of one game month in ticks (the `cf-freeplay-month-seconds` runtime-global setting).
function M.month_ticks()
  return settings.global["cf-freeplay-month-seconds"].value * 60
end

-- Largest monthly amount one Passive/Active Income or Expense station may be configured with at
-- the current month length. It scales with the month because the cap is a belt-throughput limit.
function M.max_station_cents()
  return acc.max_station_cents(M.month_ticks())
end

return M
