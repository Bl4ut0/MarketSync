-- ================================================================
-- MarketSync - Embedded Auction House Tab & Lifecycle
-- Hooks AuctionHouseFrame to add MarketSync directly into the native AH
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.AuctionHouse = {}

local AH = MarketSync.AuctionHouse

function AH.ShowAuctionHousePanel()
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return false end
    if not AH.Attach() then return false end
    local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
    if libAHTab and libAHTab:DoesIDExist("MarketSync") then
        libAHTab:SetSelected("MarketSync")
        return true
    end
    if AH.Panel then
        AH.Panel:Show()
    end
    return true
end

function AH.HideAuctionHousePanel()
    if AH.Panel then
        AH.Panel:Hide()
    end
end

function AH.Attach()
    local frame = AuctionHouseFrame
    if not frame or not frame.AuctionsTab or type(frame.Tabs) ~= "table" or #frame.Tabs == 0 then
        return false
    end
    if AH.Attached then return true end

    local panel = CreateFrame("Frame", "MarketSyncAuctionHousePanel", frame)
    panel:Hide()
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 32)
    frame.MarketSyncPanel = panel
    AH.Panel = panel

    -- Create Tab Button via LibAHTab-1-0 (safe, compatible with modern AH & all addons)
    local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
    if libAHTab then
        if not libAHTab:DoesIDExist("MarketSync") then
            libAHTab:CreateTab("MarketSync", panel, "MarketSync", "MarketSync")
        end
        AH.TabButton = libAHTab:GetButton("MarketSync")
    end

    -- Embed UI Content into AH Panel
    if MarketSync.CreateAHScannerPanel then
        panel.ScannerPanel = MarketSync.CreateAHScannerPanel(panel)
        panel.ScannerPanel:SetAllPoints(panel)
    end

    -- Attach MarketSync Breakout Sidecar to AuctionHouseFrame
    if MarketSync.CreateAHSidecar then
        AH.Sidecar = MarketSync.CreateAHSidecar(frame)
    end

    -- Hook display mode switching
    hooksecurefunc(frame, "SetDisplayMode", function()
        -- Auto-switch sidecar view depending on whether user is browsing or selling
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetMode then
            local currentMode = frame:GetDisplayMode()
            if frame.Tabs and frame.Tabs[2] and currentMode == frame.Tabs[2].displayMode then
                MarketSync.AHSidecar.SetMode("sell")
            elseif frame.Tabs and frame.Tabs[1] and currentMode == frame.Tabs[1].displayMode then
                MarketSync.AHSidecar.SetMode("lists")
            end
        end
    end)

    panel:SetScript("OnShow", function()
        if panel.ScannerPanel and panel.ScannerPanel.OnShow then
            panel.ScannerPanel:OnShow()
        end
    end)

    frame:HookScript("OnShow", function()
        if MarketSync.AHSidecar and MarketSync.AHSidecar.SetExpanded then
            local expanded = (MarketSyncDB and MarketSyncDB.AHSidecarExpanded ~= nil) and MarketSyncDB.AHSidecarExpanded or true
            MarketSync.AHSidecar.SetExpanded(expanded)
        end
    end)

    frame:HookScript("OnHide", function()
        panel:Hide()
        if AH.Sidecar then
            AH.Sidecar:Hide()
        end
        MarketSync.IsAuctionHouseOpen = false
        if MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auction House closed")
        end
    end)

    AH.Attached = true
    return true
end

-- Hook ADDON_LOADED or AUCTION_HOUSE_SHOW
local ahLoader = CreateFrame("Frame")
pcall(ahLoader.RegisterEvent, ahLoader, "ADDON_LOADED")
pcall(ahLoader.RegisterEvent, ahLoader, "AUCTION_HOUSE_SHOW")
ahLoader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_AuctionHouseUI" then
        AH.Attach()
    elseif event == "AUCTION_HOUSE_SHOW" then
        MarketSync.IsAuctionHouseOpen = true
        AH.Attach()
    end
end)
