-- GPL-3.0-or-later. First milestone: a launcher beside the native auction tabs.
-- This opens the shared portable scanner; an embedded settings/alerts pane is a later phase.
local S = MarketSyncForeverScanner

function S.AttachAuctionHouseEntry()
  local frame = AuctionHouseFrame
  if not S.Ready or not frame or not frame.AuctionsTab or type(frame.Tabs) ~= "table"
    or #frame.Tabs == 0 then return false end
  if S.AuctionHouseEntry then return true end

  local lastTab = frame.Tabs[#frame.Tabs]
  local entry = CreateFrame("Button", "MarketSyncForeverAuctionHouseEntry", frame, "AuctionHouseFrameTabTemplate")
  entry:SetText("MarketSync")
  -- Creation may occur while the parent is already shown; resize after setting the label.
  if PanelTemplates_TabResize then PanelTemplates_TabResize(entry, 20, nil, 70) end
  entry:SetPoint("LEFT", lastTab, "RIGHT", -15, 0)
  entry:SetScript("OnClick", function() S.ShowWindow() end)
  if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(entry) end
  -- The native Tabs array and display-mode selection remain managed by Blizzard.
  S.AuctionHouseEntry = entry
  return true
end
