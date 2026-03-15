-- =============================================================
-- MarketSync - Sync Module
-- Protocol, data merging, passive sync, bulk broadcast
-- =============================================================

local PREFIX = MarketSync.PREFIX
local DATA_PREFIXES = MarketSync.DATA_PREFIXES
local Debug = MarketSync.Debug
local IsBlocked = MarketSync.IsBlocked
local TrackSync = MarketSync.TrackSync
local FormatMoney = MarketSync.FormatMoney
local GetCurrentScanDay = MarketSync.GetCurrentScanDay

-- ================================================================
-- SYNC PROTOCOL
-- ADV;realm;scanDay;itemCount;ver - "I have data for this realm"
-- PULL;realm;sinceDay             - "Send me items newer than day X"
-- ACCEPT;realm;sinceDay           - "I am taking this PULL request"
-- RES;link;price;day;qty          - Single item payload (decimal)
-- REQ;link                        - Single item request
-- BRES;id:price:qty:day,...       - Bulk payload (base-36 encoded)
--   Sent on DATA_PREFIXES (MSyncD1/D2/D3) for parallel throughput
-- ================================================================

-- ================================================================
-- BASE-36 ENCODING / DECODING
-- Compresses numeric payloads by ~30% (e.g. "50000" -> "11cg")
-- Lua's tonumber(str, 36) handles decode natively.
-- ================================================================
local B36_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function ToBase36(n)
    n = math.floor(tonumber(n) or 0)
    if n == 0 then return "0" end
    local result = ""
    local neg = n < 0
    if neg then n = -n end
    while n > 0 do
        local rem = n % 36
        result = string.sub(B36_CHARS, rem + 1, rem + 1) .. result
        n = math.floor(n / 36)
    end
    return neg and ("-" .. result) or result
end

local function FromBase36(s)
    if not s or s == "" then return 0 end
    return tonumber(s, 36) or 0
end

-- Export for Chat.lua receiver
MarketSync.FromBase36 = FromBase36

MarketSync.myRealm = nil
local myLatestScanDay = 0
local myRecentItemCount = 0
local myLatestNeutralScanDay = 0
local myRecentNeutralItemCount = 0
local pullInProgress = false
local broadcastInProgress = false
local pullRequestPending = false
local pullRequestPendingTimer = nil
local lastAdvertisementAt = 0
local lastNeutralAdvertisementAt = 0
local MIN_ADV_INTERVAL_SECONDS = 15
local PULL_REQUEST_TIMEOUT_SECONDS = 25
local PULL_CLAIM_TTL_SECONDS = 30
local ScheduleDeferredADVProcessing
local neutralPullQueue = {}

MarketSync.TxCount = 0
MarketSync.RxCount = 0
MarketSync.AddonTxBytes = {}
MarketSync.AddonTxAPI = {}
MarketSync.TxBytes = 0
MarketSync.TxAPICalls = 0

-- Global hook to intercept all addons' transmission
hooksecurefunc(C_ChatInfo, "SendAddonMessage", function(prefix, text, chatType, target)
    local bytes = text and #text or 0
    MarketSync.TxBytes = (MarketSync.TxBytes or 0) + bytes
    MarketSync.TxAPICalls = (MarketSync.TxAPICalls or 0) + 1
    
    -- Accumulate bytes and API calls per-prefix (per-addon)
    if prefix then
        MarketSync.AddonTxBytes[prefix] = (MarketSync.AddonTxBytes[prefix] or 0) + bytes
        MarketSync.AddonTxAPI[prefix] = (MarketSync.AddonTxAPI[prefix] or 0) + 1
    end
end)

local function SendAddonMessage(prefix, text, chatType, target)
    -- We removed MarketSync.TxBytes counting from here because the hooksecurefunc
    -- above will catch the _SendAddonMessage call below automatically.
    C_ChatInfo.SendAddonMessage(prefix, text, chatType, target)
end

local function SetTransientBlockedState(reason)
    if not MarketSync.UpdateSwarmUI then return end
    local player = UnitName("player")
    if not player then return end
    MarketSync.UpdateSwarmUI(player, "Blocked (Busy: " .. tostring(reason or "sync") .. ")")
    C_Timer.After(2, function()
        if not MarketSync.UpdateSwarmUI then return end
        MarketSync.UpdateSwarmUI(player, nil)
    end)
end

local function SetClaim(queue, sinceDay, senderName)
    if not queue or sinceDay == nil then return end
    queue[sinceDay] = { name = senderName, ts = time() }
end

local function ClearClaim(queue, sinceDay)
    if not queue or sinceDay == nil then return end
    queue[sinceDay] = nil
end

local function GetClaimantName(queue, sinceDay)
    if not queue then return nil end
    local claim = queue[sinceDay]
    if not claim then return nil end

    if type(claim) == "table" then
        local ts = tonumber(claim.ts) or 0
        if ts > 0 and (time() - ts) > PULL_CLAIM_TTL_SECONDS then
            queue[sinceDay] = nil
            return nil
        end
        return claim.name
    end

    if type(claim) == "string" and claim ~= "" then
        return claim
    end

    return nil
end

-- Global busy check so other modules can defer new sync work until active
-- send/receive sessions are fully finished.
function MarketSync.IsSyncBusy()
    return pullInProgress
        or broadcastInProgress
        or pullRequestPending
        or ((MarketSync.RxCount or 0) > 0)
end

function MarketSync.SetPullRequestPending(isPending)
    local pending = isPending and true or false

    if pullRequestPendingTimer then
        pullRequestPendingTimer:Cancel()
        pullRequestPendingTimer = nil
    end

    pullRequestPending = pending
    if not pending then
        return
    end

    pullRequestPendingTimer = C_Timer.NewTimer(PULL_REQUEST_TIMEOUT_SECONDS, function()
        pullRequestPendingTimer = nil
        if not pullRequestPending then return end
        pullRequestPending = false
        Debug("PULL request timed out waiting for first data chunk")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cffff8800[Pull Timeout]|r No data received after %ds; sync window reopened.", PULL_REQUEST_TIMEOUT_SECONDS))
        end
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), nil)
        end
        ScheduleDeferredADVProcessing()
    end)
