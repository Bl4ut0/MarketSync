-- =============================================================
-- MarketSync - Browse Panel
-- Shared browse panel for Personal Scan and Guild Sync tabs
-- =============================================================

local NUM_RESULTS_TO_DISPLAY = 8
local RESULT_HEIGHT = 37
local FILTER_HEIGHT = 20

-- ---- Money Formatter (colorized with g/s/c) ----
local function FormatMoney(copper)
    if not copper or copper == 0 then return "|cff888888N/A|r" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local str = ""
    if g > 0 then str = str .. "|cffffd700" .. g .. "|r|cffffd700g|r " end
    if s > 0 or g > 0 then str = str .. "|cffc0c0c0" .. s .. "|r|cffc0c0c0s|r " end
    str = str .. "|cffeda55f" .. c .. "|r|cffeda55fc|r"
    return str
end

-- ---- WoW Classic Item Categories ----
local CATEGORIES = {
    { name = "Weapons", classID = 2, subs = {
        {name="One-Handed Axes",  subID=0}, {name="Two-Handed Axes",  subID=1},
        {name="Bows",             subID=2}, {name="Guns",             subID=3},
        {name="One-Handed Maces", subID=4}, {name="Two-Handed Maces", subID=5},
        {name="Polearms",         subID=6}, {name="One-Handed Swords",subID=7},
        {name="Two-Handed Swords",subID=8}, {name="Staves",           subID=10},
        {name="Fist Weapons",     subID=13},{name="Miscellaneous",    subID=14},
        {name="Daggers",          subID=15},{name="Thrown",            subID=16},
        {name="Crossbows",        subID=18},{name="Wands",            subID=19},
    }},
    { name = "Armor", classID = 4, subs = {
        {name="Miscellaneous",subID=0}, {name="Cloth",   subID=1},
        {name="Leather",      subID=2}, {name="Mail",    subID=3},
        {name="Plate",        subID=4}, {name="Shields", subID=6},
        {name="Librams",      subID=7}, {name="Idols",   subID=8},
        {name="Totems",       subID=9},
    }},
    { name = "Container", classID = 1, subs = {
        {name="Bag",      subID=0}, {name="Soul Bag",        subID=1},
        {name="Herb Bag", subID=2}, {name="Enchanting Bag",  subID=3},
        {name="Engineering Bag",subID=4}, {name="Gem Bag",   subID=5},
        {name="Mining Bag",subID=6},
    }},
    { name = "Consumable", classID = 0, subs = {
        {name="Consumable",subID=0}, {name="Potion",subID=1}, {name="Elixir",subID=2},
        {name="Flask",subID=3}, {name="Scroll",subID=4}, {name="Food & Drink",subID=5},
        {name="Item Enhancement",subID=6}, {name="Bandage",subID=7},
    }},
    { name = "Trade Goods", classID = 7, subs = {
        {name="Trade Goods",subID=0}, {name="Parts",subID=1}, {name="Explosives",subID=2},
        {name="Devices",subID=3}, {name="Jewelcrafting",subID=4}, {name="Cloth",subID=5},
        {name="Leather",subID=6}, {name="Metal & Stone",subID=7}, {name="Meat",subID=8},
        {name="Herb",subID=9}, {name="Elemental",subID=10}, {name="Other",subID=11},
        {name="Enchanting",subID=12},
    }},
    { name = "Projectile", classID = 6, subs = {
        {name="Arrow",subID=2}, {name="Bullet",subID=3},
    }},
    { name = "Quiver", classID = 11, subs = {
        {name="Quiver",subID=2}, {name="Ammo Pouch",subID=3},
    }},
    { name = "Recipe", classID = 9, subs = {
        {name="Book",subID=0}, {name="Leatherworking",subID=1}, {name="Tailoring",subID=2},
        {name="Engineering",subID=3}, {name="Blacksmithing",subID=4}, {name="Cooking",subID=5},
        {name="Alchemy",subID=6}, {name="First Aid",subID=7}, {name="Enchanting",subID=8},
        {name="Fishing",subID=9}, {name="Jewelcrafting",subID=10},
    }},
    { name = "Gems", classID = 3, subs = {
        {name="Red",subID=0}, {name="Blue",subID=1}, {name="Yellow",subID=2},
        {name="Purple",subID=3}, {name="Green",subID=4}, {name="Orange",subID=5},
        {name="Meta",subID=6}, {name="Simple",subID=7}, {name="Prismatic",subID=8},
    }},
    { name = "Miscellaneous", classID = 15 },
    { name = "Quest Items",   classID = 12 },
}

-- ---- Rarity Colors ----
local RARITY_COLORS = {
    [0] = {0.62, 0.62, 0.62}, -- Poor
    [1] = {1.00, 1.00, 1.00}, -- Common
    [2] = {0.12, 1.00, 0.00}, -- Uncommon
    [3] = {0.00, 0.44, 0.87}, -- Rare
    [4] = {0.64, 0.21, 0.93}, -- Epic
    [5] = {1.00, 0.50, 0.00}, -- Legendary
}

