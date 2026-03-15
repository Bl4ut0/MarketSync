-- =============================================================
-- MarketSync - Processing Panel UI
-- Box layout: top-left controls, lower-left custom presets, right results
-- =============================================================

local RESULTS_PER_PAGE = 8
local CUSTOM_ROWS = 2

local LEFT_X = 23
local TOP_Y = -105
local LEFT_W = 155
local LEFT_TOP_H = 188
local LEFT_BOTTOM_H = 109
local BOX_GAP = 8

local RESULTS_X = 195
local ROW_WIDTH = 632
local ROW_HEIGHT = 37

local PROCESS_OPTIONS_FALLBACK = { "ALL", "PROSPECT", "MILL", "DISENCHANT" }
local MODE_OPTIONS = {
    { key = "target", label = "Target Material" },
    { key = "process", label = "Process Scan" },
    { key = "craft", label = "Craft Profit" },
}

local function GetProcessOptions()
    if MarketSync.GetSupportedProcessingTypes then
        local supported = MarketSync.GetSupportedProcessingTypes(true)
        if type(supported) == "table" and #supported > 0 then
            return supported
        end
    end
    return PROCESS_OPTIONS_FALLBACK
end

local function IsSupportedProcessType(processType)
    if processType == nil or processType == "" then
        return true
    end
    if MarketSync.IsProcessingTypeSupported then
        return MarketSync.IsProcessingTypeSupported(processType)
    end
    local v = tostring(processType):upper()
    return v == "PROSPECT" or v == "MILL" or v == "DISENCHANT"
end

local function BuildDropdown(frameName, parent, width, initFunc)
    local dd = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width)
    dd._initFunc = initFunc
    UIDropDownMenu_Initialize(dd, initFunc)
    return dd
end

local function ReadNumber(editBox, defaultVal)
    local raw = (editBox:GetText() or "")
    local normalized = (raw:gsub(",", ""))
    local v = tonumber(normalized)
    if not v then return defaultVal end
    return v
end

local function TrimText(text)
    local raw = tostring(text or "")
    if strtrim then return strtrim(raw) end
    return raw:gsub("^%s+", ""):gsub("%s+$", "")
end

local function ResolveItemIDFromQuery(query)
    local raw = TrimText(query)
    if raw == "" then return nil end

    local linkedID = raw:match("|Hitem:(%d+):") or raw:match("item:(%d+)")
    if linkedID then
        return tonumber(linkedID)
    end

    local bracketed = raw:match("%[(.-)%]")
    if bracketed and bracketed ~= "" then
        raw = TrimText(bracketed)
    end

    local parenID = raw:match("%((%d+)%)$")
    if parenID then
        return tonumber(parenID)
    end

    local itemWordID = raw:match("^[Ii]tem%s+(%d+)$")
    if itemWordID then
        return tonumber(itemWordID)
    end

    local numericID = tonumber(raw)
    if numericID and numericID > 0 then
        return math.floor(numericID)
    end

    local _, linkByName = GetItemInfo(raw)
    if linkByName then
        local idFromLink = linkByName:match("item:(%d+)")
        if idFromLink then
            return tonumber(idFromLink)
        end
    end

    local needle = string.lower(raw)
    local targets = MarketSync.GetProcessingTargets and MarketSync.GetProcessingTargets() or {}

    for _, t in ipairs(targets) do
        local name = string.lower(t.name or "")
        if name == needle then
            return tonumber(t.itemID)
        end
    end

    for _, t in ipairs(targets) do
        local name = string.lower(t.name or "")
        if name ~= "" and string.find(name, needle, 1, true) then
            return tonumber(t.itemID)
        end
    end

    local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
    if type(cache) == "table" then
        local partialID = nil
        for id, info in pairs(cache) do
            local name = info and info.n and string.lower(tostring(info.n)) or ""
            if name ~= "" then
                if name == needle then
                    return tonumber(id)
                end
                if not partialID and string.find(name, needle, 1, true) then
                    partialID = tonumber(id)
                end
            end
        end
        if partialID then
            return partialID
        end
    end

    return nil
end

local function MoneyText(copper)
    if MarketSync.FormatMoney then
        return MarketSync.FormatMoney(math.max(0, math.floor(tonumber(copper) or 0)))
    end
    return tostring(math.floor(tonumber(copper) or 0))
end

local function FormatDelta(deltaCopper)
    local v = tonumber(deltaCopper)
    if not v then return "|cff888888-|r" end
    local absText = MoneyText(math.abs(v))
    if v >= 0 then return "|cff00ff00+" .. absText .. "|r" end
    return "|cffff4444-" .. absText .. "|r"
end

local function ColorLabel(text)
    return "|cffffd700" .. tostring(text or "") .. "|r"
end

local function ColorInfo(text)
    return "|cff66ccff" .. tostring(text or "") .. "|r"
end

local function ColorGood(text)
    return "|cff00ff00" .. tostring(text or "") .. "|r"
end

local function ColorWarn(text)
    return "|cffffaa00" .. tostring(text or "") .. "|r"
end

local function ColorBad(text)
    return "|cffff4444" .. tostring(text or "") .. "|r"
end

local function ColorMuted(text)
    return "|cffb0b0b0" .. tostring(text or "") .. "|r"
end

local function ResolveItemVisual(itemID, fallbackName)
    local id = tonumber(itemID)
    local name, link, _, _, _, _, _, _, _, icon
    if id then
        name, link, _, _, _, _, _, _, _, icon = GetItemInfo(id)
        if not icon and GetItemIcon then
            icon = GetItemIcon(id)
        end
    end
    name = name or fallbackName or ("Item " .. tostring(id or "?"))
    if not link and id then
        link = "|Hitem:" .. id .. "|h[" .. name .. "]|h"
    end
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    return name, link, icon
end

local function Truncate(text, maxLen)
    local s = tostring(text or "")
    if #s <= maxLen then return s end
    return s:sub(1, math.max(1, maxLen - 3)) .. "..."
end

local function SetControlVisible(control, visible)
    if not control then return end
    if visible then control:Show() else control:Hide() end
end

local function CreateBox(parent, x, y, width, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width, height)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    local function BorderPoint(anchorPoint, relPoint, ox, oy, w, h)
        local t = box:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetColorTexture(1, 0.84, 0, 0.25)
        t:SetPoint(anchorPoint, box, relPoint, ox, oy)
        t:SetSize(w, h)
    end

    BorderPoint("TOPLEFT", "TOPLEFT", 0, 0, width, 1)
    BorderPoint("BOTTOMLEFT", "BOTTOMLEFT", 0, 0, width, 1)
    BorderPoint("TOPLEFT", "TOPLEFT", 0, 0, 1, height)
    BorderPoint("TOPRIGHT", "TOPRIGHT", 0, 0, 1, height)

    return box
end

