// Automated test suite for MarketSync Modern Professions & First Aid (Health) consolidation
const fs = require('fs');
const path = require('path');

const candidateDeps = [
  path.resolve(__dirname, '../node_modules'),
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
];
const deps = candidateDeps.find(p => fs.existsSync(p)) || candidateDeps[0];
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring } = require(path.join(deps, 'fengari'));

const marketSyncDir = path.resolve(__dirname, '../MarketSync');
const coreLua = fs.readFileSync(path.join(marketSyncDir, 'Core.lua'), 'utf8');
const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
const processingLua = fs.readFileSync(path.join(marketSyncDir, 'Processing.lua'), 'utf8');
const uiProcessingLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Processing.lua'), 'utf8');
const uiBrowseLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Browse.lua'), 'utf8');
const uiCraftingInfoLua = fs.readFileSync(path.join(marketSyncDir, 'UI_CraftingInfo.lua'), 'utf8');
const uiItemDetailLua = fs.readFileSync(path.join(marketSyncDir, 'UI_ItemDetail.lua'), 'utf8');

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

// 1. Luaparse AST validation
test('AST syntax check on modified files', () => {
  const files = [
    { name: 'Core.lua', content: coreLua },
    { name: 'Config.lua', content: configLua },
    { name: 'Processing.lua', content: processingLua },
    { name: 'UI_Processing.lua', content: uiProcessingLua },
    { name: 'UI_Browse.lua', content: uiBrowseLua },
    { name: 'UI_CraftingInfo.lua', content: uiCraftingInfoLua },
    { name: 'UI_ItemDetail.lua', content: uiItemDetailLua },
  ];
  for (const f of files) {
    luaparse.parse(f.content, { luaVersion: '5.1' });
  }
});

