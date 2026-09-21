-- =============================================================
-- MarketSync - Core Module
-- Shared globals, database, and helper functions
-- =============================================================

MarketSync = MarketSync or {}

local ADDON_NAME = "MarketSync"
local PREFIX = "MarketSync"

MarketSync.ADDON_NAME = ADDON_NAME
MarketSync.PREFIX = PREFIX
MarketSync.ICON_COIN = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"

-- Robust helper to get addon metadata across different WoW versions
function MarketSync.GetAddOnMetadata(addon, field)
    -- Modern WoW (10.0+)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    -- Legacy WoW
    elseif GetAddOnMetadata then
        return GetAddOnMetadata(addon, field)
    end
    return nil
end

-- Cross-version item information helpers (Modern C_Item vs Legacy global)
function MarketSync.GetItemInfo(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif GetItemInfo then
        return GetItemInfo(item)
    end
    return nil
end

function MarketSync.GetItemInfoInstant(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    elseif GetItemInfoInstant then
        return GetItemInfoInstant(item)
    end
    return nil
end

function MarketSync.GetDetailedItemLevelInfo(item)
    if not item then return 0 end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        return C_Item.GetDetailedItemLevelInfo(item)
    elseif GetDetailedItemLevelInfo then
        return GetDetailedItemLevelInfo(item)
    end
    return 0
end

function MarketSync.GetItemIcon(item)
    if not item then return nil end
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(item)
    elseif GetItemIcon then
        return GetItemIcon(item)
    end
    return nil
end

-- ================================================================
-- BASE-36 ENCODING / DECODING
-- Compresses numeric payloads by ~30% (e.g. "50000" -> "11cg")
-- ================================================================
local B36_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

function MarketSync.ToBase36(n)
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

function MarketSync.FromBase36(s)
    if not s or s == "" then return 0 end
    return tonumber(s, 36) or 0
end

-- ================================================================
-- GRANULAR TIME-SERIES
-- Maps the current UNIX time into a 30-minute tracking bucket
-- ================================================================
function MarketSync.GetCurrentBucket()
    -- Delegate to active provider (e.g. Unix 30-min bucket on Forever, Auctionator epoch on legacy)
    if MarketSync.Provider and MarketSync.Provider.GetCurrentBucket then
        return MarketSync.Provider.GetCurrentBucket()
    end
    local dayZero = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 or 1600000000
    return math.floor((time() - dayZero) / 1800)
end

-- Main prefix for control messages (ADV, PULL, ACCEPT, REQ, RES, ERR)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- Data channel prefixes for parallel BRES bulk transfers.
-- Each prefix gets its own token bucket (10 burst, 1/sec regen).
-- 5 channels = 5 msg/sec sustained = ~80 items/sec with base-36 encoding.
MarketSync.DATA_PREFIXES = { "MSyncD1", "MSyncD2", "MSyncD3", "MSyncD4", "MSyncD5" }
for _, dp in ipairs(MarketSync.DATA_PREFIXES) do
    C_ChatInfo.RegisterAddonMessagePrefix(dp)
end

-- ================================================================
-- DEBUG
-- ================================================================
function MarketSync.Debug(msg)
    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync Debug]|r", msg)
    end
end

-- ================================================================
-- LINK-AWARE EDITBOX SUPPORT
-- Shift-click item links into focused addon editboxes without hijacking chat.
-- ================================================================
local _msLinkAware = {
    installed = false,
    originalInsertLink = nil,
    activeEditBox = nil,
    registry = setmetatable({}, { __mode = "k" }),
}

local function InstallLinkAwareInsertHook()
    if _msLinkAware.installed then return end
    _msLinkAware.installed = true
    _msLinkAware.originalInsertLink = ChatEdit_InsertLink

    ChatEdit_InsertLink = function(text, ...)
        -- If chat has focus, never interfere.
        local activeChat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() or nil
        if activeChat and activeChat:IsShown() and activeChat:HasFocus() and _msLinkAware.originalInsertLink then
            return _msLinkAware.originalInsertLink(text, ...)
        end

        local editBox = _msLinkAware.activeEditBox
        local opts = editBox and _msLinkAware.registry[editBox] or nil
        if editBox and opts and text and editBox:IsShown() and editBox:HasFocus() then
            if type(opts.onInsertLink) == "function" then
                local ok, handled = pcall(opts.onInsertLink, editBox, text)
                if ok and handled then
                    return true
                end
            end
            if editBox.Insert then
                editBox:Insert(text)
                return true
            end
        end

        if _msLinkAware.originalInsertLink then
            return _msLinkAware.originalInsertLink(text, ...)
        end
        return false
    end
end

function MarketSync.RegisterLinkAwareEditBox(editBox, opts)
    if not editBox then return end
    InstallLinkAwareInsertHook()
    _msLinkAware.registry[editBox] = opts or {}

    editBox:HookScript("OnEditFocusGained", function(self)
        _msLinkAware.activeEditBox = self
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        if _msLinkAware.activeEditBox == self then
            _msLinkAware.activeEditBox = nil
        end
    end)
    editBox:HookScript("OnHide", function(self)
        if _msLinkAware.activeEditBox == self then
            _msLinkAware.activeEditBox = nil
        end
    end)
end

-- ================================================================
-- DATABASE INITIALIZATION
-- ================================================================
function MarketSync.InitializeDB()
    if not MarketSyncDB then
        MarketSyncDB = {
            BlockedUsers = {},
            PassiveSync = true,
            DebugMode = false,
            EnableChatPriceCheck = true,
            EnableNotificationSounds = true,
            BuildCacheOnStartup = true,
            LowRamMode = false,
            OnDemandPersonal = false,
            OnDemandGuild = false,
            OnDemandNeutral = false,
            CacheSpeed = 2,
            ItemMetadata = {},
            HistoryLog = {},
            MinimapIcon = { hide = false, angle = 3.75 },
            PersonalData = {},
            NotificationSoundID = 8959, -- Raid Warning
            NotificationVolume = 1.0,
            NotificationMode = "on_scan",
            PerNotificationSounds = {},
        }
    end
    if not MarketSyncDB.HistoryLog then MarketSyncDB.HistoryLog = {} end
    if not MarketSyncDB.BlockedUsers then MarketSyncDB.BlockedUsers = {} end
    if MarketSyncDB.PassiveSync == nil then MarketSyncDB.PassiveSync = true end
    if MarketSyncDB.EnableNeutralSync == nil then MarketSyncDB.EnableNeutralSync = true end
    if MarketSyncDB.DebugMode == nil then MarketSyncDB.DebugMode = false end
    if MarketSyncDB.EnableChatPriceCheck == nil then MarketSyncDB.EnableChatPriceCheck = true end
    if MarketSyncDB.EnableTooltipProb == nil then MarketSyncDB.EnableTooltipProb = true end
    if MarketSyncDB.EnableTooltipAuctionPrice == nil then MarketSyncDB.EnableTooltipAuctionPrice = true end
    if MarketSyncDB.EnableNotificationSounds == nil then MarketSyncDB.EnableNotificationSounds = true end
    if MarketSyncDB.BuildCacheOnStartup == nil then MarketSyncDB.BuildCacheOnStartup = true end
    if not MarketSyncDB.CacheSpeed then MarketSyncDB.CacheSpeed = 2 end
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false, angle = 3.75 } end
    if not MarketSyncDB.NotificationSoundID then MarketSyncDB.NotificationSoundID = 8959 end
    if not MarketSyncDB.NotificationVolume then MarketSyncDB.NotificationVolume = 1.0 end
    if not MarketSyncDB.NotificationMode then MarketSyncDB.NotificationMode = "on_scan" end
    if not MarketSyncDB.AlertUndercutPct then MarketSyncDB.AlertUndercutPct = 10 end
    -- Legacy PurgeCycleDays is superseded by tiered retention (Hot/Warm/Cold/Purge).
    -- Default to 180 days (6 months of weekly macro-history) if not set.
    if MarketSyncDB.PurgeCycleDays == nil then MarketSyncDB.PurgeCycleDays = 180 end
    if MarketSyncDB.RetentionVersion == nil then MarketSyncDB.RetentionVersion = 1 end
    -- Persistent item info cache (global, not per-realm — item metadata is universal)
    -- Stores name/icon/rarity/classID so items only need to be fetched from WoW server once
    if not MarketSyncDB.ItemInfoCache then MarketSyncDB.ItemInfoCache = {} end

    if MarketSyncDB.AllowSyncInCombat == nil then MarketSyncDB.AllowSyncInCombat = true end
    if MarketSyncDB.AllowSyncInRaid == nil then MarketSyncDB.AllowSyncInRaid = false end
    if MarketSyncDB.AllowSyncInDungeon == nil then MarketSyncDB.AllowSyncInDungeon = false end
    if MarketSyncDB.AllowSyncInPvP == nil then MarketSyncDB.AllowSyncInPvP = false end
    if MarketSyncDB.AllowSyncInArena == nil then MarketSyncDB.AllowSyncInArena = false end

    if MarketSyncDB.AllowCacheInCombat == nil then MarketSyncDB.AllowCacheInCombat = true end
    if MarketSyncDB.AllowCacheInRaid == nil then MarketSyncDB.AllowCacheInRaid = false end
    if MarketSyncDB.AllowCacheInDungeon == nil then MarketSyncDB.AllowCacheInDungeon = false end
    if MarketSyncDB.AllowCacheInPvP == nil then MarketSyncDB.AllowCacheInPvP = false end
    if MarketSyncDB.AllowCacheInArena == nil then MarketSyncDB.AllowCacheInArena = false end
    
    if not MarketSyncDB.RealmData then MarketSyncDB.RealmData = {} end

    -- MIGRATION: Move old global data to the current realm's partition on first load
    local realm = GetNormalizedRealmName() or GetRealmName()
    if realm and not MarketSyncDB.RealmData[realm] then
        MarketSyncDB.RealmData[realm] = {
            PersonalData = MarketSyncDB.PersonalData or {},
            ItemMetadata = MarketSyncDB.ItemMetadata or {},
            HistoryLog = MarketSyncDB.HistoryLog or {},
            PersonalScanTime = MarketSyncDB.PersonalScanTime,
            NeutralData = {},
            NeutralMeta = {},
            NeutralSync = {},
            NeutralScanTime = nil,
            NeutralSwarmTSF = nil,
            KnownCraftingRecipesByCharacter = {},
            KnownProfessionsByCharacter = {},
            NotificationRequests = {},
            NotificationState = {},
            NotificationSettings = {
                rearmBufferPct = 5,
                rearmAfterSec = 1800,
                defaultCooldownSec = 300,
            },
        }
    end
    
    -- Cleanup old global data
    MarketSyncDB.PersonalData = nil
    MarketSyncDB.ItemMetadata = nil
    MarketSyncDB.HistoryLog = nil
    MarketSyncDB.SyncStats = nil
    MarketSyncDB.WeeklySyncStats = nil
    MarketSyncDB.PersonalScanTime = nil

    -- MIGRATION (v0.5.2 → v0.5.3): Seed SwarmTSF from PersonalScanTime if missing.
    -- Without this, the first ADV after upgrade would broadcast TSF=0, making other
    -- clients think we have no freshness data and triggering an unnecessary PULL.
    local realmDB = MarketSyncDB.RealmData[realm]
    if realmDB and realmDB.PersonalScanTime and not realmDB.SwarmTSF then
        realmDB.SwarmTSF = realmDB.PersonalScanTime
    end

    if realmDB then
        if not realmDB.NeutralData then realmDB.NeutralData = {} end
        if not realmDB.NeutralMeta then realmDB.NeutralMeta = {} end
        if not realmDB.NeutralSync then realmDB.NeutralSync = {} end
        if not realmDB.KnownCraftingRecipesByCharacter then realmDB.KnownCraftingRecipesByCharacter = {} end
        if not realmDB.KnownProfessionsByCharacter then realmDB.KnownProfessionsByCharacter = {} end
        if not realmDB.NotificationRequests then realmDB.NotificationRequests = {} end
        if not realmDB.NotificationState then realmDB.NotificationState = {} end
        realmDB.SyncStats = nil
        realmDB.WeeklySyncStats = nil
        if not realmDB.NotificationSettings then
            realmDB.NotificationSettings = {
                rearmBufferPct = 5,
                rearmAfterSec = 1800,
                defaultCooldownSec = 300,
            }
        end
    end

    if MarketSync.Favorites and MarketSync.Favorites.Initialize then
        MarketSync.Favorites.Initialize()
    end
