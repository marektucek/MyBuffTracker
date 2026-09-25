MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker

function MBT.ApplyDefaults(db)
  db = db or {}
  db.anchor = db.anchor or { point = "CENTER", x = 0, y = 0 }
  db.anchor.relativePoint = db.anchor.relativePoint or db.anchor.point
  db.sortMode = db.sortMode or "fixed"
  db.iconScale = db.iconScale or 1
  db.trackedBuffs = db.trackedBuffs or {}
  return db
end

function MBT.AddTrackedBuff(db, spellId, displayName, icon)
  for _, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      return buff
    end
  end
  local order = #db.trackedBuffs + 1
  table.insert(db.trackedBuffs, {
    spellId = spellId,
    displayName = displayName,
    icon = icon,
    missingBehavior = "hide",
    barColor = nil,
    order = order,
  })
  return db.trackedBuffs[#db.trackedBuffs]
end

local function renumber(trackedBuffs)
  for i, buff in ipairs(trackedBuffs) do
    buff.order = i
  end
end

function MBT.RemoveTrackedBuff(db, spellId)
  for i, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      table.remove(db.trackedBuffs, i)
      break
    end
  end
  renumber(db.trackedBuffs)
end

function MBT.MoveTrackedBuff(db, spellId, direction)
  local buffs = db.trackedBuffs
  local index
  for i, buff in ipairs(buffs) do
    if buff.spellId == spellId then
      index = i
      break
    end
  end
  if not index then return end
  local targetIndex = index + direction
  if targetIndex < 1 or targetIndex > #buffs then return end
  buffs[index], buffs[targetIndex] = buffs[targetIndex], buffs[index]
  renumber(buffs)
end

function MBT.SetMissingBehavior(db, spellId, behavior)
  for _, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      buff.missingBehavior = behavior
      break
    end
  end
end

function MBT.SetBarColor(db, spellId, r, g, b)
  for _, buff in ipairs(db.trackedBuffs) do
    if buff.spellId == spellId then
      buff.barColor = r and { r = r, g = g, b = b } or nil
      break
    end
  end
end

function MBT.SetSortMode(db, sortMode)
  db.sortMode = sortMode
end

function MBT.SetIconScale(db, scale)
  db.iconScale = scale
end

function MBT.SetAnchorPosition(db, point, relativePoint, x, y)
  db.anchor.point = point
  db.anchor.relativePoint = relativePoint
  db.anchor.x = x
  db.anchor.y = y
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
  if event == "ADDON_LOADED" and addonName == "MyBuffTracker" then
    MyBuffTrackerDB = MBT.ApplyDefaults(MyBuffTrackerDB)
    MBT.db = MyBuffTrackerDB

    if MBT.InitTracker then
      MBT.InitTracker()
    end
    if MBT.InitConfig then
      MBT.InitConfig()
    end

    self:UnregisterEvent("ADDON_LOADED")
  end
end)

SLASH_MYBUFFTRACKER1 = "/bt"
SLASH_MYBUFFTRACKER2 = "/mbt"
SlashCmdList["MYBUFFTRACKER"] = function()
  if MBT.ToggleConfig then
    MBT.ToggleConfig()
  end
end
