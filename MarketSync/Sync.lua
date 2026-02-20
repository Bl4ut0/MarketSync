-- =============================================================
-- MarketSync - Sync Module
-- Protocol, data merging, passive sync, bulk broadcast
-- =============================================================

local PREFIX = MarketSync.PREFIX
local DATA_PREFIXES = MarketSync.DATA_PREFIXES
local Debug = MarketSync.Debug
local IsBlocked = MarketSync.IsBlocked
local TrackSync = MarketSync.TrackSync
local FormatMoney = MarketSync.FormatMoney
local GetCurrentScanDay = MarketSync.GetCurrentScanDay

-- ================================================================
-- SYNC PROTOCOL
-- ADV;realm;scanDay;itemCount;ver - "I have data for this realm"
-- PULL;realm;sinceDay             - "Send me items newer than day X"
-- ACCEPT;realm;sinceDay           - "I am taking this PULL request"
-- RES;link;price;day;qty          - Single item payload (decimal)
-- REQ;link                        - Single item request
-- BRES;id:price:qty:day,...       - Bulk payload (base-36 encoded)
--   Sent on DATA_PREFIXES (MSyncD1/D2/D3) for parallel throughput
-- ================================================================

-- ================================================================
-- BASE-36 ENCODING / DECODING
-- Compresses numeric payloads by ~30% (e.g. "50000" -> "11cg")
-- Lua's tonumber(str, 36) handles decode natively.
-- ================================================================
local B36_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function ToBase36(n)
    n = math.floor(tonumber(n) or 0)
    if n == 0 then return "0" end
    local result = ""
    local neg = n < 0
    if neg then n = -n end
    while n > 0 do
        local rem = n % 36
        result = string.sub(B36_CHARS, rem + 1, rem + 1) .. result
        n = math.floor(n / 36)
    end
    return neg and ("-" .. result) or result
end

local function FromBase36(s)
    if not s or s == "" then return 0 end
    return tonumber(s, 36) or 0
end

-- Export for Chat.lua receiver
MarketSync.FromBase36 = FromBase36

MarketSync.myRealm = nil
local myLatestScanDay = 0
local myRecentItemCount = 0
local pullInProgress = false

MarketSync.TxCount = 0
MarketSync.RxCount = 0

-- ================================================================
-- NETWORK MONITORING (Tx/Rx per second)
-- ================================================================
local lastTx, lastRx = 0, 0
C_Timer.NewTicker(1.0, function()
    local txRate = MarketSync.TxCount - lastTx
    local rxRate = MarketSync.RxCount - lastRx
    lastTx = MarketSync.TxCount
    lastRx = MarketSync.RxCount

    if MarketSync.UpdateNetworkUI then
        MarketSync.UpdateNetworkUI(txRate, rxRate)
    end
end)

-- ================================================================
-- LOCAL SCAN SNAPSHOT (Duplicating Personal Data)
-- ================================================================
function MarketSync.SnapshotPersonalScan()
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0, 0 end
    if not MarketSync.GetRealmDB().PersonalData then MarketSync.GetRealmDB().PersonalData = {} end
    
    wipe(MarketSync.GetRealmDB().PersonalData)
    
    local today = MarketSync.GetCurrentScanDay()
    local count = 0
    local todayCount = 0
    
    for dbKey, data in pairs(Auctionator.Database.db) do
        -- Only copy price and day if the item was seen TODAY and it's not a fresh guild sync.
        -- We just literally copy everything that exists in the database to build a raw offline view.
        -- If the user wants a 1:1 local offline scan, we capture dbKey => Data map.
        -- To keep memory small, we just save { m = data.m, d = lastSeen }
        if type(data) == "table" then
            local lastSeenDay = 0
            if data.h then
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d > lastSeenDay then lastSeenDay = d end
                end
            end
            if data.m and data.m > 0 then
                MarketSync.GetRealmDB().PersonalData[dbKey] = { m = data.m, d = lastSeenDay }
                count = count + 1
                if lastSeenDay == today then
                    todayCount = todayCount + 1
                end
            end
        end
    end
    
    Debug("SnapshotPersonalScan: Duplicated " .. count .. " items (" .. todayCount .. " from today) into Personal storage.")
    
    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Duplicated " .. count .. " items into Personal cache.")
    end
    
    return count, todayCount
end