function createLuaState(setupLua) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    time = function() return 1773780000 end
    UnitFullName = function() return "TestChar", "Faerlina" end
    GetRealmName = function() return "Faerlina" end
    GetNormalizedRealmName = function() return "Faerlina" end
    GetExpansionLevel = function() return 9 end

    GameTooltip = { HookScript = function() end }
    TooltipDataProcessor = { AddTooltipPostCall = function() end }
    MarketSync = MarketSync or {}
    MarketSyncDB = MarketSyncDB or {}
    MarketSync.GetRealmDB = function() return MarketSyncDB end
    MarketSync.GetAuctionPrice = function(id)
      local prices = {
        [118] = 2000,    -- Minor Healing Potion: 20s
        [1251] = 500,    -- Linen Bandage: 5s
        [2447] = 500,    -- Peacebloom: 5s
        [765] = 400,     -- Silverleaf: 4s
        [3371] = 50,     -- Empty Vial: 50c
        [2592] = 100,    -- Linen Cloth: 1s
      }
      return prices[id] or 1000
    end
    MarketSync.GetAuctionAge = function(id) return 0.5 end
    MarketSync.FormatMoney = function(copper) return tostring(copper) .. "c" end
  `;

  const script = `${mockEnv}\n${setupLua || ''}\n${processingLua}`;
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

// 2. Modern C_TradeSkillUI Scanning Test
test('scans recipes via modern C_TradeSkillUI schematic API', () => {
  const L = createLuaState(`
    C_TradeSkillUI = {
      GetAllRecipeIDs = function() return { 101, 102 } end,
      GetBaseProfessionInfo = function() return { professionName = "Classic Alchemy", parentProfessionName = "Alchemy" } end,
      GetRecipeInfo = function(id)
        if id == 101 then
          return { name = "Minor Healing Potion", learned = true, disabled = false, minMade = 1, maxMade = 1 }
        else
          return { name = "Disabled Recipe", learned = false, disabled = true }
        end
      end,
      GetRecipeItemLink = function(id)
        if id == 101 then return "|Hitem:118:0:0:0|h[Minor Healing Potion]|h" end
        return nil
      end,
      GetRecipeSchematic = function(id, isRecraft)
        if id == 101 then
          return {
            quantityMin = 1,
            quantityMax = 1,
            reagentSlotSchematics = {
              { quantityRequired = 1, reagents = { { itemID = 2447 } } },
              { quantityRequired = 1, reagents = { { itemID = 765 } } },
              { quantityRequired = 1, reagents = { { itemID = 3371 } } },
            }
          }
        end
        return nil
      end
    }
  `);

  execLua(L, `
    local success = MarketSync.RefreshKnownCraftingRecipes()
    assert(success == true, "Expected RefreshKnownCraftingRecipes to succeed with C_TradeSkillUI")

    local count = MarketSync.GetCraftRecipeCount("Alchemy")
    assert(count == 1, "Expected 1 learned recipe in Alchemy, got " .. tostring(count))
  `);
});

// 3. Legacy GetTradeSkillInfo Fallback Scanning Test
test('falls back gracefully to legacy GetTradeSkillInfo API', () => {
  const L = createLuaState(`
    C_TradeSkillUI = nil
    GetTradeSkillLine = function() return "First Aid" end
    GetNumTradeSkills = function() return 2 end
    GetTradeSkillInfo = function(i)
      if i == 1 then
        return "Linen Bandage", "optimal", 0, false, nil, 1
      else
        return "Header", "header", 0, false, nil, 0
      end
    end
    GetTradeSkillItemLink = function(i)
      return "|Hitem:1251:0:0:0|h[Linen Bandage]|h"
    end
    GetTradeSkillNumMade = function(i) return 1, 1 end
    GetTradeSkillNumReagents = function(i) return 1 end
    GetTradeSkillReagentItemLink = function(i, r) return "|Hitem:2592:0:0:0|h[Linen Cloth]|h" end
    GetTradeSkillReagentInfo = function(i, r) return "Linen Cloth", "icon", 1 end
  `);

  execLua(L, `
    local success = MarketSync.RefreshKnownCraftingRecipes()
    assert(success == true, "Expected RefreshKnownCraftingRecipes to succeed with legacy API")

    local count = MarketSync.GetCraftRecipeCount("First Aid (Health)")
    assert(count >= 1, "Expected at least 1 recipe in First Aid (Health)")
  `);
});

// 4. Secondary Profession Detection without inventing learned recipes
test('lists First Aid but does not invent unscanned recipes', () => {
  const L = createLuaState(`
    -- Player has primary Alchemy and secondary First Aid (6th return)
    GetProfessions = function() return 1, nil, nil, nil, nil, 2 end
    GetProfessionInfo = function(idx)
      if idx == 1 then return "Alchemy" end
      if idx == 2 then return "First Aid" end
      return nil
    end
  `);

  execLua(L, `
    local profs = MarketSync.GetProcessingProfessions()
    local hasFirstAidHealth = false
    local hasBareFirstAid = false
    for _, p in ipairs(profs) do
      if p == "First Aid (Health)" then hasFirstAidHealth = true end
      if p == "First Aid" then hasBareFirstAid = true end
    end
    assert(hasFirstAidHealth == true, "Expected First Aid (Health) in professions list")
    assert(hasBareFirstAid == false, "Bare 'First Aid' should be normalized into 'First Aid (Health)'")

    -- Query recipes for First Aid (Health)
    local crafts = MarketSync.FindProfitableCrafts("First Aid (Health)", 0)
    assert(#crafts == 0, "Unscanned static recipes must not be shown as learned")
  `);
});

test('current character profession dropdown excludes unlearned cached crafts', () => {
  const L = createLuaState(`
    GetProfessions = function() return 1, 2, nil, nil, 3, 4 end
    GetProfessionInfo = function(idx)
      return ({ [1] = "Engineering", [2] = "Mining", [3] = "Cooking", [4] = "First Aid" })[idx]
    end
  `);

  execLua(L, `
    MarketSyncDB.KnownProfessionsByCharacter = {
      ["TestChar-Faerlina"] = { updatedAt = 1, professions = { Enchanting = true, Engineering = true } }
    }
    MarketSyncDB.KnownCraftingRecipesByCharacter = {
      ["TestChar-Faerlina"] = {
        __cacheVersion = 2,
        Enchanting = { cacheVersion = 2, recipes = {
          { name = "Minor Wizard Oil", outputItemID = 20744,
            mats = { { itemID = 10940, qty = 1 } } }
        } }
      }
    }
    local professions = MarketSync.GetProcessingProfessions()
    local found = {}
    for _, name in ipairs(professions) do found[name] = true end
    assert(found.Engineering and found.Cooking and found["First Aid (Health)"],
      "Current engineering, cooking, and first aid should remain selectable")
    assert(not found.Enchanting, "Unlearned Enchanting must not reappear from cached recipes")
    assert(not found.Mining, "Gathering professions do not have craft-profit recipes")
    GetProfessions = function() return 2 end
    local gatheringOnly = MarketSync.GetProcessingProfessions()
    assert(#gatheringOnly == 0, "A known gathering-only character must not inherit stale craft professions")
  `);
});

// 5. Dynamic Alchemy Health Potion Aggregation Test
test('dynamically aggregates scanned Alchemy health potions into First Aid (Health)', () => {
  const L = createLuaState(`
    C_TradeSkillUI = {
      GetAllRecipeIDs = function() return { 501 } end,
      GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end,
      GetRecipeInfo = function(id)
        return { name = "Super Healing Potion", learned = true, disabled = false, minMade = 1, maxMade = 1 }
      end,
      GetRecipeItemLink = function(id) return "|Hitem:22829:0:0:0|h[Super Healing Potion]|h" end,
      GetRecipeSchematic = function(id)
        return {
          quantityMin = 1,
          quantityMax = 1,
          reagentSlotSchematics = {
            { quantityRequired = 2, reagents = { { itemID = 22791 } } },
            { quantityRequired = 1, reagents = { { itemID = 22785 } } },
            { quantityRequired = 1, reagents = { { itemID = 22849 } } },
          }
        }
      end
    }
  `);

  execLua(L, `
    -- Scan Alchemy into character store
    MarketSync.RefreshKnownCraftingRecipes()

    -- Now inspect First Aid (Health)
    local crafts = MarketSync.FindProfitableCrafts("First Aid (Health)", 0)
    local foundSuperHealing = false
    for _, craft in ipairs(crafts) do
      if craft.outputItemID == 22829 then
        foundSuperHealing = true
      end
    end
    assert(foundSuperHealing == true, "Expected Super Healing Potion from Alchemy scan to be present in First Aid (Health)")
    local allCrafts = MarketSync.FindProfitableCrafts("ALL", 0)
    assert(#allCrafts == 1, "ALL should deduplicate a recipe shared by profession views")
  `);
});

test('known crafts remain visible when auction prices are missing', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function() return nil end
    C_TradeSkillUI = {
      GetAllRecipeIDs = function() return { 101 } end,
      GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end,
      GetRecipeInfo = function() return { name = "Minor Healing Potion", learned = true, disabled = false } end,
      GetRecipeItemLink = function() return "|Hitem:118|h[Minor Healing Potion]|h" end,
      GetRecipeSchematic = function()
        return { quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
          { quantityRequired = 1, reagents = { { itemID = 2447 } } },
        } }
      end,
    }
  `);
  execLua(L, `
    MarketSync.RefreshKnownCraftingRecipes()
    local rows = MarketSync.FindProfitableCrafts("ALL", 0)
    assert(#rows == 1, "Learned recipe should remain visible")
    assert(rows[1].hasMissingPrice == true and rows[1].margin == nil,
      "Unknown pricing must not be shown as zero profit")
  `);
});

test('disenchant range uses priced outcomes from the same probability row as EV', () => {
  const L = createLuaState();
  execLua(L, `
    local ev, stale, missing, gross, partial, drops, low, high =
      MarketSync.EstimateDisenchantEV(2, 16, 4, 999)
    assert(#drops == 3, "Expected dust, essence, and shard")
    assert(missing == 0 and partial == false, "All outputs should be priced")
    assert(math.abs(gross - 2225) < 0.01, "Expected gross EV from probability-weighted quantities")
    assert(ev == 2113, "Expected 5% AH-cut net EV")
    assert(low == 950 and high == 2850, "Expected min/max outcome after AH cut")
  `);
});

