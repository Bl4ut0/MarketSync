const assert = require('assert');
const fs = require('fs');
const path = require('path');
const candidates = [
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
  'C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/ItemRack-Forever/node_modules',
];
const deps = candidates.find(candidate => fs.existsSync(path.join(candidate, 'luaparse'))) || candidates[0];
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring } = require(path.join(deps, 'fengari'));

const addon = path.resolve(__dirname, '../MarketSync');
for (const name of ['ObservationAPI.lua', 'Scanner.lua', 'Chat.lua', 'Core.lua', 'Sync.lua']) {
  luaparse.parse(fs.readFileSync(path.join(addon, name), 'utf8'), { luaVersion: '5.1' });
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const source = fs.readFileSync(path.join(addon, 'ObservationAPI.lua'), 'utf8');
const script = `
time = function() return 1800000000 end
MarketSync = { Debug = function() end }
${source}
local api = MarketSync.ObservationAPI.v1
local received = {}
local function listener(event)
  received[#received + 1] = event
  event.event = "mutated"
end
local function other(event)
  received[#received + 1] = event
end
assert(api.Register(listener))
assert(api.Register(other))
assert(not api.Register("bad"))
local first = api.NewScanID("local")
local second = api.NewScanID("local")
assert(first ~= second)
api.Emit({ event = "observation", scanId = first, quantity = 3 })
assert(#received == 2)
assert(received[1] ~= received[2])
assert(received[2].event == "observation" or received[1].event == "observation")
api.Unregister(listener)
api.Emit({ event = "finish", scanId = first })
assert(#received == 3)
`;
if (lauxlib.luaL_dostring(L, to_luastring(script)) !== lua.LUA_OK) {
  throw new Error(lua.lua_tojsstring(L, -1));
}
assert.ok(true);
console.log('PASS observation API and Lua syntax');
