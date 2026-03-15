-- =============================================================
-- MarketSync - Network Monitor
-- A standalone window displaying real-time sync bandwidth and events
-- =============================================================

local ADDON_NAME = "MarketSync"
local MarketSync = _G.MarketSync
local FormatMoney = MarketSync.FormatMoney

local MonitorFrame = nil
local earlyCacheLogs = {}
local earlyNetworkLogs = {}
local CACHE_LOG_TAGS = {
    "[Start]",
    "[Personal]",
    "[Personal Done]",
    "[Guild]",
    "[Pass 1 Done]",
    "[Done]",
    "[Async Resolve]",
    "[Guild Commit]",
    "[Neutral Commit]",
}

local function IsCacheLogMessage(msg)
    if type(msg) ~= "string" then return false end
    for _, tag in ipairs(CACHE_LOG_TAGS) do
        if string.find(msg, tag, 1, true) then
            return true
        end
    end
    if string.find(msg, "Index build", 1, true) then
        return true
    end
    if string.find(msg, "Neutral sync started - buffering incoming data.", 1, true) then
        return true
    end
    if string.find(msg, "[Neutral]", 1, true) and string.find(msg, "Processed", 1, true) then
        return true
    end
    return false
end

local function CreateMonitorFrame()
    if MonitorFrame then return end

    MonitorFrame = CreateFrame("Frame", "MarketSyncMonitorFrame", UIParent, "BasicFrameTemplateWithInset")
    MonitorFrame:SetSize(620, 520)
    MonitorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    MonitorFrame:SetMovable(true)
    MonitorFrame:EnableMouse(true)
    MonitorFrame:RegisterForDrag("LeftButton")
    MonitorFrame:SetScript("OnDragStart", MonitorFrame.StartMoving)
    MonitorFrame:SetScript("OnDragStop", MonitorFrame.StopMovingOrSizing)
    MonitorFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    MonitorFrame:SetFrameLevel(100)
    MonitorFrame:SetToplevel(true)
    MonitorFrame:Hide()
    
    -- Make it close on ESC
    table.insert(UISpecialFrames, "MarketSyncMonitorFrame")

    MonitorFrame.TitleText:SetText("MarketSync Debug Console")
    MonitorFrame.TitleText:ClearAllPoints()
    local titleAnchor = MonitorFrame.TitleContainer or MonitorFrame.TitleBg or MonitorFrame
    MonitorFrame.TitleText:SetPoint("CENTER", titleAnchor, "CENTER", 0, 0)

    -- Right-click menu for opening Task Manager
    local titleButton = CreateFrame("Button", nil, MonitorFrame)
    titleButton:SetAllPoints(MonitorFrame.TitleText)
    titleButton:RegisterForClicks("RightButtonUp")
    local dd = CreateFrame("Frame", "MarketSyncMonitorConfigDropdown", MonitorFrame, "UIDropDownMenuTemplate")
    titleButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            UIDropDownMenu_Initialize(dd, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                info.text = "Open Rate Monitor (Task Manager)"
                info.notCheckable = true
                info.func = function()
                    if MarketSync.ToggleRateMonitor then
                        MarketSync.ToggleRateMonitor()
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end, "MENU")
            ToggleDropDownMenu(1, nil, dd, "cursor", 0, 0)
        end
    end)

    -- Stats Panel
    local statsPanel = CreateFrame("Frame", nil, MonitorFrame, "BackdropTemplate")
    statsPanel:SetSize(580, 40)
    statsPanel:SetPoint("TOP", MonitorFrame, "TOP", 0, -30)
    statsPanel.backdropInfo = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    statsPanel:ApplyBackdrop()
    statsPanel:SetBackdropColor(0, 0, 0, 0.5)

    local txLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txLabel:SetPoint("LEFT", 15, 0)
    txLabel:SetText("|cffff8800Tx: 0 msgs/s|r")
    MonitorFrame.txLabel = txLabel

    local rxLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rxLabel:SetPoint("LEFT", 200, 0)
    rxLabel:SetText("|cff00ff00Rx: 0 msgs/s|r")
    MonitorFrame.rxLabel = rxLabel

    local queueLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueLabel:SetPoint("RIGHT", -15, 0)
    queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
    MonitorFrame.queueLabel = queueLabel
    -- Log / Console
    local logPanel = CreateFrame("Frame", nil, MonitorFrame, "BackdropTemplate")
    logPanel:SetSize(410, 200)
    logPanel:SetPoint("TOPLEFT", statsPanel, "BOTTOMLEFT", 0, -10)
    logPanel.backdropInfo = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    logPanel:ApplyBackdrop()
    logPanel:SetBackdropColor(0, 0, 0, 0.5)

    local logScroll = CreateFrame("ScrollingMessageFrame", nil, logPanel)
    logScroll:SetPoint("TOPLEFT", logPanel, "TOPLEFT", 10, -10)
    logScroll:SetPoint("BOTTOMRIGHT", logPanel, "BOTTOMRIGHT", -10, 10)
    logScroll:SetFontObject("GameFontHighlightSmall")
    logScroll:SetJustifyH("LEFT")
    logScroll:SetFading(false)
    logScroll:SetMaxLines(500)
    logScroll:EnableMouseWheel(true)
    logScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    MonitorFrame.logScroll = logScroll
    
    -- Swarm Queue Tracker
    local swarmPanel = CreateFrame("Frame", nil, MonitorFrame, "BackdropTemplate")
    swarmPanel:SetSize(160, 200)
    swarmPanel:SetPoint("TOPRIGHT", statsPanel, "BOTTOMRIGHT", 0, -10)
    swarmPanel.backdropInfo = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    swarmPanel:ApplyBackdrop()
    
    local swarmTitle = swarmPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    swarmTitle:SetPoint("TOP", 0, -10)
    swarmTitle:SetText("Swarm Queue")

    local swarmText = CreateFrame("ScrollingMessageFrame", nil, swarmPanel)
    swarmText:SetPoint("TOPLEFT", 10, -25)
    swarmText:SetPoint("BOTTOMRIGHT", -10, 10)
    swarmText:SetFontObject("GameFontHighlightSmall")
    swarmText:SetJustifyH("LEFT")
    swarmText:SetFading(false)
    swarmText:SetMaxLines(50)
    swarmText:EnableMouseWheel(true)
    swarmText:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    MonitorFrame.swarmText = swarmText
    
    -- Initialize display
    swarmText:AddMessage("No active peers.")
    -- Add an introductory message
    logScroll:AddMessage("|cFF00FF00[MarketSync]|r Network Monitor Initialized. Listening for sync events...", 1, 1, 1)

    -- Cache Activity Stream
    local cachePanel = CreateFrame("Frame", nil, MonitorFrame, "BackdropTemplate")
    cachePanel:SetSize(580, 200)
    cachePanel:SetPoint("TOPLEFT", logPanel, "BOTTOMLEFT", 0, -10)
    cachePanel.backdropInfo = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    }
    cachePanel:ApplyBackdrop()
    cachePanel:SetBackdropColor(0, 0, 0, 0.5)

    local cacheTitle = cachePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cacheTitle:SetPoint("TOPLEFT", 10, -10)
    cacheTitle:SetText("Cache Processing Stream")

    local cacheScroll = CreateFrame("ScrollingMessageFrame", nil, cachePanel)
    cacheScroll:SetPoint("TOPLEFT", cachePanel, "TOPLEFT", 10, -30)
    cacheScroll:SetPoint("BOTTOMRIGHT", cachePanel, "BOTTOMRIGHT", -10, 10)
    cacheScroll:SetFontObject("GameFontHighlightSmall")
    cacheScroll:SetJustifyH("LEFT")
    cacheScroll:SetFading(false)
    cacheScroll:SetMaxLines(500)
    cacheScroll:EnableMouseWheel(true)
    cacheScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    MonitorFrame.cacheScroll = cacheScroll
    cacheScroll:AddMessage("|cFF00FF00[MarketSync]|r Cache Monitor Initialized. Ready for rebuild tasks...", 1, 1, 1)

    -- Dump early logs
    for _, log in ipairs(earlyNetworkLogs) do
        MonitorFrame.logScroll:AddMessage(log)
    end
    wipe(earlyNetworkLogs)
    
    for _, log in ipairs(earlyCacheLogs) do
        MonitorFrame.cacheScroll:AddMessage(log)
    end
    wipe(earlyCacheLogs)

