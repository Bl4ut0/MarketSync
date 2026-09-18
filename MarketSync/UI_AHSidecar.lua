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
-- ================================================================
-- BAG SCANNER HELPER
-- Scans player inventory grouped by bag container (0 to 5)
-- ================================================================
function Sidecar.ScanBagsForSelling()
    local bags = {}
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    local getContainerInvID = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID

    if type(getNumSlots) ~= "function" then
        return {}
    end

    -- Scan backpack (0) through bags (1-4) and reagent bag (5)
    local maxBags = (NUM_BAG_SLOTS or 4) + 1
    for bag = 0, maxBags do
        local numSlots = getNumSlots(bag) or 0
        if numSlots > 0 then
            local bagName = "Bag " .. bag
            local bagIcon = 133633
            if bag == 0 then
                bagName = "Backpack"
                bagIcon = 130716
            elseif bag == 5 then
                bagName = "Reagent Bag"
                bagIcon = 463560
            elseif getContainerInvID then
                local invID = getContainerInvID(bag)
                if invID then
                    local link = GetInventoryItemLink and GetInventoryItemLink("player", invID)
                    local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", invID)
                    if icon then bagIcon = icon end
                    if link then
                        local infoName = SafeGetItemInfo(link)
                        bagName = infoName or (link:match("%[(.-)%]")) or ("Bag " .. bag)
                    end
                end
            end

            local bagItems = {}
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
                    local _, count, locked, qual, _, _, link, _, _, id, bound = getItemInfo(bag, slot)
                    itemID = id
                    stackCount = count or 1
                    isBound = bound
                    isLocked = locked
                    quality = qual
                    itemLink = link
                end

                -- Filter: valid itemID, not soulbound, and not locked
                if itemID and itemID > 0 and not isBound and not isLocked then
                    local _, _, _, _, _, _, _, _, _, _, _, classID = SafeGetItemInfo(itemID)
                    if classID ~= 12 then -- Not a quest item
                        local name, link, rQual, _, _, _, _, _, _, icon = SafeGetItemInfo(itemID)
                        if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
                            local c = MarketSyncDB.ItemInfoCache[itemID]
                            name = c.n
                            icon = c.ic
                            rQual = c.r
                        end
                        local marketP = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(itemID) or 0
                        table.insert(bagItems, {
                            bag = bag,
                            slot = slot,
                            itemID = itemID,
                            name = name or ("Item #" .. itemID),
                            icon = icon or 134400,
                            quality = quality or rQual or 1,
                            link = itemLink or link or ("item:" .. itemID),
                            stackCount = stackCount or 1,
                            marketPrice = marketP,
                        })
                    end
                end
            end

            table.insert(bags, {
                bagID = bag,
                name = bagName,
                icon = bagIcon,
                totalSlots = numSlots,
                items = bagItems,
            })
        end
    end

    return bags
end

