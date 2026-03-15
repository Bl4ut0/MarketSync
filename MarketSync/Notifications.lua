-- =============================================================
-- MarketSync - Notifications Module
-- Threshold alerts + Auctionator shopping list import
-- =============================================================

local ADDON_CALLER_ID = "MarketSync"

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
    return name
end

local function AlertNotification(req, state, itemName, price)
    local threshold = req.thresholdCopper or 0
    local scopeText = (req.scope == "neutral") and "Neutral" or ((req.scope == "main") and "Main" or "Any")
    local msg = string.format(
        "|cFF00FF00[MarketSync Alert]|r %s dropped to %s (threshold %s, scope: %s).",
        itemName or req.displayName or req.matchValue or "Tracked item",
        MarketSync.FormatMoney(price),
        MarketSync.FormatMoney(threshold),
        scopeText
    )
    print(msg)

    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), ChatTypeInfo["RAID_WARNING"])
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
            PlaySound(soundID, "Master")
        end
    end

    -- Trigger Minimap Flash
    if MarketSync.StartMinimapFlash then
        MarketSync.StartMinimapFlash()
    end
end

function MarketSync.UpsertNotificationRequest(req)
    local realmDB = MarketSync.GetRealmDB()
    local matchType = req.matchType or "name"
    local matchValue = req.matchValue or req.displayName
    if not matchValue then return nil end

    local scope = NormalizeScope(req.scope)
    local requestID = req.id or BuildRequestID(matchType, matchValue, scope)
    local now = time()

    local existing = realmDB.NotificationRequests[requestID] or {}
    existing.id = requestID
    existing.matchType = matchType
    existing.matchValue = matchValue
    existing.displayName = req.displayName or existing.displayName or tostring(matchValue)
    existing.thresholdCopper = tonumber(req.thresholdCopper) or existing.thresholdCopper or 0
    existing.scope = scope
    existing.variantMode = NormalizeVariantMode(req.variantMode)
    -- Use 30-minute default if not specified
    existing.cooldownSec = tonumber(req.cooldownSec) or existing.cooldownSec or (realmDB.NotificationSettings and realmDB.NotificationSettings.defaultCooldownSec or 1800)
    existing.enabled = (req.enabled == nil) and (existing.enabled ~= false) or not not req.enabled
    existing.createdAt = existing.createdAt or now
    existing.quantityHint = tonumber(req.quantityHint) or existing.quantityHint
    existing.importSource = req.importSource or existing.importSource

    realmDB.NotificationRequests[requestID] = existing
    GetRequestState(realmDB, requestID)
    return existing
end

function MarketSync.DeleteNotificationRequest(requestID)
    local realmDB = MarketSync.GetRealmDB()
    realmDB.NotificationRequests[requestID] = nil
    realmDB.NotificationState[requestID] = nil
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

function MarketSync.EvaluateNotificationsForRecord(dbKey, price, eventScope, sourceName, explicitName, explicitItemID)
    local realmDB = MarketSync.GetRealmDB()
    if not realmDB or not realmDB.NotificationRequests then return 0 end
    if not price or price <= 0 then return 0 end

    -- Check global notification mode
    local globalMode = MarketSyncDB and MarketSyncDB.NotificationMode or "on_scan"
    -- If we wanted to implement a purely periodic check, we'd do it elsewhere, 
    -- but for now "on_scan" and "periodic" both trigger here, just maybe with different thresholds.
    -- The user suggested "run sounds on the regular schedule OR when new scan data comes in".
    -- "Schedule" implys a ticker. I'll add a ticker later for "periodic".

    local itemID = explicitItemID or MarketSync.ParseItemIDFromDBKey(dbKey)
    local itemName = explicitName or ResolveItemName(itemID)
    local now = time()
    local alerted = 0
    local settings = realmDB.NotificationSettings or {}
    local rearmPct = tonumber(settings.rearmBufferPct) or 5
    local rearmAfterSec = tonumber(settings.rearmAfterSec) or 1800

    for id, req in pairs(realmDB.NotificationRequests) do
        if req.enabled ~= false and ScopeAllows(req.scope, eventScope) and RequestMatches(req, dbKey, itemID, itemName) then
            local threshold = tonumber(req.thresholdCopper) or 0
            if threshold > 0 then
                local state = GetRequestState(realmDB, id)
                -- Force 30 minute minimum if settings say so, or use per-req cooldown
                local cooldown = tonumber(req.cooldownSec) or (settings.defaultCooldownSec or 1800)
                local sinceAlert = now - (state.lastAlertAt or 0)
                local rearmThreshold = math.floor(threshold * (1 + (rearmPct / 100)))

                if state.armed == false then
                    if price > rearmThreshold or sinceAlert >= rearmAfterSec then
                        state.armed = true
                    end
                end

                if state.armed ~= false and price <= threshold and sinceAlert >= cooldown then
                    state.lastAlertAt = now
                    state.lastAlertPrice = price
                    state.armed = false
                    AlertNotification(req, state, itemName, price)
                    alerted = alerted + 1
                end
            end
        end
    end

    return alerted
end

function MarketSync.GetAuctionatorShoppingListNames()
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
