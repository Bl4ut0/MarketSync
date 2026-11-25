-- Compare buyouts using recent listings from the open auction house.
local api = C_AuctionHouse
local modern = api and type(api.SendSearchQuery) == "function"
if type(CreateFrame) ~= "function" or not (StaticPopupDialogs and StaticPopup_Show) then return end
if not modern and type(GetAuctionItemInfo) ~= "function" then return end

local DIALOG = "MARKETSYNC_LOW_POST_PRICE"
local MAX_AGE = 300
local PRICE_RATIO = 0.60
local MIN_SAMPLE = 3
local openAt, browseUpdate, revision = nil, nil, 0
local updates, refreshers = {}, {}
local attached = {}

local function MarketScope()
    return (MarketSync.IsNeutralAHOpen == true
        or (MarketSync.IsNeutralAHSession and MarketSync.IsNeutralAHSession())) and "neutral" or "main"
end

local function IsRecent(at)
    return at and openAt and at >= openAt and GetTime() - at <= MAX_AGE
end

local function ItemKeyText(key)
    if not key or not key.itemID then return end
    return table.concat({key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0}, ":")
end

local function AddPrice(prices, price, weight)
    if type(price) == "number" and price > 0 and type(weight) == "number" and weight > 0 then
        prices[price] = (prices[price] or 0) + weight
    end
end

