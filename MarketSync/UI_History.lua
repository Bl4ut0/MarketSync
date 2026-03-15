-- =============================================================
-- MarketSync - Item History Panel
-- In-frame detail view: price graph (left) + scan list (right)
-- Uses Bid-tab parchment background, same as Settings
-- =============================================================

local SCANS_PER_PAGE = 18
local CONTENT_TOP = -75      -- below header row
local CONTENT_BOTTOM = 45    -- above bottom gold bar
local LEFT_MARGIN = 25
local RIGHT_MARGIN = 20

-- Layout: LEFT = graph, RIGHT = scan list
local GRAPH_WIDTH = 370
local LIST_START_X = 410

-- ---- Money Formatter (colorized with g/s/c) ----
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

-- Plain money formatter (no color codes, for graph labels)
local function FormatMoneyPlain(copper)
    if not copper or copper == 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return g .. "g" .. (s > 0 and (" " .. s .. "s") or "") end
    if s > 0 then return s .. "s" .. (c > 0 and (" " .. c .. "c") or "") end
    return c .. "c"
end

-- ================================================================
-- EXTRACT HISTORY DATA FROM AUCTIONATOR DB
-- ================================================================

-- Convert scan day number to a readable date string
local function ScanDayToDate(scanDay)
    if not Auctionator or not Auctionator.Constants or not Auctionator.Constants.SCAN_DAY_0 then
        return "Day " .. scanDay
    end
    local timestamp = Auctionator.Constants.SCAN_DAY_0 + (scanDay * 86400)
    return date("%b %d", timestamp)
end

-- Get age in days from scan day
local function ScanDayAge(scanDay)
    local currentDay = MarketSync.GetCurrentScanDay()
    if currentDay == 0 then return "?" end
    local age = currentDay - scanDay
    if age == 0 then return "Today"
    elseif age == 1 then return "Yesterday"
    else return age .. "d ago" end
end

