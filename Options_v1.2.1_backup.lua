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
  cb:SetScript("OnClick", function(self) VendorFarmDB[key] = self:GetChecked() and true or false; if ns.Refresh then ns.Refresh() end end)
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
  sub:SetText("Gold/hr = (coin + drop chance x sell price) x kills per hour. Sell prices are read live from your client; drop rates come from the CMaNGOS vanilla database. Open the list with /vfarm, or /vfarm 32 to check another level.")

  slider(p, "Scan from (levels under you)", "below", 0, 20, 1, -90)
  slider(p, "Add levels above you (+)", "above", 0, 5, 1, -135, function(v) return "+" .. v end)
  slider(p, "Seconds per kill (incl. loot and rest)", "killSec", 8, 90, 1, -180, function(v) return v .. "s" end)
  slider(p, "Elite kill time multiplier", "eliteMult", 1, 6, 0.5, -225, function(v) return ("x%.1f"):format(v) end)
  slider(p, "Rows shown", "rows", 5, 30, 1, -270)
  slider(p, "Kills until your own drop rates take over", "learnFull", 5, 100, 5, -315)

  local y = -355
  check(p, "Include elites", "elites", y); y = y - 28
  check(p, "Include dungeon mobs", "dungeons", y, "Instance mobs. Remember the instance cap (players report 5 per hour)."); y = y - 28
  check(p, "Include rares", "rares", y, "Rare spawns are listed as if they were always up, so their gold/hr is not realistic."); y = y - 28
  check(p, "Add skinning loot", "skinning", y, "Adds leather and hides at vendor price (or AH price if that's on)."); y = y - 28
  check(p, "Use Auctionator price when higher", "useAH", y, "Non-grey items use Auctionator's last scan minus the 5% AH cut, when that beats the vendor price."); y = y - 28
  check(p, "Learn drop rates from my kills", "learn", y, "Records your kills, coin and loot per mob. Your rates blend in as kills grow and fully replace the database at the kill count above. Mobs marked with a green dot have your data. /vfarm resetdata clears it."); y = y - 28
  check(p, "Cap kills/hr by respawn rate", "respawnCap", y, "Limits kills per hour to spawn count x 3600 / respawn time, for mobs with few spawns."); y = y - 28

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
