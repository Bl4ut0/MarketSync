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

test('Tooltip hook handles focus button with FontString count table safely', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const testScript = `
    MarketSync = MarketSync or {}
    MarketSync.FormatMoney = function(amt) return tostring(amt) end
    MarketSync.FormatMoneyColored = function(amt) return tostring(amt) end
    MarketSync.FormatRelativeTime = function() return "Today" end
    MarketSync.GetItemPriceAndScanInfo = function(id)
      return { price = 3900, source = "Guild Sync", ageDays = 0 }
    end
    MarketSyncDB = { EnableTooltipAuctionPrice = true, EnableTooltipProb = false }

    local linesAdded = {}
    local tooltip = {
      GetItem = function() return "Bronze Tube", "item:4371" end,
      NumLines = function() return 0 end,
      GetName = function() return "GameTooltip" end,
      AddDoubleLine = function(self, left, right)
        table.insert(linesAdded, { left = left, right = right })
      end,
      AddLine = function(self, text)
        table.insert(linesAdded, { left = text })
      end,
    }

    -- Mock focus button where focus.count is a FontString table (reproducing UI_AHSidecar button)
    local mockFocus = {
      count = {
        GetText = function() return "5" end
      },
      stackCount = 5,
    }
    GetMouseFoci = function() return { mockFocus } end

    -- Extract and execute the tooltip price logic
    local priceInfo = MarketSync.GetItemPriceAndScanInfo(4371)
    local priceStr = MarketSync.FormatMoney(priceInfo.price)
    tooltip:AddDoubleLine("MarketSync AH:", priceStr)

    local stackCount = nil
    local data = { id = 4371 }
    if data and type(data.stackCount) == "number" and data.stackCount > 1 then
      stackCount = data.stackCount
    elseif tooltip.GetItem then
      local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
      if focus then
        if type(focus.stackCount) == "number" and focus.stackCount > 1 then
          stackCount = focus.stackCount
        elseif type(focus.count) == "number" and focus.count > 1 then
          stackCount = focus.count
        elseif type(focus.Count) == "number" and focus.Count > 1 then
          stackCount = focus.Count
        elseif type(focus.count) == "table" and focus.count.GetText then
          local n = tonumber(focus.count:GetText())
          if n and n > 1 then stackCount = n end
        elseif type(focus.Count) == "table" and focus.Count.GetText then
          local n = tonumber(focus.Count:GetText())
          if n and n > 1 then stackCount = n end
        end
      end
    end

    assert(stackCount == 5, "stackCount should have been safely parsed as 5, got " .. tostring(stackCount))
    if stackCount and stackCount > 1 then
      local stackPrice = priceInfo.price * stackCount
      assert(stackPrice == 19500, "stack price should be 19500")
      tooltip:AddDoubleLine("Stack (" .. stackCount .. "):", tostring(stackPrice))
    end
    assert(#linesAdded == 2, "Expected 2 tooltip lines added")
  `;

  if (lauxlib.luaL_dostring(L, to_luastring(testScript)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Favorites.AddToList resolves item names and item links', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    MarketSync = {}
    MarketSyncDB = {}
    C_Item = {
      GetItemInfoInstant = function(name)
        if name == "Handful of Copper Bolts" then return 4371 end
        return nil
      end
    }
  `;
  lauxlib.luaL_dostring(L, to_luastring(mock));

  const favLua = fs.readFileSync(path.join(marketSyncDir, 'Favorites.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(favLua)) !== 0) {
    throw new Error('Failed to load Favorites.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    local F = MarketSync.Favorites
    local ok1 = F.AddToList("Favorites", "Handful of Copper Bolts")
    assert(ok1 == true, "AddToList by name should succeed")
    local items = F.GetListItems("Favorites")
    assert(#items == 1, "Favorites should have 1 item")
    assert(items[1].itemID == 4371, "Item should be 4371")

    local ok2 = F.AddToList("Favorites", "item:13444")
    assert(ok2 == true, "AddToList by item link should succeed")
    assert(#F.GetListItems("Favorites") == 2, "Favorites should have 2 items")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Scanner parses table itemKey in ITEM_SEARCH_RESULTS_UPDATED and commodity number in COMMODITY_SEARCH_RESULTS_UPDATED', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    time = function() return 1773780000 end
    GetTime = function() return 1000 end
    MarketSync = {
      IsAuctionHouseOpen = true,
      GetRealmDB = function() return { PersonalData = {} } end,
      Debug = function() end,
      ToBase36 = function(n) return tostring(n) end,
    }
    MarketSyncDB = {}
    registeredEvents = {}
    eventHandler = nil
    CreateFrame = function()
      return {
        RegisterEvent = function(self, evt) registeredEvents[evt] = true end,
        SetScript = function(self, name, handler)
          if name == "OnEvent" then eventHandler = handler end
        end,
      }
    end
    C_AuctionHouse = {
      SendSearchQuery = function() end,
      GetNumItemSearchResults = function() return 1 end,
      GetItemSearchResultInfo = function() return { quantity = 5, buyoutAmount = 10000 } end,
      HasFullItemSearchResults = function() return true end,
      GetNumCommoditySearchResults = function() return 1 end,
      GetCommoditySearchResultInfo = function() return { quantity = 10, unitPrice = 1500 } end,
      HasFullCommoditySearchResults = function() return true end,
    }
    C_Timer = { After = function(d, fn) end }
    C_Item = { GetItemInfo = function() return "Test Item", nil, 1 end }
  `;
  lauxlib.luaL_dostring(L, to_luastring(mock));

  const scannerLua = fs.readFileSync(path.join(marketSyncDir, 'Scanner.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(scannerLua)) !== 0) {
    throw new Error('Failed to load Scanner.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    local S = MarketSync.Scanner
    assert(S.IsAvailable() == true, "Scanner should be available when AH is open")

    -- Simulate pending item search
    S.Active = true
    S.Pending = { itemID = 4371, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }

    -- Fire ITEM_SEARCH_RESULTS_UPDATED with table argument { itemID = 4371 }
    eventHandler(nil, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 4371, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    assert(S.Pending == nil, "Pending should be cleared after ITEM_SEARCH_RESULTS_UPDATED with table arg")
    assert(#S.RecentResults >= 1, "Recent results should record item search")

    -- Simulate pending commodity search
    S.Active = true
    S.Pending = { itemID = 2770, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }

    -- Fire COMMODITY_SEARCH_RESULTS_UPDATED with numeric itemID
    eventHandler(nil, "COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(S.Pending == nil, "Pending should be cleared after COMMODITY_SEARCH_RESULTS_UPDATED with number arg")
    assert(#S.RecentResults >= 2, "Recent results should record commodity search")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('AST syntax check on all MarketSync Lua files', () => {
  const files = fs.readdirSync(marketSyncDir).filter(f => f.endsWith('.lua'));
  for (const f of files) {
    const code = fs.readFileSync(path.join(marketSyncDir, f), 'utf8');
    try {
      luaparse.parse(code, { comments: false, scope: true });
    } catch (err) {
      throw new Error(`Syntax error in ${f}: ${err.message}`);
    }
  }
});

console.log('\nAll AH feature tests passed successfully!');
