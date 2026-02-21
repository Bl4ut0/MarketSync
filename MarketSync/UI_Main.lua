-- =============================================================
-- MarketSync - Main Frame
-- Window shell, tabs, leaderboard, settings
-- =============================================================

local MainFrame, BrowseContent, SyncContent, LeaderContent, SettingsContent
local ItemHistoryPanel
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
    local titleText = MainFrame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    titleText:SetPoint("TOP", 0, -18)
    titleText:SetText("Browse Auctions")
    MainFrame.titleText = titleText
    
    -- --- SYNC MONITOR ---
    local syncMonitor = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncMonitor:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -35, -20)
    syncMonitor:SetJustifyH("RIGHT")
    syncMonitor:SetText("|cff888888Network: Idle|r")
    MainFrame.syncMonitor = syncMonitor
    
    function MarketSync.UpdateNetworkUI(txRate, rxRate, statusText)
        if MainFrame and MainFrame.syncMonitor then
            if statusText then
                MainFrame.syncMonitor:SetText(statusText)
            elseif txRate > 0 and rxRate > 0 then
                MainFrame.syncMonitor:SetText(string.format("|cff00ff00Rx: %d/s|r   |cffff8800Tx: %d/s|r", rxRate, txRate))
            elseif txRate > 0 then
                MainFrame.syncMonitor:SetText(string.format("|cffff8800Sending: %d items/sec|r", txRate))
            elseif rxRate > 0 then
                MainFrame.syncMonitor:SetText(string.format("|cff00ff00Receiving: %d items/sec|r", rxRate))
            else
                MainFrame.syncMonitor:SetText("|cff888888Network: Idle|r")
            end
        end

        if MarketSyncMonitorFrame and MarketSyncMonitorFrame:IsShown() then
            MarketSyncMonitorFrame.txLabel:SetText(string.format("|cffff8800Tx: %d items/s|r", txRate))
            MarketSyncMonitorFrame.rxLabel:SetText(string.format("|cff00ff00Rx: %d items/s|r", rxRate))
            
            if statusText then
                MarketSyncMonitorFrame.queueLabel:SetText(statusText)
            elseif txRate > 0 or rxRate > 0 then
                MarketSyncMonitorFrame.queueLabel:SetText("|cff00ff00Sync Active|r")
            elseif not IsInGuild() then
                MarketSyncMonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Disabled (No Guild)|r")
            else
                MarketSyncMonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
            end
        end
    end

    -- ================================================================
    -- BOTTOM TABS
    -- ================================================================
    local tabNames = {"Personal Scan", "Guild Sync", "Leaderboard", "Settings"}
    local tabs = {}
    local contentFrames = {}

    local function SelectTab(id)
        activeBrowseTab = id
        -- Always hide item history panel when switching tabs
        if ItemHistoryPanel then ItemHistoryPanel:Hide() end
        for i, tab in ipairs(tabs) do
            if i == id then
                PanelTemplates_SelectTab(tab)
                if contentFrames[i] then contentFrames[i]:Show() end
            else
                PanelTemplates_DeselectTab(tab)
                if contentFrames[i] then contentFrames[i]:Hide() end
            end
        end
        local titles = {"Browse Auctions (Personal Scan)", "Browse Auctions (Guild Sync)", "Sync Leaderboard", "Addon Settings"}
        titleText:SetText(titles[id] or "")
    end

    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", "AucAnnTab" .. i, MainFrame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(name)
        if i == 1 then
            tab:SetPoint("TOPLEFT", MainFrame, "BOTTOMLEFT", 60, 12)
        else
            tab:SetPoint("TOPLEFT", tabs[i-1], "TOPRIGHT", -8, 0)
        end
        tab:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = tab
    end
    MainFrame.numTabs = #tabs
    MainFrame.tabs = tabs

    -- ================================================================
    -- TAB 1 & 2: BROWSE PANELS (Personal / Guild)
    -- ================================================================
    BrowseContent = MarketSync.CreateBrowsePanel(MainFrame, "personal")
    table.insert(contentFrames, BrowseContent)

    SyncContent = MarketSync.CreateBrowsePanel(MainFrame, "guild")
    SyncContent:Hide()
    table.insert(contentFrames, SyncContent)

    -- ================================================================
    -- ITEM HISTORY DETAIL PANEL (shared, overlays browse content)
    -- ================================================================
    ItemHistoryPanel = MarketSync.CreateItemHistoryPanel(MainFrame)
    ItemHistoryPanel:Hide()
    MainFrame.historyPanel = ItemHistoryPanel

    -- Back button returns to the active browse tab
    ItemHistoryPanel.backBtn:SetScript("OnClick", function()
        ItemHistoryPanel:Hide()
        -- Show the correct browse content based on active tab
        if activeBrowseTab == 1 then
            BrowseContent:Show()
            titleText:SetText("Browse Auctions (Personal)")
        elseif activeBrowseTab == 2 then
            SyncContent:Show()
            titleText:SetText("Browse Auctions (Guild Sync)")
        end
    end)

    -- Global function to show item history from any browse panel
    function MarketSync.ShowItemHistory(dbKey, itemLink, name, icon, price)
        -- Hide the active browse content (but keep the bottom bar visible via persistent elements)
        local sourceTab = "personal"
        if activeBrowseTab == 1 then
            BrowseContent:Hide()
            sourceTab = "personal"
        elseif activeBrowseTab == 2 then
            SyncContent:Hide()
            sourceTab = "guild"
        end
        titleText:SetText("Item History")
        ItemHistoryPanel:ShowItem(dbKey, itemLink, name, icon, price, sourceTab)
    end

    -- ================================================================
    -- TAB 3: LEADERBOARD
    -- ================================================================
    LeaderContent = CreateFrame("Frame", nil, MainFrame)
    LeaderContent:SetAllPoints()
    LeaderContent:Hide()
    table.insert(contentFrames, LeaderContent)

    -- Leaderboard background (Bid tab parchment - full width)
    local ltl = LeaderContent:CreateTexture(nil, "BACKGROUND")
    ltl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopLeft")
    ltl:SetSize(256, 256); ltl:SetPoint("TOPLEFT")
    local ltm = LeaderContent:CreateTexture(nil, "BACKGROUND")
    ltm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Top")
    ltm:SetSize(320, 256); ltm:SetPoint("TOPLEFT", 256, 0)
    local ltr = LeaderContent:CreateTexture(nil, "BACKGROUND")
    ltr:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopRight")
    ltr:SetSize(256, 256); ltr:SetPoint("TOPLEFT", ltm, "TOPRIGHT")
    local lbl = LeaderContent:CreateTexture(nil, "BACKGROUND")
    lbl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotLeft")
    lbl:SetSize(256, 256); lbl:SetPoint("TOPLEFT", 0, -256)
    local lbm = LeaderContent:CreateTexture(nil, "BACKGROUND")
    lbm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Bot")
    lbm:SetSize(320, 256); lbm:SetPoint("TOPLEFT", 256, -256)
    local lbr = LeaderContent:CreateTexture(nil, "BACKGROUND")
    lbr:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotRight")
    lbr:SetSize(256, 256); lbr:SetPoint("TOPLEFT", lbm, "TOPRIGHT")

    -- Title and Toggle Buttons
    local leaderTitle = LeaderContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    leaderTitle:SetPoint("TOPLEFT", 100, -70)
    leaderTitle:SetText("Top Swarm Contributors")

    local leaderboardMode = "alltime" -- "alltime" or "weekly"

    local weeklyBtn = CreateFrame("Button", nil, LeaderContent, "UIPanelButtonTemplate")
    weeklyBtn:SetSize(100, 24)
    weeklyBtn:SetPoint("TOPLEFT", LeaderContent, "TOPRIGHT", -220, -68)
    weeklyBtn:SetText("Weekly")
    
    local allTimeBtn = CreateFrame("Button", nil, LeaderContent, "UIPanelButtonTemplate")
    allTimeBtn:SetSize(100, 24)
    allTimeBtn:SetPoint("RIGHT", weeklyBtn, "LEFT", -5, 0)
    allTimeBtn:SetText("All Time")

    -- Column Headers
    local lColNames = {"Rank", "Player Name", "Items Seeded", "Last Seen"}
    local lColWidths = {60, 220, 160, 160}
    local lColX = 100
    for i, cname in ipairs(lColNames) do
        local hdr = LeaderContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hdr:SetPoint("TOPLEFT", lColX, -110)
        hdr:SetWidth(lColWidths[i])
        hdr:SetJustifyH("LEFT")
        hdr:SetText("|cffffd700" .. cname .. "|r")
        lColX = lColX + lColWidths[i]
    end

    local sep = LeaderContent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 0.84, 0, 0.2) -- subtle gold line
    sep:SetSize(600, 1)
    sep:SetPoint("TOPLEFT", 100, -125)

    local lRows = {}
    local emptyText = LeaderContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    emptyText:SetPoint("CENTER", 0, -20)
    emptyText:Hide()
    
    local function UpdateLeaderboardUI()
        for _, r in pairs(lRows) do r:Hide() end
        emptyText:Hide()
        
        -- Update button states
        if leaderboardMode == "alltime" then
            allTimeBtn:Disable()
            weeklyBtn:Enable()
        else
            allTimeBtn:Enable()
            weeklyBtn:Disable()
        end
        
        local list = {}
        if leaderboardMode == "alltime" then
            if MarketSyncDB and MarketSync.GetRealmDB().SyncStats then
                for u, s in pairs(MarketSync.GetRealmDB().SyncStats) do
                    table.insert(list, {name=u, count=s.count, last=s.last})
                end
            end
        else
            if MarketSyncDB and MarketSync.GetRealmDB().WeeklySyncStats and MarketSync.GetRealmDB().WeeklySyncStats.data then
                for u, s in pairs(MarketSync.GetRealmDB().WeeklySyncStats.data) do
                    table.insert(list, {name=u, count=s.count, last=s.last})
                end
            end
        end
        table.sort(list, function(a,b) return a.count > b.count end)

        local y = 0
        for i, d in ipairs(list) do
            if i > 12 then break end
            local row = lRows[i]
            if not row then
                row = CreateFrame("Frame", nil, LeaderContent)
                row:SetSize(600, 22)
                row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.highlight:SetAllPoints()
                row.highlight:SetColorTexture(1, 1, 1, 0.05)
                row.rank = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); row.rank:SetPoint("LEFT", 0, 0); row.rank:SetWidth(60); row.rank:SetJustifyH("LEFT")
                row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal"); row.name:SetPoint("LEFT", 60, 0); row.name:SetWidth(220); row.name:SetJustifyH("LEFT")
                row.count = row:CreateFontString(nil, "ARTWORK", "GameFontNormal"); row.count:SetPoint("LEFT", 280, 0); row.count:SetWidth(160); row.count:SetJustifyH("LEFT")
                row.last = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); row.last:SetPoint("LEFT", 440, 0); row.last:SetWidth(160); row.last:SetJustifyH("LEFT")
                lRows[i] = row
            end

            local prefix = ""
            if i == 1 then prefix = "|cffffd700#1 |r"
            elseif i == 2 then prefix = "|cffc0c0c0#2 |r"
            elseif i == 3 then prefix = "|cffcd7f32#3 |r"
            else prefix = "|cff888888#" .. i .. " |r" end

            row.rank:SetText(prefix)
            -- Apply a class color styling to the player name if possible? Let's just use bright white for now.
            row.name:SetText("|cffffffff" .. d.name .. "|r")
            
            local function FormatCount(c)
                if c >= 1000000 then return string.format("%.1fm", c / 1000000)
                elseif c >= 1000 then return string.format("%.1fk", c / 1000)
                else return tostring(c) end
            end

            row.count:SetText("|cff00ff00" .. FormatCount(d.count) .. "|r items")

            local ago = time() - d.last
            if ago < 60 then
                row.last:SetText("Just now")
            elseif ago < 3600 then
                row.last:SetText(math.floor(ago/60) .. " min ago")
            elseif ago < 86400 then
                row.last:SetText(math.floor(ago/3600) .. " hrs ago")
            else
                row.last:SetText(math.floor(ago/86400) .. " days ago")
            end

            row:SetPoint("TOPLEFT", 100, -131 - y)
            row:Show()
            y = y + 22
        end

        if #list == 0 then
            emptyText:SetText(leaderboardMode == "alltime" and "No sync data yet. Sync with guild members to see stats!" or "No sync data this week.")
            emptyText:Show()
        end
    end
    
    weeklyBtn:SetScript("OnClick", function()
        leaderboardMode = "weekly"
        UpdateLeaderboardUI()
    end)
    
    allTimeBtn:SetScript("OnClick", function()
        leaderboardMode = "alltime"
        UpdateLeaderboardUI()
    end)

    LeaderContent:SetScript("OnShow", UpdateLeaderboardUI)

    -- ================================================================
    -- TAB 4: SETTINGS
    -- ================================================================
    SettingsContent = CreateFrame("Frame", nil, MainFrame)
    SettingsContent:SetAllPoints()
    SettingsContent:Hide()
    table.insert(contentFrames, SettingsContent)

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

    -- --- LEFT COLUMN: Sync Settings ---
    local syncHeader = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    syncHeader:SetPoint("TOPLEFT", 70, -50)
    syncHeader:SetText("|cffffd700Sync Settings|r")

    local syncSep = SettingsContent:CreateTexture(nil, "ARTWORK")
    syncSep:SetColorTexture(0, 0, 0, 0)
    syncSep:SetSize(350, 1)
    syncSep:SetPoint("TOPLEFT", syncHeader, "BOTTOMLEFT", 0, -10) -- Reduced from -20

    -- 1. Lock Minimap Button
    local chkLock = CreateFrame("CheckButton", nil, SettingsContent, "UICheckButtonTemplate")
    chkLock:SetPoint("TOPLEFT", syncSep, "BOTTOMLEFT", 0, -5)
    chkLock.text:SetText("Lock Minimap Button")
    chkLock.text:SetFontObject("GameFontHighlight")
    chkLock:SetScript("OnClick", function(self)
        if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = {} end
        MarketSyncDB.MinimapIcon.locked = self:GetChecked()
    end)
    chkLock:SetScript("OnShow", function(self)
        if MarketSyncDB and MarketSyncDB.MinimapIcon then
            self:SetChecked(MarketSyncDB.MinimapIcon.locked)
        end
    end)

    -- 2. Passive Sync
    local chkPassive = CreateFrame("CheckButton", nil, SettingsContent, "UICheckButtonTemplate")
    chkPassive:SetPoint("TOPLEFT", chkLock, "BOTTOMLEFT", 0, -4) -- Tight spacing
    chkPassive.text:SetText("Enable Passive Background Sync")
    chkPassive.text:SetFontObject("GameFontHighlight")
    chkPassive:SetScript("OnClick", function(self)
        MarketSyncDB.PassiveSync = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Passive Sync " .. (MarketSyncDB.PassiveSync and "Enabled" or "Disabled"))
    end)
    chkPassive:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.PassiveSync) end
    end)

    local passiveDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    passiveDesc:SetPoint("TOPLEFT", chkPassive, "BOTTOMLEFT", 26, 0)
    passiveDesc:SetWidth(320)
    passiveDesc:SetJustifyH("LEFT")
    passiveDesc:SetText("|cff888888Automatically receives price data from guild in background.|r")

    -- 3. Chat Price Check
    local chkChat = CreateFrame("CheckButton", nil, SettingsContent, "UICheckButtonTemplate")
    chkChat:SetPoint("TOPLEFT", passiveDesc, "BOTTOMLEFT", -26, -8)
    chkChat.text:SetText("Enable Chat Price Check '?'")
    chkChat.text:SetFontObject("GameFontHighlight")
    chkChat:SetScript("OnClick", function(self)
        MarketSyncDB.EnableChatPriceCheck = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Chat Price Check " .. (MarketSyncDB.EnableChatPriceCheck and "Enabled" or "Disabled"))
    end)
    chkChat:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableChatPriceCheck) end
    end)

    local chatDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    chatDesc:SetPoint("TOPLEFT", chkChat, "BOTTOMLEFT", 26, 0)
    chatDesc:SetWidth(320)
    chatDesc:SetJustifyH("LEFT")
    chatDesc:SetText("|cff888888Answer queries from other players using '? [Item Link]'.|r")

    -- 4. Startup Cache
    local chkCache = CreateFrame("CheckButton", nil, SettingsContent, "UICheckButtonTemplate")
    chkCache:SetPoint("TOPLEFT", chatDesc, "BOTTOMLEFT", -26, -8)
    chkCache.text:SetText("Build Item Cache on Startup")
    chkCache.text:SetFontObject("GameFontHighlight")
    chkCache:SetScript("OnClick", function(self)
        MarketSyncDB.BuildCacheOnStartup = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Startup Cache " .. (MarketSyncDB.BuildCacheOnStartup and "Enabled" or "Disabled"))
    end)
    chkCache:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.BuildCacheOnStartup) end
    end)

    local cacheDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cacheDesc:SetPoint("TOPLEFT", chkCache, "BOTTOMLEFT", 26, 0)
    cacheDesc:SetWidth(320)
    cacheDesc:SetJustifyH("LEFT")
    cacheDesc:SetText("|cff888888Pre-loads item data after login.|r")

    -- 5. Debug Mode (Last)
    local chkDebug = CreateFrame("CheckButton", nil, SettingsContent, "UICheckButtonTemplate")
    chkDebug:SetPoint("TOPLEFT", cacheDesc, "BOTTOMLEFT", -26, -8)
    chkDebug.text:SetText("Enable Debug Messages")
    chkDebug.text:SetFontObject("GameFontHighlight")
    chkDebug:SetScript("OnClick", function(self)
        MarketSyncDB.DebugMode = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Debug Mode " .. (MarketSyncDB.DebugMode and "Enabled" or "Disabled"))
    end)
    chkDebug:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.DebugMode) end
    end)

    -- --- RIGHT COLUMN: Quick Info + Cache Speed + Manage Users ---
    local rightColX = 430

    -- Right column header
    local rightHeader = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    rightHeader:SetPoint("TOPLEFT", rightColX, -50)
    rightHeader:SetText("|cffffd700Quick Info|r")

    local rightSep = SettingsContent:CreateTexture(nil, "ARTWORK")
    rightSep:SetColorTexture(0.6, 0.6, 0.6, 0.4)
    rightSep:SetSize(320, 1)
    rightSep:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -4)

    -- Right column status info
    local rightStatsText = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rightStatsText:SetPoint("TOPLEFT", rightSep, "BOTTOMLEFT", 5, -8)
    rightStatsText:SetWidth(310)
    rightStatsText:SetJustifyH("LEFT")
    rightStatsText:SetSpacing(4)
    SettingsContent.rightStatsText = rightStatsText

    -- Cache Build Speed (right column, under stats)
    local speedHeader = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    speedHeader:SetPoint("TOPLEFT", rightStatsText, "BOTTOMLEFT", -5, -14)
    speedHeader:SetText("|cffffd700Cache Build Speed|r")

    local speedSlider = CreateFrame("Slider", nil, SettingsContent, "OptionsSliderTemplate")
    speedSlider:SetPoint("TOPLEFT", speedHeader, "BOTTOMLEFT", 10, -16)
    speedSlider:SetWidth(180)
    speedSlider:SetMinMaxValues(1, 4)
    speedSlider:SetValueStep(1)
    speedSlider:SetObeyStepOnDrag(true)
    speedSlider.Low:SetText("1")
    speedSlider.High:SetText("4")

    -- Add a clean, thin track line behind the thumb so it feels anchored
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

    local speedLabel = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    speedLabel:SetPoint("LEFT", speedSlider, "RIGHT", 18, 0)
    speedLabel:SetWidth(120)
    speedLabel:SetJustifyH("LEFT")

    local speedDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    speedDesc:SetPoint("TOPLEFT", speedSlider, "BOTTOMLEFT", -10, -12)
    speedDesc:SetWidth(310)
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

    -- Manage Users button (right column, under speed)
    local btnManageUsers = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnManageUsers:SetSize(140, 22)
    btnManageUsers:SetPoint("TOPLEFT", speedDesc, "BOTTOMLEFT", 0, -14)
    btnManageUsers:SetText("Manage Users")

    local manageUsersDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    manageUsersDesc:SetPoint("LEFT", btnManageUsers, "RIGHT", 8, 0)
    manageUsersDesc:SetWidth(140)
    manageUsersDesc:SetJustifyH("LEFT")
    manageUsersDesc:SetText("|cff888888Block/unblock sync partners.|r")

    -- Open Debug Console button
    local btnNetworkMonitor = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnNetworkMonitor:SetSize(140, 22)
    btnNetworkMonitor:SetPoint("TOPLEFT", btnManageUsers, "BOTTOMLEFT", 0, -10)
    btnNetworkMonitor:SetText("Debug Console")

    local monitorDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    monitorDesc:SetPoint("LEFT", btnNetworkMonitor, "RIGHT", 8, 0)
    monitorDesc:SetWidth(150)
    monitorDesc:SetJustifyH("LEFT")
    monitorDesc:SetText("|cff888888View network stream and cache logs.|r")

    btnNetworkMonitor:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then
            MarketSync.ToggleNetworkMonitor()
        end
    end)

    -- Reset Data button
    local btnResetData = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnResetData:SetSize(140, 22)
    btnResetData:SetPoint("TOPLEFT", btnNetworkMonitor, "BOTTOMLEFT", 0, -10)
    btnResetData:SetText("Reset Data")

    local resetDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    resetDesc:SetPoint("LEFT", btnResetData, "RIGHT", 8, 0)
    resetDesc:SetWidth(150)
    resetDesc:SetJustifyH("LEFT")
    resetDesc:SetText("|cffff4444Wipe sync data & make new snapshot.|r")

    btnResetData:SetScript("OnClick", function()
        StaticPopupDialogs["MARKETSYNC_CONFIRM_RESET"] = {
            text = "Are you sure you want to reset all MarketSync data? This will clear your personal snapshot and guild sync data, but will NOT delete your local Auctionator database. A new snapshot will be created immediately.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if MarketSyncDB then
                    if MarketSync.GetRealmDB().PersonalData then wipe(MarketSync.GetRealmDB().PersonalData) end
                    if MarketSync.GetRealmDB().ItemMetadata then wipe(MarketSync.GetRealmDB().ItemMetadata) end
                    if MarketSync.GetRealmDB().HistoryLog then wipe(MarketSync.GetRealmDB().HistoryLog) end
                    if MarketSync.GetRealmDB().SyncStats then wipe(MarketSync.GetRealmDB().SyncStats) end
                    if MarketSync.GetRealmDB().WeeklySyncStats and MarketSync.GetRealmDB().WeeklySyncStats.data then wipe(MarketSync.GetRealmDB().WeeklySyncStats.data) end
                    MarketSync.GetRealmDB().PersonalScanTime = nil
                    MarketSync.GetRealmDB().CachedScanStats = nil
                end
                
                if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
                
                if MarketSync.SnapshotPersonalScan then
                    MarketSync.SnapshotPersonalScan()
                end
                
                print("|cFF00FF00[MarketSync]|r All sync data has been wiped and a new snapshot was taken.")
                
                if activeBrowseTab == 1 or activeBrowseTab == 2 then
                    if MarketSync.BuildSearchIndex then
                        MarketSync.BuildSearchIndex()
                    end
                end
                
                -- Update settings stats view if currently showing
                if MarketSyncMainFrame and MarketSyncMainFrame.UpdateRightStats then
                    MarketSyncMainFrame.UpdateRightStats()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MARKETSYNC_CONFIRM_RESET")
    end)

    -- Rebuild Cache button
    local btnRebuildIndex = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnRebuildIndex:SetSize(140, 22)
    btnRebuildIndex:SetPoint("TOPLEFT", btnResetData, "BOTTOMLEFT", 0, -10)
    btnRebuildIndex:SetText("Rebuild Caches")

    local rebuildDesc = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    rebuildDesc:SetPoint("LEFT", btnRebuildIndex, "RIGHT", 8, 0)
    rebuildDesc:SetWidth(180)
    rebuildDesc:SetJustifyH("LEFT")
    rebuildDesc:SetText("|cff888888Manually process search index.|r")

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
        if MarketSyncDB and MarketSync.GetRealmDB().SyncStats then for u,_ in pairs(MarketSync.GetRealmDB().SyncStats) do allUsers[u]=true end end
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
        local uniqueSyncers = 0
        if Auctionator and Auctionator.Database and Auctionator.Database.db then
            for _ in pairs(Auctionator.Database.db) do totalItems = totalItems + 1 end
        end
        if MarketSyncDB then
            if MarketSync.GetRealmDB().ItemMetadata then
                for _ in pairs(MarketSync.GetRealmDB().ItemMetadata) do syncedItems = syncedItems + 1 end
            end
            if MarketSync.GetRealmDB().SyncStats then
                for _ in pairs(MarketSync.GetRealmDB().SyncStats) do uniqueSyncers = uniqueSyncers + 1 end
            end
        end

        -- Cache status (using three-cache API)
        local personalCache = "Not started"
        local guildCache = "Not started"
        local idxStatus = MarketSync.GetIndexStatus and MarketSync.GetIndexStatus()
        if idxStatus then
            if idxStatus.personalPending > 0 then
                personalCache = "|cffff8800" .. idxStatus.personalResolved .. "/" .. idxStatus.personalTotal .. " (" .. idxStatus.personalPending .. " pending)|r"
            elseif idxStatus.personalReady and idxStatus.personalResolved >= idxStatus.personalTotal and idxStatus.personalTotal > 0 then
                personalCache = "|cff00ff00" .. idxStatus.personalResolved .. "/" .. idxStatus.personalTotal .. " Complete|r"
            elseif idxStatus.personalReady then
                personalCache = "|cffff8800" .. idxStatus.personalResolved .. "/" .. idxStatus.personalTotal .. " Building...|r"
            end
            if idxStatus.guildPending > 0 then
                guildCache = "|cffff8800" .. idxStatus.guildResolved .. "/" .. idxStatus.guildTotal .. " (" .. idxStatus.guildPending .. " pending)|r"
            elseif idxStatus.guildReady and idxStatus.guildResolved >= idxStatus.guildTotal and idxStatus.guildTotal > 0 then
                guildCache = "|cff00ff00" .. idxStatus.guildResolved .. "/" .. idxStatus.guildTotal .. " Complete|r"
            elseif idxStatus.guildReady then
                guildCache = "|cff00ff00" .. idxStatus.guildResolved .. "/" .. idxStatus.guildTotal .. " Complete|r"
            end
        end

        -- Right column: all stats consolidated
        local syncActiveStr = ""
        if idxStatus and idxStatus.guildSyncActive then
            syncActiveStr = "\n|cffff8800Guild Sync In Progress|r (" .. (idxStatus.guildIncoming or 0) .. " incoming)"
        end
        SettingsContent.rightStatsText:SetText(
            "|cff00ff00Total Items:|r " .. totalItems .. "  |cff00ff00Synced:|r " .. syncedItems .. "\n" ..
            "|cff00ff00Personal Cache:|r " .. personalCache .. "\n" ..
            "|cff00ff00Guild Cache:|r " .. guildCache .. "\n" ..
            "|cff00ff00Sync Partners:|r " .. uniqueSyncers ..
            syncActiveStr
        )
    end

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


