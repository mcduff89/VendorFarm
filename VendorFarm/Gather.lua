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
  local out, names = {}, {}
  if not (GetProfessions and GetProfessionInfo) then return out, names end
  local list = { GetProfessions() }
  for i = 1, 6 do
    local idx = list[i]
    if idx then
      local ok, name, _, level, _, _, _, line = pcall(GetProfessionInfo, idx)
      if ok and line then
        for k, id in pairs(SKILL) do if id == line then out[k] = level; names[k] = name end end
      end
    end
  end
  return out, names
end

-- Skill-ups -----------------------------------------------------------------
-- Gathering colours: orange until required skill +25, yellow until +50, green until +100, then grey.
-- Starting chances of a point per gather are the usual Classic ones; your own gathers take over.
local COLOR_P = { orange = 1, yellow = 0.75, green = 0.25, grey = 0 }
local COLOR_HEX = { orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "9d9d9d" }
local SKILL_FULL = 30
ns.SkillHex = COLOR_HEX

function ns.SkillColor(skill, req)
  if not skill or not req or skill < req then return nil end
  local d = skill - req
  return d < 25 and "orange" or (d < 50 and "yellow" or (d < 100 and "green" or "grey"))
end

-- Skinning needs: mob level 1-10 -> 1, 11-20 -> (level - 10) x 10, 21+ -> level x 5.
function ns.SkinReq(lvl)
  if lvl <= 10 then return 1 end
  if lvl <= 20 then return (lvl - 10) * 10 end
  return lvl * 5
end

local function fishDefault(skill)
  skill = skill or 1
  if skill < 75 then return 1 end
  return math.max(0.1, 1 - (skill - 75) / 250)
end

-- chance of a point: key is a colour, or "fish" (needs your fishing skill)
function ns.SkillChance(key, skill)
  if not key then return 0 end
  local est = key == "fish" and fishDefault(skill) or COLOR_P[key] or 0
  if key == "grey" then return 0 end
  local l = VendorFarmDB.skillRolls and VendorFarmDB.skillRolls[key]
  if not l or (l.n or 0) == 0 then return est, 0 end
  local w = math.min(1, l.n / SKILL_FULL)
  return (1 - w) * est + w * l.e, w
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

-- Your data per zone: db.gather[uiMap] = { n nodes, c coin, i={[item]=qty}, gap pace, gn pace samples,
--   fn catches, fc coin, f={[item]=qty} }. Item counts (not copper) so everyone's prices apply.
local function gstat(z)
  local db = VendorFarmDB
  db.gather = db.gather or {}
  local st = db.gather[z]
  if not st or not st.i then   -- (2.0.0 kept only copper totals; start those zones fresh)
    st = { n = 0, c = 0, i = {}, gn = 0, fn = 0, fc = 0, f = {}, gap = st and st.gap }
    db.gather[z] = st
  end
  return st
end
ns.GatherStat = gstat

local function itemsValue(t, n, coin)
  if not n or n <= 0 then return nil end
  local v = coin or 0
  for id, q in pairs(t) do v = v + q * (ns.ItemValue(id)) end
  return v / n
end

