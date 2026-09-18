-- ================================================================
-- MarketSync - Embedded Auction House Tab & Lifecycle
-- Hooks AuctionHouseFrame to add MarketSync directly into the native AH
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.AuctionHouse = {}

local AH = MarketSync.AuctionHouse

function AH.ShowAuctionHousePanel(targetTab)
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return false end
    if not AH.Attach() then return false end
    local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
    if libAHTab then
        local tabID = "MarketSyncScanner"
        if targetTab == "processing" or targetTab == "Processing" then
            tabID = "MarketSyncProcessing"
        elseif targetTab == "alerts" or targetTab == "Alerts" then
            tabID = "MarketSyncAlerts"
        elseif targetTab == "analytics" or targetTab == "Analytics" then
            tabID = "MarketSyncAnalytics"
        end
        if libAHTab:DoesIDExist(tabID) then
            libAHTab:SetSelected(tabID)
            return true
        end
    end
    return true
end

function AH.HideAuctionHousePanel()
    if AH.ScannerPanel then AH.ScannerPanel:Hide() end
    if AH.ProcessingPanel then AH.ProcessingPanel:Hide() end
    if AH.AlertsPanel then AH.AlertsPanel:Hide() end
    if AH.AnalyticsPanel then AH.AnalyticsPanel:Hide() end
end

function AH.Attach()
    local frame = AuctionHouseFrame
    if not frame or not frame.AuctionsTab or type(frame.Tabs) ~= "table" or #frame.Tabs == 0 then
        return false
    end
    if AH.Attached then return true end

    -- 1. Scanner Panel Container
    local panelScanner = CreateFrame("Frame", "MarketSyncAHScannerPanel", frame)
    panelScanner:Hide()
    panelScanner:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panelScanner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    AH.ScannerPanel = panelScanner

    if MarketSync.CreateAHScannerPanel then
        panelScanner.Content = MarketSync.CreateAHScannerPanel(panelScanner)
    end
    panelScanner:SetScript("OnShow", function()
        if panelScanner.Content and panelScanner.Content.OnShow then
            panelScanner.Content:OnShow()
        end
    end)

    -- 2. Processing Panel Container
    local panelProcessing = CreateFrame("Frame", "MarketSyncAHProcessingPanel", frame)
    panelProcessing:Hide()
    panelProcessing:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panelProcessing:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    AH.ProcessingPanel = panelProcessing

    if MarketSync.CreateProcessingPanel then
        panelProcessing.Content = MarketSync.CreateProcessingPanel(panelProcessing)
    end

    -- 3. Alerts Panel Container
    local panelAlerts = CreateFrame("Frame", "MarketSyncAHAlertsPanel", frame)
    panelAlerts:Hide()
    panelAlerts:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panelAlerts:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    AH.AlertsPanel = panelAlerts

    if MarketSync.CreateNotificationsPanel then
        panelAlerts.Content = MarketSync.CreateNotificationsPanel(panelAlerts)
    end

    -- 4. Analytics Panel Container
    local panelAnalytics = CreateFrame("Frame", "MarketSyncAHAnalyticsPanel", frame)
    panelAnalytics:Hide()
    panelAnalytics:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panelAnalytics:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    AH.AnalyticsPanel = panelAnalytics

    if MarketSync.CreateAnalyticsPanel then
        panelAnalytics.Content = MarketSync.CreateAnalyticsPanel(panelAnalytics)
    end
    panelAnalytics:SetScript("OnShow", function()
        if panelAnalytics.Content and panelAnalytics.Content.OnShow then
            panelAnalytics.Content:OnShow()
        end
    end)

    -- Register 4 tabs via LibAHTab-1-0 (Scanner, Processing, Alerts, Analytics)
    local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
    if libAHTab then
        if not libAHTab:DoesIDExist("MarketSyncScanner") then
            libAHTab:CreateTab("MarketSyncScanner", panelScanner, "Scanner", "MarketSync Scanner")
        end
        if not libAHTab:DoesIDExist("MarketSyncProcessing") then
            libAHTab:CreateTab("MarketSyncProcessing", panelProcessing, "Processing", "MarketSync Processing")
        end
        if not libAHTab:DoesIDExist("MarketSyncAlerts") then
            libAHTab:CreateTab("MarketSyncAlerts", panelAlerts, "Alerts", "MarketSync Alerts")
        end
        if not libAHTab:DoesIDExist("MarketSyncAnalytics") then
            libAHTab:CreateTab("MarketSyncAnalytics", panelAnalytics, "Analytics", "MarketSync Analytics & Tracking")
        end
        AH.ScannerTab = libAHTab:GetButton("MarketSyncScanner")
        AH.ProcessingTab = libAHTab:GetButton("MarketSyncProcessing")
        AH.AlertsTab = libAHTab:GetButton("MarketSyncAlerts")
        AH.AnalyticsTab = libAHTab:GetButton("MarketSyncAnalytics")
    end

    -- Attach MarketSync Breakout Sidecar to AuctionHouseFrame
    if MarketSync.CreateAHSidecar then
        AH.Sidecar = MarketSync.CreateAHSidecar(frame)
    end

    -- Hook display mode switching
    hooksecurefunc(frame, "SetDisplayMode", function()
        -- Auto-switch sidecar view depending on whether user is browsing or selling
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetMode then
            local currentMode = frame:GetDisplayMode()
            if frame.Tabs and frame.Tabs[2] and currentMode == frame.Tabs[2].displayMode then
                MarketSync.AHSidecar.SetMode("sell")
            elseif frame.Tabs and frame.Tabs[1] and currentMode == frame.Tabs[1].displayMode then
                MarketSync.AHSidecar.SetMode("lists")
            end
        end
    end)

    frame:HookScript("OnShow", function()
        MarketSync.IsAuctionHouseOpen = true
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetExpanded then
            local expanded = (MarketSyncDB and MarketSyncDB.AHSidecarExpanded ~= nil) and MarketSyncDB.AHSidecarExpanded or true
            MarketSync.AHSidecar.SetExpanded(expanded)
        end
    end)

    frame:HookScript("OnHide", function()
        panelScanner:Hide()
        panelProcessing:Hide()
        panelAlerts:Hide()
        panelAnalytics:Hide()
        if AH.Sidecar then
            AH.Sidecar:Hide()
        end
        MarketSync.IsAuctionHouseOpen = false
        if MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auction House closed")
        end
    end)

    AH.Attached = true
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