-- ================================================================
-- PIXEL GRAPH RENDERER (adaptive, drawn with texture lines)
-- ================================================================
local function CreateGraph(parent, width, height)
    local graph = CreateFrame("Frame", nil, parent)
    graph:SetSize(width, height)
    graph.lines = {}
    graph.dots = {}
    graph.gridLines = {}
    graph.labels = {}
    graph.plotWidth = width
    graph.plotHeight = height
    graph.lineCursor = 0
    graph.dotCursor = 0
    graph.gridCursor = 0
    graph.labelCursor = 0

    -- Background
    local bg = graph:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetColorTexture(0, 0, 0, 0.35)
    bg:SetAllPoints()
    graph.bg = bg

    -- Border
    local borderLeft = graph:CreateTexture(nil, "BORDER")
    borderLeft:SetColorTexture(0.6, 0.5, 0.2, 0.8)
    borderLeft:SetSize(1, height)
    borderLeft:SetPoint("TOPLEFT", 0, 0)

    local borderBottom = graph:CreateTexture(nil, "BORDER")
    borderBottom:SetColorTexture(0.6, 0.5, 0.2, 0.8)
    borderBottom:SetSize(width, 1)
    borderBottom:SetPoint("BOTTOMLEFT", 0, 0)

    local borderTop = graph:CreateTexture(nil, "BORDER")
    borderTop:SetColorTexture(0.6, 0.5, 0.2, 0.4)
    borderTop:SetSize(width, 1)
    borderTop:SetPoint("TOPLEFT", 0, 0)

    local borderRight = graph:CreateTexture(nil, "BORDER")
    borderRight:SetColorTexture(0.6, 0.5, 0.2, 0.4)
    borderRight:SetSize(1, height)
    borderRight:SetPoint("TOPRIGHT", 0, 0)

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

    function graph:GetOrCreateLine()
        self.lineCursor = self.lineCursor + 1
        local line = self.lines[self.lineCursor]
        if not line then
            line = self:CreateLine(nil, "ARTWORK")
            self.lines[self.lineCursor] = line
        end
        return line
    end

    function graph:DrawLine(x1, y1, x2, y2, r, g, b, a, thickness)
        local line = self:GetOrCreateLine()
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
            self.dots[self.dotCursor] = dot
        end
        local s = size or 6
        dot:SetSize(s, s)
        dot:SetColorTexture(r or 1, g or 1, b or 1, 1)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
        dot:Show()
    end

    function graph:DrawGridLine(y, alpha)
        self.gridCursor = self.gridCursor + 1
        local gl = self.gridLines[self.gridCursor]
        if not gl then
            gl = self:CreateTexture(nil, "BACKGROUND", nil, 3)
            self.gridLines[self.gridCursor] = gl
        end
        gl:SetColorTexture(0.5, 0.5, 0.5, alpha or 0.15)
        gl:SetSize(self.plotWidth - 2, 1)
        gl:ClearAllPoints()
        gl:SetPoint("LEFT", self, "BOTTOMLEFT", 1, y)
        gl:Show()
    end

    function graph:AddLabel(x, y, text, anchor)
        self.labelCursor = self.labelCursor + 1
        local lbl = self.labels[self.labelCursor]
        if not lbl then
            lbl = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
            self.labels[self.labelCursor] = lbl
        end
        lbl:ClearAllPoints()
        lbl:SetPoint(anchor or "TOP", self, "BOTTOMLEFT", x, y)
        lbl:SetText(text)
        lbl:Show()
    end

    function graph:PlotHistory(history)
        self:Clear()

        if not history or #history < 1 then
            local noData = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noData:SetPoint("CENTER")
            noData:SetText("No historical data")
            table.insert(self.labels, noData)
            return
        end

        -- Use up to 30 data points (most recent), reverse to oldest-left
        local maxPoints = math.min(#history, 30)
        local plotData = {}
        for i = maxPoints, 1, -1 do
            table.insert(plotData, history[i])
        end

        -- Find min/max price
        local minPrice, maxPrice = math.huge, 0
        for _, d in ipairs(plotData) do
            if d.high and d.high > maxPrice then maxPrice = d.high end
            if d.low and d.low < minPrice then minPrice = d.low end
            if d.price and d.price > maxPrice then maxPrice = d.price end
            if d.price and d.price < minPrice then minPrice = d.price end
        end

        if minPrice == math.huge then minPrice = 0 end
        if maxPrice == 0 then maxPrice = 100 end

        -- Add 10% padding
        local range = maxPrice - minPrice
        if range == 0 then range = maxPrice * 0.1; if range == 0 then range = 100 end end
        local padMin = minPrice - (range * 0.1)
        if padMin < 0 then padMin = 0 end
        local padMax = maxPrice + (range * 0.1)
        local fullRange = padMax - padMin
        if fullRange == 0 then fullRange = 100 end

        local pw = self.plotWidth - 50  -- plot area width (leave room for Y labels)
        local ph = self.plotHeight - 30 -- plot area height (leave room for X labels)
        local offsetX = 45              -- left margin for Y labels
        local offsetY = 18              -- bottom margin for X labels

        -- Grid lines (4 horizontal)
        for i = 0, 4 do
            local frac = i / 4
            local yPos = offsetY + (frac * ph)
            self:DrawGridLine(yPos, 0.15)
            local priceVal = padMin + (frac * fullRange)
            self:AddLabel(offsetX - 5, yPos, FormatMoneyPlain(math.floor(priceVal)), "RIGHT")
        end

        -- Plot points
        local numPoints = #plotData
        local spacing = pw / math.max(numPoints - 1, 1)
        local prevX, prevY

        for i, d in ipairs(plotData) do
            local x = offsetX + ((i - 1) * spacing)
            local priceNorm = (d.price - padMin) / fullRange
            local y = offsetY + (priceNorm * ph)

            -- Draw high-low range bar
            if d.high and d.low and d.high ~= d.low then
                local yHigh = offsetY + (((d.high - padMin) / fullRange) * ph)
                local yLow = offsetY + (((d.low - padMin) / fullRange) * ph)
                self:DrawLine(x, yLow, x, yHigh, 0.4, 0.4, 0.8, 0.5, 1)
            end

            -- Connect from previous point
            if prevX then
                self:DrawLine(prevX, prevY, x, y, 0.2, 0.8, 0.2, 0.9, 2)
            end

            -- Dot
            self:DrawDot(x, y, 0.3, 1.0, 0.3, 5)

            -- X-axis date labels (spaced to avoid crowding)
            local labelEvery = math.max(1, math.floor(numPoints / 6))
            if i == 1 or i == numPoints or (i % labelEvery == 0) then
                self:AddLabel(x, offsetY - 12, ScanDayToDate(d.day), "TOP")
            end

            prevX, prevY = x, y
        end
    end

    return graph
end

-- ================================================================
-- CREATE ITEM HISTORY PANEL
-- ================================================================
function MarketSync.CreateItemHistoryPanel(parentFrame)
    local panel = CreateFrame("Frame", nil, parentFrame)
    panel:SetAllPoints(parentFrame)
    panel:Hide()

    panel.historyData = {}
    panel.scanPage = 0
    panel.sourceTab = "personal"  -- which browse tab opened this

    -- ================================================================
    -- BACKGROUND TEXTURES (Bid-tab parchment, same as Settings)
    -- ================================================================
    local btl = panel:CreateTexture(nil, "BACKGROUND")
    btl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopLeft")
    btl:SetSize(256, 256); btl:SetPoint("TOPLEFT")

    local btm = panel:CreateTexture(nil, "BACKGROUND")
    btm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Top")
    btm:SetSize(320, 256); btm:SetPoint("TOPLEFT", 256, 0)

    local btr = panel:CreateTexture(nil, "BACKGROUND")
    btr:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopRight")
    btr:SetSize(256, 256); btr:SetPoint("TOPLEFT", btm, "TOPRIGHT")

    local bbl = panel:CreateTexture(nil, "BACKGROUND")
    bbl:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotLeft")
    bbl:SetSize(256, 256); bbl:SetPoint("TOPLEFT", 0, -256)

    local bbm = panel:CreateTexture(nil, "BACKGROUND")
    bbm:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Bot")
    bbm:SetSize(320, 256); bbm:SetPoint("TOPLEFT", 256, -256)

    local bbr = panel:CreateTexture(nil, "BACKGROUND")
    bbr:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotRight")
    bbr:SetSize(256, 256); bbr:SetPoint("TOPLEFT", bbm, "TOPRIGHT")

    -- ================================================================
    -- HEADER ROW: Item info (buttons moved to bottom slots)
    -- ================================================================

    -- Item icon (centered in header area)
    local itemIcon = panel:CreateTexture(nil, "ARTWORK")
    itemIcon:SetSize(32, 32)
    itemIcon:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 350, -40)
    panel.itemIcon = itemIcon

    local iconBorder = panel:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconBorder:SetSize(54, 54)
    iconBorder:SetPoint("CENTER", itemIcon, "CENTER")

    -- Item name
    local itemName = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    itemName:SetPoint("LEFT", itemIcon, "RIGHT", 8, 6)
    itemName:SetWidth(500)
    itemName:SetJustifyH("LEFT")
    panel.itemName = itemName

    -- Current market price
    local itemPrice = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    itemPrice:SetPoint("LEFT", itemIcon, "RIGHT", 8, -8)
    itemPrice:SetWidth(500)
    itemPrice:SetJustifyH("LEFT")
    panel.itemPrice = itemPrice

    panel.activeTab = "history"

    -- Thin separator under header
    local headerSep = panel:CreateTexture(nil, "ARTWORK")
    headerSep:SetColorTexture(0.6, 0.5, 0.2, 0.4)
    headerSep:SetSize(780, 1)
    headerSep:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LEFT_MARGIN, CONTENT_TOP + 3)

    -- ================================================================
    -- LEFT SIDE: PRICE GRAPH
    -- ================================================================
    local graphHeight = 310  -- tall graph filling most of the vertical space
    local graph = CreateGraph(panel, GRAPH_WIDTH, graphHeight)
    graph:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LEFT_MARGIN, CONTENT_TOP)
    panel.graph = graph

    -- Graph title
    local graphTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    graphTitle:SetPoint("TOP", graph, "TOP", 0, 12)
    graphTitle:SetText("|cffffd700Price Trend|r")
    panel.graphTitle = graphTitle

    -- ================================================================
    -- RIGHT SIDE: SCAN HISTORY TABLE
    -- ================================================================
    local listWidth = 390
    local ROW_HEIGHT = 16

    -- Section title (centered over the scan columns)
    local listTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listTitle:SetPoint("TOP", parentFrame, "TOPLEFT", LIST_START_X + 195, CONTENT_TOP + 12)
    listTitle:SetText("|cffffd700Scan History|r")
    panel.listTitle = listTitle

    -- Column headers
    local scanColDefs = {
        {name = "Date",   width = 45,  offset = 0},
        {name = "High",   width = 100, offset = 45},
        {name = "Low",    width = 100, offset = 145},
        {name = "Qty",    width = 40,  offset = 245},
        {name = "Source", width = 50,  offset = 285},
        {name = "Age",    width = 55,  offset = 335},
    }

    panel.scanHeaders = {}
    for i, col in ipairs(scanColDefs) do
        local hdr = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hdr:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LIST_START_X + col.offset, CONTENT_TOP)
        hdr:SetWidth(col.width)
        hdr:SetJustifyH("LEFT")
        hdr:SetText("|cffffd700" .. col.name .. "|r")
        panel.scanHeaders[i] = hdr
    end

    local listSep = panel:CreateTexture(nil, "ARTWORK")
    listSep:SetColorTexture(0.6, 0.5, 0.2, 0.4)
    listSep:SetSize(listWidth, 1)
    listSep:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LIST_START_X, CONTENT_TOP - 12)
    panel.listSep = listSep

    -- Scan rows
    panel.scanRows = {}
    for i = 1, SCANS_PER_PAGE do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(listWidth, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LIST_START_X, CONTENT_TOP - 14 - ((i - 1) * ROW_HEIGHT))

        row.dateText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.dateText:SetPoint("LEFT", 0, 0); row.dateText:SetWidth(45); row.dateText:SetJustifyH("LEFT")

        row.highText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.highText:SetPoint("LEFT", 45, 0); row.highText:SetWidth(100); row.highText:SetJustifyH("LEFT")

        row.lowText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.lowText:SetPoint("LEFT", 145, 0); row.lowText:SetWidth(100); row.lowText:SetJustifyH("LEFT")

        row.qtyText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.qtyText:SetPoint("LEFT", 245, 0); row.qtyText:SetWidth(40); row.qtyText:SetJustifyH("LEFT")

        row.sourceText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.sourceText:SetPoint("LEFT", 285, 0); row.sourceText:SetWidth(50); row.sourceText:SetJustifyH("LEFT")

        row.ageText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.ageText:SetPoint("LEFT", 335, 0); row.ageText:SetWidth(55); row.ageText:SetJustifyH("LEFT")

        -- Alternating row background
        if i % 2 == 0 then
            local rowBg = row:CreateTexture(nil, "BACKGROUND", nil, 3)
            rowBg:SetColorTexture(1, 1, 1, 0.03)
            rowBg:SetAllPoints()
        end

        row:Hide()
        panel.scanRows[i] = row
    end

    -- ================================================================
    -- BOTTOM BAR: Status info (left) + Pagination (center-left) + Action Buttons (right slots)
    -- ================================================================

    -- Status text (bottom left - shows scan/sync info based on source tab)
    panel.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.statusText:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 30, 20)
    panel.statusText:SetWidth(150)
    panel.statusText:SetJustifyH("LEFT")

    -- Sync label
    panel.syncLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.syncLabel:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 195, 20)
    panel.syncLabel:SetJustifyH("LEFT")

    -- Item count
    panel.itemCountText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.itemCountText:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 300, 20)
    panel.itemCountText:SetWidth(100)
    panel.itemCountText:SetJustifyH("LEFT")

    -- Pagination (moved to center-left, after item count)
    panel.scanPageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.scanPageText:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 400, 20)

    local scanPrevBtn = CreateFrame("Button", nil, panel)
    scanPrevBtn:SetSize(28, 28)
    scanPrevBtn:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 510, 11)
    scanPrevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    scanPrevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    scanPrevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    scanPrevBtn:SetScript("OnClick", function()
        if panel.scanPage > 0 then
            panel.scanPage = panel.scanPage - 1
            panel:UpdateScanTable()
        end
    end)
    panel.scanPrevBtn = scanPrevBtn

    local scanNextBtn = CreateFrame("Button", nil, panel)
    scanNextBtn:SetSize(28, 28)
    scanNextBtn:SetPoint("LEFT", scanPrevBtn, "RIGHT", 2, 0)
    scanNextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    scanNextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    scanNextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    scanNextBtn:SetScript("OnClick", function()
        local maxPage = math.max(0, math.ceil(#panel.historyData / SCANS_PER_PAGE) - 1)
        if panel.scanPage < maxPage then
            panel.scanPage = panel.scanPage + 1
            panel:UpdateScanTable()
        end
    end)
    panel.scanNextBtn = scanNextBtn

    -- ================================================================
    -- BOTTOM-RIGHT SLOTS: Back, History, Data
    -- Fit inside the 3 recessed AH money-input slots in the gold bar
    -- Slots are ~70px wide with ~8px gaps between them
    -- ================================================================

    -- Left slot: Back
    local backBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    backBtn:SetSize(75, 19)
    backBtn:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -170, 14)
    backBtn:SetText("Back")
    panel.backBtn = backBtn

    -- Middle slot: History
    local tabHistBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    tabHistBtn:SetSize(75, 19)
    tabHistBtn:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -90, 14)
    tabHistBtn:SetText("History")
    panel.tabHistBtn = tabHistBtn

    -- Right slot: Data
    local tabSalesBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    tabSalesBtn:SetSize(80, 19)
    tabSalesBtn:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -8, 14)
    tabSalesBtn:SetText("Data")
    panel.tabSalesBtn = tabSalesBtn

    -- No data text
    panel.noDataText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noDataText:SetPoint("CENTER", panel, "CENTER", 0, -30)
    panel.noDataText:SetText("No scan history available for this item.")
    panel.noDataText:Hide()

    -- ================================================================
    -- SALES DATA VIEW (overlays the graph + list area)
    -- ================================================================
    panel.salesFrame = CreateFrame("Frame", nil, panel)
    panel.salesFrame:SetAllPoints(panel)
    panel.salesFrame:Hide()

    local salesTitle = panel.salesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    salesTitle:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LEFT_MARGIN, CONTENT_TOP + 2)
    salesTitle:SetText("|cffffd700Available Listings Breakdown|r")

    local salesDesc = panel.salesFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    salesDesc:SetPoint("TOPLEFT", salesTitle, "BOTTOMLEFT", 0, -4)
    salesDesc:SetWidth(780)
    salesDesc:SetJustifyH("LEFT")
    salesDesc:SetText("|cff888888This shows the distribution of listings at different price points from stored scan data.\n" ..
        "Use this to verify if the 'lowest price' is representative or a possible outlier.|r")

    -- Sales column headers (positioned below the description)
    local salesHeaderY = CONTENT_TOP - 32
    local salesColX = LEFT_MARGIN
    local salesColDefs = {
        {name = "Price Point", width = 180},
        {name = "Quantity",    width = 100},
        {name = "% of Total",  width = 100},
        {name = "Notes",       width = 300},
    }
    panel.salesHeaders = {}
    for i, col in ipairs(salesColDefs) do
        local hdr = panel.salesFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hdr:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", salesColX, salesHeaderY)
        hdr:SetWidth(col.width)
        hdr:SetJustifyH("LEFT")
        hdr:SetText("|cffffd700" .. col.name .. "|r")
        panel.salesHeaders[i] = hdr
        salesColX = salesColX + col.width
    end

    local salesSep = panel.salesFrame:CreateTexture(nil, "ARTWORK")
    salesSep:SetColorTexture(0.6, 0.5, 0.2, 0.4)
    salesSep:SetSize(780, 1)
    salesSep:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LEFT_MARGIN, salesHeaderY - 12)

    panel.salesRows = {}
    local salesRowStart = salesHeaderY - 15
    for i = 1, 15 do
        local row = CreateFrame("Frame", nil, panel.salesFrame)
        row:SetSize(780, 20)
        row:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", LEFT_MARGIN, salesRowStart - ((i - 1) * 20))

        row.priceText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.priceText:SetPoint("LEFT", 0, 0); row.priceText:SetWidth(180); row.priceText:SetJustifyH("LEFT")

        row.qtyText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.qtyText:SetPoint("LEFT", 180, 0); row.qtyText:SetWidth(100); row.qtyText:SetJustifyH("LEFT")

        row.pctText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.pctText:SetPoint("LEFT", 280, 0); row.pctText:SetWidth(100); row.pctText:SetJustifyH("LEFT")

        row.noteText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.noteText:SetPoint("LEFT", 400, 0); row.noteText:SetWidth(300); row.noteText:SetJustifyH("LEFT")

        if i % 2 == 0 then
            local rowBg = row:CreateTexture(nil, "BACKGROUND", nil, 3)
            rowBg:SetColorTexture(1, 1, 1, 0.03)
            rowBg:SetAllPoints()
        end

        row:Hide()
        panel.salesRows[i] = row
    end

    panel.salesNoData = panel.salesFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.salesNoData:SetPoint("CENTER", panel.salesFrame, "CENTER", 0, -30)
    panel.salesNoData:SetText("|cff888888Sales distribution data is computed from stored scan records.\nMore scans = more accurate breakdown.|r")
    panel.salesNoData:Hide()

    -- ================================================================
    -- UPDATE FUNCTIONS
    -- ================================================================

    function panel:UpdateStatusBar()
        if self.sourceTab == "personal" then
            local personalTime = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime or 0
            local totalItems = 0
            if Auctionator and Auctionator.Database and Auctionator.Database.db then
                for _ in pairs(Auctionator.Database.db) do totalItems = totalItems + 1 end
            end

            if personalTime > 0 then
                local timeStr = MarketSync.FormatRealmTime(personalTime)
                local myName = UnitName("player") or "You"
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. myName .. "|r")
            else
                self.statusText:SetText("|cffff8800No personal scan data|r")
            end
            self.itemCountText:SetText("|cffffd700" .. totalItems .. "|r items")
            self.syncLabel:SetText("|cff00ff00Last Personal Scan|r")
        elseif self.sourceTab == "guild" then
            local latestUser, latestTime = nil, 0
            local totalItems = 0
            if MarketSync.GetLatestSyncContributor then
                latestUser, latestTime = MarketSync.GetLatestSyncContributor(false)
            end
            latestTime = tonumber(latestTime) or 0
            -- Count items from the live Auctionator DB (same source as Guild Sync browse tab)
            if Auctionator and Auctionator.Database and Auctionator.Database.db then
                for _ in pairs(Auctionator.Database.db) do totalItems = totalItems + 1 end
            end
            
            -- Check if our personal scan is newer than the latest guild sync
            local personalTime = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime or 0
            if personalTime > latestTime then
                local timeStr = MarketSync.FormatRealmTime(personalTime)
                local myName = UnitName("player") or "You"
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. myName .. "|r")
                self.syncLabel:SetText("|cff00ff00Latest Data|r")
            elseif latestUser then
                local timeStr = MarketSync.FormatRealmTime(latestTime)
                local shortName = latestUser:match("^([^%-]+)") or latestUser
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. shortName .. "|r")
                self.syncLabel:SetText("|cff00ff00Last Guild Sync|r")
            else
                self.statusText:SetText("|cffff8800No sync data yet|r")
                self.syncLabel:SetText("")
            end
            self.itemCountText:SetText("|cffffd700" .. totalItems .. "|r items")
        end
    end

    function panel:UpdateScanTable()
        local offset = self.scanPage * SCANS_PER_PAGE
        local total = #self.historyData

        for i = 1, SCANS_PER_PAGE do
            local row = self.scanRows[i]
            local idx = offset + i
            if idx <= total then
                local d = self.historyData[idx]
                row.dateText:SetText(ScanDayToDate(d.day))
                row.highText:SetText(FormatMoney(d.high))
                row.lowText:SetText(FormatMoney(d.low))
                row.qtyText:SetText(d.quantity > 0 and d.quantity or "-")
                row.ageText:SetText(ScanDayAge(d.day))
                -- Source comes directly from the per-day attribution baked into historyData
                row.sourceText:SetText(d.source or "Personal")
                row:Show()
            else
                row:Hide()
            end
        end

        local maxPage = math.max(0, math.ceil(total / SCANS_PER_PAGE) - 1)
        self.scanPageText:SetText(total .. " scans (Page " .. (self.scanPage + 1) .. "/" .. (maxPage + 1) .. ")")
        self.scanPrevBtn:SetEnabled(self.scanPage > 0)
        self.scanNextBtn:SetEnabled(self.scanPage < maxPage)

        if total == 0 then
            self.noDataText:Show()
        else
            self.noDataText:Hide()
        end
    end

    function panel:UpdateSalesData()
        for _, row in ipairs(self.salesRows) do row:Hide() end
        self.salesNoData:Hide()

        local history = self.historyData
        if not history or #history == 0 then
            self.salesNoData:Show()
            return
        end

        -- Group prices into buckets
        local pricePoints = {}
        local totalQty = 0
        for _, d in ipairs(history) do
            local price = d.price
            if price and price > 0 then
                if not pricePoints[price] then
                    pricePoints[price] = { price = price, qty = 0, count = 0 }
                end
                local qty = (d.quantity > 0) and d.quantity or 1
                pricePoints[price].qty = pricePoints[price].qty + qty
                pricePoints[price].count = pricePoints[price].count + 1
                totalQty = totalQty + qty
            end
        end

        local sorted = {}
        for _, pp in pairs(pricePoints) do table.insert(sorted, pp) end
        table.sort(sorted, function(a, b) return a.price < b.price end)

        if #sorted == 0 then
            self.salesNoData:Show()
            return
        end

        local lowestPrice = sorted[1].price

        for i, pp in ipairs(sorted) do
            if i > 15 then break end
            local row = self.salesRows[i]
            row.priceText:SetText(FormatMoney(pp.price))
            row.qtyText:SetText(pp.qty)
            local pct = (totalQty > 0) and (pp.qty / totalQty * 100) or 0
            row.pctText:SetText(string.format("%.1f%%", pct))

            if pp.price == lowestPrice then
                if pp.qty <= 1 then
                    row.noteText:SetText("|cffff8800Possible outlier (1 unit)|r")
                else
                    row.noteText:SetText("|cff00ff00Lowest - " .. pp.qty .. " available|r")
                end
            else
                local diff = pp.price - lowestPrice
                local pctDiff = (lowestPrice > 0) and (diff / lowestPrice * 100) or 0
                if pctDiff < 5 then
                    row.noteText:SetText("|cff888888~same price|r")
                else
                    row.noteText:SetText("|cff888888+" .. string.format("%.0f%%", pctDiff) .. " above lowest|r")
                end
            end
            row:Show()
        end
    end

    function panel:ShowHistoryTab()
        self.activeTab = "history"
        self.graph:Show()
        self.graphTitle:Show()
        self.listTitle:Show()
        for _, h in ipairs(self.scanHeaders) do h:Show() end
        self.listSep:Show()
        self.scanPrevBtn:Show()
        self.scanNextBtn:Show()
        self.scanPageText:Show()
        self.salesFrame:Hide()

        self.tabHistBtn:Disable()
        self.tabSalesBtn:Enable()

        self:UpdateScanTable()
        if self.historyData and #self.historyData > 0 then
            self.graph:PlotHistory(self.historyData)
        end
    end

    function panel:ShowSalesTab()
        self.activeTab = "sales"
        self.graph:Hide()
        self.graphTitle:Hide()
        self.listTitle:Hide()
        for _, h in ipairs(self.scanHeaders) do h:Hide() end
        self.listSep:Hide()
        for _, row in ipairs(self.scanRows) do row:Hide() end
        self.noDataText:Hide()
        self.scanPrevBtn:Hide()
        self.scanNextBtn:Hide()
        self.scanPageText:Hide()

        self.salesFrame:Show()
        self.tabHistBtn:Enable()
        self.tabSalesBtn:Disable()

        self:UpdateSalesData()
    end

    -- ---- SHOW ITEM ----
    function panel:ShowItem(dbKey, itemLink, name, icon, price, sourceTab)
        self.currentDbKey = dbKey
        self.historyData = MarketSync.GetItemHistory(dbKey)
        self.scanPage = 0
        self.sourceTab = sourceTab or "personal"

        -- Set header info
        self.itemIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        self.itemName:SetText(itemLink or name or "Unknown Item")
        self.itemPrice:SetText("Current Market: " .. FormatMoney(price))

        -- Update bottom bar with scan/sync info
        self:UpdateStatusBar()

        -- Show history tab by default
        self:ShowHistoryTab()
        self:Show()
    end

    -- Tab click handlers
    tabHistBtn:SetScript("OnClick", function() panel:ShowHistoryTab() end)
    tabSalesBtn:SetScript("OnClick", function() panel:ShowSalesTab() end)

    return panel
end


