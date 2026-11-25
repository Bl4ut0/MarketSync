-- =============================================================
-- MarketSync - Unified Diagnostics & Administration Window
-- Native PortraitFrameTemplate / Legacy Auction House shell
-- Hosting Task Manager, Rate Limiter, Network & Swarm, and Data Pack
-- =============================================================

local ADDON_NAME = "MarketSync"
local MarketSync = _G.MarketSync

local DiagnosticsFrame = nil
local MonitorFrame = nil
local TaskManagerFrame = nil
local RateMonitorFrame = nil
local DataPackFrame = nil
local activeDiagTab = nil

local earlyCacheLogs = {}
local earlyNetworkLogs = {}
local RenderSwarmUI
local RefreshTaskManager
local RefreshDataPackTab
local monitorRefreshPending = false

local function ScheduleMonitorRefresh()
    if monitorRefreshPending or not MonitorFrame or not MonitorFrame:IsShown() then return end
    if not C_Timer or not C_Timer.After then return end
    monitorRefreshPending = true
    C_Timer.After(0.2, function()
        monitorRefreshPending = false
        if not MonitorFrame or not MonitorFrame:IsShown() then return end
        if RenderSwarmUI then RenderSwarmUI() end
        -- Bound both retained history and display work; hidden monitors only buffer.
        for _, stream in ipairs({
            { earlyNetworkLogs, MonitorFrame.logScroll },
            { earlyCacheLogs, MonitorFrame.cacheScroll },
        }) do
            for i = 1, math.min(20, #stream[1]) do
                stream[2]:AddMessage(table.remove(stream[1], 1))
            end
        end
        if #earlyNetworkLogs > 0 or #earlyCacheLogs > 0 then ScheduleMonitorRefresh() end
    end)
end

local function QueueMonitorLog(queue, message)
    queue[#queue + 1] = message
    if #queue > 500 then table.remove(queue, 1) end
    ScheduleMonitorRefresh()
end

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

function MarketSync.LogCacheEvent(msg)
    local timestamp = date("%H:%M:%S")
    local formattedMsg = string.format("[%s] %s", timestamp, msg)
    QueueMonitorLog(earlyCacheLogs, formattedMsg)
end

function MarketSync.LogNetworkEvent(msg)
    if IsCacheLogMessage(msg) then
        if MarketSync.LogCacheEvent then
            MarketSync.LogCacheEvent(msg)
        end
        return
    end
    local formattedMsg = date("%H:%M:%S") .. " " .. msg
    QueueMonitorLog(earlyNetworkLogs, formattedMsg)
end

-- ================================================================
-- SWARM TRACKING LOGIC
-- ================================================================
MarketSync.SwarmPeers = {}

local TRANSIENT_SWARM_STATES = {
    ["Electing Sync Source"] = true,
    ["Awaiting Data"] = true,
    ["Awaiting Neutral Data"] = true,
    ["Receiving"] = true,
    ["Receiving Neutral"] = true,
    ["Sending"] = true,
    ["Sending Neutral"] = true,
    ["Observing Sync"] = true,
    ["Throttled"] = true,
}

local function NormalizeSwarmPeerKey(name)
    return string.lower(tostring(name or "")):gsub("[%s%-]+", "")
end

local function CanonicalizeSwarmUser(user)
    if not user or user == "" then return nil, false end
    local raw = tostring(user)
    if MarketSync.StripKnownRealmSuffix then
        raw = select(1, MarketSync.StripKnownRealmSuffix(raw))
    else
        local base, suffix = raw:match("^(.+)%-([^%-]+)$")
        local localRealm = MarketSync.myRealm
            or (type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName())
            or (type(GetRealmName) == "function" and GetRealmName())
        if base and suffix and localRealm and localRealm ~= ""
            and (string.lower(suffix) == string.lower(localRealm)
                or (MarketSync.IsSameSyncRealm and MarketSync.IsSameSyncRealm(suffix, localRealm))) then
            raw = base
        end
    end

    local isLocal = MarketSync.IsLocalSyncIdentity and MarketSync.IsLocalSyncIdentity(raw) or false
    if isLocal then
        -- If passed a hyphenated First-Last (e.g. "Blauto-Theblind"), convert to the clean space-separated display name
        if raw:find("-", 1, true) and MarketSync.GetLocalPlayerDisplayName then
            raw = MarketSync.GetLocalPlayerDisplayName()
        end
    end
    return raw, isLocal
end

function MarketSync.UpdateSwarmUI(user, status)
    if user then
        local canonical, isLocal = CanonicalizeSwarmUser(user)
        if canonical and canonical ~= "" then
            local normTarget = NormalizeSwarmPeerKey(canonical)
            local existingKey = nil
            for peerKey in pairs(MarketSync.SwarmPeers) do
                local peerIsLocal = isLocal and MarketSync.IsLocalSyncIdentity and MarketSync.IsLocalSyncIdentity(peerKey)
                local sameNormalized = NormalizeSwarmPeerKey(peerKey) == normTarget
                if peerIsLocal or sameNormalized then
                    if not existingKey or peerKey == canonical or (#peerKey > #existingKey and not peerKey:find("-", 1, true)) then
                        existingKey = peerKey
                    end
                end
            end

            if status then
                -- Remove any duplicate alias keys for this same player/peer before writing
                for peerKey in pairs(MarketSync.SwarmPeers) do
                    local peerIsLocal = isLocal and MarketSync.IsLocalSyncIdentity and MarketSync.IsLocalSyncIdentity(peerKey)
                    local sameNormalized = NormalizeSwarmPeerKey(peerKey) == normTarget
                    if (peerIsLocal or sameNormalized) and peerKey ~= canonical then
                        MarketSync.SwarmPeers[peerKey] = nil
                    end
                end
                MarketSync.SwarmPeers[canonical] = { status = status, time = time() }
            else
                -- Instead of deleting the user when they finish, drop their existing entry to Idle
                -- and remove any duplicate alias rows.
                local targetKey = existingKey or (MarketSync.SwarmPeers[canonical] and canonical or nil)
                if targetKey then
                    local fallback = (isLocal and type(IsInGuild) == "function" and not IsInGuild()) and "No Guild" or "Idle"
                    for peerKey in pairs(MarketSync.SwarmPeers) do
                        local peerIsLocal = isLocal and MarketSync.IsLocalSyncIdentity and MarketSync.IsLocalSyncIdentity(peerKey)
                        local sameNormalized = NormalizeSwarmPeerKey(peerKey) == normTarget
                        if (peerIsLocal or sameNormalized) and peerKey ~= targetKey then
                            MarketSync.SwarmPeers[peerKey] = nil
                        end
                    end
                    MarketSync.SwarmPeers[targetKey] = { status = fallback, time = time() }
                end
            end
        end
    end

    ScheduleMonitorRefresh()
end

function MarketSync.ClearTransientSwarmStates()
    local now = time()
    local changed = false
    for peerKey, info in pairs(MarketSync.SwarmPeers) do
        if type(info) == "table" and TRANSIENT_SWARM_STATES[info.status] then
            local isLocal = MarketSync.IsLocalSyncIdentity and MarketSync.IsLocalSyncIdentity(peerKey)
            info.status = (isLocal and type(IsInGuild) == "function" and not IsInGuild()) and "No Guild" or "Idle"
            info.time = now
            changed = true
        end
    end
    if changed then
        ScheduleMonitorRefresh()
    end
end

RenderSwarmUI = function()
    if not MonitorFrame or not MonitorFrame:IsShown() then return end
    local now = time()

    local sortedPeers = {}
    for peer, info in pairs(MarketSync.SwarmPeers) do
        -- Expire silent queue entries, including our own completed activity.
        if now - info.time > 300 then
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
        if statusText == "Electing Sync Source" then return 5 end
        if statusText == "Observing Sync" then return 5 end
        if statusText == "Neutral Capture" then return 5 end
        if statusText == "Throttled" then return 4 end
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
        if statusText == "Electing Sync Source" then return "|cffffd100" end
        if statusText == "Observing Sync" then return "|cff88ccff" end
        if statusText == "Neutral Capture" then return "|cff33ccff" end
        if statusText == "Throttled" then return "|cffff8800" end
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

    local lines = {}
    for _, peerInfo in ipairs(sortedPeers) do
        local statusText = peerInfo.status or "Idle"
        local color = GetStatusColor(statusText)

        lines[#lines + 1] = peerInfo.name .. ": " .. color .. statusText .. "|r"
        if #lines >= 50 then break end
    end

    if #lines == 0 then lines[1] = "No active peers." end
    local signature = table.concat(lines, "\n")
    if MonitorFrame.swarmSignature == signature then return end
    MonitorFrame.swarmSignature = signature
    MonitorFrame.swarmText:Clear()
    for _, line in ipairs(lines) do MonitorFrame.swarmText:AddMessage(line) end
end

-- ================================================================
-- TASK MANAGER: background scanner, cache, sync, and memory state
-- ================================================================
local function FormatTaskTime(epoch)
    if not epoch or epoch <= 0 then return "Never" end
    return date("%Y-%m-%d %H:%M", epoch)
end

RefreshTaskManager = function(force)
    if not TaskManagerFrame or not TaskManagerFrame:IsShown() then return end
    local data = MarketSync.GetDiagnosticsSnapshot and MarketSync.GetDiagnosticsSnapshot(force == true) or {}
    local scan, sync, index = data.scanner or {}, data.sync or {}, data.indexes or {}
    local times, network = data.scanTimes or {}, data.network or {}
    local storage, runtime = data.storage or {}, data.runtime or {}
    local function IndexLine(label, resolved, total, pending, building, incoming)
        return string.format("%s: %d/%d ready, %d pending%s%s", label,
            resolved or 0, total or 0, pending or 0,
            building and " [building]" or "", (incoming or 0) > 0 and " [sync inbound " .. incoming .. "]" or "")
    end
    TaskManagerFrame.workText:SetText(table.concat({
        "|cffffd700Scanner|r",
        string.format("State: %s  Mode: %s  Scope: %s", scan.active and "Active" or "Idle",
            scan.full and "Full AH" or "Targeted", scan.scope or "main"),
        string.format("Progress: %d/%d  Queue: %d", scan.current or 0, scan.total or 0,
            runtime.scanQueue or 0),
        "Status: " .. tostring(scan.status or "Idle"),
        "Last full: " .. FormatTaskTime(times.full),
        "Last partial: " .. FormatTaskTime(times.partial),
        "Last neutral: " .. FormatTaskTime(times.neutral),
        "",
        "|cffffd700Search cache build|r",
        IndexLine("Personal", index.personalResolved, index.personalTotal, index.personalPending,
            index.personalBuilding),
        IndexLine("Guild", index.guildResolved, index.guildTotal, index.guildPending,
            index.guildBuilding, index.guildIncoming),
        IndexLine("Neutral", index.neutralResolved, index.neutralTotal, index.neutralPending,
            index.neutralBuilding, index.neutralIncoming),
        "",
        "|cffffd700Guild sync|r",
        string.format("Lane: %s  Scope: %s", sync.phase or "unknown", sync.scope or "none"),
        "Source: " .. tostring(sync.source or "none"),
        string.format("Outbound: %s  Inbound: %s  Throttled: %s", tostring(sync.outbound == true),
            tostring(sync.inbound == true), tostring(sync.throttled == true)),
        string.format("Control queued: %d  Sent: %d  Received: %d", sync.controlQueued or 0,
            sync.sentItems or 0, sync.receivedItems or 0),
        string.format("Transfer snapshot: %d entries  Pending frame: %d B", sync.frozenEntryCount or 0,
            sync.pendingFrameBytes or 0),
        string.format("Queued control payload: %d B", sync.queuedControlBytes or 0),
        "Wait reason: " .. tostring(sync.waitReason or "none"),
        string.format("Frame attempts: %d  Retry in %.1fs  No progress: %.1fs", sync.frameAttempts or 0, sync.retryIn or 0, sync.stalledFor or 0),
        string.format("Controls: oldest %.1fs  Expired %d  Dropped %d", sync.oldestControlAge or 0,
            (sync.queueStats or {}).expired or 0, (sync.queueStats or {}).dropped or 0),
        string.format("Own API acceptance: %d accepted / %d refused; %d retries; %d aborted transfers",
            (sync.sendStats or {}).accepted or 0, (sync.sendStats or {}).refused or 0,
            (sync.queueStats or {}).retries or 0, (sync.queueStats or {}).aborted or 0),
        string.format("Traffic: Tx %.1f/s, Rx %.1f/s; other-addon attempts %.0f B/s, %.1f API/s",
            network.txRate or 0, network.rxRate or 0, network.otherBytes or 0,
            network.otherAPIs or 0),
    }, "\n"))

    if TaskManagerFrame.workScrollContent then
        TaskManagerFrame.workScrollContent:SetHeight(math.max(1, tonumber(TaskManagerFrame.workText:GetStringHeight()) or 320))
    end
    local function FmtSize(kb)
        local n = tonumber(kb) or 0
        if n >= 1024 then
            return string.format("%.2f MB", n / 1024)
        end
        return string.format("%.1f KB", n)
    end
    local function Part(name)
        local part = storage[name] or {}
        return string.format("%d rows, ~%s", part.count or 0, FmtSize(part.estimatedKB))
    end
    local pack = data.dataPack or {}
    local memLines = {
        "|cffffd700Memory & data|r",
        "MarketSync RAM: " .. (data.addonKB and FmtSize(data.addonKB) or "unavailable"),
        "MarketSyncData RAM: " .. (data.dataPackAddonKB and FmtSize(data.dataPackAddonKB) or (pack.loaded and "unavailable" or "not loaded")),
        "MarketSyncLedger RAM: " .. (data.ledgerAddonKB and FmtSize(data.ledgerAddonKB) or "not loaded"),
        "Lua heap (all addons): " .. (data.luaHeapKB and FmtSize(data.luaHeapKB) or "unavailable"),
        "",
        "|cffffd700MarketSync tables (sampled):|r",
        "Personal scans: " .. Part("personal"),
        "Guild sync prices: " .. Part("guildPrices"),
        "DataPack active: " .. Part("dataPackActive"),
        "Guild metadata: " .. Part("guild"),
        "Neutral AH: " .. Part("neutral"),
        "Item info cache: " .. Part("itemInfo"),
        "Price history: " .. Part("history"),
        "Inventories: " .. Part("inventory"),
        "Recipes: " .. Part("recipes"),
        "Alerts: " .. Part("alerts"),
        "Storage subtotal: ~" .. FmtSize(data.storedEstimatedKB or 0),
        "Provider store*: " .. Part("provider"),
        "",
        "|cffffd700Runtime & search indexes:|r",
        string.format("Active indexes: %d rows, ~%s", runtime.indexRows or 0, FmtSize(runtime.indexEstimatedKB or 0)),
        string.format("Recent scan results: %d  Peers: %d", runtime.recentResults or 0, runtime.peers or 0),
        "",
        "|cffffd700MarketSyncData pack:|r",
    }
    if pack.loaded then
        memLines[#memLines + 1] = string.format("Flavor: %s (v%s) · %s", tostring(pack.flavor), tostring(pack.version), tostring(pack.dataDate or "—"))
        memLines[#memLines + 1] = string.format("Total: %d markets, %d items (~%s)", pack.partitionCount or 0, pack.totalRecords or 0, FmtSize(pack.estimatedKB or 0))
        for _, p in ipairs(pack.partitions or {}) do
            memLines[#memLines + 1] = string.format("· %s%s: %d (~%s)",
                p.key, p.active and " |cff40cf78[active]|r" or "", p.count or 0, FmtSize(p.estimatedKB or 0))
        end
    else
        memLines[#memLines + 1] = "Not loaded"
    end
    memLines[#memLines + 1] = ""
    memLines[#memLines + 1] = "|cff888888*Provider store may belong to Auctionator; excluded from subtotal.|r"

    TaskManagerFrame.memoryText:SetText(table.concat(memLines, "\n"))
    if TaskManagerFrame.memoryScrollContent then
        TaskManagerFrame.memoryScrollContent:SetHeight(math.max(1, tonumber(TaskManagerFrame.memoryText:GetStringHeight()) or 320))
    end
end

-- ================================================================
-- UNIFIED DIAGNOSTICS WINDOW & TAB PAGES
-- Matches MainFrame & AHSidecar native PortraitFrameTemplate / Legacy AH art
-- ================================================================
local TAB_DEFS = {
    { key = "tasks",   label = "Task Manager",    title = "MarketSync — Task Manager",         icon = "Interface\\Icons\\INV_Misc_Book_09",               width = 132 },
    { key = "rate",    label = "Rate Limiter",    title = "MarketSync — Network Rate Limiter", icon = "Interface\\Icons\\Spell_Nature_AstralRecalGroup", width = 128 },
    { key = "network", label = "Network & Swarm", title = "MarketSync — Network Monitor",      icon = "Interface\\Icons\\INV_Misc_Coin_01",               width = 148 },
    { key = "data",    label = "Data Pack",       title = "MarketSync — MarketSyncData Pack",  icon = "Interface\\Icons\\INV_Misc_Note_01",               width = 116 },
}

local function CreateBreakoutTab(parent, def)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(def.width, 24)
    tab:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    if hl.SetAllPoints then hl:SetAllPoints(tab) end
    hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    if hl.SetAlpha then hl:SetAlpha(0.25) end

    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(def.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tab.icon = icon

    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 26, 0)
    label:SetPoint("RIGHT", -6, 0)
    label:SetJustifyH("CENTER")
    label:SetText(def.label)
    tab.label = label
    tab.def = def
    return tab
end

local function CountPackRecords(records, importedOnly)
    if type(records) ~= "table" then return 0 end
    local count = 0
    for _, entry in pairs(records) do
        local isRecord = type(entry) == "table"
        local price = tonumber(isRecord and entry.m or entry)
        if price and price > 0 and (not importedOnly or (MarketSync.IsWebAuctionRecord and MarketSync.IsWebAuctionRecord(entry))) then
            count = count + 1
        end
    end
    return count
end

RefreshDataPackTab = function()
    if not DataPackFrame or not DataPackFrame:IsShown() then return end
    local realm = MarketSync.GetAuctionRealm and MarketSync.GetAuctionRealm() or ""
    local faction = MarketSync.GetPlayerMarketFaction and MarketSync.GetPlayerMarketFaction() or "Unknown"
    local marketKnown = realm ~= "" and faction ~= "Unknown"
    local marketLabel = marketKnown and (realm .. " / " .. faction) or nil
    local dataAddon = _G.MarketSyncData
    local loaded = type(dataAddon) == "table"
    local packCount, activeCount = 0, 0
    local status = "|cffff6b6bMarketSyncData is not loaded|r"
    local description = "Enable the MarketSyncData addon to supplement missing scan data with daily compiled Auction House history."
    local version, flavor, dataDate = "—", "—", "—"

    if loaded then
        version = tostring(dataAddon.version or dataAddon.Version or "—")
        flavor = tostring(dataAddon.flavor or dataAddon.Flavor or "—")
        local dates = dataAddon.dates or dataAddon.Dates
        local compiled = dataAddon.compiledAt or dataAddon.date or dataAddon.Date
        if type(dates) == "table" and #dates > 0 then
            dataDate = #dates == 1 and tostring(dates[1]) or string.format("%s to %s", dates[1], dates[#dates])
        elseif compiled then
            dataDate = tostring(compiled)
        elseif type(dataAddon.generatedAt) == "number" and dataAddon.generatedAt > 0 then
            dataDate = "Built " .. date("%Y-%m-%d", dataAddon.generatedAt)
        end

        local directPrices = dataAddon.prices or dataAddon.Prices
        local directCount = CountPackRecords(directPrices)
        packCount = directCount
        activeCount = directCount
        if type(directPrices) ~= "table" then
            if type(dataAddon.InjectIntoMarketSync) == "function" then
                pcall(dataAddon.InjectIntoMarketSync)
            end
            if type(dataAddon.GetCurrentMarketPrices) == "function" then
                local prices, label = dataAddon.GetCurrentMarketPrices()
                marketLabel = label
                marketKnown = label ~= nil
                packCount = CountPackRecords(prices)
            elseif marketKnown and type(_G.MarketSyncDataDB) == "table" then
                local markets = _G.MarketSyncDataDB
                local normalized = MarketSync.NormalizeSyncRealm and MarketSync.NormalizeSyncRealm(realm)
                local prices = markets[realm .. "@" .. faction] or (normalized and markets[normalized .. "@" .. faction])
                packCount = CountPackRecords(prices)
            end
            if marketKnown and MarketSync.GetRealmDB then
                activeCount = CountPackRecords(MarketSync.GetRealmDB().GuildData, true)
            end
        end

        local ingested = (dataAddon.importedMarket ~= nil)
        if activeCount > 0 then
            status = "|cff40cf78Connected|r"
            description = string.format(
                "Connected to %s — supplementing %s missing items (%s already covered by in-game scans).",
                tostring(marketLabel or "current market"),
                (BreakUpLargeNumbers or tostring)(activeCount),
                (BreakUpLargeNumbers or tostring)(math.max(0, packCount - activeCount))
            )
        elseif packCount > 0 and ingested then
            status = "|cff40cf78Connected|r"
            description = string.format(
                "Connected to %s — all %s pack items are currently covered by in-game scans; DataPack is standing by for unscanned items.",
                tostring(marketLabel or "current market"),
                (BreakUpLargeNumbers or tostring)(packCount)
            )
        elseif packCount > 0 then
            status = "|cffffb14eLoaded|r"
            description = "The pack has prices for this market; click Refresh Status to link it to the active market."
        else
            status = "|cffffb14eLoaded|r"
            description = marketKnown and "The loaded pack contains no price records for this market." or "Current market context is unavailable."
        end
    end

    local snapshot = MarketSync.GetDiagnosticsSnapshot and MarketSync.GetDiagnosticsSnapshot() or {}
    local storage = snapshot.storage or {}
    local packDiag = snapshot.dataPack or {}
    local personalRows = (storage.personal or {}).count or 0
    local guildRows = (storage.guildPrices or storage.guild or {}).count or 0

    local function FmtSize(kb)
        local n = tonumber(kb) or 0
        if n >= 1024 then return string.format("%.2f MB", n / 1024) end
        return string.format("%.1f KB", n)
    end

    local fmt = BreakUpLargeNumbers or tostring
    DataPackFrame.Status:SetText(status)
    DataPackFrame.Description:SetText(description)
    DataPackFrame.PackRecords:SetText(fmt(packCount))
    DataPackFrame.ActiveRecords:SetText(fmt(activeCount))
    if DataPackFrame.PackMemory then
        if snapshot.dataPackAddonKB then
            DataPackFrame.PackMemory:SetText(FmtSize(snapshot.dataPackAddonKB))
        elseif loaded then
            DataPackFrame.PackMemory:SetText("~" .. FmtSize(packDiag.estimatedKB or 0))
        else
            DataPackFrame.PackMemory:SetText("0 KB")
        end
    end
    DataPackFrame.Flavor:SetText(flavor)
    DataPackFrame.Market:SetText(marketLabel or "—")
    DataPackFrame.PackVersion:SetText(version)
    DataPackFrame.DataDate:SetText(dataDate)
    DataPackFrame.SourceHierarchy:SetText(string.format(
        "|cffffd700Priority:|r 1. Personal (%s)\n2. Guild (%s)  3. DataPack (%s)",
        fmt(personalRows), fmt(guildRows), fmt(activeCount)
    ))
    if DataPackFrame.PartitionListText then
        local pLines = {}
        if loaded and #(packDiag.partitions or {}) > 0 then
            pLines[#pLines + 1] = string.format("|cffffd700Total:|r %d markets, %s items (~%s)",
                packDiag.partitionCount or 0, fmt(packDiag.totalRecords or 0), FmtSize(packDiag.estimatedKB or 0))
            pLines[#pLines + 1] = ""
            for _, p in ipairs(packDiag.partitions) do
                pLines[#pLines + 1] = string.format("%s%s  |cffaaaaaa— %s items (~%s)|r",
                    p.key, p.active and " |cff40cf78[Active]|r" or "", fmt(p.count or 0), FmtSize(p.estimatedKB or 0))
            end
        elseif loaded then
            pLines[1] = "|cff888888No partitioned market tables found in MarketSyncDataDB.|r"
        else
            pLines[1] = "|cff888888MarketSyncData is not enabled.|r"
        end
        DataPackFrame.PartitionListText:SetText(table.concat(pLines, "\n"))
        if DataPackFrame.PartitionScrollContent then
            DataPackFrame.PartitionScrollContent:SetHeight(math.max(1, tonumber(DataPackFrame.PartitionListText:GetStringHeight()) or 150))
        end
    end
end

local function BuildTaskManagerPage(parent)
    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local leftX = isLegacy and 25 or 18
    local leftW = isLegacy and 473 or 480
    local bottomY = isLegacy and 15 or 12
    local panelH = isLegacy and 338 or 344
    local page = CreateFrame("Frame", "MarketSyncTaskManagerFrame", parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    TaskManagerFrame = page

    local pageTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageTitle:SetText("MarketSync Task Manager")
    pageTitle:Hide()
    page.TitleText = pageTitle

    local workHdr = MarketSync.CreateAHColumnHeader(page, leftW, 22, "Scanner & Background Tasks", nil, true)
    workHdr:SetPoint("TOPLEFT", leftX, -66)
    local workPanel = MarketSync.CreateModernInset(page, leftX, -88, leftW, panelH, "results")

    local workScroll = CreateFrame("ScrollFrame", nil, workPanel, "UIPanelScrollFrameTemplate")
    workScroll:SetPoint("TOPLEFT", 10, -8)
    workScroll:SetPoint("BOTTOMRIGHT", -26, 8)
    local workContent = CreateFrame("Frame", nil, workScroll)
    workContent:SetSize(436, 330)
    workScroll:SetScrollChild(workContent)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(workScroll) end
    page.workScrollContent = workContent

    local workText = workContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    workText:SetPoint("TOPLEFT", 0, 0)
    workText:SetWidth(436)
    workText:SetJustifyH("LEFT")
    page.workText = workText

    local memHdr = MarketSync.CreateAHColumnHeader(page, 304, 22, "Memory & Overhead", nil, true)
    memHdr:SetPoint("TOPLEFT", 510, -66)
    local memoryPanel = MarketSync.CreateModernInset(page, 510, -88, 304, panelH, "results")

    local memoryScroll = CreateFrame("ScrollFrame", nil, memoryPanel, "UIPanelScrollFrameTemplate")
    memoryScroll:SetPoint("TOPLEFT", 10, -8)
    memoryScroll:SetPoint("BOTTOMRIGHT", -26, 8)
    local memoryContent = CreateFrame("Frame", nil, memoryScroll)
    memoryContent:SetSize(260, 330)
    memoryScroll:SetScrollChild(memoryContent)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(memoryScroll) end
    page.memoryScrollContent = memoryContent

    local memoryText = memoryContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    memoryText:SetPoint("TOPLEFT", 0, 0)
    memoryText:SetWidth(260)
    memoryText:SetJustifyH("LEFT")
    page.memoryText = memoryText

    local function Action(label, x, width, callback)
        local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        button:SetSize(width, 20)
        button:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", x, bottomY)
        button:SetText(label)
        button:SetScript("OnClick", callback)
        return button
    end
    Action("Refresh", leftX, 96, function() RefreshTaskManager(true) end)
    Action("Rebuild Index", leftX + 104, 126, function()
        if MarketSync.InvalidateIndexCache then MarketSync.InvalidateIndexCache() end
        if MarketSync.BuildSearchIndex then MarketSync.BuildSearchIndex() end
        RefreshTaskManager(true)
    end)
    Action("Print Diagnostics", leftX + 238, 146, function()
        if MarketSync.PrintDiagnosticsSnapshot then MarketSync.PrintDiagnosticsSnapshot() end
    end)

    page.elapsed = 0
    page:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 5 then
            self.elapsed = 0
            RefreshTaskManager()
        end
    end)
end

local function BuildRateMonitorPage(parent)
    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local leftX = isLegacy and 25 or 18
    local leftW = isLegacy and 375 or 382
    local bottomY = isLegacy and 15 or 12
    local panelH = isLegacy and 338 or 344
    local page = CreateFrame("Frame", "MarketSyncRateMonitorFrame", parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    RateMonitorFrame = page

    local pageTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageTitle:SetText("Network Rate Limiter")
    pageTitle:Hide()
    page.TitleText = pageTitle

    -- Left Column: Bandwidth & API Throughput
    local leftHdr = MarketSync.CreateAHColumnHeader(page, leftW, 22, "Bandwidth & API Throughput", nil, true)
    leftHdr:SetPoint("TOPLEFT", leftX, -66)
    local card1 = MarketSync.CreateModernInset(page, leftX, -88, leftW, panelH, "controls")

    local rateSub = card1:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    rateSub:SetPoint("TOPLEFT", 14, -12)
    rateSub:SetWidth(354)
    rateSub:SetJustifyH("LEFT")
    rateSub:SetText("|cff888888Local addon-message attempts, not delivered bandwidth.|r")

    local txMsgLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txMsgLabel:SetPoint("TOPLEFT", 14, -40)
    txMsgLabel:SetText("All-addon send attempts: 0.0/sec")
    page.txMsgLabel = txMsgLabel

    local rxMsgLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rxMsgLabel:SetPoint("TOPLEFT", 14, -62)
    rxMsgLabel:SetText("MarketSync received records: 0.0/sec")
    page.rxMsgLabel = rxMsgLabel

    local txByteLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txByteLabel:SetPoint("TOPLEFT", 14, -84)
    txByteLabel:SetText("Attempted payload: 0 B/s")
    page.txByteLabel = txByteLabel

    local limitLabel = card1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    limitLabel:SetPoint("TOPLEFT", 14, -106)
    limitLabel:SetText("DATA target 640 B/s; gauge reference 800 B/s")

    page.deliveryLabel = card1:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.deliveryLabel:SetPoint("TOPLEFT", 14, -128)
    page.deliveryLabel:SetText("Own API: 0.0 accepted/s · 0.0 refused/s")

    page.transportLabel = card1:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.transportLabel:SetPoint("TOPLEFT", 14, -150)
    page.transportLabel:SetWidth(354)
    page.transportLabel:SetJustifyH("LEFT")
    page.transportLabel:SetText("Other attempts: none")

    local barTrack = CreateFrame("Frame", nil, card1, "BackdropTemplate")
    barTrack:SetSize(354, 22)
    barTrack:SetPoint("TOPLEFT", 14, -188)
    barTrack:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    barTrack:SetBackdropColor(MarketSync.GetThemeColor("scrollTrack", 0.85))
    barTrack:SetBackdropBorderColor(MarketSync.GetThemeColor("border", 0.90))
    barTrack._marketSyncThemeRole = "scrollTrack"

    local rateBar = CreateFrame("StatusBar", nil, barTrack)
    rateBar:SetPoint("TOPLEFT", 2, -2)
    rateBar:SetPoint("BOTTOMRIGHT", -2, 2)
    rateBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rateBar:GetStatusBarTexture():SetHorizTile(false)
    rateBar:SetMinMaxValues(0, 800)
    rateBar:SetValue(0)
    rateBar:SetStatusBarColor(0.20, 0.85, 0.30)

    local rateBarText = rateBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rateBarText:SetPoint("CENTER", barTrack, "CENTER", 0, 0)
    rateBarText:SetText("0 B/s (0.0% of reference)")
    page.rateBar = rateBar
    page.rateBarText = rateBarText

    local measurementNote = card1:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    measurementNote:SetPoint("BOTTOMLEFT", 14, 14)
    measurementNote:SetWidth(354)
    measurementNote:SetJustifyH("LEFT")
    measurementNote:SetText("API acceptance is not delivery. Battle.net traffic is not measured. Hover rows on the right for per-channel details.")

    -- Right Column: Per-Addon / Prefix Breakdown Table
    local hdrAddon = MarketSync.CreateAHColumnHeader(page, 206, 22, "Addon / Prefix", nil, true)
    hdrAddon:SetPoint("TOPLEFT", 412, -66)

    local hdrApi = MarketSync.CreateAHColumnHeader(page, 86, 22, "API/s", nil, true)
    hdrApi:SetPoint("LEFT", hdrAddon, "RIGHT", 0, 0)

    local hdrBytes = MarketSync.CreateAHColumnHeader(page, 110, 22, "Attempt B/s", nil, true)
    hdrBytes:SetPoint("LEFT", hdrApi, "RIGHT", 0, 0)

    local card2 = MarketSync.CreateModernInset(page, 412, -88, 402, panelH, "results")

    local emptyAddons = card2:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyAddons:SetPoint("CENTER", card2, "CENTER", 0, 0)
    emptyAddons:SetText("|cff888888No active addon traffic detected.|r")
    page.emptyAddonsText = emptyAddons

    page.addonRows = {}
    page.addonLabels = {}

    for i = 1, 12 do
        local row = CreateFrame("Frame", nil, card2)
        row:SetSize(396, 26)
        row:SetPoint("TOPLEFT", 3, -(i - 1) * 27 - 4)

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 1 then
            rowBg:SetColorTexture(MarketSync.GetThemeColor("rowEven"))
        else
            rowBg:SetColorTexture(MarketSync.GetThemeColor("rowOdd"))
        end
        row.bg = rowBg

        local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", 10, 0)
        nameText:SetWidth(190)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local apiText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        apiText:SetPoint("LEFT", 206, 0)
        apiText:SetWidth(80)
        apiText:SetJustifyH("CENTER")
        row.apiText = apiText

        local byteText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        byteText:SetPoint("RIGHT", -10, 0)
        byteText:SetWidth(100)
        byteText:SetJustifyH("RIGHT")
        row.byteText = byteText

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.data or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tostring(self.data.prefix), 1, 0.82, 0)
            GameTooltip:AddLine("Send attempts only; other addons' acceptance is unknown.", 0.8, 0.8, 0.8, true)
            for kind, rate in pairs(self.data.transports or {}) do
                GameTooltip:AddLine(string.format("%s: %.1f API/s, %.0f payload B/s", kind, rate.apiRate, rate.rate))
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        row:Hide()
        page.addonRows[i] = row
        page.addonLabels[i] = nameText
    end

    local btnRules = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnRules:SetSize(156, 20)
    btnRules:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftX, bottomY)
    btnRules:SetText("Smart Bandwidth Rules")
    btnRules:SetScript("OnClick", function()
        if MarketSync.ShowSmartRulesDialog then MarketSync.ShowSmartRulesDialog() end
    end)

    local btnPeers = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnPeers:SetSize(136, 20)
    btnPeers:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftX + 164, bottomY)
    btnPeers:SetText("User Management")
    btnPeers:SetScript("OnClick", function()
        if MarketSync.ShowUserManagementDialog then MarketSync.ShowUserManagementDialog() end
    end)
end

local function BuildNetworkMonitorPage(parent)
    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local leftX = isLegacy and 25 or 18
    local leftW = isLegacy and 523 or 530
    local fullW = isLegacy and 789 or 796
    local bottomY = isLegacy and 15 or 12
    local cacheH = isLegacy and 114 or 120
    local swarmH = isLegacy and 300 or 306
    local page = CreateFrame("Frame", "MarketSyncMonitorFrame", parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    MonitorFrame = page

    local pageTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageTitle:SetText("Network Monitor & Debug Console")
    pageTitle:Hide()
    page.TitleText = pageTitle

    local statsPanel = MarketSync.CreateModernInset(page, leftX, -66, fullW, 32, "controls")

    local txLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txLabel:SetPoint("LEFT", 16, 0)
    txLabel:SetText("|cffff8800Tx: 0 items/s|r")
    page.txLabel = txLabel

    local rxLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rxLabel:SetPoint("LEFT", 186, 0)
    rxLabel:SetText("|cff00ff00Rx: 0 items/s|r")
    page.rxLabel = rxLabel

    local queueLabel = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueLabel:SetPoint("LEFT", 356, 0)
    queueLabel:SetText("|cffaaaaaaNetwork: Idle|r")
    page.queueLabel = queueLabel

    local limitBadge = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    limitBadge:SetPoint("RIGHT", -16, 0)
    limitBadge:SetText("DATA budget: 640 B/s")

    -- Network Event Log
    local logHeader = MarketSync.CreateAHColumnHeader(page, leftW, 20, "Network Event Log", nil, true)
    logHeader:SetPoint("TOPLEFT", leftX, -106)
    local logPanel = MarketSync.CreateModernInset(page, leftX, -126, leftW, 158, "results")

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
    page.logScroll = logScroll

    -- Cache Activity Stream
    local cacheHeader = MarketSync.CreateAHColumnHeader(page, leftW, 20, "Cache Processing Stream", nil, true)
    cacheHeader:SetPoint("TOPLEFT", leftX, -292)

    local btnClearCache = CreateFrame("Button", nil, cacheHeader, "UIPanelButtonTemplate")
    btnClearCache:SetSize(58, 18)
    btnClearCache:SetPoint("RIGHT", -4, 0)
    btnClearCache:SetText("Clear")
    btnClearCache:SetScript("OnClick", function()
        if page.cacheScroll then
            wipe(earlyCacheLogs)
            page.cacheScroll:Clear()
            page.cacheScroll:AddMessage("|cff888888Cache log cleared.|r")
        end
    end)

    local cachePanel = MarketSync.CreateModernInset(page, leftX, -312, leftW, cacheH, "results")

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
    page.cacheScroll = cacheScroll

    -- Swarm Queue (Right Column)
    local swarmHeader = MarketSync.CreateAHColumnHeader(page, 254, 20, "Swarm Queue", nil, true)
    swarmHeader:SetPoint("TOPLEFT", 560, -106)
    local swarmPanel = MarketSync.CreateModernInset(page, 560, -126, 254, swarmH, "results")

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
    page.swarmText = swarmText

    swarmText:AddMessage("No active peers.")
    logScroll:AddMessage("|cFF00FF00[MarketSync]|r Network Monitor Initialized. Listening for sync events...", 1, 1, 1)
    cacheScroll:AddMessage("|cFF00FF00[MarketSync]|r Cache Monitor Initialized. Ready for rebuild tasks...", 1, 1, 1)

    local btnClearNet = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnClearNet:SetSize(130, 20)
    btnClearNet:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftX, bottomY)
    btnClearNet:SetText("Clear Event Log")
    btnClearNet:SetScript("OnClick", function()
        wipe(earlyNetworkLogs)
        logScroll:Clear()
        logScroll:AddMessage("|cff888888Network log cleared.|r")
    end)

    local btnPeers = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnPeers:SetSize(136, 20)
    btnPeers:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftX + 138, bottomY)
    btnPeers:SetText("User Management")
    btnPeers:SetScript("OnClick", function()
        if MarketSync.ShowUserManagementDialog then MarketSync.ShowUserManagementDialog() end
    end)
end

local function BuildDataPackPage(parent)
    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local leftX = isLegacy and 25 or 18
    local leftW = isLegacy and 375 or 382
    local fullW = isLegacy and 789 or 796
    local card1W = isLegacy and 251 or 258
    local bottomY = isLegacy and 15 or 12
    local detailsH = isLegacy and 178 or 184
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    page:Hide()
    DataPackFrame = page

    local statusPanel = MarketSync.CreateModernInset(page, leftX, -66, fullW, 66, "controls")
    local status = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    status:SetPoint("TOPLEFT", 14, -12)
    page.Status = status
    local description = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -6)
    description:SetPoint("RIGHT", statusPanel, "RIGHT", -14, 0)
    description:SetJustifyH("LEFT")
    page.Description = description

    local function AddRecordCard(x, w, label)
        local card = MarketSync.CreateModernInset(page, x, -142, w, 74, "controls")
        local labelText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetPoint("TOPLEFT", 14, -12)
        labelText:SetText(label)
        local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        value:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -8)
        return value
    end
    page.PackRecords = AddRecordCard(leftX, card1W, "Pack records (this market)")
    page.ActiveRecords = AddRecordCard(287, 258, "Active DataPack records")
    page.PackMemory = AddRecordCard(556, 258, "DataPack RAM footprint")

    local detailsHdr = MarketSync.CreateAHColumnHeader(page, leftW, 22, "Pack Metadata & Lookup Priority", nil, true)
    detailsHdr:SetPoint("TOPLEFT", leftX, -226)
    local details = MarketSync.CreateModernInset(page, leftX, -248, leftW, detailsH, "controls")

    local function AddDetailField(x, y, label)
        local labelText = details:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetPoint("TOPLEFT", x, y)
        labelText:SetText(label)
        local value = details:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -4)
        return value
    end
    page.Flavor = AddDetailField(16, -14, "Pack flavor")
    page.Market = AddDetailField(198, -14, "Current market")
    page.PackVersion = AddDetailField(16, -62, "Pack version")
    page.DataDate = AddDetailField(198, -62, "Data dates")

    local sourceLine = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sourceLine:SetPoint("BOTTOMLEFT", 16, 14)
    sourceLine:SetPoint("RIGHT", details, "RIGHT", -16, 0)
    sourceLine:SetJustifyH("LEFT")
    page.SourceHierarchy = sourceLine

    local partHdr = MarketSync.CreateAHColumnHeader(page, 402, 22, "Market Partitions & Footprint", nil, true)
    partHdr:SetPoint("TOPLEFT", 412, -226)
    local partPanel = MarketSync.CreateModernInset(page, 412, -248, 402, detailsH, "results")
    local partScroll = CreateFrame("ScrollFrame", nil, partPanel, "UIPanelScrollFrameTemplate")
    partScroll:SetPoint("TOPLEFT", 10, -8)
    partScroll:SetPoint("BOTTOMRIGHT", -26, 8)
    local partContent = CreateFrame("Frame", nil, partScroll)
    partContent:SetSize(358, 160)
    partScroll:SetScrollChild(partContent)
    if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(partScroll) end
    page.PartitionScrollContent = partContent
    local partText = partContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    partText:SetPoint("TOPLEFT", 0, 0)
    partText:SetWidth(358)
    partText:SetJustifyH("LEFT")
    page.PartitionListText = partText

    local btnRefresh = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    btnRefresh:SetSize(120, 20)
    btnRefresh:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", leftX, bottomY)
    btnRefresh:SetText("Refresh Status")
    btnRefresh:SetScript("OnClick", RefreshDataPackTab)
end

local function ApplyDiagTabVisuals()
    if not DiagnosticsFrame then return end
    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    if DiagnosticsFrame.headerSep then
        DiagnosticsFrame.headerSep:SetColorTexture(MarketSync.GetThemeColor("headerBorder"))
    end
    for _, tab in ipairs(DiagnosticsFrame.tabButtons or {}) do
        local isSelected = tab.def.key == activeDiagTab
        tab.selected = isSelected
        if isSelected then
            tab:SetBackdropColor(MarketSync.GetThemeColor("selected"))
            tab:SetBackdropBorderColor(1, 0.82, 0, 0.95)
            tab.label:SetText("|cFFFFD100" .. tab.def.label .. "|r")
            if MarketSync.Theme and MarketSync.Theme.DecorateWarcraftWindow then
                MarketSync.Theme.DecorateWarcraftWindow(DiagnosticsFrame, tab.def.icon, tab.def.title)
            elseif DiagnosticsFrame.TitleText then
                DiagnosticsFrame.TitleText:SetText(tab.def.title)
            end
        else
            tab:SetBackdropColor(MarketSync.GetThemeColor("header"))
            if isLegacy then
                tab:SetBackdropBorderColor(0.40, 0.42, 0.45, 0.85)
            else
                tab:SetBackdropBorderColor(0.50, 0.42, 0.28, 0.85)
            end
            tab.label:SetText("|cFFB0A080" .. tab.def.label .. "|r")
        end
    end
end

local function SelectDiagnosticsTab(tabKey)
    if not DiagnosticsFrame then return end
    activeDiagTab = tabKey or "tasks"

    if TaskManagerFrame then TaskManagerFrame:Hide() end
    if RateMonitorFrame then RateMonitorFrame:Hide() end
    if MonitorFrame then MonitorFrame:Hide() end
    if DataPackFrame then DataPackFrame:Hide() end

    ApplyDiagTabVisuals()

    if activeDiagTab == "tasks" then
        if not TaskManagerFrame then BuildTaskManagerPage(DiagnosticsFrame) end
        TaskManagerFrame.elapsed = 0
        TaskManagerFrame:Show()
        RefreshTaskManager(true)
    elseif activeDiagTab == "rate" then
        if not RateMonitorFrame then BuildRateMonitorPage(DiagnosticsFrame) end
        RateMonitorFrame:Show()
    elseif activeDiagTab == "network" then
        if not MonitorFrame then BuildNetworkMonitorPage(DiagnosticsFrame) end
        MonitorFrame:Show()
        ScheduleMonitorRefresh()
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(nil, nil) end
    elseif activeDiagTab == "data" then
        if not DataPackFrame then BuildDataPackPage(DiagnosticsFrame) end
        DataPackFrame:Show()
        RefreshDataPackTab()
    end
end

local function EnsureDiagnosticsFrame()
    if DiagnosticsFrame then return DiagnosticsFrame end

    if MarketSync.Theme and MarketSync.Theme.CreateStandardWindow then
        DiagnosticsFrame = MarketSync.Theme.CreateStandardWindow(
            "MarketSyncDiagnosticsFrame",
            "MarketSync — Diagnostics",
            832,
            480,
            "Interface\\Icons\\INV_Misc_Book_09"
        )
    else
        DiagnosticsFrame = MarketSync.CreateModernDialog(
            "MarketSyncDiagnosticsFrame",
            832,
            480,
            "MarketSync — Diagnostics",
            "Interface\\Icons\\INV_Misc_Book_09"
        )
    end
    DiagnosticsFrame:SetFrameStrata("HIGH")
    MarketSync.DiagnosticsFrame = DiagnosticsFrame

    -- Breakout-style icon+label mode tabs beside the top-left portrait
    DiagnosticsFrame.tabButtons = {}
    local prevTab = nil
    for _, def in ipairs(TAB_DEFS) do
        local tab = CreateBreakoutTab(DiagnosticsFrame, def)
        if not prevTab then
            tab:SetPoint("TOPLEFT", DiagnosticsFrame, "TOPLEFT", 68, -33)
        else
            tab:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
        end
        tab:SetScript("OnClick", function()
            SelectDiagnosticsTab(def.key)
        end)
        table.insert(DiagnosticsFrame.tabButtons, tab)
        prevTab = tab
    end

    -- Subtle divider under the tab strip
    local headerSep = DiagnosticsFrame:CreateTexture(nil, "BORDER")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", DiagnosticsFrame, "TOPLEFT", 68, -60)
    headerSep:SetPoint("TOPRIGHT", DiagnosticsFrame, "TOPRIGHT", -18, -60)
    headerSep:SetColorTexture(MarketSync.GetThemeColor("headerBorder"))
    DiagnosticsFrame.headerSep = headerSep

    -- Shared bottom-right Close button
    local isLegacyDiag = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()
    local btnClose = CreateFrame("Button", nil, DiagnosticsFrame, "UIPanelButtonTemplate")
    btnClose:SetSize(88, 20)
    btnClose:SetPoint("BOTTOMRIGHT", DiagnosticsFrame, "BOTTOMRIGHT", isLegacyDiag and -16 or -18, isLegacyDiag and 15 or 12)
    btnClose:SetText("Close")
    btnClose:SetScript("OnClick", function() DiagnosticsFrame:Hide() end)

    local function OnDiagHide()
        if TaskManagerFrame then TaskManagerFrame:Hide() end
        if RateMonitorFrame then RateMonitorFrame:Hide() end
        if MonitorFrame then MonitorFrame:Hide() end
        if DataPackFrame then DataPackFrame:Hide() end
    end

    if DiagnosticsFrame.HookScript then
        DiagnosticsFrame:HookScript("OnShow", function()
            ApplyDiagTabVisuals()
        end)
        DiagnosticsFrame:HookScript("OnHide", OnDiagHide)
    else
        DiagnosticsFrame:SetScript("OnShow", ApplyDiagTabVisuals)
        DiagnosticsFrame:SetScript("OnHide", OnDiagHide)
    end

    return DiagnosticsFrame
end

function MarketSync.OpenDiagnosticsHub(tabKey)
    local hub = EnsureDiagnosticsFrame()
    local target = tabKey or activeDiagTab or "tasks"
    if hub:IsShown() and activeDiagTab == target then
        hub:Hide()
        return
    end
    hub:Show()
    SelectDiagnosticsTab(target)
end

function MarketSync.ToggleTaskManager()
    MarketSync.OpenDiagnosticsHub("tasks")
end

function MarketSync.ToggleRateMonitor()
    MarketSync.OpenDiagnosticsHub("rate")
end

function MarketSync.ToggleNetworkMonitor()
    MarketSync.OpenDiagnosticsHub("network")
end

function MarketSync.OpenDiagnosticsDataPack()
    MarketSync.OpenDiagnosticsHub("data")
end

-- ================================================================
-- NETWORK RATE LIMITER LIVE UPDATE HOOK
-- ================================================================
function MarketSync.UpdateRateMonitor(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
    if not RateMonitorFrame or not RateMonitorFrame:IsShown() then return end

    local apiRateSafe = tonumber(txAPIRate) or 0
    RateMonitorFrame.txMsgLabel:SetText(string.format("All-addon send attempts: %.1f/sec", apiRateSafe))
    RateMonitorFrame.rxMsgLabel:SetText(string.format("MarketSync received records: %.1f/sec", rxRate or 0))
    RateMonitorFrame.txByteLabel:SetText(string.format("Attempted payload: %.0f B/s", txBytesRate or 0))
    local rates = MarketSync.SyncSendRates or {}
    RateMonitorFrame.deliveryLabel:SetText(string.format("Own API: %.1f accepted/s · %.1f refused/s", rates.accepted or 0, rates.refused or 0))
    local transports = MarketSync.OtherTransportRates or {}
    local parts = {}
    for _, kind in ipairs({ "GUILD", "WHISPER", "PARTY", "RAID", "CHANNEL" }) do
        local rate = transports[kind]
        if rate and rate.apiRate > 0 then parts[#parts + 1] = string.format("%s %.1f/s", kind, rate.apiRate) end
    end
    RateMonitorFrame.transportLabel:SetText("Other attempts: " .. (#parts > 0 and table.concat(parts, " · ") or "none"))

    local bytes = txBytesRate or 0
    local usagePct = math.min(1.0, bytes / 800)
    RateMonitorFrame.rateBar:SetValue(bytes)
    if RateMonitorFrame.rateBarText then
        RateMonitorFrame.rateBarText:SetText(string.format("%.0f B/s (%.1f%% of reference)", bytes, usagePct * 100))
    end

    -- Color the progress bar smoothly: Green -> Amber -> Red
    if usagePct < 0.5 then
        RateMonitorFrame.rateBar:SetStatusBarColor(0.20, 0.85, 0.30)
    elseif usagePct < 0.8 then
        RateMonitorFrame.rateBar:SetStatusBarColor(0.95, 0.75, 0.10)
    else
        RateMonitorFrame.rateBar:SetStatusBarColor(0.95, 0.25, 0.20)
    end

    -- Update Top Addons List
    local hasAddons = false
    local maxRows = #(RateMonitorFrame.addonRows or {})
    for i = 1, maxRows do
        local row = RateMonitorFrame.addonRows and RateMonitorFrame.addonRows[i]
        local label = RateMonitorFrame.addonLabels and RateMonitorFrame.addonLabels[i]
        local data = addonRates and addonRates[i]
        if data then
            hasAddons = true
            if row then
                row.data = data
                row.nameText:SetText(string.format("%d. %s", i, tostring(data.prefix)))
                row.apiText:SetText(string.format("%.1f/s", data.apiRate or 0))
                row.byteText:SetText(string.format("%.0f B/s", data.rate or 0))
                row:Show()
            end
            if label and label ~= row.nameText then
                label:SetText(string.format("%d. %s: %.1f/sec | %.0f B/s", i, tostring(data.prefix), data.apiRate or 0, data.rate or 0))
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

if SlashCmdList then
    SLASH_MARKETSYNCDIAG1 = "/msdiag"
    SLASH_MARKETSYNCDIAG2 = "/msadmin"
    SlashCmdList["MARKETSYNCDIAG"] = function()
        MarketSync.OpenDiagnosticsHub("tasks")
    end
end
