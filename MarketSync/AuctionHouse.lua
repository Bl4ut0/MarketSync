-- ================================================================
-- MarketSync - Embedded Auction House Tab & Lifecycle
-- Hooks AuctionHouseFrame to add MarketSync directly into the native AH
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.AuctionHouse = {}

local AH = MarketSync.AuctionHouse
local displayMode = { "MarketSyncPanel" }

function AH.ShowAuctionHousePanel()
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return false end
    if not AH.Attach() then return false end
    AuctionHouseFrame:SetDisplayMode(displayMode)
    if AH.Panel then
        AH.Panel:Show()
    end
    return true
end

function AH.HideAuctionHousePanel()
    if AH.Panel then
        AH.Panel:Hide()
    end
end

function AH.Attach()
    local frame = AuctionHouseFrame
    if not frame or not frame.AuctionsTab or type(frame.Tabs) ~= "table" or #frame.Tabs == 0 then
        return false
    end
    if AH.TabButton and AH.Panel then return true end

    if type(frame.tabsForDisplayMode) ~= "table" or type(frame.SetDisplayMode) ~= "function" then
        return false
    end

    local lastTab = frame.Tabs[#frame.Tabs]
    local panel = CreateFrame("Frame", "MarketSyncAuctionHousePanel", frame)
    panel:Hide()
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    frame.MarketSyncPanel = panel
    AH.Panel = panel

    -- Create Tab Button
    local entry
    local ok, res = pcall(CreateFrame, "Button", "MarketSyncAuctionHouseTab", frame, "AuctionHouseFrameTabTemplate")
    if ok and res then
        entry = res
    else
        entry = CreateFrame("Button", "MarketSyncAuctionHouseTab", frame, "PanelTabButtonTemplate")
    end
    entry:SetText("MarketSync")
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(entry, 20, nil, 70)
    end
    table.insert(frame.Tabs, entry)
    local tabIndex = #frame.Tabs
    entry:SetID(tabIndex)
    frame.tabsForDisplayMode[displayMode] = tabIndex
    PanelTemplates_SetNumTabs(frame, tabIndex)
    entry:ClearAllPoints()
    entry:SetPoint("LEFT", lastTab, "RIGHT", -15, 0)
    entry:SetScript("OnClick", function()
        AH.ShowAuctionHousePanel()
    end)
    PanelTemplates_DeselectTab(entry)
    AH.TabButton = entry

    -- Embed UI Content into AH Panel
    if MarketSync.CreateAHScannerPanel then
        panel.ScannerPanel = MarketSync.CreateAHScannerPanel(panel)
        panel.ScannerPanel:SetAllPoints(panel)
    end

    -- Hook display mode switching
    hooksecurefunc(frame, "SetDisplayMode", function()
        local selected = (frame:GetDisplayMode() == displayMode) and frame:IsShown()
        panel:SetShown(selected)
        if selected then
            frame:SetTitle("MarketSync")
            if panel.ScannerPanel and panel.ScannerPanel.OnShow then
                panel.ScannerPanel:OnShow()
            end
        end
    end)

    hooksecurefunc(frame, "UpdateTitle", function()
        if frame:GetDisplayMode() == displayMode then
            frame:SetTitle("MarketSync")
        end
    end)

    frame:HookScript("OnHide", function()
        panel:Hide()
        MarketSync.IsAuctionHouseOpen = false
        if MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auction House closed")
        end
    end)

    PanelTemplates_UpdateTabs(frame)
    return true
end

-- Hook ADDON_LOADED or AUCTION_HOUSE_SHOW
local ahLoader = CreateFrame("Frame")
pcall(ahLoader.RegisterEvent, ahLoader, "ADDON_LOADED")
pcall(ahLoader.RegisterEvent, ahLoader, "AUCTION_HOUSE_SHOW")
ahLoader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_AuctionHouseUI" then
        AH.Attach()
    elseif event == "AUCTION_HOUSE_SHOW" then
        MarketSync.IsAuctionHouseOpen = true
        AH.Attach()
    end
end)
