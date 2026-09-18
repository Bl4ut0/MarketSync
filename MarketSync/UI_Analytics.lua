-- =============================================================
-- MarketSync - Analytics & Historiography Panel
-- Detailed breakdown of status, trends, and data sources
-- Matches Blizzard Auction House sleek dark metallic slate design
-- =============================================================

MarketSync = MarketSync or {}

local registeredPanels = {}

local function SafeGetItemInfo(idOrLink)
    if not idOrLink then return nil end
    if MarketSync and MarketSync.SafeGetItemInfo then
        return MarketSync.SafeGetItemInfo(idOrLink)
    end
    if C_Item and C_Item.GetItemInfo then
        local res = { pcall(C_Item.GetItemInfo, idOrLink) }
        if res[1] and res[2] then return select(2, unpack(res)) end
    end
    if GetItemInfo then
        local res = { pcall(GetItemInfo, idOrLink) }
        if res[1] and res[2] then return select(2, unpack(res)) end
    end
    return nil
end

local function FormatMoneyPlain(copper)
    if not copper or copper == 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return g .. "g" .. (s > 0 and (" " .. s .. "s") or "") end
    if s > 0 then return s .. "s" .. (c > 0 and (" " .. c .. "c") or "") end
    return c .. "c"
end

local function FormatMoney(copper)
    if not copper or copper == 0 then return "|cff888888N/A|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local str = ""
    if g > 0 then str = str .. "|cffffd700" .. g .. "|r|cffffd700g|r " end
    if s > 0 or g > 0 then str = str .. "|cffc0c0c0" .. s .. "|r|cffc0c0c0s|r " end
    str = str .. "|cffeda55f" .. c .. "|r|cffeda55fc|r"
    return str
end

local function ScanDayToDate(scanDay)
    if MarketSync and MarketSync.ScanDayToDate then
        return MarketSync.ScanDayToDate(scanDay)
    end
    local day = tonumber(scanDay) or 0
    if day > 10000 then
        return date("%b %d", day * 86400)
    end
    local scan0 = (Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0)
        or (MarketSync and MarketSync.SCAN_DAY_0)
        or 1577836800
    local timestamp = scan0 + (day * 86400)
    return date("%b %d", timestamp)
end

local function ResolveItem(input)
    if not input then return nil end
    local itemID = tonumber(input)
    if not itemID and type(input) == "string" then
        local linkID = input:match("item:(%d+)")
        if linkID then
            itemID = tonumber(linkID)
        end
    end

    local name, link, quality, icon
    if itemID then
        name, link, quality, _, _, _, _, _, _, icon = SafeGetItemInfo(itemID)
        if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
            local c = MarketSyncDB.ItemInfoCache[itemID]
            name = c.n
            icon = c.ic
            quality = c.r
            link = "item:" .. itemID
        end
    else
        name = input
        if MarketSyncDB and MarketSyncDB.ItemInfoCache then
            local lowerInput = input:lower()
            for id, c in pairs(MarketSyncDB.ItemInfoCache) do
                if c.n and c.n:lower() == lowerInput then
                    itemID = id
                    name = c.n
                    icon = c.ic
                    quality = c.r
                    link = "item:" .. id
                    break
                end
            end
        end
        if not itemID then
            local n, l, q, _, _, _, _, _, _, ic = SafeGetItemInfo(input)
            if n then
                name = n
                link = l
                quality = q
                icon = ic
                local foundID = l and l:match("item:(%d+)")
                if foundID then itemID = tonumber(foundID) end
            end
        end
    end

    if not itemID and not name then return nil end
    local dbKey = itemID and tostring(itemID) or input
    local price = 0
    if itemID and MarketSync.GetAuctionPrice then
        price = MarketSync.GetAuctionPrice(itemID) or 0
    end

    return {
        dbKey = dbKey,
        itemID = itemID,
        itemLink = link,
        name = name or ("Item #" .. tostring(itemID)),
        icon = icon or 134400,
        quality = quality or 1,
        price = price,
    }
end

