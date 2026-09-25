-- =============================================================
-- MarketSync - Chat Module
-- Event handling for addon messages and chat queries
-- =============================================================

local PREFIX = MarketSync.PREFIX
local Debug = MarketSync.Debug
local FormatMoney = MarketSync.FormatMoney
local FormatAge = MarketSync.FormatAge

-- Protocol-2 sessions stage raw DATA strings until END proves that every
-- sequence exists.  Main and neutral state remain isolated even though the
-- guild uses a single physical transfer lane.
local guildSyncCommitTimer = nil -- retained only for unreachable v1 handlers below
local GUILD_SYNC_IDLE_TIMEOUT = 5
local sessionRxTotal = 0
local scanCacheInvalidatedThisSession = false
local rxSessions = { M = nil, N = nil }
local rejectedSessions = { M = nil, N = nil }
local pendingFreshADV = nil
local pendingFreshNeutralADV = nil
local SMART_RULES_SYNC_MSG = {
    PULL = true,
    ACCEPT = true,
    REQ = true,
    BRES = true,
    RES = true,
    END = true,
    NPULL = true,
    NACCEPT = true,
    NBRES = true,
    NEND = true,
    BEGIN = true,
    DATA = true,
    ABORT = true,
    HOLD = true,
}
local PRICE_CHECK_MIN_INTERVAL = 2
local PRICE_CHECK_WINDOW_SEC = 15
local PRICE_CHECK_MAX_REQUESTS = 4
local PRICE_CHECK_MUTE_SEC = 60
local PRICE_CHECK_ROUTE_BY_EVENT = {
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_OFFICER = "OFFICER",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    CHAT_MSG_CHANNEL = "CHANNEL",
}
local priceCheckRequestState = {}

-- ================================================================
-- EVENT FRAME
-- ================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHAT_MSG_SAY")
frame:RegisterEvent("CHAT_MSG_YELL")
frame:RegisterEvent("CHAT_MSG_OFFICER")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_ADDON")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_INSTANCE_CHAT")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_INSTANCE_CHAT_LEADER")

local function CompareVersions(v1, v2)
    local function parse(v)
        v = tostring(v)
        local major, minor, patch = v:match("(%d+)%.(%d+)%.?(%d*)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end
    local m1, n1, p1 = parse(v1)
    local m2, n2, p2 = parse(v2)
    if m1 > m2 then return 1 end
    if m1 < m2 then return -1 end
    if n1 > n2 then return 1 end
    if n1 < n2 then return -1 end
    if p1 > p2 then return 1 end
    if p1 < p2 then return -1 end
    return 0
end

local function IsADVNewer(left, right)
    if not right then return true end
    if (left.scanDay or 0) ~= (right.scanDay or 0) then
        return (left.scanDay or 0) > (right.scanDay or 0)
    end
    if (left.scanTime or 0) ~= (right.scanTime or 0) then
        return (left.scanTime or 0) > (right.scanTime or 0)
    end
    if (left.itemCount or 0) ~= (right.itemCount or 0) then
        return (left.itemCount or 0) > (right.itemCount or 0)
    end
    -- Stable final tie-break means every guild member elects the same source
    -- even if two equal advertisements arrive in a different order.
    return string.lower(tostring(left.senderIdentity or left.sender or ""))
        < string.lower(tostring(right.senderIdentity or right.sender or ""))
end

local function ComputeFreshness(advBucket, advItemCount, advScanTime)
    local ourBucket = MarketSync.GetMyLatestBucket()
    local ourItemCount = 0
    if advBucket == ourBucket then
        ourItemCount = MarketSync.CountRecentItemsBucket(ourBucket)
    end
    local ourScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().SwarmTSF) or 0
    local ourTotalCount = (MarketSync.GetTotalPersonalItemCount and MarketSync.GetTotalPersonalItemCount()) or 0

    local isFresher = false
    if advBucket > ourBucket then
        -- They have a newer bucket, always fresher
        isFresher = true
    elseif advBucket == ourBucket then
        -- In the same bucket:
        -- If peer has more items (e.g. peer performed a full scan while we only have a partial scan),
        -- or if peer's scan time is newer and they do not have fewer items.
        if (advItemCount or 0) > ourItemCount then
            isFresher = true
        elseif advScanTime > ourScanTime and (advItemCount or 0) >= ourItemCount then
            isFresher = true
        elseif advScanTime == 0 and (advItemCount or 0) > ourItemCount then
            isFresher = true
        end
    elseif ourTotalCount < 200 and (advItemCount or 0) > 500 then
        -- Baseline bootstrap: local database has sparse/empty catalog (< 200 items), while peer
        -- advertises a full catalog (> 500 items). Request baseline catchup from bucket 0.
        isFresher = true
        ourBucket = 0
    end

    return isFresher, ourBucket, ourItemCount, ourScanTime
end

local function ComputeNeutralFreshness(advScanDay, advItemCount, advScanTime)
    local ourDay = (MarketSync.GetMyLatestNeutralScanDay and MarketSync.GetMyLatestNeutralScanDay()) or 0
    local ourItemCount = 0
    if advScanDay == ourDay and MarketSync.CountNeutralRecentItems then
        ourItemCount = MarketSync.CountNeutralRecentItems(ourDay)
    end
    local ourScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().NeutralSwarmTSF) or 0

    local isFresher = false
    if advScanDay > ourDay then
        isFresher = true
    elseif advScanDay == ourDay then
        if advScanTime > ourScanTime then
            isFresher = true
        elseif advScanTime == 0 and advItemCount > ourItemCount then
            isFresher = true
        end
    end

    return isFresher, ourDay, ourItemCount, ourScanTime
end

local function QueueDeferredADV(advData)
    if not pendingFreshADV or IsADVNewer(advData, pendingFreshADV) then
        pendingFreshADV = advData
        Debug(string.format("Queued deferred ADV from %s (day=%d, tsf=%d, items=%d)",
            tostring(advData.sender), tonumber(advData.scanDay) or 0, tonumber(advData.scanTime) or 0, tonumber(advData.itemCount) or 0))
    end
end

local function QueueDeferredNeutralADV(advData)
    if not pendingFreshNeutralADV or IsADVNewer(advData, pendingFreshNeutralADV) then
        pendingFreshNeutralADV = advData
        Debug(string.format("Queued deferred NADV from %s (day=%d, tsf=%d, items=%d)",
            tostring(advData.sender), tonumber(advData.scanDay) or 0, tonumber(advData.scanTime) or 0, tonumber(advData.itemCount) or 0))
    end
end

local function ScheduleDeferredADVProcessing()
    if not MarketSync.ProcessDeferredADV then return end
    C_Timer.After(0.25, function()
        if MarketSync.ProcessDeferredADV then
            MarketSync.ProcessDeferredADV()
        end
    end)
end

local function GetLocalPriceCheckIdentity()
    if type(UnitFullName) == "function" then
        local playerName, playerRealm = UnitFullName("player")
        if playerName and playerName ~= "" then
            if playerRealm and playerRealm ~= "" then
                return tostring(playerName) .. "-" .. tostring(playerRealm)
            end
            return tostring(playerName)
        end
    end
    return tostring(UnitName("player") or "Unknown")
end

local function NormalizePriceCheckSender(sender)
    local raw = tostring(sender or "")
    if raw == "" then return nil end
    return string.lower(raw)
end

local function BuildPriceCheckQueryKey(senderKey, itemID)
    local item = tonumber(itemID)
    if not senderKey or not item then return nil end
    return string.format("%s:%d", tostring(senderKey), item)
end

local function ExtractPriceCheckItemID(queryKey)
    local raw = tostring(queryKey or "")
    if raw == "" then return nil end
    return tonumber(raw:match(":(%d+)$")) or tonumber(raw)
end

local function CancelPendingPriceCheck(queryKey, reason)
    if not queryKey or not MarketSync.pendingQueries or not MarketSync.pendingQueries[queryKey] then
        return false
    end
    local pending = MarketSync.pendingQueries[queryKey]
    MarketSync.pendingQueries[queryKey] = nil
    if reason then
        Debug(string.format("Suppressed reply for %s (%s)", tostring(pending.itemID or queryKey), tostring(reason)))
    end
    return true
end

local function CancelPendingQueriesByItem(itemID, reason)
    if not itemID or not MarketSync.pendingQueries then return 0 end
    local canceled = 0
    for queryKey, pending in pairs(MarketSync.pendingQueries) do
        if pending and tonumber(pending.itemID) == tonumber(itemID) then
            MarketSync.pendingQueries[queryKey] = nil
            canceled = canceled + 1
        end
    end
    if canceled > 0 and reason then
        Debug(string.format("Suppressed %d pending reply(s) for %d (%s)", canceled, tonumber(itemID) or 0, tostring(reason)))
    end
    return canceled
end

local function GetPriceCheckCoordinationRoute(event, channelID)
    local distribution = PRICE_CHECK_ROUTE_BY_EVENT[event]
    if not distribution then
        return nil, nil
    end
    if distribution == "CHANNEL" then
        local id = tonumber(channelID)
        if id and id > 0 then
            return distribution, id
        end
        return nil, nil
    end
    if (distribution == "GUILD" or distribution == "OFFICER") and not IsInGuild() then
        return nil, nil
    end
    return distribution, nil
end

local function SendPriceCheckClaim(event, channelID, itemID, senderKey)
    local distribution, target = GetPriceCheckCoordinationRoute(event, channelID)
    if not distribution or not itemID or not senderKey then
        return false
    end
    local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, string.format("CLAIM;%d;%s", tonumber(itemID) or 0, tostring(senderKey)), distribution, target)
    return ok
end

