const fs = require('fs');
const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');

const addon = path.join(__dirname, '../MarketSync');

const legacyClients = [
  ['Forever', 16001],
  ['Classic Era', 11509],
  ['Season of Discovery', 11509],
  ['Anniversary', 20506],
  ['TBC', 20506],
  ['Classic progression', 50503],
];
for (const [name, interfaceNumber] of legacyClients) {
  const client = createAddonSim({ flavor: name === 'Forever' ? 'forever' : 'classic', interface: interfaceNumber });
  for (const file of ['Config.lua', 'InventoryTracking.lua']) {
    client.loadLuaFile(path.join(addon, file));
  }
  client.run(`
    MarketSync.InitializeDB()
    TooltipDataProcessor = nil
    C_Container = nil
    local reads = 0
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
    GetContainerItemInfo = function()
      reads = reads + 1
      return nil, 3, nil, nil, nil, nil, '|Hitem:555|h[Ore]|h', nil, nil, 555
    end
    local T = MarketSync.InventoryTracking
    T.InstallTooltips()
    local update = assert(GameTooltip:GetScript('OnTooltipSetItem'))
    GameTooltip:SetItemByID(5335)
    update(GameTooltip)
    assert(GameTooltip:NumLines() == 1, 'An untracked item keeps only its normal tooltip text')

    A_Admin.FireEvent('PLAYER_LOGIN')
    GameTooltip:SetItemByID(555)
    update(GameTooltip)
    assert(GameTooltip.lines[2].right:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') == 'Total 3' and not MarketSync.ItemLedger)
    if MarketSync.GetClientFlavor() == 'forever' then
      GetRealmName = function() return '' end
      GetNormalizedRealmName = GetRealmName
      UnitName = function() return 'Blauto', 'Theblind' end
      UnitClass = function() return 'Hunter', 'HUNTER' end
      RegionalUniqueNamesEnabled = function() return true end
      RAID_CLASS_COLORS = { HUNTER = { colorStr = 'ffabd473' } }
      Enum = { GameRule = { PvPRuleset = 1, RPRuleset = 2 } }
      C_GameRules = { IsGameRuleActive = function(rule) return rule == 1 end }
      MarketSyncDB.InventoryTracking['Blauto-CAMWOW US2 Realm 6 PvP'] = {
        bags = { at = 10, complete = true, quantities = { [555] = 19, [989] = 7 } },
        bank = { at = 10, complete = true, quantities = { [555] = 4 } },
      }
      MarketSyncDB.InventoryTracking['Hearing-CAMWOW US2 Realm 6 PvP'] = {
        bank = { at = 10, complete = true, quantities = { [555] = 3 } },
      }
      MarketSyncDB.InventoryTracking['Hearing-'] = {
        bank = { at = 12, complete = true, quantities = { [555] = 2 } },
      }
      T.CaptureBags()
      GameTooltip:ClearLines()
      GameTooltip.MarketSyncOwnershipItem = nil
      GameTooltip:SetItemByID(555)
      update(GameTooltip)
      assert(GameTooltip.lines[3].left:find('|cffabd473Blauto Theblind|r', 1, true))
      local byOwner = {}
      for _, entry in ipairs(T.Holdings(555)) do
        byOwner[entry.owner] = (byOwner[entry.owner] or 0) + entry.qty
      end
      assert(byOwner['Blauto Theblind-pvp'] == 7 and byOwner['Blauto-CAMWOW US2 Realm 6 PvP'] == nil)
      assert((byOwner['Hearing-'] or byOwner['Hearing-CAMWOW US2 Realm 6 PvP']) == 2)
      assert(#T.Holdings(989) == 0, 'An older bag record must not restore a sold item')
    end

    T.SetEnabled(false)
    local previousReads = reads
    A_Admin.FireEvent('BAG_UPDATE_DELAYED')
    A_Admin.AdvanceTime(1)
    GameTooltip:SetItemByID(555)
    update(GameTooltip)
    assert(reads == previousReads and GameTooltip:NumLines() == 1)
  `, `${name} legacy inventory APIs without Ledger`);
  console.log(`PASS ${name} legacy inventory APIs without Ledger`);
}

const sim = createAddonSim({ flavor: 'retail', interface: 120001 });
for (const file of ['Config.lua', 'Theme.lua', 'InventoryTracking.lua', 'Core.lua']) {
  sim.loadLuaFile(path.join(addon, file));
}

