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
run(`
  _G = _G or {}
  function CreateFrame(_, name, parent, template)
    local frame = { name = name, parent = parent, template = template, visible = true, scripts = {} }
    function frame:SetPoint(...) self.point = {...} end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:GetFrameLevel() return self.level or 1 end
    function frame:SetID(id) self.id = id end
    function frame:GetID() return self.id end
    function frame:SetText(value) self.text = value end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:HookScript(event, fn) self.scripts[event] = fn end
    function frame:RegisterEvent() end
    function frame:Show()
      self.visible = true
      if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide() self.visible = false end
    function frame:IsShown() return self.visible end
    if name then _G[name] = frame end
    return frame
  end
  AuctionFrame = CreateFrame('Frame', 'AuctionFrame')
  AuctionFrame.numTabs = 3
  for i = 1, 3 do
    local tab = CreateFrame('Button', 'AuctionFrameTab' .. i, AuctionFrame)
    tab:SetID(i)
  end
  function PanelTemplates_SetNumTabs(frame, count) frame.numTabs = count end
  function PanelTemplates_EnableTab() end
  function PanelTemplates_TabResize() end
  selected = 1
  function PanelTemplates_GetSelectedTab() return selected end
  function AuctionFrameTab_OnClick(tab) selected = tab:GetID() end
  function hooksecurefunc(name, fn)
    local previous = _G[name]
    _G[name] = function(...)
      previous(...)
      fn(...)
    end
  end
  MarketSyncDB = {
    EnableProcessingTab = true, EnableAlertsTab = true,
    EnableAnalyticsTab = true, UseAuctionatorScanner = false,
  }
  sidecarVisible = nil
  MarketSync = {
    AuctionHouse = {},
    Scanner = { IsLegacyAH = true, Active = false },
    AHSidecar = {
      SetVisibleForAH = function(visible) sidecarVisible = visible end,
      SetMode = function(mode) sidecarMode = mode end,
    },
  }
  for _, name in ipairs({'CreateLegacySearchPanel', 'CreateAHScannerPanel',
      'CreateProcessingPanel', 'CreateNotificationsPanel', 'CreateAnalyticsPanel'}) do
    MarketSync[name] = function() return { Show = function() end } end
  end
  MarketSync.CreateAHSidecar = function() return CreateFrame('Frame') end
`);
run(fs.readFileSync(path.join(__dirname, '../MarketSync/LegacyAuctionHouse.lua'), 'utf8'));
run(`
  local ah = MarketSync.AuctionHouse
  assert(ah.AttachLegacy() == true)
  assert(AuctionFrame.numTabs == 8)
  assert(ah.LegacyTabs.search.text == 'Search' and ah.LegacyTabs.scanner.text == 'Scan')
  assert(ah.LegacyTabs.processing.text == 'Process')
  assert(ah.LegacyTabs.analytics.text == 'Analytics')
  assert(ah.Sidecar ~= nil and sidecarVisible == true)
  ah.LegacyTabs.search.scripts.OnClick()
  assert(ah.LegacyHosts.search:IsShown() and not ah.LegacyHosts.scanner:IsShown())
  assert(sidecarVisible == true)
  ah.LegacyTabs.processing.scripts.OnClick()
  assert(ah.LegacyHosts.processing:IsShown() and sidecarVisible == false)
  AuctionFrameTab_OnClick(_G.AuctionFrameTab3)
  assert(not ah.LegacyHosts.processing:IsShown() and sidecarVisible == true)
  assert(sidecarMode == 'sell')
  MarketSyncDB.EnableProcessingTab = false
  ah.RefreshTabVisibility()
  assert(not ah.LegacyTabs.processing:IsShown())
  assert(ah.LegacyTabs.alerts:IsShown())
  assert(ah.AttachLegacy() == true and AuctionFrame.numTabs == 8)
`);
console.log('PASS classic Auction House tabs, panel switching, and sidecar routing');
