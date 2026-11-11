-- Local inventory and transaction facts. Market quotes are never acquisition costs.
MarketSync = MarketSync or {}
local I = { recentTransactions = {}, recentObservations = {} }
MarketSync.ItemLedger = I

if not MarketSync.IsLedgerEnabled then
    function MarketSync.IsLedgerEnabled()
        return (MarketSyncDB and MarketSyncDB.EnableLedgerBeta == true) or false
    end
end

if not MarketSync.SetLedgerEnabled then
    function MarketSync.SetLedgerEnabled(enabled)
        if not MarketSyncDB then return end
        MarketSyncDB.EnableLedgerBeta = enabled and true or false
        if enabled then
            local t = MarketSync.InventoryTracking
            if t and t.CaptureBags then t.CaptureBags() end
            if I.SeedObservedStock then I.SeedObservedStock() end
        end
        if I.Refresh then I.Refresh() end
        local w = MarketSyncItemLedger
        if w and w.Refresh then w:Refresh() end
    end
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = Copy(v) end; return out
end
local function Integer(value, positive)
    value = tonumber(value)
    return value and value == math.floor(value) and value >= (positive and 1 or 0) and value or nil
end
function I.Owner()
    return (UnitName("player") or "Player") .. "-" .. (GetRealmName() or "Realm")
end
function I.Partition()
    local interface = GetBuildInfo and select(4, GetBuildInfo()) or 0
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    if MarketSync.NormalizeSyncRealm then realm = MarketSync.NormalizeSyncRealm(realm) end
    return tostring(interface) .. ":" .. tostring(realm) .. ":" .. tostring(UnitFactionGroup and UnitFactionGroup("player") or "Unknown")
end
function I.Store()
    MarketSyncDB = MarketSyncDB or {}
    MarketSyncDB.ItemLedger = MarketSyncDB.ItemLedger or { version = 1, nextID = 0, characters = {}, transactions = {}, seen = {}, lots = {}, reservations = {} }
    return MarketSyncDB.ItemLedger
end
local function ID()
    local s = I.Store(); s.nextID = s.nextID + 1; return s.nextID
end
function I.Key(link)
    local id = tonumber(link) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    if not id then return nil end
    local suffix = type(link) == "string" and tonumber(link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:|]+)")) or 0
    return tostring(id) .. ":" .. tostring(suffix or 0), id
end

I.batchDepth = 0
I.batchNeedsNotify = false

function I.BeginBatch()
    I.batchDepth = (I.batchDepth or 0) + 1
end

function I.EndBatch()
    if not I.batchDepth or I.batchDepth <= 0 then
        I.batchDepth = 0
        return
    end
    I.batchDepth = I.batchDepth - 1
    if I.batchDepth == 0 and I.batchNeedsNotify then
        I.batchNeedsNotify = false
        if I.Refresh then I.Refresh() end
    end
end

local function Notify()
    if I.batchDepth and I.batchDepth > 0 then
        I.batchNeedsNotify = true
        return
    end
    if I.Refresh then I.Refresh() end
