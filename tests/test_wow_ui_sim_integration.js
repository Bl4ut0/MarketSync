// ============================================================================
// Integration Test Suite: WoW Addon Simulator (wow_addon_sim.js)
// Exercises layout/anchor cycle detection, A_Admin combat lockdown & taint
// checks, Forever surname server-echoed CHAT_MSG_ADDON loopback, deterministic
// C_Timer advancement, and right-click context menu interaction.
// ============================================================================

const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');

const ROOT = path.resolve(__dirname, '..');
const ADDON_DIR = path.join(ROOT, 'MarketSync');

function testAnchorCycleAndGeometrySolver() {
  const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
  sim.run(`
    local parent = CreateFrame("Frame", "SimTestParent", UIParent)
    parent:SetSize(500, 400)

    local child = CreateFrame("Frame", "SimTestChild", parent)
    child:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -40)
    child:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 20)

    assert(child:GetWidth() == 468, "Two-point width should be 500 - 16 - 16 = 468, got " .. tostring(child:GetWidth()))
    assert(child:GetHeight() == 340, "Two-point height should be 400 - 40 - 20 = 340, got " .. tostring(child:GetHeight()))

    local frameA = CreateFrame("Frame", "SimCycleA", UIParent)
    local frameB = CreateFrame("Frame", "SimCycleB", UIParent)
    local frameC = CreateFrame("Frame", "SimCycleC", UIParent)

    frameA:SetPoint("TOPLEFT", frameB, "BOTTOMLEFT", 0, -4)
    frameB:SetPoint("TOPLEFT", frameC, "BOTTOMLEFT", 0, -4)

    local ok, err = pcall(function()
      frameC:SetPoint("TOPLEFT", frameA, "BOTTOMLEFT", 0, -4)
    end)
    assert(not ok, "Circular SetPoint dependency should throw an error")
    assert(tostring(err):find("Cannot anchor to a region dependent on it", 1, true), "Expected anchor cycle message, got: " .. tostring(err))
  `, 'testAnchorCycleAndGeometrySolver');
  console.log('  [PASS] Layout geometry solver & anchor-cycle detection');
}

function testCombatLockdownTaintAndEscapeHandling() {
  for (const flavor of ['forever', 'legacy']) {
    const iface = flavor === 'forever' ? 16001 : 20506;
    const sim = createAddonSim({ flavor, interface: iface });
    sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
    sim.loadLuaFile(path.join(ADDON_DIR, 'Theme.lua'));

    sim.run(`
      MarketSync.InitializeDB()
      local w1 = CreateFrame("Frame", "SimEscWin1", UIParent, "BackdropTemplate")
      w1:SetSize(420, 300)
      MarketSync.Theme.DecorateWarcraftWindow(w1, "Interface\\\\Icons\\\\INV_Misc_Coin_01")
      MarketSync.RegisterEscapeFrame(w1)

      local w2 = CreateFrame("Frame", "SimEscWin2", UIParent, "BackdropTemplate")
      w2:SetSize(420, 300)
      MarketSync.Theme.DecorateWarcraftWindow(w2, "Interface\\\\Icons\\\\INV_Misc_Book_09")
      MarketSync.RegisterEscapeFrame(w2)

      w1:Show()
      w2:Show()
      assert(w1:IsShown() and w2:IsShown(), "Both windows should be shown")
      assert(w1.warcraftEmblem and w1.warcraftRing and w1.warcraftTitleBg, "Warcraft window decoration should attach circular portrait ring, emblem, and title header banner")
      assert(not w1._hasOnKeyDown and not w2._hasOnKeyDown, "Standard windows must not use OnKeyDown (combat taint risk)")

      -- Enter combat lockdown and verify Escape still closes UISpecialFrames cleanly without taint
      A_Admin.SetInCombat(true)
      assert(InCombatLockdown() == true, "Should be in combat lockdown")

      local closed1 = A_Admin.PressEscape()
      assert(closed1 == 1 and not w2:IsShown() and w1:IsShown(), "First Escape should close top UISpecialFrame (w2)")
      local closed2 = A_Admin.PressEscape()
      assert(closed2 == 1 and not w1:IsShown(), "Second Escape should close remaining UISpecialFrame (w1)")
      assert(#A_Admin.taintErrors == 0, "Closing standard windows in combat should produce zero taint errors")

      -- Verify protected actions DO trigger taint guard during combat lockdown
      local secBtn = CreateFrame("Button", "SimSecureBtn", UIParent, "SecureActionButtonTemplate")
      local okAttr = pcall(function()
        secBtn:SetAttribute("type", "item")
      end)
      assert(not okAttr, "SecureActionButtonTemplate:SetAttribute must fail during InCombatLockdown()")
      assert(#A_Admin.taintErrors == 1, "Taint error should be recorded")

      A_Admin.SetInCombat(false)
      secBtn:SetAttribute("type", "item")
      assert(secBtn:GetAttribute("type") == "item", "SetAttribute should succeed outside combat")
    `, `testCombatLockdown_${flavor}`);
  }
  console.log('  [PASS] Combat lockdown taint guard & UISpecialFrames Escape lifecycle (forever & legacy)');
}

