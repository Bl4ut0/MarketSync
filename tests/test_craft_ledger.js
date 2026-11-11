const fs = require('fs');
const path = require('path');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const luaparse=require('luaparse');
const state=lauxlib.luaL_newstate(); lualib.luaL_openlibs(state);
function run(code){if(lauxlib.luaL_dostring(state,to_luastring(code))!==lua.LUA_OK)throw Error(lua.lua_tojsstring(state,-1));}
run(`
now=100; who='Alice'; function time() return now end; function GetTime() return now end
function UnitName() return who end; function GetRealmName() return 'Playset2' end
function GetBuildInfo() return '1.60.1','70205','',16001 end
function print() end; UIParent={}; StaticPopupDialogs={}; function StaticPopup_Show() end
function widget()
 local w={scripts={},width=300,shown=true}
 setmetatable(w,{__index=function(t,k) if k:match('^[A-Z]') then return function() end end end})
 function w:SetScript(k,v) self.scripts[k]=v end
 function w:SetSize(x,y) self.width=x end; function w:GetWidth() return self.width end
 function w:CreateFontString() return widget() end
 function w:CreateTexture() return widget() end
 function w:Show() self.shown=true end; function w:Hide() self.shown=false end
 function w:IsShown() return self.shown end
 function w:SetText(t) self.text=t end
 return w
end
function CreateFrame(_,name) local w=widget(); if name then _G[name]=w end; return w end
hooks={}; function hooksecurefunc(target,name,callback)
 if type(target)=='string' then hooks[target]=name else hooks[name]=callback end
end
function DoTradeSkill() end; function GetTradeSkillItemLink() return 'item:101' end
craftedInventory=0; function GetItemCount() return craftedInventory end
LOOT_ITEM_CREATED_SELF='Created: %s'; LOOT_ITEM_CREATED_SELF_MULTIPLE='Created: %sx%d'
C_AuctionHouse={StartCommoditiesPurchase=function() end,ConfirmCommoditiesPurchase=function() end,
 PlaceBid=function() end,GetAuctionInfoByID=function() return {itemKey={itemID=10},buyoutAmount=100} end,
 GetNumItemSearchResults=function() return 1 end,GetItemSearchResultInfo=function() return {auctionID=44,quantity=2} end}
MarketSyncDB={Favorites={},FavoriteQuantities={}}
MarketSync={GetRealmDB=function() return MarketSyncDB end, GetItemInfo=function(id) return 'Item '..id end}
function MarketSync.BuildCraftPurchasePlan(req)
 local buys={}; if req.selectedBuys[10]~=false then buys[10]={itemID=10,name='Ore',qty=req.quantity*2,unitPrice=50} end
 return {buys=buys,provided={},recipes={{outputQty=req.quantity}},buyCount=1}
end
function MarketSync.CalculateGroundUpCraftCost(recipe,choices,qty)
 return {reagentsTree={{itemID=10,name='Ore',qty=qty*2,canCraft=false,chooseCraft=false}}}
end
function MarketSync.CalculateRecipeProfit() return {outputPrice=1000,grossRevenue=1000,netRevenue=950} end
`);
for(const name of ['Favorites.lua','Ledger/CraftLedger.lua','Ledger/UI_CraftManager.lua']){
 const code=fs.readFileSync(path.join(__dirname,'../MarketSync',name),'utf8');luaparse.parse(code,{luaVersion:'5.1'});run(code);
}
run(`
local L=MarketSync.CraftLedger
local recipe={outputItemID=100,name='Widget',mats={{itemID=10,qty=2}}}
local a=assert(L.Save(recipe,{quantity=2})); local b=assert(L.Save(recipe,{quantity=1}))
assert(a.shoppingName~=b.shoppingName and MarketSync.Favorites.GetQuantity(a.shoppingName,10)==4)
assert(L.RecordPurchase(10,3,150,'receipt-1')); assert(not L.RecordPurchase(10,3,150,'receipt-1'))
assert(a.purchased[10].qty==3 and not b.purchased[10]); assert(L.Remaining(a)[10].qty==1)
assert(MarketSync.Favorites.GetQuantity(a.shoppingName,10)==1)
local oldList=a.shoppingName
assert(L.Save(recipe,{quantity=3},a.id)==a); assert(a.purchased[10].paid==150)
assert(not MarketSyncDB.Favorites[oldList]); assert(L.Remaining(a)[10].qty==3)
assert(not L.Complete(a.id)); assert(L.RecordPurchase(10,4,400,'receipt-2'))
assert(a.status=='Purchased' and not a.shoppingName and b.purchased[10].qty==1)
assert(L.Complete(a.id,1)); assert(a.status=='Purchased' and a.craftedQty==1)
assert(L.Complete(a.id,1)); assert(not L.Save(recipe,{quantity=1},a.id))
assert(L.Complete(a.id)); assert(a.status=='Crafted' and #L.List()==1 and #L.List(true)==1)
assert(L.RecordSale(a.id,1,1000,50,'sale-1')); assert(not L.RecordSale(a.id,1,1000,50,'sale-1'))
assert(not L.RecordSale(a.id,99,1000,50)); local t=L.Totals(a)
assert(t.gross==1000 and t.fees==50 and t.sold==1)
assert(math.abs(t.profit-(950-t.paid/a.outputQty))<0.001)
who='Bob'; assert(#L.List()==0 and #L.List(true)==0); assert(not L.Remove(a.id)); who='Alice'
local c=assert(L.Save(recipe,{quantity=1,selectedBuys={[10]=false}})); assert(c.status=='Purchased' and not c.shoppingName)
local d=assert(L.Save(recipe,{quantity=1})); local target=d.shoppingName
L.ExpectPurchase(10,2,200); now=111; ERR_AUCTION_BID_PLACED='Success'
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Success'); assert(d.status=='Shopping')
L.ExpectPurchase(10,2,200); L.eventFrame.scripts.OnEvent(nil,'UI_ERROR_MESSAGE')
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Success'); assert(d.status=='Shopping')
L.ExpectPurchase(10,2,200); L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Success')
-- FIFO: remaining demand in b receives one, then d receives one.
assert(b.status=='Purchased' and d.purchased[10].qty==1)
assert(L.Remove(d.id)); assert(not MarketSyncDB.Favorites[target])
MarketSync.OpenCraftingTree(recipe); assert(MarketSyncCraftManager.recipe==recipe)
assert(MarketSyncCraftManager.save.text=='Add to Craft List')
MarketSyncCraftManager.save.scripts.OnClick(); assert(MarketSyncCraftManager.jobID)
assert(MarketSyncCraftManager.save.text=='Update Craft')
MarketSync.OpenCraftingTree(recipe,nil,{ledgerID=a.id}); assert(MarketSyncCraftManager.history)
assert(MarketSyncCraftManager.panes[2].heading.text:find('Recorded costs'))
local craft=assert(L.Save({outputItemID=101,name='Created Widget',mats={{itemID=10,qty=2}}},{quantity=2,selectedBuys={[10]=false}}))
hooks.DoTradeSkill(1,2)
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_LOOT','Looted: item:101x2'); assert(craft.status=='Purchased')
craftedInventory=1
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_LOOT','Created: item:101x1'); assert(craft.craftedQty==1)
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_LOOT','Created: item:101x1'); assert(craft.craftedQty==1, 'Duplicate creation receipt cannot advance without new inventory')
craftedInventory=2
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_LOOT','Created: item:101x1'); assert(craft.status=='Crafted')
local pending; for _,job in ipairs(L.List()) do if job.status=='Shopping' then pending=job; break end end
hooks.StartCommoditiesPurchase(10,2)
L.eventFrame.scripts.OnEvent(nil,'COMMODITY_PRICE_UPDATED',50,100)
hooks.ConfirmCommoditiesPurchase(10,2)
L.eventFrame.scripts.OnEvent(nil,'COMMODITY_PURCHASE_SUCCEEDED')
assert(pending.status=='Purchased' and pending.purchased[10].paid==100)
L.eventFrame.scripts.OnEvent(nil,'COMMODITY_PURCHASE_SUCCEEDED'); assert(pending.purchased[10].paid==100)
local item=assert(L.Save(recipe,{quantity=1})); hooks.PlaceBid(44,100)
L.eventFrame.scripts.OnEvent(nil,'AUCTION_HOUSE_PURCHASE_COMPLETED',45); assert(item.status=='Shopping')
L.eventFrame.scripts.OnEvent(nil,'AUCTION_HOUSE_PURCHASE_COMPLETED',44); assert(item.status=='Purchased')
L.eventFrame.scripts.OnEvent(nil,'AUCTION_HOUSE_PURCHASE_COMPLETED',44); assert(item.purchased[10].paid==100)
MarketSync.ListProcessingCraftSets=function() return {{name='Legacy',itemIDs={100},recipes={[100]=recipe},quantities={[100]=1}}} end
assert(L.ImportLegacyPlans()==1); assert(L.ImportLegacyPlans()==0)
`);
run(fs.readFileSync(path.join(__dirname,'../MarketSync/Processing.lua'),'utf8'));
run(`
MarketSync.CraftLedger.Refresh=nil
MarketSync.GetAuctionPrice=function() return 100 end
MarketSync.GetAuctionAge=function() return 0 end
local recipe={outputItemID=777,name='Batch craft',outputQty=2,mats={{itemID=10,qty=4}}}
local job=assert(MarketSync.CraftLedger.Save(recipe,{quantity=3,choices={[10]=false}}))
assert(job.outputQty==6 and job.plan.buys[10].qty==12)
assert(MarketSync.CraftLedger.RecordPurchase(10,12,1200,'real-plan',job.id))
assert(job.status=='Purchased' and MarketSync.CraftLedger.Complete(job.id,6))
assert(job.status=='Crafted')
`);
console.log('PASS craft ledger lifecycle, receipts, partial purchases, allocation, history, sales, isolation, manager UI and real recipe plans');
