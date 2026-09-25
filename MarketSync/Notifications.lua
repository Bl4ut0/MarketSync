-- =============================================================
-- MarketSync - Notifications Module
-- Threshold alerts + Auctionator shopping list import
-- =============================================================

local ADDON_CALLER_ID = "MarketSync"
local PERIODIC_FRESHNESS_SECONDS = 300
MarketSync.NotificationsMuted = false -- Session only; never persisted.

function MarketSync.ToggleNotificationMute()
    MarketSync.NotificationsMuted = not MarketSync.NotificationsMuted
    if MarketSync.NotificationsMuted then
        if MarketSync.StopMinimapFlash then MarketSync.StopMinimapFlash() end
        print("|cff00ff00[MarketSync]|r Alerts muted until logout or Shift-Left-Click on the minimap button again.")
    else
        MarketSync.RefreshNotificationUnreadState()
        print("|cff00ff00[MarketSync]|r Alerts enabled.")
    end
    return MarketSync.NotificationsMuted
end

local function NormalizeScope(scope)
    if scope == "main" or scope == "neutral" or scope == "all" then
        return scope
    end
    return "all"
end

local function NormalizeVariantMode(mode)
    if mode == "exact_key" or mode == "any_suffix" then
        return mode
    end
    return "any_suffix"
end

local function BuildRequestID(matchType, matchValue, scope)
    local safe = tostring(matchValue or ""):gsub("[^%w:_%-]", "_")
    return string.format("%s:%s:%s", tostring(matchType or "name"), safe, NormalizeScope(scope))
end

local function GetRequestState(realmDB, requestID)
    if not realmDB.NotificationState[requestID] then
        realmDB.NotificationState[requestID] = {
            lastAlertAt = 0,
            lastAlertPrice = 0,
            armed = true,
        }
    end
    return realmDB.NotificationState[requestID]
end

local function ResolveItemName(itemID)
    if not itemID then return nil end
    local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID]
    if cache and cache.n then return cache.n end
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
    if not name and GetItemInfo then
        name = GetItemInfo(itemID)
    end
    return name
end

local function StripColorCodes(text)
    return tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function MarketSync.PlayNotificationSound(soundID, preview)
    local id = tonumber(soundID)
    if not id or id <= 0 then return false end
    if MarketSync.NotificationsMuted and not preview then return false end
    if not preview and (not MarketSyncDB or not MarketSyncDB.EnableNotificationSounds) then
        return false
    end

    -- WoW does not expose a per-PlaySound gain parameter. A zero preference is
    -- still honored as a hard mute; non-zero alerts use the player's Master mix.
    local volume = MarketSyncDB and tonumber(MarketSyncDB.NotificationVolume) or 1
    if volume <= 0 then return false end
    local ok = pcall(PlaySound, id, "Master")
    return ok
end

function MarketSync.AcknowledgeNotifications()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if realmDB then
        realmDB.NotificationLog = realmDB.NotificationLog or {}
        for _, entry in ipairs(realmDB.NotificationLog) do
            entry.read = true
        end
        realmDB.NotificationLastViewedAt = time()
    end
    MarketSync.NotificationUnreadCount = 0
    if MarketSync.StopMinimapFlash then
        MarketSync.StopMinimapFlash()
    end
end

function MarketSync.RefreshNotificationUnreadState()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    local unread = 0
    for _, entry in ipairs((realmDB and realmDB.NotificationLog) or {}) do
        -- Older log rows predate persisted acknowledgement. Treat only rows
        -- explicitly written as unread by this release as pending alerts.
        if entry.read == false then unread = unread + 1 end
    end
    MarketSync.NotificationUnreadCount = unread
    if unread <= 0 and MarketSync.StopMinimapFlash then
        MarketSync.StopMinimapFlash()
    elseif unread > 0 and not MarketSync.NotificationsMuted
        and (not MarketSyncDB or MarketSyncDB.EnableMinimapAlerts ~= false)
        and MarketSync.StartMinimapFlash then
        MarketSync.StartMinimapFlash()
    end
    return unread
