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
        GetEntryByKey(realmDB.GuildData or realmDB.PersonalData, dbKey), now)) then
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

-- Build a read-only draft for the bulk alert editor. Nothing is saved until
-- the user explicitly confirms the preview window.
function MarketSync.GetNotificationImportCandidates(listName, listSource, discountPct)
    local candidates, seen = {}, {}
    local pct = math.max(0, math.min(100, tonumber(discountPct) or 10))
    local specs = {}
    if not listName or listName == "__ALL__" then
        specs = MarketSync.GetImportableListNames()
    else
        specs[1] = { name = listName, source = listSource or "favorites" }
    end

    local function AddCandidate(itemID, displayName, sourceName, sourceType, maxPrice, quantityHint, suffix)
        itemID = tonumber(itemID)
        local suffixNum = (tonumber(suffix) and tonumber(suffix) > 0) and math.floor(tonumber(suffix)) or 0
        local matchType = (itemID and suffixNum > 0) and "dbKey" or (itemID and "itemID" or "name")
        local matchValue = (itemID and suffixNum > 0) and string.format("p:%d:%d", itemID, suffixNum)
            or (itemID or tostring(displayName or ""):lower())
        local variantMode = (matchType == "dbKey") and "exact_key" or "any_suffix"
        if matchValue == "" then return end
        local identity = matchType .. ":" .. tostring(matchValue)
        if seen[identity] then return end
        seen[identity] = true

        local marketPrice = MarketSync.GetAuctionPrice
            and MarketSync.GetAuctionPrice((matchType == "dbKey" and matchValue) or itemID or displayName) or nil
        marketPrice = tonumber(marketPrice)
        if not marketPrice or marketPrice <= 0 then marketPrice = nil end
        local threshold = tonumber(maxPrice)
        if not threshold or threshold <= 0 then
            threshold = marketPrice and math.floor(marketPrice * (100 - pct) / 100) or 0
        end
        local existing
        local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        for _, request in pairs((realmDB and realmDB.NotificationRequests) or {}) do
            if request.matchType == matchType and tostring(request.matchValue) == tostring(matchValue) then
                existing = request
                break
            end
        end
        local resolvedThreshold = existing and tonumber(existing.thresholdCopper)
            or math.max(0, math.floor(threshold))
        candidates[#candidates + 1] = {
            itemID = itemID,
            matchType = matchType,
            matchValue = matchValue,
            variantMode = variantMode,
            displayName = tostring(displayName or (itemID and ("Item " .. itemID)) or matchValue),
            marketPrice = marketPrice,
            thresholdCopper = resolvedThreshold,
            scope = existing and existing.scope or "all",
            urgent = existing and existing.urgent == true or false,
            enabled = existing and existing.enabled ~= false or (not existing and resolvedThreshold > 0),
            selected = resolvedThreshold > 0,
            requestID = existing and existing.id or nil,
            listName = sourceName,
            listSource = sourceType,
            quantityHint = quantityHint,
        }
    end

    for _, spec in ipairs(specs) do
        if spec.source == "favorites" then
            local list = MarketSyncDB and MarketSyncDB.Favorites and MarketSyncDB.Favorites[spec.name]
            local metaItems = MarketSyncDB and MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[spec.name]
                and MarketSyncDB.FavoriteMeta[spec.name].items
            local qtyMap = MarketSyncDB and MarketSyncDB.FavoriteQuantities and MarketSyncDB.FavoriteQuantities[spec.name]
            for _, itemID in ipairs(list or {}) do
                local meta = metaItems and metaItems[itemID]
                local name = MarketSync.GetItemInfo and MarketSync.GetItemInfo(itemID)
                if (not name or name == "") and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
                    name = MarketSyncDB.ItemInfoCache[itemID].n
                end
                if (not name or name == "") and meta and meta.name then
                    name = meta.name
                end
                AddCandidate(itemID, name, spec.name, "favorites", meta and meta.maxPrice, qtyMap and qtyMap[itemID], meta and meta.suffix)
            end
        elseif spec.source == "auctionator" and Auctionator and Auctionator.API and Auctionator.API.v1 then
            local api = Auctionator.API.v1
            local ok, entries = pcall(api.GetShoppingListItems, ADDON_CALLER_ID, spec.name)
            if ok and type(entries) == "table" then
                for _, raw in ipairs(entries) do
                    for _, entry in ipairs(SplitImportedSearchEntries(raw)) do
                        local converted, term = pcall(api.ConvertFromSearchString, ADDON_CALLER_ID, entry)
                        if converted and type(term) == "table" and type(term.searchString) == "string" then
                            local name = term.searchString:gsub('^"(.*)"$', "%1")
                            local itemID = MarketSync.ResolveItemID and MarketSync.ResolveItemID(name)
                            AddCandidate(itemID, name, spec.name, "auctionator", term.maxPrice, term.quantity)
                        end
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.displayName:lower() < b.displayName:lower()
    end)
    return candidates
