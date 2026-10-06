-- Live, grouped Auction House search for the classic-family UI.
MarketSync = MarketSync or {}

function MarketSync.CreateLegacySearchPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    local scanner = MarketSync.Scanner
    local search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    search:SetSize(300, 24)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -18)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(88, 22)
    button:SetPoint("LEFT", search, "RIGHT", 12, 0)
    button:SetText("Search AH")
    local function Submit()
        search:ClearFocus()
        if scanner and scanner.StartLiveSearch then scanner.StartLiveSearch(search:GetText()) end
    end
    button:SetScript("OnClick", Submit)
    search:SetScript("OnEnterPressed", Submit)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -12)
    status:SetPoint("RIGHT", panel, "RIGHT", -22, 0)
    status:SetJustifyH("LEFT")

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -12)
    header:SetText("Item / variant                         Unit buyout       Stack       Auctions       Available")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -38, 20)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(700, 1)
    scroll:SetScrollChild(content)
    local rowHeight, rowCount, rows = 27, 17, {}
    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(rowHeight)
        row:SetPoint("LEFT", content, "LEFT", 4, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.name:SetWidth(300)
        row.name:SetJustifyH("LEFT")
        row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.price:SetPoint("LEFT", row.name, "RIGHT", 7, 0)
        row.price:SetWidth(90)
        row.stack = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.stack:SetPoint("LEFT", row.price, "RIGHT", 8, 0)
        row.stack:SetWidth(60)
        row.auctions = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.auctions:SetPoint("LEFT", row.stack, "RIGHT", 8, 0)
        row.auctions:SetWidth(60)
        row.available = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.available:SetPoint("LEFT", row.auctions, "RIGHT", 8, 0)
        row.available:SetWidth(65)
        row:SetScript("OnEnter", function(self)
            if not self.data or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.data.link and GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink(self.data.link)
            else
                GameTooltip:SetText(self.data.name or "Auction")
            end
            GameTooltip:AddLine("Exact stack buyout: " .. (MarketSync.FormatMoney and MarketSync.FormatMoney(self.data.buyout) or tostring(self.data.buyout)))
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        rows[i] = row
    end

    local function Refresh()
        if not panel:IsShown() then return end
        local results = scanner and scanner.LiveSearchResults or {}
        local disabled = scanner and scanner.IsDisabledByAuctionator and scanner.IsDisabledByAuctionator()
        button:SetEnabled(not disabled and scanner and scanner.IsAvailable and scanner.IsAvailable())
        status:SetText(disabled and "Auctionator owns live scanning. Disable Auctionator scanning in MarketSync Settings to use this page."
            or (scanner and scanner.Status or "Open the auctioneer and enter an item name."))
        content:SetHeight(math.max(1, #results * rowHeight))
        local first = math.floor((scroll:GetVerticalScroll() or 0) / rowHeight)
        for i, row in ipairs(rows) do
            local index = first + i
            local data = results[index]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(index - 1) * rowHeight)
            row:SetPoint("RIGHT", content, "RIGHT", -4, 0)
            row.data = data
            if data then
                row.icon:SetTexture(data.icon or 134400)
                row.name:SetText(data.name or ("Item #" .. data.itemID))
                row.price:SetText(MarketSync.FormatMoney and MarketSync.FormatMoney(data.unitPrice) or tostring(data.unitPrice))
                row.stack:SetText(tostring(data.stackSize))
                row.auctions:SetText(tostring(data.auctions))
                row.available:SetText(tostring(data.available))
                row:Show()
            else row:Hide() end
        end
    end
    panel.Refresh = Refresh
    panel.SetQuery = function(_, query)
        if type(query) == "string" then search:SetText(query) end
    end
    panel:SetScript("OnShow", Refresh)
    scroll:HookScript("OnVerticalScroll", Refresh)
    if scanner and scanner.RegisterCallback then scanner.RegisterCallback(Refresh) end
    return panel
end
