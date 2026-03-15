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
        -- Switch to Settings tab (Tab 6)
        if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[6] then
            MarketSyncMainFrame.tabs[6]:Click()
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
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    -- Handle both the legacy folder name and the new name
    if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == "AuctionatorAnnouncer") then
        -- STAGE 1: Bare minimum â€” no DB iteration at all
        MarketSync.InitializeDB()
        CreateMinimapButton()

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

        -- Snapshot the current Auctionator DB size and "today" count so we can detect a real scan on close
        MarketSync._ahOpenItemCount = 0
        MarketSync._ahOpenTodayCount = 0
        if Auctionator and Auctionator.Database and Auctionator.Database.db then
            local today = MarketSync.GetCurrentScanDay()
            for _, data in pairs(Auctionator.Database.db) do
                MarketSync._ahOpenItemCount = MarketSync._ahOpenItemCount + 1
                if type(data) == "table" and data.h and data.h[tostring(today)] then
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

    elseif event == "AUCTION_HOUSE_CLOSED" then
        -- Guard: Only run the snapshot pipeline if we actually tracked the AH opening.
        -- Some WoW edge cases (NPC interactions, addon taint, etc.) can fire
        -- AUCTION_HOUSE_CLOSED without a preceding AUCTION_HOUSE_SHOW. Running the
        -- pipeline on a spurious close would set a false PersonalScanTime and trigger
        -- phantom ADV broadcasts to the guild.
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
            local today = MarketSync.GetCurrentScanDay()
            local myLatestScanDay = MarketSync.GetMyLatestScanDay()

            -- Immediately snapshot the latest DB state exclusively to the PersonalData pool
            if MarketSync.SnapshotPersonalScan then
                local _, todayCount = MarketSync.SnapshotPersonalScan()

                -- Only stamp PersonalScanTime if Auctionator actually scanned new data
                -- during this AH session (item count grew vs what we saw at open time).
                -- This prevents merely visiting the AH from being treated as a scan.
                local preCount = MarketSync._ahOpenItemCount or 0
                local preToday = MarketSync._ahOpenTodayCount or 0
                local postCount = 0
                local postToday = 0
                local today = MarketSync.GetCurrentScanDay()

                if Auctionator and Auctionator.Database and Auctionator.Database.db then
                    for _, data in pairs(Auctionator.Database.db) do 
                        postCount = postCount + 1 
                        if type(data) == "table" and data.h and data.h[tostring(today)] then
                            postToday = postToday + 1
                        end
                    end
                end
                
                -- Detect a real scan if total items grew OR if the number of items 
                -- seen "today" grew (captures price-only updates to existing items).
                local realScanOccurred = (postCount > preCount) or (postToday > preToday)
                MarketSync._ahOpenItemCount = nil  -- clear snapshot
                MarketSync._ahOpenTodayCount = nil

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