test('broad Processing search reads only the built cache without item or price queries', () => {
  const L = createLuaState('');
  execLua(L, `
    local index = {}
    for id = 10000, 10260 do
      index[tostring(id)] = { itemID = id, name = "Unpriced", price = 0 }
    end
    index["999"] = { itemID = 999, name = "Cached Green", rarity = 2,
      ilvl = 16, classID = 4, price = 100, age = 0 }
    for _, drop in ipairs(MarketSync.GetDisenchantDropList(2, 16, 4)) do
      index[tostring(drop.itemID)] = { itemID = drop.itemID, name = "Cached Material",
        price = 1000, age = 0 }
    end
    MarketSync.GetProcessingIndexSources = function()
      return index, { ["999"] = { itemID = 999, name = "Cached Guild Green", rarity = 2,
        ilvl = 16, classID = 4, price = 80, age = 0 } }
    end
    MarketSync.GetAuctionPrice = function() error("live price lookup during bulk search") end
    MarketSync.GetItemInfo = function() error("item request during bulk search") end
    AUCTIONATOR_PRICE_DATABASE = setmetatable({}, {
      __pairs = function() error("raw Auctionator DB walked") end,
    })
    local batches = 0
    local snapshot = MarketSync.BuildProcessingCacheSnapshot(function()
      batches = batches + 1
    end)
    assert(snapshot.indexedRows > 250 and batches > 0,
      "Large cache snapshot should expose bounded work steps")
    assert(snapshot.prices[999] and not snapshot.prices[10000],
      "Only priced, resolved index rows may become candidates")
    assert(snapshot.prices[999].price == 80,
      "Ready guild cache prices must be included in the snapshot")
    local rows = MarketSync.FindArbitrageByProcess("DISENCHANT", 0, snapshot)
    assert(#rows == 1 and rows[1].inputItemID == 999,
      "Disenchant search should evaluate the cached green item only")
  `);
});

test('browse placeholders recover after tooltip loads without a bulk rebuild', () => {
  const L = createLuaState('');
  const prefix = uiBrowseLua.slice(0, uiBrowseLua.indexOf('-- PARSE ITEM ID from a dbKey'));
  execLua(L, `
    scheduled = {}
    C_Timer = { After = function(_, fn) scheduled[#scheduled + 1] = fn end }
    CreateFrame = function()
      itemEvents = {
        RegisterEvent = function() end,
        SetScript = function(self, _, fn) self.onEvent = fn end,
      }
      return itemEvents
    end
    MarketSync.GetCurrentScanDay = function() return 100 end
    local available = false
    MarketSync.GetItemInfo = function(id)
      if available and id == 2515 then
        return "Flèche pointue", "|cffffffff|Hitem:2515:0|h[Flèche pointue]|h|r",
          1, 10, 10, "Projectile", "Arrow", 200, "", 132382, 0, 6, 2
      end
    end
    ${prefix}
    local entries = {}
    for i = 1, 45 do
      entries[i] = BuildIndexEntry("2515", 2515, { m = 123, d = 96 }, "personal", true)
      assert(entries[i].isPlaceholder, "Expected unresolved placeholder")
    end
    assert(not MarketSyncDB.ItemInfoCache or not MarketSyncDB.ItemInfoCache[2515],
      "Placeholder must never be saved as a real localized item")
    local refreshes = 0
    local visible = { IsShown = function() return true end,
      UpdateResults = function() refreshes = refreshes + 1 end }
    browsePanels[visible] = true
    available = true
    itemEvents.onEvent(nil, "GET_ITEM_INFO_RECEIVED", 2515, true)
    itemEvents.onEvent(nil, "ITEM_DATA_LOAD_RESULT", 2515, true)
    assert(#scheduled == 1, "Load events should coalesce")
    table.remove(scheduled, 1)()
    local resolved = 0
    for _, entry in ipairs(entries) do
      if not entry.isPlaceholder then resolved = resolved + 1 end
      assert(entry.price == 123 and entry.age == 4 and entry.source == "Personal",
        "Resolution must preserve market price and provenance")
    end
    assert(resolved == 20, "Late resolution must be capped at 20 rows per tick")
    while #scheduled > 0 do table.remove(scheduled, 1)() end
    for _, entry in ipairs(entries) do
      assert(entry.name == "Flèche pointue" and entry.icon == 132382 and entry.classID == 6,
        "Localized name, icon and filters should recover in place")
    end
    assert(refreshes == 3, "Refresh visible rows once per batch, not per item")
    assert(MarketSyncDB.ItemInfoCache[2515].n == "Flèche pointue", "Persist successful resolution")
    local unavailable = BuildIndexEntry("999999", 999999, { m = 1 }, "personal", true)
    ScheduleBrowseItemResolution(999999)
    table.remove(scheduled, 1)()
    assert(unavailable.isPlaceholder and #scheduled == 0, "Missing IDs must not spin forever")
    itemEvents.onEvent(nil, "GET_ITEM_INFO_RECEIVED", 999999, false)
    assert(#scheduled == 0, "Failed loads must not trigger another query")
  `);
});

test('Processing cache prefers fresh observations over stale lower prices', () => {
  const L = createLuaState('');
  execLua(L, `
    MarketSync.GetProcessingIndexSources = function()
      return {
        a = { itemID = 1, price = 100, age = 0, exactTime = 200 },
        b = { itemID = 2, price = 100, age = 0, exactTime = 200 },
        c = { itemID = 3, price = 100, age = 0 },
      }, {
        a = { itemID = 1, price = 1, age = 5, exactTime = 100 },
        b = { itemID = 2, price = 1, age = 0, exactTime = 100 },
        c = { itemID = 3, price = 1 },
      }
    end
    local snapshot = MarketSync.BuildProcessingCacheSnapshot()
    for id = 1, 3 do
      assert(snapshot.prices[id].price == 100, "Older or unknown-age bargain displaced fresh price")
    end
  `);
});

