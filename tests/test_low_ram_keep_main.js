// Low RAM mode with "Keep Main tab source loaded" (MarketSync/UI_Browse.lua):
// only the Main tab's source is built eagerly; everything else stays on demand.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const source = fs.readFileSync(path.join(__dirname, '../MarketSync/UI_Browse.lua'), 'utf8').replace(/\r\n/g, '\n');
function extract(name) {
  const start = source.indexOf('function MarketSync.' + name);
  if (start < 0) throw new Error(name + ' not found');
  return source.slice(start, source.indexOf('\nend\n', start) + '\nend\n'.length);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let passed = 0;
function run(chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
}
function test(name, chunk) {
  try { run(chunk); } catch (e) { console.error('FAIL ' + name + ': ' + e.message); process.exit(1); }
  console.log('PASS ' + name);
  passed++;
}

run('MarketSync = {}; MarketSyncDB = {}\n' + extract('LowRamKeptSource') + extract('IsLowRamDeferred'));

test('Low RAM off: nothing is deferred', `
  MarketSyncDB.LowRamMode = false
  assert(MarketSync.LowRamKeptSource() == nil)
  assert(not MarketSync.IsLowRamDeferred("personal") and not MarketSync.IsLowRamDeferred("neutral"))
`);

test('Low RAM on without the option: everything is on demand', `
  MarketSyncDB.LowRamMode, MarketSyncDB.LowRamKeepMain = true, false
  assert(MarketSync.LowRamKeptSource() == nil)
  for _, s in ipairs({ "personal", "guild", "neutral" }) do assert(MarketSync.IsLowRamDeferred(s), s) end
`);

test('Keeping a Personal Main tab loads only Personal', `
  MarketSyncDB.LowRamKeepMain, MarketSyncDB.MainSource = true, "personal"
  assert(MarketSync.LowRamKeptSource() == "personal")
  assert(not MarketSync.IsLowRamDeferred("personal"))
  assert(MarketSync.IsLowRamDeferred("guild") and MarketSync.IsLowRamDeferred("neutral"))
`);

test('Keeping a Guild Main tab loads only Guild', `
  MarketSyncDB.MainSource = "guild"
  assert(not MarketSync.IsLowRamDeferred("guild"))
  assert(MarketSync.IsLowRamDeferred("personal") and MarketSync.IsLowRamDeferred("neutral"))
`);

test('Keeping Latest builds Personal and Guild to merge it; Neutral stays on demand', `
  MarketSyncDB.MainSource = "latest"
  assert(MarketSync.LowRamKeptSource() == "latest")
  assert(not MarketSync.IsLowRamDeferred("personal") and not MarketSync.IsLowRamDeferred("guild"))
  assert(MarketSync.IsLowRamDeferred("neutral"))
  MarketSyncDB.MainSource = nil
  assert(MarketSync.LowRamKeptSource() == "latest", "Latest is the default Main source")
`);

console.log(`All ${passed} Low RAM keep-Main tests passed.`);
