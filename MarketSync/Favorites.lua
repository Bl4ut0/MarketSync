-- ================================================================
-- MarketSync - Favorites & Preferred Lists Manager
-- Native shopping and favorite lists for quick targeted scanning
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.Favorites = {}

local F = MarketSync.Favorites
F.ChangeCallbacks = {}

local DEFAULT_LISTS = {
    "Favorites",
    "Consumables",
    "Trade Goods",
}

local VALID_FLAVORS = {
    forever = true,
    classicEra = true,
    anniversary = true,
    classic = true,
    retail = true,
}

local VALID_FACTIONS = {
    Alliance = true,
    Horde = true,
    Neutral = true,
    CrossFaction = true,
    Commodities = true,
}

local MAX_COPPER = 99999999999

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function IsFiniteInteger(n)
    return type(n) == "number" and n == n and n > -9007199254740992 and n < 9007199254740992 and math.floor(n) == n
end

local function EnsureMetaStore(listName)
    if not MarketSyncDB or not listName or listName == "" then return nil end
    MarketSyncDB.FavoriteMeta = MarketSyncDB.FavoriteMeta or {}
    local entry = MarketSyncDB.FavoriteMeta[listName]
    if type(entry) ~= "table" then
        entry = { items = {} }
        MarketSyncDB.FavoriteMeta[listName] = entry
    elseif type(entry.items) ~= "table" then
        entry.items = {}
    end
    return entry
end

function F.Initialize()
    if not MarketSyncDB then return end
    MarketSyncDB.Favorites = MarketSyncDB.Favorites or {}
    MarketSyncDB.FavoriteQuantities = MarketSyncDB.FavoriteQuantities or {}
    MarketSyncDB.FavoriteMeta = MarketSyncDB.FavoriteMeta or {}
    for _, defaultName in ipairs(DEFAULT_LISTS) do
        if not MarketSyncDB.Favorites[defaultName] then
            MarketSyncDB.Favorites[defaultName] = {}
        end
    end
end

function F.RegisterCallback(fn)
    if type(fn) == "function" then
        table.insert(F.ChangeCallbacks, fn)
    end
end

local function NotifyChanged()
    for _, fn in ipairs(F.ChangeCallbacks) do
        pcall(fn)
    end
end

function F.GetLists()
    F.Initialize()
    local lists = {}
    if MarketSyncDB and MarketSyncDB.Favorites then
        for name in pairs(MarketSyncDB.Favorites) do
            table.insert(lists, name)
        end
    end
    table.sort(lists, function(a, b)
        if a == "Favorites" then return true end
        if b == "Favorites" then return false end
        return a < b
    end)
    return lists
end

local function ApplyListMeta(listName, meta)
    if type(meta) ~= "table" then return end
    local store = EnsureMetaStore(listName)
    if not store then return end
    if meta.flavor ~= nil then
        if meta.flavor == false or meta.flavor == "" then
            store.flavor = nil
        elseif VALID_FLAVORS[meta.flavor] then
            store.flavor = meta.flavor
        end
    end
    if meta.realm ~= nil then
        if meta.realm == false then
            store.realm = nil
        else
            local r = Trim(tostring(meta.realm))
            store.realm = (r ~= "") and r or nil
        end
    end
    if meta.faction ~= nil then
        if meta.faction == false or meta.faction == "" then
            store.faction = nil
        elseif VALID_FACTIONS[meta.faction] then
            store.faction = meta.faction
        end
    end
end

function F.CreateList(name, meta)
    F.Initialize()
    name = Trim(name)
    if name == "" then return false, "List name cannot be empty" end
    if MarketSyncDB.Favorites[name] then
        return false, "A list with this name already exists"
    end
    MarketSyncDB.Favorites[name] = {}
    if type(meta) == "table" then
        ApplyListMeta(name, meta)
    end
    NotifyChanged()
    return true
end

function F.DeleteList(name)
    F.Initialize()
    if name == "Favorites" then
        return false, "Cannot delete default Favorites list"
    end
    if not MarketSyncDB.Favorites[name] then
        return false, "List not found"
    end
    MarketSyncDB.Favorites[name] = nil
    if MarketSyncDB.FavoriteQuantities then MarketSyncDB.FavoriteQuantities[name] = nil end
    if MarketSyncDB.FavoriteMeta then MarketSyncDB.FavoriteMeta[name] = nil end
    NotifyChanged()
    return true
end

