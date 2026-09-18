-- =============================================================
-- MarketSync - Neutral AH Isolation Module
-- Captures neutral scans without polluting main Auctionator DB
-- =============================================================

local neutralSessionActive = false
local neutralHookInstalled = false
local wrappedSetPrice = false
local originalSetPrice = nil
local neutralSessionSeenKeys = {}
local neutralSessionCaptureCount = 0
local neutralSessionVerifiedCount = 0
local neutralFullScanActive = false
local neutralFullScanKeys = {}

local NEUTRAL_SUBZONES = {
    ["Booty Bay"] = true,
    ["Gadgetzan"] = true,
    ["Everlook"] = true,
    ["Area 52"] = true,
}

-- Zone map IDs containing the TBC neutral auction houses. These supplement
-- localized subzone text; no faction auction house exists in these zones.
local NEUTRAL_AH_ZONE_MAPS = {
    [50] = true, [71] = true, [83] = true, [109] = true, [210] = true,
    [1434] = true, [1446] = true, [1452] = true, [1953] = true,
}

local function ResolveNeutralAuctionContext()
    -- Classic clients expose the active AH's economic rate on some builds. This
    -- is locale-independent: faction AHs use the normal rate, while neutral AHs
    -- use the higher rate. Ignore unavailable/zero values and retain the zone
    -- fallback for TBC builds where the API is absent.
    local function IsHigherNeutralRate(getRate, normalFraction, normalPercent)
        if type(getRate) ~= "function" then return false end
        local ok, rate = pcall(getRate)
        rate = ok and tonumber(rate) or nil
        if not rate or rate <= 0 then return false end
        if rate <= 1 then return rate > normalFraction end
        return rate > normalPercent and rate <= 100
    end
    if IsHigherNeutralRate(GetAuctionHouseCut, 0.05, 5)
        or IsHigherNeutralRate(GetAuctionHouseDepositRate, 0.15, 15) then
        return true
    end

    if type(UnitFactionGroup) == "function" then
        local ok, _, factionToken = pcall(UnitFactionGroup, "npc")
        if ok and factionToken == "Neutral" then return true end
    end
    if type(UnitReaction) == "function" then
        local ok, reaction = pcall(UnitReaction, "npc", "player")
        -- A reaction of exactly 4 is neutral. Friendly faction auctioneers are
        -- 5 or higher, so this signal cannot classify a normal AH as neutral.
        if ok and tonumber(reaction) == 4 then return true end
    end
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and NEUTRAL_AH_ZONE_MAPS[tonumber(mapID)] then return true end
    end

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
    if not priceData or type(priceData) ~= "table" then return false end
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
    if price <= 0 then return false end

    local qty = 0
    if priceData.a and priceData.a[dayStr] then
        qty = tonumber(priceData.a[dayStr]) or 0
    end

    if MarketSync.UpdateLocalNeutralDBByKey then
        MarketSync.UpdateLocalNeutralDBByKey(dbKey, price, latestDay, qty, senderName or "Personal", true)
        return true
    end
    return false
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

        -- Run Auctionator against an isolated scratch slot. Restoring the exact
        -- original reference avoids copying years of history for every full-scan
        -- item and ensures neutral writes never mutate the main database object.
        local originalEntry = self.db and self.db[dbKey] or nil
        local isFirstTouch = neutralSessionSeenKeys[dbKey] == nil
        if self.db then self.db[dbKey] = nil end

        wrappedSetPrice = true
        local setOK, setResult = pcall(originalSetPrice, self, dbKey, minPrice, currentDay, minSeen, numAvailable, checkUncollected)
        wrappedSetPrice = false

        local captureOK, capturedOrError = true, false
        local scratchEntry = self.db and self.db[dbKey] or nil
        if setOK and scratchEntry then
            captureOK, capturedOrError = pcall(
                CaptureNeutralFromPriceData,
                dbKey,
                scratchEntry,
                UnitName("player")
            )
        end

        -- Treat Auctionator's main database as a transaction: restoration must
        -- run after SetPrice succeeds or fails, and after capture/alert code
        -- succeeds or fails.
        local restoreOK, restoreError = pcall(function()
            if not self.db then return end
            self.db[dbKey] = originalEntry
        end)

        if not restoreOK then
            error("Neutral Auctionator DB restore failed: " .. tostring(restoreError), 0)
        end
        if not setOK then
            error(setResult, 0)
        end
        if not captureOK then
            error(capturedOrError, 0)
        end
        if capturedOrError and isFirstTouch then
            neutralSessionSeenKeys[dbKey] = true
            neutralSessionCaptureCount = neutralSessionCaptureCount + 1
        end
        if capturedOrError and neutralFullScanActive then
            neutralFullScanKeys[dbKey] = true
        end
        return setResult
    end

    neutralHookInstalled = true
    return true
