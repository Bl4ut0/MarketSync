-- ================================================================
-- MarketSync - Native Auction House Scanner
-- 100% standalone scanning engine using Forever C_AuctionHouse APIs
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.Scanner = {
    Active = false,
    Status = "Idle",
    Generation = 0,
    NextRequestAt = 0,
    Scheduled = false,
    Queue = {},
    Pending = nil,
    Progress = { current = 0, total = 0 },
    RecentResults = {},
    ResultsRevision = 0,
    Callbacks = {},
    ReplicateProcessing = false,
}

local S = MarketSync.Scanner

local function GetAHAPI()
    return C_AuctionHouse or _G.C_AuctionHouse
end

local function GetReplicateFuncs()
    local api = GetAHAPI()
    local repl = (api and type(api.ReplicateItems) == "function" and api.ReplicateItems)
        or (type(_G.ReplicateItems) == "function" and _G.ReplicateItems)
    local getNum = (api and type(api.GetNumReplicateItems) == "function" and api.GetNumReplicateItems)
        or (type(_G.GetNumReplicateItems) == "function" and _G.GetNumReplicateItems)
    local getInfo = (api and type(api.GetReplicateItemInfo) == "function" and api.GetReplicateItemInfo)
        or (type(_G.GetReplicateItemInfo) == "function" and _G.GetReplicateItemInfo)
    local getLink = (api and type(api.GetReplicateItemLink) == "function" and api.GetReplicateItemLink)
        or (type(_G.GetReplicateItemLink) == "function" and _G.GetReplicateItemLink)
    return repl, getNum, getInfo, getLink
end

local function SafeCall(name, ...)
    local api = GetAHAPI()
    if not api or type(api[name]) ~= "function" then return nil end
    local ok, result = pcall(api[name], ...)
    if not ok then
        MarketSync.Debug("C_AuctionHouse." .. name .. " error: " .. tostring(result))
        return nil
    end
    return result
end

function S.RegisterCallback(fn)
    if type(fn) == "function" then
        table.insert(S.Callbacks, fn)
    end
end

function S.Notify()
    for _, fn in ipairs(S.Callbacks) do
        pcall(fn)
    end
end

local function StopDebugProgressTicker()
    if S.DebugProgressTicker then
        S.DebugProgressTicker:Cancel()
        S.DebugProgressTicker = nil
    end
end

local function StartDebugProgressTicker()
    StopDebugProgressTicker()
    if MarketSyncDB and MarketSyncDB.DebugMode then
        MarketSync.Debug("Scanner started: " .. tostring(S.Status or "Starting scan"))
    end
    S.DebugProgressTicker = C_Timer.NewTicker(2, function()
        if not S.Active then
            StopDebugProgressTicker()
            return
        end
        if MarketSyncDB and MarketSyncDB.DebugMode then
            MarketSync.Debug("Scanner progress: " .. tostring(S.Status or "In progress"))
        end
    end)
end

function S.IsAvailable()
    local frameOpen = MarketSync.IsAuctionHouseOpen == true
        or (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown())
        or (_G.AuctionFrame and _G.AuctionFrame:IsShown())
    local api = GetAHAPI()
    return (frameOpen == true) and api ~= nil and type(api.SendSearchQuery) == "function"
end

function S.CopyKey(key)
    if type(key) ~= "table" or type(key.itemID) ~= "number" or key.itemID <= 0 then return nil end
    return {
        itemID = key.itemID,
        itemLevel = key.itemLevel or 0,
        itemSuffix = key.itemSuffix or 0,
        battlePetSpeciesID = key.battlePetSpeciesID or 0,
    }
end

local function NotifyScanProgress()
    local now = (type(GetTime) == "function" and GetTime()) or time()
    if not S.LastProgressNotifyAt or now - S.LastProgressNotifyAt >= 0.25 then
        S.LastProgressNotifyAt = now
        S.Notify()
    end
end

