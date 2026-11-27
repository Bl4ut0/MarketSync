// Tests for the shared selected shopping list (MarketSync/Favorites.lua).
// The breakout panel and the legacy Scan page both read and set it.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

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

run(`MarketSync = {}; MarketSyncDB = {}`);
run(fs.readFileSync(path.join(__dirname, '../MarketSync/Favorites.lua'), 'utf8'));
run(`F = MarketSync.Favorites; changes = 0; F.RegisterCallback(function() changes = changes + 1 end)`);

test('The default list is selected until another is picked', `
  assert(F.GetSelectedList() == "Favorites")
`);

test('Picking a list saves it and notifies both pages', `
  assert(F.CreateList("Herbs"))
  local before = changes
  assert(F.SetSelectedList("Herbs") == true)
  assert(F.GetSelectedList() == "Herbs" and MarketSyncDB.SelectedShoppingList == "Herbs")
  assert(changes == before + 1, "change callback fired")
  assert(F.SetSelectedList("No Such List") == false and F.GetSelectedList() == "Herbs")
`);

test('Renaming the selected list keeps it selected', `
  assert(F.RenameList("Herbs", "Flowers"))
  assert(F.GetSelectedList() == "Flowers")
`);

test('Deleting the selected list falls back to Favorites', `
  assert(F.DeleteList("Flowers"))
  assert(F.GetSelectedList() == "Favorites")
`);

console.log(`All ${passed} selected-list tests passed.`);
