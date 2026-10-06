-- Classic-family native Auction House tabs and the shared sidecar.
local AH = MarketSync and MarketSync.AuctionHouse
if not AH then return end
local modernShowPanel = AH.ShowAuctionHousePanel

local function HidePanels()
    for _, host in pairs(AH.LegacyHosts or {}) do host:Hide() end
end

local function SidecarFor(kind)
    if MarketSync.AHSidecar and MarketSync.AHSidecar.SetVisibleForAH then
        MarketSync.AHSidecar.SetVisibleForAH(kind == "search" or kind == "scanner" or kind == "native")
        if kind == "native" and MarketSync.AHSidecar.SetMode then
            local selected = AuctionFrame and PanelTemplates_GetSelectedTab
                and PanelTemplates_GetSelectedTab(AuctionFrame)
            local auctionatorSell = _G.AuctionatorTabs_Selling
            MarketSync.AHSidecar.SetMode((selected == 3
                or (auctionatorSell and selected == auctionatorSell:GetID())) and "sell" or "lists")
        end
    end
end

function AH.AttachLegacy()
    if AH.LegacyAttached then return true end
    if not (MarketSync.Scanner and MarketSync.Scanner.IsLegacyAH) then return false end
    local auctionFrame = _G.AuctionFrame
    if not auctionFrame or not auctionFrame.numTabs then return false end
    local factories = {
        search = MarketSync.CreateLegacySearchPanel,
        scanner = MarketSync.CreateAHScannerPanel,
        processing = MarketSync.CreateProcessingPanel,
        alerts = MarketSync.CreateNotificationsPanel,
        analytics = MarketSync.CreateAnalyticsPanel,
    }
    if not factories.search or not factories.scanner then return false end

    local hosts, tabs = {}, {}
    AH.LegacyHosts, AH.LegacyTabs = hosts, tabs
    local function MakeHost(factory)
        local host = CreateFrame("Frame", nil, auctionFrame)
        host:SetPoint("TOPLEFT", auctionFrame, "TOPLEFT", 12, -38)
        host:SetPoint("BOTTOMRIGHT", auctionFrame, "BOTTOMRIGHT", -12, 32)
        host:SetFrameLevel(auctionFrame:GetFrameLevel() + 10)
        host.Content = factory(host)
        host:SetScript("OnShow", function()
            if MarketSync.MainFrame and MarketSync.MainFrame:IsShown() then MarketSync.MainFrame:Hide() end
            local content = host.Content
            if content then
                if content.Show then content:Show() end
                if content.OnShow then content.OnShow(content) end
            end
        end)
        host:Hide()
        return host
    end

    local order = {
        { kind = "search", label = "Search" },
        { kind = "scanner", label = "Scan" },
        { kind = "processing", label = "Process" },
        { kind = "alerts", label = "Alerts" },
        { kind = "analytics", label = "Analytics" },
    }
    for _, entry in ipairs(order) do
        if factories[entry.kind] then
            hosts[entry.kind] = MakeHost(factories[entry.kind])
            local index = auctionFrame.numTabs + 1
            local tab = CreateFrame("Button", "AuctionFrameTab" .. index, auctionFrame, "AuctionTabTemplate")
            tab:SetID(index)
            tab:SetText(entry.label)
            tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (index - 1)], "RIGHT", -15, 0)
            PanelTemplates_SetNumTabs(auctionFrame, index)
            if PanelTemplates_EnableTab then PanelTemplates_EnableTab(auctionFrame, index) end
            if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
            tabs[entry.kind] = tab
        end
    end
    AH.LegacySearchTab, AH.LegacyScannerTab = tabs.search, tabs.scanner
    AH.LegacySearchHost, AH.LegacyScannerHost = hosts.search, hosts.scanner
    AH.LegacyScannerPanel = hosts.scanner and hosts.scanner.Content
    AH.LegacyAnalyticsPanel = hosts.analytics and hosts.analytics.Content

    local function Select(kind)
        if not auctionFrame:IsShown() or not tabs[kind] then return false end
        HidePanels()
        if type(AuctionFrameTab_OnClick) == "function" then AuctionFrameTab_OnClick(tabs[kind]) end
        hosts[kind]:Show()
        SidecarFor(kind)
        return true
    end
    AH.ShowLegacyPanel = Select
    for kind, tab in pairs(tabs) do
        tab:SetScript("OnClick", function() Select(kind) end)
    end

    function AH.RefreshTabVisibility()
        local useAuctionator = MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true
            and Auctionator and Auctionator.Database
        local visible = {
            search = true,
            scanner = not useAuctionator,
            processing = MarketSyncDB and MarketSyncDB.EnableProcessingTab == true,
            alerts = MarketSyncDB and MarketSyncDB.EnableAlertsTab == true,
            analytics = not MarketSyncDB or MarketSyncDB.EnableAnalyticsTab ~= false,
        }
        local firstTab = tabs.search
        local previous = firstTab and _G["AuctionFrameTab" .. (firstTab:GetID() - 1)]
            or _G.AuctionFrameTab3
        for _, entry in ipairs(order) do
            local tab = tabs[entry.kind]
            if tab then
                if visible[entry.kind] then
                    tab:ClearAllPoints()
                    tab:SetPoint("LEFT", previous, "RIGHT", -15, 0)
                    tab:Show()
                    previous = tab
                else
                    if hosts[entry.kind] and hosts[entry.kind]:IsShown() then Select("search") end
                    tab:Hide()
                end
            end
        end
    end
    AH.RefreshTabVisibility()

    if type(hooksecurefunc) == "function" and type(AuctionFrameTab_OnClick) == "function" then
        hooksecurefunc("AuctionFrameTab_OnClick", function(tab)
            for kind, ownTab in pairs(tabs) do
                if tab == ownTab then
                    HidePanels()
                    SidecarFor(kind)
                    return
                end
            end
            HidePanels()
            SidecarFor("native")
        end)
    end
    if MarketSync.CreateAHSidecar then
        AH.Sidecar = MarketSync.CreateAHSidecar(auctionFrame)
        SidecarFor("native")
    end
    auctionFrame:HookScript("OnHide", function()
        HidePanels()
        if MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auction House closed")
        end
    end)
    AH.LegacyAttached = true
    return true
end

function AH.ShowAuctionHousePanel(targetTab)
    if MarketSync.Scanner and MarketSync.Scanner.IsLegacyAH then
        if not AH.AttachLegacy() then return false end
        local kind = type(targetTab) == "string" and targetTab:lower() or "scanner"
        return AH.ShowLegacyPanel(kind)
    end
    return modernShowPanel and modernShowPanel(targetTab) or false
end

MarketSync.OpenLegacySearch = function(query)
    if not AH.AttachLegacy() then return false end
    if type(query) == "number" and MarketSync.GetItemInfo then query = MarketSync.GetItemInfo(query) end
    if type(query) ~= "string" or query == "" then return false end
    query = query:match("%[(.-)%]") or query
    if AH.LegacySearchHost.Content and AH.LegacySearchHost.Content.SetQuery then
        AH.LegacySearchHost.Content:SetQuery(query)
    end
    if not AH.ShowLegacyPanel("search") then return false end
    return MarketSync.Scanner.StartLiveSearch(query)
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("AUCTION_HOUSE_SHOW")
listener:RegisterEvent("ADDON_LOADED")
listener:SetScript("OnEvent", function(_, event, name)
    if event == "AUCTION_HOUSE_SHOW" or (event == "ADDON_LOADED" and name == "Blizzard_AuctionUI") then
        AH.AttachLegacy()
    end
end)
