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

    MonitorFrame = MarketSync.CreateModernDialog("MarketSyncMonitorFrame", 680, 560, "|cFFFFD100Network Monitor & Debug Console|r")
    MonitorFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    MonitorFrame:SetFrameLevel(100)
    MonitorFrame:SetToplevel(true)
    MonitorFrame:Hide()

    -- Quick button to open Task Manager right in the header
    local btnTaskMgr = CreateFrame("Button", nil, MonitorFrame.Header, "UIPanelButtonTemplate")
    btnTaskMgr:SetSize(110, 20)
    btnTaskMgr:SetPoint("RIGHT", MonitorFrame.CloseButton, "LEFT", -6, 0)
    btnTaskMgr:SetText("Task Manager")
    btnTaskMgr:SetScript("OnClick", function()
        if MarketSync.ToggleRateMonitor then
            MarketSync.ToggleRateMonitor()
        end
    end)

    local monSub = MonitorFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    monSub:SetPoint("TOPLEFT", 16, -36)
    monSub:SetText("|cff888888Real-time communication events, peer status, and cache pipeline activity.|r")

    -- Stats Panel
    local statsPanel = MarketSync.CreateModernInset(MonitorFrame, 14, -56, 652, 34)

    local txLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txLabel:SetPoint("LEFT", 16, 0)
    txLabel:SetText("|cffff8800Tx: 0 msgs/s|r")
    MonitorFrame.txLabel = txLabel

    local rxLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rxLabel:SetPoint("LEFT", 190, 0)
    rxLabel:SetText("|cff00ff00Rx: 0 msgs/s|r")
    MonitorFrame.rxLabel = rxLabel

    local queueLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueLabel:SetPoint("LEFT", 360, 0)
    queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
    MonitorFrame.queueLabel = queueLabel

    local limitBadge = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    limitBadge:SetPoint("RIGHT", -16, 0)
    limitBadge:SetText("Throttle Limit: ~800 B/s")

    -- Log / Console Header & Inset
    local logHeader = MarketSync.CreateAHColumnHeader(MonitorFrame, 450, 20, "Network Event Log")
    logHeader:SetPoint("TOPLEFT", 14, -96)

    local logPanel = MarketSync.CreateModernInset(MonitorFrame, 14, -116, 450, 216)

    local logScroll = CreateFrame("ScrollingMessageFrame", nil, logPanel)
    logScroll:SetPoint("TOPLEFT", logPanel, "TOPLEFT", 8, -6)
    logScroll:SetPoint("BOTTOMRIGHT", logPanel, "BOTTOMRIGHT", -8, 6)
    logScroll:SetFontObject("GameFontHighlightSmall")
    logScroll:SetJustifyH("LEFT")
    logScroll:SetFading(false)
    logScroll:SetMaxLines(500)
    logScroll:EnableMouseWheel(true)
    logScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    MonitorFrame.logScroll = logScroll

    -- Swarm Queue Tracker Header & Inset
    local swarmHeader = MarketSync.CreateAHColumnHeader(MonitorFrame, 194, 20, "Swarm Queue")
    swarmHeader:SetPoint("TOPLEFT", 472, -96)

    local swarmPanel = MarketSync.CreateModernInset(MonitorFrame, 472, -116, 194, 216)

    local swarmText = CreateFrame("ScrollingMessageFrame", nil, swarmPanel)
    swarmText:SetPoint("TOPLEFT", swarmPanel, "TOPLEFT", 8, -6)
    swarmText:SetPoint("BOTTOMRIGHT", swarmPanel, "BOTTOMRIGHT", -8, 6)
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
    logScroll:AddMessage("|cFF00FF00[MarketSync]|r Network Monitor Initialized. Listening for sync events...", 1, 1, 1)

    -- Cache Activity Stream Header & Inset
    local cacheHeader = MarketSync.CreateAHColumnHeader(MonitorFrame, 652, 20, "Cache Processing Stream")
    cacheHeader:SetPoint("TOPLEFT", 14, -338)

    local btnClearCache = CreateFrame("Button", nil, cacheHeader, "UIPanelButtonTemplate")
    btnClearCache:SetSize(60, 18)
    btnClearCache:SetPoint("RIGHT", -4, 0)
    btnClearCache:SetText("Clear")
    btnClearCache:SetScript("OnClick", function()
        if MonitorFrame and MonitorFrame.cacheScroll then
            MonitorFrame.cacheScroll:Clear()
            MonitorFrame.cacheScroll:AddMessage("|cff888888Cache log cleared.|r")
        end
    end)

    local cachePanel = MarketSync.CreateModernInset(MonitorFrame, 14, -358, 652, 160)

    local cacheScroll = CreateFrame("ScrollingMessageFrame", nil, cachePanel)
    cacheScroll:SetPoint("TOPLEFT", cachePanel, "TOPLEFT", 8, -6)
    cacheScroll:SetPoint("BOTTOMRIGHT", cachePanel, "BOTTOMRIGHT", -8, 6)
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

    -- Bottom Close Button
    local btnCloseMon = CreateFrame("Button", nil, MonitorFrame, "UIPanelButtonTemplate")
    btnCloseMon:SetSize(80, 22)
    btnCloseMon:SetPoint("BOTTOMRIGHT", MonitorFrame, "BOTTOMRIGHT", -14, 10)
    btnCloseMon:SetText("Close")
    btnCloseMon:SetScript("OnClick", function() MonitorFrame:Hide() end)

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

    RateMonitorFrame = MarketSync.CreateModernDialog("MarketSyncRateMonitorFrame", 400, 440, "|cFFFFD100Task Manager: Rate Limiter|r")
    RateMonitorFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    RateMonitorFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    RateMonitorFrame:SetFrameLevel(105)
    RateMonitorFrame:SetToplevel(true)
    RateMonitorFrame:Hide()

    local rateSub = RateMonitorFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rateSub:SetPoint("TOPLEFT", 16, -36)
    rateSub:SetText("|cff888888Real-time sync throughput and bandwidth throttle monitor.|r")

    -- Card 1: Throughput & Bandwidth Inset
    local card1 = MarketSync.CreateModernInset(RateMonitorFrame, 14, -56, 372, 136)

    local card1Title = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card1Title:SetPoint("TOPLEFT", 12, -10)
    card1Title:SetText("|cffffd700Bandwidth & API Throughput|r")

    local txMsgLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txMsgLabel:SetPoint("TOPLEFT", 14, -30)
    txMsgLabel:SetText("Tx API Calls: 0/sec |cff888888(WoW Limit: ~50/s)|r")
    RateMonitorFrame.txMsgLabel = txMsgLabel

    local rxMsgLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rxMsgLabel:SetPoint("TOPLEFT", 14, -48)
    rxMsgLabel:SetText("Rx API Calls: 0/sec")
    RateMonitorFrame.rxMsgLabel = rxMsgLabel

    local txByteLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txByteLabel:SetPoint("TOPLEFT", 14, -66)
    txByteLabel:SetText("Tx Bandwidth: 0 B/s")
    RateMonitorFrame.txByteLabel = txByteLabel

    local limitLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    limitLabel:SetPoint("TOPLEFT", 14, -84)
    limitLabel:SetText("Throttle Threshold: ~800 B/s")

    -- Modern Progress Bar Track & Fill
    local barTrack = CreateFrame("Frame", nil, card1, "BackdropTemplate")
    barTrack:SetSize(344, 20)
    barTrack:SetPoint("TOPLEFT", 14, -104)
    barTrack:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    barTrack:SetBackdropColor(0.02, 0.03, 0.04, 1.0)
    barTrack:SetBackdropBorderColor(0.22, 0.24, 0.28, 0.9)

    local rateBar = CreateFrame("StatusBar", nil, barTrack)
    rateBar:SetPoint("TOPLEFT", 1, -1)
    rateBar:SetPoint("BOTTOMRIGHT", -1, 1)
    rateBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rateBar:GetStatusBarTexture():SetHorizTile(false)
    rateBar:SetMinMaxValues(0, 800)
    rateBar:SetValue(0)
    rateBar:SetStatusBarColor(0.20, 0.85, 0.30)

    local rateBarText = rateBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rateBarText:SetPoint("CENTER", barTrack, "CENTER", 0, 0)
    rateBarText:SetText("0 B/s (0.0% of limit)")
    RateMonitorFrame.rateBar = rateBar
    RateMonitorFrame.rateBarText = rateBarText

    -- Card 2: Top Addons Breakdown Table
    local hdrAddon = MarketSync.CreateAHColumnHeader(RateMonitorFrame, 192, 20, "Addon / Prefix")
    hdrAddon:SetPoint("TOPLEFT", 14, -198)

    local hdrApi = MarketSync.CreateAHColumnHeader(RateMonitorFrame, 80, 20, "API/s")
    hdrApi:SetPoint("LEFT", hdrAddon, "RIGHT", 0, 0)

    local hdrBytes = MarketSync.CreateAHColumnHeader(RateMonitorFrame, 100, 20, "Bandwidth")
    hdrBytes:SetPoint("LEFT", hdrApi, "RIGHT", 0, 0)

    local card2 = MarketSync.CreateModernInset(RateMonitorFrame, 14, -218, 372, 180)

    local emptyAddons = card2:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyAddons:SetPoint("CENTER", card2, "CENTER", 0, 0)
    emptyAddons:SetText("|cff888888No active addon traffic detected.|r")
    RateMonitorFrame.emptyAddonsText = emptyAddons

    RateMonitorFrame.addonRows = {}
    RateMonitorFrame.addonLabels = {}

    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, card2)
        row:SetSize(368, 24)
        row:SetPoint("TOPLEFT", 2, -(i - 1) * 25 - 2)

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 1 then
            rowBg:SetColorTexture(0.07, 0.09, 0.12, 0.65)
        else
            rowBg:SetColorTexture(0.04, 0.05, 0.07, 0.65)
        end
        row.bg = rowBg

        local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", 8, 0)
        nameText:SetWidth(180)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local apiText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        apiText:SetPoint("LEFT", 192, 0)
        apiText:SetWidth(75)
        apiText:SetJustifyH("CENTER")
        row.apiText = apiText

        local byteText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        byteText:SetPoint("RIGHT", -8, 0)
        byteText:SetWidth(90)
        byteText:SetJustifyH("RIGHT")
        row.byteText = byteText

        row:Hide()
        RateMonitorFrame.addonRows[i] = row

        -- Legacy fallback label compatibility
        RateMonitorFrame.addonLabels[i] = nameText
    end

    -- Bottom Controls
    local btnConsole = CreateFrame("Button", nil, RateMonitorFrame, "UIPanelButtonTemplate")
    btnConsole:SetSize(120, 22)
    btnConsole:SetPoint("BOTTOMLEFT", RateMonitorFrame, "BOTTOMLEFT", 14, 12)
    btnConsole:SetText("Debug Console")
    btnConsole:SetScript("OnClick", function()
        if MarketSync.ToggleNetworkMonitor then
            MarketSync.ToggleNetworkMonitor()
        end
    end)

    local btnCloseRate = CreateFrame("Button", nil, RateMonitorFrame, "UIPanelButtonTemplate")
    btnCloseRate:SetSize(80, 22)
    btnCloseRate:SetPoint("BOTTOMRIGHT", RateMonitorFrame, "BOTTOMRIGHT", -14, 12)
    btnCloseRate:SetText("Close")
    btnCloseRate:SetScript("OnClick", function() RateMonitorFrame:Hide() end)
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

    local bytes = txBytesRate or 0
    local usagePct = math.min(1.0, bytes / 800)
    RateMonitorFrame.rateBar:SetValue(bytes)
    if RateMonitorFrame.rateBarText then
        RateMonitorFrame.rateBarText:SetText(string.format("%d B/s (%.1f%% of throttle limit)", bytes, usagePct * 100))
    end

    -- Color the progress bar smoothly: Green -> Amber -> Red
    if usagePct < 0.5 then
        RateMonitorFrame.rateBar:SetStatusBarColor(0.20, 0.85, 0.30) -- Green
    elseif usagePct < 0.8 then
        RateMonitorFrame.rateBar:SetStatusBarColor(0.95, 0.75, 0.10) -- Amber
    else
        RateMonitorFrame.rateBar:SetStatusBarColor(0.95, 0.25, 0.20) -- Red
    end

    -- Update Top Addons List
    local hasAddons = false
    for i = 1, 6 do
        local row = RateMonitorFrame.addonRows and RateMonitorFrame.addonRows[i]
        local label = RateMonitorFrame.addonLabels and RateMonitorFrame.addonLabels[i]
        local data = addonRates and addonRates[i]
        if data then
            hasAddons = true
            if row then
                row.nameText:SetText(string.format("%d. %s", i, tostring(data.prefix)))
                row.apiText:SetText(string.format("%d/s", data.apiRate or 0))
                row.byteText:SetText(string.format("%d B/s", data.rate or 0))
                row:Show()
            end
            if label and label ~= row.nameText then
                label:SetText(string.format("%d. %s: %d/sec | %d B/s", i, tostring(data.prefix), data.apiRate or 0, data.rate or 0))
            end
        else
            if row then row:Hide() end
            if label and label ~= (row and row.nameText) then label:SetText("") end
        end
    end
    if RateMonitorFrame.emptyAddonsText then
        if hasAddons then
            RateMonitorFrame.emptyAddonsText:Hide()
        else
            RateMonitorFrame.emptyAddonsText:Show()
        end
    end
end
