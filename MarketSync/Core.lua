-- =============================================================
-- MarketSync - Init, Minimap, Options, Slash Commands
-- Entry point that ties all modules together
-- =============================================================

local ADDON_NAME = MarketSync.ADDON_NAME
local category  -- Forward declaration for minimap/options access

if not StaticPopupDialogs then StaticPopupDialogs = {} end
StaticPopupDialogs["MARKETSYNC_CONFIRM_SESSION_MUTE"] = {
    text = "Mute all MarketSync alerts for this session? You can turn them back on with Shift-Left-Click on the minimap button. This confirmation appears only once.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        MarketSyncDB.NotificationMuteConfirmed = true
        if MarketSync.ToggleNotificationMute then MarketSync.ToggleNotificationMute() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ================================================================
-- MINIMAP BUTTON
-- ================================================================
local function CreateMinimapButton()
    if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = { hide = false, minimapPos = 225 } end
    
    local ldb = LibStub("LibDataBroker-1.1")
    local icon = LibStub("LibDBIcon-1.0")

    local MarketSyncLDB = ldb:NewDataObject("MarketSync", {
        type = "launcher",
        text = "MarketSync",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        OnClick = function(self, button)
            if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
                if not MarketSyncDB.NotificationMuteConfirmed then
                    StaticPopup_Show("MARKETSYNC_CONFIRM_SESSION_MUTE")
                elseif MarketSync.ToggleNotificationMute then
                    MarketSync.ToggleNotificationMute()
                end
                return
            elseif button == "RightButton" then
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                    -- Switch to Settings tab (Tab 7)
                    if MarketSync.SelectMainFrameTab then
                        MarketSync.SelectMainFrameTab(7)
                    elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[7] then
                        MarketSyncMainFrame.tabs[7]:Click()
                    end
                end
            elseif button == "MiddleButton" then
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                    -- Switch to Alerts tab (Tab 6)
                    if MarketSync.SelectMainFrameTab then
                        MarketSync.SelectMainFrameTab(6)
                    elseif MarketSyncMainFrame and MarketSyncMainFrame.tabs and MarketSyncMainFrame.tabs[6] then
                        MarketSyncMainFrame.tabs[6]:Click()
                    end
                end
            else
                if MarketSync_ToggleUI then
                    MarketSync_ToggleUI()
                end
            end
            -- Stop flashing on any click
            if MarketSync.StopMinimapFlash then
                MarketSync.StopMinimapFlash()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("MarketSync")
            tooltip:AddLine(" ")
            tooltip:AddLine("|cFF00FF00Left-Click|r to Open Window")
            tooltip:AddLine("|cFF00FF00Middle-Click|r for Notifications")
            tooltip:AddLine("|cFF00FF00Right-Click|r for Settings")
            tooltip:AddLine("|cFF00FF00Shift-Left-Click|r to toggle alerts for this session")
            if MarketSync.NotificationsMuted then
                tooltip:AddLine("|cffffaa00Alerts muted until logout|r")
            end
        end,
    })

    icon:Register("MarketSync", MarketSyncLDB, MarketSyncDB.MinimapIcon)
    
    -- Re-implement Flashing Overlay on the frame LibDBIcon created
    local btn = icon:GetMinimapButton("MarketSync")
    if btn then
        local flash = btn:CreateTexture(nil, "OVERLAY")
        flash:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        flash:SetBlendMode("ADD")
        flash:SetAllPoints()
        flash:Hide()
        btn.flash = flash

        local flashGroup = flash:CreateAnimationGroup()
        local alpha = flashGroup:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.5)
        alpha:SetOrder(1)
        local alpha2 = flashGroup:CreateAnimation("Alpha")
        alpha2:SetFromAlpha(1)
        alpha2:SetToAlpha(0)
        alpha2:SetDuration(0.5)
        alpha2:SetOrder(2)
        flashGroup:SetLooping("REPEAT")

        function MarketSync.StartMinimapFlash()
            if MarketSync.NotificationsMuted then return end
            if not flash:IsShown() then
                flash:Show()
                flashGroup:Play()
            end
        end

        function MarketSync.StopMinimapFlash()
            if flash:IsShown() then
                flashGroup:Stop()
                flash:Hide()
            end
        end
    end
end

-- ================================================================
-- INTERFACE OPTIONS PANEL
-- ================================================================

-- Main Panel
local panel = CreateFrame("Frame", "MarketSyncConfig", UIParent)
panel.name = "MarketSync"
category = (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutCategory(panel, panel.name)) or (InterfaceOptions_AddCategory and InterfaceOptions_AddCategory(panel))
if Settings then Settings.RegisterAddOnCategory(category) end
MarketSync.SettingsCategory = category
MarketSync.SettingsPanel = panel

