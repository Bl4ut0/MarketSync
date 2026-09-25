const fs = require('fs');
const path = require('path');
const candidates = [path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
  'C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/ItemRack-Forever/node_modules'];
const deps = candidates.find(p => fs.existsSync(p)) || candidates[0];
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

const source = fs.readFileSync(path.resolve(__dirname, '../MarketSync/Export.lua'), 'utf8');
luaparse.parse(source, { luaVersion: '5.1' });
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const fixture = `
MarketSync = {}
time = function() return 1800000000 end
realm = {
  PersonalData = { ["p:4471:12"] = { m = 900, d = 20500, observedAt = 1800000000,
    latestBucket = 984020, h = { ["20500"] = "20:p0:5" }, vh = { ["20500"] = "20:p0:5" } } },
  NeutralData = { ["4472"] = { m = 1800, d = 20500, q = 2, vm = 1800, vd = 20500,
    vq = 2, h = { ["20500"] = 1900 }, l = { ["20500"] = 1700 } } },
}
MarketSync.GetRealmDB = function() return realm end
MarketSync.Provider = { GetMarketID = function() return "forever|1|Test Realm|Alliance|main" end }
C_Timer = { pending = {}, After = function(_, fn) table.insert(C_Timer.pending, fn) end }
`;
function run(script) {
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
}
run(fixture + source);
run(`
local before = realm.PersonalData["p:4471:12"].m
local parts, count, failure
assert(MarketSync.BuildDatabaseExportParts(function(p, e, c) parts, failure, count = p, e, c end))
while #C_Timer.pending > 0 do table.remove(C_Timer.pending, 1)() end
assert(not failure and #parts == 1 and count == 6)
assert(parts[1]:find("MSX\\t1\\t1\\t1\\tforever%%7C1%%7CTest%%20Realm", 1))
assert(parts[1]:find("I\\tM\\tp%%3A4471%%3A12\\t900\\t20500", 1))
assert(parts[1]:find("H\\tM\\tp%%3A4471%%3A12\\t20500\\th\\t20%%3Ap0%%3A5", 1))
assert(parts[1]:find("I\\tN\\t4472\\t1800\\t20500", 1))
assert(realm.PersonalData["p:4471:12"].m == before)
for i = 1, 600 do realm.PersonalData[tostring(i)] = { m = i, d = 20500 } end
assert(MarketSync.BuildDatabaseExportParts(function(p, e, c) parts, failure, count = p, e, c end))
while #C_Timer.pending > 0 do table.remove(C_Timer.pending, 1)() end
assert(not failure and #parts > 1)
for i, part in ipairs(parts) do
  assert(part:find("MSX\\t1\\t" .. i .. "\\t" .. #parts .. "\\t", 1))
  assert(#part < 12500, "part too large for comfortable copy")
end
`);
console.log('PASS read-only, versioned, chunked database export');