test('Craft Profit search uses saved recipes and cached prices without rescanning professions', () => {
  const L = createLuaState('');
  execLua(L, `
    MarketSyncDB.KnownCraftingRecipesByCharacter = {
      ["TestChar-Faerlina"] = {
        __cacheVersion = 2,
        Alchemy = { cacheVersion = 2, recipes = {
          { name = "Minor Healing Potion", outputItemID = 118, outputQty = 1,
            mats = { { itemID = 2447, qty = 1 } } }
        } }
      }
    }
    MarketSync.RefreshKnownCraftingRecipes = function()
      error("Craft Profit must not rescan the profession")
    end
    MarketSync.GetAuctionPrice = function()
      error("Craft Profit must not query a live price")
    end
    local snapshot = { prices = {
      [118] = { itemID = 118, name = "Minor Healing Potion", price = 2000, age = 0 },
      [2447] = { itemID = 2447, name = "Peacebloom", price = 500, age = 0 },
    } }
    local rows = MarketSync.FindProfitableCrafts("Alchemy", 0, nil, nil, snapshot)
    assert(#rows == 1 and rows[1].craftCost == 500 and rows[1].meetsMargin,
      "Craft Profit should use saved recipes and snapshot prices")
  `);
});

test('every bundled disenchant bracket has a complete probability distribution', () => {
  const L = createLuaState();
  execLua(L, `
    for _, classID in ipairs({2, 4}) do
      for quality = 2, 4 do
        for ilvl = 1, 164 do
          local drops = MarketSync.GetDisenchantDropList(quality, ilvl, classID)
          if #drops > 0 then
            local total = 0
            for _, drop in ipairs(drops) do total = total + drop.chance end
            assert(math.abs(total - 1) < 0.025,
              "Incomplete odds for class " .. classID .. " quality " .. quality .. " level " .. ilvl .. ": " .. total)
          end
        end
      end
    end
  `);
});

test('Forever does not infer TBC materials for unsupported green item levels', () => {
  const L = createLuaState(`
    MarketSync.Provider = { GetActiveName = function() return "forever" end }
    Auctionator = { Constants = { DisenchantingProbability = {
      [4] = { [2] = { { 66, 99, 100, 1, 22445 } } }
    } } }
  `);
  execLua(L, `
    assert(#MarketSync.GetDisenchantDropList(2, 16, 4) == 3, "Classic bracket should remain supported")
    assert(#MarketSync.GetDisenchantDropList(2, 80, 4) == 0, "TBC dust is not verified for Forever")
  `);
});

// 6. Vendor Price Lookup Test
test('resolves static and cached vendor prices accurately', () => {
  const L = createLuaState();
  execLua(L, `
    assert(MarketSync.GetVendorPrice(3371) == 40, "Empty Vial should be 40 copper")
    assert(MarketSync.GetVendorPrice(2321) == 100, "Fine Thread should be 100 copper")
    assert(MarketSync.GetVendorPrice(3857) == 500, "Coal should be 500 copper")
    assert(MarketSync.GetVendorPrice(4289) == 10, "Salt should be 10 copper")
    assert(MarketSync.GetVendorPrice(38682) == 1000, "Enchanting Vellum should be 1000 copper")

    -- Dynamic realm cache test
    MarketSyncDB.VendorPrices = { [99999] = 1234 }
    assert(MarketSync.GetVendorPrice(99999) == 1234, "Dynamic realm cache vendor price should be resolved")
  `);
});

// 7. Intermediate Recipe Lookup Test
test('resolves intermediate recipes for multi-tier components', () => {
  const L = createLuaState();
  execLua(L, `
    local linenBolt = MarketSync.GetRecipeForOutput(2996)
    assert(linenBolt ~= nil, "Bolt of Linen Cloth recipe should exist")
    assert(linenBolt.mats[1].itemID == 2592, "Bolt of Linen Cloth should require Linen Cloth")
    assert(linenBolt.mats[1].qty == 2, "Bolt of Linen Cloth should require 2 Linen Cloth")

    local steelBar = MarketSync.GetRecipeForOutput(3859)
    assert(steelBar ~= nil, "Steel Bar recipe should exist")
    assert(#steelBar.mats == 2, "Steel Bar should require 2 reagents (Iron Bar + Coal)")

    local grindingStone = MarketSync.GetRecipeForOutput(2863)
    assert(grindingStone ~= nil, "Rough Grinding Stone recipe should exist")
  `);
});

// 8. Recursive Ground-Up Craft Cost & Savings Test
test('calculates multi-tier recursive ground-up craft costs and savings', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      local prices = {
        [2775] = 200,   -- Iron Ore: 2s (200c)
        [3575] = 1500,  -- Iron Bar on AH: 15s (1500c)
        [3859] = 2500,  -- Steel Bar on AH: 25s (2500c)
      }
      return prices[id] or 0
    end
  `);

  execLua(L, `
    -- Steel Bar requires: 1x Iron Bar (3575) + 1x Coal (3857, vendor: 500c)
    -- Iron Bar can be smelted from 1x Iron Ore (2775, AH: 200c)
    -- Direct craft cost = 1500c (Iron Bar) + 500c (Coal) = 2000c
    -- Ground-up craft cost = 200c (Iron Ore) + 500c (Coal) = 700c
    -- Savings = 1300c (65% saved!)

    local cost = MarketSync.CalculateGroundUpCraftCost(3859)
    assert(cost ~= nil, "Expected cost data for Steel Bar")
    assert(cost.directCraftCost == 2000, "Expected directCraftCost == 2000, got " .. tostring(cost.directCraftCost))
    assert(cost.groundUpCost == 700, "Expected groundUpCost == 700, got " .. tostring(cost.groundUpCost))
    assert(cost.effectiveCost == 700, "Expected effectiveCost == 700, got " .. tostring(cost.effectiveCost))
    assert(cost.savings == 1300, "Expected savings == 1300, got " .. tostring(cost.savings))
    assert(cost.savingsPct == 65, "Expected savingsPct == 65, got " .. tostring(cost.savingsPct))
  `);
});

// 9. Checklist User Overrides Test
test('respects user overrides on intermediate craftables', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      local prices = {
        [2775] = 200,   -- Iron Ore
        [3575] = 1500,  -- Iron Bar
        [3859] = 2500,  -- Steel Bar
      }
      return prices[id] or 0
    end
  `);

  execLua(L, `
    -- Force buy finished Iron Bar directly on AH instead of smelting
    local overrides = { [3575] = false }
    local cost = MarketSync.CalculateGroundUpCraftCost(3859, overrides)

    assert(cost.effectiveCost == 2000, "Effective cost should reflect direct AH purchase when override is false: " .. tostring(cost.effectiveCost))
    assert(cost.savings == 0, "Savings should be 0 when user chooses to buy finished: " .. tostring(cost.savings))

    -- Force craft Iron Bar
    local overridesCraft = { [3575] = true }
    local costCraft = MarketSync.CalculateGroundUpCraftCost(3859, overridesCraft)
    assert(costCraft.effectiveCost == 700, "Effective cost should reflect ground-up craft: " .. tostring(costCraft.effectiveCost))
    assert(costCraft.savings == 1300, "Savings should be 1300: " .. tostring(costCraft.savings))
  `);
});

