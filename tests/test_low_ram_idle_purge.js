// Low RAM mode: a source loaded on demand (Load button) stays in memory while it
// is used, then is freed after 5 idle minutes off screen. The source kept for
// the Main tab is never freed. Loads the whole addon in the simulated client.
const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;

const sim = createAddonSim({ flavor: 'anniversary', interface: 20505 });
sim.run(`
  A_Admin.realm = "Nightslayer"
  A_Admin.faction = "Horde"
  collectgarbage = function() return 0 end -- not implemented by fengari
  local function Stub() return setmetatable({}, { __index = function() return function() return Stub() end end }) end
  LibStub = function() return Stub() end
  ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
  AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent)
`, 'stubs');
sim.loadToc(path.join(ROOT, 'MarketSync/MarketSync.toc'));
sim.run(`
  A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
  A_Admin.FireEvent("PLAYER_LOGIN")
  MarketSync.InitializeDB()
  MarketSyncDB.LowRamMode = true
  MarketSyncDB.LowRamKeepMain = false
  local db = MarketSync.GetRealmDB()
  db.NeutralData = db.NeutralData or {}
  db.NeutralData["4339"] = { m = 1500, d = MarketSync.GetCurrentScanDay(), h = {}, vh = {} }
  db.PersonalData["4338"] = { m = 900, d = MarketSync.GetCurrentScanDay(), h = {}, vh = {} }
  function Loaded(source) return MarketSync.GetLoadedSources()[source] end
  function Settle() A_Admin.AdvanceTime(5) end
`, 'setup');

function test(name, chunk) {
  try { sim.run(chunk, name); } catch (e) { console.error('FAIL ' + name + ': ' + e.message); process.exit(1); }
  console.log('PASS ' + name);
  passed++;
}

test('Neutral is not in memory until it is loaded', `
  A_Admin.AdvanceTime(120)
  assert(not Loaded("neutral"), "Neutral must wait for the Load button")
`);

test('A loaded source stays while it is used', `
  local done = false
  MarketSync.LoadNeutralCache(function() done = true end)
  Settle()
  assert(done and Loaded("neutral"), "Neutral loads on request")
  MarketSync.TouchLowRamSource("neutral")
  A_Admin.AdvanceTime(240)
  MarketSync.TouchLowRamSource("neutral")
  A_Admin.AdvanceTime(240)
  assert(Loaded("neutral"), "used within the last 5 minutes, so kept")
`);

test('An idle source is freed after 5 minutes', `
  A_Admin.AdvanceTime(400)
  assert(not Loaded("neutral"), "idle Neutral is freed")
`);

test('The source kept for the Main tab is never freed', `
  MarketSyncDB.LowRamKeepMain = true
  MarketSyncDB.MainSource = "personal"
  MarketSync.PreloadKeptSource()
  Settle()
  assert(Loaded("personal"), "kept Personal is loaded")
  A_Admin.AdvanceTime(900)
  assert(Loaded("personal"), "kept Personal survives idle time")
`);

test('Keeping Latest frees Personal and Guild, and Processing still has prices', `
  MarketSyncDB.LowRamKeepMain = true
  MarketSyncDB.MainSource = "latest"
  MarketSync.PreloadKeptSource()
  Settle()
  assert(Loaded("latest"), "Latest is kept")
  assert(not Loaded("personal") and not Loaded("guild"), "Personal and Guild are freed once Latest is built")
  local status = MarketSync.GetIndexStatus()
  assert(status.latestReady and status.personalReleased and status.guildReleased,
    "The Debugging page is told Latest is built and the others were freed")
  assert((status.personalTotal or 0) == 0 and (status.personalResolved or 0) == 0,
    "Freed sources must not keep stale counts")
  local index = MarketSync.GetProcessingIndexSources()
  assert(index and index["4338"], "Processing reads the kept Latest index instead of reporting no market cache")
  local _, _, _, _, _, loadedRows = MarketSync.GetEstimatedRAMUsage()
  assert(loadedRows == status.latestCount, "RAM estimate counts only rows in memory")
`);

test('After Personal and Guild are freed, new scans and syncs go into Latest instead of emptying it', `
  local db = MarketSync.GetRealmDB()
  local before = MarketSync.GetIndexStatus().latestCount
  -- A personal scan writes a new row and reports its key.
  db.PersonalData["4340"] = { m = 777, d = MarketSync.GetCurrentScanDay(), observedAt = time(), h = {}, vh = {} }
  MarketSync.RefreshPersonalBrowseIndexKeys({ ["4340"] = true })
  Settle()
  local status = MarketSync.GetIndexStatus()
  assert(status.latestReady, "a personal scan must not discard Latest")
  assert(status.latestCount == before + 1, "the scanned row joins Latest: " .. tostring(status.latestCount))
  assert(not Loaded("personal"), "Personal stays freed")
  -- A guild sync delivers a row, then commits.
  db.GuildData = db.GuildData or {}
  db.GuildData["4341"] = { m = 555, d = MarketSync.GetCurrentScanDay(), h = {}, vh = {} }
  MarketSync.AddToGuildIncoming("4341")
  MarketSync.CommitGuildSync()
  Settle()
  status = MarketSync.GetIndexStatus()
  assert(status.latestReady and status.latestCount == before + 2, "a guild sync must not discard Latest")
  local index = MarketSync.GetProcessingIndexSources()
  assert(index and index["4340"] and index["4341"], "Processing sees the new rows")
`);

test('Nothing is freed with Low RAM mode off', `
  MarketSyncDB.LowRamMode = false
  MarketSyncDB.LowRamKeepMain = false
  MarketSync.LoadNeutralCache()
  Settle()
  A_Admin.AdvanceTime(900)
  assert(Loaded("neutral"), "Low RAM off keeps everything")
`);

console.log(`All ${passed} Low RAM idle purge tests passed.`);
