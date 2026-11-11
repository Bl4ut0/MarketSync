-- Character-owned craft jobs. Receipts are immutable facts, separate from plans.
MarketSync = MarketSync or {}
local L = {}
MarketSync.CraftLedger = L
local function Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k, v in pairs(t) do out[k] = Copy(v) end; return out
end
local function Owner() return (UnitName("player") or "Player") .. "-" .. (GetRealmName() or "Realm") end
local function Store()
    local db = MarketSync.GetRealmDB()
    db.CraftLedger = db.CraftLedger or { nextID = 0, jobs = {} }
    return db.CraftLedger
end
local function Changed()
    if L.Refresh then L.Refresh() end
    if MarketSync.AHSidecar and MarketSync.AHSidecar.UpdateCraftView then MarketSync.AHSidecar.UpdateCraftView() end
end
function L.Get(id) return Store().jobs[id] end
function L.List(history)
    local out = {}
    for _, job in pairs(Store().jobs) do
        if job.owner == Owner() and (job.status == "Crafted") == (history == true) then out[#out + 1] = job end
    end
    table.sort(out, function(a,b) return a.id < b.id end); return out
end
function L.Remaining(job)
    local out = {}
    for id, material in pairs(job.plan.buys) do
        local qty = math.max(0, material.qty - ((job.purchased[id] or {}).qty or 0) - ((job.supplied or {})[id] or 0))
        if qty > 0 then local entry = Copy(material); entry.qty = qty; out[id] = entry end
    end
    return out
end
function L.SetService(id, customer)
    local job = L.Get(id)
    customer = type(customer) == "string" and customer:match("^%s*(.-)%s*$")
    if not job or job.owner ~= Owner() or job.status == "Crafted" or not customer or customer == "" then return false end
    job.kind, job.customer = "service", customer; Changed(); return true
end
function L.FindShoppingList(name)
    for _, job in ipairs(L.List()) do if job.shoppingName==name then return job end end
end
function L.GetItemDemand(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local neededTotal, reservedTotal = 0, 0
    local jobsNeeding = {}
    for _, job in ipairs(L.List()) do
        local remaining = L.Remaining(job)
        if remaining and remaining[itemID] and remaining[itemID].qty > 0 then
            local qty = remaining[itemID].qty
            neededTotal = neededTotal + qty
            jobsNeeding[#jobsNeeding + 1] = {
                job = job,
                needed = qty,
            }
        end
    end
    if MarketSync.ItemLedger and MarketSync.ItemLedger.Store and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then
        local key = MarketSync.ItemLedger.Key(itemID)
        for _, r in pairs(MarketSync.ItemLedger.Store().reservations or {}) do
            if r.key == key then
                for _, part in ipairs(r.parts or {}) do
                    reservedTotal = reservedTotal + (part.qty or 0)
                end
            end
        end
    end
    local toCraftTotal = 0
    local craftJobs = {}
    for _, job in ipairs(L.List()) do
        if job.itemID == itemID then
            local remain = math.max(0, (job.outputQty or job.quantity or 1) - (job.craftedQty or 0))
            if remain > 0 then
                toCraftTotal = toCraftTotal + remain
                craftJobs[#craftJobs + 1] = { job = job, remaining = remain }
            end
        end
    end
    if neededTotal == 0 and toCraftTotal == 0 then return nil end
    return {
        needed = neededTotal,
        reserved = reservedTotal,
        jobsNeeding = jobsNeeding,
        toCraft = toCraftTotal,
        craftJobs = craftJobs,
    }
end
local function SyncShopping(job)
    local F = MarketSync.Favorites
    if job.shoppingName then F.DeleteList(job.shoppingName); job.shoppingName = nil end
    if job.status == "Crafted" then return end
    local remaining = L.Remaining(job)
    job.status = next(remaining) and "Shopping" or "Purchased"
    if not next(remaining) then return end
    -- Include owner and stable ID to avoid overwriting user lists or another job.
    local base = job.name .. " x" .. job.quantity .. " [Craft " .. job.owner .. ":" .. job.id .. "]"
    local name, n = base, 1
    while MarketSyncDB.Favorites and MarketSyncDB.Favorites[name] do n = n + 1; name = base .. " " .. n end
    F.CreateList(name); job.shoppingName = name
    for id, material in pairs(remaining) do F.AddToList(name, id); F.SetQuantity(name, id, material.qty) end
end
L.RefreshShopping = SyncShopping
function L.Save(recipe, options, id)
    options = options or {}
    if not recipe or type(recipe.mats) ~= "table" then return nil, "Recipe materials are unavailable." end
    local job = id and L.Get(id)
    if id and (not job or job.owner ~= Owner() or job.status == "Crafted") then return nil, "Only your pending crafts can be updated." end
    local quantity = math.max(1, math.floor(tonumber(options.quantity) or 1))
    local request = { recipe = Copy(recipe), quantity = quantity, choices = Copy(options.choices or {}), selectedBuys = Copy(options.selectedBuys or {}) }
    local plan = MarketSync.BuildCraftPurchasePlan(request)
    if #plan.recipes == 0 then return nil, "Recipe materials are unavailable." end
    if job and job.craftedQty > (plan.recipes[1].outputQty or quantity) then return nil, "Quantity cannot be below the amount already crafted." end
    if not job then
        local store = Store(); store.nextID = store.nextID + 1
        job = { id = store.nextID, owner = Owner(), purchased = {}, receipts = {}, sales = {}, createdAt = time(), craftedQty = 0 }
        store.jobs[job.id] = job
    end
    job.recipe, job.quantity, job.choices, job.selectedBuys = request.recipe, quantity, request.choices, request.selectedBuys
    job.name, job.itemID, job.plan = recipe.name or "Craft", tonumber(recipe.outputItemID), plan
    job.manualCraftOnly = not job.itemID
    job.outputQty = plan.recipes[1].outputQty or quantity
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then MarketSync.ItemLedger.UpdateReservations(job) end
    job.updatedAt = time(); SyncShopping(job); Changed(); return job
end
function L.RecordPurchase(itemID, quantity, totalPaid, receiptID, targetID)
    itemID, quantity, totalPaid = tonumber(itemID), tonumber(quantity), tonumber(totalPaid)
    if not targetID and MarketSync.PurchaseList then
        targetID = MarketSync.PurchaseList.ReceiptTarget(itemID, quantity, totalPaid)
    end
    if not itemID or not quantity or quantity <= 0 or quantity % 1 ~= 0 or not totalPaid or totalPaid < 0 then return false end
    local store = Store(); store.receiptIDs = store.receiptIDs or {}
    if receiptID and store.receiptIDs[receiptID] then return false end
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then
        local _, state = MarketSync.ItemLedger.Record("auction purchase", { incoming = { { itemID = itemID, qty = quantity } },
            cashOut = totalPaid, actualCost = totalPaid, inTransit = true, token = receiptID and ("purchase:" .. receiptID),
            evidence = receiptID and "purchase receipt" or "confirmed purchase or manual receipt" })
        if state == "duplicate" then return false end
    end
    local available, allocated = quantity, 0
    for _, job in ipairs(L.List()) do
        if not targetID or job.id == targetID then
            local remaining = L.Remaining(job)[itemID]
            local used = math.min(available, remaining and remaining.qty or 0)
            if used > 0 then
                local paid = math.floor(totalPaid * (allocated + used) / quantity) - math.floor(totalPaid * allocated / quantity)
                local p = job.purchased[itemID] or { qty = 0, paid = 0 }
                p.qty, p.paid = p.qty + used, p.paid + paid; job.purchased[itemID] = p
                job.receipts[#job.receipts + 1] = { itemID = itemID, qty = used, paid = paid, at = time(), id = receiptID }
                available, allocated = available - used, allocated + used; SyncShopping(job)
            end
        end
    end
    if allocated > 0 then if receiptID then store.receiptIDs[receiptID] = true end; Changed(); return true end
    return false
end
function L.Complete(id, quantity)
    local job = L.Get(id)
    if not job or job.owner ~= Owner() or job.status ~= "Purchased" then return false end
    local qty = tonumber(quantity) or (job.outputQty - job.craftedQty)
    if qty <= 0 or qty ~= math.floor(qty) then return false end
    qty = math.min(qty, job.outputQty - job.craftedQty)
    job.craftedQty = math.min(job.outputQty, job.craftedQty + qty)
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then
        MarketSync.ItemLedger.RecordCraft(job, qty)
        if job.craftedQty >= job.outputQty then
            local covered
            local paid, unknown
            paid, unknown, covered = MarketSync.ItemLedger.ReservedCost(job.id)
            job.stockCost = (job.stockCost or 0) + paid
            job.unknownStockCost = job.unknownStockCost or unknown
            for id, material in pairs(job.plan.provided or {}) do
                if (covered[id] or 0) + ((job.stockCoverage or {})[id] or 0) + ((job.supplied or {})[id] or 0) < material.qty then job.unknownStockCost = true end
            end
            MarketSync.ItemLedger.Release(job.id, true)
        end
    end
    if job.craftedQty >= job.outputQty then job.status = "Crafted"; job.completedAt = time(); SyncShopping(job) end
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then MarketSync.ItemLedger.UpdateCraftCosts(job) end
    Changed(); return true
end
function L.RecordSale(id, quantity, gross, fees, saleID)
    local job = L.Get(id)
    quantity, gross, fees = tonumber(quantity), tonumber(gross), tonumber(fees) or 0
    if not job or not job.itemID or job.kind == "service" or job.owner ~= Owner() or job.status ~= "Crafted" or not quantity or quantity <= 0 or quantity % 1 ~= 0 or not gross or gross < 0 or fees < 0 or fees > gross then return false end
    local sold = 0
    for _, sale in ipairs(job.sales) do if saleID and sale.id == saleID then return false end; sold = sold + sale.qty end
    if sold + quantity > job.craftedQty then return false end
    job.sales[#job.sales + 1] = { qty = quantity, gross = gross, fees = fees, at = time(), id = saleID }
    Changed(); return true
end
function L.Totals(job)
    local result = { paid = 0, sold = 0, gross = 0, fees = 0 }
    for _, receipt in ipairs(job.receipts) do result.paid = result.paid + receipt.paid end
    for _, sale in ipairs(job.sales) do result.sold = result.sold + sale.qty; result.gross = result.gross + sale.gross; result.fees = result.fees + sale.fees end
    result.net = result.gross - result.fees
    result.paid = result.paid + (job.stockCost or 0)
    result.unknownCost = job.unknownStockCost == true
    if next(job.plan.provided or {}) and job.stockCost == nil then result.unknownCost = true end
    if job.kind == "service" and MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then
        local service = MarketSync.ItemLedger.ServiceTotals(job)
        result.gross, result.net, result.fees = service.earned, service.earned - service.earnedRefunds, service.expenses
        result.deposits, result.delivered = service.deposits - service.refunds, service.delivered
        result.profit = not result.unknownCost and result.net - result.paid - result.fees or nil
        if job.status ~= "Crafted" then result.profit = nil end
        return result
    end
    result.profit = result.sold > 0 and result.net - result.paid * result.sold / job.outputQty or nil
    if result.unknownCost then result.profit = nil end

    -- Compute opportunity value of raw materials vs. realized sales
    local matMarketTotal = 0
    local getPrice = MarketSync.GetAuctionPrice
    for _, mat in ipairs((job.recipe and job.recipe.mats) or {}) do
        local mQty = (tonumber(mat.qty) or 0) * (job.quantity or 1)
        local unitQuote = (job.plan and job.plan.buys and job.plan.buys[mat.itemID] and job.plan.buys[mat.itemID].unitPrice)
            or (getPrice and tonumber(getPrice(mat.itemID))) or 0
        matMarketTotal = matMarketTotal + (unitQuote * mQty)
    end
    result.matMarketValue = matMarketTotal
    result.matNetAH = math.floor(matMarketTotal * 0.95)
    if result.sold > 0 and matMarketTotal > 0 and job.outputQty and job.outputQty > 0 then
        local scaledMatNet = result.matNetAH * result.sold / job.outputQty
        result.valueGainedVsMats = math.floor(result.net - scaledMatNet + 0.5)
    end
    return result
end
function L.Remove(id)
    local job = L.Get(id); if not job or job.owner ~= Owner() then return false end
    if job.shoppingName then MarketSync.Favorites.DeleteList(job.shoppingName) end
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then MarketSync.ItemLedger.Release(id) end
    Store().jobs[id] = nil; Changed(); return true
end
function L.CorrectPurchase(id, itemID, quantity, totalPaid)
    local job = L.Get(id)
    itemID, quantity, totalPaid = tonumber(itemID), tonumber(quantity), tonumber(totalPaid)
    if not job or job.owner ~= Owner() or not itemID or not quantity or quantity < 0 or quantity % 1 ~= 0
        or not totalPaid or totalPaid < 0 or totalPaid % 1 ~= 0 or (quantity == 0 and totalPaid ~= 0) then return false end
    local old = job.purchased[itemID] or { qty = 0, paid = 0 }
    job.receipts[#job.receipts + 1] = { itemID = itemID, qty = quantity - old.qty, paid = totalPaid - old.paid, at = time(), correction = true }
    job.purchased[itemID] = { qty = quantity, paid = totalPaid }
    if job.status ~= "Crafted" then SyncShopping(job) end
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then MarketSync.ItemLedger.UpdateCraftCosts(job) end
    Changed(); return true
end
function L.CorrectCrafted(id, quantity)
    local job = L.Get(id); quantity = tonumber(quantity)
    if not job or job.owner ~= Owner() or not quantity or quantity < 0 or quantity % 1 ~= 0 or quantity > job.outputQty then return false end
    local sold = 0; for _, sale in ipairs(job.sales) do sold = sold + sale.qty end
    if quantity < math.max(sold, job.deliveredQty or 0) then return false end
    job.corrections = job.corrections or {}
    job.corrections[#job.corrections + 1] = { at = time(), previous = job.craftedQty, quantity = quantity }
    if quantity < job.craftedQty then job.unknownStockCost = true end
    job.craftedQty = quantity
    if quantity == job.outputQty then job.status = "Crafted"; job.completedAt = time()
    else job.status = "Purchased"; job.completedAt = nil end
    SyncShopping(job)
    if MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then MarketSync.ItemLedger.UpdateCraftCosts(job) end
    Changed(); return true
end
function L.ImportLegacyPlans()
    local store=Store(); store.imported=store.imported or {}; local count=0
    for _, set in ipairs(MarketSync.ListProcessingCraftSets and MarketSync.ListProcessingCraftSets() or {}) do
        for _, id in ipairs(set.itemIDs or {}) do
            local key=Owner()..":"..set.name..":"..id
            local recipe=(set.recipes or {})[id] or MarketSync.GetRecipeForOutput(id)
            if recipe and not store.imported[key] then
                local job=L.Save(recipe,{quantity=(set.quantities or {})[id] or 1, choices=set.choices,selectedBuys=set.selectedBuys})
                if job then store.imported[key]=true; count=count+1 end
            end
        end
    end
    return count
end

-- Confirm native purchases using the server success message, never the click.
function L.ExpectPurchase(itemID, qty, paid)
    L.pendingPurchase = { itemID = itemID, qty = qty, paid = paid, expires = GetTime() + 10 }
end
local function ItemCount(id)
    local fn = C_Item and C_Item.GetItemCount or GetItemCount
    return fn and fn(id, false) or nil
end
function L.BeginCraft(id, count)
    if not id then L.expectedCraft = nil; return end
    local recipe = MarketSync.GetRecipeForOutput and MarketSync.GetRecipeForOutput(id)
    L.expectedCraft = { itemID = id, expires = GetTime() + 600, observedCount = ItemCount(id),
        remaining = math.max(1, tonumber(count) or 1) * math.max(1, recipe and recipe.outputQty or 1) }
end
function L.ParseReceipt(message, formats)
    if type(message) ~= "string" then return nil end
    local function Escape(text) return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end
    for _, format in pairs(formats or {}) do
        local pattern, kinds, cursor = "^", {}, 1
        while true do
            local first, last = format:find("%%[%d%$]*[sd]", cursor)
            if not first then pattern = pattern .. Escape(format:sub(cursor)) .. "$"; break end
            pattern = pattern .. Escape(format:sub(cursor, first - 1))
            local kind = format:sub(last, last); kinds[#kinds + 1] = kind
            pattern = pattern .. (kind == "d" and "(%d+)" or "(.-)"); cursor = last + 1
        end
        local values = { message:match(pattern) }
        if #values > 0 then
            local id, qty, link
            for index, value in ipairs(values) do
                if kinds[index] == "d" then qty = tonumber(value)
                elseif value:find("item:", 1, true) then id = tonumber(value:match("item:(%d+)")); link = value end
            end
            if id then return id, qty or 1, link end
        end
    end
end
function L.ConfirmCraftOutput(id, reported)
    local expected = L.expectedCraft
    if not expected or expected.itemID ~= id or expected.observedCount == nil or expected.remaining <= 0 then return end
    local function Confirm()
        if L.expectedCraft ~= expected or GetTime() > expected.expires then return end
        local count = ItemCount(id)
        local qty = count and math.min(reported, expected.remaining, math.max(0, count - expected.observedCount)) or 0
        if qty <= 0 then return end
        expected.observedCount = expected.observedCount + qty; expected.remaining = expected.remaining - qty
        local unallocated = qty
        for _, job in ipairs(L.List()) do
            if job.itemID == id and job.status == "Purchased" and unallocated > 0 then
                local used = math.min(unallocated, job.outputQty - job.craftedQty)
                L.Complete(job.id, used); unallocated = unallocated - used
            end
        end
        if unallocated > 0 and MarketSync.ItemLedger and (not MarketSync.IsLedgerEnabled or MarketSync.IsLedgerEnabled()) then
            local candidates = {}
            for _, job in ipairs(L.List()) do
                local needed = ((job.plan.craftSteps or {})[id] or 0) - ((job.componentsCrafted or {})[id] or 0)
                if job.status == "Purchased" and needed >= unallocated then candidates[#candidates + 1] = job end
            end
            local recipe = MarketSync.GetRecipeForOutput and MarketSync.GetRecipeForOutput(id)
            if #candidates == 1 and recipe then MarketSync.ItemLedger.RecordComponent(candidates[1], recipe, id, unallocated)
            else MarketSync.ItemLedger.Record("crafted output", { incoming = { { itemID = id, qty = unallocated } }, evidence = "creation receipt and inventory confirmation", metadata = { ambiguousCraft = #candidates > 1 } }) end
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Confirm) else Confirm() end
end
local events = CreateFrame("Frame")
L.eventFrame = events
events:RegisterEvent("CHAT_MSG_SYSTEM"); events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("CHAT_MSG_LOOT"); events:RegisterEvent("AUCTION_HOUSE_CLOSED")
for _, event in ipairs({"COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR", "TRADE_SKILL_ITEM_CRAFTED_RESULT"}) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        pcall(events.RegisterEvent, events, event)
    end
end
events:SetScript("OnEvent", function(_, event, message, total)
    if event == "UI_ERROR_MESSAGE" or event == "AUCTION_HOUSE_CLOSED" or event == "COMMODITY_PURCHASE_FAILED" or event == "AUCTION_HOUSE_SHOW_ERROR" then L.pendingPurchase = nil; L.commodityQuote=nil; L.pendingAuctions={}; return end
    if event=="AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local isSafeKey = (not MarketSync.IsSecretValue or not MarketSync.IsSecretValue(message))
        if isSafeKey then
            local p=L.pendingAuctions and L.pendingAuctions[message]
            if p then L.pendingAuctions[message]=nil; if GetTime()<=p.expires then L.RecordPurchase(p.itemID,p.qty,p.paid) end end
        end
    end
    if event == "COMMODITY_PRICE_UPDATED" and L.commodityQuote then
        L.commodityQuote.paid=total
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local p=L.pendingPurchase
        if p and p.commodity and GetTime()<=p.expires then L.pendingPurchase=nil; L.RecordPurchase(p.itemID,p.qty,p.paid) end
    end
    if event == "CHAT_MSG_SYSTEM" then
        local isSafe = MarketSync.IsSafeString and MarketSync.IsSafeString(message) or (type(message) == "string")
        if isSafe then
            local p = L.pendingPurchase
            if p and not p.commodity and GetTime() <= p.expires and ERR_AUCTION_BID_PLACED and message == ERR_AUCTION_BID_PLACED then
                L.pendingPurchase = nil; L.RecordPurchase(p.itemID, p.qty, p.paid)
            end
        end
    elseif event == "CHAT_MSG_LOOT" and L.expectedCraft and GetTime() <= L.expectedCraft.expires then
        local isSafe = MarketSync.IsSafeString and MarketSync.IsSafeString(message) or (type(message) == "string")
        if isSafe then
            local id, qty = L.ParseReceipt(message, { LOOT_ITEM_CREATED_SELF, LOOT_ITEM_CREATED_SELF_MULTIPLE })
            if id == L.expectedCraft.itemID then L.ConfirmCraftOutput(id, qty) end
        end
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" and type(message) == "table" then
        if message.itemID and message.quantity and message.quantity > 0 then L.ConfirmCraftOutput(message.itemID, message.quantity) end
    end
end)
if hooksecurefunc and DoTradeSkill then
    hooksecurefunc("DoTradeSkill", function(index, count)
        local link = GetTradeSkillItemLink and GetTradeSkillItemLink(index)
        local id = link and tonumber(link:match("item:(%d+)"))
        L.BeginCraft(id, count)
    end)
end
if hooksecurefunc and PlaceAuctionBid then
    hooksecurefunc("PlaceAuctionBid",function(kind,index,amount)
        if kind~="list" or not GetAuctionItemInfo then return end
        local _,_,count,_,_,_,_,_,_,buyout,_,_,_,_,_,_,id=GetAuctionItemInfo(kind,index)
        local link=GetAuctionItemLink and GetAuctionItemLink(kind,index)
        id=tonumber(id) or (link and tonumber(link:match("item:(%d+)")))
        if id and tonumber(buyout) and buyout>0 and amount==buyout then L.ExpectPurchase(id,count,buyout) end
    end)
end
if hooksecurefunc and C_AuctionHouse and C_AuctionHouse.PlaceBid and C_AuctionHouse.GetAuctionInfoByID then
    hooksecurefunc(C_AuctionHouse,"PlaceBid",function(auctionID,amount)
        local info=C_AuctionHouse.GetAuctionInfoByID(auctionID)
        if not info or not info.itemKey or not info.buyoutAmount or info.buyoutAmount~=amount then return end
        local qty
        if C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo then
            for i=1,C_AuctionHouse.GetNumItemSearchResults(info.itemKey) do
                local result=C_AuctionHouse.GetItemSearchResultInfo(info.itemKey,i)
                if result and result.auctionID==auctionID then qty=result.quantity; break end
            end
        end
        if qty then
            L.pendingAuctions=L.pendingAuctions or {}
            L.pendingAuctions[auctionID]={itemID=info.itemKey.itemID,qty=qty,paid=amount,expires=GetTime()+10}
        end
    end)
end
if hooksecurefunc and C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    hooksecurefunc(C_TradeSkillUI,"CraftRecipe",function(recipeID,count)
        local link=C_TradeSkillUI.GetRecipeItemLink and C_TradeSkillUI.GetRecipeItemLink(recipeID)
        local id=link and tonumber(link:match("item:(%d+)"))
        L.BeginCraft(id,count)
    end)
end
if hooksecurefunc and C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase and C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse,"StartCommoditiesPurchase",function(itemID,qty)
        L.commodityQuote={itemID=itemID,qty=qty,expires=GetTime()+30}
    end)
    hooksecurefunc(C_AuctionHouse,"ConfirmCommoditiesPurchase",function(itemID,qty)
        local q=L.commodityQuote
        if q and q.itemID==itemID and q.qty==qty and q.paid and GetTime()<=q.expires then
            L.ExpectPurchase(itemID,qty,q.paid); L.pendingPurchase.commodity=true
        end
    end)
end
