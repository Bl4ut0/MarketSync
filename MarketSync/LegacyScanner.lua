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
    legacy.terms, legacy.termIndex, legacy.exactSearch = nil, nil, false
    legacy.requestID = legacy.requestID + 1
    legacy.data, legacy.keys = {}, {}
    if mode == "search" then
        S.LiveSearchResults = {}
        S.LiveSearchProgress = { completed = 0, total = 1, state = "scanning" }
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
        if S.LiveSearchProgress then S.LiveSearchProgress.state = "complete" end
        S.LiveSearchAt = GetTime()
        S.LiveSearchScope = scope
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
        bidAmount, _, _, owner, _, saleStatus, itemID = GetAuctionItemInfo("list", index)
    local link = GetAuctionItemLink and GetAuctionItemLink("list", index) or nil
    itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    count, buyout = tonumber(count), tonumber(buyout)
    if not itemID or not count or count < 1 or not buyout or buyout < 1 then return end
    if (UnitName and owner==UnitName("player")) or tonumber(bidAmount)==buyout
        or (saleStatus and saleStatus ~= 0) then return end
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
            auctions = 1, available = count, page = legacy.page, query = legacy.query,
            queryExact = legacy.exactSearch }
        legacy.data[identity] = row
        S.LiveSearchResults[#S.LiveSearchResults + 1] = row
    end
end

function S.Cancel(reason)
    if legacy.mode == "search" and S.LiveSearchProgress then
        S.LiveSearchProgress.state = "stopped"
    end
    if legacy.mode == "multi" and S.MultiScan then
        -- Finished items keep their results; the interrupted one goes back to the queue.
        if legacy.multiEntry and legacy.multiEntry.state == "scanning" then
            legacy.multiEntry.state = "queued"
        end
        legacy.multiEntry, legacy.multiGroups, legacy.multiOrder = nil, nil, nil
        S.MultiScan.state = "stopped"
        S.MultiScan.revision = (S.MultiScan.revision or 0) + 1
    end
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

-- onFail(reason) replaces cancelling the whole scan when one query fails; the
-- multi-item scan uses it to retry or skip a single item.
local function Query(name, page, getAll, onFail)
    local generation = S.Generation
    local attempts = 0
    local fail = onFail or S.Cancel
    local function Try()
        if not S.Active or S.Generation ~= generation then return end
        if not CanQuery(getAll) then
            attempts = attempts + 1
            if attempts < 40 then
                After(0.25, Try)
            else
                fail("Auction House query throttled")
            end
            return
        end
        legacy.waiting = true
        legacy.requestID = legacy.requestID + 1
        local requestID = legacy.requestID
        local ok = pcall(QueryAuctionItems, name or "", nil, nil, page or 0,
            nil, nil, getAll == true, legacy.exactSearch == true, nil)
        if not ok then
            legacy.waiting = false
            fail("Auction House query failed")
            return
        end
        After(15, function()
            if S.Active and S.Generation == generation and legacy.waiting
                and legacy.requestID == requestID then
                legacy.waiting = false
                fail("Auction House response timed out")
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
        S.Status = "Open the Auction House to scan."
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
        S.Status = "Open the Auction House to scan."
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
        S.Status = "Open the Auction House to search."
        Notify()
        return false
    end
    local terms
    if type(query) == "table" then
        terms = {}
        local seen = {}
        for _, item in ipairs(query) do
            local name = type(item) == "table" and item.name or nil
            local id = type(item) == "table" and item.itemID or tonumber(item)
            if not name and id and MarketSync.GetItemInfo then name = MarketSync.GetItemInfo(id) end
            if not name and id and GetItemInfo then name = GetItemInfo(id) end
            name = type(name) == "string" and name:match("^%s*(.-)%s*$") or nil
            if not name or name == "" then
                S.Status = "Item name unavailable; try again after item data loads"
                Notify()
                return false
            end
            if not seen[name] then terms[#terms + 1], seen[name] = name, true end
        end
        query = terms[1]
    end
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or nil
    if not query or query == "" then
        S.Status = "Enter an item name to search"
        Notify()
        return false
    end
    Start("Searching auctions for " .. query .. "...", "search")
    legacy.terms, legacy.termIndex, legacy.exactSearch = terms, terms and 1, terms ~= nil
    legacy.query = query
    S.LiveSearchProgress.total = terms and #terms or 1
    S.LiveSearchProgress.query = query
    Notify()
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
    if MarketSync.PurchaseList and MarketSync.PurchaseList.state=="awaiting" then return false end
    if S.IsDisabledByAuctionator and S.IsDisabledByAuctionator() then return false end
    if S.Active then S.Cancel("replaced by purchase check") end
    if not S.IsAvailable() then return false end
    Start("Checking selected auction...", "purchase")
    legacy.purchaseTarget = row
    legacy.exactSearch = row.queryExact == true
    legacy.page = row.page
    Query(row.query, row.page, false)
    return true
end

function S.BuyPreparedLivePurchase(row)
    if MarketSync.PurchaseList and MarketSync.PurchaseList.state=="awaiting"
        and MarketSync.PurchaseList.pending~=row then return false end
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
    if MarketSync.CraftLedger then
        MarketSync.CraftLedger.ExpectPurchase(row.itemID, row.stackSize or 1, row.buyout)
    end
    PlaceAuctionBid("list", ready.index, row.buyout)
    S.Status = "Purchase submitted; confirm delivery in your mailbox."
    Notify()
    return true
end

-- ================================================================
-- Multi-item price scan (legacy Scan page)
-- One exact-name query per item, so each item only pages through its own
-- auctions. Each finished item keeps its live listings for the page and saves
-- its lowest unit price to MarketSync history. A query that fails or times out
-- is retried once; after that only that item is marked failed and the scan
-- moves on. Stopping keeps every finished item.
-- ================================================================
local MULTI_RETRIES = 1

local function MultiItemName(entry)
    if entry.name then return entry.name end
    local cached = MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[entry.itemID]
    local name = cached and cached.n
    if not name and MarketSync.GetItemInfo then name = MarketSync.GetItemInfo(entry.itemID) end
    if not name and GetItemInfo then name = GetItemInfo(entry.itemID) end
    if type(name) == "string" and name ~= "" then entry.name = name end
    return entry.name
end

local function MultiNotify()
    local multi = S.MultiScan
    if multi then multi.revision = (multi.revision or 0) + 1 end
    Notify()
end

local function ReadMultiRow(index)
    local entry = legacy.multiEntry
    if not entry then return end
    local name, texture, count, quality, _, level, _, _, _, buyout,
        _, _, _, owner, _, saleStatus, itemID = GetAuctionItemInfo("list", index)
    local link = GetAuctionItemLink and GetAuctionItemLink("list", index) or nil
    itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    count, buyout = tonumber(count), tonumber(buyout)
    -- Bid-only and already-sold auctions have no buyout a player can use.
    if itemID ~= entry.itemID or not count or count < 1 or not buyout or buyout < 1 then return end
    if saleStatus and saleStatus ~= 0 then return end
    local suffix = Suffix(link)
    if entry.itemSuffix and entry.itemSuffix ~= 0 and suffix ~= entry.itemSuffix then return end
    local mine = UnitName and owner ~= nil and owner == UnitName("player") or false
    entry.icon = entry.icon or texture
    entry.quality = entry.quality or quality
    entry.link = entry.link or link
    -- Same per-unit rounding as the target scan, so history stays comparable.
    local unitPrice = math.floor(buyout / count)
    if unitPrice < 1 then return end
    local identity = table.concat({ suffix, count, buyout, mine and 1 or 0 }, ":")
    local group = legacy.multiGroups[identity]
    if group then
        group.auctions = group.auctions + 1
        group.available = group.available + count
    else
        group = { itemID = itemID, itemSuffix = suffix, link = link, name = name, icon = texture,
            quality = quality, level = level, stackSize = count, buyout = buyout,
            unitPrice = unitPrice, auctions = 1, available = count, mine = mine,
            -- Where this stack was seen, so PrepareLivePurchase can re-check it before buying.
            query = entry.name, page = legacy.page, queryExact = legacy.exactSearch }
        legacy.multiGroups[identity] = group
        legacy.multiOrder[#legacy.multiOrder + 1] = group
    end
end

local NextMulti

local function CompleteMultiItem()
    local entry = legacy.multiEntry
    if not entry then return end
    local listings = legacy.multiOrder or {}
    table.sort(listings, function(a, b)
        if a.unitPrice ~= b.unitPrice then return a.unitPrice < b.unitPrice end
        if a.stackSize ~= b.stackSize then return a.stackSize > b.stackSize end
        return (a.mine and 0 or 1) < (b.mine and 0 or 1)
    end)
    entry.listings = listings
    entry.minUnit, entry.available, entry.auctions = nil, 0, 0
    local variants = {}
    for _, group in ipairs(listings) do
        entry.available = entry.available + group.available
        entry.auctions = entry.auctions + group.auctions
        if not entry.minUnit or group.unitPrice < entry.minUnit then entry.minUnit = group.unitPrice end
        local variant = variants[group.itemSuffix]
        if not variant then
            variant = { group = group, unitPrice = group.unitPrice, available = 0 }
            variants[group.itemSuffix] = variant
        end
        variant.available = variant.available + group.available
        if group.unitPrice < variant.unitPrice then variant.unitPrice, variant.group = group.unitPrice, group end
    end
    entry.state = #listings > 0 and "done" or "empty"
    entry.reason = nil
    entry.scannedAt = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
    if MarketSync.RecordScanObservation then
        for suffix, variant in pairs(variants) do
            local g = variant.group
            MarketSync.RecordScanObservation({ itemID = entry.itemID, itemSuffix = suffix,
                itemLevel = g.level or 0, name = g.name, icon = g.icon, quality = g.quality,
                itemLink = g.link }, variant.unitPrice, variant.available, false, false, true)
        end
    end
    legacy.multiEntry, legacy.multiGroups, legacy.multiOrder = nil, nil, nil
    local multi = S.MultiScan
    multi.completed = (multi.completed or 0) + 1
    S.Progress.current = multi.completed
    MultiNotify()
    After(0.05, NextMulti)
end

local function FailMultiItem(reason)
    local entry = legacy.multiEntry
    if not entry or not S.Active or legacy.mode ~= "multi" then return end
    entry.attempts = (entry.attempts or 0) + 1
    if entry.attempts <= MULTI_RETRIES then
        legacy.page, legacy.multiGroups, legacy.multiOrder = 0, {}, {}
        S.Status = string.format("Retrying %s (%s)", entry.name or ("#" .. entry.itemID), reason)
        MultiNotify()
        Query(entry.name, 0, false, FailMultiItem)
        return
    end
    entry.state, entry.reason = "failed", reason
    legacy.multiEntry, legacy.multiGroups, legacy.multiOrder = nil, nil, nil
    local multi = S.MultiScan
    multi.completed = (multi.completed or 0) + 1
    S.Progress.current = multi.completed
    MultiNotify()
    After(0.25, NextMulti)
end

local function FinishMulti()
    local multi = S.MultiScan
    multi.state = "complete"
    multi.finishedAt = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
    Finish()
    local done, empty, failed, skipped = 0, 0, 0, 0
    for _, entry in ipairs(multi.items) do
        if entry.state == "done" then done = done + 1
        elseif entry.state == "empty" then empty = empty + 1
        elseif entry.state == "failed" then failed = failed + 1
        elseif entry.state == "skipped" then skipped = skipped + 1 end
    end
    S.Status = string.format("Scan complete: %d priced, %d with no auctions%s%s", done, empty,
        failed > 0 and string.format(", %d failed", failed) or "",
        skipped > 0 and string.format(", %d skipped (item info not loaded)", skipped) or "")
    MultiNotify()
end

NextMulti = function()
    if not S.Active or legacy.mode ~= "multi" then return end
    local multi = S.MultiScan
    local entry
    for i = (multi.index or 0) + 1, #multi.items do
        if multi.items[i].state == "queued" then multi.index, entry = i, multi.items[i]; break end
    end
    if not entry and not multi.retriedNames then
        -- Item names load from the server on first request; give skipped items one more pass.
        multi.retriedNames = true
        for _, item in ipairs(multi.items) do
            if item.state == "skipped" then item.state = "queued"; multi.completed = multi.completed - 1 end
        end
        multi.index = 0
        return NextMulti()
    end
    if not entry then FinishMulti() return end
    if not MultiItemName(entry) then
        entry.state, entry.reason = "skipped", "Item info not loaded yet"
        multi.completed = (multi.completed or 0) + 1
        MultiNotify()
        After(0.01, NextMulti)
        return
    end
    entry.state, entry.attempts, entry.reason = "scanning", 0, nil
    legacy.multiEntry, legacy.multiGroups, legacy.multiOrder = entry, {}, {}
    legacy.page = 0
    -- Random-suffix listings are named "<item> of the Bear", which an exact search
    -- for the base name never matches; rows are filtered by item ID either way.
    entry.looseSearch = (entry.itemSuffix or 0) ~= 0
    legacy.exactSearch = not entry.looseSearch
    S.Pending = entry
    S.Status = string.format("Scanning %d / %d: %s", (multi.completed or 0) + 1, #multi.items, entry.name)
    MultiNotify()
    Query(entry.name, 0, false, FailMultiItem)
end

-- items: item IDs, links, DB keys, or { itemID, itemSuffix, name } tables.
function S.StartMultiScan(items)
    if S.Active then S.Cancel("replaced by new scan") end
    if S.IsDisabledByAuctionator and S.IsDisabledByAuctionator() then
        S.Status = "MarketSync scanning disabled while Auctionator scans"
        Notify()
        return false
    end
    if not S.IsAvailable() then
        S.Status = "Open the Auction House to scan."
        Notify()
        return false
    end
    local entries, seen = {}, {}
    for _, item in ipairs(items or {}) do
        local key = S.ToItemKey(item)
        local suffix = key and (key.itemSuffix or 0) or 0
        local identity = key and string.format("%d:%d", key.itemID, suffix)
        if key and not seen[identity] then
            seen[identity] = true
            local dbKey = suffix ~= 0 and string.format("p:%d:%d", key.itemID, suffix) or tostring(key.itemID)
            local info = MarketSync.GetItemPriceAndScanInfo and MarketSync.GetItemPriceAndScanInfo(dbKey)
            entries[#entries + 1] = { itemID = key.itemID, itemSuffix = suffix,
                name = type(item) == "table" and item.name or nil,
                link = type(item) == "table" and item.link or nil,
                previousPrice = info and info.price or nil, state = "queued" }
        end
    end
    if #entries == 0 then
        S.Status = "Add items to scan first."
        Notify()
        return false
    end
    Start("Starting multi-item scan...", "multi")
    legacy.exactSearch = true
    S.MultiScan = { items = entries, state = "scanning", index = 0, completed = 0,
        startedAt = S.ScanTime, revision = ((S.MultiScan and S.MultiScan.revision) or 0) + 1 }
    S.Progress.total = #entries
    NextMulti()
    return true
end

function S.GetMultiScan()
    return S.MultiScan
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "AUCTION_ITEM_LIST_UPDATE")
pcall(frame.RegisterEvent, frame, "AUCTION_HOUSE_CLOSED")
-- The legacy AH fires AUCTION_ITEM_LIST_UPDATE before every row has loaded:
-- owners and links arrive in later updates. A multi-item page is read only when
-- every row of the target item has both (as Auctionator's scan does), so own
-- auctions and suffix variants are recognised. Owners of deleted characters may
-- never load, so a page is read anyway after a short grace period.
local MULTI_PAGE_GRACE = 2.5
local HandleEvent

local function WaitsForFullPage()
    return legacy.mode == "multi" or legacy.mode == "purchase"
end

-- The multi scan and the purchase check (which compares the exact link) both
-- need every row of their item complete.
local function MultiPageReady()
    local entry = legacy.mode == "purchase" and legacy.purchaseTarget or legacy.multiEntry
    if not entry then return true end
    local count = tonumber((GetNumAuctionItems("list"))) or 0
    for i = 1, count do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, owner, _, _, itemID = GetAuctionItemInfo("list", i)
        local link = GetAuctionItemLink and GetAuctionItemLink("list", i) or nil
        itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
        if not itemID then return false end
        if itemID == entry.itemID and (owner == nil or link == nil) then return false end
    end
    return true
end

local function WaitForMultiPage()
    if legacy.graceRequest == legacy.requestID then return end
    legacy.graceRequest = legacy.requestID
    local requestID, generation = legacy.requestID, S.Generation
    After(MULTI_PAGE_GRACE, function()
        if S.Active and S.Generation == generation and legacy.waiting
            and legacy.requestID == requestID and WaitsForFullPage() then
            legacy.forceRead = true
            HandleEvent(nil, "AUCTION_ITEM_LIST_UPDATE")
        end
    end)
end

HandleEvent = function(_, event)
    if event == "AUCTION_HOUSE_CLOSED" then
        S.PurchaseReady = nil
        if S.Active then S.Cancel("Auctioneer closed") end
        return
    end
    if not S.Active or not legacy.waiting then return end
    if WaitsForFullPage() and not legacy.forceRead and not MultiPageReady() then
        WaitForMultiPage()
        return
    end
    legacy.forceRead = false
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
            elseif legacy.mode == "multi" then ReadMultiRow(i)
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
        if legacy.mode == "multi" then
            if not legacy.multiEntry then return end
            local entry = legacy.multiEntry
            if (legacy.page + 1) * 50 < total then
                legacy.page = legacy.page + 1
                Query(entry.name, legacy.page, false, FailMultiItem)
            elseif #legacy.multiOrder == 0 and not entry.looseSearch then
                -- Nothing under the exact name: the item may only be listed with
                -- random suffixes. Search once more by name containing it.
                entry.looseSearch = true
                legacy.exactSearch = false
                legacy.page = 0
                Query(entry.name, 0, false, FailMultiItem)
            else
                CompleteMultiItem()
            end
            return
        end
        if (legacy.mode == "target" or legacy.mode == "search") and (legacy.page + 1) * 50 < total then
            legacy.page = legacy.page + 1
            local name = legacy.mode == "search" and legacy.query
                or (S.Pending.name or (MarketSync.GetItemInfo and MarketSync.GetItemInfo(S.Pending.itemID)))
            Query(name, legacy.page, false)
            return
        end
        if legacy.mode == "search" then
            S.LiveSearchProgress.completed = legacy.termIndex or 1
            if legacy.terms and legacy.termIndex < #legacy.terms then
                legacy.termIndex = legacy.termIndex + 1
                legacy.query = legacy.terms[legacy.termIndex]
                S.LiveSearchProgress.query = legacy.query
                legacy.page = 0
                S.Status = string.format("Searching list (%d / %d): %s", legacy.termIndex, #legacy.terms, legacy.query)
                Notify()
                Query(legacy.query, 0, false)
            else Finish() end
            return
        end
        SaveRows(function()
            if legacy.mode == "full" then
                local now = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
                if MarketSyncDB then MarketSyncDB.LastFullScanAt = now end
                local db = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
                if db and S.ScanScope ~= "neutral" then
                    db.FullScanTime, db.SwarmTSF = now, now
                    if MarketSync.RecordPersonalScan then MarketSync.RecordPersonalScan(db, now)
                    else db.PersonalScanTime = now end
                end
                Finish()
            else
                S.Pending = nil
                After(0.05, NextTarget)
            end
        end)
    end
    ReadBatch()
end
frame:SetScript("OnEvent", HandleEvent)
