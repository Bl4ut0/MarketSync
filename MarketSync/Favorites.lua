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

function F.Initialize()
    if not MarketSyncDB then return end
    MarketSyncDB.Favorites = MarketSyncDB.Favorites or {}
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

function F.CreateList(name)
    F.Initialize()
    if not name or name == "" then return false, "List name cannot be empty" end
    name = name:match("^%s*(.-)%s*$")
    if MarketSyncDB.Favorites[name] then
        return false, "A list with this name already exists"
    end
    MarketSyncDB.Favorites[name] = {}
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
    NotifyChanged()
    return true
end

local function ExtractItemID(itemOrLink)
    if type(itemOrLink) == "number" then return itemOrLink end
    if type(itemOrLink) == "string" then
        local idStr = itemOrLink:match("item:(%d+)") or itemOrLink:match("^(%d+)$")
        if idStr then return tonumber(idStr) end
    end
    if type(itemOrLink) == "table" and itemOrLink.itemID then
        return tonumber(itemOrLink.itemID)
    end
    return nil
end

function F.AddToList(listName, itemOrLink)
    F.Initialize()
    listName = listName or "Favorites"
    local itemID = ExtractItemID(itemOrLink)
    if not itemID or itemID <= 0 then return false, "Invalid item" end

    MarketSyncDB.Favorites[listName] = MarketSyncDB.Favorites[listName] or {}
    local list = MarketSyncDB.Favorites[listName]

    for _, existingID in ipairs(list) do
        if existingID == itemID then
            return true -- Already in list
        end
    end

    table.insert(list, itemID)
    NotifyChanged()
    return true
end

function F.RemoveFromList(listName, itemOrLink)
    F.Initialize()
    listName = listName or "Favorites"
    local itemID = ExtractItemID(itemOrLink)
    if not itemID then return false end

    local list = MarketSyncDB.Favorites[listName]
    if not list then return false end

    for idx, existingID in ipairs(list) do
        if existingID == itemID then
            table.remove(list, idx)
            NotifyChanged()
            return true
        end
    end
    return false
end

function F.IsItemInList(listName, itemOrLink)
    F.Initialize()
    listName = listName or "Favorites"
    local itemID = ExtractItemID(itemOrLink)
    if not itemID then return false end

    local list = MarketSyncDB.Favorites[listName]
    if not list then return false end

    for _, existingID in ipairs(list) do
        if existingID == itemID then return true end
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

function F.GetListItems(listName)
    F.Initialize()
    listName = listName or "Favorites"
    local list = MarketSyncDB.Favorites[listName] or {}
    local items = {}

    for _, itemID in ipairs(list) do
        local name, link, quality, ilvl, minLevel, itemType, itemSubType, _, _, icon = C_Item.GetItemInfo(itemID)
        -- If not loaded yet, check cache or provide fallback
        if not name and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
            local c = MarketSyncDB.ItemInfoCache[itemID]
            name = c.n
            quality = c.r
            icon = c.ic
            ilvl = c.i
        end
        if not name then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        table.insert(items, {
            itemID = itemID,
            name = name or ("Item #" .. itemID),
            link = link or ("item:" .. itemID),
            icon = icon or 134400,
            quality = quality or 1,
            ilvl = ilvl or 0,
        })
    end

    table.sort(items, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return items
end
