-- ================================================================
-- MarketSync - Built-in Auction House Scanner Page & Quick Lists
-- Interactive AH scanning dashboard with preferred lists popup
-- ================================================================

MarketSync = MarketSync or {}

function MarketSync.CreateAHScannerPanel(parent)
    local panel = CreateFrame("Frame", "MarketSyncAHScannerFrame", parent, "BackdropTemplate")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
    panel:SetBackdropBorderColor(0.2, 0.25, 0.3, 0.8)

    -- Top Header / Control Bar
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 10, -10)
    header:SetPoint("TOPRIGHT", -10, -10)
    header:SetHeight(50)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 5, -5)
    title:SetText("|cFF00FF00MarketSync|r |cFFFFD100Scanner|r")

    local statusText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    statusText:SetText("Ready to scan")

    -- Scan Watched Button
    local scanWatchedBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    scanWatchedBtn:SetSize(130, 26)
    scanWatchedBtn:SetPoint("TOPRIGHT", -230, -5)
    scanWatchedBtn:SetText("Scan Watched")
    scanWatchedBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            MarketSync.Scanner.ScanWatched()
        end
    end)

    -- Quick Lists Button
    local quickListsBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    quickListsBtn:SetSize(120, 26)
    quickListsBtn:SetPoint("LEFT", scanWatchedBtn, "RIGHT", 8, 0)
    quickListsBtn:SetText("⭐ Quick Lists")

    -- Stop Scan Button
    local stopBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    stopBtn:SetSize(90, 26)
    stopBtn:SetPoint("LEFT", quickListsBtn, "RIGHT", 8, 0)
    stopBtn:SetText("Stop")
    stopBtn:Disable()
    stopBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            MarketSync.Scanner.Cancel("Stopped by user")
        end
    end)

    -- Progress Bar
    local progressBar = CreateFrame("StatusBar", nil, panel, "BackdropTemplate")
    progressBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    progressBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)
    progressBar:SetHeight(16)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.1, 0.75, 0.2, 0.9)
    progressBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    progressBar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    progressBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)

    local progressLabel = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressLabel:SetPoint("CENTER")
    progressLabel:SetText("Idle")

    -- Table Header
    local tableHeader = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    tableHeader:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -10)
    tableHeader:SetPoint("TOPRIGHT", progressBar, "BOTTOMRIGHT", 0, -10)
    tableHeader:SetHeight(24)
    tableHeader:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    tableHeader:SetBackdropColor(0.12, 0.14, 0.18, 0.9)

    local thItem = tableHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thItem:SetPoint("LEFT", 35, 0)
    thItem:SetText("Scanned Item")

    local thPrice = tableHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thPrice:SetPoint("RIGHT", -150, 0)
    thPrice:SetText("Unit Buyout")

    local thQty = tableHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thQty:SetPoint("RIGHT", -70, 0)
    thQty:SetText("Available")

    local thTime = tableHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thTime:SetPoint("RIGHT", -15, 0)
    thTime:SetText("Time")

    -- Results Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "MarketSyncAHScanScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth() or 700, 1)
    scrollFrame:SetScrollChild(content)

    local resultRows = {}
    local function UpdateResultsTable()
        local results = (MarketSync.Scanner and MarketSync.Scanner.RecentResults) or {}
        local rowHeight = 26

        for i = 1, math.max(#results, #resultRows) do
            local row = resultRows[i]
            local data = results[i]

            if data then
                if not row then
                    row = CreateFrame("Frame", nil, content, "BackdropTemplate")
                    row:SetHeight(rowHeight)
                    row:SetPoint("LEFT", 0, 0)
                    row:SetPoint("RIGHT", 0, 0)
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", 6, 0)

                    row.favBtn = CreateFrame("Button", nil, row)
                    row.favBtn:SetSize(18, 18)
                    row.favBtn:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                    row.favBtn.text = row.favBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.favBtn.text:SetPoint("CENTER")
                    row.favBtn.text:SetText("☆")

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.favBtn, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", row, "RIGHT", -230, 0)
                    row.name:SetJustifyH("LEFT")

                    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.price:SetPoint("RIGHT", -140, 0)

                    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.qty:SetPoint("RIGHT", -60, 0)

                    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    row.time:SetPoint("RIGHT", -15, 0)

                    resultRows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowHeight)

                if i % 2 == 0 then
                    row:SetBackdropColor(0.1, 0.12, 0.15, 0.5)
                else
                    row:SetBackdropColor(0.06, 0.08, 0.1, 0.5)
                end

                row.icon:SetTexture(data.icon)
                row.name:SetText(data.name)
                row.price:SetText(MarketSync.FormatMoney and MarketSync.FormatMoney(data.unitPrice) or tostring(data.unitPrice))
                row.qty:SetText(data.available or 1)
                row.time:SetText(date("%H:%M:%S", data.time))

                -- Favorite Toggle
                local isFav = MarketSync.Favorites and MarketSync.Favorites.IsItemInList("Favorites", data.itemID)
                row.favBtn.text:SetText(isFav and "|cFFFFD100★|r" or "|cFF777777☆|r")
                row.favBtn:SetScript("OnClick", function()
                    if MarketSync.Favorites then
                        MarketSync.Favorites.ToggleItemInList("Favorites", data.itemID)
                        UpdateResultsTable()
                    end
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end
        content:SetHeight(math.max(1, #results * rowHeight))
    end

    -- ================================================================
    -- ⭐ QUICK LISTS POPUP / DRAWER
    -- ================================================================
    local quickPopup = CreateFrame("Frame", "MarketSyncQuickListsPopup", panel, "BackdropTemplate")
    quickPopup:SetSize(340, 430)
    quickPopup:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -50)
    quickPopup:SetFrameLevel(panel:GetFrameLevel() + 10)
    quickPopup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    quickPopup:SetBackdropColor(0.08, 0.1, 0.14, 0.98)
    quickPopup:Hide()

    local popupTitle = quickPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popupTitle:SetPoint("TOPLEFT", 14, -12)
    popupTitle:SetText("Preferred / Favorite Lists")

    local closePopupBtn = CreateFrame("Button", nil, quickPopup, "UIPanelCloseButton")
    closePopupBtn:SetPoint("TOPRIGHT", -4, -4)
    closePopupBtn:SetScript("OnClick", function() quickPopup:Hide() end)

    -- Active List Selection Dropdown / Buttons
    local currentListName = "Favorites"
    local listLabel = quickPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listLabel:SetPoint("TOPLEFT", 14, -38)
    listLabel:SetText("Active List: |cFFFFD100" .. currentListName .. "|r")

    -- Scan This List Button
    local scanListBtn = CreateFrame("Button", nil, quickPopup, "UIPanelButtonTemplate")
    scanListBtn:SetSize(140, 24)
    scanListBtn:SetPoint("TOPLEFT", 14, -60)
    scanListBtn:SetText("▶ Scan This List")
    scanListBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            MarketSync.Scanner.ScanList(currentListName)
            quickPopup:Hide()
        end
    end)

    -- New List Button
    local newListBtn = CreateFrame("Button", nil, quickPopup, "UIPanelButtonTemplate")
    newListBtn:SetSize(90, 24)
    newListBtn:SetPoint("LEFT", scanListBtn, "RIGHT", 6, 0)
    newListBtn:SetText("+ New List")
    newListBtn:SetScript("OnClick", function()
        StaticPopupDialogs["MARKETSYNC_NEW_LIST"] = {
            text = "Enter a name for the new Preferred List:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local text = self.editBox:GetText()
                if text and text ~= "" and MarketSync.Favorites then
                    MarketSync.Favorites.CreateList(text)
                    currentListName = text
                    listLabel:SetText("Active List: |cFFFFD100" .. currentListName .. "|r")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MARKETSYNC_NEW_LIST")
    end)

    -- Items in Selected List
    local popupScroll = CreateFrame("ScrollFrame", nil, quickPopup, "UIPanelScrollFrameTemplate")
    popupScroll:SetPoint("TOPLEFT", 12, -92)
    popupScroll:SetPoint("BOTTOMRIGHT", -28, 40)

    local popupContent = CreateFrame("Frame", nil, popupScroll)
    popupContent:SetSize(280, 1)
    popupScroll:SetScrollChild(popupContent)

    local listRows = {}
    local function UpdatePopupItems()
        local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(currentListName) or {}
        local rowH = 22

        for i = 1, math.max(#items, #listRows) do
            local row = listRows[i]
            local item = items[i]

            if item then
                if not row then
                    row = CreateFrame("Frame", nil, popupContent)
                    row:SetHeight(rowH)
                    row:SetPoint("LEFT", 0, 0)
                    row:SetPoint("RIGHT", 0, 0)

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(18, 18)
                    row.icon:SetPoint("LEFT", 2, 0)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", -30, 0)
                    row.name:SetJustifyH("LEFT")

                    row.delBtn = CreateFrame("Button", nil, row)
                    row.delBtn:SetSize(16, 16)
                    row.delBtn:SetPoint("RIGHT", -2, 0)
                    row.delBtn.text = row.delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.delBtn.text:SetPoint("CENTER")
                    row.delBtn.text:SetText("|cFFFF4444×|r")

                    listRows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                row.icon:SetTexture(item.icon)
                row.name:SetText(item.name)
                row.delBtn:SetScript("OnClick", function()
                    if MarketSync.Favorites then
                        MarketSync.Favorites.RemoveFromList(currentListName, item.itemID)
                        UpdatePopupItems()
                    end
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end
        popupContent:SetHeight(math.max(1, #items * rowH))
    end

    -- Add item editbox at bottom of popup
    local addBox = CreateFrame("EditBox", nil, quickPopup, "InputBoxTemplate")
    addBox:SetSize(220, 20)
    addBox:SetPoint("BOTTOMLEFT", 16, 12)
    addBox:SetAutoFocus(false)
    addBox:SetText("Drop item or enter ID...")
    addBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(currentListName, text)
            self:SetText("")
            self:ClearFocus()
            UpdatePopupItems()
        end
    end)
    addBox:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(currentListName, itemID or itemLink)
            ClearCursor()
            UpdatePopupItems()
        end
    end)

    quickListsBtn:SetScript("OnClick", function()
        if quickPopup:IsShown() then
            quickPopup:Hide()
        else
            quickPopup:Show()
            UpdatePopupItems()
        end
    end)

    -- Register scanner updates
    local function OnScannerUpdate()
        local scanner = MarketSync.Scanner
        if not scanner then return end

        statusText:SetText(scanner.Status or "Idle")
        if scanner.Active then
            stopBtn:Enable()
            scanWatchedBtn:Disable()
            if scanner.Progress.total > 0 then
                progressBar:SetMinMaxValues(0, scanner.Progress.total)
                progressBar:SetValue(scanner.Progress.current)
                progressLabel:SetText(string.format("%d / %d (%d%%)",
                    scanner.Progress.current,
                    scanner.Progress.total,
                    math.floor((scanner.Progress.current / scanner.Progress.total) * 100)))
            end
        else
            stopBtn:Disable()
            scanWatchedBtn:Enable()
            progressBar:SetValue(progressBar:GetMinMaxValues())
            progressLabel:SetText(scanner.Status or "Ready")
        end

        UpdateResultsTable()
    end

    if MarketSync.Scanner then
        MarketSync.Scanner.RegisterCallback(OnScannerUpdate)
    end
    if MarketSync.Favorites then
        MarketSync.Favorites.RegisterCallback(UpdatePopupItems)
    end

    panel.OnShow = function()
        OnScannerUpdate()
    end

    return panel
end
