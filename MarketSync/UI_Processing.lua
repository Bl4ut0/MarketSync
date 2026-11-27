-- =============================================================
-- MarketSync - Processing Panel UI
-- Compact mode controls above full-width results, with saved views in a popout
-- =============================================================

local RESULTS_PER_PAGE = 8
local CUSTOM_ROWS = 3

local LEFT_X = 14
local TOP_Y = -70
local LEFT_W = 164
local LEFT_TOP_H = 174
local LEFT_BOTTOM_H = 164
local BOX_GAP = 6

local RESULTS_X = 186
local ROW_WIDTH = 632
local ROW_HEIGHT = 37

local PROCESS_OPTIONS_FALLBACK = { "ALL", "PROSPECT", "MILL", "DISENCHANT" }
-- Recipe colours as the profession window shows them.
local SKILL_DIFFICULTY = {
    optimal = { text = "|cffff8040Orange|r", rank = 1 },
    difficult = { text = "|cffff8040Orange|r", rank = 1 },
    medium = { text = "|cffffff00Yellow|r", rank = 2 },
    easy = { text = "|cff40c040Green|r", rank = 3 },
    trivial = { text = "|cff808080Grey|r", rank = 4 },
}
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

local function FormatProcessType(processType)
    if not processType then return "-" end
    local v = tostring(processType):upper()
    if v == "DISENCHANT" then return "Disenchant" end
    if v == "PROSPECT" then return "Prospect" end
    if v == "MILL" then return "Milling" end
    return tostring(processType)
end

local function BuildDropdown(frameName, parent, width, initFunc)
    -- Match the sidecar: a native AH button opens a hidden Blizzard menu.
    if MarketSync.CreateDropdownButton then
        return MarketSync.CreateDropdownButton(parent, frameName, width or 120, 22, initFunc)
    end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 22)
    local menu = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    menu:Hide()
    button._menu = menu
    button._initFunc = initFunc
    UIDropDownMenu_Initialize(menu, initFunc)
    button:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, menu, self, 0, 0)
    end)
    return button
end

local function SetDropdownLabel(button, label)
    button:SetText(tostring(label or "") .. "  |cFFFFD100v|r")
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

local function ResolveItemVisual(itemID, fallbackName, onMissingName)
    local id = tonumber(itemID)
    local name, link, _, _, _, _, _, _, _, icon
    if id then
        name, link, _, _, _, _, _, _, _, icon = SafeGetItemInfo(id)
        if not name and C_Item and C_Item.GetItemNameByID then
            local ok, localizedName = pcall(C_Item.GetItemNameByID, id)
            if ok and type(localizedName) == "string" and localizedName ~= "" then
                name = localizedName
            end
        end
        if not icon then
            icon = SafeGetItemIcon(id)
        end
        if not name and onMissingName then onMissingName(id) end
    end
    name = name or fallbackName or (onMissingName and id and ("Loading item #" .. id .. "..."))
        or ("Item " .. tostring(id or "?"))
    if not link and id then
        local hex = (rarity and RARITY_HEX and RARITY_HEX[rarity]) or "ffffffff"
        link = "|c" .. hex .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
    end
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    return name, link, icon
end

-- Broad result lists must not request item data for every row. Cached names
-- and icons are enough until the player inspects one specific result.
local function ResolveCachedItemVisual(itemID, fallbackName)
    local id = tonumber(itemID)
    local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
    local info = id and cache and cache[id]
    local name = (info and info.n) or fallbackName or ("Item " .. tostring(id or "?"))
    local icon = (info and info.ic) or "Interface\\Icons\\INV_Misc_QuestionMark"
    local link = id and ("|cffffffff|Hitem:" .. id ..
        ":0:0:0:0:0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r") or nil
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

local function CreateBox(parent, x, y, width, height, auctionSurface)
    if MarketSync and MarketSync.CreateModernInset then
        return MarketSync.CreateModernInset(parent, x, y, width, height, auctionSurface)
    end
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width, height)
    return box
end

local function StyleStandardGameButton(btn, text)
    if not btn then return btn end
    if (type(text) == "string" or type(text) == "number") and btn.SetText then btn:SetText(text) end
    return btn
end

local RAIL_W = 176
local RAIL_INNER_W = RAIL_W - 16
local PROCESS_LIST = { "ALL", "DISENCHANT", "PROSPECT", "MILL" }
local QUALITY_FILTERS = {
    { key = 2, label = "Unc.", color = "|cff1eff00" },
    { key = 3, label = "Rare", color = "|cff0070dd" },
    { key = 4, label = "Epic", color = "|cffa335ee" },
}
local MAX_RECENT_TARGETS = 3

local registeredPanels = {}

local function CachedItemField(itemID, field)
    local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
    local info = cache and tonumber(itemID) and cache[tonumber(itemID)]
    return info and info[field]
end

local function CreateCheck(parent, x, y, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local text = check.text or check.Text or check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    check.text = text
    text:ClearAllPoints()
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return check
end

local function CreateRailLabel(parent, y, text)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    label:SetText(text)
    return label
end

local function SetToggleButton(btn, active, label)
    btn:SetText(active and ("|cffffd700" .. label .. "|r") or label)
    if active then
        if btn.LockHighlight then btn:LockHighlight() end
    elseif btn.UnlockHighlight then
        btn:UnlockHighlight()
    end
end

-- -------------------------------------------------------------
-- Profession scan confirmation: a short note on the open profession window.
-- -------------------------------------------------------------
local scanToast
function MarketSync.OnProfessionScanned(professionName, total, added)
    local label = (professionName == "First Aid (Health)") and "First Aid" or tostring(professionName)
    for _, p in ipairs(registeredPanels) do
        if p.RefreshProfessionStatus then pcall(p.RefreshProfessionStatus) end
    end
    if MarketSync.ProfessionStatusFrame and MarketSync.ProfessionStatusFrame:IsShown()
        and MarketSync.ProfessionStatusFrame.Refresh then
        MarketSync.ProfessionStatusFrame:Refresh()
    end
    if not UIParent then return end
    if not scanToast then
        scanToast = CreateFrame("Frame", "MarketSyncProfessionScanToast", UIParent, "BackdropTemplate")
        scanToast:SetSize(300, 40)
        scanToast:SetFrameStrata("DIALOG")
        if scanToast.SetBackdrop then
            scanToast:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            scanToast:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
            scanToast:SetBackdropBorderColor(0.31, 0.82, 0.42, 1)
        end
        scanToast.title = scanToast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scanToast.title:SetPoint("TOPLEFT", 10, -7)
        scanToast.title:SetPoint("RIGHT", -10, 0)
        scanToast.title:SetJustifyH("LEFT")
        scanToast.body = scanToast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        scanToast.body:SetPoint("TOPLEFT", scanToast.title, "BOTTOMLEFT", 0, -2)
        scanToast.body:SetPoint("RIGHT", -10, 0)
        scanToast.body:SetJustifyH("LEFT")
        scanToast:Hide()
    end
    local host = (ProfessionsFrame and ProfessionsFrame:IsShown() and ProfessionsFrame)
        or (TradeSkillFrame and TradeSkillFrame:IsShown() and TradeSkillFrame)
        or (CraftFrame and CraftFrame:IsShown() and CraftFrame)
    scanToast:ClearAllPoints()
    if host then
        scanToast:SetPoint("TOP", host, "BOTTOM", 0, -4)
    else
        scanToast:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    scanToast.title:SetText("|cff4fd06aMarketSync saved " .. label .. "|r")
    local addedText = (tonumber(added) or 0) > 0 and string.format(" | %d new since last scan", added) or ""
    scanToast.body:SetText(string.format("%d item recipes%s", tonumber(total) or 0, addedText))
    scanToast:Show()
    scanToast.token = (scanToast.token or 0) + 1
    local token = scanToast.token
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            if scanToast.token == token then scanToast:Hide() end
        end)
    end
end

-- -------------------------------------------------------------
-- Professions window: what is scanned for every character.
-- -------------------------------------------------------------
local STATUS_GLYPH = {
    ready = "|cff4fd06aReady|r",
    stale = "|cffffb347Refresh|r",
    missing = "|cffff8a7aNot scanned|r",
    gathering = "|cffa89e8cGathering|r",
}