end

function MarketSync.LogCacheEvent(msg)
    local timestamp = date("%H:%M:%S")
    local formattedMsg = string.format("[%s] %s", timestamp, msg)
    if MonitorFrame and MonitorFrame.cacheScroll then
        MonitorFrame.cacheScroll:AddMessage(formattedMsg)
    else
        table.insert(earlyCacheLogs, formattedMsg)
        if #earlyCacheLogs > 500 then table.remove(earlyCacheLogs, 1) end
    end
end

function MarketSync.ToggleNetworkMonitor()
    if not MonitorFrame then CreateMonitorFrame() end
    if MonitorFrame:IsShown() then
        MonitorFrame:Hide()
    else
        MonitorFrame:Show()
        -- Force a refresh so we see ourselves instantly
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), nil)
        end
    end
end

-- (Removed UpdateNetworkUI hook; now natively handled by UI_Main.lua)

-- Function to add log entries
function MarketSync.LogNetworkEvent(msg)
    if IsCacheLogMessage(msg) then
        if MarketSync.LogCacheEvent then
            MarketSync.LogCacheEvent(msg)
        end
        return
    end
    local formattedMsg = date("%H:%M:%S") .. " " .. msg
    if MonitorFrame and MonitorFrame.logScroll then
        MonitorFrame.logScroll:AddMessage(formattedMsg)
    else
        table.insert(earlyNetworkLogs, formattedMsg)
        if #earlyNetworkLogs > 500 then table.remove(earlyNetworkLogs, 1) end
    end
