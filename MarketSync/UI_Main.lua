-- =============================================================
-- MarketSync - Main Frame
-- Window shell, tabs, and settings
-- =============================================================

local MainFrame, BrowseContent, SyncContent, NeutralContent, ProcessingContent, NotificationsContent, SettingsContent
local ItemHistoryPanel, AnalyticsPanel, ItemDetailPanel
local activeBrowseTab = 1

-- ================================================================
-- HELPER: CreateModernInset
-- Matches Blizzard Auction House sleek dark bronze/stone inset panels
-- ================================================================
function MarketSync.CreateModernInset(parent, x, y, width, height)
    local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    inset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    inset:SetBackdropColor(0.075, 0.070, 0.065, 0.96)
    inset:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.90)

    -- Subtle top inner highlight line matching Blizzard AH insets (warm bronze/gold sheen)
    local topHighlight = inset:CreateTexture(nil, "BORDER")
    topHighlight:SetHeight(1)
    topHighlight:SetPoint("TOPLEFT", 1, -1)
    topHighlight:SetPoint("TOPRIGHT", -1, -1)
    topHighlight:SetColorTexture(0.50, 0.42, 0.25, 0.25)
    inset.topHighlight = topHighlight

    if x and y then
        inset:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if width and height then
        inset:SetSize(width, height)
    end
    return inset
end

-- ================================================================
-- HELPER: CreateAHColumnHeader
-- Matches Blizzard Auction House column headers (clean dark bronze/stone + sort arrow)
-- ================================================================
function MarketSync.CreateAHColumnHeader(parent, width, height, text, sortKey)
    local hdr = CreateFrame("Button", nil, parent, "BackdropTemplate")
    hdr:SetSize(width, height or 20)
    hdr.sortKey = sortKey

    hdr:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    hdr:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    hdr:SetBackdropBorderColor(0.32, 0.28, 0.20, 0.85)

    -- Vertical separator on right side
    local sep = hdr:CreateTexture(nil, "OVERLAY")
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT", 0, -2)
    sep:SetPoint("BOTTOMRIGHT", 0, 2)
    sep:SetColorTexture(0.35, 0.30, 0.20, 0.60)
    hdr.sep = sep

    local label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -15, 0)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(false) end
    label:SetText(text or "")
    hdr.label = label

    local arrow = hdr:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", -4, -1)
    arrow:SetTexCoord(0, 0.5625, 0, 1.0)
    arrow:Hide()
    hdr.arrow = arrow

    hdr:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.24, 0.20, 0.12, 0.95)
    end)
    hdr:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    end)

    return hdr
end

