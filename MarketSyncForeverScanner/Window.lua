-- GPL-3.0-or-later. Portable form of the same browser used inside the auction house.
local S = MarketSyncForeverScanner
local window

S.RefreshWindow = S.RefreshMarketBrowsers

local function CreateWindow()
  window = CreateFrame("Frame", "MarketSyncForeverScannerWindow", UIParent, "PortraitFrameTemplate")
  window:Hide()
  window:SetSize(880, 572)
  window:SetPoint("CENTER")
  window:SetFrameStrata("DIALOG")
  window:SetClampedToScreen(true)
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:SetTitle("MarketSync Forever - Saved Auction Data")
  window:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_01")
  window.Browser = S.CreateMarketBrowser(window, 856, 522, false)
  window.Browser:ClearAllPoints()
  window.Browser:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -34)
  window:SetScript("OnShow", S.RefreshMarketBrowsers)
  table.insert(UISpecialFrames, "MarketSyncForeverScannerWindow")
end

function S.ShowWindow()
  if not window then CreateWindow() end
  window:Show()
  S.RefreshMarketBrowsers()
end

function S.ToggleWindow()
  if not window then S.ShowWindow()
  else window:SetShown(not window:IsShown()) end
end