function testForeverSurnameLoopbackAndSwarmQueueLifecycle() {
  const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
  sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Theme.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Sync.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Chat.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'UI_Monitor.lua'));

  sim.run(`
    MarketSync.InitializeDB()

    -- Verify Forever UnitFullName returns FirstName, Surname while wire sender has FirstName Surname-Realm
    local fn, sn = UnitFullName("player")
    assert(fn == "Blauto" and sn == "Theblind", "Forever UnitFullName should return first + surname")
    assert(A_Admin.GetWireSenderIdentity() == "Blauto Theblind-ClassicBetaPvP2", "Forever wire sender identity mismatch")
    assert(MarketSync.IsLocalSyncIdentity("Blauto"), "Short first name must be recognized as local player")
    assert(MarketSync.IsLocalSyncIdentity("Blauto-Theblind"), "Hyphenated surname must be recognized as local player")
    assert(MarketSync.IsLocalSyncIdentity("Blauto Theblind"), "Space-separated surname must be recognized as local player")
    assert(MarketSync.IsLocalSyncIdentity("Blauto Theblind-ClassicBetaPvP2"), "Wire sender with surname+realm must be recognized as local player")

    -- Open the Network Monitor window so RenderSwarmUI runs when timers tick
    MarketSync.ToggleNetworkMonitor()

    -- Seed all 3 historical duplicate aliases into UpdateSwarmUI + start a guild pull contention window
    MarketSync.UpdateSwarmUI("Blauto-Theblind", "Awaiting Data")
    MarketSync.UpdateSwarmUI("Blauto", "Idle")
    MarketSync.ObserveGuildPull("M", "PeerAlpha-ClassicBetaPvP2", 3000, "Blauto Theblind-ClassicBetaPvP2", 1000, A_Admin.unix)
    A_Admin.AdvanceTime(0.1)

    local function countLocalPeers()
      local count, status = 0, nil
      for k, info in pairs(MarketSync.SwarmPeers) do
        if k:find("Blauto", 1, true) then
          count = count + 1
          status = info.status
        end
      end
      return count, status
    end

    local cnt1, st1 = countLocalPeers()
    assert(cnt1 == 1, "Local player must appear exactly once in SwarmPeers, got " .. tostring(cnt1))
    assert(st1 == "Electing Sync Source", "Expected Electing Sync Source during contention, got: " .. tostring(st1))

    -- Advance time past the 1.5s contention window -> should transition to Awaiting Data
    A_Admin.AdvanceTime(2)
    local cnt2, st2 = countLocalPeers()
    assert(cnt2 == 1, "Local player must still appear once after contention, got " .. tostring(cnt2))
    assert(st2 == "Awaiting Data", "Expected Awaiting Data after winning contention, got: " .. tostring(st2))

    -- Advance time past the 35s guild lane timeout -> must cleanly reset to Idle
    A_Admin.AdvanceTime(36)
    local cnt3, st3 = countLocalPeers()
    assert(cnt3 == 1, "Local player must still appear once after timeout, got " .. tostring(cnt3))
    assert(st3 == "Idle", "Expected local status to reset to Idle after pull timeout, got: " .. tostring(st3))

    -- Backend 0-100 shard parallelization test (e.g. "English 52" vs "English", "English 14", "English 0", "English 100")
    MarketSync.myRealm = "English"
    assert(MarketSync.IsSameSyncRealm("English", "English 52"), "English and English 52 must match as the same sync realm")
    assert(MarketSync.IsSameSyncRealm("English 52", "English 14"), "English 52 and English 14 must match")
    assert(MarketSync.IsSameSyncRealm("English 0", "English 100"), "English 0 and English 100 must match")
    assert(MarketSync.IsSameSyncRealm("English-52", "English_52"), "English-52 and English_52 must match")
    assert(MarketSync.IsSameSyncRealm("English #52", "English 52"), "English #52 and English 52 must match")
    assert(not MarketSync.IsSameSyncRealm("English 52", "German 52"), "Different language playsets must not match")

    -- Verify StripKnownRealmSuffix strips shard 52 and 100
    local base52, realm52 = MarketSync.StripKnownRealmSuffix("GuildPerson-English 52")
    assert(base52 == "GuildPerson" and realm52 == "English 52", "StripKnownRealmSuffix must strip English 52")
    local baseHyphen, realmHyphen = MarketSync.StripKnownRealmSuffix("GuildPerson-English-52")
    assert(baseHyphen == "GuildPerson", "StripKnownRealmSuffix must strip English-52")

    -- Verify UpdateSwarmUI strips shard 52 and deduplicates across shards 0-100
    MarketSync.UpdateSwarmUI("ShardPeer-English 52", "Ready")
    assert(MarketSync.SwarmPeers["ShardPeer"] ~= nil, "ShardPeer from English 52 must be registered in SwarmPeers as ShardPeer")
    assert(MarketSync.SwarmPeers["ShardPeer"].status == "Ready", "ShardPeer status should be Ready")

    -- Shard 14 update should update existing ShardPeer without creating duplicate row
    MarketSync.UpdateSwarmUI("ShardPeer-English 14", "Idle")
    local shardCount = 0
    for k in pairs(MarketSync.SwarmPeers) do
      if k:find("ShardPeer", 1, true) then shardCount = shardCount + 1 end
    end
    assert(shardCount == 1, "ShardPeer must appear exactly once in SwarmPeers across shards, got: " .. tostring(shardCount))
    assert(MarketSync.SwarmPeers["ShardPeer"].status == "Idle", "ShardPeer status should transition to Idle")
  `, 'testForeverSurnameLoopbackAndSwarmQueueLifecycle');

  console.log('  [PASS] Forever surname CHAT_MSG_ADDON loopback & Swarm Queue state transitions');
}

