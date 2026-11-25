-- =============================================================
-- MarketSync - Browse Panel
-- Shared browse panel for Personal Scan and Guild Sync tabs
-- =============================================================

local NUM_RESULTS_TO_DISPLAY = 8
local RESULT_HEIGHT = 37
local FILTER_HEIGHT = 21

-- ---- Money Formatter (colorized with g/s/c) ----
local function FormatMoney(copper)
    if not copper or copper == 0 then return "|cff888888N/A|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local str = ""
    if g > 0 then str = str .. "|cffffd700" .. g .. "|r|cffffd700g|r " end
    if s > 0 or g > 0 then str = str .. "|cffc0c0c0" .. s .. "|r|cffc0c0c0s|r " end
    str = str .. "|cffeda55f" .. c .. "|r|cffeda55fc|r"
    return str
end

-- ---- WoW Item Categories (matches native Auction House client) ----
local CATEGORIES = {
    { name = "Weapons", classID = 2, subs = {
        { name = "One-Handed",    subIDs = { 0, 4, 7, 13, 15 } },
        { name = "Two-Handed",    subIDs = { 1, 5, 6, 8, 10 } },
        { name = "Ranged",        subIDs = { 2, 3, 16, 18, 19 } },
        { name = "Miscellaneous", subIDs = { 14, 20 } },
    }},
    { name = "Armor", classID = 4, subs = {
        { name = "Plate",         subIDs = { 4 } },
        { name = "Mail",          subIDs = { 3 } },
        { name = "Leather",       subIDs = { 2 } },
        { name = "Cloth",         subIDs = { 1 } },
        { name = "Relic",         subIDs = { 7, 8, 9, 10, 11 } },
        { name = "Miscellaneous", subIDs = { 0, 6 } },
    }},
    { name = "Containers", classID = 1, subs = {
        { name = "Regular Bags",  subIDs = { 0 } },
        { name = "Ammo",          subIDs = { 10 }, extraClassID = 11 },
        { name = "Trade Bags",    subIDs = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
    }},
    { name = "Consumables", classID = 0, subs = {
        { name = "Potion",           subIDs = { 1 } },
        { name = "Elixir",           subIDs = { 2 } },
        { name = "Flask",            subIDs = { 3 } },
        { name = "Scroll",           subIDs = { 4 } },
        { name = "Food & Drink",     subIDs = { 5 } },
        { name = "Item Enhancement", subIDs = { 6 } },
        { name = "Bandage",          subIDs = { 7 } },
        { name = "Other",            subIDs = { 0 } },
    }},
    { name = "Trade Goods", classID = 7, subs = {
        { name = "Parts",         subIDs = { 1 } },
        { name = "Explosives",    subIDs = { 2 } },
        { name = "Devices",       subIDs = { 3 } },
        { name = "Jewelcrafting", subIDs = { 4 } },
        { name = "Cloth",         subIDs = { 5 } },
        { name = "Leather",       subIDs = { 6 } },
        { name = "Metal & Stone", subIDs = { 7 } },
        { name = "Meat",          subIDs = { 8 } },
        { name = "Herb",          subIDs = { 9 } },
        { name = "Elemental",     subIDs = { 10 } },
        { name = "Enchanting",    subIDs = { 12 } },
        { name = "Other",         subIDs = { 0, 11 } },
    }},
    { name = "Ammo", classID = 6, subs = {
        { name = "Arrow",  subIDs = { 2 } },
        { name = "Bullet", subIDs = { 3 } },
    }},
    { name = "Recipes", classID = 9, subs = {
        { name = "Book",                 subIDs = { 0 } },
        { name = "Leatherworking",       subIDs = { 1 } },
        { name = "Tailoring",           subIDs = { 2 } },
        { name = "Engineering",          subIDs = { 3 } },
        { name = "Blacksmithing",        subIDs = { 4 } },
        { name = "Cooking",              subIDs = { 5 } },
        { name = "Alchemy",              subIDs = { 6 } },
        { name = "First Aid (Health)",   subIDs = { 7 } },
        { name = "Enchanting",           subIDs = { 8 } },
        { name = "Fishing",              subIDs = { 9 } },
        { name = "Jewelcrafting",        subIDs = { 10 } },
    }},
    { name = "Quest Items",   classID = 12 },
    { name = "Miscellaneous", classID = 15, subs = {
        { name = "Junk",           subIDs = { 0 } },
        { name = "Reagent",        subIDs = { 1 } },
        { name = "Companion Pets", subIDs = { 2 } },
        { name = "Holiday",        subIDs = { 3 } },
        { name = "Mount",          subIDs = { 5 } },
        { name = "Other",          subIDs = { 4 } },
    }},
}

-- ---- Rarity Colors ----
local RARITY_COLORS = {
    [0] = {0.62, 0.62, 0.62}, -- Poor
    [1] = {1.00, 1.00, 1.00}, -- Common
    [2] = {0.12, 1.00, 0.00}, -- Uncommon
    [3] = {0.00, 0.44, 0.87}, -- Rare
    [4] = {0.64, 0.21, 0.93}, -- Epic
    [5] = {1.00, 0.50, 0.00}, -- Legendary
}

-- ================================================================
-- SEARCH INDEX CACHES (three separate indices)
-- ================================================================
-- 1. PersonalIndex: All items from Auctionator.Database.db (Personal Scan tab)
-- 2. GuildIndex:    Only synced items with metadata (Guild Sync tab - stable)
-- 3. GuildIncoming: Staging buffer for new sync data (merged when ready)
-- ================================================================

local LatestIndex = {}
local PersonalIndex = {}
local GuildIndex = {}
local DataPackIndex = {}
local NeutralIndex = {}
local SnapshotIndex = {}
local SnapshotIndexKey = nil
local GuildIncomingBuffer = {}
local NeutralIncomingBuffer = {}

local LatestIndexReady = false
local PersonalIndexReady = false
local PersonalIndexBuilding = false
local GuildIndexReady = false
local DataPackIndexReady = false
local NeutralIndexReady = false
local IndexCallbacks = {}

-- Tracking for background resolution
local LatestPending = {}      -- { dbKey = itemID }
local PersonalPending = {}    -- { dbKey = itemID }
local PersonalDirtyKeys = {}
local personalRefreshScheduled = false
local browsePanels = setmetatable({}, { __mode = "k" })
local unresolvedBrowseEntries = {}
local GuildPending = {}       -- { dbKey = itemID }
local DataPackPending = {}    -- { dbKey = itemID }
local NeutralPending = {}     -- { dbKey = itemID }
local LatestTotal = 0
local LatestResolved = 0
local PersonalTotal = 0
local PersonalResolved = 0
local GuildTotal = 0
local GuildResolved = 0
local DataPackTotal = 0
local DataPackResolved = 0
local NeutralTotal = 0
local NeutralResolved = 0
local GuildIncomingCount = 0
local NeutralIncomingCount = 0
local GuildSyncActive = false
local NeutralSyncActive = false

-- Global trackers for cache rebuilding so they can be safely cancelled
local activeBuildTicker = nil
local activePeriodicRetry = nil
local activeRetryFrame = nil

-- ================================================================
-- RARITY HEX COLORS (for reconstructing item links from cache)
-- ================================================================
local RARITY_HEX = {
    [0] = "ff9d9d9d", -- Poor
    [1] = "ffffffff", -- Common
    [2] = "ff1eff00", -- Uncommon
    [3] = "ff0070dd", -- Rare
    [4] = "ffa335ee", -- Epic
    [5] = "ffff8000", -- Legendary
}

-- ================================================================
-- HELPER: Build an index entry from a dbKey + itemID
-- Returns the entry table or nil if item data isn't cached yet
-- Uses persistent ItemInfoCache to avoid repeated server requests
-- ================================================================
local function BuildIndexEntry(dbKey, itemID, data, sourceMode, allowFallback)
    local name, link, rarity, ilvl, minLevel, icon, classID, subClassID
    local isPlaceholder = false
    local suffixText
    local suffixID = type(dbKey) == "string" and tonumber(dbKey:match("^p:%d+:(%-?%d+)$")) or nil
    if type(dbKey) == "string" then
        suffixText = dbKey:match("^gr:%d+:(.+)$")
            or dbKey:match("^g:%d+:(.+)$")
            or dbKey:match("/([%w%s%-%'\"]+)$")
    end

    -- 1. Try in-memory / SavedVariables cache first (instant, zero lag)
    local cached
    if MarketSync.GetValidatedItemInfoCacheEntry then
        cached = MarketSync.GetValidatedItemInfoCacheEntry(itemID)
    elseif MarketSyncDB and type(MarketSyncDB.ItemInfoCache) == "table" then
        cached = MarketSyncDB.ItemInfoCache[itemID]
    end
    if cached and cached.n then
        name = cached.n
        rarity = cached.r or 1
        ilvl = cached.i or 0
        minLevel = cached.m or 0
        icon = cached.ic
        classID = cached.c
        subClassID = cached.s
        -- Reconstruct item link from cached data
        local hex = RARITY_HEX[rarity] or RARITY_HEX[1]
        link = "|c" .. hex .. "|Hitem:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
    else
        -- 2. Fall back to WoW API (may trigger server request)
        local itemType, itemSubType
        name, link, rarity, ilvl, minLevel, itemType, itemSubType, _, _, icon, _, classID, subClassID = MarketSync.GetItemInfo(itemID)
        if not name then
            if allowFallback then
                isPlaceholder = true
                name = "Item #" .. itemID
                rarity = 1
                ilvl = 0
                minLevel = 0
                icon = 134400
                classID = 0
                subClassID = 0
            else
                return nil
            end
        end

        -- 3. Write through to persistent cache for future sessions
        if MarketSyncDB and name and not isPlaceholder then
            if not MarketSyncDB.ItemInfoCache then
                MarketSyncDB.ItemInfoCache = {}
            end
            local cacheEntry = {
                n = name, r = rarity, i = ilvl, m = minLevel,
                ic = icon, c = classID, s = subClassID,
            }
            if not MarketSync.IsValidItemInfoCacheEntry or MarketSync.IsValidItemInfoCacheEntry(cacheEntry) then
                MarketSyncDB.ItemInfoCache[itemID] = cacheEntry
            end
        end
    end

    if not name then return nil end

    local itemLinkString = "item:" .. itemID
    if suffixID and suffixID ~= 0 then
        itemLinkString = string.format("item:%d:0:0:0:0:0:%d:0", itemID, suffixID)
        local variantName, variantLink, variantRarity, variantIlvl = MarketSync.GetItemInfo(itemLinkString)
        if variantName then
            name = variantName
            link = variantLink or link
            rarity = variantRarity or rarity
            ilvl = variantIlvl or ilvl
        else
            suffixText = "Variant " .. tostring(suffixID)
        end
    end

    -- Keep random-enchant suffixes searchable/visible in Personal+Guild browse results.
    local displayName = name
    if suffixText and suffixText ~= "" then
        local lowerName = name:lower()
        local lowerSuffix = suffixText:lower()
        if not lowerName:find(lowerSuffix, 1, true) then
            displayName = name .. " " .. suffixText
        end
    end

    local hex = RARITY_HEX[rarity] or RARITY_HEX[1]
    local validLink = link
    if not isPlaceholder and (not validLink or not validLink:find("item:%d+:")) then
        local _, realLink = MarketSync.GetItemInfo(itemID)
        if realLink and realLink:find("item:%d+:") then
            validLink = realLink
        end
    end
    if not validLink then
        local fullItemString = suffixID and suffixID ~= 0
            and string.format("item:%d:0:0:0:0:0:%d:0:0:0:0:0:0", itemID, suffixID)
            or string.format("item:%d:0:0:0:0:0:0:0:0:0:0:0:0", itemID)
        validLink = "|c" .. hex .. "|H" .. fullItemString .. "|h[" .. displayName .. "]|h|r"
    end
    link = validLink

    local price = 0
    local dbDay = MarketSync.GetCurrentScanDay()
    if type(data) == "table" then
        price = data.m or 0
        dbDay = data.d or dbDay
    elseif type(data) == "number" then
        price = data
    end

    local age = nil
    local meta = MarketSyncDB and MarketSync.GetRealmDB().ItemMetadata and MarketSync.GetRealmDB().ItemMetadata[dbKey]
    local source = "Personal"
    local exactTime = nil

    local dayStr = tostring(dbDay)
    if sourceMode == "personal" then
        -- Offline mirrored personal data { m, d }
        local currentDay = MarketSync.GetCurrentScanDay()
        age = math.max(0, currentDay - dbDay)
        if age == 0 or (type(age) == "number" and age < 1) then
            exactTime = tonumber(data.observedAt)
        end
    elseif sourceMode == "datapack" then
        local currentDay = MarketSync.GetCurrentScanDay()
        age = math.max(0, currentDay - dbDay)
        source = "DataPack"
        exactTime = (type(data) == "table" and (tonumber(data.observedAt) or tonumber(data.t))) or nil
    elseif sourceMode == "neutral" then
        local currentDay = MarketSync.GetCurrentScanDay()
        age = math.max(0, currentDay - dbDay)
        local nmeta = MarketSyncDB and MarketSync.GetRealmDB().NeutralMeta and MarketSync.GetRealmDB().NeutralMeta[dbKey]
        source = (nmeta and nmeta.source) or "Neutral"
        exactTime = (nmeta and nmeta.time) or (MarketSyncDB and MarketSync.GetRealmDB().NeutralScanTime)
    else
        -- Active live database (Provider or Auctionator)
        age = MarketSync.GetAuctionAge and MarketSync.GetAuctionAge(dbKey)
        if age == nil and Auctionator and Auctionator.Database and Auctionator.Database.GetPriceAge then
            age = Auctionator.Database:GetPriceAge(dbKey)
        end
        
        -- Check snapshot from Provider if available
        if MarketSync.Provider and MarketSync.Provider.GetSnapshot then
            local snap = MarketSync.Provider.GetSnapshot(dbKey)
            if snap and snap.seenAt then
                exactTime = snap.seenAt
            end
        end

        local isToday = (age == 0) or (type(age) == "number" and (age < 1 or math.floor(age) == 0))

        -- Determine source by checking per-day metadata first
        if meta and meta.days and meta.days[dayStr] then
            source = meta.days[dayStr].source or "Guild"
            exactTime = meta.days[dayStr].time or exactTime
        elseif isToday then
            -- If it was scanned today and we have NO sync metadata for today, it must be personal.
            source = "Personal"
            if not exactTime and MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime then
                exactTime = MarketSync.GetRealmDB().PersonalScanTime
            end
        elseif meta then
            -- Fallback for older sync data that might only have top-level metadata
            source = meta.lastSource or meta.source or "Guild"
            exactTime = meta.lastTime or meta.time or exactTime
        end
        
        -- Final override for Personal scans today even if meta exists (belt and suspenders)
        if source == "Personal" and isToday and MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime then
            if not exactTime then
                exactTime = MarketSync.GetRealmDB().PersonalScanTime
            end
        end
    end

    if sourceMode ~= "neutral" then
        local record = type(data) == "table" and data or {}
        if record.src == "DataPack" then
            source = "DataPack"
            exactTime = tonumber(record.t) or tonumber(record.observedAt) or exactTime
        elseif MarketSync.IsWebAuctionRecord and MarketSync.IsWebAuctionRecord(record) then
            source = "DataPack"
            exactTime = tonumber(record.t) or exactTime
        elseif sourceMode ~= "personal" and record.source then
            source = record.source
        end
        exactTime = tonumber(record.observedAt)
            or (record.latestBucket and MarketSync.ScanDayToTimestamp
                and (MarketSync.ScanDayToTimestamp(math.floor(record.latestBucket / 48)) + record.latestBucket % 48 * 1800))
            or exactTime
        if exactTime then age = math.max(0, time() - exactTime) / 86400 end
    end
    local entry = {
        name = displayName, nameLower = displayName:lower(), link = link,
        rarity = rarity or 1, ilvl = ilvl or 0, minLevel = minLevel or 0,
        icon = icon, classID = classID, subClassID = subClassID,
        price = price, age = age, dbKey = dbKey, itemID = itemID,
        source = source, exactTime = exactTime,
        hasMeta = (source ~= "Personal"),
        isPlaceholder = isPlaceholder,
    }
    if isPlaceholder then
        local entries = unresolvedBrowseEntries[itemID]
        if not entries then
            entries = setmetatable({}, { __mode = "k" })
            unresolvedBrowseEntries[itemID] = entries
        end
        entries[entry] = true
    end
    return entry
end

-- LATE BROWSE ITEM RESOLUTION: placeholders remain eligible after bulk retries stop.
-- Only process IDs reported loaded or explicitly hovered, never the whole DB.
local loadedBrowseIDs = {}
local browseResolveScheduled = false
local function ScheduleBrowseItemResolution(itemID)
    itemID = tonumber(itemID)
    if not itemID or not unresolvedBrowseEntries[itemID] then return end
    loadedBrowseIDs[itemID] = true
    if browseResolveScheduled or not C_Timer or not C_Timer.After then return end
    browseResolveScheduled = true
    local function Step()
        local checked, changed = 0, false
        while checked < 20 do
            local id = next(loadedBrowseIDs)
            if not id then break end
            local entries = unresolvedBrowseEntries[id]
            local entry = entries and next(entries)
            if not entry then
                loadedBrowseIDs[id] = nil
                unresolvedBrowseEntries[id] = nil
            else
                entries[entry] = nil
                checked = checked + 1
                local resolved = BuildIndexEntry(entry.dbKey, id, { m = entry.price }, "personal", false)
                if resolved then
                    -- Mutate in place so index and existing result references both update.
                    for _, key in ipairs({ "name", "nameLower", "link", "rarity", "ilvl",
                        "minLevel", "icon", "classID", "subClassID" }) do
                        entry[key] = resolved[key]
                    end
                    entry.isPlaceholder = false
                    changed = true
                else
                    -- No immediate retry loop for invalid or still-unavailable IDs.
                    entries[entry] = true
                    loadedBrowseIDs[id] = nil
                end
            end
        end
        if changed then
            for panel in pairs(browsePanels) do
                if panel:IsShown() and panel.UpdateResults then panel:UpdateResults() end
            end
        end
        if next(loadedBrowseIDs) then C_Timer.After(0.1, Step)
        else browseResolveScheduled = false end
    end
    C_Timer.After(0.1, Step)
end

local browseItemEvents = CreateFrame("Frame")
browseItemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
pcall(browseItemEvents.RegisterEvent, browseItemEvents, "ITEM_DATA_LOAD_RESULT")
browseItemEvents:SetScript("OnEvent", function(_, _, itemID, success)
    if success ~= false then ScheduleBrowseItemResolution(itemID) end
end)

-- ================================================================
-- PARSE ITEM ID from a dbKey
-- ================================================================
local function ParseItemID(dbKey)
    if MarketSync.ParseItemIDFromDBKey then
        return MarketSync.ParseItemIDFromDBKey(dbKey)
    end
    return tonumber((tostring(dbKey)):match("(%d+)"))
end

-- ================================================================
local function IsPackRecord(record)
    if type(record) ~= "table" then return false end
    if record.src == "DataPack" then return true end
    if MarketSync.IsWebAuctionRecord and MarketSync.IsWebAuctionRecord(record) then return true end
    return false
end

local function RecordTimestamp(record)
    if type(record) == "number" then return 0 end
    if type(record) ~= "table" then return -1 end
    local obs = tonumber(record.observedAt) or tonumber(record.t)
    if obs and obs > 0 then return obs end
    local day = tonumber(record.d) or 0
    return day * 86400
end

local function SelectLatestSourceRecord(pData, gData, packEntry)
    local bestData, bestMode, bestStamp = nil, nil, -1
    if pData and ((type(pData) == "table" and (tonumber(pData.m) or 0) > 0) or (type(pData) == "number" and pData > 0)) then
        bestData = pData
        bestMode = "personal"
        bestStamp = RecordTimestamp(pData)
    end
    if gData then
        local gPrice = (type(gData) == "table" and tonumber(gData.m)) or (gData.latest and gData.latest.minUnitPrice) or 0
        if gPrice and gPrice > 0 then
            local gIsPack = IsPackRecord(gData)
            if not gIsPack or (MarketSyncDB and MarketSyncDB.PassiveSync ~= false) or gIsPack then
                if gIsPack or not MarketSyncDB or MarketSyncDB.PassiveSync ~= false then
                    local gStamp = RecordTimestamp(gData)
                    if not bestData or (not gIsPack and gStamp > bestStamp) or (gIsPack and gStamp > bestStamp + 86400) then
                        bestData = gData
                        bestMode = gIsPack and "datapack" or "guild"
                        bestStamp = gStamp
                    end
                end
            end
        end
    end
    if not bestData and packEntry then
        local pPrice = type(packEntry) == "table" and tonumber(packEntry.m) or tonumber(packEntry)
        if pPrice and pPrice > 0 then
            bestData = type(packEntry) == "table" and packEntry or { m = pPrice, src = "DataPack" }
            bestMode = "datapack"
        end
    end
    return bestData, bestMode
end

function MarketSync.ReleaseSecondaryBrowseCaches(keepSource)
    if not MarketSyncDB or not MarketSyncDB.LowRamMode or MarketSyncDB.KeepSecondaryIndexesLoaded then
        return
    end
    if keepSource ~= "snapshot" then
        wipe(SnapshotIndex)
        SnapshotIndexKey = nil
    end
    if keepSource ~= "personal" then
        PersonalIndexReady = false
        wipe(PersonalIndex)
        wipe(PersonalPending)
        PersonalTotal = 0
        PersonalResolved = 0
    end
    if keepSource ~= "guild" then
        GuildIndexReady = false
        wipe(GuildIndex)
        wipe(GuildPending)
        GuildTotal = 0
        GuildResolved = 0
    end
    if keepSource ~= "datapack" then
        DataPackIndexReady = false
        wipe(DataPackIndex)
        wipe(DataPackPending)
        DataPackTotal = 0
        DataPackResolved = 0
    end
    if keepSource ~= "neutral" then
        NeutralIndexReady = false
        wipe(NeutralIndex)
        wipe(NeutralPending)
        NeutralTotal = 0
        NeutralResolved = 0
    end
end

function MarketSync.InvalidateIndexCache()
    wipe(unresolvedBrowseEntries)
    wipe(loadedBrowseIDs)
    LatestIndexReady = false
    PersonalIndexReady = false
    GuildIndexReady = false
    DataPackIndexReady = false
    NeutralIndexReady = false
    PersonalIndexBuilding = false
    SnapshotIndexKey = nil
    wipe(LatestIndex)
    wipe(PersonalIndex)
    wipe(GuildIndex)
    wipe(DataPackIndex)
    wipe(NeutralIndex)
    wipe(SnapshotIndex)
    wipe(GuildIncomingBuffer)
    wipe(NeutralIncomingBuffer)
    wipe(LatestPending)
    wipe(PersonalPending)
    wipe(PersonalDirtyKeys)
    personalRefreshScheduled = false
    wipe(GuildPending)
    wipe(DataPackPending)
    wipe(NeutralPending)
    LatestTotal = 0
    PersonalTotal = 0
    GuildTotal = 0
    DataPackTotal = 0
    NeutralTotal = 0
    LatestResolved = 0
    PersonalResolved = 0
    GuildResolved = 0
    DataPackResolved = 0
    NeutralResolved = 0
    GuildIncomingCount = 0
    NeutralIncomingCount = 0
    GuildSyncActive = false
    NeutralSyncActive = false

    -- Cancel any active background build processes
    if activeBuildTicker then activeBuildTicker:Cancel(); activeBuildTicker = nil end
    if activePeriodicRetry then activePeriodicRetry:Cancel(); activePeriodicRetry = nil end
    if activeRetryFrame then
        activeRetryFrame:UnregisterAllEvents()
        activeRetryFrame:SetScript("OnEvent", nil)
        activeRetryFrame = nil
    end
end

-- Auctionator provides the exact keys changed by a scan. Refresh only those
-- personal rows; guild and neutral indices are independent of that source.
local function ProcessPersonalDirtyKeys()
    if PersonalIndexBuilding then
        personalRefreshScheduled = false
        return
    end
    local store = MarketSync.GetRealmDB() and MarketSync.GetRealmDB().PersonalData or {}
    local gStore = MarketSync.GetRealmDB() and MarketSync.GetRealmDB().GuildData or {}
    local processed = 0
    while processed < 50 do
        local dbKey = next(PersonalDirtyKeys)
        if not dbKey then break end
        PersonalDirtyKeys[dbKey] = nil
        local itemID = ParseItemID(dbKey)
        local data = store[dbKey]
        if PersonalIndexReady then
            local wasKnown = PersonalIndex[dbKey] ~= nil or PersonalPending[dbKey] ~= nil
            local wasResolved = PersonalIndex[dbKey] ~= nil
            local entry = data and itemID and BuildIndexEntry(dbKey, itemID, data, "personal") or nil
            PersonalIndex[dbKey] = entry
            PersonalPending[dbKey] = data and itemID and not entry and itemID or nil
            local isKnown = PersonalIndex[dbKey] ~= nil or PersonalPending[dbKey] ~= nil
            if isKnown ~= wasKnown then PersonalTotal = PersonalTotal + (isKnown and 1 or -1) end
            if (entry ~= nil) ~= wasResolved then PersonalResolved = PersonalResolved + (entry and 1 or -1) end
        end
        if LatestIndexReady then
            local bestData, bestMode = SelectLatestSourceRecord(data, gStore[dbKey], nil)
            local wasKnown = LatestIndex[dbKey] ~= nil or LatestPending[dbKey] ~= nil
            local wasResolved = LatestIndex[dbKey] ~= nil
            local lEntry = bestData and itemID and BuildIndexEntry(dbKey, itemID, bestData, bestMode or "personal") or nil
            LatestIndex[dbKey] = lEntry
            LatestPending[dbKey] = bestData and itemID and not lEntry and itemID or nil
            local isKnown = LatestIndex[dbKey] ~= nil or LatestPending[dbKey] ~= nil
            if isKnown ~= wasKnown then LatestTotal = LatestTotal + (isKnown and 1 or -1) end
            if (lEntry ~= nil) ~= wasResolved then LatestResolved = LatestResolved + (lEntry and 1 or -1) end
        end
        processed = processed + 1
    end
    if next(PersonalDirtyKeys) then
        if C_Timer and C_Timer.After then C_Timer.After(0, ProcessPersonalDirtyKeys)
        else ProcessPersonalDirtyKeys() end
        return
    end
    personalRefreshScheduled = false
    for panel in pairs(browsePanels) do
        if (panel.dataSource == "personal" or panel.dataSource == "main")
            and panel.IsShown and panel:IsShown() and panel.RunSearch then
            panel:RunSearch()
        end
    end
end

function MarketSync.RefreshPersonalBrowseIndexKeys(keys)
    if type(keys) ~= "table" then return false end
    if not PersonalIndexReady and not LatestIndexReady and not PersonalIndexBuilding then return true end
    for dbKey in pairs(keys) do PersonalDirtyKeys[dbKey] = true end
    if (PersonalIndexReady or LatestIndexReady) and not PersonalIndexBuilding and not personalRefreshScheduled and next(PersonalDirtyKeys) then
        personalRefreshScheduled = true
        if C_Timer and C_Timer.After then C_Timer.After(0, ProcessPersonalDirtyKeys)
        else ProcessPersonalDirtyKeys() end
    end
    return true
end

-- ================================================================
-- CACHE SUSPENSION LOGIC
-- ================================================================
function MarketSync.CanBuildCache()
    if not MarketSyncDB then return true end
    if not MarketSyncDB.AllowCacheInCombat and InCombatLockdown and InCombatLockdown() then return false end

    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance then
            if instanceType == "raid" and not MarketSyncDB.AllowCacheInRaid then return false end
            if instanceType == "party" and not MarketSyncDB.AllowCacheInDungeon then return false end
            if instanceType == "pvp" and not MarketSyncDB.AllowCacheInPvP then return false end
            if instanceType == "arena" and not MarketSyncDB.AllowCacheInArena then return false end
        end
    end
    return true
end

-- ================================================================
-- BUILD ALL INDICES (runs once, populates Personal + Guild)
-- ================================================================
local function BuildSearchIndex(callback)
    local isLowRam = MarketSyncDB and MarketSyncDB.LowRamMode
    local keepLatest = not isLowRam or (MarketSyncDB and MarketSyncDB.PartialLowRamKeepLatest ~= false)
    local wantLatest = not LatestIndexReady and (keepLatest or MarketSync.ForceLatest)
    local wantPersonal = not PersonalIndexReady and (not isLowRam or MarketSync.ForcePersonal)
    local wantGuild = not GuildIndexReady and (not isLowRam or MarketSync.ForceGuild)
    local wantDataPack = not DataPackIndexReady and (not isLowRam or MarketSync.ForceDataPack)
    local wantNeutral = not NeutralIndexReady and (not isLowRam or MarketSync.ForceNeutral)

    if not wantLatest and not wantPersonal and not wantGuild and not wantDataPack and not wantNeutral then
        if callback then callback() end
        return
    end
    if callback then table.insert(IndexCallbacks, callback) end
    if PersonalIndexBuilding then return end
    PersonalIndexBuilding = true

    -- Read cache speed preset
    local speedLevel = (MarketSyncDB and MarketSyncDB.CacheSpeed) or 2
    local preset = MarketSync.CacheSpeedPresets[speedLevel] or MarketSync.CacheSpeedPresets[2]

    if wantLatest then LatestTotal = 0; LatestResolved = 0 end
    if wantPersonal then PersonalTotal = 0; PersonalResolved = 0 end
    if wantGuild then GuildTotal = 0; GuildResolved = 0 end
    if wantDataPack then DataPackTotal = 0; DataPackResolved = 0 end
    if wantNeutral then NeutralTotal = 0; NeutralResolved = 0 end

    local co = coroutine.create(function()
        local realmDB = MarketSync.GetRealmDB()
        local pStore = MarketSyncDB and realmDB and realmDB.PersonalData
        local liveStore = (realmDB and realmDB.GuildData)
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)
        local directPackPrices = nil
        if _G.MarketSyncData and type(_G.MarketSyncData.GetCurrentMarketPrices) == "function" then
            local okP, prices = pcall(_G.MarketSyncData.GetCurrentMarketPrices)
            if okP and type(prices) == "table" then directPackPrices = prices end
        end

        local nStore = realmDB and realmDB.NeutralData
        if not liveStore and not pStore and not directPackPrices and not nStore then
            if wantLatest then LatestIndexReady = true; MarketSync.ForceLatest = nil end
            if wantPersonal then PersonalIndexReady = true; MarketSync.ForcePersonal = nil end
            if wantGuild then GuildIndexReady = true; MarketSync.ForceGuild = nil end
            if wantDataPack then DataPackIndexReady = true; MarketSync.ForceDataPack = nil end
            if wantNeutral then NeutralIndexReady = true; MarketSync.ForceNeutral = nil end
            PersonalIndexBuilding = false
            for _, cb in ipairs(IndexCallbacks) do cb() end
            wipe(IndexCallbacks)
            return
        end
        local count = 0
        local totalProcessed = 0
        local currentYieldLimit = 5 -- Start very slow to let UI render first frame instantly
        if MarketSync.LogCacheEvent then
            MarketSync.LogCacheEvent("|cff00ff00[Start]|r Index build started.")
        end

        -- 0. BUILD UNIFIED 'LATEST' MAIN AH CACHE (Single deduplicated hot index)
        if wantLatest then
            local visited = {}
            local function AddLatestKey(dbKey, pData, gData, packEntry)
                if visited[dbKey] then return end
                visited[dbKey] = true
                local bestData, bestMode = SelectLatestSourceRecord(pData, gData, packEntry)
                if not bestData then return end
                local itemID = ParseItemID(dbKey) or (type(bestData) == "table" and bestData.key and bestData.key.itemID)
                if itemID then
                    LatestTotal = LatestTotal + 1
                    local entry = BuildIndexEntry(dbKey, itemID, bestData, bestMode or "personal")
                    if entry then
                        LatestIndex[dbKey] = entry
                        LatestResolved = LatestResolved + 1
                    else
                        LatestPending[dbKey] = itemID
                    end
                end
                count = count + 1
                totalProcessed = totalProcessed + 1
                if count >= currentYieldLimit then
                    coroutine.yield()
                    count = 0
                    currentYieldLimit = preset.yieldEvery
                end
            end
            for dbKey, pData in pairs(pStore or {}) do
                AddLatestKey(dbKey, pData, liveStore and liveStore[dbKey], directPackPrices and (directPackPrices[dbKey] or directPackPrices[tonumber(dbKey)]))
            end
            for dbKey, gData in pairs(liveStore or {}) do
                AddLatestKey(dbKey, pStore and pStore[dbKey], gData, directPackPrices and (directPackPrices[dbKey] or directPackPrices[tonumber(dbKey)]))
            end
            for rawKey, packEntry in pairs(directPackPrices or {}) do
                local dbKey = tostring(rawKey)
                AddLatestKey(dbKey, pStore and pStore[dbKey], liveStore and liveStore[dbKey], packEntry)
            end
            LatestIndexReady = true
            MarketSync.ForceLatest = nil
        end

        -- 1. BUILD PERSONAL CACHE
        if pStore then
            if isLowRam and not PersonalIndexReady and not MarketSync.ForcePersonal then
                if MarketSync.LogCacheEvent then
                    MarketSync.LogCacheEvent("|cffffff00[Personal]|r On-Demand enabled (Low RAM). Skipping Personal index build.")
                end
            elseif not PersonalIndexReady then
                for dbKey, data in pairs(pStore) do
                    local itemID = ParseItemID(dbKey)
                    if itemID then
                        PersonalTotal = PersonalTotal + 1
                        local entry = BuildIndexEntry(dbKey, itemID, data, "personal")
                        if entry then
                            PersonalIndex[dbKey] = entry
                            PersonalResolved = PersonalResolved + 1
                        else
                            PersonalPending[dbKey] = itemID
                        end
                    end
                    count = count + 1
                    totalProcessed = totalProcessed + 1
                    if count >= currentYieldLimit then
                        coroutine.yield()
                        count = 0
                        currentYieldLimit = preset.yieldEvery
                    end
                end
                PersonalIndexReady = true
                MarketSync.ForcePersonal = nil
            end
        elseif wantPersonal then
            PersonalIndexReady = true
            MarketSync.ForcePersonal = nil
        end

        -- 2. BUILD GUILD SYNC CACHE (Pure guild-synced quotes)
        if isLowRam and not GuildIndexReady and not MarketSync.ForceGuild then
            if MarketSync.LogCacheEvent then
                MarketSync.LogCacheEvent("|cff88aaff[Guild]|r On-Demand enabled (Low RAM). Skipping Guild index build.")
            end
        elseif liveStore and not GuildIndexReady then
            for dbKey, data in pairs(liveStore) do
                if not IsPackRecord(data) then
                    local price = (type(data) == "table" and data.m) or (data and data.latest and data.latest.minUnitPrice)
                    if price and price > 0 then
                        local itemID = ParseItemID(dbKey) or (data.key and data.key.itemID)
                        if itemID then
                            GuildTotal = GuildTotal + 1
                            local entry = BuildIndexEntry(dbKey, itemID, data, "guild")
                            if entry then
                                GuildIndex[dbKey] = entry
                                GuildResolved = GuildResolved + 1
                            else
                                GuildPending[dbKey] = itemID
                            end
                        end
                    end
                end
                count = count + 1
                totalProcessed = totalProcessed + 1
                if count >= currentYieldLimit then
                    coroutine.yield()
                    count = 0
                    currentYieldLimit = preset.yieldEvery
                end
            end
            GuildIndexReady = true
            MarketSync.ForceGuild = nil
        elseif wantGuild then
            GuildIndexReady = true
            MarketSync.ForceGuild = nil
        end

        -- 2b. BUILD DATA PACK CACHE (On-Demand daily compiled pack quotes)
        if wantDataPack and not DataPackIndexReady then
            local seenPack = {}
            for dbKey, data in pairs(liveStore or {}) do
                if IsPackRecord(data) then
                    seenPack[dbKey] = true
                    local price = tonumber(data.m) or 0
                    local itemID = ParseItemID(dbKey)
                    if price > 0 and itemID then
                        DataPackTotal = DataPackTotal + 1
                        local entry = BuildIndexEntry(dbKey, itemID, data, "datapack")
                        if entry then
                            DataPackIndex[dbKey] = entry
                            DataPackResolved = DataPackResolved + 1
                        else
                            DataPackPending[dbKey] = itemID
                        end
                    end
                    count = count + 1
                    if count >= currentYieldLimit then
                        coroutine.yield()
                        count = 0
                        currentYieldLimit = preset.yieldEvery
                    end
                end
            end
            for rawKey, packEntry in pairs(directPackPrices or {}) do
                local dbKey = tostring(rawKey)
                if not seenPack[dbKey] then
                    local pPrice = type(packEntry) == "table" and tonumber(packEntry.m) or tonumber(packEntry)
                    local itemID = ParseItemID(dbKey)
                    if pPrice and pPrice > 0 and itemID then
                        DataPackTotal = DataPackTotal + 1
                        local norm = type(packEntry) == "table" and packEntry or { m = pPrice, src = "DataPack" }
                        local entry = BuildIndexEntry(dbKey, itemID, norm, "datapack")
                        if entry then
                            DataPackIndex[dbKey] = entry
                            DataPackResolved = DataPackResolved + 1
                        else
                            DataPackPending[dbKey] = itemID
                        end
                    end
                    count = count + 1
                    if count >= currentYieldLimit then
                        coroutine.yield()
                        count = 0
                        currentYieldLimit = preset.yieldEvery
                    end
                end
            end
            DataPackIndexReady = true
            MarketSync.ForceDataPack = nil
        end

        -- 3. BUILD NEUTRAL CACHE
        if MarketSyncDB.LowRamMode and not NeutralIndexReady and not MarketSync.ForceNeutral then
            if MarketSync.LogCacheEvent then
                MarketSync.LogCacheEvent("|cff00ccff[Neutral]|r On-Demand enabled (Low RAM). Skipping Neutral index build.")
            end
        elseif not NeutralIndexReady then
            if MarketSyncDB and MarketSync.GetRealmDB().NeutralData then
                for dbKey, data in pairs(MarketSync.GetRealmDB().NeutralData) do
                    local itemID = ParseItemID(dbKey)
                    if itemID then
                        NeutralTotal = NeutralTotal + 1
                        local entry = BuildIndexEntry(dbKey, itemID, data, "neutral")
                        if entry then
                            NeutralIndex[dbKey] = entry
                            NeutralResolved = NeutralResolved + 1
                        else
                            NeutralPending[dbKey] = itemID
                        end
                    end
                    count = count + 1
                    totalProcessed = totalProcessed + 1
                    if count >= currentYieldLimit then
                        if MarketSync.LogCacheEvent then
                            MarketSync.LogCacheEvent(string.format("|cff00ccff[Neutral]|r Processed %d entries so far (%d resolved).", totalProcessed, NeutralResolved))
                        end
                        coroutine.yield()
                        count = 0
                        currentYieldLimit = preset.yieldEvery
                    end
                end
            end
            NeutralIndexReady = true
            MarketSync.ForceNeutral = nil
        end

        -- Final pass complete
        PersonalIndexBuilding = false
        if (PersonalIndexReady or LatestIndexReady) and next(PersonalDirtyKeys) and not personalRefreshScheduled then
            personalRefreshScheduled = true
            C_Timer.After(0, ProcessPersonalDirtyKeys)
        end
        local pPending, gPending, nPending = 0, 0, 0
        for _ in pairs(PersonalPending) do pPending = pPending + 1 end
        for _ in pairs(GuildPending) do gPending = gPending + 1 end
        for _ in pairs(NeutralPending) do nPending = nPending + 1 end
        if MarketSync.LogCacheEvent then
            if pPending + gPending + nPending > 0 then
                MarketSync.LogCacheEvent(string.format("|cff00ff00[Pass 1 Done]|r Personal: %d/%d (%d pending). Guild: %d/%d (%d pending). Neutral: %d/%d (%d pending).", PersonalResolved, PersonalTotal, pPending, GuildResolved, GuildTotal, gPending, NeutralResolved, NeutralTotal, nPending))
            else
                MarketSync.LogCacheEvent(string.format("|cff00ff00[Done]|r Index build complete. Personal: %d items. Guild: %d items. Neutral: %d items.", PersonalResolved, GuildResolved, NeutralResolved))
            end
        end
        for _, cb in ipairs(IndexCallbacks) do cb() end
        wipe(IndexCallbacks)
    end)

    -- Build ticker runs fast (0.01s) so items resolve quickly during first pass.
    -- CPU load per tick is controlled by preset.yieldEvery, not ticker speed.
    activeBuildTicker = C_Timer.NewTicker(0.01, function()
        if not MarketSync.CanBuildCache() then return end
        if coroutine.status(co) == "dead" then 
            if activeBuildTicker then activeBuildTicker:Cancel() end
            activeBuildTicker = nil
            return 
        end
        local ok, err = coroutine.resume(co)
        if not ok then 
            print("|cffff0000[MarketSync] Index error:|r", err)
            if activeBuildTicker then activeBuildTicker:Cancel() end
            activeBuildTicker = nil 
        end
    end)

    -- ================================================================
    -- BACKGROUND RETRY: Resolve pending items from both caches
    -- ================================================================
    -- BACKGROUND RETRY: Resolve pending items from all caches
    -- ================================================================
    if activeRetryFrame then activeRetryFrame:UnregisterAllEvents() end
    activeRetryFrame = CreateFrame("Frame")
    local retryBatchSize = preset.batchSize
    local retryTimer = nil
    local pendingRetryAttempts = {}

    local function ProcessPendingBatch(forceFallback)
        local processed = 0
        local latestRemove = {}
        local personalRemove = {}
        local guildRemove = {}
        local packRemove = {}
        local neutralRemove = {}
        local pStore = MarketSyncDB and MarketSync.GetRealmDB().PersonalData
        local nStore = MarketSyncDB and MarketSync.GetRealmDB().NeutralData
        local gStore = MarketSync.GetRealmDB().GuildData
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)

        -- Resolve Latest pending
        for dbKey, itemID in pairs(LatestPending) do
            if processed >= retryBatchSize then break end
            local bestData, bestMode = SelectLatestSourceRecord(pStore and pStore[dbKey], gStore and gStore[dbKey], nil)
            if bestData then
                pendingRetryAttempts[dbKey] = (pendingRetryAttempts[dbKey] or 0) + 1
                local allowFallback = forceFallback or (pendingRetryAttempts[dbKey] > 8)
                local entry = BuildIndexEntry(dbKey, itemID, bestData, bestMode or "personal", allowFallback)
                if entry then
                    LatestIndex[dbKey] = entry
                    LatestResolved = LatestResolved + 1
                    table.insert(latestRemove, dbKey)
                end
            else
                table.insert(latestRemove, dbKey)
            end
            processed = processed + 1
        end

        -- Resolve DataPack pending
        for dbKey, itemID in pairs(DataPackPending) do
            if processed >= retryBatchSize then break end
            local data = gStore and gStore[dbKey]
            if data then
                pendingRetryAttempts[dbKey] = (pendingRetryAttempts[dbKey] or 0) + 1
                local allowFallback = forceFallback or (pendingRetryAttempts[dbKey] > 8)
                local entry = BuildIndexEntry(dbKey, itemID, data, "datapack", allowFallback)
                if entry then
                    DataPackIndex[dbKey] = entry
                    DataPackResolved = DataPackResolved + 1
                    table.insert(packRemove, dbKey)
                end
            else
                table.insert(packRemove, dbKey)
            end
            processed = processed + 1
        end

        -- Resolve Personal pending
        for dbKey, itemID in pairs(PersonalPending) do
            if processed >= retryBatchSize then break end
            local data = (pStore and pStore[dbKey]) or (gStore and gStore[dbKey])
            if data then
                pendingRetryAttempts[dbKey] = (pendingRetryAttempts[dbKey] or 0) + 1
                local allowFallback = forceFallback or (pendingRetryAttempts[dbKey] > 8)
                local entry = BuildIndexEntry(dbKey, itemID, data, "personal", allowFallback)
                if entry then
                    PersonalIndex[dbKey] = entry
                    PersonalResolved = PersonalResolved + 1
                    table.insert(personalRemove, dbKey)

                    -- Also resolve guild if pending
                    if GuildPending[dbKey] then
                        GuildIndex[dbKey] = entry
                        GuildResolved = GuildResolved + 1
                        table.insert(guildRemove, dbKey)
                    end
                end
            else
                table.insert(personalRemove, dbKey)
            end
            processed = processed + 1
        end

        -- Resolve Guild pending (for items not in Personal)
        for dbKey, itemID in pairs(GuildPending) do
            if processed >= retryBatchSize then break end
            if not PersonalPending[dbKey] then -- Skip if already checked above
                local data = (gStore and gStore[dbKey]) or (pStore and pStore[dbKey])
                if data then
                    pendingRetryAttempts[dbKey] = (pendingRetryAttempts[dbKey] or 0) + 1
                    local allowFallback = forceFallback or (pendingRetryAttempts[dbKey] > 8)
                    local entry = BuildIndexEntry(dbKey, itemID, data, "guild", allowFallback)
                    if entry then
                        GuildIndex[dbKey] = entry
                        GuildResolved = GuildResolved + 1
                        table.insert(guildRemove, dbKey)
                    end
                else
                    table.insert(guildRemove, dbKey)
                end
                processed = processed + 1
            end
        end

        -- Resolve Neutral pending from isolated neutral store
        for dbKey, itemID in pairs(NeutralPending) do
            if processed >= retryBatchSize then break end
            local data = nStore and nStore[dbKey]
            if data then
                pendingRetryAttempts[dbKey] = (pendingRetryAttempts[dbKey] or 0) + 1
                local allowFallback = forceFallback or (pendingRetryAttempts[dbKey] > 8)
                local entry = BuildIndexEntry(dbKey, itemID, data, "neutral", allowFallback)
                if entry then
                    NeutralIndex[dbKey] = entry
                    NeutralResolved = NeutralResolved + 1
                    table.insert(neutralRemove, dbKey)
                end
            else
                table.insert(neutralRemove, dbKey)
            end
            processed = processed + 1
        end

        for _, key in ipairs(latestRemove) do LatestPending[key] = nil; pendingRetryAttempts[key] = nil end
        for _, key in ipairs(personalRemove) do PersonalPending[key] = nil; pendingRetryAttempts[key] = nil end
        for _, key in ipairs(guildRemove) do GuildPending[key] = nil; pendingRetryAttempts[key] = nil end
        for _, key in ipairs(packRemove) do DataPackPending[key] = nil; pendingRetryAttempts[key] = nil end
        for _, key in ipairs(neutralRemove) do NeutralPending[key] = nil; pendingRetryAttempts[key] = nil end

        return processed, #latestRemove + #personalRemove + #guildRemove + #packRemove + #neutralRemove
    end

    local resolveDelay = preset.resolveDelay or 0.5
    activeRetryFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    activeRetryFrame:SetScript("OnEvent", function(self, event, itemID, success)
        if not MarketSync.CanBuildCache() then return end
        if retryTimer then return end
        retryTimer = C_Timer.NewTimer(resolveDelay, function()
            retryTimer = nil
            if not MarketSync.CanBuildCache() then return end
            local checked, resolved = ProcessPendingBatch(false)

            if resolved > 0 and MarketSync.LogCacheEvent then
                MarketSync.LogCacheEvent(string.format("|cff88aaff[Async Resolve]|r Fetched %d items from WoW server.", resolved))
            end

            -- Check if all items are resolved
            local pRemaining, gRemaining, nRemaining = 0, 0, 0
            for _ in pairs(LatestPending) do pRemaining = pRemaining + 1 end
            for _ in pairs(PersonalPending) do pRemaining = pRemaining + 1 end
            for _ in pairs(GuildPending) do gRemaining = gRemaining + 1 end
            for _ in pairs(DataPackPending) do gRemaining = gRemaining + 1 end
            for _ in pairs(NeutralPending) do nRemaining = nRemaining + 1 end
            if pRemaining == 0 and gRemaining == 0 and nRemaining == 0 then
                self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                if MarketSyncDB and MarketSyncDB.DebugMode then
                    print("|cFF00FF00[MarketSync]|r Index complete: Personal " .. PersonalResolved .. "/" .. PersonalTotal ..
                        ", Guild " .. GuildResolved .. "/" .. GuildTotal ..
                        ", Neutral " .. NeutralResolved .. "/" .. NeutralTotal)
                end
                if MarketSync.LogCacheEvent then
                    MarketSync.LogCacheEvent("|cff00ff00[Done]|r All pending items resolved successfully.")
                end
            end
        end)
    end)

    -- Periodic retry for missed events
    local periodicCycleCount = 0
    if activePeriodicRetry then activePeriodicRetry:Cancel() end
    activePeriodicRetry = C_Timer.NewTicker(preset.interval, function()
        if not MarketSync.CanBuildCache() then return end
        local pRemaining, gRemaining, nRemaining = 0, 0, 0
        for _ in pairs(LatestPending) do pRemaining = pRemaining + 1 end
        for _ in pairs(PersonalPending) do pRemaining = pRemaining + 1 end
        for _ in pairs(GuildPending) do gRemaining = gRemaining + 1 end
        for _ in pairs(DataPackPending) do gRemaining = gRemaining + 1 end
        for _ in pairs(NeutralPending) do nRemaining = nRemaining + 1 end

        if pRemaining == 0 and gRemaining == 0 and nRemaining == 0 then
            activePeriodicRetry:Cancel()
            activePeriodicRetry = nil
            return
        end

        periodicCycleCount = periodicCycleCount + 1
        local forceFallback = (periodicCycleCount >= 6)

        local requested = 0
        for _, itemID in pairs(LatestPending) do
            if requested >= preset.requests then break end
            MarketSync.RequestItemData(itemID)
            requested = requested + 1
        end
        for dbKey, itemID in pairs(PersonalPending) do
            if requested >= preset.requests then break end
            MarketSync.RequestItemData(itemID)
            requested = requested + 1
        end
        for dbKey, itemID in pairs(GuildPending) do
            if requested >= preset.requests then break end
            if not PersonalPending[dbKey] then
                MarketSync.RequestItemData(itemID)
                requested = requested + 1
            end
        end
        for dbKey, itemID in pairs(NeutralPending) do
            if requested >= preset.requests then break end
            MarketSync.RequestItemData(itemID)
            requested = requested + 1
        end

        ProcessPendingBatch(forceFallback)
    end)