end

-- ================================================================
-- SWARM TRACKING LOGIC
-- ================================================================
MarketSync.SwarmPeers = {}

function MarketSync.UpdateSwarmUI(user, status)
    if not user then return end
    
    if status then
        MarketSync.SwarmPeers[user] = { status = status, time = time() }
    else
        -- Instead of deleting the user when they finish, drop them to Idle
        if MarketSync.SwarmPeers[user] then
            local fallback = (user == UnitName("player") and not IsInGuild()) and "No Guild" or "Idle"
            MarketSync.SwarmPeers[user].status = fallback
            MarketSync.SwarmPeers[user].time = time()
        end
    end
    
    if not MonitorFrame or not MonitorFrame:IsShown() then return end
    
    MonitorFrame.swarmText:Clear()
    local now = time()
    
    local myName = UnitName("player")
    local myDefaultStatus = IsInGuild() and "Idle" or "No Guild"
    
    if myName and not MarketSync.SwarmPeers[myName] then
        MarketSync.SwarmPeers[myName] = { status = myDefaultStatus, time = now }
    elseif myName and MarketSync.SwarmPeers[myName] and (MarketSync.SwarmPeers[myName].status == "Idle" or MarketSync.SwarmPeers[myName].status == "No Guild") then
        MarketSync.SwarmPeers[myName].status = myDefaultStatus
    end
    
    local sortedPeers = {}
    for peer, info in pairs(MarketSync.SwarmPeers) do
        -- Expire Idle statuses after 5 minutes of total silence (except for ourselves)
        if peer ~= myName and (now - info.time > 300) then
            MarketSync.SwarmPeers[peer] = nil
        else
            table.insert(sortedPeers, { name = peer, status = info.status, time = info.time })
        end
    end
    
    local function GetStatusWeight(statusText)
        if statusText == "Sending Neutral" then return 9 end
        if statusText == "Receiving Neutral" then return 8 end
        if statusText == "Sending" then return 7 end
        if statusText == "Receiving" then return 6 end
        if statusText == "Awaiting Neutral Data" then return 6 end
        if statusText == "Awaiting Data" then return 5 end
        if statusText == "Neutral Capture" then return 5 end
        if statusText == "Waiting" then return 4 end
        if string.find(statusText, "Blocked", 1, true) then return 4 end
        if statusText == "Ready" then return 3 end
        if string.find(statusText, "Version Mismatch", 1, true) then return 2 end
        if statusText == "Error" then return 2 end
        if string.find(statusText, "Paused", 1, true) then return 2 end
        if statusText == "Idle" then return 1 end
        if statusText == "Disabled" then return 1 end
        if statusText == "No Guild" then return 0 end
        return 1
    end

    local function GetStatusColor(statusText)
        if statusText == "Sending Neutral" then return "|cff44ddff" end
        if statusText == "Receiving Neutral" then return "|cff00ffff" end
        if statusText == "Sending" then return "|cff00ff00" end
        if statusText == "Receiving" then return "|cff66ffcc" end
        if statusText == "Awaiting Neutral Data" then return "|cff66ccff" end
        if statusText == "Awaiting Data" then return "|cffffff00" end
        if statusText == "Neutral Capture" then return "|cff33ccff" end
        if statusText == "Waiting" then return "|cffff8800" end
        if string.find(statusText, "Blocked", 1, true) then return "|cffffaa00" end
        if statusText == "Ready" then return "|cffffffff" end
        if string.find(statusText, "Version Mismatch", 1, true) then return "|cffff4444" end
        if statusText == "Error" then return "|cffff0000" end
        if string.find(statusText, "Paused", 1, true) then return "|cffff8800" end
        if statusText == "Disabled" then return "|cff666666" end
        if statusText == "No Guild" then return "|cff555555" end
        return "|cff888888"
    end
    
    table.sort(sortedPeers, function(a, b)
        local wA = GetStatusWeight(a.status or "Idle")
        local wB = GetStatusWeight(b.status or "Idle")
        if wA ~= wB then
            return wA > wB -- Higher weight first
        end
        return a.name < b.name -- Alphabetical tie breaker
    end)
    
    local count = 0
    for _, peerInfo in ipairs(sortedPeers) do
        local statusText = peerInfo.status or "Idle"
        local color = GetStatusColor(statusText)
        
        MonitorFrame.swarmText:AddMessage(peerInfo.name .. ": " .. color .. statusText .. "|r")
        count = count + 1
    end
    
    if count == 0 then MonitorFrame.swarmText:AddMessage("No active peers.") end