end

local function AlertNotification(req, state, itemName, price, eventScope, sourceName, isUrgent)
    if MarketSync.NotificationsMuted then return end
    local threshold = req.thresholdCopper or 0
    local scope = NormalizeScope(eventScope or req.scope)
    local scopeText = (scope == "neutral") and "Neutral" or ((scope == "main") and "Main" or "Any")
    local urgentText = isUrgent and " |cffff4444[URGENT]|r" or ""
    local msg = string.format(
        "|cFF00FF00[MarketSync Alert]|r%s %s dropped to %s (threshold %s, scope: %s).",
        urgentText,
        itemName or req.displayName or req.matchValue or "Tracked item",
        MarketSync.FormatMoney(price),
        MarketSync.FormatMoney(threshold),
        scopeText
    )
    print(msg)

    if MarketSyncDB and MarketSyncDB.EnableRaidWarningAlerts ~= false
        and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, StripColorCodes(msg), ChatTypeInfo["RAID_WARNING"])
    end

    if MarketSyncDB and MarketSyncDB.EnableNotificationSounds then
        local soundID = MarketSyncDB.NotificationSoundID or 8959
        local perID = req.id and MarketSyncDB.PerNotificationSounds and MarketSyncDB.PerNotificationSounds[req.id]
        if perID == 0 then
            -- Muted for this specific item
            soundID = nil
        elseif perID and perID > 0 then
            soundID = perID
        end

        if soundID and soundID > 0 then
            MarketSync.PlayNotificationSound(soundID, false)
        end
    end

    MarketSync.NotificationUnreadCount = (MarketSync.NotificationUnreadCount or 0) + 1

    -- Trigger the default visual notification channel.
    if (not MarketSyncDB or MarketSyncDB.EnableMinimapAlerts ~= false) and MarketSync.StartMinimapFlash then
        MarketSync.StartMinimapFlash()
    end

    local realmDB = MarketSync.GetRealmDB()
    realmDB.NotificationLog = realmDB.NotificationLog or {}

    local itemID = nil
    if req.matchType == "itemID" then
        itemID = tonumber(req.matchValue)
    elseif req.matchType == "dbKey" and MarketSync.ParseItemIDFromDBKey then
        itemID = MarketSync.ParseItemIDFromDBKey(req.matchValue)
    end
    if not itemID and itemName and MarketSync.ResolveItemID then
        itemID = MarketSync.ResolveItemID(itemName)
    end

    local itemLink = nil
    local itemIcon = nil
    if itemID then
        local _, link, _, _, _, _, _, _, _, icon = MarketSync.GetItemInfo(itemID)
        itemLink = link
        itemIcon = icon or (MarketSync.GetItemIcon and MarketSync.GetItemIcon(itemID))
    end

    table.insert(realmDB.NotificationLog, 1, {
        requestID = req.id,
        itemName = itemName or req.displayName or (itemID and ("Item " .. itemID)) or "Unknown",
        itemLink = itemLink,
        itemID = itemID,
        itemIcon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
        price = price,
        threshold = threshold,
        scope = scope,
        source = sourceName,
        dbKey = req.matchType == "dbKey" and req.matchValue or nil,
        urgent = isUrgent and true or false,
        time = time(),
        read = false,
    })
    if #realmDB.NotificationLog > 50 then
        local removed = table.remove(realmDB.NotificationLog)
        if removed and removed.read == false then
            MarketSync.NotificationUnreadCount = math.max(0,
                (tonumber(MarketSync.NotificationUnreadCount) or 0) - 1)
        end
    end
end

function MarketSync.ClearNotificationLog()
    local realmDB = MarketSync.GetRealmDB()
    if realmDB then
        realmDB.NotificationLog = {}
    end
    MarketSync.NotificationUnreadCount = 0
end

function MarketSync.MarkAllNotificationsRead()
    local realmDB = MarketSync.GetRealmDB()
    if realmDB and realmDB.NotificationLog then
        for _, entry in ipairs(realmDB.NotificationLog) do
            entry.read = true
        end
    end
    MarketSync.NotificationUnreadCount = 0
