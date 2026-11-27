-- ================================================================
-- MarketSync - Provider Abstraction Layer
-- Decouples MarketSync from direct Auctionator dependencies.
-- Provides a unified interface for Forever native and Auctionator backends.
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.Provider = {}

local Provider = MarketSync.Provider
Provider.Registry = {}
Provider.Active = nil
Provider.ActiveName = nil
Provider.ChangeCallbacks = {}

-- Register a provider implementation
function Provider.Register(name, providerTable)
    if type(name) ~= "string" or type(providerTable) ~= "table" then return end
    Provider.Registry[name] = providerTable
    providerTable.name = name
end

-- Fallback null provider so calls never crash if no backend is loaded
local NullProvider = {
    name = "none",
    GetSnapshot = function() return nil end,
    GetPrice = function() return nil end,
    GetPriceAge = function() return nil end,
    GetCurrentBucket = function() return math.floor(time() / 1800) end,
    GetMarketID = function() return "offline" end,
    GetLiveStore = function() return nil end,
    IsWatchSupported = function() return false end,
    ToggleWatch = function() return false end,
    IsWatched = function() return false end,
    CanExportShoppingList = function() return false end,
    ExportShoppingList = function() return false, "Shopping list export unavailable" end,
    StartScan = function() return false end,
    StopScan = function() return false end,
    IsScanActive = function() return false end,
    Initialize = function() end,
}
Provider.Register("none", NullProvider)

-- Auto-select the appropriate provider based on the environment
function Provider.Select(preferred)
    if preferred and Provider.Registry[preferred] then
        Provider.Active = Provider.Registry[preferred]
        Provider.ActiveName = preferred
        return Provider.Active
    end

    -- When enabled, Auctionator owns scanning and its SavedVariables database.
    -- Prefer it explicitly even on Forever, where MarketSync also ships a native scanner.
    if MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true
        and Auctionator and Auctionator.Database and Provider.Registry["auctionator"] then
        Provider.Active = Provider.Registry["auctionator"]
        Provider.ActiveName = "auctionator"
        return Provider.Active
    end

    -- 1. Check for Forever native scanner or modern C_AuctionHouse
    if MarketSync.Scanner or MarketSyncForeverScanner or (C_AuctionHouse and (type(C_AuctionHouse.SendSearchQuery) == "function" or type(C_AuctionHouse.SendBrowseQuery) == "function")) then
        if Provider.Registry["forever"] then
            Provider.Active = Provider.Registry["forever"]
            Provider.ActiveName = "forever"
            return Provider.Active
        end
    end

    -- 2. Check for Auctionator
    if Auctionator and Auctionator.Database then
        if Provider.Registry["auctionator"] then
            Provider.Active = Provider.Registry["auctionator"]
            Provider.ActiveName = "auctionator"
            return Provider.Active
        end
    end

    -- 3. If neither backend is detected in the environment, fall back to null provider
    Provider.Active = NullProvider
    Provider.ActiveName = "none"
    return Provider.Active
end

function Provider.GetActive()
    if not Provider.Active then
        Provider.Select()
    end
    return Provider.Active or NullProvider
end

function Provider.GetActiveName()
    if not Provider.Active then Provider.Select() end
    return Provider.ActiveName or "none"
end

-- ================================================================
-- DELEGATED INTERFACE METHODS
-- ================================================================

function Provider.GetSnapshot(keyOrLink)
    local active = Provider.GetActive()
    if active and active.GetSnapshot then
        return active.GetSnapshot(keyOrLink)
    end
    return nil
end

function Provider.GetPrice(keyOrLink)
    local active = Provider.GetActive()
    if active and active.GetPrice then
        return active.GetPrice(keyOrLink)
    end
    return nil
end

function Provider.GetPriceAge(keyOrLink)
    local active = Provider.GetActive()
    if active and active.GetPriceAge then
        return active.GetPriceAge(keyOrLink)
    end
    return nil
end

function Provider.GetPriceTime(keyOrLink)
    local active = Provider.GetActive()
    if active and active.GetPriceTime then
        return active.GetPriceTime(keyOrLink)
    end
    local snap = Provider.GetSnapshot(keyOrLink)
    return snap and snap.seenAt or nil
end

function Provider.GetCurrentBucket()
    local active = Provider.GetActive()
    if active and active.GetCurrentBucket then
        return active.GetCurrentBucket()
    end
    return math.floor(time() / 1800)
