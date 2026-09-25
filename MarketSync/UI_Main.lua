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
    syncButton:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -38, -14)
    syncButton:SetHeight(20)
    syncButton:SetWidth(150)

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

        -- LOW RAM MODE: Load caches on demand
        if MarketSyncDB and MarketSyncDB.LowRamMode then
            if id == 1 and MarketSyncDB.OnDemandPersonal and MarketSync.LoadPersonalCache then
                MarketSync.LoadPersonalCache()
            elseif id == 2 and MarketSyncDB.OnDemandGuild and MarketSync.LoadGuildCache then
                MarketSync.LoadGuildCache()
            elseif id == 3 and MarketSyncDB.OnDemandNeutral and MarketSync.LoadNeutralCache then
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

    -- Column layout: four columns
    local TOP_Y   = -70
    local COL1_X  = 18
    local COL2_X  = 204 -- Expanded 5px left (from 209)
    local COL3_X  = 400 -- Memory Saver Box
    local COL4_X  = 587
    local CONTENT_H = 338

    -- Box Widths (186 for first 3 to perfectly span 18 to 587 with 5px gaps)
    local COL1_W  = 186
    local COL2_W  = 196 -- Expanded by 10px total (5px left, 5px right)
    local COL3_W  = 187
    local COL4_W  = 237

    -- Column 1: Global Settings
    local leftGlobalBox   = CreateBox(SettingsContent, COL1_W, CONTENT_H, COL1_X, TOP_Y)
    
    -- Column 2: Toggle Features
    local leftFeaturesBox = CreateBox(SettingsContent, COL2_W, CONTENT_H, COL2_X, TOP_Y)

    -- Column 3: Memory Saver
    local middleMemoryBox = CreateBox(SettingsContent, COL3_W, CONTENT_H, COL3_X, TOP_Y)

    -- Column 4: Quick Info
    local rightInfoBox    = CreateBox(SettingsContent, COL4_W, 285, COL4_X, TOP_Y)

    -- Labels invisible boundary removed. Labels now dynamically attach to buttons.

    -- ================================================================
    -- HELPER: AttachTooltip
    -- ================================================================
    local function AttachTooltip(frame, text)
        if not text or text == "" then return end
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local function CreateCheckbox(parent, anchor, anchorPoint, label, tooltipText)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(24, 24) -- Make checkbox smaller
        if anchorPoint then
            cb:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -8) -- Restored to 0 X-offset to prevent staggering
        else
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        end
        cb.text:SetText(label)
        cb.text:SetFontObject("GameFontHighlightSmall") -- Make text smaller
        cb.text:SetWidth(150) -- Adjusted for tighter columns
        cb.text:SetJustifyH("LEFT")
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0) -- Bring text closer to box
        AttachTooltip(cb, tooltipText)
        return cb
    end

    -- ================================================================
    -- COLUMN 1: GLOBAL SETTINGS
    -- ================================================================
    local header1 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header1:SetPoint("TOP", leftGlobalBox, "TOP", 0, 16) -- Perfectly centered above the box
    header1:SetTextColor(1, 0.82, 0)
    header1:SetText("Global Settings")

    local chkLock = CreateCheckbox(leftGlobalBox, leftGlobalBox, "TOPLEFT",
        "Lock Minimap Button", "Prevent the minimap button from being dragged.")
    chkLock:ClearAllPoints()
    chkLock:SetPoint("TOPLEFT", leftGlobalBox, "TOPLEFT", 10, -12)
    chkLock:SetScript("OnClick", function(self)
        if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = {} end
        MarketSyncDB.MinimapIcon.locked = self:GetChecked()
    end)
    chkLock:SetScript("OnShow", function(self)
        if MarketSyncDB and MarketSyncDB.MinimapIcon then self:SetChecked(MarketSyncDB.MinimapIcon.locked) end
    end)

    local chkNotifSound = CreateCheckbox(leftGlobalBox, chkLock, "BOTTOMLEFT",
        "Enable Notification Sounds", "Play a sound when a tracked notification request triggers.")
    chkNotifSound:SetScript("OnClick", function(self)
        MarketSyncDB.EnableNotificationSounds = self:GetChecked()
    end)
    chkNotifSound:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNotificationSounds == true) end
    end)

    local chkMinimapAlerts = CreateCheckbox(leftGlobalBox, chkNotifSound, "BOTTOMLEFT",
        "Flash Minimap for Alerts", "Flash the MarketSync minimap button until notifications are acknowledged.")
    chkMinimapAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableMinimapAlerts = self:GetChecked() and true or false
        if not MarketSyncDB.EnableMinimapAlerts and MarketSync.StopMinimapFlash then
            -- Disabling this visual channel must not erase unseen notification
            -- context. Viewing the Notifications tab performs acknowledgement.
            MarketSync.StopMinimapFlash()
        elseif MarketSyncDB.EnableMinimapAlerts
            and (tonumber(MarketSync.NotificationUnreadCount) or 0) > 0
            and MarketSync.StartMinimapFlash then
            MarketSync.StartMinimapFlash()
        end
    end)
    chkMinimapAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableMinimapAlerts ~= false) end
    end)

    local chkRaidAlerts = CreateCheckbox(leftGlobalBox, chkMinimapAlerts, "BOTTOMLEFT",
        "Show Alert Banner", "Display triggered notifications in the on-screen raid-warning banner.")
    chkRaidAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableRaidWarningAlerts = self:GetChecked() and true or false
    end)
    chkRaidAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableRaidWarningAlerts ~= false) end
    end)

    local chkPeriodicAlerts = CreateCheckbox(leftGlobalBox, chkRaidAlerts, "BOTTOMLEFT",
        "Periodic Tracked Checks", "Recheck only tracked notification items once per minute in addition to scan-time checks.")
    chkPeriodicAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.NotificationMode = self:GetChecked() and "both" or "on_scan"
    end)
    chkPeriodicAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then
            self:SetChecked(MarketSyncDB.NotificationMode == "periodic" or MarketSyncDB.NotificationMode == "both")
        end
    end)

    local chkCache = CreateCheckbox(leftGlobalBox, chkPeriodicAlerts, "BOTTOMLEFT",
        "Build Item Cache on Startup", "Pre-load item data shortly after login.")
    chkCache:SetScript("OnClick", function(self)
        MarketSyncDB.BuildCacheOnStartup = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Startup Cache " .. (MarketSyncDB.BuildCacheOnStartup and "Enabled" or "Disabled"))
    end)
    chkCache:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.BuildCacheOnStartup) end
    end)

    local chkDebug = CreateCheckbox(leftGlobalBox, chkCache, "BOTTOMLEFT",
        "Enable Debug Messages", "Print additional diagnostics in chat.")
    chkDebug:SetScript("OnClick", function(self)
        MarketSyncDB.DebugMode = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Debug Mode " .. (MarketSyncDB.DebugMode and "Enabled" or "Disabled"))
    end)
    chkDebug:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.DebugMode) end
    end)

    local undercutHeader = leftGlobalBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    undercutHeader:SetPoint("TOPLEFT", chkDebug, "BOTTOMLEFT", 6, -10)
    undercutHeader:SetText("Alert Undercut (%)")
    undercutHeader:SetTextColor(1, 0.82, 0)

    local undercutSlider = CreateFrame("Slider", "MarketSyncAlertUndercutSlider", leftGlobalBox, "OptionsSliderTemplate")
    undercutSlider:SetPoint("TOPLEFT", undercutHeader, "BOTTOMLEFT", 4, -14)
    undercutSlider:SetWidth(140)
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
    end)
    undercutSlider:SetScript("OnShow", function(self)
        local val = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        self:SetValue(val)
        self.Text:SetText(string.format("%d%%", val))
    end)
    AttachTooltip(undercutSlider, "Configure the default undercut percentage for quick alert buttons and preferred list imports (1% to 50%).")

    -- ================================================================
    -- COLUMN 2: TOGGLE FEATURES
    -- ================================================================
    local header2 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header2:SetPoint("TOP", leftFeaturesBox, "TOP", 0, 16) -- Perfectly centered above the box
    header2:SetTextColor(1, 0.82, 0)
    header2:SetText("Toggle Features")

    local chkGuild = CreateCheckbox(leftFeaturesBox, leftFeaturesBox, "TOPLEFT",
        "Enable Guild Sync",
        "Enable or disable guild data syncing. When disabled, the Guild Sync tab will be hidden and your swarm status will show as 'Disabled'.")
    chkGuild:ClearAllPoints()
    chkGuild:SetPoint("TOPLEFT", leftFeaturesBox, "TOPLEFT", 15, -12)
    chkGuild:SetScript("OnClick", function(self)
        MarketSyncDB.PassiveSync = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Guild Sync " .. (MarketSyncDB.PassiveSync and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), self:GetChecked() and nil or "Disabled")
        end
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    end)
    chkGuild:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.PassiveSync) end
    end)

    local chkNeutral = CreateCheckbox(leftFeaturesBox, chkGuild, "BOTTOMLEFT",
        "Enable Neutral AH Sync",
        "Enable or disable Neutral Auction House syncing. When disabled, the Neutral AH tab will be hidden and your swarm status will show as 'Disabled'.")
    chkNeutral:SetScript("OnClick", function(self)
        MarketSyncDB.EnableNeutralSync = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Neutral Sync " .. (MarketSyncDB.EnableNeutralSync and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), self:GetChecked() and nil or "Disabled")
        end
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    end)
    chkNeutral:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNeutralSync ~= false) end
    end)

    local chkPriceCheck = CreateCheckbox(leftFeaturesBox, chkNeutral, "BOTTOMLEFT",
        "Enable Chat Price Check '?'",
        "Answer queries from other players using '? [Item Link]'.")
    chkPriceCheck:SetScript("OnClick", function(self)
        MarketSyncDB.EnableChatPriceCheck = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Chat Price Check " .. (MarketSyncDB.EnableChatPriceCheck and "Enabled" or "Disabled"))
    end)
    chkPriceCheck:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableChatPriceCheck ~= false) end
    end)

    local chkTooltip = CreateCheckbox(leftFeaturesBox, chkPriceCheck, "BOTTOMLEFT",
        "Enable Tooltip Probabilities",
        "Show expected yields and EV values for Prospecting, Milling, and Disenchanting on item tooltips.")
    chkTooltip:SetScript("OnClick", function(self)
        MarketSyncDB.EnableTooltipProb = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Tooltip Probabilities " .. (MarketSyncDB.EnableTooltipProb and "Enabled" or "Disabled"))
    end)
    chkTooltip:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableTooltipProb ~= false) end
    end)

    local chkTooltipPrice = CreateCheckbox(leftFeaturesBox, chkTooltip, "BOTTOMLEFT",
        "Enable Tooltip Auction Prices",
        "Show buyout prices, stack totals, and scan freshness directly on item tooltips (standalone mode).")
    chkTooltipPrice:SetScript("OnClick", function(self)
        MarketSyncDB.EnableTooltipAuctionPrice = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Tooltip Auction Prices " .. (MarketSyncDB.EnableTooltipAuctionPrice and "Enabled" or "Disabled"))
    end)
    chkTooltipPrice:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableTooltipAuctionPrice ~= false) end
    end)

    -- --- SOUND CONTROLS ---
    local soundHeader = leftFeaturesBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    soundHeader:SetPoint("TOPLEFT", chkTooltipPrice, "BOTTOMLEFT", 6, -10)
    soundHeader:SetText("Notification Sound")
    soundHeader:SetTextColor(1, 0.82, 0)

    -- Dropdown
    local soundDropdown = CreateFrame("Frame", "MarketSyncSoundDropdown", leftFeaturesBox, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", soundHeader, "BOTTOMLEFT", -15, -5)
    UIDropDownMenu_SetWidth(soundDropdown, 110)

    local function PlaySelectedSound()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then
            MarketSync.PlayNotificationSound(soundID, true)
        end
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

    -- Play Button
    local btnPlaySound = CreateFrame("Button", nil, leftFeaturesBox, "UIPanelButtonTemplate")
    btnPlaySound:SetSize(22, 22)
    btnPlaySound:SetPoint("LEFT", soundDropdown, "RIGHT", -5, 2)
    btnPlaySound:SetText(">")
    btnPlaySound:SetScript("OnClick", PlaySelectedSound)
    AttachTooltip(btnPlaySound, "Preview selected sound.")

    -- Volume Slider
    local volSlider = CreateFrame("Slider", "MarketSyncVolumeSlider", leftFeaturesBox, "OptionsSliderTemplate")
    volSlider:SetPoint("TOPLEFT", soundDropdown, "BOTTOMLEFT", 20, -15)
    volSlider:SetWidth(140)
    volSlider:SetMinMaxValues(0, 100)
    volSlider:SetValueStep(5)
    volSlider:SetObeyStepOnDrag(true)
    volSlider.Low:SetText("0%")
    volSlider.High:SetText("100%")
    volSlider.Text:SetText("Alert Volume*")

    volSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        MarketSyncDB.NotificationVolume = val / 100
        -- TBC's PlaySound API has no per-sound gain. Zero is a hard mute;
        -- non-zero values are retained for clients that gain volume support.
    end)
    volSlider:SetScript("OnShow", function(self)
        self:SetValue((MarketSyncDB and MarketSyncDB.NotificationVolume or 1) * 100)
    end)
    AttachTooltip(volSlider, "TBC uses the game's Master volume for alert loudness. Setting this to 0 mutes MarketSync; non-zero alerts follow the WoW Master volume.")

    local syncDisabledNote = leftFeaturesBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    syncDisabledNote:SetPoint("BOTTOMLEFT", leftFeaturesBox, "BOTTOMLEFT", 15, 10)
    syncDisabledNote:SetWidth(170)
    syncDisabledNote:SetJustifyH("LEFT")
    syncDisabledNote:SetTextColor(1, 0.4, 0.4)
    syncDisabledNote:SetText("Disabling Sync will hide the Guild/Neutral tabs.")

    -- ================================================================
    -- COLUMN 3: MEMORY SAVER
    -- ================================================================
    local header3 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header3:SetPoint("TOP", middleMemoryBox, "TOP", 0, 16) -- Perfectly centered above the box
    header3:SetTextColor(1, 0.82, 0)
    header3:SetText("Memory Saver")

    local chkLowRam = CreateCheckbox(middleMemoryBox, middleMemoryBox, "TOPLEFT",
        "Enable Low RAM Mode", "Wipe caches and run GC when the UI is closed.")
    chkLowRam:ClearAllPoints()
    chkLowRam:SetPoint("TOPLEFT", middleMemoryBox, "TOPLEFT", 18, -12) -- Master explicitly centered
    
    local subToggles = {}
    local function UpdateSubTogglesState()
        local masterEnabled = chkLowRam:GetChecked()
        for _, cb in ipairs(subToggles) do
            if masterEnabled then
                cb:Enable()
                cb.text:SetTextColor(1, 1, 1)
            else
                cb:Disable()
                cb.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    chkLowRam:SetScript("OnClick", function(self)
        MarketSyncDB.LowRamMode = self:GetChecked()
        UpdateSubTogglesState()
        if not self:GetChecked() then
            -- If turning off, may need to trigger a background rebuild if enabled
            if MarketSyncDB.BuildCacheOnStartup and MarketSync.BuildSearchIndex then
                MarketSync.BuildSearchIndex()
            end
        end
    end)
    chkLowRam:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.LowRamMode) end
        UpdateSubTogglesState()
    end)

    local function CreateSubToggle(label, key, anchor)
        local cb = CreateCheckbox(middleMemoryBox, anchor, "BOTTOMLEFT", label, "Only load this data when the tab is clicked.")
        cb.text:SetWidth(110)
        cb:SetScript("OnClick", function(self)
            MarketSyncDB[key] = self:GetChecked()
            if self:GetChecked() and MarketSync.InvalidateIndexCache then
                MarketSync.InvalidateIndexCache() -- Immediate wipe to start on-demand cycle
            end
        end)
        cb:SetScript("OnShow", function(self)
            if MarketSyncDB then self:SetChecked(MarketSyncDB[key]) end
        end)
        table.insert(subToggles, cb)
        return cb
    end

    local chkODP = CreateSubToggle("Personal: Demand", "OnDemandPersonal", chkLowRam)
    local chkODG = CreateSubToggle("Guild: Demand", "OnDemandGuild", chkODP)
    local chkODN = CreateSubToggle("Neutral: Demand", "OnDemandNeutral", chkODG)

    -- ================================================================
    -- BETA FEATURES SUBSECTION
    -- ================================================================
    local betaBox = CreateFrame("Frame", nil, middleMemoryBox, "BackdropTemplate")
    betaBox:SetPoint("TOPLEFT", middleMemoryBox, "TOPLEFT", 8, -138)
    betaBox:SetPoint("BOTTOMRIGHT", middleMemoryBox, "BOTTOMRIGHT", -8, 8)
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
    betaHeader:SetPoint("TOPLEFT", betaBox, "TOPLEFT", 10, -9)
    betaHeader:SetText("|cffffaa00Beta Features|r")

    local betaBadge = betaBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    betaBadge:SetPoint("LEFT", betaHeader, "RIGHT", 4, 0)
    betaBadge:SetText("|cffff6600[BETA]|r")

    local betaSub = betaBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    betaSub:SetPoint("TOPLEFT", betaHeader, "BOTTOMLEFT", 0, -3)
    betaSub:SetText("Experimental modules:")

    local function CreateBetaToggle(label, key, defaultVal, tooltipText, prevAnchor)
        local cb = CreateCheckbox(betaBox, prevAnchor or betaBox, prevAnchor and "BOTTOMLEFT" or "TOPLEFT", label, tooltipText)
        cb.text:SetWidth(130)
        if not prevAnchor then
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", betaBox, "TOPLEFT", 8, -36)
        end
        cb:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            MarketSyncDB[key] = isChecked
            if key == "UseAuctionatorScanner" then
                MarketSyncDB.AuctionatorScannerUserChoice = true
                if isChecked and MarketSync.Scanner and MarketSync.Scanner.Active then
                    MarketSync.Scanner.Cancel("Auctionator scanning enabled")
                end
            end
            print(string.format("|cFF00FF00[MarketSync]|r %s %s", label, isChecked and "Enabled" or "Disabled"))
            if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
            if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then
                MarketSync.AuctionHouse.RefreshTabVisibility()
            end
            if key == "UseAuctionatorScanner" and MarketSync.Provider then
                MarketSync.Provider.Select()
                if isChecked and MarketSync.RegisterAuctionatorHooks then
                    MarketSync.RegisterAuctionatorHooks()
                end
            end
            if key == "EnableProfessionCraftInfo" and MarketSync.RefreshCraftingInfoUI then
                MarketSync.RefreshCraftingInfoUI()
            end
        end)
        cb:SetScript("OnShow", function(self)
            if MarketSyncDB then
                if defaultVal == false then
                    self:SetChecked(MarketSyncDB[key] == true)
                else
                    self:SetChecked(MarketSyncDB[key] ~= false)
                end
            end
        end)
        return cb
    end

    local chkBetaProcessing = CreateBetaToggle(
        "Enable Processing",
        "EnableProcessingTab",
        false,
        "Show the Processing tab (crafting costs, reagent tree solver, and profitability) on both the portable window and Auction House.",
        nil
    )

    local chkBetaAlerts = CreateBetaToggle(
        "Enable Alerts",
        "EnableAlertsTab",
        false,
        "Show the Alerts tab (price alerts, watchlist, and deal triggers) on both the portable window and Auction House.",
        chkBetaProcessing
    )

    local chkBetaAnalytics = CreateBetaToggle(
        "Enable Analytics",
        "EnableAnalyticsTab",
        true,
        "Show the Analytics tab (price history charts, volume trends, and item stats) on both the portable window and Auction House.",
        chkBetaAlerts
    )

    local chkAuctionatorScan = CreateBetaToggle(
        "Use Auctionator scanning",
        "UseAuctionatorScanner",
        Auctionator ~= nil and Auctionator.Database ~= nil,
        "Let Auctionator perform Auction House scans and keep its price database. MarketSync imports completed Auctionator full scans, protects neutral-AH prices, and hides its duplicate Scanner tab. Disable this to use MarketSync's native scanner instead.",
        chkBetaAnalytics
    )

    local chkBetaProf = CreateBetaToggle(
        "TradeSkill Costs",
        "EnableProfessionCraftInfo",
        true,
        "Show crafting costs, profit calculation, and recursive materials tree drawer directly inside the Blizzard TradeSkill window.",
        chkAuctionatorScan
    )

    -- ================================================================
    -- RIGHT: Quick Info + Cache Speed + Manage Users / Smart Rules
    -- ================================================================
    local rightHeader = rightInfoBox:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    rightHeader:SetPoint("BOTTOMLEFT", rightInfoBox, "TOPLEFT", 80, 2) -- Centered
    rightHeader:SetText("|cffffd700Quick Info|r")

    local rightStatsText = rightInfoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rightStatsText:SetPoint("TOPLEFT", rightInfoBox, "TOPLEFT", 15, -12)
    rightStatsText:SetWidth(207)
    rightStatsText:SetJustifyH("LEFT")
    rightStatsText:SetSpacing(3)
    SettingsContent.rightStatsText = rightStatsText

    -- Cache Build Speed
    local speedHeader = rightInfoBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    speedHeader:SetPoint("TOPLEFT", rightStatsText, "BOTTOMLEFT", -2, -14)
    speedHeader:SetText("|cffffd700Cache Build Speed|r")

    local speedSlider = CreateFrame("Slider", nil, rightInfoBox, "OptionsSliderTemplate")
    speedSlider:SetPoint("TOPLEFT", speedHeader, "BOTTOMLEFT", 10, -14)
    speedSlider:SetWidth(100)
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
    sliderTrackBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sliderTrackBorder:SetBackdropBorderColor(0, 0, 0, 1)

    local speedLabel = rightInfoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    speedLabel:SetPoint("LEFT", speedSlider, "RIGHT", 10, 0)
    speedLabel:SetWidth(85)
    speedLabel:SetJustifyH("LEFT")

    local speedDesc = rightInfoBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    speedDesc:SetPoint("TOPLEFT", speedSlider, "BOTTOMLEFT", -10, -10)
    speedDesc:SetWidth(165)
    speedDesc:SetJustifyH("LEFT")

    local function UpdateSpeedDisplay(val)
        local preset = MarketSync.CacheSpeedPresets[val]
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

    -- Manage Users + Smart Rules at bottom of Quick Info box
    local btnManageUsers = CreateFrame("Button", nil, rightInfoBox, "UIPanelButtonTemplate")
    btnManageUsers:SetSize(100, 22)
    btnManageUsers:SetPoint("BOTTOMLEFT", rightInfoBox, "BOTTOMLEFT", 15, 12)
    btnManageUsers:SetText("Manage Users")
    AttachTooltip(btnManageUsers, "Block or unblock sync partners.")

    local btnSmartBandwidth = CreateFrame("Button", nil, rightInfoBox, "UIPanelButtonTemplate")
    btnSmartBandwidth:SetSize(100, 22)
    btnSmartBandwidth:SetPoint("LEFT", btnManageUsers, "RIGHT", 7, 0)
    btnSmartBandwidth:SetText("Smart Rules")
    AttachTooltip(btnSmartBandwidth, "Configure where background sync and cache indexing are allowed.")

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

    btnSmartBandwidth:SetScript("OnClick", function()
        if smartRulesFrame:IsShown() then smartRulesFrame:Hide() else smartRulesFrame:Show() end
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

    btnManageUsers:SetScript("OnClick", function()
        if userMgmtFrame:IsShown() then
            userMgmtFrame:Hide()
        else
            RefreshUserList()
            userMgmtFrame:Show()
        end
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
        if Auctionator and Auctionator.Database and Auctionator.Database.db then
            for _ in pairs(Auctionator.Database.db) do totalItems = totalItems + 1 end
        end
        if MarketSyncDB then
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
            "|cff00ff00Total Items:|r " .. totalItems .. "  |cff00ff00Synced:|r " .. syncedItems .. "  |cff00ccffNeutral:|r " .. neutralItems .. "\n" ..
            "|cff00ff00Personal Cache:|r " .. personalCache .. "\n" ..
            "|cff00ff00Guild Cache:|r " .. guildCache .. "\n" ..
            "|cff00ccffNeutral Cache:|r " .. neutralCache .. "\n" ..
            "|cff00ff00Sync Partners:|r " .. uniqueSyncers ..
            syncActiveStr
        )
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