end

function MarketSync.UpsertNotificationRequest(req)
    local realmDB = MarketSync.GetRealmDB()
    local matchType = req.matchType or "name"
    local matchValue = req.matchValue or req.displayName
    if not matchValue then return nil end

    local scope = NormalizeScope(req.scope)
    local requestedID = req.id and tostring(req.id) or nil
    local requestedExisting = requestedID and realmDB.NotificationRequests[requestedID] or nil
    local canonicalID = BuildRequestID(matchType, matchValue, scope)

    -- An ID contains the request scope. Keeping the old ID while changing scope
    -- corrupts that identity and can later create an apparently unrelated
    -- duplicate. Preserve a stable ID while the identity is unchanged, but
    -- atomically re-key an edited request when any identity field changes.
    local identityChanged = requestedExisting and (
        requestedExisting.matchType ~= matchType
        or tostring(requestedExisting.matchValue) ~= tostring(matchValue)
        or NormalizeScope(requestedExisting.scope) ~= scope
    )
    local requestID = (requestedExisting and not identityChanged) and requestedID or canonicalID
    local now = time()

    local existing = requestedExisting or realmDB.NotificationRequests[requestID] or {}
    local previousThreshold = tonumber(existing.thresholdCopper)

    if requestedExisting and requestID ~= requestedID then
        local targetState = realmDB.NotificationState[requestID]
        local sourceState = realmDB.NotificationState[requestedID]
        if not targetState and sourceState then
            realmDB.NotificationState[requestID] = sourceState
        elseif targetState and sourceState
            and (tonumber(sourceState.lastAlertAt) or 0) > (tonumber(targetState.lastAlertAt) or 0) then
            realmDB.NotificationState[requestID] = sourceState
        end

        if MarketSyncDB and MarketSyncDB.PerNotificationSounds then
            if MarketSyncDB.PerNotificationSounds[requestID] == nil then
                MarketSyncDB.PerNotificationSounds[requestID] = MarketSyncDB.PerNotificationSounds[requestedID]
            end
            MarketSyncDB.PerNotificationSounds[requestedID] = nil
        end

        realmDB.NotificationRequests[requestedID] = nil
        realmDB.NotificationState[requestedID] = nil
    end

    existing.id = requestID
    existing.matchType = matchType
    existing.matchValue = matchValue
    existing.displayName = req.displayName or existing.displayName or tostring(matchValue)
    existing.thresholdCopper = tonumber(req.thresholdCopper) or existing.thresholdCopper or 0
    existing.scope = scope
    existing.variantMode = NormalizeVariantMode(req.variantMode)
    -- Hard 1-hour cooldown (3600s) default
    existing.cooldownSec = 3600
    existing.enabled = (req.enabled == nil) and (existing.enabled ~= false) or not not req.enabled
    existing.urgent = (req.urgent == nil) and (existing.urgent == true) or not not req.urgent
    existing.createdAt = existing.createdAt or now
    existing.quantityHint = tonumber(req.quantityHint) or existing.quantityHint
    existing.importSource = req.importSource or existing.importSource

    realmDB.NotificationRequests[requestID] = existing
    local state = GetRequestState(realmDB, requestID)
    if previousThreshold and previousThreshold ~= existing.thresholdCopper then
        state.armed = true
    end
    return existing
end

function MarketSync.DeleteNotificationRequest(requestID)
    local realmDB = MarketSync.GetRealmDB()
    realmDB.NotificationRequests[requestID] = nil
    realmDB.NotificationState[requestID] = nil
    if MarketSyncDB and MarketSyncDB.PerNotificationSounds then
        MarketSyncDB.PerNotificationSounds[requestID] = nil
    end
end