local function PopulateAddonSettings(panel)
    if panel.initialized then return end
    panel.initialized = true

    -- Header Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cFFFFD100MarketSync Configuration|r")

    -- Top-right shortcut button to open the portable MainFrame
    local btnOpenMain = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnOpenMain:SetSize(165, 22)
    btnOpenMain:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -26, -12)
    btnOpenMain:SetText("Open MarketSync Window")
    btnOpenMain:SetScript("OnClick", function()
        if MarketSync_ToggleUI then MarketSync_ToggleUI() end
        if SettingsPanel and SettingsPanel.Hide then SettingsPanel:Hide() end
        if InterfaceOptionsFrame and InterfaceOptionsFrame.Hide then InterfaceOptionsFrame:Hide() end
    end)

    local subText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subText:SetText("Configure memory management, auction scanning, profession calculation, notifications, and peer sync.")

    -- ScrollFrame container
    local scroll = CreateFrame("ScrollFrame", "MarketSyncConfigScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(scroll) end
    if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local step = 32
        local maxScroll = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * step)))
        if self.SetVerticalScroll then self:SetVerticalScroll(newScroll) end
    end)

    local canvas = CreateFrame("Frame", "MarketSyncConfigCanvas", scroll)
    canvas:SetSize(570, 960)
    scroll:SetScrollChild(canvas)

    local function AttachTooltip(frame, text)
        if not text or text == "" then return end
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function CreateCard(w, h, anchor, yOff)
        local card = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
        card:SetSize(w, h)
        if anchor then
            card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff or -12)
        else
            card:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
        end
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        card:SetBackdropColor(0.065, 0.060, 0.055, 0.95)
        card:SetBackdropBorderColor(0.35, 0.30, 0.20, 0.85)

        local topHighlight = card:CreateTexture(nil, "BORDER")
        topHighlight:SetHeight(1)
        topHighlight:SetPoint("TOPLEFT", 1, -1)
        topHighlight:SetPoint("TOPRIGHT", -1, -1)
        topHighlight:SetColorTexture(0.55, 0.45, 0.25, 0.35)

        return card
    end

    local refreshControls = {}
    local function CreateOptCheckbox(parent, x, y, label, tooltip, key, defaultVal, onChange)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        cb.text:SetText(label)
        cb.text:SetFontObject("GameFontHighlightSmall")
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        AttachTooltip(cb, tooltip)

        cb:SetScript("OnClick", function(self)
            local val = self:GetChecked()
            if MarketSyncDB and key then
                MarketSyncDB[key] = val
            end
            if onChange then onChange(val) end
        end)

        local function Refresh()
            if MarketSyncDB and key then
                if defaultVal == false then
                    cb:SetChecked(MarketSyncDB[key] == true)
                else
                    cb:SetChecked(MarketSyncDB[key] ~= false)
                end
            end
        end
        table.insert(refreshControls, Refresh)
        cb:SetScript("OnShow", Refresh)

        return cb
    end

    -- ================================================================
    -- CARD 1: PERFORMANCE & MEMORY MANAGEMENT
    -- ================================================================
    local cardMemory = CreateCard(565, 175, nil, 0)

    local hMemory = cardMemory:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hMemory:SetPoint("TOPLEFT", 12, -10)
    hMemory:SetText("|cffffd700Performance & Memory Management|r")

    local sMemory = cardMemory:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sMemory:SetPoint("TOPLEFT", hMemory, "BOTTOMLEFT", 0, -3)
    sMemory:SetText("Configure RAM conservation, on-demand loading, and background caching rate.")

    local UpdateMemoryCardLayout
    local chkStartup

    local chkLowRam = CreateOptCheckbox(cardMemory, 12, -42, "Enable Low RAM Mode (Default: ON)",
        "Wipes search index caches and runs Lua garbage collection when browse windows are closed. Automatically loads caches on demand.",
        "LowRamMode", true, function(val)
            if not val and MarketSync.BuildSearchIndex then
                MarketSync.BuildSearchIndex()
            end
            if UpdateMemoryCardLayout then UpdateMemoryCardLayout() end
        end)

    chkStartup = CreateOptCheckbox(cardMemory, 12, -68, "Pre-Build Search Index on Startup",
        "Pre-indexes stored auction data shortly after login. When Low RAM mode is enabled, on-demand indexing is recommended instead.",
        "BuildCacheOnStartup", false, function(val)
            if val and MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end
        end)

    -- Cache Build Speed Slider
    local speedHeader = cardMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    speedHeader:SetPoint("TOPLEFT", 12, -96)
    speedHeader:SetText("|cffffd700Cache Build Speed:|r")

    local speedSlider = CreateFrame("Slider", "MarketSyncAddonSpeedSlider", cardMemory, "OptionsSliderTemplate")
    speedSlider:SetPoint("LEFT", speedHeader, "RIGHT", 14, 0)
    speedSlider:SetWidth(120)
    speedSlider:SetMinMaxValues(1, 4)
    speedSlider:SetValueStep(1)
    if speedSlider.SetObeyStepOnDrag then speedSlider:SetObeyStepOnDrag(true) end
    if speedSlider.Low then speedSlider.Low:SetText("1") end
    if speedSlider.High then speedSlider.High:SetText("4") end

    local speedNameText = cardMemory:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    speedNameText:SetPoint("LEFT", speedSlider, "RIGHT", 10, 0)

    local speedDescText = cardMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    speedDescText:SetPoint("TOPLEFT", speedHeader, "BOTTOMLEFT", 0, -8)
    speedDescText:SetWidth(540)
    speedDescText:SetJustifyH("LEFT")

    local function UpdateSpeedDisplay(val)
        local preset = MarketSync.CacheSpeedPresets and MarketSync.CacheSpeedPresets[val]
        if preset then
            speedNameText:SetText("|cffffcc00" .. preset.name .. "|r")
            speedDescText:SetText(preset.desc .. " |cff888888(Controls yield rate and item batch size)|r")
        end
        if speedSlider.Text then speedSlider.Text:SetText("") end
    end

    speedSlider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        if MarketSyncDB then MarketSyncDB.CacheSpeed = val end
        UpdateSpeedDisplay(val)
    end)
    local function RefreshSpeed()
        local val = (MarketSyncDB and MarketSyncDB.CacheSpeed) or 2
        speedSlider:SetValue(val)
        UpdateSpeedDisplay(val)
    end
    table.insert(refreshControls, RefreshSpeed)

    -- Live RAM Estimation
    local ramText = cardMemory:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ramText:SetPoint("TOPLEFT", speedDescText, "BOTTOMLEFT", 0, -8)
    ramText:SetWidth(400)
    ramText:SetJustifyH("LEFT")

    local btnRebuildCache = CreateFrame("Button", nil, cardMemory, "UIPanelButtonTemplate")
    btnRebuildCache:SetSize(130, 20)
    btnRebuildCache:SetPoint("TOPRIGHT", cardMemory, "TOPRIGHT", -12, -142)
    btnRebuildCache:SetText("Rebuild Cache")
    AttachTooltip(btnRebuildCache, "Manually rebuild personal, guild, and neutral browse index caches.")
    btnRebuildCache:SetScript("OnClick", function()
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        if MarketSync.BuildSearchIndex then
            MarketSync.BuildSearchIndex()
            print("|cFF00FF00[MarketSync]|r Triggered manual search cache rebuild.")
        end
    end)

    local function RefreshRAM()
        if MarketSync.GetEstimatedRAMUsage then
            local estMB, totalItems, pCount, gCount, nCount = MarketSync.GetEstimatedRAMUsage()
            ramText:SetText(string.format("|cff888888Index Footprint:|r |cffffffff~%.1f MB|r |cff888888(%d items: %d personal, %d guild, %d neutral)|r",
                estMB, totalItems, pCount, gCount, nCount))
        end
    end
    table.insert(refreshControls, RefreshRAM)

    UpdateMemoryCardLayout = function()
        local isLowRam = MarketSyncDB and (MarketSyncDB.LowRamMode ~= false)
        if isLowRam then
            if chkStartup then chkStartup:Hide() end
            speedHeader:ClearAllPoints()
            speedHeader:SetPoint("TOPLEFT", 12, -70)
            btnRebuildCache:ClearAllPoints()
            btnRebuildCache:SetPoint("TOPRIGHT", cardMemory, "TOPRIGHT", -12, -116)
            cardMemory:SetHeight(148)
        else
            if chkStartup then chkStartup:Show() end
            speedHeader:ClearAllPoints()
            speedHeader:SetPoint("TOPLEFT", 12, -96)
            btnRebuildCache:ClearAllPoints()
            btnRebuildCache:SetPoint("TOPRIGHT", cardMemory, "TOPRIGHT", -12, -142)
            cardMemory:SetHeight(175)
        end
    end
    table.insert(refreshControls, UpdateMemoryCardLayout)

    -- ================================================================
    -- CARD 2: PROFESSIONS & CRAFTING (Out of Beta!)
    -- ================================================================
    local cardProf = CreateCard(565, 70, cardMemory, -10)

    local hProf = cardProf:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hProf:SetPoint("TOPLEFT", 12, -10)
    hProf:SetText("|cffffd700Professions & Crafting|r")

    local sProf = cardProf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sProf:SetPoint("TOPLEFT", hProf, "BOTTOMLEFT", 0, -3)
    sProf:SetText("Direct in-game trade skill margin calculations, vendor pricing, and materials tree.")

    CreateOptCheckbox(cardProf, 12, -38, "TradeSkill Costs & Profitability (Production)",
        "Show crafting costs, net profit margins (with 5% AH cut), vendor materials, and recursive component trees directly in the Blizzard TradeSkill window.",
        "EnableProfessionCraftInfo", true, function(val)
            if MarketSync.RefreshCraftingInfoUI then MarketSync.RefreshCraftingInfoUI() end
        end)

    -- ================================================================
    -- CARD 3: AUCTION HOUSE & SCANNING
    -- ================================================================
    local cardAH = CreateCard(565, 175, cardProf, -10)

    local hAH = cardAH:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hAH:SetPoint("TOPLEFT", 12, -10)
    hAH:SetText("|cffffd700Auction House & Scanning|r")

    local sAH = cardAH:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sAH:SetPoint("TOPLEFT", hAH, "BOTTOMLEFT", 0, -3)
    sAH:SetText("Auction House integration, tooltip prices, yields, and chat price answering.")

    CreateOptCheckbox(cardAH, 12, -40, "Enable Analytics Tab",
        "Show price history charts, volume trends, and item stats in both main window and Auction House.",
        "EnableAnalyticsTab", true, function(val)
            if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
            if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        end)

    CreateOptCheckbox(cardAH, 12, -66, "Use Auctionator Scanning (if present)",
        "Let Auctionator perform full AH scans and import its price database. If disabled or Auctionator is absent, MarketSync uses its native high-speed scanner.",
        "UseAuctionatorScanner", Auctionator ~= nil and Auctionator.Database ~= nil, function(val)
            if MarketSyncDB then MarketSyncDB.AuctionatorScannerUserChoice = true end
            if MarketSync.Provider then MarketSync.Provider.Select() end
            if val and MarketSync.RegisterAuctionatorHooks then MarketSync.RegisterAuctionatorHooks() end
        end)

    CreateOptCheckbox(cardAH, 12, -92, "Show Auction Prices on Tooltips",
        "Display buyout prices, stack totals, and scan freshness directly on item tooltips.",
        "EnableTooltipAuctionPrice", true, nil)

    CreateOptCheckbox(cardAH, 12, -118, "Show Expected Values (EV) on Tooltips",
        "Show expected yields and EV values for Prospecting, Milling, and Disenchanting.",
        "EnableTooltipProb", true, nil)

    CreateOptCheckbox(cardAH, 12, -144, "Enable Chat Price Check ('? [item]')",
        "Automatically answer queries from other players using '? [Item Link]'.",
        "EnableChatPriceCheck", true, nil)

    -- ================================================================
    -- CARD 4: AUDIO & NOTIFICATIONS
    -- ================================================================
    local cardAudio = CreateCard(565, 140, cardAH, -10)

    local hAudio = cardAudio:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hAudio:SetPoint("TOPLEFT", 12, -10)
    hAudio:SetText("|cffffd700Audio & Notifications|r")

    local sAudio = cardAudio:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sAudio:SetPoint("TOPLEFT", hAudio, "BOTTOMLEFT", 0, -3)
    sAudio:SetText("Audible alert triggers and visual deal notifications.")

    local UpdateAudioAndAlertsCard
    local chkBetaAlerts, undercutSlider

    local lockedAudioNotice = cardAudio:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    lockedAudioNotice:SetPoint("TOPLEFT", 14, -38)
    lockedAudioNotice:SetPoint("RIGHT", cardAudio, "RIGHT", -14, 0)
    lockedAudioNotice:SetJustifyH("LEFT")
    lockedAudioNotice:SetText("|cffffaa00[BETA LOCKED]|r Audio and visual notifications require the |cffffd700Price Alerts|r module.\nTurn on |cffffd700[BETA] Enable Price Alerts Tab|r under Beta Features below to unlock audio and alert settings.")

    local btnUnlockAudio = CreateFrame("Button", nil, cardAudio, "UIPanelButtonTemplate")
    btnUnlockAudio:SetSize(165, 20)
    btnUnlockAudio:SetPoint("TOPLEFT", lockedAudioNotice, "BOTTOMLEFT", 0, -8)
    btnUnlockAudio:SetText("Enable Price Alerts (Beta)")
    btnUnlockAudio:SetScript("OnClick", function()
        if MarketSyncDB then MarketSyncDB.EnableAlertsTab = true end
        if chkBetaAlerts then chkBetaAlerts:SetChecked(true) end
        if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
        if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        if UpdateAudioAndAlertsCard then UpdateAudioAndAlertsCard() end
    end)

    local chkNotifSound = CreateOptCheckbox(cardAudio, 12, -38, "Enable Notification Sounds",
        "Play a sound when a tracked notification request triggers.",
        "EnableNotificationSounds", true, function(val)
            if UpdateAudioAndAlertsCard then UpdateAudioAndAlertsCard() end
        end)

    -- Sound Dropdown
    local soundDropdown = CreateFrame("Frame", "MarketSyncAddonSoundDropdown", cardAudio, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", 10, -64)
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(soundDropdown, 120) end

    local function PlaySelectedSound()
        local soundID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        if MarketSync.PlayNotificationSound then MarketSync.PlayNotificationSound(soundID, true) end
    end

    local function OnSoundSelect(self)
        if MarketSyncDB then MarketSyncDB.NotificationSoundID = self.arg1 end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(soundDropdown, self.value) end
        if CloseDropDownMenus then CloseDropDownMenus() end
    end

    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(soundDropdown, function()
            local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo()
            if info then
                for _, s in ipairs(MarketSync.StandardSounds or {}) do
                    info.text = s.name
                    info.value = s.name
                    info.arg1 = s.id
                    info.func = OnSoundSelect
                    info.checked = (MarketSyncDB and MarketSyncDB.NotificationSoundID == s.id)
                    if UIDropDownMenu_AddButton then UIDropDownMenu_AddButton(info) end
                end
            end
        end)
    end

    local btnPlaySound = CreateFrame("Button", nil, cardAudio, "UIPanelButtonTemplate")
    btnPlaySound:SetSize(22, 22)
    btnPlaySound:SetPoint("LEFT", soundDropdown, "RIGHT", -10, 2)
    btnPlaySound:SetText(">")
    btnPlaySound:SetScript("OnClick", PlaySelectedSound)
    AttachTooltip(btnPlaySound, "Preview selected alert sound.")

    -- Volume Slider
    local volSlider = CreateFrame("Slider", "MarketSyncAddonVolSlider", cardAudio, "OptionsSliderTemplate")
    volSlider:SetPoint("TOPLEFT", 18, -108)
    volSlider:SetWidth(125)
    volSlider:SetMinMaxValues(0, 100)
    volSlider:SetValueStep(5)
    if volSlider.SetObeyStepOnDrag then volSlider:SetObeyStepOnDrag(true) end
    if volSlider.Low then volSlider.Low:SetText("0%") end
    if volSlider.High then volSlider.High:SetText("100%") end
    if volSlider.Text then volSlider.Text:SetText("Alert Volume") end

    volSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        if MarketSyncDB then MarketSyncDB.NotificationVolume = val / 100 end
    end)
    local function RefreshVolume()
        local vol = (MarketSyncDB and MarketSyncDB.NotificationVolume or 1) * 100
        volSlider:SetValue(vol)
        local currentID = MarketSyncDB and MarketSyncDB.NotificationSoundID or 8959
        for _, s in ipairs(MarketSync.StandardSounds or {}) do
            if s.id == currentID then
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(soundDropdown, s.name) end
                break
            end
        end
    end
    table.insert(refreshControls, RefreshVolume)

    -- Visual Alerts on right side of Card 4
    local chkMinimapAlerts = CreateOptCheckbox(cardAudio, 360, -38, "Flash Minimap for Alerts",
        "Flash the MarketSync minimap button until notifications are acknowledged.",
        "EnableMinimapAlerts", true, function(val)
            if not val and MarketSync.StopMinimapFlash then MarketSync.StopMinimapFlash() end
        end)

    local chkRaidAlerts = CreateOptCheckbox(cardAudio, 360, -64, "Show On-Screen Alert Banner",
        "Display triggered notifications in the on-screen raid-warning banner.",
        "EnableRaidWarningAlerts", true, nil)

    UpdateAudioAndAlertsCard = function()
        local alertsEnabled = MarketSyncDB and (MarketSyncDB.EnableAlertsTab == true)
        if undercutSlider then
            if alertsEnabled then
                undercutSlider:Show()
            else
                undercutSlider:Hide()
            end
        end

        if not alertsEnabled then
            if lockedAudioNotice then lockedAudioNotice:Show() end
            if btnUnlockAudio then btnUnlockAudio:Show() end
            if chkNotifSound then chkNotifSound:Hide() end
            if soundDropdown then soundDropdown:Hide() end
            if btnPlaySound then btnPlaySound:Hide() end
            if volSlider then volSlider:Hide() end
            if chkMinimapAlerts then chkMinimapAlerts:Hide() end
            if chkRaidAlerts then chkRaidAlerts:Hide() end
            cardAudio:SetHeight(95)
        else
            if lockedAudioNotice then lockedAudioNotice:Hide() end
            if btnUnlockAudio then btnUnlockAudio:Hide() end
            if chkNotifSound then chkNotifSound:Show() end
            if chkMinimapAlerts then chkMinimapAlerts:Show() end
            if chkRaidAlerts then chkRaidAlerts:Show() end

            local soundEnabled = MarketSyncDB and (MarketSyncDB.EnableNotificationSounds ~= false)
            if soundEnabled then
                if soundDropdown then soundDropdown:Show() end
                if btnPlaySound then btnPlaySound:Show() end
                if volSlider then volSlider:Show() end
                cardAudio:SetHeight(140)
            else
                if soundDropdown then soundDropdown:Hide() end
                if btnPlaySound then btnPlaySound:Hide() end
                if volSlider then volSlider:Hide() end
                cardAudio:SetHeight(90)
            end
        end
    end
    table.insert(refreshControls, UpdateAudioAndAlertsCard)

    -- ================================================================
    -- CARD 5: DATA SYNC & SWARM
    -- ================================================================
    local cardSwarm = CreateCard(565, 140, cardAudio, -10)

    local hSwarm = cardSwarm:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hSwarm:SetPoint("TOPLEFT", 12, -10)
    hSwarm:SetText("|cffffd700Data Sync & Swarm|r")

    local sSwarm = cardSwarm:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sSwarm:SetPoint("TOPLEFT", hSwarm, "BOTTOMLEFT", 0, -3)
    sSwarm:SetText("Peer-to-peer guild network synchronization, privacy, and latency management.")

    CreateOptCheckbox(cardSwarm, 12, -38, "Enable Guild Sync",
        "Enable or disable guild data syncing. When disabled, the Guild Sync tab is hidden and swarm status shows as 'Disabled'.",
        "PassiveSync", true, function(val)
            if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), val and nil or "Disabled") end
            if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        end)

    CreateOptCheckbox(cardSwarm, 12, -64, "Enable Neutral AH Sync",
        "Enable or disable Neutral AH data syncing.",
        "EnableNeutralSync", true, function(val)
            if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), val and nil or "Disabled") end
            if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        end)

    local chkLockMinimap = CreateOptCheckbox(cardSwarm, 12, -90, "Lock Minimap Button",
        "Prevent the minimap button from being dragged.",
        nil, false, function(val)
            if MarketSyncDB then
                if not MarketSyncDB.MinimapIcon then MarketSyncDB.MinimapIcon = {} end
                MarketSyncDB.MinimapIcon.locked = val
            end
        end)
    table.insert(refreshControls, function()
        if MarketSyncDB and MarketSyncDB.MinimapIcon and chkLockMinimap then
            chkLockMinimap:SetChecked(MarketSyncDB.MinimapIcon.locked == true)
        end
    end)

    -- Swarm Action Buttons
    local btnManageUsers = CreateFrame("Button", nil, cardSwarm, "UIPanelButtonTemplate")
    btnManageUsers:SetSize(130, 22)
    btnManageUsers:SetPoint("TOPLEFT", 280, -38)
    btnManageUsers:SetText("Manage Users")
    AttachTooltip(btnManageUsers, "Block or unblock sync partners.")
    btnManageUsers:SetScript("OnClick", function()
        if MarketSync.ShowUserManagementDialog then MarketSync.ShowUserManagementDialog() end
    end)

    local btnSmartBandwidth = CreateFrame("Button", nil, cardSwarm, "UIPanelButtonTemplate")
    btnSmartBandwidth:SetSize(130, 22)
    btnSmartBandwidth:SetPoint("LEFT", btnManageUsers, "RIGHT", 10, 0)
    btnSmartBandwidth:SetText("Smart Rules")
    AttachTooltip(btnSmartBandwidth, "Configure where background sync and cache indexing are allowed.")
    btnSmartBandwidth:SetScript("OnClick", function()
        if MarketSync.ShowSmartRulesDialog then MarketSync.ShowSmartRulesDialog() end
    end)

    local btnConsole = CreateFrame("Button", nil, cardSwarm, "UIPanelButtonTemplate")
    btnConsole:SetSize(130, 22)
    btnConsole:SetPoint("TOPLEFT", 280, -68)
    btnConsole:SetText("Sync Console")
    AttachTooltip(btnConsole, "View network stream and cache logs.")
    btnConsole:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then MarketSync.ToggleNetworkMonitor() end
    end)

    local btnResetData = CreateFrame("Button", nil, cardSwarm, "UIPanelButtonTemplate")
    btnResetData:SetSize(130, 22)
    btnResetData:SetPoint("LEFT", btnConsole, "RIGHT", 10, 0)
    btnResetData:SetText("Reset Sync Data")
    AttachTooltip(btnResetData, "|cffff4444Wipe sync data and create a new personal snapshot.|r")
    btnResetData:SetScript("OnClick", function()
        if StaticPopup_Show then
            StaticPopup_Show("MarketSync_CONFIRM_RESET")
        end
    end)

    -- ================================================================
    -- CARD 6: BETA & EXPERIMENTAL FEATURES
    -- ================================================================
    local cardBeta = CreateCard(565, 116, cardSwarm, -10)

    local hBeta = cardBeta:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hBeta:SetPoint("TOPLEFT", 12, -10)
    hBeta:SetText("|cffffaa00Beta & Experimental Features|r")

    local sBeta = cardBeta:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sBeta:SetPoint("TOPLEFT", hBeta, "BOTTOMLEFT", 0, -3)
    sBeta:SetText("Modules currently under active development.")

    CreateOptCheckbox(cardBeta, 12, -38, "|cffff6600[BETA]|r Enable Processing Tab",
        "Show the Processing tab (recursive solver, vendor arbitrage, and batch shopping list) on MainFrame and Auction House.",
        "EnableProcessingTab", false, function(val)
            if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
            if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
        end)

    chkBetaAlerts = CreateOptCheckbox(cardBeta, 12, -64, "|cffff6600[BETA]|r Enable Price Alerts Tab",
        "Show the Alerts tab (price alerts, watchlist, and deal triggers) on both portable window and Auction House.",
        "EnableAlertsTab", false, function(val)
            if MainFrame and MainFrame.RefreshTabVisibility then MainFrame.RefreshTabVisibility() end
            if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then MarketSync.AuctionHouse.RefreshTabVisibility() end
            if UpdateAudioAndAlertsCard then UpdateAudioAndAlertsCard() end
        end)

    -- Default Undercut Slider (for Price Alerts)
    undercutSlider = CreateFrame("Slider", "MarketSyncAddonUndercutSlider", cardBeta, "OptionsSliderTemplate")
    undercutSlider:SetPoint("TOPLEFT", 320, -64)
    undercutSlider:SetWidth(130)
    undercutSlider:SetMinMaxValues(1, 50)
    undercutSlider:SetValueStep(1)
    if undercutSlider.SetObeyStepOnDrag then undercutSlider:SetObeyStepOnDrag(true) end
    if undercutSlider.Low then undercutSlider.Low:SetText("1%") end
    if undercutSlider.High then undercutSlider.High:SetText("50%") end
    if undercutSlider.Text then undercutSlider.Text:SetText("Default Undercut %") end

    undercutSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        if MarketSyncDB then MarketSyncDB.AlertUndercutPct = val end
        if self.Text then self.Text:SetText(string.format("Default Undercut: %d%%", val)) end
        if MarketSync.RefreshNotificationUndercutButtons then MarketSync.RefreshNotificationUndercutButtons() end
    end)
    local function RefreshUndercut()
        local val = (MarketSyncDB and MarketSyncDB.AlertUndercutPct) or 10
        undercutSlider:SetValue(val)
        if undercutSlider.Text then undercutSlider.Text:SetText(string.format("Default Undercut: %d%%", val)) end
        if UpdateAudioAndAlertsCard then UpdateAudioAndAlertsCard() end
    end
    table.insert(refreshControls, RefreshUndercut)

    CreateOptCheckbox(cardBeta, 12, -90, "Enable Debug Diagnostics",
        "Print verbose synchronization, retention, and scanning diagnostics in chat.",
        "DebugMode", false, nil)

    function panel.RefreshSettingsValues()
        for _, refresh in ipairs(refreshControls) do
            refresh()
        end
    end