function F.RenameList(oldName, newName)
    F.Initialize()
    if type(oldName) ~= "string" or oldName == "" or not MarketSyncDB.Favorites[oldName] then
        return false, "List not found"
    end
    if oldName == "Favorites" then
        return false, "Cannot rename default Favorites list"
    end
    newName = Trim(newName)
    if newName == "" then
        return false, "List name cannot be empty"
    end
    if oldName == newName then
        return true
    end
    if MarketSyncDB.Favorites[newName] then
        return false, "A list with this name already exists"
    end
    MarketSyncDB.Favorites[newName] = MarketSyncDB.Favorites[oldName]
    MarketSyncDB.Favorites[oldName] = nil
    if MarketSyncDB.FavoriteQuantities then
        MarketSyncDB.FavoriteQuantities[newName] = MarketSyncDB.FavoriteQuantities[oldName]
        MarketSyncDB.FavoriteQuantities[oldName] = nil
    end
    if MarketSyncDB.FavoriteMeta then
        MarketSyncDB.FavoriteMeta[newName] = MarketSyncDB.FavoriteMeta[oldName]
        MarketSyncDB.FavoriteMeta[oldName] = nil
    end
    NotifyChanged()
    return true
end

local function ExtractItemRef(itemOrLink)
    if type(itemOrLink) == "number" then
        if IsFiniteInteger(itemOrLink) and itemOrLink > 0 then
            return itemOrLink, nil
        end
        return nil, nil
    end
    if type(itemOrLink) == "string" then
        local variantID, variantSuffix = itemOrLink:match("^p:(%d+):(%-?%d+)$")
        if variantID then
            local sid = tonumber(variantSuffix)
            return tonumber(variantID), (sid and sid >= 0) and sid or nil
        end

        local itemString = itemOrLink:match("|H(item:[^|]+)|h") or itemOrLink:match("^(item:%d+[^%s|]*)")
        if itemString then
            local fields = {}
            for field in itemString:gmatch("([^:]+)") do
                fields[#fields + 1] = field
            end
            local idNum = tonumber(fields[2])
            local suffixNum = tonumber(fields[8])
            if idNum and idNum > 0 then
                return idNum, (suffixNum and suffixNum >= 0) and suffixNum or nil
            end
        end

        local idStr = itemOrLink:match("item:(%d+)")
            or itemOrLink:match("^p:(%d+)$")
            or itemOrLink:match("^(%d+)$")
        if idStr then return tonumber(idStr), nil end

        -- Fallback: resolve item name
        local cleanName = itemOrLink:match("%[(.-)%]") or itemOrLink
        cleanName = cleanName:match("^%s*(.-)%s*$")
        if cleanName and cleanName ~= "" then
            if MarketSync and MarketSync.ResolveItemID then
                local ok, id = pcall(MarketSync.ResolveItemID, cleanName)
                if ok and tonumber(id) then return tonumber(id), nil end
            end
            if C_Item and C_Item.GetItemInfoInstant then
                local ok, id = pcall(C_Item.GetItemInfoInstant, cleanName)
                if ok and tonumber(id) then return tonumber(id), nil end
            elseif GetItemInfoInstant then
                local ok, id = pcall(GetItemInfoInstant, cleanName)
                if ok and tonumber(id) then return tonumber(id), nil end
            end
        end
    end
    if type(itemOrLink) == "table" then
        local idNum = tonumber(itemOrLink.itemID or itemOrLink.id)
        local sNum = tonumber(itemOrLink.suffix or itemOrLink.itemSuffix or itemOrLink.s)
        if idNum and idNum > 0 then
            return idNum, (sNum and sNum >= 0) and math.floor(sNum) or nil
        end
    end
    return nil, nil
end

local function ApplyItemMetaPatch(listName, itemKey, patch)
    if type(patch) ~= "table" or itemKey == nil or itemKey == "" then return false end
    local store = EnsureMetaStore(listName)
    if not store then return false end
    local itemMeta = store.items[itemKey]
    if type(itemMeta) ~= "table" then
        itemMeta = {}
    end

    if patch.suffix ~= nil then
        if patch.suffix == false then
            itemMeta.suffix = nil
        else
            local s = tonumber(patch.suffix)
            if s and IsFiniteInteger(s) and s >= 0 then
                itemMeta.suffix = (s > 0) and s or nil
            end
        end
    end

    if patch.maxPrice ~= nil then
        if patch.maxPrice == false then
            itemMeta.maxPrice = nil
        else
            local m = tonumber(patch.maxPrice)
            if m and IsFiniteInteger(m) and m >= 0 and m <= MAX_COPPER then
                itemMeta.maxPrice = m
            end
        end
    end

    if patch.note ~= nil then
        if patch.note == false or patch.note == "" then
            itemMeta.note = nil
        elseif type(patch.note) == "string" then
            itemMeta.note = patch.note
        end
    end

    if patch.done ~= nil then
        if patch.done == true or patch.done == 1 then
            itemMeta.done = true
        else
            itemMeta.done = nil
        end
    end

    if patch.alert ~= nil then
        if patch.alert == true or patch.alert == 1 then
            itemMeta.alert = true
        else
            itemMeta.alert = nil
        end
    end

    if patch.name ~= nil then
        if patch.name == false or patch.name == "" then
            itemMeta.name = nil
        elseif type(patch.name) == "string" then
            itemMeta.name = patch.name
        end
    end

    if next(itemMeta) ~= nil then
        store.items[itemKey] = itemMeta
    else
        store.items[itemKey] = nil
    end
    return true
end

local function FindVariantStoreKey(listName, itemOrLink)
    local itemID, suffixID = ExtractItemRef(itemOrLink)
    if not itemID or itemID <= 0 then return nil, nil, nil end
    if type(itemOrLink) == "string" and itemOrLink:match("^p:%d+:%-?%d+$") then
        local list = MarketSyncDB and MarketSyncDB.Favorites and MarketSyncDB.Favorites[listName]
        if list then
            for _, existing in ipairs(list) do
                if existing == itemOrLink then
                    return itemOrLink, itemID, suffixID
                end
            end
        end
        local metaItems = MarketSyncDB and MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName] and MarketSyncDB.FavoriteMeta[listName].items
        if metaItems and metaItems[itemOrLink] then
            return itemOrLink, itemID, suffixID
        end
        local qtyMap = MarketSyncDB and MarketSyncDB.FavoriteQuantities and MarketSyncDB.FavoriteQuantities[listName]
        if qtyMap and qtyMap[itemOrLink] ~= nil then
            return itemOrLink, itemID, suffixID
        end
    end
    return itemID, itemID, suffixID
