// Tests for the Analytics history filter (MarketSync/Processing.lua, "Analytics history filter").
// Loads only that section, so the test does not need the whole addon.
const fs = require('fs');
const path = require('path');
const candidateDeps = [
  path.resolve(__dirname, '../node_modules'),
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
];
const deps = candidateDeps.find(p => fs.existsSync(p)) || candidateDeps[0];
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

// Windows checkouts use CRLF; the section boundaries below match LF only.
const source = fs.readFileSync(path.join(__dirname, '../MarketSync/Processing.lua'), 'utf8').replace(/\r\n/g, '\n');
const start = source.indexOf('local ANALYTICS_DAYS_BEFORE_MONTH');
const fnStart = source.indexOf('function MarketSync.FilterAnalyticsHistory');
if (start < 0 || fnStart < 0) throw new Error('Analytics filter section not found in Processing.lua');
const fnEnd = source.indexOf('\nend\n', fnStart) + '\nend\n'.length;
const section = source.slice(start, fnEnd);

let passed = 0;
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const prelude = `
  MarketSync = {}
  MarketSync.ScanDayToTimestamp = function(d) return d * 86400 end
  MarketSync.GetCurrentBucket = function() return 0 end
  MarketSync.BucketOffsetToTime = function(o)
    return string.format("%d:%s", math.floor(o / 2), (o % 2 == 0) and "00" or "30")
  end
`;
if (lauxlib.luaL_dostring(L, to_luastring(prelude + section)) !== 0) {
  throw new Error('Analytics filter section failed to load: ' + to_jsstring(lua.lua_tostring(L, -1)));
}

function run(name, body) {
  const code = `
    local function Row(day, offset, price, granular)
      return { day = day, bucketOffset = offset, price = price, isGranular = granular and true or false }
    end
    ${body}
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== 0) {
    console.error(`FAIL ${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
    process.exit(1);
  }
  console.log(`PASS ${name}`);
  passed++;
}

// Expected unix days come from JS Date so the Lua civil-date math is checked against a known source.
const unixDay = (y, m, d) => Date.UTC(y, m - 1, d) / 86400000;
const today = unixDay(2026, 11, 25);

run('ParseAnalyticsDate matches the JS calendar', `
  assert(MarketSync.ParseAnalyticsDate("1970-01-01") == 0, "epoch")
  assert(MarketSync.ParseAnalyticsDate("2026-11-25") == ${today}, "2026-11-25")
  assert(MarketSync.ParseAnalyticsDate("2024-02-29") == ${unixDay(2024, 2, 29)}, "leap day")
`);

run('ParseAnalyticsDate rejects impossible or malformed dates', `
  assert(MarketSync.ParseAnalyticsDate("2026-02-30") == nil, "Feb 30")
  assert(MarketSync.ParseAnalyticsDate("2026-02-29") == nil, "non-leap Feb 29")
  assert(MarketSync.ParseAnalyticsDate("2026-13-01") == nil, "month 13")
  assert(MarketSync.ParseAnalyticsDate("2026-1-01") == nil, "short month")
  assert(MarketSync.ParseAnalyticsDate("") == nil, "empty")
`);

run('ParseAnalyticsTime maps HH:MM to half-hour buckets', `
  assert(MarketSync.ParseAnalyticsTime("00:00") == 0, "midnight")
  assert(MarketSync.ParseAnalyticsTime("17:30") == 35, "17:30")
  assert(MarketSync.ParseAnalyticsTime("9:05") == 18, "9:05 floors to 9:00")
  assert(MarketSync.ParseAnalyticsTime("23:59") == 47, "last slot")
  assert(MarketSync.ParseAnalyticsTime("24:00") == nil, "hour 24")
  assert(MarketSync.ParseAnalyticsTime("nope") == nil, "garbage")
`);

run('week index is Monday based', `
  assert(MarketSync.AnalyticsWeekIndex(3) == MarketSync.AnalyticsWeekIndex(0), "Sunday 1970-01-04 shares a week with Thursday")
  assert(MarketSync.AnalyticsWeekIndex(4) == MarketSync.AnalyticsWeekIndex(3) + 1, "Monday starts the next week")
  assert(MarketSync.AnalyticsWeekStartDay(MarketSync.AnalyticsWeekIndex(4)) == 4, "week start is that Monday")
`);

run('events mode keeps the newest N observations in order', `
  local h = { Row(3,1,10,true), Row(3,0,11,true), Row(2,5,12,true) }
  local v = MarketSync.FilterAnalyticsHistory(h, { mode = "events", count = 2 })
  assert(#v == 2 and v[1] == h[1] and v[2] == h[2], "first two rows")
  assert(#MarketSync.FilterAnalyticsHistory(h, { mode = "events" }) == 3, "nil count keeps all")
`);

run('date mode is inclusive on both ends and open when nil', `
  local h = { Row(${today}, 1, 1, true), Row(${today - 1}, 1, 2, true), Row(${today - 5}, 1, 3, true) }
  assert(#MarketSync.FilterAnalyticsHistory(h, { mode = "date", fromDay = ${today - 1}, toDay = ${today} }) == 2, "inclusive range")
  assert(#MarketSync.FilterAnalyticsHistory(h, { mode = "date", fromDay = ${today - 1} }) == 2, "open end")
  assert(#MarketSync.FilterAnalyticsHistory(h, { mode = "date" }) == 3, "no bounds keeps all")
`);

run('week mode returns only that Monday-to-Sunday week', `
  local monday = ${unixDay(2026, 11, 23)}
  local h = { Row(monday + 6, 1, 1, true), Row(monday, 1, 2, true), Row(monday - 1, 1, 3, true) }
  local v = MarketSync.FilterAnalyticsHistory(h, { mode = "week", weekIndex = MarketSync.AnalyticsWeekIndex(monday) })
  assert(#v == 2, "Monday and Sunday are in the week, the prior Sunday is not")
`);

run('time mode returns one half-hour slot from granular rows only', `
  local h = { Row(10, 35, 1, true), Row(9, 35, 2, true), Row(8, 34, 3, true), Row(7, nil, 4, false) }
  local v = MarketSync.FilterAnalyticsHistory(h, { mode = "time", bucketOffset = 35 })
  assert(#v == 2 and v[1].day == 10 and v[2].day == 9, "17:30 on each day, nothing else")
`);

run('ListAnalyticsWeeks returns sorted unique week indexes', `
  local h = { Row(${today}, 1, 1, true), Row(${today - 1}, 1, 1, true), Row(${today - 14}, 1, 1, true) }
  local weeks = MarketSync.ListAnalyticsWeeks(h)
  assert(#weeks == 2, "two distinct weeks")
  assert(weeks[1] < weeks[2], "ascending")
`);

console.log(`\nAll ${passed} analytics filter tests passed.`);
