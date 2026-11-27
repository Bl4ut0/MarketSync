// UI tests for the legacy multi-item Scan page (MarketSync/UI_LegacyMultiScan.lua).
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let passed = 0;
function run(source) {
  if (lauxlib.luaL_dostring(L, to_luastring(source)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
function test(name, chunk) {
  try { run(chunk); } catch (e) { console.error('FAIL ' + name + ': ' + e.message); process.exit(1); }
  console.log('PASS ' + name);
  passed++;
}

run(`
  -- Frames: record what the page sets; any other widget method is a no-op.
  local noop = function() end
  local methods = {}
  function methods:SetSize(w, h) self.width, self.height = w, h end
  function methods:SetWidth(w) self.width = w end
  function methods:GetWidth() return self.width or 0 end
  function methods:SetText(v) self.text = v end
  function methods:GetText() return self.text or "" end
  function methods:SetEnabled(v) self.enabled = v end
  function methods:SetScript(name, fn) self.scripts[name] = fn end
  function methods:HookScript(name, fn) self.scripts[name] = fn end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:IsShown() return self.shown end
  function methods:SetTexture(t) self.texture = t end
  function methods:GetVerticalScroll() return 0 end
  function methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
  function methods:SetValue(v) self.value = v end
  function methods:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end
  function methods:CreateFontString() return NewRegion(self) end
  function methods:CreateTexture() return NewRegion(self) end
  local meta = { __index = function(_, key)
    if type(key) == "string" and key:match("^%u") then return methods[key] or noop end
  end }
  function NewRegion(parent)
    return setmetatable({ parent = parent, scripts = {}, shown = true }, meta)
  end
  CreateFrame = function(_, _, parent) return NewRegion(parent) end
  UIParent = NewRegion()
  GameTooltip = NewRegion()
  itemNames = { [100] = "Test Ore", [200] = "Test Herb", [300] = "Test Vial" }
  function GetItemInfo(ref)
    local id = tonumber(ref) or (type(ref) == "string" and tonumber(ref:match("item:(%d+)")))
    if id and itemNames[id] then return itemNames[id], "item:" .. id, 1, 1, 1, "", "", 20, "", 134 end
  end
  function GetMoney() return 100000 end
  StaticPopupDialogs = {}
  function StaticPopup_Show(name, a, b, data) popup = { name = name, a = a, b = b, data = data } end
  NUM_BAG_SLOTS = 0
  bag = {}
  C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
    GetContainerItemInfo = function(_, slot) return bag[slot] end,
  }
  printed = {}
  started = nil
  MarketSyncDB = {}

  -- Shopping lists: just enough of Favorites.lua for the page.
  lists = { Favorites = {}, Herbs = { 200 } }
  selectedList = "Favorites"
  favCallbacks = {}
  local function changed() for _, fn in ipairs(favCallbacks) do fn() end end
  local function idOf(ref) return tonumber(ref) or (type(ref) == "string" and tonumber(ref:match("item:(%d+)"))) end
  Favorites = {
    GetLists = function()
      local names = {}
      for name in pairs(lists) do names[#names + 1] = name end
      table.sort(names)
      return names
    end,
    CreateList = function(name) if lists[name] then return false end; lists[name] = {}; changed(); return true end,
    GetSelectedList = function() return selectedList end,
    SetSelectedList = function(name) selectedList = name; changed(); return true end,
    GetListItems = function(name)
      local out = {}
      for _, id in ipairs(lists[name] or {}) do
        out[#out + 1] = { itemID = id, suffix = 0, name = itemNames[id], link = "item:" .. id, dbKey = tostring(id) }
      end
      return out
    end,
    IsItemInList = function(name, ref)
      for _, id in ipairs(lists[name]) do if id == idOf(ref) then return true end end
      return false
    end,
    AddToList = function(name, ref) table.insert(lists[name], idOf(ref)); changed(); return true end,
    RemoveFromList = function(name, ref)
      for i, id in ipairs(lists[name]) do if id == idOf(ref) then table.remove(lists[name], i) break end end
      changed()
      return true
    end,
    RegisterCallback = function(fn) favCallbacks[#favCallbacks + 1] = fn end,
  }

  prepared = nil
  MarketSync = {
    Favorites = Favorites,
    Print = function(msg) printed[#printed + 1] = msg end,
    FormatMoney = function(v) return tostring(v) .. "c" end,
    GetThemeColor = function() return 0.1, 0.1, 0.1, 1 end,
    GetItemPriceAndScanInfo = function(key) if key == "100" then return { price = 100 } end end,
    Scanner = {
      Active = false, Status = "Idle",
      IsAvailable = function() return true end,
      IsDisabledByAuctionator = function() return false end,
      ToItemKey = function(ref)
        local id = idOf(ref)
        if not id and type(ref) == "string" then
          for k, v in pairs(itemNames) do if v == ref then id = k end end
        end
        return id and { itemID = id, itemSuffix = 0 } or nil
      end,
      StartMultiScan = function(items) started = items; return true end,
      RegisterCallback = function(fn) refreshCallback = fn end,
      PrepareLivePurchase = function(row) prepared = row; return true end,
      BuyPreparedLivePurchase = function(row) bought = row; return true end,
    },
  }
  MarketSync.Scanner.GetMultiScan = function() return MarketSync.Scanner.MultiScan end
`);
run(fs.readFileSync(path.join(__dirname, '../MarketSync/UI_LegacyMultiScan.lua'), 'utf8'));
run(`panel = MarketSync.CreateLegacyMultiScanPanel(NewRegion()); panel.shown = true; panel.Refresh()`);

test('Adding items edits the shopping list selected in the breakout', `
  panel.ItemInput.text = "Test Ore"
  panel.ItemInput.scripts.OnEnterPressed(panel.ItemInput)
  assert(#lists.Favorites == 1 and lists.Favorites[1] == 100, "added to the selected list")
  assert(panel:AddItem("item:300") == true)
  assert(panel:AddItem("item:100") == false, "no duplicate")
  assert(#lists.Favorites == 2)
  assert(panel.QueueRows[1].name.text == "Test Ore" and panel.QueueRows[2].name.text == "Test Vial")
  assert(panel.SummaryRows[1].state.text:find("Not scanned"))
  assert(panel.AddListButton.text:find("Favorites"), "list picker shows the selected list")
  assert(panel.ScanButton.enabled == true)
`);

test('An unknown name is reported instead of added', `
  panel.ItemInput.text = "No Such Item"
  panel.ItemInput.scripts.OnEnterPressed(panel.ItemInput)
  assert(#lists.Favorites == 2 and printed[#printed]:find("Item not found"))
`);

test('A list picked in the breakout shows on the Scan page', `
  Favorites.SetSelectedList("Herbs")
  assert(panel.QueueRows[1].name.text == "Test Herb" and panel.QueueRows[2].shown == false)
  assert(panel.AddListButton.text:find("Herbs"))
  Favorites.SetSelectedList("Favorites")
  assert(panel.QueueRows[1].name.text == "Test Ore")
`);

test('Removing an item removes it from the list', `
  panel.QueueRows[2]:Click("RightButton")
  assert(#lists.Favorites == 1 and lists.Favorites[1] == 100)
  table.insert(lists.Favorites, 300)
  refreshCallback()
`);

test('Scan All scans the whole selected list', `
  panel.ScanButton:Click()
  assert(started and #started == 2 and started[1].itemID == 100 and started[2].itemID == 300)
`);

test('Results show lowest price, change against market, and the selected item listings', `
  MarketSync.Scanner.MultiScan = { state = "complete", completed = 2, items = {
    { itemID = 100, itemSuffix = 0, name = "Test Ore", state = "done", minUnit = 80, available = 11, auctions = 3,
      previousPrice = 100, listings = {
        { unitPrice = 80, stackSize = 1, auctions = 1, buyout = 80, mine = true, link = "item:100", name = "Test Ore" },
        { unitPrice = 100, stackSize = 5, auctions = 2, buyout = 500, link = "item:100", name = "Test Ore" } } },
    { itemID = 300, itemSuffix = 0, name = "Test Vial", state = "empty", available = 0, auctions = 0, listings = {} },
  } }
  refreshCallback()
  local ore = panel.SummaryRows[1]
  assert(ore.price.text == "80c", ore.price.text)
  assert(ore.delta.text:find("%-20%%"), "20% below market: " .. ore.delta.text)
  assert(ore.available.text == "11 (3)")
  assert(panel.SummaryRows[2].state.text:find("No auctions"))
  assert(panel.DetailRows[1].price.text == "80c" and panel.DetailRows[1].seller.text:find("You"))
  assert(panel.DetailRows[2].stack.text == "5" and panel.DetailRows[2].buyout.text == "500c")
  assert(panel.DetailRows[3].shown == false)
`);

test('A listing is checked on the Auction House, then bought after confirming', `
  panel.DetailRows[1]:Click()
  assert(prepared == nil, "own auctions cannot be bought")
  panel.DetailRows[2]:Click()
  assert(prepared and prepared.buyout == 500, "selected stack is re-checked")
  assert(panel.BuyButton.enabled == false, "not buyable until verified")
  MarketSync.Scanner.PurchaseReady = { row = prepared, index = 4 }
  refreshCallback()
  assert(panel.BuyButton.enabled == true)
  panel.BuyButton:Click()
  assert(popup and popup.name == "MARKETSYNC_LEGACY_SCAN_BUY_STACK" and popup.b == "500c")
  StaticPopupDialogs[popup.name].OnAccept(nil, popup.data)
  assert(bought == prepared)
  MarketSync.Scanner.PurchaseReady = nil
`);

test('Items from a scan started elsewhere are listed under the list items', `
  MarketSync.Scanner.MultiScan.items[3] = { itemID = 200, itemSuffix = 0, name = "Test Herb", state = "done",
    minUnit = 5, available = 1, auctions = 1, listings = {} }
  refreshCallback()
  assert(panel.QueueRows[3].name.text == "Test Herb" and panel.QueueRows[3].state.text:find("Not in list"))
  assert(#lists.Favorites == 2, "not added to the list")
`);

test('Clear removes the results but keeps the list', `
  panel.ClearButton:Click()
  assert(MarketSync.Scanner.MultiScan == nil and #lists.Favorites == 2)
`);

test('Bags fills its own Bags list, not the selected list, and shows it', `
  lists.Consumables = { 200 }
  Favorites.SetSelectedList("Consumables")
  bag[1] = { itemID = 100, hyperlink = "item:100", isBound = false }
  bag[2] = { itemID = 300, hyperlink = "item:300", isBound = true }
  panel.AddBagsButton:Click()
  assert(#lists.Consumables == 1 and lists.Consumables[1] == 200, "selected list untouched")
  assert(lists.Bags and #lists.Bags == 1 and lists.Bags[1] == 100, "soulbound item skipped")
  assert(selectedList == "Bags", "Bags list is shown")
  assert(panel.QueueRows[1].name.text == "Test Ore")
  assert(printed[#printed]:find("1 tradeable"))
  -- Next click rebuilds it from the current bags.
  bag[1] = { itemID = 200, hyperlink = "item:200", isBound = false }
  panel.AddBagsButton:Click()
  assert(#lists.Bags == 1 and lists.Bags[1] == 200, "items no longer in the bags drop off")
`);

test('Stop is only available while a list scan runs', `
  MarketSync.Scanner.MultiScan = { state = "scanning", completed = 0, items = {} }
  MarketSync.Scanner.Active = true
  refreshCallback()
  assert(panel.StopButton.enabled == true and panel.ScanButton.enabled == false)
  MarketSync.Scanner.Active = false
  MarketSync.Scanner.MultiScan.state = "complete"
  refreshCallback()
  assert(panel.StopButton.enabled == false)
`);

console.log(`All ${passed} multi-scan UI tests passed.`);
