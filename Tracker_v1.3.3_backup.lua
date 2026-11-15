-- VendorFarm Tracker: compact session window and kill-speed learning.
local ADDON, ns = ...

local BREAK = 180        -- a gap longer than this between kills is a break, not farming time
local ALPHA = 0.15       -- how fast the learned seconds-per-kill follows your recent kills
local tf, lines
local lastKill           -- GetTime() of the previous kill (this login)

local function session()
  local db = VendorFarmDB
  db.session = db.session or { kills = 0, gold = 0, expected = 0, active = 0, mobs = {} }
  return db.session
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
  local m = ns.IndexMobs()[id]
  if lastKill then
    local gap = now - lastKill
    if gap < BREAK then
      s.active = s.active + gap
      -- kill-speed learning: normalise elite kills back to a normal-mob pace
      local sec = gap
      if m and (m.rank == 1 or m.rank == 2) then sec = sec / math.max(1, db.eliteMult) end
      db.killEMA = db.killEMA and (db.killEMA * (1 - ALPHA) + sec * ALPHA) or sec
      db.killSamples = (db.killSamples or 0) + 1
      if db.killSamples >= 5 then
        db.killSec = math.max(5, math.min(300, math.floor(db.killEMA + 0.5)))
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
  ns.RefreshTracker()
end

local function resetSession()
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
  btn("Interface\\Buttons\\UI-RefreshButton", "Reset session", resetSession, expand)

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
  sec = math.floor(sec)
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
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
