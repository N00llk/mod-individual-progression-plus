IPTalents = IPTalents or {}
local IPT = IPTalents


function IPT.AggregateAttr(state, entries, attr)
  local flat, pct, any = 0, 1, false
  local ranks = (state and state.ranks) or {}
  for _, m in ipairs(entries or {}) do
    if m.attr == attr then
      local rank = ranks[m.talent] or 0
      if rank > 0 then
        local v = m.vals[rank]
        if v then
          any = true
          if m.kind == "pct" then pct = pct * (1 + v / 100) else flat = flat + v end
        end
      end
    end
  end
  return flat, pct, any
end

function IPT.FormatSecs(secs)
  if secs < 0 then secs = 0 end
  local tenths = math.floor(secs * 10 + 0.5)
  local whole = math.floor(tenths / 10)
  local frac = tenths - whole * 10
  if frac == 0 then return tostring(whole) end
  return whole .. "." .. frac
end

function IPT.RewriteCastBase(text, baseMs, flat, pct)
  if not text then return nil end
  if not (string.match(text, "^([%d%.]+)%s+sec cast$") or string.match(text, "^Instant")) then return nil end
  local newSecs = (baseMs / 1000) * (pct or 1) + (flat or 0) / 1000
  if newSecs <= 0 then return "Instant" end
  return IPT.FormatSecs(newSecs) .. " sec cast"
end


local function ActiveTree()
  if not (IPTalentsData and IPT.state) then return nil end
  local byClass = IPTalentsData[IPT.state.era]
  return byClass and byClass[IPT._classId or 8]
end

function IPT.ApplyToTooltip(tooltip)
  if not (IPT.state and IPT.state.isEraChar) then return end   -- WotLK chars keep native tooltips
  local tree = ActiveTree()
  if not tree then return end
  local name = tooltip.GetName and tooltip:GetName()
  if not name then return end
  local titleFS = _G[name .. "TextLeft1"]
  local spellName = titleFS and titleFS:GetText()
  local baseMs = spellName and tree.castTimeBase and tree.castTimeBase[spellName]
  if not baseMs then return end

  local flat, pct = IPT.AggregateAttr(IPT.state, tree.spellMods and tree.spellMods[spellName], "castTime")

  local changed = false
  for i = 1, tooltip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local fs = _G[name .. side .. i]
      local newText = fs and IPT.RewriteCastBase(fs:GetText(), baseMs, flat, pct)
      if newText and newText ~= fs:GetText() then fs:SetText(newText); changed = true end
    end
  end
  if changed then tooltip:Show() end   -- re-fit after changing lines
end

function IPT.InitTooltips()
  if IPT._tooltipHooked then return end
  IPT._tooltipHooked = true
  local function handler(self) IPT.ApplyToTooltip(self) end
  if GameTooltip then
    hooksecurefunc(GameTooltip, "SetSpell", handler)
    hooksecurefunc(GameTooltip, "SetAction", handler)
  end
end
