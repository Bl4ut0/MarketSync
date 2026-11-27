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

local function CreateBox(parent, x, y, width, height, auctionSurface)
    if MarketSync and MarketSync.CreateModernInset then
        return MarketSync.CreateModernInset(parent, x, y, width, height, auctionSurface)
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
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 100, 22)
    local menu = CreateFrame("Frame", frameName, parent, "UIDropDownMenuTemplate")
    menu:Hide()
    button._menu = menu
    UIDropDownMenu_Initialize(menu, function(self, level)
        for _, opt in ipairs(SCOPE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.func = function()
                setValue(opt.value)
                button:SetText(opt.label .. "  |cFFFFD100v|r")
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    button:SetText(ScopeLabel(getValue()) .. "  |cFFFFD100v|r")
    button:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, menu, self, 0, 0)
    end)
    return button
end

local function SetDropdownLabel(button, label)
    button:SetText(tostring(label or "") .. "  |cFFFFD100v|r")
end

local function StyleModernPillButton(btn, text, isGold)
    if not btn then return btn end
    -- Use the same native button appearance and interactions as the sidecar.
    if (type(text) == "string" or type(text) == "number") and btn.SetText then btn:SetText(text) end
    return btn
end

local function StyleModernSubTab(btn, isActive, text)
    if not btn then return end
    if btn._marketSyncNativeSubTab then
        btn:SetText(text)
        if btn.SetSelected then
            btn:SetSelected(isActive)
        elseif isActive and PanelTemplates_SelectTab then
            PanelTemplates_SelectTab(btn)
        elseif not isActive and PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(btn)
        end
        return
    end
    StripBlizzardTextures(btn)
    if btn.SetBackdrop then
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        if isActive then
            btn:SetBackdropColor(MarketSync.GetThemeColor("hover"))
            btn:SetBackdropBorderColor(1.0, 0.85, 0.20, 1.0)
        else
            btn:SetBackdropColor(MarketSync.GetThemeColor("header"))
            btn:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))
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
                    self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
                    self:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
                end
                local s = self.GetFontString and self:GetFontString()
                if s and s.SetTextColor then s:SetTextColor(1.0, 0.90, 0.60) end
            end
        end)
        btn:HookScript("OnLeave", function(self)
            StripBlizzardTextures(self)
            if not self._isActive then
                if self.SetBackdropColor then
                    self:SetBackdropColor(MarketSync.GetThemeColor("header"))
                    self:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))
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
local bulkImportPopup
local BULK_ROWS_PER_PAGE = 6

