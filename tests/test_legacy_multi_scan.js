// Tests for the legacy multi-item price scan (MarketSync/LegacyScanner.lua, S.StartMultiScan).
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const source = fs.readFileSync(path.join(__dirname, '../MarketSync/LegacyScanner.lua'), 'utf8');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let passed = 0;
function run(chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
function test(name, chunk) {
  try { run(chunk); } catch (e) { console.error('FAIL ' + name + ': ' + e.message); process.exit(1); }
  console.log('PASS ' + name);
  passed++;
}

run(`
  timers = {}
  C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
  -- Runs queued timers except the 15 s response timeouts, which tests fire on purpose.
  function RunTimers()
    for _ = 1, 20 do
      local pending = timers
      timers = {}
      local ran = false
      for _, t in ipairs(pending) do
        if t.delay < 15 then t.fn(); ran = true else timers[#timers + 1] = t end
      end
      if not ran then return end
    end
  end
  function FireTimeouts()
    local pending = timers
    timers = {}
    for _, t in ipairs(pending) do if t.delay >= 15 then t.fn() else timers[#timers + 1] = t end end
  end
  function time() return 1770000000 end
  function GetTime() return 100 end
  itemNames = { [100] = "Test Ore", [300] = "Test Herb" }
  function GetItemInfo(id) return itemNames[id] end
  queries = {}
  function CanSendAuctionQuery() return true, true end
  function QueryAuctionItems(name, _, _, page, _, _, all, exact)
    queries[#queries + 1] = { name = name, page = page, all = all, exact = exact }
  end
  results, resultTotal = {}, 0
  function GetNumAuctionItems() return #results, resultTotal end
  function GetAuctionItemInfo(_, index)
    local r = results[index]
    return r.name, 123, r.count, 2, true, 10, nil, 0, 0,
      r.buyout, 0, nil, nil, (r.owner ~= false) and (r.owner or "Seller") or nil, nil, r.sold or 0, r.id
  end
  function GetAuctionItemLink(_, index) local r = results[index]; if not r.noLink then return r.link end end
  function UnitName() return "TestPlayer" end
  AuctionFrame = { IsShown = function() return true end }
  function CreateFrame()
    LegacyFrame = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.script = fn end }
    return LegacyFrame
  end
  function Respond(rows, total)
    results, resultTotal = rows, total or #rows
    LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
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
        return id and { itemID = id, itemSuffix = type(item) == "table" and item.itemSuffix or 0 } or nil
      end,
    },
    GetItemInfo = GetItemInfo,
    GetRealmDB = function() return MarketSyncDB end,
    GetItemPriceAndScanInfo = function(key) if key == "100" then return { price = 50 } end end,
    RecordScanObservation = function(key, price, qty, isCommodity, full)
      recorded[#recorded + 1] = { key = key, price = price, qty = qty, commodity = isCommodity, full = full }
    end,
  }
`);
run(source);

test('Each item is searched by its exact name and gets its own live listings', `
  local S = MarketSync.Scanner
  queries, recorded = {}, {}
  assert(S.StartMultiScan({ 100, 300 }) == true)
  assert(#queries == 1 and queries[1].name == "Test Ore" and queries[1].exact == true, "exact-name query")
  Respond({
    { id = 100, name = "Test Ore", count = 5, buyout = 500, link = "item:100" },
    { id = 100, name = "Test Ore", count = 5, buyout = 500, link = "item:100" },
    { id = 100, name = "Test Ore", count = 1, buyout = 80, link = "item:100", owner = "TestPlayer" },
    { id = 999, name = "Test Ore Bag", count = 1, buyout = 1, link = "item:999" },
    { id = 100, name = "Test Ore", count = 2, buyout = 0, link = "item:100" },
  })
  RunTimers()
  local multi = S.GetMultiScan()
  local ore = multi.items[1]
  assert(ore.state == "done", "ore state " .. tostring(ore.state))
  assert(ore.minUnit == 80 and ore.available == 11 and ore.auctions == 3, "summary")
  assert(#ore.listings == 2, "identical stacks grouped, other items and bid-only ignored")
  assert(ore.listings[1].mine == true and ore.listings[1].unitPrice == 80, "cheapest first, flagged as own")
  assert(ore.listings[2].auctions == 2 and ore.listings[2].available == 10)
  assert(ore.previousPrice == 50, "market price before the scan is kept for comparison")
  assert(#recorded == 1 and recorded[1].price == 80 and recorded[1].qty == 11 and recorded[1].commodity == false)
  assert(queries[2].name == "Test Herb", "moves on to the next item")
  Respond({})
  RunTimers()
  assert(queries[3].name == "Test Herb" and queries[3].exact == false, "empty exact search retried by name")
  Respond({})
  RunTimers()
  assert(multi.items[2].state == "empty")
  assert(multi.state == "complete" and S.Active == false)
  assert(S.Status:find("1 priced") and S.Status:find("1 with no auctions"), S.Status)
`);

test('Pages through an item with more than 50 auctions', `
  local S = MarketSync.Scanner
  queries, recorded = {}, {}
  assert(S.StartMultiScan({ 100 }) == true)
  local page = {}
  for i = 1, 50 do page[i] = { id = 100, name = "Test Ore", count = 1, buyout = 100 + i, link = "item:100" } end
  Respond(page, 60)
  RunTimers()
  assert(queries[2].page == 1 and queries[2].name == "Test Ore", "second page requested")
  Respond({ { id = 100, name = "Test Ore", count = 1, buyout = 90, link = "item:100" } }, 60)
  RunTimers()
  local ore = S.GetMultiScan().items[1]
  assert(ore.minUnit == 90 and ore.auctions == 51, "both pages counted")
`);

test('A timed-out item is retried once, then skipped without cancelling the list', `
  local S = MarketSync.Scanner
  queries = {}
  assert(S.StartMultiScan({ 100, 300 }) == true)
  FireTimeouts()
  RunTimers()
  assert(#queries == 2 and queries[2].name == "Test Ore", "retried once")
  FireTimeouts()
  RunTimers()
  local multi = S.GetMultiScan()
  assert(multi.items[1].state == "failed" and multi.items[1].reason:find("timed out"))
  assert(S.Active == true and queries[3].name == "Test Herb", "scan continues with the next item")
  Respond({ { id = 300, name = "Test Herb", count = 1, buyout = 40, link = "item:300" } })
  RunTimers()
  assert(multi.items[2].state == "done" and multi.state == "complete")
  assert(S.Status:find("1 failed"), S.Status)
`);

test('Items whose names have not loaded are retried at the end, then reported as skipped', `
  local S = MarketSync.Scanner
  queries = {}
  assert(S.StartMultiScan({ 400, 100 }) == true)
  local multi = S.GetMultiScan()
  RunTimers()
  assert(queries[1].name == "Test Ore", "unknown item does not block the list")
  itemNames[400] = "Late Item"
  Respond({})
  RunTimers()
  Respond({})
  RunTimers()
  assert(queries[3].name == "Late Item", "skipped item retried once its name loaded")
  Respond({})
  RunTimers()
  Respond({})
  RunTimers()
  assert(multi.items[1].state == "empty" and multi.state == "complete")
  itemNames[400] = nil
`);

test('Stopping keeps finished items and returns the current one to the queue', `
  local S = MarketSync.Scanner
  assert(S.StartMultiScan({ 100, 300 }) == true)
  Respond({ { id = 100, name = "Test Ore", count = 1, buyout = 70, link = "item:100" } })
  RunTimers()
  local multi = S.GetMultiScan()
  assert(multi.items[2].state == "scanning")
  S.Cancel("Stopped")
  assert(multi.state == "stopped" and multi.items[1].state == "done" and multi.items[1].minUnit == 70)
  assert(multi.items[2].state == "queued")
`);

test('Random-suffix variants are saved separately but listed together', `
  local S = MarketSync.Scanner
  recorded = {}
  assert(S.StartMultiScan({ 100 }) == true)
  Respond({
    { id = 100, name = "Test Ore", count = 1, buyout = 90, link = "|cff1eff00|Hitem:100:0:0:0:0:0:-12:0|h[Test Ore of Power]|h|r" },
    { id = 100, name = "Test Ore", count = 1, buyout = 60, link = "|cff1eff00|Hitem:100:0:0:0:0:0:-13:0|h[Test Ore of Speed]|h|r" },
  })
  RunTimers()
  assert(#recorded == 2, "one history entry per variant")
  local ore = S.GetMultiScan().items[1]
  assert(#ore.listings == 2 and ore.minUnit == 60)
`);

test('A page is read only once owners and links have loaded', `
  local S = MarketSync.Scanner
  queries, recorded = {}, {}
  assert(S.StartMultiScan({ 100 }) == true)
  local partial = {
    { id = 100, name = "Test Ore", count = 1, buyout = 50, link = "item:100", owner = false },
    { id = 100, name = "Test Ore", count = 1, buyout = 60, link = "item:100", noLink = true },
  }
  results, resultTotal = partial, 2
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  local ore = S.GetMultiScan().items[1]
  assert(ore.state == "scanning", "partial page is not read")
  Respond({
    { id = 100, name = "Test Ore", count = 1, buyout = 50, link = "item:100", owner = "TestPlayer" },
    { id = 100, name = "Test Ore", count = 1, buyout = 60, link = "item:100" },
  })
  RunTimers()
  assert(ore.state == "done" and ore.listings[1].mine == true and ore.auctions == 2, "read once complete")
`);

test('A page whose owners never load is read after the grace period', `
  local S = MarketSync.Scanner
  assert(S.StartMultiScan({ 100 }) == true)
  results, resultTotal = { { id = 100, name = "Test Ore", count = 1, buyout = 50, link = "item:100", owner = false } }, 1
  LegacyFrame.script(LegacyFrame, "AUCTION_ITEM_LIST_UPDATE")
  local ore = S.GetMultiScan().items[1]
  assert(ore.state == "scanning")
  RunTimers()
  assert(ore.state == "done" and ore.minUnit == 50)
`);

test('Suffix variants are searched by name containing the base name', `
  local S = MarketSync.Scanner
  queries = {}
  assert(S.StartMultiScan({ { itemID = 100, itemSuffix = -12 } }) == true)
  assert(queries[1].exact == false)
  Respond({
    { id = 100, name = "Test Ore of Power", count = 1, buyout = 90, link = "|cff1eff00|Hitem:100:0:0:0:0:0:-12:0|h[Test Ore of Power]|h|r" },
    { id = 100, name = "Test Ore of Speed", count = 1, buyout = 60, link = "|cff1eff00|Hitem:100:0:0:0:0:0:-13:0|h[Test Ore of Speed]|h|r" },
  })
  RunTimers()
  local ore = S.GetMultiScan().items[1]
  assert(ore.minUnit == 90 and #ore.listings == 1, "only the queued variant")
`);

test('Nothing to scan and a closed Auction House are reported', `
  local S = MarketSync.Scanner
  assert(S.StartMultiScan({}) == false and S.Status == "Add items to scan first.")
  AuctionFrame.IsShown = function() return false end
  assert(S.StartMultiScan({ 100 }) == false and S.Status:find("Open the Auction House"))
  AuctionFrame.IsShown = function() return true end
`);

console.log(`All ${passed} multi-scan tests passed.`);
