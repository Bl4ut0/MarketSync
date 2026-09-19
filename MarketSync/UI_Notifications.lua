-- =============================================================
-- MarketSync - Notifications Tab UI (Perfect Window Fit)
-- Dual-view: Tracked Watchlist & Alert History
-- Interactive item drop slot, presets, and native Favorites import
-- =============================================================

local NotificationPanel = nil
local registeredNotificationPanels = {}
local ROWS_PER_PAGE = 9

local LEFT_X = 20
local TOP_Y = -68
local LEFT_W = 196
local RESULTS_X = 224
local ROW_WIDTH = 584
local CONTENT_H = 338
local ROW_HEIGHT = 27

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
    if MarketSync and MarketSync.CreateModernInset then
        return MarketSync.CreateModernInset(parent, x, y, width, height)
    end
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width, height)
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
    local isEmbedded = (parent ~= MarketSync.MainFrame)
    local LEFT_X = isEmbedded and 12 or 20
    local LEFT_W = isEmbedded and 180 or 196
    local RESULTS_X = isEmbedded and 198 or 224
    local ROW_WIDTH = isEmbedded and 550 or 584
    local numRowsPerPage = isEmbedded and 12 or 9

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    if parent == MarketSync.MainFrame then
        panel:Hide()
    end

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
    panel.importDiscountPct = 10

    -- Forward declarations
    local RefreshView, RefreshWatchlistTable, RefreshHistoryTable, RefreshImportDropdown
    local SetEditorItem, ClearEditorForm

    -- =========================================================
    -- TOP SUB-TAB HEADER (Clearing portrait at X >= 76 on MainFrame)
    -- =========================================================
    local btnTabWatchlist = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTabWatchlist:SetSize(130, 22)
    btnTabWatchlist:SetPoint("TOPLEFT", panel, "TOPLEFT", isEmbedded and 8 or 76, isEmbedded and -8 or -34)
    btnTabWatchlist:SetText("Tracked Watchlist")

    local btnTabHistory = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTabHistory:SetSize(130, 22)
    btnTabHistory:SetPoint("LEFT", btnTabWatchlist, "RIGHT", 6, 0)
    btnTabHistory:SetText("Alert History")

    local btnTestSound = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTestSound:SetSize(76, 20)
    btnTestSound:SetPoint("TOPRIGHT", panel, "TOPRIGHT", isEmbedded and -8 or -26, isEmbedded and -8 or -34)
    btnTestSound:SetText("Test Sound")
    btnTestSound:SetScript("OnClick", function()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then
            MarketSync.PlayNotificationSound(soundID, true)
        end
    end)

    local soundCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    soundCheck:SetSize(20, 20)
    soundCheck:SetPoint("RIGHT", btnTestSound, "LEFT", -75, 0)
    local soundText = soundCheck.text or soundCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    soundCheck.text = soundText
    soundText:SetText("Sound Alerts")
    soundText:ClearAllPoints()
    soundText:SetPoint("LEFT", soundCheck, "RIGHT", 3, 0)
    soundCheck:SetChecked(MarketSyncDB and MarketSyncDB.EnableNotificationSounds ~= false)
    soundCheck:SetScript("OnClick", function(self)
        if MarketSyncDB then
            MarketSyncDB.EnableNotificationSounds = self:GetChecked() and true or false
        end
    end)

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btnTabWatchlist, {
            name = "Tracked Watchlist",
            context = "Tab",
            description = "View and manage tracked item price alerts",
            getIndexInfo = function() return { index = 1, total = 2 } end,
        })
        MarketSync.SetAccessibility(btnTabHistory, {
            name = "Alert History",
            context = "Tab",
            description = "View history of triggered price alerts",
            getIndexInfo = function() return { index = 2, total = 2 } end,
        })
        MarketSync.SetAccessibility(btnTestSound, {
            name = "Test Sound",
            context = "Button",
            description = "Play notification alert test sound",
        })
        MarketSync.SetAccessibility(soundCheck, {
            name = "Sound Alerts",
            context = function(self)
                return self:GetChecked() and "Check Button, Checked" or "Check Button, Unchecked"
            end,
            description = "Toggle audio notifications for market alerts",
        })
    end

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
    -- LEFT COLUMN: ALERT EDITOR (BOX 1 - Height 216)
    -- =========================================================
    local editorBox
    if isEmbedded then
        editorBox = CreateBox(panel, LEFT_X, -34, LEFT_W, 216)
    else
        editorBox = CreateBox(panel, LEFT_X, TOP_Y, LEFT_W, 216)
    end

    local editorTitle = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editorTitle:SetPoint("TOPLEFT", 10, -7)
    editorTitle:SetText("|cffffd700Alert Editor|r")
    local parentPrefix = (parent and parent.GetName and parent:GetName()) or "MarketSync"
    -- 32x32 Item Drop Slot
    local itemSlot = CreateFrame("Button", parentPrefix .. "ItemDropSlot", editorBox)
    itemSlot:SetSize(32, 32)
    itemSlot:SetPoint("TOPLEFT", 10, -23)

    local itemSlotIcon = itemSlot:CreateTexture(nil, "BORDER")
    itemSlotIcon:SetAllPoints()
    itemSlotIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local itemSlotBorder = itemSlot:CreateTexture(nil, "OVERLAY")
    itemSlotBorder:SetSize(36, 36)
    itemSlotBorder:SetPoint("CENTER")
    itemSlotBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    itemSlotBorder:SetBlendMode("ADD")
    itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.5)

    local itemSlotHighlight = itemSlot:CreateTexture(nil, "HIGHLIGHT")
    itemSlotHighlight:SetAllPoints()
    itemSlotHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    itemSlotHighlight:SetBlendMode("ADD")

    local itemSlotName = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    itemSlotName:SetPoint("TOPLEFT", itemSlot, "TOPRIGHT", 6, -1)
    itemSlotName:SetPoint("RIGHT", editorBox, "RIGHT", -6, 0)
    itemSlotName:SetJustifyH("LEFT")
    itemSlotName:SetText("|cff888888Drag item here|r")

    local itemSlotMarket = editorBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    itemSlotMarket:SetPoint("BOTTOMLEFT", itemSlot, "BOTTOMRIGHT", 6, 1)
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

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(itemSlot, {
            name = function()
                return panel.editorItemName or "Item Drop Slot"
            end,
            context = "Button",
            description = "Drop an item from your bags or click with an item to configure price alerts",
        })
    end

    -- Item Target EditBox
    local targetLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    targetLabel:SetPoint("TOPLEFT", 10, -58)
    targetLabel:SetText("Item Name or ID:")

    local targetBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    targetBox:SetSize(LEFT_W - 20, 18)
    targetBox:SetPoint("TOPLEFT", 10, -72)
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

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(targetBox, {
            name = "Item Target",
            context = "Edit Box",
            description = "Enter item name or item ID for price alert",
        })
    end

    -- Threshold Input & Preset Buttons
    local threshLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    threshLabel:SetPoint("TOPLEFT", 10, -94)
    threshLabel:SetText("Alert Below (Gold):")

    local threshBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    threshBox:SetSize(54, 18)
    threshBox:SetPoint("TOPLEFT", 10, -108)
    threshBox:SetAutoFocus(false)
    threshBox:SetText("0")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(threshBox)
    end

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(threshBox, {
            name = "Alert Threshold Gold",
            context = "Edit Box",
            description = "Notify when price drops below this gold amount",
        })
    end

    local btn10Pct = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btn10Pct:SetSize(36, 18)
    btn10Pct:SetPoint("LEFT", threshBox, "RIGHT", 4, 0)
    btn10Pct:SetText("-10%")

    local btn20Pct = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btn20Pct:SetSize(36, 18)
    btn20Pct:SetPoint("LEFT", btn10Pct, "RIGHT", 2, 0)
    btn20Pct:SetText("-20%")

    local btnMarket = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btnMarket:SetSize(38, 18)
    btnMarket:SetPoint("LEFT", btn20Pct, "RIGHT", 2, 0)
    btnMarket:SetText("Mkt")

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

    -- Dedicated Scope Row
    local scopeLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", 10, -130)
    scopeLabel:SetText("Scope:")

    local scopeDropdown = BuildScopeDropdown(
        parentPrefix .. "NotificationsScopeDropdown",
        editorBox,
        80,
        function() return panel.editorScope end,
        function(v) panel.editorScope = v end
    )
    scopeDropdown:SetPoint("TOPLEFT", editorBox, "TOPLEFT", 45, -125)

    -- Dedicated Cooldown Row
    local cooldownLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cooldownLabel:SetPoint("TOPLEFT", 10, -150)
    cooldownLabel:SetText("Cooldown:")

    local cd5m = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd5m:SetSize(24, 18)
    cd5m:SetPoint("LEFT", cooldownLabel, "RIGHT", 6, 0)
    cd5m:SetText("5m")

    local cd15m = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd15m:SetSize(28, 18)
    cd15m:SetPoint("LEFT", cd5m, "RIGHT", 2, 0)
    cd15m:SetText("15m")

    local cd30m = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd30m:SetSize(28, 18)
    cd30m:SetPoint("LEFT", cd15m, "RIGHT", 2, 0)
    cd30m:SetText("30m")

    local cd1h = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    cd1h:SetSize(24, 18)
    cd1h:SetPoint("LEFT", cd30m, "RIGHT", 2, 0)
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
    urgentCheck:SetSize(18, 18)
    urgentCheck:SetPoint("TOPLEFT", 10, -170)
    local urgentText = urgentCheck.text or urgentCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    urgentCheck.text = urgentText
    urgentText:SetText("Urgent (Raid Warning)")
    urgentText:ClearAllPoints()
    urgentText:SetPoint("LEFT", urgentCheck, "RIGHT", 4, 0)
    urgentCheck:SetChecked(false)

    -- Action Buttons
    local btnSave = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btnSave:SetSize(115, 20)
    btnSave:SetPoint("TOPLEFT", 10, -190)
    btnSave:SetText("Add Alert")

    local btnClear = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate")
    btnClear:SetSize(58, 20)
    btnClear:SetPoint("LEFT", btnSave, "RIGHT", 4, 0)
    btnClear:SetText("Clear")

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(urgentCheck, {
            name = "Urgent Alert",
            context = function(self)
                return self:GetChecked() and "Check Button, Checked" or "Check Button, Unchecked"
            end,
            description = "Show raid warning popup on screen when this alert triggers",
        })
        MarketSync.SetAccessibility(btnSave, {
            name = function() return btnSave:GetText() or "Add Alert" end,
            context = "Button",
            description = "Save or update this price alert",
        })
        MarketSync.SetAccessibility(btnClear, {
            name = "Clear Form",
            context = "Button",
            description = "Reset alert editor fields",
        })
    end

    -- =========================================================
    -- LEFT COLUMN: PREFERRED LIST IMPORT (BOX 2 - Height 114)
    -- =========================================================
    local importBox
    if isEmbedded then
        importBox = CreateBox(panel, LEFT_X, -260, LEFT_W, 200)
        importBox:SetWidth(LEFT_W)
        importBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_X, 8)
    else
        importBox = CreateBox(panel, LEFT_X, TOP_Y - 224, LEFT_W, 114)
    end

    local importTitle = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importTitle:SetPoint("TOPLEFT", 10, -7)
    importTitle:SetText("|cffffd700Preferred List Import|r")

    local importDropdown = CreateFrame("Frame", parentPrefix .. "NotificationsImportDropdown", importBox, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(importDropdown, LEFT_W - 54)
    importDropdown:SetPoint("TOPLEFT", importBox, "TOPLEFT", -12, -22)

    local discountLabel = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    discountLabel:SetPoint("TOPLEFT", 10, -53)
    discountLabel:SetText("Discount:")

    local impBtn10 = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    impBtn10:SetSize(38, 18)
    impBtn10:SetPoint("LEFT", discountLabel, "RIGHT", 4, 0)
    impBtn10:SetText("-10%")

    local impBtn20 = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    impBtn20:SetSize(38, 18)
    impBtn20:SetPoint("LEFT", impBtn10, "RIGHT", 2, 0)
    impBtn20:SetText("-20%")

    local impBtnMarket = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
    impBtnMarket:SetSize(38, 18)
    impBtnMarket:SetPoint("LEFT", impBtn20, "RIGHT", 2, 0)
    impBtnMarket:SetText("Mkt")

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
    btnDoImport:SetSize(LEFT_W - 20, 20)
    btnDoImport:SetPoint("TOPLEFT", 10, -78)
    btnDoImport:SetText("Import List into Watchlist")

    local importStatusText = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importStatusText:SetPoint("TOPLEFT", 10, -100)
    importStatusText:SetText("")

    if isEmbedded then
        local importDesc = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
        importDesc:SetPoint("TOPLEFT", 10, -118)
        importDesc:SetPoint("BOTTOMRIGHT", -10, 10)
        importDesc:SetJustifyH("LEFT")
        if importDesc.SetJustifyV then
            importDesc:SetJustifyV("TOP")
        end
        importDesc:SetText("|cff777777Automatically populates watchlist price triggers from your favorite items or shopping lists with configured discounts below market price.|r")
    end

    -- =========================================================
    -- RIGHT COLUMN: ENCLOSING RESULTS BOX (Height 338)
    -- =========================================================
    local rightBox
    if isEmbedded then
        rightBox = CreateBox(panel, RESULTS_X, -34, ROW_WIDTH, 440)
        rightBox:SetWidth(ROW_WIDTH)
        rightBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    else
        rightBox = CreateBox(panel, RESULTS_X, TOP_Y, ROW_WIDTH, CONTENT_H)
    end

    -- Top Toolbar inside rightBox
    local searchBox = CreateFrame("EditBox", nil, rightBox, "InputBoxTemplate")
    searchBox:SetSize(180, 18)
    searchBox:SetPoint("TOPLEFT", 10, -8)
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
    local btnMarkAllRead = CreateFrame("Button", nil, rightBox, "UIPanelButtonTemplate")
    btnMarkAllRead:SetSize(95, 20)
    btnMarkAllRead:SetPoint("TOPLEFT", 10, -7)
    btnMarkAllRead:SetText("Mark All Read")
    btnMarkAllRead:SetScript("OnClick", function()
        if MarketSync.MarkAllNotificationsRead then
            MarketSync.MarkAllNotificationsRead()
        end
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end)

    local btnClearHistory = CreateFrame("Button", nil, rightBox, "UIPanelButtonTemplate")
    btnClearHistory:SetSize(90, 20)
    btnClearHistory:SetPoint("LEFT", btnMarkAllRead, "RIGHT", 6, 0)
    btnClearHistory:SetText("Clear History")
    btnClearHistory:SetScript("OnClick", function()
        if MarketSync.ClearNotificationLog then
            MarketSync.ClearNotificationLog()
        end
        panel.historyPage = 0
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end)

    -- Shared Status label
    local statusText = rightBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)
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

    -- Horizontal separator bar above headers
    local headerSep = rightBox:CreateTexture(nil, "BACKGROUND", nil, 2)
    headerSep:SetColorTexture(0.35, 0.30, 0.20, 0.60)
    headerSep:SetPoint("TOPLEFT", 0, -30)
    headerSep:SetSize(ROW_WIDTH, 1)

    -- Header background strip
    local headerStrip = rightBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerStrip:SetColorTexture(0.12, 0.11, 0.10, 0.95)
    headerStrip:SetPoint("TOPLEFT", 0, -31)
    headerStrip:SetSize(ROW_WIDTH, 18)

    -- Watchlist column headers
    local wHdrIcon = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrIcon:SetPoint("TOPLEFT", 10, -34)
    wHdrIcon:SetText("Item")

    local wHdrThresh = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrThresh:SetPoint("TOPLEFT", isEmbedded and 215 or 235, -34)
    wHdrThresh:SetText("Threshold")

    local wHdrScope = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrScope:SetPoint("TOPLEFT", isEmbedded and 305 or 335, -34)
    wHdrScope:SetText("Scope")

    local wHdrCooldown = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrCooldown:SetPoint("TOPLEFT", isEmbedded and 375 or 405, -34)
    wHdrCooldown:SetText("Cooldown")

    local wHdrActive = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrActive:SetPoint("TOPLEFT", isEmbedded and 440 or 475, -34)
    wHdrActive:SetText("Active")

    local wHdrDel = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrDel:SetPoint("TOPLEFT", isEmbedded and 505 or 540, -34)
    wHdrDel:SetText("Del")

    -- History column headers
    local hHdrTime = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrTime:SetPoint("TOPLEFT", 10, -34)
    hHdrTime:SetText("Time")

    local hHdrItem = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrItem:SetPoint("TOPLEFT", isEmbedded and 70 or 75, -34)
    hHdrItem:SetText("Item")

    local hHdrPrice = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrPrice:SetPoint("TOPLEFT", isEmbedded and 235 or 275, -34)
    hHdrPrice:SetText("Alert Price")

    local hHdrThresh = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrThresh:SetPoint("TOPLEFT", isEmbedded and 325 or 365, -34)
    hHdrThresh:SetText("Target")

    local hHdrScope = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrScope:SetPoint("TOPLEFT", isEmbedded and 410 or 450, -34)
    hHdrScope:SetText("Scope")

    local hHdrSource = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hHdrSource:SetPoint("TOPLEFT", isEmbedded and 475 or 515, -34)
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
    -- TABLE ROWS (9 Rows, 27px height each)
    -- =========================================================
    local rows = {}
    local emptyLabel = rightBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyLabel:SetPoint("CENTER", rightBox, "CENTER", 0, 10)
    emptyLabel:SetText("")

    for i = 1, numRowsPerPage do
        local row = CreateFrame("Button", nil, rightBox)
        row:SetSize(ROW_WIDTH - 8, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", rightBox, "TOPLEFT", 4, -51 - ((i - 1) * 28))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(i % 2 == 0 and 0.10 or 0.06, i % 2 == 0 and 0.095 or 0.055, i % 2 == 0 and 0.09 or 0.05, 0.70)
        row.bg = bg

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.30, 0.25, 0.12, 0.40)

        local accent = row:CreateTexture(nil, "OVERLAY")
        accent:SetSize(3, ROW_HEIGHT)
        accent:SetPoint("LEFT")
        accent:SetColorTexture(1, 0.84, 0, 0.9)
        accent:Hide()
        row.accent = accent

        -- Icon button (shared)
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(20, 20)
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
        wName:SetSize(isEmbedded and 175 or 195, 20)
        wName:SetJustifyH("LEFT")
        row.wName = wName

        local wThresh = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wThresh:SetPoint("LEFT", isEmbedded and 211 or 231, 0)
        wThresh:SetSize(isEmbedded and 85 or 90, 20)
        wThresh:SetJustifyH("LEFT")
        row.wThresh = wThresh

        local wScope = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wScope:SetPoint("LEFT", isEmbedded and 301 or 331, 0)
        wScope:SetSize(isEmbedded and 65 or 60, 20)
        wScope:SetJustifyH("LEFT")
        row.wScope = wScope

        local wCooldown = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wCooldown:SetPoint("LEFT", isEmbedded and 371 or 401, 0)
        wCooldown:SetSize(isEmbedded and 60 or 55, 20)
        wCooldown:SetJustifyH("LEFT")
        row.wCooldown = wCooldown

        local wActiveCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        wActiveCheck:SetSize(18, 18)
        wActiveCheck:SetPoint("LEFT", isEmbedded and 442 or 477, 0)
        row.wActiveCheck = wActiveCheck

        local wDelBtn = CreateFrame("Button", nil, row)
        wDelBtn:SetSize(18, 18)
        wDelBtn:SetPoint("LEFT", isEmbedded and 503 or 538, 0)
        local delText = wDelBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        delText:SetPoint("CENTER")
        delText:SetText("|cffff4444✕|r")
        row.wDelBtn = wDelBtn

        -- History items
        local hTime = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hTime:SetPoint("LEFT", 4, 0)
        hTime:SetSize(58, 20)
        hTime:SetJustifyH("LEFT")
        row.hTime = hTime

        local hName = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hName:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
        hName:SetSize(isEmbedded and 150 or 165, 20)
        hName:SetJustifyH("LEFT")
        row.hName = hName

        local hPrice = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hPrice:SetPoint("LEFT", isEmbedded and 231 or 271, 0)
        hPrice:SetSize(85, 20)
        hPrice:SetJustifyH("LEFT")
        row.hPrice = hPrice

        local hThresh = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hThresh:SetPoint("LEFT", isEmbedded and 321 or 361, 0)
        hThresh:SetSize(80, 20)
        hThresh:SetJustifyH("LEFT")
        row.hThresh = hThresh

        local hScope = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hScope:SetPoint("LEFT", isEmbedded and 406 or 446, 0)
        hScope:SetSize(isEmbedded and 60 or 55, 20)
        hScope:SetJustifyH("LEFT")
        row.hScope = hScope

        local hSource = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hSource:SetPoint("LEFT", isEmbedded and 471 or 511, 0)
        hSource:SetSize(58, 20)
        hSource:SetJustifyH("LEFT")
        row.hSource = hSource

        -- Row click handler (load into editor)
        row:SetScript("OnClick", function(self)
            if row.request then
                panel.editorEditingID = row.request.id
                btnSave:SetText("Update Alert")
                SetEditorItem(row.request.matchValue or row.request.displayName or row.itemID)
                threshBox:SetText(FormatGoldInput(row.request.thresholdCopper))
                panel.editorScope = row.request.scope or "all"
                UIDropDownMenu_SetText(scopeDropdown, ScopeLabel(panel.editorScope))
                HighlightCooldownBtn(tonumber(row.request.cooldownSec) or 300)
                urgentCheck:SetChecked(row.request.urgent == true)
            elseif row.historyEntry then
                SetEditorItem(row.historyEntry.itemLink or row.historyEntry.itemID or row.historyEntry.itemName)
                threshBox:SetText(FormatGoldInput(row.historyEntry.threshold))
            end
        end)

        rows[i] = row
    end

    -- Footer inside rightBox
    local footerSep = rightBox:CreateTexture(nil, "BACKGROUND", nil, 2)
    footerSep:SetColorTexture(0.35, 0.30, 0.20, 0.60)
    footerSep:SetPoint("BOTTOMLEFT", 0, 30)
    footerSep:SetSize(ROW_WIDTH, 1)

    local countText = rightBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    countText:SetPoint("BOTTOMLEFT", 10, 8)
    countText:SetText("")

    local btnPrev = CreateFrame("Button", nil, rightBox, "UIPanelButtonTemplate")
    btnPrev:SetSize(50, 18)
    btnPrev:SetPoint("BOTTOMRIGHT", -105, 6)
    btnPrev:SetText("< Prev")

    local pageText = rightBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pageText:SetPoint("LEFT", btnPrev, "RIGHT", 4, 0)
    pageText:SetPoint("RIGHT", rightBox, "BOTTOMRIGHT", -54, 15)
    pageText:SetJustifyH("CENTER")
    pageText:SetText("1 / 1")

    local btnNext = CreateFrame("Button", nil, rightBox, "UIPanelButtonTemplate")
    btnNext:SetSize(50, 18)
    btnNext:SetPoint("BOTTOMRIGHT", -6, 6)
    btnNext:SetText("Next >")

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btnPrev, {
            name = "Previous Page",
            context = "Button",
            description = "Go to previous page of alerts",
        })
        MarketSync.SetAccessibility(btnNext, {
            name = "Next Page",
            context = "Button",
            description = "Go to next page of alerts",
        })
    end

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
        local thresholdMultiplier = (100 - discountPct)
        local imported = 0
        local err = nil

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
            importStatusText:SetText(string.format("|cff00ff00Imported %d alert(s)!|r", imported))
            panel.watchlistPage = 0
            RefreshWatchlistTable()
            C_Timer.After(4, function() importStatusText:SetText("") end)
        else
            importStatusText:SetText("|cffff4444" .. tostring(err or "No items imported.") .. "|r")
            C_Timer.After(4, function() importStatusText:SetText("") end)
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
        local maxPage = math.max(0, math.ceil(total / numRowsPerPage) - 1)
        if panel.watchlistPage > maxPage then panel.watchlistPage = maxPage end
        if panel.watchlistPage < 0 then panel.watchlistPage = 0 end

        btnPrev:SetEnabled(panel.watchlistPage > 0)
        btnNext:SetEnabled(panel.watchlistPage < maxPage)
        pageText:SetText(string.format("%d / %d", panel.watchlistPage + 1, math.max(1, maxPage + 1)))

        local startIndex = (panel.watchlistPage * numRowsPerPage) + 1
        local endIndex = math.min(total, startIndex + numRowsPerPage - 1)

        if total == 0 then
            countText:SetText("No tracked items")
            emptyLabel:SetText(panel.searchQuery ~= "" and "No matching tracked items." or "No tracked items.\nDrag an item to the editor or import a Preferred List.")
            emptyLabel:Show()
        else
            countText:SetText(string.format("Showing %d-%d of %d alerts", startIndex, endIndex, total))
            emptyLabel:Hide()
        end

        for i = 1, numRowsPerPage do
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

                if MarketSync.SetAccessibility then
                    local displayName = MarketSync.StripColorCodes(req.displayName or req.matchValue or "Item")
                    MarketSync.SetAccessibility(row, {
                        name = function()
                            return displayName
                        end,
                        context = "Button",
                        description = function()
                            local thresh = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(req.thresholdCopper) or (tostring(req.thresholdCopper or 0) .. " copper")
                            local stateStr = (req.enabled ~= false) and "Active" or "Disabled"
                            return string.format("%s, Alert threshold below %s, Status: %s. Click to load into alert editor.", displayName, thresh, stateStr)
                        end,
                        getIndexInfo = function()
                            return { index = reqIndex, total = total }
                        end,
                    })
                    MarketSync.SetAccessibility(row.wActiveCheck, {
                        name = "Enable Alert: " .. displayName,
                        context = function(self)
                            return self:GetChecked() and "Check Button, Checked" or "Check Button, Unchecked"
                        end,
                        description = "Toggle active monitoring for " .. displayName,
                    })
                    MarketSync.SetAccessibility(row.wDelBtn, {
                        name = "Delete Alert: " .. displayName,
                        context = "Button",
                        description = "Remove " .. displayName .. " from price alert watchlist",
                    })
                end

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
        local maxPage = math.max(0, math.ceil(total / numRowsPerPage) - 1)
        if panel.historyPage > maxPage then panel.historyPage = maxPage end
        if panel.historyPage < 0 then panel.historyPage = 0 end

        btnPrev:SetEnabled(panel.historyPage > 0)
        btnNext:SetEnabled(panel.historyPage < maxPage)
        pageText:SetText(string.format("%d / %d", panel.historyPage + 1, math.max(1, maxPage + 1)))

        local startIndex = (panel.historyPage * numRowsPerPage) + 1
        local endIndex = math.min(total, startIndex + numRowsPerPage - 1)

        if total == 0 then
            countText:SetText("No alerts recorded")
            emptyLabel:SetText("No alerts recorded yet.\nAlerts will appear here when prices drop below your thresholds.")
            emptyLabel:Show()
        else
            countText:SetText(string.format("Showing %d-%d of %d alerts", startIndex, endIndex, total))
            emptyLabel:Hide()
        end

        for i = 1, numRowsPerPage do
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
                row.iconBtn:SetPoint("LEFT", 68, 0)
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

                if MarketSync.SetAccessibility then
                    local cleanHistName = MarketSync.StripColorCodes(entry.itemName or (entry.itemID and ("Item " .. entry.itemID)) or "Alert")
                    MarketSync.SetAccessibility(row, {
                        name = function()
                            return cleanHistName
                        end,
                        context = "Button",
                        description = function()
                            local priceStr = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(entry.price) or (tostring(entry.price or 0) .. " copper")
                            local threshStr = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(entry.threshold) or (tostring(entry.threshold or 0) .. " copper")
                            return string.format("%s, Seen price: %s, Threshold was: %s, Source: %s. Click to search in Auction House.", cleanHistName, priceStr, threshStr, entry.source or "Scan")
                        end,
                        getIndexInfo = function()
                            return { index = (panel.historyPage * ROWS_PER_PAGE) + i, total = total }
                        end,
                    })
                end

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
    panel.rows = rows
    panel.rightBox = rightBox
    table.insert(registeredNotificationPanels, panel)
    return panel
end

function MarketSync.ToggleNotificationsManager()
    if MarketSync.SelectMainFrameTab then
        if MarketSyncMainFrame and not MarketSyncMainFrame:IsShown() then
            MarketSyncMainFrame:Show()
        end
        MarketSync.SelectMainFrameTab(6)
    elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[6] then
        if not MarketSyncMainFrame:IsShown() then
            MarketSyncMainFrame:Show()
        end
        MarketSyncMainFrame.tabs[6]:Click()
    elseif MarketSync_ToggleUI then
        MarketSync_ToggleUI()
    end
end
