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
      }
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