local function MedianPrice(prices)
    local values, total = {}, 0
    for price, weight in pairs(prices) do
        values[#values + 1] = price
        total = total + weight
    end
    if total < MIN_SAMPLE then return end
    table.sort(values)
    local count = 0
    for _, price in ipairs(values) do
        count = count + prices[price]
        -- With an even sample, the lower median requires a strict majority
        -- above the proposed buyout, even if prices are split in two.
        if count * 2 >= total then return price, total end
    end
end

local function ModernPrices(key, exactKey, commodity)
    local count = commodity and api.GetNumCommoditySearchResults or api.GetNumItemSearchResults
    local result = commodity and api.GetCommoditySearchResultInfo or api.GetItemSearchResultInfo
    local complete = commodity and api.HasFullCommoditySearchResults or api.HasFullItemSearchResults
    if not (count and result and complete and complete(key)) then return end
    local prices = {}
    for index = 1, count(key) do
        local row = result(key, index)
        if row and not row.containsAccountItem then
            if commodity then
                local own = row.numOwnerItems or (row.containsOwnerItem and row.quantity) or 0
                AddPrice(prices, row.unitPrice, row.quantity - own)
            elseif not row.containsOwnerItem and ItemKeyText(row.itemKey) == exactKey
                and row.buyoutAmount and row.quantity and row.quantity > 0 then
                AddPrice(prices, row.buyoutAmount / row.quantity, 1)
            end
        end
    end
    return MedianPrice(prices)
end

local function LegacyPrices(name, itemID, useSearch)
    local prices = {}
    if useSearch then
        for _, row in ipairs(MarketSync.Scanner.LiveSearchResults or {}) do
            if row.itemID == itemID and row.name == name and row.buyout and row.stackSize > 0 then
                AddPrice(prices, row.buyout / row.stackSize, row.auctions)
            end
        end
    else
        local count, total = GetNumAuctionItems("list")
        -- An ordinary Browse query can be sorted or paginated by the seller.
        -- Only use the rows if all results fit on this page.
        if not count or count ~= total or count > (NUM_AUCTION_ITEMS_PER_PAGE or 50) then return end
        local playerName = UnitName("player")
        for index = 1, count do
            local rowName, _, quantity, _, _, _, _, _, _, buyout, bid, _, _, owner, _, status, id =
                GetAuctionItemInfo("list", index)
            if rowName == name and id == itemID and quantity and quantity > 0
                and buyout and bid ~= buyout and owner ~= playerName and (not status or status == 0) then
                AddPrice(prices, buyout / quantity, 1)
            end
        end
    end
    return MedianPrice(prices)
end

local function ReadModern(frame, commodity)
    local location = frame:GetItem()
    if not location or not location:IsValid() then return end
    local exact = api.GetItemKeyFromItem(location)
    if not exact then return end
    local exactKey = ItemKeyText(exact)
    local key = commodity and exact.itemID or frame.listDisplayedItemKey or exact
    local stamp = updates[commodity and key or ItemKeyText(key)]
    local quantity = frame:GetQuantity()
    local bid, price
    if commodity then
        price = frame:GetUnitPrice()
    else
        bid, price = frame:GetPrice()
    end
    if not (IsRecent(stamp) and price and price > 0 and quantity and quantity > 0) then return end
    local guid = C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(location)
    return {
        identity = table.concat({guid or exactKey, price, bid or 0, quantity, frame:GetDuration() or 0}, ":"),
        unitPrice = commodity and price or price / quantity,
        stackPrice = not commodity and quantity > 1 and price or nil,
        stackSize = quantity,
        source = exactKey, basis = commodity and "units" or "listings",
        quote = function() return ModernPrices(key, exactKey, commodity) end,
    }
end

local function ReadLegacy()
    local name, _, _, _, _, _, _, _, _, itemID, guid = GetAuctionSellItemInfo()
    local frame = _G.AuctionFrameAuctions
    local stack = _G.AuctionsStackSizeEntry:GetNumber()
    local stacks = _G.AuctionsNumStacksEntry:GetNumber()
    local price = MoneyInputFrame_GetCopper(_G.BuyoutPrice)
    if not (name and itemID and price and price > 0 and stack and stack > 0 and stacks and stacks > 0) then return end
    local scope = MarketScope()
    local scanner = MarketSync.Scanner
    local searchAt = scanner and scanner.LiveSearchProgress and scanner.LiveSearchProgress.state == "complete"
        and scanner.LiveSearchScope == scope and scanner.LiveSearchAt
    local hasBrowse = IsRecent(browseUpdate) and not (scanner and scanner.Active)
    if not (hasBrowse or IsRecent(searchAt)) then return end
    local useSearch = IsRecent(searchAt) and (not hasBrowse or searchAt >= browseUpdate)
    return {
        identity = table.concat({guid or itemID, name, price, MoneyInputFrame_GetCopper(_G.StartPrice) or 0,
            stack, stacks, frame.priceType or 0, frame.duration or 0, scope}, ":"),
        unitPrice = frame.priceType == 1 and price or price / stack,
        stackPrice = frame.priceType ~= 1 and stack > 1 and price or nil,
        stackSize = stack,
        source = table.concat({itemID, name, scope, hasBrowse and browseUpdate or 0,
            IsRecent(searchAt) and (scanner.LiveSearchRevision or searchAt) or 0}, ":"),
        basis = "listings",
        quote = function()
            local median, total = LegacyPrices(name, itemID, useSearch)
            if not median and useSearch and hasBrowse then return LegacyPrices(name, itemID, false) end
            if not median and not useSearch and IsRecent(searchAt) then return LegacyPrices(name, itemID, true) end
            return median, total
        end,
    }
end

StaticPopupDialogs[DIALOG] = {
    text = "%s",
    button1 = "Keep Price",
    button2 = "Review Price",
    OnAccept = function(_, confirm) if confirm then confirm() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Attach(button, read)
    if not button or attached[button] then return end
    attached[button] = true
    -- Leave the native click handler and its hardware-event checks in place.
    -- Once the seller reviews the price, their next click is on Blizzard's button.
    local review = CreateFrame("Button", nil, button, "UIPanelButtonTemplate")
    review:SetAllPoints(button)
    review:SetFrameLevel(button:GetFrameLevel() + 1)
    review:SetText("Review Low Price")
    review:Hide()

    local accepted, source, quotedRevision, median, total
    local function Refresh()
        local offer = openAt and button:IsVisible() and button:IsEnabled() and read()
        if not offer or offer.identity ~= accepted then accepted = nil end
        if not offer then
            review:Hide()
            return
        end
        if offer.source ~= source or revision ~= quotedRevision then
            source, quotedRevision = offer.source, revision
            median, total = offer.quote()
        end
        local warn = accepted ~= offer.identity and median and offer.unitPrice <= median * PRICE_RATIO
        review:SetShown(not not warn)
        if warn then return offer, median, total end
    end
    review:SetScript("OnClick", function()
        local offer, reference, sampleCount = Refresh()
        if not offer then return end
        local priceText = MarketSync.FormatMoney(offer.unitPrice) .. " per item"
        if offer.stackPrice then
            local prefix = offer.unitPrice % 1 == 0 and "" or "about "
            priceText = string.format("%s per stack of %d (%s%s)",
                MarketSync.FormatMoney(offer.stackPrice), offer.stackSize, prefix, priceText)
        end
        local message = string.format(
            "Your buyout is %s. Most of the %d comparable %s are priced higher (median %s per item).\n\nA very low listing may be bait. Keep this price?",
            priceText, sampleCount, offer.basis, MarketSync.FormatMoney(reference))
        StaticPopup_Show(DIALOG, message, nil, function()
            local current = Refresh()
            if current and current.identity == offer.identity then
                accepted = offer.identity
                review:Hide()
            end
        end)
    end)
    button:HookScript("OnEnter", Refresh)
    button:HookScript("OnClick", function() accepted = nil end)
    button:HookScript("OnHide", function()
        accepted = nil
        review:Hide()
        if StaticPopup_Hide then StaticPopup_Hide(DIALOG) end
    end)
    refreshers[#refreshers + 1] = Refresh
end

local function AttachLegacy()
    local frame = _G.AuctionFrameAuctions
    if not (frame and type(GetAuctionSellItemInfo) == "function" and type(MoneyInputFrame_GetCopper) == "function"
        and _G.StartPrice and _G.BuyoutPrice and _G.AuctionsStackSizeEntry and _G.AuctionsNumStacksEntry) then return end
    Attach(_G.AuctionsCreateAuctionButton, ReadLegacy)
    local scanner = MarketSync.Scanner
    if not (scanner and scanner.StartLiveSearch and MarketSync.Print) or frame.MarketSyncCheckPrice then return end
    local check = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    check:SetSize(82, 20)
    check:SetPoint("TOPLEFT", frame, "TOPLEFT", 23, -73)
    check:SetText("Check Price")
    check:SetScript("OnClick", function()
        local name, _, _, _, _, _, _, _, _, itemID = GetAuctionSellItemInfo()
        if not name or not itemID then return end
        if scanner.Active then
            MarketSync.Print("Wait for the current auction scan to finish before checking this item.")
        elseif not scanner.StartLiveSearch({{ name = name, itemID = itemID }}) then
            MarketSync.Print(scanner.Status)
        end
    end)
    frame.MarketSyncCheckPrice = check
    refreshers[#refreshers + 1] = function()
        check:SetShown(openAt ~= nil and frame:IsVisible() and GetAuctionSellItemInfo() ~= nil)
        check:SetText(scanner.Active and "Scanning..." or "Check Price")
    end
end

local function AttachModern()
    local frame = _G.AuctionHouseFrame
    if not (frame and api.GetItemKeyFromItem) then return end
    local item, commodity = frame.ItemSellFrame, frame.CommoditiesSellFrame
    if item and item.GetPrice then
        Attach(item.PostButton, function() return ReadModern(item, false) end)
    end
    if commodity and commodity.GetUnitPrice then
        Attach(commodity.PostButton, function() return ReadModern(commodity, true) end)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("AUCTION_HOUSE_SHOW")
watcher:RegisterEvent("AUCTION_HOUSE_CLOSED")
if modern then
    watcher:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
    watcher:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    watcher:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
    watcher:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
else
    watcher:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end
local elapsed = 0
local function OnUpdate(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.2 then return end
    elapsed = 0
    for _, refresh in ipairs(refreshers) do refresh() end
end
watcher:SetScript("OnEvent", function(self, event, key)
    if event == "AUCTION_HOUSE_SHOW" then
        openAt = GetTime()
        if modern then AttachModern() else AttachLegacy() end
        self:SetScript("OnUpdate", OnUpdate)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        openAt, browseUpdate, updates = nil, nil, {}
        revision = revision + 1
        for _, refresh in ipairs(refreshers) do refresh() end
        self:SetScript("OnUpdate", nil)
    elseif openAt then
        if event == "AUCTION_ITEM_LIST_UPDATE" then
            browseUpdate = GetTime()
        else
            local identity = type(key) == "table" and ItemKeyText(key) or key
            if identity then updates[identity] = GetTime() end
        end
        revision = revision + 1
    end
end)
