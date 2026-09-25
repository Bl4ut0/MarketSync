-- ================================================================
-- MarketSync - Embedded Auction House Tab & Lifecycle
-- Hooks AuctionHouseFrame to add MarketSync directly into the native AH
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.AuctionHouse = MarketSync.AuctionHouse or {}

local AH = MarketSync.AuctionHouse

function AH.RefreshTabVisibility()
    -- Stub until attached to AuctionHouseFrame
end

local function GetBuyFrameItem(buyFrame)
    if not buyFrame then return nil, nil, nil end
    local itemKey = buyFrame.GetItemKey and buyFrame:GetItemKey()
    local itemLink = nil
    local itemID = nil
    if buyFrame.BuyDisplay and buyFrame.BuyDisplay.ItemDisplay then
        local disp = buyFrame.BuyDisplay.ItemDisplay
        itemLink = disp.itemLink
        itemKey = itemKey or disp.itemKey
        itemID = disp.itemID or (itemKey and itemKey.itemID)
    elseif buyFrame.ItemDisplay then
        local disp = buyFrame.ItemDisplay
        itemLink = disp.itemLink
        itemKey = itemKey or disp.itemKey
        itemID = disp.itemID or (itemKey and itemKey.itemID)
    end
    if not itemID and itemKey and itemKey.itemID then
        itemID = itemKey.itemID
    end
    if not itemLink and itemID then
        if C_Item and C_Item.GetItemInfo then
            itemLink = select(2, C_Item.GetItemInfo(itemID))
        elseif GetItemInfo then
            itemLink = select(2, GetItemInfo(itemID))
        end
        itemLink = itemLink or ("item:" .. itemID)
    end
    return itemID, itemLink, itemKey
end

local function AttachBuyAnalyticsButton(buyFrame, btnName)
    if not buyFrame or buyFrame[btnName] then return end
    local btn = CreateFrame("Button", btnName, buyFrame, "UIPanelButtonTemplate")
    btn:SetSize(110, 22)
    btn:SetText("View Analytics")
    -- Keep this action in the buy-frame navigation row. The old top-right
    -- anchor covered the commodity list's "Available" column header.
    if buyFrame.BackButton then
        btn:SetPoint("LEFT", buyFrame.BackButton, "RIGHT", 8, 0)
    else
        btn:SetPoint("TOPLEFT", buyFrame, "TOPLEFT", 129, -9)
    end
    btn:SetScript("OnClick", function()
        local itemID, itemLink = GetBuyFrameItem(buyFrame)
        if itemID or itemLink then
            MarketSync.ShowAnalytics(itemID or itemLink, itemLink)
        end
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btn, {
            name = "View Analytics",
            context = "Button",
            description = "Open price history and analytics for this item",
        })
    end
    buyFrame[btnName] = btn
end

