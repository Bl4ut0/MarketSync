const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const luaparse = require('luaparse');
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
function run(code) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
}
run(`
now=1000; who='Alice'; faction='Horde'; interface=16001; wallet=10000
function time() return now end; function GetTime() return now end
function UnitName(unit) return unit=='NPC' and 'Customer' or who end
function GetRealmName() return 'PvP2' end; function GetNormalizedRealmName() return 'PvP2' end
function UnitFactionGroup() return faction end; function GetBuildInfo() return '', '', '', interface end
function GetMoney() return wallet end
counts={}; function GetItemCount(id) return counts[id] or 0 end
UIParent={}; StaticPopupDialogs={}; function StaticPopup_Show() end
function widget()
 local w={scripts={},width=400,height=400,shown=true}
 setmetatable(w,{__index=function(_,key) if key:match('^[A-Z]') then return function() end end end})
 function w:SetScript(k,v) self.scripts[k]=v end
 function w:HookScript(k,v) self.scripts[k]=v end
 function w:SetSize(x,y) self.width=x;self.height=y end
 function w:GetWidth() return self.width end; function w:GetHeight() return self.height end
 function w:CreateFontString() return widget() end; function w:CreateTexture() return widget() end
 function w:SetText(value) self.text=value end
 function w:Show() self.shown=true end; function w:Hide() self.shown=false end
 function w:IsShown() return self.shown end
 return w
end
function CreateFrame(_,name) local w=widget(); if name then _G[name]=w end; return w end
hooks={}; function hooksecurefunc(name,fn) hooks[name]=fn end
MarketSyncDB={Favorites={},FavoriteQuantities={}}
MarketSync={GetRealmDB=function() return MarketSyncDB end,
 NormalizeSyncRealm=function(r) return interface==16001 and r:gsub('%d+$','') or r end,
 GetItemInfo=function(id) return 'Item '..id end}
function MarketSync.BuildCraftPurchasePlan(request)
 local buys,provided={},{}
 local target=request.selectedBuys[10]==false and provided or buys
 target[10]={itemID=10,qty=request.quantity*2,name='Ore',unitPrice=100}
 return {buys=buys,provided=provided,recipes={{outputQty=request.quantity}},buyCount=1}
end
`);
for (const file of ['Favorites.lua', 'Ledger/CraftLedger.lua', 'Ledger/ItemLedger.lua', 'Ledger/InventoryTracking.lua', 'Ledger/UI_ItemLedger.lua']) {
  const code = fs.readFileSync(path.join(__dirname, '../MarketSync', file), 'utf8');
  luaparse.parse(code, { luaVersion: '5.1' }); run(code);
}
run(`
local I,L,T=MarketSync.ItemLedger,MarketSync.CraftLedger,MarketSync.InventoryTracking

-- Beta Toggle Verification:
-- By default (EnableLedgerBeta = false), transactional recording is disabled,
-- but the light observation tracker still records storage snapshots for holdings tooltips!
assert(not MarketSync.IsLedgerEnabled(), 'Ledger beta defaults to disabled')
local disabledRec, disReason = I.Record('trade', { incoming = {{ itemID = 10, qty = 4 }} })
assert(disabledRec == nil and disReason == 'ledger_disabled', 'Transactions are not recorded when beta toggle is off')

-- Light observation tracking still records bag contents for tooltips:
I.Snapshot('bags', { ['10:0'] = { itemID = 10, qty = 4 } })
assert(#I.List() == 0, 'No opening inventory or observation transactions recorded when beta is off')
assert(#I.Holdings(10) == 1 and I.Holdings(10)[1].qty == 4, 'Holdings reports accurate bag count when beta is off')

-- Now enable Ledger Beta:
MarketSync.SetLedgerEnabled(true)
assert(MarketSync.IsLedgerEnabled() == true, 'Ledger enabled after SetLedgerEnabled(true)')

local key=I.Key('item:10:0:0:0:0:0:-7:0'); assert(key=='10:-7',key)
local a=assert(I.Record('trade',{incoming={{itemID=10,qty=4}},counterparty='Customer',token='trade1'}))
local again,state=I.Record('trade',{incoming={{itemID=10,qty=4}},token='trade1'})
assert(again.id==a.id and state=='duplicate')
assert(I.Lot(a.lots[1]).qty==4 and I.Lot(a.lots[1]).unitCost==nil)
assert(not I.Record('trade',{incoming={{itemID=10,qty=-1}}}))
assert(not I.Record('trade',{cashIn=0.5}))
assert(I.SetCost(a.id,400))
I.Snapshot('bags',{['10:0']={itemID=10,qty=4}})
assert(I.Reserve(100,'10:0',3))
assert(not I.Reserve(101,'10:0',2),'Reservations cannot claim the same physical units')
local cost,unknown=I.ReservedCost(100); assert(cost==300 and not unknown)
I.Release(100)
local sent=I.Record('mail sent',{outgoing={{itemID=10,qty=2}},counterparty='Bob-PvP2',fee=30})
who='Bob'
local received=I.Record('mail collected',{incoming={{itemID=10,qty=2}},counterparty='Alice-PvP2'})
I.Snapshot('bags',{['10:0']={itemID=10,qty=2}})
assert(I.LinkTransfer(sent.id,received.id))
local valued=0
for _,lot in ipairs(I.Store().lots) do if lot.owner==I.Owner() and lot.qty>0 then assert(lot.unitCost==100);valued=valued+lot.qty end end
assert(valued==2,'Own-character transfers preserve cost once')
assert(not I.LinkTransfer(sent.id,received.id))
assert(#I.Holdings(10)==2)
faction='Alliance';assert(#I.Holdings(10)==0,'Faction inventories stay partitioned');faction='Horde'
interface=11509; assert(#I.Holdings(10)==0,'Client inventories stay partitioned');interface=16001
who='Alice'
local recipe={outputItemID=100,name='Widget',outputQty=1,mats={{itemID=10,qty=2}}}
local job=assert(L.Save(recipe,{quantity=1}));assert(L.SetService(job.id,'Customer'))
local supply=I.Record('trade',{incoming={{itemID=10,qty=2}},cashIn=500,counterparty='Customer'})
assert(I.LinkService(supply.id,job.id,'materials'))
assert(job.status=='Purchased' and not job.shoppingName)
assert(I.LinkService(supply.id,job.id,'payment'),'Materials and payment can arrive in one exchange')
assert(not I.LinkService(supply.id,job.id,'payment'),'No duplicate financial role')
assert(L.Complete(job.id,1))
local returned=I.Record('mail sent',{outgoing={{itemID=100,qty=1}},fee=30,counterparty='Customer'})
assert(I.LinkService(returned.id,job.id,'delivery'))
local t=L.Totals(job);assert(t.gross==500 and t.fees==30 and t.profit==470)
assert(job.deliveredQty==1 and not L.RecordSale(job.id,1,10000,0))
local free=assert(L.Save(recipe,{quantity=1}));assert(L.SetService(free.id,'Customer'))
local freeSupply=I.Record('mail collected',{incoming={{itemID=10,qty=2}},counterparty='Customer'})
assert(I.LinkService(freeSupply.id,free.id,'materials'));assert(L.Complete(free.id))
assert(L.Totals(free).profit==0,'Unpaid customer craft creates no monetary gain')
local deposit=I.Record('trade',{cashIn=300,counterparty='Customer'})
assert(I.LinkService(deposit.id,free.id,'deposit'));assert(L.Totals(free).gross==0)
assert(L.Totals(free).deposits==300)
local provided=assert(L.Save(recipe,{quantity=1,selectedBuys={[10]=false}}))
assert(L.Complete(provided.id));assert(L.Totals(provided).unknownCost and L.Totals(provided).profit==nil)
local action=assert(L.Save({name='Enchant',mats={{itemID=10,qty=2}}},{quantity=1,selectedBuys={[10]=false}}))
assert(action.manualCraftOnly and L.Complete(action.id))
local saved=MarketSyncDB.ItemLedger
who='Bob';assert(#I.List()>0);who='Alice'
assert(I.Store()==saved and I.Get(supply.id).serviceID==job.id,'Facts persist independently of windows')
local purchase=I.Record('auction purchase',{incoming={{itemID=55,qty=2}},cashOut=600,actualCost=600,inTransit=true})
local mail=I.Record('mail collected',{incoming={{itemID=55,qty=2}},metadata={invoice={kind='buyer'}}})
assert(I.MatchPendingPurchase(mail));assert(I.Lot(mail.lots[1]).unitCost==300)
assert(I.Lot(purchase.lots[1]).qty==0)
-- Client identities with identical names cannot overwrite each other's storage.
interface=11509;I.Snapshot('bags',{['10:0']={itemID=10,qty=1}});interface=16001
assert(#I.Holdings(10)==2)
-- No forged income from deposits, deposit refunds or customer property.
local depositRefund=I.Record('trade',{cashOut=100,counterparty='Customer'})
assert(I.LinkService(depositRefund.id,free.id,'refund'));assert(L.Totals(free).profit==0)
assert(L.Totals(free).deposits==200)
assert(not I.LinkService(deposit.id,free.id,'payment'))
local earnedRefund=I.Record('trade',{cashOut=50,counterparty='Customer'})
assert(I.LinkService(earnedRefund.id,job.id,'earnedRefund'));assert(L.Totals(job).profit==420)
assert(not L.CorrectCrafted(job.id,0),'Delivered output cannot be removed by a correction')
local corrected=assert(L.Save(recipe,{quantity=1}))
assert(L.RecordPurchase(10,2,200,'correct-me',corrected.id));assert(corrected.status=='Purchased')
assert(L.CorrectPurchase(corrected.id,10,1,100));assert(corrected.status=='Shopping')
assert(L.Totals(corrected).paid==100 and #corrected.receipts==2)
assert(L.CorrectPurchase(corrected.id,10,2,200));assert(L.Complete(corrected.id))
assert(L.CorrectCrafted(corrected.id,0));assert(corrected.status=='Purchased')
-- Known cost survives user-stock intermediates and final output.
local stock=I.Record('vendor purchase',{incoming={{itemID=77,qty=2}},actualCost=400,cashOut=400})
I.Snapshot('bags',{['77:0']={itemID=77,qty=2}})
local nested=assert(L.Save({outputItemID=200,name='Nested',mats={{itemID=78,qty=1}}},{quantity=1,selectedBuys={[10]=false}}))
nested.plan.provided={[77]={itemID=77,qty=2}};assert(I.Reserve(nested.id,'77:0',2))
I.RecordComponent(nested,{outputQty=1,mats={{itemID=77,qty=2}}},78,1)
assert(nested.stockCost==400 and I.Lot(stock.lots[1]).qty==0)
assert(L.Complete(nested.id));assert(not L.Totals(nested).unknownCost and L.Totals(nested).paid==400)
local found=false
for _,lot in ipairs(I.Store().lots) do if lot.itemID==200 then assert(I.Cost(lot.id)==400);found=true end end
assert(found)
local parsed,quantity=L.ParseReceipt('Created 12 of item:100',{ 'Created %2$d of %1$s' })
assert(parsed==100 and quantity==12,'Localized positional receipt formats retain quantities')
local view=MarketSync.OpenItemLedger(job.id);assert(view.jobID==job.id)
`);
run(`
-- Client observer confirmations; cancelled/repeated events cannot commit facts.
local I,T=MarketSync.ItemLedger,MarketSync.InventoryTracking
local function Count(kind) local n=0;for _,tx in ipairs(I.List()) do if tx.kind==kind then n=n+1 end end;return n end
function GetTradePlayerItemInfo() return 'Ore',1,1 end
function GetTradePlayerItemLink() return 'item:10' end
function GetTradeTargetItemInfo() return 'Widget',1,1 end
function GetTradeTargetItemLink() return 'item:100' end
function GetPlayerTradeMoney() return 0 end;function GetTargetTradeMoney() return 200 end
ERR_TRADE_COMPLETE='Trade complete'
T.eventFrame.scripts.OnEvent(nil,'TRADE_SHOW')
T.eventFrame.scripts.OnEvent(nil,'TRADE_ACCEPT_UPDATE',1,1)
T.eventFrame.scripts.OnEvent(nil,'TRADE_REQUEST_CANCEL')
local before=Count('trade');T.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Trade complete');assert(Count('trade')==before)
T.eventFrame.scripts.OnEvent(nil,'TRADE_SHOW');T.eventFrame.scripts.OnEvent(nil,'TRADE_ACCEPT_UPDATE',1,1)
T.eventFrame.scripts.OnEvent(nil,'TRADE_CLOSED');T.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Trade complete')
assert(Count('trade')==before+1);T.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Trade complete');assert(Count('trade')==before+1)
mailItems={{itemID=99,qty=2}};mailMoney=0
function GetInboxNumItems() return 1,1 end
function GetInboxHeaderInfo() return nil,nil,'Friend','Supplies',mailMoney,0,20,#mailItems end
function GetInboxItem(_,slot) local item=mailItems[slot];if item then return 'Item',item.itemID,1,item.qty end end
function GetInboxItemLink(_,slot) local item=mailItems[slot];return item and 'item:'..item.itemID end
function TakeInboxItem() end;function TakeInboxMoney() end
T.InstallHooks();T.eventFrame.scripts.OnEvent(nil,'MAIL_SHOW')

-- When beta ledger is disabled, TakeInboxItem and TakeInboxMoney must not error and must not start collection tracking
MarketSync.SetLedgerEnabled(false)
hooks.TakeInboxItem(1, 1)
hooks.TakeInboxMoney(1)
assert(T.collections == nil, 'No collection batch or observation error when ledger beta is disabled')
MarketSync.SetLedgerEnabled(true)

local previous=Count('mail collected');hooks.TakeInboxItem(1,1)
assert(Count('mail collected')==previous,'Click is not confirmation')
mailItems={};counts[99]=2
T.eventFrame.scripts.OnEvent(nil,'MAIL_INBOX_UPDATE');assert(Count('mail collected')==previous+1)
T.eventFrame.scripts.OnEvent(nil,'MAIL_INBOX_UPDATE');assert(Count('mail collected')==previous+1)
mailMoney=100;T.eventFrame.scripts.OnEvent(nil,'MAIL_INBOX_UPDATE');hooks.TakeInboxMoney(1)
mailMoney=0;wallet=wallet+100;T.eventFrame.scripts.OnEvent(nil,'MAIL_INBOX_UPDATE')
assert(Count('mail collected')==previous+2)
-- Multiple attachment requests share quantity thresholds, not duplicate credits.
mailMoney=0;counts[88]=0;mailItems={{itemID=88,qty=2},{itemID=88,qty=3}}
T.CaptureMail();hooks.TakeInboxItem(1,1);hooks.TakeInboxItem(1,1);hooks.TakeInboxItem(1,2)
local bulk=Count('mail collected')
mailItems={[2]={itemID=88,qty=3}};counts[88]=2;T.CaptureMail();assert(Count('mail collected')==bulk+1)
mailItems={};counts[88]=5;T.CaptureMail();assert(Count('mail collected')==bulk+2)
T.CaptureMail();assert(Count('mail collected')==bulk+2)
-- Outgoing mail is committed only on server success.
function SendMail() end;function SetSendMailMoney() end;function SetSendMailCOD() end
function GetSendMailItem(slot) if slot==1 then return 'Item',88,1,1 end end
function GetSendMailItemLink(slot) if slot==1 then return 'item:88' end end
function GetSendMailPrice() return 30 end
T.InstallHooks();hooks.SetSendMailMoney(50);hooks.SendMail('Other','Supplies')
local sent=Count('mail sent');T.eventFrame.scripts.OnEvent(nil,'MAIL_FAILED');T.eventFrame.scripts.OnEvent(nil,'MAIL_SEND_SUCCESS')
assert(Count('mail sent')==sent)
hooks.SendMail('Other','Supplies');T.eventFrame.scripts.OnEvent(nil,'MAIL_SEND_SUCCESS')
assert(Count('mail sent')==sent+1);T.eventFrame.scripts.OnEvent(nil,'MAIL_SEND_SUCCESS');assert(Count('mail sent')==sent+1)
-- Modern character bank tabs are scanned only when their contents are available.
Enum={BankType={Character=0}}
C_Bank={CanViewBank=function() return true end,FetchPurchasedBankTabIDs=function() return {6} end}
C_Container={GetContainerNumSlots=function(bag) return bag==6 and 2 or 0 end,
 GetContainerItemInfo=function(bag,slot) if bag==6 and slot==1 then return {itemID=777,stackCount=3,hyperlink='item:777'} end end}
T.bankOpen=true;T.CaptureBank();assert(I.Holdings(777)[1].qty==3)
C_Bank.CanViewBank=function() return false end
T.CaptureBank();assert(I.Holdings(777)[1].qty==3,'Unavailable bank contents must not overwrite known counts with zero')
-- Display-only setting leaves inventory tracking untouched.
GameTooltip=widget();GameTooltip.lines={}
function GameTooltip:GetItem() return 'Ore','item:10' end
function GameTooltip:AddLine(line) self.lines[#self.lines+1]=line end
function GameTooltip:AddDoubleLine(left,right) self.lines[#self.lines+1]=tostring(left)..'  '..tostring(right) end
T.InstallTooltips();GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
assert(#GameTooltip.lines>0)
local compactLines = table.concat(GameTooltip.lines, ' ')
assert(compactLines:find('Inventory:'), 'Compact tooltip must show Inventory header')
assert(compactLines:find('Total'), 'Compact tooltip must show total item count')
assert(compactLines:find('Hold Shift'), 'Compact tooltip must include shift hint when extra details exist')

-- Shift modifier displays full breakdown
shiftActive = true
function IsShiftKeyDown() return shiftActive end
GameTooltip.lines = {}
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
local shiftLines = table.concat(GameTooltip.lines, ' ')
assert(shiftLines:find('Inventory Details:'), 'Shift tooltip must show Inventory Details')
assert(shiftLines:find('Cost Basis'), 'Shift tooltip must display FIFO cost basis')
shiftActive = false

-- Pending craft demand is displayed in tooltip
local L = MarketSync.CraftLedger
local plan = MarketSync.BuildCraftPurchasePlan({ quantity = 2, selectedBuys = {}, choices = {} })
local job = L.Save({ name = 'Bronze Widget', outputItemID = 999, mats = {{ itemID = 10, qty = 4 }} }, { quantity = 2 })
GameTooltip.lines = {}
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
local craftLines = table.concat(GameTooltip.lines, ' ')
assert(craftLines:find('Pending Crafts:'), 'Tooltip must show pending craft demand')

-- Tooltip craft demand can be disabled via setting
MarketSyncDB.EnableTooltipCraftDemand = false
GameTooltip.lines = {}
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
local disabledDemandLines = table.concat(GameTooltip.lines, ' ')
assert(not disabledDemandLines:find('Pending Crafts:'), 'Disabling EnableTooltipCraftDemand must hide pending craft demand')
MarketSyncDB.EnableTooltipCraftDemand = true

-- Tooltip modifier key customization (e.g. CTRL)
MarketSyncDB.TooltipModifier = "CTRL"
GameTooltip.lines = {}
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
local ctrlHintLines = table.concat(GameTooltip.lines, ' ')
assert(ctrlHintLines:find('Hold Ctrl'), 'Tooltip hint must reflect custom CTRL modifier key')

ctrlActive = true
function IsControlKeyDown() return ctrlActive end
GameTooltip.lines = {}
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
local ctrlDetailLines = table.concat(GameTooltip.lines, ' ')
assert(ctrlDetailLines:find('Inventory Details:'), 'Custom CTRL modifier must expand tooltip details')
ctrlActive = false
MarketSyncDB.TooltipModifier = "SHIFT"

MarketSyncDB.ShowItemsOnOtherCharacters=false;GameTooltip.lines={}
GameTooltip.scripts.OnTooltipCleared(GameTooltip);GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
assert(#GameTooltip.lines==0 and #I.Holdings(10)>0)
MarketSyncDB.ShowItemsOnOtherCharacters=true

-- MODIFIER_STATE_CHANGED safely triggers active tooltip refresh
T.eventFrame.scripts.OnEvent(nil, 'MODIFIER_STATE_CHANGED', 'LSHIFT')

-- Confirmation budgets cannot be reused for a second storage change.
local receipt=I.Record('trade',{incoming={{itemID=500,qty=1}}})
local first=I.Record('inventory observation',{state='unresolved',metadata={storage='bags',delta={['500:0']=1}}})
local second=I.Record('inventory observation',{state='unresolved',metadata={storage='bags',delta={['500:0']=1}}})
I.Reconcile(first);I.Reconcile(second)
assert(first.state=='reconciled' and second.state=='unresolved')

-- Auto-tagging incoming materials against active craft demand
local tagBuy = I.Record('auction purchase', { incoming = {{ itemID = 10, qty = 2 }}, cashOut = 200, actualCost = 200 })
assert(tagBuy.metadata and tagBuy.metadata.taggedCraftName == 'Bronze Widget', 'Incoming material automatically tagged with demanding craft')

-- Automatic zero-cost guild craft round-trip linking (materials in -> craft -> output returned to same player within 30m)
local guildIn = I.Record('trade', { incoming = {{ itemID = 601, qty = 2 }}, counterparty = 'Guildie-PvP2', cashOut = 0 })
local guildCraft = I.Record('crafted output', { incoming = {{ itemID = 602, qty = 1 }}, outgoing = {{ itemID = 601, qty = 2 }} })
local guildOut = I.Record('trade', { outgoing = {{ itemID = 602, qty = 1 }}, counterparty = 'Guildie-PvP2', cashIn = 50, cashOut = 0 })
assert(guildIn.classification == 'guild craft' and guildOut.classification == 'guild craft', 'Zero-cost guild craft round-trip automatically linked')
assert(guildOut.metadata.guildCraftSummary and guildOut.metadata.guildCraftSummary.tip == 50 and guildOut.metadata.guildCraftSummary.netCost == 0)

-- Crafting value gained vs. raw material AH sell value
MarketSync.GetAuctionPrice = function(id) return id == 601 and 100 or (id == 602 and 400) or 100 end
local gain = I.EvaluateValueGained(guildCraft)
assert(gain and gain.matMarketValue == 200 and gain.outMarketValue == 400 and gain.valueGainedVsMats == (380 - 190), 'Evaluates value gained over raw material AH value')

-- Logical 30-day ledger compaction trims settled old transactions into +/- primary rollups while preserving active lots
local oldSettled = I.Record('vendor sale', { outgoing = {{ itemID = 700, qty = 3 }}, cashIn = 900 })
oldSettled.at = now - (40 * 86400)
local trimmedCount = I.TrimLedger(30)
assert(trimmedCount >= 1 and I.Get(oldSettled.id) == nil, 'Old settled record compacted after 30 days')
local rollup = I.GetRollupSummary()
assert(rollup.cashIn >= 900 and rollup.items[700] and rollup.items[700].outQty == 3, 'Compacted rollup retains primary +/- item and gold values')

-- Resolving unassigned / unattributed records and bulk acknowledging bag observations
local unattr = I.Record('unattributed inventory', { incoming = {{ itemID = 801, qty = 2 }}, state = 'unresolved' })
assert(unattr.state == 'unresolved' and I.Lot(unattr.lots[1]).unitCost == nil)
assert(I.ResolveRecord(unattr.id, 'set_cost', 0))
assert(unattr.state == 'confirmed' and unattr.classification == 'self-found / free' and I.Lot(unattr.lots[1]).unitCost == 0)

local obs1 = I.Record('inventory observation', { state = 'unresolved', metadata = { delta = { ['802:0'] = -1 }, unresolved = { ['802:0'] = -1 } } })
local obs2 = I.Record('inventory observation', { state = 'unresolved', metadata = { delta = { ['803:0'] = -1 }, unresolved = { ['803:0'] = -1 } } })
local resolvedCount = I.ResolveAllObservations()
assert(resolvedCount >= 2 and obs1.state == 'reconciled' and obs2.state == 'reconciled', 'Bulk acknowledge resolves unresolved bag observations')

-- ItemRack gear swap & internal bag movement immunity:
-- Items moved between bags and equipment slots on the same character produce zero transactions.
local openGear = I.Record('opening inventory', { incoming = {{ itemID = 901, qty = 1 }, { itemID = 902, qty = 1 }} })
local initialBags = { ['901:0'] = { itemID = 901, qty = 1 }, ['902:0'] = { itemID = 902, qty = 1 } }
local initialEquipped = { ['903:0'] = { itemID = 903, qty = 1 }, ['904:0'] = { itemID = 904, qty = 1 } }
I.Snapshot('bags', initialBags, { equipped = initialEquipped })
I.Snapshot('equipped', initialEquipped)
local txCountBeforeSwap = #I.List()

-- ItemRack swaps 901 from bag to equipped, and 903 from equipped to bag
local swappedBags = { ['903:0'] = { itemID = 903, qty = 1 }, ['902:0'] = { itemID = 902, qty = 1 } }
local swappedEquipped = { ['901:0'] = { itemID = 901, qty = 1 }, ['904:0'] = { itemID = 904, qty = 1 } }
I.Snapshot('bags', swappedBags, { equipped = swappedEquipped })
I.Snapshot('equipped', swappedEquipped)
assert(#I.List() == txCountBeforeSwap, 'Gear swap between bags and equipped creates 0 ledger transactions')

-- Swap back
I.Snapshot('bags', initialBags, { equipped = initialEquipped })
I.Snapshot('equipped', initialEquipped)
assert(#I.List() == txCountBeforeSwap, 'Swapping gear back creates 0 ledger transactions')

-- Moving items between bag slots (same bag totals) produces zero transactions
I.Snapshot('bags', initialBags, { equipped = initialEquipped })
assert(#I.List() == txCountBeforeSwap, 'Internal bag rearrangement creates 0 ledger transactions')

-- External item gain (looting 3 of item 905) DOES record an observation
local lootBags = { ['901:0'] = { itemID = 901, qty = 1 }, ['902:0'] = { itemID = 902, qty = 1 }, ['905:0'] = { itemID = 905, qty = 3 } }
I.Snapshot('bags', lootBags, { equipped = initialEquipped })
assert(#I.List() == txCountBeforeSwap + 1, 'External item gain creates an observation')
local lootObs = I.List()[1]
assert(lootObs.kind == 'inventory observation' and lootObs.metadata.delta['905:0'] == 3, 'Observation delta contains only real external gains')
assert(lootObs.metadata.delta['901:0'] == nil and lootObs.metadata.delta['903:0'] == nil, 'Observation excludes equipped gear')

-- Holdings still report accurate counts across both bags and equipped
local h901 = I.Holdings(901)
local foundBags, foundEquipped = false, false
for _, h in ipairs(h901) do
    if h.owner == I.Owner() and h.storage == 'bags' and h.qty == 1 then foundBags = true end
    if h.owner == I.Owner() and h.storage == 'equipped' and h.qty == 1 then foundEquipped = true end
end
assert(foundBags and not foundEquipped, 'Holdings accurately report 901 in bags')

-- SeedObservedStock preserves lots and costs for equipped gear without creating unattributed records
local crafted = I.Record('crafted output', { incoming = {{ itemID = 910, qty = 1 }}, actualCost = 500 })
assert(crafted and #crafted.lots == 1)
local lotID = crafted.lots[1]
assert(I.Lot(lotID).qty == 1 and I.Lot(lotID).unitCost == 500)
-- Equip the crafted item
local eqCrafted = { ['910:0'] = { itemID = 910, qty = 1 } }
I.Snapshot('bags', initialBags, { equipped = eqCrafted })
I.Snapshot('equipped', eqCrafted)
local txCountBeforeSeed = #I.List()
I.SeedObservedStock()
if #I.List() > txCountBeforeSeed then
    local newTx = I.List()[1]
    local inInfo = newTx.incoming and newTx.incoming[1] and ('itemID=' .. tostring(newTx.incoming[1].itemID) .. ' qty=' .. tostring(newTx.incoming[1].qty)) or 'no incoming'
    error('SeedObservedStock created unexpected tx kind=' .. tostring(newTx.kind) .. ' id=' .. tostring(newTx.id) .. ' ' .. inInfo)
end
assert(I.Lot(lotID).qty == 1, 'Equipped item lot is NOT burned during SeedObservedStock')
assert(I.Lot(lotID).unitCost == 500, 'Equipped item cost is preserved during SeedObservedStock')
assert(#I.List() == txCountBeforeSeed, 'Equipped gear does not create unattributed inventory')

-- Trailing debounce verification:
-- Rapid burst of BAG_UPDATE_DELAYED and PLAYER_EQUIPMENT_CHANGED fires debounce timer
local timerQueue = {}
local simClock = 100.0
GetTime = function() return simClock end
C_Timer = {
    After = function(delay, callback)
        table.insert(timerQueue, { at = simClock + delay, fn = callback })
    end
}
local snapshotsExecuted = 0
local origCaptureBags = T.CaptureBags
T.CaptureBags = function() snapshotsExecuted = snapshotsExecuted + 1; origCaptureBags() end

-- Simulate 15 rapid events in a burst (like ItemRack swapping a 15-piece set)
for i = 1, 15 do
    simClock = simClock + 0.02
    T.eventFrame.scripts.OnEvent(nil, i % 2 == 0 and 'BAG_UPDATE_DELAYED' or 'PLAYER_EQUIPMENT_CHANGED')
end

-- Assert that while events were firing in burst, snapshot has NOT executed yet
assert(snapshotsExecuted == 0, 'Debounce prevents snapshot execution in the middle of a gear swap burst')

-- Advance simulated time by running timers in queue until complete
while #timerQueue > 0 do
    table.sort(timerQueue, function(a, b) return a.at < b.at end)
    local nextTimer = table.remove(timerQueue, 1)
    simClock = nextTimer.at
    nextTimer.fn()
end

-- Assert that exactly ONE snapshot executed after the entire burst settled
assert(snapshotsExecuted == 1, 'Only one single snapshot runs after burst settles')
T.CaptureBags = origCaptureBags
C_Timer = nil


`);
run(fs.readFileSync(path.join(__dirname, '../MarketSync/Ledger/ItemLedger.lua'), 'utf8'));
run(`assert(MarketSync.ItemLedger.Store().transactions[1], 'Reload preserves saved transactions')`);
console.log('PASS item ledger custody, costs, reservations, transfers, service profits, mail/trade confirmation and ownership isolation');
