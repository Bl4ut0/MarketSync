-- ================================================================
-- MarketSync - Auction House Breakout Sidecar
-- Integrated Shopping Lists (quick search & batch buy) +
-- Inventory-Based Bag Selling (match lowest market price & 1-click select/post)
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
    if MarketSync.Scanner and MarketSync.Scanner.IsLegacyAH then
        local name = type(itemOrName) == "string" and itemOrName or nil
        local itemID = tonumber(itemOrName)
        if not name and itemID then
            name = SafeGetItemInfo(itemID)
            if not name and MarketSyncDB and MarketSyncDB.ItemInfoCache
                and MarketSyncDB.ItemInfoCache[itemID] then
                name = MarketSyncDB.ItemInfoCache[itemID].n
            end
        end
        if not name or name == "" then return false end
        name = name:match("%[(.-)%]") or name
        local selectedTab = AuctionFrame and PanelTemplates_GetSelectedTab
            and PanelTemplates_GetSelectedTab(AuctionFrame)
        local auctionatorShopping = _G.AuctionatorTabs_Shopping
        local useAuctionator = Auctionator and Auctionator.API and Auctionator.API.v1
            and type(Auctionator.API.v1.MultiSearchExact) == "function"
            and ((MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true)
                or (auctionatorShopping and selectedTab == auctionatorShopping:GetID()))
        if useAuctionator then
            local ok = pcall(Auctionator.API.v1.MultiSearchExact, "MarketSync", { name })
            if ok then return true end
        end
        if selectedTab == 1 and _G.BrowseName and _G.BrowseSearchButton then
            _G.BrowseName:SetText(name)
            _G.BrowseSearchButton:Click()
            return true
        end
        return MarketSync.OpenLegacySearch and MarketSync.OpenLegacySearch(name) or false
    end
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

function MarketSync.OpenCraftListForRecipe(recipeOrItemID)
    if not MarketSync.MainFrame then return false end
    if MarketSync.RefreshKnownCraftingRecipes then MarketSync.RefreshKnownCraftingRecipes() end
    if not MarketSync.MainFrame:IsShown() then MarketSync.MainFrame:Show() end
    local host = AuctionHouseFrame or AuctionFrame or MarketSync.MainFrame
    if MarketSync.CreateAHSidecar then MarketSync.CreateAHSidecar(host) end
    if not Sidecar.ShowForMain then return false end
    Sidecar.ShowForMain("craft")
    if recipeOrItemID and Sidecar.AddCraftRecipe then
        local ok, reason = Sidecar.AddCraftRecipe(recipeOrItemID)
        if not ok then print("|cffff4444[MarketSync]|r " .. tostring(reason)) end
        return ok
    end
    return true
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
-- Toggles the Shopping / Craft / Bags panel from anywhere (slash commands), creating
-- it first if neither the Auction House nor the MarketSync window has done so.
function MarketSync.ToggleSidecarAnywhere(mode)
    if not Sidecar.Frame and MarketSync.CreateAHSidecar then
        MarketSync.CreateAHSidecar(AuctionHouseFrame or AuctionFrame or MarketSync.MainFrame or UIParent)
    end
    if Sidecar.Toggle then Sidecar.Toggle(mode) end
end

