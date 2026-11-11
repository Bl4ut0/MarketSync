const fs=require('fs');const path=require('path');
const {lua,lauxlib,lualib,to_luastring}=require('fengari');
const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
function run(code){if(lauxlib.luaL_dostring(state,to_luastring(code))!==lua.LUA_OK)throw Error(lua.lua_tojsstring(state,-1));}
run(`
theme='forever'; MarketSync={}
function MarketSync.GetUITheme() return theme end
function MarketSync.GetThemeColor(role) if role=='dialog' then return .075,.07,.065,.98 else return .1,.11,.12,.96 end end
function MarketSync.SkinModernScrollBar(frame) frame.skinned=true end
function frame(kind)
 local f={shown=false,children={},scripts={},kind=kind or 'Frame',backdrop={bgFile='black'}}
 function f:GetChildren() return table.unpack(self.children) end
 function f:GetBackdrop() return self.backdrop end
 function f:SetBackdrop(b) self.backdrop=b end
 function f:SetBackdropColor(...) self.color={...} end
 function f:SetBackdropBorderColor(...) self.border={...} end
 function f:IsObjectType(k) return self.kind==k end
 function f:IsShown() return self.shown end
 function f:HookScript(k,fn) local old=self.scripts[k];self.scripts[k]=function() if old then old() end;fn() end end
 function f:Show() if not self.shown then self.shown=true;if self.scripts.OnShow then self.scripts.OnShow() end end end
 function f:Hide() if self.shown then self.shown=false;if self.scripts.OnHide then self.scripts.OnHide() end end end
 return f
end
function button()
 local f=frame('Button');f.text='Buy';f.normal={SetVertexColor=function(self,...) self.color={...} end}
 function f:GetText() return self.text end
 function f:GetNormalTexture() return self.normal end
 function f:SetNormalTexture(value) self.texture=value end
 return f
end
`);
run(fs.readFileSync(path.join(__dirname,'../MarketSync/Theme.lua'),'utf8'));
run(`
local root=frame();local action=button();local icon=button();icon.text=nil
local scroll=frame('ScrollFrame');local selected=frame('Button');selected.selected=true;selected.color={.9,.8,.7,1}
root.children={action,icon,scroll,selected}
MarketSync.Theme.Register(root);root:Show()
assert(root.backdrop.bgFile=='Interface\\\\DialogFrame\\\\UI-DialogBox-Background-Dark' and root.backdrop.edgeFile=='Interface\\\\DialogFrame\\\\UI-DialogBox-Border','Root window uses authentic Warcraft dialog backdrop')
assert(action._marketSyncThemeButton and not action.texture,'Button preserves native Blizzard UIPanelButtonTemplate textures without flat WHITE8X8 overwriting')
assert(scroll.skinned and selected.color[1]==.9,'Style scrollbars and preserve selected rows')
theme='legacy';local old=button();MarketSync.Theme.Button(old);assert(old._marketSyncThemeButton,'Button registration handles legacy')
theme='forever'
local craft=frame();craft.Refresh=function(self) self.refreshed=true end
local ledger=frame();local purchase=frame()
MarketSync.ShowWorkspaceWindow(craft)
MarketSync.ShowWorkspaceWindow(ledger,craft)
assert(ledger:IsShown() and not craft:IsShown(),'Related large windows do not overlap')
ledger:Hide();assert(craft:IsShown() and craft.refreshed,'Closing ledger restores current craft context')
craft.dirty=true
craft.ConfirmContextSwitch=function(callback) pending=callback end
MarketSync.ShowWorkspaceWindow(ledger,craft)
assert(craft:IsShown() and not ledger:IsShown() and pending,'Unsaved changes protect context before switching')
craft.dirty=false;pending();assert(ledger:IsShown() and not craft:IsShown())
MarketSync.ShowWorkspaceWindow(purchase,craft)
assert(purchase:IsShown() and not ledger:IsShown(),'A hidden explicit source falls back to the active workspace')
purchase:Hide();assert(ledger:IsShown());ledger:Hide();assert(craft:IsShown())
`);
console.log('PASS theme coverage, icon/selection preservation, exclusive windows, draft protection and context restoration');
