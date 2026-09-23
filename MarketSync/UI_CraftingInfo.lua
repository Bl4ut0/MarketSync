-- =============================================================
-- MarketSync - Crafting Info & Multi-Tier Ground-Up UI
-- Profession Window Hooks & Interactive Materials Tree Drawer
-- =============================================================

MarketSync = MarketSync or {}
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
        frame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.9)
    end
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

    f.userOverrides = {}
    f.targetQuantity = 1

    -- Header Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("MarketSync Materials Breakdown & Checklist")
    f.title = title

    -- Subtitle / Recipe info
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", 16, -34)
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
    presetBg:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
    presetBg:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.8)

    local pLabel = presetBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pLabel:SetPoint("LEFT", 10, 0)
    pLabel:SetText("Strategy:")

    local btnOptimal = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnOptimal:SetSize(110, 20); btnOptimal:SetPoint("LEFT", pLabel, "RIGHT", 8, 0); btnOptimal:SetText("Optimal (Cheapest)")
    btnOptimal:SetNormalFontObject("GameFontNormalSmall")
    btnOptimal:SetScript("OnClick", function()
        f.userOverrides = {}
        f:RefreshTree()
    end)

    local btnBuyAll = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnBuyAll:SetSize(90, 20); btnBuyAll:SetPoint("LEFT", btnOptimal, "RIGHT", 6, 0); btnBuyAll:SetText("Buy Finished")
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
        f:RefreshTree()
    end)

    local btnCraftAll = CreateFrame("Button", nil, presetBg, "UIPanelButtonTemplate")
    btnCraftAll:SetSize(90, 20); btnCraftAll:SetPoint("LEFT", btnBuyAll, "RIGHT", 6, 0); btnCraftAll:SetText("Craft All Raw")
    btnCraftAll:SetNormalFontObject("GameFontNormalSmall")
    btnCraftAll:SetScript("OnClick", function()
        -- Force craft on all craftable nodes
        local function MarkCraft(nodes)
            for _, n in ipairs(nodes or {}) do
                if n.canCraft then
                    f.userOverrides[n.itemID] = true
                end
                if n.subMats then MarkCraft(n.subMats) end
            end
        end
        if f.lastCostData and f.lastCostData.reagentsTree then
            MarkCraft(f.lastCostData.reagentsTree)
        end
        f:RefreshTree()
    end)

    -- Scroll Frame for Reagent Tree
    local scrollFrame = CreateFrame("ScrollFrame", "MarketSyncCraftingTreeScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -96)
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
    summaryBox:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    summaryBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.8)

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
    btnExport:SetSize(180, 24); btnExport:SetPoint("BOTTOMLEFT", 16, 12); btnExport:SetText("Export to AH Shopping List")
    btnExport:SetScript("OnClick", function()
        if f.lastCostData and f.lastCostData.reagentsTree then
            local rName = f.currentRecipe and f.currentRecipe.name or "Craft Mats"
            local success, countOrErr = MarketSync.ExportCustomShoppingList(f.lastCostData.reagentsTree, f.userOverrides, "MarketSync " .. rName)
            if success then
                print(string.format("|cff00ff00[MarketSync]|r Exported %d items to Auctionator shopping list: MarketSync %s", countOrErr, rName))
            else
                print("|cffff2020[MarketSync]|r Export failed: " .. tostring(countOrErr))
            end
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

            -- Tree branch icon / bullet
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16); icon:SetPoint("LEFT", 0, 0)
            row.icon = icon

            -- Interactive Craft Checkbox for craftables
            local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            check:SetSize(20, 20); check:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            row.check = check

            -- Main Item Text (Quantity + Name)
            local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", check, "RIGHT", 4, 0)
            row.itemText = itemText

            -- Price & Comparison Details
            local detailText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            detailText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.detailText = detailText

            f.rowPool[index] = row
        end
        return row
    end

    function f:RefreshTree()
        if not self.currentRecipe then return end

        local profitData = MarketSync.CalculateRecipeProfit(self.currentRecipe, self.userOverrides, self.targetQuantity)
        if not profitData or not profitData.costData then return end

        local cost = profitData.costData
        self.lastCostData = cost
        self.qtyValue:SetText(tostring(self.targetQuantity))

        local rName = self.currentRecipe.name or "Recipe"
        self.subtitle:SetText(string.format("|cffffd700%s|r (Total Yield: %d)", rName, cost.outputQty))

        -- Summary Strings
        self.sumDirect:SetText("Direct Purchase Cost: " .. FormatMoney(cost.directCraftCost))
        self.sumEffective:SetText("Effective Cost: " .. FormatMoney(cost.effectiveCost))

        if cost.savings > 0 then
            self.sumSavings:SetText(string.format("Gold Saved: |cff00ff00%s (%d%% saved)|r", FormatMoney(cost.savings), cost.savingsPct))
        else
            self.sumSavings:SetText("|cff888888No savings (Direct purchase is optimal)|r")
        end

        if profitData.outputPrice > 0 then
            local pVal = profitData.effectiveProfit
            local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
            local pStr = FormatMoney(math.abs(pVal))
            self.sumProfit:SetText(string.format("Net Profit: %s%s|r (%d%%)", pCol, pStr, profitData.effectiveMarginPct))
        else
            self.sumProfit:SetText("|cff888888Profit: No AH price|r")
        end

        -- Flatten tree for visual display
        local displayRows = {}
        local function Flatten(nodes, depth)
            for _, node in ipairs(nodes or {}) do
                table.insert(displayRows, { node = node, depth = depth })
                -- If user is crafting this intermediate, show its sub-mats indented below!
                if node.chooseCraft and node.subMats and #node.subMats > 0 then
                    Flatten(node.subMats, depth + 1)
                end
            end
        end

        Flatten(cost.reagentsTree, 0)

        -- Render rows
        for _, r in ipairs(self.rowPool) do r:Hide() end

        local curY = 0
        for i, rowData in ipairs(displayRows) do
            local node = rowData.node
            local depth = rowData.depth
            local row = GetRow(i)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 6, curY)
            row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -6, curY)

            local indentX = depth * 20
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", indentX, 0)

            -- Item texture
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(node.itemID)
            row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Item Text
            local isFinishedChosen = not node.chooseCraft
            local nameColor = isFinishedChosen and "|cffffffff" or "|cff00ffff"
            local sourceTag = node.isVendor and "|cff00ffcc[Vendor]|r " or (node.canCraft and "|cffffff00[Craftable]|r " or "|cffaaaaaa[AH]|r ")
            row.itemText:SetText(string.format("%s%s%s x%d|r", sourceTag, nameColor, node.name, node.qty))

            -- Checkbox logic for craftable intermediate
            if node.canCraft then
                row.check:Show()
                row.check:ClearAllPoints()
                row.check:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.itemText:ClearAllPoints()
                row.itemText:SetPoint("LEFT", row.check, "RIGHT", 4, 0)

                row.check:SetChecked(node.chooseCraft == true)
                row.check:SetScript("OnClick", function(chk)
                    f.userOverrides[node.itemID] = chk:GetChecked()
                    f:RefreshTree()
                end)

                -- Comparison detail
                local buyStr = FormatMoney(node.directTotalPrice)
                local craftStr = FormatMoney(node.craftTotalPrice or 0)
                if node.unitSavings > 0 then
                    local saveStr = FormatMoney(node.totalSavings)
                    row.detailText:SetText(string.format("Craft: %s |cff888888(AH: %s)|r |cff00ff00(-%s)|r", craftStr, buyStr, saveStr))
                else
                    row.detailText:SetText(string.format("AH: %s |cff888888(Craft: %s)|r", buyStr, craftStr))
                end
            else
                row.check:Hide()
                row.itemText:ClearAllPoints()
                row.itemText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)

                -- Raw material detail
                local costStr = FormatMoney(node.effectiveTotalPrice)
                local unitStr = FormatMoney(node.effectiveUnitPrice)
                row.detailText:SetText(string.format("%s |cff888888(%s ea)|r", costStr, unitStr))
            end

            row:Show()
            curY = curY - 26
        end

        scrollContent:SetHeight(math.max(300, math.abs(curY) + 20))
    end

    treeFrame = f
    return f
