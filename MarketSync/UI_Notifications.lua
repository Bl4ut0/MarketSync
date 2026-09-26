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
local CONTENT_H = 348
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

local function StripBlizzardTextures(btn)
    if not btn then return end
    if btn.Left and btn.Left.SetAlpha then btn.Left:SetAlpha(0) end
    if btn.Middle and btn.Middle.SetAlpha then btn.Middle:SetAlpha(0) end
    if btn.Right and btn.Right.SetAlpha then btn.Right:SetAlpha(0) end
    local norm = btn.GetNormalTexture and btn:GetNormalTexture()
    if norm and norm.SetAlpha then norm:SetAlpha(0) end
    local push = btn.GetPushedTexture and btn:GetPushedTexture()
    if push and push.SetAlpha then push:SetAlpha(0) end
    local dis = btn.GetDisabledTexture and btn:GetDisabledTexture()
    if dis and dis.SetAlpha then dis:SetAlpha(0) end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl and hl.SetAlpha and hl.GetTexture and hl:GetTexture() and string.find(tostring(hl:GetTexture()), "UI%-Panel%-Button") then
        hl:SetAlpha(0)
    end
end

local function BuildScopeDropdown(frameName, parent, width, getValue, setValue)
    local dd = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate,BackdropTemplate")
    local ddWidth = width or 100
    local innerWidth = math.max(40, ddWidth - 36)
    UIDropDownMenu_SetWidth(dd, innerWidth)

    local left = _G[frameName.."Left"]
    local mid = _G[frameName.."Middle"]
    local right = _G[frameName.."Right"]
    if left then left:Hide() end
    if mid then mid:Hide() end
    if right then right:Hide() end

    dd:SetSize(ddWidth, 22)
    dd:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    dd:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    dd:SetBackdropBorderColor(0.32, 0.28, 0.20, 0.85)

    local btn = _G[frameName.."Button"]
    if btn then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", dd, "RIGHT", -2, 0)
    end
    local txt = _G[frameName.."Text"]
    if txt then
        txt:ClearAllPoints()
        txt:SetPoint("LEFT", dd, "LEFT", 8, 0)
        txt:SetPoint("RIGHT", dd, "RIGHT", -22, 0)
        txt:SetJustifyH("LEFT")
        txt:SetTextColor(0.90, 0.85, 0.75)
    end

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

local function StyleModernPillButton(btn, text, isGold)
    if not btn then return btn end
    if type(text) == "boolean" and isGold == nil then
        isGold = text
        text = nil
    end
    StripBlizzardTextures(btn)
    btn._isGold = isGold
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        if isGold then
            btn:SetBackdropColor(0.40, 0.30, 0.10, 0.95)
            btn:SetBackdropBorderColor(0.85, 0.70, 0.20, 1.0)
        else
            btn:SetBackdropColor(0.13, 0.12, 0.10, 0.95)
            btn:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.85)
        end
    end
    local fs = btn.GetFontString and btn:GetFontString()
    if not fs and btn.CreateFontString and btn.SetFontString then
        fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        btn:SetFontString(fs)
    end
    if fs and fs.SetTextColor then
        if isGold then
            fs:SetTextColor(1.0, 0.92, 0.45)
        else
            fs:SetTextColor(0.85, 0.80, 0.70)
        end
    end
    if (type(text) == "string" or type(text) == "number") and btn.SetText then btn:SetText(text) end
    if not btn._hookedPill and btn.HookScript then
        btn._hookedPill = true
        btn:HookScript("OnEnter", function(self)
            StripBlizzardTextures(self)
            if self.SetBackdropColor then
                if self._isGold then
                    self:SetBackdropColor(0.55, 0.42, 0.12, 1.0)
                    self:SetBackdropBorderColor(1.0, 0.88, 0.35, 1.0)
                else
                    self:SetBackdropColor(0.22, 0.19, 0.14, 0.95)
                    self:SetBackdropBorderColor(0.80, 0.65, 0.25, 0.95)
                end
            end
            local s = self.GetFontString and self:GetFontString()
            if s and s.SetTextColor then s:SetTextColor(1.0, 0.95, 0.60) end
        end)
        btn:HookScript("OnLeave", function(self)
            StripBlizzardTextures(self)
            if self.SetBackdropColor then
                if self._isGold then
                    self:SetBackdropColor(0.40, 0.30, 0.10, 0.95)
                    self:SetBackdropBorderColor(0.85, 0.70, 0.20, 1.0)
                else
                    self:SetBackdropColor(0.13, 0.12, 0.10, 0.95)
                    self:SetBackdropBorderColor(0.38, 0.32, 0.22, 0.85)
                end
            end
            local s = self.GetFontString and self:GetFontString()
            if s and s.SetTextColor then
                if self._isGold then
                    s:SetTextColor(1.0, 0.92, 0.45)
                else
                    s:SetTextColor(0.85, 0.80, 0.70)
                end
            end
        end)
    end
    return btn
