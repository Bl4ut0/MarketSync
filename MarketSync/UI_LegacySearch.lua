-- Classic Auction House grouped buying view. Prices here are live quotes, not
-- observations; scan history is written only by the Scanner tab.
MarketSync = MarketSync or {}

function MarketSync.CreateLegacySearchPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    local scanner = MarketSync.Scanner
    local selected

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetColorTexture(0.045, 0.048, 0.055, 0.99)

    local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    search:SetSize(390, 24)
    search:SetPoint("TOPLEFT", 22, -16)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)

    local searchButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    searchButton:SetSize(92, 22)
    searchButton:SetPoint("LEFT", search, "RIGHT", 12, 0)
    searchButton:SetText("Search")

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    status:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    status:SetJustifyH("LEFT")

    local header = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    header:SetPoint("TOPLEFT", status, "BOTTOMLEFT", -4, -8)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -28, 0)
    header:SetHeight(22)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    header:SetBackdropColor(0.12, 0.13, 0.15, 0.98)
    local columns = {
        { "Item / variant", 34 }, { "Unit buyout", 338 },
        { "Stack", 446 }, { "Auctions", 509 }, { "Available", 572 },
    }
    for _, column in ipairs(columns) do
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", header, "LEFT", column[2], 0)
        label:SetText(column[1])
    end

    local selectionBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    selectionBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 8)
    selectionBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 8)
    selectionBar:SetHeight(44)
    selectionBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    selectionBar:SetBackdropColor(0.07, 0.08, 0.09, 0.98)
    selectionBar:SetBackdropBorderColor(0.31, 0.32, 0.34, 0.95)
    local selectionText = selectionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectionText:SetPoint("LEFT", 12, 0)
    selectionText:SetPoint("RIGHT", -145, 0)
    selectionText:SetJustifyH("LEFT")

    local buyButton = CreateFrame("Button", nil, selectionBar, "UIPanelButtonTemplate")
    buyButton:SetSize(124, 24)
    buyButton:SetPoint("RIGHT", -10, 0)
    buyButton:SetText("Buy 1 Stack")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    scroll:SetPoint("BOTTOMRIGHT", selectionBar, "TOPRIGHT", -15, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(730, 1)
    scroll:SetScrollChild(content)
    local rowHeight, rows = 27, {}

    local function Refresh()
        if not panel:IsShown() then return end
        local results = scanner and scanner.LiveSearchResults or {}
        local disabled = scanner and scanner.IsDisabledByAuctionator and scanner.IsDisabledByAuctionator()
        searchButton:SetEnabled(not disabled and scanner and scanner.IsAvailable and scanner.IsAvailable())
        status:SetText(disabled and "Auctionator scanning is enabled. Disable it in MarketSync Settings to use Search."
            or (scanner and scanner.Status or "Open the auctioneer and search for an item."))
        content:SetHeight(math.max(1, #results * rowHeight))
        local first = math.floor((scroll:GetVerticalScroll() or 0) / rowHeight)
        for i, row in ipairs(rows) do
            local index = first + i
            local data = results[index]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(index - 1) * rowHeight)
            row.data = data
            if data then
                row.background:SetColorTexture(data == selected and 0.18 or 0.07,
                    data == selected and 0.21 or 0.08, data == selected and 0.24 or 0.09, 0.95)
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
            selectionText:SetText(string.format("%s  x%d   |cffffd100%s per stack|r", selected.name or "Item", selected.stackSize, price))
        else
            selectionText:SetText("Select a price row to check a live stack before buying.")
        end
    end

    for i = 1, 15 do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(710, rowHeight)
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints(row)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 3, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.name:SetWidth(290)
        row.name:SetJustifyH("LEFT")
        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.price:SetPoint("LEFT", row.name, "RIGHT", 7, 0)
        row.price:SetWidth(100)
        row.stack = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.stack:SetPoint("LEFT", row.price, "RIGHT", 8, 0)
        row.stack:SetWidth(55)
        row.auctions = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.auctions:SetPoint("LEFT", row.stack, "RIGHT", 8, 0)
        row.auctions:SetWidth(55)
        row.available = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.available:SetPoint("LEFT", row.auctions, "RIGHT", 8, 0)
        row.available:SetWidth(75)
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
