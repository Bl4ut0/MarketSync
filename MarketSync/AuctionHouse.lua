-- ================================================================
-- MarketSync - Auction House Tabs & Lifecycle (shared core)
-- This file owns the single entry points for the native Auction House
-- integration. Retail (AuctionHouseFrame, LibAHTab tabs) is built here.
-- Classic-family clients (AuctionFrame) are built in LegacyAuctionHouse.lua.
-- Both read the same tab-visibility table and use the same dispatchers.
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.AuctionHouse = MarketSync.AuctionHouse or {}

local AH = MarketSync.AuctionHouse

-- True on Classic-family clients, where the native frame is AuctionFrame.
function AH.IsLegacyClient()
    return (MarketSync.Scanner and MarketSync.Scanner.IsLegacyAH) and true or false
end

-- Single source of truth for which MarketSync tabs are enabled. Both tab
-- strips read this, so the two clients cannot drift apart.
function AH.TabVisibility()
    local db = MarketSyncDB or {}
    local useAuctionatorScan = db.UseAuctionatorScanner == true
        and Auctionator ~= nil and Auctionator.Database ~= nil
    return {
        search = true,
        scanner = not useAuctionatorScan,
        processing = db.EnableProcessingTab == true,
        alerts = db.EnableAlertsTab == true,
        analytics = db.EnableAnalyticsTab ~= false,
    }
end

-- Shared entry point for every caller. Refreshes whichever tab strip is
-- attached for this client. Attach functions call their own refresh directly
-- because they run before the attached flags are set.
function AH.RefreshTabVisibility()
    if AH.LegacyAttached and AH.RefreshLegacyTabs then
        return AH.RefreshLegacyTabs()
    end
    if AH.Attached and AH.RefreshModernTabs then
        return AH.RefreshModernTabs()
    end
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

-- Shows a retail panel. Classic clients go through AH.ShowAuctionHousePanel.
local function ShowModernPanel(targetTab)
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

-- The one public entry point for opening an Auction House panel. It picks
-- the native frame for this client. Callers never reassign these functions.
function AH.ShowAuctionHousePanel(targetTab)
    if AH.IsLegacyClient() then
        if not AH.AttachLegacy() then return false end
        local kind = type(targetTab) == "string" and targetTab:lower() or "scanner"
        return AH.ShowLegacyPanel(kind)
    end
    return ShowModernPanel(targetTab)
end

-- Builds a hidden panel anchored to the retail AH frame, leaving the native
-- footer visible.
local function CreateTabPanel(frame, name)
    local panel = CreateFrame("Frame", name, frame)
    panel:Hide()
    local footer = frame.MoneyFrameBorder
    if footer then
        -- Blizzard anchors Sell and Auctions two pixels above the money border.
        panel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -34)
        panel:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 7, 2)
        panel.MarketSyncNativeAuctionFooter = true
    else
        panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    end
    return panel
end

-- Builds one retail panel. Showing it hides the MarketSync main window, sets
-- the breakout sidecar, and shows its content. afterShow (optional) runs
-- after the content has been shown.
local function BuildModernPanel(frame, name, factory, sidecarVisible, afterShow)
    local panel = CreateTabPanel(frame, name)
    if factory then
        panel.Content = factory(panel)
    end
    panel:SetScript("OnShow", function()
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetVisibleForAH then
            MarketSync.AHSidecar.SetVisibleForAH(sidecarVisible)
        end
        local content = panel.Content
        if content then
            if content.Show then content:Show() end
            local onShow = content.OnShow or (content.GetScript and content:GetScript("OnShow"))
            if onShow then
                onShow(content)
            end
            if afterShow then afterShow(content) end
        end
    end)
    panel:SetScript("OnHide", function()
        if panel.Content and panel.Content.Hide then
            panel.Content:Hide()
        end
    end)
    return panel
end

