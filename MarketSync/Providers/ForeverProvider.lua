-- ================================================================
-- MarketSync - Forever Provider Implementation
-- Connects MarketSync to Forever's native C_AuctionHouse scanner.
-- ================================================================

MarketSync = MarketSync or {}

local ForeverProvider = {}

-- Normalize item link, ID, or table to a native ItemKey
function ForeverProvider.ToItemKey(keyOrLink)
    if type(keyOrLink) == "table" then
        if keyOrLink.itemID then
            return {
                itemID = tonumber(keyOrLink.itemID) or 0,
                itemLevel = tonumber(keyOrLink.itemLevel) or 0,
                itemSuffix = tonumber(keyOrLink.itemSuffix) or 0,
                battlePetSpeciesID = tonumber(keyOrLink.battlePetSpeciesID) or 0,
            }
        end
        return nil
    end

    if type(keyOrLink) == "number" or (type(keyOrLink) == "string" and keyOrLink:match("^%d+$")) then
        return {
            itemID = tonumber(keyOrLink),
            itemLevel = 0,
            itemSuffix = 0,
            battlePetSpeciesID = 0,
        }
    end

    if type(keyOrLink) == "string" then
        local dbItemID, dbSuffix = keyOrLink:match("^p:(%d+):(%-?%d+)$")
        if dbItemID then
            return {
                itemID = tonumber(dbItemID),
                itemLevel = 0,
                itemSuffix = tonumber(dbSuffix) or 0,
                battlePetSpeciesID = 0,
            }
        end

        -- Native Key string "itemID:itemLevel:itemSuffix:battlePetSpeciesID"
        local kId, kLvl, kSuf, kPet = keyOrLink:match("^(%d+):(%d+):(%d+):(%d+)$")
        if kId then
            return {
                itemID = tonumber(kId),
                itemLevel = tonumber(kLvl) or 0,
                itemSuffix = tonumber(kSuf) or 0,
                battlePetSpeciesID = tonumber(kPet) or 0,
            }
        end

        -- Parse item link: item:itemID:enchantID:gemID1:gemID2:gemID3:gemID4:suffixID:...
        local itemID = keyOrLink:match("item:(%d+)")
        if itemID then
            local itemString = keyOrLink:match("|H(item:[^|]+)|h") or keyOrLink:match("(item:%d+[^%s|]*)")
            local itemFields = {}
            for field in (itemString or ""):gmatch("([^:]+)") do
                itemFields[#itemFields + 1] = field
            end
            local suffixID = tonumber(itemFields[8]) or 0
            return {
                itemID = tonumber(itemID),
                itemLevel = 0,
                itemSuffix = suffixID,
                battlePetSpeciesID = 0,
            }
        end

        -- Battle pet link: battlepet:speciesID:level:breedQuality:...
        local speciesID = keyOrLink:match("battlepet:(%d+)")
        if speciesID then
            return {
                itemID = 82800, -- Pet Cage
                itemLevel = 0,
                itemSuffix = 0,
                battlePetSpeciesID = tonumber(speciesID) or 0,
            }
        end

        -- Fallback: If keyOrLink is an item name or bracketed name, resolve via C_Item
        local cleanName = keyOrLink:match("%[(.-)%]") or keyOrLink
        if cleanName and cleanName ~= "" then
            local resolvedID = nil
            if C_Item and C_Item.GetItemInfoInstant then
                local ok, res = pcall(C_Item.GetItemInfoInstant, cleanName)
                if ok and tonumber(res) then resolvedID = tonumber(res) end
            elseif GetItemInfoInstant then
                local ok, res = pcall(GetItemInfoInstant, cleanName)
                if ok and tonumber(res) then resolvedID = tonumber(res) end
            end
            if resolvedID and resolvedID > 0 then
                return {
                    itemID = resolvedID,
                    itemLevel = 0,
                    itemSuffix = 0,
                    battlePetSpeciesID = 0,
                }
            end
        end
    end

    return nil
end

function ForeverProvider.ToKeyID(keyOrLink)
    local key = ForeverProvider.ToItemKey(keyOrLink)
    if not key or not key.itemID or key.itemID <= 0 then return nil end
    return table.concat({key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID}, ":")
end

function ForeverProvider.GetSnapshot(keyOrLink)
    local key = ForeverProvider.ToItemKey(keyOrLink)
    if not key then return nil end

    -- 1. Check external scanner or test mock if present
    local scanner = MarketSyncForeverScanner
    if scanner then
        if scanner.Provider and type(scanner.Provider.GetSnapshot) == "function" then
            return scanner.Provider.GetSnapshot(key)
        end
        if scanner.Store and scanner.Store.records then
            local keyID = ForeverProvider.ToKeyID(key)
            local rec = scanner.Store.records[keyID]
            if rec and rec.latest then
                return rec.latest
            end
        end
    end

    -- 2. Check native PersonalData
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if realmDB and realmDB.PersonalData then
        local dbKey = tostring(key.itemID)
        if key.itemSuffix and key.itemSuffix ~= 0 then
            dbKey = "p:" .. key.itemID .. ":" .. key.itemSuffix
        end
        local entry = realmDB.PersonalData[dbKey]
        if entry and entry.m and entry.m > 0 then
            local seenAt = realmDB.PersonalScanTime or time()
            return {
                seenAt = seenAt,
                complete = true,
                minUnitPrice = entry.m,
                available = 1,
                source = "native-personal",
            }
        end
    end

    return nil
end

function ForeverProvider.GetPrice(keyOrLink)
    local snapshot = ForeverProvider.GetSnapshot(keyOrLink)
    if snapshot and snapshot.complete and snapshot.minUnitPrice and snapshot.minUnitPrice > 0 then
        return snapshot.minUnitPrice
    end
    return nil
end

function ForeverProvider.GetPriceAge(keyOrLink)
    local snapshot = ForeverProvider.GetSnapshot(keyOrLink)
    if snapshot and snapshot.seenAt then
        local elapsed = math.max(0, time() - snapshot.seenAt)
        return elapsed / 86400 -- Return in days to match MarketSync conventions
    end
    return nil
end

function ForeverProvider.GetPriceTime(keyOrLink)
    local snapshot = ForeverProvider.GetSnapshot(keyOrLink)
    return snapshot and snapshot.seenAt or nil
end

function ForeverProvider.GetCurrentBucket()
    -- Native Unix 30-minute tracking buckets
    local now = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
    return math.floor(now / 1800)
end

function ForeverProvider.GetMarketID()
    local scanner = MarketSyncForeverScanner
    if scanner and scanner.MarketID then
        return scanner.MarketID
    end
    local realm = GetNormalizedRealmName and (GetNormalizedRealmName() or GetRealmName()) or "UnknownRealm"
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
    return "forever-" .. realm .. "-" .. faction
end

function ForeverProvider.GetLiveStore()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if realmDB and realmDB.PersonalData then
        return realmDB.PersonalData
    end
    local scanner = MarketSyncForeverScanner
    if scanner and scanner.Store then
        return scanner.Store.records
    end
    return nil
end

function ForeverProvider.IsWatchSupported()
    return true
end

function ForeverProvider.ToggleWatch(keyID)
    local scanner = MarketSyncForeverScanner
    if scanner and type(scanner.ToggleWatch) == "function" then
        local resolved = ForeverProvider.ToKeyID(keyID) or keyID
        return scanner.ToggleWatch(resolved)
    end

    local itemID = tonumber(keyID) or tonumber(tostring(keyID):match("(%d+)"))
    if not itemID then return false end
    if MarketSyncDB then
        if not MarketSyncDB.WatchList then MarketSyncDB.WatchList = {} end
        if MarketSyncDB.WatchList[itemID] then
            MarketSyncDB.WatchList[itemID] = nil
            if MarketSync.Favorites then MarketSync.Favorites.RemoveFromList("Favorites", itemID) end
            return false
        else
            MarketSyncDB.WatchList[itemID] = true
            if MarketSync.Favorites then MarketSync.Favorites.AddToList("Favorites", itemID) end
            return true
        end
    end
    return false
end

function ForeverProvider.IsWatched(keyID)
    local scanner = MarketSyncForeverScanner
    if scanner and scanner.Store and scanner.Store.watched then
        local resolved = ForeverProvider.ToKeyID(keyID) or tostring(keyID)
        if scanner.Store.watched[resolved] == true or scanner.Store.watched[tostring(keyID)] == true then
            return true
        end
    end

    local itemID = tonumber(keyID) or tonumber(tostring(keyID):match("(%d+)"))
    if not itemID then return false end
    if MarketSyncDB and MarketSyncDB.WatchList then
        return MarketSyncDB.WatchList[itemID] == true
    end
    if MarketSync.Favorites then
        return MarketSync.Favorites.IsItemInList("Favorites", itemID)
    end
    return false
end

function ForeverProvider.CanExportShoppingList()
    return false
end

function ForeverProvider.ExportShoppingList()
    return false, "Shopping list export requires Auctionator"
end

function ForeverProvider.IsScanActive()
    if MarketSync.Scanner then
        return MarketSync.Scanner.Active == true
    end
    local scanner = MarketSyncForeverScanner
    return scanner and scanner.Active == true or false
end

function ForeverProvider.StartScan()
    if MarketSync.Scanner then
        return MarketSync.Scanner.ScanWatched()
    end
    local scanner = MarketSyncForeverScanner
    if scanner and type(scanner.StartWatched) == "function" then
        return scanner.StartWatched()
    end
    return false
end

function ForeverProvider.StopScan()
    if MarketSync.Scanner and MarketSync.Scanner.Active then
        MarketSync.Scanner.Cancel("Stopped by user")
        return true
    end
    local scanner = MarketSyncForeverScanner
    if scanner and type(scanner.Cancel) == "function" then
        scanner.Cancel("Scan stopped by user")
        return true
    end
    return false
end

function ForeverProvider.Initialize()
    if MarketSync.Scanner and MarketSync.Scanner.RegisterCallback then
        MarketSync.Scanner.RegisterCallback(function()
            if MarketSync.Provider and MarketSync.Provider.TriggerChangeCallbacks then
                MarketSync.Provider.TriggerChangeCallbacks()
            end
        end)
    end
end

if MarketSync.Provider and MarketSync.Provider.Register then
    MarketSync.Provider.Register("forever", ForeverProvider)
end
