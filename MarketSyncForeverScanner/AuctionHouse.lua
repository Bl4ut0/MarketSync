-- GPL-3.0-or-later. Embedded native auction-house tab; no transaction API calls.
local S = MarketSyncForeverScanner
local displayMode = {"MarketSyncForeverPanel"}

function S.HideAuctionHousePanel()
  if S.AuctionHousePanel then S.AuctionHousePanel:Hide() end
end

function S.ShowAuctionHousePanel()
  if not S.IsAuctioneerAvailable() or not AuctionHouseFrame:IsShown()
    or not S.AttachAuctionHouseEntry() then
    S.Status = "Open an auctioneer to use the MarketSync tab"
    S.Notify()
    return false
  end
  AuctionHouseFrame:SetDisplayMode(displayMode)
  S.RefreshMarketBrowsers()
  return true
end

function S.AttachAuctionHouseEntry()
  local frame = AuctionHouseFrame
  if not S.Ready or not frame or not frame.AuctionsTab or type(frame.Tabs) ~= "table"
    or #frame.Tabs == 0 then return false end
  if S.AuctionHouseEntry then return true end
  if type(frame.tabsForDisplayMode) ~= "table" or type(AuctionHouseFrameDisplayMode) ~= "table"
    or type(frame.SetDisplayMode) ~= "function" or type(frame.GetDisplayMode) ~= "function"
    or type(frame.UpdateTitle) ~= "function" or type(hooksecurefunc) ~= "function" then return false end

  local lastTab = frame.Tabs[#frame.Tabs]
  local panel = CreateFrame("Frame", "MarketSyncForeverAuctionHousePanel", frame)
  panel:Hide()
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
  panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
  panel.Browser = S.CreateMarketBrowser(panel, 776, 472, true)
  frame.MarketSyncForeverPanel = panel

  local entry = CreateFrame("Button", "MarketSyncForeverAuctionHouseEntry", frame, "AuctionHouseFrameTabTemplate")
  entry:SetText("MarketSync")
  PanelTemplates_TabResize(entry, 20, nil, 70)
  table.insert(frame.Tabs, entry)
  local tabIndex = #frame.Tabs
  entry:SetID(tabIndex)
  frame.tabsForDisplayMode[displayMode] = tabIndex
  PanelTemplates_SetNumTabs(frame, tabIndex)
  entry:ClearAllPoints()
  entry:SetPoint("LEFT", lastTab, "RIGHT", -15, 0)
  entry:SetScript("OnClick", S.ShowAuctionHousePanel)
  PanelTemplates_DeselectTab(entry)
  S.AuctionHouseEntry, S.AuctionHousePanel = entry, panel
  S.AuctionHouseDisplayMode, S.AuctionHouseTabIndex = displayMode, tabIndex

  -- The local mode list makes Blizzard hide its native subframes on entry.
  -- The post-hook hides our extra panel when Blizzard switches to any other mode.
  -- Do not insert our mode into the global native display-mode definitions.
  hooksecurefunc(frame, "SetDisplayMode", function()
    local selected = frame:GetDisplayMode() == displayMode and S.Ready == true
      and S.AuctioneerOpen == true and frame:IsShown()
    panel:SetShown(selected)
    if selected then frame:SetTitle("MarketSync") end
  end)
  hooksecurefunc(frame, "UpdateTitle", function()
    if frame:GetDisplayMode() == displayMode then frame:SetTitle("MarketSync") end
  end)
  frame:HookScript("OnHide", function()
    panel:Hide()
    S.AuctioneerOpen = false
    S.Cancel("Auctioneer closed; saved prices remain available")
  end)
  PanelTemplates_UpdateTabs(frame)
  return true
end
