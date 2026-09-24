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

local addEditBox, addButton, matchIcon, matchNameText, confirmButton, cancelButton
local advancedToggle, spellIdEditBox, addByIdButton, notFoundText
local pendingMatch
local advancedMode = false

local function ShowPendingMatch(match)
  pendingMatch = match
  matchIcon:SetTexture(match.icon)
  matchNameText:SetText(match.displayName)
  matchIcon:Show()
  matchNameText:Show()
  confirmButton:Show()
  cancelButton:Show()
  notFoundText:Hide()
end

local function ClearPendingMatch()
  pendingMatch = nil
  matchIcon:Hide()
  matchNameText:Hide()
  confirmButton:Hide()
  cancelButton:Hide()
end

local function HandleAddByName()
  local name = addEditBox:GetText()
  if not name or name == "" then return end
  local match = MBT.ResolveBuffByName(name, UnitBuff)
  if match then
    ShowPendingMatch(match)
  else
    ClearPendingMatch()
    notFoundText:Show()
  end
end

local function HandleConfirm()
  if not pendingMatch then return end
  MBT.AddTrackedBuff(MBT.db, pendingMatch.spellId, pendingMatch.displayName, pendingMatch.icon)
  ClearPendingMatch()
  addEditBox:SetText("")
  if MBT.RefreshConfigRows then MBT.RefreshConfigRows() end
  MBT.RefreshDisplay()
end

local function HandleAddById()
  local idText = spellIdEditBox:GetText()
  local spellId = tonumber(idText)
  if not spellId then return end
  local name, _, icon = GetSpellInfo(spellId)
  local displayName = name or ("Spell " .. spellId)
  MBT.AddTrackedBuff(MBT.db, spellId, displayName, icon)
  spellIdEditBox:SetText("")
  if MBT.RefreshConfigRows then MBT.RefreshConfigRows() end
  MBT.RefreshDisplay()
end
