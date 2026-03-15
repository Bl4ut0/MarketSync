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
    if MarketSyncDB.EnableNotificationSounds == nil then MarketSyncDB.EnableNotificationSounds = true end
    if MarketSyncDB.BuildCacheOnStartup == nil then MarketSyncDB.BuildCacheOnStartup = true end
    if not MarketSyncDB.CacheSpeed then MarketSyncDB.CacheSpeed = 2 end
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false, angle = 3.75 } end
    if not MarketSyncDB.NotificationSoundID then MarketSyncDB.NotificationSoundID = 8959 end
    if not MarketSyncDB.NotificationVolume then MarketSyncDB.NotificationVolume = 1.0 end
    if not MarketSyncDB.NotificationMode then MarketSyncDB.NotificationMode = "on_scan" end
    if not MarketSyncDB.PerNotificationSounds then MarketSyncDB.PerNotificationSounds = {} end
    
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
end

-- Fast helper function to get the partitioned database for the current realm
function MarketSync.GetRealmDB()
    local realm = GetNormalizedRealmName() or GetRealmName()
    if not realm then return {} end
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
-- AUCTIONATOR HELPERS
-- ================================================================
function MarketSync.GetAuctionPrice(itemLink)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return nil end
    return Auctionator.API.v1.GetAuctionPriceByItemLink(ADDON_NAME, itemLink)
end

function MarketSync.GetAuctionAge(itemLink)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return nil end
    return Auctionator.API.v1.GetAuctionAgeByItemLink(ADDON_NAME, itemLink)
end

function MarketSync.GetCurrentScanDay()
    if Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 then
        return math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
    end
    return 0
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
    local _, linkByName = GetItemInfo(raw)
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