end

-- ================================================================
-- GUILD INCOMING BUFFER: Staging area for active sync data
-- New items from sync land here, not in GuildIndex directly
-- ================================================================

-- Called by sync module when a new sync session starts
function MarketSync.BeginGuildSync()
    GuildSyncActive = true
    GuildIncomingCount = 0
    wipe(GuildIncomingBuffer)
    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Guild sync started - buffering incoming data")
    end
end

-- Called by sync module for each item received during sync
function MarketSync.AddToGuildIncoming(dbKey)
    if not GuildIndexReady and not LatestIndexReady then return end
    local liveStore = MarketSync.GetRealmDB().GuildData
        or (Auctionator and Auctionator.Database and Auctionator.Database.db)
    if not liveStore then return end

    local data = liveStore[dbKey]
    if not data then return end

    local itemID = ParseItemID(dbKey)
    if not itemID then return end

    -- Only build Guild entries here (forcePersonal = false)
    local entry = BuildIndexEntry(dbKey, itemID, data, "guild")
    if entry then
        if GuildSyncActive then
            -- Route to incoming buffer
            GuildIncomingBuffer[dbKey] = entry
            GuildIncomingCount = GuildIncomingCount + 1
        else
            if GuildIndexReady then
                local isNewGuild = not GuildIndex[dbKey]
                GuildIndex[dbKey] = entry
                if isNewGuild then
                    GuildTotal = GuildTotal + 1
                    GuildResolved = GuildResolved + 1
                end
            end
            if LatestIndexReady then
                local pStore = MarketSyncDB and MarketSync.GetRealmDB().PersonalData
                local bestData, bestMode = SelectLatestSourceRecord(pStore and pStore[dbKey], data, nil)
                if bestData == data then
                    local isNewLatest = not LatestIndex[dbKey]
                    LatestIndex[dbKey] = BuildIndexEntry(dbKey, itemID, bestData, bestMode or "guild") or entry
                    if isNewLatest then
                        LatestTotal = LatestTotal + 1
                        LatestResolved = LatestResolved + 1
                    end
                end
            end
        end
    else
        -- Not cached yet, request it
        if GuildSyncActive then
            if GuildIndexReady then GuildPending[dbKey] = itemID end
            if LatestIndexReady then LatestPending[dbKey] = itemID end
        end
        MarketSync.RequestItemData(itemID)
    end
