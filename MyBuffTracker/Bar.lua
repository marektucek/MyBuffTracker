MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker

function MBT.FormatTime(seconds)
  if seconds >= 60 then
    return string.format("%dm", math.ceil(seconds / 60))
  end
  return string.format("%.1fs", seconds)
end

local DEFAULT_BAR_COLOR = { r = 0.2, g = 0.6, b = 1.0 }
local BAR_WIDTH = 160
local BAR_HEIGHT = 20
local ICON_SIZE = BAR_HEIGHT

function MBT.CreateBar(parent, index)
  local bar = CreateFrame("Frame", "MyBuffTrackerBar" .. index, parent)
  bar:SetSize(BAR_WIDTH, BAR_HEIGHT)

  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetSize(ICON_SIZE, ICON_SIZE)
  bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)

  bar.bar = CreateFrame("StatusBar", nil, bar)
  bar.bar:SetSize(BAR_WIDTH - ICON_SIZE - 2, BAR_HEIGHT)
  bar.bar:SetPoint("LEFT", bar.icon, "RIGHT", 2, 0)
  bar.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar.bar:SetMinMaxValues(0, 1)
  bar.bar:SetValue(1)

  bar.bar.bg = bar.bar:CreateTexture(nil, "BACKGROUND")
  bar.bar.bg:SetAllPoints(bar.bar)
  bar.bar.bg:SetTexture(0, 0, 0, 0.5)

  bar.label = bar.bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  bar.label:SetPoint("LEFT", bar.bar, "LEFT", 3, 0)
  bar.label:SetPoint("RIGHT", bar.bar, "RIGHT", -3, 0)
  bar.label:SetJustifyH("LEFT")

  return bar
end

function MBT.UpdateBar(bar, data, now)
  bar.spellId = data.spellId
  bar:Show()
  bar.icon:SetTexture(data.icon)

  local color = data.barColor or DEFAULT_BAR_COLOR
  bar.bar:SetStatusBarColor(color.r, color.g, color.b)

  if data.isActive then
    bar.icon:SetDesaturated(false)
    local remaining = math.max(data.expirationTime - now, 0)
    local fraction = 1
    if data.duration and data.duration > 0 then
      fraction = remaining / data.duration
    end
    bar.bar:SetValue(fraction)

    local text = data.displayName
    if data.count and data.count > 1 then
      text = text .. " x" .. data.count
    end
    text = text .. "  " .. MBT.FormatTime(remaining)
    bar.label:SetText(text)
  else
    bar.icon:SetDesaturated(true)
    bar.bar:SetValue(1)
    bar.label:SetText(data.displayName)
  end
end
