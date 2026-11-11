-- Persistent three-pane craft planner; profession hooks use this entry point.
local L = MarketSync.CraftLedger
local window
local function ThemeColor(role,...)
    if MarketSync.GetThemeColor then return MarketSync.GetThemeColor(role) end
    return ...
end
local function Money(value)
    value=math.floor(value or 0)
    local sign=value<0 and "-" or ""
    return sign .. (MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(math.abs(value)) or tostring(math.abs(value)) .. "c")
end
local function Name(id) return (MarketSync.GetItemInfo and MarketSync.GetItemInfo(id)) or ("Item " .. id) end
local function Text(parent, x, y, width, text, font)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    t:SetPoint("TOPLEFT", x, y); t:SetWidth(width); t:SetJustifyH("LEFT"); t:SetText(text or ""); return t
end
local function Button(parent, x, y, width, label, click, template)
    local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y); b:SetSize(width, 22); b:SetText(label); b:SetScript("OnClick", click); return b
end
local function CreateInset(parent, x, y, width, height)
    if MarketSync.CreateModernInset then
        local inset = MarketSync.CreateModernInset(parent, x, y, width, height)
        if x and y then inset:SetPoint("TOPLEFT", x, y) end
        if width and height then inset:SetSize(width, height) end
        return inset
    end
    local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if x and y then inset:SetPoint("TOPLEFT", x, y) end
    if width and height then inset:SetSize(width, height) end
    inset:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    inset._marketSyncThemeRole = "inset"
    inset:SetBackdropColor(0.05, 0.045, 0.04, 0.90)
    inset:SetBackdropBorderColor(0.50, 0.42, 0.28, 0.95)
    return inset
end
local function Copy(t) local out = {}; for k,v in pairs(t or {}) do out[k] = v end; return out end
local function Prompt(key, label, callback)
    StaticPopupDialogs[key] = { text = label, button1 = "Save", button2 = "Cancel", hasEditBox = true,
        timeout = 0, whileDead = true, hideOnEscape = true, OnAccept = function(p)
            local box = p.editBox or p.EditBox; if box then callback(box:GetText()) end
        end }
    StaticPopup_Show(key)
end
local function Report(ok, reason) if not ok then print("|cffff5555[MarketSync]|r " .. (reason or "Invalid entry or action for this craft.")) end end
function MarketSync.PromptCraftPurchase(jobID, itemID)
    Prompt("MARKETSYNC_CRAFT_PURCHASE","Purchase: quantity, total gold paid (e.g. 2,3.5)",function(text)
        local q,g=text:match("^%s*(%d+)%s*,%s*([%d%.]+)%s*$")
        q,g=tonumber(q),tonumber(g)
        Report(q and g and L.RecordPurchase(itemID,q,g*10000,nil,jobID))
    end)
end
local function Select(job)
    local f = window
    f.jobID, f.recipe, f.quantity = job.id, job.recipe, job.quantity
    f.choices, f.selectedBuys = Copy(job.choices), Copy(job.selectedBuys)
    f.expanded = {}; f.selectedNodeID = job.itemID
    f.dirty = false; f:Refresh()
end
local function SaveDraft(frame)
    if not frame.recipe or frame.history then return false end
    local job,reason=L.Save(frame.recipe,{quantity=frame.quantity,choices=frame.choices,selectedBuys=frame.selectedBuys},frame.jobID)
    if not job then Report(false,reason); return false end
    Select(job); return true
end
local function DiscardOrRun(frame, callback, context)
    if not frame.dirty then callback(); return end
    StaticPopupDialogs.MARKETSYNC_SAVE_CRAFT={text="Save your craft changes before "..(context or "switching crafts").."?",
        button1="Save",button2="Cancel",button3="Discard",timeout=0,hideOnEscape=true,
        OnAccept=function() if SaveDraft(frame) then callback() end end,
        OnAlt=function()
            local saved=frame.jobID and L.Get(frame.jobID)
            if saved then Select(saved) else frame.dirty=false; frame.recipe=nil; frame:Refresh() end
            callback()
        end,
    }
    StaticPopup_Show("MARKETSYNC_SAVE_CRAFT")
end
local function OpenShopping(job)
    if not job or not job.shoppingName then return end
    if MarketSync.AHSidecar and MarketSync.AHSidecar.SelectShoppingList then MarketSync.AHSidecar.SelectShoppingList(job.shoppingName) end
    if MarketSync.AHSidecar and MarketSync.AHSidecar.ShowForMain then MarketSync.AHSidecar.ShowForMain("lists") end