end

-- Fast helper function to get the partitioned database for the current realm
function MarketSync.GetRealmDB()
    local realm = GetNormalizedRealmName() or GetRealmName()
    if not realm or not MarketSyncDB or not MarketSyncDB.RealmData then return {} end
    if not MarketSyncDB.RealmData[realm] then
        MarketSyncDB.RealmData[realm] = {
            PersonalData = {},
            ItemMetadata = {},
            HistoryLog = {},
            NeutralData = {},
            NeutralMeta = {},
            NeutralSync = {},
            NeutralScanTime = nil,
            NeutralSwarmTSF = nil,
            KnownCraftingRecipesByCharacter = {},
            KnownProfessionsByCharacter = {},
            NotificationRequests = {},
            NotificationState = {},
            NotificationSettings = {
                rearmBufferPct = 5,
                rearmAfterSec = 1800,
                defaultCooldownSec = 300,
            },
        }
    end
    local realmDB = MarketSyncDB.RealmData[realm]
    if not realmDB.NeutralData then realmDB.NeutralData = {} end
    if not realmDB.NeutralMeta then realmDB.NeutralMeta = {} end
    if not realmDB.NeutralSync then realmDB.NeutralSync = {} end
    if not realmDB.KnownCraftingRecipesByCharacter then realmDB.KnownCraftingRecipesByCharacter = {} end
    if not realmDB.KnownProfessionsByCharacter then realmDB.KnownProfessionsByCharacter = {} end
    if not realmDB.NotificationRequests then realmDB.NotificationRequests = {} end
    if not realmDB.NotificationState then realmDB.NotificationState = {} end
    realmDB.SyncStats = nil
    realmDB.WeeklySyncStats = nil
    if not realmDB.NotificationSettings then
        realmDB.NotificationSettings = {
            rearmBufferPct = 5,
            rearmAfterSec = 1800,
            defaultCooldownSec = 300,
        }
    end
    return realmDB
end

-- ================================================================
-- CACHE SPEED PRESETS
-- ================================================================
-- Each level controls: batch size per tick, retry interval, re-request count, coroutine yield frequency, resolve debounce
MarketSync.CacheSpeedPresets = {
    [1] = { name = "Conservative",  batchSize = 25,  interval = 1.5,  requests = 5,    yieldEvery = 20,  resolveDelay = 1.0,  desc = "|cff888888Minimal CPU impact. Best for older hardware.\\nVery smooth but slower indexing.|r" },
    [2] = { name = "Balanced",      batchSize = 50,  interval = 0.8,  requests = 8,    yieldEvery = 50,  resolveDelay = 0.5,  desc = "|cff888888Good balance. Smooth performance for most PCs.\\nRecommended default.|r" },
    [3] = { name = "Aggressive",    batchSize = 100, interval = 0.5,  requests = 12,   yieldEvery = 100, resolveDelay = 0.3,  desc = "|cff888888Faster indexing with potential minor stutter.\\nUse if you have a high-end CPU.|r" },
    [4] = { name = "Maximum",       batchSize = 200, interval = 0.25, requests = 20,   yieldEvery = 200, resolveDelay = 0.1,  desc = "|cffff8800Fastest possible. Will likely cause frame drops.\\nOnly use if you want it done NOW.|r" },
}