local function AllowPriceCheckRequest(senderKey)
    if not senderKey then
        return false, "missing sender"
    end

    local now = (type(GetTime) == "function" and GetTime()) or 0
    local state = priceCheckRequestState[senderKey]
    if not state then
        state = {
            windowStart = now,
            count = 0,
            lastAt = -math.huge,
            rapidHits = 0,
            mutedUntil = 0,
        }
        priceCheckRequestState[senderKey] = state
    end

    if now < (state.mutedUntil or 0) then
        return false, "muted"
    end

    if (now - (state.windowStart or 0)) > PRICE_CHECK_WINDOW_SEC then
        state.windowStart = now
        state.count = 0
        state.rapidHits = 0
    end

    if (now - (state.lastAt or -math.huge)) < PRICE_CHECK_MIN_INTERVAL then
        state.rapidHits = (state.rapidHits or 0) + 1
        state.lastAt = now
        if state.rapidHits >= 3 then
            state.mutedUntil = now + PRICE_CHECK_MUTE_SEC
            return false, "rapid mute"
        end
        return false, "rapid"
    end

    state.lastAt = now
    state.count = (state.count or 0) + 1
    state.rapidHits = 0

    if state.count > PRICE_CHECK_MAX_REQUESTS then
        state.mutedUntil = now + PRICE_CHECK_MUTE_SEC
        return false, "burst mute"
    end

    return true
end

function MarketSync.ProcessDeferredADV()
    if not MarketSync.CanSync or not MarketSync.CanSync() then return false end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then return false end

    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local localVersion = MarketSync.GetAddOnMetadata("MarketSync", "Version") or "0.0.0"

    -- Process standard deferred ADV first.
    if pendingFreshADV then
        local adv = pendingFreshADV
        pendingFreshADV = nil

        if adv.realm == MarketSync.myRealm then
            local cmp = CompareVersions(adv.version or "0.4.0-beta", localVersion)
            if cmp > 0 then
                if MarketSyncDB and MarketSyncDB.PassiveSync then
                    MarketSyncDB.PassiveSync = false
                    print(string.format("|cFFFF0000[MarketSync]|r Sync Disabled! You are running an outdated version (v%s). %s is running v%s. Please update your addon.", localVersion, adv.sender or "Unknown", adv.version or "unknown"))
                end
                return false
            elseif cmp == 0 then
                local isFresher, ourDay, ourItemCount, ourScanTime = ComputeFreshness(adv.scanDay or 0, adv.itemCount or 0, adv.scanTime or 0)
                if isFresher then
                    Debug(string.format("Processing deferred ADV from %s (Day %d vs %d, Time %d vs %d, Items %d vs %d)",
                        adv.sender or "Unknown", adv.scanDay or 0, ourDay, adv.scanTime or 0, ourScanTime, adv.itemCount or 0, ourItemCount))
                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent(string.format("|cff00ccff[Deferred ADV]|r Pulling freshest queued source: %s (Day %d, TSF %d).", adv.sender or "Unknown", adv.scanDay or 0, adv.scanTime or 0))
                    end
                    if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving") end
                    if MarketSync.BeginGuildSync then
                        MarketSync.BeginGuildSync()
                    end
                    MarketSync.SendPullRequest(ourDay)
                    return true
                end
            end
        end
    end

    -- Then process neutral deferred ADV.
    if pendingFreshNeutralADV then
        local adv = pendingFreshNeutralADV
        pendingFreshNeutralADV = nil
        if adv.realm ~= MarketSync.myRealm then return false end

        local cmp = CompareVersions(adv.version or "0.4.0-beta", localVersion)
        if cmp ~= 0 then return false end

        local isFresher, ourDay = ComputeNeutralFreshness(adv.scanDay or 0, adv.itemCount or 0, adv.scanTime or 0)
        if not isFresher then return false end

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ccff[Deferred NADV]|r Pulling freshest queued neutral source: %s (Day %d, TSF %d).", adv.sender or "Unknown", adv.scanDay or 0, adv.scanTime or 0))
        end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving Neutral") end
        if MarketSync.BeginNeutralSync then
            MarketSync.BeginNeutralSync()
        end
        if MarketSync.SendNeutralPullRequest then
            MarketSync.SendNeutralPullRequest(ourDay)
            return true
        end
    end

    return false
end

-- ================================================================
-- SYNC PROTOCOL 2 RECEIVE / COORDINATION
-- ================================================================

-- Replace the legacy deferred processor above.  Main has priority when both
-- logical flows have a queued advertisement; neutral remains queued until the
-- shared guild lane becomes idle.
function MarketSync.ProcessDeferredADV()
    if not MarketSync.CanSync or not MarketSync.CanSync() then return false end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then return false end
    if MarketSync.SyncVersionBlocked then return false end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end

    local function tryAdvertisement(scope, adv)
        if not adv or adv.realm ~= MarketSync.myRealm then return false end
        if not MarketSync.IsPeerDataCompatible(adv.version, adv.protocol) then return false end
        if not MarketSync.CanParticipateInData(scope) then return false end
        local rejected = rejectedSessions[scope]
        if rejected then
            local revision = tonumber(adv.scanDay) or 0
            local scanTime = tonumber(adv.scanTime) or 0
            if revision < rejected.revision
                or (revision == rejected.revision and scanTime <= rejected.scanTime) then
                -- Never turn a rejected transfer into an automatic catch-up.
                -- We can still receive this revision if another guild member
                -- requests it, but locally we only request a genuinely newer ADV.
                return false
            end
        end

        local isFresher, ourRevision
        if scope == "N" then
            isFresher, ourRevision = ComputeNeutralFreshness(adv.scanDay or 0, adv.itemCount or 0, adv.scanTime or 0)
        else
            isFresher, ourRevision = ComputeFreshness(adv.scanDay or 0, adv.itemCount or 0, adv.scanTime or 0)
        end
        if not isFresher then return false end

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format(
                "|cff00ccff[Deferred %sADV]|r Elected exact source %s (revision %d, TSF %d).",
                scope == "N" and "N" or "", tostring(adv.senderIdentity or adv.sender),
                tonumber(adv.scanDay) or 0, tonumber(adv.scanTime) or 0))
        end
        return MarketSync.ScheduleDirectedPull(scope, ourRevision or 0,
            adv.senderIdentity or adv.sender, adv.scanDay or 0, adv.scanTime or 0)
    end

    if pendingFreshADV then
        local adv = pendingFreshADV
        pendingFreshADV = nil
        if tryAdvertisement("M", adv) then return true end
    end
    if pendingFreshNeutralADV then
        local adv = pendingFreshNeutralADV
        pendingFreshNeutralADV = nil
        if tryAdvertisement("N", adv) then return true end
    end
    return false
end

local function DecodeDBKey(encoded)
    local value = tostring(encoded or "")
    local marker = value:sub(1, 1)
    local body = value:sub(2)
    if marker == "n" then
        local numeric = MarketSync.FromBase36(body)
        if numeric and numeric > 0 then return numeric end
        return nil
    elseif marker == "s" and body ~= "" then
        return body
    end
    return nil
end

local function DecodeWireBase36(value)
    local text = tostring(value or "")
    if text == "" or not text:match("^[0-9a-z]+$") then return nil end
    local decoded = tonumber(text, 36)
    if not decoded or decoded < 0 or decoded ~= math.floor(decoded) then return nil end
    return decoded
end

local function GetLocalScopeFreshness(scope)
    local realmDB = MarketSync.GetRealmDB()
    if scope == "N" then
        return (MarketSync.GetMyLatestNeutralScanDay and MarketSync.GetMyLatestNeutralScanDay()) or 0,
            tonumber(realmDB.NeutralSwarmTSF) or 0
    end
    return (MarketSync.GetMyLatestBucket and MarketSync.GetMyLatestBucket()) or 0,
        tonumber(realmDB.SwarmTSF) or 0
end

local function IsTargetFresher(scope, revision, scanTime)
    local localRevision, localScanTime = GetLocalScopeFreshness(scope)
    return revision > localRevision
        or (revision == localRevision and scanTime > localScanTime),
        localRevision, localScanTime
end

local function ParseStagedOperations(session, finalSequence, expectedRecords)
    if finalSequence < 0 or finalSequence > 100000 then return nil, "invalid final sequence" end
    local operations = {}
    local parsedRecords = 0

    for sequence = 1, finalSequence do
        local payload = session.chunks[sequence]
        if not payload then return nil, "missing sequence " .. tostring(sequence) end

        for record in string.gmatch(payload, "([^,]+)") do
            parsedRecords = parsedRecords + 1
            if session.scope == "M" then
                local encodedKey, dayB36, encodedPoints = record:match("^([^_]+)_([^_]+)_(.+)$")
                local dbKey = DecodeDBKey(encodedKey)
                local day = DecodeWireBase36(dayB36)
                if not dbKey or not day or day <= 0 or not encodedPoints then
                    return nil, "malformed main record"
                end

                local decodedPoints = {}
                for point in string.gmatch(encodedPoints, "([^.]+)") do
                    local offsetText, priceB36, qtyB36 = point:match("^(%d+):([0-9a-z]+):([0-9a-z]+)$")
                    local offset = tonumber(offsetText)
                    local price = DecodeWireBase36(priceB36)
                    local quantity = DecodeWireBase36(qtyB36)
                    if not offset or offset < 0 or offset >= 48 or not price or price <= 0 or not quantity or quantity < 0 then
                        return nil, "malformed main point"
                    end
                    table.insert(decodedPoints, string.format("%d:%s:%s", offset, priceB36, qtyB36))
                end
                if #decodedPoints == 0 then return nil, "empty main record" end
                table.insert(operations, {
                    key = dbKey,
                    day = day,
                    history = table.concat(decodedPoints, ","),
                })
            else
                local encodedKey, priceB36, qtyB36, dayB36 = record:match("^([^_]+)_([^_]+)_([^_]+)_([^_]+)$")
                local dbKey = DecodeDBKey(encodedKey)
                local price = DecodeWireBase36(priceB36)
                local quantity = DecodeWireBase36(qtyB36)
                local day = DecodeWireBase36(dayB36)
                if not dbKey or not price or price <= 0 or not quantity or quantity < 0 or not day or day <= 0 then
                    return nil, "malformed neutral record"
                end
                table.insert(operations, { key = dbKey, price = price, quantity = quantity, day = day })
            end
        end
    end

    if parsedRecords ~= expectedRecords then
        return nil, string.format("record count mismatch (%d/%d)", parsedRecords, expectedRecords)
    end
    return operations
end

local function CloneSyncValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, nestedValue in pairs(value) do
        copy[CloneSyncValue(key, seen)] = CloneSyncValue(nestedValue, seen)
    end
    return copy
end

