-- VendorFarm Gathering tab: herb and ore nodes per zone, skinning and fishing, ranked by gold/hr.
-- Node values, spawn spots (weighted by how often their spawn pool has them up) and fishing loot
-- come from CMaNGOS (DataNodes.lua). Nodes and catches per hour are estimates until you have
-- gathered or fished in a zone; then your own rate takes over.
local ADDON, ns = ...

local BREAK = 300          -- more than 5 minutes between gathers isn't counted as gathering time
local ALPHA = 0.15
local NODE_FULL, VALUE_FULL, FISH_FULL = 20, 30, 40
local FISH_DEFAULT = 150   -- catches per hour before you have fished
local SKILL = { herb = 182, ore = 186, skin = 393, fish = 356 }
local CONT = { [0] = 1415, [1] = 1414 }   -- Eastern Kingdoms, Kalimdor

-- Profession skills ---------------------------------------------------------
function ns.ProfSkills()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then return out end
  local list = { GetProfessions() }
  for i = 1, 6 do
    local idx = list[i]
    if idx then
      local ok, _, _, level, _, _, _, line = pcall(GetProfessionInfo, idx)
      if ok and line then
        for k, id in pairs(SKILL) do if id == line then out[k] = level end end
      end
    end
  end
  return out
end

-- Zone of the player (walk up from subzones/cities to the zone map).
local function zoneMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local id = C_Map.GetBestMapForUnit("player")
  for _ = 1, 4 do
    local info = id and C_Map.GetMapInfo(id)
    if not info then return id end
    if info.mapType == 3 or not info.parentMapID or info.parentMapID == 0 then return id end
    local parent = C_Map.GetMapInfo(info.parentMapID)
    if not parent or parent.mapType < 3 then return id end
    id = info.parentMapID
  end
  return id
end
ns.PlayerZoneMap = zoneMap

local function zoneName(id)
  local info = id and C_Map and C_Map.GetMapInfo(id)
  return info and info.name or ("Map " .. tostring(id))
end

-- Node -> zone mapping (done in small chunks the first time the tab opens) --------------
local nodes        -- [objectID] = { kind, skill, name, items = {{id, expected}} }
local zoneNodes    -- [uiMap] = { [objectID] = weight up at a time }
local mapState = "idle"   -- idle | working | done | failed
local progress = 0

local function parseNodes()
  if nodes then return end
  nodes = {}
  for id, t in pairs(ns.NODES) do
    local items = {}
    for it, e in t[4]:gmatch("(%d+):(%d+)") do items[#items + 1] = { tonumber(it), tonumber(e) / 10000 } end
    nodes[id] = { kind = t[1], skill = t[2], name = t[3], items = items }
  end
end
function ns.NodeInfo(id) parseNodes(); return nodes[id] end

local function rectOf(uiMap)
  local ok1, _, tl = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(0, 0))
  local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(1, 1))
  if not (ok1 and ok2 and tl and br) then return end
  local top, left = tl:GetXY()
  local bottom, right = br:GetXY()
  if top == bottom or left == right then return end
  return top, left, bottom, right
end

