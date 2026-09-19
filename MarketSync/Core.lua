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
                    -- Switch to Settings tab (Tab 7)
                    if MarketSync.SelectMainFrameTab then
                        MarketSync.SelectMainFrameTab(7)
                    elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[7] then
                        MarketSyncMainFrame.tabs[7]:Click()
                    end
                end
            elseif button == "MiddleButton" then
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                    -- Switch to Alerts tab (Tab 6)
                    if MarketSync.SelectMainFrameTab then
                        MarketSync.SelectMainFrameTab(6)
                    elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[6] then
                        MarketSyncMainFrame.tabs[6]:Click()
                    end
                end
            else
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                end
            end
            -- Stop flashing on any click
            if MarketSync.StopMinimapFlash then
                MarketSync.StopMinimapFlash()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("MarketSync")
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFF00FF00Left-Click|r to Open Window")
            tooltip:AddLine("|cFF00FF00Middle-Click|r for Notifications")
            tooltip:AddLine("|cFF00FF00Right-Click|r for Settings")
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
    end
end

-- ================================================================
-- INTERFACE OPTIONS PANEL
-- ================================================================

-- Main Panel
local panel = CreateFrame("Frame", "MarketSyncConfig", UIParent)
panel.name = "MarketSync"
category = (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutCategory(panel, panel.name)) or (InterfaceOptions_AddCategory and InterfaceOptions_AddCategory(panel))
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
    HideUIPanel(SettingsPanel)
    HideUIPanel(InterfaceOptionsFrame)
end)

local btnSettings = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btnSettings:SetPoint("LEFT", btnOpen, "RIGHT", 10, 0)
btnSettings:SetSize(160, 25)
btnSettings:SetText("Open Settings")
btnSettings:SetScript("OnClick", function()
    if MarketSync_ToggleUI then
        MarketSync_ToggleUI()
        -- Switch to Settings tab (Tab 7)
        if MarketSync.SelectMainFrameTab then
            MarketSync.SelectMainFrameTab(7)
        elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[7] then
            MarketSyncMainFrame.tabs[7]:Click()
        end
    end
    HideUIPanel(SettingsPanel)
    HideUIPanel(InterfaceOptionsFrame)
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
local auctionatorHooksInstalled = false
local function RegisterAuctionatorHooks()
    if auctionatorHooksInstalled then return end
    if not (Auctionator and Auctionator.Database) then return end

    if type(Auctionator.Database.SetPrice) == "function" and type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, Auctionator.Database, "SetPrice", function(_, dbKey)
            if dbKey and MarketSync.IsAuctionHouseOpen and not MarketSync.IsNeutralAHOpen then
                MarketSync._ahScanActivity = (MarketSync._ahScanActivity or 0) + 1
            end
        end)
    end

    if type(Auctionator.Database.ProcessScan) == "function" and type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, Auctionator.Database, "ProcessScan", function(_, itemIndexes)
            if type(itemIndexes) == "table" and next(itemIndexes) and MarketSync.IsAuctionHouseOpen and not MarketSync.IsNeutralAHOpen then
                MarketSync._ahScanActivity = (MarketSync._ahScanActivity or 0) + 1
                MarketSync._ahFullScanCompleted = true
            end
        end)
    end

    local eventBus = Auctionator.EventBus
    local events = Auctionator.FullScan and Auctionator.FullScan.Events
    if eventBus and type(eventBus.Register) == "function" and events and events.ScanComplete then
        local listener = {}
        function listener:ReceiveEvent(eventName)
            if eventName == events.ScanComplete then
                MarketSync._ahFullScanCompleted = true
                if not MarketSync.IsNeutralAHOpen and MarketSync.SnapshotPersonalScan then
                    local _, todayCount = MarketSync.SnapshotPersonalScan()
                    local now = time()
                    local today = MarketSync.GetCurrentScanDay()
                    local realmDB = MarketSync.GetRealmDB()
                    realmDB.PersonalScanTime = now
                    realmDB.SwarmTSF = now
                    if MarketSync.GetMyLatestScanDay and MarketSync.GetMyLatestScanDay() == today then
                        realmDB.LastCountDay = today
                        realmDB.LastTodayCount = todayCount
                    end
                    if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
                    if MarketSync.BuildSearchIndex then
                        C_Timer.After(1, function() if MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end end)
                    end
                    if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                        C_Timer.After(2, function() if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end end)
                    end
                end
            end
        end
        pcall(eventBus.Register, eventBus, listener, { events.ScanComplete })
    end

    auctionatorHooksInstalled = true
end