function MarketSync.ShowProfessionStatus()
    local frame = MarketSync.ProfessionStatusFrame
    if not frame then
        if MarketSync.CreateModernDialog then
            frame = MarketSync.CreateModernDialog("MarketSyncProfessionStatusFrame", 520, 400, "Professions",
                "Interface\\Icons\\Trade_BlackSmithing")
        else
            frame = CreateFrame("Frame", "MarketSyncProfessionStatusFrame", UIParent, "BackdropTemplate")
            frame:SetSize(520, 400)
            frame:SetPoint("CENTER")
        end
        frame:SetFrameStrata("DIALOG")
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() frame:Hide() end)

        local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        intro:SetPoint("TOPLEFT", 20, -40)
        intro:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
        intro:SetJustifyH("LEFT")
        intro:SetText("Recipes MarketSync knows for each character. Craft Profit uses these lists.")

        frame.lines = {}
        for i = 1, 14 do
            local line = CreateFrame("Frame", nil, frame)
            line:SetSize(480, 18)
            line:SetPoint("TOPLEFT", 20, -62 - (i - 1) * 19)
            line.state = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            line.state:SetPoint("LEFT", 0, 0)
            line.state:SetWidth(74)
            line.state:SetJustifyH("LEFT")
            line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            line.name:SetPoint("LEFT", 78, 0)
            line.name:SetWidth(140)
            line.name:SetJustifyH("LEFT")
            line.info = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            line.info:SetPoint("LEFT", 222, 0)
            line.info:SetPoint("RIGHT", line, "RIGHT", 0, 0)
            line.info:SetJustifyH("LEFT")
            for _, fs in ipairs({ line.state, line.name, line.info }) do
                if fs.SetWordWrap then fs:SetWordWrap(false) end
            end
            line:Hide()
            frame.lines[i] = line
        end

        local steps = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        steps:SetPoint("BOTTOMLEFT", 20, 46)
        steps:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
        steps:SetJustifyH("LEFT")
        steps:SetText("|cffffd7001.|r Open a profession from your spellbook.   |cffffd7002.|r MarketSync reads it on its own."
            .. "   |cffffd7003.|r Close it. The row above turns |cff4fd06aReady|r.")
        frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.status:SetPoint("BOTTOMLEFT", 20, 20)
        frame.status:SetPoint("RIGHT", frame, "RIGHT", -150, 0)
        frame.status:SetJustifyH("LEFT")

        local rescan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        rescan:SetSize(124, 22)
        rescan:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
        rescan:SetText("Rescan open window")
        rescan:SetScript("OnClick", function()
            if not MarketSync.ResyncProfessionCache then return end
            local ok, msg = MarketSync.ResyncProfessionCache()
            frame.status:SetText((ok and "|cff4fd06a" or "|cffffd100") .. tostring(msg or "") .. "|r")
            frame:Refresh()
        end)
        frame.rescanButton = rescan

        function frame:Refresh()
            local entries = {}
            local characters = MarketSync.GetProcessingCraftingCharacters
                and MarketSync.GetProcessingCraftingCharacters() or {}
            for _, choice in ipairs(characters) do
                entries[#entries + 1] = { header = true, text = choice.isCurrent
                    and ("|cffffd700" .. tostring(choice.key) .. "|r  |cffa89e8cthis character|r")
                    or ("|cffffd700" .. tostring(choice.key) .. "|r") }
                for _, row in ipairs(MarketSync.GetProfessionScanStatus
                    and MarketSync.GetProfessionScanStatus(not choice.isCurrent and choice.key or nil) or {}) do
                    entries[#entries + 1] = { row = row }
                end
            end
            for i, line in ipairs(self.lines) do
                local entry = entries[i]
                if not entry then
                    line:Hide()
                elseif entry.header then
                    line.state:SetText("")
                    line.name:SetText(entry.text)
                    line.name:SetWidth(460)
                    line.info:SetText("")
                    line:Show()
                else
                    local row = entry.row
                    line.name:SetWidth(140)
                    line.state:SetText(STATUS_GLYPH[row.state] or "")
                    local rank = row.rank and (" |cffa89e8c" .. tostring(row.rank) .. "|r") or ""
                    line.name:SetText("  " .. tostring(row.label) .. rank)
                    local parts = {}
                    if row.recipes and row.recipes > 0 then
                        parts[#parts + 1] = tostring(row.recipes) .. " recipes"
                    end
                    if row.updatedAt and row.updatedAt > 0 and MarketSync.FormatRelativeTime then
                        parts[#parts + 1] = MarketSync.FormatRelativeTime(row.updatedAt)
                    end
                    if row.state ~= "ready" and row.hint then parts[#parts + 1] = row.hint end
                    if row.usesCraftWindow and row.state == "missing" then
                        parts[#parts + 1] = "(Craft window)"
                    end
                    line.info:SetText("|cffd8ccb4" .. table.concat(parts, " | ") .. "|r")
                    line:Show()
                end
            end
        end
        frame:SetScript("OnShow", function(self) self:Refresh() end)
        MarketSync.ProfessionStatusFrame = frame
        frame:Hide()
    end
    frame.status:SetText("")
    frame:Show()
    frame:Refresh()
    return frame
end

function MarketSync.CreateProcessingPanel(parent)
    local isEmbedded = (parent ~= MarketSync.MainFrame)
    local isLegacyMain = not isEmbedded and MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local LEFT_X = isEmbedded and 10 or (isLegacyMain and 24 or 14)
    local RESULTS_X = LEFT_X + RAIL_W + 10
    local parentWidth = parent.GetWidth and parent:GetWidth() or 0
    local parentHeight = parent.GetHeight and parent:GetHeight() or 0
    local effectiveWidth = parentWidth > 0 and parentWidth or (isEmbedded and 780 or 850)
    local ROW_WIDTH = math.max(360, effectiveWidth - RESULTS_X - 14)
    local tabsY = isEmbedded and -8 or -34
    local bodyTop = isEmbedded and -36 or -62
    local FOOTER_H = 30
    local bottomInset = parent.MarketSyncNativeAuctionFooter and 0 or 8

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    if parent == MarketSync.MainFrame then
        panel:Hide()
    end
    registeredPanels[#registeredPanels + 1] = panel

    panel.activeMode = "target"
    function panel:CancelCachedWork()
        self.cacheRunID = (self.cacheRunID or 0) + 1
    end
    panel:SetScript("OnHide", function(self) self:CancelCachedWork() end)
    panel.selectedTargetID = nil
    panel.selectedProcess = nil
    panel.selectedProfession = nil
    panel.selectedCharacterKey = nil -- nil means the active character
    panel.activeCraftSet = nil
    panel.lastMode = nil
    panel.lastArbitrageResults = {}
    panel.lastCraftResults = {}
    panel.allRows = {}
    panel.filters = {
        onlyProfitable = false,
        hideStale = false,
        madeBy = nil,
        qualities = { [2] = true, [3] = true, [4] = true },
        minLevel = nil,
        maxLevel = nil,
    }
    local pendingItemNames = {}
    local function RequestItemName(itemID)
        local id = tonumber(itemID)
        if not id or pendingItemNames[id] then return end
        pendingItemNames[id] = true
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    panel.selectedCrafts = {}
    panel.selectedArbitrage = {}
    panel.displayRows = {}
    panel.page = 0
    panel.customPage = 0
    local customRowCount = CUSTOM_ROWS

    -- Left rail (settings, or details of the clicked row) and the results table.
    local railBox = CreateBox(panel, LEFT_X, bodyTop, RAIL_W, 300, "controls")
    railBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_X, bottomInset)
    local rightBox = CreateBox(panel, RESULTS_X - 4, bodyTop, ROW_WIDTH + 8, 320, "results")
    rightBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(effectiveWidth - (RESULTS_X + ROW_WIDTH + 4)), bottomInset)
    panel.railBox = railBox
    panel.leftTopBox = railBox
    panel.rightBox = rightBox

    local settingsView = CreateFrame("Frame", nil, railBox)
    settingsView:SetAllPoints(railBox)
    local detailsView = CreateFrame("Frame", nil, railBox)
    detailsView:SetAllPoints(railBox)
    detailsView:Hide()
    panel.settingsView = settingsView
    panel.detailsView = detailsView

    local btnRailSettings = CreateFrame("Button", nil, railBox, "UIPanelButtonTemplate")
    btnRailSettings:SetSize(78, 20)
    btnRailSettings:SetPoint("TOPLEFT", railBox, "TOPLEFT", 8, -6)
    local btnRailDetails = CreateFrame("Button", nil, railBox, "UIPanelButtonTemplate")
    btnRailDetails:SetSize(78, 20)
    btnRailDetails:SetPoint("LEFT", btnRailSettings, "RIGHT", 4, 0)
    local function ShowRailView(view)
        panel.railView = view
        SetControlVisible(settingsView, view ~= "details")
        SetControlVisible(detailsView, view == "details")
        SetToggleButton(btnRailSettings, view ~= "details", "Settings")
        SetToggleButton(btnRailDetails, view == "details", "Details")
    end
    panel.ShowRailView = ShowRailView
    btnRailSettings:SetScript("OnClick", function() ShowRailView("settings") end)
    btnRailDetails:SetScript("OnClick", function() ShowRailView("details") end)
    ShowRailView("settings")

    local modeButtons = {}
    local btnRun
    local ApplyDisplaySort
    local RunActiveMode
    local UpdateResultRows
    local HandleTableMouseWheel
    local RefreshResultHeaders
    local BuildCraftDisplay
    local ApplyFilters
    local ShowDetails
    local UpdateSelectionSummary

    local tableScrollBar
    if MarketSync.CreateModernTableScrollBar and rightBox then
        tableScrollBar = MarketSync.CreateModernTableScrollBar(panel, rightBox, function(newPage)
            panel.page = newPage
            if panel.UpdateResultRows then
                panel.UpdateResultRows()
            elseif UpdateResultRows then
                UpdateResultRows()
            end
        end, 8, -24, FOOTER_H + 2)
        panel.tableScrollBar = tableScrollBar
        tableScrollBar:AttachMouseWheel(rightBox)
        tableScrollBar:AttachMouseWheel(panel)
    end

    local function UpdateRunButtonText()
        if not btnRun then return end
        if panel.activeMode == "process" then
            btnRun:SetText("Run Process")
        elseif panel.activeMode == "craft" then
            btnRun:SetText("Refresh")
        else
            btnRun:SetText("Run Target")
        end
    end

    local function RefreshModeButtons()
        for _, def in ipairs(MODE_OPTIONS) do
            local btn = modeButtons[def.key]
            if btn then
                SetToggleButton(btn, def.key == panel.activeMode, def.label)
            end
        end
    end

    local function CreateModeTab(def, index)
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(isEmbedded and 114 or 124, 24)
        if index == 1 then
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", isEmbedded and 64 or 76, tabsY)
        else
            btn:SetPoint("LEFT", modeButtons[MODE_OPTIONS[index - 1].key], "RIGHT", 5, 0)
        end
        btn:SetText(def.label)

        btn:SetScript("OnClick", function()
            if panel.activeMode ~= def.key then
                panel:CancelCachedWork()
                panel.activeMode = def.key
                panel.selectedCrafts = {}
                panel.selectedArbitrage = {}
                panel.displayRows = {}
                panel.allRows = {}
                if panel.ClearResults then panel:ClearResults() end
                RefreshModeButtons()
                UpdateRunButtonText()
                if panel.RefreshModeControls then
                    panel:RefreshModeControls()
                end
                if panel.RefreshCustomRows then panel.RefreshCustomRows() end
                if ShowDetails then ShowDetails(nil) end
                ShowRailView("settings")
                if def.key == "craft" and RunActiveMode then
                    RunActiveMode()
                end
            end
        end)
        return btn
    end

    modeButtons.target = CreateModeTab(MODE_OPTIONS[1], 1)
    modeButtons.process = CreateModeTab(MODE_OPTIONS[2], 2)
    modeButtons.craft = CreateModeTab(MODE_OPTIONS[3], 3)
    RefreshModeButtons()

    -- Freshness of the market cache used by the last run.
    local priceBadge = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    priceBadge:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, tabsY - 6)
    priceBadge:SetJustifyH("RIGHT")
    priceBadge:SetText("")
    panel.priceBadge = priceBadge

    local parentPrefix = (parent and parent.GetName and parent:GetName()) or "MarketSync"
    local modeControls = { target = {}, process = {}, craft = {} }
    local function Track(mode, control)
        modeControls[mode][#modeControls[mode] + 1] = control
        return control
    end

    -- ===================== Target Material settings =====================
    local targetLabel = Track("target", CreateRailLabel(settingsView, -34, "Target material"))
    local targetInputBox = CreateFrame("EditBox", nil, settingsView, "InputBoxTemplate")
    Track("target", targetInputBox)
    panel.targetInputBox = targetInputBox
    targetInputBox:SetSize(RAIL_INNER_W - 6, 18)
    targetInputBox:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 14, -50)
    targetInputBox:SetAutoFocus(false)
    targetInputBox:SetText("")
    targetInputBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Target material", 1, 0.82, 0)
        GameTooltip:AddLine("Drop an item here, shift-click a link, or type a name or ID and press Enter.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    targetInputBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    targetInputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    local targetHint = Track("target", settingsView:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall"))
    targetHint:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -72)
    targetHint:SetWidth(RAIL_INNER_W)
    targetHint:SetJustifyH("LEFT")
    targetHint:SetText("|cffa89e8cType, drop or shift-click an item.|r")

    local targetDropdown
    local recentButtons = {}
    local function RememberTarget(itemID)
        if not MarketSyncDB then return end
        local list = MarketSyncDB.ProcessingRecentTargets or {}
        local out = { tonumber(itemID) }
        for _, id in ipairs(list) do
            if tonumber(id) ~= tonumber(itemID) and #out < MAX_RECENT_TARGETS then out[#out + 1] = tonumber(id) end
        end
        MarketSyncDB.ProcessingRecentTargets = out
        if panel.RefreshRecentTargets then panel.RefreshRecentTargets() end
    end
    local function SetTargetFromItem(item)
        local itemID = ResolveItemIDFromQuery(item)
        if not itemID then return false end
        local name = SafeGetItemInfo(itemID)
        panel.selectedTargetID = itemID
        targetInputBox:SetText(name and (name .. " (" .. itemID .. ")") or ("Item " .. itemID))
        if targetDropdown then
            SetDropdownLabel(targetDropdown, "Pick from list")
        end
        targetInputBox:ClearFocus()
        if panel.activeMode == "target" and RunActiveMode then RunActiveMode() end
        return true
    end
    panel.SetTargetFromItem = SetTargetFromItem
    local function HandleTargetItemDrop()
        if type(GetCursorInfo) ~= "function" then return false end
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType ~= "item" or not (SetTargetFromItem(itemLink) or SetTargetFromItem(itemID)) then return false end
        if type(ClearCursor) == "function" then ClearCursor() end
        return true
    end
    targetInputBox:SetScript("OnReceiveDrag", HandleTargetItemDrop)
    targetInputBox:SetScript("OnMouseUp", function()
        HandleTargetItemDrop()
    end)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(targetInputBox, {
            onInsertLink = function(_, text)
                return SetTargetFromItem(text)
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
            description = "Drag an item, shift-click an item link, or enter an item name or ID to search",
        })
    end

    targetDropdown = BuildDropdown(parentPrefix .. "ProcessingTargetDropdown", settingsView, RAIL_INNER_W, function(self, level)
        local resetInfo = UIDropDownMenu_CreateInfo()
        resetInfo.text = "Clear target"
        resetInfo.func = function()
            panel.selectedTargetID = nil
            targetInputBox:SetText("")
            SetDropdownLabel(targetDropdown, "Pick from list")
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
            local icon = t.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.itemID))
            -- Native menus measure the label to choose their width. Include the
            -- icon in that measurement instead of anchoring it beyond the text.
            if icon then
                opt.text = opt.text .. "  |T" .. tostring(icon) .. ":16:16:0:0|t  "
            else
                opt.text = opt.text .. "  "
            end
            opt.func = function()
                panel.selectedTargetID = t.itemID
                targetInputBox:SetText(t.name or ("Item #" .. tostring(t.itemID)))
                if panel.activeMode == "target" and RunActiveMode then
                    RunActiveMode()
                end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    Track("target", targetDropdown)
    targetDropdown:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -88)
    SetDropdownLabel(targetDropdown, "Pick from list")

    local recentLabel = Track("target", CreateRailLabel(settingsView, -116, "Recent"))
    for i = 1, MAX_RECENT_TARGETS do
        local btn = CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate")
        btn:SetSize(RAIL_INNER_W, 18)
        btn:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -130 - (i - 1) * 20)
        btn:Hide()
        btn:SetScript("OnClick", function(self)
            if self.itemID then SetTargetFromItem(self.itemID) end
        end)
        recentButtons[i] = btn
    end
    function panel.RefreshRecentTargets()
        local list = MarketSyncDB and MarketSyncDB.ProcessingRecentTargets or {}
        local isTarget = panel.activeMode == "target"
        SetControlVisible(recentLabel, isTarget and #list > 0)
        for i, btn in ipairs(recentButtons) do
            local id = tonumber(list[i])
            btn.itemID = id
            if id and isTarget then
                local name = CachedItemField(id, "n") or SafeGetItemInfo(id) or ("Item " .. id)
                btn:SetText(Truncate(name, 24))
                btn:Show()
            else
                btn:Hide()
            end
        end
    end

    local madeByLabel = Track("target", CreateRailLabel(settingsView, -196, "Made by"))
    local madeByDropdown
    madeByDropdown = BuildDropdown(parentPrefix .. "ProcessingMadeByDropdown", settingsView, RAIL_INNER_W, function(_, level)
        for _, p in ipairs(GetProcessOptions()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = (p == "ALL") and "Any process" or FormatProcessType(p)
            info.checked = (panel.filters.madeBy == nil and p == "ALL") or panel.filters.madeBy == p
            info.func = function()
                panel.filters.madeBy = (p ~= "ALL") and p or nil
                SetDropdownLabel(madeByDropdown, info.text)
                if ApplyFilters then ApplyFilters() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    Track("target", madeByDropdown)
    madeByDropdown:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -210)
    SetDropdownLabel(madeByDropdown, "Any process")

    -- ===================== Process Scan settings =====================
    Track("process", CreateRailLabel(settingsView, -34, "Process"))
    local processButtons = {}
    for i, p in ipairs(PROCESS_LIST) do
        local btn = CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate")
        btn:SetSize(RAIL_INNER_W, 20)
        btn:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -48 - (i - 1) * 22)
        btn.processType = p
        btn:SetScript("OnClick", function(self)
            if not IsSupportedProcessType(p ~= "ALL" and p or nil) then return end
            panel.selectedProcess = (p == "ALL") and nil or p
            if panel.RefreshProcessButtons then panel.RefreshProcessButtons() end
            if panel.activeMode == "process" and RunActiveMode then RunActiveMode() end
        end)
        processButtons[i] = Track("process", btn)
    end
    panel.processButtons = processButtons
    function panel.RefreshProcessButtons()
        for _, btn in ipairs(processButtons) do
            local p = btn.processType
            local supported = IsSupportedProcessType(p ~= "ALL" and p or nil)
            local label = (p == "ALL") and "All processes" or FormatProcessType(p)
            local active = (panel.selectedProcess == nil and p == "ALL") or panel.selectedProcess == p
            if not supported then
                btn:SetText("|cff8a806e" .. label .. " (not on this client)|r")
                if btn.SetEnabled then btn:SetEnabled(false) end
            else
                if btn.SetEnabled then btn:SetEnabled(true) end
                SetToggleButton(btn, active, label)
            end
        end
    end

    Track("process", CreateRailLabel(settingsView, -142, "Quality"))
    local qualityButtons = {}
    local qualityW = math.floor((RAIL_INNER_W - 8) / 3)
    for i, q in ipairs(QUALITY_FILTERS) do
        local btn = CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate")
        btn:SetSize(qualityW, 20)
        btn:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8 + (i - 1) * (qualityW + 4), -156)
        btn:SetScript("OnClick", function()
            panel.filters.qualities[q.key] = not panel.filters.qualities[q.key]
            if panel.RefreshQualityButtons then panel.RefreshQualityButtons() end
            if ApplyFilters then ApplyFilters() end
        end)
        qualityButtons[i] = Track("process", btn)
    end
    function panel.RefreshQualityButtons()
        for i, q in ipairs(QUALITY_FILTERS) do
            local on = panel.filters.qualities[q.key]
            qualityButtons[i]:SetText(on and (q.color .. q.label .. "|r") or ("|cff8a806e" .. q.label .. "|r"))
        end
    end

    Track("process", CreateRailLabel(settingsView, -184, "Item level"))
    local function LevelBox(x)
        local box = CreateFrame("EditBox", nil, settingsView, "InputBoxTemplate")
        box:SetSize(44, 18)
        box:SetPoint("TOPLEFT", settingsView, "TOPLEFT", x, -200)
        box:SetAutoFocus(false)
        if box.SetNumeric then box:SetNumeric(true) end
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return Track("process", box)
    end
    local minLevelBox = LevelBox(14)
    local levelTo = Track("process", settingsView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    levelTo:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 64, -203)
    levelTo:SetText("to")
    local maxLevelBox = LevelBox(84)
    local function ReadLevels()
        panel.filters.minLevel = tonumber(minLevelBox:GetText())
        panel.filters.maxLevel = tonumber(maxLevelBox:GetText())
        if ApplyFilters then ApplyFilters() end
    end
    for _, box in ipairs({ minLevelBox, maxLevelBox }) do
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ReadLevels() end)
        box:SetScript("OnEditFocusLost", ReadLevels)
    end

    -- ===================== Craft Profit settings =====================
    local professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions()) or {}
    panel.selectedProfession = "ALL"
    panel.craftSaleTarget = "ah" -- "ah" (resell on AH -5% cut) or "vendor" (bulk vendor shuffle, 0% cut)

    local RefreshProfessionOptions
    local characterLabel = Track("craft", CreateRailLabel(settingsView, -34, "Crafter"))

    local characterDropdown
    characterDropdown = BuildDropdown(parentPrefix .. "ProcessingCharacterDropdown", settingsView, RAIL_INNER_W, function(self, level)
        local choices = MarketSync.GetProcessingCraftingCharacters and MarketSync.GetProcessingCraftingCharacters() or {}
        for _, choice in ipairs(choices) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = choice.isCurrent and ("This character: " .. choice.key) or choice.key
            opt.tooltipTitle = choice.key
            opt.tooltipText = choice.isCurrent and "Current character's known recipes"
                or (choice.scopeKnown
                    and "Cached recipes from this character; profitability uses this realm's current auction prices."
                    or "Older cache: game version and faction were not recorded. Reopen this character's profession to verify its recipes before relying on profit estimates.")
            opt.func = function()
                panel.selectedCharacterKey = choice.isCurrent and nil or choice.key
                SetDropdownLabel(characterDropdown, choice.isCurrent and "This character" or Truncate(choice.key, 17))
                panel.activeCraftSet = nil
                panel.selectedCrafts = {}
                if RefreshProfessionOptions then RefreshProfessionOptions() end
                if panel.RefreshProfessionStatus then panel.RefreshProfessionStatus() end
                if panel.activeMode == "craft" and RunActiveMode then RunActiveMode() end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    Track("craft", characterDropdown)
    characterDropdown:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -48)
    SetDropdownLabel(characterDropdown, "This character")

    local professionLabel = Track("craft", CreateRailLabel(settingsView, -76, "Profession"))

    local professionDropdown
    professionDropdown = BuildDropdown(parentPrefix .. "CraftProfDropdown", settingsView, RAIL_INNER_W, function(self, level)
        professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions(panel.selectedCharacterKey)) or professionOptions
        local options = { "ALL" }
        for _, name in ipairs(professionOptions) do options[#options + 1] = name end
        for _, p in ipairs(options) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = p
            opt.func = function()
                panel.selectedProfession = p
                panel.selectedCrafts = {}
                SetDropdownLabel(professionDropdown, p)
                if panel.RefreshProfessionStatus then panel.RefreshProfessionStatus() end
                if panel.activeMode == "craft" and panel:IsShown() and RunActiveMode then
                    RunActiveMode()
                end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    Track("craft", professionDropdown)
    professionDropdown:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -90)
    SetDropdownLabel(professionDropdown, "ALL")

    local profStatusText = Track("craft", settingsView:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall"))
    profStatusText:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -114)
    profStatusText:SetWidth(RAIL_INNER_W)
    profStatusText:SetJustifyH("LEFT")
    panel.profStatusText = profStatusText
    function panel.RefreshProfessionStatus()
        if not MarketSync.GetProfessionScanStatus then
            profStatusText:SetText("")
            return
        end
        local rows = MarketSync.GetProfessionScanStatus(panel.selectedCharacterKey)
        local prof = panel.selectedProfession
        if prof and prof ~= "ALL" then
            for _, row in ipairs(rows) do
                if row.name == prof then
                    local color = row.state == "ready" and "|cff4fd06a" or "|cffffb347"
                    local age = (row.updatedAt and row.updatedAt > 0 and MarketSync.FormatRelativeTime)
                        and (" | " .. MarketSync.FormatRelativeTime(row.updatedAt)) or ""
                    if row.state == "missing" then
                        profStatusText:SetText(color .. tostring(row.hint) .. "|r")
                    else
                        profStatusText:SetText(color .. tostring(row.recipes or 0) .. " recipes" .. age .. "|r"
                            .. (row.state == "stale" and ("\n|cffffb347" .. tostring(row.hint) .. "|r") or ""))
                    end
                    return
                end
            end
        end
        local ready, needs = 0, 0
        for _, row in ipairs(rows) do
            if row.state == "ready" then ready = ready + 1
            elseif row.state == "missing" or row.state == "stale" then needs = needs + 1 end
        end
        if needs > 0 then
            profStatusText:SetText(string.format("|cff4fd06a%d ready|r | |cffffb347%d need a scan|r", ready, needs))
        elseif ready > 0 then
            profStatusText:SetText(string.format("|cff4fd06a%d professions ready|r", ready))
        else
            profStatusText:SetText("|cffffb347Open a profession window to scan it.|r")
        end
    end

    Track("craft", CreateRailLabel(settingsView, -146, "Sell to"))
    local halfW = math.floor((RAIL_INNER_W - 4) / 2)
    local btnSellAH = Track("craft", CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate"))
    btnSellAH:SetSize(halfW, 20)
    btnSellAH:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -160)
    local btnSellVendor = Track("craft", CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate"))
    btnSellVendor:SetSize(halfW, 20)
    btnSellVendor:SetPoint("LEFT", btnSellAH, "RIGHT", 4, 0)
    panel.sellButtons = { ah = btnSellAH, vendor = btnSellVendor }
    local function RefreshSaleTarget()
        SetToggleButton(btnSellAH, panel.craftSaleTarget ~= "vendor", "Auction")
        SetToggleButton(btnSellVendor, panel.craftSaleTarget == "vendor", "Vendor")
    end
    local function SetSaleTarget(target)
        if panel.craftSaleTarget == target then return end
        panel.craftSaleTarget = target
        RefreshSaleTarget()
        if RefreshResultHeaders then RefreshResultHeaders() end
        if panel.activeMode == "craft" and RunActiveMode then RunActiveMode() end
    end
    btnSellAH:SetScript("OnClick", function() SetSaleTarget("ah") end)
    btnSellVendor:SetScript("OnClick", function() SetSaleTarget("vendor") end)
    btnSellAH:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sell on the Auction House", 1, 0.82, 0)
        GameTooltip:AddLine("Auction prices less material cost and the 5% cut.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnSellAH:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btnSellVendor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sell to a vendor", 1, 0.82, 0)
        GameTooltip:AddLine("Vendor sell price less material cost. No fee.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnSellVendor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    RefreshSaleTarget()

    local btnProfessions = Track("craft", CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate"))
    btnProfessions:SetSize(RAIL_INNER_W, 20)
    btnProfessions:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 8, -232)
    btnProfessions:SetText("Professions...")
    btnProfessions:SetScript("OnClick", function() MarketSync.ShowProfessionStatus() end)
    btnProfessions:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Professions", 1, 0.82, 0)
        GameTooltip:AddLine("See which professions are scanned for each character, and how to scan the rest.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnProfessions:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.professionsButton = btnProfessions

    -- ===================== Shared filters =====================
    local function FilterY()
        if panel.activeMode == "target" then return -238 end
        if panel.activeMode == "process" then return -226 end
        return -184
    end
    local chkProfitable = CreateCheck(settingsView, 6, -238, "Only profitable", function(on)
        panel.filters.onlyProfitable = on
        if ApplyFilters then ApplyFilters() end
    end)
    local chkStale = CreateCheck(settingsView, 6, -258, "Hide stale prices", function(on)
        panel.filters.hideStale = on
        if ApplyFilters then ApplyFilters() end
    end)
    panel.profitableCheck = chkProfitable
    panel.staleCheck = chkStale
    local function PlaceFilterChecks()
        local y = FilterY()
        chkProfitable:ClearAllPoints()
        chkProfitable:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 6, y)
        chkStale:ClearAllPoints()
        chkStale:SetPoint("TOPLEFT", settingsView, "TOPLEFT", 6, y - 20)
        chkStale.text:SetText(panel.activeMode == "process" and "Hide partial / stale" or "Hide stale prices")
    end

    -- ===================== Results footer =====================
    btnRun = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local btnExport = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local btnTrack = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    local statusSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.statusSummary = statusSummary
    panel.runButton = btnRun

    btnRun:SetSize(84, 22)
    btnExport:SetSize(62, 22)
    btnTrack:SetSize(60, 22)

    btnRun:SetPoint("BOTTOMRIGHT", rightBox, "BOTTOMRIGHT", -112, 5)
    btnExport:SetPoint("RIGHT", btnRun, "LEFT", -4, 0)
    btnTrack:SetPoint("RIGHT", btnExport, "LEFT", -4, 0)

    statusSummary:SetPoint("BOTTOMLEFT", rightBox, "BOTTOMLEFT", 8, 10)
    statusSummary:SetPoint("RIGHT", btnTrack, "LEFT", -8, 0)
    statusSummary:SetJustifyH("LEFT")
    if statusSummary.SetWordWrap then statusSummary:SetWordWrap(false) end
    btnExport:SetText("Export")
    btnTrack:SetText("Track")
    local function OpenCraftSidecar(itemID)
        local host = AuctionHouseFrame or AuctionFrame or MarketSync.MainFrame
        if MarketSync.CreateAHSidecar then MarketSync.CreateAHSidecar(host) end
        local sidecar = MarketSync.AHSidecar
        if not sidecar or not sidecar.Frame then return false end
        if parent == MarketSync.MainFrame then
            if sidecar.ShowForMain then sidecar.ShowForMain("craft") end
        else
            if sidecar.SetVisibleForAH then sidecar.SetVisibleForAH(true) end
            if sidecar.SetExpanded then sidecar.SetExpanded(true) end
            if sidecar.SetMode then sidecar.SetMode("craft") end
        end
        if itemID and sidecar.AddCraftRecipe then
            local ok, reason = sidecar.AddCraftRecipe(itemID)
            if not ok then print("|cffff4444[MarketSync]|r " .. tostring(reason)) end
            return ok
        end
        return true
    end
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
    end

    panel.sortField = "valueSort"
    panel.sortAscending = false

    local itemWidth = math.floor(ROW_WIDTH * 0.30)
    local typeWidth = math.floor(ROW_WIDTH * 0.12)
    local statusWidth = 66
    local priceWidth = math.floor((ROW_WIDTH - itemWidth - typeWidth - statusWidth) / 4)
    itemWidth = ROW_WIDTH - typeWidth - statusWidth - (priceWidth * 4)
    local colDefs = {
        { name = "Item",     width = itemWidth,   sortKey = "itemSort"   },
        { name = "Type",     width = typeWidth,   sortKey = "typeSort"   },
        { name = "Value",    width = priceWidth,  sortKey = "valueSort"  },
        { name = "Max/ea",   width = priceWidth,  sortKey = "maxSort"    },
        { name = "AH/ea",    width = priceWidth,  sortKey = "liveSort"   },
        { name = "Edge",     width = priceWidth,  sortKey = "deltaSort"  },
        { name = "Status",   width = statusWidth, sortKey = "statusSort" },
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

    local rowHeight = isEmbedded and 36 or 37
    local usableHeight = parentHeight > 0 and parentHeight or (isEmbedded and 440 or 430)
    local hdrY = bodyTop - 4
    local rowStartY = hdrY - 22
    local numResultsPerPage = math.max(1, math.min(10,
        math.floor((usableHeight + rowStartY - FOOTER_H - bottomInset - 6) / rowHeight)))

    local colX = RESULTS_X - 2
    for i, col in ipairs(colDefs) do
        local hdr = MarketSync.CreateAHColumnHeader and MarketSync.CreateAHColumnHeader(panel, col.width, 20, col.name, col.sortKey, true)
        if not hdr then
            hdr = CreateFrame("Button", nil, panel, "BackdropTemplate")
            hdr:SetSize(col.width, 20)
            hdr.label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hdr.label:SetPoint("LEFT", 6, 0)
            hdr.label:SetPoint("RIGHT", -15, 0)
            hdr.label:SetText(col.name)
        end
        if hdr.label and hdr.label.SetWordWrap then
            hdr.label:SetWordWrap(false)
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

    local TARGET_HEADERS = {
        { "Item", "Input item you would buy and process." },
        { "Process", "How the item turns into the target material." },
        { "Yield", "Expected number of target materials per input item." },
        { "Buy under", "Break-even buy price per input item after the 5% auction cut on the material." },
        { "AH now", "Current auction price per input item." },
        { "Edge", "Profit per input item: break-even price minus the current auction price." },
        { "Status", "GOOD: buy under break-even. MISS: too expensive. STALE: a price is over 24 hours old." },
    }
    local PROCESS_HEADERS = {
        { "Item", "Input item you would buy and process." },
        { "Process", "Processing method." },
        { "Value", "Average value of the results per input item, before the 5% auction cut." },
        { "Buy under", "Break-even buy price per input item after the 5% auction cut." },
        { "AH now", "Current auction price per input item." },
        { "Edge", "Profit per input item: break-even price minus the current auction price." },
        { "Status", "GOOD: buy under break-even. PARTIAL: some result prices are missing. STALE: a price is over 24 hours old." },
    }
    local CRAFT_HEADERS = {
        { "Item", "Crafted item." },
        { "Skill", "Recipe difficulty colour for this crafter." },
        { "Profit", "Expected sale after the 5% cut, minus the full material cost of one craft." },
        { "ROI", "Profit as a share of the material cost." },
        { "Mats", "Current cost of all materials for one craft." },
        { "Sells for", "Expected auction sale for one craft after the 5% cut." },
        { "Status", "GOOD: profitable. MISS: loses money. STALE: a price is over 24 hours old." },
    }
    local VENDOR_CRAFT_HEADERS = {
        { "Item", "Crafted item." },
        { "Skill", "Recipe difficulty colour for this crafter." },
        { "Vendor+", "Vendor payout minus the full material cost of one craft. No fee." },
        { "ROI", "Profit as a share of the material cost." },
        { "Mats", "Current cost of all materials for one craft." },
        { "Vendor pays", "Vendor sell price for one craft." },
        { "Status", "Whether buying the materials and selling the craft to a vendor makes money." },
    }

    RefreshResultHeaders = function()
        local definitions = (panel.activeMode == "process") and PROCESS_HEADERS or TARGET_HEADERS
        if panel.activeMode == "craft" then
            definitions = (panel.craftSaleTarget == "vendor") and VENDOR_CRAFT_HEADERS or CRAFT_HEADERS
        end
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
        row.iconButton = iconButton
        local iconTex = iconButton:CreateTexture(nil, "BORDER")
        iconTex:SetAllPoints()
        row.iconTex = iconTex

        local iconBorder = iconButton:CreateTexture(nil, "ARTWORK")
        iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        iconBorder:SetSize(60, 60)
        iconBorder:SetPoint("CENTER")

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", 34, 0)
        rowBg:SetPoint("BOTTOMRIGHT", 0, 0)
        if i % 2 == 0 then
            rowBg:SetColorTexture(MarketSync.GetThemeColor("rowEven"))
        else
            rowBg:SetColorTexture(MarketSync.GetThemeColor("rowOdd"))
        end
        row.rowBg = rowBg

        local c1 = colDefs[1].width
        local c2 = c1 + colDefs[2].width
        local c3 = c2 + colDefs[3].width
        local c4 = c3 + colDefs[4].width
        local c5 = c4 + colDefs[5].width
        local c6 = c5 + colDefs[6].width

        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.nameText:SetPoint("LEFT", iconButton, "RIGHT", 6, 0)
        row.nameText:SetPoint("RIGHT", row, "LEFT", c1 - 4, 0)
        row.nameText:SetJustifyH("LEFT")
        if row.nameText.SetWordWrap then row.nameText:SetWordWrap(false) end

        row.typeText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.typeText:SetPoint("LEFT", row, "LEFT", c1 + 4, 0)
        row.typeText:SetPoint("RIGHT", row, "LEFT", c2 - 4, 0)
        row.typeText:SetJustifyH("LEFT")

        row.valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.valueText:SetPoint("LEFT", row, "LEFT", c2 + 4, 0)
        row.valueText:SetPoint("RIGHT", row, "LEFT", c3 - 4, 0)
        row.valueText:SetJustifyH("RIGHT")

        row.maxText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.maxText:SetPoint("LEFT", row, "LEFT", c3 + 4, 0)
        row.maxText:SetPoint("RIGHT", row, "LEFT", c4 - 4, 0)
        row.maxText:SetJustifyH("RIGHT")

        row.liveText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.liveText:SetPoint("LEFT", row, "LEFT", c4 + 4, 0)
        row.liveText:SetPoint("RIGHT", row, "LEFT", c5 - 4, 0)
        row.liveText:SetJustifyH("RIGHT")

        row.deltaText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.deltaText:SetPoint("LEFT", row, "LEFT", c5 + 4, 0)
        row.deltaText:SetPoint("RIGHT", row, "LEFT", c6 - 4, 0)
        row.deltaText:SetJustifyH("RIGHT")

        row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.statusText:SetPoint("LEFT", row, "LEFT", c6 + 6, 0)
        row.statusText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.statusText:SetJustifyH("LEFT")
        for _, label in ipairs({ row.typeText, row.valueText, row.maxText, row.liveText, row.deltaText, row.statusText }) do
            if label.SetWordWrap then label:SetWordWrap(false) end
        end

        local createNativeHighlight = MarketSync.CreateForeverAuctionRowHighlight
        local selectedBg = createNativeHighlight and createNativeHighlight(row, true)
        if not selectedBg then
            selectedBg = row:CreateTexture(nil, "BACKGROUND")
            selectedBg:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
            selectedBg:SetVertexColor(1, 0.8, 0, 0.45)
            selectedBg:SetBlendMode("ADD")
            selectedBg:SetAllPoints(row)

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
            highlight:SetBlendMode("ADD")
            if highlight.SetAlpha then highlight:SetAlpha(0.38) end
            highlight:SetSize(ROW_WIDTH - 38, 32)
            highlight:SetPoint("TOPLEFT", 33, -3)
            highlight:SetTexCoord(0, 1.0, 0, 0.578125)
        else
            createNativeHighlight(row)
        end
        selectedBg:Hide()
        row.selectedBg = selectedBg

        local function ShowRowTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            local tooltipSet = false
            if row.link then
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
                if ok then
                    tooltipSet = true
                elseif row.itemID then
                    local ok2 = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(row.itemID))
                    tooltipSet = ok2
                end
            elseif row.itemID then
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(row.itemID))
                tooltipSet = ok
            end
            if not tooltipSet then
                local name = (row.nameText and row.nameText.GetText and row.nameText:GetText()) or tostring(row.itemID or "Unknown")
                GameTooltip:SetText(name, 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            if row.data and row.data.approximate then
                GameTooltip:AddLine(MarketSync.FOREVER_DISENCHANT_NOTE, 1, 0.67, 0, true)
            end
            GameTooltip:AddLine("|cffa89e8cClick for details and to select. Right-click for more.|r", 1, 1, 1, true)
            GameTooltip:Show()
        end
        row.ShowTooltip = ShowRowTooltip

        iconButton:SetScript("OnEnter", function(self)
            row:LockHighlight()
            ShowRowTooltip(self)
        end)
        iconButton:SetScript("OnLeave", function()
            row:UnlockHighlight()
            GameTooltip:Hide()
        end)
        local function HandleRowClick(button)
            if row.link and (HandleModifiedItemClick(row.link) or (IsModifiedClick("CHATLINK") and ChatEdit_InsertLink and ChatEdit_InsertLink(row.link))) then
                return
            end

            local isCraft = (panel.lastMode == "craft")
            local idKey = isCraft and row.craftID or row.itemID
            local selectTable = isCraft and panel.selectedCrafts or panel.selectedArbitrage

            if not idKey then return end

            if button == "RightButton" then
                local isSelected = selectTable[idKey] and true or false
                local customActions = {
                    {
                        text = isSelected and "Deselect" or "Select",
                        func = function()
                            selectTable[idKey] = not isSelected and true or nil
                            row.selectedBg:SetShown(not isSelected)
                            if row.data then row.data.isSelected = not isSelected end
                            if UpdateSelectionSummary then UpdateSelectionSummary() end
                        end
                    },
                    {
                        text = "Create Price Alert...",
                        func = function()
                            if MarketSync.OpenAlertEditorWithItem then
                                MarketSync.OpenAlertEditorWithItem(row.itemID or row.link, row.data and row.data.trackThreshold,
                                    panel.lastMode == "craft" and "Craft Profit" or "Processing")
                            end
                        end
                    },
                    {
                        text = "Add to Favorites",
                        func = function()
                            if MarketSync.Favorites and MarketSync.Favorites.AddToList and row.itemID then
                                MarketSync.Favorites.AddToList("Favorites", row.itemID)
                                print("|cFF00FF00[MarketSync]|r Added " .. tostring((row.data and row.data.name) or (row.nameText and row.nameText:GetText()) or "item") .. " to Favorites.")
                            end
                        end
                    }
                }
                if isCraft and row.itemID then
                    table.insert(customActions, 2, {
                        text = "Add to Craft List",
                        func = function() OpenCraftSidecar(row.itemID) end,
                    })
                end
                if MarketSync.ShowItemContextMenu then
                    MarketSync.ShowItemContextMenu(row, {
                        itemID = row.itemID,
                        itemLink = row.link,
                        itemName = (row.data and row.data.name) or (row.nameText and row.nameText:GetText()),
                        icon = row.iconTex and row.iconTex:GetTexture(),
                        price = row.data and row.data.liveSort or nil,
                        customActions = customActions,
                    })
                end
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
            if ShowDetails and row.data then ShowDetails(row.data) end
            if UpdateSelectionSummary then UpdateSelectionSummary() end
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
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(self, delta)
            if HandleTableMouseWheel then
                HandleTableMouseWheel(delta)
            end
        end)
        iconButton:EnableMouseWheel(true)
        iconButton:SetScript("OnMouseWheel", function(self, delta)
            if HandleTableMouseWheel then
                HandleTableMouseWheel(delta)
            end
        end)
        if tableScrollBar then
            tableScrollBar:AttachMouseWheel(row)
            tableScrollBar:AttachMouseWheel(iconButton)
        end
        panel.resultRows[i] = row
    end


    panel.noResultsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noResultsText:SetPoint("TOP", rightBox, "TOP", 0, -110)
    panel.noResultsText:SetWidth(ROW_WIDTH - 40)
    panel.noResultsText:SetText("|cff888888Run a mode to see results.|r")
    panel.noResultsText:Show()

    local prevBtn = CreateFrame("Button", nil, panel)
    prevBtn:SetSize(20, 20)
    prevBtn:SetPoint("BOTTOMRIGHT", rightBox, "BOTTOMRIGHT", -32, 6)
    prevBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local pnt = prevBtn.GetNormalTexture and prevBtn:GetNormalTexture()
    if pnt and pnt.SetVertexColor then pnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) end

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(20, 20)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local nnt = nextBtn.GetNormalTexture and nextBtn:GetNormalTexture()
    if nnt and nnt.SetVertexColor then nnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) end

    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.pageText:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0)
    panel.pageText:SetText("1/1")

    -- ===================== Details view =====================
    local detailIcon = detailsView:CreateTexture(nil, "ARTWORK")
    detailIcon:SetSize(32, 32)
    detailIcon:SetPoint("TOPLEFT", detailsView, "TOPLEFT", 8, -34)
    local detailName = detailsView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    detailName:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 6, 0)
    detailName:SetWidth(RAIL_W - 56)
    detailName:SetJustifyH("LEFT")
    if detailName.SetWordWrap then detailName:SetWordWrap(false) end
    local detailSub = detailsView:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    detailSub:SetPoint("TOPLEFT", detailName, "BOTTOMLEFT", 0, -3)
    detailSub:SetWidth(RAIL_W - 56)
    detailSub:SetJustifyH("LEFT")

    local function StatBox(x, labelText)
        local box = CreateFrame("Frame", nil, detailsView)
        box:SetSize(math.floor((RAIL_INNER_W - 4) / 2), 34)
        box:SetPoint("TOPLEFT", detailsView, "TOPLEFT", x, -72)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.35)
        box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
        box.label:SetPoint("TOPLEFT", 5, -4)
        box.label:SetText(labelText)
        box.value = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        box.value:SetPoint("BOTTOMLEFT", 5, 4)
        box.value:SetPoint("RIGHT", box, "RIGHT", -4, 0)
        box.value:SetJustifyH("LEFT")
        return box
    end
    local statA = StatBox(8, "Profit")
    local statB = StatBox(12 + math.floor((RAIL_INNER_W - 4) / 2), "ROI")

    local detailLinesText = detailsView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detailLinesText:SetPoint("TOPLEFT", detailsView, "TOPLEFT", 8, -114)
    detailLinesText:SetPoint("BOTTOMRIGHT", detailsView, "BOTTOMRIGHT", -8, 60)
    detailLinesText:SetJustifyH("LEFT")
    if detailLinesText.SetJustifyV then detailLinesText:SetJustifyV("TOP") end
    if detailLinesText.SetSpacing then detailLinesText:SetSpacing(2) end

    local detailEmpty = detailsView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detailEmpty:SetPoint("TOPLEFT", detailsView, "TOPLEFT", 10, -40)
    detailEmpty:SetWidth(RAIL_INNER_W)
    detailEmpty:SetJustifyH("LEFT")
    detailEmpty:SetText("|cffa89e8cClick a result to see where its numbers come from.|r")

    local btnDetailSearch = CreateFrame("Button", nil, detailsView, "UIPanelButtonTemplate")
    btnDetailSearch:SetSize(RAIL_INNER_W, 22)
    btnDetailSearch:SetPoint("BOTTOMLEFT", detailsView, "BOTTOMLEFT", 8, 32)
    btnDetailSearch:SetText("Search in AH")
    local btnDetailList = CreateFrame("Button", nil, detailsView, "UIPanelButtonTemplate")
    btnDetailList:SetSize(halfW, 22)
    btnDetailList:SetPoint("BOTTOMLEFT", detailsView, "BOTTOMLEFT", 8, 8)
    local btnDetailAlert = CreateFrame("Button", nil, detailsView, "UIPanelButtonTemplate")
    btnDetailAlert:SetSize(halfW, 22)
    btnDetailAlert:SetPoint("LEFT", btnDetailList, "RIGHT", 4, 0)
    btnDetailAlert:SetText("Alert")
    panel.detailButtons = { search = btnDetailSearch, list = btnDetailList, alert = btnDetailAlert }

    local function YieldLines(itemID)
        local def = MarketSync.ProcessingData and MarketSync.ProcessingData[tonumber(itemID)]
        if type(def) ~= "table" or type(def.yields) ~= "table" or #def.yields == 0 then return nil end
        local lines = { ColorLabel("Possible results:") }
        for i, y in ipairs(def.yields) do
            if i > 5 then lines[#lines + 1] = ColorMuted("..."); break end
            local name = ResolveCachedItemVisual(y.itemID)
            local chance = tonumber(y.chance) or tonumber(y.probability)
            local qty = (y.min and y.max and y.min ~= y.max) and (tostring(y.min) .. "-" .. tostring(y.max))
                or tostring(y.qty or y.min or 1)
            local chanceText = chance and string.format(" %d%%", math.floor((chance <= 1 and chance * 100 or chance) + 0.5)) or ""
            local price = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(y.itemID)
            lines[#lines + 1] = string.format("%s x%s%s %s", Truncate(name, 18), qty, ColorMuted(chanceText),
                price and price > 0 and ("|cffffffff" .. MoneyText(price) .. "|r") or ColorMuted("no price"))
        end
        return lines
    end

    ShowDetails = function(data)
        panel.detailData = data
        if not data then
            for _, region in ipairs({ detailIcon, detailName, detailSub, detailLinesText }) do region:Hide() end
            statA:Hide(); statB:Hide()
            btnDetailSearch:Hide(); btnDetailList:Hide(); btnDetailAlert:Hide()
            detailEmpty:Show()
            return
        end
        detailEmpty:Hide()
        for _, region in ipairs({ detailIcon, detailName, detailSub, detailLinesText }) do region:Show() end
        statA:Show(); statB:Show()
        btnDetailSearch:Show(); btnDetailList:Show(); btnDetailAlert:Show()
        detailIcon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local quality = CachedItemField(data.itemID, "r")
        local hex = quality and RARITY_HEX and RARITY_HEX[quality]
        detailName:SetText(hex and ("|c" .. hex .. tostring(data.nameText) .. "|r") or tostring(data.nameText or ""))
        detailSub:SetText("|cffa89e8c" .. MarketSync.StripColorCodes(tostring(data.typeText or "")) .. "|r")
        local isCraft = panel.lastMode == "craft"
        statA.label:SetText(isCraft and "Profit" or "Edge")
        statA.value:SetText(isCraft and tostring(data.valueText or "-") or tostring(data.deltaText or "-"))
        statB.label:SetText("ROI")
        statB.value:SetText(data.roiText or "-")
        local lines = {}
        if not isCraft then
            for _, line in ipairs(YieldLines(data.itemID) or {}) do lines[#lines + 1] = line end
        end
        for _, line in ipairs(data.detailLines or {}) do lines[#lines + 1] = line end
        detailLinesText:SetText(table.concat(lines, "\n"))
        btnDetailList:SetText(isCraft and "+ Craft list" or "+ Favorites")
        ShowRailView("details")
    end
    panel.ShowDetails = ShowDetails
    ShowDetails(nil)

    btnDetailSearch:SetScript("OnClick", function()
        local data = panel.detailData
        if not data or not data.itemID then return end
        local ok = MarketSync.SearchInAuctionHouse and MarketSync.SearchInAuctionHouse(data.itemID)
        if not ok then
            statusSummary:SetText("|cffffd100Open the Auction House to search for this item.|r")
        end
    end)
    btnDetailList:SetScript("OnClick", function()
        local data = panel.detailData
        if not data or not data.itemID then return end
        if panel.lastMode == "craft" then
            OpenCraftSidecar(data.itemID)
        elseif MarketSync.Favorites and MarketSync.Favorites.AddToList then
            MarketSync.Favorites.AddToList("Favorites", data.itemID)
            statusSummary:SetText("|cff00ff00Added " .. tostring(data.nameText) .. " to Favorites.|r")
        end
    end)
    btnDetailAlert:SetScript("OnClick", function()
        local data = panel.detailData
        if not data or not data.itemID or not MarketSync.OpenAlertEditorWithItem then return end
        MarketSync.OpenAlertEditorWithItem(data.itemID, data.trackThreshold,
            panel.lastMode == "craft" and "Craft Profit" or "Processing")
    end)

    -- ===================== Saved views (bottom of the rail) =====================
    -- Short hosts (Classic AH) keep two saved rows so the filters stay clear.
    local railHeight = usableHeight + bodyTop - bottomInset
    customRowCount = (railHeight < 370) and 2 or CUSTOM_ROWS
    local savedBox = CreateFrame("Frame", nil, settingsView)
    savedBox:SetPoint("BOTTOMLEFT", settingsView, "BOTTOMLEFT", 0, 0)
    savedBox:SetPoint("BOTTOMRIGHT", settingsView, "BOTTOMRIGHT", 0, 0)
    savedBox:SetHeight(28 + customRowCount * 20)
    panel.leftBottomBox = savedBox
    panel.savedBox = savedBox
    local savedDivider = savedBox:CreateTexture(nil, "ARTWORK")
    savedDivider:SetPoint("TOPLEFT", 8, 0)
    savedDivider:SetPoint("TOPRIGHT", -8, 0)
    savedDivider:SetHeight(1)
    savedDivider:SetColorTexture(1, 0.82, 0, 0.18)

    local customTitle = savedBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    customTitle:SetPoint("TOPLEFT", 8, -7)
    customTitle:SetText("Saved views")

    local btnSaveCustom = CreateFrame("Button", nil, savedBox, "UIPanelButtonTemplate")
    btnSaveCustom:SetSize(62, 18)
    btnSaveCustom:SetPoint("TOPRIGHT", savedBox, "TOPRIGHT", -8, -4)
    btnSaveCustom:SetText("+ Save")
    panel.saveViewButton = btnSaveCustom

    local customEmptyText = savedBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    customEmptyText:SetPoint("TOPLEFT", 8, -26)
    customEmptyText:SetWidth(RAIL_INNER_W)
    customEmptyText:SetJustifyH("LEFT")
    customEmptyText:SetText("|cff8a806eNothing saved yet. + Save keeps these settings.|r")

    local customRows = {}
    for i = 1, customRowCount do
        local row = CreateFrame("Button", nil, savedBox)
        row:SetSize(RAIL_INNER_W, 18)
        row:SetPoint("TOPLEFT", 8, -24 - ((i - 1) * 20))

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(MarketSync.GetThemeColor("stripe"))
        end

        row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.deleteBtn:SetSize(20, 16)
        row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.deleteBtn:SetText("X")
        row.applyBtn = row

        row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.nameText:SetPoint("RIGHT", row.deleteBtn, "LEFT", -4, 0)
        row.nameText:SetJustifyH("LEFT")
        if row.nameText.SetWordWrap then row.nameText:SetWordWrap(false) end

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.12)

        row:Hide()
        customRows[i] = row
    end
    panel.customRows = customRows

    panel.customPageText = savedBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.customPageText:SetPoint("RIGHT", btnSaveCustom, "LEFT", -40, 0)
    panel.customPageText:SetText("1/1")

    local customPrevBtn = CreateFrame("Button", nil, savedBox)
    customPrevBtn:SetSize(16, 16)
    customPrevBtn:SetPoint("LEFT", panel.customPageText, "RIGHT", 2, 0)
    customPrevBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    customPrevBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    customPrevBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local cpnt = customPrevBtn.GetNormalTexture and customPrevBtn:GetNormalTexture()
    if cpnt and cpnt.SetVertexColor then cpnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) end

    local customNextBtn = CreateFrame("Button", nil, savedBox)
    customNextBtn:SetSize(16, 16)
    customNextBtn:SetPoint("LEFT", customPrevBtn, "RIGHT", 2, 0)
    customNextBtn:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    customNextBtn:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    customNextBtn:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local cnnt = customNextBtn.GetNormalTexture and customNextBtn:GetNormalTexture()
    if cnnt and cnnt.SetVertexColor then cnnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) end

    -- Name prompt for + Save.
    local customNameBox = { _text = "" }
    function customNameBox:GetText() return self._text end
    function customNameBox:SetText(text) self._text = tostring(text or "") end
    function customNameBox:ClearFocus() end
    panel.customNameBox = customNameBox
    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    StaticPopupDialogs["MARKETSYNC_PROCESSING_SAVE_VIEW"] = StaticPopupDialogs["MARKETSYNC_PROCESSING_SAVE_VIEW"] or {
        text = "%s",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = true,
        OnAccept = function(self, data)
            local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
            local text = eb and eb:GetText()
            if data and data.onSave then data.onSave(text) end
        end,
        EditBoxOnEnterPressed = function(self)
            local dialog = self:GetParent()
            if dialog and dialog.button1 then dialog.button1:Click() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

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
        SetDropdownLabel(targetDropdown, "Pick from list")
        if panel.selectedProcess and not IsSupportedProcessType(panel.selectedProcess) then
            panel.selectedProcess = nil
        end
        if panel.RefreshProcessButtons then panel.RefreshProcessButtons() end
        SetDropdownLabel(professionDropdown, panel.selectedProfession or "No professions")
        SetDropdownLabel(characterDropdown, panel.selectedCharacterKey and Truncate(panel.selectedCharacterKey, 17) or "This character")
    end

    RefreshProfessionOptions = function()
        professionOptions = (MarketSync.GetProcessingProfessions and MarketSync.GetProcessingProfessions(panel.selectedCharacterKey)) or professionOptions
        if (not panel.selectedProfession or panel.selectedProfession == "") and #professionOptions > 0 then
            panel.selectedProfession = professionOptions[1]
        end

        local professionValid = panel.selectedProfession == "ALL"
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
            UIDropDownMenu_Initialize(professionDropdown._menu, professionDropdown._initFunc)
        end
        SetDropdownLabel(professionDropdown, panel.selectedProfession or "No professions")
    end

    function panel:RefreshModeControls()
        for mode, controls in pairs(modeControls) do
            for _, control in ipairs(controls) do
                SetControlVisible(control, mode == panel.activeMode)
            end
        end
        if panel.RefreshRecentTargets then panel.RefreshRecentTargets() end
        if panel.RefreshProcessButtons then panel.RefreshProcessButtons() end
        if panel.RefreshQualityButtons then panel.RefreshQualityButtons() end
        if panel.activeMode == "craft" and panel.RefreshProfessionStatus then panel.RefreshProfessionStatus() end
        PlaceFilterChecks()
        chkProfitable:SetChecked(panel.filters.onlyProfitable)
        chkStale:SetChecked(panel.filters.hideStale)

        local isCraft = panel.activeMode == "craft"
        customTitle:SetText(isCraft and "Craft lists" or "Saved views")
        btnSaveCustom:SetText(isCraft and "+ List" or "+ Save")
        customEmptyText:SetText(isCraft and "|cff8a806eSelect rows, then + List to save them.|r"
            or "|cff8a806eNothing saved yet. + Save keeps these settings.|r")

        RefreshResultHeaders()
    end

    local function SetNoResultsMessage(message)
        panel.noResultsMessage = message or "Run a mode to see results."
        if panel.noResultsText then
            panel.noResultsText:SetText("|cff888888" .. panel.noResultsMessage .. "|r")
        end
    end

    UpdateResultRows = function()
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
                    if row.selectedBg.SetShown then
                        row.selectedBg:SetShown(data.isSelected and true or false)
                    elseif data.isSelected then
                        row.selectedBg:Show()
                    else
                        row.selectedBg:Hide()
                    end
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
        panel.pageText:SetText(string.format("%d/%d", pageShown, totalPages))

        local hasPrev = panel.page > 0
        local hasNext = total > 0 and panel.page < (totalPages - 1)
        prevBtn:SetEnabled(hasPrev)
        nextBtn:SetEnabled(hasNext)
        local pnt = prevBtn.GetNormalTexture and prevBtn:GetNormalTexture()
        if pnt and pnt.SetVertexColor then
            if hasPrev then pnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) else pnt:SetVertexColor(MarketSync.GetThemeColor("arrowDisabled")) end
        end
        local nnt = nextBtn.GetNormalTexture and nextBtn:GetNormalTexture()
        if nnt and nnt.SetVertexColor then
            if hasNext then nnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) else nnt:SetVertexColor(MarketSync.GetThemeColor("arrowDisabled")) end
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
    panel.UpdateResultRows = UpdateResultRows

    -- Footer line: what the last run found, how many rows the filters show,
    -- and how many rows are selected for Track / Export / craft lists.
    UpdateSelectionSummary = function()
        local base = panel.runSummaryText
        if not base then return end
        local selected = 0
        local selectTable = (panel.lastMode == "craft") and panel.selectedCrafts or panel.selectedArbitrage
        for _, v in pairs(selectTable or {}) do
            if v then selected = selected + 1 end
        end
        local shown, all = #(panel.displayRows or {}), #(panel.allRows or {})
        local parts = { base }
        if shown ~= all then parts[#parts + 1] = string.format("|cffa89e8c%d shown|r", shown) end
        if selected > 0 then parts[#parts + 1] = string.format("|cffffd700%d selected|r", selected) end
        statusSummary:SetText(table.concat(parts, " | "))
    end
    panel.UpdateSelectionSummary = UpdateSelectionSummary

    local function RowPassesFilters(data)
        local f = panel.filters
        if f.onlyProfitable and not data.isProfitable then return false end
        if f.hideStale and data.isStale then return false end
        if panel.activeMode == "target" and f.madeBy and data.processType ~= f.madeBy then return false end
        if panel.activeMode == "process" then
            local quality = tonumber(CachedItemField(data.itemID, "r"))
            if quality and quality >= 2 and quality <= 4 and not f.qualities[quality] then return false end
            local ilvl = tonumber(CachedItemField(data.itemID, "i"))
            if ilvl and f.minLevel and ilvl < f.minLevel then return false end
            if ilvl and f.maxLevel and ilvl > f.maxLevel then return false end
        end
        return true
    end

    -- Filters only hide rows; prices and calculations stay as they were.
    ApplyFilters = function(skipSort)
        local out = {}
        for _, data in ipairs(panel.allRows or {}) do
            if RowPassesFilters(data) then out[#out + 1] = data end
        end
        panel.displayRows = out
        if skipSort then return end
        if ApplyDisplaySort then ApplyDisplaySort() else UpdateResultRows() end
        UpdateSelectionSummary()
    end
    panel.ApplyFilters = ApplyFilters

    local function PublishRows(rows)
        panel.allRows = rows or {}
        ApplyFilters(true)
    end

    HandleTableMouseWheel = function(delta)
        if tableScrollBar and tableScrollBar.HandleWheel then
            tableScrollBar:HandleWheel(delta)
            return
        end
        local total = #(panel.displayRows or {})
        local totalPages = math.max(1, math.ceil(total / numResultsPerPage))
        if delta > 0 then
            if panel.page > 0 then
                panel.page = panel.page - 1
                UpdateResultRows()
            end
        else
            if panel.page < (totalPages - 1) then
                panel.page = panel.page + 1
                UpdateResultRows()
            end
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

    local function BuildArbitrageDisplay(arbitrageResults, yieldStep)
        local rows = {}
        local marginPct = 0
        local marginMult = 1.0

        for index, r in ipairs(arbitrageResults or {}) do
            local itemName, itemLink, icon = ResolveCachedItemVisual(r.inputItemID, r.inputName)
            local livePrice = tonumber(r.livePrice) or 0
            local maxBuy = tonumber(r.maxBuyPerUnit) or 0
            local evPerUnit = tonumber(r.evPerUnit)
            if not evPerUnit then
                evPerUnit = math.floor((maxBuy / marginMult) + 0.5)
            end
            local delta = evPerUnit - livePrice

            local roiPct = (livePrice > 0) and math.floor((delta / livePrice * 100) + 0.5) or nil
            local pctColor = "|cff888888"
            local pctLabel = ""
            if roiPct then
                local sign = (roiPct >= 0) and "+" or ""
                pctColor = (roiPct >= 0) and "|cff00ff00" or "|cffff2020"
                pctLabel = " " .. pctColor .. "(" .. sign .. roiPct .. "%)|r"
            end

            local status
            local statusRank = 0
            -- The ROI sits in the details panel; the narrow Status column
            -- keeps only the verdict.
            if r.partialEV then
                status = "|cffffaa00PARTIAL|r"
                statusRank = 2
            elseif r.liveStale or r.evStale or r.targetStale then
                status = "|cffffaa00STALE|r"
                statusRank = 2
            elseif livePrice <= 0 then
                status = "|cff888888NO AH|r"
                statusRank = 1
            elseif delta >= 0 then
                status = "|cff00ff00GOOD|r"
                statusRank = 3
            else
                status = "|cffff4444MISS|r"
                statusRank = 0
            end

            local detailLines = {}
            local ahCutPercent = tonumber(r.ahCutPercent) or 5

            -- 1. Net Profit & ROI
            if livePrice > 0 then
                local roiSuffix = ""
                if roiPct then
                    local roiSign = (roiPct > 0) and "+" or ""
                    roiSuffix = string.format(" %s(%s%d%% ROI)|r", pctColor, roiSign, roiPct)
                end
                detailLines[#detailLines + 1] = string.format("%s %s%s",
                    ColorLabel("Net Profit/Input:"), FormatDelta(delta), roiSuffix)
            end

            -- 2. Break-even Buy Cap
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r %s",
                ColorLabel("Break-even Buy:"), MoneyText(evPerUnit), ColorMuted("(after " .. tostring(ahCutPercent) .. "% AH cut)"))

            -- 3. Yield & Profit range (only if variable yields)
            if r.processType == "DISENCHANT" then
                if r.lowNetPerAction and r.highNetPerAction and (r.lowNetPerAction ~= r.highNetPerAction) then
                    detailLines[#detailLines + 1] = string.format("%s %s to %s",
                        ColorLabel("Yield Range (Net):"),
                        MoneyText(r.lowNetPerAction), MoneyText(r.highNetPerAction))
                    if livePrice > 0 then
                        detailLines[#detailLines + 1] = string.format("%s %s to %s",
                            ColorLabel("Profit Range:"),
                            FormatDelta(r.lowNetPerAction - livePrice),
                            FormatDelta(r.highNetPerAction - livePrice))
                    end
                end
            end

            -- 4. Target specifics for Milling / Prospecting / Target searches
            if r.targetName then
                detailLines[#detailLines + 1] = string.format("%s %s  %s %s",
                    ColorLabel("Target:"), ColorInfo(r.targetName), ColorMuted("@"), ColorGood(MoneyText(r.targetPrice or 0)))
                if r.expectedTarget and r.expectedTarget > 0 then
                    detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r",
                        ColorLabel("Expected Yield:"), ExpectedQuantityText(r.expectedTarget))
                end
            end

            if r.stackSize and tonumber(r.stackSize) and tonumber(r.stackSize) > 1 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%d|r", ColorLabel("Input Stack Size:"), tonumber(r.stackSize))
            end

            -- 5. Warnings (only when relevant)
            if r.missingOutputs and tonumber(r.missingOutputs) and tonumber(r.missingOutputs) > 0 then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%d|r", ColorWarn("Missing priced outputs:"), tonumber(r.missingOutputs))
                detailLines[#detailLines + 1] = ColorWarn("Displayed EV is a conservative partial lower bound.")
            end
            if r.liveStale or r.evStale or r.targetStale then
                detailLines[#detailLines + 1] = ColorWarn("One or more prices are stale (>24h).")
            end
            local approximateDE = tostring(r.processType or ""):upper() == "DISENCHANT"
                and MarketSync.IsDisenchantApproximate and MarketSync.IsDisenchantApproximate()
            if approximateDE then
                detailLines[#detailLines + 1] = ColorWarn(MarketSync.FOREVER_DISENCHANT_NOTE)
            end

            -- Target Material shows how many materials one input yields;
            -- Process Scan shows the results' value before the auction cut.
            local isTargetRow = r.expectedTarget ~= nil
            local stackSize = math.max(1, tonumber(r.stackSize) or 1)
            local grossPerUnit = tonumber(r.grossEVPerAction) and math.floor(r.grossEVPerAction / stackSize) or evPerUnit
            local valueText, valueSort
            if isTargetRow then
                valueText = ExpectedQuantityText(r.expectedTarget)
                valueSort = tonumber(r.expectedTarget) or 0
            else
                valueText = MoneyText(grossPerUnit)
                valueSort = grossPerUnit
            end
            local roiText = roiPct and (pctColor .. ((roiPct >= 0) and "+" or "") .. roiPct .. "%|r") or "-"

            rows[#rows + 1] = {
                itemID = r.inputItemID,
                link = itemLink,
                icon = icon,
                nameText = itemName,
                -- "~" marks an approximate Forever disenchant estimate.
                typeText = FormatProcessType(r.processType) .. (approximateDE and " |cffffb347~|r" or ""),
                approximate = approximateDE,
                processType = r.processType and tostring(r.processType):upper() or nil,
                roiText = roiText,
                isProfitable = statusRank == 3,
                isStale = statusRank == 2,
                valueText = valueText,
                maxText = MoneyText(maxBuy),
                liveText = (livePrice > 0) and MoneyText(livePrice) or "-",
                deltaText = FormatDelta(delta),
                statusText = status,
                itemSort = string.lower(itemName or ""),
                typeSort = string.lower(tostring(r.processType or "")),
                valueSort = valueSort,
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
            if yieldStep and index % 50 == 0 then yieldStep(index) end
        end

        return rows
    end

    BuildCraftDisplay = function(craftResults, yieldStep)
        local rows = {}
        local useVendor = (panel.craftSaleTarget == "vendor")

        for index, c in ipairs(craftResults or {}) do
            local outputName = c.outputName or c.recipeName or ("Item " .. tostring(c.outputItemID or "?"))
            local itemName, itemLink, icon = ResolveCachedItemVisual(c.outputItemID, outputName)
            local craftCost = tonumber(c.craftCost) or 0
            local missingMatPrice = c.hasMissingMatPrice == true
            local outputQty = math.max(1, tonumber(c.outputQty) or 1)
            local outputQtyMin = math.max(1, tonumber(c.outputQtyMin) or outputQty)
            local outputQtyMax = math.max(outputQtyMin, tonumber(c.outputQtyMax) or outputQty)

            -- Resolve vendor sell price from client item cache for previously cached recipes
            local vendorUnitPrice = tonumber(c.vendorUnitPrice) or 0
            if vendorUnitPrice <= 0 and c.outputItemID and MarketSync.GetVendorSellPrice then
                local resolvedSell = MarketSync.GetVendorSellPrice(c.outputItemID, false)
                if resolvedSell and resolvedSell > 0 then
                    vendorUnitPrice = resolvedSell
                    c.vendorUnitPrice = resolvedSell
                    c.vendorRevenueMin = math.floor(resolvedSell * outputQtyMin)
                    c.vendorRevenueExpected = math.floor(resolvedSell * outputQty)
                    c.vendorRevenueMax = math.floor(resolvedSell * outputQtyMax)
                    c.vendorRevenue = c.vendorRevenueMin or c.vendorRevenueExpected
                    c.vendorMaxCraftCost = c.vendorRevenue
                    if not missingMatPrice then
                        c.vendorMarginMin = c.vendorRevenueMin - craftCost
                        c.vendorMarginExpected = c.vendorRevenueExpected - craftCost
                        c.vendorMarginMax = c.vendorRevenueMax - craftCost
                        c.vendorMargin = c.vendorMarginMin or c.vendorMarginExpected
                        c.vendorMeetsMargin = (c.vendorMargin or 0) >= 0
                        if craftCost > 0 then
                            local vScale = c.vendorMaxCraftCost / craftCost
                            for _, matInfo in ipairs(c.matsDetailed or {}) do
                                if matInfo.price and matInfo.price > 0 then
                                    matInfo.vendorCapPrice = math.max(1, math.floor(matInfo.price * vScale))
                                end
                            end
                        end
                    end
                end
            end

            local vendorRevenue = tonumber(c.vendorRevenue) or 0
            local vendorMargin = tonumber(c.vendorMargin) or 0
            local vendorMaxSpend = tonumber(c.vendorMaxCraftCost) or 0
            local hasVendorSell = vendorRevenue > 0

            local revenue = useVendor and vendorRevenue or (tonumber(c.revenue) or 0)
            local margin = useVendor and vendorMargin or (tonumber(c.margin) or 0)
            local maxSpend = useVendor and vendorMaxSpend or (tonumber(c.maxCraftCost) or 0)
            local capDelta = maxSpend - craftCost
            local missingPrice = c.hasMissingPrice == true
            if useVendor then missingPrice = missingMatPrice or not hasVendorSell end

            -- Match the Materials window: ROI is profit divided by material
            -- cost, not profit divided by net sale proceeds.
            local profitPct = (craftCost > 0 and not missingPrice)
                and math.floor((margin / craftCost * 100) + 0.5) or nil
            local pctLabel = ""
            if profitPct and not missingPrice then
                if profitPct >= 0 then
                    pctLabel = " |cff00ff00(+" .. profitPct .. "%)|r"
                else
                    pctLabel = " |cffff2020(" .. profitPct .. "%)|r"
                end
            end

            local status
            local statusRank = 0
            if useVendor and not hasVendorSell then
                status = "|cff777777NO VENDOR|r"
                statusRank = 0
            elseif missingPrice then
                status = "|cffffaa00NO PRICE|r"
                statusRank = 1
            elseif (not useVendor and c.outputStale) or c.hasStaleMat then
                status = "|cffffaa00STALE|r"
                statusRank = 2
            elseif (useVendor and c.vendorMeetsMargin) or (not useVendor and c.meetsMargin) then
                status = "|cff00ff00GOOD|r"
                statusRank = 3
            else
                status = "|cffff4444MISS|r"
                statusRank = 0
            end
            local roiText = (profitPct and pctLabel ~= "") and pctLabel:gsub("[%(%)]", ""):gsub("^ ", "") or "-"

            local detailLines = {}
            local outputQty = tonumber(c.outputQty) or 1
            local outputQtyMin = tonumber(c.outputQtyMin) or outputQty
            local outputQtyMax = tonumber(c.outputQtyMax) or outputQty
            local ahCutPercent = tonumber(c.ahCutPercent) or 5
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Recipe:"), ColorInfo(itemName))
            detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("Profession:"), ColorInfo(c.profession or "Unknown"))
            if outputQtyMin ~= outputQtyMax then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%g-%g|r %s",
                    ColorLabel("Output/Craft:"), outputQtyMin, outputQtyMax,
                    ColorMuted(string.format("(expected %.2f)", outputQty)))
            else
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%g|r", ColorLabel("Output/Craft:"), outputQty)
            end
            detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r",
                ColorLabel("Output AH/Each (gross):"), (c.outputUnitPrice and c.outputUnitPrice > 0) and MoneyText(c.outputUnitPrice) or "Unavailable")
            if hasVendorSell then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r %s",
                    ColorLabel("Vendor Payout/Craft:"), MoneyText(vendorRevenue), ColorMuted("(0% cut, instant bulk)"))
            end
            if not missingMatPrice then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r", ColorLabel("Material Cost/Craft:"), MoneyText(craftCost))
            end
            if c.hasMissingPrice ~= true then
                detailLines[#detailLines + 1] = string.format("%s %s %s", ColorLabel("Net AH Revenue/Craft:"),
                    ColorGood(MoneyText(tonumber(c.revenue) or 0)), ColorMuted("(after " .. tostring(ahCutPercent) .. "% main-AH cut)"))
            elseif not useVendor then
                detailLines[#detailLines + 1] = ColorWarn("AH Profit unavailable: scan missing output or material prices.")
            end
            if hasVendorSell and not missingMatPrice then
                local vProfitText = SignedMoneyText(vendorMargin, true)
                local vRoi = craftCost > 0 and math.floor((vendorMargin / craftCost * 100) + 0.5) or 0
                detailLines[#detailLines + 1] = string.format("%s %s %s",
                    ColorLabel("Bulk Vendor Profit/Craft:"),
                    (vendorMargin >= 0) and ColorGood(vProfitText) or ColorBad(vProfitText),
                    ColorMuted(string.format("(%s%d%% ROI)", vendorMargin >= 0 and "+" or "", vRoi)))
            end

            local marginText = MoneyText(math.abs(margin))
            if margin >= 0 then
                marginText = "+" .. marginText
            else
                marginText = "-" .. marginText
            end
            if not missingPrice and not useVendor then
                if c.marginMin and c.marginMax and c.marginMax > c.marginMin then
                    detailLines[#detailLines + 1] = string.format("%s %s / %s / %s",
                        ColorLabel("AH Profit/Craft (min / exp / max):"),
                        (c.marginMin >= 0 and ColorGood or ColorBad)(SignedMoneyText(c.marginMin, true)),
                        ((c.marginExpected or margin) >= 0 and ColorGood or ColorBad)(SignedMoneyText(c.marginExpected or margin, true)),
                        (c.marginMax >= 0 and ColorGood or ColorBad)(SignedMoneyText(c.marginMax, true)))
                    detailLines[#detailLines + 1] = ColorMuted(string.format("Guaranteed floor: %s | Max proc yield: %s",
                        SignedMoneyText(c.marginMin, true), SignedMoneyText(c.marginMax, true)))
                else
                    detailLines[#detailLines + 1] = string.format("%s %s", ColorLabel("AH Profit/Craft:"), (margin >= 0) and ColorGood(marginText) or ColorBad(marginText))
                end
            end

            if maxSpend > 0 and not missingPrice then
                detailLines[#detailLines + 1] = string.format("%s |cffffffff%s|r",
                    ColorLabel(useVendor and "Vendor Break-Even Mat Cap/Craft:" or "AH Material Cost Cap/Craft:"), MoneyText(maxSpend))
            end

            local mats = c.matsDetailed or {}
            for i, mat in ipairs(mats) do
                if i > 4 then
                    detailLines[#detailLines + 1] = ColorMuted("...")
                    break
                end
                local matName = ResolveCachedItemVisual(mat.itemID)
                local qty = tonumber(mat.qty) or 1
                local matPriceText = (mat.price and mat.price > 0) and MoneyText(mat.price) or "No price"
                local priceColor = mat.stale and ColorWarn(matPriceText) or "|cffffffff" .. matPriceText .. "|r"
                local capNote = (useVendor and mat.vendorCapPrice and mat.vendorCapPrice > 0)
                    and ColorMuted(" (max " .. MoneyText(mat.vendorCapPrice) .. "/ea)") or ""
                detailLines[#detailLines + 1] = string.format("%s x%d %s %s%s%s",
                    ColorMuted(matName), qty, ColorMuted("@"), priceColor, ColorMuted("/ea"), capNote)
            end

            local minMarg = useVendor and c.vendorMarginMin or c.marginMin
            local maxMarg = useVendor and c.vendorMarginMax or c.marginMax
            local valueDisplay = "-"
            if not missingPrice then
                if minMarg and maxMarg and maxMarg > minMarg then
                    valueDisplay = SignedMoneyText(minMarg, true) .. " +"
                else
                    valueDisplay = SignedMoneyText(margin, true)
                end
            end

            local difficulty = SKILL_DIFFICULTY[string.lower(tostring(c.skillType or ""))]
            rows[#rows + 1] = {
                recipeName = outputName,
                itemID = c.outputItemID,
                link = itemLink,
                icon = icon,
                nameText = itemName or outputName,
                typeText = difficulty and difficulty.text or tostring(c.profession or "Craft"),
                roiText = roiText,
                isProfitable = statusRank == 3,
                isStale = statusRank == 2,
                valueText = valueDisplay,
                maxText = missingPrice and "-" or roiText,
                liveText = missingPrice and "-" or MoneyText(craftCost),
                deltaText = (revenue > 0) and MoneyText(revenue) or "-",
                statusText = status,
                trackThreshold = craftCost > 0 and craftCost or nil,
                itemSort = string.lower(itemName or ""),
                typeSort = difficulty and difficulty.rank or 9,
                valueSort = missingPrice and -math.huge or margin,
                maxSort = profitPct or -math.huge,
                liveSort = tonumber(craftCost) or 0,
                deltaSort = tonumber(revenue) or 0,
                statusSort = statusRank,
                detail = table.concat(detailLines, "\n"),
                detailLines = detailLines,
                isSelected = panel.selectedCrafts and panel.selectedCrafts[outputName] or false,
            }
            if yieldStep and index % 50 == 0 then yieldStep(index) end
        end

        return rows
    end

    if panel.RegisterEvent then
        panel:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        panel:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    end
    panel:SetScript("OnEvent", function(_, event, itemID, success)
        local id = tonumber(itemID)
        if not id or not pendingItemNames[id] then return end
        pendingItemNames[id] = nil
        if success == false or panel.lastMode ~= panel.activeMode then return end
        -- Rebuild presentation only: auction prices and craft calculations
        -- stay intact while freshly loaded, client-localized names replace IDs.
        if panel.lastMode == "craft" then
            PublishRows(BuildCraftDisplay(panel.lastCraftResults))
        elseif panel.lastMode == "target" or panel.lastMode == "process" then
            PublishRows(BuildArbitrageDisplay(panel.lastArbitrageResults))
        else
            return
        end
        if ApplyDisplaySort then ApplyDisplaySort() else UpdateResultRows() end
        local tooltipOwner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
        if tooltipOwner then
            for _, row in ipairs(panel.resultRows) do
                if tooltipOwner == row or tooltipOwner == row.iconButton then
                    GameTooltip:Hide()
                    row.ShowTooltip(tooltipOwner)
                    break
                end
            end
        end
    end)

    local function RunCachedWork(work, onComplete)
        local runID = panel.cacheRunID
        local function Start()
            if runID ~= panel.cacheRunID then return end
            local sources = MarketSync.GetProcessingIndexSources
                and MarketSync.GetProcessingIndexSources()
            if not sources then
                -- Low RAM leaves prices unloaded until something needs them.
                -- Load Personal and Guild once, then run again; Low RAM frees
                -- them later when they sit idle.
                if not panel.loadingPrices and MarketSync.LoadPersonalCache and MarketSync.LoadGuildCache then
                    panel.loadingPrices = true
                    statusSummary:SetText("|cffffd700Loading market prices...|r")
                    MarketSync.LoadPersonalCache(function()
                        MarketSync.LoadGuildCache(function()
                            panel.loadingPrices = false
                            if MarketSync.TouchLowRamSource then
                                MarketSync.TouchLowRamSource("personal")
                                MarketSync.TouchLowRamSource("guild")
                            end
                            Start()
                        end)
                    end)
                    return
                end
                if not panel.loadingPrices then
                    statusSummary:SetText("|cffffaa00No market prices yet. Scan the Auction House or sync with your guild first.|r")
                end
                return
            end

            statusSummary:SetText("|cffffd700Processing cached prices...|r")
            local worker = coroutine.create(function()
                local function YieldStep() coroutine.yield() end
                local snapshot = MarketSync.BuildProcessingCacheSnapshot(YieldStep)
                if not snapshot then return nil end
                local result = work(snapshot, YieldStep)
                -- Newest observation in the cache, for the freshness badge.
                if type(result) == "table" then
                    local newest, n = 0, 0
                    for _, entry in pairs(snapshot.prices or {}) do
                        local stamp = type(entry) == "table" and tonumber(entry.exactTime) or 0
                        if stamp > newest then newest = stamp end
                        n = n + 1
                        if n % 500 == 0 then YieldStep() end
                    end
                    result.newestPriceAt = newest
                end
                return result
            end)
            local function Step()
                if runID ~= panel.cacheRunID then return end
                local ok, result = coroutine.resume(worker)
                if not ok then
                    statusSummary:SetText("|cffff4444Processing failed: " .. tostring(result) .. "|r")
                    return
                end
                if coroutine.status(worker) == "dead" then
                    if result then
                        local newest = tonumber(result.newestPriceAt) or 0
                        if newest > 0 and MarketSync.FormatRelativeTime then
                            local age = time() - newest
                            local color = age > 86400 and "|cffffb347" or "|cff4fd06a"
                            priceBadge:SetText("Prices: " .. color .. "newest "
                                .. MarketSync.FormatRelativeTime(newest) .. "|r")
                        else
                            priceBadge:SetText("|cffa89e8cPrices: market cache|r")
                        end
                        panel.runSummaryText = nil
                        onComplete(result)
                        if not panel.runSummaryText and statusSummary.GetText then
                            panel.runSummaryText = statusSummary:GetText()
                        end
                        if ShowDetails then ShowDetails(nil) end
                        if panel.railView == "details" then ShowRailView("settings") end
                        UpdateSelectionSummary()
                    end
                elseif C_Timer and C_Timer.After then
                    C_Timer.After(0, Step)
                else
                    Step()
                end
            end
            Step()
        end
        Start()
    end

    RunActiveMode = function()
        panel.cacheRunID = (panel.cacheRunID or 0) + 1
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
                    PublishRows({})
                    SetNoResultsMessage("Unknown target. Use an item link, itemID, or a cached item name.")
                    UpdateResultRows()
                    return
                end
            end

            if not panel.selectedTargetID then
                statusSummary:SetText("|cffff4444Enter a target item name, link, or ID first.|r")
                PublishRows({})
                SetNoResultsMessage("Drop an item on Target material, or type its name and press Enter.")
                UpdateResultRows()
                return
            end

            local targetID = panel.selectedTargetID
            RunCachedWork(function(snapshot, yieldStep)
                local results = MarketSync.FindArbitrageByTarget
                    and MarketSync.FindArbitrageByTarget(targetID, 0, snapshot, yieldStep) or {}
                return { results = results, rows = BuildArbitrageDisplay(results, yieldStep),
                    targetEntry = snapshot.prices[tonumber(targetID)] }
            end, function(data)
                panel.lastMode = "target"
                panel.lastArbitrageResults = data.results
                panel.lastCraftResults = {}
                PublishRows(data.rows)
                RememberTarget(targetID)
                local targetName = (data.targetEntry and data.targetEntry.name)
                    or ("Item " .. tostring(targetID))
                local targetPrice = data.targetEntry and tonumber(data.targetEntry.price)
                if not targetPrice or targetPrice <= 0 then
                    statusSummary:SetText(string.format("|cffffaa00%s: No cached AH price|r", targetName))
                    SetNoResultsMessage(string.format("'%s' has no price in the built market cache.", targetName))
                else
                    local good = 0
                    for _, row in ipairs(panel.allRows) do if row.isProfitable then good = good + 1 end end
                    statusSummary:SetText(string.format("|cff00ff00%s|r %s: %d under break-even of %d",
                        Truncate(targetName, 20), MoneyText(targetPrice), good, #panel.allRows))
                    local hasTargetDefinition = MarketSync.HasProcessingDefinitionForTarget
                        and MarketSync.HasProcessingDefinitionForTarget(targetID)
                    if hasTargetDefinition then
                        SetNoResultsMessage("No cached AH items yield this material.")
                    else
                        SetNoResultsMessage("Target has no processing definitions in the current dataset yet.")
                    end
                end
                ApplyDisplaySort()
            end)
            return
        end

        if panel.activeMode == "process" then
            local processType = panel.selectedProcess
            RunCachedWork(function(snapshot, yieldStep)
                local results = MarketSync.FindArbitrageByProcess
                    and MarketSync.FindArbitrageByProcess(processType, 0, snapshot, yieldStep) or {}
                return { results = results, rows = BuildArbitrageDisplay(results, yieldStep) }
            end, function(data)
                panel.lastMode = "process"
                panel.lastArbitrageResults = data.results
                panel.lastCraftResults = {}
                PublishRows(data.rows)
                local good = 0
                for _, row in ipairs(panel.allRows) do if row.isProfitable then good = good + 1 end end
                statusSummary:SetText(string.format("|cff00ff00%s|r: %d profitable of %d",
                    processType and FormatProcessType(processType) or "All processes", good, #panel.allRows))
                SetNoResultsMessage("No processable items with prices in the built market cache.")
                ApplyDisplaySort()
            end)
            return
        end

        local profession = panel.selectedProfession
        if not profession or profession == "" then
            statusSummary:SetText("|cffff4444Select a profession first.|r")
            PublishRows({})
            SetNoResultsMessage("No professions scanned yet. Open a profession window, or press Professions... to see what is missing.")
            UpdateResultRows()
            return
        end

        local craftSet = nil
        if panel.activeCraftSet then
            craftSet = {}
            for _, itemID in ipairs(panel.activeCraftSet.itemIDs or {}) do
                craftSet[tonumber(itemID)] = true
            end
        end
        local characterKey = panel.selectedCharacterKey
        local setName = panel.activeCraftSet and panel.activeCraftSet.name
        RunCachedWork(function(snapshot, yieldStep)
            local results = MarketSync.FindProfitableCrafts
                and MarketSync.FindProfitableCrafts(profession, 0, characterKey, craftSet,
                    snapshot, yieldStep) or {}
            return { results = results, rows = BuildCraftDisplay(results, yieldStep) }
        end, function(data)
            panel.lastMode = "craft"
            panel.lastCraftResults = data.results
            panel.lastArbitrageResults = {}
            PublishRows(data.rows)

            local profitableCount = 0
            local useVendor = panel.craftSaleTarget == "vendor"
            for _, row in ipairs(data.results) do
                local profit = useVendor and row.vendorMargin or (not useVendor and row.margin)
                if profit and profit > 0 then profitableCount = profitableCount + 1 end
            end
            local sourceLabel = characterKey and Truncate(characterKey, 14) or "This character"
            local setLabel = setName and (" / " .. Truncate(setName, 14)) or ""
            statusSummary:SetText(string.format("|cff00ff00%s / %s%s|r: %d profitable of %d",
                sourceLabel, profession, setLabel, profitableCount, #panel.allRows))
            if #panel.allRows == 0 then
                local knownCount = MarketSync.GetCraftRecipeCount
                    and MarketSync.GetCraftRecipeCount(profession, characterKey) or 0
                if knownCount == 0 then
                    SetNoResultsMessage("No recipes saved for " .. tostring(profession)
                        .. " yet. Open its profession window once and MarketSync reads it on its own.")
                elseif setName then
                    SetNoResultsMessage("No recipes in this list are known by the selected crafter and profession.")
                else
                    SetNoResultsMessage("No craft rows have complete cached pricing data yet.")
                end
            else
                SetNoResultsMessage("Showing cached recipes sorted by highest profit.")
            end
            panel.sortField = "valueSort"
            panel.sortAscending = false
            ApplyDisplaySort()
        end)
    end

    local function BuildSelectionSummary(selection)
        if not selection then return "" end

        local mode = tostring(selection.mode or "target")
        if mode == "target" then
            local target = FindTargetName(selection.targetItemID) or "(none)"
            return string.format("Target: %s", target)
        end
        if mode == "process" then
            return string.format("Process: %s", tostring(selection.processType or "ALL"))
        end
        return string.format("Craft: %s", tostring(selection.profession or "(none)"))
    end

    local function ApplySelection(selection)
        if not selection then return end
        panel:CancelCachedWork()

        panel.activeMode = tostring(selection.mode or "target")
        panel.selectedTargetID = tonumber(selection.targetItemID)

        local processType = selection.processType and tostring(selection.processType):upper() or nil
        panel.selectedProcess = (processType and processType ~= "ALL") and processType or nil

        if selection.profession and tostring(selection.profession) ~= "" then
            panel.selectedProfession = tostring(selection.profession)
        end

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
        if panel.RefreshCustomRows then panel.RefreshCustomRows() end

        if type(selection.filters) == "table" then
            panel.filters.onlyProfitable = selection.filters.onlyProfitable == true
            panel.filters.hideStale = selection.filters.hideStale == true
            local madeBy = selection.filters.madeBy
            panel.filters.madeBy = (madeBy and madeBy ~= "ALL") and madeBy or nil
            panel.filters.minLevel = tonumber(selection.filters.minLevel)
            panel.filters.maxLevel = tonumber(selection.filters.maxLevel)
            panel:RefreshModeControls()
        end
        statusSummary:SetText("|cff00ff00Loaded view:|r " .. Truncate(selection.name or "View", 22))
        if panel.activeMode ~= "target" or panel.selectedTargetID then
            if RunActiveMode then RunActiveMode() end
        end
    end

    local RefreshCustomRows
    RefreshCustomRows = function()
        local isCraft = panel.activeMode == "craft"
        local selections
        if isCraft then
            selections = { { name = "All recipes", all = true } }
            for _, craftSet in ipairs(MarketSync.ListProcessingCraftSets and MarketSync.ListProcessingCraftSets() or {}) do
                selections[#selections + 1] = craftSet
            end
        else
            selections = MarketSync.ListProcessingCustomSelections and MarketSync.ListProcessingCustomSelections() or {}
        end
        local total = #selections
        local totalPages = math.max(1, math.ceil(total / customRowCount))

        if panel.customPage < 0 then panel.customPage = 0 end
        if panel.customPage > (totalPages - 1) then panel.customPage = totalPages - 1 end

        local firstIndex = (panel.customPage * customRowCount) + 1
        for i = 1, customRowCount do
            local row = customRows[i]
            local selection = selections[firstIndex + i - 1]

            if selection then
                row.selection = selection
                local active = isCraft and (selection.all and not panel.activeCraftSet
                    or panel.activeCraftSet and panel.activeCraftSet.name == selection.name)

                row.nameText:SetText((active and "|cffffd700" or "")
                    .. Truncate(selection.name or "Preset", 15) .. (active and "|r" or ""))
                if isCraft and selection.all then row.deleteBtn:Hide() else row.deleteBtn:Show() end

                row.applyBtn:SetScript("OnClick", function()
                    if isCraft then
                        panel.activeCraftSet = selection.all and nil or selection
                        if RunActiveMode then RunActiveMode() end
                        RefreshCustomRows()
                    else
                        ApplySelection(selection)
                    end
                end)
                row.deleteBtn:SetScript("OnClick", function()
                    local deleted = isCraft and MarketSync.DeleteProcessingCraftSet
                        and MarketSync.DeleteProcessingCraftSet(selection.name)
                        or not isCraft and MarketSync.DeleteProcessingCustomSelection
                        and MarketSync.DeleteProcessingCustomSelection(selection.id)
                    if deleted then
                        if isCraft and panel.activeCraftSet and panel.activeCraftSet.name == selection.name then
                            panel.activeCraftSet = nil
                            if RunActiveMode then RunActiveMode() end
                        end
                        statusSummary:SetText((isCraft and "|cffffaa00Deleted list:|r " or "|cffffaa00Deleted preset:|r ") .. Truncate(selection.name or "Preset", 18))
                        RefreshCustomRows()
                    else
                        statusSummary:SetText("|cffff4444Failed to delete preset.|r")
                    end
                end)

                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(selection.name or "Preset", 1, 0.82, 0)
                    GameTooltip:AddLine(isCraft and (selection.all and "Show all known recipes"
                        or (tostring(#(selection.itemIDs or {})) .. " selected item(s)"))
                        or BuildSelectionSummary(selection), 0.85, 0.85, 0.85, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)


                row.deleteBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(isCraft and "Delete craft list" or "Delete preset", 1, 0.25, 0.25)
                    GameTooltip:Show()
                end)
                row.deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row.selection = nil
                row:Hide()
            end
        end

        SetControlVisible(customEmptyText, total == 0)
        local paged = totalPages > 1
        SetControlVisible(panel.customPageText, paged)
        SetControlVisible(customPrevBtn, paged)
        SetControlVisible(customNextBtn, paged)
        panel.customPageText:SetText(string.format("%d/%d", panel.customPage + 1, totalPages))

        local hasCPrev = total > 0 and panel.customPage > 0
        local hasCNext = total > 0 and panel.customPage < (totalPages - 1)
        customPrevBtn:SetEnabled(hasCPrev)
        customNextBtn:SetEnabled(hasCNext)
        local cpnt = customPrevBtn.GetNormalTexture and customPrevBtn:GetNormalTexture()
        if cpnt and cpnt.SetVertexColor then
            if hasCPrev then cpnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) else cpnt:SetVertexColor(MarketSync.GetThemeColor("arrowDisabled")) end
        end
        local cnnt = customNextBtn.GetNormalTexture and customNextBtn:GetNormalTexture()
        if cnnt and cnnt.SetVertexColor then
            if hasCNext then cnnt:SetVertexColor(MarketSync.GetThemeColor("arrow")) else cnnt:SetVertexColor(MarketSync.GetThemeColor("arrowDisabled")) end
        end
    end
    panel.RefreshCustomRows = RefreshCustomRows

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

    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    if not StaticPopupDialogs["MARKETSYNC_PROCESSING_NEW_LIST"] then
        StaticPopupDialogs["MARKETSYNC_PROCESSING_NEW_LIST"] = {
            text = "Enter name for new Shopping List:",
            button1 = "Create & Add",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                local text = eb and eb:GetText()
                text = text and text:match("^%s*(.-)%s*$")
                if text and text ~= "" and MarketSync.Favorites then
                    MarketSync.Favorites.CreateList(text)
                    local items = panel._pendingExportItemIDs or {}
                    local count = 0
                    for _, id in ipairs(items) do
                        if MarketSync.Favorites.AddToList(text, id) then
                            count = count + 1
                        end
                    end
                    statusSummary:SetText(string.format("|cff00ff00Created '%s' with %d item(s).|r", text, count))
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    local function GetExportItemIDs()
        local itemIDs = {}
        local seen = {}
        local function Add(id)
            id = tonumber(id)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                itemIDs[#itemIDs + 1] = id
            end
        end

        if panel.lastMode == "craft" then
            local hasAnySelection = false
            for _, v in pairs(panel.selectedCrafts or {}) do
                if v then hasAnySelection = true; break end
            end
            for _, row in ipairs(panel.lastCraftResults or {}) do
                local name = row.outputName or row.recipeName or ("Item " .. tostring(row.outputItemID or "?"))
                local isSelected = panel.selectedCrafts and panel.selectedCrafts[name]
                if (not hasAnySelection) or isSelected then
                    Add(row.outputItemID)
                    for _, mat in ipairs(row.matsDetailed or {}) do
                        Add(mat.itemID)
                    end
                end
            end
        else
            local hasAnySelection = false
            for _, v in pairs(panel.selectedArbitrage or {}) do
                if v then hasAnySelection = true; break end
            end
            for _, row in ipairs(panel.lastArbitrageResults or {}) do
                local isSelected = panel.selectedArbitrage and panel.selectedArbitrage[row.inputItemID]
                if (not hasAnySelection) or isSelected then
                    Add(row.inputItemID)
                end
            end
        end
        return itemIDs
    end

    local exportMenu = CreateFrame("Frame", parentPrefix .. "ProcessingExportMenu", panel, "UIDropDownMenuTemplate")
    exportMenu:Hide()

    UIDropDownMenu_Initialize(exportMenu, function(self, level)
        local itemIDs = GetExportItemIDs()
        if #itemIDs == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "No items to export"
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end

        local header = UIDropDownMenu_CreateInfo()
        header.text = string.format("Export %d Item(s) to:", #itemIDs)
        header.isTitle = true
        UIDropDownMenu_AddButton(header, level)

        local lists = (MarketSync.Favorites and MarketSync.Favorites.GetLists and MarketSync.Favorites.GetLists()) or { "Favorites" }
        for _, listName in ipairs(lists) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = "  List: " .. listName
            opt.func = function()
                local count = 0
                for _, id in ipairs(itemIDs) do
                    if MarketSync.Favorites and MarketSync.Favorites.AddToList(listName, id) then
                        count = count + 1
                    end
                end
                statusSummary:SetText(string.format("|cff00ff00Added %d item(s) to '%s'.|r", count, listName))
            end
            UIDropDownMenu_AddButton(opt, level)
        end

        local newOpt = UIDropDownMenu_CreateInfo()
        newOpt.text = "|cff00ff00+ Create New List...|r"
        newOpt.func = function()
            panel._pendingExportItemIDs = itemIDs
            StaticPopup_Show("MARKETSYNC_PROCESSING_NEW_LIST")
        end
        UIDropDownMenu_AddButton(newOpt, level)

        if Auctionator or MarketSync.ExportCraftMatsToAuctionator or MarketSync.ExportArbitrageToAuctionator then
            local aucOpt = UIDropDownMenu_CreateInfo()
            aucOpt.text = "Export to Auctionator List"
            aucOpt.func = function()
                local ok, info
                if panel.lastMode == "craft" and MarketSync.ExportCraftMatsToAuctionator then
                    local exportRows = {}
                    for _, row in ipairs(panel.lastCraftResults or {}) do
                        if row and row.meetsMargin then
                            exportRows[#exportRows + 1] = row
                        end
                    end
                    ok, info = MarketSync.ExportCraftMatsToAuctionator(exportRows)
                elseif MarketSync.ExportArbitrageToAuctionator then
                    ok, info = MarketSync.ExportArbitrageToAuctionator(panel.lastArbitrageResults or {})
                end
                if ok then
                    statusSummary:SetText(string.format("|cff00ff00Exported %d items to Auctionator.|r", tonumber(info) or 0))
                else
                    statusSummary:SetText("|cffff4444Export failed:|r " .. tostring(info or "unknown error"))
                end
            end
            UIDropDownMenu_AddButton(aucOpt, level)
        end
    end)

    btnExport:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, exportMenu, self, 0, 0)
    end)

    btnTrack:SetScript("OnClick", function()
        local candidates = {}
        local seen = {}

        local function AddCandidate(itemID, thresholdCopper, liveCopper, fallbackName)
            local id = tonumber(itemID)
            local threshold = tonumber(thresholdCopper) or 0
            if not id or id <= 0 or seen[id] then
                return
            end
            seen[id] = true
            local itemName = ResolveItemVisual(id, fallbackName)
            candidates[#candidates + 1] = {
                matchType = "itemID",
                matchValue = id,
                itemID = id,
                displayName = itemName,
                marketPrice = math.max(0, math.floor((tonumber(liveCopper) or 0) + 0.5)),
                thresholdCopper = math.max(0, math.floor(threshold + 0.5)),
                scope = "all",
                urgent = false,
                enabled = true,
                selected = true,
                listName = (panel.lastMode == "craft") and "Craft Materials" or "Processing Scan",
            }
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
                local name = craft.outputName or craft.recipeName or ("Item " .. tostring(craft.outputItemID or "?"))
                local isSelected = panel.selectedCrafts and panel.selectedCrafts[name]
                if (not hasCraftSelection) or isSelected then
                    for _, mat in ipairs(craft.matsDetailed or {}) do
                        AddCandidate(mat.itemID, mat.capPrice or mat.price, mat.price, nil)
                    end
                end
            end
        else
            for _, r in ipairs(panel.lastArbitrageResults or {}) do
                local isSelected = panel.selectedArbitrage and panel.selectedArbitrage[r.inputItemID]
                if (not hasArbitrageSelection) or isSelected then
                    AddCandidate(r.inputItemID, r.maxBuyPerUnit, r.livePrice, r.inputName)
                end
            end
        end

        if #candidates == 0 then
            statusSummary:SetText("|cffff4444No valid rows to track.|r")
            return
        end

        if MarketSync.ShowBulkAlertImportPopup then
            local listLabel = (panel.lastMode == "craft") and "Craft Materials" or "Processing Scan"
            MarketSync.ShowBulkAlertImportPopup(listLabel, candidates, function(imported)
                if imported and imported > 0 then
                    statusSummary:SetText(string.format("|cff00ff00Imported %d alert(s) to Watchlist!|r", imported))
                end
            end)
            return
        end

        local tracked = 0
        for _, c in ipairs(candidates) do
            if MarketSync.UpsertNotificationRequest then
                local req = MarketSync.UpsertNotificationRequest(c)
                if req then tracked = tracked + 1 end
            end
        end
        statusSummary:SetText(string.format("|cff00ff00Tracked %d item(s).|r", tracked))
    end)

    local function SaveCurrentView()
        local isCraft = panel.activeMode == "craft"
        if isCraft and not MarketSync.UpsertProcessingCraftSet then
            statusSummary:SetText("|cffff4444Craft lists unavailable.|r")
            return
        end
        if not isCraft and not MarketSync.UpsertProcessingCustomSelection then
            statusSummary:SetText("|cffff4444Custom selections unavailable.|r")
            return
        end

        local name = TrimText(customNameBox:GetText())
        if name == "" then
            statusSummary:SetText(isCraft and "|cffff4444List name is required.|r" or "|cffff4444Preset name is required.|r")
            return
        end

        if isCraft then
            local itemIDs = {}
            local seen = {}
            for _, craft in ipairs(panel.lastCraftResults or {}) do
                local outputName = craft.outputName or craft.recipeName or ("Item " .. tostring(craft.outputItemID or "?"))
                local itemID = tonumber(craft.outputItemID)
                if itemID and panel.selectedCrafts[outputName] and not seen[itemID] then
                    itemIDs[#itemIDs + 1] = itemID
                    seen[itemID] = true
                end
            end
            local saved, err = MarketSync.UpsertProcessingCraftSet(name, itemIDs)
            if not saved then
                statusSummary:SetText("|cffff4444Save failed:|r " .. tostring(err or "unknown error"))
                return
            end
            panel.activeCraftSet = saved
            panel.customPage = 0
            customNameBox:SetText("")
            RefreshCustomRows()
            if RunActiveMode then RunActiveMode() end
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
            marginPct = 0,
            minCraftMarginGold = 0,
            filters = {
                onlyProfitable = panel.filters.onlyProfitable,
                hideStale = panel.filters.hideStale,
                madeBy = panel.filters.madeBy,
                minLevel = panel.filters.minLevel,
                maxLevel = panel.filters.maxLevel,
            },
        }

        local saved, err = MarketSync.UpsertProcessingCustomSelection(payload)
        if not saved then
            statusSummary:SetText("|cffff4444Save failed:|r " .. tostring(err or "unknown error"))
            return
        end

        customNameBox:SetText("")
        panel.customPage = 0
        RefreshCustomRows()
        statusSummary:SetText("|cff00ff00Saved view:|r " .. Truncate(saved.name or name, 22))
    end
    panel.SaveCurrentView = function(name)
        customNameBox:SetText(name or "")
        SaveCurrentView()
    end

    btnSaveCustom:SetScript("OnClick", function()
        local isCraft = panel.activeMode == "craft"
        if isCraft then
            local any = false
            for _, v in pairs(panel.selectedCrafts or {}) do if v then any = true break end end
            if not any then
                statusSummary:SetText("|cffffd100Click the recipes to keep first, then + List.|r")
                return
            end
        end
        if StaticPopup_Show then
            StaticPopup_Show("MARKETSYNC_PROCESSING_SAVE_VIEW",
                isCraft and "Name this craft list:" or "Name this saved view:", nil,
                { onSave = function(text) panel.SaveCurrentView(text) end })
        end
    end)

    prevBtn:SetScript("OnClick", function()
        if tableScrollBar and tableScrollBar.HandleWheel then
            tableScrollBar:HandleWheel(1)
        else
            panel.page = panel.page - 1
            UpdateResultRows()
        end
    end)

    nextBtn:SetScript("OnClick", function()
        if tableScrollBar and tableScrollBar.HandleWheel then
            tableScrollBar:HandleWheel(-1)
        else
            panel.page = panel.page + 1
            UpdateResultRows()
        end
    end)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if HandleTableMouseWheel then
            HandleTableMouseWheel(delta)
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

        if characterDropdown and characterDropdown._initFunc then
            UIDropDownMenu_Initialize(characterDropdown._menu, characterDropdown._initFunc)
        end

        if targetDropdown and targetDropdown._initFunc then
            UIDropDownMenu_Initialize(targetDropdown._menu, targetDropdown._initFunc)
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

    if MarketSync.Theme then MarketSync.Theme.Register(panel) end
    return panel
end
