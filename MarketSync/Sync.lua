-- =============================================================
-- MarketSync - Sync Module
-- Protocol, data merging, passive sync, bulk broadcast
-- =============================================================

local PREFIX = MarketSync.PREFIX
local Debug = MarketSync.Debug
local IsBlocked = MarketSync.IsBlocked
local TrackSync = MarketSync.TrackSync
local FormatMoney = MarketSync.FormatMoney
local GetCurrentScanDay = MarketSync.GetCurrentScanDay

-- ================================================================
-- SYNC PROTOCOL
-- ADV;realm;scanDay;itemCount   - "I have data for this realm"
-- PULL;realm;sinceDay           - "Send me items newer than day X"
-- RES;link;price;day;qty        - Data payload
-- REQ;link                      - Single item request
-- ================================================================

MarketSync.myRealm = nil
local myLatestScanDay = 0
local myRecentItemCount = 0
local pullInProgress = false

-- ================================================================
-- SCAN DAY HELPERS
-- ================================================================
function MarketSync.GetMyLatestScanDay()
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0 end
    local best = 0
    local checked = 0
    for dbKey, data in pairs(Auctionator.Database.db) do
        if type(data) == "table" and data.h then
            for dayStr in pairs(data.h) do
                local d = tonumber(dayStr)
                if d and d > best then best = d end
            end
        end
        checked = checked + 1
        if checked > 200 then break end
    end
    return best
end

local function CountRecentItems(sinceDay)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0 end
    -- Sample up to 500 items and extrapolate to avoid freezing on large DBs
    local count = 0
    local checked = 0
    local total = 0
    for dbKey, data in pairs(Auctionator.Database.db) do
        total = total + 1
        if checked < 500 then
            if type(data) == "table" and data.h then
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d >= sinceDay then count = count + 1; break end
                end
            end
            checked = checked + 1
        end
    end
    -- Extrapolate from sample if we didn't check everything
    if checked > 0 and total > checked then
        count = math.floor(count * (total / checked))
    end
    return count
end

-- ================================================================
-- SEND FUNCTIONS
-- ================================================================
function MarketSync.SendAdvertisement()
    if not IsInGuild() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    myLatestScanDay = MarketSync.GetMyLatestScanDay()
    myRecentItemCount = CountRecentItems(myLatestScanDay)
    if myLatestScanDay > 0 and myRecentItemCount > 0 then
        local payload = string.format("ADV;%s;%d;%d", MarketSync.myRealm, myLatestScanDay, myRecentItemCount)
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
        Debug("Sent ADV: realm=" .. MarketSync.myRealm .. " day=" .. myLatestScanDay .. " items=" .. myRecentItemCount)
    end
end

function MarketSync.SendPullRequest(sinceDay)
    if not IsInGuild() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("PULL;%s;%d", MarketSync.myRealm, sinceDay)
    C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    Debug("Sent PULL: realm=" .. MarketSync.myRealm .. " sinceDay=" .. sinceDay)
end

function MarketSync.SendSyncRequest(itemLink)
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, "REQ;" .. itemLink, "GUILD")
    end
end

function MarketSync.SendSyncResponse(itemLink, price, day, quantity, channel, target)
    quantity = quantity or 0
    local payload = string.format("RES;%s;%d;%d;%d", itemLink, price, day, quantity)
    C_ChatInfo.SendAddonMessage(PREFIX, payload, channel, target)
end

