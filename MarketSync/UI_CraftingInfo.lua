-- =============================================================
-- MarketSync - Crafting Info & Multi-Tier Ground-Up UI
-- Profession Window Hooks & Interactive Materials Tree Drawer
-- =============================================================

MarketSync = MarketSync or {}

-- Another addon can anchor its panel through a label we previously moved.
-- Check every anchor and parent, including indirect dependencies, before
-- making its panel our own anchor target.
local function DependsOnRegion(region, target, visited)
    if type(region) == "string" then region = _G[region] end
    if not region then return false end
    if region == target then return true end
    visited = visited or {}
    if visited[region] then return false end
    visited[region] = true
    if region.GetParent and DependsOnRegion(region:GetParent(), target, visited) then return true end
    if region.GetPoint then
        local count = region.GetNumPoints and region:GetNumPoints() or 1
        for index = 1, count do
            local _, relative = region:GetPoint(index)
            if DependsOnRegion(relative, target, visited) then return true end
        end
    end
    return false
end
MarketSync.RefreshCraftingInfoUI = function() end

local function FormatMoney(copper)
    if not copper or copper == 0 then return "|cff8888880c|r" end
    if MarketSync.FormatMoneyColored then
        return MarketSync.FormatMoneyColored(copper)
    elseif MarketSync.FormatMoney then
        return MarketSync.FormatMoney(copper)
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local str = ""
    if g > 0 then str = str .. "|cffffd700" .. g .. "g|r " end
    if s > 0 or g > 0 then str = str .. "|cffc0c0c0" .. s .. "s|r " end
    str = str .. "|cffeda55f" .. c .. "c|r"
    return str
end

