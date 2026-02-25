-- =============================================================
-- MarketSync - Chat Module
-- Event handling for addon messages and chat queries
-- =============================================================

local PREFIX = MarketSync.PREFIX
local Debug = MarketSync.Debug
local FormatMoney = MarketSync.FormatMoney
local FormatAge = MarketSync.FormatAge

-- Guild sync commit timer: after 5s of no RES messages, commit the buffer
local guildSyncCommitTimer = nil
local GUILD_SYNC_IDLE_TIMEOUT = 5

-- Session-level Rx counter: survives the idle timeout reset so END can validate completeness
local sessionRxTotal = 0
local scanCacheInvalidatedThisSession = false

-- ================================================================
-- EVENT FRAME
-- ================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHAT_MSG_SAY")
frame:RegisterEvent("CHAT_MSG_YELL")
frame:RegisterEvent("CHAT_MSG_OFFICER")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_ADDON")

local function CompareVersions(v1, v2)
    local function parse(v)
        v = tostring(v)
        local major, minor, patch = v:match("(%d+)%.(%d+)%.?(%d*)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end
    local m1, n1, p1 = parse(v1)
    local m2, n2, p2 = parse(v2)
    if m1 > m2 then return 1 end
    if m1 < m2 then return -1 end
    if n1 > n2 then return 1 end
    if n1 < n2 then return -1 end
    if p1 > p2 then return 1 end
    if p1 < p2 then return -1 end
    return 0
end

frame:SetScript("OnEvent", function(self, event, ...)
    -- ========================================
    -- ADDON MESSAGES (Sync Protocol)
    -- ========================================
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        
        -- Build a lookup table for data prefixes (fast check)
        local isDataPrefix = false
        for _, dp in ipairs(MarketSync.DATA_PREFIXES or {}) do
            if prefix == dp then isDataPrefix = true; break end
        end
        
        -- Accept messages from main prefix OR any data prefix
        if prefix ~= PREFIX and not isDataPrefix then return end

        -- Strip realm suffix: sender comes as "Name-Realm" but UnitName returns just "Name"
        local senderName = sender and sender:match("^([^%-]+)") or sender
        if senderName == UnitName("player") then return end

        -- Fast Guild Check: Ignore sync events if we aren't actually in a guild
        if not IsInGuild() then
            if MarketSync.UpdateNetworkUI then MarketSync.UpdateNetworkUI(0, 0, "|cffaaaaaaNetwork: Disabled (No Guild)|r") end
            return
        end

        -- Extract sender's realm from "Name-Realm" format
        local senderRealm = sender and sender:match("%-(.+)$")
        local msgType, p1, p2, p3, p4, p5 = strsplit(";", msg)

        if msgType == "ADV" then
            local advRealm = p1
            local advScanDay = tonumber(p2) or 0
            local advItemCount = tonumber(p3) or 0
            local advVersion = p4 or "0.4.0-beta"
            local advScanTime = tonumber(p5) or 0
            
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if advRealm ~= MarketSync.myRealm then
                Debug("Ignoring ADV from " .. senderName .. " (realm " .. tostring(advRealm) .. " != " .. MarketSync.myRealm .. ")")
                return
            end
            
            -- Version Compatibility Check
            local localVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("MarketSync", "Version") or GetAddOnMetadata("MarketSync", "Version") or "0.0.0"
            local cmp = CompareVersions(advVersion, localVersion)
            if cmp > 0 then
                -- They are newer. We must disable our sync and warn the user to update.
                if MarketSyncDB and MarketSyncDB.PassiveSync then
                    MarketSyncDB.PassiveSync = false
                    print(string.format("|cFFFF0000[MarketSync]|r Sync Disabled! You are running an outdated version (v%s). %s is running v%s. Please update your addon.", localVersion, senderName, advVersion))
                    if MarketSync.LogNetworkEvent then
                        MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Outdated addon version! Disabled sync to prevent data corruption. (New version: v%s)", advVersion))
                    end
                end
                return
            elseif cmp < 0 then
                -- They are older. We just ignore their payload, but we explicitly list them in the Swarm Queue
                -- so the user can see who is running around with an outdated addon version.
                if MarketSync.UpdateSwarmUI then
                    MarketSync.UpdateSwarmUI(senderName, "|cff888888Legacy (v" .. advVersion .. ")|r")
                end
                
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("Ignoring ADV from %s (Outdated version: v%s)", senderName, advVersion))
                end
                return
            end

            Debug("Received ADV from " .. senderName .. ": day=" .. advScanDay .. " items=" .. advItemCount)
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("Incoming |cff00ffff[ADV]|r from |cffffff00%s|r (Day %d, %d items, TSF: %s, v%s)", senderName, advScanDay, advItemCount, advScanTime > 0 and tostring(advScanTime) or "None", advVersion))
            end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Ready") end
            local ourDay = MarketSync.GetMyLatestScanDay()
            local ourItemCount = 0
            if advScanDay == ourDay then
                ourItemCount = MarketSync.CountRecentItems(ourDay)
            end
            local ourScanTime = (MarketSync.GetRealmDB() and MarketSync.GetRealmDB().SwarmTSF) or 0
            
            local isFresher = false
            if advScanDay > ourDay then
                -- They have a newer scan day, always fresher
                isFresher = true
            elseif advScanDay == ourDay then
                -- Same scan day — Since version guard ensures both clients >= current version,
                -- both universally support TSF. If the TSF timestamp is identical, 
                -- the payload represents the exact identical snapshot hash.
                -- NEVER ping-pong sync for minor local count artifacts if TSF matches.
                if advScanTime > ourScanTime then
                    isFresher = true
                elseif advScanTime == 0 and advItemCount > ourItemCount then
                    -- Legacy fallback ONLY if neither client has ever generated a TSF token
                    isFresher = true
                end
            end
            
            if isFresher then
                -- Don't initiate a PULL if we're already mid-transfer
                if (MarketSync.RxCount or 0) > 0 then
                    Debug("Suppressing PULL: already receiving data (" .. (MarketSync.RxCount or 0) .. " items so far)")
                    return
                end
                
                Debug(string.format("Their data is fresher (Day %d vs %d, Time %d vs %d, Items %d vs %d), sending PULL", advScanDay, ourDay, advScanTime, ourScanTime, advItemCount, ourItemCount))
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent("Data is fresher. Sending |cffff8800[PULL]|r request to Guild...")
                end
                
                -- We are going to receive data
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving") end
                
                -- Begin guild sync session before pulling
                if MarketSync.BeginGuildSync then
                    MarketSync.BeginGuildSync()
                end
                MarketSync.SendPullRequest(ourDay)
            end

        elseif msgType == "PULL" then
            local pullRealm = p1
            local sinceDay = tonumber(p2) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if pullRealm ~= MarketSync.myRealm then return end
            if not MarketSyncDB or not MarketSyncDB.PassiveSync then return end
            
            if MarketSync.LogNetworkEvent then
                MarketSync.LogNetworkEvent(string.format("Received |cffff8800[PULL]|r from |cffffff00%s|r (Since Day %d). Coordinating swarm...", senderName, sinceDay))
            end
            
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Receiving") end
            
            if MarketSync.SchedulePullResponse then
                MarketSync.SchedulePullResponse(sinceDay, senderName)
            end

        elseif msgType == "ACCEPT" then
            local acceptRealm = p1
            local sinceDay = tonumber(p2) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if acceptRealm ~= MarketSync.myRealm then return end
            
            if MarketSync.RegisterPullAccept then
                MarketSync.RegisterPullAccept(sinceDay, senderName)
            end

        elseif msgType == "REQ" then
            local link = p1
            if not link then return end
            if senderRealm and MarketSync.myRealm and senderRealm ~= MarketSync.myRealm then return end
            local price = MarketSync.GetAuctionPrice(link)
            local age = MarketSync.GetAuctionAge(link)
            if price and age then
                local scanDay = MarketSync.GetCurrentScanDay() - age
                MarketSync.SendSyncResponse(link, price, scanDay, 0, "GUILD")
            end

        elseif msgType == "BRES" then
            local payloadStr = p1
            local legacyDay = tonumber(p2) -- v1 format had day as second semicolon field
            if not payloadStr or payloadStr == "" then return end
            if senderRealm and MarketSync.myRealm and senderRealm ~= MarketSync.myRealm then
                Debug("Ignoring BRES from cross-realm sender: " .. tostring(sender))
                return
            end
            
            local FromBase36 = MarketSync.FromBase36
            local items = {strsplit(",", payloadStr)}
            for _, itemData in ipairs(items) do
                local dbKey, priceStr, qtyStr, dayStr
                local isV4 = false
                
                if itemData:find("_") then
                    dbKey, priceStr, qtyStr, dayStr = strsplit("_", itemData)
                    isV4 = true
                else
                    dbKey, priceStr, qtyStr, dayStr = strsplit(":", itemData)
                end
                
                local price = FromBase36(priceStr)
                if price == 0 and priceStr ~= "0" then price = tonumber(priceStr) end
                local quantity = FromBase36(qtyStr)
                if quantity == 0 and qtyStr and qtyStr ~= "0" then quantity = tonumber(qtyStr) or 0 end
                local day = FromBase36(dayStr)
                if day == 0 then day = tonumber(dayStr) or legacyDay end
                
                if price and day and day > 0 then
                    if isV4 then
                        -- For v4, dbKey is the direct Auctionator database key string, no base36 decode
                        local finalDbKey = dbKey
                        MarketSync.UpdateLocalDBByKey(finalDbKey, price, day, quantity, senderName)
                    else
                        -- Legacy handling
                        local itemID = FromBase36(dbKey)
                        if itemID == 0 then itemID = tonumber(dbKey) end
                        if itemID and itemID > 0 then
                            local link = "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0:0"
                            MarketSync.UpdateLocalDB(link, price, day, quantity, senderName)
                        end
                    end
                end
            end
            MarketSync.RxCount = (MarketSync.RxCount or 0) + #items
            sessionRxTotal = sessionRxTotal + #items
            
            -- Eagerly invalidate CachedScanStats on first data chunk of a sync session.
            -- This prevents stale cached counts from being served to ADV broadcasts
            -- while sync data is actively modifying the Auctionator database.
            if not scanCacheInvalidatedThisSession then
                scanCacheInvalidatedThisSession = true
                if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
                Debug("CachedScanStats invalidated on first BRES chunk (session Rx: " .. sessionRxTotal .. ")")
            end
            
            -- Receiver checkpoint logging
            if MarketSync.LogNetworkEvent then
                local rxTotal = MarketSync.RxCount or 0
                -- Log every roughly 100 received items by checking if this chunk crosses a 100-boundary
                if math.floor(rxTotal / 100) > math.floor((rxTotal - #items) / 100) then
                    MarketSync.LogNetworkEvent(string.format("|cff00ccff[Rx Checkpoint]|r Received %d total items from %s (%d in this chunk, prefix: %s)", rxTotal, senderName, #items, prefix))
                end
            end
            
            if MarketSync.UpdateSwarmUI then 
                MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving")
                MarketSync.UpdateSwarmUI(senderName, "Sending")
            end
            
            -- Increased idle timeout from 5s to 8s to accommodate the slower 0.3s send rate.
            -- This prevents premature commits while the sender is still transmitting between yields.
            if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
            guildSyncCommitTimer = C_Timer.NewTimer(8, function()
                guildSyncCommitTimer = nil
                local rxCount = MarketSync.RxCount or 0
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Rx Timeout]|r 8s idle — partial sync committed. Received %d items (transfer may be incomplete).", rxCount))
                end
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
                if MarketSync.CommitGuildSync then
                    MarketSync.CommitGuildSync()
                end
                -- Invalidate scan cache but do NOT update PersonalScanTime
                -- A timeout means the transfer was incomplete, so the receiver should
                -- remain eligible for a re-PULL on the next ADV cycle.
                if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
                MarketSync.RxCount = 0
                -- Do NOT reset sessionRxTotal here — END handler needs it to validate completeness
            end)

        elseif msgType == "END" then
            local itemsSent = tonumber(p1) or 0
            local messagesSent = tonumber(p2) or 0
            local senderScanTime = tonumber(p3) or 0  -- sender's original PersonalScanTime
            -- Use the session-level counter for completeness validation.
            -- MarketSync.RxCount may have been reset by the 8s idle timeout,
            -- but sessionRxTotal survives that reset.
            local rxCount = sessionRxTotal
            
            -- Immediate commit
            if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
            if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Idle") end
            if MarketSync.CommitGuildSync then
                MarketSync.CommitGuildSync()
            end
            
            -- Validate: only stamp our freshness if we received the full payload
            local isComplete = (rxCount >= itemsSent) and (itemsSent > 0)
            
            if isComplete then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cff00ff00[Rx Complete]|r Full sync verified! Received %d / %d items. Scan freshness updated (TSF: %d).", rxCount, itemsSent, senderScanTime))
                end
                -- Full transfer confirmed — stamp the SENDER's scan time (not ours!)
                -- This ensures both clients share the same TSF and won't ping-pong sync.
                -- NOTE: We do NOT call SnapshotPersonalScan() here! The Personal Scan
                -- snapshot is sacred — it only updates when the player visits the AH.
                -- This timestamp is purely for swarm freshness comparison (ADV TSF).
                if MarketSyncDB then
                    local realmDB = MarketSync.GetRealmDB()
                    realmDB.CachedScanStats = nil
                    -- Only stamp SwarmTSF (protocol freshness), NOT PersonalScanTime.
                    -- PersonalScanTime is sacred — it only updates when the player
                    -- actually visits the AH. This prevents guild syncs from appearing
                    -- as false personal scans in the UI.
                    realmDB.SwarmTSF = (senderScanTime > 0) and senderScanTime or time()
                end
                -- Send ACK back to guild so the sender sees confirmation
                -- Add a randomized jitter delay (1-20 seconds) to prevent guild channel flood 
                -- if hundreds of members finish downloading at the exact same moment.
                if IsInGuild() then
                    local myName = UnitName("player") or "Unknown"
                    local jitter = math.random(1, 20)
                    C_Timer.After(jitter, function()
                        if IsInGuild() then
                            C_ChatInfo.SendAddonMessage("MSync", string.format("ACK;%d;%s", rxCount, myName), "GUILD")
                        end
                    end)
                end
            else
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff8800[Rx Partial]|r Received %d / %d items (%.0f%%). Will re-PULL on next ADV cycle.", rxCount, itemsSent, (itemsSent > 0 and (rxCount / itemsSent * 100) or 0)))
                end
                -- Partial transfer — do NOT update PersonalScanTime so we stay eligible for re-PULL
                if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
            end
            
            -- Reset session Rx counters for a clean slate
            MarketSync.RxCount = 0
            sessionRxTotal = 0
            scanCacheInvalidatedThisSession = false

        elseif msgType == "RES" then
            local link = p1
            local price = tonumber(p2)
            local day = tonumber(p3)
            local quantity = tonumber(p4) or 0
            if senderRealm and MarketSync.myRealm and senderRealm ~= MarketSync.myRealm then
                Debug("Ignoring RES from cross-realm sender: " .. tostring(sender))
                return
            end
            if link and price and day then
                MarketSync.RxCount = (MarketSync.RxCount or 0) + 1
                MarketSync.UpdateLocalDB(link, price, day, quantity, senderName)
                if MarketSync.UpdateSwarmUI then 
                    MarketSync.UpdateSwarmUI(UnitName("player"), "Receiving")
                    MarketSync.UpdateSwarmUI(senderName, "Sending")
                end

                -- Reset the idle commit timer on every RES received
                if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
                guildSyncCommitTimer = C_Timer.NewTimer(GUILD_SYNC_IDLE_TIMEOUT, function()
                    guildSyncCommitTimer = nil
                    if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(UnitName("player"), nil) end
                    if MarketSync.CommitGuildSync then
                        MarketSync.CommitGuildSync()
                    end
                    -- Invalidate scan cache because we just received new items!
                    if MarketSyncDB then MarketSync.GetRealmDB().CachedScanStats = nil end
                end)
            end
        elseif msgType == "ACK" then
            local ackCount = tonumber(p1) or 0
            local ackUser = p2 or senderName
            if senderName ~= UnitName("player") then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cff00ff00[ACK]|r %s confirmed download complete (%d items received).", ackUser, ackCount))
                end
                if MarketSync.UpdateSwarmUI then MarketSync.UpdateSwarmUI(senderName, "Idle") end
            end

        elseif msgType == "ERR" then
            local targetName = p1
            local crashKey = p2
            if targetName == UnitName("player") then
                if MarketSync.LogNetworkEvent then
                    MarketSync.LogNetworkEvent(string.format("|cffff0000[Error]|r Sync failed. %s's database contains a corrupt entry at dbKey: %s", senderName, tostring(crashKey)))
                end
                if MarketSync.UpdateSwarmUI then
                    MarketSync.UpdateSwarmUI(senderName, "|cffff0000Error|r")
                    MarketSync.UpdateSwarmUI(UnitName("player"), nil)
                end
                if guildSyncCommitTimer then
                    guildSyncCommitTimer:Cancel()
                    guildSyncCommitTimer = nil
                end
            end

        elseif msgType == "CLAIM" then
            local claimedItemID = tonumber(p1)
            if not claimedItemID then return end
            
            -- Track all competing claimants for this itemID so we can tiebreak deterministically
            if not MarketSync.claimContestants then MarketSync.claimContestants = {} end
            if not MarketSync.claimContestants[claimedItemID] then MarketSync.claimContestants[claimedItemID] = {} end
            MarketSync.claimContestants[claimedItemID][senderName] = true
            
            -- If we haven't claimed this item ourselves yet, cancel our pending lottery immediately.
            -- (Their timer fired before ours — they're ahead of us in the lottery.)
            if MarketSync.pendingQueries and MarketSync.pendingQueries[claimedItemID] then
                MarketSync.pendingQueries[claimedItemID] = nil
                Debug("Price check for " .. claimedItemID .. " claimed by " .. senderName .. ", cancelling our pending lottery")
            end

            -- Housekeeping: evict stale claimContestants entries for items no longer in play.
            -- This prevents the table from growing indefinitely over a long session.
            for itemID, _ in pairs(MarketSync.claimContestants) do
                if itemID ~= claimedItemID then
                    MarketSync.claimContestants[itemID] = nil
                end
            end
        end
        return
    end

    -- ========================================
    -- CHAT QUERIES ("? [Item Link]")
    -- ========================================
    local msg, sender, _, _, _, _, _, channelID = ...
    
    -- Guild Requirement: If we are not in a guild, ignore all public channels (except whispers)
    if not IsInGuild() and event ~= "CHAT_MSG_WHISPER" then return end
    
    -- Strip sender name for comparison (sender may include realm suffix)
    local querySender = sender and sender:match("^([^%-]+)") or sender
    
    -- 1. Anti-Flood: Monitor for existing replies from other clients
    -- If we see a price reply message from someone else, cancel our pending reply for that item.
    -- Match both raw escape-coded links and rendered item links to be safe across WoW versions.
    local replyLink = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r):") or msg:match("(%[.-%]):.*%d+[gsc]")
    if replyLink and querySender ~= UnitName("player") then
        local itemID = tonumber(replyLink:match("item:(%d+)")) or tonumber(replyLink:match("%[(.-)%]") and select(1, C_Item.GetItemInfoInstant(replyLink:match("%[(.-)%]"))) or 0)
        if itemID and itemID > 0 and MarketSync.pendingQueries and MarketSync.pendingQueries[itemID] then
            MarketSync.pendingQueries[itemID] = nil -- Cancel our pending reply
            Debug("Suppressed reply for " .. itemID .. " (beaten by " .. querySender .. " via chat)")
        end
        return
    end

    -- 2. Handle Incoming Queries
    if msg:find("^%?") then
        -- Respect the user's setting to disable auto-replies
        if MarketSyncDB and not MarketSyncDB.EnableChatPriceCheck then return end

        -- Never reply to your own queries
        if querySender == UnitName("player") then return end

        local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            if not itemID then return end

            -- Init pending table if needed
            if not MarketSync.pendingQueries then MarketSync.pendingQueries = {} end

            -- Ignore if we already have a pending reply for this item (debounce)
            if MarketSync.pendingQueries[itemID] then return end

            -- Check if we even have data first
            local price = MarketSync.GetAuctionPrice(link)
            if not price then return end -- No data, no reply

            -- Start the lottery!
            MarketSync.pendingQueries[itemID] = true
            local delay = 0.5 + (math.random() * 2.5) -- 0.5s to 3.0s random delay (wider window for coordination)

            C_Timer.After(delay, function()
                -- PHASE 1: If a CLAIM from another client arrived while we waited, abort.
                if not MarketSync.pendingQueries[itemID] then return end
                MarketSync.pendingQueries[itemID] = nil -- Clear flag

                -- Broadcast our CLAIM to other clients (addon channel = near-instant)
                -- but do NOT send the visible chat reply yet.
                local myName = UnitName("player") or "Unknown"
                if not MarketSync.claimContestants then MarketSync.claimContestants = {} end
                if not MarketSync.claimContestants[itemID] then MarketSync.claimContestants[itemID] = {} end
                MarketSync.claimContestants[itemID][myName] = true -- Register ourselves
                
                if IsInGuild() then
                    C_ChatInfo.SendAddonMessage(PREFIX, "CLAIM;" .. itemID, "GUILD")
                end

                -- PHASE 2: Grace period — wait 300ms for competing CLAIMs to arrive.
                -- If another client fired at nearly the same time, their CLAIM will arrive
                -- during this window. We then use alphabetical name order as a deterministic
                -- tiebreaker so exactly one client always wins.
                C_Timer.After(0.3, function()
                    -- Check all contestants for this item
                    local contestants = MarketSync.claimContestants and MarketSync.claimContestants[itemID]
                    if contestants then
                        -- Deterministic tiebreak: lowest alphabetical name wins
                        for name, _ in pairs(contestants) do
                            if name < myName then
                                -- Someone with a lower name also claimed — they win, we stand down
                                Debug("Price check tiebreak: " .. name .. " wins over " .. myName .. " for item " .. itemID)
                                MarketSync.claimContestants[itemID] = nil
                                return
                            end
                        end
                        MarketSync.claimContestants[itemID] = nil -- Clean up
                    end

                    -- We won the tiebreak (or were the only claimant) — send the reply!
                    local age = MarketSync.GetAuctionAge(link)
                    local ageStr

                    local itemID = tonumber(link:match("item:(%d+)"))
                    local exactTime = nil
                    local source = myName -- Default to self
                    
                    if itemID and MarketSyncDB and MarketSync.GetRealmDB().ItemMetadata then
                        local meta = MarketSync.GetRealmDB().ItemMetadata[tostring(itemID)] or MarketSync.GetRealmDB().ItemMetadata["g:"..itemID] or MarketSync.GetRealmDB().ItemMetadata["p:"..itemID]
                        if meta then
                            exactTime = meta.lastTime or meta.time
                            local contributor = meta.lastSource or meta.source
                            if contributor and contributor ~= "Personal" then
                                source = contributor
                            end
                        end
                    end

                    if age == 0 and not exactTime and MarketSyncDB and MarketSync.GetRealmDB().PersonalScanTime then
                        exactTime = MarketSync.GetRealmDB().PersonalScanTime
                    end

                    if exactTime then
                        ageStr = MarketSync.FormatRealmTime(exactTime, "%H:%M RT (") .. source .. ")"
                    elseif age == 0 then
                        ageStr = "Today (" .. source .. ")"
                    elseif age then
                        ageStr = age .. "d ago (" .. source .. ")"
                    else
                        ageStr = "Unknown"
                    end
                    
                    local output = string.format("%s: %s (Age: %s)", link, FormatMoney(price), ageStr)

                    -- Determine channel to reply in
                    local replyChannel = "SAY"
                    local target = nil
                    
                    if event == "CHAT_MSG_GUILD" then replyChannel = "GUILD"
                    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then replyChannel = "PARTY"
                    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then replyChannel = "RAID"
                    elseif event == "CHAT_MSG_YELL" then replyChannel = "YELL"
                    elseif event == "CHAT_MSG_OFFICER" then replyChannel = "OFFICER"
                    elseif event == "CHAT_MSG_WHISPER" then
                        replyChannel = "WHISPER"
                        target = sender
                    elseif event == "CHAT_MSG_CHANNEL" then
                        replyChannel = "CHANNEL"
                        target = channelID
                    end

                    C_ChatInfo.SendChatMessage(output, replyChannel, nil, target)
                end)
            end)
        end
    end
end)


