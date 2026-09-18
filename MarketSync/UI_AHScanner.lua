-- ================================================================
-- MarketSync - Built-in Auction House Scanner Page & Quick Lists
-- Dual-pane layout: Multi-list targeted scanning + Full AH replicate scan
-- ================================================================

MarketSync = MarketSync or {}

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

local function CreateCustomCheckBox(parent, onClick)
    local cb = CreateFrame("Button", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    cb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    cb:SetBackdropColor(0.08, 0.10, 0.13, 0.95)
    cb:SetBackdropBorderColor(0.35, 0.38, 0.45, 0.8)

    cb.checkTex = cb:CreateTexture(nil, "OVERLAY")
    cb.checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.checkTex:SetSize(18, 18)
    cb.checkTex:SetPoint("CENTER", 0, 0)
    cb.checkTex:Hide()

    cb.checked = false
    cb:SetScript("OnClick", function(self)
        self.checked = not self.checked
        if self.checked then
            self.checkTex:Show()
        else
            self.checkTex:Hide()
        end
        if onClick then onClick(self.checked) end
    end)

    cb.SetCheckedState = function(self, state)
        self.checked = state and true or false
        if self.checked then
            self.checkTex:Show()
        else
            self.checkTex:Hide()
        end
    end
    return cb
end

function MarketSync.CreateAHScannerPanel(parent)
    local panel = CreateFrame("Frame", "MarketSyncAHScannerFrame", parent)
    panel:SetAllPoints(parent)

    -- Left Pane: Scan Lists Management (260px wide)
    local leftInset = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    leftInset:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    leftInset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    leftInset:SetWidth(260)
    leftInset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    leftInset:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
    leftInset:SetBackdropBorderColor(0.20, 0.22, 0.26, 0.90)

    -- Right Pane: Scan Operations & Results Feed
    local rightInset = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    rightInset:SetPoint("TOPLEFT", leftInset, "TOPRIGHT", 6, 0)
    rightInset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    rightInset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    rightInset:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
    rightInset:SetBackdropBorderColor(0.20, 0.22, 0.26, 0.90)

    -- ================================================================
    -- LEFT PANE: MULTI-LIST CHECKLIST & SELECTION
    -- ================================================================
    local leftHeader = CreateFrame("Frame", nil, leftInset)
    leftHeader:SetPoint("TOPLEFT", 6, -6)
    leftHeader:SetPoint("TOPRIGHT", -6, -6)
    leftHeader:SetHeight(26)

    local listTitle = leftHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    listTitle:SetPoint("LEFT", 4, 0)
    listTitle:SetText("|cFFFFD100Scan Lists|r")

    local newListBtn = CreateFrame("Button", nil, leftHeader, "UIPanelButtonTemplate")
    newListBtn:SetSize(58, 22)
    newListBtn:SetPoint("RIGHT", -54, 0)
    newListBtn:SetText("+ New")

    local delListBtn = CreateFrame("Button", nil, leftHeader, "UIPanelButtonTemplate")
    delListBtn:SetSize(50, 22)
    delListBtn:SetPoint("RIGHT", 0, 0)
    delListBtn:SetText("Delete")

    -- Multi-list checklist scroll area
    local listScroll = CreateFrame("ScrollFrame", "MarketSyncScanListScroll", leftInset, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -4)
    listScroll:SetPoint("RIGHT", -22, 0)
    listScroll:SetHeight(130)

    local listScrollContent = CreateFrame("Frame", nil, listScroll)
    listScrollContent:SetSize(232, 1)
    listScroll:SetScrollChild(listScrollContent)

    -- Batch selection buttons
    local selectAllBtn = CreateFrame("Button", nil, leftInset, "UIPanelButtonTemplate")
    selectAllBtn:SetSize(54, 20)
    selectAllBtn:SetPoint("TOPLEFT", listScroll, "BOTTOMLEFT", 2, -6)
    selectAllBtn:SetText("All")

    local deselectAllBtn = CreateFrame("Button", nil, leftInset, "UIPanelButtonTemplate")
    deselectAllBtn:SetSize(54, 20)
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    deselectAllBtn:SetText("None")

    -- Scan Selected Lists CTA Button
    local scanSelectedBtn = CreateFrame("Button", nil, leftInset, "UIPanelButtonTemplate")
    scanSelectedBtn:SetPoint("TOPLEFT", selectAllBtn, "BOTTOMLEFT", 0, -4)
    scanSelectedBtn:SetPoint("RIGHT", -6, 0)
    scanSelectedBtn:SetHeight(24)
    scanSelectedBtn:SetText("Scan Selected Lists")

    -- Divider between Lists Checklist and Active List Items
    local divider = leftInset:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", scanSelectedBtn, "BOTTOMLEFT", -2, -8)
    divider:SetPoint("RIGHT", -4, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(0.20, 0.22, 0.26, 0.90)

    -- Active List Header
    local activeListLabel = leftInset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeListLabel:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 4, -6)
    activeListLabel:SetPoint("RIGHT", -6, 0)
    activeListLabel:SetJustifyH("LEFT")
    activeListLabel:SetText("List Items: |cFFFFD100Favorites|r")

    -- Active List Items ScrollFrame
    local itemsScroll = CreateFrame("ScrollFrame", "MarketSyncScanItemsScroll", leftInset, "UIPanelScrollFrameTemplate")
    itemsScroll:SetPoint("TOPLEFT", activeListLabel, "BOTTOMLEFT", 0, -4)
    itemsScroll:SetPoint("BOTTOMRIGHT", -22, 34)

    local itemsScrollContent = CreateFrame("Frame", nil, itemsScroll)
    itemsScrollContent:SetSize(232, 1)
    itemsScroll:SetScrollChild(itemsScrollContent)

    local itemsEmptyText = itemsScroll:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemsEmptyText:SetPoint("CENTER", 0, 0)
    itemsEmptyText:SetText("No items in list.\nType name/ID below.")

    -- Quick Add Bar
    local addBox = CreateFrame("EditBox", nil, leftInset, "InputBoxTemplate")
    addBox:SetPoint("BOTTOMLEFT", 8, 8)
    addBox:SetPoint("BOTTOMRIGHT", -6, 8)
    addBox:SetHeight(20)
    addBox:SetAutoFocus(false)
    addBox:SetFontObject("GameFontHighlightSmall")
    addBox:SetText("Drop item or enter ID...")

    addBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Drop item or enter ID..." then self:SetText("") end
    end)
    addBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Drop item or enter ID...") end
    end)

    -- State
    local selectedListName = "Favorites"
    local checkedLists = { ["Favorites"] = true }
    local checklistRows = {}
    local itemRows = {}

    local RefreshListsView
    local RefreshActiveItemsView

    addBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" and text ~= "Drop item or enter ID..." and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(selectedListName, text)
            self:SetText("")
            self:ClearFocus()
            RefreshActiveItemsView()
            RefreshListsView()
        end
    end)

    addBox:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(selectedListName, itemID or itemLink)
            ClearCursor()
            RefreshActiveItemsView()
            RefreshListsView()
        end
    end)

    -- New List Popup
    newListBtn:SetScript("OnClick", function()
        StaticPopupDialogs["MARKETSYNC_SCANNER_NEW_LIST"] = {
            text = "Enter name for new Shopping List:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                local text = eb and eb:GetText()
                if text and text ~= "" and MarketSync.Favorites then
                    local ok = MarketSync.Favorites.CreateList(text)
                    if ok then
                        selectedListName = text
                        checkedLists[text] = true
                        RefreshListsView()
                        RefreshActiveItemsView()
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MARKETSYNC_SCANNER_NEW_LIST")
    end)

    -- Delete List Button
    delListBtn:SetScript("OnClick", function()
        if selectedListName == "Favorites" then
            print("|cFFFF4444[MarketSync]|r Cannot delete the default Favorites list.")
            return
        end
        if MarketSync.Favorites then
            MarketSync.Favorites.DeleteList(selectedListName)
            checkedLists[selectedListName] = nil
            selectedListName = "Favorites"
            RefreshListsView()
            RefreshActiveItemsView()
        end
    end)

    -- Checklist updater
    RefreshListsView = function()
        local lists = (MarketSync.Favorites and MarketSync.Favorites.GetLists()) or { "Favorites" }
        local rowH = 24
        local totalSelectedItems = 0

        for i = 1, math.max(#lists, #checklistRows) do
            local row = checklistRows[i]
            local listName = lists[i]

            if listName then
                if not row then
                    row = CreateFrame("Frame", nil, listScrollContent, "BackdropTemplate")
                    row:SetHeight(rowH)
                    row:SetPoint("LEFT", 0, 0)
                    row:SetPoint("RIGHT", 0, 0)
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

                    row.cb = CreateCustomCheckBox(row, function(checked)
                        checkedLists[row.listName] = checked
                        RefreshListsView()
                    end)
                    row.cb:SetPoint("LEFT", 4, 0)

                    row.btn = CreateFrame("Button", nil, row)
                    row.btn:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
                    row.btn:SetPoint("RIGHT", -40, 0)
                    row.btn:SetHeight(rowH)

                    row.name = row.btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", 0, 0)
                    row.name:SetJustifyH("LEFT")

                    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.count:SetPoint("RIGHT", -4, 0)

                    checklistRows[i] = row
                end

                row.listName = listName
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(listName) or {}
                local count = #items
                if checkedLists[listName] then
                    totalSelectedItems = totalSelectedItems + count
                end

                row.cb:SetCheckedState(checkedLists[listName] or false)
                row.name:SetText(listName)
                row.count:SetText(string.format("|cff888888(%d)|r", count))

                if listName == selectedListName then
                    row:SetBackdropColor(0.20, 0.16, 0.05, 0.85)
                    row.name:SetTextColor(1, 0.82, 0)
                elseif i % 2 == 0 then
                    row:SetBackdropColor(0.08, 0.10, 0.13, 0.5)
                    row.name:SetTextColor(0.85, 0.85, 0.85)
                else
                    row:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
                    row.name:SetTextColor(0.85, 0.85, 0.85)
                end

                row.btn:SetScript("OnClick", function()
                    selectedListName = listName
                    RefreshListsView()
                    RefreshActiveItemsView()
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end

        listScrollContent:SetHeight(math.max(1, #lists * rowH))
        scanSelectedBtn:SetText(string.format("Scan Selected (%d items)", totalSelectedItems))
        activeListLabel:SetText(string.format("List Items: |cFFFFD100%s|r", selectedListName))
    end

    -- Active list items updater
    RefreshActiveItemsView = function()
        local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(selectedListName) or {}
        local rowH = 22

        if #items == 0 then
            itemsEmptyText:Show()
        else
            itemsEmptyText:Hide()
        end

        for i = 1, math.max(#items, #itemRows) do
            local row = itemRows[i]
            local item = items[i]

            if item then
                if not row then
                    row = CreateFrame("Frame", nil, itemsScrollContent)
                    row:SetHeight(rowH)
                    row:SetPoint("LEFT", 0, 0)
                    row:SetPoint("RIGHT", 0, 0)

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(18, 18)
                    row.icon:SetPoint("LEFT", 2, 0)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", -24, 0)
                    row.name:SetJustifyH("LEFT")

                    row.delBtn = CreateFrame("Button", nil, row)
                    row.delBtn:SetSize(16, 16)
                    row.delBtn:SetPoint("RIGHT", -2, 0)
                    row.delBtn.text = row.delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.delBtn.text:SetPoint("CENTER")
                    row.delBtn.text:SetText("|cFFFF4444x|r")

                    itemRows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                row.icon:SetTexture(item.icon)
                local colorHex = "ffffffff"
                if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] then
                    colorHex = ITEM_QUALITY_COLORS[item.quality].hex or "ffffffff"
                end
                row.name:SetText(string.format("|c%s%s|r", colorHex, item.name))

                row.delBtn:SetScript("OnClick", function()
                    if MarketSync.Favorites then
                        MarketSync.Favorites.RemoveFromList(selectedListName, item.itemID)
                        RefreshActiveItemsView()
                        RefreshListsView()
                    end
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end

        itemsScrollContent:SetHeight(math.max(1, #items * rowH))
    end

    selectAllBtn:SetScript("OnClick", function()
        local lists = (MarketSync.Favorites and MarketSync.Favorites.GetLists()) or {}
        for _, name in ipairs(lists) do
            checkedLists[name] = true
        end
        RefreshListsView()
    end)

    deselectAllBtn:SetScript("OnClick", function()
        checkedLists = {}
        RefreshListsView()
    end)

    scanSelectedBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            local activeNames = {}
            for name, isChecked in pairs(checkedLists) do
                if isChecked then table.insert(activeNames, name) end
            end
            if #activeNames > 0 then
                MarketSync.Scanner.ScanMultipleLists(activeNames)
            else
                print("|cFFFF4444[MarketSync]|r Please check at least one list to scan.")
            end
        end
    end)

    -- ================================================================
    -- RIGHT PANE: SCAN CONTROLS & LIVE RESULTS FEED
    -- ================================================================
    local rightHeader = CreateFrame("Frame", nil, rightInset)
    rightHeader:SetPoint("TOPLEFT", 10, -10)
    rightHeader:SetPoint("TOPRIGHT", -10, -10)
    rightHeader:SetHeight(48)

    local feedTitle = rightHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    feedTitle:SetPoint("TOPLEFT", 2, 0)
    feedTitle:SetText("|cFF00FF00MarketSync|r |cFFFFD100Scanner Feed|r")

    local statusText = rightHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", feedTitle, "BOTTOMLEFT", 0, -4)
    statusText:SetText("Ready to scan")

    -- Scan All (Full AH) Button
    local scanAllBtn = CreateFrame("Button", nil, rightHeader, "UIPanelButtonTemplate")
    scanAllBtn:SetSize(148, 26)
    scanAllBtn:SetPoint("TOPRIGHT", -206, 0)
    scanAllBtn:SetText("Scan All (Full AH)")

    -- Scan Watched Button
    local scanWatchedBtn = CreateFrame("Button", nil, rightHeader, "UIPanelButtonTemplate")
    scanWatchedBtn:SetSize(116, 26)
    scanWatchedBtn:SetPoint("LEFT", scanAllBtn, "RIGHT", 6, 0)
    scanWatchedBtn:SetText("Scan Watched")

    -- Stop Scan Button
    local stopBtn = CreateFrame("Button", nil, rightHeader, "UIPanelButtonTemplate")
    stopBtn:SetSize(76, 26)
    stopBtn:SetPoint("LEFT", scanWatchedBtn, "RIGHT", 6, 0)
    stopBtn:SetText("Stop")
    stopBtn:Disable()

    scanAllBtn:SetScript("OnClick", function()
        if MarketSync.Scanner and MarketSync.Scanner.StartFullScan then
            MarketSync.Scanner.StartFullScan()
        end
    end)

    scanWatchedBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            MarketSync.Scanner.ScanWatched()
        end
    end)

    stopBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            MarketSync.Scanner.Cancel("Stopped by user")
        end
    end)

    -- Progress Bar
    local progressBar = CreateFrame("StatusBar", nil, rightInset, "BackdropTemplate")
    progressBar:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 2, -6)
    progressBar:SetPoint("TOPRIGHT", rightHeader, "BOTTOMRIGHT", -2, -6)
    progressBar:SetHeight(16)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.1, 0.75, 0.2, 0.9)
    progressBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    progressBar:SetBackdropColor(0.08, 0.10, 0.13, 0.95)
    progressBar:SetBackdropBorderColor(0.20, 0.22, 0.26, 0.90)
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)

    local progressLabel = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressLabel:SetPoint("CENTER")
    progressLabel:SetText("Idle")

    -- Column Headers using modern dark AH slate style
    local colHeaders = {
        { name = "Scanned Item", width = 230, sortKey = "name" },
        { name = "Unit Buyout", width = 110, sortKey = "unitPrice" },
        { name = "Available", width = 80, sortKey = "available" },
        { name = "Time", width = 70, sortKey = "time" },
    }

    local colContainer = CreateFrame("Frame", nil, rightInset)
    colContainer:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -8)
    colContainer:SetPoint("TOPRIGHT", progressBar, "BOTTOMRIGHT", 0, -8)
    colContainer:SetHeight(20)

    local startX = 2
    for _, col in ipairs(colHeaders) do
        local hdr = MarketSync.CreateAHColumnHeader and MarketSync.CreateAHColumnHeader(colContainer, col.width, 20, col.name, col.sortKey)
        if not hdr then
            hdr = CreateFrame("Button", nil, colContainer, "BackdropTemplate")
            hdr:SetSize(col.width, 20)
            hdr.label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hdr.label:SetPoint("LEFT", 6, 0)
            hdr.label:SetText(col.name)
        end
        hdr:SetPoint("TOPLEFT", colContainer, "TOPLEFT", startX, 0)
        startX = startX + col.width
    end

    -- Results Scroll Frame
    local resultsScroll = CreateFrame("ScrollFrame", "MarketSyncAHScanResultsScroll", rightInset, "UIPanelScrollFrameTemplate")
    resultsScroll:SetPoint("TOPLEFT", colContainer, "BOTTOMLEFT", 0, -4)
    resultsScroll:SetPoint("BOTTOMRIGHT", -22, 10)

    local resultsContent = CreateFrame("Frame", nil, resultsScroll)
    resultsContent:SetSize(480, 1)
    resultsScroll:SetScrollChild(resultsContent)

    local resultRows = {}
    local function UpdateResultsTable()
        local results = (MarketSync.Scanner and MarketSync.Scanner.RecentResults) or {}
        local rowH = 26

        for i = 1, math.max(#results, #resultRows) do
            local row = resultRows[i]
            local data = results[i]

            if data then
                if not row then
                    row = CreateFrame("Button", nil, resultsContent, "BackdropTemplate")
                    row:SetHeight(rowH)
                    row:SetPoint("LEFT", 2, 0)
                    row:SetPoint("RIGHT", -2, 0)
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", 6, 0)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                    row.name:SetPoint("RIGHT", -260, 0)
                    row.name:SetJustifyH("LEFT")

                    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.price:SetPoint("RIGHT", -150, 0)

                    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.qty:SetPoint("RIGHT", -75, 0)

                    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    row.time:SetPoint("RIGHT", -10, 0)

                    resultRows[i] = row
                end

                row.data = data
                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                if i % 2 == 0 then
                    row:SetBackdropColor(0.08, 0.09, 0.12, 0.50)
                else
                    row:SetBackdropColor(0.04, 0.05, 0.07, 0.50)
                end

                row.icon:SetTexture(data.icon)
                local colorHex = "ffffffff"
                if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[data.quality] then
                    colorHex = ITEM_QUALITY_COLORS[data.quality].hex or "ffffffff"
                end
                row.name:SetText(string.format("|c%s%s|r", colorHex, data.name))
                row.price:SetText(MarketSync.FormatMoney and MarketSync.FormatMoney(data.unitPrice) or tostring(data.unitPrice))
                row.qty:SetText(tostring(data.available or 1))
                row.time:SetText(date("%H:%M:%S", data.time))

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.18, 0.22, 0.30, 0.60)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if data.itemKey and data.itemKey.itemID then
                        local link = select(2, SafeGetItemInfo(data.itemKey.itemID))
                        if link and GameTooltip.SetHyperlink then
                            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                        else
                            GameTooltip:SetText(data.name, 1, 1, 1)
                        end
                    else
                        GameTooltip:SetText(data.name, 1, 1, 1)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF00FF00Left-Click|r: Search in Auction House", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)

                row:SetScript("OnLeave", function(self)
                    if i % 2 == 0 then
                        self:SetBackdropColor(0.08, 0.09, 0.12, 0.50)
                    else
                        self:SetBackdropColor(0.04, 0.05, 0.07, 0.50)
                    end
                    GameTooltip:Hide()
                end)

                row:SetScript("OnClick", function(self, mouseButton)
                    if MarketSync.SearchInAuctionHouse and data.itemID then
                        MarketSync.SearchInAuctionHouse(data.itemID)
                    end
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end

        resultsContent:SetHeight(math.max(1, #results * rowH))
    end

    -- Cooldown & Scanner Update Loop
    local function UpdateScannerState()
        local scanner = MarketSync.Scanner
        if not scanner then return end

        statusText:SetText(scanner.Status or "Ready")

        -- Cooldown timer check on Scan All button
        local cd = (scanner.GetFullScanCooldownRemaining and scanner.GetFullScanCooldownRemaining()) or 0
        if scanner.Active then
            stopBtn:Enable()
            scanWatchedBtn:Disable()
            scanAllBtn:Disable()
            scanSelectedBtn:Disable()
            if scanner.Progress and scanner.Progress.total > 0 then
                progressBar:SetMinMaxValues(0, scanner.Progress.total)
                progressBar:SetValue(scanner.Progress.current)
                progressLabel:SetText(string.format("%d / %d (%d%%)",
                    scanner.Progress.current,
                    scanner.Progress.total,
                    math.floor((scanner.Progress.current / scanner.Progress.total) * 100)))
            else
                progressLabel:SetText(scanner.Status or "Scanning...")
            end
        else
            stopBtn:Disable()
            scanWatchedBtn:Enable()
            scanSelectedBtn:Enable()

            if cd > 0 then
                scanAllBtn:Disable()
                local mins = math.floor(cd / 60)
                local secs = cd % 60
                scanAllBtn:SetText(string.format("Scan All (%dm %02ds)", mins, secs))
            else
                scanAllBtn:Enable()
                scanAllBtn:SetText("Scan All (Full AH)")
            end

            progressBar:SetValue(progressBar:GetMinMaxValues())
            progressLabel:SetText(scanner.Status or "Ready")
        end

        UpdateResultsTable()
    end

    if MarketSync.Scanner then
        MarketSync.Scanner.RegisterCallback(UpdateScannerState)
    end
    if MarketSync.Favorites then
        MarketSync.Favorites.RegisterCallback(function()
            RefreshListsView()
            RefreshActiveItemsView()
        end)
    end

    -- Periodic ticker for cooldown countdown while panel is open
    local tickerTime = 0
    panel:SetScript("OnUpdate", function(self, elapsed)
        tickerTime = tickerTime + elapsed
        if tickerTime >= 1.0 then
            tickerTime = 0
            if panel:IsShown() and MarketSync.Scanner and not MarketSync.Scanner.Active then
                local cd = (MarketSync.Scanner.GetFullScanCooldownRemaining and MarketSync.Scanner.GetFullScanCooldownRemaining()) or 0
                if cd > 0 then
                    local mins = math.floor(cd / 60)
                    local secs = cd % 60
                    scanAllBtn:SetText(string.format("Scan All (%dm %02ds)", mins, secs))
                else
                    scanAllBtn:Enable()
                    scanAllBtn:SetText("Scan All (Full AH)")
                end
            end
        end
    end)

    panel.OnShow = function()
        RefreshListsView()
        RefreshActiveItemsView()
        UpdateScannerState()
    end

    RefreshListsView()
    RefreshActiveItemsView()
    UpdateScannerState()

    return panel
end