-- ================================================================
-- BLOCK / TRACK FUNCTIONS
-- ================================================================
function MarketSync.IsBlocked(user)
    return MarketSyncDB and MarketSyncDB.BlockedUsers and MarketSyncDB.BlockedUsers[user]
end

function MarketSync.ToggleBlock(user)
    if not MarketSyncDB then MarketSync.InitializeDB() end
    if MarketSyncDB.BlockedUsers[user] then
        MarketSyncDB.BlockedUsers[user] = nil
        print(string.format("|cFF00FF00[MarketSync]|r Unblocked %s.", user))
    else
        MarketSyncDB.BlockedUsers[user] = true
        print(string.format("|cFFFF0000[MarketSync]|r Blocked %s.", user))
    end
end

function MarketSync.TrackSync(sender, count)
    return
end

local SyncContributorCache = {
    builtAt = 0,
    list = {},
    latestUser = nil,
    latestTime = 0,
}

local function NormalizeContributor(source)
    if not source or source == "" then return nil end
    if source == "Personal" or source == "Unknown" then return nil end
    return tostring(source)
end

local function BuildSyncContributorCache()
    local realmDB = MarketSync.GetRealmDB()
    local seen = {}
    local list = {}
    local latestUser, latestTime = nil, 0

    if realmDB and realmDB.ItemMetadata then
        for _, meta in pairs(realmDB.ItemMetadata) do
            if type(meta) == "table" then
                local source = NormalizeContributor(meta.lastSource or meta.source)
                local stamp = tonumber(meta.lastTime or meta.time) or 0
                if source and not seen[source] then
                    seen[source] = true
                    table.insert(list, source)
                end
                if source and stamp > latestTime then
                    latestTime = stamp
                    latestUser = source
                end
            end
        end
    end

    if realmDB and realmDB.NeutralMeta then
        for _, meta in pairs(realmDB.NeutralMeta) do
            if type(meta) == "table" then
                local source = NormalizeContributor(meta.source)
                local stamp = tonumber(meta.time) or 0
                if source and not seen[source] then
                    seen[source] = true
                    table.insert(list, source)
                end
                if source and stamp > latestTime then
                    latestTime = stamp
                    latestUser = source
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    SyncContributorCache.builtAt = time()
    SyncContributorCache.list = list
    SyncContributorCache.latestUser = latestUser
    SyncContributorCache.latestTime = latestTime
end

function MarketSync.InvalidateSyncContributorCache()
    SyncContributorCache.builtAt = 0
    SyncContributorCache.list = {}
    SyncContributorCache.latestUser = nil
    SyncContributorCache.latestTime = 0
end

function MarketSync.GetSyncContributorSnapshot(forceRebuild)
    local now = time()
    if forceRebuild or (now - (SyncContributorCache.builtAt or 0)) >= 10 then
        BuildSyncContributorCache()
    end

    local out = {}
    for i, name in ipairs(SyncContributorCache.list or {}) do
        out[i] = name
    end

    return out, SyncContributorCache.latestUser, SyncContributorCache.latestTime
end

function MarketSync.GetLatestSyncContributor(forceRebuild)
    local _, latestUser, latestTime = MarketSync.GetSyncContributorSnapshot(forceRebuild)
    return latestUser, latestTime
end

-- ================================================================
-- TIERED RETENTION: Compact Record Helpers
-- ================================================================
-- Compact format uses prefix markers to distinguish from raw bucket strings:
--   Raw:    "5:b4:a,11:b2:c,23:b6:8"   (bucketOffset:b36price:b36qty, ...)
--   Daily:  "D:b36min:b36max:b36avg:b36vol"   (D = daily summary)
--   Weekly: "W:b36min:b36max:b36avg:b36vol"   (W = weekly summary)

-- Tier boundaries (days from current scan day)
MarketSync.RETENTION_HOT_DAYS  = 7    -- Full 30-min resolution (synced)
MarketSync.RETENTION_WARM_DAYS = 30   -- Daily summaries (local)
MarketSync.RETENTION_COLD_DAYS = 180  -- Weekly summaries (local, 6 months)

function MarketSync.IsCompactRecord(str)
    if not str or type(str) ~= "string" or #str < 2 then return false end
    local prefix = str:sub(1, 2)
    return prefix == "D:" or prefix == "W:"
end

-- Compacts a raw 30-min bucket string into a daily summary "D:min:max:avg:vol"
function MarketSync.CompactDayString(histStr)
    if not histStr or histStr == "" then return nil end
    if MarketSync.IsCompactRecord(histStr) then return histStr end

    local minPrice, maxPrice, sumPrice, totalVol, count = math.huge, 0, 0, 0, 0
    for _, p_b36, q_b36 in string.gmatch(histStr, "(%d+):([%w%-]+):([%w%-]+)") do
        local price = MarketSync.FromBase36(p_b36)
        local qty = MarketSync.FromBase36(q_b36)
        if price > 0 then
            if price < minPrice then minPrice = price end
            if price > maxPrice then maxPrice = price end
            sumPrice = sumPrice + price
            totalVol = totalVol + qty
            count = count + 1
        end
    end
    if count == 0 then return nil end
    local avg = math.floor(sumPrice / count)
    return string.format("D:%s:%s:%s:%s",
        MarketSync.ToBase36(minPrice), MarketSync.ToBase36(maxPrice),
        MarketSync.ToBase36(avg), MarketSync.ToBase36(totalVol))
end

-- Parses a compact record string. Returns nil if not compact.
-- Returns: { type="daily"|"weekly", min=N, max=N, avg=N, volume=N }
function MarketSync.ParseCompactRecord(str)
    if not str or type(str) ~= "string" or #str < 2 then return nil end
    local prefix = str:sub(1, 1)
    if prefix ~= "D" and prefix ~= "W" then return nil end
    local minB36, maxB36, avgB36, volB36 = str:match("^[DW]:([%w%-]+):([%w%-]+):([%w%-]+):([%w%-]+)$")
    if not minB36 then return nil end
    return {
        type = (prefix == "D") and "daily" or "weekly",
        min = MarketSync.FromBase36(minB36),
        max = MarketSync.FromBase36(maxB36),
        avg = MarketSync.FromBase36(avgB36),
        volume = MarketSync.FromBase36(volB36),
    }
end

-- Merges two compact records into one combined weekly summary.
-- Used when aggregating daily compacts into weekly summaries.
function MarketSync.MergeCompactRecords(a, b)
    if not a then return b end
    if not b then return a end
    local aVol = a.volume or 1
    local bVol = b.volume or 1
    local totalVol = aVol + bVol
    local aWeight = (a.avg or 0) * aVol
    local bWeight = (b.avg or 0) * bVol
    local mergedAvg = totalVol > 0 and math.floor((aWeight + bWeight) / totalVol) or math.floor(((a.avg or 0) + (b.avg or 0)) / 2)
    return {
        type = "weekly",
        min = math.min(a.min or math.huge, b.min or math.huge),
        max = math.max(a.max or 0, b.max or 0),
        avg = mergedAvg,
        volume = totalVol,
    }
end