test('craft requests aggregate selected raw purchases without mixing in finished intermediates', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      return ({ [2775] = 200, [3575] = 1500, [3859] = 2500 })[id] or 0
    end
  `);
  execLua(L, `
    local request = { itemIDs = { 3859 }, quantities = { [3859] = 3 },
      choices = { [3575] = true }, selectedBuys = {} }
    local plan = MarketSync.BuildCraftPurchasePlan(request)
    assert(#plan.recipes == 1 and plan.recipes[1].outputQty == 3)
    assert(plan.buys[2775] and plan.buys[2775].qty == 3, "Expected 3 Iron Ore")
    assert(plan.buys[3857] and plan.buys[3857].qty == 3, "Expected 3 Coal")
    assert(not plan.buys[3575], "Crafted intermediate must not be bought")
    assert(plan.estimatedBuyCost == 2100, "Expected 3 x 700c raw cost")
    request.selectedBuys[2775] = false
    local unchecked = MarketSync.BuildCraftPurchasePlan(request)
    assert(not unchecked.buys[2775] and unchecked.buys[3857].qty == 3,
      "Unchecking ore must omit only ore from export")
    request.choices[3575] = false
    request.selectedBuys[3575] = true
    local finished = MarketSync.BuildCraftPurchasePlan(request)
    assert(finished.buys[3575] and finished.buys[3575].qty == 3)
    assert(not finished.buys[2775], "Buying intermediate must not include its raw input")
    assert(not finished.provided[2775], "Buying parent must not also require provided children")
    request.selectedBuys[3575] = false
    local supplied = MarketSync.BuildCraftPurchasePlan(request)
    assert(supplied.provided[3575] and supplied.provided[3575].qty == 3,
      "Providing parent should be the only terminal requirement for that branch")
    assert(not supplied.buys[2775] and not supplied.provided[2775],
      "Providing parent must not include any lower-tier inputs")
    request.choices[3575] = true
    local restored = MarketSync.BuildCraftPurchasePlan(request)
    assert(restored.buys[3857] and restored.buys[3857].qty == 3,
      "Switching back to Craft should restore the active child requirements")
  `);
});

test('output-less SoD profession actions still build material purchase plans', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      return ({ [4387] = 500, [3575] = 1000, [2835] = 50 })[id] or 0
    end
  `);
  execLua(L, `
    local tinker = { name = "Tinker: Magnetic Displacement", outputQty = 1,
      mats = { { itemID = 4387, qty = 2 }, { itemID = 2835, qty = 1 } } }
    local plan = MarketSync.BuildCraftPurchasePlan({
      recipe = tinker, quantity = 2, choices = { [4387] = false },
      selectedBuys = { [2835] = false },
    })
    assert(#plan.recipes == 1 and plan.recipes[1].itemID == nil,
      "Output-less action must not require a synthetic item ID")
    assert(plan.buys[4387] and plan.buys[4387].qty == 4,
      "Transient plan must calculate repeated material quantities")
    assert(plan.provided[2835] and plan.provided[2835].qty == 2,
      "Provided material choice must survive without an output ID")
    assert(plan.buyUnits == 4 and plan.providedUnits == 2,
      "Summary counts must include only active terminal materials")
  `);
  if (!uiCraftingInfoLua.includes('BuildCurrentCraftRequest(self)') ||
      !uiCraftingInfoLua.includes('BuildCurrentCraftRequest(f)')) {
    throw new Error('Craft tree summary and export must use output-less-safe requests');
  }
});

test('explicit craft choice survives missing AH prices and reports uncertainty', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id) return 0 end
  `);
  execLua(L, `
    local cost = MarketSync.CalculateGroundUpCraftCost(3859, { [3575] = true })
    assert(cost.reagentsTree[1].chooseCraft, "User Craft choice must not be silently changed")
    assert(cost.hasMissing, "Unknown material price must remain visible")
  `);
});

test('craft export replaces the separate shopping snapshot with selected quantities', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      return ({ [2775] = 200, [3575] = 1500, [3859] = 2500 })[id] or 0
    end
    local lists, quantities = {}, {}
    MarketSync.Favorites = {
      GetLists = function() local out = {}; for name in pairs(lists) do out[#out + 1] = name end; return out end,
      CreateList = function(name) lists[name] = {}; quantities[name] = {}; return true end,
      GetList = function(name) return lists[name] end,
      AddToList = function(name, id) lists[name][#lists[name] + 1] = id; return true end,
      RemoveFromList = function(name, id)
        for i, found in ipairs(lists[name]) do if found == id then table.remove(lists[name], i); break end end
      end,
      SetQuantity = function(name, id, qty) quantities[name][id] = qty end,
      GetQuantity = function(name, id) return quantities[name][id] end,
    }
  `);
  execLua(L, `
    local request = { name = "Steel", itemIDs = { 3859 }, quantities = { [3859] = 2 },
      choices = { [3575] = true }, selectedBuys = {} }
    local ok, count, name = MarketSync.ExportCraftPurchasesToShoppingList(request)
    assert(ok and count == 2 and name == "Steel Materials")
    assert(MarketSync.Favorites.GetQuantity(name, 2775) == 2)
    request.selectedBuys[2775] = false
    ok, count = MarketSync.ExportCraftPurchasesToShoppingList(request)
    assert(ok and count == 1 and #MarketSync.Favorites.GetList(name) == 1)
    assert(MarketSync.Favorites.GetList(name)[1] == 3857, "Old unchecked ore must be removed")
  `);
});