end

panel:SetScript("OnShow", function(self)
    PopulateAddonSettings(self)
    if self.RefreshSettingsValues then
        self.RefreshSettingsValues()
    end
end)

-- ================================================================
-- STAGED INITIALIZATION
-- ================================================================
-- Stage 1 (immediate):  DB defaults + minimap â€” zero DB iteration
-- Stage 2 (45s):        Passive sync â€” lightweight guild advertisements
-- Stage 3 (90s):        Search index cache â€” heavy coroutine, only if enabled
-- On-Demand:            Opening the Browse UI always triggers cache build
-- ================================================================
local auctionatorDBUpdateRegistered = false
local auctionatorFullScanRegistered = false
local auctionatorSetPriceHookInstalled = false
local auctionatorFullScanListener = {}
local auctionatorDBSnapshotPending = false
local suppressNextScheduledDBSnapshot = false
local pendingAuctionatorKeys = {}
local fullScanState = { active = false, scope = nil, keys = nil }
local function RegisterAuctionatorHooks()
    if not (Auctionator and Auctionator.Database) then return end

    local function IsNeutralCaptureActive()
        return MarketSync.IsNeutralAHOpen == true
            or (MarketSync.IsNeutralAHSession and MarketSync.IsNeutralAHSession())
    end

    local function WarnGroupedSuffixKeys(keys)
        if not MarketSyncDB or MarketSyncDB.AuctionatorGroupedSuffixWarningShown then return end
        for key in pairs(keys or {}) do
            if type(key) == "string" and key:match("^gr:%d+:") then
                MarketSyncDB.AuctionatorGroupedSuffixWarningShown = true
                print("|cFFFF8800[MarketSync]|r Auctionator's targeted or neutral scan supplied grouped suffix prices only. Exact numeric suffix pricing is captured from main AH full scans when raw links are available.")
                return
            end
        end
    end

    local function SnapshotAuctionatorChanges(authoritative, exactKeys, observationScanID, scanTime)
        if IsNeutralCaptureActive() or not MarketSync.SnapshotPersonalScan then return false end
        local ok, count, todayCount, changedCount = pcall(MarketSync.SnapshotPersonalScan, {
            evaluateNotifications = true,
            authoritative = authoritative == true,
            keys = exactKeys,
            exactKeys = exactKeys ~= nil,
            observationScanID = observationScanID,
            scanTime = scanTime,
        })
        if not ok then
            MarketSync.Debug("Auctionator database snapshot failed: " .. tostring(count))
            return false
        end
        if exactKeys and MarketSync.RefreshPersonalBrowseIndexKeys then
            MarketSync.RefreshPersonalBrowseIndexKeys(exactKeys)
        elseif (tonumber(changedCount) or 0) > 0 and MarketSync.InvalidateIndexCache then
            MarketSync.InvalidateIndexCache()
        end
        return true, count, todayCount, changedCount
    end

    local function ResetFullScanState()
        fullScanState.active, fullScanState.scope, fullScanState.keys = false, nil, nil
        fullScanState.observationScanID = nil
        fullScanState.scanTime = nil
        MarketSync._auctionatorScanActive = false
    end

    local function HandleFullScanStart()
        local now = MarketSync.GetServerTime and MarketSync.GetServerTime() or time()
        if fullScanState.observationScanID and MarketSync.ObservationAPI then
            MarketSync.ObservationAPI.v1.Emit({ event = "cancel",
                scanId = fullScanState.observationScanID, source = "local",
                scope = fullScanState.scope == "N" and "neutral" or "main",
                scanTime = fullScanState.scanTime or now,
                reason = "replaced by new scan" })
        end
        pendingAuctionatorKeys = {}
        fullScanState.active = true
        fullScanState.scope = IsNeutralCaptureActive() and "N" or "M"
        fullScanState.keys = auctionatorSetPriceHookInstalled and {} or nil
        fullScanState.scanTime = now
        if MarketSync.ObservationAPI and MarketSync.ObservationAPI.v1.HasListeners() then
            fullScanState.observationScanID = MarketSync.ObservationAPI.v1.NewScanID("local")
            MarketSync.ObservationAPI.v1.Emit({ event = "start",
                scanId = fullScanState.observationScanID, source = "local",
                scope = fullScanState.scope == "N" and "neutral" or "main",
                scanTime = now })
        end
        MarketSync._auctionatorScanActive = true
        if fullScanState.scope == "N" and MarketSync.BeginNeutralFullScan then
            MarketSync.BeginNeutralFullScan()
        end
    end

    local function HandleFullScanFailed()
        local failedScope = fullScanState.scope
        local failedScanTime = fullScanState.scanTime or (MarketSync.GetServerTime and MarketSync.GetServerTime() or time())
        if fullScanState.observationScanID and MarketSync.ObservationAPI then
            MarketSync.ObservationAPI.v1.Emit({ event = "cancel",
                scanId = fullScanState.observationScanID, source = "local",
                scope = failedScope == "N" and "neutral" or "main",
                scanTime = failedScanTime, reason = "scan failed" })
        end
        ResetFullScanState()
        pendingAuctionatorKeys = {}
        if failedScope == "N" and MarketSync.FailNeutralFullScan then
            MarketSync.FailNeutralFullScan()
        end
    end

    local function HandleFullScanComplete(rawScan, isAuctionatorFullScan)
        local completedScope = fullScanState.scope or (IsNeutralCaptureActive() and "N" or "M")
        local completedKeys = fullScanState.keys
        local observationScanID = fullScanState.observationScanID
        local scanTime = fullScanState.scanTime or (MarketSync.GetServerTime and MarketSync.GetServerTime() or time())
        ResetFullScanState()
        pendingAuctionatorKeys = {}

        if completedScope == "N" then
            suppressNextScheduledDBSnapshot = auctionatorDBUpdateRegistered
            WarnGroupedSuffixKeys(completedKeys)
            if MarketSync.CompleteNeutralFullScan then
                MarketSync.CompleteNeutralFullScan(completedKeys)
            end
            if observationScanID and MarketSync.ObservationAPI then
                local neutralData = MarketSync.GetRealmDB().NeutralData or {}
                for dbKey in pairs(completedKeys or {}) do
                    local entry = neutralData[dbKey]
                    local price = entry and tonumber(entry.vm)
                    if price and price > 0 then
                        local itemID, itemSuffix = MarketSync.ParseItemIDFromDBKey(tostring(dbKey))
                        local quantity = tonumber(entry.vq)
                        local dayNum = tonumber(entry.vd)
                        local observedTime = dayNum and MarketSync.ScanDayToTimestamp and MarketSync.ScanDayToTimestamp(dayNum) or nil
                        MarketSync.ObservationAPI.v1.Emit({ event = "observation",
                            scanId = observationScanID, source = "local", scope = "neutral",
                            scanTime = scanTime,
                            key = tostring(dbKey), itemID = itemID, itemSuffix = itemSuffix,
                            unitPrice = price, quantity = quantity and quantity > 0 and quantity or nil,
                            observedAt = nil, observedTime = observedTime, observedDay = dayNum, timePrecision = "day" })
                    end
                end
            end
            if observationScanID and MarketSync.ObservationAPI then
                MarketSync.ObservationAPI.v1.Emit({ event = "finish", scanId = observationScanID,
                    source = "local", scope = "neutral", scanTime = scanTime })
            end
            return
        end
        suppressNextScheduledDBSnapshot = auctionatorDBUpdateRegistered
        local function FinishSnapshot()
            MarketSync._ahFullScanCompleted = true
            -- Without a SetPrice key hook, fail closed. Sweeping Auctionator's whole
            -- DB can certify prices imported from guild sync or partial searches.
            if completedKeys == nil then
                MarketSync.Debug("Auctionator full scan completed without exact keys; freshness was not advanced")
                if observationScanID and MarketSync.ObservationAPI then
                    MarketSync.ObservationAPI.v1.Emit({ event = "cancel", scanId = observationScanID,
                        source = "local", scope = "main", scanTime = scanTime, reason = "exact keys unavailable" })
                end
                return
            end

            local ok, _, todayCount = SnapshotAuctionatorChanges(true, completedKeys, observationScanID, scanTime)
            if not ok then
                if observationScanID and MarketSync.ObservationAPI then
                    MarketSync.ObservationAPI.v1.Emit({ event = "cancel", scanId = observationScanID,
                        source = "local", scope = "main", scanTime = scanTime, reason = "snapshot failed" })
                end
                return
            end
            if observationScanID and MarketSync.ObservationAPI then
                MarketSync.ObservationAPI.v1.Emit({ event = "finish", scanId = observationScanID,
                    source = "local", scope = "main", scanTime = scanTime })
            end
            local realmDB = MarketSync.GetRealmDB()
            local now, today = scanTime, MarketSync.GetCurrentScanDay()
            realmDB.PersonalScanTime, realmDB.SwarmTSF = now, now
            realmDB.CachedScanStats = nil
            if MarketSync.GetMyLatestScanDay and MarketSync.GetMyLatestScanDay() == today then
                realmDB.LastCountDay = today
                realmDB.LastTodayCount = tonumber(todayCount) or 0
            end
            if C_Timer and C_Timer.After then
                if MarketSync.BuildSearchIndex then
                    C_Timer.After(1, function()
                        if MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end
                    end)
                end
                if MarketSyncDB and MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                    C_Timer.After(2, function()
                        if MarketSync.SendAdvertisement then MarketSync.SendAdvertisement() end
                    end)
                end
            end
        end

        if isAuctionatorFullScan and completedKeys then
            local capture = MarketSync.CaptureAuctionatorRawSuffixScan
            local started = type(capture) == "function" and capture(rawScan, FinishSnapshot, completedKeys)
            if started then return end
            if MarketSyncDB and not MarketSyncDB.AuctionatorSuffixFidelityWarningShown then
                MarketSyncDB.AuctionatorSuffixFidelityWarningShown = true
                print("|cFFFF8800[MarketSync]|r Auctionator did not provide raw scan links. Exact numeric suffix prices cannot be captured from this scan; grouped prices are still available.")
            end
        end
        FinishSnapshot()
    end

    local function ScheduleDBSnapshot()
        if auctionatorDBSnapshotPending or not (C_Timer and C_Timer.After) then return end
        auctionatorDBSnapshotPending = true
        C_Timer.After(0, function()
            auctionatorDBSnapshotPending = false
            if suppressNextScheduledDBSnapshot then
                suppressNextScheduledDBSnapshot = false
                return
            end
            if fullScanState.active or IsNeutralCaptureActive() then return end
            local keys = pendingAuctionatorKeys
            pendingAuctionatorKeys = {}
            if auctionatorSetPriceHookInstalled and next(keys) then
                WarnGroupedSuffixKeys(keys)
                SnapshotAuctionatorChanges(false, keys)
            end
        end)
    end

    local scanEventSets = {}
    local fullScanEvents = Auctionator.FullScan and Auctionator.FullScan.Events
    local incrementalScanEvents = Auctionator.IncrementalScan and Auctionator.IncrementalScan.Events
    if fullScanEvents then table.insert(scanEventSets, fullScanEvents) end
    if incrementalScanEvents then table.insert(scanEventSets, incrementalScanEvents) end
    function auctionatorFullScanListener:ReceiveEvent(eventName, scanData)
        if not (MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true) then return end
        if #scanEventSets == 0 then return end
        local ok, err = pcall(function()
            for _, events in ipairs(scanEventSets) do
                if events then
                    if events.ScanStart and eventName == events.ScanStart then
                        HandleFullScanStart()
                        break
                    elseif events.ScanComplete and eventName == events.ScanComplete then
                        HandleFullScanComplete(scanData, events == fullScanEvents)
                        break
                    elseif events.ScanFailed and eventName == events.ScanFailed then
                        HandleFullScanFailed()
                        break
                    end
                end
            end
        end)
        if not ok then
            ResetFullScanState()
            if MarketSync.FailNeutralFullScan then pcall(MarketSync.FailNeutralFullScan) end
            MarketSync.Debug("Auctionator scan integration failed: " .. tostring(err))
        end
    end

    if not auctionatorSetPriceHookInstalled and type(Auctionator.Database.SetPrice) == "function"
        and type(hooksecurefunc) == "function" then
        local ok, err = pcall(hooksecurefunc, Auctionator.Database, "SetPrice", function(_, dbKey)
            if not (MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true) then return end
            if dbKey == nil then return end
            MarketSync._ahScanActivity = (MarketSync._ahScanActivity or 0) + 1
            if fullScanState.active then
                if fullScanState.keys then fullScanState.keys[dbKey] = true end
            elseif not IsNeutralCaptureActive() then
                pendingAuctionatorKeys[dbKey] = true
                ScheduleDBSnapshot()
            end
        end)
        auctionatorSetPriceHookInstalled = ok == true
        if not ok then MarketSync.Debug("Auctionator SetPrice hook unavailable: " .. tostring(err)) end
    end

    local api = Auctionator.API and Auctionator.API.v1
    if not auctionatorDBUpdateRegistered and api and type(api.RegisterForDBUpdate) == "function" then
        local ok = pcall(api.RegisterForDBUpdate, ADDON_NAME, ScheduleDBSnapshot)
        auctionatorDBUpdateRegistered = ok == true
    end

    if not auctionatorFullScanRegistered and Auctionator.EventBus
        and type(Auctionator.EventBus.Register) == "function" then
        local scanEvents = {}
        for _, events in ipairs(scanEventSets) do
            if events then
                if events.ScanStart then table.insert(scanEvents, events.ScanStart) end
                if events.ScanComplete then table.insert(scanEvents, events.ScanComplete) end
                if events.ScanFailed then table.insert(scanEvents, events.ScanFailed) end
            end
        end
        if #scanEvents == 0 then return end
        local ok, err = pcall(Auctionator.EventBus.Register, Auctionator.EventBus, auctionatorFullScanListener, scanEvents)
        auctionatorFullScanRegistered = ok == true
        if not ok then MarketSync.Debug("Auctionator scan event listener unavailable: " .. tostring(err)) end
    end
