-- =============================================================
-- MarketSync - Main Frame
-- Window shell, tabs, and settings
-- =============================================================

local MainFrame, MainHost, BrowseContent, SyncContent, NeutralContent, ProcessingContent, NotificationsContent, SettingsContent
local ItemHistoryPanel, AnalyticsPanel, ItemDetailPanel
local activeBrowseTab = 1

-- ================================================================
-- HELPER: CreateModernInset
-- Matches Blizzard Auction House sleek dark bronze/stone inset panels
-- ================================================================
if not MarketSync.CreateModernInset then function MarketSync.CreateModernInset(parent, x, y, width, height)
    local inset = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    inset:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    if isLegacy then
        inset:SetBackdropColor(0.05, 0.045, 0.04, 0.96)
        inset:SetBackdropBorderColor(0.50, 0.42, 0.28, 0.95)
    else
        inset:SetBackdropColor(0.05, 0.045, 0.04, 0.90)
        inset:SetBackdropBorderColor(0.50, 0.42, 0.28, 0.95)
    end

    -- Subtle top inner highlight line matching Blizzard AH insets (warm bronze/gold sheen)
    local topHighlight = inset:CreateTexture(nil, "BORDER")
    topHighlight:SetHeight(1)
    topHighlight:SetPoint("TOPLEFT", 3, -3)
    topHighlight:SetPoint("TOPRIGHT", -3, -3)
    topHighlight:SetColorTexture(0.50, 0.42, 0.28, 0.7)
    inset.topHighlight = topHighlight

    if x and y then
        inset:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    if width and height then
        inset:SetSize(width, height)
    end
    return inset
end
end

-- ================================================================
-- HELPER: CreateAHColumnHeader
-- Matches Blizzard Auction House column headers (clean dark bronze/stone + sort arrow)
-- ================================================================
if not MarketSync.CreateAHColumnHeader then function MarketSync.CreateAHColumnHeader(parent, width, height, text, sortKey)
    local hdr = CreateFrame("Button", nil, parent, "BackdropTemplate")
    hdr:SetSize(width, height or 20)
    hdr.sortKey = sortKey

    hdr:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    hdr:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    hdr:SetBackdropBorderColor(0.32, 0.28, 0.20, 0.85)

    -- Vertical separator on right side
    local sep = hdr:CreateTexture(nil, "OVERLAY")
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT", 0, -2)
    sep:SetPoint("BOTTOMRIGHT", 0, 2)
    sep:SetColorTexture(0.35, 0.30, 0.20, 0.60)
    hdr.sep = sep

    local label = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -15, 0)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(false) end
    label:SetText(text or "")
    hdr.label = label

    local arrow = hdr:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", -4, -1)
    arrow:SetTexCoord(0, 0.5625, 0, 1.0)
    arrow:Hide()
    hdr.arrow = arrow

    hdr:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.24, 0.20, 0.12, 0.95)
    end)
    hdr:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.11, 0.10, 0.95)
    end)

    return hdr
end
end

