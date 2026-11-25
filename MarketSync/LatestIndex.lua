-- ================================================================
-- MarketSync - Latest index merge (Source selector, phase 2a)
-- Merges the Personal and Guild browse indexes into one table that keeps the
-- newest entry for each record key. This is a pure function: it reads only
-- its two arguments, so it can be tested without the UI or saved variables.
-- ================================================================

MarketSync = MarketSync or {}

-- True when entry a is newer than entry b. Uses exactTime (Unix seconds) when
-- both entries have it. Otherwise the smaller age in days is newer. A tie keeps
-- the entry already chosen, which is the Personal one.
local function IsNewer(a, b)
    local ta, tb = a.exactTime, b.exactTime
    if ta and tb then return ta > tb end
    if ta and not tb then return true end
    if tb and not ta then return false end
    local aa, ab = a.age, b.age
    if aa and ab then return aa < ab end
    if aa and not ab then return true end
    return false
end

-- personalIndex and guildIndex are tables keyed by record key, as built by
-- the browse index. Entries with no price are skipped. Returns a new table.
function MarketSync.MergeLatestIndex(personalIndex, guildIndex)
    local latest = {}
    for dbKey, entry in pairs(personalIndex or {}) do
        if type(entry) == "table" and (entry.price or 0) > 0 then
            latest[dbKey] = entry
        end
    end
    for dbKey, entry in pairs(guildIndex or {}) do
        if type(entry) == "table" and (entry.price or 0) > 0 then
            local current = latest[dbKey]
            if not current or IsNewer(entry, current) then
                latest[dbKey] = entry
            end
        end
    end
    return latest
end
