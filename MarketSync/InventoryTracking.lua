-- Physical inventory for the current character and saved alts.
local T = { bankOpen = false, mailOpen = false }
MarketSync.InventoryTracking = T

function T.IsEnabled()
    return MarketSyncDB and MarketSyncDB.ShowItemsOnOtherCharacters ~= false
end

-- Optional holdings provider (the MarketSyncLedger addon) is read at call time from
-- MarketSync.InventoryHoldingsProvider = { IsActive = fn, Holdings = fn }. Core stays
-- the single scanner. While the provider reports active, snapshots go to it and
-- tooltips read from it; otherwise core keeps its own store and tooltips read that.
local function ProviderActive()
    local p = MarketSync.InventoryHoldingsProvider
    return p ~= nil and p.IsActive() == true
end

local function Owner()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName()
    return name and (name .. "-" .. (realm or ""))
end

local function TrackingOwner()
    local ruleset = MarketSync.GetForeverAuctionRuleset and MarketSync.GetForeverAuctionRuleset()
    if ruleset and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
        local name, surname = UnitName("player")
        if name and MarketSync.IsSafeString(surname) and surname ~= "" then
            return name .. " " .. surname .. "-" .. ruleset
        end
    end
    return Owner()
end

local function Add(items, link, quantity)
    if MarketSync.IsSecretValue and (MarketSync.IsSecretValue(link) or MarketSync.IsSecretValue(quantity)) then return end
    local id = tonumber(link) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    local suffix = type(link) == "string" and tonumber(link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:|]+)"))
    local key = id and (id .. ":" .. (suffix or 0))
    quantity = tonumber(quantity)
    if key and quantity and quantity > 0 then
        local entry = items[key] or { key = key, itemID = id, qty = 0, link = type(link) == "string" and link or nil }
        entry.qty = entry.qty + quantity; items[key] = entry
    end
end
local function BagItems(first, last, observedSlots)
    local items = {}
    local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local info = C_Container and C_Container.GetContainerItemInfo or GetContainerItemInfo
    if not slots or not info then return nil end
    for bag = first, last do
        for slot = 1, slots(bag) or 0 do
            local a, b, _, _, _, _, link, _, _, id = info(bag, slot)
            if type(a) == "table" then Add(items, a.hyperlink or a.itemID, a.stackCount)
            else Add(items, link or id, b) end
            if observedSlots then
                observedSlots[bag .. ":" .. slot] = type(a) == "table"
                    and { link = a.hyperlink or a.itemID, qty = a.stackCount }
                    or ((link or id) and { link = link or id, qty = b })
            end
        end
    end
    return items
end

local function Quantities(items)
    local quantities = {}
    for _, item in pairs(items) do
        if type(item) == "table" and type(item.itemID) == "number" and type(item.qty) == "number" and item.qty > 0 then
            quantities[item.itemID] = (quantities[item.itemID] or 0) + item.qty
        end
    end
    return quantities
end

local function Characters()
    if not MarketSyncDB then return end
    if type(MarketSyncDB.InventoryTracking) ~= "table" then
        -- One-time migration from the legacy ledger copy. That copy stops updating once
        -- MarketSyncLedger owns the records, so it only seeds the first run.
        local inventory = {}
        local ledger = MarketSyncDB.ItemLedger
        for _, character in pairs(type(ledger) == "table" and type(ledger.characters) == "table" and ledger.characters or {}) do
            if type(character) == "table" and type(character.owner) == "string" and type(character.storage) == "table" then
                local storage = inventory[character.owner] or {}
                inventory[character.owner] = storage
                for location, snapshot in pairs(character.storage) do
                    if type(snapshot) == "table" and type(snapshot.items) == "table" and type(snapshot.at) == "number"
                        and (not storage[location] or snapshot.at > storage[location].at) then
                        storage[location] = { at = snapshot.at, complete = snapshot.complete ~= false, quantities = Quantities(snapshot.items) }
                    end
                end
            end
        end
        MarketSyncDB.InventoryTracking = inventory
    end
    return MarketSyncDB.InventoryTracking