end

-- ================================================================
-- RATE MONITOR (TASK MANAGER)
-- ================================================================
local RateMonitorFrame = nil

local function CreateRateMonitorFrame()
    if RateMonitorFrame then return end

    RateMonitorFrame = CreateFrame("Frame", "MarketSyncRateMonitorFrame", UIParent, "BasicFrameTemplateWithInset")
    RateMonitorFrame:SetSize(300, 260)
    RateMonitorFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    RateMonitorFrame:SetMovable(true)
    RateMonitorFrame:EnableMouse(true)
    RateMonitorFrame:RegisterForDrag("LeftButton")
    RateMonitorFrame:SetScript("OnDragStart", RateMonitorFrame.StartMoving)
    RateMonitorFrame:SetScript("OnDragStop", RateMonitorFrame.StopMovingOrSizing)
    RateMonitorFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    RateMonitorFrame:SetFrameLevel(105)
    RateMonitorFrame:SetToplevel(true)
    RateMonitorFrame:Hide()
    
    table.insert(UISpecialFrames, "MarketSyncRateMonitorFrame")

    RateMonitorFrame.TitleText:SetText("Rate Limiter Monitor")
    RateMonitorFrame.TitleText:ClearAllPoints()
    local titleAnchor = RateMonitorFrame.TitleContainer or RateMonitorFrame.TitleBg or RateMonitorFrame
    RateMonitorFrame.TitleText:SetPoint("CENTER", titleAnchor, "CENTER", 0, 0)

    local txMsgLabel = RateMonitorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txMsgLabel:SetPoint("TOPLEFT", 15, -35)
    txMsgLabel:SetText("Tx API Calls: 0/sec")
    RateMonitorFrame.txMsgLabel = txMsgLabel

    local rxMsgLabel = RateMonitorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rxMsgLabel:SetPoint("TOPLEFT", 15, -55)
    rxMsgLabel:SetText("Rx API Calls: 0/sec")
    RateMonitorFrame.rxMsgLabel = rxMsgLabel

    local txByteLabel = RateMonitorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txByteLabel:SetPoint("TOPLEFT", 15, -75)
    txByteLabel:SetText("Tx Bandwidth: 0 B/s")
    RateMonitorFrame.txByteLabel = txByteLabel

    local limitLabel = RateMonitorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    limitLabel:SetPoint("TOPLEFT", 15, -100)
    limitLabel:SetText("Global Server Rate Limit Threshold: ~800 B/s")
    
    local rateBar = CreateFrame("StatusBar", nil, RateMonitorFrame, "TextStatusBar")
    rateBar:SetSize(260, 20)
    rateBar:SetPoint("TOPLEFT", 15, -120)
    rateBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rateBar:GetStatusBarTexture():SetHorizTile(false)
    rateBar:SetMinMaxValues(0, 800)
    rateBar:SetValue(0)
    rateBar:SetStatusBarColor(0, 1, 0)
    
    local bg = rateBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)

    local border = CreateFrame("Frame", nil, rateBar, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    
    RateMonitorFrame.rateBar = rateBar

    -- Top Addons Breakdown
    local breakdownHeader = RateMonitorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    breakdownHeader:SetPoint("TOPLEFT", 15, -150)
    breakdownHeader:SetText("|cffffd700Top Addons (API/s | B/s)|r")

    RateMonitorFrame.addonLabels = {}
    local yOffset = -170
    for i = 1, 5 do
        local lbl = RateMonitorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 25, yOffset)
        lbl:SetText("")
        RateMonitorFrame.addonLabels[i] = lbl
        yOffset = yOffset - 15
    end
