// Tests for the Latest index merge (MarketSync/LatestIndex.lua, phase 2a)
const fs = require('fs');
const path = require('path');
const candidateDeps = [
  path.resolve(__dirname, '../node_modules'),
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
];
const deps = candidateDeps.find(p => fs.existsSync(p)) || candidateDeps[0];
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

const source = fs.readFileSync(path.join(__dirname, '../MarketSync/LatestIndex.lua'), 'utf8');

let passed = 0;
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_dostring(L, to_luastring(source)) !== 0) {
  throw new Error('LatestIndex.lua failed to load: ' + to_jsstring(lua.lua_tostring(L, -1)));
}

function run(name, body) {
  const code = `
    local function E(price, exactTime, age) return { price = price, exactTime = exactTime, age = age } end
    ${body}
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== 0) {
    console.error(`FAIL ${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
    process.exit(1);
  }
  console.log(`PASS ${name}`);
  passed++;
}

run('guild entry with a newer exact time replaces the personal entry', `
  local p = { k = E(100, 1000) }
  local g = { k = E(120, 2000) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.k.price == 120, "newer guild entry should win")
`);

run('personal entry with a newer exact time is kept', `
  local p = { k = E(100, 3000) }
  local g = { k = E(120, 2000) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.k.price == 100, "newer personal entry should win")
`);

run('a tie on exact time keeps the personal entry', `
  local p = { k = E(100, 2000) }
  local g = { k = E(120, 2000) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.k.price == 100, "tie should keep personal")
`);

run('an entry with an exact time beats one without', `
  local p = { k = E(100, nil, 0.5) }
  local g = { k = E(120, 1500) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.k.price == 120, "exact time should beat age-only")
`);

run('without exact times the smaller age is newer', `
  local p = { k = E(100, nil, 3) }
  local g = { k = E(120, nil, 1) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.k.price == 120, "smaller age should win")
`);

run('keys present in only one index are kept', `
  local p = { a = E(10, 1) }
  local g = { b = E(20, 2) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.a.price == 10 and m.b.price == 20, "both keys should be present")
`);

run('entries with no price are skipped', `
  local p = { a = E(nil, 5), b = E(10, 1) }
  local g = { a = E(0, 9), c = E(30, 2) }
  local m = MarketSync.MergeLatestIndex(p, g)
  assert(m.a == nil, "entry without a price should be skipped")
  assert(m.b.price == 10 and m.c.price == 30, "priced entries should remain")
`);

run('missing indexes give an empty result, not an error', `
  local m = MarketSync.MergeLatestIndex(nil, nil)
  assert(next(m) == nil, "no indexes should give an empty table")
  local m2 = MarketSync.MergeLatestIndex({ a = E(5, 1) }, nil)
  assert(m2.a.price == 5, "personal only should pass through")
`);

run('the inputs are not modified', `
  local p = { k = E(100, 1000) }
  local g = { k = E(120, 2000) }
  MarketSync.MergeLatestIndex(p, g)
  assert(p.k.price == 100 and g.k.price == 120, "inputs should be unchanged")
`);

console.log(`\n${passed} passed`);
