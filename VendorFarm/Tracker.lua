-- VendorFarm Tracker: compact session window and kill-speed learning.
local ADDON, ns = ...

local BREAK = 180        -- a gap longer than this between kills is a break, not farming time
local SESSION_GAP = 900  -- 15 minutes without a kill ends the session (it goes to History) automatically
local ALPHA = 0.15       -- how fast the learned seconds-per-kill follows your recent kills
local tf, lines
local lastKill           -- GetTime() of the previous kill (this login)

local function session()
  local db = VendorFarmDB
  db.session = db.session or { kills = 0, gold = 0, expected = 0, active = 0, mobs = {} }
  local s = db.session
  s.zones = s.zones or {}
  s.start = s.start or time()
  return s
end

local function activeSeconds()
  local s = session()
  local live = 0
  if lastKill then
    local gap = GetTime() - lastKill
    if gap < BREAK then live = gap end
  end
  return s.active + live
end

function ns.OnKill(id)
  local db, s = VendorFarmDB, session()
  local now = GetTime()
  -- long gap (also across logouts): save the old session and start a new one
  if s.last and time() - s.last > SESSION_GAP then
    ns.ArchiveSession()
    db.session = nil; lastKill = nil
    s = session()
  end
  s.last = time()
  s.lvl = UnitLevel("player")
  local zone = GetRealZoneText and GetRealZoneText() or "?"
  if zone and zone ~= "" then s.zones[zone] = (s.zones[zone] or 0) + 1 end
  local m = ns.IndexMobs()[id]
  if lastKill then
    local gap = now - lastKill
    if gap < BREAK then
      s.active = s.active + gap
      -- per-mob pace (time from the previous kill to this one)
      db.pace = db.pace or {}
      local p = db.pace[id] or { e = gap, n = 0 }
      p.e = p.n == 0 and gap or (p.e * (1 - ALPHA) + gap * ALPHA)
      p.n = p.n + 1
      db.pace[id] = p
      ns.Debug("pace: %.0fs since last kill; mob %d now %.0fs over %d kills", gap, id, p.e, p.n)
      -- kill-speed learning: normal and elite kills are timed separately;
      -- the elite multiplier is elite pace / normal pace once both have data.
      if m and (m.rank == 1 or m.rank == 2) then
        db.eliteEMA = db.eliteEMA and (db.eliteEMA * (1 - ALPHA) + gap * ALPHA) or gap
        db.eliteSamples = (db.eliteSamples or 0) + 1
      else
        db.killEMA = db.killEMA and (db.killEMA * (1 - ALPHA) + gap * ALPHA) or gap
        db.killSamples = (db.killSamples or 0) + 1
        if db.killSamples >= 5 then
          db.killSec = math.max(5, math.min(300, math.floor(db.killEMA + 0.5)))
        end
      end
      if (db.eliteSamples or 0) >= 3 and db.killEMA and db.killEMA > 0 then
        db.eliteMult = math.max(1, math.min(10, db.eliteEMA / db.killEMA))
      end
    end
  end
  lastKill = now
  s.kills = s.kills + 1
  s.mobs[id] = (s.mobs[id] or 0) + 1
  if m then s.expected = s.expected + ns.ValuePerKill(m) end
  ns.RefreshTracker()
end

function ns.OnLoot(copper, what, qty)
  if not copper or copper <= 0 then return end
  local s = session()
  s.gold = s.gold + copper
  -- breakdown for the Looted tooltip: coin, and items at vendor price vs. Auctionator price
  if what then s.split = (s.split or 0) + copper end
  if what == "coin" then
    s.coin = (s.coin or 0) + copper
  elseif what then
    local vendor, ah = ns.ItemBoth(what)
    qty = qty or 1
    s.items = (s.items or 0) + qty
    s.itemsV = (s.itemsV or 0) + vendor * qty
    s.itemsBest = (s.itemsBest or 0) + math.max(vendor, ah or 0) * qty
    if ah then
      s.ahItems = (s.ahItems or 0) + qty
      s.itemsA = (s.itemsA or 0) + ah * qty
      s.itemsAV = (s.itemsAV or 0) + vendor * qty   -- vendor value of the same items, to compare
    end
  end
  if ns.OnRunLoot then ns.OnRunLoot(copper) end
  ns.RefreshTracker()
end

local function resetSession()
  if ns.ArchiveSession() then print("|cffffd100VendorFarm|r: session saved to History.") end
  VendorFarmDB.session = nil
  lastKill = nil
  ns.RefreshTracker()
end

-- Automatic session end: 15 minutes without a kill, taking a flight path,
-- or going into (or out of) a dungeon/raid. Only when the session has kills.
local function autoEnd(reason)
  local s = VendorFarmDB.session
  if not s or (s.kills or 0) == 0 then return end
  local saved = ns.ArchiveSession()
  VendorFarmDB.session = nil
  lastKill = nil
  print(("|cffffd100VendorFarm|r: session ended (%s)%s."):format(reason, saved and ", saved to History" or ""))
  ns.RefreshTracker()