-- ================================================================
-- METADATA PRUNING (Hybrid Retention Policy)
-- ================================================================
-- Prevents unbounded RAM growth from ItemMetadata accumulation.
-- Tier 1: Cap per-item `days` sub-tables to the N most recent scan days.
-- Tier 2: Remove entire metadata entries for items not seen in 30 days.
-- Designed to run once per login (deferred, low-priority).
local MAX_DAYS_PER_ITEM = 7          -- Keep only the 7 most recent day entries per item
local STALE_THRESHOLD_SECONDS = 30 * 86400  -- 30 days in seconds

function MarketSync.PruneMetadata()
    local realmDB = MarketSync.GetRealmDB()
    if not realmDB or not realmDB.ItemMetadata then return end

    local now = time()
    local prunedItems = 0      -- Entire entries removed (stale)
    local trimmedDays = 0      -- Individual day sub-entries trimmed
    local totalItems = 0

    for key, meta in pairs(realmDB.ItemMetadata) do
        totalItems = totalItems + 1

        -- TIER 2: Remove entire entry if lastTime is older than 30 days
        local lastTime = meta.lastTime or meta.time or 0
        if lastTime > 0 and (now - lastTime) > STALE_THRESHOLD_SECONDS then
            realmDB.ItemMetadata[key] = nil
            prunedItems = prunedItems + 1
        else
            -- TIER 1: Cap days sub-table to MAX_DAYS_PER_ITEM most recent entries
            if meta.days then
                -- Collect all day keys and sort descending (most recent first)
                local dayKeys = {}
                for dayStr in pairs(meta.days) do
                    dayKeys[#dayKeys + 1] = dayStr
                end

                if #dayKeys > MAX_DAYS_PER_ITEM then
                    table.sort(dayKeys, function(a, b)
                        return (tonumber(a) or 0) > (tonumber(b) or 0)
                    end)

                    -- Remove entries beyond the cap
                    for i = MAX_DAYS_PER_ITEM + 1, #dayKeys do
                        meta.days[dayKeys[i]] = nil
                        trimmedDays = trimmedDays + 1
                    end
                end
            end
        end
    end

    if prunedItems > 0 or trimmedDays > 0 then
        MarketSync.Debug(string.format(
            "PruneMetadata: %d/%d stale items removed, %d day-entries trimmed (cap: %d days/item, stale: %dd)",
            prunedItems, totalItems, trimmedDays, MAX_DAYS_PER_ITEM, STALE_THRESHOLD_SECONDS / 86400
        ))
        if MarketSyncDB and MarketSyncDB.DebugMode then
            print(string.format(
                "|cFF00FF00[MarketSync]|r Pruned metadata: %d stale items removed, %d day-entries trimmed.",
                prunedItems, trimmedDays
            ))
        end
    end
end

-- ================================================================
-- TIME FORMATTING HELPER
-- ================================================================
function MarketSync.FormatRealmTime(timestamp, formatStr)
    if not timestamp then return "" end
    formatStr = formatStr or "%H:%M RT"
    
    local sHour, sMinute = GetGameTime()
    local lDate = date("*t")
    
    local sTotal = sHour * 60 + sMinute
    local lTotal = lDate.hour * 60 + lDate.min
    
    local diffMins = sTotal - lTotal
    
    -- Handle day wrapping across time zones
    if diffMins > 12 * 60 then
        diffMins = diffMins - 24 * 60
    elseif diffMins < -12 * 60 then
        diffMins = diffMins + 24 * 60
    end
    
    local adjustedTime = timestamp + (diffMins * 60)
    return date(formatStr, adjustedTime)
end

function MarketSync.FormatRealmDateString(timestamp)
    if not timestamp then return "Unknown" end
    
    local sHour, sMinute = GetGameTime()
    local lDate = date("*t")
    local diffMins = (sHour * 60 + sMinute) - (lDate.hour * 60 + lDate.min)
    if diffMins > 12 * 60 then diffMins = diffMins - 24 * 60
    elseif diffMins < -12 * 60 then diffMins = diffMins + 24 * 60 end
    
    local adjustedTime = timestamp + (diffMins * 60)
    local adjustedNow = time() + (diffMins * 60)
    
    local d1 = date("*t", adjustedTime)
    local d2 = date("*t", adjustedNow)
    
    if d1.year == d2.year and d1.month == d2.month and d1.day == d2.day then
        return date("Today at %H:%M RT", adjustedTime)
    end
    
    local yesterday = adjustedNow - 86400
    local dy = date("*t", yesterday)
    if d1.year == dy.year and d1.month == dy.month and d1.day == dy.day then
        return date("Yesterday at %H:%M RT", adjustedTime)
    end
    
    return date("%b %d at %H:%M RT", adjustedTime)
end

function MarketSync.ParseItemIDFromDBKey(dbKey)
    if type(dbKey) == "number" then return dbKey end
    if type(dbKey) ~= "string" then return nil end

    local idStr = dbKey:match("^item:(%d+)")
        or dbKey:match("^gr:(%d+)")
        or dbKey:match("^g:(%d+)")
        or dbKey:match("^p:(%d+)")
        or dbKey:match("^(%d+)$")
        or dbKey:match("(%d+)")
    if idStr then
        return tonumber(idStr)
    end
    return nil
end

-- ================================================================
-- PRICE AND AGE HELPERS (ROUTED THROUGH PROVIDER)
-- ================================================================
function MarketSync.GetAuctionPrice(itemLink)
    if MarketSync.Provider and MarketSync.Provider.GetPrice then
        local price = MarketSync.Provider.GetPrice(itemLink)
        if price ~= nil then return price end
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        local aPrice = Auctionator.API.v1.GetAuctionPriceByItemLink(ADDON_NAME, itemLink)
        if aPrice ~= nil then return aPrice end
    end
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if realmDB and realmDB.PersonalData and itemLink then
        local id = tonumber(itemLink) or (type(itemLink) == "string" and tonumber(itemLink:match("item:(%d+)")))
        local dbKey = id and tostring(id) or tostring(itemLink)
        local entry = realmDB.PersonalData[dbKey]
        if entry and entry.m and entry.m > 0 then
            return entry.m
        end
    end
    return nil
end

function MarketSync.GetAuctionAge(itemLink)
    if MarketSync.Provider and MarketSync.Provider.GetPriceAge then
        local age = MarketSync.Provider.GetPriceAge(itemLink)
        if age ~= nil then return age end
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        return Auctionator.API.v1.GetAuctionAgeByItemLink(ADDON_NAME, itemLink)
    end
    return nil
end

function MarketSync.GetAuctionTime(itemLink)
    if MarketSync.Provider and MarketSync.Provider.GetPriceTime then
        local t = MarketSync.Provider.GetPriceTime(itemLink)
        if t ~= nil then return t end
    end
    return nil
end

MarketSync.SCAN_DAY_0 = 1577836800 -- Jan 1, 2020 UTC

function MarketSync.GetCurrentScanDay()
    if Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 then
        return math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
    end
    return math.floor(time() / 86400)
end

function MarketSync.ScanDayToTimestamp(scanDay)
    if not scanDay then return time() end
    local day = tonumber(scanDay) or 0
    if day <= 0 then return time() end
    -- If day > 10000, it represents elapsed days since the standard UNIX epoch (Jan 1, 1970)
    if day > 10000 then
        return day * 86400
    end
    -- Otherwise, it represents days since Auctionator epoch (Jan 1, 2020)
    local scan0 = (Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0)
        or MarketSync.SCAN_DAY_0
        or 1577836800
    return scan0 + (day * 86400)
end

function MarketSync.ScanDayToDate(scanDay)
    if not scanDay then return "" end
    local sDay = tonumber(scanDay)
    if not sDay then return tostring(scanDay) end
    local ts = MarketSync.ScanDayToTimestamp(sDay)
    return date("%b %d", ts)
end

-- ================================================================
-- MONEY / AGE FORMATTERS
-- ================================================================
function MarketSync.FormatMoney(amount)
    if not amount then return "N/A" end
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    local str = ""
    if gold > 0 then str = str .. gold .. "g " end
    if silver > 0 or gold > 0 then str = str .. silver .. "s " end
    str = str .. copper .. "c"
    return str
end

function MarketSync.FormatMoneyColored(amount)
    if not amount or amount <= 0 then return "|cff8888880c|r" end
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    local str = ""
    if gold > 0 then str = str .. "|cffffd700" .. gold .. "g|r " end
    if silver > 0 or gold > 0 then str = str .. "|cffc0c0c0" .. silver .. "s|r " end
    if copper > 0 or (gold == 0 and silver == 0) then str = str .. "|cffeda55f" .. copper .. "c|r" end
    return str
end

-- Strip WoW color codes, hyperlinks, and texture escapes for clean narrator text
function MarketSync.StripColorCodes(text)
    if not text or type(text) ~= "string" then return "" end
    local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    clean = clean:gsub("|H.-|h(.-)|h", "%1")
    clean = clean:gsub("|T.-|t", "")
    clean = clean:gsub("|A.-|a", "")
    return clean:match("^%s*(.-)%s*$") or clean
end

-- Convert copper amount to spoken words for screen readers (e.g. "4 gold, 20 silver, 15 copper")
function MarketSync.FormatNarrationMoney(amount)
    if not amount or amount <= 0 then return "0 copper" end
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, gold .. " gold")
    end
    if silver > 0 then
        table.insert(parts, silver .. " silver")
    end
    if copper > 0 or #parts == 0 then
        table.insert(parts, copper .. " copper")
    end
    return table.concat(parts, ", ")
