-- VendorFarm Dungeons: ranks 5-man dungeons by gold per run and gold/hr, and learns your runs.
-- Saved: VendorFarmDB.runs[instanceMapID] = { name=, n=runs, sec=total seconds, gold=total copper }
--        VendorFarmDB.curRun = { map=, name=, t=GetTime() at entry, gold=copper looted so far }
local ADDON, ns = ...

local CAP = 5          -- new instances per hour (players report 5/hr on Forever; unpublished)
local RESET = 60       -- seconds added per run for reset, run-out and zone-in
-- Starting run-time guesses in minutes: typical full clear for a group at level (Classic
-- experience, not Forever-measured). Replaced by your own average after one run.
local TYPICAL = {
  [389] = 20, [36] = 40, [43] = 45, [33] = 40, [48] = 45, [34] = 25, [90] = 60, [47] = 50,
  [189] = 120, [129] = 50, [70] = 60, [209] = 60, [349] = 90, [109] = 75, [230] = 150,
  [229] = 120, [429] = 150, [329] = 120, [289] = 75,
}

function ns.DungeonRank(level)
  local db = VendorFarmDB
  level = level or UnitLevel("player")
  local by = {}
  for _, m in ipairs(ns.Parse()) do
    local name = ns.INSTANCES[m.map]
    if name then
      local d = by[m.map]
      if not d then d = { map = m.map, name = name, value = 0, mobs = 0, elites = 0, parts = {} }; by[m.map] = d end
      local v = ns.ValuePerKill(m) * m.spawns
      d.value = d.value + v
      d.mobs = d.mobs + m.spawns
      local elite = m.rank == 1 or m.rank == 2 or m.rank == 3
      if elite then d.elites = d.elites + m.spawns end
      d.parts[#d.parts + 1] = { mob = m, v = v }
      if m.rank ~= 3 then
        d.minL = math.min(d.minL or m.minL, m.minL); d.maxL = math.max(d.maxL or m.maxL, m.maxL)
      end
    end
  end
  -- dungeons only you have run (new Forever instances) still show with your numbers
  for map, r in pairs(db.runs or {}) do
    if not by[map] and r.n and r.n > 0 then
      by[map] = { map = map, name = r.name or ("Instance " .. map), value = 0, mobs = 0, elites = 0, parts = {}, observedOnly = true }
    end
  end
  local out = {}
  local maxLevel = level + (db.above or 0)
  for _, d in pairs(by) do
   -- only dungeons you can handle: lowest mob level at or below your level + the "+N" setting
   if db.allDungeons or not d.minL or d.minL <= maxLevel then
    local r = db.runs and db.runs[d.map]
    local n = r and r.n or 0
    -- run time: your average once you have a run, else the typical clear time
    d.estSec = (TYPICAL[d.map] or 60) * 60
    d.runSec = n > 0 and (r.sec / n) or d.estSec
    d.timeSource = n > 0 and "yours" or "estimate"
    -- gold per run: model blended toward your average, fully yours after 5 runs
    local w = d.observedOnly and 1 or math.min(1, n / 5)
    d.perRun = (1 - w) * d.value + (n > 0 and w * r.gold / n or 0)
    d.runsHr = math.min(CAP, 3600 / math.max(60, d.runSec + RESET))
    d.capped = 3600 / math.max(60, d.runSec + RESET) >= CAP
    d.perHour = d.perRun * d.runsHr
    d.yourRuns = n
    table.sort(d.parts, function(a, b) return a.v > b.v end)
    out[#out + 1] = d
   end
  end
  table.sort(out, function(a, b) return a.perHour > b.perHour end)
  return out, CAP
end

-- Run tracking ---------------------------------------------------------------
local function instanceNow()
  if not GetInstanceInfo then return end
  local name, itype, _, _, _, _, _, mapID = GetInstanceInfo()
  if itype == "party" and mapID then return mapID, name end
end

local function finishRun()
  local db = VendorFarmDB
  local cur = db.curRun
  db.curRun = nil
  if not cur then return end
  local dur = GetTime() - cur.t
  if dur < 180 or dur > 3 * 3600 then return end  -- too short to be a run, or stale from another session
  db.runs = db.runs or {}
  local r = db.runs[cur.map] or { n = 0, sec = 0, gold = 0 }
  r.name = cur.name or r.name
  r.n, r.sec, r.gold = r.n + 1, r.sec + dur, r.gold + cur.gold
  db.runs[cur.map] = r
  print(("|cffffd100VendorFarm|r: %s run logged, %d:%02d and %s looted."):format(r.name or "Dungeon",
    math.floor(dur / 60), math.floor(dur) % 60, ns.Money(cur.gold)))
end

local function checkInstance()
  local db = VendorFarmDB
  if not db then return end
  local map, name = instanceNow()
  local cur = db.curRun
  if cur and (not map or map ~= cur.map) then finishRun(); cur = nil end
  if map and not cur then
    db.curRun = { map = map, name = name, t = GetTime(), gold = 0 }
  elseif cur and GetTime() - cur.t > 3 * 3600 then
    db.curRun = { map = map, name = name, t = GetTime(), gold = 0 }  -- left over from an old session
  end
end

function ns.OnRunLoot(copper)
  local cur = VendorFarmDB and VendorFarmDB.curRun
  if cur then cur.gold = cur.gold + copper end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:SetScript("OnEvent", function() C_Timer.After(1, checkInstance) end)
