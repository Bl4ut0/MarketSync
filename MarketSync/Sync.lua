-- =============================================================
-- MarketSync - Sync Module
-- Protocol, data merging, passive sync, bulk broadcast
-- =============================================================

local PREFIX = MarketSync.PREFIX
local DATA_PREFIXES = MarketSync.DATA_PREFIXES
local Debug = MarketSync.Debug
local IsBlocked = MarketSync.IsBlocked
local TrackSync = MarketSync.TrackSync
local FormatMoney = MarketSync.FormatMoney
local GetCurrentScanDay = MarketSync.GetCurrentScanDay

-- ================================================================
-- SYNC PROTOCOL (revision 2)
--
-- Control prefix:
--   ADV/NADV;realm;revision;records;addonVersion;scanTime;protocol;status
--   PULL/NPULL;realm;source;advertisedRevision;advertisedScanTime;sinceRevision;protocol;addonVersion
--   HOLD;session;scope
--
-- One physical data prefix (MSyncD1), sequentially framed:
--   BEGIN;session;scope;realm;baseRevision;revision;scanTime;protocol;addonVersion
--   DATA;session;sequence;scope;compactRecords
--   END;session;scope;finalSequence;recordCount;baseRevision;revision;scanTime
--
-- Scope is M (main AH) or N (neutral AH).  Only the exact advertiser named in
-- PULL may broadcast.  BEGIN/DATA/END always use one ordered stream; the other
-- registered data prefixes remain registered only so older installations fail
-- closed instead of producing "unknown prefix" noise during a rolling update.
-- ================================================================

local SYNC_PROTOCOL_REVISION = 2
local DATA_PREFIX = DATA_PREFIXES and DATA_PREFIXES[1] or PREFIX
local MAX_WIRE_BYTES = 248
local MAX_RECORD_BYTES = 185
-- At the 248-byte wire ceiling, 9 data slots plus 1 control slot every 3.5s
-- cap MarketSync at about 709 B/s: ~80% data, <=10% control, >=10% headroom
-- under the addon's documented ~800 B/s guild-channel budget.
local TX_TICK_SECONDS = 0.35
local PULL_ELECTION_MAX_MS = 4000
local PULL_CONTENTION_SECONDS = 1.5
local PULL_SOURCE_START_GRACE_SECONDS = 0.75
local GUILD_LANE_TIMEOUT_SECONDS = 35
local PEER_BASELINE_TTL_SECONDS = 360
local TX_DATA_BUDGET_BYTES_PER_SECOND = 640
local TX_OTHER_API_PAUSE_RATE = 36
local TX_HOLD_AFTER_SECONDS = 10

MarketSync.SYNC_PROTOCOL_REVISION = SYNC_PROTOCOL_REVISION
MarketSync.SyncVersionBlocked = MarketSync.SyncVersionBlocked or false

-- ================================================================
-- BASE-36 ENCODING / DECODING
-- Compresses numeric payloads by ~30% (e.g. "50000" -> "11cg")
-- Lua's tonumber(str, 36) handles decode natively.
-- ================================================================
local ToBase36 = MarketSync.ToBase36
local FromBase36 = MarketSync.FromBase36

local function ScanDayOffsetToBucket(scanDay, bucketOffset)
    return ((tonumber(scanDay) or 0) * 48) + (tonumber(bucketOffset) or 0)
end

local function BucketToScanDay(bucket)
    return math.floor((tonumber(bucket) or 0) / 48)
end

MarketSync.myRealm = nil
local myLatestScanDay = 0
local myRecentItemCount = 0
local myLatestNeutralScanDay = 0
local myRecentNeutralItemCount = 0
local pullInProgress = false
local broadcastInProgress = false
local pullRequestPending = false
local pullRequestPendingTimer = nil
local pullElectionPending = false
local pullElectionGeneration = 0
local pullContentionPending = false
local pullContentionGeneration = 0
local pullContentionCandidates = {}
local lastAdvertisementAt = 0
local lastNeutralAdvertisementAt = 0
local MIN_ADV_INTERVAL_SECONDS = 15
local PULL_REQUEST_TIMEOUT_SECONDS = 25
local ScheduleDeferredADVProcessing

-- Every client tracks the same guild-wide lane from PULL -> BEGIN -> END.  This
-- prevents a neutral and main dump (or two main dumps) from running together.
local guildLane = {
    phase = "idle",
    scope = nil,
    source = nil,
    revision = 0,
    sessionId = nil,
    timer = nil,
}

local controlQueue = {}
local outboundTransfer = nil
local txWheelPosition = 0
local txBudgetTokens = MAX_WIRE_BYTES * 2
local txBudgetUpdatedAt = GetTime()
local sessionSerial = 0
local peerBaselineCensus = { M = {}, N = {} }

MarketSync.TxCount = 0
MarketSync.RxCount = 0
MarketSync.AddonTxBytes = {}
MarketSync.AddonTxAPI = {}
MarketSync.TxBytes = 0
MarketSync.TxAPICalls = 0

-- Global hook to intercept all addons' transmission
hooksecurefunc(C_ChatInfo, "SendAddonMessage", function(prefix, text, chatType, target)
    local bytes = text and #text or 0
    MarketSync.TxBytes = (MarketSync.TxBytes or 0) + bytes
    MarketSync.TxAPICalls = (MarketSync.TxAPICalls or 0) + 1
    
    -- Accumulate bytes and API calls per-prefix (per-addon)
    if prefix then
        MarketSync.AddonTxBytes[prefix] = (MarketSync.AddonTxBytes[prefix] or 0) + bytes
        MarketSync.AddonTxAPI[prefix] = (MarketSync.AddonTxAPI[prefix] or 0) + 1
    end
end)

local function SendAddonMessage(prefix, text, chatType, target)
    -- We removed MarketSync.TxBytes counting from here because the hooksecurefunc
    -- above will catch the _SendAddonMessage call below automatically.
    C_ChatInfo.SendAddonMessage(prefix, text, chatType, target)
end

local function SetTransientBlockedState(reason)
    if not MarketSync.UpdateSwarmUI then return end
    local player = UnitName("player")
    if not player then return end
    MarketSync.UpdateSwarmUI(player, "Blocked (Busy: " .. tostring(reason or "sync") .. ")")
    C_Timer.After(2, function()
        if not MarketSync.UpdateSwarmUI then return end
        MarketSync.UpdateSwarmUI(player, nil)
    end)
end

local function GetLocalAddonVersion()
    return MarketSync.GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or "0.0.0"
end

local function CompareVersions(v1, v2)
    local function parse(version)
        local major, minor, patch = tostring(version or "0"):match("(%d+)%.(%d+)%.?(%d*)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end
    local a1, a2, a3 = parse(v1)
    local b1, b2, b3 = parse(v2)
    if a1 ~= b1 then return a1 > b1 and 1 or -1 end
    if a2 ~= b2 then return a2 > b2 and 1 or -1 end
    if a3 ~= b3 then return a3 > b3 and 1 or -1 end
    return 0
end

local function NormalizeIdentity(value)
    return string.lower(tostring(value or "")):gsub("%s+", "")
end

function MarketSync.NoteSyncPeerBaseline(scope, identity, revision)
    local census = peerBaselineCensus[scope]
    local key = NormalizeIdentity(identity)
    local numericRevision = tonumber(revision)
    if not census or key == "" or not numericRevision or numericRevision < 0 then return false end
    census[key] = {
        revision = math.floor(numericRevision),
        seenAt = time(),
    }
    return true
end

function MarketSync.ForgetSyncPeerBaseline(scope, identity)
    local census = peerBaselineCensus[scope]
    local key = NormalizeIdentity(identity)
    if not census or key == "" then return false end
    census[key] = nil
    return true
end

local function GetMinimumRecentPeerBaseline(scope, requestedRevision)
    local census = peerBaselineCensus[scope]
    local minimum = math.max(0, math.floor(tonumber(requestedRevision) or 0))
    if not census then return minimum end

    local now = time()
    for identity, entry in pairs(census) do
        if type(entry) ~= "table" or (now - (tonumber(entry.seenAt) or 0)) > PEER_BASELINE_TTL_SECONDS then
            census[identity] = nil
        else
            local revision = tonumber(entry.revision)
            if revision and revision >= 0 and revision < minimum then
                minimum = math.floor(revision)
            end
        end
    end
    return minimum
end

function MarketSync.GetLocalSyncIdentity()
    if type(UnitFullName) == "function" then
        local name, realm = UnitFullName("player")
        if name and name ~= "" then
            if realm and realm ~= "" then
                return tostring(name) .. "-" .. tostring(realm)
            end
            return tostring(name)
        end
    end
    return tostring(UnitName("player") or "Unknown")
end

function MarketSync.IsLocalSyncIdentity(identity)
    local wanted = NormalizeIdentity(identity)
    if wanted == "" then return false end
    local full = NormalizeIdentity(MarketSync.GetLocalSyncIdentity())
    local short = NormalizeIdentity(UnitName("player"))
    return wanted == full or (not wanted:find("-", 1, true) and wanted == short)
end

function MarketSync.IsPeerDataCompatible(addonVersion, protocolRevision)
    local protocol = tonumber(protocolRevision) or 0
    -- Release versions are informational.  Wire compatibility is controlled by
    -- the independently versioned protocol so patch releases can interoperate.
    return protocol == SYNC_PROTOCOL_REVISION
end

function MarketSync.NotePeerSyncVersion(addonVersion, protocolRevision, senderName)
    local localVersion = GetLocalAddonVersion()
    local protocol = tonumber(protocolRevision) or 0
    local versionCmp = CompareVersions(addonVersion, localVersion)
    local peerIsNewer = protocol > SYNC_PROTOCOL_REVISION

    if peerIsNewer and not MarketSync.SyncVersionBlocked then
        MarketSync.SyncVersionBlocked = true
        MarketSync.NewerSyncVersion = tostring(addonVersion or "unknown")
        print(string.format(
            "|cFFFF0000[MarketSync]|r Market-data sync is disabled (control messages only) because %s is running newer/incompatible sync code (v%s, protocol %d). Please update MarketSync.",
            tostring(senderName or "a guild member"), tostring(addonVersion or "unknown"), protocol))
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format(
                "|cffff0000[Version Gate]|r Data send/receive disabled locally; peer=%s v%s protocol=%d, local=v%s protocol=%d.",
                tostring(senderName or "Unknown"), tostring(addonVersion or "unknown"), protocol,
                localVersion, SYNC_PROTOCOL_REVISION))
        end
    end


    if versionCmp > 0 and protocol == SYNC_PROTOCOL_REVISION
        and MarketSync.NewerAddonVersionSeen ~= tostring(addonVersion) then
        MarketSync.NewerAddonVersionSeen = tostring(addonVersion)
        print(string.format(
            "|cFFFF8800[MarketSync]|r A newer addon release is available (v%s, seen on %s). Sync remains compatible on protocol %d.",
            tostring(addonVersion or "unknown"), tostring(senderName or "a guild member"), SYNC_PROTOCOL_REVISION))
    end

    return MarketSync.IsPeerDataCompatible(addonVersion, protocolRevision), versionCmp
end

function MarketSync.CanParticipateInData(scope)
    if MarketSync.SyncVersionBlocked then return false end
    if not MarketSyncDB then return true end
    if scope == "N" then
        return MarketSyncDB.EnableNeutralSync ~= false
    end
    return MarketSyncDB.PassiveSync ~= false
end

local function QueueControlMessage(payload, dedupeKey, priority)
    if not payload or payload == "" then return end
    if #payload > MAX_WIRE_BYTES then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format(
                "|cffff0000[Sync Error]|r Dropped oversized control frame (%d/%d bytes).",
                #payload, MAX_WIRE_BYTES))
        end
        return
    end
    if dedupeKey then
        for index = #controlQueue, 1, -1 do
            if controlQueue[index].key == dedupeKey then
                controlQueue[index].payload = payload
                return
            end
        end
    end
    local entry = { payload = payload, key = dedupeKey }
    if priority then
        table.insert(controlQueue, 1, entry)
    else
        table.insert(controlQueue, entry)
    end
end

MarketSync.QueueSyncControl = QueueControlMessage

local function CancelPullElection()
    pullElectionGeneration = pullElectionGeneration + 1
    pullElectionPending = false
end

local function CancelPullContention()
    pullContentionGeneration = pullContentionGeneration + 1
    pullContentionPending = false
    pullContentionCandidates = {}
end

local function ResetGuildLane(reason)
    if guildLane.timer then
        guildLane.timer:Cancel()
        guildLane.timer = nil
    end
    guildLane.phase = "idle"
    guildLane.scope = nil
    guildLane.source = nil
    guildLane.revision = 0
    guildLane.sessionId = nil
    pullInProgress = false
    pullRequestPending = false
    CancelPullElection()
    CancelPullContention()
    if pullRequestPendingTimer then
        pullRequestPendingTimer:Cancel()
        pullRequestPendingTimer = nil
    end
    if reason then Debug("Guild transfer lane reopened: " .. tostring(reason)) end
    if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
    ScheduleDeferredADVProcessing()
