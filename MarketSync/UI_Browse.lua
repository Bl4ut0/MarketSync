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

local PersonalIndex = {}
local GuildIndex = {}
local NeutralIndex = {}
local GuildIncomingBuffer = {}
local NeutralIncomingBuffer = {}

local PersonalIndexReady = false
local PersonalIndexBuilding = false
local GuildIndexReady = false
local NeutralIndexReady = false
local IndexCallbacks = {}

-- Tracking for background resolution
local PersonalPending = {}    -- { dbKey = itemID }
local PersonalDirtyKeys = {}
local personalRefreshScheduled = false
local browsePanels = setmetatable({}, { __mode = "k" })
local GuildPending = {}       -- { dbKey = itemID }
local NeutralPending = {}     -- { dbKey = itemID }
local PersonalTotal = 0
local PersonalResolved = 0
local GuildTotal = 0
local GuildResolved = 0
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
        link = "|c" .. hex .. "|Hitem:" .. itemID .. "|h[" .. name .. "]|h|r"
    else
        -- 2. Fall back to WoW API (may trigger server request)
        local itemType, itemSubType
        name, link, rarity, ilvl, minLevel, itemType, itemSubType, _, _, icon, _, classID, subClassID = C_Item.GetItemInfo(itemID)
        if not name then
            if allowFallback then
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
        if MarketSyncDB and name and not allowFallback then
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
    link = "|c" .. hex .. "|H" .. itemLinkString .. "|h[" .. displayName .. "]|h|r"

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
            exactTime = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime
        end
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

    return {
        name = displayName, nameLower = displayName:lower(), link = link,
        rarity = rarity or 1, ilvl = ilvl or 0, minLevel = minLevel or 0,
        icon = icon, classID = classID, subClassID = subClassID,
        price = price, age = age, dbKey = dbKey, itemID = itemID,
        source = source, exactTime = exactTime,
        hasMeta = (source ~= "Personal"),
    }
end

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
function MarketSync.InvalidateIndexCache()
    PersonalIndexReady = false
    GuildIndexReady = false
    NeutralIndexReady = false
    PersonalIndexBuilding = false
    wipe(PersonalIndex)
    wipe(GuildIndex)
    wipe(NeutralIndex)
    wipe(GuildIncomingBuffer)
    wipe(NeutralIncomingBuffer)
    wipe(PersonalPending)
    wipe(PersonalDirtyKeys)
    personalRefreshScheduled = false
    wipe(GuildPending)
    wipe(NeutralPending)
    PersonalTotal = 0
    GuildTotal = 0
    NeutralTotal = 0
    PersonalResolved = 0
    GuildResolved = 0
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
    local processed = 0
    while processed < 50 do
        local dbKey = next(PersonalDirtyKeys)
        if not dbKey then break end
        PersonalDirtyKeys[dbKey] = nil
        local itemID = ParseItemID(dbKey)
        local wasKnown = PersonalIndex[dbKey] ~= nil or PersonalPending[dbKey] ~= nil
        local wasResolved = PersonalIndex[dbKey] ~= nil
        local data = store[dbKey]
        local entry = data and itemID and BuildIndexEntry(dbKey, itemID, data, "personal") or nil
        PersonalIndex[dbKey] = entry
        PersonalPending[dbKey] = data and itemID and not entry and itemID or nil
        local isKnown = PersonalIndex[dbKey] ~= nil or PersonalPending[dbKey] ~= nil
        if isKnown ~= wasKnown then PersonalTotal = PersonalTotal + (isKnown and 1 or -1) end
        if (entry ~= nil) ~= wasResolved then PersonalResolved = PersonalResolved + (entry and 1 or -1) end
        processed = processed + 1
    end
    if next(PersonalDirtyKeys) then
        if C_Timer and C_Timer.After then C_Timer.After(0, ProcessPersonalDirtyKeys)
        else ProcessPersonalDirtyKeys() end
        return
    end
    personalRefreshScheduled = false
    for panel in pairs(browsePanels) do
        if panel.dataSource == "personal" and panel.IsShown and panel:IsShown() and panel.RunSearch then
            panel:RunSearch()
        end
    end
end

