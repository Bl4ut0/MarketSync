// Tests strict regional & per-market Data Pack selection at login and runtime.
// Ensures only the character's flavor/region/realm-or-ruleset/faction pack is loaded,
// mismatched flavors or regions are rejected, and GuildData never absorbs pack rows.
const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');

const ROOT = path.resolve(__dirname, '..');
let passed = 0;

function makeSim(opts) {
  const sim = createAddonSim(opts);
  sim.run(`
    local function Stub() return setmetatable({}, { __index = function() return function() return Stub() end end }) end
    LibStub = function() return Stub() end
    ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
    AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent)
    SlashCmdList = SlashCmdList or {}
  `, 'stubs');
  sim.loadToc(path.join(ROOT, 'MarketSync/MarketSync.toc'));
  return sim;
}

function test(name, fn) {
  try {
    fn();
    console.log('PASS ' + name);
    passed++;
  } catch (e) {
    console.error('FAIL ' + name + ': ' + e.message);
    process.exit(1);
  }
}

test('Forever loads only the current ruleset and faction pack, never other packs', () => {
  const sim = makeSim({ flavor: 'forever', interface: 16001 });
  sim.run(`
    A_Admin.realm = "PvP2"
    A_Admin.faction = "Alliance"
    GetCurrentRegionName = function() return "US" end
    A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
    A_Admin.FireEvent("PLAYER_LOGIN")
    MarketSync.InitializeDB()

    loadedAddons = {}
    local installed = {
      ["MarketSyncData_Forever_pvp_Alliance"] = true,
      ["MarketSyncData_Forever_pvp_Horde"] = true,
      ["MarketSyncData_Forever_normal_Alliance"] = true,
      ["MarketSyncData_Retail_us"] = true,
    }
    C_AddOns = {
      GetAddOnInfo = function(name)
        if installed[name] then return name, name, "", true, "DEMAND_LOADED" end
        return nil
      end,
      IsAddOnLoaded = function(name) return loadedAddons[name] == true end,
      LoadAddOn = function(name)
        if not installed[name] then return false, "MISSING" end
        loadedAddons[name] = true
        if name == "MarketSyncData_Forever_pvp_Alliance" then
          MarketSyncDataDB = MarketSyncDataDB or {}
          MarketSyncDataDB["pvp@Alliance"] = {
            ["13468"] = { m = 640000, t = 1700000000, h = { [200] = "1:5000:2" } },
          }
        end
        return true
      end,
    }
    MarketSyncData = { flavor = "forever" }

    local prices, label, loadedName = MarketSync.EnsureCurrentDataPack()
    assert(loadedName == "MarketSyncData_Forever_pvp_Alliance", "expected pvp_Alliance load, got " .. tostring(loadedName))
    assert(loadedAddons["MarketSyncData_Forever_pvp_Alliance"] == true, "pvp_Alliance should be loaded")
    assert(loadedAddons["MarketSyncData_Forever_pvp_Horde"] == nil, "pvp_Horde must not load")
    assert(loadedAddons["MarketSyncData_Forever_normal_Alliance"] == nil, "normal_Alliance must not load")
    assert(loadedAddons["MarketSyncData_Retail_us"] == nil, "Retail pack must not load on Forever")
    assert(prices and prices["13468"] and prices["13468"].m == 640000, "prices from active market returned")
    assert(MarketSync.GetDataPackPrice("13468") == 640000, "GetDataPackPrice reads active market")

    local rec = MarketSync.GetDataPackRecord("13468")
    assert(rec and rec.h and rec.h[200] == "1:5000:2", "GetDataPackRecord reads Forever history")

    local db = MarketSync.GetRealmDB()
    assert(not (db.GuildData and db.GuildData["13468"]), "GuildData must not copy DataPack rows")
  `);
});