end

local function ArmGuildLaneTimeout(expectedPhase)
    if guildLane.timer then guildLane.timer:Cancel() end
    guildLane.timer = C_Timer.NewTimer(GUILD_LANE_TIMEOUT_SECONDS, function()
        guildLane.timer = nil
        if guildLane.phase ~= expectedPhase then return end
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format(
                "|cffff8800[Sync Timeout]|r %s session timed out; incomplete data was discarded and no retry was requested.",
                tostring(guildLane.scope == "N" and "Neutral" or "Main")))
        end
        if MarketSync.DiscardInboundSyncSession then
            MarketSync.DiscardInboundSyncSession(guildLane.scope, guildLane.sessionId, "timeout")
        end
        outboundTransfer = nil
        ResetGuildLane("timeout")
    end)
end

-- Global busy check so other modules can defer new sync work until active
-- send/receive sessions are fully finished.
function MarketSync.IsSyncBusy()
    return guildLane.phase ~= "idle"
        or pullInProgress
        or broadcastInProgress
        or pullRequestPending
        or pullElectionPending
        or pullContentionPending
        or outboundTransfer ~= nil
        or ((MarketSync.RxCount or 0) > 0)
end

function MarketSync.SetPullRequestPending(isPending)
    local pending = isPending and true or false

    if pullRequestPendingTimer then
        pullRequestPendingTimer:Cancel()
        pullRequestPendingTimer = nil
    end

    pullRequestPending = pending
    if not pending then
        return
    end

    pullRequestPendingTimer = C_Timer.NewTimer(PULL_REQUEST_TIMEOUT_SECONDS, function()
        pullRequestPendingTimer = nil
        if not pullRequestPending then return end
        pullRequestPending = false
        Debug("PULL request timed out waiting for first data chunk")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cffff8800[Pull Timeout]|r No data received after %ds; sync window reopened.", PULL_REQUEST_TIMEOUT_SECONDS))
        end
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), nil)
        end
        if guildLane.phase == "requested" then
            ResetGuildLane("request timeout")
        else
            ScheduleDeferredADVProcessing()
        end
    end)
end

local function IsPullCandidateBetter(left, right)
    if not right then return true end
    if left.scope ~= right.scope then
        -- Main is the high-priority logical flow. Neutral can use the lane only
        -- when no main candidate is contending for the same idle window.
        return left.scope == "M"
    end
    if left.revision ~= right.revision then return left.revision > right.revision end
    if left.scanTime ~= right.scanTime then return left.scanTime > right.scanTime end

    local leftSource = NormalizeIdentity(left.sourceIdentity)
    local rightSource = NormalizeIdentity(right.sourceIdentity)
    if leftSource ~= rightSource then return leftSource < rightSource end
    if left.sinceRevision ~= right.sinceRevision then
        -- When the exact same source was requested more than once, serve the
        -- oldest requested baseline so every recent listener can apply it.
        return left.sinceRevision < right.sinceRevision
    end
    return NormalizeIdentity(left.requesterIdentity) < NormalizeIdentity(right.requesterIdentity)
end

local function FinalizePullContention(generation)
    if generation ~= pullContentionGeneration or not pullContentionPending then return end

    local winner = nil
    for _, candidate in pairs(pullContentionCandidates) do
        if IsPullCandidateBetter(candidate, winner) then winner = candidate end
    end
    pullContentionPending = false
    pullContentionCandidates = {}
    if not winner or guildLane.phase ~= "contending" then return end

    guildLane.phase = "requested"
    guildLane.scope = winner.scope
    guildLane.source = winner.sourceIdentity
    guildLane.revision = winner.revision
    guildLane.sessionId = nil
    pullRequestPending = true
    ArmGuildLaneTimeout("requested")

    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(winner.requesterIdentity or UnitName("player"),
            winner.scope == "N" and "Awaiting Neutral Data" or "Awaiting Data")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "|cff00ffff[Lane Election]|r %s source %s won the %.1fs PULL contention window (revision %d).",
            winner.scope == "N" and "Neutral" or "Main", tostring(winner.sourceIdentity),
            PULL_CONTENTION_SECONDS, winner.revision))
    end

    if MarketSync.IsLocalSyncIdentity(winner.sourceIdentity)
        and MarketSync.CanParticipateInData(winner.scope) then
        -- Let slower listeners close the same contention window and enter the
        -- requested phase before BEGIN. This prevents an elected source from
        -- looking like an early/non-elected preemption on those clients.
        C_Timer.After(PULL_SOURCE_START_GRACE_SECONDS, function()
            if guildLane.phase ~= "requested" or guildLane.scope ~= winner.scope
                or NormalizeIdentity(guildLane.source) ~= NormalizeIdentity(winner.sourceIdentity) then
                return
            end
            local callOK, started = pcall(MarketSync.StartDirectedBroadcast, winner.scope,
                winner.sinceRevision, winner.revision, winner.scanTime,
                winner.sourceIdentity, winner.requesterIdentity)
            if not callOK and MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent("|cffff0000[Sync Error]|r Elected source failed before BEGIN: "
                    .. tostring(started))
            end
            if (not callOK or not started) and guildLane.phase == "requested" then
                -- Validation/freeze failures must not strand the elected source
                -- in a busy state. Peers retain their bounded request timeout.
                ResetGuildLane("elected source could not start")
            end
        end)
    elseif MarketSync.IsLocalSyncIdentity(winner.sourceIdentity) then
        ResetGuildLane("elected source no longer participates")
    end
end

function MarketSync.ObserveGuildPull(scope, sourceIdentity, revision, requesterIdentity,
                                     sinceRevision, advertisedScanTime)
    if scope ~= "M" and scope ~= "N" then return false end
    if not sourceIdentity or sourceIdentity == "" then return false end
    if guildLane.phase == "sending" or guildLane.phase == "receiving" then
        return false
    end
    if guildLane.phase == "requested" then
        return false
    end

    CancelPullElection()
    local candidate = {
        scope = scope,
        sourceIdentity = tostring(sourceIdentity),
        requesterIdentity = tostring(requesterIdentity or ""),
        revision = math.max(0, math.floor(tonumber(revision) or 0)),
        scanTime = math.max(0, math.floor(tonumber(advertisedScanTime) or 0)),
        sinceRevision = math.max(0, math.floor(tonumber(sinceRevision) or 0)),
    }
    local candidateKey = table.concat({ scope, NormalizeIdentity(sourceIdentity),
        NormalizeIdentity(requesterIdentity) }, "|")

    if not pullContentionPending then
        pullContentionGeneration = pullContentionGeneration + 1
        local generation = pullContentionGeneration
        pullContentionPending = true
        pullContentionCandidates = {}
        guildLane.phase = "contending"
        C_Timer.After(PULL_CONTENTION_SECONDS, function()
            FinalizePullContention(generation)
        end)
    elseif guildLane.phase ~= "contending" then
        return false
    end

    local existing = pullContentionCandidates[candidateKey]
    if not existing or IsPullCandidateBetter(candidate, existing) then
        pullContentionCandidates[candidateKey] = candidate
    end
    local current = nil
    for _, queuedCandidate in pairs(pullContentionCandidates) do
        if IsPullCandidateBetter(queuedCandidate, current) then current = queuedCandidate end
    end
    guildLane.scope = current and current.scope or scope
    guildLane.source = current and current.sourceIdentity or sourceIdentity
    guildLane.revision = current and current.revision or candidate.revision
    guildLane.sessionId = nil
    pullRequestPending = true
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(requesterIdentity or UnitName("player"), "Electing Sync Source")
    end
    return true
end

function MarketSync.AcceptInboundTransfer(scope, sessionId, sourceIdentity, revision)
    if scope ~= "M" and scope ~= "N" then return false end
    if not sessionId or sessionId == "" then return false end

    if guildLane.phase == "sending" then return false end
    if guildLane.phase == "receiving" then
        return guildLane.sessionId == sessionId
            and guildLane.scope == scope
            and NormalizeIdentity(guildLane.source) == NormalizeIdentity(sourceIdentity)
    end
    if guildLane.phase == "contending" then
        -- No candidate is elected until the bounded window closes. Accepting an
        -- early BEGIN here would let a losing source preempt the shared lane.
        return false
    end
    if guildLane.phase == "requested" then
        if guildLane.scope ~= scope
            or NormalizeIdentity(guildLane.source) ~= NormalizeIdentity(sourceIdentity)
            or (tonumber(revision) or 0) < (tonumber(guildLane.revision) or 0) then
            return false
        end
    elseif guildLane.phase ~= "idle" and guildLane.phase ~= "electing" then
        return false
    elseif MarketSync.LogNetworkEvent then
        -- Recovery case: a listener may join the guild channel or miss the lone
        -- PULL control frame yet still receive BEGIN. Observing an actual framed
        -- stream must cancel its unsent election so it cannot create a parallel
        -- dump. This never authorizes the listener to transmit.
        MarketSync.LogNetworkEvent(string.format(
            "|cffff8800[Lane Recovery]|r Accepted BEGIN from %s after its PULL was not observed locally.",
            tostring(sourceIdentity)))
    end

    CancelPullElection()
    CancelPullContention()
    guildLane.phase = "receiving"
    guildLane.scope = scope
    guildLane.source = sourceIdentity
    guildLane.revision = tonumber(revision) or 0
    guildLane.sessionId = sessionId
    pullRequestPending = false
    if pullRequestPendingTimer then pullRequestPendingTimer:Cancel(); pullRequestPendingTimer = nil end
    ArmGuildLaneTimeout("receiving")
    return true
end

function MarketSync.TouchInboundTransfer(scope, sessionId, sourceIdentity)
    if guildLane.phase ~= "receiving" then return false end
    if guildLane.scope ~= scope or guildLane.sessionId ~= sessionId then return false end
    if sourceIdentity and NormalizeIdentity(guildLane.source) ~= NormalizeIdentity(sourceIdentity) then return false end
    ArmGuildLaneTimeout("receiving")
    return true
end

function MarketSync.FinishGuildTransfer(scope, sessionId, reason)
    if guildLane.scope ~= scope then return false end
    if guildLane.sessionId and sessionId and guildLane.sessionId ~= sessionId then return false end
    if outboundTransfer and outboundTransfer.sessionId == sessionId then
        outboundTransfer = nil
    end
    ResetGuildLane(reason or "complete")
    return true
end

local function GetTxClock()
    return type(GetTime) == "function" and GetTime() or time()
end

local function RefillTxBudget(now)
    local elapsed = math.max(0, math.min(2, now - (txBudgetUpdatedAt or now)))
    txBudgetUpdatedAt = now
    local externalBytes = math.max(0, tonumber(MarketSync.OtherTxBytesRate) or 0)
    local externalAPI = math.max(0, tonumber(MarketSync.OtherTxAPIRate) or 0)
    local refillRate = math.max(0, TX_DATA_BUDGET_BYTES_PER_SECOND - externalBytes)
    if externalAPI >= TX_OTHER_API_PAUSE_RATE then refillRate = 0 end
    txBudgetTokens = math.min(MAX_WIRE_BYTES * 2, txBudgetTokens + (elapsed * refillRate))
    return refillRate
end

local function AbortOutboundTransfer(transfer, reason)
    local abortPayload = string.format("ABORT;%s;%s", transfer.sessionId, transfer.scope)
    SendAddonMessage(DATA_PREFIX, abortPayload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent("|cffff0000[Sync Error]|r Broadcast aborted: " .. tostring(reason))
    end
    outboundTransfer = nil
    ResetGuildLane("sender error")
end

local function CompleteOutboundTransfer(transfer)
    local completedScope = transfer.scope
    local completedSession = transfer.sessionId
    outboundTransfer = nil
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Complete]|r %s broadcast %s finished.",
            completedScope == "N" and "Neutral" or "Main", completedSession))
    end
    MarketSync.FinishGuildTransfer(completedScope, completedSession, "sender complete")
end

