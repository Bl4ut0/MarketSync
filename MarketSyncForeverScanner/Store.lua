-- GPL-3.0-or-later. Native price provider prototype, independent of Auctionator's schema.
MarketSyncForeverScanner = {Version = "0.2.0", Status = "Offline browsing", Active = false}
local S = MarketSyncForeverScanner

function S.CopyKey(key)
  if type(key) ~= "table" or type(key.itemID) ~= "number" or key.itemID <= 0 then return nil end
  return {
    itemID = key.itemID, itemLevel = key.itemLevel or 0,
    itemSuffix = key.itemSuffix or 0, battlePetSpeciesID = key.battlePetSpeciesID or 0,
  }
end

function S.KeyID(key)
  local k = S.CopyKey(key)
  if not k then return nil end
  return table.concat({k.itemID, k.itemLevel, k.itemSuffix, k.battlePetSpeciesID}, ":")
end

function S.InitializeStore()
  local realm = GetNormalizedRealmName() or GetRealmName()
  if not realm or realm == "" then return false end
  local region = GetCurrentRegion and GetCurrentRegion() or "unknown-region"
  local faction = UnitFactionGroup("player") or "unknown-faction"
  MarketSyncForeverScanDB = MarketSyncForeverScanDB or {schema = 1, markets = {}}
  if MarketSyncForeverScanDB.schema ~= 1 then
    S.Status = "Unsupported saved-data schema"
    return false
  end
  MarketSyncForeverScanDB.markets = MarketSyncForeverScanDB.markets or {}
  -- Faction and the user's main/neutral bucket remain separate until native market scope is verified.
  S.MarketPrefix = table.concat({"forever", tostring(region), realm, faction}, "|")
  S.SetMarket("main")
  return true
end

function S.SetMarket(bucket)
  if bucket ~= "main" and bucket ~= "neutral" then return false end
  if not S.MarketPrefix or S.Active then return false end
  if S.AuctioneerOpen then
    S.Status = "Close the auctioneer before changing the Main / Neutral bucket"
    S.Notify()
    return false
  end
  S.MarketBucket = bucket
  S.MarketID = S.MarketPrefix .. "|" .. bucket
  local markets = MarketSyncForeverScanDB.markets
  markets[S.MarketID] = markets[S.MarketID] or {records = {}, watched = {}, completedWatchScans = 0}
  S.Store = markets[S.MarketID]
  S.Notify()
  return true
end

function S.Notify()
  if not S.BatchCapture and S.RefreshWindow then S.RefreshWindow() end
end

function S.RememberKey(key)
  if not S.Store then return nil end
  local copy = S.CopyKey(key)
  local id = copy and S.KeyID(copy)
  if not id then return nil end
  local record = S.Store.records[id]
  if not record then
    record = {key = copy, keyID = id, history = {}}
    S.Store.records[id] = record
  end
  local info = C_AuctionHouse.GetItemKeyInfo(copy)
  if info then
    record.name, record.icon = info.itemName, info.iconFileID
    record.isCommodity, record.quality = info.isCommodity, info.quality
  end
  return record
end

function S.SaveSnapshot(key, snapshot)
  local record = S.RememberKey(key)
  if not record then return nil end
  snapshot.seenAt = time()
  snapshot.marketID = S.MarketID
  snapshot.clientVersion, snapshot.clientBuild = GetBuildInfo()
  snapshot.clientBuild = tostring(snapshot.clientBuild)
  if snapshot.source == "native-commodity-search" then record.isCommodity = true end
  if snapshot.source == "native-item-search" then record.isCommodity = false end
  record.latest = snapshot
  if snapshot.complete then
    record.lastComplete = snapshot
    local history = record.history
    -- One observation per 30-minute bucket; preserve observation time within the bucket.
    local bucket = math.floor(snapshot.seenAt / 1800)
    local point = {
      bucket = bucket, seenAt = snapshot.seenAt, minUnitPrice = snapshot.minUnitPrice,
      available = snapshot.available, pricedQuantity = snapshot.pricedQuantity,
      source = snapshot.source,
    }
    if #history > 0 and history[#history].bucket == bucket then
      history[#history] = point
    else
      table.insert(history, point)
      if #history > 96 then table.remove(history, 1) end
    end
  end
  S.Notify()
  return record
end

function S.ToggleWatch(id)
  if not S.Store or not S.Store.records[id] or S.Active then return false end
  if S.Store.watched[id] then
    S.Store.watched[id] = nil
  else
    local count = 0
    for _ in pairs(S.Store.watched) do count = count + 1 end
    if count >= 50 then S.Status = "Watch list limit: 50 native item keys"; S.Notify(); return false end
    S.Store.watched[id] = true
  end
  S.Notify()
  return true
end

-- Explicit provider boundary for a later MarketSync integration. No legacy DB or wire writes.
S.Provider = {
  name = "forever-native", schema = 1,
  GetSnapshot = function(key)
    local id = S.KeyID(key)
    local record = S.Store and id and S.Store.records[id]
    local function copy(value)
      if type(value) ~= "table" then return value end
      local result = {}
      for k, v in pairs(value) do result[k] = copy(v) end
      return result
    end
    return record and record.lastComplete and copy(record.lastComplete) or nil
  end,
  GetMarketID = function() return S.MarketID end,
}
