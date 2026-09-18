-- ================================================================
-- MarketSync - Auction House Breakout Sidecar
-- Integrated Shopping Lists (quick search & batch buy) +
-- Inventory-Based Bag Selling (auto-undercut & 1-click select/post)
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.AHSidecar = {}

local Sidecar = MarketSync.AHSidecar
local SIDECAR_WIDTH = 330

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

local function GetPriceText(itemID)
    if not itemID then return "|cff888888--|r" end
    local p = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(itemID)
    if p and p > 0 then
        if MarketSync.FormatMoney then
            return MarketSync.FormatMoney(p)
        end
        return tostring(p) .. "c"
    end
    return "|cff888888No data|r"
end

-- ================================================================
-- SEARCH DISPATCH HELPER
-- Drives the native AuctionHouseFrame to search an item immediately
-- ================================================================
function MarketSync.SearchInAuctionHouse(itemOrName)
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return false end
    local name = type(itemOrName) == "string" and itemOrName or nil
    local itemID = tonumber(itemOrName)
    if not name and itemID then
        name = SafeGetItemInfo(itemID)
        if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
            name = MarketSyncDB.ItemInfoCache[itemID].n
        end
    end
    if not name or name == "" then return false end

    -- Clean bracketed name if present
    local cleanName = name:match("%[(.-)%]") or name

    -- 1. Switch to native Buy tab if not currently on it
    if AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[1] then
        if AuctionHouseFrame.GetDisplayMode and AuctionHouseFrame.Tabs[1].displayMode then
            if AuctionHouseFrame:GetDisplayMode() ~= AuctionHouseFrame.Tabs[1].displayMode then
                AuctionHouseFrame.Tabs[1]:Click()
            end
        end
    end

    -- 2. Populate SearchBar and trigger search
    if AuctionHouseFrame.SearchBar then
        if AuctionHouseFrame.SearchBar.SearchBox then
            AuctionHouseFrame.SearchBar.SearchBox:SetText(cleanName)
        end
        if AuctionHouseFrame.SearchBar.StartSearch then
            AuctionHouseFrame.SearchBar:StartSearch()
            return true
        elseif AuctionHouseFrame.SearchBar.SearchButton then
            AuctionHouseFrame.SearchBar.SearchButton:Click()
            return true
        end
    end

    -- Fallback to C_AuctionHouse.SendSearchQuery if search bar not available
    if C_AuctionHouse and C_AuctionHouse.SendSearchQuery and itemID then
        local itemKey = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
        pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, false)
        return true
    end

    return false
end