function AH.Attach()
    local frame = AuctionHouseFrame
    if not frame or not frame.AuctionsTab or type(frame.Tabs) ~= "table" or #frame.Tabs == 0 then
        return false
    end
    if AH.Attached then return true end

    -- Analytics opened from a buy frame or the search box loads that item.
    local function AutoLoadAnalytics(content)
        local activeID, activeLink = nil, nil
        if frame.CommoditiesBuyFrame and frame.CommoditiesBuyFrame:IsShown() then
            activeID, activeLink = GetBuyFrameItem(frame.CommoditiesBuyFrame)
        elseif frame.ItemBuyFrame and frame.ItemBuyFrame:IsShown() then
            activeID, activeLink = GetBuyFrameItem(frame.ItemBuyFrame)
        end
        if activeID or activeLink then
            if content.ShowItem then
                content:ShowItem(activeID or activeLink, activeLink)
            end
        elseif frame.SearchBar and frame.SearchBar.SearchBox then
            local txt = frame.SearchBar.SearchBox:GetText()
            if txt and txt ~= "" and content.SelectByNameOrQuery then
                content:SelectByNameOrQuery(txt)
            end
        end
    end

    -- The four retail panels. Only the scanner keeps the sidecar visible.
    local panelScanner = BuildModernPanel(frame, "MarketSyncAHScannerPanel", MarketSync.CreateAHScannerPanel, true)
    AH.ScannerPanel = panelScanner
    local panelProcessing = BuildModernPanel(frame, "MarketSyncAHProcessingPanel", MarketSync.CreateProcessingPanel, false)
    AH.ProcessingPanel = panelProcessing
    local panelAlerts = BuildModernPanel(frame, "MarketSyncAHAlertsPanel", MarketSync.CreateNotificationsPanel, false)
    AH.AlertsPanel = panelAlerts
    local panelAnalytics = BuildModernPanel(frame, "MarketSyncAHAnalyticsPanel", MarketSync.CreateAnalyticsPanel, false, AutoLoadAnalytics)
    AH.AnalyticsPanel = panelAnalytics

    -- Register the four tabs via LibAHTab-1-0 (Scanner, Processing, Alerts, Analytics)
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

    -- Re-anchor the visible LibAHTab tabs without gaps.
    AH.RefreshModernTabs = function()
        local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
        if not libAHTab or not libAHTab.internalState or not libAHTab.internalState.rootFrame then return end

        local offsetX = (WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE) and -14 or 3
        local visible = AH.TabVisibility()
        local tabConfigs = {
            { id = "MarketSyncScanner", btn = AH.ScannerTab, enabled = visible.scanner },
            { id = "MarketSyncProcessing", btn = AH.ProcessingTab, enabled = visible.processing },
            { id = "MarketSyncAlerts", btn = AH.AlertsTab, enabled = visible.alerts },
            { id = "MarketSyncAnalytics", btn = AH.AnalyticsTab, enabled = visible.analytics },
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
    AH.RefreshModernTabs()

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

    local function UpdateNativeSidecar()
        local currentMode = frame:GetDisplayMode()
        local sidecar = MarketSync.AHSidecar
        local auctionsMode = frame.AuctionsTab.displayMode or (AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Auctions)
        if auctionsMode and currentMode == auctionsMode then
            if sidecar and sidecar.SetVisibleForAH then sidecar.SetVisibleForAH(false) end
            return
        end
        local isBlizzardBuy = frame.Tabs and frame.Tabs[1] and currentMode == frame.Tabs[1].displayMode
        local isBlizzardSell = frame.Tabs and frame.Tabs[2] and currentMode == frame.Tabs[2].displayMode

        if isBlizzardBuy or isBlizzardSell then
            if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
                MarketSync.MainFrame:Hide()
            end
            if sidecar and sidecar.SetVisibleForAH then sidecar.SetVisibleForAH(frame:IsShown()) end
            if sidecar and sidecar.SetMode then sidecar.SetMode(isBlizzardSell and "sell" or "lists") end
            if frame.CommoditiesBuyFrame then
                AttachBuyAnalyticsButton(frame.CommoditiesBuyFrame, "MarketSyncCommoditiesAnalyticsBtn")
            end
            if frame.ItemBuyFrame then
                AttachBuyAnalyticsButton(frame.ItemBuyFrame, "MarketSyncItemAnalyticsBtn")
            end
        end
    end
    hooksecurefunc(frame, "SetDisplayMode", UpdateNativeSidecar)
    if frame:IsShown() then UpdateNativeSidecar() end

    frame:HookScript("OnShow", function()
        MarketSync.IsAuctionHouseOpen = true
        AH.RefreshTabVisibility()
        if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Hide()
        end
        if frame.CommoditiesBuyFrame then
            AttachBuyAnalyticsButton(frame.CommoditiesBuyFrame, "MarketSyncCommoditiesAnalyticsBtn")
        end
        if frame.ItemBuyFrame then
            AttachBuyAnalyticsButton(frame.ItemBuyFrame, "MarketSyncItemAnalyticsBtn")
        end
        UpdateNativeSidecar()
    end)

    frame:HookScript("OnHide", function()
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetVisibleForAH then
            MarketSync.AHSidecar.SetVisibleForAH(false)
        end
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

-- One listener for both clients. Each attach function returns false on the
-- client it does not apply to, so a single event can safely call both.
local ahLoader = CreateFrame("Frame")
pcall(ahLoader.RegisterEvent, ahLoader, "ADDON_LOADED")
pcall(ahLoader.RegisterEvent, ahLoader, "AUCTION_HOUSE_SHOW")
ahLoader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_AuctionHouseUI" then
            AH.Attach()
        elseif arg1 == "Blizzard_AuctionUI" and AH.AttachLegacy then
            AH.AttachLegacy()
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        MarketSync.IsAuctionHouseOpen = true
        AH.Attach()
        if AH.AttachLegacy then AH.AttachLegacy() end
    end
end)