end

ScheduleDeferredADVProcessing = function()
    if not MarketSync.ProcessDeferredADV then return end
    C_Timer.After(0.25, function()
        if MarketSync.ProcessDeferredADV then
            MarketSync.ProcessDeferredADV()
        end
    end)
end

-- ================================================================
-- NETWORK MONITORING (Tx/Rx per second)
-- ================================================================
local lastTx, lastRx, lastTxBytes, lastTxAPI = 0, 0, 0, 0
local lastAddonBytes = {}

-- Store global rates for sync ticker throttling
MarketSync.GlobalTxAPIRate = 0
MarketSync.GlobalTxBytesRate = 0

C_Timer.NewTicker(1.0, function()
    local txRate = (MarketSync.TxCount or 0) - lastTx
    local rxRate = (MarketSync.RxCount or 0) - lastRx
    local currentTxBytes = MarketSync.TxBytes or 0
    local currentTxAPI = MarketSync.TxAPICalls or 0
    local txBytesRate = currentTxBytes - lastTxBytes
    local txAPIRate = currentTxAPI - lastTxAPI
    lastTx = MarketSync.TxCount or 0
    lastRx = MarketSync.RxCount or 0
    lastTxBytes = currentTxBytes
    lastTxAPI = currentTxAPI

    MarketSync.GlobalTxAPIRate = txAPIRate
    MarketSync.GlobalTxBytesRate = txBytesRate

    -- Calculate bytes/sec and msgs/sec for each individual addon prefix
    local addonRates = {}
    local safeAddonBytes = MarketSync.AddonTxBytes or {}
    local safeAddonAPI = MarketSync.AddonTxAPI or {}
    
    -- Consolidate known prefixes
    local knownPrefixes = {}
    for prefix in pairs(safeAddonBytes) do knownPrefixes[prefix] = true end
    for prefix in pairs(safeAddonAPI) do knownPrefixes[prefix] = true end

    for prefix in pairs(knownPrefixes) do
        local currentBytes = safeAddonBytes[prefix] or 0
        local currentAPI = safeAddonAPI[prefix] or 0
        
        local prevBytes = lastAddonBytes[prefix] or { bytes = 0, api = 0 }
        
        local rateBytes = currentBytes - (prevBytes.bytes or 0)
        local rateAPI = currentAPI - (prevBytes.api or 0)
        
        if rateBytes > 0 or prevBytes.bytes > 0 or rateAPI > 0 or prevBytes.api > 0 then
            table.insert(addonRates, { prefix = prefix, rate = rateBytes, apiRate = rateAPI })
        end
        lastAddonBytes[prefix] = { bytes = currentBytes, api = currentAPI }
    end
    
    -- Sort the addon breakdown highest to lowest (by bytes)
    table.sort(addonRates, function(a, b)
        return a.rate > b.rate
    end)

    if MarketSync.UpdateNetworkUI then
        MarketSync.UpdateNetworkUI(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
    end
end)

-- ================================================================
-- LOCAL SCAN SNAPSHOT (Duplicating Personal Data)
-- ================================================================
function MarketSync.SnapshotPersonalScan()
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0, 0 end
    if not MarketSync.GetRealmDB().PersonalData then MarketSync.GetRealmDB().PersonalData = {} end
    
    wipe(MarketSync.GetRealmDB().PersonalData)
    
    local today = MarketSync.GetCurrentScanDay()
    local count = 0
    local todayCount = 0
    local skipped = 0
    
    for dbKey, data in pairs(Auctionator.Database.db) do
        if type(data) == "table" then
            -- Only snapshot items with parseable itemIDs (consistent with CountRecentItems/RespondToPull)
            local hasValidID = false
            if type(dbKey) == "number" or type(dbKey) == "string" then
                hasValidID = true
            end
            
            if hasValidID and data.m and data.m > 0 then
                local lastSeenDay = 0
                if data.h then
                    for dayStr in pairs(data.h) do
                        local d = tonumber(dayStr)
                        if d and d > lastSeenDay then lastSeenDay = d end
                    end
                end
                MarketSync.GetRealmDB().PersonalData[dbKey] = { m = data.m, d = lastSeenDay }
                count = count + 1
                if lastSeenDay == today then
                    todayCount = todayCount + 1
                end
            else
                skipped = skipped + 1
            end
        end
    end
    
    Debug("SnapshotPersonalScan: Duplicated " .. count .. " items (" .. todayCount .. " from today, " .. skipped .. " skipped) into Personal storage.")
    
    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Duplicated " .. count .. " items into Personal cache. (" .. skipped .. " unparseable keys skipped)")
    end
    
    return count, todayCount
end

-- ================================================================
-- SCAN DAY HELPERS
-- ================================================================
function MarketSync.GetMyLatestScanDay()
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0 end
    
    local today = MarketSync.GetCurrentScanDay()
    
    -- If we have a cached day and it is "today", trust the cache
    if MarketSyncDB and MarketSync.GetRealmDB().CachedScanStats and MarketSync.GetRealmDB().CachedScanStats.day == today then
        return MarketSync.GetRealmDB().CachedScanStats.day
    end
    
    local best = 0
    for dbKey, data in pairs(Auctionator.Database.db) do
        if type(data) == "table" and data.h then
            for dayStr in pairs(data.h) do
                local d = tonumber(dayStr)
                if d and d > best then best = d end
            end
        end
    end
    return best
end

function MarketSync.CountRecentItems(sinceDay)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0 end
    
    local today = MarketSync.GetCurrentScanDay()
    
    -- If we have cached stats for the requested day, trust the cache
    if MarketSyncDB and MarketSync.GetRealmDB().CachedScanStats and MarketSync.GetRealmDB().CachedScanStats.day == sinceDay then
        return MarketSync.GetRealmDB().CachedScanStats.count
    end
    
    local count = 0
    for dbKey, data in pairs(Auctionator.Database.db) do
        if type(data) == "table" and data.h then
            -- Only count items with parseable itemIDs (must match RespondToPull logic)
            local hasValidID = false
            if type(dbKey) == "number" or type(dbKey) == "string" then
                hasValidID = true
            end
            if hasValidID then
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d >= sinceDay then 
                        count = count + 1
                        break 
                    end
                end
            end
        end
    end
    
    -- Cache the result if we are checking "today" to save CPU on future ADVs
    if MarketSyncDB and sinceDay == today then
        MarketSync.GetRealmDB().CachedScanStats = { day = sinceDay, count = count }
    end
    
    return count
end

function MarketSync.GetMyLatestNeutralScanDay()
    local realmDB = MarketSync.GetRealmDB()
    local best = 0
    for _, data in pairs(realmDB.NeutralData or {}) do
        if type(data) == "table" then
            local d = tonumber(data.d) or 0
            if d > best then best = d end
        end
    end
    return best
end

function MarketSync.CountNeutralRecentItems(sinceDay)
    local realmDB = MarketSync.GetRealmDB()
    local count = 0
    for _, data in pairs(realmDB.NeutralData or {}) do
        if type(data) == "table" then
            local d = tonumber(data.d) or 0
            if d >= (tonumber(sinceDay) or 0) then
                count = count + 1
            end
        end
    end
    return count
end

-- ================================================================
-- SEND FUNCTIONS
-- ================================================================
function MarketSync.CanSync()
    if not IsInGuild() then return false end
    if not MarketSyncDB then return true end
    if not MarketSyncDB.AllowSyncInCombat and InCombatLockdown and InCombatLockdown() then return false end
    
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance then
            if instanceType == "raid" and not MarketSyncDB.AllowSyncInRaid then return false end
            if instanceType == "party" and not MarketSyncDB.AllowSyncInDungeon then return false end
            if instanceType == "pvp" and not MarketSyncDB.AllowSyncInPvP then return false end
            if instanceType == "arena" and not MarketSyncDB.AllowSyncInArena then return false end
        end
    end
    return true
end

function MarketSync.SendAdvertisement()
    if not MarketSync.CanSync() then return end
    -- ADVs are allowed during active sync, but throttle to protect guild chat limits.
    local now = time()
    if (now - (lastAdvertisementAt or 0)) < MIN_ADV_INTERVAL_SECONDS then
        Debug("ADV throttled: minimum interval not reached")
        return
    end

    -- Suppress ADV while the Auction House is actively open (e.g. running an Auctionator scan)
    if MarketSync.IsAuctionHouseOpen then
        Debug("ADV suppressed: Auction House is currently open")
        return
    end
    -- Instead of entirely suppressing ADV when PassiveSync is off, we send a "Disabled" heartbeat.
    local isDisabled = (MarketSyncDB and MarketSyncDB.PassiveSync == false)

    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    myLatestScanDay = MarketSync.GetMyLatestScanDay()
    myRecentItemCount = MarketSync.CountRecentItems(myLatestScanDay)
    
    local localVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or "0.0.0"
    
    if isDisabled then
        -- Send a heartbeat with TSF literally set to "DISABLED"
        local payload = string.format("ADV;%s;0;0;%s;DISABLED", MarketSync.myRealm, localVersion)
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastAdvertisementAt = now
        -- Update our own UI to show disabled state too
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Disabled") end
    elseif myLatestScanDay > 0 and myRecentItemCount > 0 then
        local myScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().SwarmTSF) or 0
        local payload = string.format("ADV;%s;%d;%d;%s;%s", MarketSync.myRealm, myLatestScanDay, myRecentItemCount, localVersion, tostring(myScanTime))
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastAdvertisementAt = now
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ffff[ADV]|r to Guild (Day %d, %d items, TSF: %d, v%s)", myLatestScanDay, myRecentItemCount, myScanTime, localVersion))
        end
        Debug("Sent ADV: realm=" .. MarketSync.myRealm .. " day=" .. myLatestScanDay .. " items=" .. myRecentItemCount .. " tsf=" .. myScanTime .. " v=" .. localVersion)
    end