end

function MarketSync.ToggleRateMonitor()
    if not RateMonitorFrame then CreateRateMonitorFrame() end
    if RateMonitorFrame:IsShown() then
        RateMonitorFrame:Hide()
    else
        RateMonitorFrame:Show()
    end
end

function MarketSync.UpdateRateMonitor(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
    if not RateMonitorFrame or not RateMonitorFrame:IsShown() then return end

    local apiRateSafe = txAPIRate or 0
    RateMonitorFrame.txMsgLabel:SetText(string.format("Tx API Calls: %d/sec |cffaaaaaa(WoW Limit: ~50/s)|r", apiRateSafe))
    RateMonitorFrame.rxMsgLabel:SetText(string.format("Rx API Calls: %d/sec", rxRate or 0))
    RateMonitorFrame.txByteLabel:SetText(string.format("Tx Bandwidth: %d B/s", txBytesRate or 0))

    local usagePct = math.min(1.0, (txBytesRate or 0) / 800)
    RateMonitorFrame.rateBar:SetValue(txBytesRate or 0)
    
    -- Color the progress bar from Green -> Yellow -> Red
    if usagePct < 0.5 then
        RateMonitorFrame.rateBar:SetStatusBarColor(0, 1, 0) -- Green
    elseif usagePct < 0.8 then
        RateMonitorFrame.rateBar:SetStatusBarColor(1, 1, 0) -- Yellow
    else
        RateMonitorFrame.rateBar:SetStatusBarColor(1, 0, 0) -- Red
    end

    -- Update Top 5 List
    for i = 1, 5 do
        local label = RateMonitorFrame.addonLabels[i]
        local data = addonRates and addonRates[i]
        if data then
            label:SetText(string.format("%d. %s: %d/sec | %d B/s", i, tostring(data.prefix), data.apiRate or 0, data.rate))
        else
            label:SetText("")
        end
    end
end