-- One transmitter ticker reserves one slot in ten for control/headroom. The
-- single active transfer borrows all other slots regardless of scope. A small
-- token budget subtracts other addons' measured traffic, pausing DATA without
-- advancing the producer. A sparse HOLD keeps an already-started receiver from
-- discarding its staging buffer during sustained external traffic pressure.
C_Timer.NewTicker(TX_TICK_SECONDS, function()
    txWheelPosition = (txWheelPosition % 10) + 1
    local isControlSlot = txWheelPosition == 10

    -- With no data dump active, control traffic should not wait for its reserved slot.
    if not outboundTransfer and guildLane.phase ~= "receiving" and #controlQueue > 0 then
        local entry = table.remove(controlQueue, 1)
        SendAddonMessage(PREFIX, entry.payload, "GUILD")
        return
    end

    if isControlSlot then
        if #controlQueue > 0 then
            local entry = table.remove(controlQueue, 1)
            SendAddonMessage(PREFIX, entry.payload, "GUILD")
        end
        return
    end

    local transfer = outboundTransfer
    if not transfer then return end
    local now = GetTxClock()
    local refillRate = RefillTxBudget(now)

    if not transfer.pendingPayload then
        local ok, payload, isFinal = coroutine.resume(transfer.producer)
        if not ok then
            AbortOutboundTransfer(transfer, payload)
            return
        end
        if not payload or payload == "" then
            AbortOutboundTransfer(transfer, "producer returned an empty frame")
            return
        end
        if #payload > MAX_WIRE_BYTES then
            AbortOutboundTransfer(transfer, string.format(
                "encoded frame exceeded wire limit (%d/%d)", #payload, MAX_WIRE_BYTES))
            return
        end
        transfer.pendingPayload = payload
        transfer.pendingFinal = isFinal and true or false
    end

    local payloadBytes = #transfer.pendingPayload
    -- BEGIN is a single small frame and must establish the receiver session
    -- promptly; otherwise a source paused before BEGIN has no session id it can
    -- heartbeat and requesters may reopen the lane. All DATA/END frames budget.
    local isBeginFrame = transfer.pendingPayload:sub(1, 6) == "BEGIN;"
    if not isBeginFrame and (refillRate <= 0 or txBudgetTokens < payloadBytes) then
        if transfer.began and (now - (transfer.lastProgressAt or now)) >= TX_HOLD_AFTER_SECONDS
            and (now - (transfer.lastHoldAt or 0)) >= TX_HOLD_AFTER_SECONDS then
            QueueControlMessage(string.format("HOLD;%s;%s", transfer.sessionId, transfer.scope),
                "HOLD:" .. transfer.sessionId, true)
            transfer.lastHoldAt = now
        end
        if not transfer.throttled and MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), "Throttled")
        end
        transfer.throttled = true
        if not MarketSync.lastThrottleLog or (time() - MarketSync.lastThrottleLog) > 5 then
            MarketSync.lastThrottleLog = time()
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format(
                    "|cffff8800[Throttled]|r Pausing DATA for other-addon load (%d msgs/s, %d B/s); staged transfer retained.",
                    tonumber(MarketSync.OtherTxAPIRate) or 0, tonumber(MarketSync.OtherTxBytesRate) or 0))
            end
        end
        return
    end

    local payload = transfer.pendingPayload
    local isFinal = transfer.pendingFinal
    transfer.pendingPayload = nil
    transfer.pendingFinal = nil
    txBudgetTokens = math.max(0, txBudgetTokens - payloadBytes)
    SendAddonMessage(DATA_PREFIX, payload, "GUILD")
    transfer.lastProgressAt = now
    if isBeginFrame then transfer.began = true end
    if transfer.throttled and MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), transfer.scope == "N" and "Sending Neutral" or "Sending")
    end
    transfer.throttled = false
    if isFinal then CompleteOutboundTransfer(transfer) end
end)

ScheduleDeferredADVProcessing = function()
    if not MarketSync.ProcessDeferredADV then return end
    C_Timer.After(0.25, function()
        if MarketSync.ProcessDeferredADV then
            MarketSync.ProcessDeferredADV()
        end
    end)
end

-- ================================================================
-- NETWORK MONITORING (Tx/Rx per second)
-- ================================================================
local lastTx, lastRx, lastTxBytes, lastTxAPI = 0, 0, 0, 0
local lastAddonBytes = {}

-- Store global rates for sync ticker throttling
MarketSync.GlobalTxAPIRate = 0
MarketSync.GlobalTxBytesRate = 0

C_Timer.NewTicker(1.0, function()
    local txRate = (MarketSync.TxCount or 0) - lastTx
    local rxRate = (MarketSync.RxCount or 0) - lastRx
    local currentTxBytes = MarketSync.TxBytes or 0
    local currentTxAPI = MarketSync.TxAPICalls or 0
    local txBytesRate = currentTxBytes - lastTxBytes
    local txAPIRate = currentTxAPI - lastTxAPI
    lastTx = MarketSync.TxCount or 0
    lastRx = MarketSync.RxCount or 0
    lastTxBytes = currentTxBytes
    lastTxAPI = currentTxAPI

    MarketSync.GlobalTxAPIRate = txAPIRate
    MarketSync.GlobalTxBytesRate = txBytesRate

    -- Calculate bytes/sec and msgs/sec for each individual addon prefix
    local addonRates = {}
    local syncBytesRate = 0
    local syncAPIRate = 0
    local safeAddonBytes = MarketSync.AddonTxBytes or {}
    local safeAddonAPI = MarketSync.AddonTxAPI or {}
    
    -- Consolidate known prefixes
    local knownPrefixes = {}
    for prefix in pairs(safeAddonBytes) do knownPrefixes[prefix] = true end
    for prefix in pairs(safeAddonAPI) do knownPrefixes[prefix] = true end

    for prefix in pairs(knownPrefixes) do
        local currentBytes = safeAddonBytes[prefix] or 0
        local currentAPI = safeAddonAPI[prefix] or 0
        
        local prevBytes = lastAddonBytes[prefix] or { bytes = 0, api = 0 }
        
        local rateBytes = currentBytes - (prevBytes.bytes or 0)
        local rateAPI = currentAPI - (prevBytes.api or 0)
        
        if rateBytes > 0 or prevBytes.bytes > 0 or rateAPI > 0 or prevBytes.api > 0 then
            table.insert(addonRates, { prefix = prefix, rate = rateBytes, apiRate = rateAPI })
        end
        if prefix == PREFIX or prefix == DATA_PREFIX then
            syncBytesRate = syncBytesRate + math.max(0, rateBytes)
            syncAPIRate = syncAPIRate + math.max(0, rateAPI)
        end
        lastAddonBytes[prefix] = { bytes = currentBytes, api = currentAPI }
    end

    -- The global hook includes MarketSync's own preceding second. Expose the
    -- external portion separately so the v2 token budget cannot pause forever
    -- merely because its own stream was close to the intended ceiling.
    MarketSync.SyncTxBytesRate = syncBytesRate
    MarketSync.SyncTxAPIRate = syncAPIRate
    MarketSync.OtherTxBytesRate = math.max(0, txBytesRate - syncBytesRate)
    MarketSync.OtherTxAPIRate = math.max(0, txAPIRate - syncAPIRate)
    
    -- Sort the addon breakdown highest to lowest (by bytes)
    table.sort(addonRates, function(a, b)
        return a.rate > b.rate
    end)

    if MarketSync.UpdateNetworkUI then
        MarketSync.UpdateNetworkUI(txRate, rxRate, txAPIRate, txBytesRate, addonRates)
    end
end)

-- ================================================================
-- LOCAL SCAN SNAPSHOT (Duplicating Personal Data)
-- ================================================================
local function MergeTimeseriesPoint(histStr, bucketOffset, price, quantity, rejectOutlier)
    histStr = type(histStr) == "string" and histStr or ""
    local offset = tonumber(bucketOffset)
    local encodedPrice = MarketSync.ToBase36(price)
    local encodedQuantity = MarketSync.ToBase36(quantity)
    local replacement = string.format("%d:%s:%s", offset, encodedPrice, encodedQuantity)
    local points = {}
    local found = false
    local changed = false
    local accepted = true

    for point in string.gmatch(histStr, "([^,]+)") do
        local oldOffset, oldPriceB36, oldQtyB36 = point:match("^(%d+):([%w%-]+):([%w%-]+)$")
        if tonumber(oldOffset) == offset then
            found = true
            local oldPrice = MarketSync.FromBase36(oldPriceB36)
            local oldQuantity = MarketSync.FromBase36(oldQtyB36)
            local isPollution = rejectOutlier and quantity <= 2 and oldPrice > 0
                and (price > (oldPrice * 3) or price < (oldPrice * 0.5))
            if isPollution then
                accepted = false
                table.insert(points, point)
            else
                table.insert(points, replacement)
                changed = changed or oldPrice ~= price or oldQuantity ~= quantity
            end
        else
            table.insert(points, point)
        end
    end

    if not found then
        table.insert(points, replacement)
        changed = true
    end
    return table.concat(points, ","), changed, accepted
end

function MarketSync.EnsureVerifiedSnapshotSchema()
    local realmDB = MarketSync.GetRealmDB()
    if tonumber(realmDB.VerifiedSnapshotSchema) == 1 then return false end

    -- Pre-RC data did not distinguish complete scans from partial searches.
    -- Preserve it for local browsing, but fail closed for outbound eligibility.
    for _, entry in pairs(realmDB.PersonalData or {}) do
        if type(entry) == "table" then
            entry.vh = nil
            entry.latestBucket = nil
        end
    end
    for _, entry in pairs(realmDB.NeutralData or {}) do
        if type(entry) == "table" then
            entry.vm = nil
            entry.vd = nil
            entry.vq = nil
        end
    end
    realmDB.LatestBucket = nil
    realmDB.SwarmTSF = nil
    realmDB.NeutralVerifiedDay = nil
    realmDB.NeutralSwarmTSF = nil
    realmDB.NeutralScanTime = nil
    realmDB.CachedScanStats = nil
    realmDB.VerifiedSnapshotSchema = 1
    return true
end

function MarketSync.SnapshotPersonalScan(options)
    local liveStore = MarketSync.Provider and MarketSync.Provider.GetLiveStore()
        or (Auctionator and Auctionator.Database and Auctionator.Database.db)
    if not liveStore then return 0, 0 end
    if not MarketSync.GetRealmDB().PersonalData then MarketSync.GetRealmDB().PersonalData = {} end

    -- Optional notification integration. Generic Auctionator DB updates are
    -- observations, not proof that a complete scan finished, so source
    -- eligibility advances only when the FullScan completion path explicitly
    -- passes { authoritative = true }.
    local evaluateChanges = options == true or type(options) == "function"
        or (type(options) == "table" and options.evaluateNotifications == true)
    local authoritative = type(options) == "table" and options.authoritative == true
    local changeCallback = type(options) == "function" and options
        or (type(options) == "table" and options.onPriceChanged)
    local exactKeys = type(options) == "table" and options.exactKeys == true
        and type(options.keys) == "table"
    local source = exactKeys and options.keys or liveStore
    
    local today = MarketSync.GetCurrentScanDay()
    local todayStr = tostring(today)
    local bucketID = MarketSync.GetCurrentBucket()
    local bucketOffset = bucketID % 48
    if bucketOffset < 0 or bucketOffset >= 48 then
        bucketOffset = math.max(0, math.min(47, bucketOffset))
    end
    local pData = MarketSync.GetRealmDB().PersonalData
    
    local count = 0
    local todayCount = 0
    local skipped = 0
    local changedCount = 0
    
    for dbKey, sourceValue in pairs(source) do
        local data = exactKeys and liveStore[dbKey] or sourceValue
        if type(data) == "table" then
            local hasValidID = false
            if type(dbKey) == "number" or type(dbKey) == "string" then
                hasValidID = true
            end
            
            local priceVal = tonumber(data.m) or (data.latest and data.latest.complete and tonumber(data.latest.minUnitPrice)) or 0
            if hasValidID and priceVal > 0 then
                local lastSeenDay = 0
                if data.h then
                    for dayStr in pairs(data.h) do
                        local d = tonumber(dayStr)
                        if d and d > lastSeenDay then lastSeenDay = d end
                    end
                end
                
                if not pData[dbKey] then pData[dbKey] = { m = 0, d = 0, h = {} } end
                local entry = pData[dbKey]
                if not entry.h then entry.h = {} end
                local previousObservedPrice = tonumber(entry.m) or 0
                local observedPrice = priceVal
                local observedPriceChanged = previousObservedPrice ~= observedPrice

                entry.m = observedPrice
                entry.d = lastSeenDay > 0 and lastSeenDay or today
                if exactKeys or data.latest then entry.observedAt = (data.latest and data.latest.seenAt) or time() end
                
                -- Only write Timeseries buckets for data seen today
                if lastSeenDay == today then
                    local qty = 0
                    if data.a and data.a[todayStr] then qty = tonumber(data.a[todayStr]) or 0 end
                    
                    local histStr, historyChanged, accepted = MergeTimeseriesPoint(
                        entry.h[todayStr], bucketOffset, observedPrice, qty, true)
                    entry.h[todayStr] = histStr

                    if observedPriceChanged or historyChanged then
                        changedCount = changedCount + 1
                    end
                    -- Alert on the exact observed SetPrice change even when the
                    -- history pollution filter intentionally rejects that point.
                    if observedPriceChanged and evaluateChanges then
                        local evaluator = changeCallback or MarketSync.EvaluateNotificationsForRecord
                        if evaluator then
                            local ok, err = pcall(evaluator, dbKey, observedPrice, "main", "Personal")
                            if not ok then Debug("Personal scan notification evaluation failed: " .. tostring(err)) end
                        end
                    end
                    
                    if authoritative then
                        entry.vh = entry.vh or {}
                        if accepted then
                            entry.vh[todayStr] = select(1, MergeTimeseriesPoint(
                                entry.vh[todayStr], bucketOffset, observedPrice, qty, false))
                        end
                        if not entry.latestBucket or bucketID > entry.latestBucket then
                            entry.latestBucket = bucketID
                        end

                        if not MarketSync.GetRealmDB().LatestBucket or bucketID > MarketSync.GetRealmDB().LatestBucket then
                            MarketSync.GetRealmDB().LatestBucket = bucketID
                        end
                    end
                    todayCount = todayCount + 1
                end
                count = count + 1
            else
                skipped = skipped + 1
            end
        end
    end
    
    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Synchronized " .. count .. " items into Personal Timeseries Array. (" .. skipped .. " skipped)")
    end
    
    return count, todayCount, changedCount
