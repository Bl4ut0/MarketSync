-- Classic Auction House grouped buying view. Prices here are live quotes, not
-- observations; scan history is written only by the Scanner tab.
MarketSync = MarketSync or {}

function MarketSync.CreateLegacySearchPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    local scanner = MarketSync.Scanner
    local selected
    local panelWidth = parent.GetWidth and parent:GetWidth() or 0
    -- Leave the right-hand gutter for the native scroll bar; result cells
    -- must fit inside the ScrollFrame viewport, not just its outer border.
    local tableWidth = math.max(1, (panelWidth > 0 and panelWidth or 900) - 80)
    local colPrice = math.floor(tableWidth * 0.47)
    local colStack = math.floor(tableWidth * 0.65)
    local colAuctions = math.floor(tableWidth * 0.76)
    local colAvailable = math.floor(tableWidth * 0.87)

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetColorTexture(0.035, 0.037, 0.042, 0.99)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -10)
    title:SetText("Search Auctions")
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
    hint:SetText("Live prices - select a row to check a stack")

    local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    search:SetHeight(24)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -31)
    search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -133, -31)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)

    local searchButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    searchButton:SetSize(98, 24)
    searchButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -31)
    searchButton:SetText("Search AH")

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -9)
    status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -64)
    status:SetJustifyH("LEFT")

    local header = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -89)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, -89)
    header:SetHeight(24)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    header:SetBackdropColor(0.12, 0.12, 0.13, 0.98)
    header:SetBackdropBorderColor(0.25, 0.25, 0.27, 0.95)
    local columns = {
        { "Item / variant", 32 }, { "Unit buyout", colPrice },
        { "Stack", colStack }, { "Auctions", colAuctions }, { "Available", colAvailable },
    }
    for _, column in ipairs(columns) do
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", header, "LEFT", column[2], 0)
        label:SetText(column[1])
    end

    local selectionBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    selectionBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 10)
    selectionBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 10)
    selectionBar:SetHeight(58)
    selectionBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    selectionBar:SetBackdropColor(0.085, 0.083, 0.077, 0.98)
    selectionBar:SetBackdropBorderColor(0.33, 0.31, 0.25, 0.95)
    local selectionTitle = selectionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectionTitle:SetPoint("TOPLEFT", selectionBar, "TOPLEFT", 12, -8)
    selectionTitle:SetText("Selected auction")
    local selectionText = selectionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectionText:SetPoint("TOPLEFT", selectionTitle, "BOTTOMLEFT", 0, -5)
    selectionText:SetPoint("TOPRIGHT", selectionBar, "TOPRIGHT", -150, -25)
    selectionText:SetJustifyH("LEFT")
    if selectionText.SetWordWrap then selectionText:SetWordWrap(false) end

    local buyButton = CreateFrame("Button", nil, selectionBar, "UIPanelButtonTemplate")
    buyButton:SetSize(128, 26)
    buyButton:SetPoint("RIGHT", selectionBar, "RIGHT", -11, 0)
    buyButton:SetText("Buy 1 Stack")

    local resultsArea = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    resultsArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    resultsArea:SetPoint("BOTTOMRIGHT", selectionBar, "TOPRIGHT", 0, 5)
    resultsArea:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    resultsArea:SetBackdropColor(0.025, 0.026, 0.03, 0.98)
    resultsArea:SetBackdropBorderColor(0.25, 0.25, 0.27, 0.95)

    local emptyOverlay = CreateFrame("Frame", nil, resultsArea)
    emptyOverlay:SetAllPoints(resultsArea)
    emptyOverlay:EnableMouse(false)
    local emptyTitle = emptyOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyTitle:SetPoint("CENTER", emptyOverlay, "CENTER", 0, 21)
    local emptyHint = emptyOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyHint:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -9)
    emptyHint:SetWidth(440)
    emptyHint:SetJustifyH("CENTER")

    local scroll = CreateFrame("ScrollFrame", nil, resultsArea, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 2, -4)
    scroll:SetPoint("BOTTOMRIGHT", resultsArea, "BOTTOMRIGHT", -23, 4)
    emptyOverlay:SetFrameLevel(scroll:GetFrameLevel() + 1)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(tableWidth, 1)
    scroll:SetScrollChild(content)
    local rowHeight, rows = 32, {}

    local function Refresh()
        if not panel:IsShown() then return end
        local results = scanner and scanner.LiveSearchResults or {}
        local disabled = scanner and scanner.IsDisabledByAuctionator and scanner.IsDisabledByAuctionator()
        searchButton:SetEnabled(not disabled and scanner and scanner.IsAvailable and scanner.IsAvailable())
        status:SetText(disabled and "Auctionator scanning is enabled. Disable it in MarketSync Settings to use Search."
            or (scanner and scanner.Status or "Open the auctioneer and search for an item."))
        if #results == 0 then
            local query = search:GetText() or ""
            if disabled then
                emptyTitle:SetText("Search is unavailable")
                emptyHint:SetText("Disable Auctionator scanning in MarketSync Settings to use this search page.")
            elseif scanner and scanner.Active then
                emptyTitle:SetText("Searching auctions...")
                emptyHint:SetText("Matching price and stack-size groups will appear here.")
            elseif query ~= "" then
                emptyTitle:SetText("No matching auctions")
                emptyHint:SetText("Nothing is listed for " .. query .. ". Try a shorter name or search again later.")
            else
                emptyTitle:SetText("Find an item to buy")
                emptyHint:SetText("Search by item name above, or choose an item from your MarketSync lists.")
            end
            emptyTitle:Show()
            emptyHint:Show()
        else
            emptyTitle:Hide()
            emptyHint:Hide()
        end
        content:SetHeight(math.max(1, #results * rowHeight))
        local first = math.floor((scroll:GetVerticalScroll() or 0) / rowHeight)
        for i, row in ipairs(rows) do
            local index = first + i
            local data = results[index]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(index - 1) * rowHeight)
            row.data = data
            if data then
                row.background:SetColorTexture(data == selected and 0.20 or (index % 2 == 0 and 0.075 or 0.045),
                    data == selected and 0.17 or (index % 2 == 0 and 0.072 or 0.043),
                    data == selected and 0.09 or (index % 2 == 0 and 0.066 or 0.04), 0.98)
                row.icon:SetTexture(data.icon or 134400)
                row.name:SetText(data.name or ("Item #" .. data.itemID))
                row.price:SetText(MarketSync.FormatMoney and MarketSync.FormatMoney(data.unitPrice) or tostring(data.unitPrice))
                row.stack:SetText(tostring(data.stackSize))
                row.auctions:SetText(tostring(data.auctions))
                row.available:SetText(tostring(data.available))
                row:Show()
            else row:Hide() end
        end
        local ready = selected and scanner and scanner.PurchaseReady
        buyButton:SetEnabled(ready and ready.row == selected and not scanner.Active
            and (type(GetMoney) ~= "function" or GetMoney() >= selected.buyout) or false)
        if selected then
            local price = MarketSync.FormatMoney and MarketSync.FormatMoney(selected.buyout) or tostring(selected.buyout) .. "c"
            selectionTitle:SetText(ready and ready.row == selected and "Stack verified - ready to buy" or "Checking selected stack")
            selectionText:SetText(string.format("%s  x%d   |cffffd100%s for this stack|r", selected.name or "Item", selected.stackSize, price))
        else
            selectionTitle:SetText("Selected auction")
            selectionText:SetText("Select a price row to verify a live stack before buying.")
        end
    end

    for i = 1, 15 do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(tableWidth - 6, rowHeight)
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints(row)
        local separator = row:CreateTexture(nil, "ARTWORK")
        separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        separator:SetHeight(1)
        separator:SetColorTexture(0.18, 0.18, 0.18, 0.65)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(colPrice - 47)
        row.name:SetJustifyH("LEFT")
        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.price:SetPoint("LEFT", row, "LEFT", colPrice - 2, 0)
        row.price:SetWidth(colStack - colPrice - 10)
        row.price:SetTextColor(1, 0.82, 0.30)
        row.stack = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.stack:SetPoint("LEFT", row, "LEFT", colStack - 2, 0)
        row.stack:SetWidth(colAuctions - colStack - 10)
        row.auctions = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.auctions:SetPoint("LEFT", row, "LEFT", colAuctions - 2, 0)
        row.auctions:SetWidth(colAvailable - colAuctions - 10)
        row.available = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.available:SetPoint("LEFT", row, "LEFT", colAvailable - 2, 0)
        row.available:SetWidth(tableWidth - colAvailable - 12)
        for _, label in ipairs({ row.name, row.price, row.stack, row.auctions, row.available }) do
            if label.SetWordWrap then label:SetWordWrap(false) end
        end
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            selected = self.data
            if scanner and scanner.PrepareLivePurchase then scanner.PrepareLivePurchase(selected) end
            Refresh()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.data or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.data.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(self.data.link)
            else GameTooltip:SetText(self.data.name or "Auction") end
            GameTooltip:AddLine("Click to check this exact stack for purchase.")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        rows[i] = row
    end

    local function Submit()
        selected = nil
        search:ClearFocus()
        if scanner and scanner.StartLiveSearch then scanner.StartLiveSearch(search:GetText()) end
        Refresh()
    end
    searchButton:SetScript("OnClick", Submit)
    search:SetScript("OnEnterPressed", Submit)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    buyButton:SetScript("OnClick", function()
        if not selected or not scanner or not scanner.PurchaseReady
            or scanner.PurchaseReady.row ~= selected then return end
        if not (StaticPopupDialogs and StaticPopup_Show) then return end
        StaticPopupDialogs.MARKETSYNC_LEGACY_BUY_STACK = {
            text = "Buy one stack of %s for %s?",
            button1 = "Buy Stack", button2 = "Cancel", timeout = 0,
            whileDead = false, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function(_, target)
                if scanner.BuyPreparedLivePurchase then scanner.BuyPreparedLivePurchase(target) end
            end,
        }
        local price = MarketSync.FormatMoney and MarketSync.FormatMoney(selected.buyout) or tostring(selected.buyout) .. "c"
        StaticPopup_Show("MARKETSYNC_LEGACY_BUY_STACK", selected.name or "Item", price, selected)
    end)

    panel.Refresh = Refresh
    panel.SearchField = search
    panel.SearchButton = searchButton
    panel.EmptyTitle = emptyTitle
    panel.EmptyHint = emptyHint
    panel.ResultRows = rows
    panel.BuyButton = buyButton
    panel.SetQuery = function(_, query)
        if type(query) == "string" then
            selected = nil
            search:SetText(query)
        end
    end
    panel:SetScript("OnShow", Refresh)
    scroll:HookScript("OnVerticalScroll", Refresh)
    if scanner and scanner.RegisterCallback then scanner.RegisterCallback(Refresh) end
    return panel
end
