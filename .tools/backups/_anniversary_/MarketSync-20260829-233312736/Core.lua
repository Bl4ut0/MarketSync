-- =============================================================
-- MarketSync - Init, Minimap, Options, Slash Commands
-- Entry point that ties all modules together
-- =============================================================

local ADDON_NAME = MarketSync.ADDON_NAME
local category  -- Forward declaration for minimap/options access

-- ================================================================
-- MINIMAP BUTTON
-- ================================================================
local function CreateMinimapButton()
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false, minimapPos = 225 } end
    
    local ldb = LibStub("LibDataBroker-1.1")
    local icon = LibStub("LibDBIcon-1.0")

    local MarketSyncLDB = ldb:NewDataObject("MarketSync", {
        type = "launcher",
        text = "MarketSync",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        OnClick = function(self, button)
            if button == "RightButton" then
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                    -- Switch to Settings tab (Tab 6)
                    if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[6] then
                        MarketSyncMainFrame.tabs[6]:Click()
                    end
                end
            elseif button == "MiddleButton" then
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                    -- Switch to Notifications tab (Tab 5)
                    if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[5] then
                        MarketSyncMainFrame.tabs[5]:Click()
                    end
                end
            else
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("MarketSync")
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFF00FF00Left-Click|r to Open Window")
            tooltip:AddLine("|cFF00FF00Middle-Click|r for Notifications")
            tooltip:AddLine("|cFF00FF00Right-Click|r for Settings")
            local unread = tonumber(MarketSync.NotificationUnreadCount) or 0
            if unread > 0 then
                tooltip:AddLine(string.format("|cffff4444%d unacknowledged alert(s)|r", unread))
            end
        end,
    })

    icon:Register("MarketSync", MarketSyncLDB, MarketSyncDB.MinimapIcon)
    
    -- Re-implement Flashing Overlay on the frame LibDBIcon created
    local btn = icon:GetMinimapButton("MarketSync")
    if btn then
        local flash = btn:CreateTexture(nil, "OVERLAY")
        flash:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        flash:SetBlendMode("ADD")
        flash:SetAllPoints()
        flash:Hide()
        btn.flash = flash

        local flashGroup = flash:CreateAnimationGroup()
        local alpha = flashGroup:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.5)
        alpha:SetOrder(1)
        local alpha2 = flashGroup:CreateAnimation("Alpha")
        alpha2:SetFromAlpha(1)
        alpha2:SetToAlpha(0)
        alpha2:SetDuration(0.5)
        alpha2:SetOrder(2)
        flashGroup:SetLooping("REPEAT")

        function MarketSync.StartMinimapFlash()
            if not flash:IsShown() then
                flash:Show()
                flashGroup:Play()
            end
        end

        function MarketSync.StopMinimapFlash()
            if flash:IsShown() then
                flashGroup:Stop()
                flash:Hide()
            end
        end
        if (tonumber(MarketSync.NotificationUnreadCount) or 0) > 0
            and MarketSyncDB.EnableMinimapAlerts ~= false then
            MarketSync.StartMinimapFlash()
        end
    end
end

-- ================================================================
-- INTERFACE OPTIONS PANEL
-- ================================================================

-- Main Panel
local panel = CreateFrame("Frame", "MarketSyncConfig", UIParent)
panel.name = "MarketSync"
category = Settings and Settings.RegisterCanvasLayoutCategory(panel, panel.name) or InterfaceOptions_AddCategory(panel)
if Settings then Settings.RegisterAddOnCategory(category) end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("MarketSync")

local subText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subText:SetText("MarketSync settings are managed within the main addon window.")

local btnOpen = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btnOpen:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -20)
btnOpen:SetSize(160, 25)
btnOpen:SetText("Open MarketSync")
btnOpen:SetScript("OnClick", function()
    if MarketSync_ToggleUI then MarketSync_ToggleUI() end
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
end)

local btnSettings = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btnSettings:SetPoint("LEFT", btnOpen, "RIGHT", 10, 0)
btnSettings:SetSize(160, 25)
btnSettings:SetText("Open Settings")
btnSettings:SetScript("OnClick", function()
    if MarketSync_ToggleUI then
        MarketSync_ToggleUI()
        -- Switch to Settings tab (Tab 6)
        if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[6] then
            MarketSyncMainFrame.tabs[6]:Click()
        end
    end
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
end)

-- Lock button moved to Main UI Settings tab