end

-- Attach official Blizzard Narration methods and accessible GameTooltips to UI regions
function MarketSync.SetAccessibility(region, opts)
    if not region then return end
    opts = opts or {}

    -- Official Blizzard Narration interface (Blizzard_Narration)
    region.NarrationGetName = function(self)
        local n = opts.name
        if type(n) == "function" then n = n(self) end
        if not n and self.GetText then n = self:GetText() end
        return MarketSync.StripColorCodes(n or "")
    end

    region.NarrationGetContext = function(self)
        local c = opts.context
        if type(c) == "function" then c = c(self) end
        if c then return c end
        local objType = self.GetObjectType and self:GetObjectType() or "Button"
        if objType == "CheckButton" or self.GetChecked then
            local checked = self.GetChecked and self:GetChecked()
            return checked and "Check Button, Checked" or "Check Button, Unchecked"
        end
        return objType
    end

    region.NarrationGetDescription = function(self)
        local d = opts.description
        if type(d) == "function" then d = d(self) end
        return MarketSync.StripColorCodes(d or "")
    end

    if opts.getIndexInfo then
        region.NarrationGetIndexInfo = function(self)
            return opts.getIndexInfo(self)
        end
    end

    -- Setup or enhance GameTooltip for mouse-driven screen narration (Blizzard_NarrationSourceMouse)
    if (opts.tooltipTitle or opts.tooltipText or opts.tooltipHint) and region.SetScript then
        local prevEnter = region:GetScript("OnEnter")
        local prevLeave = region:GetScript("OnLeave")

        region:SetScript("OnEnter", function(self)
            if prevEnter then prevEnter(self) end
            if not GameTooltip:IsOwned(self) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local title = opts.tooltipTitle
                if type(title) == "function" then title = title(self) end
                if not title then title = region:NarrationGetName() end

                local desc = opts.tooltipText or opts.description
                if type(desc) == "function" then desc = desc(self) end

                local hint = opts.tooltipHint
                if type(hint) == "function" then hint = hint(self) end

                if title and title ~= "" then
                    GameTooltip:SetText(title, 1, 0.82, 0)
                end
                if desc and desc ~= "" then
                    GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true)
                end
                if hint and hint ~= "" then
                    GameTooltip:AddLine(hint, 0, 0.8, 1, true)
                end
                GameTooltip:Show()
            end
        end)

        region:SetScript("OnLeave", function(self)
            if prevLeave then prevLeave(self) end
            if GameTooltip:IsOwned(self) then
                GameTooltip:Hide()
            end
        end)
    end
end

function MarketSync.FormatRelativeTime(epochTime, fallbackDays)
    if epochTime and epochTime > 0 then
        local diff = math.max(0, time() - epochTime)
        if diff < 60 then
            return "Just now"
        elseif diff < 3600 then
            return string.format("%dm ago", math.max(1, math.floor(diff / 60)))
        elseif diff < 86400 then
            return string.format("%dh ago", math.floor(diff / 3600))
        else
            return string.format("%dd ago", math.floor(diff / 86400))
        end
    end
    if fallbackDays ~= nil and type(fallbackDays) == "number" then
        if fallbackDays < 1 and fallbackDays > 0 then
            local diff = math.floor(fallbackDays * 86400)
            if diff < 60 then return "Just now" end
            if diff < 3600 then return string.format("%dm ago", math.max(1, math.floor(diff / 60))) end
            return string.format("%dh ago", math.floor(diff / 3600))
        end
        local wholeDays = math.max(0, math.floor(fallbackDays))
        if wholeDays == 0 then return "Today" end
        if wholeDays == 1 then return "Yesterday" end
        return string.format("%dd ago", wholeDays)
    end
    return "Unknown"
end

function MarketSync.FormatAuctionAge(ageDays, exactTime, isDetailed)
    local diff = nil
    if exactTime and tonumber(exactTime) and tonumber(exactTime) > 0 then
        diff = math.max(0, time() - tonumber(exactTime))
    elseif ageDays and type(ageDays) == "number" then
        if ageDays < 1 and ageDays > 0 then
            diff = math.max(0, math.floor(ageDays * 86400))
        elseif ageDays >= 1 then
            diff = math.floor(ageDays * 86400)
        elseif ageDays == 0 then
            diff = 0
        end
    end

    if diff == nil then
        if ageDays ~= nil and type(ageDays) == "number" then
            local wholeDays = math.max(0, math.floor(ageDays))
            if wholeDays == 0 then return "Today" end
            if wholeDays == 1 then return isDetailed and "1 day ago" or "1d ago" end
            return isDetailed and string.format("%d days ago", wholeDays) or string.format("%dd ago", wholeDays)
        end
        return "Unknown"
    end

    if isDetailed then
        if diff < 60 then
            return "Just now"
        elseif diff < 3600 then
            local mins = math.max(1, math.floor(diff / 60))
            return string.format("%d min%s ago", mins, mins == 1 and "" or "s")
        elseif diff < 86400 then
            local hours = math.floor(diff / 3600)
            local remMins = math.floor((diff % 3600) / 60)
            if remMins > 0 then
                return string.format("%d hr%s %d min%s ago", hours, hours == 1 and "" or "s", remMins, remMins == 1 and "" or "s")
            else
                return string.format("%d hr%s ago", hours, hours == 1 and "" or "s")
            end
        else
            local days = math.floor(diff / 86400)
            if days <= 1 then
                return "1 day ago"
            else
                return string.format("%d days ago", days)
            end
        end
    else
        -- Compact format (for table columns and narrow views)
        if diff < 60 then
            return "Just now"
        elseif diff < 3600 then
            return string.format("%dm ago", math.max(1, math.floor(diff / 60)))
        elseif diff < 86400 then
            return string.format("%dh ago", math.floor(diff / 3600))
        else
            local days = math.floor(diff / 86400)
            return string.format("%dd ago", math.max(1, days))
        end
    end
