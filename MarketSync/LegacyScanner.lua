-- Native scanner adapter for Classic Era, Season of Discovery, and TBC.
-- The modern scanner owns the same store and UI; this file only replaces its
-- auction-query transport when the legacy Auction House API is present.
local S = MarketSync and MarketSync.Scanner
if not S then return end
if C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery) == "function" then return end
if type(QueryAuctionItems) ~= "function" then return end

S.IsLegacyAH = true
local legacy = { mode = nil, page = 0, waiting = false, data = nil, keys = nil, requestID = 0 }
local oldCancel = S.Cancel
local Suffix

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) else fn() end
end

local function Notify()
    if S.Notify then S.Notify() end
end

local function Emit(event, reason)
    if not S.ObservationScanID or not (MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1) then return end
    local now = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
    MarketSync.ObservationAPI.v1.Emit({ event = event, scanId = S.ObservationScanID,
        source = "local", scope = S.ScanScope or "main", scanTime = S.ScanTime or now, reason = reason })
    if event == "finish" or event == "cancel" then S.ObservationScanID = nil end
end

local function Start(label, mode)
    S.Generation = (S.Generation or 0) + 1
    S.Active = true
    S.Pending = nil
    S.Queue = {}
    if mode ~= "search" and mode ~= "purchase" then
        S.RecentResults = {}
        S.ResultsRevision = (S.ResultsRevision or 0) + 1
    end
    S.Progress = { current = 0, total = 0 }
    S.PurchaseReady = nil
    S.Status = label
    S.ScanTime = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
    S.ScanScope = (MarketSync.IsNeutralAHOpen == true
        or (MarketSync.IsNeutralAHSession and MarketSync.IsNeutralAHSession())) and "neutral" or "main"
    legacy.mode, legacy.page, legacy.waiting = mode, 0, false
    legacy.requestID = legacy.requestID + 1
    legacy.data, legacy.keys = {}, {}
    if mode == "search" then
        S.LiveSearchResults = {}
        S.LiveSearchRevision = (S.LiveSearchRevision or 0) + 1
    end
    if mode ~= "search" and mode ~= "purchase" and MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1
        and MarketSync.ObservationAPI.v1.HasListeners() then
        S.ObservationScanID = MarketSync.ObservationAPI.v1.NewScanID("local")
        Emit("start")
    end
    Notify()
end