test('Retail loads only the matching regional pack and rejects mismatched regions', () => {
  const sim = makeSim({ flavor: 'retail', interface: 120001 });
  sim.run(`
    A_Admin.realm = "Area52"
    A_Admin.faction = "Horde"
    GetCurrentRegionName = function() return "US" end
    A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
    A_Admin.FireEvent("PLAYER_LOGIN")
    MarketSync.InitializeDB()

    loadedAddons = {}
    local installed = {
      ["MarketSyncData_Retail_us"] = true,
      ["MarketSyncData_Retail_eu"] = true,
    }
    C_AddOns = {
      GetAddOnInfo = function(name)
        if installed[name] then return name, name, "", true, "DEMAND_LOADED" end
        return nil
      end,
      IsAddOnLoaded = function(name) return loadedAddons[name] == true end,
      LoadAddOn = function(name)
        if not installed[name] then return false end
        loadedAddons[name] = true
        MarketSyncDataDB = MarketSyncDataDB or {}
        if name == "MarketSyncData_Retail_us" then
          MarketSyncDataDB["us@Commodities"] = {
            ["210796"] = { m = 123400, t = 1700000100, h = { [201] = "2:2a:4" } },
          }
        elseif name == "MarketSyncData_Retail_eu" then
          MarketSyncDataDB["eu@Commodities"] = {
            ["210796"] = { m = 999900, t = 1700000100, h = { [201] = "2:9z:9" } },
          }
        end
        return true
      end,
    }
    MarketSyncData = { flavor = "retail", region = "us" }

    local prices, _, loadedName = MarketSync.EnsureCurrentDataPack()
    assert(loadedName == "MarketSyncData_Retail_us", "expected US Retail pack")
    assert(loadedAddons["MarketSyncData_Retail_eu"] == nil, "EU Retail pack must never load on US")
    assert(prices and prices["210796"].m == 123400)

    local rec = MarketSync.GetDataPackRecord("210796")
    assert(rec and rec.h and rec.h[201] == "2:2a:4", "GetDataPackRecord resolves Retail US record")

    -- Force a wrong-region Data Pack and ensure MarketSync refuses it cleanly
    MarketSync.ResetDataPackCache()
    MarketSyncData.region = "eu"
    local badPrices, _, _, err = MarketSync.EnsureCurrentDataPack()
    assert(badPrices == nil and err == "region_mismatch", "expected region_mismatch, got " .. tostring(err))
    assert(MarketSync.GetDataPackPrice("210796") == nil, "mismatched region price must be rejected")
    assert(MarketSync.GetMarketSyncDataPrice("210796") == nil, "Provider hook rejects mismatched region")
  `);
});

test('Classic Progression supports Index connected-realm mapping and rejects cross-flavor packs', () => {
  const sim = makeSim({ flavor: 'classic', interface: 50503 });
  sim.run(`
    A_Admin.realm = "Faerlina"
    A_Admin.faction = "Horde"
    GetCurrentRegionName = function() return "US" end
    A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
    A_Admin.FireEvent("PLAYER_LOGIN")
    MarketSync.InitializeDB()

    loadedAddons = {}
    local installed = {
      ["MarketSyncData_Classic_us_group3"] = true,
      ["MarketSyncData_Classic_eu_group1"] = true,
    }
    C_AddOns = {
      GetAddOnInfo = function(name)
        if installed[name] then return name, name, "", true, "DEMAND_LOADED" end
        return nil
      end,
      IsAddOnLoaded = function(name) return loadedAddons[name] == true end,
      LoadAddOn = function(name)
        if not installed[name] then return false end
        loadedAddons[name] = true
        MarketSyncDataDB = MarketSyncDataDB or {}
        if name == "MarketSyncData_Classic_us_group3" then
          MarketSyncDataDB["us_faerlina@CrossFaction"] = {
            ["72092"] = { m = 45000, t = 1700000200, h = { [202] = "3:1a:8" } },
          }
        end
        return true
      end,
    }
    MarketSyncData = {
      flavor = "classic",
      Index = {
        ["us_faerlina@CrossFaction"] = { addon = "MarketSyncData_Classic_us_group3", region = "us" },
        ["eu_firemaw@CrossFaction"] = { addon = "MarketSyncData_Classic_eu_group1", region = "eu" },
      },
    }

    local prices, _, loadedName = MarketSync.EnsureCurrentDataPack()
    assert(loadedName == "MarketSyncData_Classic_us_group3", "expected mapped connected-realm US pack")
    assert(loadedAddons["MarketSyncData_Classic_eu_group1"] == nil, "EU pack must never load")
    assert(prices and prices["72092"].m == 45000)

    local provPrice = MarketSync.GetMarketSyncDataPrice(72092)
    assert(provPrice == 45000, "Provider resolves regional Classic pack price")

    -- Cross-flavor Data Pack (e.g. Forever pack manually loaded in Classic) must be rejected
    MarketSync.ResetDataPackCache()
    MarketSyncData.flavor = "forever"
    local wrongPrices, _, _, reason = MarketSync.EnsureCurrentDataPack()
    assert(wrongPrices == nil and reason == "flavor_mismatch", "expected flavor_mismatch, got " .. tostring(reason))
    assert(MarketSync.GetMarketSyncDataPrice(72092) == nil, "Provider hook rejects cross-flavor Data Pack")
  `);
});