-- ================================================================
-- SEARCH INDEX CACHES (three separate indices)
-- ================================================================
-- 1. PersonalIndex: All items from Auctionator.Database.db (Personal Scan tab)
-- 2. GuildIndex:    Only synced items with metadata (Guild Sync tab - stable)
-- 3. GuildIncoming: Staging buffer for new sync data (merged when ready)
-- ================================================================

local PersonalIndex = {}
local GuildIndex = {}
local GuildIncomingBuffer = {}

local PersonalIndexReady = false
local PersonalIndexBuilding = false
local GuildIndexReady = false
local IndexCallbacks = {}

-- Tracking for background resolution
local PersonalPending = {}    -- { dbKey = itemID }
local GuildPending = {}       -- { dbKey = itemID }
local PersonalTotal = 0
local PersonalResolved = 0
local GuildTotal = 0
local GuildResolved = 0
local GuildIncomingCount = 0
local GuildSyncActive = false

-- ================================================================
-- HELPER: Build an index entry from a dbKey + itemID
-- Returns the entry table or nil if item data isn't cached yet
-- ================================================================
local function BuildIndexEntry(dbKey, itemID, data)
    local name, link, rarity, ilvl, minLevel, itemType, itemSubType, _, _, icon, _, classID, subClassID = C_Item.GetItemInfo(itemID)
    if not name then return nil end
    local price = data.m or 0
    local age = Auctionator and Auctionator.Database and Auctionator.Database.GetPriceAge and Auctionator.Database:GetPriceAge(dbKey) or nil
    local meta = MarketSyncDB and MarketSyncDB.ItemMetadata and MarketSyncDB.ItemMetadata[dbKey]
    return {
        name = name, nameLower = name:lower(), link = link,
        rarity = rarity or 1, ilvl = ilvl or 0, minLevel = minLevel or 0,
        icon = icon, classID = classID, subClassID = subClassID,
        price = price, age = age, dbKey = dbKey,
        source = meta and meta.source or "Personal",
        hasMeta = meta ~= nil,
    }
end

-- ================================================================
-- PARSE ITEM ID from a dbKey
-- ================================================================
local function ParseItemID(dbKey)
    if type(dbKey) == "string" then
        if dbKey:match("^%d+$") then return tonumber(dbKey)
        elseif dbKey:match("^g:(%d+)") then return tonumber(dbKey:match("^g:(%d+)"))
        elseif dbKey:match("^p:(%d+)") then return tonumber(dbKey:match("^p:(%d+)")) end
    elseif type(dbKey) == "number" then
        return dbKey
    end
    return nil
end

