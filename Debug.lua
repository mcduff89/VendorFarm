-- VendorFarm environment check (/vfarm check, and on /vfarm debug): what this client offers.
local ADDON, ns = ...

function ns.DebugCheck()
  local function yes(v) return v and "|cff66ff66yes|r" or "|cffff6666no|r" end
  local p = function(label, v, extra) print(("|cffffd100VendorFarm|r check: %s %s%s"):format(label, yes(v), extra and (" " .. extra) or "")) end
  local _, _, _, toc = GetBuildInfo()
  print(("|cffffd100VendorFarm|r check: client interface %s, VendorFarm %s"):format(tostring(toc), ns.VERSION))
  p("QuestieDB NpcDB (zones, spawns, friendly filter):", NpcDB and NpcDB.zoneID and NpcDB.spawns)
  p("QuestieDB zone maps (waypoints):", ns.UiMapForArea and ns.UiMapForArea(1) ~= nil, "Dun Morogh -> " .. tostring(ns.UiMapForArea and ns.UiMapForArea(1)))
  p("TomTom:", TomTom and TomTom.AddWaypoint)
  p("Auctionator API:", Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID)
  p("Combat log readable:", CombatLogGetCurrentEventInfo ~= nil, "(empty corpses only count if PARTY_KILL lines show in debug)")
  p("Secret-value checks available:", issecretvalue ~= nil)
  p("Addon messages:", C_ChatInfo and C_ChatInfo.SendAddonMessage)
  if ns.SyncStatus then
    local players, mobs, kills, onChannel = ns.SyncStatus()
    p("Hidden VendorFarmSync channel joined:", onChannel, ("| community: %d players, %d mobs, %d kills"):format(players, mobs, kills))
  end
  local db = VendorFarmDB
  local mobs, kills = 0, 0
  for _, o in pairs(db.obs or {}) do if o.k and o.k > 0 then mobs = mobs + 1; kills = kills + o.k end end
  print(("|cffffd100VendorFarm|r check: your data %d mobs, %d kills; pace %ds (%d samples), elites x%.1f"):format(
    mobs, kills, db.killSec, db.killSamples or 0, db.eliteMult))
end