function MarketSync.ListNotificationRequests()
    local realmDB = MarketSync.GetRealmDB()
    local out = {}
    for _, req in pairs(realmDB.NotificationRequests) do
        table.insert(out, req)
    end
    table.sort(out, function(a, b)
        return (a.displayName or a.id or ""):lower() < (b.displayName or b.id or ""):lower()
    end)
    return out
end

local function RequestMatches(req, dbKey, itemID, itemName)
    if req.matchType == "dbKey" then
        if req.variantMode == "any_suffix" then
            local reqID = MarketSync.ParseItemIDFromDBKey(req.matchValue)
            return reqID and itemID and reqID == itemID
        end
        return tostring(req.matchValue) == tostring(dbKey)
    elseif req.matchType == "itemID" then
        return tonumber(req.matchValue) and itemID and tonumber(req.matchValue) == itemID
    else
        if not itemName then return false end
        local needle = tostring(req.matchValue):lower()
        local hay = itemName:lower()
        if req.variantMode == "any_suffix" then
            return hay:find(needle, 1, true) ~= nil
        end
        return hay == needle
    end
end

local function ScopeAllows(reqScope, eventScope)
    reqScope = NormalizeScope(reqScope)
    eventScope = NormalizeScope(eventScope)
    if reqScope == "all" then return true end
    if eventScope == "all" then return true end
    return reqScope == eventScope
end

local function EvaluateMatchedRequest(realmDB, id, req, price, eventScope, sourceName, itemName, now)
    local threshold = tonumber(req.thresholdCopper) or 0
    if threshold <= 0 then return false end
    if price > threshold then return false end

    local state = GetRequestState(realmDB, id)
    local settings = realmDB.NotificationSettings or {}
    local HARD_HOURLY_LIMIT = 3600
    local cooldown = HARD_HOURLY_LIMIT
    local urgentMinInterval = math.max(1, tonumber(settings.urgentMinIntervalSec) or 10)
    local sinceAlert = now - (state.lastAlertAt or 0)

    -- Check if price actually changed within the last hour
    local hasLastPrice = (state.lastAlertPrice ~= nil and state.lastAlertPrice > 0)
    local priceChanged = (not hasLastPrice) or (price ~= state.lastAlertPrice)

    if sinceAlert < cooldown then
        -- Within the 1-hour window: only alert if there is actually a price change
        if not priceChanged then
            return false
        end
        -- Enforce debounce between price-change notifications to avoid multi-packet bursts
        if sinceAlert < urgentMinInterval then
            return false
        end
    end

    local isUrgent = (req.urgent == true)
    state.lastAlertAt = now
    state.lastAlertPrice = price
    state.armed = false
    AlertNotification(req, state, itemName, price, eventScope, sourceName, isUrgent)
    return true
end

function MarketSync.EvaluateNotificationsForRecord(dbKey, price, eventScope, sourceName, explicitName, explicitItemID)
    if MarketSync.NotificationsMuted then return 0 end
    local realmDB = MarketSync.GetRealmDB()
    if not realmDB or not realmDB.NotificationRequests then return 0 end
    if not price or price <= 0 then return 0 end

    local itemID = explicitItemID or MarketSync.ParseItemIDFromDBKey(dbKey)
    local itemName = explicitName or ResolveItemName(itemID)
    local now = time()
    local alerted = 0

    for id, req in pairs(realmDB.NotificationRequests) do
        if req.enabled ~= false and ScopeAllows(req.scope, eventScope) and RequestMatches(req, dbKey, itemID, itemName) then
            if EvaluateMatchedRequest(realmDB, id, req, price, eventScope, sourceName, itemName, now) then
                alerted = alerted + 1
            end
        end
    end

    return alerted
end

local function ResolveTrackedItemID(req)
    if req.matchType == "itemID" then return tonumber(req.matchValue) end
    if req.matchType == "dbKey" then
        return MarketSync.ParseItemIDFromDBKey(req.matchValue)
    end
    if MarketSync.ResolveItemID then
        return MarketSync.ResolveItemID(req.displayName or req.matchValue)
    end
    return nil
end

