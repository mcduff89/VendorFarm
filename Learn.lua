-- VendorFarm Learn: records your own kills and loot so drop rates can come from your play.
-- Saved in VendorFarmDB.obs[npcID] = { n=name, lo=, hi=, z=zone, k=kills, c=copper, i={[item]=qty},
--   sk=corpses skinned/gathered, s={[item]=qty} }
local ADDON, ns = ...

local secret = _G.issecretvalue or function() return false end
local function ok(v) return v ~= nil and not secret(v) end

local function npcFromGUID(guid)
  if not ok(guid) or type(guid) ~= "string" then return end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" then return tonumber(id) end
end

local function obsFor(id)
  local db = VendorFarmDB
  if not db.learn then return { k = 0, c = 0, i = {}, sk = 0, s = {} } end  -- tracker still works, nothing saved
  db.obs = db.obs or {}
  local o = db.obs[id]
  if not o then o = { k = 0, c = 0, i = {}, sk = 0, s = {} }; db.obs[id] = o end
  return o
end
ns.ObsFor = function(id) return VendorFarmDB.obs and VendorFarmDB.obs[id] end

-- Remember what a mob is called, its level and zone (covers Forever-only mobs).
local function noteUnit(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) then return end
  local okCall, canAttack = pcall(UnitCanAttack, "player", unit)
  if not okCall or not ok(canAttack) or not canAttack then return end
  local id = npcFromGUID(UnitGUID(unit)); if not id then return end
  local name, level = UnitName(unit), UnitLevel(unit)
  if not ok(name) or not ok(level) or level <= 0 then return end
  local o = obsFor(id)
  o.n = name
  o.lo = math.min(o.lo or level, level); o.hi = math.max(o.hi or level, level)
  local z = GetZoneText and GetZoneText()
  if z and z ~= "" then o.z = z end
  local c = UnitClassification and UnitClassification(unit)
  if ok(c) then o.r = (c == "elite" and 1) or (c == "rareelite" and 2) or (c == "rare" and 4) or (c == "worldboss" and 3) or 0 end
end

-- Your totals for a mob changed: rebuild its blend and queue it for sharing.
local function changed(id)
  if ns.InvalidateCombined then ns.InvalidateCombined(id) end
  if ns.SyncMarkOwn and VendorFarmDB.learn then ns.SyncMarkOwn(id) end
end

-- Session state (not saved): which corpses were counted and what came off them.
local killed, looted, firstItems, window = {}, {}, {}, {}

local function countKill(guid, id)
  if killed[guid] then return end
  killed[guid] = true
  local o = obsFor(id); o.k = o.k + 1
  changed(id)
  ns.Debug("kill counted: mob %d (%s), now %d kills", id, tostring(o.n or "?"), o.k)
  if ns.OnKill then ns.OnKill(id) end
end

local function moneyFromText(text)
  if not ok(text) or type(text) ~= "string" then return 0 end
  local function amt(word) return tonumber(text:match("(%d+)%s*" .. (word or "@@"))) or 0 end
  return amt(GOLD) * 10000 + amt(SILVER) * 100 + amt(COPPER)
end

local function itemIDFromLink(link)
  if not ok(link) or type(link) ~= "string" then return end
  return tonumber(link:match("item:(%d+)"))
end

