const fs = require('fs');
const path = require('path');
const deps = path.resolve(__dirname, '../../ItemRack-Forever/node_modules');
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring } = require(path.join(deps, 'fengari'));
const root = path.resolve(__dirname, '../MarketSyncForeverScanner');
const modules = ['Store.lua', 'Scanner.lua', 'Window.lua', 'AuctionHouse.lua', 'Core.lua'];
const code = modules.map(name => {
  const source = fs.readFileSync(path.join(root, name), 'utf8');
  luaparse.parse(source, { luaVersion: '5.1' });
  return `\n-- ${name}\ndo\n${source}\nend\n`;
}).join('\n');

const fixture = `
now = 100; unix = 1800000000
function GetTime() return now end
function time() return unix end
function GetBuildInfo() return "1.60.1", "69893", "Sep 16 2026", 987654 end
function GetNormalizedRealmName() return "TestRealm" end
function GetRealmName() return "Test Realm" end
function GetCurrentRegion() return 1 end
function UnitFactionGroup() return "Alliance" end
function IsLoggedIn() return true end
function print() end
WOW_PROJECT_ID = 91
Enum = {PlayerInteractionType={Auctioneer=21}, ItemClass={Weapon=2,Armor=4,Projectile=6}}
UIParent = {}; UISpecialFrames = {}; SlashCmdList = {}
AuctionHouseFrame = {}
local function widget()
 local f={shown=true,text="",scripts={},events={}}
 function f:SetScript(name, cb) self.scripts[name]=cb end
 function f:RegisterEvent(name) self.events[name]=true end
 function f:CreateFontString() return widget() end
 function f:SetText(text) self.text=text end
 function f:GetText() return self.text end
 function f:IsShown() return self.shown end
 function f:IsVisible()
  local parent=rawget(self,"parent")
  return self.shown and (not parent or not parent.IsVisible or parent:IsVisible())
 end
 function f:GetParent() return self.parent end
 function f:SetPoint(...) self.point={...} end
 function f:SetShown(value) self.shown=value; if value and self.scripts.OnShow then self.scripts.OnShow(self) end end
 function f:Show() self:SetShown(true) end
 function f:Hide() self:SetShown(false) end
 function f:SetEnabled(value) self.enabled=value end
 setmetatable(f,{__index=function(self,name) return function() end end})
 return f
end
frameRequests={}
function CreateFrame(kind,name,parent,template)
 local f=widget();f.TitleText=widget();f.parent=parent;f.template=template
 if name then _G[name]=f end
 table.insert(frameRequests,{kind=kind,name=name,parent=parent,template=template})
 return f
end
function nativeAuctionFrame()
 local f=widget()
 f.BuyTab=widget();f.SellTab=widget();f.AuctionsTab=widget()
 f.Tabs={f.BuyTab,f.SellTab,f.AuctionsTab}
 f.tabsForDisplayMode={Buy=1,Sell=2,Auctions=3}
 f.displayMode="Auctions";f.selectedTab=3
 function f:SetDisplayMode(mode) self.displayMode=mode end
 return f
end
function PanelTemplates_DeselectTab(tab)
 tab.selected=false
end
function PanelTemplates_TabResize(tab,padding,absoluteSize,minWidth)
 tab.resizedText=tab:GetText();tab.tabPadding=padding;tab.minTabWidth=minWidth
end
function hooksecurefunc(tbl,name,callback)
 local original=tbl[name]
 tbl[name]=function(...) local result=original(...);callback(...);return result end
end
timers={}
C_Timer={After=function(delay,callback) table.insert(timers,{at=now+delay,callback=callback}) end}
function advance(seconds)
 local target=now+seconds
 local iterations=0
 while true do
  local best,index
  for i,timer in ipairs(timers) do if timer.at<=target and (not best or timer.at<best.at) then best,index=timer,i end end
  if not best then break end
  table.remove(timers,index);now=best.at;iterations=iterations+1
  assert(iterations<10000,"timer loop")
  best.callback()
 end
 now=target
end
key={itemID=25,itemLevel=10,itemSuffix=7,battlePetSpeciesID=0}
commodityKey={itemID=2447,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
itemRows={};commodityRows={};browseRows={}
fullItem=true;fullCommodity=true;ready=true;requests={}
C_Item={GetItemInfoInstant=function() return nil,nil,nil,nil,nil,2 end}
C_AuctionHouse={
 GetItemKeyInfo=function(k) return {itemName="Item "..k.itemID,iconFileID=1,quality=2,isCommodity=k.itemID==2447} end,
 GetBrowseResults=function() return browseRows end,
 GetNumItemSearchResults=function() return #itemRows end,
 GetNumCommoditySearchResults=function() return #commodityRows end,
 GetItemSearchResultsQuantity=function() error("quantity is not a row count") end,
 GetCommoditySearchResultsQuantity=function() error("quantity is not a row count") end,
 GetItemSearchResultInfo=function(k,i) return itemRows[i] end,
 GetCommoditySearchResultInfo=function(id,i) return commodityRows[i] end,
 HasFullItemSearchResults=function() return fullItem end,
 HasFullCommoditySearchResults=function() return fullCommodity end,
 IsThrottledMessageSystemReady=function() return ready end,
 SendSearchQuery=function(k,sorts,own) table.insert(requests,{kind="search",key=k,time=now});assert(type(own)=="boolean") end,
 RequestMoreItemSearchResults=function(k) table.insert(requests,{kind="more-item",key=k,time=now});return false end,
 RequestMoreCommoditySearchResults=function(id) table.insert(requests,{kind="more-commodity",itemID=id,time=now});return false end,
 SendBrowseQuery=function() end,
}
`;
let passed = 0;
function test(name, assertions) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const source = fixture + code + `\nlocal S=MarketSyncForeverScanner\nS.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_LOGIN")\nS.AuctioneerOpen=true\n` + assertions;
  let status = lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring(name));
  if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) throw new Error(`${name}: ${lua.lua_tojsstring(L, -1)}`);
  lua.lua_close(L);
  passed++;
  console.log(`PASS ${name}`);
}

