-- VendorFarm: TomTom waypoint to the nearest friendly vendor (left-click) or repair vendor (right-click).
-- Vendor list from CMaNGOS; spawn spots and faction from QuestieDB.
local ADDON, ns = ...

local cache      -- [npcID] = { {continent, wx, wy, uiMap, x, y}, ... }
local vendorWP   -- { uid, repair }

local function myFaction()
  return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

local function worldPos(uiMap, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x, y))
  if ok and cont and pos then return cont, pos.x, pos.y end
end

local function spots(id)
  cache = cache or {}
  if cache[id] then return cache[id] end
  local list = {}
  local ok, sp = pcall(NpcDB.spawns, id)
  if ok and type(sp) == "table" then
    for area, coords in pairs(sp) do
      local uiMap = type(coords) == "table" and ns.UiMapForArea(area)
      if uiMap then
        for _, c in ipairs(coords) do
          if c[1] and c[1] >= 0 then
            local cont, wx, wy = worldPos(uiMap, c[1] / 100, c[2] / 100)
            list[#list + 1] = { cont, wx, wy, uiMap, c[1], c[2] }
          end
        end
      end
    end
  end
  cache[id] = list
  return list
end

local function clear()
  if vendorWP and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, vendorWP.uid) end
  vendorWP = nil
end

function ns.HasVendorWaypoint() return vendorWP ~= nil end

function ns.NearestVendor(repair)
  if vendorWP and vendorWP.repair == (repair and true or false) then clear(); return end
  clear()
  if not (TomTom and TomTom.AddWaypoint and NpcDB and NpcDB.spawns and NpcDB.friendlyToFaction) then
    print("|cffffd100VendorFarm|r: the vendor button needs TomTom and QuestieDB."); return
  end
  local pMap = C_Map.GetBestMapForUnit("player")
  local pp = pMap and C_Map.GetPlayerMapPosition(pMap, "player")
  if not pp then print("|cffffd100VendorFarm|r: can't read your position here."); return end
  local px, py = pp:GetXY()
  local pCont, pwx, pwy = worldPos(pMap, px, py)
  local fac = myFaction()
  local best, bd, bs
  for id, v in pairs(ns.VENDORS) do
    if not repair or v[3] == 1 then
      local ok, f = pcall(NpcDB.friendlyToFaction, id)
      if ok and f and f:find(fac, 1, true) then
        for _, s in ipairs(spots(id)) do
          local d
          if pCont and s[1] == pCont and s[2] then
            d = (s[2] - pwx) ^ 2 + (s[3] - pwy) ^ 2            -- yards, works across zones
          elseif s[4] == pMap then
            d = ((s[5] / 100 - px) * 4000) ^ 2 + ((s[6] / 100 - py) * 4000) ^ 2 -- same map, rough
          end
          if d and (not bd or d < bd) then best, bd, bs = id, d, s end
        end
      end
    end
  end
  if not best then
    print(("|cffffd100VendorFarm|r: no friendly %s found on this continent."):format(repair and "repair vendor" or "vendor")); return
  end
  local v = ns.VENDORS[best]
  local title = v[1] .. (v[2] ~= "" and (" <" .. v[2] .. ">") or "")
  local uid = TomTom:AddWaypoint(bs[4], bs[5] / 100, bs[6] / 100, { title = title, from = "VendorFarm" })
  vendorWP = { uid = uid, repair = repair and true or false }
  local yards = pCont and bs[1] == pCont and math.sqrt(bd)
  print(("|cffffd100VendorFarm|r: waypoint to %s%s. Click again to remove it."):format(title, yards and (" (%d yards)"):format(yards) or ""))
  ns.Debug("vendor %d at uiMap %s %.1f, %.1f", best, tostring(bs[4]), bs[5], bs[6])
end

function ns.VendorButton(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_10")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, btn) ns.NearestVendor(btn == "RightButton") end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:AddLine("Nearest vendor")
    GameTooltip:AddLine("Left-click: waypoint to the nearest vendor.", 0.5, 1, 0.5)
    GameTooltip:AddLine("Right-click: nearest vendor that repairs.", 0.5, 1, 0.5)
    GameTooltip:AddLine("Click again to remove it.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end