local function SafeRegisterEvent(frame, eventName)
    if frame and eventName then
        pcall(frame.RegisterEvent, frame, eventName)
    end
end
-- ================================================================
-- TIERED RETENTION DOWNSAMPLER
-- Hot (0-7d):    full 30-min resolution (synced via guild swarm)
-- Warm (8-30d):  daily compact summaries (D:min:max:avg:vol, local)
-- Cold (31-180d): weekly compact summaries (W:min:max:avg:vol, local)
-- Purge (>180d): hard deleted
-- Fixes memory leak: strips data.vh older than Hot cutoff (7d)
-- ================================================================
function MarketSync.DownsampleRetention(onComplete)
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if not realmDB or not realmDB.PersonalData then
        if onComplete then onComplete(0, 0, 0, 0) end
        return
    end

    local currentDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or math.floor(time() / 86400)
    local hotDays = MarketSync.RETENTION_HOT_DAYS or 7
    local warmDays = MarketSync.RETENTION_WARM_DAYS or 30
    local coldDays = MarketSync.RETENTION_COLD_DAYS or 180

    local hotCutoff  = currentDay - hotDays
    local warmCutoff = currentDay - warmDays
    local coldCutoff = currentDay - coldDays

    local compactedDailyCount = 0
    local compactedWeeklyCount = 0
    local purgedCount = 0
    local vhPrunedCount = 0

    if MarketSyncDB and MarketSyncDB.DebugMode then
        print(string.format("|cFF00FF00[MarketSync]|r Downsampling retention (Hot: %dd, Warm: %dd, Cold: %dd)",
            hotDays, warmDays, coldDays))
    end

    local co = coroutine.create(function()
        local i = 0
        for dbKey, data in pairs(realmDB.PersonalData) do
            if type(data) == "table" and data.h then
                local weeklyBuckets = {}

                for dayKey, histStr in pairs(data.h) do
                    if type(dayKey) == "string" and dayKey:sub(1, 2) == "W_" then
                        -- Cold weekly record
                        local weekNum = tonumber(dayKey:sub(3))
                        if weekNum then
                            local weekAnchorDay = weekNum * 7
                            if weekAnchorDay < coldCutoff then
                                data.h[dayKey] = nil
                                purgedCount = purgedCount + 1
                            end
                        end
                    else
                        local dayNum = tonumber(dayKey)
                        if dayNum then
                            if dayNum < coldCutoff then
                                -- Beyond cold tier: hard purge
                                data.h[dayKey] = nil
                                purgedCount = purgedCount + 1
                            elseif dayNum < warmCutoff then
                                -- Warm -> Cold: accumulate into weekly summary
                                local weekNum = math.floor(dayNum / 7)
                                local weekKey = "W_" .. tostring(weekNum)
                                local rec = MarketSync.ParseCompactRecord(histStr)
                                if not rec and not MarketSync.IsCompactRecord(histStr) then
                                    local compacted = MarketSync.CompactDayString(histStr)
                                    if compacted then
                                        rec = MarketSync.ParseCompactRecord(compacted)
                                    end
                                end
                                if rec then
                                    weeklyBuckets[weekKey] = MarketSync.MergeCompactRecords(
                                        weeklyBuckets[weekKey], rec)
                                end
                                data.h[dayKey] = nil
                                compactedWeeklyCount = compactedWeeklyCount + 1
                            elseif dayNum < hotCutoff then
                                -- Hot -> Warm: convert raw buckets to daily summary
                                if not MarketSync.IsCompactRecord(histStr) then
                                    local compacted = MarketSync.CompactDayString(histStr)
                                    if compacted then
                                        data.h[dayKey] = compacted
                                        compactedDailyCount = compactedDailyCount + 1
                                    end
                                end
                            end
                        end
                    end
                end

                -- Flush accumulated weekly records
                for weekKey, wRec in pairs(weeklyBuckets) do
                    local existingStr = data.h[weekKey]
                    if existingStr then
                        local existingRec = MarketSync.ParseCompactRecord(existingStr)
                        if existingRec then
                            wRec = MarketSync.MergeCompactRecords(existingRec, wRec)
                        end
                    end
                    data.h[weekKey] = string.format("W:%s:%s:%s:%s",
                        MarketSync.ToBase36(wRec.min),
                        MarketSync.ToBase36(wRec.max),
                        MarketSync.ToBase36(wRec.avg),
                        MarketSync.ToBase36(wRec.volume))
                end

                -- Prune vh (verified history) leak: only keep hot tier for outbound sync
                if type(data.vh) == "table" then
                    for vhDayKey, _ in pairs(data.vh) do
                        local vhDayNum = tonumber(vhDayKey)
                        if not vhDayNum or vhDayNum < hotCutoff or (type(vhDayKey) == "string" and vhDayKey:sub(1, 2) == "W_") then
                            data.vh[vhDayKey] = nil
                            vhPrunedCount = vhPrunedCount + 1
                        end
                    end
                    if not next(data.vh) then
                        data.vh = nil
                    end
                end
            end

            i = i + 1
            if i % 500 == 0 then coroutine.yield() end
        end

        if MarketSyncDB and MarketSyncDB.DebugMode and (compactedDailyCount > 0 or compactedWeeklyCount > 0 or purgedCount > 0 or vhPrunedCount > 0) then
            print(string.format(
                "|cFF00FF00[MarketSync]|r Retention Downsampler: %d daily, %d weekly, %d purged, %d vh pruned",
                compactedDailyCount, compactedWeeklyCount, purgedCount, vhPrunedCount))
        end
        if onComplete then
            onComplete(compactedDailyCount, compactedWeeklyCount, purgedCount, vhPrunedCount)
        end
    end)

    local function RunChunk()
        if coroutine.status(co) ~= "dead" then
            local ok, err = coroutine.resume(co)
            if not ok then
                if MarketSync.Debug then MarketSync.Debug("Error in Retention Downsampler coroutine: " .. tostring(err)) end
                error("Error in Retention Downsampler coroutine: " .. tostring(err))
            else
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.02, RunChunk)
                else
                    RunChunk()
                end
            end
        end
    end
    RunChunk()