local function GetEntryByKey(container, dbKey)
    if not container or dbKey == nil then return nil end
    local entry = container[dbKey] or container[tostring(dbKey)]
    if not entry then
        local numericKey = tonumber(dbKey)
        if numericKey then entry = container[numericKey] end
    end
    return entry
end

local function IsFreshLocalObservation(entry, now)
    local observedAt = tonumber(entry and entry.observedAt) or 0
    return observedAt > 0 and (now - observedAt) >= 0
        and (now - observedAt) <= PERIODIC_FRESHNESS_SECONDS
end

local function GetExactMainTrackedPrice(dbKey)
    if MarketSync.Provider and MarketSync.Provider.GetPrice then
        local p = MarketSync.Provider.GetPrice(dbKey)
        if p and p > 0 then return p end
    end
    local db = Auctionator and Auctionator.Database and Auctionator.Database.db
    if not db or dbKey == nil then return nil end

    local data = GetEntryByKey(db, dbKey)
    local price = tonumber(data and data.m)
    return (price and price > 0) and price or nil
end

local function GetMainTrackedPrice(realmDB, req, itemID, now, requireFresh)
    local dbKey = req.matchType == "dbKey" and NormalizeVariantMode(req.variantMode) == "exact_key"
        and req.matchValue or (itemID and tostring(itemID))
    if not dbKey or (requireFresh and not IsFreshLocalObservation(
        GetEntryByKey(realmDB.PersonalData, dbKey), now)) then
        return nil
    end
    if req.matchType == "dbKey" and NormalizeVariantMode(req.variantMode) == "exact_key" then
        return GetExactMainTrackedPrice(dbKey)
    end
    if MarketSync.Provider and MarketSync.Provider.GetPrice then
        local p = MarketSync.Provider.GetPrice(itemID)
        if p and p > 0 then return p end
    end
    if not itemID or not Auctionator or not Auctionator.API or not Auctionator.API.v1 then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_CALLER_ID, itemID)
    if ok and tonumber(price) and tonumber(price) > 0 then return tonumber(price) end
    return nil
end

local function BuildNeutralTrackedPriceIndex(realmDB, now, requireFresh)
    local byKey = {}
    local byItemID = {}
    for dbKey, data in pairs(realmDB.NeutralData or {}) do
        local price = tonumber(data and data.m)
        if price and price > 0 and (not requireFresh or IsFreshLocalObservation(data, now)) then
            byKey[tostring(dbKey)] = price
            local itemID = MarketSync.ParseItemIDFromDBKey(dbKey)
            if itemID and (not byItemID[itemID] or price < byItemID[itemID]) then
                byItemID[itemID] = price
            end
        end
    end
    return byKey, byItemID
end

local function GetNeutralTrackedPrice(req, itemID, byKey, byItemID)
    if req.matchType == "dbKey" and NormalizeVariantMode(req.variantMode) == "exact_key" then
        return byKey[tostring(req.matchValue)]
    end
    return itemID and byItemID[itemID] or nil
end

-- Low-cost scan/periodic evaluator: iterates tracked requests, never the full AH database.
function MarketSync.EvaluateTrackedNotifications(eventScope, sourceName)
    if MarketSync.NotificationsMuted then return 0 end
    local scope = NormalizeScope(eventScope)
    local realmDB = MarketSync.GetRealmDB()
    local alerted = 0
    local now = time()
    local neutralByKey, neutralByItemID
    if scope == "neutral" then
        -- One linear index build per sweep; requests no longer each rescan the
        -- entire neutral database. The exact-key map keeps suffix variants intact.
        neutralByKey, neutralByItemID = BuildNeutralTrackedPriceIndex(realmDB, now, isPeriodic)
    end

    for id, req in pairs(realmDB.NotificationRequests or {}) do
        if req.enabled ~= false and ScopeAllows(req.scope, scope) then
            local itemID = ResolveTrackedItemID(req)
            local exactDBKey = req.matchType == "dbKey"
                and NormalizeVariantMode(req.variantMode) == "exact_key"
            if itemID or exactDBKey then
                local price
                if scope == "neutral" then
                    price = GetNeutralTrackedPrice(req, itemID, neutralByKey, neutralByItemID)
                else
                    price = GetMainTrackedPrice(realmDB, req, itemID, now, isPeriodic)
                end
                if price and EvaluateMatchedRequest(realmDB, id, req, price, scope, sourceName, ResolveItemName(itemID), now) then
                    alerted = alerted + 1
                end
            end
        end
    end
    return alerted