-- ================================================================
-- SCAN DAY HELPERS
-- ================================================================
function MarketSync.GetMyLatestScanDay()
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0 end
    
    local today = MarketSync.GetCurrentScanDay()
    
    -- If we have a cached day and it is "today", trust the cache
    if MarketSyncDB and MarketSync.GetRealmDB().CachedScanStats and MarketSync.GetRealmDB().CachedScanStats.day == today then
        return MarketSync.GetRealmDB().CachedScanStats.day
    end
    
    local best = 0
    for dbKey, data in pairs(Auctionator.Database.db) do
        if type(data) == "table" and data.h then
            for dayStr in pairs(data.h) do
                local d = tonumber(dayStr)
                if d and d > best then best = d end
            end
        end
    end
    return best
end

function MarketSync.CountRecentItems(sinceDay)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return 0 end
    
    local today = MarketSync.GetCurrentScanDay()
    
    -- If we have cached stats for the requested day, trust the cache
    if MarketSyncDB and MarketSync.GetRealmDB().CachedScanStats and MarketSync.GetRealmDB().CachedScanStats.day == sinceDay then
        return MarketSync.GetRealmDB().CachedScanStats.count
    end
    
    local count = 0
    for dbKey, data in pairs(Auctionator.Database.db) do
        if type(data) == "table" and data.h then
            for dayStr in pairs(data.h) do
                local d = tonumber(dayStr)
                if d and d >= sinceDay then 
                    count = count + 1
                    break 
                end
            end
        end
    end
    
    -- Cache the result if we are checking "today" to save CPU on future ADVs
    if MarketSyncDB and sinceDay == today then
        MarketSync.GetRealmDB().CachedScanStats = { day = sinceDay, count = count }
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
    myRecentItemCount = MarketSync.CountRecentItems(myLatestScanDay)
    if myLatestScanDay > 0 and myRecentItemCount > 0 then
        local localVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or "0.0.0"
        local myScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().PersonalScanTime) or 0
        local payload = string.format("ADV;%s;%d;%d;%s;%s", MarketSync.myRealm, myLatestScanDay, myRecentItemCount, localVersion, tostring(myScanTime))
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ffff[ADV]|r to Guild (Day %d, %d items, TSF: %d, v%s)", myLatestScanDay, myRecentItemCount, myScanTime, localVersion))
        end
        Debug("Sent ADV: realm=" .. MarketSync.myRealm .. " day=" .. myLatestScanDay .. " items=" .. myRecentItemCount .. " tsf=" .. myScanTime .. " v=" .. localVersion)
    end
end

function MarketSync.SendPullRequest(sinceDay)
    if not IsInGuild() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("PULL;%s;%d", MarketSync.myRealm, sinceDay)
    C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cffff8800[PULL]|r to Guild (Since Day %d)", sinceDay))
    end
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
    MarketSync.TxCount = MarketSync.TxCount + 1
end

function MarketSync.SendBulkSyncResponse(chunkBuffer, dataPrefix, channel, target)
    local payload = "BRES;" .. chunkBuffer
    C_ChatInfo.SendAddonMessage(dataPrefix, payload, channel, target)
end

-- ================================================================
-- SWARM COORDINATOR (PULL Queuing & Throttled Responses)
-- ================================================================
MarketSync.PullQueue = {}

function MarketSync.SendPullAccept(sinceDay)
    if not IsInGuild() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("ACCEPT;%s;%d", MarketSync.myRealm, sinceDay)
    C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ff00[ACCEPT]|r to Guild (Claiming PULL for Day %d)", sinceDay))
    end
end

function MarketSync.RegisterPullAccept(sinceDay, senderName)
    MarketSync.PullQueue[sinceDay] = senderName
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ff00[Swarm]|r %s claimed PULL for Day %d", senderName, sinceDay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(senderName, "Sending")
    end
end

function MarketSync.SchedulePullResponse(sinceDay, requester)
    if pullInProgress then return end

    local delay = math.random() * 8.0 -- 0.0 to 8.0 seconds for large guilds
    
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cffff8800[Swarm]|r Queued PULL from %s. Waiting %.1fs for consensus...", requester, delay))
    end
    
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Waiting")
    end

    C_Timer.After(delay, function()
        -- See if someone else accepted this pull
        local claimant = MarketSync.PullQueue[sinceDay]
        if claimant then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r %s is already fulfilling PULL (Day %d). Standing down.", claimant, sinceDay))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil) -- remove our wait state
            end
            return 
        end
        
        -- Nobody else took it, we accept!
        MarketSync.SendPullAccept(sinceDay)
        MarketSync.RespondToPull(sinceDay, requester)
        
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), "Sending")
        end
    end)
