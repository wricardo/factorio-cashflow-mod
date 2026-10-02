local here = (arg and arg[0] or ""):match("(.*/)") or "./"
local source = arg[1] or "."
package.path = source .. "/?.lua;" .. here .. "?.lua;" .. package.path

local files = {}
for i = 2, #arg do files[#files + 1] = arg[i] end
-- freeplay_test installs the fake runtime, which disables `require`, so it must load last.
if #files == 0 then files = { "accounting_test", "split_test", "freeplay_test" } end
local passed, failed = 0, 0

for _, file in ipairs(files) do
  local tests = require(file)
  local names = {}
  for name in pairs(tests) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      print("FAIL " .. file .. " :: " .. name .. "\n  " .. tostring(err))
    end
  end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
