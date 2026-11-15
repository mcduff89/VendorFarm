-- VendorFarm UI: one small movable window with the ranked list.
local ADDON, ns = ...

local ROW_H, W = 18, 470
local frame, rows, fromBox, toText, plusDD, statusText
local overrideLevel

local function money(c)
  c = math.floor(c + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("%d|cffffd100g|r %02d|cffc7c7cfs|r"):format(g, s) end
  if s > 0 then return ("%d|cffc7c7cfs|r %02d|cffeda55fc|r"):format(s, cp) end
  return ("%d|cffeda55fc|r"):format(cp)
end
ns.Money = money

local RANK = { [1] = " |cffffd100(Elite)|r", [2] = " |cffffd100(Rare Elite)|r", [4] = " |cffc0c0ff(Rare)|r" }

local function showTooltip(row)
  local r = row.data; if not r then return end
  local m = r.mob
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(m.name .. (RANK[m.rank] or ""), 1, 1, 1)
  local lvl = m.minL == m.maxL and m.minL or (m.minL .. "-" .. m.maxL)
  GameTooltip:AddDoubleLine("Level " .. lvl, (ns.ZoneName(m)), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
  GameTooltip:AddDoubleLine("Kills/hr (model)", ("%d"):format(r.kph), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Spawns / respawn", ("%d / %ds"):format(m.spawns, m.respawn), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddLine(" ")
  local coin, items, rest, skin, w, o = ns.Effective(m)
  if o and o.k and o.k > 0 then
    GameTooltip:AddDoubleLine("Your data", ("%d kills, %d%% weight"):format(o.k, math.floor(w * 100 + 0.5)), 0.4, 1, 0.4, 0.4, 1, 0.4)
  end
  if m.observedOnly then GameTooltip:AddLine("Not in the database: from your kills only.", 0.4, 1, 0.4, true) end
  GameTooltip:AddDoubleLine("Coin per kill", money(coin), 1, 0.82, 0, 1, 1, 1)
  local parts = {}
  local function collect(list, tag)
    for _, it in ipairs(list) do
      local price, src, vendor, ah, age = ns.ItemValue(it[1])
      parts[#parts+1] = { id = it[1], e = it[2], price = price, src = src, tag = tag, v = it[2] * price,
        vendor = vendor, ah = ah, age = age }
    end
  end
  collect(items)
  if VendorFarmDB.skinning then collect(skin, "skin") end
  table.sort(parts, function(a, b) return a.v > b.v end)
  for i = 1, math.min(#parts, 10) do
    local p = parts[i]
    if p.v >= 0.5 then
      local q = ns.ItemQuality(p.id)
      local cr, cg, cb = 1, 1, 1
      if C_Item and C_Item.GetItemQualityColor then cr, cg, cb = C_Item.GetItemQualityColor(q)
      elseif GetItemQualityColor then cr, cg, cb = GetItemQualityColor(q) end
      local pct = p.e <= 1 and ("%.1f%%"):format(p.e * 100) or ("x%.1f"):format(p.e)
      -- right side: price per item and where it came from, then what it adds per kill
      local each
      if p.src == "ah" then
        each = ("%s |cff80c0ffAH%s|r"):format(money(p.ah), p.age and (" " .. p.age .. "d") or "")
      elseif p.src == "db" then
        each = money(p.price) .. " |cff888888db|r"
      else
        each = money(p.price) .. " |cff888888vendor|r"
      end
      GameTooltip:AddDoubleLine(("%s %s%s"):format(ns.ItemName(p.id), pct, p.tag and " |cff888888skin|r" or ""),
        ("%s  |cff888888=|r %s"):format(each, money(p.v)), cr, cg, cb, 1, 1, 1)
    end
  end
  if rest > 0.5 then GameTooltip:AddDoubleLine("Other small drops", money(rest), 0.6, 0.6, 0.6, 1, 1, 1) end
  GameTooltip:AddDoubleLine("Value per kill", money(r.perKill), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(w > 0 and "Drop rates: your kills blended with the CMaNGOS vanilla DB." or "Drop rates: CMaNGOS vanilla DB, not Forever-measured.", 0.6, 0.6, 0.6, true)
  GameTooltip:AddLine("Each line: price per item, then what it adds per kill (chance x price).", 0.6, 0.6, 0.6, true)
  if VendorFarmDB.useAH then
    GameTooltip:AddLine("|cff80c0ffAH|r = Auctionator's last scan (Nd = days old), used minus the 5% cut when it beats the vendor price.", 0.6, 0.6, 0.6, true)
  end
  GameTooltip:AddLine("|cff888888db|r = sell price not cached yet (Classic value).", 0.6, 0.6, 0.6, true)
  GameTooltip:AddLine(ns.HasWaypoint(m.id) and "Left-click: remove the waypoint." or "Left-click: TomTom waypoint to the main camp.", 0.5, 1, 0.5)
  GameTooltip:AddLine(r.target and "Right-click: remove from your farm targets." or "Right-click: add to your farm targets.", 0.5, 1, 0.5)
  GameTooltip:Show()
end

local function makeRow(i)
  local r = CreateFrame("Button", nil, frame)
  r:SetSize(W - 16, ROW_H)
  r:SetPoint("TOPLEFT", 8, -80 - (i - 1) * ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  local function fs(x, w, justify)
    local f = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f:SetPoint("LEFT", x, 0); f:SetWidth(w); f:SetJustifyH(justify or "LEFT"); f:SetWordWrap(false)
    return f
  end
  r.name = fs(2, 170); r.lvl = fs(172, 40, "CENTER"); r.zone = fs(214, 110)
  r.kill = fs(326, 60, "RIGHT"); r.hour = fs(390, 66, "RIGHT")
  r:SetScript("OnEnter", showTooltip)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, btn)
    if not self.data then return end
    if btn == "RightButton" then ns.ToggleTarget(self.data.mob.id) else ns.Waypoint(self.data.mob) end
  end)
  return r
end

local function build()
  frame = CreateFrame("Frame", "VendorFarmFrame", UIParent, "BackdropTemplate")
  frame:SetSize(W, 92 + VendorFarmDB.rows * ROW_H)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  frame:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
  frame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint(); VendorFarmDB.point = { p, rp, x, y }
  end)
  local pt = VendorFarmDB.point
  if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("CENTER") end
  tinsert(UISpecialFrames, "VendorFarmFrame")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8); title:SetText("VendorFarm")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2); close:SetScale(0.8)

  local gear = CreateFrame("Button", nil, frame)
  gear:SetSize(16, 16); gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
  gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetScript("OnClick", function() ns.OpenOptions() end)

  local compact = CreateFrame("Button", nil, frame)
  compact:SetSize(16, 16); compact:SetPoint("RIGHT", gear, "LEFT", -4, 0)
  compact:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
  compact:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  compact:SetScript("OnClick", function() frame:Hide(); ns.ShowTracker(true) end)
  compact:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText("Compact tracker"); GameTooltip:Show() end)
  compact:SetScript("OnLeave", GameTooltip_Hide)
  gear:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText("Options"); GameTooltip:Show() end)
  gear:SetScript("OnLeave", GameTooltip_Hide)

  -- Level range: From <box> to <your level> plus a +0..+5 dropdown.
  local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lbl:SetPoint("TOPLEFT", 110, -10); lbl:SetText("From")
  fromBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  fromBox:SetSize(28, 16); fromBox:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
  fromBox:SetAutoFocus(false); fromBox:SetNumeric(true); fromBox:SetMaxLetters(2)
  fromBox:SetScript("OnEnterPressed", function(s)
    local v, level = tonumber(s:GetText()), ns.CurrentLevel()
    if v then VendorFarmDB.below = math.max(0, math.min(level - 1, level - v)) end
    s:ClearFocus(); ns.Refresh()
  end)
  fromBox:SetScript("OnEscapePressed", function(s) s:ClearFocus(); ns.Refresh() end)
  fromBox:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText("Lowest mob level to scan. Press Enter.\nIt stays the same number of levels under you when you level up.", 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  fromBox:SetScript("OnLeave", GameTooltip_Hide)
  toText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  toText:SetPoint("LEFT", fromBox, "RIGHT", 6, 0)

  local function setAbove(v) VendorFarmDB.above = v; ns.Refresh() end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(64); dd:SetPoint("LEFT", toText, "RIGHT", 6, 0)
    dd:SetupMenu(function(_, root)
      for v = 0, 5 do
        root:CreateRadio("+" .. v, function() return VendorFarmDB.above == v end, function() setAbove(v) end)
      end
    end)
  else
    -- Fallback: a button that cycles +0..+5 (left click up, right click down, or mouse wheel).
    dd = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dd:SetSize(40, 18); dd:SetPoint("LEFT", toText, "RIGHT", 6, 0)
    dd:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    dd:SetScript("OnClick", function(_, btn) setAbove((VendorFarmDB.above + (btn == "RightButton" and 5 or 1)) % 6) end)
    dd:EnableMouseWheel(true)
    dd:SetScript("OnMouseWheel", function(_, d) setAbove(math.max(0, math.min(5, VendorFarmDB.above + d))) end)
  end
  plusDD = dd

  local function toggle(text, key, anchor, x)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    if anchor then cb:SetPoint("LEFT", anchor, "RIGHT", x or 6, 0) else cb:SetPoint("TOPLEFT", 8, -26) end
    cb.text = cb.text or cb.Text
    if cb.text then cb.text:SetText(text); cb.text:SetFontObject("GameFontHighlightSmall") end
    cb:SetChecked(VendorFarmDB[key])
    cb:SetScript("OnClick", function(s) VendorFarmDB[key] = s:GetChecked() and true or false; ns.Refresh() end)
    frame["cb_" .. key] = cb
    return cb.text or cb
  end
  local a = toggle("Zone", "zoneOnly", nil)
  a = toggle("Elites", "elites", a, 4)
  a = toggle("Dungeons", "dungeons", a, 4)
  a = toggle("Skinning", "skinning", a, 4)
  toggle("AH price", "useAH", a, 4)

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusText:SetPoint("TOPLEFT", 10, -48); statusText:SetPoint("RIGHT", -10, 0); statusText:SetJustifyH("LEFT")

  local hdr = { { "Mob", 10, 170 }, { "Lvl", 180, 40, "CENTER" }, { "Zone", 222, 110 }, { "Per kill", 334, 60, "RIGHT" }, { "Gold/hr", 398, 66, "RIGHT" } }
  for _, h in ipairs(hdr) do
    local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", h[2], -64); f:SetWidth(h[3]); f:SetJustifyH(h[4] or "LEFT"); f:SetText(h[1])
  end
  rows = {}
end

local function layoutRows()
  local n = VendorFarmDB.rows
  frame:SetHeight(92 + n * ROW_H)
  for i = 1, math.max(n, #rows) do
    if i <= n then rows[i] = rows[i] or makeRow(i) end
    if rows[i] and i > n then rows[i]:Hide() end
  end
end

function ns.Refresh(newLevel)
  if not frame or not frame:IsShown() then return end
  layoutRows()
  local level = overrideLevel or newLevel or UnitLevel("player")
  ns.levelShown = level
  local db = VendorFarmDB
  -- don't overwrite the box while you are typing in it (item data refreshes the list every few seconds)
  if not fromBox:HasFocus() then fromBox:SetText(tostring(math.max(1, level - db.below))) end
  toText:SetText(("to %d%s"):format(level, overrideLevel and " |cff888888(/vfarm)|r" or ""))
  if plusDD.GenerateMenu then plusDD:GenerateMenu() elseif plusDD.SetText then plusDD:SetText("+" .. db.above) end
  for _, k in ipairs({ "zoneOnly", "elites", "dungeons", "skinning", "useAH" }) do
    if frame["cb_" .. k] then frame["cb_" .. k]:SetChecked(VendorFarmDB[k]) end
  end
  local list = ns.Rank(level)
  local est = ns.TargetEstimate()
  if est then
    statusText:SetText(("Targets together: |cffffffff%s/hr|r at %ds per kill. Right-click rows to add or remove."):format(money(est), db.killSec))
  else
    statusText:SetText(("Mobs %d-%d%s, %ds per kill%s. %d matches. Right-click a row to pick it as a target."):format(
      math.max(1, level - db.below), level + db.above, db.zoneOnly and " here" or "", db.killSec, (db.killSamples or 0) >= 5 and " (your pace)" or " (starting guess)", #list))
  end
  for i = 1, db.rows do
    local row, r = rows[i], list[i]
    row.data = r
    if r then
      local m = r.mob
      local o = ns.ObsFor(m.id)
      local mark = (o and o.k and o.k > 0 and VendorFarmDB.learn) and " |cff66ff66•|r" or ""
      row.name:SetText((r.target and "|cffffd100>|r " or "") .. m.name .. (m.rank ~= 0 and " |cffffd100*|r" or "") .. mark)
      row.lvl:SetText(m.minL == m.maxL and m.minL or (m.minL .. "-" .. m.maxL))
      row.zone:SetText((ns.ZoneName(m)))
      row.kill:SetText(money(r.perKill))
      row.hour:SetText(money(r.perHour))
      row:Show()
    else
      row:Hide()
    end
  end
end

function ns.CurrentLevel() return ns.levelShown or UnitLevel("player") end

function ns.IsShown() return frame and frame:IsShown() end

function ns.Toggle(level)
  if not frame then build() end
  if level then overrideLevel = level; frame:Show(); ns.Refresh(); return end
  if frame:IsShown() then frame:Hide() else frame:Show(); ns.Refresh() end
end