function testBagObservationAndRightClickResolution() {
  const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
  sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Theme.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'CraftLedger.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'PurchaseList.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'ItemLedger.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'InventoryTracking.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'UI_ItemLedger.lua'));

  sim.run(`
    MarketSync.InitializeDB()

    local I = MarketSync.ItemLedger
    -- When beta is disabled, Record is a no-op
    assert(not MarketSync.IsLedgerEnabled(), "Ledger beta should default to false")
    assert(I.Record("inventory observation", { state = "unresolved" }) == nil, "Record returns nil when ledger is disabled")

    -- Enable Ledger Beta
    MarketSync.SetLedgerEnabled(true)
    assert(MarketSync.IsLedgerEnabled() == true, "Ledger beta enabled")

    -- Seed an unresolved inventory observation
    local obs = I.Record("inventory observation", {
      state = "unresolved",
      metadata = { delta = { ["555:0"] = 5 } },
      evidence = "bag snapshot",
    })
    assert(obs and obs.state == "unresolved", "Seeded observation should be unresolved")

    -- Open the Item Ledger window and filter to 'Needs review'
    local f = MarketSync.OpenItemLedger()
    assert(f and f:IsShown(), "Item Ledger window should be open")
    A_Admin.Click(f.cards[3]) -- Click Needs Review summary card
    assert(f.filter == "review", "Clicking Needs Review card should set filter to review")

    -- Find the first visible row and trigger A_Admin.RightClick(row)
    local row = f.rows and f.rows[1]
    assert(row and row:IsShown(), "First review row should be visible")

    local menu = A_Admin.RightClick(row)
    assert(type(menu) == "table" and #menu >= 3, "Right-clicking an unresolved ledger row should open a context menu")

    -- Invoke the "Confirm: Mark Reviewed" resolution option from the right-click context menu
    local resolvedViaMenu = false
    for _, item in ipairs(menu) do
      if type(item.text) == "string" and item.text:find("Mark Reviewed", 1, true) and type(item.func) == "function" then
        item.func()
        resolvedViaMenu = true
        break
      end
    end
    assert(resolvedViaMenu, "Context menu should contain a callable 'Mark Reviewed' resolution item")
    assert(obs.state == "reconciled", "Observation should now be reconciled after clicking the context menu action")
  `, 'testBagObservationAndRightClickResolution');

  console.log('  [PASS] Interactive right-click context menu resolves unassigned bag observations');
}

