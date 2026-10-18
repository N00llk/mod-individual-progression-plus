IPTalents = IPTalents or {}
local IPT = IPTalents
local RU = GetLocale and GetLocale() == "ruRU"

local FRAME_W, FRAME_H = 384, 512

local BG_X, BG_Y = 23, -77

local SCROLL_X, SCROLL_Y = BG_X, BG_Y
local SCROLL_W, SCROLL_H = 296, 332

local CHILD_W = SCROLL_W
local CHILD_H = 455

local BTN          = 37
local COL_X0       = 35                  -- 4 cols of 63px pitch center in 296px (35px margins)
local COL_SPACING  = 63
local ROW_Y0       = 20
local ROW_SPACING  = 63                  -- real row pitch (restored; no longer compressed)
local VANILLA_MAX_TIER = 6   -- 0-indexed last row of the 7-tier Vanilla trees; floors the

local ARROW_TEX  = "Interface\\TalentFrame\\UI-TalentArrows"
local BRANCH_TEX = "Interface\\TalentFrame\\UI-TalentBranches"
local ARROW_DOWN  = { 0, 0.5, 0, 0.5 }        -- "top" arrow: points down into the node
local ARROW_RIGHT = { 1.0, 0.5, 0, 0.5 }
local ARROW_LEFT  = { 0.5, 1.0, 0, 0.5 }
local BRANCH_VERT = { 0, 0.125, 0, 0.484375 } -- "down" segment
local BRANCH_HORZ = { 0.2578125, 0.3828125, 0, 0.5 } -- "right"/"left" segment
local ARROW_DOWN_OFF  = { 0, 0.5, 0.5, 1.0 }
local ARROW_RIGHT_OFF = { 1.0, 0.5, 0.5, 1.0 }
local ARROW_LEFT_OFF  = { 0.5, 1.0, 0.5, 1.0 }
local BRANCH_VERT_OFF = { 0, 0.125, 0.5, 0.984375 }
local BRANCH_HORZ_OFF = { 0.2578125, 0.3828125, 0.5, 1.0 }

local function BackgroundBase(token)
  return "Interface\\TalentFrame\\" .. (token or "MageFire")
end

local function colX(col)  return COL_X0 + col * COL_SPACING end
local function rowY(tier) return ROW_Y0 + tier * ROW_SPACING end

function IPT.IsReachable(node, spentInTab, ranks, byId)
  if not node then return false end
  if (spentInTab or 0) < (node.prereqPoints or 0) then return false end
  local pid = node.prereqTalent
  if pid and pid ~= 0 then
    local pre = byId and byId[pid]
    if pre and ((ranks and ranks[pid] or 0) < pre.maxRank) then return false end
  end
  return true
end

function IPT.SpecPoints(tree, ranks)
  local pts = { 0, 0, 0 }
  for _, n in ipairs(tree.talents) do
    if pts[n.tab] then pts[n.tab] = pts[n.tab] + ((ranks and ranks[n.id]) or 0) end
  end
  return pts
end

function IPT.PrimaryTab(tree, ranks, fallback)
  local pts = IPT.SpecPoints(tree, ranks)
  local best, bestPts = fallback, 0
  for i = 1, 3 do
    if pts[i] > bestPts then best, bestPts = i, pts[i] end
  end
  return best
end

local function TreeFor(era, classId)
  local byClass = IPTalentsData and IPTalentsData[era]
  return byClass and byClass[classId]
end

local function NodeAvailable(v, node)
  return IPT.IsReachable(node, v.spentActive, v.state.ranks, v.byId)
end

local function SetTreeBackground(v, bgToken)
  local base = BackgroundBase(bgToken)
  local f = v.frame
  f.bgTL:SetTexture(base .. "-TopLeft")
  f.bgTR:SetTexture(base .. "-TopRight")
  f.bgBL:SetTexture(base .. "-BottomLeft")
  f.bgBR:SetTexture(base .. "-BottomRight")
end

