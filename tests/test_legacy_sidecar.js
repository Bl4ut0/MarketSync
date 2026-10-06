const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
run(`
  _G = _G or {}
  MarketSync = {
    Scanner = { IsLegacyAH = true },
    GetItemInfo = function(id) return id == 100 and 'Test Ore' or nil end,
    OpenLegacySearch = function(name) lastRoute = 'marketsync'; lastName = name; return true end,
  }
  MarketSyncDB = { UseAuctionatorScanner = false }
  AuctionFrame = {}
  selected = 4
  function PanelTemplates_GetSelectedTab() return selected end
  BrowseName = { SetText = function(_, value) lastName = value end }
  BrowseSearchButton = { Click = function() lastRoute = 'native' end }
`);
run(fs.readFileSync(path.join(__dirname, '../MarketSync/UI_AHSidecar.lua'), 'utf8'));
run(`
  assert(MarketSync.SearchInAuctionHouse(100) == true)
  assert(lastRoute == 'marketsync' and lastName == 'Test Ore')
  selected = 1
  assert(MarketSync.SearchInAuctionHouse('Test Ore') == true)
  assert(lastRoute == 'native')
  Auctionator = { API = { v1 = {
    MultiSearchExact = function(callerID, terms)
      assert(callerID == 'MarketSync' and terms[1] == 'Test Ore')
      lastRoute = 'auctionator'
    end,
  } } }
  MarketSyncDB.UseAuctionatorScanner = true
  assert(MarketSync.SearchInAuctionHouse('Test Ore') == true)
  assert(lastRoute == 'auctionator')
`);
console.log('PASS classic sidecar routes searches to native, MarketSync, and Auctionator pages');