local function ShowBulkImportPopup(listLabel, candidates, onSaved)
    if not bulkImportPopup then
        local popup = CreateFrame("Frame", "MarketSyncBulkAlertImportFrame", UIParent, "BackdropTemplate")
        popup:SetSize(820, 490)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 25)
        popup:SetFrameStrata("DIALOG")
        popup:SetFrameLevel(200)
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        popup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        popup:SetBackdropColor(MarketSync.GetThemeColor("dialog"))
        popup:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
        if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(popup) end

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", popup, "TOP", 0, -14)
        title:SetText("Mass Import Price Alerts")
        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
        close:SetScript("OnClick", function() popup:Hide() end)
        if MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
            and MarketSync.Theme and MarketSync.Theme.DecorateWarcraftWindow then
            popup.TitleText, popup.CloseButton = title, close
            MarketSync.Theme.DecorateWarcraftWindow(popup, "Interface\\Icons\\INV_Misc_Book_09", "Mass Import Price Alerts")
        end

        popup.listText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        popup.listText:SetPoint("TOPLEFT", popup.portrait and 70 or 18, -38)
        popup.listText:SetPoint("RIGHT", popup, "RIGHT", -215, 0)
        popup.listText:SetJustifyH("LEFT")

        local function PresetAll(multiplier)
            for _, item in ipairs(popup.items or {}) do
                if item.marketPrice and item.marketPrice > 0 then
                    item.thresholdCopper = math.floor(item.marketPrice * multiplier)
                end
            end
            popup:RefreshRows()
        end
        local undercut = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        undercut:SetSize(92, 22)
        undercut:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -108, -34)
        undercut:SetText("Discount All")
        undercut:SetScript("OnClick", function()
            local pct = (MarketSyncDB and tonumber(MarketSyncDB.AlertUndercutPct)) or 10
            PresetAll(math.max(0, 1 - pct / 100))
        end)
        local market = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        market:SetSize(92, 22)
        market:SetPoint("LEFT", undercut, "RIGHT", 4, 0)
        market:SetText("Market All")
        market:SetScript("OnClick", function() PresetAll(1) end)

        local headers = {
            { "Import / Item", 20 }, { "Market", 268 }, { "Alert Below (g / s / c)", 365 },
            { "Scope", 514 }, { "Urgent", 663 }, { "Enabled", 746 },
        }
        for _, spec in ipairs(headers) do
            local label = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", popup, "TOPLEFT", spec[2], -73)
            label:SetText(spec[1])
        end

        popup.rows = {}
        for i = 1, BULK_ROWS_PER_PAGE do
            local row = CreateFrame("Frame", nil, popup)
            row:SetSize(784, 49)
            row:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -94 - (i - 1) * 50)
            if i % 2 == 0 then
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints()
                stripe:SetColorTexture(MarketSync.GetThemeColor("stripe", 0.035))
            end

            row.select = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.select:SetSize(20, 20)
            row.select:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", row, "LEFT", 25, 0)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 52, 0)
            row.name:SetWidth(184)
            row.name:SetJustifyH("LEFT")
            if row.name.SetWordWrap then row.name:SetWordWrap(false) end
            row.market = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.market:SetPoint("LEFT", row, "LEFT", 250, 0)
            row.market:SetWidth(88)
            row.market:SetJustifyH("LEFT")

            local function CoinBox(x, width, suffix)
                local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
                box:SetSize(width, 20)
                box:SetPoint("LEFT", row, "LEFT", x, 0)
                box:SetAutoFocus(false)
                box:SetNumeric(true)
                local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("LEFT", box, "RIGHT", 2, 0)
                label:SetText(suffix)
                return box
            end
            row.gold = CoinBox(345, 44, "g")
            row.silver = CoinBox(400, 28, "s")
            row.copper = CoinBox(440, 28, "c")
            local function SaveThreshold()
                if popup.updatingRows or not row.item then return end
                local g = tonumber(row.gold:GetText()) or 0
                local s = tonumber(row.silver:GetText()) or 0
                local c = tonumber(row.copper:GetText()) or 0
                row.item.thresholdCopper = math.floor(g * 10000 + s * 100 + c)
            end
            for _, box in ipairs({ row.gold, row.silver, row.copper }) do
                box:SetScript("OnTextChanged", SaveThreshold)
                box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); SaveThreshold() end)
                box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            end

            row.scope = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.scope:SetSize(134, 22)
            row.scope:SetPoint("LEFT", row, "LEFT", 490, 0)
            local scopeMenu = CreateFrame("Frame", "MarketSyncBulkAlertScope" .. i, row, "UIDropDownMenuTemplate")
            scopeMenu:Hide()
            UIDropDownMenu_Initialize(scopeMenu, function(_, level)
                for _, option in ipairs(SCOPE_OPTIONS) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = option.label
                    info.checked = row.item and row.item.scope == option.value
                    info.func = function()
                        if row.item then row.item.scope = option.value end
                        SetDropdownLabel(row.scope, option.label)
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            row.scope:SetScript("OnClick", function(self)
                ToggleDropDownMenu(1, nil, scopeMenu, self, 0, 0)
            end)
            row.urgent = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.urgent:SetSize(20, 20)
            row.urgent:SetPoint("LEFT", row, "LEFT", 644, 0)
            row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.enabled:SetSize(20, 20)
            row.enabled:SetPoint("LEFT", row, "LEFT", 726, 0)
            row.select:SetScript("OnClick", function(self)
                if row.item then row.item.selected = self:GetChecked() and true or false end
            end)
            row.urgent:SetScript("OnClick", function(self)
                if row.item then row.item.urgent = self:GetChecked() and true or false end
            end)
            row.enabled:SetScript("OnClick", function(self)
                if row.item then row.item.enabled = self:GetChecked() and true or false end
            end)
            popup.rows[i] = row
        end

        popup.pageText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        popup.pageText:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 82, 49)
        local prev = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        prev:SetSize(52, 22)
        prev:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 18, 42)
        prev:SetText("< Prev")
        prev:SetScript("OnClick", function() popup.page = math.max(0, popup.page - 1); popup:RefreshRows() end)
        local next = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        next:SetSize(52, 22)
        next:SetPoint("LEFT", popup.pageText, "RIGHT", 8, -1)
        next:SetText("Next >")
        next:SetScript("OnClick", function()
            popup.page = math.min(math.max(0, math.ceil(#popup.items / BULK_ROWS_PER_PAGE) - 1), popup.page + 1)
            popup:RefreshRows()
        end)
        popup.prevButton, popup.nextButton = prev, next
        popup.status = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        popup.status:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 18, 17)
        popup.status:SetPoint("RIGHT", popup, "RIGHT", -240, 0)
        popup.status:SetJustifyH("LEFT")
        local cancel = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        cancel:SetSize(82, 24)
        cancel:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 12)
        cancel:SetText("Cancel")
        cancel:SetScript("OnClick", function() popup:Hide() end)
        local save = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        save:SetSize(140, 24)
        save:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
        save:SetText("Import Selected")
        save:SetScript("OnClick", function()
            local selected = {}
            for _, item in ipairs(popup.items or {}) do
                if item.selected then
                    if not item.thresholdCopper or item.thresholdCopper <= 0 then
                        popup.status:SetText("|cffff4444Set a price above 0 for " .. item.displayName .. ".|r")
                        return
                    end
                    selected[#selected + 1] = item
                end
            end
            if #selected == 0 then
                popup.status:SetText("|cffff4444Select at least one priced item.|r")
                return
            end
            local imported = 0
            for _, item in ipairs(selected) do
                local request = MarketSync.UpsertNotificationRequest({
                    id = item.requestID,
                    matchType = item.matchType,
                    matchValue = item.matchValue,
                    displayName = item.displayName,
                    thresholdCopper = item.thresholdCopper,
                    scope = item.scope,
                    variantMode = item.variantMode or "any_suffix",
                    cooldownSec = 3600,
                    urgent = item.urgent,
                    enabled = item.enabled,
                    quantityHint = item.quantityHint,
                    importSource = item.listName,
                })
                if request then imported = imported + 1 end
            end
            popup:Hide()
            if popup.onSaved then popup.onSaved(imported) end
        end)

        function popup:RefreshRows()
            local total = #(self.items or {})
            local maxPage = math.max(0, math.ceil(total / BULK_ROWS_PER_PAGE) - 1)
            self.page = math.min(math.max(0, self.page or 0), maxPage)
            self.updatingRows = true
            for i, row in ipairs(self.rows) do
                local item = self.items[self.page * BULK_ROWS_PER_PAGE + i]
                row.item = item
                if item then
                    row:Show()
                    row.select:SetChecked(item.selected)
                    row.icon:SetTexture(SafeGetItemIcon(item.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local name = item.displayName or "Unknown item"
                    if #name > 29 then name = name:sub(1, 26) .. "..." end
                    row.name:SetText(name)
                    row.market:SetText(item.marketPrice and FormatMoneyColored(item.marketPrice) or "|cff888888Unknown|r")
                    local copper = math.max(0, math.floor(tonumber(item.thresholdCopper) or 0))
                    row.gold:SetText(tostring(math.floor(copper / 10000)))
                    row.silver:SetText(tostring(math.floor((copper % 10000) / 100)))
                    row.copper:SetText(tostring(copper % 100))
                    SetDropdownLabel(row.scope, ScopeLabel(item.scope))
                    row.urgent:SetChecked(item.urgent)
                    row.enabled:SetChecked(item.enabled)
                else
                    row:Hide()
                end
            end
            self.updatingRows = false
            local first = total > 0 and self.page * BULK_ROWS_PER_PAGE + 1 or 0
            self.pageText:SetText(string.format("%d-%d of %d", first, math.min(total, first + BULK_ROWS_PER_PAGE - 1), total))
            self.prevButton:SetEnabled(self.page > 0)
            self.nextButton:SetEnabled(self.page < maxPage)
        end
        bulkImportPopup = popup
        popup:Hide()
    end

    bulkImportPopup.items = candidates
    bulkImportPopup.page = 0
    bulkImportPopup.onSaved = onSaved
    bulkImportPopup.listText:SetText(string.format("List: %s  |  %d item(s)", listLabel, #candidates))
    bulkImportPopup.status:SetText("Review each alert; only checked rows are imported.")
    bulkImportPopup:RefreshRows()
    bulkImportPopup:Show()
end

MarketSync.ShowBulkAlertImportPopup = ShowBulkImportPopup

-- =============================================================
-- ALERTS PAGE (Workbench layout)
-- Left rail: settings for the open tab, the alert editor, or details of a
-- history entry. Right: the watchlist or alert history table.
-- =============================================================
local RAIL_W = 176
local RAIL_INNER_W = RAIL_W - 16

local function SetControlVisible(control, visible)
    if not control then return end
    if visible then control:Show() else control:Hide() end
end

local function Truncate(text, maxLen)
    local s = tostring(text or "")
    if #s <= maxLen then return s end
    return s:sub(1, math.max(1, maxLen - 3)) .. "..."
end

-- "4g 50s 20c", "4g50", "450s", "4.5" (gold) and "45000c" all work.
local function ParseMoneyText(text)
    local raw = TrimText(text):lower():gsub(",", ".")
    if raw == "" then return 0 end
    local g = tonumber(raw:match("([%d%.]+)%s*g")) or 0
    local s = tonumber(raw:match("([%d%.]+)%s*s")) or 0
    local c = tonumber(raw:match("([%d%.]+)%s*c")) or 0
    if not raw:find("[gsc]") then
        g = tonumber(raw) or 0
    end
    return math.max(0, math.floor(g * 10000 + s * 100 + c + 0.5))
end
MarketSync.ParseAlertMoneyText = ParseMoneyText

local function MoneyInputText(copper)
    local c = math.max(0, math.floor(tonumber(copper) or 0))
    local g, s, cc = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = cc .. "c" end
    return table.concat(parts, " ")
end

local function RailLabel(parent, y, text)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    label:SetText(text)
    return label
end

local function RailButton(parent, y, width, text, x)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or RAIL_INNER_W, 20)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 8, y)
    btn:SetText(text)
    return btn
end

local function SetActive(btn, active, label)
    btn:SetText(active and ("|cffffd700" .. label .. "|r") or label)
    if active then
        if btn.LockHighlight then btn:LockHighlight() end
    elseif btn.UnlockHighlight then
        btn:UnlockHighlight()
    end
end

local function AttachTip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SourceLabel(source)
    if not source or source == "" or source == "Personal" then return "My scan" end
    return "Guild sync | " .. tostring(source)
end

local function TimeLabel(epoch)
    local t = tonumber(epoch) or 0
    if t <= 0 then return "-" end
    local now = time()
    if date and date("%Y%m%d", t) == date("%Y%m%d", now) then return date("%H:%M", t) end
    if date and date("%Y%m%d", t) == date("%Y%m%d", now - 86400) then return "Yesterday" end
    return FormatRelativeTime(t)
end

local function RequestItemID(req)
    if req.matchType == "itemID" then return tonumber(req.matchValue) end
    if req.matchType == "dbKey" and MarketSync.ParseItemIDFromDBKey then
        return MarketSync.ParseItemIDFromDBKey(req.matchValue)
    end
    return nil
end

function MarketSync.CreateNotificationsPanel(parent)
    local isEmbedded = (parent ~= MarketSync.MainFrame)
    local isLegacyMain = not isEmbedded and MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local LEFT_X = isEmbedded and 10 or (isLegacyMain and 24 or 14)
    local RESULTS_X = LEFT_X + RAIL_W + 10
    local parentWidth = parent.GetWidth and parent:GetWidth() or 0
    local parentHeight = parent.GetHeight and parent:GetHeight() or 0
    local effectiveWidth = parentWidth > 0 and parentWidth or (isEmbedded and 780 or 850)
    local usableHeight = parentHeight > 0 and parentHeight or (isEmbedded and 440 or 430)
    local ROW_WIDTH = math.max(360, effectiveWidth - RESULTS_X - 14)
    local tabsY = isEmbedded and -8 or -34
    local bodyTop = isEmbedded and -36 or -62
    local bottomPadding = parent.MarketSyncNativeAuctionFooter and 0 or 8
    local FOOTER_H = 30
    local HEADER_H = 22
    local ROW_H = 28
    local numRowsPerPage = math.max(4, math.floor((usableHeight + bodyTop - bottomPadding - HEADER_H - FOOTER_H - 8) / ROW_H))

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
    panel.listFilter = nil
    panel.watchFilter = "all"     -- all | close | paused | noprice
    panel.historyFilter = "all"   -- all | unread | below | urgent
    panel.sourceFilter = "any"    -- any | mine | guild
    panel.editorItemID = nil
    panel.editorItemLink = nil
    panel.editorItemName = nil
    panel.editorMarketPrice = 0
    panel.editorScope = "all"
    panel.editorEditingID = nil
    panel.editorSoundID = nil
    panel.editorOrigin = nil
    panel.importSelectedList = "__ALL__"
    panel.importSelectedSource = nil

    local RefreshView, RefreshWatchlistTable, RefreshHistoryTable, RefreshImportDropdown
    local SetEditorItem, ClearEditorForm, ShowRail, ShowHistoryDetails
    local parentPrefix = (parent and parent.GetName and parent:GetName()) or "MarketSync"

    -- =========================================================
    -- HEADER: tabs and alert-wide switches
    -- =========================================================
    local function CreateAlertTab()
        local tab = MarketSync.CreateForeverAuctionControl
            and MarketSync.CreateForeverAuctionControl("Button", panel, "PanelTopTabButtonTemplate")
        if tab then
            tab._marketSyncNativeSubTab = true
            return tab
        end
        return CreateFrame("Button", nil, panel, "UIPanelButtonTemplate,BackdropTemplate")
    end

    local btnTabWatchlist = CreateAlertTab()
    btnTabWatchlist:SetSize(120, 24)
    btnTabWatchlist:SetPoint("TOPLEFT", panel, "TOPLEFT", isEmbedded and 64 or 76, tabsY)
    btnTabWatchlist:SetText("Watchlist")

    local btnTabHistory = CreateAlertTab()
    btnTabHistory:SetSize(134, 24)
    btnTabHistory:SetPoint("LEFT", btnTabWatchlist, "RIGHT", 6, 0)
    btnTabHistory:SetText("Alert History")

    local btnMute = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate,BackdropTemplate")
    btnMute:SetSize(64, 22)
    btnMute:SetPoint("TOPRIGHT", panel, "TOPRIGHT", isEmbedded and -8 or -26, tabsY)
    local btnTestSound = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate,BackdropTemplate")
    btnTestSound:SetSize(46, 22)
    btnTestSound:SetPoint("RIGHT", btnMute, "LEFT", -4, 0)
    btnTestSound:SetText("Test")
    AttachTip(btnTestSound, "Test sound", "Plays your alert sound once.")
    btnTestSound:SetScript("OnClick", function()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then MarketSync.PlayNotificationSound(soundID, true) end
    end)
    local function RefreshMute()
        btnMute:SetText(MarketSync.NotificationsMuted and "|cffff8a7aMuted|r" or "Mute")
    end
    btnMute:SetScript("OnClick", function()
        if MarketSync.ToggleNotificationMute then MarketSync.ToggleNotificationMute() end
        RefreshMute()
    end)
    AttachTip(btnMute, "Mute alerts", "Silences every alert until you log out or click again. Alerts are not recorded while muted.")
    RefreshMute()

    local function HeaderCheck(anchor, label, key, tipTitle, tipBody)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        local text = check.text or check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        check.text = text
        text:SetText(label)
        text:ClearAllPoints()
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
        check:SetPoint("RIGHT", anchor, "LEFT", -((text.GetStringWidth and text:GetStringWidth() or 40) + 10), 0)
        check:SetChecked(MarketSyncDB and MarketSyncDB[key] ~= false)
        check:SetScript("OnClick", function(self)
            if MarketSyncDB then MarketSyncDB[key] = self:GetChecked() and true or false end
            if key == "EnableNotificationSounds" and MarketSync.RefreshSettingsUI then pcall(MarketSync.RefreshSettingsUI) end
        end)
        AttachTip(check, tipTitle, tipBody)
        check.settingKey = key
        return check
    end
    local bannerCheck = HeaderCheck(btnTestSound, "Banner", "EnableRaidWarningAlerts", "On-screen banner",
        "Shows each alert in the raid-warning banner. Urgent alerts always show it.")
    local soundCheck = HeaderCheck(bannerCheck, "Sound", "EnableNotificationSounds", "Sound alerts",
        "Plays your alert sound. Pick the sound in Settings, or per alert in the editor.")
    panel.soundCheck, panel.bannerCheck = soundCheck, bannerCheck

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btnTabWatchlist, {
            name = "Watchlist", context = "Tab",
            description = "View and manage tracked item price alerts",
            getIndexInfo = function() return { index = 1, total = 2 } end,
        })
        MarketSync.SetAccessibility(btnTabHistory, {
            name = "Alert History", context = "Tab",
            description = "View history of triggered price alerts",
            getIndexInfo = function() return { index = 2, total = 2 } end,
        })
        MarketSync.SetAccessibility(btnTestSound, { name = "Test Sound", context = "Button",
            description = "Play notification alert test sound" })
        MarketSync.SetAccessibility(soundCheck, {
            name = "Sound Alerts",
            context = function(self) return self:GetChecked() and "Check Button, Checked" or "Check Button, Unchecked" end,
            description = "Toggle audio notifications for market alerts",
        })
    end

    local function UpdateSubTabButtons()
        local unread = tonumber(MarketSync.NotificationUnreadCount) or 0
        local historyText = unread > 0 and string.format("Alert History (|cffffd700%d|r)", unread) or "Alert History"
        StyleModernSubTab(btnTabWatchlist, panel.currentView == "watchlist", "Watchlist")
        StyleModernSubTab(btnTabHistory, panel.currentView == "history", historyText)
    end
    UpdateSubTabButtons()

    btnTabWatchlist:SetScript("OnClick", function()
        if panel.currentView == "watchlist" then return end
        panel.currentView = "watchlist"
        UpdateSubTabButtons()
        ShowRail("watch")
        RefreshView()
    end)
    btnTabHistory:SetScript("OnClick", function()
        if panel.currentView == "history" then return end
        panel.currentView = "history"
        UpdateSubTabButtons()
        ShowRail("history")
        RefreshView()
    end)

    -- =========================================================
    -- BOXES
    -- =========================================================
    local railBox = CreateBox(panel, LEFT_X, bodyTop, RAIL_W, 300, "controls")
    railBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_X, bottomPadding)
    local rightBox = CreateBox(panel, RESULTS_X - 4, bodyTop, ROW_WIDTH + 8, 320, "results")
    rightBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(effectiveWidth - (RESULTS_X + ROW_WIDTH + 4)), bottomPadding)
    panel.railBox = railBox

    local watchView = CreateFrame("Frame", nil, railBox); watchView:SetAllPoints(railBox)
    local editView = CreateFrame("Frame", nil, railBox); editView:SetAllPoints(railBox)
    local historyView = CreateFrame("Frame", nil, railBox); historyView:SetAllPoints(railBox)
    local detailView = CreateFrame("Frame", nil, railBox); detailView:SetAllPoints(railBox)
    panel.railViews = { watch = watchView, edit = editView, history = historyView, detail = detailView }
    ShowRail = function(name)
        panel.railView = name
        for key, view in pairs(panel.railViews) do
            if key == name then view:Show() else view:Hide() end
        end
    end

    -- Footer status line (shared).
    local statusText = rightBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", rightBox, "BOTTOMLEFT", 10, 10)
    statusText:SetPoint("RIGHT", rightBox, "BOTTOMRIGHT", -110, 10)
    statusText:SetJustifyH("LEFT")
    if statusText.SetWordWrap then statusText:SetWordWrap(false) end
    local countText = statusText
    local statusToken = 0
    local function SetStatus(msg, isError)
        statusToken = statusToken + 1
        local token = statusToken
        statusText:SetText((isError and "|cffff4444" or "|cff00ff00") .. tostring(msg) .. "|r")
        if C_Timer and C_Timer.After then
            C_Timer.After(4, function()
                if token == statusToken and RefreshView then RefreshView() end
            end)
        end
    end
    panel.SetStatus = SetStatus

    -- =========================================================
    -- RAIL: Watchlist settings
    -- =========================================================
    local btnNewAlert = RailButton(watchView, -8, RAIL_INNER_W, "+ New alert")
    btnNewAlert:SetScript("OnClick", function()
        ClearEditorForm()
        ShowRail("edit")
    end)
    AttachTip(btnNewAlert, "New alert", "Drop an item, shift-click a link, or type its name.")

    local importDropdown = CreateFrame("Button", nil, watchView, "UIPanelButtonTemplate")
    importDropdown:SetSize(RAIL_INNER_W, 20)
    importDropdown:SetPoint("TOPLEFT", watchView, "TOPLEFT", 8, -34)
    local importMenu = CreateFrame("Frame", parentPrefix .. "NotificationsImportDropdown", watchView, "UIDropDownMenuTemplate")
    importMenu:Hide()
    importDropdown._menu = importMenu
    SetDropdownLabel(importDropdown, "All Lists")
    importDropdown:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, importMenu, self, 0, 0)
    end)

    local halfW = math.floor((RAIL_INNER_W - 4) / 2)
    local btnDoImport = RailButton(watchView, -56, RAIL_INNER_W, "Review List Alerts...")
    AttachTip(btnDoImport, "Review List Alerts",
        "Preview every item in the list above, adjust its alert price, then confirm the import.")
    local btnImportString = RailButton(watchView, -78, RAIL_INNER_W, "Import String...")
    AttachTip(btnImportString, "Import String", "Paste a MarketSync list string to review its alerts.")

    local searchBox = CreateFrame("EditBox", nil, watchView, "InputBoxTemplate")
    searchBox:SetSize(RAIL_INNER_W - 6, 18)
    searchBox:SetPoint("TOPLEFT", watchView, "TOPLEFT", 14, -106)
    searchBox:SetAutoFocus(false)
    local searchPlaceholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 4, 0)
    searchPlaceholder:SetText("Search alerts...")
    searchBox:SetScript("OnTextChanged", function(self)
        local txt = TrimText(self:GetText())
        if txt == "" then searchPlaceholder:Show() else searchPlaceholder:Hide() end
        panel.searchQuery = txt:lower()
        panel.watchlistPage = 0
        if RefreshWatchlistTable then RefreshWatchlistTable() end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    RailLabel(watchView, -132, "List")
    local listFilterButton = CreateFrame("Button", nil, watchView, "UIPanelButtonTemplate")
    listFilterButton:SetSize(RAIL_INNER_W, 20)
    listFilterButton:SetPoint("TOPLEFT", watchView, "TOPLEFT", 8, -146)
    local listFilterMenu = CreateFrame("Frame", parentPrefix .. "NotificationsListFilter", watchView, "UIDropDownMenuTemplate")
    listFilterMenu:Hide()
    listFilterButton._menu = listFilterMenu
    SetDropdownLabel(listFilterButton, "All alerts")
    UIDropDownMenu_Initialize(listFilterMenu, function(_, level)
        local seen, names = {}, {}
        for _, req in ipairs(MarketSync.ListNotificationRequests and MarketSync.ListNotificationRequests() or {}) do
            local name = req.importSource or req.origin
            if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
        end
        table.sort(names)
        local all = UIDropDownMenu_CreateInfo()
        all.text = "All alerts"
        all.checked = panel.listFilter == nil
        all.func = function()
            panel.listFilter = nil
            SetDropdownLabel(listFilterButton, "All alerts")
            RefreshWatchlistTable()
        end
        UIDropDownMenu_AddButton(all, level)
        for _, name in ipairs(names) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = panel.listFilter == name
            info.func = function()
                panel.listFilter = name
                SetDropdownLabel(listFilterButton, Truncate and Truncate(name, 20) or name)
                RefreshWatchlistTable()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    listFilterButton:SetScript("OnClick", function(self) ToggleDropDownMenu(1, nil, listFilterMenu, self, 0, 0) end)

    RailLabel(watchView, -174, "Show")
    local WATCH_FILTERS = {
        { key = "all", label = "Everything" },
        { key = "close", label = "Close to firing", tip = "Within 10% of the alert price, or already below it." },
        { key = "paused", label = "Paused" },
        { key = "noprice", label = "No price yet", tip = "No auction price has been seen for these items." },
    }
    local watchFilterButtons = {}
    for i, f in ipairs(WATCH_FILTERS) do
        local btn = RailButton(watchView, -188 - (i - 1) * 22, RAIL_INNER_W, f.label)
        btn:SetScript("OnClick", function()
            panel.watchFilter = f.key
            panel.watchlistPage = 0
            RefreshWatchlistTable()
        end)
        if f.tip then AttachTip(btn, f.label, f.tip) end
        btn.filterKey, btn.filterLabel = f.key, f.label
        watchFilterButtons[i] = btn
    end

    -- =========================================================
    -- RAIL: Alert editor
    -- =========================================================
    local editorTitle = RailLabel(editView, -8, "New alert")
    local btnBack = CreateFrame("Button", nil, editView, "UIPanelButtonTemplate")
    btnBack:SetSize(52, 18)
    btnBack:SetPoint("TOPRIGHT", editView, "TOPRIGHT", -8, -5)
    btnBack:SetText("Back")
    btnBack:SetScript("OnClick", function() ShowRail(panel.currentView == "history" and "history" or "watch") end)

    local itemSlot = CreateFrame("Button", parentPrefix .. "ItemDropSlot", editView)
    itemSlot:SetSize(34, 34)
    itemSlot:SetPoint("TOPLEFT", editView, "TOPLEFT", 10, -30)
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

    local itemSlotName = editView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    itemSlotName:SetPoint("TOPLEFT", itemSlot, "TOPRIGHT", 6, -1)
    itemSlotName:SetPoint("RIGHT", editView, "RIGHT", -6, 0)
    itemSlotName:SetJustifyH("LEFT")
    if itemSlotName.SetWordWrap then itemSlotName:SetWordWrap(false) end
    itemSlotName:SetText("|cff888888Drop an item here|r")
    local itemSlotMarket = editView:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    itemSlotMarket:SetPoint("BOTTOMLEFT", itemSlot, "BOTTOMRIGHT", 6, 1)
    itemSlotMarket:SetJustifyH("LEFT")
    itemSlotMarket:SetText("Now: |cff888888--|r")

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
        elseif panel.editorItemLink then
            if HandleModifiedItemClick then HandleModifiedItemClick(panel.editorItemLink) end
        end
    end)
    itemSlot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if panel.editorItemLink then
            GameTooltip:SetHyperlink(panel.editorItemLink)
        elseif panel.editorItemID then
            GameTooltip:SetItemByID(panel.editorItemID)
        else
            GameTooltip:SetText("Item Drop Slot", 1, 0.82, 0)
            GameTooltip:AddLine("Drag an item from your bags or shift-click a link to set up an alert.", 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    itemSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(itemSlot, {
            name = function() return panel.editorItemName or "Item Drop Slot" end,
            context = "Button",
            description = "Drop an item from your bags or click with an item to configure price alerts",
        })
    end

    local targetBox = CreateFrame("EditBox", nil, editView, "InputBoxTemplate")
    targetBox:SetSize(RAIL_INNER_W - 6, 18)
    targetBox:SetPoint("TOPLEFT", editView, "TOPLEFT", 14, -70)
    targetBox:SetAutoFocus(false)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(targetBox, {
            onInsertLink = function(box, text)
                local id = text and text:match("item:(%d+)")
                if id then SetEditorItem(tonumber(id)); return true end
                local itemName = text and text:match("%[(.-)%]")
                if itemName then SetEditorItem(itemName); return true end
                return false
            end
        })
    end
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(targetBox, { name = "Item Target", context = "Edit Box",
            description = "Enter item name or item ID for price alert" })
    end

    RailLabel(editView, -94, "Alert when below")
    local priceBox = CreateFrame("EditBox", nil, editView, "InputBoxTemplate")
    priceBox:SetSize(RAIL_INNER_W - 6, 18)
    priceBox:SetPoint("TOPLEFT", editView, "TOPLEFT", 14, -108)
    priceBox:SetAutoFocus(false)
    priceBox:SetText("")
    AttachTip(priceBox, "Alert price", "Type 4g 50s, 450s or 4.5. MarketSync alerts when a listing is at or below it.")
    panel.priceBox = priceBox

    local function GetThresholdCopper()
        return ParseMoneyText(priceBox:GetText())
    end
    panel.GetThresholdCopper = GetThresholdCopper
    local function SetThresholdCopper(copper)
        local c = math.max(0, math.floor(tonumber(copper) or 0))
        priceBox:SetText(c > 0 and MoneyInputText(c) or "")
    end
    panel.SetThresholdCopper = SetThresholdCopper

    local quickW = math.floor((RAIL_INNER_W - 8) / 3)
    local function QuickButton(index, label, factor, tip)
        local btn = RailButton(editView, -130, quickW, label, 8 + (index - 1) * (quickW + 4))
        btn:SetScript("OnClick", function()
            local market = tonumber(panel.editorMarketPrice) or 0
            if market <= 0 then
                SetStatus("No current price for this item yet.", true)
                return
            end
            SetThresholdCopper(math.floor(market * factor))
        end)
        AttachTip(btn, label, tip)
        return btn
    end
    QuickButton(1, "Now", 1, "Alert at the current price.")
    QuickButton(2, "-10%", 0.9, "10% under the current price.")
    QuickButton(3, "-20%", 0.8, "20% under the current price.")

    RailLabel(editView, -158, "Auction houses")
    local mainScopeCheck = CreateFrame("CheckButton", nil, editView, "UICheckButtonTemplate")
    mainScopeCheck:SetSize(18, 18)
    mainScopeCheck:SetPoint("TOPLEFT", editView, "TOPLEFT", 8, -172)
    local mainScopeText = editView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mainScopeText:SetPoint("LEFT", mainScopeCheck, "RIGHT", 1, 0)
    mainScopeText:SetText("Main")
    local neutralScopeCheck = CreateFrame("CheckButton", nil, editView, "UICheckButtonTemplate")
    neutralScopeCheck:SetSize(18, 18)
    neutralScopeCheck:SetPoint("LEFT", mainScopeText, "RIGHT", 14, 0)
    local neutralScopeText = editView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    neutralScopeText:SetPoint("LEFT", neutralScopeCheck, "RIGHT", 1, 0)
    neutralScopeText:SetText("Neutral")
    local function SetScopeChecks(scope)
        panel.editorScope = scope or "all"
        mainScopeCheck:SetChecked(scope ~= "neutral")
        neutralScopeCheck:SetChecked(scope ~= "main")
    end
    local function UpdateScopeFromChecks(changed)
        if not mainScopeCheck:GetChecked() and not neutralScopeCheck:GetChecked() then
            changed:SetChecked(true)
        end
        panel.editorScope = mainScopeCheck:GetChecked() and
            (neutralScopeCheck:GetChecked() and "all" or "main") or "neutral"
    end
    mainScopeCheck:SetScript("OnClick", UpdateScopeFromChecks)
    neutralScopeCheck:SetScript("OnClick", UpdateScopeFromChecks)
    SetScopeChecks("all")

    local urgentCheck = CreateFrame("CheckButton", nil, editView, "UICheckButtonTemplate")
    urgentCheck:SetSize(18, 18)
    urgentCheck:SetPoint("TOPLEFT", editView, "TOPLEFT", 8, -194)
    local urgentText = urgentCheck.text or urgentCheck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    urgentCheck.text = urgentText
    urgentText:SetText("Urgent (always shows banner)")
    urgentText:ClearAllPoints()
    urgentText:SetPoint("LEFT", urgentCheck, "RIGHT", 2, 0)
    urgentCheck:SetChecked(false)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(urgentCheck, {
            name = "Urgent Alert",
            context = function(self) return self:GetChecked() and "Check Button, Checked" or "Check Button, Unchecked" end,
            description = "Always show the on-screen banner when this alert fires",
        })
    end

    RailLabel(editView, -218, "Sound")
    local soundButton = CreateFrame("Button", nil, editView, "UIPanelButtonTemplate")
    soundButton:SetSize(RAIL_INNER_W - 30, 20)
    soundButton:SetPoint("TOPLEFT", editView, "TOPLEFT", 8, -232)
    local soundMenu = CreateFrame("Frame", parentPrefix .. "NotificationsSoundMenu", editView, "UIDropDownMenuTemplate")
    soundMenu:Hide()
    soundButton._menu = soundMenu
    local function SoundLabel(id)
        if id == nil then return "Default sound" end
        if id == 0 then return "No sound" end
        return MarketSync.GetNotificationSoundName and MarketSync.GetNotificationSoundName(id) or tostring(id)
    end
    local function RefreshSoundButton() SetDropdownLabel(soundButton, SoundLabel(panel.editorSoundID)) end
    UIDropDownMenu_Initialize(soundMenu, function(_, level)
        local def = UIDropDownMenu_CreateInfo()
        def.text = "Default sound"
        def.checked = panel.editorSoundID == nil
        def.func = function() panel.editorSoundID = nil; RefreshSoundButton() end
        UIDropDownMenu_AddButton(def, level)
        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = (s.id == 0) and "No sound" or s.name
            info.checked = panel.editorSoundID == s.id
            info.func = function()
                panel.editorSoundID = s.id
                RefreshSoundButton()
                if s.id > 0 and MarketSync.PlayNotificationSound then MarketSync.PlayNotificationSound(s.id, true) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    soundButton:SetScript("OnClick", function(self) ToggleDropDownMenu(1, nil, soundMenu, self, 0, 0) end)
    local soundPreview = CreateFrame("Button", nil, editView, "UIPanelButtonTemplate")
    soundPreview:SetSize(26, 20)
    soundPreview:SetPoint("LEFT", soundButton, "RIGHT", 4, 0)
    soundPreview:SetText(">")
    AttachTip(soundPreview, "Preview", "Plays this alert's sound.")
    soundPreview:SetScript("OnClick", function()
        local id = panel.editorSoundID or (MarketSyncDB and MarketSyncDB.NotificationSoundID) or 8959
        if id > 0 and MarketSync.PlayNotificationSound then MarketSync.PlayNotificationSound(id, true) end
    end)
    RefreshSoundButton()

    local btnSave = CreateFrame("Button", nil, editView, "UIPanelButtonTemplate,BackdropTemplate")
    btnSave:SetSize(RAIL_INNER_W, 22)
    btnSave:SetPoint("BOTTOMLEFT", editView, "BOTTOMLEFT", 8, 32)
    btnSave:SetText("Add Alert")
    local btnPause = CreateFrame("Button", nil, editView, "UIPanelButtonTemplate,BackdropTemplate")
    btnPause:SetSize(halfW, 22)
    btnPause:SetPoint("BOTTOMLEFT", editView, "BOTTOMLEFT", 8, 8)
    btnPause:SetText("Pause")
    local btnDelete = CreateFrame("Button", nil, editView, "UIPanelButtonTemplate,BackdropTemplate")
    btnDelete:SetSize(halfW, 22)
    btnDelete:SetPoint("LEFT", btnPause, "RIGHT", 4, 0)
    btnDelete:SetText("Delete")
    local btnClear = btnBack
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btnSave, { name = function() return btnSave:GetText() or "Add Alert" end,
            context = "Button", description = "Save or update this price alert" })
    end

    -- =========================================================
    -- RAIL: History settings and details
    -- =========================================================
    local btnMarkAllRead = RailButton(historyView, -8, RAIL_INNER_W, "Mark All Read")
    btnMarkAllRead:SetScript("OnClick", function()
        if MarketSync.MarkAllNotificationsRead then MarketSync.MarkAllNotificationsRead() end
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end)
    RailLabel(historyView, -36, "Show")
    local HISTORY_FILTERS = {
        { key = "all", label = "All" },
        { key = "unread", label = "Unread" },
        { key = "below", label = "Still below target", tip = "The current lowest price is still at or under the alert price." },
        { key = "urgent", label = "Urgent only" },
    }
    local historyFilterButtons = {}
    for i, f in ipairs(HISTORY_FILTERS) do
        local btn = RailButton(historyView, -50 - (i - 1) * 22, RAIL_INNER_W, f.label)
        btn:SetScript("OnClick", function()
            panel.historyFilter = f.key
            panel.historyPage = 0
            RefreshHistoryTable()
        end)
        if f.tip then AttachTip(btn, f.label, f.tip) end
        btn.filterKey, btn.filterLabel = f.key, f.label
        historyFilterButtons[i] = btn
    end
    RailLabel(historyView, -144, "Seen by")
    local SOURCE_FILTERS = {
        { key = "any", label = "Anyone" },
        { key = "mine", label = "My scans" },
        { key = "guild", label = "Guild sync" },
    }
    local sourceFilterButtons = {}
    for i, f in ipairs(SOURCE_FILTERS) do
        local btn = RailButton(historyView, -158 - (i - 1) * 22, RAIL_INNER_W, f.label)
        btn:SetScript("OnClick", function()
            panel.sourceFilter = f.key
            panel.historyPage = 0
            RefreshHistoryTable()
        end)
        btn.filterKey, btn.filterLabel = f.key, f.label
        sourceFilterButtons[i] = btn
    end
    local historyNote = historyView:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    historyNote:SetPoint("BOTTOMLEFT", historyView, "BOTTOMLEFT", 8, 34)
    historyNote:SetWidth(RAIL_INNER_W)
    historyNote:SetJustifyH("LEFT")
    historyNote:SetText("|cff8a806eKeeps the last 50 alerts.|r")
    local btnClearHistory = CreateFrame("Button", nil, historyView, "UIPanelButtonTemplate,BackdropTemplate")
    btnClearHistory:SetSize(RAIL_INNER_W, 22)
    btnClearHistory:SetPoint("BOTTOMLEFT", historyView, "BOTTOMLEFT", 8, 8)
    btnClearHistory:SetText("Clear History...")
    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    StaticPopupDialogs["MARKETSYNC_CLEAR_ALERT_HISTORY"] = StaticPopupDialogs["MARKETSYNC_CLEAR_ALERT_HISTORY"] or {
        text = "Clear all alert history? Your alerts stay on the watchlist.",
        button1 = "Clear",
        button2 = "Cancel",
        OnAccept = function(_, data) if data and data.onAccept then data.onAccept() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    local function ClearHistoryNow()
        if MarketSync.ClearNotificationLog then MarketSync.ClearNotificationLog() end
        panel.historyPage = 0
        UpdateSubTabButtons()
        RefreshHistoryTable()
    end
    btnClearHistory:SetScript("OnClick", function()
        if StaticPopup_Show then
            StaticPopup_Show("MARKETSYNC_CLEAR_ALERT_HISTORY", nil, nil, { onAccept = ClearHistoryNow })
        else
            ClearHistoryNow()
        end
    end)

    local detailBack = CreateFrame("Button", nil, detailView, "UIPanelButtonTemplate")
    detailBack:SetSize(52, 18)
    detailBack:SetPoint("TOPRIGHT", detailView, "TOPRIGHT", -8, -5)
    detailBack:SetText("Back")
    detailBack:SetScript("OnClick", function() ShowRail("history") end)
    local detailIcon = detailView:CreateTexture(nil, "ARTWORK")
    detailIcon:SetSize(32, 32)
    detailIcon:SetPoint("TOPLEFT", detailView, "TOPLEFT", 8, -28)
    local detailName = detailView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    detailName:SetPoint("TOPLEFT", detailIcon, "TOPRIGHT", 6, 0)
    detailName:SetWidth(RAIL_W - 56)
    detailName:SetJustifyH("LEFT")
    if detailName.SetWordWrap then detailName:SetWordWrap(false) end
    local detailWhen = detailView:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
    detailWhen:SetPoint("TOPLEFT", detailName, "BOTTOMLEFT", 0, -3)
    local detailHeadline = detailView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    detailHeadline:SetPoint("TOPLEFT", detailView, "TOPLEFT", 8, -70)
    detailHeadline:SetWidth(RAIL_INNER_W)
    detailHeadline:SetJustifyH("LEFT")
    local detailBody = detailView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    detailBody:SetPoint("TOPLEFT", detailView, "TOPLEFT", 8, -110)
    detailBody:SetPoint("BOTTOMRIGHT", detailView, "BOTTOMRIGHT", -8, 60)
    detailBody:SetJustifyH("LEFT")
    if detailBody.SetJustifyV then detailBody:SetJustifyV("TOP") end
    if detailBody.SetSpacing then detailBody:SetSpacing(3) end
    local btnDetailSearch = CreateFrame("Button", nil, detailView, "UIPanelButtonTemplate")
    btnDetailSearch:SetSize(RAIL_INNER_W, 22)
    btnDetailSearch:SetPoint("BOTTOMLEFT", detailView, "BOTTOMLEFT", 8, 32)
    btnDetailSearch:SetText("Search in AH")
    local btnDetailEdit = CreateFrame("Button", nil, detailView, "UIPanelButtonTemplate")
    btnDetailEdit:SetSize(halfW, 22)
    btnDetailEdit:SetPoint("BOTTOMLEFT", detailView, "BOTTOMLEFT", 8, 8)
    btnDetailEdit:SetText("Edit alert")
    local btnDetailPause = CreateFrame("Button", nil, detailView, "UIPanelButtonTemplate")
    btnDetailPause:SetSize(halfW, 22)
    btnDetailPause:SetPoint("LEFT", btnDetailEdit, "RIGHT", 4, 0)
    btnDetailPause:SetText("Pause alert")

    -- =========================================================
    -- TABLE
    -- =========================================================
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
        end, 8, -24, FOOTER_H + 2)
        panel.tableScrollBar = tableScrollBar
        tableScrollBar:AttachMouseWheel(rightBox)
        tableScrollBar:AttachMouseWheel(panel)
    end

    local headerStrip = rightBox:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerStrip:SetColorTexture(MarketSync.GetThemeColor("header"))
    headerStrip:SetPoint("TOPLEFT", 4, -4)
    headerStrip:SetSize(ROW_WIDTH, 18)
    local headerSep = rightBox:CreateTexture(nil, "BACKGROUND", nil, 2)
    headerSep:SetColorTexture(MarketSync.GetThemeColor("headerBorder"))
    headerSep:SetPoint("TOPLEFT", 4, -22)
    headerSep:SetSize(ROW_WIDTH, 1)

    -- Column layouts: { key, label, width, justify, tooltip }. Item takes the rest.
    local WATCH_COLUMNS = {
        { "name", "Item", 0, "LEFT" },
        { "at", "Alert at", 74, "RIGHT", "The alert fires when a listing is at or below this price." },
        { "now", "Now", 74, "RIGHT", "Cheapest price last seen in the auction houses this alert watches." },
        { "close", "How close", 86, "RIGHT", "How far the current price is above the alert price." },
        { "scope", "AH", 52, "LEFT" },
        { "last", "Last fired", 66, "LEFT" },
        { "on", "On", 28, "CENTER", "Untick to pause this alert." },
    }
    local HISTORY_COLUMNS = {
        { "time", "Time", 62, "LEFT" },
        { "name", "Item", 0, "LEFT" },
        { "price", "Dropped to", 74, "RIGHT" },
        { "target", "Target", 70, "RIGHT" },
        { "saved", "Under", 46, "RIGHT", "How far under the alert price the listing was." },
        { "scope", "AH", 50, "LEFT" },
        { "source", "Seen by", 92, "LEFT", "My scan: your own Auction House scan. Guild sync: a guild member's shared scan." },
    }
    local function LayoutColumns(columns)
        local fixed = 0
        for _, c in ipairs(columns) do fixed = fixed + c[3] end
        local out, x = {}, 0
        for _, c in ipairs(columns) do
            local width = (c[3] > 0) and c[3] or (ROW_WIDTH - 8 - fixed)
            out[c[1]] = { x = x, width = width, justify = c[4], label = c[2], tip = c[5] }
            out[#out + 1] = out[c[1]]
            x = x + width
        end
        return out
    end
    local watchLayout = LayoutColumns(WATCH_COLUMNS)
    local historyLayout = LayoutColumns(HISTORY_COLUMNS)

    local headerLabels = {}
    for i = 1, 7 do
        local hdr = CreateFrame("Frame", nil, rightBox)
        hdr:SetSize(60, 18)
        hdr.text = hdr:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        hdr.text:SetPoint("TOPLEFT", hdr, "TOPLEFT", 0, 0)
        hdr.text:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
        if hdr.EnableMouse then hdr:EnableMouse(true) end
        hdr:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.label or "", 1, 0.82, 0)
            GameTooltip:AddLine(self.tip, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        hdr:SetScript("OnLeave", function() GameTooltip:Hide() end)
        headerLabels[i] = hdr
    end
    local function ApplyHeaders(layout, iconOffset)
        for i, hdr in ipairs(headerLabels) do
            local col = layout[i]
            if col then
                hdr:ClearAllPoints()
                local x = 8 + col.x + ((col.label == "Item") and iconOffset or 0)
                hdr:SetPoint("TOPLEFT", rightBox, "TOPLEFT", x, -4)
                hdr:SetSize(math.max(10, col.width - 6 - ((col.label == "Item") and iconOffset or 0)), 18)
                hdr.text:SetJustifyH(col.justify)
                hdr.text:SetText(col.label)
                hdr.label, hdr.tip = col.label, col.tip
                hdr:Show()
            else
                hdr:Hide()
            end
        end
    end

    local rows = {}
    local emptyLabel = rightBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyLabel:SetPoint("CENTER", rightBox, "CENTER", 0, 10)
    emptyLabel:SetWidth(ROW_WIDTH - 40)
    emptyLabel:SetText("")

    local function Cell(row, justify)
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetJustifyH(justify or "LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    local function PlaceCell(fs, col, height, extraX)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", fs:GetParent(), "LEFT", 4 + col.x + (extraX or 0), 0)
        fs:SetSize(math.max(10, col.width - 6 - (extraX or 0)), height)
        fs:SetJustifyH(col.justify)
    end

    for i = 1, numRowsPerPage do
        local row = CreateFrame("Button", nil, rightBox)
        row:SetSize(ROW_WIDTH - 8, ROW_H - 1)
        row:SetPoint("TOPLEFT", rightBox, "TOPLEFT", 8, -(HEADER_H + 4) - ((i - 1) * ROW_H))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(MarketSync.GetThemeColor(i % 2 == 0 and "rowEven" or "rowOdd"))
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
        if hl.SetBlendMode then hl:SetBlendMode("ADD") end
        if hl.SetAlpha then hl:SetAlpha(0.28) end
        local accent = row:CreateTexture(nil, "OVERLAY")
        accent:SetSize(3, ROW_H - 1)
        accent:SetPoint("LEFT")
        accent:SetColorTexture(1, 0.84, 0, 0.9)
        accent:Hide()
        row.accent = accent

        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(20, 20)
        local iconTex = iconBtn:CreateTexture(nil, "BORDER")
        iconTex:SetAllPoints()
        row.iconTex, row.iconBtn = iconTex, iconBtn
        iconBtn:SetScript("OnEnter", function(self)
            if row.itemLink or row.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if row.itemLink then GameTooltip:SetHyperlink(row.itemLink) else GameTooltip:SetItemByID(row.itemID) end
                GameTooltip:Show()
            end
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.cells = {}
        for _, key in ipairs({ "c1", "c2", "c3", "c4", "c5", "c6", "c7" }) do
            row.cells[key] = Cell(row)
        end
        row.wActiveCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.wActiveCheck:SetSize(18, 18)

        local function HandleRowClick(self, button)
            if button == "RightButton" then
                local req, h = row.request, row.historyEntry
                local customActions = {}
                if req then
                    customActions = {
                        { text = "Edit Alert", func = function() panel.OpenEditorForRequest(req) end },
                        { text = (req.enabled ~= false) and "Pause Alert" or "Resume Alert", func = function()
                            req.enabled = not (req.enabled ~= false)
                            MarketSync.UpsertNotificationRequest(req)
                            RefreshView()
                        end },
                        { text = "Delete Alert", func = function()
                            MarketSync.DeleteNotificationRequest(req.id)
                            RefreshView()
                        end },
                    }
                elseif h then
                    customActions = {
                        { text = "Load into Alert Form", func = function()
                            SetEditorItem(h.itemLink or h.itemID or h.itemName)
                            SetThresholdCopper(h.threshold)
                            ShowRail("edit")
                        end },
                    }
                end
                if MarketSync.ShowItemContextMenu then
                    MarketSync.ShowItemContextMenu(row, {
                        itemID = row.itemID,
                        itemLink = row.itemLink,
                        itemName = (req and req.displayName) or (h and h.itemName),
                        price = (req and req.thresholdCopper) or (h and (h.price or h.threshold)),
                        customActions = customActions,
                    })
                end
                return
            end
            if row.request then
                panel.OpenEditorForRequest(row.request)
            elseif row.historyEntry then
                ShowHistoryDetails(row.historyEntry)
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
        row:Hide()
        rows[i] = row
    end

    local btnPrev = CreateFrame("Button", nil, rightBox)
    btnPrev:SetSize(20, 20)
    btnPrev:SetPoint("BOTTOMRIGHT", -32, 6)
    btnPrev:SetNormalTexture("Interface\\Buttons\\Arrow-Left-Up")
    btnPrev:SetPushedTexture("Interface\\Buttons\\Arrow-Left-Down")
    btnPrev:SetDisabledTexture("Interface\\Buttons\\Arrow-Left-Disabled")
    local btnNext = CreateFrame("Button", nil, rightBox)
    btnNext:SetSize(20, 20)
    btnNext:SetPoint("LEFT", btnPrev, "RIGHT", 4, 0)
    btnNext:SetNormalTexture("Interface\\Buttons\\Arrow-Right-Up")
    btnNext:SetPushedTexture("Interface\\Buttons\\Arrow-Right-Down")
    btnNext:SetDisabledTexture("Interface\\Buttons\\Arrow-Right-Disabled")
    local pageText = rightBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pageText:SetPoint("RIGHT", btnPrev, "LEFT", -4, 0)
    pageText:SetJustifyH("RIGHT")
    pageText:SetText("1/1")
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(btnPrev, { name = "Previous Page", context = "Button", description = "Go to previous page of alerts" })
        MarketSync.SetAccessibility(btnNext, { name = "Next Page", context = "Button", description = "Go to next page of alerts" })
    end
    local function UpdatePager(page, maxPage)
        local hasPrev, hasNext = page > 0, page < maxPage
        btnPrev:SetEnabled(hasPrev)
        btnNext:SetEnabled(hasNext)
        local pnt = btnPrev.GetNormalTexture and btnPrev:GetNormalTexture()
        if pnt and pnt.SetVertexColor then pnt:SetVertexColor(MarketSync.GetThemeColor(hasPrev and "arrow" or "arrowDisabled")) end
        local nnt = btnNext.GetNormalTexture and btnNext:GetNormalTexture()
        if nnt and nnt.SetVertexColor then nnt:SetVertexColor(MarketSync.GetThemeColor(hasNext and "arrow" or "arrowDisabled")) end
        pageText:SetText(string.format("%d/%d", page + 1, maxPage + 1))
        if tableScrollBar then tableScrollBar:Update(page, maxPage) end
    end
    btnPrev:SetScript("OnClick", function()
        if panel.currentView == "watchlist" then
            if panel.watchlistPage > 0 then panel.watchlistPage = panel.watchlistPage - 1; RefreshWatchlistTable() end
        elseif panel.historyPage > 0 then
            panel.historyPage = panel.historyPage - 1; RefreshHistoryTable()
        end
    end)
    btnNext:SetScript("OnClick", function()
        if panel.currentView == "watchlist" then
            panel.watchlistPage = panel.watchlistPage + 1; RefreshWatchlistTable()
        else
            panel.historyPage = panel.historyPage + 1; RefreshHistoryTable()
        end
    end)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then btnPrev:Click() else btnNext:Click() end
    end)

    -- =========================================================
    -- EDITOR LOGIC
    -- =========================================================
    local function CurrentPriceFor(link, itemID, raw)
        local priceInfo = MarketSync.GetItemPriceAndScanInfo and MarketSync.GetItemPriceAndScanInfo(link or itemID or raw)
        local marketPrice = priceInfo and tonumber(priceInfo.price) or 0
        if marketPrice <= 0 then
            marketPrice = (MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(link or itemID or raw)) or 0
        end
        return marketPrice
    end

    local function ShowEditorFor(req)
        editorTitle:SetText(req and "Edit alert" or "New alert")
        btnSave:SetText(req and "Update Alert" or "Add Alert")
        SetControlVisible(btnPause, req ~= nil)
        SetControlVisible(btnDelete, req ~= nil)
        if req then btnPause:SetText(req.enabled ~= false and "Pause" or "Resume") end
    end

    SetEditorItem = function(itemOrLink)
        if not itemOrLink then return end
        local raw = tostring(itemOrLink)
        local itemID = MarketSync.ParseItemIDFromDBKey and MarketSync.ParseItemIDFromDBKey(raw)
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
        if quality and quality > 1 and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            itemSlotBorder:SetVertexColor(r, g, b, 0.8)
        else
            itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.5)
        end
        itemSlotName:SetText(link or name or raw)
        targetBox:SetText(name or raw)

        local marketPrice = CurrentPriceFor(link, itemID, raw)
        panel.editorMarketPrice = marketPrice
        local savedRequest
        if MarketSync.ListNotificationRequests then
            for _, req in ipairs(MarketSync.ListNotificationRequests()) do
                local matchesID = itemID and req.matchType == "itemID" and tonumber(req.matchValue) == itemID
                local matchesName = name and req.matchType == "name" and tostring(req.matchValue):lower() == name:lower()
                if matchesID or matchesName then
                    savedRequest = req
                    if req.scope == panel.editorScope then break end
                end
            end
        end
        panel.editorEditingID = savedRequest and savedRequest.id or nil
        panel.editorRequest = savedRequest
        ShowEditorFor(savedRequest)
        if savedRequest then
            SetThresholdCopper(savedRequest.thresholdCopper)
            SetScopeChecks(savedRequest.scope or "all")
            urgentCheck:SetChecked(savedRequest.urgent == true)
            local per = MarketSyncDB and MarketSyncDB.PerNotificationSounds
            panel.editorSoundID = per and per[savedRequest.id] or nil
        elseif marketPrice > 0 then
            SetThresholdCopper(math.floor(marketPrice))
        else
            SetThresholdCopper(0)
        end
        RefreshSoundButton()
        itemSlotMarket:SetText("Now: " .. (marketPrice > 0 and FormatMoneyColored(marketPrice) or "|cff888888--|r"))
    end
    panel.SetEditorItem = SetEditorItem

    panel.OpenEditorForRequest = function(req)
        SetEditorItem(req.matchValue or req.displayName)
        panel.editorEditingID = req.id
        panel.editorRequest = req
        ShowEditorFor(req)
        SetThresholdCopper(req.thresholdCopper)
        SetScopeChecks(req.scope or "all")
        urgentCheck:SetChecked(req.urgent == true)
        local per = MarketSyncDB and MarketSyncDB.PerNotificationSounds
        panel.editorSoundID = per and per[req.id] or nil
        RefreshSoundButton()
        ShowRail("edit")
    end

    ClearEditorForm = function()
        panel.editorEditingID = nil
        panel.editorRequest = nil
        panel.editorItemID = nil
        panel.editorItemLink = nil
        panel.editorItemName = nil
        panel.editorMarketPrice = 0
        panel.editorSoundID = nil
        panel.editorOrigin = nil
        itemSlotIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        itemSlotBorder:SetVertexColor(1, 0.84, 0, 0.5)
        itemSlotName:SetText("|cff888888Drop an item here|r")
        itemSlotMarket:SetText("Now: |cff888888--|r")
        targetBox:SetText("")
        SetThresholdCopper(0)
        SetScopeChecks("all")
        urgentCheck:SetChecked(false)
        RefreshSoundButton()
        ShowEditorFor(nil)
    end
    panel.ClearEditorForm = ClearEditorForm

    targetBox:SetScript("OnEnterPressed", function(self)
        local val = TrimText(self:GetText())
        if val ~= "" then SetEditorItem(val) end
        self:ClearFocus()
    end)
    targetBox:SetScript("OnEditFocusLost", function(self)
        local val = TrimText(self:GetText())
        if val ~= "" and not panel.editorItemID then SetEditorItem(val) end
    end)
    targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    priceBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); btnSave:Click() end)
    priceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    priceBox:SetScript("OnEditFocusLost", function(self)
        local copper = ParseMoneyText(self:GetText())
        if copper > 0 then self:SetText(MoneyInputText(copper)) end
    end)

    btnSave:SetScript("OnClick", function()
        local rawTarget = TrimText(targetBox:GetText())
        if rawTarget == "" and not panel.editorItemID then
            SetStatus("Enter an item name or drop an item.", true)
            return
        end
        local threshCopper = GetThresholdCopper()
        if threshCopper <= 0 then
            SetStatus("Set an alert price above 0.", true)
            return
        end
        local matchType, matchValue = "name", rawTarget:lower()
        local displayName = panel.editorItemName or rawTarget
        if panel.editorItemID then
            matchType, matchValue = "itemID", panel.editorItemID
        end
        local reqID = panel.editorEditingID
        if not reqID then
            reqID = string.format("%s:%s:%s", matchType, tostring(matchValue), panel.editorScope or "all")
        end
        local previous = panel.editorRequest
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
            enabled = previous and previous.enabled ~= false or true,
            origin = panel.editorOrigin,
        })
        if req then
            if MarketSyncDB then
                MarketSyncDB.PerNotificationSounds = MarketSyncDB.PerNotificationSounds or {}
                MarketSyncDB.PerNotificationSounds[req.id] = panel.editorSoundID
            end
            SetStatus(panel.editorEditingID and "Alert updated." or "Alert added.")
            ClearEditorForm()
            ShowRail("watch")
            RefreshWatchlistTable()
        else
            SetStatus("Failed to save alert.", true)
        end
    end)
    btnPause:SetScript("OnClick", function()
        local req = panel.editorRequest
        if not req then return end
        req.enabled = not (req.enabled ~= false)
        MarketSync.UpsertNotificationRequest(req)
        ShowEditorFor(req)
        SetStatus(req.enabled and "Alert resumed." or "Alert paused.")
        RefreshWatchlistTable()
    end)
    btnDelete:SetScript("OnClick", function()
        local req = panel.editorRequest
        if not req then return end
        MarketSync.DeleteNotificationRequest(req.id)
        SetStatus("Alert deleted.")
        ClearEditorForm()
        ShowRail("watch")
        RefreshWatchlistTable()
    end)

    -- =========================================================
    -- LIST IMPORT
    -- =========================================================
    RefreshImportDropdown = function()
        local lists = MarketSync.GetImportableListNames and MarketSync.GetImportableListNames() or {}
        UIDropDownMenu_Initialize(importMenu, function(self, level)
            local infoAll = UIDropDownMenu_CreateInfo()
            infoAll.text = "All Lists"
            infoAll.func = function()
                panel.importSelectedList = "__ALL__"
                panel.importSelectedSource = nil
                SetDropdownLabel(importDropdown, "All Lists")
            end
            UIDropDownMenu_AddButton(infoAll, level)
            for _, item in ipairs(lists) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.label or item.name
                info.func = function()
                    panel.importSelectedList = item.name
                    panel.importSelectedSource = item.source
                    SetDropdownLabel(importDropdown, item.label or item.name)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        SetDropdownLabel(importDropdown, panel.importSelectedList == "__ALL__" and "All Lists" or panel.importSelectedList)
    end

    btnDoImport:SetScript("OnClick", function()
        local candidates = MarketSync.GetNotificationImportCandidates
            and MarketSync.GetNotificationImportCandidates(panel.importSelectedList,
                panel.importSelectedSource, (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10)
            or {}
        if #candidates == 0 then
            SetStatus("That list has no items.", true)
            return
        end
        local label = panel.importSelectedList == "__ALL__" and "All Lists" or panel.importSelectedList
        ShowBulkImportPopup(label, candidates, function(imported)
            SetStatus(string.format("Imported %d alert(s).", imported))
            panel.watchlistPage = 0
            RefreshWatchlistTable()
        end)
    end)

    btnImportString:SetScript("OnClick", function()
        if not MarketSync.ShowListImportDialog then
            SetStatus("Import codec unavailable.", true)
            return
        end
        MarketSync.ShowListImportDialog({
            mode = "alerts",
            onImportAlerts = function(decoded)
                local candidates = MarketSync.BuildNotificationCandidatesFromDecodedList
                    and MarketSync.BuildNotificationCandidatesFromDecodedList(decoded) or {}
                if #candidates == 0 then
                    SetStatus("No items found in string.", true)
                    return
                end
                ShowBulkImportPopup(decoded.n or "Imported List", candidates, function(count)
                    SetStatus(string.format("Imported %d alert(s) from %s.", count, tostring(decoded.n or "string")))
                    UpdateSubTabButtons()
                    RefreshView()
                end)
            end,
        })
    end)

    -- =========================================================
    -- WATCHLIST
    -- =========================================================
    local function RefreshFilterButtons(buttons, active)
        for _, btn in ipairs(buttons) do SetActive(btn, btn.filterKey == active, btn.filterLabel) end
    end

    RefreshWatchlistTable = function()
        RefreshFilterButtons(watchFilterButtons, panel.watchFilter)
        ApplyHeaders(watchLayout, 24)
        local all = MarketSync.ListNotificationRequests and MarketSync.ListNotificationRequests() or {}
        local statuses = MarketSync.GetNotificationRequestStatuses and MarketSync.GetNotificationRequestStatuses(all) or {}
        local counts = { close = 0, paused = 0, noprice = 0 }
        local shown = {}
        for _, req in ipairs(all) do
            local st = statuses[req.id] or {}
            local isClose = st.isBelow or (st.gapPct and st.gapPct <= 10)
            if isClose and req.enabled ~= false then counts.close = counts.close + 1 end
            if req.enabled == false then counts.paused = counts.paused + 1 end
            if not st.currentPrice then counts.noprice = counts.noprice + 1 end
            local keep = true
            if panel.searchQuery ~= "" then
                keep = tostring(req.displayName or req.matchValue or ""):lower():find(panel.searchQuery, 1, true) ~= nil
            end
            if keep and panel.listFilter then
                keep = (req.importSource == panel.listFilter) or (req.origin == panel.listFilter)
            end
            if keep and panel.watchFilter == "close" then keep = isClose and req.enabled ~= false end
            if keep and panel.watchFilter == "paused" then keep = req.enabled == false end
            if keep and panel.watchFilter == "noprice" then keep = not st.currentPrice end
            if keep then shown[#shown + 1] = { req = req, st = st } end
        end
        for _, btn in ipairs(watchFilterButtons) do
            local n = counts[btn.filterKey]
            local label = n and n > 0 and string.format("%s (%d)", btn.filterLabel, n) or btn.filterLabel
            SetActive(btn, btn.filterKey == panel.watchFilter, label)
        end
        -- Closest to firing first, then by name.
        table.sort(shown, function(a, b)
            local ga = a.st.gapPct or math.huge
            local gb = b.st.gapPct or math.huge
            if (a.req.enabled ~= false) ~= (b.req.enabled ~= false) then return a.req.enabled ~= false end
            if ga ~= gb then return ga < gb end
            return tostring(a.req.displayName or ""):lower() < tostring(b.req.displayName or ""):lower()
        end)

        local total = #shown
        local maxPage = math.max(0, math.ceil(total / numRowsPerPage) - 1)
        panel.watchlistPage = math.min(math.max(0, panel.watchlistPage), maxPage)
        UpdatePager(panel.watchlistPage, maxPage)
        local startIndex = panel.watchlistPage * numRowsPerPage + 1

        if #all == 0 then
            emptyLabel:SetText("No alerts yet.\nPress + New alert, or review a list on the left.")
            emptyLabel:Show()
        elseif total == 0 then
            emptyLabel:SetText("No alerts match these filters.")
            emptyLabel:Show()
        else
            emptyLabel:Hide()
        end
        countText:SetText(string.format("%d alerts | %d on | %d paused", #all, #all - counts.paused, counts.paused))

        for i, row in ipairs(rows) do
            local entry = shown[startIndex + i - 1]
            local cells = row.cells
            row.accent:Hide()
            if entry then
                local req, st = entry.req, entry.st
                row.request, row.historyEntry = req, nil
                local itemID = RequestItemID(req)
                row.itemID = itemID
                local name, link, _, _, _, _, _, _, _, icon
                if itemID then name, link, _, _, _, _, _, _, _, icon = SafeGetItemInfo(itemID) end
                row.itemLink = link
                row.iconTex:SetTexture(icon or SafeGetItemIcon(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.iconBtn:ClearAllPoints()
                row.iconBtn:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.iconBtn:Show()

                local dName = link or req.displayName or (itemID and ("Item " .. itemID)) or tostring(req.matchValue)
                if req.urgent then dName = "|cffff4444!|r " .. dName end
                if req.enabled == false then dName = "|cff8a806e" .. MarketSync.StripColorCodes(dName) .. "|r" end
                PlaceCell(cells.c1, watchLayout.name, 20, 24)
                cells.c1:SetText(dName)
                PlaceCell(cells.c2, watchLayout.at, 20)
                cells.c2:SetText(FormatMoneyColored(req.thresholdCopper))
                PlaceCell(cells.c3, watchLayout.now, 20)
                cells.c3:SetText(st.currentPrice and FormatMoneyColored(st.currentPrice) or "|cff8a806e-|r")
                PlaceCell(cells.c4, watchLayout.close, 20)
                if not st.currentPrice then
                    cells.c4:SetText("|cff8a806eNo price|r")
                elseif st.isBelow then
                    cells.c4:SetText("|cff4fd06aBelow now|r")
                elseif st.gapPct and st.gapPct <= 10 then
                    cells.c4:SetText(string.format("|cffffb347%d%% over|r", st.gapPct))
                else
                    cells.c4:SetText(string.format("|cffa89e8c%d%% over|r", st.gapPct or 0))
                end
                PlaceCell(cells.c5, watchLayout.scope, 20)
                cells.c5:SetText(req.scope == "main" and "Main" or (req.scope == "neutral" and "Neutral" or "Both"))
                PlaceCell(cells.c6, watchLayout.last, 20)
                cells.c6:SetText((st.lastAlertAt or 0) > 0 and FormatRelativeTime(st.lastAlertAt) or "|cff8a806eNever|r")
                cells.c7:SetText("")
                row.wActiveCheck:ClearAllPoints()
                row.wActiveCheck:SetPoint("LEFT", row, "LEFT", 4 + watchLayout.on.x + 4, 0)
                row.wActiveCheck:SetChecked(req.enabled ~= false)
                row.wActiveCheck:SetScript("OnClick", function(self)
                    req.enabled = self:GetChecked() and true or false
                    MarketSync.UpsertNotificationRequest(req)
                    RefreshWatchlistTable()
                end)
                row.wActiveCheck:Show()
                for _, fs in pairs(cells) do fs:Show() end

                if MarketSync.SetAccessibility then
                    local displayName = MarketSync.StripColorCodes(req.displayName or req.matchValue or "Item")
                    MarketSync.SetAccessibility(row, {
                        name = function() return displayName end,
                        context = "Button",
                        description = function()
                            local thresh = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(req.thresholdCopper) or (tostring(req.thresholdCopper or 0) .. " copper")
                            return string.format("%s, alert below %s, %s. Click to edit.", displayName, thresh,
                                (req.enabled ~= false) and "on" or "paused")
                        end,
                        getIndexInfo = function() return { index = startIndex + i - 1, total = total } end,
                    })
                end
                row:Show()
            else
                row.request, row.historyEntry = nil, nil
                row.wActiveCheck:Hide()
                row:Hide()
            end
        end
    end

    -- =========================================================
    -- HISTORY
    -- =========================================================
    local function HistoryStatus(entry)
        if not (MarketSync.GetNotificationRequestStatus and entry.requestID) then return {} end
        local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        local req = realmDB and realmDB.NotificationRequests and realmDB.NotificationRequests[entry.requestID]
        if not req then return {} end
        local st = MarketSync.GetNotificationRequestStatus(req)
        st.request = req
        return st
    end

    ShowHistoryDetails = function(entry)
        panel.detailEntry = entry
        local st = HistoryStatus(entry)
        detailIcon:SetTexture(entry.itemIcon or SafeGetItemIcon(entry.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
        detailName:SetText(entry.itemLink or entry.itemName or "Item")
        detailWhen:SetText("|cffa89e8c" .. FormatRelativeTime(entry.time) .. "|r")
        local price, target = tonumber(entry.price) or 0, tonumber(entry.threshold) or 0
        local under = (target > 0) and math.floor(((target - price) / target) * 100 + 0.5) or 0
        detailHeadline:SetText(string.format("|cff4fd06aDropped to %s|r\n|cffcfe8d2%d%% under your %s target|r",
            MarketSync.FormatMoney and MarketSync.FormatMoney(price) or price, under,
            MarketSync.FormatMoney and MarketSync.FormatMoney(target) or target))
        local lines = {
            "|cffa89e8cSeen by|r  " .. SourceLabel(entry.source),
            "|cffa89e8cAuction house|r  " .. (entry.scope == "neutral" and "Neutral" or (entry.scope == "main" and "Main" or "Either")),
            "|cffa89e8cAlert type|r  " .. (entry.urgent and "|cffff8a7aUrgent|r" or "Normal"),
        }
        if st.currentPrice then
            local still = st.currentPrice <= target and "|cff4fd06a still under target|r" or "|cffffb347 back above target|r"
            lines[#lines + 1] = "|cffa89e8cLowest now|r  " .. FormatMoneyColored(st.currentPrice) .. still
        end
        local req = st.request
        if req and (req.origin or req.importSource) then
            lines[#lines + 1] = "|cffa89e8cFrom|r  " .. tostring(req.origin or req.importSource)
        end
        if not req then lines[#lines + 1] = "|cff8a806eThis alert was deleted.|r" end
        detailBody:SetText(table.concat(lines, "\n"))
        SetControlVisible(btnDetailEdit, req ~= nil)
        SetControlVisible(btnDetailPause, req ~= nil)
        if req then btnDetailPause:SetText(req.enabled ~= false and "Pause alert" or "Resume alert") end
        ShowRail("detail")
    end
    panel.ShowHistoryDetails = ShowHistoryDetails

    btnDetailSearch:SetScript("OnClick", function()
        local entry = panel.detailEntry
        if not entry then return end
        local ok = MarketSync.SearchInAuctionHouse and MarketSync.SearchInAuctionHouse(entry.itemID or entry.itemName)
        if not ok then SetStatus("Open the Auction House to search for this item.", true) end
    end)
    btnDetailEdit:SetScript("OnClick", function()
        local st = panel.detailEntry and HistoryStatus(panel.detailEntry)
        if st and st.request then panel.OpenEditorForRequest(st.request) end
    end)
    btnDetailPause:SetScript("OnClick", function()
        local st = panel.detailEntry and HistoryStatus(panel.detailEntry)
        if not (st and st.request) then return end
        st.request.enabled = not (st.request.enabled ~= false)
        MarketSync.UpsertNotificationRequest(st.request)
        ShowHistoryDetails(panel.detailEntry)
    end)

    RefreshHistoryTable = function()
        RefreshFilterButtons(historyFilterButtons, panel.historyFilter)
        RefreshFilterButtons(sourceFilterButtons, panel.sourceFilter)
        ApplyHeaders(historyLayout, 24)
        local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        local history = realmDB and realmDB.NotificationLog or {}
        local needStatus = panel.historyFilter == "below"
        local statusByRequest = {}
        if needStatus and MarketSync.GetNotificationRequestStatuses then
            local reqs, seen = {}, {}
            for _, entry in ipairs(history) do
                local req = entry.requestID and realmDB.NotificationRequests and realmDB.NotificationRequests[entry.requestID]
                if req and not seen[req.id] then seen[req.id] = true; reqs[#reqs + 1] = req end
            end
            statusByRequest = MarketSync.GetNotificationRequestStatuses(reqs)
        end
        local shown, unread = {}, 0
        for _, entry in ipairs(history) do
            if entry.read == false then unread = unread + 1 end
            local keep = true
            if panel.historyFilter == "unread" then keep = entry.read == false end
            if panel.historyFilter == "urgent" then keep = entry.urgent == true end
            if panel.historyFilter == "below" then
                local st = entry.requestID and statusByRequest[entry.requestID]
                keep = st and st.isBelow or false
            end
            local mine = (entry.source == nil or entry.source == "" or entry.source == "Personal")
            if keep and panel.sourceFilter == "mine" then keep = mine end
            if keep and panel.sourceFilter == "guild" then keep = not mine end
            if keep then shown[#shown + 1] = entry end
        end

        local total = #shown
        local maxPage = math.max(0, math.ceil(total / numRowsPerPage) - 1)
        panel.historyPage = math.min(math.max(0, panel.historyPage), maxPage)
        UpdatePager(panel.historyPage, maxPage)
        local startIndex = panel.historyPage * numRowsPerPage + 1
        if #history == 0 then
            emptyLabel:SetText("No alerts yet.\nThey show here when a price drops to an alert's target.")
            emptyLabel:Show()
        elseif total == 0 then
            emptyLabel:SetText("No alerts match these filters.")
            emptyLabel:Show()
        else
            emptyLabel:Hide()
        end
        countText:SetText(string.format("%d alerts | %d unread", #history, unread))

        for i, row in ipairs(rows) do
            local entry = shown[startIndex + i - 1]
            local cells = row.cells
            row.wActiveCheck:Hide()
            if entry then
                row.historyEntry, row.request = entry, nil
                row.itemID, row.itemLink = entry.itemID, entry.itemLink
                row.accent:SetShown(entry.read == false)
                local bold = entry.read == false
                PlaceCell(cells.c1, historyLayout.time, 20)
                cells.c1:SetText((bold and "|cffffd700" or "|cffa89e8c") .. TimeLabel(entry.time) .. "|r")
                row.iconTex:SetTexture(entry.itemIcon or SafeGetItemIcon(entry.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.iconBtn:ClearAllPoints()
                row.iconBtn:SetPoint("LEFT", row, "LEFT", 4 + historyLayout.name.x, 0)
                row.iconBtn:Show()
                local dName = entry.itemLink or entry.itemName or (entry.itemID and ("Item " .. entry.itemID)) or "Unknown"
                if entry.urgent then dName = "|cffff4444!|r " .. dName end
                PlaceCell(cells.c2, historyLayout.name, 20, 24)
                cells.c2:SetText(dName)
                PlaceCell(cells.c3, historyLayout.price, 20)
                cells.c3:SetText(FormatMoneyColored(entry.price))
                PlaceCell(cells.c4, historyLayout.target, 20)
                cells.c4:SetText(FormatMoneyColored(entry.threshold))
                local price, target = tonumber(entry.price) or 0, tonumber(entry.threshold) or 0
                PlaceCell(cells.c5, historyLayout.saved, 20)
                cells.c5:SetText(target > 0 and string.format("|cff4fd06a%d%%|r", math.floor(((target - price) / target) * 100 + 0.5)) or "-")
                PlaceCell(cells.c6, historyLayout.scope, 20)
                cells.c6:SetText(entry.scope == "neutral" and "Neutral" or (entry.scope == "main" and "Main" or "Either"))
                PlaceCell(cells.c7, historyLayout.source, 20)
                cells.c7:SetText(SourceLabel(entry.source))
                for _, fs in pairs(cells) do fs:Show() end

                if MarketSync.SetAccessibility then
                    local cleanName = MarketSync.StripColorCodes(entry.itemName or (entry.itemID and ("Item " .. entry.itemID)) or "Alert")
                    MarketSync.SetAccessibility(row, {
                        name = function() return cleanName end,
                        context = "Button",
                        description = function()
                            local priceStr = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(entry.price) or (tostring(entry.price or 0) .. " copper")
                            return string.format("%s, dropped to %s, seen by %s. Click for details.", cleanName, priceStr, SourceLabel(entry.source))
                        end,
                        getIndexInfo = function() return { index = startIndex + i - 1, total = total } end,
                    })
                end
                row:Show()
            else
                row.request, row.historyEntry = nil, nil
                row:Hide()
            end
        end
    end

    RefreshView = function()
        if panel.currentView == "watchlist" then
            RefreshWatchlistTable()
        else
            RefreshHistoryTable()
        end
    end
    panel.RefreshView = function() RefreshView() end

    panel:SetScript("OnShow", function()
        if MarketSync.AcknowledgeNotifications then
            MarketSync.AcknowledgeNotifications()
        end
        soundCheck:SetChecked(MarketSyncDB and MarketSyncDB.EnableNotificationSounds ~= false)
        bannerCheck:SetChecked(MarketSyncDB and MarketSyncDB.EnableRaidWarningAlerts ~= false)
        RefreshMute()
        UpdateSubTabButtons()
        RefreshImportDropdown()
        if panel.railView ~= "edit" then
            ShowRail(panel.currentView == "history" and "history" or "watch")
        end
        RefreshView()
    end)

    ShowRail("watch")
    ClearEditorForm()

    NotificationPanel = panel
    panel.rows = rows
    panel.rightBox = rightBox
    table.insert(registeredNotificationPanels, panel)
    if MarketSync.Theme then MarketSync.Theme.Register(panel) end
    return panel
end

function MarketSync.ToggleNotificationsManager()
    if MarketSync.SelectMainFrameTab then
        if MarketSyncMainFrame and not MarketSyncMainFrame:IsShown() then
            MarketSyncMainFrame:Show()
        end
        MarketSync.SelectMainFrameTab(5)
    elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[5] then
        if not MarketSyncMainFrame:IsShown() then
            MarketSyncMainFrame:Show()
        end
        MarketSyncMainFrame.tabs[5]:Click()
    elseif MarketSync_ToggleUI then
        MarketSync_ToggleUI()
    end
end

-- origin: where the alert is made from (for example "Processing"); shown in
-- the alert's history details.
function MarketSync.OpenAlertEditorWithItem(itemRef, price, origin)
    if AuctionFrame and AuctionFrame:IsShown() and MarketSync.AuctionHouse and MarketSync.AuctionHouse.SelectTab then
        MarketSync.AuctionHouse.SelectTab("alerts")
    elseif MarketSync.SelectMainFrameTab then
        if MarketSyncMainFrame and not MarketSyncMainFrame:IsShown() then
            MarketSyncMainFrame:Show()
        end
        MarketSync.SelectMainFrameTab(5)
    elseif MarketSync.ToggleNotificationsManager then
        MarketSync.ToggleNotificationsManager()
    end

    for _, p in ipairs(registeredNotificationPanels) do
        if p and p.SetEditorItem then
            p.SetEditorItem(itemRef)
            if price and price > 0 and p.SetThresholdCopper then
                p.SetThresholdCopper(price)
            end
            p.editorOrigin = origin
            if p.railViews and p.railViews.edit then
                for key, view in pairs(p.railViews) do
                    if key == "edit" then view:Show() else view:Hide() end
                end
                p.railView = "edit"
            end
        end
    end
end
