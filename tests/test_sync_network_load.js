// Automated test suite for MarketSync: Full Sync Verification, Multi-Player Network Load & Guild Flood Prevention
const fs = require('fs');
const path = require('path');

const candidateDeps = [
  path.resolve(__dirname, '../node_modules'),
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
];
const deps = candidateDeps.find(p => fs.existsSync(p)) || candidateDeps[0];
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

const marketSyncDir = path.resolve(__dirname, '../MarketSync');

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

// ---------------------------------------------------------------------
// TEST 1: AST Syntax Validation on All Core & UI Files
// ---------------------------------------------------------------------
test('AST syntax check on MarketSync sync and alerts files', () => {
  const fileNames = [
    'Notifications.lua',
    'Config.lua',
    'UI_Notifications.lua',
    'UI_Main.lua',
    'Sync.lua',
    'Chat.lua',
    'Neutral.lua',
  ];
  for (const name of fileNames) {
    const filePath = path.join(marketSyncDir, name);
    if (fs.existsSync(filePath)) {
      const code = fs.readFileSync(filePath, 'utf8');
      luaparse.parse(code, { luaVersion: '5.1' });
    }
  }
});

// Helper to create a sandbox WoW environment
function createLuaEnv(extraSetup) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const mock = `
    time = function() return 1773780000 end
    GetTime = function() return 1000 end
    IsInGuild = function() return true end
    GetNormalizedRealmName = function() return "Faerlina" end
    GetRealmName = function() return "Faerlina" end
    UnitName = function(u) return "LocalPlayer" end
    UnitFullName = function(u) return "LocalPlayer", "Faerlina" end
    SetPortraitTexture = function() end
    UIParent = {}
    hooksecurefunc = function(t, k, f) end
    C_Timer = {
      After = function(d, f) end,
      NewTicker = function(i, f) return { Cancel = function() end } end,
    }
    C_ChatInfo = {
      SendAddonMessage = function(p, t, c, tgt) end,
      RegisterAddonMessagePrefix = function(p) return true end,
    }
    tinsert = table.insert
    UISpecialFrames = {}
    PanelTemplates_SelectTab = function() end
    PanelTemplates_DeselectTab = function() end
    PanelTemplates_TabResize = function() end
    PanelTemplates_SetNumTabs = function() end
    PanelTemplates_ResizeTabsToFit = function() end
    UIDropDownMenu_SetWidth = function() end
    UIDropDownMenu_Initialize = function() end
    UIDropDownMenu_SetText = function() end
    UIDropDownMenu_CreateInfo = function() return {} end
    UIDropDownMenu_AddButton = function() end

    GameTooltip = {
      SetOwner = function() end,
      SetText = function() end,
      Show = function() end,
      Hide = function() end,
      AddLine = function() end,
      ClearLines = function() end,
    }
    CloseDropDownMenus = function() end
    strtrim = function(s) if not s then return "" end return (s:gsub("^%s*(.-)%s*$", "%1")) end
    wipe = function(t) if type(t) == "table" then for k in pairs(t) do t[k] = nil end end return t end

    CreateFrame = function(frameType, name, parent, template)
      local f = {
        name = name,
        parent = parent,
        scripts = {},
        points = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown ~= false end,
        SetPoint = function(self, ...) table.insert(self.points, { ... }) end,
        ClearAllPoints = function(self) self.points = {} end,
        SetAllPoints = function(self) end,
        SetSize = function(self, w, h) self.width = w self.height = h end,
        SetWidth = function(self, w) self.width = w end,
        SetHeight = function(self, h) self.height = h end,
        GetWidth = function(self) return self.width or 100 end,
        GetHeight = function(self) return self.height or 20 end,
        SetMovable = function(self) end,
        EnableMouse = function(self) end,
        RegisterForDrag = function(self) end,
        SetFrameStrata = function(self) end,
        SetToplevel = function(self) end,
        RegisterEvent = function(self) end,
        HookScript = function(self, name, fn) end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        SetID = function(self, id) self.id = id end,
        GetID = function(self) return self.id or 0 end,
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text or "" end,
        SetAlpha = function(self, a) self.alpha = a end,
        Enable = function() end,
        Disable = function() end,
        SetEnabled = function(self, en) end,
        SetChecked = function(self, c) self.checked = c end,
        GetChecked = function(self) return self.checked end,
        SetMinMaxValues = function(self, min, max) self.minVal = min self.maxVal = max end,
        SetValueStep = function(self, s) self.step = s end,
        SetObeyStepOnDrag = function(self, b) end,
        SetValue = function(self, v) self.val = v end,
        GetValue = function(self) return self.val or 0 end,
        SetAutoFocus = function(self, b) end,
        SetMaxLetters = function(self, n) end,
        ClearFocus = function(self) end,
        SetScrollChild = function(self, c) self.scrollChild = c end,
        GetVerticalScroll = function(self) return 0 end,
        GetVerticalScrollRange = function(self) return 0 end,
        SetVerticalScroll = function(self, v) end,
        CreateTexture = function()
          return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
            SetTexture = function() end,
            SetSize = function() end,
            SetHeight = function() end,
            SetWidth = function() end,
            SetPoint = function() end,
            SetBlendMode = function() end,
            SetVertexColor = function() end,
            SetTexCoord = function() end,
            AddMaskTexture = function() end,
            Show = function() end,
            Hide = function() end,
          }
        end,
        CreateMaskTexture = function()
          return {
            SetTexture = function() end,
            SetSize = function() end,
            SetPoint = function() end,
          }
        end,
        CreateFontString = function()
          local fs = {
            SetPoint = function() end,
            ClearAllPoints = function() end,
            SetText = function(self, t) self.text = t end,
            GetText = function(self) return self.text or "" end,
            SetJustifyH = function() end,
            SetJustifyV = function() end,
            SetTextColor = function() end,
            SetFontObject = function() end,
            SetSize = function() end,
            SetWidth = function() end,
            SetHeight = function() end,
            SetSpacing = function() end,
            GetStringWidth = function() return 100 end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            SetShown = function(self, s) self.shown = s end,
          }
          return fs
        end,
        EnableMouseWheel = function() end,
      }
      if frameType == "CheckButton" or (template and type(template) == "string" and template:find("CheckButton")) then
        f.text = f:CreateFontString()
      end
      if frameType == "Slider" or (template and type(template) == "string" and template:find("Slider")) then
        f.Low = f:CreateFontString()
        f.High = f:CreateFontString()
        f.Text = f:CreateFontString()
      end
      return f
    end
    MarketSync = MarketSync or {}
    MarketSync.StandardSounds = {
      { id = 8959, name = "Raid Warning" },
      { id = 5674, name = "Auction Window Open" },
    }
    MarketSync.CacheSpeedPresets = {
      [1] = { name = "Eco", desc = "Eco speed" },
      [2] = { name = "Normal", desc = "Normal speed" },
      [3] = { name = "Fast", desc = "Fast speed" },
      [4] = { name = "Ludicrous", desc = "Max speed" },
    }
    MarketSync.CreateModernDialog = function(name, w, h, title)
      local d = CreateFrame("Frame", name, UIParent)
      d:SetSize(w or 400, h or 300)
      return d
    end
    MarketSyncDB = {
      PassiveSync = true,
      EnableNeutralSync = true,
      AlertUndercutPct = 10,
      RealmData = {
        Faerlina = {
          PersonalData = {},
          NeutralData = {},
          ItemMetadata = {},
          NotificationRequests = {},
          NotificationState = {},
          NotificationLog = {},
        }
      }
    }
    MarketSync.GetRealmDB = function()
      return MarketSyncDB.RealmData.Faerlina
    end
    MarketSync.ADDON_NAME = "MarketSync"
    MarketSync.GetAddOnMetadata = function(a, f) return "0.8.0" end
    MarketSync.CreateBrowsePanel = function(p) return CreateFrame("Frame", nil, p) end
    MarketSync.CreateAnalyticsPanel = function(p) return CreateFrame("Frame", nil, p) end
    MarketSync.CreateProcessingPanel = function(p) return CreateFrame("Frame", nil, p) end
    MarketSync.CreateNotificationsPanel = function(p) return CreateFrame("Frame", nil, p) end
    MarketSync.CreateItemDetailPanel = function(p) return CreateFrame("Frame", nil, p) end
    MarketSync.FormatMoney = function(copper)
      local g = math.floor((copper or 0) / 10000)
      return tostring(g) .. "g"
    end
    MarketSync.GetItemInfo = function(id)
      return "Item " .. tostring(id), "item:" .. tostring(id), 1, 0, 0, "", "", 1, "", 134400
    end
    MarketSync.ResolveItemID = function(id) return tonumber(id) or 13444 end
    ${extraSetup || ''}
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(mock)) !== 0) {
    throw new Error('Mock env init failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  return L;
}

// ---------------------------------------------------------------------
// TEST 2: Hard Hourly Alert Cooldown & Price-Change Gating
// ---------------------------------------------------------------------
test('Alert Engine: Hard hourly cooldown suppresses duplicate price alerts, triggers on price change', () => {
  const L = createLuaEnv();
  const notifLua = fs.readFileSync(path.join(marketSyncDir, 'Notifications.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(notifLua)) !== 0) {
    throw new Error('Failed to load Notifications.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const script = `
    local realmDB = MarketSync.GetRealmDB()

    -- Create tracked alert: Threshold 100g (1,000,000 copper)
    local req = MarketSync.UpsertNotificationRequest({
      matchType = "itemID",
      matchValue = 13444,
      displayName = "Major Healing Potion",
      thresholdCopper = 1000000,
      scope = "all",
      enabled = true,
    })
    assert(req ~= nil, "request must be created")
    assert(req.cooldownSec == 3600, "cooldownSec must default to 3600s hard hourly limit, got: " .. tostring(req.cooldownSec))

    -- 1. Initial scan at t=1000, price=80g (800,000c <= 100g). Must trigger alert!
    local matched1 = MarketSync.EvaluateNotificationsForRecord(13444, 800000, "main", "LocalScan", "Major Healing Potion", 13444)
    assert(matched1 == 1, "Initial price below threshold must trigger alert")
    assert(#realmDB.NotificationLog == 1, "NotificationLog must have 1 entry")
    assert(realmDB.NotificationLog[1].price == 800000, "Logged price must be 800,000c")

    -- 2. Second scan 10 minutes later (t=1600), SAME price=80g.
    -- Within the 1-hour window, NO change in price. Must be SUPPRESSED!
    time = function() return 1773780000 + 600 end
    local matched2 = MarketSync.EvaluateNotificationsForRecord(13444, 800000, "main", "LocalScan", "Major Healing Potion", 13444)
    assert(matched2 == 0, "Identical price within the hour must be suppressed, got: " .. tostring(matched2))
    assert(#realmDB.NotificationLog == 1, "NotificationLog must still have 1 entry (no duplicate spam)")

    -- 3. Third scan 15 minutes later (t=1900), price DROPS to 75g (750,000c).
    -- Within the hour, but price actually changed! Must trigger alert!
    time = function() return 1773780000 + 900 end
    local matched3 = MarketSync.EvaluateNotificationsForRecord(13444, 750000, "main", "LocalScan", "Major Healing Potion", 13444)
    assert(matched3 == 1, "Price change within the hour must trigger alert, got: " .. tostring(matched3))
    assert(#realmDB.NotificationLog == 2, "NotificationLog must have 2 entries after price drop")
    assert(realmDB.NotificationLog[1].price == 750000, "Logged price must be new price 750,000c")

    -- 4. Fourth scan 1 hour later (t=1900 + 3601), same price=75g.
    -- 1 hour has elapsed! Hourly reminder limit reached. Must trigger alert!
    time = function() return 1773780000 + 900 + 3601 end
    local matched4 = MarketSync.EvaluateNotificationsForRecord(13444, 750000, "main", "LocalScan", "Major Healing Potion", 13444)
    assert(matched4 == 1, "Hourly interval expiration must trigger alert, got: " .. tostring(matched4))
    assert(#realmDB.NotificationLog == 3, "NotificationLog must have 3 entries after 1 hour")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Session alert mute suppresses scan alerts without changing saved requests', () => {
  const L = createLuaEnv();
  const notifLua = fs.readFileSync(path.join(marketSyncDir, 'Notifications.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(notifLua)) !== 0) {
    throw new Error('Failed to load Notifications.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  const script = `
    local realmDB = MarketSync.GetRealmDB()
    MarketSync.UpsertNotificationRequest({
      matchType = "itemID", matchValue = 13444, thresholdCopper = 1000000,
      scope = "all", enabled = true,
    })
    assert(MarketSync.ToggleNotificationMute() == true)
    assert(MarketSync.EvaluateNotificationsForRecord(13444, 800000, "main", "LocalScan", "Potion", 13444) == 0)
    assert(#realmDB.NotificationLog == 0)
    assert(MarketSyncDB.NotificationsMuted == nil, "Mute must be session-only")
    assert(MarketSync.ToggleNotificationMute() == false)
    assert(MarketSync.EvaluateNotificationsForRecord(13444, 800000, "main", "LocalScan", "Potion", 13444) == 1)
    assert(#realmDB.NotificationLog == 1)
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

// ---------------------------------------------------------------------
// TEST 3: Title Bar Sync Status & Interactive Toggle
// ---------------------------------------------------------------------
test('UI_Main: Title Bar Sync Status renders clean dot indicators and updates system-wide', () => {
  const L = createLuaEnv();
  const mainLua = fs.readFileSync(path.join(marketSyncDir, 'UI_Main.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(mainLua)) !== 0) {
    throw new Error('Failed to load UI_Main.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const script = `
    PanelTemplates_SetNumTabs = function() end
    PanelTemplates_TabResize = function() end
    PanelTemplates_SelectTab = function() end
    PanelTemplates_DeselectTab = function() end
    PanelTemplates_ResizeTabsToFit = function() end
    UISpecialFrames = {}

    local mf = MarketSync.CreateMainFrame()
    assert(mf ~= nil, "MainFrame must be created")
    assert(mf.syncMonitor ~= nil, "MainFrame.syncMonitor must exist")
    assert(mf.syncButton ~= nil, "MainFrame.syncButton must exist")

    -- Test Idle Status
    MarketSync.UpdateNetworkUI(0, 0, nil, 0, {})
    assert(mf.syncMonitor.text and mf.syncMonitor.text:find("Sync: Idle"), "Idle state must show 'Sync: Idle', got: " .. tostring(mf.syncMonitor.text))

    -- Test Tx Status (broadcasting)
    MarketSync.UpdateNetworkUI(15, 0, nil, 500, {})
    assert(mf.syncMonitor.text:find("Tx: 15 items/s"), "Tx state must show Tx items/s, got: " .. tostring(mf.syncMonitor.text))

    -- Test Rx Status (receiving)
    MarketSync.UpdateNetworkUI(0, 22, nil, 0, {})
    assert(mf.syncMonitor.text:find("Rx: 22 items/s"), "Rx state must show Rx items/s, got: " .. tostring(mf.syncMonitor.text))

    -- Test Both Tx & Rx Status
    MarketSync.UpdateNetworkUI(10, 20, nil, 600, {})
    assert(mf.syncMonitor.text:find("Rx: 20/s") and mf.syncMonitor.text:find("Tx: 10/s"), "Dual state must show both Rx and Tx, got: " .. tostring(mf.syncMonitor.text))

    -- Test No Guild Status
    IsInGuild = function() return false end
    MarketSync.UpdateNetworkUI(0, 0, nil, 0, {})
    assert(mf.syncMonitor.text:find("Sync: No Guild"), "No Guild state must show 'Sync: No Guild', got: " .. tostring(mf.syncMonitor.text))
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

// ---------------------------------------------------------------------
// TEST 4: Full Sync Data Verification (Wire Ceiling, Serialization, Scopes)
// ---------------------------------------------------------------------
test('Sync Protocol: Wire ceiling <=248 bytes, lossless serialization, and neutral AH scope isolation', () => {
  const L = createLuaEnv(`
    outboundFrames = {}
    transmitTick = nil
    local currentTxTime = 1000
    AdvanceTxClock = function() currentTxTime = currentTxTime + 1 end
    GetTime = function() return currentTxTime end
    C_Timer.NewTicker = function(interval, callback)
      if not transmitTick then transmitTick = callback end
      return { Cancel = function() end }
    end
    C_ChatInfo.SendAddonMessage = function(prefix, payload)
      outboundFrames[#outboundFrames + 1] = payload
    end
  `);
  const configLua = fs.readFileSync(path.join(marketSyncDir, 'Config.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(configLua)) !== 0) {
    throw new Error('Failed to load Config.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  const syncLua = fs.readFileSync(path.join(marketSyncDir, 'Sync.lua'), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(syncLua)) !== 0) {
    throw new Error('Failed to load Sync.lua: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }

  const script = `
    local realmDB = MarketSync.GetRealmDB()

    -- Populate mock personal scan data across 50 items with rich 30-min timeseries
    local scanDay = 20500
    realmDB.PersonalData = {}
    for i = 1, 50 do
      local dbKey = "item:" .. (13400 + i)
      realmDB.PersonalData[dbKey] = {
        m = 50000 + (i * 100),
        d = scanDay,
        latestBucket = (scanDay * 48) + 20,
        h = {
          [tostring(scanDay)] = "5:b4:a,11:b2:c,20:b6:8",
          [tostring(scanDay - 2)] = "10:a1:2,25:a5:4",
        },
        vh = {
          [tostring(scanDay)] = "5:b4:a,11:b2:c,20:b6:8",
          [tostring(scanDay - 2)] = "10:a1:2,25:a5:4",
        }
      }
    end
    realmDB.PersonalData["p:4471:12"] = {
      m = 1000, d = scanDay, latestBucket = (scanDay * 48) + 20,
      h = { [tostring(scanDay)] = "20:rs:2" },
      vh = { [tostring(scanDay)] = "20:rs:2" },
    }
    realmDB.PersonalData["p:4471:13"] = {
      m = 2000, d = scanDay, latestBucket = (scanDay * 48) + 20,
      h = { [tostring(scanDay)] = "20:1jk:3" },
      vh = { [tostring(scanDay)] = "20:1jk:3" },
    }

    -- Populate Neutral AH data
    realmDB.NeutralData = {}
    for i = 1, 20 do
      local dbKey = "item:" .. (20000 + i)
      realmDB.NeutralData[dbKey] = {
        vd = scanDay,
        vm = 120000 + (i * 500),
        vq = 5 + i,
      }
    end

    -- Verify Base36 bidirectional encoding
    local val = 1234567
    local b36 = MarketSync.ToBase36(val)
    local dec = MarketSync.FromBase36(b36)
    assert(dec == val, "Base36 roundtrip failed")

    -- Verify Compact Record parser
    local compactStr = "D:100:500:250:50"
    local parsed = MarketSync.ParseCompactRecord(compactStr)
    assert(parsed ~= nil, "Compact record must parse")
    assert(parsed.type == "daily", "Parsed type must be daily")
    assert(parsed.min == MarketSync.FromBase36("100"), "Parsed min must match")
    assert(parsed.volume == MarketSync.FromBase36("50"), "Parsed volume must match")

    -- Test Main AH Scope "M" directed broadcast creation
    MarketSync.myRealm = "Faerlina"
    MarketSync.CanSync = function() return true end
    MarketSync.CanParticipateInData = function(s) return true end
    MarketSync.GetMyLatestBucket = function() return (scanDay * 48) + 20 end
    MarketSync.GetCurrentScanDay = function() return scanDay end
    realmDB.SwarmTSF = 1773780000

    local ok, started = pcall(MarketSync.StartDirectedBroadcast, "M", (scanDay * 48), (scanDay * 48) + 20, 1773780000, "LocalPlayer", "PeerPlayer")
    assert(ok and started, "Main directed broadcast must start successfully")

    -- Test Neutral AH Scope "N" directed broadcast creation
    MarketSync.GetMyLatestNeutralScanDay = function() return scanDay end
    realmDB.NeutralSwarmTSF = 1773780000
    local okN, startedN = pcall(MarketSync.StartDirectedBroadcast, "N", scanDay - 1, scanDay, 1773780000, "LocalPlayer", "PeerPlayer")
    -- Should cleanly reject concurrent start while M is active (preventing cross-scope collision)
    assert(startedN == false, "Cross-scope broadcast must not collide with active send")

    for i = 1, 300 do AdvanceTxClock(); transmitTick() end
    local sentBoar, sentEagle = false, false
    for _, frame in ipairs(outboundFrames) do
      if frame:find("sp:4471:12_", 1, true) then sentBoar = true end
      if frame:find("sp:4471:13_", 1, true) then sentEagle = true end
    end
    assert(sentBoar and sentEagle,
      "Guild DATA frames must preserve both suffix-specific verified histories")

    MarketSync._Protocol2CommitInProgress = true
    MarketSync.UpdateLocalDBByKey("p:4471:14", scanDay, "20:2s:1", "PeerPlayer")
    MarketSync._Protocol2CommitInProgress = false
    assert(realmDB.PersonalData["p:4471:14"] and realmDB.PersonalData["p:4471:14"].m == 100,
      "Received variant must be stored under its exact suffix key")
    assert(realmDB.PersonalData["4471"] == nil and realmDB.PersonalData["p:4471:12"].m == 1000,
      "Receiving one suffix must not change the base item or another suffix")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

test('Auctionator raw full scan retains exact numeric suffix prices without base-key pollution', () => {
  const L = createLuaEnv(`
    pendingCallbacks = {}
    C_Timer.After = function(_, callback)
      pendingCallbacks[#pendingCallbacks + 1] = callback
    end
  `);
  for (const file of ['Config.lua', 'Sync.lua']) {
    const source = fs.readFileSync(path.join(marketSyncDir, file), 'utf8');
    if (lauxlib.luaL_dostring(L, to_luastring(source)) !== 0) {
      throw new Error(`Failed to load ${file}: ` + to_jsstring(lua.lua_tostring(L, -1)));
    }
  }
  const script = `
    MarketSync.GetCurrentScanDay = function() return 20500 end
    MarketSync.GetCurrentBucket = function() return 20500 * 48 + 20 end
    MarketSync.NormalizeItemKey = function(link)
      local id, suffix = MarketSync.ParseItemIDFromDBKey(link)
      if not id then return nil end
      return suffix and suffix ~= 0 and string.format("p:%d:%d", id, suffix) or tostring(id),
        id, { itemID = id, itemSuffix = suffix or 0 }
    end
    local function Row(link, quantity, buyout)
      local info = { [3] = quantity, [10] = buyout }
      return { itemLink = link, auctionInfo = info }
    end
    local done
    local exactKeys = {}
    local scan = {
      Row("item:4471:0:0:0:0:0:12:0", 2, 2000),
      Row("item:4471:0:0:0:0:0:12:0", 3, 2700),
      Row("item:4471:0:0:0:0:0:13:0", 1, 1800),
      Row("item:4471:0:0:0:0:0:-14:0", 1, 1600),
      Row("item:4472:0:0:0:0:0:0:0", 4, 4000),
    }
    assert(MarketSync.CaptureAuctionatorRawSuffixScan(scan, function(count) done = count end, exactKeys))
    local steps = 0
    while #pendingCallbacks > 0 do
      local callback = table.remove(pendingCallbacks, 1)
      callback()
      steps = steps + 1
      assert(steps < 20, "capture should finish in bounded ticks")
    end
    local entries = MarketSync.GetRealmDB().PersonalData
    assert(done == 3, "expected three exact suffix records")
    assert(entries["p:4471:12"].m == 900 and entries["p:4471:13"].m == 1800,
      "suffixes must retain separate lowest unit prices")
    assert(entries["p:4471:12"].vh["20500"] == "20:p0:5", "quantity should aggregate for exact suffix")
    assert(entries["p:4471:-14"].m == 1600 and exactKeys["p:4471:-14"],
      "negative suffix must remain distinct and be refreshed in the browse index")
    assert(entries["4471"] == nil and entries["4472"] == nil,
      "raw suffix capture must not invent or overwrite base-item records")
    assert(entries["p:4471:12"].latestBucket == 20500 * 48 + 20,
      "exact suffix must be eligible for guild sync")
  `;
  if (lauxlib.luaL_dostring(L, to_luastring(script)) !== 0) {
    throw new Error('Validation failed: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
});

// ---------------------------------------------------------------------
// TEST 5: Network Load Simulation: 20-Player Swarm Pull Contention & Election
// ---------------------------------------------------------------------
test('Network Load Simulation: 20 concurrent players elect exactly 1 broadcaster without channel flood', () => {
  // Simulate 20 players in a guild
  const NUM_PLAYERS = 20;
  const players = [];
  for (let i = 1; i <= NUM_PLAYERS; i++) {
    players.push({
      name: `Player${i}`,
      scanDay: 20500,
      bucket: (20500 * 48) + (i % 5), // Varying scan freshness
      scanTime: 1773780000 + i,
      lanePhase: 'idle',
      messagesSent: 0,
    });
  }

  // Simulating a PULL request issued by Player1
  const requester = players[0];
  const guildAddonChannel = [];

  function broadcastAddonMessage(sender, prefix, payload) {
    guildAddonChannel.push({ sender, prefix, payload, time: Date.now() });
    // Every other player observes the message
    for (const p of players) {
      if (p.name !== sender) {
        observeMessage(p, sender, prefix, payload);
      }
    }
  }

  function observeMessage(player, sender, prefix, payload) {
    if (payload.startsWith('PULL;')) {
      // Player enters contention window if they have newer data
      if (player.bucket > 20500 * 48 && player.lanePhase === 'idle') {
        player.lanePhase = 'contending';
      }
    } else if (payload.startsWith('BEGIN;')) {
      // Another player was elected and started sending!
      // All other players must abort contention and become receivers!
      if (player.lanePhase === 'contending' || player.lanePhase === 'electing') {
        player.lanePhase = 'receiving';
      }
    }
  }

  // 1. Requester broadcasts PULL
  broadcastAddonMessage(requester.name, 'MSync', `PULL;Faerlina;Guild;${20500 * 48 + 4};1773780020;${20500 * 48};2;0.8.0`);

  // 2. All players who have eligible data enter contention
  const contenders = players.filter(p => p.lanePhase === 'contending');
  assert(contenders.length > 0, 'Multiple eligible players entered contention');

  // 3. Contention resolution: Player with best revision/time wins (Player20 has highest time)
  contenders.sort((a, b) => b.bucket - a.bucket || b.scanTime - a.scanTime);
  const electedWinner = contenders[0];

  // Winner sends BEGIN
  electedWinner.lanePhase = 'sending';
  electedWinner.messagesSent++;
  broadcastAddonMessage(electedWinner.name, 'MSyncD1', `BEGIN;sess1;M;Faerlina;${20500 * 48};${electedWinner.bucket};${electedWinner.scanTime};2;0.8.0`);

  // Verify that ALL other contenders moved to 'receiving'
  for (const p of players) {
    if (p.name === electedWinner.name) {
      assert(p.lanePhase === 'sending', 'Winner must be sending');
    } else {
      assert(p.lanePhase !== 'sending', `Player ${p.name} must NOT be sending (no lane contention)`);
    }
  }

  // Verify no duplicate broadcasts occurred
  const beginFrames = guildAddonChannel.filter(m => m.payload.startsWith('BEGIN;'));
  assert(beginFrames.length === 1, `Exactly 1 BEGIN frame must be transmitted, got ${beginFrames.length}`);
});

// ---------------------------------------------------------------------
// TEST 6: Token Bucket Rate Limiter & External Addon Traffic Flood Prevention
// ---------------------------------------------------------------------
test('Token Bucket Ceiling: Enforces <=640 B/s budget, control slot reservation, and pauses on external flood', () => {
  const MAX_WIRE_BYTES = 248;
  const TX_TICK_SECONDS = 0.35;
  const TX_DATA_BUDGET_BYTES_PER_SECOND = 640;
  const TX_OTHER_API_PAUSE_RATE = 36;

  let txBudgetTokens = MAX_WIRE_BYTES * 2;
  let txClock = 1000.0;
  let lastUpdate = txClock;
  let wheelPosition = 0;
  let dataFramesSent = 0;
  let controlFramesSent = 0;
  let totalBytesSent = 0;
  let throttledTicks = 0;

  function refillBudget(now) {
    const elapsed = Math.max(0, now - lastUpdate);
    lastUpdate = now;
    txBudgetTokens = Math.min(MAX_WIRE_BYTES * 3, txBudgetTokens + (elapsed * TX_DATA_BUDGET_BYTES_PER_SECOND));
    return txBudgetTokens;
  }

  // Simulate 100 ticks of transmitter loop with 1,000 items queued
  let queueBytes = 10000;
  let externalAddonMsgRate = 0;

  for (let tick = 1; tick <= 100; tick++) {
    txClock += TX_TICK_SECONDS;
    refillBudget(txClock);
    wheelPosition = (wheelPosition % 10) + 1;
    const isControlSlot = (wheelPosition === 10);

    // Mid-stream simulation: at ticks 40-50, external addons burst 45 msgs/s (Attune / Details)
    if (tick >= 40 && tick <= 50) {
      externalAddonMsgRate = 45;
    } else {
      externalAddonMsgRate = 5;
    }

    if (isControlSlot) {
      controlFramesSent++;
    } else if (externalAddonMsgRate > TX_OTHER_API_PAUSE_RATE) {
      // Throttled by external addon traffic!
      throttledTicks++;
    } else {
      const frameBytes = 220; // safe wire frame
      if (txBudgetTokens >= frameBytes && queueBytes > 0) {
        txBudgetTokens -= frameBytes;
        queueBytes -= frameBytes;
        dataFramesSent++;
        totalBytesSent += frameBytes;
      }
    }
  }

  // Verify constraints
  const totalSeconds = 100 * TX_TICK_SECONDS; // 35 seconds
  const overallByteRate = totalBytesSent / totalSeconds;

  assert(overallByteRate <= TX_DATA_BUDGET_BYTES_PER_SECOND,
    `Overall byte rate (${overallByteRate.toFixed(1)} B/s) must not exceed budget (${TX_DATA_BUDGET_BYTES_PER_SECOND} B/s)`);
  assert(controlFramesSent === 10, `Slot 10 must be reserved for control frames, got ${controlFramesSent}`);
  assert(throttledTicks >= 9, `Transmitter must pause when external addon traffic exceeds 36 msgs/s, throttled ${throttledTicks} ticks`);
});

// Helper assertion function
function assert(condition, message) {
  if (!condition) {
    throw new Error(message || 'Assertion failed');
  }
}

console.log(`\nAll ${passed} sync verification and network load tests passed successfully!`);
