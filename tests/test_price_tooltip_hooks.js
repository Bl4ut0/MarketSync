// Price tooltip hooks on a client that has TooltipDataProcessor but whose item
// tooltips only fire OnTooltipSetItem (the Anniversary client), and on a client
// that fires both. Loads the whole addon in the simulated client.
const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;

const sim = createAddonSim({ flavor: 'anniversary', interface: 20505 });
sim.run(`
  A_Admin.realm = "Nightslayer"
  A_Admin.faction = "Horde"
  local function Stub() return setmetatable({}, { __index = function() return function() return Stub() end end }) end
  LibStub = function() return Stub() end
  ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
  AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent)
  -- The data-driven tooltip system exists, but nothing ever runs its callbacks.
  postCalls = {}
  Enum = Enum or {}
  Enum.TooltipDataType = { Item = 0 }
  TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = fn end }
`, 'stubs');
sim.loadToc(path.join(ROOT, 'MarketSync/MarketSync.toc'));
sim.run(`
  A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
  A_Admin.FireEvent("PLAYER_LOGIN")
  MarketSync.InitializeDB()
  MarketSync.GetRealmDB().PersonalData["4339"] = { m = 1900000, d = MarketSync.GetCurrentScanDay(), h = {}, vh = {} }
  function ShowItem()
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
    GameTooltip.MarketSyncProcessingItem = nil
    GameTooltip.MarketSyncOwnershipItem = nil
    GameTooltip:SetHyperlink("item:4339")
  end
  function CountPriceLines()
    local n = 0
    for _, line in ipairs(GameTooltip.lines) do if line.left:find("MarketSync AH") then n = n + 1 end end
    return n
  end
`, 'setup');

function test(name, chunk) {
  try { sim.run(chunk, name); } catch (e) { console.error('FAIL ' + name + ': ' + e.message); process.exit(1); }
  console.log('PASS ' + name);
  passed++;
}

test('Both hook paths are installed', `
  local via = MarketSync.TooltipStats.installedVia
  assert(via and via:find("TooltipDataProcessor") and via:find("OnTooltipSetItem"), tostring(via))
  assert(#postCalls >= 1 and GameTooltip._scripts.OnTooltipSetItem ~= nil)
`);

test('Price shows when only OnTooltipSetItem fires', `
  ShowItem()
  GameTooltip._scripts.OnTooltipSetItem(GameTooltip)
  assert(CountPriceLines() == 1, "price line count " .. CountPriceLines())
`);

test('A client that fires both paths gets the price once', `
  ShowItem()
  GameTooltip._scripts.OnTooltipSetItem(GameTooltip)
  for _, fn in ipairs(postCalls) do fn(GameTooltip, { id = 4339 }) end
  assert(CountPriceLines() == 1, "price line count " .. CountPriceLines())
`);

test('/ms tooltip reports that the hook ran', `
  assert(MarketSync.TooltipStats.calls >= 2)
`);

test('Data Pack fills tooltips only when nothing was scanned, and never enters guild data', `
  local db = MarketSync.GetRealmDB()
  db.GuildData = db.GuildData or {}
  -- An old loader left a copied pack row behind; a real synced row must stay.
  db.GuildData["7070"] = { m = 500, q = 1, t = 1, src = "DataPack" }
  db.GuildData["7071"] = { m = 800, q = 1, d = MarketSync.GetCurrentScanDay() }
  assert(MarketSync.PurgeDataPackRowsFromGuildData(db) == 1, "copied pack rows are removed")
  assert(db.GuildData["7070"] == nil and db.GuildData["7071"] ~= nil, "synced rows stay")

  -- The pack add-on keeps its own table and is read on demand.
  MarketSyncData = { GetCurrentMarketPrices = function()
    return { ["4339"] = { m = 111, t = 1 }, ["7070"] = { m = 500, t = 1 } }, "test market"
  end }
  local packOnly = MarketSync.GetItemPriceAndScanInfo("item:7070", { allowDataPack = true })
  assert(packOnly and packOnly.price == 500 and packOnly.source == "Data Pack", "unscanned item uses the pack")
  assert(MarketSync.GetItemPriceAndScanInfo("item:7070") == nil, "without allowDataPack only scans and syncs count")
  local scanned = MarketSync.GetItemPriceAndScanInfo("item:4339", { allowDataPack = true })
  assert(scanned and scanned.price == 1900000 and scanned.source ~= "Data Pack", "scan data wins over the pack")
  assert(db.GuildData["7070"] == nil, "reading the pack never writes guild data")
`);

console.log(`All ${passed} price tooltip hook tests passed.`);
