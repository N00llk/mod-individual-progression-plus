IPTalents = IPTalents or {}
local IPT = IPTalents

local function GuardStockToggle()
  if IPT._stockToggleWrapped or not PlayerTalentFrame_Toggle then return end
  IPT._stockToggleWrapped = true
  local stockToggle = PlayerTalentFrame_Toggle
  PlayerTalentFrame_Toggle = function(pet, ...)
    if not pet and not IPT._allowStock and IPT.state and IPT.state.isEraChar then
      IPT.TogglePanel()
      return
    end
    return stockToggle(pet, ...)
  end

  local function GlyphsBlockedByEra()
    return IPT.state and IPT.state.era and IPT.state.era < 2 and IPT._classId ~= 6
  end
  local function GlyphUnavailable()
    local msg = GetLocale() == "ruRU" and
      "Символы доступны в эпохе Wrath of the Lich King." or
      "Glyphs are available in the Wrath of the Lich King era."
    UIErrorsFrame:AddMessage(msg, 1, 0.2, 0.2, 1, 3)
  end
  local stockGlyphToggle = PlayerTalentFrame_ToggleGlyphFrame
  if stockGlyphToggle then
    PlayerTalentFrame_ToggleGlyphFrame = function(...)
      if GlyphsBlockedByEra() then return GlyphUnavailable() end
      return stockGlyphToggle(...)
    end
  end
  local stockGlyphOpen = PlayerTalentFrame_OpenGlyphFrame
  if stockGlyphOpen then
    PlayerTalentFrame_OpenGlyphFrame = function(...)
      if GlyphsBlockedByEra() then return GlyphUnavailable() end
      return stockGlyphOpen(...)
    end
  end
end

local function GuardStockFrame()
  if not PlayerTalentFrame or PlayerTalentFrame._eraGuarded then return end
  GuardStockToggle()
  PlayerTalentFrame._eraGuarded = true
  PlayerTalentFrame:HookScript("OnShow", function(self)
    if IPT._allowStock then return end
    if IPT.state and IPT.state.isEraChar then
      HideUIPanel(self)     -- era chars never see the WotLK tree...
      IPT.ShowPanel()        -- ...a direct stock-panel open shows their era tree
    end
  end)
end

local function IsPetSpecTab(tab)
  return tab and type(tab.specIndex) == "string" and tab.specIndex:find("petspec") ~= nil
end

local function SelectPetSpec()
  for i = 1, 6 do
    local tab = _G["PlayerSpecTab" .. i]
    if tab and tab:IsShown() and IsPetSpecTab(tab) then
      tab:Click()
      return true
    end
  end
  return false
end

local function ApplyPetOnly(tab)
  if IPT._petOnlyMode and not IsPetSpecTab(tab) then
    tab:SetAlpha(0); tab:EnableMouse(false)
  else
    tab:SetAlpha(1); tab:EnableMouse(true)
  end
end

local function GuardPlayerSpecTabs()
  for i = 1, 6 do
    local tab = _G["PlayerSpecTab" .. i]
    if tab then
      if not tab._eraPetGuarded then
        tab._eraPetGuarded = true
        tab:HookScript("OnShow", function(self) ApplyPetOnly(self) end)
      end
      ApplyPetOnly(tab)   -- apply to whatever is shown right now
    end
  end
  if PlayerTalentFrame and not PlayerTalentFrame._eraPetHideHooked then
    PlayerTalentFrame._eraPetHideHooked = true
    PlayerTalentFrame:HookScript("OnHide", function()
      IPT._petOnlyMode = false
      for i = 1, 6 do
        local t = _G["PlayerSpecTab" .. i]
        if t then t:SetAlpha(1); t:EnableMouse(true) end
      end
    end)
  end
end

function IPT.OpenStockTalents()
  if not UnitExists("pet") then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd000IPTalents:|r summon a pet to view its talent tree.")
    return
  end
  IPT._allowStock = true
  if not IsAddOnLoaded("Blizzard_TalentUI") then LoadAddOn("Blizzard_TalentUI") end
  if PlayerTalentFrame then
    IPT._petOnlyMode = true
    ShowUIPanel(PlayerTalentFrame)
    GuardPlayerSpecTabs()   -- attach OnShow guards + hide player tabs now (catches the click cascade)
    SelectPetSpec()         -- land on the pet's own tree (correct per active pet)
  end
  IPT._allowStock = false
end

function IPT.InitHook()
  if IPT._hooked then return end
  IPT._hooked = true
  if IsAddOnLoaded("Blizzard_TalentUI") then GuardStockFrame() end
  local w = CreateFrame("Frame")
  w:RegisterEvent("ADDON_LOADED")
  w:SetScript("OnEvent", function(self, event, name)
    if name == "Blizzard_TalentUI" then GuardStockFrame() end
  end)
end