end

local function ResolveAddStoreKey(listName, itemID, wantedSuffix)
    local list = MarketSyncDB and MarketSyncDB.Favorites and MarketSyncDB.Favorites[listName]
    local metaItems = MarketSyncDB and MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName] and MarketSyncDB.FavoriteMeta[listName].items
    local normalizedWanted = (tonumber(wantedSuffix) and tonumber(wantedSuffix) > 0) and math.floor(tonumber(wantedSuffix)) or 0

    if normalizedWanted > 0 and list then
        local variantKey = string.format("p:%d:%d", itemID, normalizedWanted)
        for _, existing in ipairs(list) do
            if existing == variantKey then
                return variantKey, true
            end
        end
    end

    if list then
        for _, existing in ipairs(list) do
            if existing == itemID then
                if wantedSuffix == nil then
                    return itemID, true
                end
                local existingMeta = metaItems and metaItems[itemID]
                local existingSuffix = (existingMeta and tonumber(existingMeta.suffix) and tonumber(existingMeta.suffix) > 0)
                    and math.floor(tonumber(existingMeta.suffix)) or 0
                if existingSuffix == normalizedWanted then
                    return itemID, true
                end
                local variantKey = string.format("p:%d:%d", itemID, normalizedWanted)
                for _, entry in ipairs(list) do
                    if entry == variantKey then
                        return variantKey, true
                    end
                end
                return variantKey, false
            end
        end
    end

    return itemID, false
end

function F.GetListMeta(listName)
    F.Initialize()
    listName = listName or "Favorites"
    local entry = MarketSyncDB and MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName]
    if type(entry) ~= "table" then return {} end
    return {
        flavor = entry.flavor,
        realm = entry.realm,
        faction = entry.faction,
    }
end

function F.SetListMeta(listName, meta)
    F.Initialize()
    listName = listName or "Favorites"
    if not MarketSyncDB or not MarketSyncDB.Favorites or not MarketSyncDB.Favorites[listName] then
        return false, "List not found"
    end
    if type(meta) ~= "table" then return false, "Invalid metadata" end
    ApplyListMeta(listName, meta)
    NotifyChanged()
    return true
end

