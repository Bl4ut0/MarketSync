-- Visual activity & stock ledger (Design C: Progressive Hybrid).
-- Classification and FIFO cost accounting stay in ItemLedger.
local I = MarketSync.ItemLedger
local window

local function Color(role)
    if MarketSync.GetThemeColor then return MarketSync.GetThemeColor(role) end
    return .10, .09, .08, .98
end

local function Money(copper)
    copper = math.floor(copper or 0)
    return (copper < 0 and "-" or "") .. (MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(math.abs(copper)) or math.abs(copper) .. "c")
end

local function Label(parent, x, y, width, text, font)
    local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", x, y)
    t:SetWidth(width)
    t:SetJustifyH("LEFT")
    t:SetText(text or "")
    return t
end

local function Button(parent, x, y, width, text, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function Panel(parent, x, y, w, h)
    if MarketSync.CreateModernInset then
        return MarketSync.CreateModernInset(parent, x, y, w, h)
    end
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetPoint("TOPLEFT", x, y)
    p:SetSize(w, h)
    p:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(Color("inset"))
    p:SetBackdropBorderColor(Color("border"))
    return p
end

local function Prompt(text, fn)
    StaticPopupDialogs.MARKETSYNC_LEDGER_ENTRY = {
        text = text,
        button1 = "Apply",
        button2 = "Cancel",
        hasEditBox = true,
        timeout = 0,
        hideOnEscape = true,
        OnAccept = function(p)
            local box = p.editBox or p.EditBox
            if box then fn(box:GetText()) end
        end
    }
    StaticPopup_Show("MARKETSYNC_LEDGER_ENTRY")
end

local function Report(ok, reason)
    if not ok then
        print("|cffff5555[MarketSync]|r " .. (reason or "This action needs a matching transaction and saved craft."))
    end
end

local function ItemName(item)
    return (MarketSync.GetItemInfo and MarketSync.GetItemInfo(item.itemID)) or "Item " .. tostring(item.itemID)
end

local titles = {
    ['auction purchase'] = 'Auction purchase',
    ['opening inventory'] = 'Starting inventory',
    ['inventory observation'] = 'Inventory changed',
    ['unattributed inventory'] = 'Item origin unknown',
    ['crafted output'] = 'Craft completed',
    ['mail sent'] = 'Mail sent',
    ['mail collected'] = 'Mail collected',
    ['trade'] = 'Player trade',
    ['trade completed'] = 'Player trade',
    ['vendor purchase'] = 'Vendor purchase',
    ['vendor sale'] = 'Vendor sale',
}

local function Title(tx)
    return titles[tx.kind] or (tx.kind:gsub('^%l', string.upper))
end

local function NeedsReview(tx)
    return tx.state == 'unresolved' or tx.metadata.custodyPending or (tx.classification == 'unassigned' and tx.kind == 'trade')
end

local function Status(tx)
    if NeedsReview(tx) then return '|cffffbb44Needs review|r' end
    if tx.serviceID or tx.transferID or tx.saleJobID or tx.classification ~= 'unassigned' then return '|cff77ddbbLinked|r' end
    if tx.state == 'reconciled' then return '|cff77ddbbMatched|r' end
    return '|cff91c9ffRecorded|r'
end

local function DirectionInfo(tx)
    local hasIn = #tx.incoming > 0 or (tx.cashIn or 0) > 0
    local hasOut = #tx.outgoing > 0 or (tx.cashOut or 0) > 0
    for _, qty in pairs(tx.metadata.unresolved or tx.metadata.delta or {}) do
        if qty > 0 then hasIn = true elseif qty < 0 then hasOut = true end
    end
    if hasIn and hasOut then
        return "both", "|cff66bbff[⇄]|r "
    elseif hasIn then
        return "in", "|cff00ff00[+IN]|r "
    elseif hasOut then
        return "out", "|cffff6666[-OUT]|r "
    end
    return "neutral", "|cffaaaaaa[•]|r "
end

local function FirstItem(tx)
    if tx.incoming[1] then
        return { itemID = tx.incoming[1].itemID, qty = tx.incoming[1].qty, dir = "in" }
    end
    if tx.outgoing[1] then
        return { itemID = tx.outgoing[1].itemID, qty = tx.outgoing[1].qty, dir = "out" }
    end
    for key, qty in pairs(tx.metadata.unresolved or tx.metadata.delta or {}) do
        local id = tonumber(tostring(key):match('^(%d+)'))
        if id and qty ~= 0 then
            return { itemID = id, qty = math.abs(qty), dir = qty > 0 and "in" or "out" }
        end
    end
end

local function SetIcon(button, item)
    button.itemID = item and item.itemID
    local icon = item and MarketSync.GetItemIcon and MarketSync.GetItemIcon(item.itemID)
    if not icon and item and MarketSync.GetItemInfo then
        icon = select(10, MarketSync.GetItemInfo(item.itemID))
    end
    button.texture:SetTexture(icon or (item and "Interface\\Icons\\INV_Misc_QuestionMark" or "Interface\\Icons\\INV_Misc_Coin_01"))
end

local function Icon(parent, x, y, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetPoint("TOPLEFT", x, y)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAllPoints(b)
    b:SetScript("OnEnter", function(self)
        if not self.itemID or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(self.itemID)
        else
            GameTooltip:SetHyperlink("item:" .. self.itemID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local filters = {
    { 'all', 'All activity' },
    { 'review', 'Needs review' },
    { 'purchases', 'Purchases' },
    { 'crafts', 'Crafts & sales' },
    { 'transfers', 'Mail & trades' },
    { 'customer', 'Customer crafts' }
}

local flowFilters = {
    { 'all', 'Flow: In & Out' },
    { 'in', 'Flow: +In Only' },
    { 'out', 'Flow: -Out Only' },
}

local function Matches(tx, f)
    local k = tx.kind
    if f.filter == 'review' and not NeedsReview(tx) then return false end
    if f.filter == 'purchases' and k ~= 'auction purchase' and k ~= 'vendor purchase' then return false end
    if f.filter == 'crafts' and k ~= 'crafted output' and not tx.saleJobID and not (tx.metadata.invoice and tx.metadata.invoice.kind == 'seller') then return false end
    if f.filter == 'transfers' and not k:find('mail', 1, true) and not k:find('trade', 1, true) then return false end
    if f.filter == 'customer' and not tx.serviceID and not tx.metadata.customerJob then return false end

    if f.flowFilter and f.flowFilter ~= 'all' then
        local dir = DirectionInfo(tx)
        if f.flowFilter == 'in' and dir ~= 'in' and dir ~= 'both' then return false end
        if f.flowFilter == 'out' and dir ~= 'out' and dir ~= 'both' then return false end
    end

    local query = (f.searchText or ''):lower()
    if query == '' then return true end
    local id = tonumber(query) or tonumber(query:match('item:(%d+)'))
    local names = { Title(tx), tx.counterparty or '', tx.classification }
    for _, list in ipairs({ tx.incoming, tx.outgoing }) do
        for _, item in ipairs(list) do
            if id and id == item.itemID then return true end
            names[#names + 1] = ItemName(item)
        end
    end
    local first = FirstItem(tx)
    if first then
        if id and id == first.itemID then return true end
        names[#names + 1] = ItemName(first)
    end
    for key in pairs(tx.metadata.unresolved or tx.metadata.delta or {}) do
        local itemID = tonumber(tostring(key):match('^(%d+)'))
        if itemID then
            if id == itemID then return true end
            names[#names + 1] = ItemName({ itemID = itemID })
        end
    end
    return not id and table.concat(names, ' '):lower():find(query, 1, true) ~= nil
end

local function CollectCatalogItems(searchText)
    local store = I.Store and I.Store()
    if not store then return {} end
    local map = {}
    local function Ensure(itemID)
        itemID = tonumber(itemID)
        if not itemID or itemID <= 0 then return nil end
        if not map[itemID] then
            map[itemID] = { itemID = itemID, total = 0, byOwner = {}, paid = 0, costUnits = 0, reserved = 0 }
        end
        return map[itemID]
    end
    local partition = I.Partition and I.Partition()
    for _, character in pairs(store.characters or {}) do
        if not partition or character.partition == partition then
            local short = tostring(character.owner or character.name or "Player"):match("^([^%-]+)") or "Player"
            for _, snap in pairs(character.storage or {}) do
                for key, item in pairs(snap.items or {}) do
                    local id = item.itemID or tonumber(tostring(key):match("^(%d+)"))
                    local entry = Ensure(id)
                    if entry and (item.qty or 0) > 0 then
                        entry.total = entry.total + item.qty
                        entry.byOwner[short] = (entry.byOwner[short] or 0) + item.qty
                    end
                end
            end
        end
    end
    for _, lot in ipairs(store.lots or {}) do
        if (not partition or lot.partition == partition) and (lot.qty or 0) > 0 then
            local entry = Ensure(lot.itemID)
            if entry and lot.unitCost then
                entry.paid = entry.paid + (lot.unitCost * lot.qty)
                entry.costUnits = entry.costUnits + lot.qty
            end
        end
    end
    for _, res in pairs(store.reservations or {}) do
        if (not partition or res.partition == partition) and (res.qty or 0) > 0 then
            local id = tonumber(tostring(res.key):match("^(%d+)"))
            local entry = Ensure(id)
            if entry then entry.reserved = entry.reserved + res.qty end
        end
    end

    local query = (searchText or ""):lower()
    local queryID = tonumber(query) or tonumber(query:match("item:(%d+)"))
    local out = {}
    for _, entry in pairs(map) do
        if entry.total > 0 or entry.reserved > 0 then
            local name = ItemName(entry)
            entry.name = name
            if query == "" or (queryID and queryID == entry.itemID) or name:lower():find(query, 1, true) then
                out[#out + 1] = entry
            end
        end
    end
    table.sort(out, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

function MarketSync.OpenItemLedger(jobID)
    if MarketSync.IsLedgerEnabled and not MarketSync.IsLedgerEnabled() then
        return nil
    end
    local craft = MarketSyncCraftManager
    if craft and craft:IsShown() and craft.dirty and craft.ConfirmContextSwitch then
        craft.ConfirmContextSwitch(function() MarketSync.OpenItemLedger(jobID or craft.jobID) end)
        return
    end
    if not window then
        local f = CreateFrame("Frame", "MarketSyncItemLedger", UIParent, "BackdropTemplate")
        window = f
        f:SetSize(1060, 660)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(Color("dialog"))
        f:SetBackdropBorderColor(Color("border"))
        if MarketSync.Theme and MarketSync.Theme.DecorateWarcraftWindow then
            MarketSync.Theme.DecorateWarcraftWindow(f, "Interface\\Icons\\INV_Misc_Coin_01", "|cffffd100Inventory & Craft Ledger |cffff8800[Beta]|r|r")
        end

        f.context = Label(f, 60, -36, 760)

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() f:Hide() end)
        f.CloseButton = close

        Button(f, 896, -14, 126, "|TInterface\\Icons\\Trade_BlackSmithing:13:13:0:0|t Craft Manager", function()
            if MarketSync.OpenCraftManager then MarketSync.OpenCraftManager(f.jobID) end
        end)

        local betaToggleBtn = Button(f, 756, -14, 134, "", function()
            if MarketSync.SetLedgerEnabled and MarketSync.IsLedgerEnabled then
                MarketSync.SetLedgerEnabled(not MarketSync.IsLedgerEnabled())
            end
        end)
        f.betaToggleBtn = betaToggleBtn

        -- Beta notice banner shown when transactional tracking is disabled
        local betaNotice = Panel(f, 18, -68, 1024, 52)
        Label(betaNotice, 16, -8, 800, "|cffffaa00Transactional Item Ledger is currently disabled (Beta Feature)|r")
        Label(betaNotice, 16, -26, 800, "Lightweight inventory observation is active for tooltips. Enable the Beta to record purchases/sales, trade, mail, and FIFO material costs.")
        Button(betaNotice, 836, -14, 172, "|cff00ff00Enable Ledger Beta|r", function()
            if MarketSync.SetLedgerEnabled then MarketSync.SetLedgerEnabled(true) end
        end)
        f.betaNotice = betaNotice

        -- 4 KPI Summary Cards (with Warcraft Icon Badges)
        local cardIcons = {
            "Interface\\MoneyFrame\\UI-GoldIcon",
            "Interface\\Icons\\INV_Misc_Coin_02",
            "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
            "Interface\\Icons\\INV_Misc_Bag_10_Blue",
        }
        f.cards = {}
        for n = 1, 4 do
            local card = Panel(f, 18 + (n - 1) * 258, -68, 250, 52)
            local badge = card:CreateTexture(nil, "ARTWORK")
            if badge and badge.SetSize then
                badge:SetSize(22, 22)
                badge:SetPoint("TOPLEFT", 10, -15)
                badge:SetTexture(cardIcons[n])
                card.badge = badge
            end
            card.title = Label(card, 38, -8, 204)
            card.value = Label(card, 38, -27, 204, nil, "GameFontNormal")
            f.cards[n] = card
        end

        f.viewMode = 'activity'
        f.filter = 'all'
        f.flowFilter = 'all'
        f.page = 0
        f.actions = {}
        f.detailRows = {}

        -- View Mode Tabs (Design C: Progressive Hybrid with Icons)
        f.viewTabs = {}
        local tabSpecs = {
            { 'activity', '|TInterface\\Icons\\INV_Misc_Coin_01:13:13:0:0|t In / Out Activity', 152 },
            { 'stock', '|TInterface\\Icons\\INV_Misc_Bag_08:13:13:0:0|t Character Stock & Lots', 176 },
            { 'review', '|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:13:13:0:0|t Needs Review', 128 },
        }
        local tabX = 18
        for idx, spec in ipairs(tabSpecs) do
            local btn = Button(f, tabX, -130, spec[3], spec[2], function()
                if spec[1] == 'review' then
                    f.viewMode = 'activity'
                    f.filter = 'review'
                    if f.filterButton then f.filterButton:SetText('Needs review v') end
                elseif spec[1] == 'stock' then
                    f.viewMode = 'stock'
                else
                    f.viewMode = 'activity'
                    if f.filter == 'review' then
                        f.filter = 'all'
                        if f.filterButton then f.filterButton:SetText('All activity v') end
                    end
                end
                f.page = 0
                f:Refresh()
            end)
            f.viewTabs[idx] = btn
            tabX = tabX + spec[3] + 6
        end

        -- Search Box
        local query = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.query = query
        query:SetSize(184, 24)
        query:SetPoint("TOPLEFT", 482, -130)
        query:SetAutoFocus(false)
        query:SetMaxLetters(80)
        query:SetScript("OnTextChanged", function(self)
            f.searchText = self:GetText()
            f.page = 0
            if f.Refresh then f:Refresh() end
        end)
        query:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        query:SetScript("OnEnterPressed", function(self) self:ClearFocus(); f:Refresh() end)
        query:SetText("")
        if MarketSync.RegisterLinkAwareEditBox then MarketSync.RegisterLinkAwareEditBox(query) end
        Label(f, 482, -158, 200, "Search item, player, ID or link.")

        -- Category Filter Dropdown
        local filter = Button(f, 676, -130, 128, "All activity v", function(self)
            local menu = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
            UIDropDownMenu_Initialize(menu, function(_, level)
                for _, entry in ipairs(filters) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = entry[2]
                    info.checked = f.filter == entry[1]
                    info.func = function()
                        f.viewMode = 'activity'
                        f.filter = entry[1]
                        f.page = 0
                        self:SetText(entry[2] .. " v")
                        f:Refresh()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            ToggleDropDownMenu(1, nil, menu, self, 0, 0)
        end)
        f.filterButton = filter

        -- Direction Flow Filter (In / Out)
        local flowBtn = Button(f, 810, -130, 114, "Flow: In & Out v", function(self)
            local menu = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
            UIDropDownMenu_Initialize(menu, function(_, level)
                for _, entry in ipairs(flowFilters) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = entry[2]
                    info.checked = f.flowFilter == entry[1]
                    info.func = function()
                        f.viewMode = 'activity'
                        f.flowFilter = entry[1]
                        f.page = 0
                        self:SetText(entry[2] .. " v")
                        f:Refresh()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            ToggleDropDownMenu(1, nil, menu, self, 0, 0)
        end)
        f.flowButton = flowBtn

        -- Refresh Storage Button
        Button(f, 930, -130, 112, "Refresh storage", function()
            local t = MarketSync.InventoryTracking
            if t then t.CaptureBags(); t.CaptureBank(); t.CaptureMail() end
            if I.SeedObservedStock then I.SeedObservedStock() end
            f:Refresh()
        end)

        -- Card 3 Click -> Filter to Needs Review
        f.cards[3]:EnableMouse(true)
        f.cards[3]:SetScript("OnMouseUp", function()
            f.viewMode = 'activity'
            f.filter = 'review'
            f.page = 0
            filter:SetText('Needs review v')
            f:Refresh()
        end)

        -- Card 4 Click -> Toggle Stock View
        f.cards[4]:EnableMouse(true)
        f.cards[4]:SetScript("OnMouseUp", function()
            f.viewMode = (f.viewMode == 'stock') and 'activity' or 'stock'
            f.page = 0
            f:Refresh()
        end)

        -- Pagination Controls
        f.pageLabel = Label(f, 750, -162, 130)
        f.newer = Button(f, 888, -158, 72, "Newer", function() f.page = math.max(0, f.page - 1); f:Refresh() end)
        f.older = Button(f, 968, -158, 72, "Older", function() f.page = f.page + 1; f:Refresh() end)

        -- Left Pane: Scannable In/Out Stream OR Stock Browser
        local listPanel = Panel(f, 18, -186, 404, 372)
        if MarketSync.CreateAHColumnHeader then
            local lh = MarketSync.CreateAHColumnHeader(listPanel, 402, 22, "|cffffd700In / Out Activity Stream  (Right-Click Row for Menu)|r")
            lh:SetPoint("TOPLEFT", 1, -1)
            f.listHeading = lh.label or lh
        else
            f.listHeading = Label(listPanel, 12, -9, 376, "|cffffd700In / Out Activity Stream|r", "GameFontNormal")
        end
        local scroll = CreateFrame("ScrollFrame", nil, listPanel, "UIPanelScrollFrameTemplate")
        f.activityScroll = scroll
        scroll:SetPoint("TOPLEFT", 6, -32)
        scroll:SetPoint("BOTTOMRIGHT", -24, 8)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(370, 1)
        scroll:SetScrollChild(content)
        f.rows = {}

        -- Right Pane: Contextual Inspector & Item Flow Drawer
        local right = Panel(f, 432, -186, 610, 372)
        if MarketSync.CreateAHColumnHeader then
            local dh = MarketSync.CreateAHColumnHeader(right, 608, 22, "|cffffd700Transaction & Item Flow Inspector|r")
            dh:SetPoint("TOPLEFT", 1, -1)
            f.detailHeading = dh.label or dh
        else
            f.detailHeading = Label(right, 12, -9, 570, "|cffffd700Transaction & Item Flow Inspector|r", "GameFontNormal")
        end
        local detailsScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
        f.detailsScroll = detailsScroll
        detailsScroll:SetPoint("TOPLEFT", 8, -34)
        detailsScroll:SetPoint("BOTTOMRIGHT", -24, 8)
        local details = CreateFrame("Frame", nil, detailsScroll)
        details:SetSize(576, 1)
        detailsScroll:SetScrollChild(details)

        -- Contextual Action Definitions
        local friendly = {
            ['Output returned'] = 'Deliver crafted item',
            ['Own expense'] = 'Crafting expense',
            ['Outgoing: own stock'] = 'Use my own stock',
            ['Correct'] = 'Correct craft records',
            ['Link own-character mail'] = 'Match a character transfer'
        }
        local function Action(group, name, fn)
            if group ~= 'window' then
                f.actions[#f.actions + 1] = { group = group, name = friendly[name] or name, original = name, run = fn }
            end
        end
        local function Link(role)
            local ok, reason = I.LinkService(f.selected, f.jobID, role)
            Report(ok, reason)
            f:Refresh()
        end
        Action("customer", "Customer materials", function()
            local tx = I.Get(f.selected)
            Link(tx and #tx.incoming > 0 and "materials" or "materialsReturn")
        end)
        Action("customer", "Output returned", function() Link("delivery") end)
        Action("customer", "Service payment", function() Link("payment") end)
        Action("customer", "Own expense", function() Link("expense") end)
        Action("customer", "Deposit", function() Link("deposit") end)
        Action("customer", "Refund", function()
            StaticPopupDialogs.MARKETSYNC_LEDGER_REFUND = {
                text = "Classify this outgoing gold: returned deposit or refunded earned payment?",
                button1 = "Deposit refund",
                button2 = "Earned refund",
                button3 = "Cancel",
                timeout = 0,
                hideOnEscape = true,
                OnAccept = function() Link("refund") end,
                OnCancel = function(_, reason) if reason == "clicked" then Link("earnedRefund") end end
            }
            StaticPopup_Show("MARKETSYNC_LEDGER_REFUND")
        end)
        Action("inventory", "Set actual cost", function()
            local selected = f.selected
            Prompt("Actual acquisition cost for this intact single-item lot, in gold. Unknown is not zero.", function(text)
                local gold = tonumber(text)
                if gold and gold >= 0 then
                    local ok, reason = (I.ResolveRecord and I.ResolveRecord(selected, "set_cost", math.floor(gold * 10000 + 0.5)))
                        or I.SetCost(selected, math.floor(gold * 10000 + 0.5))
                    Report(ok, reason)
                else
                    Report(false, "Enter a non-negative gold value (e.g. 0 or 1.5).")
                end
                f:Refresh()
            end)
        end)
        Action("inventory", "Mark Self-Found / 0g", function()
            if I.ResolveRecord then
                Report(I.ResolveRecord(f.selected, "set_cost", 0))
            else
                Report(I.SetCost(f.selected, 0))
            end
            f:Refresh()
        end)
        Action("inventory", "Mark Reviewed (Keep Unknown)", function()
            if I.ResolveRecord then
                Report(I.ResolveRecord(f.selected, "acknowledge"))
            end
            f:Refresh()
        end)
        Action("inventory", "Acknowledge All Bag Changes", function()
            if I.ResolveAllObservations then
                local n = I.ResolveAllObservations()
                print("|cff00ff00[MarketSync]|r Acknowledged " .. n .. " unresolved storage/bag observation(s).")
            end
            f:Refresh()
        end)
        Action("inventory", "Link own-character mail", function()
            local selected = f.selected
            Prompt("Enter the transaction ID for the other character's matching receipt. Select the outgoing transaction first.", function(text)
                Report(I.LinkTransfer(selected, tonumber(text)))
                f:Refresh()
            end)
        end)
        Action("craft", "Reserve own stock", function()
            local job = f.jobID and MarketSync.CraftLedger.Get(f.jobID)
            if not job then Report(false, "Open this ledger from a saved craft first."); return end
            Prompt("Provide material: item ID,quantity (e.g. 123,4). Uses observed stock and its known cost; save Provide decisions first.", function(text)
                local id, qty = text:match("^%s*(%d+)%s*,%s*(%d+)%s*$")
                id, qty = tonumber(id), tonumber(qty)
                local requirement = id and (job.plan.provided or {})[id]
                if not requirement or qty ~= requirement.qty then
                    Report(false, "Reserve the saved Provide quantity for this material.")
                    return
                end
                Report(I.Reserve(job.id, I.Key(id), qty))
                f:Refresh()
            end)
        end)
        Action("craft", "Link sale invoice", function()
            local tx = I.Get(f.selected)
            local invoice = tx and tx.metadata.invoice
            local job = f.jobID and MarketSync.CraftLedger.Get(f.jobID)
            if not job or job.kind == "service" or not invoice or invoice.kind ~= "seller" or tx.classification ~= "unassigned" then
                Report(false)
                return
            end
            local gross = invoice.bid and invoice.bid > 0 and invoice.bid or invoice.buyout
            local fee, deposit = invoice.fee or 0, invoice.deposit or 0
            if not gross or not invoice.qty or tx.cashIn ~= gross - fee + deposit then
                Report(false, "Invoice values do not match collected money; use manual sale review.")
                return
            end
            local ok = MarketSync.CraftLedger.RecordSale(job.id, invoice.qty, gross, fee, "invoice:" .. tx.id)
            if ok then tx.classification, tx.saleJobID = "sale invoice", job.id end
            Report(ok)
            f:Refresh()
        end)
        Action("inventory", "Refresh storage", function()
            local tracking = MarketSync.InventoryTracking
            if tracking then tracking.CaptureBags(); tracking.CaptureBank(); tracking.CaptureMail() end
            if I.SeedObservedStock then I.SeedObservedStock() end
            f:Refresh()
        end)
        Action("inventory", "Outgoing: own stock", function() Report(I.AttributeOwn(f.selected)); f:Refresh() end)
        Action("inventory", "Link free guild craft", function()
            local selected = f.selected
            Prompt("Enter the incoming material transaction ID to link with this outgoing delivery as a zero-cost guild craft:", function(text)
                local inID = tonumber(text)
                Report(inID and I.LinkGuildCraft and I.LinkGuildCraft(inID, selected))
                f:Refresh()
            end)
        end)
        Action("inventory", "Trim old history (30d+)", function()
            local n = I.TrimLedger and I.TrimLedger() or 0
            print("|cff00ff00[MarketSync]|r Compacted " .. n .. " older ledger records into summary rollups.")
            f:Refresh()
        end)
        Action("craft", "Correct", function()
            if not f.jobID then Report(false, "Select a craft first."); return end
            local id = f.jobID
            Prompt("Correction: crafted,total outputs OR item ID,total purchased quantity,total gold paid. Keeps an audit record.", function(text)
                local amount = text:match("^%s*crafted%s*,%s*(%d+)%s*$")
                if amount then
                    Report(MarketSync.CraftLedger.CorrectCrafted(id, tonumber(amount)))
                else
                    local item, qty, gold = text:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*([%d%.]+)%s*$")
                    item, qty, gold = tonumber(item), tonumber(qty), tonumber(gold)
                    Report(item and qty and gold and MarketSync.CraftLedger.CorrectPurchase(id, item, qty, math.floor(gold * 10000 + 0.5)))
                end
                f:Refresh()
            end)
        end)

        local function Eligible(a)
            local tx = I.Get(f.selected)
            local job = f.jobID and MarketSync.CraftLedger.Get(f.jobID)
            if a.group == 'customer' then
                if not tx or not job or job.kind ~= 'service' or tx.state ~= 'confirmed' then return false end
                if a.original == 'Customer materials' then return #tx.incoming > 0 or #tx.outgoing > 0 end
                if a.original == 'Output returned' then return #tx.outgoing > 0 end
                if a.original == 'Service payment' or a.original == 'Deposit' then return (tx.cashIn or 0) > 0 end
                return (tx.cashOut or 0) > 0
            end
            if a.original == 'Link sale invoice' then
                return tx and job and job.kind ~= 'service' and tx.metadata.invoice and tx.metadata.invoice.kind == 'seller' and tx.classification == 'unassigned'
            end
            if a.original == 'Set actual cost' or a.original == 'Mark Self-Found / 0g' then
                local lot = tx and #tx.lots == 1 and I.Lot(tx.lots[1])
                return lot and lot.qty == lot.originalQty and not lot.customerJob
            end
            if a.original == 'Mark Reviewed (Keep Unknown)' then
                return tx and NeedsReview(tx)
            end
            if a.original == 'Link own-character mail' then return tx and tx.kind == 'mail sent' end
            if a.original == 'Outgoing: own stock' then return tx and #tx.outgoing > 0 end
            if a.group == 'craft' then return job ~= nil end
            return true
        end

        Label(f, 18, -572, 1000, "|cffffd700Actions for this record|r   Choose a group below, or click any item icon to inspect its full In/Out history.")
        f.actionButtons = {}
        for n, spec in ipairs({ { 'inventory', 'Inventory & ownership' }, { 'craft', 'Craft & sales' }, { 'customer', 'Customer exchange' } }) do
            f.actionButtons[n] = Button(f, 18 + (n - 1) * 224, -596, 212, spec[2] .. " v", function(self)
                local menu = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
                UIDropDownMenu_Initialize(menu, function(_, level)
                    for _, a in ipairs(f.actions) do
                        if a.group == spec[1] then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = a.name
                            info.notCheckable = true
                            info.disabled = not Eligible(a)
                            info.func = a.run
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
                end)
                ToggleDropDownMenu(1, nil, menu, self, 0, 0)
            end)
        end
        Button(f, 904, -596, 138, "Back / Close", function() f:Hide() end)
        f.auditButton = Button(f, 704, -596, 184, "Technical details", function()
            f.expandedAudit = not f.expandedAudit
            f:Refresh()
        end)
        f.guidance = Label(f, 18, -634, 1020, "Unknown costs stay unknown. Inventory changes and transfers are never assumed to be sales.")

        local function Detail(kind, text, item, actions)
            local index = f.detailCount + 1
            f.detailCount = index
            local row = f.detailRows[index]
            if not row then
                row = CreateFrame("Frame", nil, details, "BackdropTemplate")
                row:SetWidth(568)
                row:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
                row.icon = Icon(row, 8, -8, 30)
                row.text = Label(row, 12, -10, 540)
                row.qButtons = {}
                for bIdx = 1, 3 do
                    row.qButtons[bIdx] = Button(row, 12 + (bIdx - 1) * 182, -52, 174, "", function() end)
                end
                f.detailRows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -f.detailY)
            local hasActions = actions and #actions > 0
            local rowH = hasActions and 86 or (kind == 'item' and 54 or 62)
            row:SetHeight(rowH)
            row:SetBackdropColor(Color('inset'))
            row:SetBackdropBorderColor(hasActions and 1 or Color('border'), hasActions and .72 or select(2, Color('border')), hasActions and .20 or select(3, Color('border')), 1)
            row.icon:Hide()
            for bIdx = 1, 3 do
                local qb = row.qButtons[bIdx]
                local act = hasActions and actions[bIdx]
                if act then
                    qb:SetText(act.label)
                    qb:SetScript("OnClick", act.fn)
                    qb:Show()
                else
                    qb:Hide()
                end
            end
            row.text:ClearAllPoints()
            row.text:SetPoint("TOPLEFT", 12, -10)
            row.text:SetWidth(540)
            if item then
                SetIcon(row.icon, item)
                row.icon:Show()
                row.text:ClearAllPoints()
                row.text:SetPoint("TOPLEFT", 48, -8)
                row.text:SetWidth(506)
                row.icon:SetScript("OnClick", function(self, btn)
                    f.itemID = item.itemID
                    f:Refresh()
                    if btn == "RightButton" and MarketSync.ShowItemContextMenu then
                        MarketSync.ShowItemContextMenu(self, { itemID = item.itemID, itemName = ItemName(item) })
                    end
                end)
            end
            row.text:SetText(text)
            row:Show()
            f.detailY = f.detailY + (rowH + 6)
        end

        local function RenderItemHistorySection(itemID)
            if not itemID then return end
            local iName = ItemName({ itemID = itemID })
            Detail('info', '|cffffd700Where you own ' .. iName .. '|r\nLast observed storage across characters; offline counts may be out of date.')
            local holdings = I.Holdings(itemID)
            for _, h in ipairs(holdings) do
                Detail('info', h.owner .. ' · ' .. h.qty .. ' in ' .. h.storage .. '\nUpdated ' .. math.floor(math.max(0, time() - h.at) / 60) .. ' minutes ago' .. (h.complete and '' or ' · Partial snapshot'))
            end
            if #holdings == 0 then
                Detail('info', 'No recorded storage snapshot for this item.')
            end

            -- Chronological In/Out timeline for this specific item
            local itemMovements = {}
            for _, tx in ipairs(I.List()) do
                local matchedQty = nil
                local dirLabel = nil
                for _, inc in ipairs(tx.incoming) do
                    if inc.itemID == itemID then matchedQty = inc.qty; dirLabel = '|cff00ff00+IN|r' end
                end
                for _, out in ipairs(tx.outgoing) do
                    if out.itemID == itemID then matchedQty = out.qty; dirLabel = '|cffff6666-OUT|r' end
                end
                if not matchedQty then
                    for key, dQty in pairs(tx.metadata.unresolved or tx.metadata.delta or {}) do
                        local dID = tonumber(tostring(key):match('^(%d+)'))
                        if dID == itemID and dQty ~= 0 then
                            matchedQty = math.abs(dQty)
                            dirLabel = dQty > 0 and '|cff00ff00+IN|r' or '|cffff6666-OUT|r'
                        end
                    end
                end
                if matchedQty then
                    local goldStr = (tx.cashOut or 0) > 0 and ('Paid ' .. Money(tx.cashOut))
                        or (tx.cashIn or 0) > 0 and ('Received ' .. Money(tx.cashIn))
                        or 'No gold'
                    itemMovements[#itemMovements + 1] = string.format("%s x%d via %s (%s · %s)",
                        dirLabel, matchedQty, Title(tx), tx.owner or "Player", goldStr)
                    if #itemMovements >= 6 then break end
                end
            end
            if #itemMovements > 0 then
                Detail('info', '|cffffd700Recent In / Out History for ' .. iName .. '|r\n' .. table.concat(itemMovements, "\n"))
            end
            local rollup = I.GetRollupSummary and I.GetRollupSummary()
            local rItem = rollup and rollup.items and rollup.items[itemID]
            if rItem and ((rItem.inQty or 0) > 0 or (rItem.outQty or 0) > 0) then
                Detail('info', string.format('|cff91c9ffCompacted Historical Rollup (30d+)|r\n|cff00ff00+%d In|r · |cffff6666-%d Out|r · Net Δ: %+d units',
                    rItem.inQty or 0, rItem.outQty or 0, (rItem.inQty or 0) - (rItem.outQty or 0)))
            end
        end

        function f:Refresh()
            local enabled = MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()
            if self.betaNotice then
                if enabled then self.betaNotice:Hide() else self.betaNotice:Show() end
            end
            if self.betaToggleBtn then
                self.betaToggleBtn:SetText(enabled and "|cff77ddbbBeta: Active|r" or "|cff00ff00Enable Beta|r")
            end
            for n = 1, 4 do
                if self.cards[n] then
                    if enabled then self.cards[n]:Show() else self.cards[n]:Hide() end
                end
            end

            local job = self.jobID and MarketSync.CraftLedger.Get(self.jobID)
            self.context:SetText(job and ("|cff77ddbbTracking:|r " .. job.name .. " x" .. job.quantity .. (job.customer and " · Customer: " .. job.customer or " · Your own craft"))
                or "Your multi-character inventory, In/Out item movements, and gold exchanges. Open from a saved craft to link records.")

            local all = I.List()
            local transactions = {}
            local rollup = I.GetRollupSummary and I.GetRollupSummary() or { cashIn = 0, cashOut = 0 }
            local review, cashIn, cashOut = 0, (rollup.cashIn or 0), (rollup.cashOut or 0)
            for _, tx in ipairs(all) do
                if NeedsReview(tx) then review = review + 1 end
                if tx.state == 'confirmed' then
                    cashIn = cashIn + (tx.cashIn or 0)
                    cashOut = cashOut + (tx.cashOut or 0)
                end
                if Matches(tx, self) then transactions[#transactions + 1] = tx end
            end

            local catalog = nil
            if self.viewMode == 'stock' then
                catalog = CollectCatalogItems(self.searchText)
            end
            local totals = job and MarketSync.CraftLedger.Totals(job)
            self.cards[1].title:SetText(job and 'Materials paid for this craft' or 'Gold spent · recorded activity')
            self.cards[1].value:SetText("|cffff6666-|r " .. Money(totals and totals.paid or cashOut) .. (totals and totals.unknownCost and ' |cffffbb44Cost incomplete|r' or ''))
            self.cards[2].title:SetText(job and 'Sales / service payments' or 'Gold received · recorded activity')
            self.cards[2].value:SetText("|cff00ff00+|r " .. Money(totals and totals.gross or cashIn))
            self.cards[3].title:SetText('Needs review · click to filter')
            self.cards[3].value:SetText((review > 0 and '|cffffbb44' or '|cff77ddbb') .. review .. (review == 1 and ' record|r' or ' records|r'))

            local netGold = (totals and ((totals.gross or 0) - (totals.paid or 0))) or (cashIn - cashOut)
            self.cards[4].title:SetText('Net flow & stock · click to view')
            local stockInfo = catalog and (' · |cffffffff' .. #catalog .. ' items|r') or ' · |cffffffffStock|r'
            self.cards[4].value:SetText((netGold >= 0 and '|cff77ddbb+' or '|cffff6666') .. Money(netGold) .. '|r' .. stockInfo)

            for _, row in ipairs(self.rows) do row:Hide() end
            for _, row in ipairs(self.detailRows) do row:Hide() end
            self.detailCount, self.detailY = 0, 0

            if self.viewMode == 'stock' then
                self.listHeading:SetText("|cffffd700Character Stock & FIFO Lots|r")
                local pages = math.max(1, math.ceil(#catalog / 50))
                self.page = math.min(self.page, pages - 1)
                self.pageLabel:SetText('Page ' .. (self.page + 1) .. ' / ' .. pages)
                self.newer:SetEnabled(self.page > 0)
                self.older:SetEnabled(self.page + 1 < pages)

                local count = math.min(50, #catalog - self.page * 50)
                if not self.itemID and catalog[1] then self.itemID = catalog[1].itemID end

                for index = 1, count do
                    local entry = catalog[self.page * 50 + index]
                    local row = self.rows[index]
                    if not row then
                        row = CreateFrame("Button", nil, content, "BackdropTemplate")
                        row:SetSize(370, 68)
                        if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
                        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                        row.icon = Icon(row, 8, -13, 34)
                        row.title = Label(row, 50, -9, 205, nil, "GameFontNormalSmall")
                        row.item = Label(row, 50, -29, 300)
                        row.status = Label(row, 254, -10, 106)
                        row.meta = Label(row, 50, -48, 300)
                        self.rows[index] = row
                    end
                    row:SetPoint("TOPLEFT", 0, -(index - 1) * 72)
                    row.selected = (self.itemID == entry.itemID)
                    row:SetBackdropColor(Color(row.selected and 'hover' or (index % 2 == 0 and 'rowEven' or 'rowOdd')))
                    row:SetBackdropBorderColor(Color('border'))
                    if row.selected then row:SetBackdropBorderColor(1, .82, 0, 1) end

                    SetIcon(row.icon, entry)
                    local coloredName = entry.name
                    if MarketSync.FormatColoredItemName then
                        local quality = MarketSync.GetItemInfo and select(3, MarketSync.GetItemInfo(entry.itemID))
                        coloredName = MarketSync.FormatColoredItemName(coloredName, quality or 1)
                    end
                    row.title:SetText("|cffffd700Stock Holding|r")
                    row.status:SetText("|cffffffff" .. entry.total .. " total|r")
                    row.item:SetText(coloredName .. " x" .. entry.total)

                    local ownerParts = {}
                    for oName, oQty in pairs(entry.byOwner) do
                        ownerParts[#ownerParts + 1] = oName .. ": " .. oQty
                    end
                    table.sort(ownerParts)
                    local avgCost = entry.costUnits > 0 and ("FIFO " .. Money(entry.paid / entry.costUnits)) or "Cost unknown"
                    row.meta:SetText(avgCost .. " · " .. table.concat(ownerParts, ", "))

                    local function SelectStock(_, btn)
                        self.itemID = entry.itemID
                        detailsScroll:SetVerticalScroll(0)
                        self:Refresh()
                        if btn == "RightButton" then
                            if MarketSync.ShowItemContextMenu then
                                MarketSync.ShowItemContextMenu(row, {
                                    itemID = entry.itemID,
                                    itemName = entry.name,
                                    customActions = {
                                        {
                                            text = "Filter Activity to This Item",
                                            func = function()
                                                self.viewMode = 'activity'
                                                self.filter = 'all'
                                                self.searchText = entry.name
                                                if self.query then self.query:SetText(entry.name) end
                                                self.page = 0
                                                self:Refresh()
                                            end
                                        },
                                    }
                                })
                            end
                        end
                    end
                    row:SetScript("OnClick", SelectStock)
                    row.icon:SetScript("OnClick", SelectStock)
                    row:Show()
                end
                content:SetHeight(math.max(1, count * 72))

                if self.itemID then
                    self.detailHeading:SetText("|cffffd700Item Stock & Flow History|r")
                    RenderItemHistorySection(self.itemID)
                else
                    self.detailHeading:SetText("|cffffd700No Stock Recorded|r")
                    Detail('info', "Open your bags, bank, or mailbox on characters to populate stock holdings.")
                end
                details:SetHeight(math.max(1, self.detailY))
                if MarketSync.Theme then MarketSync.Theme.Apply(self) end
                return
            end

            -- Default View: Activity Stream (or Review Queue)
            self.listHeading:SetText(self.filter == 'review' and "|cffffbb44Needs Review & Attribution|r" or "|cffffd700In / Out Activity Stream|r")
            local pages = math.max(1, math.ceil(#transactions / 50))
            self.page = math.min(self.page, pages - 1)
            self.pageLabel:SetText('Page ' .. (self.page + 1) .. ' / ' .. pages)
            self.newer:SetEnabled(self.page > 0)
            self.older:SetEnabled(self.page + 1 < pages)

            local visible = {}
            for index = self.page * 50 + 1, math.min(#transactions, (self.page + 1) * 50) do
                visible[transactions[index].id] = true
            end
            if not visible[self.selected] then
                self.selected = transactions[self.page * 50 + 1] and transactions[self.page * 50 + 1].id
                self.itemID = nil
                self.expandedAudit = false
                detailsScroll:SetVerticalScroll(0)
            end

            local count = math.min(50, #transactions - self.page * 50)
            for index = 1, count do
                local tx = transactions[self.page * 50 + index]
                local row = self.rows[index]
                if not row then
                    row = CreateFrame("Button", nil, content, "BackdropTemplate")
                    row:SetSize(370, 68)
                    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
                    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                    row.icon = Icon(row, 8, -13, 34)
                    row.title = Label(row, 50, -9, 205, nil, "GameFontNormalSmall")
                    row.item = Label(row, 50, -29, 300)
                    row.status = Label(row, 254, -10, 106)
                    row.meta = Label(row, 50, -48, 300)
                    self.rows[index] = row
                end
                row:SetPoint("TOPLEFT", 0, -(index - 1) * 72)
                row.selected = self.selected == tx.id
                row:SetBackdropColor(Color(row.selected and 'hover' or (index % 2 == 0 and 'rowEven' or 'rowOdd')))
                row:SetBackdropBorderColor(Color('border'))
                if row.selected then row:SetBackdropBorderColor(1, .82, 0, 1) end

                local first = FirstItem(tx)
                SetIcon(row.icon, first)
                local _, dirBadge = DirectionInfo(tx)
                row.title:SetText(dirBadge .. Title(tx))
                row.status:SetText(Status(tx))

                local name = first and ItemName(first) or (tx.counterparty and 'With ' .. tx.counterparty or 'Gold / inventory record')
                if first and MarketSync.FormatColoredItemName then
                    local quality = MarketSync.GetItemInfo and select(3, MarketSync.GetItemInfo(first.itemID))
                    name = MarketSync.FormatColoredItemName(name, quality or 1)
                end
                local qtySuffix = ""
                if first then
                    local sign = first.dir == "in" and "|cff00ff00+" or (first.dir == "out" and "|cffff6666-" or "")
                    local closeSign = (first.dir == "in" or first.dir == "out") and "|r" or ""
                    qtySuffix = " x" .. first.qty .. " (" .. sign .. first.qty .. closeSign .. ")"
                end
                row.item:SetText(name .. qtySuffix)

                local cash = (tx.cashOut or 0) > 0 and ('|cffff6666-' .. Money(tx.cashOut) .. '|r')
                    or (tx.cashIn or 0) > 0 and ('|cff00ff00+' .. Money(tx.cashIn) .. '|r')
                    or (tx.counterparty or 'No gold exchanged')
                row.meta:SetText(cash .. ' · ' .. (tx.owner or '') .. ' · ' .. (date and date('%b %d %H:%M', tx.at) or tostring(tx.at)))

                local function OpenRowContextMenu()
                    local menu = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
                    UIDropDownMenu_Initialize(menu, function(_, level)
                        local hdr = UIDropDownMenu_CreateInfo()
                        hdr.text = Title(tx) .. (first and (" · " .. ItemName(first)) or "")
                        hdr.isTitle = true
                        hdr.notCheckable = true
                        UIDropDownMenu_AddButton(hdr, level)

                        if NeedsReview(tx) then
                            local hasIntact = #tx.lots >= 1
                            for _, lID in ipairs(tx.lots) do
                                local l = I.Lot(lID)
                                if not l or l.qty ~= l.originalQty or l.customerJob then hasIntact = false end
                            end
                            if hasIntact then
                                local freeBtn = UIDropDownMenu_CreateInfo()
                                freeBtn.text = "|cff55ff88Confirm: Self-Found / 0g|r"
                                freeBtn.notCheckable = true
                                freeBtn.func = function()
                                    if I.ResolveRecord then Report(I.ResolveRecord(tx.id, "set_cost", 0)) end
                                    self:Refresh()
                                end
                                UIDropDownMenu_AddButton(freeBtn, level)

                                local paidBtn = UIDropDownMenu_CreateInfo()
                                paidBtn.text = "|cffffd700Confirm: Set Paid Cost...|r"
                                paidBtn.notCheckable = true
                                paidBtn.func = function()
                                    local targetID = tx.id
                                    Prompt("Enter total gold paid for these item(s) (e.g. 0 or 1.5):", function(text)
                                        local gold = tonumber(text)
                                        if gold and gold >= 0 then
                                            Report(I.ResolveRecord(targetID, "set_cost", math.floor(gold * 10000 + 0.5)))
                                        else
                                            Report(false, "Enter a non-negative gold value.")
                                        end
                                        self:Refresh()
                                    end)
                                end
                                UIDropDownMenu_AddButton(paidBtn, level)
                            end

                            local ackBtn = UIDropDownMenu_CreateInfo()
                            ackBtn.text = "|cff77ddbbConfirm: Mark Reviewed|r"
                            ackBtn.notCheckable = true
                            ackBtn.func = function()
                                if I.ResolveRecord then Report(I.ResolveRecord(tx.id, "acknowledge")) end
                                self:Refresh()
                            end
                            UIDropDownMenu_AddButton(ackBtn, level)

                            if tx.kind == "inventory observation" or tx.kind == "unattributed inventory" then
                                local bulkBtn = UIDropDownMenu_CreateInfo()
                                bulkBtn.text = "Confirm All Bag/Ammo Changes"
                                bulkBtn.notCheckable = true
                                bulkBtn.func = function()
                                    if I.ResolveAllObservations then
                                        local n = I.ResolveAllObservations()
                                        print("|cff00ff00[MarketSync]|r Acknowledged " .. n .. " unresolved storage/bag observation(s).")
                                    end
                                    self:Refresh()
                                end
                                UIDropDownMenu_AddButton(bulkBtn, level)
                            end
                        end

                        for _, a in ipairs(self.actions) do
                            if Eligible(a) and a.original ~= "Mark Self-Found / 0g" and a.original ~= "Mark Reviewed (Keep Unknown)" and a.original ~= "Acknowledge All Bag Changes" then
                                local info = UIDropDownMenu_CreateInfo()
                                info.text = a.name
                                info.notCheckable = true
                                info.func = a.run
                                UIDropDownMenu_AddButton(info, level)
                            end
                        end

                        if first and first.itemID then
                            local inspectBtn = UIDropDownMenu_CreateInfo()
                            inspectBtn.text = "Inspect Item Stock & Flow"
                            inspectBtn.notCheckable = true
                            inspectBtn.func = function()
                                self.itemID = first.itemID
                                self:Refresh()
                            end
                            UIDropDownMenu_AddButton(inspectBtn, level)

                            if MarketSync.SearchInAuctionHouse then
                                local ahBtn = UIDropDownMenu_CreateInfo()
                                ahBtn.text = "Search in Auction House"
                                ahBtn.notCheckable = true
                                ahBtn.func = function()
                                    MarketSync.SearchInAuctionHouse(ItemName(first) or first.itemID)
                                end
                                UIDropDownMenu_AddButton(ahBtn, level)
                            end
                        end

                        local cancelBtn = UIDropDownMenu_CreateInfo()
                        cancelBtn.text = "Cancel"
                        cancelBtn.notCheckable = true
                        cancelBtn.func = function() if CloseDropDownMenus then CloseDropDownMenus() end end
                        UIDropDownMenu_AddButton(cancelBtn, level)
                    end, "MENU")
                    ToggleDropDownMenu(1, nil, menu, row, 0, 0)
                end

                local function Select(_, btn)
                    self.selected = tx.id
                    self.itemID = nil
                    self.expandedAudit = false
                    detailsScroll:SetVerticalScroll(0)
                    self:Refresh()
                    if btn == "RightButton" then
                        OpenRowContextMenu()
                    end
                end
                row:SetScript("OnClick", Select)
                row.icon:SetScript("OnClick", Select)
                row:SetScript("OnEnter", function() if not row.selected then row:SetBackdropColor(Color('hover')) end end)
                row:SetScript("OnLeave", function() if not row.selected then row:SetBackdropColor(Color(index % 2 == 0 and 'rowEven' or 'rowOdd')) end end)
                row:Show()
            end
            content:SetHeight(math.max(1, count * 72))

            local tx = I.Get(self.selected)
            if tx then
                self.detailHeading:SetText('|cffffd700' .. Title(tx) .. '|r · ' .. Status(tx))
                if NeedsReview(tx) then
                    local quickActions = {}
                    local hasIntactLot = false
                    if #tx.lots >= 1 then
                        hasIntactLot = true
                        for _, lotID in ipairs(tx.lots) do
                            local l = I.Lot(lotID)
                            if not l or l.qty ~= l.originalQty or l.customerJob then hasIntactLot = false end
                        end
                    end

                    if hasIntactLot then
                        quickActions[#quickActions + 1] = {
                            label = "Self-Found / 0g",
                            fn = function()
                                if I.ResolveRecord then Report(I.ResolveRecord(tx.id, "set_cost", 0)) end
                                self:Refresh()
                            end
                        }
                        quickActions[#quickActions + 1] = {
                            label = "Set Paid Cost...",
                            fn = function()
                                local targetID = tx.id
                                Prompt("Enter total gold paid for these item(s) (e.g. 0 or 1.5):", function(text)
                                    local gold = tonumber(text)
                                    if gold and gold >= 0 then
                                        Report(I.ResolveRecord(targetID, "set_cost", math.floor(gold * 10000 + 0.5)))
                                    else
                                        Report(false, "Enter a non-negative gold value.")
                                    end
                                    self:Refresh()
                                end)
                            end
                        }
                    elseif tx.metadata and tx.metadata.custodyPending and #tx.outgoing > 0 then
                        quickActions[#quickActions + 1] = {
                            label = "Use My Own Stock",
                            fn = function()
                                Report(I.AttributeOwn(tx.id))
                                self:Refresh()
                            end
                        }
                    elseif tx.kind == "trade" and tx.classification == "unassigned" then
                        quickActions[#quickActions + 1] = {
                            label = "Personal Trade",
                            fn = function()
                                if I.ResolveRecord then Report(I.ResolveRecord(tx.id, "personal_trade")) end
                                self:Refresh()
                            end
                        }
                        if #tx.outgoing > 0 then
                            quickActions[#quickActions + 1] = {
                                label = "Free Guild Craft...",
                                fn = function()
                                    local targetID = tx.id
                                    Prompt("Enter incoming material transaction ID to link as a zero-cost guild craft:", function(text)
                                        local inID = tonumber(text)
                                        Report(inID and I.LinkGuildCraft and I.LinkGuildCraft(inID, targetID))
                                        self:Refresh()
                                    end)
                                end
                            }
                        end
                    end

                    quickActions[#quickActions + 1] = {
                        label = (tx.kind == "inventory observation" or tx.kind == "unattributed inventory") and "Mark Reviewed" or "Keep Unknown Cost",
                        fn = function()
                            if I.ResolveRecord then Report(I.ResolveRecord(tx.id, "acknowledge")) end
                            self:Refresh()
                        end
                    }
                    if #quickActions < 3 and (tx.kind == "inventory observation" or tx.kind == "unattributed inventory") then
                        quickActions[#quickActions + 1] = {
                            label = "Clear All Bag Changes",
                            fn = function()
                                if I.ResolveAllObservations then
                                    local n = I.ResolveAllObservations()
                                    print("|cff00ff00[MarketSync]|r Acknowledged " .. n .. " unresolved storage/bag observation(s).")
                                end
                                self:Refresh()
                            end
                        }
                    end

                    Detail('info', '|cffffbb44Quick Resolution — Choose how to classify this record:|r\nClick a button below to resolve this item immediately and clear its Needs Review status.', nil, quickActions)
                else
                    Detail('info', 'This activity has been recorded (' .. tostring(tx.classification or 'confirmed') .. '). Link it to a craft or exchange when appropriate.')
                end
                Detail('info', '|cffffd700Who & when|r\n' .. tx.owner .. (tx.counterparty and ' · With ' .. tx.counterparty or '') .. '\n' .. (date and date('%b %d, %H:%M', tx.at) or tostring(tx.at)))
                for _, item in ipairs(tx.incoming) do
                    Detail('item', '|cff00ff00+ Received|r · ' .. ItemName(item) .. ' x' .. item.qty .. '\nClick the icon to inspect multi-character stock & In/Out history.', item)
                end
                for _, item in ipairs(tx.outgoing) do
                    Detail('item', '|cffffbb77- Sent / used|r · ' .. ItemName(item) .. ' x' .. item.qty .. '\nClick the icon to inspect multi-character stock & In/Out history.', item)
                end
                if tx.kind == 'inventory observation' then
                    for key, qty in pairs(tx.metadata.unresolved or tx.metadata.delta or {}) do
                        local id = tonumber(tostring(key):match('^(%d+)'))
                        if id and qty ~= 0 then
                            local item = { itemID = id, qty = math.abs(qty) }
                            Detail('item', (qty > 0 and '|cff77ddbb+ More in storage|r · ' or '|cffffbb77- Fewer in storage|r · ') .. ItemName(item) .. ' x' .. item.qty .. '\nObserved movement; source and acquisition cost are not inferred.', item)
                        end
                    end
                end
                Detail('info', '|cffffd700Gold exchanged|r\nReceived ' .. Money(tx.cashIn) .. ' · Paid ' .. Money(tx.cashOut) .. '\nFees / postage ' .. Money(tx.fee))
                for _, lotID in ipairs(tx.lots) do
                    local lot = I.Lot(lotID)
                    local cost = I.Cost(lotID)
                    if lot then
                        Detail('info', '|cffffd700' .. lot.qty .. ' units in this inventory lot|r\n' .. (cost == nil and '|cffffbb44Acquisition cost unknown — do not treat as free.|r' or 'Actual unit cost: ' .. Money(cost)) .. (lot.customerJob and '\n|cff91c9ffCustomer-owned materials|r' or ''))
                    end
                end
                if tx.metadata and tx.metadata.taggedCraftName then
                    Detail('info', '|cff77ddbbAuto-Tagged Craft Material|r\nMatches active demand for: ' .. tx.metadata.taggedCraftName .. ' (Need ' .. tostring(tx.metadata.taggedNeed or 1) .. ')')
                end
                if tx.classification == "guild craft" or (tx.metadata and tx.metadata.guildCraftSummary) then
                    local gs = tx.metadata and tx.metadata.guildCraftSummary
                    local peerName = (gs and gs.customer) or tx.counterparty or "Guildmate"
                    local tipAmt = (gs and gs.tip) or (tx.cashIn or 0)
                    Detail('info', '|cff77ddbbZero-Cost Guild Craft|r\nPass-through craft with ' .. peerName .. ' · Material expense: 0c (Not counted as loss)\nService tip / net: ' .. Money(tipAmt))
                end
                if tx.kind == "crafted output" and I.EvaluateValueGained then
                    local gain = I.EvaluateValueGained(tx)
                    if gain and (gain.matMarketValue > 0 or gain.outMarketValue > 0) then
                        local vsMat = gain.valueGainedVsMats and Money(gain.valueGainedVsMats) or "Unknown"
                        local vsPaid = gain.profitVsPaid and Money(gain.profitVsPaid) or "Unknown"
                        Detail('info', '|cffffd700Crafting Value Gained & Opportunity Cost|r\nRaw Mat AH Value (-5%): ' .. Money(gain.matNetAH) .. ' · Output AH Value (-5%): ' .. Money(gain.outNetAH) .. '\nValue Gained vs. Selling Raw Mats: ' .. vsMat .. ' · Profit vs. Paid: ' .. vsPaid)
                    end
                end
                if tx.serviceID or tx.transferID or tx.saleJobID then
                    Detail('info', '|cff77ddbbLinked record|r\n' .. (tx.serviceID and 'Customer craft #' .. tx.serviceID or tx.saleJobID and 'Sale for craft #' .. tx.saleJobID or 'Matching character transfer #' .. tx.transferID))
                end
                if tx.metadata.invoice then
                    Detail('info', '|cffffd700Auction receipt|r\n' .. (tx.metadata.invoice.name or 'Item receipt') .. ' · ' .. (tx.metadata.invoice.kind == 'seller' and 'Sale receipt — link it from Craft & sales.' or 'Purchase receipt'))
                end
                for key, quote in pairs(tx.estimatedValue or {}) do
                    Detail('info', '|cff91c9ffMarket estimate only|r\n' .. key .. ': ' .. Money(quote.unitPrice) .. ' per unit\nThis is not proof of the amount paid.')
                end
                if self.itemID then
                    RenderItemHistorySection(self.itemID)
                end
                if self.expandedAudit then
                    Detail('info', '|cff999999Audit trail|r\nRecord #' .. tx.id .. ' · ' .. tx.state .. '\nEvidence: ' .. tx.evidence .. ' · Classification: ' .. tx.classification)
                end
                self.guidance:SetText(NeedsReview(tx) and 'Needs review: determine who owns the items and whether money changed hands before classifying this record.'
                    or job and 'Actions link this activity to ' .. job.name .. '. Unknown acquisition costs remain unknown.'
                    or 'Open from a saved craft to enable craft and customer actions. Inventory tools work independently.')
            else
                self.detailHeading:SetText('|cffffd700No matching activity|r')
                Detail('info', 'No records match your search or filter.\nTry All activity, clear the search, or refresh storage.')
            end
            details:SetHeight(math.max(1, self.detailY))
            if MarketSync.Theme then MarketSync.Theme.Apply(self) end
        end

        local refreshQueued = false
        local function SafeRefresh()
            refreshQueued = false
            if f and f:IsShown() then f:Refresh() end
        end

        I.Refresh = function()
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
        if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(f) end
    end
    window.jobID = jobID
    if MarketSync.ShowWorkspaceWindow then MarketSync.ShowWorkspaceWindow(window, craft) else window:Show() end
    window:Refresh()
    return window
end

function MarketSync.ToggleItemLedger(jobID)
    if window and window:IsShown() and not jobID then
        window:Hide()
        return nil
    end
    if MarketSync.IsLedgerEnabled and not MarketSync.IsLedgerEnabled() then
        return nil
    end
    return MarketSync.OpenItemLedger(jobID)
end