-- ================================================================
-- STAGED INITIALIZATION
-- ================================================================
-- Stage 1 (immediate):  DB defaults + minimap â€” zero DB iteration
-- Stage 2 (45s):        Passive sync â€” lightweight guild advertisements
-- Stage 3 (90s):        Search index cache â€” heavy coroutine, only if enabled
-- On-Demand:            Opening the Browse UI always triggers cache build
-- ================================================================
local auctionatorDBUpdateRegistered = false
local auctionatorFullScanRegistered = false
local auctionatorSetPriceHookInstalled = false
local auctionatorProcessScanHookInstalled = false
local auctionatorFullScanListener = {}
local auctionatorDBSnapshotPending = false
local suppressNextScheduledDBSnapshot = false
local pendingAuctionatorKeys = {}
local fullScanState = {
    active = false,
    scope = nil,
    keys = nil,
}
local lastProcessScanKeys = nil
local ScheduleAuctionatorDBSnapshot

local function IsNeutralCaptureActive()
    return MarketSync.IsNeutralAHOpen
        or (MarketSync.IsNeutralAHSession and MarketSync.IsNeutralAHSession())
end

local function SnapshotAuctionatorChanges(authoritative, exactKeys)
    if IsNeutralCaptureActive() or not MarketSync.SnapshotPersonalScan then
        return false
    end

    -- Partial/search records are valid and may update alerts, but only the exact
    -- FullScan listener opts into advancing the outbound bucket revision.
    local ok, count, todayCount, changedCount = pcall(MarketSync.SnapshotPersonalScan, {
        evaluateNotifications = true,
        authoritative = authoritative == true,
        keys = exactKeys,
        exactKeys = exactKeys ~= nil,
    })
    if not ok then
        MarketSync.Debug("Auctionator DB snapshot failed: " .. tostring(count))
        return false
    end
    if (tonumber(changedCount) or 0) > 0 and MarketSync.InvalidateIndexCache then
        MarketSync.InvalidateIndexCache()
    end
    return true, count, todayCount, changedCount
end

local function ResetFullScanState()
    fullScanState.active = false
    fullScanState.scope = nil
    fullScanState.keys = nil
end

local function HandleAuctionatorFullScanStart()
    -- Do not let an earlier partial observation become part of this scan's
    -- authoritative key set. A pending timer will simply find no keys.
    pendingAuctionatorKeys = {}
    lastProcessScanKeys = nil
    fullScanState.active = true
    fullScanState.scope = IsNeutralCaptureActive() and "N" or "M"
    fullScanState.keys = auctionatorSetPriceHookInstalled and {} or nil

    if fullScanState.scope == "N" and MarketSync.BeginNeutralFullScan then
        MarketSync.BeginNeutralFullScan()
    end
end

local function HandleAuctionatorFullScanFailed()
    local failedScope = fullScanState.scope
    ResetFullScanState()
    lastProcessScanKeys = nil
    pendingAuctionatorKeys = {}
    if failedScope == "N" and MarketSync.FailNeutralFullScan then
        MarketSync.FailNeutralFullScan()
    end
end

local function HandleAuctionatorFullScanComplete()
    local completedScope = fullScanState.scope or (IsNeutralCaptureActive() and "N" or "M")
    local completedKeys = fullScanState.keys or lastProcessScanKeys
    ResetFullScanState()
    lastProcessScanKeys = nil
    pendingAuctionatorKeys = {}

    if completedScope == "N" then
        suppressNextScheduledDBSnapshot = auctionatorDBUpdateRegistered
        if MarketSync.CompleteNeutralFullScan then
            MarketSync.CompleteNeutralFullScan(completedKeys)
        end
        return
    end

    -- Without an exact key source a FullScan completion must fail closed. A
    -- whole-database sweep could certify prices injected by guild sync or an
    -- unrelated partial search.
    if completedKeys == nil then
        suppressNextScheduledDBSnapshot = auctionatorDBUpdateRegistered
        MarketSync.Debug("Full scan completed without exact changed keys; outbound freshness was not advanced")
        return
    end

    -- A precise Auctionator FullScan completion event is the only main-AH event
    -- authorized to advance freshness or advertise a new personal snapshot.
    local ok, _, todayCount = SnapshotAuctionatorChanges(true, completedKeys)
    if not ok then return end
    suppressNextScheduledDBSnapshot = auctionatorDBUpdateRegistered

    local realmDB = MarketSync.GetRealmDB()
    local now = time()
    local today = MarketSync.GetCurrentScanDay()
    realmDB.PersonalScanTime = now
    realmDB.SwarmTSF = now
    realmDB.CachedScanStats = nil
    if MarketSync.GetMyLatestScanDay and MarketSync.GetMyLatestScanDay() == today then
        realmDB.LastCountDay = today
        realmDB.LastTodayCount = tonumber(todayCount) or 0
    end

    if MarketSync.InvalidateIndexCache then
        MarketSync.InvalidateIndexCache()
    end
    if MarketSync.BuildSearchIndex then
        C_Timer.After(1, function()
            if MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end
        end)
    end
    if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
        C_Timer.After(2, function()
            if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end
        end)
    end