local function ApplyBackdrop(frame, bg, edge, edgeSize, insets)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = bg or "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = edge or "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = edgeSize or 14,
            insets = insets or { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(MarketSync.GetThemeColor("dialog"))
        frame:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
    end
end

local function BuildCurrentCraftRequest(frame)
    local recipe = frame.currentRecipe
    local id = recipe and tonumber(recipe.outputItemID)
    local request = {
        name = recipe and recipe.name or "Craft Mats",
        choices = frame.userOverrides,
        selectedBuys = frame.selectedBuys,
    }
    if id and id > 0 then
        request.itemIDs = { id }
        request.quantities = { [id] = frame.targetQuantity }
        request.recipes = { [id] = MarketSync.SnapshotCraftRecipe(recipe) }
    else
        request.recipe = recipe
        request.quantity = frame.targetQuantity
    end
    return request
end

-- ================================================================
-- INTERACTIVE MATERIALS BREAKDOWN DRAWER (Tree View)
-- ================================================================

local treeFrame = nil

local function CreateCraftingTreeFrame()
    if treeFrame then return treeFrame end

    local f = CreateFrame("Frame", "MarketSyncCraftingTreeFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 520)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(60)
    ApplyBackdrop(f)
    if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(f) end

    f.userOverrides = {}
    f.selectedBuys = {}
    f.expandedNodes = {}
    f.allExpanded = false
    f.targetQuantity = 1
    if MarketSync.Theme and MarketSync.Theme.DecorateWarcraftWindow then
        MarketSync.Theme.DecorateWarcraftWindow(f, "Interface\\Icons\\Trade_Engineering")
    end

    -- Header Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", 58, -14)
    title:SetText("|cffffd700MarketSync Materials & Crafting Choices|r")
    f.title = title

    -- Subtitle / Recipe info
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", 58, -36)
    subtitle:SetText("Recipe: Loading...")
    f.subtitle = subtitle

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Quantity Stepper
    local qtyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLabel:SetPoint("TOPRIGHT", -120, -36)
    qtyLabel:SetText("Craft Qty:")

    local btnMinus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnMinus:SetSize(20, 20); btnMinus:SetPoint("LEFT", qtyLabel, "RIGHT", 6, 0); btnMinus:SetText("-")
    btnMinus:SetScript("OnClick", function()
        if f.targetQuantity > 1 then
            f.targetQuantity = f.targetQuantity - 1
            f:RefreshTree()
        end
    end)

    local qtyValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qtyValue:SetPoint("LEFT", btnMinus, "RIGHT", 6, 0)
    qtyValue:SetText("1")
    f.qtyValue = qtyValue

    local btnPlus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnPlus:SetSize(20, 20); btnPlus:SetPoint("LEFT", qtyValue, "RIGHT", 6, 0); btnPlus:SetText("+")
    btnPlus:SetScript("OnClick", function()
        f.targetQuantity = f.targetQuantity + 1
        f:RefreshTree()
    end)

    -- Presets Bar
    local presetBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    presetBg:SetSize(488, 28)
    presetBg:SetPoint("TOPLEFT", 16, -60)
    ApplyBackdrop(presetBg, "Interface\\Buttons\\WHITE8X8", "Interface\\Buttons\\WHITE8X8", 1, { left = 1, right = 1, top = 1, bottom = 1 })
    presetBg:SetBackdropColor(MarketSync.GetThemeColor("header"))
    presetBg:SetBackdropBorderColor(MarketSync.GetThemeColor("headerBorder"))

    local treeHint = presetBg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    treeHint:SetPoint("TOPLEFT", presetBg, "BOTTOMLEFT", 2, -5)
    treeHint:SetText("Checked Buy = purchase; unchecked Buy = provide yourself. Craft expands ingredients.")

    local pLabel = presetBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pLabel:SetPoint("LEFT", 10, 0)
    pLabel:SetText("Strategy:")

    local btnOptimal = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnOptimal:SetSize(96, 20); btnOptimal:SetPoint("LEFT", pLabel, "RIGHT", 8, 0); btnOptimal:SetText("Optimal")
    btnOptimal:SetNormalFontObject("GameFontNormalSmall")
    btnOptimal:SetScript("OnClick", function()
        f.userOverrides = {}
        f:ExpandActiveNodes()
        f:RefreshTree()
    end)

    local btnBuyAll = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnBuyAll:SetSize(78, 20); btnBuyAll:SetPoint("LEFT", btnOptimal, "RIGHT", 6, 0); btnBuyAll:SetText("Buy Finished")
    btnBuyAll:SetNormalFontObject("GameFontNormalSmall")
    btnBuyAll:SetScript("OnClick", function()
        -- Force buy on all craftable nodes
        local function MarkBuy(nodes)
            for _, n in ipairs(nodes or {}) do
                if n.canCraft then
                    f.userOverrides[n.itemID] = false
                end
                if n.subMats then MarkBuy(n.subMats) end
            end
        end
        if f.lastCostData and f.lastCostData.reagentsTree then
            MarkBuy(f.lastCostData.reagentsTree)
        end
        f.expandedNodes = {}
        f:RefreshTree()
    end)

    local btnCraftAll = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnCraftAll:SetSize(84, 20); btnCraftAll:SetPoint("LEFT", btnBuyAll, "RIGHT", 6, 0); btnCraftAll:SetText("Craft All Raw")
    btnCraftAll:SetNormalFontObject("GameFontNormalSmall")
    btnCraftAll:SetScript("OnClick", function()
        -- Force craft on all craftable nodes
        local function MarkCraft(nodes)
            for _, n in ipairs(nodes or {}) do
                if n.canCraft then
                    f.userOverrides[n.itemID] = true
                    f.expandedNodes[n.itemID] = true
                end
                if n.subMats then MarkCraft(n.subMats) end
            end
        end
        if f.lastCostData and f.lastCostData.reagentsTree then
            MarkCraft(f.lastCostData.reagentsTree)
        end
        f:RefreshTree()
    end)

    local btnExpand = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnExpand:SetSize(92, 20); btnExpand:SetPoint("LEFT", btnCraftAll, "RIGHT", 6, 0); btnExpand:SetText("Expand Details")
    btnExpand:SetNormalFontObject("GameFontNormalSmall")
    btnExpand:SetScript("OnClick", function()
        f.allExpanded = not f.allExpanded
        local function SetExpanded(nodes)
            for _, node in ipairs(nodes or {}) do
                if node.subMats and #node.subMats > 0 then
                    f.expandedNodes[node.itemID] = f.allExpanded
                    SetExpanded(node.subMats)
                end
            end
        end
        if f.lastCostData then SetExpanded(f.lastCostData.reagentsTree) end
        btnExpand:SetText(f.allExpanded and "Collapse Details" or "Expand Details")
        f:RefreshTree()
    end)
    f.expandButton = btnExpand

    -- Scroll Frame for Reagent Tree
    local scrollFrame = CreateFrame("ScrollFrame", "MarketSyncCraftingTreeScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -108)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 110)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(468, 400)
    scrollFrame:SetScrollChild(scrollContent)
    f.scrollContent = scrollContent

    -- Summary Box at Bottom
    local summaryBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    summaryBox:SetSize(488, 58)
    summaryBox:SetPoint("BOTTOMLEFT", 16, 42)
    ApplyBackdrop(summaryBox, "Interface\\Buttons\\WHITE8X8", "Interface\\Buttons\\WHITE8X8", 1, { left = 1, right = 1, top = 1, bottom = 1 })
    summaryBox:SetBackdropColor(MarketSync.GetThemeColor("inset"))
    summaryBox:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))

    local sumDirect = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sumDirect:SetPoint("TOPLEFT", 12, -8)
    f.sumDirect = sumDirect

    local sumEffective = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sumEffective:SetPoint("TOPLEFT", 12, -24)
    f.sumEffective = sumEffective

    local sumSavings = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sumSavings:SetPoint("TOPLEFT", 12, -40)
    f.sumSavings = sumSavings

    local sumProfit = summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    sumProfit:SetPoint("TOPRIGHT", -12, -16)
    f.sumProfit = sumProfit

    -- Action Buttons (Bottom Bar)
    local btnExport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnExport:SetSize(195, 24); btnExport:SetPoint("BOTTOMLEFT", 16, 12); btnExport:SetText("Export checked to Shopping")
    btnExport:SetScript("OnClick", function()
        if f.currentRecipe then
            local rName = f.currentRecipe.name or "Craft Mats"
            local request = BuildCurrentCraftRequest(f)
            local success, countOrErr, name = MarketSync.ExportCraftPurchasesToShoppingList(request, "Craft " .. rName)
            if success then
                print(string.format("|cff00ff00[MarketSync]|r Exported %d material types to Shopping list: %s", countOrErr, name))
            else
                print("|cffff2020[MarketSync]|r Export failed: " .. tostring(countOrErr))
            end
        end
    end)

    local btnCraftList = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCraftList:SetSize(125, 24)
    btnCraftList:SetPoint("LEFT", btnExport, "RIGHT", 5, 0)
    btnCraftList:SetText("Save Craft... v")
    f.btnCraftList = btnCraftList
    local craftSaveMenu = CreateFrame("Frame", "MarketSyncCraftSaveMenu", f, "UIDropDownMenuTemplate")
    craftSaveMenu:Hide()
    local function SaveRequest(name)
        if not f.currentRecipe then return end
        local saved, reason = MarketSync.SaveCraftRequest(name, f.currentRecipe, {
            quantity = f.targetQuantity, choices = f.userOverrides, selectedBuys = f.selectedBuys,
        })
        if not saved then
            print("|cffff4444[MarketSync]|r " .. tostring(reason))
            return
        end
        f.craftListName = saved.name
        if MarketSync.AHSidecar and MarketSync.AHSidecar.UpdateCraftView then
            MarketSync.AHSidecar.UpdateCraftView()
        end
        print("|cff00ff00[MarketSync]|r Saved craft request to " .. saved.name)
    end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(craftSaveMenu, function(_, level)
            local names = { "Crafts" }
            local seen = { Crafts = true }
            for _, list in ipairs(MarketSync.ListProcessingCraftSets()) do
                if not seen[list.name] then names[#names + 1] = list.name; seen[list.name] = true end
            end
            for _, name in ipairs(names) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = name
                info.checked = name == f.craftListName
                info.func = function() SaveRequest(name) end
                UIDropDownMenu_AddButton(info, level)
            end
            local newInfo = UIDropDownMenu_CreateInfo()
            newInfo.text = "+ New Craft List..."
            newInfo.func = function()
                StaticPopupDialogs["MARKETSYNC_NEW_CRAFT_REQUEST_LIST"] = {
                    text = "Name this Craft List:", button1 = "Save", button2 = "Cancel",
                    hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
                    OnAccept = function(popup)
                        local box = popup.editBox or popup.EditBox
                            or (popup.GetName and _G[popup:GetName() .. "EditBox"])
                        local name = box and box:GetText()
                        if name and name:match("%S") then SaveRequest(name) end
                    end,
                }
                StaticPopup_Show("MARKETSYNC_NEW_CRAFT_REQUEST_LIST")
            end
            UIDropDownMenu_AddButton(newInfo, level)
        end)
    end
    btnCraftList:SetScript("OnClick", function()
        if ToggleDropDownMenu then
            ToggleDropDownMenu(1, nil, craftSaveMenu, btnCraftList, 0, 0)
        else
            SaveRequest(f.craftListName or "Crafts")
        end
    end)

    local btnClose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnClose:SetSize(80, 24); btnClose:SetPoint("BOTTOMRIGHT", -16, 12); btnClose:SetText("Close")
    btnClose:SetScript("OnClick", function() f:Hide() end)

    f.rowPool = {}

    -- Function to allocate or retrieve a row frame
    local function GetRow(index)
        local row = f.rowPool[index]
        if not row then
            row = CreateFrame("Frame", nil, scrollContent)
            row:SetSize(460, 26)

            local groupBG = row:CreateTexture(nil, "BACKGROUND")
            groupBG:SetAllPoints(row)
            groupBG:SetColorTexture(MarketSync.GetThemeColor("header"))
            groupBG:Hide()
            row.groupBG = groupBG

            local tierText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tierText:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.tierText = tierText

            local tierCheckText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            tierCheckText:SetPoint("RIGHT", row, "RIGHT", -32, 0)
            tierCheckText:SetWidth(115)
            tierCheckText:SetJustifyH("RIGHT")
            tierCheckText:SetText("Craft these items")
            row.tierCheckText = tierCheckText

            local tierCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            tierCheck:SetSize(20, 20)
            tierCheck:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.tierCheck = tierCheck

            local expand = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            expand:SetSize(16, 18)
            expand:SetNormalFontObject("GameFontNormalSmall")
            row.expand = expand

            -- Tree branch icon / bullet
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            row.icon = icon

            -- Interactive Craft Checkbox for craftables
            local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            check:SetSize(20, 20); check:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            row.check = check
            local buyCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            buyCheck:SetSize(18, 18)
            buyCheck:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            row.buyCheck = buyCheck

            -- Main Item Text (Quantity + Name)
            local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", check, "RIGHT", 4, 0)
            row.itemText = itemText

            -- Price & Comparison Details
            local detailText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            detailText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            detailText:SetWidth(150)
            detailText:SetJustifyH("RIGHT")
            row.detailText = detailText
            itemText:SetPoint("RIGHT", detailText, "LEFT", -6, 0)

            f.rowPool[index] = row
        end
        return row
    end

    function f:ExpandActiveNodes()
        if not self.currentRecipe then return end
        local cost = MarketSync.CalculateGroundUpCraftCost(self.currentRecipe,
            self.userOverrides, self.targetQuantity)
        local function Expand(nodes)
            for _, node in ipairs(nodes or {}) do
                if node.chooseCraft and node.subMats and #node.subMats > 0 then
                    self.expandedNodes[node.itemID] = true
                    Expand(node.subMats)
                end
            end
        end
        Expand(cost and cost.reagentsTree)
    end

    function f:RefreshTree()
        if not self.currentRecipe then return end

        local profitData = MarketSync.CalculateRecipeProfit(self.currentRecipe, self.userOverrides, self.targetQuantity)
        if not profitData or not profitData.costData then return end

        local cost = profitData.costData
        self.lastCostData = cost
        self.qtyValue:SetText(tostring(self.targetQuantity))

        self.expansionInitialized = true

        local rName = self.currentRecipe.name or "Recipe"
        self.subtitle:SetText(string.format("|cffffd700%s|r (Total Yield: %d)", rName, cost.outputQty))

        -- Summary Strings
        local outputItemID = tonumber(self.currentRecipe.outputItemID)
        if outputItemID and outputItemID > 0 then
            self.btnCraftList:Enable()
            self.btnCraftList:SetText("Save Craft... v")
        else
            self.btnCraftList:Disable()
            self.btnCraftList:SetText("No item output")
        end
        local plan = MarketSync.BuildCraftPurchasePlan(BuildCurrentCraftRequest(self))
        self.sumDirect:SetText("Net AH sale: " .. FormatMoney(profitData.netRevenue))
        self.sumEffective:SetText("Material value: " .. FormatMoney(cost.effectiveCost))
        self.sumSavings:SetText(string.format("Buy: %s (%d units)  |  Provide: %d units",
            FormatMoney(plan.estimatedBuyCost), plan.buyUnits, plan.providedUnits))

        if profitData.outputPrice > 0 and not cost.hasMissing then
            local pVal = profitData.effectiveProfit
            local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020-"
            local pStr = FormatMoney(math.abs(pVal))
            self.sumProfit:SetText(string.format("Value profit: %s%s|r  ROI %d%%", pCol, pStr, profitData.effectiveMarginPct))
        else
            self.sumProfit:SetText("|cff888888Profit: price missing|r")
        end

    -- Only the active acquisition branch contributes materials. A bought or
    -- self-provided parent stops the tree; its saved child preferences remain
    -- available if the player switches that parent back to Craft.
        local displayRows = {}
        local function AddGroup(nodes, depth, parentNode)
            if not nodes or #nodes == 0 then return end
            local craftableNodes = {}
            local allCraft = true
            for _, node in ipairs(nodes) do
                if node.canCraft then
                    craftableNodes[#craftableNodes + 1] = node
                    if not node.chooseCraft then allCraft = false end
                end
            end
            local groupName = depth == 0 and "Recipe reagents" or ("If you craft " .. tostring(parentNode.name))
            table.insert(displayRows, {
                kind = "group",
                depth = depth,
                title = string.format("Tier %d · %s", depth + 1, groupName),
                craftableNodes = craftableNodes,
                allCraft = #craftableNodes > 0 and allCraft,
            })
            for _, node in ipairs(nodes) do
                table.insert(displayRows, { kind = "item", node = node, depth = depth })
                if node.chooseCraft and node.subMats and #node.subMats > 0
                    and self.expandedNodes[node.itemID] then
                    AddGroup(node.subMats, depth + 1, node)
                end
            end
        end

        if cost.reagentsTree and #cost.reagentsTree > 0 then
            AddGroup(cost.reagentsTree, 0)
        else
            displayRows[1] = { kind = "empty", title = "No reagent breakdown is available for this recipe." }
        end

        -- Render rows
        for _, r in ipairs(self.rowPool) do r:Hide() end

        local curY = 0
        for i, rowData in ipairs(displayRows) do
            local row = GetRow(i)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 6, curY)
            row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -6, curY)

            row.tierText:Hide()
            row.tierCheckText:Hide()
            row.tierCheck:Hide()
            row.expand:Hide()
            row.icon:Hide()
            row.check:Hide()
            row.itemText:Hide()
            row.detailText:Hide()
            row.buyCheck:Hide()

            if rowData.kind == "group" then
                row:SetHeight(22)
                row.groupBG:Show()
                row.tierText:ClearAllPoints()
                row.tierText:SetPoint("LEFT", row, "LEFT", 10 + (rowData.depth * 12), 0)
                row.tierText:SetText("|cffffd75e" .. rowData.title .. "|r")
                row.tierText:Show()
                if #rowData.craftableNodes > 0 then
                    row.tierCheck:SetChecked(rowData.allCraft)
                    row.tierCheck:Show()
                    row.tierCheckText:Show()
                    row.tierCheck:SetScript("OnClick", function(check)
                        local shouldCraft = check:GetChecked() == true
                        for _, craftNode in ipairs(rowData.craftableNodes) do
                            self.userOverrides[craftNode.itemID] = shouldCraft
                            self.expandedNodes[craftNode.itemID] = shouldCraft
                        end
                        self:RefreshTree()
                    end)
                end
                row:Show()
                curY = curY - 22
            elseif rowData.kind == "empty" then
                row:SetHeight(28)
                row.groupBG:Hide()
                row.itemText:ClearAllPoints()
                row.itemText:SetPoint("LEFT", row, "LEFT", 12, 0)
                row.itemText:SetText("|cffaaaaaa" .. rowData.title .. "|r")
                row.itemText:Show()
                row:Show()
                curY = curY - 28
            else
            local node = rowData.node
            local depth = rowData.depth
            row:SetHeight(26)
            row.groupBG:Hide()

            local indentX = depth * 16
            if node.chooseCraft and node.subMats and #node.subMats > 0 then
                row.expand:ClearAllPoints()
                row.expand:SetPoint("LEFT", row, "LEFT", indentX, 0)
                row.expand:SetText(self.expandedNodes[node.itemID] and "-" or "+")
                row.expand:Show()
                row.expand:SetScript("OnClick", function()
                    self.expandedNodes[node.itemID] = not self.expandedNodes[node.itemID]
                    self:RefreshTree()
                end)
            end
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", indentX + 18, 0)
            row.icon:Show()

            -- Item texture
            local itemTexture = MarketSync.GetItemIcon and MarketSync.GetItemIcon(node.itemID)
            if not itemTexture and MarketSync.GetItemInfo then
                itemTexture = select(10, MarketSync.GetItemInfo(node.itemID))
            end
            row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Item Text
            local nameColor = node.chooseCraft and "|cff00ffff" or "|cffffffff"
            local sourceTag = node.chooseCraft and "|cff00ffff[CRAFT]|r "
                or (self.selectedBuys[node.itemID] == false and "|cffaaaaff[PROVIDE]|r "
                or (node.isVendor and "|cff00ffcc[BUY VENDOR]|r " or "|cffffd75e[BUY AH]|r "))
            row.itemText:SetText(string.format("%s%s%s x%d|r", sourceTag, nameColor, node.name, node.qty))

            -- Checkbox logic for craftable intermediate
            if node.canCraft then
                row.check:Show()
                row.check:ClearAllPoints()
                row.check:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.itemText:ClearAllPoints()
                row.itemText:SetPoint("LEFT", row.check, "RIGHT", 4, 0)

                row.check:SetChecked(node.chooseCraft == true)
                row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.check:SetScript("OnClick", function(chk)
                    local shouldCraft = chk:GetChecked() == true
                    f.userOverrides[node.itemID] = shouldCraft
                    f.expandedNodes[node.itemID] = shouldCraft
                    f:RefreshTree()
                end)
                if not node.chooseCraft then
                    row.buyCheck:SetChecked(self.selectedBuys[node.itemID] ~= false)
                    row.buyCheck:Show()
                end

                -- Show the selected method and make the cheaper alternative explicit.
                local buyStr = FormatMoney(node.directTotalPrice)
                local craftStr = FormatMoney(node.craftTotalPrice or 0)
                local craftDelta = (node.directTotalPrice or 0) - (node.craftTotalPrice or 0)
                local choice = node.chooseCraft and ("Craft " .. craftStr) or ("Buy " .. buyStr)
                if craftDelta > 0 then
                    row.detailText:SetText(choice .. " |cff888888· Craft cheaper by " .. FormatMoney(craftDelta) .. "|r")
                elseif craftDelta < 0 then
                    row.detailText:SetText(choice .. " |cff888888· Buy cheaper by " .. FormatMoney(-craftDelta) .. "|r")
                else
                    row.detailText:SetText(choice .. " |cff888888· Same cost|r")
                end

                row.check:SetScript("OnEnter", function(check)
                    GameTooltip:SetOwner(check, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Choose how to get " .. tostring(node.name), 1, 1, 1)
                    GameTooltip:AddLine("Buy finished item: " .. buyStr, 0.9, 0.9, 0.9, true)
                    GameTooltip:AddLine("Craft from ingredients: " .. craftStr, 0.9, 0.9, 0.9, true)
                    if craftDelta > 0 then
                        GameTooltip:AddLine("Crafting is cheaper by " .. FormatMoney(craftDelta), 0.2, 1, 0.2, true)
                    elseif craftDelta < 0 then
                        GameTooltip:AddLine("Buying is cheaper by " .. FormatMoney(-craftDelta), 0.2, 1, 0.2, true)
                    else
                        GameTooltip:AddLine("Both choices cost the same.", 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:AddLine("Checked: craft and show inputs. Unchecked: use this item directly; child inputs leave the active plan.", 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
            else
                row.check:Show()
                row.check:SetChecked(self.selectedBuys[node.itemID] ~= false)
                row.check:SetScript("OnEnter", function(check)
                    GameTooltip:SetOwner(check, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Buy checked; provide yourself when unchecked")
                    GameTooltip:Show()
                end)
                row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.check:SetScript("OnClick", function(chk)
                    self.selectedBuys[node.itemID] = chk:GetChecked() == true
                    self:RefreshTree()
                end)

                -- Raw material detail
                if node.directUnitPrice and node.directUnitPrice > 0 then
                    local costStr = FormatMoney(node.effectiveTotalPrice)
                    local unitStr = FormatMoney(node.effectiveUnitPrice)
                    row.detailText:SetText(string.format("%s |cff888888(%s ea)|r", costStr, unitStr))
                else
                    row.detailText:SetText("|cffffaa00Price unavailable|r")
                end
            end

            row.buyCheck:SetScript("OnClick", function(chk)
                self.selectedBuys[node.itemID] = chk:GetChecked() == true
                self:RefreshTree()
            end)

            row.detailText:Show()
            row.detailText:ClearAllPoints()
            row.detailText:SetPoint("RIGHT", row, "RIGHT", row.buyCheck:IsShown() and -25 or -8, 0)
            row.itemText:Show()
            row:Show()
            curY = curY - 26
            end
        end

        scrollContent:SetHeight(math.max(300, math.abs(curY) + 20))
    end

    treeFrame = f
    return f
end

function MarketSync.OpenCraftingTree(recipeOrOutputItemID, anchorFrame, savedCraftSet)
    local f = CreateCraftingTreeFrame()
    local itemID = type(recipeOrOutputItemID) == "table" and tonumber(recipeOrOutputItemID.outputItemID)
        or tonumber(recipeOrOutputItemID)
    local function Clone(source)
        local result = {}
        for key, value in pairs(source or {}) do result[key] = value end
        return result
    end
    f.targetQuantity = savedCraftSet and (tonumber((savedCraftSet.quantities or {})[itemID]) or 1) or 1
    f.userOverrides = Clone(savedCraftSet and savedCraftSet.choices)
    f.selectedBuys = Clone(savedCraftSet and savedCraftSet.selectedBuys)
    f.craftListName = savedCraftSet and savedCraftSet.name
        or (MarketSync.AHSidecar and MarketSync.AHSidecar.GetActiveCraftListName
            and MarketSync.AHSidecar.GetActiveCraftListName()) or "Crafts"
    f.expandedNodes = {}
    f.allExpanded = false
    f.expansionInitialized = false
    if f.expandButton then f.expandButton:SetText("Expand Details") end

    local recipe = nil
    if type(recipeOrOutputItemID) == "table" and recipeOrOutputItemID.mats then
        recipe = recipeOrOutputItemID
    elseif tonumber(recipeOrOutputItemID) then
        recipe = MarketSync.GetRecipeForOutput(recipeOrOutputItemID)
    end

    if not recipe then
        print("|cffff2020[MarketSync]|r No recipe found for item " .. tostring(recipeOrOutputItemID))
        return
    end

    f.currentRecipe = recipe
    f:ExpandActiveNodes()

    if anchorFrame and anchorFrame:IsShown() then
        f:ClearAllPoints()
        -- Anchor neatly to the right of the profession / item frame
        f:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 10, 0)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    end

    f:Show()
    f:RefreshTree()
end

-- ================================================================
-- BLIZZARD PROFESSION WINDOW HOOKS (Classic TradeSkillFrame)
-- ================================================================

local function ItemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Resolve against the open profession, rather than cached indices from another
-- character or a previous filter state.
function MarketSync.JumpToProfessionItem(itemID)
    if not itemID or (InCombatLockdown and InCombatLockdown()) then return false end
    if TradeSkillFrame and TradeSkillFrame:IsShown() and GetNumTradeSkills then
        -- Expand headers first: collapsed categories hide recipe indices.
        if ExpandTradeSkillSubClass then
            for i = GetNumTradeSkills(), 1, -1 do
                local _, kind, _, expanded = GetTradeSkillInfo(i)
                if kind == "header" and not expanded then ExpandTradeSkillSubClass(i) end
            end
        end
        for i = 1, GetNumTradeSkills() do
            if ItemIDFromLink(GetTradeSkillItemLink(i)) == itemID then
                if TradeSkillFrame_SetSelection then TradeSkillFrame_SetSelection(i)
                elseif SelectTradeSkill then SelectTradeSkill(i) end
                if TradeSkillFrame_Update then TradeSkillFrame_Update() end
                return true
            end
        end
    elseif CraftFrame and CraftFrame:IsShown() and GetNumCrafts and GetCraftItemLink then
        if ExpandCraftSkillLine then
            for i = GetNumCrafts(), 1, -1 do
                local _, _, kind, _, expanded = GetCraftInfo(i)
                if kind == "header" and not expanded then ExpandCraftSkillLine(i) end
            end
        end
        for i = 1, GetNumCrafts() do
            if ItemIDFromLink(GetCraftItemLink(i)) == itemID then
                if CraftFrame_SetSelection then CraftFrame_SetSelection(i)
                elseif SelectCraft then SelectCraft(i) end
                if CraftFrame_Update then CraftFrame_Update() end
                return true
            end
        end
    elseif ProfessionsFrame and ProfessionsFrame:IsShown() and C_TradeSkillUI
        and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeItemLink then
        for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
            if info and info.learned and ItemIDFromLink(C_TradeSkillUI.GetRecipeItemLink(recipeID)) == itemID
                and ProfessionsFrame.SelectRecipe then
                ProfessionsFrame:SelectRecipe(recipeID)
                return true
            end
        end
    end
    return false
end

local function HookProfessionItemButton(button, getItemID)
    if not button or button.marketSyncRecipeJump or not button.HookScript then return end
    button.marketSyncRecipeJump = true
    -- OnMouseUp observes right clicks without replacing native left-click or
    -- reagent-quality selection handlers and their click registrations.
    button:HookScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" then MarketSync.JumpToProfessionItem(getItemID(self)) end
    end)
end

local function InitClassicCraftItemHooks()
    if not CraftFrame then return end
    HookProfessionItemButton(CraftIcon, function()
        return GetCraftItemLink and ItemIDFromLink(GetCraftItemLink(GetCraftSelectionIndex()))
    end)
    for r = 1, (MAX_CRAFT_REAGENTS or 8) do
        local reagentIndex = r
        HookProfessionItemButton(_G["CraftReagent" .. r], function()
            return GetCraftReagentItemLink
                and ItemIDFromLink(GetCraftReagentItemLink(GetCraftSelectionIndex(), reagentIndex))
        end)
    end
end

local function InitClassicTradeSkillHook()
    if not TradeSkillFrame then return end
    if MarketSync.TradeSkillHookInitialized then return end
    MarketSync.TradeSkillHookInitialized = true

    local infoFrame = CreateFrame("Frame", "MarketSyncCraftingInfo", TradeSkillFrame)
    infoFrame:SetSize(240, 52)
    -- Keep native profession controls above this informational overlay so
    -- MarketSync never visually masks reagent/action options.
    infoFrame:SetFrameLevel(TradeSkillFrame:GetFrameLevel() + 5)
    infoFrame:EnableMouse(true)

    -- Session recovery: ensure native Blizzard labels are not stuck to infoFrame from any prior session state
    if TradeSkillDescription and TradeSkillDescription.GetPoint then
        local pCount = TradeSkillDescription.GetNumPoints and TradeSkillDescription:GetNumPoints() or 1
        for pi = 1, pCount do
            local _, relTo = TradeSkillDescription:GetPoint(pi)
            if relTo == infoFrame or relTo == "MarketSyncCraftingInfo" then
                TradeSkillDescription:ClearAllPoints()
                if TradeSkillSkillIcon then
                    TradeSkillDescription:SetPoint("TOPLEFT", TradeSkillSkillIcon, "BOTTOMLEFT", 0, -10)
                end
                break
            end
        end
    end
    if TradeSkillReagentLabel and TradeSkillReagentLabel.GetPoint then
        local pCount = TradeSkillReagentLabel.GetNumPoints and TradeSkillReagentLabel:GetNumPoints() or 1
        for pi = 1, pCount do
            local _, relTo = TradeSkillReagentLabel:GetPoint(pi)
            if relTo == infoFrame or relTo == "MarketSyncCraftingInfo" then
                TradeSkillReagentLabel:ClearAllPoints()
                if TradeSkillSkillName then
                    TradeSkillReagentLabel:SetPoint("TOPLEFT", TradeSkillSkillName, "BOTTOMLEFT", 0, -10)
                end
                break
            end
        end
    end

    -- Labels
    infoFrame.costLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.costLabel:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
    infoFrame.costLabel:SetWidth(132)
    infoFrame.costLabel:SetJustifyH("LEFT")

    infoFrame.groundUpLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.groundUpLabel:SetPoint("TOPLEFT", infoFrame.costLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.groundUpLabel:SetJustifyH("LEFT")

    infoFrame.profitLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.profitLabel:SetPoint("TOPLEFT", infoFrame.groundUpLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.profitLabel:SetJustifyH("LEFT")

    infoFrame.warningLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    infoFrame.warningLabel:SetPoint("TOPLEFT", infoFrame.profitLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.warningLabel:SetJustifyH("LEFT")

    -- Breakdown toggle button
    local btnBreakdown = CreateFrame("Button", nil, infoFrame, "UIPanelButtonTemplate")
    btnBreakdown:SetSize(96, 18)
    btnBreakdown:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", 0, 0)
    btnBreakdown:SetText("Breakdown ▼")
    btnBreakdown:SetNormalFontObject("GameFontNormalSmall")
    btnBreakdown:SetHighlightFontObject("GameFontHighlightSmall")
    btnBreakdown:SetScript("OnClick", function()
        if treeFrame and treeFrame:IsShown() then
            treeFrame:Hide()
        else
            MarketSync.OpenCraftingTree(infoFrame.currentRecipe, TradeSkillFrame)
        end
    end)
    infoFrame.btnBreakdown = btnBreakdown

    local btnCraftList = CreateFrame("Button", nil, infoFrame, "UIPanelButtonTemplate")
    btnCraftList:SetSize(96, 18)
    btnCraftList:SetPoint("TOPRIGHT", btnBreakdown, "BOTTOMRIGHT", 0, -2)
    btnCraftList:SetText("+ Craft List")
    btnCraftList:SetNormalFontObject("GameFontNormalSmall")
    btnCraftList:SetScript("OnClick", function()
        local recipe = infoFrame.currentRecipe
        if recipe and MarketSync.OpenCraftListForRecipe then
            MarketSync.OpenCraftListForRecipe(recipe)
        end
    end)
    infoFrame.btnCraftList = btnCraftList

    local function UpdateCraftingInfo()
        if not MarketSyncDB or MarketSyncDB.EnableProfessionCraftInfo == false then
            infoFrame:Hide()
            return
        end

        local recipeIndex = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()
        if not recipeIndex or recipeIndex == 0 then
            infoFrame:Hide()
            return
        end

        local numReagents = (GetTradeSkillNumReagents and GetTradeSkillNumReagents(recipeIndex)) or 0
        HookProfessionItemButton(TradeSkillSkillIcon, function()
            return ItemIDFromLink(GetTradeSkillItemLink(GetTradeSkillSelectionIndex()))
        end)
        for r = 1, numReagents do
            local reagentIndex = r
            HookProfessionItemButton(_G["TradeSkillReagent" .. r], function()
                return ItemIDFromLink(GetTradeSkillReagentItemLink(GetTradeSkillSelectionIndex(), reagentIndex))
            end)
        end
        if numReagents == 0 then
            infoFrame:Hide()
            return
        end

        local recipeLink = GetTradeSkillItemLink and GetTradeSkillItemLink(recipeIndex)
        local outputItemID = nil
        if recipeLink then
            outputItemID = tonumber(recipeLink:match("item:(%d+)"))
        end

        local mats = {}
        for r = 1, numReagents do
            local rLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(recipeIndex, r)
            local rID = rLink and tonumber(rLink:match("item:(%d+)"))
            local count = 1
            if GetTradeSkillReagentInfo then
                _, _, count = GetTradeSkillReagentInfo(recipeIndex, r)
            end
            if rID then
                table.insert(mats, { itemID = rID, qty = tonumber(count) or 1 })
            end
        end

        local recipeName = GetTradeSkillInfo and GetTradeSkillInfo(recipeIndex)
        local numMade = (GetTradeSkillNumMade and select(1, GetTradeSkillNumMade(recipeIndex))) or 1

        local recipe = {
            name = recipeName,
            outputItemID = outputItemID,
            outputQty = numMade,
            mats = mats,
            recipeIndex = recipeIndex,
        }
        infoFrame.currentRecipe = recipe
        if outputItemID and outputItemID > 0 then
            btnCraftList:Enable()
        else
            btnCraftList:Disable()
        end

        local profitData = MarketSync.CalculateRecipeProfit(recipe)
        if not profitData or not profitData.costData then
            infoFrame:Hide()
            return
        end

        local cost = profitData.costData

        -- Direct Cost Line
        local directStr = FormatMoney(cost.directCraftCost)
        local groundUpStr = FormatMoney(cost.groundUpCost)

        -- Determine layout type:
        -- Single-column classic (Era/Vanilla/Anniversary): frame width <= 500 with detail pane below recipe list.
        -- Two-column classic (WoW Forever / WotLK / Cata): frame width > 500 with detail pane in right column.
        local detailScroll = TradeSkillDetailScrollFrame
        local frameWidth = TradeSkillFrame.GetWidth and TradeSkillFrame:GetWidth() or 0
        local isOneColumn = (frameWidth > 0 and frameWidth <= 500) and (detailScroll ~= nil)

        infoFrame:ClearAllPoints()

        if isOneColumn then
            -- Single-column classic layout (Era/Vanilla/Anniversary)
            -- Position in the empty upper-right area of TradeSkillDetailScrollFrame next to TradeSkillSkillName.
            -- This preserves all native reagents, NEVER shifts TradeSkillDescription or TradeSkillReagentLabel,
            -- and completely prevents anchor cycles with Auctionator or other addons.
            if infoFrame.SetParent then infoFrame:SetParent(TradeSkillFrame) end
            if detailScroll and detailScroll.GetFrameLevel and infoFrame.SetFrameLevel then
                infoFrame:SetFrameLevel(detailScroll:GetFrameLevel() + 5)
            end
            infoFrame:SetPoint("TOPRIGHT", detailScroll, "TOPRIGHT", -24, -2)
            infoFrame:SetSize(136, 46)

            -- Buttons: compact top row
            btnBreakdown:ClearAllPoints()
            btnBreakdown:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
            btnBreakdown:SetSize(66, 18)
            btnBreakdown:SetText("Breakdown")
            btnBreakdown:Show()

            btnCraftList:ClearAllPoints()
            btnCraftList:SetPoint("LEFT", btnBreakdown, "RIGHT", 4, 0)
            btnCraftList:SetSize(66, 18)
            btnCraftList:SetText("+ Craft List")
            btnCraftList:Show()

            -- Labels: direct cost and profit margin
            infoFrame.costLabel:ClearAllPoints()
            infoFrame.costLabel:SetPoint("TOPLEFT", btnBreakdown, "BOTTOMLEFT", 0, -3)
            infoFrame.costLabel:SetWidth(136)
            infoFrame.costLabel:SetText("Cost: " .. directStr)
            infoFrame.costLabel:Show()

            infoFrame.groundUpLabel:Hide() -- Available in rich tooltip on hover

            infoFrame.profitLabel:ClearAllPoints()
            infoFrame.profitLabel:SetPoint("TOPLEFT", infoFrame.costLabel, "BOTTOMLEFT", 0, -1)
            infoFrame.profitLabel:SetWidth(136)
            if profitData.outputPrice > 0 then
                local pVal = profitData.groundUpProfit
                local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
                local pStr = FormatMoney(math.abs(pVal))
                local mCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
                infoFrame.profitLabel:SetText(string.format("Profit: %s%s|r (%s%d%%|r)", pCol, pStr, mCol, profitData.groundUpMarginPct))
            else
                infoFrame.profitLabel:SetText("|cff888888Profit: No AH price|r")
            end
            infoFrame.profitLabel:Show()

            if profitData.hasWarnings and #profitData.warnings > 0 then
                infoFrame.warningLabel:ClearAllPoints()
                infoFrame.warningLabel:SetPoint("TOPLEFT", infoFrame.profitLabel, "BOTTOMLEFT", 0, -1)
                infoFrame.warningLabel:SetWidth(136)
                infoFrame.warningLabel:SetText("|cffff9900! Price warnings|r")
                infoFrame.warningLabel:Show()
            else
                infoFrame.warningLabel:Hide()
            end
        else
            -- Two-column classic layout (WoW Forever / WotLK / Cata)
            -- Detail pane is on the right column with plenty of width.
            if infoFrame.SetParent then infoFrame:SetParent(TradeSkillFrame) end
            if infoFrame.SetFrameLevel and TradeSkillFrame.GetFrameLevel then
                infoFrame:SetFrameLevel(TradeSkillFrame:GetFrameLevel() + 5)
            end
            local width = 240
            infoFrame:SetWidth(width)

            infoFrame.costLabel:ClearAllPoints()
            infoFrame.costLabel:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
            infoFrame.costLabel:SetWidth(width)
            infoFrame.costLabel:SetText("To Craft: " .. directStr)
            infoFrame.costLabel:Show()

            infoFrame.groundUpLabel:ClearAllPoints()
            infoFrame.groundUpLabel:SetPoint("TOPLEFT", infoFrame.costLabel, "BOTTOMLEFT", 0, -2)
            infoFrame.groundUpLabel:SetWidth(width)
            if cost.optimalSavings > 0 then
                local saveStr = FormatMoney(cost.optimalSavings)
                infoFrame.groundUpLabel:SetText(string.format("Ground-Up: %s |cff00ff00(-%s / %d%%)|r", groundUpStr, saveStr, cost.optimalSavingsPct))
            else
                infoFrame.groundUpLabel:SetText("Ground-Up: " .. groundUpStr)
            end
            infoFrame.groundUpLabel:Show()

            infoFrame.profitLabel:ClearAllPoints()
            infoFrame.profitLabel:SetPoint("TOPLEFT", infoFrame.groundUpLabel, "BOTTOMLEFT", 0, -2)
            infoFrame.profitLabel:SetWidth(width)
            if profitData.outputPrice > 0 then
                local pVal = profitData.groundUpProfit
                local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
                local pStr = FormatMoney(math.abs(pVal))
                local mCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
                local directComp = ""
                if cost.optimalSavings > 0 then
                    local dVal = profitData.directProfit
                    local dStr = FormatMoney(math.abs(dVal))
                    local dCol = (dVal >= 0) and "+ " or "- "
                    directComp = string.format(" |cff888888(Direct: %s%s)|r", dCol, dStr)
                end
                infoFrame.profitLabel:SetText(string.format("Profit: %s%s|r (%s%d%%|r)%s", pCol, pStr, mCol, profitData.groundUpMarginPct, directComp))
                infoFrame.profitLabel:Show()
            else
                infoFrame.profitLabel:SetText(outputItemID and
                    "|cff888888Profit: No AH price for output item|r" or
                    "|cff888888Profit: No item output|r")
                infoFrame.profitLabel:Show()
            end

            if profitData.hasWarnings and #profitData.warnings > 0 then
                infoFrame.warningLabel:ClearAllPoints()
                infoFrame.warningLabel:SetPoint("TOPLEFT", infoFrame.profitLabel, "BOTTOMLEFT", 0, -2)
                infoFrame.warningLabel:SetWidth(width)
                infoFrame.warningLabel:SetText("|cffff9900Warning: " .. table.concat(profitData.warnings, ", ") .. "|r")
                infoFrame.warningLabel:Show()
            else
                infoFrame.warningLabel:Hide()
            end

            local textHeight = 0
            for _, label in ipairs({ infoFrame.costLabel, infoFrame.groundUpLabel,
                infoFrame.profitLabel, infoFrame.warningLabel }) do
                if label:IsShown() then
                    textHeight = textHeight + (label.GetStringHeight and label:GetStringHeight() or 12) + 2
                end
            end

            btnBreakdown:ClearAllPoints()
            btnBreakdown:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, -textHeight - 4)
            btnBreakdown:SetSize(96, 18)
            btnBreakdown:SetText("Breakdown ▼")
            btnBreakdown:Show()

            btnCraftList:ClearAllPoints()
            btnCraftList:SetPoint("LEFT", btnBreakdown, "RIGHT", 4, 0)
            btnCraftList:SetSize(96, 18)
            btnCraftList:SetText("+ Craft List")
            btnCraftList:Show()

            infoFrame:SetSize(width, textHeight + 26)

            -- Anchor cleanly inside the right column without touching native Blizzard labels
            if AuctionatorCraftingInfo and AuctionatorCraftingInfo:IsShown()
                and not DependsOnRegion(AuctionatorCraftingInfo, infoFrame) then
                infoFrame:SetPoint("TOPLEFT", AuctionatorCraftingInfo, "BOTTOMLEFT", 0, -4)
            elseif detailScroll then
                infoFrame:SetPoint("TOPLEFT", detailScroll, "TOPLEFT", 0, 0)
            else
                infoFrame:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 210, -120)
            end
        end

        -- Rich hover details for info frame
        infoFrame:SetScript("OnEnter", function(self)
            if not self.currentRecipe then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.currentRecipe.name or "Craft Information", 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Direct Craft Cost:", directStr, 0.9, 0.9, 0.9, 1, 1, 1)
            if cost.optimalSavings > 0 then
                local saveStr = FormatMoney(cost.optimalSavings)
                GameTooltip:AddDoubleLine("Ground-Up Optimal:", string.format("%s (-%s / %d%%)", groundUpStr, saveStr, cost.optimalSavingsPct), 0.9, 0.9, 0.9, 0.2, 1, 0.2)
            else
                GameTooltip:AddDoubleLine("Ground-Up Cost:", groundUpStr, 0.9, 0.9, 0.9, 1, 1, 1)
            end
            if profitData.outputPrice > 0 then
                GameTooltip:AddDoubleLine("AH Market Price:", FormatMoney(profitData.outputPrice), 0.9, 0.9, 0.9, 1, 1, 1)
                local pVal = profitData.groundUpProfit
                local pCol = (pVal >= 0) and "+ " or "- "
                GameTooltip:AddDoubleLine("Estimated Profit:", string.format("%s%s (%d%%)", pCol, FormatMoney(math.abs(pVal)), profitData.groundUpMarginPct), 0.9, 0.9, 0.9, pVal >= 0 and 0.2 or 1, pVal >= 0 and 1 or 0.2, 0.2)
            else
                GameTooltip:AddDoubleLine("AH Market Price:", "No data", 0.9, 0.9, 0.9, 0.6, 0.6, 0.6)
            end
            if profitData.hasWarnings and #profitData.warnings > 0 then
                GameTooltip:AddLine(" ")
                for _, w in ipairs(profitData.warnings) do
                    GameTooltip:AddLine("Warning: " .. w, 1, 0.6, 0.2, true)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click Breakdown for interactive materials tree.", 0.6, 0.8, 1, true)
            GameTooltip:AddLine("Click + Craft List to add to your shopping list.", 0.6, 0.8, 1, true)
            GameTooltip:Show()
        end)
        infoFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        infoFrame:Show()
    end

    hooksecurefunc("TradeSkillFrame_SetSelection", function()
        UpdateCraftingInfo()
    end)

    infoFrame:SetScript("OnShow", function()
        UpdateCraftingInfo()
    end)
    infoFrame:SetScript("OnHide", function()
        if treeFrame then treeFrame:Hide() end
    end)

    local prevRefresh = MarketSync.RefreshCraftingInfoUI
    MarketSync.RefreshCraftingInfoUI = function()
        if prevRefresh then prevRefresh() end
        if TradeSkillFrame and TradeSkillFrame:IsShown() then
            UpdateCraftingInfo()
        end
    end
end

-- ================================================================
-- BLIZZARD MODERN PROFESSIONS HOOK (Dragonflight / TWW)
-- ================================================================

local function InitModernProfessionsHook()
    if not ProfessionsFrame or not ProfessionsFrame.CraftingPage or not ProfessionsFrame.CraftingPage.SchematicForm then
        return
    end
    if MarketSync.ProfessionsHookInitialized then return end
    MarketSync.ProfessionsHookInitialized = true

    local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm
    local infoFrame = CreateFrame("Frame", "MarketSyncCraftingInfoProfessionsFrame", schematicForm)
    infoFrame:SetSize(300, 54)
    -- The default +1 child layer leaves native reagent selectors in front.
    infoFrame:SetFrameLevel(schematicForm:GetFrameLevel() + 1)
    infoFrame:EnableMouse(false)

    infoFrame.costLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.costLabel:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
    infoFrame.costLabel:SetWidth(192)
    infoFrame.costLabel:SetJustifyH("LEFT")

    infoFrame.groundUpLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.groundUpLabel:SetPoint("TOPLEFT", infoFrame.costLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.groundUpLabel:SetJustifyH("LEFT")

    infoFrame.profitLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.profitLabel:SetPoint("TOPLEFT", infoFrame.groundUpLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.profitLabel:SetJustifyH("LEFT")

    local btnBreakdown = CreateFrame("Button", nil, infoFrame, "UIPanelButtonTemplate")
    btnBreakdown:SetSize(96, 18)
    btnBreakdown:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", 0, 0)
    btnBreakdown:SetText("Breakdown ▼")
    btnBreakdown:SetNormalFontObject("GameFontNormalSmall")
    btnBreakdown:SetHighlightFontObject("GameFontHighlightSmall")
    btnBreakdown:SetScript("OnClick", function()
        if treeFrame and treeFrame:IsShown() then
            treeFrame:Hide()
        else
            MarketSync.OpenCraftingTree(infoFrame.currentRecipe, ProfessionsFrame)
        end
    end)
    infoFrame.btnBreakdown = btnBreakdown

    local btnCraftList = CreateFrame("Button", nil, infoFrame, "UIPanelButtonTemplate")
    btnCraftList:SetSize(96, 18)
    btnCraftList:SetPoint("TOPRIGHT", btnBreakdown, "BOTTOMRIGHT", 0, -2)
    btnCraftList:SetText("+ Craft List")
    btnCraftList:SetNormalFontObject("GameFontNormalSmall")
    btnCraftList:SetScript("OnClick", function()
        local recipe = infoFrame.currentRecipe
        if recipe and MarketSync.OpenCraftListForRecipe then
            MarketSync.OpenCraftListForRecipe(recipe)
        end
    end)
    infoFrame.btnCraftList = btnCraftList

    local function UpdateModernCraftingInfo()
        for _, slots in pairs(schematicForm.reagentSlots or {}) do
            for _, slot in ipairs(slots) do
                HookProfessionItemButton(slot.Button, function(button)
                    local reagent = button.GetReagent and button:GetReagent()
                    return reagent and reagent.itemID
                end)
            end
        end
        HookProfessionItemButton(schematicForm.OutputIcon, function()
            local info = schematicForm.GetRecipeInfo and schematicForm:GetRecipeInfo()
            return info and C_TradeSkillUI.GetRecipeItemLink
                and ItemIDFromLink(C_TradeSkillUI.GetRecipeItemLink(info.recipeID))
        end)
        if not MarketSyncDB or MarketSyncDB.EnableProfessionCraftInfo == false then
            infoFrame:Hide()
            return
        end

        local recipeInfo = schematicForm.GetRecipeInfo and schematicForm:GetRecipeInfo()
        if not recipeInfo or not recipeInfo.recipeID then
            infoFrame:Hide()
            return
        end

        local recipeID = recipeInfo.recipeID
        local schematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
            and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        if not schematic or not schematic.reagentSlotSchematics or #schematic.reagentSlotSchematics == 0 then
            infoFrame:Hide()
            return
        end

        local mats = {}
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local reqQty = tonumber(slot.quantityRequired) or 1
            if type(slot.reagents) == "table" and #slot.reagents > 0 then
                local firstReagent = slot.reagents[1]
                local rItemID = firstReagent and tonumber(firstReagent.itemID)
                if rItemID then
                    table.insert(mats, { itemID = rItemID, qty = reqQty })
                end
            end
        end

        local outputItemID = tonumber(schematic.outputItemID) or tonumber(recipeInfo.productID)
        local numMade = tonumber(schematic.quantityMin) or 1

        local recipe = {
            name = recipeInfo.name,
            outputItemID = outputItemID,
            outputQty = numMade,
            mats = mats,
            recipeIndex = recipeID,
        }
        infoFrame.currentRecipe = recipe
        if outputItemID and outputItemID > 0 then
            btnCraftList:Enable()
        else
            btnCraftList:Disable()
        end

        local profitData = MarketSync.CalculateRecipeProfit(recipe)
        if not profitData or not profitData.costData then
            infoFrame:Hide()
            return
        end

        local cost = profitData.costData

        infoFrame.costLabel:SetText("To Craft: " .. FormatMoney(cost.directCraftCost))

        local groundUpStr = FormatMoney(cost.groundUpCost)
        if cost.optimalSavings > 0 then
            local saveStr = FormatMoney(cost.optimalSavings)
            infoFrame.groundUpLabel:SetText(string.format("Ground-Up: %s |cff00ff00(-%s / %d%%)|r", groundUpStr, saveStr, cost.optimalSavingsPct))
        else
            infoFrame.groundUpLabel:SetText("Ground-Up: " .. groundUpStr)
        end
        if profitData.outputPrice > 0 then
            local pVal = profitData.groundUpProfit
            local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
            local pStr = FormatMoney(math.abs(pVal))
            local mCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
            infoFrame.profitLabel:SetText(string.format("Profit: %s%s|r (%s%d%%|r)", pCol, pStr, mCol, profitData.groundUpMarginPct))
            infoFrame.profitLabel:Show()
        else
            infoFrame.profitLabel:SetText(outputItemID and
                "|cff888888Profit: No AH price for output item|r" or
                "|cff888888Profit: No item output|r")
            infoFrame.profitLabel:Show()
        end

        infoFrame:ClearAllPoints()
        local reagents = schematicForm.Reagents
        if AuctionatorCraftingInfoProfessionsFrame and AuctionatorCraftingInfoProfessionsFrame:IsShown()
            and not DependsOnRegion(AuctionatorCraftingInfoProfessionsFrame, infoFrame) then
            infoFrame:SetPoint("TOPLEFT", AuctionatorCraftingInfoProfessionsFrame, "BOTTOMLEFT", 0, -4)
        elseif reagents and not DependsOnRegion(reagents, infoFrame) then
            infoFrame:SetPoint("TOPLEFT", reagents, "BOTTOMLEFT", 0, -10)
        else
            infoFrame:SetPoint("BOTTOMLEFT", schematicForm, "BOTTOMLEFT", 20, 20)
        end

        infoFrame:Show()
    end

    hooksecurefunc(schematicForm, "Init", UpdateModernCraftingInfo)
    if schematicForm.RegisterCallback and ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event then
        schematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified, UpdateModernCraftingInfo)
        schematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified, UpdateModernCraftingInfo)
    end

    local prevRefresh = MarketSync.RefreshCraftingInfoUI
    MarketSync.RefreshCraftingInfoUI = function()
        if prevRefresh then prevRefresh() end
        if ProfessionsFrame and ProfessionsFrame:IsShown() then
            UpdateModernCraftingInfo()
        end
    end
end

-- ================================================================
-- EVENT REGISTRATION & LIFECYCLE
-- ================================================================

local hookWatcher = CreateFrame("Frame")
hookWatcher:RegisterEvent("ADDON_LOADED")
hookWatcher:RegisterEvent("TRADE_SKILL_SHOW")
-- CRAFT_SHOW belongs to the older Craft UI and is absent on modern clients.
-- Validate before registering: some clients report an unknown event even when
-- RegisterEvent is called inside pcall.
local canRegisterCraftShow
if C_EventUtils and C_EventUtils.IsEventValid then
    canRegisterCraftShow = C_EventUtils.IsEventValid("CRAFT_SHOW")
else
    canRegisterCraftShow = type(GetCraftInfo) == "function" and type(GetCraftItemLink) == "function"
end
if canRegisterCraftShow then hookWatcher:RegisterEvent("CRAFT_SHOW") end

hookWatcher:SetScript("OnEvent", function(self, event, arg1)
    if event == "CRAFT_SHOW" then
        InitClassicCraftItemHooks()
    elseif event == "TRADE_SKILL_SHOW" then
        InitClassicTradeSkillHook()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TradeSkillUI" or arg1 == "Blizzard_CraftUI" then
            InitClassicTradeSkillHook()
            InitClassicCraftItemHooks()
        elseif arg1 == "Blizzard_Professions" then
            InitModernProfessionsHook()
        end
    end
end)

-- Attempt immediate initialization if frame is already present
InitClassicCraftItemHooks()
if TradeSkillFrame then
    InitClassicTradeSkillHook()
end
if ProfessionsFrame then
    InitModernProfessionsHook()
end