function MarketSync.RefreshPersonalBrowseIndexKeys(keys)
    if type(keys) ~= "table" then return false end
    if not PersonalIndexReady and not PersonalIndexBuilding then return true end
    for dbKey in pairs(keys) do PersonalDirtyKeys[dbKey] = true end
    if PersonalIndexReady and not PersonalIndexBuilding and not personalRefreshScheduled and next(PersonalDirtyKeys) then
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
    if PersonalIndexReady and GuildIndexReady and NeutralIndexReady then
        if callback then callback() end
        return
    end
    if callback then table.insert(IndexCallbacks, callback) end
    if PersonalIndexBuilding then return end
    PersonalIndexBuilding = true

    -- Read cache speed preset
    local speedLevel = (MarketSyncDB and MarketSyncDB.CacheSpeed) or 2
    local preset = MarketSync.CacheSpeedPresets[speedLevel] or MarketSync.CacheSpeedPresets[2]

    PersonalTotal = 0
    PersonalResolved = 0
    GuildTotal = 0
    GuildResolved = 0
    NeutralTotal = 0
    NeutralResolved = 0

    local co = coroutine.create(function()
        local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)
        if not liveStore and not (MarketSyncDB and MarketSync.GetRealmDB().PersonalData) then
            PersonalIndexReady = true; GuildIndexReady = true; NeutralIndexReady = true
            PersonalIndexBuilding = false
            return
        end
        local count = 0
        local totalProcessed = 0
        local currentYieldLimit = 5 -- Start very slow to let UI render first frame instantly
        if MarketSync.LogCacheEvent then
            MarketSync.LogCacheEvent("|cff00ff00[Start]|r Index build started. Personal + Guild + Neutral caches queued.")
        end

        -- 1. BUILD PERSONAL CACHE
        if MarketSyncDB and MarketSync.GetRealmDB().PersonalData then
            if MarketSyncDB.LowRamMode and not PersonalIndexReady and not MarketSync.ForcePersonal then
                if MarketSync.LogCacheEvent then
                    MarketSync.LogCacheEvent("|cffffff00[Personal]|r On-Demand enabled (Low RAM). Skipping Personal index build.")
                end
            elseif not PersonalIndexReady then
                for dbKey, data in pairs(MarketSync.GetRealmDB().PersonalData) do
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
                        if MarketSync.LogCacheEvent then
                            MarketSync.LogCacheEvent(string.format("|cffff8800[Personal]|r Processed %d / ~%d entries (%d resolved, %d pending)", totalProcessed, PersonalTotal, PersonalResolved, PersonalTotal - PersonalResolved))
                        end
                        coroutine.yield()
                        count = 0
                        currentYieldLimit = preset.yieldEvery
                    end
                end
                PersonalIndexReady = true
                MarketSync.ForcePersonal = nil
            end
        else
            PersonalIndexReady = true
        end

        if MarketSync.LogCacheEvent then
            MarketSync.LogCacheEvent(string.format("|cff00ff00[Personal Done]|r %d items resolved, %d pending item data loads.", PersonalResolved, PersonalTotal - PersonalResolved))
        end

        -- 2. BUILD GUILD SYNC CACHE
        if MarketSyncDB.LowRamMode and not GuildIndexReady and not MarketSync.ForceGuild then
            if MarketSync.LogCacheEvent then
                MarketSync.LogCacheEvent("|cff88aaff[Guild]|r On-Demand enabled (Low RAM). Skipping Guild index build.")
            end
        elseif liveStore and not GuildIndexReady then
            for dbKey, data in pairs(liveStore) do
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
                count = count + 1
                totalProcessed = totalProcessed + 1
                if count >= currentYieldLimit then
                    if MarketSync.LogCacheEvent then
                        MarketSync.LogCacheEvent(string.format("|cff88aaff[Guild]|r Processed %d entries so far (%d resolved).", totalProcessed, GuildResolved))
                    end
                    coroutine.yield()
                    count = 0
                    currentYieldLimit = preset.yieldEvery
                end
            end
            GuildIndexReady = true
            MarketSync.ForceGuild = nil
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
        if PersonalIndexReady and next(PersonalDirtyKeys) and not personalRefreshScheduled then
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
        local personalRemove = {}
        local guildRemove = {}
        local neutralRemove = {}
        local pStore = MarketSyncDB and MarketSync.GetRealmDB().PersonalData
        local nStore = MarketSyncDB and MarketSync.GetRealmDB().NeutralData
        local gStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)

        -- Resolve Personal pending
        for dbKey, itemID in pairs(PersonalPending) do
            if processed >= retryBatchSize and not forceFallback then break end
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
            if processed >= retryBatchSize and not forceFallback then break end
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
            if processed >= retryBatchSize and not forceFallback then break end
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

        for _, key in ipairs(personalRemove) do PersonalPending[key] = nil; pendingRetryAttempts[key] = nil end
        for _, key in ipairs(guildRemove) do GuildPending[key] = nil; pendingRetryAttempts[key] = nil end
        for _, key in ipairs(neutralRemove) do NeutralPending[key] = nil; pendingRetryAttempts[key] = nil end

        return processed, #personalRemove + #guildRemove + #neutralRemove
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
            for _ in pairs(PersonalPending) do pRemaining = pRemaining + 1 end
            for _ in pairs(GuildPending) do gRemaining = gRemaining + 1 end
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
        for _ in pairs(PersonalPending) do pRemaining = pRemaining + 1 end
        for _ in pairs(GuildPending) do gRemaining = gRemaining + 1 end
        for _ in pairs(NeutralPending) do nRemaining = nRemaining + 1 end

        if pRemaining == 0 and gRemaining == 0 and nRemaining == 0 then
            activePeriodicRetry:Cancel()
            activePeriodicRetry = nil
            return
        end

        periodicCycleCount = periodicCycleCount + 1
        local forceFallback = (periodicCycleCount >= 6)

        local requested = 0
        for dbKey, itemID in pairs(PersonalPending) do
            if requested >= preset.requests then break end
            C_Item.RequestLoadItemDataByID(itemID)
            requested = requested + 1
        end
        for dbKey, itemID in pairs(GuildPending) do
            if requested >= preset.requests then break end
            if not PersonalPending[dbKey] then
                C_Item.RequestLoadItemDataByID(itemID)
                requested = requested + 1
            end
        end
        for dbKey, itemID in pairs(NeutralPending) do
            if requested >= preset.requests then break end
            C_Item.RequestLoadItemDataByID(itemID)
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
    if not GuildIndexReady then return end  -- Index hasn't been built yet
    local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
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
            -- No active sync, update guild index directly
            local isNewGuild = not GuildIndex[dbKey]
            GuildIndex[dbKey] = entry
            if isNewGuild then
                GuildTotal = GuildTotal + 1
                GuildResolved = GuildResolved + 1
            end
        end
    else
        -- Not cached yet, request it
        if GuildSyncActive then
            -- Mark for incoming resolution
            GuildPending[dbKey] = itemID
        end
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Called when sync session ends â€” merge incoming buffer into live Guild index
function MarketSync.CommitGuildSync()
    local merged = 0
    local removed = 0
    for dbKey, entry in pairs(GuildIncomingBuffer) do
        if entry then
            GuildIndex[dbKey] = entry
            merged = merged + 1
        else
            -- entry is false -> Removal
            if GuildIndex[dbKey] then
                GuildIndex[dbKey] = nil
                removed = removed + 1
            end
        end
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
        C_Item.RequestLoadItemDataByID(itemID)
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
    local pPending, gPending, nPending = 0, 0, 0
    for _ in pairs(PersonalPending) do pPending = pPending + 1 end
    for _ in pairs(GuildPending) do gPending = gPending + 1 end
    for _ in pairs(NeutralPending) do nPending = nPending + 1 end
    return {
        personalReady = PersonalIndexReady,
        personalBuilding = PersonalIndexBuilding,
        personalTotal = PersonalTotal,
        personalResolved = PersonalResolved,
        personalPending = pPending,
        guildReady = GuildIndexReady,
        guildBuilding = PersonalIndexBuilding, -- single build pipeline drives both caches
        guildTotal = GuildTotal,
        guildResolved = GuildResolved,
        guildPending = gPending,
        guildSyncActive = GuildSyncActive,
        guildIncoming = GuildIncomingCount,
        neutralReady = NeutralIndexReady,
        neutralBuilding = PersonalIndexBuilding,
        neutralTotal = NeutralTotal,
        neutralResolved = NeutralResolved,
        neutralPending = nPending,
        neutralSyncActive = NeutralSyncActive,
        neutralIncoming = NeutralIncomingCount,
    }
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
            btn:SetBackdropColor(0.24, 0.18, 0.08, 0.95)
            btn:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.95)
        else
            btn:SetBackdropColor(0.13, 0.12, 0.10, 0.95)
            btn:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.85)
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
                    self:SetBackdropColor(0.32, 0.24, 0.10, 0.98)
                    self:SetBackdropBorderColor(1.0, 0.88, 0.30, 1.0)
                else
                    self:SetBackdropColor(0.22, 0.19, 0.14, 0.95)
                    self:SetBackdropBorderColor(0.95, 0.78, 0.25, 0.95)
                end
            end
            local s = self.GetFontString and self:GetFontString()
            if s and s.SetTextColor then s:SetTextColor(1.0, 0.90, 0.40) end
        end)
        btn:HookScript("OnLeave", function(self)
            if self.SetBackdropColor then
                if isGold then
                    self:SetBackdropColor(0.24, 0.18, 0.08, 0.95)
                    self:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.95)
                else
                    self:SetBackdropColor(0.13, 0.12, 0.10, 0.95)
                    self:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.85)
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

