const fs = require('fs');
const path = require('path');
const deps = path.resolve(__dirname, '../../ItemRack-Forever/node_modules');
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring } = require(path.join(deps, 'fengari'));
const root = path.resolve(__dirname, '../MarketSyncForeverScanner');
const modules = ['Store.lua', 'Scanner.lua', 'Browser.lua', 'Window.lua', 'AuctionHouse.lua', 'Core.lua'];
const nativeFramePath = process.env.MARKETSYNC_BLIZZARD_FRAME || 'C:/Program Files (x86)/World of Warcraft/_classic_beta_/BlizzardInterfaceCode/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua';
const nativeFrame = fs.readFileSync(nativeFramePath, 'utf8');
function nativeSection(start, end) {
  const first = nativeFrame.indexOf(start), last = nativeFrame.indexOf(end, first + start.length);
  if (first < 0 || last < 0) throw new Error(`Native controller marker missing: ${start}`);
  return nativeFrame.slice(first, last);
}
const nativeController = nativeSection('AuctionHouseFrameDisplayMode = {', 'function AuctionHouseFrameMixin:IsListingAuctions()')
  + nativeSection('function AuctionHouseFrameMixin:UpdateTitle()', 'function AuctionHouseFrameMixin:GetBrowseResultsFrame()');
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
 function f:CreateTexture() return widget() end
 function f:SetText(text)
  self.text=text
  if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end
 end
 function f:GetText() return self.text end
 function f:IsShown() return self.shown end
 function f:IsVisible()
  local parent=rawget(self,"parent")
  return self.shown and (not parent or not parent.IsVisible or parent:IsVisible())
 end
 function f:GetParent() return rawget(self,"parent") end
 function f:SetID(value) self.id=value end
 function f:GetID() return self.id end
 function f:SetTitle(value) self.title=value end
 function f:SetPortraitToAsset(value) self.portrait=value end
 function f:GetItem() return self.item end
 function f:IsWoWTokenCategorySelected() return false end
 function f:SetSize(width,height) self.width,self.height=width,height end
 function f:SetWidth(width) self.width=width end
 function f:SetHeight(height) self.height=height end
 function f:GetStringHeight() local _,count=self.text:gsub("\\n","");return (count+1)*12 end
 function f:SetTexture(value) self.texture=value end
 function f:SetVerticalScroll(value) self.verticalScroll=value end
 function f:SetScrollChild(child) self.scrollChild=child end
 function f:SetPoint(...) self.point={...} end
 function f:HookScript(name,callback)
  local original=self.scripts[name]
  self.scripts[name]=function(...) if original then original(...) end;callback(...) end
 end
 function f:SetShown(value)
  local changed=self.shown~=value;self.shown=value
  local callback=self.scripts[value and "OnShow" or "OnHide"]
  if changed and callback then callback(self) end
 end
 function f:Show() self:SetShown(true) end
 function f:Hide() self:SetShown(false) end
 function f:SetEnabled(value) self.enabled=value end
 local noop={SetJustifyH=true,SetJustifyV=true,SetWordWrap=true,SetAutoFocus=true,
  SetColorTexture=true,SetHighlightTexture=true,SetAllPoints=true,ClearAllPoints=true,
  SetFrameStrata=true,SetClampedToScreen=true,SetMovable=true,EnableMouse=true,
  RegisterForDrag=true,StartMoving=true,StopMovingOrSizing=true,ClearFocus=true}
 setmetatable(f,{__index=function(self,name) if noop[name] then return function() end end end})
 return f
end
frameRequests={}
function CreateFrame(kind,name,parent,template)
 local f=widget();f.TitleText=widget();f.parent=parent;f.template=template
 if name then _G[name]=f end
 table.insert(frameRequests,{kind=kind,name=name,parent=parent,template=template})
 return f
end
function PanelTemplates_DeselectTab(tab)
 tab.selected=false
end
function PanelTemplates_SelectTab(tab) tab.selected=true end
function PanelTemplates_UpdateTabs(frame)
 for i,tab in ipairs(frame.Tabs) do tab.selected=i==frame.selectedTab end
end
function PanelTemplates_SetNumTabs(frame,count) frame.numTabs=count end
function PanelTemplates_SetTab(frame,index) frame.selectedTab=index;PanelTemplates_UpdateTabs(frame) end
function PanelTemplates_GetSelectedTab(frame) return frame.selectedTab end
function PanelTemplates_TabResize(tab,padding,absoluteSize,minWidth)
 tab.resizedText=tab:GetText();tab.tabPadding=padding;tab.minTabWidth=minWidth