local function Finish()
    local mode = legacy.mode
    local scope = S.ScanScope
    if mode == "search" then
        table.sort(S.LiveSearchResults, function(a, b)
            if a.unitPrice ~= b.unitPrice then return a.unitPrice < b.unitPrice end
            if a.itemID ~= b.itemID then return a.itemID < b.itemID end
            if a.itemSuffix ~= b.itemSuffix then return a.itemSuffix > b.itemSuffix end
            return a.stackSize > b.stackSize
        end)
        S.LiveSearchRevision = (S.LiveSearchRevision or 0) + 1
        Emit("finish")
        S.Active, S.Pending, S.ScanTime, S.ScanScope = false, nil, nil, nil
        legacy.mode, legacy.waiting, legacy.data, legacy.keys = nil, false, nil, nil
        legacy.requestID = legacy.requestID + 1
        S.Status = string.format("Search Complete (%d price/stack groups)", #S.LiveSearchResults)
        Notify()
        return
    end
    if mode == "full" and S.ScanScope == "neutral" and MarketSync.CompleteNeutralFullScan then
        MarketSync.CompleteNeutralFullScan()
    end
    Emit("finish")
    S.Active, S.Pending, S.ScanTime, S.ScanScope = false, nil, nil, nil
    legacy.mode, legacy.waiting, legacy.data, legacy.keys = nil, false, nil, nil
    legacy.requestID = legacy.requestID + 1
    S.Status = mode == "full" and "Full Scan Complete" or "Scan Complete"
    if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    if scope ~= "neutral" and MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
        After(2, function() MarketSync.SendAdvertisement() end)
    end
    Notify()
end

local function ReadSearchRow(index)
    local name, texture, count, quality, _, level, _, _, _, buyout,
        _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", index)
    local link = GetAuctionItemLink and GetAuctionItemLink("list", index) or nil
    itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    count, buyout = tonumber(count), tonumber(buyout)
    if not itemID or not count or count < 1 or not buyout or buyout < 1 then return end
    local suffix = Suffix(link)
    -- Group only identical variants, stack sizes and exact buyout amounts.
    local identity = table.concat({itemID, suffix, count, buyout}, ":")
    local row = legacy.data[identity]
    if row then
        row.auctions = row.auctions + 1
        row.available = row.available + count
    else
        row = { itemID = itemID, itemSuffix = suffix, link = link, name = name,
            icon = texture, quality = quality, level = level, stackSize = count,
            buyout = buyout, unitPrice = math.ceil(buyout / count),
            auctions = 1, available = count, page = legacy.page, query = legacy.query }
        legacy.data[identity] = row
        S.LiveSearchResults[#S.LiveSearchResults + 1] = row
    end
end

function S.Cancel(reason)
    if legacy.mode == "full" and S.ScanScope == "neutral" and MarketSync.FailNeutralFullScan then
        MarketSync.FailNeutralFullScan()
    end
    legacy.mode, legacy.waiting, legacy.data, legacy.keys = nil, false, nil, nil
    legacy.requestID = legacy.requestID + 1
    Emit("cancel", reason)
    oldCancel(reason)
    S.PurchaseReady = nil
    S.ScanScope = nil
end

function S.IsAvailable()
    local open = MarketSync.IsAuctionHouseOpen == true
        or (_G.AuctionFrame and _G.AuctionFrame:IsShown())
    return open and type(QueryAuctionItems) == "function"
        and type(GetAuctionItemInfo) == "function"
        and type(GetNumAuctionItems) == "function"
end

local function CanQuery(getAll)
    if type(CanSendAuctionQuery) ~= "function" then return true end
    local ok, regular, full = pcall(CanSendAuctionQuery)
    return ok and ((getAll and full) or (not getAll and regular)) == true
end

local function Query(name, page, getAll)
    local generation = S.Generation
    local attempts = 0
    local function Try()
        if not S.Active or S.Generation ~= generation then return end
        if not CanQuery(getAll) then
            attempts = attempts + 1
            if attempts < 40 then
                After(0.25, Try)
            else
                S.Cancel("Auction House query throttled")
            end
            return
        end
        legacy.waiting = true
        legacy.requestID = legacy.requestID + 1
        local requestID = legacy.requestID
        local ok = pcall(QueryAuctionItems, name or "", nil, nil, page or 0,
            nil, nil, getAll == true, false, nil)
        if not ok then
            S.Cancel("Auction House query failed")
            return
        end
        After(15, function()
            if S.Active and S.Generation == generation and legacy.waiting
                and legacy.requestID == requestID then
                S.Cancel("Auction House response timed out")
            end
        end)
    end
    Try()
end

Suffix = function(link)
    if type(link) ~= "string" then return 0 end
    local itemString = link:match("|H(item:[^|]+)|h") or link:match("(item:%d+[^%s|]*)")
    if not itemString then return 0 end
    local fields = {}
    -- Empty enchant/gem fields are significant: skipping them shifts suffixID.
    for field in (itemString .. ":"):gmatch("(.-):") do fields[#fields + 1] = field end
    return tonumber(fields[8]) or 0
end

local function ReadRow(index, targetID, targetSuffix)
    local name, texture, count, quality, _, level, _, _, _, buyout,
        _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", index)
    local link = GetAuctionItemLink and GetAuctionItemLink("list", index) or nil
    itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    count, buyout = tonumber(count), tonumber(buyout)
    if not itemID or (targetID and itemID ~= targetID) or not count or count <= 0
        or not buyout or buyout <= 0 then return end
    local suffix = Suffix(link)
    if targetSuffix and targetSuffix ~= 0 and suffix ~= targetSuffix then return end
    local key = suffix ~= 0 and string.format("p:%d:%d", itemID, suffix) or tostring(itemID)
    local price = math.floor(buyout / count)
    if price <= 0 then return end
    local row = legacy.data[key]
    if not row then
        row = { itemKey = { itemID = itemID, itemSuffix = suffix, itemLevel = level or 0,
            name = name, icon = texture, quality = quality, itemLink = link },
            unitPrice = price, available = count }
        legacy.data[key] = row
        legacy.keys[#legacy.keys + 1] = key
    else
        row.available = row.available + count
        if price < row.unitPrice then
            row.unitPrice = price
            row.itemKey.itemLink = link or row.itemKey.itemLink
        end
    end
end

local function SaveRows(onDone)
    local generation, index = S.Generation, 0
    local total = #legacy.keys
    local function Batch()
        if not S.Active or S.Generation ~= generation then return end
        local stop = math.min(total, index + 150)
        for i = index + 1, stop do
            local row = legacy.data[legacy.keys[i]]
            if row then MarketSync.RecordScanObservation(row.itemKey, row.unitPrice,
                row.available, false, legacy.mode == "full", true) end
        end
        index = stop
        S.Status = string.format("Saving scan results (%d / %d)...", index, total)
        Notify()
        if index >= total then onDone() else After(0.01, Batch) end
    end
    Batch()
end

local function NextTarget()
    if not S.Active then return end
    if #S.Queue == 0 then Finish() return end
    S.Pending = table.remove(S.Queue, 1)
    S.Progress.current = S.Progress.total - #S.Queue
    local key = S.Pending
    local cached = MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[key.itemID]
    local name = key.name or (cached and cached.n)
    if not name and MarketSync.GetItemInfo then name = MarketSync.GetItemInfo(key.itemID) end
    if not name and GetItemInfo then name = GetItemInfo(key.itemID) end
    if not name then
        S.Status = "Item name unavailable for #" .. tostring(key.itemID)
        Notify()
        After(0.01, NextTarget)
        return
    end
    key.name = name
    legacy.page, legacy.data, legacy.keys = 0, {}, {}
    S.Status = string.format("Scanning %d / %d: %s", S.Progress.current, S.Progress.total, name)
    Notify()
    Query(name, 0, false)
end

function S.StartScan(itemsOrKeys, label)
    if S.Active then S.Cancel("replaced by new scan") end
    if S.IsDisabledByAuctionator and S.IsDisabledByAuctionator() then
        S.Status = "MarketSync scanning disabled while Auctionator scans"
        Notify()
        return false
    end
    if not S.IsAvailable() then
        S.Status = "Auctioneer must be open to scan"
        Notify()
        return false
    end
    Start(label or "Starting list scan...", "target")
    local seen = {}
    for _, item in ipairs(itemsOrKeys or {}) do
        local key = S.ToItemKey(item)
        local identity = key and string.format("%d:%d", key.itemID, key.itemSuffix or 0)
        if key and not seen[identity] then
            if type(item) == "table" then key.name = item.name end
            seen[identity] = true
            S.Queue[#S.Queue + 1] = key
        end
    end
    S.Progress.total = #S.Queue
    if #S.Queue == 0 then S.Cancel("No items to scan") return false end
    NextTarget()
    return true
end

function S.StartFullScan()
    if S.Active then S.Cancel("replaced by new scan") end
    if S.IsDisabledByAuctionator and S.IsDisabledByAuctionator() then
        S.Status = "MarketSync scanning disabled while Auctionator scans"
        Notify()
        return false
    end
    if not S.IsAvailable() then
        S.Status = "Auctioneer must be open to scan"
        Notify()
        return false
    end
    local cooldown = S.GetFullScanCooldownRemaining and S.GetFullScanCooldownRemaining() or 0
    if cooldown > 0 or not CanQuery(true) then
        S.Status = "Full scan on Auction House cooldown"
        Notify()
        return false
    end
    Start("Requesting full legacy AH snapshot...", "full")
    if S.ScanScope == "neutral" and MarketSync.BeginNeutralFullScan then
        MarketSync.BeginNeutralFullScan()
    end
    Query("", 0, true)
    return true
end

function S.StartLiveSearch(query)
    if S.Active then S.Cancel("replaced by live search") end
    if S.IsDisabledByAuctionator and S.IsDisabledByAuctionator() then
        S.Status = "MarketSync live search disabled while Auctionator scans"
        Notify()
        return false
    end
    if not S.IsAvailable() then
        S.Status = "Auctioneer must be open to search"
        Notify()
        return false
    end
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or nil
    if not query or query == "" then
        S.Status = "Enter an item name to search"
        Notify()
        return false
    end
    Start("Searching auctions for " .. query .. "...", "search")
    legacy.query = query
    Query(query, 0, false)
    return true
end

local function MatchesPurchase(row, index)
    if not row or not index then return false end
    local name, _, count, _, _, _, _, _, _, buyout, bidAmount,
        _, _, owner, _, _, itemID = GetAuctionItemInfo("list", index)
    local link = GetAuctionItemLink and GetAuctionItemLink("list", index) or nil
    itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    return itemID == row.itemID and Suffix(link) == row.itemSuffix
        and tonumber(count) == row.stackSize and tonumber(buyout) == row.buyout
        and (not row.link or row.link == link) and tonumber(bidAmount) ~= row.buyout
        and owner ~= (UnitName and UnitName("player"))
end

-- A grouped search result is only a quote. Re-query its source page before
-- enabling purchase; the final click checks the live row again.
function S.PrepareLivePurchase(row)
    if type(row) ~= "table" or not row.query or row.page == nil then return false end
    if S.IsDisabledByAuctionator and S.IsDisabledByAuctionator() then return false end
    if S.Active then S.Cancel("replaced by purchase check") end
    if not S.IsAvailable() then return false end
    Start("Checking selected auction...", "purchase")
    legacy.purchaseTarget = row
    legacy.page = row.page
    Query(row.query, row.page, false)
    return true
end

function S.BuyPreparedLivePurchase(row)
    local ready = S.PurchaseReady
    if not ready or ready.row ~= row or S.Active or not S.IsAvailable() then return false end
    if type(PlaceAuctionBid) ~= "function" or not MatchesPurchase(row, ready.index) then
        S.PurchaseReady = nil
        S.Status = "Auction changed. Select it again to refresh the price."
        Notify()
        return false
    end
    if type(GetMoney) == "function" and GetMoney() < row.buyout then return false end
    S.PurchaseReady = nil
    PlaceAuctionBid("list", ready.index, row.buyout)
    S.Status = "Purchase submitted; confirm delivery in your mailbox."
    Notify()
    return true
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "AUCTION_ITEM_LIST_UPDATE")
pcall(frame.RegisterEvent, frame, "AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_CLOSED" then
        S.PurchaseReady = nil
        if S.Active then S.Cancel("Auctioneer closed") end
        return
    end
    if not S.Active or not legacy.waiting then return end
    legacy.waiting = false
    local count, total = GetNumAuctionItems("list")
    count, total = tonumber(count) or 0, tonumber(total) or 0
    if legacy.mode == "purchase" then
        local target = legacy.purchaseTarget
        S.PurchaseReady = nil
        for i = 1, count do
            if MatchesPurchase(target, i) then
                S.PurchaseReady = { row = target, index = i }
                break
            end
        end
        S.Active = false
        legacy.mode, legacy.purchaseTarget = nil, nil
        S.Status = S.PurchaseReady and "Exact stack found. Review and buy one stack."
            or "That exact stack is no longer available. Search again."
        Notify()
        return
    end
    local generation = S.Generation
    local targetID = legacy.mode == "target" and S.Pending and S.Pending.itemID or nil
    local targetSuffix = legacy.mode == "target" and S.Pending and S.Pending.itemSuffix or nil
    local index = 1
    if legacy.mode == "full" then S.Progress.total = count end
    local function ReadBatch()
        if not S.Active or S.Generation ~= generation then return end
        local stop = math.min(count, index + 249)
        for i = index, stop do
            if legacy.mode == "search" then ReadSearchRow(i)
            else ReadRow(i, targetID, targetSuffix) end
        end
        index = stop + 1
        if legacy.mode == "full" then
            S.Progress.current = stop
            S.Status = string.format("Processing auctions (%d / %d)...", stop, count)
            Notify()
        end
        if index <= count then After(0.01, ReadBatch) return end
        if legacy.mode == "search" then
            S.Progress.current = math.min((legacy.page * 50) + count, total)
            S.Progress.total = total
            S.Status = string.format("Searching auctions (%d / %d)...", S.Progress.current, total)
            Notify()
        end
        if (legacy.mode == "target" or legacy.mode == "search") and (legacy.page + 1) * 50 < total then
            legacy.page = legacy.page + 1
            local name = legacy.mode == "search" and legacy.query
                or (S.Pending.name or (MarketSync.GetItemInfo and MarketSync.GetItemInfo(S.Pending.itemID)))
            Query(name, legacy.page, false)
            return
        end
        if legacy.mode == "search" then Finish() return end
        SaveRows(function()
            if legacy.mode == "full" then
                local now = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
                if MarketSyncDB then MarketSyncDB.LastFullScanAt = now end
                local db = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
                if db and S.ScanScope ~= "neutral" then
                    db.FullScanTime, db.PersonalScanTime, db.SwarmTSF = now, now, now
                end
                Finish()
            else
                S.Pending = nil
                After(0.05, NextTarget)
            end
        end)
    end
    ReadBatch()
end)