test('saved craft plans keep recipe snapshots and farm versus buy choices separate', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      return ({ [900001] = 1000, [900002] = 80, [900003] = 20 })[id] or 0
    end
  `);
  execLua(L, `
    local liveRecipe = { outputItemID = 900001, name = "Test Widget", outputQty = 1,
      mats = { { itemID = 900002, qty = 2 }, { itemID = 900003, qty = 1 } } }
    assert(MarketSync.GetRecipeForOutput(900001) == nil, "Test recipe should not exist in lookup")
    local farm = MarketSync.SaveCraftRequest("Farm Route", liveRecipe, {
      quantity = 3, selectedBuys = { [900002] = false } })
    local buy = MarketSync.SaveCraftRequest("Buy Route", liveRecipe, {
      quantity = 2, selectedBuys = { [900002] = true } })
    assert(farm and buy, "Live profession recipe must save without a lookup hit")
    local saved = MarketSync.ListProcessingCraftSets()
    assert(#saved == 2 and saved[1].name == "Buy Route" and saved[2].name == "Farm Route")
    local buyPlan = MarketSync.BuildCraftPurchasePlan(saved[1])
    local farmPlan = MarketSync.BuildCraftPurchasePlan(saved[2])
    assert(buyPlan.buys[900002].qty == 4 and not buyPlan.provided[900002])
    assert(farmPlan.provided[900002].qty == 6 and not farmPlan.buys[900002])
    assert(farmPlan.buys[900003].qty == 3, "Other ingredients still need buying")
    assert(saved[2].recipes[900001].mats[1].itemID == 900002,
      "Recipe snapshot should remain available for editing offline")
    MarketSync.SaveCraftRequest("Farm Route", liveRecipe, { quantity = 5 })
    local revised = MarketSync.ListProcessingCraftSets()[2]
    assert(#revised.itemIDs == 1 and revised.quantities[900001] == 5,
      "Editing a craft should update its saved quantity without duplicating the recipe")
  `);
});

// 10. Recipe Profit & 5% AH Cut Calculation Test
test('calculates recipe net profit with 5% AH cut', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      local prices = {
        [2775] = 200,   -- Iron Ore
        [3575] = 1500,  -- Iron Bar
        [3859] = 2500,  -- Steel Bar
      }
      return prices[id] or 0
    end
  `);

  execLua(L, `
    local profit = MarketSync.CalculateRecipeProfit(3859)
    assert(profit ~= nil, "Expected profit calculation for Steel Bar")
    assert(profit.grossRevenue == 2500, "Gross revenue should be 2500")
    assert(profit.netRevenue == 2375, "Net revenue after 5% cut should be 2375, got " .. tostring(profit.netRevenue))
    assert(profit.directProfit == 375, "Direct profit should be 2375 - 2000 = 375, got " .. tostring(profit.directProfit))
    assert(profit.groundUpProfit == 1675, "Ground-up profit should be 2375 - 700 = 1675, got " .. tostring(profit.groundUpProfit))
    assert(profit.effectiveMarginPct == 239, "Effective margin % should be 239%, got " .. tostring(profit.effectiveMarginPct))
  `);
});

// 11. Custom Shopping List Generation Test
test('exports custom shopping list reflecting user checklist decisions', () => {
  const L = createLuaState(`
    MarketSync.GetAuctionPrice = function(id)
      local prices = { [2775] = 200, [3575] = 1500 }
      return prices[id] or 0
    end
    Auctionator = {
      API = {
        v1 = {
          CreateShoppingList = function(caller, name, items)
            _G.LastExportedItems = items
            return true
          end,
          ConvertToSearchString = function(caller, term)
            return term.searchString
          end
        }
      }
    }
  `);

  execLua(L, `
    local costCraft = MarketSync.CalculateGroundUpCraftCost(3859, { [3575] = true })
    local ok1, count1 = MarketSync.ExportCustomShoppingList(costCraft.reagentsTree, { [3575] = true }, "Test List 1")
    assert(ok1 == true, "Expected export to succeed")

    local foundIronOre = false
    local foundIronBar = false
    for _, str in ipairs(_G.LastExportedItems or {}) do
      if str:find("2775") or str:find("Iron Ore") then foundIronOre = true end
      if str:find("3575") or str:find("Iron Bar") then foundIronBar = true end
    end
    assert(foundIronOre == true, "Shopping list should contain Iron Ore when intermediate craft is checked")
    assert(foundIronBar == false, "Shopping list should NOT contain Iron Bar when intermediate craft is checked")

    -- Now export when user unchecks craft (buying finished Iron Bar)
    local costBuy = MarketSync.CalculateGroundUpCraftCost(3859, { [3575] = false })
    local ok2, count2 = MarketSync.ExportCustomShoppingList(costBuy.reagentsTree, { [3575] = false }, "Test List 2")
    assert(ok2 == true, "Expected export to succeed")

    foundIronOre = false
    foundIronBar = false
    for _, str in ipairs(_G.LastExportedItems or {}) do
      if str:find("2775") or str:find("Iron Ore") then foundIronOre = true end
      if str:find("3575") or str:find("Iron Bar") then foundIronBar = true end
    end
    assert(foundIronBar == true, "Shopping list should contain Iron Bar when user decides to buy directly")
    assert(foundIronOre == false, "Shopping list should NOT contain Iron Ore when buy is selected")
  `);
});