end
MarketSync.RegisterAuctionatorHooks = RegisterAuctionatorHooks

local function SafeRegisterEvent(frame, eventName)
    if frame and eventName then
        pcall(frame.RegisterEvent, frame, eventName)
    end
end
-- ================================================================
-- TIERED RETENTION DOWNSAMPLER
-- Hot (0-7d):    full 30-min resolution (synced via guild swarm)
-- Warm (8-30d):  daily compact summaries (D:min:max:avg:vol, local)
-- Cold (31-180d): weekly compact summaries (W:min:max:avg:vol, local)
-- Purge (>180d): hard deleted
-- Fixes memory leak: strips data.vh older than Hot cutoff (7d)
-- ================================================================
function MarketSync.DownsampleRetention(onComplete)
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if not realmDB or not realmDB.PersonalData then
        if onComplete then onComplete(0, 0, 0, 0) end
        return
    end

    local currentDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or math.floor(time() / 86400)
    local hotDays = MarketSync.RETENTION_HOT_DAYS or 7
    local warmDays = MarketSync.RETENTION_WARM_DAYS or 30
    local coldDays = MarketSync.RETENTION_COLD_DAYS or 180

    local hotCutoff  = currentDay - hotDays
    local warmCutoff = currentDay - warmDays
    local coldCutoff = currentDay - coldDays

    local compactedDailyCount = 0
    local compactedWeeklyCount = 0
    local purgedCount = 0
    local vhPrunedCount = 0
    local purgedVariantCount = 0

    if MarketSyncDB and MarketSyncDB.DebugMode then
        print(string.format("|cFF00FF00[MarketSync]|r Downsampling retention (Hot: %dd, Warm: %dd, Cold: %dd)",
            hotDays, warmDays, coldDays))
    end

    local co = coroutine.create(function()
        local i = 0
        for dbKey, data in pairs(realmDB.PersonalData) do
            if type(data) == "table" and data.h then
                local weeklyBuckets = {}

                for dayKey, histStr in pairs(data.h) do
                    if type(dayKey) == "string" and dayKey:sub(1, 2) == "W_" then
                        -- Cold weekly record
                        local weekNum = tonumber(dayKey:sub(3))
                        if weekNum then
                            local weekAnchorDay = weekNum * 7
                            if weekAnchorDay < coldCutoff then
                                data.h[dayKey] = nil
                                purgedCount = purgedCount + 1
                            end
                        end
                    else
                        local dayNum = tonumber(dayKey)
                        if dayNum then
                            if dayNum < coldCutoff then
                                -- Beyond cold tier: hard purge
                                data.h[dayKey] = nil
                                purgedCount = purgedCount + 1
                            elseif dayNum < warmCutoff then
                                -- Warm -> Cold: accumulate into weekly summary
                                local weekNum = math.floor(dayNum / 7)
                                local weekKey = "W_" .. tostring(weekNum)
                                local rec = MarketSync.ParseCompactRecord(histStr)
                                if not rec and not MarketSync.IsCompactRecord(histStr) then
                                    local compacted = MarketSync.CompactDayString(histStr)
                                    if compacted then
                                        rec = MarketSync.ParseCompactRecord(compacted)
                                    end
                                end
                                if rec then
                                    weeklyBuckets[weekKey] = MarketSync.MergeCompactRecords(
                                        weeklyBuckets[weekKey], rec)
                                end
                                data.h[dayKey] = nil
                                compactedWeeklyCount = compactedWeeklyCount + 1
                            elseif dayNum < hotCutoff then
                                -- Hot -> Warm: convert raw buckets to daily summary
                                if not MarketSync.IsCompactRecord(histStr) then
                                    local compacted = MarketSync.CompactDayString(histStr)
                                    if compacted then
                                        data.h[dayKey] = compacted
                                        compactedDailyCount = compactedDailyCount + 1
                                    end
                                end
                            elseif MarketSync.DeduplicateScanBuckets then
                                data.h[dayKey] = MarketSync.DeduplicateScanBuckets(histStr)
                            end
                        end
                    end
                end

                -- Flush accumulated weekly records
                for weekKey, wRec in pairs(weeklyBuckets) do
                    local existingStr = data.h[weekKey]
                    if existingStr then
                        local existingRec = MarketSync.ParseCompactRecord(existingStr)
                        if existingRec then
                            wRec = MarketSync.MergeCompactRecords(existingRec, wRec)
                        end
                    end
                    data.h[weekKey] = string.format("W:%s:%s:%s:%s",
                        MarketSync.ToBase36(wRec.min),
                        MarketSync.ToBase36(wRec.max),
                        MarketSync.ToBase36(wRec.avg),
                        MarketSync.ToBase36(wRec.volume))
                end

                -- Prune vh (verified history) leak: only keep hot tier for outbound sync
                if type(data.vh) == "table" then
                    for vhDayKey, vhHistory in pairs(data.vh) do
                        local vhDayNum = tonumber(vhDayKey)
                        if not vhDayNum or vhDayNum < hotCutoff or (type(vhDayKey) == "string" and vhDayKey:sub(1, 2) == "W_") then
                            data.vh[vhDayKey] = nil
                            vhPrunedCount = vhPrunedCount + 1
                        elseif MarketSync.DeduplicateScanBuckets then
                            data.vh[vhDayKey] = MarketSync.DeduplicateScanBuckets(vhHistory)
                        end
                    end
                    if not next(data.vh) then
                        data.vh = nil
                    end
                end
            end

            -- Retention applies to the complete price key. Once all three
            -- history tiers expire, remove only that exact item variant.
            if type(data) == "table"
                and (not data.h or (type(data.h) == "table" and not next(data.h)))
                and (not data.vh or (type(data.vh) == "table" and not next(data.vh)))
                and (tonumber(data.d) or 0) < coldCutoff then
                realmDB.PersonalData[dbKey] = nil
                purgedVariantCount = purgedVariantCount + 1
            end

            i = i + 1
            if i % 500 == 0 then coroutine.yield() end
        end

        if purgedVariantCount > 0 and MarketSync.InvalidateIndexCache then
            MarketSync.InvalidateIndexCache()
        end
        if MarketSyncDB and MarketSyncDB.DebugMode and (compactedDailyCount > 0 or compactedWeeklyCount > 0 or purgedCount > 0 or vhPrunedCount > 0 or purgedVariantCount > 0) then
            print(string.format(
                "|cFF00FF00[MarketSync]|r Retention Downsampler: %d daily, %d weekly, %d old records, %d vh, %d expired variants",
                compactedDailyCount, compactedWeeklyCount, purgedCount, vhPrunedCount, purgedVariantCount))
        end
        if onComplete then
            onComplete(compactedDailyCount, compactedWeeklyCount, purgedCount, vhPrunedCount)
        end
    end)

    local function RunChunk()
        if coroutine.status(co) ~= "dead" then
            local ok, err = coroutine.resume(co)
            if not ok then
                if MarketSync.Debug then MarketSync.Debug("Error in Retention Downsampler coroutine: " .. tostring(err)) end
                error("Error in Retention Downsampler coroutine: " .. tostring(err))
            else
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.02, RunChunk)
                else
                    RunChunk()
                end
            end
        end
    end
    RunChunk()