end

function MarketSync.GetItemPriceAndScanInfo(keyOrLink)
    if not keyOrLink then return nil end
    local itemID, suffix = MarketSync.ParseItemIDFromDBKey(tostring(keyOrLink))
    if not itemID then
        if type(keyOrLink) == "number" then
            itemID = keyOrLink
        elseif type(keyOrLink) == "string" then
            itemID = tonumber(keyOrLink:match("item:(%d+)") or keyOrLink:match("^(%d+)$"))
        end
    end
    if not itemID then return nil end

    local itemKey = tostring(itemID)
    local suffixKey = (suffix and suffix ~= 0) and ("p:" .. itemID .. ":" .. suffix) or nil
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB() or {}
    
    local price = nil
    local ageDays = nil
    local scanTime = nil
    local source = nil
    local currentDay = MarketSync.GetCurrentScanDay()

    -- 1. Check PersonalData
    local pData = realmDB.PersonalData
    local pEntry = pData and ((suffixKey and pData[suffixKey]) or pData[itemKey])
    if pEntry and pEntry.m and pEntry.m > 0 then
        price = pEntry.m
        local entryDay = tonumber(pEntry.d) or currentDay
        ageDays = math.max(0, currentDay - entryDay)
        if ageDays == 0 and realmDB.PersonalScanTime then
            scanTime = realmDB.PersonalScanTime
        end
        source = "Personal Scan"
    end

    -- 2. Check Provider / LiveStore / Synced Guild Data
    if not price and MarketSync.Provider and MarketSync.Provider.GetPrice then
        local lookupKey = suffixKey or (keyOrLink and tostring(keyOrLink):match("item:%d+") and keyOrLink) or itemKey
        local provPrice = MarketSync.Provider.GetPrice(lookupKey)
        if provPrice and provPrice > 0 then
            price = provPrice
            local provAge = MarketSync.Provider.GetPriceAge and MarketSync.Provider.GetPriceAge(lookupKey)
            if provAge ~= nil then
                ageDays = math.max(0, math.floor(provAge))
            end
            if not scanTime and MarketSync.Provider.GetSnapshot then
                local snap = MarketSync.Provider.GetSnapshot(lookupKey)
                if snap and snap.seenAt then
                    scanTime = snap.seenAt
                end
            end
            source = "Guild Sync"
        end
    end

    -- Check ItemMetadata for more accurate guild contributor and timestamp
    local meta = realmDB.ItemMetadata and ((suffixKey and realmDB.ItemMetadata[suffixKey]) or realmDB.ItemMetadata[itemKey])
    if meta then
        local dayStr = tostring(pEntry and pEntry.d or currentDay)
        if meta.days and meta.days[dayStr] then
            source = meta.days[dayStr].source or source or "Guild Sync"
            scanTime = meta.days[dayStr].time or scanTime
        elseif meta.lastSource then
            source = meta.lastSource or source
            scanTime = meta.lastTime or scanTime
        end
    end

    -- 3. Check Neutral AH Data
    local neutralPrice = nil
    local nData = realmDB.NeutralData
    local nEntry = nData and ((suffixKey and nData[suffixKey]) or nData[itemKey])
    if nEntry and nEntry.m and nEntry.m > 0 then
        neutralPrice = nEntry.m
    end

    if not price and not neutralPrice then
        return nil
    end

    return {
        itemID = itemID,
        suffix = suffix,
        price = price,
        ageDays = ageDays,
        scanTime = scanTime,
        source = source or "MarketSync",
        neutralPrice = neutralPrice,
    }
end

function MarketSync.FormatAge(days)
    if not days then return "Unknown" end
    if days == 0 then return "Today" end
    if days == 1 then return "Yesterday" end
    return string.format("%d days ago", days)
end

-- ================================================================
-- SHARED UTILITIES
-- ================================================================

local function TrimText(text)
    local raw = tostring(text or "")
    if strtrim then return strtrim(raw) end
    return raw:gsub("^%s+", ""):gsub("%s+$", "")
end

function MarketSync.ResolveItemID(query)
    local raw = TrimText(query)
    if raw == "" then return nil end

    -- 1. Try itemID or itemLink match
    local linkedID = raw:match("|Hitem:(%d+):") or raw:match("item:(%d+)")
    if linkedID then
        return tonumber(linkedID)
    end

    local bracketed = raw:match("%[(.-)%]")
    if bracketed and bracketed ~= "" then
        raw = TrimText(bracketed)
    end

    local numericID = tonumber(raw)
    if numericID and numericID > 0 then
        return math.floor(numericID)
    end

    -- 2. Try Exact Name Match (Case-Insensitive) via GetItemInfo
    local _, linkByName = MarketSync.GetItemInfo(raw)
    if linkByName then
        local idFromLink = linkByName:match("item:(%d+)")
        if idFromLink then
            return tonumber(idFromLink)
        end
    end

    -- 3. Try Local Cache (MarketSyncDB.ItemInfoCache)
    local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
    if type(cache) == "table" then
        local needle = string.lower(raw)
        for id, info in pairs(cache) do
            local name = info and info.n and string.lower(tostring(info.n)) or ""
            if name == needle then
                return tonumber(id)
            end
        end
    end

    -- 4. Try Processing Targets (if available)
    if MarketSync.GetProcessingTargets then
        local ok, targets = pcall(MarketSync.GetProcessingTargets)
        if ok and type(targets) == "table" then
            local needle = string.lower(raw)
            for _, t in ipairs(targets) do
                if string.lower(t.name or "") == needle then
                    return tonumber(t.itemID)
                end
            end
        end
    end

    return nil
end

-- ================================================================
-- NOTIFICATION SOUNDS DATA
-- ================================================================
MarketSync.StandardSounds = {
    { name = "Raid Warning", id = 8959 },
    { name = "Auction Open", id = 3171 },
    { name = "Level Up",     id = 124 },
    { name = "Quest Done",   id = 125 },
    { name = "Ready Check",  id = 8960 },
    { name = "Inbox Open",   id = 1404 },
    { name = "Item Sold",    id = 1195 },
    { name = "Hush",         id = 0 }, -- Mute
}

-- ================================================================
-- UI HELPER: CreateModernDialog
-- Clean dark-slate dialog matching Blizzard Auction House styling
-- ================================================================
function MarketSync.CreateModernDialog(name, width, height, titleText)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width or 400, height or 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.075, 0.070, 0.065, 0.98)
    frame:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.95)

    if name then
        table.insert(UISpecialFrames, name)
    end

    -- Header bar
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetPoint("TOPRIGHT", -8, -6)
    header:SetHeight(28)
    frame.Header = header
    frame.TitleContainer = header
    frame.TitleBg = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 6, 0)
    title:SetText(titleText or "|cFFFFD100MarketSync|r")
    frame.TitleText = title

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.CloseButton = closeBtn

    local headerSep = frame:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -2)
    headerSep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -2, -2)
    headerSep:SetColorTexture(0.40, 0.35, 0.20, 0.50)
    frame.headerSep = headerSep

    frame:Hide()
    return frame
end

-- ================================================================
-- UI HELPER: CreateModernInset
-- Matches Blizzard Auction House sleek dark bronze/stone inset panels
-- ================================================================
function MarketSync.CreateModernInset(parent, x, y, width, height)
    local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    inset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    inset:SetBackdropColor(0.075, 0.070, 0.065, 0.96)
    inset:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.90)

    -- Subtle top inner highlight line matching Blizzard AH insets (warm bronze/gold sheen)
    local topHighlight = inset:CreateTexture(nil, "BORDER")
    topHighlight:SetHeight(1)
    topHighlight:SetPoint("TOPLEFT", 1, -1)
    topHighlight:SetPoint("TOPRIGHT", -1, -1)
    topHighlight:SetColorTexture(0.50, 0.42, 0.25, 0.25)
    inset.topHighlight = topHighlight

    if x and y then
        inset:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if width and height then
        inset:SetSize(width, height)
    elseif width then
        inset:SetWidth(width)
    elseif height then
        inset:SetHeight(height)
    end
    return inset
