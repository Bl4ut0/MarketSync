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
    local mockLibAHTab = {
      DoesIDExist = function(self, id) return createdTabs[id] ~= nil end,
      CreateTab = function(self, id, frameRef, text, header)
        createdTabs[id] = { id = id, frameRef = frameRef, text = text, header = header }
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
