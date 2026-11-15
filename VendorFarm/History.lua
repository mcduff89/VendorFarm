-- VendorFarm session history: every farm session is saved, and the History tab
-- ranks the spots you have actually farmed by the gold/hr you really made.
local ADDON, ns = ...

local MIN_KILLS, MIN_SEC = 10, 300   -- shorter sessions are too noisy to keep
local MAX_SESSIONS = 300

local function topKey(t)
  local best, bn = nil, 0
  for k, n in pairs(t or {}) do if n > bn then best, bn = k, n end end
  return best, bn
end

-- Save the current session (if it is long enough). Called on reset, and when a
-- new kill comes after a long gap.
function ns.ArchiveSession()
  local db = VendorFarmDB
  local s = db.session
  if not s or (s.kills or 0) < MIN_KILLS or (s.active or 0) < MIN_SEC then return false end
  local mob = topKey(s.mobs)
  local zone = topKey(s.zones) or "?"
  local others = {}
  for id, n in pairs(s.mobs) do if id ~= mob then others[#others + 1] = { id, n } end end
  table.sort(others, function(a, b) return a[2] > b[2] end)
  for i = #others, 4, -1 do others[i] = nil end
  db.history = db.history or {}
  table.insert(db.history, {
    t = s.start or time(), dur = s.active, kills = s.kills, gold = s.gold, exp = s.expected,
    zone = zone, mob = mob, mobN = s.mobs[mob], lvl = s.lvl, others = others,
  })
  while #db.history > MAX_SESSIONS do table.remove(db.history, 1) end
  ns.Debug("session saved: %s in %s, %d kills, %ds", tostring(mob), zone, s.kills, s.active)
  return true
end

-- One row per spot (main mob + zone), best real gold/hr first.
function ns.HistoryRank(level)
  local spots, list = {}, {}
  local idx = ns.IndexMobs()
  for _, h in ipairs(VendorFarmDB.history or {}) do
    local key = tostring(h.mob) .. "|" .. h.zone
    local sp = spots[key]
    if not sp then
      sp = { history = true, key = key, mobID = h.mob, mob = idx[h.mob], zone = h.zone,
        n = 0, dur = 0, gold = 0, exp = 0, kills = 0, sessions = {} }
      spots[key] = sp; list[#list + 1] = sp
    end
    sp.n = sp.n + 1; sp.dur = sp.dur + h.dur; sp.gold = sp.gold + h.gold
    sp.exp = sp.exp + (h.exp or 0); sp.kills = sp.kills + h.kills
    sp.lvl = h.lvl or sp.lvl; sp.last = h.t
    sp.sessions[#sp.sessions + 1] = h
  end
  for _, sp in ipairs(list) do
    local hrs = sp.dur / 3600
    sp.perHour = hrs > 0 and sp.gold / hrs or 0
    sp.modelHour = hrs > 0 and sp.exp / hrs or 0
    sp.luck = sp.exp > 0 and sp.gold / sp.exp or nil
    sp.name = sp.mob and sp.mob.name or ns.ObservedName and ns.ObservedName(sp.mobID) or ("Mob " .. tostring(sp.mobID))
  end
  table.sort(list, function(a, b) return a.perHour > b.perHour end)
  return list
end

function ns.HistoryTooltip(owner, sp)
  local money = ns.Money
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(sp.name .. " in " .. sp.zone, 1, 1, 1)
  GameTooltip:AddDoubleLine("Sessions", ("%d, %s farming, %d kills"):format(sp.n, ns.Clock(sp.dur), sp.kills), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("You made", money(sp.perHour) .. "/hr", 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("Model said", money(sp.modelHour) .. "/hr", 0.8, 0.8, 0.8, 1, 1, 1)
  if sp.mob then
    local r = { mob = sp.mob }
    local now = ns.ValuePerKill(sp.mob) * ns.KillsPerHour(sp.mob)
    GameTooltip:AddDoubleLine("Model today", money(now) .. "/hr", 0.8, 0.8, 0.8, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Recent sessions", 1, 0.82, 0)
  for i = #sp.sessions, math.max(1, #sp.sessions - 5), -1 do
    local h = sp.sessions[i]
    local hrs = h.dur / 3600
    GameTooltip:AddDoubleLine(("%s  lvl %s  %s, %d kills"):format(date("%b %d %H:%M", h.t), tostring(h.lvl or "?"), ns.Clock(h.dur), h.kills),
      money(hrs > 0 and h.gold / hrs or 0) .. "/hr", 0.8, 0.8, 0.8, 1, 1, 1)
    if h.others and #h.others > 0 then
      local parts = {}
      for _, o in ipairs(h.others) do
        local m = ns.IndexMobs()[o[1]]
        parts[#parts + 1] = ("%s x%d"):format(m and m.name or tostring(o[1]), o[2])
      end
      GameTooltip:AddLine("   also " .. table.concat(parts, ", "), 0.6, 0.6, 0.6, true)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("A session ends when you reset the tracker or go 15 minutes without a kill. Under 10 kills or 5 minutes isn't saved.", 0.6, 0.6, 0.6, true)
  if sp.mob then
    GameTooltip:AddLine(ns.HasWaypoint(sp.mob.id) and "Left-click: remove the waypoint." or "Left-click: TomTom waypoint to the main camp.", 0.5, 1, 0.5)
    GameTooltip:AddLine("Right-click: add or remove as a farm target.", 0.5, 1, 0.5)
  end
  GameTooltip:Show()
end
