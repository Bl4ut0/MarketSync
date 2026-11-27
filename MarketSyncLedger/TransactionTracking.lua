-- Optional Ledger observers. Only confirmed client events commit transactions.
local _, companion = ...
local I = MarketSync.ItemLedger
local Inventory = MarketSync.InventoryTracking
local T = { hooks = {}, mailOpen = false }
MarketSync.LedgerTracking = T

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
    local out, signatures = {}, {}
    for index = 1, GetInboxNumItems() or 0 do
        local mail = ReadMail(index); out[index] = mail
        signatures[mail.signature] = (signatures[mail.signature] or 0) + 1
    end
    return out, signatures
end
function T.CaptureMail()
    if not MarketSync.IsLedgerEnabled() or not T.mailOpen or not (GetInboxNumItems and GetInboxHeaderInfo and GetInboxItem) then return end
    local batch = T.collections
    if not batch then return end
    local _, signatures = Mails()
    for index = #batch.pending, 1, -1 do
        local p = batch.pending[index]
        local changed = (signatures[p.mail.signature] or 0) < p.matches
        local confirmed = changed and ((p.item and ItemCount(p.item.itemID) >= p.threshold)
            or (not p.item and GetMoney() >= p.threshold))
        if p.item and p.mail.cod > 0 and GetMoney() > p.money - p.mail.cod then confirmed = false end
        if confirmed then
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
            table.remove(batch.pending, index)
        elseif time() > p.expires then table.remove(batch.pending, index) end
    end
    if #batch.pending == 0 then T.collections = nil end
end
local function Collect(index, slot)
    if not MarketSync.IsLedgerEnabled() then return end
    if not T.mailOpen or not (GetInboxNumItems and GetInboxHeaderInfo and GetInboxItem) then return end
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
        matches = math.max(1, signatures[mail.signature] or 0), token = token, expires = time() + 10 }
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
    if not (GetTradePlayerItemInfo and GetTradeTargetItemInfo) then return end
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
    if not MarketSync.IsLedgerEnabled() then return end
    Hook("TakeInboxItem", Collect)
    Hook("TakeInboxMoney", function(index) Collect(index) end)
    Hook("SetSendMailMoney", function(amount) if MarketSync.IsLedgerEnabled() then T.sendMoney = amount end end)
    Hook("SetSendMailCOD", function(amount) if MarketSync.IsLedgerEnabled() then T.sendCOD = amount end end)
    Hook("SendMail", function(recipient, subject)
        if not MarketSync.IsLedgerEnabled() then return end
        T.send = { recipient = recipient, subject = subject, items = Draft(), money = T.sendMoney or 0,
            cod = T.sendCOD or 0, fee = GetSendMailPrice and GetSendMailPrice() or 0 }
    end)
    Hook("BuyMerchantItem", function(index, quantity)
        if not MarketSync.IsLedgerEnabled() then return end
        if not Inventory.IsEnabled() then return end
        if not (GetMerchantItemInfo and GetMerchantItemLink) or T.vendor then return end
        local _, _, price, stack, _, _, extended = GetMerchantItemInfo(index)
        local link = GetMerchantItemLink(index); local _, id = I.Key(link)
        if not id or not price or extended then return end
        local qty = tonumber(quantity) or stack or 1
        -- The hook runs after the request; keep the expected cost, then confirm
        -- through the subsequent inventory update before recording it.
        T.vendor = { link = link, itemID = id, qty = qty, paid = price * qty / math.max(1, stack or 1), expires = time() + 5 }
    end)
    local function Sell(bag, slot)
        if not MarketSync.IsLedgerEnabled() then return end
        if not Inventory.IsEnabled() then return end
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