function AH.ShowAuctionHousePanel(targetTab)
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return false end
    if not AH.Attach() then return false end
    if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
        MarketSync.MainFrame:Hide()
    end
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
    if AH.ScannerPanel then
        AH.ScannerPanel:Hide()
        if AH.ScannerPanel.Content and AH.ScannerPanel.Content.Hide then AH.ScannerPanel.Content:Hide() end
    end
    if AH.ProcessingPanel then
        AH.ProcessingPanel:Hide()
        if AH.ProcessingPanel.Content and AH.ProcessingPanel.Content.Hide then AH.ProcessingPanel.Content:Hide() end
    end
    if AH.AlertsPanel then
        AH.AlertsPanel:Hide()
        if AH.AlertsPanel.Content and AH.AlertsPanel.Content.Hide then AH.AlertsPanel.Content:Hide() end
    end
    if AH.AnalyticsPanel then
        AH.AnalyticsPanel:Hide()
        if AH.AnalyticsPanel.Content and AH.AnalyticsPanel.Content.Hide then AH.AnalyticsPanel.Content:Hide() end
    end
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
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if AH.Sidecar and (MarketSyncDB == nil or MarketSyncDB.AHSidecarExpanded ~= false) then
            AH.Sidecar:Show()
        end
        if panelScanner.Content then
            if panelScanner.Content.Show then panelScanner.Content:Show() end
            local onShow = panelScanner.Content.OnShow or (panelScanner.Content.GetScript and panelScanner.Content:GetScript("OnShow"))
            if onShow then
                onShow(panelScanner.Content)
            end
        end
    end)
    panelScanner:SetScript("OnHide", function()
        if panelScanner.Content and panelScanner.Content.Hide then
            panelScanner.Content:Hide()
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
    panelProcessing:SetScript("OnShow", function()
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if AH.Sidecar and AH.Sidecar.Hide then
            AH.Sidecar:Hide()
        end
        if panelProcessing.Content then
            if panelProcessing.Content.Show then panelProcessing.Content:Show() end
            local onShow = panelProcessing.Content.OnShow or (panelProcessing.Content.GetScript and panelProcessing.Content:GetScript("OnShow"))
            if onShow then
                onShow(panelProcessing.Content)
            end
        end
    end)
    panelProcessing:SetScript("OnHide", function()
        if panelProcessing.Content and panelProcessing.Content.Hide then
            panelProcessing.Content:Hide()
        end
    end)

    -- 3. Alerts Panel Container
    local panelAlerts = CreateFrame("Frame", "MarketSyncAHAlertsPanel", frame)
    panelAlerts:Hide()
    panelAlerts:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panelAlerts:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    AH.AlertsPanel = panelAlerts

    if MarketSync.CreateNotificationsPanel then
        panelAlerts.Content = MarketSync.CreateNotificationsPanel(panelAlerts)
    end
    panelAlerts:SetScript("OnShow", function()
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if AH.Sidecar and AH.Sidecar.Hide then
            AH.Sidecar:Hide()
        end
        if panelAlerts.Content then
            if panelAlerts.Content.Show then panelAlerts.Content:Show() end
            local onShow = panelAlerts.Content.OnShow or (panelAlerts.Content.GetScript and panelAlerts.Content:GetScript("OnShow"))
            if onShow then
                onShow(panelAlerts.Content)
            end
        end
    end)
    panelAlerts:SetScript("OnHide", function()
        if panelAlerts.Content and panelAlerts.Content.Hide then
            panelAlerts.Content:Hide()
        end
    end)

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
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if AH.Sidecar and AH.Sidecar.Hide then
            AH.Sidecar:Hide()
        end
        if panelAnalytics.Content then
            if panelAnalytics.Content.Show then panelAnalytics.Content:Show() end
            local onShow = panelAnalytics.Content.OnShow or (panelAnalytics.Content.GetScript and panelAnalytics.Content:GetScript("OnShow"))
            if onShow then
                onShow(panelAnalytics.Content)
            end

            -- Auto-load active item from BuyFrame or SearchBox if user navigated to Analytics
            local activeID, activeLink = nil, nil
            if frame.CommoditiesBuyFrame and frame.CommoditiesBuyFrame:IsShown() then
                activeID, activeLink = GetBuyFrameItem(frame.CommoditiesBuyFrame)
            elseif frame.ItemBuyFrame and frame.ItemBuyFrame:IsShown() then
                activeID, activeLink = GetBuyFrameItem(frame.ItemBuyFrame)
            end
            if activeID or activeLink then
                if panelAnalytics.Content.ShowItem then
                    panelAnalytics.Content:ShowItem(activeID or activeLink, activeLink)
                end
            elseif frame.SearchBar and frame.SearchBar.SearchBox then
                local txt = frame.SearchBar.SearchBox:GetText()
                if txt and txt ~= "" and panelAnalytics.Content.SelectByNameOrQuery then
                    panelAnalytics.Content:SelectByNameOrQuery(txt)
                end
            end
        end
    end)
    panelAnalytics:SetScript("OnHide", function()
        if panelAnalytics.Content and panelAnalytics.Content.Hide then
            panelAnalytics.Content:Hide()
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

        if MarketSync.SetAccessibility then
            local customTabs = {
                { btn = AH.ScannerTab, name = "Scanner", desc = "MarketSync Auction House scanner panel" },
                { btn = AH.ProcessingTab, name = "Processing", desc = "MarketSync crafting and disenchanting profitability panel" },
                { btn = AH.AlertsTab, name = "Alerts", desc = "MarketSync market deal alerts and notification panel" },
                { btn = AH.AnalyticsTab, name = "Analytics", desc = "MarketSync price history and item tracking analytics" },
            }
            local baseCount = (frame.Tabs and #frame.Tabs or 0)
            local totalAH = baseCount + #customTabs
            for i, tabInfo in ipairs(customTabs) do
                if tabInfo.btn then
                    MarketSync.SetAccessibility(tabInfo.btn, {
                        name = tabInfo.name,
                        context = "Tab",
                        description = tabInfo.desc,
                        getIndexInfo = function()
                            return { index = baseCount + i, total = totalAH }
                        end,
                        tooltipTitle = tabInfo.name .. " Tab",
                        tooltipText = tabInfo.desc,
                    })
                end
            end
        end
    end

    -- Dynamically re-anchor visible LibAHTab tabs cleanly without gaps
    function AH.RefreshTabVisibility()
        local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
        if not libAHTab or not libAHTab.internalState or not libAHTab.internalState.rootFrame then return end

        local offsetX = (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE) and -14 or 3
        local useAuctionatorScan = MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true
            and Auctionator and Auctionator.Database
        local tabConfigs = {
            { id = "MarketSyncScanner", btn = AH.ScannerTab, enabled = not useAuctionatorScan },
            { id = "MarketSyncProcessing", btn = AH.ProcessingTab, enabled = (MarketSyncDB and MarketSyncDB.EnableProcessingTab == true) },
            { id = "MarketSyncAlerts", btn = AH.AlertsTab, enabled = (MarketSyncDB and MarketSyncDB.EnableAlertsTab == true) },
            { id = "MarketSyncAnalytics", btn = AH.AnalyticsTab, enabled = (MarketSyncDB and MarketSyncDB.EnableAnalyticsTab ~= false) },
        }

        local lastVisible = nil
        local firstVisibleID = nil
        local activeWasHidden = false

        for _, cfg in ipairs(tabConfigs) do
            local btn = cfg.btn or (libAHTab.GetButton and libAHTab:GetButton(cfg.id))
            if btn then
                if cfg.enabled then
                    firstVisibleID = firstVisibleID or cfg.id
                    if btn.ClearAllPoints then btn:ClearAllPoints() end
                    if not lastVisible then
                        btn:SetPoint("TOPLEFT", libAHTab.internalState.rootFrame, "TOPLEFT", offsetX, 0)
                    else
                        btn:SetPoint("TOPLEFT", lastVisible, "TOPRIGHT", offsetX, 0)
                    end
                    btn:Show()
                    lastVisible = btn
                else
                    if btn.frameRef and btn.frameRef:IsShown() then
                        activeWasHidden = true
                        btn.frameRef:Hide()
                    end
                    if PanelTemplates_DeselectTab then
                        PanelTemplates_DeselectTab(btn)
                    end
                    btn:Hide()
                end
            end
        end

        if activeWasHidden then
            if firstVisibleID and libAHTab:DoesIDExist(firstVisibleID) then
                libAHTab:SetSelected(firstVisibleID)
            elseif frame and frame.Tabs and frame.Tabs[1] then
                frame.Tabs[1]:Click()
            end
        end
    end

    if AH.RefreshTabVisibility then
        AH.RefreshTabVisibility()
    end

    -- Attach MarketSync Breakout Sidecar to AuctionHouseFrame
    if MarketSync.CreateAHSidecar then
        AH.Sidecar = MarketSync.CreateAHSidecar(frame)
    end

    -- Attach Buy Analytics buttons to Commodities and Item buy frames
    if frame.CommoditiesBuyFrame then
        AttachBuyAnalyticsButton(frame.CommoditiesBuyFrame, "MarketSyncCommoditiesAnalyticsBtn")
    end
    if frame.ItemBuyFrame then
        AttachBuyAnalyticsButton(frame.ItemBuyFrame, "MarketSyncItemAnalyticsBtn")
    end

    -- Hook display mode switching
    hooksecurefunc(frame, "SetDisplayMode", function()
        local currentMode = frame:GetDisplayMode()
        local isBlizzardBuy = frame.Tabs and frame.Tabs[1] and currentMode == frame.Tabs[1].displayMode
        local isBlizzardSell = frame.Tabs and frame.Tabs[2] and currentMode == frame.Tabs[2].displayMode

        if isBlizzardBuy or isBlizzardSell then
            if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
                MarketSync.MainFrame:Hide()
            end
            if AH.Sidecar and (MarketSyncDB == nil or MarketSyncDB.AHSidecarExpanded ~= false) then
                AH.Sidecar:Show()
            end
            if MarketSync.AHSidecar and MarketSync.AHSidecar.SetMode then
                if isBlizzardSell then
                    MarketSync.AHSidecar.SetMode("sell")
                else
                    MarketSync.AHSidecar.SetMode("lists")
                end
            end
            if frame.CommoditiesBuyFrame then
                AttachBuyAnalyticsButton(frame.CommoditiesBuyFrame, "MarketSyncCommoditiesAnalyticsBtn")
            end
            if frame.ItemBuyFrame then
                AttachBuyAnalyticsButton(frame.ItemBuyFrame, "MarketSyncItemAnalyticsBtn")
            end
        end
    end)

    frame:HookScript("OnShow", function()
        MarketSync.IsAuctionHouseOpen = true
        if AH.RefreshTabVisibility then
            AH.RefreshTabVisibility()
        end
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if frame.CommoditiesBuyFrame then
            AttachBuyAnalyticsButton(frame.CommoditiesBuyFrame, "MarketSyncCommoditiesAnalyticsBtn")
        end
        if frame.ItemBuyFrame then
            AttachBuyAnalyticsButton(frame.ItemBuyFrame, "MarketSyncItemAnalyticsBtn")
        end
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetExpanded then
            local expanded = (MarketSyncDB and MarketSyncDB.AHSidecarExpanded ~= nil) and MarketSyncDB.AHSidecarExpanded or true
            MarketSync.AHSidecar.SetExpanded(expanded)
        end
    end)

    frame:HookScript("OnHide", function()
        if panelScanner.Content and panelScanner.Content.Hide then panelScanner.Content:Hide() end
        panelScanner:Hide()
        if panelProcessing.Content and panelProcessing.Content.Hide then panelProcessing.Content:Hide() end
        panelProcessing:Hide()
        if panelAlerts.Content and panelAlerts.Content.Hide then panelAlerts.Content:Hide() end
        panelAlerts:Hide()
        if panelAnalytics.Content and panelAnalytics.Content.Hide then panelAnalytics.Content:Hide() end
        panelAnalytics:Hide()
        if AH.Sidecar and AH.Sidecar.Hide then
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
