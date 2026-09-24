// Automated test suite for MarketSync Modern Professions & First Aid (Health) consolidation
const fs = require('fs');
const path = require('path');

const candidateDeps = [
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
  'C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/ItemRack-Forever/node_modules'
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

console.log(`\nAll ${passed} profession tests passed successfully!`);