end

local eventFrame = CreateFrame("Frame")
SafeRegisterEvent(eventFrame, "ADDON_LOADED")
SafeRegisterEvent(eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
SafeRegisterEvent(eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Auctionator" then
            if not MarketSync.Provider or MarketSync.Provider.GetActiveName() == "auctionator" then
                RegisterAuctionatorHooks()
            end
        elseif arg1 == ADDON_NAME or arg1 == "AuctionatorAnnouncer" then
            MarketSync.InitializeDB()
            CreateMinimapButton()
            if MarketSync.Provider and MarketSync.Provider.Initialize then
                MarketSync.Provider.Initialize()
            end
            if not MarketSync.Provider or MarketSync.Provider.GetActiveName() == "auctionator" then
                RegisterAuctionatorHooks()
            end

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
    end
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

        -- STAGE 4: Tiered Retention Downsampler (120s)
        -- Hot (0-7d):    full 30-min resolution (synced via guild swarm)
        -- Warm (8-30d):  daily compact summaries (D:min:max:avg:vol, local)
        -- Cold (31-180d): weekly compact summaries (W:min:max:avg:vol, local)
        -- Purge (>180d): deleted
        C_Timer.After(120, function()
            if MarketSync.DownsampleRetention then
                MarketSync.DownsampleRetention()
            end
        end)

        -- Register for AH events so we can invalidate the scan cache dynamically
        SafeRegisterEvent(self, "AUCTION_HOUSE_CLOSED")
        SafeRegisterEvent(self, "AUCTION_HOUSE_SHOW")

        -- Register for Smart Rules state tracking (combat/instance transitions)
        SafeRegisterEvent(self, "PLAYER_REGEN_DISABLED")   -- Entering combat
        SafeRegisterEvent(self, "PLAYER_REGEN_ENABLED")    -- Leaving combat
        SafeRegisterEvent(self, "ZONE_CHANGED_NEW_AREA")   -- Entering/leaving instances
        SafeRegisterEvent(self, "SKILL_LINES_CHANGED")
        SafeRegisterEvent(self, "TRADE_SKILL_SHOW")
        SafeRegisterEvent(self, "TRADE_SKILL_DATA_SOURCE_CHANGED")
        SafeRegisterEvent(self, "TRADE_SKILL_LIST_UPDATE")
        SafeRegisterEvent(self, "TRADE_SKILL_UPDATE")
        if MarketSync.RefreshKnownProfessionCache then
            MarketSync.RefreshKnownProfessionCache()
        end
        MarketSync._lastCanSync = MarketSync.CanSync and MarketSync.CanSync() or true

    elseif event == "AUCTION_HOUSE_SHOW"
        or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and (arg1 == 21 or (Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.Auctioneer))) then
        MarketSync.IsAuctionHouseOpen = true
        MarketSync.IsNeutralAHOpen = false

        -- Snapshot current live store size and "today" count so we can detect a real scan on close
        MarketSync._ahOpenItemCount = 0
        MarketSync._ahOpenTodayCount = 0
        local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)
        if liveStore then
            local today = MarketSync.GetCurrentScanDay()
            for _, data in pairs(liveStore) do
                MarketSync._ahOpenItemCount = MarketSync._ahOpenItemCount + 1
                if (type(data) == "table" and data.h and data.h[tostring(today)])
                    or (data and data.latest and data.latest.seenAt and (time() - data.latest.seenAt) < 86400) then
                    MarketSync._ahOpenTodayCount = MarketSync._ahOpenTodayCount + 1
                end
            end
        end

        if MarketSync.HandleAuctionHouseShown then
            local ok, isNeutral = pcall(MarketSync.HandleAuctionHouseShown)
            if ok then
                MarketSync.IsNeutralAHOpen = isNeutral and true or false
            else
                MarketSync.Debug("Neutral AH show hook failed: " .. tostring(isNeutral))
            end
        end

    elseif event == "AUCTION_HOUSE_CLOSED"
        or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and (arg1 == 21 or (Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.Auctioneer))) then
        -- Guard: Only run the snapshot pipeline if we actually tracked the AH opening.
        if not MarketSync.IsAuctionHouseOpen then
            MarketSync.Debug("AUCTION_HOUSE_CLOSED fired but AH was never opened — ignoring (spurious event)")
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
            local today = MarketSync.GetCurrentScanDay()
            local myLatestScanDay = MarketSync.GetMyLatestScanDay()

            -- Immediately snapshot the latest DB state exclusively to the PersonalData pool
            if MarketSync.SnapshotPersonalScan then
                local _, todayCount, changedCount = MarketSync.SnapshotPersonalScan()

                local preCount = MarketSync._ahOpenItemCount or 0
                local preToday = MarketSync._ahOpenTodayCount or 0
                local postCount = 0
                local postToday = 0
                local today = MarketSync.GetCurrentScanDay()

                local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
                    or (Auctionator and Auctionator.Database and Auctionator.Database.db)
                if liveStore then
                    for _, data in pairs(liveStore) do 
                        postCount = postCount + 1 
                        if (type(data) == "table" and data.h and data.h[tostring(today)])
                            or (data and data.latest and data.latest.seenAt and (time() - data.latest.seenAt) < 86400) then
                            postToday = postToday + 1
                        end
                    end
                end
                
                -- Detect a real scan if Auctionator/Scanner scanned, items grew, or price changes were recorded
                local scannerScanned = MarketSyncForeverScanner and MarketSyncForeverScanner.Store and MarketSyncForeverScanner.Store.completedWatchScans and MarketSyncForeverScanner.Store.completedWatchScans > 0
                local scanCompleted = MarketSync._ahFullScanCompleted or scannerScanned
                local scanActivity = MarketSync._ahScanActivity and MarketSync._ahScanActivity > 0
                local countGrew = (postCount > preCount) or (postToday > preToday)
                local changesRecorded = (changedCount and changedCount > 0)

                local realScanOccurred = scanCompleted or scanActivity or countGrew or changesRecorded
                MarketSync._ahOpenItemCount = nil
                MarketSync._ahOpenTodayCount = nil
                MarketSync._ahFullScanCompleted = nil
                MarketSync._ahScanActivity = nil

                if realScanOccurred then
                    local now = time()
                    MarketSync.GetRealmDB().PersonalScanTime = now  -- Sacred: actual AH scan
                    MarketSync.GetRealmDB().SwarmTSF = now          -- Protocol freshness
                    if myLatestScanDay == today then
                        MarketSync.GetRealmDB().LastCountDay = today
                        MarketSync.GetRealmDB().LastTodayCount = todayCount
                    end
                elseif not realScanOccurred then
                    MarketSync.Debug("AH closed without a real scan (" .. preCount .. " -> " .. postCount .. " items) — skipping PersonalScanTime stamp")
                end
            end

            if MarketSync.GetRealmDB().CachedScanStats then
                MarketSync.GetRealmDB().CachedScanStats = nil
                if MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                    -- Broadcast our new findings roughly 2 seconds after closing the AH
                    C_Timer.After(2, function() MarketSync.SendAdvertisement() end)
                end
            end

            -- Invalidate browse index so Guild Sync tab reflects fresh scan data
            -- then trigger a rebuild so the async resolver starts fresh
            if MarketSync.InvalidateIndexCache then
                MarketSync.InvalidateIndexCache()
            end
            if MarketSync.BuildSearchIndex then
                C_Timer.After(1, function() MarketSync.BuildSearchIndex() end)
            end
        end

    -- Keep known profession recipes in sync with the player's profession book.
    elseif event == "TRADE_SKILL_SHOW"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED"
        or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_UPDATE"
        or event == "SKILL_LINES_CHANGED" then
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
