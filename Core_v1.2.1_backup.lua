-- VendorFarm Core: data parsing, pricing and the gold/hr model.
local ADDON, ns = ...
ns.VERSION = "1.2.1"

local DEFAULTS = {
  below = 4,          -- levels under you to include
  above = 1,          -- levels over you to include
  killSec = 25,       -- seconds per kill for a normal mob, incl. loot and rest
  eliteMult = 3,      -- elites take this many times longer
  elites = false,
  dungeons = false,
  rares = false,
  skinning = false,   -- add skinning loot (only if you have Skinning)
  useAH = false,      -- price non-grey items at Auctionator minus 5% cut when higher than vendor
  respawnCap = true,  -- cap kills/hr by how fast the mob respawns
  rows = 20,
  learn = true,       -- record your own kills and loot
  learnFull = 30,     -- kills until your own drop rates fully replace the database
  point = nil,
}
ns.DEFAULTS = DEFAULTS

-- Vanilla instance maps (raids and battlegrounds are left out on purpose).
ns.INSTANCES = {
  [33]="Shadowfang Keep", [34]="The Stockade", [36]="The Deadmines", [43]="Wailing Caverns",
  [47]="Razorfen Kraul", [48]="Blackfathom Deeps", [70]="Uldaman", [90]="Gnomeregan",
  [109]="Sunken Temple", [129]="Razorfen Downs", [189]="Scarlet Monastery", [209]="Zul'Farrak",
  [229]="Blackrock Spire", [230]="Blackrock Depths", [289]="Scholomance", [329]="Stratholme",
  [349]="Maraudon", [389]="Ragefire Chasm", [429]="Dire Maul",
}

local mobs      -- parsed list
local itemInfo  -- itemID -> {name, quality, sell}

local function parseList(s)
  local t = {}
  if s and s ~= "" then
    for id, e in s:gmatch("(%d+):(%d+)") do
      t[#t+1] = { tonumber(id), tonumber(e) / 10000 }
    end
  end
  return t
end

function ns.Parse()
  if mobs then return mobs end
  mobs, itemInfo = {}, {}
  for id, s in pairs(ns.ITEMS) do
    local name, q, sell = s:match("^(.-)|(%d+)|(%d+)$")
    itemInfo[id] = { name = name, quality = tonumber(q), sell = tonumber(sell) }
  end
  for id, s in pairs(ns.MOBS) do
    local f = { strsplit("|", s) }
    mobs[#mobs+1] = {
      id = id, name = f[1], minL = tonumber(f[2]), maxL = tonumber(f[3]), rank = tonumber(f[4]),
      coin = tonumber(f[5]), spawns = tonumber(f[6]), map = tonumber(f[7]),
      items = parseList(f[8]), rest = tonumber(f[9]) or 0, skin = parseList(f[10]),
      respawn = tonumber(f[11]) or 300,
    }
  end
  ns.MOBS, ns.ITEMS = nil, nil -- free the strings
  return mobs
end

-- Prices -------------------------------------------------------------------
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local pending = {}

-- Returns copper, source ("vendor" live, "db" fallback, "ah")
function ns.ItemValue(id)
  local db = VendorFarmDB
  local info = itemInfo[id]
  local name, _, quality, _, _, _, _, _, _, _, sell = GetItemInfo(id)
  local vendor, src
  if name and sell then
    vendor, src = sell, "vendor"
  else
    vendor, src = info and info.sell or 0, "db"
    if not pending[id] and C_Item and C_Item.RequestLoadItemDataByID then
      pending[id] = true
      C_Item.RequestLoadItemDataByID(id)
    end
  end
  quality = quality or (info and info.quality) or 1
  if db.useAH and quality >= 1 and Auctionator and Auctionator.API and Auctionator.API.v1
     and Auctionator.API.v1.GetAuctionPriceByItemID then
    local ok, ah = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, id)
    if ok and type(ah) == "number" and ah * 0.95 > vendor then
      return math.floor(ah * 0.95), "ah"
    end
  end
  return vendor, src
end

function ns.ItemName(id)
  local name = GetItemInfo(id)
  return name or (itemInfo[id] and itemInfo[id].name) or ("item " .. id)
end
function ns.ItemQuality(id)
  local _, _, q = GetItemInfo(id)
  return q or (itemInfo[id] and itemInfo[id].quality) or 1
end

-- Model --------------------------------------------------------------------
function ns.ValuePerKill(m)
  local db = VendorFarmDB
  local coin, items, rest, skin = ns.Effective(m)
  local v = coin + rest
  for _, it in ipairs(items) do v = v + it[2] * (ns.ItemValue(it[1])) end
  if db.skinning then
    for _, it in ipairs(skin) do v = v + it[2] * (ns.ItemValue(it[1])) end
  end
  return v
end

function ns.KillsPerHour(m)
  local db = VendorFarmDB
  local sec = db.killSec
  if m.rank == 1 or m.rank == 2 then sec = sec * db.eliteMult end
  local kph = 3600 / math.max(sec, 1)
  if db.respawnCap and m.respawn > 0 and m.map <= 1 then
    kph = math.min(kph, m.spawns * 3600 / m.respawn)
  end
  return kph
end

local function friendly(m)
  if m.observedOnly then return false end
  if not (NpcDB and NpcDB.friendlyToFaction) then return false end
  local ok, f = pcall(NpcDB.friendlyToFaction, m.id)
  if not ok or not f then return false end
  -- Anything friendly to either faction is a town/guard/PvP NPC, not a farm mob.
  return f == "A" or f == "H" or f == "AH"
