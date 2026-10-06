-- Attach MarketSync's live scanner and grouped search to the classic AH tabs.
-- The portable window is for saved data and settings, not live AH querying.
local AH = MarketSync and MarketSync.AuctionHouse
if not AH then return end

local function HidePanels()
    if AH.LegacyScannerHost then AH.LegacyScannerHost:Hide() end
    if AH.LegacySearchHost then AH.LegacySearchHost:Hide() end
end

function AH.AttachLegacy()
    if AH.LegacyAttached then return true end
    if not (MarketSync.Scanner and MarketSync.Scanner.IsLegacyAH) then return false end
    local auctionFrame = _G.AuctionFrame
    if not auctionFrame or not auctionFrame.numTabs then return false end
    if not (MarketSync.CreateAHScannerPanel and MarketSync.CreateLegacySearchPanel) then return false end

    local function MakeHost(factory)
        local host = CreateFrame("Frame", nil, auctionFrame)
        host:SetPoint("TOPLEFT", auctionFrame, "TOPLEFT", 12, -38)
        host:SetPoint("BOTTOMRIGHT", auctionFrame, "BOTTOMRIGHT", -12, 32)
        host:SetFrameLevel(auctionFrame:GetFrameLevel() + 10)
        host.Content = factory(host)
        host:SetScript("OnShow", function()
            if host.Content and host.Content.OnShow then host.Content.OnShow() end
        end)
        host:Hide()
        return host
    end

    AH.LegacyScannerHost = MakeHost(MarketSync.CreateAHScannerPanel)
    AH.LegacySearchHost = MakeHost(MarketSync.CreateLegacySearchPanel)
    AH.LegacyScannerPanel = AH.LegacyScannerHost.Content

    local function Select(kind)
        if not auctionFrame:IsShown() then return false end
        HidePanels()
        local tab = kind == "search" and AH.LegacySearchTab or AH.LegacyScannerTab
        if type(AuctionFrameTab_OnClick) == "function" then AuctionFrameTab_OnClick(tab) end
        if kind == "search" then AH.LegacySearchHost:Show() else AH.LegacyScannerHost:Show() end
        return true
    end
    AH.ShowLegacyPanel = Select

    local function AddTab(label, kind)
        local index = auctionFrame.numTabs + 1
        local tab = CreateFrame("Button", "AuctionFrameTab" .. index, auctionFrame, "AuctionTabTemplate")
        tab:SetID(index)
        tab:SetText(label)
        tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (index - 1)], "RIGHT", -15, 0)
        PanelTemplates_SetNumTabs(auctionFrame, index)
        if PanelTemplates_EnableTab then PanelTemplates_EnableTab(auctionFrame, index) end
        if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
        tab:SetScript("OnClick", function() Select(kind) end)
        return tab
    end
    AH.LegacyScannerTab = AddTab("MarketSync Scanner", "scanner")
    AH.LegacySearchTab = AddTab("MarketSync Search", "search")
    if type(hooksecurefunc) == "function" and type(AuctionFrameTab_OnClick) == "function" then
        hooksecurefunc("AuctionFrameTab_OnClick", function(tab)
            if tab ~= AH.LegacyScannerTab and tab ~= AH.LegacySearchTab then HidePanels() end
        end)
    end
    auctionFrame:HookScript("OnHide", function()
        HidePanels()
        if MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auction House closed")
        end
    end)
    AH.LegacyAttached = true
    return true
end

MarketSync.OpenLegacySearch = function(query)
    if not AH.AttachLegacy() then return false end
    if type(query) == "number" and MarketSync.GetItemInfo then query = MarketSync.GetItemInfo(query) end
    if type(query) ~= "string" or query == "" then return false end
    query = query:match("%[(.-)%]") or query
    if AH.LegacySearchHost.Content and AH.LegacySearchHost.Content.SetQuery then
        AH.LegacySearchHost.Content:SetQuery(query)
    end
    if not AH.ShowLegacyPanel("search") then return false end
    return MarketSync.Scanner.StartLiveSearch(query)
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("AUCTION_HOUSE_SHOW")
listener:RegisterEvent("ADDON_LOADED")
listener:SetScript("OnEvent", function(_, event, name)
    if event == "AUCTION_HOUSE_SHOW" or (event == "ADDON_LOADED" and name == "Blizzard_AuctionUI") then
        AH.AttachLegacy()
    end
end)
