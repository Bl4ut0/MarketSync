const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const source = fs.readFileSync(path.join(__dirname, '../MarketSync/PostingWarning.lua'), 'utf8');
const setup = `
local frames = {}
function CreateFrame(kind, _, parent)
    local frame = { kind = kind, parent = parent, scripts = {}, events = {}, shown = true, enabled = true }
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:IsEnabled() return self.enabled end
    function frame:SetShown(shown) self.shown = shown end
    function frame:Hide() self.shown = false end
    function frame:GetFrameLevel() return 10 end
    function frame:SetFrameLevel() end
    function frame:SetAllPoints() end
    function frame:SetPoint() end
    function frame:SetSize() end
    function frame:SetText(text) self.text = text end
    function frame:RegisterEvent(event)
        assert(event ~= "NEW_AUCTION_UPDATE")
        self.events[event] = true
    end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:HookScript(event, fn)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end
    frames[#frames + 1] = frame
    return frame
end
function FindFrame(label, parent)
    for _, frame in ipairs(frames) do
        if frame.text == label and frame.parent == parent then return frame end
    end
    error("Couldn't find " .. label)
end
function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
    end
end
function Tick()
    for _, frame in ipairs(frames) do
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.25) end
    end
end
now = 10
function GetTime() return now end
MarketSync = {
    FormatMoney = function(copper) return tostring(math.floor(copper + 0.5)) .. "c" end,
    Print = function() end,
}
StaticPopupDialogs = {}
function StaticPopup_Show(key, text, _, accept) popup = {key = key, text = text, accept = accept} end
function StaticPopup_Hide() popup = nil end
function Accept() StaticPopupDialogs[popup.key].OnAccept(nil, popup.accept) end
function NativeButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetScript("OnClick", function() posted = (posted or 0) + 1 end)
    return button
end
`;

function run(label, client, checks) {
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  try {
    const status = lauxlib.luaL_dostring(state, to_luastring([setup, client, source, checks].join('\n')));
    if (status !== lua.LUA_OK) throw new Error(`${label}: ${lua.lua_tojsstring(state, -1)}`);
    console.log(`PASS ${label}`);
  } finally {
    lua.lua_close(state);
  }
}

run('legacy posting warning uses full results and compares unit prices', `
AuctionFrameAuctions = CreateFrame("Frame")
AuctionFrameAuctions.priceType = 2
AuctionsCreateAuctionButton = NativeButton(AuctionFrameAuctions)
stackSize, numStacks = 5, 1
AuctionsStackSizeEntry = { GetNumber = function() return stackSize end }
AuctionsNumStacksEntry = { GetNumber = function() return numStacks end }
StartPrice, BuyoutPrice = { value = 1 }, { value = 500 }
function MoneyInputFrame_GetCopper(frame) return frame.value end
function GetAuctionSellItemInfo() return "Test Ore", nil,nil,nil,nil,nil,nil,nil,nil,100,"GUID" end
function UnitName() return "Seller" end
MarketSync.Scanner = {StartLiveSearch = function(items) searched = items[1]; return true end}
-- The first listing is one unit. The other sellers use different stack sizes.
listings = {{1,100}, {5,5000}, {10,10100}, {1,500}, {1,300}, {1,1}}
function GetNumAuctionItems() return #listings, resultCount or #listings end
function GetAuctionItemInfo(_, index)
    local row = listings[index]
    return index == 4 and "Test Ore of Power" or "Test Ore", nil, row[1], nil,nil,nil,nil,nil,nil,
        row[2], 0, nil,nil, index == 5 and "Seller" or "Other", nil, index == 6 and 1 or 0, 100
end
`, `
Fire("AUCTION_HOUSE_SHOW")
local button = AuctionsCreateAuctionButton
local review = FindFrame("Review Low Price", button)
Tick()
assert(not review.shown)
FindFrame("Check Price", AuctionFrameAuctions).scripts.OnClick()
assert(searched.itemID == 100 and searched.name == "Test Ore")
resultCount = 60
Fire("AUCTION_ITEM_LIST_UPDATE")
Tick()
assert(not review.shown, "a single page must not count as the whole market")
resultCount = nil
Fire("AUCTION_ITEM_LIST_UPDATE")
Tick()
assert(review.shown)
review.scripts.OnClick()
assert(popup.text:find("100c per item", 1, true))
assert(popup.text:find("500c per stack of 5", 1, true))
assert(popup.text:find("3 comparable listings", 1, true))
assert(popup.text:find("median 1000c", 1, true))
assert(not posted)
numStacks = 2
Accept()
assert(review.shown, "changed stack count must require a new review")
review.scripts.OnClick()
Accept()
assert(not review.shown and not posted)
button.scripts.OnClick(button)
assert(posted == 1, "native OnClick still posts in response to the seller's separate click")
AuctionFrameAuctions.priceType = 1
BuyoutPrice.value = 900
Tick()
assert(not review.shown, "normal undercuts should not prompt")
BuyoutPrice.value = 400
Tick()
assert(review.shown)
table.insert(listings, {1,400})
Fire("AUCTION_ITEM_LIST_UPDATE")
Tick()
assert(not review.shown, "a market split evenly at the proposed price is not a majority")
table.remove(listings)
Fire("AUCTION_ITEM_LIST_UPDATE")
Tick()
assert(review.shown)
now = 311
Tick()
assert(not review.shown, "stale browse data cannot prompt")

local s = MarketSync.Scanner
s.LiveSearchAt = now
s.LiveSearchScope = "main"
s.LiveSearchProgress = {state = "complete"}
s.LiveSearchResults = {
    {itemID = 100, name = "Test Ore", buyout = 100, stackSize = 1, auctions = 1},
    {itemID = 100, name = "Test Ore", buyout = 5000, stackSize = 5, auctions = 3},
}
Tick()
assert(review.shown, "a completed scanner check can be used after leaving Browse")
review.scripts.OnClick()
assert(popup.text:find("4 comparable listings", 1, true))
MarketSync.IsNeutralAHOpen = true
Tick()
assert(not review.shown, "main and neutral auction data must stay separate")
MarketSync.IsNeutralAHOpen = false
Fire("AUCTION_HOUSE_CLOSED")
assert(not review.shown)
now = 312
Fire("AUCTION_HOUSE_SHOW")
Tick()
assert(not review.shown, "the previous auction house session cannot supply a new warning")
`);