-- ================================================================
-- BUILD ALL INDICES (runs once, populates Personal + Guild)
-- ================================================================
local function BuildSearchIndex(callback)
    if PersonalIndexReady then
        if callback then callback() end
        return
    end
    if callback then table.insert(IndexCallbacks, callback) end
    if PersonalIndexBuilding then return end
    PersonalIndexBuilding = true

    -- Read cache speed preset
    local speedLevel = (MarketSyncDB and MarketSyncDB.CacheSpeed) or 2
    local preset = MarketSync.CacheSpeedPresets[speedLevel] or MarketSync.CacheSpeedPresets[2]

    PersonalTotal = 0
    PersonalResolved = 0
    GuildTotal = 0
    GuildResolved = 0

    local co = coroutine.create(function()
        if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then
            PersonalIndexReady = true; GuildIndexReady = true
            PersonalIndexBuilding = false
            return
        end
        local count = 0
        local currentYieldLimit = 5 -- Start very slow to let UI render first frame instantly
        for dbKey, data in pairs(Auctionator.Database.db) do
            local itemID = ParseItemID(dbKey)
            if itemID then
                PersonalTotal = PersonalTotal + 1
                local entry = BuildIndexEntry(dbKey, itemID, data)
                if entry then
                    -- Always goes into Personal index
                    PersonalIndex[dbKey] = entry
                    PersonalResolved = PersonalResolved + 1

                    -- If it has sync metadata, also add to Guild index
                    if entry.hasMeta then
                        GuildIndex[dbKey] = entry
                        GuildTotal = GuildTotal + 1
                        GuildResolved = GuildResolved + 1
                    end
                else
                    -- Item not cached, track for retry
                    PersonalPending[dbKey] = itemID
                    C_Item.RequestLoadItemDataByID(itemID)

                    -- If it has sync metadata, also track for guild retry
                    local meta = MarketSyncDB and MarketSyncDB.ItemMetadata and MarketSyncDB.ItemMetadata[dbKey]
                    if meta then
                        GuildPending[dbKey] = itemID
                        GuildTotal = GuildTotal + 1
                    end
                end
            end
            count = count + 1
            if count >= currentYieldLimit then
                coroutine.yield()
                count = 0
                currentYieldLimit = preset.yieldEvery -- Switch to normal speed
            end
        end

        -- First pass complete - mark as ready so users can browse
        PersonalIndexReady = true; GuildIndexReady = true
        PersonalIndexBuilding = false
        for _, cb in ipairs(IndexCallbacks) do cb() end
        wipe(IndexCallbacks)
    end)

    local ticker
    ticker = C_Timer.NewTicker(0.01, function()
        if coroutine.status(co) == "dead" then ticker:Cancel(); return end
        local ok, err = coroutine.resume(co)
        if not ok then print("|cffff0000[MarketSync] Index error:|r", err); ticker:Cancel() end
    end)

    -- ================================================================
    -- BACKGROUND RETRY: Resolve pending items from both caches
    -- ================================================================
    local retryFrame = CreateFrame("Frame")
    local retryBatchSize = preset.batchSize
    local retryTimer = nil

    local function ProcessPendingBatch()
        if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return end
        local processed = 0
        local personalRemove = {}
        local guildRemove = {}

        -- Resolve Personal pending
        for dbKey, itemID in pairs(PersonalPending) do
            if processed >= retryBatchSize then break end
            local data = Auctionator.Database.db[dbKey]
            if data then
                local entry = BuildIndexEntry(dbKey, itemID, data)
                if entry then
                    PersonalIndex[dbKey] = entry
                    PersonalResolved = PersonalResolved + 1
                    table.insert(personalRemove, dbKey)

                    -- Also resolve guild if pending
                    if GuildPending[dbKey] then
                        GuildIndex[dbKey] = entry
                        GuildResolved = GuildResolved + 1
                        table.insert(guildRemove, dbKey)
                    end
                end
            end
            processed = processed + 1
        end

        for _, key in ipairs(personalRemove) do PersonalPending[key] = nil end
        for _, key in ipairs(guildRemove) do GuildPending[key] = nil end
    end

    retryFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    retryFrame:SetScript("OnEvent", function(self, event, itemID, success)
        if retryTimer then return end
        retryTimer = C_Timer.After(0.1, function()
            retryTimer = nil
            ProcessPendingBatch()

            -- Check if all items are resolved
            local pRemaining, gRemaining = 0, 0
            for _ in pairs(PersonalPending) do pRemaining = pRemaining + 1 end
            for _ in pairs(GuildPending) do gRemaining = gRemaining + 1 end
            if pRemaining == 0 and gRemaining == 0 then
                self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                if MarketSyncDB and MarketSyncDB.DebugMode then
                    print("|cFF00FF00[MarketSync]|r Index complete: Personal " .. PersonalResolved .. "/" .. PersonalTotal ..
                        ", Guild " .. GuildResolved .. "/" .. GuildTotal)
                end
            end
        end)
    end)

    -- Periodic retry for missed events
    local periodicRetry
    periodicRetry = C_Timer.NewTicker(preset.interval, function()
        local pRemaining, gRemaining = 0, 0
        for _ in pairs(PersonalPending) do pRemaining = pRemaining + 1 end
        for _ in pairs(GuildPending) do gRemaining = gRemaining + 1 end

        if pRemaining == 0 and gRemaining == 0 then
            periodicRetry:Cancel()
            return
        end

        local requested = 0
        for dbKey, itemID in pairs(PersonalPending) do
            if requested >= preset.requests then break end
            C_Item.RequestLoadItemDataByID(itemID)
            requested = requested + 1
        end

        ProcessPendingBatch()
    end)
end

-- ================================================================
-- GUILD INCOMING BUFFER: Staging area for active sync data
-- New items from sync land here, not in GuildIndex directly
-- ================================================================

-- Called by sync module when a new sync session starts
function MarketSync.BeginGuildSync()
    GuildSyncActive = true
    GuildIncomingCount = 0
    wipe(GuildIncomingBuffer)
    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Guild sync started - buffering incoming data")
    end
end