end

function MarketSync.BeginNeutralSession()
    if neutralSessionActive then return end
    neutralSessionActive = true
    neutralSessionCaptureCount = 0
    neutralSessionVerifiedCount = 0
    neutralFullScanActive = false
    wipe(neutralFullScanKeys)
    wipe(neutralSessionSeenKeys)

    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent("|cff00ccff[Neutral]|r Neutral AH session detected. Isolated capture enabled.")
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Neutral Capture")
    end
end

function MarketSync.BeginNeutralFullScan()
    if not neutralSessionActive then return false end
    neutralFullScanActive = true
    wipe(neutralFullScanKeys)
    return true
end

function MarketSync.FailNeutralFullScan()
    neutralFullScanActive = false
    wipe(neutralFullScanKeys)
end

function MarketSync.CompleteNeutralFullScan(exactKeys)
    if not neutralSessionActive or not neutralFullScanActive then
        MarketSync.FailNeutralFullScan()
        return false
    end

    neutralFullScanActive = false
    local keys = exactKeys or neutralFullScanKeys
    local realmDB = MarketSync.GetRealmDB()
    local verifiedCount = 0
    local verifiedDay = 0
    local now = time()

    for dbKey in pairs(keys or {}) do
        local entry = realmDB.NeutralData and realmDB.NeutralData[dbKey]
        if type(entry) == "table" then
            local price = tonumber(entry.m) or 0
            local day = tonumber(entry.d) or 0
            if price > 0 and day > 0 then
                entry.vm = price
                entry.vd = day
                entry.vq = math.max(0, tonumber(entry.q) or 0)
                verifiedCount = verifiedCount + 1
                if day > verifiedDay then verifiedDay = day end

                local meta = realmDB.NeutralMeta and realmDB.NeutralMeta[dbKey]
                if meta then
                    meta.state = "Complete"
                    meta.source = UnitName("player") or "Personal"
                    meta.time = now
                end
            end
        end
    end
    wipe(neutralFullScanKeys)

    if verifiedCount <= 0 then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent("|cffaaaaaa[Neutral]|r Full scan completed without transferable price records; freshness was not advanced.")
        end
        return true, 0
    end

    realmDB.NeutralVerifiedDay = verifiedDay
    realmDB.NeutralScanTime = now
    realmDB.NeutralSwarmTSF = now
    realmDB.CachedScanStats = nil
    if realmDB.NeutralSync then
        realmDB.NeutralSync.lastVerifiedItems = verifiedCount
    end
    neutralSessionVerifiedCount = verifiedCount

    if MarketSync.InvalidateIndexCache then
        MarketSync.InvalidateIndexCache()
    end
    if MarketSync.BuildSearchIndex then
        C_Timer.After(1, function()
            if MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end
        end)
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "|cff00ccff[Neutral]|r Verified full scan complete. %d item(s) are eligible for outbound sync.",
            verifiedCount))
    end
    return true, verifiedCount
end

function MarketSync.EndNeutralSession()
    if not neutralSessionActive then return false end
    neutralSessionActive = false

    local realmDB = MarketSync.GetRealmDB()
    local capturedCount = neutralSessionCaptureCount
    local verifiedCount = neutralSessionVerifiedCount
    MarketSync.FailNeutralFullScan()
    if realmDB.NeutralSync then
        realmDB.NeutralSync.lastSessionItems = capturedCount
    end

    wipe(neutralSessionSeenKeys)
    neutralSessionCaptureCount = 0
    neutralSessionVerifiedCount = 0

    if capturedCount > 0 then
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
    end
    if verifiedCount > 0 and MarketSync.SendNeutralAdvertisement then
        C_Timer.After(2, function()
            if MarketSync.SendNeutralAdvertisement then MarketSync.SendNeutralAdvertisement() end
        end)
    end

    if MarketSync.LogNetworkEvent then
        if capturedCount > 0 then
            MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r Neutral session closed with %d observed item(s). Only a successful full scan is eligible for outbound sync.", capturedCount))
        else
            MarketSync.LogNetworkEvent("|cffaaaaaa[Neutral]|r Neutral AH closed without captured scan data; freshness was not advanced.")
        end
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