local function onLoot()
  local n = GetNumLootItems and GetNumLootItems() or 0
  for slot = 1, n do
    local src = { GetLootSourceInfo(slot) }
    local slotType = GetLootSlotType(slot)
    local isMoney = slotType == (Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2)
    local itemID = not isMoney and itemIDFromLink(GetLootSlotLink(slot))
    local _, slotName, slotQty = GetLootSlotInfo(slot)
    if VendorFarmDB.debug then
      local parts = {}
      for j = 1, #src, 2 do parts[#parts + 1] = tostring(npcFromGUID(src[j]) or src[j]) .. " x" .. tostring(src[j + 1]) end
      ns.Debug("loot slot %d: %s %s | text %q qty %s | sources: %s", slot, isMoney and "MONEY" or "item",
        tostring(itemID or ""), tostring(slotName), tostring(slotQty), table.concat(parts, ", "))
    end
    for j = 1, #src, 2 do
      local guid, qty = src[j], src[j + 1]
      local id = npcFromGUID(guid)
      if id and not (window[guid] and window[guid][slot]) then
        window[guid] = window[guid] or {}; window[guid][slot] = true
        local o = obsFor(id)
        local second = looted[guid]          -- corpse already looted once: skinning/gathering
        changed(id)
        if not second then countKill(guid, id) end
        if isMoney then
          if not second then
            local cp = (ok(qty) and qty or 0)
            if cp <= 1 and #src == 2 then cp = moneyFromText(slotName) end
            ns.Debug("  coin counted: %d copper for mob %d", cp, id)
            o.c = o.c + cp
            if ns.OnLoot then ns.OnLoot(cp, "coin") end
          end
        elseif itemID then
          qty = ok(qty) and qty or (ok(slotQty) and slotQty or 1)
          if not second then
            o.i[itemID] = (o.i[itemID] or 0) + qty
            if ns.OnLoot then ns.OnLoot(qty * (ns.ItemValue(itemID)), itemID, qty) end
            firstItems[guid] = firstItems[guid] or {}; firstItems[guid][itemID] = true
          elseif not (firstItems[guid] and firstItems[guid][itemID]) then
            -- left-over first loot (full bags) is skipped; anything new is skin/gather loot
            if not window[guid].skin then window[guid].skin = true; o.sk = o.sk + 1 end
            o.s[itemID] = (o.s[itemID] or 0) + qty
            if ns.OnLoot and VendorFarmDB.skinning then ns.OnLoot(qty * (ns.ItemValue(itemID)), itemID, qty) end
          end
        end
      end
    end
  end
end

local function onLootClosed()
  for guid in pairs(window) do looted[guid] = true end
  wipe(window)
end

-- Kills without loot (empty corpses) still count, when the combat log is readable on Forever.
local function onCombatLog()
  if not CombatLogGetCurrentEventInfo then return end
  local okCall, _, sub, _, srcGUID, _, _, _, destGUID = pcall(CombatLogGetCurrentEventInfo)
  if not okCall or sub ~= "PARTY_KILL" then return end
  local id = npcFromGUID(destGUID)
  ns.Debug("combat log PARTY_KILL seen for mob %s", tostring(id))
  if id then countKill(destGUID, id) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("LOOT_READY")
f:RegisterEvent("LOOT_CLOSED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(_, event)
  if not VendorFarmDB then return end
  if event == "LOOT_READY" then onLoot()
  elseif event == "LOOT_CLOSED" then onLootClosed()
  elseif event == "PLAYER_TARGET_CHANGED" then noteUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then noteUnit("mouseover")
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then onCombatLog()
  end
end)

-- Blend: your rates take over as kills grow (full weight at learnFull kills).
function ns.Weight(o)
  if not (VendorFarmDB.learn and o and o.k and o.k > 0) then return 0 end
  return math.min(1, o.k / math.max(1, VendorFarmDB.learnFull))
end

function ns.Effective(m)
  local o = ns.CombinedObs and ns.CombinedObs(m.id) or ns.ObsFor(m.id)
  local w = ns.Weight(o)
  if m.observedOnly and w > 0 then w = 1 end   -- nothing in the database to blend with
  if w == 0 then return m.coin, m.items, m.rest, m.skin, 0, o end
  local e = {}
  for _, it in ipairs(m.items) do e[it[1]] = (1 - w) * it[2] end
  for id, q in pairs(o.i) do e[id] = (e[id] or 0) + w * q / o.k end
  local items = {}
  for id, v in pairs(e) do if v > 0 then items[#items + 1] = { id, v } end end
  local skin = m.skin
  if o.sk and o.sk > 0 then
    local ws = m.observedOnly and 1 or math.min(1, o.sk / math.max(1, VendorFarmDB.learnFull))
    local se = {}
    for _, it in ipairs(m.skin) do se[it[1]] = (1 - ws) * it[2] end
    for id, q in pairs(o.s) do se[id] = (se[id] or 0) + ws * q / o.sk end
    skin = {}
    for id, v in pairs(se) do if v > 0 then skin[#skin + 1] = { id, v } end end
  end
  return (1 - w) * m.coin + w * o.c / o.k, items, (1 - w) * m.rest, skin, w, o
end

-- Mobs you have fought that the database doesn't know (new Forever mobs).
function ns.ObservedOnly(known)
  local out = {}
  for id, o in pairs(VendorFarmDB.obs or {}) do
    if not known[id] and o.n and o.lo and o.k and o.k > 0 then
      out[#out + 1] = { id = id, name = o.n, minL = o.lo, maxL = o.hi, rank = o.r or 0, coin = 0,
        spawns = 0, map = 0, items = {}, rest = 0, skin = {}, respawn = 0, zoneName = o.z, observedOnly = true }
    end
  end
  return out
end
