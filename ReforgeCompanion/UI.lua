-- Kleines verschiebbares Fenster mit dem Log-Status und die Befehle /reforge und /rfc.
local _, ns = ...
local L = ns.L

local window, dot, title, detail

local COLORS = {
  on = { 0.35, 0.79, 0.55 },
  off = { 0.55, 0.60, 0.66 },
  warn = { 0.94, 0.71, 0.29 },
}

local function clock(seconds)
  seconds = math.floor(seconds)
  local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
  if hours > 0 then
    return ("%d:%02d:%02d"):format(hours, minutes, seconds % 60)
  end
  return ("%d:%02d"):format(minutes, seconds % 60)
end

local function detailText(status)
  if status.state == "unavailable" then
    return ""
  end
  if status.state == "on" then
    if status.stopsIn then
      return L.stopsIn:format(clock(status.stopsIn))
    end
    if not status.advanced then
      return L.noAdvanced
    end
    local where = status.kind and L[status.kind]
    local elapsed = status.elapsed and clock(status.elapsed)
    if where and elapsed then
      return where .. " · " .. elapsed
    end
    return where or elapsed or ""
  end
  if status.suppressed then
    return L.manualOff
  end
  return status.auto and L.autoOn or L.autoOff
end

function ns.RefreshWindow()
  if not window then
    return
  end
  local status = ns.Status()
  local color = COLORS.off
  if status.state == "unavailable" then
    color = COLORS.warn
    title:SetText(L.unavailable)
  elseif status.state == "on" then
    color = status.advanced and COLORS.on or COLORS.warn
    title:SetText(L.logOn)
  else
    title:SetText(L.logOff)
  end
  dot:SetColorTexture(color[1], color[2], color[3], 1)
  detail:SetText(detailText(status))
end

local function savePosition()
  local point, _, relativePoint, x, y = window:GetPoint()
  ns.DB().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function placeWindow()
  local position = ns.DB().position
  window:ClearAllPoints()
  if position then
    window:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
  else
    window:SetPoint("TOP", UIParent, "TOP", 0, -60)
  end
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("reforge Companion", 0.95, 0.48, 0.17)
  GameTooltip:AddLine(L.tipAuto:format(ns.STOP_GRACE / 60), 1, 1, 1, true)
  GameTooltip:AddLine(L.tipClick)
  GameTooltip:AddLine(L.tipRight)
  if not ns.DB().locked then
    GameTooltip:AddLine(L.tipDrag)
  end
  GameTooltip:Show()
end

function ns.CreateWindow()
  window = CreateFrame("Button", "ReforgeCompanionWindow", UIParent, "BackdropTemplate")
  window:SetSize(150, 36)
  window:SetClampedToScreen(true)
  window:SetMovable(true)
  window:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  window:SetBackdropColor(0.05, 0.06, 0.08, 0.85)
  window:SetBackdropBorderColor(0.3, 0.33, 0.38, 1)

  dot = window:CreateTexture(nil, "ARTWORK")
  dot:SetSize(8, 8)
  dot:SetPoint("LEFT", window, "LEFT", 10, 0)

  title = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  title:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -7)
  title:SetPoint("RIGHT", window, "RIGHT", -6, 0)
  title:SetJustifyH("LEFT")

  detail = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  detail:SetPoint("RIGHT", window, "RIGHT", -6, 0)
  detail:SetJustifyH("LEFT")

  window:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.SetAuto(not ns.DB().auto)
    else
      ns.Toggle()
    end
    ns.RefreshWindow()
  end)
  window:SetScript("OnDragStart", function(self)
    if not ns.DB().locked then
      self:StartMoving()
    end
  end)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  window:SetScript("OnEnter", showTooltip)
  window:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  placeWindow()
  window:SetShown(ns.DB().shown)
  ns.RefreshWindow()
end

local function setShown(shown)
  ns.DB().shown = shown
  window:SetShown(shown)
end

-- Eintrag im Addon-Menue der Minimap (siehe .toc).
function ReforgeCompanion_OnAddonCompartmentClick()
  setShown(not ns.DB().shown)
end

SLASH_REFORGECOMPANION1 = "/reforge"
SLASH_REFORGECOMPANION2 = "/rfc"
SlashCmdList.REFORGECOMPANION = function(input)
  local command = (input or ""):lower():match("^%s*(%S*)")
  local status = ns.Status()
  if command == "start" then
    if status.state == "off" then
      ns.Toggle()
    end
  elseif command == "stop" then
    if status.state == "on" then
      ns.Toggle()
    end
  elseif command == "auto" then
    ns.SetAuto(not ns.DB().auto)
  elseif command == "lock" then
    ns.DB().locked = not ns.DB().locked
    ns.Print(ns.DB().locked and L.locked or L.unlocked)
  elseif command == "show" then
    setShown(true)
  elseif command == "hide" then
    setShown(false)
    ns.Print(L.hidden)
  elseif command == "reset" then
    ns.DB().position = nil
    placeWindow()
    setShown(true)
    ns.Print(L.position)
  else
    ns.Print(L.help)
  end
  ns.RefreshWindow()
end
