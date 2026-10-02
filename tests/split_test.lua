local split = require("script.split")

local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local T = {}

local function lefts_in_window(percent, first_tick)
  local lefts = 0
  for tick = first_tick, first_tick + split.WINDOW_TICKS - 1 do
    if split.priority(percent, tick) == "left" then lefts = lefts + 1 end
  end
  return lefts
end

function T.every_whole_percent_favours_the_left_for_exactly_that_many_ticks_of_100()
  for percent = 0, 100 do
    eq(lefts_in_window(percent, 0), percent, percent .. "% over one window")
    eq(lefts_in_window(percent, 12345), percent, percent .. "% over a window starting mid-cycle")
  end
end

function T.the_extremes_never_flip_the_priority()
  for tick = 0, 250 do
    eq(split.priority(0, tick), "right")
    eq(split.priority(100, tick), "left")
  end
end

function T.the_left_ticks_form_one_contiguous_block_per_window()
  -- Interleaving the ticks aliased against belt item spacing in the real-engine measurements, so
  -- the schedule must stay one block: left first, then right.
  local flips, previous = 0, split.priority(30, 0)
  for tick = 1, split.WINDOW_TICKS - 1 do
    local current = split.priority(30, tick)
    if current ~= previous then flips = flips + 1 end
    previous = current
  end
  eq(flips, 1)
  eq(split.priority(30, 0), "left")
  eq(split.priority(30, 99), "right")
end

function T.entered_shares_round_to_a_whole_percent_within_0_to_100()
  eq(split.clamp_percent(30), 30)
  eq(split.clamp_percent(30.4), 30)
  eq(split.clamp_percent(30.5), 31)
  eq(split.clamp_percent(-5), 0)
  eq(split.clamp_percent(150), 100)
end

return T
