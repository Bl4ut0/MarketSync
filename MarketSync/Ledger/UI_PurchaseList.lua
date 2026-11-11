local P=MarketSync.PurchaseList
local window
local function Money(value)
    return MarketSync.FormatMoney and MarketSync.FormatMoney(math.ceil(value or 0)) or tostring(math.ceil(value or 0)).."c"
end
local function Name(id) return (MarketSync.GetItemInfo and MarketSync.GetItemInfo(id)) or "Item "..tostring(id) end
local function Text(parent,x,y,width,text)
    local t=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t:SetPoint("TOPLEFT",x,y);t:SetWidth(width);t:SetJustifyH("LEFT");t:SetText(text or "");return t
end
function P.ShowTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:SetText("Purchase crafting list")
    local job=P.SelectedJob();local plan,reason=P.Preview(job)
    if not plan then GameTooltip:AddLine(reason,1,0.7,0.2,true)
    else
        GameTooltip:AddLine(job.name.." x"..job.quantity,1,0.82,0)
        for _,m in ipairs(plan.materials) do
            GameTooltip:AddLine(Name(m.itemID)..": need "..m.need..", buy "..m.units.." · "..Money(m.cost),1,1,1,true)
        end
        GameTooltip:AddLine("Quoted total: "..Money(plan.total),1,0.82,0)
        if GetMoney and GetMoney()<plan.total then GameTooltip:AddLine("Not enough gold for the full list.",1,0.25,0.2,true) end
        if plan.extra>0 then GameTooltip:AddLine("Includes "..plan.extra.." extra units from whole stacks.",1,0.65,0.15,true) end
        if not plan.complete then GameTooltip:AddLine("Incomplete availability. Scan again before purchasing.",1,0.25,0.2,true) end
        GameTooltip:AddLine("Cheapest unit price first. Review and confirm each verified stack.",0.7,0.7,0.7,true)
    end
    GameTooltip:Show()