-- Keep originals for only the records touched by this transfer. The working
-- copies become live on success; an apply exception can restore every original
-- reference without cloning the entire Auctionator database.
local function BuildApplyTransaction(session, operations)
    local realmDB = MarketSync.GetRealmDB()
    local transaction = {
        realmDB = realmDB,
        entries = {},
        realmTables = {},
        realmValues = {
            { field = "LatestBucket", original = realmDB.LatestBucket },
            { field = "SwarmTSF", original = realmDB.SwarmTSF },
            { field = "NeutralSwarmTSF", original = realmDB.NeutralSwarmTSF },
            { field = "NeutralVerifiedDay", original = realmDB.NeutralVerifiedDay },
            { field = "NeutralScanTime", original = realmDB.NeutralScanTime },
            { field = "CachedScanStats", original = realmDB.CachedScanStats },
        },
    }
    local cloneMemo = {}

    local function workingRealmTable(field)
        local original = realmDB[field]
        if type(original) == "table" then return original end
        local working = {}
        table.insert(transaction.realmTables, { field = field, original = original, working = working })
        return working
    end

    local function replaceRealmTable(field)
        local original = realmDB[field]
        local working = type(original) == "table" and CloneSyncValue(original, cloneMemo) or {}
        table.insert(transaction.realmTables, { field = field, original = original, working = working })
        return working
    end

    local function journalEntry(container, key)
        local original = container[key]
        table.insert(transaction.entries, {
            container = container,
            key = key,
            existed = original ~= nil,
            original = original,
            working = original ~= nil and CloneSyncValue(original, cloneMemo) or nil,
        })
    end

    local touched = {}
    if session.scope == "N" then
        local neutralData = workingRealmTable("NeutralData")
        local neutralMeta = workingRealmTable("NeutralMeta")
        replaceRealmTable("NeutralSync")
        for _, operation in ipairs(operations) do
            if not touched[operation.key] then
                touched[operation.key] = true
                journalEntry(neutralData, operation.key)
                journalEntry(neutralMeta, operation.key)
            end
        end
    else
        local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)
        if not liveStore and MarketSync.Provider and MarketSync.Provider.GetActiveName() == "auctionator" then
            return nil, "Auctionator database unavailable during apply"
        end
        local personalData = workingRealmTable("PersonalData")
        local itemMetadata = workingRealmTable("ItemMetadata")
        replaceRealmTable("HistoryLog")
        for _, operation in ipairs(operations) do
            if not touched[operation.key] then
                touched[operation.key] = true
                if liveStore then journalEntry(liveStore, operation.key) end
                journalEntry(personalData, operation.key)
                journalEntry(itemMetadata, operation.key)
            end
        end
    end

    function transaction:Install()
        for _, realmTable in ipairs(self.realmTables) do
            self.realmDB[realmTable.field] = realmTable.working
        end
        for _, entry in ipairs(self.entries) do
            entry.container[entry.key] = entry.working
        end
    end

    function transaction:Rollback()
        for index = #self.entries, 1, -1 do
            local entry = self.entries[index]
            if entry.existed then
                entry.container[entry.key] = entry.original
            else
                entry.container[entry.key] = nil
            end
        end
        for index = #self.realmTables, 1, -1 do
            local realmTable = self.realmTables[index]
            self.realmDB[realmTable.field] = realmTable.original
        end
        for _, realmValue in ipairs(self.realmValues) do
            self.realmDB[realmValue.field] = realmValue.original
        end

        -- Begin/Commit buffers are UI-only, but an exception may leave them in
        -- an active state. Invalidating clears both buffers and rebuilds lazily.
        if MarketSync.InvalidateIndexCache then
            pcall(MarketSync.InvalidateIndexCache)
        else
            local beginSync = session.scope == "N" and MarketSync.BeginNeutralSync or MarketSync.BeginGuildSync
            local commitSync = session.scope == "N" and MarketSync.CommitNeutralSync or MarketSync.CommitGuildSync
            if beginSync then pcall(beginSync) end
            if commitSync then pcall(commitSync) end
        end
    end

    return transaction
end

local function CommitStagedSession(session, finalSequence, expectedRecords)
    if session.chunkCount ~= finalSequence then
        return false, string.format("sequence count mismatch (%d/%d)", session.chunkCount, finalSequence)
    end
    local operations, parseError = ParseStagedOperations(session, finalSequence, expectedRecords)
    if not operations then return false, parseError end

    local realmDB = MarketSync.GetRealmDB()
    local revision = tonumber(session.revision) or 0
    local scanTime = tonumber(session.scanTime) or 0
    local oldRevision = session.scope == "N"
        and ((MarketSync.GetMyLatestNeutralScanDay and MarketSync.GetMyLatestNeutralScanDay()) or 0)
        or ((MarketSync.GetMyLatestBucket and MarketSync.GetMyLatestBucket()) or 0)
    local oldScanTime = session.scope == "N"
        and (tonumber(realmDB.NeutralSwarmTSF) or 0)
        or (tonumber(realmDB.SwarmTSF) or 0)

    local buildOK, transaction, transactionError = pcall(BuildApplyTransaction, session, operations)
    if not buildOK then
        return false, "transaction preparation failed: " .. tostring(transaction)
    end
    if not transaction then return false, transactionError end
    local installOK, installError = pcall(transaction.Install, transaction)
    if not installOK then
        pcall(transaction.Rollback, transaction)
        return false, "transaction install failed: " .. tostring(installError)
    end

    local priorCommitState = MarketSync._Protocol2CommitInProgress
    MarketSync._Protocol2CommitInProgress = true
    local committedNotificationPrices = {}
    local function noteCommittedPrice(operation, price, day, offset)
        price = tonumber(price)
        day = tonumber(day) or 0
        offset = tonumber(offset) or 0
        if not price or price <= 0 then return end
        local previous = committedNotificationPrices[operation.key]
        if not previous or day > previous.day
            or (day == previous.day and offset > previous.offset) then
            committedNotificationPrices[operation.key] = {
                price = price,
                day = day,
                offset = offset,
            }
        end
    end
    local ok, applyError = pcall(function()
        if session.scope == "N" then
            if MarketSync.BeginNeutralSync then MarketSync.BeginNeutralSync() end
            for _, operation in ipairs(operations) do
                local acceptedPrice, acceptedDay, acceptedOffset = MarketSync.UpdateLocalNeutralDBByKey(
                    operation.key, operation.price, operation.day,
                    operation.quantity, session.senderName)
                noteCommittedPrice(operation, acceptedPrice, acceptedDay, acceptedOffset)
            end
            if MarketSync.CommitNeutralSync then MarketSync.CommitNeutralSync() end
        else
            if MarketSync.BeginGuildSync then MarketSync.BeginGuildSync() end
            for _, operation in ipairs(operations) do
                local acceptedPrice, acceptedDay, acceptedOffset = MarketSync.UpdateLocalDBByKey(
                    operation.key, operation.day, operation.history, session.senderName)
                noteCommittedPrice(operation, acceptedPrice, acceptedDay, acceptedOffset)
            end
            if MarketSync.CommitGuildSync then MarketSync.CommitGuildSync() end
        end
    end)
    MarketSync._Protocol2CommitInProgress = priorCommitState
    if not ok then
        pcall(transaction.Rollback, transaction)
        return false, "apply failed and was rolled back: " .. tostring(applyError)
    end

    -- Publish only after the verified transaction is committed. The wire
    -- carries 30-minute buckets, not per-auction timestamps; never substitute
    -- receive time or the session's advertised scan time for observation time.
    local observationAPI = MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1
    if observationAPI and observationAPI.HasListeners() then
        local scanId = "sync-" .. tostring(session.id)
        local scope = session.scope == "N" and "neutral" or "main"
        for _, operation in ipairs(operations) do
            local itemID, itemSuffix = MarketSync.ParseItemIDFromDBKey(tostring(operation.key))
            if session.scope == "N" then
                observationAPI.Emit({ event = "observation", scanId = scanId,
                    source = "synced", scope = scope, key = operation.key,
                    itemID = itemID, itemSuffix = itemSuffix, unitPrice = operation.price,
                    quantity = operation.quantity and operation.quantity > 0 and operation.quantity or nil,
                    observedAt = nil, observedDay = operation.day, timePrecision = "day" })
            else
                for offset, priceText, qtyText in string.gmatch(operation.history, "(%d+):([%w%-]+):([%w%-]+)") do
                    local quantity = MarketSync.FromBase36(qtyText)
                    observationAPI.Emit({ event = "observation", scanId = scanId,
                        source = "synced", scope = scope, key = operation.key,
                        itemID = itemID, itemSuffix = itemSuffix,
                        unitPrice = MarketSync.FromBase36(priceText),
                        quantity = quantity and quantity > 0 and quantity or nil,
                        observedAt = nil, observedDay = operation.day,
                        observedBucketOffset = tonumber(offset), timePrecision = "30m" })
                end
            end
        end
        observationAPI.Emit({ event = "finish", scanId = scanId, source = "synced", scope = scope })
    end

    -- A complete zero-record delta is valid: END still advances the verified
    -- source timestamp.  Never move freshness backwards after an older dump.
    if revision > oldRevision or (revision == oldRevision and scanTime >= oldScanTime) then
        if session.scope == "N" then
            realmDB.NeutralVerifiedDay = math.max(tonumber(realmDB.NeutralVerifiedDay) or 0, revision)
            realmDB.NeutralSwarmTSF = math.max(oldScanTime, scanTime)
            realmDB.NeutralScanTime = realmDB.NeutralSwarmTSF
        else
            realmDB.LatestBucket = math.max(tonumber(realmDB.LatestBucket) or 0, revision)
            realmDB.SwarmTSF = math.max(oldScanTime, scanTime)
        end
    end
    realmDB.CachedScanStats = nil
    if MarketSync.EvaluateNotificationsForRecord then
        -- Evaluate only records actually committed by this session. A global
        -- tracked-item sweep can surface unrelated stale cache entries as if
        -- they arrived in the just-finished download.
        local notificationScope = session.scope == "N" and "neutral" or "main"
        for dbKey, committed in pairs(committedNotificationPrices) do
            local notificationOK, notificationError = pcall(
                MarketSync.EvaluateNotificationsForRecord, dbKey, committed.price,
                notificationScope, session.senderName)
            if not notificationOK then
                Debug("Post-commit notification evaluation failed: " .. tostring(notificationError))
            end
        end
    end
    MarketSync.RxCount = #operations
    return true, #operations