end
function MarketSync.ShowCraftProfessions(anchor)
    if InCombatLockdown and InCombatLockdown() then return end
    if anchor.professionMenu then anchor.professionMenu:Hide(); anchor.professionMenu = nil; return end
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    if MarketSync.Theme then MarketSync.Theme.Register(menu) end
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2); menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12})
    local professions = MarketSync.GetProcessingProfessions()
    menu:SetSize(200, math.max(35, #professions * 26 + 12))
    for i, name in ipairs(professions) do
        local spell = name == "First Aid (Health)" and "First Aid" or name
        local b = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate,UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", 6, -6 - (i-1)*26); b:SetSize(188,24); b:SetText(name)
        b:SetAttribute("type", "spell"); b:SetAttribute("spell", spell)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetScript("PostClick", function() menu:Hide(); anchor.professionMenu = nil end)
    end
    if #professions == 0 then Text(menu, 8, -10, 185, "Open a profession to detect it.") end
    anchor.professionMenu = menu; menu:Show()
end
local function Create()
    if window then return window end
    local ok, res
    local legacyTheme = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    if legacyTheme then
        ok, res = pcall(CreateFrame, "Frame", "MarketSyncCraftManager", UIParent, "BackdropTemplate")
    else
        ok, res = pcall(CreateFrame, "Frame", "MarketSyncCraftManager", UIParent, "PortraitFrameTemplate")
    end
    local f
    if ok and res then
        f = res
    else
        f = CreateFrame("Frame", "MarketSyncCraftManager", UIParent)
    end
    window = f
    f:SetSize(832, 480); f:SetPoint("CENTER"); f:SetClampedToScreen(true); f:SetFrameStrata("HIGH")
    f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)

    if legacyTheme and f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 10, right = 10, top = 10, bottom = 10 },
        })
        f:SetBackdropColor(0.08, 0.08, 0.09, 1)
    end
    if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(f) end

    local function Close()
        DiscardOrRun(f,function() f.closing=true; f:Hide(); f.closing=false end,"closing")
    end
    f.ConfirmContextSwitch=function(callback) DiscardOrRun(f,callback,"opening another window") end
    f:SetScript("OnHide",function()
        if f.dirty and not f.closing then f:Show(); Close() end
    end)

    -- Portrait in top-left
    local portrait = (f.GetPortrait and f:GetPortrait())
        or (type(f.PortraitContainer) == "table" and f.PortraitContainer.portrait)
        or _G["MarketSyncCraftManagerPortrait"]
    if not portrait then
        portrait = f:CreateTexture(nil, "BACKGROUND")
        portrait:SetSize(60, 60)
        portrait:SetPoint("TOPLEFT", 6, -6)
        if f.CreateMaskTexture then
            local mask = f:CreateMaskTexture()
            if mask then
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetSize(58, 58)
                mask:SetPoint("TOPLEFT", 8, -7)
                if portrait.AddMaskTexture then portrait:AddMaskTexture(mask) end
            end
        end
    end
    f.portrait = portrait
    local function UpdatePortrait()
        if SetPortraitToAsset and portrait then
            SetPortraitToAsset(portrait, "Interface\\Icons\\Trade_BlackSmithing")
        elseif portrait and portrait.SetTexture then
            portrait:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
            if portrait.SetTexCoord then portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        end
    end
    f:HookScript("OnShow", UpdatePortrait)
    UpdatePortrait()

    -- Title Text inside Blizzard Title Bar
    local titleText = (f.GetTitleText and f:GetTitleText())
        or (type(f.TitleContainer) == "table" and f.TitleContainer.TitleText)
        or _G["MarketSyncCraftManagerTitleText"]
    if not titleText then
        titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", 0, -18)
    end
    titleText:SetTextColor(1, 0.82, 0)
    titleText:SetText("MarketSync - Materials & Crafting Choices")
    f.titleText = titleText
    f.TitleText = titleText

    -- Close button
    local closeIcon = (type(f.CloseButton) == "table" and f.CloseButton) or _G["MarketSyncCraftManagerCloseButton"]
    if not closeIcon then
        closeIcon = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeIcon:SetPoint("TOPRIGHT", -4, -4)
    end
    closeIcon:SetScript("OnClick", Close)
    f.CloseButton = closeIcon
    f.closeButton = closeIcon

    -- Quantity Stepper in header area
    local qtyFrame = CreateFrame("Frame", nil, f)
    qtyFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -44, legacyTheme and -12 or -3)
    qtyFrame:SetSize(130, 20)
    local minusBtn = CreateFrame("Button", nil, qtyFrame, "UIPanelButtonTemplate")
    minusBtn:SetSize(20, 20); minusBtn:SetPoint("LEFT", 0, 0); minusBtn:SetText("-")
    minusBtn:SetScript("OnClick", function()
        if not f.history then
            f.quantity = math.max(1, (f.quantity or 1) - 1)
            f.dirty = true
            f:Refresh()
        end
    end)
    local qtyText = qtyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qtyText:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
    qtyText:SetPoint("RIGHT", qtyFrame, "RIGHT", -24, 0)
    qtyText:SetJustifyH("CENTER")
    f.qty = qtyText
    local plusBtn = CreateFrame("Button", nil, qtyFrame, "UIPanelButtonTemplate")
    plusBtn:SetSize(20, 20); plusBtn:SetPoint("RIGHT", 0, 0); plusBtn:SetText("+")
    plusBtn:SetScript("OnClick", function()
        if not f.history then
            f.quantity = (f.quantity or 1) + 1
            f.dirty = true
            f:Refresh()
        end
    end)

    f.subtitle = Text(f, 66, legacyTheme and -36 or -32, 580, nil, "GameFontHighlightSmall")

    -- Top Strategy Inset Toolbar
    local strategy = CreateInset(f, 16, -56, 800, 30)
    local baseLevel = (f.GetFrameLevel and f:GetFrameLevel()) or 1
    if strategy.SetFrameLevel then strategy:SetFrameLevel(baseLevel + 1) end

    local function Preset(value)
        local cost = f.recipe and MarketSync.CalculateGroundUpCraftCost(f.recipe,{},f.quantity)
        local function Walk(nodes) for _,n in ipairs(nodes or {}) do if n.canCraft then f.choices[n.itemID]=value end; Walk(n.subMats) end end
        Walk(cost and cost.reagentsTree); f.dirty=true; f:Refresh()
    end

    Button(strategy, 4, -4, 68, "Optimal", function() f.choices={}; f.selectedBuys={}; f.dirty=true; f:Refresh() end)
    Button(strategy, 74, -4, 86, "Buy Finished", function() Preset(false) end)
    Button(strategy, 162, -4, 90, "Craft All Raw", function() Preset(true) end)
    Button(strategy, 254, -4, 94, "Import Plans", function()
        local count=L.ImportLegacyPlans(); print("|cff00ff00[MarketSync]|r Imported "..count.." saved craft requests."); f:Refresh()
    end)
    Button(strategy, 350, -4, 102, "Customer Craft", function()
        if not f.jobID then Report(false,"Save the craft first."); return end
        local id=f.jobID
        Prompt("MARKETSYNC_CRAFT_CUSTOMER","Customer character name for this supplied-material craft",function(text)
            Report(L.SetService(id,text)); f:Refresh()
        end)
    end)
    Button(strategy, 454, -4, 90, "Record Qty", function()
        local id=f.jobID; if not id then return end
        Prompt("MARKETSYNC_CRAFT_QUANTITY","Number of outputs actually completed (manual correction for missing craft events)",function(text)
            local qty=tonumber(text); Report(qty and L.Complete(id,qty)); f:Refresh()
        end)
    end)
    local ledgerBtn = Button(strategy, 546, -4, 96, "Item Ledger", function()
        if not MarketSync.IsLedgerEnabled or not MarketSync.IsLedgerEnabled() then
            print("|cffffbb44[MarketSync]|r The Item Ledger is currently disabled. Enable it under AddOn Settings > Beta Features.")
            return
        end
        if MarketSync.OpenItemLedger then MarketSync.OpenItemLedger(f.jobID) end
    end)
    ledgerBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled() then
            GameTooltip:SetText("MarketSync Item Ledger", 1, 0.82, 0)
            GameTooltip:AddLine("Open the Item & Gold Ledger window.", 0.8, 0.8, 0.8)
        else
            GameTooltip:SetText("MarketSync Item Ledger |cffff4444(Disabled)|r", 1, 0.82, 0)
            GameTooltip:AddLine("Enable the Transactional Item Ledger in AddOn Settings > Beta Features to access this feature.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    ledgerBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.ledgerBtn = ledgerBtn

    function f.UpdateLedgerButtonState()
        local isEnabled = MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()
        if isEnabled then
            if f.ledgerBtn.Enable then f.ledgerBtn:Enable() end
            if f.ledgerBtn.SetAlpha then f.ledgerBtn:SetAlpha(1.0) end
        else
            if f.ledgerBtn.Disable then f.ledgerBtn:Disable() end
            if f.ledgerBtn.SetAlpha then f.ledgerBtn:SetAlpha(0.5) end
        end
    end

    local profBtn = Button(strategy, 644, -4, 152, "Professions v", function(self) MarketSync.ShowCraftProfessions(self) end)
    f.profBtn = profBtn

    f.expanded = {}
    f.panes = {}
    -- Three native insets matching Blizzard UI
    local paneSpecs = {
        [1] = { 272, 278, "Recipe breakdown" },
        [2] = { 556, 260, "Purchase plan" },
        [3] = { 16,  250, "Craft Management" },
    }
    for i = 1, 3 do
        local spec = paneSpecs[i]
        local pane = CreateInset(f, spec[1], -90, spec[2], 306)

        local paneHdrBg = pane:CreateTexture(nil, "BORDER")
        paneHdrBg:SetPoint("TOPLEFT", 3, -3); paneHdrBg:SetPoint("TOPRIGHT", -3, -3); paneHdrBg:SetHeight(24)
        paneHdrBg:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        paneHdrBg:SetVertexColor(0.50, 0.42, 0.28, 0.35)

        pane.heading = Text(pane, 8, -6, spec[2] - 16, "|cffffd700" .. spec[3] .. "|r", "GameFontNormal")
        if MarketSync.CreateAHColumnHeader then
            local colTitle = i == 1 and "Item / Recipe" or i == 2 and "Material / Cost (Right-Click)" or "Craft"
            local colHdr = MarketSync.CreateAHColumnHeader(pane, spec[2] - 4, 20, colTitle)
            colHdr:SetPoint("TOPLEFT", 2, -26)
            pane.columns = colHdr.label or colHdr
        else
            pane.columns = Text(pane, 10, -28, spec[2] - 20, i == 1 and "Item / Recipe" or i == 2 and "Material / Cost" or "Craft / Quantity / Status", "GameFontNormalSmall")
        end
        if i == 1 then
            Text(pane, spec[2] - 95, -28, 30, "Need", "GameFontNormalSmall")
            Text(pane, spec[2] - 62, -28, 58, "Action", "GameFontNormalSmall")
        elseif i == 3 then
            pane.columns:SetText("Craft")
            Text(pane, spec[2] - 110, -28, 28, "Qty", "GameFontNormalSmall")
            Text(pane, spec[2] - 78, -28, 72, "Status", "GameFontNormalSmall")
        end

        local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 4, -48)
        scroll:SetPoint("BOTTOMRIGHT", -22, i == 3 and 60 or 6)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(spec[2] - 34, 1)
        scroll:SetScrollChild(content)
        pane.content = content
        pane.scroll = scroll
        pane.rows = {}
        f.panes[i] = pane
    end

    local p = f.panes[3]
    f.completeButton = Button(p, 4, -252, 118, "Mark Crafted", function()
        Report(f.jobID and L.Complete(f.jobID))
        if f.jobID and L.Get(f.jobID).status == "Crafted" then f.history = true end
        f:Refresh()
    end)
    f.saleButton = Button(p, 126, -252, 118, "Record Sale", function()
        local id = f.jobID; if not id then return end
        Prompt("MARKETSYNC_CRAFT_SALE", "Sale: quantity, gross sale gold, fees in gold (e.g. 1,42,2.1)", function(text)
            local q, g, fee = text:match("^%s*(%d+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
            q, g, fee = tonumber(q), tonumber(g), tonumber(fee)
            Report(q and g and fee and L.RecordSale(id, q, g * 10000, fee * 10000))
        end)
    end)
    f.removeButton = Button(p, 4, -278, 118, "Remove Craft", function()
        if not f.jobID then return end
        local id = f.jobID
        StaticPopupDialogs.MARKETSYNC_REMOVE_JOB = {
            text = "Permanently remove this craft and its recorded history?",
            button1 = "Remove", button2 = "Cancel", timeout = 0, hideOnEscape = true,
            OnAccept = function() f.jobID = nil; f.recipe = nil; L.Remove(id); f:Refresh() end
        }
        StaticPopup_Show("MARKETSYNC_REMOVE_JOB")
    end)
    f.historyButton = Button(p, 126, -278, 118, "Craft History", function()
        DiscardOrRun(f, function()
            f.history = not f.history
            f.jobID = nil
            f.recipe = nil
            f.dirty = false
            f:Refresh()
        end)
    end)

    f.selectedIcon = f:CreateTexture(nil, "ARTWORK")
    f.selectedIcon:SetPoint("TOPLEFT", 18, -404)
    f.selectedIcon:SetSize(36, 36)
    local iconBorder = f:CreateTexture(nil, "OVERLAY")
    iconBorder:SetPoint("CENTER", f.selectedIcon, "CENTER", 0, 0)
    iconBorder:SetSize(46, 46)
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    f.selectedIconBorder = iconBorder

    f.selectionText = Text(f, 62, -406, 400)
    f.state = Text(f, 62, -424, 400, nil, "GameFontNormalSmall")

    f.shoppingButton = Button(f, 474, -410, 116, "Export Shopping", function()
        OpenShopping(f.jobID and L.Get(f.jobID))
    end)
    f.save = Button(f, 596, -410, 130, "Add to Craft List", function()
        SaveDraft(f)
    end)
    f.closeButton = Button(f, 732, -410, 84, "Close", Close)

    local function CreateCraftTab(id, text)
        local tabName = "MarketSyncCraftManagerTab" .. id
        local templates = legacyTheme
            and {"CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate"}
            or {"AuctionHouseFrameDisplayModeTabTemplate", "AuctionHouseFrameTabTemplate", "PanelTabButtonTemplate"}
        local tab
        for _, tmpl in ipairs(templates) do
            local ok, res = pcall(CreateFrame, "Button", tabName, f, tmpl)
            if ok and res then tab = res; break end
        end
        if not tab then tab = CreateFrame("Button", tabName, f) end
        tab:SetID(id)
        tab:SetText(text)
        tab:SetHeight(32)
        tab:SetWidth(150)
        local baseLevel = f.GetFrameLevel and f:GetFrameLevel() or 1
        if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 4) end
        if type(tab.Text) == "table" and tab.Text.SetWidth then tab.Text:SetWidth(134) end
        if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0, 150) end
        if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
        return tab
    end

    local tab1 = CreateCraftTab(1, "Materials & Planning")
    local tab2 = CreateCraftTab(2, "Craft History")
    f.tabs = {tab1, tab2}
    f.numTabs = 2

    if legacyTheme then
        tab1:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 60, 12)
        tab2:SetPoint("TOPLEFT", tab1, "TOPRIGHT", -8, 0)
    else
        tab1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 19, -28)
        tab2:SetPoint("BOTTOMLEFT", tab1, "BOTTOMRIGHT", -2, 0)
    end

    tab1:SetScript("OnClick", function()
        if f.history then
            DiscardOrRun(f, function()
                f.history = false
                f.jobID = nil
                f.recipe = nil
                f.dirty = false
                f:Refresh()
            end)
        end
    end)
    tab2:SetScript("OnClick", function()
        if not f.history then
            DiscardOrRun(f, function()
                f.history = true
                f.jobID = nil
                f.recipe = nil
                f.dirty = false
                f:Refresh()
            end)
        end
    end)

    local function Row(pane,index,height)
        local row=pane.rows[index]
        if not row then
            row=CreateFrame("Button",nil,pane.content,"BackdropTemplate"); row:SetWidth(pane.content:GetWidth()); row:RegisterForClicks("LeftButtonUp","RightButtonUp")
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
            hl:SetAlpha(0.20)
            row.hl = hl
            row.label=Text(row,3,-7,pane.content:GetWidth()-8,nil,"GameFontHighlightSmall")
            row.action=Button(row,pane.content:GetWidth()-62,-3,60,"",function() end)
            row.expand=Button(row,0,-4,16,"-",function() end); row.expand:SetSize(16,20)
            row.iconButton=CreateFrame("Button",nil,row); row.iconButton:SetSize(22,22)
            row.icon=row.iconButton:CreateTexture(nil,"ARTWORK"); row.icon:SetAllPoints(row.iconButton)
            row.quantity=Text(row,pane.content:GetWidth()-92,-8,28,nil,"GameFontHighlightSmall")
            row.status=Text(row,pane.content:GetWidth()-74,-8,72,nil,"GameFontHighlightSmall")
            row.guide=row:CreateTexture(nil,"BACKGROUND"); row.guide:SetColorTexture(ThemeColor("border",0.4,0.35,0.25,0.4))
            pane.rows[index]=row
        end
        row:SetPoint("TOPLEFT",0,-(index-1)*height); row:SetHeight(height); row.action:Hide(); row.expand:Hide(); row.iconButton:Hide(); row.quantity:Hide(); row.status:Hide(); row.guide:Hide()
        row.label:SetHeight(height-6)
        row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT",3,-7); row.label:SetWidth(pane.content:GetWidth()-8)
        row.itemID=nil; row.selected=false
        row:SetBackdropColor(ThemeColor(index%2==0 and "rowEven" or "rowOdd",0.10,0.09,0.08,index%2==0 and 0.45 or 0.25))
        row:SetBackdropBorderColor(ThemeColor("border",0.28,0.22,0.15,0.45))
        row:SetScript("OnClick",nil)
        local function Enter(owner)
            if row.itemID and GameTooltip then
                GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then GameTooltip:SetItemByID(row.itemID)
                elseif GameTooltip.SetHyperlink then GameTooltip:SetHyperlink("item:"..row.itemID) end
                GameTooltip:Show()
            end
        end
        row:SetScript("OnEnter",function(self)
            if not self.selected then
                self:SetBackdropColor(ThemeColor("hover",0.20,0.16,0.08,0.75))
                self:SetBackdropBorderColor(ThemeColor("border",0.50,0.40,0.20,0.85))
            end
            Enter(self)
        end)
        row:SetScript("OnLeave",function(self)
            if not self.selected then
                self:SetBackdropColor(ThemeColor(index%2==0 and "rowEven" or "rowOdd",0.10,0.09,0.08,index%2==0 and 0.45 or 0.25))
                self:SetBackdropBorderColor(ThemeColor("border",0.28,0.22,0.15,0.45))
            end
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.iconButton:SetScript("OnEnter",Enter); row.iconButton:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        row.iconButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row.iconButton:SetScript("OnClick",function(_,button) local click=row:GetScript("OnClick"); if click then click(row,button) end end)
        row:Show(); return row
    end
    local function ItemRow(row,id,indent)
        row.itemID=id
        local icon=id and (MarketSync.GetItemIcon and MarketSync.GetItemIcon(id) or (MarketSync.GetItemInfo and select(10,MarketSync.GetItemInfo(id))))
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.iconButton:ClearAllPoints(); row.iconButton:SetPoint("LEFT",row,"LEFT",indent or 4,0); row.iconButton:Show()
        row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT",(indent or 4)+26,-7)
        row.label:SetWidth(row:GetWidth()-(indent or 4)-32)
    end
    local function Highlight(row)
        row.selected=true
        row:SetBackdropColor(ThemeColor("hover",0.25,0.18,0.05,0.90))
        row:SetBackdropBorderColor(1,0.82,0,0.95)
    end
    function f:Refresh()
        for _,pane in ipairs(self.panes) do for _,row in ipairs(pane.rows) do row:Hide() end end
        local job=self.jobID and L.Get(self.jobID)
        self.historyButton:SetText(self.history and "Pending Crafts" or "Craft History")
        self.shoppingButton:SetEnabled(job~=nil and job.shoppingName~=nil)
        self.completeButton:SetEnabled(job~=nil and job.status=="Purchased" and not self.dirty)
        self.removeButton:SetEnabled(job~=nil)
        self.saleButton:SetEnabled(job~=nil and job.itemID~=nil and job.kind~="service" and job.status=="Crafted")
        self.qty:SetText("Qty: "..(self.quantity or 1))
        self.subtitle:SetText(self.recipe and ((self.recipe.name or "Craft") .. (job and " · "..job.status or " · New craft")) or "Select a pending craft, or open a profession to choose a recipe.")
        self.save:SetText(job and "Update Craft" or "Add to Craft List")
        self.save:SetEnabled(self.recipe~=nil and not self.history and (not job or self.dirty))
        self.selectionText:SetText(self.recipe and ("Selected craft: |cff00ffff"..(self.recipe.name or "Craft").." x"..(self.quantity or 1).."|r"..(job and " · "..job.status or " · New craft")) or "Select a craft to view its recipe and costs.")
        local outputID=self.recipe and tonumber(self.recipe.outputItemID)
        self.selectedIcon:SetTexture(outputID and ((MarketSync.GetItemIcon and MarketSync.GetItemIcon(outputID)) or (MarketSync.GetItemInfo and select(10,MarketSync.GetItemInfo(outputID)))) or "Interface\\Icons\\INV_Misc_QuestionMark")
        self.state:SetText(self.dirty and "|cffffcc00Unsaved changes — "..(job and "Update Craft to save." or "Add to Craft List to save.").."|r" or "Select a recipe row to inspect it. Right-click a tracked craft for actions.")
        local n=0
        local cost=self.recipe and MarketSync.CalculateGroundUpCraftCost(self.recipe,self.choices,self.quantity)
        local selectedNode
        local function Walk(nodes,depth,parentPath)
            for index,node in ipairs(nodes or {}) do
                local path=parentPath.."/"..index..":"..node.itemID
                n=n+1; local row=Row(self.panes[1],n,32)
                local indent=18+depth*10
                ItemRow(row,node.itemID,indent)
                row.label:SetWidth(math.max(60,self.panes[1].content:GetWidth()-indent-105))
                row.label:SetText((node.chooseCraft and "|cff00ffff" or "|cffffffff")..node.name.."|r")
                row.quantity:ClearAllPoints(); row.quantity:SetPoint("RIGHT",row,"RIGHT",-66,0)
                row.quantity:SetText(tostring(node.qty)); row.quantity:Show()
                if depth>0 then
                    row.guide:ClearAllPoints(); row.guide:SetPoint("TOPLEFT",indent-8,0); row.guide:SetSize(1,32); row.guide:Show()
                end
                if self.selectedNodeID==node.itemID then selectedNode=node; Highlight(row) end
                row:SetScript("OnClick",function(_, button)
                    self.selectedNodeID=node.itemID; self:Refresh()
                    if button=="RightButton" and not self.history then
                        local menu=CreateFrame("Frame",nil,UIParent,"UIDropDownMenuTemplate")
                        UIDropDownMenu_Initialize(menu,function(_,level)
                            local hdr=UIDropDownMenu_CreateInfo(); hdr.text=node.name; hdr.isTitle=true; hdr.notCheckable=true; UIDropDownMenu_AddButton(hdr,level)
                            for _,method in ipairs(node.canCraft and {"Buy","Craft","Provide"} or {"Buy","Provide"}) do
                                local info=UIDropDownMenu_CreateInfo(); info.text="Set to: "..method; info.notCheckable=true; info.func=function()
                                    self.choices[node.itemID]=method=="Craft"; self.selectedBuys[node.itemID]=method~="Provide"; self.dirty=true; self:Refresh()
                                end; UIDropDownMenu_AddButton(info,level)
                            end
                            if MarketSync.SearchInAuctionHouse then
                                local ah=UIDropDownMenu_CreateInfo(); ah.text="Search in Auction House"; ah.notCheckable=true; ah.func=function() MarketSync.SearchInAuctionHouse(node.name or node.itemID) end; UIDropDownMenu_AddButton(ah,level)
                            end
                        end,"MENU"); ToggleDropDownMenu(1,nil,menu,row,0,0)
                    end
                end)
                local children=node.chooseCraft and node.subMats and #node.subMats>0
                if children then
                    row.expand:ClearAllPoints(); row.expand:SetPoint("LEFT",row,"LEFT",indent-17,0)
                    row.expand:SetText(self.expanded[path]==false and "+" or "-"); row.expand:Show()
                    row.expand:SetScript("OnClick",function() self.expanded[path]=self.expanded[path]==false; self:Refresh() end)
                end
                if not self.history then
                    row.action:ClearAllPoints(); row.action:SetPoint("RIGHT",row,"RIGHT",-2,0); row.action:SetSize(60,20)
                    row.action:SetText(node.chooseCraft and "Craft v" or (self.selectedBuys[node.itemID]==false and "Provide v" or "Buy v")); row.action:Show()
                    row.action:SetScript("OnClick",function()
                        local menu=CreateFrame("Frame",nil,UIParent,"UIDropDownMenuTemplate")
                        UIDropDownMenu_Initialize(menu,function(_,level)
                            for _,method in ipairs(node.canCraft and {"Buy","Craft","Provide"} or {"Buy","Provide"}) do
                                local info=UIDropDownMenu_CreateInfo(); info.text=method; info.func=function()
                                    self.choices[node.itemID]=method=="Craft"; self.selectedBuys[node.itemID]=method~="Provide"; self.dirty=true; self:Refresh()
                                end; UIDropDownMenu_AddButton(info,level)
                            end
                        end); ToggleDropDownMenu(1,nil,menu,row.action,0,0)
                    end)
                end
                if children and self.expanded[path]~=false then Walk(node.subMats,depth+1,path) end
            end
        end
        if self.recipe then
            n=1; local root=Row(self.panes[1],n,32)
            ItemRow(root,outputID,18); root.label:SetWidth(self.panes[1].content:GetWidth()-54)
            root.label:SetText("|cff00ffff"..(self.recipe.name or "Craft").." x"..(cost and cost.outputQty or self.quantity or 1).."|r")
            root.expand:SetText(self.expanded.root==false and "+" or "-"); root.expand:Show()
            root.expand:SetScript("OnClick",function() self.expanded.root=self.expanded.root==false; self:Refresh() end)
            root:SetScript("OnClick",function() self.selectedNodeID=outputID; self:Refresh() end)
            if self.selectedNodeID==outputID then Highlight(root) end
            if self.expanded.root~=false then Walk(cost and cost.reagentsTree,0,"root") end
        end
        self.panes[1].content:SetHeight(math.max(1,n*32))
        local middle=self.panes[2]; local m=0
        local function Line(text,click,itemID)
            m=m+1; local row=Row(middle,m,36)
            if itemID then ItemRow(row,itemID,4) end
            row.label:SetText(text); row:SetScript("OnClick",click)
        end
        if job and job.status~="Shopping" and not self.dirty then
            middle.heading:SetText("|cffffd700Recorded costs|r")
            for id,purchase in pairs(job.purchased) do Line(Name(id).." x"..purchase.qty.."\nPaid: "..Money(purchase.paid),nil,id) end
            local totals=L.Totals(job)
            Line("Total materials paid: "..Money(totals.paid))
            if totals.unknownCost then Line("Acquisition cost incomplete.\nReserve known stock or review Item Ledger.") end
            if job.kind=="service" then
                Line("Customer: "..(job.customer or "Unknown"))
                Line("Service payment: "..Money(totals.gross).."\nOwn fees/costs: "..Money(totals.fees))
                Line("Deposits held: "..Money(totals.deposits).."\nDelivered: "..(totals.delivered or 0).." / "..job.craftedQty)
                Line("Customer materials and returned items\nare excluded from sales revenue.")
            end
            local profit=MarketSync.CalculateRecipeProfit(job.recipe,job.choices,job.quantity)
            if job.kind~="service" and profit and profit.outputPrice and profit.outputPrice>0 then
                Line("Current market value: "..Money(profit.grossRevenue))
                if not totals.unknownCost then Line("Estimated profit after AH cut: "..Money(profit.netRevenue-totals.paid)) end
            elseif job.kind~="service" then Line("Current market value: unavailable") end
            if job.kind~="service" then
                Line("Sold: "..totals.sold.." / "..job.outputQty.."\nSale proceeds: "..Money(totals.gross))
                Line("Sale fees: "..Money(totals.fees))
            end
            Line(totals.profit and "Realized profit: "..Money(totals.profit) or (totals.unknownCost and "Realized profit: cost incomplete" or "Actual sale: Not sold"))
            for _,sale in ipairs(job.sales) do
                Line("Sale x"..sale.qty.." · "..(date and date("%m/%d %H:%M",sale.at) or tostring(sale.at)).."\nGross "..Money(sale.gross).." · Fees "..Money(sale.fees))
            end
            if next(job.plan.provided) then Line("Provided materials excluded from paid cost.") end
        elseif self.recipe then
            middle.heading:SetText("|cffffd700Purchase plan|r")
            local plan=MarketSync.BuildCraftPurchasePlan({recipe=self.recipe,quantity=self.quantity,choices=self.choices,selectedBuys=self.selectedBuys})
            local buys=job and not self.dirty and L.Remaining(job) or plan.buys
            local order={}; for id in pairs(buys) do order[#order+1]=id end
            table.sort(order,function(a,b) return Name(a)<Name(b) end)
            local estimate=0
            for _,id in ipairs(order) do
                local buy=buys[id]; estimate=estimate+(buy.unitPrice or 0)*buy.qty
                Line(Name(id).." x"..buy.qty.."\nEstimate: "..Money((buy.unitPrice or 0)*buy.qty),function(_, button)
                    if button=="RightButton" then
                        local menu=CreateFrame("Frame",nil,UIParent,"UIDropDownMenuTemplate")
                        UIDropDownMenu_Initialize(menu,function(_,level)
                            local hdr=UIDropDownMenu_CreateInfo(); hdr.text=Name(id).." x"..buy.qty; hdr.isTitle=true; hdr.notCheckable=true; UIDropDownMenu_AddButton(hdr,level)
                            if job and not self.dirty then
                                local rec=UIDropDownMenu_CreateInfo(); rec.text="Record Purchase..."; rec.notCheckable=true; rec.func=function() MarketSync.PromptCraftPurchase(job.id,id) end; UIDropDownMenu_AddButton(rec,level)
                            end
                            if MarketSync.SearchInAuctionHouse then
                                local ah=UIDropDownMenu_CreateInfo(); ah.text="Search in Auction House"; ah.notCheckable=true; ah.func=function() MarketSync.SearchInAuctionHouse(Name(id) or id) end; UIDropDownMenu_AddButton(ah,level)
                            end
                        end,"MENU"); ToggleDropDownMenu(1,nil,menu,middle,0,0)
                        return
                    end
                    if not job or self.dirty then Report(false,"Save the craft before recording purchases."); return end
                    MarketSync.PromptCraftPurchase(job.id,id)
                end,id)
                if MarketSync.ItemLedger then
                    for _, h in ipairs(MarketSync.ItemLedger.Holdings(id)) do
                        if h.owner~=MarketSync.ItemLedger.Owner() and MarketSyncDB.ShowItemsOnOtherCharacters~=false then
                            Line(h.owner..": "..h.qty.." ("..h.storage..")\nTransfer required · last recorded")
                        end
                    end
                end
            end
            Line("|cffffd700Estimated buy cost: "..Money(estimate).."|r")
            Line("Click a material to record a purchase.\nNative AH purchases are recorded on confirmation.")
            if job then Line("Recorded spending: "..Money(L.Totals(job).paid)) end
        end
        if selectedNode then
            Line("|cffffd700Selected: "..selectedNode.name.."|r",nil,selectedNode.itemID)
            Line("Buy: "..Money(selectedNode.directTotalPrice))
            if selectedNode.canCraft then Line("Craft: "..Money(selectedNode.craftTotalPrice)) end
        end
        middle.content:SetHeight(math.max(1,m*36))
        self.panes[3].heading:SetText(self.history and "|cffffd700Craft History|r" or "|cffffd700Craft Management|r")
        local jobs=L.List(self.history)
        for i,entry in ipairs(jobs) do
            local row=Row(self.panes[3],i,32)
            ItemRow(row,entry.itemID,4)
            local totals=L.Totals(entry)
            local status=entry.status=="Crafted" and (totals.sold>=entry.outputQty and "Sold" or totals.sold>0 and "Part sold" or "Crafted") or entry.status
            if entry.kind=="service" and entry.status=="Crafted" then
                status=(totals.delivered or 0)>=entry.outputQty and "Returned" or (totals.delivered or 0)>0 and "Part returned" or "Awaiting return"
            end
            row.label:SetText("|cff00ffff"..entry.name.."|r")
            row.label:SetWidth(math.max(50,self.panes[3].content:GetWidth()-120))
            row.quantity:ClearAllPoints(); row.quantity:SetPoint("RIGHT",row,"RIGHT",-74,0)
            row.quantity:SetText(tostring(entry.quantity)); row.quantity:Show()
            row.status:ClearAllPoints(); row.status:SetPoint("RIGHT",row,"RIGHT",-4,0)
            row.status:SetText((entry.status=="Shopping" and "|cffffd700" or "|cff55ff88")..status.."|r"); row.status:Show()
            if entry.id==self.jobID then Highlight(row) end
            row:SetScript("OnClick",function(_,button)
                if self.dirty and self.jobID==entry.id then return end
                if self.dirty and self.jobID~=entry.id then
                    DiscardOrRun(self,function() Select(entry) end); return
                end
                Select(entry)
                if button=="RightButton" then
                    local menu=CreateFrame("Frame",nil,UIParent,"UIDropDownMenuTemplate")
                    UIDropDownMenu_Initialize(menu,function(_,level)
                        local info=UIDropDownMenu_CreateInfo(); info.text=entry.status=="Crafted" and "View recorded costs" or "View materials"; info.notCheckable=true; info.func=function() Select(entry) end; UIDropDownMenu_AddButton(info,level)
                        if entry.shoppingName then local shopping=UIDropDownMenu_CreateInfo(); shopping.text="Open Shopping"; shopping.notCheckable=true; shopping.func=function() OpenShopping(entry) end; UIDropDownMenu_AddButton(shopping,level) end
                        local ledgerItem = UIDropDownMenu_CreateInfo()
                        if MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled() then
                            ledgerItem.text = "Open Item Ledger"
                            ledgerItem.notCheckable = true
                            ledgerItem.func = function() if MarketSync.OpenItemLedger then MarketSync.OpenItemLedger(entry.id) end end
                        else
                            ledgerItem.text = "|cff888888Open Item Ledger (Disabled)|r"
                            ledgerItem.disabled = true
                            ledgerItem.notCheckable = true
                        end
                        UIDropDownMenu_AddButton(ledgerItem, level)
                        if entry.status=="Purchased" then
                            local comp=UIDropDownMenu_CreateInfo(); comp.text="|cff55ff88Confirm: Mark Crafted|r"; comp.notCheckable=true; comp.func=function() Report(L.Complete(entry.id)); if L.Get(entry.id) and L.Get(entry.id).status=="Crafted" then self.history=true end; self:Refresh() end; UIDropDownMenu_AddButton(comp,level)
                        end
                        if entry.status=="Crafted" and entry.itemID and entry.kind~="service" then
                            local sale=UIDropDownMenu_CreateInfo(); sale.text="|cffffd700Record Sale...|r"; sale.notCheckable=true; sale.func=function() self.saleButton:GetScript("OnClick")(self.saleButton) end; UIDropDownMenu_AddButton(sale,level)
                        end
                        local cust=UIDropDownMenu_CreateInfo(); cust.text="Set Customer Craft..."; cust.notCheckable=true; cust.func=function()
                            Prompt("MARKETSYNC_CRAFT_CUSTOMER","Customer character name for this supplied-material craft",function(text)
                                Report(L.SetService(entry.id,text)); self:Refresh()
                            end)
                        end; UIDropDownMenu_AddButton(cust,level)
                        local rem=UIDropDownMenu_CreateInfo(); rem.text="|cffff5555Remove Craft...|r"; rem.notCheckable=true; rem.func=function() self.removeButton:GetScript("OnClick")(self.removeButton) end; UIDropDownMenu_AddButton(rem,level)
                    end); ToggleDropDownMenu(1,nil,menu,row,0,0)
                end
            end)
        end
        self.panes[3].content:SetHeight(math.max(1,#jobs*32))
        if tab1 and tab2 then
            if PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
                if self.history then
                    PanelTemplates_DeselectTab(tab1)
                    PanelTemplates_SelectTab(tab2)
                else
                    PanelTemplates_SelectTab(tab1)
                    PanelTemplates_DeselectTab(tab2)
                end
            elseif PanelTemplates_SetTab then
                PanelTemplates_SetTab(self, self.history and 2 or 1)
            end
        end
        if self.UpdateLedgerButtonState then self:UpdateLedgerButtonState() end
        if MarketSync.Theme then MarketSync.Theme.Apply(self) end
    end
    f:HookScript("OnShow", function()
        if f.UpdateLedgerButtonState then f.UpdateLedgerButtonState() end
    end)
    f.UpdateLedgerButtonState()
    local refreshQueued = false
    local function SafeRefresh()
        refreshQueued = false
        if f and f:IsShown() then
            local job=f.jobID and L.Get(f.jobID)
            if job and job.status=="Crafted" then f.history=true end
            f:Refresh()
        end
    end
    L.Refresh=function()
        if f and f:IsShown() then
            if not refreshQueued then
                refreshQueued = true
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, SafeRefresh)
                else
                    SafeRefresh()
                end
            end
        end
    end
    return f
end
function MarketSync.OpenCraftingTree(recipeOrItemID, anchor, saved)
    local f=Create()
    if f.dirty and (recipeOrItemID or (saved and saved.ledgerID)) then
        if saved and saved.ledgerID==f.jobID then f:Show(); return end
        DiscardOrRun(f,function() MarketSync.OpenCraftingTree(recipeOrItemID,anchor,saved) end)
        return
    end
    local recipe=type(recipeOrItemID)=="table" and recipeOrItemID or (recipeOrItemID and MarketSync.GetRecipeForOutput(recipeOrItemID))
    if saved and saved.ledgerID and L.Get(saved.ledgerID) then
        f.history=L.Get(saved.ledgerID).status=="Crafted"; Select(L.Get(saved.ledgerID))
    elseif recipe then
        f.jobID=nil; f.history=false; f.recipe=recipe
        f.quantity=saved and (saved.quantities or {})[recipe.outputItemID] or 1
        f.choices=Copy(saved and saved.choices); f.selectedBuys=Copy(saved and saved.selectedBuys); f.dirty=false
        f.expanded={}; f.selectedNodeID=tonumber(recipe.outputItemID)
    end
    if MarketSync.ShowWorkspaceWindow then MarketSync.ShowWorkspaceWindow(f) else f:Show() end
    f:Refresh()
end
