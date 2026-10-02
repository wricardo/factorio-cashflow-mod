-- Reads the map's runtime settings. Kept apart from accounting.lua, which must stay free of
-- Factorio API calls so it can be unit-tested with plain Lua.
local M = {}

-- Length of one game month in ticks (the `cashflow-month-seconds` runtime-global setting).
function M.month_ticks()
  return settings.global["cashflow-month-seconds"].value * 60
end

return M
