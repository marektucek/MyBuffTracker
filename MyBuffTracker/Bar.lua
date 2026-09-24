MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker

function MBT.FormatTime(seconds)
  if seconds >= 60 then
    return string.format("%dm", math.ceil(seconds / 60))
  end
  return string.format("%.1fs", seconds)
end