end

-- ================================================================
-- SWARM BUCKET HELPERS
-- ================================================================
function MarketSync.GetMyLatestBucket()
    if MarketSyncDB and MarketSync.GetRealmDB().LatestBucket then
        return MarketSync.GetRealmDB().LatestBucket
    end
    
    local pData = MarketSync.GetRealmDB().PersonalData
    if not pData then return 0 end
    
    local best = 0
    for dbKey, data in pairs(pData) do
        if data.latestBucket and data.latestBucket > best then
            best = data.latestBucket
        end
    end
    
    if MarketSyncDB then
        MarketSync.GetRealmDB().LatestBucket = best
    end
    return best
end

function MarketSync.CountRecentItemsBucket(sinceBucket)
    local pData = MarketSync.GetRealmDB().PersonalData
    if not pData then return 0 end
    
    local count = 0
    for dbKey, data in pairs(pData) do
        if data.latestBucket and data.latestBucket >= sinceBucket then
            count = count + 1
        end
    end
    return count
end

function MarketSync.GetTotalPersonalItemCount()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if not realmDB or not realmDB.PersonalData then return 0 end
    local count = 0
    for _ in pairs(realmDB.PersonalData) do
        count = count + 1
    end
    return count
end

-- CountRecentItems was replaced by CountRecentItemsBucket above for Personal Data.
function MarketSync.GetMyLatestScanDay()
    local pData = MarketSync.GetRealmDB().PersonalData
    if not pData then return 0 end
    
    local best = 0
    for dbKey, data in pairs(pData) do
        if type(data) == "table" then
            local d = tonumber(data.d) or 0
            if d > best then best = d end
        end
    end
    return best
end

function MarketSync.GetMyLatestNeutralScanDay()
    local realmDB = MarketSync.GetRealmDB()
    -- The realm marker advances only after an exact local FullScan or complete
    -- protocol-2 commit. Never infer global freshness from observed `d` or from
    -- an entry written before its enclosing scan transaction completed.
    return math.max(0, tonumber(realmDB.NeutralVerifiedDay) or 0)
end

function MarketSync.CountNeutralRecentItems(sinceDay)
    local realmDB = MarketSync.GetRealmDB()
    local verifiedDay = math.max(0, tonumber(realmDB.NeutralVerifiedDay) or 0)
    if verifiedDay <= 0 or verifiedDay ~= (tonumber(sinceDay) or 0) then return 0 end
    local count = 0
    for _, data in pairs(realmDB.NeutralData or {}) do
        if type(data) == "table" then
            local d = tonumber(data.vd) or 0
            local price = tonumber(data.vm) or 0
            if d == verifiedDay and price > 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- ================================================================
-- SEND FUNCTIONS
-- ================================================================
function MarketSync.CanSync()
    if not IsInGuild() then return false end
    if not MarketSyncDB then return true end
    if not MarketSyncDB.AllowSyncInCombat and InCombatLockdown and InCombatLockdown() then return false end
    
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance then
            if instanceType == "raid" and not MarketSyncDB.AllowSyncInRaid then return false end
            if instanceType == "party" and not MarketSyncDB.AllowSyncInDungeon then return false end
            if instanceType == "pvp" and not MarketSyncDB.AllowSyncInPvP then return false end
            if instanceType == "arena" and not MarketSyncDB.AllowSyncInArena then return false end
        end
    end
    return true
end

function MarketSync.SendAdvertisement()
    if not MarketSync.CanSync() then return end
    -- Suppress ADV while actively receiving or waiting for data
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        Debug("ADV suppressed: sync session is active")
        return
    end
    local now = time()
    if (now - (lastAdvertisementAt or 0)) < MIN_ADV_INTERVAL_SECONDS then
        Debug("ADV throttled: minimum interval not reached")
        return
    end

    -- Suppress ADV while the Auction House is actively open (e.g. running an Auctionator scan)
    if MarketSync.IsAuctionHouseOpen then
        Debug("ADV suppressed: Auction House is currently open")
        return
    end
    -- Instead of entirely suppressing ADV when PassiveSync is off, we send a "Disabled" heartbeat.
    local isDisabled = (MarketSyncDB and MarketSyncDB.PassiveSync == false)

    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    myLatestScanDay = MarketSync.GetMyLatestBucket()
    myRecentItemCount = MarketSync.CountRecentItemsBucket(myLatestScanDay)
    
    local localVersion = MarketSync.GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or "0.0.0"
    
    if isDisabled then
        -- Send a heartbeat with TSF literally set to "DISABLED"
        local payload = string.format("ADV;%s;0;0;%s;DISABLED", MarketSync.myRealm, localVersion)
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastAdvertisementAt = now
        -- Update our own UI to show disabled state too
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Disabled") end
    elseif myLatestScanDay > 0 and myRecentItemCount > 0 then
        local myScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().SwarmTSF) or 0
        local payload = string.format("ADV;%s;%d;%d;%s;%s", MarketSync.myRealm, myLatestScanDay, myRecentItemCount, localVersion, tostring(myScanTime))
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastAdvertisementAt = now
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ffff[ADV]|r to Guild (Bucket %d, %d items, TSF: %d, v%s)", myLatestScanDay, myRecentItemCount, myScanTime, localVersion))
        end
        Debug("Sent ADV: realm=" .. MarketSync.myRealm .. " bucket=" .. myLatestScanDay .. " items=" .. myRecentItemCount .. " tsf=" .. myScanTime .. " v=" .. localVersion)
    end
end

function MarketSync.SendNeutralAdvertisement()
    if not MarketSync.CanSync() then return end
    -- Suppress NADV while actively receiving or waiting for data
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        Debug("NADV suppressed: sync session is active")
        return
    end

    -- Share the same throttle window as main ADV to respect guild channel limits.
    local now = time()
    if (now - (lastNeutralAdvertisementAt or 0)) < MIN_ADV_INTERVAL_SECONDS then
        return
    end

    if MarketSync.IsAuctionHouseOpen then
        return
    end

    local isDisabled = (MarketSyncDB and MarketSyncDB.EnableNeutralSync == false)

    if not MarketSync.myRealm then
        MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName()
    end

    myLatestNeutralScanDay = MarketSync.GetMyLatestNeutralScanDay()
    myRecentNeutralItemCount = MarketSync.CountNeutralRecentItems(myLatestNeutralScanDay)
    
    local localVersion = MarketSync.GetAddOnMetadata(MarketSync.ADDON_NAME, "Version") or "0.0.0"

    if isDisabled then
        local payload = string.format("NADV;%s;0;0;%s;DISABLED", MarketSync.myRealm, localVersion)
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastNeutralAdvertisementAt = now
        -- Update our own UI to show disabled state too for neutral
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Disabled") end
    elseif myLatestNeutralScanDay > 0 and myRecentNeutralItemCount > 0 then
        local neutralTSF = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().NeutralSwarmTSF) or 0
        local payload = string.format("NADV;%s;%d;%d;%s;%s", MarketSync.myRealm, myLatestNeutralScanDay, myRecentNeutralItemCount, localVersion, tostring(neutralTSF))
        SendAddonMessage(PREFIX, payload, "GUILD")
        lastNeutralAdvertisementAt = now

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ccff[NADV]|r to Guild (Day %d, %d items, TSF: %d, v%s)", myLatestNeutralScanDay, myRecentNeutralItemCount, neutralTSF, localVersion))
        end
    end
end

function MarketSync.SendPullRequest(sinceBucket)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent("|cffaaaaaa[Swarm]|r Pull request skipped: sync system is busy.")
        end
        SetTransientBlockedState("send/receive active")
        return
    end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("PULL;%s;%d", MarketSync.myRealm, sinceBucket)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.SetPullRequestPending then
        MarketSync.SetPullRequestPending(true)
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Awaiting Data")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cffff8800[PULL]|r to Guild (Since Bucket %d)", sinceBucket))
    end
    Debug("Sent PULL: realm=" .. MarketSync.myRealm .. " sinceBucket=" .. sinceBucket)
end

function MarketSync.SendNeutralPullRequest(sinceDay)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent("|cffaaaaaa[Neutral]|r Pull request skipped: sync system is busy.")
        end
        SetTransientBlockedState("send/receive active")
        return
    end

    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("NPULL;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.SetPullRequestPending then
        MarketSync.SetPullRequestPending(true)
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Awaiting Neutral Data")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ccff[NPULL]|r to Guild (Since Day %d)", sinceDay))
    end
end

function MarketSync.SendSyncRequest(itemLink)
    if IsInGuild() then
        SendAddonMessage(PREFIX, "REQ;" .. itemLink, "GUILD")
    end
end

function MarketSync.SendSyncResponse(itemLink, price, day, quantity, channel, target)
    -- Respect Smart Rules for guild traffic (combat/instance suppression).
    if channel == "GUILD" and MarketSync.CanSync and not MarketSync.CanSync() then
        return
    end
    quantity = quantity or 0
    local payload = string.format("RES;%s;%d;%d;%d", itemLink, price, day, quantity)
    SendAddonMessage(PREFIX, payload, channel, target)
    MarketSync.TxCount = MarketSync.TxCount + 1
end

function MarketSync.SendBulkSyncResponse(chunkBuffer, dataPrefix, channel, target)
    local payload = "BRES;" .. chunkBuffer
    SendAddonMessage(dataPrefix, payload, channel, target)
end

-- ================================================================
-- SWARM COORDINATOR (PULL Queuing & Throttled Responses)
-- ================================================================
MarketSync.PullQueue = {}

function MarketSync.SendPullAccept(sinceDay)
    if not MarketSync.CanSync() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("ACCEPT;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ff00[ACCEPT]|r to Guild (Claiming PULL for Day %d)", sinceDay))
    end
end

function MarketSync.RegisterPullAccept(sinceDay, senderName)
    SetClaim(MarketSync.PullQueue, sinceDay, senderName)
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ff00[Swarm]|r %s claimed PULL for Day %d", senderName, sinceDay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(senderName, "Sending")
    end
end

function MarketSync.SendNeutralPullAccept(sinceDay)
    if not MarketSync.CanSync() then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
    local payload = string.format("NACCEPT;%s;%d", MarketSync.myRealm, sinceDay)
    SendAddonMessage(PREFIX, payload, "GUILD")
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("Outgoing |cff00ccff[NACCEPT]|r to Guild (Claiming neutral pull for Day %d)", sinceDay))
    end
end

function MarketSync.RegisterNeutralPullAccept(sinceDay, senderName)
    SetClaim(neutralPullQueue, sinceDay, senderName)
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r %s claimed NPULL for Day %d", senderName, sinceDay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(senderName, "Sending Neutral")
    end
end

function MarketSync.SchedulePullResponse(sinceDay, requester)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r Ignoring PULL from %s while another sync blast is active.", requester or "unknown"))
        end
        SetTransientBlockedState("send/receive active")
        return
    end

    local delay = math.random() * 8.0 -- 0.0 to 8.0 seconds for large guilds
    
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cffff8800[Swarm]|r Queued PULL from %s. Waiting %.1fs for consensus...", requester, delay))
    end
    
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Waiting")
    end

    C_Timer.After(delay, function()
        -- Re-check Smart Rules at execution time (state may have changed during delay).
        if not MarketSync.CanSync() then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r Skipped PULL response for %s (Smart Rules currently blocking sync).", requester or "unknown"))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            end
            return
        end

        -- Re-check runtime lock right before claiming/sending.
        if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r Skipped queued PULL response for %s (another sync blast became active).", requester or "unknown"))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            end
            SetTransientBlockedState("send/receive active")
            return
        end

        -- See if someone else accepted this pull
        local claimant = GetClaimantName(MarketSync.PullQueue, sinceDay)
        if claimant then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Swarm]|r %s is already fulfilling PULL (Day %d). Standing down.", claimant, sinceDay))
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil) -- remove our wait state
            end
            return 
        end
        
        -- Nobody else took it, we accept!
        MarketSync.SendPullAccept(sinceDay)
        MarketSync.RespondToPull(sinceDay, requester)
        
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), "Sending")
        end
    end)
end

