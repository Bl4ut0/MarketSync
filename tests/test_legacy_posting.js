const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const source = fs.readFileSync(path.join(__dirname, '../MarketSync/LegacyPosting.lua'), 'utf8');
const setup = `
MarketSync = { GetAuctionPrice = function() return 1000 end, FormatMoney = function(v) return tostring(v) end }
CreateFrame = nil
C_AuctionHouse = nil
`;
function run(script) {
  const status = lauxlib.luaL_dostring(L, to_luastring(script));
  if (status !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
run(setup + source + `
assert(MarketSync.LegacyPosting.SuggestBuyout(1000) == 999)
assert(MarketSync.LegacyPosting.SuggestBuyout(2) == 1)
assert(MarketSync.LegacyPosting.SuggestBuyout(1) == nil)
assert(MarketSync.LegacyPosting.SuggestBuyout(nil) == nil)
`);
run(`
MarketSync.GetAuctionPrice = function() return 1000 end
MarketSync.Print = function() end
AuctionFrameAuctions = { priceType = 1 }
StartPrice = {}
BuyoutPrice = {}
AuctionsStackSizeEntry = { GetNumber = function() return 5 end }
GetAuctionSellItemInfo = function() return nil,nil,nil,nil,nil,nil,nil,nil,nil,123 end
MoneyInputFrame_SetCopper = function(frame, amount) frame.value = amount end
MoneyInputFrame_GetCopper = function(frame) return frame.value or 0 end
CreateFrame = function()
  local frame = {}
  function frame:SetSize() end
  function frame:SetPoint() end
  function frame:SetText() end
  function frame:RegisterEvent() end
  function frame:SetScript(event, fn) frame[event] = fn end
  return frame
end
` + source + `
assert(MarketSync.LegacyPosting.button == nil)
-- The event watcher attaches when the legacy Auction House becomes available.
`);
// A second Lua state-free run checks the price transformation with an attached button.
run(`
MarketSync.LegacyPosting.button = nil
local oldCreate = CreateFrame
CreateFrame = function(...)
  local frame = oldCreate(...)
  if select(1, ...) == "Frame" then watcher = frame end
  return frame
end
` + source + `
watcher.OnEvent()
assert(select(10, GetAuctionSellItemInfo()) == 123, 'item ID')
assert(MarketSync.GetAuctionPrice(123) == 1000, 'market price')
assert(MarketSync.LegacyPosting.button ~= nil, 'button')
MarketSync.LegacyPosting.button.OnClick()
assert(BuyoutPrice.value == 999 and StartPrice.value == 1, tostring(BuyoutPrice.value) .. '/' .. tostring(StartPrice.value))
AuctionFrameAuctions.priceType = 2
MarketSync.LegacyPosting.button.OnClick()
assert(BuyoutPrice.value == 4995, tostring(BuyoutPrice.value))
`);
assert(source.includes('GetAuctionSellItemInfo()'));
assert(source.includes('MoneyInputFrame_SetCopper(_G.BuyoutPrice, displayPrice)'));
assert(!source.includes('StartAuction('));
console.log('PASS legacy manual undercut recommendation');
