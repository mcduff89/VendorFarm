-- VendorFarm Tracker: compact session window and kill-speed learning.
local ADDON, ns = ...

local BREAK = 180        -- a gap longer than this between kills is a break, not farming time
local SESSION_GAP = 900  -- 15 minutes without a kill ends the session (it goes to History)
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

function ns.OnLoot(copper)
  if not copper or copper <= 0 then return end
  local s = session()
  s.gold = s.gold + copper
  if ns.OnRunLoot then ns.OnRunLoot(copper) end
  ns.RefreshTracker()
end

local function resetSession()
  if ns.ArchiveSession() then print("|cffffd100VendorFarm|r: session saved to History.") end
  VendorFarmDB.session = nil
  lastKill = nil
  ns.RefreshTracker()
end

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
    lines[4]:SetText("|cff888888No targets: right-click mobs in the list.|r")
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
