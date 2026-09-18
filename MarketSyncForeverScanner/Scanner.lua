local S = MarketSyncForeverScanner
local A = C_AuctionHouse
S.Generation = 0
S.NextRequestAt = 0
S.Scheduled = false

local function safeCall(name, ...)
  local ok, result = pcall(A[name], ...)
  if not ok then error("C_AuctionHouse." .. name .. ": " .. tostring(result), 0) end
  return result
end

function S.IsAuctioneerAvailable()
  return S.Ready == true and S.AuctioneerOpen == true and AuctionHouseFrame ~= nil and S.Store ~= nil
end

function S.Cancel(reason)
  S.Generation = S.Generation + 1
  S.Active, S.Pending, S.Queue, S.Scheduled = false, nil, nil, false
  S.ThrottleWaitStarted, S.BatchCapture = nil, false
  S.Status = reason or "Scan cancelled"
  S.Notify()
end

function S.CaptureBrowse()
  if not S.IsAuctioneerAvailable() then return end
  S.BatchCapture = true
  for _, row in ipairs(A.GetBrowseResults()) do
    if S.CopyKey(row.itemKey) then
      -- Browse prices/quantities are advertised values for a query, never a whole-market scan.
      S.SaveSnapshot(row.itemKey, {
        source = "native-browse", complete = false, coverage = "observed-browse",
        browseMinPrice = row.minPrice, available = row.totalQuantity,
      })
    end
  end
  S.BatchCapture = false
  S.Notify()
end

local function summarize(key, commodity)
  local argument = commodity and key.itemID or key
  local countName = commodity and "GetNumCommoditySearchResults" or "GetNumItemSearchResults"
  local infoName = commodity and "GetCommoditySearchResultInfo" or "GetItemSearchResultInfo"
  local completeName = commodity and "HasFullCommoditySearchResults" or "HasFullItemSearchResults"
  local count = safeCall(countName, argument)
  local snapshot = {
    source = commodity and "native-commodity-search" or "native-item-search",
    coverage = "one-native-item-key", complete = safeCall(completeName, argument),
    available = 0, pricedQuantity = 0, rows = count, priceLevels = {},
  }
  snapshot.nativeComplete = snapshot.complete
  local bins, seenAuctions = {}, {}
  for index = 1, count do
    local row = safeCall(infoName, argument, index)
    if row then
      -- A broader sell search can include other variants; preserve exact native-key identity.
      local rowKey = not commodity and S.KeyID(row.itemKey) or nil
      if not commodity and not rowKey then snapshot.complete = false; snapshot.dataMissing = true end
      local sameKey = commodity or rowKey == S.KeyID(key)
      if sameKey and (not row.auctionID or not seenAuctions[row.auctionID]) then
        if row.auctionID then seenAuctions[row.auctionID] = true end
        local quantity = tonumber(row.quantity) or 0
        if quantity > 0 then
          snapshot.available = snapshot.available + quantity
          local unitPrice = commodity and row.unitPrice or nil
          if not commodity and row.buyoutAmount and row.buyoutAmount > 0 then
            unitPrice = row.buyoutAmount / quantity
          end
          if type(unitPrice) == "number" and unitPrice > 0 then
            snapshot.pricedQuantity = snapshot.pricedQuantity + quantity
            snapshot.minUnitPrice = snapshot.minUnitPrice and math.min(snapshot.minUnitPrice, unitPrice) or unitPrice
            bins[unitPrice] = (bins[unitPrice] or 0) + quantity
          end
        else
          snapshot.complete = false
          snapshot.dataMissing = true
        end
      end
    else
      -- Data loading can leave holes even when the native completeness flag is true.
      snapshot.complete = false
      snapshot.dataMissing = true
    end
  end
  for price, quantity in pairs(bins) do
    table.insert(snapshot.priceLevels, {unitPrice = price, quantity = quantity})
  end
  table.sort(snapshot.priceLevels, function(a, b) return a.unitPrice < b.unitPrice end)
  -- Keep bounded depth for portable browsing without inventing missing volume.
  while #snapshot.priceLevels > 20 do table.remove(snapshot.priceLevels) end
  return snapshot
end

function S.Schedule()
  if not S.Active or S.Scheduled then return end
  S.Scheduled = true
  local generation = S.Generation
  local delay = math.max(0.1, S.NextRequestAt - GetTime())
  C_Timer.After(delay, function()
    if generation ~= S.Generation then return end
    S.Scheduled = false
    local ok, err = pcall(S.Pump)
    if not ok then S.Cancel("Scan failed: " .. tostring(err)) end
  end)
end

function S.Issue(name, argument, more)
  local generation = S.Generation
  S.OwnRequest = true
  S.NextRequestAt = GetTime() + 1.1 -- Below documented 100 search calls/minute, plus native readiness.
  local ok, result
  if more then
    ok, result = pcall(A[name], argument)
  else
    ok, result = pcall(A[name], argument, {}, false)
  end
  S.OwnRequest = false
  if not ok then S.Cancel("Request rejected: " .. tostring(result)); return false end
  local pending = S.Pending
  if pending and generation == S.Generation then
    pending.requestToken = (pending.requestToken or 0) + 1
    local token = pending.requestToken
    C_Timer.After(25, function()
      if generation == S.Generation and S.Pending == pending and pending.requestToken == token then
        S.Cancel("Timed out waiting for native auction results; last completed prices retained")
      end
    end)
  end
  if more and result == true and pending and S.Pending == pending and generation == S.Generation then
    S.CaptureSearch(pending.key, pending.commodity)
  end
  return true
