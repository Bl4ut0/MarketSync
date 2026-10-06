const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const source = fs.readFileSync(path.join(__dirname, '../MarketSync/LegacyScanner.lua'), 'utf8');

function run(chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
run(`
  _G = _G or {}
  timers = {}
  C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
  function RunTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
  end
  function time() return 1770000000 end
  function GetItemInfo(id) return id == 100 and "Test Ore" or nil end
  queries = {}
  function CanSendAuctionQuery() return true, true end
  function QueryAuctionItems(name, _, _, page, _, _, all, exact)
    queries[#queries + 1] = { name = name, page = page, all = all, exact = exact }
  end
  results = {}
  resultTotal = 0
  function GetNumAuctionItems() return #results, resultTotal end
  function GetAuctionItemInfo(_, index)
    local r = results[index]
    return r.name, 123, r.count, 2, true, 10, nil, 0, 0,
      r.buyout, 0, nil, nil, nil, nil, nil, r.id
  end
  function GetAuctionItemLink(_, index) return results[index].link end
  AuctionFrame = { IsShown = function() return true end }
  function CreateFrame()
    LegacyFrame = {
      RegisterEvent = function() end,
      SetScript = function(self, _, fn) self.script = fn end,
    }
    return LegacyFrame
  end
  recorded = {}
  MarketSyncDB = { ItemInfoCache = {} }
  MarketSync = {
    Scanner = {
      Active = false, Generation = 0, RecentResults = {}, Progress = {},
      Notify = function() end,
      Cancel = function(reason)
        local s = MarketSync.Scanner
        s.Active = false
        s.Generation = s.Generation + 1
        s.Status = reason
      end,
      ToItemKey = function(item)
        local id = type(item) == "table" and item.itemID or tonumber(item)
        return id and { itemID = id } or nil
      end,
      GetFullScanCooldownRemaining = function() return 0 end,
    },
    GetItemInfo = GetItemInfo,
    GetRealmDB = function() return MarketSyncDB end,
    RecordScanObservation = function(key, price, qty, _, full)
      recorded[#recorded + 1] = { key = key, price = price, qty = qty, full = full }
    end,
  }
`);
run(source);
run(`
  assert(MarketSync.Scanner.IsLegacyAH == true)
  assert(MarketSync.Scanner.IsAvailable() == true)
  assert(MarketSync.Scanner.StartFullScan() == true)
  assert(queries[1].all == true and queries[1].name == "")
  results = {
    {id = 100, name = "Test Ore", count = 2, buyout = 200, link = "item:100"},
    {id = 100, name = "Test Ore", count = 3, buyout = 240, link = "item:100"},
  }
  resultTotal = 2
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  RunTimers()
  assert(#recorded == 1 and recorded[1].price == 80 and recorded[1].qty == 5)
  assert(recorded[1].full == true and MarketSync.Scanner.Active == false)
  assert(MarketSyncDB.LastFullScanAt == 1770000000)
  recorded = {}
  assert(MarketSync.Scanner.StartScan({100}, "Target") == true)
  assert(queries[2].name == "Test Ore" and queries[2].all == false)
  results = {{id = 100, name = "Test Ore", count = 1, buyout = 77, link = "item:100"}}
  resultTotal = 1
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  RunTimers()
  assert(#recorded == 1 and recorded[1].price == 77 and recorded[1].full == false)
  assert(MarketSync.Scanner.Active == false)
  recorded = {}
  assert(MarketSync.Scanner.StartFullScan() == true)
  results = {
    {id = 100, name = "Test Ore", count = 1, buyout = 90,
      link = "|cff1eff00|Hitem:100:0:0:0:0:0:-12:0|h[Test Ore of Power]|h|r"},
    {id = 100, name = "Test Ore", count = 2, buyout = 120,
      link = "|cff1eff00|Hitem:100:0:0:0:0:0:-13:0|h[Test Ore of Speed]|h|r"},
  }
  resultTotal = 2
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  RunTimers()
  assert(#recorded == 2, "suffix variants must be stored separately")
  assert(recorded[1].key.itemSuffix == -12 and recorded[2].key.itemSuffix == -13)
  observations = {}
  MarketSync.ObservationAPI = { v1 = {
    HasListeners = function() return true end,
    NewScanID = function() return "neutral-scan" end,
    Emit = function(event) observations[#observations + 1] = event end,
  }}
  MarketSync.IsNeutralAHOpen = true
  MarketSync.BeginNeutralFullScan = function() neutralStarted = true end
  MarketSync.CompleteNeutralFullScan = function() neutralCompleted = true end
  local mainScanTime = MarketSyncDB.FullScanTime
  recorded = {}
  assert(MarketSync.Scanner.StartFullScan() == true)
  assert(neutralStarted == true and observations[1].scope == "neutral")
  results = {{id = 100, name = "Test Ore", count = 1, buyout = 90, link = "item:100"}}
  resultTotal = 1
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  RunTimers()
  assert(neutralCompleted == true and observations[#observations].scope == "neutral")
  assert(MarketSyncDB.FullScanTime == mainScanTime, "neutral scan must not advance main freshness")
  MarketSync.IsNeutralAHOpen = false
  observations = {}
  recorded = {}
  assert(MarketSync.Scanner.StartScan({100}, "Paged Target") == true)
  results = {
    {id = 100, name = "Test Ore", count = 2, buyout = 200, link = "item:100"},
    {id = 100, name = "Test Ore", count = 1, buyout = 0, link = "item:100"},
  }
  resultTotal = 51
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  assert(queries[#queries].page == 1, "target scan must request later result pages")
  assert(#recorded == 0, "target scan must wait for every page before saving")
  results = {{id = 100, name = "Test Ore", count = 3, buyout = 240, link = "item:100"}}
  resultTotal = 51
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  RunTimers()
  assert(#recorded == 1 and recorded[1].price == 80 and recorded[1].qty == 5,
    "paged target scan must aggregate rows and ignore auctions without buyout: " ..
    tostring(#recorded) .. " " .. tostring(recorded[1] and recorded[1].price) ..
    " " .. tostring(recorded[1] and recorded[1].qty))
`);
console.log('PASS legacy full, targeted, and neutral scan transport');
