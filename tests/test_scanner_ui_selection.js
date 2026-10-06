const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const source = fs.readFileSync(path.join(__dirname, '../MarketSync/UI_AHScanner.lua'), 'utf8');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
run('MarketSync = {}');
run(source);
run(`
  local selected = MarketSync.GetCheckedScannerLists(
    { Favorites = true, Consumables = false, ['Trade Goods'] = true },
    { 'Favorites', 'Consumables', 'Trade Goods' })
  assert(#selected == 2 and selected[1] == 'Favorites' and selected[2] == 'Trade Goods')
  assert(#MarketSync.GetCheckedScannerLists({}, { 'Favorites' }) == 0)
`);
assert(source.includes('MarketSync.Scanner.ScanMultipleLists(activeNames)'));
assert(!source.includes('MarketSync.Scanner.ScanWatched()'));
console.log('PASS scanner toolbar uses only checked lists and has no duplicate watched action');