test('PLAYER_ENTERING_WORLD auto-loads the player market Data Pack after purging stale GuildData rows', () => {
  const sim = makeSim({ flavor: 'anniversary', interface: 20505 });
  sim.run(`
    A_Admin.realm = "Nightslayer"
    A_Admin.faction = "Alliance"
    GetCurrentRegionName = function() return "US" end
    A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
    A_Admin.FireEvent("PLAYER_LOGIN")
    MarketSync.InitializeDB()

    local db = MarketSync.GetRealmDB()
    db.GuildData["999"] = { m = 100, q = 1, t = 1, src = "DataPack" }

    loadedAddons = {}
    local installed = {
      ["MarketSyncData_Anniversary_us_nightslayer_Alliance"] = true,
      ["MarketSyncData_Anniversary_us_nightslayer_Horde"] = true,
    }
    C_AddOns = {
      GetAddOnInfo = function(name)
        if installed[name] then return name, name, "", true, "DEMAND_LOADED" end
        return nil
      end,
      IsAddOnLoaded = function(name) return loadedAddons[name] == true end,
      LoadAddOn = function(name)
        if not installed[name] then return false end
        loadedAddons[name] = true
        MarketSyncDataDB = MarketSyncDataDB or {}
        MarketSyncDataDB["us_nightslayer@Alliance"] = {
          ["22450"] = { m = 77000, t = 1700000300, h = { [205] = "0:4b:5" } },
        }
        return true
      end,
    }
    MarketSyncData = { flavor = "anniversary", region = "us" }

    -- Capture C_Timer.After callback fired at 2s on PLAYER_ENTERING_WORLD
    local timerCallbacks = {}
    C_Timer = { After = function(sec, fn) timerCallbacks[#timerCallbacks + 1] = { sec = sec, fn = fn } end }
    A_Admin.FireEvent("PLAYER_ENTERING_WORLD")
    for _, t in ipairs(timerCallbacks) do
      if t.sec == 2 and type(t.fn) == "function" then t.fn() end
    end

    assert(db.GuildData["999"] == nil, "stale DataPack row purged from GuildData on login")
    assert(loadedAddons["MarketSyncData_Anniversary_us_nightslayer_Alliance"] == true, "character Anniversary Alliance pack auto-loaded at login")
    assert(loadedAddons["MarketSyncData_Anniversary_us_nightslayer_Horde"] == nil, "Horde pack never loaded on Alliance character")
    assert(db.GuildData["22450"] == nil, "DataPack rows never copied into GuildData")
    assert(MarketSync.GetDataPackPrice("22450") == 77000, "item price available directly from loaded regional pack")
  `);
});

console.log(`All ${passed} regional DataPack loader tests passed.`);
