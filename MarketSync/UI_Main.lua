-- =============================================================
-- MarketSync - Main Frame
-- Window shell, tabs, and settings
-- =============================================================

local MainFrame, BrowseContent, SyncContent, NeutralContent, ProcessingContent, NotificationsContent, SettingsContent
local ItemHistoryPanel, AnalyticsPanel, ItemDetailPanel
local activeBrowseTab = 1

-- ================================================================
-- MAIN FRAME CONSTRUCTION
-- ================================================================
local function CreateMainFrame()
    if MainFrame then return MainFrame end

    -- --- MAIN WINDOW (832 x 447, same as AuctionFrame) ---
    MainFrame = CreateFrame("Frame", "MarketSyncMainFrame", UIParent)
    MainFrame:SetSize(832, 447)
    MainFrame:SetPoint("CENTER")
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
    MainFrame:SetFrameStrata("HIGH")
    MainFrame:SetToplevel(true)
    tinsert(UISpecialFrames, "MarketSyncMainFrame")

    -- --- BACKGROUND TEXTURES (AH Style Parchment) ---
    -- --- BACKGROUND TEXTURES (AH Style Parchment) ---
    local tl = MainFrame:CreateTexture(nil, "ARTWORK")
    tl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft")
    tl:SetSize(256, 256)
    tl:SetPoint("TOPLEFT")

    local tm = MainFrame:CreateTexture(nil, "ARTWORK")
    tm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Top")
    tm:SetSize(320, 256)
    tm:SetPoint("TOPLEFT", 256, 0)

    local tr = MainFrame:CreateTexture(nil, "ARTWORK")
    tr:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopRight")
    tr:SetSize(256, 256)
    tr:SetPoint("TOPLEFT", tm, "TOPRIGHT", 0, 0)

    local bl = MainFrame:CreateTexture(nil, "ARTWORK")
    bl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotLeft")
    bl:SetSize(256, 191)
    bl:SetPoint("TOPLEFT", 0, -256)
    bl:SetTexCoord(0, 1, 0, 191/256)

    local bm = MainFrame:CreateTexture(nil, "OVERLAY")
    bm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Bot")
    bm:SetSize(320, 191)
    bm:SetPoint("TOPLEFT", 256, -256)
    bm:SetTexCoord(0, 1, 0, 191/256)

    local br = MainFrame:CreateTexture(nil, "ARTWORK")
    br:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotRight")
    br:SetSize(256, 191)
    br:SetPoint("TOPLEFT", bm, "TOPRIGHT", 0, 0)
    br:SetTexCoord(0, 1, 0, 191/256)

    -- Cover up the money input slots on the right with more clean gold bar texture
    local brCover = MainFrame:CreateTexture(nil, "OVERLAY")
    brCover:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Bot")
    brCover:SetSize(260, 191)
    brCover:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -5, -256)
    brCover:SetTexCoord(0, 0.75, 0, 191/256)

    -- --- PORTRAIT ---
    -- --- PORTRAIT (2D Character Face) ---
    local portrait = MainFrame:CreateTexture(nil, "BACKGROUND")
    portrait:SetSize(60, 60)
    portrait:SetPoint("TOPLEFT", 6, -6)
    
    local function UpdatePortrait()
        SetPortraitTexture(portrait, "player")
    end
    
    -- Mask to circle
    local mask = MainFrame:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(58, 58)
    mask:SetPoint("TOPLEFT", 8, -7)
    portrait:AddMaskTexture(mask)

    -- Event handling to update portrait if player appearance changes (e.g. barbshop, gear)
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
    MainFrame:SetScript("OnShow", function() UpdatePortrait() end)
    
    UpdatePortrait()


    -- --- CLOSE BUTTON ---
    local closeBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 3, -8)

    -- --- TITLE ---
    local titleText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", 0, -18)
    titleText:SetTextColor(1, 0.82, 0) -- Restore exact WoW standard yellow title
    titleText:SetText(MarketSync.ADDON_NAME or "MarketSync")
    -- Low RAM Mode: 5-minute idle GC
    local lowRamIdleTicker = nil

    MainFrame:SetScript("OnHide", function()
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
    MainFrame:SetScript("OnShow", function()
        if lowRamIdleTicker then
            lowRamIdleTicker:Cancel()
            lowRamIdleTicker = nil
        end
    end)
    MainFrame.titleText = titleText
    
    local titleHitBox = CreateFrame("Button", nil, MainFrame)
    titleHitBox:SetPoint("CENTER", titleText, "CENTER")
    titleHitBox:SetHeight(20)
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
    
    -- --- SYNC MONITOR ---
    local syncMonitor = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncMonitor:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -35, -20)
    syncMonitor:SetJustifyH("RIGHT")
    syncMonitor:SetText("|cff888888Network: Idle|r")
    MainFrame.syncMonitor = syncMonitor
    
    function MarketSync.UpdateNetworkUI(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
        if MainFrame and MainFrame.syncMonitor then
            if type(txAPIRate) == "string" then -- Traditional statusText passthrough
                MainFrame.syncMonitor:SetText(txAPIRate)
            elseif txRate > 0 and rxRate > 0 then
                MainFrame.syncMonitor:SetText(string.format("|cff00ff00Rx: %d/s|r   |cffff8800Tx: %d/s|r", rxRate, txRate))
            elseif txRate > 0 then
                MainFrame.syncMonitor:SetText(string.format("|cffff8800Sending: %d items/s|r", txRate))
            elseif rxRate > 0 then
                MainFrame.syncMonitor:SetText(string.format("|cff00ff00Receiving: %d items/s|r", rxRate))
            else
                MainFrame.syncMonitor:SetText("|cff888888Network: Idle|r")
            end
        end

        if MarketSyncMonitorFrame and MarketSyncMonitorFrame:IsShown() then
            MarketSyncMonitorFrame.txLabel:SetText(string.format("|cffff8800Tx: %d items/s|r", txRate))
            MarketSyncMonitorFrame.rxLabel:SetText(string.format("|cff00ff00Rx: %d items/s|r", rxRate))
            
            if type(txAPIRate) == "string" then
                MarketSyncMonitorFrame.queueLabel:SetText(txAPIRate)
            elseif txRate > 0 or rxRate > 0 then
                MarketSyncMonitorFrame.queueLabel:SetText("|cff00ff00Sync Active|r")
            elseif not IsInGuild() then
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
    local tabNames = {"Personal Scan", "Guild Sync", "Neutral AH", "Processing", "Notifications", "Settings"}
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
        activeBrowseTab = id
        MainFrame.activeTabID = id
        
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
                PanelTemplates_SelectTab(tab)
                if contentFrames[i] then contentFrames[i]:Show() end
            else
                PanelTemplates_DeselectTab(tab)
                if contentFrames[i] then contentFrames[i]:Hide() end
            end
        end
        local titles = {
            "Personal Scan",
            "Guild Sync",
            "Neutral AH",
            "Processing",
            "Notifications",
            "Settings"
        }
        
        local tooltips = {
            "Browse your natively scanned Auction House data.",
            "Browse composite Auction House data synced from guild members.",
            "Browse data from the Neutral Auction House.",
            "Organized controls on the left, auction-style arbitrage and crafting results on the right.",
            "Track targets by threshold and import from Auctionator shopping lists.",
            "Configure MarketSync background settings, caches, and UI behaviors.",
        }

        local versionStr = "v" .. tostring(C_AddOns and C_AddOns.GetAddOnMetadata("MarketSync", "Version") or GetAddOnMetadata("MarketSync", "Version") or "1.0")
        local fullTitle = string.format("%s (%s) - %s", MarketSync.ADDON_NAME or "MarketSync", versionStr, titles[id] or "")
        titleText:SetText(fullTitle)
        titleText:Show()
        
        -- Adjust hitbox width to cover the new text
        MainFrame.titleHitBox:SetWidth(titleText:GetStringWidth() + 20)
        MainFrame.titleHitBox.tooltipTitle = titles[id] or ""
        MainFrame.titleHitBox.tooltipText = tooltips[id]
        MainFrame.titleHitBox:Show()
    end

    local lastVisibleTab = nil
    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", "AucAnnTab" .. i, MainFrame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(name)
        
        -- Check if tab should be hidden based on settings
        local isHidden = false
        if i == 2 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
            isHidden = true
        elseif i == 3 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
            isHidden = true
        end
        
        if isHidden then
            tab:Hide()
        else
            if not lastVisibleTab then
                -- First visible tab anchors to the frame
                tab:SetPoint("TOPLEFT", MainFrame, "BOTTOMLEFT", 60, 12)
            else
                -- Subsequent visible tabs anchor to the previous visible tab
                tab:SetPoint("TOPLEFT", lastVisibleTab, "TOPRIGHT", -8, 0)
            end
            lastVisibleTab = tab
        end
        
        tab:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = tab
    end
    MainFrame.numTabs = #tabs
    MainFrame.tabs = tabs

    -- Dynamically show/hide tabs and re-anchor visible ones
    local function RefreshTabVisibility()
        local lastVisible = nil
        for i, tab in ipairs(MainFrame.tabs) do
            local shouldHide = false
            if i == 2 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
                shouldHide = true
            elseif i == 3 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
                shouldHide = true
            end

            tab:ClearAllPoints()
            if shouldHide then
                tab:Hide()
            else
                tab:Show()
                if not lastVisible then
                    tab:SetPoint("TOPLEFT", MainFrame, "BOTTOMLEFT", 60, 12)
                else
                    tab:SetPoint("TOPLEFT", lastVisible, "TOPRIGHT", -8, 0)
                end
                lastVisible = tab
            end
        end
        -- If the currently selected tab is now hidden, switch to Personal Scan
        if MainFrame.selectedTab then
            local selTab = MainFrame.tabs[MainFrame.selectedTab]
            if selTab and not selTab:IsShown() then
                SelectTab(1)
            end
        end
    end
    MainFrame.RefreshTabVisibility = RefreshTabVisibility

    -- ================================================================
    -- TAB 1 & 2: BROWSE PANELS (Personal / Guild)
    -- ================================================================
    BrowseContent = MarketSync.CreateBrowsePanel(MainFrame, "personal")
    table.insert(contentFrames, BrowseContent)

    SyncContent = MarketSync.CreateBrowsePanel(MainFrame, "guild")
    SyncContent:Hide()
    table.insert(contentFrames, SyncContent)

    NeutralContent = MarketSync.CreateBrowsePanel(MainFrame, "neutral")
    NeutralContent:Hide()
    table.insert(contentFrames, NeutralContent)

    ProcessingContent = MarketSync.CreateProcessingPanel and MarketSync.CreateProcessingPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    ProcessingContent:SetAllPoints()
    ProcessingContent:Hide()
    table.insert(contentFrames, ProcessingContent)

    NotificationsContent = MarketSync.CreateNotificationsPanel and MarketSync.CreateNotificationsPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    NotificationsContent:SetAllPoints()
    NotificationsContent:Hide()
    table.insert(contentFrames, NotificationsContent)

    -- ================================================================
    -- ITEM HISTORY DETAIL PANEL (shared, overlays browse content)
    -- ================================================================
    ItemHistoryPanel = MarketSync.CreateItemHistoryPanel(MainFrame)
    ItemHistoryPanel:Hide()
    MainFrame.historyPanel = ItemHistoryPanel

    AnalyticsPanel = MarketSync.CreateAnalyticsPanel(MainFrame)
    AnalyticsPanel:Hide()
    MainFrame.analyticsPanel = AnalyticsPanel

    -- Back button returns to the active browse tab
    ItemHistoryPanel.backBtn:SetScript("OnClick", function()
        ItemHistoryPanel:Hide()
        -- Show the correct browse content based on active tab
        if activeBrowseTab == 1 then
            BrowseContent:Show()
        elseif activeBrowseTab == 2 then
            SyncContent:Show()
        end
        SelectTab(activeBrowseTab) -- Refreshes the title natively
    end)

    -- Global function to show item history from any browse panel
    function MarketSync.ShowItemHistory(dbKey, itemLink, name, icon, price, sourceTab)
        MarketSync.HideAllTabContent()

        if not sourceTab then
            if activeBrowseTab == 1 then
                sourceTab = "personal"
            elseif activeBrowseTab == 2 then
                sourceTab = "guild"
            elseif activeBrowseTab == 3 then
                sourceTab = "neutral"
            end
        end

        local versionStr = "v" .. tostring(GetAddOnMetadata("MarketSync", "Version") or "1.0")
        titleText:SetText(string.format("%s (%s) - Item History", MarketSync.ADDON_NAME or "MarketSync", versionStr))
        MainFrame.titleHitBox.tooltipText = nil -- No tooltip for history overlay
        ItemHistoryPanel:ShowItem(dbKey, itemLink, name, icon, price, sourceTab)
    end

    -- ================================================================
    -- TAB 6: SETTINGS
    -- ================================================================
    SettingsContent = CreateFrame("Frame", nil, MainFrame)
    SettingsContent:SetAllPoints()
    SettingsContent:Hide()
    table.insert(contentFrames, SettingsContent)

    local settingsTabTitle = SettingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsTabTitle:SetPoint("TOP", 0, -18)
    settingsTabTitle:SetTextColor(1, 0.82, 0)
    settingsTabTitle:SetText(string.format("%s (v%s) - Settings", MarketSync.ADDON_NAME or "MarketSync", GetAddOnMetadata("MarketSync", "Version") or "1.0"))

    -- Settings background (Bid tab parchment)
    local stl = SettingsContent:CreateTexture(nil, "BACKGROUND")
    stl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopLeft")
    stl:SetSize(256, 256); stl:SetPoint("TOPLEFT")
    local stm = SettingsContent:CreateTexture(nil, "BACKGROUND")
    stm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Top")
    stm:SetSize(320, 256); stm:SetPoint("TOPLEFT", 256, 0)
    local str = SettingsContent:CreateTexture(nil, "BACKGROUND")
    str:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopRight")
    str:SetSize(256, 256); str:SetPoint("TOPLEFT", stm, "TOPRIGHT")
    local sbl = SettingsContent:CreateTexture(nil, "BACKGROUND")
    sbl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotLeft")
    sbl:SetSize(256, 256); sbl:SetPoint("TOPLEFT", 0, -256)
    local sbm = SettingsContent:CreateTexture(nil, "BACKGROUND")
    sbm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Bot")
    sbm:SetSize(320, 256); sbm:SetPoint("TOPLEFT", 256, -256)
    local sbr = SettingsContent:CreateTexture(nil, "BACKGROUND")
    sbr:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotRight")
    sbr:SetSize(256, 256); sbr:SetPoint("TOPLEFT", sbm, "TOPRIGHT")

    -- --- SETTINGS UI FRAMES ---
    local function CreateBox(parent, w, h, x, y)
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetSize(w, h)
        box:SetPoint("TOPLEFT", x, y)
        box:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        box:SetBackdropColor(0, 0, 0, 0.4)
        box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        return box
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
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNotificationSounds ~= false) end
    end)

    local chkCache = CreateCheckbox(leftGlobalBox, chkNotifSound, "BOTTOMLEFT",
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

    -- ================================================================
    -- COLUMN 2: TOGGLE FEATURES
    -- ================================================================
    local header2 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header2:SetPoint("TOP", leftFeaturesBox, "TOP", 0, 16) -- Perfectly centered above the box
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

    -- --- SOUND CONTROLS ---
    local soundHeader = leftFeaturesBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    soundHeader:SetPoint("TOPLEFT", chkTooltip, "BOTTOMLEFT", 6, -10)
    soundHeader:SetText("Notification Sound")
    soundHeader:SetTextColor(1, 0.82, 0)

    -- Dropdown
    local soundDropdown = CreateFrame("Frame", "MarketSyncSoundDropdown", leftFeaturesBox, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", soundHeader, "BOTTOMLEFT", -15, -5)
    UIDropDownMenu_SetWidth(soundDropdown, 110)

    local function PlaySelectedSound()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if soundID and soundID > 0 then
            PlaySound(soundID, "Master")
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
    volSlider.Text:SetText("Alert Volume")

    volSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        MarketSyncDB.NotificationVolume = val / 100
        -- Note: Actual volume control depends on PlaySound capabilities, 
        -- but we store the preference.
    end)
    volSlider:SetScript("OnShow", function(self)
        self:SetValue((MarketSyncDB and MarketSyncDB.NotificationVolume or 1) * 100)
    end)

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

    local smartRulesFrame = CreateFrame("Frame", "MarketSyncSmartRulesFrame", UIParent, "BasicFrameTemplateWithInset")
    smartRulesFrame:SetSize(420, 280)
    smartRulesFrame:SetPoint("CENTER")
    smartRulesFrame:SetFrameStrata("DIALOG")
    smartRulesFrame.title = smartRulesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    smartRulesFrame.title:SetPoint("CENTER", smartRulesFrame.TitleBg, "CENTER", 0, 0)
    smartRulesFrame.title:SetText("Smart Bandwidth Rules")
    smartRulesFrame:Hide()

    local swDesc = smartRulesFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    swDesc:SetPoint("TOPLEFT", 15, -35)
    swDesc:SetWidth(390)
    swDesc:SetJustifyH("LEFT")
    swDesc:SetText("Automatically suspend heavy background operations to protect your network ping.")

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

    local syncLabel = smartRulesFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    syncLabel:SetPoint("TOPLEFT", 20, -75)
    syncLabel:SetText("|cffffd700Allow Swarm Sync in:|r")

    CreateSmartCheckbox(smartRulesFrame, "Combat", "AllowSyncInCombat", 25, -95)
    CreateSmartCheckbox(smartRulesFrame, "Raids", "AllowSyncInRaid", 25, -125)
    CreateSmartCheckbox(smartRulesFrame, "Dungeons / Parties", "AllowSyncInDungeon", 25, -155)
    CreateSmartCheckbox(smartRulesFrame, "Battlegrounds", "AllowSyncInPvP", 25, -185)
    CreateSmartCheckbox(smartRulesFrame, "Arenas", "AllowSyncInArena", 25, -215)

    local cacheLabel = smartRulesFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cacheLabel:SetPoint("TOPLEFT", 220, -75)
    cacheLabel:SetText("|cffffd700Allow Cache Indexer in:|r")

    CreateSmartCheckbox(smartRulesFrame, "Combat", "AllowCacheInCombat", 225, -95)
    CreateSmartCheckbox(smartRulesFrame, "Raids", "AllowCacheInRaid", 225, -125)
    CreateSmartCheckbox(smartRulesFrame, "Dungeons / Parties", "AllowCacheInDungeon", 225, -155)
    CreateSmartCheckbox(smartRulesFrame, "Battlegrounds", "AllowCacheInPvP", 225, -185)
    CreateSmartCheckbox(smartRulesFrame, "Arenas", "AllowCacheInArena", 225, -215)

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
    local userMgmtFrame = CreateFrame("Frame", "MarketSyncUserMgmt", UIParent, "BasicFrameTemplateWithInset")
    userMgmtFrame:SetSize(360, 380)
    userMgmtFrame:SetPoint("CENTER", 0, 50)
    userMgmtFrame:SetMovable(true)
    userMgmtFrame:EnableMouse(true)
    userMgmtFrame:RegisterForDrag("LeftButton")
    userMgmtFrame:SetScript("OnDragStart", userMgmtFrame.StartMoving)
    userMgmtFrame:SetScript("OnDragStop", userMgmtFrame.StopMovingOrSizing)
    userMgmtFrame:SetFrameStrata("DIALOG")
    userMgmtFrame:SetClampedToScreen(true)
    userMgmtFrame.TitleText:SetText("User Management")
    userMgmtFrame:Hide()

    -- Fix visual break in top-left corner of the Inset border
    if userMgmtFrame.Inset then
        userMgmtFrame.Inset:SetPoint("TOPLEFT", userMgmtFrame, "TOPLEFT", 4, -25)
        userMgmtFrame.Inset:SetPoint("BOTTOMRIGHT", userMgmtFrame, "BOTTOMRIGHT", -4, 4)
    end

    local umDesc = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    umDesc:SetPoint("TOPLEFT", 12, -30)
    umDesc:SetWidth(330)
    umDesc:SetJustifyH("LEFT")
    umDesc:SetText("|cff888888Block users to ignore their synced data. Blocked users' data will not be stored.|r")

    -- Column Headers
    local umUserLabel = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    umUserLabel:SetPoint("TOPLEFT", umDesc, "BOTTOMLEFT", 0, -8)
    umUserLabel:SetWidth(160)
    umUserLabel:SetJustifyH("LEFT")
    umUserLabel:SetText("|cffffd700Player|r")

    local umStatusLabel = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    umStatusLabel:SetPoint("LEFT", umUserLabel, "RIGHT", 0, 0)
    umStatusLabel:SetWidth(60)
    umStatusLabel:SetJustifyH("LEFT")
    umStatusLabel:SetText("|cffffd700Status|r")

    local umActionLabel = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    umActionLabel:SetPoint("LEFT", umStatusLabel, "RIGHT", 0, 0)
    umActionLabel:SetWidth(60)
    umActionLabel:SetJustifyH("CENTER")
    umActionLabel:SetText("|cffffd700Action|r")

    local umColSep = userMgmtFrame:CreateTexture(nil, "ARTWORK")
    umColSep:SetColorTexture(0.5, 0.5, 0.5, 0.3)
    umColSep:SetSize(320, 1)
    umColSep:SetPoint("TOPLEFT", umUserLabel, "BOTTOMLEFT", 0, -2)

    -- Scroll area for user rows
    local umScrollChild = CreateFrame("Frame", nil, userMgmtFrame)
    umScrollChild:SetPoint("TOPLEFT", umColSep, "BOTTOMLEFT", 0, -3)
    umScrollChild:SetSize(330, 260)

    local blockRows = {}

    local function RefreshUserList()
        for _, r in pairs(blockRows) do r:Hide() end
        local y = 0
        local count = 0

        local allUsers = {}
        local contributors = {}
        if MarketSync.GetSyncContributorSnapshot then
            contributors = select(1, MarketSync.GetSyncContributorSnapshot(true)) or {}
        end
        for _, user in ipairs(contributors) do
            allUsers[user] = true
        end
        if MarketSyncDB and MarketSyncDB.BlockedUsers then for u,_ in pairs(MarketSyncDB.BlockedUsers) do allUsers[u]=true end end

        local sortedUsers = {}
        for user in pairs(allUsers) do table.insert(sortedUsers, user) end
        table.sort(sortedUsers)

        for _, user in ipairs(sortedUsers) do
            count = count + 1
            local row = blockRows[count]
            if not row then
                row = CreateFrame("Frame", nil, umScrollChild)
                row:SetClipsChildren(true)
                row:SetSize(320, 20)
                row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.nameText:SetPoint("LEFT", 0, 0)
                row.nameText:SetWidth(200)
                row.nameText:SetJustifyH("LEFT")

                row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.statusText:SetPoint("LEFT", 200, 0)
                row.statusText:SetWidth(60)
                row.statusText:SetJustifyH("LEFT")

                row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.btn:SetSize(60, 18)
                row.btn:SetPoint("LEFT", 260, 0)
                row.btn:SetScript("OnClick", function(btnSelf)
                    if MarketSync.ToggleBlock then MarketSync.ToggleBlock(btnSelf.user) end
                    RefreshUserList()
                end)

                local rowSep = row:CreateTexture(nil, "BACKGROUND")
                rowSep:SetColorTexture(0.3, 0.3, 0.3, 0.2)
                rowSep:SetHeight(1)
                rowSep:SetPoint("BOTTOMLEFT", 0, 0)
                rowSep:SetPoint("BOTTOMRIGHT", 0, 0)

                blockRows[count] = row
            end
            local isBlocked = MarketSyncDB.BlockedUsers and MarketSyncDB.BlockedUsers[user]
            row.nameText:SetText(user)
            if isBlocked then
                row.statusText:SetText("|cffff0000Blocked|r")
                row.btn:SetText("Unblock")
            else
                row.statusText:SetText("|cff00ff00Active|r")
                row.btn:SetText("Block")
            end
            row.btn.user = user
            row:SetPoint("TOPLEFT", 0, -y)
            row:Show()
            y = y + 22
        end

        if count == 0 then
            if not umScrollChild.emptyText then
                umScrollChild.emptyText = umScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                umScrollChild.emptyText:SetPoint("TOPLEFT", 0, -10)
            end
            umScrollChild.emptyText:SetText("|cff888888No users synced yet.|r")
            umScrollChild.emptyText:Show()
        elseif umScrollChild.emptyText then
            umScrollChild.emptyText:Hide()
        end
    end

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
    PanelTemplates_SetNumTabs(MainFrame, #tabs)
    SelectTab(1)

    MainFrame:Hide()
    return MainFrame
end

-- ================================================================
-- Global Toggle Function
-- ================================================================
function MarketSync_ToggleUI()
    if not MainFrame then CreateMainFrame() end
    if MainFrame:IsShown() then
        MainFrame:Hide()
    else
        MainFrame:Show()
        MarketSync.BuildSearchIndex()
    end
end


