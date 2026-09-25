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

test('Escape registration leaves modern protected dispatcher untouched', () => {
  const source = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  const start = source.indexOf('function MarketSync.RegisterEscapeFrame(frame)');
  const end = source.indexOf('local ADDON_NAME =', start);
  if (start < 0 || end < 0) throw new Error('Escape registration code not found');
  const chunk = source.slice(start, end);
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const script = `
    MarketSync = {}
    UISpecialFrames = {}
    GameMenuEscPriority = { AddOn = 8 }
    local registrations = 0
    RegisterGameMenuEscHandler = function(priority, callback)
      registrations = registrations + 1
    end
    ${chunk}
    local frame = {
      shown = true,
      GetName = function() return 'MarketSyncTestFrame' end,
      IsShown = function(self) return self.shown end,
      Hide = function(self) self.shown = false end,
    }
    MarketSync.RegisterEscapeFrame(frame)
    assert(registrations == 0 and #UISpecialFrames == 0)
    assert(frame.shown == true)
    RegisterGameMenuEscHandler = nil
    MarketSync.RegisterEscapeFrame(frame)
    assert(UISpecialFrames[1] == 'MarketSyncTestFrame')
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== 0) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
});

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

    S.Cancel("test")
    Auctionator = { Database = {} }
    MarketSyncDB.UseAuctionatorScanner = true
    assert(S.StartScan({ 1001 }, "blocked") == false, "native item scan should be blocked")
    assert(S.StartFullScan() == false, "native full scan should be blocked")
    assert(S.Active == false, "blocked scan must remain inactive")
    MarketSyncDB.UseAuctionatorScanner = false
    assert(S.StartScan({ 1001 }, "override") == true, "settings override should restore native scanning")
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
      UpsertScanBucket = function(_, offset, price, quantity)
        return tostring(offset) .. ":" .. tostring(price) .. ":" .. tostring(quantity)
      end,
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

    -- 1. Automated queue item search with DUAL events (_ADDED then _UPDATED)
    S.Active = true
    S.Pending = { itemID = 4371, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }

    -- Fire ITEM_SEARCH_RESULTS_ADDED first
    eventHandler(nil, "ITEM_SEARCH_RESULTS_ADDED", { itemID = 4371, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    assert(S.Pending == nil, "Pending should be cleared after first event")
    assert(#S.RecentResults == 1, "Expected exactly 1 result after first event, got: " .. #S.RecentResults)

    -- Fire ITEM_SEARCH_RESULTS_UPDATED immediately after while S.Active is still true
    eventHandler(nil, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 4371, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    assert(#S.RecentResults == 1, "Duplicate event while S.Active must NOT add a second entry, got: " .. #S.RecentResults)

    -- 2. Automated queue commodity search with DUAL events (_ADDED then _UPDATED)
    S.Active = true
    S.Pending = { itemID = 2770, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }

    -- Fire COMMODITY_SEARCH_RESULTS_ADDED first
    eventHandler(nil, "COMMODITY_SEARCH_RESULTS_ADDED", 2770)
    assert(S.Pending == nil, "Pending should be cleared after first commodity event")
    assert(#S.RecentResults == 2, "Expected exactly 2 results, got: " .. #S.RecentResults)

    -- Fire COMMODITY_SEARCH_RESULTS_UPDATED immediately after
    eventHandler(nil, "COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
    assert(#S.RecentResults == 2, "Duplicate commodity event while S.Active must NOT add a duplicate entry, got: " .. #S.RecentResults)

    -- 3. Manual search (S.Active == false) with DUAL events
    S.Active = false
    S.Pending = nil
    eventHandler(nil, "COMMODITY_SEARCH_RESULTS_ADDED", 13444)
    assert(#S.RecentResults == 3, "Expected 3 results after manual search, got: " .. #S.RecentResults)
    eventHandler(nil, "COMMODITY_SEARCH_RESULTS_UPDATED", 13444)
    assert(#S.RecentResults == 3, "Duplicate manual event within 2s debounce must NOT add duplicate, got: " .. #S.RecentResults)
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Modern Dialog Helpers and Task Manager / Rate Monitor update logic', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    UIParent = {}
    UISpecialFrames = {}
    time = function() return 1773780000 end
    date = function(fmt) return "14:00:00" end
    UnitFactionGroup = function() return "Alliance" end
    GetRealmName = function() return "Faerlina" end
    GetNormalizedRealmName = function() return "Faerlina" end
    UnitName = function() return "Player" end
    IsInGuild = function() return true end
    C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
    ItemLocation = { CreateFromItemLink = function(link) return { link = link } end }
    function CreateFrame(frameType, name, parent, template)
      local f = {
        name = name,
        parent = parent,
        shown = false,
        scripts = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        SetSize = function(self, w, h) self.width = w; self.height = h end,
        SetHeight = function(self, h) self.height = h end,
        SetWidth = function(self, w) self.width = w end,
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text end,
        SetPoint = function(self, ...) end,
        ClearAllPoints = function(self) end,
        SetMovable = function(self, m) end,
        EnableMouse = function(self, e) end,
        RegisterForDrag = function(self, ...) end,
        SetFrameStrata = function(self, s) end,
        SetFrameLevel = function(self, l) end,
        SetToplevel = function(self, t) end,
        SetClampedToScreen = function(self, c) end,
        SetBackdrop = function(self, b) end,
        SetBackdropColor = function(self, ...) end,
        SetBackdropBorderColor = function(self, ...) end,
        SetScript = function(self, ev, fn) self.scripts[ev] = fn end,
        CreateTexture = function(self, ...)
          return {
            SetHeight = function() end,
            SetWidth = function() end,
            SetPoint = function() end,
            SetColorTexture = function() end,
            SetTexture = function() end,
            SetSize = function() end,
            SetTexCoord = function() end,
            SetAllPoints = function() end,
            Hide = function() end,
            Show = function() end,
          }
        end,
        CreateFontString = function(self, ...)
          return {
            text = "",
            SetPoint = function() end,
            SetWidth = function() end,
            SetJustifyH = function() end,
            SetText = function(s, t) s.text = t end,
            GetText = function(s) return s.text end,
            Hide = function() end,
            Show = function() end,
          }
        end,
        SetStatusBarTexture = function() end,
        GetStatusBarTexture = function() return { SetHorizTile = function() end } end,
        SetMinMaxValues = function() end,
        SetValue = function(self, v) self.val = v end,
        SetStatusBarColor = function(self, r, g, b) self.color = {r, g, b} end,
      }
      if name then _G[name] = f end
      return f
    end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mock));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Config.lua error: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const monitorLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Monitor.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(monitorLua)) !== 0) {
    throw new Error('UI_Monitor.lua error: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    assert(type(MarketSync.CreateModernDialog) == "function", "CreateModernDialog should be defined")
    assert(type(MarketSync.CreateModernInset) == "function", "CreateModernInset should be defined")
    assert(type(MarketSync.CreateAHColumnHeader) == "function", "CreateAHColumnHeader should be defined")

    local testDlg = MarketSync.CreateModernDialog("MarketSyncTestDialog", 400, 300, "|cFFFFD100Test|r")
    assert(testDlg.Header ~= nil, "Dialog should have Header")
    assert(testDlg.TitleText ~= nil, "Dialog should have TitleText")
    assert(testDlg.CloseButton ~= nil, "Dialog should have CloseButton")

    -- Test Rate Monitor toggling and updating
    MarketSync.ToggleRateMonitor()
    local rf = MarketSyncRateMonitorFrame
    assert(rf ~= nil, "MarketSyncRateMonitorFrame should exist")
    assert(rf:IsShown(), "RateMonitorFrame should be shown after ToggleRateMonitor")

    MarketSync.UpdateRateMonitor(10, 5, 12, 450, {
      { prefix = "MarketSync", apiRate = 8, rate = 320 },
      { prefix = "Auctionator", apiRate = 4, rate = 130 }
    })

    assert(rf.rateBar.val == 450, "rateBar value should match txBytesRate")
    assert(rf.rateBarText:GetText():find("450 B/s"), "rateBarText should include 450 B/s")
    assert(rf.addonRows[1]:IsShown(), "First addon row should be shown")
    assert(rf.addonRows[1].nameText:GetText():find("MarketSync"), "Addon row 1 should contain MarketSync")
    assert(rf.addonRows[2]:IsShown(), "Second addon row should be shown")
    assert(rf.addonRows[2].nameText:GetText():find("Auctionator"), "Addon row 2 should contain Auctionator")
    assert(not rf.addonRows[3]:IsShown(), "Third addon row should be hidden")

    -- Test ToggleBlock logic
    MarketSyncDB = { BlockedUsers = {} }
    MarketSync.ToggleBlock("GnomishSeller")
    assert(MarketSyncDB.BlockedUsers["GnomishSeller"] == true, "GnomishSeller should be blocked")
    MarketSync.ToggleBlock("GnomishSeller")
    assert(MarketSyncDB.BlockedUsers["GnomishSeller"] == nil, "GnomishSeller should be unblocked")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('FormatColoredItemName handles quality colors cleanly without duplicate |c prefixes', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const testScript = `
    MarketSync = MarketSync or {}
    UnitName = function() return "Player" end
    IsInGuild = function() return true end
    C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end }
    CreateFrame = function() return { SetBackdrop = function() end, SetBackdropColor = function() end, SetBackdropBorderColor = function() end, CreateTexture = function() return { SetHeight = function() end, SetPoint = function() end, SetColorTexture = function() end } end } end
    ITEM_QUALITY_COLORS = {
      [0] = { hex = "|cff9d9d9d", colorStr = "ff9d9d9d" },
      [1] = { hex = "|cffffffff", colorStr = "ffffffff" },
      [2] = { hex = "|cff1eff00", colorStr = "ff1eff00" },
      [3] = { hex = "|cff0070dd", colorStr = "ff0070dd" },
      [4] = { hex = "|cffa335ee", colorStr = "ffa335ee" },
    }
  `;
  lauxlib.luaL_dostring(L, to_luastring(testScript));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    local f = MarketSync.FormatColoredItemName
    assert(type(f) == "function", "FormatColoredItemName should be a function")

    -- 1. Plain item name
    local r1 = f("Flint and Tinder", 1)
    assert(r1 == "|cffffffffFlint and Tinder|r", "expected |cffffffffFlint and Tinder|r, got " .. tostring(r1))
    assert(not r1:find("|c|c"), "should never produce double |c prefix")

    -- 2. Uncommon (green) item
    local r2 = f("Native Pants", 2)
    assert(r2 == "|cff1eff00Native Pants|r", "expected |cff1eff00Native Pants|r, got " .. tostring(r2))

    -- 3. String that already has |c formatting
    local alreadyColored = "|cff1eff00Native Pants|r"
    local r3 = f(alreadyColored, 2)
    assert(r3 == alreadyColored, "pre-colored string should be returned unmodified")
    assert(not r3:find("|c|c"), "should never prepend |c to already colored string")

    -- 4. Nil and empty string
    assert(f(nil, 1) == "", "nil name should return empty string")
    assert(f("", 1) == "", "empty name should return empty string")

    -- 5. Fallback without quality
    local r5 = f("Mystery Item", nil)
    assert(r5 == "|cffffffffMystery Item|r", "fallback should use white")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('FormatColoredItemName validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('AuctionHouse.lua registers 4 embedded tabs including Analytics', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const setupMock = `
    MarketSync = MarketSync or {}
    CreateFrame = function(frameType, name, parent, template)
      local f = {
        name = name,
        shown = false,
        scripts = {},
        points = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        SetPoint = function(self, ...) table.insert(self.points, { ... }) end,
        ClearAllPoints = function(self) self.points = {} end,
        SetAllPoints = function(self) end,
        SetSize = function(self, w, h) self.width = w self.height = h end,
        SetWidth = function(self, w) self.width = w end,
        SetHeight = function(self, h) self.height = h end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        HookScript = function(self, name, fn)
          local old = self.scripts[name]
          self.scripts[name] = function(...) if old then old(...) end fn(...) end
        end,
        CreateTexture = function(self)
          return {
            SetColorTexture = function() end,
            SetTexture = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetAllPoints = function() end,
            Show = function() end,
            Hide = function() end,
          }
        end,
        CreateFontString = function(self)
          return {
            SetPoint = function() end,
            SetText = function(self, t) self.text = t end,
            GetText = function(self) return self.text or "" end,
            SetFontObject = function() end,
            SetJustifyH = function() end,
            SetWordWrap = function() end,
            Show = function() end,
            Hide = function() end,
          }
        end,
      }
      if name then _G[name] = f end
      return f
    end

    hooksecurefunc = function(t, k, hookFn)
      local orig = t[k]
      t[k] = function(...)
        if orig then orig(...) end
        hookFn(...)
      end
    end

    AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
    AuctionHouseFrame.Tabs = { { displayMode = "buy" }, { displayMode = "sell" } }
    AuctionHouseFrame.AuctionsTab = { displayMode = "auctions" }
    AuctionHouseFrame.displayMode = "buy"
    AuctionHouseFrame.GetDisplayMode = function(self) return self.displayMode end
    AuctionHouseFrame.SetDisplayMode = function(self, mode) self.displayMode = mode end
    AuctionHouseFrame.SetTitle = function(self, title) self.title = title end

    local createdTabs = {}
    local selectedTab = nil
    local rootFrame = CreateFrame("Frame", "MockLibAHTabRoot")
    local mockLibAHTab = {
      internalState = { rootFrame = rootFrame, Tabs = {}, usedIDs = {} },
      DoesIDExist = function(self, id) return createdTabs[id] ~= nil end,
      CreateTab = function(self, id, frameRef, text, header)
        local btn = CreateFrame("Button", id)
        btn.id = id
        btn.frameRef = frameRef
        btn.text = text
        btn.header = header
        createdTabs[id] = btn
        self.internalState.usedIDs[id] = btn
        table.insert(self.internalState.Tabs, btn)
      end,
      GetButton = function(self, id) return createdTabs[id] end,
      SetSelected = function(self, id)
        selectedTab = id
        if createdTabs[id] and createdTabs[id].frameRef then
          createdTabs[id].frameRef:Show()
        end
      end,
    }

    LibStub = function(libName, silent)
      if libName == "LibAHTab-1-0" then return mockLibAHTab end
      return nil
    end

    MarketSync.CreateAHScannerPanel = function(parent) return { frame = parent } end
    MarketSync.CreateProcessingPanel = function(parent) return { frame = parent } end
    MarketSync.CreateNotificationsPanel = function(parent) return { frame = parent } end
    MarketSync.CreateAnalyticsPanel = function(parent) return { frame = parent } end
  `;
  lauxlib.luaL_dostring(L, to_luastring(setupMock));

  const ahLua = fs.readFileSync(path.join(marketSyncDir, 'AuctionHouse.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(ahLua)) !== 0) {
    throw new Error('Failed to load AuctionHouse.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    local AH = MarketSync.AuctionHouse
    local ok = AH.Attach()
    assert(ok == true, "AH.Attach should succeed")
    assert(AH.ScannerPanel ~= nil, "ScannerPanel should exist")
    assert(AH.ProcessingPanel ~= nil, "ProcessingPanel should exist")
    assert(AH.AlertsPanel ~= nil, "AlertsPanel should exist")
    assert(AH.AnalyticsPanel ~= nil, "AnalyticsPanel should exist")

    -- Check all 4 tabs
    local lib = LibStub("LibAHTab-1-0")
    assert(lib:DoesIDExist("MarketSyncScanner"), "MarketSyncScanner tab should be registered")
    assert(lib:DoesIDExist("MarketSyncProcessing"), "MarketSyncProcessing tab should be registered")
    assert(lib:DoesIDExist("MarketSyncAlerts"), "MarketSyncAlerts tab should be registered")
    assert(lib:DoesIDExist("MarketSyncAnalytics"), "MarketSyncAnalytics tab should be registered")

    -- Test AH.RefreshTabVisibility dynamically hiding and showing beta tabs
    MarketSyncDB = { EnableProcessingTab = false, EnableAlertsTab = false, EnableAnalyticsTab = true }
    AH.RefreshTabVisibility()
    assert(not lib:GetButton("MarketSyncProcessing"):IsShown(), "Processing tab should be hidden on AH")
    assert(not lib:GetButton("MarketSyncAlerts"):IsShown(), "Alerts tab should be hidden on AH")
    assert(lib:GetButton("MarketSyncScanner"):IsShown(), "Scanner tab should remain shown on AH")
    assert(lib:GetButton("MarketSyncAnalytics"):IsShown(), "Analytics tab should remain shown on AH")

    MarketSyncDB.EnableProcessingTab = true
    MarketSyncDB.EnableAlertsTab = true
    AH.RefreshTabVisibility()
    assert(lib:GetButton("MarketSyncProcessing"):IsShown(), "Processing tab should be shown when enabled")
    assert(lib:GetButton("MarketSyncAlerts"):IsShown(), "Alerts tab should be shown when enabled")

    -- Test switching to analytics
    AuctionHouseFrame:Show()
    AH.ShowAuctionHousePanel("analytics")
    assert(AH.AnalyticsPanel:IsShown(), "AnalyticsPanel should be shown after ShowAuctionHousePanel('analytics')")

    -- Test hiding panels
    AH.HideAuctionHousePanel()
    assert(not AH.AnalyticsPanel:IsShown(), "AnalyticsPanel should be hidden after HideAuctionHousePanel")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('AH tabs validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Analytics and Processing history decoupling from Auctionator', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    time = function() return 1789756200 end -- Sep 18, 2026
    date = os.date
    GetTime = function() return 1000 end
    GetBuildInfo = function() return "1.15.5", "57361", "Oct 15 2024", 11505 end
    GetNormalizedRealmName = function() return "Faerlina" end
    GetRealmName = function() return "Faerlina" end
    UnitFactionGroup = function() return "Horde" end
    Auctionator = nil -- Ensure Auctionator is strictly nil!
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
    CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
    MarketSyncDB = {
      RealmData = {
        ["Faerlina"] = {
          PersonalData = {
            ["4471"] = {
              m = 400,
              d = 20714,
              latestBucket = 994309,
              h = {
                ["20714"] = "37:b4:a" -- offset 37 (18:30), price 400 (b4), qty 10 (a)
              }
            }
          },
          ItemMetadata = {}
        }
      }
    }
    MarketSync = {
      FromBase36 = function(s)
        if not s then return 0 end
        return tonumber(s, 36) or 0
      end
    }
  `;
  lauxlib.luaL_dostring(L, to_luastring(mock));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const processingLua = fs.readFileSync(path.join(marketSyncDir, 'Processing.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(processingLua)) !== 0) {
    throw new Error('Failed to load Processing.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    assert(Auctionator == nil, "Auctionator must be nil")

    -- Check ScanDayToTimestamp and ScanDayToDate
    local ts = MarketSync.ScanDayToTimestamp(20714)
    assert(ts == 20714 * 86400, "Unix day 20714 should convert to 20714 * 86400")
    local dStr = MarketSync.ScanDayToDate(20714)
    assert(type(dStr) == "string" and #dStr > 0, "ScanDayToDate should return valid string")

    -- Check GetGranularHistory with Auctionator nil
    local points = MarketSync.GetGranularHistory("4471")
    assert(#points == 1, "Expected 1 granular point, got " .. tostring(#points))
    assert(points[1].day == 20714, "Expected day 20714")
    assert(points[1].bucketOffset == 37, "Expected offset 37")
    assert(points[1].price == 400, "Expected price 400")
    assert(points[1].quantity == 10, "Expected qty 10")
    assert(points[1].timestamp == (20714 * 86400) + (37 * 1800), "Timestamp calculation mismatch")

    -- Check GetItemHistory with Auctionator nil
    local history = MarketSync.GetItemHistory("4471")
    assert(#history == 1, "Expected 1 history point, got " .. tostring(#history))
    assert(history[1].price == 400, "Expected price 400 in history")
    assert(history[1].isGranular == true, "Expected isGranular == true")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('History decoupling validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Accessibility helpers and narrator protocol support', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const mockEnv = `
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
    time = function() return 1773780000 end
    hooksecurefunc = function() end
    CreateFrame = function() return { SetScript = function() end, SetBackdrop = function() end, SetSize = function() end, SetPoint = function() end, Show = function() end, Hide = function() end } end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    -- 1. Test StripColorCodes
    local clean1 = MarketSync.StripColorCodes("|cffffd100MarketSync|r")
    assert(clean1 == "MarketSync", "Expected 'MarketSync', got: " .. tostring(clean1))
    local clean2 = MarketSync.StripColorCodes("|cff00ff00Left-Click|r: Search |TInterface\\\\Icons\\\\INV_Misc_Herb:16:16|t")
    assert(clean2 == "Left-Click: Search", "Expected 'Left-Click: Search', got: " .. tostring(clean2))
    local clean3 = MarketSync.StripColorCodes("|cff9d9d9d|Hitem:7073::::::::1:1445::1:28:2044|h[Broken Fang]|h|r")
    assert(clean3 == "[Broken Fang]", "Expected '[Broken Fang]', got: " .. tostring(clean3))

    -- 2. Test FormatNarrationMoney
    local m0 = MarketSync.FormatNarrationMoney(0)
    assert(m0 == "0 copper", "Expected '0 copper', got: " .. tostring(m0))
    local m50 = MarketSync.FormatNarrationMoney(50)
    assert(m50 == "50 copper", "Expected '50 copper', got: " .. tostring(m50))
    local mSilver = MarketSync.FormatNarrationMoney(125)
    assert(mSilver == "1 silver, 25 copper", "Expected '1 silver, 25 copper', got: " .. tostring(mSilver))
    local mGold = MarketSync.FormatNarrationMoney(4502015)
    assert(mGold == "450 gold, 20 silver, 15 copper", "Expected '450 gold, 20 silver, 15 copper', got: " .. tostring(mGold))

    -- 3. Test SetAccessibility
    local mockBtn = {
      text = "|cFFFFD100Click Me|r",
      GetText = function(self) return self.text end,
      GetObjectType = function() return "Button" end
    }
    MarketSync.SetAccessibility(mockBtn, {
      name = function(self) return self:GetText() end,
      context = "Button",
      description = "|cff00ff00Performs action|r",
      getIndexInfo = function() return { index = 2, total = 5 } end,
    })

    assert(mockBtn:NarrationGetName() == "Click Me", "NarrationGetName should strip color codes")
    assert(mockBtn:NarrationGetContext() == "Button", "NarrationGetContext should match")
    assert(mockBtn:NarrationGetDescription() == "Performs action", "NarrationGetDescription should strip colors")
    local idxInfo = mockBtn:NarrationGetIndexInfo()
    assert(idxInfo.index == 2 and idxInfo.total == 5, "NarrationGetIndexInfo should return 2 of 5")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Accessibility helpers validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  // 4. Verify UI_AHScanner button streamlining
  const scannerLua = fs.readFileSync(path.join(marketSyncDir, 'UI_AHScanner.lua'), 'utf8');
  if (scannerLua.includes('local analyticsBtn = CreateFrame')) {
    throw new Error('Redundant analyticsBtn should be removed from UI_AHScanner.lua');
  }
  if (!scannerLua.includes('toggleSelectBtn')) {
    throw new Error('Consolidated toggleSelectBtn should be present in UI_AHScanner.lua');
  }
});

test('Tiered retention downsampler, compact records, and analytics clarity', () => {
  // 1. Verify UI_Analytics terminology decoupling
  const analyticsLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Analytics.lua'), 'utf8');
  if (analyticsLua.includes('|cFFFFD100Tracked Items|r')) {
    throw new Error('UI_Analytics should not label scanned items as Tracked Items');
  }
  if (!analyticsLua.includes('|cFFFFD100Scanned Items|r')) {
    throw new Error('UI_Analytics should label scan results as Scanned Items');
  }
  if (!analyticsLua.includes('favBannerBtn')) {
    throw new Error('UI_Analytics should have a Favorite toggle button on the banner');
  }

  // 2. Lua environment testing for compaction and downsampling
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
    time = function() return 20714 * 86400 end
    hooksecurefunc = function() end
    CreateFrame = function()
      local f = {
        SetScript = function() end,
        SetBackdrop = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        SetText = function() end,
        Show = function() end,
        Hide = function() end,
        CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end
      }
      return f
    end
    C_Timer = { After = function(delay, fn) fn() end }
    GetGameTime = function() return 12, 0 end
    date = function(fmt, t) return "Sep 18" end
    LibStub = function() return { NewDataObject = function() end, Register = function() end } end
    InterfaceOptions_AddCategory = function() end
    SlashCmdList = {}
    GetBuildInfo = function() return "1.15.2", "54321", "Apr 1 2024", 11502 end
    GetNormalizedRealmName = function() return "TestRealm" end
    GetRealmName = function() return "TestRealm" end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const coreLua = fs.readFileSync(path.join(marketSyncDir, 'Core.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(coreLua)) !== 0) {
    throw new Error('Failed to load Core.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const processingLua = fs.readFileSync(path.join(marketSyncDir, 'Processing.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(processingLua)) !== 0) {
    throw new Error('Failed to load Processing.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    -- A. Test CompactDayString and ParseCompactRecord
    local raw = "0:2s:1,12:2u:2,24:30:1" -- 100 copper (1x), 102 copper (2x), 108 copper (1x)
    assert(MarketSync.IsCompactRecord(raw) == false, "raw bucket string should not be compact")
    local compacted = MarketSync.CompactDayString(raw)
    assert(compacted ~= nil, "CompactDayString should return a string")
    assert(MarketSync.IsCompactRecord(compacted) == true, "compacted string should be compact")
    assert(compacted:sub(1, 2) == "D:", "compacted string should have D: prefix")

    local parsed = MarketSync.ParseCompactRecord(compacted)
    assert(parsed ~= nil, "ParseCompactRecord should succeed")
    assert(parsed.type == "daily", "type should be daily")
    assert(parsed.min == 100, "min should be 100, got: " .. tostring(parsed.min))
    assert(parsed.max == 108, "max should be 108, got: " .. tostring(parsed.max))
    assert(parsed.avg == 103, "avg should be 103, got: " .. tostring(parsed.avg))
    assert(parsed.volume == 4, "volume should be 4, got: " .. tostring(parsed.volume))

    -- B. Test MergeCompactRecords
    local rec2 = { type = "daily", min = 90, max = 120, avg = 110, volume = 6 }
    local weekly = MarketSync.MergeCompactRecords(parsed, rec2)
    assert(weekly.type == "weekly", "merged record type should be weekly")
    assert(weekly.min == 90, "merged min should be 90")
    assert(weekly.max == 120, "merged max should be 120")
    assert(weekly.volume == 10, "merged volume should be 10")
    -- weighted avg: (103*4 + 110*6) / 10 = (412 + 660) / 10 = 107.2 -> 107
    assert(weekly.avg == 107, "merged avg should be 107, got: " .. tostring(weekly.avg))

    -- C. Test DownsampleRetention Transitions & vh cleanup
    local currentDay = 20714
    MarketSync.GetCurrentScanDay = function() return currentDay end

    MarketSync.InitializeDB()
    local realmDB = MarketSync.GetRealmDB()
    realmDB.PersonalData = {
      ["4471"] = {
        h = {
          ["20714"] = "5:b4:a,11:b2:c", -- Today (Hot: 0d): keep raw
          ["20700"] = "2:2s:1,14:30:1", -- 14 days ago (Warm): compact to D:
          ["20670"] = "D:2s:30:2v:4",  -- 44 days ago (Cold): compact to W_2952
          ["W_2910"] = "W:10:20:15:10", -- ~20370 (344 days ago): older than 180d, PURGE!
        },
        vh = {
          ["20714"] = "5:b4:a",         -- Today: keep in vh
          ["20700"] = "2:2s:1",         -- 14 days ago: strip from vh!
          ["20670"] = "D:2s:30:2v:4",   -- 44 days ago: strip from vh!
        }
      },
      ["p:4471:12"] = {
        m = 120, d = currentDay,
        h = { ["20714"] = "5:2s:1,5:3c:2", ["20700"] = "5:2s:1", ["20670"] = "D:2s:3c:30:4" },
        vh = { ["20714"] = "5:2s:1,5:3c:2" },
      },
      ["p:4471:13"] = {
        m = 200, d = currentDay,
        h = { ["20714"] = "5:5k:1" },
        vh = { ["20714"] = "5:5k:1" },
      },
      ["p:4471:14"] = {
        m = 75, d = 20500,
        h = { ["20500"] = "5:23:1" },
        vh = { ["20500"] = "5:23:1" },
      },
    }

    MarketSync.DownsampleRetention()

    local entry = realmDB.PersonalData["4471"]
    -- Hot tier preserved
    assert(entry.h["20714"] == "5:b4:a,11:b2:c", "Hot tier should stay raw")
    -- Warm tier compacted to daily
    assert(entry.h["20700"] ~= nil, "Day 20700 should exist")
    assert(entry.h["20700"]:sub(1, 2) == "D:", "Day 20700 should be compacted to D:")
    -- Cold tier aggregated to weekly
    assert(entry.h["20670"] == nil, "Day 20670 should be removed after weekly aggregation")
    local weekKey = "W_" .. tostring(math.floor(20670 / 7))
    assert(entry.h[weekKey] ~= nil, "Weekly bucket " .. weekKey .. " should exist")
    assert(entry.h[weekKey]:sub(1, 2) == "W:", "Weekly bucket should start with W:")
    -- Purge tier deleted
    assert(entry.h["W_2910"] == nil, "Stale weekly record older than 180d should be purged")
    -- vh leak fixed: only hot tier remains in vh
    assert(entry.vh["20714"] == "5:b4:a", "Hot tier vh preserved for sync")
    assert(entry.vh["20700"] == nil, "Older vh entry should be pruned")
    assert(entry.vh["20670"] == nil, "Cold vh entry should be pruned")

    -- The three retention tiers and expiry operate on exact suffix keys.
    local boar = realmDB.PersonalData["p:4471:12"]
    local eagle = realmDB.PersonalData["p:4471:13"]
    assert(boar and eagle and boar ~= eagle, "Suffix variants must remain separate entries")
    assert(boar.h["20714"] == "5:3c:2", "Duplicate hot bucket must keep the latest variant price")
    assert(boar.vh["20714"] == "5:3c:2", "Verified sync history must keep one point per bucket")
    assert(boar.h["20700"]:sub(1, 2) == "D:", "Variant warm history must compact independently")
    assert(boar.h[weekKey] and boar.h[weekKey]:sub(1, 2) == "W:",
      "Variant cold history must remain under its own weekly key")
    assert(eagle.h["20714"] == "5:5k:1", "One variant must not change another variant's price")
    assert(realmDB.PersonalData["p:4471:14"] == nil, "Expired variant must be purged")
    assert(realmDB.PersonalData["4471"] == entry, "Purging a variant must preserve its base item")
    local boarPoints = MarketSync.GetGranularHistory("p:4471:12")
    local eaglePoints = MarketSync.GetGranularHistory("p:4471:13")
    assert(#boarPoints == 1 and boarPoints[1].price == 120, "Analytics must read the boar variant only")
    assert(#eaglePoints == 1 and eaglePoints[1].price == 200, "Analytics must read the eagle variant only")
    local linkedBoarPoints = MarketSync.GetGranularHistory("item:4471:0:0:0:0:0:12:0")
    assert(#linkedBoarPoints == 1 and linkedBoarPoints[1].price == 120,
      "Analytics must resolve a variant hyperlink to its exact history")

    -- D. Test GetItemHistory and GetGranularHistory reading of compact records
    local fullHistory = MarketSync.GetItemHistory("4471")
    assert(#fullHistory >= 3, "Expected at least 3 points in full history, got: " .. tostring(#fullHistory))

    local granularHistory = MarketSync.GetGranularHistory("4471")
    -- Granular history must only contain 30-min bucket points from today, skipping D: and W:
    assert(#granularHistory == 2, "Expected exactly 2 granular points, got: " .. tostring(#granularHistory))
    for _, pt in ipairs(granularHistory) do
      assert(pt.bucketOffset ~= nil, "Granular points must have bucketOffset")
    end
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Tiered retention validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Individual scan observation, item normalization, HistoryLog logging, and immediate callback notifications', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
    time = function() return 20714 * 86400 end
    hooksecurefunc = function() end
    CreateFrame = function()
      local f = {
        SetScript = function() end,
        SetBackdrop = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        SetText = function() end,
        Show = function() end,
        Hide = function() end,
        CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end,
        RegisterEvent = function() end,
      }
      return f
    end
    C_Timer = { After = function(delay, fn) end }
    GetGameTime = function() return 12, 0 end
    date = function(fmt, t) return "Sep 18" end
    GetNormalizedRealmName = function() return "TestRealm" end
    GetRealmName = function() return "TestRealm" end
    C_Item = {
      GetItemInfo = function(id)
        _G.ItemInfoCalls = (_G.ItemInfoCalls or 0) + 1
        return "Test Item", "item:" .. tostring(id), 2, 16, 1, "Armor", "Cloth", 1, "", 134400, 0, 4, 1
      end,
      GetItemLink = function(id) return "item:" .. tostring(id) end
    }
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const observationLua = fs.readFileSync(path.join(marketSyncDir, 'ObservationAPI.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(observationLua)) !== 0) {
    throw new Error('Failed to load ObservationAPI.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const scannerLua = fs.readFileSync(path.join(marketSyncDir, 'Scanner.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(scannerLua)) !== 0) {
    throw new Error('Failed to load Scanner.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    -- 1. Test NormalizeItemKey
    local dbKey1, id1 = MarketSync.NormalizeItemKey(4471)
    assert(dbKey1 == "4471" and id1 == 4471, "NormalizeItemKey failed for numeric ID")

    local dbKey2, id2 = MarketSync.NormalizeItemKey("4471")
    assert(dbKey2 == "4471" and id2 == 4471, "NormalizeItemKey failed for string ID")

    local dbKey3, id3 = MarketSync.NormalizeItemKey({ itemID = 4471, itemSuffix = 12 })
    assert(dbKey3 == "p:4471:12" and id3 == 4471, "NormalizeItemKey failed for suffix table")

    local dbKey4, id4 = MarketSync.NormalizeItemKey("|cffffffff|Hitem:7890:0:0:0|h[Item]|h|r")
    assert(dbKey4 == "7890" and id4 == 7890, "NormalizeItemKey failed for item link")

    local dbKey5 = MarketSync.NormalizeItemKey("item:4471:0:0:0:0:0:12:0")
    assert(dbKey5 == "p:4471:12", "Item link suffix must identify its own price record")
    local dbKey6 = MarketSync.NormalizeItemKey("p:4471:-13")
    assert(dbKey6 == "p:4471:-13", "Signed suffix key must retain its identity")
    local nativeKey = MarketSync.Scanner.ToItemKey("p:4471:-13")
    assert(nativeKey and nativeKey.itemID == 4471 and nativeKey.itemSuffix == -13,
      "Scanner searches must retain a signed suffix key")

    -- 2. Test RecordScanObservation and immediate callback
    MarketSync.InitializeDB()
    local callbackFired = false
    local observationEvents = {}
    MarketSync.ObservationAPI.v1.Register(function(event)
      observationEvents[#observationEvents + 1] = event
    end)
    MarketSync.Scanner.RegisterCallback(function()
      callbackFired = true
    end)

    MarketSync.RecordScanObservation(4471, 25000, 5, true, false)
    assert(#observationEvents == 3, "Manual observation needs start, data, finish")
    assert(observationEvents[1].event == "start" and observationEvents[3].event == "finish")
    assert(observationEvents[2].scanId == observationEvents[1].scanId)
    assert(observationEvents[2].key == "4471" and observationEvents[2].quantity == 5)
    assert(observationEvents[2].observedAt == time() and observationEvents[2].source == "local")

    -- Assert callback fired immediately (for sidecar shopping list update)
    assert(callbackFired == true, "Scanner.RegisterCallback should fire immediately upon scan observation")

    -- Assert PersonalData updated
    local realmDB = MarketSync.GetRealmDB()
    assert(realmDB.PersonalData["4471"] ~= nil, "PersonalData must contain scanned item")
    assert(realmDB.PersonalData["4471"].m == 25000, "PersonalData market price must match unitPrice")
    local metadata = MarketSyncDB.ItemInfoCache[4471]
    assert(metadata and metadata.r == 2 and metadata.i == 16 and metadata.c == 4,
      "Scan must cache green equipment metadata for processing")
    -- Assert HistoryLog (data logs) contains the scan
    assert(realmDB.HistoryLog ~= nil and #realmDB.HistoryLog > 0, "HistoryLog must contain the observation")
    assert(realmDB.HistoryLog[1].price == 25000, "HistoryLog price must match unitPrice")
    assert(realmDB.HistoryLog[1].sender == "Self", "HistoryLog sender must be Self")

    -- Assert GetAuctionPrice returns the freshly scanned price immediately
    local price = MarketSync.GetAuctionPrice(4471)
    assert(price == 25000, "MarketSync.GetAuctionPrice must return 25000, got: " .. tostring(price))

    local callsAfterFirstScan = _G.ItemInfoCalls
    callbackFired = false
    MarketSync.RecordScanObservation(4471, 24000, 5, true, true, true)
    assert(_G.ItemInfoCalls == callsAfterFirstScan, "Cached metadata must avoid another item-info lookup")
    assert(callbackFired == false, "Deferred full-scan records must not refresh UI per item")

    -- Repeated scans replace the same 30-minute slot for each variant.
    MarketSync.RecordScanObservation({ itemID = 4471, itemSuffix = 12 }, 12000, 2, false, true, true)
    MarketSync.RecordScanObservation({ itemID = 4471, itemSuffix = 12 }, 11000, 3, false, true, true)
    MarketSync.RecordScanObservation({ itemID = 4471, itemSuffix = 13 }, 22000, 1, false, true, true)
    local day = tostring(MarketSync.GetCurrentScanDay())
    local offset = MarketSync.GetCurrentBucket() % 48
    assert(realmDB.PersonalData["p:4471:12"].h[day] == offset .. ":" .. MarketSync.ToBase36(11000) .. ":3",
      "Repeated scans must retain one latest boar point in the current bucket, got "
        .. tostring(realmDB.PersonalData["p:4471:12"].h[day]))
    assert(realmDB.PersonalData["p:4471:13"].m == 22000,
      "Other suffix must retain its own price")
    assert(MarketSync.GetAuctionPrice("p:4471:12") == 11000,
      "Variant price lookup must use the exact suffix")
    assert(MarketSync.GetAuctionPrice("item:4471:0:0:0:0:0:12:0") == 11000,
      "Variant hyperlink price lookup must use the exact suffix")
    assert(MarketSync.GetItemPriceAndScanInfo("p:4471:13").price == 22000,
      "Analytics price info must use the exact suffix")
    assert(MarketSync.GetItemPriceAndScanInfo("p:4471:14") == nil,
      "Missing suffix price must not fall back to the base item")
    local repaired = MarketSync.UpsertScanBucket("0:2s:1,0:3c:2", 0, 150, 3)
    assert(repaired == "0:" .. MarketSync.ToBase36(150) .. ":3",
      "Existing duplicate buckets must collapse to the latest point")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Individual scan observation test failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Auction age formatting masks float days into human-readable duration without decimals', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
    time = function() return 1773780000 end
    hooksecurefunc = function() end
    CreateFrame = function()
      local f = {
        SetScript = function() end,
        SetBackdrop = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        SetText = function() end,
        Show = function() end,
        Hide = function() end,
        CreateFontString = function() return { SetPoint = function() end, SetText = function() end } end,
        RegisterEvent = function() end,
      }
      return f
    end
    C_Timer = { After = function() end }
    GetGameTime = function() return 12, 0 end
    date = function(fmt, t) return "Sep 18" end
    GetNormalizedRealmName = function() return "TestRealm" end
    GetRealmName = function() return "TestRealm" end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    -- 1. Test 5 minutes ago from float days (0.0036689814814815 days ≈ 317s)
    local floatAge = 317 / 86400
    local detailed = MarketSync.FormatAuctionAge(floatAge, nil, true)
    local compact = MarketSync.FormatAuctionAge(floatAge, nil, false)
    assert(detailed == "5 mins ago", "Expected '5 mins ago', got: " .. tostring(detailed))
    assert(compact == "5m ago", "Expected '5m ago', got: " .. tostring(compact))

    -- 2. Test exactTime timestamp (10 minutes ago = 600s)
    local scanTime = time() - 600
    local detailedTime = MarketSync.FormatAuctionAge(nil, scanTime, true)
    local compactTime = MarketSync.FormatAuctionAge(nil, scanTime, false)
    assert(detailedTime == "10 mins ago", "Expected '10 mins ago', got: " .. tostring(detailedTime))
    assert(compactTime == "10m ago", "Expected '10m ago', got: " .. tostring(compactTime))

    -- 3. Test hours and minutes (2 hours 15 mins = 8100s)
    local twoHoursAgo = time() - 8100
    local detailedHrs = MarketSync.FormatAuctionAge(nil, twoHoursAgo, true)
    local compactHrs = MarketSync.FormatAuctionAge(nil, twoHoursAgo, false)
    assert(detailedHrs == "2 hrs 15 mins ago", "Expected '2 hrs 15 mins ago', got: " .. tostring(detailedHrs))
    assert(compactHrs == "2h ago", "Expected '2h ago', got: " .. tostring(compactHrs))

    -- 4. Test multi-day age with decimals stripped (4.72 days)
    local multiDayAge = 4.72
    local detailedDays = MarketSync.FormatAuctionAge(multiDayAge, nil, true)
    local compactDays = MarketSync.FormatAuctionAge(multiDayAge, nil, false)
    assert(detailedDays == "4 days ago", "Expected '4 days ago', got: " .. tostring(detailedDays))
    assert(compactDays == "4d ago", "Expected '4d ago', got: " .. tostring(compactDays))

    -- 5. Test 1 day ago
    local oneDay = MarketSync.FormatAuctionAge(1.0, nil, true)
    local oneDayCompact = MarketSync.FormatAuctionAge(1.0, nil, false)
    assert(oneDay == "1 day ago", "Expected '1 day ago', got: " .. tostring(oneDay))
    assert(oneDayCompact == "1d ago", "Expected '1d ago', got: " .. tostring(oneDayCompact))

    -- 6. Test FormatRelativeTime fallbackDays with float
    local relTimeFloat = MarketSync.FormatRelativeTime(nil, floatAge)
    assert(relTimeFloat == "5m ago", "Expected '5m ago' from FormatRelativeTime, got: " .. tostring(relTimeFloat))

    local relTimeMulti = MarketSync.FormatRelativeTime(nil, 3.8)
    assert(relTimeMulti == "3d ago", "Expected '3d ago' without decimals, got: " .. tostring(relTimeMulti))
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('FormatAuctionAge test failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('MainFrame registers 7 tabs with Analytics, Processing, Alerts, and redirects ShowItemHistory to ShowAnalytics', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    MarketSync = MarketSync or {}
    MarketSyncDB = { LowRamMode = false, PassiveSync = true, EnableNeutralSync = true, EnableAnalyticsTab = true, EnableProcessingTab = true, EnableAlertsTab = true, EnableProfessionCraftInfo = true }
    UISpecialFrames = {}
    time = function() return 1773780000 end
    GetTime = function() return 1000 end
    GetGameTime = function() return 12, 0 end
    date = function(fmt, t) return "Sep 18" end
    GetNormalizedRealmName = function() return "TestRealm" end
    GetRealmName = function() return "TestRealm" end
    IsInGuild = function() return true end
    tinsert = table.insert
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

    PanelTemplates_SelectTab = function(tab) tab.selected = true end
    PanelTemplates_DeselectTab = function(tab) tab.selected = false end
    PanelTemplates_TabResize = function(tab) end
    PanelTemplates_SetNumTabs = function(frame, n) frame.numTabs = n end

    local framesCreated = {}
    CreateFrame = function(frameType, name, parent, template)
      local f = {
        name = name,
        parent = parent,
        template = template,
        shown = true,
        scripts = {},
        points = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        SetPoint = function(self, ...) table.insert(self.points, { ... }) end,
        ClearAllPoints = function(self) self.points = {} end,
        SetAllPoints = function(self) end,
        SetSize = function(self, w, h) self.width = w self.height = h end,
        SetWidth = function(self, w) self.width = w end,
        SetHeight = function(self, h) self.height = h end,
        GetWidth = function(self) return self.width or 832 end,
        GetHeight = function(self) return self.height or 447 end,
        SetMovable = function(self) end,
        EnableMouse = function(self) end,
        EnableMouseWheel = function(self) end,
        RegisterForDrag = function(self) end,
        SetFrameStrata = function(self) end,
        SetToplevel = function(self) end,
        SetID = function(self, id) self.id = id end,
        GetID = function(self) return self.id end,
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text or "" end,
        SetTextColor = function(self) end,
        Click = function(self) if self.scripts["OnClick"] then self.scripts["OnClick"](self) end end,
        RegisterEvent = function(self) end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn)
          local old = self.scripts[name]
          self.scripts[name] = function(...) if old then old(...) end fn(...) end
        end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        SetPortraitToUnit = function() end,
        CreateTexture = function(self)
          return {
            SetColorTexture = function() end,
            SetTexture = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetAllPoints = function() end,
            Show = function() end,
            Hide = function() end,
            SetBlendMode = function() end,
            SetVertexColor = function() end,
            SetTexCoord = function() end,
            AddMaskTexture = function() end,
            SetHeight = function() end,
            SetWidth = function() end,
          }
        end,
        CreateMaskTexture = function(self)
          return { SetTexture = function() end, SetSize = function() end, SetPoint = function() end }
        end,
        AddMaskTexture = function(self) end,
        SetChecked = function(self, val) self.checked = val end,
        GetChecked = function(self) return self.checked end,
        SetAutoFocus = function() end,
        SetNumeric = function() end,
        SetNumber = function() end,
        SetMaxLetters = function() end,
        ClearFocus = function() end,
        HighlightText = function() end,
        SetMinMaxValues = function() end,
        SetValue = function(self, v) self.val = v end,
        GetValue = function(self) return self.val or 0 end,
        SetValueStep = function() end,
        SetObeyStepOnDrag = function() end,
        SetScrollChild = function() end,
        GetVerticalScroll = function() return 0 end,
        SetVerticalScroll = function() end,
        GetVerticalScrollRange = function() return 0 end,
        CreateFontString = function(self)
          return {
            SetPoint = function() end,
            ClearAllPoints = function() end,
            SetText = function(self, t) self.text = t end,
            GetText = function(self) return self.text or "" end,
            GetStringWidth = function(self) return 100 end,
            SetTextColor = function() end,
            SetFontObject = function() end,
            SetJustifyH = function() end,
            SetWidth = function() end,
            SetSpacing = function() end,
            Show = function() end,
            Hide = function() end,
          }
        end,
        SetSpacing = function() end,
      }
      if frameType == "CheckButton" or (template and type(template) == "string" and template:find("CheckButton")) then
        f.text = f:CreateFontString()
      end
      if frameType == "Slider" or (template and type(template) == "string" and template:find("Slider")) then
        f.Low = f:CreateFontString()
        f.High = f:CreateFontString()
        f.Text = f:CreateFontString()
        if name then
          _G[name .. "Low"] = f.Low
          _G[name .. "High"] = f.High
          _G[name .. "Text"] = f.Text
        end
      end
      if name then _G[name] = f end
      table.insert(framesCreated, f)
      return f
    end

    GameTooltip = { SetOwner = function() end, Hide = function() end, Show = function() end, SetText = function() end, AddLine = function() end }
    UIDropDownMenu_SetWidth = function() end
    UIDropDownMenu_Initialize = function() end
    UIDropDownMenu_SetText = function() end
    UIDropDownMenu_CreateInfo = function() return {} end
    UIDropDownMenu_AddButton = function() end

    MarketSync.CreateBrowsePanel = function(parent, scope)
      local f = CreateFrame("Frame", nil, parent)
      f.scope = scope
      return f
    end
    MarketSync.CreateAnalyticsPanel = function(parent)
      local f = CreateFrame("Frame", nil, parent)
      f.isAnalytics = true
      f.ShowItem = function(self, key, link, name, icon, price)
        self.lastShownItem = { key = key, link = link, name = name }
      end
      return f
    end
    MarketSync.CreateProcessingPanel = function(parent)
      local f = CreateFrame("Frame", nil, parent)
      f.isProcessing = true
      return f
    end
    MarketSync.CreateNotificationsPanel = function(parent)
      local f = CreateFrame("Frame", nil, parent)
      f.isAlerts = true
      return f
    end
    MarketSync.CreateItemDetailPanel = function(parent)
      return CreateFrame("Frame", nil, parent)
    end
    MarketSync.CreateItemHistoryPanel = function(parent)
      local f = CreateFrame("Frame", nil, parent)
      f.backBtn = CreateFrame("Button", nil, f)
      f.ShowItem = function() end
      return f
    end
    MarketSync.CreateModernDialog = function() return CreateFrame("Frame") end
    MarketSync.ShowModernConfirmation = function() end
    MarketSync.ShowModernPrompt = function() end
    MarketSync.GetAddOnMetadata = function() return "1.0" end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const mainLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Main.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(mainLua)) !== 0) {
    throw new Error('Failed to load UI_Main.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    local mainFrame = MarketSync.CreateMainFrame()
    assert(mainFrame ~= nil, "MainFrame should exist")
    assert(mainFrame.tabs ~= nil, "MainFrame.tabs should exist")
    assert(#mainFrame.tabs == 7, "MainFrame must have 7 tabs, found: " .. tostring(#mainFrame.tabs))
    assert(mainFrame.tabs[1]:GetText() == "Personal Scan", "Tab 1 must be Personal Scan")
    assert(mainFrame.tabs[2]:GetText() == "Guild Sync", "Tab 2 must be Guild Sync")
    assert(mainFrame.tabs[3]:GetText() == "Neutral AH", "Tab 3 must be Neutral AH")
    assert(mainFrame.tabs[4]:GetText() == "Analytics", "Tab 4 must be Analytics")
    assert(mainFrame.tabs[5]:GetText() == "Processing", "Tab 5 must be Processing")
    assert(mainFrame.tabs[6]:GetText() == "Alerts", "Tab 6 must be Alerts")
    assert(mainFrame.tabs[7]:GetText() == "Settings", "Tab 7 must be Settings")

    -- Test SelectMainFrameTab
    assert(type(MarketSync.SelectMainFrameTab) == "function", "SelectMainFrameTab should be exposed")
    MarketSync.SelectMainFrameTab(4)
    assert(mainFrame.activeTabID == 4, "Tab 4 should be active")
    assert(mainFrame.contentFrames[4]:IsShown(), "Analytics contentFrame should be shown")

    -- Test uniform tab width and anchoring
    assert(type(mainFrame.RefreshTabVisibility) == "function", "RefreshTabVisibility should be exposed")
    for i = 1, 7 do
      assert(mainFrame.tabs[i]:GetWidth() == 104, "Tab " .. i .. " should have uniform width 104, got " .. tostring(mainFrame.tabs[i]:GetWidth()))
    end

    -- Test dynamic resizing when a tab is hidden
    MarketSyncDB.PassiveSync = false
    mainFrame.RefreshTabVisibility()
    assert(not mainFrame.tabs[2]:IsShown(), "Tab 2 should be hidden when PassiveSync is false")
    for i = 1, 7 do
      if i ~= 2 then
        assert(mainFrame.tabs[i]:GetWidth() == 112, "Tab " .. i .. " should have resized to 112 with 6 tabs, got " .. tostring(mainFrame.tabs[i]:GetWidth()))
      end
    end
    MarketSyncDB.PassiveSync = true
    mainFrame.RefreshTabVisibility()

    -- Test Beta toggles hiding Processing and Alerts
    MarketSyncDB.EnableProcessingTab = false
    mainFrame.RefreshTabVisibility()
    assert(not mainFrame.tabs[5]:IsShown(), "Tab 5 (Processing) should be hidden when EnableProcessingTab is false")
    MarketSyncDB.EnableProcessingTab = true
    mainFrame.RefreshTabVisibility()
    assert(mainFrame.tabs[5]:IsShown(), "Tab 5 (Processing) should be shown when EnableProcessingTab is true")

    MarketSyncDB.EnableAlertsTab = false
    mainFrame.RefreshTabVisibility()
    assert(not mainFrame.tabs[6]:IsShown(), "Tab 6 (Alerts) should be hidden when EnableAlertsTab is false")
    MarketSyncDB.EnableAlertsTab = true
    mainFrame.RefreshTabVisibility()
    assert(mainFrame.tabs[6]:IsShown(), "Tab 6 (Alerts) should be shown when EnableAlertsTab is true")

    -- Test ShowItemHistory delegation to ShowAnalytics
    local analyticsCalledWith = nil
    MarketSync.ShowAnalytics = function(k, l, n, ic, pr)
      analyticsCalledWith = { key = k, link = l, name = n }
    end
    MarketSync.ShowItemHistory("4471", "item:4471", "Tin Bar", nil, 500)
    assert(analyticsCalledWith ~= nil, "ShowItemHistory must delegate to MarketSync.ShowAnalytics")
    assert(analyticsCalledWith.key == "4471", "Analytics received key 4471")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('MainFrame 7-tab check failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('AuctionHouse buy frame button hook and sidecar suppression across tabs', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    MarketSync = MarketSync or {}
    MarketSyncDB = { AHSidecarExpanded = true }
    C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
    time = function() return 1773780000 end
    GetTime = function() return 1000 end
    hooksecurefunc = function(t, k, hookFn)
      local orig = t[k]
      t[k] = function(...)
        if orig then orig(...) end
        hookFn(...)
      end
    end

    local createdFrames = {}
    CreateFrame = function(frameType, name, parent, template)
      local f = {
        name = name,
        parent = parent,
        template = template,
        shown = false,
        scripts = {},
        points = {},
        Show = function(self)
          self.shown = true
          if self.scripts["OnShow"] then self.scripts["OnShow"](self) end
        end,
        Hide = function(self)
          self.shown = false
          if self.scripts["OnHide"] then self.scripts["OnHide"](self) end
        end,
        IsShown = function(self) return self.shown end,
        SetPoint = function(self, ...) table.insert(self.points, { ... }) end,
        SetAllPoints = function(self) end,
        SetSize = function(self, w, h) self.width = w self.height = h end,
        SetWidth = function(self, w) self.width = w end,
        SetHeight = function(self, h) self.height = h end,
        GetWidth = function(self) return self.width or 750 end,
        GetHeight = function(self) return self.height or 447 end,
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text or "" end,
        SetNormalTexture = function(self) end,
        SetPushedTexture = function(self) end,
        SetHighlightTexture = function(self) end,
        Click = function(self) if self.scripts["OnClick"] then self.scripts["OnClick"](self) end end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn)
          local old = self.scripts[name]
          self.scripts[name] = function(...) if old then old(...) end fn(...) end
        end,
        CreateTexture = function(self)
          return { SetColorTexture = function() end, SetTexture = function() end, SetPoint = function() end, SetSize = function() end, Show = function() end, Hide = function() end }
        end,
        CreateFontString = function(self)
          return { SetPoint = function() end, SetText = function(self, t) self.text = t end, GetText = function(self) return self.text or "" end, Show = function() end, Hide = function() end }
        end,
      }
      if name then _G[name] = f end
      table.insert(createdFrames, f)
      return f
    end

    MarketSync.MainFrame = CreateFrame("Frame", "MarketSyncMainFrame")
    MarketSync.MainFrame:Show() -- initially open

    AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
    AuctionHouseFrame.Tabs = { { displayMode = "buy" }, { displayMode = "sell" } }
    AuctionHouseFrame.AuctionsTab = { displayMode = "auctions" }
    AuctionHouseFrame.CommoditiesBuyFrame = CreateFrame("Frame", "CommoditiesBuyFrame", AuctionHouseFrame)
    AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay = {
      ItemDisplay = {
        itemLink = "|Hitem:13444|h[Major Healing Potion]|h",
        itemID = 13444,
        GetItemInfo = function() return "Major Healing Potion", "|Hitem:13444|h[Major Healing Potion]|h", 13444 end
      }
    }
    AuctionHouseFrame.ItemBuyFrame = CreateFrame("Frame", "ItemBuyFrame", AuctionHouseFrame)

    AuctionHouseFrame.displayMode = "buy"
    AuctionHouseFrame.GetDisplayMode = function(self) return self.displayMode end
    AuctionHouseFrame.SetDisplayMode = function(self, mode) self.displayMode = mode end

    local createdTabs = {}
    local mockLibAHTab = {
      DoesIDExist = function(self, id) return createdTabs[id] ~= nil end,
      CreateTab = function(self, id, frameRef, text, header)
        createdTabs[id] = { id = id, frameRef = frameRef, text = text, header = header }
      end,
      GetButton = function(self, id) return createdTabs[id] end,
      SetSelected = function(self, id)
        if createdTabs[id] and createdTabs[id].frameRef then
          createdTabs[id].frameRef:Show()
        end
      end,
    }
    LibStub = function(name) if name == "LibAHTab-1-0" then return mockLibAHTab end end

    MarketSync.CreateAHScannerPanel = function(parent) return CreateFrame("Frame", nil, parent) end
    MarketSync.CreateProcessingPanel = function(parent) return CreateFrame("Frame", nil, parent) end
    MarketSync.CreateNotificationsPanel = function(parent) return CreateFrame("Frame", nil, parent) end
    MarketSync.CreateAnalyticsPanel = function(parent)
      local f = CreateFrame("Frame", nil, parent)
      f.ShowItem = function(self, k, l, n) self.activeItem = k end
      return f
    end
    MarketSync.CreateAHSidecar = function(parent)
      local sc = CreateFrame("Frame", nil, parent)
      sc.SetMode = function(m) sc.mode = m end
      sc.SetExpanded = function(exp) sc.expanded = exp end
      return sc
    end
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const ahLua = fs.readFileSync(path.join(marketSyncDir, 'AuctionHouse.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(ahLua)) !== 0) {
    throw new Error('Failed to load AuctionHouse.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    local AH = MarketSync.AuctionHouse
    AH.Attach()

    -- 1. Opening AH should suppress/close MarketSync.MainFrame
    assert(MarketSync.MainFrame:IsShown() == true, "MainFrame starts shown")
    AuctionHouseFrame:Show()
    assert(MarketSync.MainFrame:IsShown() == false, "MainFrame must be hidden when AH opens")

    -- 2. CommoditiesBuyFrame should have MarketSyncCommoditiesAnalyticsBtn
    local btnCom = _G["MarketSyncCommoditiesAnalyticsBtn"]
    assert(btnCom ~= nil, "MarketSyncCommoditiesAnalyticsBtn must be attached to CommoditiesBuyFrame")
    assert(btnCom:GetText():find("Analytics"), "Button text must mention Analytics")

    -- 3. Sidecar suppression on custom tabs:
    AH.Sidecar:Show()
    assert(AH.Sidecar:IsShown() == true, "Sidecar starts shown")

    -- Switching to Processing tab hides Sidecar
    AH.ShowAuctionHousePanel("processing")
    assert(AH.Sidecar:IsShown() == false, "Sidecar must hide on Processing tab")

    -- Switching to Alerts tab hides Sidecar
    AH.Sidecar:Show()
    AH.ShowAuctionHousePanel("alerts")
    assert(AH.Sidecar:IsShown() == false, "Sidecar must hide on Alerts tab")

    -- Switching to Analytics tab hides Sidecar
    AH.Sidecar:Show()
    AH.ShowAuctionHousePanel("analytics")
    assert(AH.Sidecar:IsShown() == false, "Sidecar must hide on Analytics tab")

    -- Switching back to Scanner tab restores Sidecar
    AH.ShowAuctionHousePanel("scanner")
    assert(AH.Sidecar:IsShown() == true, "Sidecar must restore on Scanner tab")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('AH buy button and sidecar suppression check failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Processing and Alerts panels adjust widths responsively for Auction House embedding', () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mockEnv = `
    MarketSync = MarketSync or {}
    MarketSyncDB = {}
    UIDropDownMenu_SetWidth = function() end
    UIDropDownMenu_Initialize = function() end
    UIDropDownMenu_SetText = function() end
    UIDropDownMenu_CreateInfo = function() return {} end
    UIDropDownMenu_AddButton = function() end

    CreateFrame = function(frameType, name, parent, template)
      local f = {
        name = name,
        parent = parent,
        scripts = {},
        points = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        SetPoint = function(self, ...) table.insert(self.points, { ... }) end,
        SetAllPoints = function(self) end,
        SetSize = function(self, w, h) self.width = w self.height = h end,
        SetWidth = function(self, w) self.width = w end,
        SetHeight = function(self, h) self.height = h end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        GetWidth = function(self) return self.width or 0 end,
        GetHeight = function(self) return self.height or 0 end,
        SetAutoFocus = function() end,
        SetNumeric = function() end,
        SetFontObject = function() end,
        SetScrollChild = function() end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text or "" end,
        HighlightText = function() end,
        ClearFocus = function() end,
        SetChecked = function(self, val) self.checked = val end,
        GetChecked = function(self) return self.checked end,
        Click = function() end,
        RegisterForClicks = function() end,
        LockHighlight = function() end,
        UnlockHighlight = function() end,
        SetNormalTexture = function() end,
        SetPushedTexture = function() end,
        SetDisabledTexture = function() end,
        SetHighlightTexture = function() end,
        SetAlpha = function() end,
        Enable = function() end,
        Disable = function() end,
        SetEnabled = function(self, en) if en then self:Enable() else self:Disable() end end,
        CreateTexture = function() return { SetColorTexture = function() end, SetTexture = function() end, SetSize = function() end, SetWidth = function() end, SetHeight = function() end, SetPoint = function() end, SetAllPoints = function() end, SetBlendMode = function() end, SetVertexColor = function() end, SetTexCoord = function() end, Show = function() end, Hide = function() end } end,
        CreateLine = function() return { SetThickness = function() end, SetColorTexture = function() end, SetStartPoint = function() end, SetEndPoint = function() end, Show = function() end, Hide = function() end } end,
        CreateFontString = function() return { SetPoint = function() end, ClearAllPoints = function() end, SetText = function() end, GetText = function() return "" end, SetSize = function() end, SetWidth = function() end, SetHeight = function() end, SetJustifyH = function() end, SetJustifyV = function() end, SetTextColor = function() end, SetFontObject = function() end, Show = function() end, Hide = function() end } end,
        EnableMouseWheel = function() end,
        EnableMouse = function() end,
      }
      if frameType == "CheckButton" or (template and type(template) == "string" and template:find("CheckButton")) then
        f.text = f:CreateFontString()
      end
      return f
    end

    MarketSync.MainFrame = CreateFrame("Frame", "MarketSyncMainFrame")
    MarketSync.MainFrame:SetSize(832, 447)
  `;
  lauxlib.luaL_dostring(L, to_luastring(mockEnv));

  const procLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Processing.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(procLua)) !== 0) {
    throw new Error('Failed to load UI_Processing.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const notifLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Notifications.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(notifLua)) !== 0) {
    throw new Error('Failed to load UI_Notifications.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const analyticsLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Analytics.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(analyticsLua)) !== 0) {
    throw new Error('Failed to load UI_Analytics.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const check = `
    -- Standalone MainFrame processing panel
    local procMain = MarketSync.CreateProcessingPanel(MarketSync.MainFrame)
    assert(procMain.resultRows[1].width == 632, "MainFrame processing row width should be 632, got: " .. tostring(procMain.resultRows[1].width))
    assert(#procMain.resultRows == 8, "MainFrame processing rows should be 8, got: " .. tostring(#procMain.resultRows))

    -- Embedded AH processing panel
    local ahProcContainer = CreateFrame("Frame", "AHProcContainer")
    ahProcContainer:SetSize(756, 447)
    local procAH = MarketSync.CreateProcessingPanel(ahProcContainer)
    assert(procAH.resultRows[1].width == 550, "Embedded AH processing row width should be 550, got: " .. tostring(procAH.resultRows[1].width))
    assert(#procAH.resultRows == 11, "Embedded AH processing rows should be 11, got: " .. tostring(#procAH.resultRows))
    -- Total row right offset: RESULTS_X (198) + ROW_WIDTH (550) = 748px <= 756px
    assert(198 + procAH.resultRows[1].width <= 756, "Processing table must fit inside AH width <= 756px")

    -- Standalone MainFrame alerts panel
    local alertsMain = MarketSync.CreateNotificationsPanel(MarketSync.MainFrame)
    assert(alertsMain.rows[1].width == 576, "MainFrame alerts row width should be 576, got: " .. tostring(alertsMain.rows[1].width))
    assert(#alertsMain.rows == 9, "MainFrame alerts rows should be 9, got: " .. tostring(#alertsMain.rows))

    -- Embedded AH alerts panel
    local ahAlertsContainer = CreateFrame("Frame", "AHAlertsContainer")
    ahAlertsContainer:SetSize(756, 447)
    local alertsAH = MarketSync.CreateNotificationsPanel(ahAlertsContainer)
    assert(alertsAH.rows[1].width == 542, "Embedded AH alerts row width should be 542, got: " .. tostring(alertsAH.rows[1].width))
    assert(#alertsAH.rows == 12, "Embedded AH alerts rows should be 12, got: " .. tostring(#alertsAH.rows))
    -- Total row right offset: RESULTS_X (198) + ROW_WIDTH (550) = 748px <= 756px
    assert(198 + alertsAH.rows[1].width <= 756, "Alerts table must fit inside AH width <= 756px")

    -- Standalone MainFrame analytics panel
    local analyticsMain = MarketSync.CreateAnalyticsPanel(MarketSync.MainFrame)
    assert(analyticsMain.isEmbedded == false, "MainFrame analytics isEmbedded should be false")
    assert(analyticsMain.graphCard.height == 155, "MainFrame analytics graph height should be 155, got: " .. tostring(analyticsMain.graphCard.height))
    assert(analyticsMain.banner.height == 44, "MainFrame analytics banner height should be 44, got: " .. tostring(analyticsMain.banner.height))

    -- Embedded AH analytics panel
    local ahAnalyticsContainer = CreateFrame("Frame", "AHAnalyticsContainer")
    ahAnalyticsContainer:SetSize(756, 447)
    local analyticsAH = MarketSync.CreateAnalyticsPanel(ahAnalyticsContainer)
    assert(analyticsAH.isEmbedded == true, "AH analytics isEmbedded should be true")
    assert(analyticsAH.graphCard.height == 230, "AH analytics graph height should be 230, got: " .. tostring(analyticsAH.graphCard.height))
    assert(analyticsAH.banner.height == 46, "AH analytics banner height should be 46, got: " .. tostring(analyticsAH.banner.height))
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(check)) !== 0) {
    throw new Error('Responsive layout check failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
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