end

function Provider.GetMarketID()
    local active = Provider.GetActive()
    if active and active.GetMarketID then
        return active.GetMarketID()
    end
    return "default"
end

function Provider.GetLiveStore()
    local active = Provider.GetActive()
    if active and active.GetLiveStore then
        return active.GetLiveStore()
    end
    return nil
end

function Provider.IsWatchSupported()
    local active = Provider.GetActive()
    return active and active.IsWatchSupported and active.IsWatchSupported() or false
end

function Provider.ToggleWatch(keyID)
    local active = Provider.GetActive()
    if active and active.ToggleWatch then
        return active.ToggleWatch(keyID)
    end
    return false
end

function Provider.IsWatched(keyID)
    local active = Provider.GetActive()
    if active and active.IsWatched then
        return active.IsWatched(keyID)
    end
    return false
end

function Provider.CanExportShoppingList()
    local active = Provider.GetActive()
    return active and active.CanExportShoppingList and active.CanExportShoppingList() or false
end

function Provider.ExportShoppingList(listName, items)
    local active = Provider.GetActive()
    if active and active.ExportShoppingList then
        return active.ExportShoppingList(listName, items)
    end
    return false, "Not supported by active provider"
end

function Provider.StartScan()
    local active = Provider.GetActive()
    if active and active.StartScan then
        return active.StartScan()
    end
    return false
end

function Provider.StopScan()
    local active = Provider.GetActive()
    if active and active.StopScan then
        return active.StopScan()
    end
    return false
end

function Provider.IsScanActive()
    local active = Provider.GetActive()
    return active and active.IsScanActive and active.IsScanActive() or false
end

function Provider.RegisterChangeCallback(callback)
    if type(callback) == "function" then
        table.insert(Provider.ChangeCallbacks, callback)
    end
end

function Provider.TriggerChangeCallbacks(...)
    for _, cb in ipairs(Provider.ChangeCallbacks) do
        pcall(cb, ...)
    end
end

function Provider.Initialize()
    Provider.Select()
    local active = Provider.GetActive()
    if active and active.Initialize then
        active.Initialize()
    end
end

-- MarketSyncData Hook: supplement missing scan data from MarketSyncData addon
function MarketSync.GetMarketSyncDataPrice(itemId)
    local dataAddon = _G.MarketSyncData
    if type(dataAddon) ~= "table" then return nil end
    if MarketSync.IsDataPackFlavorCompatible
        and not MarketSync.IsDataPackFlavorCompatible(dataAddon.flavor or dataAddon.Flavor) then
        return nil
    end
    if MarketSync.IsDataPackRegionCompatible
        and not MarketSync.IsDataPackRegionCompatible(dataAddon.region or dataAddon.Region) then
        return nil
    end
    if type(dataAddon.GetPrice) == "function" then
        return dataAddon.GetPrice(itemId)
    end
    if MarketSync.EnsureCurrentDataPack then
        local prices = MarketSync.EnsureCurrentDataPack()
        local rec = type(prices) == "table" and itemId ~= nil and (prices[itemId] or prices[tostring(itemId)])
        if type(rec) == "table" and tonumber(rec.m) then
            return tonumber(rec.m)
        elseif type(rec) == "number" then
            return rec
        end
    end
    local prices = dataAddon.prices or dataAddon.Prices
    if type(prices) == "table" then
        return prices[itemId] or prices[tostring(itemId)]
    end
    return nil
end

function MarketSync.FormatDataSourceLabel(source)
    if source == "personal" then return "Personal Scan" end
    if source == "guild" then return "Guild Sync" end
    if source == "msdata" then return "MarketSyncData" end
    return "Unknown"
end

function MarketSync.GetPriceWithSource(itemId)
    local personal = MarketSync.GetPersonalPrice and MarketSync.GetPersonalPrice(itemId)
    if personal then
        return personal, "personal"
    end
    local guild = MarketSync.GetGuildPrice and MarketSync.GetGuildPrice(itemId)
    if guild then
        return guild, "guild"
    end
    local msdata = MarketSync.GetMarketSyncDataPrice and MarketSync.GetMarketSyncDataPrice(itemId)
    if msdata then
        return msdata, "msdata"
    end
    return nil, nil
end