function F.GetItemMeta(listName, itemOrLink)
    F.Initialize()
    listName = listName or "Favorites"
    local storeKey, itemID = FindVariantStoreKey(listName, itemOrLink)
    if not itemID or not MarketSyncDB or not MarketSyncDB.FavoriteMeta then return nil end
    local entry = MarketSyncDB.FavoriteMeta[listName]
    local raw = entry and entry.items and (entry.items[storeKey] or entry.items[itemID])
    if type(raw) ~= "table" then return nil end
    return {
        suffix = raw.suffix,
        maxPrice = raw.maxPrice,
        note = raw.note,
        done = raw.done == true,
        alert = raw.alert == true,
        name = raw.name,
    }
end

function F.SetItemMeta(listName, itemOrLink, patch)
    F.Initialize()
    listName = listName or "Favorites"
    local storeKey, itemID, refSuffix = FindVariantStoreKey(listName, itemOrLink)
    if not itemID or itemID <= 0 then return false, "Invalid item" end
    if type(patch) ~= "table" then return false, "Invalid metadata" end
    local mergedPatch = {}
    for k, v in pairs(patch) do mergedPatch[k] = v end
    if mergedPatch.suffix == nil and refSuffix ~= nil then
        mergedPatch.suffix = refSuffix
    end
    local ok = ApplyItemMetaPatch(listName, storeKey, mergedPatch)
    if ok then NotifyChanged() end
    return ok
end

function F.AddToList(listName, itemOrLink, opts)
    F.Initialize()
    listName = listName or "Favorites"
    local itemID, suffixID = ExtractItemRef(itemOrLink)
    if not itemID or itemID <= 0 then return false, "Invalid item" end

    MarketSyncDB.Favorites[listName] = MarketSyncDB.Favorites[listName] or {}
    local list = MarketSyncDB.Favorites[listName]

    local wantedSuffix = (type(opts) == "table" and opts.suffix ~= nil) and tonumber(opts.suffix) or suffixID
    local storeKey, exists = ResolveAddStoreKey(listName, itemID, wantedSuffix)

    if not exists then
        table.insert(list, storeKey)
    end

    local hasMetaPatch = type(opts) == "table" or (suffixID ~= nil and suffixID > 0)
    if hasMetaPatch then
        local patch = {}
        if type(opts) == "table" then
            for k, v in pairs(opts) do patch[k] = v end
        end
        if patch.suffix == nil and suffixID ~= nil then
            patch.suffix = suffixID
        end
        ApplyItemMetaPatch(listName, storeKey, patch)
        if type(opts) == "table" and tonumber(opts.quantity) and tonumber(opts.quantity) >= 1 then
            MarketSyncDB.FavoriteQuantities = MarketSyncDB.FavoriteQuantities or {}
            MarketSyncDB.FavoriteQuantities[listName] = MarketSyncDB.FavoriteQuantities[listName] or {}
            MarketSyncDB.FavoriteQuantities[listName][storeKey] = math.floor(tonumber(opts.quantity))
        end
    end

    if not exists or hasMetaPatch then
        NotifyChanged()
    end
    return true, storeKey
end

function F.RemoveFromList(listName, itemOrLink)
    F.Initialize()
    listName = listName or "Favorites"
    local storeKey, itemID = FindVariantStoreKey(listName, itemOrLink)
    if not itemID then return false end

    local list = MarketSyncDB.Favorites[listName]
    if not list then return false end

    for idx, existingID in ipairs(list) do
        if existingID == storeKey or (storeKey == itemID and existingID == itemID) then
            table.remove(list, idx)
            if MarketSyncDB.FavoriteQuantities and MarketSyncDB.FavoriteQuantities[listName] then
                MarketSyncDB.FavoriteQuantities[listName][existingID] = nil
            end
            if MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName] and MarketSyncDB.FavoriteMeta[listName].items then
                MarketSyncDB.FavoriteMeta[listName].items[existingID] = nil
            end
            NotifyChanged()
            return true
        end
    end
    return false
end

function F.SetQuantity(listName, itemOrLink, quantity)
    F.Initialize()
    local storeKey, itemID = FindVariantStoreKey(listName, itemOrLink)
    local qty = tonumber(quantity)
    if not itemID or not qty or qty < 1 then return false end
    MarketSyncDB.FavoriteQuantities = MarketSyncDB.FavoriteQuantities or {}
    MarketSyncDB.FavoriteQuantities[listName] = MarketSyncDB.FavoriteQuantities[listName] or {}
    MarketSyncDB.FavoriteQuantities[listName][storeKey] = math.floor(qty)
    NotifyChanged()
    return true
