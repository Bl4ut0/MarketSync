-- Same shared dropdown as Config.lua; defined here too for hosts that load this file alone.
MarketSync = MarketSync or {}
if not MarketSync.CreateDropdownButton then function MarketSync.CreateDropdownButton(parent, menuName, width, height, initFunc)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, height or 22)
    local menu = CreateFrame("Frame", menuName, parent, "UIDropDownMenuTemplate")
    menu:Hide()
    button._menu, button._initFunc = menu, initFunc
    if initFunc and UIDropDownMenu_Initialize then UIDropDownMenu_Initialize(menu, initFunc) end
    function button:SetLabel(text) self:SetText(tostring(text or "") .. "  |cFFFFD100v|r") end
    button:SetScript("OnClick", function(self)
        if GameTooltip then GameTooltip:Hide() end
        if ToggleDropDownMenu then ToggleDropDownMenu(1, nil, menu, self, 0, 0) end
    end)
    return button
end end

-- =============================================================
-- MarketSync - Legacy multi-item Scan page
-- Classic-family Auction House only (Era, Anniversary, Classic progression).
-- Left: the items to scan, added like the Forever sell page's item slot
-- (drop an item, shift-click a link, type a name, or add bags / a list).
-- Right: one row per item with its lowest live price, like Auctionator's
-- shopping results, and the selected item's live listings underneath, where a
-- stack can be checked and bought (the Search tab's flow).
-- The list shown here is the shopping list selected in the breakout
-- (Favorites.GetSelectedList); adding or removing items edits that list.
-- Prices come from Scanner.StartMultiScan (LegacyScanner.lua), which also
-- saves each item's lowest price to MarketSync history. Nothing is posted.
-- =============================================================
MarketSync = MarketSync or {}

local QUEUE_LIMIT = 200
local LEFT_WIDTH = 246

local STATE_TEXT = {
    queued = "|cff9d9d9dQueued|r",
    scanning = "|cffffd100Scanning...|r",
    done = "|cff40ff40Priced|r",
    empty = "|cffff8040No auctions|r",
    failed = "|cffff4040Failed|r",
    skipped = "|cffff4040Skipped|r",
}

local function Money(copper)
    if not copper then return "-" end
    return MarketSync.FormatMoney and MarketSync.FormatMoney(copper) or (tostring(copper) .. "c")
end

local function Identity(itemID, suffix)
    return string.format("%d:%d", itemID, suffix or 0)
end

local function ItemDisplay(itemID, suffix, link)
    local name, itemLink, quality, _, _, _, _, _, _, texture
    if GetItemInfo then name, itemLink, quality, _, _, _, _, _, _, texture = GetItemInfo(link or itemID) end
    if not name and MarketSync.GetItemInfo then name = MarketSync.GetItemInfo(itemID) end
    if not texture and GetItemInfoInstant then texture = select(5, GetItemInfoInstant(itemID)) end
    local cached = MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID]
    name = name or (cached and cached.n) or ("Item #" .. itemID)
    return name, link or itemLink, quality, texture or 134400
end

-- Reads an item reference from a link, "item:ID", a DB key, an ID or a name.
local function ParseItem(ref)
    if type(ref) == "number" then return ref, 0 end
    if type(ref) ~= "string" then return nil end
    local text = ref:match("^%s*(.-)%s*$")
    if text == "" then return nil end
    local key = MarketSync.Scanner and MarketSync.Scanner.ToItemKey and MarketSync.Scanner.ToItemKey(text)
    if key and key.itemID then return key.itemID, key.itemSuffix or 0, text:find("|Hitem:") and text or nil end
    return nil
end

local function Fav() return MarketSync.Favorites end

local function SelectedList()
    local F = Fav()
    return (F and F.GetSelectedList and F.GetSelectedList()) or "Favorites"
end

-- The selected shopping list, as { itemID, itemSuffix, link, name, icon, quality, dbKey }.
local function GetQueue()
    local F = Fav()
    local items = (F and F.GetListItems and F.GetListItems(SelectedList())) or {}
    local queue = {}
    for _, item in ipairs(items) do
        queue[#queue + 1] = { itemID = item.itemID, itemSuffix = item.suffix or 0, link = item.link,
            name = item.name, icon = item.icon, quality = item.quality, dbKey = item.dbKey }
    end
    return queue