-- ================================================================
-- MAIN FRAME CONSTRUCTION
-- ================================================================
local function CreateMainFrame()
    if MainFrame then return MainFrame end
    local legacyTheme = MarketSync.GetUITheme and MarketSync.GetUITheme() == "legacy"

    -- Ensure Auction House UI is loaded so AuctionHouseFrameDisplayModeTabTemplate and textures are present
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
        if C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_AuctionHouseUI")
        end
    elseif UIParentLoadAddOn and (not IsAddOnLoaded or not IsAddOnLoaded("Blizzard_AuctionHouseUI")) then
        pcall(UIParentLoadAddOn, "Blizzard_AuctionHouseUI")
    end

    -- --- MAIN WINDOW (832 x 447, PortraitFrameTemplate) ---
    local ok, res
    if legacyTheme then
        ok, res = pcall(CreateFrame, "Frame", "MarketSyncMainFrame", UIParent, "BackdropTemplate")
    else
        ok, res = pcall(CreateFrame, "Frame", "MarketSyncMainFrame", UIParent, "PortraitFrameTemplate")
    end
    if ok and res then
        MainFrame = res
    else
        MainFrame = CreateFrame("Frame", "MarketSyncMainFrame", UIParent)
    end
    MarketSync.MainFrame = MainFrame
    MainFrame:SetSize(832, 447)
    MainFrame:SetPoint("CENTER")
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
    MainFrame:SetFrameStrata("HIGH")
    MainFrame:SetToplevel(true)
    if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(MainFrame) end

    if legacyTheme then
        -- Textured fallback for clients without the original Classic AH art.
        MainFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 10, right = 10, top = 10, bottom = 10 },
        })
        MainFrame:SetBackdropColor(0.065, 0.055, 0.045, 0.96)
        MainFrame:SetBackdropBorderColor(0.85, 0.72, 0.45, 0.98)
        if MarketSync.Theme and MarketSync.Theme.ApplyLegacyAuctionFrame then
            MarketSync.Theme.ApplyLegacyAuctionFrame(MainFrame)
        end
    end

    -- --- PORTRAIT ---
    local portrait = MainFrame.GetPortrait and MainFrame:GetPortrait()
        or (MainFrame.PortraitContainer and MainFrame.PortraitContainer.portrait)
        or _G["MarketSyncMainFramePortrait"]
    if not portrait then
        local legacyArt = MainFrame._marketSyncLegacyAuctionArt
        local pHost = (legacyArt and legacyArt.portraitOverlay) or MainFrame
        portrait = pHost:CreateTexture(nil, (legacyArt and legacyArt.portraitOverlay) and "ARTWORK" or "BACKGROUND")
        portrait:SetSize(60, 60)
        portrait:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 6, -6)
        local mask = pHost:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(58, 58)
        mask:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 8, -7)
        portrait:AddMaskTexture(mask)
    end
    MainFrame.portrait = portrait

    local function UpdatePortrait()
        if MainFrame.SetPortraitToUnit then
            MainFrame:SetPortraitToUnit("player")
        elseif portrait then
            SetPortraitTexture(portrait, "player")
        end
    end

    local portraitFrame = CreateFrame("Frame", nil, MainFrame)
    portraitFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    portraitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    portraitFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_PORTRAIT_UPDATE" and unit == "player" then
            UpdatePortrait()
        elseif event == "PLAYER_ENTERING_WORLD" then
            UpdatePortrait()
        end
    end)
    MainFrame:HookScript("OnShow", function() UpdatePortrait() end)
    UpdatePortrait()

    -- --- CLOSE BUTTON ---
    local closeBtn = MainFrame.CloseButton or _G["MarketSyncMainFrameCloseButton"]
    if not closeBtn then
        closeBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", legacyTheme and 3 or -4, legacyTheme and -8 or -4)
    end
    closeBtn:SetScript("OnClick", function()
        MainFrame:Hide()
    end)
    MainFrame.CloseBtn = closeBtn


    -- Keep the collapsed sidecar as a small bump attached to the window edge.
    -- Both surfaces reuse the same Shopping / Craft / Bags sidecar.
    local sidecarTab = CreateFrame("Button", nil, MainFrame, "BackdropTemplate")
    sidecarTab:SetSize(18, 38)
    sidecarTab:SetPoint("TOPLEFT", MainFrame, "TOPRIGHT", -2, -60)
    if sidecarTab.SetFrameLevel then
        sidecarTab:SetFrameLevel((MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 0) + 10)
    end
    sidecarTab:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sidecarTab:SetBackdropColor(MarketSync.GetThemeColor("header"))
    sidecarTab:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
    local sidecarArrow = sidecarTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sidecarArrow:SetPoint("CENTER", 0, 0)
    sidecarArrow:SetText(">")
    sidecarTab:SetScript("OnEnter", function(self)
        self:SetBackdropColor(MarketSync.GetThemeColor("hover"))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("MarketSync Lists", 1, 0.82, 0)
        GameTooltip:AddLine("Open Shopping, Craft, and Bags", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    sidecarTab:SetScript("OnLeave", function(self)
        self:SetBackdropColor(MarketSync.GetThemeColor("header"))
        GameTooltip:Hide()
    end)
    sidecarTab:SetScript("OnClick", function()
        local sidecar = MarketSync.AHSidecar
        if not sidecar or not sidecar.Frame then
            local host = AuctionHouseFrame or AuctionFrame or MainFrame
            if MarketSync.CreateAHSidecar then MarketSync.CreateAHSidecar(host) end
            sidecar = MarketSync.AHSidecar
        end
        if sidecar and sidecar.ShowForMain then
            sidecar.MainToggleButton = sidecarTab
            sidecar.ShowForMain(sidecar.currentMode or "lists")
        end
    end)
    if MarketSync.SetAccessibility then
        MarketSync.SetAccessibility(sidecarTab, {
            name = "Open MarketSync Lists",
            context = "Button",
            description = "Open the portable Shopping, Craft, and Bags breakout panel",
        })
    end
    MainFrame:HookScript("OnShow", function()
        local sidecar = MarketSync.AHSidecar
        if not sidecar or not sidecar.Frame then
            local host = AuctionHouseFrame or AuctionFrame or MainFrame
            if MarketSync.CreateAHSidecar then MarketSync.CreateAHSidecar(host) end
            sidecar = MarketSync.AHSidecar
        end
        if sidecar then sidecar.MainToggleButton = sidecarTab end
        if sidecar and sidecar.ShowForMain and
            (not MarketSyncDB or MarketSyncDB.MainSidecarExpanded ~= false) then
            sidecar.ShowForMain(sidecar.currentMode or "lists")
        else
            sidecarTab:Show()
        end
    end)

    -- --- TITLE ---
    local titleText = MainFrame.GetTitleText and MainFrame:GetTitleText()
        or (MainFrame.TitleContainer and MainFrame.TitleContainer.TitleText)
        or _G["MarketSyncMainFrameTitleText"]
    if not titleText then
        titleText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", 0, -18)
    end
    titleText:SetTextColor(1, 0.82, 0)
    titleText:SetText(MarketSync.ADDON_NAME or "MarketSync")
    MainFrame.titleText = titleText

    -- Low RAM Mode: 5-minute idle GC
    local lowRamIdleTicker = nil

    MainFrame:HookScript("OnHide", function()
        if MarketSyncDB and MarketSyncDB.LowRamMode then
            if not lowRamIdleTicker then
                lowRamIdleTicker = C_Timer.NewTicker(300, function()
                    if MainFrame:IsShown() then return end
                    if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
                    if MarketSyncDB.ItemInfoCache then wipe(MarketSyncDB.ItemInfoCache) end
                    collectgarbage("collect")
                    print("|cFF00FF00[MarketSync]|r Low RAM Mode: 5-minute idle reached. Cache cleared and memory recovered.")
                    if lowRamIdleTicker then lowRamIdleTicker:Cancel(); lowRamIdleTicker = nil end
                end, 1) -- Run exactly once after 5 minutes
            end
        end
    end)
    MainFrame:HookScript("OnShow", function()
        if lowRamIdleTicker then
            lowRamIdleTicker:Cancel()
            lowRamIdleTicker = nil
        end
    end)

    local titleHitBox = CreateFrame("Button", nil, MainFrame)
    titleHitBox:SetPoint("CENTER", MainFrame.TitleContainer or titleText, "CENTER")
    titleHitBox:SetHeight(22)
    titleHitBox:SetWidth(300) -- Will be updated dynamically
    titleHitBox:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltipTitle, 1, 0.82, 0)
            GameTooltip:AddLine(self.tooltipText, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
    end)
    titleHitBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    MainFrame.titleHitBox = titleHitBox

    -- --- TITLE BAR SYNC STATUS MONITOR ---
    local syncButton = CreateFrame("Button", nil, MainFrame)
    -- Anchor to the title bar itself, not the template close button (whose
    -- vertical position varies by client and can put the label under content).
    -- PortraitFrameTemplate's title strip is shallow; keep the status text
    -- centered in it rather than sitting on the lower decorative border.
    syncButton:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -42, legacyTheme and -12 or -3)
    syncButton:SetHeight(20)
    syncButton:SetWidth(150)
    local syncFrameLevel = 100
    if closeBtn and closeBtn.GetFrameLevel then
        syncFrameLevel = math.max(syncFrameLevel, closeBtn:GetFrameLevel() + 5)
    end
    if MainFrame.GetFrameLevel then
        syncFrameLevel = math.max(syncFrameLevel, MainFrame:GetFrameLevel() + 100)
    end
    if syncButton.SetFrameLevel then
        syncButton:SetFrameLevel(syncFrameLevel)
    end

    local syncMonitor = syncButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncMonitor:SetPoint("RIGHT", syncButton, "RIGHT", 0, 0)
    syncMonitor:SetJustifyH("RIGHT")
    syncMonitor:SetText("|cff00ff00●|r |cff888888Sync: Idle|r")
    MainFrame.syncMonitor = syncMonitor
    MainFrame.syncButton = syncButton

    function MainFrame.UpdateLedgerButtonState()
        local available = MarketSync.CanOpenLedger and MarketSync.CanOpenLedger()
        if available and not MainFrame.LedgerButton then
            local button = CreateFrame("Button", nil, MainFrame, "UIPanelButtonTemplate")
            button:SetSize(78, 20)
            button:SetPoint("RIGHT", syncButton, "LEFT", -6, 0)
            button:SetText("Ledger")
            button:SetScript("OnClick", function() MarketSync.OpenLedgerShortcut() end)
            if MarketSync.SetAccessibility then
                MarketSync.SetAccessibility(button, {
                    name = "MarketSync Item Ledger",
                    context = "Button",
                    description = "Open the Item & Gold Ledger window.",
                })
            end
            MainFrame.LedgerButton = button
        end
        if MainFrame.LedgerButton then MainFrame.LedgerButton:SetShown(available == true) end
    end
    MainFrame:HookScript("OnShow", MainFrame.UpdateLedgerButtonState)
    MainFrame.UpdateLedgerButtonState()

    syncButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("MarketSync Network Status", 1, 0.82, 0)
        local inGuild = IsInGuild and IsInGuild()
        if not inGuild then
            GameTooltip:AddLine("Guild Sync: |cffff8800Disabled (Not in a guild)|r", 0.85, 0.85, 0.85, true)
        elseif MarketSyncDB and MarketSyncDB.PassiveSync == false then
            GameTooltip:AddLine("Guild Sync: |cffaaaaaaDisabled (Settings)|r", 0.85, 0.85, 0.85, true)
        else
            GameTooltip:AddLine("Guild Sync: |cff00ff00Active (Listening)|r", 0.85, 0.85, 0.85, true)
        end
        local tx = MarketSync.TxRate or 0
        local rx = MarketSync.RxRate or 0
        GameTooltip:AddLine(string.format("Traffic: Tx %d/s | Rx %d/s", tx, rx), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Click to toggle Network Monitor Console.", 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    syncButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncButton:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then
            MarketSync.ToggleNetworkMonitor()
        end
    end)
    
    function MarketSync.UpdateNetworkUI(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
        MarketSync.TxRate = txRate or 0
        MarketSync.RxRate = rxRate or 0
        if MainFrame and MainFrame.syncMonitor then
            local text
            if type(txAPIRate) == "string" then
                text = txAPIRate
            elseif not IsInGuild or not IsInGuild() then
                text = "|cff888888●|r |cff666666Sync: No Guild|r"
            elseif MarketSyncDB and MarketSyncDB.PassiveSync == false then
                text = "|cff888888●|r |cff666666Sync: Disabled|r"
            elseif txRate > 0 and rxRate > 0 then
                text = string.format("|cff00ff00● Rx: %.0f/s|r  |cffff8800Tx: %.0f/s|r", rxRate, txRate)
            elseif txRate > 0 then
                text = string.format("|cffff8800● Tx: %.0f items/s|r", txRate)
            elseif rxRate > 0 then
                text = string.format("|cff00ff00● Rx: %.0f items/s|r", rxRate)
            elseif MarketSync.GetSyncTaskStatus and MarketSync.GetSyncTaskStatus().outbound then
                local status = MarketSync.GetSyncTaskStatus()
                text = status.throttled and "|cffffaa00● Sync: Waiting|r" or "|cff00ff00● Sync: Sending|r"
            else
                text = "|cff00ff00●|r |cff888888Sync: Idle|r"
            end
            MainFrame.syncMonitor:SetText(text)
            if MainFrame.syncButton and MainFrame.syncMonitor.GetStringWidth then
                MainFrame.syncButton:SetWidth(math.max(80, MainFrame.syncMonitor:GetStringWidth() + 10))
            end
        end

        if MarketSyncMonitorFrame and MarketSyncMonitorFrame:IsShown() then
            MarketSyncMonitorFrame.txLabel:SetText(string.format("|cffff8800Tx: %.0f items/s|r", txRate or 0))
            MarketSyncMonitorFrame.rxLabel:SetText(string.format("|cff00ff00Rx: %.0f items/s|r", rxRate or 0))
            
            if type(txAPIRate) == "string" then
                MarketSyncMonitorFrame.queueLabel:SetText(txAPIRate)
            elseif (txRate or 0) > 0 or (rxRate or 0) > 0 then
                MarketSyncMonitorFrame.queueLabel:SetText("|cff00ff00Sync Active|r")
            elseif MarketSync.GetSyncTaskStatus and MarketSync.GetSyncTaskStatus().outbound then
                local reason = MarketSync.GetSyncTaskStatus().waitReason
                MarketSyncMonitorFrame.queueLabel:SetText("|cffffaa00" .. (reason ~= "none" and reason or "Sync session active") .. "|r")
            elseif not IsInGuild or not IsInGuild() then
                MarketSyncMonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Disabled (No Guild)|r")
            else
                MarketSyncMonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
            end
        end

        if MarketSync.UpdateRateMonitor then
            MarketSync.UpdateRateMonitor(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
        end
    end

    -- ================================================================
    -- BOTTOM TABS
    -- ================================================================
    local tabNames = {"Main", "Neutral AH", "Analytics", "Processing", "Alerts", "Debugging"}
    local tabs = {}
    local contentFrames = {}
    MainFrame.contentFrames = contentFrames

    -- Item Detail Dashboard (Standalone view)
    if MarketSync.CreateItemDetailPanel then
        ItemDetailPanel = MarketSync.CreateItemDetailPanel(MainFrame)
    end

    function MarketSync.HideAllTabContent()
        for _, frame in ipairs(contentFrames) do
            if frame then frame:Hide() end
        end
        if ItemHistoryPanel then ItemHistoryPanel:Hide() end
        if AnalyticsPanel then AnalyticsPanel:Hide() end
        if ItemDetailPanel then ItemDetailPanel:Hide() end
    end

    local function SelectTab(id)
        if tabs[id] and not tabs[id]:IsShown() then
            for idx, t in ipairs(tabs) do
                if t:IsShown() then
                    id = idx
                    break
                end
            end
        end
        activeBrowseTab = id
        MainFrame.activeTabID = id
        MainFrame.selectedTab = id
        
        -- Hide all sub-panels (Detail, History, Analytics) on tab change
        if MarketSync.HideAllTabContent then
            MarketSync.HideAllTabContent()
        end

        -- Only auto-preload caches on tab change when Low RAM mode is disabled
        if MarketSyncDB and not MarketSyncDB.LowRamMode then
            if id == 1 then
                if MainFrame.mainSource == "guild" and MarketSync.LoadGuildCache then
                    MarketSync.LoadGuildCache()
                elseif MarketSync.LoadPersonalCache then
                    MarketSync.LoadPersonalCache()
                end
            elseif id == 2 and MarketSync.LoadNeutralCache then
                MarketSync.LoadNeutralCache()
            end
        end

        for i, tab in ipairs(tabs) do
            if i == id then
                if PanelTemplates_SelectTab then
                    PanelTemplates_SelectTab(tab)
                end
                if tab.SetSelected then
                    tab:SetSelected(true)
                end
                local baseLevel = MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 1
                if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 6) end
                if contentFrames[i] then contentFrames[i]:Show() end
            else
                if PanelTemplates_DeselectTab then
                    PanelTemplates_DeselectTab(tab)
                end
                if tab.SetSelected then
                    tab:SetSelected(false)
                end
                local baseLevel = MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 1
                if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 4) end
                if contentFrames[i] then contentFrames[i]:Hide() end
            end
        end
        -- Main tab: show the source (Personal or Guild) chosen in the selector.
        if id == 1 and MarketSync.ApplyMainSource then
            MarketSync.ApplyMainSource(MainFrame.mainSource)
        end
        -- On Classic/Legacy, Auction House Browse views (Tabs 1-2) use the native
        -- uncovered UI-AuctionFrame-Browse-* background; custom views (Tabs 4+)
        -- enable the seamless stone canvas fill inside the outer frame border.
        if legacyTheme and MarketSync.Theme and MarketSync.Theme.SetLegacyCanvasVisible then
            MarketSync.Theme.SetLegacyCanvasVisible(MainFrame, id >= 3)
        end

        local titles = {
            "Main",
            "Neutral AH",
            "Analytics",
            "Processing",
            "Alerts",
            "Debugging"
        }
        
        local tooltips = {
            "Browse your personal or guild Auction House data. Use Source to switch.",
            "Browse data from the Neutral Auction House.",
            "Inspect in-depth price trends, historical distribution, and market metrics.",
            "Organized controls on the left, auction-style arbitrage and crafting results on the right.",
            "Track targets by threshold and watch lists.",
            "Maintenance, task and resource monitoring. Configure options under AddOns settings.",
        }

        local versionStr = "v" .. tostring(MarketSync.GetAddOnMetadata("MarketSync", "Version") or "1.0")
        local fullTitle = string.format("%s (%s) - %s", MarketSync.ADDON_NAME or "MarketSync", versionStr, titles[id] or "")
        titleText:SetText(fullTitle)
        titleText:Show()
        
        -- Adjust hitbox width to cover the new text
        MainFrame.titleHitBox:SetWidth(titleText:GetStringWidth() + 20)
        MainFrame.titleHitBox.tooltipTitle = titles[id] or ""
        MainFrame.titleHitBox.tooltipText = tooltips[id]
        MainFrame.titleHitBox:Show()
    end
    MarketSync.SelectMainFrameTab = SelectTab

    local function CreateMainTab(id, name)
        local tab
        local tabName = "MarketSyncMainFrameTab" .. id

        local templates = legacyTheme
            and {"CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate"}
            or {"AuctionHouseFrameDisplayModeTabTemplate", "AuctionHouseFrameTabTemplate", "PanelTabButtonTemplate"}
        if MarketSync.IsForeverAuctionStyle and MarketSync.IsForeverAuctionStyle() then
            -- Keep the Auction House artwork without its native display-mode action.
            templates = {"AuctionHouseFrameTabTemplate", "PanelTabButtonTemplate"}
        end
        for _, tmpl in ipairs(templates) do
            local ok, res = pcall(CreateFrame, "Button", tabName, MainFrame, tmpl)
            if ok and res then
                tab = res
                break
            end
        end
        if not tab then
            tab = CreateFrame("Button", tabName, MainFrame)
            if MarketSync.StyleModernTab then
                MarketSync.StyleModernTab(tab)
            end
        end
        tab:SetID(id)
        tab:SetText(name)
        local baseLevel = MainFrame.GetFrameLevel and MainFrame:GetFrameLevel() or 1
        if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + 4) end
        if PanelTemplates_DeselectTab then
            PanelTemplates_DeselectTab(tab)
        end
        return tab
    end

    for i, name in ipairs(tabNames) do
        local tab = CreateMainTab(i, name)
        tab:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = tab
    end
    MainFrame.numTabs = #tabs
    MainFrame.tabs = tabs

    -- Dynamically show/hide tabs, size them uniformly, and anchor visible ones cleanly
    local function RefreshTabVisibility()
        -- Re-apply the Main tab source so the Guild option follows PassiveSync.
        if MarketSync.ApplyMainSource and MainFrame.mainSource then
            MarketSync.ApplyMainSource(MainFrame.mainSource)
        end
        local visibleTabs = {}
        for i, tab in ipairs(MainFrame.tabs) do
            local shouldHide = false
            if i == 2 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
                shouldHide = true
            elseif i == 3 and MarketSyncDB and MarketSyncDB.EnableAnalyticsTab == false then
                shouldHide = true
            elseif i == 4 and MarketSyncDB and not MarketSyncDB.EnableProcessingTab then
                shouldHide = true
            elseif i == 5 and MarketSyncDB and not MarketSyncDB.EnableAlertsTab then
                shouldHide = true
            elseif i == 6 and MarketSyncDB and MarketSyncDB.EnableDebuggingTab == false
                and not MainFrame.debuggingOpenOverride then
                shouldHide = true
            end

            if shouldHide then
                tab:Hide()
            else
                table.insert(visibleTabs, tab)
            end
        end

        local numVisible = #visibleTabs
        if numVisible == 0 then return end

        -- Calculate balanced tab width across the 832px window:
        -- 7 tabs: 104px (span ~714px)
        -- 6 tabs: 112px (span ~660px)
        -- <=5 tabs: 120px (span ~590px)
        local tabWidth = 104
        if legacyTheme then
            tabWidth = numVisible <= 5 and 126 or (numVisible == 6 and 116 or 106)
        elseif numVisible >= 9 then
            tabWidth = 86
        elseif numVisible >= 8 then
            tabWidth = 96
        elseif numVisible <= 5 then
            tabWidth = 120
        elseif numVisible == 6 then
            tabWidth = 112
        end

        local overlap = -2  -- 2px overlap for seamless end-cap docking without clipping text

        MainFrame.tabPadding = 0
        MainFrame.minTabWidth = tabWidth
        MainFrame.maxTabWidth = tabWidth

        local lastVisible = nil
        for idx, tab in ipairs(visibleTabs) do
            tab:ClearAllPoints()
            tab:Show()

            tab:SetHeight(32)
            tab:SetWidth(tabWidth)

            if legacyTheme then
                if tab.Text then tab.Text:SetWidth(0) end
                if PanelTemplates_TabResize then
                    PanelTemplates_TabResize(tab, 4)
                end
            else
                if tab.Text then
                    tab.Text:SetWidth(tabWidth - 16)
                end
                if PanelTemplates_TabResize then
                    PanelTemplates_TabResize(tab, 0, tabWidth)
                end
            end

            if not lastVisible and legacyTheme then
                tab:SetPoint("TOPLEFT", MainFrame, "BOTTOMLEFT", 48, 12)
            elseif legacyTheme then
                tab:SetPoint("TOPLEFT", lastVisible, "TOPRIGHT", -12, 0)
            elseif not lastVisible then
                -- First visible tab docks to the bottom border of MainFrame
                -- -28 from BOTTOMLEFT aligns the tab top to the bottom border gold trim
                tab:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 19, -28)
            else
                -- Subsequent tabs anchor by BOTTOMLEFT to previous tab's BOTTOMRIGHT + overlap
                -- This guarantees ALL tab bottoms and tops remain perfectly aligned at identical Y
                tab:SetPoint("BOTTOMLEFT", lastVisible, "BOTTOMRIGHT", overlap, 0)
            end
            lastVisible = tab
        end

        -- Ensure current selected tab retains elevated frame level
        if MainFrame.selectedTab then
            local selTab = MainFrame.tabs[MainFrame.selectedTab]
            if selTab and not selTab:IsShown() then
                SelectTab(1)
            else
                SelectTab(MainFrame.selectedTab)
            end
        else
            SelectTab(1)
        end
    end
    MainFrame.RefreshTabVisibility = RefreshTabVisibility
    MarketSync.RefreshTabVisibility = RefreshTabVisibility
    RefreshTabVisibility()

    MainFrame:HookScript("OnShow", function(self)
        if self.RefreshTabVisibility then
            self:RefreshTabVisibility()
        end
    end)

    -- ================================================================
    -- TAB 1, 2, 3: BROWSE PANELS (Personal / Guild / Neutral)
    -- ================================================================
    -- TAB 1: MAIN. Personal and Guild share one host; the Source selector picks one.
    MainHost = CreateFrame("Frame", nil, MainFrame)
    MainHost:SetAllPoints(MainFrame)
    MainHost:Hide()
    table.insert(contentFrames, MainHost)

    BrowseContent = MarketSync.CreateBrowsePanel(MainHost, "personal")
    BrowseContent:Hide()
    SyncContent = MarketSync.CreateBrowsePanel(MainHost, "guild")
    SyncContent:Hide()

    -- TAB 2: NEUTRAL AH
    NeutralContent = MarketSync.CreateBrowsePanel(MainFrame, "neutral")
    NeutralContent:Hide()
    table.insert(contentFrames, NeutralContent)

    -- TAB 4: UNIFIED ANALYTICS PANEL
    AnalyticsPanel = MarketSync.CreateAnalyticsPanel and MarketSync.CreateAnalyticsPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    AnalyticsPanel:SetAllPoints()
    AnalyticsPanel:Hide()
    MainFrame.analyticsPanel = AnalyticsPanel
    table.insert(contentFrames, AnalyticsPanel)

    -- TAB 5: PROCESSING PANEL
    ProcessingContent = MarketSync.CreateProcessingPanel and MarketSync.CreateProcessingPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    ProcessingContent:SetAllPoints()
    ProcessingContent:Hide()
    table.insert(contentFrames, ProcessingContent)

    -- TAB 6: ALERTS PANEL
    NotificationsContent = MarketSync.CreateNotificationsPanel and MarketSync.CreateNotificationsPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    NotificationsContent:SetAllPoints()
    NotificationsContent:Hide()
    table.insert(contentFrames, NotificationsContent)

    -- ================================================================
    -- MAIN TAB SOURCE SELECTOR (Personal / Guild)
    -- Sits in the top-right dead space of the Main tab.
    -- ================================================================
    local sourceButtons = {}
    local function MakeSourceButton(label, source, offsetX)
        local btn = CreateFrame("Button", nil, MainHost, "UIPanelButtonTemplate")
        btn:SetSize(84, 22)
        btn:SetText(label)
        btn:SetPoint("TOPRIGHT", MainHost, "TOPRIGHT", offsetX, -30)
        btn:SetScript("OnClick", function() MarketSync.ApplyMainSource(source, true) end)
        sourceButtons[source] = btn
        return btn
    end
    MakeSourceButton("Guild", "guild", -18)
    MakeSourceButton("Personal", "personal", -106)
    MainHost.sourceButtons = sourceButtons
    MainFrame.sourceButtons = sourceButtons

    -- Shows the chosen source (personal or guild) on the Main tab. The guild
    -- source is unavailable while PassiveSync is off, so it falls back to personal.
    function MarketSync.ApplyMainSource(source, userChosen)
        if source ~= "guild" then source = "personal" end
        if source == "guild" and MarketSyncDB and MarketSyncDB.PassiveSync == false then
            source = "personal"
        end
        MainFrame.mainSource = source
        if MarketSyncDB then MarketSyncDB.MainSource = source end
        local function ShowIf(frame, show)
            if not frame then return end
            if show then frame:Show() else frame:Hide() end
        end
        ShowIf(BrowseContent, source == "personal")
        ShowIf(SyncContent, source == "guild")
        ShowIf(sourceButtons.guild, not (MarketSyncDB and MarketSyncDB.PassiveSync == false))
        for key, btn in pairs(sourceButtons) do
            if btn.LockHighlight and btn.UnlockHighlight then
                if key == source then btn:LockHighlight() else btn:UnlockHighlight() end
            end
        end
        if userChosen and MarketSyncDB and not MarketSyncDB.LowRamMode then
            if source == "guild" and MarketSync.LoadGuildCache then
                MarketSync.LoadGuildCache()
            elseif MarketSync.LoadPersonalCache then
                MarketSync.LoadPersonalCache()
            end
        end
    end
    MarketSync.ApplyMainSource(MarketSyncDB and MarketSyncDB.MainSource or "personal")

    -- Global function to show item history from any browse panel (redirected to unified modern Analytics)
    function MarketSync.ShowItemHistory(dbKey, itemLink, name, icon, price, sourceTab)
        if MarketSync.ShowAnalytics then
            MarketSync.ShowAnalytics(dbKey, itemLink, name, icon, price)
        end
    end

    -- ================================================================
    -- TAB 7: DEBUGGING (configuration is in Blizzard AddOns settings)
    -- ================================================================
    SettingsContent = CreateFrame("Frame", nil, MainFrame)
    SettingsContent:SetAllPoints()
    SettingsContent:Hide()
    table.insert(contentFrames, SettingsContent)


    -- --- SETTINGS UI FRAMES ---
    local function CreateBox(parent, w, h, x, y)
        return MarketSync.CreateModernInset(parent, x, y, w, h)
    end

    -- Four categorized columns
    local TOP_Y     = -70
    local CONTENT_H = 338
    local COL1_X    = 18
    local COL2_X    = 210
    local COL3_X    = 410
    local COL4_X    = 600

    local COL1_W    = 188 -- Column 1: Performance & Memory
    local COL2_W    = 196 -- Column 2: Professions & AH
    local COL3_W    = 186 -- Column 3: Audio & Notifications
    local COL4_W    = 218 -- Column 4: Sync & Swarm + Beta

    local boxMemory = CreateBox(SettingsContent, COL1_W, CONTENT_H, COL1_X, TOP_Y)
    local boxAH     = CreateBox(SettingsContent, COL2_W, CONTENT_H, COL2_X, TOP_Y)
    local boxAudio  = CreateBox(SettingsContent, COL3_W, CONTENT_H, COL3_X, TOP_Y)
    local boxSwarm  = CreateBox(SettingsContent, COL4_W, CONTENT_H, COL4_X, TOP_Y)

    -- ================================================================
    -- HELPER: AttachTooltip & CreateCheckbox
    -- ================================================================
    local function AttachTooltip(frame, text)
        if not text or text == "" then return end
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function CreateCheckbox(parent, anchor, anchorPoint, label, tooltipText)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        if anchorPoint then
            cb:SetPoint("TOPLEFT", anchor, anchorPoint, 0, -6)
        else
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        end
        cb.text:SetText(label)
        cb.text:SetFontObject("GameFontHighlightSmall")
        cb.text:SetWidth(152)
        cb.text:SetJustifyH("LEFT")
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        AttachTooltip(cb, tooltipText)
        return cb
    end

    -- ================================================================
    -- COLUMN 1: PERFORMANCE & MEMORY MANAGEMENT
    -- ================================================================
    local header1 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header1:SetPoint("TOP", boxMemory, "TOP", 0, 16)
    header1:SetTextColor(1, 0.82, 0)
    header1:SetText("Performance & Memory")

    local UpdateMemorySettingsVisibility
    local chkCache
    local speedHeader

    local chkLowRam = CreateCheckbox(boxMemory, boxMemory, "TOPLEFT",
        "Enable Low RAM Mode", "Wipe search caches and run Lua garbage collection when windows are closed. Recommended on by default.")
    chkLowRam:ClearAllPoints()
    chkLowRam:SetPoint("TOPLEFT", boxMemory, "TOPLEFT", 12, -10)
    chkLowRam:SetScript("OnClick", function(self)
        MarketSyncDB.LowRamMode = self:GetChecked()
        if not self:GetChecked() then
            if MarketSyncDB.BuildCacheOnStartup and MarketSync.BuildSearchIndex then
                MarketSync.BuildSearchIndex()
            end
        end
        if UpdateMemorySettingsVisibility then UpdateMemorySettingsVisibility() end
    end)
    chkLowRam:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.LowRamMode) end
        if UpdateMemorySettingsVisibility then UpdateMemorySettingsVisibility() end
    end)

    chkCache = CreateCheckbox(boxMemory, chkLowRam, "BOTTOMLEFT",
        "Pre-Build on Startup", "Pre-load and index item data shortly after login (disabled by default in Low RAM mode).")
    chkCache:SetScript("OnClick", function(self)
        MarketSyncDB.BuildCacheOnStartup = self:GetChecked()
    end)
    chkCache:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.BuildCacheOnStartup) end
    end)

    -- Cache Build Speed Slider
    speedHeader = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    speedHeader:SetPoint("TOPLEFT", chkCache, "BOTTOMLEFT", 4, -10)
    speedHeader:SetText("Cache Build Speed")
    speedHeader:SetTextColor(1, 0.82, 0)

    UpdateMemorySettingsVisibility = function()
        local isLowRam = MarketSyncDB and (MarketSyncDB.LowRamMode ~= false)
        if isLowRam then
            if chkCache then chkCache:Hide() end
            if speedHeader then
                speedHeader:ClearAllPoints()
                speedHeader:SetPoint("TOPLEFT", chkLowRam, "BOTTOMLEFT", 4, -12)
            end
        else
            if chkCache then chkCache:Show() end
            if speedHeader then
                speedHeader:ClearAllPoints()
                speedHeader:SetPoint("TOPLEFT", chkCache, "BOTTOMLEFT", 4, -10)
            end
        end
    end

    local speedSlider = CreateFrame("Slider", "MarketSyncMainCacheSpeedSlider", boxMemory, "OptionsSliderTemplate")
    speedSlider:SetPoint("TOPLEFT", speedHeader, "BOTTOMLEFT", 6, -14)
    speedSlider:SetWidth(110)
    speedSlider:SetMinMaxValues(1, 4)
    speedSlider:SetValueStep(1)
    speedSlider:SetObeyStepOnDrag(true)
    speedSlider.Low:SetText("1")
    speedSlider.High:SetText("4")

    local sliderTrack = speedSlider:CreateTexture(nil, "BACKGROUND")
    sliderTrack:SetColorTexture(MarketSync.GetThemeColor("scrollTrack", 0.8))
    sliderTrack:SetHeight(4)
    sliderTrack:SetPoint("LEFT", speedSlider, "LEFT", 4, 0)
    sliderTrack:SetPoint("RIGHT", speedSlider, "RIGHT", -4, 0)

    local sliderTrackBorder = CreateFrame("Frame", nil, speedSlider, "BackdropTemplate")
    sliderTrackBorder:SetPoint("TOPLEFT", sliderTrack, "TOPLEFT", -1, 1)
    sliderTrackBorder:SetPoint("BOTTOMRIGHT", sliderTrack, "BOTTOMRIGHT", 1, -1)
    sliderTrackBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    sliderTrackBorder:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))

    local speedLabel = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    speedLabel:SetPoint("LEFT", speedSlider, "RIGHT", 8, 0)
    speedLabel:SetWidth(50)
    speedLabel:SetJustifyH("LEFT")

    local speedDesc = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    speedDesc:SetPoint("TOPLEFT", speedSlider, "BOTTOMLEFT", -6, -8)
    speedDesc:SetWidth(168)
    speedDesc:SetJustifyH("LEFT")

    local function UpdateSpeedDisplay(val)
        local preset = MarketSync.CacheSpeedPresets and MarketSync.CacheSpeedPresets[val]
        if preset then
            speedLabel:SetText("|cffffd700" .. preset.name .. "|r")
            speedDesc:SetText(preset.desc)
        end
        speedSlider.Text:SetText("")
    end

    speedSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        MarketSyncDB.CacheSpeed = val
        UpdateSpeedDisplay(val)
    end)
    speedSlider:SetScript("OnShow", function(self)
        local val = (MarketSyncDB and MarketSyncDB.CacheSpeed) or 2
        self:SetValue(val)
        UpdateSpeedDisplay(val)
    end)
    AttachTooltip(speedSlider, "Controls background indexing yield rate and batch size when building search caches or resolving item data.")

    local themeHeader = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    themeHeader:SetPoint("TOPLEFT", boxMemory, "TOPLEFT", 12, -220)
    themeHeader:SetText("Window Theme")
    local themeDropdown = CreateFrame("Frame", nil, boxMemory, "UIDropDownMenuTemplate")
    themeDropdown:SetPoint("TOPLEFT", themeHeader, "BOTTOMLEFT", -15, -4)
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(themeDropdown, 130) end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(themeDropdown, function()
            for _, theme in ipairs({{"auto", "Auto (game version)"}, {"forever", "Forever"}, {"legacy", "Legacy"}}) do
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = theme[2], theme[1]
                info.checked = MarketSync.GetUIThemePreference and MarketSync.GetUIThemePreference() == theme[1]
                info.func = function()
                    if CloseDropDownMenus then CloseDropDownMenus() end
                    if MarketSync.SetUITheme then MarketSync.SetUITheme(theme[1]) end
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
    end
    themeDropdown:SetScript("OnShow", function(self)
        if UIDropDownMenu_SetText then
            local preference = MarketSync.GetUIThemePreference and MarketSync.GetUIThemePreference() or "auto"
            UIDropDownMenu_SetText(self, preference == "auto" and "Auto (" .. (MarketSync.GetUITheme() == "legacy" and "Legacy" or "Forever") .. ")"
                or (preference == "legacy" and "Legacy" or "Forever"))
        end
    end)

    local ramText = boxMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ramText:SetPoint("BOTTOMLEFT", boxMemory, "BOTTOMLEFT", 10, 8)
    ramText:SetWidth(168)
    ramText:SetJustifyH("LEFT")
    SettingsContent.ramText = ramText

    -- ================================================================
    -- COLUMN 2: PROFESSIONS & AUCTION HOUSE
    -- ================================================================
    local header2 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header2:SetPoint("TOP", boxAH, "TOP", 0, 16)
    header2:SetTextColor(1, 0.82, 0)
    header2:SetText("Professions & AH")

    local chkTradeSkill = CreateCheckbox(boxAH, boxAH, "TOPLEFT",
        "TradeSkill Costs", "Show crafting costs, profit margins, vendor pricing, and materials tree drawer inside TradeSkill window.")
    chkTradeSkill:ClearAllPoints()
    chkTradeSkill:SetPoint("TOPLEFT", boxAH, "TOPLEFT", 12, -10)
    chkTradeSkill:SetScript("OnClick", function(self)
        MarketSyncDB.EnableProfessionCraftInfo = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r TradeSkill Costs " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MarketSync.RefreshCraftingInfoUI then MarketSync.RefreshCraftingInfoUI() end
    end)
    chkTradeSkill:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableProfessionCraftInfo ~= false) end
    end)

    local chkAnalytics = CreateCheckbox(boxAH, chkTradeSkill, "BOTTOMLEFT",
        "Enable Analytics Tab", "Show price history charts, volume trends, and item stats on both portable window and Auction House.")
    chkAnalytics:SetScript("OnClick", function(self)
        MarketSyncDB.EnableAnalyticsTab = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Analytics " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
    end)
    chkAnalytics:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableAnalyticsTab ~= false) end
    end)

    local chkAuctionatorScan = CreateCheckbox(boxAH, chkAnalytics, "BOTTOMLEFT",
        "Auctionator Scanning", "Let Auctionator perform AH scans and import its price database. Disable to use MarketSync's native scanner.")
    chkAuctionatorScan:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        MarketSyncDB.UseAuctionatorScanner = isChecked
        MarketSyncDB.AuctionatorScannerUserChoice = true
        if isChecked and MarketSync.Scanner and MarketSync.Scanner.Active then
            MarketSync.Scanner.Cancel("Auctionator scanning enabled")
        end
        if MarketSync.Provider then MarketSync.Provider.Select() end
        if isChecked and MarketSync.RegisterAuctionatorHooks then MarketSync.RegisterAuctionatorHooks() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.LegacyScannerPanel
            and MarketSync.AuctionHouse.LegacyScannerPanel.RefreshScannerState then
            MarketSync.AuctionHouse.LegacyScannerPanel.RefreshScannerState()
        end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then
            MarketSync.AuctionHouse.RefreshTabVisibility()
        end
        print("|cFF00FF00[MarketSync]|r Auctionator Scanning " .. (isChecked and "Enabled" or "Disabled"))
    end)
    chkAuctionatorScan:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.UseAuctionatorScanner ~= false) end
    end)

    local chkTooltipPrice = CreateCheckbox(boxAH, chkAuctionatorScan, "BOTTOMLEFT",
        "Tooltip Auction Prices", "Show buyout prices, stack totals, and scan freshness directly on item tooltips.")
    chkTooltipPrice:SetScript("OnClick", function(self)
        MarketSyncDB.EnableTooltipAuctionPrice = self:GetChecked()
    end)
    chkTooltipPrice:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableTooltipAuctionPrice ~= false) end
    end)

    local chkTooltip = CreateCheckbox(boxAH, chkTooltipPrice, "BOTTOMLEFT",
        "Tooltip Probabilities", "Show expected yields and EV values for Prospecting, Milling, and Disenchanting on item tooltips.")
    chkTooltip:SetScript("OnClick", function(self)
        MarketSyncDB.EnableTooltipProb = self:GetChecked()
    end)
    chkTooltip:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableTooltipProb ~= false) end
    end)

    local chkPriceCheck = CreateCheckbox(boxAH, chkTooltip, "BOTTOMLEFT",
        "Chat Price Check '?'", "Answer queries from other players using '? [Item Link]'.")
    chkPriceCheck:SetScript("OnClick", function(self)
        MarketSyncDB.EnableChatPriceCheck = self:GetChecked()
    end)
    chkPriceCheck:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableChatPriceCheck ~= false) end
    end)

    -- Forward declarations for dynamic visibility across columns
    local UpdateAudioSettingsVisibility
    local chkBetaAlerts

    -- ================================================================
    -- COLUMN 3: AUDIO & NOTIFICATIONS
    -- ================================================================
    local header3 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header3:SetPoint("TOP", boxAudio, "TOP", 0, 16)
    header3:SetTextColor(1, 0.82, 0)
    header3:SetText("Audio & Alerts")

    local lockedAudioBox = CreateFrame("Frame", nil, boxAudio)
    lockedAudioBox:SetAllPoints()

    local lockedAudioIcon = lockedAudioBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lockedAudioIcon:SetPoint("TOP", boxAudio, "TOP", 0, -28)
    lockedAudioIcon:SetTextColor(1, 0.67, 0)
    lockedAudioIcon:SetText("[BETA LOCKED]")

    local lockedAudioDesc = lockedAudioBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lockedAudioDesc:SetPoint("TOPLEFT", boxAudio, "TOPLEFT", 12, -56)
    lockedAudioDesc:SetPoint("RIGHT", boxAudio, "RIGHT", -12, 0)
    lockedAudioDesc:SetJustifyH("CENTER")
    lockedAudioDesc:SetSpacing(3)
    lockedAudioDesc:SetText("|cffaaaaaaPrice Alerts & Notifications are currently in Beta.\n\nTurn on '|cffffd700Enable Alerts|r' in the Beta Features panel to unlock notification sounds, volume, and visual alerts.|r")

    local btnUnlockAudio = CreateFrame("Button", nil, lockedAudioBox, "UIPanelButtonTemplate")
    btnUnlockAudio:SetSize(140, 22)
    btnUnlockAudio:SetPoint("TOP", lockedAudioDesc, "BOTTOM", 0, -16)
    btnUnlockAudio:SetText("Enable Alerts (Beta)")
    btnUnlockAudio:SetScript("OnClick", function()
        if MarketSyncDB then MarketSyncDB.EnableAlertsTab = true end
        if chkBetaAlerts then chkBetaAlerts:SetChecked(true) end
        if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
    end)

    local chkNotifSound = CreateCheckbox(boxAudio, boxAudio, "TOPLEFT",
        "Enable Sound Alerts", "Play a sound when a tracked notification request triggers.")
    chkNotifSound:ClearAllPoints()
    chkNotifSound:SetPoint("TOPLEFT", boxAudio, "TOPLEFT", 10, -10)
    chkNotifSound:SetScript("OnClick", function(self)
        MarketSyncDB.EnableNotificationSounds = self:GetChecked()
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
    end)
    chkNotifSound:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNotificationSounds == true) end
    end)

    -- Sound controls
    local soundHeader = boxAudio:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    soundHeader:SetPoint("TOPLEFT", chkNotifSound, "BOTTOMLEFT", 6, -6)
    soundHeader:SetText("Notification Sound")
    soundHeader:SetTextColor(1, 0.82, 0)

    local soundDropdown = CreateFrame("Frame", "MarketSyncMainSoundDropdown", boxAudio, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", soundHeader, "BOTTOMLEFT", -15, -4)
    UIDropDownMenu_SetWidth(soundDropdown, 110)

    local function PlaySelectedSound()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then MarketSync.PlayNotificationSound(soundID, true) end
    end

    local function OnSoundSelect(self)
        MarketSyncDB.NotificationSoundID = self.arg1
        UIDropDownMenu_SetText(soundDropdown, self.value)
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(soundDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            info.text = s.name
            info.value = s.name
            info.arg1 = s.id
            info.func = OnSoundSelect
            info.checked = (MarketSyncDB.NotificationSoundID == s.id)
            UIDropDownMenu_AddButton(info)
        end
    end)

    soundDropdown:SetScript("OnShow", function(self)
        local currentID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            if s.id == currentID then
                UIDropDownMenu_SetText(self, s.name)
                break
            end
        end
    end)

    local btnPlaySound = CreateFrame("Button", nil, boxAudio, "UIPanelButtonTemplate")
    btnPlaySound:SetSize(22, 22)
    btnPlaySound:SetPoint("LEFT", soundDropdown, "RIGHT", -5, 2)
    btnPlaySound:SetText(">")
    btnPlaySound:SetScript("OnClick", PlaySelectedSound)
    AttachTooltip(btnPlaySound, "Preview selected sound.")

    local volSlider = CreateFrame("Slider", "MarketSyncMainVolSlider", boxAudio, "OptionsSliderTemplate")
    volSlider:SetPoint("TOPLEFT", soundDropdown, "BOTTOMLEFT", 20, -12)
    volSlider:SetWidth(135)
    volSlider:SetMinMaxValues(0, 100)
    volSlider:SetValueStep(5)
    volSlider:SetObeyStepOnDrag(true)
    volSlider.Low:SetText("0%")
    volSlider.High:SetText("100%")
    volSlider.Text:SetText("Alert Volume*")

    volSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        MarketSyncDB.NotificationVolume = val / 100
    end)
    volSlider:SetScript("OnShow", function(self)
        self:SetValue((MarketSyncDB and MarketSyncDB.NotificationVolume or 1) * 100)
    end)
    AttachTooltip(volSlider, "Setting this to 0 mutes MarketSync; non-zero alerts follow WoW Master volume.")

    local chkMinimapAlerts = CreateCheckbox(boxAudio, volSlider, "BOTTOMLEFT",
        "Flash Minimap Button", "Flash the MarketSync minimap button until notifications are acknowledged.")
    chkMinimapAlerts:ClearAllPoints()
    chkMinimapAlerts:SetPoint("TOPLEFT", volSlider, "BOTTOMLEFT", -14, -14)
    chkMinimapAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableMinimapAlerts = self:GetChecked() and true or false
        if not MarketSyncDB.EnableMinimapAlerts and MarketSync.StopMinimapFlash then MarketSync.StopMinimapFlash() end
    end)
    chkMinimapAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableMinimapAlerts ~= false) end
    end)

    local chkRaidAlerts = CreateCheckbox(boxAudio, chkMinimapAlerts, "BOTTOMLEFT",
        "Show Alert Banner", "Display triggered notifications in the on-screen raid-warning banner.")
    chkRaidAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableRaidWarningAlerts = self:GetChecked() and true or false
    end)
    chkRaidAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableRaidWarningAlerts ~= false) end
    end)

    UpdateAudioSettingsVisibility = function()
        local alertsEnabled = MarketSyncDB and (MarketSyncDB.EnableAlertsTab == true)
        if not alertsEnabled then
            if lockedAudioBox then lockedAudioBox:Show() end
            if chkNotifSound then chkNotifSound:Hide() end
            if soundHeader then soundHeader:Hide() end
            if soundDropdown then soundDropdown:Hide() end
            if btnPlaySound then btnPlaySound:Hide() end
            if volSlider then volSlider:Hide() end
            if chkMinimapAlerts then chkMinimapAlerts:Hide() end
            if chkRaidAlerts then chkRaidAlerts:Hide() end
        else
            if lockedAudioBox then lockedAudioBox:Hide() end
            if chkNotifSound then chkNotifSound:Show() end
            if chkMinimapAlerts then chkMinimapAlerts:Show() end
            if chkRaidAlerts then chkRaidAlerts:Show() end

            local soundEnabled = MarketSyncDB and (MarketSyncDB.EnableNotificationSounds ~= false)
            if soundEnabled then
                if soundHeader then soundHeader:Show() end
                if soundDropdown then soundDropdown:Show() end
                if btnPlaySound then btnPlaySound:Show() end
                if volSlider then volSlider:Show() end
                if chkMinimapAlerts then
                    chkMinimapAlerts:ClearAllPoints()
                    chkMinimapAlerts:SetPoint("TOPLEFT", volSlider, "BOTTOMLEFT", -14, -14)
                end
            else
                if soundHeader then soundHeader:Hide() end
                if soundDropdown then soundDropdown:Hide() end
                if btnPlaySound then btnPlaySound:Hide() end
                if volSlider then volSlider:Hide() end
                if chkMinimapAlerts then
                    chkMinimapAlerts:ClearAllPoints()
                    chkMinimapAlerts:SetPoint("TOPLEFT", chkNotifSound, "BOTTOMLEFT", 0, -8)
                end
            end
        end
    end

    -- ================================================================
    -- COLUMN 4: SYNC & SWARM + BETA
    -- ================================================================
    local header4 = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header4:SetPoint("TOP", boxSwarm, "TOP", 0, 16)
    header4:SetTextColor(1, 0.82, 0)
    header4:SetText("Sync & Swarm")

    local chkGuild = CreateCheckbox(boxSwarm, boxSwarm, "TOPLEFT",
        "Enable Guild Sync", "Enable or disable guild data syncing.")
    chkGuild:ClearAllPoints()
    chkGuild:SetPoint("TOPLEFT", boxSwarm, "TOPLEFT", 12, -10)
    chkGuild:SetScript("OnClick", function(self)
        MarketSyncDB.PassiveSync = self:GetChecked()
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), self:GetChecked() and nil or "Disabled") end
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    end)
    chkGuild:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.PassiveSync) end
    end)

    local chkNeutral = CreateCheckbox(boxSwarm, chkGuild, "BOTTOMLEFT",
        "Enable Neutral AH Sync", "Enable or disable Neutral Auction House syncing.")
    chkNeutral:SetScript("OnClick", function(self)
        MarketSyncDB.EnableNeutralSync = self:GetChecked()
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), self:GetChecked() and nil or "Disabled") end
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
    end)
    chkNeutral:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableNeutralSync ~= false) end
    end)

    local chkLock = CreateCheckbox(boxSwarm, chkNeutral, "BOTTOMLEFT",
        "Lock Minimap Button", "Prevent the minimap button from being dragged.")
    chkLock:SetScript("OnClick", function(self)
        if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = {} end
        MarketSyncDB.MinimapIcon.locked = self:GetChecked()
    end)
    chkLock:SetScript("OnShow", function(self)
        if MarketSyncDB and MarketSyncDB.MinimapIcon then self:SetChecked(MarketSyncDB.MinimapIcon.locked) end
    end)

    local rightStatsText = boxSwarm:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rightStatsText:SetPoint("TOPLEFT", chkLock, "BOTTOMLEFT", 4, -8)
    rightStatsText:SetWidth(200)
    rightStatsText:SetJustifyH("LEFT")
    rightStatsText:SetSpacing(2)
    SettingsContent.rightStatsText = rightStatsText

    local btnManageUsers = CreateFrame("Button", nil, boxSwarm, "UIPanelButtonTemplate")
    btnManageUsers:SetSize(96, 20)
    btnManageUsers:SetPoint("TOPLEFT", rightStatsText, "BOTTOMLEFT", 0, -8)
    btnManageUsers:SetText("Manage Users")
    AttachTooltip(btnManageUsers, "Block or unblock sync partners.")

    local btnSmartBandwidth = CreateFrame("Button", nil, boxSwarm, "UIPanelButtonTemplate")
    btnSmartBandwidth:SetSize(96, 20)
    btnSmartBandwidth:SetPoint("LEFT", btnManageUsers, "RIGHT", 8, 0)
    btnSmartBandwidth:SetText("Smart Rules")
    AttachTooltip(btnSmartBandwidth, "Configure where background sync and cache indexing are allowed.")

    -- Open AddOn Settings shortcut button
    local btnOpenBlizzSettings = CreateFrame("Button", nil, boxSwarm, "UIPanelButtonTemplate")
    btnOpenBlizzSettings:SetSize(200, 22)
    btnOpenBlizzSettings:SetPoint("TOPLEFT", btnManageUsers, "BOTTOMLEFT", 0, -8)
    btnOpenBlizzSettings:SetText("Open AddOn Settings")
    AttachTooltip(btnOpenBlizzSettings, "Open Blizzard's AddOn Settings menu for full categorized configuration.")
    btnOpenBlizzSettings:SetScript("OnClick", function()
        if MarketSync.OpenSettings then MarketSync.OpenSettings() end
    end)

    -- BETA FEATURES SUBSECTION (at bottom of Box 4)
    local betaBox = CreateFrame("Frame", nil, boxSwarm, "BackdropTemplate")
    betaBox:SetPoint("TOPLEFT", btnOpenBlizzSettings, "BOTTOMLEFT", -2, -8)
    betaBox:SetPoint("BOTTOMRIGHT", boxSwarm, "BOTTOMRIGHT", -8, 8)
    betaBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    betaBox:SetBackdropColor(MarketSync.GetThemeColor("inset"))
    betaBox:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))

    local betaTopHighlight = betaBox:CreateTexture(nil, "BORDER")
    betaTopHighlight:SetHeight(1)
    betaTopHighlight:SetPoint("TOPLEFT", 1, -1)
    betaTopHighlight:SetPoint("TOPRIGHT", -1, -1)
    betaTopHighlight:SetColorTexture(MarketSync.GetThemeColor("border"))

    local betaHeader = betaBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    betaHeader:SetPoint("TOPLEFT", betaBox, "TOPLEFT", 8, -6)
    betaHeader:SetText("|cffffaa00Beta Features|r")

    local betaBadge = betaBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    betaBadge:SetPoint("LEFT", betaHeader, "RIGHT", 4, 0)
    betaBadge:SetText("|cffff6600[BETA]|r")

    local chkBetaProcessing = CreateCheckbox(betaBox, betaHeader, "BOTTOMLEFT",
        "Enable Processing", "Show the Processing tab (materials solver, arbitrage, and batch crafting) on portable window and Auction House.")
    chkBetaProcessing:ClearAllPoints()
    chkBetaProcessing:SetPoint("TOPLEFT", betaBox, "TOPLEFT", 6, -24)
    chkBetaProcessing:SetScript("OnClick", function(self)
        MarketSyncDB.EnableProcessingTab = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Processing " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
    end)
    chkBetaProcessing:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableProcessingTab == true) end
    end)

    chkBetaAlerts = CreateCheckbox(betaBox, chkBetaProcessing, "BOTTOMLEFT",
        "Enable Alerts", "Show the Alerts tab (price alerts, watchlist, and deal triggers) on both the portable window and Auction House.")
    chkBetaAlerts:SetScript("OnClick", function(self)
        MarketSyncDB.EnableAlertsTab = self:GetChecked()
        print("|cFF00FF00[MarketSync]|r Alerts " .. (self:GetChecked() and "Enabled" or "Disabled"))
        if MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        if UpdateAudioSettingsVisibility then UpdateAudioSettingsVisibility() end
    end)
    chkBetaAlerts:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.EnableAlertsTab == true) end
    end)

    local chkDebug = CreateCheckbox(betaBox, chkBetaAlerts, "BOTTOMLEFT",
        "Debug Messages", "Print verbose synchronization and scanner diagnostics in chat.")
    chkDebug:ClearAllPoints()
    chkDebug:SetPoint("TOPLEFT", chkBetaAlerts, "BOTTOMLEFT", 0, -8)
    chkDebug:SetScript("OnClick", function(self)
        MarketSyncDB.DebugMode = self:GetChecked()
    end)
    chkDebug:SetScript("OnShow", function(self)
        if MarketSyncDB then self:SetChecked(MarketSyncDB.DebugMode == true) end
    end)

    -- ================================================================
    -- Gold Bar Buttons & Labels
    -- ================================================================
    -- Rebuild button
    local btnRebuildIndex = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnRebuildIndex:SetSize(75, 19)
    btnRebuildIndex:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -170, 17)
    btnRebuildIndex:SetText("Rebuild")
    AttachTooltip(btnRebuildIndex, "Manually rebuild personal, guild, and neutral browse caches.")

    -- Reset button
    local btnResetData = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnResetData:SetSize(75, 19)
    btnResetData:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -90, 17)
    btnResetData:SetText("Reset")
    AttachTooltip(btnResetData, "|cffff4444Wipe sync data and create a new personal snapshot.|r")

    -- Console button 
    local btnNetworkMonitor = CreateFrame("Button", nil, SettingsContent, "UIPanelButtonTemplate")
    btnNetworkMonitor:SetSize(80, 19)
    btnNetworkMonitor:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -8, 17)
    btnNetworkMonitor:SetText("Console")
    AttachTooltip(btnNetworkMonitor, "View network stream and cache logs.")

    -- Labels (Perfectly aligned above the buttons)
    local lblCache = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lblCache:SetPoint("BOTTOM", btnRebuildIndex, "TOP", 0, 5)
    lblCache:SetText("Cache")

    local lblData = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lblData:SetPoint("BOTTOM", btnResetData, "TOP", 0, 5)
    lblData:SetText("Data")

    local lblDebug = SettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lblDebug:SetPoint("BOTTOM", btnNetworkMonitor, "TOP", 0, 5)
    lblDebug:SetText("Debug")

    local smartRulesFrame = (MarketSync.Theme and MarketSync.Theme.CreateStandardWindow
        and MarketSync.Theme.CreateStandardWindow("MarketSyncSmartRulesFrame", "Smart Bandwidth Rules", 460, 326, "Interface\\Icons\\Spell_Nature_TimeStop"))
        or MarketSync.CreateModernDialog("MarketSyncSmartRulesFrame", 460, 326, "|cFFFFD100Smart Bandwidth Rules|r")
    smartRulesFrame:SetPoint("CENTER")

    local isLegacyPopup = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local swDesc = smartRulesFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    swDesc:SetPoint("TOPLEFT", 68, isLegacyPopup and -41 or -34)
    swDesc:SetWidth(372)
    swDesc:SetJustifyH("LEFT")
    swDesc:SetText("|cff888888Automatically suspend background operations to protect your network ping.|r")

    local rulesInset = MarketSync.CreateModernInset(smartRulesFrame, 18, isLegacyPopup and -72 or -68, 424, isLegacyPopup and 206 or 212)

    local function CreateSmartCheckbox(parent, label, key, xOffset, yOffset)
        local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", xOffset, yOffset)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
        cb.text:SetText(label)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(MarketSyncDB and MarketSyncDB[key])
        end)
        cb:SetScript("OnClick", function(self)
            if MarketSyncDB then MarketSyncDB[key] = self:GetChecked() end
        end)
        return cb
    end

    local syncLabel = rulesInset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    syncLabel:SetPoint("TOPLEFT", 16, -14)
    syncLabel:SetText("|cffffd700Allow Swarm Sync in:|r")

    CreateSmartCheckbox(rulesInset, "Combat", "AllowSyncInCombat", 20, -36)
    CreateSmartCheckbox(rulesInset, "Raids", "AllowSyncInRaid", 20, -66)
    CreateSmartCheckbox(rulesInset, "Dungeons / Parties", "AllowSyncInDungeon", 20, -96)
    CreateSmartCheckbox(rulesInset, "Battlegrounds", "AllowSyncInPvP", 20, -126)
    CreateSmartCheckbox(rulesInset, "Arenas", "AllowSyncInArena", 20, -156)

    local cacheLabel = rulesInset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cacheLabel:SetPoint("TOPLEFT", 216, -14)
    cacheLabel:SetText("|cffffd700Allow Cache Indexer in:|r")

    CreateSmartCheckbox(rulesInset, "Combat", "AllowCacheInCombat", 220, -36)
    CreateSmartCheckbox(rulesInset, "Raids", "AllowCacheInRaid", 220, -66)
    CreateSmartCheckbox(rulesInset, "Dungeons / Parties", "AllowCacheInDungeon", 220, -96)
    CreateSmartCheckbox(rulesInset, "Battlegrounds", "AllowCacheInPvP", 220, -126)
    CreateSmartCheckbox(rulesInset, "Arenas", "AllowCacheInArena", 220, -156)

    local btnCloseRules = CreateFrame("Button", nil, smartRulesFrame, "UIPanelButtonTemplate")
    btnCloseRules:SetSize(80, 22)
    btnCloseRules:SetPoint("BOTTOMRIGHT", smartRulesFrame, "BOTTOMRIGHT", -18, isLegacyPopup and 14 or 10)
    btnCloseRules:SetText("Close")
    btnCloseRules:SetScript("OnClick", function() smartRulesFrame:Hide() end)

    MarketSync.SmartRulesFrame = smartRulesFrame
    function MarketSync.ShowSmartRulesDialog()
        if not smartRulesFrame then return end
        if smartRulesFrame:IsShown() then smartRulesFrame:Hide() else smartRulesFrame:Show() end
    end

    btnSmartBandwidth:SetScript("OnClick", function()
        MarketSync.ShowSmartRulesDialog()
    end)

    btnNetworkMonitor:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then
            MarketSync.ToggleNetworkMonitor()
        end
    end)

    -- (Rebuild and Reset button scripts below use the exact same functionality, but have been repositioned above)

    btnRebuildIndex:SetScript("OnClick", function()
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        if MarketSync.BuildSearchIndex then
            MarketSync.BuildSearchIndex()
            if MarketSyncDB and MarketSyncDB.DebugMode then
                print("|cFF00FF00[MarketSync]|r Triggered manual index rebuild.")
            end
        end
    end)

    -- ================================================================
    -- USER MANAGEMENT POPUP
    -- ================================================================
    local userMgmtFrame = (MarketSync.Theme and MarketSync.Theme.CreateStandardWindow
        and MarketSync.Theme.CreateStandardWindow("MarketSyncUserMgmt", "User Management", 460, 490, "Interface\\Icons\\INV_Misc_GroupLooking"))
        or MarketSync.CreateModernDialog("MarketSyncUserMgmt", 460, 490, "|cFFFFD100User Management|r")
    userMgmtFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

    local umDesc = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    umDesc:SetPoint("TOPLEFT", 68, isLegacyPopup and -41 or -34)
    umDesc:SetWidth(372)
    umDesc:SetJustifyH("LEFT")
    umDesc:SetText("|cff888888Manage peer sync status. Blocked users' data is not accepted or stored.|r")

    -- Manual Block Input Box & Button
    local addBox = CreateFrame("EditBox", nil, userMgmtFrame, "InputBoxTemplate")
    addBox:SetSize(230, 20)
    addBox:SetPoint("TOPLEFT", 24, -68)
    addBox:SetAutoFocus(false)
    addBox:SetText("")
    addBox:SetMaxLetters(40)

    local addPlaceholder = addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    addPlaceholder:SetPoint("LEFT", 4, 0)
    addPlaceholder:SetText("Enter player name to block...")
    addBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then addPlaceholder:Show() else addPlaceholder:Hide() end
    end)
    addBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local addBtn = CreateFrame("Button", nil, userMgmtFrame, "UIPanelButtonTemplate")
    addBtn:SetSize(96, 22)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
    addBtn:SetText("Block Player")

    -- Column Headers
    local hdrPlayer = MarketSync.CreateAHColumnHeader(userMgmtFrame, 224, 20, "Player")
    hdrPlayer:SetPoint("TOPLEFT", 18, -98)

    local hdrStatus = MarketSync.CreateAHColumnHeader(userMgmtFrame, 90, 20, "Status")
    hdrStatus:SetPoint("LEFT", hdrPlayer, "RIGHT", 0, 0)

    local hdrAction = MarketSync.CreateAHColumnHeader(userMgmtFrame, 110, 20, "Action")
    hdrAction:SetPoint("LEFT", hdrStatus, "RIGHT", 0, 0)

    -- Inset Panel for table rows
    local listInset = MarketSync.CreateModernInset(userMgmtFrame, 18, -120, 424, 322)

    local scrollFrame = CreateFrame("ScrollFrame", "MarketSyncUserMgmtScrollFrame", listInset, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -14, 2)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(scrollFrame) end
    scrollFrame:EnableMouseWheel(true)

    local umScrollChild = CreateFrame("Frame", nil, scrollFrame)
    umScrollChild:SetSize(374, 1)
    scrollFrame:SetScrollChild(umScrollChild)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = 26
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, cur - step))
        else
            self:SetVerticalScroll(math.min(maxScroll, cur + step))
        end
    end)

    local emptyText = umScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyText:SetPoint("TOP", umScrollChild, "TOP", 0, -50)
    emptyText:SetWidth(340)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText("|cff888888No sync peers recorded yet.|r\n|cff555555Synced guild members or blocked players will appear here.|r")

    local summaryText = userMgmtFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summaryText:SetPoint("LEFT", userMgmtFrame, "BOTTOMLEFT", 16, 22)
    summaryText:SetText("Total: 0 peers")

    local btnCloseUserMgmt = CreateFrame("Button", nil, userMgmtFrame, "UIPanelButtonTemplate")
    btnCloseUserMgmt:SetSize(80, 22)
    btnCloseUserMgmt:SetPoint("BOTTOMRIGHT", userMgmtFrame, "BOTTOMRIGHT", -18, isLegacyPopup and 14 or 12)
    btnCloseUserMgmt:SetText("Close")
    btnCloseUserMgmt:SetScript("OnClick", function() userMgmtFrame:Hide() end)

    local blockRows = {}

    local function RefreshUserList()
        for _, r in pairs(blockRows) do r:Hide() end
        local count = 0
        local activeCount = 0
        local blockedCount = 0

        local allUsers = {}
        local contributors = {}
        if MarketSync.GetSyncContributorSnapshot then
            contributors = select(1, MarketSync.GetSyncContributorSnapshot(true)) or {}
        end
        for _, user in ipairs(contributors) do
            allUsers[user] = true
        end
        if MarketSyncDB and MarketSyncDB.BlockedUsers then
            for u, _ in pairs(MarketSyncDB.BlockedUsers) do
                allUsers[u] = true
            end
        end

        local sortedUsers = {}
        for user in pairs(allUsers) do
            table.insert(sortedUsers, user)
        end
        table.sort(sortedUsers)

        for _, user in ipairs(sortedUsers) do
            count = count + 1
            local row = blockRows[count]
            if not row then
                row = CreateFrame("Button", nil, umScrollChild)
                row:SetSize(374, 24)

                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                row.bg = bg

                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
                if hl.SetBlendMode then hl:SetBlendMode("ADD") end
                if hl.SetAlpha then hl:SetAlpha(0.28) end
                row.hl = hl

                row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                row.nameText:SetPoint("LEFT", 10, 0)
                row.nameText:SetWidth(190)
                row.nameText:SetJustifyH("LEFT")

                row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                row.statusText:SetPoint("LEFT", 205, 0)
                row.statusText:SetWidth(80)
                row.statusText:SetJustifyH("LEFT")

                row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.btn:SetSize(75, 20)
                row.btn:SetPoint("RIGHT", -10, 0)
                row.btn:SetScript("OnClick", function(btnSelf)
                    if MarketSync.ToggleBlock then MarketSync.ToggleBlock(btnSelf.user) end
                    RefreshUserList()
                end)

                blockRows[count] = row
            end

            if count % 2 == 1 then
                row.bg:SetColorTexture(MarketSync.GetThemeColor("rowEven"))
            else
                row.bg:SetColorTexture(MarketSync.GetThemeColor("rowOdd"))
            end

            local isBlocked = MarketSyncDB.BlockedUsers and MarketSyncDB.BlockedUsers[user]
            row.nameText:SetText(user)
            if isBlocked then
                blockedCount = blockedCount + 1
                row.statusText:SetText("|cffff4444Blocked|r")
                row.btn:SetText("Unblock")
            else
                activeCount = activeCount + 1
                row.statusText:SetText("|cff00ff00Active|r")
                row.btn:SetText("Block")
            end
            row.btn.user = user
            row:SetPoint("TOPLEFT", 0, -(count - 1) * 25)
            row:Show()
        end

        umScrollChild:SetHeight(math.max(1, count * 25))

        if count == 0 then
            emptyText:Show()
            summaryText:SetText("Total: 0 peers")
        else
            emptyText:Hide()
            summaryText:SetText(string.format("Total: %d peers (|cff00ff00%d Active|r, |cffff4444%d Blocked|r)", count, activeCount, blockedCount))
        end
    end

    local function DoManualBlock()
        local name = strtrim(addBox:GetText() or "")
        if name ~= "" then
            if MarketSync.ToggleBlock then MarketSync.ToggleBlock(name) end
            addBox:SetText("")
            addBox:ClearFocus()
            RefreshUserList()
        end
    end
    addBtn:SetScript("OnClick", DoManualBlock)
    addBox:SetScript("OnEnterPressed", DoManualBlock)

    MarketSync.UserMgmtFrame = userMgmtFrame
    function MarketSync.ShowUserManagementDialog()
        if not userMgmtFrame then return end
        if userMgmtFrame:IsShown() then
            userMgmtFrame:Hide()
        else
            RefreshUserList()
            userMgmtFrame:Show()
        end
    end

    btnManageUsers:SetScript("OnClick", function()
        MarketSync.ShowUserManagementDialog()
    end)

    -- ================================================================
    -- SETTINGS Auto-Refresh Stats
    -- ================================================================
    local function UpdateSettingsStats()
        -- Update DB stats
        local totalItems = 0
        local syncedItems = 0
        local neutralItems = 0
        local uniqueSyncers = 0
        if MarketSyncDB then
            local personalData = MarketSync.GetRealmDB().PersonalData
            if personalData then
                for _ in pairs(personalData) do totalItems = totalItems + 1 end
            end
            if MarketSync.GetRealmDB().ItemMetadata then
                for _ in pairs(MarketSync.GetRealmDB().ItemMetadata) do syncedItems = syncedItems + 1 end
            end
            if MarketSync.GetRealmDB().NeutralData then
                for _ in pairs(MarketSync.GetRealmDB().NeutralData) do neutralItems = neutralItems + 1 end
            end
            if MarketSync.GetSyncContributorSnapshot then
                local contributors = select(1, MarketSync.GetSyncContributorSnapshot(false)) or {}
                uniqueSyncers = #contributors
            end
        end

        -- Cache status (using three-cache API)
        local personalCache = "Not started"
        local guildCache = "Not started"
        local neutralCache = "Not started"
        local idxStatus = MarketSync.GetIndexStatus and MarketSync.GetIndexStatus()
        if idxStatus then
            local function FormatCacheStatus(resolved, total, pending, ready, building)
                if building then
                    if pending > 0 then
                        return "|cffff8800" .. resolved .. "/" .. total .. " (" .. pending .. ")|r"
                    end
                    if total > 0 then
                        return "|cffff8800" .. resolved .. "/" .. total .. "|r"
                    end
                    return "|cffff8800...|r"
                end

                if pending > 0 then
                    return "|cffff8800" .. resolved .. "/" .. total .. " (" .. pending .. ")|r"
                end

                if ready and total > 0 and resolved >= total then
                    return "|cff00ff00" .. resolved .. "/" .. total .. "|r"
                end

                if ready then
                    return "|cff8888880|r"
                end

                return "|cff888888-|r"
            end

            personalCache = FormatCacheStatus(
                idxStatus.personalResolved or 0,
                idxStatus.personalTotal or 0,
                idxStatus.personalPending or 0,
                idxStatus.personalReady,
                idxStatus.personalBuilding
            )

            guildCache = FormatCacheStatus(
                idxStatus.guildResolved or 0,
                idxStatus.guildTotal or 0,
                idxStatus.guildPending or 0,
                idxStatus.guildReady,
                idxStatus.guildBuilding
            )

            neutralCache = FormatCacheStatus(
                idxStatus.neutralResolved or 0,
                idxStatus.neutralTotal or 0,
                idxStatus.neutralPending or 0,
                idxStatus.neutralReady,
                idxStatus.neutralBuilding
            )
        end

        -- Right column: all stats consolidated
        local syncActiveStr = ""
        if idxStatus and idxStatus.guildSyncActive then
            syncActiveStr = "\n|cffff8800Guild Sync In Progress|r (" .. (idxStatus.guildIncoming or 0) .. " incoming)"
        elseif idxStatus and idxStatus.neutralSyncActive then
            syncActiveStr = "\n|cff00ccffNeutral Sync In Progress|r (" .. (idxStatus.neutralIncoming or 0) .. " incoming)"
        end
        SettingsContent.rightStatsText:SetText(
            "|cff00ff00Personal:|r " .. totalItems .. "  |cff00ff00Guild:|r " .. syncedItems .. "\n" ..
            "|cff00ccffNeutral:|r " .. neutralItems .. "  |cff00ff00Partners:|r " .. uniqueSyncers .. "\n" ..
            "|cff00ff00Personal cache:|r " .. personalCache .. "\n" ..
            "|cff00ff00Guild cache:|r " .. guildCache .. "\n" ..
            "|cff00ccffNeutral cache:|r " .. neutralCache ..
            syncActiveStr
        )
        if SettingsContent.ramText and MarketSync.GetEstimatedRAMUsage then
            local estMB, totalStored = MarketSync.GetEstimatedRAMUsage()
            SettingsContent.ramText:SetText(string.format("|cff888888Est. Index RAM:|r |cffffffff~%.1f MB|r\n|cff888888(%d stored items)|r", estMB, totalStored))
        end
    end
    -- The legacy in-window controls are retained only for their existing helper
    -- dialogs (Smart Rules and User Management). Configuration itself now lives
    -- solely in Blizzard's AddOns settings page.
    for _, region in ipairs({boxMemory, boxAH, boxAudio, boxSwarm,
        header1, header2, header3, header4,
        btnRebuildIndex, btnResetData, btnNetworkMonitor,
        lblCache, lblData, lblDebug}) do
        region:Hide()
    end

    -- ================================================================
    -- DEBUGGING & RESOURCE DASHBOARD (Tab 7)
    -- ================================================================
    local isLegacyDebug = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local kpiTopY = isLegacyDebug and -40 or -35
    local kpiHeight = isLegacyDebug and 52 or 56
    local function CreateKpiCard(x, titleLabel)
        local card = MarketSync.CreateModernInset(SettingsContent, x, kpiTopY, 180, kpiHeight)
        local lbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 10, isLegacyDebug and -5 or -6)
        lbl:SetText(titleLabel)
        local val = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPLEFT", 10, isLegacyDebug and -19 or -21)
        val:SetWidth(160)
        val:SetJustifyH("LEFT")
        if val.SetWordWrap then val:SetWordWrap(false) end
        local sub = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("TOPLEFT", val, "BOTTOMLEFT", 0, isLegacyDebug and -2 or -3)
        sub:SetWidth(160)
        sub:SetJustifyH("LEFT")
        if sub.SetWordWrap then sub:SetWordWrap(false) end
        return { frame = card, value = val, sub = sub }
    end

    local kpiRam = CreateKpiCard(70, "MarketSync RAM")
    local kpiPack = CreateKpiCard(258, "MarketSyncData Pack")
    local kpiIndex = CreateKpiCard(446, "Search Indexes")
    local kpiSync = CreateKpiCard(634, "Sync & Scanner")

    local function DebugButton(parent, label, x, y, width, callback, smallFont)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if smallFont and button.SetNormalFontObject then
            button:SetNormalFontObject("GameFontNormalSmall")
            button:SetHighlightFontObject("GameFontHighlightSmall")
        end
        button:SetText(label)
        button:SetScript("OnClick", callback)
        return button
    end

    -- Left Column: Diagnostics Hub & Maintenance Deck
    local dbgLeftX = isLegacyDebug and 25 or 18
    local dbgLeftW = isLegacyDebug and 267 or 274
    local dbgPadX = isLegacyDebug and 9 or 12
    local dbgBtnFullW = dbgLeftW - dbgPadX * 2
    local dbgBtnHalfW = isLegacyDebug and 120 or 121
    local dbgBtnRightX = dbgPadX + dbgBtnHalfW + (dbgBtnFullW - dbgBtnHalfW * 2)
    local hubHdr = MarketSync.CreateAHColumnHeader(SettingsContent, dbgLeftW, 22, "|cffffd100Diagnostics & Admin Hub|r")
    hubHdr:SetPoint("TOPLEFT", dbgLeftX, -97)
    local debugTools = MarketSync.CreateModernInset(SettingsContent, dbgLeftX, -119, dbgLeftW, 160)

    DebugButton(debugTools, "Open Diagnostics Console", dbgPadX, -10, dbgBtnFullW, function()
        if MarketSync.OpenDiagnosticsHub then
            MarketSync.OpenDiagnosticsHub("tasks")
        elseif MarketSync.ToggleTaskManager then
            MarketSync.ToggleTaskManager()
        end
    end)
    DebugButton(debugTools, "Task Manager", dbgPadX, -41, dbgBtnHalfW, function()
        if MarketSync.ToggleTaskManager then MarketSync.ToggleTaskManager() end
    end, true)
    DebugButton(debugTools, "Rate Limiter", dbgBtnRightX, -41, dbgBtnHalfW, function()
        if MarketSync.ToggleRateMonitor then MarketSync.ToggleRateMonitor() end
    end, true)
    DebugButton(debugTools, "Network & Swarm", dbgPadX, -70, dbgBtnHalfW, function()
        if MarketSync.ToggleNetworkMonitor then MarketSync.ToggleNetworkMonitor() end
    end, true)
    DebugButton(debugTools, "Data Pack", dbgBtnRightX, -70, dbgBtnHalfW, function()
        if MarketSync.OpenDiagnosticsDataPack then
            MarketSync.OpenDiagnosticsDataPack()
        elseif MarketSync.ReviewMarketSyncData then
            MarketSync.ReviewMarketSyncData()
        end
    end, true)
    DebugButton(debugTools, "Smart Rules", dbgPadX, -99, dbgBtnHalfW, function()
        if MarketSync.ShowSmartRulesDialog then MarketSync.ShowSmartRulesDialog() end
    end, true)
    DebugButton(debugTools, "Peer Blocklist", dbgBtnRightX, -99, dbgBtnHalfW, function()
        if MarketSync.ShowUserManagementDialog then MarketSync.ShowUserManagementDialog() end
    end, true)
    local hubHint = debugTools:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hubHint:SetPoint("BOTTOMLEFT", dbgPadX, 9)
    hubHint:SetWidth(dbgBtnFullW)
    hubHint:SetJustifyH("LEFT")
    hubHint:SetText("Opens the unified 4-tab Diagnostics window.")

    local maintHdr = MarketSync.CreateAHColumnHeader(SettingsContent, dbgLeftW, 22, "|cffffd100Maintenance & Settings|r")
    maintHdr:SetPoint("TOPLEFT", dbgLeftX, -286)
    local maintBox = MarketSync.CreateModernInset(SettingsContent, dbgLeftX, -308, dbgLeftW, 100)

    DebugButton(maintBox, "Rebuild Index", dbgPadX, -10, dbgBtnHalfW, function()
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        if MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end
    end, true)
    DebugButton(maintBox, "Print Snapshot", dbgBtnRightX, -10, dbgBtnHalfW, function()
        if MarketSync.PrintDiagnosticsSnapshot then MarketSync.PrintDiagnosticsSnapshot() end
    end, true)
    DebugButton(maintBox, "AddOn Settings", dbgPadX, -40, dbgBtnHalfW, function()
        if MarketSync.OpenSettings then MarketSync.OpenSettings() end
    end, true)
    DebugButton(maintBox, "Reset Data...", dbgBtnRightX, -40, dbgBtnHalfW, function()
        if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
            print("|cFFFF8800[MarketSync]|r Wait for the active sync to finish before resetting data.")
        elseif StaticPopup_Show then
            StaticPopup_Show("MARKETSYNC_CONFIRM_MARKET_DATA_RESET")
        end
    end, true)
    local maintNote = maintBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    maintNote:SetPoint("BOTTOMLEFT", dbgPadX, 9)
    maintNote:SetWidth(dbgBtnFullW)
    maintNote:SetJustifyH("LEFT")
    maintNote:SetText("*Shared provider store excluded from subtotal.")

    -- Bottom footer slot status (keeps Classic bottom-left well neatly populated)
    local debugFooterStatus = SettingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    debugFooterStatus:SetPoint("BOTTOMLEFT", SettingsContent, "BOTTOMLEFT", isLegacyDebug and 25 or 28, isLegacyDebug and 20 or 16)
    debugFooterStatus:SetWidth(152)
    debugFooterStatus:SetJustifyH("LEFT")
    if debugFooterStatus.SetWordWrap then debugFooterStatus:SetWordWrap(false) end

    -- Right Column: Striped Storage & Data Pack Footprint Table
    local colSource = MarketSync.CreateAHColumnHeader(SettingsContent, 240, 22, "Component / Data Source")
    colSource:SetPoint("TOPLEFT", 302, -97)
    local colRecords = MarketSync.CreateAHColumnHeader(SettingsContent, 144, 22, "Records / Scope")
    colRecords:SetPoint("LEFT", colSource, "RIGHT", 0, 0)
    local colSize = MarketSync.CreateAHColumnHeader(SettingsContent, 128, 22, "Footprint")
    colSize:SetPoint("LEFT", colRecords, "RIGHT", 0, 0)

    local debugResources = MarketSync.CreateModernInset(SettingsContent, 302, -119, 512, 289)
    local resScroll = CreateFrame("ScrollFrame", nil, debugResources, "UIPanelScrollFrameTemplate")
    resScroll:SetPoint("TOPLEFT", 4, -4)
    resScroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local resContent = CreateFrame("Frame", nil, resScroll)
    resContent:SetSize(480, 281)
    resScroll:SetScrollChild(resContent)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(resScroll) end

    local resourceRows = {}
    local function AcquireResourceRow(idx)
        local row = resourceRows[idx]
        if row then return row end
        row = CreateFrame("Frame", nil, resContent)
        row:SetSize(480, 22)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bar = row:CreateTexture(nil, "BORDER")
        row.bar:SetPoint("TOPRIGHT", -2, -2)
        row.bar:SetPoint("BOTTOMRIGHT", -2, 2)
        row.bar:SetWidth(1)
        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(228)
        row.name:SetJustifyH("LEFT")
        row.records = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.records:SetPoint("LEFT", 240, 0)
        row.records:SetWidth(136)
        row.records:SetJustifyH("LEFT")
        row.size = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.size:SetPoint("RIGHT", -8, 0)
        row.size:SetWidth(98)
        row.size:SetJustifyH("RIGHT")
        resourceRows[idx] = row
        return row
    end

    local function RefreshDebugResources()
        local snapshot = MarketSync.GetDiagnosticsSnapshot and MarketSync.GetDiagnosticsSnapshot() or {}
        local storage, runtime, index = snapshot.storage or {}, snapshot.runtime or {}, snapshot.indexes or {}
        local pack = snapshot.dataPack or {}
        local scan = snapshot.scanner or {}
        local sync = snapshot.sync or {}
        local fmtNum = BreakUpLargeNumbers or tostring

        local function FmtSize(kb)
            local n = tonumber(kb) or 0
            if n >= 1024 then return string.format("%.2f MB", n / 1024) end
            return string.format("%.1f KB", n)
        end

        -- Update Top KPI Strip
        kpiRam.value:SetText(snapshot.addonKB and ("|cffffd100" .. FmtSize(snapshot.addonKB) .. "|r") or "|cff888888Unavailable|r")
        kpiRam.sub:SetText("Heap: " .. (snapshot.luaHeapKB and FmtSize(snapshot.luaHeapKB) or "—"))

        local activePackRows = (storage.dataPackActive or {}).count or 0
        if pack.loaded then
            local packRam = snapshot.dataPackAddonKB or pack.estimatedKB or 0
            local isConnected = activePackRows > 0 or pack.importedMarket ~= nil
            kpiPack.value:SetText(isConnected and "|cff40cf78Connected|r" or "|cffffb14eLoaded|r")
            if activePackRows > 0 then
                kpiPack.sub:SetText(string.format("+%s items · %s", fmtNum(activePackRows), FmtSize(packRam)))
            else
                kpiPack.sub:SetText(string.format("%s items · %s", fmtNum(pack.totalRecords or 0), FmtSize(packRam)))
            end
        else
            kpiPack.value:SetText("|cff888888Not Loaded|r")
            kpiPack.sub:SetText("Optional DataPack addon")
        end

        kpiIndex.value:SetText(string.format("%s · ~%s", fmtNum(runtime.indexRows or 0), FmtSize(runtime.indexEstimatedKB or 0)))
        kpiIndex.sub:SetText(string.format("P:%d  G:%d  N:%d",
            index.personalResolved or 0, index.guildResolved or 0, index.neutralResolved or 0))
        local activeTheme = MarketSync.GetUITheme and MarketSync.GetUITheme() or "auto"
        debugFooterStatus:SetText("UI: " .. (activeTheme == "legacy" and "Classic" or "Forever"))

        local syncState = scan.active and "|cff40cf78Scanning|r"
            or (sync.outbound and "|cffffaa00Sending|r")
            or (sync.inbound and "|cff66ffccReceiving|r")
            or "|cffccccccIdle|r"
        kpiSync.value:SetText(syncState)
        kpiSync.sub:SetText(string.format("%d peers · Queue %d", runtime.peers or 0, runtime.scanQueue or 0))

        -- Build Footprint Table Entries
        local entries = {
            { header = "|cffffd100Client-Measured Add-On Memory|r" },
            {
                name = "MarketSync (Core)",
                records = "Measured RAM",
                size = snapshot.addonKB and FmtSize(snapshot.addonKB) or "Unavailable",
                kb = snapshot.addonKB or 0,
                accent = { 0.85, 0.68, 0.24, 0.22 },
            },
            {
                name = "MarketSyncData (Daily Pack)",
                records = pack.loaded and ("Flavor: " .. tostring(pack.flavor)) or "Addon disabled",
                size = snapshot.dataPackAddonKB and FmtSize(snapshot.dataPackAddonKB) or (pack.loaded and ("~" .. FmtSize(pack.estimatedKB)) or "Not loaded"),
                kb = snapshot.dataPackAddonKB or pack.estimatedKB or 0,
                accent = { 0.25, 0.78, 0.45, 0.22 },
            },
            {
                name = "MarketSyncLedger (Standalone)",
                records = snapshot.ledgerAddonKB and "Loaded" or "Addon disabled",
                size = snapshot.ledgerAddonKB and FmtSize(snapshot.ledgerAddonKB) or "Not loaded",
                kb = snapshot.ledgerAddonKB or 0,
                accent = { 0.35, 0.62, 0.90, 0.22 },
            },
            { header = "|cffffd100MarketSync Tables & Indexes (Sampled)|r" },
        }

        local function AddPart(label, part, unit, isShared)
            local p = part or {}
            local c = p.count or 0
            local kb = p.estimatedKB or 0
            entries[#entries + 1] = {
                name = label,
                records = string.format("%s %s", fmtNum(c), unit or "rows"),
                size = "~" .. FmtSize(kb),
                kb = isShared and 0 or kb,
                accent = isShared and { 0.45, 0.45, 0.50, 0.16 } or { 0.75, 0.60, 0.28, 0.18 },
            }
        end

        AddPart("Personal Scan Data", storage.personal, "items")
        AddPart("Guild Sync Prices", storage.guildPrices, "items")
        AddPart("DataPack Active (in GuildData)", storage.dataPackActive, "items")
        AddPart("Guild Contributor Metadata", storage.guild, "rows")
        AddPart("Neutral / Blackwater AH", storage.neutral, "items")
        entries[#entries + 1] = {
            name = "Active Search Indexes",
            records = string.format("%s resolved", fmtNum(runtime.indexRows or 0)),
            size = "~" .. FmtSize(runtime.indexEstimatedKB or 0),
            kb = runtime.indexEstimatedKB or 0,
            accent = { 0.75, 0.60, 0.28, 0.18 },
        }
        AddPart("Item Info Cache", storage.itemInfo, "items")
        AddPart("Price History Log", storage.history, "rows")
        AddPart("Character Inventories", storage.inventory, "chars")
        local recAlertCount = ((storage.recipes or {}).count or 0) + ((storage.alerts or {}).count or 0)
        local recAlertKB = ((storage.recipes or {}).estimatedKB or 0) + ((storage.alerts or {}).estimatedKB or 0)
        entries[#entries + 1] = {
            name = "Saved Recipes & Alerts",
            records = string.format("%s entries", fmtNum(recAlertCount)),
            size = "~" .. FmtSize(recAlertKB),
            kb = recAlertKB,
            accent = { 0.75, 0.60, 0.28, 0.18 },
        }
        entries[#entries + 1] = {
            name = "|cffffd700MarketSync Storage Subtotal|r",
            records = "Owned SavedVariables",
            size = "|cffffd700~" .. FmtSize(snapshot.storedEstimatedKB or 0) .. "|r",
            kb = 0,
        }
        AddPart("Provider Live Store* (Shared)", storage.provider, "rows", true)

        entries[#entries + 1] = { header = "|cffffd100MarketSyncData Pack Partitions|r" }
        if pack.loaded and #(pack.partitions or {}) > 0 then
            for _, p in ipairs(pack.partitions) do
                entries[#entries + 1] = {
                    name = p.key .. (p.active and " |cff40cf78[Active]|r" or ""),
                    records = string.format("%s items", fmtNum(p.count or 0)),
                    size = "~" .. FmtSize(p.estimatedKB or 0),
                    kb = p.estimatedKB or 0,
                    accent = p.active and { 0.25, 0.78, 0.45, 0.24 } or { 0.40, 0.55, 0.65, 0.16 },
                }
            end
        else
            entries[#entries + 1] = {
                name = "|cff888888No DataPack partitions loaded|r",
                records = pack.loaded and tostring(pack.dataDate or "—") or "Enable MarketSyncData",
                size = "—",
                kb = 0,
            }
        end

        local maxKB = 1024
        for _, e in ipairs(entries) do
            if (e.kb or 0) > maxKB then maxKB = e.kb end
        end

        for _, r in pairs(resourceRows) do r:Hide() end
        local y = 0
        for i, e in ipairs(entries) do
            local row = AcquireResourceRow(i)
            row:SetPoint("TOPLEFT", 0, -y)
            if e.header then
                row.bg:SetColorTexture(MarketSync.GetThemeColor("header"))
                row.bar:Hide()
                row.name:SetWidth(464)
                row.name:SetText(e.header)
                row.records:SetText("")
                row.size:SetText("")
            else
                row.name:SetWidth(228)
                if i % 2 == 0 then
                    row.bg:SetColorTexture(MarketSync.GetThemeColor("rowEven"))
                else
                    row.bg:SetColorTexture(MarketSync.GetThemeColor("rowOdd"))
                end
                if (e.kb or 0) > 0 and e.accent then
                    local pct = math.min(1, e.kb / maxKB)
                    row.bar:SetWidth(math.max(2, math.floor(116 * pct)))
                    row.bar:SetColorTexture(e.accent[1], e.accent[2], e.accent[3], e.accent[4])
                    row.bar:Show()
                else
                    row.bar:Hide()
                end
                row.name:SetText(e.name or "")
                row.records:SetText("|cffbbbbbb" .. tostring(e.records or "") .. "|r")
                row.size:SetText(e.size or "")
            end
            row:Show()
            y = y + 23
        end
        resContent:SetHeight(math.max(290, y + 4))
    end
    SettingsContent.lastUpdate = 0
    SettingsContent:SetScript("OnUpdate", function(self, elapsed)
        self.lastUpdate = self.lastUpdate + elapsed
        if self.lastUpdate >= 5 then
            self.lastUpdate = 0
            RefreshDebugResources()
        end
    end)
    SettingsContent:SetScript("OnShow", function(self)
        self.lastUpdate = 0
        RefreshDebugResources()
    end)

    function MarketSync.OpenDebuggingWindow()
        if not MainFrame:IsShown() then MainFrame:Show() end
        MainFrame.debuggingOpenOverride = true
        RefreshTabVisibility()
        SelectTab(6)
    end
    MainFrame:HookScript("OnHide", function(self)
        if self.debuggingOpenOverride then
            self.debuggingOpenOverride = nil
            RefreshTabVisibility()
        end
    end)

    -- ================================================================
    -- Finalize
    -- ================================================================
    MainFrame.contentFrames = contentFrames
    RefreshTabVisibility()
    SelectTab(1)

    MainFrame:Hide()
    return MainFrame
end

-- ================================================================
MarketSync.CreateMainFrame = CreateMainFrame

-- Global Toggle Function
-- ================================================================
function MarketSync_ToggleUI()
    if not MainFrame then CreateMainFrame() end
    if MainFrame:IsShown() then
        MainFrame:Hide()
    else
        MainFrame:Show()
        if MarketSync.BuildSearchIndex then
            MarketSync.BuildSearchIndex()
        end
    end
end