end
function I.Get(id) return I.Store().transactions[tonumber(id)] end
function I.List()
    local out = {}
    for _, tx in pairs(I.Store().transactions) do
        if tx.owner == I.Owner() and tx.partition == I.Partition() then out[#out + 1] = tx end
    end
    table.sort(out, function(a, b) return a.id > b.id end); return out
end
local function Items(items)
    local out = {}
    for _, item in ipairs(items or {}) do
        local key, id = I.Key(item.link or item.itemID)
        local qty = Integer(item.qty, true)
        if not key or not qty then return nil end
        out[#out + 1] = { key = item.key or key, itemID = id, qty = qty, link = item.link }
    end
    return out
end
local function Reserved(lotID)
    local count = 0
    for _, reservation in pairs(I.Store().reservations) do
        for _, part in ipairs(reservation.parts) do if part.lotID == lotID then count = count + part.qty end end
    end
    return count
end
local function Take(owner, partition, item, customerJob, ignoreReservations)
    local parts, remaining = {}, item.qty
    for _, lot in ipairs(I.Store().lots) do
        if lot.owner == owner and lot.partition == partition and lot.key == item.key and not lot.inTransit
            and lot.customerJob == customerJob then
            local available = math.max(0, lot.qty - (ignoreReservations and 0 or Reserved(lot.id)))
            local qty = math.min(remaining, available)
            if qty > 0 then
                parts[#parts + 1] = { lotID = lot.id, qty = qty, unitCost = lot.unitCost, customerJob = lot.customerJob }
                lot.qty = lot.qty - qty; remaining = remaining - qty
            end
        end
        if remaining == 0 then break end
    end
    if remaining > 0 then parts[#parts + 1] = { qty = remaining, unknown = true, customerJob = customerJob } end
    return parts
end
function I.Record(kind, options)
    if MarketSync.IsLedgerEnabled and not MarketSync.IsLedgerEnabled() then
        return nil, "ledger_disabled"
    end
    options = options or {}
    local incoming, outgoing = Items(options.incoming), Items(options.outgoing)
    local cashIn, cashOut, fee = Integer(options.cashIn or 0), Integer(options.cashOut or 0), Integer(options.fee or 0)
    if not incoming or not outgoing or not cashIn or not cashOut or not fee then return nil, "Invalid quantities or copper values." end
    local s = I.Store()
    if options.token and s.seen[options.token] then return I.Get(s.seen[options.token]), "duplicate" end
    local tx = { id = ID(), kind = kind, owner = I.Owner(), partition = I.Partition(), at = time(),
        incoming = incoming, outgoing = outgoing, cashIn = cashIn, cashOut = cashOut, fee = fee,
        counterparty = options.counterparty, evidence = options.evidence or "manual", state = options.state or "confirmed",
        classification = "unassigned", lots = {}, consumed = {}, metadata = Copy(options.metadata or {}) }
    tx.inTransit = options.inTransit == true
    if options.estimatedValue then tx.estimatedValue = Copy(options.estimatedValue) end
    if not tx.estimatedValue and kind ~= "inventory observation" and MarketSync.GetAuctionPrice then
        tx.estimatedValue = {}
        for _, direction in ipairs({ incoming, outgoing }) do for _, item in ipairs(direction) do
            local price = tonumber(MarketSync.GetAuctionPrice(item.link or item.itemID))
            if price and price > 0 then tx.estimatedValue[item.key] = { unitPrice = price, quotedAt = time(), source = "saved market quote" } end
        end end
    end
    for _, item in ipairs(outgoing) do
        if options.preConsumed and options.preConsumed[item.key] then
            tx.consumed[item.key] = Copy(options.preConsumed[item.key])
        else
        local customerStock = false
        if not options.customerJob then
            for _, lot in ipairs(s.lots) do
                if lot.owner == tx.owner and lot.partition == tx.partition and lot.key == item.key and lot.customerJob and lot.qty > 0 then customerStock = true end
            end
        end
        if customerStock then
            tx.metadata.custodyPending = true
            tx.consumed[item.key] = { { qty = item.qty, unknown = true } }
        else tx.consumed[item.key] = Take(tx.owner, tx.partition, item, options.customerJob) end
        end
    end
    for _, item in ipairs(incoming) do
        -- A delayed confirmation may follow the inventory snapshot. Reclassify
        -- the newly observed units instead of creating a second copy.
        if kind ~= "unattributed inventory" and kind ~= "opening inventory" and not options.inTransit then
            local remaining = item.qty
            for _, observed in ipairs(s.lots) do
                local source = s.transactions[observed.txID]
                if source and source.kind == "unattributed inventory" and source.owner == tx.owner and source.partition == tx.partition
                    and observed.key == item.key and tx.at - source.at <= 5 and Reserved(observed.id) == 0 then
                    local qty = math.min(remaining, observed.qty); observed.qty = observed.qty - qty; remaining = remaining - qty
                    source.metadata.confirmedBy = tx.id
                end
                if remaining == 0 then break end
            end
        end
        local lot = { id = ID(), txID = tx.id, owner = tx.owner, partition = tx.partition, key = item.key,
            itemID = item.itemID, qty = item.qty, originalQty = item.qty, customerJob = options.customerJob,
            inTransit = options.inTransit == true }
        if #incoming == 1 and options.actualCost ~= nil and Integer(options.actualCost) then lot.unitCost = options.actualCost / item.qty end
        s.lots[#s.lots + 1] = lot; tx.lots[#tx.lots + 1] = lot.id
    end
    s.transactions[tx.id] = tx
    I.recentTransactions[#I.recentTransactions + 1] = tx.id
    if #I.recentTransactions > 256 then table.remove(I.recentTransactions, 1) end
    if kind == "inventory observation" then
        I.recentObservations[#I.recentObservations + 1] = tx.id
        if #I.recentObservations > 64 then table.remove(I.recentObservations, 1) end
    end
    if options.token then s.seen[options.token] = tx.id end
    for _, id in ipairs(I.recentObservations) do
        local observation = I.Get(id)
        if observation and observation.owner == tx.owner and observation.partition == tx.partition and math.abs(observation.at - tx.at) <= 5 then I.Reconcile(observation) end
    end
    if I.MatchOwnTransfer and (kind == "mail collected" or kind == "mail sent") then I.MatchOwnTransfer(tx) end
    if I.AutoTagMaterials and tx.state == "confirmed" and #tx.incoming > 0 then I.AutoTagMaterials(tx) end
    if I.AutoMatchGuildCraft and tx.state == "confirmed" and (kind == "trade" or kind == "mail sent") and #tx.outgoing > 0 then I.AutoMatchGuildCraft(tx) end
    Notify(); return tx
end
function I.Lot(id)
    for _, lot in ipairs(I.Store().lots) do if lot.id == id then return lot end end
end
function I.Cost(lotID, visited)
    local lot = I.Lot(lotID); if not lot then return nil end
    visited = visited or {}; if visited[lotID] then return nil end; visited[lotID] = true
    if lot.sourceLotID then return I.Cost(lot.sourceLotID, visited) end
    return lot.unitCost
end
function I.SetCost(txID, totalCopper)
    local tx = I.Get(txID); totalCopper = Integer(totalCopper)
    if not tx or tx.owner ~= I.Owner() or tx.partition ~= I.Partition() or #tx.lots ~= 1 or not totalCopper then return false end
    local lot = I.Lot(tx.lots[1])
    if lot.qty ~= lot.originalQty or Reserved(lot.id) > 0 or lot.customerJob then return false, "Used, reserved or customer-owned lots require review." end
    lot.unitCost = totalCopper / lot.originalQty
    lot.sourceLotID = nil
    tx.metadata.costCorrection = { copper = totalCopper, at = time() }; Notify(); return true
end
function I.Snapshot(storage, items, options)
    options = options or {}
    local owner, partition, s = I.Owner(), I.Partition(), I.Store()
    local identity = partition .. ":" .. owner
    local character = s.characters[identity] or { storage = {} }; s.characters[identity] = character
    character.partition, character.name, character.owner = partition, owner, owner
    local old = character.storage[storage]
    local snapshot = { at = time(), items = Copy(items), complete = options.complete ~= false }
    character.storage[storage] = snapshot
    if storage == "equipped" or (MarketSync.IsLedgerEnabled and not MarketSync.IsLedgerEnabled()) then
        Notify(); return snapshot
    end
    if not old and storage ~= "mail" then
        -- Existing inventory has an unknown historical cost, not a free cost.
        I.BeginBatch()
        for key, item in pairs(items) do
            local known = 0
            for _, lot in ipairs(s.lots) do if lot.owner == owner and lot.partition == partition and lot.key == key and not lot.inTransit then known = known + lot.qty end end
            local observed = 0
            for location, data in pairs(character.storage) do if location ~= "mail" and location ~= "equipped" then observed = observed + (data.items[key] and data.items[key].qty or 0) end end
            if observed > known then I.Record("opening inventory", { incoming = { { link = item.link, itemID = item.itemID, qty = observed - known } }, evidence = "initial storage snapshot" }) end
        end
        I.EndBatch()
    end
    -- Snapshot differences describe unknown movement, never an inferred purchase.
    -- Internal swaps on the same character (e.g. ItemRack equipping/unequipping gear or moving slots)
    -- produce zero net possession change and are never recorded as observation records.
    if old and storage ~= "mail" then
        local delta, keys = {}, {}
        local oldEquipped = (storage == "bags" and character.storage["equipped"] and character.storage["equipped"].items) or nil
        local newEquipped = (storage == "bags" and options.equipped) or nil
        for key in pairs(old.items) do keys[key] = true end
        for key in pairs(items) do keys[key] = true end
        if newEquipped and oldEquipped then
            for key in pairs(oldEquipped) do keys[key] = true end
            for key in pairs(newEquipped) do keys[key] = true end
        end
        for key in pairs(keys) do
            local bagQty = (items[key] and items[key].qty or 0) - (old.items[key] and old.items[key].qty or 0)
            local eqQty = 0
            if newEquipped and oldEquipped then
                eqQty = (newEquipped[key] and newEquipped[key].qty or 0) - (oldEquipped[key] and oldEquipped[key].qty or 0)
            end
            local qty = bagQty + eqQty
            if qty ~= 0 then delta[key] = qty end
        end
        if next(delta) then
            local tx = I.Record("inventory observation", { state = "unresolved", evidence = "storage snapshot",
                metadata = { storage = storage, delta = delta, previousAt = old.at } })
            I.Reconcile(tx)
        end
    end
    Notify(); return snapshot
end
function I.Reconcile(observation)
    if MarketSync.IsLedgerEnabled and not MarketSync.IsLedgerEnabled() then return end
    if not observation or observation.kind ~= "inventory observation" then return end
    local remaining = Copy(observation.metadata.delta)
    local links = {}
    for _, id in ipairs(I.recentTransactions) do
        local tx = I.Get(id)
        if tx and tx.id ~= observation.id and tx.state == "confirmed" and tx.kind ~= "inventory observation" and tx.kind ~= "opening inventory"
            and tx.owner == observation.owner and tx.partition == observation.partition
            and math.abs(tx.at - observation.at) <= 5 and not tx.inTransit and observation.metadata.storage == "bags" then
            tx.observationClaims = tx.observationClaims or {}
            for _, direction in ipairs({ { tx.incoming, 1 }, { tx.outgoing, -1 } }) do
                for _, item in ipairs(direction[1]) do
                    local qty = remaining[item.key] or 0
                    local claimKey = item.key .. ":" .. direction[2]
                    local claims = tx.observationClaims[claimKey] or {}; tx.observationClaims[claimKey] = claims
                    claims[observation.id] = nil
                    local used = 0; for other, count in pairs(claims) do if other ~= observation.id then used = used + count end end
                    local available = math.max(0, item.qty - used)
                    if qty * direction[2] > 0 then
                        local applied = math.min(math.abs(qty), available)
                        remaining[item.key] = qty - direction[2] * applied
                        claims[observation.id] = applied
                        if applied > 0 then links[tx.id] = true end
                    end
                end
            end
        end
    end
    observation.metadata.unresolved = remaining; observation.metadata.links = links
    local unresolved = false; for _, qty in pairs(remaining) do if qty ~= 0 then unresolved = true end end
    observation.state = unresolved and "unresolved" or "reconciled"
end
function I.Holdings(itemID)
    local out = {}
    for _, character in pairs(I.Store().characters) do
        if character.partition == I.Partition() then
            for storage, snapshot in pairs(character.storage) do
                local qty = 0
                for _, item in pairs(snapshot.items) do if item.itemID == tonumber(itemID) then qty = qty + item.qty end end
                if qty > 0 then out[#out + 1] = { owner = character.owner, storage = storage, qty = qty, at = snapshot.at, complete = snapshot.complete } end
            end
        end
    end
    table.sort(out, function(a,b) return a.owner == b.owner and a.storage < b.storage or a.owner < b.owner end)
    return out
end
function I.Reserve(jobID, key, quantity)
    quantity = Integer(quantity, true); if not quantity then return false end
    local s, owner, partition = I.Store(), I.Owner(), I.Partition()
    local token = partition .. ":" .. owner .. ":" .. tostring(jobID) .. ":" .. key
    if s.reservations[token] then return false, "This material is already reserved." end
    local observed, claimed = 0, 0
    local character = s.characters[partition .. ":" .. owner]
    for storage, snapshot in pairs(character and character.storage or {}) do
        if storage ~= "mail" and storage ~= "equipped" then observed = observed + (snapshot.items[key] and snapshot.items[key].qty or 0) end
    end
    for _, r in pairs(s.reservations) do if r.owner == owner and r.partition == partition and r.key == key then for _, part in ipairs(r.parts) do claimed = claimed + part.qty end end end
    if observed - claimed < quantity then return false, "Refresh this character's bags/bank before reserving this quantity." end
    local parts, remaining = {}, quantity
    for _, lot in ipairs(s.lots) do
        if lot.owner == owner and lot.partition == partition and lot.key == key and not lot.inTransit
            and (not lot.customerJob or lot.customerJob == jobID) then
            local qty = math.min(remaining, math.max(0, lot.qty - Reserved(lot.id)))
            if qty > 0 then parts[#parts + 1] = { lotID = lot.id, qty = qty }; remaining = remaining - qty end
        end
        if remaining == 0 then break end
    end
    if remaining > 0 then return false, "Not enough observed, unreserved material on this character." end
    s.reservations[token] = { owner = owner, partition = partition, jobID = jobID, key = key, parts = parts }; Notify(); return true
end
function I.Release(jobID, consume)
    local s = I.Store()
    for token, reservation in pairs(s.reservations) do
        if reservation.owner == I.Owner() and reservation.partition == I.Partition() and reservation.jobID == jobID then
            if consume then for _, part in ipairs(reservation.parts) do local lot = I.Lot(part.lotID); if lot then lot.qty = math.max(0, lot.qty - part.qty) end end end
            s.reservations[token] = nil
        end
    end
end
function I.UpdateReservations(job)
    for token, reservation in pairs(I.Store().reservations) do
        if reservation.owner == I.Owner() and reservation.partition == I.Partition() and reservation.jobID == job.id then
            local id = tonumber(reservation.key:match("^(%d+)"))
            local material = (job.plan.provided or {})[id]
            local qty = 0; for _, part in ipairs(reservation.parts) do qty = qty + part.qty end
            if not material or material.qty ~= qty then I.Store().reservations[token] = nil end
        end
    end
end
function I.ReservedCost(jobID)
    local paid, unknown, covered = 0, false, {}
    for _, r in pairs(I.Store().reservations) do
        if r.owner == I.Owner() and r.partition == I.Partition() and r.jobID == jobID then
            for _, part in ipairs(r.parts) do
                local id = tonumber(r.key:match("^(%d+)")); covered[id] = (covered[id] or 0) + part.qty
                local lot = I.Lot(part.lotID)
                if lot and not lot.customerJob then
                    local cost = I.Cost(lot.id)
                    if cost == nil then unknown = true else paid = paid + cost * part.qty end
                end
            end
        end
    end
    return paid, unknown, covered
end
local function TransferFits(a, b)
    local remaining = {}
    for _, item in ipairs(a.outgoing) do remaining[item.key] = (remaining[item.key] or 0) + item.qty end
    for key, qty in pairs(a.transferAllocated or {}) do remaining[key] = (remaining[key] or 0) - qty end
    local requested = {}
    for _, item in ipairs(b.incoming) do requested[item.key] = (requested[item.key] or 0) + item.qty end
    for key, qty in pairs(requested) do if qty > (remaining[key] or 0) then return nil end end
    if b.cashIn > a.cashOut - (a.transferGold or 0) or a.cashIn > 0 or b.cashOut > 0 then return nil end
    if not next(requested) and b.cashIn <= 0 then return nil end
    return requested, remaining
end
function I.LinkTransfer(outID, inID)
    local a, b, s = I.Get(outID), I.Get(inID), I.Store()
    if not a or not b or a.transferID or b.transferID or (a.owner == b.owner and not b.metadata.returned) or a.partition ~= b.partition
        or (a.owner ~= I.Owner() and b.owner ~= I.Owner()) or a.serviceID or b.serviceID or a.metadata.custodyPending then return false end
    if not s.characters[a.partition .. ":" .. a.owner] or not s.characters[b.partition .. ":" .. b.owner] then return false end
    local requested, remaining = TransferFits(a, b); if not requested then return false end
    for _, lotID in ipairs(b.lots) do
        local lot = I.Lot(lotID); if lot.qty ~= lot.originalQty or Reserved(lotID) > 0 then return false end
    end
    -- Preserve individual cost lots; never replace mixed costs with a guessed price.
    for _, lotID in ipairs(b.lots) do I.Lot(lotID).qty = 0 end
    for key, qty in pairs(requested) do
        local parts = a.consumed[key] or { { qty = qty, unknown = true } }
        local skip, needed = (a.transferAllocated or {})[key] or 0, qty
        for _, part in ipairs(parts) do
            local offset = math.min(skip, part.qty); skip = skip - offset
            local used = math.min(needed, part.qty - offset)
            if used > 0 then
                s.lots[#s.lots + 1] = { id = ID(), txID = b.id, owner = b.owner, partition = b.partition, key = key,
                    itemID = tonumber(key:match("^(%d+)")), qty = used, originalQty = used, unitCost = part.unitCost, sourceLotID = part.lotID }
                b.lots[#b.lots + 1] = s.lots[#s.lots].id; needed = needed - used
            end
        end
        a.transferAllocated = a.transferAllocated or {}; a.transferAllocated[key] = (a.transferAllocated[key] or 0) + qty
        remaining[key] = remaining[key] - qty
    end
    a.transferGold = (a.transferGold or 0) + b.cashIn
    a.transferReceipts = a.transferReceipts or {}; a.transferReceipts[#a.transferReceipts + 1] = b.id
    local complete = a.transferGold == a.cashOut
    for _, qty in pairs(remaining) do if qty ~= 0 then complete = false end end
    if complete then a.transferID = b.id end
    b.transferID = a.id; a.classification, b.classification = "own transfer", "own transfer"
    Notify(); return true
end
function I.MatchOwnTransfer(tx)
    if tx.transferID or tx.serviceID then return false end
    local function NamesMatch(name, owner)
        if not name then return false end
        name, owner = name:lower():gsub("%s", ""), owner:lower():gsub("%s", "")
        return name == owner or (not name:find("-", 1, true) and owner:match("^([^%-]+)") == name)
    end
    local candidates = {}
    for _, other in pairs(I.Store().transactions) do
        if other.owner ~= tx.owner and other.partition == tx.partition and not other.transferID and not other.serviceID
            and NamesMatch(tx.counterparty, other.owner) and NamesMatch(other.counterparty, tx.owner) then
            local a, b = tx.kind == "mail sent" and tx or other, tx.kind == "mail sent" and other or tx
            if a.kind == "mail sent" and b.kind == "mail collected" and a.at <= b.at then
                if TransferFits(a, b) then candidates[#candidates + 1] = { a.id, b.id } end
            end
        end
    end
    if #candidates == 1 then return I.LinkTransfer(candidates[1][1], candidates[1][2]) end
    if #candidates > 1 then tx.metadata.ambiguousTransfer = true end
    return false
end
function I.LinkService(txID, jobID, role)
    local tx, L = I.Get(txID), MarketSync.CraftLedger
    local job = L and L.Get(jobID)
    local roles = { materials = true, materialsReturn = true, delivery = true, payment = true, expense = true, deposit = true, refund = true, earnedRefund = true }
    if not tx or tx.owner ~= I.Owner() or tx.partition ~= I.Partition() or (tx.serviceID and tx.serviceID ~= jobID) or tx.transferID or tx.transferReceipts
        or not job or job.owner ~= I.Owner() or job.kind ~= "service" or not roles[role] or tx.state ~= "confirmed" then return false end
    if tx.serviceRoles and tx.serviceRoles[role] then return false, "This exchange role is already linked." end
    if role == "payment" and tx.serviceRoles and tx.serviceRoles.deposit or role == "deposit" and tx.serviceRoles and tx.serviceRoles.payment then
        return false, "A deposit and earned payment cannot claim the same gold. Review or split the exchange."
    end
    if role == "materials" then
        if #tx.incoming == 0 then return false end
        for _, lotID in ipairs(tx.lots) do
            local lot = I.Lot(lotID)
            if not lot or lot.qty ~= lot.originalQty or Reserved(lotID) > 0 then return false, "Materials were already used or reserved." end
        end
        for _, lotID in ipairs(tx.lots) do I.Lot(lotID).customerJob = jobID end
        job.supplied = job.supplied or {}
        for _, item in ipairs(tx.incoming) do job.supplied[item.itemID] = (job.supplied[item.itemID] or 0) + item.qty end
    elseif role == "materialsReturn" then
        if #tx.outgoing == 0 then return false end
        for _, item in ipairs(tx.outgoing) do
            local supplied = (job.supplied or {})[item.itemID] or 0
            if supplied < item.qty then return false end
            for _, part in ipairs(tx.consumed[item.key] or {}) do if part.lotID then return false end end
            local available = 0
            for _, lot in ipairs(I.Store().lots) do if lot.owner == I.Owner() and lot.partition == I.Partition() and lot.customerJob == jobID and lot.key == item.key then available = available + lot.qty end end
            if available < item.qty then return false end
        end
        for _, item in ipairs(tx.outgoing) do
            tx.consumed[item.key] = Take(tx.owner, tx.partition, item, jobID)
            job.supplied[item.itemID] = job.supplied[item.itemID] - item.qty
        end
        tx.metadata.custodyPending = nil
    elseif role == "delivery" then
        if job.craftedQty <= 0 then return false, "Craft the order before linking its delivery." end
        local qty = 0
        for _, item in ipairs(tx.outgoing) do if item.itemID == job.itemID then qty = qty + item.qty end end
        if qty == 0 or (job.deliveredQty or 0) + qty > job.craftedQty then return false end
        for _, item in ipairs(tx.outgoing) do
            if item.itemID == job.itemID then
                for _, part in ipairs(tx.consumed[item.key] or {}) do
                    if part.lotID then return false, "This delivery consumed your own stock; review the item attribution." end
                end
                local available = 0
                for _, lot in ipairs(I.Store().lots) do if lot.owner == I.Owner() and lot.partition == I.Partition() and lot.customerJob == jobID and lot.key == item.key then available = available + lot.qty end end
                if available < item.qty then return false, "Customer output was not observed in custody." end
            end
        end
        for _, item in ipairs(tx.outgoing) do if item.itemID == job.itemID then tx.consumed[item.key] = Take(tx.owner, tx.partition, item, jobID) end end
        tx.metadata.custodyPending = nil
        job.deliveredQty = (job.deliveredQty or 0) + qty
    elseif role == "payment" and tx.cashIn <= 0 then return false
    elseif role == "expense" and (#tx.incoming > 0 or tx.cashOut + tx.fee <= 0) then return false, "Acquired items use cost lots or purchase receipts; do not record their cost twice."
    elseif role == "refund" and tx.cashOut <= 0 then return false
    elseif role == "earnedRefund" and tx.cashOut <= 0 then return false
    elseif role == "deposit" and tx.cashIn <= 0 then return false end
    tx.serviceID, tx.serviceRole, tx.classification = jobID, role, "customer service"
    tx.serviceRoles = tx.serviceRoles or {}; tx.serviceRoles[role] = true
    job.transactions = job.transactions or {}
    local linked = false; for _, id in ipairs(job.transactions) do if id == tx.id then linked = true end end
    if not linked then job.transactions[#job.transactions + 1] = tx.id end
    if L.RefreshShopping and job.status ~= "Crafted" then L.RefreshShopping(job) end
    if L.Refresh then L.Refresh() end; Notify(); return true
end
function I.MatchPendingPurchase(tx)
    if not tx or tx.kind ~= "mail collected" or #tx.incoming ~= 1 or tx.cashOut > 0 then return false end
    local item, candidates = tx.incoming[1], {}
    -- An auction invoice, not merely a familiar sender name, identifies auction mail.
    if not tx.metadata.invoice or tx.metadata.invoice.kind ~= "buyer" then return false end
    for _, purchase in ipairs(I.List()) do
        if purchase.kind == "auction purchase" and not purchase.collectedID and #purchase.incoming == 1
            and purchase.incoming[1].key == item.key and purchase.incoming[1].qty == item.qty then candidates[#candidates + 1] = purchase end
    end
    if #candidates ~= 1 then tx.metadata.unresolvedPurchase = true; return false end
    local purchase = candidates[1]
    local source, destination = I.Lot(purchase.lots[1]), I.Lot(tx.lots[1])
    if not source or not destination or destination.qty ~= destination.originalQty then return false end
    destination.unitCost = source.unitCost; source.qty = 0
    purchase.collectedID, tx.purchaseID = tx.id, purchase.id; return true
end
local function ConsumeInputs(job, recipe, crafts)
    local outgoing, consumed = {}, {}
    for _, mat in ipairs(recipe.mats or {}) do
        local key = I.Key(mat.itemID)
        local needed = math.max(0, (tonumber(mat.qty) or 0) * crafts)
        local parts = {}
        -- Reserved user stock carries its actual cost through intermediate crafts.
        for token, r in pairs(I.Store().reservations) do
            if r.owner == I.Owner() and r.partition == I.Partition() and r.jobID == job.id and r.key == key then
                for _, part in ipairs(r.parts) do
                    local lot = I.Lot(part.lotID); local qty = math.min(needed, part.qty, lot and lot.qty or 0)
                    if qty > 0 then
                        lot.qty, part.qty, needed = lot.qty - qty, part.qty - qty, needed - qty
                        parts[#parts + 1] = { lotID = lot.id, qty = qty, unitCost = lot.unitCost, customerJob = lot.customerJob }
                        job.stockCoverage = job.stockCoverage or {}; job.stockCoverage[mat.itemID] = (job.stockCoverage[mat.itemID] or 0) + qty
                        if not lot.customerJob then
                            local cost = I.Cost(lot.id)
                            if cost == nil then job.unknownStockCost = true else job.stockCost = (job.stockCost or 0) + cost * qty end
                        end
                    end
                end
                local remaining = 0; for _, part in ipairs(r.parts) do remaining = remaining + part.qty end
                if remaining == 0 then I.Store().reservations[token] = nil end
            end
        end
        if needed > 0 and job.kind == "service" then
            local available = 0
            for _, lot in ipairs(I.Store().lots) do if lot.owner == I.Owner() and lot.partition == I.Partition() and lot.customerJob == job.id and lot.key == key then available = available + lot.qty end end
            local qty = math.min(needed, available)
            if qty > 0 then
                for _, part in ipairs(Take(I.Owner(), I.Partition(), { key = key, qty = qty }, job.id)) do parts[#parts + 1] = part end
                needed = needed - qty
            end
        end
        if needed > 0 then
            for _, part in ipairs(Take(I.Owner(), I.Partition(), { key = key, qty = needed })) do parts[#parts + 1] = part end
        end
        local count = (tonumber(mat.qty) or 0) * crafts
        if count > 0 then outgoing[#outgoing + 1] = { itemID = mat.itemID, qty = count }; consumed[key] = parts end
    end
    return outgoing, consumed
end
function I.RecordCraft(job, quantity)
    if not job.itemID then return I.Record("profession action", { evidence = "manual completion", metadata = { jobID = job.id, qty = quantity } }) end
    local output = { itemID = job.itemID, qty = quantity }
    local yield = math.max(1, tonumber(job.recipe.outputQty) or 1)
    local crafts = math.floor(job.craftedQty / yield) - math.floor((job.craftedQty - quantity) / yield)
    local outgoing, consumed = ConsumeInputs(job, job.recipe, crafts)
    local tx = I.Record("crafted output", { incoming = { output }, outgoing = outgoing, preConsumed = consumed, customerJob = job.kind == "service" and job.id or nil,
        evidence = "confirmed crafting output", metadata = { jobID = job.id } })
    return tx
end
function I.RecordComponent(job, recipe, itemID, quantity)
    local yield = math.max(1, tonumber(recipe.outputQty) or 1)
    local previous = (job.componentsCrafted or {})[itemID] or 0
    local crafts = math.floor((previous + quantity) / yield) - math.floor(previous / yield)
    local outgoing, consumed = ConsumeInputs(job, recipe, crafts)
    job.componentsCrafted = job.componentsCrafted or {}; job.componentsCrafted[itemID] = previous + quantity
    return I.Record("crafted component", { incoming = { { itemID = itemID, qty = quantity } }, outgoing = outgoing, preConsumed = consumed,
        customerJob = job.kind == "service" and job.id or nil, evidence = "confirmed intermediate craft", metadata = { jobID = job.id } })
end
function I.UpdateCraftCosts(job)
    if job.kind == "service" then return end
    local totals = MarketSync.CraftLedger.Totals(job)
    for _, lot in ipairs(I.Store().lots) do
        local tx = I.Get(lot.txID)
        if lot.owner == I.Owner() and lot.partition == I.Partition() and tx and tx.kind == "crafted output" and tx.metadata.jobID == job.id then
            lot.unitCost = job.status == "Crafted" and not totals.unknownCost and totals.paid / job.outputQty or nil
        end
    end
end
function I.AttributeOwn(txID)
    local tx = I.Get(txID)
    if not tx or tx.owner ~= I.Owner() or tx.partition ~= I.Partition() or not tx.metadata.custodyPending or tx.serviceID then return false end
    for _, item in ipairs(tx.outgoing) do tx.consumed[item.key] = Take(tx.owner, tx.partition, item) end
    tx.metadata.custodyPending = nil; Notify(); return true
end
function I.SeedObservedStock()
    if MarketSync.IsLedgerEnabled and not MarketSync.IsLedgerEnabled() then return end
    local character = I.Store().characters[I.Partition() .. ":" .. I.Owner()]
    if not character then return end
    local observed = {}
    local equippedItems = (character.storage["equipped"] and character.storage["equipped"].items) or {}
    for storage, snapshot in pairs(character.storage) do
        if storage ~= "mail" and storage ~= "equipped" then for key, item in pairs(snapshot.items) do
            local entry = observed[key] or { itemID = item.itemID, link = item.link, qty = 0 }
            entry.qty = entry.qty + item.qty; observed[key] = entry
        end end
    end
    I.BeginBatch()
    for key, item in pairs(observed) do
        local known = 0
        for _, lot in ipairs(I.Store().lots) do if lot.owner == I.Owner() and lot.partition == I.Partition() and lot.key == key and not lot.inTransit then known = known + lot.qty end end
        if item.qty > known then
            I.Record("unattributed inventory", { incoming = { { itemID = item.itemID, link = item.link, qty = item.qty - known } }, evidence = "inventory reconciliation", state = "unresolved" })
        end
    end
    I.EndBatch()
    -- Unexplained losses invalidate costs/reservations rather than silently
    -- assigning an old cost to replacement stock. Customer custody is reviewed
    -- separately and is never converted into the user's property here.
    local keys = {}; for _, lot in ipairs(I.Store().lots) do if lot.owner == I.Owner() and lot.partition == I.Partition() and not lot.inTransit then keys[lot.key] = true end end
    for key in pairs(keys) do
        local known = 0
        for _, lot in ipairs(I.Store().lots) do if lot.owner == I.Owner() and lot.partition == I.Partition() and lot.key == key and not lot.inTransit then known = known + lot.qty end end
        local totalPossessed = (observed[key] and observed[key].qty or 0) + (equippedItems[key] and equippedItems[key].qty or 0)
        local loss = known - totalPossessed
        if loss > 0 then
            for token, r in pairs(I.Store().reservations) do
                if r.owner == I.Owner() and r.partition == I.Partition() and r.key == key then
                    local job = MarketSync.CraftLedger and MarketSync.CraftLedger.Get(r.jobID)
                    if job then job.unknownStockCost = true end
                    I.Store().reservations[token] = nil
                end
            end
            for _, lot in ipairs(I.Store().lots) do
                if lot.owner == I.Owner() and lot.partition == I.Partition() and lot.key == key and not lot.customerJob and not lot.inTransit then
                    lot.unitCost = nil
                    local qty = math.min(loss, lot.qty); lot.qty = lot.qty - qty; loss = loss - qty
                end
            end
        end
    end
end
function I.ResolveRecord(txID, mode, totalCopper)
    local tx = I.Get(txID)
    if not tx or tx.owner ~= I.Owner() or tx.partition ~= I.Partition() then return false, "Select one of this character's records first." end
    if mode == "set_cost" then
        totalCopper = Integer(totalCopper)
        if not totalCopper then return false, "Enter a valid non-negative copper/gold amount." end
        if #tx.lots == 1 then
            local ok, reason = I.SetCost(txID, totalCopper)
            if not ok then return false, reason end
        elseif #tx.lots > 1 then
            local totalUnits = 0
            for _, lotID in ipairs(tx.lots) do
                local lot = I.Lot(lotID)
                if not lot or lot.qty ~= lot.originalQty or Reserved(lot.id) > 0 or lot.customerJob then
                    return false, "Used, reserved or customer-owned lots require review."
                end
                totalUnits = totalUnits + lot.originalQty
            end
            if totalUnits <= 0 then return false end
            for _, lotID in ipairs(tx.lots) do
                local lot = I.Lot(lotID)
                lot.unitCost = totalCopper / totalUnits
                lot.sourceLotID = nil
            end
            tx.metadata.costCorrection = { copper = totalCopper, at = time() }
        end
        tx.state = "confirmed"
        tx.classification = totalCopper == 0 and "self-found / free" or "manual cost"
        Notify()
        return true
    elseif mode == "acknowledge" then
        if tx.metadata and tx.metadata.custodyPending and #tx.outgoing > 0 then
            I.AttributeOwn(txID)
        end
        if tx.metadata and tx.metadata.unresolved then
            tx.metadata.acknowledgedDelta = Copy(tx.metadata.unresolved)
            tx.metadata.unresolved = {}
        end
        if tx.state == "unresolved" then
            tx.state = tx.kind == "inventory observation" and "reconciled" or "confirmed"
        end
        if tx.classification == "unassigned" then
            tx.classification = #tx.incoming > 0 and "personal stock" or (#tx.outgoing > 0 and "used / consumed" or "reviewed")
        end
        Notify()
        return true
    elseif mode == "personal_trade" then
        if tx.metadata and tx.metadata.custodyPending and #tx.outgoing > 0 then
            I.AttributeOwn(txID)
        end
        if tx.state == "unresolved" then tx.state = "confirmed" end
        tx.classification = "personal trade"
        Notify()
        return true
    end
    return false, "Unsupported resolution mode."
end

function I.ResolveAllObservations()
    local owner, partition = I.Owner(), I.Partition()
    local toResolve = {}
    for _, tx in pairs(I.Store().transactions) do
        if tx.owner == owner and tx.partition == partition and tx.state == "unresolved"
            and (tx.kind == "inventory observation" or tx.kind == "unattributed inventory")
            and not (tx.metadata and tx.metadata.custodyPending) and not tx.serviceID and not tx.transferID then
            toResolve[#toResolve + 1] = tx.id
        end
    end

    local count = 0
    I.BeginBatch()
    for _, txID in ipairs(toResolve) do
        if I.ResolveRecord(txID, "acknowledge") then
            count = count + 1
        end
    end
    I.EndBatch()
    return count
end

function I.ServiceTotals(job)
    local result = { earned = 0, expenses = 0, deposits = 0, refunds = 0, earnedRefunds = 0, delivered = job.deliveredQty or 0 }
    for _, id in ipairs(job.transactions or {}) do
        local tx = I.Get(id)
        if tx then
            local roles = tx.serviceRoles or { [tx.serviceRole] = true }
            if roles.payment then result.earned = result.earned + tx.cashIn end
            if roles.expense then result.expenses = result.expenses + tx.cashOut end
            if roles.deposit then result.deposits = result.deposits + tx.cashIn end
            if roles.refund then result.refunds = result.refunds + tx.cashOut end
            if roles.earnedRefund then result.earnedRefunds = result.earnedRefunds + tx.cashOut end
            result.expenses = result.expenses + tx.fee
        end
    end
    return result
end

-- Automatically tag incoming material acquisitions against active craft demand without
-- altering unassigned transaction state or forging customer commissions.
function I.AutoTagMaterials(tx)
    if not tx or not MarketSync.CraftLedger or not MarketSync.CraftLedger.GetItemDemand then return end
    for _, item in ipairs(tx.incoming or {}) do
        local demand = MarketSync.CraftLedger.GetItemDemand(item.itemID)
        if demand and demand.needed > 0 and demand.jobsNeeding and demand.jobsNeeding[1] then
            local primary = demand.jobsNeeding[1].job
            tx.metadata = tx.metadata or {}
            tx.metadata.taggedJobID = primary.id
            tx.metadata.taggedCraftName = primary.name
            tx.metadata.taggedNeed = demand.needed
            return
        end
    end
end

-- Link a zero-cost material receipt, intermediate craft, and output return to the same
-- player/guildmate as a pass-through guild craft so materials do not count as a loss.
function I.LinkGuildCraft(inTxID, outTxID, craftTxID)
    local inTx, outTx = I.Get(inTxID), I.Get(outTxID)
    local craftTx = craftTxID and I.Get(craftTxID) or nil
    if not inTx or not outTx or inTx.id == outTx.id then return false, "Select both the incoming material record and outgoing delivery record." end
    if inTx.owner ~= I.Owner() or outTx.owner ~= I.Owner() or inTx.partition ~= I.Partition() or outTx.partition ~= I.Partition() then return false end
    if inTx.serviceID or outTx.serviceID or inTx.transferID or outTx.transferID then return false, "Already linked to another service or transfer." end
    if #inTx.incoming == 0 or #outTx.outgoing == 0 then return false, "Guild craft requires incoming materials and outgoing crafted items." end
    if (inTx.cashOut or 0) > 0 or (outTx.cashOut or 0) > 0 then return false, "Zero-cost guild craft cannot include gold paid out for materials." end

    for _, lotID in ipairs(inTx.lots or {}) do
        local lot = I.Lot(lotID)
        if lot then
            lot.guildCraft = outTx.id
            lot.unitCost = 0
            lot.qty = 0
        end
    end
    if craftTx and craftTx.owner == I.Owner() and craftTx.partition == I.Partition() then
        for _, lotID in ipairs(craftTx.lots or {}) do
            local lot = I.Lot(lotID)
            if lot then
                lot.guildCraft = outTx.id
                lot.unitCost = 0
                lot.qty = 0
            end
        end
        craftTx.classification = "guild craft"
        craftTx.guildCraftPeer = outTx.id
    end
    outTx.metadata.custodyPending = nil
    inTx.classification = "guild craft"
    outTx.classification = "guild craft"
    inTx.guildCraftPeer = outTx.id
    outTx.guildCraftPeer = inTx.id
    local tip = (inTx.cashIn or 0) + (outTx.cashIn or 0) - (outTx.fee or 0)
    outTx.metadata.guildCraftSummary = {
        customer = outTx.counterparty or inTx.counterparty or "Guildmate",
        inTxID = inTx.id,
        craftTxID = craftTx and craftTx.id or nil,
        tip = tip,
        netCost = 0,
    }
    Notify()
    return true
end

-- Automatically detect ad-hoc zero-cost guild crafts when a player receives materials
-- from a counterparty for 0g, crafts the item (outside a formal Customer Craft job),
-- and returns the crafted output to that same counterparty within 30 minutes.
function I.AutoMatchGuildCraft(outTx)
    if not outTx or outTx.serviceID or outTx.transferID or outTx.classification ~= "unassigned" then return false end
    if not outTx.counterparty or outTx.counterparty == "" or (outTx.cashOut or 0) > 0 or #outTx.outgoing == 0 then return false end

    -- Do not interfere if an explicit Customer Craft service job exists for this counterparty
    local L = MarketSync.CraftLedger
    if L and L.List then
        for _, job in ipairs(L.List()) do
            if job.kind == "service" and job.customer and job.customer:lower() == outTx.counterparty:lower() then
                return false
            end
        end
        for _, job in ipairs(L.List(true)) do
            if job.kind == "service" and job.customer and job.customer:lower() == outTx.counterparty:lower() then
                return false
            end
        end
    end

    local outItem = outTx.outgoing[1]
    if not outItem then return false end
    local windowSec = 1800
    local matchedCraft, matchedIn

    for _, tx in ipairs(I.List()) do
        if tx.id ~= outTx.id and tx.classification == "unassigned" and not tx.serviceID and not tx.transferID
            and math.abs(outTx.at - tx.at) <= windowSec then
            if not matchedCraft and tx.kind == "crafted output" and not tx.metadata.jobID and #tx.incoming > 0 and #tx.outgoing > 0 then
                if tx.incoming[1].itemID == outItem.itemID and tx.incoming[1].qty >= outItem.qty then
                    matchedCraft = tx
                end
            end
        end
    end
    if not matchedCraft then return false end

    local neededMat = matchedCraft.outgoing[1]
    if not neededMat then return false end
    for _, tx in ipairs(I.List()) do
        if tx.id ~= outTx.id and tx.id ~= matchedCraft.id and tx.classification == "unassigned"
            and not tx.serviceID and not tx.transferID and (tx.cashOut or 0) == 0
            and tx.counterparty and tx.counterparty:lower() == outTx.counterparty:lower()
            and math.abs(outTx.at - tx.at) <= windowSec and tx.at <= outTx.at then
            for _, inc in ipairs(tx.incoming or {}) do
                if inc.itemID == neededMat.itemID and inc.qty >= neededMat.qty then
                    matchedIn = tx
                    break
                end
            end
            if matchedIn then break end
        end
    end

    if matchedIn and matchedCraft then
        return I.LinkGuildCraft(matchedIn.id, outTx.id, matchedCraft.id)
    end
    return false
end

-- Evaluate both Actual Profit (vs. FIFO Paid Cost) and Value Gained (vs. Raw Material AH Sell Value)
function I.EvaluateValueGained(tx)
    if not tx then return nil end
    local getPrice = MarketSync.GetAuctionPrice
    local matMarketValue = 0
    local actualPaid = 0
    local unknownActual = false

    for _, mat in ipairs(tx.outgoing or {}) do
        local p = getPrice and tonumber(getPrice(mat.link or mat.itemID))
        if p and p > 0 then
            matMarketValue = matMarketValue + (p * mat.qty)
        elseif tx.estimatedValue and tx.estimatedValue[mat.key] then
            matMarketValue = matMarketValue + (tx.estimatedValue[mat.key].unitPrice * mat.qty)
        end
        for _, part in ipairs((tx.consumed or {})[mat.key] or {}) do
            if part.unknown or part.unitCost == nil then
                if not part.customerJob then unknownActual = true end
            elseif not part.customerJob then
                actualPaid = actualPaid + (part.unitCost * part.qty)
            end
        end
    end

    local outMarketValue = 0
    for _, out in ipairs(tx.incoming or {}) do
        local p = getPrice and tonumber(getPrice(out.link or out.itemID))
        if p and p > 0 then
            outMarketValue = outMarketValue + (p * out.qty)
        elseif tx.estimatedValue and tx.estimatedValue[out.key] then
            outMarketValue = outMarketValue + (tx.estimatedValue[out.key].unitPrice * out.qty)
        end
    end

    local matNetAH = math.floor(matMarketValue * 0.95)
    local outNetAH = math.floor(outMarketValue * 0.95)
    return {
        actualPaid = not unknownActual and math.floor(actualPaid + 0.5) or nil,
        unknownActual = unknownActual,
        matMarketValue = matMarketValue,
        matNetAH = matNetAH,
        outMarketValue = outMarketValue,
        outNetAH = outNetAH,
        valueGainedVsMats = (matMarketValue > 0 and outMarketValue > 0) and (outNetAH - matNetAH) or nil,
        profitVsPaid = (not unknownActual and outMarketValue > 0) and (outNetAH - math.floor(actualPaid + 0.5)) or nil,
    }
end

function I.GetRollupSummary()
    local s = I.Store()
    s.rollups = s.rollups or {}
    local key = I.Partition() .. ":" .. I.Owner()
    s.rollups[key] = s.rollups[key] or {
        trimmedCount = 0,
        cashIn = 0,
        cashOut = 0,
        fees = 0,
        guildCrafts = 0,
        items = {},
    }
    return s.rollups[key]
end

-- Logical tiered compaction: retains full granular transactions within the hot window
-- (default 30 days) and compacts older settled records into lightweight +/- primary rollups.
-- Active FIFO stock lots and unresolved records needing review are never trimmed.
function I.TrimLedger(retentionDays)
    local days = tonumber(retentionDays) or (MarketSyncDB and tonumber(MarketSyncDB.LedgerRetentionDays)) or 30
    if days <= 0 then return 0 end
    local cutoff = time() - (days * 86400)
    local s = I.Store()
    local owner, partition = I.Owner(), I.Partition()
    local rollup = I.GetRollupSummary()
    local trimmed = 0
    local removedTxIDs = {}

    for id, tx in pairs(s.transactions) do
        if tx.owner == owner and tx.partition == partition and (tx.at or 0) < cutoff then
            local needsReview = tx.state == "unresolved" or tx.metadata.custodyPending or (tx.classification == "unassigned" and tx.kind == "trade")
            local hasActiveLots = false
            for _, lotID in ipairs(tx.lots or {}) do
                local lot = I.Lot(lotID)
                if lot and (lot.qty > 0 or Reserved(lot.id) > 0) then
                    hasActiveLots = true
                    break
                end
            end
            local hasActiveJob = false
            if tx.serviceID and MarketSync.CraftLedger and MarketSync.CraftLedger.Get then
                local j = MarketSync.CraftLedger.Get(tx.serviceID)
                if j and j.status ~= "Crafted" then hasActiveJob = true end
            end

            if not needsReview and not hasActiveLots and not hasActiveJob then
                rollup.trimmedCount = (rollup.trimmedCount or 0) + 1
                rollup.cashIn = (rollup.cashIn or 0) + (tx.cashIn or 0)
                rollup.cashOut = (rollup.cashOut or 0) + (tx.cashOut or 0)
                rollup.fees = (rollup.fees or 0) + (tx.fee or 0)
                if tx.classification == "guild craft" then
                    rollup.guildCrafts = (rollup.guildCrafts or 0) + 1
                end
                for _, inc in ipairs(tx.incoming or {}) do
                    local ie = rollup.items[inc.itemID] or { itemID = inc.itemID, inQty = 0, outQty = 0, goldIn = 0, goldOut = 0 }
                    ie.inQty = ie.inQty + (inc.qty or 0)
                    ie.goldOut = ie.goldOut + (tx.cashOut or 0)
                    rollup.items[inc.itemID] = ie
                end
                for _, out in ipairs(tx.outgoing or {}) do
                    local ie = rollup.items[out.itemID] or { itemID = out.itemID, inQty = 0, outQty = 0, goldIn = 0, goldOut = 0 }
                    ie.outQty = ie.outQty + (out.qty or 0)
                    ie.goldIn = ie.goldIn + (tx.cashIn or 0)
                    rollup.items[out.itemID] = ie
                end
                removedTxIDs[id] = true
                s.transactions[id] = nil
                trimmed = trimmed + 1
            end
        end
    end

    if trimmed > 0 then
        local remainingLots = {}
        for _, lot in ipairs(s.lots) do
            if not (removedTxIDs[lot.txID] and (lot.qty or 0) == 0) then
                remainingLots[#remainingLots + 1] = lot
            end
        end
        s.lots = remainingLots
        local remainingRecent = {}
        for _, rID in ipairs(I.recentTransactions) do
            if not removedTxIDs[rID] then remainingRecent[#remainingRecent + 1] = rID end
        end
        I.recentTransactions = remainingRecent
        Notify()
    end
    return trimmed
end
