const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');
const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
for (const file of ['Config.lua', 'Favorites.lua', '../MarketSyncLedger/CraftLedger.lua',
  '../MarketSyncLedger/PurchaseList.lua', '../MarketSyncLedger/ItemLedger.lua', 'InventoryTracking.lua', '../MarketSyncLedger/TransactionTracking.lua']) {
  sim.loadLuaFile(path.join(__dirname, '../MarketSync', file));
}
sim.run(String.raw`
  MarketSync.InitializeDB()
  ERR_TRADE_COMPLETE='Trade complete.'
  ERR_AUCTION_BID_PLACED='Bid accepted.'
  LOOT_ITEM_SELF='You receive loot: %s.'
  LOOT_ITEM_CREATED_SELF='You create: %s.'
  local link='|Hitem:1001:0:0:0:0:0:0:0|h[Test item]|h'
  local loot='You receive loot: '..link..'.'
  local crafted='You create: '..link..'.'
  local restricted={ [ERR_TRADE_COMPLETE]=true, [ERR_AUCTION_BID_PLACED]=true,
    [loot]=true, [crafted]=true, LSHIFT=true }
  local restrict=true
  issecretvalue=function(value) return restrict and restricted[value] or false end
  local I,L,T,P=MarketSync.ItemLedger,MarketSync.CraftLedger,MarketSync.LedgerTracking,MarketSync.PurchaseList
  local trades,receipts,outputs,loots,tooltips
  I.Record=function(kind)
    if kind=='trade' then trades=trades+1 end
    if kind=='loot received' then loots=loots+1 end
  end
  L.RecordPurchase=function() receipts=receipts+1 end
  L.ConfirmCraftOutput=function() outputs=outputs+1 end
  MarketSync.RefreshActiveTooltip=function() tooltips=tooltips+1 end

  for _, enabled in ipairs({false,true}) do
    MarketSyncDB.EnableLedgerBeta=enabled
    trades,receipts,outputs,loots,tooltips=0,0,0,0,0
    restrict=true
    local trade={accepted=true,expires=time()+30}
    local purchase={itemID=1001,qty=1,paid=100,expires=GetTime()+30}
    T.trade=trade;L.pendingPurchase=purchase
    L.expectedCraft={itemID=1001,expires=GetTime()+30}
    P.state='awaiting';P.confirmed=nil
    assert(type(ERR_TRADE_COMPLETE)=='string' and not MarketSync.IsSafeString(ERR_TRADE_COMPLETE),
      'Secret values still report type string; type alone cannot override a rejection')
    A_Admin.FireEvent('CHAT_MSG_SYSTEM',ERR_TRADE_COMPLETE)
    A_Admin.FireEvent('CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED)
    A_Admin.FireEvent('CHAT_MSG_LOOT',loot)
    A_Admin.FireEvent('CHAT_MSG_LOOT',crafted)
    A_Admin.FireEvent('MODIFIER_STATE_CHANGED','LSHIFT',1)
    assert(T.trade==trade,'Rejected system message must not clear the pending trade')
    assert(L.pendingPurchase==purchase,'Rejected system message must not consume the pending purchase')
    assert(not P.confirmed,'Rejected system message must not confirm the purchase queue')
    assert(trades==0 and receipts==0 and outputs==0 and loots==0 and tooltips==0,
      'Rejected chat strings must not reach comparison, parsing, or receipt/tooltip actions')
    assert(L.ParseReceipt(loot,{LOOT_ITEM_SELF})==nil,'Direct receipt parser rejects secret strings too')

    restrict=false
    A_Admin.FireEvent('CHAT_MSG_SYSTEM','Unrelated system message')
    assert(T.trade==trade and L.pendingPurchase==purchase and not P.confirmed)
    A_Admin.FireEvent('CHAT_MSG_SYSTEM',ERR_TRADE_COMPLETE)
    A_Admin.FireEvent('CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED)
    A_Admin.FireEvent('CHAT_MSG_LOOT',loot)
    A_Admin.FireEvent('CHAT_MSG_LOOT',crafted)
    A_Admin.FireEvent('MODIFIER_STATE_CHANGED','LSHIFT',1)
    assert(T.trade==(not enabled and trade or nil) and trades==(enabled and 1 or 0),
      'Only the enabled observer handles trade confirmations')
    assert(L.pendingPurchase==nil and receipts==1 and P.confirmed,'Readable purchase confirmation is still routed')
    assert(outputs==1 and loots==(enabled and 1 or 0) and tooltips==1,
      'Readable craft, loot and modifier events retain their normal behavior')
    A_Admin.FireEvent('CHAT_MSG_SYSTEM',ERR_TRADE_COMPLETE)
    A_Admin.FireEvent('CHAT_MSG_SYSTEM',ERR_AUCTION_BID_PLACED)
    assert(trades==(enabled and 1 or 0) and receipts==1,'Duplicate readable messages do not re-record receipts')
  end
`, 'secretStringChatRegression');
console.log('PASS secret strings are rejected without state changes; readable trade, purchase, loot and craft receipts still work');
