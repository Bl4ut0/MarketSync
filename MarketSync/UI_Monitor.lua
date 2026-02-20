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
    logScroll:SetMaxLines(250)
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
    swarmText:SetMaxLines(100)
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
    cacheScroll:SetMaxLines(250)
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
        if #earlyCacheLogs > 200 then table.remove(earlyCacheLogs, 1) end
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

-- Hook into UpdateNetworkUI to update the Stats Panel
local originalUpdateUI = MarketSync.UpdateNetworkUI
function MarketSync.UpdateNetworkUI(txRate, rxRate, statusText)
    if originalUpdateUI then originalUpdateUI(txRate, rxRate, statusText) end
    if not MonitorFrame or not MonitorFrame:IsShown() then return end
    
    MonitorFrame.txLabel:SetText(string.format("|cffff8800Tx: %d msgs/s|r", txRate))
    MonitorFrame.rxLabel:SetText(string.format("|cff00ff00Rx: %d msgs/s|r", rxRate))
    
    if statusText then
        MonitorFrame.queueLabel:SetText(statusText)
    elseif txRate > 0 or rxRate > 0 then
        MonitorFrame.queueLabel:SetText("|cff00ff00Sync Active|r")
    else
        MonitorFrame.queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
    end
end

-- Function to add log entries
function MarketSync.LogNetworkEvent(msg)
    local formattedMsg = date("%H:%M:%S") .. " " .. msg
    if MonitorFrame and MonitorFrame.logScroll then
        MonitorFrame.logScroll:AddMessage(formattedMsg)
    else
        table.insert(earlyNetworkLogs, formattedMsg)
        if #earlyNetworkLogs > 200 then table.remove(earlyNetworkLogs, 1) end
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
            MarketSync.SwarmPeers[user].status = "Idle"
            MarketSync.SwarmPeers[user].time = time()
        end
    end
    
    if not MonitorFrame or not MonitorFrame:IsShown() then return end
    
    MonitorFrame.swarmText:Clear()
    local now = time()
    
    local myName = UnitName("player")
    if myName and not MarketSync.SwarmPeers[myName] then
        MarketSync.SwarmPeers[myName] = { status = "Idle", time = now }
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
    
    -- Priority Weights: New Data (Ready) > Active (Sending/Receiving) > Waiting > Idle
    local weights = {
        ["Ready"] = 5,
        ["Sending"] = 4,
        ["Receiving"] = 3,
        ["Waiting"] = 2,
        ["Idle"] = 1
    }
    
    table.sort(sortedPeers, function(a, b)
        local wA = weights[a.status] or 0
        local wB = weights[b.status] or 0
        if wA ~= wB then
            return wA > wB -- Higher weight first
        end
        return a.name < b.name -- Alphabetical tie breaker
    end)
    
    local count = 0
    for _, peerInfo in ipairs(sortedPeers) do
        local color = "|cff888888" -- Idle grey
        if peerInfo.status == "Sending" then color = "|cff00ff00"
        elseif peerInfo.status == "Waiting" then color = "|cffff8800"
        elseif peerInfo.status == "Receiving" then color = "|cff00ffff"
        elseif peerInfo.status == "Ready" then color = "|cffffffff" end
        
        MonitorFrame.swarmText:AddMessage(peerInfo.name .. ": " .. color .. peerInfo.status .. "|r")
        count = count + 1
    end
    
    if count == 0 then MonitorFrame.swarmText:AddMessage("No active peers.") end
end
