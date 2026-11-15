-- VendorFarm options panel (Settings API canvas, guarded for older clients).
local ADDON, ns = ...
local category

local function slider(parent, label, key, minV, maxV, step, y, fmt)
  -- OptionsSliderTemplate may be gone on newer clients; fall back to the plain slider.
  local ok, s = pcall(CreateFrame, "Slider", nil, parent, "OptionsSliderTemplate")
  if not ok or not s then s = CreateFrame("Slider", nil, parent, "UISliderTemplate") end
  s:SetPoint("TOPLEFT", 20, y); s:SetSize(260, 17)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
  local text = s.Text
  if not text then
    text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOM", s, "TOP", 0, 2)
  end
  local low, high = s.Low, s.High
  if low then low:SetText(minV) end
  if high then high:SetText(maxV) end
  local function upd(v) if text then text:SetText(label .. ": " .. (fmt and fmt(v) or v)) end end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    VendorFarmDB[key] = v; upd(v); if ns.Refresh then ns.Refresh() end
  end)
  s:SetScript("OnShow", function(self) self:SetValue(VendorFarmDB[key]); upd(VendorFarmDB[key]) end)
  return s
end

local function check(parent, label, key, y, tip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", 16, y)
  local t = cb.text or cb.Text
  if t then t:SetText(label) end
  cb:SetScript("OnShow", function(self) self:SetChecked(VendorFarmDB[key]) end)
  cb:SetScript("OnClick", function(self)
    VendorFarmDB[key] = self:GetChecked() and true or false
    if ns.Refresh then ns.Refresh() end
    if key == "minimap" and ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    if key == "spawnPins" and ns.UpdateSpawnPins then ns.UpdateSpawnPins() end
  end)
  if tip then
    cb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
  end
  return cb
end

function ns.InitOptions()
  local p = CreateFrame("Frame")
  p.name = "VendorFarm"
  local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16); t:SetText("VendorFarm " .. ns.VERSION)
  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 16, -40); sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("Gold/hr = (coin + drop chance x sell price) x kills per hour. Kills per hour comes from your own pace, timed between kills (gaps over 3 minutes count as breaks). Sell prices are read live from your client; drop rates come from the CMaNGOS vanilla database. Open the list with /vfarm, or /vfarm 32 to check another level. The level range is set at the top of the list window.")

  -- Kill pace is learned, not set: show it read-only with a reset button.
  local pace = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pace:SetPoint("TOPLEFT", 20, -92); pace:SetWidth(420); pace:SetJustifyH("LEFT")
  local elite = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  elite:SetPoint("TOPLEFT", 20, -114); elite:SetWidth(420); elite:SetJustifyH("LEFT")
  local function showPace()
    local db = VendorFarmDB
    local n = db.killSamples or 0
    if n >= 5 then
      pace:SetText(("Your kill pace: |cffffffff%ds per kill|r (learned from %d kills, incl. loot and rest)"):format(db.killSec, n))
    else
      pace:SetText(("Your kill pace: |cffffffff%ds per kill|r (starting guess; learns after %d more kills)"):format(db.killSec, 5 - n))
    end
    local e = db.eliteSamples or 0
    elite:SetText(("Elites take |cffffffff%.1fx|r as long%s"):format(db.eliteMult,
      e >= 3 and (" (learned from %d elite kills)"):format(e) or (" (starting guess; learns after %d elite kills)"):format(3 - e)))
  end
  p:SetScript("OnShow", showPace)
  local resetPace = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  resetPace:SetSize(110, 22); resetPace:SetPoint("LEFT", pace, "RIGHT", 8, 0); resetPace:SetText("Reset pace")
  resetPace:SetScript("OnClick", function()
    local db = VendorFarmDB
    db.killSec, db.killEMA, db.killSamples = ns.DEFAULTS.killSec, nil, 0
    db.pace = {}
    db.eliteMult, db.eliteEMA, db.eliteSamples = ns.DEFAULTS.eliteMult, nil, 0
    showPace(); if ns.Refresh then ns.Refresh() end
  end)

  slider(p, "Rows shown", "rows", 5, 30, 1, -160)
  slider(p, "Kills until your own drop rates take over", "learnFull", 10, 250, 10, -205)

  local y = -245
  check(p, "Include elites", "elites", y); y = y - 24
  check(p, "Include dungeon mobs", "dungeons", y, "Instance mobs. Remember the instance cap (players report 5 per hour)."); y = y - 24
  check(p, "Include rares", "rares", y, "Rare spawns are listed as if they were always up, so their gold/hr is not realistic."); y = y - 24
  check(p, "Add skinning loot", "skinning", y, "Adds leather and hides at vendor price (or AH price if that's on)."); y = y - 24
  check(p, "Use Auctionator price when higher", "useAH", y, "Non-grey items use Auctionator's last scan minus the 5% AH cut, when that beats the vendor price."); y = y - 24
  check(p, "Learn drop rates from my kills", "learn", y, "Records your kills, coin and loot per mob. Your rates blend in as kills grow and fully replace the database at the kill count above. Mobs marked with a green dot have your data. /vfarm resetdata clears it."); y = y - 24
  check(p, "Only mobs in my current zone", "zoneOnly", y); y = y - 24
  check(p, "Share my drop data with other VendorFarm users", "syncShare", y, "Sends your kill, coin and loot totals per mob through hidden addon messages (guild, party and the hidden channel below). Only counts, nothing else. Paused in combat and in instances."); y = y - 24
  check(p, "Use other players' drop data", "syncUse", y, "Blends everyone's kills into the drop rates. Each player counts for at most 500 kills per mob, and impossible numbers are thrown out. Blue dot = community data only."); y = y - 24
  check(p, "Use the hidden VendorFarmSync channel", "syncPublic", y, "Joins a hidden chat channel so you can share with every VendorFarm user online, not just your guild and group. Takes effect after /reload."); y = y - 24
  local syncLine = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  syncLine:SetPoint("TOPLEFT", 20, y - 4); y = y - 24
  p:HookScript("OnShow", function()
    if ns.SyncStatus then
      local players, mobs, kills, onChannel = ns.SyncStatus()
      syncLine:SetText(("Community data: %d players, %d mobs, %d kills. Hidden channel: %s."):format(players, mobs, kills, onChannel and "joined" or "not joined"))
    end
  end)
  check(p, "Spawn dots on the map and minimap", "spawnPins", y, "Your farm targets and the waypoint mob show every spawn point. Hovering a row in the list previews its spawns while the world map is open."); y = y - 24
  check(p, "Show minimap button", "minimap", y, "Left-click: list. Right-click: tracker. Shift-click: options. Drag to move."); y = y - 24
  check(p, "Cap kills/hr by respawn rate", "respawnCap", y, "Limits kills per hour to spawn count x 3600 / respawn time, for mobs with few spawns."); y = y - 24

  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(p, "VendorFarm")
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
  end
  ns.optionsPanel = p
end

function ns.OpenOptions()
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
    InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
  end
end
