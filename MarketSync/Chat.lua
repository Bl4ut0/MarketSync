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

frame:SetScript("OnEvent", function(self, event, ...)
    -- ========================================
    -- ADDON MESSAGES (Sync Protocol)
    -- ========================================
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= PREFIX then return end

        -- Strip realm suffix: sender comes as "Name-Realm" but UnitName returns just "Name"
        local senderName = sender and sender:match("^([^%-]+)") or sender
        if senderName == UnitName("player") then return end

        -- Extract sender's realm from "Name-Realm" format
        local senderRealm = sender and sender:match("%-(.+)$")
        local msgType, p1, p2, p3, p4 = strsplit(";", msg)

        if msgType == "ADV" then
            local advRealm = p1
            local advScanDay = tonumber(p2) or 0
            local advItemCount = tonumber(p3) or 0
            if not MarketSync.myRealm then MarketSync.myRealm = GetNormalizedRealmName() or GetRealmName() end
            if advRealm ~= MarketSync.myRealm then
                Debug("Ignoring ADV from " .. senderName .. " (realm " .. tostring(advRealm) .. " != " .. MarketSync.myRealm .. ")")
                return
            end
            Debug("Received ADV from " .. senderName .. ": day=" .. advScanDay .. " items=" .. advItemCount)
            MarketSync.TrackSync(senderName, 0)
            local ourDay = MarketSync.GetMyLatestScanDay()
            if advScanDay > ourDay then
                Debug("Their data is fresher (" .. advScanDay .. " vs " .. ourDay .. "), sending PULL")
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
            MarketSync.RespondToPull(sinceDay, senderName)

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
                MarketSync.UpdateLocalDB(link, price, day, quantity, senderName)

                -- Reset the idle commit timer on every RES received
                if guildSyncCommitTimer then guildSyncCommitTimer:Cancel(); guildSyncCommitTimer = nil end
                guildSyncCommitTimer = C_Timer.NewTimer(GUILD_SYNC_IDLE_TIMEOUT, function()
                    guildSyncCommitTimer = nil
                    if MarketSync.CommitGuildSync then
                        MarketSync.CommitGuildSync()
                    end
                end)
            end
        end
        return
    end

    -- ========================================
    -- CHAT QUERIES ("? [Item Link]")
    -- ========================================
    local msg, sender, _, _, _, _, _, channelID = ...
    
    -- 1. Anti-Flood: Monitor for existing replies
    -- If we see "[Item Link]: 1g 20s" from someone else, cancel our pending reply for that item.
    local replyLink = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r):")
    if replyLink and sender ~= UnitName("player") then
        local itemID = GetItemInfoInstant(replyLink)
        if itemID and MarketSync.pendingQueries and MarketSync.pendingQueries[itemID] then
            MarketSync.pendingQueries[itemID] = nil -- Cancel our pending reply
            Debug("Suppressed reply for " .. itemID .. " (beaten by " .. sender .. ")")
        end
        return
    end

    -- 2. Handle Incoming Queries
    if msg:find("^%?") then
        -- Respect the user's setting to disable auto-replies
        if MarketSyncDB and not MarketSyncDB.EnableChatPriceCheck then return end

        local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
        if link then
            local itemID = GetItemInfoInstant(link)
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
            local delay = 0.5 + (math.random() * 1.5) -- 0.5s to 2.0s random delay

            C_Timer.After(delay, function()
                -- If the flag was cleared by the monitor above, abort.
                if not MarketSync.pendingQueries[itemID] then return end
                MarketSync.pendingQueries[itemID] = nil -- Clear flag

                -- Re-check price (just in case, though unlikely to change in 1s)
                local age = MarketSync.GetAuctionAge(link)
                local ageStr = FormatAge(age)
                local metaStr = ""

                -- We can try to get metadata, but AuctionatorDB is synchronous usually?
                -- If DBKeyFromLink is async, this might be Tricky inside a Timer callback context? 
                -- Actually GetAuctionPrice is direct. DBKeyFromLink uses a callback or returns keys?
                -- Auctionator.Utilities.DBKeyFromLink(link, callback) ...
                -- Let's keep it simple for now to ensure reliability inside the timer.
                
                local output = string.format("%s: %s (Age: %s)", link, FormatMoney(price), ageStr)

                -- Determine channel to reply in
                local replyChannel = "SAY"
                local target = nil
                
                -- Map event to reply channel
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
        end
    end
end)


