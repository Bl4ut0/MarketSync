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
    S.RecentResults = {}
    S.ResultsRevision = (S.ResultsRevision or 0) + 1
    S.Progress = { current = 0, total = 0 }
    S.Status = label
    S.ScanTime = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
    S.ScanScope = (MarketSync.IsNeutralAHOpen == true
        or (MarketSync.IsNeutralAHSession and MarketSync.IsNeutralAHSession())) and "neutral" or "main"
    legacy.mode, legacy.page, legacy.waiting = mode, 0, false
    legacy.requestID = legacy.requestID + 1
    legacy.data, legacy.keys = {}, {}
    if MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1
        and MarketSync.ObservationAPI.v1.HasListeners() then
        S.ObservationScanID = MarketSync.ObservationAPI.v1.NewScanID("local")
        Emit("start")
    end
    Notify()
end

local function Finish()
    local mode = legacy.mode
    local scope = S.ScanScope
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

function S.Cancel(reason)
    if legacy.mode == "full" and S.ScanScope == "neutral" and MarketSync.FailNeutralFullScan then
        MarketSync.FailNeutralFullScan()
    end
    legacy.mode, legacy.waiting, legacy.data, legacy.keys = nil, false, nil, nil
    legacy.requestID = legacy.requestID + 1
    Emit("cancel", reason)
    oldCancel(reason)
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

local function Suffix(link)
    if type(link) ~= "string" then return 0 end
    local itemString = link:match("|H(item:[^|]+)|h") or link:match("(item:%d+[^%s|]*)")
    if not itemString then return 0 end
    local fields = {}
    for field in itemString:gmatch("([^:]+)") do fields[#fields + 1] = field end
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
        if key and not seen[key.itemID] then
            if type(item) == "table" then key.name = item.name end
            seen[key.itemID] = true
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

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "AUCTION_ITEM_LIST_UPDATE")
pcall(frame.RegisterEvent, frame, "AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_CLOSED" then
        if S.Active then S.Cancel("Auctioneer closed") end
        return
    end
    if not S.Active or not legacy.waiting then return end
    legacy.waiting = false
    local count, total = GetNumAuctionItems("list")
    count, total = tonumber(count) or 0, tonumber(total) or 0
    local generation = S.Generation
    local targetID = legacy.mode == "target" and S.Pending and S.Pending.itemID or nil
    local targetSuffix = legacy.mode == "target" and S.Pending and S.Pending.itemSuffix or nil
    local index = 1
    if legacy.mode == "full" then S.Progress.total = count end
    local function ReadBatch()
        if not S.Active or S.Generation ~= generation then return end
        local stop = math.min(count, index + 249)
        for i = index, stop do ReadRow(i, targetID, targetSuffix) end
        index = stop + 1
        if legacy.mode == "full" then
            S.Progress.current = stop
            S.Status = string.format("Processing auctions (%d / %d)...", stop, count)
            Notify()
        end
        if index <= count then After(0.01, ReadBatch) return end
        if legacy.mode == "target" and (legacy.page + 1) * 50 < total then
            legacy.page = legacy.page + 1
            Query(S.Pending.name or (MarketSync.GetItemInfo and MarketSync.GetItemInfo(S.Pending.itemID)), legacy.page, false)
            return
        end
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
