const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(chunk) {
  if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
const read = name => fs.readFileSync(path.join(__dirname, '../MarketSync', name), 'utf8');
run(`
  frames = {}
  local methods = {}
  function methods:SetScript(event, fn) self.scripts[event] = fn end
  function methods:SetText(text) self.text = text end
  function methods:GetText() return self.text or "" end
  function methods:GetName() return self.name end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:IsShown() return self.shown ~= false end
  function methods:GetWidth() return 900 end
  function methods:GetHeight() return 500 end
  function methods:GetMinMaxValues() return 0, 1 end
  function methods:GetVerticalScroll() return 0 end
  function methods:GetVerticalScrollRange() return 0 end
  function methods:RegisterForClicks(...) self.clicks = { ... } end
  local function object(kind, name, parent)
    local result = setmetatable({ kind = kind, name = name, parent = parent, scripts = {} }, {
      __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^[A-Z]") then return function() end end
      end,
    })
    frames[#frames + 1] = result
    return result
  end
  function methods:CreateTexture() return object("Texture", nil, self) end
  function methods:CreateFontString() return object("FontString", nil, self) end
  function methods:CreateLine() return object("Line", nil, self) end
  CreateFrame = object
  UIParent = CreateFrame("Frame", "UIParent")
  GameTooltip = object("Tooltip")
  C_Timer = { After = function() end, NewTimer = function() return {} end }
  date = function() return "12:00" end
  time = function() return 100 end
  GetCursorInfo = function() end
  UIDropDownMenu_CreateInfo = function() return {} end
  UIDropDownMenu_AddButton = function(info) menuEntries[#menuEntries + 1] = info end
  UIDropDownMenu_Initialize = function(frame, fn) frame.initialize = fn end
  ToggleDropDownMenu = function(_, _, frame)
    openedMenu = frame
    menuEntries = {}
    frame.initialize(frame, 1)
  end
  CloseDropDownMenus = function() end
  MarketSyncDB = { Favorites = { Favorites = { 123 }, Other = { 123 } }, PersonalData = {} }
  MarketSync = {
    GetThemeColor = function() return 0, 0, 0, 1 end,
    GetRealmDB = function() return MarketSyncDB end,
    GetAuctionPrice = function() return 750 end,
    GetItemInfo = function(id)
      local n = tonumber(id) or tonumber(tostring(id):match("item:(%d+)")) or 123
      return "Test Ore", "item:" .. n, 1, 1, 1, "Trade Goods", "Ore", 20, "", 134400
    end,
    NormalizeItemKey = function(key) return "p:" .. key.itemID .. ":5" end,
    FormatMoney = function(n) return tostring(n) end,
    SearchInAuctionHouse = function(name) searched = name end,
    OpenAlertEditorWithItem = function(link, price) alertLink, alertPrice = link, price end,
    ShowAnalytics = function() end,
    Scanner = {
      RegisterCallback = function() end, ResultsRevision = 1, Status = "Ready",
      RecentResults = {
        { itemID = 123, name = "Test Ore", unitPrice = 750, available = 2, icon = 134400 },
        { itemKey = { itemID = 456, itemLink = "item:456:0:0:0:0:0:5" },
          name = "Variant Ore", unitPrice = 900, available = 1, icon = 134400 },
      },
    },
  }
  MarketSync.MainFrame = CreateFrame("Frame", "MainFrame")
`);
run(read('Favorites.lua'));
const config = read('Config.lua');
run(config.slice(config.indexOf('local globalItemContextMenu = nil')));
run(`
  local original = MarketSync.ShowItemContextMenu
  MarketSync.ShowItemContextMenu = function(anchor, opts)
    lastContext = opts
    original(anchor, opts)
  end
  function action(text)
    for _, info in ipairs(menuEntries) do if info.text == text then return info end end
  end
`);
run(read('UI_AHScanner.lua'));
run(`
  scannerPanel = MarketSync.CreateAHScannerPanel(MarketSync.MainFrame)
  scannerPanel.OnShow()
  local listRow, feedRow, variantRow
  for _, row in ipairs(frames) do
    if row.kind == "Button" and rawget(row, "delBtn") then listRow = row end
    if row.kind == "Button" and type(row.data) == "table" then
      if row.data.itemID == 123 then feedRow = row else variantRow = row end
    end
  end
  assert(listRow and feedRow and variantRow, "Expected scanner list and feed rows")
  listRow.scripts.OnClick(listRow, "RightButton")
  assert(lastContext.listName == "Favorites" and action("Remove from Favorites"))
  assert(action("Create Price Alert") and action("Add to List"))
  action("Create Price Alert").func()
  assert(alertLink == "item:123" and alertPrice == 750, "Alert uses clicked item and price")
  feedRow.scripts.OnClick(feedRow, "RightButton")
  assert(action("Remove from Favorites"), "Feed removal available only for active-list members")
  variantRow.scripts.OnClick(variantRow, "RightButton")
  assert(lastContext.itemID == 456 and lastContext.dbKey == "p:456:5")
  assert(lastContext.itemLink == "item:456:0:0:0:0:0:5", "Variant link must survive")
  assert(not action("Remove from Favorites"), "No removal for items outside active list")
  feedRow.scripts.OnClick(feedRow, "LeftButton")
  assert(searched == "Test Ore", "Keep scanner left-click search")
`);
run(read('UI_Analytics.lua'));
run(`
  local firstFrame = #frames + 1
  analytics = MarketSync.CreateAnalyticsPanel(MarketSync.MainFrame)
  analytics.ShowItem = function(_, key) selectedKey = key end
  analytics:OnShow()
  local recentRow, favoritesButton
  for i = firstFrame, #frames do
    local frame = frames[i]
    if frame.kind == "Button" and rawget(frame, "icon") and rawget(frame, "price") then recentRow = frame end
    if frame.kind == "Button" and frame.text == "Favorites  |cff888888v|r" then favoritesButton = frame end
  end
  assert(recentRow and favoritesButton, "Expected Analytics recent row and list button")
  selectedKey = nil
  recentRow.scripts.OnClick(recentRow, "RightButton")
  assert(not selectedKey, "Right-click must not change selected analytics item")
  assert(lastContext.hideAnalytics and not action("Show Analytics"))
  assert(action("Create Price Alert") and not action("Remove from Favorites"))
  recentRow.scripts.OnClick(recentRow, "LeftButton")
  assert(selectedKey == "123", "Keep analytics left-click selection")
  favoritesButton.scripts.OnClick(favoritesButton, "LeftButton")
  recentRow.scripts.OnClick(recentRow, "RightButton")
  assert(action("Remove from Favorites"), "Analytics list view supplies removal context")
  action("Remove from Favorites").func()
  assert(not MarketSync.Favorites.IsItemInList("Favorites", 123))
  assert(MarketSync.Favorites.IsItemInList("Other", 123), "Removal must not affect other lists")
  analytics.currentItem = { itemID = 123, dbKey = "123", name = "Test Ore", price = 750 }
  analytics.banner.scripts.OnMouseUp(analytics.banner, "RightButton")
  assert(lastContext.itemID == 123 and action("Create Price Alert"), "Banner exposes selected item actions")
  menuEntries = {}
  openedMenu.initialize(openedMenu, 2, "FAVORITE_LISTS")
  action("Favorites").func()
  assert(MarketSync.Favorites.IsItemInList("Favorites", 123), "Add to List uses real list manager")
  analytics.currentItem = nil
  lastContext = nil
  analytics.banner.scripts.OnMouseUp(analytics.banner, "RightButton")
  assert(lastContext == nil, "Empty Analytics banner must not offer phantom item actions")
`);
console.log('PASS shared scanner and Analytics item actions, contextual removal, and variant identity');