end
local function Create()
    if window then return window end
    local f=CreateFrame("Frame","MarketSyncPurchaseList",UIParent,"BackdropTemplate");window=f
    f:SetSize(620,490);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true)
    f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving);f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(f) end
    if MarketSync.Theme and MarketSync.Theme.DecorateWarcraftWindow then
        MarketSync.Theme.DecorateWarcraftWindow(f, "Interface\\Icons\\INV_Misc_Bag_10", "|cffffd100Crafting Purchase Confirmations|r")
    end
    local closeTop = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeTop:SetPoint("TOPRIGHT", 2, 2)
    closeTop:SetScript("OnClick", function() f:Hide() end)
    f.CloseButton = closeTop
    f.title=Text(f,60,-36,530)
    local inset = MarketSync.CreateModernInset and MarketSync.CreateModernInset(f, 14, -64, 592, 238) or nil
    local scroll=CreateFrame("ScrollFrame",nil,inset or f,"UIPanelScrollFrameTemplate")
    if inset then
        scroll:SetPoint("TOPLEFT",6,-6);scroll:SetPoint("BOTTOMRIGHT",-26,6)
    else
        scroll:SetPoint("TOPLEFT",16,-68);scroll:SetPoint("BOTTOMRIGHT",-34,188)
    end
    local content=CreateFrame("Frame",nil,scroll);content:SetSize(552,1);scroll:SetScrollChild(content);f.rows={}
    f.total=Text(f,16,-312,580);f.current=Text(f,16,-340,580);f.message=Text(f,16,-399,580)
    f.action=CreateFrame("Button",nil,f,"UIPanelButtonTemplate");f.action:SetSize(195,26);f.action:SetPoint("BOTTOMLEFT",16,16)
    f.action:SetScript("OnClick",function() if P.state=="ready" then P.BuyNext() else P.CheckNext() end end)
    f.refresh=CreateFrame("Button",nil,f,"UIPanelButtonTemplate");f.refresh:SetSize(170,26);f.refresh:SetPoint("LEFT",f.action,"RIGHT",8,0);f.refresh:SetText("Refresh list prices")
    f.refresh:SetScript("OnClick",function()
        if P.state=="awaiting" then return end
        local job=P.jobID and MarketSync.CraftLedger.Get(P.jobID) or P.SelectedJob()
        if not job then return end
        local ids={};for id in pairs(MarketSync.CraftLedger.Remaining(job)) do ids[#ids+1]=id end;table.sort(ids)
        if #ids==0 then return end
        P.Pause("Scanning outstanding materials. Reopen Purchase List to review the new quote.")
        MarketSync.Scanner.StartLiveSearch(ids)
    end)
    local close=CreateFrame("Button",nil,f,"UIPanelButtonTemplate");close:SetSize(90,26);close:SetPoint("BOTTOMRIGHT",-16,16);close:SetText("Close");close:SetScript("OnClick",function() f:Hide() end)
    f:SetScript("OnHide",function() if P.state=="ready" or P.state=="checking" then P.Pause("Purchase review closed. Reopen the list to continue.") end end)
    function f:Refresh()
        local job=P.jobID and MarketSync.CraftLedger.Get(P.jobID)
        self.title:SetText(job and job.name.." x"..job.quantity.." · "..(job.shoppingName or "Materials purchased") or "Select a crafting-linked shopping list.")
        for _,row in ipairs(self.rows) do row:Hide() end
        local plan=P.plan
        if plan then
            for i,entry in ipairs(plan.entries) do
                local row=self.rows[i]
                if not row then
                    row=Text(content,4,-(i-1)*52,540)
                    if row.SetScript and EasyMenu then
                        row:SetScript("OnMouseUp", function(_, btn)
                            if btn == "RightButton" and row.entry then
                                local e = row.entry
                                local menu = {
                                    { text = Name(e.itemID) .. " x" .. tostring(e.stackSize), isTitle = true, notCheckable = true },
                                    { text = "Check / Buy Next Stack", notCheckable = true, func = function()
                                        if P.state == "ready" then P.BuyNext() else P.CheckNext() end
                                    end },
                                    { text = "Search in Auction House", notCheckable = true, func = function()
                                        if MarketSync.SearchAuctionHouseByName then MarketSync.SearchAuctionHouseByName(Name(e.itemID)) end
                                    end },
                                    { text = "Cancel", notCheckable = true, func = function() end },
                                }
                                if not f.contextMenuFrame then
                                    f.contextMenuFrame = CreateFrame("Frame", "MarketSyncPurchaseListContextMenu", f, "UIDropDownMenuTemplate")
                                end
                                EasyMenu(menu, f.contextMenuFrame, "cursor", 0, 0, "MENU")
                            end
                        end)
                    end
                    self.rows[i]=row
                end
                row.entry = entry
                local warning=entry.extra>0 and " |cffffaa33("..entry.extra.." extra units)|r" or ""
                if entry.higherTier then warning=warning.." |cffffaa33Higher price tier — confirm|r" end
                row:SetText((i<P.index and "|cff55ff88Confirmed: |r" or "")..Name(entry.itemID).." x"..entry.stackSize.." · "..Money(entry.buyout).."\nUnit price: "..Money(entry.unitCost).." (rounded up)\n"..warning)
                row:Show()
            end
            content:SetHeight(math.max(1,#plan.entries*52))
            self.total:SetText("Quoted total: "..Money(plan.total).." · "..#plan.entries.." stacks · "..plan.units.." units"..(plan.extra>0 and " · "..plan.extra.." extra" or ""))
            if GetMoney and GetMoney()<plan.total and P.index==1 then self.total:SetText(self.total:GetText().." |cffff5555Not enough gold for full list|r") end
            local entry=plan.entries[P.index]
            self.current:SetText(entry and ("Next: "..Name(entry.itemID).." x"..entry.stackSize.." for "..Money(entry.buyout).."\n"..(entry.extra>0 and "Whole stack includes "..entry.extra.." extra units. " or "")..(entry.higherTier and "This stack costs more per unit than the cheapest tier." or "Cheapest available unit-price order.")) or "No further stacks in this reviewed plan.")
        else self.total:SetText("");self.current:SetText("") end
        self.message:SetText(self.error or P.message or (plan and not plan.complete and (plan.reason or "Not enough live auctions for the entire list. Refresh prices.") or "Check the next stack, then confirm its exact price and quantity. Changed auctions stop the queue."))
        self.action:SetText(P.state=="ready" and "Buy Stack "..P.index.." / "..#P.plan.entries or P.state=="complete" and "Purchases confirmed" or "Check next stack")
        self.action:SetEnabled(not self.error and plan and plan.complete and (P.state=="review" or P.state=="ready"))
        self.refresh:SetEnabled(P.state~="awaiting")
    end
    P.Refresh=function() if f:IsShown() then f:Refresh() end end
    return f
end
function P.Show()
    local f=Create()
    if P.state=="awaiting" then f.error=nil;f:Show();f:Refresh();return end
    local job=P.SelectedJob();local ok,reason=P.Open(job)
    if not ok then
        P.plan=nil;P.jobID=job and job.id;P.state="idle";f.error=reason
    else f.error=nil end
    if MarketSync.ShowWorkspaceWindow then MarketSync.ShowWorkspaceWindow(f) else f:Show() end
    f:Refresh()
end