function MarketSync.ScheduleNeutralPullResponse(sinceDay, requester)
    if not MarketSync.CanSync() then return end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Neutral]|r Ignoring NPULL from %s while another sync blast is active.", requester or "unknown"))
        end
        SetTransientBlockedState("send/receive active")
        return
    end

    local delay = math.random() * 8.0
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r Queued NPULL from %s. Waiting %.1fs for consensus...", requester or "unknown", delay))
    end
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), "Waiting")
    end

    C_Timer.After(delay, function()
        if not MarketSync.CanSync() then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            return
        end
        if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            SetTransientBlockedState("send/receive active")
            return
        end
        local claimant = GetClaimantName(neutralPullQueue, sinceDay)
        if claimant then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffaaaaaa[Neutral]|r %s is already fulfilling NPULL (Day %d). Standing down.", claimant, sinceDay))
            end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            return
        end

        MarketSync.SendNeutralPullAccept(sinceDay)
        MarketSync.RespondToNeutralPull(sinceDay, requester)
        if MarketSync.UpdateSwarmUI then
            MarketSync.UpdateSwarmUI(UnitName("player"), "Sending Neutral")
        end
    end)
end

function MarketSync.RespondToNeutralPull(sinceDay, requester)
    if pullInProgress then
        SetTransientBlockedState("active send")
        return
    end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        SetTransientBlockedState("send/receive active")
        return
    end
    if not MarketSync.CanSync() then return end

    local realmDB = MarketSync.GetRealmDB()
    if not realmDB or not realmDB.NeutralData then return end

    pullInProgress = true
    SetClaim(neutralPullQueue, sinceDay, UnitName("player") or "Unknown")
    local MAX_PAYLOAD = 248
    local numPrefixes = #DATA_PREFIXES
    local prefixIndex = 0

    local co = coroutine.create(function()
        local sent = 0
        local scanned = 0
        local messagesSent = 0
        local buffer = ""
        local bufferCount = 0

        for dbKey, data in pairs(realmDB.NeutralData) do
            scanned = scanned + 1
            local d = tonumber(data and data.d) or 0
            if d >= sinceDay then
                local price = tonumber(data.m) or 0
                if price > 0 then
                    local qty = tonumber(data.q) or 0
                    local itemStr = tostring(dbKey) .. "_" .. ToBase36(price) .. "_" .. ToBase36(qty) .. "_" .. ToBase36(d)
                    local currentLen = string.len(buffer)
                    if currentLen > 0 and currentLen + 1 + string.len(itemStr) > MAX_PAYLOAD then
                        local dp = DATA_PREFIXES[prefixIndex]
                        SendAddonMessage(dp, "NBRES;" .. buffer, "GUILD")
                        MarketSync.TxCount = MarketSync.TxCount + bufferCount
                        sent = sent + bufferCount
                        messagesSent = messagesSent + 1
                        buffer = ""
                        bufferCount = 0
                        coroutine.yield()
                    end
                    if buffer == "" then
                        buffer = itemStr
                    else
                        buffer = buffer .. "," .. itemStr
                    end
                    bufferCount = bufferCount + 1
                end
            end
        end

        if buffer ~= "" then
            local dp = DATA_PREFIXES[prefixIndex]
            SendAddonMessage(dp, "NBRES;" .. buffer, "GUILD")
            MarketSync.TxCount = MarketSync.TxCount + bufferCount
            sent = sent + bufferCount
            messagesSent = messagesSent + 1
        end

        local neutralTSF = (realmDB and realmDB.NeutralSwarmTSF) or 0
        SendAddonMessage(PREFIX, string.format("NEND;%d;%d;%s", sent, messagesSent, tostring(neutralTSF)), "GUILD")
        ClearClaim(neutralPullQueue, sinceDay)
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ccff[Neutral]|r Sent %d neutral items in %d messages (%d scanned).", sent, messagesSent, scanned))
        end

        pullInProgress = false
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
        ScheduleDeferredADVProcessing()
    end)

    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if not MarketSync.CanSync() then
            ticker:Cancel()
            ClearClaim(neutralPullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
            return
        end

        -- GLOBAL SELF-THROTTLING
        -- If other addons (like Attune) are bursting, skip our tick to prevet disconnect
        local apiLimit = 40
        local byteLimit = 750
        if (MarketSync.GlobalTxAPIRate or 0) > apiLimit or (MarketSync.GlobalTxBytesRate or 0) > byteLimit then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Throttled") end
            return -- Skip this tick, wait for rates to drop
        end

        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            ClearClaim(neutralPullQueue, sinceDay)
            pullInProgress = false
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            ScheduleDeferredADVProcessing()
            return
        end

        -- Restore status if we were throttled (only reached if coroutine is still alive)
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending Neutral") end

        prefixIndex = (prefixIndex % numPrefixes) + 1
        local ok, err = coroutine.resume(co)
        if not ok then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent("|cffff0000[Neutral Error]|r " .. tostring(err))
            end
            ticker:Cancel()
            ClearClaim(neutralPullQueue, sinceDay)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
        end
    end)
end

function MarketSync.RespondToPull(sinceBucket, requester)
    if pullInProgress then
        Debug("PULL response already in progress, ignoring request from " .. (requester or "unknown"))
        SetTransientBlockedState("active send")
        return
    end
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        Debug("RespondToPull ignored: another sync blast is active")
        SetTransientBlockedState("send/receive active")
        return
    end
    if not MarketSync.CanSync() then
        Debug("RespondToPull blocked by Smart Rules")
        return
    end
    local pData = MarketSync.GetRealmDB().PersonalData
    if not pData then return end
    
    pullInProgress = true
    SetClaim(MarketSync.PullQueue, sinceBucket, UnitName("player") or "Unknown")
    Debug("Responding to PULL from " .. (requester or "unknown") .. " (sinceBucket=" .. sinceBucket .. ")")

    local MAX_PAYLOAD = 248  -- 255 minus "BRES;" prefix (5) minus safety margin (2)
    local numPrefixes = #DATA_PREFIXES
    local prefixIndex = 0
    
    local co = coroutine.create(function()
        local sent = 0
        local scanned = 0
        local messagesSent = 0
        local buffer = ""
        local bufferCount = 0
        
        _G.MarketSyncActivePullKey = "Starting"
        local yieldCounter = 0

        -- Count total eligible items first for progress tracking
        local totalEligible = 0
        for dbKey, data in pairs(pData) do
            if data.latestBucket and data.latestBucket >= sinceBucket then
                totalEligible = totalEligible + 1
            end
        end

        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Start]|r Sending Timeseries Strings for %d items via %d parallel channels", totalEligible, numPrefixes))
        end

        local dayCutoff = math.floor(sinceBucket / 48)
        local currentScanDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or math.floor(time() / 86400)
        local hotCutoff = currentScanDay - (MarketSync.RETENTION_HOT_DAYS or 7)

        for dbKey, data in pairs(pData) do
            scanned = scanned + 1
            _G.MarketSyncActivePullKey = tostring(dbKey)
            
            local hasBucket = data.latestBucket and data.latestBucket >= sinceBucket
            local hasLegacy = not data.latestBucket and data.d and tonumber(data.d) >= dayCutoff
            if (hasBucket or hasLegacy) and data.h then
                for dayStr, histStr in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d >= dayCutoff and d >= hotCutoff and not (MarketSync.IsCompactRecord and MarketSync.IsCompactRecord(histStr)) then
                        -- Transmit natively. Replace commas with periods so we don't break BRES splitting
                        local safeHistStr = string.gsub(histStr, ",", ".")
                        local itemStr = tostring(dbKey) .. "_" .. MarketSync.ToBase36(d) .. "_" .. safeHistStr
                        
                        local currentLen = string.len(buffer)
                        if currentLen > 0 and currentLen + 1 + string.len(itemStr) > MAX_PAYLOAD then
                            local dp = DATA_PREFIXES[prefixIndex]
                            MarketSync.SendBulkSyncResponse(buffer, dp, "GUILD")
                            MarketSync.TxCount = MarketSync.TxCount + bufferCount
                            sent = sent + bufferCount
                            messagesSent = messagesSent + 1
                            buffer = ""
                            bufferCount = 0
                            yieldCounter = 0
                            
                            if sent % 100 < 16 then
                                if MarketSync.LogNetworkEvent then
                                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Checkpoint]|r Sent %d / %d items (%d msgs, %d scanned)", sent, totalEligible, messagesSent, scanned))
                                end
                            end
                            coroutine.yield()
                        end
                        
                        if buffer == "" then
                            buffer = itemStr
                        else
                            buffer = buffer .. "," .. itemStr
                        end
                        bufferCount = bufferCount + 1
                    end
                end
            end
            
            yieldCounter = yieldCounter + 1
            if yieldCounter >= 500 then
                yieldCounter = 0
                coroutine.yield()
            end
        end

        -- Flush remaining buffer
        if buffer ~= "" then
            local dp = DATA_PREFIXES[prefixIndex]
            MarketSync.SendBulkSyncResponse(buffer, dp, "GUILD")
            MarketSync.TxCount = MarketSync.TxCount + bufferCount
            sent = sent + bufferCount
            messagesSent = messagesSent + 1
        end

        Debug("PULL response complete: sent " .. sent .. " timeseries arrays in " .. messagesSent .. " messages")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("|cff00ff00[Sync Complete]|r Sent %d timeseries arrays in %d messages via %d channels. (%d items scanned)", sent, messagesSent, numPrefixes, scanned))
        end

        if requester and IsInGuild() then
            local myScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().SwarmTSF) or 0
            SendAddonMessage(PREFIX, string.format("END;%d;%d;%s", sent, messagesSent, tostring(myScanTime)), "GUILD")
        end

        ClearClaim(MarketSync.PullQueue, sinceBucket)
        pullInProgress = false
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
        ScheduleDeferredADVProcessing()
    end)

    -- Multi-prefix round-robin: 5 prefixes available
    -- Total sustained: ~5 msg/sec × ~16 items/msg = ~80 items/sec.
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if not MarketSync.CanSync() then
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent("|cffff8800[Swarm]|r PULL response paused/stopped by Smart Rules.")
            end
            if MarketSync.UpdateSwarmUI then
                MarketSync.UpdateSwarmUI(UnitName("player"), nil)
            end
            ticker:Cancel()
            ClearClaim(MarketSync.PullQueue, sinceBucket)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
            return
        end

        -- GLOBAL SELF-THROTTLING
        -- Pause sync if global traffic (including other addons) is nearing disconnect limits
        local apiLimit = 40
        local byteLimit = 750
        if (MarketSync.GlobalTxAPIRate or 0) > apiLimit or (MarketSync.GlobalTxBytesRate or 0) > byteLimit then
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Throttled") end
            -- Log only occasionally to avoid spamming the log during sustained throttling
            if not MarketSync.lastThrottleLog or (time() - MarketSync.lastThrottleLog) > 5 then
                MarketSync.lastThrottleLog = time()
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Throttled]|r Global server load is too high (%d msgs/s, %d B/s); pausing sync...", MarketSync.GlobalTxAPIRate, MarketSync.GlobalTxBytesRate))
                end
            end
            return -- Skip this tick
        end

        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            ClearClaim(MarketSync.PullQueue, sinceBucket)
            pullInProgress = false
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            ScheduleDeferredADVProcessing()
            return
        end

        -- Restore status if we were throttled (only reached if coroutine is still alive)
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending") end
        
        -- Advance prefix index before resuming coroutine
        -- The coroutine will use this to send its chunk
        prefixIndex = (prefixIndex % numPrefixes) + 1
        
        local ok, err = coroutine.resume(co)
        if not ok then
            local crashKey = _G.MarketSyncActivePullKey or "Unknown"
            Debug("PULL response error at key [" .. crashKey .. "]: " .. tostring(err))
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Swarm Sync halted entirely. CRASH at dbKey: %s. Err: %s", crashKey, tostring(err)))
            end
            if IsInGuild() and requester then
                SendAddonMessage(PREFIX, string.format("ERR;%s;%s", requester, crashKey), "GUILD")
            end
            ticker:Cancel()
            ClearClaim(MarketSync.PullQueue, sinceBucket)
            pullInProgress = false
            ScheduleDeferredADVProcessing()
        end
    end)
end

-- ================================================================
-- PROTOCOL 2 OVERRIDES
--
-- These definitions intentionally replace the revision-1 public entry points
-- above.  Keeping the old local implementation in this release makes the
-- migration diff reviewable, but no protocol-2 receive path invokes it and
-- unframed BRES/NBRES/RES messages are rejected in Chat.lua.
-- ================================================================