end

function MarketSync.SendNeutralAdvertisement()
    if not MarketSync.CanSync() then return end

    -- Share the same throttle window as main ADV to respect guild channel limits.
    local now = time()
    if (now - (lastNeutralAdvertisementAt or 0)) < MIN_ADV_INTERVAL_SECONDS then
        return
    end

    if MarketSync.IsAuctionHouseOpen then
        return
    end

    local isDisabled = (MarketSyncDB and MarketSyncDB.EnableNeutralSync == false)

    if not MarketSync.myRealm then
        MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName()
    end

    myLatestNeutralScanDay = MarketSync.GetMyLatestNeutralScanDay()
    myRecentNeutralItemCount = MarketSync.CountNeutralRecentItems(myLatestNeutralScanDay)
    
    local localVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or "0.0.0"

    if isDisabled then
        local payload = string.format("NADV;%s;0;0;%s;DISABLED", MarketSync.myRealm, localVersion)
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastNeutralAdvertisementAt = now
        -- Update our own UI to show disabled state too for neutral
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Disabled") end
    elseif myLatestNeutralScanDay > 0 and myRecentNeutralItemCount > 0 then
        local neutralTSF = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().NeutralSwarmTSF) or 0
        local payload = string.format("NADV;%s;%d;%d;%s;%s", MarketSync.myRealm, myLatestNeutralScanDay, myRecentNeutralItemCount, localVersion, tostring(neutralTSF))
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastNeutralAdvertisementAt = now

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ccff[NADV]|r to Guild (Day %d, %d items, TSF: %d, v%s)", myLatestNeutralScanDay, myRecentNeutralItemCount, neutralTSF, localVersion))
        end
    end