-- Ranking -------------------------------------------------------------------
-- Rows: { name, tag, lvl, rateText, per, perHour, kind, zone, parts }
function ns.GatherRank(level)
  local db = VendorFarmDB
  level = level or UnitLevel("player")
  local skills = ns.ProfSkills()
  local out = {}
  if mapState == "idle" then startMapping() end
  local pick = db.zone
  local here = pick == "@here" and zoneMap()
  local pickName = pick and pick ~= "@here" and pick
  local maxSkill = math.min(300, level * 5)
  local skillMode = db.gSkillUp
  local hSkill = skills.herb or (skillMode and 1 or maxSkill)
  local oSkill = skills.ore or (skillMode and 1 or maxSkill)
  local mounted = level >= 40

  local function levels(z)
    if not (C_Map and C_Map.GetMapLevels) then return end
    local ok, lo, hi = pcall(C_Map.GetMapLevels, z)
    if ok and lo and lo > 0 then return lo, hi end
  end
  local function okZone(z)
    if here then return z == here end
    if pickName then return zoneName(z) == pickName end
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
        local up, value, parts, pts, all = 0, 0, {}, 0, {}
        for id, w in pairs(list) do
          local nd = nodes[id]
          if nd and ((nd.kind == 1 and db.gHerb) or (nd.kind == 2 and db.gOre)) then
            all[#all + 1] = { skill = nd.skill, kind = nd.kind, w = w }
          end
          if nd and ((nd.kind == 1 and db.gHerb and nd.skill <= hSkill) or (nd.kind == 2 and db.gOre and nd.skill <= oSkill)) then
            local v = lootValue(nd.items)
            local col = ns.SkillColor(nd.kind == 1 and hSkill or oSkill, nd.skill)
            local p = ns.SkillChance(col)
            up = up + w; value = value + w * v; pts = pts + w * p
            parts[#parts + 1] = { id = id, name = nd.name, skill = nd.skill, kind = nd.kind, w = w, v = v, col = col, p = p }
          end
        end
        if up >= 1 and not (skillMode and pts <= 0) then
          local st = ns.CombinedGather(z)
          local perEst = value / up
          local per, vw = blend(perEst, itemsValue(st.i, st.n, st.c), st.n, VALUE_FULL)
          local nphEst = 60 * up / (up + 40) * (mounted and 1 or 0.7)
          -- other players' pace improves the guess; your own pace takes over after 20 nodes here
          local nph = blend(nphEst, st.oGap and 3600 / st.oGap or nil, st.oGn, 40)
          local rw
          nph, rw = blend(nph, st.gap and 3600 / st.gap or nil, st.gn, NODE_FULL)
          rw = (st.oGn > 0 or rw > 0) and math.max(rw, 0.01) or rw
          local tag = (db.gHerb and db.gOre) and "Herbs + ore" or (db.gHerb and "Herbs" or "Ore")
          out[#out + 1] = { kind = "nodes", zone = z, name = zoneName(z), tag = tag, lvl = lvlText(z),
            rate = ("~%d up, %d/hr%s"):format(up + 0.5, nph + 0.5, rw >= 1 and "" or " est"),
            per = per, perHour = per * nph, up = up, nph = nph, nphEst = nphEst, rw = rw, vw = vw,
            perEst = perEst, parts = parts, st = st, all = all, hSkill = hSkill, oSkill = oSkill,
            pts = pts / up, ptsHour = pts / up * nph }
        end
      end
    end
  end

  -- fishing
  if db.gFish then
    local catches = blend(FISH_DEFAULT, db.fishGap and 3600 / db.fishGap or nil, db.fishN or 0, FISH_FULL)
    local fSkill = skills.fish or 1
    local fp = ns.SkillChance("fish", fSkill)
    for area in pairs(ns.FISH) do
      local z = ns.UiMapForArea and ns.UiMapForArea(area)
      if z and okZone(z) then
        local info = C_Map.GetMapInfo(z)
        if info and (info.mapType == 3 or info.mapType == 4) then
          local vEst, items = fishValue(area)
          local st = ns.CombinedGather(z)
          local per, vw = blend(vEst, itemsValue(st.f, st.fn, st.fc), st.fn, FISH_FULL)
          out[#out + 1] = { kind = "fish", zone = z, name = zoneName(z), tag = "Fishing", lvl = lvlText(z),
            rate = ("%d catches/hr%s"):format(catches + 0.5, (db.fishN or 0) >= FISH_FULL and "" or " est"),
            per = per, perHour = per * catches, items = items, vw = vw, st = st,
            pts = fp, ptsHour = fp * catches, fSkill = fSkill }
        end
      end
    end
  end

  -- skinning: best skinnable mob per zone in your level range (kills/hr x skinning loot only)
  if db.gSkin then
    -- a picked zone: Rank lists that zone's mobs at any level; otherwise your level range everywhere
    -- for skill-ups, look at mobs around the level your skinning skill is made for
    local rankLvl = level
    if skillMode and skills.skin then
      local s = skills.skin
      local lv = s >= 100 and math.floor(s / 5) or (s >= 10 and math.floor(s / 10) + 10 or 10)
      rankLvl = math.max(1, math.min(level, lv + 2))
    end
    local ok, list = pcall(ns.Rank, rankLvl)
    if ok then
      local best = {}
      local sSkill = skills.skin or (skillMode and 1 or nil)
      for _, r in ipairs(list) do
        local m = r.mob
        local _, _, _, skin = ns.Effective(m)
        local sv = lootValue(skin)
        local req = ns.SkinReq(m.maxL or m.minL or 1)
        local col = sSkill and ns.SkillColor(sSkill, req)
        local p = col and ns.SkillChance(col) or 0
        if sv > 0 and (not sSkill or req <= sSkill) and not (skillMode and p <= 0) then
          local zn, area = ns.ZoneName(m)
          local z = area and ns.UiMapForArea(area)
          if z and (pick or okZone(z)) then
            local hr = sv * r.kph
            local score = skillMode and p * r.kph or hr
            if not best[z] or score > best[z].score then
              best[z] = { kind = "skin", zone = z, name = zoneName(z), tag = "Skinning: " .. m.name, lvl = lvlText(z),
                rate = ("%d kills/hr"):format(r.kph + 0.5), per = sv, perHour = hr, mob = m,
                pts = p, ptsHour = p * r.kph, col = col, req = req, sSkill = sSkill, score = score }
            end
          end
        end
      end
      for _, r in pairs(best) do out[#out + 1] = r end
    end
  end

  if skillMode then
    table.sort(out, function(a, b)
      if math.abs((a.ptsHour or 0) - (b.ptsHour or 0)) > 0.5 then return (a.ptsHour or 0) > (b.ptsHour or 0) end
      return a.perHour > b.perHour
    end)
  else
    table.sort(out, function(a, b) return a.perHour > b.perHour end)
  end
  return out, mapState, progress
end

function ns.GatherTooltip(owner, r)
  local money = ns.Money
  local tt = GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  tt:AddLine(r.name .. "  |cffaaaaaa" .. r.tag .. "|r", 1, 1, 1)
  local function row(l, v) tt:AddDoubleLine(l, v, 0.8, 0.8, 0.8, 1, 1, 1) end
  local function note(t) tt:AddLine(t, 0.6, 0.6, 0.6, true) end
  local skillMode = VendorFarmDB.gSkillUp
  local function pct(p) return ("%d%%"):format((p or 0) * 100 + 0.5) end
  if skillMode then
    row("Skill-ups per hour", ("~%d"):format((r.ptsHour or 0) + 0.5))
    row(r.kind == "nodes" and "Chance per node" or (r.kind == "fish" and "Chance per catch" or "Chance per skin"), pct(r.pts))
  end
  if skillMode and r.kind == "nodes" then
    tt:AddLine(" ")
    table.sort(r.parts, function(a, b) return a.w * (a.p or 0) > b.w * (b.p or 0) end)
    for i = 1, math.min(#r.parts, 10) do
      local q = r.parts[i]
      local hex = COLOR_HEX[q.col or "grey"]
      tt:AddDoubleLine(("|cff%s%s|r |cff888888(%d)|r  ~%.1f up"):format(hex, q.name, q.skill, q.w),
        ("%s, grey at %d"):format(pct(q.p), q.skill + 100), 1, 1, 1, 1, 1, 1)
    end
    -- when this zone stops paying: average chance over the nodes you could gather at that skill
    local function avgP(d)
      local sw, sp = 0, 0
      for _, q in ipairs(r.all) do
        local s = (q.kind == 1 and r.hSkill or r.oSkill) + d
        if q.skill <= s then sw = sw + q.w; sp = sp + q.w * ns.SkillChance(ns.SkillColor(s, q.skill)) end
      end
      return sw > 0 and sp / sw or 0
    end
    local moveAt
    for d = 1, 300 do
      local s = math.max(r.hSkill, r.oSkill) + d
      if s > 300 then break end
      if avgP(d) < 0.35 then moveAt = s; break end
    end
    tt:AddLine(" ")
    if moveAt then note(("Move on at about skill %d: most nodes here are green or grey by then."):format(moveAt)) end
    note("Orange nodes always give a point, yellow usually, green sometimes, grey never. Chances start at the usual Classic values and switch to what your own gathering shows after 30 gathers of each colour.")
    tt:Show()
    return
  end
  if skillMode and r.kind == "skin" then
    row("Mob", ("%s (level %s)"):format(r.mob.name, r.mob.maxL or r.mob.minL or "?"))
    row("Kills per hour", r.rate)
    tt:AddDoubleLine("Needs skill", ("|cff%s%d|r, grey at %d"):format(COLOR_HEX[r.col or "grey"], r.req, r.req + 100), 0.8, 0.8, 0.8, 1, 1, 1)
    row("Skinning loot per kill", money(r.per))
    tt:AddLine(" ")
    note("Skinning skill needed: mob level x5 from level 21 (level 11-20: (level-10) x10). Pick mobs that are orange or yellow for you.")
    tt:Show()
    return
  end
  if skillMode and r.kind == "fish" then
    row("Fishing skill", r.fSkill)
    note("Fishing gives a point on most catches early on, and less often as your skill rises. The chance is learned from your own catches. Low-level water is fine for skill-ups; zone doesn't change the chance.")
    tt:AddLine(" ")
  end
  if r.kind == "nodes" then
    row("Nodes up at a time (you can gather)", ("~%d"):format(r.up + 0.5))
    row("Nodes per hour", ("%d%s"):format(r.nph + 0.5, r.rw >= 1 and " (yours)" or (r.st.gn > 0 and (" (%d%% yours)"):format(math.min(1, r.st.gn / NODE_FULL) * 100) or (r.st.oGn > 0 and " (from other players)" or " (estimate)"))))
    row("Value per node", money(r.per) .. (r.vw > 0 and (" (%d%% your loot)"):format(r.vw * 100) or ""))
    if r.st and r.st.ownN > 0 then row("You gathered here", ("%d nodes"):format(r.st.ownN)) end
    if r.st and r.st.players > 0 then row("Other players here", ("%d nodes from %d players"):format(r.st.n - r.st.ownN, r.st.players)) end
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
    if r.st and r.st.ownFN > 0 then row("You caught here", r.st.ownFN) end
    if r.st and r.st.fn > r.st.ownFN then row("Other players caught here", r.st.fn - r.st.ownFN) end
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

-- Skill-up chances: each gather or catch is a roll of its colour ("fish" for fishing); a
-- "Your skill in X has increased" message within 4 seconds either side counts as a hit.
local pending, lastSkillMsg
local function rollDone(p)
  local db = VendorFarmDB
  db.skillRolls = db.skillRolls or {}
  local l = db.skillRolls[p.key] or { n = 0, e = 0 }
  local hit = p.hit and 1 or 0
  l.e = l.n == 0 and hit or (l.e * (1 - ALPHA) + hit * ALPHA)
  l.n = l.n + 1
  db.skillRolls[p.key] = l
  ns.Debug("skill roll %s: %s (%d rolls, %.0f%%)", p.key, p.hit and "point" or "no point", l.n, l.e * 100)
end
local function roll(key, profName)
  if not key or key == "grey" or not profName then return end
  local p = { key = key, name = profName, t = GetTime() }
  if lastSkillMsg and not lastSkillMsg.used and GetTime() - lastSkillMsg.t < 4 and lastSkillMsg.msg:find(profName, 1, true) then
    p.hit = true; lastSkillMsg.used = true
  end
  pending = p
  C_Timer.After(4, function() if pending == p then pending = nil end; rollDone(p) end)
end
local function onSkillMsg(msg)
  if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
  if pending and not pending.hit and GetTime() - pending.t < 4 and msg:find(pending.name, 1, true) then
    pending.hit = true; return
  end
  lastSkillMsg = { t = GetTime(), msg = msg }
end

-- Adds one loot window into item counts + coin; returns its value at your prices (for debug).
local function recordSlots(n, items)
  local coin, v = 0, 0
  for slot = 1, n do
    local t = GetLootSlotType(slot)
    if t == (Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2) then
      local src = { GetLootSourceInfo(slot) }
      local q = src[2]
      if type(q) == "number" and not (issecretvalue and issecretvalue(q)) then coin = coin + q end
    else
      local link = GetLootSlotLink(slot)
      local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
      local _, _, qty = GetLootSlotInfo(slot)
      qty = (type(qty) == "number" and not (issecretvalue and issecretvalue(qty))) and qty or 1
      if id then items[id] = (items[id] or 0) + qty; v = v + qty * (ns.ItemValue(id)) end
    end
  end
  return coin, v + coin
end

local function onLoot()
  local db = VendorFarmDB
  local n = GetNumLootItems and GetNumLootItems() or 0
  if n == 0 then return end
  local now = GetTime()
  local z = zoneMap()
  if not z then return end
  if IsFishingLoot and IsFishingLoot() then
    local st = gstat(z)
    local coin, v = recordSlots(n, st.f)
    st.fn = st.fn + 1; st.fc = st.fc + coin
    if ns.SyncMarkGather then ns.SyncMarkGather(z) end
    if lastFish and now - lastFish < 120 then
      local gap = now - lastFish
      db.fishGap = db.fishGap and (db.fishGap * (1 - ALPHA) + gap * ALPHA) or gap
      db.fishN = (db.fishN or 0) + 1
    end
    lastFish = now
    local _, names = ns.ProfSkills()
    roll("fish", names.fish)
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
  local st = gstat(z)
  local coin, v = recordSlots(n, st.i)
  st.n = st.n + 1; st.c = st.c + coin
  if lastGather and now - lastGather < BREAK then
    local gap = now - lastGather
    st.gap = st.gap and (st.gap * (1 - ALPHA) + gap * ALPHA) or gap
    st.gn = st.gn + 1
  end
  lastGather = now
  local sk, names = ns.ProfSkills()
  local kind = nodes[entry].kind == 1 and "herb" or "ore"
  roll(ns.SkillColor(sk[kind], nodes[entry].skill), names[kind])
  if ns.SyncMarkGather then ns.SyncMarkGather(z) end
  ns.Debug("gathered %s in %s worth %d (%d here)", nodes[entry].name, zoneName(z), v, st.n)
end

local f = CreateFrame("Frame")
f:RegisterEvent("LOOT_READY")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_SKILL")
f:SetScript("OnEvent", function(_, ev, msg)
  if ev == "CHAT_MSG_SKILL" then pcall(onSkillMsg, msg); return end
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

