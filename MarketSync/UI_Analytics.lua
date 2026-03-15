-- =============================================================
-- MarketSync - Analytics & Historiography Panel
-- Detailed breakdown of status, trends, and data sources
-- =============================================================

local AnalyticsPanel
local LEFT_MARGIN = 25
local CONTENT_TOP = -75
local GRAPH_WIDTH = 370
local INFO_START_X = 410

-- Ref reused from UI_History
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
    if not Auctionator or not Auctionator.Constants or not Auctionator.Constants.SCAN_DAY_0 then
        return "Day " .. scanDay
    end
    local timestamp = Auctionator.Constants.SCAN_DAY_0 + (scanDay * 86400)
    return date("%b %d", timestamp)
end

-- ================================================================
-- GRAPH RENDERER (Simplified port from UI_History)
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

    local bg = graph:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetColorTexture(0, 0, 0, 0.35)
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

    function graph:DrawDot(x, y, r, g, b)
        self.dotCursor = self.dotCursor + 1
        local dot = self.dots[self.dotCursor]
        if not dot then
            dot = self:CreateTexture(nil, "OVERLAY")
            table.insert(self.dots, dot)
        end
        dot:SetSize(5, 5)
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
            table.insert(self.labels, lbl)
        end
        lbl:ClearAllPoints()
        lbl:SetPoint(anchor or "TOP", self, "BOTTOMLEFT", x, y)
        lbl:SetText(text)
        lbl:Show()
    end

    function graph:Plot(history)
        self:Clear()
        if not history or #history < 2 then
            self:AddLabel(self.plotWidth/2, self.plotHeight/2, "Insufficient data for trend", "CENTER")
            return
        end

        local plotData = {}
        local maxPoints = math.min(#history, 14)
        for i = maxPoints, 1, -1 do table.insert(plotData, history[i]) end

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

        local pw, ph = self.plotWidth - 50, self.plotHeight - 40
        local ox, oy = 45, 25

        -- Y-axis
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
            self:DrawDot(x, y, 0.3, 1, 0.3)
            if i == 1 or i == #plotData or (i % 3 == 0) then
                self:AddLabel(x, oy - 12, ScanDayToDate(d.day), "TOP")
            end
            px, py = x, y
        end
    end

    return graph
end

-- ================================================================
-- ANALYTICS PANEL
-- ================================================================
function MarketSync.CreateAnalyticsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()

    -- Background textures
    local textures = {
        {"Bid-TopLeft", 256, 256, "TOPLEFT", 0, 0},
        {"Bid-Top", 320, 256, "TOPLEFT", 256, 0},
        {"Bid-TopRight", 256, 256, "TOPLEFT", 576, 0},
        {"Bid-BotLeft", 256, 256, "TOPLEFT", 0, -256},
        {"Bid-Bot", 320, 256, "TOPLEFT", 256, -256},
        {"Bid-BotRight", 256, 256, "TOPLEFT", 576, -256},
    }
    for _, t in ipairs(textures) do
        local tex = panel:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-" .. t[1])
        tex:SetSize(t[2], t[3]); tex:SetPoint(t[4], t[5], t[6])
    end

    -- Header info
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48); icon:SetPoint("TOPLEFT", 30, -25)
    panel.icon = icon

    local iconBorder = panel:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconBorder:SetSize(80, 80); iconBorder:SetPoint("CENTER", icon)

    local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 15, -2)
    panel.name = name

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Price Analytics & Data Historiography")

    -- Main Graph
    local graph = CreateGraph(panel, GRAPH_WIDTH, 280)
    graph:SetPoint("TOPLEFT", LEFT_MARGIN, CONTENT_TOP)
    panel.graph = graph

    local graphTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    graphTitle:SetPoint("TOP", graph, "TOP", 0, 15)
    graphTitle:SetText("|cffffd700Historical Trend (14 Days)|r")

    -- Metrics Side Panel
    local metricsBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    metricsBox:SetSize(350, 280); metricsBox:SetPoint("TOPLEFT", INFO_START_X, CONTENT_TOP)
    metricsBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    metricsBox:SetBackdropColor(0, 0, 0, 0.45)

    local function CreateMetric(y, label)
        local lbl = metricsBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 15, y)
        lbl:SetText(label)
        local val = metricsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("TOPRIGHT", -15, y)
        return val
    end

    panel.mPrice = CreateMetric(-15, "Current Market Value")
    panel.mStatus = CreateMetric(-40, "Status Confidence")
    panel.mAge = CreateMetric(-65, "Data Age (Last Scanned)")
    panel.mThreshold = CreateMetric(-80, "Global Freshness Limit")
    panel.mThreshold:SetText("3 Days")

    -- Divider
    local div = metricsBox:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(1, 0.82, 0, 0.2); div:SetSize(320, 1); div:SetPoint("TOP", 0, -105)

    local srcTitle = metricsBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcTitle:SetPoint("TOPLEFT", 15, -115)
    srcTitle:SetText("Source Distribution (Last 30 Scans)")

    panel.mPersonal = CreateMetric(-135, "Personal Scan Contribution")
    panel.mGuild = CreateMetric(-155, "Guild Data Contribution")
    
    local debugNote = metricsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall")
    debugNote:SetPoint("BOTTOMLEFT", 15, 15); debugNote:SetWidth(320); debugNote:SetJustifyH("LEFT")
    debugNote:SetText("|cff888888Note: 'Stale' records are automatically ignored by arbitrage calculators to protect profit margins from outdated data spikes.|r")

    -- Footer Buttons
    local backBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    backBtn:SetSize(75, 19); backBtn:SetPoint("BOTTOMRIGHT", -170, 14)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function() panel:Hide() end)

    function panel:ShowItem(dbKey, itemLink, itemName, iconTex, price)
        self.icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        self.name:SetText(itemLink or itemName or "Unknown")
        self.mPrice:SetText(FormatMoney(price))

        -- Data retrieval
        local history = MarketSync.GetItemHistory and MarketSync.GetItemHistory(dbKey) or {}
        self.graph:Plot(history)

        local latestAge = 0
        local personal, guild = 0, 0
        if #history > 0 then
            latestAge = MarketSync.GetCurrentScanDay() - history[1].day
            for i=1, math.min(#history, 30) do
                if history[i].source == "Personal" then personal = personal + 1 else guild = guild + 1 end
            end
        end

        local total = personal + guild
        self.mPersonal:SetText(total > 0 and (math.floor(personal/total*100).."%") or "0%")
        self.mGuild:SetText(total > 0 and (math.floor(guild/total*100).."%") or "0%")

        local ageStr = (latestAge == 0) and "Today" or (latestAge .. "d ago")
        if latestAge == 0 and history[1] and history[1].source == "Personal" then
            local pTime = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime
            if pTime and pTime > 0 then
                ageStr = "Today (" .. MarketSync.FormatRealmTime(pTime) .. ")"
            end
        end

        local isStale = (latestAge > 3)
        self.mAge:SetText((isStale and "|cffff4444" or "|cff00ff00") .. ageStr .. "|r")
        self.mStatus:SetText(isStale and "|cffff4444STALE|r" or "|cff00ff00GOOD|r")

        self:Show()
    end

    AnalyticsPanel = panel
    return panel
end

function MarketSync.ShowAnalytics(dbKey, itemLink, name, icon, price)
    if not AnalyticsPanel then return end

    -- Hide all tab content frames to prevent bleeds/overlaps
    if MarketSync.HideAllTabContent then
        MarketSync.HideAllTabContent()
    end

    AnalyticsPanel:ShowItem(dbKey, itemLink, name, icon, price)
end