test('native suffix, level and pet identity stay separate', `
assert(S.KeyID(key)=="25:10:7:0")
local other=S.CopyKey(key);other.itemSuffix=8
assert(S.KeyID(other)~=S.KeyID(key))
other=S.CopyKey(key);other.itemLevel=11;assert(S.KeyID(other)~=S.KeyID(key))
other=S.CopyKey(key);other.battlePetSpeciesID=9;assert(S.KeyID(other)~=S.KeyID(key))
assert(WOW_PROJECT_ID==91 and not Auctionator)
`);
test('browse observations never claim complete item or market coverage', `
browseRows={{itemKey=key,minPrice=60,totalQuantity=27}}
S.CaptureBrowse()
local r=S.Store.records[S.KeyID(key)]
assert(r.latest.browseMinPrice==60 and r.latest.available==27 and not r.latest.complete)
assert(r.lastComplete==nil and #r.history==0 and #requests==0)
`);
test('item buyouts divide by stack quantity and skip other suffixes and bids', `
local other=S.CopyKey(key);other.itemSuffix=8
itemRows={{itemKey=key,auctionID=1,quantity=4,buyoutAmount=100},
 {itemKey=key,auctionID=2,quantity=2,buyoutAmount=80},
 {itemKey=key,auctionID=3,quantity=1,minBid=1},
 {itemKey=other,auctionID=4,quantity=20,buyoutAmount=1}}
S.CaptureSearch(key,false)
local r=S.Store.records[S.KeyID(key)]
assert(r.latest.available==7 and r.latest.pricedQuantity==6 and r.latest.minUnitPrice==25)
assert(#r.latest.priceLevels==2 and r.latest.priceLevels[1].quantity==4 and #r.history==1)
`);
test('commodity row count and volume remain distinct', `
commodityRows={{auctionID=1,quantity=100,unitPrice=60},{auctionID=2,quantity=150,unitPrice=70}}
S.CaptureSearch(commodityKey,true)
local p=S.Provider.GetSnapshot(commodityKey)
assert(p.available==250 and p.rows==2 and p.minUnitPrice==60 and p.pricedQuantity==250)
`);
test('partial results retain the last complete observation', `
commodityRows={{quantity=10,unitPrice=60}}
S.CaptureSearch(commodityKey,true)
fullCommodity=false;commodityRows={{quantity=2,unitPrice=80}}
S.CaptureSearch(commodityKey,true)
local r=S.Store.records[S.KeyID(commodityKey)]
assert(not r.latest.complete and r.lastComplete.minUnitPrice==60 and #r.history==1)
`);
test('empty complete results represent unavailable stock without a zero buyout', `
S.CaptureSearch(key,false)
local p=S.Provider.GetSnapshot(key)
assert(p.complete and p.available==0 and p.minUnitPrice==nil)
`);
test('provider snapshots cannot mutate stored prices', `
commodityRows={{quantity=10,unitPrice=60}};S.CaptureSearch(commodityKey,true)
local p=S.Provider.GetSnapshot(commodityKey);p.minUnitPrice=1;p.priceLevels[1].quantity=999
local q=S.Provider.GetSnapshot(commodityKey);assert(q.minUnitPrice==60 and q.priceLevels[1].quantity==10)
`);
test('native throttle gates watched requests and bounds throttle waits', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));ready=false
assert(S.StartWatched());advance(5);assert(#requests==0 and S.Active)
advance(61);assert(not S.Active and #requests==0 and S.Store.completedWatchScans==0)
`);
test('pagination waits for readiness and marks complete only after final results', `
S.RememberKey(commodityKey);S.ToggleWatch(S.KeyID(commodityKey));assert(S.StartWatched());advance(.2)
assert(#requests==1 and S.Pending.commodity)
fullCommodity=false;commodityRows={{quantity=5,unitPrice=60}}
S.CaptureSearch(commodityKey,true);ready=false;advance(2)
assert(#requests==1 and S.Active and S.Provider.GetSnapshot(commodityKey)==nil)
ready=true;advance(1);assert(#requests==2 and requests[2].kind=="more-commodity")
fullCommodity=true;commodityRows={{quantity=10,unitPrice=60},{quantity=5,unitPrice=70}}
S.CaptureSearch(commodityKey,true);advance(2)
assert(not S.Active and S.Store.completedWatchScans==1 and S.Provider.GetSnapshot(commodityKey).available==15)
`);
test('requests are spaced across repeated watch scans', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));S.StartWatched();advance(.2)
S.CaptureSearch(key,false);advance(2);assert(not S.Active)
S.StartWatched();advance(.2);assert(#requests==2 and requests[2].time-requests[1].time>=1.1)
`);
test('paging can finish immediately without another native event', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));S.StartWatched();advance(.2)
fullItem=false;itemRows={{itemKey=key,quantity=1,buyoutAmount=60}}
S.CaptureSearch(key,false)
C_AuctionHouse.RequestMoreItemSearchResults=function() fullItem=true;return true end
advance(3)
assert(not S.Active and S.Store.completedWatchScans==1 and S.Provider.GetSnapshot(key).minUnitPrice==60)
`);
test('missing row data retries the cache without extra search requests', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));S.StartWatched();advance(.2)
C_AuctionHouse.GetNumItemSearchResults=function() return 1 end
S.CaptureSearch(key,false);advance(2)
assert(S.Active and #requests==1 and S.Provider.GetSnapshot(key)==nil)
itemRows={{itemKey=key,quantity=1,buyoutAmount=60}};advance(2)
assert(not S.Active and #requests==1 and S.Provider.GetSnapshot(key).minUnitPrice==60)
`);
test('closing the auctioneer invalidates delayed callbacks without freshness', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));S.StartWatched()
S.EventFrame.scripts.OnEvent(S.EventFrame,"AUCTION_HOUSE_CLOSED")
advance(40);assert(#requests==0 and not S.Active and S.Store.completedWatchScans==0)
S.CaptureSearch(key,false);assert(S.Store.records[S.KeyID(key)].latest==nil)
`);
test('unanswered requests time out without clearing the previous snapshot', `
commodityRows={{quantity=10,unitPrice=60}};S.CaptureSearch(commodityKey,true)
S.ToggleWatch(S.KeyID(commodityKey));S.StartWatched();advance(30)
assert(not S.Active and S.Store.completedWatchScans==0 and S.Provider.GetSnapshot(commodityKey).minUnitPrice==60)
`);
test('native user searches cancel the queue and own requests do not', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));S.StartWatched();advance(.2);assert(S.Active)
C_AuctionHouse.SendBrowseQuery({});assert(not S.Active)
advance(40);assert(#requests==1 and S.Store.completedWatchScans==0)
`);
test('native request rejection clears all request guards', `
S.RememberKey(key);S.ToggleWatch(S.KeyID(key))
C_AuctionHouse.SendSearchQuery=function() error("restricted") end
S.StartWatched();advance(.2)
assert(not S.Active and not S.OwnRequest and S.Pending==nil and S.Store.completedWatchScans==0)
`);
test('main and neutral stores and watched lists remain separate', `
S.CaptureSearch(key,false);S.ToggleWatch(S.KeyID(key));local main=S.Store
assert(not S.SetMarket("neutral"));assert(S.Store==main)
S.AuctioneerOpen=false;assert(S.SetMarket("neutral"));assert(S.Store~=main and next(S.Store.records)==nil)
S.AuctioneerOpen=true;S.CaptureSearch(commodityKey,true);S.AuctioneerOpen=false
assert(S.SetMarket("main"));assert(S.Store==main and S.Store.watched[S.KeyID(key)])
`);
test('history and watch lists are bounded', `
for i=1,100 do unix=unix+1800;S.CaptureSearch(key,false) end
assert(#S.Store.records[S.KeyID(key)].history==96)
for i=1,50 do local k={itemID=1000+i};S.RememberKey(k);assert(S.ToggleWatch(S.KeyID(k))) end
S.RememberKey(commodityKey);assert(not S.ToggleWatch(S.KeyID(commodityKey)))
`);
test('unsupported clients and missing namespaces hold capture', `
GetBuildInfo=function() return "12.1.0","69814","date",120100 end
local ok=S.CheckClient();assert(not ok)
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_LOGIN")
assert(not S.IsAuctioneerAvailable() and not S.StartWatched())
GetBuildInfo=function() return "1.60.1","69893","date",987654 end
C_AuctionHouse=nil;ok=S.CheckClient();assert(not ok)
`);
test('portable window opens offline and diagnostics make no market requests', `
S.AuctioneerOpen=false;S.ToggleWindow();S.Notify();S.ToggleWindow();S.ToggleWindow()
local r=S.Report();assert(not r.fullMarketScanImplemented and not r.guildSyncEnabled and r.interface==987654)
assert(#requests==0 and not S.StartWatched())
`);
test('late native UI load attaches one launcher without changing native tab selection', `
AuctionHouseFrame=nil;assert(not S.AttachAuctionHouseEntry() and not S.AuctionHouseEntry)
AuctionHouseFrame=nativeAuctionFrame()
local tabs=AuctionHouseFrame.Tabs;local modes=AuctionHouseFrame.tabsForDisplayMode
S.EventFrame.scripts.OnEvent(S.EventFrame,"ADDON_LOADED","OtherAddon")
assert(not S.AuctionHouseEntry)
S.EventFrame.scripts.OnEvent(S.EventFrame,"ADDON_LOADED","Blizzard_AuctionHouseUI")
local entry=S.AuctionHouseEntry
assert(entry and entry:GetParent()==AuctionHouseFrame and entry.template=="AuctionHouseFrameTabTemplate")
assert(entry:GetText()=="MarketSync" and entry.point[2]==AuctionHouseFrame.AuctionsTab and entry.selected==false)
assert(entry.resizedText=="MarketSync" and entry.tabPadding==20 and entry.minTabWidth==70)
entry.scripts.OnClick(entry);assert(MarketSyncForeverScannerWindow:IsShown())
entry.scripts.OnClick(entry);assert(MarketSyncForeverScannerWindow:IsShown())
S.EventFrame.scripts.OnEvent(S.EventFrame,"ADDON_LOADED","Blizzard_AuctionHouseUI")
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
local count=0;for _,r in ipairs(frameRequests) do if r.name=="MarketSyncForeverAuctionHouseEntry" then count=count+1 end end
assert(count==1 and S.AuctionHouseEntry==entry and #tabs==3 and AuctionHouseFrame.Tabs==tabs)
assert(AuctionHouseFrame.tabsForDisplayMode==modes and modes.Auctions==3)
assert(AuctionHouseFrame.displayMode=="Auctions" and AuctionHouseFrame.selectedTab==3 and #requests==0)
`);
test('an already loaded auction frame gets the launcher and closure preserves the portable window', `
AuctionHouseFrame=nativeAuctionFrame();AuctionHouseFrame:Hide()
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_LOGIN")
local entry=S.AuctionHouseEntry;assert(entry and not entry:IsVisible())
AuctionHouseFrame:Show();entry.scripts.OnClick(entry)
assert(entry:IsVisible() and MarketSyncForeverScannerWindow:IsVisible())
AuctionHouseFrame:Hide();S.EventFrame.scripts.OnEvent(S.EventFrame,"AUCTION_HOUSE_CLOSED")
assert(not entry:IsVisible() and MarketSyncForeverScannerWindow:IsVisible() and not S.AuctioneerOpen)
AuctionHouseFrame:Show();S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
assert(S.AuctionHouseEntry==entry and entry:IsVisible() and #requests==0)
local report=S.Report()
assert(report.auctionHouseEntryAttached and report.auctionHouseEntryMode=="portable-launcher")
assert(not report.embeddedAuctionHousePanel and not report.alertsEnabled and not report.guildSyncEnabled)
`);
test('an unsupported client never adds an auction-house launcher', `
AuctionHouseFrame=nativeAuctionFrame()
GetBuildInfo=function() return "12.1.0","69814","date",120100 end
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_LOGIN")
S.EventFrame.scripts.OnEvent(S.EventFrame,"ADDON_LOADED","Blizzard_AuctionHouseUI")
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
assert(not S.Ready and not S.AuctionHouseEntry and not S.AttachAuctionHouseEntry() and #requests==0)
`);
console.log(`Validated ${modules.length} production Lua files as Lua 5.1; ${passed} runtime cases passed.`);
