-- =============================================================
-- MarketSync - Processing Panel UI
-- Box layout: top-left controls, lower-left custom presets, right results
-- =============================================================

local RESULTS_PER_PAGE = 8
local CUSTOM_ROWS = 4

local LEFT_X = 23
local TOP_Y = -70
local LEFT_W = 155
local LEFT_TOP_H = 188
local LEFT_BOTTOM_H = 150
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

local function SafeGetItemInfo(item)
    if not item then return nil end
    if MarketSync and MarketSync.GetItemInfo then
        return MarketSync.GetItemInfo(item)
    elseif C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif GetItemInfo then
        return GetItemInfo(item)
    end
    return nil
end

local function SafeGetItemIcon(item)
    if not item then return nil end
    if MarketSync and MarketSync.GetItemIcon then
        return MarketSync.GetItemIcon(item)
    elseif C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(item)
    elseif GetItemIcon then
        return GetItemIcon(item)
    end
    return nil
end

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
    local dd = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate,BackdropTemplate")
    UIDropDownMenu_SetWidth(dd, width)
    dd._initFunc = initFunc
    UIDropDownMenu_Initialize(dd, initFunc)

    -- Reskin to sleek AH dark style
    local left = _G[frameName.."Left"]
    local mid = _G[frameName.."Middle"]
    local right = _G[frameName.."Right"]
    if left then left:Hide() end
    if mid then mid:Hide() end
    if right then right:Hide() end

    dd:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    dd:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    dd:SetBackdropBorderColor(0.32, 0.28, 0.20, 0.85)

    local txt = _G[frameName.."Text"]
    if txt then
        txt:ClearAllPoints()
        txt:SetPoint("LEFT", dd, "LEFT", 10, 0)
        txt:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
        txt:SetJustifyH("LEFT")
    end

    local btn = _G[frameName.."Button"]
    if btn then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", dd, "RIGHT", -2, 0)
    end

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

    local _, linkByName = SafeGetItemInfo(raw)
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

local function SignedMoneyText(copper, showPlus)
    local value = tonumber(copper) or 0
    local prefix = ""
    if value < 0 then
        prefix = "-"
    elseif showPlus and value > 0 then
        prefix = "+"
    end
    return prefix .. MoneyText(math.abs(value))
end

local function ExpectedQuantityText(value)
    local amount = math.max(0, tonumber(value) or 0)
    if amount < 0.1 then return string.format("%.3f", amount) end
    if amount < 1 then return string.format("%.2f", amount) end
    return string.format("%.1f", amount)
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
        name, link, _, _, _, _, _, _, _, icon = SafeGetItemInfo(id)
        if not icon then
            icon = SafeGetItemIcon(id)
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
    if MarketSync and MarketSync.CreateModernInset then
        return MarketSync.CreateModernInset(parent, x, y, width, height)
    end
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width, height)
    return box
end