// 12. Cycle Detection Test
test('handles cyclic dependencies gracefully without infinite recursion', () => {
  const L = createLuaState();
  execLua(L, `
    -- Clear auction prices so cycle items have no price
    MarketSync.GetAuctionPrice = function(id) return nil end

    -- Artificially insert a cycle into IntermediateRecipes
    MarketSync.IntermediateRecipes[9991] = {
      name = "Cycle A", outputItemID = 9991, outputQty = 1,
      mats = { { itemID = 9992, qty = 1 } }
    }
    MarketSync.IntermediateRecipes[9992] = {
      name = "Cycle B", outputItemID = 9992, outputQty = 1,
      mats = { { itemID = 9991, qty = 1 } }
    }

    local cost = MarketSync.CalculateGroundUpCraftCost(9991)
    assert(cost ~= nil, "Cycle detection should terminate safely and return cost structure")
    assert(cost.hasMissing == true, "Cycle with no baseline prices should flag hasMissing")
  `);
});

test('classic crafting info never creates a reagent-label anchor cycle', () => {
  const L = createLuaState();
  execLua(L, `
    local function region(parent)
      local r = { parent = parent, points = {}, scripts = {}, shown = false }
      function r:SetPoint(point, relativeTo, relativePoint, x, y)
        local dependency = relativeTo
        while dependency do
          assert(dependency ~= self, "Cannot anchor to a region dependent on it")
          local anchor = dependency.points and dependency.points[1]
          dependency = anchor and anchor[2] or nil
        end
        self.points[1] = { point, relativeTo, relativePoint, x, y }
      end
      function r:GetPoint(index)
        local anchor = self.points[index or 1]
        if anchor then return table.unpack(anchor) end
      end
      function r:ClearAllPoints() self.points = {} end
      function r:SetSize() end
      function r:SetWidth() end
      function r:SetText() end
      function r:SetJustifyH() end
      function r:SetFrameLevel() end
      function r:GetFrameLevel() return 1 end
      function r:EnableMouse() end
      function r:Enable() self.enabled = true end
      function r:Disable() self.enabled = false end
      function r:SetNormalFontObject() end
      function r:SetHighlightFontObject() end
      function r:SetScript(name, fn) self.scripts[name] = fn end
      function r:RegisterEvent() end
      function r:CreateFontString() return region(self) end
      function r:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
      end
      function r:Hide() self.shown = false end
      function r:IsShown() return self.shown end
      return r
    end
    CreateFrame = function(_, name, parent)
      local frame = region(parent)
      if name then _G[name] = frame end
      return frame
    end
    TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame")
    TradeSkillReagentLabel = CreateFrame("Frame", "TradeSkillReagentLabel", TradeSkillFrame)
    TradeSkillReagentLabel:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 210, -120)
    hooksecurefunc = function(name, fn) if name == "TradeSkillFrame_SetSelection" then onSelection = fn end end
    GetTradeSkillSelectionIndex = function() return 2 end
    GetTradeSkillNumReagents = function() return 1 end
    GetTradeSkillItemLink = function() return "|Hitem:232436|h[Darkclaw Bisque]|h" end
    GetTradeSkillReagentItemLink = function() return "|Hitem:123|h[Reagent]|h" end
    GetTradeSkillReagentInfo = function() return "Reagent", nil, 1 end
    GetTradeSkillInfo = function() return "Darkclaw Bisque" end
    GetTradeSkillNumMade = function() return 1 end
    MarketSyncDB.EnableProfessionCraftInfo = true
    MarketSync.CalculateRecipeProfit = function()
      return { costData = { directCraftCost = 0, groundUpCost = 0, optimalSavings = 0 },
        outputPrice = 0, hasWarnings = false, warnings = {} }
    end
  `);
  execLua(L, uiCraftingInfoLua);
  execLua(L, `
    onSelection()
    onSelection()
    local _, infoRelative = MarketSyncCraftingInfo:GetPoint(1)
    local _, reagentRelative = TradeSkillReagentLabel:GetPoint(1)
    assert(infoRelative == TradeSkillFrame, "Crafting info should use the saved stable Blizzard anchor")
    assert(reagentRelative == MarketSyncCraftingInfo, "Reagent label should sit below crafting info")

    AuctionatorCraftingInfo = CreateFrame("Frame", "AuctionatorCraftingInfo", TradeSkillFrame)
    AuctionatorCraftingInfo:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 210, -100)
    AuctionatorCraftingInfo:Show()
    onSelection()
    local _, restoredRelative = TradeSkillReagentLabel:GetPoint(1)
    assert(restoredRelative == TradeSkillFrame, "Auctionator layout should restore the native reagent anchor")
  `);
});

test('target materials follow client build, not account expansion entitlement', () => {
  const L = createLuaState(`
    GetBuildInfo = function() return "1.60.1", "", "", 160001 end
    GetExpansionLevel = function() return 10 end
  `);
  execLua(L, `
    local targets = MarketSync.GetProcessingTargets()
    local foundVanilla, foundTBC = false, false
    for _, target in ipairs(targets) do
      if target.itemID == 10940 then foundVanilla = true end
      if target.itemID == 22445 then foundTBC = true end
    end
    assert(foundVanilla, "Expected Classic enchanting material")
    assert(not foundTBC, "TBC enchanting material must not appear on a 1.x client")
    assert(not MarketSync.IsProcessingTypeSupported("PROSPECT"), "Prospecting must not appear on a 1.x client")
  `);
});

