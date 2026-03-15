-- =============================================================
-- MarketSync - Notifications Tab UI
-- Embedded panel with manual controls, list import, and request management
-- =============================================================

local NotificationPanel
local ROWS_PER_PAGE = 9

local LEFT_X = 23
local TOP_Y = -105
local LEFT_W = 155
local LEFT_TOP_H = 188
local LEFT_BOTTOM_H = 100
local BOX_GAP = 8

local RESULTS_X = 195
local ROW_WIDTH = 632
local ROW_HEIGHT = 32

local SCOPE_OPTIONS = {
    { value = "all", label = "All" },
    { value = "main", label = "Main AH" },
    { value = "neutral", label = "Neutral AH" },
}

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
    local raw = TrimText(text):gsub(",", ".")
    local gold = tonumber(raw)
    if not gold or gold <= 0 then
        return 0
    end
    return math.floor(gold * 10000)
end

local function FormatGoldInput(copper)
    local g = (tonumber(copper) or 0) / 10000
    return tostring(math.max(0, math.floor(g + 0.5)))
end

local function Truncate(text, maxLen)
    local s = tostring(text or "")
    if #s <= maxLen then
        return s
    end
    return s:sub(1, math.max(1, maxLen - 3)) .. "..."
end

local function ReadInt(editBox, defaultVal)
    local raw = TrimText(editBox and editBox:GetText() or "")
    local v = tonumber(raw)
    if not v then return defaultVal end
    return math.floor(v + 0.5)
end

local function MoneyText(copper)
    if MarketSync.FormatMoney then
        return MarketSync.FormatMoney(math.max(0, math.floor(tonumber(copper) or 0)))
    end
    return tostring(math.floor(tonumber(copper) or 0))
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

local function BuildUpsertPayload(req, enabledOverride)
    return {
        id = req.id,
        matchType = req.matchType,
        matchValue = req.matchValue,
        displayName = req.displayName,
        thresholdCopper = req.thresholdCopper,
        scope = req.scope,
        variantMode = req.variantMode,
        cooldownSec = req.cooldownSec,
        enabled = (enabledOverride == nil) and (req.enabled ~= false) or enabledOverride,
        quantityHint = req.quantityHint,
        importSource = req.importSource,
    }
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

local function ResolveManualRequest(rawValue)
    local raw = TrimText(rawValue)
    if raw == "" then
        return nil
    end

    local linkedID = raw:match("|Hitem:(%d+):") or raw:match("item:(%d+)")
    if linkedID then
        local id = tonumber(linkedID)
        if id and id > 0 then
            local itemName = GetItemInfo(id)
            return {
                matchType = "itemID",
                matchValue = id,
                displayName = itemName or ("Item " .. tostring(id)),
            }
        end
    end

    local bracketed = raw:match("%[(.-)%]")
    if bracketed and bracketed ~= "" then
        raw = TrimText(bracketed)
    end

    local asID = tonumber(raw)
    if asID and asID > 0 then
        local id = math.floor(asID)
        local itemName = GetItemInfo(id)
        return {
            matchType = "itemID",
            matchValue = id,
            displayName = itemName or ("Item " .. tostring(id)),
        }
    end

    return {
        matchType = "name",
        matchValue = string.lower(raw),
        displayName = raw,
    }
end

local function ResolveRequestVisual(req)
    local matchType = tostring(req and req.matchType or "")
    local matchValue = req and req.matchValue
    local displayName = tostring((req and req.displayName) or matchValue or "Unknown")

    local itemID = nil
    if matchType == "itemID" then
        itemID = tonumber(matchValue)
    elseif matchType == "name" then
        itemID = MarketSync.ResolveItemID(matchValue)
    end

    local name, link, _, _, _, _, _, _, _, icon
    if itemID then
        name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    elseif displayName ~= "" then
        -- Fallback attempt for display names that aren't already converted to itemIDs
        local displayID = MarketSync.ResolveItemID(displayName)
        if displayID then
            itemID = displayID
            name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        else
            name, link, _, _, _, _, _, _, _, icon = GetItemInfo(displayName)
            if link then
                itemID = tonumber(link:match("item:(%d+)"))
            end
        end
    end

    name = name or displayName
    if not link and itemID then
        link = "|Hitem:" .. tostring(itemID) .. "|h[" .. tostring(name) .. "]|h"
    end
    
    if not icon and itemID and GetItemIcon then
        icon = GetItemIcon(itemID)
    end
    
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"

    return name, link, icon, itemID
end

