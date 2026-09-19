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
    Callbacks = {},
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
    return repl, getNum, getInfo
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

function S.ToItemKey(keyOrID)
    if type(keyOrID) == "table" and keyOrID.itemID then
        return S.CopyKey(keyOrID)
    end
    local id = tonumber(keyOrID)
    if not id and type(keyOrID) == "string" then
        id = tonumber(keyOrID:match("item:(%d+)") or keyOrID:match("^(%d+)$"))
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
            local ok, k = pcall(api.MakeItemKey, id, 0, 0, 0)
            if ok and k then return k end
        end
        return {
            itemID = id,
            itemLevel = 0,
            itemSuffix = 0,
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
    S.Pending = nil
    S.Queue = {}
    S.Scheduled = false
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
        local prefix, id, suff = itemKey:match("^(%a+):(%d+):?(%d*)$")
        if id then
            itemID = tonumber(id)
            itemSuffix = tonumber(suff) or 0
        else
            local linkID = itemKey:match("item:(%d+)")
            itemID = linkID and tonumber(linkID) or tonumber(itemKey)
        end
    end
    if not itemID or itemID <= 0 then return nil, nil, nil end
    local dbKey = (itemSuffix and itemSuffix ~= 0) and string.format("p:%d:%d", itemID, itemSuffix) or tostring(itemID)
    local normalizedKey = { itemID = itemID, itemLevel = 0, itemSuffix = itemSuffix, battlePetSpeciesID = 0 }
    return dbKey, itemID, normalizedKey
end
MarketSync.NormalizeItemKey = NormalizeItemKey

local function RecordScanObservation(itemKey, unitPrice, available, isCommodity, isFullScan)
    if not itemKey or not unitPrice or unitPrice <= 0 then return end
    local dbKey, itemID, normalizedKey = NormalizeItemKey(itemKey)
    if not dbKey or not itemID then return end

    local now = time()
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

    -- Base-36 encoded time-series string
    local b36Price = MarketSync.ToBase36(unitPrice)
    local b36Qty = MarketSync.ToBase36(math.max(1, available or 1))
    local point = bucketOffset .. ":" .. b36Price .. ":" .. b36Qty

    if not entry.h[dayStr] or entry.h[dayStr] == "" then
        entry.h[dayStr] = point
    else
        entry.h[dayStr] = entry.h[dayStr] .. "," .. point
    end
    entry.vh[dayStr] = entry.h[dayStr]

    realmDB.PersonalScanTime = now
    realmDB.SwarmTSF = now
    if isFullScan then
        realmDB.FullScanTime = now
    else
        realmDB.PartialScanTime = now
    end
    realmDB.LatestBucket = math.max(tonumber(realmDB.LatestBucket) or 0, bucketID)

    -- Item info lookup
    local name, link, quality, _, _, _, _, _, _, icon = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    if C_Item and C_Item.GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    end
    if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
        name = MarketSyncDB.ItemInfoCache[itemID].n
        icon = MarketSyncDB.ItemInfoCache[itemID].ic
        quality = MarketSyncDB.ItemInfoCache[itemID].r
    end

    -- Record in data logs (HistoryLog)
    if not realmDB.HistoryLog then realmDB.HistoryLog = {} end
    local itemLink = link or (type(itemKey) == "string" and itemKey:match("|Hitem:")) or ("item:" .. itemID)
    table.insert(realmDB.HistoryLog, 1, {
        link = itemLink,
        price = unitPrice,
        sender = "Self",
        time = now,
    })
    if #realmDB.HistoryLog > 100 then table.remove(realmDB.HistoryLog) end

    -- Record in live Scanner feed
    table.insert(S.RecentResults, 1, {
        itemID = itemID,
        itemKey = normalizedKey,
        name = name or ("Item #" .. itemID),
        icon = icon or 134400,
        quality = quality or 1,
        unitPrice = unitPrice,
        available = available or 0,
        time = now,
        isCommodity = isCommodity or false,
    })
    if #S.RecentResults > 50 then table.remove(S.RecentResults) end

    -- Evaluate notifications
    if MarketSync.EvaluateNotificationsForRecord then
        pcall(MarketSync.EvaluateNotificationsForRecord, dbKey, unitPrice, "main", "Personal")
    end

    -- Notify subscribers (UI_AHSidecar shopping lists, UI_AHScanner, etc.)
    S.Notify()

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
            S.Pending = nil
            S.Status = "Scan Complete"
            if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
            if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                C_Timer.After(2, function() if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end end)
            end
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
    S.Scheduled = false
    S.Queue = {}
    S.RecentResults = {}

    for _, item in ipairs(itemsOrKeys or {}) do
        local key = S.ToItemKey(item)
        if key then
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
    if not replFunc then
        S.Status = "Full scan (ReplicateItems) not supported on this client"
        S.Notify()
        print("|cFFFF4444[MarketSync]|r Full AH scan (ReplicateItems) not supported on this client. Use Scan Watched or Scan Lists instead.")
        return false
    end

    S.Generation = S.Generation + 1
    S.Active = true
    S.Pending = nil
    S.Queue = {}
    S.RecentResults = {}
    S.Progress.total = 100
    S.Progress.current = 0
    S.Status = "Requesting full AH snapshot from server..."
    S.Notify()

    local ok = pcall(replFunc)
    if not ok then
        S.Active = false
        S.Status = "ReplicateItems request failed"
        S.Notify()
        print("|cFFFF4444[MarketSync]|r ReplicateItems request failed.")
        return false
    end

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
        local replFunc, getNumFunc, getInfoFunc = GetReplicateFuncs()
        if not S.Active or not getNumFunc or not getInfoFunc then return end
        local totalItems = getNumFunc() or 0
        if totalItems == 0 then
            S.Status = "Replicate returned 0 items"
            S.Active = false
            S.Notify()
            return
        end

        S.Status = string.format("Processing %d auction items...", totalItems)
        S.Progress.total = totalItems
        S.Progress.current = 0
        S.Notify()

        local SLICE_SIZE = 1000
        local currentIndex = 0
        local aggregated = {}

        local sliceFrame = CreateFrame("Frame")
        sliceFrame:SetScript("OnUpdate", function(sf)
            if not S.Active then
                sf:SetScript("OnUpdate", nil)
                return
            end

            local stopIndex = math.min(totalItems, currentIndex + SLICE_SIZE)
            for idx = currentIndex + 1, stopIndex do
                local name, texture, count, qualityID, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID = getInfoFunc(idx - 1)
                if not itemID and type(name) == "table" and name.itemID then
                    local info = name
                    itemID = info.itemID
                    count = info.quantity or 1
                    buyoutPrice = info.buyoutAmount or 0
                end

                if itemID and itemID > 0 and count and count > 0 and buyoutPrice and buyoutPrice > 0 then
                    local unitPrice = math.floor(buyoutPrice / count)
                    if unitPrice > 0 then
                        if not aggregated[itemID] or unitPrice < aggregated[itemID].unitPrice then
                            aggregated[itemID] = {
                                itemID = itemID,
                                unitPrice = unitPrice,
                                available = (aggregated[itemID] and aggregated[itemID].available or 0) + count,
                            }
                        else
                            aggregated[itemID].available = (aggregated[itemID].available or 0) + count
                        end
                    end
                end
            end

            currentIndex = stopIndex
            S.Progress.current = currentIndex
            S.Status = string.format("Processing auctions (%d / %d)...", currentIndex, totalItems)
            S.Notify()

            if currentIndex >= totalItems then
                sf:SetScript("OnUpdate", nil)
                local countRecorded = 0
                for itemID, info in pairs(aggregated) do
                    local key = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
                    RecordScanObservation(key, info.unitPrice, info.available, false, true)
                    countRecorded = countRecorded + 1
                end

                MarketSyncDB.LastFullScanAt = time()
                local realmDB = MarketSync.GetRealmDB()
                if realmDB then
                    realmDB.FullScanTime = time()
                    realmDB.PersonalScanTime = time()
                    realmDB.SwarmTSF = time()
                end

                S.Active = false
                S.Status = string.format("Full Scan Complete: %d items recorded", countRecorded)
                if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
                if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                    C_Timer.After(1, function() if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end end)
                end
                S.Notify()
            end
        end)
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

        if S.Active and S.Pending then
            -- Automated queue scan: process pending item and advance queue
            if not updatedItemID or (S.Pending.itemID and updatedItemID == S.Pending.itemID) then
                local minPrice, available, isComplete, resolvedCommodity = SummarizeSearchResults(S.Pending, isCommodity)
                if minPrice and minPrice > 0 then
                    RecordScanObservation(S.Pending, minPrice, available, resolvedCommodity, false)
                end
                S.Pending = nil
                S.ScheduleNext()
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