end

function MarketSync.SendPullRequest(sinceDay)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent("|cffaaaaaa[Swarm]|r Pull request skipped: sync system is busy.")
        end
        SetTransientBlockedState("send/receive active")
        return
    end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("PULL;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.SetPullRequestPending then
        MarketSync.SetPullRequestPending(true)
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Awaiting Data")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cffff8800[PULL]|r to Guild (Since Day %d)", sinceDay))
    end
    Debug("Sent PULL: realm=" .. MarketSync.myRealm .. " sinceDay=" .. sinceDay)
end

function MarketSync.SendNeutralPullRequest(sinceDay)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent("|cffaaaaaa[Neutral]|r Pull request skipped: sync system is busy.")
        end
        SetTransientBlockedState("send/receive active")
        return
    end

    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("NPULL;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.SetPullRequestPending then
        MarketSync.SetPullRequestPending(true)
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Awaiting Neutral Data")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ccff[NPULL]|r to Guild (Since Day %d)", sinceDay))
    end
end

function MarketSync.SendSyncRequest(itemLink)
    if IsInGuild() then
        SendAddonMessage(PREFIX, "REQ;" .. itemLink, "GUILD")
    end
end

function MarketSync.SendSyncResponse(itemLink, price, day, quantity, channel, target)
    -- Respect Smart Rules for guild traffic (combat/instance suppression).
    if channel == "GUILD" and MarketSync.CanSync and not MarketSync.CanSync() then
        return
    end
    quantity = quantity or 0
    local payload = string.format("RES;%s;%d;%d;%d", itemLink, price, day, quantity)
    SendAddonMessage(PREFIX, payload, channel, target)
    MarketSync.TxCount = MarketSync.TxCount + 1
end

function MarketSync.SendBulkSyncResponse(chunkBuffer, dataPrefix, channel, target)
    local payload = "BRES;" .. chunkBuffer
    SendAddonMessage(dataPrefix, payload, channel, target)
end

-- ================================================================
-- SWARM COORDINATOR (PULL Queuing & Throttled Responses)
-- ================================================================
MarketSync.PullQueue = {}

function MarketSync.SendPullAccept(sinceDay)
    if not MarketSync.CanSync() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("ACCEPT;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ff00[ACCEPT]|r to Guild (Claiming PULL for Day %d)", sinceDay))
    end
end

function MarketSync.RegisterPullAccept(sinceDay, senderName)
    SetClaim(MarketSync.PullQueue, sinceDay, senderName)
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ff00[Swarm]|r %s claimed PULL for Day %d", senderName, sinceDay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(senderName, "Sending")
    end
end

function MarketSync.SendNeutralPullAccept(sinceDay)
    if not MarketSync.CanSync() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("NACCEPT;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ccff[NACCEPT]|r to Guild (Claiming neutral pull for Day %d)", sinceDay))
    end
end

function MarketSync.RegisterNeutralPullAccept(sinceDay, senderName)
    SetClaim(neutralPullQueue, sinceDay, senderName)
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r %s claimed NPULL for Day %d", senderName, sinceDay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(senderName, "Sending Neutral")
    end
end

function MarketSync.SchedulePullResponse(sinceDay, requester)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r Ignoring PULL from %s while another sync blast is active.", requester or "unknown"))
        end
        SetTransientBlockedState("send/receive active")
        return
    end

    local delay = math.random() * 8.0 -- 0.0 to 8.0 seconds for large guilds
    
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cffff8800[Swarm]|r Queued PULL from %s. Waiting %.1fs for consensus...", requester, delay))
    end
    
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Waiting")
    end

    C_Timer.After(delay, function()
        -- Re-check Smart Rules at execution time (state may have changed during delay).
        if not MarketSync.CanSync() then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r Skipped PULL response for %s (Smart Rules currently blocking sync).", requester or "unknown"))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            end
            return
        end

        -- Re-check runtime lock right before claiming/sending.
        if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r Skipped queued PULL response for %s (another sync blast became active).", requester or "unknown"))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            end
            SetTransientBlockedState("send/receive active")
            return
        end

        -- See if someone else accepted this pull
        local claimant = GetClaimantName(MarketSync.PullQueue, sinceDay)
        if claimant then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r %s is already fulfilling PULL (Day %d). Standing down.", claimant, sinceDay))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil) -- remove our wait state
            end
            return 
        end
        
        -- Nobody else took it, we accept!
        MarketSync.SendPullAccept(sinceDay)
        MarketSync.RespondToPull(sinceDay, requester)
        
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), "Sending")
        end
    end)
end

function MarketSync.ScheduleNeutralPullResponse(sinceDay, requester)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Neutral]|r Ignoring NPULL from %s while another sync blast is active.", requester or "unknown"))
        end
        SetTransientBlockedState("send/receive active")
        return
    end

    local delay = math.random() * 8.0
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r Queued NPULL from %s. Waiting %.1fs for consensus...", requester or "unknown", delay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Waiting")
    end

    C_Timer.After(delay, function()
        if not MarketSync.CanSync() then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            return
        end
        if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            SetTransientBlockedState("send/receive active")
            return
        end
        local claimant = GetClaimantName(neutralPullQueue, sinceDay)
        if claimant then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Neutral]|r %s is already fulfilling NPULL (Day %d). Standing down.", claimant, sinceDay))
            end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            return
        end

        MarketSync.SendNeutralPullAccept(sinceDay)
        MarketSync.RespondToNeutralPull(sinceDay, requester)
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), "Sending Neutral")
        end
    end)
end

