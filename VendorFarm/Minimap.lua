-- VendorFarm minimap button (and a LibDataBroker launcher if a broker display is installed).
-- Left-click: list. Right-click: compact tracker. Shift-click: options. Drag to move.
local ADDON, ns = ...
local btn

local function tooltip(tt)
  tt:AddLine("VendorFarm")
  local s = VendorFarmDB.session
  if s and s.kills and s.kills > 0 then
    tt:AddDoubleLine("Session kills", s.kills, 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Looted", ns.Money(s.gold), 0.8, 0.8, 0.8, 1, 1, 1)
    if ns.SessionRate then tt:AddDoubleLine("Gold/hr", ns.Money(ns.SessionRate()), 0.8, 0.8, 0.8, 1, 1, 1) end
  else
    tt:AddLine("No kills this session yet.", 0.6, 0.6, 0.6)
  end
  tt:AddLine(" ")
  tt:AddLine("Left-click: farm list", 0.5, 1, 0.5)
  tt:AddLine("Right-click: compact tracker", 0.5, 1, 0.5)
  tt:AddLine("Shift-click: options", 0.5, 1, 0.5)
end

local function onClick(_, button)
  if IsShiftKeyDown() then ns.OpenOptions()
  elseif button == "RightButton" then ns.ToggleTracker()
  else ns.Toggle() end
end

local function place()
  local a = math.rad(VendorFarmDB.minimapAngle or 200)
  local x, y = math.cos(a), math.sin(a)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  local r = (Minimap:GetWidth() / 2) + 5
  if shape == "SQUARE" then
    -- push to the square's edge
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
    r = (Minimap:GetWidth() / 2) + 2
  end
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function build()
  btn = CreateFrame("Button", "VendorFarmMinimapButton", Minimap)
  btn:SetSize(31, 31); btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp"); btn:RegisterForDrag("LeftButton")
  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1); icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  btn:SetScript("OnClick", onClick)
  btn:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_LEFT"); tooltip(GameTooltip); GameTooltip:Show() end)
  btn:SetScript("OnLeave", GameTooltip_Hide)
  btn:SetScript("OnDragStart", function(s)
    s:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      VendorFarmDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      place()
    end)
  end)
  btn:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
  place()
end

function ns.UpdateMinimapButton()
  if VendorFarmDB.minimap then
    if not btn then build() end
    btn:Show(); place()
  elseif btn then
    btn:Hide()
  end
end

-- Broker displays (Titan, ChocolateBar, ElvUI datatexts...) pick this up if LibDataBroker is loaded.
local function registerBroker()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  if not LDB then return end
  LDB:NewDataObject("VendorFarm", {
    type = "launcher", icon = "Interface\\Icons\\INV_Misc_Coin_02", label = "VendorFarm",
    OnClick = onClick, OnTooltipShow = tooltip,
  })
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  ns.UpdateMinimapButton()
  pcall(registerBroker)
end)
