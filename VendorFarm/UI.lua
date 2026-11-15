-- VendorFarm UI: one small movable window with the ranked list.
local ADDON, ns = ...

local ROW_H, W = 18, 520
local OFF = 0   -- extra vertical space when the Gathering checkbox row is shown
local frame, rows, fromBox, toText, plusDD, statusText, headers, tabs
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

local function showDungeonTooltip(row, d)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(d.name, 1, 1, 1)
  if d.minL then GameTooltip:AddDoubleLine("Mob levels", d.minL .. "-" .. d.maxL, 0.8, 0.8, 0.8, 1, 1, 1) end
  if d.mobs > 0 then GameTooltip:AddDoubleLine("Mobs per clear", ("%d (%d elite)"):format(d.mobs, d.elites), 0.8, 0.8, 0.8, 1, 1, 1) end
  local m, s = math.floor(d.runSec / 60), math.floor(d.runSec) % 60
  GameTooltip:AddDoubleLine("Run time", ("%d:%02d %s"):format(m, s, d.timeSource == "yours" and ("(your " .. d.yourRuns .. " runs)") or "(estimate)"), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Runs per hour", ("%.1f%s"):format(d.runsHr, d.capped and " (instance cap)" or ""), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Biggest earners per clear", 1, 0.82, 0)
  for i = 1, math.min(10, #d.parts) do
    local p = d.parts[i]
    if p.v >= 1 then
      local tag = p.mob.rank == 3 and " |cffff8000boss|r" or ""
      GameTooltip:AddDoubleLine(("%s x%d%s"):format(p.mob.name, p.mob.spawns, tag), money(p.v), 1, 1, 1, 1, 1, 1)
    end
  end
  GameTooltip:AddDoubleLine("Gold per run", money(d.perRun), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Full clear of every spawn, valued like the mob list (your drop rates, vendor or AH). This is the whole group's loot: in a group of 5 your share is about a fifth. Gold per run blends to your own runs over 5 runs.", 0.6, 0.6, 0.6, true)
  GameTooltip:AddLine("Runs are logged when you leave the dungeon (3 min minimum). The 5 per hour cap is player-reported, not published.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function showTooltip(row)
  local r = row.data; if not r then return end
  if r.dungeon then return showDungeonTooltip(row, r) end
  if r.history then return ns.HistoryTooltip(row, r) end
  if r.kind then return ns.GatherTooltip(row, r) end
  local m = r.mob
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(m.name .. (RANK[m.rank] or ""), 1, 1, 1)
  local lvl = m.minL == m.maxL and m.minL or (m.minL .. "-" .. m.maxL)
  GameTooltip:AddDoubleLine("Level " .. lvl, (ns.ZoneName(m)), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
  local sec, pace = ns.MobPace(m)
  GameTooltip:AddDoubleLine("Seconds per kill", (pace and pace.n >= 3) and ("%ds (your %d kills here)"):format(math.floor(sec + 0.5), pace.n) or ("%ds (your overall pace)"):format(math.floor(sec + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Kills/hr", ("%d"):format(r.kph), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Spawns / respawn", ("%d / %ds"):format(m.spawns, m.respawn), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddLine(" ")
  local coin, items, rest, skin, w, o = ns.Effective(m)
  if o and o.k and o.k > 0 then
    local own = o.ownK or o.k
    if own > 0 then GameTooltip:AddDoubleLine("Your kills", tostring(own), 0.4, 1, 0.4, 0.4, 1, 0.4) end
    if (o.players or 0) > 0 then
      GameTooltip:AddDoubleLine("Community kills", ("%d from %d players"):format(o.otherK, o.players), 0.4, 0.8, 1, 0.4, 0.8, 1)
    end
    GameTooltip:AddDoubleLine("Learned weight", ("%d%%"):format(math.floor(w * 100 + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
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
  GameTooltip:AddLine(w > 0 and "Drop rates: your and other players' kills blended with the CMaNGOS vanilla DB." or "Drop rates: CMaNGOS vanilla DB, not Forever-measured.", 0.6, 0.6, 0.6, true)
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
  r.name = fs(2, 200); r.lvl = fs(204, 40, "CENTER"); r.zone = fs(246, 130)
  r.kill = fs(378, 64, "RIGHT"); r.hour = fs(444, 66, "RIGHT")
  r:SetScript("OnEnter", function(self)
    showTooltip(self)
    local d = self.data
    local id = d and (d.mob and d.mob.id or d.mobID)
    if id and not d.dungeon and ns.PreviewSpawns then ns.PreviewSpawns(id) end
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide(); if ns.ClearPreview then ns.ClearPreview() end end)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, btn)
    if not self.data or self.data.dungeon or not self.data.mob then return end
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

  -- Mobs / Dungeons tabs
  tabs = {}
  local function tab(key, text, x, w)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(w, 18); b:SetPoint("TOPLEFT", x, -5)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER"); b.text:SetText(text)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(1, 0.82, 0, 1); b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", 4, 0); b.line:SetPoint("BOTTOMRIGHT", -4, 0)
    b:SetScript("OnClick", function() VendorFarmDB.tab = key; ns.Refresh() end)
    tabs[key] = b
  end
  tab("mobs", "Mobs", 4, 48)
  tab("dungeons", "Dungeons", 52, 68)
  tab("history", "History", 120, 60)
  tab("gathering", "Gathering", 182, 70)

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
  local vendor = ns.VendorButton(frame)
  vendor:SetPoint("RIGHT", compact, "LEFT", -4, 0)
  compact:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText("Compact tracker"); GameTooltip:Show() end)
  compact:SetScript("OnLeave", GameTooltip_Hide)
  gear:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText("Options"); GameTooltip:Show() end)
  gear:SetScript("OnLeave", GameTooltip_Hide)

  -- Level range: From <box> to <your level> plus a +0..+5 dropdown.
  local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lbl:SetPoint("TOPLEFT", 262, -10); lbl:SetText("From")
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

  -- Gathering tab: which kinds of gathering to rank (shown only on that tab)
  frame.gRow = CreateFrame("Frame", nil, frame)
  frame.gRow:SetPoint("TOPLEFT", 0, -46); frame.gRow:SetSize(W, 20)
  frame.gChecks = {}
  local ga
  for _, g in ipairs({ { "gHerb", "Herbalism", "herb" }, { "gOre", "Mining", "ore" }, { "gSkin", "Skinning", "skin" }, { "gFish", "Fishing", "fish" } }) do
    local cb = CreateFrame("CheckButton", nil, frame.gRow, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    if ga then cb:SetPoint("LEFT", ga, "RIGHT", 6, 0) else cb:SetPoint("LEFT", 8, 0) end
    cb.text = cb.text or cb.Text
    if cb.text then cb.text:SetFontObject("GameFontHighlightSmall") end
    cb.label, cb.prof, cb.key = g[2], g[3], g[1]
    cb:SetScript("OnClick", function(s) VendorFarmDB[s.key] = s:GetChecked() and true or false; ns.Refresh() end)
    frame.gChecks[#frame.gChecks + 1] = cb
    ga = cb.text or cb
  end

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusText:SetPoint("TOPLEFT", 10, -48); statusText:SetPoint("RIGHT", -10, 0); statusText:SetJustifyH("LEFT")

  local hdr = { { "Mob", 10, 200 }, { "Lvl", 212, 40, "CENTER" }, { "Zone", 254, 130 }, { "Per kill", 386, 64, "RIGHT" }, { "Gold/hr", 452, 66, "RIGHT" } }
  headers = {}
  for i, h in ipairs(hdr) do
    local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", h[2], -64); f:SetWidth(h[3]); f:SetJustifyH(h[4] or "LEFT"); f:SetText(h[1])
    f.x = h[2]
    headers[i] = f
  end
  rows = {}
end

local function layoutRows()
  local n = VendorFarmDB.rows
  frame:SetHeight(92 + OFF + n * ROW_H)
  statusText:SetPoint("TOPLEFT", 10, -48 - OFF)
  for _, h in ipairs(headers) do h:SetPoint("TOPLEFT", h.x, -64 - OFF) end
  for i = 1, math.max(n, #rows) do
    if i <= n then rows[i] = rows[i] or makeRow(i); rows[i]:SetPoint("TOPLEFT", 8, -80 - OFF - (i - 1) * ROW_H) end
    if rows[i] and i > n then rows[i]:Hide() end
  end
end

function ns.Refresh(newLevel)
  if not frame or not frame:IsShown() then return end
  local gathering = VendorFarmDB.tab == "gathering"
  OFF = gathering and 22 or 0
  frame.gRow:SetShown(gathering)
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
  local dungeons = db.tab == "dungeons"
  for key, b in pairs(tabs) do
    local on = key == (tabs[db.tab] and db.tab or "mobs")
    b.line:SetShown(on); b.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
  end
  local history = db.tab == "history"
  local names = dungeons and { "Dungeon", "Lvl", "Run time", "Per run", "Gold/hr" }
    or history and { "Spot you farmed", "Lvl", "Zone", "vs model", "Made/hr" }
    or { "Mob", "Lvl", "Zone", "Per kill", "Gold/hr" }
  for i, h in ipairs(headers) do h:SetText(names[i]) end
  if gathering then
    for i, h in ipairs(headers) do h:SetText(({ "Zone / gathering", "Lvl", "Nodes up / rate", "Per node", "Gold/hr" })[i]) end
    local sk = ns.ProfSkills()
    for _, cb in ipairs(frame.gChecks) do
      cb:SetChecked(db[cb.key])
      if cb.text then cb.text:SetText(cb.label .. (sk[cb.prof] and (" |cffaaaaaa" .. sk[cb.prof] .. "|r") or " |cff666666-|r")) end
    end
    local list, state, prog = ns.GatherRank(level)
    if state == "working" then
      statusText:SetText(("Placing %d%% of the herb and ore spots into zones (first time only this session)..."):format(prog * 100))
    elseif state == "failed" and (db.gHerb or db.gOre) then
      statusText:SetText("Couldn't place herb/ore spots into zones on this client. Fishing and skinning still work. Try /vfarm check.")
    else
      statusText:SetText(("%d results%s. Rates say est until you've gathered or fished there; hover for the breakdown."):format(#list, db.zoneOnly and " in this zone" or ""))
    end
    for i = 1, db.rows do
      local row, r = rows[i], list[i]
      row.data = r
      if r then
        local col = r.kind == "nodes" and "|cff66ff66" or (r.kind == "fish" and "|cff66ccff" or "|cffffcc66")
        row.name:SetText(r.name .. "  " .. col .. r.tag .. "|r")
        row.lvl:SetText(r.lvl or "")
        row.zone:SetText(r.rate)
        row.kill:SetText(money(r.per))
        row.hour:SetText(money(r.perHour))
        row:Show()
      else
        row:Hide()
      end
    end
    if state == "working" then C_Timer.After(0.3, function() ns.Refresh() end) end
    return
  end
  if history then
    local list = ns.HistoryRank(level)
    statusText:SetText(#list > 0 and ("%d spots from %d saved sessions, ranked by the gold/hr you really made. Hover for each session."):format(#list, #(db.history or {}))
      or "No saved sessions yet. A session is saved when you end it on the tracker or after 15 minutes without a kill.")
    for i = 1, db.rows do
      local row, sp = rows[i], list[i]
      row.data = sp
      if sp then
        row.name:SetText(sp.name .. (sp.n > 1 and (" |cff888888x" .. sp.n .. "|r") or ""))
        row.lvl:SetText(tostring(sp.lvl or "?"))
        row.zone:SetText(sp.zone)
        if sp.luck then
          local pct = sp.luck * 100
          local col = pct >= 100 and "66ff66" or (pct >= 75 and "ffd100" or "ff6666")
          row.kill:SetText(("|cff%s%d%%|r"):format(col, pct))
        else
          row.kill:SetText("-")
        end
        row.hour:SetText(money(sp.perHour))
        row:Show()
      else
        row:Hide()
      end
    end
    return
  end
  if dungeons then
    local list, cap = ns.DungeonRank(level)
    statusText:SetText(("Dungeons up to level %d, full clears, max %d runs/hr. Times are typical clears until you run one."):format(level + db.above, cap))
    for i = 1, db.rows do
      local row, d = rows[i], list[i]
      row.data = d
      if d then
        d.dungeon = true
        local col = (d.minL and d.minL > level + 2) and "|cffff6666" or ((d.maxL and d.maxL < level - 10) and "|cff9d9d9d" or "|cffffffff")
        row.name:SetText(col .. d.name .. "|r" .. (d.yourRuns > 0 and " |cff66ff66•|r" or ""))
        row.lvl:SetText(d.minL and (d.minL .. "-" .. d.maxL) or "?")
        local m, s = math.floor(d.runSec / 60), math.floor(d.runSec) % 60
        row.zone:SetText(("%d:%02d%s"):format(m, s, d.timeSource == "yours" and "" or " |cff888888est|r"))
        row.kill:SetText(money(d.perRun))
        row.hour:SetText(money(d.perHour))
        row:Show()
      else
        row:Hide()
      end
    end
    return
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
      local o = ns.CombinedObs and ns.CombinedObs(m.id) or ns.ObsFor(m.id)
      local mark = ""
      if VendorFarmDB.learn and o and o.k and o.k > 0 then
        mark = ((o.ownK or o.k) > 0) and " |cff66ff66•|r" or " |cff66ccff•|r"   -- green: yours, blue: community only
      end
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

function ns.Toggle(level, forceShow)
  if not frame then build() end
  if forceShow then frame:Show(); ns.Refresh(); return end
  if level then overrideLevel = level; frame:Show(); ns.Refresh(); return end
  if frame:IsShown() then frame:Hide() else frame:Show(); ns.Refresh() end
end