end

ScheduleAuctionatorDBSnapshot = function()
    if auctionatorDBSnapshotPending then return end
    auctionatorDBSnapshotPending = true
    C_Timer.After(0, function()
        auctionatorDBSnapshotPending = false
        -- RegisterForDBUpdate also contains ScanComplete. Its deferred generic
        -- pass is redundant when the exact listener just committed the same DB.
        if suppressNextScheduledDBSnapshot then
            suppressNextScheduledDBSnapshot = false
            return
        end
        if fullScanState.active or IsNeutralCaptureActive() then
            return
        end

        local exactKeys = pendingAuctionatorKeys
        pendingAuctionatorKeys = {}
        if not auctionatorSetPriceHookInstalled or not next(exactKeys) then
            return
        end
        SnapshotAuctionatorChanges(false, exactKeys)
    end)
end

function auctionatorFullScanListener:ReceiveEvent(eventName)
    local events = Auctionator and Auctionator.FullScan and Auctionator.FullScan.Events
    if not events then return end

    local handler
    if events.ScanStart and eventName == events.ScanStart then
        handler = HandleAuctionatorFullScanStart
    elseif events.ScanComplete and eventName == events.ScanComplete then
        handler = HandleAuctionatorFullScanComplete
    elseif events.ScanFailed and eventName == events.ScanFailed then
        handler = HandleAuctionatorFullScanFailed
    end
    if handler then
        local ok, err = pcall(handler)
        if not ok then
            ResetFullScanState()
            if MarketSync.FailNeutralFullScan then
                pcall(MarketSync.FailNeutralFullScan)
            end
            MarketSync.Debug("Auctionator FullScan event failed: " .. tostring(err))
        end
    end
end