function testTaintedSecretStringImmunity() {
  const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
  sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Theme.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'ObservationAPI.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'CraftLedger.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'PurchaseList.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Ledger', 'InventoryTracking.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Sync.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Chat.lua'));

  sim.run(`
    MarketSync.InitializeDB()

    -- Simulate Blizzard issecretvalue API and secret string values
    local secret1 = setmetatable({}, {
      __index = function(t, k) error("attempt to index local 'sender' (a secret string value, while execution tainted by 'MarketSync')") end,
      __eq = function(a, b) error("attempt to compare local 'message' (a secret string value, while execution tainted by 'MarketSync')") end,
    })
    local secret2 = setmetatable({}, {
      __index = function(t, k) error("attempt to index local 'msg' (a secret string value, while execution tainted by 'MarketSync')") end,
      __eq = function(a, b) error("attempt to compare local 'message' (a secret string value, while execution tainted by 'MarketSync')") end,
    })

    issecretvalue = function(v)
      return v == secret1 or v == secret2
    end

    -- 1. Test CHAT_MSG_GUILD with secret strings
    local okGuild, errGuild = pcall(function()
      A_Admin.FireEvent("CHAT_MSG_GUILD", secret2, secret1, "", "", secret1, "", 0, 0)
    end)
    assert(okGuild, "CHAT_MSG_GUILD with secret strings should not throw: " .. tostring(errGuild))

    -- 2. Test CHAT_MSG_SYSTEM with secret string (ERR_TRADE_COMPLETE / ERR_AUCTION_BID_PLACED)
    local okSys, errSys = pcall(function()
      A_Admin.FireEvent("CHAT_MSG_SYSTEM", secret1)
    end)
    assert(okSys, "CHAT_MSG_SYSTEM with secret string should not throw: " .. tostring(errSys))

    -- 3. Test CHAT_MSG_LOOT with secret string
    local okLoot, errLoot = pcall(function()
      A_Admin.FireEvent("CHAT_MSG_LOOT", secret1)
    end)
    assert(okLoot, "CHAT_MSG_LOOT with secret string should not throw: " .. tostring(errLoot))

    -- 4. Test CHAT_MSG_ADDON with secret strings
    local okAddon, errAddon = pcall(function()
      A_Admin.FireEvent("CHAT_MSG_ADDON", secret1, secret2, "GUILD", secret1)
    end)
    assert(okAddon, "CHAT_MSG_ADDON with secret strings should not throw: " .. tostring(errAddon))
  `, 'testTaintedSecretStringImmunity');

  console.log('  [PASS] Tainted execution and secret string immunity across Chat and Ledger systems');
}

console.log('Running WoW Addon Simulator integration tests...');
testAnchorCycleAndGeometrySolver();
testCombatLockdownTaintAndEscapeHandling();
testForeverSurnameLoopbackAndSwarmQueueLifecycle();
testBagObservationAndRightClickResolution();
testTaintedSecretStringImmunity();
console.log('All WoW Addon Simulator integration tests passed!');