end

local eventFrame = CreateFrame("Frame")
local function HandleAuctionatorScannerDetection()
    if not (MarketSyncDB and Auctionator and Auctionator.Database) then return end
    if MarketSyncDB.AuctionatorScannerUserChoice ~= true then
        MarketSyncDB.UseAuctionatorScanner = true
    end
    if MarketSyncDB.UseAuctionatorScanner ~= true then return end
    if MarketSync.Scanner and MarketSync.Scanner.Active then
        MarketSync.Scanner.Cancel("Auctionator scanning enabled")
    end
    if MarketSync.Provider and MarketSync.Provider.Select then MarketSync.Provider.Select() end
    if MarketSync.AuctionHouse and MarketSync.AuctionHouse.RefreshTabVisibility then
        MarketSync.AuctionHouse.RefreshTabVisibility()
    end
    if not MarketSyncDB.AuctionatorScannerNoticeShown then
        MarketSyncDB.AuctionatorScannerNoticeShown = true
        print("|cFF00FF00[MarketSync]|r Auctionator detected. MarketSync scanning is disabled. To re-enable it, turn off 'Use Auctionator scanning' in MarketSync Settings.")
    end
end
SafeRegisterEvent(eventFrame, "ADDON_LOADED")
SafeRegisterEvent(eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
SafeRegisterEvent(eventFrame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Auctionator" then
            HandleAuctionatorScannerDetection()
            if not MarketSync.Provider or MarketSync.Provider.GetActiveName() == "auctionator" then
                RegisterAuctionatorHooks()
            end
        elseif arg1 == ADDON_NAME or arg1 == "AuctionatorAnnouncer" then
            MarketSync.InitializeDB()
            HandleAuctionatorScannerDetection()
            CreateMinimapButton()
            if MarketSync.Provider and MarketSync.Provider.Initialize then
                MarketSync.Provider.Initialize()
            end
            if not MarketSync.Provider or MarketSync.Provider.GetActiveName() == "auctionator" then
                RegisterAuctionatorHooks()
            end

        -- FIRST LAUNCH PROTECTION: If the user doesn't have an offline personal snapshot pool yet,
        -- forcibly snapshot whatever exists in their Live Auctionator DB into the mirror pool right now.
        -- This guarantees new users don't see an empty "Personal Snapshot" screen if they've used Auctionator before.
        -- IMPORTANT: If PersonalScanTime exists, the user has already done a real AH scan and their
        -- PersonalData is sacred â€” never overwrite it on boot (guild sync grows the live DB, which
        -- would otherwise trigger the migration check every login).
        C_Timer.After(5, function()
            local hasPersonalScan = MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime
            if hasPersonalScan then return end  -- Sacred personal scan exists, do not touch

            local needsSnapshot = false
            if MarketSyncDB and MarketSync.GetRealmDB().PersonalData then
                local pdCount = 0
                for _ in pairs(MarketSync.GetRealmDB().PersonalData) do pdCount = pdCount + 1 end

                local auctCount = 0
                if Auctionator and Auctionator.Database and Auctionator.Database.db then
                    for _ in pairs(Auctionator.Database.db) do auctCount = auctCount + 1 end
                end

                if pdCount == 0 then
                    needsSnapshot = true  -- First launch, no data at all
                elseif auctCount > pdCount + 500 then
                    needsSnapshot = true  -- Pre-0.4.5 data without variant keys
                    if MarketSyncDB and MarketSyncDB.DebugMode then
                        print("|cFF00FF00[MarketSync]|r Migration: PersonalData is missing variant keys (" .. pdCount .. " vs " .. auctCount .. "), re-snapshotting...")
                    end
                end
            else
                needsSnapshot = true
            end
            if needsSnapshot and MarketSync.SnapshotPersonalScan then
                MarketSync.SnapshotPersonalScan()
            end
        end)

        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- STAGE 2: Passive sync (45s) â€” sets up guild advertisement ticker
        C_Timer.After(45, function()
            -- ... (rest of stage 2)
            MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName()
            MarketSync.StartPassiveSync()
            if MarketSyncDB and MarketSyncDB.DebugMode then
                print("|cFF00FF00[MarketSync]|r Stage 2: Passive sync started (45s)")
            end
        end)

        -- STAGE 2.5: Metadata pruning (60s) â€” trim stale ItemMetadata to prevent RAM bloat
        C_Timer.After(60, function()
            if MarketSync.PruneMetadata then
                MarketSync.PruneMetadata()
            end
            if MarketSync.ValidateItemInfoCacheAsync then
                MarketSync.ValidateItemInfoCacheAsync()
            end
        end)

        -- STAGE 3: Search index cache (90s) â€” only if user opted in
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

        -- STAGE 4: Tiered Retention Downsampler (120s)
        -- Hot (0-7d):    full 30-min resolution (synced via guild swarm)
        -- Warm (8-30d):  daily compact summaries (D:min:max:avg:vol, local)
        -- Cold (31-180d): weekly compact summaries (W:min:max:avg:vol, local)
        -- Purge (>180d): deleted
        C_Timer.After(120, function()
            if MarketSync.DownsampleRetention then
                MarketSync.DownsampleRetention()
            end
        end)
        if C_Timer.NewTicker then
            C_Timer.NewTicker(86400, function()
                if MarketSync.DownsampleRetention then MarketSync.DownsampleRetention() end
                if MarketSync.PruneMetadata then MarketSync.PruneMetadata() end
            end)
        end

        -- Register for AH events so we can invalidate the scan cache dynamically
        SafeRegisterEvent(self, "AUCTION_HOUSE_CLOSED")
        SafeRegisterEvent(self, "AUCTION_HOUSE_SHOW")

        -- Register for Smart Rules state tracking (combat/instance transitions)
        SafeRegisterEvent(self, "PLAYER_REGEN_DISABLED")   -- Entering combat
        SafeRegisterEvent(self, "PLAYER_REGEN_ENABLED")    -- Leaving combat
        SafeRegisterEvent(self, "ZONE_CHANGED_NEW_AREA")   -- Entering/leaving instances
        SafeRegisterEvent(self, "SKILL_LINES_CHANGED")
        SafeRegisterEvent(self, "TRADE_SKILL_SHOW")
        SafeRegisterEvent(self, "TRADE_SKILL_DATA_SOURCE_CHANGED")
        SafeRegisterEvent(self, "TRADE_SKILL_LIST_UPDATE")
        SafeRegisterEvent(self, "TRADE_SKILL_UPDATE")
        if MarketSync.RefreshKnownProfessionCache then
            MarketSync.RefreshKnownProfessionCache()
        end
        MarketSync._lastCanSync = MarketSync.CanSync and MarketSync.CanSync() or true

    elseif event == "AUCTION_HOUSE_SHOW"
        or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and (arg1 == 21 or (Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.Auctioneer))) then
        MarketSync.IsAuctionHouseOpen = true
        MarketSync.IsNeutralAHOpen = false

        -- The legacy/native scanner path uses these counts as a fallback. Auctionator
        -- integration uses exact scan events and should not sweep its whole DB on AH open.
        MarketSync._ahOpenItemCount = 0
        MarketSync._ahOpenTodayCount = 0
        local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
            or (Auctionator and Auctionator.Database and Auctionator.Database.db)
        local auctionatorIntegration = MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true
            and Auctionator and Auctionator.Database
        if liveStore and not auctionatorIntegration then
            local today = MarketSync.GetCurrentScanDay()
            for _, data in pairs(liveStore) do
                MarketSync._ahOpenItemCount = MarketSync._ahOpenItemCount + 1
                if (type(data) == "table" and data.h and data.h[tostring(today)])
                    or (data and data.latest and data.latest.seenAt and (time() - data.latest.seenAt) < 86400) then
                    MarketSync._ahOpenTodayCount = MarketSync._ahOpenTodayCount + 1
                end
            end
        end

        if MarketSync.HandleAuctionHouseShown then
            local ok, isNeutral = pcall(MarketSync.HandleAuctionHouseShown)
            if ok then
                MarketSync.IsNeutralAHOpen = isNeutral and true or false
            else
                MarketSync.Debug("Neutral AH show hook failed: " .. tostring(isNeutral))
            end
        end

    elseif event == "AUCTION_HOUSE_CLOSED"
        or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and (arg1 == 21 or (Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.Auctioneer))) then
        -- Guard: Only run the snapshot pipeline if we actually tracked the AH opening.
        if not MarketSync.IsAuctionHouseOpen then
            MarketSync.Debug("AUCTION_HOUSE_CLOSED fired but AH was never opened — ignoring (spurious event)")
            return
        end
        MarketSync.IsAuctionHouseOpen = false
        local wasNeutralSession = MarketSync.IsNeutralAHOpen
        MarketSync.IsNeutralAHOpen = false

        if MarketSync.HandleAuctionHouseClosed then
            local ok, wasNeutral = pcall(MarketSync.HandleAuctionHouseClosed)
            if ok and wasNeutral then
                wasNeutralSession = true
            elseif not ok then
                MarketSync.Debug("Neutral AH close hook failed: " .. tostring(wasNeutral))
            end
        end

        if wasNeutralSession then
            return
        end
        if MarketSyncDB and MarketSyncDB.UseAuctionatorScanner == true and Auctionator and Auctionator.Database then
            -- Auctionator's exact DB-update/full-scan hooks already imported data.
            -- Closing the AH is not evidence that a complete personal scan occurred.
            MarketSync.GetRealmDB().CachedScanStats = nil
            MarketSync._ahOpenItemCount = nil
            MarketSync._ahOpenTodayCount = nil
            MarketSync._ahFullScanCompleted = nil
            MarketSync._ahScanActivity = nil
            return
        end
        if MarketSyncDB then
            local today = MarketSync.GetCurrentScanDay()
            local myLatestScanDay = MarketSync.GetMyLatestScanDay()

            -- Immediately snapshot the latest DB state exclusively to the PersonalData pool
            if MarketSync.SnapshotPersonalScan then
                local _, todayCount, changedCount = MarketSync.SnapshotPersonalScan()

                local preCount = MarketSync._ahOpenItemCount or 0
                local preToday = MarketSync._ahOpenTodayCount or 0
                local postCount = 0
                local postToday = 0
                local today = MarketSync.GetCurrentScanDay()

                local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
                    or (Auctionator and Auctionator.Database and Auctionator.Database.db)
                if liveStore then
                    for _, data in pairs(liveStore) do 
                        postCount = postCount + 1 
                        if (type(data) == "table" and data.h and data.h[tostring(today)])
                            or (data and data.latest and data.latest.seenAt and (time() - data.latest.seenAt) < 86400) then
                            postToday = postToday + 1
                        end
                    end
                end
                
                -- Detect a real scan if Auctionator/Scanner scanned, items grew, or price changes were recorded
                local scannerScanned = MarketSyncForeverScanner and MarketSyncForeverScanner.Store and MarketSyncForeverScanner.Store.completedWatchScans and MarketSyncForeverScanner.Store.completedWatchScans > 0
                local scanCompleted = MarketSync._ahFullScanCompleted or scannerScanned
                local scanActivity = MarketSync._ahScanActivity and MarketSync._ahScanActivity > 0
                local countGrew = (postCount > preCount) or (postToday > preToday)
                local changesRecorded = (changedCount and changedCount > 0)

                local realScanOccurred = scanCompleted or scanActivity or countGrew or changesRecorded
                MarketSync._ahOpenItemCount = nil
                MarketSync._ahOpenTodayCount = nil
                MarketSync._ahFullScanCompleted = nil
                MarketSync._ahScanActivity = nil

                if realScanOccurred then
                    local now = time()
                    MarketSync.GetRealmDB().PersonalScanTime = now  -- Sacred: actual AH scan
                    MarketSync.GetRealmDB().SwarmTSF = now          -- Protocol freshness
                    if myLatestScanDay == today then
                        MarketSync.GetRealmDB().LastCountDay = today
                        MarketSync.GetRealmDB().LastTodayCount = todayCount
                    end
                elseif not realScanOccurred then
                    MarketSync.Debug("AH closed without a real scan (" .. preCount .. " -> " .. postCount .. " items) — skipping PersonalScanTime stamp")
                end
            end

            if MarketSync.GetRealmDB().CachedScanStats then
                MarketSync.GetRealmDB().CachedScanStats = nil
                if MarketSyncDB.PassiveSync and MarketSync.SendAdvertisement then
                    -- Broadcast our new findings roughly 2 seconds after closing the AH
                    C_Timer.After(2, function() MarketSync.SendAdvertisement() end)
                end
            end

            -- Invalidate browse index so Guild Sync tab reflects fresh scan data
            -- then trigger a rebuild so the async resolver starts fresh
            if MarketSync.InvalidateIndexCache then
                MarketSync.InvalidateIndexCache()
            end
            if MarketSync.BuildSearchIndex then
                C_Timer.After(1, function() MarketSync.BuildSearchIndex() end)
            end
        end

    -- Keep known profession recipes in sync with the player's profession book.
    elseif event == "TRADE_SKILL_SHOW"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED"
        or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_UPDATE"
        or event == "SKILL_LINES_CHANGED" then
        if MarketSync.RefreshKnownProfessionCache then
            MarketSync.RefreshKnownProfessionCache()
        end
        if event == "SKILL_LINES_CHANGED" then
            return
        end
        if MarketSync.RefreshKnownCraftingRecipes then
            MarketSync.RefreshKnownCraftingRecipes()
        end

    -- ================================================================
    -- SMART RULES: State Transition Logging
    -- Detect when sync eligibility changes and log the reason
    -- ================================================================
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
        or event == "ZONE_CHANGED_NEW_AREA" then

        -- Short delay to let WoW state settle (IsInInstance can lag slightly on zone transitions)
        C_Timer.After(0.5, function()
            if not MarketSync.CanSync then return end
            local canNow = MarketSync.CanSync()
            local couldBefore = MarketSync._lastCanSync

            if canNow ~= couldBefore then
                MarketSync._lastCanSync = canNow

                -- Determine the specific reason for the state change
                local reason = ""
                if not canNow then
                    -- Identify why sync was disabled
                    if InCombatLockdown and InCombatLockdown() then
                        reason = "Entered Combat"
                    elseif IsInInstance then
                        local inInstance, instanceType = IsInInstance()
                        if inInstance then
                            if instanceType == "raid" then reason = "Entered Raid"
                            elseif instanceType == "party" then reason = "Entered Dungeon"
                            elseif instanceType == "pvp" then reason = "Entered Battleground"
                            elseif instanceType == "arena" then reason = "Entered Arena"
                            else reason = "Entered Instance (" .. (instanceType or "unknown") .. ")"
                            end
                        end
                    end
                    if reason == "" then reason = "Smart Rules" end

                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent("|cffff4444[Smart Rules]|r Sync |cffff4444DISABLED|r â€” " .. reason)
                    end
                    MarketSync.Debug("Smart Rules: Sync DISABLED â€” " .. reason)
                    if MarketSync.UpdateSwarmUI then
                        MarketSync.UpdateSwarmUI(UnitName("player"), "Paused (" .. reason .. ")")
                    end
                    if MarketSync.SetPullRequestPending then
                        MarketSync.SetPullRequestPending(false)
                    end
                else
                    -- Identify why sync was re-enabled
                    if event == "PLAYER_REGEN_ENABLED" then
                        reason = "Left Combat"
                    elseif event == "ZONE_CHANGED_NEW_AREA" then
                        reason = "Left Instance"
                    else
                        reason = "Conditions cleared"
                    end

                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent("|cff44ff44[Smart Rules]|r Sync |cff44ff44ENABLED|r â€” " .. reason)
                    end
                    MarketSync.Debug("Smart Rules: Sync ENABLED â€” " .. reason)
                    if MarketSync.UpdateSwarmUI then
                        MarketSync.UpdateSwarmUI(UnitName("player"), nil)
                    end

                    -- If a fresher ADV was deferred while we were blocked, process it now.
                    if MarketSync.ProcessDeferredADV then
                        C_Timer.After(0.5, function()
                            if MarketSync.ProcessDeferredADV then
                                MarketSync.ProcessDeferredADV()
                            end
                        end)
                    end
                end
            end
        end)
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