end

-- Called when sync session ends — merge incoming buffer into live Guild & Latest indices
function MarketSync.CommitGuildSync()
    local merged = 0
    local removed = 0
    local pStore = MarketSyncDB and MarketSync.GetRealmDB().PersonalData
    local liveStore = MarketSync.GetRealmDB().GuildData
    for dbKey, entry in pairs(GuildIncomingBuffer) do
        if entry then
            if GuildIndexReady then
                GuildIndex[dbKey] = entry
            end
            if LatestIndexReady then
                local bestData, bestMode = SelectLatestSourceRecord(pStore and pStore[dbKey], liveStore and liveStore[dbKey], nil)
                if bestData then
                    local itemID = ParseItemID(dbKey)
                    LatestIndex[dbKey] = (itemID and BuildIndexEntry(dbKey, itemID, bestData, bestMode or "guild")) or entry
                end
            end
            merged = merged + 1
        else
            -- entry is false -> Removal
            if GuildIndexReady and GuildIndex[dbKey] then
                GuildIndex[dbKey] = nil
                removed = removed + 1
            end
        end
    end

    if LatestIndexReady then
        LatestTotal = 0; LatestResolved = 0
        for _ in pairs(LatestIndex) do LatestTotal = LatestTotal + 1; LatestResolved = LatestResolved + 1 end
    end

    -- Recount guild totals
    GuildTotal = 0
    GuildResolved = 0
    for _ in pairs(GuildIndex) do
        GuildTotal = GuildTotal + 1
        GuildResolved = GuildResolved + 1
    end

    GuildSyncActive = false
    GuildIncomingCount = 0
    wipe(GuildIncomingBuffer)

    -- Invalidate CachedScanStats so the next ADV re-counts from the live database.
    -- This is the critical handoff point: new items are now in the Auctionator DB,
    -- so any pre-sync cached count is definitively stale.
    if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end

    if MarketSync.LogCacheEvent then
        MarketSync.LogCacheEvent(string.format("|cff88aaff[Guild Commit]|r Merged %d items, removed %d. Guild index now %d items total.", merged, removed, GuildTotal))
    end

    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Guild sync committed: " .. merged .. " items merged, " .. removed .. " items removed, " .. GuildTotal .. " total guild items")
    end