function MarketSync.CreateProcessingPanel(parent)
    local isEmbedded = (parent ~= MarketSync.MainFrame)
    local LEFT_X = isEmbedded and 12 or 23
    local LEFT_W = isEmbedded and 180 or 155
    local RESULTS_X = isEmbedded and 198 or 195
    local ROW_WIDTH = isEmbedded and 550 or 632

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    if parent == MarketSync.MainFrame then
        panel:Hide()
    end

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

    local leftTopBox, leftBottomBox, rightBox
    if isEmbedded then
        leftTopBox = CreateBox(panel, LEFT_X, -34, LEFT_W, 204)
        leftBottomBox = CreateBox(panel, LEFT_X, -246, LEFT_W, 214)
        leftBottomBox:SetWidth(LEFT_W)
        leftBottomBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_X, 8)
        rightBox = CreateBox(panel, RESULTS_X, -34, ROW_WIDTH, 436)
        rightBox:SetWidth(ROW_WIDTH)
        rightBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    else
        leftTopBox = CreateBox(panel, LEFT_X, TOP_Y, LEFT_W, LEFT_TOP_H)
        leftBottomBox = CreateBox(panel, LEFT_X, TOP_Y - LEFT_TOP_H - BOX_GAP, LEFT_W, LEFT_BOTTOM_H)
        rightBox = CreateBox(panel, RESULTS_X - 2, TOP_Y, ROW_WIDTH + 4, 346)
    end
    panel.leftTopBox = leftTopBox
    panel.leftBottomBox = leftBottomBox
    panel.rightBox = rightBox

    local leftTopTitle = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    leftTopTitle:SetPoint("TOPLEFT", 8, -8)
    leftTopTitle:SetText("|cffffd700Target Material Controls|r")

    local modeButtons = {}
    local btnRun
    local ApplyDisplaySort
    local RunActiveMode
    local UpdateResultRows

    local tableScrollBar
    if MarketSync.CreateModernTableScrollBar and rightBox then
        tableScrollBar = MarketSync.CreateModernTableScrollBar(panel, rightBox, function(newPage)
            panel.page = newPage
            if UpdateResultRows then
                UpdateResultRows()
            end
        end, 8, isEmbedded and -24 or -28, 28)
        panel.tableScrollBar = tableScrollBar
        tableScrollBar:AttachMouseWheel(rightBox)
        tableScrollBar:AttachMouseWheel(panel)
    end

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
                    btn:Disable()
                    local t = btn.GetFontString and btn:GetFontString()
                    if t and t.SetTextColor then t:SetTextColor(1.0, 0.82, 0.0) end
                else
                    btn:Enable()
                    local t = btn.GetFontString and btn:GetFontString()
                    if t and t.SetTextColor then t:SetTextColor(0.90, 0.90, 0.90) end
                end
            end
        end
        if leftTopTitle then
            if panel.activeMode == "target" then
                leftTopTitle:SetText("|cffffd700Target Material Controls|r")
            elseif panel.activeMode == "process" then
                leftTopTitle:SetText("|cffffd700Process Scan Controls|r")
            else
                leftTopTitle:SetText("|cffffd700Craft Profit Controls|r")
            end
        end
    end

    -- Top Sub-Tab Mode Buttons (Target Material / Process Scan / Craft Profit)
    local function CreateModeTab(def, index)
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(isEmbedded and 115 or 122, 22)
        if index == 1 then
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", isEmbedded and 8 or 76, isEmbedded and -8 or -34)
        else
            btn:SetPoint("LEFT", modeButtons[MODE_OPTIONS[index - 1].key], "RIGHT", 6, 0)
        end
        btn:SetText(def.label)

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

    modeButtons.target = CreateModeTab(MODE_OPTIONS[1], 1)
    modeButtons.process = CreateModeTab(MODE_OPTIONS[2], 2)
    modeButtons.craft = CreateModeTab(MODE_OPTIONS[3], 3)

    local targetLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    targetLabel:SetPoint("TOPLEFT", 8, -26)
    targetLabel:SetText("Target (Name/ID)")

    local targetInputBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    targetInputBox:SetSize(LEFT_W - 16, 18)
    targetInputBox:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", 8, -42)
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

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(modeButtons.target, {
            name = "Target Material Mode",
            context = "Button",
            description = "Calculate profitability for a specific target material",
        })
        MarketSync.SetAccessibility(modeButtons.process, {
            name = "Process Type Mode",
            context = "Button",
            description = "Calculate profitability across all materials for a processing method",
        })
        MarketSync.SetAccessibility(modeButtons.craft, {
            name = "Profession Crafting Mode",
            context = "Button",
            description = "Calculate profitability across recipes for a selected profession",
        })
        MarketSync.SetAccessibility(targetInputBox, {
            name = "Target Material Input",
            context = "Edit Box",
            description = "Enter item name, item link, or item ID to evaluate",
        })
    end

    local parentPrefix = (parent and parent.GetName and parent:GetName()) or "MarketSync"
    local targetDropdown
    targetDropdown = BuildDropdown(parentPrefix .. "ProcessingTargetDropdown", leftTopBox, LEFT_W - 26, function(self, level)
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
            local priceStr = ""
            local price = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(t.itemID)
            if price and price > 0 and MarketSync.FormatMoney then
                priceStr = "  " .. MarketSync.FormatMoney(price)
            end
            opt.text = string.format("%s%s", t.name or ("Item #" .. tostring(t.itemID)), priceStr)
            opt.icon = t.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.itemID))
            opt.func = function()
                panel.selectedTargetID = t.itemID
                targetInputBox:SetText(t.name or ("Item #" .. tostring(t.itemID)))
                UIDropDownMenu_SetText(targetDropdown, t.name or ("Item #" .. tostring(t.itemID)))
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    targetDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -12, -64)

    local targetDesc = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    targetDesc:SetPoint("TOPLEFT", 8, -122)
    targetDesc:SetPoint("BOTTOMRIGHT", -8, 8)
    targetDesc:SetJustifyH("LEFT")
    if targetDesc.SetJustifyV then targetDesc:SetJustifyV("TOP") end
    targetDesc:SetText("|cff777777Calculates arbitrage profit from buying this material and processing it into secondary yields.|r")

    local processLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    processLabel:SetPoint("TOPLEFT", 8, -26)
    processLabel:SetText("Process")

    local processDropdown
    processDropdown = BuildDropdown(parentPrefix .. "ProcessingTypeDropdown", leftTopBox, LEFT_W - 54, function(self, level)
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
    processDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -12, -42)
    UIDropDownMenu_SetText(processDropdown, "ALL")

    local processDesc = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    processDesc:SetPoint("TOPLEFT", 8, -102)
    processDesc:SetPoint("BOTTOMRIGHT", -8, 8)
    processDesc:SetJustifyH("LEFT")
    if processDesc.SetJustifyV then processDesc:SetJustifyV("TOP") end
    processDesc:SetText("|cff777777Evaluates all auction house ores, herbs, and gear for mass processing profit.|r")

    local professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions()) or {}
    panel.selectedProfession = professionOptions[1] or nil

    local professionLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    professionLabel:SetPoint("TOPLEFT", 8, -26)
    professionLabel:SetText("Profession")

    local professionDropdown
    professionDropdown = BuildDropdown(parentPrefix .. "CraftProfDropdown", leftTopBox, LEFT_W - 54, function(self, level)
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
    professionDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -12, -42)
    UIDropDownMenu_SetText(professionDropdown, panel.selectedProfession or "No professions")

    local craftDesc = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    craftDesc:SetPoint("TOPLEFT", 8, -102)
    craftDesc:SetPoint("BOTTOMRIGHT", -8, 8)
    craftDesc:SetJustifyH("LEFT")
    if craftDesc.SetJustifyV then craftDesc:SetJustifyV("TOP") end
    craftDesc:SetText("|cff777777Calculates profit for all recipes in your known profession against current auction prices.|r")

    local marginLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    marginLabel:SetPoint("TOPLEFT", 8, -98)
    marginLabel:SetText("Margin %")

    local marginBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    marginBox:SetSize(36, 18)
    marginBox:SetPoint("LEFT", marginLabel, "RIGHT", 6, 0)
    marginBox:SetAutoFocus(false)
    marginBox:SetNumeric(true)
    marginBox:SetText("10")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(marginBox)
    end

    local marginBtn10 = CreateFrame("Button", nil, leftTopBox, "UIPanelButtonTemplate")
    marginBtn10:SetSize(32, 18)
    marginBtn10:SetPoint("LEFT", marginBox, "RIGHT", 4, 0)
    marginBtn10:SetText("10%")
    marginBtn10:SetScript("OnClick", function() marginBox:SetText("10") end)

    local marginBtn20 = CreateFrame("Button", nil, leftTopBox, "UIPanelButtonTemplate")
    marginBtn20:SetSize(32, 18)
    marginBtn20:SetPoint("LEFT", marginBtn10, "RIGHT", 2, 0)
    marginBtn20:SetText("20%")
    marginBtn20:SetScript("OnClick", function() marginBox:SetText("20") end)

    local minMarginLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    minMarginLabel:SetPoint("TOPLEFT", 8, -74)
    minMarginLabel:SetText("Min Craft")

    local minMarginGoldBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    minMarginGoldBox:SetSize(36, 18)
    minMarginGoldBox:SetPoint("LEFT", minMarginLabel, "RIGHT", 6, 0)
    minMarginGoldBox:SetAutoFocus(false)
    minMarginGoldBox:SetNumeric(true)
    minMarginGoldBox:SetText("5")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(minMarginGoldBox)
    end

    local minGoldBtn5 = CreateFrame("Button", nil, leftTopBox, "UIPanelButtonTemplate")
    minGoldBtn5:SetSize(28, 18)
    minGoldBtn5:SetPoint("LEFT", minMarginGoldBox, "RIGHT", 4, 0)
    minGoldBtn5:SetText("5g")
    minGoldBtn5:SetScript("OnClick", function() minMarginGoldBox:SetText("5") end)

    local minGoldBtn20 = CreateFrame("Button", nil, leftTopBox, "UIPanelButtonTemplate")
    minGoldBtn20:SetSize(32, 18)
    minGoldBtn20:SetPoint("LEFT", minGoldBtn5, "RIGHT", 2, 0)
    minGoldBtn20:SetText("20g")
    minGoldBtn20:SetScript("OnClick", function() minMarginGoldBox:SetText("20") end)

    btnRun = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local btnExport = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local btnTrack = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local statusSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    if isEmbedded then
        btnRun:SetSize(84, 20)
        btnExport:SetSize(68, 20)
        btnTrack:SetSize(64, 20)

        btnTrack:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -7)
        btnExport:SetPoint("RIGHT", btnTrack, "LEFT", -4, 0)
        btnRun:SetPoint("RIGHT", btnExport, "LEFT", -4, 0)

        statusSummary:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, -9)
        statusSummary:SetWidth(280)
        statusSummary:SetJustifyH("LEFT")
    else
        btnRun:SetSize(90, 22)
        btnExport:SetSize(65, 22)
        btnTrack:SetSize(65, 22)

        btnTrack:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -22, -34)
        btnExport:SetPoint("RIGHT", btnTrack, "LEFT", -4, 0)
        btnRun:SetPoint("RIGHT", btnExport, "LEFT", -4, 0)

        statusSummary:SetPoint("RIGHT", btnRun, "LEFT", -10, 0)
        statusSummary:SetWidth(220)
        statusSummary:SetJustifyH("RIGHT")
    end
    btnExport:SetText("Export")
    btnTrack:SetText("Track")
    statusSummary:SetText("|cff888888Ready|r")

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btnRun, {
            name = function() return btnRun:GetText() or "Run" end,
            context = "Button",
            description = "Execute processing profitability calculation",
        })
        MarketSync.SetAccessibility(btnExport, {
            name = "Export",
            context = "Button",
            description = "Export processing results to CSV or clipboard",
        })
        MarketSync.SetAccessibility(btnTrack, {
            name = "Track",
            context = "Button",
            description = "Add selected items to tracking and alerts",
        })
        MarketSync.SetAccessibility(marginBox, {
            name = "Margin Percentage",
            context = "Edit Box",
            description = "Minimum target profit margin percentage",
        })
        MarketSync.SetAccessibility(minMarginGoldBox, {
            name = "Minimum Margin Gold",
            context = "Edit Box",
            description = "Minimum gold profit required for craft",
        })
    end

    panel.sortField = "valueSort"
    panel.sortAscending = false

    local colDefs = isEmbedded and {
        { name = "Item",     width = 180, sortKey = "itemSort"   },
        { name = "Type/Lvl", width = 54,  sortKey = "typeSort"   },
        { name = "Value",    width = 66,  sortKey = "valueSort"  },
        { name = "Max",      width = 66,  sortKey = "maxSort"    },
        { name = "Live",     width = 64,  sortKey = "liveSort"   },
        { name = "Delta",    width = 64,  sortKey = "deltaSort"  },
        { name = "Status",   width = 56,  sortKey = "statusSort" },
    } or {
        { name = "Item",     width = 244, sortKey = "itemSort"   },
        { name = "Type/Lvl", width = 58,  sortKey = "typeSort"   },
        { name = "Value",    width = 72,  sortKey = "valueSort"  },
        { name = "Max",      width = 72,  sortKey = "maxSort"    },
        { name = "Live",     width = 66,  sortKey = "liveSort"   },
        { name = "Delta",    width = 66,  sortKey = "deltaSort"  },
        { name = "Status",   width = 58,  sortKey = "statusSort" },
    }

    panel.headerButtons = {}
    local function RefreshHeaderArrows()
        for _, h in ipairs(panel.headerButtons) do
            if h.sortKey and h.sortKey == panel.sortField then
                if h.arrow then h.arrow:Show() end
                if h.label then h.label:SetTextColor(1, 0.82, 0) end
                if panel.sortAscending then
                    if h.arrow then h.arrow:SetTexCoord(0, 0.5625, 1.0, 0) end
                else
                    if h.arrow then h.arrow:SetTexCoord(0, 0.5625, 0, 1.0) end
                end
            else
                if h.arrow then h.arrow:Hide() end
                if h.label then h.label:SetTextColor(0.85, 0.85, 0.85) end
            end
        end
    end

    local numResultsPerPage = isEmbedded and 11 or 8
    local rowHeight = isEmbedded and 36 or 37
    local hdrY = isEmbedded and -32 or -70
    local rowStartY = isEmbedded and -54 or -94

    local colX = RESULTS_X - 2
    for i, col in ipairs(colDefs) do
        local hdr = MarketSync.CreateAHColumnHeader and MarketSync.CreateAHColumnHeader(panel, col.width, 20, col.name, col.sortKey)
        if not hdr then
            hdr = CreateFrame("Button", nil, panel, "BackdropTemplate")
            hdr:SetSize(col.width, 20)
            hdr.label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hdr.label:SetPoint("LEFT", 6, 0)
            hdr.label:SetText(col.name)
        end
        hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", colX, hdrY)
        hdr.sortKey = col.sortKey

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
        colX = colX + col.width
    end

    local ARBITRAGE_HEADERS = {
        { "Item", "Input item being purchased and processed." },
        { "Process", "Processing method." },
        { "Net EV/ea", "Expected net resale value per input item after the 5% main Auction House sale cut." },
        { "Max/ea", "Maximum buy price per input item after applying the selected safety margin." },
        { "AH/ea", "Current Auctionator price per input item." },
        { "Edge/ea", "Maximum buy price minus the current price, per input item." },
        { "Status", "Partial/stale pricing state and whether the current input price is at or below the maximum buy price." },
    }
    local CRAFT_HEADERS = {
        { "Item", "Crafted output item." },
        { "Diff.", "Current profession difficulty reported for this recipe." },
        { "Profit/Craft", "Expected net revenue minus the complete material basket cost for one craft." },
        { "Cap/Craft", "Maximum total material spend for one craft while preserving the selected minimum profit." },
        { "Mats/Craft", "Current total Auctionator cost of the complete material basket for one craft." },
        { "Room/Craft", "Material cost cap minus current material basket cost, per craft." },
        { "Status", "Price freshness and whether the craft meets the selected minimum profit." },
    }

    local function RefreshResultHeaders()
        local definitions = (panel.activeMode == "craft") and CRAFT_HEADERS or ARBITRAGE_HEADERS
        for i, header in ipairs(panel.headerButtons) do
            local definition = definitions[i]
            if header.label and definition then
                header.label:SetText(definition[1])
                header.tooltipTitle = definition[1]
                header.tooltipText = definition[2]
            end
        end
    end

    RefreshResultHeaders()
    RefreshHeaderArrows()

    panel.resultRows = {}
    for i = 1, numResultsPerPage do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(ROW_WIDTH, rowHeight)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, rowStartY - ((i - 1) * rowHeight))

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

        -- Modern clean row background matching native AH subtle alternation
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", 34, 0)
        rowBg:SetPoint("BOTTOMRIGHT", 0, 0)
        if i % 2 == 0 then
            rowBg:SetColorTexture(0.10, 0.095, 0.09, 0.50)
        else
            rowBg:SetColorTexture(0.06, 0.055, 0.05, 0.50)
        end
        row.rowBg = rowBg

        local rowHl = row:CreateTexture(nil, "HIGHLIGHT")
        rowHl:SetPoint("TOPLEFT", 34, 0)
        rowHl:SetPoint("BOTTOMRIGHT", 0, 0)
        rowHl:SetColorTexture(0.30, 0.25, 0.12, 0.40)

        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.nameText:SetPoint("TOPLEFT", 43, -3)
        row.nameText:SetWidth(isEmbedded and 134 or 198)
        row.nameText:SetJustifyH("LEFT")

        row.typeText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.typeText:SetPoint("TOPLEFT", isEmbedded and 184 or 246, -3)
        row.typeText:SetWidth(isEmbedded and 48 or 50)
        row.typeText:SetJustifyH("LEFT")

        row.valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.valueText:SetPoint("TOPLEFT", isEmbedded and 238 or 304, -3)
        row.valueText:SetWidth(isEmbedded and 58 or 60)
        row.valueText:SetJustifyH("RIGHT")

        row.maxText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.maxText:SetPoint("TOPLEFT", isEmbedded and 304 or 374, -3)
        row.maxText:SetWidth(isEmbedded and 58 or 60)
        row.maxText:SetJustifyH("RIGHT")

        row.liveText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.liveText:SetPoint("TOPLEFT", isEmbedded and 370 or 442, -3)
        row.liveText:SetWidth(isEmbedded and 56 or 54)
        row.liveText:SetJustifyH("RIGHT")

        row.deltaText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.deltaText:SetPoint("TOPLEFT", isEmbedded and 434 or 506, -3)
        row.deltaText:SetWidth(isEmbedded and 56 or 54)
        row.deltaText:SetJustifyH("RIGHT")

        row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.statusText:SetPoint("TOPLEFT", isEmbedded and 498 or 570, -3)
        row.statusText:SetWidth(isEmbedded and 50 or 54)
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
        highlight:SetSize(ROW_WIDTH - 38, 32)
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
                    info.text = "Search in AH"
                    info.notCheckable = true
                    info.func = function()
                        if MarketSync.SearchInAuctionHouse then
                            local searchTarget = (row.data and row.data.name) or (row.nameText and row.nameText:GetText()) or row.itemID
                            MarketSync.SearchInAuctionHouse(searchTarget)
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
        if tableScrollBar then
            tableScrollBar:AttachMouseWheel(row)
            tableScrollBar:AttachMouseWheel(iconButton)
        end
        panel.resultRows[i] = row
    end


    panel.noResultsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noResultsText:SetPoint("TOP", panel, "TOP", isEmbedded and 80 or 115, -200)
    panel.noResultsText:SetText("|cff888888Run a mode to see results.|r")
    panel.noResultsText:Show()

    local prevBtn = CreateFrame("Button", nil, panel)
    prevBtn:SetSize(20, 20)
    prevBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", isEmbedded and -40 or -48, 14)
    prevBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local pnt = prevBtn.GetNormalTexture and prevBtn:GetNormalTexture()
    if pnt and pnt.SetVertexColor then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(20, 20)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local nnt = nextBtn.GetNormalTexture and nextBtn:GetNormalTexture()
    if nnt and nnt.SetVertexColor then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end

    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.pageText:SetPoint("RIGHT", prevBtn, "LEFT", -8, 0)
    panel.pageText:SetText("0 results")

    local btnResyncProf = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnResyncProf:SetSize(118, 20)
    btnResyncProf:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", RESULTS_X + 2, 14)
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

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(prevBtn, {
            name = "Previous Page",
            context = "Button",
            description = "Navigate to previous page of results",
        })
        MarketSync.SetAccessibility(nextBtn, {
            name = "Next Page",
            context = "Button",
            description = "Navigate to next page of results",
        })
        MarketSync.SetAccessibility(btnResyncProf, {
            name = "Resync Professions",
            context = "Button",
            description = "Refreshes profession recipe cache for currently open trade skill window",
            tooltipTitle = "Resync profession cache",
            tooltipText = "Refreshes cache for the profession window currently open.",
        })
    end

    local customTitle = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    customTitle:SetPoint("TOPLEFT", 8, -8)
    customTitle:SetText("|cffffd700Custom Selections|r")

    local customNameLabel = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    customNameLabel:SetPoint("TOPLEFT", 8, -26)
    customNameLabel:SetText("Preset")

    local customNameBox = CreateFrame("EditBox", nil, leftBottomBox, "InputBoxTemplate")
    customNameBox:SetSize(110, 18)
    customNameBox:SetPoint("LEFT", customNameLabel, "RIGHT", 6, 0)
    customNameBox:SetAutoFocus(false)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(customNameBox)
    end

    local btnSaveCustom = CreateFrame("Button", nil, leftBottomBox, "UIPanelButtonTemplate")
    btnSaveCustom:SetSize(52, 18)
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
        row.nameText:SetWidth(108)
        row.nameText:SetJustifyH("LEFT")

        row.applyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.applyBtn:SetSize(24, 16)
        row.applyBtn:SetPoint("LEFT", 112, 0)
        row.applyBtn:SetText("L")

        row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.deleteBtn:SetSize(24, 16)
        row.deleteBtn:SetPoint("LEFT", 140, 0)
        row.deleteBtn:SetText("X")

        row:Hide()
        customRows[i] = row
    end

    panel.customPageText = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.customPageText:SetPoint("BOTTOMLEFT", 8, 8)
    panel.customPageText:SetText("1/1")

    local customPrevBtn = CreateFrame("Button", nil, leftBottomBox)
    customPrevBtn:SetSize(16, 16)
    customPrevBtn:SetPoint("BOTTOMRIGHT", -26, 6)
    customPrevBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    customPrevBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    customPrevBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local cpnt = customPrevBtn.GetNormalTexture and customPrevBtn:GetNormalTexture()
    if cpnt and cpnt.SetVertexColor then cpnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end

    local customNextBtn = CreateFrame("Button", nil, leftBottomBox)
    customNextBtn:SetSize(16, 16)
    customNextBtn:SetPoint("LEFT", customPrevBtn, "RIGHT", 4, 0)
    customNextBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    customNextBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    customNextBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local cnnt = customNextBtn.GetNormalTexture and customNextBtn:GetNormalTexture()
    if cnnt and cnnt.SetVertexColor then cnnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end

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

        local name = SafeGetItemInfo(id)
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
        SetControlVisible(targetDropdown, isTarget)
        SetControlVisible(targetDesc, isTarget)

        SetControlVisible(processLabel, isProcess)
        SetControlVisible(processDropdown, isProcess)
        SetControlVisible(processDesc, isProcess)

        SetControlVisible(professionLabel, isCraft)
        SetControlVisible(professionDropdown, isCraft)
        SetControlVisible(craftDesc, isCraft)

        if isTarget then
            marginLabel:SetPoint("TOPLEFT", 8, -98)
        else
            marginLabel:SetPoint("TOPLEFT", 8, -76)
        end

        SetControlVisible(marginLabel, (isTarget or isProcess))
        SetControlVisible(marginBox, (isTarget or isProcess))
        SetControlVisible(marginBtn10, (isTarget or isProcess))
        SetControlVisible(marginBtn20, (isTarget or isProcess))

        SetControlVisible(minMarginLabel, isCraft)
        SetControlVisible(minMarginGoldBox, isCraft)
        SetControlVisible(minGoldBtn5, isCraft)
        SetControlVisible(minGoldBtn20, isCraft)
        RefreshResultHeaders()
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
        local totalPages = math.max(1, math.ceil(total / numResultsPerPage))
        if panel.page < 0 then panel.page = 0 end
        if panel.page > (totalPages - 1) then panel.page = totalPages - 1 end

        local firstIndex = (panel.page * numResultsPerPage) + 1
        for i = 1, numResultsPerPage do
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

                if MarketSync.SetAccessibility then
                    MarketSync.SetAccessibility(row, {
                        name = function()
                            return MarketSync.StripColorCodes(data.nameText or "Item")
                        end,
                        context = "Button",
                        description = function()
                            local val = MarketSync.StripColorCodes(data.valueText or "")
                            local status = MarketSync.StripColorCodes(data.statusText or "")
                            local typ = MarketSync.StripColorCodes(data.typeText or "")
                            return string.format("%s, Type: %s, Value: %s, Status: %s. Click to select or view details.", MarketSync.StripColorCodes(data.nameText or ""), typ, val, status)
                        end,
                        getIndexInfo = function()
                            return { index = firstIndex + i - 1, total = total }
                        end,
                    })
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

        local hasPrev = panel.page > 0
        local hasNext = total > 0 and panel.page < (totalPages - 1)
        prevBtn:SetEnabled(hasPrev)
        nextBtn:SetEnabled(hasNext)
        local pnt = prevBtn.GetNormalTexture and prevBtn:GetNormalTexture()
        if pnt and pnt.SetVertexColor then
            if hasPrev then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else pnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        local nnt = nextBtn.GetNormalTexture and nextBtn:GetNormalTexture()
        if nnt and nnt.SetVertexColor then
            if hasNext then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else nnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end

        if total > 0 then
            panel.noResultsText:Hide()
        else
            panel.noResultsText:Show()
        end

        if tableScrollBar then
            tableScrollBar:Update(panel.page, totalPages - 1)
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
            if r.partialEV then
                status = "|cffffaa00PARTIAL|r"
                statusRank = 2
            elseif r.liveStale or r.evStale or r.targetStale then
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
            local ahCutPercent = tonumber(r.ahCutPercent) or 5
            local evBasisLabel = r.targetName and "Target-only Net EV/Input:"
                or (r.partialEV and "Partial Net EV/Input:" or "Net EV/Input:")
            local evText = r.partialEV and ColorWarn(MoneyText(evPerUnit)) or ColorGood(MoneyText(evPerUnit))
            detailLines[#detailLines + 1] = string.format("%s %s %s",
                ColorLabel(evBasisLabel), evText, ColorMuted("(after " .. tostring(ahCutPercent) .. "% main-AH cut)"))
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r %s",
                ColorLabel("Max Buy/Input:"), MoneyText(maxBuy), ColorMuted("(" .. tostring(math.floor(marginPct + 0.5)) .. "% margin)"))
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r",
                ColorLabel("Live AH/Input:"), (livePrice > 0) and MoneyText(livePrice) or "Unavailable")
            detailLines[#detailLines + 1] = string.format("%s %s",
                ColorLabel("Edge/Input:"), FormatDelta(delta))
            if r.targetName then
                detailLines[#detailLines + 1] = string.format("%s %s  %s %s",
                    ColorLabel("Target AH/Each (gross):"), ColorInfo(r.targetName), ColorMuted("@"), ColorGood(MoneyText(r.targetPrice or 0)))
            end
            if r.expectedTarget then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r",
                    ColorLabel("Expected Target/Action:"), ExpectedQuantityText(r.expectedTarget))
            end
            if r.evPerAction then
                detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Net EV/Action:"), ColorGood(MoneyText(r.evPerAction)))
            end
            if r.stackSize and tonumber(r.stackSize) and tonumber(r.stackSize) > 1 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%d|r", ColorLabel("Stack Size:"), tonumber(r.stackSize))
            end
            if r.missingOutputs and tonumber(r.missingOutputs) and tonumber(r.missingOutputs) > 0 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%d|r", ColorWarn("Missing priced outputs:"), tonumber(r.missingOutputs))
                detailLines[#detailLines + 1] = ColorWarn("Displayed EV is a conservative partial lower bound.")
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
            local outputQty = tonumber(c.outputQty) or 1
            local outputQtyMin = tonumber(c.outputQtyMin) or outputQty
            local outputQtyMax = tonumber(c.outputQtyMax) or outputQty
            local ahCutPercent = tonumber(c.ahCutPercent) or 5
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Recipe:"), ColorInfo(outputName))
            if outputQtyMin ~= outputQtyMax then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%g-%g|r %s",
                    ColorLabel("Output/Craft:"), outputQtyMin, outputQtyMax,
                    ColorMuted(string.format("(expected %.2f)", outputQty)))
            else
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%g|r", ColorLabel("Output/Craft:"), outputQty)
            end
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r",
                ColorLabel("Output AH/Each (gross):"), MoneyText(c.outputUnitPrice or 0))
            detailLines[#detailLines + 1] = string.format("%s %s %s", ColorLabel("Net Revenue/Craft:"),
                ColorGood(MoneyText(revenue)), ColorMuted("(after " .. tostring(ahCutPercent) .. "% main-AH cut)"))
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r", ColorLabel("Material Cost/Craft:"), MoneyText(craftCost))

            local marginText = MoneyText(math.abs(margin))
            if margin >= 0 then
                marginText = "+" .. marginText
            else
                marginText = "-" .. marginText
            end
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Profit/Craft:"), (margin >= 0) and ColorGood(marginText) or ColorBad(marginText))

            if maxSpend > 0 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r", ColorLabel("Material Cost Cap/Craft:"), MoneyText(maxSpend))
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
                detailLines[#detailLines + 1] = string.format("%s x%d %s %s%s",
                    ColorMuted(matName), qty, ColorMuted("@"), priceColor, ColorMuted("/ea"))
            end

            rows[#rows + 1] = {
                recipeName = outputName,
                itemID = c.outputItemID,
                link = itemLink,
                icon = icon,
                nameText = Truncate(itemName, 24),
                typeText = Truncate(tostring(c.skillType or "Craft"), 8),
                valueText = SignedMoneyText(margin, true),
                maxText = MoneyText(maxSpend),
                liveText = MoneyText(craftCost),
                deltaText = FormatDelta(capDelta),
                statusText = status,
                itemSort = string.lower(itemName or ""),
                typeSort = string.lower(tostring(c.skillType or "")),
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

        local hasCPrev = panel.customPage > 0
        local hasCNext = total > 0 and panel.customPage < (totalPages - 1)
        customPrevBtn:SetEnabled(hasCPrev)
        customNextBtn:SetEnabled(hasCNext)
        local cpnt = customPrevBtn.GetNormalTexture and customPrevBtn:GetNormalTexture()
        if cpnt and cpnt.SetVertexColor then
            if hasCPrev then cpnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else cpnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        local cnnt = customNextBtn.GetNormalTexture and customNextBtn:GetNormalTexture()
        if cnnt and cnnt.SetVertexColor then
            if hasCNext then cnnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else cnnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
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