end

-- ================================================================
-- UI HELPER: CreateAHColumnHeader
-- Matches Blizzard Auction House column headers (clean dark bronze/stone + sort arrow)
-- ================================================================
function MarketSync.CreateAHColumnHeader(parent, width, height, text, sortKey)
    local hdr = CreateFrame("Button", nil, parent, "BackdropTemplate")
    hdr:SetSize(width, height or 20)
    hdr.sortKey = sortKey

    hdr:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    hdr:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    hdr:SetBackdropBorderColor(0.32, 0.28, 0.20, 0.85)

    -- Vertical separator on right side
    local sep = hdr:CreateTexture(nil, "OVERLAY")
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT", 0, -2)
    sep:SetPoint("BOTTOMRIGHT", 0, 2)
    sep:SetColorTexture(0.35, 0.30, 0.20, 0.60)
    hdr.sep = sep

    local label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -15, 0)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(false) end
    label:SetText(text or "")
    hdr.label = label

    local arrow = hdr:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", -4, -1)
    arrow:SetTexCoord(0, 0.5625, 0, 1.0)
    arrow:Hide()
    hdr.arrow = arrow

    hdr:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.24, 0.20, 0.12, 0.95)
    end)
    hdr:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    end)

    return hdr
end

-- ================================================================
-- UI HELPER: FormatColoredItemName
-- Properly colors item names based on quality without prefixing literal |c
-- ================================================================
function MarketSync.FormatColoredItemName(name, quality)
    if not name or name == "" then return "" end
    -- If already contains color formatting code, return as-is
    if name:find("|c") then
        return name
    end
    local colorHex = "ffffffff"
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local qCol = ITEM_QUALITY_COLORS[quality]
        colorHex = qCol.colorStr or (qCol.hex and qCol.hex:gsub("^|c", "")) or "ffffffff"
    end
    return string.format("|c%s%s|r", colorHex, name)
end

-- ================================================================
-- UI HELPER: StyleModernTab
-- Fallback skinner for tabs when native AuctionHouseFrameDisplayModeTabTemplate
-- is not available in mock/legacy environments.
-- ================================================================
function MarketSync.StyleModernTab(tab)
    if not tab then return end
    tab:SetHeight(32)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.07, 0.06, 0.95)
    tab._modernBg = bg

    local border = tab:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", 1, -1)
    border:SetPoint("BOTTOMRIGHT", -1, 1)
    border:SetColorTexture(0.30, 0.25, 0.16, 0.85)
    tab._modernBorder = border

    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
    hl:SetBlendMode("ADD")
    tab._modernHl = hl

    local text = tab.GetFontString and tab:GetFontString()
    if text then
        if text.SetFontObject then text:SetFontObject("GameFontNormalSmall") end
        if text.SetTextColor then text:SetTextColor(0.75, 0.70, 0.60) end
    end

    tab.SetSelected = function(self, isSelected)
        if isSelected then
            if self._modernBg and self._modernBg.SetColorTexture then self._modernBg:SetColorTexture(0.16, 0.13, 0.08, 0.98) end
            if self._modernBorder and self._modernBorder.SetColorTexture then self._modernBorder:SetColorTexture(1.0, 0.82, 0.0, 0.95) end
            local t = self.GetFontString and self:GetFontString()
            if t and t.SetTextColor then t:SetTextColor(1.0, 0.82, 0.0) end
        else
            if self._modernBg and self._modernBg.SetColorTexture then self._modernBg:SetColorTexture(0.08, 0.07, 0.06, 0.95) end
            if self._modernBorder and self._modernBorder.SetColorTexture then self._modernBorder:SetColorTexture(0.30, 0.25, 0.16, 0.85) end
            local t = self.GetFontString and self:GetFontString()
            if t and t.SetTextColor then t:SetTextColor(0.75, 0.70, 0.60) end
        end
    end
end

-- ================================================================
-- UI HELPER: SkinModernScrollBar
-- Converts legacy Classic button-sliders into modern WoW Retail /
-- Classic 1.15+ borderless slim scrollbars matching the client AH.
-- ================================================================
function MarketSync.SkinModernScrollBar(scrollFrame, customWidth, offsetX)
    if not scrollFrame then return end
    local name = scrollFrame:GetName()
    local scrollBar = (name and _G[name .. "ScrollBar"]) or scrollFrame.ScrollBar
    if not scrollBar then
        for _, child in ipairs({ scrollFrame:GetChildren() }) do
            if child and child.IsObjectType and child:IsObjectType("Slider") then
                scrollBar = child
                break
            end
        end
    end
    if not scrollBar then return end

    local barWidth = customWidth or 8
    local xOff = offsetX or 0
    local sbName = scrollBar:GetName()

    -- Identify up/down buttons
    local upBtn = (sbName and _G[sbName .. "ScrollUpButton"]) or (name and _G[name .. "ScrollBarScrollUpButton"]) or scrollBar.ScrollUpButton or scrollBar.Back
    local downBtn = (sbName and _G[sbName .. "ScrollDownButton"]) or (name and _G[name .. "ScrollBarScrollDownButton"]) or scrollBar.ScrollDownButton or scrollBar.Forward
    if not upBtn or not downBtn then
        for _, child in ipairs({ scrollBar:GetChildren() }) do
            if child and child.IsObjectType and child:IsObjectType("Button") then
                if not upBtn then upBtn = child
                elseif not downBtn then downBtn = child end
            end
        end
    end

    -- Re-anchor scrollBar to span seamlessly
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", xOff + barWidth + 2, -14)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", xOff + barWidth + 2, 14)
    scrollBar:SetWidth(barWidth)

    -- Style track background: subtle dark stone recessed groove
    if not scrollBar.modernTrack then
        local track = scrollBar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0.04, 0.04, 0.04, 0.55)
        scrollBar.modernTrack = track
    end

    -- Style thumb: modern sleek rounded pill
    local thumb = (sbName and _G[sbName .. "ThumbTexture"]) or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()) or scrollBar.ThumbTexture
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetColorTexture(0.24, 0.20, 0.14, 0.85) -- Warm bronze/stone
        thumb:SetSize(barWidth, 32)
    end

    local function ApplyButtonTextures(btn, isUp)
        if not btn then return end
        local upTex = isUp and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up"
        local downTex = isUp and "Interface\\Buttons\\Arrow-Up-Down" or "Interface\\Buttons\\Arrow-Down-Down"
        local disTex = isUp and "Interface\\Buttons\\Arrow-Up-Disabled" or "Interface\\Buttons\\Arrow-Down-Disabled"
        if btn.SetNormalTexture then btn:SetNormalTexture(upTex) end
        if btn.SetPushedTexture then btn:SetPushedTexture(downTex) end
        if btn.SetDisabledTexture then btn:SetDisabledTexture(disTex) end

        local nt = btn.GetNormalTexture and btn:GetNormalTexture()
        local dt = btn.GetDisabledTexture and btn:GetDisabledTexture()
        if btn:IsEnabled() then
            if nt and nt.SetVertexColor then nt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
        else
            if nt and nt.SetVertexColor then nt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
            if dt and dt.SetVertexColor then dt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
    end

    -- Modern Chevron Up Button
    if upBtn then
        upBtn:ClearAllPoints()
        upBtn:SetPoint("BOTTOM", scrollBar, "TOP", 0, 1)
        upBtn:SetSize(barWidth + 4, 12)
        ApplyButtonTextures(upBtn, true)
    end

    -- Modern Chevron Down Button
    if downBtn then
        downBtn:ClearAllPoints()
        downBtn:SetPoint("TOP", scrollBar, "BOTTOM", 0, -1)
        downBtn:SetSize(barWidth + 4, 12)
        ApplyButtonTextures(downBtn, false)
    end

    -- Hover effect on thumb
    if scrollBar.HookScript then
        scrollBar:HookScript("OnEnter", function()
            if thumb and thumb.SetColorTexture then thumb:SetColorTexture(0.48, 0.38, 0.18, 0.95) end
        end)
        scrollBar:HookScript("OnLeave", function()
            if thumb and thumb.SetColorTexture then thumb:SetColorTexture(0.24, 0.20, 0.14, 0.85) end
        end)
    end

    -- Hook UIPanelScrollBar_Update to preserve modern styling on range updates
    if not scrollBar._modernHooked and type(hooksecurefunc) == "function" and _G["UIPanelScrollBar_Update"] then
        scrollBar._modernHooked = true
        hooksecurefunc("UIPanelScrollBar_Update", function(sb)
            if sb == scrollBar then
                if thumb and thumb.SetColorTexture then
                    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
                    thumb:SetColorTexture(0.24, 0.20, 0.14, 0.85)
                    local curH = thumb:GetHeight() or 32
                    thumb:SetSize(barWidth, math.max(20, curH))
                end
                ApplyButtonTextures(upBtn, true)
                ApplyButtonTextures(downBtn, false)
            end
        end)
    end