end

function MarketSync.DiscardInboundSyncSession(scope, sessionId, reason)
    local session = rxSessions[scope]
    if not session or (sessionId and session.id ~= sessionId) then return false end
    rxSessions[scope] = nil
    if session.observationStarted and MarketSync.ObservationAPI then
        MarketSync.ObservationAPI.v1.Emit({ event = "cancel",
            scanId = "sync-" .. tostring(session.id), source = "synced",
            scope = scope == "N" and "neutral" or "main", reason = reason or "discarded" })
    end
    if session.applyEligible or session.invalidReason then
        rejectedSessions[scope] = {
            revision = tonumber(session.revision) or 0,
            scanTime = tonumber(session.scanTime) or 0,
        }
    end
    MarketSync.RxCount = 0
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), nil)
        MarketSync.UpdateSwarmUI(session.senderName, "Idle")
    end
    Debug(string.format("Discarded incomplete %s session %s (%s)", tostring(scope), tostring(session.id), tostring(reason or "rejected")))
    return true
end

local function HandleAdvertisementV2(scope, realm, revisionText, countText, addonVersion,
                                      scanTimeText, protocolText, status, senderName, senderIdentity)
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    if realm ~= MarketSync.myRealm then return true end

    local protocol = tonumber(protocolText) or 0
    local compatible, versionCmp = MarketSync.NotePeerSyncVersion(addonVersion, protocol, senderName)
    status = tostring(status or ((scanTimeText == "DISABLED") and "DISABLED" or "LEGACY"))
    if not compatible then
        if MarketSync.ForgetSyncPeerBaseline then
            MarketSync.ForgetSyncPeerBaseline(scope, senderIdentity)
        end
        if MarketSync.UpdateSwarmUI then
            local detail = versionCmp < 0 and "Older Version" or "Version Mismatch"
            MarketSync.UpdateSwarmUI(senderName, string.format("%s (v%s/p%d)", detail, tostring(addonVersion), protocol))
        end
        return true
    end
    if MarketSync.IsBlocked and MarketSync.IsBlocked(senderName) then
        if MarketSync.ForgetSyncPeerBaseline then
            MarketSync.ForgetSyncPeerBaseline(scope, senderIdentity)
        end
        return true
    end
    if status ~= "READY" then
        if MarketSync.ForgetSyncPeerBaseline then
            MarketSync.ForgetSyncPeerBaseline(scope, senderIdentity)
        end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, status == "OUTDATED" and "Update Required" or "Disabled") end
        return true
    end

    local revision = tonumber(revisionText) or 0
    local itemCount = tonumber(countText) or 0
    local scanTime = tonumber(scanTimeText) or 0
    if revision < 0 or itemCount < 0 or scanTime < 0 then
        if MarketSync.ForgetSyncPeerBaseline then
            MarketSync.ForgetSyncPeerBaseline(scope, senderIdentity)
        end
        return true
    end
    revision = math.floor(revision)
    itemCount = math.floor(itemCount)
    scanTime = math.floor(scanTime)
    if MarketSync.NoteSyncPeerBaseline then
        MarketSync.NoteSyncPeerBaseline(scope, senderIdentity, revision)
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "Incoming |cff00ffff[%sADV]|r from %s (revision %d, %d records, TSF %d, v%s/p%d).",
            scope == "N" and "N" or "", tostring(senderName), revision, itemCount, scanTime,
            tostring(addonVersion), protocol))
    end
    if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Ready") end

    local isFresher
    if scope == "N" then
        isFresher = ComputeNeutralFreshness(revision, itemCount, scanTime)
    else
        isFresher = ComputeFreshness(revision, itemCount, scanTime)
    end
    if isFresher and MarketSync.CanParticipateInData(scope) then
        local advertisement = {
            sender = senderName,
            senderIdentity = senderIdentity,
            realm = realm,
            scanDay = revision,
            itemCount = itemCount,
            scanTime = scanTime,
            version = addonVersion,
            protocol = protocol,
        }
        if scope == "N" then QueueDeferredNeutralADV(advertisement) else QueueDeferredADV(advertisement) end
        ScheduleDeferredADVProcessing()
    end
    return true
end

local function HandleProtocol2Message(msgType, p1, p2, p3, p4, p5, p6, p7, p8,
                                      senderName, senderIdentity, channel, prefix)
    if msgType == "ADV" then
        if prefix ~= PREFIX or channel ~= "GUILD" then return true end
        return HandleAdvertisementV2("M", p1, p2, p3, p4, p5, p6, p7, senderName, senderIdentity)
    elseif msgType == "NADV" then
        if prefix ~= PREFIX or channel ~= "GUILD" then return true end
        return HandleAdvertisementV2("N", p1, p2, p3, p4, p5, p6, p7, senderName, senderIdentity)
    end

    if msgType == "PULL" or msgType == "NPULL" then
        local scope = msgType == "NPULL" and "N" or "M"
        local realm = p1
        local sourceIdentity = p2
        local advertisedRevision = tonumber(p3) or 0
        local advertisedScanTime = tonumber(p4) or 0
        local sinceRevision = tonumber(p5) or 0
        local protocol = tonumber(p6) or 0
        local addonVersion = p7
        if prefix ~= PREFIX or channel ~= "GUILD" then return true end
        if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
        if realm ~= MarketSync.myRealm then return true end
        if not MarketSync.IsPeerDataCompatible(addonVersion, protocol) then
            MarketSync.NotePeerSyncVersion(addonVersion, protocol, senderName)
            return true
        end
        if MarketSync.IsBlocked and MarketSync.IsBlocked(senderName) then return true end

        -- Register every near-simultaneous request in the same bounded window.
        -- Sync.lua ranks the candidates deterministically and only the winning
        -- exact source starts after contention closes.
        MarketSync.ObserveGuildPull(scope, sourceIdentity, advertisedRevision, senderIdentity,
            sinceRevision, advertisedScanTime)
        return true
    end

    if msgType == "HOLD" then
        if prefix ~= PREFIX or channel ~= "GUILD" then return true end
        local sessionId, scope = p1, p2
        if scope ~= "M" and scope ~= "N" then return true end
        if sessionId and sessionId ~= "" then
            MarketSync.TouchInboundTransfer(scope, sessionId, senderIdentity)
        end
        return true
    end

    local dataPrefix = (MarketSync.DATA_PREFIXES and MarketSync.DATA_PREFIXES[1]) or PREFIX
    if msgType == "BEGIN" then
        if prefix ~= dataPrefix or channel ~= "GUILD" then return true end
        local sessionId, scope, realm = p1, p2, p3
        local baseRevision = DecodeWireBase36(p4)
        local revision = DecodeWireBase36(p5)
        local scanTime = DecodeWireBase36(p6)
        local protocol = tonumber(p7) or 0
        local addonVersion = p8
        if scope ~= "M" and scope ~= "N" then return true end
        if not baseRevision or not revision or not scanTime or baseRevision > revision then return true end
        if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
        if realm ~= MarketSync.myRealm then return true end
        if not MarketSync.IsPeerDataCompatible(addonVersion, protocol) then
            MarketSync.NotePeerSyncVersion(addonVersion, protocol, senderName)
            return true
        end
        if not MarketSync.AcceptInboundTransfer(scope, sessionId, senderIdentity, revision) then return true end

        local existing = rxSessions[scope]
        if existing and existing.id == sessionId then
            if existing.baseRevision ~= baseRevision or existing.revision ~= revision
                or existing.scanTime ~= scanTime
                or string.lower(tostring(existing.sender)) ~= string.lower(tostring(senderIdentity)) then
                existing.invalidReason = "BEGIN metadata changed during session"
                existing.applyEligible = false
                existing.chunks = {}
                existing.chunkCount = 0
                MarketSync.RxCount = 0
            end
            return true
        end

        local targetFresher, localRevision, localScanTime = IsTargetFresher(scope, revision, scanTime)
        local canParticipate = MarketSync.CanParticipateInData(scope)
            and (not MarketSync.CanSync or MarketSync.CanSync())
            and (not MarketSync.IsBlocked or not MarketSync.IsBlocked(senderName))
        local baselineCovered = localRevision >= baseRevision
        local applyEligible = canParticipate and baselineCovered and targetFresher
        local skipReason
        if not canParticipate then
            skipReason = "flow disabled, blocked, or Smart Rules active"
        elseif not baselineCovered then
            skipReason = string.format("local revision %d is behind transfer base %d", localRevision, baseRevision)
        elseif not targetFresher then
            skipReason = string.format("local revision/time %d/%d is already as fresh as target %d/%d",
                localRevision, localScanTime, revision, scanTime)
        end

        if existing and existing.observationStarted and MarketSync.ObservationAPI then
            MarketSync.ObservationAPI.v1.Emit({ event = "cancel",
                scanId = "sync-" .. tostring(existing.id), source = "synced",
                scope = scope == "N" and "neutral" or "main", reason = "replaced by new transfer" })
        end
        rxSessions[scope] = {
            id = sessionId,
            scope = scope,
            sender = senderIdentity,
            senderName = senderName,
            baseRevision = baseRevision,
            revision = revision,
            scanTime = scanTime,
            applyEligible = applyEligible,
            observationStarted = applyEligible,
            skipReason = skipReason,
            chunks = {},
            chunkCount = 0,
        }
        if applyEligible and MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1.HasListeners() then
            MarketSync.ObservationAPI.v1.Emit({ event = "start",
                scanId = "sync-" .. tostring(sessionId), source = "synced",
                scope = scope == "N" and "neutral" or "main" })
        end
        MarketSync.RxCount = 0
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), applyEligible
                and (scope == "N" and "Receiving Neutral" or "Receiving") or "Observing Sync")
            MarketSync.UpdateSwarmUI(senderName, scope == "N" and "Sending Neutral" or "Sending")
        end
        return true
    elseif msgType == "DATA" then
        if prefix ~= dataPrefix or channel ~= "GUILD" then return true end
        local sessionId, sequenceText, scope, payload = p1, p2, p3, p4
        local sequence = DecodeWireBase36(sequenceText)
        if scope ~= "M" and scope ~= "N" then return true end
        if not MarketSync.TouchInboundTransfer(scope, sessionId, senderIdentity) then return true end
        local session = rxSessions[scope]
        if session and session.id == sessionId
            and string.lower(tostring(session.sender)) == string.lower(tostring(senderIdentity)) then
            if not sequence or sequence <= 0 or sequence > 100000 or not payload or payload == "" then
                session.invalidReason = "malformed DATA frame"
                session.applyEligible = false
                session.chunks = {}
                session.chunkCount = 0
                MarketSync.RxCount = 0
            elseif session.applyEligible and not session.invalidReason then
                local priorPayload = session.chunks[sequence]
                if priorPayload and priorPayload ~= payload then
                    session.invalidReason = "conflicting duplicate DATA sequence " .. tostring(sequence)
                    session.applyEligible = false
                    session.chunks = {}
                    session.chunkCount = 0
                    MarketSync.RxCount = 0
                elseif not priorPayload then
                    session.chunks[sequence] = payload
                    session.chunkCount = session.chunkCount + 1
                    MarketSync.RxCount = session.chunkCount
                end
            end
        end
        return true
    elseif msgType == "END" and (p2 == "M" or p2 == "N") then
        if prefix ~= dataPrefix or channel ~= "GUILD" then return true end
        local sessionId, scope = p1, p2
        local finalSequence = DecodeWireBase36(p3)
        local expectedRecords = DecodeWireBase36(p4)
        local baseRevision = DecodeWireBase36(p5)
        local revision = DecodeWireBase36(p6)
        local scanTime = DecodeWireBase36(p7)
        if not MarketSync.TouchInboundTransfer(scope, sessionId, senderIdentity) then return true end

        local session = rxSessions[scope]
        local complete, skipped = false, false
        local result = "receiver disabled or BEGIN was missed"
        if session and session.id == sessionId
            and string.lower(tostring(session.sender)) == string.lower(tostring(senderIdentity)) then
            if not finalSequence or not expectedRecords or not baseRevision or not revision or not scanTime
                or finalSequence > 100000 or expectedRecords > 1000000 then
                session.invalidReason = "malformed END frame"
            elseif baseRevision ~= session.baseRevision or revision ~= session.revision
                or scanTime ~= session.scanTime then
                session.invalidReason = "END metadata did not match BEGIN"
            end

            if not session.invalidReason and session.applyEligible then
                local stillFresher, localRevision, localScanTime = IsTargetFresher(scope, revision, scanTime)
                if localRevision < baseRevision then
                    session.applyEligible = false
                    session.skipReason = string.format("local revision %d fell behind transfer base %d",
                        localRevision, baseRevision)
                elseif not stillFresher then
                    session.applyEligible = false
                    session.skipReason = string.format("local revision/time %d/%d became as fresh as target %d/%d",
                        localRevision, localScanTime, revision, scanTime)
                end
            end

            if session.invalidReason then
                result = session.invalidReason
            elseif not session.applyEligible then
                skipped = true
                result = session.skipReason or "listener was not eligible for this delta"
            else
                complete, result = CommitStagedSession(session, finalSequence, expectedRecords)
            end
        end
        if session then
            if not complete and session.observationStarted and MarketSync.ObservationAPI then
                MarketSync.ObservationAPI.v1.Emit({ event = "cancel",
                    scanId = "sync-" .. tostring(session.id), source = "synced",
                    scope = scope == "N" and "neutral" or "main", reason = tostring(result) })
            end
            if complete then
                rejectedSessions[scope] = nil
            elseif not skipped then
                rejectedSessions[scope] = {
                    revision = tonumber(session.revision) or 0,
                    scanTime = tonumber(session.scanTime) or 0,
                }
            end
        end
        rxSessions[scope] = nil
        if MarketSync.SetPullRequestPending then MarketSync.SetPullRequestPending(false) end

        if MarketSync.LogNetworkEvent and session then
            if complete then
                MarketSync.LogNetworkEvent(string.format(
                    "|cff00ff00[Rx Complete]|r Verified session %s: %d records in %d ordered chunks; base %d advanced to %d.",
                    sessionId, tonumber(result) or 0, finalSequence, baseRevision, revision))
            elseif skipped then
                MarketSync.LogNetworkEvent(string.format(
                    "|cffaaaaaa[Rx Observed]|r Session %s finished without local apply (%s).",
                    sessionId, tostring(result)))
            else
                MarketSync.LogNetworkEvent(string.format(
                    "|cffff8800[Rx Rejected]|r Session %s discarded (%s). No freshness update or automatic retry.",
                    sessionId, tostring(result)))
            end
        end
        MarketSync.RxCount = 0
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            MarketSync.UpdateSwarmUI(senderName, "Idle")
        end
        MarketSync.FinishGuildTransfer(scope, sessionId,
            complete and "receiver complete" or (skipped and "receiver observed" or "receiver rejected"))
        return true
    elseif msgType == "ABORT" then
        if prefix ~= dataPrefix or channel ~= "GUILD" then return true end
        local sessionId, scope = p1, p2
        if (scope == "M" or scope == "N") and MarketSync.TouchInboundTransfer(scope, sessionId, senderIdentity) then
            MarketSync.DiscardInboundSyncSession(scope, sessionId, "sender abort")
            MarketSync.FinishGuildTransfer(scope, sessionId, "sender abort")
        end
        return true
    end

    -- Revision-1 market-data and claimant messages are deliberately fail-closed.
    if msgType == "BRES" or msgType == "NBRES" or msgType == "NEND"
        or msgType == "RES" or msgType == "REQ" or msgType == "ACCEPT"
        or msgType == "NACCEPT" or msgType == "ACK" then
        return true
    end
    if msgType == "END" then return true end -- legacy END lacks scope
    return false
