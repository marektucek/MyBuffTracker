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
  if not name then
    notFoundText:Show()
    return
  end
  MBT.AddTrackedBuff(MBT.db, spellId, name, icon)
  spellIdEditBox:SetText("")
  notFoundText:Hide()
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
      row.activeOnlyCheck:SetChecked(buff.missingBehavior ~= "dim")
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

  row.activeOnlyCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.activeOnlyCheck:SetWidth(20)
  row.activeOnlyCheck:SetHeight(20)
  row.activeOnlyCheck:SetPoint("LEFT", row.nameText, "RIGHT", 4, 0)
  row.activeOnlyCheck:SetScript("OnClick", function(self)
    MBT.SetMissingBehavior(MBT.db, row.spellId, self:GetChecked() and "hide" or "dim")
    MBT.RefreshDisplay()
  end)
  row.activeOnlyCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Show only while active")
    GameTooltip:AddLine("Checked: the bar is hidden when the buff is missing.", 1, 1, 1, true)
    GameTooltip:AddLine("Unchecked: the bar stays visible, grayed out.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  row.activeOnlyCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row.colorSwatch = CreateFrame("Button", nil, row)
  row.colorSwatch:SetWidth(16)
  row.colorSwatch:SetHeight(16)
  row.colorSwatch:SetPoint("LEFT", row.activeOnlyCheck, "RIGHT", 24, 0)
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

local configFrame

function MBT.InitConfig()
  configFrame = CreateFrame("Frame", "MyBuffTrackerConfig", UIParent)
  configFrame:SetWidth(400)
  configFrame:SetHeight(620)
  configFrame:SetPoint("CENTER")
  configFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  configFrame:SetMovable(true)
  configFrame:EnableMouse(true)
  configFrame:RegisterForDrag("LeftButton")
  configFrame:SetScript("OnDragStart", configFrame.StartMoving)
  configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
  configFrame:Hide()
  configFrame:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "MyBuffTrackerConfig")

  local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", configFrame, "TOP", 0, -16)
  title:SetText("MyBuffTracker")

  local closeButton = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -4, -4)
  closeButton:SetScript("OnClick", function() configFrame:Hide() end)

  addEditBox = CreateFrame("EditBox", "MyBuffTrackerAddEditBox", configFrame, "InputBoxTemplate")
  addEditBox:SetWidth(180)
  addEditBox:SetHeight(20)
  addEditBox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -48)
  addEditBox:SetAutoFocus(false)
  addEditBox:SetScript("OnEnterPressed", HandleAddByName)

  addButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  addButton:SetWidth(60)
  addButton:SetHeight(22)
  addButton:SetText("Add")
  addButton:SetPoint("LEFT", addEditBox, "RIGHT", 8, 0)
  addButton:SetScript("OnClick", HandleAddByName)

  matchIcon = configFrame:CreateTexture(nil, "ARTWORK")
  matchIcon:SetWidth(20)
  matchIcon:SetHeight(20)
  matchIcon:SetPoint("TOPLEFT", addEditBox, "BOTTOMLEFT", 0, -8)
  matchIcon:Hide()

  matchNameText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  matchNameText:SetPoint("LEFT", matchIcon, "RIGHT", 4, 0)
  matchNameText:SetWidth(140)
  matchNameText:SetJustifyH("LEFT")
  matchNameText:Hide()

  confirmButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  confirmButton:SetWidth(70)
  confirmButton:SetHeight(20)
  confirmButton:SetText("Confirm")
  confirmButton:SetPoint("LEFT", matchNameText, "RIGHT", 8, 0)
  confirmButton:SetScript("OnClick", HandleConfirm)
  confirmButton:Hide()

  cancelButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  cancelButton:SetWidth(60)
  cancelButton:SetHeight(20)
  cancelButton:SetText("Cancel")
  cancelButton:SetPoint("LEFT", confirmButton, "RIGHT", 4, 0)
  cancelButton:SetScript("OnClick", ClearPendingMatch)
  cancelButton:Hide()

  notFoundText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  notFoundText:SetPoint("TOPLEFT", addEditBox, "BOTTOMLEFT", 0, -8)
  notFoundText:SetWidth(340)
  notFoundText:SetJustifyH("LEFT")
  notFoundText:SetText("No active buff matches that name. Use Advanced to enter a spell ID.")
  notFoundText:Hide()

  advancedToggle = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
  advancedToggle:SetWidth(20)
  advancedToggle:SetHeight(20)
  advancedToggle:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -108)

  local advancedLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  advancedLabel:SetPoint("LEFT", advancedToggle, "RIGHT", 2, 0)
  advancedLabel:SetText("Advanced: add by spell ID")

  spellIdEditBox = CreateFrame("EditBox", "MyBuffTrackerSpellIdEditBox", configFrame, "InputBoxTemplate")
  spellIdEditBox:SetWidth(100)
  spellIdEditBox:SetHeight(20)
  spellIdEditBox:SetPoint("TOPLEFT", advancedToggle, "BOTTOMLEFT", 8, -4)
  spellIdEditBox:SetAutoFocus(false)
  spellIdEditBox:SetNumeric(true)
  spellIdEditBox:SetScript("OnEnterPressed", HandleAddById)
  spellIdEditBox:Hide()

  addByIdButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  addByIdButton:SetWidth(60)
  addByIdButton:SetHeight(20)
  addByIdButton:SetText("Add")
  addByIdButton:SetPoint("LEFT", spellIdEditBox, "RIGHT", 6, 0)
  addByIdButton:SetScript("OnClick", HandleAddById)
  addByIdButton:Hide()

  advancedToggle:SetScript("OnClick", function(self)
    advancedMode = self:GetChecked()
    if advancedMode then
      spellIdEditBox:Show()
      addByIdButton:Show()
    else
      spellIdEditBox:Hide()
      addByIdButton:Hide()
    end
  end)

  local listContainer = CreateFrame("Frame", nil, configFrame)
  listContainer:SetWidth(360)
  listContainer:SetHeight(MAX_VISIBLE_ROWS * (ROW_HEIGHT + 2))
  listContainer:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -180)
  MBT.CreateConfigRows(listContainer)

  -- Column headers, centered over the row controls they describe.
  local function CreateHeader(text, x)
    local header = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header:SetPoint("BOTTOM", listContainer, "TOPLEFT", x, 2)
    header:SetText(text)
    return header
  end
  local buffHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  buffHeader:SetPoint("BOTTOMLEFT", listContainer, "TOPLEFT", 0, 2)
  buffHeader:SetText("Tracked buffs")
  CreateHeader("Active only", 158)
  CreateHeader("Color", 200)

  local sortLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sortLabel:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -12)
  sortLabel:SetText("Bar order:")

  local sortOptions = {
    { mode = "fixed", text = "List order" },
    { mode = "expiration", text = "Expiring soonest first" },
  }
  local sortRadios = {}
  local function RefreshSortRadios()
    for _, radio in ipairs(sortRadios) do
      radio:SetChecked(MBT.db.sortMode == radio.mode)
    end
  end
  local previous = sortLabel
  for i, option in ipairs(sortOptions) do
    local radio = CreateFrame("CheckButton", nil, configFrame, "UIRadioButtonTemplate")
    radio.mode = option.mode
    radio:SetPoint("LEFT", previous, "RIGHT", i == 1 and 8 or 12, 0)
    local label = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", radio, "RIGHT", 2, 0)
    label:SetText(option.text)
    radio:SetHitRectInsets(0, -label:GetStringWidth() - 2, 0, 0)
    radio:SetScript("OnClick", function(self)
      MBT.SetSortMode(MBT.db, self.mode)
      RefreshSortRadios()
      MBT.RefreshDisplay()
    end)
    sortRadios[i] = radio
    previous = label
  end

  local anchorLocked = true
  local lockButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
  lockButton:SetWidth(160)
  lockButton:SetHeight(22)
  lockButton:SetPoint("TOPLEFT", sortLabel, "BOTTOMLEFT", 0, -12)
  local function RefreshLockButton()
    lockButton:SetText(anchorLocked and "Unlock Anchor" or "Lock Anchor")
  end
  lockButton:SetScript("OnClick", function()
    anchorLocked = not anchorLocked
    MBT.SetAnchorLocked(anchorLocked)
    RefreshLockButton()
  end)

  local iconSlider = CreateFrame("Slider", "MyBuffTrackerIconScaleSlider", configFrame, "OptionsSliderTemplate")
  iconSlider:SetWidth(200)
  iconSlider:SetHeight(17)
  iconSlider:SetPoint("TOPLEFT", lockButton, "BOTTOMLEFT", 4, -26)
  iconSlider:SetMinMaxValues(0.5, 2)
  iconSlider:SetValueStep(0.1)
  _G[iconSlider:GetName() .. "Low"]:SetText("50%")
  _G[iconSlider:GetName() .. "High"]:SetText("200%")
  local iconSliderText = _G[iconSlider:GetName() .. "Text"]
  local function RefreshIconSliderText(scale)
    iconSliderText:SetText(string.format("Icon size: %d%%", math.floor(scale * 100 + 0.5)))
  end
  iconSlider:SetValue(MBT.db.iconScale)
  RefreshIconSliderText(MBT.db.iconScale)
  iconSlider:SetScript("OnValueChanged", function(self, value)
    local scale = math.floor(value * 10 + 0.5) / 10
    MBT.SetIconScale(MBT.db, scale)
    RefreshIconSliderText(scale)
    MBT.RefreshDisplay()
  end)

  RefreshSortRadios()
  RefreshLockButton()
  MBT.RefreshConfigRows()
end

function MBT.ToggleConfig()
  if not configFrame then return end
  if configFrame:IsShown() then
    configFrame:Hide()
  else
    MBT.RefreshConfigRows()
    configFrame:Show()
  end
end
