IPTalents = IPTalents or {}
local IPT = IPTalents

IPT.inspect = IPT.inspect or { current = nil, cache = {} }

function IPT.ParseSync(state, message)
  local era, managed, pts, rest = string.match(message, "^SYNC%s+(%d+)%s+(%d+)%s+(%-?%d+)%s*(.*)$")
  if not era then return false end
  local seq, total, tail = string.match(rest, "^(%d+)/(%d+)%s*(.*)$")
  local isFirst
  if seq then
    isFirst = (tonumber(seq) == 1)
    rest = tail
  else
    isFirst = true   -- sentinel-less message = single chunk = reset
  end
  state.era = tonumber(era)
  state.availPts = tonumber(pts)
  state.isEraChar = (tonumber(managed) == 1)
  if isFirst then state.ranks = {} end
  for id, rank in string.gmatch(rest, "(%d+):(%d+)") do
    state.ranks[tonumber(id)] = tonumber(rank)
  end
  return true
end

function IPT.ParseInspectSync(cache, message)
  local guid, era, managed, cls, rest =
    string.match(message, "^ISYNC%s+(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s*(.*)$")
  if not guid then return nil end
  local seq, total, tail = string.match(rest, "^(%d+)/(%d+)%s*(.*)$")
  local isFirst = true
  if seq then
    isFirst = (tonumber(seq) == 1)
    rest = tail
  end
  local e = cache[guid]
  if not isFirst and not e then return guid end   -- orphan continuation (its chunk 1 was dropped): ignore
  if isFirst then
    e = { ranks = {} }
    cache[guid] = e
  end
  e.partial = (seq ~= nil) and (tonumber(seq) < tonumber(total))   -- more chunks still to come
  e.era = tonumber(era)
  e.managed = (tonumber(managed) == 1)
  e.classId = tonumber(cls)
  for id, rank in string.gmatch(rest, "(%d+):(%d+)") do
    e.ranks[tonumber(id)] = tonumber(rank)
  end
  return guid
end

IPT.SENTINEL_SPELL_ID = 932999

function IPT.CheckGeneration(serverStamp)
  IPT.state.serverGen = serverStamp
  local name = GetSpellInfo and GetSpellInfo(IPT.SENTINEL_SPELL_ID) or nil
  local clientStamp = name and string.match(name, "Gen (%x+)$") or nil
  IPT.state.clientGen = clientStamp
  if clientStamp ~= serverStamp then
    local ru = GetLocale and GetLocale() == "ruRU"
    local formatText = ru and
      "|cffff2020IPTalents: клиентский патч %s, сервер %s. " ..
      "Обновите Data/ruRU/patch-ruRU-Z.MPQ и полностью перезапустите игру.|r" or
      "|cffff2020IPTalents: your client patch is generation %s but the server is %s. " ..
      "Replace Data/ruRU/patch-ruRU-Z.MPQ with the current one and restart the game.|r"
    local msg = string.format(formatText, clientStamp or (ru and "ОТСУТСТВУЕТ" or "MISSING"), serverStamp)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
  end
end

function IPT.OnAddonMsg(prefix, message)
  if prefix ~= IPT.PREFIX then return end
  local gen = string.match(message, "^GEN%s+(%x+)$")
  if gen then
    IPT.CheckGeneration(gen)
    return
  end
  local iguid = string.match(message, "^ISYNC%s+(%S+)")
  if iguid then
    if iguid == IPT.inspect.current then
      IPT.ParseInspectSync(IPT.inspect.cache, message)
      if IPT.RefreshInspect then IPT.RefreshInspect() end   -- Inspect.lua (absent in tests)
    end
    return
  end
  if IPT.ParseSync(IPT.state, message) then
    if IPT.Refresh then IPT.Refresh() end   -- TalentUI hook (may be absent in tests)
  end
end

function IPT.Send(payload)
  SendAddonMessage(IPT.PREFIX, payload, "WHISPER", UnitName("player"))
end
function IPT.RequestSync() IPT.Send("HELLO") end
function IPT.Learn(id) IPT.Send("LEARN " .. id) end
function IPT.RequestInspect(guid) IPT.Send("INSPECT " .. guid) end

function IPT.InitComms()
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(self, event, prefix, message)
    IPT.OnAddonMsg(prefix, message)
  end)
end
