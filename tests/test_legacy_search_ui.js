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
    function frame:SetStatusBarTexture() end
    function frame:SetStatusBarColor() end
    function frame:SetMinMaxValues(low, high) self.minimum, self.maximum = low, high end
    function frame:SetValue(value) self.value = value end
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
    GetThemeColor = function() return 0.1, 0.1, 0.1, 1 end,
    Scanner = {
      LiveSearchResults = {},
      Status = "Idle",
      IsAvailable = function() return true end,
      IsDisabledByAuctionator = function() return false end,
      PrepareLivePurchase = function(row)
        if MarketSync.Scanner.Active then MarketSync.Scanner.Cancel("replaced by purchase check") end
        MarketSync.Scanner.PurchaseReady = { row = row }
      end,
      Cancel = function(reason)
        MarketSync.Scanner.Active = false
        MarketSync.Scanner.LiveSearchProgress.state = "stopped"
        MarketSync.Scanner.Status = reason
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
  assert(panel.ResultRows[1].name:GetText() == "[+] Test Ore")
  assert(not panel.ResultRows[2]:IsShown(), "Items start collapsed")
  panel.ResultRows[1].scripts.OnClick(panel.ResultRows[1])
  assert(panel.ResultRows[2].data == result, "Expanding reveals exact stack rows")
  assert(panel.BuyButton.enabled == true, "Buying should enable after exact-stack validation")
  local cheaper = { name = "Test Ore", itemID = 100, unitPrice = 50,
    stackSize = 5, auctions = 2, available = 10, buyout = 250 }
  MarketSync.Scanner.LiveSearchResults = { result, cheaper }
  panel:Refresh()
  assert(panel.ResultRows[1].price:GetText() == "50c", "Header shows minimum unit price")
  assert(panel.ResultRows[1].available:GetText() == "16", "Header sums availability")
  panel.ResultRows[1].scripts.OnClick(panel.ResultRows[1])
  assert(not panel.ResultRows[2]:IsShown(), "Group collapses again")
  assert(MarketSync.Scanner.PurchaseReady.row == cheaper, "Group selects cheapest actual stack")

  MarketSync.Scanner.Active = true
  MarketSync.Scanner.LiveSearchProgress = { completed = 1, total = 3, query = "Test Herb", state = "scanning" }
  panel:Refresh()
  assert(panel.ScanProgressBar.value == 1 and panel.ScanProgressBar.maximum == 3)
  assert(panel.ScanProgressText:GetText() == "Scanning - 1 / 3 searched")
  assert(panel.StopScanButton.enabled)
  panel.ResultRows[1].scripts.OnClick(panel.ResultRows[1])
  assert(panel.ScanProgressText:GetText() == "Scan stopped - 1 / 3 searched",
    "Result interactions must retain the stopped scan progress during purchase checks")
  assert(not panel.StopScanButton.enabled and #MarketSync.Scanner.LiveSearchResults == 2)
  MarketSync.Scanner.Active = true
  MarketSync.Scanner.LiveSearchProgress.state = "scanning"
  panel:Refresh()
  panel.StopScanButton.scripts.OnClick()
  assert(not MarketSync.Scanner.Active and panel.ScanProgressBar.value == 1)
  assert(panel.ScanProgressText:GetText() == "Scan stopped - 1 / 3 searched")
  MarketSync.Scanner.LiveSearchProgress.completed = 3
  MarketSync.Scanner.LiveSearchProgress.state = "complete"
  panel:Refresh()
  assert(panel.ScanProgressBar.value == 3 and not panel.StopScanButton.enabled)
  assert(panel.ScanProgressText:GetText() == "Scan complete - 3 / 3 searched")

  panel.SearchField:SetText("Other Ore")
  panel.SearchButton.scripts.OnClick()
  assert(MarketSync.Scanner.lastQuery == "Other Ore")
`);
console.log('PASS classic Search layout, empty state, result selection, and purchase validation');
