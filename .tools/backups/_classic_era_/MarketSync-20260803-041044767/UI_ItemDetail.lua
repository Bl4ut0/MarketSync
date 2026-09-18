-- =============================================================
-- MarketSync - Item Detail Dashboard
-- Centralized view for Price History, Notifications, and Processing
-- =============================================================

local ItemDetailPanel
local LEFT_MARGIN = 25
local CONTENT_TOP = -75
local GRAPH_WIDTH = 370
local INFO_START_X = 410

-- Helper for money formatting
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

local function FormatMoneyPlain(copper)
    if not copper or copper == 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return g .. "g" .. (s > 0 and (s .. "s") or "") end
    if s > 0 then return s .. "s" .. (c > 0 and (c .. "c") or "") end
    return c .. "c"
end

local function ScanDayToDate(scanDay)
    if not Auctionator or not Auctionator.Constants or not Auctionator.Constants.SCAN_DAY_0 then
        return "Day " .. scanDay
    end
    local timestamp = Auctionator.Constants.SCAN_DAY_0 + (scanDay * 86400)
    return date("%b %d", timestamp)
end

-- ================================================================
-- GRAPH RENDERER
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
        if not line then line = self:CreateLine(nil, "ARTWORK"); table.insert(self.lines, line) end
        line:SetThickness(thickness or 2)
        line:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
        line:SetStartPoint("BOTTOMLEFT", x1, y1)
        line:SetEndPoint("BOTTOMLEFT", x2, y2)
        line:Show()
    end

    function graph:DrawDot(x, y, r, g, b)
        self.dotCursor = self.dotCursor + 1
        local dot = self.dots[self.dotCursor]
        if not dot then dot = self:CreateTexture(nil, "OVERLAY"); table.insert(self.dots, dot) end
        dot:SetSize(5, 5); dot:SetColorTexture(r or 1, g or 1, b or 1, 1)
        dot:ClearAllPoints(); dot:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
        dot:Show()
    end

    function graph:DrawGridLine(y)
        self.gridCursor = self.gridCursor + 1
        local gl = self.gridLines[self.gridCursor]
        if not gl then gl = self:CreateTexture(nil, "BACKGROUND", nil, 3); table.insert(self.gridLines, gl) end
        gl:SetColorTexture(0.5, 0.5, 0.5, 0.15); gl:SetSize(self.plotWidth - 2, 1)
        gl:ClearAllPoints(); gl:SetPoint("LEFT", self, "BOTTOMLEFT", 1, y); gl:Show()
    end

    function graph:AddLabel(x, y, text, anchor)
        self.labelCursor = self.labelCursor + 1
        local lbl = self.labels[self.labelCursor]
        if not lbl then lbl = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightExtraSmall"); table.insert(self.labels, lbl) end
        lbl:ClearAllPoints(); lbl:SetPoint(anchor or "TOP", self, "BOTTOMLEFT", x, y); lbl:SetText(text); lbl:Show()
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
            if i == 1 or i == #plotData or (i % 3 == 0) then self:AddLabel(x, oy - 12, ScanDayToDate(d.day), "TOP") end
            px, py = x, y
        end
    end
    return graph
end