local function startMapping()
  if mapState ~= "idle" then return end
  parseNodes()
  if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapInfoAtPosition and CreateVector2D) then
    mapState = "failed"; return
  end
  local jobs = {}
  for m, s in pairs(ns.NODESPAWNS) do
    for e, x, y, w in s:gmatch("(%d+),(%-?%d+),(%-?%d+),(%d+)") do
      jobs[#jobs + 1] = { m, tonumber(e), tonumber(x) * 25, tonumber(y) * 25, tonumber(w) / 100 }
    end
  end
  local rects = {}
  for m, ui in pairs(CONT) do
    local t, l, b, r = rectOf(ui)
    if t then rects[m] = { t, l, b, r } end
  end
  if not next(rects) then mapState = "failed"; return end
  zoneNodes = {}
  mapState = "working"
  local i = 1
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function()
    local stop = math.min(#jobs, i + 1200)
    for k = i, stop do
      local j = jobs[k]
      local rc = rects[j[1]]
      if rc then
        local x = (rc[2] - j[4]) / (rc[2] - rc[4])
        local y = (rc[1] - j[3]) / (rc[1] - rc[3])
        if x > 0 and x < 1 and y > 0 and y < 1 then
          local ok, info = pcall(C_Map.GetMapInfoAtPosition, CONT[j[1]], x, y)
          if ok and info and info.mapID then
            local z = zoneNodes[info.mapID] or {}
            z[j[2]] = (z[j[2]] or 0) + j[5]
            zoneNodes[info.mapID] = z
          end
        end
      end
    end
    i = stop + 1
    progress = i / math.max(#jobs, 1)
    if i > #jobs then
      f:SetScript("OnUpdate", nil)
      mapState = next(zoneNodes) and "done" or "failed"
      local n = 0; for _ in pairs(zoneNodes) do n = n + 1 end
      ns.Debug("gathering: %d node spots mapped into %d zones", #jobs, n)
      if ns.Refresh then ns.Refresh() end
    end
  end)
end

-- Values --------------------------------------------------------------------
local function lootValue(items)
  local v = 0
  for _, it in ipairs(items) do v = v + it[2] * (ns.ItemValue(it[1])) end
  return v
end

local fishTables  -- [areaID] = items
local function fishValue(area)
  fishTables = fishTables or {}
  if not fishTables[area] then
    local items = {}
    for it, e in (ns.FISH[area] or ""):gmatch("(%d+):(%d+)") do items[#items + 1] = { tonumber(it), tonumber(e) / 10000 } end
    fishTables[area] = items
  end
  return lootValue(fishTables[area]), fishTables[area]
end

local function blend(est, learned, n, full)
  if not learned or not n or n <= 0 then return est, 0 end
  local w = math.min(1, n / full)
  return (1 - w) * est + w * learned, w
end

-- Learned data per zone: db.gather[uiMap] = { n, v, gap, gn, fn, fv }
local function gstat(z)
  local db = VendorFarmDB
  db.gather = db.gather or {}
  db.gather[z] = db.gather[z] or { n = 0, v = 0, gn = 0, fn = 0, fv = 0 }
  return db.gather[z]
end

-- Ranking -------------------------------------------------------------------
-- Rows: { name, tag, lvl, rateText, per, perHour, kind, zone, parts }
function ns.GatherRank(level)
  local db = VendorFarmDB
  level = level or UnitLevel("player")
  local skills = ns.ProfSkills()
  local out = {}
  if mapState == "idle" then startMapping() end
  local here = db.zoneOnly and zoneMap()
  local maxSkill = math.min(300, level * 5)
  local hSkill = skills.herb or maxSkill
  local oSkill = skills.ore or maxSkill
  local mounted = level >= 40

  local function levels(z)
    if not (C_Map and C_Map.GetMapLevels) then return end
    local ok, lo, hi = pcall(C_Map.GetMapLevels, z)
    if ok and lo and lo > 0 then return lo, hi end
  end
  local function okZone(z)
    if here then return z == here end
    local lo = levels(z)
    return not lo or lo <= level + db.above + 3
  end
  local function lvlText(z)
    local lo, hi = levels(z)
    return lo and (lo == hi and tostring(lo) or (lo .. "-" .. hi)) or ""
  end

  -- herb + ore nodes
  if (db.gHerb or db.gOre) and mapState == "done" then
    for z, list in pairs(zoneNodes) do
      if okZone(z) then
        local up, value, parts = 0, 0, {}
        for id, w in pairs(list) do
          local nd = nodes[id]
          if nd and ((nd.kind == 1 and db.gHerb and nd.skill <= hSkill) or (nd.kind == 2 and db.gOre and nd.skill <= oSkill)) then
            local v = lootValue(nd.items)
            up = up + w; value = value + w * v
            parts[#parts + 1] = { id = id, name = nd.name, skill = nd.skill, kind = nd.kind, w = w, v = v }
          end
        end
        if up >= 1 then
          local st = gstat(z)
          local perEst = value / up
          local per, vw = blend(perEst, st.n > 0 and st.v / st.n or nil, st.n, VALUE_FULL)
          local nphEst = 60 * up / (up + 40) * (mounted and 1 or 0.7)
          local nph, rw = blend(nphEst, st.gap and 3600 / st.gap or nil, st.gn, NODE_FULL)
          local tag = (db.gHerb and db.gOre) and "Herbs + ore" or (db.gHerb and "Herbs" or "Ore")
          out[#out + 1] = { kind = "nodes", zone = z, name = zoneName(z), tag = tag, lvl = lvlText(z),
            rate = ("~%d up, %d/hr%s"):format(up + 0.5, nph + 0.5, rw >= 1 and "" or " est"),
            per = per, perHour = per * nph, up = up, nph = nph, nphEst = nphEst, rw = rw, vw = vw,
            perEst = perEst, parts = parts, st = st }
        end
      end
    end
  end

  -- fishing
  if db.gFish then
    local catches = blend(FISH_DEFAULT, db.fishGap and 3600 / db.fishGap or nil, db.fishN or 0, FISH_FULL)
    for area in pairs(ns.FISH) do
      local z = ns.UiMapForArea and ns.UiMapForArea(area)
      if z and okZone(z) then
        local info = C_Map.GetMapInfo(z)
        if info and (info.mapType == 3 or info.mapType == 4) then
          local vEst, items = fishValue(area)
          local st = gstat(z)
          local per, vw = blend(vEst, st.fn > 0 and st.fv / st.fn or nil, st.fn, FISH_FULL)
          out[#out + 1] = { kind = "fish", zone = z, name = zoneName(z), tag = "Fishing", lvl = lvlText(z),
            rate = ("%d catches/hr%s"):format(catches + 0.5, (db.fishN or 0) >= FISH_FULL and "" or " est"),
            per = per, perHour = per * catches, items = items, vw = vw, st = st }
        end
      end
    end
  end

  -- skinning: best skinnable mob per zone in your level range (kills/hr x skinning loot only)
  if db.gSkin then
    local keepZone, keepSkin = db.zoneOnly, db.skinning
    db.zoneOnly = false
    local ok, list = pcall(ns.Rank, level)
    db.zoneOnly = keepZone
    if ok then
      local best = {}
      for _, r in ipairs(list) do
        local m = r.mob
        local _, _, _, skin = ns.Effective(m)
        local sv = lootValue(skin)
        if sv > 0 then
          local zn, area = ns.ZoneName(m)
          local z = area and ns.UiMapForArea(area)
          if z and okZone(z) then
            local hr = sv * r.kph
            if not best[z] or hr > best[z].perHour then
              best[z] = { kind = "skin", zone = z, name = zoneName(z), tag = "Skinning: " .. m.name, lvl = lvlText(z),
                rate = ("%d kills/hr"):format(r.kph + 0.5), per = sv, perHour = hr, mob = m }
            end
          end
        end
      end
      for _, r in pairs(best) do out[#out + 1] = r end
    end
  end

  table.sort(out, function(a, b) return a.perHour > b.perHour end)
  return out, mapState, progress
end

function ns.GatherTooltip(owner, r)
  local money = ns.Money
  local tt = GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  tt:AddLine(r.name .. "  |cffaaaaaa" .. r.tag .. "|r", 1, 1, 1)
  local function row(l, v) tt:AddDoubleLine(l, v, 0.8, 0.8, 0.8, 1, 1, 1) end
  local function note(t) tt:AddLine(t, 0.6, 0.6, 0.6, true) end
  if r.kind == "nodes" then
    row("Nodes up at a time (you can gather)", ("~%d"):format(r.up + 0.5))
    row("Nodes per hour", ("%d%s"):format(r.nph + 0.5, r.rw >= 1 and " (yours)" or (r.rw > 0 and (" (%d%% yours)"):format(r.rw * 100) or " (estimate)")))
    row("Value per node", money(r.per) .. (r.vw > 0 and (" (%d%% your loot)"):format(r.vw * 100) or ""))
    if r.st and r.st.n > 0 then row("You gathered here", ("%d nodes, %s"):format(r.st.n, money(r.st.v))) end
    tt:AddLine(" ")
    table.sort(r.parts, function(a, b) return a.w * a.v > b.w * b.v end)
    for i = 1, math.min(#r.parts, 10) do
      local p = r.parts[i]
      tt:AddDoubleLine(("%s |cff888888(%d)|r  ~%.1f up"):format(p.name, p.skill, p.w), money(p.v) .. " each",
        p.kind == 1 and 0.4 or 0.8, p.kind == 1 and 1 or 0.7, p.kind == 1 and 0.4 or 0.5, 1, 1, 1)
    end
    tt:AddLine(" ")
    note("Nodes up: spawn spots in this zone weighted by how often the game has a node there. Only nodes your skill can gather count.")
    note("Nodes per hour starts as an estimate (more nodes up = more per hour, slower without a mount) and switches to your own pace after 20 nodes here.")
  elseif r.kind == "fish" then
    row("Catches per hour", r.rate)
    row("Value per catch", money(r.per))
    if r.st and r.st.fn > 0 then row("You caught here", ("%d, %s"):format(r.st.fn, money(r.st.fv))) end
    tt:AddLine(" ")
    local its = {}
    for _, it in ipairs(r.items or {}) do its[#its + 1] = { it[1], it[2], it[2] * (ns.ItemValue(it[1])) } end
    table.sort(its, function(a, b) return a[3] > b[3] end)
    for i = 1, math.min(#its, 8) do
      tt:AddDoubleLine(("%s %.0f%%"):format(ns.ItemName(its[i][1]), its[i][2] * 100), money(its[i][3]) .. " per catch", 1, 1, 1, 1, 1, 1)
    end
    tt:AddLine(" ")
    note("Open-water loot for this zone. Pools and low fishing skill aren't counted; a low skill means more fish get away. Your catch rate is learned from your fishing.")
  else
    row("Mob", r.mob.name)
    row("Kills per hour", r.rate)
    row("Skinning loot per kill", money(r.per))
    note("Skinning only. The mob's own drops are on the Mobs tab.")
  end
  tt:Show()
end

-- Learning from your gathering and fishing ----------------------------------
local seen = {}
local lastGather, lastFish

local function slotValue(slot)
  local t = GetLootSlotType(slot)
  if t == (Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2) then
    local src = { GetLootSourceInfo(slot) }
    local q = src[2]
    return (type(q) == "number" and not (issecretvalue and issecretvalue(q))) and q or 0
  end
  local link = GetLootSlotLink(slot)
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  local _, _, qty = GetLootSlotInfo(slot)
  if id then return (qty or 1) * (ns.ItemValue(id)) end
  return 0
end

local function onLoot()
  local db = VendorFarmDB
  local n = GetNumLootItems and GetNumLootItems() or 0
  if n == 0 then return end
  local now = GetTime()
  local z = zoneMap()
  if not z then return end
  if IsFishingLoot and IsFishingLoot() then
    local v = 0
    for s = 1, n do v = v + slotValue(s) end
    local st = gstat(z); st.fn = st.fn + 1; st.fv = st.fv + v
    if lastFish and now - lastFish < 120 then
      local gap = now - lastFish
      db.fishGap = db.fishGap and (db.fishGap * (1 - ALPHA) + gap * ALPHA) or gap
      db.fishN = (db.fishN or 0) + 1
    end
    lastFish = now
    ns.Debug("fishing catch in %s worth %d", zoneName(z), v)
    return
  end
  local ok, guid = pcall(GetLootSourceInfo, 1)
  if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
  if not guid:find("^GameObject") then return end
  local entry = tonumber((select(6, strsplit("-", guid))))
  parseNodes()
  if not entry or not nodes[entry] or seen[guid] then return end
  seen[guid] = true
  local v = 0
  for s = 1, n do v = v + slotValue(s) end
  local st = gstat(z); st.n = st.n + 1; st.v = st.v + v
  if lastGather and now - lastGather < BREAK then
    local gap = now - lastGather
    st.gap = st.gap and (st.gap * (1 - ALPHA) + gap * ALPHA) or gap
    st.gn = st.gn + 1
  end
  lastGather = now
  ns.Debug("gathered %s in %s worth %d (%d here)", nodes[entry].name, zoneName(z), v, st.n)
end

local f = CreateFrame("Frame")
f:RegisterEvent("LOOT_READY")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, ev)
  if ev == "PLAYER_LOGIN" then
    -- first run: tick the gathering professions you have
    local db = VendorFarmDB
    if db.gHerb == nil then
      local sk = ns.ProfSkills()
      db.gHerb = sk.herb ~= nil; db.gOre = sk.ore ~= nil; db.gSkin = sk.skin ~= nil; db.gFish = sk.fish ~= nil
      if not (db.gHerb or db.gOre or db.gSkin or db.gFish) then db.gHerb = true end
    end
    return
  end
  local ok, err = pcall(onLoot)
  if not ok then ns.Debug("gathering loot error: %s", tostring(err)) end
end)