end
AuctionHouseFrameMixin={}
AUCTION_HOUSE_FRAME_TITLE_BUY="Buy";AUCTION_HOUSE_FRAME_TITLE_SELL="Sell";AUCTION_HOUSE_AUCTIONS_SUB_TAB="Auctions"
hiddenPopups={}
function StaticPopup_Hide(name) table.insert(hiddenPopups,name) end
${nativeController}
function nativeAuctionFrame()
 local f=widget()
 for _,mode in pairs(AuctionHouseFrameDisplayMode) do
  for _,name in ipairs(mode) do if not f[name] then f[name]=widget();f[name].parent=f;f[name]:Hide() end end
 end
 f.BuyDialog=widget();f.BuyDialog.parent=f;f.BuyDialog:Hide()
 f.BuyTab=widget();f.SellTab=widget();f.AuctionsTab=widget()
 f.Tabs={f.BuyTab,f.SellTab,f.AuctionsTab}
 f.tabsForDisplayMode={}
 for _,mode in ipairs({AuctionHouseFrameDisplayMode.Buy,AuctionHouseFrameDisplayMode.CommoditiesBuy,
  AuctionHouseFrameDisplayMode.ItemBuy,AuctionHouseFrameDisplayMode.WoWTokenBuy}) do f.tabsForDisplayMode[mode]=1 end
 for _,mode in ipairs({AuctionHouseFrameDisplayMode.ItemSell,AuctionHouseFrameDisplayMode.CommoditiesSell,
  AuctionHouseFrameDisplayMode.WoWTokenSell}) do f.tabsForDisplayMode[mode]=2 end
 f.tabsForDisplayMode[AuctionHouseFrameDisplayMode.Auctions]=3
 f.numTabs=3
 f.GetDisplayMode=AuctionHouseFrameMixin.GetDisplayMode
 f.SetDisplayMode=AuctionHouseFrameMixin.SetDisplayMode
 f.UpdateTitle=AuctionHouseFrameMixin.UpdateTitle
 f.GetCategoriesList=AuctionHouseFrameMixin.GetCategoriesList
 f:SetDisplayMode(AuctionHouseFrameDisplayMode.Auctions)
 f:SetScript("OnShow",function(self) self:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end)
 return f
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
test('late native UI load adds one managed tab with embedded content', `
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
assert(not S.AuctionHousePanel:IsVisible())
entry.scripts.OnClick(entry)
assert(S.AuctionHousePanel:IsVisible() and S.AuctionHousePanel:GetParent()==AuctionHouseFrame)
assert(entry.selected and AuctionHouseFrame.selectedTab==4 and entry:GetID()==4)
assert(AuctionHouseFrame:GetDisplayMode()==S.AuctionHouseDisplayMode and AuctionHouseFrame.title=="MarketSync")
assert(not AuctionHouseFrame.AuctionsFrame:IsShown() and not MarketSyncForeverScannerWindow)
entry.scripts.OnClick(entry);assert(S.AuctionHousePanel:IsVisible())
AuctionHouseFrame:UpdateTitle();assert(AuctionHouseFrame.title=="MarketSync")
S.EventFrame.scripts.OnEvent(S.EventFrame,"ADDON_LOADED","Blizzard_AuctionHouseUI")
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
local count=0;for _,r in ipairs(frameRequests) do if r.name=="MarketSyncForeverAuctionHouseEntry" then count=count+1 end end
assert(count==1 and S.AuctionHouseEntry==entry and #tabs==4 and AuctionHouseFrame.Tabs==tabs)
assert(AuctionHouseFrame.tabsForDisplayMode==modes and modes[AuctionHouseFrameDisplayMode.Auctions]==3)
assert(modes[S.AuctionHouseDisplayMode]==4 and AuctionHouseFrame.numTabs==4 and #requests==0)
assert(not AuctionHouseFrameDisplayMode.MarketSyncForever)
`);
test('native frame closure cancels scans and reopening restores Buy while keeping the portable window', `
AuctionHouseFrame=nativeAuctionFrame();AuctionHouseFrame:Hide()
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_LOGIN")
local entry=S.AuctionHouseEntry;assert(entry and not entry:IsVisible())
AuctionHouseFrame:Show();entry.scripts.OnClick(entry)
S.AuctionHousePanel.Browser.portableButton.scripts.OnClick()
assert(entry:IsVisible() and S.AuctionHousePanel:IsVisible() and MarketSyncForeverScannerWindow:IsVisible())
assert(MarketSyncForeverScannerWindow.template=="PortraitFrameTemplate")
S.RememberKey(key);S.ToggleWatch(S.KeyID(key));S.StartWatched()
AuctionHouseFrame:Hide()
assert(not S.Active and not S.AuctioneerOpen and not S.AuctionHousePanel:IsShown())
S.EventFrame.scripts.OnEvent(S.EventFrame,"AUCTION_HOUSE_CLOSED");advance(40)
assert(not entry:IsVisible() and MarketSyncForeverScannerWindow:IsVisible() and #requests==0)
AuctionHouseFrame:Show();S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
assert(S.AuctionHouseEntry==entry and entry:IsVisible() and #requests==0)
assert(not S.AuctionHousePanel:IsVisible() and AuctionHouseFrame:GetDisplayMode()==AuctionHouseFrameDisplayMode.Buy)
assert(AuctionHouseFrame.selectedTab==1 and AuctionHouseFrame.title=="Buy" and not entry.selected)
local report=S.Report()
assert(report.auctionHouseEntryAttached and report.auctionHouseEntryMode=="embedded-tab")
assert(report.embeddedAuctionHousePanel and not report.auctionHousePanelVisible and report.portableDesign=="native-portrait")
assert(not report.alertsEnabled and not report.guildSyncEnabled)
`);
test('an unsupported client never adds an auction-house tab', `
AuctionHouseFrame=nativeAuctionFrame()
GetBuildInfo=function() return "12.1.0","69814","date",120100 end
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_LOGIN")
S.EventFrame.scripts.OnEvent(S.EventFrame,"ADDON_LOADED","Blizzard_AuctionHouseUI")
S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
assert(not S.Ready and not S.AuctionHouseEntry and not S.AttachAuctionHouseEntry() and #requests==0)
`);
test('exported Blizzard controller restores every native display and title after leaving MarketSync', `
AuctionHouseFrame=nativeAuctionFrame();assert(S.AttachAuctionHouseEntry())
for name,mode in pairs(AuctionHouseFrameDisplayMode) do
 assert(S.ShowAuctionHousePanel() and S.AuctionHousePanel:IsVisible())
 AuctionHouseFrame.BuyDialog:Show();local before=#hiddenPopups
 S.ShowAuctionHousePanel();assert(S.AuctionHousePanel:IsVisible())
 AuctionHouseFrame:SetDisplayMode(mode)
 assert(not S.AuctionHousePanel:IsShown() and not S.AuctionHouseEntry.selected)
 assert(AuctionHouseFrame:GetDisplayMode()==mode)
 for _,subframe in ipairs(mode) do assert(AuctionHouseFrame[subframe]:IsShown(),name.." missing "..subframe) end
 local expected=name:find("Sell") and 2 or name=="Auctions" and 3 or 1
 assert(AuctionHouseFrame.selectedTab==expected)
 assert(AuctionHouseFrame.title==(expected==2 and "Sell" or expected==3 and "Auctions" or "Buy"))
 assert(not AuctionHouseFrame.BuyDialog:IsShown() and #hiddenPopups-before==#AuctionHouseFramePopups)
end
assert(#requests==0)
`);
test('other managed addon tabs coexist before and after MarketSync without shifting native indexes', `
AuctionHouseFrame=nativeAuctionFrame()
local other=widget();local otherMode={"OtherPane"}
AuctionHouseFrame.OtherPane=widget();AuctionHouseFrameDisplayMode.OtherAddon=otherMode
table.insert(AuctionHouseFrame.Tabs,other);AuctionHouseFrame.tabsForDisplayMode[otherMode]=4
assert(S.AttachAuctionHouseEntry() and S.AuctionHouseTabIndex==5)
local later=widget();local laterMode={"LaterPane"}
AuctionHouseFrame.LaterPane=widget();AuctionHouseFrameDisplayMode.LaterAddon=laterMode
table.insert(AuctionHouseFrame.Tabs,later);AuctionHouseFrame.tabsForDisplayMode[laterMode]=6
PanelTemplates_SetNumTabs(AuctionHouseFrame,6)
S.ShowAuctionHousePanel();assert(AuctionHouseFrame.selectedTab==5 and S.AuctionHouseEntry.selected)
AuctionHouseFrame:SetDisplayMode(laterMode)
assert(AuctionHouseFrame.selectedTab==6 and later.selected and not S.AuctionHousePanel:IsShown())
assert(AuctionHouseFrame.Tabs[4]==other and AuctionHouseFrame.Tabs[6]==later)
assert(AuctionHouseFrame.tabsForDisplayMode[AuctionHouseFrameDisplayMode.ItemSell]==2)
assert(AuctionHouseFrame.tabsForDisplayMode[AuctionHouseFrameDisplayMode.Auctions]==3)
assert(S.AttachAuctionHouseEntry() and #AuctionHouseFrame.Tabs==6 and #requests==0)
`);
test('embedded and portable browsers share watches, price updates and scan state with independent searches', `
commodityRows={{quantity=10,unitPrice=60}};S.CaptureSearch(commodityKey,true)
AuctionHouseFrame=nativeAuctionFrame();S.AttachAuctionHouseEntry();S.ShowAuctionHousePanel();S.ShowWindow()
local ah=S.AuctionHousePanel.Browser;local portable=MarketSyncForeverScannerWindow.Browser
assert(#S.MarketBrowsers==2 and ah.rows[1].record.keyID==S.KeyID(commodityKey))
ah.rows[1].watch.scripts.OnClick()
assert(S.Store.watched[S.KeyID(commodityKey)] and portable.rows[1].watch:GetText()=="*")
portable.search:SetText("nothing");assert(not portable.rows[1]:IsShown() and ah.rows[1]:IsShown())
commodityRows={{quantity=12,unitPrice=70}};fullCommodity=false;S.CaptureSearch(commodityKey,true)
portable.search:SetText("")
assert(ah.rows[1].price:GetText()=="0g 0s 70c" and portable.rows[1].price:GetText()=="0g 0s 70c")
assert(ah.rows[1].seen:GetText():find("Partial") and S.Provider.GetSnapshot(commodityKey).minUnitPrice==60)
ah.rows[1].scripts.OnClick();assert(ah.selected==S.KeyID(commodityKey) and portable.selected==nil)
assert(ah.detail:GetText():find("Blizzard commodity search") and ah.detailScroll.verticalScroll==0)
S.StartWatched()
assert(ah.stopButton.enabled and portable.stopButton.enabled and not ah.scanButton.enabled)
advance(.2);fullCommodity=true;S.CaptureSearch(commodityKey,true);advance(2)
assert(not ah.stopButton.enabled and portable.scanButton.enabled and S.Store.completedWatchScans==1)
assert(ah.rows[1].seen:GetText():find("Full item") and portable.rows[1].quantity:GetText()=="12")
`);
test('modern browsers reset selected details on isolated Main and Neutral store changes', `
itemRows={{itemKey=key,quantity=4,buyoutAmount=100}};S.CaptureSearch(key,false);S.ToggleWatch(S.KeyID(key))
local main=S.Store
AuctionHouseFrame=nativeAuctionFrame();S.AttachAuctionHouseEntry();S.ShowAuctionHousePanel();S.ShowWindow()
local portable=MarketSyncForeverScannerWindow.Browser
portable.rows[1].scripts.OnClick();assert(portable.selected==S.KeyID(key))
AuctionHouseFrame:Hide();assert(S.SetMarket("neutral"))
assert(not portable.rows[1]:IsShown() and portable.selected==nil and not portable.scanButton.enabled)
AuctionHouseFrame:Show();S.EventFrame.scripts.OnEvent(S.EventFrame,"PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21)
commodityRows={{quantity=3,unitPrice=90}};S.CaptureSearch(commodityKey,true);S.ShowAuctionHousePanel()
assert(S.AuctionHousePanel.Browser.rows[1].record.keyID==S.KeyID(commodityKey))
AuctionHouseFrame:Hide();assert(S.SetMarket("main"))
assert(S.Store==main and portable.rows[1].record.keyID==S.KeyID(key))
assert(portable.rows[1].price:GetText()=="0g 0s 25c" and portable.rows[1].watch:GetText()=="*")
assert(not S.AuctionHousePanel:IsVisible() and MarketSyncForeverScannerWindow:IsVisible())
`);
test('an unavailable native tab controller leaves the auction house unmodified', `
AuctionHouseFrame=nativeAuctionFrame();AuctionHouseFrame.tabsForDisplayMode=nil
assert(not S.AttachAuctionHouseEntry())
assert(#AuctionHouseFrame.Tabs==3 and not S.AuctionHousePanel and not S.AuctionHouseEntry)
assert(AuctionHouseFrame:GetDisplayMode()==AuctionHouseFrameDisplayMode.Auctions and #requests==0)
`);
test('opening the embedded tab while offline is held without changing native display or querying', `
AuctionHouseFrame=nativeAuctionFrame();S.AttachAuctionHouseEntry();S.AuctioneerOpen=false
assert(not S.ShowAuctionHousePanel() and not S.AuctionHousePanel:IsVisible())
assert(AuctionHouseFrame:GetDisplayMode()==AuctionHouseFrameDisplayMode.Auctions and #requests==0)
`);
console.log(`Validated ${modules.length} production Lua files as Lua 5.1; ${passed} runtime cases passed against the exported Blizzard display controller.`);
