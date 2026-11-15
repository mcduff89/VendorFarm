-- VendorFarm spawn dots: every spawn point of your selected mobs (farm targets and the
-- waypoint mob) on the world map and minimap, and a preview of a row's spawns when you
-- hover it with the world map open. Drawn with HereBeDragons-Pins (ships with TomTom and Questie).
local ADDON, ns = ...

local REF, HOVER = "VendorFarmSpawns", "VendorFarmHover"
local MAX_PINS = 400
local pool, used = {}, {}            -- frames, and which are in use per ref
local warned

local function pinsLib()
  return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local function mobName(id)
  local m = ns.IndexMobs()[id]
  return m and m.name or ("Mob " .. id)
end

local function getPin(size, r, g, b, glow)
  local p = table.remove(pool)
  if not p then
    p = CreateFrame("Frame", nil, UIParent)
    p.border = p:CreateTexture(nil, "BACKGROUND")
    p.border:SetAllPoints(); p.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); p.border:SetVertexColor(0, 0, 0, 1)
    p.dot = p:CreateTexture(nil, "ARTWORK")
    p.dot:SetPoint("TOPLEFT", 1.5, -1.5); p.dot:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    p.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
    p.glow:SetPoint("CENTER"); p.glow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:AddLine(s.name or "", 1, 1, 1)
      GameTooltip:AddLine("VendorFarm spawn point", 0.6, 0.6, 0.6); GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
  end
  p:SetSize(size, size)
  p.dot:SetVertexColor(r, g, b, 1)
  p.glow:SetShown(glow and true or false)
  if glow then p.glow:SetSize(size * 2.6, size * 2.6); p.glow:SetVertexColor(r, g, b, 0.3) end
  p:EnableMouse(true)
  return p
end

local function clearRef(ref, lib)
  lib = lib or pinsLib()
  if lib then
    pcall(lib.RemoveAllWorldMapIcons, lib, ref)
    pcall(lib.RemoveAllMinimapIcons, lib, ref)
  end
  for _, p in ipairs(used[ref] or {}) do p:Hide(); p:ClearAllPoints(); pool[#pool + 1] = p end
  used[ref] = {}
end

-- every spawn of one mob as { uiMap, x 0-1, y 0-1 }
local function spawnsOf(id)
  local out = {}
  if not (NpcDB and NpcDB.spawns) then return out end
  local ok, sp = pcall(NpcDB.spawns, id)
  if not ok or type(sp) ~= "table" then return out end
  for area, list in pairs(sp) do
    local uiMap = type(list) == "table" and ns.UiMapForArea(area)
    if uiMap then
      for _, c in ipairs(list) do
        if c[1] and c[1] >= 0 then out[#out + 1] = { uiMap, c[1] / 100, c[2] / 100 } end
      end
    end
  end
  return out
end

local function place(ref, ids, opts)
  local lib = pinsLib()
  clearRef(ref, lib)
  if not lib then
    if not warned then warned = true; print("|cffffd100VendorFarm|r: spawn dots need TomTom or Questie (HereBeDragons) loaded.") end
    return
  end
  local n = 0
  for _, id in ipairs(ids) do
    local name = mobName(id)
    for _, s in ipairs(spawnsOf(id)) do
      if n >= MAX_PINS then break end
      if opts.world then
        local p = getPin(opts.size, 1, 0.82, 0, opts.glow); p.name = name
        local ok = pcall(lib.AddWorldMapIconMap, lib, ref, p, s[1], s[2], s[3], 3)  -- 3 = show on zone and continent maps
        if ok then used[ref][#used[ref] + 1] = p; n = n + 1 else pool[#pool + 1] = p end
      end
      if opts.minimap then
        local p = getPin(8, 1, 0.82, 0); p.name = name
        local ok = pcall(lib.AddMinimapIconMap, lib, ref, p, s[1], s[2], s[3], false, false)
        if ok then used[ref][#used[ref] + 1] = p; n = n + 1 else pool[#pool + 1] = p end
      end
    end
  end
  ns.Debug("%s: %d spawn dots for %d mobs", ref, n, #ids)
end

-- Selected mobs: your farm targets plus the mob with the waypoint arrow.
function ns.UpdateSpawnPins()
  local db = VendorFarmDB
  if not db.spawnPins then clearRef(REF); return end
  local ids, seen = {}, {}
  for id in pairs(db.targets or {}) do ids[#ids + 1] = id; seen[id] = true end
  local wp = ns.WaypointMob and ns.WaypointMob()
  if wp and not seen[wp] then ids[#ids + 1] = wp end
  place(REF, ids, { world = true, minimap = true, size = 9 })
end

-- Row hover preview (only while the world map is open).
function ns.PreviewSpawns(id)
  if not id or not VendorFarmDB.spawnPins then return end
  if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
  place(HOVER, { id }, { world = true, size = 11, glow = true })
end

function ns.ClearPreview()
  if used[HOVER] and #used[HOVER] > 0 then clearRef(HOVER) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  -- wait a moment so QuestieDB and TomTom have finished loading
  C_Timer.After(3, function() pcall(ns.UpdateSpawnPins) end)
  if hooksecurefunc then
    hooksecurefunc(ns, "ToggleTarget", function() pcall(ns.UpdateSpawnPins) end)
    hooksecurefunc(ns, "Waypoint", function() pcall(ns.UpdateSpawnPins) end)
  end
end)