end

-- ================================================================
-- UI HELPER: CreateModernTableScrollBar
-- Creates a modern vertical scrollbar for paginated table insets
-- (e.g., Browse, Processing, Alerts) matching native WoW AH tables.
-- ================================================================
function MarketSync.CreateModernTableScrollBar(parent, insetFrame, onPageChanged, customWidth, topOffset, bottomOffset)
    if not parent or not insetFrame then return end

    local barWidth = customWidth or 8
    local topOff = topOffset or -30
    local botOff = bottomOffset or 28

    local slider = CreateFrame("Slider", nil, insetFrame)
    slider:SetPoint("TOPRIGHT", insetFrame, "TOPRIGHT", -4, topOff - 14)
    slider:SetPoint("BOTTOMRIGHT", insetFrame, "BOTTOMRIGHT", -4, botOff + 14)
    slider:SetWidth(barWidth)
    slider:SetOrientation("VERTICAL")
    slider:SetMinMaxValues(0, 1)
    slider:SetValue(0)
    slider:SetValueStep(1)
    slider:EnableMouse(true)
    slider:EnableMouseWheel(true)

    -- Track gutter
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.04, 0.04, 0.04, 0.55)
    slider.track = track

    -- Thumb pill
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetColorTexture(0.24, 0.20, 0.14, 0.85)
    thumb:SetSize(barWidth, 32)
    slider:SetThumbTexture(thumb)
    slider.thumb = thumb

    -- Hover effect
    slider:SetScript("OnEnter", function()
        thumb:SetColorTexture(0.48, 0.38, 0.18, 0.95)
    end)
    slider:SetScript("OnLeave", function()
        thumb:SetColorTexture(0.24, 0.20, 0.14, 0.85)
    end)

    -- Up Chevron Button
    local upBtn = CreateFrame("Button", nil, insetFrame)
    upBtn:SetSize(barWidth + 4, 12)
    upBtn:SetPoint("BOTTOM", slider, "TOP", 0, 1)
    if upBtn.SetNormalTexture then
        upBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Up-Up")
        upBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Up-Down")
        upBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Up-Disabled")
        local upTex = upBtn:GetNormalTexture()
        if upTex and upTex.SetVertexColor then upTex:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
    end

    -- Down Chevron Button
    local downBtn = CreateFrame("Button", nil, insetFrame)
    downBtn:SetSize(barWidth + 4, 12)
    downBtn:SetPoint("TOP", slider, "BOTTOM", 0, -1)
    if downBtn.SetNormalTexture then
        downBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Down-Up")
        downBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Down-Down")
        downBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Down-Disabled")
        local downTex = downBtn:GetNormalTexture()
        if downTex and downTex.SetVertexColor then downTex:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
    end

    slider.upBtn = upBtn
    slider.downBtn = downBtn

    local isUpdating = false
    slider:SetScript("OnValueChanged", function(self, value)
        if isUpdating then return end
        local rounded = math.floor(value + 0.5)
        if onPageChanged then
            onPageChanged(rounded)
        end
    end)

    upBtn:SetScript("OnClick", function()
        local cur = slider:GetValue()
        local minVal, _ = slider:GetMinMaxValues()
        if cur > minVal then
            slider:SetValue(math.max(minVal, cur - 1))
        end
    end)

    downBtn:SetScript("OnClick", function()
        local cur = slider:GetValue()
        local _, maxVal = slider:GetMinMaxValues()
        if cur < maxVal then
            slider:SetValue(math.min(maxVal, cur + 1))
        end
    end)

    local function HandleWheel(delta)
        local cur = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if minVal >= maxVal then return end
        if delta > 0 then
            slider:SetValue(math.max(minVal, cur - 1))
        else
            slider:SetValue(math.min(maxVal, cur + 1))
        end
    end

    slider:SetScript("OnMouseWheel", function(self, delta)
        HandleWheel(delta)
    end)

    function slider:AttachMouseWheel(targetFrame)
        if not targetFrame then return end
        targetFrame:EnableMouseWheel(true)
        if targetFrame.HookScript then
            targetFrame:HookScript("OnMouseWheel", function(self, delta)
                HandleWheel(delta)
            end)
        else
            targetFrame:SetScript("OnMouseWheel", function(self, delta)
                HandleWheel(delta)
            end)
        end
    end

    function slider:Update(currentPage, maxPage)
        isUpdating = true
        maxPage = math.max(0, maxPage or 0)
        currentPage = math.max(0, math.min(currentPage or 0, maxPage))
        slider:SetMinMaxValues(0, maxPage)
        slider:SetValue(currentPage)

        if maxPage > 0 then
            slider:Show()
            upBtn:Show()
            downBtn:Show()
            if currentPage <= 0 then
                upBtn:Disable()
                local uTex = upBtn.GetNormalTexture and upBtn:GetNormalTexture()
                if uTex and uTex.SetVertexColor then uTex:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
                local uDis = upBtn.GetDisabledTexture and upBtn:GetDisabledTexture()
                if uDis and uDis.SetVertexColor then uDis:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
            else
                upBtn:Enable()
                local uTex = upBtn.GetNormalTexture and upBtn:GetNormalTexture()
                if uTex and uTex.SetVertexColor then uTex:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
            end
            if currentPage >= maxPage then
                downBtn:Disable()
                local dTex = downBtn.GetNormalTexture and downBtn:GetNormalTexture()
                if dTex and dTex.SetVertexColor then dTex:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
                local dDis = downBtn.GetDisabledTexture and downBtn:GetDisabledTexture()
                if dDis and dDis.SetVertexColor then dDis:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
            else
                downBtn:Enable()
                local dTex = downBtn.GetNormalTexture and downBtn:GetNormalTexture()
                if dTex and dTex.SetVertexColor then dTex:SetVertexColor(0.70, 0.65, 0.55, 0.90) end
            end
        else
            slider:Hide()
            upBtn:Hide()
            downBtn:Hide()
        end
        isUpdating = false
    end

    return slider
end


