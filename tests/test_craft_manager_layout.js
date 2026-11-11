const fs=require('fs');
const path=require('path');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
function run(source){if(lauxlib.luaL_dostring(state,to_luastring(source))!==lua.LUA_OK)throw Error(lua.lua_tojsstring(state,-1));}
run(`
function widget()
 local w={scripts={},width=300,height=0,shown=true,level=1}
 setmetatable(w,{__index=function(t,k) if k:match('^[A-Z]') then return function() end end end})
 function w:SetScript(k,v) self.scripts[k]=v end; function w:GetScript(k) return self.scripts[k] end
 function w:SetSize(x,y) self.width,self.height=x,y end
 function w:GetWidth() return self.width end; function w:GetFrameLevel() return self.level end
 function w:SetHeight(h) self.height=h end; function w:SetWidth(n) self.width=n end
 function w:CreateFontString() return widget() end; function w:CreateTexture() return widget() end
 function w:SetTexture(v) self.texture=v end
 function w:SetBackdropColor(...) self.background={...} end
 function w:SetBackdropBorderColor(...) self.border={...} end
 function w:SetPoint(...) self.point={...} end
 function w:Show() self.shown=true end; function w:Hide() self.shown=false end
 function w:SetEnabled(v) self.enabled=v end
 function w:IsShown() return self.shown end; function w:SetText(v) self.text=v end
 return w
end
function CreateFrame(_,name) local w=widget(); if name then _G[name]=w end; return w end
UIParent=widget();StaticPopupDialogs={};function StaticPopup_Show(k) lastPopup=k end
GameTooltip=widget();function GameTooltip:SetItemByID(id) self.itemID=id end
local names={[100]='Master Widget',[200]='Subcraft',[10]='Ore',[11]='Cloth'}
MarketSync={GetItemInfo=function(id) return names[id],nil,nil,nil,nil,nil,nil,nil,nil,'icon:'..tostring(id) end}
MarketSyncDB={}
function MarketSync.CalculateGroundUpCraftCost(recipe,choices,qty)
 local craft=choices[200]~=false
 return {outputQty=qty,reagentsTree={{itemID=200,name='Subcraft',qty=qty,canCraft=true,chooseCraft=craft,directTotalPrice=200,craftTotalPrice=100,subMats={{itemID=10,name='Ore',qty=qty*2,chooseCraft=false,directTotalPrice=100}}},{itemID=11,name='Cloth',qty=qty,chooseCraft=false,directTotalPrice=50}}}
end
function MarketSync.BuildCraftPurchasePlan(req)
 return {buys=req.choices[200]==false and {[200]={qty=req.quantity,unitPrice=200}} or {[10]={qty=req.quantity*2,unitPrice=50}},provided={},recipes={}}
end
function MarketSync.CalculateRecipeProfit() return {outputPrice=1000,grossRevenue=1000,netRevenue=950} end
local recipe={name='Master Widget',outputItemID=100,mats={{itemID=200,qty=1}}}
jobs={{id=1,name='Master Widget',itemID=100,recipe=recipe,quantity=1,status='Shopping',choices={},selectedBuys={},purchased={},sales={},plan={provided={}},outputQty=1},{id=2,name='Other Widget',itemID=100,recipe=recipe,quantity=2,status='Shopping',choices={},selectedBuys={},purchased={},sales={},plan={provided={}},outputQty=2}}
local L={}
MarketSync.CraftLedger=L
function L.Get(id) return jobs[id] end; function L.List(history) return history and {} or jobs end
function L.Totals() return {paid=0,sold=0,gross=0,fees=0} end
function L.Remaining(job) return MarketSync.BuildCraftPurchasePlan({choices=job.choices,quantity=job.quantity}).buys end
function L.Save(recipe,options,id)
 local j=jobs[id]; j.choices=options.choices; j.selectedBuys=options.selectedBuys; j.quantity=options.quantity; return j
end
function UIDropDownMenu_Initialize(menu,callback) menu.callback=callback end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems+1]=info end
function ToggleDropDownMenu(_,_,menu) menuItems={}; menu.callback(menu,1) end
`);
const source=fs.readFileSync(path.join(__dirname,'../MarketSync/Ledger/UI_CraftManager.lua'),'utf8');
require('luaparse').parse(source,{luaVersion:'5.1'});run(source);
run(`
MarketSync.OpenCraftingTree(jobs[1].recipe,nil,{ledgerID=1})
local f=MarketSyncCraftManager
assert(f.width==832 and f.height==480,'Compact window dimensions')
assert(f.panes[3].rows[1].selected and not f.panes[3].rows[2].selected,'Active craft highlight')
assert(f.panes[1].rows[2].iconButton:IsShown(),'Ingredient icon')
f.panes[1].rows[2].iconButton.scripts.OnEnter(f.panes[1].rows[2].iconButton)
assert(GameTooltip.itemID==200,'Hovered icon links to the correct item')
assert(f.panes[1].content.height==128,'Expanded root, subcraft and two materials')
f.panes[1].rows[2].expand.scripts.OnClick()
assert(f.panes[1].content.height==96 and not f.dirty,'Collapsing changes only presentation')
f.panes[1].rows[2].expand.scripts.OnClick()
assert(f.panes[1].content.height==128,'Subcraft expands again')
f.panes[1].rows[2].action.scripts.OnClick()
for _,option in ipairs(menuItems) do if option.text=='Buy' then option.func(); break end end
assert(f.dirty and f.choices[200]==false and jobs[1].choices[200]==nil,'Dropdown edits remain a draft')
assert(f.panes[1].content.height==96,'Bought subcraft hides child materials')
assert(f.panes[2].rows[1].itemID==200,'Purchase plan immediately follows draft')
assert(f.state.text:find('Unsaved changes'),'Draft is clearly marked')
f.panes[3].rows[1].scripts.OnClick(nil,'LeftButton')
assert(f.dirty and f.choices[200]==false,'Reselecting active job preserves edits')
f.panes[3].rows[2].scripts.OnClick(nil,'LeftButton')
assert(lastPopup=='MARKETSYNC_SAVE_CRAFT' and f.jobID==1,'Switching context protects unsaved changes')
StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT.OnAlt()
assert(f.jobID==2 and not f.dirty and f.quantity==2,'Selecting another craft loads its context')
assert(f.panes[3].rows[2].selected and not f.panes[3].rows[1].selected,'Selection highlight follows context')
f.panes[1].rows[2].action.scripts.OnClick()
for _,option in ipairs(menuItems) do if option.text=='Provide' then option.func(); break end end
assert(f.dirty and jobs[2].selectedBuys[200]==nil)
f.save.scripts.OnClick()
assert(not f.dirty and jobs[2].selectedBuys[200]==false and jobs[2].choices[200]==false,'Update commits decisions')
f.dirty=true; f.quantity=3
f.closeButton.scripts.OnClick()
assert(f:IsShown() and lastPopup=='MARKETSYNC_SAVE_CRAFT','Close offers Save/Discard/Cancel')
assert(StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT.button2=='Cancel')
assert(StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT.button3=='Discard')
assert(f.dirty and jobs[2].quantity==2,'Cancel leaves draft untouched')
StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT.OnAccept()
assert(not f:IsShown() and jobs[2].quantity==3 and not f.dirty,'Save commits before closing')
f:Show();f.dirty=true;f.quantity=9
f.panes[3].rows[1].scripts.OnClick(nil,'LeftButton')
StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT.OnAccept()
assert(jobs[2].quantity==9 and f.jobID==1,'Save commits before switching profiles')
f.dirty=true;f.quantity=99
f.closeButton.scripts.OnClick();StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT.OnAlt()
assert(jobs[1].quantity==1 and f.quantity==1 and not f:IsShown(),'Discard restores stored craft')
f:Show();f.dirty=true
f.scripts.OnHide()
assert(f:IsShown() and lastPopup=='MARKETSYNC_SAVE_CRAFT','Escape/programmatic Hide protects draft')
`);
console.log('PASS compact craft manager, tooltips, branch expansion, context selection and draft updates');