end

local function InventoryOwners(characters)
    local groups, ownerKeys, knownRulesets, fullNames = {}, {}, {}, {}
    local appearances = MarketSyncDB.InventoryCharacterInfo or {}
    local forever = MarketSync.GetClientFlavor and MarketSync.GetClientFlavor() == "forever"
    local current = TrackingOwner()
    if forever then
        for owner in pairs(characters) do
            local name, realm = owner:match("^([^%-]+)%-(.*)$")
            if name then
                local ruleset = appearances[owner] and appearances[owner].ruleset
                    or MarketSync.GetForeverRulesetForRealm(realm)
                local first = name:match("^(%S+)")
                ownerKeys[owner] = { name = name, first = first, realm = realm, ruleset = ruleset }
                if ruleset then
                    local previous = knownRulesets[first]
                    if previous == nil then
                        knownRulesets[first] = ruleset
                    elseif previous ~= ruleset then
                        knownRulesets[first] = false
                    end
                    if name ~= first then
                        local marketKey = first .. "-" .. ruleset
                        local known = fullNames[marketKey]
                        if known == nil then fullNames[marketKey] = name
                        elseif known ~= name then fullNames[marketKey] = false end
                    end
                end
            end
        end
    end
    for owner, storages in pairs(characters) do
        local identity = ownerKeys[owner]
        local ruleset = identity and (identity.ruleset or (identity.realm == "" and knownRulesets[identity.first]))
        local key = owner
        if ruleset then
            local name = identity.name
            if name == identity.first then name = fullNames[name .. "-" .. ruleset] or name end
            key = name .. "-" .. ruleset
        end
        local group = groups[key]
        if not group then
            group = { owner = owner, storages = {} }
            groups[key] = group
        elseif owner == current or (group.owner ~= current and appearances[owner] and not appearances[group.owner]) then
            group.owner = owner
        end
        for location, snapshot in pairs(storages) do
            local prior = group.storages[location]
            if not prior or snapshot.at > prior.at or (snapshot.at == prior.at and owner == current) then
                group.storages[location] = snapshot
            end
        end
    end
    return groups
end

function T.Holdings(itemID)
    local holdings = {}
    if not T.IsEnabled() then return holdings end
    if ProviderActive() then return MarketSync.InventoryHoldingsProvider.Holdings(itemID) or holdings end
    for _, group in pairs(InventoryOwners(Characters() or {})) do
        for location, snapshot in pairs(group.storages) do
            local qty = snapshot.quantities[itemID]
            if qty and qty > 0 then
                holdings[#holdings + 1] = {
                    owner = group.owner, storage = location, qty = qty, at = snapshot.at, complete = snapshot.complete,
                }
            end
        end
    end
    table.sort(holdings, function(a, b)
        if a.owner == b.owner then return a.storage < b.storage end
        return a.owner < b.owner
    end)
    return holdings
end

local function Save(storage, items, options)
    local owner = TrackingOwner()
    if not owner then return end
    if not ProviderActive() then
        local characters = Characters()
        characters[owner] = characters[owner] or {}
        characters[owner][storage] = {
            at = time(), complete = not options or options.complete ~= false, quantities = Quantities(items),
        }
    end
    if T.OnSnapshot then T.OnSnapshot(storage, items, options) end
end

local function SaveCharacterAppearance()
    local owner = TrackingOwner()
    if not owner then return end
    local name, surname = UnitName("player")
    local regionalNames = RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
    if regionalNames and MarketSync.IsSafeString(surname) and surname ~= "" then
        name = name .. " " .. surname
    end
    local _, class
    if UnitClass then _, class = UnitClass("player") end
    MarketSyncDB.InventoryCharacterInfo = MarketSyncDB.InventoryCharacterInfo or {}
    MarketSyncDB.InventoryCharacterInfo[owner] = {
        name = name, class = class,
        ruleset = MarketSync.GetForeverAuctionRuleset and MarketSync.GetForeverAuctionRuleset(),
    }
