MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker

function MBT.MatchActiveAuras(trackedBuffs, unitBuffFn)
  local trackedSpellIds = {}
  for _, buff in ipairs(trackedBuffs) do
    trackedSpellIds[buff.spellId] = true
  end

  local activeBySpellId = {}
  local i = 1
  while true do
    local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = unitBuffFn("player", i)
    if not name then break end
    if trackedSpellIds[spellId] then
      activeBySpellId[spellId] = {
        icon = icon,
        count = count,
        duration = duration,
        expirationTime = expirationTime,
      }
    end
    i = i + 1
  end

  return activeBySpellId
end

function MBT.ComputeDisplayList(trackedBuffs, activeBySpellId, sortMode)
  local list = {}

  for _, buff in ipairs(trackedBuffs) do
    local active = activeBySpellId[buff.spellId]
    local visible = (active ~= nil) or (buff.missingBehavior == "dim")
    if visible then
      table.insert(list, {
        spellId = buff.spellId,
        displayName = buff.displayName,
        icon = (active and active.icon) or buff.icon,
        barColor = buff.barColor,
        order = buff.order,
        isActive = active ~= nil,
        count = (active and active.count) or 0,
        duration = (active and active.duration) or 0,
        expirationTime = (active and active.expirationTime) or 0,
      })
    end
  end

  if sortMode == "expiration" then
    table.sort(list, function(a, b)
      if a.isActive ~= b.isActive then
        return a.isActive
      end
      if a.isActive then
        local aExp = (a.expirationTime and a.expirationTime > 0) and a.expirationTime or math.huge
        local bExp = (b.expirationTime and b.expirationTime > 0) and b.expirationTime or math.huge
        return aExp < bExp
      end
      return a.order < b.order
    end)
  else
    table.sort(list, function(a, b)
      return a.order < b.order
    end)
  end

  return list
end

local UPDATE_INTERVAL = 0.1

local anchor
local bars = {}
local elapsedSinceUpdate = 0

local function EnsureBar(index)
  if not bars[index] then
    bars[index] = MBT.CreateBar(anchor, index)
  end
  return bars[index]
end

local function LayoutBars(displayList)
  for i, data in ipairs(displayList) do
    local bar = EnsureBar(i)
    MBT.SetBarIconScale(bar, MBT.db.iconScale)
    bar:ClearAllPoints()
    if i == 1 then
      bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    else
      bar:SetPoint("BOTTOMLEFT", bars[i - 1], "TOPLEFT", 0, 2)
    end
    MBT.UpdateBar(bar, data, GetTime())
  end

  for i = #displayList + 1, #bars do
    bars[i]:Hide()
  end
end

function MBT.RefreshDisplay()
  if not MBT.db then return end
  local activeBySpellId = MBT.MatchActiveAuras(MBT.db.trackedBuffs, UnitBuff)
  local displayList = MBT.ComputeDisplayList(MBT.db.trackedBuffs, activeBySpellId, MBT.db.sortMode)
  LayoutBars(displayList)
end

function MBT.SetAnchorLocked(locked)
  if not anchor then return end
  if locked then anchor.handle:Hide() else anchor.handle:Show() end
end

function MBT.InitTracker()
  anchor = CreateFrame("Frame", "MyBuffTrackerAnchor", UIParent)
  anchor:SetWidth(160)
  anchor:SetHeight(20)
  anchor:SetPoint(MBT.db.anchor.point, UIParent, MBT.db.anchor.relativePoint, MBT.db.anchor.x, MBT.db.anchor.y)
  anchor:SetMovable(true)

  -- Bars grow upward from the anchor, so the drag handle sits just below the
  -- first bar where it never covers bar text.
  local handle = CreateFrame("Frame", nil, anchor)
  handle:SetWidth(160)
  handle:SetHeight(16)
  handle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  handle:SetFrameLevel(anchor:GetFrameLevel() + 10)
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function() anchor:StartMoving() end)
  handle:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local point, _, relativePoint, x, y = anchor:GetPoint()
    MBT.SetAnchorPosition(MBT.db, point, relativePoint, x, y)
  end)

  local handleBg = handle:CreateTexture(nil, "BACKGROUND")
  handleBg:SetAllPoints(handle)
  handleBg:SetTexture(0, 0.6, 1, 0.6)

  local handleText = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  handleText:SetAllPoints(handle)
  handleText:SetText("MyBuffTracker (drag)")

  handle:Hide()
  anchor.handle = handle

  MBT.anchor = anchor

  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("UNIT_AURA")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    MBT.RefreshDisplay()
  end)

  local ticker = CreateFrame("Frame")
  ticker:SetScript("OnUpdate", function(self, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= UPDATE_INTERVAL then
      elapsedSinceUpdate = 0
      MBT.RefreshDisplay()
    end
  end)

  MBT.RefreshDisplay()
end