function MarketSync.CreateProcessingPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()

    panel.activeMode = "target"
    panel.selectedTargetID = nil
    panel.selectedProcess = nil
    panel.selectedProfession = nil
    panel.lastMode = nil
    panel.lastArbitrageResults = {}
    panel.lastCraftResults = {}
    panel.selectedCrafts = {}
    panel.selectedArbitrage = {}
    panel.displayRows = {}
    panel.page = 0
    panel.customPage = 0

    local leftTopBox = CreateBox(panel, LEFT_X, TOP_Y, LEFT_W, LEFT_TOP_H)
    local leftBottomBox = CreateBox(panel, LEFT_X, TOP_Y - LEFT_TOP_H - BOX_GAP, LEFT_W, LEFT_BOTTOM_H)
    local rightBox = CreateFrame("Frame", nil, panel)
    rightBox:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X - 2, -81)
    rightBox:SetSize(ROW_WIDTH + 4, 324)

    local leftTopTitle = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    leftTopTitle:SetPoint("TOPLEFT", 8, -8)
    leftTopTitle:SetText("|cffffd700Selection Controls|r")

    local modeButtons = {}
    local btnRun
    local ApplyDisplaySort
    local RunActiveMode

    local function UpdateRunButtonText()
        if not btnRun then return end
        if panel.activeMode == "process" then
            btnRun:SetText("Run Process")
        elseif panel.activeMode == "craft" then
            btnRun:SetText("Run Craft")
        else
            btnRun:SetText("Run Target")
        end
    end

    local function RefreshModeButtons()
        for _, def in ipairs(MODE_OPTIONS) do
            local btn = modeButtons[def.key]
            if btn then
                if def.key == panel.activeMode then
                    btn.selected:Show()
                    btn.text:SetTextColor(1.0, 0.87, 0.1)
                else
                    btn.selected:Hide()
                    btn.text:SetTextColor(1, 1, 1)
                end
            end
        end
    end

    local function CreateModeButton(def, yOffset)
        local btn = CreateFrame("Button", nil, leftTopBox)
        btn:SetSize(LEFT_W - 16, 18)
        btn:SetPoint("TOPLEFT", 8, yOffset)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
        bg:SetTexCoord(0, 0.53125, 0, 0.625)
        bg:SetAllPoints()

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints()

        local selected = btn:CreateTexture(nil, "ARTWORK")
        selected:SetColorTexture(1, 0.84, 0, 0.16)
        selected:SetAllPoints()
        selected:Hide()
        btn.selected = selected

        local txt = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        txt:SetPoint("CENTER")
        txt:SetText(def.label)
        btn.text = txt

        btn:SetScript("OnClick", function()
            if panel.activeMode ~= def.key then
                panel.activeMode = def.key
                panel.selectedCrafts = {}
                panel.selectedArbitrage = {}
                panel.displayRows = {}
                if panel.ClearResults then panel:ClearResults() end
                RefreshModeButtons()
                UpdateRunButtonText()
                if panel.RefreshModeControls then
                    panel:RefreshModeControls()
                end
            end
        end)

        return btn
    end

    modeButtons.target = CreateModeButton(MODE_OPTIONS[1], -26)
    modeButtons.process = CreateModeButton(MODE_OPTIONS[2], -48)
    modeButtons.craft = CreateModeButton(MODE_OPTIONS[3], -70)

    local targetLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    targetLabel:SetPoint("TOPLEFT", 8, -94)
    targetLabel:SetText("Target (Name/ID)")

    local targetInputBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    targetInputBox:SetSize(LEFT_W - 16, 18)
    targetInputBox:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", 8, -110)
    targetInputBox:SetAutoFocus(false)
    targetInputBox:SetText("")
    targetInputBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Enter target item", 1, 0.82, 0)
        GameTooltip:AddLine("Use item link, itemID, or a cached item name.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    targetInputBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(targetInputBox, {
            onInsertLink = function(box, text)
                local itemName = text and text:match("%[(.-)%]")
                if itemName and itemName ~= "" then
                    box:SetText(itemName)
                    return true
                end
                return false
            end
        })
    end

    local targetDropdown
    targetDropdown = BuildDropdown("MarketSyncProcessingTargetDropdown", leftTopBox, LEFT_W - 26, function(self, level)
        local resetInfo = UIDropDownMenu_CreateInfo()
        resetInfo.text = "Select material..."
        resetInfo.func = function()
            panel.selectedTargetID = nil
            targetInputBox:SetText("")
            UIDropDownMenu_SetText(targetDropdown, "Select material...")
        end
        UIDropDownMenu_AddButton(resetInfo, level)

        for _, t in ipairs(MarketSync.GetProcessingTargets and MarketSync.GetProcessingTargets() or {}) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = string.format("%s (%d)", t.name or ("Item " .. tostring(t.itemID)), t.itemID)
            opt.func = function()
                panel.selectedTargetID = t.itemID
                targetInputBox:SetText(t.name or ("Item " .. tostring(t.itemID)))
                UIDropDownMenu_SetText(targetDropdown, opt.text)
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    targetDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -8, -126)

    local processLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    processLabel:SetPoint("TOPLEFT", 8, -94)
    processLabel:SetText("Process")

    local processDropdown
    processDropdown = BuildDropdown("MarketSyncProcessingTypeDropdown", leftTopBox, LEFT_W - 26, function(self, level)
        if panel.selectedProcess and not IsSupportedProcessType(panel.selectedProcess) then
            panel.selectedProcess = nil
        end

        for _, p in ipairs(GetProcessOptions()) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = p
            opt.func = function()
                panel.selectedProcess = (p == "ALL") and nil or p
                UIDropDownMenu_SetText(processDropdown, p)
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    processDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -8, -104)
    UIDropDownMenu_SetText(processDropdown, "ALL")

    local professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions()) or {}
    panel.selectedProfession = professionOptions[1] or nil

    local professionLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    professionLabel:SetPoint("TOPLEFT", 8, -94)
    professionLabel:SetText("Profession")

    local professionDropdown
    professionDropdown = BuildDropdown("MarketSyncCraftProfDropdown", leftTopBox, LEFT_W - 26, function(self, level)
        professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions()) or professionOptions
        for _, p in ipairs(professionOptions) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = p
            opt.func = function()
                panel.selectedProfession = p
                UIDropDownMenu_SetText(professionDropdown, p)
                if panel.activeMode == "craft" and panel:IsShown() and RunActiveMode then
                    RunActiveMode()
                end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    professionDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -8, -104)
    UIDropDownMenu_SetText(professionDropdown, panel.selectedProfession or "No professions")

    local marginLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    marginLabel:SetPoint("TOPLEFT", 8, -138)
    marginLabel:SetText("Margin %")

    local marginBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    marginBox:SetSize(45, 18)
    marginBox:SetPoint("LEFT", marginLabel, "RIGHT", 8, 0)
    marginBox:SetAutoFocus(false)
    marginBox:SetNumeric(true)
    marginBox:SetText("10")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(marginBox)
    end

    local minMarginLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    minMarginLabel:SetPoint("TOPLEFT", 8, -138)
    minMarginLabel:SetText("Min Craft g")

    local minMarginGoldBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    minMarginGoldBox:SetSize(45, 18)
    minMarginGoldBox:SetPoint("LEFT", minMarginLabel, "RIGHT", 8, 0)
    minMarginGoldBox:SetAutoFocus(false)
    minMarginGoldBox:SetNumeric(true)
    minMarginGoldBox:SetText("5")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(minMarginGoldBox)
    end

    btnRun = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnRun:SetSize(100, 22)
    btnRun:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -238, -44)

    local btnExport = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnExport:SetSize(100, 22)
    btnExport:SetPoint("LEFT", btnRun, "RIGHT", 6, 0)
    btnExport:SetText("Export")

    local btnTrack = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTrack:SetSize(100, 22)
    btnTrack:SetPoint("LEFT", btnExport, "RIGHT", 6, 0)
    btnTrack:SetText("Track")

    local statusSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusSummary:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -66)
    statusSummary:SetWidth(320)
    statusSummary:SetJustifyH("RIGHT")
    statusSummary:SetText("|cff888888Ready|r")

    panel.sortField = "valueSort"
    panel.sortAscending = false

    local colDefs = {
        { name = "Item",   width = 244, sortKey = "itemSort"   },
        { name = "Type/Lvl", width = 58,  sortKey = "typeSort"   },
        { name = "Value",  width = 72,  sortKey = "valueSort"  },
        { name = "Max",    width = 72,  sortKey = "maxSort"    },
        { name = "Live",   width = 66,  sortKey = "liveSort"   },
        { name = "Delta",  width = 66,  sortKey = "deltaSort"  },
        { name = "Status", width = 58,  sortKey = "statusSort" },
    }

    panel.headerButtons = {}
    local function RefreshHeaderArrows()
        for _, h in ipairs(panel.headerButtons) do
            if h.sortKey and h.sortKey == panel.sortField then
                h.arrow:Show()
                if panel.sortAscending then
                    h.arrow:SetTexCoord(0, 0.5625, 1.0, 0)
                else
                    h.arrow:SetTexCoord(0, 0.5625, 0, 1.0)
                end
            else
                h.arrow:Hide()
            end
        end
    end

    local colX = 193
    for i, col in ipairs(colDefs) do
        local hdr = CreateFrame("Button", nil, panel)
        hdr:SetSize(col.width, 19)
        hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", colX, -81)
        hdr.sortKey = col.sortKey

        local hleft = hdr:CreateTexture(nil, "BACKGROUND")
        hleft:SetTexture("Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
        hleft:SetSize(5, 19)
        hleft:SetPoint("TOPLEFT")
        hleft:SetTexCoord(0, 0.078125, 0, 0.59375)

        local hright = hdr:CreateTexture(nil, "BACKGROUND")
        hright:SetTexture("Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
        hright:SetSize(4, 19)
        hright:SetPoint("TOPRIGHT")
        hright:SetTexCoord(0.90625, 0.96875, 0, 0.59375)

        local hmid = hdr:CreateTexture(nil, "BACKGROUND")
        hmid:SetTexture("Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
        hmid:SetPoint("LEFT", hleft, "RIGHT")
        hmid:SetPoint("RIGHT", hright, "LEFT")
        hmid:SetHeight(19)
        hmid:SetTexCoord(0.078125, 0.90625, 0, 0.59375)

        local htxt = hdr:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        htxt:SetPoint("LEFT", 8, 0)
        htxt:SetText(col.name)

        local arrow = hdr:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        arrow:SetSize(9, 8)
        arrow:SetPoint("LEFT", htxt, "RIGHT", 3, -2)
        arrow:SetTexCoord(0, 0.5625, 0, 1.0)
        arrow:Hide()
        hdr.arrow = arrow

        local hhl = hdr:CreateTexture(nil, "HIGHLIGHT")
        hhl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        hhl:SetBlendMode("ADD")
        hhl:SetPoint("LEFT", 0, 0)
        hhl:SetPoint("RIGHT", 4, 0)
        hhl:SetHeight(24)

        if col.sortKey then
            hdr:SetScript("OnClick", function()
                if panel.sortField == col.sortKey then
                    panel.sortAscending = not panel.sortAscending
                else
                    panel.sortField = col.sortKey
                    panel.sortAscending = true
                end
                RefreshHeaderArrows()
                if ApplyDisplaySort then
                    ApplyDisplaySort()
                end
            end)
        end

        panel.headerButtons[i] = hdr
        colX = colX + col.width - 2
    end
    RefreshHeaderArrows()

    panel.resultRows = {}
    for i = 1, RESULTS_PER_PAGE do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(ROW_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", RESULTS_X, -107 - ((i - 1) * ROW_HEIGHT))

        local iconButton = CreateFrame("Button", nil, row)
        iconButton:SetSize(32, 32)
        iconButton:SetPoint("TOPLEFT", 0, -3)
        local iconTex = iconButton:CreateTexture(nil, "BORDER")
        iconTex:SetAllPoints()
        row.iconTex = iconTex

        local iconBorder = iconButton:CreateTexture(nil, "ARTWORK")
        iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        iconBorder:SetSize(60, 60)
        iconBorder:SetPoint("CENTER")

        local nameLeft = row:CreateTexture(nil, "BACKGROUND")
        nameLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameLeft:SetSize(10, 32)
        nameLeft:SetPoint("LEFT", 34, 2)
        nameLeft:SetTexCoord(0, 0.078125, 0, 1.0)

        local nameRight = row:CreateTexture(nil, "BACKGROUND")
        nameRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameRight:SetSize(10, 32)
        nameRight:SetPoint("LEFT", 617, 2)
        nameRight:SetTexCoord(0.75, 0.828125, 0, 1.0)

        local nameMid = row:CreateTexture(nil, "BACKGROUND")
        nameMid:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameMid:SetPoint("LEFT", nameLeft, "RIGHT")
        nameMid:SetPoint("RIGHT", nameRight, "LEFT")
        nameMid:SetHeight(32)
        nameMid:SetTexCoord(0.078125, 0.75, 0, 1.0)

        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.nameText:SetPoint("TOPLEFT", 43, -3)
        row.nameText:SetWidth(198)
        row.nameText:SetJustifyH("LEFT")

        row.typeText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.typeText:SetPoint("TOPLEFT", 246, -3)
        row.typeText:SetWidth(50)
        row.typeText:SetJustifyH("LEFT")

        row.valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.valueText:SetPoint("TOPLEFT", 304, -3)
        row.valueText:SetWidth(60)
        row.valueText:SetJustifyH("RIGHT")

        row.maxText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.maxText:SetPoint("TOPLEFT", 374, -3)
        row.maxText:SetWidth(60)
        row.maxText:SetJustifyH("RIGHT")

        row.liveText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.liveText:SetPoint("TOPLEFT", 442, -3)
        row.liveText:SetWidth(54)
        row.liveText:SetJustifyH("RIGHT")

        row.deltaText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.deltaText:SetPoint("TOPLEFT", 506, -3)
        row.deltaText:SetWidth(54)
        row.deltaText:SetJustifyH("RIGHT")

        row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.statusText:SetPoint("TOPLEFT", 570, -3)
        row.statusText:SetWidth(54)
        row.statusText:SetJustifyH("LEFT")

        local selectedBg = row:CreateTexture(nil, "BACKGROUND")
        selectedBg:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        selectedBg:SetVertexColor(1, 0.8, 0, 0.5)
        selectedBg:SetBlendMode("ADD")
        selectedBg:SetAllPoints(row)
        selectedBg:Hide()
        row.selectedBg = selectedBg

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
        highlight:SetBlendMode("ADD")
        highlight:SetSize(594, 32)
        highlight:SetPoint("TOPLEFT", 33, -3)
        highlight:SetTexCoord(0, 1.0, 0, 0.578125)

        local function ShowRowTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            local tooltipSet = false
            if row.link then
                -- Try SetHyperlink first; if the item isn't cached it may fail
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
                if ok then
                    tooltipSet = true
                elseif row.itemID then
                    -- Fallback: use item:ID which WoW can request-and-show
                    local ok2 = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(row.itemID))
                    tooltipSet = ok2
                end
            elseif row.itemID then
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(row.itemID))
                tooltipSet = ok
            end
            if not tooltipSet then
                -- Pure text fallback for completely unresolved items
                local name = (row.nameText and row.nameText.GetText and row.nameText:GetText()) or tostring(row.itemID or "Unknown")
                GameTooltip:SetText(name, 1, 1, 1)
            end
            if row.detailLines and #row.detailLines > 0 then
                GameTooltip:AddLine(" ")
                for _, line in ipairs(row.detailLines) do
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            elseif row.detailText and row.detailText ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(row.detailText, 0.85, 0.85, 0.85, true)
            end
            GameTooltip:Show()
        end

        iconButton:SetScript("OnEnter", function(self)
            row:LockHighlight()
            ShowRowTooltip(self)
        end)
        iconButton:SetScript("OnLeave", function()
            row:UnlockHighlight()
            GameTooltip:Hide()
        end)
        local function HandleRowClick(button)
            if row.link and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(row.link)
                return
            end
            
            local isCraft = (panel.lastMode == "craft")
            local idKey = isCraft and row.craftID or row.itemID
            local selectTable = isCraft and panel.selectedCrafts or panel.selectedArbitrage
            
            if not idKey then return end

            if button == "RightButton" then
                local menuFrame = CreateFrame("Frame", "MarketSyncProcContextMenu", UIParent, "UIDropDownMenuTemplate")
                local isSelected = selectTable[idKey] and true or false
                UIDropDownMenu_Initialize(menuFrame, function(_, level)
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = isSelected and "Deselect" or "Select"
                    info.notCheckable = true
                    info.func = function()
                        selectTable[idKey] = not isSelected and true or nil
                        row.selectedBg:SetShown(not isSelected)
                        if row.data then row.data.isSelected = not isSelected end
                    end
                    UIDropDownMenu_AddButton(info, level)

                    info = UIDropDownMenu_CreateInfo()
                    info.text = "History"
                    info.notCheckable = true
                    info.func = function()
                        if MarketSync.ShowItemHistory then
                            local hDBKey = row.itemID and tostring(row.itemID) or nil
                            if hDBKey then
                                local hPrice = row.data and row.data.liveSort or nil
                                MarketSync.ShowItemHistory(hDBKey, row.link, row.nameText:GetText(), row.iconTex:GetTexture(), hPrice)
                            end
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)

                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Analytics"
                    info.notCheckable = true
                    info.func = function()
                        if MarketSync.ShowAnalytics then
                            local hDBKey = row.itemID and tostring(row.itemID) or nil
                            if hDBKey then
                                local hPrice = row.data and row.data.liveSort or nil
                                MarketSync.ShowAnalytics(hDBKey, row.link, row.nameText:GetText(), row.iconTex:GetTexture(), hPrice)
                            end
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)

                    info = UIDropDownMenu_CreateInfo()
                    info.text = ""
                    info.isTitle = true
                    info.notCheckable = true
                    UIDropDownMenu_AddButton(info, level)

                    info = UIDropDownMenu_CreateInfo()
                    info.text = "Cancel"
                    info.notCheckable = true
                    info.func = function() end
                    UIDropDownMenu_AddButton(info, level)
                end, "MENU")
                ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
                return
            end

            if selectTable[idKey] then
                selectTable[idKey] = nil
                row.selectedBg:Hide()
                if row.data then row.data.isSelected = false end
            else
                selectTable[idKey] = true
                row.selectedBg:Show()
                if row.data then row.data.isSelected = true end
            end
        end

        iconButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        iconButton:SetScript("OnClick", function(self, button) HandleRowClick(button) end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button) HandleRowClick(button) end)
        
        row:SetScript("OnEnter", function(self)
            self:LockHighlight()
            ShowRowTooltip(self)
        end)
        row:SetScript("OnLeave", function(self)
            self:UnlockHighlight()
            GameTooltip:Hide()
        end)

        row:Hide()
        panel.resultRows[i] = row
    end


    panel.noResultsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noResultsText:SetPoint("TOP", parent, "TOP", 115, -200)
    panel.noResultsText:SetText("|cff888888Run a mode to see results.|r")
    panel.noResultsText:Show()

    local prevBtn = CreateFrame("Button", nil, panel)
    prevBtn:SetSize(28, 28)
    prevBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -50, 11)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(28, 28)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")

    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.pageText:SetPoint("BOTTOMRIGHT", prevBtn, "BOTTOMLEFT", -8, 9)
    panel.pageText:SetText("0 results")

    local btnResyncProf = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnResyncProf:SetSize(118, 20)
    btnResyncProf:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RESULTS_X + 2, 15)
    btnResyncProf:SetText("Resync Profs")
    btnResyncProf:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Resync profession cache", 1, 0.82, 0)
        GameTooltip:AddLine("Refreshes cache for the profession window currently open.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Open each crafting profession and press this once per profession.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    btnResyncProf:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local customTitle = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    customTitle:SetPoint("TOPLEFT", 8, -8)
    customTitle:SetText("|cffffd700Custom Selections|r")

    local customNameLabel = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    customNameLabel:SetPoint("TOPLEFT", 8, -26)
    customNameLabel:SetText("Preset")

    local customNameBox = CreateFrame("EditBox", nil, leftBottomBox, "InputBoxTemplate")
    customNameBox:SetSize(88, 18)
    customNameBox:SetPoint("LEFT", customNameLabel, "RIGHT", 6, 0)
    customNameBox:SetAutoFocus(false)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(customNameBox)
    end

    local btnSaveCustom = CreateFrame("Button", nil, leftBottomBox, "UIPanelButtonTemplate")
    btnSaveCustom:SetSize(50, 18)
    btnSaveCustom:SetPoint("TOPLEFT", 8, -46)
    btnSaveCustom:SetText("Save")

    local customRows = {}
    for i = 1, CUSTOM_ROWS do
        local row = CreateFrame("Frame", nil, leftBottomBox)
        row:SetSize(LEFT_W - 12, 18)
        row:SetPoint("TOPLEFT", 6, -66 - ((i - 1) * 18))

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.04)
        end

        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", 0, 0)
        row.nameText:SetWidth(96)
        row.nameText:SetJustifyH("LEFT")

        row.applyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.applyBtn:SetSize(22, 16)
        row.applyBtn:SetPoint("LEFT", 100, 0)
        row.applyBtn:SetText("L")

        row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.deleteBtn:SetSize(22, 16)
        row.deleteBtn:SetPoint("LEFT", 126, 0)
        row.deleteBtn:SetText("X")

        row:Hide()
        customRows[i] = row
    end

    panel.customPageText = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.customPageText:SetPoint("BOTTOMLEFT", 8, 8)
    panel.customPageText:SetText("1/1")

    local customPrevBtn = CreateFrame("Button", nil, leftBottomBox, "UIPanelButtonTemplate")
    customPrevBtn:SetSize(22, 16)
    customPrevBtn:SetPoint("BOTTOMRIGHT", -28, 6)
    customPrevBtn:SetText("<")

    local customNextBtn = CreateFrame("Button", nil, leftBottomBox, "UIPanelButtonTemplate")
    customNextBtn:SetSize(22, 16)
    customNextBtn:SetPoint("LEFT", customPrevBtn, "RIGHT", 4, 0)
    customNextBtn:SetText(">")

    local function ModeLabel(mode)
        if mode == "process" then return "Process Scan" end
        if mode == "craft" then return "Craft Profit" end
        return "Target Material"
    end

    local function FindTargetName(itemID)
        local id = tonumber(itemID)
        if not id then return nil end

        local targets = MarketSync.GetProcessingTargets and MarketSync.GetProcessingTargets() or {}
        for _, t in ipairs(targets) do
            if tonumber(t.itemID) == id then
                return t.name or ("Item " .. tostring(id))
            end
        end

        local name = GetItemInfo(id)
        return name or ("Item " .. tostring(id))
    end

    local function RefreshDropdownLabels()
        if panel.selectedTargetID then
            local id = tonumber(panel.selectedTargetID)
            local targetText = string.format("%s (%d)", FindTargetName(id) or ("Item " .. tostring(id)), id)
            UIDropDownMenu_SetText(targetDropdown, targetText)
        else
            UIDropDownMenu_SetText(targetDropdown, "Select material...")
        end

        if panel.selectedProcess and not IsSupportedProcessType(panel.selectedProcess) then
            panel.selectedProcess = nil
        end
        UIDropDownMenu_SetText(processDropdown, panel.selectedProcess or "ALL")
        UIDropDownMenu_SetText(professionDropdown, panel.selectedProfession or "No professions")
    end

    local function RefreshProfessionOptions()
        professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions()) or professionOptions
        if (not panel.selectedProfession or panel.selectedProfession == "") and #professionOptions > 0 then
            panel.selectedProfession = professionOptions[1]
        end

        local professionValid = false
        for _, p in ipairs(professionOptions) do
            if p == panel.selectedProfession then
                professionValid = true
                break
            end
        end
        if not professionValid and #professionOptions > 0 then
            panel.selectedProfession = professionOptions[1]
        end
        if #professionOptions == 0 then
            panel.selectedProfession = nil
        end

        if professionDropdown and professionDropdown._initFunc then
            UIDropDownMenu_Initialize(professionDropdown, professionDropdown._initFunc)
        end
        UIDropDownMenu_SetText(professionDropdown, panel.selectedProfession or "No professions")
    end

    function panel:RefreshModeControls()
        local isTarget = panel.activeMode == "target"
        local isProcess = panel.activeMode == "process"
        local isCraft = panel.activeMode == "craft"

        SetControlVisible(targetLabel, isTarget)
        SetControlVisible(targetInputBox, isTarget)
        SetControlVisible(targetDropdown, false)

        SetControlVisible(processLabel, isProcess)
        SetControlVisible(processDropdown, isProcess)

        SetControlVisible(professionLabel, isCraft)
        SetControlVisible(professionDropdown, isCraft)

        SetControlVisible(marginLabel, (isTarget or isProcess))
        SetControlVisible(marginBox, (isTarget or isProcess))

        SetControlVisible(minMarginLabel, isCraft)
        SetControlVisible(minMarginGoldBox, isCraft)
    end

    local function SetNoResultsMessage(message)
        panel.noResultsMessage = message or "Run a mode to see results."
        if panel.noResultsText then
            panel.noResultsText:SetText("|cff888888" .. panel.noResultsMessage .. "|r")
        end
    end

    local function UpdateResultRows()
        local rows = panel.displayRows or {}
        local total = #rows
        local totalPages = math.max(1, math.ceil(total / RESULTS_PER_PAGE))
        if panel.page < 0 then panel.page = 0 end
        if panel.page > (totalPages - 1) then panel.page = totalPages - 1 end

        local firstIndex = (panel.page * RESULTS_PER_PAGE) + 1
        for i = 1, RESULTS_PER_PAGE do
            local row = panel.resultRows[i]
            local data = rows[firstIndex + i - 1]
            if row and data then
                row.link = data.link
                row.detailText = data.detail
                row.detailLines = data.detailLines
                row.itemID = data.itemID

                row.iconTex:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.nameText:SetText(data.nameText or "")
                row.typeText:SetText(data.typeText or "")
                row.valueText:SetText(data.valueText or "-")
                row.maxText:SetText(data.maxText or "-")
                row.liveText:SetText(data.liveText or "-")
                row.deltaText:SetText(data.deltaText or "-")
                row.statusText:SetText(data.statusText or "")
                
                row.data = data
                row.craftID = data.recipeName
                if row.selectedBg then
                    row.selectedBg:SetShown(data.isSelected and true or false)
                end

                row:Show()
            elseif row then
                row.link = nil
                row.detailText = nil
                row.detailLines = nil
                row.itemID = nil
                row.data = nil
                row.craftID = nil
                if row.selectedBg then
                    row.selectedBg:Hide()
                end
                row:Hide()
            end
        end

        local pageShown = (total > 0) and (panel.page + 1) or 1
        panel.pageText:SetText(string.format("%d results (Page %d/%d)", total, pageShown, totalPages))

        prevBtn:SetEnabled(panel.page > 0)
        nextBtn:SetEnabled(total > 0 and panel.page < (totalPages - 1))

        if total > 0 then
            panel.noResultsText:Hide()
        else
            panel.noResultsText:Show()
        end
    end

    function panel:ClearResults()
        SetNoResultsMessage("Run a mode to see results.")
        UpdateResultRows()
    end

    ApplyDisplaySort = function()
        if not panel.displayRows or #panel.displayRows <= 1 then
            UpdateResultRows()
            return
        end

        local key = panel.sortField or "valueSort"
        local asc = panel.sortAscending == true

        table.sort(panel.displayRows, function(a, b)
            local av = a and a[key]
            local bv = b and b[key]

            local at = type(av)
            local bt = type(bv)
            if at == "number" or bt == "number" then
                av = tonumber(av) or -math.huge
                bv = tonumber(bv) or -math.huge
                if av == bv then
                    local an = tostring(a and a.nameText or "")
                    local bn = tostring(b and b.nameText or "")
                    if asc then return an < bn else return an > bn end
                end
                if asc then return av < bv else return av > bv end
            end

            av = tostring(av or "")
            bv = tostring(bv or "")
            if av == bv then
                local an = tostring(a and a.nameText or "")
                local bn = tostring(b and b.nameText or "")
                if asc then return an < bn else return an > bn end
            end
            if asc then return av < bv else return av > bv end
        end)

        panel.page = 0
        UpdateResultRows()
    end

    local function BuildArbitrageDisplay(arbitrageResults)
        local rows = {}
        local marginPct = ReadNumber(marginBox, 10)
        marginPct = math.max(0, math.min(99, marginPct))
        local marginMult = math.max(0.01, 1 - (marginPct / 100))

        for _, r in ipairs(arbitrageResults or {}) do
            local itemName, itemLink, icon = ResolveItemVisual(r.inputItemID, r.inputName)
            local livePrice = tonumber(r.livePrice) or 0
            local maxBuy = tonumber(r.maxBuyPerUnit) or 0
            local evPerUnit = tonumber(r.evPerUnit)
            if not evPerUnit then
                evPerUnit = math.floor((maxBuy / marginMult) + 0.5)
            end
            local delta = maxBuy - livePrice

            local status
            local statusRank = 0
            if r.liveStale or r.evStale or r.targetStale then
                status = "|cffffaa00STALE|r"
                statusRank = 2
            elseif livePrice <= 0 then
                status = "|cff888888NO AH|r"
                statusRank = 1
            elseif r.profitable then
                status = "|cff00ff00GOOD|r"
                statusRank = 3
            else
                status = "|cffff4444MISS|r"
                statusRank = 0
            end

            local detailLines = {}
            if r.targetName then
                detailLines[#detailLines + 1] = string.format("%s %s  %s %s",
                    ColorLabel("Target:"), ColorInfo(r.targetName), ColorMuted("@"), ColorGood(MoneyText(r.targetPrice or 0)))
            end
            if r.expectedTarget then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%.2f|r",
                    ColorLabel("Expected/Action:"), tonumber(r.expectedTarget) or 0)
            end
            if r.evPerAction then
                detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("EV/Action:"), ColorGood(MoneyText(r.evPerAction)))
            end
            if r.stackSize and tonumber(r.stackSize) and tonumber(r.stackSize) > 1 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%d|r", ColorLabel("Stack Size:"), tonumber(r.stackSize))
            end
            if r.missingOutputs and tonumber(r.missingOutputs) and tonumber(r.missingOutputs) > 0 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%d|r", ColorWarn("Missing priced outputs:"), tonumber(r.missingOutputs))
            end
            if r.liveStale or r.evStale or r.targetStale then
                detailLines[#detailLines + 1] = ColorWarn("One or more prices are stale.")
            end

            rows[#rows + 1] = {
                itemID = r.inputItemID,
                link = itemLink,
                icon = icon,
                nameText = Truncate(itemName, 24),
                typeText = Truncate(tostring(r.processType or "-"), 8),
                valueText = MoneyText(evPerUnit),
                maxText = MoneyText(maxBuy),
                liveText = (livePrice > 0) and MoneyText(livePrice) or "-",
                deltaText = FormatDelta(delta),
                statusText = status,
                itemSort = string.lower(itemName or ""),
                typeSort = string.lower(tostring(r.processType or "")),
                valueSort = tonumber(evPerUnit) or 0,
                maxSort = tonumber(maxBuy) or 0,
                liveSort = tonumber(livePrice) or 0,
                deltaSort = tonumber(delta) or 0,
                statusSort = statusRank,
                detail = table.concat(detailLines, "\n"),
                detailLines = detailLines,
                trackItemID = r.inputItemID,
                trackName = itemName,
                trackThreshold = maxBuy,
                isSelected = panel.selectedArbitrage and panel.selectedArbitrage[r.inputItemID] or false,
            }
        end

        return rows
    end

    local function BuildCraftDisplay(craftResults)
        local rows = {}

        for _, c in ipairs(craftResults or {}) do
            local outputName = c.outputName or c.recipeName or ("Item " .. tostring(c.outputItemID or "?"))
            local itemName, itemLink, icon = ResolveItemVisual(c.outputItemID, outputName)
            local revenue = tonumber(c.revenue) or 0
            local craftCost = tonumber(c.craftCost) or 0
            local margin = tonumber(c.margin) or 0
            local maxSpend = tonumber(c.maxCraftCost) or 0
            local capDelta = maxSpend - craftCost

            local status
            local statusRank = 0
            if c.outputStale or c.hasStaleMat then
                status = "|cffffaa00STALE|r"
                statusRank = 2
            elseif c.meetsMargin then
                status = "|cff00ff00GOOD|r"
                statusRank = 3
            else
                status = "|cffff4444MISS|r"
                statusRank = 0
            end

            local detailLines = {}
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Recipe:"), ColorInfo(outputName))
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Revenue:"), ColorGood(MoneyText(revenue)))
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r", ColorLabel("Cost:"), MoneyText(craftCost))

            local marginText = MoneyText(math.abs(margin))
            if margin >= 0 then
                marginText = "+" .. marginText
            else
                marginText = "-" .. marginText
            end
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Margin:"), (margin >= 0) and ColorGood(marginText) or ColorBad(marginText))

            if maxSpend > 0 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r", ColorLabel("Max Spend:"), MoneyText(maxSpend))
            end

            local mats = c.matsDetailed or {}
            for i, mat in ipairs(mats) do
                if i > 4 then
                    detailLines[#detailLines + 1] = ColorMuted("...")
                    break
                end
                local matName = ResolveItemVisual(mat.itemID)
                local qty = tonumber(mat.qty) or 1
                local matPriceText = MoneyText(mat.price or 0)
                local priceColor = mat.stale and ColorWarn(matPriceText) or "|cffffffff" .. matPriceText .. "|r"
                detailLines[#detailLines + 1] = string.format("%s x%d %s %s",
                    ColorMuted(matName), qty, ColorMuted("@"), priceColor)
            end

            rows[#rows + 1] = {
                recipeName = outputName,
                itemID = c.outputItemID,
                link = itemLink,
                icon = icon,
                nameText = Truncate(itemName, 24),
                typeText = c.recipeIndex and ("Lvl " .. tostring(c.recipeIndex)) or "Craft",
                valueText = MoneyText(margin),
                maxText = MoneyText(maxSpend),
                liveText = MoneyText(craftCost),
                deltaText = FormatDelta(capDelta),
                statusText = status,
                itemSort = string.lower(itemName or ""),
                typeSort = c.recipeIndex and -tonumber(c.recipeIndex) or 0,
                valueSort = tonumber(margin) or 0,
                maxSort = tonumber(maxSpend) or 0,
                liveSort = tonumber(craftCost) or 0,
                deltaSort = tonumber(capDelta) or 0,
                statusSort = statusRank,
                detail = table.concat(detailLines, "\n"),
                detailLines = detailLines,
                isSelected = panel.selectedCrafts and panel.selectedCrafts[outputName] or false,
            }
        end

        return rows
    end

    RunActiveMode = function()
        panel.page = 0

        if panel.activeMode == "target" then
            local targetQuery = TrimText(targetInputBox:GetText())
            if targetQuery ~= "" then
                local resolvedID = ResolveItemIDFromQuery(targetQuery)
                if resolvedID then
                    panel.selectedTargetID = resolvedID
                else
                    panel.selectedTargetID = nil
                    statusSummary:SetText("|cffff4444Target not found. Enter item link, itemID, or cached name.|r")
                    panel.displayRows = {}
                    SetNoResultsMessage("Unknown target. Use an item link, itemID, or a cached item name.")
                    UpdateResultRows()
                    return
                end
            end

            if not panel.selectedTargetID then
                statusSummary:SetText("|cffff4444Enter a target item name, link, or ID first.|r")
                panel.displayRows = {}
                SetNoResultsMessage("Enter a target item name/link/ID, then click Run Target.")
                UpdateResultRows()
                return
            end

            local marginPct = math.floor(ReadNumber(marginBox, 10) + 0.5)
            marginPct = math.max(0, math.min(99, marginPct))
            marginBox:SetText(tostring(marginPct))

            local results = MarketSync.FindArbitrageByTarget and MarketSync.FindArbitrageByTarget(panel.selectedTargetID, marginPct) or {}
            panel.lastMode = "target"
            panel.lastArbitrageResults = results
            panel.lastCraftResults = {}
            panel.displayRows = BuildArbitrageDisplay(results)

            local targetName = FindTargetName(panel.selectedTargetID) or ("Item " .. tostring(panel.selectedTargetID))
            statusSummary:SetText(string.format("|cff00ff00%s|r: %d result(s)", targetName, #panel.displayRows))
            local hasTargetDefinition = false
            for _, def in pairs(MarketSync.ProcessingData or {}) do
                for _, y in ipairs(def.yields or {}) do
                    if tonumber(y.itemID) == tonumber(panel.selectedTargetID) then
                        hasTargetDefinition = true
                        break
                    end
                end
                if hasTargetDefinition then break end
            end
            if hasTargetDefinition then
                SetNoResultsMessage("No target arbitrage rows met the current inputs.")
            else
                SetNoResultsMessage("Target has no processing definitions in the current dataset yet.")
            end
            ApplyDisplaySort()
            return
        end

        if panel.activeMode == "process" then
            local marginPct = math.floor(ReadNumber(marginBox, 10) + 0.5)
            marginPct = math.max(0, math.min(99, marginPct))
            marginBox:SetText(tostring(marginPct))

            local results = MarketSync.FindArbitrageByProcess and MarketSync.FindArbitrageByProcess(panel.selectedProcess, marginPct) or {}
            panel.lastMode = "process"
            panel.lastArbitrageResults = results
            panel.lastCraftResults = {}
            panel.displayRows = BuildArbitrageDisplay(results)

            statusSummary:SetText(string.format("|cff00ff00%s|r: %d result(s)", panel.selectedProcess or "ALL", #panel.displayRows))
            SetNoResultsMessage("No process-scan rows met the current inputs.")
            ApplyDisplaySort()
            return
        end

        local profession = panel.selectedProfession
        if not profession or profession == "" then
            statusSummary:SetText("|cffff4444Select a profession first.|r")
            panel.displayRows = {}
            SetNoResultsMessage("Select a profession, then click Run Craft.")
            UpdateResultRows()
            return
        end

        local minMarginGold = ReadNumber(minMarginGoldBox, 5)
        minMarginGold = math.max(0, minMarginGold)
        minMarginGoldBox:SetText(tostring(math.floor(minMarginGold + 0.5)))

        local minMarginCopper = math.floor(minMarginGold * 10000)
        local results = MarketSync.FindProfitableCrafts and MarketSync.FindProfitableCrafts(profession, minMarginCopper) or {}

        panel.lastMode = "craft"
        panel.lastCraftResults = results
        panel.lastArbitrageResults = {}
        panel.displayRows = BuildCraftDisplay(results)

        local profitableCount = 0
        for _, row in ipairs(results) do
            if row and row.meetsMargin then
                profitableCount = profitableCount + 1
            end
        end

        statusSummary:SetText(string.format("|cff00ff00%s|r: %d profitable / %d total", profession, profitableCount, #panel.displayRows))
        if #panel.displayRows == 0 then
            local knownCount = MarketSync.GetCraftRecipeCount and MarketSync.GetCraftRecipeCount(profession) or 0
            if knownCount == 0 then
                SetNoResultsMessage("No known recipes cached yet. Open your profession window once to index recipes.")
            else
                SetNoResultsMessage("No craft rows have complete pricing data yet.")
            end
        else
            SetNoResultsMessage("Showing profitable and unprofitable rows for this profession.")
        end
        ApplyDisplaySort()
    end

    local function BuildSelectionSummary(selection)
        if not selection then return "" end

        local mode = tostring(selection.mode or "target")
        if mode == "target" then
            local target = FindTargetName(selection.targetItemID) or "(none)"
            return string.format("Target: %s | Margin: %s%%", target, tostring(selection.marginPct or 10))
        end
        if mode == "process" then
            return string.format("Process: %s | Margin: %s%%", tostring(selection.processType or "ALL"), tostring(selection.marginPct or 10))
        end
        return string.format("Craft: %s | Min Margin: %sg", tostring(selection.profession or "(none)"), tostring(selection.minCraftMarginGold or 5))
    end

    local function ApplySelection(selection)
        if not selection then return end

        panel.activeMode = tostring(selection.mode or "target")
        panel.selectedTargetID = tonumber(selection.targetItemID)

        local processType = selection.processType and tostring(selection.processType):upper() or nil
        panel.selectedProcess = (processType and processType ~= "ALL") and processType or nil

        if selection.profession and tostring(selection.profession) ~= "" then
            panel.selectedProfession = tostring(selection.profession)
        end

        marginBox:SetText(tostring(math.floor((tonumber(selection.marginPct) or 10) + 0.5)))
        minMarginGoldBox:SetText(tostring(math.floor((tonumber(selection.minCraftMarginGold) or 5) + 0.5)))

        if panel.activeMode == "target" then
            local targetName = FindTargetName(panel.selectedTargetID)
            if targetName then
                targetInputBox:SetText(targetName)
            elseif panel.selectedTargetID then
                targetInputBox:SetText(tostring(panel.selectedTargetID))
            end
        end

        RefreshModeButtons()
        UpdateRunButtonText()
        panel:RefreshModeControls()
        RefreshDropdownLabels()

        statusSummary:SetText("|cff00ff00Loaded preset:|r " .. Truncate(selection.name or "Preset", 22))
    end

    local RefreshCustomRows
    RefreshCustomRows = function()
        local selections = MarketSync.ListProcessingCustomSelections and MarketSync.ListProcessingCustomSelections() or {}
        local total = #selections
        local totalPages = math.max(1, math.ceil(total / CUSTOM_ROWS))

        if panel.customPage < 0 then panel.customPage = 0 end
        if panel.customPage > (totalPages - 1) then panel.customPage = totalPages - 1 end

        local firstIndex = (panel.customPage * CUSTOM_ROWS) + 1
        for i = 1, CUSTOM_ROWS do
            local row = customRows[i]
            local selection = selections[firstIndex + i - 1]

            if selection then
                row.selection = selection
                row.nameText:SetText(Truncate(selection.name or "Preset", 15))

                row.applyBtn:SetScript("OnClick", function()
                    ApplySelection(selection)
                end)
                row.deleteBtn:SetScript("OnClick", function()
                    if MarketSync.DeleteProcessingCustomSelection and MarketSync.DeleteProcessingCustomSelection(selection.id) then
                        statusSummary:SetText("|cffffaa00Deleted preset:|r " .. Truncate(selection.name or "Preset", 18))
                        RefreshCustomRows()
                    else
                        statusSummary:SetText("|cffff4444Failed to delete preset.|r")
                    end
                end)

                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(selection.name or "Preset", 1, 0.82, 0)
                    GameTooltip:AddLine(BuildSelectionSummary(selection), 0.85, 0.85, 0.85, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                row.applyBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Load preset", 1, 0.82, 0)
                    GameTooltip:Show()
                end)
                row.applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row.deleteBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Delete preset", 1, 0.25, 0.25)
                    GameTooltip:Show()
                end)
                row.deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row.selection = nil
                row:Hide()
            end
        end

        if total > 0 then
            panel.customPageText:SetText(string.format("%d/%d", panel.customPage + 1, totalPages))
        else
            panel.customPageText:SetText("0/0")
        end

        customPrevBtn:SetEnabled(panel.customPage > 0)
        customNextBtn:SetEnabled(total > 0 and panel.customPage < (totalPages - 1))
    end

    targetInputBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if panel.activeMode == "target" then
            btnRun:Click()
        end
    end)

    targetInputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    btnRun:SetScript("OnClick", function()
        RunActiveMode()
    end)

    btnExport:SetScript("OnClick", function()
        if panel.lastMode == "craft" then
            if not panel.lastCraftResults or #panel.lastCraftResults == 0 then
                statusSummary:SetText("|cffff4444No craft results to export.|r")
                return
            end

            local exportRows = {}
            local hasAnySelection = false
            for k, v in pairs(panel.selectedCrafts or {}) do
                if v then hasAnySelection = true; break end
            end

            for _, row in ipairs(panel.lastCraftResults) do
                if row and row.meetsMargin then
                    local name = row.outputName or row.recipeName or ("Item " .. tostring(row.outputItemID or "?"))
                    local isSelected = panel.selectedCrafts and panel.selectedCrafts[name]
                    if (not hasAnySelection) or isSelected then
                        exportRows[#exportRows + 1] = row
                    end
                end
            end
            if #exportRows == 0 then
                statusSummary:SetText("|cffff4444No valid craft rows to export.|r")
                return
            end

            local ok, info
            if MarketSync.ExportCraftMatsToAuctionator then
                ok, info = MarketSync.ExportCraftMatsToAuctionator(exportRows)
            else
                ok, info = false, "Export unavailable"
            end
            if ok then
                statusSummary:SetText(string.format("|cff00ff00Exported %d craft mats.|r", tonumber(info) or 0))
            else
                statusSummary:SetText("|cffff4444Export failed:|r " .. tostring(info or "unknown error"))
            end
            return
        end

        if not panel.lastArbitrageResults or #panel.lastArbitrageResults == 0 then
            statusSummary:SetText("|cffff4444No arbitrage results to export.|r")
            return
        end

        local ok, info
        if MarketSync.ExportArbitrageToAuctionator then
            ok, info = MarketSync.ExportArbitrageToAuctionator(panel.lastArbitrageResults)
        else
            ok, info = false, "Export unavailable"
        end
        if ok then
            statusSummary:SetText(string.format("|cff00ff00Exported %d list entries.|r", tonumber(info) or 0))
        else
            statusSummary:SetText("|cffff4444Export failed:|r " .. tostring(info or "unknown error"))
        end
    end)

    btnTrack:SetScript("OnClick", function()
        if not MarketSync.UpsertNotificationRequest then
            statusSummary:SetText("|cffff4444Notifications module unavailable.|r")
            return
        end

        local tracked = 0
        local seen = {}

        local function AddTrack(itemID, thresholdCopper, fallbackName)
            local id = tonumber(itemID)
            local threshold = tonumber(thresholdCopper) or 0
            if not id or id <= 0 or threshold <= 0 or seen[id] then
                return
            end
            seen[id] = true

            local itemName = ResolveItemVisual(id, fallbackName)
            local req = MarketSync.UpsertNotificationRequest({
                matchType = "itemID",
                matchValue = id,
                displayName = itemName,
                thresholdCopper = math.floor(threshold),
                scope = "all",
                variantMode = "any_suffix",
                enabled = true,
            })
            if req then
                tracked = tracked + 1
            end
        end

        local hasArbitrageSelection = false
        for _, v in pairs(panel.selectedArbitrage or {}) do
            if v then hasArbitrageSelection = true; break end
        end

        local hasCraftSelection = false
        for _, v in pairs(panel.selectedCrafts or {}) do
            if v then hasCraftSelection = true; break end
        end

        if panel.lastMode == "craft" then
            for _, craft in ipairs(panel.lastCraftResults or {}) do
                if craft and craft.meetsMargin then
                    local name = craft.outputName or craft.recipeName or ("Item " .. tostring(craft.outputItemID or "?"))
                    local isSelected = panel.selectedCrafts and panel.selectedCrafts[name]
                    if (not hasCraftSelection) or isSelected then
                        for _, mat in ipairs(craft.matsDetailed or {}) do
                            AddTrack(mat.itemID, mat.capPrice or mat.price, nil)
                        end
                    end
                end
            end
        else
            for _, r in ipairs(panel.lastArbitrageResults or {}) do
                local isSelected = panel.selectedArbitrage and panel.selectedArbitrage[r.inputItemID]
                if (not hasArbitrageSelection) or isSelected then
                    AddTrack(r.inputItemID, r.maxBuyPerUnit, r.inputName)
                end
            end
        end

        if tracked > 0 then
            statusSummary:SetText(string.format("|cff00ff00Tracked %d item(s).|r", tracked))
        else
            statusSummary:SetText("|cffff4444No valid rows to track.|r")
        end
    end)

    btnResyncProf:SetScript("OnClick", function()
        if not MarketSync.ResyncProfessionCache then
            statusSummary:SetText("|cffff4444Profession resync is unavailable.|r")
            return
        end

        local ok, msg = MarketSync.ResyncProfessionCache()

        RefreshProfessionOptions()
        RefreshDropdownLabels()
        if ok then
            statusSummary:SetText("|cff00ff00" .. tostring(msg or "Profession resync complete.") .. "|r")
        elseif msg and string.find(msg, "Open", 1, true) then
            statusSummary:SetText("|cffffff00" .. tostring(msg) .. "|r")
        else
            statusSummary:SetText("|cffff4444" .. tostring(msg or "Unable to resync professions.") .. "|r")
        end
    end)

    btnSaveCustom:SetScript("OnClick", function()
        if not MarketSync.UpsertProcessingCustomSelection then
            statusSummary:SetText("|cffff4444Custom selections unavailable.|r")
            return
        end

        local name = TrimText(customNameBox:GetText())
        if name == "" then
            statusSummary:SetText("|cffff4444Preset name is required.|r")
            return
        end

        if panel.activeMode == "target" then
            local targetQuery = TrimText(targetInputBox:GetText())
            if targetQuery ~= "" then
                local resolvedID = ResolveItemIDFromQuery(targetQuery)
                if resolvedID then
                    panel.selectedTargetID = resolvedID
                else
                    panel.selectedTargetID = nil
                    statusSummary:SetText("|cffff4444Target not found for this preset.|r")
                    return
                end
            end

            if not panel.selectedTargetID then
                statusSummary:SetText("|cffff4444Select a target material before saving.|r")
                return
            end
        end
        if panel.activeMode == "craft" and (not panel.selectedProfession or panel.selectedProfession == "") then
            statusSummary:SetText("|cffff4444Select a profession before saving.|r")
            return
        end

        local payload = {
            name = name,
            mode = panel.activeMode,
            targetItemID = panel.selectedTargetID,
            processType = panel.selectedProcess,
            profession = panel.selectedProfession,
            marginPct = math.floor(ReadNumber(marginBox, 10) + 0.5),
            minCraftMarginGold = math.floor(ReadNumber(minMarginGoldBox, 5) + 0.5),
        }

        local saved, err = MarketSync.UpsertProcessingCustomSelection(payload)
        if not saved then
            statusSummary:SetText("|cffff4444Save failed:|r " .. tostring(err or "unknown error"))
            return
        end

        customNameBox:SetText("")
        panel.customPage = 0
        RefreshCustomRows()
        statusSummary:SetText("|cff00ff00Saved preset:|r " .. Truncate(saved.name or name, 22))
    end)

    customNameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        btnSaveCustom:Click()
    end)

    prevBtn:SetScript("OnClick", function()
        panel.page = panel.page - 1
        UpdateResultRows()
    end)

    nextBtn:SetScript("OnClick", function()
        panel.page = panel.page + 1
        UpdateResultRows()
    end)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if self.page > 0 then
                self.page = self.page - 1
                UpdateResultRows()
            end
            return
        end

        local total = #(self.displayRows or {})
        local maxPage = math.max(0, math.ceil(total / RESULTS_PER_PAGE) - 1)
        if self.page < maxPage then
            self.page = self.page + 1
            UpdateResultRows()
        end
    end)

    customPrevBtn:SetScript("OnClick", function()
        panel.customPage = panel.customPage - 1
        RefreshCustomRows()
    end)

    customNextBtn:SetScript("OnClick", function()
        panel.customPage = panel.customPage + 1
        RefreshCustomRows()
    end)

    panel:SetScript("OnShow", function()
        RefreshProfessionOptions()

        if targetDropdown and targetDropdown._initFunc then
            UIDropDownMenu_Initialize(targetDropdown, targetDropdown._initFunc)
        end
        if processDropdown and processDropdown._initFunc then
            UIDropDownMenu_Initialize(processDropdown, processDropdown._initFunc)
        end

        RefreshModeButtons()
        UpdateRunButtonText()
        panel:RefreshModeControls()
        RefreshDropdownLabels()
        RefreshCustomRows()

        if not panel.displayRows or #panel.displayRows == 0 then
            SetNoResultsMessage("Run " .. ModeLabel(panel.activeMode) .. " to see results.")
        end
        UpdateResultRows()
    end)

    RefreshModeButtons()
    UpdateRunButtonText()
    panel:RefreshModeControls()
    RefreshProfessionOptions()
    RefreshDropdownLabels()
    RefreshCustomRows()
    SetNoResultsMessage("Run a mode to see results.")
    panel.displayRows = {}
    UpdateResultRows()

    return panel
end