-- ================================================================
-- GRAPH RENDERER
-- Dynamic width/height historical price chart
-- ================================================================
local function CreateGraph(parent)
    local graph = CreateFrame("Frame", nil, parent)
    graph.lines = {}
    graph.dots = {}
    graph.gridLines = {}
    graph.labels = {}
    graph.plotWidth = 500
    graph.plotHeight = 180

    local bg = graph:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetColorTexture(0, 0, 0, 0.40)
    bg:SetAllPoints()

    graph.lineCursor = 0
    graph.dotCursor = 0
    graph.gridCursor = 0
    graph.labelCursor = 0

    function graph:Clear()
        for _, line in ipairs(self.lines) do line:Hide() end
        for _, dot in ipairs(self.dots) do dot:Hide() end
        for _, gl in ipairs(self.gridLines) do gl:Hide() end
        for _, lbl in ipairs(self.labels) do lbl:Hide() end
        self.lineCursor = 0
        self.dotCursor = 0
        self.gridCursor = 0
        self.labelCursor = 0
    end

    function graph:DrawLine(x1, y1, x2, y2, r, g, b, a, thickness)
        self.lineCursor = self.lineCursor + 1
        local line = self.lines[self.lineCursor]
        if not line then
            line = self:CreateLine(nil, "ARTWORK")
            table.insert(self.lines, line)
        end
        line:SetThickness(thickness or 2)
        line:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
        line:SetStartPoint("BOTTOMLEFT", x1, y1)
        line:SetEndPoint("BOTTOMLEFT", x2, y2)
        line:Show()
    end

    function graph:DrawDot(x, y, r, g, b, size)
        self.dotCursor = self.dotCursor + 1
        local dot = self.dots[self.dotCursor]
        if not dot then
            dot = self:CreateTexture(nil, "OVERLAY")
            table.insert(self.dots, dot)
        end
        local s = size or 5
        dot:SetSize(s, s)
        dot:SetColorTexture(r or 1, g or 1, b or 1, 1)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
        dot:Show()
    end

    function graph:DrawGridLine(y)
        self.gridCursor = self.gridCursor + 1
        local gl = self.gridLines[self.gridCursor]
        if not gl then
            gl = self:CreateTexture(nil, "BACKGROUND", nil, 3)
            table.insert(self.gridLines, gl)
        end
        gl:SetColorTexture(0.5, 0.5, 0.5, 0.15)
        gl:SetSize(math.max(10, self.plotWidth - 2), 1)
        gl:ClearAllPoints()
        gl:SetPoint("LEFT", self, "BOTTOMLEFT", 1, y)
        gl:Show()
    end

    function graph:AddLabel(x, y, text, anchor)
        self.labelCursor = self.labelCursor + 1
        local lbl = self.labels[self.labelCursor]
        if not lbl then
            lbl = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
            table.insert(self.labels, lbl)
        end
        lbl:ClearAllPoints()
        lbl:SetPoint(anchor or "TOP", self, "BOTTOMLEFT", x, y)
        lbl:SetText(text)
        lbl:Show()
    end

    function graph:Plot(history)
        self:Clear()
        local curW = self:GetWidth()
        local curH = self:GetHeight()
        if curW and curW > 100 then self.plotWidth = curW end
        if curH and curH > 60 then self.plotHeight = curH end

        if not history or #history == 0 then
            self:AddLabel(self.plotWidth / 2, self.plotHeight / 2, "|cFF888888Insufficient historical scan data|r", "CENTER")
            return
        end

        if #history == 1 then
            local d = history[1]
            local pw = self.plotWidth - 55
            local ph = self.plotHeight - 40
            local ox, oy = 50, 25
            local y = oy + (ph / 2)
            self:DrawGridLine(y)
            self:AddLabel(ox - 5, y, FormatMoneyPlain(d.price), "RIGHT")
            local x = ox + (pw / 2)
            self:DrawDot(x, y, 0.3, 1, 0.3, 7)
            local label = ScanDayToDate(d.day) .. (d.timeLabel and ("\n" .. d.timeLabel) or "")
            self:AddLabel(x, oy - 12, label, "TOP")
            return
        end

        local plotData = {}
        local maxPoints = math.min(#history, 48)
        for i = maxPoints, 1, -1 do
            table.insert(plotData, history[i])
        end

        local minPrice, maxPrice = math.huge, 0
        for _, d in ipairs(plotData) do
            if d.price > maxPrice then maxPrice = d.price end
            if d.price < minPrice then minPrice = d.price end
        end
        if minPrice == maxPrice then maxPrice = maxPrice + 100 end

        local range = maxPrice - minPrice
        local padMin = math.max(0, minPrice - (range * 0.15))
        local padMax = maxPrice + (range * 0.15)
        local fullRange = padMax - padMin

        local pw = self.plotWidth - 55
        local ph = self.plotHeight - 40
        local ox, oy = 50, 25

        -- Y-axis grid & labels (5 tiers)
        for i = 0, 4 do
            local f = i / 4
            local y = oy + (f * ph)
            self:DrawGridLine(y)
            self:AddLabel(ox - 5, y, FormatMoneyPlain(padMin + (f * fullRange)), "RIGHT")
        end

        local spacing = pw / (#plotData - 1)
        local px, py
        for i, d in ipairs(plotData) do
            local x = ox + ((i - 1) * spacing)
            local y = oy + (((d.price - padMin) / fullRange) * ph)
            if px then self:DrawLine(px, py, x, y, 0.2, 0.8, 0.2, 1, 2) end

            if d.isGranular then
                self:DrawDot(x, y, 0.2, 0.7, 1.0, 5)
            else
                self:DrawDot(x, y, 0.3, 1, 0.3, 6)
            end

            if i == 1 or i == #plotData or (i % math.max(1, math.floor(#plotData / 6)) == 0) then
                if d.isGranular and d.timeLabel then
                    self:AddLabel(x, oy - 12, ScanDayToDate(d.day) .. "\n" .. d.timeLabel, "TOP")
                else
                    self:AddLabel(x, oy - 12, ScanDayToDate(d.day), "TOP")
                end
            end
            px, py = x, y
        end
    end

    return graph
end

-- ================================================================
-- ANALYTICS PANEL CONSTRUCTOR
-- ================================================================
function MarketSync.CreateAnalyticsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    -- Left Inset: Search, Item Drop & List of Recent/Tracked Items (240px)
    local leftInset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(panel, 6, -6, 240, nil)
    if not leftInset then
        leftInset = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        leftInset:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
        leftInset:SetWidth(240)
    end
    leftInset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    leftInset:SetWidth(240)

    -- Right Inset: Detail Banner, Historical Graph & Intraday Metrics
    local rightInset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(panel)
    if not rightInset then
        rightInset = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    end
    rightInset:SetPoint("TOPLEFT", leftInset, "TOPRIGHT", 6, 0)
    rightInset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)

    -- ================================================================
    -- LEFT INSET: ITEM SELECTION & QUICK SEARCH
    -- ================================================================
    local leftHeader = CreateFrame("Frame", nil, leftInset)
    leftHeader:SetPoint("TOPLEFT", 6, -6)
    leftHeader:SetPoint("TOPRIGHT", -6, -6)
    leftHeader:SetHeight(26)

    local listTitle = leftHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    listTitle:SetPoint("LEFT", 4, 0)
    listTitle:SetText("|cFFFFD100Scanned Items|r")

    -- Mode Switcher: [ Recent ] [ Favorites ]
    local recentBtn = CreateFrame("Button", nil, leftHeader, "UIPanelButtonTemplate")
    recentBtn:SetSize(62, 20)
    recentBtn:SetPoint("RIGHT", -66, 0)
    recentBtn:SetText("Recent")

    local favBtn = CreateFrame("Button", nil, leftHeader, "UIPanelButtonTemplate")
    favBtn:SetSize(64, 20)
    favBtn:SetPoint("RIGHT", 0, 0)
    favBtn:SetText("Favorites")

    -- Quick Search & Drop EditBox
    local searchBox = CreateFrame("EditBox", nil, leftInset, "InputBoxTemplate")
    searchBox:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 4, -6)
    searchBox:SetPoint("TOPRIGHT", leftHeader, "BOTTOMRIGHT", -4, -6)
    searchBox:SetHeight(20)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetText("Drop item or enter name/ID...")

    searchBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Drop item or enter name/ID..." then self:SetText("") end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Drop item or enter name/ID...") end
    end)

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(recentBtn, {
            name = "Recent Items",
            context = "Button",
            description = "Show recently scanned items list",
        })
        MarketSync.SetAccessibility(favBtn, {
            name = "Favorite Items",
            context = "Button",
            description = "Show favorite items list",
        })
        MarketSync.SetAccessibility(searchBox, {
            name = "Search Analytics",
            context = "Edit Box",
            description = "Drop item or enter name or ID to view analytics",
        })
    end

    local currentMode = "recent"
    local selectedDBKey = nil
    local itemsList = {}
    local itemRows = {}
    local rowH = 24

    local function HandleItemDrop()
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and (itemID or itemLink) then
            ClearCursor()
            local itemInfo = ResolveItem(itemID or itemLink)
            if itemInfo then
                panel:ShowItem(itemInfo.dbKey, itemInfo.itemLink, itemInfo.name, itemInfo.icon, itemInfo.price)
            end
            return true
        end
        return false
    end

    searchBox:SetScript("OnReceiveDrag", HandleItemDrop)
    searchBox:SetScript("OnMouseUp", function(self)
        if HandleItemDrop() then self:ClearFocus() end
    end)

    searchBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" and text ~= "Drop item or enter name/ID..." then
            local itemInfo = ResolveItem(text)
            if itemInfo then
                panel:ShowItem(itemInfo.dbKey, itemInfo.itemLink, itemInfo.name, itemInfo.icon, itemInfo.price)
                self:SetText("")
                self:ClearFocus()
            end
        end
    end)

    -- Item List ScrollFrame
    local itemsScroll = CreateFrame("ScrollFrame", "MarketSyncAnalyticsItemsScroll", leftInset, "UIPanelScrollFrameTemplate")
    itemsScroll:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -2, -6)
    itemsScroll:SetPoint("BOTTOMRIGHT", -22, 6)
    itemsScroll:EnableMouse(true)
    itemsScroll:SetScript("OnReceiveDrag", HandleItemDrop)
    itemsScroll:SetScript("OnMouseUp", function() HandleItemDrop() end)

    local itemsContent = CreateFrame("Frame", nil, itemsScroll)
    itemsContent:SetSize(210, 1)
    itemsScroll:SetScrollChild(itemsContent)
    itemsContent:EnableMouse(true)
    itemsContent:SetScript("OnReceiveDrag", HandleItemDrop)
    itemsContent:SetScript("OnMouseUp", function() HandleItemDrop() end)

    local emptyListText = itemsScroll:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyListText:SetPoint("CENTER", 0, 0)
    emptyListText:SetText("No scanned items recorded.\nRun an AH scan or drop an item above.")

    local function RefreshItemsList()
        itemsList = {}
        if currentMode == "recent" then
            listTitle:SetText("|cFFFFD100Scanned Items|r")
            emptyListText:SetText("No scanned items recorded.\nRun an AH scan or drop an item above.")
            recentBtn:Disable()
            favBtn:Enable()
            local seen = {}
            -- From live Scanner results
            local recent = (MarketSync.Scanner and MarketSync.Scanner.RecentResults) or {}
            for _, r in ipairs(recent) do
                if r.itemID and not seen[r.itemID] then
                    seen[r.itemID] = true
                    table.insert(itemsList, {
                        itemID = r.itemID,
                        name = r.name,
                        icon = r.icon,
                        quality = r.quality,
                        price = r.unitPrice,
                        sourceText = "Live Scan Feed",
                    })
                end
            end
            -- From PersonalData DB if recent is small
            if #itemsList < 20 and MarketSyncDB and MarketSync.GetRealmDB then
                local pData = MarketSync.GetRealmDB().PersonalData or {}
                for k, v in pairs(pData) do
                    local id = tonumber(k)
                    if id and not seen[id] then
                        seen[id] = true
                        local name, link, qual, _, _, _, _, _, _, icon = SafeGetItemInfo(id)
                        if not name and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[id] then
                            name = MarketSyncDB.ItemInfoCache[id].n
                            icon = MarketSyncDB.ItemInfoCache[id].ic
                            qual = MarketSyncDB.ItemInfoCache[id].r
                        end
                        local p = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(id) or 0
                        table.insert(itemsList, {
                            itemID = id,
                            name = name or ("Item #" .. id),
                            icon = icon or 134400,
                            quality = qual or 1,
                            price = p,
                            sourceText = "AH Scan Database",
                        })
                        if #itemsList >= 40 then break end
                    end
                end
            end
        else
            listTitle:SetText("|cFFFFD100Favorite Items|r")
            emptyListText:SetText("No favorite items saved.\nAdd items to your Favorites list.")
            recentBtn:Enable()
            favBtn:Disable()
            if MarketSync.Favorites and MarketSync.Favorites.GetList then
                local favs = MarketSync.Favorites.GetList("Favorites") or {}
                for _, id in ipairs(favs) do
                    local name, link, qual, _, _, _, _, _, _, icon = SafeGetItemInfo(id)
                    if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[id] then
                        name = MarketSyncDB.ItemInfoCache[id].n
                        icon = MarketSyncDB.ItemInfoCache[id].ic
                        qual = MarketSyncDB.ItemInfoCache[id].r
                    end
                    local p = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(id) or 0
                    table.insert(itemsList, {
                        itemID = id,
                        name = name or ("Item #" .. id),
                        icon = icon or 134400,
                        quality = qual or 1,
                        price = p,
                        sourceText = "User Favorites",
                    })
                end
            end
        end

        if #itemsList == 0 then
            emptyListText:Show()
        else
            emptyListText:Hide()
        end

        for i = 1, math.max(#itemsList, #itemRows) do
            local item = itemsList[i]
            local row = itemRows[i]
            if item then
                if not row then
                    row = CreateFrame("Button", nil, itemsContent, "BackdropTemplate")
                    row:SetHeight(rowH)
                    row:SetBackdrop({
                        bgFile = "Interface\Buttons\WHITE8X8",
                        edgeFile = "Interface\Buttons\WHITE8X8",
                        edgeSize = 1,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 }
                    })
                    row:SetBackdropBorderColor(0, 0, 0, 0)

                    local rIcon = row:CreateTexture(nil, "ARTWORK")
                    rIcon:SetSize(18, 18)
                    rIcon:SetPoint("LEFT", 3, 0)
                    rIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    row.icon = rIcon

                    local rPrice = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
                    rPrice:SetPoint("RIGHT", -4, 0)
                    rPrice:SetJustifyH("RIGHT")
                    row.price = rPrice

                    local rName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    rName:SetPoint("LEFT", rIcon, "RIGHT", 4, 0)
                    rName:SetPoint("RIGHT", rPrice, "LEFT", -4, 0)
                    rName:SetJustifyH("LEFT")
                    rName:SetWordWrap(false)
                    row.name = rName

                    itemRows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                local isSelected = (selectedDBKey and selectedDBKey == tostring(item.itemID))
                if isSelected then
                    row:SetBackdropColor(0.18, 0.28, 0.42, 0.85)
                    row:SetBackdropBorderColor(0.35, 0.60, 0.90, 0.80)
                elseif i % 2 == 0 then
                    row:SetBackdropColor(0.08, 0.09, 0.12, 0.50)
                    row:SetBackdropBorderColor(0, 0, 0, 0)
                else
                    row:SetBackdropColor(0.04, 0.05, 0.07, 0.50)
                    row:SetBackdropBorderColor(0, 0, 0, 0)
                end

                row.icon:SetTexture(item.icon)
                row.name:SetText(MarketSync.FormatColoredItemName and MarketSync.FormatColoredItemName(item.name, item.quality) or item.name)
                row.price:SetText(FormatMoneyPlain(item.price))

                row:SetScript("OnClick", function()
                    selectedDBKey = tostring(item.itemID)
                    panel:ShowItem(selectedDBKey, nil, item.name, item.icon, item.price)
                    RefreshItemsList()
                end)

                row:SetScript("OnEnter", function(self)
                    if not isSelected then
                        self:SetBackdropColor(0.15, 0.18, 0.24, 0.80)
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local link = select(2, SafeGetItemInfo(item.itemID))
                    if link and GameTooltip.SetHyperlink then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                    else
                        GameTooltip:SetText(item.name, 1, 1, 1)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF00FF00Click|r: View price analytics & trends", 0.8, 0.8, 0.8)
                    if item.sourceText then
                        GameTooltip:AddLine("|cFF888888Source: " .. item.sourceText .. "|r", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:Show()
                end)

                row:SetScript("OnLeave", function(self)
                    if isSelected then
                        self:SetBackdropColor(0.18, 0.28, 0.42, 0.85)
                    elseif i % 2 == 0 then
                        self:SetBackdropColor(0.08, 0.09, 0.12, 0.50)
                    else
                        self:SetBackdropColor(0.04, 0.05, 0.07, 0.50)
                    end
                    GameTooltip:Hide()
                end)

                if MarketSync.SetAccessibility then
                    MarketSync.SetAccessibility(row, {
                        name = function() return item.name or "Item" end,
                        context = "Button",
                        description = function()
                            local pSpoken = (item.price and item.price > 0) and (MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(item.price) or (item.price .. " copper")) or "No price data"
                            return string.format("%s, Latest price: %s. Click to view price analytics and trends.", item.name or "", pSpoken)
                        end,
                        getIndexInfo = function() return { index = i, total = #itemsList } end,
                    })
                end

                row:Show()
            elseif row then
                row:Hide()
            end
        end

        itemsContent:SetHeight(math.max(1, #itemsList * rowH))
    end

    recentBtn:SetScript("OnClick", function()
        currentMode = "recent"
        RefreshItemsList()
    end)
    favBtn:SetScript("OnClick", function()
        currentMode = "favorites"
        RefreshItemsList()
    end)

    -- ================================================================
    -- RIGHT INSET: DETAIL BANNER, GRAPH & METRICS
    -- ================================================================
    -- 1. Top Detail Banner (Icon, Name, Subtitle, Search in AH button)
    local banner = CreateFrame("Frame", nil, rightInset)
    banner:SetPoint("TOPLEFT", 10, -8)
    banner:SetPoint("TOPRIGHT", -10, -8)
    banner:SetHeight(46)

    local icon = banner:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.icon = icon

    local iconBorder = banner:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconBorder:SetSize(68, 68)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)

    local itemName = banner:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    itemName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    itemName:SetPoint("RIGHT", -215, 0)
    itemName:SetJustifyH("LEFT")
    panel.name = itemName

    local itemSub = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    itemSub:SetPoint("TOPLEFT", itemName, "BOTTOMLEFT", 0, -4)
    itemSub:SetPoint("RIGHT", -215, 0)
    itemSub:SetJustifyH("LEFT")
    itemSub:SetText("Price Analytics & Historiography")
    panel.subtitle = itemSub

    local searchAHBtn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
    searchAHBtn:SetSize(100, 22)
    searchAHBtn:SetPoint("RIGHT", -2, 0)
    searchAHBtn:SetText("Search in AH")
    searchAHBtn:SetScript("OnClick", function()
        if panel.currentItem and MarketSync.SearchInAuctionHouse then
            MarketSync.SearchInAuctionHouse(panel.currentItem.itemID or panel.currentItem.name)
        end
    end)
    searchAHBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search in Auction House", 1, 1, 1)
        GameTooltip:AddLine("Switches to the native AH Buy tab and queries this item directly.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    searchAHBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local favBannerBtn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
    favBannerBtn:SetSize(96, 22)
    favBannerBtn:SetPoint("RIGHT", searchAHBtn, "LEFT", -4, 0)
    favBannerBtn:SetText("+ Favorite")
    panel.favBannerBtn = favBannerBtn

    local function UpdateFavBannerBtn()
        if not panel.currentItem or not panel.currentItem.itemID then
            favBannerBtn:Disable()
            favBannerBtn:SetText("+ Favorite")
            return
        end
        favBannerBtn:Enable()
        local isFav = MarketSync.Favorites and MarketSync.Favorites.IsItemInList and MarketSync.Favorites.IsItemInList("Favorites", panel.currentItem.itemID)
        if isFav then
            favBannerBtn:SetText("|cFFFFD100★ Favorited|r")
        else
            favBannerBtn:SetText("+ Favorite")
        end
    end
    panel.UpdateFavBannerBtn = UpdateFavBannerBtn

    favBannerBtn:SetScript("OnClick", function()
        if panel.currentItem and panel.currentItem.itemID and MarketSync.Favorites and MarketSync.Favorites.ToggleItemInList then
            MarketSync.Favorites.ToggleItemInList("Favorites", panel.currentItem.itemID)
            UpdateFavBannerBtn()
            if currentMode == "favorites" then
                RefreshItemsList()
            end
        end
    end)
    favBannerBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle Favorite", 1, 1, 1)
        GameTooltip:AddLine("Add or remove this item from your Favorites list.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    favBannerBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(searchAHBtn, {
            name = "Search in Auction House",
            context = "Button",
            description = function()
                local n = panel.currentItem and panel.currentItem.name or "current item"
                return "Query " .. n .. " in Auction House Buy tab"
            end,
            tooltipTitle = "Search in Auction House",
            tooltipText = "Switches to the native AH Buy tab and queries this item directly.",
        })
        MarketSync.SetAccessibility(favBannerBtn, {
            name = "Toggle Favorite",
            context = "Button",
            description = function()
                local n = panel.currentItem and panel.currentItem.name or "current item"
                return "Toggle " .. n .. " in Favorites list"
            end,
            tooltipTitle = "Toggle Favorite",
            tooltipText = "Add or remove this item from your Favorites list.",
        })
    end

    -- 2. Historical Trend Card
    local graphCard = MarketSync.CreateModernInset and MarketSync.CreateModernInset(rightInset)
    if not graphCard then
        graphCard = CreateFrame("Frame", nil, rightInset, "BackdropTemplate")
    end
    graphCard:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -6)
    graphCard:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, -6)
    graphCard:SetHeight(230)

    local graphHeader = graphCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    graphHeader:SetPoint("TOPLEFT", 10, -8)
    graphHeader:SetText("|cFFFFD100Historical Price Trend|r")

    local graphLegend = graphCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
    graphLegend:SetPoint("TOPRIGHT", -10, -8)
    graphLegend:SetText("|cFF33FF33— Daily Price|r    |cFF33B2FF● Granular 30-Min Snapshot|r")

    local graph = CreateGraph(graphCard)
    graph:SetPoint("TOPLEFT", 10, -26)
    graph:SetPoint("BOTTOMRIGHT", -10, 8)
    panel.graph = graph

    -- 3. Metrics & Insights Card
    local metricsCard = MarketSync.CreateModernInset and MarketSync.CreateModernInset(rightInset)
    if not metricsCard then
        metricsCard = CreateFrame("Frame", nil, rightInset, "BackdropTemplate")
    end
    metricsCard:SetPoint("TOPLEFT", graphCard, "BOTTOMLEFT", 0, -6)
    metricsCard:SetPoint("BOTTOMRIGHT", -10, 10)

    -- Left Column: Market Value & Freshness
    local leftMetricsTitle = metricsCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    leftMetricsTitle:SetPoint("TOPLEFT", 14, -8)
    leftMetricsTitle:SetText("|cFFFFD100Market Value & Freshness|r")

    local function CreateMetricRow(parent, anchor, yOff, label)
        local row = CreateFrame("Frame", nil, parent)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
        row:SetPoint("RIGHT", parent, "CENTER", -15, 0)
        row:SetHeight(18)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(label)

        local val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("RIGHT", 0, 0)
        row.val = val
        return val
    end

    panel.mPrice = CreateMetricRow(metricsCard, leftMetricsTitle, -6, "Current Market Value")
    panel.mStatus = CreateMetricRow(metricsCard, leftMetricsTitle, -26, "Data Health / Confidence")
    panel.mAge = CreateMetricRow(metricsCard, leftMetricsTitle, -46, "Data Age (Last Scanned)")
    panel.mSource = CreateMetricRow(metricsCard, leftMetricsTitle, -66, "Source Distribution")

    -- Subtle vertical divider in metrics card
    local vDivider = metricsCard:CreateTexture(nil, "BORDER")
    vDivider:SetWidth(1)
    vDivider:SetPoint("TOP", metricsCard, "TOP", 0, -8)
    vDivider:SetPoint("BOTTOM", metricsCard, "BOTTOM", 0, 8)
    vDivider:SetColorTexture(0.20, 0.22, 0.26, 0.70)

    -- Right Column: Intraday Analytics (30-Minute Buckets)
    local rightMetricsTitle = metricsCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rightMetricsTitle:SetPoint("TOPLEFT", metricsCard, "TOP", 15, -8)
    rightMetricsTitle:SetText("|cFF4499FFIntraday Analytics (30-min Buckets)|r")

    local function CreateRightMetricRow(parent, anchor, yOff, label)
        local row = CreateFrame("Frame", nil, parent)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
        row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
        row:SetHeight(18)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(label)

        local val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("RIGHT", 0, 0)
        row.val = val
        return val
    end

    panel.mBestTime = CreateRightMetricRow(metricsCard, rightMetricsTitle, -6, "Best Time to Buy")
    panel.mVolatility = CreateRightMetricRow(metricsCard, rightMetricsTitle, -26, "Intraday Price Volatility")
    panel.mDataPoints = CreateRightMetricRow(metricsCard, rightMetricsTitle, -46, "Granular Snapshots")

    local debugNote = metricsCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
    debugNote:SetPoint("BOTTOMLEFT", metricsCard, "BOTTOM", 15, 8)
    debugNote:SetPoint("RIGHT", -14, 0)
    debugNote:SetJustifyH("LEFT")
    debugNote:SetText("|cFF888888Intraday analytics compute cyclical price dips based on 30-minute scan snapshots across sessions.|r")

    -- 4. Empty State Placeholder (Visible when no item is selected)
    local emptyState = CreateFrame("Frame", nil, rightInset)
    emptyState:SetAllPoints(rightInset)
    emptyState:EnableMouse(true)
    emptyState:SetScript("OnReceiveDrag", HandleItemDrop)
    emptyState:SetScript("OnMouseUp", function() HandleItemDrop() end)

    local emptyTitle = emptyState:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    emptyTitle:SetPoint("CENTER", 0, 40)
    emptyTitle:SetText("|cFFFFD100Price Analytics & Historiography|r")

    local emptyMsg = emptyState:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyMsg:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -12)
    emptyMsg:SetText("No Item Selected")

    local emptyDesc = emptyState:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyDesc:SetPoint("TOP", emptyMsg, "BOTTOM", 0, -8)
    emptyDesc:SetWidth(440)
    emptyDesc:SetJustifyH("CENTER")
    emptyDesc:SetText("|cFF888888Drop an item from your bags, enter a name or ID on the left,\nor pick an item from Recent Scans to view historical price charts and intraday purchasing patterns.|r")

    -- ================================================================
    -- SHOW ITEM DATA METHOD
    -- ================================================================
    function panel:ShowItem(dbKey, itemLink, itemName, iconTex, price)
        if not dbKey and not itemLink and not itemName then return end

        local itemInfo = ResolveItem(dbKey or itemLink or itemName)
        local key = (itemInfo and itemInfo.dbKey) or (dbKey and tostring(dbKey)) or "0"
        local nameStr = (itemInfo and itemInfo.name) or itemName or "Unknown Item"
        local iconPath = (itemInfo and itemInfo.icon) or iconTex or 134400
        local qual = (itemInfo and itemInfo.quality) or 1
        local marketPrice = (price and price > 0 and price) or (itemInfo and itemInfo.price) or 0
        local resolvedLink = (itemInfo and itemInfo.itemLink) or itemLink

        selectedDBKey = key
        panel.currentItem = {
            dbKey = key,
            itemID = itemInfo and itemInfo.itemID,
            name = nameStr,
            icon = iconPath,
            quality = qual,
            price = marketPrice,
            link = resolvedLink,
        }

        emptyState:Hide()
        if self.UpdateFavBannerBtn then self:UpdateFavBannerBtn() end
        self.icon:SetTexture(iconPath)
        self.name:SetText(MarketSync.FormatColoredItemName and MarketSync.FormatColoredItemName(nameStr, qual) or nameStr)

        local subText = "Item ID: " .. tostring(key)
        if resolvedLink then
            local _, _, _, _, _, itemType, itemSubType = SafeGetItemInfo(resolvedLink)
            if itemType and itemSubType then
                subText = subText .. " | " .. itemType .. " (" .. itemSubType .. ")"
            end
        end
        self.subtitle:SetText(subText)

        self.mPrice:SetText(FormatMoney(marketPrice))

        -- Retrieve History Data
        local history = MarketSync.GetItemHistory and MarketSync.GetItemHistory(key) or {}
        self.graph:Plot(history)

        -- Evaluate Data Freshness & Source Distribution
        local latestAge = 0
        local personal, guild = 0, 0
        if #history > 0 then
            local curDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or 0
            latestAge = math.max(0, curDay - (history[1].day or curDay))
            for i = 1, math.min(#history, 30) do
                if history[i].source == "Personal" then
                    personal = personal + 1
                else
                    guild = guild + 1
                end
            end
        end

        local total = personal + guild
        local pPct = total > 0 and math.floor(personal / total * 100) or 0
        local gPct = total > 0 and (100 - pPct) or 0
        self.mSource:SetText(string.format("Personal: %d%% | Guild: %d%%", pPct, gPct))

        local ageStr = (latestAge == 0) and "Today" or (latestAge .. "d ago")
        if latestAge == 0 and history[1] and history[1].source == "Personal" then
            local pTime = MarketSyncDB and MarketSync.GetRealmDB and MarketSync.GetRealmDB().PersonalScanTime
            if pTime and pTime > 0 and MarketSync.FormatRealmTime then
                ageStr = "Today (" .. MarketSync.FormatRealmTime(pTime) .. ")"
            end
        end

        local isStale = (latestAge > 3)
        self.mAge:SetText((isStale and "|cffff4444" or "|cff00ff00") .. ageStr .. "|r")
        self.mStatus:SetText(isStale and "|cffff4444STALE|r" or "|cff00ff00GOOD|r")

        -- Evaluate Intraday Analytics (30-Minute Buckets)
        local granular = MarketSync.GetGranularHistory and MarketSync.GetGranularHistory(key) or {}
        self.mDataPoints:SetText(#granular > 0 and (#granular .. " snapshots") or "|cff888888None|r")

        if #granular >= 3 then
            local bucketPrices = {}
            for _, pt in ipairs(granular) do
                local offs = pt.bucketOffset
                if offs then
                    if not bucketPrices[offs] then bucketPrices[offs] = { sum = 0, count = 0 } end
                    bucketPrices[offs].sum = bucketPrices[offs].sum + pt.price
                    bucketPrices[offs].count = bucketPrices[offs].count + 1
                end
            end

            local bestOffset, bestAvg = nil, math.huge
            for offs, data in pairs(bucketPrices) do
                local avg = data.sum / data.count
                if avg < bestAvg then
                    bestAvg = avg
                    bestOffset = offs
                end
            end

            if bestOffset and MarketSync.BucketOffsetToTime then
                local timeStr = MarketSync.BucketOffsetToTime(bestOffset)
                self.mBestTime:SetText("|cff00ff00" .. timeStr .. "|r (avg " .. FormatMoneyPlain(math.floor(bestAvg)) .. ")")
            else
                self.mBestTime:SetText("|cff888888Insufficient data|r")
            end

            local allSum, allMin, allMax = 0, math.huge, 0
            for _, pt in ipairs(granular) do
                allSum = allSum + pt.price
                if pt.price < allMin then allMin = pt.price end
                if pt.price > allMax then allMax = pt.price end
            end
            local mean = allSum / #granular
            if mean > 0 then
                local volatility = ((allMax - allMin) / mean) * 100
                local volColor = volatility > 25 and "|cffff4444" or (volatility > 10 and "|cffffd700" or "|cff00ff00")
                self.mVolatility:SetText(volColor .. string.format("%.1f%%", volatility) .. "|r")
            else
                self.mVolatility:SetText("|cff888888N/A|r")
            end
        else
            self.mBestTime:SetText("|cff888888Need 3+ data points|r")
            self.mVolatility:SetText("|cff888888Need 3+ data points|r")
        end

        RefreshItemsList()
        self:Show()
    end

    function panel:OnShow()
        RefreshItemsList()
        if panel.currentItem then
            panel:ShowItem(panel.currentItem.dbKey, panel.currentItem.link, panel.currentItem.name, panel.currentItem.icon, panel.currentItem.price)
        elseif #itemsList > 0 then
            local first = itemsList[1]
            panel:ShowItem(tostring(first.itemID), nil, first.name, first.icon, first.price)
        else
            emptyState:Show()
        end
    end

    panel:SetScript("OnShow", panel.OnShow)

    table.insert(registeredPanels, panel)
    return panel
end

-- ================================================================
-- GLOBAL ENTRY POINT: MarketSync.ShowAnalytics
-- Switches to AH Analytics tab if AH is open, or MainFrame if standalone
-- ================================================================
function MarketSync.ShowAnalytics(dbKey, itemLink, name, icon, price)
    -- 1. If native AH is open, activate AH Analytics tab
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() and MarketSync.AuctionHouse and MarketSync.AuctionHouse.ShowAuctionHousePanel then
        MarketSync.AuctionHouse.ShowAuctionHousePanel("analytics")
    elseif MarketSync.MainFrame then
        if MarketSync.HideAllTabContent then
            MarketSync.HideAllTabContent()
        end
        if not MarketSync.MainFrame:IsShown() then
            MarketSync.MainFrame:Show()
        end
    end

    -- 2. Dispatch to all registered analytics panels
    for _, p in ipairs(registeredPanels) do
        if p.ShowItem then
            p:ShowItem(dbKey, itemLink, name, icon, price)
        end
    end
end
