-- ================================================================
-- MarketSync - Auctionator Provider Implementation
-- Encapsulates legacy Auctionator integration for Classic Era / TBC / Retail.
-- ================================================================

MarketSync = MarketSync or {}
local ADDON_NAME = MarketSync.ADDON_NAME or "MarketSync"

local AuctionatorProvider = {}

local function ExtractDBKey(keyOrLink)
    if type(keyOrLink) == "number" then
        return "i:" .. keyOrLink
    elseif type(keyOrLink) == "string" then
        local itemID = keyOrLink:match("item:(%d+)")
        if itemID then
            return "i:" .. itemID
        elseif keyOrLink:match("^%d+$") then
            return "i:" .. keyOrLink
        end
        return keyOrLink
    end
    return nil
end

local function GetGuildRecord(keyOrLink)
    if not MarketSync.GetRealmDB then return nil end
    local db = MarketSync.GetRealmDB()
    local id, suffix
    if MarketSync.ParseItemIDFromDBKey then id, suffix = MarketSync.ParseItemIDFromDBKey(keyOrLink) end
    local key = id and (suffix and suffix ~= 0 and string.format("p:%d:%d", id, suffix) or tostring(id))
    return db.GuildData and ((key and db.GuildData[key]) or db.GuildData[ExtractDBKey(keyOrLink)])
end

function AuctionatorProvider.GetPrice(keyOrLink)
    local record = GetGuildRecord(keyOrLink)
    if record and record.m and record.m > 0 then return record.m end
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then
        if Auctionator and Auctionator.Database and Auctionator.Database.db then
            local dbKey = ExtractDBKey(keyOrLink)
            local row = dbKey and Auctionator.Database.db[dbKey]
            return row and row.m
        end
        return nil
    end

    if type(keyOrLink) == "number" or (type(keyOrLink) == "string" and keyOrLink:match("^%d+$")) then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_NAME, tonumber(keyOrLink))
        return ok and price or nil
    end

    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, ADDON_NAME, tostring(keyOrLink))
    return ok and price or nil
end

function AuctionatorProvider.GetPriceAge(keyOrLink)
    local record = GetGuildRecord(keyOrLink)
    if record then
        local observed = tonumber(record.observedAt)
            or (tonumber(record.d) and tonumber(record.d) > 0 and MarketSync.ScanDayToTimestamp(record.d))
        return observed and math.max(0, time() - observed) / 86400 or nil
    end
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then
        if Auctionator and Auctionator.Database and type(Auctionator.Database.GetPriceAge) == "function" then
            local dbKey = ExtractDBKey(keyOrLink)
            return dbKey and Auctionator.Database:GetPriceAge(dbKey) or nil
        end
        return nil
    end

    if type(keyOrLink) == "number" or (type(keyOrLink) == "string" and keyOrLink:match("^%d+$")) then
        local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemID, ADDON_NAME, tonumber(keyOrLink))
        return ok and age or nil
    end

    local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemLink, ADDON_NAME, tostring(keyOrLink))
    return ok and age or nil
end

function AuctionatorProvider.GetSnapshot(keyOrLink)
    local record = GetGuildRecord(keyOrLink)
    if record and record.m and record.m > 0 then
        local age = AuctionatorProvider.GetPriceAge(keyOrLink)
        return { minUnitPrice = record.m, available = record.available,
            seenAt = age and (time() - age * 86400) or nil, complete = true,
            source = record.source or "guild-market", coverage = "full" }
    end
    local price = AuctionatorProvider.GetPrice(keyOrLink)
    if not price then return nil end
    local ageDays = AuctionatorProvider.GetPriceAge(keyOrLink)
    local ageSeconds = ageDays and (ageDays * 86400) or 0
    return {
        minUnitPrice = price,
        available = nil,
        seenAt = time() - ageSeconds,
        complete = true,
        source = "auctionator",
        coverage = "full",
    }
end

function AuctionatorProvider.GetCurrentBucket()
    local dayZero = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 or 1600000000
    return math.floor((time() - dayZero) / 1800)
end

function AuctionatorProvider.GetMarketID()
    local realm = GetRealmName and GetRealmName() or "UnknownRealm"
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
    return realm .. "-" .. faction
end

function AuctionatorProvider.GetLiveStore()
    return Auctionator and Auctionator.Database and Auctionator.Database.db or nil
end

function AuctionatorProvider.IsWatchSupported()
    return false
end

function AuctionatorProvider.ToggleWatch()
    return false
end

function AuctionatorProvider.IsWatched()
    return false
end

function AuctionatorProvider.CanExportShoppingList()
    return Auctionator ~= nil
end

function AuctionatorProvider.ExportShoppingList(listName, items)
    if MarketSync.ExportCraftMatsToAuctionator then
        return MarketSync.ExportCraftMatsToAuctionator(items)
    end
    return false, "Export function unavailable"
end

function AuctionatorProvider.IsScanActive()
    return MarketSync._auctionatorScanActive == true
end

function AuctionatorProvider.StartScan()
    if not (Auctionator and Auctionator.State) then return false end
    local frame = Auctionator.State.FullScanFrameRef
    local config = Auctionator.Config
    local options = config and config.Options
    local replicateOption = options and options.REPLICATE_SCAN
    if replicateOption and config.Get and not config.Get(replicateOption) then
        frame = Auctionator.State.IncrementalScanFrameRef or frame
    end
    if not frame or type(frame.InitiateScan) ~= "function" then
        return false, "Open the Auction House and load Auctionator's scan controls first"
    end
    if type(frame.CanInitiate) == "function" and not frame:CanInitiate() then
        return false, "Auctionator's scan is already running or still on cooldown"
    end
    if AuctionatorProvider.IsScanActive() then return false, "Auctionator scan is already running" end
    local ok, err = pcall(frame.InitiateScan, frame)
    if not ok then return false, tostring(err) end
    return true
end

function AuctionatorProvider.StopScan()
    local state = Auctionator and Auctionator.State
    local frame = state and (state.FullScanFrameRef or state.IncrementalScanFrameRef)
    if frame and type(frame.CancelScan) == "function" then
        local ok = pcall(frame.CancelScan, frame)
        return ok
    end
    return false
end

function AuctionatorProvider.Initialize()
    -- Hook Auctionator when ready
    if MarketSync.RegisterAuctionatorHooks then
        MarketSync.RegisterAuctionatorHooks()
    end
end

if MarketSync.Provider and MarketSync.Provider.Register then
    MarketSync.Provider.Register("auctionator", AuctionatorProvider)
end