end

local function ContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- itemID, link, bound for a bag slot.
local function ContainerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.hyperlink, info.isBound end
        return nil
    end
    if GetContainerItemInfo then
        local _, _, _, _, _, _, link, _, _, itemID, isBound = GetContainerItemInfo(bag, slot)
        return itemID, link, isBound
    end
end

function MarketSync.CreateLegacyMultiScanPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    local scanner = MarketSync.Scanner
    local selectedIdentity
    local selectedListing
    local panelWidth = (parent.GetWidth and parent:GetWidth() or 0) > 0 and parent:GetWidth() or 802

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetColorTexture(MarketSync.GetThemeColor("dialog"))

    local function MakeBox(x, y, width, height, anchor)
        local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        box:SetPoint("TOPLEFT", anchor or panel, "TOPLEFT", x, y)
        box:SetSize(width, height)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        box:SetBackdropColor(MarketSync.GetThemeColor("inset"))
        box:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
        return box
    end

    local function MakeButton(parentFrame, text, width, height)
        local button = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
        button:SetSize(width, height or 22)
        button:SetText(text)
        return button
    end

    local function Tip(frame, title, text)
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(title, 1, 0.82, 0)
            if text then GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- =============================================================
    -- LEFT: items to scan
    -- =============================================================
    local leftTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -8)
    leftTitle:SetText("Items to Scan")
    local countText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countText:SetPoint("LEFT", leftTitle, "RIGHT", 8, 0)

    local Refresh
    local function AddItem(itemID, suffix, link, silent)
        local F = Fav()
        if not itemID or not (F and F.AddToList) then return false end
        local listName = SelectedList()
        local ref = link or itemID
        if F.IsItemInList and F.IsItemInList(listName, ref) then return false end
        if #GetQueue() >= QUEUE_LIMIT then
            if not silent and MarketSync.Print then MarketSync.Print("A scan list holds up to " .. QUEUE_LIMIT .. " items.") end
            return false
        end
        local ok = F.AddToList(listName, ref)
        if ok then selectedIdentity = selectedIdentity or Identity(itemID, suffix) end
        return ok and true or false
    end

    -- Item slot: drop an item from the bags, like the Forever sell page.
    local slot = CreateFrame("Button", nil, panel)
    slot:SetSize(37, 37)
    slot:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -30)
    local slotArt = slot:CreateTexture(nil, "BACKGROUND")
    slotArt:SetAllPoints(slot)
    slotArt:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    slotArt:SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local function TakeCursorItem()
        local kind, itemID, link = GetCursorInfo and GetCursorInfo()
        if kind ~= "item" then return end
        local id, suffix = ParseItem(link)
        AddItem(id or tonumber(itemID), suffix or 0, link)
        if ClearCursor then ClearCursor() end
        Refresh()
    end
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnReceiveDrag", TakeCursorItem)
    slot:SetScript("OnClick", TakeCursorItem)
    Tip(slot, "Add an item", "Drop an item from your bags here.")

    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetSize(LEFT_WIDTH - 37 - 70, 20)
    input:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -2)
    input:SetAutoFocus(false)
    input:SetMaxLetters(120)
    local inputHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    inputHint:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -2)
    inputHint:SetText("Drop, shift-click, or type a name")

    local addButton = MakeButton(panel, "Add", 50, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 4, 0)
    local function SubmitInput()
        local text = input:GetText() or ""
        local id, suffix, link = ParseItem(text)
        if id then
            AddItem(id, suffix, link)
            input:SetText("")
        elseif text ~= "" and MarketSync.Print then
            MarketSync.Print("Item not found. Shift-click the item, or use its exact name after it has been seen.")
        end
        input:ClearFocus()
        Refresh()
    end
    addButton:SetScript("OnClick", SubmitInput)
    input:SetScript("OnEnterPressed", SubmitInput)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if MarketSync.RegisterLinkAwareEditBox then
        MarketSync.RegisterLinkAwareEditBox(input, {
            onInsertLink = function(box, text)
                local id, suffix = ParseItem(text)
                if id then AddItem(id, suffix, text); box:SetText(""); Refresh(); return true end
                return false
            end,
        })
    end

    -- Bag items go into their own "Bags" list, rebuilt from the bags on every
    -- click, so the player's other shopping lists are never touched.
    local BAGS_LIST = "Bags"
    local addBags = MakeButton(panel, "Bags", 76, 20)
    addBags:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -8)
    addBags:SetScript("OnClick", function()
        local F = Fav()
        if not (F and F.AddToList and F.GetListItems and F.RemoveFromList) then return end
        if F.CreateList then F.CreateList(BAGS_LIST) end -- no-op when it exists
        -- Empty it first: items sold or moved out of the bags drop off.
        for _, item in ipairs(F.GetListItems(BAGS_LIST)) do
            F.RemoveFromList(BAGS_LIST, item.dbKey or item.itemID)
        end
        local added, seen = 0, {}
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for bagSlot = 1, ContainerSlots(bag) do
                local itemID, link, bound = ContainerItem(bag, bagSlot)
                if itemID and not bound and added < QUEUE_LIMIT then
                    local _, suffix = ParseItem(link)
                    local identity = Identity(itemID, suffix)
                    if not seen[identity] then
                        seen[identity] = true
                        if F.AddToList(BAGS_LIST, link or itemID) then added = added + 1 end
                    end
                end
            end
        end
        selectedIdentity = nil
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SelectShoppingList then
            MarketSync.AHSidecar.SelectShoppingList(BAGS_LIST)
        elseif F.SetSelectedList then
            F.SetSelectedList(BAGS_LIST)
        end
        if MarketSync.Print then
            MarketSync.Print(string.format("Bags list updated: %d tradeable item(s) from your bags.", added))
        end
        Refresh()
    end)
    Tip(addBags, "Bags", "Shows the items in your bags that are not soulbound, as the \"Bags\" list. Each click rebuilds that list from your current bags; your other lists are not changed.")

    -- The breakout's list picker dropdown: the game's own button and menu list.
    local addList = MarketSync.CreateDropdownButton(panel, "MarketSyncMultiScanListMenu", 76, 20, function(_, level)
        local lists = (MarketSync.Favorites and MarketSync.Favorites.GetLists and MarketSync.Favorites.GetLists()) or {}
        for _, listName in ipairs(lists) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = listName
            info.checked = (listName == SelectedList())
            info.func = function()
                -- Picking a list here picks it in the breakout too.
                if MarketSync.AHSidecar and MarketSync.AHSidecar.SelectShoppingList then
                    MarketSync.AHSidecar.SelectShoppingList(listName)
                elseif Fav() and Fav().SetSelectedList then
                    Fav().SetSelectedList(listName)
                end
                selectedIdentity = nil
                Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    addList:SetPoint("LEFT", addBags, "RIGHT", 4, 0)
    addList:SetLabel("List")    Tip(addList, "Shopping list", "Chooses which shopping list this page scans and edits. It is the same list as the one selected in the breakout panel.")

    local clearButton = MakeButton(panel, "Clear", 64, 20)
    clearButton:SetPoint("LEFT", addList, "RIGHT", 4, 0)
    clearButton:SetScript("OnClick", function()
        if not scanner or scanner.Active then return end
        -- Clears the scan results only; the shopping list keeps its items.
        scanner.MultiScan = nil
        Refresh()
    end)
    Tip(clearButton, "Clear results", "Clears the scan results on this page. The shopping list keeps its items.")

    local queueBox = MakeBox(14, -106, LEFT_WIDTH, 1)
    queueBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 40)
    queueBox:SetHeight(0)
    local queueScroll = CreateFrame("ScrollFrame", nil, queueBox, "UIPanelScrollFrameTemplate")
    queueScroll:SetPoint("TOPLEFT", queueBox, "TOPLEFT", 2, -3)
    queueScroll:SetPoint("BOTTOMRIGHT", queueBox, "BOTTOMRIGHT", -22, 3)
    local queueContent = CreateFrame("Frame", nil, queueScroll)
    queueContent:SetSize(LEFT_WIDTH - 26, 1)
    queueScroll:SetScrollChild(queueContent)
    local queueEmpty = queueBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queueEmpty:SetPoint("CENTER", queueBox, "CENTER", 0, 0)
    queueEmpty:SetWidth(LEFT_WIDTH - 30)
    queueEmpty:SetText("This list is empty.\nAdd items with the slot, the box, or pick another list (Bags shows your bag items).")

    local scanButton = MakeButton(panel, "Scan All", 92, 24)
    scanButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 10)
    local stopButton = MakeButton(panel, "Stop", 64, 24)
    stopButton:SetPoint("LEFT", scanButton, "RIGHT", 4, 0)
    local fullButton = MakeButton(panel, "Full Scan", 82, 24)
    fullButton:SetPoint("LEFT", stopButton, "RIGHT", 4, 0)
    Tip(scanButton, "Scan All", "Searches the Auction House for each item in the list and saves each lowest price to MarketSync.")
    Tip(fullButton, "Full Scan", "Reads every auction at once (Auction House full-scan cooldown applies). Prices are saved, not listed here.")

    -- =============================================================
    -- RIGHT: results per item, then the selected item's listings
    -- =============================================================
    local rightX = 14 + LEFT_WIDTH + 12
    local rightWidth = panelWidth - rightX - 14
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", rightX, -10)
    status:SetWidth(rightWidth)
    status:SetJustifyH("LEFT")
    if status.SetWordWrap then status:SetWordWrap(false) end

    local progress = CreateFrame("StatusBar", nil, panel)
    progress:SetPoint("TOPLEFT", panel, "TOPLEFT", rightX, -26)
    progress:SetSize(rightWidth, 12)
    progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progress:SetStatusBarColor(0.75, 0.55, 0.12)
    progress:SetMinMaxValues(0, 1)
    local progressBg = progress:CreateTexture(nil, "BACKGROUND")
    progressBg:SetAllPoints(progress)
    progressBg:SetColorTexture(MarketSync.GetThemeColor("scrollTrack", 1))

    local sumCols = { { "Item", 30 }, { "Lowest", 0.46 }, { "vs Market", 0.62 }, { "Available", 0.76 }, { "Status", 0.88 } }
    local function ColX(frac, width) return frac < 1 and math.floor(width * frac) or frac end

    local function MakeHeader(y, columns, width)
        local header = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", rightX, y)
        header:SetSize(width, 20)
        header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        header:SetBackdropColor(MarketSync.GetThemeColor("header"))
        header:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))
        header.labels = {}
        for i, column in ipairs(columns) do
            local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", header, "LEFT", ColX(column[2], width) + (i == 1 and 0 or -2), 0)
            label:SetText(column[1])
            header.labels[i] = label
        end
        return header
    end

    local summaryHeader = MakeHeader(-44, sumCols, rightWidth)
    local summaryBox = MakeBox(0, 0, rightWidth, 150, summaryHeader)
    summaryBox:ClearAllPoints()
    summaryBox:SetPoint("TOPLEFT", summaryHeader, "BOTTOMLEFT", 0, 0)
    local summaryScroll = CreateFrame("ScrollFrame", nil, summaryBox, "UIPanelScrollFrameTemplate")
    summaryScroll:SetPoint("TOPLEFT", summaryBox, "TOPLEFT", 2, -2)
    summaryScroll:SetPoint("BOTTOMRIGHT", summaryBox, "BOTTOMRIGHT", -22, 2)
    local summaryContent = CreateFrame("Frame", nil, summaryScroll)
    summaryContent:SetSize(rightWidth - 26, 1)
    summaryScroll:SetScrollChild(summaryContent)
    local summaryEmpty = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryEmpty:SetPoint("CENTER", summaryBox, "CENTER", 0, 0)
    summaryEmpty:SetText("Add items on the left, then press Scan All.")

    local detailTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailTitle:SetPoint("TOPLEFT", summaryBox, "BOTTOMLEFT", 2, -8)
    detailTitle:SetWidth(rightWidth - 120)
    detailTitle:SetJustifyH("LEFT")
    local buyButton = MakeButton(panel, "Buy 1 Stack", 110, 20)
    buyButton:SetPoint("TOPRIGHT", summaryBox, "BOTTOMRIGHT", 0, -4)
    Tip(buyButton, "Buy 1 Stack", "Select a listing below. MarketSync re-checks that exact stack on the Auction House, then this buys one stack after you confirm.")

    local detailCols = { { "Unit price", 8 }, { "Stack", 0.30 }, { "Auctions", 0.44 }, { "Buyout", 0.60 }, { "Seller", 0.84 } }
    local detailHeader = MakeHeader(0, detailCols, rightWidth)
    detailHeader:ClearAllPoints()
    detailHeader:SetPoint("TOPLEFT", summaryBox, "BOTTOMLEFT", 0, -28)
    local detailBox = MakeBox(0, 0, rightWidth, 1, detailHeader)
    detailBox:ClearAllPoints()
    detailBox:SetPoint("TOPLEFT", detailHeader, "BOTTOMLEFT", 0, 0)
    detailBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 10)
    local detailScroll = CreateFrame("ScrollFrame", nil, detailBox, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 2, -2)
    detailScroll:SetPoint("BOTTOMRIGHT", detailBox, "BOTTOMRIGHT", -22, 2)
    local detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(rightWidth - 26, 1)
    detailScroll:SetScrollChild(detailContent)
    local detailEmpty = detailBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailEmpty:SetPoint("CENTER", detailBox, "CENTER", 0, 0)

    -- =============================================================
    -- Row pools
    -- =============================================================
    local function RowBase(parentFrame, width, height)
        local row = CreateFrame("Button", nil, parentFrame)
        row:SetSize(width, height)
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        return row
    end
    local function Cell(row, x, width, font)
        local text = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", x, 0)
        text:SetWidth(width)
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(false) end
        return text
    end

    local queueRowH, queueRows = 22, {}
    for i = 1, 14 do
        local row = RowBase(queueContent, LEFT_WIDTH - 28, queueRowH)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.name = Cell(row, 25, 120)
        row.state = Cell(row, 148, 52)
        row.remove = CreateFrame("Button", nil, row)
        row.remove:SetSize(16, 16)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        row.remove:SetScript("OnClick", function()
            local data = row.data
            if not data then return end
            if data.inList and Fav() and Fav().RemoveFromList then
                Fav().RemoveFromList(SelectedList(), data.dbKey or data.itemID)
            end
            if selectedIdentity == data.identity then selectedIdentity = nil end
            Refresh()
        end)
        row:SetScript("OnClick", function(self, button)
            if not self.data then return end
            if button == "RightButton" then self.remove:Click() return end
            selectedIdentity = self.data.identity
            Refresh()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.data.link and GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, self.data.link)
            else GameTooltip:SetText(self.data.name) end
            if self.data.reason then GameTooltip:AddLine(self.data.reason, 1, 0.4, 0.4, true) end
            GameTooltip:AddLine("Right-click to remove.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        queueRows[i] = row
    end

    local sumRowH, sumRows = 24, {}
    local sumWidth = rightWidth - 28
    for i = 1, 8 do
        local row = RowBase(summaryContent, sumWidth, sumRowH)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.name = Cell(row, 30, ColX(0.46, rightWidth) - 36)
        row.price = Cell(row, ColX(0.46, rightWidth) - 2, ColX(0.62, rightWidth) - ColX(0.46, rightWidth) - 4)
        row.price:SetTextColor(1, 0.82, 0.30)
        row.delta = Cell(row, ColX(0.62, rightWidth) - 2, ColX(0.76, rightWidth) - ColX(0.62, rightWidth) - 4)
        row.available = Cell(row, ColX(0.76, rightWidth) - 2, ColX(0.88, rightWidth) - ColX(0.76, rightWidth) - 4)
        row.state = Cell(row, ColX(0.88, rightWidth) - 2, sumWidth - ColX(0.88, rightWidth))
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            selectedIdentity = self.data.identity
            Refresh()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.data.link and GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, self.data.link)
            else GameTooltip:SetText(self.data.name) end
            if self.data.previousPrice then
                GameTooltip:AddDoubleLine("Market price before scan:", Money(self.data.previousPrice), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sumRows[i] = row
    end

    local detailRowH, detailRows = 20, {}
    for i = 1, 8 do
        local row = RowBase(detailContent, sumWidth, detailRowH)
        row.price = Cell(row, 8, ColX(0.30, rightWidth) - 12)
        row.price:SetTextColor(1, 0.82, 0.30)
        row.stack = Cell(row, ColX(0.30, rightWidth) - 2, ColX(0.44, rightWidth) - ColX(0.30, rightWidth) - 4)
        row.auctions = Cell(row, ColX(0.44, rightWidth) - 2, ColX(0.60, rightWidth) - ColX(0.44, rightWidth) - 4)
        row.buyout = Cell(row, ColX(0.60, rightWidth) - 2, ColX(0.84, rightWidth) - ColX(0.60, rightWidth) - 4)
        row.seller = Cell(row, ColX(0.84, rightWidth) - 2, sumWidth - ColX(0.84, rightWidth))
        -- Selecting a listing re-checks that exact stack (the Search tab's buy flow).
        row:SetScript("OnClick", function(self)
            local data = self.data
            if not data or data.mine then return end
            if scanner and scanner.Active then return end
            selectedListing = data
            if scanner and scanner.PrepareLivePurchase then scanner.PrepareLivePurchase(data) end
            Refresh()
        end)
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.data.link then pcall(GameTooltip.SetHyperlink, GameTooltip, self.data.link) end
            GameTooltip:AddLine(self.data.mine and "Your auction." or "Click to check this stack for buying.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        detailRows[i] = row
    end

    -- =============================================================
    -- Refresh
    -- =============================================================
    -- The selected list joined with the latest scan results, in list order.
    -- Items from a scan started elsewhere (a craft list's materials, another
    -- list) that are not in this list follow underneath.
    local function BuildDisplay()
        local results, order = {}, {}
        local multi = scanner and scanner.GetMultiScan and scanner.GetMultiScan()
        if multi then
            for _, entry in ipairs(multi.items) do
                local identity = Identity(entry.itemID, entry.itemSuffix)
                results[identity] = entry
                order[#order + 1] = identity
            end
        end
        local display = {}
        local queue = GetQueue()
        local inListIDs = {}
        for _, item in ipairs(queue) do
            item.inList = true
            inListIDs[Identity(item.itemID, item.itemSuffix)] = true
        end
        for _, identity in ipairs(order) do
            if not inListIDs[identity] then
                local entry = results[identity]
                queue[#queue + 1] = { itemID = entry.itemID, itemSuffix = entry.itemSuffix, link = entry.link }
            end
        end
        for _, item in ipairs(queue) do
            local identity = Identity(item.itemID, item.itemSuffix)
            local result = results[identity]
            local name, link, quality, icon = ItemDisplay(item.itemID, item.itemSuffix, item.link)
            local previous = result and result.previousPrice
            if not result and MarketSync.GetItemPriceAndScanInfo then
                local key = (item.itemSuffix or 0) ~= 0 and string.format("p:%d:%d", item.itemID, item.itemSuffix)
                    or tostring(item.itemID)
                local info = MarketSync.GetItemPriceAndScanInfo(key)
                previous = info and info.price
            end
            display[#display + 1] = {
                identity = identity, itemID = item.itemID, itemSuffix = item.itemSuffix,
                inList = item.inList == true, dbKey = item.dbKey,
                name = (result and result.name) or name, link = (result and result.link) or link,
                quality = quality, icon = (result and result.icon) or icon,
                state = result and result.state or "notScanned", reason = result and result.reason,
                minUnit = result and result.minUnit, available = result and result.available,
                auctions = result and result.auctions, listings = result and result.listings,
                previousPrice = previous,
            }
        end
        return display
    end

    local function RenderRows(rows, rowHeight, scroll, content, items, fill)
        content:SetHeight(math.max(1, #items * rowHeight))
        local first = math.floor((scroll:GetVerticalScroll() or 0) / rowHeight)
        for i, row in ipairs(rows) do
            local index = first + i
            local data = items[index]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * rowHeight)
            row.data = data
            if data then
                fill(row, data, index)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    local function RowColor(row, data, index)
        local role = (data.identity and data.identity == selectedIdentity) and "hover"
            or (index % 2 == 0 and "rowEven" or "rowOdd")
        row.background:SetColorTexture(MarketSync.GetThemeColor(role))
    end

    Refresh = function()
        if not panel:IsShown() then return end
        local display = BuildDisplay()
        local multi = scanner and scanner.GetMultiScan and scanner.GetMultiScan()
        local scanning = scanner and scanner.Active and multi and multi.state == "scanning"
        local disabled = scanner and scanner.IsDisabledByAuctionator and scanner.IsDisabledByAuctionator()
        local available = scanner and scanner.IsAvailable and scanner.IsAvailable()

        local listName = SelectedList()
        countText:SetText(string.format("%s - %d item(s)", listName, #GetQueue()))
        addList:SetText((#listName > 9 and listName:sub(1, 8) .. ".." or listName) .. " v")
        scanButton:SetEnabled((not disabled and available and not (scanner and scanner.Active) and #display > 0) and true or false)
        stopButton:SetEnabled(scanning and true or false)
        clearButton:SetEnabled((not scanning and #display > 0) and true or false)
        fullButton:SetEnabled((not disabled and available and not (scanner and scanner.Active)) and true or false)

        if disabled then
            status:SetText("Auctionator scanning is enabled. Turn it off in MarketSync Settings to scan here.")
        else
            status:SetText(scanner and scanner.Status or "Open the Auction House to scan.")
        end
        local total = multi and #multi.items or 0
        progress:SetMinMaxValues(0, math.max(1, total))
        progress:SetValue(multi and (multi.completed or 0) or 0)
        progress:SetStatusBarColor(multi and multi.state == "stopped" and 0.5 or 0.75, 0.55, 0.12)

        if #display == 0 then queueEmpty:Show() summaryEmpty:Show() else queueEmpty:Hide() summaryEmpty:Hide() end

        RenderRows(queueRows, queueRowH, queueScroll, queueContent, display, function(row, data, index)
            RowColor(row, data, index)
            row.icon:SetTexture(data.icon)
            row.name:SetText(data.name)
            if data.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[data.quality] then
                local c = ITEM_QUALITY_COLORS[data.quality]
                row.name:SetTextColor(c.r, c.g, c.b)
            else
                row.name:SetTextColor(1, 1, 1)
            end
            row.state:SetText(data.inList and (STATE_TEXT[data.state] or "") or "|cff9d9d9dNot in list|r")
        end)

        RenderRows(sumRows, sumRowH, summaryScroll, summaryContent, display, function(row, data, index)
            RowColor(row, data, index)
            row.icon:SetTexture(data.icon)
            row.name:SetText(data.name)
            row.price:SetText(data.minUnit and Money(data.minUnit) or "-")
            if data.minUnit and data.previousPrice and data.previousPrice > 0 then
                local pct = (data.minUnit - data.previousPrice) / data.previousPrice * 100
                local color = pct <= -5 and "|cff40ff40" or (pct >= 10 and "|cffff6060" or "|cffd0d0d0")
                row.delta:SetText(string.format("%s%+.0f%%|r", color, pct))
            else
                row.delta:SetText("-")
            end
            row.available:SetText(data.available and data.available > 0
                and string.format("%d (%d)", data.available, data.auctions or 0) or "-")
            row.state:SetText(STATE_TEXT[data.state] or "|cff9d9d9dNot scanned|r")
        end)

        local selected
        for _, data in ipairs(display) do
            if data.identity == selectedIdentity then selected = data break end
        end
        local listings = selected and selected.listings or {}
        local listingStillShown = false
        for _, listing in ipairs(listings) do if listing == selectedListing then listingStillShown = true end end
        if not listingStillShown then selectedListing = nil end
        local ready = selectedListing and scanner and scanner.PurchaseReady
        ready = ready and ready.row == selectedListing and ready or nil
        if selectedListing then
            local checking = scanner and scanner.Active and not ready
            detailTitle:SetText(string.format("%s x%d for %s - %s", selected.name, selectedListing.stackSize,
                Money(selectedListing.buyout), ready and "|cff40ff40stack verified|r"
                or (checking and "checking stack..." or "|cffff8040stack no longer listed|r")))
        elseif selected then
            detailTitle:SetText(string.format("%s - %s", selected.name,
                #listings > 0 and string.format("%d listing group(s); click one to buy", #listings) or "live listings"))
        else
            detailTitle:SetText("Select an item to see its live listings")
        end
        buyButton:SetEnabled((ready and not scanner.Active and available
            and (type(GetMoney) ~= "function" or GetMoney() >= selectedListing.buyout)) and true or false)
        if not selected then
            detailEmpty:SetText("")
        elseif selected.state == "empty" then
            detailEmpty:SetText("No buyout auctions were listed for this item.")
        elseif selected.state == "failed" or selected.state == "skipped" then
            detailEmpty:SetText(selected.reason or "This item could not be scanned.")
        elseif #listings == 0 then
            detailEmpty:SetText("Scan this item to see its listings.")
        else
            detailEmpty:SetText("")
        end
        RenderRows(detailRows, detailRowH, detailScroll, detailContent, listings, function(row, data, index)
            row.background:SetColorTexture(MarketSync.GetThemeColor(data == selectedListing and "hover"
                or (index % 2 == 0 and "rowEven" or "rowOdd")))
            row.price:SetText(Money(data.unitPrice))
            row.stack:SetText(tostring(data.stackSize))
            row.auctions:SetText(tostring(data.auctions))
            row.buyout:SetText(Money(data.buyout))
            row.seller:SetText(data.mine and "|cff40c0ffYou|r" or "")
        end)
    end

    scanButton:SetScript("OnClick", function()
        local items = {}
        for _, item in ipairs(GetQueue()) do
            items[#items + 1] = { itemID = item.itemID, itemSuffix = item.itemSuffix, link = item.link }
        end
        if scanner and scanner.StartMultiScan then scanner.StartMultiScan(items) end
        Refresh()
    end)
    stopButton:SetScript("OnClick", function()
        if scanner and scanner.Active and scanner.Cancel then
            scanner.Cancel("Scan stopped. Finished items keep their prices.")
        end
        Refresh()
    end)
    fullButton:SetScript("OnClick", function()
        if scanner and scanner.StartFullScan then scanner.StartFullScan() end
        Refresh()
    end)
    buyButton:SetScript("OnClick", function()
        local listing = selectedListing
        local ready = listing and scanner and scanner.PurchaseReady
        if not ready or ready.row ~= listing then return end
        if not (StaticPopupDialogs and StaticPopup_Show) then return end
        StaticPopupDialogs.MARKETSYNC_LEGACY_SCAN_BUY_STACK = {
            text = "Buy one stack of %s for %s?",
            button1 = "Buy Stack", button2 = "Cancel", timeout = 0,
            whileDead = false, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function(_, target)
                if scanner.BuyPreparedLivePurchase and scanner.BuyPreparedLivePurchase(target) then
                    selectedListing = nil
                end
                Refresh()
            end,
        }
        local label = string.format("%s x%d", listing.name or "item", listing.stackSize or 1)
        StaticPopup_Show("MARKETSYNC_LEGACY_SCAN_BUY_STACK", label, Money(listing.buyout), listing)
    end)

    for _, scroll in ipairs({ queueScroll, summaryScroll, detailScroll }) do
        scroll:HookScript("OnVerticalScroll", function() Refresh() end)
    end
    panel:SetScript("OnShow", Refresh)
    panel:SetScript("OnHide", function() if CloseDropDownMenus then CloseDropDownMenus() end end)
    panel.Refresh = Refresh
    panel.AddItem = function(_, ref)
        local id, suffix, link = ParseItem(ref)
        local added = AddItem(id, suffix, link)
        Refresh()
        return added
    end
    panel.ScanButton, panel.StopButton, panel.FullScanButton = scanButton, stopButton, fullButton
    panel.QueueRows, panel.SummaryRows, panel.DetailRows = queueRows, sumRows, detailRows
    panel.ItemInput, panel.ItemSlot, panel.BuyButton = input, slot, buyButton
    panel.AddBagsButton, panel.AddListButton, panel.ClearButton = addBags, addList, clearButton
    if scanner and scanner.RegisterCallback then scanner.RegisterCallback(Refresh) end
    -- List edits and list picks made in the breakout show here at once.
    if Fav() and Fav().RegisterCallback then Fav().RegisterCallback(function() Refresh() end) end
    if MarketSync.Theme and MarketSync.Theme.Register then MarketSync.Theme.Register(panel) end
    return panel
end