end

function MarketSync.BeginNeutralSync()
    NeutralSyncActive = true
    NeutralIncomingCount = 0
    wipe(NeutralIncomingBuffer)
    if MarketSync.LogCacheEvent then
        MarketSync.LogCacheEvent("|cff00ccff[Neutral]|r Neutral sync started - buffering incoming data.")
    end
end

function MarketSync.AddToNeutralIncoming(dbKey)
    if not NeutralIndexReady then return end
    local ndata = MarketSync.GetRealmDB().NeutralData and MarketSync.GetRealmDB().NeutralData[dbKey]
    if not ndata then return end

    local itemID = ParseItemID(dbKey)
    if not itemID then return end

    local entry = BuildIndexEntry(dbKey, itemID, ndata, "neutral")
    if entry then
        if NeutralSyncActive then
            NeutralIncomingBuffer[dbKey] = entry
            NeutralIncomingCount = NeutralIncomingCount + 1
        else
            local isNew = not NeutralIndex[dbKey]
            NeutralIndex[dbKey] = entry
            if isNew then
                NeutralTotal = NeutralTotal + 1
                NeutralResolved = NeutralResolved + 1
            end
        end
    else
        NeutralPending[dbKey] = itemID
        MarketSync.RequestItemData(itemID)
    end
end

function MarketSync.CommitNeutralSync()
    local merged = 0
    local removed = 0
    for dbKey, entry in pairs(NeutralIncomingBuffer) do
        if entry then
            NeutralIndex[dbKey] = entry
            merged = merged + 1
        else
            if NeutralIndex[dbKey] then
                NeutralIndex[dbKey] = nil
                removed = removed + 1
            end
        end
    end

    NeutralTotal = 0
    NeutralResolved = 0
    for _ in pairs(NeutralIndex) do
        NeutralTotal = NeutralTotal + 1
        NeutralResolved = NeutralResolved + 1
    end

    NeutralSyncActive = false
    NeutralIncomingCount = 0
    wipe(NeutralIncomingBuffer)

    if MarketSync.LogCacheEvent then
        MarketSync.LogCacheEvent(string.format("|cff00ccff[Neutral Commit]|r Merged %d items, removed %d. Neutral index now %d items.", merged, removed, NeutralTotal))
    end
end

-- ================================================================
-- STATUS API for UI
-- ================================================================
MarketSync.GetIndexStatus = function()
    local lPending, pPending, gPending, dPending, nPending = 0, 0, 0, 0, 0
    for _ in pairs(LatestPending) do lPending = lPending + 1 end
    for _ in pairs(PersonalPending) do pPending = pPending + 1 end
    for _ in pairs(GuildPending) do gPending = gPending + 1 end
    for _ in pairs(DataPackPending) do dPending = dPending + 1 end
    for _ in pairs(NeutralPending) do nPending = nPending + 1 end
    return {
        latestReady = LatestIndexReady,
        latestBuilding = PersonalIndexBuilding,
        latestTotal = LatestTotal,
        latestResolved = LatestResolved,
        latestPending = lPending,
        personalReady = PersonalIndexReady,
        personalBuilding = PersonalIndexBuilding,
        personalTotal = PersonalTotal,
        personalResolved = PersonalResolved,
        personalPending = pPending,
        guildReady = GuildIndexReady,
        guildBuilding = PersonalIndexBuilding,
        guildTotal = GuildTotal,
        guildResolved = GuildResolved,
        guildPending = gPending,
        guildSyncActive = GuildSyncActive,
        guildIncoming = GuildIncomingCount,
        dataPackReady = DataPackIndexReady,
        dataPackTotal = DataPackTotal,
        dataPackResolved = DataPackResolved,
        dataPackPending = dPending,
        neutralReady = NeutralIndexReady,
        neutralBuilding = PersonalIndexBuilding,
        neutralTotal = NeutralTotal,
        neutralResolved = NeutralResolved,
        neutralPending = nPending,
        neutralSyncActive = NeutralSyncActive,
        neutralIncoming = NeutralIncomingCount,
    }
end

-- Processing consumes only rows already resolved by the throttled Browse
-- index build. Reuses LatestIndex when Smart Partial Low RAM keeps only Latest loaded.
MarketSync.GetProcessingIndexSources = function()
    if PersonalIndexBuilding or (not LatestIndexReady and not PersonalIndexReady and not GuildIndexReady) then return nil end
    if PersonalIndexReady or GuildIndexReady then
        return PersonalIndexReady and PersonalIndex or {}, GuildIndexReady and GuildIndex or (LatestIndexReady and LatestIndex or nil)
    end
    return LatestIndex, nil
end

-- Expose for use by Frame module and startup trigger
MarketSync.BuildSearchIndex = BuildSearchIndex

local function StyleModernPillButton(btn, text, isGold)
    if not btn then return btn end
    if type(text) == "boolean" and isGold == nil then
        isGold = text
        text = nil
    end
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        if isGold then
            btn:SetBackdropColor(MarketSync.GetThemeColor("hover"))
            btn:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.95)
        else
            btn:SetBackdropColor(MarketSync.GetThemeColor("header"))
            btn:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))
        end
    end
    local fs = btn.GetFontString and btn:GetFontString()
    if not fs and btn.CreateFontString and btn.SetFontString then
        fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        btn:SetFontString(fs)
    end
    if fs and fs.SetTextColor then
        if isGold then
            fs:SetTextColor(1.0, 0.88, 0.35)
        else
            fs:SetTextColor(0.90, 0.85, 0.75)
        end
    end
    if (type(text) == "string" or type(text) == "number") and btn.SetText then btn:SetText(text) end
    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            if self.SetBackdropColor then
                if isGold then
                    self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
                    self:SetBackdropBorderColor(1.0, 0.88, 0.30, 1.0)
                else
                    self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
                    self:SetBackdropBorderColor(0.95, 0.78, 0.25, 0.95)
                end
            end
            local s = self.GetFontString and self:GetFontString()
            if s and s.SetTextColor then s:SetTextColor(1.0, 0.90, 0.40) end
        end)
        btn:HookScript("OnLeave", function(self)
            if self.SetBackdropColor then
                if isGold then
                    self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
                    self:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.95)
                else
                    self:SetBackdropColor(MarketSync.GetThemeColor("header"))
                    self:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))
                end
            end
            local s = self.GetFontString and self:GetFontString()
            if s and s.SetTextColor then
                if isGold then
                    s:SetTextColor(1.0, 0.88, 0.35)
                else
                    s:SetTextColor(0.90, 0.85, 0.75)
                end
            end
        end)
    end
    return btn
end

local SOURCE_LABELS = {
    latest   = "Latest",
    personal = "Personal",
    guild    = "Guild",
    datapack = "Data Pack",
    neutral  = "Neutral",
}

local function ExtractHistoricalDayPrice(record, dayNum)
    if type(record) ~= "table" or not dayNum then return nil end
    local dayStr = tostring(dayNum)
    if type(record.h) == "table" then
        local val = record.h[dayStr] or record.h[dayNum]
        if type(val) == "number" and val > 0 then
            return val
        elseif type(val) == "string" and val ~= "" then
            if MarketSync.IsCompactRecord and MarketSync.IsCompactRecord(val) and MarketSync.ParseCompactRecord then
                local parsed = MarketSync.ParseCompactRecord(val)
                if parsed and ((parsed.min and parsed.min > 0) or (parsed.avg and parsed.avg > 0)) then
                    return (parsed.min and parsed.min > 0) and parsed.min or parsed.avg
                end
            else
                local lastPrice
                for _, b36p in val:gmatch("(%d+):([%w%-]+):[%w%-]+") do
                    local p = MarketSync.FromBase36 and MarketSync.FromBase36(b36p) or tonumber(b36p)
                    if p and p > 0 then lastPrice = p end
                end
                if lastPrice and lastPrice > 0 then return lastPrice end
                local numVal = tonumber(val)
                if numVal and numVal > 0 then return numVal end
            end
        end
    end
    if tonumber(record.d) == dayNum and tonumber(record.m) and tonumber(record.m) > 0 then
        return tonumber(record.m)
    end
    return nil
end