local function RegisterAuctionatorCallbacks()
    if not auctionatorSetPriceHookInstalled
        and Auctionator and Auctionator.Database
        and type(Auctionator.Database.SetPrice) == "function"
        and type(hooksecurefunc) == "function" then
        local ok, err = pcall(hooksecurefunc, Auctionator.Database, "SetPrice", function(_, dbKey)
            if dbKey == nil then return end
            if fullScanState.active then
                if fullScanState.keys then
                    fullScanState.keys[dbKey] = true
                end
                return
            end
            if IsNeutralCaptureActive() then return end
            pendingAuctionatorKeys[dbKey] = true
            ScheduleAuctionatorDBSnapshot()
        end)
        if ok then
            auctionatorSetPriceHookInstalled = true
        else
            MarketSync.Debug("Auctionator SetPrice tracking hook unavailable: " .. tostring(err))
        end
    end

    if not auctionatorProcessScanHookInstalled
        and Auctionator and Auctionator.Database
        and type(Auctionator.Database.ProcessScan) == "function"
        and type(hooksecurefunc) == "function" then
        local ok, err = pcall(hooksecurefunc, Auctionator.Database, "ProcessScan", function(_, itemIndexes)
            if type(itemIndexes) ~= "table" then return end
            local keys = {}
            for dbKey in pairs(itemIndexes) do keys[dbKey] = true end
            lastProcessScanKeys = keys
            if fullScanState.active then
                fullScanState.keys = keys
            end
        end)
        if ok then
            auctionatorProcessScanHookInstalled = true
        else
            MarketSync.Debug("Auctionator ProcessScan tracking hook unavailable: " .. tostring(err))
        end
    end

    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not auctionatorDBUpdateRegistered and api and type(api.RegisterForDBUpdate) == "function" then
        local ok, err = pcall(api.RegisterForDBUpdate, ADDON_NAME, function()
            ScheduleAuctionatorDBSnapshot()
        end)
        if ok then
            auctionatorDBUpdateRegistered = true
        else
            MarketSync.Debug("Auctionator DB update callback unavailable: " .. tostring(err))
        end
    end

    local eventBus = Auctionator and Auctionator.EventBus
    local events = Auctionator and Auctionator.FullScan and Auctionator.FullScan.Events
    if not auctionatorFullScanRegistered and eventBus and type(eventBus.Register) == "function"
        and events and events.ScanComplete then
        local fullScanEvents = {}
        if events.ScanStart then table.insert(fullScanEvents, events.ScanStart) end
        table.insert(fullScanEvents, events.ScanComplete)
        if events.ScanFailed then table.insert(fullScanEvents, events.ScanFailed) end
        local ok, err = pcall(eventBus.Register, eventBus, auctionatorFullScanListener, fullScanEvents)
        if ok then
            auctionatorFullScanRegistered = true
        else
            MarketSync.Debug("Auctionator FullScan listener unavailable: " .. tostring(err))
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    -- Handle both the legacy folder name and the new name
    if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == "AuctionatorAnnouncer") then
        -- STAGE 1: Bare minimum â€” no DB iteration at all
        MarketSync.InitializeDB()
        if MarketSync.EnsureVerifiedSnapshotSchema then
            MarketSync.EnsureVerifiedSnapshotSchema()
        end
        if MarketSync.RefreshNotificationUnreadState then
            MarketSync.RefreshNotificationUnreadState()
        end
        CreateMinimapButton()
        RegisterAuctionatorCallbacks()

        -- FIRST LAUNCH PROTECTION: If the user doesn't have an offline personal snapshot pool yet,
        -- forcibly snapshot whatever exists in their Live Auctionator DB into the mirror pool right now.
        -- This guarantees new users don't see an empty "Personal Snapshot" screen if they've used Auctionator before.
        -- IMPORTANT: If PersonalScanTime exists, the user has already done a real AH scan and their
        -- PersonalData is sacred â€” never overwrite it on boot (guild sync grows the live DB, which
        -- would otherwise trigger the migration check every login).
        C_Timer.After(5, function()
            local hasPersonalScan = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime
            if hasPersonalScan then return end  -- Sacred personal scan exists, do not touch

            local needsSnapshot = false
            if MarketSyncDB and MarketSync.GetRealmDB().PersonalData then
                local pdCount = 0
                for _ in pairs(MarketSync.GetRealmDB().PersonalData) do pdCount = pdCount + 1 end

                local auctCount = 0
                if Auctionator and Auctionator.Database and Auctionator.Database.db then
                    for _ in pairs(Auctionator.Database.db) do auctCount = auctCount + 1 end
                end

                if pdCount == 0 then
                    needsSnapshot = true  -- First launch, no data at all
                elseif auctCount > pdCount + 500 then
                    needsSnapshot = true  -- Pre-0.4.5 data without variant keys
                    if MarketSyncDB and MarketSyncDB.DebugMode then
                        print("|cFF00FF00[MarketSync]|r Migration: PersonalData is missing variant keys (" .. pdCount .. " vs " .. auctCount .. "), re-snapshotting...")
                    end
                end
            else
                needsSnapshot = true
            end
            if needsSnapshot and MarketSync.SnapshotPersonalScan then
                MarketSync.SnapshotPersonalScan()
            end
        end)

        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- STAGE 2: Passive sync (45s) â€” sets up guild advertisement ticker
        C_Timer.After(45, function()
            -- ... (rest of stage 2)
            MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName()
            MarketSync.StartPassiveSync()
            if MarketSyncDB and MarketSyncDB.DebugMode then
                print("|cFF00FF00[MarketSync]|r Stage 2: Passive sync started (45s)")
            end
        end)

        -- STAGE 2.5: Metadata pruning (60s) â€” trim stale ItemMetadata to prevent RAM bloat
        C_Timer.After(60, function()
            if MarketSync.PruneMetadata then
                MarketSync.PruneMetadata()
            end
        end)

        -- STAGE 3: Search index cache (90s) â€” only if user opted in
        C_Timer.After(90, function()
            if MarketSyncDB and MarketSyncDB.BuildCacheOnStartup then
                if MarketSyncDB.DebugMode then
                    print("|cFF00FF00[MarketSync]|r Stage 3: Building search index (90s)")
                end
                if MarketSync.BuildSearchIndex then
                    MarketSync.BuildSearchIndex()
                end
            end
        end)

        -- STAGE 4: Time-Series Purge (120s) â€” cleanly prune granular history older than PurgeCycle
        C_Timer.After(120, function()
            if not MarketSyncDB or type(MarketSyncDB.PurgeCycleDays) ~= "number" then return end
            -- "Infinite" translates to e.g. 9999 or simply not pruning if set to 0. 
            -- Let's say if it's 0, it means infinite.
            if MarketSyncDB.PurgeCycleDays <= 0 then return end

            local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
            if not realmDB or not realmDB.PersonalData then return end

            local currentDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or math.floor(time() / 86400)
            local cutoffDay = currentDay - MarketSyncDB.PurgeCycleDays
            local deletedStringCount = 0

            if MarketSyncDB.DebugMode then
                print("|cFF00FF00[MarketSync]|r Stage 4: Pruning History Strings older than Day " .. cutoffDay)
            end

            -- Coroutine to prevent execution stall when iterating thousands of items
            local co = coroutine.create(function()
                local i = 0
                for _, data in pairs(realmDB.PersonalData) do
                    if type(data) == "table" and data.h then
                        for dayStr, _ in pairs(data.h) do
                            local dayNum = tonumber(dayStr)
                            if dayNum and dayNum < cutoffDay then
                                data.h[dayStr] = nil
                                deletedStringCount = deletedStringCount + 1
                            end
                        end
                    end
                    if type(data) == "table" and data.vh then
                        for dayStr in pairs(data.vh) do
                            local dayNum = tonumber(dayStr)
                            if dayNum and dayNum < cutoffDay then
                                data.vh[dayStr] = nil
                                deletedStringCount = deletedStringCount + 1
                            end
                        end
                    end
                    i = i + 1
                    if i % 1000 == 0 then coroutine.yield() end
                end

                if MarketSyncDB.DebugMode and deletedStringCount > 0 then
                    print("|cFF00FF00[MarketSync]|r Pruned " .. deletedStringCount .. " stale history string points.")
                end
            end)
            
            local function RunChunk()
                if coroutine.status(co) ~= "dead" then
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        MarketSync.Debug("Error in Timeseries Purge coroutine: " .. tostring(err))
                    else
                        C_Timer.After(0.05, RunChunk)
                    end
                end
            end
            RunChunk()
        end)

        -- Register for AH events so we can invalidate the scan cache dynamically
        self:RegisterEvent("AUCTION_HOUSE_CLOSED")
        self:RegisterEvent("AUCTION_HOUSE_SHOW")

        -- Register for Smart Rules state tracking (combat/instance transitions)
        self:RegisterEvent("PLAYER_REGEN_DISABLED")   -- Entering combat
        self:RegisterEvent("PLAYER_REGEN_ENABLED")    -- Leaving combat
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")   -- Entering/leaving instances
        self:RegisterEvent("SKILL_LINES_CHANGED")
        self:RegisterEvent("TRADE_SKILL_SHOW")
        self:RegisterEvent("TRADE_SKILL_UPDATE")
        if MarketSync.RefreshKnownProfessionCache then
            MarketSync.RefreshKnownProfessionCache()
        end
        MarketSync._lastCanSync = MarketSync.CanSync and MarketSync.CanSync() or true

    elseif event == "AUCTION_HOUSE_SHOW" then
        MarketSync.IsAuctionHouseOpen = true
        MarketSync.IsNeutralAHOpen = false

        if MarketSync.HandleAuctionHouseShown then
            local ok, isNeutral = pcall(MarketSync.HandleAuctionHouseShown)
            if ok then
                MarketSync.IsNeutralAHOpen = isNeutral and true or false
            else
                MarketSync.Debug("Neutral AH show hook failed: " .. tostring(isNeutral))
            end
        end

    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- Some WoW edge cases can fire a close without a preceding show. Ignore
        -- those so neutral-session cleanup is never run against an unknown AH.
        if not MarketSync.IsAuctionHouseOpen then
            MarketSync.Debug("AUCTION_HOUSE_CLOSED fired but AH was never opened â€” ignoring (spurious event)")
            return
        end
        MarketSync.IsAuctionHouseOpen = false
        local wasNeutralSession = MarketSync.IsNeutralAHOpen
        MarketSync.IsNeutralAHOpen = false

        if MarketSync.HandleAuctionHouseClosed then
            local ok, wasNeutral = pcall(MarketSync.HandleAuctionHouseClosed)
            if ok and wasNeutral then
                wasNeutralSession = true
            elseif not ok then
                MarketSync.Debug("Neutral AH close hook failed: " .. tostring(wasNeutral))
            end
        end

        if wasNeutralSession then
            return
        end
        if MarketSyncDB then
            -- Auctionator's DB events already copied valid price changes. Closing
            -- the AH alone is not evidence that a full scan completed.
            MarketSync.GetRealmDB().CachedScanStats = nil
        end
    -- Keep known profession recipes in sync with the player's profession book.
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "SKILL_LINES_CHANGED" then
        if MarketSync.RefreshKnownProfessionCache then
            MarketSync.RefreshKnownProfessionCache()
        end
        if event == "SKILL_LINES_CHANGED" then
            return
        end
        if MarketSync.RefreshKnownCraftingRecipes then
            MarketSync.RefreshKnownCraftingRecipes()
        end

    -- ================================================================
    -- SMART RULES: State Transition Logging
    -- Detect when sync eligibility changes and log the reason
    -- ================================================================
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
        or event == "ZONE_CHANGED_NEW_AREA" then

        -- Short delay to let WoW state settle (IsInInstance can lag slightly on zone transitions)
        C_Timer.After(0.5, function()
            if not MarketSync.CanSync then return end
            local canNow = MarketSync.CanSync()
            local couldBefore = MarketSync._lastCanSync

            if canNow ~= couldBefore then
                MarketSync._lastCanSync = canNow

                -- Determine the specific reason for the state change
                local reason = ""
                if not canNow then
                    -- Identify why sync was disabled
                    if InCombatLockdown and InCombatLockdown() then
                        reason = "Entered Combat"
                    elseif IsInInstance then
                        local inInstance, instanceType = IsInInstance()
                        if inInstance then
                            if instanceType == "raid" then reason = "Entered Raid"
                            elseif instanceType == "party" then reason = "Entered Dungeon"
                            elseif instanceType == "pvp" then reason = "Entered Battleground"
                            elseif instanceType == "arena" then reason = "Entered Arena"
                            else reason = "Entered Instance (" .. (instanceType or "unknown") .. ")"
                            end
                        end
                    end
                    if reason == "" then reason = "Smart Rules" end

                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent("|cffff4444[Smart Rules]|r Sync |cffff4444DISABLED|r â€” " .. reason)
                    end
                    MarketSync.Debug("Smart Rules: Sync DISABLED â€” " .. reason)
                    if MarketSync.UpdateSwarmUI then
                        MarketSync.UpdateSwarmUI(UnitName("player"), "Paused (" .. reason .. ")")
                    end
                    if MarketSync.SetPullRequestPending then
                        MarketSync.SetPullRequestPending(false)
                    end
                else
                    -- Identify why sync was re-enabled
                    if event == "PLAYER_REGEN_ENABLED" then
                        reason = "Left Combat"
                    elseif event == "ZONE_CHANGED_NEW_AREA" then
                        reason = "Left Instance"
                    else
                        reason = "Conditions cleared"
                    end

                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent("|cff44ff44[Smart Rules]|r Sync |cff44ff44ENABLED|r â€” " .. reason)
                    end
                    MarketSync.Debug("Smart Rules: Sync ENABLED â€” " .. reason)
                    if MarketSync.UpdateSwarmUI then
                        MarketSync.UpdateSwarmUI(UnitName("player"), nil)
                    end

                    -- If a fresher ADV was deferred while we were blocked, process it now.
                    if MarketSync.ProcessDeferredADV then
                        C_Timer.After(0.5, function()
                            if MarketSync.ProcessDeferredADV then
                                MarketSync.ProcessDeferredADV()
                            end
                        end)
                    end
                end
            end
        end)
    end
end)

-- ================================================================
-- SLASH COMMANDS
-- ================================================================
SLASH_MarketSync1 = "/marketsync"
SLASH_MarketSync2 = "/ms"
SLASH_MarketSync3 = "/aucann"
SlashCmdList["MarketSync"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "search" or cmd == "browse" or cmd == "ui" then
        if MarketSync_ToggleUI then
            MarketSync_ToggleUI()
        end
    elseif cmd == "stats" or cmd == "config" then
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(category:GetID())
        else
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    elseif cmd == "block" then
        if #arg > 0 then MarketSync.ToggleBlock(arg) else print("Usage: /ms block [playername]") end
    elseif cmd == "unblock" then
        if #arg > 0 then MarketSync.ToggleBlock(arg) else print("Usage: /ms unblock [playername]") end
    else
        print("|cFF00FF00[MarketSync]|r Commands:")
        print("  /ms search - Open the browse window.")
        print("  /ms config - Open settings panel.")
        print("  /ms block [name] - Block a sender.")
    end
end