Inventory.OnBagsCaptured = function(bags, slots)
    if not MarketSync.IsLedgerEnabled() then return end
    local p = T.vendor
    if p and T.lastBags then
        local key = I.Key(p.link)
        local before, after = T.lastBags[key] and T.lastBags[key].qty or 0, bags[key] and bags[key].qty or 0
        if time() > p.expires then
            T.vendor = nil
        elseif after - before == p.qty and (T.lastMoney or 0) - GetMoney() == p.paid then
            I.Record("vendor purchase", { incoming = { { link = p.link, qty = p.qty } }, cashOut = p.paid,
                actualCost = p.paid, evidence = "matching bag and money change" })
            T.vendor = nil
        end
    end
    local sale = T.sale
    if sale and T.lastBags then
        local before, after = T.lastBags[sale.key] and T.lastBags[sale.key].qty or 0, bags[sale.key] and bags[sale.key].qty or 0
        if time() > sale.expires then
            T.sale = nil
        elseif before - after == sale.qty and GetMoney() - (T.lastMoney or 0) == sale.paid then
            I.Record("vendor sale", { outgoing = { { link = sale.link, qty = sale.qty } }, cashIn = sale.paid,
                evidence = "matching bag and money change" })
            T.sale = nil
        end
    end
    T.lastBags, T.lastMoney, T.slots = bags, GetMoney and GetMoney() or 0, slots
end

Inventory.OnSnapshot = function(storage, items, options)
    if MarketSync.IsLedgerEnabled() then I.Snapshot(storage, items, options) end
end

Inventory.OnBankClosed = function()
    if MarketSync.IsLedgerEnabled() then I.SeedObservedStock() end
end

Inventory.OnScanningDisabled = function()
    T.vendor, T.sale, T.lastBags, T.lastMoney, T.slots = nil, nil, nil, nil, nil
end

Inventory.AddTooltipDetails = function(tooltip, id, myOwner, isShift, hasStock)
    if not MarketSync.IsLedgerEnabled() then return end
    local addedLines, hasHiddenDetails = false, false
    if isShift and hasStock and myOwner then
        local key = I.Key(id)
        local paid, units = 0, 0
        for _, lot in ipairs(I.Store().lots) do
            if lot.owner == myOwner and lot.key == key and lot.qty > 0 and lot.unitCost then
                paid = paid + lot.unitCost * lot.qty
                units = units + lot.qty
            end
        end
        if units > 0 then
            local avg = paid / units
            local formatted = MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(avg)
                or (MarketSync.FormatMoney and MarketSync.FormatMoney(avg) or (math.floor(avg) .. "c"))
            tooltip:AddDoubleLine("  |cff888888Cost Basis (FIFO):|r",
                string.format("%s/ea |cff888888(%d units)|r", formatted, units))
            addedLines = true
        end
    end

    local showDemand = companion and companion.GetDB().showCraftDemand
    if not companion then showDemand = MarketSyncDB.EnableTooltipCraftDemand ~= false end
    local L = MarketSync.CraftLedger
    local demand = showDemand and L and L.GetItemDemand and L.GetItemDemand(id)
    if demand then
        if not isShift then
            if demand.needed > 0 then
                local jCount = #demand.jobsNeeding
                local resText = demand.reserved > 0 and string.format(" · %d reserved", demand.reserved) or ""
                tooltip:AddDoubleLine( "|cffffd700Pending Crafts:|r",
                    string.format("|cffffffffNeed %d|r |cff888888(%d %s%s)|r", demand.needed, jCount, jCount == 1 and "job" or "jobs", resText))
                hasHiddenDetails = true
                addedLines = true
            end
            if demand.toCraft > 0 then
                local cCount = #demand.craftJobs
                tooltip:AddDoubleLine( "|cffffd700Craft Queue:|r",
                    string.format("|cff00ff00%d to craft|r |cff888888(%d %s)|r", demand.toCraft, cCount, cCount == 1 and "job" or "jobs"))
                hasHiddenDetails = true
                addedLines = true
            end
        else
            if demand.needed > 0 then
                tooltip:AddLine( "|cffffd700Pending Craft Requirements:|r")
                for _, req in ipairs(demand.jobsNeeding) do
                    local j = req.job
                    local title = j.name .. " x" .. j.quantity
                    if j.kind == "service" and j.customer then
                        title = title .. " |cff77ddbb(Customer: " .. j.customer .. ")|r"
                    end
                    tooltip:AddDoubleLine( "  " .. title .. ":", string.format("|cffffffffNeed %d|r", req.needed))
                end
                addedLines = true
            end
            if demand.toCraft > 0 then
                tooltip:AddLine( "|cffffd700Pending Craft Output:|r")
                for _, craft in ipairs(demand.craftJobs) do
                    local j = craft.job
                    tooltip:AddDoubleLine( "  " .. j.name .. ":",
                        string.format("|cff00ff00%d remaining of %d|r", craft.remaining, j.outputQty or j.quantity or 1))
                end
                addedLines = true
            end
        end
    end

    return addedLines, hasHiddenDetails