-- ================================================================
-- MAIN FRAME CONSTRUCTION
-- ================================================================
local function CreateMainFrame()
    if MainFrame then return MainFrame end

    -- Ensure Auction House UI is loaded so AuctionHouseFrameDisplayModeTabTemplate and textures are present
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
        if C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_AuctionHouseUI")
        end
    elseif UIParentLoadAddOn and (not IsAddOnLoaded or not IsAddOnLoaded("Blizzard_AuctionHouseUI")) then
        pcall(UIParentLoadAddOn, "Blizzard_AuctionHouseUI")
    end

    -- --- MAIN WINDOW (832 x 447, PortraitFrameTemplate) ---
    local ok, res = pcall(CreateFrame, "Frame", "MarketSyncMainFrame", UIParent, "PortraitFrameTemplate")
    if ok and res then
        MainFrame = res
    else
        MainFrame = CreateFrame("Frame", "MarketSyncMainFrame", UIParent)
    end
    MarketSync.MainFrame = MainFrame
    MainFrame:SetSize(832, 447)
    MainFrame:SetPoint("CENTER")
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
    MainFrame:SetFrameStrata("HIGH")
    MainFrame:SetToplevel(true)
    if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(MainFrame) end

    -- --- PORTRAIT ---
    local portrait = MainFrame.GetPortrait and MainFrame:GetPortrait()
        or (MainFrame.PortraitContainer and MainFrame.PortraitContainer.portrait)
        or _G["MarketSyncMainFramePortrait"]
    if not portrait then
        portrait = MainFrame:CreateTexture(nil, "BACKGROUND")
        portrait:SetSize(60, 60)
        portrait:SetPoint("TOPLEFT", 6, -6)
        local mask = MainFrame:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(58, 58)
        mask:SetPoint("TOPLEFT", 8, -7)
        portrait:AddMaskTexture(mask)
    end
    MainFrame.portrait = portrait

    local function UpdatePortrait()
        if MainFrame.SetPortraitToUnit then
            MainFrame:SetPortraitToUnit("player")
        elseif portrait then
            SetPortraitTexture(portrait, "player")
        end
    end

    local portraitFrame = CreateFrame("Frame", nil, MainFrame)
    portraitFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    portraitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    portraitFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_PORTRAIT_UPDATE" and unit == "player" then
            UpdatePortrait()
        elseif event == "PLAYER_ENTERING_WORLD" then
            UpdatePortrait()
        end
    end)
    MainFrame:HookScript("OnShow", function() UpdatePortrait() end)
    UpdatePortrait()

    -- --- CLOSE BUTTON ---
    local closeBtn = MainFrame.CloseButton or _G["MarketSyncMainFrameCloseButton"]
    if not closeBtn then
        closeBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
    end
    closeBtn:SetScript("OnClick", function()
        MainFrame:Hide()
    end)
    MainFrame.CloseBtn = closeBtn

    -- --- TITLE ---
    local titleText = MainFrame.GetTitleText and MainFrame:GetTitleText()
        or (MainFrame.TitleContainer and MainFrame.TitleContainer.TitleText)
        or _G["MarketSyncMainFrameTitleText"]
    if not titleText then
        titleText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", 0, -18)
    end
    titleText:SetTextColor(1, 0.82, 0)
    titleText:SetText(MarketSync.ADDON_NAME or "MarketSync")
    MainFrame.titleText = titleText

    -- Low RAM Mode: 5-minute idle GC
    local lowRamIdleTicker = nil

    MainFrame:HookScript("OnHide", function()
        if MarketSyncDB and MarketSyncDB.LowRamMode then
            if not lowRamIdleTicker then
                lowRamIdleTicker = C_Timer.NewTicker(300, function()
                    if MainFrame:IsShown() then return end
                    if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
                    if MarketSyncDB.ItemInfoCache then wipe(MarketSyncDB.ItemInfoCache) end
                    collectgarbage("collect")
                    print("|cFF00FF00[MarketSync]|r Low RAM Mode: 5-minute idle reached. Cache cleared and memory recovered.")
                    if lowRamIdleTicker then lowRamIdleTicker:Cancel(); lowRamIdleTicker = nil end
                end, 1) -- Run exactly once after 5 minutes
            end
        end
    end)
    MainFrame:HookScript("OnShow", function()
        if lowRamIdleTicker then
            lowRamIdleTicker:Cancel()
            lowRamIdleTicker = nil
        end
    end)

    local titleHitBox = CreateFrame("Button", nil, MainFrame)
    titleHitBox:SetPoint("CENTER", MainFrame.TitleContainer or titleText, "CENTER")
    titleHitBox:SetHeight(22)
    titleHitBox:SetWidth(300) -- Will be updated dynamically
    titleHitBox:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltipTitle, 1, 0.82, 0)
            GameTooltip:AddLine(self.tooltipText, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
    end)
    titleHitBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    MainFrame.titleHitBox = titleHitBox

    -- --- TITLE BAR SYNC STATUS MONITOR ---
    local syncButton = CreateFrame("Button", nil, MainFrame)
    -- Anchor to the title bar itself, not the template close button (whose
    -- vertical position varies by client and can put the label under content).
    syncButton:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -42, -9)
    syncButton:SetHeight(20)
    syncButton:SetWidth(150)
    local syncFrameLevel = 100
    if closeBtn and closeBtn.GetFrameLevel then
        syncFrameLevel = math.max(syncFrameLevel, closeBtn:GetFrameLevel() + 5)
    end
    if MainFrame.GetFrameLevel then
        syncFrameLevel = math.max(syncFrameLevel, MainFrame:GetFrameLevel() + 100)
    end
    if syncButton.SetFrameLevel then
        syncButton:SetFrameLevel(syncFrameLevel)
    end

    local syncMonitor = syncButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncMonitor:SetPoint("RIGHT", syncButton, "RIGHT", 0, 0)
    syncMonitor:SetJustifyH("RIGHT")
    syncMonitor:SetText("|cff00ff00●|r |cff888888Sync: Idle|r")
    MainFrame.syncMonitor = syncMonitor
    MainFrame.syncButton = syncButton

    syncButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("MarketSync Network Status", 1, 0.82, 0)
        local inGuild = IsInGuild and IsInGuild()
        if not inGuild then
            GameTooltip:AddLine("Guild Sync: |cffff8800Disabled (Not in a guild)|r", 0.85, 0.85, 0.85, true)
        elseif MarketSyncDB and MarketSyncDB.PassiveSync == false then
            GameTooltip:AddLine("Guild Sync: |cffaaaaaaDisabled (Settings)|r", 0.85, 0.85, 0.85, true)
        else
            GameTooltip:AddLine("Guild Sync: |cff00ff00Active (Listening)|r", 0.85, 0.85, 0.85, true)
        end
        local tx = MarketSync.TxRate or 0
        local rx = MarketSync.RxRate or 0
        GameTooltip:AddLine(string.format("Traffic: Tx %d/s | Rx %d/s", tx, rx), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Click to toggle Network Monitor Console.", 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    syncButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncButton:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then
            MarketSync.ToggleNetworkMonitor()
        end
    end)
    
    function MarketSync.UpdateNetworkUI(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
        MarketSync.TxRate = txRate or 0
        MarketSync.RxRate = rxRate or 0
        if MainFrame and MainFrame.syncMonitor then
            local text
            if type(txAPIRate) == "string" then
                text = txAPIRate
            elseif not IsInGuild or not IsInGuild() then
                text = "|cff888888●|r |cff666666Sync: No Guild|r"
            elseif MarketSyncDB and MarketSyncDB.PassiveSync == false then
                text = "|cff888888●|r |cff666666Sync: Disabled|r"
            elseif txRate > 0 and rxRate > 0 then
                text = string.format("|cff00ff00● Rx: %d/s|r  |cffff8800Tx: %d/s|r", rxRate, txRate)
            elseif txRate > 0 then
                text = string.format("|cffff8800● Tx: %d items/s|r", txRate)
            elseif rxRate > 0 then
                text = string.format("|cff00ff00● Rx: %d items/s|r", rxRate)
            else
                text = "|cff00ff00●|r |cff888888Sync: Idle|r"
            end
            MainFrame.syncMonitor:SetText(text)
            if MainFrame.syncButton and MainFrame.syncMonitor.GetStringWidth then
                MainFrame.syncButton:SetWidth(math.max(80, MainFrame.syncMonitor:GetStringWidth() + 10))
            end
        end

        if MarketSyncMonitorFrame and MarketSyncMonitorFrame:IsShown() then
            MarketSyncMonitorFrame.txLabel:SetText(string.format("|cffff8800Tx: %d items/s|r", txRate or 0))
            MarketSyncMonitorFrame.rxLabel:SetText(string.format("|cff00ff00Rx: %d items/s|r", rxRate or 0))
            
            if type(txAPIRate) == "string" then
                MarketSyncMonitorFrame.queueLabel:SetText(txAPIRate)
            elseif (txRate or 0) > 0 or (rxRate or 0) > 0 then
                MarketSyncMonitorFrame.queueLabel:SetText("|cff00ff00Sync Active|r")
            elseif not IsInGuild or not IsInGuild() then
                MarketSyncMonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Disabled (No Guild)|r")
            else
                MarketSyncMonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
            end
        end

        if MarketSync.UpdateRateMonitor then
            MarketSync.UpdateRateMonitor(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
        end
    end

    -- ================================================================
    -- BOTTOM TABS
    -- ================================================================
    local tabNames = {"Personal Scan", "Guild Sync", "Neutral AH", "Analytics", "Processing", "Alerts", "Settings"}
    local tabs = {}
    local contentFrames = {}
    MainFrame.contentFrames = contentFrames

    -- Item Detail Dashboard (Standalone view)
    if MarketSync.CreateItemDetailPanel then
        ItemDetailPanel = MarketSync.CreateItemDetailPanel(MainFrame)
    end

    function MarketSync.HideAllTabContent()
        for _, frame in ipairs(contentFrames) do
            if frame then frame:Hide() end
        end
        if ItemHistoryPanel then ItemHistoryPanel:Hide() end
        if AnalyticsPanel then AnalyticsPanel:Hide() end
        if ItemDetailPanel then ItemDetailPanel:Hide() end
    end

    local function SelectTab(id)
        if tabs[id] and not tabs[id]:IsShown() then
            for idx, t in ipairs(tabs) do
                if t:IsShown() then
                    id = idx
                    break
                end
            end
        end
        activeBrowseTab = id
        MainFrame.activeTabID = id
        MainFrame.selectedTab = id
        
        -- Hide all sub-panels (Detail, History, Analytics) on tab change
        if MarketSync.HideAllTabContent then
            MarketSync.HideAllTabContent()
        end

        -- Only auto-preload caches on tab change when Low RAM mode is disabled
        if MarketSyncDB and not MarketSyncDB.LowRamMode then
            if id == 1 and MarketSync.LoadPersonalCache then
                MarketSync.LoadPersonalCache()
            elseif id == 2 and MarketSync.LoadGuildCache then
                MarketSync.LoadGuildCache()
            elseif id == 3 and MarketSync.LoadNeutralCache then
                MarketSync.LoadNeutralCache()
            end
        end

        for i, tab in ipairs(tabs) do
            if i == id then
                if PanelTemplates_SelectTab then
                    PanelTemplates_SelectTab(tab)
                end
                if tab.SetSelected then
                    tab:SetSelected(true)
                end
                local baseLevel = MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 1
                if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 6) end
                if contentFrames[i] then contentFrames[i]:Show() end
            else
                if PanelTemplates_DeselectTab then
                    PanelTemplates_DeselectTab(tab)
                end
                if tab.SetSelected then
                    tab:SetSelected(false)
                end
                local baseLevel = MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 1
                if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 4) end
                if contentFrames[i] then contentFrames[i]:Hide() end
            end
        end
        local titles = {
            "Personal Scan",
            "Guild Sync",
            "Neutral AH",
            "Analytics",
            "Processing",
            "Alerts",
            "Settings"
        }
        
        local tooltips = {
            "Browse your natively scanned Auction House data.",
            "Browse composite Auction House data synced from guild members.",
            "Browse data from the Neutral Auction House.",
            "Inspect in-depth price trends, historical distribution, and market metrics.",
            "Organized controls on the left, auction-style arbitrage and crafting results on the right.",
            "Track targets by threshold and watch lists.",
            "Configure MarketSync background settings, caches, and UI behaviors.",
        }

        local versionStr = "v" .. tostring(MarketSync.GetAddOnMetadata("MarketSync", "Version") or "1.0")
        local fullTitle = string.format("%s (%s) - %s", MarketSync.ADDON_NAME or "MarketSync", versionStr, titles[id] or "")
        titleText:SetText(fullTitle)
        titleText:Show()
        
        -- Adjust hitbox width to cover the new text
        MainFrame.titleHitBox:SetWidth(titleText:GetStringWidth() + 20)
        MainFrame.titleHitBox.tooltipTitle = titles[id] or ""
        MainFrame.titleHitBox.tooltipText = tooltips[id]
        MainFrame.titleHitBox:Show()
    end
    MarketSync.SelectMainFrameTab = SelectTab

    local function CreateMainTab(id, name)
        local tab
        local tabName = "MarketSyncMainFrameTab" .. id

        -- Match native Blizzard Auction House tabs 1:1
        local templates = {
            "AuctionHouseFrameDisplayModeTabTemplate",
            "AuctionHouseFrameTabTemplate",
            "PanelTabButtonTemplate",
        }
        for _, tmpl in ipairs(templates) do
            local ok, res = pcall(CreateFrame, "Button", tabName, MainFrame, tmpl)
            if ok and res then
                tab = res
                break
            end
        end
        if not tab then
            tab = CreateFrame("Button", tabName, MainFrame)
            if MarketSync.StyleModernTab then
                MarketSync.StyleModernTab(tab)
            end
        end
        tab:SetID(id)
        tab:SetText(name)
        local baseLevel = MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 1
        if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 4) end
        if PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(tab)
        end
        return tab
    end

    for i, name in ipairs(tabNames) do
        local tab = CreateMainTab(i, name)
        tab:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = tab
    end
    MainFrame.numTabs = #tabs
    MainFrame.tabs = tabs

    -- Dynamically show/hide tabs, size them uniformly, and anchor visible ones cleanly
    local function RefreshTabVisibility()
        local visibleTabs = {}
        for i, tab in ipairs(MainFrame.tabs) do
            local shouldHide = false
            if i == 2 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
                shouldHide = true
            elseif i == 3 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
                shouldHide = true
            elseif i == 4 and MarketSyncDB and MarketSyncDB.EnableAnalyticsTab == false then
                shouldHide = true
            elseif i == 5 and MarketSyncDB and not MarketSyncDB.EnableProcessingTab then
                shouldHide = true
            elseif i == 6 and MarketSyncDB and not MarketSyncDB.EnableAlertsTab then
                shouldHide = true
            end

            if shouldHide then
                tab:Hide()
            else
                table.insert(visibleTabs, tab)
            end
        end

        local numVisible = #visibleTabs
        if numVisible == 0 then return end

        -- Calculate balanced tab width across the 832px window:
        -- 7 tabs: 104px (span ~714px)
        -- 6 tabs: 112px (span ~660px)
        -- <=5 tabs: 120px (span ~590px)
        local tabWidth = 104
        if numVisible <= 5 then
            tabWidth = 120
        elseif numVisible == 6 then
            tabWidth = 112
        end

        local overlap = -2  -- 2px overlap for seamless end-cap docking without clipping text

        MainFrame.tabPadding = 0
        MainFrame.minTabWidth = tabWidth
        MainFrame.maxTabWidth = tabWidth

        local lastVisible = nil
        for idx, tab in ipairs(visibleTabs) do
            tab:ClearAllPoints()
            tab:Show()

            tab:SetHeight(32)
            tab:SetWidth(tabWidth)

            if tab.Text then
                tab.Text:SetWidth(tabWidth - 16)
            end
            if PanelTemplates_TabResize then
                PanelTemplates_TabResize(tab, 0, tabWidth)
            end

            if not lastVisible then
                -- First visible tab docks to the bottom border of MainFrame
                -- -28 from BOTTOMLEFT aligns the tab top to the bottom border gold trim
                tab:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 19, -28)
            else
                -- Subsequent tabs anchor by BOTTOMLEFT to previous tab's BOTTOMRIGHT + overlap
                -- This guarantees ALL tab bottoms and tops remain perfectly aligned at identical Y
                tab:SetPoint("BOTTOMLEFT", lastVisible, "BOTTOMRIGHT", overlap, 0)
            end
            lastVisible = tab
        end

        -- Ensure current selected tab retains elevated frame level
        if MainFrame.selectedTab then
            local selTab = MainFrame.tabs[MainFrame.selectedTab]
            if selTab and not selTab:IsShown() then
                SelectTab(1)
            else
                SelectTab(MainFrame.selectedTab)
            end
        else
            SelectTab(1)
        end
    end
    MainFrame.RefreshTabVisibility = RefreshTabVisibility
    MarketSync.RefreshTabVisibility = RefreshTabVisibility
    RefreshTabVisibility()

    MainFrame:HookScript("OnShow", function(self)
        if self.RefreshTabVisibility then
            self:RefreshTabVisibility()
        end
    end)

    -- ================================================================
    -- TAB 1, 2, 3: BROWSE PANELS (Personal / Guild / Neutral)
    -- ================================================================
    BrowseContent = MarketSync.CreateBrowsePanel(MainFrame, "personal")
    BrowseContent:Hide()
    table.insert(contentFrames, BrowseContent)

    SyncContent = MarketSync.CreateBrowsePanel(MainFrame, "guild")
    SyncContent:Hide()
    table.insert(contentFrames, SyncContent)

    NeutralContent = MarketSync.CreateBrowsePanel(MainFrame, "neutral")
    NeutralContent:Hide()
    table.insert(contentFrames, NeutralContent)

    -- TAB 4: UNIFIED ANALYTICS PANEL
    AnalyticsPanel = MarketSync.CreateAnalyticsPanel and MarketSync.CreateAnalyticsPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    AnalyticsPanel:SetAllPoints()
    AnalyticsPanel:Hide()
    MainFrame.analyticsPanel = AnalyticsPanel
    table.insert(contentFrames, AnalyticsPanel)

    -- TAB 5: PROCESSING PANEL
    ProcessingContent = MarketSync.CreateProcessingPanel and MarketSync.CreateProcessingPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    ProcessingContent:SetAllPoints()
    ProcessingContent:Hide()
    table.insert(contentFrames, ProcessingContent)

    -- TAB 6: ALERTS PANEL
    NotificationsContent = MarketSync.CreateNotificationsPanel and MarketSync.CreateNotificationsPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    NotificationsContent:SetAllPoints()
    NotificationsContent:Hide()
    table.insert(contentFrames, NotificationsContent)

    -- Global function to show item history from any browse panel (redirected to unified modern Analytics)
    function MarketSync.ShowItemHistory(dbKey, itemLink, name, icon, price, sourceTab)
        if MarketSync.ShowAnalytics then
            MarketSync.ShowAnalytics(dbKey, itemLink, name, icon, price)
        end
    end

    -- ================================================================
    -- TAB 7: SETTINGS
    -- ================================================================
    SettingsContent = CreateFrame("Frame", nil, MainFrame)
    SettingsContent:SetAllPoints()
    SettingsContent:Hide()
    table.insert(contentFrames, SettingsContent)

    -- --- SETTINGS UI FRAMES ---
    local function CreateBox(parent, w, h, x, y)
        return MarketSync.CreateModernInset(parent, x, y, w, h)
    end

    -- Four categorized columns
    local TOP_Y     = -70
    local CONTENT_H = 338
    local COL1_X    = 18
    local COL2_X    = 210
    local COL3_X    = 410
    local COL4_X    = 600

    local COL1_W    = 188 -- Column 1: Performance & Memory
    local COL2_W    = 196 -- Column 2: Professions & AH
    local COL3_W    = 186 -- Column 3: Audio & Notifications
    local COL4_W    = 218 -- Column 4: Sync & Swarm + Beta

    local boxMemory = CreateBox(SettingsContent, COL1_W, CONTENT_H, COL1_X, TOP_Y)
    local boxAH     = CreateBox(SettingsContent, COL2_W, CONTENT_H, COL2_X, TOP_Y)
    local boxAudio  = CreateBox(SettingsContent, COL3_W, CONTENT_H, COL3_X, TOP_Y)
    local boxSwarm  = CreateBox(SettingsContent, COL4_W, CONTENT_H, COL4_X, TOP_Y)

    -- ================================================================
    -- HELPER: AttachTooltip & CreateCheckbox
    -- ================================================================
    local function AttachTooltip(frame, text)
        if not text or text == "" then return end
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function CreateCheckbox(parent, anchor, anchorPoint, label, tooltipText)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        if anchorPoint then
            cb:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -6)
        else
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        end
        cb.text:SetText(label)
        cb.text:SetFontObject("GameFontHighlightSmall")
        cb.text:SetWidth(152)
        cb.text:SetJustifyH("LEFT")
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        AttachTooltip(cb, tooltipText)
        return cb
    end

    -- ================================================================
    -- COLUMN 1: PERFORMANCE & MEMORY MANAGEMENT
    -- ================================================================
    local header1 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header1:SetPoint("TOP", boxMemory, "TOP", 0, 16)
    header1:SetTextColor(1, 0.82, 0)
    header1:SetText("Performance & Memory")

    local UpdateMemorySettingsVisibility
    local chkCache
    local speedHeader

    local chkLowRam = CreateCheckbox(boxMemory, boxMemory, "TOPLEFT",
        "Enable Low RAM Mode", "Wipe search caches and run Lua garbage collection when windows are closed. Recommended on by default.")
    chkLowRam:ClearAllPoints()
    chkLowRam:SetPoint("TOPLEFT", boxMemory, "TOPLEFT", 12, -10)
    chkLowRam:SetScript("OnClick", function(self)
        MarketSyncDB.LowRamMode = self:GetChecked()
        if not self:GetChecked() then
            if MarketSyncDB.BuildCacheOnStartup and MarketSync.BuildSearchIndex then
                MarketSync.BuildSearchIndex()
            end
        end
        if UpdateMemorySettingsVisibility then UpdateMemorySettingsVisibility() end
    end)
    chkLowRam:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.LowRamMode) end
        if UpdateMemorySettingsVisibility then UpdateMemorySettingsVisibility() end
    end)

    chkCache = CreateCheckbox(boxMemory, chkLowRam, "BOTTOMLEFT",
        "Pre-Build on Startup", "Pre-load and index item data shortly after login (disabled by default in Low RAM mode).")
    chkCache:SetScript("OnClick", function(self)
        MarketSyncDB.BuildCacheOnStartup = self:GetChecked()
    end)
    chkCache:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.BuildCacheOnStartup) end
    end)

    -- Cache Build Speed Slider
    speedHeader = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    speedHeader:SetPoint("TOPLEFT", chkCache, "BOTTOMLEFT", 4, -10)
    speedHeader:SetText("Cache Build Speed")
    speedHeader:SetTextColor(1, 0.82, 0)

    UpdateMemorySettingsVisibility = function()
        local isLowRam = MarketSyncDB and (MarketSyncDB.LowRamMode ~= false)
        if isLowRam then
            if chkCache then chkCache:Hide() end
            if speedHeader then
                speedHeader:ClearAllPoints()
                speedHeader:SetPoint("TOPLEFT", chkLowRam, "BOTTOMLEFT", 4, -12)
            end
        else
            if chkCache then chkCache:Show() end
            if speedHeader then
                speedHeader:ClearAllPoints()
                speedHeader:SetPoint("TOPLEFT", chkCache, "BOTTOMLEFT", 4, -10)
            end
        end
    end

    local speedSlider = CreateFrame("Slider", "MarketSyncMainCacheSpeedSlider", boxMemory, "OptionsSliderTemplate")
    speedSlider:SetPoint("TOPLEFT", speedHeader, "BOTTOMLEFT", 6, -14)
    speedSlider:SetWidth(110)
    speedSlider:SetMinMaxValues(1, 4)
    speedSlider:SetValueStep(1)
    speedSlider:SetObeyStepOnDrag(true)
    speedSlider.Low:SetText("1")
    speedSlider.High:SetText("4")

    local sliderTrack = speedSlider:CreateTexture(nil, "BACKGROUND")
    sliderTrack:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    sliderTrack:SetHeight(4)
    sliderTrack:SetPoint("LEFT", speedSlider, "LEFT", 4, 0)
    sliderTrack:SetPoint("RIGHT", speedSlider, "RIGHT", -4, 0)

    local sliderTrackBorder = CreateFrame("Frame", nil, speedSlider, "BackdropTemplate")
    sliderTrackBorder:SetPoint("TOPLEFT", sliderTrack, "TOPLEFT", -1, 1)
    sliderTrackBorder:SetPoint("BOTTOMRIGHT", sliderTrack, "BOTTOMRIGHT", 1, -1)
    sliderTrackBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    sliderTrackBorder:SetBackdropBorderColor(0, 0, 0, 1)

    local speedLabel = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    speedLabel:SetPoint("LEFT", speedSlider, "RIGHT", 8, 0)
    speedLabel:SetWidth(50)
    speedLabel:SetJustifyH("LEFT")

    local speedDesc = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    speedDesc:SetPoint("TOPLEFT", speedSlider, "BOTTOMLEFT", -6, -8)
    speedDesc:SetWidth(168)
    speedDesc:SetJustifyH("LEFT")

    local function UpdateSpeedDisplay(val)
        local preset = MarketSync.CacheSpeedPresets and MarketSync.CacheSpeedPresets[val]
        if preset then
            speedLabel:SetText("|cffffd700" .. preset.name .. "|r")
            speedDesc:SetText(preset.desc)
        end
        speedSlider.Text:SetText("")
    end

    speedSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        MarketSyncDB.CacheSpeed = val
        UpdateSpeedDisplay(val)
    end)
    speedSlider:SetScript("OnShow", function(self)
        local val = (MarketSyncDB and MarketSyncDB.CacheSpeed) or 2
        self:SetValue(val)
        UpdateSpeedDisplay(val)
    end)
    AttachTooltip(speedSlider, "Controls background indexing yield rate and batch size when building search caches or resolving item data.")

    local ramText = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ramText:SetPoint("BOTTOMLEFT", boxMemory, "BOTTOMLEFT", 10, 8)
    ramText:SetWidth(168)
    ramText:SetJustifyH("LEFT")
    SettingsContent.ramText = ramText

    -- ================================================================
    -- COLUMN 2: PROFESSIONS & AUCTION HOUSE
    -- ================================================================
    local header2 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header2:SetPoint("TOP", boxAH, "TOP", 0, 16)
    header2:SetTextColor(1, 0.82, 0)
    header2:SetText("Professions & AH")

    local chkTradeSkill = CreateCheckbox(boxAH, boxAH, "TOPLEFT",
        "TradeSkill Costs", "Show crafting costs, profit margins, vendor pricing, and materials tree drawer inside TradeSkill window.")
    chkTradeSkill:ClearAllPoints()
    chkTradeSkill:SetPoint("TOPLEFT", boxAH, "TOPLEFT", 12, -10)
    chkTradeSkill:SetScript("OnClick", function(self)
        MarketSyncDB.EnableProfessionCraftInfo = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r TradeSkill Costs " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MarketSync.RefreshCraftingInfoUI then MarketSync.RefreshCraftingInfoUI() end
    end)
    chkTradeSkill:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableProfessionCraftInfo ~= false) end
    end)

    local chkAnalytics = CreateCheckbox(boxAH, chkTradeSkill, "BOTTOMLEFT",
        "Enable Analytics Tab", "Show price history charts, volume trends, and item stats on both portable window and Auction House.")
    chkAnalytics:SetScript("OnClick", function(self)
        MarketSyncDB.EnableAnalyticsTab = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Analytics " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
    end)
    chkAnalytics:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableAnalyticsTab ~= false) end
    end)

    local chkAuctionatorScan = CreateCheckbox(boxAH, chkAnalytics, "BOTTOMLEFT",
        "Auctionator Scanning", "Let Auctionator perform AH scans and import its price database. Disable to use MarketSync's native scanner.")
    chkAuctionatorScan:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        MarketSyncDB.UseAuctionatorScanner = isChecked
        MarketSyncDB.AuctionatorScannerUserChoice = true
        if isChecked and MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auctionator scanning enabled")
        end
        if MarketSync.Provider then MarketSync.Provider.Select() end
        if isChecked and MarketSync.RegisterAuctionatorHooks then MarketSync.RegisterAuctionatorHooks() end
        print("|cFF00FF00[MarketSync]|r Auctionator Scanning " .. (isChecked and "Enabled" or "Disabled"))
    end)
    chkAuctionatorScan:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.UseAuctionatorScanner ~= false) end
    end)

    local chkTooltipPrice = CreateCheckbox(boxAH, chkAuctionatorScan, "BOTTOMLEFT",
        "Tooltip Auction Prices", "Show buyout prices, stack totals, and scan freshness directly on item tooltips.")
    chkTooltipPrice:SetScript("OnClick", function(self)
        MarketSyncDB.EnableTooltipAuctionPrice = self:GetChecked()
    end)
    chkTooltipPrice:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableTooltipAuctionPrice ~= false) end
    end)

    local chkTooltip = CreateCheckbox(boxAH, chkTooltipPrice, "BOTTOMLEFT",
        "Tooltip Probabilities", "Show expected yields and EV values for Prospecting, Milling, and Disenchanting on item tooltips.")
    chkTooltip:SetScript("OnClick", function(self)
        MarketSyncDB.EnableTooltipProb = self:GetChecked()
    end)
    chkTooltip:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableTooltipProb ~= false) end
    end)

    local chkPriceCheck = CreateCheckbox(boxAH, chkTooltip, "BOTTOMLEFT",
        "Chat Price Check '?'", "Answer queries from other players using '? [Item Link]'.")
    chkPriceCheck:SetScript("OnClick", function(self)
        MarketSyncDB.EnableChatPriceCheck = self:GetChecked()
    end)
    chkPriceCheck:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableChatPriceCheck ~= false) end
    end)

    -- Forward declarations for dynamic visibility across columns
    local UpdateAudioSettingsVisibility
    local UpdateBetaSettingsVisibility
    local chkBetaAlerts, undercutHeader, undercutSlider

    -- ================================================================
    -- COLUMN 3: AUDIO & NOTIFICATIONS
    -- ================================================================
    local header3 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header3:SetPoint("TOP", boxAudio, "TOP", 0, 16)
    header3:SetTextColor(1, 0.82, 0)
    header3:SetText("Audio & Alerts")

    local lockedAudioBox = CreateFrame("Frame", nil, boxAudio)
    lockedAudioBox:SetAllPoints()

    local lockedAudioIcon = lockedAudioBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lockedAudioIcon:SetPoint("TOP", boxAudio, "TOP", 0, -28)
    lockedAudioIcon:SetTextColor(1, 0.67, 0)
    lockedAudioIcon:SetText("[BETA LOCKED]")

    local lockedAudioDesc = lockedAudioBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lockedAudioDesc:SetPoint("TOPLEFT", boxAudio, "TOPLEFT", 12, -56)
    lockedAudioDesc:SetPoint("RIGHT", boxAudio, "RIGHT", -12, 0)
    lockedAudioDesc:SetJustifyH("CENTER")
    lockedAudioDesc:SetSpacing(3)
    lockedAudioDesc:SetText("|cffaaaaaaPrice Alerts & Notifications are currently in Beta.\n\nTurn on '|cffffd700Enable Alerts|r' in the Beta Features panel to unlock notification sounds, volume, and visual alerts.|r")

    local btnUnlockAudio = CreateFrame("Button", nil, lockedAudioBox, "UIPanelButtonTemplate")
    btnUnlockAudio:SetSize(140, 22)
    btnUnlockAudio:SetPoint("TOP", lockedAudioDesc, "BOTTOM", 0, -16)
    btnUnlockAudio:SetText("Enable Alerts (Beta)")
    btnUnlockAudio:SetScript("OnClick", function()
        if MarketSyncDB then MarketSyncDB.EnableAlertsTab = true end
        if chkBetaAlerts then chkBetaAlerts:SetChecked(true) end
        if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
        if UpdateBetaSettingsVisibility then UpdateBetaSettingsVisibility() end
    end)

    local chkNotifSound = CreateCheckbox(boxAudio, boxAudio, "TOPLEFT",
        "Enable Sound Alerts", "Play a sound when a tracked notification request triggers.")
    chkNotifSound:ClearAllPoints()
    chkNotifSound:SetPoint("TOPLEFT", boxAudio, "TOPLEFT", 10, -10)
    chkNotifSound:SetScript("OnClick", function(self)
        MarketSyncDB.EnableNotificationSounds = self:GetChecked()
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
    end)
    chkNotifSound:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNotificationSounds == true) end
    end)

    -- Sound controls
    local soundHeader = boxAudio:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    soundHeader:SetPoint("TOPLEFT", chkNotifSound, "BOTTOMLEFT", 6, -6)
    soundHeader:SetText("Notification Sound")
    soundHeader:SetTextColor(1, 0.82, 0)

    local soundDropdown = CreateFrame("Frame", "MarketSyncMainSoundDropdown", boxAudio, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", soundHeader, "BOTTOMLEFT", -15, -4)
    UIDropDownMenu_SetWidth(soundDropdown, 110)

    local function PlaySelectedSound()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then MarketSync.PlayNotificationSound(soundID, true) end
    end

    local function OnSoundSelect(self)
        MarketSyncDB.NotificationSoundID = self.arg1
        UIDropDownMenu_SetText(soundDropdown, self.value)
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(soundDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            info.text = s.name
            info.value = s.name
            info.arg1 = s.id
            info.func = OnSoundSelect
            info.checked = (MarketSyncDB.NotificationSoundID == s.id)
            UIDropDownMenu_AddButton(info)
        end
    end)

    soundDropdown:SetScript("OnShow", function(self)
        local currentID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            if s.id == currentID then
                UIDropDownMenu_SetText(self, s.name)
                break
            end
        end
    end)

    local btnPlaySound = CreateFrame("Button", nil, boxAudio, "UIPanelButtonTemplate")
    btnPlaySound:SetSize(22, 22)
    btnPlaySound:SetPoint("LEFT", soundDropdown, "RIGHT", -5, 2)
    btnPlaySound:SetText(">")
    btnPlaySound:SetScript("OnClick", PlaySelectedSound)
    AttachTooltip(btnPlaySound, "Preview selected sound.")

    local volSlider = CreateFrame("Slider", "MarketSyncMainVolSlider", boxAudio, "OptionsSliderTemplate")
    volSlider:SetPoint("TOPLEFT", soundDropdown, "BOTTOMLEFT", 20, -12)
    volSlider:SetWidth(135)
    volSlider:SetMinMaxValues(0, 100)
    volSlider:SetValueStep(5)
    volSlider:SetObeyStepOnDrag(true)
    volSlider.Low:SetText("0%")
    volSlider.High:SetText("100%")
    volSlider.Text:SetText("Alert Volume*")

    volSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        MarketSyncDB.NotificationVolume = val / 100
    end)
    volSlider:SetScript("OnShow", function(self)
        self:SetValue((MarketSyncDB and MarketSyncDB.NotificationVolume or 1) * 100)
    end)
    AttachTooltip(volSlider, "Setting this to 0 mutes MarketSync; non-zero alerts follow WoW Master volume.")

    local chkMinimapAlerts = CreateCheckbox(boxAudio, volSlider, "BOTTOMLEFT",
        "Flash Minimap Button", "Flash the MarketSync minimap button until notifications are acknowledged.")
    chkMinimapAlerts:ClearAllPoints()
    chkMinimapAlerts:SetPoint("TOPLEFT", volSlider, "BOTTOMLEFT", -14, -14)
    chkMinimapAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableMinimapAlerts = self:GetChecked() and true or false
        if not MarketSyncDB.EnableMinimapAlerts and MarketSync.StopMinimapFlash then MarketSync.StopMinimapFlash() end
    end)
    chkMinimapAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableMinimapAlerts ~= false) end
    end)

    local chkRaidAlerts = CreateCheckbox(boxAudio, chkMinimapAlerts, "BOTTOMLEFT",
        "Show Alert Banner", "Display triggered notifications in the on-screen raid-warning banner.")
    chkRaidAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableRaidWarningAlerts = self:GetChecked() and true or false
    end)
    chkRaidAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableRaidWarningAlerts ~= false) end
    end)

    UpdateAudioSettingsVisibility = function()
        local alertsEnabled = MarketSyncDB and (MarketSyncDB.EnableAlertsTab == true)
        if not alertsEnabled then
            if lockedAudioBox then lockedAudioBox:Show() end
            if chkNotifSound then chkNotifSound:Hide() end
            if soundHeader then soundHeader:Hide() end
            if soundDropdown then soundDropdown:Hide() end
            if btnPlaySound then btnPlaySound:Hide() end
            if volSlider then volSlider:Hide() end
            if chkMinimapAlerts then chkMinimapAlerts:Hide() end
            if chkRaidAlerts then chkRaidAlerts:Hide() end
        else
            if lockedAudioBox then lockedAudioBox:Hide() end
            if chkNotifSound then chkNotifSound:Show() end
            if chkMinimapAlerts then chkMinimapAlerts:Show() end
            if chkRaidAlerts then chkRaidAlerts:Show() end

            local soundEnabled = MarketSyncDB and (MarketSyncDB.EnableNotificationSounds ~= false)
            if soundEnabled then
                if soundHeader then soundHeader:Show() end
                if soundDropdown then soundDropdown:Show() end
                if btnPlaySound then btnPlaySound:Show() end
                if volSlider then volSlider:Show() end
                if chkMinimapAlerts then
                    chkMinimapAlerts:ClearAllPoints()
                    chkMinimapAlerts:SetPoint("TOPLEFT", volSlider, "BOTTOMLEFT", -14, -14)
                end
            else
                if soundHeader then soundHeader:Hide() end
                if soundDropdown then soundDropdown:Hide() end
                if btnPlaySound then btnPlaySound:Hide() end
                if volSlider then volSlider:Hide() end
                if chkMinimapAlerts then
                    chkMinimapAlerts:ClearAllPoints()
                    chkMinimapAlerts:SetPoint("TOPLEFT", chkNotifSound, "BOTTOMLEFT", 0, -8)
                end
            end
        end
    end

    -- ================================================================
    -- COLUMN 4: SYNC & SWARM + BETA
    -- ================================================================
    local header4 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header4:SetPoint("TOP", boxSwarm, "TOP", 0, 16)
    header4:SetTextColor(1, 0.82, 0)
    header4:SetText("Sync & Swarm")

    local chkGuild = CreateCheckbox(boxSwarm, boxSwarm, "TOPLEFT",
        "Enable Guild Sync", "Enable or disable guild data syncing.")
    chkGuild:ClearAllPoints()
    chkGuild:SetPoint("TOPLEFT", boxSwarm, "TOPLEFT", 12, -10)
    chkGuild:SetScript("OnClick", function(self)
        MarketSyncDB.PassiveSync = self:GetChecked()
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), self:GetChecked() and nil or "Disabled") end
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    end)
    chkGuild:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.PassiveSync) end
    end)

    local chkNeutral = CreateCheckbox(boxSwarm, chkGuild, "BOTTOMLEFT",
        "Enable Neutral AH Sync", "Enable or disable Neutral Auction House syncing.")
    chkNeutral:SetScript("OnClick", function(self)
        MarketSyncDB.EnableNeutralSync = self:GetChecked()
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), self:GetChecked() and nil or "Disabled") end
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    end)
    chkNeutral:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNeutralSync ~= false) end
    end)

    local chkLock = CreateCheckbox(boxSwarm, chkNeutral, "BOTTOMLEFT",
        "Lock Minimap Button", "Prevent the minimap button from being dragged.")
    chkLock:SetScript("OnClick", function(self)
        if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = {} end
        MarketSyncDB.MinimapIcon.locked = self:GetChecked()
    end)
    chkLock:SetScript("OnShow", function(self)
        if MarketSyncDB and MarketSyncDB.MinimapIcon then self:SetChecked(MarketSyncDB.MinimapIcon.locked) end
    end)

    local rightStatsText = boxSwarm:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rightStatsText:SetPoint("TOPLEFT", chkLock, "BOTTOMLEFT", 4, -8)
    rightStatsText:SetWidth(200)
    rightStatsText:SetJustifyH("LEFT")
    rightStatsText:SetSpacing(2)
    SettingsContent.rightStatsText = rightStatsText

    local btnManageUsers = CreateFrame("Button", nil, boxSwarm, "UIPanelButtonTemplate")
    btnManageUsers:SetSize(96, 20)
    btnManageUsers:SetPoint("TOPLEFT", rightStatsText, "BOTTOMLEFT", 0, -8)
    btnManageUsers:SetText("Manage Users")
    AttachTooltip(btnManageUsers, "Block or unblock sync partners.")

    local btnSmartBandwidth = CreateFrame("Button", nil, boxSwarm, "UIPanelButtonTemplate")
    btnSmartBandwidth:SetSize(96, 20)
    btnSmartBandwidth:SetPoint("LEFT", btnManageUsers, "RIGHT", 8, 0)
    btnSmartBandwidth:SetText("Smart Rules")
    AttachTooltip(btnSmartBandwidth, "Configure where background sync and cache indexing are allowed.")

    -- Open AddOn Settings shortcut button
    local btnOpenBlizzSettings = CreateFrame("Button", nil, boxSwarm, "UIPanelButtonTemplate")
    btnOpenBlizzSettings:SetSize(200, 22)
    btnOpenBlizzSettings:SetPoint("TOPLEFT", btnManageUsers, "BOTTOMLEFT", 0, -8)
    btnOpenBlizzSettings:SetText("Open AddOn Settings")
    AttachTooltip(btnOpenBlizzSettings, "Open Blizzard's AddOn Settings menu for full categorized configuration.")
    btnOpenBlizzSettings:SetScript("OnClick", function()
        if MarketSync.OpenSettings then MarketSync.OpenSettings() end
    end)

    -- BETA FEATURES SUBSECTION (at bottom of Box 4)
    local betaBox = CreateFrame("Frame", nil, boxSwarm, "BackdropTemplate")
    betaBox:SetPoint("TOPLEFT", btnOpenBlizzSettings, "BOTTOMLEFT", -2, -8)
    betaBox:SetPoint("BOTTOMRIGHT", boxSwarm, "BOTTOMRIGHT", -8, 8)
    betaBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    betaBox:SetBackdropColor(0.04, 0.04, 0.05, 0.85)
    betaBox:SetBackdropBorderColor(0.45, 0.35, 0.15, 0.70)

    local betaTopHighlight = betaBox:CreateTexture(nil, "BORDER")
    betaTopHighlight:SetHeight(1)
    betaTopHighlight:SetPoint("TOPLEFT", 1, -1)
    betaTopHighlight:SetPoint("TOPRIGHT", -1, -1)
    betaTopHighlight:SetColorTexture(0.70, 0.50, 0.15, 0.40)

    local betaHeader = betaBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    betaHeader:SetPoint("TOPLEFT", betaBox, "TOPLEFT", 8, -6)
    betaHeader:SetText("|cffffaa00Beta Features|r")

    local betaBadge = betaBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    betaBadge:SetPoint("LEFT", betaHeader, "RIGHT", 4, 0)
    betaBadge:SetText("|cffff6600[BETA]|r")

    local chkBetaProcessing = CreateCheckbox(betaBox, betaHeader, "BOTTOMLEFT",
        "Enable Processing", "Show the Processing tab (materials solver, arbitrage, and batch crafting) on portable window and Auction House.")
    chkBetaProcessing:ClearAllPoints()
    chkBetaProcessing:SetPoint("TOPLEFT", betaBox, "TOPLEFT", 6, -24)
    chkBetaProcessing:SetScript("OnClick", function(self)
        MarketSyncDB.EnableProcessingTab = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Processing " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
    end)
    chkBetaProcessing:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableProcessingTab == true) end
    end)

    chkBetaAlerts = CreateCheckbox(betaBox, chkBetaProcessing, "BOTTOMLEFT",
        "Enable Alerts", "Show the Alerts tab (price alerts, watchlist, and deal triggers) on both the portable window and Auction House.")
    chkBetaAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableAlertsTab = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Alerts " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
        if UpdateBetaSettingsVisibility then UpdateBetaSettingsVisibility() end
    end)
    chkBetaAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableAlertsTab == true) end
        if UpdateBetaSettingsVisibility then UpdateBetaSettingsVisibility() end
    end)

    undercutHeader = betaBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    undercutHeader:SetPoint("TOPLEFT", chkBetaAlerts, "BOTTOMLEFT", 6, -4)
    undercutHeader:SetText("Alert Undercut:")

    undercutSlider = CreateFrame("Slider", "MarketSyncMainUndercutSlider", betaBox, "OptionsSliderTemplate")
    undercutSlider:SetPoint("LEFT", undercutHeader, "RIGHT", 6, 0)
    undercutSlider:SetWidth(80)
    undercutSlider:SetHeight(14)
    undercutSlider:SetMinMaxValues(1, 50)
    undercutSlider:SetValueStep(1)
    undercutSlider:SetObeyStepOnDrag(true)
    undercutSlider.Low:SetText("1%")
    undercutSlider.High:SetText("50%")
    undercutSlider.Text:SetText("10%")

    undercutSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        MarketSyncDB.AlertUndercutPct = val
        self.Text:SetText(string.format("%d%%", val))
        if MarketSync.RefreshNotificationUndercutButtons then MarketSync.RefreshNotificationUndercutButtons() end
    end)
    undercutSlider:SetScript("OnShow", function(self)
        local val = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        self:SetValue(val)
        self.Text:SetText(string.format("%d%%", val))
    end)

    local chkDebug = CreateCheckbox(betaBox, undercutHeader, "BOTTOMLEFT",
        "Debug Messages", "Print verbose synchronization and scanner diagnostics in chat.")
    chkDebug:ClearAllPoints()
    chkDebug:SetPoint("TOPLEFT", undercutHeader, "BOTTOMLEFT", -6, -8)
    chkDebug:SetScript("OnClick", function(self)
        MarketSyncDB.DebugMode = self:GetChecked()
    end)
    chkDebug:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.DebugMode == true) end
    end)

    UpdateBetaSettingsVisibility = function()
        local alertsEnabled = MarketSyncDB and (MarketSyncDB.EnableAlertsTab == true)
        if alertsEnabled then
            if undercutHeader then undercutHeader:Show() end
            if undercutSlider then undercutSlider:Show() end
            if chkDebug then
                chkDebug:ClearAllPoints()
                chkDebug:SetPoint("TOPLEFT", undercutHeader, "BOTTOMLEFT", -6, -8)
            end
        else
            if undercutHeader then undercutHeader:Hide() end
            if undercutSlider then undercutSlider:Hide() end
            if chkDebug then
                chkDebug:ClearAllPoints()
                chkDebug:SetPoint("TOPLEFT", chkBetaAlerts, "BOTTOMLEFT", 0, -4)
            end
        end
    end

    -- ================================================================
    -- Gold Bar Buttons & Labels
    -- ================================================================
    -- Rebuild button
    local btnRebuildIndex = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnRebuildIndex:SetSize(75, 19)
    btnRebuildIndex:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -170, 17)
    btnRebuildIndex:SetText("Rebuild")
    AttachTooltip(btnRebuildIndex, "Manually rebuild personal, guild, and neutral browse caches.")

    -- Reset button
    local btnResetData = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnResetData:SetSize(75, 19)
    btnResetData:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -90, 17)
    btnResetData:SetText("Reset")
    AttachTooltip(btnResetData, "|cffff4444Wipe sync data and create a new personal snapshot.|r")

    -- Console button 
    local btnNetworkMonitor = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnNetworkMonitor:SetSize(80, 19)
    btnNetworkMonitor:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -8, 17)
    btnNetworkMonitor:SetText("Console")
    AttachTooltip(btnNetworkMonitor, "View network stream and cache logs.")

    -- Labels (Perfectly aligned above the buttons)
    local lblCache = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lblCache:SetPoint("BOTTOM", btnRebuildIndex, "TOP", 0, 5)
    lblCache:SetText("Cache")

    local lblData = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lblData:SetPoint("BOTTOM", btnResetData, "TOP", 0, 5)
    lblData:SetText("Data")

    local lblDebug = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lblDebug:SetPoint("BOTTOM", btnNetworkMonitor, "TOP", 0, 5)
    lblDebug:SetText("Debug")

    local smartRulesFrame = MarketSync.CreateModernDialog("MarketSyncSmartRulesFrame", 440, 310, "|cFFFFD100Smart Bandwidth Rules|r")
    smartRulesFrame:SetPoint("CENTER")

    local swDesc = smartRulesFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    swDesc:SetPoint("TOPLEFT", 16, -38)
    swDesc:SetWidth(400)
    swDesc:SetJustifyH("LEFT")
    swDesc:SetText("|cff888888Automatically suspend background operations to protect your network ping.|r")

    local rulesInset = MarketSync.CreateModernInset(smartRulesFrame, 14, -58, 412, 208)

    local function CreateSmartCheckbox(parent, label, key, xOffset, yOffset)
        local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", xOffset, yOffset)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
        cb.text:SetText(label)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(MarketSyncDB and MarketSyncDB[key])
        end)
        cb:SetScript("OnClick", function(self)
            if MarketSyncDB then MarketSyncDB[key] = self:GetChecked() end
        end)
        return cb
    end

    local syncLabel = rulesInset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    syncLabel:SetPoint("TOPLEFT", 16, -14)
    syncLabel:SetText("|cffffd700Allow Swarm Sync in:|r")

    CreateSmartCheckbox(rulesInset, "Combat", "AllowSyncInCombat", 20, -36)
    CreateSmartCheckbox(rulesInset, "Raids", "AllowSyncInRaid", 20, -66)
    CreateSmartCheckbox(rulesInset, "Dungeons / Parties", "AllowSyncInDungeon", 20, -96)
    CreateSmartCheckbox(rulesInset, "Battlegrounds", "AllowSyncInPvP", 20, -126)
    CreateSmartCheckbox(rulesInset, "Arenas", "AllowSyncInArena", 20, -156)

    local cacheLabel = rulesInset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cacheLabel:SetPoint("TOPLEFT", 216, -14)
    cacheLabel:SetText("|cffffd700Allow Cache Indexer in:|r")

    CreateSmartCheckbox(rulesInset, "Combat", "AllowCacheInCombat", 220, -36)
    CreateSmartCheckbox(rulesInset, "Raids", "AllowCacheInRaid", 220, -66)
    CreateSmartCheckbox(rulesInset, "Dungeons / Parties", "AllowCacheInDungeon", 220, -96)
    CreateSmartCheckbox(rulesInset, "Battlegrounds", "AllowCacheInPvP", 220, -126)
    CreateSmartCheckbox(rulesInset, "Arenas", "AllowCacheInArena", 220, -156)

    local btnCloseRules = CreateFrame("Button", nil, smartRulesFrame, "UIPanelButtonTemplate")
    btnCloseRules:SetSize(80, 22)
    btnCloseRules:SetPoint("BOTTOMRIGHT", smartRulesFrame, "BOTTOMRIGHT", -14, 10)
    btnCloseRules:SetText("Close")
    btnCloseRules:SetScript("OnClick", function() smartRulesFrame:Hide() end)

    MarketSync.SmartRulesFrame = smartRulesFrame
    function MarketSync.ShowSmartRulesDialog()
        if not smartRulesFrame then return end
        if smartRulesFrame:IsShown() then smartRulesFrame:Hide() else smartRulesFrame:Show() end
    end

    btnSmartBandwidth:SetScript("OnClick", function()
        MarketSync.ShowSmartRulesDialog()
    end)

    btnNetworkMonitor:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then
            MarketSync.ToggleNetworkMonitor()
        end
    end)

    -- (Rebuild and Reset button scripts below use the exact same functionality, but have been repositioned above)

    btnRebuildIndex:SetScript("OnClick", function()
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        if MarketSync.BuildSearchIndex then
            MarketSync.BuildSearchIndex()
            if MarketSyncDB and MarketSyncDB.DebugMode then
                print("|cFF00FF00[MarketSync]|r Triggered manual index rebuild.")
            end
        end
    end)

    -- ================================================================
    -- USER MANAGEMENT POPUP
    -- ================================================================
    local userMgmtFrame = MarketSync.CreateModernDialog("MarketSyncUserMgmt", 430, 480, "|cFFFFD100User Management|r")
    userMgmtFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

    local umDesc = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    umDesc:SetPoint("TOPLEFT", 16, -38)
    umDesc:SetWidth(398)
    umDesc:SetJustifyH("LEFT")
    umDesc:SetText("|cff888888Manage peer sync status. Blocked users' data is not accepted or stored.|r")

    -- Manual Block Input Box & Button
    local addBox = CreateFrame("EditBox", nil, userMgmtFrame, "InputBoxTemplate")
    addBox:SetSize(210, 20)
    addBox:SetPoint("TOPLEFT", 22, -62)
    addBox:SetAutoFocus(false)
    addBox:SetText("")
    addBox:SetMaxLetters(40)

    local addPlaceholder = addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    addPlaceholder:SetPoint("LEFT", 4, 0)
    addPlaceholder:SetText("Enter player name to block...")
    addBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then addPlaceholder:Show() else addPlaceholder:Hide() end
    end)

    local addBtn = CreateFrame("Button", nil, userMgmtFrame, "UIPanelButtonTemplate")
    addBtn:SetSize(90, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
    addBtn:SetText("Block Player")

    -- Column Headers
    local hdrPlayer = MarketSync.CreateAHColumnHeader(userMgmtFrame, 205, 20, "Player")
    hdrPlayer:SetPoint("TOPLEFT", 14, -90)

    local hdrStatus = MarketSync.CreateAHColumnHeader(userMgmtFrame, 85, 20, "Status")
    hdrStatus:SetPoint("LEFT", hdrPlayer, "RIGHT", 0, 0)

    local hdrAction = MarketSync.CreateAHColumnHeader(userMgmtFrame, 110, 20, "Action")
    hdrAction:SetPoint("LEFT", hdrStatus, "RIGHT", 0, 0)

    -- Inset Panel for table rows
    local listInset = MarketSync.CreateModernInset(userMgmtFrame, 14, -112, 400, 318)

    local scrollFrame = CreateFrame("ScrollFrame", "MarketSyncUserMgmtScrollFrame", listInset, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -14, 2)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(scrollFrame) end
    scrollFrame:EnableMouseWheel(true)

    local umScrollChild = CreateFrame("Frame", nil, scrollFrame)
    umScrollChild:SetSize(374, 1)
    scrollFrame:SetScrollChild(umScrollChild)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = 26
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, cur - step))
        else
            self:SetVerticalScroll(math.min(maxScroll, cur + step))
        end
    end)

    local emptyText = umScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyText:SetPoint("TOP", umScrollChild, "TOP", 0, -50)
    emptyText:SetWidth(340)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText("|cff888888No sync peers recorded yet.|r\n|cff555555Synced guild members or blocked players will appear here.|r")

    local summaryText = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summaryText:SetPoint("LEFT", userMgmtFrame, "BOTTOMLEFT", 16, 22)
    summaryText:SetText("Total: 0 peers")

    local btnCloseUserMgmt = CreateFrame("Button", nil, userMgmtFrame, "UIPanelButtonTemplate")
    btnCloseUserMgmt:SetSize(80, 22)
    btnCloseUserMgmt:SetPoint("BOTTOMRIGHT", userMgmtFrame, "BOTTOMRIGHT", -14, 12)
    btnCloseUserMgmt:SetText("Close")
    btnCloseUserMgmt:SetScript("OnClick", function() userMgmtFrame:Hide() end)

    local blockRows = {}

    local function RefreshUserList()
        for _, r in pairs(blockRows) do r:Hide() end
        local count = 0
        local activeCount = 0
        local blockedCount = 0

        local allUsers = {}
        local contributors = {}
        if MarketSync.GetSyncContributorSnapshot then
            contributors = select(1, MarketSync.GetSyncContributorSnapshot(true)) or {}
        end
        for _, user in ipairs(contributors) do
            allUsers[user] = true
        end
        if MarketSyncDB and MarketSyncDB.BlockedUsers then
            for u, _ in pairs(MarketSyncDB.BlockedUsers) do
                allUsers[u] = true
            end
        end

        local sortedUsers = {}
        for user in pairs(allUsers) do
            table.insert(sortedUsers, user)
        end
        table.sort(sortedUsers)

        for _, user in ipairs(sortedUsers) do
            count = count + 1
            local row = blockRows[count]
            if not row then
                row = CreateFrame("Button", nil, umScrollChild)
                row:SetSize(374, 24)

                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                row.bg = bg

                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(0.30, 0.25, 0.12, 0.40)
                row.hl = hl

                row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.nameText:SetPoint("LEFT", 10, 0)
                row.nameText:SetWidth(190)
                row.nameText:SetJustifyH("LEFT")

                row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.statusText:SetPoint("LEFT", 205, 0)
                row.statusText:SetWidth(80)
                row.statusText:SetJustifyH("LEFT")

                row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.btn:SetSize(75, 20)
                row.btn:SetPoint("RIGHT", -10, 0)
                row.btn:SetScript("OnClick", function(btnSelf)
                    if MarketSync.ToggleBlock then MarketSync.ToggleBlock(btnSelf.user) end
                    RefreshUserList()
                end)

                blockRows[count] = row
            end

            if count % 2 == 1 then
                row.bg:SetColorTexture(0.10, 0.095, 0.09, 0.70)
            else
                row.bg:SetColorTexture(0.06, 0.055, 0.05, 0.70)
            end

            local isBlocked = MarketSyncDB.BlockedUsers and MarketSyncDB.BlockedUsers[user]
            row.nameText:SetText(user)
            if isBlocked then
                blockedCount = blockedCount + 1
                row.statusText:SetText("|cffff4444Blocked|r")
                row.btn:SetText("Unblock")
            else
                activeCount = activeCount + 1
                row.statusText:SetText("|cff00ff00Active|r")
                row.btn:SetText("Block")
            end
            row.btn.user = user
            row:SetPoint("TOPLEFT", 0, -(count - 1) * 25)
            row:Show()
        end

        umScrollChild:SetHeight(math.max(1, count * 25))

        if count == 0 then
            emptyText:Show()
            summaryText:SetText("Total: 0 peers")
        else
            emptyText:Hide()
            summaryText:SetText(string.format("Total: %d peers (|cff00ff00%d Active|r, |cffff4444%d Blocked|r)", count, activeCount, blockedCount))
        end
    end

    local function DoManualBlock()
        local name = strtrim(addBox:GetText() or "")
        if name ~= "" then
            if MarketSync.ToggleBlock then MarketSync.ToggleBlock(name) end
            addBox:SetText("")
            addBox:ClearFocus()
            RefreshUserList()
        end
    end
    addBtn:SetScript("OnClick", DoManualBlock)
    addBox:SetScript("OnEnterPressed", DoManualBlock)

    MarketSync.UserMgmtFrame = userMgmtFrame
    function MarketSync.ShowUserManagementDialog()
        if not userMgmtFrame then return end
        if userMgmtFrame:IsShown() then
            userMgmtFrame:Hide()
        else
            RefreshUserList()
            userMgmtFrame:Show()
        end
    end

    btnManageUsers:SetScript("OnClick", function()
        MarketSync.ShowUserManagementDialog()
    end)

    -- ================================================================
    -- SETTINGS Auto-Refresh Stats
    -- ================================================================
    local function UpdateSettingsStats()
        -- Update DB stats
        local totalItems = 0
        local syncedItems = 0
        local neutralItems = 0
        local uniqueSyncers = 0
        if MarketSyncDB then
            local personalData = MarketSync.GetRealmDB().PersonalData
            if personalData then
                for _ in pairs(personalData) do totalItems = totalItems + 1 end
            end
            if MarketSync.GetRealmDB().ItemMetadata then
                for _ in pairs(MarketSync.GetRealmDB().ItemMetadata) do syncedItems = syncedItems + 1 end
            end
            if MarketSync.GetRealmDB().NeutralData then
                for _ in pairs(MarketSync.GetRealmDB().NeutralData) do neutralItems = neutralItems + 1 end
            end
            if MarketSync.GetSyncContributorSnapshot then
                local contributors = select(1, MarketSync.GetSyncContributorSnapshot(false)) or {}
                uniqueSyncers = #contributors
            end
        end

        -- Cache status (using three-cache API)
        local personalCache = "Not started"
        local guildCache = "Not started"
        local neutralCache = "Not started"
        local idxStatus = MarketSync.GetIndexStatus and MarketSync.GetIndexStatus()
        if idxStatus then
            local function FormatCacheStatus(resolved, total, pending, ready, building)
                if building then
                    if pending > 0 then
                        return "|cffff8800" .. resolved .. "/" .. total .. " (" .. pending .. ")|r"
                    end
                    if total > 0 then
                        return "|cffff8800" .. resolved .. "/" .. total .. "|r"
                    end
                    return "|cffff8800...|r"
                end

                if pending > 0 then
                    return "|cffff8800" .. resolved .. "/" .. total .. " (" .. pending .. ")|r"
                end

                if ready and total > 0 and resolved >= total then
                    return "|cff00ff00" .. resolved .. "/" .. total .. "|r"
                end

                if ready then
                    return "|cff8888880|r"
                end

                return "|cff888888-|r"
            end

            personalCache = FormatCacheStatus(
                idxStatus.personalResolved or 0,
                idxStatus.personalTotal or 0,
                idxStatus.personalPending or 0,
                idxStatus.personalReady,
                idxStatus.personalBuilding
            )

            guildCache = FormatCacheStatus(
                idxStatus.guildResolved or 0,
                idxStatus.guildTotal or 0,
                idxStatus.guildPending or 0,
                idxStatus.guildReady,
                idxStatus.guildBuilding
            )

            neutralCache = FormatCacheStatus(
                idxStatus.neutralResolved or 0,
                idxStatus.neutralTotal or 0,
                idxStatus.neutralPending or 0,
                idxStatus.neutralReady,
                idxStatus.neutralBuilding
            )
        end

        -- Right column: all stats consolidated
        local syncActiveStr = ""
        if idxStatus and idxStatus.guildSyncActive then
            syncActiveStr = "\n|cffff8800Guild Sync In Progress|r (" .. (idxStatus.guildIncoming or 0) .. " incoming)"
        elseif idxStatus and idxStatus.neutralSyncActive then
            syncActiveStr = "\n|cff00ccffNeutral Sync In Progress|r (" .. (idxStatus.neutralIncoming or 0) .. " incoming)"
        end
        SettingsContent.rightStatsText:SetText(
            "|cff00ff00Personal:|r " .. totalItems .. "  |cff00ff00Guild:|r " .. syncedItems .. "\n" ..
            "|cff00ccffNeutral:|r " .. neutralItems .. "  |cff00ff00Partners:|r " .. uniqueSyncers .. "\n" ..
            "|cff00ff00Personal cache:|r " .. personalCache .. "\n" ..
            "|cff00ff00Guild cache:|r " .. guildCache .. "\n" ..
            "|cff00ccffNeutral cache:|r " .. neutralCache ..
            syncActiveStr
        )
        if SettingsContent.ramText and MarketSync.GetEstimatedRAMUsage then
            local estMB, totalStored = MarketSync.GetEstimatedRAMUsage()
            SettingsContent.ramText:SetText(string.format("|cff888888Est. Index RAM:|r |cffffffff~%.1f MB|r\n|cff888888(%d stored items)|r", estMB, totalStored))
        end
    end
    MainFrame.UpdateRightStats = UpdateSettingsStats

    SettingsContent.lastUpdate = 0
    SettingsContent:SetScript("OnUpdate", function(self, elapsed)
        self.lastUpdate = self.lastUpdate + elapsed
        if self.lastUpdate >= 0.5 then
            self.lastUpdate = 0
            UpdateSettingsStats()
        end
    end)
    SettingsContent:SetScript("OnShow", function(self)
        self.lastUpdate = 0
        UpdateSettingsStats()
        if UpdateMemorySettingsVisibility then UpdateMemorySettingsVisibility() end
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
        if UpdateBetaSettingsVisibility then UpdateBetaSettingsVisibility() end
    end)

    -- ================================================================
    -- Finalize
    -- ================================================================
    MainFrame.contentFrames = contentFrames
    RefreshTabVisibility()
    SelectTab(1)

    MainFrame:Hide()
    return MainFrame
end

-- ================================================================
MarketSync.CreateMainFrame = CreateMainFrame

-- Global Toggle Function
-- ================================================================
function MarketSync_ToggleUI()
    if not MainFrame then CreateMainFrame() end
    if MainFrame:IsShown() then
        MainFrame:Hide()
    else
        MainFrame:Show()
        if MarketSync.BuildSearchIndex then
            MarketSync.BuildSearchIndex()
        end
    end
end