end

local function StyleModernSubTab(btn, isActive, text)
    if not btn then return end
    StripBlizzardTextures(btn)
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        if isActive then
            btn:SetBackdropColor(0.38, 0.28, 0.10, 0.98)
            btn:SetBackdropBorderColor(1.0, 0.85, 0.20, 1.0)
        else
            btn:SetBackdropColor(0.12, 0.10, 0.08, 0.92)
            btn:SetBackdropBorderColor(0.32, 0.26, 0.18, 0.85)
        end
    end
    local fs = btn.GetFontString and btn:GetFontString()
    if not fs and btn.CreateFontString and btn.SetFontString then
        fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        btn:SetFontString(fs)
    end
    if fs and fs.SetTextColor then
        if isActive then
            fs:SetTextColor(1.0, 0.95, 0.70)
        else
            fs:SetTextColor(0.75, 0.70, 0.60)
        end
    end
    if text and btn.SetText then btn:SetText(text) end
    btn._isActive = isActive
    if not btn._hookedTab and btn.HookScript then
        btn._hookedTab = true
        btn:HookScript("OnEnter", function(self)
            StripBlizzardTextures(self)
            if not self._isActive then
                if self.SetBackdropColor then
                    self:SetBackdropColor(0.20, 0.17, 0.12, 0.95)
                    self:SetBackdropBorderColor(0.70, 0.58, 0.25, 0.95)
                end
                local s = self.GetFontString and self:GetFontString()
                if s and s.SetTextColor then s:SetTextColor(1.0, 0.90, 0.60) end
            end
        end)
        btn:HookScript("OnLeave", function(self)
            StripBlizzardTextures(self)
            if not self._isActive then
                if self.SetBackdropColor then
                    self:SetBackdropColor(0.12, 0.10, 0.08, 0.92)
                    self:SetBackdropBorderColor(0.32, 0.26, 0.18, 0.85)
                end
                local s = self.GetFontString and self:GetFontString()
                if s and s.SetTextColor then s:SetTextColor(0.75, 0.70, 0.60) end
            end
        end)
    end
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
    local btnTabWatchlist = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate,BackdropTemplate")
    btnTabWatchlist:SetSize(134, 24)
    btnTabWatchlist:SetPoint("TOPLEFT", panel, "TOPLEFT", isEmbedded and 64 or 76, isEmbedded and -8 or -34)
    btnTabWatchlist:SetText("Tracked Watchlist")

    local btnTabHistory = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate,BackdropTemplate")
    btnTabHistory:SetSize(134, 24)
    btnTabHistory:SetPoint("LEFT", btnTabWatchlist, "RIGHT", 6, 0)
    btnTabHistory:SetText("Alert History")

    local btnTestSound = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate,BackdropTemplate")
    btnTestSound:SetSize(84, 22)
    btnTestSound:SetPoint("TOPRIGHT", panel, "TOPRIGHT", isEmbedded and -8 or -26, isEmbedded and -8 or -34)
    btnTestSound:SetText("Test Sound")
    StyleModernPillButton(btnTestSound, "Test Sound")
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
        local unread = tonumber(MarketSync.NotificationUnreadCount) or 0
        local historyText = unread > 0 and string.format("Alert History (|cffffd700%d|r)", unread) or "Alert History"

        if panel.currentView == "watchlist" then
            StyleModernSubTab(btnTabWatchlist, true, "Tracked Watchlist")
            StyleModernSubTab(btnTabHistory, false, historyText)
        else
            StyleModernSubTab(btnTabWatchlist, false, "Tracked Watchlist")
            StyleModernSubTab(btnTabHistory, true, historyText)
        end
    end
    UpdateSubTabButtons()

    btnTabWatchlist:SetScript("OnClick", function()
        if panel.currentView == "watchlist" then return end
        panel.currentView = "watchlist"
        UpdateSubTabButtons()
        RefreshView()
    end)

    btnTabHistory:SetScript("OnClick", function()
        if panel.currentView == "history" then return end
        panel.currentView = "history"
        UpdateSubTabButtons()
        RefreshView()
    end)

    -- =========================================================
    -- LEFT COLUMN: ALERT EDITOR (BOX 1 - Height 216)
    -- =========================================================
    local editorBox
    if isEmbedded then
        editorBox = CreateBox(panel, LEFT_X, -34, LEFT_W, 252)
    else
        editorBox = CreateBox(panel, LEFT_X, TOP_Y, LEFT_W, 252)
    end

    local editorTitle = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editorTitle:SetPoint("TOPLEFT", 10, -7)
    editorTitle:SetText("|cffffd700Alert Editor|r")
    local parentPrefix = (parent and parent.GetName and parent:GetName()) or "MarketSync"
    -- 34x34 Item Drop Slot
    local itemSlot = CreateFrame("Button", parentPrefix .. "ItemDropSlot", editorBox)
    itemSlot:SetSize(34, 34)
    itemSlot:SetPoint("TOPLEFT", 10, -24)

    local itemSlotIcon = itemSlot:CreateTexture(nil, "BORDER")
    itemSlotIcon:SetAllPoints()
    itemSlotIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local itemSlotBorder = itemSlot:CreateTexture(nil, "OVERLAY")
    itemSlotBorder:SetSize(38, 38)
    itemSlotBorder:SetPoint("CENTER")
    itemSlotBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    itemSlotBorder:SetBlendMode("ADD")
    itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.6)

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
    targetLabel:SetPoint("TOPLEFT", 10, -62)
    targetLabel:SetText("Item Name or ID:")

    local targetBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    targetBox:SetSize(LEFT_W - 20, 20)
    targetBox:SetPoint("TOPLEFT", 10, -76)
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

    -- Threshold Input & Preset Buttons (Gold, Silver, Bronze/Copper)
    local threshLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    threshLabel:SetPoint("TOPLEFT", 10, -100)
    threshLabel:SetText("Alert Below:")

    local goldBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    goldBox:SetSize(40, 20)
    goldBox:SetPoint("TOPLEFT", 10, -116)
    goldBox:SetAutoFocus(false)
    goldBox:SetNumeric(true)
    if goldBox.SetMaxLetters then goldBox:SetMaxLetters(7) end
    goldBox:SetText("0")

    local goldLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    goldLabel:SetPoint("LEFT", goldBox, "RIGHT", 2, 0)
    goldLabel:SetText("|cffffd700g|r")

    local silverBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    silverBox:SetSize(24, 20)
    silverBox:SetPoint("LEFT", goldLabel, "RIGHT", 4, 0)
    silverBox:SetAutoFocus(false)
    silverBox:SetNumeric(true)
    if silverBox.SetMaxLetters then silverBox:SetMaxLetters(2) end
    silverBox:SetText("0")

    local silverLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    silverLabel:SetPoint("LEFT", silverBox, "RIGHT", 2, 0)
    silverLabel:SetText("|cffc0c0c0s|r")

    local copperBox = CreateFrame("EditBox", nil, editorBox, "InputBoxTemplate")
    copperBox:SetSize(24, 20)
    copperBox:SetPoint("LEFT", silverLabel, "RIGHT", 4, 0)
    copperBox:SetAutoFocus(false)
    copperBox:SetNumeric(true)
    if copperBox.SetMaxLetters then copperBox:SetMaxLetters(2) end
    copperBox:SetText("0")

    local copperLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    copperLabel:SetPoint("LEFT", copperBox, "RIGHT", 2, 0)
    copperLabel:SetText("|cffeda55fc|r")

    goldBox:SetScript("OnTabPressed", function() silverBox:SetFocus() end)
    silverBox:SetScript("OnTabPressed", function() copperBox:SetFocus() end)
    copperBox:SetScript("OnTabPressed", function() goldBox:SetFocus() end)

    local function GetThresholdCopper()
        local g = tonumber(goldBox:GetText()) or 0
        local s = tonumber(silverBox:GetText()) or 0
        local c = tonumber(copperBox:GetText()) or 0
        return (g * 10000) + (s * 100) + c
    end
    panel.GetThresholdCopper = GetThresholdCopper

    local function SetThresholdCopper(copper)
        local c = math.max(0, tonumber(copper) or 0)
        local g = math.floor(c / 10000)
        local s = math.floor((c % 10000) / 100)
        local cop = c % 100
        goldBox:SetText(tostring(g))
        silverBox:SetText(tostring(s))
        copperBox:SetText(tostring(cop))
    end
    panel.SetThresholdCopper = SetThresholdCopper

    local btnUndercut = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnUndercut:SetSize(48, 20)
    btnUndercut:SetPoint("TOPLEFT", editorBox, "TOPLEFT", 10, -140)
    btnUndercut:SetText("-10%")
    StyleModernPillButton(btnUndercut, "-10%")

    local btnMarket = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnMarket:SetSize(52, 20)
    btnMarket:SetPoint("LEFT", btnUndercut, "RIGHT", 6, 0)
    btnMarket:SetText("Market")
    StyleModernPillButton(btnMarket, "Market")

    local function ApplyThresholdPreset(multiplier)
        local mp = panel.editorMarketPrice or 0
        if mp <= 0 then
            local target = panel.editorItemLink or panel.editorItemID or targetBox:GetText()
            if target and target ~= "" then
                mp = (MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(target)) or 0
                if mp > 0 then
                    panel.editorMarketPrice = mp
                    itemSlotMarket:SetText("Market: " .. FormatMoneyColored(mp))
                end
            end
        end

        if mp > 0 then
            local targetCopper = math.max(0, math.floor(mp * multiplier))
            SetThresholdCopper(targetCopper)
        else
            local cur = GetThresholdCopper()
            if cur > 0 and multiplier < 1.0 then
                local targetCopper = math.max(0, math.floor(cur * multiplier))
                SetThresholdCopper(targetCopper)
            end
        end
    end

    local function RefreshUndercutButtons()
        local pct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        btnUndercut:SetText("-" .. tostring(pct) .. "%")
    end
    panel.RefreshUndercutButtons = RefreshUndercutButtons

    btnUndercut:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local pct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        GameTooltip:SetText(string.format("Set threshold to %d%% below market price.", pct), 1, 1, 1)
        GameTooltip:AddLine("Configure default percentage in Settings (Beta section).", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btnUndercut:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btnUndercut:SetScript("OnClick", function()
        local pct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        ApplyThresholdPreset(math.max(0, 1 - (pct / 100)))
    end)
    btnMarket:SetScript("OnClick", function() ApplyThresholdPreset(1.0) end)

    -- Dedicated Scope Row
    local scopeLabel = editorBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", 10, -166)
    scopeLabel:SetText("Scope:")

    local scopeDropdown = BuildScopeDropdown(
        parentPrefix .. "NotificationsScopeDropdown",
        editorBox,
        LEFT_W - 68,
        function() return panel.editorScope end,
        function(v) panel.editorScope = v end
    )
    scopeDropdown:SetPoint("LEFT", scopeLabel, "RIGHT", 6, 0)

    -- Urgent Checkbox
    local urgentCheck = CreateFrame("CheckButton", nil, editorBox, "UICheckButtonTemplate")
    urgentCheck:SetSize(18, 18)
    urgentCheck:SetPoint("TOPLEFT", 10, -194)
    local urgentText = urgentCheck.text or urgentCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    urgentCheck.text = urgentText
    urgentText:SetText("Urgent (Raid Warning)")
    urgentText:ClearAllPoints()
    urgentText:SetPoint("LEFT", urgentCheck, "RIGHT", 4, 0)
    urgentCheck:SetChecked(false)

    -- Action Buttons (dynamically sized to never spill over LEFT_W - 20)
    local saveW = isEmbedded and 100 or 108
    local clearW = isEmbedded and 50 or 56
    local btnSave = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnSave:SetSize(saveW, 22)
    btnSave:SetPoint("TOPLEFT", 10, -220)
    btnSave:SetText("Add Alert")
    StyleModernPillButton(btnSave, "Add Alert", true)

    local btnClear = CreateFrame("Button", nil, editorBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnClear:SetSize(clearW, 22)
    btnClear:SetPoint("LEFT", btnSave, "RIGHT", 6, 0)
    btnClear:SetText("Clear")
    StyleModernPillButton(btnClear, "Clear")

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
    -- LEFT COLUMN: PREFERRED LIST IMPORT (BOX 2)
    -- =========================================================
    local importBox
    if isEmbedded then
        importBox = CreateBox(panel, LEFT_X, -292, LEFT_W, 178)
        importBox:SetWidth(LEFT_W)
        importBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_X, 8)
    else
        importBox = CreateBox(panel, LEFT_X, TOP_Y - 258, LEFT_W, 118)
    end

    local importTitle = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importTitle:SetPoint("TOPLEFT", 10, -7)
    importTitle:SetText("|cffffd700Preferred List Import|r")

    local importDropdown = CreateFrame("Frame", parentPrefix .. "NotificationsImportDropdown", importBox, "UIDropDownMenuTemplate,BackdropTemplate")
    local ddWidth = LEFT_W - 20
    local innerWidth = math.max(40, ddWidth - 36)
    UIDropDownMenu_SetWidth(importDropdown, innerWidth)
    local ddLeft = _G[parentPrefix .. "NotificationsImportDropdownLeft"]
    local ddMid = _G[parentPrefix .. "NotificationsImportDropdownMiddle"]
    local ddRight = _G[parentPrefix .. "NotificationsImportDropdownRight"]
    if ddLeft then ddLeft:Hide() end
    if ddMid then ddMid:Hide() end
    if ddRight then ddRight:Hide() end
    importDropdown:SetSize(ddWidth, 22)
    importDropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    importDropdown:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    importDropdown:SetBackdropBorderColor(0.32, 0.28, 0.20, 0.85)
    local ddBtn = _G[parentPrefix .. "NotificationsImportDropdownButton"]
    if ddBtn then
        ddBtn:ClearAllPoints()
        ddBtn:SetPoint("RIGHT", importDropdown, "RIGHT", -2, 0)
    end
    local ddTxt = _G[parentPrefix .. "NotificationsImportDropdownText"]
    if ddTxt then
        ddTxt:ClearAllPoints()
        ddTxt:SetPoint("LEFT", importDropdown, "LEFT", 8, 0)
        ddTxt:SetPoint("RIGHT", importDropdown, "RIGHT", -22, 0)
        ddTxt:SetJustifyH("LEFT")
        ddTxt:SetTextColor(0.90, 0.85, 0.75)
    end
    importDropdown:SetPoint("TOPLEFT", importBox, "TOPLEFT", 10, -25)

    local discountLabel = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    discountLabel:SetPoint("TOPLEFT", 10, -54)
    discountLabel:SetText("Discount:")

    local impBtnUndercut = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate,BackdropTemplate")
    impBtnUndercut:SetSize(46, 20)
    impBtnUndercut:SetPoint("LEFT", discountLabel, "RIGHT", 6, 0)
    impBtnUndercut:SetText("-10%")
    StyleModernPillButton(impBtnUndercut, "-10%")

    local impBtnMarket = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate,BackdropTemplate")
    impBtnMarket:SetSize(48, 20)
    impBtnMarket:SetPoint("LEFT", impBtnUndercut, "RIGHT", 4, 0)
    impBtnMarket:SetText("Market")
    StyleModernPillButton(impBtnMarket, "Market")

    local function HighlightImportDiscount(pct)
        panel.importDiscountPct = pct
        local userPct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        impBtnUndercut:SetAlpha(pct == userPct and 1.0 or 0.6)
        impBtnMarket:SetAlpha(pct == 0 and 1.0 or 0.6)
    end

    local function RefreshImportUndercutButton()
        local userPct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        impBtnUndercut:SetText("-" .. tostring(userPct) .. "%")
    end
    panel.RefreshImportUndercutButton = RefreshImportUndercutButton

    impBtnUndercut:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local pct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        GameTooltip:SetText(string.format("Import with %d%% discount below market price.", pct), 1, 1, 1)
        GameTooltip:AddLine("Configure default percentage in Settings (Beta section).", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    impBtnUndercut:SetScript("OnLeave", function() GameTooltip:Hide() end)

    impBtnUndercut:SetScript("OnClick", function()
        local userPct = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        HighlightImportDiscount(userPct)
    end)
    impBtnMarket:SetScript("OnClick", function() HighlightImportDiscount(0) end)
    HighlightImportDiscount(10)

    local btnDoImport = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnDoImport:SetSize(LEFT_W - 20, 22)
    btnDoImport:SetPoint("TOPLEFT", 10, -80)
    btnDoImport:SetText("Import to Watchlist")
    StyleModernPillButton(btnDoImport, "Import to Watchlist", true)

    local importStatusText = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importStatusText:SetPoint("TOPLEFT", 10, -104)
    importStatusText:SetText("")

    local importDesc = importBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    if isEmbedded then
        importDesc:SetPoint("TOPLEFT", 10, -106)
        importDesc:SetPoint("BOTTOMRIGHT", -10, 6)
    else
        importDesc:SetPoint("TOPLEFT", 10, -104)
        importDesc:SetPoint("BOTTOMRIGHT", -10, 6)
    end
    importDesc:SetJustifyH("LEFT")
    if importDesc.SetJustifyV then
        importDesc:SetJustifyV("TOP")
    end
    importDesc:SetText("|cff777777Populates watchlist price triggers from your favorite lists with configured discounts below market price.|r")

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

    local tableScrollBar
    if MarketSync.CreateModernTableScrollBar and rightBox then
        tableScrollBar = MarketSync.CreateModernTableScrollBar(panel, rightBox, function(newPage)
            if panel.currentView == "watchlist" then
                panel.watchlistPage = newPage
                if RefreshWatchlistTable then RefreshWatchlistTable() end
            else
                panel.historyPage = newPage
                if RefreshHistoryTable then RefreshHistoryTable() end
            end
        end, 8, -28, 28)
        panel.tableScrollBar = tableScrollBar
        tableScrollBar:AttachMouseWheel(rightBox)
        tableScrollBar:AttachMouseWheel(panel)
    end

    -- Top Toolbar inside rightBox
    local searchBox = CreateFrame("EditBox", nil, rightBox, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPLEFT", 10, -7)
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
    clearSearchText:SetText("X")
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
    local btnMarkAllRead = CreateFrame("Button", nil, rightBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnMarkAllRead:SetSize(104, 22)
    btnMarkAllRead:SetPoint("TOPLEFT", 10, -6)
    btnMarkAllRead:SetText("Mark All Read")
    StyleModernPillButton(btnMarkAllRead, "Mark All Read")
    btnMarkAllRead:SetScript("OnClick", function()
        if MarketSync.MarkAllNotificationsRead then
            MarketSync.MarkAllNotificationsRead()
        end
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end)

    local btnClearHistory = CreateFrame("Button", nil, rightBox, "UIPanelButtonTemplate,BackdropTemplate")
    btnClearHistory:SetSize(96, 22)
    btnClearHistory:SetPoint("LEFT", btnMarkAllRead, "RIGHT", 6, 0)
    btnClearHistory:SetText("Clear History")
    StyleModernPillButton(btnClearHistory, "Clear History")
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
    wHdrThresh:SetPoint("TOPLEFT", isEmbedded and 245 or 275, -34)
    wHdrThresh:SetText("Threshold")

    local wHdrScope = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrScope:SetPoint("TOPLEFT", isEmbedded and 360 or 395, -34)
    wHdrScope:SetText("Scope")

    local wHdrActive = rightBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    wHdrActive:SetPoint("TOPLEFT", isEmbedded and 445 or 480, -34)
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
        wName:SetSize(isEmbedded and 205 or 235, 20)
        wName:SetJustifyH("LEFT")
        row.wName = wName

        local wThresh = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wThresh:SetPoint("LEFT", isEmbedded and 241 or 271, 0)
        wThresh:SetSize(isEmbedded and 105 or 110, 20)
        wThresh:SetJustifyH("LEFT")
        row.wThresh = wThresh

        local wScope = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wScope:SetPoint("LEFT", isEmbedded and 356 or 391, 0)
        wScope:SetSize(isEmbedded and 75 or 75, 20)
        wScope:SetJustifyH("LEFT")
        row.wScope = wScope

        local wCooldown = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wCooldown:Hide()
        row.wCooldown = wCooldown

        local wActiveCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        wActiveCheck:SetSize(18, 18)
        wActiveCheck:SetPoint("LEFT", isEmbedded and 447 or 482, 0)
        row.wActiveCheck = wActiveCheck

        local wDelBtn = CreateFrame("Button", nil, row)
        wDelBtn:SetSize(18, 18)
        wDelBtn:SetPoint("LEFT", isEmbedded and 505 or 540, 0)
        local delText = wDelBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        delText:SetPoint("CENTER")
        delText:SetText("|cffff5555X|r")
        wDelBtn:SetScript("OnEnter", function() delText:SetText("|cffff2222X|r") end)
        wDelBtn:SetScript("OnLeave", function() delText:SetText("|cffff5555X|r") end)
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

        -- Row click handler (Left click: load into editor; Right click: context menu)
        local function HandleRowClick(self, button)
            if button == "RightButton" then
                if row.request then
                    local req = row.request
                    local customActions = {
                        {
                            text = "Edit in Alert Form",
                            func = function()
                                panel.editorEditingID = req.id
                                btnSave:SetText("Update Alert")
                                SetEditorItem(req.matchValue or req.displayName or row.itemID)
                                SetThresholdCopper(req.thresholdCopper)
                                panel.editorScope = req.scope or "all"
                                UIDropDownMenu_SetText(scopeDropdown, ScopeLabel(panel.editorScope))
                                urgentCheck:SetChecked(req.urgent == true)
                            end
                        },
                        {
                            text = (req.enabled ~= false) and "Disable Alert" or "Enable Alert",
                            func = function()
                                if MarketSync.ToggleNotificationRequest then
                                    MarketSync.ToggleNotificationRequest(req.id)
                                else
                                    req.enabled = not (req.enabled ~= false)
                                end
                                RefreshView()
                            end
                        },
                        {
                            text = "Delete Alert",
                            func = function()
                                if MarketSync.DeleteNotificationRequest then
                                    MarketSync.DeleteNotificationRequest(req.id)
                                    RefreshView()
                                end
                            end
                        },
                    }
                    if MarketSync.ShowItemContextMenu then
                        MarketSync.ShowItemContextMenu(row, {
                            itemID = row.itemID,
                            itemLink = row.itemLink,
                            itemName = req.displayName or row.itemName,
                            price = req.thresholdCopper,
                            customActions = customActions,
                        })
                    end
                elseif row.historyEntry then
                    local h = row.historyEntry
                    local customActions = {
                        {
                            text = "Load into Alert Form",
                            func = function()
                                SetEditorItem(h.itemLink or h.itemID or h.itemName)
                                SetThresholdCopper(h.threshold)
                            end
                        }
                    }
                    if MarketSync.ShowItemContextMenu then
                        MarketSync.ShowItemContextMenu(row, {
                            itemID = row.itemID,
                            itemLink = row.itemLink or h.itemLink,
                            itemName = h.itemName or row.itemName,
                            price = h.price or h.threshold,
                            customActions = customActions,
                        })
                    end
                end
                return
            end

            -- Left click: load into editor
            if row.request then
                panel.editorEditingID = row.request.id
                btnSave:SetText("Update Alert")
                SetEditorItem(row.request.matchValue or row.request.displayName or row.itemID)
                SetThresholdCopper(row.request.thresholdCopper)
                panel.editorScope = row.request.scope or "all"
                UIDropDownMenu_SetText(scopeDropdown, ScopeLabel(panel.editorScope))
                urgentCheck:SetChecked(row.request.urgent == true)
            elseif row.historyEntry then
                SetEditorItem(row.historyEntry.itemLink or row.historyEntry.itemID or row.historyEntry.itemName)
                SetThresholdCopper(row.historyEntry.threshold)
            end
        end

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", HandleRowClick)
        iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        iconBtn:SetScript("OnClick", HandleRowClick)

        if tableScrollBar then
            tableScrollBar:AttachMouseWheel(row)
            tableScrollBar:AttachMouseWheel(iconBtn)
        end

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

    local btnPrev = CreateFrame("Button", nil, rightBox)
    btnPrev:SetSize(20, 20)
    btnPrev:SetPoint("BOTTOMRIGHT", -48, 6)
    btnPrev:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    btnPrev:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    btnPrev:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local pnt = btnPrev.GetNormalTexture and btnPrev:GetNormalTexture()
    if pnt and pnt.SetVertexColor then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end

    local btnNext = CreateFrame("Button", nil, rightBox)
    btnNext:SetSize(20, 20)
    btnNext:SetPoint("LEFT", btnPrev, "RIGHT", 4, 0)
    btnNext:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    btnNext:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    btnNext:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local nnt = btnNext.GetNormalTexture and btnNext:GetNormalTexture()
    if nnt and nnt.SetVertexColor then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) end

    local pageText = rightBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pageText:SetPoint("RIGHT", btnPrev, "LEFT", -8, 0)
    pageText:SetJustifyH("RIGHT")
    pageText:SetText("1 / 1")

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
            local curThresh = GetThresholdCopper()
            if curThresh == 0 then
                SetThresholdCopper(math.floor(marketPrice * 0.9))
            end
        else
            itemSlotMarket:SetText("Market: |cff888888--|r")
        end
    end
    panel.SetEditorItem = SetEditorItem

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
        SetThresholdCopper(0)
        panel.editorScope = "all"
        UIDropDownMenu_SetText(scopeDropdown, "All Scopes")
        if panel.RefreshUndercutButtons then panel.RefreshUndercutButtons() end
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
    targetBox:SetScript("OnEditFocusLost", function(self)
        local val = TrimText(self:GetText())
        if val ~= "" and not panel.editorItemID then
            SetEditorItem(val)
        end
    end)
    targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function OnCoinEnterPressed(self)
        self:ClearFocus()
        btnSave:Click()
    end
    goldBox:SetScript("OnEnterPressed", OnCoinEnterPressed)
    goldBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    silverBox:SetScript("OnEnterPressed", OnCoinEnterPressed)
    silverBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    copperBox:SetScript("OnEnterPressed", OnCoinEnterPressed)
    copperBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    btnSave:SetScript("OnClick", function()
        local rawTarget = TrimText(targetBox:GetText())
        if rawTarget == "" and not panel.editorItemID then
            SetStatus("Enter an item name or drop an item.", true)
            return
        end

        local threshCopper = GetThresholdCopper()
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
            cooldownSec = 3600,
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

        local hasPrev = panel.watchlistPage > 0
        local hasNext = panel.watchlistPage < maxPage
        btnPrev:SetEnabled(hasPrev)
        btnNext:SetEnabled(hasNext)
        local pnt = btnPrev.GetNormalTexture and btnPrev:GetNormalTexture()
        if pnt and pnt.SetVertexColor then
            if hasPrev then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else pnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        local nnt = btnNext.GetNormalTexture and btnNext:GetNormalTexture()
        if nnt and nnt.SetVertexColor then
            if hasNext then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else nnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        pageText:SetText(string.format("%d / %d", panel.watchlistPage + 1, math.max(1, maxPage + 1)))
        if tableScrollBar then
            tableScrollBar:Update(panel.watchlistPage, maxPage)
        end

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

                if row.wCooldown then row.wCooldown:Hide() end

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

        local hasPrev = panel.historyPage > 0
        local hasNext = panel.historyPage < maxPage
        btnPrev:SetEnabled(hasPrev)
        btnNext:SetEnabled(hasNext)
        local pnt = btnPrev.GetNormalTexture and btnPrev:GetNormalTexture()
        if pnt and pnt.SetVertexColor then
            if hasPrev then pnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else pnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        local nnt = btnNext.GetNormalTexture and btnNext:GetNormalTexture()
        if nnt and nnt.SetVertexColor then
            if hasNext then nnt:SetVertexColor(0.70, 0.65, 0.55, 0.90) else nnt:SetVertexColor(0.30, 0.28, 0.22, 0.45) end
        end
        pageText:SetText(string.format("%d / %d", panel.historyPage + 1, math.max(1, maxPage + 1)))
        if tableScrollBar then
            tableScrollBar:Update(panel.historyPage, maxPage)
        end

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
        if RefreshUndercutButtons then
            RefreshUndercutButtons()
        end
        if RefreshImportUndercutButton then
            RefreshImportUndercutButton()
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

function MarketSync.RefreshNotificationUndercutButtons()
    for _, p in ipairs(registeredNotificationPanels) do
        if p.RefreshUndercutButtons then p.RefreshUndercutButtons() end
        if p.RefreshImportUndercutButton then p.RefreshImportUndercutButton() end
    end
end

function MarketSync.OpenAlertEditorWithItem(itemRef, price)
    if AuctionFrame and AuctionFrame:IsShown() and MarketSync.AuctionHouse and MarketSync.AuctionHouse.SelectTab then
        MarketSync.AuctionHouse.SelectTab("alerts")
    elseif MarketSync.SelectMainFrameTab then
        if MarketSyncMainFrame and not MarketSyncMainFrame:IsShown() then
            MarketSyncMainFrame:Show()
        end
        MarketSync.SelectMainFrameTab(6)
    elseif MarketSync.ToggleNotificationsManager then
        MarketSync.ToggleNotificationsManager()
    end

    for _, p in ipairs(registeredNotificationPanels) do
        if p and p.SetEditorItem then
            p.SetEditorItem(itemRef)
            if price and price > 0 and p.SetThresholdCopper then
                p.SetThresholdCopper(price)
            end
        end
    end
end
