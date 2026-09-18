-- =============================================================
-- MarketSync - Notifications Tab UI (Modern Overhaul)
-- Dual-view: Tracked Watchlist & Alert History
-- Interactive item drop slot, presets, and native Favorites import
-- =============================================================

local NotificationPanel = nil
local ROWS_PER_PAGE = 10

local LEFT_X = 20
local TOP_Y = -58
local LEFT_W = 215
local RESULTS_X = 245
local ROW_WIDTH = 565
local ROW_HEIGHT = 28

local SCOPE_OPTIONS = {
    { value = "all", label = "All Scopes" },
    { value = "main", label = "Main AH" },
    { value = "neutral", label = "Neutral AH" },
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

local function TrimText(text)
    local raw = tostring(text or "")
    if strtrim then return strtrim(raw) end
    return raw:gsub("^%s+", ""):gsub("%s+$", "")
end

local function ScopeLabel(scopeValue)
    for _, opt in ipairs(SCOPE_OPTIONS) do
        if opt.value == scopeValue then
            return opt.label
        end
    end
    return "All"
end

local function ParseGoldToCopper(text)
    if MarketSync.ParseMoneyToCopper then
        return MarketSync.ParseMoneyToCopper(text)
    end
    local raw = TrimText(text):gsub(",", ".")
    local gold = tonumber(raw)
    return gold and math.max(0, math.floor((gold * 10000) + 0.5)) or 0
end

local function FormatGoldInput(copper)
    if MarketSync.FormatMoneyPlain then
        return MarketSync.FormatMoneyPlain(copper)
    end
    local c = math.max(0, tonumber(copper) or 0)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    if s > 0 then
        return string.format("%.2f", c / 10000)
    end
    return tostring(g)
end

local function FormatMoneyColored(copper)
    if MarketSync.FormatMoneyColored then
        return MarketSync.FormatMoneyColored(copper)
    end
    if MarketSync.FormatMoney then
        return MarketSync.FormatMoney(copper)
    end
    return tostring(copper or 0) .. "c"
end

local function FormatRelativeTime(epochTime, fallbackDays)
    if MarketSync.FormatRelativeTime then
        return MarketSync.FormatRelativeTime(epochTime, fallbackDays)
    end
    if epochTime and epochTime > 0 then
        local diff = math.max(0, time() - epochTime)
        if diff < 60 then return "Just now" end
        if diff < 3600 then return string.format("%dm ago", math.floor(diff / 60)) end
        if diff < 86400 then return string.format("%dh ago", math.floor(diff / 3600)) end
        return string.format("%dd ago", math.floor(diff / 86400))
    end
    return "Today"
end

local function CreateBox(parent, x, y, width, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width, height)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)

    local function BorderLine(anchorPoint, relPoint, ox, oy, w, h)
        local t = box:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetColorTexture(1, 0.84, 0, 0.25)
        t:SetPoint(anchorPoint, box, relPoint, ox, oy)
        t:SetSize(w, h)
    end

    BorderLine("TOPLEFT", "TOPLEFT", 0, 0, width, 1)
    BorderLine("BOTTOMLEFT", "BOTTOMLEFT", 0, 0, width, 1)
    BorderLine("TOPLEFT", "TOPLEFT", 0, 0, 1, height)
    BorderLine("TOPRIGHT", "TOPRIGHT", 0, 0, 1, height)

    return box
end

