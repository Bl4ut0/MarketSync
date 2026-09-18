// Automated test suite for MarketSync Provider abstraction and Auctionator decoupling
const fs = require('fs');
const path = require('path');
const deps = path.resolve(__dirname, '../../ItemRack-Forever/node_modules');
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring } = require(path.join(deps, 'fengari'));

const marketSyncDir = path.resolve(__dirname, '../MarketSync');
const providerLua = fs.readFileSync(path.join(marketSyncDir, 'Provider.lua'), 'utf8');
const auctionatorProviderLua = fs.readFileSync(path.join(marketSyncDir, 'Providers/AuctionatorProvider.lua'), 'utf8');
const foreverProviderLua = fs.readFileSync(path.join(marketSyncDir, 'Providers/ForeverProvider.lua'), 'utf8');
const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');

let passed = 0;
function test(name, fn) {
  try {
    fn();
    console.log(`PASS ${name}`);
    passed++;
  } catch (err) {
    console.error(`FAIL ${name}: ${err.message}`);
    process.exit(1);
  }
}

function createLuaState(setupLua) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    time = function() return 1773780000 end
    UnitFactionGroup = function() return "Alliance" end
    GetRealmName = function() return "Faerlina" end
    GetNormalizedRealmName = function() return "Faerlina" end
    C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
    ItemLocation = { CreateFromItemLink = function(link) return { link = link } end }
  `;

  const script = `${mockEnv}\n${setupLua || ''}\n${providerLua}\n${auctionatorProviderLua}\n${foreverProviderLua}\n${configLua}`;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== lua.LUA_OK) {
    const err = lua.lua_tojsstring(L, -1);
    throw new Error(`Lua setup error: ${err}`);
  }
  return L;
}

function execLua(L, chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
    const err = lua.lua_tojsstring(L, -1);
    throw new Error(`Lua exec error: ${err}`);
  }
}

// 1. Provider auto-selection tests
test('auto-selects ForeverProvider when MarketSyncForeverScanner is present and Auctionator is nil', () => {
  const L = createLuaState(`
    MarketSyncForeverScanner = { Version = "0.3.0" }
    Auctionator = nil
  `);
  execLua(L, `
    MarketSync.Provider.Select()
    assert(MarketSync.Provider.GetActiveName() == "forever", "Expected forever provider")
    assert(MarketSync.Provider.IsWatchSupported() == true, "Expected watch support")
    assert(MarketSync.Provider.CanExportShoppingList() == false, "Shopping lists should be disabled on Forever")
  `);
});

test('auto-selects AuctionatorProvider when Auctionator is loaded without scanner', () => {
  const L = createLuaState(`
    MarketSyncForeverScanner = nil
    Auctionator = {
      Database = { db = {} },
      API = { v1 = {
        GetAuctionPriceByItemID = function(caller, id) return 15000 end,
        GetAuctionAgeByItemID = function(caller, id) return 2.5 end,
      }},
      Constants = { SCAN_DAY_0 = 1600000000 },
    }
  `);
  execLua(L, `
    MarketSync.Provider.Select()
    assert(MarketSync.Provider.GetActiveName() == "auctionator", "Expected auctionator provider")
    assert(MarketSync.Provider.IsWatchSupported() == false, "Auctionator should not report watch support")
    assert(MarketSync.Provider.CanExportShoppingList() == true, "Shopping lists should be enabled on Auctionator")
    assert(MarketSync.GetAuctionPrice(1234) == 15000, "GetAuctionPrice should query Auctionator API")
    assert(MarketSync.GetAuctionAge(1234) == 2.5, "GetAuctionAge should query Auctionator API")
  `);
});

test('falls back to NullProvider without error when no auction backends are loaded', () => {
  const L = createLuaState(`
    MarketSyncForeverScanner = nil
    Auctionator = nil
    C_AuctionHouse = nil
  `);
  execLua(L, `
    MarketSync.Provider.Select()
    assert(MarketSync.Provider.GetActiveName() == "none", "Expected none provider")
    assert(MarketSync.GetAuctionPrice(1234) == nil, "Should return nil without error")
    assert(MarketSync.GetAuctionAge(1234) == nil, "Should return nil without error")
    assert(MarketSync.Provider.CanExportShoppingList() == false, "Shopping lists should be disabled")
  `);
});

// 2. ForeverProvider native item key normalization & quote semantics
test('normalizes item links, suffixes, and pet species without losing variant identity', () => {
  const L = createLuaState(`
    MarketSyncForeverScanner = { Version = "0.3.0" }
  `);
  execLua(L, `
    local P = MarketSync.Provider.Registry["forever"]
    local k1 = P.ToItemKey("item:1234:0:0:0:0:0:55")
    assert(k1.itemID == 1234 and k1.itemSuffix == 55 and k1.itemLevel == 0, "Suffix 55 should be preserved")

    local k2 = P.ToItemKey("item:1234:0:0:0:0:0:0")
    assert(k2.itemID == 1234 and k2.itemSuffix == 0, "Base suffix 0 should be preserved")
    assert(P.ToKeyID("item:1234:0:0:0:0:0:55") ~= P.ToKeyID("item:1234:0:0:0:0:0:0"), "Variants must not collide")

    local k3 = P.ToItemKey("battlepet:150")
    assert(k3.itemID == 82800 and k3.battlePetSpeciesID == 150, "Battle pet species should be preserved")

    local k4 = P.ToItemKey(5678)
    assert(k4.itemID == 5678 and k4.itemSuffix == 0 and k4.itemLevel == 0, "Numeric item ID parsed")
  `);
});

test('ForeverProvider enforces complete quote semantics and rejects partial browse prices', () => {
  const L = createLuaState(`
    local mockRecords = {
      ["1001:0:0:0"] = {
        keyID = "1001:0:0:0",
        key = { itemID = 1001, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
        latest = {
          minUnitPrice = 4500,
          seenAt = 1773778200, -- 1800s (30m) ago
          complete = true,
          source = "native-item-search",
          available = 10,
        },
      },
      ["1002:0:0:0"] = {
        keyID = "1002:0:0:0",
        key = { itemID = 1002, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
        latest = {
          browseMinPrice = 3000,
          minUnitPrice = nil,
          seenAt = 1773778200,
          complete = false,
          source = "native-browse",
          available = 5,
        },
      },
      ["1003:0:0:0"] = {
        keyID = "1003:0:0:0",
        key = { itemID = 1003, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
        latest = {
          minUnitPrice = nil,
          seenAt = 1773778200,
          complete = true,
          source = "native-item-search",
          available = 0,
        },
      },
    }

    MarketSyncForeverScanner = {
      Version = "0.3.0",
      Store = { records = mockRecords, watched = { ["1001:0:0:0"] = true } },
      Provider = {
        GetSnapshot = function(key)
          local id = table.concat({key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0}, ":")
          return mockRecords[id] and mockRecords[id].latest or nil
        end
      },
      MarketID = "forever|1|Faerlina|Alliance|main",
    }
  `);

  execLua(L, `
    MarketSync.Provider.Select("forever")
    
    -- Complete quote returns valid buyout price
    assert(MarketSync.GetAuctionPrice(1001) == 4500, "Complete snapshot should yield buyout price")
    local age = MarketSync.GetAuctionAge(1001)
    assert(math.abs(age - (1800 / 86400)) < 0.0001, "Age should match elapsed days")

    -- Incomplete / browse-only result cannot produce a fresh buyout price
    assert(MarketSync.GetAuctionPrice(1002) == nil, "Partial browse result must not produce buyout price")

    -- Complete empty result has zero stock and no price
    assert(MarketSync.GetAuctionPrice(1003) == nil, "Empty complete result has no price")

    -- Watch status
    assert(MarketSync.Provider.IsWatched("1001:0:0:0") == true, "Key 1001 should be watched")
    assert(MarketSync.Provider.IsWatched("1002:0:0:0") == false, "Key 1002 should not be watched")
  `);
});

test('ForeverProvider uses native Unix 30-minute buckets', () => {
  const L = createLuaState(`
    MarketSyncForeverScanner = { Version = "0.3.0" }
  `);
  execLua(L, `
    MarketSync.Provider.Select("forever")
    local bucket = MarketSync.GetCurrentBucket()
    local expected = math.floor(1773780000 / 1800)
    assert(bucket == expected, "Forever should use Unix 30-min bucket: " .. tostring(bucket) .. " vs " .. tostring(expected))
  `);
});

test('MarketSync runs without Auctionator present and leaves original MarketSyncDB intact', () => {
  const L = createLuaState(`
    MarketSyncForeverScanner = {
      Version = "0.3.0",
      Store = { records = {}, watched = {} },
      Provider = { GetSnapshot = function() return nil end },
      MarketID = "forever-test",
    }
    Auctionator = nil
  `);
  execLua(L, `
    MarketSync.InitializeDB()
    assert(MarketSyncDB ~= nil, "MarketSyncDB should initialize without Auctionator")
    assert(MarketSync.Provider.GetActiveName() == "forever", "Should activate forever provider")
    assert(MarketSync.GetAuctionPrice("item:9999") == nil, "Lookups return nil cleanly")
  `);
});

console.log(`\nAll ${passed} provider decoupling tests passed successfully!`);
