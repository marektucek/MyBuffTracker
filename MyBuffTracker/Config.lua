MyBuffTracker = MyBuffTracker or {}
local MBT = MyBuffTracker

function MBT.ResolveBuffByName(name, unitBuffFn)
  local lowerName = string.lower(name)
  local i = 1
  while true do
    local buffName, _, icon, _, _, _, _, _, _, _, spellId = unitBuffFn("player", i)
    if not buffName then break end
    if string.lower(buffName) == lowerName then
      return { spellId = spellId, displayName = buffName, icon = icon }
    end
    i = i + 1
  end
  return nil
end