-- ================================================================
-- CONSTRUCT SIDECAR FRAME
-- ================================================================
function MarketSync.CreateAHSidecar(parent)
    if Sidecar.Frame then return Sidecar.Frame end

    local ahFrame = parent or AuctionHouseFrame
    if not ahFrame then return nil end

    -- 1. Drawer Toggle Tab on AH right edge (shown ONLY when sidecar is closed)
    local toggleBtn = CreateFrame("Button", "MarketSyncAHSidecarToggleBtn", ahFrame, "BackdropTemplate")
    toggleBtn:SetSize(22, 70)
    toggleBtn:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", -2, -60)
    toggleBtn:SetFrameLevel(ahFrame:GetFrameLevel() + 5)
    toggleBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    toggleBtn:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
    toggleBtn:SetBackdropBorderColor(0.5, 0.42, 0.25, 0.9)
    toggleBtn:EnableMouse(true)
    toggleBtn:RegisterForClicks("LeftButtonUp")

    local toggleArrow = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggleArrow:SetPoint("CENTER", 0, 0)
    toggleArrow:SetText("|cFFFFD100>|r")

    toggleBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.22, 0.28, 0.95)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("MarketSync Sidecar", 1, 0.82, 0)
        GameTooltip:AddLine("Click to open Shopping Lists & Bag Selling", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
        GameTooltip:Hide()
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(toggleBtn, {
            name = "MarketSync Sidecar",
            context = "Button",
            description = "Expand MarketSync Shopping Lists and Bag Selling drawer",
            tooltipTitle = "MarketSync Sidecar",
            tooltipText = "Click to open Shopping Lists & Bag Selling",
        })
    end

    -- 2. Breakout Sidecar Frame -- aligned neatly with AH frame inset
    local frame = CreateFrame("Frame", "MarketSyncAHSidecarFrame", ahFrame, "BackdropTemplate")
    frame:SetWidth(SIDECAR_WIDTH)
    frame:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", -2, -28)
    frame:SetPoint("BOTTOMLEFT", ahFrame, "BOTTOMRIGHT", -2, 28)
    frame:SetFrameStrata(ahFrame:GetFrameStrata())
    frame:SetFrameLevel(ahFrame:GetFrameLevel() + 1)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.06, 0.07, 0.09, 0.98)
    frame:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.95)
    Sidecar.Frame = frame

    -- Top Header Container
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(28)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    title:SetText("|cFFFFD100MarketSync|r")

    local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        Sidecar.SetExpanded(false)
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(closeBtn, {
            name = "Close Sidecar",
            context = "Button",
            description = "Collapse MarketSync Shopping Lists and Bag Selling drawer",
        })
    end

    -- Separator line under header
    local headerSep = frame:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -2)
    headerSep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -2)
    headerSep:SetColorTexture(0.4, 0.35, 0.2, 0.5)

    -- Mode Switcher Tabs: [ Shopping Lists ]  [ Bag Selling ]
    local tabLists = CreateFrame("Button", nil, frame, "BackdropTemplate")
    tabLists:SetSize(152, 24)
    tabLists:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 2, -6)
    tabLists:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tabLists.label = tabLists:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tabLists.label:SetPoint("CENTER")
    tabLists.label:SetText("Shopping Lists")

    local tabBags = CreateFrame("Button", nil, frame, "BackdropTemplate")
    tabBags:SetSize(152, 24)
    tabBags:SetPoint("LEFT", tabLists, "RIGHT", 4, 0)
    tabBags:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tabBags.label = tabBags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tabBags.label:SetPoint("CENTER")
    tabBags.label:SetText("Bag Selling")

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(tabLists, {
            name = "Shopping Lists",
            context = "Tab",
            description = "Switch to Shopping Lists panel",
            getIndexInfo = function() return { index = 1, total = 2 } end,
        })
        MarketSync.SetAccessibility(tabBags, {
            name = "Bag Selling",
            context = "Tab",
            description = "Switch to Inventory Bag Selling panel",
            getIndexInfo = function() return { index = 2, total = 2 } end,
        })
    end

    -- Content Containers
    local listsContainer = CreateFrame("Frame", nil, frame)
    listsContainer:SetPoint("TOPLEFT", tabLists, "BOTTOMLEFT", -2, -6)
    listsContainer:SetPoint("BOTTOMRIGHT", -6, 6)

    local sellContainer = CreateFrame("Frame", nil, frame)
    sellContainer:SetPoint("TOPLEFT", tabLists, "BOTTOMLEFT", -2, -6)
    sellContainer:SetPoint("BOTTOMRIGHT", -6, 6)
    sellContainer:Hide()

    local activeMode = "lists"
    local function SetMode(mode)
        activeMode = mode
        if mode == "lists" then
            listsContainer:Show()
            sellContainer:Hide()
            tabLists:SetBackdropColor(0.20, 0.24, 0.32, 0.95)
            tabLists:SetBackdropBorderColor(0.6, 0.5, 0.25, 0.9)
            tabLists.label:SetText("|cFFFFD100Shopping Lists|r")
            tabBags:SetBackdropColor(0.08, 0.09, 0.12, 0.6)
            tabBags:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
            tabBags.label:SetText("|cFF888888Bag Selling|r")
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
        else
            listsContainer:Hide()
            sellContainer:Show()
            tabBags:SetBackdropColor(0.20, 0.24, 0.32, 0.95)
            tabBags:SetBackdropBorderColor(0.6, 0.5, 0.25, 0.9)
            tabBags.label:SetText("|cFFFFD100Bag Selling|r")
            tabLists:SetBackdropColor(0.08, 0.09, 0.12, 0.6)
            tabLists:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
            tabLists.label:SetText("|cFF888888Shopping Lists|r")
            if Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
        end
    end
    Sidecar.SetMode = SetMode

    tabLists:SetScript("OnClick", function() SetMode("lists") end)
    tabBags:SetScript("OnClick", function() SetMode("sell") end)

    -- Toggle Expand / Collapse
    function Sidecar.SetExpanded(expanded)
        MarketSyncDB = MarketSyncDB or {}
        MarketSyncDB.AHSidecarExpanded = (expanded == true)
        if expanded then
            frame:Show()
            toggleBtn:Hide()
            if activeMode == "lists" and Sidecar.UpdateListsView then
                Sidecar.UpdateListsView()
            elseif activeMode == "sell" and Sidecar.UpdateSellView then
                Sidecar.UpdateSellView()
            end
        else
            frame:Hide()
            toggleBtn:Show()
        end
    end

    toggleBtn:SetScript("OnClick", function()
        Sidecar.SetExpanded(true)
    end)

    -- ================================================================
    -- 1. SHOPPING LISTS VIEW
    -- ================================================================
    local currentListName = "Favorites"

    local listControlBar = CreateFrame("Frame", nil, listsContainer)
    listControlBar:SetPoint("TOPLEFT", 0, 0)
    listControlBar:SetPoint("TOPRIGHT", 0, 0)
    listControlBar:SetHeight(48)

    local listLabel = listControlBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listLabel:SetPoint("TOPLEFT", 4, -2)
    listLabel:SetText("List:")

    -- Custom styled Dropdown Button
    local dropdownBtn = CreateFrame("Button", nil, listControlBar, "UIPanelButtonTemplate")
    dropdownBtn:SetSize(160, 22)
    dropdownBtn:SetPoint("TOPLEFT", 4, -18)
    dropdownBtn:SetText(currentListName .. "  |cFFFFD100v|r")

    local hiddenDropdown = CreateFrame("Frame", "MarketSyncSidecarListHiddenDropdown", listControlBar, "UIDropDownMenuTemplate")
    hiddenDropdown:Hide()

    local function InitListDropdown(self, level)
        local lists = MarketSync.Favorites and MarketSync.Favorites.GetLists() or { "Favorites" }
        for _, lName in ipairs(lists) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = lName
            opt.checked = (lName == currentListName)
            opt.func = function()
                currentListName = lName
                dropdownBtn:SetText(lName .. "  |cFFFFD100v|r")
                if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end
    UIDropDownMenu_Initialize(hiddenDropdown, InitListDropdown)

    dropdownBtn:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, hiddenDropdown, dropdownBtn, 0, 0)
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(dropdownBtn, {
            name = function() return "Shopping List: " .. (currentListName or "Favorites") end,
            context = "Button",
            description = "Select active shopping list",
        })
    end

    -- New List Button
    local newListBtn = CreateFrame("Button", nil, listControlBar, "UIPanelButtonTemplate")
    newListBtn:SetSize(62, 22)
    newListBtn:SetPoint("LEFT", dropdownBtn, "RIGHT", 4, 0)
    newListBtn:SetText("+ New")
    newListBtn:SetScript("OnClick", function()
        StaticPopupDialogs["MARKETSYNC_SIDECAR_NEW_LIST"] = {
            text = "Enter name for new Shopping List:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName().."EditBox"])
                local text = eb and eb:GetText()
                if text and text ~= "" and MarketSync.Favorites then
                    local ok = MarketSync.Favorites.CreateList(text)
                    if ok then
                        currentListName = text
                        dropdownBtn:SetText(text .. "  |cFFFFD100v|r")
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
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(newListBtn, {
            name = "New Shopping List",
            context = "Button",
            description = "Create a new shopping list",
        })
    end

    -- Delete List Button
    local delListBtn = CreateFrame("Button", nil, listControlBar, "UIPanelButtonTemplate")
    delListBtn:SetSize(52, 22)
    delListBtn:SetPoint("LEFT", newListBtn, "RIGHT", 4, 0)
    delListBtn:SetText("Delete")
    delListBtn:SetScript("OnClick", function()
        if currentListName == "Favorites" then
            print("|cFFFF4444[MarketSync]|r Cannot delete the default Favorites list.")
            return
        end
        if MarketSync.Favorites then
            MarketSync.Favorites.DeleteList(currentListName)
            currentListName = "Favorites"
            dropdownBtn:SetText("Favorites  |cFFFFD100v|r")
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
        end
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(delListBtn, {
            name = "Delete Shopping List",
            context = "Button",
            description = function() return "Delete shopping list " .. (currentListName or "") end,
        })
    end

    -- Search Entire List Button
    local searchAllBtn = CreateFrame("Button", nil, listsContainer, "UIPanelButtonTemplate")
    searchAllBtn:SetSize(298, 24)
    searchAllBtn:SetPoint("TOPLEFT", listControlBar, "BOTTOMLEFT", 4, -2)
    searchAllBtn:SetText("Scan Entire List")
    searchAllBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            if MarketSync.Scanner.Active then
                MarketSync.Scanner.Cancel("User stopped scan")
            else
                local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(currentListName) or {}
                if #items == 0 then
                    print(string.format("|cFFFF4444[MarketSync]|r List '%s' has no items to scan. Drag an item or type its name to add items.", currentListName))
                    return
                end
                MarketSync.Scanner.ScanList(currentListName)
            end
        end
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(searchAllBtn, {
            name = function() return (MarketSync.Scanner and MarketSync.Scanner.Active) and "Stop Scan" or "Scan Entire List" end,
            context = "Button",
            description = function() return "Scan all items in " .. (currentListName or "") .. " on the Auction House" end,
        })
    end

    -- Unified Drag & Drop Handler for Item Adding
    local function HandleSidecarItemDrop()
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(currentListName, itemID or itemLink)
            ClearCursor()
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
            return true
        end
        return false
    end

    -- Quick Add Bar (EditBox + Drag & Drop Target)
    local addBox = CreateFrame("EditBox", nil, listsContainer, "InputBoxTemplate")
    addBox:SetSize(296, 20)
    addBox:SetPoint("TOPLEFT", searchAllBtn, "BOTTOMLEFT", 6, -8)
    addBox:SetAutoFocus(false)
    addBox:SetText("Drop item or enter name/ID...")
    addBox:SetFontObject("GameFontHighlightSmall")

    addBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Drop item or enter name/ID..." then
            self:SetText("")
        end
    end)
    addBox:SetScript("OnEditFocusLost", function(self)
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
    addBox:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    addBox:SetScript("OnMouseUp", function(self, button)
        if HandleSidecarItemDrop() then
            self:ClearFocus()
        end
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(addBox, {
            name = "Add Item",
            context = "Edit Box",
            description = "Drop an item or type name or ID to add to current shopping list",
        })
    end

    -- Recessed Inset for List Items
    local listInset = CreateFrame("Frame", nil, listsContainer, "BackdropTemplate")
    listInset:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -6, -6)
    listInset:SetPoint("BOTTOMRIGHT", 0, 0)
    listInset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    listInset:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
    listInset:SetBackdropBorderColor(0.20, 0.22, 0.26, 0.90)
    listInset:EnableMouse(true)
    listInset:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    listInset:SetScript("OnMouseUp", function(self, button)
        HandleSidecarItemDrop()
    end)

    -- Scrollable List Items Table
    local listScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarListScroll", listInset, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 2, -3)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 3)
    listScroll:EnableMouse(true)
    listScroll:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    listScroll:SetScript("OnMouseUp", function(self, button)
        HandleSidecarItemDrop()
    end)

    local listScrollContent = CreateFrame("Frame", nil, listScroll)
    listScrollContent:SetSize(280, 1)
    listScroll:SetScrollChild(listScrollContent)
    listScrollContent:EnableMouse(true)
    listScrollContent:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    listScrollContent:SetScript("OnMouseUp", function(self, button)
        HandleSidecarItemDrop()
    end)

    local listEmptyText = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listEmptyText:SetPoint("CENTER", 0, 20)
    listEmptyText:SetText("No items in this list.\n\nDrag an item here or type\nits name above to add.")

    local listRows = {}
    local function UpdateListsView()
        local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(currentListName) or {}
        local rowH = 26

        if #items == 0 then
            listEmptyText:Show()
        else
            listEmptyText:Hide()
        end

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
                    row.name:SetPoint("RIGHT", -76, 0)
                    row.name:SetJustifyH("LEFT")

                    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.price:SetPoint("RIGHT", -20, 0)

                    row.delBtn = CreateFrame("Button", nil, row)
                    row.delBtn:SetSize(16, 16)
                    row.delBtn:SetPoint("RIGHT", -2, 0)
                    row.delBtn.text = row.delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.delBtn.text:SetPoint("CENTER")
                    row.delBtn.text:SetText("|cFFFF4444x|r")

                    listRows[i] = row
                end

                row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)

                if i % 2 == 0 then
                    row:SetBackdropColor(0.09, 0.11, 0.14, 0.7)
                else
                    row:SetBackdropColor(0.05, 0.06, 0.08, 0.7)
                end

                row.icon:SetTexture(item.icon)
                row.name:SetText(MarketSync.FormatColoredItemName and MarketSync.FormatColoredItemName(item.name, item.quality) or item.name)
                row.price:SetText(GetPriceText(item.itemID))

                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "RightButton" then
                        if MarketSync.ShowAnalytics and item.itemID then
                            MarketSync.ShowAnalytics(tostring(item.itemID), item.link, item.name, item.icon, MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(item.itemID))
                        end
                    else
                        MarketSync.SearchInAuctionHouse(item.name or item.itemID)
                    end
                end)

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.18, 0.22, 0.30, 0.9)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if item.link and GameTooltip.SetHyperlink then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
                    else
                        GameTooltip:SetText(item.name, 1, 1, 1)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF00FF00Left-Click|r: Search in Auction House", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("|cFF00FF00Right-Click|r: View Analytics & Tracking", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    if i % 2 == 0 then
                        self:SetBackdropColor(0.09, 0.11, 0.14, 0.7)
                    else
                        self:SetBackdropColor(0.05, 0.06, 0.08, 0.7)
                    end
                    GameTooltip:Hide()
                end)

                row.delBtn:SetScript("OnClick", function()
                    if MarketSync.Favorites then
                        MarketSync.Favorites.RemoveFromList(currentListName, item.itemID)
                        UpdateListsView()
                    end
                end)

                if MarketSync.SetAccessibility then
                    MarketSync.SetAccessibility(row, {
                        name = function() return item.name or "Item" end,
                        context = "Button",
                        description = function()
                            local price = (item.itemID and MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(item.itemID)) or 0
                            local priceSpoken = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(price) or (price .. " copper")
                            return string.format("%s, Market price %s. Left-click to search in Auction House, Right-click for analytics.", item.name or "", priceSpoken)
                        end,
                        getIndexInfo = function() return { index = i, total = #items } end,
                    })
                    MarketSync.SetAccessibility(row.delBtn, {
                        name = "Remove from list",
                        context = "Button",
                        description = function() return "Remove " .. (item.name or "item") .. " from shopping list" end,
                    })
                end

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
    sellFilterBox:SetSize(210, 20)
    sellFilterBox:SetPoint("TOPLEFT", 4, -4)
    sellFilterBox:SetAutoFocus(false)
    sellFilterBox:SetFontObject("GameFontHighlightSmall")
    sellFilterBox:SetText("Filter inventory...")

    sellFilterBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Filter inventory..." then self:SetText("") end
    end)
    sellFilterBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Filter inventory...") end
    end)
    sellFilterBox:SetScript("OnTextChanged", function()
        if Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
    end)

    local refreshBagsBtn = CreateFrame("Button", nil, sellContainer, "UIPanelButtonTemplate")
    refreshBagsBtn:SetSize(78, 22)
    refreshBagsBtn:SetPoint("LEFT", sellFilterBox, "RIGHT", 6, 0)
    refreshBagsBtn:SetText("Refresh")
    refreshBagsBtn:SetScript("OnClick", function()
        if Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
    end)

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(sellFilterBox, {
            name = "Filter Inventory",
            context = "Edit Box",
            description = "Type to filter bag items by name",
        })
        MarketSync.SetAccessibility(refreshBagsBtn, {
            name = "Refresh Bags",
            context = "Button",
            description = "Scan player bags for auctionable items",
        })
    end

    -- Recessed Inset for Bag Selling
    local sellInset = CreateFrame("Frame", nil, sellContainer, "BackdropTemplate")
    sellInset:SetPoint("TOPLEFT", sellFilterBox, "BOTTOMLEFT", -4, -6)
    sellInset:SetPoint("BOTTOMRIGHT", 0, 0)
    sellInset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    sellInset:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
    sellInset:SetBackdropBorderColor(0.20, 0.22, 0.26, 0.90)

    local sellScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarSellScroll", sellInset, "UIPanelScrollFrameTemplate")
    sellScroll:SetPoint("TOPLEFT", 2, -3)
    sellScroll:SetPoint("BOTTOMRIGHT", -22, 3)

    local sellScrollContent = CreateFrame("Frame", nil, sellScroll)
    sellScrollContent:SetSize(288, 1)
    sellScroll:SetScrollChild(sellScrollContent)

    local sellEmptyText = sellInset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sellEmptyText:SetPoint("CENTER", 0, 20)
    sellEmptyText:SetText("No auctionable items found in bags.")

    local bagHeaderPool = {}
    local slotButtonPool = {}

    local function UpdateSellView()
        local bags = Sidecar.ScanBagsForSelling()
        local query = sellFilterBox:GetText()
        if query == "Filter inventory..." then query = "" end
        query = string.lower(query:match("^%s*(.-)%s*$") or "")

        -- Hide existing pooled elements
        for _, h in ipairs(bagHeaderPool) do h:Hide() end
        for _, b in ipairs(slotButtonPool) do b:Hide() end

        local yOffset = -4
        local totalMatching = 0
        local headerIndex = 0
        local slotButtonIndex = 0

        for _, bag in ipairs(bags) do
            local matching = {}
            for _, item in ipairs(bag.items or {}) do
                if query == "" or string.find(string.lower(item.name or ""), query, 1, true) then
                    table.insert(matching, item)
                end
            end

            if #matching > 0 then
                totalMatching = totalMatching + #matching
                headerIndex = headerIndex + 1
                local header = bagHeaderPool[headerIndex]
                if not header then
                    header = CreateFrame("Frame", nil, sellScrollContent, "BackdropTemplate")
                    header:SetSize(284, 22)
                    header:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8",
                        edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 },
                    })
                    header:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
                    header:SetBackdropBorderColor(0.22, 0.25, 0.30, 0.85)

                    header.icon = header:CreateTexture(nil, "ARTWORK")
                    header.icon:SetSize(16, 16)
                    header.icon:SetPoint("LEFT", 4, 0)

                    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    header.title:SetPoint("LEFT", header.icon, "RIGHT", 6, 0)
                    header.title:SetPoint("RIGHT", -80, 0)
                    header.title:SetJustifyH("LEFT")

                    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    header.count:SetPoint("RIGHT", -6, 0)

                    bagHeaderPool[headerIndex] = header
                end

                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", sellScrollContent, "TOPLEFT", 2, yOffset)
                header.icon:SetTexture(bag.icon)
                header.title:SetText(bag.name)
                header.count:SetText(string.format("|cFFFFD100%d|r/%d items", #matching, bag.totalSlots))
                header:Show()

                yOffset = yOffset - 26

                -- Render 6-column item slot grid
                local numRows = math.ceil(#matching / 6)
                for idx, item in ipairs(matching) do
                    slotButtonIndex = slotButtonIndex + 1
                    local btn = slotButtonPool[slotButtonIndex]
                    if not btn then
                        btn = CreateFrame("Button", nil, sellScrollContent, "BackdropTemplate")
                        btn:SetSize(42, 42)
                        btn:SetBackdrop({
                            bgFile = "Interface\\Buttons\\WHITE8X8",
                            edgeFile = "Interface\\Buttons\\WHITE8X8",
                            edgeSize = 1,
                            insets = { left = 1, right = 1, top = 1, bottom = 1 },
                        })
                        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                        btn.icon = btn:CreateTexture(nil, "ARTWORK")
                        btn.icon:SetSize(36, 36)
                        btn.icon:SetPoint("CENTER", 0, 0)

                        btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                        btn.count:SetPoint("BOTTOMRIGHT", -2, 2)

                        slotButtonPool[slotButtonIndex] = btn
                    end

                    local col = (idx - 1) % 6
                    local row = math.floor((idx - 1) / 6)
                    local x = 6 + col * 46
                    local y = yOffset - row * 46

                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", sellScrollContent, "TOPLEFT", x, y)
                    btn.icon:SetTexture(item.icon)
                    btn.count:SetText(item.stackCount > 1 and tostring(item.stackCount) or "")
                    btn.stackCount = item.stackCount
                    btn.item = item

                    local qColor = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality] or { r = 0.4, g = 0.4, b = 0.4 }
                    btn:SetBackdropColor(0.06, 0.08, 0.10, 0.95)
                    btn:SetBackdropBorderColor(qColor.r or 0.4, qColor.g or 0.4, qColor.b or 0.4, 0.85)

                    btn:SetScript("OnEnter", function(self)
                        self:SetBackdropBorderColor(1, 0.82, 0, 1)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if item.link and GameTooltip.SetHyperlink then
                            pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
                        else
                            GameTooltip:SetText(item.name, 1, 1, 1)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(string.format("%s (Slot %d)", bag.name, item.slot), 0.8, 0.8, 0.8)
                        GameTooltip:AddLine(string.format("Stack Count: |cFFFFD100%d|r", item.stackCount), 1, 1, 1)
                        if item.marketPrice and item.marketPrice > 0 then
                            local priceStr = MarketSync.FormatMoney and MarketSync.FormatMoney(item.marketPrice) or tostring(item.marketPrice)
                            GameTooltip:AddLine(string.format("Market Price: %s", priceStr), 1, 1, 1)
                            local under = math.max(1, item.marketPrice - 1)
                            local underStr = MarketSync.FormatMoney and MarketSync.FormatMoney(under) or tostring(under)
                            GameTooltip:AddLine(string.format("Suggested Undercut (-1c): %s", underStr), 0.4, 1.0, 0.4)
                        else
                            GameTooltip:AddLine("Market Price: |cff888888No data|r", 1, 1, 1)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFF00FF00Left-Click|r: Select into AH Sell slot", 0.9, 0.9, 0.9)
                        GameTooltip:AddLine("|cFFFFD100Right-Click|r: Search in Auction House", 0.9, 0.9, 0.9)
                        GameTooltip:Show()
                    end)

                    btn:SetScript("OnLeave", function(self)
                        self:SetBackdropBorderColor(qColor.r or 0.4, qColor.g or 0.4, qColor.b or 0.4, 0.85)
                        GameTooltip:Hide()
                    end)

                    btn:SetScript("OnClick", function(self, mouseButton)
                        if mouseButton == "RightButton" then
                            MarketSync.SearchInAuctionHouse(item.itemID)
                            return
                        end

                        -- 1. Switch to native Sell tab
                        if AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[2] then
                            AuctionHouseFrame.Tabs[2]:Click()
                        end

                        -- 2. Pick up item from container slot and place in sell frame
                        local pFunc = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
                        if pFunc then
                            pFunc(item.bag, item.slot)
                            if AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.ItemDisplay then
                                pcall(AuctionHouseFrame.ItemSellFrame.ItemDisplay.Click, AuctionHouseFrame.ItemSellFrame.ItemDisplay)
                            elseif AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay then
                                pcall(AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.Click, AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay)
                            elseif ClickAuctionSellItemButton then
                                pcall(ClickAuctionSellItemButton)
                            end
                            ClearCursor()
                        end

                        -- 3. Set suggested undercut price (marketPrice - 1 copper)
                        if item.marketPrice and item.marketPrice > 1 then
                            local undercutPrice = item.marketPrice - 1
                            if AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.PriceInput and AuctionHouseFrame.ItemSellFrame.PriceInput.SetAmount then
                                pcall(AuctionHouseFrame.ItemSellFrame.PriceInput.SetAmount, AuctionHouseFrame.ItemSellFrame.PriceInput, undercutPrice)
                            elseif AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.UnitPrice and AuctionHouseFrame.CommoditiesSellFrame.UnitPrice.SetAmount then
                                pcall(AuctionHouseFrame.CommoditiesSellFrame.UnitPrice.SetAmount, AuctionHouseFrame.CommoditiesSellFrame.UnitPrice, undercutPrice)
                            end
                        end
                    end)

                    if MarketSync.SetAccessibility then
                        MarketSync.SetAccessibility(btn, {
                            name = function() return item.name or "Bag Item" end,
                            context = "Button",
                            description = function()
                                local countStr = item.stackCount > 1 and (item.stackCount .. " items") or "1 item"
                                local priceDesc = ""
                                if item.marketPrice and item.marketPrice > 0 then
                                    local pSpoken = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(item.marketPrice) or (item.marketPrice .. " copper")
                                    local uSpoken = MarketSync.FormatNarrationMoney and MarketSync.FormatNarrationMoney(math.max(1, item.marketPrice - 1)) or (math.max(1, item.marketPrice - 1) .. " copper")
                                    priceDesc = string.format("Market price %s, suggested undercut %s. ", pSpoken, uSpoken)
                                end
                                return string.format("%s, %s, %s slot %d. %sLeft-click to select into sell slot, Right-click to search in Auction House.", item.name or "", countStr, bag.name or "Bag", item.slot or 1, priceDesc)
                            end,
                            getIndexInfo = function() return { index = idx, total = #matching } end,
                        })
                    end

                    btn:Show()
                end

                yOffset = yOffset - (numRows * 46) - 10
            end
        end

        if totalMatching == 0 then
            sellEmptyText:Show()
        else
            sellEmptyText:Hide()
        end

        sellScrollContent:SetHeight(math.max(1, -yOffset))
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
                dropdownBtn:SetText(currentListName .. "  |cFFFFD100v|r")
                Sidecar.UpdateListsView()
            end
        end)
    end

    -- Register with Scanner callbacks for live progress & prices
    if MarketSync.Scanner then
        MarketSync.Scanner.RegisterCallback(function()
            if not frame:IsShown() then return end
            if activeMode == "lists" then
                if MarketSync.Scanner.Active then
                    local cur = (MarketSync.Scanner.Progress and MarketSync.Scanner.Progress.current) or 0
                    local tot = (MarketSync.Scanner.Progress and MarketSync.Scanner.Progress.total) or 0
                    searchAllBtn:SetText(string.format("Scanning (%d/%d)... Stop", cur, tot))
                else
                    searchAllBtn:SetText("Scan Entire List")
                end
                if Sidecar.UpdateListsView then
                    Sidecar.UpdateListsView()
                end
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