end
ns.AutoEndSession = autoEnd

local function idleCheck()
  local s = VendorFarmDB and VendorFarmDB.session
  if s and s.last and time() - s.last > SESSION_GAP then autoEnd("15 minutes without a kill") end
  if UnitOnTaxi and UnitOnTaxi("player") then autoEnd("flight path") end
end

local function instanceKey()
  local inInst, kind = IsInInstance()
  if inInst and (kind == "party" or kind == "raid") then
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    return tostring(id or name)
  end
  return "world"
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_CONTROL_LOST")
ev:SetScript("OnEvent", function(_, event)
  if not VendorFarmDB then return end
  if event == "PLAYER_CONTROL_LOST" then
    C_Timer.After(1, function()
      if UnitOnTaxi and UnitOnTaxi("player") then autoEnd("flight path") end
    end)
    return
  end
  C_Timer.After(1, function()
    local key = instanceKey()
    local prev = VendorFarmDB.lastInstance
    VendorFarmDB.lastInstance = key
    -- a /reload or relog in the same place is not a zone change
    if prev and prev ~= key then
      autoEnd(key == "world" and "left the dungeon" or "entered a dungeon")
    end
    idleCheck()
  end)
end)
if C_Timer.NewTicker then C_Timer.NewTicker(30, idleCheck) end

local function build()
  tf = CreateFrame("Frame", "VendorFarmTracker", UIParent, "BackdropTemplate")
  tf:SetSize(230, 86)
  tf:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  tf:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
  tf:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
  tf:SetClampedToScreen(true)
  tf:EnableMouse(true); tf:SetMovable(true); tf:RegisterForDrag("LeftButton")
  tf:SetScript("OnDragStart", tf.StartMoving)
  tf:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint(); VendorFarmDB.trackerPoint = { p, rp, x, y }
  end)
  local pt = VendorFarmDB.trackerPoint
  if pt then tf:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else tf:SetPoint("TOPRIGHT", -260, -220) end

  local title = tf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 6, -5); title:SetText("VendorFarm")

  local function btn(tex, tip, onClick, anchor)
    local b = CreateFrame("Button", nil, tf)
    b:SetSize(14, 14)
    if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -3, 0) else b:SetPoint("TOPRIGHT", -4, -4) end
    b:SetNormalTexture(tex)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show() end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
  end
  local close = btn("Interface\\Buttons\\UI-StopButton", "Hide tracker", function() ns.ShowTracker(false) end)
  local expand = btn("Interface\\Buttons\\UI-PlusButton-Up", "Open the full list", function() ns.Toggle() end, close)
  local reset = btn("Interface\\Buttons\\UI-RefreshButton", "End session (saves it to History) and start a new one", resetSession, expand)
  ns.VendorButton(tf):SetPoint("RIGHT", reset, "LEFT", -3, 0)

  lines = {}
  for i = 1, 4 do
    local f = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", 6, -6 - i * 15); f:SetPoint("RIGHT", -6, 0); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
    lines[i] = f
    -- invisible hover area over each line for its explanation tooltip
    local h = CreateFrame("Frame", nil, tf)
    h:SetPoint("TOPLEFT", 4, -4 - i * 15); h:SetPoint("RIGHT", -4, 0); h:SetHeight(15)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_BOTTOM"); ns.TrackerTooltip(i); GameTooltip:Show() end)
    h:SetScript("OnLeave", GameTooltip_Hide)
    -- keep dragging the window working through the hover areas
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function() tf:StartMoving() end)
    h:SetScript("OnDragStop", function() tf:GetScript("OnDragStop")(tf) end)
  end
  -- tick once a second so the clock and live gold/hr move (cheap, elapsed-time throttle)
  local acc = 0
  tf:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc >= 1 then acc = 0; ns.RefreshTracker() end
  end)
end

local function clock(sec)
  return ns.Clock(sec)
end

function ns.Clock(sec)
  sec = math.floor(sec)
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
end