end

function MarketSync.OpenCraftingTree(recipeOrOutputItemID, anchorFrame)
    local f = CreateCraftingTreeFrame()
    f.targetQuantity = 1
    f.userOverrides = {}

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

local function InitClassicTradeSkillHook()
    if not TradeSkillFrame then return end
    if MarketSync.TradeSkillHookInitialized then return end
    MarketSync.TradeSkillHookInitialized = true

    local infoFrame = CreateFrame("Frame", "MarketSyncCraftingInfo", TradeSkillFrame)
    infoFrame:SetSize(240, 52)
    infoFrame:SetFrameLevel(TradeSkillFrame:GetFrameLevel() + 5)

    -- Labels
    infoFrame.costLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.costLabel:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
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
    btnBreakdown:SetPoint("LEFT", infoFrame.groundUpLabel, "RIGHT", 6, 0)
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

        local profitData = MarketSync.CalculateRecipeProfit(recipe)
        if not profitData or not profitData.costData then
            infoFrame:Hide()
            return
        end

        local cost = profitData.costData

        -- Direct Cost Line
        local directStr = FormatMoney(cost.directCraftCost)
        infoFrame.costLabel:SetText("To Craft: " .. directStr)

        -- Ground-Up Line
        local groundUpStr = FormatMoney(cost.groundUpCost)
        if cost.optimalSavings > 0 then
            local saveStr = FormatMoney(cost.optimalSavings)
            infoFrame.groundUpLabel:SetText(string.format("Ground-Up: %s |cff00ff00(-%s / %d%%)|r", groundUpStr, saveStr, cost.optimalSavingsPct))
        else
            infoFrame.groundUpLabel:SetText("Ground-Up: " .. groundUpStr)
        end
        btnBreakdown:Show()
        btnBreakdown:ClearAllPoints()
        btnBreakdown:SetPoint("LEFT", infoFrame.groundUpLabel, "RIGHT", 8, 0)

        -- Profit Line
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
            infoFrame.profitLabel:SetText("|cff888888Profit: No AH price for output item|r")
            infoFrame.profitLabel:Show()
        end

        -- Warnings
        if profitData.hasWarnings and #profitData.warnings > 0 then
            infoFrame.warningLabel:SetText("|cffff9900Warning: " .. table.concat(profitData.warnings, ", ") .. "|r")
            infoFrame.warningLabel:Show()
        else
            infoFrame.warningLabel:Hide()
        end

        -- Anchoring: coordinate with or without Auctionator
        infoFrame:ClearAllPoints()
        local originalFirstLine = TradeSkillDescription or TradeSkillReagentLabel
        if AuctionatorCraftingInfo and AuctionatorCraftingInfo:IsShown() then
            infoFrame:SetPoint("TOPLEFT", AuctionatorCraftingInfo, "BOTTOMLEFT", 0, -2)
        elseif originalFirstLine then
            infoFrame:SetPoint("TOPLEFT", originalFirstLine, "TOPLEFT", 0, 0)
            if not infoFrame.hasShiftedDescription then
                infoFrame.hasShiftedDescription = true
                infoFrame.origPoint = { originalFirstLine:GetPoint(1) }
                originalFirstLine:ClearAllPoints()
                originalFirstLine:SetPoint("TOPLEFT", infoFrame, "BOTTOMLEFT", 0, -6)
            end
        else
            infoFrame:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 210, -120)
        end

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
    infoFrame:SetFrameLevel(schematicForm:GetFrameLevel() + 5)

    infoFrame.costLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.costLabel:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 0, 0)
    infoFrame.costLabel:SetJustifyH("LEFT")

    infoFrame.groundUpLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.groundUpLabel:SetPoint("TOPLEFT", infoFrame.costLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.groundUpLabel:SetJustifyH("LEFT")

    infoFrame.profitLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoFrame.profitLabel:SetPoint("TOPLEFT", infoFrame.groundUpLabel, "BOTTOMLEFT", 0, -2)
    infoFrame.profitLabel:SetJustifyH("LEFT")

    local btnBreakdown = CreateFrame("Button", nil, infoFrame, "UIPanelButtonTemplate")
    btnBreakdown:SetSize(96, 18)
    btnBreakdown:SetPoint("LEFT", infoFrame.groundUpLabel, "RIGHT", 6, 0)
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

    local function UpdateModernCraftingInfo()
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
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
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
        btnBreakdown:ClearAllPoints()
        btnBreakdown:SetPoint("LEFT", infoFrame.groundUpLabel, "RIGHT", 8, 0)

        if profitData.outputPrice > 0 then
            local pVal = profitData.groundUpProfit
            local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
            local pStr = FormatMoney(math.abs(pVal))
            local mCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
            infoFrame.profitLabel:SetText(string.format("Profit: %s%s|r (%s%d%%|r)", pCol, pStr, mCol, profitData.groundUpMarginPct))
            infoFrame.profitLabel:Show()
        else
            infoFrame.profitLabel:SetText("|cff888888Profit: No AH price for output item|r")
            infoFrame.profitLabel:Show()
        end

        infoFrame:ClearAllPoints()
        local reagents = schematicForm.Reagents
        if AuctionatorCraftingInfoProfessionsFrame and AuctionatorCraftingInfoProfessionsFrame:IsShown() then
            infoFrame:SetPoint("TOPLEFT", AuctionatorCraftingInfoProfessionsFrame, "BOTTOMLEFT", 0, -4)
        elseif reagents then
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

hookWatcher:SetScript("OnEvent", function(self, event, arg1)
    if event == "TRADE_SKILL_SHOW" then
        InitClassicTradeSkillHook()
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TradeSkillUI" or arg1 == "Blizzard_CraftUI" then
            InitClassicTradeSkillHook()
        elseif arg1 == "Blizzard_Professions" then
            InitModernProfessionsHook()
        end
    end
end)

-- Attempt immediate initialization if frame is already present
if TradeSkillFrame then
    InitClassicTradeSkillHook()
end
if ProfessionsFrame then
    InitModernProfessionsHook()
end