function MarketSync.CreateAHSidecar(parent)
    if Sidecar.Frame then return Sidecar.Frame end

    local ahFrame = parent or AuctionHouseFrame
    if not ahFrame then return nil end
    local legacyAH = MarketSync.Scanner and MarketSync.Scanner.IsLegacyAH

    -- 1. Drawer Toggle Tab on AH right edge (shown ONLY when sidecar is closed)
    local toggleBtn = CreateFrame("Button", "MarketSyncAHSidecarToggleBtn", ahFrame, "BackdropTemplate")
    toggleBtn:SetSize(18, 38)
    toggleBtn:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", -2, -60)
    toggleBtn:SetFrameLevel(ahFrame:GetFrameLevel() + (legacyAH and 31 or 5))
    toggleBtn:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    toggleBtn:SetBackdropColor(MarketSync.GetThemeColor("header"))
    toggleBtn:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
    toggleBtn:EnableMouse(true)
    toggleBtn:RegisterForClicks("LeftButtonUp")

    local toggleArrow = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggleArrow:SetPoint("CENTER", 0, 0)
    toggleArrow:SetText("|cFFFFD100>|r")

    toggleBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("MarketSync Sidecar", 1, 0.82, 0)
        GameTooltip:AddLine("Click to open Shopping Lists & Bag Selling", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(MarketSync.GetThemeColor("header"))
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

    -- Created without an Auction House or MarketSync window (floating only): the
    -- AH edge tab has nothing to attach to until the AH opens.
    if ahFrame == UIParent then toggleBtn:Hide() end

    local frame = MarketSync.Theme.CreateStandardWindow("MarketSyncAHSidecarFrame", "MarketSync Sidecar",
        SIDECAR_WIDTH, 400, "Interface\\Icons\\INV_Misc_Book_09", true)
    frame:ClearAllPoints()
    frame:SetHeight(0)
    frame:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", -2, -28)
    frame:SetPoint("BOTTOMLEFT", ahFrame, "BOTTOMRIGHT", -2, 28)
    frame:SetFrameStrata(ahFrame:GetFrameStrata())
    frame:SetFrameLevel(ahFrame:GetFrameLevel() + (legacyAH and 30 or 1))
    Sidecar.Frame = frame
    Sidecar.host = "ah"

    local closeBtn = frame.CloseButton
    closeBtn:SetScript("OnClick", function()
        if Sidecar.host == "float" then
            frame:Hide()
        elseif Sidecar.host == "main" and Sidecar.HideForMain then
            Sidecar.HideForMain()
        else
            Sidecar.SetExpanded(false)
        end
    end)

    -- Pop-out / dock button: detaches the drawer into a free-standing window, or
    -- docks a floating one back to the Auction House or the main window.
    local popBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    popBtn:SetSize(48, 18)
    popBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    popBtn:SetText("Float")
    if popBtn.GetFontString and popBtn:GetFontString() then
        popBtn:GetFontString():SetFontObject(GameFontNormalSmall)
    end
    popBtn:SetScript("OnClick", function()
        if Sidecar.host == "float" then
            Sidecar.Dock(Sidecar.currentMode)
        else
            Sidecar.ShowFloating(Sidecar.currentMode)
        end
    end)
    popBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if Sidecar.host == "float" then
            GameTooltip:SetText("Dock", 1, 0.82, 0)
            GameTooltip:AddLine("Attach this panel back to the Auction House or the MarketSync window.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText("Float", 1, 0.82, 0)
            GameTooltip:AddLine("Open this panel as its own movable window. /sidecar also opens it on its own.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    popBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Sidecar.PopButton = popBtn

    -- Remember where a floating panel was left.
    frame:HookScript("OnDragStop", function(self)
        if Sidecar.host ~= "float" then return end
        local point, _, relativePoint, x, y = self:GetPoint(1)
        MarketSyncDB = MarketSyncDB or {}
        MarketSyncDB.FloatingSidecar = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(closeBtn, {
            name = "Close Sidecar",
            context = "Button",
            description = "Collapse MarketSync Shopping Lists and Bag Selling drawer",
        })
    end


    -- Mode Switcher Tabs: [ Shopping ] [ Craft ] [ Bags ]
    local compactLegacy = frame._marketSyncCompactLegacyArt ~= nil
    local tabHeight, tabTop, tabGap = 24, compactLegacy and 39 or 33, 4
    local tabRight = compactLegacy and 12 or 10
    local tabLists = CreateFrame("Button", nil, frame, "BackdropTemplate")
    tabLists:SetHeight(tabHeight)
    tabLists:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local tabListsHl = tabLists:CreateTexture(nil, "HIGHLIGHT")
    tabListsHl:SetAllPoints(tabLists)
    tabListsHl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    tabListsHl:SetBlendMode("ADD")
    tabListsHl:SetAlpha(0.25)
    tabLists.icon = tabLists:CreateTexture(nil, "ARTWORK")
    if tabLists.icon then
        if tabLists.icon.SetSize then tabLists.icon:SetSize(12, 12) end
        if tabLists.icon.SetPoint then tabLists.icon:SetPoint("LEFT", 7, 0) end
        if tabLists.icon.SetTexture then tabLists.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01") end
        if tabLists.icon.SetTexCoord then tabLists.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    tabLists.label = tabLists:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tabLists.label:SetPoint("CENTER", 6, 0)
    tabLists.label:SetText("Shopping")

    local tabCraft = CreateFrame("Button", nil, frame, "BackdropTemplate")
    tabCraft:SetHeight(tabHeight)
    tabCraft:SetPoint("LEFT", tabLists, "RIGHT", tabGap, 0)
    tabCraft:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local tabCraftHl = tabCraft:CreateTexture(nil, "HIGHLIGHT")
    tabCraftHl:SetAllPoints(tabCraft)
    tabCraftHl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    tabCraftHl:SetBlendMode("ADD")
    tabCraftHl:SetAlpha(0.25)
    tabCraft.icon = tabCraft:CreateTexture(nil, "ARTWORK")
    if tabCraft.icon then
        if tabCraft.icon.SetSize then tabCraft.icon:SetSize(12, 12) end
        if tabCraft.icon.SetPoint then tabCraft.icon:SetPoint("LEFT", 7, 0) end
        if tabCraft.icon.SetTexture then tabCraft.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing") end
        if tabCraft.icon.SetTexCoord then tabCraft.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    tabCraft.label = tabCraft:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tabCraft.label:SetPoint("CENTER", 6, 0)
    tabCraft.label:SetText("Craft")

    local tabBags = CreateFrame("Button", nil, frame, "BackdropTemplate")
    tabBags:SetHeight(tabHeight)
    tabBags:SetPoint("LEFT", tabCraft, "RIGHT", tabGap, 0)
    tabBags:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local tabBagsHl = tabBags:CreateTexture(nil, "HIGHLIGHT")
    tabBagsHl:SetAllPoints(tabBags)
    tabBagsHl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    tabBagsHl:SetBlendMode("ADD")
    tabBagsHl:SetAlpha(0.25)
    tabBags.icon = tabBags:CreateTexture(nil, "ARTWORK")
    if tabBags.icon then
        if tabBags.icon.SetSize then tabBags.icon:SetSize(12, 12) end
        if tabBags.icon.SetPoint then tabBags.icon:SetPoint("LEFT", 7, 0) end
        if tabBags.icon.SetTexture then tabBags.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08") end
        if tabBags.icon.SetTexCoord then tabBags.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    tabBags.label = tabBags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tabBags.label:SetPoint("CENTER", 6, 0)
    tabBags.label:SetText("Bags")

    local function LayoutModeTabs()
        local portrait = frame.warcraftRing or frame.PortraitContainer or frame.portrait
        local portraitWidth = portrait and portrait.GetWidth and portrait:GetWidth() or 0
        local tabLeft = math.max(62, portraitWidth + 8)
        local tabWidth = math.floor((frame:GetWidth() - tabLeft - tabRight - 2 * tabGap) / 3)
        tabLists:ClearAllPoints()
        tabLists:SetPoint("TOPLEFT", frame, "TOPLEFT", tabLeft, -tabTop)
        for _, tab in ipairs({ tabLists, tabCraft, tabBags }) do
            tab:SetWidth(math.max(1, tabWidth))
        end
    end
    frame:HookScript("OnSizeChanged", LayoutModeTabs)
    frame:HookScript("OnShow", LayoutModeTabs)
    LayoutModeTabs()

    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(tabLists, {
            name = "Shopping Lists",
            context = "Tab",
            description = "Switch to Shopping Lists panel",
            getIndexInfo = function() return { index = 1, total = 3 } end,
        })
        MarketSync.SetAccessibility(tabCraft, {
            name = "Craft Lists", context = "Tab",
            description = "Switch to crafting recipe and materials checklist",
            getIndexInfo = function() return { index = 2, total = 3 } end,
        })
        MarketSync.SetAccessibility(tabBags, {
            name = "Bag Selling",
            context = "Tab",
            description = "Switch to Inventory Bag Selling panel",
            getIndexInfo = function() return { index = 3, total = 3 } end,
        })
    end

    -- Content Containers
    local contentTop = -(tabTop + tabHeight + 6)
    local contentBottom = compactLegacy and 8 or 6
    local contentRight = compactLegacy and -8 or -6
    local listsContainer = CreateFrame("Frame", nil, frame)
    listsContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, contentTop)
    listsContainer:SetPoint("BOTTOMRIGHT", contentRight, contentBottom)

    local sellContainer = CreateFrame("Frame", nil, frame)
    sellContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, contentTop)
    sellContainer:SetPoint("BOTTOMRIGHT", contentRight, contentBottom)
    sellContainer:Hide()

    local craftContainer = CreateFrame("Frame", nil, frame)
    craftContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, contentTop)
    craftContainer:SetPoint("BOTTOMRIGHT", contentRight, contentBottom)
    craftContainer:Hide()

    local activeMode = "lists"

    local function SetMode(mode)
        if mode ~= "craft" and mode ~= "sell" then mode = "lists" end
        activeMode = mode
        Sidecar.currentMode = mode
        listsContainer:SetShown(mode == "lists")
        craftContainer:SetShown(mode == "craft")
        sellContainer:SetShown(mode == "sell")
        for _, tab in ipairs({ tabLists, tabCraft, tabBags }) do
            local selected = (tab == tabLists and mode == "lists")
                or (tab == tabCraft and mode == "craft") or (tab == tabBags and mode == "sell")
            if selected then
                tab:SetBackdropColor(MarketSync.GetThemeColor("hover"))
                tab:SetBackdropBorderColor(1, 0.82, 0, 0.95)
            else
                tab:SetBackdropColor(MarketSync.GetThemeColor("header"))
                tab:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder", 0.85))
            end
        end
        tabLists.label:SetText(mode == "lists" and "|cFFFFD100Shopping|r" or "|cFFB0A080Shopping|r")
        tabCraft.label:SetText(mode == "craft" and "|cFFFFD100Craft|r" or "|cFFB0A080Craft|r")
        tabBags.label:SetText(mode == "sell" and "|cFFFFD100Bags|r" or "|cFFB0A080Bags|r")
        if mode == "lists" and Sidecar.UpdateListsView then Sidecar.UpdateListsView()
        elseif mode == "craft" and Sidecar.UpdateCraftView then Sidecar.UpdateCraftView()
        elseif mode == "sell" and Sidecar.UpdateSellView then Sidecar.UpdateSellView() end
    end
    Sidecar.SetMode = SetMode

    tabLists:SetScript("OnClick", function() SetMode("lists") end)
    tabCraft:SetScript("OnClick", function() SetMode("craft") end)
    tabBags:SetScript("OnClick", function() SetMode("sell") end)

    -- Toggle Expand / Collapse
    function Sidecar.SetExpanded(expanded)
        if Sidecar.host == "ah" and Sidecar.AHVisible == false then return end
        MarketSyncDB = MarketSyncDB or {}
        MarketSyncDB.AHSidecarExpanded = (expanded == true)
        if expanded then
            frame:Show()
            toggleBtn:Hide()
            if activeMode == "lists" and Sidecar.UpdateListsView then
                Sidecar.UpdateListsView()
            elseif activeMode == "craft" and Sidecar.UpdateCraftView then
                Sidecar.UpdateCraftView()
            elseif activeMode == "sell" and Sidecar.UpdateSellView then
                Sidecar.UpdateSellView()
            end
        else
            frame:Hide()
            if Sidecar.host == "ah" then toggleBtn:Show() else toggleBtn:Hide() end
        end
    end

    local function AuctionHouseShown()
        local ah = AuctionHouseFrame or AuctionFrame
        return ah and ah.IsShown and ah:IsShown() and Sidecar.AHVisible ~= false
    end

    local function MainShown()
        return MarketSync.MainFrame and MarketSync.MainFrame:IsShown()
    end

    -- Opens the panel: docked to the Auction House when it is open, docked to the
    -- MarketSync window when that is open, otherwise as a floating window.
    function Sidecar.Toggle(mode)
        if frame:IsShown() then
            if Sidecar.host == "float" then
                frame:Hide()
            elseif Sidecar.host == "main" and Sidecar.HideForMain then
                Sidecar.HideForMain()
            else
                Sidecar.SetExpanded(false)
            end
        elseif AuctionHouseShown() then
            Sidecar.SetVisibleForAH(true)
            Sidecar.SetExpanded(true)
            if mode then SetMode(mode) end
        elseif MainShown() then
            Sidecar.ShowForMain(mode)
        else
            Sidecar.ShowFloating(mode)
        end
    end

    -- Free-standing, movable panel that does not need the Auction House or the
    -- MarketSync window, for managing shopping and favorites lists on their own.
    function Sidecar.ShowFloating(mode)
        local wasMain = Sidecar.host == "main"
        Sidecar.host = "float"
        if frame.SetParent then frame:SetParent(UIParent) end
        frame:ClearAllPoints()
        frame:SetHeight(420)
        local pos = MarketSyncDB and MarketSyncDB.FloatingSidecar
        if pos and pos.point then
            frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        frame:SetFrameStrata("MEDIUM")
        if frame.SetToplevel then frame:SetToplevel(true) end
        if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
        frame:Show()
        if MarketSync.EnsureFrameOnScreen then MarketSync.EnsureFrameOnScreen(frame) end
        toggleBtn:Hide()
        -- The docking tab on the MarketSync window stays available while floating.
        if wasMain and Sidecar.MainToggleButton then Sidecar.MainToggleButton:Show() end
        if Sidecar.PopButton then Sidecar.PopButton:SetText("Dock") end
        SetMode(mode or Sidecar.currentMode or "lists")
    end

    -- Attaches a floating panel back to the Auction House or the MarketSync window.
    -- With neither open it stays floating.
    function Sidecar.Dock(mode)
        if AuctionHouseShown() then
            Sidecar.SetVisibleForAH(true, true)
            Sidecar.SetExpanded(true)
            if mode then SetMode(mode) end
        elseif MainShown() then
            Sidecar.ShowForMain(mode)
        else
            print("|cFFFFD100[MarketSync]|r Open the Auction House or the MarketSync window to dock this panel.")
        end
    end
    MarketSync.ToggleAHSidecar = Sidecar.Toggle
    MarketSync.AHSidecar.Toggle = Sidecar.Toggle

    toggleBtn:SetScript("OnClick", function()
        Sidecar.SetExpanded(true)
    end)
    Sidecar.ToggleButton = toggleBtn
    -- forceDock: dock even when the panel is currently floating (the Dock button).
    -- Otherwise an open floating panel stays where the player put it when the
    -- Auction House opens or closes.
    function Sidecar.SetVisibleForAH(visible, forceDock)
        Sidecar.AHVisible = visible == true
        local keepFloating = Sidecar.host == "float" and frame:IsShown() and not forceDock
        if visible then
            local host = AuctionHouseFrame or AuctionFrame or ahFrame
            toggleBtn:SetParent(host)
            toggleBtn:ClearAllPoints()
            toggleBtn:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, -60)
            if keepFloating then
                toggleBtn:Hide()
                return
            end
            Sidecar.host = "ah"
            frame:ClearAllPoints()
            frame:SetHeight(0)
            frame:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, -28)
            frame:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", -2, 28)
            frame:SetFrameStrata(host:GetFrameStrata())
            if Sidecar.PopButton then Sidecar.PopButton:SetText("Float") end
        elseif keepFloating then
            toggleBtn:Hide()
            return
        end
        if not visible and Sidecar.host ~= "main" then
            frame:Hide()
            toggleBtn:Hide()
        elseif visible and MarketSyncDB and MarketSyncDB.AHSidecarExpanded then
            frame:Show()
            toggleBtn:Hide()
        elseif visible then
            frame:Hide()
            toggleBtn:Show()
        end
    end
    function Sidecar.ShowForMain(mode)
        if not MarketSync.MainFrame then return end
        if not Sidecar.mainHideHooked then
            MarketSync.MainFrame:HookScript("OnHide", function()
                if Sidecar.host == "main" then frame:Hide() end
            end)
            Sidecar.mainHideHooked = true
        end
        Sidecar.host = "main"
        if Sidecar.PopButton then Sidecar.PopButton:SetText("Float") end
        frame:ClearAllPoints()
        frame:SetHeight(0)
        frame:SetPoint("TOPLEFT", MarketSync.MainFrame, "TOPRIGHT", -2, -28)
        frame:SetPoint("BOTTOMLEFT", MarketSync.MainFrame, "BOTTOMRIGHT", -2, 28)
        frame:SetFrameStrata(MarketSync.MainFrame:GetFrameStrata())
        frame:Show()
        toggleBtn:Hide()
        MarketSyncDB = MarketSyncDB or {}
        MarketSyncDB.MainSidecarExpanded = true
        if Sidecar.MainToggleButton then Sidecar.MainToggleButton:Hide() end
        SetMode(mode or Sidecar.currentMode or "lists")
    end
    function Sidecar.HideForMain()
        if Sidecar.host ~= "main" then return end
        frame:Hide()
        MarketSyncDB = MarketSyncDB or {}
        MarketSyncDB.MainSidecarExpanded = false
        if Sidecar.MainToggleButton then Sidecar.MainToggleButton:Show() end
    end

    -- ================================================================
    -- CRAFT LISTS: saved recipes and their reagent checklist
    -- ================================================================
    local currentCraftList = "Crafts"
    local craftLabel = craftContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftLabel:SetPoint("TOPLEFT", 6, -3)
    craftLabel:SetText("Craft list:")
    local craftDropdown = CreateFrame("Button", nil, craftContainer, "UIPanelButtonTemplate")
    craftDropdown:SetSize(160, 22)
    craftDropdown:SetPoint("TOPLEFT", 4, -19)
    local craftMenu = CreateFrame("Frame", "MarketSyncSidecarCraftDropdown", craftContainer, "UIDropDownMenuTemplate")
    craftMenu:Hide()
    local function GetCraftList()
        for _, list in ipairs(MarketSync.ListProcessingCraftSets and MarketSync.ListProcessingCraftSets() or {}) do
            if list.name == currentCraftList then return list end
        end
        return { name = currentCraftList, itemIDs = {}, checked = {}, choices = {},
            selectedBuys = {}, quantities = {}, recipes = {} }
    end
    function Sidecar.GetActiveCraftListName() return currentCraftList end
    local function RefreshCraftDropdown()
        craftDropdown:SetText(currentCraftList .. "  |cFFFFD100v|r")
    end
    UIDropDownMenu_Initialize(craftMenu, function(self, level)
        for _, list in ipairs(MarketSync.ListProcessingCraftSets and MarketSync.ListProcessingCraftSets() or {}) do
            local name = list.name
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = name
            opt.checked = name == currentCraftList
            opt.func = function()
                currentCraftList = name
                RefreshCraftDropdown()
                if Sidecar.UpdateCraftView then Sidecar.UpdateCraftView() end
            end
            UIDropDownMenu_AddButton(opt, level)
        end
    end)
    craftDropdown:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, craftMenu, craftDropdown, 0, 0)
    end)
    RefreshCraftDropdown()

    local craftNew = CreateFrame("Button", nil, craftContainer, "UIPanelButtonTemplate")
    craftNew:SetSize(62, 22)
    craftNew:SetPoint("LEFT", craftDropdown, "RIGHT", 4, 0)
    craftNew:SetText("+ New")
    craftNew:SetScript("OnClick", function()
        StaticPopupDialogs["MARKETSYNC_SIDECAR_NEW_CRAFT_LIST"] = {
            text = "Enter name for new Craft List:", button1 = "Create", button2 = "Cancel",
            hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(self)
                local box = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                local name = box and box:GetText()
                if name and name ~= "" and MarketSync.UpsertProcessingCraftSet then
                    local saved = MarketSync.UpsertProcessingCraftSet(name, {})
                    if saved then
                        currentCraftList = saved.name
                        RefreshCraftDropdown()
                        Sidecar.UpdateCraftView()
                    end
                end
            end,
        }
        StaticPopup_Show("MARKETSYNC_SIDECAR_NEW_CRAFT_LIST")
    end)
    local craftDelete = CreateFrame("Button", nil, craftContainer, "UIPanelButtonTemplate")
    craftDelete:SetSize(52, 22)
    craftDelete:SetPoint("LEFT", craftNew, "RIGHT", 4, 0)
    craftDelete:SetText("Delete")
    craftDelete:SetScript("OnClick", function()
        if MarketSync.DeleteProcessingCraftSet then
            MarketSync.DeleteProcessingCraftSet(currentCraftList)
            local lists = MarketSync.ListProcessingCraftSets and MarketSync.ListProcessingCraftSets() or {}
            currentCraftList = lists[1] and lists[1].name or "Crafts"
            RefreshCraftDropdown()
            Sidecar.UpdateCraftView()
        end
    end)

    local craftHint = craftContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    craftHint:SetPoint("TOPLEFT", 7, -49)
    craftHint:SetPoint("RIGHT", craftContainer, "RIGHT", -7, 0)
    craftHint:SetJustifyH("LEFT")
    craftHint:SetText("Left check = Craft; Buy check = purchase, else provide.")
    local craftSearch = CreateFrame("Button", nil, craftContainer, "UIPanelButtonTemplate")
    craftSearch:SetSize(145, 21)
    craftSearch:SetPoint("TOPLEFT", 8, -69)
    craftSearch:SetText("Scan Buy Materials")
    craftSearch:SetScript("OnClick", function()
        local plan = MarketSync.BuildCraftPurchasePlan(GetCraftList())
        local ids = {}
        for id, buy in pairs(plan.buys) do
            if not buy.isVendor then ids[#ids + 1] = id end
        end
        table.sort(ids)
        if #ids == 0 then
            print("|cffffaa00[MarketSync]|r No Auction House materials marked Buy in this Craft list.")
        elseif legacyAH and MarketSync.OpenLegacySearch then
            MarketSync.OpenLegacySearch(ids)
        elseif MarketSync.Scanner and MarketSync.Scanner.StartScan then
            MarketSync.Scanner.StartScan(ids, "Craft list: " .. currentCraftList)
        end
    end)
    local craftExport = CreateFrame("Button", nil, craftContainer, "UIPanelButtonTemplate")
    craftExport:SetSize(145, 21)
    craftExport:SetPoint("LEFT", craftSearch, "RIGHT", 4, 0)
    craftExport:SetText("Copy to Shopping")
    craftExport:SetScript("OnClick", function()
        local ok, countOrReason, name = MarketSync.ExportCraftPurchasesToShoppingList(GetCraftList())
        if ok then
            print(string.format("|cff00ff00[MarketSync]|r %d material types exported to Shopping list: %s", countOrReason, name))
        else
            print("|cffff4444[MarketSync]|r " .. tostring(countOrReason))
        end
    end)
    local craftAdd = CreateFrame("EditBox", nil, craftContainer, "InputBoxTemplate")
    craftAdd:SetSize(296, 20)
    craftAdd:SetPoint("TOPLEFT", 8, -95)
    craftAdd:SetAutoFocus(false)
    craftAdd:SetText("Item ID or link...")
    craftAdd:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Item ID or link..." then self:SetText("") end
    end)
    craftAdd:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local craftInset = CreateFrame("Frame", nil, craftContainer, "BackdropTemplate")
    craftInset:SetPoint("TOPLEFT", craftAdd, "BOTTOMLEFT", -6, -8)
    craftInset:SetPoint("BOTTOMRIGHT", craftContainer, "BOTTOMRIGHT", 0, 0)
    craftInset:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    craftInset._marketSyncThemeRole = "inset"
    craftInset:SetBackdropColor(MarketSync.GetThemeColor("inset"))
    craftInset:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
    local craftScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarCraftScroll", craftInset,
        "UIPanelScrollFrameTemplate")
    craftScroll:SetPoint("TOPLEFT", 2, -3)
    craftScroll:SetPoint("BOTTOMRIGHT", -17, 3)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(craftScroll) end
    local craftRowsFrame = CreateFrame("Frame", nil, craftScroll)
    craftRowsFrame:SetSize(278, 1)
    craftScroll:SetScrollChild(craftRowsFrame)
    local craftRows = {}
    local function CraftItemName(id)
        local name = SafeGetItemInfo(id)
        local cached = MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[id]
        return name or (cached and cached.n) or ("Item " .. tostring(id))
    end
    local function BuildCraftRows(list)
        local rows = {}
        local function AddNode(node, depth, seen)
            if not node or not node.itemID or depth > 4 then return end
            rows[#rows + 1] = { id = node.itemID, qty = node.qty or 1, depth = depth,
                craftable = node.canCraft, chooseCraft = node.chooseCraft,
                activeBuy = not node.chooseCraft,
                provided = not node.chooseCraft and (list.selectedBuys or {})[node.itemID] == false }
            if node.chooseCraft and node.subMats and not seen[node.itemID] then
                local nextSeen = {}
                for key, value in pairs(seen) do nextSeen[key] = value end
                nextSeen[node.itemID] = true
                for _, child in ipairs(node.subMats) do AddNode(child, depth + 1, nextSeen) end
            end
        end
        for _, id in ipairs(list.itemIDs or {}) do
            local qty = math.max(1, math.floor(tonumber((list.quantities or {})[id]) or 1))
            rows[#rows + 1] = { id = id, depth = 0, output = true, qty = qty }
            local recipe = list.recipes and list.recipes[id]
            local cost = MarketSync.CalculateGroundUpCraftCost and MarketSync.CalculateGroundUpCraftCost(recipe or id, list.choices, qty)
            for _, node in ipairs(cost and cost.reagentsTree or {}) do AddNode(node, 1, {}) end
        end
        return rows
    end
    function Sidecar.UpdateCraftView()
        RefreshCraftDropdown()
        local list = GetCraftList()
        local entries = BuildCraftRows(list)
        local plan = MarketSync.BuildCraftPurchasePlan and MarketSync.BuildCraftPurchasePlan(list)
        craftHint:SetText(#entries == 0 and "Drop a crafted item or recipe to plan materials."
            or string.format("%d recipes | Buy %d | Provide %d", #(list.itemIDs or {}),
                plan and plan.buyCount or 0, plan and plan.providedCount or 0))
        for i = 1, math.max(#entries, #craftRows) do
            local entry = entries[i]
            local row = craftRows[i]
            if entry then
                if not row then
                    row = CreateFrame("Button", nil, craftRowsFrame)
                    row:SetHeight(24)
                    row:SetPoint("LEFT", 2, 0)
                    row:SetPoint("RIGHT", -2, 0)
                    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    row.check:SetSize(18, 18)
                    row.check:SetPoint("LEFT", 0, 0)
                    row.buyCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    row.buyCheck:SetSize(18, 18)
                    row.buyCheck:SetPoint("RIGHT", -1, 0)
                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("RIGHT", row, "RIGHT", -24, 0)
                    row.name:SetJustifyH("LEFT")
                    row.remove = CreateFrame("Button", nil, row)
                    row.remove:SetSize(18, 18)
                    row.remove:SetPoint("RIGHT", -2, 0)
                    row.remove.label = row.remove:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.remove.label:SetPoint("CENTER")
                    row.remove.label:SetText("|cffff4444x|r")
                    row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.minus:SetSize(16, 17)
                    row.minus:SetText("-")
                    row.minus:SetPoint("RIGHT", row.remove, "LEFT", -1, 0)
                    row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.plus:SetSize(16, 17)
                    row.plus:SetText("+")
                    row.plus:SetPoint("RIGHT", row.minus, "LEFT", -1, 0)
                    craftRows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", craftRowsFrame, "TOPLEFT", 0, -(i - 1) * 24)
                row:SetPoint("TOPRIGHT", craftRowsFrame, "TOPRIGHT", 0, -(i - 1) * 24)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.check, "RIGHT", 3 + math.min(3, entry.depth) * 9, 0)
                row.name:SetPoint("RIGHT", row, "RIGHT", entry.output and -77 or (entry.craftable and -24 or -8), 0)
                local tag = entry.output and "Edit craft: " or (entry.chooseCraft and "CRAFT: "
                    or (entry.provided and "PROVIDE: " or "BUY: "))
                row.name:SetText((entry.output and "|cffffd700" or "|cffcccccc")
                    .. tag .. CraftItemName(entry.id) .. (entry.qty and (" x" .. entry.qty) or "") .. "|r")
                row.check:SetShown(not entry.output)
                row.check:SetChecked(entry.craftable and entry.chooseCraft
                    or (not entry.craftable and (list.selectedBuys or {})[entry.id] ~= false))
                row.check:SetScript("OnClick", function(self)
                    local latest = GetCraftList()
                    if entry.craftable then
                        latest.choices[entry.id] = self:GetChecked() == true
                    else
                        latest.selectedBuys[entry.id] = self:GetChecked() == true
                    end
                    MarketSync.UpsertProcessingCraftSet(latest.name, latest.itemIDs, latest.checked,
                        latest.choices, latest.selectedBuys, latest.quantities, latest.recipes)
                    Sidecar.UpdateCraftView()
                end)
                row.check:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(entry.craftable and "Craft this component when checked"
                        or "Buy this material when checked; otherwise provide it")
                    GameTooltip:Show()
                end)
                row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.buyCheck:SetShown(entry.craftable and not entry.chooseCraft)
                row.buyCheck:SetChecked((list.selectedBuys or {})[entry.id] ~= false)
                row.buyCheck:SetScript("OnClick", function(self)
                    local latest = GetCraftList()
                    latest.selectedBuys[entry.id] = self:GetChecked() == true
                    MarketSync.UpsertProcessingCraftSet(latest.name, latest.itemIDs, latest.checked,
                        latest.choices, latest.selectedBuys, latest.quantities, latest.recipes)
                    Sidecar.UpdateCraftView()
                end)
                row.buyCheck:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Buy this component when checked; otherwise provide it")
                    GameTooltip:Show()
                end)
                row.buyCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.plus:SetShown(entry.output == true)
                row.minus:SetShown(entry.output == true)
                local function SetCraftQty(delta)
                    local latest = GetCraftList()
                    latest.quantities[entry.id] = math.max(1, math.min(999,
                        (tonumber(latest.quantities[entry.id]) or 1) + delta))
                    MarketSync.UpsertProcessingCraftSet(latest.name, latest.itemIDs, latest.checked,
                        latest.choices, latest.selectedBuys, latest.quantities, latest.recipes)
                    Sidecar.UpdateCraftView()
                end
                row.plus:SetScript("OnClick", function() SetCraftQty(1) end)
                row.minus:SetScript("OnClick", function() SetCraftQty(-1) end)
                row.remove:SetShown(entry.output == true)
                row.remove:SetScript("OnClick", function()
                    local latest = GetCraftList()
                    for index, id in ipairs(latest.itemIDs) do
                        if id == entry.id then table.remove(latest.itemIDs, index); break end
                    end
                    MarketSync.UpsertProcessingCraftSet(latest.name, latest.itemIDs, latest.checked,
                        latest.choices, latest.selectedBuys, latest.quantities, latest.recipes)
                    Sidecar.UpdateCraftView()
                end)
                row:SetScript("OnClick", function()
                    if not entry.output then return end
                    local latest = GetCraftList()
                    local recipe = latest.recipes and latest.recipes[entry.id]
                        or (MarketSync.GetRecipeForOutput and MarketSync.GetRecipeForOutput(entry.id))
                    if recipe and MarketSync.OpenCraftingTree then
                        MarketSync.OpenCraftingTree(recipe, nil, latest)
                    end
                end)
                row:Show()
            elseif row then row:Hide() end
        end
        craftRowsFrame:SetHeight(math.max(1, #entries * 24))
    end
    function Sidecar.AddCraftRecipe(itemOrLink, listName, options)
        local suppliedRecipe = type(itemOrLink) == "table" and itemOrLink.mats and itemOrLink or nil
        local id = suppliedRecipe and tonumber(suppliedRecipe.outputItemID)
            or tonumber(itemOrLink) or (type(itemOrLink) == "string"
            and tonumber(itemOrLink:match("item:(%d+)")))
        if not id and MarketSync.ResolveItemID then id = MarketSync.ResolveItemID(itemOrLink) end
        if listName and listName ~= "" then currentCraftList = listName end
        local list = GetCraftList()
        local recipe = suppliedRecipe or (list.recipes and list.recipes[id])
            or (MarketSync.GetRecipeForOutput and MarketSync.GetRecipeForOutput(id))
        if not id or not recipe then
            return false, "No known recipe for this item. Open its profession first."
        end
        list.recipes = list.recipes or {}
        if suppliedRecipe and MarketSync.SnapshotCraftRecipe then
            list.recipes[id] = MarketSync.SnapshotCraftRecipe(suppliedRecipe)
        end
        if type(options) == "table" then
            list.choices = list.choices or {}
            list.selectedBuys = list.selectedBuys or {}
            list.quantities = list.quantities or {}
            if options.choices then
                for itemID, value in pairs(options.choices) do list.choices[itemID] = value end
            end
            if options.selectedBuys then
                for itemID, value in pairs(options.selectedBuys) do list.selectedBuys[itemID] = value end
            end
            if options.quantity then list.quantities[id] = options.quantity end
        end
        for _, existing in ipairs(list.itemIDs) do
            if existing == id then
                MarketSync.UpsertProcessingCraftSet(list.name, list.itemIDs, list.checked,
                    list.choices, list.selectedBuys, list.quantities, list.recipes)
                if Sidecar.UpdateCraftView then Sidecar.UpdateCraftView() end
                return true
            end
        end
        list.itemIDs[#list.itemIDs + 1] = id
        MarketSync.UpsertProcessingCraftSet(list.name, list.itemIDs, list.checked,
            list.choices, list.selectedBuys, list.quantities, list.recipes)
        if Sidecar.UpdateCraftView then Sidecar.UpdateCraftView() end
        return true
    end
    local function HandleCraftDrop()
        if not GetCursorInfo then return false end
        local kind, value, link = GetCursorInfo()
        if kind ~= "item" and kind ~= "spell" then return false end
        if kind == "spell" and MarketSync.RefreshKnownCraftingRecipes then
            MarketSync.RefreshKnownCraftingRecipes()
        end
        local output = kind == "spell" and MarketSync.GetCraftOutputForRecipeID
            and MarketSync.GetCraftOutputForRecipeID(value) or nil
        local ok, reason = Sidecar.AddCraftRecipe(output or (kind == "item" and (link or value)))
        if ok then ClearCursor() else print("|cffff4444[MarketSync]|r " .. tostring(reason)) end
        return ok
    end
    for _, target in ipairs({ craftAdd, craftInset, craftScroll, craftRowsFrame }) do
        target:EnableMouse(true)
        target:SetScript("OnReceiveDrag", HandleCraftDrop)
        target:SetScript("OnMouseUp", HandleCraftDrop)
    end
    craftAdd:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local ok, reason = Sidecar.AddCraftRecipe(text)
        if not ok then print("|cffff4444[MarketSync]|r " .. tostring(reason)) end
        self:SetText("")
        self:ClearFocus()
    end)

    -- ================================================================
    -- 1. SHOPPING LISTS VIEW
    -- ================================================================
    -- The selected list is shared with the legacy Scan page (Favorites.GetSelectedList).
    local Fav = MarketSync.Favorites
    local currentListName = (Fav and Fav.GetSelectedList and Fav.GetSelectedList()) or "Favorites"
    function Sidecar.GetSelectedShoppingListName() return currentListName end

    local listControlBar = CreateFrame("Frame", nil, listsContainer)
    listControlBar:SetPoint("TOPLEFT", 0, 0)
    listControlBar:SetPoint("TOPRIGHT", 0, 0)
    listControlBar:SetHeight(27)

    local actionsBtn = CreateFrame("Button", "MarketSyncSidecarListActions", listControlBar, "UIPanelButtonTemplate")
    actionsBtn:SetSize(84, 25)
    actionsBtn:SetPoint("RIGHT", listControlBar, "RIGHT", -1, 0)
    actionsBtn:SetText("Actions v")

    local searchAllBtn = CreateFrame("Button", "MarketSyncSidecarListScan", listControlBar, "UIPanelButtonTemplate")
    searchAllBtn:SetSize(58, 25)
    searchAllBtn:SetPoint("RIGHT", actionsBtn, "LEFT", -6, 0)
    searchAllBtn:SetText("Scan")

    local dropdownBtn = CreateFrame("Button", "MarketSyncSidecarListPicker", listControlBar, "UIPanelButtonTemplate")
    dropdownBtn:SetHeight(25)
    dropdownBtn:SetPoint("LEFT", listControlBar, "LEFT", 1, 0)
    dropdownBtn:SetPoint("RIGHT", searchAllBtn, "LEFT", -6, 0)
    dropdownBtn:SetText(currentListName .. "  |cFFFFD100v|r")
    local pickerText = dropdownBtn.GetFontString and dropdownBtn:GetFontString()
    if pickerText then
        pickerText:SetWidth(SIDECAR_WIDTH - 182)
        pickerText:SetWordWrap(false)
    end
    function Sidecar.SelectShoppingList(name)
        currentListName = name
        dropdownBtn:SetText(name .. "  |cFFFFD100v|r")
        if Fav and Fav.SetSelectedList then Fav.SetSelectedList(name) end
        if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
    end

    local hiddenDropdown = CreateFrame("Frame", "MarketSyncSidecarListHiddenDropdown", listControlBar, "UIDropDownMenuTemplate")
    hiddenDropdown:Hide()

    local function InitListDropdown(self, level)
        local lists = MarketSync.Favorites and MarketSync.Favorites.GetLists() or { "Favorites" }
        for _, lName in ipairs(lists) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text = lName
            opt.checked = (lName == currentListName)
            opt.func = function()
                Sidecar.SelectShoppingList(lName)
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

    local function PromptListText(dialogKey, text, action, onAccept)
        StaticPopupDialogs[dialogKey] = {
            text = text, button1 = action, button2 = "Cancel", hasEditBox = true,
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(popup)
                local input = popup.editBox or popup.EditBox or (popup.GetName and _G[popup:GetName() .. "EditBox"])
                local value = input and input:GetText()
                value = value and value:match("^%s*(.-)%s*$")
                if not value or value == "" then return end
                local ok, reason = onAccept(value)
                if not ok and reason then print("|cffff4444[MarketSync]|r " .. reason) end
            end,
        }
        StaticPopup_Show(dialogKey)
    end

    local function RemoveListItem(listName, value)
        local favorites = MarketSync.Favorites
        local match, ambiguous
        local name = value:lower()
        local key = value:find("item:", 1, true) and MarketSync.Scanner and MarketSync.Scanner.ToItemKey
            and MarketSync.Scanner.ToItemKey(value)
        if key and key.itemSuffix and key.itemSuffix > 0 then
            return favorites.RemoveFromList(listName, string.format("p:%d:%d", key.itemID, key.itemSuffix))
        end
        for _, item in ipairs(favorites.GetListItems(listName)) do
            if value == item.dbKey then
                return favorites.RemoveFromList(listName, item.dbKey)
            end
            if value == item.link or tonumber(value) == item.itemID or (item.name and item.name:lower() == name) then
                ambiguous = ambiguous or match ~= nil
                match = match or item.dbKey or item.itemID
            end
        end
        if ambiguous then return false, "More than one item matches. Enter the exact item key or link." end
        if not match then return false, "Item not found in " .. listName .. "." end
        return favorites.RemoveFromList(listName, match)
    end

    local actionsMenu = CreateFrame("Frame", "MarketSyncSidecarListActionsMenu", listControlBar, "UIDropDownMenuTemplate")
    actionsMenu:Hide()
    UIDropDownMenu_Initialize(actionsMenu, function(_, level)
        if level ~= 1 then return end
        local listName = currentListName
        local favorites = MarketSync.Favorites
        local tracked = MarketSync.CraftLedger and MarketSync.CraftLedger.FindShoppingList(listName)
        local canRemoveItems = favorites and not tracked and #favorites.GetList(listName) > 0
        local function AddAction(label, callback, disabled)
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.notCheckable = true
            info.disabled = disabled
            info.func = function()
                if disabled then return end
                if CloseDropDownMenus then CloseDropDownMenus() end
                callback()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        AddAction("Add Item...", function()
            PromptListText("MARKETSYNC_SIDECAR_ADD_ITEM", "Add an item by name, ID, or link.", "Add", function(value)
                return favorites.AddToList(listName, value)
            end)
        end, not favorites)
        AddAction("Remove Item...", function()
            PromptListText("MARKETSYNC_SIDECAR_REMOVE_ITEM", "Remove an item by name, ID, or link.", "Remove", function(value)
                return RemoveListItem(listName, value)
            end)
        end, not canRemoveItems)
        AddAction("New List...", function()
            PromptListText("MARKETSYNC_SIDECAR_NEW_LIST", "Name the new shopping list.", "Create", function(name)
                local ok, reason = favorites.CreateList(name)
                if ok then Sidecar.SelectShoppingList(name) end
                return ok, reason
            end)
        end, not favorites)
        AddAction("Delete List", function()
            if tracked then
                if MarketSync.OpenCraftManager then MarketSync.OpenCraftManager(tracked.id) end
                print("|cffffcc00[MarketSync]|r Update or remove the tracked craft to change its shopping list.")
            elseif favorites.DeleteList(listName) then
                Sidecar.SelectShoppingList("Favorites")
            end
        end, not favorites or listName == "Favorites")
        AddAction("Import List...", function()
            MarketSync.ShowListImportDialog({ onSuccess = function(result)
                if result and result.listName then Sidecar.SelectShoppingList(result.listName) end
            end })
        end, not MarketSync.ShowListImportDialog)
        AddAction("Export List...", function()
            MarketSync.ShowListExportDialog(listName)
        end, not MarketSync.ShowListExportDialog)
    end, "MENU")
    actionsBtn:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, actionsMenu, actionsBtn, 0, 0)
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(actionsBtn, {
            name = "Shopping list actions",
            context = "Button",
            tooltipTitle = "List Actions",
            tooltipText = "Add or remove items, manage lists, and import or export.",
        })
    end
    searchAllBtn:SetScript("OnClick", function()
        if MarketSync.Scanner then
            if MarketSync.Scanner.Active then
                MarketSync.Scanner.Cancel("User stopped scan")
            else
                local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(currentListName) or {}
                if #items == 0 then
                    print(string.format("|cFFFF4444[MarketSync]|r List '%s' has no items to scan. Drop an item here or use Actions > Add Item.", currentListName))
                    return
                end
                if legacyAH and MarketSync.OpenLegacySearch then
                    MarketSync.OpenLegacySearch(items)
                else
                    MarketSync.Scanner.ScanList(currentListName)
                end
            end
        end
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(searchAllBtn, {
            name = function() return (MarketSync.Scanner and MarketSync.Scanner.Active) and "Stop Scan" or "Scan Entire List" end,
            context = "Button",
            description = function() return "Scan all items in " .. (currentListName or "") .. " on the Auction House" end,
            tooltipText = function()
                local scanner = MarketSync.Scanner
                if scanner and scanner.Active then
                    local progress = scanner.Progress or {}
                    return string.format("Scanning %d of %d. Click to stop.", progress.current or 0, progress.total or 0)
                end
                return "Scan all items in " .. currentListName .. "."
            end,
        })
    end

    -- Unified Drag & Drop Handler for Item Adding
    local function HandleSidecarItemDrop()
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and MarketSync.Favorites then
            MarketSync.Favorites.AddToList(currentListName, itemLink or itemID)
            ClearCursor()
            if Sidecar.UpdateListsView then Sidecar.UpdateListsView() end
            return true
        end
        return false
    end

    local listInset = MarketSync.CreateModernInset(listsContainer)
    listInset:SetPoint("TOPLEFT", listControlBar, "BOTTOMLEFT", 0, -5)
    listInset:SetPoint("BOTTOMRIGHT", 0, 0)
    listInset:EnableMouse(true)
    listInset:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    listInset:SetScript("OnMouseUp", function(self, button)
        HandleSidecarItemDrop()
    end)

    -- Scrollable List Items Table
    local listScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarListScroll", listInset, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -5)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 5)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(listScroll) end
    listScroll:EnableMouse(true)
    listScroll:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    listScroll:SetScript("OnMouseUp", function(self, button)
        HandleSidecarItemDrop()
    end)

    local listScrollContent = CreateFrame("Frame", nil, listScroll)
    listScrollContent:SetSize(SIDECAR_WIDTH - 38, 1)
    listScroll:SetScrollChild(listScrollContent)
    listScroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then listScrollContent:SetWidth(width) end
    end)
    listScrollContent:EnableMouse(true)
    listScrollContent:SetScript("OnReceiveDrag", HandleSidecarItemDrop)
    listScrollContent:SetScript("OnMouseUp", function(self, button)
        HandleSidecarItemDrop()
    end)

    local listEmptyText = listInset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listEmptyText:SetPoint("CENTER")
    listEmptyText:SetText("No items in this list.\nDrop an item here or use Actions > Add Item.")

    local listRows = {}
    local function UpdateListsView()
        local items = MarketSync.Favorites and MarketSync.Favorites.GetListItems(currentListName) or {}
        local rowH = 26
        searchAllBtn:SetText(MarketSync.Scanner and MarketSync.Scanner.Active and "Stop" or "Scan")

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
                    row:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8",
                        edgeSize = 1,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 }
                    })
                    local hl = row:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints(row)
                    hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
                    hl:SetBlendMode("ADD")
                    hl:SetAlpha(0.25)
                    row.hl = hl

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", 4, 0)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetJustifyH("LEFT")
                    row.name:SetWordWrap(false)

                    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.price:SetPoint("RIGHT", -20, 0)
                    row.name:SetPoint("RIGHT", row.price, "LEFT", -6, 0)

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
                    row:SetBackdropColor(MarketSync.GetThemeColor("rowEven"))
                else
                    row:SetBackdropColor(MarketSync.GetThemeColor("rowOdd"))
                end
                row:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))

                row.icon:SetTexture(item.icon)
                local quantity = item.quantity or (MarketSync.Favorites.GetQuantity and MarketSync.Favorites.GetQuantity(currentListName, item.itemID)) or 1
                local itemMeta = MarketSync.Favorites.GetItemMeta and MarketSync.Favorites.GetItemMeta(currentListName, item.dbKey or item.itemID)
                local suffix = tonumber(item.suffix or (itemMeta and itemMeta.suffix)) or 0
                local priceKey = (suffix > 0 and item.dbKey) or item.itemID
                local isDone = (item.done == true) or (itemMeta and itemMeta.done == true) or false
                local maxPrice = tonumber(item.maxPrice or (itemMeta and itemMeta.maxPrice))
                local itemNote = item.note or (itemMeta and itemMeta.note)

                local baseName = item.name or ("Item #" .. tostring(item.itemID))
                if suffix > 0 and not baseName:find("%+" .. suffix) then
                    baseName = baseName .. " (+" .. suffix .. ")"
                end
                local displayName = MarketSync.FormatColoredItemName and MarketSync.FormatColoredItemName(baseName, item.quality) or baseName
                local prefix = isDone and "|cff66cc66[Done]|r " or ""
                row.name:SetText(prefix .. displayName .. (quantity > 1 and (" x" .. quantity) or ""))
                if row.SetAlpha then row:SetAlpha(isDone and 0.60 or 1.0) end

                local priceText = GetPriceText(priceKey)
                local marketPrice = MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(priceKey) or nil
                if marketPrice and marketPrice > 0 and maxPrice and maxPrice > 0 then
                    if marketPrice <= maxPrice then
                        priceText = "|cff44ff44" .. priceText .. "|r"
                    else
                        priceText = "|cffffaa44" .. priceText .. "|r"
                    end
                end
                row.price:SetText(priceText)

                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "RightButton" then
                        if MarketSync.ShowAnalytics and item.itemID then
                            local analyticsKey = (suffix > 0 and item.dbKey) or tostring(item.itemID)
                            MarketSync.ShowAnalytics(analyticsKey, item.link, item.name, item.icon, MarketSync.GetAuctionPrice and MarketSync.GetAuctionPrice(priceKey))
                        end
                    else
                        MarketSync.SearchInAuctionHouse(item.name or item.itemID)
                    end
                end)

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if item.link and GameTooltip.SetHyperlink then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
                    else
                        GameTooltip:SetText(item.name, 1, 1, 1)
                    end
                    if maxPrice and maxPrice > 0 then
                        local fmtMax = MarketSync.FormatMoney and MarketSync.FormatMoney(maxPrice) or (tostring(maxPrice) .. "c")
                        GameTooltip:AddLine("Target Max: " .. fmtMax, 0.9, 0.85, 0.3)
                    end
                    if type(itemNote) == "string" and itemNote ~= "" then
                        GameTooltip:AddLine("Note: " .. itemNote, 0.85, 0.85, 0.85, true)
                    end
                    if isDone then
                        GameTooltip:AddLine("Status: Done", 0.4, 0.9, 0.4)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF00FF00Left-Click|r: Search in Auction House", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("|cFF00FF00Right-Click|r: View Analytics & Tracking", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    if i % 2 == 0 then
                        self:SetBackdropColor(MarketSync.GetThemeColor("rowEven"))
                    else
                        self:SetBackdropColor(MarketSync.GetThemeColor("rowOdd"))
                    end
                    GameTooltip:Hide()
                end)

                row.delBtn:SetScript("OnClick", function()
                    local job = MarketSync.CraftLedger and MarketSync.CraftLedger.FindShoppingList(currentListName)
                    if job and MarketSync.PromptCraftPurchase then
                        MarketSync.PromptCraftPurchase(job.id, item.itemID)
                        return
                    end
                    if MarketSync.Favorites then
                        MarketSync.Favorites.RemoveFromList(currentListName, item.dbKey or item.itemID)
                        UpdateListsView()
                    end
                end)
                local tracked = MarketSync.CraftLedger and MarketSync.CraftLedger.FindShoppingList(currentListName)
                row.delBtn.text:SetText(tracked and "|cff00ff00+|r" or "|cffff4444x|r")

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
    sellFilterBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
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
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sellInset._marketSyncThemeRole = "inset"
    sellInset:SetBackdropColor(MarketSync.GetThemeColor("inset"))
    sellInset:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))

    local sellScroll = CreateFrame("ScrollFrame", "MarketSyncSidecarSellScroll", sellInset, "UIPanelScrollFrameTemplate")
    sellScroll:SetPoint("TOPLEFT", 2, -3)
    sellScroll:SetPoint("BOTTOMRIGHT", -14, 3)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(sellScroll) end

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
                        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 8,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 },
                    })
                    header:SetBackdropColor(MarketSync.GetThemeColor("header"))
                    header:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))

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
                            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                            edgeSize = 8,
                            insets = { left = 1, right = 1, top = 1, bottom = 1 },
                        })
                        btn:SetBackdropColor(MarketSync.GetThemeColor("inset", 0.8))
                        btn:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
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
                    btn:SetBackdropColor(MarketSync.GetThemeColor("inset"))
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
                            if MarketSyncDB and MarketSyncDB.EnableTooltipAuctionPrice == false then
                                GameTooltip:AddLine(string.format("Market Price: %s", priceStr), 1, 1, 1)
                            end
                            GameTooltip:AddLine(string.format("Suggested Match Price: %s", priceStr), 0.4, 1.0, 0.4)
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
                        if legacyAH and _G.AuctionFrameTab3 then
                            _G.AuctionFrameTab3:Click()
                        elseif AuctionHouseFrame and AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[2] then
                            AuctionHouseFrame.Tabs[2]:Click()
                        end

                        -- 2. Pick up item from container slot and place in sell frame
                        local pFunc = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
                        if pFunc then
                            pFunc(item.bag, item.slot)
                            if legacyAH and type(ClickAuctionSellItemButton) == "function" then
                                pcall(ClickAuctionSellItemButton)
                            elseif AuctionHouseFrame and AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.ItemDisplay then
                                pcall(AuctionHouseFrame.ItemSellFrame.ItemDisplay.Click, AuctionHouseFrame.ItemSellFrame.ItemDisplay)
                            elseif AuctionHouseFrame and AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay then
                                pcall(AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.Click, AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay)
                            elseif ClickAuctionSellItemButton then
                                pcall(ClickAuctionSellItemButton)
                            end
                            if ClearCursor then ClearCursor() end
                        end

                        -- 3. Set suggested match price (matches current lowest market price, no 1c undercut)
                        if not legacyAH and item.marketPrice and item.marketPrice > 0 then
                            local postPrice = item.marketPrice
                            if AuctionHouseFrame and AuctionHouseFrame.ItemSellFrame and AuctionHouseFrame.ItemSellFrame.PriceInput and AuctionHouseFrame.ItemSellFrame.PriceInput.SetAmount then
                                pcall(AuctionHouseFrame.ItemSellFrame.PriceInput.SetAmount, AuctionHouseFrame.ItemSellFrame.PriceInput, postPrice)
                            elseif AuctionHouseFrame and AuctionHouseFrame.CommoditiesSellFrame and AuctionHouseFrame.CommoditiesSellFrame.UnitPrice and AuctionHouseFrame.CommoditiesSellFrame.UnitPrice.SetAmount then
                                pcall(AuctionHouseFrame.CommoditiesSellFrame.UnitPrice.SetAmount, AuctionHouseFrame.CommoditiesSellFrame.UnitPrice, postPrice)
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
                                    priceDesc = string.format("Market price %s. ", pSpoken)
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
            -- Follow a list picked on the Scan page, or a deleted list.
            local shared = Fav and Fav.GetSelectedList and Fav.GetSelectedList()
            if shared and shared ~= currentListName then
                currentListName = shared
                dropdownBtn:SetText(currentListName .. "  |cFFFFD100v|r")
            end
            if frame:IsShown() and activeMode == "lists" and Sidecar.UpdateListsView then
                dropdownBtn:SetText(currentListName .. "  |cFFFFD100v|r")
                Sidecar.UpdateListsView()
            end
        end)
    end

    -- Refresh prices and the Scan button after scanner state changes.
    if MarketSync.Scanner then
        MarketSync.Scanner.RegisterCallback(function()
            if frame:IsShown() and activeMode == "lists" then
                UpdateListsView()
            end
        end)
    end

    -- Initial state: restore previous state or default to true
    local startExpanded = not legacyAH
    if MarketSyncDB and MarketSyncDB.AHSidecarExpanded ~= nil then
        startExpanded = MarketSyncDB.AHSidecarExpanded
    end
    Sidecar.SetExpanded(startExpanded)
    if not ahFrame:IsShown() then
        frame:Hide()
        toggleBtn:Hide()
    end

    return frame
end