function MarketSync.CreateNotificationsPanel(parent)
    if NotificationPanel then
        return NotificationPanel
    end

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel:Hide()

    panel.page = 0
    panel.manualScope = "all"
    panel.importScope = "all"
    panel.importListName = "__ALL__"
    panel.importListOptions = { "__ALL__" }
    panel.selectedIDs = {}
    panel.requestLookup = {}
    panel.selectionLocked = false
    panel.manualDraftName = nil

    local leftTopBox = CreateBox(panel, LEFT_X, TOP_Y, LEFT_W, LEFT_TOP_H)
    local leftBottomBox = CreateBox(panel, LEFT_X, TOP_Y - LEFT_TOP_H - BOX_GAP, LEFT_W, LEFT_BOTTOM_H)

    local manualTitle = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    manualTitle:SetPoint("TOPLEFT", 8, -8)
    manualTitle:SetText("|cffffd700Manual Request|r")

    local nameLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", 8, -30)
    nameLabel:SetText("Target (Name/ID)")

    local nameBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    nameBox:SetSize(LEFT_W - 16, 18)
    nameBox:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", 8, -46)
    nameBox:SetAutoFocus(false)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(nameBox, {
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

    local thresholdLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    thresholdLabel:SetPoint("TOPLEFT", 8, -72)
    thresholdLabel:SetText("Threshold (g)")

    local thresholdBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    thresholdBox:SetSize(45, 18)
    thresholdBox:SetPoint("LEFT", thresholdLabel, "RIGHT", 8, 0)
    thresholdBox:SetAutoFocus(false)
    thresholdBox:SetNumeric(true)
    thresholdBox:SetText("0")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(thresholdBox)
    end

    local cooldownLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cooldownLabel:SetPoint("TOPLEFT", 8, -98)
    cooldownLabel:SetText("Cooldown (sec)")

    local cooldownBox = CreateFrame("EditBox", nil, leftTopBox, "InputBoxTemplate")
    cooldownBox:SetSize(55, 18)
    cooldownBox:SetPoint("LEFT", cooldownLabel, "RIGHT", 8, 0)
    cooldownBox:SetAutoFocus(false)
    cooldownBox:SetNumeric(true)
    cooldownBox:SetText("300")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(cooldownBox)
    end

    local scopeLabel = leftTopBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", 8, -124)
    scopeLabel:SetText("Scope")

    local manualScopeDropdown = BuildScopeDropdown(
        "MarketSyncManualScopeDropdown",
        leftTopBox,
        90,
        function() return panel.manualScope end,
        function(v) panel.manualScope = v end
    )
    manualScopeDropdown:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", -8, -136)

    local btnAdd = CreateFrame("Button", nil, leftTopBox, "UIPanelButtonTemplate")
    btnAdd:SetSize(LEFT_W - 16, 20)
    btnAdd:SetPoint("TOPLEFT", leftTopBox, "TOPLEFT", 8, -166)
    btnAdd:SetText("Add / Update")

    local importTitle = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importTitle:SetPoint("TOPLEFT", 8, -8)
    importTitle:SetText("|cffffd700List Import|r")

    local importListDropdown = CreateFrame("Frame", "MarketSyncImportListDropdown", leftBottomBox, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(importListDropdown, LEFT_W - 30)
    importListDropdown:SetPoint("TOPLEFT", leftBottomBox, "TOPLEFT", -8, -24)

    local useListMaxCheck = CreateFrame("CheckButton", nil, leftBottomBox, "UICheckButtonTemplate")
    useListMaxCheck:SetSize(24, 24)
    useListMaxCheck:SetPoint("TOPLEFT", 8, -44) -- Bumped up slightly
    useListMaxCheck.text:SetText("Use list max price")
    useListMaxCheck:SetChecked(true)

    local fallbackLabel = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fallbackLabel:SetPoint("TOPLEFT", 8, -70) -- Bumped up slightly
    fallbackLabel:SetText("Fallback g")

    local importFallbackBox = CreateFrame("EditBox", nil, leftBottomBox, "InputBoxTemplate")
    importFallbackBox:SetSize(34, 18)
    importFallbackBox:SetPoint("LEFT", fallbackLabel, "RIGHT", 4, 0)
    importFallbackBox:SetAutoFocus(false)
    importFallbackBox:SetNumeric(true)
    importFallbackBox:SetText("0")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(importFallbackBox)
    end

    local importCooldownLabel = leftBottomBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    importCooldownLabel:SetPoint("LEFT", importFallbackBox, "RIGHT", 6, 0)
    importCooldownLabel:SetText("CD")

    local importCooldownBox = CreateFrame("EditBox", nil, leftBottomBox, "InputBoxTemplate")
    importCooldownBox:SetSize(34, 18)
    importCooldownBox:SetPoint("LEFT", importCooldownLabel, "RIGHT", 3, 0)
    importCooldownBox:SetAutoFocus(false)
    importCooldownBox:SetNumeric(true)
    importCooldownBox:SetText("300")
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(importCooldownBox)
    end

    local btnImport = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnImport:SetSize(72, 22)
    btnImport:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 23, 14) 
    btnImport:SetText("Import")

    local btnRefreshLists = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnRefreshLists:SetSize(72, 22)
    btnRefreshLists:SetPoint("LEFT", btnImport, "RIGHT", 4, 0)
    btnRefreshLists:SetText("Lists")

    local btnRefresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnRefresh:SetSize(80, 22)
    btnRefresh:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -44)
    btnRefresh:SetText("Refresh")

    local btnClearSelected = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnClearSelected:SetSize(80, 22)
    btnClearSelected:SetPoint("RIGHT", btnRefresh, "LEFT", -4, 0)
    btnClearSelected:SetText("Clear Sel")

    local btnDeleteSelected = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnDeleteSelected:SetSize(80, 22)
    btnDeleteSelected:SetPoint("RIGHT", btnClearSelected, "LEFT", -4, 0)
    btnDeleteSelected:SetText("Delete Sel")

    local soundCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    soundCheck:SetPoint("RIGHT", btnDeleteSelected, "LEFT", -8, -1)
    soundCheck:SetSize(24, 24)
    soundCheck.text:SetText("Alerts")
    soundCheck.text:ClearAllPoints()
    soundCheck.text:SetPoint("RIGHT", soundCheck, "LEFT", -2, 0)

    local statusSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusSummary:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -66)
    statusSummary:SetWidth(220)
    statusSummary:SetJustifyH("RIGHT")
    statusSummary:SetText("")

    panel.selectionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.selectionLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 195, 20)
    panel.selectionLabel:SetJustifyH("LEFT")
    panel.selectionLabel:SetText("|cff00ff00Selection|r")

    panel.selectionText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.selectionText:SetPoint("LEFT", panel.selectionLabel, "RIGHT", 8, 0)
    panel.selectionText:SetWidth(230)
    panel.selectionText:SetJustifyH("LEFT")
    panel.selectionText:SetText("|cffffd700None|r")

    local headers = {
        { label = "",          x = RESULTS_X + 2,   w = 34 },
        { label = "Name",      x = RESULTS_X + 36,  w = 240 },
        { label = "Threshold", x = RESULTS_X + 277, w = 90 },
        { label = "Scope",     x = RESULTS_X + 368, w = 56 },
        { label = "CD",        x = RESULTS_X + 425, w = 40 },
        { label = "On",        x = RESULTS_X + 466, w = 34 },
        { label = "Source",    x = RESULTS_X + 501, w = 98 },
        { label = "",          x = RESULTS_X + 600, w = 33 },
    }

    for _, col in ipairs(headers) do
        local hdr = CreateFrame("Frame", nil, panel)
        hdr:SetSize(col.w, 19)
        hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", col.x, -81)

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
        htxt:SetPoint("LEFT", 6, 0)
        htxt:SetText(col.label)
    end

    local function ShowRowTooltip(row, owner)
        if row.itemLink then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(row.itemLink)
            GameTooltip:Show()
            return
        end
        if row.displayName and row.displayName ~= "" then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.displayName, 1, 1, 1)
            GameTooltip:Show()
        end
    end

    panel.rows = {}
    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(ROW_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", RESULTS_X, -107 - ((i - 1) * ROW_HEIGHT))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, (i % 2 == 0) and 0.14 or 0.08)

        local selectedBg = row:CreateTexture(nil, "ARTWORK")
        selectedBg:SetAllPoints()
        selectedBg:SetColorTexture(1, 0.84, 0, 0.16)
        selectedBg:Hide()
        row.selectedBg = selectedBg

        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(1, 0.84, 0, 0.15)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        sep:SetSize(ROW_WIDTH, 1)

        local iconButton = CreateFrame("Button", nil, row)
        iconButton:SetSize(32, 32)
        iconButton:SetPoint("TOPLEFT", 0, -2)
        row.iconButton = iconButton

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
        nameLeft:SetPoint("LEFT", 34, 0)
        nameLeft:SetTexCoord(0, 0.078125, 0, 1.0)

        local nameRight = row:CreateTexture(nil, "BACKGROUND")
        nameRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameRight:SetSize(10, 32)
        nameRight:SetPoint("LEFT", 274, 0)
        nameRight:SetTexCoord(0.75, 0.828125, 0, 1.0)

        local nameMid = row:CreateTexture(nil, "BACKGROUND")
        nameMid:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameMid:SetPoint("LEFT", nameLeft, "RIGHT")
        nameMid:SetPoint("RIGHT", nameRight, "LEFT")
        nameMid:SetHeight(32)
        nameMid:SetTexCoord(0.078125, 0.75, 0, 1.0)

        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.name:SetPoint("LEFT", 40, 0)
        row.name:SetWidth(234)
        row.name:SetJustifyH("LEFT")

        row.threshold = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.threshold:SetPoint("LEFT", 278, 0)
        row.threshold:SetWidth(90)
        row.threshold:SetJustifyH("LEFT")

        row.scope = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.scope:SetPoint("LEFT", 369, 0)
        row.scope:SetWidth(56)
        row.scope:SetJustifyH("LEFT")

        row.cooldown = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.cooldown:SetPoint("LEFT", 426, 0)
        row.cooldown:SetWidth(40)
        row.cooldown:SetJustifyH("LEFT")

        row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.enabled:SetSize(20, 20)
        row.enabled:SetPoint("LEFT", 467, 0)

        row.source = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.source:SetPoint("LEFT", 501, 0)
        row.source:SetWidth(98)
        row.source:SetJustifyH("LEFT")

        row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.delete:SetSize(30, 16)
        row.delete:SetPoint("LEFT", 600, 0)
        row.delete:SetText("X")

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
        highlight:SetBlendMode("ADD")
        highlight:SetSize(599, 32)
        highlight:SetPoint("TOPLEFT", 33, -1)
        highlight:SetTexCoord(0, 1.0, 0, 0.578125)

        iconButton:SetScript("OnEnter", function(self)
            row:LockHighlight()
            ShowRowTooltip(row, self)
        end)
        iconButton:SetScript("OnLeave", function()
            row:UnlockHighlight()
            GameTooltip:Hide()
        end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row:SetScript("OnEnter", function(self)
            self:LockHighlight()
            ShowRowTooltip(self, self)
        end)
        row:SetScript("OnLeave", function(self)
            self:UnlockHighlight()
            GameTooltip:Hide()
        end)

        row:Hide()
        panel.rows[i] = row
    end

    panel.noResultsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noResultsText:SetPoint("TOP", parent, "TOP", 102, -210)
    panel.noResultsText:SetText("|cff888888No requests yet. Add one on the left or import a list.|r")
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
    panel.pageText:SetText("0 requests")

    local function SetStatus(message, color)
        local msg = tostring(message or "")
        if msg == "" then
            statusSummary:SetText("")
            return
        end
        local c = color or "|cff888888"
        statusSummary:SetText(c .. msg .. "|r")
    end

    local function RefreshImportDropdown()
        local options = { "__ALL__" }
        if MarketSync.GetAuctionatorShoppingListNames then
            for _, name in ipairs(MarketSync.GetAuctionatorShoppingListNames()) do
                options[#options + 1] = name
            end
        end
        panel.importListOptions = options

        local hasCurrent = false
        for _, v in ipairs(options) do
            if v == panel.importListName then
                hasCurrent = true
                break
            end
        end
        if not hasCurrent then
            panel.importListName = "__ALL__"
        end

        UIDropDownMenu_Initialize(importListDropdown, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            info.text = "All Lists"
            info.func = function()
                panel.importListName = "__ALL__"
                UIDropDownMenu_SetText(importListDropdown, "All Lists")
            end
            UIDropDownMenu_AddButton(info, level)

            for _, name in ipairs(panel.importListOptions or {}) do
                if name ~= "__ALL__" then
                    local opt = UIDropDownMenu_CreateInfo()
                    opt.text = name
                    opt.func = function()
                        panel.importListName = name
                        UIDropDownMenu_SetText(importListDropdown, name)
                    end
                    UIDropDownMenu_AddButton(opt, level)
                end
            end
        end)

        if panel.importListName == "__ALL__" then
            UIDropDownMenu_SetText(importListDropdown, "All Lists")
        else
            UIDropDownMenu_SetText(importListDropdown, panel.importListName)
        end
    end

    local function GetRequests()
        return (MarketSync.ListNotificationRequests and MarketSync.ListNotificationRequests()) or {}
    end

    local function SetManualScopeValue(scopeValue, explicitLabel)
        panel.manualScope = scopeValue
        if explicitLabel then
            UIDropDownMenu_SetText(manualScopeDropdown, explicitLabel)
        else
            UIDropDownMenu_SetText(manualScopeDropdown, ScopeLabel(scopeValue or "all"))
        end
    end

    local function GetSelectedRequests()
        local selected = {}
        for reqID in pairs(panel.selectedIDs or {}) do
            if panel.requestLookup and panel.requestLookup[reqID] then
                selected[#selected + 1] = panel.requestLookup[reqID]
            end
        end
        table.sort(selected, function(a, b)
            local nameA = tostring(a.displayName or a.matchValue or a.id or "")
            local nameB = tostring(b.displayName or b.matchValue or b.id or "")
            return nameA:lower() < nameB:lower()
        end)
        return selected
    end

    local function ApplyManualSelectionState()
        local selected = GetSelectedRequests()
        local count = #selected

        btnClearSelected:SetEnabled(count > 0)
        btnDeleteSelected:SetEnabled(count > 0)

        if count <= 0 then
            btnAdd:SetText("Add / Update")
            panel.selectionText:SetText("|cffffd700None|r")
            if panel.selectionLocked then
                nameBox:SetText(panel.manualDraftName or "")
                panel.selectionLocked = false
                panel.manualDraftName = nil
                if panel.manualScope == nil then
                    SetManualScopeValue("all")
                end
            end
            return
        end

        if not panel.selectionLocked then
            panel.manualDraftName = nameBox:GetText()
            panel.selectionLocked = true
        end

        btnAdd:SetText("Update Selected")

        local function SharedValue(readFn)
            local shared = nil
            for idx, req in ipairs(selected) do
                local value = readFn(req)
                if idx == 1 then
                    shared = value
                elseif shared ~= value then
                    return nil
                end
            end
            return shared
        end

        if count == 1 then
            local req = selected[1]
            local displayName = tostring(req.displayName or req.matchValue or req.id or "")
            nameBox:SetText(displayName)
            thresholdBox:SetText(FormatGoldInput(req.thresholdCopper or 0))
            cooldownBox:SetText(tostring(tonumber(req.cooldownSec) or 300))
            SetManualScopeValue(req.scope or "all")
            panel.selectionText:SetText("|cffffd700" .. Truncate(displayName, 28) .. "|r")
            return
        end

        nameBox:SetText(string.format("Multiple items selected (%d)", count))

        local sharedThreshold = SharedValue(function(req)
            return tonumber(req.thresholdCopper) or 0
        end)
        thresholdBox:SetText(sharedThreshold and FormatGoldInput(sharedThreshold) or "")

        local sharedCooldown = SharedValue(function(req)
            return tonumber(req.cooldownSec) or 300
        end)
        cooldownBox:SetText(sharedCooldown and tostring(sharedCooldown) or "")

        local sharedScope = SharedValue(function(req)
            return req.scope or "all"
        end)
        if sharedScope then
            SetManualScopeValue(sharedScope)
        else
            SetManualScopeValue(nil, "Mixed")
        end

        panel.selectionText:SetText(string.format("|cffffd700%d selected|r", count))
    end

    local function RefreshRows()
        local requests = GetRequests()
        local requestLookup = {}
        for _, req in ipairs(requests) do
            local reqID = tostring(req.id or "")
            if reqID ~= "" then
                requestLookup[reqID] = req
            end
        end
        panel.requestLookup = requestLookup

        for reqID in pairs(panel.selectedIDs) do
            if not requestLookup[reqID] then
                panel.selectedIDs[reqID] = nil
            end
        end

        local total = #requests
        local totalPages = math.max(1, math.ceil(total / ROWS_PER_PAGE))
        if panel.page < 0 then panel.page = 0 end
        if panel.page > (totalPages - 1) then panel.page = totalPages - 1 end

        local firstIndex = (panel.page * ROWS_PER_PAGE) + 1
        for i = 1, ROWS_PER_PAGE do
            local row = panel.rows[i]
            local req = requests[firstIndex + i - 1]
            if req then
                local reqID = tostring(req.id or "")
                local rowReqID = reqID
                local payload = BuildUpsertPayload(req, req.enabled ~= false)
                local itemName, itemLink, itemIcon = ResolveRequestVisual(req)
                local displayName = tostring(req.displayName or itemName or req.matchValue or rowReqID)

                row.reqID = rowReqID
                row.displayName = displayName
                row.itemLink = itemLink

                row.iconTex:SetTexture(itemIcon)
                row.name:SetText(itemLink or displayName)
                row.threshold:SetText(MoneyText(req.thresholdCopper or 0))
                row.scope:SetText(ScopeLabel(req.scope))
                row.cooldown:SetText(tostring(tonumber(req.cooldownSec) or 0))
                row.source:SetText(TrimText(req.importSource or "-"))

                local isSelected = panel.selectedIDs[rowReqID] and true or false
                row.selectedBg:SetShown(isSelected)

                row:SetScript("OnClick", function(self, button)
                    if not self.reqID or self.reqID == "" then
                        return
                    end
                    if self.itemLink and IsModifiedClick("CHATLINK") then
                        ChatEdit_InsertLink(self.itemLink)
                        return
                    end
                    if button == "RightButton" then
                        -- Build right-click context menu
                        local menuFrame = CreateFrame("Frame", "MarketSyncNotifContextMenu", UIParent, "UIDropDownMenuTemplate")
                        local isSelected = panel.selectedIDs[self.reqID] and true or false
                        local isEnabled = (payload.enabled ~= false)
                        UIDropDownMenu_Initialize(menuFrame, function(_, level)
                            local info
                            -- Select / Deselect
                            info = UIDropDownMenu_CreateInfo()
                            info.text = isSelected and "Deselect" or "Select"
                            info.notCheckable = true
                            info.func = function()
                                if isSelected then
                                    panel.selectedIDs[self.reqID] = nil
                                else
                                    panel.selectedIDs[self.reqID] = true
                                end
                                RefreshRows()
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Select Page
                            -- --- SUB-MENU LOGIC ---
                            if level == 2 then
                                if L_UIDROPDOWNMENU_MENU_VALUE == "SELECT_SUB" then
                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "All"
                                    info.notCheckable = true
                                    info.func = function()
                                        for _, r in ipairs(GetRequests()) do
                                            local rID = tostring(r.id or "")
                                            if rID ~= "" then panel.selectedIDs[rID] = true end
                                        end
                                        RefreshRows()
                                    end
                                    UIDropDownMenu_AddButton(info, level)

                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "Page"
                                    info.notCheckable = true
                                    info.func = function()
                                        local allReqs = GetRequests()
                                        local firstIdx = (panel.page * ROWS_PER_PAGE) + 1
                                        for i = 1, ROWS_PER_PAGE do
                                            local r = allReqs[firstIdx + i - 1]
                                            if r then
                                                local rID = tostring(r.id or "")
                                                if rID ~= "" then panel.selectedIDs[rID] = true end
                                            end
                                        end
                                        RefreshRows()
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end

                                if L_UIDROPDOWNMENU_MENU_VALUE == "SOUND_SUB" then
                                    local currentSound = MarketSyncDB.PerNotificationSounds and MarketSyncDB.PerNotificationSounds[rowReqID]
                                    
                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "Default (Global)"
                                    info.notCheckable = false
                                    info.checked = (currentSound == nil)
                                    info.func = function()
                                        if MarketSyncDB.PerNotificationSounds then
                                            MarketSyncDB.PerNotificationSounds[rowReqID] = nil
                                            RefreshRows()
                                        end
                                    end
                                    UIDropDownMenu_AddButton(info, level)

                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "Mute"
                                    info.notCheckable = false
                                    info.checked = (currentSound == 0)
                                    info.func = function()
                                        if not MarketSyncDB.PerNotificationSounds then MarketSyncDB.PerNotificationSounds = {} end
                                        MarketSyncDB.PerNotificationSounds[rowReqID] = 0
                                        RefreshRows()
                                    end
                                    UIDropDownMenu_AddButton(info, level)

                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "Preview Sound"
                                    info.notCheckable = true
                                    info.func = function()
                                        local sID = currentSound or MarketSyncDB.NotificationSoundID or 8959
                                        if sID and sID > 0 then PlaySound(sID, "Master") end
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                                return
                            end

                            -- --- LEVEL 1 MENU ---
                            
                            -- Open Item (Dashboard)
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "|cffffff00Open Item Dashboard|r"
                            info.notCheckable = true
                            info.func = function()
                                local _, _, _, hItemID = ResolveRequestVisual(req)
                                if hItemID and MarketSync.ShowItemDetail then
                                    MarketSync.ShowItemDetail(hItemID)
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Select Submenu
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Select..."
                            info.notCheckable = true
                            info.hasArrow = true
                            info.value = "SELECT_SUB"
                            UIDropDownMenu_AddButton(info, level)

                            -- History
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "History"
                            info.notCheckable = true
                            info.func = function()
                                if MarketSync.ShowItemHistory then
                                    local hName, hLink, hIcon, hItemID = ResolveRequestVisual(req)
                                    local hDBKey = hItemID and tostring(hItemID) or tostring(req.matchValue)
                                    local hPrice = nil
                                    if hDBKey and Auctionator and Auctionator.Database and Auctionator.Database.db then
                                        local d = Auctionator.Database.db[hDBKey]
                                        hPrice = d and d.m
                                    end
                                    MarketSync.ShowItemHistory(hDBKey, hLink, hName, hIcon, hPrice)
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Analytics
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Analytics"
                            info.notCheckable = true
                            info.func = function()
                                if MarketSync.ShowAnalytics then
                                    local hName, hLink, hIcon, hItemID = ResolveRequestVisual(req)
                                    local hDBKey = hItemID and tostring(hItemID) or tostring(req.matchValue)
                                    local hPrice = nil
                                    if hDBKey and Auctionator and Auctionator.Database and Auctionator.Database.db then
                                        local d = Auctionator.Database.db[hDBKey]
                                        hPrice = d and d.m
                                    end
                                    MarketSync.ShowAnalytics(hDBKey, hLink, hName, hIcon, hPrice)
                                end
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Notifications (Sound) Submenu
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Notifications..."
                            info.notCheckable = true
                            info.hasArrow = true
                            info.value = "SOUND_SUB"
                            UIDropDownMenu_AddButton(info, level)

                            -- Re-resolve (Only if not already an itemID match)
                            if req.matchType ~= "itemID" then
                                local resolvedID = MarketSync.ResolveItemID(displayName)
                                if resolvedID then
                                    info = UIDropDownMenu_CreateInfo()
                                    info.text = "|cff00ff00Re-resolve to ItemID|r"
                                    info.notCheckable = true
                                    info.func = function()
                                        payload.matchType = "itemID"
                                        payload.matchValue = resolvedID
                                        if MarketSync.UpsertNotificationRequest then
                                            MarketSync.UpsertNotificationRequest(payload)
                                        end
                                        SetStatus("Resolved " .. displayName .. " to itemID: " .. resolvedID, "|cff00ff00")
                                        RefreshRows()
                                    end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                            end

                            -- Enable / Disable
                            info = UIDropDownMenu_CreateInfo()
                            info.text = isEnabled and "Disable" or "Enable"
                            info.notCheckable = true
                            info.func = function()
                                payload.enabled = not isEnabled
                                if MarketSync.UpsertNotificationRequest then
                                    MarketSync.UpsertNotificationRequest(payload)
                                end
                                RefreshRows()
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Delete
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "|cffff4444Delete|r"
                            info.notCheckable = true
                            info.func = function()
                                if MarketSync.DeleteNotificationRequest then
                                    MarketSync.DeleteNotificationRequest(rowReqID)
                                end
                                panel.selectedIDs[rowReqID] = nil
                                SetStatus("Deleted request: " .. displayName, "|cffffaa00")
                                RefreshRows()
                            end
                            UIDropDownMenu_AddButton(info, level)

                            -- Cancel
                            info = UIDropDownMenu_CreateInfo()
                            info.text = "Cancel"
                            info.notCheckable = true
                            info.func = function() end
                            UIDropDownMenu_AddButton(info, level)
                        end, "MENU")
                        ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
                        return
                    end
                    if panel.selectedIDs[self.reqID] then
                        panel.selectedIDs[self.reqID] = nil
                    else
                        panel.selectedIDs[self.reqID] = true
                    end
                    RefreshRows()
                end)

                row.iconButton:SetScript("OnClick", function()
                    if row.itemLink and IsModifiedClick("CHATLINK") then
                        ChatEdit_InsertLink(row.itemLink)
                        return
                    end
                    if panel.selectedIDs[rowReqID] then
                        panel.selectedIDs[rowReqID] = nil
                    else
                        panel.selectedIDs[rowReqID] = true
                    end
                    RefreshRows()
                end)

                row.enabled:SetChecked(req.enabled ~= false)
                row.enabled:SetScript("OnClick", function(btn)
                    payload.enabled = btn:GetChecked() and true or false
                    if MarketSync.UpsertNotificationRequest then
                        MarketSync.UpsertNotificationRequest(payload)
                    end
                    RefreshRows()
                end)

                row.delete:SetScript("OnClick", function()
                    if MarketSync.DeleteNotificationRequest then
                        MarketSync.DeleteNotificationRequest(rowReqID)
                    end
                    panel.selectedIDs[rowReqID] = nil
                    SetStatus("Deleted request: " .. displayName, "|cffffaa00")
                    RefreshRows()
                end)

                row:Show()
            else
                row.reqID = nil
                row.displayName = nil
                row.itemLink = nil
                row:Hide()
            end
        end

        local pageShown = (total > 0) and (panel.page + 1) or 1
        panel.pageText:SetText(string.format("%d requests (Page %d/%d)", total, pageShown, totalPages))
        prevBtn:SetEnabled(panel.page > 0)
        nextBtn:SetEnabled(total > 0 and panel.page < (totalPages - 1))
        panel.noResultsText:SetShown(total == 0)

        ApplyManualSelectionState()
    end

    btnAdd:SetScript("OnClick", function()
        if not MarketSync.UpsertNotificationRequest then
            SetStatus("Notifications module unavailable.", "|cffff4444")
            return
        end

        local selected = GetSelectedRequests()
        if #selected > 0 then
            local thresholdRaw = TrimText(thresholdBox:GetText())
            local thresholdValue = nil
            if thresholdRaw ~= "" then
                thresholdValue = ParseGoldToCopper(thresholdRaw)
            end

            local cooldownRaw = TrimText(cooldownBox:GetText())
            local cooldownValue = nil
            if cooldownRaw ~= "" then
                cooldownValue = math.max(0, ReadInt(cooldownBox, 300))
                if cooldownValue <= 0 then
                    cooldownValue = 300
                end
            end

            local updated = 0
            for _, req in ipairs(selected) do
                local payload = BuildUpsertPayload(req, req.enabled ~= false)
                if thresholdValue ~= nil then
                    payload.thresholdCopper = thresholdValue
                    payload.enabled = thresholdValue > 0
                end
                if cooldownValue ~= nil then
                    payload.cooldownSec = cooldownValue
                end
                if panel.manualScope ~= nil then
                    payload.scope = panel.manualScope
                end

                if MarketSync.UpsertNotificationRequest(payload) then
                    updated = updated + 1
                end
            end

            if updated > 0 then
                SetStatus(string.format("Updated %d selected request(s).", updated), "|cff00ff00")
            else
                SetStatus("No selected requests were updated.", "|cffff4444")
            end
            RefreshRows()
            return
        end

        local resolved = ResolveManualRequest(nameBox:GetText())
        if not resolved then
            SetStatus("Enter a target item name, link, or itemID.", "|cffff4444")
            return
        end

        local threshold = ParseGoldToCopper(thresholdBox:GetText())
        local cooldown = math.max(0, ReadInt(cooldownBox, 300))
        if cooldown <= 0 then cooldown = 300 end

        local req = MarketSync.UpsertNotificationRequest({
            matchType = resolved.matchType,
            matchValue = resolved.matchValue,
            displayName = resolved.displayName,
            thresholdCopper = threshold,
            scope = panel.manualScope or "all",
            variantMode = "any_suffix",
            cooldownSec = cooldown,
            enabled = threshold > 0,
        })

        if req then
            SetStatus("Saved request for " .. tostring(req.displayName or "target"), "|cff00ff00")
            RefreshRows()
        else
            SetStatus("Failed to save request.", "|cffff4444")
        end
    end)

    btnImport:SetScript("OnClick", function()
        if not MarketSync.ImportNotificationRequestsFromAuctionator then
            SetStatus("Auctionator import API unavailable.", "|cffff4444")
            return
        end

        local listNames = nil
        if panel.importListName ~= "__ALL__" then
            listNames = { panel.importListName }
        end

        local fallbackThreshold = ParseGoldToCopper(importFallbackBox:GetText())
        local cooldown = math.max(0, ReadInt(importCooldownBox, 300))
        if cooldown <= 0 then cooldown = 300 end

        local imported, err = MarketSync.ImportNotificationRequestsFromAuctionator(listNames, {
            thresholdCopper = fallbackThreshold,
            useListMaxPrice = useListMaxCheck:GetChecked() and true or false,
            scope = panel.importScope,
            cooldownSec = cooldown,
            enabledDefault = nil,
        })

        if imported and imported > 0 then
            SetStatus(string.format("Imported %d request(s).", imported), "|cff00ff00")
        else
            SetStatus("No requests imported. " .. tostring(err or ""), "|cffffaa00")
        end
        RefreshRows()
    end)

    btnRefreshLists:SetScript("OnClick", function()
        RefreshImportDropdown()
        SetStatus("Shopping lists refreshed.", "|cff00ff00")
    end)

    btnRefresh:SetScript("OnClick", function()
        RefreshImportDropdown()
        RefreshRows()
        SetStatus("Notification view refreshed.", "|cff00ff00")
    end)

    btnClearSelected:SetScript("OnClick", function()
        panel.selectedIDs = {}
        RefreshRows()
        SetStatus("Selection cleared.", "|cffffaa00")
    end)

    btnDeleteSelected:SetScript("OnClick", function()
        if not MarketSync.DeleteNotificationRequest then
            SetStatus("Delete API unavailable.", "|cffff4444")
            return
        end

        local deleted = 0
        for reqID in pairs(panel.selectedIDs) do
            MarketSync.DeleteNotificationRequest(reqID)
            deleted = deleted + 1
        end
        panel.selectedIDs = {}

        if deleted > 0 then
            SetStatus(string.format("Deleted %d request(s).", deleted), "|cffffaa00")
        else
            SetStatus("No selected requests to delete.", "|cffff4444")
        end
        RefreshRows()
    end)

    prevBtn:SetScript("OnClick", function()
        panel.page = panel.page - 1
        RefreshRows()
    end)

    nextBtn:SetScript("OnClick", function()
        panel.page = panel.page + 1
        RefreshRows()
    end)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if self.page > 0 then
                self.page = self.page - 1
                RefreshRows()
            end
            return
        end

        local total = #(GetRequests())
        local maxPage = math.max(0, math.ceil(total / ROWS_PER_PAGE) - 1)
        if self.page < maxPage then
            self.page = self.page + 1
            RefreshRows()
        end
    end)

    panel:SetScript("OnShow", function()
        if soundCheck then
            soundCheck:SetChecked(MarketSyncDB and MarketSyncDB.EnableNotificationSounds ~= false)
        end
        RefreshImportDropdown()
        RefreshRows()
        SetStatus("")
    end)

    soundCheck:SetScript("OnClick", function(self)
        if MarketSyncDB then
            MarketSyncDB.EnableNotificationSounds = self:GetChecked() and true or false
        end
    end)

    nameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        btnAdd:Click()
    end)
    nameBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    RefreshImportDropdown()
    RefreshRows()
    SetStatus("")

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