end


function MarketSync.GetImportableListNames()
    local lists = {}
    -- 1. Native MarketSync Favorites
    if MarketSync.Favorites and MarketSync.Favorites.GetLists then
        local favLists = MarketSync.Favorites.GetLists()
        for _, name in ipairs(favLists) do
            table.insert(lists, { name = name, source = "favorites", label = name .. " (Favorites)" })
        end
    end
    -- 2. Auctionator shopping lists if available
    if Auctionator and Auctionator.Shopping and Auctionator.Shopping.ListManager then
        local aNames = MarketSync.GetAuctionatorShoppingListNames and MarketSync.GetAuctionatorShoppingListNames() or {}
        for _, name in ipairs(aNames) do
            table.insert(lists, { name = name, source = "auctionator", label = name .. " (Auctionator)" })
        end
    end
    return lists
end

function MarketSync.ImportNotificationRequestsFromFavorites(listNames, options)
    options = options or {}
    local realmDB = MarketSync.GetRealmDB()
    if not realmDB or not MarketSyncDB or not MarketSyncDB.Favorites then
        return 0, "Favorites database not found"
    end

    local targetLists = {}
    if type(listNames) == "string" then
        if listNames == "__ALL__" then
            for name in pairs(MarketSyncDB.Favorites) do
                table.insert(targetLists, name)
            end
        else
            table.insert(targetLists, listNames)
        end
    elseif type(listNames) == "table" and #listNames > 0 then
        targetLists = listNames
    else
        for name in pairs(MarketSyncDB.Favorites) do
            table.insert(targetLists, name)
        end
    end

    local itemsToImport = {}
    for _, lName in ipairs(targetLists) do
        local list = MarketSyncDB.Favorites[lName]
        if list then
            for _, itemID in ipairs(list) do
                table.insert(itemsToImport, { itemID = itemID, listName = lName })
            end
        end
    end

    if #itemsToImport == 0 then
        return 0, "No items found in selected list"
    end

    local imported = 0
    local skipped = 0
    local thresholdPct = tonumber(options.thresholdPct) -- e.g. 90 for 10% below market
    local fallbackCopper = math.max(0, math.floor(tonumber(options.thresholdCopper) or 0))
    local scope = options.scope or "all"
    local cooldown = tonumber(options.cooldownSec) or 300

    for _, entry in ipairs(itemsToImport) do
        local itemID = entry.itemID
        local name, link = MarketSync.GetItemInfo(itemID)
        local displayName = name or ("Item " .. tostring(itemID))
        
        local marketPrice = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(itemID)
        local resolvedThreshold = fallbackCopper

        if thresholdPct and marketPrice and marketPrice > 0 then
            resolvedThreshold = math.floor(marketPrice * (thresholdPct / 100))
        elseif (not resolvedThreshold or resolvedThreshold <= 0) and marketPrice and marketPrice > 0 then
            resolvedThreshold = math.floor(marketPrice * 0.9)
        end

        local reqID = BuildRequestID("itemID", itemID, scope)
        local req = MarketSync.UpsertNotificationRequest({
            id = reqID,
            matchType = "itemID",
            matchValue = itemID,
            displayName = displayName,
            thresholdCopper = resolvedThreshold,
            scope = scope,
            variantMode = "any_suffix",
            cooldownSec = cooldown,
            enabled = (options.enabledDefault ~= nil) and options.enabledDefault or (resolvedThreshold > 0),
            importSource = entry.listName,
        })
        if req then
            imported = imported + 1
        else
            skipped = skipped + 1
        end
    end

    return imported