end

function F.GetQuantity(listName, itemOrLink)
    local storeKey, itemID = FindVariantStoreKey(listName, itemOrLink)
    if not itemID or not MarketSyncDB or not MarketSyncDB.FavoriteQuantities or not MarketSyncDB.FavoriteQuantities[listName] then
        return 1
    end
    local qtyMap = MarketSyncDB.FavoriteQuantities[listName]
    return qtyMap[storeKey] or qtyMap[itemID] or 1
end

function F.IsItemInList(listName, itemOrLink)
    F.Initialize()
    listName = listName or "Favorites"
    local storeKey, itemID = FindVariantStoreKey(listName, itemOrLink)
    if not itemID then return false end

    local list = MarketSyncDB.Favorites[listName]
    if not list then return false end

    for _, existingID in ipairs(list) do
        if existingID == storeKey or existingID == itemID then return true end
    end
    return false
end

function F.ToggleItemInList(listName, itemOrLink)
    if F.IsItemInList(listName, itemOrLink) then
        F.RemoveFromList(listName, itemOrLink)
        return false
    else
        F.AddToList(listName, itemOrLink)
        return true
    end
end

function F.GetList(listName)
    F.Initialize()
    listName = listName or "Favorites"
    return MarketSyncDB.Favorites[listName] or {}
end

function F.GetListItems(listName)
    F.Initialize()
    listName = listName or "Favorites"
    local list = MarketSyncDB.Favorites[listName] or {}
    local metaEntry = MarketSyncDB and MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName]
    local metaItems = metaEntry and metaEntry.items
    local items = {}

    for _, rawEntry in ipairs(list) do
        local itemID, entrySuffix = ExtractItemRef(rawEntry)
        if itemID then
            local meta = metaItems and (metaItems[rawEntry] or (type(rawEntry) == "number" and metaItems[itemID] or nil)) or nil
            local suffix = (meta and tonumber(meta.suffix) and tonumber(meta.suffix) > 0)
                and math.floor(tonumber(meta.suffix))
                or ((entrySuffix and entrySuffix > 0) and entrySuffix or 0)
            local dbKey = (suffix > 0) and string.format("p:%d:%d", itemID, suffix) or tostring(itemID)
            local lookupKey = (suffix > 0) and string.format("item:%d:0:0:0:0:0:%d:0", itemID, suffix) or itemID

        local name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon
        if MarketSync and MarketSync.GetItemInfo then
            name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = MarketSync.GetItemInfo(lookupKey)
            if not name and suffix > 0 then
                name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = MarketSync.GetItemInfo(itemID)
            end
        elseif C_Item and C_Item.GetItemInfo then
            name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = C_Item.GetItemInfo(lookupKey)
            if not name and suffix > 0 then
                name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = C_Item.GetItemInfo(itemID)
            end
        elseif GetItemInfo then
            name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = GetItemInfo(lookupKey)
            if not name and suffix > 0 then
                name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = GetItemInfo(itemID)
            end
        end
        -- If not loaded yet, check complete cache entry (never store partial entries in ItemInfoCache)
        if not name and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
            local c = MarketSyncDB.ItemInfoCache[itemID]
            name = c.n
            quality = c.r
            icon = c.ic
            ilvl = c.i
        end
        if not name then
            if MarketSync and MarketSync.RequestItemData then
                pcall(MarketSync.RequestItemData, itemID)
            elseif C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, itemID)
            elseif GetItemInfo then
                pcall(GetItemInfo, itemID)
            end
        end
        local fallbackName = (meta and type(meta.name) == "string" and meta.name ~= "") and meta.name or nil
        local defaultLink = (suffix > 0) and string.format("item:%d:0:0:0:0:0:%d:0", itemID, suffix) or ("item:" .. itemID)
        table.insert(items, {
            itemID = itemID,
            name = name or fallbackName or ("Item #" .. itemID),
            link = link or defaultLink,
            icon = icon or 134400,
            quality = quality or 1,
            ilvl = ilvl or 0,
            quantity = F.GetQuantity(listName, rawEntry),
            suffix = suffix,
            dbKey = dbKey,
            maxPrice = meta and meta.maxPrice or nil,
            note = meta and meta.note or nil,
            done = (meta and meta.done == true) or false,
            alert = (meta and meta.alert == true) or false,
            cachedName = fallbackName,
        })
        end
    end

    table.sort(items, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return items
end
