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

local ROW_HEIGHT = 24
local MAX_VISIBLE_ROWS = 12
local rows = {}

function MBT.RefreshConfigRows()
  local buffs = MBT.db.trackedBuffs
  for i = 1, MAX_VISIBLE_ROWS do
    local row = rows[i]
    local buff = buffs[i]
    if buff then
      row.spellId = buff.spellId
      row.icon:SetTexture(buff.icon)
      row.nameText:SetText(buff.displayName)
      row.dimCheck:SetChecked(buff.missingBehavior == "dim")
      if buff.barColor then
        row.colorSwatchTexture:SetVertexColor(buff.barColor.r, buff.barColor.g, buff.barColor.b)
      else
        row.colorSwatchTexture:SetVertexColor(1, 1, 1)
      end
      row:Show()
    else
      row:Hide()
    end
  end
end

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetWidth(360)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + 2))

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetWidth(ROW_HEIGHT - 4)
  row.icon:SetHeight(ROW_HEIGHT - 4)
  row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

  row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.nameText:SetWidth(120)
  row.nameText:SetJustifyH("LEFT")

  row.dimCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.dimCheck:SetWidth(20)
  row.dimCheck:SetHeight(20)
  row.dimCheck:SetPoint("LEFT", row.nameText, "RIGHT", 4, 0)
  row.dimCheck:SetScript("OnClick", function(self)
    MBT.SetMissingBehavior(MBT.db, row.spellId, self:GetChecked() and "dim" or "hide")
    MBT.RefreshDisplay()
  end)

  row.colorSwatch = CreateFrame("Button", nil, row)
  row.colorSwatch:SetWidth(16)
  row.colorSwatch:SetHeight(16)
  row.colorSwatch:SetPoint("LEFT", row.dimCheck, "RIGHT", 6, 0)
  row.colorSwatch:SetNormalTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
  row.colorSwatchTexture = row.colorSwatch:GetNormalTexture()
  row.colorSwatch:SetScript("OnClick", function()
    local current
    for _, buff in ipairs(MBT.db.trackedBuffs) do
      if buff.spellId == row.spellId then current = buff.barColor end
    end
    local r, g, b = 0.2, 0.6, 1.0
    if current then r, g, b = current.r, current.g, current.b end
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      MBT.SetBarColor(MBT.db, row.spellId, nr, ng, nb)
      MBT.RefreshConfigRows()
      MBT.RefreshDisplay()
    end
    ColorPickerFrame.cancelFunc = function() end
    ShowUIPanel(ColorPickerFrame)
  end)

  row.upButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.upButton:SetWidth(20)
  row.upButton:SetHeight(20)
  row.upButton:SetText("^")
  row.upButton:SetPoint("LEFT", row.colorSwatch, "RIGHT", 6, 0)
  row.upButton:SetScript("OnClick", function()
    MBT.MoveTrackedBuff(MBT.db, row.spellId, -1)
    MBT.RefreshConfigRows()
    MBT.RefreshDisplay()
  end)

  row.downButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.downButton:SetWidth(20)
  row.downButton:SetHeight(20)
  row.downButton:SetText("v")
  row.downButton:SetPoint("LEFT", row.upButton, "RIGHT", 2, 0)
  row.downButton:SetScript("OnClick", function()
    MBT.MoveTrackedBuff(MBT.db, row.spellId, 1)
    MBT.RefreshConfigRows()
    MBT.RefreshDisplay()
  end)

  row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.removeButton:SetWidth(60)
  row.removeButton:SetHeight(20)
  row.removeButton:SetText("Remove")
  row.removeButton:SetPoint("LEFT", row.downButton, "RIGHT", 6, 0)
  row.removeButton:SetScript("OnClick", function()
    MBT.RemoveTrackedBuff(MBT.db, row.spellId)
    MBT.RefreshConfigRows()
    MBT.RefreshDisplay()
  end)

  return row
end

function MBT.CreateConfigRows(parent)
  for i = 1, MAX_VISIBLE_ROWS do
    rows[i] = CreateRow(parent, i)
  end
end
