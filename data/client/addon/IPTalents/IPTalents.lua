IPTalents = IPTalents or {}
local IPT = IPTalents

IPT.PREFIX = "IPTAL"
IPT.state = { era = nil, availPts = 0, ranks = {}, isEraChar = false }

function IPT.Init()
  if IPT._inited then return end
  IPT._inited = true
  if IPT.InitComms then IPT.InitComms() end
  if IPT.InitUI then IPT.InitUI() end
  if IPT.InitHook then IPT.InitHook() end
  if IPT.InitTooltips then IPT.InitTooltips() end
  if IPT.InitInspect then IPT.InitInspect() end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  IPT.Init()
  if IPT.RequestSync then IPT.RequestSync() end   -- pull fresh state (HELLO)
end)

SLASH_IPTALENTS_PET1 = "/pettalents"
SLASH_IPTALENTS_PET2 = "/pettalent"
SlashCmdList["IPTALENTS_PET"] = function()
  if IPT.OpenStockTalents then IPT.OpenStockTalents() end
end