end

function T.CaptureBags()
    if not T.IsEnabled() then return end
    local observedSlots = T.OnBagsCaptured and {}
    local items = BagItems(0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4, observedSlots)
    if not items then return end
    SaveCharacterAppearance()
    local equipped = {}
    if GetInventoryItemLink then
        for slot = 1, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then Add(equipped, link, 1) end
        end
    end
    if T.OnBagsCaptured then T.OnBagsCaptured(items, observedSlots) end
    Save("bags", items, { equipped = equipped })
    Save("equipped", equipped)
end
function T.CaptureBank()
    if not T.IsEnabled() or not T.bankOpen then return end
    local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    if not slots then return end
    if (slots(-1) or 0) <= 0 then
        if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType and Enum.BankType.Character then
            if C_Bank.CanViewBank and not C_Bank.CanViewBank(Enum.BankType.Character) then return end
            local items, complete = {}, true
            for _, bag in ipairs(C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character) or {}) do
                local contents = BagItems(bag, bag)
                if not contents or (slots(bag) or 0) == 0 then complete = false end
                for _, item in pairs(contents or {}) do Add(items, item.link or item.itemID, item.qty) end
            end
            if complete then Save("bank", items) end
        end
        return
    end
    local items = BagItems(-1, -1)
    if not items then return end
    local bags = BagItems((NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7))
    for _, item in pairs(bags or {}) do Add(items, item.link or item.itemID, item.qty) end
    Save("bank", items)
    if REAGENTBANK_CONTAINER then
        local reagents = BagItems(REAGENTBANK_CONTAINER, REAGENTBANK_CONTAINER)
        if reagents then Save("reagent bank", reagents) end
    end
end

function T.CaptureMail()
    if not T.IsEnabled() or not T.mailOpen or not (GetInboxNumItems and GetInboxItem) then return end
    local shown, total = GetInboxNumItems()
    if type(shown) ~= "number" then return end
    local items = {}
    for index = 1, shown do
        for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local _, id, _, qty = GetInboxItem(index, slot)
            local link = GetInboxItemLink and GetInboxItemLink(index, slot)
            Add(items, link or id, qty)
        end
    end
    Save("mail", items, { complete = not total or shown >= total })
end

local function CharacterLabel(owner)
    local saved = MarketSyncDB.InventoryCharacterInfo and MarketSyncDB.InventoryCharacterInfo[owner]
    local char, realm = owner:match("^([^%-]+)%-(.*)$")
    local myRealm = GetRealmName and GetRealmName()
    local name = saved and saved.name or char or owner
    local myRuleset = MarketSync.GetForeverAuctionRuleset and MarketSync.GetForeverAuctionRuleset()
    local sameRuleset = myRuleset and realm and MarketSync.GetForeverRulesetForRealm(realm) == myRuleset
    if realm and realm ~= "" and not sameRuleset and realm ~= myRealm
        and realm ~= (GetNormalizedRealmName and GetNormalizedRealmName()) then
        name = name .. " · " .. realm
    end
    local color = saved and saved.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[saved.class]
    if color and color.colorStr then return "  |c" .. color.colorStr .. name .. "|r" end
    return "  " .. name
end

local function CountLabel(label, quantity)
    return "|cff78baff" .. label .. "|r |cffffffff" .. (BreakUpLargeNumbers or tostring)(quantity) .. "|r"
end

local storageLabels = {
    { "bags", "Bags" }, { "bank", "Bank" }, { "reagent bank", "Reagents" },
    { "mail", "Mail" }, { "equipped", "Equipped" },
}
local labelsByStorage = {}
for _, location in ipairs(storageLabels) do labelsByStorage[location[1]] = location[2] end
local function SafeAddLine(tip, text, r, g, b)
    if tip and tip.AddLine then tip:AddLine(text, r, g, b) end
