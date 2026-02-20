-- =============================================================
-- MarketSync - Init, Minimap, Options, Slash Commands
-- Entry point that ties all modules together
-- =============================================================

local ADDON_NAME = MarketSync.ADDON_NAME
local category  -- Forward declaration for minimap/options access

-- ================================================================
-- MINIMAP BUTTON
-- ================================================================
local function CreateMinimapButton()
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false, angle = 0 } end
    if MarketSyncDB.MinimapIcon.hide then return end

    local btn = CreateFrame("Button", "MarketSyncMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", 0, 0)

    local function UpdatePosition()
        local angle = MarketSyncDB.MinimapIcon.angle or 0
        local radius = 80
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    UpdatePosition()

    btn:SetScript("OnMouseDown", function(self)
        if not MarketSyncDB.MinimapIcon.locked then self.isMoving = true end
    end)
    btn:SetScript("OnMouseUp", function(self) self.isMoving = false end)
    btn:SetScript("OnUpdate", function(self)
        if self.isMoving then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.atan2(cy - my, cx - mx)
            MarketSyncDB.MinimapIcon.angle = angle
            UpdatePosition()
        end
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if MarketSync_ToggleUI then
                MarketSync_ToggleUI()
                -- Switch to Settings tab (Tab 4)
                if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[4] then
                    MarketSyncMainFrame.tabs[4]:Click()
                end
            end
        else
            if MarketSync_ToggleUI then
                MarketSync_ToggleUI()
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("MarketSync")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFF00FF00Left-Click|r to Open Window")
        GameTooltip:AddLine("|cFF00FF00Right-Click|r for Settings")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
end

-- ================================================================
-- INTERFACE OPTIONS PANEL
-- ================================================================

-- Main Panel
local panel = CreateFrame("Frame", "MarketSyncConfig", UIParent)
panel.name = "MarketSync"
category = Settings and Settings.RegisterCanvasLayoutCategory(panel, panel.name) or InterfaceOptions_AddCategory(panel)
if Settings then Settings.RegisterAddOnCategory(category) end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("MarketSync")

local subText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subText:SetText("MarketSync settings are managed within the main addon window.")

local btnOpen = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btnOpen:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -20)
btnOpen:SetSize(160, 25)
btnOpen:SetText("Open MarketSync")
btnOpen:SetScript("OnClick", function()
    if MarketSync_ToggleUI then MarketSync_ToggleUI() end
    HideUIPanel(SettingsPanel)
    HideUIPanel(InterfaceOptionsFrame)
end)

local btnSettings = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btnSettings:SetPoint("LEFT", btnOpen, "RIGHT", 10, 0)
btnSettings:SetSize(160, 25)
btnSettings:SetText("Open Settings")
btnSettings:SetScript("OnClick", function()
    if MarketSync_ToggleUI then
        MarketSync_ToggleUI()
        -- Switch to Settings tab (Tab 4)
        if MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[4] then
            MarketSyncMainFrame.tabs[4]:Click()
        end
    end
    HideUIPanel(SettingsPanel)
    HideUIPanel(InterfaceOptionsFrame)
end)

-- Lock button moved to Main UI Settings tab

