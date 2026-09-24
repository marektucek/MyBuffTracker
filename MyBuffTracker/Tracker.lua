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
        return a.expirationTime < b.expirationTime
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
