-- Read-only client observers. Confirmation, not UI clicks, commits transactions.
local I = MarketSync.ItemLedger
local T = { hooks = {}, bankOpen = false, mailOpen = false }
MarketSync.InventoryTracking = T
if not MarketSync.IsDetailsKeyDown then
    function MarketSync.IsDetailsKeyDown()
        local mod = MarketSyncDB and MarketSyncDB.TooltipModifier or "SHIFT"
        if mod == "CTRL" then return (IsControlKeyDown and IsControlKeyDown()) and true or false
        elseif mod == "ALT" then return (IsAltKeyDown and IsAltKeyDown()) and true or false
        else return (IsShiftKeyDown and IsShiftKeyDown()) and true or false end
    end
end
local function After(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0.3, fn) else fn() end
end
local function Add(items, link, quantity)
    local key, id = I.Key(link)
    quantity = tonumber(quantity)
    if key and quantity and quantity > 0 then
        local entry = items[key] or { key = key, itemID = id, qty = 0, link = type(link) == "string" and link or nil }
        entry.qty = entry.qty + quantity; items[key] = entry
    end
end
local function Array(items)
    local out = {}; for _, item in pairs(items) do out[#out + 1] = item end; return out
end
local function BagItems(first, last)
    local items = {}
    local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local info = C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo
    if not slots or not info then return nil end
    for bag = first, last do
        for slot = 1, slots(bag) or 0 do
            local a, b, _, _, _, _, link, _, _, id = info(bag, slot)
            if type(a) == "table" then Add(items, a.hyperlink or a.itemID, a.stackCount)
            else Add(items, link or id, b) end
            T.slots = T.slots or {}
            T.slots[bag .. ":" .. slot] = type(a) == "table" and { link = a.hyperlink or a.itemID, qty = a.stackCount }
                or (link and { link = link, qty = b } or nil)
        end
    end
    return items
end
function T.CaptureBags()
    local items = BagItems(0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
    if not items then return end
    local equipped = {}
    if GetInventoryItemLink then
        for slot = 1, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then Add(equipped, link, 1) end
        end
    end
    I.Snapshot("bags", items, { equipped = equipped })
    I.Snapshot("equipped", equipped)
    T.lastBags, T.lastMoney = items, GetMoney and GetMoney() or 0
end
function T.CaptureBank()
    if not T.bankOpen then return end
    local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    if not slots then return end
    if (slots(-1) or 0) <= 0 then
        if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType and Enum.BankType.Character then
            if C_Bank.CanViewBank and not C_Bank.CanViewBank(Enum.BankType.Character) then return end
            local items, complete = {}, true
            for _, bag in ipairs(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character) or {}) do
                local contents = BagItems(bag, bag)
                if not contents or (slots(bag) or 0) == 0 then complete = false end
                for _, item in pairs(contents or {}) do Add(items, item.link or item.itemID, item.qty) end
            end
            if complete then I.Snapshot("bank", items) end
        end
        return
    end
    local items = BagItems(-1, -1)
    if not items then return end
    local bags = BagItems((NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7))
    for _, item in pairs(bags or {}) do Add(items, item.link or item.itemID, item.qty) end
    I.Snapshot("bank", items)
    if REAGENTBANK_CONTAINER then
        local reagents = BagItems(REAGENTBANK_CONTAINER, REAGENTBANK_CONTAINER)
        if reagents then I.Snapshot("reagent bank", reagents) end
    end
end
local function ItemCount(id)
    local fn = C_Item and C_Item.GetItemCount or GetItemCount
    return fn and fn(id, false) or 0
end
local function Signature(mail)
    local parts = { mail.sender or "", mail.subject or "", tostring(mail.money), tostring(mail.cod) }
    local entries = {}; for _, item in ipairs(mail.items) do entries[#entries + 1] = item.key .. "=" .. item.qty end
    table.sort(entries); parts[#parts + 1] = table.concat(entries, ","); return table.concat(parts, "\031")
end
local function ReadMail(index)
    local _, _, sender, subject, money, cod, _, count, _, returned = GetInboxHeaderInfo(index)
    local mail = { sender = sender, subject = subject, money = money or 0, cod = cod or 0, items = {}, returned = returned }
    for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local _, id, _, qty = GetInboxItem(index, slot)
        local link = GetInboxItemLink and GetInboxItemLink(index, slot)
        local key, itemID = I.Key(link or id)
        if key and qty then mail.items[#mail.items + 1] = { key = key, itemID = itemID, link = link, qty = qty, slot = slot } end
    end
    if GetInboxInvoiceInfo then
        local kind, name, buyer, bid, buyout, deposit, fee, _, _, _, qty = GetInboxInvoiceInfo(index)
        if kind then mail.invoice = { kind = kind, name = name, buyer = buyer, bid = bid, buyout = buyout, deposit = deposit, fee = fee, qty = qty } end
    end
    mail.signature = Signature(mail); return mail
end
local function Mails()
    local out, signatures, items = {}, {}, {}
    for index = 1, GetInboxNumItems() or 0 do
        local mail = ReadMail(index); out[index] = mail
        signatures[mail.signature] = (signatures[mail.signature] or 0) + 1
        for _, item in ipairs(mail.items) do Add(items, item.link or item.itemID, item.qty) end
    end
    return out, signatures, items
end
function T.CaptureMail()
    if not T.mailOpen or not (GetInboxNumItems and GetInboxHeaderInfo and GetInboxItem) then return end
    local mails, signatures, items = Mails()
    local _, total = GetInboxNumItems()
    I.Snapshot("mail", items, { complete = not total or #mails >= total })
    T.mails, T.signatures = mails, signatures
    local batch = T.collections
    if not batch then return end
    for index = #batch.pending, 1, -1 do
        local p = batch.pending[index]
        local changed = (signatures[p.mail.signature] or 0) < p.matches
        local confirmed = changed and ((p.item and ItemCount(p.item.itemID) >= p.threshold)
            or (not p.item and GetMoney() >= p.threshold))
        if p.item and p.mail.cod > 0 and GetMoney() > p.money - p.mail.cod then confirmed = false end
        if confirmed then
            if MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled() then
                batch.codRecorded = batch.codRecorded or {}
                local codKey = p.mail.signature
                local cod = p.item and not batch.codRecorded[codKey] and p.mail.cod or 0
                local tx = I.Record("mail collected", { incoming = p.item and { p.item } or {}, cashIn = not p.item and p.mail.money or 0,
                    cashOut = cod, counterparty = p.mail.sender,
                    evidence = "mailbox change and inventory/money confirmation", token = p.token,
                    metadata = { invoice = p.mail.invoice, cod = p.mail.cod > 0, sharedCOD = #p.mail.items > 1 and p.mail.cod > 0, returned = p.mail.returned } })
                if cod > 0 then batch.codRecorded[codKey] = true end
                if tx and cod > 0 and #p.mail.items == 1 then I.SetCost(tx.id, cod) end
                if tx then I.MatchPendingPurchase(tx) end
                local reqId = tonumber(p.token and p.token:match("mail:(%d+)"))
                local request = reqId and I.Get and I.Get(reqId)
                if request and tx then request.state = "reconciled"; request.metadata.confirmedBy = tx.id end
            end
            table.remove(batch.pending, index)
        elseif time() > p.expires then table.remove(batch.pending, index) end
    end
    if #batch.pending == 0 then T.collections = nil end
end
local function Collect(index, slot)
    if not (MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()) then return end
    if not T.mailOpen or not GetInboxHeaderInfo then return end
    local mail = ReadMail(index); local _, signatures = Mails()
    local item
    if slot then for _, entry in ipairs(mail.items) do if entry.slot == slot then item = entry end end; if not item then return end end
    if not slot and mail.money <= 0 then return end
    T.collections = T.collections or { pending = {}, seen = {}, baselines = {}, requested = {} }
    local batch = T.collections
    local action = mail.signature .. ":" .. tostring(index) .. ":" .. tostring(slot or "money")
    if batch.seen[action] then return end
    batch.seen[action] = true
    local key = item and tostring(item.itemID) or "money"
    batch.baselines[key] = batch.baselines[key] or (item and ItemCount(item.itemID) or GetMoney())
    batch.requested[key] = (batch.requested[key] or 0) + (item and item.qty or mail.money)
    local observation = I.Record("mail collection request", { state = "unresolved", evidence = "API request", metadata = { sender = mail.sender } })
    local token = observation and ("mail:" .. observation.id) or ("mail:req_" .. tostring(time()) .. "_" .. tostring(index) .. "_" .. tostring(slot or "money"))
    batch.pending[#batch.pending + 1] = { mail = mail, item = item, threshold = batch.baselines[key] + batch.requested[key], money = GetMoney(),
        matches = signatures[mail.signature], token = token, expires = time() + 10 }
    After(T.CaptureMail)
end
local function Draft()
    local items = {}
    if GetSendMailItem then
        for slot = 1, ATTACHMENTS_MAX_SEND or 12 do
            local _, id, _, count = GetSendMailItem(slot)
            local link = GetSendMailItemLink and GetSendMailItemLink(slot)
            Add(items, link or id, count)
        end
    end
    return Array(items)
end
local function Trade()
    if not GetTradePlayerItemInfo then return end
    local incoming, outgoing = {}, {}
    for slot = 1, 6 do
        local _, _, qty = GetTradePlayerItemInfo(slot)
        Add(outgoing, GetTradePlayerItemLink and GetTradePlayerItemLink(slot), qty)
        local _, _, targetQty = GetTradeTargetItemInfo(slot)
        Add(incoming, GetTradeTargetItemLink and GetTradeTargetItemLink(slot), targetQty)
    end
    return { incoming = Array(incoming), outgoing = Array(outgoing), cashIn = GetTargetTradeMoney and GetTargetTradeMoney() or 0,
        cashOut = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0, counterparty = GetUnitName and GetUnitName("NPC", true) or UnitName("NPC"), expires = time() + 10 }
end
local function Hook(name, fn)
    if not T.hooks[name] and type(_G[name]) == "function" and hooksecurefunc then
        hooksecurefunc(name, fn); T.hooks[name] = true
    end
end
function T.InstallHooks()
    Hook("TakeInboxItem", Collect)
    Hook("TakeInboxMoney", function(index) Collect(index) end)
    Hook("SetSendMailMoney", function(amount) T.sendMoney = amount end)
    Hook("SetSendMailCOD", function(amount) T.sendCOD = amount end)
    Hook("SendMail", function(recipient, subject)
        if not (MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()) then return end
        T.send = { recipient = recipient, subject = subject, items = Draft(), money = T.sendMoney or 0,
            cod = T.sendCOD or 0, fee = GetSendMailPrice and GetSendMailPrice() or 0 }
    end)
    Hook("BuyMerchantItem", function(index, quantity)
        if not (MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()) then return end
        if not (GetMerchantItemInfo and GetMerchantItemLink) or T.vendor then return end
        local _, _, price, stack, _, _, extended = GetMerchantItemInfo(index)
        local link = GetMerchantItemLink(index); local _, id = I.Key(link)
        if not id or extended then return end
        local qty = tonumber(quantity) or stack or 1
        -- The hook runs after the request; keep the expected cost, then confirm
        -- through the subsequent inventory update before recording it.
        T.vendor = { link = link, itemID = id, qty = qty, paid = price * qty / math.max(1, stack or 1), expires = time() + 5 }
    end)
    local function Sell(bag, slot)
        if not (MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()) then return end
        if not (MerchantFrame and MerchantFrame:IsShown()) or T.sale then return end
        local item = T.slots and T.slots[bag .. ":" .. slot]
        if not item or not item.link then return end
        local key, id = I.Key(item.link)
        local info = GetItemInfo and { GetItemInfo(item.link) }
        local price = info and info[11]
        if not id or not price then return end
        T.sale = { key = key, itemID = id, link = item.link, qty = item.qty, paid = price * item.qty, expires = time() + 5 }
    end
    Hook("UseContainerItem", Sell)
    if C_Container and C_Container.UseContainerItem and not T.hooks.modernContainer and hooksecurefunc then
        hooksecurefunc(C_Container, "UseContainerItem", Sell); T.hooks.modernContainer = true
    end
end
local function ShortOwner(owner)
    local char, realm = owner:match("^([^%-]+)%-(.+)$")
    local myRealm = GetRealmName and GetRealmName()
    if char and (not realm or realm == myRealm or (GetNormalizedRealmName and realm == GetNormalizedRealmName())) then
        return char
    end
    return owner
end
local function SafeAddLine(tip, text, r, g, b)
    if tip and tip.AddLine then tip:AddLine(text, r, g, b) end
end
local function SafeAddDoubleLine(tip, left, right, lr, lg, lb, rr, rg, rb)
    if tip and tip.AddDoubleLine then
        tip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    elseif tip and tip.AddLine then
        tip:AddLine(tostring(left) .. "  " .. tostring(right), lr or 1, lg or 1, lb or 1)
    end
end
local function Tooltip(tooltip, data)
    if not MarketSyncDB or MarketSyncDB.ShowItemsOnOtherCharacters == false then return end
    local link
    if tooltip.GetItem then local _, itemLink = tooltip:GetItem(); link = itemLink end
    local _, id = I.Key(link or (data and data.id))
    if not id then return end

    local isShift = MarketSync.IsDetailsKeyDown and MarketSync.IsDetailsKeyDown()
    local shiftFlag = isShift and "shift" or "norm"
    if tooltip.MarketSyncOwnershipItem == id and tooltip.MarketSyncOwnershipShift == shiftFlag then return end
    tooltip.MarketSyncOwnershipItem = id
    tooltip.MarketSyncOwnershipShift = shiftFlag

    local holdings = I.Holdings(id)
    local hasOther = false
    local byOwner = {}
    local owners = {}
    local totalStock = 0
    local myOwner = I.Owner()

    for _, h in ipairs(holdings) do
        if not byOwner[h.owner] then
            byOwner[h.owner] = { total = 0, storages = {}, latestAt = h.at, complete = true }
            owners[#owners + 1] = h.owner
        end
        local entry = byOwner[h.owner]
        entry.total = entry.total + h.qty
        entry.storages[h.storage] = (entry.storages[h.storage] or 0) + h.qty
        if h.at > entry.latestAt then entry.latestAt = h.at end
        if not h.complete then entry.complete = false end
        totalStock = totalStock + h.qty
        if h.owner ~= myOwner then hasOther = true end
    end

    table.sort(owners, function(a, b)
        if a == myOwner then return true end
        if b == myOwner then return false end
        return a < b
    end)

    local addedLines = false
    local hasHiddenDetails = false

    -- 1. Character Inventory (Syndicator style)
    if totalStock > 0 then
        if not isShift then
            SafeAddDoubleLine(tooltip, "|cffffd700Inventory:|r", string.format("|cffffffff%d Total|r", totalStock))
            for _, owner in ipairs(owners) do
                local entry = byOwner[owner]
                local parts = {}
                local s = entry.storages
                if s.bags and s.bags > 0 then parts[#parts + 1] = "Bags " .. s.bags end
                if s.bank and s.bank > 0 then parts[#parts + 1] = "Bank " .. s.bank end
                if s["reagent bank"] and s["reagent bank"] > 0 then parts[#parts + 1] = "Reagents " .. s["reagent bank"] end
                if s.mail and s.mail > 0 then parts[#parts + 1] = "Mail " .. s.mail end
                if s.equipped and s.equipped > 0 then parts[#parts + 1] = "Equipped " .. s.equipped end
                local locStr = table.concat(parts, ", ")
                local nameStr = ShortOwner(owner)
                local prefix = (owner == myOwner) and ("  |cff00ff00" .. nameStr .. ":|r") or ("  |cffffffff" .. nameStr .. ":|r")
                SafeAddDoubleLine(tooltip, prefix, "|cffcccccc" .. locStr .. "|r")
            end
            hasHiddenDetails = true
            addedLines = true
        else
            SafeAddDoubleLine(tooltip, "|cffffd700Inventory Details:|r", string.format("|cffffffff%d Total|r", totalStock))
            for _, h in ipairs(holdings) do
                local age = math.max(0, time() - h.at)
                local ageMins = math.floor(age / 60)
                local ageStr = ageMins < 60 and (ageMins .. "m ago") or (math.floor(ageMins / 60) .. "h ago")
                local warn = h.complete and "" or " · partial"
                local nameStr = ShortOwner(h.owner)
                local prefix = (h.owner == myOwner) and ("  |cff00ff00" .. nameStr .. "|r") or ("  |cffffffff" .. nameStr .. "|r")
                SafeAddDoubleLine(tooltip, string.format("%s (%s):", prefix, h.storage),
                    string.format("|cffffffff%d|r |cff888888[%s%s]|r", h.qty, ageStr, warn))
            end
            if (MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()) and I.Store and I.Store().lots then
                local key = I.Key(id)
                local paid, units = 0, 0
                for _, lot in ipairs(I.Store().lots) do
                    if lot.owner == myOwner and lot.key == key and lot.qty > 0 and lot.unitCost then
                        paid = paid + (lot.unitCost * lot.qty)
                        units = units + lot.qty
                    end
                end
                if units > 0 then
                    local avg = paid / units
                    local fmt = MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(avg)
                        or (MarketSync.FormatMoney and MarketSync.FormatMoney(avg)
                        or (tostring(math.floor(avg)) .. "c"))
                    SafeAddDoubleLine(tooltip, "  |cff888888Cost Basis (FIFO):|r",
                        string.format("%s/ea |cff888888(%d units)|r", fmt, units))
                end
            end
            addedLines = true
        end
    end

    -- 2. Pending Crafting Orders / System Demand
    local L = MarketSync.CraftLedger
    local demand = L and L.GetItemDemand and L.GetItemDemand(id)
    if demand and MarketSyncDB.EnableTooltipCraftDemand ~= false then
        if not isShift then
            if demand.needed > 0 then
                local jCount = #demand.jobsNeeding
                local resText = demand.reserved > 0 and string.format(" · %d reserved", demand.reserved) or ""
                SafeAddDoubleLine(tooltip, "|cffffd700Pending Crafts:|r",
                    string.format("|cffffffffNeed %d|r |cff888888(%d %s%s)|r", demand.needed, jCount, jCount == 1 and "job" or "jobs", resText))
                hasHiddenDetails = true
                addedLines = true
            end
            if demand.toCraft > 0 then
                local cCount = #demand.craftJobs
                SafeAddDoubleLine(tooltip, "|cffffd700Craft Queue:|r",
                    string.format("|cff00ff00%d to craft|r |cff888888(%d %s)|r", demand.toCraft, cCount, cCount == 1 and "job" or "jobs"))
                hasHiddenDetails = true
                addedLines = true
            end
        else
            if demand.needed > 0 then
                SafeAddLine(tooltip, "|cffffd700Pending Craft Requirements:|r")
                for _, req in ipairs(demand.jobsNeeding) do
                    local j = req.job
                    local title = j.name .. " x" .. j.quantity
                    if j.kind == "service" and j.customer then
                        title = title .. " |cff77ddbb(Customer: " .. j.customer .. ")|r"
                    end
                    SafeAddDoubleLine(tooltip, "  " .. title .. ":", string.format("|cffffffffNeed %d|r", req.needed))
                end
                addedLines = true
            end
            if demand.toCraft > 0 then
                SafeAddLine(tooltip, "|cffffd700Pending Craft Output:|r")
                for _, craft in ipairs(demand.craftJobs) do
                    local j = craft.job
                    SafeAddDoubleLine(tooltip, "  " .. j.name .. ":",
                        string.format("|cff00ff00%d remaining of %d|r", craft.remaining, j.outputQty or j.quantity or 1))
                end
                addedLines = true
            end
        end
    end

    -- 3. Modifier Hint
    if not isShift and (hasHiddenDetails or (MarketSync.HasExtraTooltipDetails and MarketSync.HasExtraTooltipDetails(id, link))) then
        local modName = MarketSyncDB and MarketSyncDB.TooltipModifier or "SHIFT"
        local hintKey = (modName == "CTRL" and "Ctrl") or (modName == "ALT" and "Alt") or "Shift"
        SafeAddLine(tooltip, string.format("|cff777777<Hold %s for full details>|r", hintKey))
        addedLines = true
    end

    if addedLines and tooltip.Show then tooltip:Show() end
end
function T.InstallTooltips()
    if T.tooltipInstalled then return end
    T.tooltipInstalled = true
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then tip:HookScript("OnTooltipCleared", function(self)
            self.MarketSyncOwnershipItem = nil
            self.MarketSyncOwnershipShift = nil
            self.MarketSyncProcessingItem = nil
            self.MarketSyncProcessingShift = nil
        end) end
    end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip)
    else
        for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do if tip and tip.HookScript then tip:HookScript("OnTooltipSetItem", Tooltip) end end
    end
end
local frame = CreateFrame("Frame"); T.eventFrame = frame
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "TRADE_SHOW", "TRADE_UPDATE", "TRADE_MONEY_CHANGED",
    "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_REQUEST_CANCEL", "TRADE_CLOSED", "CHAT_MSG_SYSTEM", "ADDON_LOADED", "CHAT_MSG_LOOT", "MODIFIER_STATE_CHANGED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        pcall(frame.RegisterEvent, frame, event)
    end
end
local snapshotScheduledAt = 0
local snapshotPending = false

function T.RunSnapshot(immediate)
    snapshotPending = false
    snapshotScheduledAt = 0
    T.CaptureMail()
    if MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled() then
        local p, bags = T.vendor, BagItems(0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
        if p and bags and T.lastBags and time() <= p.expires then
            local key = I.Key(p.link)
            local before, after = T.lastBags[key] and T.lastBags[key].qty or 0, bags[key] and bags[key].qty or 0
            if after - before == p.qty and (T.lastMoney or 0) - GetMoney() == p.paid then
                I.Record("vendor purchase", { incoming = { { link = p.link, qty = p.qty } }, cashOut = p.paid,
                    actualCost = p.paid, evidence = "matching bag and money change" })
                T.vendor = nil
            end
        end
        local sale = T.sale
        if sale and bags and T.lastBags and time() <= sale.expires then
            local before, after = T.lastBags[sale.key] and T.lastBags[sale.key].qty or 0, bags[sale.key] and bags[sale.key].qty or 0
            if before - after == sale.qty and GetMoney() - (T.lastMoney or 0) == sale.paid then
                I.Record("vendor sale", { outgoing = { { link = sale.link, qty = sale.qty } }, cashIn = sale.paid, evidence = "matching bag and money change" })
                T.sale = nil
            end
        end
    end
    T.CaptureBags()
    if T.bankOpen then T.CaptureBank() end
end

function T.ScheduleSnapshot()
    if not (C_Timer and C_Timer.After) then
        T.RunSnapshot(true)
        return
    end
    local now = GetTime and GetTime() or time()
    snapshotScheduledAt = now + 0.35
    if not snapshotPending then
        snapshotPending = true
        local function Step()
            local current = GetTime and GetTime() or time()
            local remaining = snapshotScheduledAt - current
            if remaining <= 0.05 then
                T.RunSnapshot(false)
            else
                C_Timer.After(math.max(0.05, remaining), Step)
            end
        end
        C_Timer.After(0.35, Step)
    end
end

frame:SetScript("OnEvent", function(_, event, message, target)
    local isLedger = MarketSync.IsLedgerEnabled and MarketSync.IsLedgerEnabled()
    if event == "PLAYER_LOGIN" then
        T.InstallHooks(); T.InstallTooltips(); T.CaptureBags()
        if isLedger and I.SeedObservedStock then I.SeedObservedStock() end
    elseif event == "ADDON_LOADED" then T.InstallHooks()
    elseif event == "BANKFRAME_OPENED" then T.bankOpen = true; T.CaptureBank()
    elseif event == "BANKFRAME_CLOSED" then
        T.bankOpen = false
        if isLedger and I.SeedObservedStock then I.SeedObservedStock() end
    elseif event == "MAIL_SHOW" then T.mailOpen = true; T.CaptureMail()
    elseif event == "MAIL_CLOSED" then T.mailOpen = false; T.collections = nil
    elseif event == "MAIL_INBOX_UPDATE" then After(T.CaptureMail)
    elseif event == "MAIL_FAILED" then T.send = nil; T.collections = nil
    elseif event == "MAIL_SEND_SUCCESS" and T.send then
        local p = T.send; T.send = nil
        if isLedger then
            I.Record("mail sent", { outgoing = p.items, cashOut = p.money, fee = p.fee, counterparty = p.recipient,
                evidence = "MAIL_SEND_SUCCESS", metadata = { codRequested = p.cod, subject = p.subject } })
        end
        T.sendMoney, T.sendCOD = 0, 0
    elseif event == "TRADE_SHOW" then
        if isLedger then T.trade = Trade() end
    elseif event == "TRADE_REQUEST_CANCEL" then T.trade = nil
    elseif event == "TRADE_ACCEPT_UPDATE" then
        if isLedger then
            T.trade = Trade()
            if T.trade then
                local mSafe = (not MarketSync.IsSecretValue or not MarketSync.IsSecretValue(message)) and message == 1
                local tSafe = (not MarketSync.IsSecretValue or not MarketSync.IsSecretValue(target)) and target == 1
                T.trade.accepted = mSafe and tSafe
            end
        end
    elseif event == "TRADE_UPDATE" or event == "TRADE_MONEY_CHANGED" or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" then
        if isLedger then T.trade = Trade() end
    elseif event == "CHAT_MSG_SYSTEM" then
        local isSafe = MarketSync.IsSafeString and MarketSync.IsSafeString(message) or (type(message) == "string")
        if isSafe and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
            local p = T.trade; T.trade = nil
            if isLedger and p and p.accepted and time() <= p.expires then
                p.evidence = "server trade success"; I.Record("trade", p)
            end
        end
    elseif event == "CHAT_MSG_LOOT" then
        local isSafe = MarketSync.IsSafeString and MarketSync.IsSafeString(message) or (type(message) == "string")
        if isSafe and isLedger and MarketSync.CraftLedger and MarketSync.CraftLedger.ParseReceipt then
            local id, qty, link = MarketSync.CraftLedger.ParseReceipt(message, { LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE })
            if id and link then
                I.Record("loot received", { incoming = { { link = link, qty = qty } }, evidence = "player loot receipt" })
            end
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        local isSafe = MarketSync.IsSafeString and MarketSync.IsSafeString(message) or (type(message) == "string")
        if isSafe and (message:find("SHIFT") or message:find("CTRL") or message == "LSHIFT" or message == "RSHIFT") then
            if MarketSync.RefreshActiveTooltip then MarketSync.RefreshActiveTooltip() end
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LOGOUT" then
        if event == "PLAYER_LOGOUT" then
            T.RunSnapshot(true)
        else
            T.ScheduleSnapshot()
        end
    end
end)