local function BuildChrome(v)
  local f = v.frame
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetWidth(FRAME_W)
  f:SetHeight(FRAME_H)
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
  f:EnableMouse(true)

  local chrome = {
    { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",  256, 256, "TOPLEFT",     2, -1 },
    { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight", 128, 256, "TOPRIGHT",    2, -1 },
    { "Interface\\TalentFrame\\UI-TalentFrame-BotLeft",              256, 256, "BOTTOMLEFT",  2, -1 },
    { "Interface\\TalentFrame\\UI-TalentFrame-BotRight",             128, 256, "BOTTOMRIGHT", 2, -1 },
  }
  for _, c in ipairs(chrome) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetTexture(c[1])
    t:SetWidth(c[2]); t:SetHeight(c[3])
    t:SetPoint(c[4], c[5], c[6])
  end

  f.portrait = f:CreateTexture(nil, "BACKGROUND")
  f.portrait:SetWidth(60); f.portrait:SetHeight(60)
  f.portrait:SetPoint("TOPLEFT", 7, -6)
  local function RefreshPortrait() SetPortraitTexture(f.portrait, "player") end
  RefreshPortrait()
  f:RegisterEvent("UNIT_PORTRAIT_UPDATE")
  f:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_PORTRAIT_UPDATE" and (unit == "player" or unit == nil) then RefreshPortrait() end
  end)
  f:SetScript("OnShow", function()
    RefreshPortrait()
    if TalentMicroButton then SetButtonPulse(TalentMicroButton, 0, 1) end
    PlaySound("TalentScreenOpen")
    UpdateMicroButtons()
  end)
  f:SetScript("OnHide", function()
    PlaySound("TalentScreenClose")
    UpdateMicroButtons()
  end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", 0, -18)
  f.title:SetText(RU and "Таланты" or "Talents")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("CENTER", f, "TOPRIGHT", -44, -25)

  f.petTalents = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.petTalents:SetWidth(82); f.petTalents:SetHeight(20)
  f.petTalents:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -44)   -- top-right slot (was the dev Reset button's)
  f.petTalents:SetText(RU and "Таланты питомца" or "Pet Talents")
  f.petTalents:SetScript("OnClick", function() if IPT.OpenStockTalents then IPT.OpenStockTalents() end end)
  if IPT._classId ~= 3 then f.petTalents:Hide() end
end

local function BuildTreeArea(v)
  local f = v.frame
  local name = f:GetName()

  f.bgTL = f:CreateTexture(nil, "ARTWORK")
  f.bgTL:SetWidth(256); f.bgTL:SetHeight(256)
  f.bgTL:SetPoint("TOPLEFT", BG_X, BG_Y)
  f.bgTR = f:CreateTexture(nil, "ARTWORK")
  f.bgTR:SetWidth(64); f.bgTR:SetHeight(256)
  f.bgTR:SetPoint("TOPLEFT", f.bgTL, "TOPRIGHT")
  f.bgBL = f:CreateTexture(nil, "ARTWORK")
  f.bgBL:SetWidth(256); f.bgBL:SetHeight(128)
  f.bgBL:SetPoint("TOPLEFT", f.bgTL, "BOTTOMLEFT")
  f.bgBR = f:CreateTexture(nil, "ARTWORK")
  f.bgBR:SetWidth(64); f.bgBR:SetHeight(128)
  f.bgBR:SetPoint("TOPLEFT", f.bgTL, "BOTTOMRIGHT")

  f.scroll = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
  f.scroll:SetWidth(SCROLL_W); f.scroll:SetHeight(SCROLL_H)
  f.scroll:SetPoint("TOPLEFT", SCROLL_X, SCROLL_Y)

  f.scroll:EnableMouseWheel(true)
  f.scroll:SetScript("OnMouseWheel", function(self, delta)
    self = self or this
    local d = delta or arg1 or 0
    local sb = getglobal(self:GetName() .. "ScrollBar")
    if sb then sb:SetValue(sb:GetValue() - d * ROW_SPACING) end
  end)

  f.container = CreateFrame("Frame", name .. "ScrollChild", f.scroll)
  f.container:SetWidth(CHILD_W); f.container:SetHeight(CHILD_H)
  f.scroll:SetScrollChild(f.container)

  local pointsBar = CreateFrame("Frame", nil, f)
  pointsBar:SetWidth(331); pointsBar:SetHeight(26)
  pointsBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 81)
  local borderTex = "Interface\\Buttons\\UI-Button-Borders2"
  local barBG = pointsBar:CreateTexture(nil, "BACKGROUND")
  barBG:SetAllPoints(pointsBar)
  barBG:SetTexture(borderTex)
  barBG:SetTexCoord(0, 0.646484375, 0.2109375, 0.4140625)

  local borderLeft = pointsBar:CreateTexture(nil, "BORDER")
  borderLeft:SetTexture(borderTex)
  borderLeft:SetWidth(6); borderLeft:SetHeight(18)
  borderLeft:SetPoint("LEFT", pointsBar, "LEFT", 4, 0)
  borderLeft:SetTexCoord(0, 0.01171875, 0.421875, 0.5625)
  local borderRight = pointsBar:CreateTexture(nil, "BORDER")
  borderRight:SetTexture(borderTex)
  borderRight:SetWidth(6); borderRight:SetHeight(18)
  borderRight:SetPoint("RIGHT", pointsBar, "RIGHT", -4, 0)
  borderRight:SetTexCoord(0.3046875, 0.31640625, 0.421875, 0.5625)
  local borderMiddle = pointsBar:CreateTexture(nil, "BORDER")
  borderMiddle:SetTexture(borderTex)
  borderMiddle:SetPoint("TOPLEFT", borderLeft, "TOPRIGHT")
  borderMiddle:SetPoint("BOTTOMRIGHT", borderRight, "BOTTOMLEFT")
  borderMiddle:SetTexCoord(0.01171875, 0.3046875, 0.421875, 0.5625)

  f.footerSpent = pointsBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  f.footerSpent:SetPoint("LEFT", pointsBar, "LEFT", 12, 1)
  f.footerSpent:SetJustifyH("LEFT")
  f.footerUnspent = pointsBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  f.footerUnspent:SetPoint("RIGHT", pointsBar, "RIGHT", -12, 1)
  f.footerUnspent:SetJustifyH("RIGHT")

  f.pools = {}            -- [tree] = { [nodeId] = button }  (per tree: a view can show many trees)
  f._branches = {}        -- pooled branch line textures
end

local function BuildTabs(v)
  local f = v.frame
  local name = f:GetName()
  f.tabs = {}
  for i = 1, 3 do
    local tab
    if v.tabStyle == "top" then
      tab = CreateFrame("Button", name .. "Tab" .. i, f, "TabButtonTemplate")
      if i == 1 then tab:SetPoint("TOPLEFT", 70, -40)
      else tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT") end
    else
      tab = CreateFrame("Button", name .. "Tab" .. i, f, "CharacterFrameTabButtonTemplate")
      if i == 1 then tab:SetPoint("BOTTOMLEFT", 15, 46)
      else tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", -15, 0) end
    end
    tab:SetScript("OnClick", function()
      IPT.ShowViewTab(v, i)
      PlaySound("igCharacterInfoTab")
    end)
    f.tabs[i] = tab
  end
  PanelTemplates_SetNumTabs(f, 3)
end

function IPT.NewTreeView(opts)
  local v = {
    readOnly  = opts.readOnly and true or false,
    tabStyle  = opts.tabStyle or "bottom",
    tabPad    = (opts.tabStyle == "top") and -10 or 0,   -- stock inspect tabs resize with -10
    activeTab = opts.defaultTab or 2,
    state     = { ranks = {} },
    classId   = 8,
  }
  local parent = opts.parent or UIParent
  v.frame = CreateFrame("Frame", opts.name, parent)
  if opts.chrome then
    BuildChrome(v)
  else
    v.frame:SetAllPoints(parent)
    v.frame:SetFrameLevel(parent:GetFrameLevel() + 20)
  end
  v.frame:Hide()
  BuildTreeArea(v)
  BuildTabs(v)
  return v
end

local MISSING_RU_GRANT = {
  [932902] = true, [932918] = true, [948034] = true, [948035] = true,
  [948036] = true, [948037] = true, [948038] = true,
  [948301] = true, [948450] = true,
}
local function NodeTooltip(btn)
  local v, node = btn.view, btn.node
  local rank = v.state.ranks[node.id] or 0
  GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  local gid = node.grant and (node.grant[(rank > 0) and rank or 1] or node.grant[1])
  if gid and tonumber(gid) and tonumber(gid) >= 920000
      and not (RU and MISSING_RU_GRANT[tonumber(gid)]) then
    GameTooltip:SetHyperlink("spell:" .. gid)
    GameTooltip:AddLine((RU and "Ранг " or "Rank ") .. rank .. "/" .. node.maxRank, 0.8, 0.8, 0.8)
    if not v.readOnly and rank >= 1 and rank < node.maxRank then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(RU and "Следующий ранг:" or "Next rank:", 1, 1, 1)
      GameTooltip:AddLine(node.tooltip[rank + 1] or "", 1, 0.82, 0, true)
    end
    GameTooltip:Show()
    return
  end

  GameTooltip:SetText(node.name, 1, 1, 1)
  GameTooltip:AddLine((RU and "Ранг " or "Rank ") .. rank .. "/" .. node.maxRank, 0.8, 0.8, 0.8)
  local shown = (rank > 0) and rank or 1
  GameTooltip:AddLine(node.tooltip[shown] or "", 1, 0.82, 0, true)
  if not v.readOnly and rank >= 1 and rank < node.maxRank then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(RU and "Следующий ранг:" or "Next rank:", 1, 1, 1)
    GameTooltip:AddLine(node.tooltip[rank + 1] or "", 1, 0.82, 0, true)
  end
  GameTooltip:Show()
end

local function OnNodeClick(btn)
  local v, node = btn.view, btn.node
  if v.readOnly then return end   -- inspect view: never learns
  local rank = v.state.ranks[node.id] or 0
  if rank >= node.maxRank then return end
  if (v.state.availPts or 0) < 1 then
    UIErrorsFrame:AddMessage(RU and "Недостаточно очков талантов." or "Not enough talent points.", 1, 0.2, 0.2, 1, 3)
    return
  end
  IPT.Learn(node.id)     -- server validates; UI updates when the SYNC arrives
end

local function EnsureButtons(v, tree)
  local f = v.frame
  local pool = f.pools[tree]
  if not pool then pool = {}; f.pools[tree] = pool end
  for _, node in ipairs(tree.talents) do
    if not pool[node.id] then
      f.nextTalentButtonId = (f.nextTalentButtonId or 0) + 1
      local buttonName = f:GetName() .. "Talent" .. f.nextTalentButtonId
      local b = CreateFrame("Button", buttonName, f.container, "TalentButtonTemplate")
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", colX(node.col), -rowY(node.tier))
      b.slot = _G[buttonName .. "Slot"]
      b.icon = _G[buttonName .. "IconTexture"]
      b.rankBorder = _G[buttonName .. "RankBorder"]
      b.rank = _G[buttonName .. "Rank"]

      local iconTex = node.icon or ""
      if iconTex ~= "" and not string.find(iconTex, "\\", 1, true) then
        iconTex = "Interface\\Icons\\" .. iconTex
      end
      if iconTex == "" then iconTex = "Interface\\Icons\\INV_Misc_QuestionMark" end
      b.icon:SetAllPoints(b)
      b.icon:SetTexture(iconTex)
      b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

      b.node = node
      b.view = v
      b:SetScript("OnEnter", NodeTooltip)
      b:SetScript("OnClick", OnNodeClick)
      pool[node.id] = b
    end
  end
  return pool
end

local function RenderButtons(v, tree)
  local f = v.frame
  for t, other in pairs(f.pools) do
    if t ~= tree then for _, b in pairs(other) do b:Hide() end end
  end
  local pool = f.pools[tree]
  for _, node in ipairs(tree.talents) do
    local b = pool[node.id]
    local rank = v.state.ranks[node.id] or 0
    if node.tab == v.activeTab then
      b:Show()
      b.rank:SetText(rank)
      local icon = b.icon
      local available = NodeAvailable(v, node)
      local maxed = rank >= node.maxRank
      local canLearn = not v.readOnly and available and rank < node.maxRank
          and (v.state.availPts or 0) > 0
      if maxed then
        b.slot:SetVertexColor(1, 0.82, 0)
        b.rankBorder:SetVertexColor(1, 0.78, 0.30)
      elseif canLearn then
        b.slot:SetVertexColor(0.1, 1, 0.1)
        b.rankBorder:SetVertexColor(0.25, 1, 0.25)
      else
        b.slot:SetVertexColor(1, 1, 1)
        b.rankBorder:SetVertexColor(1, 1, 1)
      end
      if maxed then
        if icon then icon:SetDesaturated(nil) end
        b.rank:SetTextColor(1, 0.82, 0.20)
      elseif rank > 0 then
        if icon then icon:SetDesaturated(nil) end
        b.rank:SetTextColor(0.1, 1, 0.1)
      elseif available then
        if icon then icon:SetDesaturated(nil) end
        if canLearn then b.rank:SetTextColor(0.1, 1, 0.1)
        else b.rank:SetTextColor(1, 1, 1) end
      else
        if icon then icon:SetDesaturated(1) end
        b.rank:SetTextColor(0.5, 0.5, 0.5)        -- locked: greyed out
      end
    else
      b:Hide()
    end
  end
end

function IPT.DrawArrows(tree, v)
  v = v or IPT.ownView
  local f = v.frame
  for _, t in ipairs(f._branches) do t:Hide() end
  local pool = f.pools[tree]
  for _, b in pairs(pool) do
    if b.arrow then b.arrow:Hide() end
  end

  local nb = 0
  local function branch(x, y, w, h, tc)
    nb = nb + 1
    local t = f._branches[nb]
    if not t then
      t = f.container:CreateTexture(nil, "ARTWORK")   -- behind the buttons
      t:SetTexture(BRANCH_TEX)
      f._branches[nb] = t
    end
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", x, -y)
    t:SetWidth(w); t:SetHeight(h)
    t:Show()
  end
  local function arrow(button, point, x, y, tc)
    local t = button.arrow
    if not t then
      t = button:CreateTexture(nil, "OVERLAY")
      t:SetTexture(ARROW_TEX)
      t:SetWidth(32); t:SetHeight(32)
      button.arrow = t
    end
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    t:ClearAllPoints()
    t:SetPoint("CENTER", button, point, x, y)
    t:Show()
  end

  local byId = {}
  for _, x in ipairs(tree.talents) do byId[x.id] = x end

  for _, node in ipairs(tree.talents) do
    if node.tab == v.activeTab and node.prereqTalent and node.prereqTalent ~= 0 then
      local from = byId[node.prereqTalent]
      if from and from.tab == node.tab then
        local fcx, fcy = colX(from.col) + BTN / 2, rowY(from.tier) + BTN / 2
        local ncx, ncy = colX(node.col) + BTN / 2, rowY(node.tier) + BTN / 2
        local dCol = node.col - from.col
        local dTier = node.tier - from.tier

        local on = NodeAvailable(v, node)
        local vert  = on and BRANCH_VERT  or BRANCH_VERT_OFF
        local horz  = on and BRANCH_HORZ  or BRANCH_HORZ_OFF
        local aDown = on and ARROW_DOWN   or ARROW_DOWN_OFF
        local aRt   = on and ARROW_RIGHT  or ARROW_RIGHT_OFF
        local aLt   = on and ARROW_LEFT   or ARROW_LEFT_OFF

        if dTier ~= 0 then
          local y0 = math.min(fcy, ncy)
          branch(fcx - 16, y0, 32, math.abs(ncy - fcy), vert)
        end
        if dCol ~= 0 then
          local x0 = math.min(fcx, ncx)
          branch(x0, ncy - 16, math.abs(ncx - fcx), 32, horz)
        end

        local targetButton = pool[node.id]
        if dCol > 0 then
          arrow(targetButton, "LEFT", -3, 0, aRt)
        elseif dCol < 0 then
          arrow(targetButton, "RIGHT", 3, 0, aLt)
        else
          arrow(targetButton, "TOP", 0, 3, aDown)
        end
      end
    end
  end
end

local function UpdateFooter(v, tree)
  local f = v.frame
  local pts = IPT.SpecPoints(tree, v.state.ranks)
  local tabName = (tree.tabs[v.activeTab] and tree.tabs[v.activeTab].name) or (RU and "Таланты" or "Talents")
  f.footerSpent:SetText(tabName .. (RU and ": " or " Talents: ") .. (pts[v.activeTab] or 0))
  if v.readOnly then
    f.footerUnspent:SetText(pts[1] .. "/" .. pts[2] .. "/" .. pts[3])
  else
    f.footerUnspent:SetText((RU and "Свободные очки: " or "Unspent Talents: ") .. (v.state.availPts or 0))
  end
end

local function RefreshHoveredTooltip(v)
  local owner = GameTooltip:GetOwner()
  if not owner or owner.view ~= v or not owner.node then return end
  if owner:IsShown() and owner:IsMouseOver() then
    NodeTooltip(owner)
  else
    GameTooltip:Hide()
  end
end

function IPT.ShowViewTab(v, i)
  local tree = TreeFor(v.state.era, v.classId)
  if not tree then return end
  v.activeTab = i
  local f = v.frame
  for t = 1, 3 do
    local tab = f.tabs[t]
    if tab and tree.tabs[t] then
      tab:SetText(tree.tabs[t].name)
      PanelTemplates_TabResize(tab, v.tabPad)
    end
  end
  PanelTemplates_SetTab(f, i)
  if tree.tabs[i] and tree.tabs[i].background then SetTreeBackground(v, tree.tabs[i].background) end

  v.byId = {}
  v.spentActive = 0
  for _, n in ipairs(tree.talents) do
    v.byId[n.id] = n
    if n.tab == i then v.spentActive = v.spentActive + (v.state.ranks[n.id] or 0) end
  end

  local maxTier = VANILLA_MAX_TIER
  for _, n in ipairs(tree.talents) do
    if n.tier > maxTier then maxTier = n.tier end
  end
  f.container:SetHeight(rowY(maxTier) + BTN + 20)

  EnsureButtons(v, tree)
  RenderButtons(v, tree)
  IPT.DrawArrows(tree, v)
  UpdateFooter(v, tree)
  RefreshHoveredTooltip(v)
end

function IPT.RenderView(v, state, classId)
  v.state, v.classId = state, classId
  if not TreeFor(state.era, classId) then return false end
  IPT.ShowViewTab(v, v.activeTab or 2)
  return true
end

local function OwnView()
  if not IPT.ownView then
    UIPanelWindows["IPTalentFrame"] = { area = "left", pushable = 6, whileDead = 1 }
    IPT.ownView = IPT.NewTreeView({ name = "IPTalentFrame", chrome = true, tabStyle = "bottom",
                                  readOnly = false, defaultTab = 2 })
    IPT.frame = IPT.ownView.frame
  end
  return IPT.ownView
end

function IPT.ShowTab(i)
  local v = OwnView()
  v.state, v.classId = IPT.state, IPT._classId
  IPT.ShowViewTab(v, i)
end

function IPT.Refresh()
  if not IPT.frame then return end
  if IPT.frame.petTalents then
    if IPT._classId == 3 then IPT.frame.petTalents:Show() else IPT.frame.petTalents:Hide() end
  end
  IPT.RenderView(IPT.ownView, IPT.state, IPT._classId)   -- default tab 2 = Fire (Improved Fireball)
end

function IPT.ShowPanel()
  OwnView()
  ShowUIPanel(IPT.frame)
  if IPT.frame:IsShown() then IPT.Refresh() end
end

function IPT.TogglePanel()
  OwnView()
  if IPT.frame:IsShown() then HideUIPanel(IPT.frame) else IPT.ShowPanel() end
end

local CLASS_ID_BY_TOKEN = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
  SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

function IPT.InitUI()
  local _, token = UnitClass("player")
  IPT._classId = CLASS_ID_BY_TOKEN[token or ""] or 8
  OwnView()
  hooksecurefunc("UpdateMicroButtons", function()
    if IPT.frame and IPT.frame:IsShown() and TalentMicroButton then
      TalentMicroButton:SetButtonState("PUSHED", 1)
    end
  end)
end
