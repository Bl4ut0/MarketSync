// Automated test suite for MarketSync AH features
const fs = require('fs');
const path = require('path');

const candidateDeps = [
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
  'C:/Users/bl4ut/Documents/Codex/2026-09-16/ok-x20/ItemRack-Forever/node_modules'
];
const deps = candidateDeps.find(p => fs.existsSync(p)) || candidateDeps[0];
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

const marketSyncDir = path.resolve(__dirname, '../MarketSync');

function test(name, fn) {
  try {
    fn();
    console.log(`PASS ${name}`);
  } catch (err) {
    console.error(`FAIL ${name}: ${err.message}`);
    process.exit(1);
  }
}

test('Sidecar.ScanBagsForSelling groups by bag container', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    time = function() return 1773780000 end
    GetTime = function() return 1000 end
    NUM_BAG_SLOTS = 4
    C_Container = {
      GetContainerNumSlots = function(bag)
        if bag == 0 then return 16
        elseif bag == 1 then return 16
        else return 0 end
      end,
      GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then
          return { itemID = 13444, stackCount = 5, isBound = false, isLocked = false, quality = 2, hyperlink = "item:13444" }
        elseif bag == 1 and slot == 2 then
          return { itemID = 13446, stackCount = 20, isBound = false, isLocked = false, quality = 3, hyperlink = "item:13446" }
        end
        return nil
      end,
      ContainerIDToInventoryID = function(bag) return 20 + bag end
    }
    GetInventoryItemLink = function(unit, inv) return "Travelers Backpack" end
    GetInventoryItemTexture = function(unit, inv) return 133633 end
    SafeGetItemInfo = function(id) return "Mock Item " .. tostring(id), nil, 2, nil, nil, nil, nil, nil, nil, 134400, nil, 0 end
    C_Item = { GetItemInfo = SafeGetItemInfo }
    CreateFrame = function() return { SetScript = function() end, SetSize = function() end, SetPoint = function() end, SetBackdrop = function() end, CreateTexture = function() return {} end, CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end, Hide = function() end, Show = function() end, IsShown = function() return true end } end
    hooksecurefunc = function() end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mock));

  const sidecarLua = fs.readFileSync(path.join(marketSyncDir, 'UI_AHSidecar.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(sidecarLua)) !== 0) {
    throw new Error('Failed to load UI_AHSidecar.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const checkScript = `
    local bags = MarketSync.AHSidecar.ScanBagsForSelling()
    assert(#bags >= 2, "expected at least 2 bags")
    assert(bags[1].name == "Backpack", "bag 0 must be Backpack")
    assert(#bags[1].items == 1, "backpack must have 1 item")
    assert(bags[1].items[1].itemID == 13444, "item must be 13444")
    assert(bags[1].items[1].stackCount == 5, "stackCount must be 5")
    assert(#bags[2].items == 1, "bag 1 must have 1 item")
    assert(bags[2].items[1].itemID == 13446, "item must be 13446")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(checkScript)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Scanner cooldown remaining and multi-list scanning', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    time = function() return 1773780000 end
    GetTime = function() return 1000 end
    MarketSync = {
      IsAuctionHouseOpen = true,
      GetRealmDB = function() return { PersonalData = {} } end,
      Favorites = {
        GetListItems = function(name)
          if name == "ListA" then return { { itemID = 1001 }, { itemID = 1002 } } end
          if name == "ListB" then return { { itemID = 1002 }, { itemID = 1003 } } end
          return {}
        end
      }
    }
    MarketSyncDB = { LastFullScanAt = 1773780000 - 300 }
    C_AuctionHouse = { SendSearchQuery = function() end }
    C_Timer = { After = function(delay, cb) end }
    CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mock));

  const scannerLua = fs.readFileSync(path.join(marketSyncDir, 'Scanner.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(scannerLua)) !== 0) {
    throw new Error('Failed to load Scanner.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const checkScript = `
    local S = MarketSync.Scanner
    local cd = S.GetFullScanCooldownRemaining()
    assert(cd == 600, "expected 600s cooldown remaining, got " .. tostring(cd))

    local ok = S.ScanMultipleLists({ "ListA", "ListB" })
    assert(ok == true, "ScanMultipleLists should return true")
    assert(S.Progress.total == 3, "expected 3 unique items in queue, got " .. tostring(S.Progress.total))
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(checkScript)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

console.log('\nAll AH feature tests passed successfully!');