local function GetItemSuffixFromLink(itemLink)
    if type(itemLink) ~= "string" then return 0 end
    local itemString = itemLink:match("|H(item:[^|]+)|h") or itemLink:match("(item:%d+[^%s|]*)")
    if not itemString then return 0 end

    local fields = {}
    for field in itemString:gmatch("([^:]+)") do
        fields[#fields + 1] = field
    end
    -- Item links use: item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:...
    return tonumber(fields[8]) or 0
end

local function GetVariantItemLink(itemID, itemSuffix)
    if not itemID then return nil end
    if not itemSuffix or itemSuffix == 0 then return "item:" .. tostring(itemID) end
    return string.format("item:%d:0:0:0:0:0:%d:0", itemID, itemSuffix)
end

function S.ToItemKey(keyOrID)
    if type(keyOrID) == "table" and keyOrID.itemID then
        return S.CopyKey(keyOrID)
    end
    local id = tonumber(keyOrID)
    local itemSuffix = type(keyOrID) == "string" and GetItemSuffixFromLink(keyOrID) or 0
    if not id and type(keyOrID) == "string" then
        if MarketSync.ParseItemIDFromDBKey then
            local parsedID, parsedSuffix = MarketSync.ParseItemIDFromDBKey(keyOrID)
            id = parsedID
            itemSuffix = tonumber(parsedSuffix) or itemSuffix
        end
        id = id or tonumber(keyOrID:match("item:(%d+)") or keyOrID:match("^(%d+)$"))
        if not id then
            local cleanName = keyOrID:match("%[(.-)%]") or keyOrID
            cleanName = cleanName:match("^%s*(.-)%s*$")
            if cleanName and cleanName ~= "" then
                if C_Item and C_Item.GetItemInfoInstant then
                    local ok, iid = pcall(C_Item.GetItemInfoInstant, cleanName)
                    if ok and tonumber(iid) then id = tonumber(iid) end
                elseif GetItemInfoInstant then
                    local ok, iid = pcall(GetItemInfoInstant, cleanName)
                    if ok and tonumber(iid) then id = tonumber(iid) end
                end
            end
        end
    end
    if id and id > 0 then
        local api = GetAHAPI()
        if api and type(api.MakeItemKey) == "function" then
            local ok, k = pcall(api.MakeItemKey, id, 0, itemSuffix, 0)
            if ok and k then return k end
        end
        return {
            itemID = id,
            itemLevel = 0,
            itemSuffix = itemSuffix,
            battlePetSpeciesID = 0,
        }
    end
    return nil
end

function S.KeyID(key)
    local k = S.CopyKey(key)
    if not k then return nil end
    return table.concat({k.itemID, k.itemLevel, k.itemSuffix, k.battlePetSpeciesID}, ":")
end

function S.Cancel(reason)
    S.Generation = S.Generation + 1
    S.Active = false
    StopDebugProgressTicker()
    S.Pending = nil
    S.Queue = {}
    S.Scheduled = false
    S.ReplicateProcessing = false
    S.FullScanMetadataAttempted = nil
    S.Status = reason or "Scan cancelled"
    S.Notify()
end

local function NormalizeItemKey(itemKey)
    if not itemKey then return nil, nil, nil end
    local itemID, itemSuffix = nil, 0
    if type(itemKey) == "table" then
        itemID = tonumber(itemKey.itemID)
        itemSuffix = tonumber(itemKey.itemSuffix) or 0
    elseif type(itemKey) == "number" then
        itemID = itemKey
    elseif type(itemKey) == "string" then
        if MarketSync.ParseItemIDFromDBKey then
            itemID, itemSuffix = MarketSync.ParseItemIDFromDBKey(itemKey)
        end
        itemID = itemID or tonumber(itemKey)
        itemSuffix = tonumber(itemSuffix) or 0
    end
    if not itemID or itemID <= 0 then return nil, nil, nil end
    local dbKey = (itemSuffix and itemSuffix ~= 0) and string.format("p:%d:%d", itemID, itemSuffix) or tostring(itemID)
    local normalizedKey = { itemID = itemID, itemLevel = 0, itemSuffix = itemSuffix, battlePetSpeciesID = 0 }
    return dbKey, itemID, normalizedKey
end
MarketSync.NormalizeItemKey = NormalizeItemKey

local lastScanObservations = {}

local function RecordScanObservation(itemKey, unitPrice, available, isCommodity, isFullScan, deferNotify)
    if not itemKey or not unitPrice or unitPrice <= 0 then return end
    local dbKey, itemID, normalizedKey = NormalizeItemKey(itemKey)
    if not dbKey or not itemID then return end
    normalizedKey.itemLink = (type(itemKey) == "table" and itemKey.itemLink)
        or GetVariantItemLink(itemID, normalizedKey.itemSuffix)
    normalizedKey.dbKey = dbKey

    local now = time()

    -- Debounce duplicate event bursts for identical observation within 2 seconds
    if not isFullScan then
        local lastObs = lastScanObservations[dbKey]
        if lastObs and (now - lastObs.time) < 2 and lastObs.price == unitPrice and lastObs.available == (available or 0) then
            return
        end
        lastScanObservations[dbKey] = { time = now, price = unitPrice, available = available or 0 }
    end

    local realmDB = MarketSync.GetRealmDB()
    if not realmDB.PersonalData then realmDB.PersonalData = {} end
    local pData = realmDB.PersonalData

    local currentDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or math.floor(now / 86400)
    local dayStr = tostring(currentDay)
    local bucketID = MarketSync.GetCurrentBucket and MarketSync.GetCurrentBucket() or math.floor(now / 1800)
    local bucketOffset = bucketID % 48

    if not pData[dbKey] then
        pData[dbKey] = { m = unitPrice, d = currentDay, h = {}, vh = {} }
    end
    local entry = pData[dbKey]
    entry.m = unitPrice
    entry.d = currentDay
    entry.latestBucket = bucketID
    if not entry.h then entry.h = {} end
    if not entry.vh then entry.vh = {} end

    entry.h[dayStr] = MarketSync.UpsertScanBucket(entry.h[dayStr], bucketOffset,
        unitPrice, math.max(1, available or 1))
    entry.vh[dayStr] = entry.h[dayStr]

    realmDB.PersonalScanTime = now
    realmDB.SwarmTSF = now
    if isFullScan then
        realmDB.FullScanTime = now
    else
        realmDB.PartialScanTime = now
    end
    realmDB.LatestBucket = math.max(tonumber(realmDB.LatestBucket) or 0, bucketID)

    -- Metadata is stable per item ID. A full replicate can contain many variants
    -- of the same item, so resolve it at most once and reuse the persistent cache.
    local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
    local cached = cache and cache[itemID]
    local name, link, quality, ilvl, minLevel, icon, classID, subClassID
    if cached then
        name, quality, ilvl, minLevel = cached.n, cached.r, cached.i, cached.m
        icon, classID, subClassID = cached.ic, cached.c, cached.s
    end
    local completeMetadata = name and quality ~= nil and ilvl ~= nil and classID ~= nil and icon ~= nil
    local attempted = isFullScan and S.FullScanMetadataAttempted
    local metadataFetched = false
    if not completeMetadata and not (attempted and attempted[itemID]) then
        if attempted then attempted[itemID] = true end
        metadataFetched = true
        local resolvedName, resolvedLink, resolvedQuality, resolvedIlvl, resolvedMinLevel,
            _, _, _, _, resolvedIcon, _, resolvedClassID, resolvedSubClassID
        if MarketSync.GetItemInfo then
            resolvedName, resolvedLink, resolvedQuality, resolvedIlvl, resolvedMinLevel,
                _, _, _, _, resolvedIcon, _, resolvedClassID, resolvedSubClassID = MarketSync.GetItemInfo(itemID)
        elseif C_Item and C_Item.GetItemInfo then
            resolvedName, resolvedLink, resolvedQuality, resolvedIlvl, resolvedMinLevel,
                _, _, _, _, resolvedIcon, _, resolvedClassID, resolvedSubClassID = C_Item.GetItemInfo(itemID)
        elseif GetItemInfo then
            resolvedName, resolvedLink, resolvedQuality, resolvedIlvl, resolvedMinLevel,
                _, _, _, _, resolvedIcon, _, resolvedClassID, resolvedSubClassID = GetItemInfo(itemID)
        end
        name, link = resolvedName or name, resolvedLink
        quality, ilvl, minLevel = resolvedQuality or quality, resolvedIlvl or ilvl, resolvedMinLevel or minLevel
        icon, classID, subClassID = resolvedIcon or icon, resolvedClassID or classID, resolvedSubClassID or subClassID
    end
    if metadataFetched and name and MarketSyncDB then
        MarketSyncDB.ItemInfoCache = cache or {}
        cached = cached or {}
        cached.n = name
        cached.r = quality or cached.r
        cached.i = ilvl or cached.i
        cached.m = minLevel or cached.m
        cached.ic = icon or cached.ic
        cached.c = classID or cached.c
        cached.s = subClassID or cached.s
        MarketSyncDB.ItemInfoCache[itemID] = cached
    end
    local displayName = name
    if normalizedKey.itemSuffix ~= 0 then
        local variantName = type(normalizedKey.itemLink) == "string"
            and normalizedKey.itemLink:match("%[(.-)%]") or nil
        local variantLink = normalizedKey.itemLink
        if not variantName and not isFullScan then
            if MarketSync.GetItemInfo then
                variantName, variantLink = MarketSync.GetItemInfo(normalizedKey.itemLink)
            elseif C_Item and C_Item.GetItemInfo then
                variantName, variantLink = C_Item.GetItemInfo(normalizedKey.itemLink)
            elseif GetItemInfo then
                variantName, variantLink = GetItemInfo(normalizedKey.itemLink)
            end
        end
        displayName = variantName or name
        link = variantLink or normalizedKey.itemLink or link
    end

    -- A full AH replicate can contain thousands of variants but HistoryLog only
    -- retains 100 entries. Keep that activity log for targeted scans; the full
    -- scan's durable per-item record is PersonalData above.
    if not isFullScan then
        if not realmDB.HistoryLog then realmDB.HistoryLog = {} end
        local itemLink = (normalizedKey.itemSuffix ~= 0 and normalizedKey.itemLink)
            or link
            or (type(itemKey) == "string" and itemKey:match("|Hitem:"))
            or ("item:" .. itemID)
        table.insert(realmDB.HistoryLog, 1, {
            link = itemLink,
            price = unitPrice,
            sender = "Self",
            time = now,
        })
        if #realmDB.HistoryLog > 100 then table.remove(realmDB.HistoryLog) end
    end

    -- Record in live Scanner feed
    table.insert(S.RecentResults, 1, {
        itemID = itemID,
        itemKey = normalizedKey,
        dbKey = dbKey,
        name = displayName or ("Item #" .. itemID),
        icon = icon or 134400,
        quality = quality or 1,
        unitPrice = unitPrice,
        available = available or 0,
        time = now,
        isCommodity = isCommodity or false,
    })
    if #S.RecentResults > 50 then table.remove(S.RecentResults) end
    S.ResultsRevision = (S.ResultsRevision or 0) + 1

    -- Evaluate notifications
    if MarketSync.EvaluateNotificationsForRecord then
        pcall(MarketSync.EvaluateNotificationsForRecord, dbKey, unitPrice, "main", "Personal")
    end

    -- Notify subscribers (UI_AHSidecar shopping lists, UI_AHScanner, etc.)
    if not deferNotify then S.Notify() end

    -- Debounced sync advertisement on partial/individual scans
    if not isFullScan and MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
        if not S._advScheduled then
            S._advScheduled = true
            C_Timer.After(2, function()
                S._advScheduled = false
                if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end
            end)
        end
    end
end
MarketSync.RecordScanObservation = RecordScanObservation

local function SummarizeSearchResults(key, isCommodityHint)
    local tries = isCommodityHint and { true, false } or { false, true }
    for _, isCommodity in ipairs(tries) do
        local argument = isCommodity and key.itemID or key
        local countName = isCommodity and "GetNumCommoditySearchResults" or "GetNumItemSearchResults"
        local infoName = isCommodity and "GetCommoditySearchResultInfo" or "GetItemSearchResultInfo"
        local completeName = isCommodity and "HasFullCommoditySearchResults" or "HasFullItemSearchResults"

        local count = SafeCall(countName, argument) or 0
        if count > 0 then
            local isComplete = SafeCall(completeName, argument)
            local minUnitPrice = nil
            local totalAvailable = 0

            for index = 1, count do
                local row = SafeCall(infoName, argument, index)
                if row then
                    local quantity = tonumber(row.quantity) or 0
                    if quantity > 0 then
                        totalAvailable = totalAvailable + quantity
                        local unitPrice = isCommodity and row.unitPrice or nil
                        if not isCommodity and row.buyoutAmount and row.buyoutAmount > 0 then
                            unitPrice = row.buyoutAmount / quantity
                        end
                        if type(unitPrice) == "number" and unitPrice > 0 then
                            if not minUnitPrice or unitPrice < minUnitPrice then
                                minUnitPrice = unitPrice
                            end
                        end
                    end
                end
            end

            if minUnitPrice and minUnitPrice > 0 then
                return minUnitPrice, totalAvailable, isComplete, isCommodity
            end
        end
    end

    return nil, 0, false, isCommodityHint
end

function S.ScheduleNext()
    if not S.Active or S.Scheduled then return end
    S.Scheduled = true
    local gen = S.Generation
    local delay = math.max(0.05, S.NextRequestAt - GetTime())

    C_Timer.After(delay, function()
        S.Scheduled = false
        if gen ~= S.Generation or not S.Active then return end

        if #S.Queue == 0 then
            S.Active = false
            StopDebugProgressTicker()
            S.Pending = nil
            S.Status = "Scan Complete"
            if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
            if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                C_Timer.After(2, function() if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end end)
            end
            MarketSync.Debug("Scanner complete: " .. S.Status)
            S.Notify()
            return
        end

        local itemKey = table.remove(S.Queue, 1)
        S.Pending = itemKey
        S.Progress.current = S.Progress.total - #S.Queue
        S.Status = string.format("Scanning %d / %d...", S.Progress.current, S.Progress.total)
        S.NextRequestAt = GetTime() + 1.1

        local sorts = {}
        local api = GetAHAPI()
        local ok = false
        if api and type(api.SendSearchQuery) == "function" then
            ok = pcall(api.SendSearchQuery, itemKey, sorts, false)
        end
        if not ok then
            MarketSync.Debug("SendSearchQuery failed for " .. tostring(itemKey.itemID))
            S.Pending = nil
            S.ScheduleNext()
        else
            -- Watchdog: advance queue if server drops event or throttles longer than 6 seconds
            local currentPending = itemKey
            local currentGen = S.Generation
            C_Timer.After(6, function()
                if S.Active and S.Generation == currentGen and S.Pending == currentPending then
                    MarketSync.Debug("Search timeout for item " .. tostring(currentPending.itemID) .. "; advancing queue")
                    S.Pending = nil
                    S.ScheduleNext()
                end
            end)
        end
        S.Notify()
    end)
end

function S.StartScan(itemsOrKeys, label)
    if not S.IsAvailable() then
        S.Status = "Auctioneer must be open to scan"
        S.Notify()
        print("|cFFFF4444[MarketSync]|r Auctioneer must be open to scan.")
        return false
    end

    S.Generation = S.Generation + 1
    S.Active = true
    S.ReplicateProcessing = false
    S.FullScanMetadataAttempted = {}
    S.Scheduled = false
    S.Queue = {}
    S.RecentResults = {}
    S.ResultsRevision = (S.ResultsRevision or 0) + 1
    if wipe then wipe(lastScanObservations) else lastScanObservations = {} end

    local seen = {}
    for _, item in ipairs(itemsOrKeys or {}) do
        local key = S.ToItemKey(item)
        if key and key.itemID and not seen[key.itemID] then
            seen[key.itemID] = true
            table.insert(S.Queue, key)
        end
    end

    if #S.Queue == 0 then
        S.Active = false
        S.Status = "No items to scan"
        S.Notify()
        return false
    end

    S.Progress.total = #S.Queue
    S.Progress.current = 0
    S.Status = label or string.format("Starting scan of %d items...", S.Progress.total)
    S.NextRequestAt = GetTime()
    StartDebugProgressTicker()
    S.ScheduleNext()
    S.Notify()
    return true
end

function S.ScanList(listName)
    listName = listName or "Favorites"
    local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(listName) or {}
    local ids = {}
    for _, item in ipairs(items) do
        if item.itemID then table.insert(ids, item.itemID) end
    end
    if #ids == 0 then
        S.Status = "No items in list '" .. listName .. "'"
        S.Notify()
        print(string.format("|cFFFF4444[MarketSync]|r List '%s' has no items to scan. Drag an item or type its name to add items.", listName))
        return false
    end
    return S.StartScan(ids, "Scanning " .. listName .. " (" .. #ids .. " items)...")
end

function S.ScanWatched()
    local ids = {}
    if MarketSyncDB and MarketSyncDB.WatchList then
        for id in pairs(MarketSyncDB.WatchList) do
            table.insert(ids, id)
        end
    end
    if #ids == 0 and MarketSync.Favorites then
        local items = MarketSync.Favorites.GetListItems("Favorites") or {}
        for _, it in ipairs(items) do
            if it.itemID then table.insert(ids, it.itemID) end
        end
    end
    if #ids == 0 then
        S.Status = "No watched or favorite items to scan"
        S.Notify()
        print("|cFFFF4444[MarketSync]|r No watched items or favorites to scan. Add items to Favorites first.")
        return false
    end
    return S.StartScan(ids, "Scanning Watched Items (" .. #ids .. " items)...")
end

function S.GetFullScanCooldownRemaining()
    if not MarketSyncDB or not MarketSyncDB.LastFullScanAt then return 0 end
    local elapsed = time() - MarketSyncDB.LastFullScanAt
    if elapsed < 900 then
        return 900 - elapsed
    end
    return 0
end

function S.ScanMultipleLists(listNames)
    if type(listNames) ~= "table" or #listNames == 0 then return false end
    local seen = {}
    local ids = {}
    for _, listName in ipairs(listNames) do
        local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(listName) or {}
        for _, it in ipairs(items) do
            if it.itemID and not seen[it.itemID] then
                seen[it.itemID] = true
                table.insert(ids, it.itemID)
            end
        end
    end
    if #ids == 0 then
        S.Status = "No items in selected lists"
        S.Notify()
        print("|cFFFF4444[MarketSync]|r Selected lists contain no items to scan. Drag or type items into lists first.")
        return false
    end
    local title = string.format("Scanning %d Lists (%d items)...", #listNames, #ids)
    return S.StartScan(ids, title)
end

function S.StartFullScan()
    if not S.IsAvailable() then
        S.Status = "Auctioneer must be open to scan"
        S.Notify()
        print("|cFFFF4444[MarketSync]|r Auctioneer must be open to scan.")
        return false
    end

    local cd = S.GetFullScanCooldownRemaining()
    if cd > 0 then
        local mins = math.floor(cd / 60)
        local secs = cd % 60
        S.Status = string.format("Full scan on cooldown (%dm %02ds remaining)", mins, secs)
        S.Notify()
        print(string.format("|cFFFF4444[MarketSync]|r Full AH scan on cooldown (%dm %02ds remaining).", mins, secs))
        return false
    end

    local replFunc, getNumFunc, getInfoFunc = GetReplicateFuncs()
    if not replFunc or not getNumFunc or not getInfoFunc then
        S.Status = "Full scan (ReplicateItems) not supported on this client"
        S.Progress.current = 0
        S.Progress.total = 0
        S.Notify()
        print("|cFFFF4444[MarketSync]|r Full AH scan (ReplicateItems) not supported on this client. Use Scan Watched or Scan Lists instead.")
        return false
    end

    S.Generation = S.Generation + 1
    S.Active = true
    S.ReplicateProcessing = false
    S.FullScanMetadataAttempted = {}
    S.Pending = nil
    S.Queue = {}
    S.RecentResults = {}
    S.ResultsRevision = (S.ResultsRevision or 0) + 1
    S.LastProgressNotifyAt = nil
    -- No percentage is meaningful until the server returns the snapshot size.
    S.Progress.total = 0
    S.Progress.current = 0
    S.Status = "Requesting full AH snapshot from server..."
    StartDebugProgressTicker()
    S.Notify()

    local ok, requestResult = pcall(replFunc)
    if not ok or requestResult == false then
        S.Active = false
        StopDebugProgressTicker()
        S.Status = "ReplicateItems request failed"
        S.Progress.current = 0
        S.Progress.total = 0
        S.Notify()
        print("|cFFFF4444[MarketSync]|r ReplicateItems request failed.")
        return false
    end

    -- Some clients accept ReplicateItems without returning data or firing the
    -- result event. Avoid leaving the scanner stuck in an active 0% state.
    local requestGeneration = S.Generation
    C_Timer.After(30, function()
        if S.Active and S.Generation == requestGeneration and not S.ReplicateProcessing then
            S.Active = false
            StopDebugProgressTicker()
            S.FullScanMetadataAttempted = nil
            S.Status = "Full scan timed out waiting for the auction snapshot"
            S.Progress.current = 0
            S.Progress.total = 0
            S.Notify()
        end
    end)

    return true
end

-- ================================================================
-- EVENT FRAME: Handle Search Results & Full Scan Replicate
-- ================================================================
local eventFrame = CreateFrame("Frame")
pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_SEARCH_RESULTS_UPDATED")
pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_SEARCH_RESULTS_ADDED")
pcall(eventFrame.RegisterEvent, eventFrame, "COMMODITY_SEARCH_RESULTS_UPDATED")
pcall(eventFrame.RegisterEvent, eventFrame, "COMMODITY_SEARCH_RESULTS_ADDED")
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
pcall(eventFrame.RegisterEvent, eventFrame, "REPLICATE_ITEM_LIST_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "AUCTION_HOUSE_CLOSED" then
        if S.Active then
            S.Cancel("Auctioneer closed")
        end
        return
    end

    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        local replFunc, getNumFunc, getInfoFunc, getLinkFunc = GetReplicateFuncs()
        if not S.Active or S.ReplicateProcessing or not getNumFunc or not getInfoFunc then return end
        S.ReplicateProcessing = true
        local totalItems = getNumFunc() or 0
        if totalItems == 0 then
            S.Status = "Replicate returned 0 items"
            S.Active = false
            S.ReplicateProcessing = false
            StopDebugProgressTicker()
            S.FullScanMetadataAttempted = nil
            S.Notify()
            return
        end

        S.Status = string.format("Processing %d auction items...", totalItems)
        S.Progress.total = totalItems
        S.Progress.current = 0
        S.Notify()

        -- Pace replicate reads across frames. Auctionator uses 250-row batches;
        -- keep that ceiling here so a large snapshot cannot monopolize one frame.
        local READ_BATCH_SIZE = 250
        -- Persist fewer rows per tick than Auctionator's simple price DB writes:
        -- MarketSync also updates history, recent results, and alert state.
        local WRITE_BATCH_SIZE = 150
        local currentIndex = 0
        local aggregated = {}
        local aggregateKeys = {}
        local scanGeneration = S.Generation

        local function FinishFullScan()
            MarketSyncDB.LastFullScanAt = time()
            local realmDB = MarketSync.GetRealmDB()
            if realmDB then
                realmDB.FullScanTime = time()
                realmDB.PersonalScanTime = time()
                realmDB.SwarmTSF = time()
            end
            S.Active = false
            S.ReplicateProcessing = false
            StopDebugProgressTicker()
            S.FullScanMetadataAttempted = nil
            S.Status = string.format("Full Scan Complete: %d item variants recorded", S.FullScanRecordedCount or 0)
            S.FullScanRecordedCount = nil
            if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
            if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                C_Timer.After(1, function() if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end end)
            end
            MarketSync.Debug("Scanner complete: " .. S.Status)
            S.Notify()
        end

        local function ProcessRecordBatch()
            if not S.Active or S.Generation ~= scanGeneration then return end

            local stopIndex = math.min(#aggregateKeys, currentIndex + WRITE_BATCH_SIZE)
            for keyIndex = currentIndex + 1, stopIndex do
                local info = aggregated[aggregateKeys[keyIndex]]
                if info then
                    RecordScanObservation(info.itemKey, info.unitPrice, info.available, false, true, true)
                    S.FullScanRecordedCount = (S.FullScanRecordedCount or 0) + 1
                end
            end
            currentIndex = stopIndex

            if currentIndex >= #aggregateKeys then
                FinishFullScan()
                return
            end

            S.Status = string.format("Saving scan results (%d / %d variants)...", currentIndex, #aggregateKeys)
            NotifyScanProgress()
            C_Timer.After(0.01, ProcessRecordBatch)
        end

        local function ProcessReadBatch()
            if not S.Active or S.Generation ~= scanGeneration then return end

            local stopIndex = math.min(totalItems, currentIndex + READ_BATCH_SIZE)
            for idx = currentIndex + 1, stopIndex do
                local name, texture, count, qualityID, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID = getInfoFunc(idx - 1)
                local itemSuffix = 0
                local itemLink
                if not itemID and type(name) == "table" and name.itemID then
                    local info = name
                    itemID = info.itemID
                    count = info.quantity or 1
                    buyoutPrice = info.buyoutAmount or 0
                    itemSuffix = tonumber(info.itemSuffix) or 0
                elseif type(name) == "table" then
                    itemSuffix = tonumber(name.itemSuffix) or 0
                end

                if getLinkFunc then
                    local linkOK, replicateLink = pcall(getLinkFunc, idx - 1)
                    if linkOK then
                        itemLink = replicateLink
                        local linkSuffix = GetItemSuffixFromLink(itemLink)
                        if linkSuffix ~= 0 then itemSuffix = linkSuffix end
                    end
                end

                if itemID and itemID > 0 and count and count > 0 and buyoutPrice and buyoutPrice > 0 then
                    local unitPrice = math.floor(buyoutPrice / count)
                    if unitPrice > 0 then
                        local dbKey = itemSuffix ~= 0
                            and string.format("p:%d:%d", itemID, itemSuffix)
                            or tostring(itemID)
                        local existing = aggregated[dbKey]
                        if not existing then
                            aggregateKeys[#aggregateKeys + 1] = dbKey
                            aggregated[dbKey] = {
                                itemID = itemID,
                                itemKey = {
                                    itemID = itemID,
                                    itemLevel = 0,
                                    itemSuffix = itemSuffix,
                                    battlePetSpeciesID = 0,
                                    itemLink = itemLink or GetVariantItemLink(itemID, itemSuffix),
                                },
                                unitPrice = unitPrice,
                                available = count,
                            }
                        else
                            existing.available = existing.available + count
                            if unitPrice < existing.unitPrice then
                                existing.unitPrice = unitPrice
                                existing.itemKey.itemLink = itemLink or existing.itemKey.itemLink
                            end
                        end
                    end
                end
            end

            currentIndex = stopIndex
            S.Progress.current = currentIndex
            S.Status = string.format("Processing auctions (%d / %d)...", currentIndex, totalItems)
            NotifyScanProgress()

            if currentIndex >= totalItems then
                currentIndex = 0
                S.FullScanRecordedCount = 0
                S.Status = string.format("Saving scan results (0 / %d variants)...", #aggregateKeys)
                NotifyScanProgress()
                ProcessRecordBatch()
            else
                C_Timer.After(0.01, ProcessReadBatch)
            end
        end

        currentIndex = 0
        ProcessReadBatch()
        return
    end

    if event == "ITEM_SEARCH_RESULTS_UPDATED"
        or event == "ITEM_SEARCH_RESULTS_ADDED"
        or event == "COMMODITY_SEARCH_RESULTS_UPDATED"
        or event == "COMMODITY_SEARCH_RESULTS_ADDED" then

        local isCommodity = (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED")
        local updatedItemID = nil
        local updatedItemKey = nil
        if type(arg1) == "table" and arg1.itemID then
            updatedItemID = tonumber(arg1.itemID)
            updatedItemKey = arg1
        elseif type(arg1) == "number" or type(arg1) == "string" then
            updatedItemID = tonumber(arg1)
            if updatedItemID then
                updatedItemKey = { itemID = updatedItemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
            end
        end

        if S.Active then
            if S.Pending then
                -- Automated queue scan: process pending item and advance queue
                if not updatedItemID or (S.Pending.itemID and updatedItemID == S.Pending.itemID) then
                    local minPrice, available, isComplete, resolvedCommodity = SummarizeSearchResults(S.Pending, isCommodity)
                    if minPrice and minPrice > 0 then
                        RecordScanObservation(S.Pending, minPrice, available, resolvedCommodity, false)
                    end
                    S.Pending = nil
                    S.ScheduleNext()
                end
            end
            return
        end

        -- Individual manual search / single-item scan:
        if updatedItemKey or updatedItemID then
            local searchKey = updatedItemKey or { itemID = updatedItemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
            local minPrice, available, isComplete, resolvedCommodity = SummarizeSearchResults(searchKey, isCommodity)
            if minPrice and minPrice > 0 then
                RecordScanObservation(searchKey, minPrice, available, resolvedCommodity, false)
            end
        end
        return
    end
end)
