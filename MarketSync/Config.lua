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

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

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
            PassiveSync = false,
            DebugMode = false,
            BuildCacheOnStartup = false,
            CacheSpeed = 2,
            ItemMetadata = {},
            SyncStats = {},
            HistoryLog = {},
            MinimapIcon = { hide = false, angle = 0 },
        }
    end
    if not MarketSyncDB.HistoryLog then MarketSyncDB.HistoryLog = {} end
    if not MarketSyncDB.BlockedUsers then MarketSyncDB.BlockedUsers = {} end
    if MarketSyncDB.PassiveSync == nil then MarketSyncDB.PassiveSync = false end
    if MarketSyncDB.DebugMode == nil then MarketSyncDB.DebugMode = false end
    if MarketSyncDB.BuildCacheOnStartup == nil then MarketSyncDB.BuildCacheOnStartup = false end
    if not MarketSyncDB.CacheSpeed then MarketSyncDB.CacheSpeed = 2 end
    if not MarketSyncDB.ItemMetadata then MarketSyncDB.ItemMetadata = {} end
    if not MarketSyncDB.SyncStats then MarketSyncDB.SyncStats = {} end
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false } end
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
    if not MarketSyncDB.SyncStats[sender] then
        MarketSyncDB.SyncStats[sender] = { count = 0, last = 0 }
    end
    MarketSyncDB.SyncStats[sender].count = MarketSyncDB.SyncStats[sender].count + count
    MarketSyncDB.SyncStats[sender].last = time()
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