-- ================================================================
-- RESPOND TO PULL (throttled coroutine)
-- ================================================================
function MarketSync.RespondToPull(sinceDay, requester)
    if pullInProgress then
        Debug("PULL response already in progress, ignoring request from " .. (requester or "unknown"))
        return
    end
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return end
    pullInProgress = true
    Debug("Responding to PULL from " .. (requester or "unknown") .. " (sinceDay=" .. sinceDay .. ")")

    local co = coroutine.create(function()
        local sent = 0
        for dbKey, data in pairs(Auctionator.Database.db) do
            if type(data) == "table" and data.h then
                local lastSeenDay = -1
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d > lastSeenDay then lastSeenDay = d end
                end
                if lastSeenDay >= sinceDay then
                    local itemID = nil
                    if type(dbKey) == "string" then
                        if dbKey:match("^%d+$") then itemID = tonumber(dbKey)
                        elseif dbKey:match("^g:(%d+)") then itemID = tonumber(dbKey:match("^g:(%d+)"))
                        elseif dbKey:match("^p:(%d+)") then itemID = tonumber(dbKey:match("^p:(%d+)")) end
                    end
                    if itemID then
                        local link = select(2, C_Item.GetItemInfo(itemID))
                        if not link then link = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0" end
                        local price = data.m
                        local dateStr = tostring(lastSeenDay)
                        local quantity = (data.a and data.a[dateStr]) or 0
                        MarketSync.SendSyncResponse(link, price, lastSeenDay, quantity, "GUILD")
                        sent = sent + 1
                        if sent % 10 == 0 then coroutine.yield() end
                    end
                end
            end
        end
        Debug("PULL response complete: sent " .. sent .. " items")
        pullInProgress = false
    end)

    local ticker
    ticker = C_Timer.NewTicker(0.05, function()
        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            pullInProgress = false
            return
        end
        local ok, err = coroutine.resume(co)
        if not ok then
            Debug("PULL response error: " .. tostring(err))
            ticker:Cancel()
            pullInProgress = false
        end
    end)
end

-- ================================================================
-- UPDATE LOCAL DATABASE (Smart Merge)
-- ================================================================
function MarketSync.UpdateLocalDB(itemLink, price, day, quantity, sender)
    if sender and IsBlocked(sender) then return end

    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
        if not dbKeys or #dbKeys == 0 then return end
        local key = dbKeys[1]

        local currentPrice = Auctionator.Database:GetPrice(key)
        local currentAge = Auctionator.Database:GetPriceAge(key)

        local currentScanDay = GetCurrentScanDay()
        local incomingScanDay = day

        -- DIRECT INSERTION to ensure persistence
        local priceData = Auctionator.Database.db[key]
        if not priceData then
            priceData = { l={}, h={}, m=0, a={} }
            Auctionator.Database.db[key] = priceData
            Debug("Creating new DB entry for " .. key)
        end

        if not priceData.a then priceData.a = {} end

        local scanDayStr = tostring(incomingScanDay)
        local currentHigh = priceData.h[scanDayStr]
        local currentLow = priceData.l[scanDayStr]

        -- 1. SMART MERGE HISTORY
        local historyUpdated = false

        if currentHigh == nil or price > currentHigh then
            priceData.h[scanDayStr] = price
            currentHigh = price
            historyUpdated = true
        end

        if price < currentHigh and (currentLow == nil or price < currentLow) then
            priceData.l[scanDayStr] = price
            historyUpdated = true
        end

        -- Merge Quantity
        if quantity and quantity > 0 then
            local currentQty = priceData.a[scanDayStr]
            if not currentQty or quantity > currentQty then
                priceData.a[scanDayStr] = quantity
                historyUpdated = true
            end
        end

        -- 2. UPDATE LATEST PRICE ('m')
        local maxDay = 0
        for d, _ in pairs(priceData.h) do
            local dayNum = tonumber(d)
            if dayNum and dayNum > maxDay then maxDay = dayNum end
        end

        if incomingScanDay >= maxDay or priceData.m == 0 then
            priceData.m = price
            Debug("Updated Latest Price (m) for " .. itemLink .. " to " .. FormatMoney(price))
        elseif historyUpdated then
            Debug("Merged Historical Data for " .. itemLink .. " (Day " .. incomingScanDay .. ")")
        end

        if sender and (historyUpdated or incomingScanDay >= maxDay) then
            TrackSync(sender, 1)
            if not MarketSyncDB.ItemMetadata then MarketSyncDB.ItemMetadata = {} end
            MarketSyncDB.ItemMetadata[key] = { source = sender, time = time() }

            -- Route to guild incoming buffer (won't disrupt live browsing)
            if MarketSync.AddToGuildIncoming then
                MarketSync.AddToGuildIncoming(key)
            end
        end

        -- Log to History
        if not MarketSyncDB.HistoryLog then MarketSyncDB.HistoryLog = {} end
        table.insert(MarketSyncDB.HistoryLog, 1, { link = itemLink, price = price, sender = sender or "Self", time = time() })
        if #MarketSyncDB.HistoryLog > 100 then table.remove(MarketSyncDB.HistoryLog) end
    end)
end

-- ================================================================
-- PASSIVE SYNC (Advertisement-based)
-- ================================================================
local passiveTicker