end

function MarketSync.BuildNotificationCandidatesFromDecodedList(decoded, options)
    options = options or {}
    if type(decoded) ~= "table" or type(decoded.i) ~= "table" then
        return {}
    end

    local defaultScope = options.scope
    if not defaultScope then
        if decoded.fa == "Neutral" then
            defaultScope = "neutral"
        elseif decoded.fa == "Alliance" or decoded.fa == "Horde" or decoded.fa == "CrossFaction" or decoded.fa == "Commodities" then
            defaultScope = "main"
        else
            defaultScope = "all"
        end
    end
    defaultScope = NormalizeScope(defaultScope)

    local discountPct = math.max(0, math.min(100, tonumber(options.discountPct) or 10))
    local sourceListName = options.listName or decoded.n or "Imported List"
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    local candidates, seen = {}, {}

    for _, item in ipairs(decoded.i) do
        local id = tonumber(item.id)
        if id and id > 0 then
            local suffix = (tonumber(item.s) and tonumber(item.s) > 0) and math.floor(tonumber(item.s)) or 0
            local matchType = (suffix > 0) and "dbKey" or "itemID"
            local matchValue = (suffix > 0) and string.format("p:%d:%d", id, suffix) or id
            local variantMode = (suffix > 0) and "exact_key" or "any_suffix"
            local identity = matchType .. ":" .. tostring(matchValue)
            if not seen[identity] then
                seen[identity] = true

                local resolvedName = ResolveItemName(id)
                local fallbackName = (type(item.nm) == "string" and item.nm ~= "") and item.nm or nil
                local displayName = resolvedName or fallbackName or ("Item #" .. tostring(id))

                local marketPrice = MarketSync.GetAuctionPrice
                    and MarketSync.GetAuctionPrice((suffix > 0) and matchValue or id) or nil
                marketPrice = tonumber(marketPrice)
                if not marketPrice or marketPrice <= 0 then marketPrice = nil end

                local explicitMax = tonumber(item.m)
                local thresholdCopper
                if explicitMax and explicitMax > 0 then
                    thresholdCopper = math.floor(explicitMax)
                elseif marketPrice and marketPrice > 0 then
                    thresholdCopper = math.floor(marketPrice * (100 - discountPct) / 100)
                else
                    thresholdCopper = 0
                end

                local existing
                for _, request in pairs((realmDB and realmDB.NotificationRequests) or {}) do
                    if request.matchType == matchType and tostring(request.matchValue) == tostring(matchValue) then
                        existing = request
                        break
                    end
                end

                local finalThreshold = existing and tonumber(existing.thresholdCopper) or thresholdCopper
                local enabled
                if item.a ~= nil then
                    enabled = (item.a == 1) and (finalThreshold > 0)
                else
                    enabled = existing and (existing.enabled ~= false) or (finalThreshold > 0)
                end

                candidates[#candidates + 1] = {
                    itemID = id,
                    matchType = matchType,
                    matchValue = matchValue,
                    variantMode = variantMode,
                    displayName = tostring(displayName),
                    marketPrice = marketPrice,
                    thresholdCopper = finalThreshold,
                    scope = existing and existing.scope or defaultScope,
                    urgent = existing and existing.urgent == true or false,
                    enabled = enabled,
                    selected = (item.a ~= 0) and (finalThreshold > 0),
                    requestID = existing and existing.id or nil,
                    listName = sourceListName,
                    listSource = "ms1",
                    quantityHint = tonumber(item.q) or 1,
                    alertFlag = item.a,
                }
            end
        end
    end

    return candidates
end

function MarketSync.ImportNotificationRequestsFromDecodedList(decoded, options)
    options = options or {}
    local candidates = MarketSync.BuildNotificationCandidatesFromDecodedList(decoded, options)
    local created = 0
    local skipped = 0
    local cooldown = tonumber(options.cooldownSec) or 300

    for _, c in ipairs(candidates) do
        local shouldImport = (c.alertFlag == 1)
            or (c.alertFlag == nil and not options.requireAlertFlag and c.thresholdCopper > 0)
            or (options.includeDisabledAlerts == true and c.thresholdCopper > 0)
        if shouldImport and c.thresholdCopper > 0 then
            local reqID = c.requestID or BuildRequestID(c.matchType, c.matchValue, c.scope)
            local req = MarketSync.UpsertNotificationRequest({
                id = reqID,
                matchType = c.matchType,
                matchValue = c.matchValue,
                displayName = c.displayName,
                thresholdCopper = c.thresholdCopper,
                scope = c.scope,
                variantMode = c.variantMode,
                cooldownSec = cooldown,
                urgent = c.urgent,
                enabled = (c.alertFlag ~= 0),
                quantityHint = c.quantityHint,
                importSource = c.listName,
            })
            if req then
                created = created + 1
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end

    return created, skipped
end
