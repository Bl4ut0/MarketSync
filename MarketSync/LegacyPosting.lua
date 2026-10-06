-- Classic-family Auction House price suggestion. Never posts an auction.
MarketSync = MarketSync or {}
MarketSync.LegacyPosting = MarketSync.LegacyPosting or {}
local Posting = MarketSync.LegacyPosting

function Posting.SuggestBuyout(marketPrice)
    local price = tonumber(marketPrice)
    if not price or price < 2 then return nil end
    return math.max(1, math.floor(price) - 1)
end

local function HasLegacySellFrame()
    return type(GetAuctionSellItemInfo) == "function"
        and type(MoneyInputFrame_SetCopper) == "function"
        and _G.AuctionFrameAuctions ~= nil
        and _G.StartPrice ~= nil
        and _G.BuyoutPrice ~= nil
        and not (C_AuctionHouse and type(C_AuctionHouse.SendSearchQuery) == "function")
end

local function ApplySuggestion()
    if not HasLegacySellFrame() then return end
    -- A neutral auction must not use the main-AH price database.
    if MarketSync.IsNeutralAHOpen == true
        or (MarketSync.IsNeutralAHSession and MarketSync.IsNeutralAHSession()) then
        if MarketSync.Print then MarketSync.Print("Neutral AH: no main-market undercut suggestion applied.") end
        return
    end
    local itemID = select(10, GetAuctionSellItemInfo())
    if not itemID then return end
    local marketPrice = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(itemID)
    local suggested = Posting.SuggestBuyout(marketPrice)
    if not suggested then
        if MarketSync.Print then MarketSync.Print("No usable market price for this item yet.") end
        return
    end
    -- The old AH can edit either per-unit or per-stack prices. Scanner prices
    -- are always per unit, so convert only in the stack-price mode.
    local displayPrice = suggested
    if _G.AuctionFrameAuctions.priceType ~= 1 and _G.AuctionsStackSizeEntry
        and _G.AuctionsStackSizeEntry.GetNumber then
        displayPrice = suggested * math.max(1, _G.AuctionsStackSizeEntry:GetNumber() or 1)
    end
    MoneyInputFrame_SetCopper(_G.BuyoutPrice, displayPrice)
    local startPrice = type(MoneyInputFrame_GetCopper) == "function"
        and MoneyInputFrame_GetCopper(_G.StartPrice) or 0
    if startPrice < 1 or startPrice > displayPrice then
        MoneyInputFrame_SetCopper(_G.StartPrice, math.min(displayPrice, math.max(1, startPrice)))
    end
    if MarketSync.Print then
        MarketSync.Print("Suggested buyout set to " .. (MarketSync.FormatMoney and MarketSync.FormatMoney(displayPrice) or tostring(displayPrice) .. "c") .. ". Review before posting, especially for item variants.")
    end
end

local function Attach()
    if Posting.button or not HasLegacySellFrame() then return end
    local button = CreateFrame("Button", "MarketSyncLegacyUndercutButton", _G.AuctionFrameAuctions, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPRIGHT", _G.AuctionFrameAuctions, "TOPRIGHT", -20, -35)
    button:SetText("Undercut 1c/unit")
    button:SetScript("OnClick", ApplySuggestion)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Set the buyout 1 copper below MarketSync's last observed price. Review it before posting.")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Posting.button = button
end

if type(CreateFrame) == "function" then
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("AUCTION_HOUSE_SHOW")
    watcher:SetScript("OnEvent", Attach)
end