run('modern posting warning uses matching item variants and commodity quantities', `
local itemKey = { itemID = 10, itemLevel = 55, itemSuffix = -2 }
itemQuery = { itemID = 10 }
local wrongVariant = { itemID = 10, itemLevel = 55, itemSuffix = 5 }
local commodityKey = { itemID = 11 }
function SellFrame(key)
    local frame = CreateFrame("Frame")
    frame.GetItem = function() return { key = key, IsValid = function() return true end } end
    frame.GetDuration = function() return 2 end
    frame.GetQuantity = function() return frame.quantity or 1 end
    frame.GetPrice = function() return nil, frame.price end
    frame.GetUnitPrice = function() return frame.price end
    frame.PostButton = NativeButton(frame)
    return frame
end
item = SellFrame(itemKey)
item.listDisplayedItemKey = itemQuery
item.price, item.quantity = 200, 2
commodity = SellFrame(commodityKey)
commodity.price, commodity.quantity = 40, 20
AuctionHouseFrame = { ItemSellFrame = item, CommoditiesSellFrame = commodity }
local itemRows = {
    { itemKey = itemKey, buyoutAmount = 100, quantity = 1 },
    { itemKey = itemKey, buyoutAmount = 1000, quantity = 1 },
    { itemKey = itemKey, buyoutAmount = 4000, quantity = 4 },
    { itemKey = wrongVariant, buyoutAmount = 1, quantity = 1 },
    { itemKey = itemKey, buyoutAmount = 1, quantity = 1, containsAccountItem = true },
}
local tiers = { {unitPrice = 40, quantity = 1}, {unitPrice = 100, quantity = 10} }
itemResultsComplete = false
C_AuctionHouse = {
    SendSearchQuery = function() error("the modern sell guard must not issue queries") end,
    GetItemKeyFromItem = function(location) return location.key end,
    GetNumItemSearchResults = function(key) assert(key == itemQuery); return #itemRows end,
    GetItemSearchResultInfo = function(_, index) return itemRows[index] end,
    HasFullItemSearchResults = function() return itemResultsComplete end,
    GetNumCommoditySearchResults = function(id) assert(id == 11); return #tiers end,
    GetCommoditySearchResultInfo = function(_,index) return tiers[index] end,
    HasFullCommoditySearchResults = function() return true end,
}
`, `
Fire("AUCTION_HOUSE_SHOW")
local itemReview = FindFrame("Review Low Price", item.PostButton)
local commodityReview = FindFrame("Review Low Price", commodity.PostButton)
Fire("ITEM_SEARCH_RESULTS_UPDATED", itemQuery)
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 11)
Tick()
assert(not itemReview.shown and commodityReview.shown)
commodityReview.scripts.OnClick()
assert(popup.text:find("11 comparable units", 1, true))
assert(popup.text:find("40c per item", 1, true))
Accept()
assert(not commodityReview.shown and not posted)
commodity.price = 35
Tick()
assert(commodityReview.shown, "changed price needs review")

itemResultsComplete = true
Fire("ITEM_SEARCH_RESULTS_ADDED", itemQuery)
Tick()
assert(itemReview.shown)
itemReview.scripts.OnClick()
assert(popup.text:find("3 comparable listings", 1, true))
assert(popup.text:find("1000c per item", 1, true))
item.price = 2000
item.PostButton.scripts.OnEnter(item.PostButton)
assert(not itemReview.shown, "normal posting button is available at the revised price")
`);