sim.run(`
  MarketSync.InitializeDB()
  local T = MarketSync.InventoryTracking
  local scans, mailScans = 0, 0
  local bankItems = 4
  C_Container.GetContainerNumSlots = function(bag) return (bag == 0 or bag == 6) and 1 or 0 end
  C_Container.GetContainerItemInfo = function(bag)
    scans = scans + 1
    return { itemID = 555, stackCount = bag == 6 and bankItems or 3 }
  end
  Enum = { TooltipDataType = { Item = 0 }, BankType = { Character = 0 } }
  C_Bank = {
    CanViewBank = function() return bankItems > 0 end,
    FetchPurchasedBankTabIDs = function() return { 6 } end,
  }
  TooltipDataProcessor = { AddTooltipPostCall = function(_, handler) InventoryTooltip = handler end }
  GetInboxNumItems = function() return 1, 2 end
  GetInboxItem = function(_, slot)
    mailScans = mailScans + 1
    if slot == 1 then return 'Ore', 555, nil, 2 end
  end

  -- Retail calls this for quest items with no snapshot and for helper tooltips.
  T.InstallTooltips()
  InventoryTooltip(GameTooltip, { id = 5335 })
  InventoryTooltip({ GetItem = function() error('ItemRack helper tooltip was read') end }, { id = 5340 })
  assert(#GameTooltip.lines == 0 and not MarketSync.ItemLedger)

  MarketSyncDB.InventoryTracking = nil
  MarketSyncDB.ItemLedger = {
    nextID = 1, characters = {
      historical = { owner = 'Alt-Other Realm', storage = { bags = {
        items = { ['555:0'] = { itemID = 555, qty = 5 } }, at = time(),
      } } },
    },
    transactions = { [1] = { id = 1, kind = 'old record', metadata = { note = 'preserve' } } },
    lots = {}, seen = {}, reservations = {},
  }
  A_Admin.FireEvent('PLAYER_LOGIN')
  A_Admin.FireEvent('MAIL_SHOW')
  A_Admin.FireEvent('BANKFRAME_OPENED')
  bankItems = 0
  T.CaptureBank()
  local holdings, total = T.Holdings(555), 0
  for _, entry in ipairs(holdings) do
    total = total + entry.qty
    if entry.storage == 'mail' then assert(entry.complete == false) end
  end
  assert(#holdings == 4 and total == 14, 'Bags, alts, bank and mail add up')
  GameTooltip:ClearLines()
  InventoryTooltip(GameTooltip, { id = 555 })
  assert(GameTooltip.lines[1].right:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') == 'Total 14')

  A_Admin.FireEvent('BAG_UPDATE_DELAYED')
  T.SetEnabled(false)
  local oldScans, oldMailScans = scans, mailScans
  A_Admin.FireEvent('BAG_UPDATE_DELAYED')
  A_Admin.FireEvent('MAIL_INBOX_UPDATE')
  A_Admin.AdvanceTime(1)
  assert(scans == oldScans and mailScans == oldMailScans and #T.Holdings(555) == 0)
  GameTooltip:ClearLines()
  InventoryTooltip(GameTooltip, { id = 555 })
  assert(#GameTooltip.lines == 0, 'Disabling tracking removes inventory lines')
  T.SetEnabled(true)
  assert(scans > oldScans and mailScans > oldMailScans and #T.Holdings(555) == 4)
`, 'Inventory without Ledger');

const ledgerTOC = fs.readFileSync(path.join(addon, '../MarketSyncLedger/MarketSyncLedger.toc'), 'utf8');
sim.run(`
  LedgerNamespace = {}
  C_AddOns.IsAddOnLoaded = function(name) return name == 'MarketSyncLedger' end
  MarketSync.GetRealmDB().CraftLedger = {
    nextID = 1, jobs = { [1] = { id = 1, owner = UnitName('player') .. '-' .. GetRealmName(), quantity = 2 } },
  }
  MarketSyncDB.EnableLedgerBeta = true
`);
for (const file of ledgerTOC.split(/\r?\n/).filter(line => line.endsWith('.lua'))) {
  const source = fs.readFileSync(path.join(addon, '../MarketSyncLedger', file), 'utf8');
  sim.run(`assert(load([====[${source}]====], '@${file}'))('MarketSyncLedger', LedgerNamespace)`, file);
}
sim.run(`
  A_Admin.FireEvent('ADDON_LOADED', 'MarketSyncLedger')
  assert(MarketSync.CanOpenLedger() and SlashCmdList.MARKETSYNCLEDGER)
  local I, L = MarketSync.ItemLedger, MarketSync.CraftLedger
  assert(I.Get(1).metadata.note == 'preserve' and L.Get(1).quantity == 2)
  I.Get(1).metadata.note = 'updated'
  L.Get(1).quantity = 4
  assert(MarketSyncDB.ItemLedger.transactions[1].metadata.note == 'preserve')
  assert(MarketSyncDB.RealmData[MarketSync.GetFactionRealmKey()].CraftLedger.jobs[1].quantity == 2)
  assert(MarketSyncLedgerDB.items == I.Store() and MarketSyncLedgerDB.crafts[MarketSync.GetFactionRealmKey()].jobs[1].quantity == 4)
  MarketSync.SetLedgerEnabled(false)
  assert(not MarketSync.CanOpenLedger() and #MarketSync.InventoryTracking.Holdings(555) > 0)
`, 'Optional Ledger storage and activation');

