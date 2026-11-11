// Reuse the real ledger's custody/receipt fixture, then exercise presentation.
const fs=require('fs');
const base=fs.readFileSync(require('path').join(__dirname,'test_item_ledger.js'),'utf8');
const extra=String.raw`
run(@@LUA@@
local oldWidget=widget
function widget()
 local w=oldWidget()
 function w:GetText() return self.text or '' end
 function w:SetTexture(v) self.texture=v end
 function w:SetEnabled(v) self.enabled=v end
 return w
end
GameTooltip=widget();function GameTooltip:SetItemByID(id) self.itemID=id end
function UIDropDownMenu_Initialize(menu,fn) menu.callback=fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems+1]=info end
function ToggleDropDownMenu(_,_,menu) menuItems={};menu.callback(menu,1) end
MarketSync.GetItemInfo=function(id) return id==555 and 'Bright Ore' or 'Item '..tostring(id),nil,2,nil,nil,nil,nil,nil,nil,'icon-'..tostring(id) end
who='Alice';faction='Horde';interface=16001
local I=MarketSync.ItemLedger
purchase=I.Record('auction purchase',{incoming={{itemID=555,qty=2}},cashOut=400,actualCost=400})
observation=I.Record('inventory observation',{state='unresolved',metadata={delta={['556:0']=-3}},evidence='storage snapshot'})
before=#I.List()
@@LUA@@);
run(fs.readFileSync(path.join(__dirname,'../MarketSync/Ledger/UI_ItemLedger.lua'),'utf8'));
run(@@LUA@@
local f=MarketSync.OpenItemLedger()
assert(f.cards[1].title.text:find('Gold spent') and f.cards[3].value.text:find('records'),'Summary cards have readable context')
local purchaseRow, observationRow
for _,row in ipairs(f.rows) do
 if row.item.text:find('Bright Ore') then purchaseRow=row end
 if row.item.text:find('Item 556') then observationRow=row end
end
assert(purchaseRow and observationRow,'Visual rows show item names')
assert(purchaseRow.icon.texture.texture=='icon-555','Rows use actual item icons')
purchaseRow.icon.scripts.OnEnter(purchaseRow.icon)
assert(GameTooltip.itemID==555,'Item tooltip uses correct identity')
purchaseRow.scripts.OnClick()
assert(f.selected==purchase.id and purchaseRow.selected,'Click updates selected record')
local cost=false;for _,row in ipairs(f.detailRows) do if row:IsShown() and row.text.text:find('Actual unit cost') then cost=true end end
assert(cost,'Actual cost appears in its own detail card')
f.actionButtons[3].scripts.OnClick(f.actionButtons[3])
for _,option in ipairs(menuItems) do assert(option.disabled,'Customer actions disabled without a service craft') end
f.cards[3].scripts.OnMouseUp()
assert(f.filter=='review','Review summary filters activity')
for _,row in ipairs(f.rows) do if row:IsShown() then assert(not row.item.text:find('Bright Ore'),'Recorded purchase excluded from needs-review filter') end end
observationRow=f.rows[1];observationRow.scripts.OnClick()
local movement=false;for _,row in ipairs(f.detailRows) do if row:IsShown() and row.icon.itemID==556 then movement=true end end
assert(movement,'Unresolved storage changes have item cards too')
assert(f.detailRows[1]:IsShown() and f.detailRows[1].qButtons and f.detailRows[1].qButtons[1]:IsShown(), 'Needs review record displays inline Quick Resolution buttons')
f.detailRows[1].qButtons[1].scripts.OnClick()
assert(observation.state=='reconciled', 'Clicking inline Quick Resolution button resolves the record immediately')
f.filter='all';f.query:SetText('bright ore');f.query.scripts.OnTextChanged(f.query)
assert(f.rows[1]:IsShown() and f.rows[1].item.text:find('Bright Ore') and not f.rows[2]:IsShown(),'Name search filters rows')
f.query:SetText('');f.query.scripts.OnTextChanged(f.query)
f.viewTabs[2].scripts.OnClick()
assert(f.viewMode=='stock','Stock tab switches to Character Stock & Lots view')
f.viewTabs[1].scripts.OnClick()
assert(f.viewMode=='activity','Activity tab switches back to In/Out stream')
assert(not f.expandedAudit,'Technical metadata hidden by default')
assert(#MarketSync.ItemLedger.List()==before and MarketSync.ItemLedger.Cost(purchase.lots[1])==200,'UI browsing does not change receipts or accounting')

-- Test mass observation resolution without script timeout (batch mode)
local I = MarketSync.ItemLedger
for i=1,200 do
  I.Record('inventory observation',{state='unresolved',metadata={delta={['557:0']=1}},evidence='storage snapshot'})
end
local refreshCalls=0
local origRefresh=f.Refresh
f.Refresh=function(self)
  refreshCalls=refreshCalls+1
  origRefresh(self)
end
local resolvedCount=I.ResolveAllObservations()
assert(resolvedCount>=200,'Mass observation resolution resolves all 200 records')
assert(refreshCalls<=1,'Batch resolution must not call UI refresh in a loop (calls: '..refreshCalls..')')
assert(I.batchDepth==0,'Batch depth must return to 0 after mass resolution')
f.Refresh=origRefresh

-- Verify ledger disabling guards
MarketSync.SetLedgerEnabled(false)
assert(MarketSync.IsLedgerEnabled() == false, 'Ledger disabled')
assert(MarketSync.OpenItemLedger() == nil, 'OpenItemLedger returns nil when disabled')
assert(MarketSync.ToggleItemLedger() == nil, 'ToggleItemLedger returns nil when disabled')
assert(not f:IsShown(), 'ItemLedger frame hidden when ledger disabled')
MarketSync.SetLedgerEnabled(true)
assert(MarketSync.IsLedgerEnabled() == true, 'Ledger re-enabled')
local reopened = MarketSync.OpenItemLedger()
assert(reopened ~= nil and reopened:IsShown(), 'OpenItemLedger succeeds when re-enabled')
@@LUA@@);
console.log('PASS visual ledger summaries, item icons, tooltips, selection, filters, costs and context actions');
`;
new Function('require','__dirname',base+extra.replaceAll('@@LUA@@',String.fromCharCode(96)))(require,__dirname);