function MarketSync.StartPassiveSync()
    if passiveTicker then passiveTicker:Cancel() end

    -- Advertise availability after a short delay on login
    C_Timer.After(15, function()
        if MarketSyncDB and MarketSyncDB.PassiveSync then
            MarketSync.SendAdvertisement()
        end
    end)

    -- Re-advertise every 5 minutes
    passiveTicker = C_Timer.NewTicker(300, function()
        if not MarketSyncDB or not MarketSyncDB.PassiveSync then return end
        if IsInInstance() then return end
        MarketSync.SendAdvertisement()
    end)
end

-- ================================================================
-- BULK BROADCAST (Manual Sync)
-- ================================================================
function MarketSync.BroadcastRecentData()
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return
    end

    print("|cFF00FF00[MarketSync]|r Starting bulk sync scan (this may take a moment)...")

    local co = coroutine.create(function()
        local count = 0
        local broadcastList = {}

        local currentScanDay = GetCurrentScanDay()
        if currentScanDay == 0 then
            print("|cFFFF0000[MarketSync]|r Error: Could not determine scan day!")
            return
        end

        local RECENT_THRESHOLD = 5
        local itemsChecked = 0

        for dbKey, data in pairs(Auctionator.Database.db) do
            itemsChecked = itemsChecked + 1
            if itemsChecked % 500 == 0 then coroutine.yield() end

            if type(data) == "table" and data.h then
                local lastSeenDay = -1
                for dayStr, _ in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d > lastSeenDay then lastSeenDay = d end
                end

                if lastSeenDay >= (currentScanDay - RECENT_THRESHOLD) then
                    local price = data.m
                    local dateStr = tostring(lastSeenDay)
                    local quantity = 0
                    if data.a and data.a[dateStr] then quantity = data.a[dateStr] end

                    local itemID = nil
                    if type(dbKey) == "string" then
                        if dbKey:match("^%d+$") then itemID = tonumber(dbKey)
                        elseif dbKey:match("^g:(%d+)") then itemID = tonumber(dbKey:match("^g:(%d+)"))
                        elseif dbKey:match("^p:(%d+)") then itemID = tonumber(dbKey:match("^p:(%d+)")) end
                    end

                    if itemID then
                        local link = select(2, C_Item.GetItemInfo(itemID))
                        if not link then link = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0" end
                        if link then
                            table.insert(broadcastList, {link = link, price = price, day = lastSeenDay, quantity = quantity})
                            count = count + 1
                        end
                    end
                end
            end
        end

        print(string.format("|cFF00FF00[MarketSync]|r Found %d items scanned in the last %d days. Broadcasting...", count, RECENT_THRESHOLD))

        for i, item in ipairs(broadcastList) do
            MarketSync.SendSyncResponse(item.link, item.price, item.day, item.quantity, "GUILD")
            if i % 10 == 0 then coroutine.yield() end
        end
        print("|cFF00FF00[MarketSync]|r Sync complete.")
    end)

    local ticker = C_Timer.NewTicker(0.01, function()
        if coroutine.status(co) == "dead" then return end
        local success, err = coroutine.resume(co)
        if not success then print("Sync Error:", err) end
    end, 100000)
end

-- ================================================================
-- SEARCH (CLI)
-- ================================================================
function MarketSync.SearchLocalDB(query)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return
    end

    query = query:lower()
    local found = 0
    print(string.format("|cFF00FF00[MarketSync]|r Search results for '%s':", query))

    for dbKey, data in pairs(Auctionator.Database.db) do
        local itemID = nil
        if type(dbKey) == "string" then
            if dbKey:match("^%d+$") then itemID = tonumber(dbKey)
            elseif dbKey:match("^g:(%d+)") then itemID = tonumber(dbKey:match("^g:(%d+)"))
            elseif dbKey:match("^p:(%d+)") then itemID = tonumber(dbKey:match("^p:(%d+)")) end
        end

        if itemID then
            local name, link = C_Item.GetItemInfo(itemID)
            if name and name:lower():find(query) then
                local price = Auctionator.Database:GetPrice(dbKey)
                local age = Auctionator.Database:GetPriceAge(dbKey)
                if price then
                    print(string.format("  %s: %s (%s)", link or name, FormatMoney(price), MarketSync.FormatAge(age)))
                    found = found + 1
                    if found >= 20 then
                        print("  ... and more.")
                        break
                    end
                end
            end
        end
    end
    if found == 0 then print("  No results found.") end
end