function ns.TrackerTooltip(i)
  local db, s = VendorFarmDB, session()
  local money = ns.Money
  local tt = GameTooltip
  local act = activeSeconds()
  local hrs = act / 3600
  local function row(l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
  local function note(t) tt:AddLine(t, 0.6, 0.6, 0.6, true) end
  if i == 1 then
    tt:AddLine("Farming time", 1, 0.82, 0)
    row("Active farming", ns.Clock(act))
    row("Kills", s.kills)
    row("Your pace", s.kills > 1 and ("%ds per kill"):format(act / (s.kills - 1)) or "-")
    row("Pace the model uses", ("%ds (%s)"):format(db.killSec, (db.killSamples or 0) >= 5 and "learned" or "starting guess"))
    note("Only time between kills counts. A gap over 3 minutes is a break and isn't added. 15 minutes without a kill ends the session and saves it to History.")
  elseif i == 2 then
    tt:AddLine("What you looted", 1, 0.82, 0)
    row("Coin", money(s.coin or 0))
    row(("Items (%d) at vendor price"):format(s.items or 0), money(s.itemsV or 0))
    if (s.ahItems or 0) > 0 then
      row(("  %d of them have AH prices"):format(s.ahItems), ("%s on AH vs %s vendor"):format(money(s.itemsA or 0), money(s.itemsAV or 0)))
    else
      row("  AH prices", "none (no Auctionator scan)")
    end
    local older = s.gold - (s.split or 0)
    if older > 1 then row("Looted before the breakdown existed", money(older)) end
    tt:AddLine(" ")
    row("Total if you vendor it all", money((s.coin or 0) + (s.itemsV or 0) + math.max(0, older)))
    row("Total selling each the best way", money((s.coin or 0) + (s.itemsBest or 0) + math.max(0, older)))
    if hrs > 0.003 then
      row("Per hour (vendor / best)", ("%s / %s"):format(money(((s.coin or 0) + (s.itemsV or 0)) / hrs), money(((s.coin or 0) + (s.itemsBest or 0)) / hrs)))
    end
    note(("The Looted number uses %s. AH prices are Auctionator's last scan minus the 5%% cut; soulbound items are vendor only."):format(
      db.useAH and "the AH price when it beats the vendor (AH price is on)" or "vendor prices (AH price is off in the list)"))
  elseif i == 3 then
    tt:AddLine("Model and luck", 1, 0.82, 0)
    row("Model", money(hrs > 0.003 and s.expected / hrs or 0) .. "/hr")
    row("Expected so far", money(s.expected))
    row("Actually looted", money(s.gold))
    note("Model: for every mob you killed, what VendorFarm expected it to drop on average (drop rates x prices, plus average coin), added up over your farming time.")
    note("Luck: what you actually looted divided by that expectation. 100% is exactly average, above 100% is lucky, below is unlucky. Rare drops make it swing a lot over short sessions.")
  else
    tt:AddLine("Farm targets", 1, 0.82, 0)
    local est = ns.TargetEstimate()
    if est then
      row("Plan", money(est) .. "/hr")
      for id in pairs(db.targets or {}) do
        local m = ns.IndexMobs()[id]
        if m then tt:AddLine("  " .. m.name, 1, 1, 1) end
      end
      note("Plan: the model's gold/hr if you kill your targets in rotation. \"of plan\" compares what you're actually making against it.")
    else
      note("Click mobs in the list to track them. They get spawn dots on the map and a planned gold/hr here.")
    end
  end
end

function ns.SessionRate()
  local hrs = activeSeconds() / 3600
  return hrs > 0.003 and session().gold / hrs or 0
end

function ns.RefreshTracker()
  if not tf or not tf:IsShown() then return end
  local db, s = VendorFarmDB, session()
  local money = ns.Money
  local act = activeSeconds()
  local hrs = act / 3600
  local perKill = s.kills > 1 and (act / (s.kills - 1)) or nil
  lines[1]:SetText(("%s farming  |  %d kills  |  %s"):format(clock(act), s.kills,
    perKill and ("%ds/kill"):format(perKill) or (db.killSec .. "s/kill model")))
  local actual = hrs > 0.003 and s.gold / hrs or 0
  lines[2]:SetText(("Looted |cffffffff%s|r  ->  |cffffffff%s/hr|r"):format(money(s.gold), money(actual)))
  local exp = hrs > 0.003 and s.expected / hrs or 0
  local pct = s.expected > 0 and (s.gold / s.expected * 100) or nil
  local col = not pct and "ffffff" or (pct >= 100 and "66ff66" or (pct >= 75 and "ffd100" or "ff6666"))
  lines[3]:SetText(("Model %s/hr%s"):format(money(exp),
    pct and ("  |  luck |cff%s%d%%|r"):format(col, pct) or ""))
  local est, names = ns.TargetEstimate()
  if est then
    local eff = (actual > 0 and est > 0) and ("  |  |cffffffff%d%%|r of plan"):format(actual / est * 100) or ""
    lines[4]:SetText(("Targets %s/hr%s"):format(money(est), eff))
  else
    lines[4]:SetText("|cff888888No targets: click mobs in the list.|r")
  end
end

function ns.ShowTracker(show)
  if not tf then build() end
  VendorFarmDB.trackerShown = show and true or false
  if show then tf:Show(); ns.RefreshTracker() else tf:Hide() end
end

function ns.ToggleTracker()
  ns.ShowTracker(not (tf and tf:IsShown()))
end

function ns.InitTracker()
  if VendorFarmDB.trackerShown then ns.ShowTracker(true) end
end
