IPTalents = IPTalents or {}
local IPT = IPTalents

local STOCK_HIDE = { "InspectTalentFrameScrollFrame", "InspectTalentFramePointsBar" }
local STOCK_TABS = { "InspectTalentFrameTab1", "InspectTalentFrameTab2", "InspectTalentFrameTab3" }

local suppressed = false   -- stock children are only ever touched while this is true (and once to restore)

local function SetStockSuppressed(on)
  if on == suppressed then return end
  suppressed = on
  for _, n in ipairs(STOCK_HIDE) do
    local fr = _G[n]
    if fr then if on then fr:Hide() else fr:Show() end end
  end
  for _, n in ipairs(STOCK_TABS) do
    local t = _G[n]
    if t then t:SetAlpha(on and 0 or 1); t:EnableMouse(not on) end
  end
end

local function EnsureView()
  if not IPT.inspectView then
    IPT.inspectView = IPT.NewTreeView({ name = "IPTalentsInspectTalentFrame", parent = InspectTalentFrame,
                                      chrome = false, tabStyle = "top", readOnly = true, defaultTab = 1 })
  end
  return IPT.inspectView
end

function IPT.RefreshInspect()
  if not InspectTalentFrame then return end
  local guid = IPT.inspect.current
  local e = guid and IPT.inspect.cache[guid]
  local byClass = e and e.managed and IPTalentsData and IPTalentsData[e.era]
  local tree = byClass and byClass[e.classId]
  if tree and InspectTalentFrame:IsShown() then
    local v = EnsureView()
    if v.guid ~= guid or v.pickedPartial then    -- new target (or reply still arriving): primary tree
      v.guid = guid
      v.activeTab = IPT.PrimaryTab(tree, e.ranks, 1)
      v.pickedPartial = e.partial
    end
    SetStockSuppressed(true)
    v.frame:Show()
    IPT.RenderView(v, { era = e.era, ranks = e.ranks, availPts = 0 }, e.classId)
  else
    if IPT.inspectView then IPT.inspectView.frame:Hide() end
    SetStockSuppressed(false)
  end
end

local function OnInspectTarget()
  if not (InspectFrame and InspectFrame:IsShown()) then return end   -- CanInspect refused: no frame
  local unit = InspectFrame.unit
  local guid = unit and UnitGUID(unit)
  IPT.inspect.current = guid
  if guid and not IPT.inspect.cache[guid] then IPT.RequestInspect(guid) end
  IPT.RefreshInspect()
end

local function AttachInspect()
  if IPT._inspectHooked or not InspectFrame or not InspectTalentFrame then return end
  IPT._inspectHooked = true
  hooksecurefunc("InspectFrame_Show", OnInspectTarget)
  hooksecurefunc("InspectFrame_UnitChanged", OnInspectTarget)
  InspectFrame:HookScript("OnHide", function()
    IPT.inspect.current = nil
    wipe(IPT.inspect.cache)
    if IPT.inspectView then IPT.inspectView.guid = nil end   -- reopening = a fresh inspect: primary tree again
    IPT.RefreshInspect()
  end)
  InspectTalentFrame:HookScript("OnShow", function() IPT.RefreshInspect() end)
  InspectTalentFrame:HookScript("OnHide", function() IPT.RefreshInspect() end)
  for _, n in ipairs(STOCK_HIDE) do
    local fr = _G[n]
    if fr then fr:HookScript("OnShow", function(self) if suppressed then self:Hide() end end) end
  end
end

function IPT.InitInspect()
  if IPT._inspectInit then return end
  IPT._inspectInit = true
  if IsAddOnLoaded("Blizzard_InspectUI") then AttachInspect() end
  local w = CreateFrame("Frame")
  w:RegisterEvent("ADDON_LOADED")
  w:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_InspectUI" then AttachInspect() end
  end)
end
