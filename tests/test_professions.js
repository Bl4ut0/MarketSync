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
const processingLua = fs.readFileSync(path.join(marketSyncDir, 'Processing.lua'), 'utf8');
const uiProcessingLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Processing.lua'), 'utf8');
const uiBrowseLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Browse.lua'), 'utf8');

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
    { name: 'Processing.lua', content: processingLua },
    { name: 'UI_Processing.lua', content: uiProcessingLua },
    { name: 'UI_Browse.lua', content: uiBrowseLua },
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

// 4. Secondary Profession Detection & Health Consolidation Test
test('consolidates bandages and health potions under First Aid (Health)', () => {
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
    assert(#crafts > 0, "Expected profitable crafts for First Aid (Health)")

    local foundBandage = false
    local foundPotion = false
    for _, craft in ipairs(crafts) do
      if craft.outputItemID == 1251 then foundBandage = true end
      if craft.outputItemID == 118 then foundPotion = true end
    end

    assert(foundBandage == true, "Expected Linen Bandage in First Aid (Health) crafts")
    assert(foundPotion == true, "Expected Minor Healing Potion in First Aid (Health) crafts")
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
  `);
});

console.log(`\nAll ${passed} profession tests passed successfully!`);