-- ================================================================
-- BAG SCANNER HELPER
-- Scans player inventory for auctionable items (excludes soulbound/quest)
-- ================================================================
function Sidecar.ScanBagsForSelling()
    local grouped = {}
    local order = {}

    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo

    if type(getNumSlots) ~= "function" then
        return {}
    end

    -- Scan backpack (0) through bags (1-4) and reagent bag (5)
    local maxBags = (NUM_BAG_SLOTS or 4) + 1
    for bag = 0, maxBags do
        local numSlots = getNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = getItemInfo(bag, slot)
            local itemID, stackCount, isBound, isLocked, quality, itemLink
            if type(info) == "table" then
                itemID = info.itemID
                stackCount = info.stackCount or 1
                isBound = info.isBound
                isLocked = info.isLocked
                quality = info.quality
                itemLink = info.hyperlink or info.itemLink
            elseif info then
                -- Legacy signature: icon, count, locked, quality, readable, lootable, link, isFiltered, noValue, id, isBound
                local _, count, locked, qual, _, _, link, _, _, id, bound = getItemInfo(bag, slot)
                itemID = id
                stackCount = count or 1
                isBound = bound
                isLocked = locked
                quality = qual
                itemLink = link
            end

            -- Filter: must have valid itemID, not soulbound, and not locked
            if itemID and itemID > 0 and not isBound and not isLocked then
                -- Verify not a quest item (classID 12)
                local _, _, _, _, _, _, _, _, _, _, _, classID = SafeGetItemInfo(itemID)
                if classID ~= 12 then
                    if not grouped[itemID] then
                        local name, link, rQual, _, _, _, _, _, _, icon = SafeGetItemInfo(itemID)
                        if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
                            local c = MarketSyncDB.ItemInfoCache[itemID]
                            name = c.n
                            icon = c.ic
                            rQual = c.r
                        end
                        grouped[itemID] = {
                            itemID = itemID,
                            name = name or ("Item #" .. itemID),
                            icon = icon or 134400,
                            quality = quality or rQual or 1,
                            link = itemLink or link or ("item:" .. itemID),
                            totalCount = 0,
                            slots = {},
                        }
                        table.insert(order, itemID)
                    end
                    grouped[itemID].totalCount = grouped[itemID].totalCount + stackCount
                    table.insert(grouped[itemID].slots, { bag = bag, slot = slot, count = stackCount })
                end
            end
        end
    end

    local items = {}
    for _, itemID in ipairs(order) do
        table.insert(items, grouped[itemID])
    end

    table.sort(items, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return items
end

-- ================================================================
-- CONSTRUCT SIDECAR FRAME
-- ================================================================
function MarketSync.CreateAHSidecar(parent)
    if Sidecar.Frame then return Sidecar.Frame end

    local ahFrame = parent or AuctionHouseFrame
    if not ahFrame then return nil end

    -- 1. Drawer Toggle Button attached to right edge of AuctionHouseFrame
    local toggleBtn = CreateFrame("Button", "MarketSyncAHSidecarToggleBtn", ahFrame, "UIPanelButtonTemplate")
    toggleBtn:SetSize(130, 24)
    toggleBtn:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", -2, -38)
    toggleBtn:SetText("🛒 MarketSync ▶")
    toggleBtn:SetFrameLevel(ahFrame:GetFrameLevel() + 5)

    -- 2. Breakout Sidecar Frame
    local frame = CreateFrame("Frame", "MarketSyncAHSidecarFrame", ahFrame, "BackdropTemplate")
    frame:SetWidth(SIDECAR_WIDTH)
    frame:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", 2, 0)
    frame:SetPoint("BOTTOMLEFT", ahFrame, "BOTTOMRIGHT", 2, 0)
    frame:SetFrameStrata(ahFrame:GetFrameStrata())
    frame:SetFrameLevel(ahFrame:GetFrameLevel() + 1)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    frame:SetBackdropBorderColor(0.4, 0.35, 0.2, 0.9)
    Sidecar.Frame = frame

    -- Top Header Container
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(62)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -4)
    title:SetText("|cFFFFD100MarketSync|r Sidecar")

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        Sidecar.SetExpanded(false)
    end)

    -- Mode Switcher Tabs
    local modeListsBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    modeListsBtn:SetSize(150, 22)
    modeListsBtn:SetPoint("BOTTOMLEFT", 6, 4)
    modeListsBtn:SetText("🛒 Shopping Lists")

    local modeSellBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    modeSellBtn:SetSize(150, 22)
    modeSellBtn:SetPoint("BOTTOMRIGHT", -6, 4)
    modeSellBtn:SetText("🎒 Bag Selling")

    -- Content Containers
    local listsContainer = CreateFrame("Frame", nil, frame)
    listsContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    listsContainer:SetPoint("BOTTOMRIGHT", -4, 6)

    local sellContainer = CreateFrame("Frame", nil, frame)
    sellContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    sellContainer:SetPoint("BOTTOMRIGHT", -4, 6)
    sellContainer:Hide()

    local activeMode = "lists"
    local function SetMode(mode)
        activeMode = mode
        if mode == "lists" then
            listsContainer:Show()
            sellContainer:Hide()
            modeListsBtn:LockHighlight()
            modeSellBtn:UnlockHighlight()
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
        else
            listsContainer:Hide()
            sellContainer:Show()
            modeSellBtn:LockHighlight()
            modeListsBtn:UnlockHighlight()
            if Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
        end
    end
    Sidecar.SetMode = SetMode

    modeListsBtn:SetScript("OnClick", function() SetMode("lists") end)
    modeSellBtn:SetScript("OnClick", function() SetMode("sell") end)

    -- Toggle Expand / Collapse
    function Sidecar.SetExpanded(expanded)
        MarketSyncDB = MarketSyncDB or {}
        MarketSyncDB.AHSidecarExpanded = (expanded == true)
        if expanded then
            frame:Show()
            toggleBtn:SetText("🛒 MarketSync ◀")
            if activeMode == "lists" and Sidecar.UpdateListsView then
                Sidecar.UpdateListsView()
            elseif activeMode == "sell" and Sidecar.UpdateSellView then
                Sidecar.UpdateSellView()
            end
        else
            frame:Hide()
            toggleBtn:SetText("🛒 MarketSync ▶")
        end
    end

    toggleBtn:SetScript("OnClick", function()
        local isShown = frame:IsShown()
        Sidecar.SetExpanded(not isShown)
    end)

    -- ================================================================
    -- 1. SHOPPING LISTS VIEW
    -- ================================================================
    local currentListName = "Favorites"

    local listControlBar = CreateFrame("Frame", nil, listsContainer)
    listControlBar:SetPoint("TOPLEFT", 6, 0)
    listControlBar:SetPoint("TOPRIGHT", -6, 0)
    listControlBar:SetHeight(58)

    local listLabel = listControlBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listLabel:SetPoint("TOPLEFT", 4, -4)
    listLabel:SetText("Active List:")

    -- List Selection Dropdown
    local listDropdown = CreateFrame("Frame", "MarketSyncSidecarListDropdown", listControlBar, "UIDropDownMenuTemplate")
    listDropdown:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(listDropdown, 140)

    local function InitListDropdown(self, level)
        local lists = MarketSync.Favorites and MarketSync.Favorites.GetLists() or { "Favorites" }
        for _, lName in ipairs(lists) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = lName
            opt.func = function()
                currentListName = lName
                UIDropDownMenu_SetText(listDropdown, lName)
                if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end
    UIDropDownMenu_Initialize(listDropdown, InitListDropdown)
    UIDropDownMenu_SetText(listDropdown, currentListName)

    -- New List Button
    local newListBtn = CreateFrame("Button", nil, listControlBar, "UIPanelButtonTemplate")
    newListBtn:SetSize(62, 22)
    newListBtn:SetPoint("LEFT", listDropdown, "RIGHT", -8, 2)
    newListBtn:SetText("+ New")
    newListBtn:SetScript("OnClick", function()
        StaticPopupDialogs["MARKETSYNC_SIDECAR_NEW_LIST"] = {
            text = "Enter name for new Shopping List:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local text = self.editBox:GetText()
                if text and text ~= "" and MarketSync.Favorites then
                    local ok = MarketSync.Favorites.CreateList(text)
                    if ok then
                        currentListName = text
                        UIDropDownMenu_Initialize(listDropdown, InitListDropdown)
                        UIDropDownMenu_SetText(listDropdown, text)
                        if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MARKETSYNC_SIDECAR_NEW_LIST")
    end)

    -- Delete List Button
    local delListBtn = CreateFrame("Button", nil, listControlBar, "UIPanelButtonTemplate")
    delListBtn:SetSize(42, 22)
    delListBtn:SetPoint("LEFT", newListBtn, "RIGHT", 4, 0)
    delListBtn:SetText("Del")
    delListBtn:SetScript("OnClick", function()
        if currentListName == "Favorites" then
            print("|cFFFF4444[MarketSync]|r Cannot delete the default Favorites list.")
            return
        end
        if MarketSync.Favorites then
            MarketSync.Favorites.DeleteList(currentListName)
            currentListName = "Favorites"
            UIDropDownMenu_Initialize(listDropdown, InitListDropdown)
            UIDropDownMenu_SetText(listDropdown, "Favorites")
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
        end
    end)

    -- Search Entire List Button
    local searchAllBtn = CreateFrame("Button", nil, listsContainer, "UIPanelButtonTemplate")
    searchAllBtn:SetSize(306, 24)
    searchAllBtn:SetPoint("TOPLEFT", listControlBar, "BOTTOMLEFT", 4, 0)
    searchAllBtn:SetText("▶ Search / Scan Entire List")
    searchAllBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            MarketSync.Scanner.ScanList(currentListName)
        end
    end)

    -- Quick Add Bar (EditBox + Drag & Drop Target)
    local addBox = CreateFrame("EditBox", nil, listsContainer, "InputBoxTemplate")
    addBox:SetSize(296, 20)
    addBox:SetPoint("TOPLEFT", searchAllBtn, "BOTTOMLEFT", 6, -8)
    addBox:SetAutoFocus(false)
    addBox:SetText("Drop item or enter name/ID...")
    addBox:SetFontObject("GameFontHighlightSmall")

    addBox:SetScript("OnFocusGained", function(self)
        if self:GetText() == "Drop item or enter name/ID..." then
            self:SetText("")
        end
    end)
    addBox:SetScript("OnFocusLost", function(self)
        if self:GetText() == "" then
            self:SetText("Drop item or enter name/ID...")
        end
    end)
    addBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" and text ~= "Drop item or enter name/ID..." and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(currentListName, text)
            self:SetText("")
            self:ClearFocus()
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
        end
    end)
    addBox:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(currentListName, itemID or itemLink)
            ClearCursor()
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
        end
    end)

    -- Scrollable List Items Table
    local listScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarListScroll", listsContainer, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -6, -8)
    listScroll:SetPoint("BOTTOMRIGHT", -24, 6)

    local listScrollContent = CreateFrame("Frame", nil, listScroll)
    listScrollContent:SetSize(286, 1)
    listScroll:SetScrollChild(listScrollContent)

    local listRows = {}
    local function UpdateListsView()
        local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(currentListName) or {}
        local rowH = 26

        for i = 1, math.max(#items, #listRows) do
            local row = listRows[i]
            local item = items[i]

            if item then
                if not row then
                    row = CreateFrame("Button", nil, listScrollContent, "BackdropTemplate")
                    row:SetHeight(rowH)
                    row:SetPoint("LEFT", 2, 0)
                    row:SetPoint("RIGHT", -2, 0)
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", 4, 0)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", -80, 0)
                    row.name:SetJustifyH("LEFT")

                    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.price:SetPoint("RIGHT", -22, 0)

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

                if i % 2 == 0 then
                    row:SetBackdropColor(0.1, 0.12, 0.15, 0.6)
                else
                    row:SetBackdropColor(0.06, 0.08, 0.1, 0.6)
                end

                row.icon:SetTexture(item.icon)
                local colorHex = "ffffffff"
                if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] then
                    colorHex = ITEM_QUALITY_COLORS[item.quality].hex or "ffffffff"
                end
                row.name:SetText(string.format("|c%s%s|r", colorHex, item.name))
                row.price:SetText(GetPriceText(item.itemID))

                -- Clicking row searches in Auction House!
                row:SetScript("OnClick", function()
                    MarketSync.SearchInAuctionHouse(item.name or item.itemID)
                end)

                -- Tooltip
                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.2, 0.25, 0.35, 0.8)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if item.link and GameTooltip.SetHyperlink then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
                    else
                        GameTooltip:SetText(item.name, 1, 1, 1)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF00FF00Click|r to search in Auction House", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    if i % 2 == 0 then
                        self:SetBackdropColor(0.1, 0.12, 0.15, 0.6)
                    else
                        self:SetBackdropColor(0.06, 0.08, 0.1, 0.6)
                    end
                    GameTooltip:Hide()
                end)

                -- Delete Button
                row.delBtn:SetScript("OnClick", function()
                    if MarketSync.Favorites then
                        MarketSync.Favorites.RemoveFromList(currentListName, item.itemID)
                        UpdateListsView()
                    end
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end
        listScrollContent:SetHeight(math.max(1, #items * rowH))
    end
    Sidecar.UpdateListsView = UpdateListsView

    -- ================================================================
    -- 2. INVENTORY-BASED BAG SELLING VIEW
    -- ================================================================
    local sellFilterBox = CreateFrame("EditBox", nil, sellContainer, "InputBoxTemplate")
    sellFilterBox:SetSize(220, 20)
    sellFilterBox:SetPoint("TOPLEFT", 10, -4)
    sellFilterBox:SetAutoFocus(false)
    sellFilterBox:SetFontObject("GameFontHighlightSmall")
    sellFilterBox:SetText("Filter inventory...")

    sellFilterBox:SetScript("OnFocusGained", function(self)
        if self:GetText() == "Filter inventory..." then self:SetText("") end
    end)
    sellFilterBox:SetScript("OnFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Filter inventory...") end
    end)
    sellFilterBox:SetScript("OnTextChanged", function()
        if Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
    end)

    local refreshBagsBtn = CreateFrame("Button", nil, sellContainer, "UIPanelButtonTemplate")
    refreshBagsBtn:SetSize(80, 22)
    refreshBagsBtn:SetPoint("LEFT", sellFilterBox, "RIGHT", 6, 0)
    refreshBagsBtn:SetText("🔄 Refresh")
    refreshBagsBtn:SetScript("OnClick", function()
        if Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
    end)

    local sellScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarSellScroll", sellContainer, "UIPanelScrollFrameTemplate")
    sellScroll:SetPoint("TOPLEFT", sellFilterBox, "BOTTOMLEFT", -6, -8)
    sellScroll:SetPoint("BOTTOMRIGHT", -24, 6)

    local sellScrollContent = CreateFrame("Frame", nil, sellScroll)
    sellScrollContent:SetSize(286, 1)
    sellScroll:SetScrollChild(sellScrollContent)

    local sellRows = {}
    local function UpdateSellView()
        local allItems = Sidecar.ScanBagsForSelling()
        local query = sellFilterBox:GetText()
        if query == "Filter inventory..." then query = "" end
        query = string.lower(query:match("^%s*(.-)%s*$"))

        local items = {}
        for _, item in ipairs(allItems) do
            if query == "" or string.find(string.lower(item.name or ""), query, 1, true) then
                table.insert(items, item)
            end
        end

        local rowH = 28
        for i = 1, math.max(#items, #sellRows) do
            local row = sellRows[i]
            local item = items[i]

            if item then
                if not row then
                    row = CreateFrame("Button", nil, sellScrollContent, "BackdropTemplate")
                    row:SetHeight(rowH)
                    row:SetPoint("LEFT", 2, 0)
                    row:SetPoint("RIGHT", -2, 0)
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(22, 22)
                    row.icon:SetPoint("LEFT", 4, 0)

                    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", -80, 0)
                    row.name:SetJustifyH("LEFT")

                    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.price:SetPoint("RIGHT", -6, 0)

                    sellRows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                if i % 2 == 0 then
                    row:SetBackdropColor(0.1, 0.12, 0.15, 0.6)
                else
                    row:SetBackdropColor(0.06, 0.08, 0.1, 0.6)
                end

                row.icon:SetTexture(item.icon)
                row.count:SetText(item.totalCount > 1 and tostring(item.totalCount) or "")
                local colorHex = "ffffffff"
                if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] then
                    colorHex = ITEM_QUALITY_COLORS[item.quality].hex or "ffffffff"
                end
                row.name:SetText(string.format("|c%s%s|r", colorHex, item.name))
                row.price:SetText(GetPriceText(item.itemID))

                -- Clicking bag row: switches AH to Sell tab and selects item for posting
                row:SetScript("OnClick", function()
                    -- 1. Switch to native Sell tab
                    if AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[2] then
                        AuctionHouseFrame.Tabs[2]:Click()
                    end

                    -- 2. Pick up item from first slot and place in sell frame
                    local firstSlot = item.slots and item.slots[1]
                    if firstSlot and C_Container and C_Container.PickupContainerItem then
                        C_Container.PickupContainerItem(firstSlot.bag, firstSlot.slot)
                        if AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.ItemDisplay then
                            pcall(AuctionHouseFrame.ItemSellFrame.ItemDisplay.Click, AuctionHouseFrame.ItemSellFrame.ItemDisplay)
                        elseif AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay then
                            pcall(AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.Click, AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay)
                        elseif ClickAuctionSellItemButton then
                            pcall(ClickAuctionSellItemButton)
                        end
                        ClearCursor()
                    end

                    -- 3. Set suggested undercut price
                    local marketP = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(item.itemID)
                    if marketP and marketP > 1 then
                        local undercutPrice = marketP - 1
                        if AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.PriceInput and AuctionHouseFrame.ItemSellFrame.PriceInput.SetAmount then
                            pcall(AuctionHouseFrame.ItemSellFrame.PriceInput.SetAmount, AuctionHouseFrame.ItemSellFrame.PriceInput, undercutPrice)
                        elseif AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.UnitPrice and AuctionHouseFrame.CommoditiesSellFrame.UnitPrice.SetAmount then
                            pcall(AuctionHouseFrame.CommoditiesSellFrame.UnitPrice.SetAmount, AuctionHouseFrame.CommoditiesSellFrame.UnitPrice, undercutPrice)
                        end
                    end
                end)

                -- Tooltip
                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.2, 0.25, 0.35, 0.8)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if item.link and GameTooltip.SetHyperlink then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
                    else
                        GameTooltip:SetText(item.name, 1, 1, 1)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(string.format("In Bags: |cFFFFD100%d|r", item.totalCount), 1, 1, 1)
                    GameTooltip:AddLine("|cFF00FF00Click|r to select into Auction House Sell slot", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    if i % 2 == 0 then
                        self:SetBackdropColor(0.1, 0.12, 0.15, 0.6)
                    else
                        self:SetBackdropColor(0.06, 0.08, 0.1, 0.6)
                    end
                    GameTooltip:Hide()
                end)

                row:Show()
            elseif row then
                row:Hide()
            end
        end
        sellScrollContent:SetHeight(math.max(1, #items * rowH))
    end
    Sidecar.UpdateSellView = UpdateSellView

    -- Bag update event watcher
    local bagEventFrame = CreateFrame("Frame")
    bagEventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    bagEventFrame:SetScript("OnEvent", function()
        if frame:IsShown() and activeMode == "sell" and Sidecar.UpdateSellView then
            Sidecar.UpdateSellView()
        end
    end)

    -- Register with Favorites callbacks
    if MarketSync.Favorites then
        MarketSync.Favorites.RegisterCallback(function()
            if frame:IsShown() and activeMode == "lists" and Sidecar.UpdateListsView then
                UIDropDownMenu_Initialize(listDropdown, InitListDropdown)
                Sidecar.UpdateListsView()
            end
        end)
    end

    -- Initial state: restore previous state or default to true
    local startExpanded = true
    if MarketSyncDB and MarketSyncDB.AHSidecarExpanded ~= nil then
        startExpanded = MarketSyncDB.AHSidecarExpanded
    end
    Sidecar.SetExpanded(startExpanded)

    return frame
end
