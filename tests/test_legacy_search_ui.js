const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(source) {
  if (lauxlib.luaL_dostring(L, to_luastring(source)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}

run(`
  local function region(parent)
    local frame = { parent = parent, scripts = {}, shown = true }
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width or 0 end
    function frame:GetFrameLevel() return 1 end
    function frame:SetFrameLevel() end
    function frame:SetPoint() end
    function frame:SetAllPoints() end
    function frame:ClearAllPoints() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:SetColorTexture() end
    function frame:SetTextColor() end
    function frame:SetJustifyH() end
    function frame:SetWordWrap() end
    function frame:SetAutoFocus() end
    function frame:SetMaxLetters() end
    function frame:ClearFocus() end
    function frame:SetTexture() end
    function frame:SetScrollChild() end
    function frame:GetVerticalScroll() return 0 end
    function frame:EnableMouse() end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text or "" end
    function frame:SetEnabled(value) self.enabled = value end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:HookScript(name, callback) self.scripts[name] = callback end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:CreateFontString() return region(self) end
    function frame:CreateTexture() return region(self) end
    return frame
  end
  CreateFrame = function(_, _, parent) return region(parent) end
  GetMoney = function() return 100000 end
  MarketSync = {
    FormatMoney = function(value) return tostring(value) .. "c" end,
    Scanner = {
      LiveSearchResults = {},
      Status = "Idle",
      IsAvailable = function() return true end,
      IsDisabledByAuctionator = function() return false end,
      PrepareLivePurchase = function(row)
        MarketSync.Scanner.PurchaseReady = { row = row }
      end,
      StartLiveSearch = function(query) MarketSync.Scanner.lastQuery = query end,
    },
  }
`);
run(fs.readFileSync(path.join(__dirname, '../MarketSync/UI_LegacySearch.lua'), 'utf8'));
run(`
  local host = CreateFrame("Frame")
  host:SetSize(900, 410)
  local panel = MarketSync.CreateLegacySearchPanel(host)
  panel:Refresh()
  assert(panel.EmptyTitle:GetText() == "Find an item to buy")
  assert(panel.ResultRows[1].width == 814, "Rows should fill the viewport without entering the scrollbar gutter")

  panel.SearchField:SetText("Preserved Holly")
  MarketSync.Scanner.Status = "Search Complete (0 price/stack groups)"
  panel:Refresh()
  assert(panel.EmptyTitle:GetText() == "No matching auctions")
  assert(panel.EmptyHint:GetText():find("Preserved Holly", 1, true))

  local result = { name = "Test Ore", itemID = 100, icon = 123, unitPrice = 75,
    stackSize = 2, auctions = 3, available = 6, buyout = 150 }
  MarketSync.Scanner.LiveSearchResults = { result }
  panel:Refresh()
  assert(not panel.EmptyTitle:IsShown(), "The empty state should hide when results exist")
  assert(panel.ResultRows[1]:IsShown())
  assert(panel.ResultRows[1].name:GetText() == "Test Ore")
  panel.ResultRows[1].scripts.OnClick(panel.ResultRows[1])
  assert(panel.BuyButton.enabled == true, "Buying should enable after exact-stack validation")

  panel.SearchField:SetText("Other Ore")
  panel.SearchButton.scripts.OnClick()
  assert(MarketSync.Scanner.lastQuery == "Other Ore")
`);
console.log('PASS classic Search layout, empty state, result selection, and purchase validation');