-- ================================================================
-- STAGED INITIALIZATION
-- ================================================================
-- Stage 1 (immediate):  DB defaults + minimap — zero DB iteration
-- Stage 2 (45s):        Passive sync — lightweight guild advertisements
-- Stage 3 (90s):        Search index cache — heavy coroutine, only if enabled
-- On-Demand:            Opening the Browse UI always triggers cache build
-- ================================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    -- Handle both the legacy folder name and the new name
    if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == "AuctionatorAnnouncer") then
        -- STAGE 1: Bare minimum — no DB iteration at all
        MarketSync.InitializeDB()
        CreateMinimapButton()

        -- FIRST LAUNCH PROTECTION: If the user doesn't have an offline personal snapshot pool yet, 
        -- forcibly snapshot whatever exists in their Live Auctionator DB into the mirror pool right now.
        -- This guarantees new users don't see an empty "Personal Snapshot" screen if they've used Auctionator before.
        C_Timer.After(5, function()
            local pCount = 0
            if MarketSyncDB and MarketSync.GetRealmDB().PersonalData then
                for _ in pairs(MarketSync.GetRealmDB().PersonalData) do pCount = pCount + 1; break end
            end
            if pCount == 0 and MarketSync.SnapshotPersonalScan then
                MarketSync.SnapshotPersonalScan()
            end
        end)

        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- STAGE 2: Passive sync (45s) — sets up guild advertisement ticker
        C_Timer.After(45, function()
            -- ... (rest of stage 2)
            MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName()
            MarketSync.StartPassiveSync()
            if MarketSyncDB and MarketSyncDB.DebugMode then
                print("|cFF00FF00[MarketSync]|r Stage 2: Passive sync started (45s)")
            end
        end)

        -- STAGE 3: Search index cache (90s) — only if user opted in
        C_Timer.After(90, function()
            if MarketSyncDB and MarketSyncDB.BuildCacheOnStartup then
                if MarketSyncDB.DebugMode then
                    print("|cFF00FF00[MarketSync]|r Stage 3: Building search index (90s)")
                end
                if MarketSync.BuildSearchIndex then
                    MarketSync.BuildSearchIndex()
                end
            end
        end)
        
        -- Register for AH events so we can invalidate the scan cache dynamically
        self:RegisterEvent("AUCTION_HOUSE_CLOSED")
        
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if MarketSyncDB then
            local today = MarketSync.GetCurrentScanDay()
            local myLatestScanDay = MarketSync.GetMyLatestScanDay()
            
            -- Immediately snapshot the latest DB state exclusively to the PersonalData pool
            if MarketSync.SnapshotPersonalScan then
                local _, todayCount = MarketSync.SnapshotPersonalScan()
                
                if myLatestScanDay == today then
                    local lastCountDay = MarketSync.GetRealmDB().LastCountDay or 0
                    local lastCount = MarketSync.GetRealmDB().LastTodayCount or 0
                    
                    if lastCountDay ~= today then
                        lastCount = 0
                    end
                    
                    if not MarketSync.GetRealmDB().PersonalScanTime or (todayCount > lastCount) then
                        MarketSync.GetRealmDB().PersonalScanTime = time()
                        MarketSync.GetRealmDB().LastCountDay = today
                    end
                    MarketSync.GetRealmDB().LastTodayCount = todayCount
                end
            end

            if MarketSync.GetRealmDB().CachedScanStats then
                MarketSync.GetRealmDB().CachedScanStats = nil
                if MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                    -- Broadcast our new findings roughly 2 seconds after closing the AH
                    C_Timer.After(2, function() MarketSync.SendAdvertisement() end)
                end
            end
        end
    end
end)

-- ================================================================
-- SLASH COMMANDS
-- ================================================================
SLASH_MarketSync1 = "/marketsync"
SLASH_MarketSync2 = "/ms"
SLASH_MarketSync3 = "/aucann"
SlashCmdList["MarketSync"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "search" or cmd == "browse" or cmd == "ui" then
        if MarketSync_ToggleUI then
            MarketSync_ToggleUI()
        end
    elseif cmd == "stats" or cmd == "config" then
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(category:GetID())
        else
            InterfaceOptionsFrame_OpenToCategory(panel)
        end
    elseif cmd == "block" then
        if #arg > 0 then MarketSync.ToggleBlock(arg) else print("Usage: /ms block [playername]") end
    elseif cmd == "unblock" then
        if #arg > 0 then MarketSync.ToggleBlock(arg) else print("Usage: /ms unblock [playername]") end
    else
        print("|cFF00FF00[MarketSync]|r Commands:")
        print("  /ms search - Open the browse window.")
        print("  /ms config - Open settings panel.")
        print("  /ms block [name] - Block a sender.")
    end
end


