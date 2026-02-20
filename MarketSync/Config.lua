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
-- 3 channels = 3 msg/sec sustained = ~48 items/sec with base-36 encoding.
MarketSync.DATA_PREFIXES = { "MSyncD1", "MSyncD2", "MSyncD3" }
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
-- DATABASE INITIALIZATION
-- ================================================================
function MarketSync.InitializeDB()
    if not MarketSyncDB then
        MarketSyncDB = {
            BlockedUsers = {},
            PassiveSync = true,
            DebugMode = false,
            EnableChatPriceCheck = true,
            BuildCacheOnStartup = true,
            CacheSpeed = 2,
            ItemMetadata = {},
            SyncStats = {},
            HistoryLog = {},
            MinimapIcon = { hide = false, angle = 0 },
            PersonalData = {},
        }
    end
    if not MarketSyncDB.HistoryLog then MarketSyncDB.HistoryLog = {} end
    if not MarketSyncDB.BlockedUsers then MarketSyncDB.BlockedUsers = {} end
    if MarketSyncDB.PassiveSync == nil then MarketSyncDB.PassiveSync = true end
    if MarketSyncDB.DebugMode == nil then MarketSyncDB.DebugMode = false end
    if MarketSyncDB.EnableChatPriceCheck == nil then MarketSyncDB.EnableChatPriceCheck = true end
    if MarketSyncDB.BuildCacheOnStartup == nil then MarketSyncDB.BuildCacheOnStartup = true end
    if not MarketSyncDB.CacheSpeed then MarketSyncDB.CacheSpeed = 2 end
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false } end
    
    if not MarketSyncDB.RealmData then MarketSyncDB.RealmData = {} end

    -- MIGRATION: Move old global data to the current realm's partition on first load
    local realm = GetNormalizedRealmName() or GetRealmName()
    if realm and not MarketSyncDB.RealmData[realm] then
        MarketSyncDB.RealmData[realm] = {
            PersonalData = MarketSyncDB.PersonalData or {},
            ItemMetadata = MarketSyncDB.ItemMetadata or {},
            HistoryLog = MarketSyncDB.HistoryLog or {},
            SyncStats = MarketSyncDB.SyncStats or {},
            WeeklySyncStats = MarketSyncDB.WeeklySyncStats or { yearWeek = date("%Y-%W"), data = {} },
            PersonalScanTime = MarketSyncDB.PersonalScanTime
        }
    end
    
    -- Cleanup old global data
    MarketSyncDB.PersonalData = nil
    MarketSyncDB.ItemMetadata = nil
    MarketSyncDB.HistoryLog = nil
    MarketSyncDB.SyncStats = nil
    MarketSyncDB.WeeklySyncStats = nil
    MarketSyncDB.PersonalScanTime = nil
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
            SyncStats = {},
            WeeklySyncStats = { yearWeek = date("%Y-%W"), data = {} }
        }
    end
    return MarketSyncDB.RealmData[realm]
end

-- ================================================================
-- CACHE SPEED PRESETS
-- ================================================================
-- Each level controls: batch size per tick, retry interval, re-request count, coroutine yield frequency
MarketSync.CacheSpeedPresets = {
    [1] = { name = "Conservative",  batchSize = 25,  interval = 1.0,  requests = 25,   yieldEvery = 20,  desc = "|cff888888Minimal CPU impact. Best for older hardware.\nVery smooth but slower indexing.|r" },
    [2] = { name = "Balanced",      batchSize = 50,  interval = 0.5,  requests = 50,   yieldEvery = 50,  desc = "|cff888888Good balance. Smooth performance for most PCs.\nRecommended default.|r" },
    [3] = { name = "Aggressive",    batchSize = 100, interval = 0.25, requests = 100,  yieldEvery = 100, desc = "|cff888888Faster indexing with potential minor stutter.\nUse if you have a high-end CPU.|r" },
    [4] = { name = "Maximum",       batchSize = 200, interval = 0.1,  requests = 200,  yieldEvery = 200, desc = "|cffff8800Fastest possible. Will likely cause frame drops.\nOnly use if you want it done NOW.|r" },
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
    if sender and MarketSync.IsBlocked(sender) then return end
    
    local realmDB = MarketSync.GetRealmDB()

    -- Track All-Time Stats
    if not realmDB.SyncStats[sender] then
        realmDB.SyncStats[sender] = { count = 0, last = 0 }
    end
    realmDB.SyncStats[sender].count = realmDB.SyncStats[sender].count + count
    realmDB.SyncStats[sender].last = time()
    
    -- Track Weekly Stats
    if not realmDB.WeeklySyncStats then
        realmDB.WeeklySyncStats = { yearWeek = date("%Y-%W"), data = {} }
    end
    
    local currentWeek = date("%Y-%W")
    if realmDB.WeeklySyncStats.yearWeek ~= currentWeek then
        realmDB.WeeklySyncStats.yearWeek = currentWeek
        realmDB.WeeklySyncStats.data = {} -- Wipe stats for the new week
    end
    
    if not realmDB.WeeklySyncStats.data[sender] then
        realmDB.WeeklySyncStats.data[sender] = { count = 0, last = 0 }
    end
    realmDB.WeeklySyncStats.data[sender].count = realmDB.WeeklySyncStats.data[sender].count + count
    realmDB.WeeklySyncStats.data[sender].last = time()
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