function MarketSync.GetAvailableScanDays(sourceMode)
    local mode = type(sourceMode) == "string" and sourceMode:lower() or "latest"
    local realmDB = MarketSyncDB and MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if not realmDB then return {} end

    local countsByDay = {}
    local function ScanStore(store, filterFn)
        if type(store) ~= "table" then return end
        for _, rec in pairs(store) do
            if type(rec) == "table" and (not filterFn or filterFn(rec)) then
                local seenDays = {}
                if type(rec.h) == "table" then
                    for dKey, val in pairs(rec.h) do
                        local dNum = tonumber(dKey)
                        if dNum and dNum > 0 and val ~= nil and val ~= "" then
                            seenDays[dNum] = true
                        end
                    end
                end
                local topDay = tonumber(rec.d)
                if topDay and topDay > 0 and tonumber(rec.m) and tonumber(rec.m) > 0 then
                    seenDays[topDay] = true
                end
                for dNum in pairs(seenDays) do
                    countsByDay[dNum] = (countsByDay[dNum] or 0) + 1
                end
            end
        end
    end

    if mode == "neutral" then
        ScanStore(realmDB.NeutralData)
    elseif mode == "personal" then
        ScanStore(realmDB.PersonalData)
    elseif mode == "guild" then
        ScanStore(realmDB.GuildData, function(r) return not IsPackRecord(r) end)
    elseif mode == "datapack" then
        ScanStore(realmDB.GuildData, function(r) return IsPackRecord(r) end)
    else
        ScanStore(realmDB.PersonalData)
        ScanStore(realmDB.GuildData)
    end

    local curDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or 0
    local out = {}
    for dNum, itemCount in pairs(countsByDay) do
        local dateStr = MarketSync.ScanDayToDate and MarketSync.ScanDayToDate(dNum) or ("Day " .. tostring(dNum))
        local diff = math.max(0, curDay - dNum)
        local relLabel = diff == 0 and "Today" or (diff == 1 and "Yesterday" or (tostring(diff) .. "d ago"))
        table.insert(out, {
            day = dNum,
            count = itemCount,
            dateText = dateStr,
            label = string.format("%s (%s)", dateStr, relLabel),
        })
    end
    table.sort(out, function(a, b) return a.day > b.day end)
    while #out > 20 do table.remove(out) end
    return out
end

local function BuildHistoricalSnapshotIndex(sourceMode, targetDay)
    local mode = type(sourceMode) == "string" and sourceMode:lower() or "latest"
    local dayNum = tonumber(targetDay)
    if not dayNum then return SnapshotIndex end
    local snapKey = mode .. ":" .. tostring(dayNum)
    if SnapshotIndexKey == snapKey and next(SnapshotIndex) ~= nil then
        return SnapshotIndex
    end
    wipe(SnapshotIndex)
    SnapshotIndexKey = snapKey

    local realmDB = MarketSyncDB and MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if not realmDB then return SnapshotIndex end

    local function PopulateFromStore(store, storeMode, filterFn)
        if type(store) ~= "table" then return end
        for dbKey, rec in pairs(store) do
            if type(rec) == "table" and (not filterFn or filterFn(rec)) then
                local dayPrice = ExtractHistoricalDayPrice(rec, dayNum)
                local itemID = ParseItemID(dbKey)
                if dayPrice and dayPrice > 0 and itemID then
                    local snapRecord = {
                        m = dayPrice,
                        d = dayNum,
                        src = IsPackRecord(rec) and "DataPack" or rec.src,
                        observedAt = MarketSync.ScanDayToTimestamp and MarketSync.ScanDayToTimestamp(dayNum) or nil,
                    }
                    local entryMode = (storeMode == "guild" and IsPackRecord(rec)) and "datapack" or storeMode
                    local entry = BuildIndexEntry(dbKey, itemID, snapRecord, entryMode, true)
                    if entry then
                        local existing = SnapshotIndex[dbKey]
                        if not existing or entry.price < existing.price then
                            SnapshotIndex[dbKey] = entry
                        end
                    end
                end
            end
        end
    end

    if mode == "neutral" then
        PopulateFromStore(realmDB.NeutralData, "neutral")
    elseif mode == "personal" then
        PopulateFromStore(realmDB.PersonalData, "personal")
    elseif mode == "guild" then
        PopulateFromStore(realmDB.GuildData, "guild", function(r) return not IsPackRecord(r) end)
    elseif mode == "datapack" then
        PopulateFromStore(realmDB.GuildData, "datapack", function(r) return IsPackRecord(r) end)
    else
        PopulateFromStore(realmDB.PersonalData, "personal")
        PopulateFromStore(realmDB.GuildData, "guild")
    end

    return SnapshotIndex
end