sim.run(`
  local launcher
  LibStub = function(name)
    if name == 'LibDataBroker-1.1' then
      return { NewDataObject = function(_, _, object) return object end }
    elseif name == 'LibDBIcon-1.0' then
      return {
        Register = function(_, key, object)
          if key == 'MarketSync' then launcher = object end
        end,
        GetMinimapButton = function() return nil end,
      }
    end
  end
  A_Admin.FireEvent('ADDON_LOADED', 'MarketSync')
  assert(launcher, 'MarketSync minimap launcher is registered')
  local settingsOpens, ledgerOpens = 0, 0
  local shift, loaded = false, false
  IsShiftKeyDown = function() return shift end
  C_AddOns.IsAddOnLoaded = function(name) return loaded and name == 'MarketSyncLedger' end
  MarketSync.OpenSettings = function() settingsOpens = settingsOpens + 1 end
  MarketSync.ToggleItemLedger = function() ledgerOpens = ledgerOpens + 1 end
  local function CheckTooltip(action)
    GameTooltip:ClearLines()
    launcher.OnTooltipShow(GameTooltip)
    assert(GameTooltip.lines[4].left:find(action, 1, true))
  end
  LedgerNamespace.GetDB().enabled = true
  launcher.OnClick(nil, 'RightButton')
  assert(settingsOpens == 1 and ledgerOpens == 0, 'An unloaded Ledger opens MarketSync settings')
  CheckTooltip('for Settings')
  loaded = true
  LedgerNamespace.GetDB().enabled = false
  launcher.OnClick(nil, 'RightButton')
  assert(settingsOpens == 2 and ledgerOpens == 0, 'Disabled Ledger opens MarketSync settings')
  CheckTooltip('for Settings')
  LedgerNamespace.GetDB().enabled = true
  launcher.OnClick(nil, 'RightButton')
  assert(settingsOpens == 2 and ledgerOpens == 1, 'An active Ledger handles the optional shortcut')
  CheckTooltip('to Open Item Ledger')
  shift = true
  launcher.OnClick(nil, 'RightButton')
  assert(settingsOpens == 3 and ledgerOpens == 1, 'Shift-right-click always opens settings')
`, 'MarketSync minimap right-click');

sim.run(`
  MarketSync.ReviewMarketSyncData()
  local status = MarketSync._dataReviewFrame
  assert(status._template == 'PortraitFrameTemplate' and status.Status:GetText():find('MarketSyncData is not loaded'))
  A_Admin.interface = 16001
  GetNormalizedRealmName = function() return 'PvP2' end
  MarketSyncData = { flavor = 'forever', injected = true, version = '2026.11.23' }
  MarketSyncDataDB = {
    ['pvp@Horde'] = { ['555'] = { m = 43 }, ['556'] = { m = 0 }, ['557'] = { m = 55 } },
    ['pvp@Alliance'] = { ['555'] = { m = 56 } },
  }
  MarketSync.ReviewMarketSyncData()
  assert(status.Status:GetText():find('Loaded') and status.PackRecords:GetText() == '2'
    and status.ActiveRecords:GetText() == '0', 'An earlier import does not imply any active prices')
  assert(status.Market:GetText() == 'PvP2 / Horde' and status.PackVersion:GetText() == '2026.11.23')
  MarketSync.GetRealmDB().GuildData['555'] = { src = 'DataPack', m = 43 }
  MarketSync.GetRealmDB().GuildData['556'] = { src = 'Guild', m = 45 }
  MarketSync.ReviewMarketSyncData()
  assert(status.Status:GetText():find('Connected') and status.ActiveRecords:GetText() == '1')
  A_Admin.faction = 'Alliance'
  MarketSync.ReviewMarketSyncData()
  assert(status.Status:GetText():find('Loaded') and status.PackRecords:GetText() == '1'
    and status.ActiveRecords:GetText() == '0', 'Pack records stay scoped to the current faction')
  MarketSyncData.prices = { [555] = 43 }
  MarketSync.ReviewMarketSyncData()
  assert(status.Status:GetText():find('Connected') and status.ActiveRecords:GetText() == '1',
    'Flat price packs still supply active records')
  A_Admin.Click(status.CloseButton)
  assert(not status:IsShown())
`, 'MarketSyncData status');

console.log('PASS inventory, Retail tooltips, scan toggle, Ledger migration, minimap right-click, and MarketSyncData status');