-- Called by sync module for each item received during sync
function MarketSync.AddToGuildIncoming(dbKey)
    if not PersonalIndexReady then return end  -- Index hasn't been built yet
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return end

    local data = Auctionator.Database.db[dbKey]
    if not data then return end

    local itemID = ParseItemID(dbKey)
    if not itemID then return end

    -- Update the Personal index immediately (the data IS in the DB)
    local entry = BuildIndexEntry(dbKey, itemID, data)
    if entry then
        local isNewPersonal = not PersonalIndex[dbKey]
        PersonalIndex[dbKey] = entry
        if isNewPersonal then PersonalResolved = PersonalResolved + 1 end

        if GuildSyncActive then
            -- Route to incoming buffer (don't disrupt live guild browsing)
            GuildIncomingBuffer[dbKey] = entry
            GuildIncomingCount = GuildIncomingCount + 1
        else
            -- No active sync, update guild index directly
            local isNewGuild = not GuildIndex[dbKey]
            GuildIndex[dbKey] = entry
            if isNewGuild then
                GuildTotal = GuildTotal + 1
                GuildResolved = GuildResolved + 1
            end
        end
    else
        -- Not cached yet, request it
        PersonalPending[dbKey] = itemID
        if GuildSyncActive then
            -- Mark for incoming resolution
            GuildPending[dbKey] = itemID
        end
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Called when sync session ends — merge incoming buffer into live Guild index
function MarketSync.CommitGuildSync()
    local merged = 0
    for dbKey, entry in pairs(GuildIncomingBuffer) do
        GuildIndex[dbKey] = entry
        merged = merged + 1
    end

    -- Recount guild totals
    GuildTotal = 0
    GuildResolved = 0
    for _ in pairs(GuildIndex) do
        GuildTotal = GuildTotal + 1
        GuildResolved = GuildResolved + 1
    end

    GuildSyncActive = false
    GuildIncomingCount = 0
    wipe(GuildIncomingBuffer)

    if MarketSyncDB and MarketSyncDB.DebugMode then
        print("|cFF00FF00[MarketSync]|r Guild sync committed: " .. merged .. " items merged, " .. GuildTotal .. " total guild items")
    end
end

-- ================================================================
-- STATUS API for UI
-- ================================================================
MarketSync.GetIndexStatus = function()
    local pPending, gPending = 0, 0
    for _ in pairs(PersonalPending) do pPending = pPending + 1 end
    for _ in pairs(GuildPending) do gPending = gPending + 1 end
    return {
        personalReady = PersonalIndexReady,
        personalTotal = PersonalTotal,
        personalResolved = PersonalResolved,
        personalPending = pPending,
        guildReady = GuildIndexReady,
        guildTotal = GuildTotal,
        guildResolved = GuildResolved,
        guildPending = gPending,
        guildSyncActive = GuildSyncActive,
        guildIncoming = GuildIncomingCount,
    }
end

-- Expose for use by Frame module and startup trigger
MarketSync.BuildSearchIndex = BuildSearchIndex

-- ================================================================
-- CREATE BROWSE PANEL
-- ================================================================
function MarketSync.CreateBrowsePanel(parent, dataSourceName)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)
    panel.dataSource = dataSourceName

    -- --- Search Bar ---
    local nameLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 80, -38)
    nameLabel:SetText("Name")

    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(160, 20)
    searchBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 80, -50)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        panel:RunSearch()
    end)
    panel.searchBox = searchBox

    -- Shift-click item insertion: extract name from link and search
    local origInsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(text, ...)
        if panel:IsVisible() and text then
            -- Extract item name from link: |cFFxxxxxx|Hitem:...|h[Item Name]|h|r
            local itemName = text:match("%[(.-)%]")
            if itemName then
                searchBox:SetText(itemName)
                searchBox:ClearFocus()
                panel:RunSearch()
                return true
            end
        end
        return origInsertLink(text, ...)
    end

    -- Search Button
    local searchBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    searchBtn:SetSize(80, 22)
    searchBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -50)
    searchBtn:SetText("Search")
    searchBtn:SetScript("OnClick", function() panel:RunSearch() end)

    -- Reset Button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, 22)
    resetBtn:SetPoint("RIGHT", searchBtn, "LEFT", -5, 0)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        panel.activeCategory = nil
        panel.activeSubCategory = nil
        panel.expandedCategory = nil
        panel:RebuildFilters()
        panel:RunSearch()
    end)

    -- --- CATEGORY SIDEBAR ---
    local SIDEBAR_WIDTH = 155
    local SIDEBAR_HEIGHT = 305
    local filterScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    filterScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 23, -105)
    filterScroll:SetSize(SIDEBAR_WIDTH, SIDEBAR_HEIGHT)
    local filterChild = CreateFrame("Frame"); filterChild:SetSize(SIDEBAR_WIDTH, 800); filterScroll:SetScrollChild(filterChild)
    local scrollBar = filterScroll.ScrollBar or _G[filterScroll:GetName() and (filterScroll:GetName().."ScrollBar")]
    if scrollBar then scrollBar:Hide() end
    filterScroll:EnableMouseWheel(true)
    filterScroll:SetScript("OnMouseWheel", function(self, delta)
        local step = FILTER_HEIGHT * 3
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newVal = current - (delta * step)
        newVal = math.max(0, math.min(newVal, maxScroll))
        self:SetVerticalScroll(newVal)
    end)
    panel.filterScroll = filterScroll
    panel.filterChild = filterChild
    panel.filterButtons = {}
    panel.expandedCategory = nil
    panel.activeSubCategory = nil

    local function MakeFilterButton(parentFrame, labelText, indent, yOff, btnWidth)
        local w = btnWidth or SIDEBAR_WIDTH
        local btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(w, FILTER_HEIGHT)
        btn:SetPoint("TOPLEFT", 0, -yOff)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
        bg:SetTexCoord(0, 0.53125, 0, 0.625)
        bg:SetAllPoints()

        local text = btn:CreateFontString(nil, "ARTWORK", indent > 0 and "GameFontHighlightSmallLeft" or "GameFontNormalSmallLeft")
        text:SetSize(w - 10 - indent, 8)
        text:SetPoint("LEFT", 4 + indent, 0)
        text:SetText(labelText)
        btn.text = text

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints()
        return btn
    end

    function panel:RebuildFilters()
        for _, b in ipairs(self.filterButtons) do b:Hide() end
        wipe(self.filterButtons)

        -- Pre-calculate total height to determine if scrollbar is needed
        local totalHeight = 0
        for _, cat in ipairs(CATEGORIES) do
            totalHeight = totalHeight + FILTER_HEIGHT
            if self.expandedCategory == cat.classID and cat.subs then
                totalHeight = totalHeight + (#cat.subs * FILTER_HEIGHT)
            end
        end

        local needsScrollbar = totalHeight > SIDEBAR_HEIGHT
        local btnWidth = needsScrollbar and (SIDEBAR_WIDTH - 20) or SIDEBAR_WIDTH

        local y = 0
        for _, cat in ipairs(CATEGORIES) do
            local btn = MakeFilterButton(self.filterChild, cat.name, 0, y, btnWidth)
            btn.classID = cat.classID
            btn.isCategory = true
            if self.activeCategory == cat.classID and not self.activeSubCategory then
                btn:LockHighlight()
            end
            btn:SetScript("OnClick", function()
                if self.activeCategory == cat.classID and self.activeSubCategory == nil then
                    -- Toggle OFF: Clear filter and collapse
                    self.activeCategory = nil
                    self.expandedCategory = nil
                else
                    -- Toggle ON: Select and Expand
                    self.activeCategory = cat.classID
                    self.activeSubCategory = nil
                    self.expandedCategory = cat.classID
                end
                self:RebuildFilters()
                self:RunSearch()
            end)
            table.insert(self.filterButtons, btn)
            y = y + FILTER_HEIGHT

            if self.expandedCategory == cat.classID and cat.subs then
                for _, sub in ipairs(cat.subs) do
                    local sbtn = MakeFilterButton(self.filterChild, sub.name, 12, y, btnWidth)
                    sbtn.classID = cat.classID
                    sbtn.subID = sub.subID
                    if self.activeSubCategory == sub.subID and self.activeCategory == cat.classID then
                        sbtn:LockHighlight()
                    end
                    sbtn:SetScript("OnClick", function()
                        if self.activeCategory == cat.classID and self.activeSubCategory == sub.subID then
                            self.activeSubCategory = nil -- Toggle OFF (Revert to Parent)
                        else
                            self.activeCategory = cat.classID
                            self.activeSubCategory = sub.subID
                        end
                        self:RebuildFilters()
                        self:RunSearch()
                    end)
                    table.insert(self.filterButtons, sbtn)
                    y = y + FILTER_HEIGHT
                end
            end
        end
        self.filterChild:SetHeight(math.max(y, SIDEBAR_HEIGHT))
        local sb = self.filterScroll.ScrollBar or _G[self.filterScroll:GetName() and (self.filterScroll:GetName().."ScrollBar")]
        if sb then
            if needsScrollbar then sb:Show() else sb:Hide() end
        end
    end
    panel:RebuildFilters()

    -- --- SORTING STATE ---
    panel.sortField = "price"
    panel.sortAscending = true

    local function SortResults(field)
        if panel.sortField == field then
            panel.sortAscending = not panel.sortAscending
        else
            panel.sortField = field
            panel.sortAscending = true
        end
        panel:ApplySort()
        panel.page = 0
        panel:UpdateResults()
        for _, h in ipairs(panel.headerButtons) do
            if h.sortKey == field then
                h.arrow:Show()
                if panel.sortAscending then
                    h.arrow:SetTexCoord(0, 0.5625, 1.0, 0)
                else
                    h.arrow:SetTexCoord(0, 0.5625, 0, 1.0)
                end
            else
                h.arrow:Hide()
            end
        end
    end

    -- --- COLUMN HEADERS ---
    local colDefs = {
        {name = "Rarity",  width = 275, sortKey = "rarity"},
        {name = "Lvl",     width = 42,  sortKey = "minLevel"},
        {name = "Price",   width = 100, sortKey = "price"},
        {name = "Age",     width = 55,  sortKey = nil},
        {name = "Source",  width = 80,  sortKey = nil},
        {name = "",        width = 92, sortKey = nil},
    }
    local colX = 193
    panel.headerButtons = {}
    for i, col in ipairs(colDefs) do
        local hdr = CreateFrame("Button", nil, panel)
        hdr:SetSize(col.width, 19)
        hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", colX, -81)
        hdr.sortKey = col.sortKey

        local hleft = hdr:CreateTexture(nil, "BACKGROUND")
        hleft:SetTexture("Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
        hleft:SetSize(5, 19)
        hleft:SetPoint("TOPLEFT")
        hleft:SetTexCoord(0, 0.078125, 0, 0.59375)

        local hright = hdr:CreateTexture(nil, "BACKGROUND")
        hright:SetTexture("Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
        hright:SetSize(4, 19)
        hright:SetPoint("TOPRIGHT")
        hright:SetTexCoord(0.90625, 0.96875, 0, 0.59375)

        local hmid = hdr:CreateTexture(nil, "BACKGROUND")
        hmid:SetTexture("Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
        hmid:SetPoint("LEFT", hleft, "RIGHT")
        hmid:SetPoint("RIGHT", hright, "LEFT")
        hmid:SetHeight(19)
        hmid:SetTexCoord(0.078125, 0.90625, 0, 0.59375)

        local htxt = hdr:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        htxt:SetPoint("LEFT", 8, 0)
        htxt:SetText(col.name)

        local arrow = hdr:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        arrow:SetSize(9, 8)
        arrow:SetPoint("LEFT", htxt, "RIGHT", 3, -2)
        arrow:SetTexCoord(0, 0.5625, 0, 1.0)
        arrow:Hide()
        hdr.arrow = arrow

        if col.sortKey == "price" then
            arrow:Show()
            arrow:SetTexCoord(0, 0.5625, 1.0, 0)
        end

        local hhl = hdr:CreateTexture(nil, "HIGHLIGHT")
        hhl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        hhl:SetBlendMode("ADD")
        hhl:SetPoint("LEFT", 0, 0)
        hhl:SetPoint("RIGHT", 4, 0)
        hhl:SetHeight(24)

        if col.sortKey then
            hdr:SetScript("OnClick", function() SortResults(col.sortKey) end)
        end

        panel.headerButtons[i] = hdr
        colX = colX + col.width - 2
    end

    -- --- Prev/Next Buttons (in gold bar, right side) ---
    panel.page = 0
    panel.currentResults = {}

    local prevBtn = CreateFrame("Button", nil, panel)
    prevBtn:SetSize(28, 28)
    prevBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -50, 11)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    prevBtn:SetScript("OnClick", function()
        if panel.page > 0 then
            panel.page = panel.page - 1
            panel:UpdateResults()
        end
    end)
    panel.prevBtn = prevBtn

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(28, 28)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    nextBtn:SetScript("OnClick", function()
        local maxPage = math.floor(#panel.currentResults / NUM_RESULTS_TO_DISPLAY)
        if panel.page < maxPage then
            panel.page = panel.page + 1
            panel:UpdateResults()
        end
    end)
    panel.nextBtn = nextBtn

    -- Page text (in gold bar, left of arrows)
    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.pageText:SetPoint("BOTTOMRIGHT", prevBtn, "BOTTOMLEFT", -8, 9)

    -- No results text
    panel.noResultsText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.noResultsText:SetPoint("TOP", parent, "TOP", 115, -200)
    panel.noResultsText:SetText("Search for items using the box above.")
    panel.noResultsText:Show()

    -- --- STATUS TEXT (inside the bottom gold bar, left side) ---
    panel.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.statusText:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 30, 20)
    panel.statusText:SetWidth(200)
    panel.statusText:SetJustifyH("LEFT")

    -- --- "Last Guild Sync" LABEL (aligned with Rarity column area) ---
    panel.syncLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.syncLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 195, 20)
    panel.syncLabel:SetJustifyH("LEFT")

    -- --- ITEM COUNT TEXT (center-left of gold bar) ---
    panel.itemCountText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.itemCountText:SetPoint("BOTTOM", parent, "BOTTOM", -60, 20)
    panel.itemCountText:SetWidth(200)
    panel.itemCountText:SetJustifyH("CENTER")

    -- --- OnShow: Update status bar and run initial search ---
    panel:SetScript("OnShow", function(self)
        self:RunSearch()
        if self.dataSource == "personal" then
            local scanAge = nil
            local totalItems = 0
            if Auctionator and Auctionator.Database and Auctionator.Database.db then
                local bestAge = 9999
                local checked = 0
                for dbKey, _ in pairs(Auctionator.Database.db) do
                    totalItems = totalItems + 1
                    if checked < 50 then
                        local age = Auctionator.Database:GetPriceAge(dbKey)
                        if age and age < bestAge then bestAge = age end
                        checked = checked + 1
                    end
                end
                if bestAge < 9999 then scanAge = bestAge end
            end
            if scanAge then
                if scanAge == 0 then
                    self.statusText:SetText("|cff00ff00Last Scan:|r Today")
                else
                    self.statusText:SetText("|cff00ff00Last Scan:|r " .. scanAge .. " day(s) ago")
                end
            else
                self.statusText:SetText("|cffff8800No scan data available|r")
            end
            self.itemCountText:SetText("|cffffd700" .. totalItems .. "|r items")
            self.syncLabel:SetText("")

        elseif self.dataSource == "guild" then
            local latestUser, latestTime = nil, 0
            local syncedItems = 0
            local uniqueSyncers = 0
            if MarketSyncDB and MarketSyncDB.SyncStats then
                for user, stats in pairs(MarketSyncDB.SyncStats) do
                    uniqueSyncers = uniqueSyncers + 1
                    if stats.last and stats.last > latestTime then
                        latestTime = stats.last
                        latestUser = user
                    end
                end
            end
            if MarketSyncDB and MarketSyncDB.ItemMetadata then
                for _ in pairs(MarketSyncDB.ItemMetadata) do syncedItems = syncedItems + 1 end
            end
            if latestUser then
                local timeStr = date("%H:%M", latestTime)
                local tzStr = date("%Z", latestTime) or ""
                tzStr = tzStr:match("^%a+") or tzStr
                local shortName = latestUser:match("^([^%-]+)") or latestUser
                self.statusText:SetText("|cffffd700" .. timeStr .. " " .. tzStr .. " " .. shortName .. "|r")
                self.syncLabel:SetText("|cff00ff00Last Guild Sync|r")
            else
                self.statusText:SetText("|cffff8800No sync data yet|r")
                self.syncLabel:SetText("")
            end
            self.itemCountText:SetText("|cffffd700" .. syncedItems .. "|r synced")
        end
    end)

    -- --- RESULT ROWS ---
    panel.resultRows = {}
    for i = 1, NUM_RESULTS_TO_DISPLAY do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(632, RESULT_HEIGHT)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 195, -107 - (i-1) * RESULT_HEIGHT)

        -- Item Icon
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetSize(32, 32)
        iconBtn:SetPoint("TOPLEFT", 0, -3)
        local iconTex = iconBtn:CreateTexture(nil, "BORDER")
        iconTex:SetAllPoints()
        row.iconTex = iconTex

        local iconNorm = iconBtn:CreateTexture(nil, "ARTWORK")
        iconNorm:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        iconNorm:SetSize(60, 60)
        iconNorm:SetPoint("CENTER")

        -- Count
        local countText = row:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        countText:SetPoint("BOTTOMRIGHT", iconBtn, -5, 2)
        countText:SetJustifyH("RIGHT")
        row.countText = countText

        -- Item Name Frame (9-slice background)
        local nameLeft = row:CreateTexture(nil, "BACKGROUND")
        nameLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameLeft:SetSize(10, 32)
        nameLeft:SetPoint("LEFT", 34, 2)
        nameLeft:SetTexCoord(0, 0.078125, 0, 1.0)

        local nameRight = row:CreateTexture(nil, "BACKGROUND")
        nameRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameRight:SetSize(10, 32)
        nameRight:SetPoint("LEFT", 617, 2)
        nameRight:SetTexCoord(0.75, 0.828125, 0, 1.0)

        local nameMid = row:CreateTexture(nil, "BACKGROUND")
        nameMid:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
        nameMid:SetPoint("LEFT", nameLeft, "RIGHT")
        nameMid:SetPoint("RIGHT", nameRight, "LEFT")
        nameMid:SetHeight(32)
        nameMid:SetTexCoord(0.078125, 0.75, 0, 1.0)

        -- Name text
        local nameText = row:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
        nameText:SetSize(230, 32)
        nameText:SetPoint("TOPLEFT", 43, -3)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Level
        local lvlText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        lvlText:SetSize(38, 32)
        lvlText:SetPoint("TOPLEFT", 275, -3)
        row.lvlText = lvlText

        -- Price (moved before Age/Source)
        local priceText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        priceText:SetPoint("TOPLEFT", 315, -3)
        priceText:SetSize(95, 32)
        priceText:SetJustifyH("RIGHT")
        row.priceText = priceText

        -- Age
        local ageText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        ageText:SetSize(50, 32)
        ageText:SetPoint("TOPLEFT", 413, -3)
        row.ageText = ageText

        -- Source
        local srcText = row:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        srcText:SetSize(75, 32)
        srcText:SetPoint("TOPLEFT", 466, -3)
        row.srcText = srcText

        -- Highlight
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
        highlight:SetBlendMode("ADD")
        highlight:SetSize(594, 32)
        highlight:SetPoint("TOPLEFT", 33, -3)
        highlight:SetTexCoord(0, 1.0, 0, 0.578125)

        -- Tooltip & Click
        iconBtn:SetScript("OnEnter", function(self)
            row:LockHighlight()
            if row.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(row.link)
                GameTooltip:Show()
            end
        end)
        iconBtn:SetScript("OnLeave", function()
            row:UnlockHighlight()
            GameTooltip:Hide()
        end)
        iconBtn:SetScript("OnClick", function()
            if row.link and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(row.link)
            elseif row.itemData and MarketSync.ShowItemHistory then
                MarketSync.ShowItemHistory(
                    row.itemData.dbKey,
                    row.itemData.link,
                    row.itemData.name,
                    row.itemData.icon,
                    row.itemData.price
                )
            end
        end)

        -- Row click (non-icon area) also opens history
        row:SetScript("OnClick", function(self)
            if self.link and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(self.link)
            elseif self.itemData and MarketSync.ShowItemHistory then
                MarketSync.ShowItemHistory(
                    self.itemData.dbKey,
                    self.itemData.link,
                    self.itemData.name,
                    self.itemData.icon,
                    self.itemData.price
                )
            end
        end)

        -- Row hover tooltip
        row:SetScript("OnEnter", function(self)
            self:LockHighlight()
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00ff00Click to view price history|r", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self:UnlockHighlight()
            GameTooltip:Hide()
        end)

        row:Hide()
        panel.resultRows[i] = row
    end

    -- Mousewheel scrolling for result pagination
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if self.page > 0 then
                self.page = self.page - 1
                self:UpdateResults()
            end
        else
            local maxPage = math.max(0, math.ceil(#self.currentResults / NUM_RESULTS_TO_DISPLAY) - 1)
            if self.page < maxPage then
                self.page = self.page + 1
                self:UpdateResults()
            end
        end
    end)

    -- --- SEARCH LOGIC ---
    function panel:RunSearch()
        local query = self.searchBox:GetText():lower()
        self.currentResults = {}
        self.page = 0

        if not PersonalIndexReady then
            self.noResultsText:SetText("Building index, please wait...")
            self.noResultsText:Show()
            self:UpdateResults()
            BuildSearchIndex(function() self:RunSearch() end)
            return
        end

        local activeCat = self.activeCategory
        local activeSub = self.activeSubCategory
        local isGuild = self.dataSource == "guild"
        local minQueryLen = 2

        -- Use the appropriate index for this tab
        local index = isGuild and GuildIndex or PersonalIndex

        for _, item in pairs(index) do
            local matchesQuery = (#query < minQueryLen) or item.nameLower:find(query, 1, true)
            if matchesQuery then
                local matchesCat = (not activeCat) or (item.classID == activeCat)
                if matchesCat then
                    local matchesSub = (not activeSub) or (item.subClassID == activeSub)
                    if matchesSub then
                        table.insert(self.currentResults, item)
                    end
                end
            end
        end

        self:ApplySort()

        if #self.currentResults == 0 then
            if isGuild and GuildSyncActive then
                self.noResultsText:SetText("Guild sync in progress... browsing available data.")
            else
                self.noResultsText:SetText("No results found.")
            end
            self.noResultsText:Show()
        else
            self.noResultsText:Hide()
        end

        self:UpdateResults()
    end

    function panel:UpdateResults()
        local offset = self.page * NUM_RESULTS_TO_DISPLAY
        local total = #self.currentResults

        for i = 1, NUM_RESULTS_TO_DISPLAY do
            local row = self.resultRows[i]
            local idx = offset + i
            if idx <= total then
                local d = self.currentResults[idx]
                row.iconTex:SetTexture(d.icon)
                row.nameText:SetText(d.link or d.name)
                row.lvlText:SetText(d.minLevel > 0 and d.minLevel or "")
                row.ageText:SetText(d.age and (d.age .. "d ago") or "N/A")
                row.srcText:SetText(d.source or "")
                row.priceText:SetText(FormatMoney(d.price))
                row.countText:SetText("")
                row.link = d.link
                row.itemData = d  -- Store full data for history click
                local rc = RARITY_COLORS[d.rarity]
                if rc then row.nameText:SetTextColor(rc[1], rc[2], rc[3]) end
                row:Show()
            else
                row:Hide()
                row.itemData = nil
            end
        end

        local maxPage = math.max(0, math.ceil(total / NUM_RESULTS_TO_DISPLAY) - 1)
        local statusStr = total .. " results (Page " .. (self.page+1) .. "/" .. (maxPage+1) .. ")"
        -- Show background index progress
        local idxStatus = MarketSync.GetIndexStatus and MarketSync.GetIndexStatus()
        if idxStatus then
            local isGuild = self.dataSource == "guild"
            local pending = isGuild and idxStatus.guildPending or idxStatus.personalPending
            if pending > 0 then
                statusStr = statusStr .. " |cffff8800(" .. pending .. " resolving...)|r"
            end
            if isGuild and idxStatus.guildSyncActive and idxStatus.guildIncoming > 0 then
                statusStr = statusStr .. " |cff00ff00(" .. idxStatus.guildIncoming .. " incoming)|r"
            end
        end
        self.pageText:SetText(statusStr)
        self.prevBtn:SetEnabled(self.page > 0)
        self.nextBtn:SetEnabled(self.page < maxPage)
    end

    function panel:ApplySort()
        local field = self.sortField
        local asc = self.sortAscending
        table.sort(self.currentResults, function(a, b)
            local va, vb = a[field], b[field]
            if va == nil then va = 0 end
            if vb == nil then vb = 0 end
            if va == vb then return a.name < b.name end
            if asc then return va < vb else return va > vb end
        end)
    end

    return panel
end