end

function MarketSync.RespondToPull(sinceDay, requester)
    if pullInProgress then
        Debug("PULL response already in progress, ignoring request from " .. (requester or "unknown"))
        return
    end
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return end
    pullInProgress = true
    Debug("Responding to PULL from " .. (requester or "unknown") .. " (sinceDay=" .. sinceDay .. ")")

    -- BRES v3: Base-36 encoded, multi-prefix parallel transfer
    -- 3 data prefixes round-robin at 1 msg/sec each = 3 msg/sec sustained.
    -- Each message packs ~16 base-36 items into 248 bytes.
    -- Total throughput: ~48 items/sec. Full 2355-item sync in ~50 seconds.
    local MAX_PAYLOAD = 248  -- 255 minus "BRES;" prefix (5) minus safety margin (2)
    local numPrefixes = #DATA_PREFIXES
    
    local co = coroutine.create(function()
        local sent = 0
        local scanned = 0
        local skipped = 0
        local messagesSent = 0
        local buffer = ""
        local bufferCount = 0
        local prefixIndex = 1  -- round-robin counter
        
        -- Store current key globally so the ticker can retrieve it on crash
        _G.MarketSyncActivePullKey = "Starting"
        local yieldCounter = 0

        -- Count total eligible items first for progress tracking
        local totalEligible = 0
        for dbKey, data in pairs(Auctionator.Database.db) do
            if type(data) == "table" and data.h then
                for dayStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d >= sinceDay then
                        totalEligible = totalEligible + 1
                        break
                    end
                end
            end
        end

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Start]|r Sending %d items via %d parallel channels (base-36 encoded)", totalEligible, numPrefixes))
        end

        for dbKey, data in pairs(Auctionator.Database.db) do
            scanned = scanned + 1
            _G.MarketSyncActivePullKey = tostring(dbKey)
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
                        local price = tonumber(data.m) or 0
                        local dateStr = tostring(lastSeenDay)
                        local quantity = (data.a and data.a[dateStr]) or 0
                        -- Base-36 encode all numeric fields
                        local itemStr = ToBase36(itemID) .. ":" .. ToBase36(price) .. ":" .. ToBase36(quantity) .. ":" .. ToBase36(lastSeenDay)
                        
                        -- Flush buffer if adding this item would exceed the wire limit
                        local currentLen = string.len(buffer)
                        if currentLen > 0 and currentLen + 1 + string.len(itemStr) > MAX_PAYLOAD then
                            -- Send on the current round-robin prefix
                            local dp = DATA_PREFIXES[prefixIndex]
                            MarketSync.SendBulkSyncResponse(buffer, dp, "GUILD")
                            MarketSync.TxCount = MarketSync.TxCount + bufferCount
                            sent = sent + bufferCount
                            messagesSent = messagesSent + 1
                            buffer = ""
                            bufferCount = 0
                            yieldCounter = 0
                            
                            -- Advance round-robin
                            prefixIndex = (prefixIndex % numPrefixes) + 1
                            
                            -- Checkpoint every 100 items
                            if sent % 100 < 16 then
                                if MarketSync.LogNetworkEvent then
                                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Checkpoint]|r Sent %d / %d items (%d msgs, %d scanned)", sent, totalEligible, messagesSent, scanned))
                                end
                            end
                            
                            coroutine.yield()
                        end
                        
                        if buffer == "" then
                            buffer = itemStr
                        else
                            buffer = buffer .. "," .. itemStr
                        end
                        bufferCount = bufferCount + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
            
            -- Safety yield: prevent WoW from killing the coroutine if we scan too many
            -- items without a buffer flush (e.g. many skipped/ineligible items in a row)
            yieldCounter = yieldCounter + 1
            if yieldCounter >= 500 then
                yieldCounter = 0
                coroutine.yield()
            end
        end
        -- Flush remaining buffer
        if buffer ~= "" then
            local dp = DATA_PREFIXES[prefixIndex]
            MarketSync.SendBulkSyncResponse(buffer, dp, "GUILD")
            MarketSync.TxCount = MarketSync.TxCount + bufferCount
            sent = sent + bufferCount
            messagesSent = messagesSent + 1
        end
        Debug("PULL response complete: sent " .. sent .. " items in " .. messagesSent .. " messages")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Complete]|r Sent %d items in %d messages via %d channels. (%d scanned, %d skipped)", sent, messagesSent, numPrefixes, scanned, skipped))
        end
        if requester and IsInGuild() then
            -- Send an explicit END signal to let the receiver know we are done
            C_ChatInfo.SendAddonMessage(PREFIX, string.format("END;%d;%d", sent, messagesSent), "GUILD")
        end
        pullInProgress = false
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
    end)

    -- Multi-prefix round-robin: 3 prefixes, each gets 1 msg/sec.
    -- Ticker fires every 1/3 second (0.34s). Each tick sends on 1 prefix,
    -- so each individual prefix sends at most 1 msg/sec (safe for its bucket).
    -- Total sustained: 3 msg/sec × ~16 items/msg = ~48 items/sec.
    -- Global CPS: 3 × 248 = 744 bytes/sec (well under 2000 safe limit).
    local ticker
    ticker = C_Timer.NewTicker(0.34, function()
        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            pullInProgress = false
            return
        end
        local ok, err = coroutine.resume(co)
        if not ok then
            local crashKey = _G.MarketSyncActivePullKey or "Unknown"
            Debug("PULL response error at key [" .. crashKey .. "]: " .. tostring(err))
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Swarm Sync halted entirely. CRASH at dbKey: %s. Err: %s", crashKey, tostring(err)))
            end
            if IsInGuild() and requester then
                C_ChatInfo.SendAddonMessage(PREFIX, string.format("ERR;%s;%s", requester, crashKey), "GUILD")
            end
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
            if not MarketSync.GetRealmDB().ItemMetadata then MarketSync.GetRealmDB().ItemMetadata = {} end
            
            -- Per-day attribution: each scan day credits the actual sender
            local meta = MarketSync.GetRealmDB().ItemMetadata[key]
            if not meta then
                meta = { days = {}, lastSource = sender, lastTime = time() }
                MarketSync.GetRealmDB().ItemMetadata[key] = meta
            end
            if not meta.days then meta.days = {} end
            
            -- Only update this day's source if we don't already have it, or if the sender updated the price
            local dayStr = tostring(incomingScanDay)
            if not meta.days[dayStr] then
                meta.days[dayStr] = { source = sender, time = time() }
            end
            -- Always track the most recent contributor
            meta.lastSource = sender
            meta.lastTime = time()

            -- Route to guild incoming buffer (won't disrupt live browsing)
            if MarketSync.AddToGuildIncoming then
                MarketSync.AddToGuildIncoming(key)
            end
        end

        -- Log to History
        if not MarketSync.GetRealmDB().HistoryLog then MarketSync.GetRealmDB().HistoryLog = {} end
        table.insert(MarketSync.GetRealmDB().HistoryLog, 1, { link = itemLink, price = price, sender = sender or "Self", time = time() })
        if #MarketSync.GetRealmDB().HistoryLog > 100 then table.remove(MarketSync.GetRealmDB().HistoryLog) end
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
                        local itemLink
                        local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
                        
                        if classID then
                             _, itemLink = C_Item.GetItemInfo(itemID)
                        end
                        
                        if not itemLink then 
                             itemLink = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0"
                        end
                        
                        if itemLink then
                            table.insert(broadcastList, {link = itemLink, price = price, day = lastSeenDay, quantity = quantity})
                            count = count + 1
                        end
                    end
                end
            end
        end

        if #broadcastList > 0 then
            print(string.format("|cFF00FF00[MarketSync]|r Found %d items. Broadcasting safely (this runs in the background)...", #broadcastList))
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending") end
        else
            print("|cFFFF0000[MarketSync]|r No recent validation items found to broadcast.")
        end

        for i, item in ipairs(broadcastList) do
            if item.link then
                MarketSync.SendSyncResponse(item.link, item.price, item.day, item.quantity, "GUILD")
            end
            if i % 5 == 0 then coroutine.yield() end
        end
        print("|cFF00FF00[MarketSync]|r Bulk sync broadcast completed.")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Bulk sync broadcast completed. Sent %d items.", #broadcastList))
        end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
    end)

    local ticker = C_Timer.NewTicker(0.2, function()
        if coroutine.status(co) == "dead" then return end
        local success, err = coroutine.resume(co)
        if not success then print("|cFFFF0000[MarketSync] Sync Error:|r", err) end
    end)
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