-- ================================================================
-- MAIN PANEL
-- ================================================================
function MarketSync.CreateItemDetailPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()

    -- Background
    for i = 1, 6 do
        local tex = panel:CreateTexture(nil, "BACKGROUND")
        local names = {"Bid-TopLeft", "Bid-Top", "Bid-TopRight", "Bid-BotLeft", "Bid-Bot", "Bid-BotRight"}
        tex:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-" .. names[i])
        if i <= 3 then
            tex:SetSize(i == 2 and 320 or 256, 256)
            tex:SetPoint("TOPLEFT", (i-1)*256 + (i>2 and 64 or 0), 0)
        else
            tex:SetSize((i-3) == 2 and 320 or 256, 256)
            tex:SetPoint("TOPLEFT", (i-4)*256 + ((i-3)>2 and 64 or 0), -256)
        end
    end

    -- Header
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48); icon:SetPoint("TOPLEFT", 30, -25)
    panel.icon = icon

    local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 15, -2)
    panel.name = name

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    desc:SetText("Single Item Dashboard | Price Trends & Alerts")

    -- Graph
    local graph = CreateGraph(panel, GRAPH_WIDTH, 260)
    graph:SetPoint("TOPLEFT", LEFT_MARGIN, CONTENT_TOP)
    panel.graph = graph

    -- Info Boxes
    local function CreateBox(x, y, w, h, title)
        local f = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        f:SetSize(w, h); f:SetPoint("TOPLEFT", x, y)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.45)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 5, 2)
        t:SetText(title)
        return f
    end

    local alertsBox = CreateBox(INFO_START_X, CONTENT_TOP, 350, 140, "Notification Settings")
    local valuesBox = CreateBox(INFO_START_X, CONTENT_TOP - 165, 350, 115, "Market Value Breakdown")

    -- --- ALERTS CONTROLS ---
    local function CreateLabel(parent, x, y, text)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", x, y); l:SetText(text)
        return l
    end

    CreateLabel(alertsBox, 15, -20, "Alert Threshold")
    local thresholdBox = CreateFrame("EditBox", nil, alertsBox, "InputBoxTemplate")
    thresholdBox:SetSize(120, 20); thresholdBox:SetPoint("TOPLEFT", 15, -35); thresholdBox:SetAutoFocus(false)
    panel.thresholdBox = thresholdBox

    CreateLabel(alertsBox, 150, -20, "Cooldown (s)")
    local cooldownBox = CreateFrame("EditBox", nil, alertsBox, "InputBoxTemplate")
    cooldownBox:SetSize(60, 20); cooldownBox:SetPoint("TOPLEFT", 150, -35); cooldownBox:SetAutoFocus(false); cooldownBox:SetNumeric(true)
    panel.cooldownBox = cooldownBox

    local enabledCheck = CreateFrame("CheckButton", nil, alertsBox, "InterfaceOptionsCheckButtonTemplate")
    enabledCheck:SetPoint("TOPLEFT", 230, -30)
    enabledCheck.Text:SetText("Enabled")
    panel.enabledCheck = enabledCheck

    CreateLabel(alertsBox, 15, -65, "Sound Override")
    local soundDropdown = CreateFrame("Frame", "MarketSyncItemDetailSoundDD", alertsBox, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", 0, -80)
    UIDropDownMenu_SetWidth(soundDropdown, 140)

    local function OnSoundSelect(self)
        panel.currentPerSound = self.arg1
        UIDropDownMenu_SetText(soundDropdown, self.value)
    end

    UIDropDownMenu_Initialize(soundDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Default (Global)"
        info.value = "Default"
        info.arg1 = nil
        info.func = OnSoundSelect
        info.checked = (panel.currentPerSound == nil)
        UIDropDownMenu_AddButton(info)

        info.text = "|cff888888Mute Item|r"
        info.value = "Mute"
        info.arg1 = 0
        info.func = OnSoundSelect
        info.checked = (panel.currentPerSound == 0)
        UIDropDownMenu_AddButton(info)

        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            info.text = s.name
            info.value = s.name
            info.arg1 = s.id
            info.func = OnSoundSelect
            info.checked = (panel.currentPerSound == s.id)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local btnSave = CreateFrame("Button", nil, alertsBox, "UIPanelButtonTemplate")
    btnSave:SetSize(80, 22); btnSave:SetPoint("BOTTOMRIGHT", -15, 15); btnSave:SetText("Save Alert")
    btnSave:SetScript("OnClick", function()
        if not panel.currentItemItemID then return end
        local tRaw = thresholdBox:GetText()
        local tVal = MarketSync.ParseGoldToCopper and MarketSync.ParseGoldToCopper(tRaw) or 0
        local cVal = tonumber(cooldownBox:GetText()) or 1800
        
        local req = {
            matchType = "itemID",
            matchValue = panel.currentItemItemID,
            displayName = panel.currentItemName,
            thresholdCopper = tVal,
            cooldownSec = cVal,
            enabled = enabledCheck:GetChecked()
        }
        if MarketSync.UpsertNotificationRequest then
            local saved = MarketSync.UpsertNotificationRequest(req)
            if saved then
                if not MarketSyncDB.PerNotificationSounds then MarketSyncDB.PerNotificationSounds = {} end
                MarketSyncDB.PerNotificationSounds[saved.id] = panel.currentPerSound
                print("|cff00ff00[MarketSync]|r Alert saved for " .. panel.currentItemName)
            end
        end
    end)

    -- --- VALUES BREAKDOWN ---
    local function CreateMetric(y, label)
        local lbl = valuesBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 15, y); lbl:SetText(label)
        local val = valuesBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("TOPRIGHT", -15, y)
        return val
    end

    panel.valCurrent = CreateMetric(-15, "Current Market Price")
    panel.valAvg30 = CreateMetric(-35, "30-Day Avg Price")
    panel.valDE = CreateMetric(-60, "Disenchant Value")
    panel.valProc = CreateMetric(-80, "Prospect/Mill Value")

    -- Footer
    local backBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    backBtn:SetSize(75, 19); backBtn:SetPoint("BOTTOMRIGHT", -170, 14); backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function() panel:Hide() end)

    function panel:RefreshItem(itemID)
        self.currentItemItemID = itemID
        local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        self.currentItemName = name or "Loading..."
        self.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        self.name:SetText(link or name or "Loading...")

        local history = MarketSync.GetItemHistory and MarketSync.GetItemHistory(tostring(itemID)) or {}
        self.graph:Plot(history)

        -- Load Notification
        local req = nil
        local realmDB = MarketSync.GetRealmDB()
        if realmDB and realmDB.NotificationRequests then
            for _, r in pairs(realmDB.NotificationRequests) do
                if r.matchType == "itemID" and tonumber(r.matchValue) == itemID then
                    req = r; break
                end
            end
        end

        if req then
            thresholdBox:SetText(MarketSync.FormatMoneyPlain and MarketSync.FormatMoneyPlain(req.thresholdCopper) or "0")
            cooldownBox:SetText(tostring(req.cooldownSec or 1800))
            enabledCheck:SetChecked(req.enabled ~= false)
            self.currentPerSound = MarketSyncDB.PerNotificationSounds and MarketSyncDB.PerNotificationSounds[req.id]
        else
            thresholdBox:SetText("0")
            cooldownBox:SetText("1800")
            enabledCheck:SetChecked(false)
            self.currentPerSound = nil
        end

        -- Sound DD text reset
        local soundText = "Default (Global)"
        if self.currentPerSound == 0 then soundText = "Mute Item" end
        if self.currentPerSound and self.currentPerSound > 0 then
            for _, s in ipairs(MarketSync.StandardSounds or {}) do
                if s.id == self.currentPerSound then soundText = s.name; break end
            end
        end
        UIDropDownMenu_SetText(soundDropdown, soundText)

        -- Prices
        local curPrice = 0
        if Auctionator and Auctionator.Database and Auctionator.Database.db then
            local d = Auctionator.Database.db[tostring(itemID)]
            curPrice = d and d.m or 0
        end
        self.valCurrent:SetText(FormatMoney(curPrice))
        
        local avg = 0
        if #history > 0 then
            for _, h in ipairs(history) do avg = avg + h.price end
            avg = avg / #history
        end
        self.valAvg30:SetText(FormatMoney(avg))

        -- DE / Proc
        -- Simplistic placeholder lookup - usually would call Processing.lua logic
        self.valDE:SetText("|cff888888N/A|r")
        self.valProc:SetText("|cff888888N/A|r")
        
        -- Try to find processing data if available
        if MarketSync.GetProcessingTargets then
            local procs = MarketSync.GetProcessingTargets()
            for _, p in ipairs(procs) do
                if p.itemID == itemID then
                    if p.processType == "DISENCHANT" then self.valDE:SetText(FormatMoney(p.yieldValue))
                    else self.valProc:SetText(FormatMoney(p.yieldValue)) end
                end
            end
        end

        self:Show()
    end

    ItemDetailPanel = panel
    return panel
end

function MarketSync.ShowItemDetail(itemID)
    if not ItemDetailPanel then return end
    if MarketSync.HideAllTabContent then MarketSync.HideAllTabContent() end
    ItemDetailPanel:RefreshItem(tonumber(itemID))
end