function MarketSync.RespondToNeutralPull(sinceDay, requester)
    if pullInProgress then
        SetTransientBlockedState("active send")
        return
    end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        SetTransientBlockedState("send/receive active")
        return
    end
    if not MarketSync.CanSync() then return end

    local realmDB = MarketSync.GetRealmDB()
    if not realmDB or not realmDB.NeutralData then return end

    pullInProgress = true
    SetClaim(neutralPullQueue, sinceDay, UnitName("player") or "Unknown")
    local MAX_PAYLOAD = 248
    local numPrefixes = #DATA_PREFIXES
    local prefixIndex = 0

    local co = coroutine.create(function()
        local sent = 0
        local scanned = 0
        local messagesSent = 0
        local buffer = ""
        local bufferCount = 0

        for dbKey, data in pairs(realmDB.NeutralData) do
            scanned = scanned + 1
            local d = tonumber(data and data.d) or 0
            if d >= sinceDay then
                local price = tonumber(data.m) or 0
                if price > 0 then
                    local qty = tonumber(data.q) or 0
                    local itemStr = tostring(dbKey) .. "_" .. ToBase36(price) .. "_" .. ToBase36(qty) .. "_" .. ToBase36(d)
                    local currentLen = string.len(buffer)
                    if currentLen > 0 and currentLen + 1 + string.len(itemStr) > MAX_PAYLOAD then
                        local dp = DATA_PREFIXES[prefixIndex]
                        SendAddonMessage(dp, "NBRES;" .. buffer, "GUILD")
                        MarketSync.TxCount = MarketSync.TxCount + bufferCount
                        sent = sent + bufferCount
                        messagesSent = messagesSent + 1
                        buffer = ""
                        bufferCount = 0
                        coroutine.yield()
                    end
                    if buffer == "" then
                        buffer = itemStr
                    else
                        buffer = buffer .. "," .. itemStr
                    end
                    bufferCount = bufferCount + 1
                end
            end
        end

        if buffer ~= "" then
            local dp = DATA_PREFIXES[prefixIndex]
            SendAddonMessage(dp, "NBRES;" .. buffer, "GUILD")
            MarketSync.TxCount = MarketSync.TxCount + bufferCount
            sent = sent + bufferCount
            messagesSent = messagesSent + 1
        end

        local neutralTSF = (realmDB and realmDB.NeutralSwarmTSF) or 0
        SendAddonMessage(PREFIX, string.format("NEND;%d;%d;%s", sent, messagesSent, tostring(neutralTSF)), "GUILD")
        ClearClaim(neutralPullQueue, sinceDay)
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r Sent %d neutral items in %d messages (%d scanned).", sent, messagesSent, scanned))
        end

        pullInProgress = false
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
        ScheduleDeferredADVProcessing()
    end)

    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if not MarketSync.CanSync() then
            ticker:Cancel()
            ClearClaim(neutralPullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
            return
        end

        -- GLOBAL SELF-THROTTLING
        -- If other addons (like Attune) are bursting, skip our tick to prevet disconnect
        local apiLimit = 40
        local byteLimit = 750
        if (MarketSync.GlobalTxAPIRate or 0) > apiLimit or (MarketSync.GlobalTxBytesRate or 0) > byteLimit then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Throttled") end
            return -- Skip this tick, wait for rates to drop
        else
            -- Restore active status if we were throttled
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending Neutral") end
        end

        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            ClearClaim(neutralPullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
            return
        end

        prefixIndex = (prefixIndex % numPrefixes) + 1
        local ok, err = coroutine.resume(co)
        if not ok then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent("|cffff0000[Neutral Error]|r " .. tostring(err))
            end
            ticker:Cancel()
            ClearClaim(neutralPullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
        end
    end)
end

function MarketSync.RespondToPull(sinceDay, requester)
    if pullInProgress then
        Debug("PULL response already in progress, ignoring request from " .. (requester or "unknown"))
        SetTransientBlockedState("active send")
        return
    end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        Debug("RespondToPull ignored: another sync blast is active")
        SetTransientBlockedState("send/receive active")
        return
    end
    if not MarketSync.CanSync() then
        Debug("RespondToPull blocked by Smart Rules")
        return
    end
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return end
    pullInProgress = true
    SetClaim(MarketSync.PullQueue, sinceDay, UnitName("player") or "Unknown")
    Debug("Responding to PULL from " .. (requester or "unknown") .. " (sinceDay=" .. sinceDay .. ")")

    -- BRES v3: Base-36 encoded, multi-prefix parallel transfer
    -- 3 data prefixes round-robin at 1 msg/sec each = 3 msg/sec sustained.
    -- Each message packs ~16 base-36 items into 248 bytes.
    -- Total throughput: ~48 items/sec. Full 2355-item sync in ~50 seconds.
    local MAX_PAYLOAD = 248  -- 255 minus "BRES;" prefix (5) minus safety margin (2)
    local numPrefixes = #DATA_PREFIXES
    local prefixIndex = 0  -- round-robin counter shared between coroutine and ticker
    
    local co = coroutine.create(function()
        local sent = 0
        local scanned = 0
        local skipped = 0
        local messagesSent = 0
        local buffer = ""
        local bufferCount = 0
        
        -- Store current key globally so the ticker can retrieve it on crash
        _G.MarketSyncActivePullKey = "Starting"
        local yieldCounter = 0

        -- Count total eligible items first for progress tracking
        local totalEligible = 0
        for dbKey, data in pairs(Auctionator.Database.db) do
            if type(data) == "table" and data.h then
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d >= sinceDay then
                        totalEligible = totalEligible + 1
                        break
                    end
                end
            end
        end

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Start]|r Sending %d items via %d parallel channels (base-36 encoded)", totalEligible, numPrefixes))
        end

        for dbKey, data in pairs(Auctionator.Database.db) do
            scanned = scanned + 1
            _G.MarketSyncActivePullKey = tostring(dbKey)
            if type(data) == "table" and data.h then
                local lastSeenDay = -1
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d > lastSeenDay then lastSeenDay = d end
                end
                if lastSeenDay >= sinceDay then
                    local itemID = dbKey

                    if itemID then
                        local price = tonumber(data.m) or 0
                        local dateStr = tostring(lastSeenDay)
                        local quantity = (data.a and data.a[dateStr]) or 0
                        -- Base-36 encode numeric fields, dbKey as string
                        local itemStr = tostring(itemID) .. "_" .. ToBase36(price) .. "_" .. ToBase36(quantity) .. "_" .. ToBase36(lastSeenDay)
                        
                        -- Flush buffer if adding this item would exceed the wire limit
                        local currentLen = string.len(buffer)
                        if currentLen > 0 and currentLen + 1 + string.len(itemStr) > MAX_PAYLOAD then
                            -- Send on the current round-robin prefix (injected by the outer ticker)
                            local dp = DATA_PREFIXES[prefixIndex]
                            MarketSync.SendBulkSyncResponse(buffer, dp, "GUILD")
                            MarketSync.TxCount = MarketSync.TxCount + bufferCount
                            sent = sent + bufferCount
                            messagesSent = messagesSent + 1
                            buffer = ""
                            bufferCount = 0
                            yieldCounter = 0
                            
                            -- Checkpoint every 100 items
                            if sent % 100 < 16 then
                                if MarketSync.LogNetworkEvent then
                                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Checkpoint]|r Sent %d / %d items (%d msgs, %d scanned)", sent, totalEligible, messagesSent, scanned))
                                end
                            end
                            
                            coroutine.yield()
                        end
                        
                        if buffer == "" then
                            buffer = itemStr
                        else
                            buffer = buffer .. "," .. itemStr
                        end
                        bufferCount = bufferCount + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
            
            -- Safety yield: prevent WoW from killing the coroutine if we scan too many
            -- items without a buffer flush (e.g. many skipped/ineligible items in a row)
            yieldCounter = yieldCounter + 1
            if yieldCounter >= 500 then
                yieldCounter = 0
                coroutine.yield()
            end
        end
        -- Flush remaining buffer
        if buffer ~= "" then
            local dp = DATA_PREFIXES[prefixIndex]
            MarketSync.SendBulkSyncResponse(buffer, dp, "GUILD")
            MarketSync.TxCount = MarketSync.TxCount + bufferCount
            sent = sent + bufferCount
            messagesSent = messagesSent + 1
        end
        Debug("PULL response complete: sent " .. sent .. " items in " .. messagesSent .. " messages")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Complete]|r Sent %d items in %d messages via %d channels. (%d scanned, %d skipped)", sent, messagesSent, numPrefixes, scanned, skipped))
        end
        if requester and IsInGuild() then
            -- Send an explicit END signal including our SwarmTSF so the receiver
            -- stamps the SAME time as us (prevents ping-pong re-sync loops)
            local myScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().SwarmTSF) or 0
            SendAddonMessage(PREFIX, string.format("END;%d;%d;%s", sent, messagesSent, tostring(myScanTime)), "GUILD")
        end
        ClearClaim(MarketSync.PullQueue, sinceDay)
        pullInProgress = false
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
        ScheduleDeferredADVProcessing()
    end)

    -- Multi-prefix round-robin: 5 prefixes available
    -- Total sustained: ~5 msg/sec × ~16 items/msg = ~80 items/sec.
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if not MarketSync.CanSync() then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent("|cffff8800[Swarm]|r PULL response paused/stopped by Smart Rules.")
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            end
            ticker:Cancel()
            ClearClaim(MarketSync.PullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
            return
        end

        -- GLOBAL SELF-THROTTLING
        -- Pause sync if global traffic (including other addons) is nearing disconnect limits
        local apiLimit = 40
        local byteLimit = 750
        if (MarketSync.GlobalTxAPIRate or 0) > apiLimit or (MarketSync.GlobalTxBytesRate or 0) > byteLimit then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Throttled") end
            -- Log only occasionally to avoid spamming the log during sustained throttling
            if not MarketSync.lastThrottleLog or (time() - MarketSync.lastThrottleLog) > 5 then
                MarketSync.lastThrottleLog = time()
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Throttled]|r Global server load is too high (%d msgs/s, %d B/s); pausing sync...", MarketSync.GlobalTxAPIRate, MarketSync.GlobalTxBytesRate))
                end
            end
            return -- Skip this tick
        else
            -- Restore status if we were throttled
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending") end
        end

        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            ClearClaim(MarketSync.PullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
            return
        end
        
        -- Advance prefix index before resuming coroutine
        -- The coroutine will use this to send its chunk
        prefixIndex = (prefixIndex % numPrefixes) + 1
        
        local ok, err = coroutine.resume(co)
        if not ok then
            local crashKey = _G.MarketSyncActivePullKey or "Unknown"
            Debug("PULL response error at key [" .. crashKey .. "]: " .. tostring(err))
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Swarm Sync halted entirely. CRASH at dbKey: %s. Err: %s", crashKey, tostring(err)))
            end
            if IsInGuild() and requester then
                SendAddonMessage(PREFIX, string.format("ERR;%s;%s", requester, crashKey), "GUILD")
            end
            ticker:Cancel()
            ClearClaim(MarketSync.PullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
        end
    end)
end

-- ================================================================
-- UPDATE LOCAL DATABASE (Smart Merge)
-- ================================================================
function MarketSync.UpdateLocalDBByKey(key, price, day, quantity, sender)
    if sender and IsBlocked(sender) then return end

    local realmDB = MarketSync.GetRealmDB() -- Cache once per call (hot path during sync)
    local itemLink = "item:" .. tostring(key) -- Fallback for logs

        local currentPrice = Auctionator.Database:GetPrice(key)
        local currentAge = Auctionator.Database:GetPriceAge(key)

        local currentScanDay = GetCurrentScanDay()
        local incomingScanDay = day

        -- DIRECT INSERTION to ensure persistence
        local priceData = Auctionator.Database.db[key]
        if not priceData then
            priceData = { l={}, h={}, m=0, a={} }
            Auctionator.Database.db[key] = priceData
            Debug("Creating new DB entry for " .. key)
        end

        if not priceData.a then priceData.a = {} end

        local scanDayStr = tostring(incomingScanDay)
        local currentHigh = priceData.h[scanDayStr]
        local currentLow = priceData.l[scanDayStr]

        -- 1. SMART MERGE HISTORY
        local historyUpdated = false

        if currentHigh == nil or price > currentHigh then
            priceData.h[scanDayStr] = price
            currentHigh = price
            historyUpdated = true
        end

        if price < currentHigh and (currentLow == nil or price < currentLow) then
            priceData.l[scanDayStr] = price
            historyUpdated = true
        end

        -- Merge Quantity
        if quantity and quantity > 0 then
            local currentQty = priceData.a[scanDayStr]
            if not currentQty or quantity > currentQty then
                priceData.a[scanDayStr] = quantity
                historyUpdated = true
            end
        end

        -- 2. UPDATE LATEST PRICE ('m')
        local maxDay = 0
        for d, _ in pairs(priceData.h) do
            local dayNum = tonumber(d)
            if dayNum and dayNum > maxDay then maxDay = dayNum end
        end

        if incomingScanDay >= maxDay or priceData.m == 0 then
            priceData.m = price
            Debug("Updated Latest Price (m) for " .. itemLink .. " to " .. FormatMoney(price))
        elseif historyUpdated then
            Debug("Merged Historical Data for " .. itemLink .. " (Day " .. incomingScanDay .. ")")
        end

        if sender and (historyUpdated or incomingScanDay >= maxDay) then
            TrackSync(sender, 1)
            if not realmDB.ItemMetadata then realmDB.ItemMetadata = {} end
            
            -- Per-day attribution: each scan day credits the actual sender
            local meta = realmDB.ItemMetadata[key]
            if not meta then
                meta = { days = {}, lastSource = sender, lastTime = time() }
                realmDB.ItemMetadata[key] = meta
            end
            if not meta.days then meta.days = {} end
            
            local dayStr = tostring(incomingScanDay)
            -- Only attribute to sender if they actually provided new/better data
            -- If we already had the exact same price for this day, don't overwrite the source
            local isNewData = historyUpdated or (not priceData.h[dayStr])
            
            if not meta.days[dayStr] or isNewData then
                meta.days[dayStr] = { source = sender, time = time() }
            end
            -- Always track the most recent contributor
            meta.lastSource = sender
            meta.lastTime = time()
            if MarketSync.InvalidateSyncContributorCache then
                MarketSync.InvalidateSyncContributorCache()
            end

            -- Route to guild incoming buffer (won't disrupt live browsing)
            if MarketSync.AddToGuildIncoming then
                MarketSync.AddToGuildIncoming(key)
            end
        end

        -- Log to History
        if not realmDB.HistoryLog then realmDB.HistoryLog = {} end
        table.insert(realmDB.HistoryLog, 1, { link = itemLink, price = price, sender = sender or "Self", time = time() })
        if #realmDB.HistoryLog > 100 then table.remove(realmDB.HistoryLog) end

        if MarketSync.EvaluateNotificationsForRecord then
            MarketSync.EvaluateNotificationsForRecord(key, price, "main", sender)
        end
end

function MarketSync.UpdateLocalNeutralDBByKey(key, price, day, quantity, sender, isLocalCapture)
    local realmDB = MarketSync.GetRealmDB()
    if not realmDB.NeutralData then realmDB.NeutralData = {} end
    if not realmDB.NeutralMeta then realmDB.NeutralMeta = {} end

    local entry = realmDB.NeutralData[key]
    if not entry then
        entry = { m = 0, d = 0, q = 0, h = {}, l = {}, a = {} }
        realmDB.NeutralData[key] = entry
    end
    if not entry.h then entry.h = {} end
    if not entry.l then entry.l = {} end
    if not entry.a then entry.a = {} end

    local incomingDay = tonumber(day) or 0
    local incomingPrice = tonumber(price) or 0
    local incomingQty = tonumber(quantity) or 0
    if incomingPrice <= 0 then return end

    local dayStr = tostring(incomingDay)
    local curHigh = entry.h[dayStr]
    local curLow = entry.l[dayStr]
    local historyUpdated = false
    if not curHigh or incomingPrice > curHigh then
        entry.h[dayStr] = incomingPrice
        historyUpdated = true
    end
    if not curLow or incomingPrice < curLow then
        entry.l[dayStr] = incomingPrice
        historyUpdated = true
    end
    if incomingQty > (tonumber(entry.a[dayStr]) or 0) then
        entry.a[dayStr] = incomingQty
        historyUpdated = true
    end

    local isNewData = historyUpdated or (not curHigh)
    if incomingDay >= (tonumber(entry.d) or 0) then
        entry.d = incomingDay
        entry.m = incomingPrice
        entry.q = incomingQty
    end

    local meta = realmDB.NeutralMeta[key] or {}
    if not meta.time or isNewData then
        meta.source = sender or (isLocalCapture and "Personal" or "Unknown")
        meta.time = time()
        meta.state = "Complete"
    end
    realmDB.NeutralMeta[key] = meta
    if MarketSync.InvalidateSyncContributorCache then
        MarketSync.InvalidateSyncContributorCache()
    end

    if sender and sender ~= UnitName("player") then
        if not realmDB.NeutralSync then realmDB.NeutralSync = {} end
        if not realmDB.NeutralSync.SyncStats then realmDB.NeutralSync.SyncStats = {} end
        local stats = realmDB.NeutralSync.SyncStats[sender] or { count = 0, last = 0 }
        stats.count = (stats.count or 0) + 1
        stats.last = time()
        realmDB.NeutralSync.SyncStats[sender] = stats
    end

    if MarketSync.AddToNeutralIncoming then
        MarketSync.AddToNeutralIncoming(key)
    end

    if MarketSync.EvaluateNotificationsForRecord then
        MarketSync.EvaluateNotificationsForRecord(key, incomingPrice, "neutral", sender)
    end
end

function MarketSync.UpdateLocalNeutralDB(itemLink, price, day, quantity, sender, isLocalCapture)
    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
        if not dbKeys or #dbKeys == 0 then return end
        MarketSync.UpdateLocalNeutralDBByKey(dbKeys[1], price, day, quantity, sender, isLocalCapture)
    end)
end

function MarketSync.UpdateLocalDB(itemLink, price, day, quantity, sender)
    if sender and IsBlocked(sender) then return end

    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
        if not dbKeys or #dbKeys == 0 then return end
        local key = dbKeys[1]
        MarketSync.UpdateLocalDBByKey(key, price, day, quantity, sender)
    end)
