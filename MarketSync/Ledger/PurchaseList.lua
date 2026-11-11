-- Quotes are plans, not receipts. Each user-confirmed stack is revalidated by
-- the scanner, then advances only on the server's buyout confirmation.
local P = { state = "idle" }
MarketSync.PurchaseList = P
local S = MarketSync.Scanner
local function Copy(row) local out={}; for k,v in pairs(row) do out[k]=v end; return out end
local function Changed() if P.Refresh then P.Refresh() end end
function P.SelectedJob()
    local sidecar=MarketSync.AHSidecar
    local name=sidecar and sidecar.GetSelectedShoppingListName and sidecar.GetSelectedShoppingListName()
    return name and MarketSync.CraftLedger.FindShoppingList(name)
end
function P.Build(needs, rows)
    local plan={entries={},materials={},total=0,units=0,extra=0,missing={},complete=true}
    local ids={}; for id in pairs(needs or {}) do ids[#ids+1]=id end; table.sort(ids)
    for _,id in ipairs(ids) do
        local need=needs[id].qty; local offers={}; local left=need
        for _,row in ipairs(rows or {}) do
            if row.itemID==id and (row.itemSuffix or 0)==0 and row.buyout and row.buyout>0
                and row.stackSize and row.stackSize>0 and row.query and row.page~=nil then offers[#offers+1]=row end
        end
        table.sort(offers,function(a,b)
            local x,y=a.buyout*b.stackSize,b.buyout*a.stackSize
            if x~=y then return x<y end
            if a.stackSize~=b.stackSize then return a.stackSize<b.stackSize end
            return (a.page or 0)<(b.page or 0)
        end)
        local material={itemID=id,need=need,units=0,cost=0,extra=0}
        local cheapest=offers[1] and offers[1].buyout/offers[1].stackSize
        for _,row in ipairs(offers) do
            if left<=0 then break end
            local count=math.min(math.ceil(left/row.stackSize),math.max(0,math.floor(tonumber(row.auctions) or 1)))
            for _=1,count do
                if #plan.entries>=500 then plan.complete=false; plan.reason="Purchase batch limit reached; split this craft into smaller quantities."; break end
                local entry=Copy(row); entry.needed=math.min(left,row.stackSize)
                entry.extra=row.stackSize-entry.needed; entry.unitCost=row.buyout/row.stackSize
                entry.higherTier=cheapest and entry.unitCost>cheapest
                plan.entries[#plan.entries+1]=entry
                left=left-entry.needed; material.units=material.units+row.stackSize; material.cost=material.cost+row.buyout
                material.extra=material.extra+entry.extra
            end
            if not plan.complete then break end
        end
        if left>0 then plan.missing[id]=left; plan.complete=false end
        plan.materials[#plan.materials+1]=material
        plan.total=plan.total+material.cost; plan.units=plan.units+material.units; plan.extra=plan.extra+material.extra
    end
    if #plan.entries==0 then plan.complete=false; plan.reason="No outstanding materials with usable live auctions." end
    return plan
end
function P.Preview(job)
    if not job then return nil,"Select a crafting-linked shopping list." end
    if not S or not S.IsLegacyAH then return nil,"This purchase queue uses the classic Search Auctions page." end
    if S.Active or not S.LiveSearchProgress or S.LiveSearchProgress.state~="complete" then return nil,"Finish scanning the selected list first." end
    if not S.LiveSearchAt or GetTime()-S.LiveSearchAt>120 then return nil,"Prices are stale. Scan the list again." end
    return P.Build(MarketSync.CraftLedger.Remaining(job),S.LiveSearchResults)
end
local function SameNeeds()
    local job=P.jobID and MarketSync.CraftLedger.Get(P.jobID)
    if not job or job.status=="Crafted" then return false end
    local remaining=MarketSync.CraftLedger.Remaining(job)
    for id,qty in pairs(P.expected or {}) do if ((remaining[id] or {}).qty or 0)~=qty then return false end end
    for id,buy in pairs(remaining) do if buy.qty~=(P.expected[id] or 0) then return false end end
    return true
end
function P.Pause(reason) P.state="paused"; P.message=reason; Changed() end
function P.Open(job)
    if P.state=="awaiting" then return false,"Waiting for the submitted stack's server confirmation." end
    local plan,reason=P.Preview(job)
    if not plan then return false,reason end
    P.jobID,P.plan,P.index,P.state,P.message=job.id,plan,1,"review",nil
    P.expected={}; for id,buy in pairs(MarketSync.CraftLedger.Remaining(job)) do P.expected[id]=buy.qty end
    Changed(); return true
end
function P.CheckNext()
    if P.state~="review" then return false end
    if not P.plan.complete then return false end
    if not SameNeeds() then P.Pause("The craft's required quantities changed. Review a new plan."); return false end
    local row=P.plan.entries[P.index]
    if not row then P.state="complete"; Changed(); return true end
    P.state="checking"; P.message="Checking the exact stack and price..."; Changed()
    if not S.PrepareLivePurchase(row) then P.Pause("Unable to verify this stack. Refresh prices and review again."); return false end
    return true
end
function P.OnScannerChanged()
    if P.state=="checking" and not S.Active then
        if S.PurchaseReady and S.PurchaseReady.row==P.plan.entries[P.index] then
            P.state="ready"; P.message="Review this stack, then click Buy Stack."
        else P.state="paused"; P.message="The reviewed stack is no longer available. Refresh prices; replacement prices need a new review." end
        Changed()
    end
end
function P.ReceiptTarget(itemID,qty,paid)
    local row=P.pending
    if row and P.state=="awaiting" and itemID==row.itemID and qty==row.stackSize and paid==row.buyout then return P.jobID end
end
function P.BuyNext()
    if P.state~="ready" then return false end
    if not SameNeeds() then P.Pause("The craft quantities changed. Review a new plan before buying."); return false end
    local row=P.plan.entries[P.index]
    if not S.PurchaseReady or S.PurchaseReady.row~=row then P.Pause("Live auction selection changed. Check this stack again."); return false end
    if GetMoney and GetMoney()<row.buyout then P.Pause("Not enough money for this stack."); return false end
    P.pending=row; P.state="awaiting"; P.message="Waiting for server confirmation..."; P.submittedAt=GetTime()
    if not S.BuyPreparedLivePurchase(row) then P.pending=nil; P.Pause("Stack price or quantity changed. Refresh and review again."); return false end
    Changed(); return true
end
function P.OnConfirmation()
    if P.state~="awaiting" or not P.pending then return end
    local row=P.pending
    local job=MarketSync.CraftLedger.Get(P.jobID)
    local remaining=job and MarketSync.CraftLedger.Remaining(job)
    local expected=math.max(0,(P.expected[row.itemID] or 0)-row.needed)
    if not remaining or ((remaining[row.itemID] or {}).qty or 0)~=expected then
        P.pending=nil;P.Pause("Could not match this confirmation to the craft receipt. Check the ledger before continuing.");return
    end
    P.expected[row.itemID]=math.max(0,(P.expected[row.itemID] or 0)-row.needed)
    P.pending=nil; P.index=P.index+1
    if P.index>#P.plan.entries then P.state="complete"; P.message="Reviewed purchases confirmed. Extra units remain in your item ledger."
    else P.state="review"; P.message="Previous purchase confirmed. Check the next stack." end
    Changed()
end
if S and S.RegisterCallback then S.RegisterCallback(P.OnScannerChanged) end
local events=CreateFrame("Frame"); P.eventFrame=events
events:RegisterEvent("CHAT_MSG_SYSTEM"); events:RegisterEvent("UI_ERROR_MESSAGE"); events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent",function(_,event,message)
    if event=="CHAT_MSG_SYSTEM" then
        local isSafe = MarketSync.IsSafeString and MarketSync.IsSafeString(message) or (type(message) == "string")
        if isSafe and ERR_AUCTION_BID_PLACED and message==ERR_AUCTION_BID_PLACED then
            -- The craft ledger registered first and handles the receipt. Defer to
            -- the next update so event-frame dispatch order cannot change routing.
            if P.state=="awaiting" then P.confirmed=true end
        end
    elseif event=="UI_ERROR_MESSAGE" or event=="AUCTION_HOUSE_CLOSED" then
        if P.state=="awaiting" or P.state=="ready" or P.state=="checking" or P.state=="review" then
            P.pending=nil; P.Pause(event=="AUCTION_HOUSE_CLOSED" and "Auction House closed. Refresh and review before continuing." or "Purchase failed. Refresh and review before continuing.")
        end
    end
end)
events:SetScript("OnUpdate",function()
    if P.confirmed then P.confirmed=nil; P.OnConfirmation()
    elseif P.state=="awaiting" and GetTime()-(P.submittedAt or 0)>10 then P.pending=nil; P.Pause("Confirmation timed out. Check your receipts, then scan and review the remaining materials.") end
end)