end

function ns.ZoneName(m)
  if m.zoneName then return m.zoneName end
  if ns.INSTANCES[m.map] then return ns.INSTANCES[m.map] end
  if m.map > 1 then return "Instance " .. m.map end
  if NpcDB and NpcDB.zoneID then
    local ok, area = pcall(NpcDB.zoneID, m.id)
    if ok and area and area > 0 and C_Map and C_Map.GetAreaInfo then
      local name = C_Map.GetAreaInfo(area)
      if name and name ~= "" then return name, area end
    end
  end
  return m.map == 0 and "Eastern Kingdoms" or "Kalimdor"
end

function ns.Rank(level)
  local db = VendorFarmDB
  level = level or UnitLevel("player")
  local lo, hi = level - db.below, level + db.above
  local out = {}
  local all = ns.Parse()
  if db.learn then
    if not ns.known then ns.known = {}; for _, m in ipairs(all) do ns.known[m.id] = true end end
    local extra = ns.ObservedOnly(ns.known)
    if #extra > 0 then
      local merged = {}
      for i = 1, #all do merged[i] = all[i] end
      for _, m in ipairs(extra) do merged[#merged + 1] = m end
      all = merged
    end
  end
  for _, m in ipairs(all) do
    local mid = (m.minL + m.maxL) / 2
    local okRank = (m.rank == 0) or ((m.rank == 1 or m.rank == 2) and db.elites) or (m.rank == 4 and db.rares)
    local okMap = (m.map <= 1) or (db.dungeons and ns.INSTANCES[m.map] ~= nil)
    if mid >= lo and mid <= hi and okRank and okMap and not friendly(m) then
      local v = ns.ValuePerKill(m)
      local kph = ns.KillsPerHour(m)
      out[#out+1] = { mob = m, perKill = v, kph = kph, perHour = v * kph }
    end
  end
  table.sort(out, function(a, b) return a.perHour > b.perHour end)
  return out
end

-- Waypoint to the mob's busiest spawn area (needs QuestieDB + TomTom).
function ns.Waypoint(m)
  if not (TomTom and TomTom.AddWaypoint and NpcDB and NpcDB.spawns) then
    print("|cffffd100VendorFarm|r: waypoints need TomTom and QuestieDB."); return
  end
  local ok, spawns = pcall(NpcDB.spawns, m.id)
  if not ok or type(spawns) ~= "table" then print("|cffffd100VendorFarm|r: no spawn data for " .. m.name); return end
  local bestArea, bestList
  for area, list in pairs(spawns) do
    if type(list) == "table" and (not bestList or #list > #bestList) then bestArea, bestList = area, list end
  end
  if not bestList or #bestList == 0 then print("|cffffd100VendorFarm|r: no spawn data for " .. m.name); return end
  local sx, sy, n = 0, 0, 0
  for _, c in ipairs(bestList) do
    if c[1] and c[1] >= 0 then sx, sy, n = sx + c[1], sy + c[2], n + 1 end
  end
  if n == 0 then return end
  local x, y = sx / n, sy / n
  -- pick the real spawn closest to the centre so the arrow lands on a mob, not between camps
  local bx, by, bd
  for _, c in ipairs(bestList) do
    if c[1] and c[1] >= 0 then
      local d = (c[1]-x)^2 + (c[2]-y)^2
      if not bd or d < bd then bx, by, bd = c[1], c[2], d end
    end
  end
  local uiMap
  local lib = _G.LibQuestieDB
  if lib and lib.Support and lib.Support.Get then
    local ok2, zdb = pcall(lib.Support.Get, "ZoneDB")
    local map = ok2 and zdb and zdb.private and zdb.private.areaIdToUiMapId
    uiMap = map and map[bestArea]
  end
  if not uiMap then print("|cffffd100VendorFarm|r: couldn't map zone " .. tostring(bestArea) .. " for a waypoint."); return end
  TomTom:AddWaypoint(uiMap, bx / 100, by / 100, { title = m.name .. " (VendorFarm)", from = "VendorFarm" })
end

-- Events -------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local dirty = false
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    VendorFarmDB = VendorFarmDB or {}
    for k, v in pairs(DEFAULTS) do if VendorFarmDB[k] == nil then VendorFarmDB[k] = v end end
    VendorFarmDB.version = ns.VERSION
    if ns.InitOptions then ns.InitOptions() end
  elseif event == "PLAYER_LEVEL_UP" then
    if ns.Refresh then C_Timer.After(0.5, function() ns.Refresh(arg1) end) end
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    -- throttle: one refresh at most every 1.5 s while item data streams in
    if not dirty and ns.IsShown and ns.IsShown() then
      dirty = true
      C_Timer.After(1.5, function() dirty = false; ns.Refresh() end)
    end
  end
end)

SLASH_VENDORFARM1 = "/vfarm"
SLASH_VENDORFARM2 = "/vendorfarm"
SlashCmdList.VENDORFARM = function(msg)
  msg = (msg or ""):lower()
  local lvl = tonumber(msg)
  if msg == "resetdata" then
    VendorFarmDB.obs = {}
    print("|cffffd100VendorFarm|r: your recorded kills and loot were cleared.")
    if ns.Refresh then ns.Refresh() end
  elseif msg == "options" or msg == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
  else
    ns.Toggle(lvl)
  end
end