end

function S.Pump()
  if not S.Active then return end
  if not S.IsAuctioneerAvailable() then S.Cancel("Auctioneer closed; saved prices retained"); return end
  if GetTime() < S.NextRequestAt then S.Schedule(); return end
  if not safeCall("IsThrottledMessageSystemReady") then
    S.ThrottleWaitStarted = S.ThrottleWaitStarted or GetTime()
    if GetTime() - S.ThrottleWaitStarted >= 60 then
      S.Cancel("Native auction throttle did not become ready; last completed prices retained")
      return
    end
    S.Status = "Waiting for native auction throttle"
    S.NextRequestAt = GetTime() + 0.5
    S.Schedule(); S.Notify(); return
  end
  S.ThrottleWaitStarted = nil
  if S.Pending then
    if S.Pending.cacheRetry then
      S.Pending.cacheRetry = false
      S.CaptureSearch(S.Pending.key, S.Pending.commodity)
    elseif S.Pending.needsMore then
      S.Pending.needsMore = false
      S.Pending.awaiting = true
      local commodity = S.Pending.commodity
      S.Issue(commodity and "RequestMoreCommoditySearchResults" or "RequestMoreItemSearchResults",
        commodity and S.Pending.key.itemID or S.Pending.key, true)
    end
    return
  end
  S.QueueIndex = S.QueueIndex + 1
  local key = S.Queue[S.QueueIndex]
  if not key then
    S.Store.completedWatchScans = S.Store.completedWatchScans + 1
    S.Store.lastWatchScanAt = time()
    S.Cancel("Watch list refreshed: " .. tostring(S.CompletedCount) .. " keys; not a full-market scan")
    return
  end
  local record = S.RememberKey(key)
  if not record or type(record.isCommodity) ~= "boolean" then
    S.Cancel("Native item metadata not loaded; open that item in the auction house and retry")
    return
  end
  S.Pending = {key = key, keyID = S.KeyID(key), commodity = record.isCommodity, awaiting = true, pages = 0}
  S.Status = "Refreshing " .. S.QueueIndex .. "/" .. #S.Queue .. ": " .. (record.name or tostring(key.itemID))
  S.Notify()
  S.Issue("SendSearchQuery", key, false)
end

function S.StartWatched()
  if S.Active then return false end
  if not S.IsAuctioneerAvailable() then S.Status = "Open an auctioneer to refresh watched items"; S.Notify(); return false end
  local queue = {}
  for id in pairs(S.Store.watched) do
    local record = S.Store.records[id]
    if record then table.insert(queue, S.CopyKey(record.key)) end
  end
  table.sort(queue, function(a, b) return S.KeyID(a) < S.KeyID(b) end)
  if #queue == 0 then S.Status = "Watch items using the star beside saved listings first"; S.Notify(); return false end
  if #queue > 50 then S.Status = "Watch list exceeds the 50-key test limit"; S.Notify(); return false end
  S.Generation = S.Generation + 1
  S.Queue, S.QueueIndex, S.CompletedCount, S.Active = queue, 0, 0, true
  S.Schedule()
  return true
end

function S.CaptureSearch(key, commodity)
  if not S.IsAuctioneerAvailable() then return end
  if not S.CopyKey(key) then return end
  local snapshot = summarize(key, commodity)
  local pending = S.Pending
  local matches = pending and (commodity and pending.commodity and pending.key.itemID == key.itemID
    or not commodity and not pending.commodity and pending.keyID == S.KeyID(key))
  if matches then
    if snapshot.complete then
      S.SaveSnapshot(pending.key, snapshot)
      pending.requestToken = (pending.requestToken or 0) + 1
      S.Pending = nil
      S.CompletedCount = S.CompletedCount + 1
      S.Schedule()
    elseif snapshot.nativeComplete and snapshot.dataMissing then
      S.SaveSnapshot(pending.key, snapshot)
      pending.awaiting = false
      pending.cacheRetry = true
      S.NextRequestAt = math.max(S.NextRequestAt, GetTime() + 0.5)
      S.Schedule()
    elseif pending.awaiting then
      S.SaveSnapshot(pending.key, snapshot)
      pending.awaiting = false
      pending.pages = pending.pages + 1
      if pending.pages > 100 then
        S.Cancel("Paging limit reached; result remains partial")
      else
        pending.needsMore = true
        S.Schedule()
      end
    end
  elseif not S.Active then
    S.SaveSnapshot(key, snapshot)
  end
end

function S.CommodityKey(itemID)
  if S.Pending and S.Pending.commodity and S.Pending.key.itemID == itemID then return S.Pending.key end
  if S.Store then
    for _, record in pairs(S.Store.records) do
      if record.key.itemID == itemID and record.isCommodity then return record.key end
    end
  end
  return {itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0}
end

function S.ExternalQuery()
  if S.Active and not S.OwnRequest then S.Cancel("Native auction search changed; watch scan stopped") end
end