local function BuildScopeDropdown(frameName, parent, width, getValue, setValue)
    local dd = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, opt in ipairs(SCOPE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.func = function()
                setValue(opt.value)
                UIDropDownMenu_SetText(dd, opt.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(dd, ScopeLabel(getValue()))
    return dd
end

-- =============================================================
-- MAIN PANEL CREATION
-- =============================================================
function MarketSync.CreateNotificationsPanel(parent)
    if NotificationPanel then
        return NotificationPanel
    end

    local panel = CreateFrame("Frame", "MarketSyncNotificationsPanel", parent)
    panel:SetAllPoints(parent)
    panel:Hide()

    -- State
    panel.currentView = "watchlist" -- "watchlist" or "history"
    panel.watchlistPage = 0
    panel.historyPage = 0
    panel.searchQuery = ""
    panel.editorItemID = nil
    panel.editorItemLink = nil
    panel.editorItemName = nil
    panel.editorMarketPrice = 0
    panel.editorScope = "all"
    panel.editorCooldown = 300
    panel.editorEditingID = nil
    panel.importSelectedList = "__ALL__"
    panel.importDiscountPct = 10 -- default 10% below market

    -- Forward declarations
    local RefreshView, RefreshWatchlistTable, RefreshHistoryTable, RefreshImportDropdown
    local SetEditorItem, ClearEditorForm

    -- =========================================================
    -- TOP SUB-TAB HEADER
    -- =========================================================
    local btnTabWatchlist = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTabWatchlist:SetSize(140, 22)
    btnTabWatchlist:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -28)
    btnTabWatchlist:SetText("Tracked Watchlist")

    local btnTabHistory = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTabHistory:SetSize(140, 22)
    btnTabHistory:SetPoint("LEFT", btnTabWatchlist, "RIGHT", 8, 0)
    btnTabHistory:SetText("Alert History")

    local soundCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    soundCheck:SetSize(22, 22)
    soundCheck:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -150, -28)
    soundCheck.text:SetText("Sound Alerts")
    soundCheck.text:ClearAllPoints()
    soundCheck.text:SetPoint("LEFT", soundCheck, "RIGHT", 4, 0)
    soundCheck:SetChecked(MarketSyncDB and MarketSyncDB.EnableNotificationSounds ~= false)
    soundCheck:SetScript("OnClick", function(self)
        if MarketSyncDB then
            MarketSyncDB.EnableNotificationSounds = self:GetChecked() and true or false
        end
    end)

    local btnTestSound = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTestSound:SetSize(78, 20)
    btnTestSound:SetPoint("LEFT", soundCheck.text, "RIGHT", 14, 0)
    btnTestSound:SetText("Test Sound")
    btnTestSound:SetScript("OnClick", function()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then
            MarketSync.PlayNotificationSound(soundID, true)
        end
    end)

    local function UpdateSubTabButtons()
        if panel.currentView == "watchlist" then
            btnTabWatchlist:Disable()
            btnTabHistory:Enable()
        else
            btnTabWatchlist:Enable()
            btnTabHistory:Disable()
        end

        local unread = tonumber(MarketSync.NotificationUnreadCount) or 0
        if unread > 0 then
            btnTabHistory:SetText(string.format("Alert History (|cffffd700%d|r)", unread))
        else
            btnTabHistory:SetText("Alert History")
        end
    end

    btnTabWatchlist:SetScript("OnClick", function()
        panel.currentView = "watchlist"
        UpdateSubTabButtons()
        RefreshView()
    end)

    btnTabHistory:SetScript("OnClick", function()
        panel.currentView = "history"
        UpdateSubTabButtons()
        RefreshView()
    end)

    -- =========================================================
    -- LEFT COLUMN: ALERT EDITOR (BOX 1)
    -- =========================================================
    local editorBox = CreateBox(panel, LEFT_X, TOP_Y, LEFT_W, 245)

    local editorTitle = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editorTitle:SetPoint("TOPLEFT", 10, -8)
    editorTitle:SetText("|cffffd700Alert Editor|r")

    -- 36x36 Item Drop Slot
    local itemSlot = CreateFrame("Button", "MarketSyncItemDropSlot", editorBox)
    itemSlot:SetSize(36, 36)
    itemSlot:SetPoint("TOPLEFT", 10, -28)

    local itemSlotIcon = itemSlot:CreateTexture(nil, "BORDER")
    itemSlotIcon:SetAllPoints()
    itemSlotIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local itemSlotBorder = itemSlot:CreateTexture(nil, "OVERLAY")
    itemSlotBorder:SetSize(40, 40)
    itemSlotBorder:SetPoint("CENTER")
    itemSlotBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    itemSlotBorder:SetBlendMode("ADD")
    itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.5)

    local itemSlotHighlight = itemSlot:CreateTexture(nil, "HIGHLIGHT")
    itemSlotHighlight:SetAllPoints()
    itemSlotHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    itemSlotHighlight:SetBlendMode("ADD")

    local itemSlotName = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    itemSlotName:SetPoint("TOPLEFT", itemSlot, "TOPRIGHT", 8, 0)
    itemSlotName:SetPoint("RIGHT", editorBox, "RIGHT", -8, 0)
    itemSlotName:SetJustifyH("LEFT")
    itemSlotName:SetText("|cff888888Drag item here|r")

    local itemSlotMarket = editorBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    itemSlotMarket:SetPoint("BOTTOMLEFT", itemSlot, "BOTTOMRIGHT", 8, 2)
    itemSlotMarket:SetJustifyH("LEFT")
    itemSlotMarket:SetText("Market: |cff888888--|r")

    itemSlot:SetScript("OnReceiveDrag", function()
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then
            SetEditorItem(itemLink or itemID)
            ClearCursor()
        end
    end)

    itemSlot:SetScript("OnClick", function(self, button)
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then
            SetEditorItem(itemLink or itemID)
            ClearCursor()
        elseif button == "RightButton" then
            ClearEditorForm()
        elseif panel.editorItemLink and IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(panel.editorItemLink)
        end
    end)

    itemSlot:SetScript("OnEnter", function(self)
        if panel.editorItemLink or panel.editorItemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if panel.editorItemLink then
                GameTooltip:SetHyperlink(panel.editorItemLink)
            else
                GameTooltip:SetItemByID(panel.editorItemID)
            end
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Item Drop Slot", 1, 0.82, 0)
            GameTooltip:AddLine("Drag an item from your bag or shift-click a link here to set up an alert.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
    end)
    itemSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Item Target EditBox
    local targetLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    targetLabel:SetPoint("TOPLEFT", 10, -70)
    targetLabel:SetText("Item Name or ID:")

    local targetBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    targetBox:SetSize(LEFT_W - 20, 18)
    targetBox:SetPoint("TOPLEFT", 10, -86)
    targetBox:SetAutoFocus(false)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(targetBox, {
            onInsertLink = function(box, text)
                local id = text and text:match("item:(%d+)")
                if id then
                    SetEditorItem(tonumber(id))
                    return true
                end
                local itemName = text and text:match("%[(.-)%]")
                if itemName then
                    SetEditorItem(itemName)
                    return true
                end
                return false
            end
        })
    end

    -- Threshold Input & Preset Buttons
    local threshLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    threshLabel:SetPoint("TOPLEFT", 10, -110)
    threshLabel:SetText("Alert Below (Gold):")

    local threshBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    threshBox:SetSize(62, 18)
    threshBox:SetPoint("TOPLEFT", 10, -126)
    threshBox:SetAutoFocus(false)
    threshBox:SetText("0")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(threshBox)
    end

    local btn10Pct = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btn10Pct:SetSize(40, 18)
    btn10Pct:SetPoint("LEFT", threshBox, "RIGHT", 4, 0)
    btn10Pct:SetText("-10%")

    local btn20Pct = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btn20Pct:SetSize(40, 18)
    btn20Pct:SetPoint("LEFT", btn10Pct, "RIGHT", 2, 0)
    btn20Pct:SetText("-20%")

    local btnMarket = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btnMarket:SetSize(44, 18)
    btnMarket:SetPoint("LEFT", btn20Pct, "RIGHT", 2, 0)
    btnMarket:SetText("Market")

    local function ApplyThresholdPreset(multiplier)
        local mp = panel.editorMarketPrice or 0
        if mp > 0 then
            local targetCopper = math.max(0, math.floor(mp * multiplier))
            threshBox:SetText(FormatGoldInput(targetCopper))
        end
    end

    btn10Pct:SetScript("OnClick", function() ApplyThresholdPreset(0.9) end)
    btn20Pct:SetScript("OnClick", function() ApplyThresholdPreset(0.8) end)
    btnMarket:SetScript("OnClick", function() ApplyThresholdPreset(1.0) end)

    -- Scope Dropdown & Cooldown Presets
    local scopeLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", 10, -148)
    scopeLabel:SetText("Scope:")

    local scopeDropdown = BuildScopeDropdown(
        "MarketSyncNotificationsScopeDropdown",
        editorBox,
        85,
        function() return panel.editorScope end,
        function(v) panel.editorScope = v end
    )
    scopeDropdown:SetPoint("TOPLEFT", editorBox, "TOPLEFT", -6, -160)

    local cooldownLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cooldownLabel:SetPoint("TOPLEFT", 112, -148)
    cooldownLabel:SetText("Cooldown:")

    local cd5m = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd5m:SetSize(22, 18)
    cd5m:SetPoint("TOPLEFT", 112, -164)
    cd5m:SetText("5m")

    local cd15m = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd15m:SetSize(26, 18)
    cd15m:SetPoint("LEFT", cd5m, "RIGHT", 1, 0)
    cd15m:SetText("15m")

    local cd30m = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd30m:SetSize(26, 18)
    cd30m:SetPoint("LEFT", cd15m, "RIGHT", 1, 0)
    cd30m:SetText("30m")

    local cd1h = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd1h:SetSize(22, 18)
    cd1h:SetPoint("LEFT", cd30m, "RIGHT", 1, 0)
    cd1h:SetText("1h")

    local function HighlightCooldownBtn(seconds)
        panel.editorCooldown = seconds
        cd5m:SetAlpha(seconds == 300 and 1.0 or 0.6)
        cd15m:SetAlpha(seconds == 900 and 1.0 or 0.6)
        cd30m:SetAlpha(seconds == 1800 and 1.0 or 0.6)
        cd1h:SetAlpha(seconds == 3600 and 1.0 or 0.6)
    end

    cd5m:SetScript("OnClick", function() HighlightCooldownBtn(300) end)
    cd15m:SetScript("OnClick", function() HighlightCooldownBtn(900) end)
    cd30m:SetScript("OnClick", function() HighlightCooldownBtn(1800) end)
    cd1h:SetScript("OnClick", function() HighlightCooldownBtn(3600) end)
    HighlightCooldownBtn(300)

    -- Urgent Checkbox
    local urgentCheck = CreateFrame("CheckButton", nil, editorBox, "UICheckButtonTemplate")
    urgentCheck:SetSize(20, 20)
    urgentCheck:SetPoint("TOPLEFT", 10, -188)
    urgentCheck.text:SetText("Urgent (Raid Warning)")
    urgentCheck.text:ClearAllPoints()
    urgentCheck.text:SetPoint("LEFT", urgentCheck, "RIGHT", 4, 0)
    urgentCheck:SetChecked(false)

    -- Action Buttons
    local btnSave = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btnSave:SetSize(125, 22)
    btnSave:SetPoint("TOPLEFT", 10, -214)
    btnSave:SetText("Add Alert")

    local btnClear = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btnClear:SetSize(65, 22)
    btnClear:SetPoint("LEFT", btnSave, "RIGHT", 5, 0)
    btnClear:SetText("Clear")

    -- =========================================================
    -- LEFT COLUMN: PREFERRED LIST IMPORT (BOX 2)
    -- =========================================================
    local importBox = CreateBox(panel, LEFT_X, TOP_Y - 253, LEFT_W, 115)

    local importTitle = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importTitle:SetPoint("TOPLEFT", 10, -8)
    importTitle:SetText("|cffffd700Preferred List Import|r")

    local importDropdown = CreateFrame("Frame", "MarketSyncNotificationsImportDropdown", importBox, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(importDropdown, LEFT_W - 35)
    importDropdown:SetPoint("TOPLEFT", importBox, "TOPLEFT", -6, -24)

    local discountLabel = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    discountLabel:SetPoint("TOPLEFT", 10, -56)
    discountLabel:SetText("Threshold:")

    local impBtn10 = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    impBtn10:SetSize(42, 18)
    impBtn10:SetPoint("LEFT", discountLabel, "RIGHT", 6, 0)
    impBtn10:SetText("-10%")

    local impBtn20 = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    impBtn20:SetSize(42, 18)
    impBtn20:SetPoint("LEFT", impBtn10, "RIGHT", 2, 0)
    impBtn20:SetText("-20%")

    local impBtnMarket = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    impBtnMarket:SetSize(45, 18)
    impBtnMarket:SetPoint("LEFT", impBtn20, "RIGHT", 2, 0)
    impBtnMarket:SetText("Market")

    local function HighlightImportDiscount(pct)
        panel.importDiscountPct = pct
        impBtn10:SetAlpha(pct == 10 and 1.0 or 0.6)
        impBtn20:SetAlpha(pct == 20 and 1.0 or 0.6)
        impBtnMarket:SetAlpha(pct == 0 and 1.0 or 0.6)
    end

    impBtn10:SetScript("OnClick", function() HighlightImportDiscount(10) end)
    impBtn20:SetScript("OnClick", function() HighlightImportDiscount(20) end)
    impBtnMarket:SetScript("OnClick", function() HighlightImportDiscount(0) end)
    HighlightImportDiscount(10)

    local btnDoImport = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    btnDoImport:SetSize(LEFT_W - 20, 22)
    btnDoImport:SetPoint("TOPLEFT", 10, -82)
    btnDoImport:SetText("Import List into Watchlist")

    -- =========================================================
    -- RIGHT COLUMN: SHARED SEARCH BAR & HEADER
    -- =========================================================
    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, TOP_Y - 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetText("")

    local searchPlaceholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 4, 0)
    searchPlaceholder:SetText("Search alerts...")

    local btnClearSearch = CreateFrame("Button", nil, searchBox)
    btnClearSearch:SetSize(16, 16)
    btnClearSearch:SetPoint("RIGHT", searchBox, "RIGHT", -4, 0)
    local clearSearchText = btnClearSearch:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    clearSearchText:SetPoint("CENTER")
    clearSearchText:SetText("✕")
    btnClearSearch:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        panel.searchQuery = ""
        panel.watchlistPage = 0
        RefreshWatchlistTable()
    end)

    searchBox:SetScript("OnTextChanged", function(self)
        local txt = TrimText(self:GetText())
        if txt == "" then
            searchPlaceholder:Show()
            btnClearSearch:Hide()
        else
            searchPlaceholder:Hide()
            btnClearSearch:Show()
        end
        panel.searchQuery = txt:lower()
        panel.watchlistPage = 0
        RefreshWatchlistTable()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- History Action Buttons
    local btnMarkAllRead = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnMarkAllRead:SetSize(100, 20)
    btnMarkAllRead:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, TOP_Y - 2)
    btnMarkAllRead:SetText("Mark All Read")
    btnMarkAllRead:SetScript("OnClick", function()
        if MarketSync.MarkAllNotificationsRead then
            MarketSync.MarkAllNotificationsRead()
        end
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end)

    local btnClearHistory = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnClearHistory:SetSize(90, 20)
    btnClearHistory:SetPoint("LEFT", btnMarkAllRead, "RIGHT", 8, 0)
    btnClearHistory:SetText("Clear History")
    btnClearHistory:SetScript("OnClick", function()
        if MarketSync.ClearNotificationLog then
            MarketSync.ClearNotificationLog()
        end
        panel.historyPage = 0
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end)

    -- Status label
    local statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    statusText:SetText("")

    local function SetStatus(msg, isError)
        if isError then
            statusText:SetText("|cffff4444" .. tostring(msg) .. "|r")
        else
            statusText:SetText("|cff00ff00" .. tostring(msg) .. "|r")
        end
        C_Timer.After(4, function()
            if statusText:GetText() == msg then statusText:SetText("") end
        end)
    end

    -- =========================================================
    -- RIGHT COLUMN: TABLE HEADERS
    -- =========================================================
    local headerFrame = CreateFrame("Frame", nil, panel)
    headerFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, TOP_Y - 26)
    headerFrame:SetSize(ROW_WIDTH, 20)

    -- Watchlist column headers
    local wHdrIcon = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrIcon:SetPoint("LEFT", 4, 0)
    wHdrIcon:SetText("Item")

    local wHdrThresh = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrThresh:SetPoint("LEFT", 240, 0)
    wHdrThresh:SetText("Threshold")

    local wHdrScope = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrScope:SetPoint("LEFT", 335, 0)
    wHdrScope:SetText("Scope")

    local wHdrCooldown = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrCooldown:SetPoint("LEFT", 395, 0)
    wHdrCooldown:SetText("Cooldown")

    local wHdrActive = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrActive:SetPoint("LEFT", 465, 0)
    wHdrActive:SetText("Active")

    local wHdrDel = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrDel:SetPoint("LEFT", 525, 0)
    wHdrDel:SetText("Del")

    -- History column headers
    local hHdrTime = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrTime:SetPoint("LEFT", 4, 0)
    hHdrTime:SetText("Time")

    local hHdrItem = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrItem:SetPoint("LEFT", 70, 0)
    hHdrItem:SetText("Item")

    local hHdrPrice = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrPrice:SetPoint("LEFT", 270, 0)
    hHdrPrice:SetText("Alert Price")

    local hHdrThresh = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrThresh:SetPoint("LEFT", 365, 0)
    hHdrThresh:SetText("Target")

    local hHdrScope = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrScope:SetPoint("LEFT", 445, 0)
    hHdrScope:SetText("Scope")

    local hHdrSource = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrSource:SetPoint("LEFT", 505, 0)
    hHdrSource:SetText("Source")

    local function UpdateHeaderVisibility()
        local isWatch = (panel.currentView == "watchlist")
        searchBox:SetShown(isWatch)
        wHdrIcon:SetShown(isWatch)
        wHdrThresh:SetShown(isWatch)
        wHdrScope:SetShown(isWatch)
        wHdrCooldown:SetShown(isWatch)
        wHdrActive:SetShown(isWatch)
        wHdrDel:SetShown(isWatch)

        btnMarkAllRead:SetShown(not isWatch)
        btnClearHistory:SetShown(not isWatch)
        hHdrTime:SetShown(not isWatch)
        hHdrItem:SetShown(not isWatch)
        hHdrPrice:SetShown(not isWatch)
        hHdrThresh:SetShown(not isWatch)
        hHdrScope:SetShown(not isWatch)
        hHdrSource:SetShown(not isWatch)
    end

    -- =========================================================
    -- RIGHT COLUMN: ROWS CONTAINER
    -- =========================================================
    local rows = {}
    local emptyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyLabel:SetPoint("CENTER", panel, "TOPLEFT", RESULTS_X + (ROW_WIDTH / 2), TOP_Y - 160)
    emptyLabel:SetText("")

    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(ROW_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, TOP_Y - 48 - ((i - 1) * (ROW_HEIGHT + 1)))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, i % 2 == 0 and 0.12 or 0.08, i % 2 == 0 and 0.12 or 0.08, 0.5)
        row.bg = bg

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        local accent = row:CreateTexture(nil, "OVERLAY")
        accent:SetSize(3, ROW_HEIGHT)
        accent:SetPoint("LEFT")
        accent:SetColorTexture(1, 0.84, 0, 0.9)
        accent:Hide()
        row.accent = accent

        -- Icon button (shared)
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(22, 22)
        iconBtn:SetPoint("LEFT", 4, 0)
        local iconTex = iconBtn:CreateTexture(nil, "BORDER")
        iconTex:SetAllPoints()
        row.iconTex = iconTex
        row.iconBtn = iconBtn

        iconBtn:SetScript("OnEnter", function(self)
            if row.itemLink or row.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if row.itemLink then
                    GameTooltip:SetHyperlink(row.itemLink)
                else
                    GameTooltip:SetItemByID(row.itemID)
                end
                GameTooltip:Show()
            end
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Watchlist items
        local wName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wName:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
        wName:SetSize(200, 20)
        wName:SetJustifyH("LEFT")
        row.wName = wName

        local wThresh = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wThresh:SetPoint("LEFT", 240, 0)
        wThresh:SetSize(85, 20)
        wThresh:SetJustifyH("LEFT")
        row.wThresh = wThresh

        local wScope = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wScope:SetPoint("LEFT", 335, 0)
        wScope:SetSize(50, 20)
        wScope:SetJustifyH("LEFT")
        row.wScope = wScope

        local wCooldown = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wCooldown:SetPoint("LEFT", 395, 0)
        wCooldown:SetSize(55, 20)
        wCooldown:SetJustifyH("LEFT")
        row.wCooldown = wCooldown

        local wActiveCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        wActiveCheck:SetSize(20, 20)
        wActiveCheck:SetPoint("LEFT", 468, 0)
        row.wActiveCheck = wActiveCheck

        local wDelBtn = CreateFrame("Button", nil, row)
        wDelBtn:SetSize(20, 20)
        wDelBtn:SetPoint("LEFT", 526, 0)
        local delText = wDelBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        delText:SetPoint("CENTER")
        delText:SetText("|cffff4444✕|r")
        row.wDelBtn = wDelBtn

        -- History items
        local hTime = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hTime:SetPoint("LEFT", 4, 0)
        hTime:SetSize(62, 20)
        hTime:SetJustifyH("LEFT")
        row.hTime = hTime

        local hName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hName:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
        hName:SetSize(170, 20)
        hName:SetJustifyH("LEFT")
        row.hName = hName

        local hPrice = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hPrice:SetPoint("LEFT", 270, 0)
        hPrice:SetSize(85, 20)
        hPrice:SetJustifyH("LEFT")
        row.hPrice = hPrice

        local hThresh = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hThresh:SetPoint("LEFT", 365, 0)
        hThresh:SetSize(70, 20)
        hThresh:SetJustifyH("LEFT")
        row.hThresh = hThresh

        local hScope = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hScope:SetPoint("LEFT", 445, 0)
        hScope:SetSize(50, 20)
        hScope:SetJustifyH("LEFT")
        row.hScope = hScope

        local hSource = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hSource:SetPoint("LEFT", 505, 0)
        hSource:SetSize(55, 20)
        hSource:SetJustifyH("LEFT")
        row.hSource = hSource

        -- Row click handler (load into editor)
        row:SetScript("OnClick", function(self)
            if row.request then
                -- Load existing request into editor
                panel.editorEditingID = row.request.id
                btnSave:SetText("Update Alert")
                SetEditorItem(row.request.matchValue or row.request.displayName or row.itemID)
                threshBox:SetText(FormatGoldInput(row.request.thresholdCopper))
                panel.editorScope = row.request.scope or "all"
                UIDropDownMenu_SetText(scopeDropdown, ScopeLabel(panel.editorScope))
                HighlightCooldownBtn(tonumber(row.request.cooldownSec) or 300)
                urgentCheck:SetChecked(row.request.urgent == true)
            elseif row.historyEntry then
                -- Load item from alert history into editor
                SetEditorItem(row.historyEntry.itemLink or row.historyEntry.itemID or row.historyEntry.itemName)
                threshBox:SetText(FormatGoldInput(row.historyEntry.threshold))
            end
        end)

        rows[i] = row
    end

    -- Pagination controls
    local footerFrame = CreateFrame("Frame", nil, panel)
    footerFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", RESULTS_X, TOP_Y - 340)
    footerFrame:SetSize(ROW_WIDTH, 24)

    local countText = footerFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    countText:SetPoint("LEFT", 4, 0)
    countText:SetText("")

    local btnPrev = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
    btnPrev:SetSize(55, 20)
    btnPrev:SetPoint("RIGHT", footerFrame, "RIGHT", -120, 0)
    btnPrev:SetText("< Prev")

    local pageText = footerFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pageText:SetPoint("LEFT", btnPrev, "RIGHT", 8, 0)
    pageText:SetPoint("RIGHT", footerFrame, "RIGHT", -55, 0)
    pageText:SetJustifyH("CENTER")
    pageText:SetText("Page 1 / 1")

    local btnNext = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
    btnNext:SetSize(55, 20)
    btnNext:SetPoint("RIGHT", footerFrame, "RIGHT", 0, 0)
    btnNext:SetText("Next >")

    btnPrev:SetScript("OnClick", function()
        if panel.currentView == "watchlist" then
            if panel.watchlistPage > 0 then
                panel.watchlistPage = panel.watchlistPage - 1
                RefreshWatchlistTable()
            end
        else
            if panel.historyPage > 0 then
                panel.historyPage = panel.historyPage - 1
                RefreshHistoryTable()
            end
        end
    end)

    btnNext:SetScript("OnClick", function()
        if panel.currentView == "watchlist" then
            panel.watchlistPage = panel.watchlistPage + 1
            RefreshWatchlistTable()
        else
            panel.historyPage = panel.historyPage + 1
            RefreshHistoryTable()
        end
    end)

    -- Mousewheel pagination
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            btnPrev:Click()
        else
            btnNext:Click()
        end
    end)

    -- =========================================================
    -- EDITOR LOGIC & ITEM RESOLUTION
    -- =========================================================
    SetEditorItem = function(itemOrLink)
        if not itemOrLink then return end
        local raw = tostring(itemOrLink)
        local itemID, suffix = MarketSync.ParseItemIDFromDBKey(raw)
        if not itemID then
            itemID = tonumber(raw:match("item:(%d+)") or raw:match("^(%d+)$"))
        end
        if not itemID and MarketSync.ResolveItemID then
            itemID = MarketSync.ResolveItemID(raw)
        end

        local name, link, quality, _, _, _, _, _, _, icon
        if itemID then
            name, link, quality, _, _, _, _, _, _, icon = SafeGetItemInfo(itemID)
        else
            name, link, quality, _, _, _, _, _, _, icon = SafeGetItemInfo(raw)
            if link then itemID = tonumber(link:match("item:(%d+)")) end
        end

        panel.editorItemID = itemID
        panel.editorItemLink = link
        panel.editorItemName = name or raw

        itemSlotIcon:SetTexture(icon or SafeGetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
        if quality and quality > 1 then
            local r, g, b = GetItemQualityColor(quality)
            itemSlotBorder:SetVertexColor(r, g, b, 0.8)
        else
            itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.5)
        end

        if link then
            itemSlotName:SetText(link)
        elseif name then
            itemSlotName:SetText(name)
        else
            itemSlotName:SetText(raw)
        end
        targetBox:SetText(name or raw)

        -- Check market price
        local priceInfo = MarketSync.GetItemPriceAndScanInfo and MarketSync.GetItemPriceAndScanInfo(link or itemID or raw)
        local marketPrice = priceInfo and priceInfo.price or (MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(link or itemID or raw)) or 0
        panel.editorMarketPrice = marketPrice
        if marketPrice > 0 then
            itemSlotMarket:SetText("Market: " .. FormatMoneyColored(marketPrice))
            -- If threshold is 0, auto-fill -10%
            local curThresh = ParseGoldToCopper(threshBox:GetText())
            if curThresh == 0 then
                threshBox:SetText(FormatGoldInput(math.floor(marketPrice * 0.9)))
            end
        else
            itemSlotMarket:SetText("Market: |cff888888--|r")
        end
    end

    ClearEditorForm = function()
        panel.editorEditingID = nil
        panel.editorItemID = nil
        panel.editorItemLink = nil
        panel.editorItemName = nil
        panel.editorMarketPrice = 0
        itemSlotIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.5)
        itemSlotName:SetText("|cff888888Drag item here|r")
        itemSlotMarket:SetText("Market: |cff888888--|r")
        targetBox:SetText("")
        threshBox:SetText("0")
        panel.editorScope = "all"
        UIDropDownMenu_SetText(scopeDropdown, "All Scopes")
        HighlightCooldownBtn(300)
        urgentCheck:SetChecked(false)
        btnSave:SetText("Add Alert")
    end

    btnClear:SetScript("OnClick", ClearEditorForm)

    targetBox:SetScript("OnEnterPressed", function(self)
        local val = TrimText(self:GetText())
        if val ~= "" then
            SetEditorItem(val)
        end
        self:ClearFocus()
    end)
    targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    threshBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        btnSave:Click()
    end)
    threshBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    btnSave:SetScript("OnClick", function()
        local rawTarget = TrimText(targetBox:GetText())
        if rawTarget == "" and not panel.editorItemID then
            SetStatus("Enter an item name or drop an item.", true)
            return
        end

        local threshCopper = ParseGoldToCopper(threshBox:GetText())
        if threshCopper <= 0 then
            SetStatus("Set a threshold price greater than 0.", true)
            return
        end

        local matchType = "name"
        local matchValue = rawTarget:lower()
        local displayName = panel.editorItemName or rawTarget
        if panel.editorItemID then
            matchType = "itemID"
            matchValue = panel.editorItemID
        end

        local reqID = panel.editorEditingID
        if not reqID then
            local scope = panel.editorScope or "all"
            reqID = string.format("%s:%s:%s", matchType, tostring(matchValue), scope)
        end

        local req = MarketSync.UpsertNotificationRequest({
            id = reqID,
            matchType = matchType,
            matchValue = matchValue,
            displayName = displayName,
            thresholdCopper = threshCopper,
            scope = panel.editorScope or "all",
            variantMode = "any_suffix",
            cooldownSec = panel.editorCooldown or 300,
            urgent = urgentCheck:GetChecked() and true or false,
            enabled = true,
        })

        if req then
            SetStatus(panel.editorEditingID and "Alert updated!" or "Alert added!")
            ClearEditorForm()
            RefreshWatchlistTable()
        else
            SetStatus("Failed to save alert.", true)
        end
    end)

    -- =========================================================
    -- LIST IMPORT CONTROLS
    -- =========================================================
    RefreshImportDropdown = function()
        local lists = MarketSync.GetImportableListNames and MarketSync.GetImportableListNames() or {}
        UIDropDownMenu_Initialize(importDropdown, function(self, level)
            local infoAll = UIDropDownMenu_CreateInfo()
            infoAll.text = "All Lists"
            infoAll.func = function()
                panel.importSelectedList = "__ALL__"
                UIDropDownMenu_SetText(importDropdown, "All Lists")
            end
            UIDropDownMenu_AddButton(infoAll, level)

            for _, item in ipairs(lists) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.label or item.name
                info.func = function()
                    panel.importSelectedList = item.name
                    UIDropDownMenu_SetText(importDropdown, item.label or item.name)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        UIDropDownMenu_SetText(importDropdown, panel.importSelectedList == "__ALL__" and "All Lists" or panel.importSelectedList)
    end

    btnDoImport:SetScript("OnClick", function()
        local listName = panel.importSelectedList
        local discountPct = panel.importDiscountPct or 10
        local thresholdMultiplier = (100 - discountPct) -- e.g. 90%
        local imported = 0
        local err = nil

        -- Prefer native MarketSync Favorites
        if MarketSync.ImportNotificationRequestsFromFavorites then
            imported, err = MarketSync.ImportNotificationRequestsFromFavorites(listName, {
                thresholdPct = thresholdMultiplier,
                scope = "all",
                cooldownSec = 300,
                enabledDefault = true,
            })
        elseif MarketSync.ImportNotificationRequestsFromAuctionator then
            imported, err = MarketSync.ImportNotificationRequestsFromAuctionator({ listName }, {
                thresholdPct = thresholdMultiplier,
                scope = "all",
                cooldownSec = 300,
                enabledDefault = true,
            })
        end

        if imported and imported > 0 then
            SetStatus(string.format("Imported %d alert(s)!", imported))
            panel.watchlistPage = 0
            RefreshWatchlistTable()
        else
            SetStatus(err or "No items imported.", true)
        end
    end)

    -- =========================================================
    -- WATCHLIST TABLE REFRESH
    -- =========================================================
    RefreshWatchlistTable = function()
        local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        local reqMap = realmDB and realmDB.NotificationRequests or {}
        local allReqs = {}

        for _, req in pairs(reqMap) do
            local matchesSearch = true
            if panel.searchQuery and panel.searchQuery ~= "" then
                local name = tostring(req.displayName or req.matchValue or ""):lower()
                matchesSearch = (name:find(panel.searchQuery, 1, true) ~= nil)
            end
            if matchesSearch then
                table.insert(allReqs, req)
            end
        end

        table.sort(allReqs, function(a, b)
            return tostring(a.displayName or a.matchValue or ""):lower() < tostring(b.displayName or b.matchValue or ""):lower()
        end)

        local total = #allReqs
        local maxPage = math.max(0, math.ceil(total / ROWS_PER_PAGE) - 1)
        if panel.watchlistPage > maxPage then panel.watchlistPage = maxPage end
        if panel.watchlistPage < 0 then panel.watchlistPage = 0 end

        btnPrev:SetEnabled(panel.watchlistPage > 0)
        btnNext:SetEnabled(panel.watchlistPage < maxPage)
        pageText:SetText(string.format("Page %d / %d", panel.watchlistPage + 1, math.max(1, maxPage + 1)))

        local startIndex = (panel.watchlistPage * ROWS_PER_PAGE) + 1
        local endIndex = math.min(total, startIndex + ROWS_PER_PAGE - 1)

        if total == 0 then
            countText:SetText("No tracked items")
            emptyLabel:SetText(panel.searchQuery ~= "" and "No matching tracked items." or "No tracked items.\nDrag an item to the editor or import a Preferred List.")
            emptyLabel:Show()
        else
            countText:SetText(string.format("Showing %d-%d of %d tracked alerts", startIndex, endIndex, total))
            emptyLabel:Hide()
        end

        for i = 1, ROWS_PER_PAGE do
            local row = rows[i]
            local reqIndex = startIndex + i - 1
            local req = allReqs[reqIndex]

            -- Hide history elements
            row.hTime:Hide()
            row.hName:Hide()
            row.hPrice:Hide()
            row.hThresh:Hide()
            row.hScope:Hide()
            row.hSource:Hide()
            row.accent:Hide()

            if req then
                row.request = req
                row.historyEntry = nil

                local itemID = nil
                if req.matchType == "itemID" then
                    itemID = tonumber(req.matchValue)
                elseif req.matchType == "dbKey" and MarketSync.ParseItemIDFromDBKey then
                    itemID = MarketSync.ParseItemIDFromDBKey(req.matchValue)
                end
                row.itemID = itemID

                local name, link, quality, _, _, _, _, _, _, icon
                if itemID then
                    name, link, quality, _, _, _, _, _, _, icon = SafeGetItemInfo(itemID)
                end
                row.itemLink = link

                row.iconTex:SetTexture(icon or SafeGetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.iconBtn:SetPoint("LEFT", 4, 0)
                row.iconBtn:Show()

                local dName = link or req.displayName or (itemID and ("Item " .. itemID)) or tostring(req.matchValue)
                if req.urgent then
                    dName = "|cffff4444!|r " .. dName
                end
                row.wName:SetText(dName)
                row.wName:Show()

                row.wThresh:SetText(FormatMoneyColored(req.thresholdCopper))
                row.wThresh:Show()

                row.wScope:SetText(ScopeLabel(req.scope))
                row.wScope:Show()

                local cdSec = tonumber(req.cooldownSec) or 300
                local cdText = (cdSec >= 3600) and string.format("%dh", math.floor(cdSec / 3600)) or string.format("%dm", math.floor(cdSec / 60))
                row.wCooldown:SetText(cdText)
                row.wCooldown:Show()

                row.wActiveCheck:SetChecked(req.enabled ~= false)
                row.wActiveCheck:SetScript("OnClick", function(self)
                    req.enabled = self:GetChecked() and true or false
                    MarketSync.UpsertNotificationRequest(req)
                end)
                row.wActiveCheck:Show()

                row.wDelBtn:SetScript("OnClick", function()
                    MarketSync.DeleteNotificationRequest(req.id)
                    RefreshWatchlistTable()
                end)
                row.wDelBtn:Show()

                row:Show()
            else
                row.request = nil
                row.historyEntry = nil
                row.wName:Hide()
                row.wThresh:Hide()
                row.wScope:Hide()
                row.wCooldown:Hide()
                row.wActiveCheck:Hide()
                row.wDelBtn:Hide()
                row.iconBtn:Hide()
                row:Hide()
            end
        end
    end

    -- =========================================================
    -- ALERT HISTORY TABLE REFRESH
    -- =========================================================
    RefreshHistoryTable = function()
        local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        local history = realmDB and realmDB.NotificationLog or {}

        local total = #history
        local maxPage = math.max(0, math.ceil(total / ROWS_PER_PAGE) - 1)
        if panel.historyPage > maxPage then panel.historyPage = maxPage end
        if panel.historyPage < 0 then panel.historyPage = 0 end

        btnPrev:SetEnabled(panel.historyPage > 0)
        btnNext:SetEnabled(panel.historyPage < maxPage)
        pageText:SetText(string.format("Page %d / %d", panel.historyPage + 1, math.max(1, maxPage + 1)))

        local startIndex = (panel.historyPage * ROWS_PER_PAGE) + 1
        local endIndex = math.min(total, startIndex + ROWS_PER_PAGE - 1)

        if total == 0 then
            countText:SetText("No alerts recorded")
            emptyLabel:SetText("No alerts recorded yet.\nAlerts will appear here when prices drop below your thresholds.")
            emptyLabel:Show()
        else
            countText:SetText(string.format("Showing %d-%d of %d recorded alerts", startIndex, endIndex, total))
            emptyLabel:Hide()
        end

        for i = 1, ROWS_PER_PAGE do
            local row = rows[i]
            local hIndex = startIndex + i - 1
            local entry = history[hIndex]

            -- Hide watchlist elements
            row.wName:Hide()
            row.wThresh:Hide()
            row.wScope:Hide()
            row.wCooldown:Hide()
            row.wActiveCheck:Hide()
            row.wDelBtn:Hide()

            if entry then
                row.historyEntry = entry
                row.request = nil
                row.itemID = entry.itemID
                row.itemLink = entry.itemLink

                row.accent:SetShown(entry.read == false)

                row.hTime:SetText(FormatRelativeTime(entry.time))
                row.hTime:Show()

                row.iconTex:SetTexture(entry.itemIcon or SafeGetItemIcon(entry.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.iconBtn:SetPoint("LEFT", 70, 0)
                row.iconBtn:Show()

                local dName = entry.itemLink or entry.itemName or (entry.itemID and ("Item " .. entry.itemID)) or "Unknown"
                if entry.urgent then
                    dName = "|cffff4444!|r " .. dName
                end
                row.hName:SetText(dName)
                row.hName:Show()

                row.hPrice:SetText(FormatMoneyColored(entry.price))
                row.hPrice:Show()

                row.hThresh:SetText(FormatMoneyColored(entry.threshold))
                row.hThresh:Show()

                row.hScope:SetText(ScopeLabel(entry.scope))
                row.hScope:Show()

                row.hSource:SetText(entry.source or "Scan")
                row.hSource:Show()

                row:Show()
            else
                row.request = nil
                row.historyEntry = nil
                row.hTime:Hide()
                row.hName:Hide()
                row.hPrice:Hide()
                row.hThresh:Hide()
                row.hScope:Hide()
                row.hSource:Hide()
                row.iconBtn:Hide()
                row.accent:Hide()
                row:Hide()
            end
        end
    end

    RefreshView = function()
        UpdateHeaderVisibility()
        if panel.currentView == "watchlist" then
            RefreshWatchlistTable()
        else
            RefreshHistoryTable()
        end
    end

    panel:SetScript("OnShow", function()
        if MarketSync.AcknowledgeNotifications then
            MarketSync.AcknowledgeNotifications()
        end
        if soundCheck then
            soundCheck:SetChecked(MarketSyncDB and MarketSyncDB.EnableNotificationSounds ~= false)
        end
        UpdateSubTabButtons()
        RefreshImportDropdown()
        RefreshView()
        statusText:SetText("")
    end)

    NotificationPanel = panel
    return panel
end

function MarketSync.ToggleNotificationsManager()
    if MarketSync_ToggleUI then
        MarketSync_ToggleUI()
    end
    if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[5] then
        MarketSyncMainFrame.tabs[5]:Click()
    end
end
