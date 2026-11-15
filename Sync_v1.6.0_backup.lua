-- VendorFarm Sync: shares kill/loot totals with other VendorFarm users through hidden addon
-- messages (guild, party/raid, and a hidden public channel). Nothing leaves the game.
--
-- Every record is a player's running TOTAL for one mob, keyed by the player who killed it
-- (the origin). A newer total replaces the older one, so hearing a record twice, or from a
-- relay, never double counts.
--   VendorFarmDB.shared[origin][npcID] = { k=kills, c=copper, sk=skinned, i={[item]=qty}, s={[item]=qty}, t=time() }
local ADDON, ns = ...

local PREFIX = "VFARM1"
local CHANNEL = "VendorFarmSync"
local SEND_GAP = 1.5          -- seconds between our messages (well under Blizzard's addon throttle)
local MAX_LEN = 250
local MAX_ORIGINS = 300       -- players kept
local MAX_AGE = 60 * 86400    -- forget a player's data after 60 days without news
local CAP_K = 500             -- one player's kills count at most this much per mob (limits skew)

local me
local queue, queued = {}, {}  -- pending { origin, npcID }
local sendTimer = 0

-- Sanity limits: drop records that can't be real.
local function sane(r)
  if not r.k or r.k <= 0 or r.k > 100000 then return false end
  if r.c and r.c / r.k > 50000 then return false end                -- > 5g coin per kill
  for _, q in pairs(r.i or {}) do if q / r.k > 20 then return false end end
  for _, q in pairs(r.s or {}) do if r.sk and r.sk > 0 and q / r.sk > 20 then return false end end
  return true
end

-- Combined data for one mob: your own totals + everyone else's (each capped at CAP_K kills).
local cache = {}
function ns.InvalidateCombined(id) if id then cache[id] = nil else wipe(cache) end end

function ns.CombinedObs(id)
  local c = cache[id]
  if c then return c end
  local db = VendorFarmDB
  local own = db.obs and db.obs[id]
  c = { k = 0, c = 0, sk = 0, i = {}, s = {}, ownK = 0, players = 0, otherK = 0 }
  local function add(r, isOwn)
    if not r or not r.k or r.k <= 0 then return end
    local scale = isOwn and 1 or math.min(1, CAP_K / r.k)
    c.k = c.k + r.k * scale
    c.c = c.c + (r.c or 0) * scale
    for item, q in pairs(r.i or {}) do c.i[item] = (c.i[item] or 0) + q * scale end
    local sScale = (not isOwn and r.sk and r.sk > CAP_K) and (CAP_K / r.sk) or 1
    c.sk = c.sk + (r.sk or 0) * sScale
    for item, q in pairs(r.s or {}) do c.s[item] = (c.s[item] or 0) + q * sScale end
    if isOwn then c.ownK = r.k else c.players = c.players + 1; c.otherK = c.otherK + r.k end
  end
  add(own, true)
  if db.syncUse then
    for origin, recs in pairs(db.shared or {}) do
      if origin ~= me then add(recs[id], false) end
    end
  end
  -- keep the name/level of mobs only you have seen, for the observed-only list
  if own then c.n, c.lo, c.hi, c.z, c.r = own.n, own.lo, own.hi, own.z, own.r end
  cache[id] = c
  return c
end

-- Encoding --------------------------------------------------------------------
local function pairsList(t)
  local out = {}
  for id, q in pairs(t or {}) do out[#out + 1] = id .. ":" .. q end
  table.sort(out)
  return out
end

-- Builds one or more messages for a record: "R;origin;npc;k;c;sk;items;skins", then
-- "C;origin;npc;k;items;skins" for whatever did not fit.
local function encode(origin, id, r)
  local items, skins = pairsList(r.i), pairsList(r.s)
  local msgs = {}
  local head = ("R;%s;%d;%d;%d;%d;"):format(origin, id, r.k, r.c or 0, r.sk or 0)
  local ii, si = 1, 1
  while true do
    local msg = head
    local part = {}
    while items[ii] and #msg + #table.concat(part, ",") + #items[ii] + 3 < MAX_LEN do
      part[#part + 1] = items[ii]; ii = ii + 1
    end
    msg = msg .. table.concat(part, ",") .. ";"
    local spart = {}
    while skins[si] and #msg + #table.concat(spart, ",") + #skins[si] + 2 < MAX_LEN do
      spart[#spart + 1] = skins[si]; si = si + 1
    end
    msgs[#msgs + 1] = msg .. table.concat(spart, ",")
    if not items[ii] and not skins[si] then break end
    head = ("C;%s;%d;%d;"):format(origin, id, r.k)
  end
  return msgs
end

local function parseList(s, into)
  for id, q in (s or ""):gmatch("(%d+):(%d+)") do into[tonumber(id)] = tonumber(q) end
end

local function store(origin, id, k, c, sk, items, skins, cont)
  local db = VendorFarmDB
  if origin == me then return end
  db.shared = db.shared or {}
  local recs = db.shared[origin]
  if not recs then
    -- keep the list bounded: drop the stalest player when full
    local n, oldest, oldestT = 0
    for o, rs in pairs(db.shared) do
      n = n + 1
      if not oldestT or (rs._t or 0) < oldestT then oldest, oldestT = o, rs._t or 0 end
    end
    if n >= MAX_ORIGINS and oldest then db.shared[oldest] = nil end
    recs = {}; db.shared[origin] = recs
  end
  local r = recs[id]
  if cont then
    if not r or r.k ~= k then return end           -- continuation of a version we don't have
  elseif not r or k > r.k then
    r = { k = k, c = c, sk = sk, i = {}, s = {} }  -- newer total replaces the old one
  elseif k < r.k then
    return                                         -- older than what we hold
  end
  parseList(items, r.i); parseList(skins, r.s)
  if not sane(r) then recs[id] = nil; return end
  r.t = time(); recs._t = r.t
  recs[id] = r
  ns.InvalidateCombined(id)
  ns.syncDirty = true
end

local function onMessage(text)
  local kind, rest = text:match("^([RC]);(.*)$")
  if kind == "R" then
    local origin, id, k, c, sk, items, skins = rest:match("^([^;]+);(%d+);(%d+);(%d+);(%d+);([^;]*);?(.*)$")
    if origin then store(origin, tonumber(id), tonumber(k), tonumber(c), tonumber(sk), items, skins, false) end
  elseif kind == "C" then
    local origin, id, k, items, skins = rest:match("^([^;]+);(%d+);(%d+);([^;]*);?(.*)$")
    if origin then store(origin, tonumber(id), tonumber(k), nil, nil, items, skins, true) end
  end
end

-- Sending ---------------------------------------------------------------------
local function enqueue(origin, id)
  local key = origin .. "#" .. id
  if queued[key] then return end
  queued[key] = true
  queue[#queue + 1] = { origin, id }
end

-- Your own changed mobs go out first; then everything you hold, slowly, so newcomers catch up.
function ns.SyncMarkOwn(id) if me then enqueue(me, id) end end

local function enqueueAll()
  local db = VendorFarmDB
  for id, o in pairs(db.obs or {}) do if o.k and o.k > 0 then enqueue(me, id) end end
  for origin, recs in pairs(db.shared or {}) do
    for id, r in pairs(recs) do if type(id) == "number" and r.k then enqueue(origin, id) end end
  end
end

local channelNum
local function targets()
  local t = {}
  if IsInGuild and IsInGuild() then t[#t + 1] = { "GUILD" } end
  if IsInRaid and IsInRaid() then t[#t + 1] = { "RAID" }
  elseif IsInGroup and IsInGroup() then t[#t + 1] = { "PARTY" } end
  if VendorFarmDB.syncPublic then
    channelNum = GetChannelName and GetChannelName(CHANNEL)
    if channelNum and channelNum > 0 then t[#t + 1] = { "CHANNEL", channelNum } end
  end
  return t
end

local pendingMsgs = {}
local function sendNext()
  if #pendingMsgs == 0 then
    local nxt = table.remove(queue, 1)
    if not nxt then return end
    queued[nxt[1] .. "#" .. nxt[2]] = nil
    local db = VendorFarmDB
    local r = nxt[1] == me and db.obs and db.obs[nxt[2]] or (db.shared and db.shared[nxt[1]] and db.shared[nxt[1]][nxt[2]])
    if not r or not r.k or r.k <= 0 then return end
    pendingMsgs = encode(nxt[1], nxt[2], r)
  end
  local msg = table.remove(pendingMsgs, 1)
  for _, t in ipairs(targets()) do
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, t[1], t[2])
  end
end

local function canSend()
  if not (VendorFarmDB and VendorFarmDB.syncShare and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  local inInst = IsInInstance and IsInInstance()
  if inInst then return false end    -- addon messages can be restricted inside instances
  return true
end

local function joinChannel()
  if not VendorFarmDB.syncPublic then return end
  if GetChannelName and GetChannelName(CHANNEL) > 0 then return end
  if JoinTemporaryChannel then
    pcall(JoinTemporaryChannel, CHANNEL)
  elseif JoinChannelByName then
    pcall(JoinChannelByName, CHANNEL)
  end
  -- keep it out of every chat tab; it's for addon data only
  C_Timer.After(2, function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local cf = _G["ChatFrame" .. i]
      if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
    end
  end)
end

function ns.SyncStatus()
  local db = VendorFarmDB
  local players, mobs, kills = 0, {}, 0
  for origin, recs in pairs(db.shared or {}) do
    if origin ~= me then
      local any = false
      for id, r in pairs(recs) do if type(id) == "number" then any = true; mobs[id] = true; kills = kills + (r.k or 0) end end
      if any then players = players + 1 end
    end
  end
  local n = 0; for _ in pairs(mobs) do n = n + 1 end
  return players, n, kills, (GetChannelName and GetChannelName(CHANNEL) or 0) > 0
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, prefix, text, _, sender)
  if event == "PLAYER_LOGIN" then
    local name, realm = UnitFullName("player")
    me = name and (name .. "-" .. (realm or GetNormalizedRealmName and GetNormalizedRealmName() or "")) or "me"
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    -- forget players we have not heard from in 60 days
    local cut = time() - MAX_AGE
    for origin, recs in pairs(VendorFarmDB.shared or {}) do
      if (recs._t or 0) < cut then VendorFarmDB.shared[origin] = nil end
    end
    C_Timer.After(20, function() joinChannel(); enqueueAll() end)
    -- after the first full pass, re-share everything every 30 minutes
    if C_Timer.NewTicker then C_Timer.NewTicker(1800, enqueueAll) end
  elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX and VendorFarmDB and VendorFarmDB.syncUse then
    if sender == me or (Ambiguate and Ambiguate(sender, "none") == UnitName("player")) then return end
    if type(text) == "string" then onMessage(text) end
  end
end)

-- Elapsed-time throttle: one message every SEND_GAP seconds while allowed.
f:SetScript("OnUpdate", function(_, e)
  sendTimer = sendTimer + e
  if sendTimer < SEND_GAP then return end
  sendTimer = 0
  if canSend() then sendNext() end
  if ns.syncDirty and ns.IsShown and ns.IsShown() then ns.syncDirty = false; ns.Refresh() end
end)