end
local function SafeAddDoubleLine(tip, left, right, lr, lg, lb, rr, rg, rb)
    if tip and tip.AddDoubleLine then
        tip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    elseif tip and tip.AddLine then
        tip:AddLine(tostring(left) .. "  " .. tostring(right), lr or 1, lg or 1, lb or 1)
    end
end
local function Tooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not T.IsEnabled() and not T.AddTooltipDetails then return end
    local link = data and data.hyperlink
    if tooltip.GetItem then
        local _, itemLink = tooltip:GetItem()
        link = itemLink or link
    end
    if MarketSync.IsSecretValue and MarketSync.IsSecretValue(link) then link = nil end
    local id = data and data.id
    if MarketSync.IsSecretValue and MarketSync.IsSecretValue(id) then id = nil end
    id = tonumber(id) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    if not id then return end

    local isShift = MarketSync.IsDetailsKeyDown and MarketSync.IsDetailsKeyDown()
    local shiftFlag = isShift and "shift" or "norm"
    if tooltip.MarketSyncOwnershipItem == id and tooltip.MarketSyncOwnershipShift == shiftFlag then return end
    tooltip.MarketSyncOwnershipItem = id
    tooltip.MarketSyncOwnershipShift = shiftFlag

    local holdings = T.Holdings(id)
    local byOwner = {}
    local owners = {}
    local totalStock = 0
    local myOwner = Owner()
    local myTrackingOwner = TrackingOwner()

    for _, h in ipairs(holdings) do
        if not byOwner[h.owner] then
            byOwner[h.owner] = { total = 0, storages = {}, latestAt = h.at, complete = true }
            owners[#owners + 1] = h.owner
        end
        local entry = byOwner[h.owner]
        entry.total = entry.total + h.qty
        entry.storages[h.storage] = (entry.storages[h.storage] or 0) + h.qty
        if h.at > entry.latestAt then entry.latestAt = h.at end
        if not h.complete then entry.complete = false end
        totalStock = totalStock + h.qty
    end

    table.sort(owners, function(a, b)
        if a == b then return false end
        if a == myTrackingOwner then return true end
        if b == myTrackingOwner then return false end
        return a < b
    end)

    local addedLines = false
    local hasHiddenDetails = false

    if totalStock > 0 then
        if not isShift then
            SafeAddDoubleLine(tooltip, "|cffffd700Inventory|r", CountLabel("Total", totalStock))
            for _, owner in ipairs(owners) do
                local entry = byOwner[owner]
                local parts = {}
                for _, location in ipairs(storageLabels) do
                    local qty = entry.storages[location[1]]
                    if qty and qty > 0 then parts[#parts + 1] = CountLabel(location[2], qty) end
                end
                SafeAddDoubleLine(tooltip, CharacterLabel(owner), table.concat(parts, "  "))
            end
            hasHiddenDetails = true
            addedLines = true
        else
            SafeAddDoubleLine(tooltip, "|cffffd700Inventory Details|r", CountLabel("Total", totalStock))
            for _, h in ipairs(holdings) do
                local age = math.max(0, time() - h.at)
                local ageMins = math.floor(age / 60)
                local ageStr = ageMins < 60 and (ageMins .. "m ago") or (math.floor(ageMins / 60) .. "h ago")
                local warn = h.complete and "" or " · partial"
                SafeAddDoubleLine(tooltip, CharacterLabel(h.owner),
                    string.format("%s |cff888888[%s%s]|r", CountLabel(labelsByStorage[h.storage] or h.storage, h.qty), ageStr, warn))
            end
            addedLines = true
        end
    end

    if T.AddTooltipDetails then
        local added, hasDetails = T.AddTooltipDetails(tooltip, id, myOwner, isShift, totalStock > 0)
        addedLines = addedLines or added
        hasHiddenDetails = hasHiddenDetails or hasDetails
    end

    -- Modifier hint
    if not isShift and (hasHiddenDetails or (MarketSync.HasExtraTooltipDetails and MarketSync.HasExtraTooltipDetails(id, link))) then
        local modName = MarketSyncDB and MarketSyncDB.TooltipModifier or "SHIFT"
        local hintKey = (modName == "CTRL" and "Ctrl") or (modName == "ALT" and "Alt") or "Shift"
        SafeAddLine(tooltip, string.format("|cff777777<Hold %s for full details>|r", hintKey))
        addedLines = true
    end

    if addedLines and tooltip.Show then tooltip:Show() end
end
function T.InstallTooltips()
    if T.tooltipInstalled then return end
    T.tooltipInstalled = true
    for _, tip in pairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then tip:HookScript("OnTooltipCleared", function(self)
            self.MarketSyncOwnershipItem = nil
            self.MarketSyncOwnershipShift = nil
            self.MarketSyncProcessingItem = nil
            self.MarketSyncProcessingShift = nil
        end) end
    end
    -- Both paths: the Anniversary client has TooltipDataProcessor but its item
    -- tooltips only fire OnTooltipSetItem. Tooltip() skips a repeat for the same
    -- item and details-key state, so a client that fires both adds lines once.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip)
    end
    for _, tip in pairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then pcall(tip.HookScript, tip, "OnTooltipSetItem", Tooltip) end
    end
end

local frame = CreateFrame("Frame")
T.eventFrame = frame
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MODIFIER_STATE_CHANGED" }) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
        pcall(frame.RegisterEvent, frame, event)
    end
end

local queuedSnapshot
local function Snapshot()
    T.CaptureBags()
    T.CaptureBank()
    T.CaptureMail()
end

local function ScheduleSnapshot()
    if not T.IsEnabled() then return end
    if not (C_Timer and C_Timer.After) then
        Snapshot()
        return
    end
    local now = GetTime or time
    local deadline = now() + 0.35
    if queuedSnapshot then
        queuedSnapshot.deadline = deadline
        return
    end
    local request = { deadline = deadline }
    queuedSnapshot = request
    local function CaptureWhenReady()
        if queuedSnapshot ~= request then return end
        local remaining = request.deadline - now()
        if remaining > 0.01 then
            C_Timer.After(remaining, CaptureWhenReady)
            return
        end
        queuedSnapshot = nil
        Snapshot()
    end
    C_Timer.After(0.35, CaptureWhenReady)
end

function T.SetEnabled(enabled)
    if not MarketSyncDB then return end
    MarketSyncDB.ShowItemsOnOtherCharacters = enabled == true
    queuedSnapshot = nil
    if not enabled and T.OnScanningDisabled then T.OnScanningDisabled() end
    if enabled then Snapshot() end
    if MarketSync.RefreshActiveTooltip then MarketSync.RefreshActiveTooltip() end
end

frame:SetScript("OnEvent", function(_, event, key)
    if event == "PLAYER_LOGIN" then
        T.InstallTooltips()
        Snapshot()
    elseif event == "PLAYER_LOGOUT" then
        Snapshot()
    elseif event == "BANKFRAME_OPENED" then
        T.bankOpen = true
        T.CaptureBank()
    elseif event == "BANKFRAME_CLOSED" then
        T.bankOpen = false
        if T.OnBankClosed and T.IsEnabled() then T.OnBankClosed() end
    elseif event == "MAIL_SHOW" then
        T.mailOpen = true
        T.CaptureMail()
    elseif event == "MAIL_CLOSED" then
        T.mailOpen = false
    elseif event == "MODIFIER_STATE_CHANGED" then
        if not (MarketSync.IsSafeString and MarketSync.IsSafeString(key)) then return end
        local modifier = MarketSyncDB and MarketSyncDB.TooltipModifier or "SHIFT"
        if key:find(modifier, 1, true) and MarketSync.RefreshActiveTooltip then MarketSync.RefreshActiveTooltip() end
    else
        ScheduleSnapshot()
    end
end)
