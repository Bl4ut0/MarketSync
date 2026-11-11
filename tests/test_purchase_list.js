const fs=require('fs');const path=require('path');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
function run(code){if(lauxlib.luaL_dostring(state,to_luastring(code))!==lua.LUA_OK)throw Error(lua.lua_tojsstring(state,-1));}
run(`
now=100;function GetTime() return now end;function time() return 1000 end
function UnitName() return 'Alice' end;function GetRealmName() return 'Realm' end
function GetMoney() return 100000 end
UIParent={};StaticPopupDialogs={};function print() end
function widget()
 local w={shown=true,scripts={},width=600}
 setmetatable(w,{__index=function(_,k) if k:match('^[A-Z]') then return function() end end end})
 function w:SetScript(k,v) self.scripts[k]=v end
 function w:CreateFontString() return widget() end
 function w:SetText(t) self.text=t end
 function w:SetSize(x,y) self.width=x end
 function w:Show() self.shown=true end;function w:Hide() self.shown=false end
 function w:IsShown() return self.shown end
 return w
end
function CreateFrame(_,name) local w=widget();if name then _G[name]=w end;return w end
MarketSyncDB={Favorites={}}
MarketSync={GetRealmDB=function() return MarketSyncDB end,GetItemInfo=function(id) return 'Item '..id end}
function MarketSync.BuildCraftPurchasePlan(req)
 return {buys={[10]={qty=req.quantity,itemID=10,unitPrice=10}},provided={},recipes={{outputQty=req.quantity}}}
end
MarketSync.Scanner={IsLegacyAH=true,Active=false,LiveSearchAt=100,LiveSearchProgress={state='complete'},LiveSearchResults={},callbacks={}}
local S=MarketSync.Scanner
function S.RegisterCallback(fn) S.callbacks[#S.callbacks+1]=fn end
function S.PrepareLivePurchase(row) S.Active=true;S.checking=row;return true end
buys=0
function S.BuyPreparedLivePurchase(row)
 buys=buys+1;MarketSync.CraftLedger.ExpectPurchase(row.itemID,row.stackSize,row.buyout);S.PurchaseReady=nil;return true
end
function Ready()
 S.Active=false;S.PurchaseReady={row=S.checking};for _,fn in ipairs(S.callbacks) do fn() end
end
function Quote(stack,price,count,page)
 return {itemID=10,itemSuffix=0,name='Ore',stackSize=stack,buyout=price,auctions=count or 1,query='Ore',queryExact=true,page=page or 0}
end
`);
for(const name of ['Favorites.lua','Ledger/CraftLedger.lua','Ledger/PurchaseList.lua','Ledger/UI_PurchaseList.lua']){
const source=fs.readFileSync(path.join(__dirname,'../MarketSync',name),'utf8');require('luaparse').parse(source,{luaVersion:'5.1'});run(source);
}
run(`
local P=MarketSync.PurchaseList;local L=MarketSync.CraftLedger;local S=MarketSync.Scanner
local plan=P.Build({[10]={qty=1}},{Quote(1,11),Quote(20,200)})
assert(plan.entries[1].stackSize==20 and plan.total==200 and plan.extra==19,'Never substitute a higher unit price to avoid whole-stack extras')
plan=P.Build({[10]={qty=3}},{Quote(2,20),Quote(1,15)})
assert(#plan.entries==2 and plan.entries[1].buyout==20 and plan.entries[2].higherTier and plan.total==35)
plan=P.Build({[10]={qty=5}},{Quote(2,20)})
assert(not plan.complete and plan.missing[10]==3,'Shortfalls block whole-list approval')
local variant=Quote(1,1);variant.itemSuffix=123
assert(P.Build({[10]={qty=1}},{variant,Quote(1,10)}).total==10,'Variants cannot replace raw materials')
local older=assert(L.Save({name='Older',outputItemID=100,mats={}},{quantity=2}))
local selected=assert(L.Save({name='Selected',outputItemID=101,mats={}},{quantity=1}))
MarketSync.AHSidecar={GetSelectedShoppingListName=function() return selected.shoppingName end}
S.LiveSearchResults={Quote(2,20)}
assert(P.SelectedJob()==selected and P.Open(selected))
assert(P.state=='review' and buys==0,'Opening is read-only')
assert(P.CheckNext() and buys==0);Ready();assert(P.state=='ready' and buys==0)
assert(P.BuyNext() and buys==1 and P.state=='awaiting')
assert(not P.BuyNext() and buys==1,'Double clicks cannot submit twice')
assert(P.ReceiptTarget(10,2,20)==selected.id)
local recorded
MarketSync.ItemLedger={Record=function(_,entry) recorded=entry end}
ERR_AUCTION_BID_PLACED='Confirmed'
-- Deliberately dispatch queue confirmation before the ledger's event.
P.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Confirmed')
L.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Confirmed')
assert(selected.status=='Purchased' and older.status=='Shopping','Receipt belongs to selected craft, not FIFO')
assert(selected.purchased[10].paid==10 and selected.purchased[10].qty==1)
assert(recorded.incoming[1].qty==2 and recorded.actualCost==20,'Full stack and its actual per-unit cost stay in inventory ledger')
P.eventFrame.scripts.OnUpdate()
assert(P.state=='complete' and P.index==2)
P.eventFrame.scripts.OnEvent(nil,'CHAT_MSG_SYSTEM','Confirmed');P.eventFrame.scripts.OnUpdate();assert(P.index==2)
MarketSync.ItemLedger=nil
S.LiveSearchAt=now;assert(P.Open(older));assert(P.CheckNext());S.Active=false;S.PurchaseReady=nil;P.OnScannerChanged()
assert(P.state=='paused' and buys==1,'Missing exact stack never triggers a replacement purchase')
assert(P.Open(older));assert(P.CheckNext());Ready()
L.Save(older.recipe,{quantity=3},older.id)
assert(not P.BuyNext() and P.state=='paused' and buys==1,'Changed craft quantities require a new review')
now=300;assert(not P.Preview(older),'Expired quote cannot authorize a plan')
now=100;S.LiveSearchAt=100;S.LiveSearchResults={Quote(2,20,2)};assert(P.Open(older));assert(P.CheckNext());Ready();assert(P.BuyNext())
now=111;P.eventFrame.scripts.OnUpdate();assert(P.state=='paused','Missing server confirmation stops the queue')
P.Show();assert(MarketSyncPurchaseList and MarketSyncPurchaseList:IsShown(),'Confirmation window opens')
`);
console.log('PASS cheapest-unit plans, extras, tiers, shortfalls, exact-stack checks, target receipts, stale prices, changed quantities and confirmation UI');