end

function MarketSync.GetAuctionatorShoppingListNames()
    if MarketSync.Provider and not MarketSync.Provider.CanExportShoppingList() then
        return {}
    end
    if not Auctionator or not Auctionator.Shopping or not Auctionator.Shopping.ListManager then
        return {}
    end
    local names = {}
    for i = 1, Auctionator.Shopping.ListManager:GetCount() do
        local list = Auctionator.Shopping.ListManager:GetByIndex(i)
        if list and list.GetName then
            table.insert(names, list:GetName())
        end
    end
    table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return names
end

local function SplitImportedSearchEntries(rawEntry)
    if type(rawEntry) ~= "string" then
        return {}
    end

    local out = {}
    local normalized = rawEntry:gsub("\r", "")
    local function TrimEntry(text)
        return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    for line in normalized:gmatch("[^\n]+") do
        local cleaned = TrimEntry(line)
        if cleaned ~= "" then
            out[#out + 1] = cleaned
        end
    end

    if #out == 0 then
        local cleaned = TrimEntry(normalized)
        if cleaned ~= "" then
            out[1] = cleaned
        end
    end

    return out
end

function MarketSync.ImportNotificationRequestsFromAuctionator(listNames, options)
    options = options or {}
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return 0, "Auctionator API unavailable"
    end

    local names = listNames
    if not names or #names == 0 then
        names = MarketSync.GetAuctionatorShoppingListNames()
    end
    if not names or #names == 0 then
        return 0, "No Auctionator lists found"
    end

    local imported = 0
    local skipped = 0
    local fallbackThreshold = math.max(0, math.floor(tonumber(options.thresholdCopper) or 0))
    local useListMaxPrice = (options.useListMaxPrice ~= false)
    local enabledDefault = options.enabledDefault

    for _, listName in ipairs(names) do
        local okItems, itemsOrErr = pcall(Auctionator.API.v1.GetShoppingListItems, ADDON_CALLER_ID, listName)
        if okItems and type(itemsOrErr) == "table" then
            for _, raw in ipairs(itemsOrErr) do
                for _, entry in ipairs(SplitImportedSearchEntries(raw)) do
                    local okTerm, term = pcall(Auctionator.API.v1.ConvertFromSearchString, ADDON_CALLER_ID, entry)
                    if okTerm and type(term) == "table" and type(term.searchString) == "string" and term.searchString ~= "" then
                        local displayName = tostring(term.searchString):gsub("^\"(.*)\"$", "%1")
                        local resolvedItemID = MarketSync.ResolveItemID(displayName)

                        local matchType, matchValue
                        if resolvedItemID then
                            matchType = "itemID"
                            matchValue = resolvedItemID
                        else
                            matchType = "name"
                            matchValue = displayName:lower()
                        end

                        local resolvedThreshold = fallbackThreshold
                        local maxPrice = tonumber(term.maxPrice)
                        if useListMaxPrice and maxPrice and maxPrice > 0 then
                            resolvedThreshold = math.floor(maxPrice)
                        end

                        local reqID = BuildRequestID(matchType, matchValue, options.scope or "all")
                        local req = MarketSync.UpsertNotificationRequest({
                            id = reqID,
                            matchType = matchType,
                            matchValue = matchValue,
                            displayName = displayName,
                            thresholdCopper = resolvedThreshold,
                            scope = options.scope or "all",
                            variantMode = "any_suffix",
                            cooldownSec = tonumber(options.cooldownSec) or nil,
                            enabled = (enabledDefault ~= nil) and enabledDefault or (resolvedThreshold > 0),
                            quantityHint = term.quantity,
                            importSource = listName,
                        })
                        if req then
                            imported = imported + 1
                        else
                            skipped = skipped + 1
                        end
                    else
                        skipped = skipped + 1
                    end
                end
            end
        else
            skipped = skipped + 1
        end
    end

    if skipped > 0 then
        return imported, string.format("Skipped %d invalid entry(s).", skipped)
    end
    return imported
end