function MarketSync.SendAdvertisement()
    if not MarketSync.CanSync() then return end
    local now = time()
    if (now - (lastAdvertisementAt or 0)) < MIN_ADV_INTERVAL_SECONDS then return end
    if MarketSync.IsAuctionHouseOpen then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end

    myLatestScanDay = MarketSync.GetMyLatestBucket()
    myRecentItemCount = MarketSync.CountRecentItemsBucket(myLatestScanDay)
    local status = MarketSync.SyncVersionBlocked and "OUTDATED"
        or ((MarketSyncDB and MarketSyncDB.PassiveSync == false) and "DISABLED" or "READY")
    local scanTime = tonumber(MarketSync.GetRealmDB().SwarmTSF) or 0
    QueueControlMessage(string.format("ADV;%s;%d;%d;%s;%d;%d;%s",
        MarketSync.myRealm, status == "READY" and myLatestScanDay or 0,
        status == "READY" and myRecentItemCount or 0, GetLocalAddonVersion(),
        status == "READY" and scanTime or 0, SYNC_PROTOCOL_REVISION, status), "ADV")
    lastAdvertisementAt = now

    if MarketSync.UpdateSwarmUI and status ~= "READY" then
        MarketSync.UpdateSwarmUI(UnitName("player"), status == "OUTDATED" and "Update Required" or "Disabled")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "Outgoing |cff00ffff[ADV]|r queued (Bucket %d, %d items, TSF %d, v%s/p%d, %s).",
            myLatestScanDay, myRecentItemCount, scanTime, GetLocalAddonVersion(), SYNC_PROTOCOL_REVISION, status))
    end
end

function MarketSync.SendNeutralAdvertisement()
    if not MarketSync.CanSync() then return end
    local now = time()
    if (now - (lastNeutralAdvertisementAt or 0)) < MIN_ADV_INTERVAL_SECONDS then return end
    if MarketSync.IsAuctionHouseOpen then return end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end

    myLatestNeutralScanDay = MarketSync.GetMyLatestNeutralScanDay()
    myRecentNeutralItemCount = MarketSync.CountNeutralRecentItems(myLatestNeutralScanDay)
    local status = MarketSync.SyncVersionBlocked and "OUTDATED"
        or ((MarketSyncDB and MarketSyncDB.EnableNeutralSync == false) and "DISABLED" or "READY")
    local scanTime = tonumber(MarketSync.GetRealmDB().NeutralSwarmTSF) or 0
    QueueControlMessage(string.format("NADV;%s;%d;%d;%s;%d;%d;%s",
        MarketSync.myRealm, status == "READY" and myLatestNeutralScanDay or 0,
        status == "READY" and myRecentNeutralItemCount or 0, GetLocalAddonVersion(),
        status == "READY" and scanTime or 0, SYNC_PROTOCOL_REVISION, status), "NADV")
    lastNeutralAdvertisementAt = now

    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "Outgoing |cff00ccff[NADV]|r queued (Day %d, %d items, TSF %d, v%s/p%d, %s).",
            myLatestNeutralScanDay, myRecentNeutralItemCount, scanTime, GetLocalAddonVersion(), SYNC_PROTOCOL_REVISION, status))
    end
end

local function HashIdentity(identity)
    local value = tostring(identity or "")
    local hash = 0
    for index = 1, #value do
        hash = (hash * 33 + string.byte(value, index)) % 65521
    end
    return hash
end

local function SendDirectedPullNow(scope, sinceRevision, sourceIdentity, advertisedRevision, advertisedScanTime)
    if not MarketSync.CanSync() or not MarketSync.CanParticipateInData(scope) then
        ResetGuildLane("pull no longer allowed")
        return false
    end
    if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end

    local requesterIdentity = MarketSync.GetLocalSyncIdentity()
    if not MarketSync.ObserveGuildPull(scope, sourceIdentity, advertisedRevision,
        requesterIdentity, sinceRevision, advertisedScanTime) then
        return false
    end

    local msgType = scope == "N" and "NPULL" or "PULL"
    local pullPayload = string.format("%s;%s;%s;%d;%d;%d;%d;%s", msgType,
        MarketSync.myRealm, tostring(sourceIdentity), tonumber(advertisedRevision) or 0,
        tonumber(advertisedScanTime) or 0, tonumber(sinceRevision) or 0,
        SYNC_PROTOCOL_REVISION, GetLocalAddonVersion())

    -- When the lane is idle, send PULL immediately so all peers observe it and
    -- cancel their pending lottery timers without waiting up to 0.35s in queue.
    if not outboundTransfer and guildLane.phase ~= "receiving" then
        SendAddonMessage(PREFIX, pullPayload, "GUILD")
    else
        QueueControlMessage(pullPayload, "PULL:" .. scope, true)
    end

    MarketSync.SetPullRequestPending(true)
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), scope == "N" and "Awaiting Neutral Data" or "Awaiting Data")
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "Outgoing |cffff8800[%s]|r sent for exact source %s (advertised %d, local %d).",
            msgType, tostring(sourceIdentity), tonumber(advertisedRevision) or 0, tonumber(sinceRevision) or 0))
    end
    return true
end

function MarketSync.ScheduleDirectedPull(scope, sinceRevision, sourceIdentity, advertisedRevision, advertisedScanTime)
    if guildLane.phase ~= "idle" or outboundTransfer or pullElectionPending then return false end
    if not MarketSync.CanSync() or not MarketSync.CanParticipateInData(scope) then return false end
    if not sourceIdentity or sourceIdentity == "" then return false end

    pullElectionGeneration = pullElectionGeneration + 1
    local generation = pullElectionGeneration
    pullElectionPending = true
    guildLane.phase = "electing"
    guildLane.scope = scope
    guildLane.source = sourceIdentity
    guildLane.revision = tonumber(advertisedRevision) or 0

    -- A stable requester delay prevents hundreds of identical PULLs in a large
    -- guild. The first observed PULL cancels outstanding local lotteries; the
    -- bounded contention window resolves requests that were already in flight.
    local delay = 0.5 + ((HashIdentity(MarketSync.GetLocalSyncIdentity()) % PULL_ELECTION_MAX_MS) / 1000)
    C_Timer.After(delay, function()
        if generation ~= pullElectionGeneration or not pullElectionPending then return end
        if guildLane.phase ~= "electing" then return end
        pullElectionPending = false
        SendDirectedPullNow(scope, sinceRevision, sourceIdentity, advertisedRevision, advertisedScanTime)
    end)
    return true
end

function MarketSync.SendPullRequest(sinceBucket, sourceIdentity, advertisedRevision, advertisedScanTime)
    return MarketSync.ScheduleDirectedPull("M", sinceBucket, sourceIdentity, advertisedRevision, advertisedScanTime)
end

function MarketSync.SendNeutralPullRequest(sinceDay, sourceIdentity, advertisedRevision, advertisedScanTime)
    return MarketSync.ScheduleDirectedPull("N", sinceDay, sourceIdentity, advertisedRevision, advertisedScanTime)
end

local function EncodeDBKey(dbKey)
    if type(dbKey) == "number" then return "n" .. ToBase36(dbKey) end
    local value = tostring(dbKey or "")
    if value == "" or #value > 120 or value:find("[,;_]", 1) then return nil end
    return "s" .. value
end

local function NewSessionId()
    sessionSerial = (sessionSerial + 1) % 46656
    return ToBase36(time()) .. ToBase36(sessionSerial)
end

-- Freeze only verified outbound fields before BEGIN. Strings and scalar values
-- are immutable in Lua, so this shallow snapshot is stable for the full send
-- without cloning Auctionator's live database or its UI-only observation data.
local function FreezeTransferSource(scope, realmDB, baseRevision, revision)
    local frozen = {}
    local since = tonumber(baseRevision) or 0
    local upperRevision = tonumber(revision) or 0

    if scope == "M" then
        local dayCutoff = BucketToScanDay(since)
        local upperDay = BucketToScanDay(upperRevision)
        local currentScanDay = MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or math.floor(time() / 86400)
        local hotCutoff = currentScanDay - (MarketSync.RETENTION_HOT_DAYS or 7)
        for dbKey, data in pairs((realmDB and realmDB.PersonalData) or {}) do
            local latestBucket = tonumber(data and data.latestBucket) or 0
            local verifiedHistory = data and data.vh
            if latestBucket > 0 and latestBucket >= since and type(verifiedHistory) == "table" then
                local encodedKey = EncodeDBKey(dbKey)
                if encodedKey then
                    for dayText, history in pairs(verifiedHistory) do
                        local day = tonumber(dayText)
                        if day and day >= dayCutoff and day >= hotCutoff and day <= upperDay
                            and type(history) == "string" and history ~= ""
                            and not (MarketSync.IsCompactRecord and MarketSync.IsCompactRecord(history)) then
                            table.insert(frozen, {
                                encodedKey = encodedKey,
                                day = day,
                                history = history,
                            })
                        end
                    end
                end
            end
        end
    else
        for dbKey, data in pairs((realmDB and realmDB.NeutralData) or {}) do
            local day = tonumber(data and data.vd) or 0
            local price = tonumber(data and data.vm) or 0
            if day >= since and day <= upperRevision and price > 0 then
                local encodedKey = EncodeDBKey(dbKey)
                if encodedKey then
                    table.insert(frozen, {
                        encodedKey = encodedKey,
                        day = day,
                        price = price,
                        quantity = math.max(0, tonumber(data.vq) or 0),
                    })
                end
            end
        end
    end

    return frozen
end