-- ================================================================
-- CREATE BROWSE PANEL
-- ================================================================
function MarketSync.CreateBrowsePanel(parent, dataSourceName)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.isMainUnified = (dataSourceName == "main")
    panel.hasTimeframePicker = panel.isMainUnified or (dataSourceName == "neutral")
    panel.dataSource = dataSourceName
    panel.activeSource = panel.isMainUnified and "latest" or dataSourceName
    panel.selectedScanDay = nil
    browsePanels[panel] = true
    local nativeStyle = MarketSync.IsForeverAuctionStyle and MarketSync.IsForeverAuctionStyle()
    local isLegacyBrowse = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local createNativeControl = MarketSync.CreateForeverAuctionControl

    -- --- Search Bar (matches native AH search bar alignment) ---
    if isLegacyBrowse then
        local nameLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 80, -38)
        nameLabel:SetText("Name")
        panel.nameLabel = nameLabel
    end

    local searchBoxWidth = isLegacyBrowse
        and (panel.isMainUnified and 164 or 180)
        or (panel.hasTimeframePicker and 186 or 220)
    local searchBox = (createNativeControl and createNativeControl("EditBox", panel, "SearchBoxTemplate"))
        or CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(searchBoxWidth, isLegacyBrowse and 18 or 20)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 80, isLegacyBrowse and -52 or -46)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        panel:RunSearch()
    end)
    panel.searchBox = searchBox

    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(searchBox, {
            onInsertLink = function(box, text)
                local itemName = text and text:match("%[(.-)%]")
                if itemName and itemName ~= "" then
                    box:SetText(itemName)
                    box:ClearFocus()
                    panel:RunSearch()
                    return true
                end
                return false
            end
        })
    end

    -- Search Button (right side on Classic to match BrowseSearchButton)
    local searchBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    searchBtn:SetSize(isLegacyBrowse and 80 or (panel.hasTimeframePicker and 80 or 84), isLegacyBrowse and 21 or 22)
    if isLegacyBrowse then
        searchBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -44, -38)
    else
        searchBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    end
    searchBtn:SetText("Search")
    searchBtn:SetScript("OnClick", function() panel:RunSearch() end)

    -- Reset Button (above category sidebar on Classic to match BrowseResetButton)
    local resetBtn = (createNativeControl and createNativeControl("Button", panel, "UIMenuButtonStretchTemplate"))
        or CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(isLegacyBrowse and 82 or (panel.hasTimeframePicker and 68 or 74), 22)
    if isLegacyBrowse then
        resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 37, -79)
    else
        resetBtn:SetPoint("LEFT", searchBtn, "RIGHT", 6, 0)
    end
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        panel.activeCategory = nil
        panel.activeSubCategory = nil
        panel.activeSubIDs = nil
        panel.expandedCategory = nil
        panel.minLevelFilter = nil
        panel.maxLevelFilter = nil
        panel.rarityFilter = nil
        panel.groupByCategory = false
        if panel.selectedScanDay ~= nil and panel.SetScanTimeframe then
            panel:SetScanTimeframe(nil)
            return
        end
        if panel.RefreshAdvancedFilters then panel:RefreshAdvancedFilters() end
        panel:RebuildFilters()
        panel:RunSearch()
    end)

    -- These filters operate on cached item metadata, so they work for personal,
    -- guild, and neutral results without issuing extra AH or item-info queries.
    local nativeFilter = createNativeControl and createNativeControl("Button", panel, "UIMenuButtonStretchTemplate")
    local filterBtn = nativeFilter or CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    filterBtn:SetSize(isLegacyBrowse and (panel.isMainUnified and 74 or 80) or (panel.hasTimeframePicker and 72 or 76), 22)
    if isLegacyBrowse then
        filterBtn:SetPoint("LEFT", searchBox, "RIGHT", panel.isMainUnified and 8 or 14, 0)
    else
        filterBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
    end
    filterBtn:SetText("Filter")
    if nativeFilter then
        if filterBtn.SetNormalFontObject then filterBtn:SetNormalFontObject(GameFontNormalSmall) end
        local arrow = filterBtn:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(10, 12)
        arrow:SetPoint("RIGHT", -5, 0)
    end

    -- --- SOURCE & SCAN TIMEFRAME SELECTORS ---
    local dropdownAnchor = filterBtn
    local function UpdateSourceAndTimeframeButtons()
        if panel.sourceBtn then
            local sLabel = SOURCE_LABELS[panel.activeSource] or "Latest"
            panel.sourceBtn:SetText("Source: " .. sLabel .. " v")
        end
        if panel.timeframeBtn then
            if panel.selectedScanDay then
                local dText = MarketSync.ScanDayToDate and MarketSync.ScanDayToDate(panel.selectedScanDay) or tostring(panel.selectedScanDay)
                panel.timeframeBtn:SetText("Scan: " .. dText .. " v")
            else
                panel.timeframeBtn:SetText("Scan: Latest v")
            end
        end
    end

    if panel.isMainUnified then
        local nativeSrc = createNativeControl and createNativeControl("Button", panel, "UIMenuButtonStretchTemplate")
        local sourceBtn = nativeSrc or CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        sourceBtn:SetSize(isLegacyBrowse and 126 or 134, 22)
        sourceBtn:SetPoint("LEFT", dropdownAnchor, "RIGHT", 8, 0)
        if nativeSrc and sourceBtn.SetNormalFontObject then
            sourceBtn:SetNormalFontObject(GameFontNormalSmall)
        end
        if isLegacyBrowse then
            local srcLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            srcLbl:SetPoint("BOTTOMLEFT", sourceBtn, "TOPLEFT", 2, 3)
            srcLbl:SetText("Source")
            panel.sourceLabel = srcLbl
        end
        local sourceDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
        sourceBtn:SetScript("OnClick", function(self)
            if UIDropDownMenu_Initialize and ToggleDropDownMenu then
                UIDropDownMenu_Initialize(sourceDropdown, function()
                    local options = {
                        { value = "latest",   text = "Latest (Combined)", desc = "Single deduplicated hot index across Personal, Guild & Data Pack" },
                        { value = "personal", text = "Personal Scan",     desc = "Only your own local Auction House scans (on-demand)" },
                        { value = "guild",    text = "Guild Sync",        desc = "Only composite quotes synced from guildmates (on-demand)" },
                        { value = "datapack", text = "Data Pack",         desc = "Only compiled MarketSyncData baseline quotes (on-demand)" },
                    }
                    for _, opt in ipairs(options) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = opt.text
                        info.value = opt.value
                        info.checked = (panel.activeSource == opt.value)
                        info.tooltipTitle = opt.text
                        info.tooltipText = opt.desc
                        info.tooltipOnButton = true
                        info.func = function()
                            if CloseDropDownMenus then CloseDropDownMenus() end
                            panel:SetSourceMode(opt.value)
                        end
                        UIDropDownMenu_AddButton(info)
                    end
                end, "MENU")
                ToggleDropDownMenu(1, nil, sourceDropdown, self, 0, 0)
            end
        end)
        sourceBtn:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Main AH Data Source", 1, 0.82, 0)
                GameTooltip:AddLine("'Latest' keeps one deduplicated Main AH index ready. Specific sources (Personal, Guild, Data Pack) load on demand.", 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end
        end)
        sourceBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        panel.sourceBtn = sourceBtn
        dropdownAnchor = sourceBtn
    end

    if panel.hasTimeframePicker then
        local nativeTf = createNativeControl and createNativeControl("Button", panel, "UIMenuButtonStretchTemplate")
        local timeframeBtn = nativeTf or CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        timeframeBtn:SetSize(isLegacyBrowse and 126 or 136, 22)
        timeframeBtn:SetPoint("LEFT", dropdownAnchor, "RIGHT", isLegacyBrowse and 8 or 6, 0)
        if nativeTf and timeframeBtn.SetNormalFontObject then
            timeframeBtn:SetNormalFontObject(GameFontNormalSmall)
        end
        if isLegacyBrowse then
            local tfLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tfLbl:SetPoint("BOTTOMLEFT", timeframeBtn, "TOPLEFT", 2, 3)
            tfLbl:SetText("Scan Point")
            panel.timeframeLabel = tfLbl
        end
        local timeframeDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
        timeframeBtn:SetScript("OnClick", function(self)
            if UIDropDownMenu_Initialize and ToggleDropDownMenu then
                UIDropDownMenu_Initialize(timeframeDropdown, function()
                    local latestInfo = UIDropDownMenu_CreateInfo()
                    latestInfo.text = "Latest (Current)"
                    latestInfo.checked = (panel.selectedScanDay == nil)
                    latestInfo.func = function()
                        if CloseDropDownMenus then CloseDropDownMenus() end
                        panel:SetScanTimeframe(nil)
                    end
                    UIDropDownMenu_AddButton(latestInfo)

                    local days = MarketSync.GetAvailableScanDays and MarketSync.GetAvailableScanDays(panel.activeSource) or {}
                    for _, entry in ipairs(days) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = string.format("%s  |cffaaaaaa(%d)|r", entry.label, entry.count)
                        info.checked = (panel.selectedScanDay == entry.day)
                        info.func = function()
                            if CloseDropDownMenus then CloseDropDownMenus() end
                            panel:SetScanTimeframe(entry.day)
                        end
                        UIDropDownMenu_AddButton(info)
                    end
                end, "MENU")
                ToggleDropDownMenu(1, nil, timeframeDropdown, self, 0, 0)
            end
        end)
        timeframeBtn:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Historical Scan Snapshot", 1, 0.82, 0)
                GameTooltip:AddLine("Inspect market prices from a specific recorded scan date without keeping historical indexes in memory.", 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end
        end)
        timeframeBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        panel.timeframeBtn = timeframeBtn
    end
    UpdateSourceAndTimeframeButtons()

    function panel:SetSourceMode(mode)
        local normalized = type(mode) == "string" and mode:lower() or "latest"
        if normalized ~= "latest" and normalized ~= "personal" and normalized ~= "guild" and normalized ~= "datapack" and normalized ~= "neutral" then
            normalized = "latest"
        end
        self.activeSource = normalized
        self.selectedScanDay = nil
        if MarketSync.ReleaseSecondaryBrowseCaches then
            MarketSync.ReleaseSecondaryBrowseCaches(normalized)
        end
        UpdateSourceAndTimeframeButtons()
        if self.RefreshStatusFooter then self:RefreshStatusFooter() end
        self:RunSearch()
    end

    function panel:SetScanTimeframe(scanDay)
        local dayNum = tonumber(scanDay)
        self.selectedScanDay = (dayNum and dayNum > 0) and dayNum or nil
        if not self.selectedScanDay and MarketSync.ReleaseSecondaryBrowseCaches then
            MarketSync.ReleaseSecondaryBrowseCaches(self.activeSource)
        end
        UpdateSourceAndTimeframeButtons()
        if self.RefreshStatusFooter then self:RefreshStatusFooter() end
        self:RunSearch()
    end

    local filterPopup = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    filterPopup:SetSize(205, 269)
    filterPopup:SetPoint("TOPLEFT", filterBtn, "BOTTOMLEFT", 0, -3)
    filterPopup:SetFrameStrata("DIALOG")
    filterPopup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    filterPopup:SetBackdropColor(MarketSync.GetThemeColor("dialog"))
    filterPopup:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
    filterPopup:Hide()
    filterBtn:SetScript("OnClick", function()
        if filterPopup:IsShown() then filterPopup:Hide() else filterPopup:Show() end
    end)

    local levelLabel = filterPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("TOPLEFT", 12, -12)
    levelLabel:SetText("Required level")
    local function MakeLevelBox(x)
        local box = CreateFrame("EditBox", nil, filterPopup, "InputBoxTemplate")
        box:SetSize(52, 19)
        box:SetPoint("TOPLEFT", x, -30)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        return box
    end
    local minBox = MakeLevelBox(14)
    local maxBox = MakeLevelBox(91)
    local levelDash = filterPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    levelDash:SetPoint("LEFT", minBox, "RIGHT", 8, 0)
    levelDash:SetText("-")

    local rarityLabel = filterPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rarityLabel:SetPoint("TOPLEFT", 12, -59)
    rarityLabel:SetText("Rarity")
    local rarityNames = { "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" }
    local rarityChecks = {}
    local function ApplyAdvancedFilters()
        panel.minLevelFilter = tonumber(minBox:GetText())
        panel.maxLevelFilter = tonumber(maxBox:GetText())
        panel.rarityFilter = {}
        local selected = 0
        for quality, check in ipairs(rarityChecks) do
            if check:GetChecked() then
                panel.rarityFilter[quality - 1] = true
                selected = selected + 1
            end
        end
        if selected == #rarityChecks then panel.rarityFilter = nil end
        panel:RunSearch()
    end
    minBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    maxBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    minBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ApplyAdvancedFilters() end)
    maxBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ApplyAdvancedFilters() end)
    minBox:SetScript("OnEditFocusLost", ApplyAdvancedFilters)
    maxBox:SetScript("OnEditFocusLost", ApplyAdvancedFilters)
    for quality, name in ipairs(rarityNames) do
        local check = CreateFrame("CheckButton", nil, filterPopup, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", 9, -75 - (quality - 1) * 23)
        check:SetChecked(true)
        local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", check, "RIGHT", 3, 0)
        label:SetText(name)
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality - 1]
        if color then label:SetTextColor(color.r, color.g, color.b) end
        check:SetScript("OnClick", ApplyAdvancedFilters)
        rarityChecks[quality] = check
    end
    local groupCheck = CreateFrame("CheckButton", nil, filterPopup, "UICheckButtonTemplate")
    groupCheck:SetSize(20, 20)
    groupCheck:SetPoint("TOPLEFT", 9, -239)
    local groupLabel = groupCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupLabel:SetPoint("LEFT", groupCheck, "RIGHT", 3, 0)
    groupLabel:SetText("Group by category")
    groupCheck:SetScript("OnClick", function(self)
        panel.groupByCategory = self:GetChecked() == true
        panel:RunSearch()
    end)
    function panel:RefreshAdvancedFilters()
        minBox:SetText(self.minLevelFilter and tostring(self.minLevelFilter) or "")
        maxBox:SetText(self.maxLevelFilter and tostring(self.maxLevelFilter) or "")
        for quality, check in ipairs(rarityChecks) do
            check:SetChecked(not self.rarityFilter or self.rarityFilter[quality - 1] == true)
        end
        groupCheck:SetChecked(self.groupByCategory == true)
    end

    -- --- CATEGORY SIDEBAR & RESULTS INSETS ---
    local isLegacyFilters = isLegacyBrowse
    local filterBtnHeight = isLegacyFilters and 20 or FILTER_HEIGHT
    local SIDEBAR_WIDTH = isLegacyFilters and 159 or 156
    local SIDEBAR_HEIGHT = isLegacyFilters and 306 or 335
    local filterStride = filterBtnHeight + ((nativeStyle or isLegacyFilters) and 0 or 2)
    local categoryInset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(
        panel, isLegacyFilters and 21 or 20, isLegacyFilters and -103 or -75, SIDEBAR_WIDTH, SIDEBAR_HEIGHT, "controls")
    panel.categoryInset = categoryInset

    local tableInset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(
        panel, isLegacyFilters and 186 or 182, isLegacyFilters and -103 or -75, isLegacyFilters and 624 or 630, isLegacyFilters and 306 or 335, "results")
    panel.tableInset = tableInset

    if isLegacyFilters then
        -- Let the native Classic UI-AuctionFrame-Browse-* stone wells frame the
        -- category list and results table directly without extra inset borders.
        for _, ins in ipairs({ categoryInset, tableInset }) do
            if ins then
                ins._marketSyncSkipTheme = true
                if ins.SetBackdropColor then ins:SetBackdropColor(0, 0, 0, 0) end
                if ins.SetBackdropBorderColor then ins:SetBackdropBorderColor(0, 0, 0, 0) end
                if ins.topHighlight and ins.topHighlight.Hide then ins.topHighlight:Hide() end
            end
        end
    end

    -- Modern vertical scrollbar for results table matching native AH
    local tableScrollBar
    if MarketSync.CreateModernTableScrollBar and tableInset then
        tableScrollBar = MarketSync.CreateModernTableScrollBar(panel, tableInset, function(newPage)
            panel.page = newPage
            panel:UpdateResults()
        end, 8, isLegacyFilters and -2 or -24, isLegacyFilters and 2 or 10)
        panel.tableScrollBar = tableScrollBar
        tableScrollBar:AttachMouseWheel(tableInset)
    end

    -- Modern slim scrollbar matching native Auction House client
    local scrollName = "MarketSyncBrowse" .. tostring(dataSourceName or "Scan") .. "FilterScroll"
    local filterScroll = CreateFrame("ScrollFrame", scrollName, panel, "UIPanelScrollFrameTemplate")
    filterScroll:SetPoint("TOPLEFT", categoryInset or panel, "TOPLEFT", isLegacyFilters and 0 or 2, isLegacyFilters and -2 or -3)
    filterScroll:SetSize(isLegacyFilters and 138 or (SIDEBAR_WIDTH - 22), isLegacyFilters and 302 or (SIDEBAR_HEIGHT - 8))
    local filterChild = CreateFrame("Frame")
    filterChild:SetSize(isLegacyFilters and 138 or (SIDEBAR_WIDTH - 22), 800)
    filterScroll:SetScrollChild(filterChild)
    if MarketSync.SkinModernScrollBar then
        MarketSync.SkinModernScrollBar(filterScroll, 8, isLegacyFilters and 2 or 4)
    end
    filterScroll:EnableMouseWheel(true)
    filterScroll:SetScript("OnMouseWheel", function(self, delta)
        local step = filterStride * 3
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newVal = current - (delta * step)
        newVal = math.max(0, math.min(newVal, maxScroll))
        self:SetVerticalScroll(newVal)
    end)
    panel.filterScroll = filterScroll
    panel.filterChild = filterChild
    panel.filterButtons = {}
    panel.expandedCategory = nil
    panel.activeSubCategory = nil
    local nativeCategoryButtons = {}

    local function MakeFilterButton(parentFrame, labelText, indent, yOff, btnWidth)
        local isSub = indent > 0
        if nativeStyle and createNativeControl and type(AuctionHouseFilterButton_SetUp) == "function" then
            local index = #panel.filterButtons + 1
            local native = nativeCategoryButtons[index]
                or createNativeControl("Button", parentFrame, "AuctionCategoryButtonTemplate")
            if native then
                nativeCategoryButtons[index] = native
                local ok = pcall(AuctionHouseFilterButton_SetUp, native, {
                    type = isSub and "subCategory" or "category", name = labelText, selected = false,
                })
                if ok then
                    native:SetSize(btnWidth or 132, FILTER_HEIGHT)
                    native:ClearAllPoints()
                    native:SetPoint("TOPLEFT", 2, -yOff)
                    function native:SetSelected(selected)
                        self.isSelected = selected
                        self.SelectedTexture:SetShown(selected)
                    end
                    native:Show()
                    return native
                end
                native:Hide()
            end
        end

        local w = (btnWidth or 132)
        if indent > 0 and not isLegacyFilters then
            w = w - indent
        end
        local btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(w, filterBtnHeight)
        btn:SetPoint("TOPLEFT", (indent > 0 and not isLegacyFilters) and (indent + 2) or 2, -yOff)

        local normalTex = btn:CreateTexture(nil, "BACKGROUND")
        local selectedTex = btn:CreateTexture(nil, "ARTWORK")
        local highlightTex = btn:CreateTexture(nil, "HIGHLIGHT")

        local selectionAtlas = isSub and "auctionhouse-nav-button-secondary-select" or "auctionhouse-nav-button-select"
        if nativeStyle then
            normalTex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
            normalTex:SetTexCoord(0, 0.53125, 0, 0.625)
            if selectedTex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(selectionAtlas) then
                selectedTex:SetAtlas(selectionAtlas, false)
                selectedTex:SetBlendMode("ADD")
            else
                selectedTex:SetColorTexture(MarketSync.GetThemeColor("hover", 0.35))
            end
            highlightTex:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
            highlightTex:SetBlendMode("ADD")
            normalTex:SetAllPoints()
            selectedTex:SetAllPoints()
            highlightTex:SetAllPoints()
        elseif not isLegacyFilters and normalTex.SetAtlas
            and pcall(normalTex.SetAtlas, normalTex, isSub and "auctionhouse-nav-button-secondary" or "auctionhouse-nav-button") then
            normalTex:SetAllPoints()
            selectedTex:SetAtlas(selectionAtlas)
            selectedTex:SetAllPoints()
            highlightTex:SetAtlas(isSub and "auctionhouse-nav-button-secondary-highlight" or "auctionhouse-nav-button-highlight")
            highlightTex:SetAllPoints()
        else
            -- Authentic Classic Auction House category & subcategory artwork:
            -- Keep UI-AuctionFrame-FilterBg visible (0.45 alpha for subcategories)
            -- and use UI-Character-Tab-Highlight (ADD) for blue selection & hover.
            normalTex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
            normalTex:SetTexCoord(0, 0.53125, 0, 0.625)
            if normalTex.SetAlpha then normalTex:SetAlpha(isSub and 0.45 or 1.0) end
            normalTex:SetAllPoints()

            selectedTex:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
            if selectedTex.SetBlendMode then selectedTex:SetBlendMode("ADD") end
            selectedTex:SetAllPoints()

            highlightTex:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
            if highlightTex.SetBlendMode then highlightTex:SetBlendMode("ADD") end
            highlightTex:SetAllPoints()
        end
        selectedTex:Hide()

        btn.NormalTexture = normalTex
        btn.SelectedTexture = selectedTex
        btn.HighlightTexture = highlightTex

        local text = btn:CreateFontString(nil, "OVERLAY", isSub and "GameFontHighlightSmall" or "GameFontNormalSmall")
        text:SetPoint("LEFT", btn, "LEFT", isSub and 14 or 8, 0)
        text:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(false) end
        text:SetText(labelText)
        btn.Text = text
        btn.text = text

        btn.SetSelected = function(self, isSelected)
            if isSelected then
                if self.SelectedTexture then self.SelectedTexture:Show() end
                if self.NormalTexture then
                    if nativeStyle or isLegacyFilters then
                        self.NormalTexture:Show()
                    else
                        self.NormalTexture:Hide()
                    end
                end
                local t = self.Text or self.text
                if t and t.SetTextColor then t:SetTextColor(1.0, 1.0, 1.0) end
            else
                if self.SelectedTexture then self.SelectedTexture:Hide() end
                if self.NormalTexture then self.NormalTexture:Show() end
                local t = self.Text or self.text
                if t and t.SetTextColor then
                    if isSub then
                        t:SetTextColor(0.85, 0.85, 0.85)
                    else
                        t:SetTextColor(1.0, 0.82, 0.0)
                    end
                end
            end
        end

        return btn
    end

    function panel:RebuildFilters()
        for _, b in ipairs(self.filterButtons) do b:Hide() end
        wipe(self.filterButtons)

        local btnWidth = isLegacyFilters and 136 or 132
        local y = isLegacyFilters and 0 or 2
        for _, cat in ipairs(CATEGORIES) do
            local btn = MakeFilterButton(self.filterChild, cat.name, 0, y, btnWidth)
            btn.classID = cat.classID
            btn.isCategory = true
            local isCatSelected = (self.activeCategory == cat.classID and not self.activeSubCategory)
            btn:SetSelected(isCatSelected)

            btn:SetScript("OnClick", function()
                if self.activeCategory == cat.classID and self.activeSubCategory == nil then
                    -- Toggle OFF: Clear filter and collapse
                    self.activeCategory = nil
                    self.expandedCategory = nil
                    self.activeSubCategory = nil
                    self.activeSubIDs = nil
                else
                    -- Toggle ON: Select and Expand
                    self.activeCategory = cat.classID
                    self.activeSubCategory = nil
                    self.activeSubIDs = nil
                    self.expandedCategory = cat.classID
                end
                self:RebuildFilters()
                self:RunSearch()
            end)
            table.insert(self.filterButtons, btn)
            y = y + filterStride

            if self.expandedCategory == cat.classID and cat.subs then
                for _, sub in ipairs(cat.subs) do
                    local sbtn = MakeFilterButton(self.filterChild, sub.name, 12, y, btnWidth)
                    sbtn.classID = cat.classID
                    sbtn.subIDs = sub.subIDs
                    local isSubSelected = (self.activeSubCategory == sub.name and self.activeCategory == cat.classID)
                    sbtn:SetSelected(isSubSelected)

                    sbtn:SetScript("OnClick", function()
                        if self.activeCategory == cat.classID and self.activeSubCategory == sub.name then
                            self.activeSubCategory = nil -- Toggle OFF (Revert to Parent)
                            self.activeSubIDs = nil
                        else
                            self.activeCategory = cat.classID
                            self.activeSubCategory = sub.name
                            self.activeSubIDs = sub.subIDs
                        end
                        self:RebuildFilters()
                        self:RunSearch()
                    end)
                    table.insert(self.filterButtons, sbtn)
                    y = y + filterStride
                end
            end
        end
        self.filterChild:SetHeight(math.max(y + 8, SIDEBAR_HEIGHT))
    end
    panel:RebuildFilters()

    -- --- SORTING STATE ---
    panel.sortField = "price"
    panel.sortAscending = true

    local function SortResults(field)
        if panel.sortField == field then
            panel.sortAscending = not panel.sortAscending
        else
            panel.sortField = field
            panel.sortAscending = true
        end
        panel:ApplySort()
        panel.page = 0
        panel:UpdateResults()
        for _, h in ipairs(panel.headerButtons) do
            if h.sortKey == field then
                if h.arrow then h.arrow:Show() end
                if h.label then h.label:SetTextColor(1, 0.82, 0) end
                if panel.sortAscending then
                    if h.arrow then h.arrow:SetTexCoord(0, 0.5625, 1.0, 0) end
                else
                    if h.arrow then h.arrow:SetTexCoord(0, 0.5625, 0, 1.0) end
                end
            else
                if h.arrow then h.arrow:Hide() end
                if h.label then h.label:SetTextColor(0.85, 0.85, 0.85) end
            end
        end
    end

    -- --- COLUMN HEADERS (matches Blizzard AH dark charcoal headers) ---
    local colDefs = {
        {name = "Item",    width = 275, sortKey = "rarity"},
        {name = "Lvl",     width = 42,  sortKey = "minLevel"},
        {name = "Price",   width = 100, sortKey = "price"},
        {name = "Age",     width = 58,  sortKey = nil},
        {name = "Src",     width = 55,  sortKey = nil},
        {name = "Seen",    width = 60,  sortKey = nil},
        {name = "",        width = isLegacyBrowse and 32 or 40, sortKey = nil},
    }
    local colX = isLegacyBrowse and 186 or 184
    local hdrH = isLegacyBrowse and 19 or 20
    local hdrY = isLegacyBrowse and -82 or -75
    panel.headerButtons = {}
    for i, col in ipairs(colDefs) do
        local hdr = MarketSync.CreateAHColumnHeader and MarketSync.CreateAHColumnHeader(panel, col.width, hdrH, col.name, col.sortKey, true)
        if not hdr then
            hdr = CreateFrame("Button", nil, panel, "BackdropTemplate")
            hdr:SetSize(col.width, hdrH)
            hdr.label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hdr.label:SetPoint("LEFT", 6, 0)
            hdr.label:SetText(col.name)
        end
        hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, hdrY)
        hdr.sortKey = col.sortKey

        if col.sortKey == "price" then
            if hdr.arrow then
                hdr.arrow:Show()
                hdr.arrow:SetTexCoord(0, 0.5625, 1.0, 0)
            end
            if hdr.label then
                hdr.label:SetTextColor(1, 0.82, 0)
            end
        end

        if col.sortKey then
            hdr:SetScript("OnClick", function() SortResults(col.sortKey) end)
        end

        panel.headerButtons[i] = hdr
        colX = colX + col.width
    end

    -- --- Prev/Next Buttons (top-right on Classic matching BrowsePrev/NextPageButton, bottom-right on modern) ---
    panel.page = 0
    panel.currentResults = {}

    local prevBtn = CreateFrame("Button", nil, panel)
    prevBtn:SetSize(20, 20)
    if isLegacyBrowse then
        prevBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 660, -60)
        prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
        prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
        prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local prevLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        prevLbl:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
        prevLbl:SetText("Prev")
        panel.prevLabel = prevLbl
    else
        prevBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -48, 14)
        prevBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
        prevBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
        prevBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
        local pnt = prevBtn.GetNormalTexture and prevBtn:GetNormalTexture()
        if pnt and pnt.SetVertexColor then pnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) end
    end
    prevBtn:SetScript("OnClick", function()
        if panel.page > 0 then
            panel.page = panel.page - 1
            panel:UpdateResults()
        end
    end)
    panel.prevBtn = prevBtn

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(20, 20)
    if isLegacyBrowse then
        nextBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -60)
        nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
        nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
        nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local nextLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nextLbl:SetPoint("RIGHT", nextBtn, "LEFT", -2, 0)
        nextLbl:SetText("Next")
        panel.nextLabel = nextLbl
    else
        nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        nextBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
        nextBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
        nextBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
        local nnt = nextBtn.GetNormalTexture and nextBtn:GetNormalTexture()
        if nnt and nnt.SetVertexColor then nnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) end
    end
    nextBtn:SetScript("OnClick", function()
        local maxPage = math.floor(#panel.currentResults / NUM_RESULTS_TO_DISPLAY)
        if panel.page < maxPage then
            panel.page = panel.page + 1
            panel:UpdateResults()
        end
    end)
    panel.nextBtn = nextBtn

    -- Page text (in bottom bar)
    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if isLegacyBrowse then
        panel.pageText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 17)
    else
        panel.pageText:SetPoint("RIGHT", prevBtn, "LEFT", -8, 0)
    end

    -- No results text
    panel.noResultsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noResultsText:SetPoint("TOP", panel, "TOP", 115, -200)
    panel.noResultsText:SetText("Search for items using the box above.")
    panel.noResultsText:Show()

    -- Low RAM notice card (loading screen with manual trigger or link to settings)
    local lowRamNotice = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    lowRamNotice:SetSize(470, 148)
    lowRamNotice:SetPoint("TOP", panel, "TOP", 115, -140)
    if lowRamNotice.SetBackdrop then
        lowRamNotice:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        if lowRamNotice.SetBackdropColor then
            lowRamNotice:SetBackdropColor(MarketSync.GetThemeColor("notice"))
        end
        if lowRamNotice.SetBackdropBorderColor then
            lowRamNotice:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
        end
    end

    local lowRamTitle = lowRamNotice:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lowRamTitle:SetPoint("TOP", lowRamNotice, "TOP", 0, -16)
    lowRamTitle:SetText("|cffffd700Low RAM Mode Active|r")
    lowRamNotice.title = lowRamTitle

    local lowRamText = lowRamNotice:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lowRamText:SetPoint("TOP", lowRamTitle, "BOTTOM", 0, -8)
    lowRamText:SetWidth(430)
    lowRamText:SetJustifyH("CENTER")
    lowRamNotice.text = lowRamText
    lowRamNotice.desc = lowRamText

    local btnLoad = CreateFrame("Button", nil, lowRamNotice, "UIPanelButtonTemplate")
    btnLoad:SetSize(154, 24)
    btnLoad:SetPoint("BOTTOMRIGHT", lowRamNotice, "BOTTOM", -8, 16)
    btnLoad:SetText("⚡ Load Scan Data")
    if StyleModernPillButton then StyleModernPillButton(btnLoad, "⚡ Load Scan Data", true) end
    local function GetEffectivePanelSource(self)
        return self.activeSource or self.dataSource or "personal"
    end

    local function IsEffectiveSourceReady(self)
        if self.selectedScanDay then return true end
        local src = GetEffectivePanelSource(self)
        if src == "latest" then return LatestIndexReady
        elseif src == "guild" then return GuildIndexReady
        elseif src == "datapack" then return DataPackIndexReady
        elseif src == "neutral" then return NeutralIndexReady
        else return PersonalIndexReady end
    end

    local function ShouldAutoBuildSource(self)
        if not MarketSyncDB or not MarketSyncDB.LowRamMode then
            return true
        end
        local src = GetEffectivePanelSource(self)
        if src == "latest" and MarketSyncDB.PartialLowRamKeepLatest ~= false then
            return true
        end
        return false
    end

    btnLoad:SetScript("OnClick", function()
        btnLoad:SetText("Loading...")
        if btnLoad.SetEnabled then btnLoad:SetEnabled(false) end
        lowRamText:SetText("|cffffcc00Loading scan records into memory... Please wait.|r")
        local onDone = function()
            btnLoad:SetText("⚡ Load Scan Data")
            if btnLoad.SetEnabled then btnLoad:SetEnabled(true) end
            if panel.RefreshStatusFooter then panel:RefreshStatusFooter() end
            panel:RunSearch()
        end
        local src = GetEffectivePanelSource(panel)
        if src == "latest" then
            MarketSync.LoadLatestCache(onDone)
        elseif src == "guild" then
            MarketSync.LoadGuildCache(onDone)
        elseif src == "datapack" then
            MarketSync.LoadDataPackCache(onDone)
        elseif src == "neutral" then
            MarketSync.LoadNeutralCache(onDone)
        else
            MarketSync.LoadPersonalCache(onDone)
        end
    end)
    btnLoad:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Load Cache on Demand", 1, 0.82, 0)
            GameTooltip:AddLine("Loads scan data for this source into memory on demand.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    btnLoad:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    lowRamNotice.btnLoad = btnLoad

    local btnLowRamSettings = CreateFrame("Button", nil, lowRamNotice, "UIPanelButtonTemplate")
    btnLowRamSettings:SetSize(174, 24)
    btnLowRamSettings:SetPoint("BOTTOMLEFT", lowRamNotice, "BOTTOM", 8, 16)
    btnLowRamSettings:SetText("Settings (Disable Low RAM)")
    if StyleModernPillButton then StyleModernPillButton(btnLowRamSettings, "Settings (Disable Low RAM)", false) end
    btnLowRamSettings:SetScript("OnClick", function()
        if MarketSync.OpenSettings then
            MarketSync.OpenSettings()
        end
    end)
    btnLowRamSettings:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Addon Settings", 1, 0.82, 0)
            GameTooltip:AddLine("Opens Settings to configure Smart Partial Low RAM or retain secondary views in memory.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    btnLowRamSettings:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    lowRamNotice.btnSettings = btnLowRamSettings
    lowRamNotice:Hide()
    panel.lowRamNotice = lowRamNotice

    -- --- STATUS TEXT (inside the bottom gold bar, left side, centered vertically) ---
    local statusBarY = isLegacyBrowse and 17 or 16
    panel.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.statusText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", isLegacyBrowse and 26 or 28, statusBarY)
    panel.statusText:SetWidth(isLegacyBrowse and 150 or 152)
    panel.statusText:SetHeight(16)
    panel.statusText:SetJustifyH("LEFT")
    if panel.statusText.SetWordWrap then panel.statusText:SetWordWrap(false) end

    -- --- "Last Guild Sync" LABEL (aligned with Rarity column area) ---
    panel.syncLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.syncLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", isLegacyBrowse and 194 or 198, statusBarY)
    panel.syncLabel:SetWidth(165)
    panel.syncLabel:SetHeight(16)
    panel.syncLabel:SetJustifyH("LEFT")
    if panel.syncLabel.SetWordWrap then panel.syncLabel:SetWordWrap(false) end

    -- --- ITEM COUNT TEXT (center-right of gold bar, clear of syncLabel & pageText) ---
    panel.itemCountText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.itemCountText:SetPoint("BOTTOM", panel, "BOTTOM", 36, statusBarY)
    panel.itemCountText:SetWidth(150)
    panel.itemCountText:SetHeight(16)
    panel.itemCountText:SetJustifyH("CENTER")
    if panel.itemCountText.SetWordWrap then panel.itemCountText:SetWordWrap(false) end

    function panel:RefreshStatusFooter()
        local src = GetEffectivePanelSource(self)
        local realmDB = MarketSyncDB and MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        if self.selectedScanDay then
            local dText = MarketSync.ScanDayToDate and MarketSync.ScanDayToDate(self.selectedScanDay) or ("Day " .. tostring(self.selectedScanDay))
            self.statusText:SetText("|cff00ccffSnapshot: " .. dText .. "|r")
            self.syncLabel:SetText("|cffffd700" .. (SOURCE_LABELS[src] or "Main AH") .. " History|r")
            local sCount = 0
            for _ in pairs(SnapshotIndex) do sCount = sCount + 1 end
            self.itemCountText:SetText("|cffffd700" .. sCount .. "|r items")
            return
        end

        local statusScope = (src == "latest" or src == "datapack") and "all" or src
        local status, label = MarketSync.FormatAuctionScanStatus(statusScope)
        if src == "datapack" then
            label = "|cffcc88ffData Pack Quotes|r"
        elseif src == "latest" and label == "" then
            label = "|cff00ff00Latest Combined|r"
        end
        self.statusText:SetText(status)
        self.syncLabel:SetText(label)

        if src == "latest" then
            local count = LatestIndexReady and LatestResolved or 0
            if count == 0 and realmDB then
                local seen = {}
                for k in pairs(realmDB.PersonalData or {}) do seen[k] = true; count = count + 1 end
                for k in pairs(realmDB.GuildData or {}) do if not seen[k] then seen[k] = true; count = count + 1 end end
            end
            self.itemCountText:SetText("|cffffd700" .. count .. "|r items")
        elseif src == "personal" then
            local totalItems = 0
            if realmDB and realmDB.PersonalData then
                for _ in pairs(realmDB.PersonalData) do totalItems = totalItems + 1 end
            end
            self.itemCountText:SetText("|cffffd700" .. totalItems .. "|r items")
        elseif src == "guild" then
            local gCount = GuildIndexReady and GuildResolved or 0
            if gCount == 0 and realmDB and realmDB.GuildData then
                for _, rec in pairs(realmDB.GuildData) do
                    if not IsPackRecord(rec) then gCount = gCount + 1 end
                end
            end
            self.itemCountText:SetText("|cffffd700" .. gCount .. "|r items")
        elseif src == "datapack" then
            local pCount = DataPackIndexReady and DataPackResolved or 0
            if pCount == 0 and realmDB and realmDB.GuildData then
                for _, rec in pairs(realmDB.GuildData) do
                    if IsPackRecord(rec) then pCount = pCount + 1 end
                end
            end
            self.itemCountText:SetText("|cffffd700" .. pCount .. "|r items")
        elseif src == "neutral" then
            local nCount = 0
            if realmDB and realmDB.NeutralData then
                for _ in pairs(realmDB.NeutralData) do nCount = nCount + 1 end
            end
            self.itemCountText:SetText("|cffffd700" .. nCount .. "|r items")
        end
    end

    -- --- OnShow: Update status bar and run initial search ---
    panel:SetScript("OnShow", function(self)
        self:RunSearch()
        self:RefreshStatusFooter()
    end)

    -- --- RESULT ROWS ---
    local browseRowWidth = isLegacyBrowse and 598 or 612
    local browseRowLeft = isLegacyBrowse and 188 or 184
    local browseRowTop = isLegacyBrowse and -106 or -97
    panel.resultRows = {}
    for i = 1, NUM_RESULTS_TO_DISPLAY do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(browseRowWidth, RESULT_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", browseRowLeft, browseRowTop - (i-1) * RESULT_HEIGHT)

        -- Item Icon
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(32, 32)
        iconBtn:SetPoint("TOPLEFT", 0, -3)
        local iconTex = iconBtn:CreateTexture(nil, "BORDER")
        iconTex:SetAllPoints()
        row.iconTex = iconTex

        local iconNorm = iconBtn:CreateTexture(nil, "ARTWORK")
        iconNorm:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        iconNorm:SetSize(60, 60)
        iconNorm:SetPoint("CENTER")

        -- Count
        local countText = row:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        countText:SetPoint("BOTTOMRIGHT", iconBtn, -5, 2)
        countText:SetJustifyH("RIGHT")
        row.countText = countText

        -- Subtle 1px row border + clean row background matching native AH
        local rowBorder = row:CreateTexture(nil, "BACKGROUND")
        rowBorder:SetPoint("TOPLEFT", 35, -2)
        rowBorder:SetPoint("BOTTOMRIGHT", 0, 1)
        rowBorder:SetColorTexture(MarketSync.GetThemeColor("headerBorder", 0.35))

        local rowBg = row:CreateTexture(nil, "BORDER")
        rowBg:SetPoint("TOPLEFT", 36, -3)
        rowBg:SetPoint("BOTTOMRIGHT", -1, 2)
        if i % 2 == 0 then
            rowBg:SetColorTexture(MarketSync.GetThemeColor("rowEven"))
        else
            rowBg:SetColorTexture(MarketSync.GetThemeColor("rowOdd"))
        end
        row.rowBg = rowBg

        -- Name text
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetSize(228, 32)
        nameText:SetPoint("TOPLEFT", 43, -3)
        nameText:SetJustifyH("LEFT")
        if nameText.SetWordWrap then nameText:SetWordWrap(false) end
        row.nameText = nameText

        -- Level
        local lvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lvlText:SetSize(38, 32)
        lvlText:SetPoint("TOPLEFT", 275, -3)
        if lvlText.SetWordWrap then lvlText:SetWordWrap(false) end
        row.lvlText = lvlText

        -- Price (moved before Age/Source)
        local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        priceText:SetPoint("TOPLEFT", 315, -3)
        priceText:SetSize(96, 32)
        priceText:SetJustifyH("RIGHT")
        if priceText.SetWordWrap then priceText:SetWordWrap(false) end
        row.priceText = priceText

        -- Age (auction age)
        local ageText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ageText:SetSize(56, 32)
        ageText:SetPoint("TOPLEFT", 418, -3)
        if ageText.SetWordWrap then ageText:SetWordWrap(false) end
        row.ageText = ageText

        -- Source
        local srcText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        srcText:SetSize(53, 32)
        srcText:SetPoint("TOPLEFT", 476, -3)
        if srcText.SetWordWrap then srcText:SetWordWrap(false) end
        row.srcText = srcText

        -- Source Age (when the source scanned it)
        local srcAgeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        srcAgeText:SetSize(58, 32)
        srcAgeText:SetPoint("TOPLEFT", 531, -3)
        if srcAgeText.SetWordWrap then srcAgeText:SetWordWrap(false) end
        row.srcAgeText = srcAgeText

        if not MarketSync.CreateForeverAuctionRowHighlight(row) then
            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
            highlight:SetBlendMode("ADD")
            if highlight.SetAlpha then highlight:SetAlpha(0.38) end
            highlight:SetPoint("TOPLEFT", 35, -2)
            highlight:SetPoint("BOTTOMRIGHT", 0, 1)
            highlight:SetTexCoord(0, 1.0, 0, 0.578125)
        end

        -- Tooltip & Click
        iconBtn:SetScript("OnEnter", function(self)
            row:LockHighlight()
            if row.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(row.link)
                if row.itemData then ScheduleBrowseItemResolution(row.itemData.itemID) end
                GameTooltip:AddLine(" ")
                if GetEffectivePanelSource(panel) == "neutral" then
                    GameTooltip:AddLine("|cff00ccffClick to view Neutral AH analytics|r", 1, 1, 1)
                else
                    GameTooltip:AddLine("|cff00ff00Click to view price history|r", 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        iconBtn:SetScript("OnLeave", function()
            row:UnlockHighlight()
            GameTooltip:Hide()
        end)
        iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        iconBtn:SetScript("OnClick", function(self, button)
            if button == "RightButton" and row.itemData and MarketSync.ShowItemContextMenu then
                MarketSync.ShowItemContextMenu(row, {
                    itemID = row.itemData.itemID,
                    itemLink = row.itemData.link,
                    itemName = row.itemData.name,
                    icon = row.itemData.icon,
                    price = row.itemData.price,
                    dbKey = row.itemData.dbKey,
                })
            elseif row.link and (HandleModifiedItemClick(row.link) or (IsModifiedClick("CHATLINK") and ChatEdit_InsertLink and ChatEdit_InsertLink(row.link))) then
            elseif row.itemData and MarketSync.ShowItemHistory then
                local scope = (GetEffectivePanelSource(panel) == "neutral") and "neutral" or "main"
                MarketSync.ShowItemHistory(
                    row.itemData.dbKey,
                    row.itemData.link,
                    row.itemData.name,
                    row.itemData.icon,
                    row.itemData.price,
                    scope
                )
            end
        end)

        -- Row click (non-icon area) also opens history or context menu
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.itemData and MarketSync.ShowItemContextMenu then
                MarketSync.ShowItemContextMenu(self, {
                    itemID = self.itemData.itemID,
                    itemLink = self.itemData.link,
                    itemName = self.itemData.name,
                    icon = self.itemData.icon,
                    price = self.itemData.price,
                    dbKey = self.itemData.dbKey,
                })
            elseif self.link and (HandleModifiedItemClick(self.link) or (IsModifiedClick("CHATLINK") and ChatEdit_InsertLink and ChatEdit_InsertLink(self.link))) then
            elseif self.itemData and MarketSync.ShowItemHistory then
                local scope = (GetEffectivePanelSource(panel) == "neutral") and "neutral" or "main"
                MarketSync.ShowItemHistory(
                    self.itemData.dbKey,
                    self.itemData.link,
                    self.itemData.name,
                    self.itemData.icon,
                    self.itemData.price,
                    scope
                )
            end
        end)

        -- Row hover tooltip
        row:SetScript("OnEnter", function(self)
            self:LockHighlight()
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                if self.itemData then ScheduleBrowseItemResolution(self.itemData.itemID) end
                GameTooltip:AddLine(" ")
                if GetEffectivePanelSource(panel) == "neutral" then
                    GameTooltip:AddLine("|cff00ccffClick to view Neutral AH analytics|r", 1, 1, 1)
                else
                    GameTooltip:AddLine("|cff00ff00Click to view price history|r", 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self:UnlockHighlight()
            GameTooltip:Hide()
        end)

        row:Hide()
        if tableScrollBar then
            tableScrollBar:AttachMouseWheel(row)
        end
        panel.resultRows[i] = row
    end

    -- Mousewheel scrolling for result pagination
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if self.page > 0 then
                self.page = self.page - 1
                self:UpdateResults()
            end
        else
            local maxPage = math.max(0, math.ceil(#self.currentResults / NUM_RESULTS_TO_DISPLAY) - 1)
            if self.page < maxPage then
                self.page = self.page + 1
                self:UpdateResults()
            end
        end
    end)

    -- --- SEARCH LOGIC ---
    function panel:RunSearch()
        local query = self.searchBox:GetText():lower()
        self.currentResults = {}
        self.page = 0

        local effSource = GetEffectivePanelSource(self)
        local isGuild = (effSource == "guild")
        local isNeutral = (effSource == "neutral")
        local isReady = IsEffectiveSourceReady(self)

        if not isReady then
            if not ShouldAutoBuildSource(self) then
                if self.noResultsText then self.noResultsText:Hide() end
                self:UpdateResults()
                return
            else
                self.noResultsText:SetText("Building index, please wait...")
                self.noResultsText:Show()
                self:UpdateResults()
                if effSource == "datapack" then
                    MarketSync.ForceDataPack = true
                elseif effSource == "latest" then
                    MarketSync.ForceLatest = true
                end
                BuildSearchIndex(function()
                    if self.RefreshStatusFooter then self:RefreshStatusFooter() end
                    self:RunSearch()
                end)
                return
            end
        end

        local activeCat = self.activeCategory
        local activeSub = self.activeSubCategory
        local exactQuery = query:match('^"(.-)"$')
        local isExact = exactQuery ~= nil
        if isExact then
            query = exactQuery
        end

        local minQueryLen = isExact and 1 or 2

        -- Use the appropriate index for this source / historical timeframe
        local index = PersonalIndex
        if self.selectedScanDay then
            index = BuildHistoricalSnapshotIndex(effSource, self.selectedScanDay)
            if self.RefreshStatusFooter then self:RefreshStatusFooter() end
        elseif effSource == "latest" then
            index = LatestIndex
        elseif isGuild then
            index = GuildIndex
        elseif effSource == "datapack" then
            index = DataPackIndex
        elseif isNeutral then
            index = NeutralIndex
        end

        local uniqueResults = {}
        for _, item in pairs(index) do
            local matchesQuery = false
            if not isExact and #query < minQueryLen then
                matchesQuery = true
            elseif isExact then
                matchesQuery = (item.nameLower == query)
            else
                matchesQuery = (item.nameLower:find(query, 1, true) ~= nil)
            end

            local level = tonumber(item.minLevel) or 0
            local matchesLevel = (not self.minLevelFilter or level >= self.minLevelFilter)
                and (not self.maxLevelFilter or level <= self.maxLevelFilter)
            local matchesRarity = not self.rarityFilter or self.rarityFilter[item.rarity or 1] == true
            if matchesQuery and matchesLevel and matchesRarity then
                local matchesCat = (not activeCat) or (item.classID == activeCat)
                if not matchesCat and activeCat == 1 and item.classID == 11 then
                    matchesCat = true
                end
                if matchesCat then
                    local matchesSub = true
                    if self.activeSubIDs then
                        matchesSub = false
                        for _, sid in ipairs(self.activeSubIDs) do
                            if item.subClassID == sid then
                                matchesSub = true
                                break
                            end
                        end
                    elseif activeSub then
                        matchesSub = (item.subClassID == activeSub)
                    end
                    if matchesSub then
                        local existing = uniqueResults[item.dbKey]
                        if not existing or item.price < existing.price then
                            uniqueResults[item.dbKey] = item
                        end
                    end
                end
            end
        end

        for _, item in pairs(uniqueResults) do
            table.insert(self.currentResults, item)
        end

        self:ApplySort()

        if #self.currentResults == 0 then
            if self.selectedScanDay then
                self.noResultsText:SetText("No recorded items found for this historical scan date.")
            elseif isGuild and GuildSyncActive then
                self.noResultsText:SetText("Guild sync in progress... browsing available data.")
            elseif isNeutral and NeutralSyncActive then
                self.noResultsText:SetText("Neutral sync in progress... browsing available data.")
            elseif isNeutral and NeutralTotal == 0 then
                self.noResultsText:SetText("No neutral scan data found. Visit a neutral auction house and run a scan.")
            elseif effSource == "datapack" and DataPackTotal == 0 then
                self.noResultsText:SetText("No Data Pack records loaded. Install or enable MarketSyncData for baseline quotes.")
            elseif effSource == "latest" and LatestTotal == 0 then
                self.noResultsText:SetText("No Auction House data found yet. Run a scan or sync with guildmates.")
            elseif effSource == "personal" and PersonalTotal == 0 then
                self.noResultsText:SetText("No personal scan data found. Please run an Auction House scan to build your offline cache.")
            else
                self.noResultsText:SetText("No results found.")
            end
            self.noResultsText:Show()
        else
            self.noResultsText:Hide()
        end

        self:UpdateResults()
    end

    function panel:UpdateResults()
        local offset = self.page * NUM_RESULTS_TO_DISPLAY
        local total = #self.currentResults

        for i = 1, NUM_RESULTS_TO_DISPLAY do
            local row = self.resultRows[i]
            local idx = offset + i
            if idx <= total then
                local d = self.currentResults[idx]
                row.iconTex:SetTexture(d.icon)
                row.nameText:SetText(d.link or d.name)
                row.lvlText:SetText(d.minLevel > 0 and d.minLevel or "")

                -- Auction Age (how old the listing data is)
                local ageStr = "N/A"
                if d.age or d.exactTime then
                    ageStr = MarketSync.FormatAuctionAge and MarketSync.FormatAuctionAge(d.age, d.exactTime, false) or "N/A"
                end

                -- Source Age (when the source scanned it)
                local srcAgeStr = ""
                if d.exactTime then
                    srcAgeStr = MarketSync.FormatRealmTime(d.exactTime, "%H:%M RT")
                end

                row.ageText:SetText(ageStr)
                row.srcText:SetText(d.source or "")
                row.srcAgeText:SetText(srcAgeStr)
                row.priceText:SetText(FormatMoney(d.price))
                row.countText:SetText("")
                row.link = d.link
                row.itemData = d  -- Store full data for history click
                local rc = RARITY_COLORS[d.rarity]
                if rc then row.nameText:SetTextColor(rc[1], rc[2], rc[3]) end
                row:Show()
            else
                row:Hide()
                row.itemData = nil
            end
        end

        local effSource = GetEffectivePanelSource(self)
        local maxPage = math.max(0, math.ceil(total / NUM_RESULTS_TO_DISPLAY) - 1)
        local statusStr = total .. " results (Page " .. (self.page+1) .. "/" .. (maxPage+1) .. ")"
        -- Show background index progress
        local idxStatus = MarketSync.GetIndexStatus and MarketSync.GetIndexStatus()
        if idxStatus and not self.selectedScanDay then
            local isGuild = (effSource == "guild")
            local isNeutral = (effSource == "neutral")
            local pending = idxStatus.personalPending
            if effSource == "latest" then
                pending = idxStatus.latestPending or 0
            elseif isGuild then
                pending = idxStatus.guildPending
            elseif effSource == "datapack" then
                pending = idxStatus.dataPackPending or 0
            elseif isNeutral then
                pending = idxStatus.neutralPending
            end
            if pending > 0 then
                statusStr = statusStr .. " |cffff8800(" .. pending .. " resolving...)|r"
            end
            if (isGuild or effSource == "latest") and idxStatus.guildSyncActive and idxStatus.guildIncoming > 0 then
                statusStr = statusStr .. " |cff00ff00(" .. idxStatus.guildIncoming .. " incoming)|r"
            elseif isNeutral and idxStatus.neutralSyncActive and idxStatus.neutralIncoming > 0 then
                statusStr = statusStr .. " |cff00ccff(" .. idxStatus.neutralIncoming .. " incoming)|r"
            end
        end
        self.pageText:SetText(statusStr)
        local hasPrev = self.page > 0
        local hasNext = self.page < maxPage
        self.prevBtn:SetEnabled(hasPrev)
        self.nextBtn:SetEnabled(hasNext)
        local pnt = self.prevBtn.GetNormalTexture and self.prevBtn:GetNormalTexture()
        if pnt and pnt.SetVertexColor then
            if hasPrev then pnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) else pnt:SetVertexColor(MarketSync.GetThemeColor("arrowDisabled")) end
        end
        local nnt = self.nextBtn.GetNormalTexture and self.nextBtn:GetNormalTexture()
        if nnt and nnt.SetVertexColor then
            if hasNext then nnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) else nnt:SetVertexColor(MarketSync.GetThemeColor("arrowDisabled")) end
        end
        if self.tableScrollBar then
            self.tableScrollBar:Update(self.page, maxPage)
        end
        local isReady = IsEffectiveSourceReady(self)

        if self.lowRamNotice then
            if not isReady and not ShouldAutoBuildSource(self) then
                local estMB, totalStored = 0, 0
                if MarketSync.GetEstimatedRAMUsage then
                    estMB, totalStored = MarketSync.GetEstimatedRAMUsage()
                end

                if PersonalIndexBuilding then
                    if self.lowRamNotice.title then self.lowRamNotice.title:SetText("|cffffd700Loading Cache into Memory...|r") end
                    self.lowRamNotice.text:SetText("|cffaaaaaaPopulating search records from disk. Please wait a moment...|r")
                    if self.lowRamNotice.btnLoad then
                        self.lowRamNotice.btnLoad:SetText("Loading...")
                        if self.lowRamNotice.btnLoad.SetEnabled then self.lowRamNotice.btnLoad:SetEnabled(false) end
                    end
                else
                    local srcLabel = SOURCE_LABELS[effSource] or "Selected"
                    if self.lowRamNotice.title then
                        self.lowRamNotice.title:SetText("|cffffd700On-Demand Source (" .. srcLabel .. ")|r")
                    end
                    self.lowRamNotice.text:SetText(string.format(
                        "|cffccccccSecondary index '%s' is kept unloaded by Smart Low RAM Mode (~%.1f MB / %d items saved).\n'Latest' stays hot for instant access; click below to load this view on demand.|r",
                        srcLabel, estMB, totalStored
                    ))
                    if self.lowRamNotice.btnLoad then
                        self.lowRamNotice.btnLoad:SetText("⚡ Load Scan Data")
                        if self.lowRamNotice.btnLoad.SetEnabled then self.lowRamNotice.btnLoad:SetEnabled(true) end
                    end
                end
                self.lowRamNotice:Show()
                if self.noResultsText then self.noResultsText:Hide() end
            else
                self.lowRamNotice:Hide()
            end
        end
    end

    function panel:ApplySort()
        local field = self.sortField
        local asc = self.sortAscending
        table.sort(self.currentResults, function(a, b)
            if self.groupByCategory then
                local classA, classB = a.classID or -1, b.classID or -1
                if classA ~= classB then return classA < classB end
                local subA, subB = a.subClassID or -1, b.subClassID or -1
                if subA ~= subB then return subA < subB end
            end
            local va, vb = a[field], b[field]
            if va == nil then va = 0 end
            if vb == nil then vb = 0 end

            if va == vb then
                if field == "minLevel" then
                    -- Secondary Sort: Best rarity first (highest rarity ID)
                    local ra = a.rarity or 0
                    local rb = b.rarity or 0
                    if ra ~= rb then
                        return ra > rb
                    end
                end

                -- Fallback / Tertiary Sort: Alphabetical order (Name string)
                local nameA = (a.nameLower or a.name or "")
                local nameB = (b.nameLower or b.name or "")
                return nameA < nameB
            end

            if asc then return va < vb else return va > vb end
        end)
    end

    if MarketSync.Theme then MarketSync.Theme.Register(panel) end
    return panel
end
-- Force load specific caches on demand
function MarketSync.LoadLatestCache(callback)
    if not LatestIndexReady then
        MarketSync.ForceLatest = true
        BuildSearchIndex(callback)
    elseif callback then
        callback()
    end
end

function MarketSync.LoadPersonalCache(callback)
    if not PersonalIndexReady then
        MarketSync.ForcePersonal = true
        BuildSearchIndex(callback)
    elseif callback then
        callback()
    end
end

function MarketSync.LoadGuildCache(callback)
    if not GuildIndexReady then
        MarketSync.ForceGuild = true
        BuildSearchIndex(callback)
    elseif callback then
        callback()
    end
end

function MarketSync.LoadDataPackCache(callback)
    if not DataPackIndexReady then
        MarketSync.ForceDataPack = true
        BuildSearchIndex(callback)
    elseif callback then
        callback()
    end
end

function MarketSync.LoadNeutralCache(callback)
    if not NeutralIndexReady then
        MarketSync.ForceNeutral = true
        BuildSearchIndex(callback)
    elseif callback then
        callback()
    end
end