end

-- ================================================================
-- PASSIVE SYNC (Advertisement-based)
-- ================================================================
local passiveTicker

function MarketSync.StartPassiveSync()
    if passiveTicker then passiveTicker:Cancel() end

    -- Advertise availability after a short delay on login
    C_Timer.After(15, function()
        if MarketSyncDB and MarketSyncDB.PassiveSync then
            MarketSync.SendAdvertisement()
            if MarketSync.SendNeutralAdvertisement then
                MarketSync.SendNeutralAdvertisement()
            end
        end
    end)

    -- Re-advertise every 5 minutes
    passiveTicker = C_Timer.NewTicker(300, function()
        if not MarketSyncDB or not MarketSyncDB.PassiveSync then return end
        MarketSync.SendAdvertisement() -- CanSync() inside handles combat/instance/arena suppression
        if MarketSync.SendNeutralAdvertisement then
            MarketSync.SendNeutralAdvertisement()
        end
    end)
end

-- ================================================================
-- BULK BROADCAST (Manual Sync)
-- ================================================================
function MarketSync.BroadcastRecentData()
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        print("|cFFFF8800[MarketSync]|r Sync busy. Wait for current blast to finish before starting a new broadcast.")
        SetTransientBlockedState("send/receive active")
        return
    end

    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return
    end

    broadcastInProgress = true
    print("|cFF00FF00[MarketSync]|r Starting bulk sync scan (this may take a moment)...")

    local co = coroutine.create(function()
        local count = 0
        local broadcastList = {}

        local currentScanDay = GetCurrentScanDay()
        if currentScanDay == 0 then
            print("|cFFFF0000[MarketSync]|r Error: Could not determine scan day!")
            return
        end

        local RECENT_THRESHOLD = 5
        local itemsChecked = 0

        for dbKey, data in pairs(Auctionator.Database.db) do
            itemsChecked = itemsChecked + 1
            if itemsChecked % 500 == 0 then coroutine.yield() end

            if type(data) == "table" and data.h then
                local lastSeenDay = -1
                for dayStr, _ in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d > lastSeenDay then lastSeenDay = d end
                end

                if lastSeenDay >= (currentScanDay - RECENT_THRESHOLD) then
                    local price = data.m
                    local dateStr = tostring(lastSeenDay)
                    local quantity = 0
                    if data.a and data.a[dateStr] then quantity = data.a[dateStr] end

                    local itemID = nil
                    if type(dbKey) == "number" then
                        itemID = dbKey
                    elseif type(dbKey) == "string" then
                        local idStr = dbKey:match("(%d+)")
                        if idStr then itemID = tonumber(idStr) end
                    end

                    if itemID then
                        local itemLink
                        local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
                        
                        if classID then
                             _, itemLink = C_Item.GetItemInfo(itemID)
                        end
                        
                        if not itemLink then 
                             itemLink = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0"
                        end
                        
                        if itemLink then
                            table.insert(broadcastList, {link = itemLink, price = price, day = lastSeenDay, quantity = quantity})
                            count = count + 1
                        end
                    end
                end
            end
        end

        if #broadcastList > 0 then
            print(string.format("|cFF00FF00[MarketSync]|r Found %d items. Broadcasting safely (this runs in the background)...", #broadcastList))
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending") end
        else
            print("|cFFFF0000[MarketSync]|r No recent validation items found to broadcast.")
        end

        for i, item in ipairs(broadcastList) do
            if item.link then
                MarketSync.SendSyncResponse(item.link, item.price, item.day, item.quantity, "GUILD")
            end
            if i % 5 == 0 then coroutine.yield() end
        end
        print("|cFF00FF00[MarketSync]|r Bulk sync broadcast completed.")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Bulk sync broadcast completed. Sent %d items.", #broadcastList))
        end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
        broadcastInProgress = false
        ScheduleDeferredADVProcessing()
    end)

    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            if broadcastInProgress then
                broadcastInProgress = false
                ScheduleDeferredADVProcessing()
            end
            return
        end
        local success, err = coroutine.resume(co)
        if not success then
            print("|cFFFF0000[MarketSync] Sync Error:|r", err)
            broadcastInProgress = false
            ticker:Cancel()
            ScheduleDeferredADVProcessing()
        end
    end)
end

-- ================================================================
-- SEARCH (CLI)
-- ================================================================
function MarketSync.SearchLocalDB(query)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return
    end

    query = query:lower()
    local found = 0
    print(string.format("|cFF00FF00[MarketSync]|r Search results for '%s':", query))

    for dbKey, data in pairs(Auctionator.Database.db) do
        local itemID = nil
        if type(dbKey) == "number" then
            itemID = dbKey
        elseif type(dbKey) == "string" then
            local idStr = dbKey:match("(%d+)")
            if idStr then itemID = tonumber(idStr) end
        end

        if itemID then
            local name, link = C_Item.GetItemInfo(itemID)
            if name and name:lower():find(query) then
                local price = Auctionator.Database:GetPrice(dbKey)
                local age = Auctionator.Database:GetPriceAge(dbKey)
                if price then
                    print(string.format("  %s: %s (%s)", link or name, FormatMoney(price), MarketSync.FormatAge(age)))
                    found = found + 1
                    if found >= 20 then
                        print("  ... and more.")
                        break
                    end
                end
            end
        end
    end
    if found == 0 then print("  No results found.") end
end