local function CreateTransferProducer(sessionId, scope, baseRevision, revision, scanTime, frozenSource)
    local realm = MarketSync.myRealm or GetNormalizedRealmName() or GetRealmName() or "Unknown"
    local addonVersion = GetLocalAddonVersion()

    return coroutine.create(function()
        coroutine.yield(string.format("BEGIN;%s;%s;%s;%s;%s;%s;%d;%s", sessionId, scope, realm,
            ToBase36(baseRevision), ToBase36(revision), ToBase36(scanTime),
            SYNC_PROTOCOL_REVISION, addonVersion), false)

        local sequence = 0
        local recordCount = 0
        local buffer = ""
        local bufferedRecords = 0

        local function flush()
            if buffer == "" then return end
            sequence = sequence + 1
            local payload = string.format("DATA;%s;%s;%s;%s", sessionId, ToBase36(sequence), scope, buffer)
            if #payload > MAX_WIRE_BYTES then
                error("encoded DATA frame exceeded wire limit: " .. tostring(#payload))
            end
            MarketSync.TxCount = (MarketSync.TxCount or 0) + bufferedRecords
            buffer = ""
            bufferedRecords = 0
            coroutine.yield(payload, false)
        end

        local function appendRecord(record)
            if not record or record == "" then return end
            if #record > MAX_RECORD_BYTES then error("encoded record exceeded safe record limit") end
            local separator = buffer == "" and "" or ","
            local nextHeader = string.format("DATA;%s;%s;%s;", sessionId, ToBase36(sequence + 1), scope)
            if buffer ~= "" and (#nextHeader + #buffer + #separator + #record) > MAX_WIRE_BYTES then
                flush()
                separator = ""
            end
            buffer = buffer .. separator .. record
            bufferedRecords = bufferedRecords + 1
            recordCount = recordCount + 1
        end

        if scope == "M" then
            local since = tonumber(baseRevision) or 0
            local upperRevision = tonumber(revision) or 0
            for _, frozenRecord in ipairs(frozenSource or {}) do
                local day = frozenRecord.day
                local recordPrefix = frozenRecord.encodedKey .. "_" .. ToBase36(day) .. "_"
                local points = ""
                for bucketOffset, priceB36, qtyB36 in string.gmatch(
                    frozenRecord.history, "(%d+):([%w%-]+):([%w%-]+)") do
                    local offset = tonumber(bucketOffset)
                    local pointPrice = FromBase36(priceB36)
                    local pointQuantity = FromBase36(qtyB36)
                    local absoluteBucket = offset and ScanDayOffsetToBucket(day, offset) or -1
                    if offset and offset >= 0 and offset < 48
                        and pointPrice and pointPrice > 0 and pointQuantity and pointQuantity >= 0
                        and absoluteBucket >= since and absoluteBucket <= upperRevision then
                        local point = bucketOffset .. ":" .. ToBase36(pointPrice) .. ":" .. ToBase36(pointQuantity)
                        local candidate = points == "" and point or (points .. "." .. point)
                        if #recordPrefix + #candidate > MAX_RECORD_BYTES then
                            if points ~= "" then appendRecord(recordPrefix .. points) end
                            points = point
                        else
                            points = candidate
                        end
                    end
                end
                if points ~= "" then appendRecord(recordPrefix .. points) end
            end
        else
            for _, frozenRecord in ipairs(frozenSource or {}) do
                appendRecord(string.format("%s_%s_%s_%s", frozenRecord.encodedKey,
                    ToBase36(frozenRecord.price), ToBase36(frozenRecord.quantity),
                    ToBase36(frozenRecord.day)))
            end
        end

        flush()
        coroutine.yield(string.format("END;%s;%s;%s;%s;%s;%s;%s", sessionId, scope,
            ToBase36(sequence), ToBase36(recordCount), ToBase36(baseRevision),
            ToBase36(revision), ToBase36(scanTime)), true)
    end)
end

function MarketSync.StartDirectedBroadcast(scope, sinceRevision, advertisedRevision, advertisedScanTime, sourceIdentity, requesterIdentity)
    if outboundTransfer or guildLane.phase == "sending" or guildLane.phase == "receiving" then return false end
    if not MarketSync.CanSync() or not MarketSync.CanParticipateInData(scope) then return false end
    if not MarketSync.IsLocalSyncIdentity(sourceIdentity) then return false end

    local realmDB = MarketSync.GetRealmDB()
    local revision = scope == "N" and MarketSync.GetMyLatestNeutralScanDay() or MarketSync.GetMyLatestBucket()
    local scanTime = scope == "N" and (tonumber(realmDB.NeutralSwarmTSF) or 0) or (tonumber(realmDB.SwarmTSF) or 0)
    if revision < (tonumber(advertisedRevision) or 0) then return false end
    if revision == (tonumber(advertisedRevision) or 0) and scanTime < (tonumber(advertisedScanTime) or 0) then return false end

    local requestedBase = math.max(0, math.floor(tonumber(sinceRevision) or 0))
    requestedBase = math.min(requestedBase, revision)
    -- READY advertisements double as a bounded, low-rate baseline census. The
    -- exact source widens the guild delta to the oldest recently seen listener;
    -- a missed ADV is still protected by the receiver-side baseline guard.
    local baseRevision = GetMinimumRecentPeerBaseline(scope, requestedBase)

    -- This synchronous pass is deliberately shallow and yield-free: WoW cannot
    -- dispatch a scan callback in the middle, so revision metadata and payload
    -- refer to one immutable verified snapshot for the entire long broadcast.
    local freezeOK, frozenSource = pcall(FreezeTransferSource, scope, realmDB, baseRevision, revision)
    if not freezeOK then
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent("|cffff0000[Sync Error]|r Could not freeze outbound snapshot: "
                .. tostring(frozenSource))
        end
        return false
    end

    local sessionId = NewSessionId()
    guildLane.phase = "sending"
    guildLane.scope = scope
    guildLane.source = MarketSync.GetLocalSyncIdentity()
    guildLane.revision = revision
    guildLane.sessionId = sessionId
    pullInProgress = true
    pullRequestPending = false
    if guildLane.timer then guildLane.timer:Cancel(); guildLane.timer = nil end
    if pullRequestPendingTimer then pullRequestPendingTimer:Cancel(); pullRequestPendingTimer = nil end

    outboundTransfer = {
        sessionId = sessionId,
        scope = scope,
        baseRevision = baseRevision,
        producer = CreateTransferProducer(sessionId, scope, baseRevision, revision, scanTime, frozenSource),
        frozenEntryCount = #frozenSource,
        lastProgressAt = GetTxClock(),
    }
    if MarketSync.UpdateSwarmUI then
        MarketSync.UpdateSwarmUI(UnitName("player"), scope == "N" and "Sending Neutral" or "Sending")
        if requesterIdentity then
            MarketSync.UpdateSwarmUI(requesterIdentity, scope == "N" and "Receiving Neutral" or "Receiving")
        end
    end
    if MarketSync.LogNetworkEvent then
        MarketSync.LogNetworkEvent(string.format(
            "|cff00ff00[Sync Start]|r Exact advertiser accepted %s request; session=%s, revision=%d, requested base=%d, guild base=%d, frozen entries=%d.",
            scope == "N" and "neutral" or "main", sessionId, revision, requestedBase,
            baseRevision, #frozenSource))
    end
    return true
end

-- Protocol 2 never emits legacy, unframed market-data messages.
function MarketSync.SendSyncRequest()
    Debug("Single-item REQ is unavailable in sync protocol 2")
    return false
end

function MarketSync.SendSyncResponse()
    Debug("Unframed RES is unavailable in sync protocol 2")
    return false
end

function MarketSync.SendBulkSyncResponse()
    Debug("Unframed BRES is unavailable in sync protocol 2")
    return false
end

function MarketSync.SendPullAccept() return false end
function MarketSync.RegisterPullAccept() return false end
function MarketSync.SendNeutralPullAccept() return false end
function MarketSync.RegisterNeutralPullAccept() return false end
function MarketSync.SchedulePullResponse() return false end
function MarketSync.ScheduleNeutralPullResponse() return false end
function MarketSync.RespondToNeutralPull() return false end
function MarketSync.RespondToPull() return false end

-- ================================================================
-- UPDATE LOCAL DATABASE (Smart Merge)
-- ================================================================
function MarketSync.UpdateLocalDBByKey(key, price_or_day, day_or_histStr, qty_or_sender, legacySender)
    local isGranular = type(day_or_histStr) == "string"
    local sender = isGranular and qty_or_sender or legacySender
    
    if sender and IsBlocked(sender) then return end

    local realmDB = MarketSync.GetRealmDB() -- Cache once per call (hot path during sync)
    local itemLink = "item:" .. tostring(key) -- Fallback for logs

    -- DIRECT INSERTION to ensure persistence (when Auctionator is loaded)
    local priceData = nil
    if Auctionator and Auctionator.Database and Auctionator.Database.db then
        priceData = Auctionator.Database.db[key]
        if not priceData then
            priceData = { l={}, h={}, m=0, a={} }
            Auctionator.Database.db[key] = priceData
            Debug("Creating new DB entry for " .. key)
        end
        if not priceData.l then priceData.l = {} end
        if not priceData.h then priceData.h = {} end
        if not priceData.a then priceData.a = {} end
    else
        priceData = { l={}, h={}, m=0, a={} }
    end

    if isGranular then
        -- ==========================================
        -- NEW GRANULAR PATH (Timeseries History Str)
        -- ==========================================
        local incomingDay = tonumber(price_or_day) or 0
        local histStr = day_or_histStr
        
        if not realmDB.PersonalData then realmDB.PersonalData = {} end
        local pData = realmDB.PersonalData
        if not pData[key] then pData[key] = { m=0, d=0, h={} } end
        if not pData[key].h then pData[key].h = {} end
        local verifiedCommit = MarketSync._Protocol2CommitInProgress == true
        if verifiedCommit and not pData[key].vh then pData[key].vh = {} end
        
        local dayStr = tostring(incomingDay)
        local mergedStr = pData[key].h[dayStr] or ""
        local verifiedMergedStr = verifiedCommit and (pData[key].vh[dayStr] or "") or nil
        local historyUpdated = false
        
        local latestIncomingPrice = nil
        local maxIncomingBucketOffset = -1
        local latestNotificationPrice = nil
        local maxNotificationBucketOffset = -1
        
        -- Parse the incoming CSV-separated bucket array
        for incPoint in string.gmatch(histStr, "([^,]+)") do
            local b_offs, p_b36, q_b36 = string.match(incPoint, "(%d+):([%w%-]+):([%w%-]+)")
            if b_offs and p_b36 and q_b36 then
                local b_num = tonumber(b_offs)
                local newPrice = MarketSync.FromBase36(p_b36)
                local newQty = MarketSync.FromBase36(q_b36)
                
                local pointChanged, acceptedLivePoint
                mergedStr, pointChanged, acceptedLivePoint = MergeTimeseriesPoint(
                    mergedStr, b_num, newPrice, newQty, true)
                historyUpdated = historyUpdated or pointChanged

                -- Transport completeness does not make a rejected price point
                -- trustworthy. Only values accepted by the live pollution
                -- filter may enter the verified outbound snapshot.
                if verifiedCommit and acceptedLivePoint then
                    verifiedMergedStr = select(1, MergeTimeseriesPoint(
                        verifiedMergedStr, b_num, newPrice, newQty, false))
                end
                if acceptedLivePoint and b_num > maxIncomingBucketOffset then
                    maxIncomingBucketOffset = b_num
                    latestIncomingPrice = newPrice
                end
                if acceptedLivePoint and pointChanged and b_num > maxNotificationBucketOffset then
                    maxNotificationBucketOffset = b_num
                    latestNotificationPrice = newPrice
                end
            end
        end
        
        pData[key].h[dayStr] = mergedStr
        if verifiedCommit then
            pData[key].vh[dayStr] = verifiedMergedStr
        end

        -- Protocol-2 payloads are only applied after every sequence is present,
        -- so their per-item revision is safe to advertise in a later broadcast.
        if verifiedCommit and maxIncomingBucketOffset >= 0 then
            local incomingBucket = ScanDayOffsetToBucket(incomingDay, maxIncomingBucketOffset)
            if incomingDay >= (tonumber(pData[key].d) or 0) and latestIncomingPrice then
                pData[key].m = latestIncomingPrice
            end
            pData[key].d = math.max(tonumber(pData[key].d) or 0, incomingDay)
            pData[key].latestBucket = math.max(tonumber(pData[key].latestBucket) or 0, incomingBucket)
            realmDB.LatestBucket = math.max(tonumber(realmDB.LatestBucket) or 0, incomingBucket)
        end
        
        if historyUpdated then
            -- Re-aggregate the day to update Auctionator backwards-compat tooltips
            local minPriceDaily = 9999999999
            local maxQtyDaily = 0
            
            for b_offs, p_b36, q_b36 in string.gmatch(mergedStr, "(%d+):([%w%-]+):([%w%-]+)") do
                local p = MarketSync.FromBase36(p_b36)
                local q = MarketSync.FromBase36(q_b36)
                if p > 0 and p < minPriceDaily then minPriceDaily = p end
                if q > maxQtyDaily then maxQtyDaily = q end
            end
            
            if minPriceDaily ~= 9999999999 then
                priceData.h[dayStr] = minPriceDaily
                priceData.a[dayStr] = maxQtyDaily
                
                local maxDay = 0
                for d, _ in pairs(priceData.h) do
                    local dayNum = tonumber(d)
                    if dayNum and dayNum > maxDay then maxDay = dayNum end
                end
                
                if incomingDay >= maxDay or priceData.m == 0 then
                    priceData.m = latestIncomingPrice or minPriceDaily
                end
            end
            
            TrackSync(sender, 1)
            if not realmDB.ItemMetadata then realmDB.ItemMetadata = {} end
            local meta = realmDB.ItemMetadata[key]
            if not meta then
                meta = { days = {}, lastSource = sender, lastTime = time() }
                realmDB.ItemMetadata[key] = meta
            end
            if not meta.days then meta.days = {} end
            meta.days[dayStr] = { source = sender, time = time() }
            meta.lastSource = sender
            meta.lastTime = time()
            
            if MarketSync.InvalidateSyncContributorCache then MarketSync.InvalidateSyncContributorCache() end
            if MarketSync.AddToGuildIncoming then MarketSync.AddToGuildIncoming(key) end
            
            if not realmDB.HistoryLog then realmDB.HistoryLog = {} end
            table.insert(realmDB.HistoryLog, 1, { link = itemLink, price = latestIncomingPrice or priceData.m, sender = sender or "Swarm", time = time() })
            if #realmDB.HistoryLog > 100 then table.remove(realmDB.HistoryLog) end

            -- Chat.lua stages complete sessions before invoking this path, which
            -- keeps incomplete chunks from producing alerts.
            if not MarketSync._Protocol2CommitInProgress
                and MarketSync.EvaluateNotificationsForRecord and latestIncomingPrice then
                MarketSync.EvaluateNotificationsForRecord(key, latestIncomingPrice, "main", sender)
            end
        end

        return latestNotificationPrice, incomingDay, maxNotificationBucketOffset

    else
        -- ==========================================
        -- LEGACY PATH (Flat Daily Minimums)
        -- ==========================================
        local price = tonumber(price_or_day) or 0
        local incomingScanDay = tonumber(day_or_histStr) or 0
        local quantity = tonumber(qty_or_sender) or 0
        
        local scanDayStr = tostring(incomingScanDay)
        local currentHigh = priceData.h[scanDayStr]
        local currentLow = priceData.l[scanDayStr]

        local historyUpdated = false

        if currentHigh == nil or price > currentHigh then
            priceData.h[scanDayStr] = price
            currentHigh = price
            historyUpdated = true
        end

        if price < currentHigh and (currentLow == nil or price < currentLow) then
            priceData.l[scanDayStr] = price
            historyUpdated = true
        end

        if quantity and quantity > 0 then
            local currentQty = priceData.a[scanDayStr]
            if not currentQty or quantity > currentQty then
                priceData.a[scanDayStr] = quantity
                historyUpdated = true
            end
        end

        local maxDay = 0
        for d, _ in pairs(priceData.h) do
            local dayNum = tonumber(d)
            if dayNum and dayNum > maxDay then maxDay = dayNum end
        end

        if incomingScanDay >= maxDay or priceData.m == 0 then
            priceData.m = price
            Debug("Updated Latest Price (m) for " .. itemLink .. " to " .. FormatMoney(price))
        elseif historyUpdated then
            Debug("Merged Historical Data for " .. itemLink .. " (Day " .. incomingScanDay .. ")")
        end

        if sender and (historyUpdated or incomingScanDay >= maxDay) then
            TrackSync(sender, 1)
            if not realmDB.ItemMetadata then realmDB.ItemMetadata = {} end
            
            local meta = realmDB.ItemMetadata[key]
            if not meta then
                meta = { days = {}, lastSource = sender, lastTime = time() }
                realmDB.ItemMetadata[key] = meta
            end
            if not meta.days then meta.days = {} end
            
            local isNewData = historyUpdated or (not priceData.h[scanDayStr])
            
            if not meta.days[scanDayStr] or isNewData then
                meta.days[scanDayStr] = { source = sender, time = time() }
            end
            meta.lastSource = sender
            meta.lastTime = time()
            if MarketSync.InvalidateSyncContributorCache then
                MarketSync.InvalidateSyncContributorCache()
            end

            if MarketSync.AddToGuildIncoming then
                MarketSync.AddToGuildIncoming(key)
            end
        end

        if not realmDB.HistoryLog then realmDB.HistoryLog = {} end
        table.insert(realmDB.HistoryLog, 1, { link = itemLink, price = price, sender = sender or "Self", time = time() })
        if #realmDB.HistoryLog > 100 then table.remove(realmDB.HistoryLog) end

        if MarketSync.EvaluateNotificationsForRecord then
            MarketSync.EvaluateNotificationsForRecord(key, price, "main", sender)
        end
    end
end

function MarketSync.UpdateLocalNeutralDBByKey(key, price, day, quantity, sender, isLocalCapture, isVerified)
    local realmDB = MarketSync.GetRealmDB()
    if not realmDB.NeutralData then realmDB.NeutralData = {} end
    if not realmDB.NeutralMeta then realmDB.NeutralMeta = {} end

    local entry = realmDB.NeutralData[key]
    if not entry then
        entry = { m = 0, d = 0, q = 0, h = {}, l = {}, a = {} }
        realmDB.NeutralData[key] = entry
    end
    if not entry.h then entry.h = {} end
    if not entry.l then entry.l = {} end
    if not entry.a then entry.a = {} end

    local incomingDay = tonumber(day) or 0
    local incomingPrice = tonumber(price) or 0
    local incomingQty = tonumber(quantity) or 0
    if incomingPrice <= 0 then return end
    local verifiedCommit = isVerified == true or MarketSync._Protocol2CommitInProgress == true

    local dayStr = tostring(incomingDay)
    local curHigh = entry.h[dayStr]
    local curLow = entry.l[dayStr]
    local historyUpdated = false
    if not curHigh or incomingPrice > curHigh then
        entry.h[dayStr] = incomingPrice
        historyUpdated = true
    end
    if not curLow or incomingPrice < curLow then
        entry.l[dayStr] = incomingPrice
        historyUpdated = true
    end
    if incomingQty > (tonumber(entry.a[dayStr]) or 0) then
        entry.a[dayStr] = incomingQty
        historyUpdated = true
    end

    local isNewData = historyUpdated or (not curHigh)
    if incomingDay >= (tonumber(entry.d) or 0) then
        entry.d = incomingDay
        entry.m = incomingPrice
        entry.q = incomingQty
    end
    if isLocalCapture then
        entry.observedAt = time()
    end
    local verifiedAccepted = false
    local verifiedChanged = false
    if verifiedCommit and incomingDay >= (tonumber(entry.vd) or 0) then
        verifiedChanged = incomingDay > (tonumber(entry.vd) or 0)
            or incomingPrice ~= (tonumber(entry.vm) or 0)
            or incomingQty ~= (tonumber(entry.vq) or 0)
        entry.vd = incomingDay
        entry.vm = incomingPrice
        entry.vq = incomingQty
        verifiedAccepted = true
    end

    local meta = realmDB.NeutralMeta[key] or {}
    if verifiedCommit then
        meta.source = sender or "Swarm"
        meta.time = time()
        meta.state = "Complete"
    elseif not meta.time or isNewData then
        meta.source = sender or (isLocalCapture and "Personal" or "Unknown")
        meta.time = time()
        meta.state = "Observed"
    end
    realmDB.NeutralMeta[key] = meta
    if MarketSync.InvalidateSyncContributorCache then
        MarketSync.InvalidateSyncContributorCache()
    end

    if sender and sender ~= UnitName("player") then
        if not realmDB.NeutralSync then realmDB.NeutralSync = {} end
        if not realmDB.NeutralSync.SyncStats then realmDB.NeutralSync.SyncStats = {} end
        local stats = realmDB.NeutralSync.SyncStats[sender] or { count = 0, last = 0 }
        stats.count = (stats.count or 0) + 1
        stats.last = time()
        realmDB.NeutralSync.SyncStats[sender] = stats
    end

    if MarketSync.AddToNeutralIncoming then
        MarketSync.AddToNeutralIncoming(key)
    end

    if not MarketSync._Protocol2CommitInProgress and MarketSync.EvaluateNotificationsForRecord then
        MarketSync.EvaluateNotificationsForRecord(key, incomingPrice, "neutral", sender)
    end
    if verifiedCommit and (not verifiedAccepted or not verifiedChanged) then return nil, incomingDay, 0 end
    return incomingPrice, incomingDay, 0
end

function MarketSync.UpdateLocalNeutralDB(itemLink, price, day, quantity, sender, isLocalCapture)
    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
        if not dbKeys or #dbKeys == 0 then return end
        MarketSync.UpdateLocalNeutralDBByKey(dbKeys[1], price, day, quantity, sender, isLocalCapture)
    end)
end

function MarketSync.UpdateLocalDB(itemLink, price, day, quantity, sender)
    if sender and IsBlocked(sender) then return end

    Auctionator.Utilities.DBKeyFromLink(itemLink, function(dbKeys)
        if not dbKeys or #dbKeys == 0 then return end
        local key = dbKeys[1]
        MarketSync.UpdateLocalDBByKey(key, price, day, quantity, sender)
    end)
end

-- ================================================================
-- PASSIVE SYNC (Advertisement-based)
-- ================================================================
local passiveTicker

function MarketSync.StartPassiveSync()
    if passiveTicker then passiveTicker:Cancel(); passiveTicker = nil end

    -- Use deterministic identity hash jitter on initial login (15s to 45s)
    -- to prevent dozens of guild members announcing at the exact same second on login/restart
    local localName = MarketSync.GetLocalSyncIdentity and MarketSync.GetLocalSyncIdentity() or UnitName("player") or "Player"
    local loginJitter = 15 + ((HashIdentity(localName) % 3000) / 100)

    C_Timer.After(loginJitter, function()
        if MarketSyncDB then
            MarketSync.SendAdvertisement()
            if MarketSync.SendNeutralAdvertisement then
                -- Stagger neutral advertisement by 6 seconds to avoid sending 2 frames in the same tick
                C_Timer.After(6, function()
                    if MarketSync.SendNeutralAdvertisement then
                        MarketSync.SendNeutralAdvertisement()
                    end
                end)
            end
        end
    end)

    -- Dynamic re-advertisement with randomized jitter (270s to 330s)
    -- Prevents periodic timer synchronization (thundering herd effect across large guilds)
    local function ScheduleNextPeriodicAdvertisement()
        local nextInterval = 270 + math.random(0, 60)
        passiveTicker = C_Timer.NewTimer(nextInterval, function()
            if MarketSyncDB then
                MarketSync.SendAdvertisement()
                if MarketSync.SendNeutralAdvertisement then
                    C_Timer.After(6, function()
                        if MarketSync.SendNeutralAdvertisement then
                            MarketSync.SendNeutralAdvertisement()
                        end
                    end)
                end
            end
            ScheduleNextPeriodicAdvertisement()
        end)
    end
    ScheduleNextPeriodicAdvertisement()
end

-- ================================================================
-- BULK BROADCAST (Manual Sync)
-- ================================================================
function MarketSync.BroadcastRecentData()
    if MarketSync.IsSyncBusy and MarketSync.IsSyncBusy() then
        print("|cFFFF8800[MarketSync]|r Sync busy. Wait for current blast to finish before starting a new broadcast.")
        SetTransientBlockedState("send/receive active")
        return
    end

    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return
    end

    broadcastInProgress = true
    print("|cFF00FF00[MarketSync]|r Starting bulk sync scan (this may take a moment)...")

    local co = coroutine.create(function()
        local count = 0
        local broadcastList = {}

        local currentScanDay = GetCurrentScanDay()
        if currentScanDay == 0 then
            print("|cFFFF0000[MarketSync]|r Error: Could not determine scan day!")
            return
        end

        local RECENT_THRESHOLD = 5
        local itemsChecked = 0

        for dbKey, data in pairs(Auctionator.Database.db) do
            itemsChecked = itemsChecked + 1
            if itemsChecked % 500 == 0 then coroutine.yield() end

            if type(data) == "table" and data.h then
                local lastSeenDay = -1
                for dayStr, _ in pairs(data.h) do
                    local d = tonumber(dayStr)
                    if d and d > lastSeenDay then lastSeenDay = d end
                end

                if lastSeenDay >= (currentScanDay - RECENT_THRESHOLD) then
                    local price = data.m
                    local dateStr = tostring(lastSeenDay)
                    local quantity = 0
                    if data.a and data.a[dateStr] then quantity = data.a[dateStr] end

                    local itemID = nil
                    if type(dbKey) == "number" then
                        itemID = dbKey
                    elseif type(dbKey) == "string" then
                        local idStr = dbKey:match("(%d+)")
                        if idStr then itemID = tonumber(idStr) end
                    end

                    if itemID then
                        local itemLink
                        local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
                        
                        if classID then
                             _, itemLink = C_Item.GetItemInfo(itemID)
                        end
                        
                        if not itemLink then 
                             itemLink = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0"
                        end
                        
                        if itemLink then
                            table.insert(broadcastList, {link = itemLink, price = price, day = lastSeenDay, quantity = quantity})
                            count = count + 1
                        end
                    end
                end
            end
        end

        if #broadcastList > 0 then
            print(string.format("|cFF00FF00[MarketSync]|r Found %d items. Broadcasting safely (this runs in the background)...", #broadcastList))
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Sending") end
        else
            print("|cFFFF0000[MarketSync]|r No recent validation items found to broadcast.")
        end

        for i, item in ipairs(broadcastList) do
            if item.link then
                MarketSync.SendSyncResponse(item.link, item.price, item.day, item.quantity, "GUILD")
            end
            if i % 5 == 0 then coroutine.yield() end
        end
        print("|cFF00FF00[MarketSync]|r Bulk sync broadcast completed.")
        if MarketSync.LogNetworkEvent then
            MarketSync.LogNetworkEvent(string.format("Bulk sync broadcast completed. Sent %d items.", #broadcastList))
        end
        if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
        broadcastInProgress = false
        ScheduleDeferredADVProcessing()
    end)

    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            if broadcastInProgress then
                broadcastInProgress = false
                ScheduleDeferredADVProcessing()
            end
            return
        end
        local success, err = coroutine.resume(co)
        if not success then
            print("|cFFFF0000[MarketSync] Sync Error:|r", err)
            broadcastInProgress = false
            ticker:Cancel()
            ScheduleDeferredADVProcessing()
        end
    end)
end

-- Manual broadcasts use the same verified, framed stream and guild-wide lane.
-- This later definition replaces the legacy RES loop above.
function MarketSync.BroadcastRecentData()
    if MarketSync.IsSyncBusy() then
        print("|cFFFF8800[MarketSync]|r Sync busy. The active guild broadcast must finish first.")
        SetTransientBlockedState("send/receive active")
        return false
    end
    if not MarketSync.CanSync() or not MarketSync.CanParticipateInData("M") then
        print("|cFFFF8800[MarketSync]|r Main auction-house sync is currently disabled.")
        return false
    end
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return false
    end

    local revision = MarketSync.GetMyLatestBucket()
    local scanTime = tonumber(MarketSync.GetRealmDB().SwarmTSF) or 0
    if revision <= 0 then
        print("|cFFFF8800[MarketSync]|r No verified main auction-house snapshot is available to broadcast.")
        return false
    end
    -- Manual sends join the same PULL election instead of bypassing the lane;
    -- two users clicking Broadcast at once therefore cannot create two dumps.
    local localIdentity = MarketSync.GetLocalSyncIdentity()
    return MarketSync.ScheduleDirectedPull("M", 0, localIdentity, revision, scanTime)
end

-- ================================================================
-- SEARCH (CLI)
-- ================================================================
function MarketSync.SearchLocalDB(query)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
        print("|cFFFF0000[MarketSync]|r Auctionator Database not found.")
        return
    end

    query = query:lower()
    local found = 0
    print(string.format("|cFF00FF00[MarketSync]|r Search results for '%s':", query))

    for dbKey, data in pairs(Auctionator.Database.db) do
        local itemID = nil
        if type(dbKey) == "number" then
            itemID = dbKey
        elseif type(dbKey) == "string" then
            local idStr = dbKey:match("(%d+)")
            if idStr then itemID = tonumber(idStr) end
        end

        if itemID then
            local name, link = C_Item.GetItemInfo(itemID)
            if name and name:lower():find(query) then
                local price = Auctionator.Database:GetPrice(dbKey)
                local age = Auctionator.Database:GetPriceAge(dbKey)
                if price then
                    print(string.format("  %s: %s (%s)", link or name, FormatMoney(price), MarketSync.FormatAge(age)))
                    found = found + 1
                    if found >= 20 then
                        print("  ... and more.")
                        break
                    end
                end
            end
        end
    end
    if found == 0 then print("  No results found.") end
end
