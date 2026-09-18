-- =============================================================
-- MarketSync - Neutral AH Isolation Module
-- Captures neutral scans without polluting main Auctionator DB
-- =============================================================

local neutralSessionActive = false
local neutralHookInstalled = false
local wrappedSetPrice = false
local originalSetPrice = nil
local touchedOriginal = {}
local touchedOriginalExists = {}
local touchedOriginalKey = {}

local NEUTRAL_SUBZONES = {
    ["Booty Bay"] = true,
    ["Gadgetzan"] = true,
    ["Everlook"] = true,
    ["Area 52"] = true,
}

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return out
end

local function ResolveNeutralAuctionContext()
    local subZone = GetSubZoneText and GetSubZoneText() or ""
    local zone = GetZoneText and GetZoneText() or ""
    local npcName = UnitName and UnitName("npc") or ""
    local inNeutralZone = NEUTRAL_SUBZONES[subZone] or NEUTRAL_SUBZONES[zone] or false
    local npcHintsNeutral = false
    if npcName and npcName ~= "" then
        local lower = npcName:lower()
        npcHintsNeutral = lower:find("auctioneer", 1, true) and inNeutralZone
    end
    return inNeutralZone or npcHintsNeutral
end

local function CaptureNeutralFromPriceData(dbKey, priceData, senderName)
    if not priceData or type(priceData) ~= "table" then return end
    local latestDay = 0
    if priceData.h then
        for dayStr in pairs(priceData.h) do
            local d = tonumber(dayStr)
            if d and d > latestDay then latestDay = d end
        end
    end
    if latestDay <= 0 and MarketSync.GetCurrentScanDay then
        latestDay = MarketSync.GetCurrentScanDay()
    end
    local price = tonumber(priceData.m) or 0
    local dayStr = tostring(latestDay)
    if price <= 0 and priceData.h and priceData.h[dayStr] then
        price = tonumber(priceData.h[dayStr]) or 0
    end
    if price <= 0 then return end

    local qty = 0
    if priceData.a and priceData.a[dayStr] then
        qty = tonumber(priceData.a[dayStr]) or 0
    end

    if MarketSync.UpdateLocalNeutralDBByKey then
        MarketSync.UpdateLocalNeutralDBByKey(dbKey, price, latestDay, qty, senderName or "Personal", true)
    end
end

function MarketSync.IsNeutralAHSession()
    return neutralSessionActive
end

function MarketSync.SetupNeutralCaptureHook()
    if neutralHookInstalled then return true end
    if not Auctionator or not Auctionator.Database or type(Auctionator.Database.SetPrice) ~= "function" then
        return false
    end

    originalSetPrice = Auctionator.Database.SetPrice
    Auctionator.Database.SetPrice = function(self, dbKey, minPrice, currentDay, minSeen, numAvailable, checkUncollected)
        if wrappedSetPrice or not neutralSessionActive then
            return originalSetPrice(self, dbKey, minPrice, currentDay, minSeen, numAvailable, checkUncollected)
        end

        local mapKey = tostring(dbKey)
        if touchedOriginalExists[mapKey] == nil then
            touchedOriginalKey[mapKey] = dbKey
            touchedOriginalExists[mapKey] = (self.db and self.db[dbKey] ~= nil) or false
            touchedOriginal[mapKey] = touchedOriginalExists[mapKey] and DeepCopy(self.db[dbKey]) or nil
        end

        wrappedSetPrice = true
        local ok, err = pcall(originalSetPrice, self, dbKey, minPrice, currentDay, minSeen, numAvailable, checkUncollected)
        wrappedSetPrice = false
        if not ok then
            error(err)
        end

        if self.db and self.db[dbKey] then
            CaptureNeutralFromPriceData(dbKey, self.db[dbKey], UnitName("player"))
        end

        local restoreKey = touchedOriginalKey[mapKey] or dbKey
        if touchedOriginalExists[mapKey] then
            self.db[restoreKey] = DeepCopy(touchedOriginal[mapKey])
        else
            self.db[restoreKey] = nil
        end
    end

    neutralHookInstalled = true
    return true
end

function MarketSync.BeginNeutralSession()
    if neutralSessionActive then return end
    neutralSessionActive = true
    wipe(touchedOriginal)
    wipe(touchedOriginalExists)
    wipe(touchedOriginalKey)

    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent("|cff00ccff[Neutral]|r Neutral AH session detected. Isolated capture enabled.")
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Neutral Capture")
    end
end

function MarketSync.EndNeutralSession()
    if not neutralSessionActive then return false end
    neutralSessionActive = false

    local realmDB = MarketSync.GetRealmDB()
    local now = time()
    realmDB.NeutralScanTime = now
    realmDB.NeutralSwarmTSF = now
    if realmDB.NeutralSync then
        realmDB.NeutralSync.lastSessionItems = 0
        for _ in pairs(realmDB.NeutralData or {}) do
            realmDB.NeutralSync.lastSessionItems = realmDB.NeutralSync.lastSessionItems + 1
        end
    end

    wipe(touchedOriginal)
    wipe(touchedOriginalExists)
    wipe(touchedOriginalKey)

    if MarketSync.InvalidateIndexCache then
        MarketSync.InvalidateIndexCache()
    end
    if MarketSync.BuildSearchIndex then
        C_Timer.After(1, function()
            if MarketSync.BuildSearchIndex then
                MarketSync.BuildSearchIndex()
            end
        end)
    end
    if MarketSync.SendNeutralAdvertisement then
        C_Timer.After(2, function()
            if MarketSync.SendNeutralAdvertisement then
                MarketSync.SendNeutralAdvertisement()
            end
        end)
    end

    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent("|cff00ccff[Neutral]|r Neutral capture complete. Snapshot committed to isolated neutral cache.")
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), nil)
    end
    return true
end

function MarketSync.HandleAuctionHouseShown()
    if not MarketSync.SetupNeutralCaptureHook or not MarketSync.SetupNeutralCaptureHook() then
        return false
    end
    local isNeutral = ResolveNeutralAuctionContext()
    if isNeutral then
        MarketSync.BeginNeutralSession()
    end
    return isNeutral
end

function MarketSync.HandleAuctionHouseClosed()
    return MarketSync.EndNeutralSession()
end