end

frame:SetScript("OnEvent", function(self, event, ...)
    -- ========================================
    -- ADDON MESSAGES (Sync Protocol)
    -- ========================================
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        
        -- Build a lookup table for data prefixes (fast check)
        local isDataPrefix = false
        for _, dp in ipairs(MarketSync.DATA_PREFIXES or {}) do
            if prefix == dp then isDataPrefix = true; break end
        end
        
        -- Accept messages from main prefix OR any data prefix
        if prefix ~= PREFIX and not isDataPrefix then return end

        -- Strip realm suffix: sender comes as "Name-Realm" but UnitName returns just "Name"
        local senderName = sender and sender:match("^([^%-]+)") or sender
        if senderName == UnitName("player") then return end

        local senderIdentity = sender or senderName or "Unknown"
        local senderKey = NormalizePriceCheckSender(senderIdentity)
        local msgType, p1, p2, p3, p4, p5, p6, p7, p8 = strsplit(";", msg)

        -- Fast Guild Check: Ignore sync events if we aren't actually in a guild.
        -- CLAIM is allowed outside guild so non-guild channel price checks can coordinate.
        if not IsInGuild() and msgType ~= "CLAIM" then
            if MarketSync.UpdateNetworkUI then MarketSync.UpdateNetworkUI(0, 0, "|cffaaaaaaNetwork: Disabled (No Guild)|r") end
            return
        end

        -- Extract sender's realm from "Name-Realm" format
        local senderRealm = sender and sender:match("%-(.+)$")

        -- Protocol 2 owns all market-data/control messages and returns before
        -- the revision-1 compatibility code below.  CLAIM remains available
        -- for the unrelated chat price-check election.
        if HandleProtocol2Message(msgType, p1, p2, p3, p4, p5, p6, p7, p8,
            senderName, senderIdentity, channel, prefix) then
            return
        end

        local isNeutralMsg = (msgType == "NADV" or msgType == "NPULL" or msgType == "NACCEPT" or msgType == "NBRES" or msgType == "NEND")

        -- Neutral transport is guild-only by design.
        if isNeutralMsg and channel ~= "GUILD" then
            return
        end

        -- Smart Rules hard gate: while sync is suspended (combat/instance), ignore
        -- active sync protocol messages so no heavy background processing occurs.
        if SMART_RULES_SYNC_MSG[msgType] and MarketSync.CanSync and not MarketSync.CanSync() then
            if msgType == "BRES" or msgType == "RES" or msgType == "END" or msgType == "NBRES" or msgType == "NEND" then
                if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
                MarketSync.RxCount = 0
                sessionRxTotal = 0
                scanCacheInvalidatedThisSession = false
                if MarketSync.SetPullRequestPending then
                    MarketSync.SetPullRequestPending(false)
                end
            end
            Debug("Smart Rules blocked incoming " .. tostring(msgType))
            return
        end

        if msgType == "ADV" then
            local advRealm = p1
            local advBucket = tonumber(p2) or 0
            local advItemCount = tonumber(p3) or 0
            local advVersion = p4 or "0.4.0-beta"
            local rawP5 = p5 or "0"
            local isDisabled = (rawP5 == "DISABLED")
            local advScanTime = isDisabled and 0 or (tonumber(rawP5) or 0)
            
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if advRealm ~= MarketSync.myRealm then
                Debug("Ignoring ADV from " .. senderName .. " (realm " .. tostring(advRealm) .. " != " .. MarketSync.myRealm .. ")")
                return
            end
            
            -- Version Compatibility Check
            local localVersion = MarketSync.GetAddOnMetadata("MarketSync", "Version") or "0.0.0"
            local cmp = CompareVersions(advVersion, localVersion)
            if cmp > 0 then
                -- They are newer. We must disable our sync and warn the user to update.
                if MarketSyncDB and MarketSyncDB.PassiveSync then
                    MarketSyncDB.PassiveSync = false
                    print(string.format("|cFFFF0000[MarketSync]|r Sync Disabled! You are running an outdated version (v%s). %s is running v%s. Please update your addon.", localVersion, senderName, advVersion))
                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Outdated addon version! Disabled sync to prevent data corruption. (New version: v%s)", advVersion))
                    end
                end
                return
            elseif cmp < 0 then
                -- They are older. We just ignore their payload, but we explicitly list them in the Swarm Queue
                -- so the user can see who is running around with an outdated addon version.
                if MarketSync.UpdateSwarmUI then
                    MarketSync.UpdateSwarmUI(senderName, "Version Mismatch (v" .. advVersion .. ")")
                end
                
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("Ignoring ADV from %s (Outdated version: v%s)", senderName, advVersion))
                end
                return
            end

            if isDisabled then
                Debug("Received DISABLED ADV from " .. senderName)
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Disabled") end
                return
            end

            Debug("Received ADV from " .. senderName .. ": bucket=" .. advBucket .. " items=" .. advItemCount)
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("Incoming |cff00ffff[ADV]|r from |cffffff00%s|r (Bucket %d, %d items, TSF: %s, v%s)", senderName, advBucket, advItemCount, advScanTime > 0 and tostring(advScanTime) or "None", advVersion))
            end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Ready") end
            local isFresher, ourBucket, ourItemCount, ourScanTime = ComputeFreshness(advBucket, advItemCount, advScanTime)
            
            if isFresher then
                -- Don't initiate a new PULL while any sync blast is active.
                if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
                    QueueDeferredADV({
                        sender = senderName,
                        realm = advRealm,
                        scanDay = advBucket,
                        itemCount = advItemCount,
                        scanTime = advScanTime,
                        version = advVersion,
                    })
                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Deferred ADV]|r Busy sync session; queued %s (Bucket %d, TSF %d) for next pull window.", senderName, advBucket, advScanTime))
                    end
                    return
                end
                
                Debug(string.format("Their data is fresher (Bucket %d vs %d, Time %d vs %d, Items %d vs %d), sending PULL", advBucket, ourBucket, advScanTime, ourScanTime, advItemCount, ourItemCount))
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent("Data is fresher. Sending |cffff8800[PULL]|r request to Guild...")
                end
                
                -- We are going to receive data
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving") end
                
                -- Begin guild sync session before pulling
                if MarketSync.BeginGuildSync then
                    MarketSync.BeginGuildSync()
                end
                MarketSync.SendPullRequest(ourBucket)
            end

        elseif msgType == "NADV" then
            local advRealm = p1
            local advScanDay = tonumber(p2) or 0
            local advItemCount = tonumber(p3) or 0
            local advVersion = p4 or "0.4.0-beta"
            local rawP5 = p5 or "0"
            local isDisabled = (rawP5 == "DISABLED")
            local advScanTime = isDisabled and 0 or (tonumber(rawP5) or 0)

            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if advRealm ~= MarketSync.myRealm then return end

            local localVersion = MarketSync.GetAddOnMetadata("MarketSync", "Version") or "0.0.0"
            local cmp = CompareVersions(advVersion, localVersion)
            if cmp > 0 then
                if MarketSyncDB and MarketSyncDB.PassiveSync then
                    MarketSyncDB.PassiveSync = false
                    print(string.format("|cFFFF0000[MarketSync]|r Sync Disabled! You are running an outdated version (v%s). %s is running v%s. Please update your addon.", localVersion, senderName, advVersion))
                end
                return
            elseif cmp < 0 then
                if MarketSync.UpdateSwarmUI then
                    MarketSync.UpdateSwarmUI(senderName, "Version Mismatch (Neutral Disabled)")
                end
                return
            end

            if isDisabled then
                Debug("Received DISABLED NADV from " .. senderName)
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Disabled") end
                return
            end

            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("Incoming |cff00ccff[NADV]|r from |cffffff00%s|r (Day %d, %d items, TSF: %s, v%s)", senderName, advScanDay, advItemCount, advScanTime > 0 and tostring(advScanTime) or "None", advVersion))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(senderName, "Ready")
            end

            local isFresher, ourDay, ourItemCount, ourScanTime = ComputeNeutralFreshness(advScanDay, advItemCount, advScanTime)
            if isFresher then
                if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
                    QueueDeferredNeutralADV({
                        sender = senderName,
                        realm = advRealm,
                        scanDay = advScanDay,
                        itemCount = advItemCount,
                        scanTime = advScanTime,
                        version = advVersion,
                    })
                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Deferred NADV]|r Busy sync session; queued %s (Day %d, TSF %d).", senderName, advScanDay, advScanTime))
                    end
                    return
                end

                Debug(string.format("Their neutral data is fresher (Day %d vs %d, Time %d vs %d, Items %d vs %d), sending NPULL",
                    advScanDay, ourDay, advScanTime, ourScanTime, advItemCount, ourItemCount))
                if MarketSync.UpdateSwarmUI then
                    MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving Neutral")
                end
                if MarketSync.BeginNeutralSync then
                    MarketSync.BeginNeutralSync()
                end
                if MarketSync.SendNeutralPullRequest then
                    MarketSync.SendNeutralPullRequest(ourDay)
                end
            end

        elseif msgType == "PULL" then
            local pullRealm = p1
            local sinceBucket = tonumber(p2) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if pullRealm ~= MarketSync.myRealm then return end
            if not MarketSyncDB or not MarketSyncDB.PassiveSync then return end
            
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("Received |cffff8800[PULL]|r from |cffffff00%s|r (Since Bucket %d). Coordinating swarm...", senderName, sinceBucket))
            end
            
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Receiving") end
            
            if MarketSync.SchedulePullResponse then
                MarketSync.SchedulePullResponse(sinceBucket, senderName)
            end

        elseif msgType == "NPULL" then
            local pullRealm = p1
            local sinceDay = tonumber(p2) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if pullRealm ~= MarketSync.myRealm then return end
            if not MarketSyncDB or not MarketSyncDB.PassiveSync then return end

            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("Received |cff00ccff[NPULL]|r from |cffffff00%s|r (Since Day %d). Coordinating neutral swarm...", senderName, sinceDay))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(senderName, "Receiving Neutral")
            end
            if MarketSync.ScheduleNeutralPullResponse then
                MarketSync.ScheduleNeutralPullResponse(sinceDay, senderName)
            end

        elseif msgType == "ACCEPT" then
            local acceptRealm = p1
            local sinceDay = tonumber(p2) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if acceptRealm ~= MarketSync.myRealm then return end
            
            if MarketSync.RegisterPullAccept then
                MarketSync.RegisterPullAccept(sinceDay, senderName)
            end

        elseif msgType == "NACCEPT" then
            local acceptRealm = p1
            local sinceDay = tonumber(p2) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if acceptRealm ~= MarketSync.myRealm then return end
            if MarketSync.RegisterNeutralPullAccept then
                MarketSync.RegisterNeutralPullAccept(sinceDay, senderName)
            end

        elseif msgType == "REQ" then
            local link = p1
            if not link then return end
            if senderRealm and MarketSync.myRealm and senderRealm ~= MarketSync.myRealm then return end
            local price = MarketSync.GetAuctionPrice(link)
            local age = MarketSync.GetAuctionAge(link)
            if price and age then
                local scanDay = MarketSync.GetCurrentScanDay() - math.floor(age)
                MarketSync.SendSyncResponse(link, price, scanDay, 0, "GUILD")
            end

        elseif msgType == "BRES" or msgType == "NBRES" then
            local payloadStr = p1
            local legacyDay = tonumber(p2) -- v1 format had day as second semicolon field
            local isNeutralPayload = (msgType == "NBRES")
            if not payloadStr or payloadStr == "" then return end
            if senderRealm and MarketSync.myRealm and senderRealm ~= MarketSync.myRealm then
                Debug("Ignoring BRES from cross-realm sender: " .. tostring(sender))
                return
            end
            if MarketSync.SetPullRequestPending then
                MarketSync.SetPullRequestPending(false)
            end
            
            local FromBase36 = MarketSync.FromBase36
            local items = {strsplit(",", payloadStr)}
            for _, itemData in ipairs(items) do
                local dbKey, priceStr, qtyStr, dayStr
                if itemData:find("_") then
                    if isNeutralPayload then
                        local dbKey, priceStr, qtyStr, dayStr = strsplit("_", itemData)
                        local price = FromBase36(priceStr)
                        if price == 0 and priceStr ~= "0" then price = tonumber(priceStr) end
                        local quantity = FromBase36(qtyStr)
                        if quantity == 0 and qtyStr and qtyStr ~= "0" then quantity = tonumber(qtyStr) or 0 end
                        local day = FromBase36(dayStr)
                        if day == 0 then day = tonumber(dayStr) or legacyDay end
                        
                        if price and day and day > 0 and MarketSync.UpdateLocalNeutralDBByKey then
                            MarketSync.UpdateLocalNeutralDBByKey(dbKey, price, day, quantity, senderName)
                        end
                    else
                        -- Timeseries String Payload
                        local dbKey, dayB36, safeHistStr = strsplit("_", itemData)
                        local day = FromBase36(dayB36)
                        if day == 0 then day = tonumber(dayB36) end
                        
                        if day and day > 0 and safeHistStr then
                             local histStr = string.gsub(safeHistStr, "%.", ",")
                             MarketSync.UpdateLocalDBByKey(dbKey, day, histStr, senderName)
                        end
                    end
                else
                    -- Legacy v1 handling (Only applicable for extremely old clients, gracefully handle)
                    local dbKey, priceStr, qtyStr, dayStr = strsplit(":", itemData)
                    local price = FromBase36(priceStr)
                    if price == 0 and priceStr ~= "0" then price = tonumber(priceStr) end
                    local quantity = FromBase36(qtyStr)
                    if quantity == 0 and qtyStr and qtyStr ~= "0" then quantity = tonumber(qtyStr) or 0 end
                    local day = FromBase36(dayStr)
                    if day == 0 then day = tonumber(dayStr) or legacyDay end
                    
                    if price and day and day > 0 then
                        local itemID = FromBase36(dbKey)
                        if itemID == 0 then itemID = tonumber(dbKey) end
                        if itemID and itemID > 0 then
                            local link = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0"
                            if isNeutralPayload and MarketSync.UpdateLocalNeutralDB then
                                MarketSync.UpdateLocalNeutralDB(link, price, day, quantity, senderName)
                            else
                                -- Fallback for unsupported legacy sync attempts
                                if MarketSync.UpdateLocalDB then
                                    MarketSync.UpdateLocalDB(link, price, day, quantity, senderName)
                                end
                            end
                        end
                    end
                end
            end
            MarketSync.RxCount = (MarketSync.RxCount or 0) + #items
            sessionRxTotal = sessionRxTotal + #items
            
            -- Eagerly invalidate CachedScanStats on first data chunk of a sync session.
            -- This prevents stale cached counts from being served to ADV broadcasts
            -- while sync data is actively modifying the Auctionator database.
            if not scanCacheInvalidatedThisSession then
                scanCacheInvalidatedThisSession = true
                if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
                Debug("CachedScanStats invalidated on first BRES chunk (session Rx: " .. sessionRxTotal .. ")")
            end
            
            -- Receiver checkpoint logging
            if MarketSync.LogNetworkEvent then
                local rxTotal = MarketSync.RxCount or 0
                -- Log every roughly 100 received items by checking if this chunk crosses a 100-boundary
                if math.floor(rxTotal / 100) > math.floor((rxTotal - #items) / 100) then
                    MarketSync.LogNetworkEvent(string.format("|cff00ccff[Rx Checkpoint]|r Received %d total items from %s (%d in this chunk, prefix: %s)", rxTotal, senderName, #items, prefix))
                end
            end
            
            if MarketSync.UpdateSwarmUI then 
                MarketSync.UpdateSwarmUI(UnitName("player"), isNeutralPayload and "Receiving Neutral" or "Receiving")
                MarketSync.UpdateSwarmUI(senderName, isNeutralPayload and "Sending Neutral" or "Sending")
            end
            
            -- Increased idle timeout from 5s to 8s to accommodate the slower 0.3s send rate.
            -- This prevents premature commits while the sender is still transmitting between yields.
            if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
            guildSyncCommitTimer = C_Timer.NewTimer(8, function()
                guildSyncCommitTimer = nil
                local rxCount = MarketSync.RxCount or 0
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Rx Timeout]|r 8s idle — partial sync committed. Received %d items (transfer may be incomplete).", rxCount))
                end
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
                if isNeutralPayload then
                    if MarketSync.CommitNeutralSync then
                        MarketSync.CommitNeutralSync()
                    end
                else
                    if MarketSync.CommitGuildSync then
                        MarketSync.CommitGuildSync()
                    end
                end
                -- Invalidate scan cache but do NOT update PersonalScanTime
                -- A timeout means the transfer was incomplete, so the receiver should
                -- remain eligible for a re-PULL on the next ADV cycle.
                if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
                MarketSync.RxCount = 0
                -- Do NOT reset sessionRxTotal here — END handler needs it to validate completeness
                if MarketSync.SetPullRequestPending then
                    MarketSync.SetPullRequestPending(false)
                end
                ScheduleDeferredADVProcessing()
            end)

        elseif msgType == "END" then
            if MarketSync.SetPullRequestPending then
                MarketSync.SetPullRequestPending(false)
            end
            local itemsSent = tonumber(p1) or 0
            local messagesSent = tonumber(p2) or 0
            local senderScanTime = tonumber(p3) or 0  -- sender's original PersonalScanTime
            -- Use the session-level counter for completeness validation.
            -- MarketSync.RxCount may have been reset by the 8s idle timeout,
            -- but sessionRxTotal survives that reset.
            local rxCount = sessionRxTotal
            
            -- Immediate commit
            if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Idle") end
            if MarketSync.CommitGuildSync then
                MarketSync.CommitGuildSync()
            end
            
            -- Validate: only stamp our freshness if we received the full payload
            local isComplete = (rxCount >= itemsSent) and (itemsSent > 0)
            
            if isComplete then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cff00ff00[Rx Complete]|r Full sync verified! Received %d / %d items. Scan freshness updated (TSF: %d).", rxCount, itemsSent, senderScanTime))
                end
                -- Full transfer confirmed — stamp the SENDER's scan time (not ours!)
                -- This ensures both clients share the same TSF and won't ping-pong sync.
                -- NOTE: We do NOT call SnapshotPersonalScan() here! The Personal Scan
                -- snapshot is sacred — it only updates when the player visits the AH.
                -- This timestamp is purely for swarm freshness comparison (ADV TSF).
                if MarketSyncDB then
                    local realmDB = MarketSync.GetRealmDB()
                    realmDB.CachedScanStats = nil
                    -- Only stamp SwarmTSF (protocol freshness), NOT PersonalScanTime.
                    -- PersonalScanTime is sacred — it only updates when the player
                    -- actually visits the AH. This prevents guild syncs from appearing
                    -- as false personal scans in the UI.
                    realmDB.SwarmTSF = (senderScanTime > 0) and senderScanTime or time()
                end
                -- Send ACK back to guild so the sender sees confirmation
                -- Add a randomized jitter delay (1-20 seconds) to prevent guild channel flood 
                -- if hundreds of members finish downloading at the exact same moment.
                if IsInGuild() then
                    local myName = UnitName("player") or "Unknown"
                    local jitter = math.random(1, 20)
                    C_Timer.After(jitter, function()
                        if IsInGuild() then
                            C_ChatInfo.SendAddonMessage("MSync", string.format("ACK;%d;%s", rxCount, myName), "GUILD")
                        end
                    end)
                end
            else
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Rx Partial]|r Received %d / %d items (%.0f%%). Will re-PULL on next ADV cycle.", rxCount, itemsSent, (itemsSent > 0 and (rxCount / itemsSent * 100) or 0)))
                end
                -- Partial transfer — do NOT update PersonalScanTime so we stay eligible for re-PULL
                if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
            end
            
            -- Reset session Rx counters for a clean slate
            MarketSync.RxCount = 0
            sessionRxTotal = 0
            scanCacheInvalidatedThisSession = false
            ScheduleDeferredADVProcessing()

        elseif msgType == "NEND" then
            if MarketSync.SetPullRequestPending then
                MarketSync.SetPullRequestPending(false)
            end
            local itemsSent = tonumber(p1) or 0
            local messagesSent = tonumber(p2) or 0
            local senderScanTime = tonumber(p3) or 0
            local rxCount = sessionRxTotal

            if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Idle") end
            if MarketSync.CommitNeutralSync then
                MarketSync.CommitNeutralSync()
            end

            local isComplete = (rxCount >= itemsSent) and (itemsSent > 0)
            if isComplete then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral Rx Complete]|r Received %d / %d neutral items.", rxCount, itemsSent))
                end
                local realmDB = MarketSync.GetRealmDB()
                realmDB.NeutralSwarmTSF = (senderScanTime > 0) and senderScanTime or time()
                realmDB.NeutralScanTime = realmDB.NeutralSwarmTSF
            else
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Neutral Rx Partial]|r Received %d / %d neutral items.", rxCount, itemsSent))
                end
            end

            MarketSync.RxCount = 0
            sessionRxTotal = 0
            scanCacheInvalidatedThisSession = false
            ScheduleDeferredADVProcessing()

        elseif msgType == "RES" then
            local link = p1
            local price = tonumber(p2)
            local day = tonumber(p3)
            local quantity = tonumber(p4) or 0
            if senderRealm and MarketSync.myRealm and senderRealm ~= MarketSync.myRealm then
                Debug("Ignoring RES from cross-realm sender: " .. tostring(sender))
                return
            end
            if link and price and day then
                if MarketSync.SetPullRequestPending then
                    MarketSync.SetPullRequestPending(false)
                end
                MarketSync.RxCount = (MarketSync.RxCount or 0) + 1
                MarketSync.UpdateLocalDB(link, price, day, quantity, senderName)
                if MarketSync.UpdateSwarmUI then 
                    MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving")
                    MarketSync.UpdateSwarmUI(senderName, "Sending")
                end

                -- Reset the idle commit timer on every RES received
                if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
                guildSyncCommitTimer = C_Timer.NewTimer(GUILD_SYNC_IDLE_TIMEOUT, function()
                    guildSyncCommitTimer = nil
                    if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
                    if MarketSync.CommitGuildSync then
                        MarketSync.CommitGuildSync()
                    end
                    -- Invalidate scan cache because we just received new items!
                    if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
                    MarketSync.RxCount = 0
                    sessionRxTotal = 0
                    scanCacheInvalidatedThisSession = false
                    if MarketSync.SetPullRequestPending then
                        MarketSync.SetPullRequestPending(false)
                    end
                    ScheduleDeferredADVProcessing()
                end)
            end
        elseif msgType == "ACK" then
            local ackCount = tonumber(p1) or 0
            local ackUser = p2 or senderName
            if senderName ~= UnitName("player") then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cff00ff00[ACK]|r %s confirmed download complete (%d items received).", ackUser, ackCount))
                end
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Idle") end
            end

        elseif msgType == "ERR" then
            local targetName = p1
            local crashKey = p2
            if targetName == UnitName("player") then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Sync failed. %s's database contains a corrupt entry at dbKey: %s", senderName, tostring(crashKey)))
                end
                if MarketSync.UpdateSwarmUI then
                    MarketSync.UpdateSwarmUI(senderName, "Error")
                    MarketSync.UpdateSwarmUI(UnitName("player"), nil)
                end
                if guildSyncCommitTimer then
                    guildSyncCommitTimer:Cancel()
                    guildSyncCommitTimer = nil
                end
                if MarketSync.SetPullRequestPending then
                    MarketSync.SetPullRequestPending(false)
                end
            end

        elseif msgType == "CLAIM" then
            local claimedItemID = tonumber(p1)
            if not claimedItemID then return end
            
            local claimedSenderKey = NormalizePriceCheckSender(p2)
            local claimedQueryKey = claimedSenderKey and BuildPriceCheckQueryKey(claimedSenderKey, claimedItemID) or nil
            local claimBucketKey = claimedQueryKey or tostring(claimedItemID)

            -- Track all competing claimants for this query so we can tiebreak deterministically.
            -- Legacy CLAIM packets only identify the itemID, so we attach them to every active
            -- bucket for that item to preserve old-client suppression as well as possible.
            if not MarketSync.claimContestants then MarketSync.claimContestants = {} end
            if claimedQueryKey then
                if not MarketSync.claimContestants[claimBucketKey] then MarketSync.claimContestants[claimBucketKey] = {} end
                MarketSync.claimContestants[claimBucketKey][senderIdentity] = true
            else
                local attached = false
                for queryKey, contestants in pairs(MarketSync.claimContestants) do
                    if ExtractPriceCheckItemID(queryKey) == claimedItemID then
                        contestants[senderIdentity] = true
                        attached = true
                    end
                end
                if not attached then
                    if not MarketSync.claimContestants[claimBucketKey] then MarketSync.claimContestants[claimBucketKey] = {} end
                    MarketSync.claimContestants[claimBucketKey][senderIdentity] = true
                end
            end
            
            -- If we haven't claimed this item ourselves yet, cancel our pending lottery immediately.
            -- (Their timer fired before ours — they're ahead of us in the lottery.)
            local canceled = false
            if claimedQueryKey then
                canceled = CancelPendingPriceCheck(claimedQueryKey, "claimed by " .. tostring(senderName))
            else
                canceled = CancelPendingQueriesByItem(claimedItemID, "legacy claim by " .. tostring(senderName)) > 0
            end
            if canceled then
                Debug("Price check for " .. claimedItemID .. " claimed by " .. senderName .. ", cancelling our pending lottery")
            end

            -- Housekeeping: evict stale claimContestants entries for items no longer in play.
            -- This prevents the table from growing indefinitely over a long session.
            for queryKey, _ in pairs(MarketSync.claimContestants) do
                local keyItemID = claimedQueryKey and nil or ExtractPriceCheckItemID(queryKey)
                if queryKey ~= claimBucketKey and keyItemID ~= claimedItemID then
                    MarketSync.claimContestants[queryKey] = nil
                end
            end
        end
        return
    end

    -- ========================================
    -- CHAT QUERIES ("? [Item Link]")
    -- ========================================
    local msg, sender, _, _, _, _, _, channelID = ...

    -- Strip sender name for comparison (sender may include realm suffix)
    local querySender = sender and sender:match("^([^%-]+)") or sender
    local querySenderKey = NormalizePriceCheckSender(sender)
    local localIdentity = GetLocalPriceCheckIdentity()

    -- 1. Anti-Flood: Monitor for existing replies from other clients
    -- If we see a price reply message from someone else, cancel our pending reply for that item.
    -- Match both raw escape-coded links and rendered item links to be safe across WoW versions.
    local replyLink = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r):") or msg:match("(%[.-%]):.*%d+[gsc]")
    if replyLink and querySender ~= UnitName("player") then
        local itemID = tonumber(replyLink:match("item:(%d+)")) or tonumber(replyLink:match("%[(.-)%]") and select(1, C_Item.GetItemInfoInstant(replyLink:match("%[(.-)%]"))) or 0)
        if itemID and itemID > 0 then
            CancelPendingQueriesByItem(itemID, "beaten by " .. tostring(querySender) .. " via chat")
        end
        return
    end

    -- 2. Handle Incoming Queries
    if msg:find("^%?") then
        -- Respect the user's setting to disable auto-replies
        if MarketSyncDB and not MarketSyncDB.EnableChatPriceCheck then return end

        -- Never reply to your own queries
        if querySender == UnitName("player") then return end
        if not querySenderKey then return end

        local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            if not itemID then return end

            -- Init pending table if needed
            if not MarketSync.pendingQueries then MarketSync.pendingQueries = {} end

            local queryKey = BuildPriceCheckQueryKey(querySenderKey, itemID)
            if not queryKey then return end

            -- Ignore if we already have a pending reply for this requester+item (debounce)
            if MarketSync.pendingQueries[queryKey] then return end

            -- Check if we even have data first
            local price = MarketSync.GetAuctionPrice(link)
            if not price then return end -- No data, no reply

            local allowed, denyReason = AllowPriceCheckRequest(querySenderKey)
            if not allowed then
                Debug("Suppressed price check from " .. tostring(querySender) .. " (" .. tostring(denyReason) .. ")")
                return
            end

            -- Start the lottery!
            MarketSync.pendingQueries[queryKey] = {
                itemID = itemID,
                sender = sender,
                senderKey = querySenderKey,
            }
            local delay = 0.5 + (math.random() * 2.5) -- 0.5s to 3.0s random delay (wider window for coordination)

            C_Timer.After(delay, function()
                -- PHASE 1: If a CLAIM from another client arrived while we waited, abort.
                if not MarketSync.pendingQueries or not MarketSync.pendingQueries[queryKey] then return end
                MarketSync.pendingQueries[queryKey] = nil -- Clear flag

                -- Broadcast our CLAIM to other clients (addon channel = near-instant)
                -- but do NOT send the visible chat reply yet.
                local myIdentity = localIdentity
                if not MarketSync.claimContestants then MarketSync.claimContestants = {} end
                if not MarketSync.claimContestants[queryKey] then MarketSync.claimContestants[queryKey] = {} end
                MarketSync.claimContestants[queryKey][myIdentity] = true -- Register ourselves

                SendPriceCheckClaim(event, channelID, itemID, querySenderKey)

                -- PHASE 2: Grace period — wait 300ms for competing CLAIMs to arrive.
                -- If another client fired at nearly the same time, their CLAIM will arrive
                -- during this window. We then use alphabetical name order as a deterministic
                -- tiebreaker so exactly one client always wins.
                C_Timer.After(0.3, function()
                    -- Check all contestants for this item
                    local contestants = MarketSync.claimContestants and MarketSync.claimContestants[queryKey]
                    if contestants then
                        -- Deterministic tiebreak: lowest alphabetical name wins
                        for name, _ in pairs(contestants) do
                            if string.lower(tostring(name)) < string.lower(tostring(myIdentity)) then
                                -- Someone with a lower name also claimed — they win, we stand down
                                Debug("Price check tiebreak: " .. name .. " wins over " .. myIdentity .. " for item " .. itemID)
                                MarketSync.claimContestants[queryKey] = nil
                                return
                            end
                        end
                        MarketSync.claimContestants[queryKey] = nil -- Clean up
                    end

                    -- We won the tiebreak (or were the only claimant) — send the reply!
                    local age = MarketSync.GetAuctionAge(link)
                    local ageStr

                    local itemID = tonumber(link:match("item:(%d+)"))
                    local exactTime = nil
                    local source = UnitName("player") or "Unknown" -- Default to self
                    
                    local meta = nil
                    if itemID and MarketSyncDB and MarketSync.GetRealmDB().ItemMetadata then
                        meta = MarketSync.GetRealmDB().ItemMetadata[tostring(itemID)] or MarketSync.GetRealmDB().ItemMetadata["g:"..itemID] or MarketSync.GetRealmDB().ItemMetadata["p:"..itemID]
                    end

                    local isToday = (age == 0) or (type(age) == "number" and (age < 1 or math.floor(age) == 0))
                    if isToday then
                        local metaTime = meta and tonumber(meta.lastTime or meta.time) or 0
                        local metaSource = meta and (meta.lastSource or meta.source)
                        
                        local personalTime = 0
                        if MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime then
                            personalTime = tonumber(MarketSync.GetRealmDB().PersonalScanTime) or 0
                        end
                        
                        -- Compare Personal against Guild sync to find who scanned it most recently today
                        if personalTime > metaTime and personalTime > 0 then
                            exactTime = personalTime
                            source = "Personal"
                        elseif metaTime > 0 then
                            exactTime = metaTime
                            source = (metaSource and metaSource ~= "Personal" and metaSource) or "Personal"
                        end
                        
                        if exactTime and exactTime > 0 then
                            ageStr = MarketSync.FormatRealmTime(exactTime, "%H:%M RT (") .. source .. ")"
                        else
                            ageStr = "Today (" .. source .. ")"
                        end
                    elseif age then
                        -- For older scans, trace the exact source for that specific historical day
                        local wholeDays = math.max(1, math.floor(age))
                        if meta and meta.days then
                            local currentDay = MarketSync.GetCurrentScanDay()
                            local scanDay = currentDay - wholeDays
                            local dayData = meta.days[tostring(scanDay)]
                            if dayData and dayData.source and dayData.source ~= "Personal" then
                                source = dayData.source
                            end
                        end
                        ageStr = wholeDays .. "d ago (" .. source .. ")"
                    else
                        ageStr = "Unknown"
                    end
                    
                    local output = string.format("%s: %s (Age: %s)", link, MarketSync.FormatMoney(price), ageStr)

                    local extraInfo = ""

                    -- Add Disenchanting Breakdown
                    if MarketSync.EstimateDisenchantEV then
                        local getItemInfo = MarketSync.GetItemInfo or (C_Item and C_Item.GetItemInfo) or GetItemInfo
                        local getDetailedIlvl = MarketSync.GetDetailedItemLevelInfo or (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
                        local quality, classID
                        if getItemInfo then
                            local _
                            _, _, quality, _, _, _, _, _, _, _, _, classID = getItemInfo(link)
                        end
                        local ilvl = 0
                        if getDetailedIlvl then ilvl = getDetailedIlvl(link) end
                        if (not ilvl or ilvl == 0) and getItemInfo then ilvl = select(4, getItemInfo(link)) or 0 end

                        if quality and quality >= 2 and quality <= 4 and (classID == 2 or classID == 4) and ilvl > 0 then
                            local isWeapon = (classID == 2)
                            local ev = MarketSync.EstimateDisenchantEV(quality, ilvl, isWeapon)
                            if ev and ev > 0 then
                                extraInfo = extraInfo .. string.format(" - DE EV: %s", MarketSync.FormatMoney(ev))
                            end
                        end
                    end
                    
                    -- Add Processing Breakdown
                    if MarketSync.ProcessingData and MarketSync.ProcessingData[itemID] then
                        local def = MarketSync.ProcessingData[itemID]
                        local evTotal = 0
                        for _, y in ipairs(def.yields or {}) do
                            local ex = y.qty or ((y.minQty + y.maxQty) / 2)
                            local matPrice = MarketSync.GetAuctionPrice("item:" .. y.itemID) or 0
                            evTotal = evTotal + (matPrice * ex * (y.prob or 1))
                        end
                        if evTotal > 0 then
                            extraInfo = extraInfo .. string.format(" - %s EV: %s", def.type or "Processing", MarketSync.FormatMoney(evTotal))
                        end
                    end

                    output = output .. extraInfo
                    C_ChatInfo.SendChatMessage(output, "WHISPER", nil, sender)
                end)
            end)
        end
    end
end)
