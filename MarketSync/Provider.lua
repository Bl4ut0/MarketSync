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

    -- 1. Check for Forever native scanner or modern C_AuctionHouse with camelot
    if MarketSyncForeverScanner or (C_AuctionHouse and type(C_AuctionHouse.SendBrowseQuery) == "function" and not Auctionator) then
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