test('TBC target list rejects later-version outcomes from bundled prospect data', () => {
  const L = createLuaState(`
    GetBuildInfo = function() return "2.5.5", "", "", 20505 end
    GetExpansionLevel = function() return 10 end
    Auctionator = { Prospect = { PROSPECT_TABLE = {
      [2770] = { [999999] = { 1.0 } }
    } } }
  `);
  execLua(L, `
    local targets = MarketSync.GetProcessingTargets()
    local foundGem, foundForeign = false, false
    for _, target in ipairs(targets) do
      if target.itemID == 818 then foundGem = true end
      if target.itemID == 999999 then foundForeign = true end
    end
    assert(foundGem, "TBC prospecting materials should be listed")
    assert(not foundForeign, "Cross-version Auctionator output must not be listed on TBC")
  `);
});

test('craft profit can use another cached character on the same realm', () => {
  const L = createLuaState('');
  execLua(L, `
    MarketSyncDB.KnownCraftingRecipesByCharacter = {
      ["Alt-Faerlina"] = {
        __cacheVersion = 2,
        Alchemy = { cacheVersion = 2, recipes = {
          { name = "Minor Healing Potion", outputItemID = 118, outputQty = 1,
            mats = { { itemID = 2447, qty = 1 }, { itemID = 765, qty = 1 } } }
        } }
      }
    }
    local characters = MarketSync.GetProcessingCraftingCharacters()
    assert(#characters == 2 and characters[1].isCurrent, "Expected current and cached alt")
    local professions = MarketSync.GetProcessingProfessions("Alt-Faerlina")
    assert(#professions == 1 and professions[1] == "Alchemy", "Expected alt's cached profession")
    local crafts = MarketSync.FindProfitableCrafts("Alchemy", 0, "Alt-Faerlina")
    assert(#crafts == 1 and crafts[1].outputItemID == 118, "Expected alt's known recipe")
    assert(crafts[1].craftingCharacter == "Alt-Faerlina", "Expected source character label")
    assert(#MarketSync.FindProfitableCrafts("Alchemy", 0) == 0, "Alt recipes must not be treated as current character's")
  `);
});

test('saved craft sets filter profitability without changing the recipe cache', () => {
  const L = createLuaState('');
  execLua(L, `
    MarketSyncDB.KnownCraftingRecipesByCharacter = {
      ["Alt-Faerlina"] = {
        __cacheVersion = 2,
        Alchemy = { cacheVersion = 2, recipes = {
          { name = "Minor Healing Potion", outputItemID = 118, outputQty = 1,
            mats = { { itemID = 2447, qty = 1 } } },
          { name = "Linen Bandage", outputItemID = 1251, outputQty = 1, recipeIndex = 3275,
            mats = { { itemID = 2592, qty = 1 } } }
        } }
      }
    }
    MarketSyncDB.KnownCraftingRecipesByCharacter["TestChar-Faerlina"] =
      MarketSyncDB.KnownCraftingRecipesByCharacter["Alt-Faerlina"]
    local saved = MarketSync.UpsertProcessingCraftSet("My crafts", { 1251, 1251, 0 })
    assert(saved and #saved.itemIDs == 1 and saved.itemIDs[1] == 1251, "Expected a clean, deduplicated list")
    local lists = MarketSync.ListProcessingCraftSets()
    assert(#lists == 1 and lists[1].name == "My crafts", "Expected persisted craft list")
    assert(MarketSync.GetCraftOutputForRecipeID(123456) == nil, "Unknown recipe cursor must not resolve")
    assert(MarketSync.GetCraftOutputForRecipeID(3275) == 1251, "Recipe cursor should resolve to crafted output")
    MarketSync.UpsertProcessingCraftSet("My crafts", { 1251 }, { [2592] = true })
    local checked = MarketSync.ListProcessingCraftSets()[1]
    assert(checked.checked[2592] == true, "Craft checklist state should persist")
    MarketSync.UpsertProcessingCraftSet("My crafts", { 1251 })
    assert(MarketSync.ListProcessingCraftSets()[1].checked[2592] == true,
      "Updating recipe selections should preserve checklist state")
    local empty = MarketSync.UpsertProcessingCraftSet("Future crafts", {})
    assert(empty and #MarketSync.ListProcessingCraftSets() == 2, "Empty craft list should be creatable")
    assert(MarketSync.DeleteProcessingCraftSet("Future crafts"), "Expected empty list deletion")
    local filtered = MarketSync.FindProfitableCrafts("Alchemy", 0, "Alt-Faerlina", { [1251] = true })
    assert(#filtered == 1 and filtered[1].outputItemID == 1251, "Expected only selected output")
    assert(MarketSync.GetCraftRecipeCount("Alchemy", "Alt-Faerlina") == 2, "Filtering must not alter cached recipes")
    assert(MarketSync.DeleteProcessingCraftSet("My crafts"), "Expected list deletion")
  `);
});

test('cross-character choices exclude incompatible game versions and factions', () => {
  const L = createLuaState(`
    GetBuildInfo = function() return "1.60.1", "", "", 160001 end
    UnitFactionGroup = function() return "Alliance" end
  `);
  execLua(L, `
    local function recipeStore(expansion, faction)
      return { __cacheVersion = 2, __clientExpansion = expansion, __faction = faction,
        Alchemy = { cacheVersion = 2, recipes = {
          { name = "Test craft", outputItemID = 118, mats = { { itemID = 2447, qty = 1 } } }
        } } }
    end
    MarketSyncDB.KnownCraftingRecipesByCharacter = {
      ["Same-Faerlina"] = recipeStore(0, "Alliance"),
      ["OtherFaction-Faerlina"] = recipeStore(0, "Horde"),
      ["OtherVersion-Faerlina"] = recipeStore(1, "Alliance"),
    }
    local choices = MarketSync.GetProcessingCraftingCharacters()
    assert(#choices == 2 and choices[2].key == "Same-Faerlina", "Only compatible alt should be selectable")
    assert(#MarketSync.FindProfitableCrafts("Alchemy", 0, "OtherFaction-Faerlina") == 0,
      "Incompatible faction recipes should not be priced against this character's AH")
    assert(MarketSyncDB.KnownCraftingRecipesByCharacter["OtherVersion-Faerlina"].__clientExpansion == 1,
      "Incompatible alt cache must not be overwritten")
  `);
});

console.log(`\nAll ${passed} profession tests passed successfully!`);