-- ================================================================
-- CREATE BROWSE PANEL
-- ================================================================
function MarketSync.CreateBrowsePanel(parent, dataSourceName)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.dataSource = dataSourceName
    browsePanels[panel] = true

    -- --- Search Bar (matches native AH search bar alignment) ---
    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 80, -46)
    searchBox:SetAutoFocus(false)
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

    -- Search Button
    local searchBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    searchBtn:SetSize(84, 22)
    searchBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    searchBtn:SetText("Search")
    searchBtn:SetScript("OnClick", function() panel:RunSearch() end)

    -- Reset Button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(74, 22)
    resetBtn:SetPoint("LEFT", searchBtn, "RIGHT", 6, 0)
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
        if panel.RefreshAdvancedFilters then panel:RefreshAdvancedFilters() end
        panel:RebuildFilters()
        panel:RunSearch()
    end)

    -- These filters operate on cached item metadata, so they work for personal,
    -- guild, and neutral results without issuing extra AH or item-info queries.
    local filterBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    filterBtn:SetSize(76, 22)
    filterBtn:SetPoint("LEFT", resetBtn, "RIGHT", 6, 0)
    filterBtn:SetText("Filter")

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
    filterPopup:SetBackdropColor(0.035, 0.03, 0.025, 0.97)
    filterPopup:SetBackdropBorderColor(0.75, 0.56, 0.20, 1)
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
    local SIDEBAR_WIDTH = 156
    local SIDEBAR_HEIGHT = 335
    local categoryInset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(panel, 20, -75, SIDEBAR_WIDTH, SIDEBAR_HEIGHT)
    panel.categoryInset = categoryInset

    local tableInset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(panel, 182, -75, 630, 335)
    panel.tableInset = tableInset

    -- Modern vertical scrollbar for results table matching native AH
    local tableScrollBar
    if MarketSync.CreateModernTableScrollBar and tableInset then
        tableScrollBar = MarketSync.CreateModernTableScrollBar(panel, tableInset, function(newPage)
            panel.page = newPage
            panel:UpdateResults()
        end, 8, -24, 10)
        panel.tableScrollBar = tableScrollBar
        tableScrollBar:AttachMouseWheel(tableInset)
    end

    -- Modern slim scrollbar matching native Auction House client
    local scrollName = "MarketSyncBrowse" .. tostring(dataSourceName or "Scan") .. "FilterScroll"
    local filterScroll = CreateFrame("ScrollFrame", scrollName, panel, "UIPanelScrollFrameTemplate")
    filterScroll:SetPoint("TOPLEFT", categoryInset or panel, "TOPLEFT", 2, -3)
    filterScroll:SetSize(SIDEBAR_WIDTH - 22, SIDEBAR_HEIGHT - 8)
    local filterChild = CreateFrame("Frame")
    filterChild:SetSize(SIDEBAR_WIDTH - 22, 800)
    filterScroll:SetScrollChild(filterChild)
    if MarketSync.SkinModernScrollBar then
        MarketSync.SkinModernScrollBar(filterScroll, 8, 4)
    end
    filterScroll:EnableMouseWheel(true)
    filterScroll:SetScript("OnMouseWheel", function(self, delta)
        local step = FILTER_HEIGHT * 3
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

    local function MakeFilterButton(parentFrame, labelText, indent, yOff, btnWidth)
        local w = (btnWidth or 132)
        if indent > 0 then
            w = w - indent
        end
        local isSub = (indent > 0)
        local btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(w, FILTER_HEIGHT)
        btn:SetPoint("TOPLEFT", (indent > 0) and (indent + 2) or 2, -yOff)

        local normalTex = btn:CreateTexture(nil, "BACKGROUND")
        local selectedTex = btn:CreateTexture(nil, "ARTWORK")
        local highlightTex = btn:CreateTexture(nil, "HIGHLIGHT")

        local hasAtlas = normalTex.SetAtlas and pcall(normalTex.SetAtlas, normalTex, isSub and "auctionhouse-nav-button-secondary" or "auctionhouse-nav-button")
        if hasAtlas then
            normalTex:SetAllPoints()
            selectedTex:SetAtlas(isSub and "auctionhouse-nav-button-secondary-select" or "auctionhouse-nav-button-select")
            selectedTex:SetAllPoints()
            highlightTex:SetAtlas(isSub and "auctionhouse-nav-button-secondary-highlight" or "auctionhouse-nav-button-highlight")
            highlightTex:SetAllPoints()
        else
            normalTex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
            normalTex:SetTexCoord(0, 0.53125, 0, 0.625)
            normalTex:SetAllPoints()

            selectedTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            selectedTex:SetColorTexture(0.20, 0.50, 0.90, 0.35)
            selectedTex:SetAllPoints()

            highlightTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            highlightTex:SetColorTexture(1.0, 1.0, 1.0, 0.10)
            highlightTex:SetAllPoints()
        end
        selectedTex:Hide()

        btn.NormalTexture = normalTex
        btn.SelectedTexture = selectedTex
        btn.HighlightTexture = highlightTex

        local text = btn:CreateFontString(nil, "OVERLAY", isSub and "GameFontHighlightSmall" or "GameFontNormalSmall")
        text:SetPoint("LEFT", btn, "LEFT", isSub and 12 or 8, 0)
        text:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(false) end
        text:SetText(labelText)
        btn.Text = text
        btn.text = text

        btn.SetSelected = function(self, isSelected)
            if isSelected then
                if self.SelectedTexture then self.SelectedTexture:Show() end
                if self.NormalTexture then self.NormalTexture:Hide() end
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

        local btnWidth = 132
        local y = 2
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
            y = y + FILTER_HEIGHT + 2

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
                    y = y + FILTER_HEIGHT + 2
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
        {name = "Age",     width = 50,  sortKey = nil},
        {name = "Src",     width = 55,  sortKey = nil},
        {name = "Seen",    width = 60,  sortKey = nil},
        {name = "",        width = 48,  sortKey = nil},
    }
    local colX = 184
    panel.headerButtons = {}
    for i, col in ipairs(colDefs) do
        local hdr = MarketSync.CreateAHColumnHeader and MarketSync.CreateAHColumnHeader(panel, col.width, 20, col.name, col.sortKey)
        if not hdr then
            hdr = CreateFrame("Button", nil, panel, "BackdropTemplate")
            hdr:SetSize(col.width, 20)
            hdr.label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hdr.label:SetPoint("LEFT", 6, 0)
            hdr.label:SetText(col.name)
        end
        hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, -75)
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

    -- --- Prev/Next Buttons (in gold bar, right side) ---
    panel.page = 0
    panel.currentResults = {}

    local prevBtn = CreateFrame("Button", nil, panel)
    prevBtn:SetSize(20, 20)
    prevBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -48, 14)
    prevBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local pnt = prevBtn.GetNormalTexture and prevBtn:GetNormalTexture()
    if pnt and pnt.SetVertexColor then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
    prevBtn:SetScript("OnClick", function()
        if panel.page > 0 then
            panel.page = panel.page - 1
            panel:UpdateResults()
        end
    end)
    panel.prevBtn = prevBtn

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(20, 20)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local nnt = nextBtn.GetNormalTexture and nextBtn:GetNormalTexture()
    if nnt and nnt.SetVertexColor then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
    nextBtn:SetScript("OnClick", function()
        local maxPage = math.floor(#panel.currentResults / NUM_RESULTS_TO_DISPLAY)
        if panel.page < maxPage then
            panel.page = panel.page + 1
            panel:UpdateResults()
        end
    end)
    panel.nextBtn = nextBtn

    -- Page text (in gold bar, left of arrows)
    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.pageText:SetPoint("RIGHT", prevBtn, "LEFT", -8, 0)

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
            lowRamNotice:SetBackdropColor(0.08, 0.08, 0.10, 0.90)
        end
        if lowRamNotice.SetBackdropBorderColor then
            lowRamNotice:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.85)
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
    btnLoad:SetScript("OnClick", function()
        btnLoad:SetText("Loading...")
        if btnLoad.SetEnabled then btnLoad:SetEnabled(false) end
        lowRamText:SetText("|cffffcc00Loading scan records into memory... Please wait.|r")
        local onDone = function()
            btnLoad:SetText("⚡ Load Scan Data")
            if btnLoad.SetEnabled then btnLoad:SetEnabled(true) end
            panel:RunSearch()
        end
        if panel.dataSource == "guild" then
            MarketSync.LoadGuildCache(onDone)
        elseif panel.dataSource == "neutral" then
            MarketSync.LoadNeutralCache(onDone)
        else
            MarketSync.LoadPersonalCache(onDone)
        end
    end)
    btnLoad:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Load Cache on Demand", 1, 0.82, 0)
            GameTooltip:AddLine("Loads scan data for this tab into memory for the current session.", 0.9, 0.9, 0.9, true)
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
            GameTooltip:AddLine("Opens Settings to disable Low RAM Mode for instant searches across all tabs.", 0.9, 0.9, 0.9, true)
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
    panel.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.statusText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 28, 16)
    panel.statusText:SetWidth(200)
    panel.statusText:SetHeight(16)
    panel.statusText:SetJustifyH("LEFT")

    -- --- "Last Guild Sync" LABEL (aligned with Rarity column area) ---
    panel.syncLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.syncLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 195, 16)
    panel.syncLabel:SetHeight(16)
    panel.syncLabel:SetJustifyH("LEFT")

    -- --- ITEM COUNT TEXT (center-left of gold bar) ---
    panel.itemCountText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.itemCountText:SetPoint("BOTTOM", panel, "BOTTOM", -60, 16)
    panel.itemCountText:SetWidth(200)
    panel.itemCountText:SetHeight(16)
    panel.itemCountText:SetJustifyH("CENTER")

    -- --- OnShow: Update status bar and run initial search ---
    panel:SetScript("OnShow", function(self)
        self:RunSearch()
        if self.dataSource == "personal" then
            local personalTime = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime or 0
            local totalItems = 0
            if MarketSyncDB and MarketSync.GetRealmDB().PersonalData then
                for _ in pairs(MarketSync.GetRealmDB().PersonalData) do
                    totalItems = totalItems + 1
                end
            end

            if personalTime > 0 then
                local timeStr = MarketSync.FormatRealmTime(personalTime)
                local myName = UnitName("player") or "You"
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. myName .. "|r")
                self.syncLabel:SetText("|cff00ff00Last Personal Scan|r")
            else
                self.statusText:SetText("|cffff8800No personal scan data|r")
                self.syncLabel:SetText("")
            end
            self.itemCountText:SetText("|cffffd700" .. totalItems .. "|r items")

        elseif self.dataSource == "guild" then
            local latestUser, latestTime = nil, 0
            if MarketSync.GetLatestSyncContributor then
                latestUser, latestTime = MarketSync.GetLatestSyncContributor(false)
            end
            latestTime = tonumber(latestTime) or 0

            -- Check if our personal scan is newer than the latest guild sync
            local personalTime = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime or 0
            if personalTime > latestTime then
                local timeStr = MarketSync.FormatRealmTime(personalTime)
                local myName = UnitName("player") or "You"
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. myName .. "|r")
                self.syncLabel:SetText("|cff00ff00Latest Data|r")
            elseif latestUser then
                local timeStr = MarketSync.FormatRealmTime(latestTime)
                local shortName = latestUser:match("^([^%-]+)") or latestUser
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. shortName .. "|r")
                self.syncLabel:SetText("|cff00ff00Last Guild Sync|r")
            else
                self.statusText:SetText("|cffff8800No sync data yet|r")
                self.syncLabel:SetText("")
            end
            self.itemCountText:SetText("|cffffd700" .. GuildResolved .. "|r items")
        elseif self.dataSource == "neutral" then
            local nCount = 0
            for _ in pairs(MarketSync.GetRealmDB().NeutralData or {}) do
                nCount = nCount + 1
            end
            if MarketSync.GetRealmDB().NeutralScanTime then
                self.statusText:SetText("|cffffd700" .. MarketSync.FormatRealmDateString(MarketSync.GetRealmDB().NeutralScanTime) .. "|r")
                self.syncLabel:SetText("|cff00ccffLast Neutral Scan|r")
            else
                self.statusText:SetText("|cffff8800No neutral data yet|r")
                self.syncLabel:SetText("")
            end
            self.itemCountText:SetText("|cffffd700" .. nCount .. "|r items")
        end
    end)

    -- --- RESULT ROWS ---
    panel.resultRows = {}
    for i = 1, NUM_RESULTS_TO_DISPLAY do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(632, RESULT_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 184, -97 - (i-1) * RESULT_HEIGHT)

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

        -- Modern clean row background matching native AH subtle alternation
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", 34, 0)
        rowBg:SetPoint("BOTTOMRIGHT", 0, 0)
        if i % 2 == 0 then
            rowBg:SetColorTexture(0.10, 0.095, 0.09, 0.50)
        else
            rowBg:SetColorTexture(0.06, 0.055, 0.05, 0.50)
        end
        row.rowBg = rowBg

        local rowHl = row:CreateTexture(nil, "HIGHLIGHT")
        rowHl:SetPoint("TOPLEFT", 34, 0)
        rowHl:SetPoint("BOTTOMRIGHT", 0, 0)
        rowHl:SetColorTexture(0.30, 0.25, 0.12, 0.40)

        -- Name text
        local nameText = row:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
        nameText:SetSize(230, 32)
        nameText:SetPoint("TOPLEFT", 43, -3)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Level
        local lvlText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        lvlText:SetSize(38, 32)
        lvlText:SetPoint("TOPLEFT", 275, -3)
        row.lvlText = lvlText

        -- Price (moved before Age/Source)
        local priceText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        priceText:SetPoint("TOPLEFT", 315, -3)
        priceText:SetSize(95, 32)
        priceText:SetJustifyH("RIGHT")
        row.priceText = priceText

        -- Age (auction age in days)
        local ageText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        ageText:SetSize(48, 32)
        ageText:SetPoint("TOPLEFT", 413, -3)
        row.ageText = ageText

        -- Source
        local srcText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        srcText:SetSize(53, 32)
        srcText:SetPoint("TOPLEFT", 463, -3)
        row.srcText = srcText

        -- Source Age (when the source scanned it)
        local srcAgeText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        srcAgeText:SetSize(58, 32)
        srcAgeText:SetPoint("TOPLEFT", 518, -3)
        row.srcAgeText = srcAgeText

        -- Highlight
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
        highlight:SetBlendMode("ADD")
        highlight:SetSize(594, 32)
        highlight:SetPoint("TOPLEFT", 33, -3)
        highlight:SetTexCoord(0, 1.0, 0, 0.578125)

        -- Tooltip & Click
        iconBtn:SetScript("OnEnter", function(self)
            row:LockHighlight()
            if row.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(row.link)
                GameTooltip:AddLine(" ")
                if panel.dataSource == "neutral" then
                    GameTooltip:AddLine("|cff00ccffNeutral cache item|r", 1, 1, 1)
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
            elseif row.link and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(row.link)
            elseif panel.dataSource ~= "neutral" and row.itemData and MarketSync.ShowItemHistory then
                MarketSync.ShowItemHistory(
                    row.itemData.dbKey,
                    row.itemData.link,
                    row.itemData.name,
                    row.itemData.icon,
                    row.itemData.price
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
            elseif self.link and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(self.link)
            elseif panel.dataSource ~= "neutral" and self.itemData and MarketSync.ShowItemHistory then
                MarketSync.ShowItemHistory(
                    self.itemData.dbKey,
                    self.itemData.link,
                    self.itemData.name,
                    self.itemData.icon,
                    self.itemData.price
                )
            end
        end)

        -- Row hover tooltip
        row:SetScript("OnEnter", function(self)
            self:LockHighlight()
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:AddLine(" ")
                if panel.dataSource == "neutral" then
                    GameTooltip:AddLine("|cff00ccffNeutral cache item|r", 1, 1, 1)
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

        local isGuild = self.dataSource == "guild"
        local isNeutral = self.dataSource == "neutral"
        local isReady = (isGuild and GuildIndexReady) or (isNeutral and NeutralIndexReady) or (not isGuild and not isNeutral and PersonalIndexReady)

        if not isReady then
            if MarketSyncDB and MarketSyncDB.LowRamMode then
                if self.noResultsText then self.noResultsText:Hide() end
                self:UpdateResults()
                return
            else
                self.noResultsText:SetText("Building index, please wait...")
                self.noResultsText:Show()
                self:UpdateResults()
                BuildSearchIndex(function() self:RunSearch() end)
                return
            end
        end

        local activeCat = self.activeCategory
        local activeSub = self.activeSubCategory
        local isGuild = self.dataSource == "guild"
        local isNeutral = self.dataSource == "neutral"
        local exactQuery = query:match('^"(.-)"$')
        local isExact = exactQuery ~= nil
        if isExact then
            query = exactQuery
        end

        local minQueryLen = isExact and 1 or 2

        -- Use the appropriate index for this tab
        local index = PersonalIndex
        if isGuild then
            index = GuildIndex
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
            if isGuild and GuildSyncActive then
                self.noResultsText:SetText("Guild sync in progress... browsing available data.")
            elseif isNeutral and NeutralSyncActive then
                self.noResultsText:SetText("Neutral sync in progress... browsing available data.")
            elseif isNeutral and NeutralTotal == 0 then
                self.noResultsText:SetText("No neutral scan data found. Visit a neutral auction house and run a scan.")
            elseif not isGuild and PersonalTotal == 0 then
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

        local maxPage = math.max(0, math.ceil(total / NUM_RESULTS_TO_DISPLAY) - 1)
        local statusStr = total .. " results (Page " .. (self.page+1) .. "/" .. (maxPage+1) .. ")"
        -- Show background index progress
        local idxStatus = MarketSync.GetIndexStatus and MarketSync.GetIndexStatus()
        if idxStatus then
            local isGuild = self.dataSource == "guild"
            local isNeutral = self.dataSource == "neutral"
            local pending = idxStatus.personalPending
            if isGuild then
                pending = idxStatus.guildPending
            elseif isNeutral then
                pending = idxStatus.neutralPending
            end
            if pending > 0 then
                statusStr = statusStr .. " |cffff8800(" .. pending .. " resolving...)|r"
            end
            if isGuild and idxStatus.guildSyncActive and idxStatus.guildIncoming > 0 then
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
            if hasPrev then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else pnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        local nnt = self.nextBtn.GetNormalTexture and self.nextBtn:GetNormalTexture()
        if nnt and nnt.SetVertexColor then
            if hasNext then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else nnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        if self.tableScrollBar then
            self.tableScrollBar:Update(self.page, maxPage)
        end
        local isGuild = self.dataSource == "guild"
        local isNeutral = self.dataSource == "neutral"
        local isReady = (isGuild and GuildIndexReady) or (isNeutral and NeutralIndexReady) or (not isGuild and not isNeutral and PersonalIndexReady)

        if self.lowRamNotice then
            if not isReady and MarketSyncDB and MarketSyncDB.LowRamMode then
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
                    if self.lowRamNotice.title then self.lowRamNotice.title:SetText("|cffffd700Low RAM Mode Active|r") end
                    self.lowRamNotice.text:SetText(string.format(
                        "|cffccccccSearch index is not loaded in memory to keep the addon lightweight.\nEstimated memory saved: ~%.1f MB (%d items stored).\nScanner, price checks, and analytics remain fully accessible.|r",
                        estMB, totalStored
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

    return panel
end
-- Force load specific caches on demand
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

function MarketSync.LoadNeutralCache(callback)
    if not NeutralIndexReady then
        MarketSync.ForceNeutral = true
        BuildSearchIndex(callback)
    elseif callback then
        callback()
    end
end
