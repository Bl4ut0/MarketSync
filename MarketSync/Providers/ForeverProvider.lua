-- ================================================================
-- MarketSync - Forever Provider Implementation
-- Connects MarketSync to Forever's native C_AuctionHouse scanner.
-- ================================================================

MarketSync = MarketSync or {}
local S = MarketSyncForeverScanner

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

        -- Try Blizzard C_AuctionHouse native helper if present
        if C_AuctionHouse and type(C_AuctionHouse.GetItemKeyFromItem) == "function" then
            local ok, itemKey = pcall(C_AuctionHouse.GetItemKeyFromItem, ItemLocation:CreateFromItemLink(keyOrLink))
            if ok and itemKey and itemKey.itemID then
                return {
                    itemID = itemKey.itemID,
                    itemLevel = itemKey.itemLevel or 0,
                    itemSuffix = itemKey.itemSuffix or 0,
                    battlePetSpeciesID = itemKey.battlePetSpeciesID or 0,
                }
            end
        end

        -- Parse item link: item:itemID:enchantID:gemID1:gemID2:gemID3:gemID4:suffixID:...
        local itemID, _, _, _, _, _, suffixID = keyOrLink:match("item:(%d+):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*)")
        if itemID then
            return {
                itemID = tonumber(itemID),
                itemLevel = 0,
                itemSuffix = tonumber(suffixID) or 0,
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
    end

    return nil
end

function ForeverProvider.ToKeyID(keyOrLink)
    local key = ForeverProvider.ToItemKey(keyOrLink)
    if not key or not key.itemID or key.itemID <= 0 then return nil end
    return table.concat({key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID}, ":")
end

function ForeverProvider.GetSnapshot(keyOrLink)
    local scanner = MarketSyncForeverScanner
    if not scanner then return nil end

    local key = ForeverProvider.ToItemKey(keyOrLink)
    if not key then return nil end

    -- Check if this is an item-ID-only lookup without specified variants
    local isGenericItemID = (type(keyOrLink) == "number") or (type(keyOrLink) == "string" and keyOrLink:match("^%d+$"))
    if isGenericItemID and scanner.Store and scanner.Store.records then
        local matches = {}
        for id, rec in pairs(scanner.Store.records) do
            if rec.key and rec.key.itemID == key.itemID then
                table.insert(matches, rec)
            end
        end
        if #matches == 0 then
            return nil
        elseif #matches > 1 then
            -- Multiple variants exist for this item ID.
            -- Rule: Check if exact base variant (0:0:0) exists.
            local baseID = table.concat({key.itemID, 0, 0, 0}, ":")
            if scanner.Store.records[baseID] and scanner.Store.records[baseID].latest then
                local snap = scanner.Store.records[baseID].latest
                if snap.complete then return scanner.CopySnapshot and scanner.CopySnapshot(snap) or snap end
            end
            -- Ambiguous variants: do not guess.
            return nil
        end
        -- Exactly one record for this itemID
        local snap = matches[1].latest
        if snap and snap.complete then
            return scanner.CopySnapshot and scanner.CopySnapshot(snap) or snap
        end
        return nil
    end

    if scanner.Provider and type(scanner.Provider.GetSnapshot) == "function" then
        return scanner.Provider.GetSnapshot(key)
    end
    return nil
end

function ForeverProvider.GetPrice(keyOrLink)
    local snapshot = ForeverProvider.GetSnapshot(keyOrLink)
    -- Complete quote check: browse-only observations have a separate advertised price
    -- and cannot produce a fresh usable buyout quote.
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

function ForeverProvider.GetCurrentBucket()
    -- Native Unix 30-minute tracking buckets
    return math.floor(time() / 1800)
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
    return false
end

function ForeverProvider.IsWatched(keyID)
    local scanner = MarketSyncForeverScanner
    if scanner and scanner.Store and scanner.Store.watched then
        local resolved = ForeverProvider.ToKeyID(keyID) or keyID
        return scanner.Store.watched[resolved] == true
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
    local scanner = MarketSyncForeverScanner
    return scanner and scanner.Active == true or false
end

function ForeverProvider.StartScan()
    local scanner = MarketSyncForeverScanner
    if scanner and type(scanner.StartWatched) == "function" then
        return scanner.StartWatched()
    end
    return false
end

function ForeverProvider.StopScan()
    local scanner = MarketSyncForeverScanner
    if scanner and type(scanner.Cancel) == "function" then
        scanner.Cancel("Scan stopped by user")
        return true
    end
    return false
end

function ForeverProvider.Initialize()
    if MarketSyncForeverScanner and type(MarketSyncForeverScanner.RegisterListener) == "function" then
        MarketSyncForeverScanner.RegisterListener(function()
            if MarketSync.Provider and MarketSync.Provider.TriggerChangeCallbacks then
                MarketSync.Provider.TriggerChangeCallbacks()
            end
        end)
    end
end

if MarketSync.Provider and MarketSync.Provider.Register then
    MarketSync.Provider.Register("forever", ForeverProvider)
end