end

local frame = CreateFrame("Frame")
T.eventFrame = frame
for _, event in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
    "TRADE_SHOW", "TRADE_UPDATE", "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_ACCEPT_UPDATE", "TRADE_REQUEST_CANCEL", "CHAT_MSG_SYSTEM", "ADDON_LOADED", "CHAT_MSG_LOOT" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        pcall(frame.RegisterEvent, frame, event)
    end
end

frame:SetScript("OnEvent", function(_, event, message, target)
    if event == "MAIL_SHOW" then T.mailOpen = true end
    if event == "MAIL_CLOSED" then T.mailOpen = false; T.collections = nil end
    if not MarketSync.IsLedgerEnabled() then return end
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        T.InstallHooks()
        if event == "PLAYER_LOGIN" and Inventory.IsEnabled() then I.SeedObservedStock() end
    elseif event == "MAIL_INBOX_UPDATE" then
        After(T.CaptureMail)
    elseif event == "MAIL_FAILED" then T.send = nil; T.collections = nil
    elseif event == "MAIL_SEND_SUCCESS" and T.send then
        local p = T.send; T.send = nil
        I.Record("mail sent", { outgoing = p.items, cashOut = p.money, fee = p.fee, counterparty = p.recipient,
            evidence = "MAIL_SEND_SUCCESS", metadata = { codRequested = p.cod, subject = p.subject } })
        T.sendMoney, T.sendCOD = 0, 0
    elseif event == "TRADE_SHOW" then
        T.trade = Trade()
    elseif event == "TRADE_REQUEST_CANCEL" then T.trade = nil
    elseif event == "TRADE_ACCEPT_UPDATE" then
        T.trade = Trade()
        if T.trade then
            local mSafe = (not MarketSync.IsSecretValue or not MarketSync.IsSecretValue(message)) and message == 1
            local tSafe = (not MarketSync.IsSecretValue or not MarketSync.IsSecretValue(target)) and target == 1
            T.trade.accepted = mSafe and tSafe
        end
    elseif event == "TRADE_UPDATE" or event == "TRADE_MONEY_CHANGED" or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" then
        T.trade = Trade()
    elseif event == "CHAT_MSG_SYSTEM" then
        local isSafe = type(message) == "string"
        if MarketSync.IsSafeString then isSafe = MarketSync.IsSafeString(message) end
        if isSafe and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
            local p = T.trade; T.trade = nil
            if p and p.accepted and time() <= p.expires then
                p.evidence = "server trade success"; I.Record("trade", p)
            end
        end
    elseif event == "CHAT_MSG_LOOT" then
        local isSafe = type(message) == "string"
        if MarketSync.IsSafeString then isSafe = MarketSync.IsSafeString(message) end
        if isSafe and MarketSync.CraftLedger and MarketSync.CraftLedger.ParseReceipt then
            local id, qty, link = MarketSync.CraftLedger.ParseReceipt(message, { LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE })
            if id and link then
                I.Record("loot received", { incoming = { { link = link, qty = qty } }, evidence = "player loot receipt" })
            end
        end
    end
end)

function T.Reset()
    Inventory.OnScanningDisabled()
    T.trade, T.send, T.sendMoney, T.sendCOD, T.collections = nil, nil, nil, nil, nil
end
