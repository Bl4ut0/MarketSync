-- =============================================================
-- MarketSync - Processing Arbitrage Module
-- EV calculator + Auctionator shopping list export
-- =============================================================

local CALLER_ID = "MarketSync"
local STALE_PRICE_DAYS = 3
local PROCESS_MIN_EXPANSION = {
    DISENCHANT = 0, -- Vanilla+
    PROSPECT = 1,   -- TBC+
    MILL = 2,       -- Wrath+
}
local PROCESS_TYPE_ORDER = { "PROSPECT", "MILL", "DISENCHANT" }

local function GetClientExpansionLevel()
    if type(GetExpansionLevel) == "function" then
        local ok, level = pcall(GetExpansionLevel)
        if ok then
            local n = tonumber(level)
            if n then
                return math.max(0, math.floor(n))
            end
        end
    end

    local _, _, _, tocVersion = GetBuildInfo()
    local toc = tonumber(tocVersion) or 0
    if toc >= 110000 then return 10 end -- The War Within+
    if toc >= 100000 then return 9 end  -- Dragonflight
    if toc >= 90000 then return 8 end   -- Shadowlands
    if toc >= 80000 then return 7 end   -- BFA
    if toc >= 70000 then return 6 end   -- Legion
    if toc >= 60000 then return 5 end   -- Warlords
    if toc >= 50000 then return 4 end   -- Mists
    if toc >= 40000 then return 3 end   -- Cataclysm
    if toc >= 30000 then return 2 end   -- Wrath
    if toc >= 20000 then return 1 end   -- TBC
    return 0 -- Vanilla / Classic Era
end

local function IsProcessTypeSupported(processType)
    local processKey = tostring(processType or ""):upper()
    local requiredExpansion = PROCESS_MIN_EXPANSION[processKey]
    if requiredExpansion == nil then
        return false
    end
    return GetClientExpansionLevel() >= requiredExpansion
end

function MarketSync.IsProcessingTypeSupported(processType)
    return IsProcessTypeSupported(processType)
end

function MarketSync.GetSupportedProcessingTypes(includeAll)
    local out = {}
    if includeAll then
        out[#out + 1] = "ALL"
    end
    for _, processType in ipairs(PROCESS_TYPE_ORDER) do
        if IsProcessTypeSupported(processType) then
            out[#out + 1] = processType
        end
    end
    return out
end

-- Foundation dataset — Classic + TBC prospecting ores
-- Probabilities sourced from community data (wow-professions.com, Wowhead)
MarketSync.ProcessingData = MarketSync.ProcessingData or {

    -- =============================================
    --  CLASSIC ERA PROSPECTING ORES
    -- =============================================

    -- Copper Ore (JC 20)
    [2770] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 2835, prob = 0.50, min = 1, max = 2 }, -- Malachite
            { itemID = 818,  prob = 0.50, min = 1, max = 2 }, -- Tigerseye
            { itemID = 2836, prob = 0.10, min = 1, max = 1 }, -- Shadowgem (rare)
        },
    },

    -- Tin Ore (JC 50)
    [2771] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 2838, prob = 0.38, min = 1, max = 2 }, -- Lesser Moonstone
            { itemID = 2840, prob = 0.38, min = 1, max = 2 }, -- Moss Agate
            { itemID = 2836, prob = 0.38, min = 1, max = 1 }, -- Shadowgem
            { itemID = 7909, prob = 0.033, min = 1, max = 1 }, -- Aquamarine (rare)
            { itemID = 3864, prob = 0.033, min = 1, max = 1 }, -- Citrine (rare)
            { itemID = 1529, prob = 0.033, min = 1, max = 1 }, -- Jade (rare)
        },
    },

    -- Iron Ore (JC 125)
    [2772] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 2838, prob = 0.35, min = 1, max = 2 }, -- Lesser Moonstone
            { itemID = 3864, prob = 0.35, min = 1, max = 2 }, -- Citrine
            { itemID = 1529, prob = 0.35, min = 1, max = 2 }, -- Jade
            { itemID = 7910, prob = 0.05, min = 1, max = 1 }, -- Star Ruby (rare)
            { itemID = 7909, prob = 0.05, min = 1, max = 1 }, -- Aquamarine (rare)
        },
    },

    -- Mithril Ore (JC 175)
    [3858] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 7910, prob = 0.35, min = 1, max = 2 }, -- Star Ruby
            { itemID = 7909, prob = 0.35, min = 1, max = 2 }, -- Aquamarine
            { itemID = 3864, prob = 0.35, min = 1, max = 2 }, -- Citrine
            { itemID = 12361, prob = 0.025, min = 1, max = 1 }, -- Blue Sapphire (rare)
            { itemID = 12799, prob = 0.025, min = 1, max = 1 }, -- Large Opal (rare)
            { itemID = 12800, prob = 0.025, min = 1, max = 1 }, -- Azerothian Diamond (rare)
            { itemID = 12364, prob = 0.025, min = 1, max = 1 }, -- Huge Emerald (rare)
        },
    },

    -- Thorium Ore (JC 250)
    [10620] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 7910, prob = 0.19, min = 1, max = 2 }, -- Star Ruby
            { itemID = 12361, prob = 0.19, min = 1, max = 2 }, -- Blue Sapphire
            { itemID = 12799, prob = 0.19, min = 1, max = 2 }, -- Large Opal
            { itemID = 12800, prob = 0.19, min = 1, max = 2 }, -- Azerothian Diamond
            { itemID = 12364, prob = 0.19, min = 1, max = 2 }, -- Huge Emerald
        },
    },

    -- =============================================
    --  TBC PROSPECTING ORES
    -- =============================================

    -- Fel Iron Ore (JC 275)
    [23424] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 23077, prob = 0.18, min = 1, max = 2 }, -- Blood Garnet
            { itemID = 21929, prob = 0.18, min = 1, max = 2 }, -- Flame Spessarite
            { itemID = 23112, prob = 0.18, min = 1, max = 2 }, -- Golden Draenite
            { itemID = 23117, prob = 0.18, min = 1, max = 2 }, -- Azure Moonstone
            { itemID = 23079, prob = 0.18, min = 1, max = 2 }, -- Deep Peridot
            { itemID = 23107, prob = 0.18, min = 1, max = 2 }, -- Shadow Draenite
        },
    },

    -- Adamantite Ore (JC 325)
    [23425] = {
        type = "PROSPECT",
        stackSize = 5,
        yields = {
            { itemID = 23436, prob = 0.17, min = 1, max = 2 }, -- Living Ruby
            { itemID = 23437, prob = 0.17, min = 1, max = 2 }, -- Talasite
            { itemID = 23438, prob = 0.17, min = 1, max = 2 }, -- Star of Elune
            { itemID = 23439, prob = 0.17, min = 1, max = 2 }, -- Noble Topaz
            { itemID = 23440, prob = 0.17, min = 1, max = 2 }, -- Dawnstone
            { itemID = 23441, prob = 0.17, min = 1, max = 2 }, -- Nightseye
        },
    },

    -- =============================================
    --  TBC MILLING HERBS
    -- =============================================

    -- Netherbloom
    [22791] = {
        type = "MILL",
        stackSize = 5,
        yields = {
            { itemID = 39334, prob = 0.90, min = 2, max = 4 }, -- Dusky Pigment
            { itemID = 43103, prob = 0.10, min = 1, max = 2 }, -- Verdant Pigment
        },
    },
}

-- =============================================
--  DISENCHANT VALUE ESTIMATION TABLE
-- =============================================
-- Disenchanting is formula-based (ilvl + quality + armor/weapon).
-- Armor: 75% dust / 20% essence / 5% shard for Uncommon
-- Weapon: 20% dust / 75% essence / 5% shard for Uncommon
-- These probabilities are hardcoded in the game client.
--
-- Each row: { ilvlMin, ilvlMax, dustID, dustMin, dustMax, essID, essMin, essMax, shardID, shardMin, shardMax }
-- For Rare/Epic: { ilvlMin, ilvlMax, shardOrCrystalID, min, max }

MarketSync.DisenchantTable = {

    -- Uncommon (Green, quality 2) — dust + essence + small shard chance
    [2] = {
        -- Classic tiers
        {   5,  15,  10940, 1, 2,  10938, 1, 2,   nil, 0, 0 },    -- Strange Dust / Lesser Magic Essence
        {  16,  20,  10940, 2, 3,  10939, 1, 2, 10978, 1, 1 },     -- Strange Dust / Greater Magic Essence / Small Glimmering
        {  21,  25,  10940, 4, 6,  11082, 1, 2, 10978, 1, 1 },     -- Strange Dust / Lesser Astral Essence / Small Glimmering
        {  26,  30,  11083, 1, 2,  11134, 1, 2, 11084, 1, 1 },     -- Soul Dust / Greater Astral / Large Glimmering
        {  31,  35,  11083, 2, 5,  11135, 1, 2, 11138, 1, 1 },     -- Soul Dust / Lesser Mystic / Small Glowing
        {  36,  40,  11137, 1, 2,  11174, 1, 2, 11139, 1, 1 },     -- Vision Dust / Greater Mystic / Large Glowing
        {  41,  45,  11137, 2, 5,  11175, 1, 2, 11177, 1, 1 },     -- Vision Dust / Lesser Nether / Small Radiant
        {  46,  50,  11176, 1, 2,  11178, 1, 2, 11178, 1, 1 },     -- Dream Dust / Greater Nether / Large Radiant
        {  51,  55,  11176, 2, 5,  16202, 1, 2, 14343, 1, 1 },     -- Dream Dust / Lesser Eternal / Small Brilliant
        {  56,  65,  16204, 1, 3,  16203, 1, 2, 14344, 1, 1 },     -- Illusion Dust / Greater Eternal / Large Brilliant
        {  66,  79,  16204, 2, 5,  16203, 1, 2, 14344, 1, 1 },     -- Illusion Dust / Greater Eternal / Large Brilliant (Vanilla 60 max bracket)
        
        -- TBC tiers (Outland gear starts at ilvl 80)
        {  80,  99,  22445, 1, 3,  22446, 1, 2, 22448, 1, 1 },     -- Arcane Dust / Lesser Planar / Small Prismatic
        { 100, 164,  22445, 2, 5,  22447, 1, 2, 22449, 1, 1 },     -- Arcane Dust / Greater Planar / Large Prismatic
    },

    -- Rare (Blue, quality 3) → guaranteed shard
    [3] = {
        -- Classic
        {  26,  30, 11084, 1, 1 },  -- Large Glimmering Shard
        {  31,  35, 11138, 1, 1 },  -- Small Glowing Shard
        {  36,  40, 11139, 1, 1 },  -- Large Glowing Shard
        {  41,  45, 11177, 1, 1 },  -- Small Radiant Shard
        {  46,  50, 11178, 1, 1 },  -- Large Radiant Shard
        {  51,  55, 14343, 1, 1 },  -- Small Brilliant Shard
        {  56,  79, 14344, 1, 1 },  -- Large Brilliant Shard (Vanilla 60 brackets push to 79)
        
        -- TBC
        {  80, 114, 22448, 1, 1 },  -- Small Prismatic Shard (below level 70 requirement)
        { 115, 164, 22449, 1, 1 },  -- Large Prismatic Shard (level 70 requirement+)
    },

    -- Epic (Purple, quality 4) → crystal
    [4] = {
        -- Classic
        {  56,  79, 20725, 1, 2 },  -- Nexus Crystal
        
        -- TBC
        {  80, 164, 22450, 1, 2 },  -- Void Crystal (all TBC epics)
    },
}



MarketSync.CraftingData = MarketSync.CraftingData or {
    Alchemy = {
        {
            name = "Flask of Blinding Light",
            outputItemID = 22861,
            outputQty = 1,
            mats = {
                { itemID = 22791, qty = 7 }, -- Netherbloom
                { itemID = 22793, qty = 3 }, -- Mana Thistle
                { itemID = 22794, qty = 1 }, -- Fel Lotus
            },
        },
    },
    Enchanting = {
        {
            name = "Large Prismatic Shard (craft proxy)",
            outputItemID = 22449,
            outputQty = 1,
            mats = {
                { itemID = 22445, qty = 3 }, -- Arcane Dust
                { itemID = 22446, qty = 1 }, -- Planar Essence
            },
        },
    },
}

local function ParseItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function GetCraftingCharacterKey()
    local playerName, playerRealm = nil, nil
    if type(UnitFullName) == "function" then
        playerName, playerRealm = UnitFullName("player")
    end
    if not playerName or playerName == "" then
        playerName = (type(UnitName) == "function" and UnitName("player")) or "Unknown"
    end
    if not playerRealm or playerRealm == "" then
        playerRealm = (type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName())
            or (type(GetRealmName) == "function" and GetRealmName())
            or "Realm"
    end
    return tostring(playerName) .. "-" .. tostring(playerRealm)
end

local function GetKnownCraftingStore()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB() or nil
    if not realmDB then return {} end
    if not realmDB.KnownCraftingRecipesByCharacter then
        realmDB.KnownCraftingRecipesByCharacter = {}
    end

    local charKey = GetCraftingCharacterKey()
    if not realmDB.KnownCraftingRecipesByCharacter[charKey] then
        realmDB.KnownCraftingRecipesByCharacter[charKey] = {}
    end

    local charStore = realmDB.KnownCraftingRecipesByCharacter[charKey]

    -- One-time migration path from legacy realm-wide store to this character's slot.
    if next(charStore) == nil and type(realmDB.KnownCraftingRecipes) == "table" then
        for profName, payload in pairs(realmDB.KnownCraftingRecipes) do
            if type(payload) == "table" and type(payload.recipes) == "table" then
                charStore[tostring(profName)] = {
                    updatedAt = tonumber(payload.updatedAt) or time(),
                    recipes = payload.recipes,
                }
            end
        end
    end

    return charStore
end

local function GetKnownProfessionStore()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB() or nil
    if not realmDB then return { updatedAt = 0, professions = {} } end
    if not realmDB.KnownProfessionsByCharacter then
        realmDB.KnownProfessionsByCharacter = {}
    end

    local charKey = GetCraftingCharacterKey()
    local payload = realmDB.KnownProfessionsByCharacter[charKey]
    if type(payload) ~= "table" then
        payload = {}
    end

    if type(payload.professions) ~= "table" then
        local migrated = {}
        for key, value in pairs(payload) do
            if type(key) == "string" and key ~= "updatedAt" and value then
                migrated[key] = true
            end
        end

        if next(migrated) == nil and type(realmDB.KnownProfessions) == "table" then
            for key, value in pairs(realmDB.KnownProfessions) do
                if type(key) == "string" and value then
                    migrated[key] = true
                elseif type(value) == "string" and value ~= "" then
                    migrated[value] = true
                end
            end
        end
        payload.professions = migrated
    end

    payload.updatedAt = tonumber(payload.updatedAt) or 0
    realmDB.KnownProfessionsByCharacter[charKey] = payload
    return payload
end

local function SetToSortedList(set)
    local out = {}
    for name, enabled in pairs(set or {}) do
        if enabled then
            out[#out + 1] = tostring(name)
        end
    end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function HasTradeSkillRecipeAPI()
    return type(GetTradeSkillLine) == "function"
        and type(GetNumTradeSkills) == "function"
        and type(GetTradeSkillInfo) == "function"
end

local NON_CRAFTING_PROFESSIONS = {
    ["Skinning"] = true,
    ["Mining"] = true,
    ["Herbalism"] = true,
    ["Fishing"] = true,
    ["Riding"] = true,
    ["Lockpicking"] = true,
}

local CRAFTING_PROFESSIONS = {
    ["Alchemy"] = true,
    ["Blacksmithing"] = true,
    ["Enchanting"] = true,
    ["Engineering"] = true,
    ["Inscription"] = true,
    ["Jewelcrafting"] = true,
    ["Leatherworking"] = true,
    ["Tailoring"] = true,
    ["Cooking"] = true,
    ["First Aid"] = true,
}

local function IsCraftingProfessionName(name)
    local prof = tostring(name or "")
    if prof == "" then return false end
    if CRAFTING_PROFESSIONS[prof] then
        return true
    end
    if NON_CRAFTING_PROFESSIONS[prof] then
        return false
    end
    return false
end

local function GetPlayerProfessionSet()
    local out = {}
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local a, b, c, d, e = GetProfessions()
        for _, idx in ipairs({ a, b, c, d, e }) do
            if idx then
                local name = GetProfessionInfo(idx)
                if name and name ~= "" and IsCraftingProfessionName(name) then
                    out[tostring(name)] = true
                end
            end
        end
    end

    -- Classic fallback when GetProfessions() is unavailable/unreliable.
    if next(out) == nil and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local numLinesRaw = GetNumSkillLines() or 0
        local numLines = tonumber(numLinesRaw) or 0
        for i = 1, numLines do
            local name, isHeader = GetSkillLineInfo(i)
            if name and not isHeader and IsCraftingProfessionName(name) then
                out[tostring(name)] = true
            end
        end
    end

    return out
end

function MarketSync.RefreshKnownProfessionCache()
    local liveSet = GetPlayerProfessionSet()
    local store = GetKnownProfessionStore()

    if next(liveSet) ~= nil then
        store.professions = {}
        for name in pairs(liveSet) do
            if IsCraftingProfessionName(name) then
                store.professions[tostring(name)] = true
            end
        end
        store.updatedAt = time()
    elseif type(store.professions) ~= "table" then
        store.professions = {}
    end

    return SetToSortedList(store.professions), tonumber(store.updatedAt) or 0
end

function MarketSync.GetCachedCraftingProfessions()
    local store = GetKnownProfessionStore()
    return SetToSortedList(store.professions), tonumber(store.updatedAt) or 0
end

local function ScanCurrentTradeSkillRecipes()
    if not HasTradeSkillRecipeAPI() then
        return nil, {}
    end

    local professionName = GetTradeSkillLine and GetTradeSkillLine() or nil
    if not professionName or professionName == "" or professionName == "UNKNOWN" then
        return nil, {}
    end

    local recipes = {}
    local seen = {}

    local numSkillsRaw = (GetNumTradeSkills and GetNumTradeSkills()) or 0
    local numSkills = tonumber(numSkillsRaw) or 0
    for i = 1, numSkills do
        local recipeName, skillType, _, _, _, numSkillUps = GetTradeSkillInfo(i)
        if recipeName and skillType ~= "header" and skillType ~= "subheader" then
            local outputLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
            local outputItemID = ParseItemIDFromLink(outputLink)
            local outputQtyRaw = (GetTradeSkillNumMade and GetTradeSkillNumMade(i)) or 1
            local outputQty = tonumber(outputQtyRaw) or 1
            outputQty = math.max(1, outputQty or 1)

            local mats = {}
            local reagentCountRaw = (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i)) or 0
            local reagentCount = tonumber(reagentCountRaw) or 0
            for r = 1, reagentCount do
                local reagentLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, r) or nil
                local reagentItemID = ParseItemIDFromLink(reagentLink)

                local qty = 1
                if GetTradeSkillReagentInfo then
                    local _, _, numRequired = GetTradeSkillReagentInfo(i, r)
                    qty = tonumber(numRequired) or qty
                elseif GetTradeSkillReagentCount then
                    local qtyRaw = GetTradeSkillReagentCount(i, r)
                    qty = tonumber(qtyRaw) or qty
                end

                if reagentItemID then
                    mats[#mats + 1] = {
                        itemID = reagentItemID,
                        qty = math.max(1, math.floor(tonumber(qty) or 1)),
                    }
                end
            end

            if outputItemID and #mats > 0 then
                local dedupeKey = tostring(outputItemID) .. ":" .. tostring(recipeName)
                if not seen[dedupeKey] then
                    seen[dedupeKey] = true
                    recipes[#recipes + 1] = {
                        name = recipeName,
                        outputItemID = outputItemID,
                        outputQty = outputQty,
                        skillType = tostring(skillType or ""),
                        numSkillUps = tonumber(numSkillUps),
                        mats = mats,
                        recipeIndex = i,
                    }
                end
            end
        end
    end

    return tostring(professionName), recipes
end

function MarketSync.RefreshKnownCraftingRecipes()
    local professionName, recipes = ScanCurrentTradeSkillRecipes()
    MarketSync.RefreshKnownProfessionCache()

    if not professionName then
        return false
    end

    local store = GetKnownCraftingStore()
    store[professionName] = {
        updatedAt = time(),
        recipes = recipes or {},
    }
    return type(recipes) == "table" and #recipes > 0
end

function MarketSync.IsProfessionResyncInProgress()
    return false
end

local function BuildProfessionResyncQueue()
    local out = {}
    local seen = {}

    local function Add(name)
        local prof = tostring(name or "")
        if prof == "" or not IsCraftingProfessionName(prof) or seen[prof] then
            return
        end
        seen[prof] = true
        out[#out + 1] = prof
    end

    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local a, b, c, d, e = GetProfessions()
        for _, idx in ipairs({ a, b, c, d, e }) do
            if idx then
                local name = GetProfessionInfo(idx)
                Add(name)
            end
        end
    end

    local cached = MarketSync.GetCachedCraftingProfessions and MarketSync.GetCachedCraftingProfessions() or {}
    for _, prof in ipairs(cached) do
        Add(prof)
    end

    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function CountIndexedResyncProfessions(queue)
    local store = GetKnownCraftingStore()
    local indexed = 0
    local missing = {}

    for _, prof in ipairs(queue or {}) do
        local cached = store[prof]
        if type(cached) == "table" and type(cached.recipes) == "table" and #cached.recipes > 0 then
            indexed = indexed + 1
        else
            missing[#missing + 1] = prof
        end
    end

    return indexed, missing
end

function MarketSync.ResyncProfessionCache(onComplete)
    local callback = (type(onComplete) == "function") and onComplete or nil
    MarketSync.RefreshKnownProfessionCache()

    local queue = BuildProfessionResyncQueue()
    if #queue == 0 then
        local msg = "No crafting professions detected. Open your Skills window and click Resync again."
        if callback then
            pcall(callback, false, msg, 0, 0)
        end
        return false, msg
    end

    -- Protected spell-cast APIs cannot be safely invoked from addon timers.
    -- Resync now captures whichever profession window is currently open.
    local scannedNow = 0
    local openProfession = HasTradeSkillRecipeAPI() and (GetTradeSkillLine and GetTradeSkillLine() or nil) or nil
    if openProfession and openProfession ~= "" and openProfession ~= "UNKNOWN" and IsCraftingProfessionName(openProfession) then
        local ok, refreshed = pcall(MarketSync.RefreshKnownCraftingRecipes)
        if ok and refreshed == true then
            scannedNow = 1
        end
    end

    local indexed, missing = CountIndexedResyncProfessions(queue)
    local success = indexed >= #queue
    local msg

    if success then
        msg = string.format("Profession cache ready: %d/%d indexed.", indexed, #queue)
    elseif scannedNow > 0 then
        local nextProf = missing[1] or "another profession"
        msg = string.format("Indexed %d/%d. Open %s and click Resync again.", indexed, #queue, tostring(nextProf))
    else
        local nextProf = missing[1] or "a crafting profession"
        msg = string.format("Open %s and click Resync while its profession window is visible.", tostring(nextProf))
    end

    if callback then
        pcall(callback, success, msg, indexed, #queue)
    end

    return success, msg, #queue
end

local function GetRecipesForProfession(professionName)
    local prof = professionName and tostring(professionName) or nil
    if not prof or prof == "" then return {} end

    local store = GetKnownCraftingStore()
    local cached = store[prof]
    if cached and type(cached.recipes) == "table" and #cached.recipes > 0 then
        return cached.recipes
    end

    -- Fallback only when trade-skill introspection isn't available on this client.
    if not HasTradeSkillRecipeAPI() then
        return (MarketSync.CraftingData and MarketSync.CraftingData[prof]) or {}
    end

    return {}
end

function MarketSync.GetCraftRecipeCount(professionName)
    local recipes = GetRecipesForProfession(professionName)
    return #recipes
end

local function GetItemName(itemID)
    if not itemID then return nil end
    local cached = MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID]
    if cached and cached.n then return cached.n end
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
    if name and MarketSyncDB and MarketSyncDB.ItemInfoCache then
        MarketSyncDB.ItemInfoCache[itemID] = MarketSyncDB.ItemInfoCache[itemID] or {}
        MarketSyncDB.ItemInfoCache[itemID].n = name
    end
    return name
end

local function GetPriceByItemID(itemID)
    if not itemID or not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER_ID, itemID)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

local function GetAgeByItemID(itemID)
    if not itemID or not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end

    local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemID, CALLER_ID, tonumber(itemID))
    if ok and type(age) == "number" and age >= 0 then
        return age
    end
    return nil
end

local function GetPriceInfoByItemID(itemID)
    local price = GetPriceByItemID(itemID)
    local age = GetAgeByItemID(itemID)
    local stale = (type(age) == "number" and age > STALE_PRICE_DAYS) or false
    return price, age, stale
end

-- Estimate the disenchant EV for a generic item of given quality / ilvl / slot.
-- Returns evCopper (number or nil), stale (bool), missingCount (int)
local function EstimateDisenchantEV(quality, itemLevel, isWeapon)
    local q = tonumber(quality)
    local ilvl = tonumber(itemLevel)
    if not q or not ilvl then return nil, false, 0 end

    local rows = MarketSync.DisenchantTable[q]
    if not rows then return nil, false, 0 end

    -- Rare / Epic path — single output type
    if q >= 3 then
        for _, row in ipairs(rows) do
            if ilvl >= row[1] and ilvl <= row[2] then
                local price = GetPriceByItemID(row[3])
                if price and price > 0 then
                    local avgQty = (row[4] + row[5]) / 2
                    local _, age, stale = GetPriceInfoByItemID(row[3])
                    return math.floor(price * avgQty), stale or false, 0
                end
                return nil, false, 1
            end
        end
        return nil, false, 0
    end

    -- Uncommon (quality 2) path — dust / essence / shard mix
    for _, row in ipairs(rows) do
        if ilvl >= row[1] and ilvl <= row[2] then
            local dustID   = row[3]
            local dustMin  = row[4]
            local dustMax  = row[5]
            local essID    = row[6]
            local essMin   = row[7]
            local essMax   = row[8]
            local shardID  = row[9]
            local shardMin = row[10]
            local shardMax = row[11]

            -- Probabilities depend on armor vs weapon
            local dustProb, essProb, shardProb
            if shardID then
                shardProb = 0.05
                if isWeapon then
                    dustProb = 0.20
                    essProb  = 0.75
                else
                    dustProb = 0.75
                    essProb  = 0.20
                end
            else
                shardProb = 0
                if isWeapon then
                    dustProb = 0.20
                    essProb  = 0.80
                else
                    dustProb = 0.80
                    essProb  = 0.20
                end
            end

            local ev = 0
            local missingCount = 0
            local anyStale = false

            -- Dust contribution
            if dustID then
                local dustPrice, _, dustStale = GetPriceInfoByItemID(dustID)
                if dustPrice and dustPrice > 0 then
                    ev = ev + dustProb * ((dustMin + dustMax) / 2) * dustPrice
                    if dustStale then anyStale = true end
                else
                    missingCount = missingCount + 1
                end
            end

            -- Essence contribution
            if essID then
                local essPrice, _, essStale = GetPriceInfoByItemID(essID)
                if essPrice and essPrice > 0 then
                    ev = ev + essProb * ((essMin + essMax) / 2) * essPrice
                    if essStale then anyStale = true end
                else
                    missingCount = missingCount + 1
                end
            end

            -- Shard contribution
            if shardID and shardProb > 0 then
                local shardPrice, _, shardStale = GetPriceInfoByItemID(shardID)
                if shardPrice and shardPrice > 0 then
                    ev = ev + shardProb * ((shardMin + shardMax) / 2) * shardPrice
                    if shardStale then anyStale = true end
                else
                    missingCount = missingCount + 1
                end
            end

            if ev > 0 then
                return math.floor(ev), anyStale, missingCount
            end
            return nil, anyStale, missingCount
        end
    end

    return nil, false, 0
end

-- Public API for UI or other modules
function MarketSync.EstimateDisenchantEV(quality, itemLevel, isWeapon)
    return EstimateDisenchantEV(quality, itemLevel, isWeapon)
end

local function ExpectedYield(y)
    local minV = tonumber(y.min) or 0
    local maxV = tonumber(y.max) or minV
    local prob = tonumber(y.prob) or 0
    return ((minV + maxV) / 2) * prob
end

local function CalculateInputEV(inputItemID, def)
    local ev = 0
    local hasAnyPrice = false
    local hasStaleOutput = false
    local missingOutputs = 0
    for _, y in ipairs(def.yields or {}) do
        local outPrice, _, outStale = GetPriceInfoByItemID(y.itemID)
        if outPrice and outPrice > 0 then
            hasAnyPrice = true
            ev = ev + (ExpectedYield(y) * outPrice)
            if outStale then
                hasStaleOutput = true
            end
        else
            missingOutputs = missingOutputs + 1
        end
    end
    if not hasAnyPrice then
        return nil, hasStaleOutput, missingOutputs
    end
    return ev, hasStaleOutput, missingOutputs
end

function MarketSync.GetProcessingTargets()
    local seen = {}
    local out = {}

    -- Prospect / Mill yield targets
    for _, def in pairs(MarketSync.ProcessingData or {}) do
        if IsProcessTypeSupported(def.type) then
            for _, y in ipairs(def.yields or {}) do
                if y.itemID and not seen[y.itemID] then
                    seen[y.itemID] = true
                    table.insert(out, {
                        itemID = y.itemID,
                        name = GetItemName(y.itemID) or ("Item " .. tostring(y.itemID)),
                    })
                end
            end
        end
    end

    -- Disenchant output materials (dusts, essences, shards, crystals)
    if IsProcessTypeSupported("DISENCHANT") then
        for _, rows in pairs(MarketSync.DisenchantTable or {}) do
            for _, row in ipairs(rows) do
                -- Uncommon rows have 11 fields; Rare/Epic have 5
                local ids = {}
                if #row >= 11 then
                    -- dustID, essID, shardID
                    if row[3] then ids[#ids+1] = row[3] end
                    if row[6] then ids[#ids+1] = row[6] end
                    if row[9] then ids[#ids+1] = row[9] end
                elseif #row >= 5 then
                    if row[3] then ids[#ids+1] = row[3] end
                end
                for _, id in ipairs(ids) do
                    if id and not seen[id] then
                        seen[id] = true
                        table.insert(out, {
                            itemID = id,
                            name = GetItemName(id) or ("Item " .. tostring(id)),
                        })
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local na = string.lower(a.name or "")
        local nb = string.lower(b.name or "")
        if na == nb then
            return (tonumber(a.itemID) or 0) < (tonumber(b.itemID) or 0)
        end
        return na < nb
    end)
    return out
end

function MarketSync.GetProcessingProfessions()
    MarketSync.RefreshKnownCraftingRecipes()
    local playerProfSet = GetPlayerProfessionSet()
    local cachedProfessions = MarketSync.RefreshKnownProfessionCache()
    local knownProfessionSet = {}

    for name in pairs(playerProfSet) do
        if IsCraftingProfessionName(name) then
            knownProfessionSet[tostring(name)] = true
        end
    end
    for _, name in ipairs(cachedProfessions or {}) do
        if IsCraftingProfessionName(name) then
            knownProfessionSet[tostring(name)] = true
        end
    end

    local hasKnownProfs = next(knownProfessionSet) ~= nil
    local out = {}
    local seen = {}

    local function AddProfessionIfEligible(name)
        local prof = tostring(name or "")
        if prof == "" then return end
        if seen[prof] then return end
        if hasKnownProfs and not knownProfessionSet[prof] then
            return
        end
        local knownRecipes = MarketSync.GetCraftRecipeCount(prof)
        if knownRecipes > 0 or (hasKnownProfs and knownProfessionSet[prof] and IsCraftingProfessionName(prof)) then
            seen[prof] = true
            out[#out + 1] = prof
        end
    end

    for name in pairs(knownProfessionSet) do
        AddProfessionIfEligible(name)
    end

    local knownRecipeStore = GetKnownCraftingStore()
    for name, payload in pairs(knownRecipeStore) do
        if type(name) == "string" and type(payload) == "table" then
            AddProfessionIfEligible(name)
        end
    end

    -- Fallback path if profession APIs are unavailable.
    if #out == 0 and not hasKnownProfs then
        for name in pairs(MarketSync.CraftingData or {}) do
            AddProfessionIfEligible(name)
        end
    end

    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function MarketSync.GetProcessingStaleThresholdDays()
    return STALE_PRICE_DAYS
end

local function GetProcessingCustomSelectionStore()
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB() or nil
    if not realmDB then return {} end
    if not realmDB.ProcessingCustomSelections then
        realmDB.ProcessingCustomSelections = {}
    end
    return realmDB.ProcessingCustomSelections
end

local function NormalizeSelectionMode(mode)
    local v = tostring(mode or ""):lower()
    if v == "target" or v == "process" or v == "craft" then
        return v
    end
    return "target"
end

local function NormalizeProcessType(value)
    if value == nil then return nil end
    local v = tostring(value):upper()
    if v == "" or v == "ALL" then return nil end
    if IsProcessTypeSupported(v) then
        return v
    end
    return nil
end

function MarketSync.ListProcessingCustomSelections()
    local store = GetProcessingCustomSelectionStore()
    local out = {}
    for _, entry in ipairs(store) do
        if type(entry) == "table" and entry.id and entry.name then
            out[#out + 1] = {
                id = entry.id,
                name = entry.name,
                mode = NormalizeSelectionMode(entry.mode),
                targetItemID = tonumber(entry.targetItemID),
                processType = NormalizeProcessType(entry.processType),
                profession = entry.profession and tostring(entry.profession) or nil,
                marginPct = tonumber(entry.marginPct) or 10,
                minCraftMarginGold = tonumber(entry.minCraftMarginGold) or 5,
            }
        end
    end

    table.sort(out, function(a, b)
        local na = string.lower(a.name or "")
        local nb = string.lower(b.name or "")
        if na == nb then
            return tostring(a.id) < tostring(b.id)
        end
        return na < nb
    end)
    return out
end

function MarketSync.UpsertProcessingCustomSelection(selection)
    if type(selection) ~= "table" then return nil, "Invalid selection payload" end

    local name = tostring(selection.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil, "Selection name is required"
    end

    local store = GetProcessingCustomSelectionStore()
    local id = selection.id
    if not id or id == "" then
        id = tostring(time()) .. "-" .. tostring(math.random(1000, 9999))
    end

    local payload = {
        id = id,
        name = name,
        mode = NormalizeSelectionMode(selection.mode),
        targetItemID = tonumber(selection.targetItemID),
        processType = NormalizeProcessType(selection.processType),
        profession = selection.profession and tostring(selection.profession) or nil,
        marginPct = tonumber(selection.marginPct) or 10,
        minCraftMarginGold = tonumber(selection.minCraftMarginGold) or 5,
    }

    for i, existing in ipairs(store) do
        if existing and existing.id == id then
            store[i] = payload
            return payload
        end
    end

    table.insert(store, payload)
    return payload
end

function MarketSync.DeleteProcessingCustomSelection(selectionID)
    local id = selectionID and tostring(selectionID) or nil
    if not id or id == "" then return false end
    local store = GetProcessingCustomSelectionStore()
    for i, existing in ipairs(store) do
        if existing and tostring(existing.id) == id then
            table.remove(store, i)
            return true
        end
    end
    return false
end

function MarketSync.FindArbitrageByTarget(targetItemID, marginPercent)
    local targetPrice, targetAge, targetStale = GetPriceInfoByItemID(targetItemID)
    if not targetPrice or targetPrice <= 0 then
        return {}
    end

    local margin = tonumber(marginPercent) or 0
    local marginMult = math.max(0, 1 - (margin / 100))
    local results = {}

    -- 1. Prospect / Mill sources from ProcessingData
    for inputItemID, def in pairs(MarketSync.ProcessingData or {}) do
        if IsProcessTypeSupported(def.type) then
            local expectedTarget = 0
            for _, y in ipairs(def.yields or {}) do
                if tonumber(y.itemID) == tonumber(targetItemID) then
                    expectedTarget = expectedTarget + ExpectedYield(y)
                end
            end
            if expectedTarget > 0 then
                local stackSize = tonumber(def.stackSize) or 1
                local maxBuyPerStack = targetPrice * expectedTarget * marginMult
                local maxBuyPerUnit = math.floor(maxBuyPerStack / math.max(1, stackSize))
                local livePrice, liveAge, liveStale = GetPriceInfoByItemID(inputItemID)
                livePrice = livePrice or 0
                table.insert(results, {
                    inputItemID = inputItemID,
                    inputName = GetItemName(inputItemID) or ("Item " .. tostring(inputItemID)),
                    processType = def.type,
                    stackSize = stackSize,
                    targetItemID = targetItemID,
                    targetName = GetItemName(targetItemID) or ("Item " .. tostring(targetItemID)),
                    targetPrice = targetPrice,
                    targetAge = targetAge,
                    targetStale = targetStale,
                    expectedTarget = expectedTarget,
                    maxBuyPerUnit = maxBuyPerUnit,
                    maxBuyPerStack = math.floor(maxBuyPerStack),
                    livePrice = livePrice,
                    liveAge = liveAge,
                    liveStale = liveStale,
                    profitable = (livePrice > 0 and livePrice <= maxBuyPerUnit),
                })
            end
        end
    end

    -- 2. Disenchant sources — find items in ItemInfoCache whose DE table yields the target material
    if IsProcessTypeSupported("DISENCHANT") then
        local tid = tonumber(targetItemID)
        local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
        if tid and type(cache) == "table" then
            for itemID, info in pairs(cache) do
                if type(info) == "table" then
                    local quality = tonumber(info.r) or 0
                    local ilvl = tonumber(info.i) or 0
                    local classID = tonumber(info.c)

                    if quality >= 2 and quality <= 4 and (classID == 2 or classID == 4) and ilvl > 0 then
                        local isWeapon = (classID == 2)
                        -- Check if this item's DE table includes the target material
                        local rows = MarketSync.DisenchantTable[quality]
                        if rows then
                            for _, row in ipairs(rows) do
                                if ilvl >= row[1] and ilvl <= row[2] then
                                    local yieldsTarget = false
                                    local expectedQty = 0

                                    if #row >= 11 then
                                        -- Uncommon: check dust, essence, shard
                                        local dustProb = isWeapon and 0.20 or 0.75
                                        local essProb  = isWeapon and 0.75 or 0.20
                                        local shardProb = row[9] and 0.05 or 0
                                        if not row[9] then
                                            dustProb = isWeapon and 0.20 or 0.80
                                            essProb  = isWeapon and 0.80 or 0.20
                                        end

                                        if row[3] == tid then
                                            yieldsTarget = true
                                            expectedQty = dustProb * ((row[4] + row[5]) / 2)
                                        end
                                        if row[6] == tid then
                                            yieldsTarget = true
                                            expectedQty = expectedQty + essProb * ((row[7] + row[8]) / 2)
                                        end
                                        if row[9] and row[9] == tid then
                                            yieldsTarget = true
                                            expectedQty = expectedQty + shardProb * ((row[10] + row[11]) / 2)
                                        end
                                    elseif #row >= 5 then
                                        -- Rare/Epic: single output
                                        if row[3] == tid then
                                            yieldsTarget = true
                                            expectedQty = (row[4] + row[5]) / 2
                                        end
                                    end

                                    if yieldsTarget and expectedQty > 0 then
                                        local maxBuy = math.floor(targetPrice * expectedQty * marginMult)
                                        local livePrice, liveAge, liveStale = GetPriceInfoByItemID(itemID)
                                        livePrice = livePrice or 0
                                        if livePrice > 0 then
                                            table.insert(results, {
                                                inputItemID = tonumber(itemID),
                                                inputName = info.n or ("Item " .. tostring(itemID)),
                                                processType = "DISENCHANT",
                                                stackSize = 1,
                                                targetItemID = targetItemID,
                                                targetName = GetItemName(targetItemID) or ("Item " .. tostring(targetItemID)),
                                                targetPrice = targetPrice,
                                                targetAge = targetAge,
                                                targetStale = targetStale,
                                                expectedTarget = expectedQty,
                                                maxBuyPerUnit = maxBuy,
                                                maxBuyPerStack = maxBuy,
                                                livePrice = livePrice,
                                                liveAge = liveAge,
                                                liveStale = liveStale,
                                                profitable = (livePrice <= maxBuy),
                                            })
                                        end
                                    end
                                    break -- Only one ilvl row matches
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if (a.profitable and not b.profitable) then return true end
        if (b.profitable and not a.profitable) then return false end
        return (a.maxBuyPerUnit or 0) > (b.maxBuyPerUnit or 0)
    end)

    return results
end

function MarketSync.FindArbitrageByProcess(processType, marginPercent)
    local requestedProcess = processType and tostring(processType):upper() or nil
    local normalizedProcess = NormalizeProcessType(processType)
    if requestedProcess and requestedProcess ~= "" and requestedProcess ~= "ALL" and not normalizedProcess then
        return {}
    end
    processType = normalizedProcess

    local margin = tonumber(marginPercent) or 0
    local marginMult = math.max(0, 1 - (margin / 100))
    local results = {}

    -- 1. Prospect / Mill entries from ProcessingData (unchanged)
    for inputItemID, def in pairs(MarketSync.ProcessingData or {}) do
        if IsProcessTypeSupported(def.type) and (not processType or def.type == processType) then
            local evPerAction, evStale, missingOutputs = CalculateInputEV(inputItemID, def)
            if evPerAction and evPerAction > 0 then
                local stackSize = tonumber(def.stackSize) or 1
                local evPerUnit = evPerAction / math.max(1, stackSize)
                local maxBuyPerUnit = math.floor(evPerUnit * marginMult)
                local livePrice, liveAge, liveStale = GetPriceInfoByItemID(inputItemID)
                livePrice = livePrice or 0
                table.insert(results, {
                    inputItemID = inputItemID,
                    inputName = GetItemName(inputItemID) or ("Item " .. tostring(inputItemID)),
                    processType = def.type,
                    stackSize = stackSize,
                    evPerAction = math.floor(evPerAction),
                    evPerUnit = math.floor(evPerUnit),
                    evStale = evStale,
                    missingOutputs = missingOutputs,
                    maxBuyPerUnit = maxBuyPerUnit,
                    livePrice = livePrice,
                    liveAge = liveAge,
                    liveStale = liveStale,
                    profitable = (livePrice > 0 and livePrice <= maxBuyPerUnit),
                })
            end
        end
    end

    -- 2. Disenchant entries — scan existing ItemInfoCache
    if IsProcessTypeSupported("DISENCHANT") and (not processType or processType == "DISENCHANT") then
        local cache = MarketSyncDB and MarketSyncDB.ItemInfoCache
        if type(cache) == "table" then
            for itemID, info in pairs(cache) do
                if type(info) == "table" then
                    local quality = tonumber(info.r) or 0
                    local ilvl = tonumber(info.i) or 0
                    local classID = tonumber(info.c)

                    -- Only equipment (Weapons = 2, Armor = 4) with Uncommon+ quality
                    if quality >= 2 and quality <= 4 and (classID == 2 or classID == 4) and ilvl > 0 then
                        local isWeapon = (classID == 2)
                        local deEV, deStale, deMissing = EstimateDisenchantEV(quality, ilvl, isWeapon)

                        if deEV and deEV > 0 then
                            local maxBuyPerUnit = math.floor(deEV * marginMult)
                            local livePrice, liveAge, liveStale = GetPriceInfoByItemID(itemID)
                            livePrice = livePrice or 0

                            -- Only include items that have a live AH price (i.e. actually listed)
                            if livePrice > 0 then
                                table.insert(results, {
                                    inputItemID = tonumber(itemID),
                                    inputName = info.n or ("Item " .. tostring(itemID)),
                                    processType = "DISENCHANT",
                                    stackSize = 1,
                                    evPerAction = deEV,
                                    evPerUnit = deEV,
                                    evStale = deStale,
                                    missingOutputs = deMissing,
                                    maxBuyPerUnit = maxBuyPerUnit,
                                    livePrice = livePrice,
                                    liveAge = liveAge,
                                    liveStale = liveStale,
                                    profitable = (livePrice <= maxBuyPerUnit),
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if (a.profitable and not b.profitable) then return true end
        if (b.profitable and not a.profitable) then return false end
        return (a.evPerUnit or 0) > (b.evPerUnit or 0)
    end)
    return results
end

local function BuildAuctionatorSearchString(name, maxPrice, quantity)
    if not name or name == "" then
        return nil
    end

    local term = {
        searchString = name,
        isExact = true,
    }
    if tonumber(maxPrice) and tonumber(maxPrice) > 0 then
        term.maxPrice = math.floor(tonumber(maxPrice))
    end
    if tonumber(quantity) and tonumber(quantity) > 0 then
        term.quantity = math.floor(tonumber(quantity))
    end

    local okConv, searchString = pcall(Auctionator.API.v1.ConvertToSearchString, CALLER_ID, term)
    if okConv and type(searchString) == "string" and searchString ~= "" then
        return searchString
    end

    return '"' .. name .. '"'
end

function MarketSync.ExportArbitrageToAuctionator(results, listName)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return false, "Auctionator API unavailable"
    end
    if not results or #results == 0 then
        return false, "No results to export"
    end

    local exportName = listName or ("MarketSync Arbitrage " .. date("%m/%d %H:%M"))
    local searchStrings = {}
    local seenInput = {}

    for _, r in ipairs(results) do
        if r.inputItemID and not seenInput[r.inputItemID] and (r.maxBuyPerUnit or 0) > 0 then
            seenInput[r.inputItemID] = true
            local name = GetItemName(r.inputItemID)
            if name then
                local searchString = BuildAuctionatorSearchString(name, math.max(1, math.floor(r.maxBuyPerUnit)))
                if searchString then
                    table.insert(searchStrings, searchString)
                end
            end
        end
    end

    if #searchStrings == 0 then
        return false, "No valid export entries"
    end

    local okCreate, err = pcall(Auctionator.API.v1.CreateShoppingList, CALLER_ID, exportName, searchStrings)
    if not okCreate then
        return false, tostring(err)
    end
    return true, #searchStrings
end

function MarketSync.FindProfitableCrafts(professionName, minMarginCopper)
    MarketSync.RefreshKnownCraftingRecipes()

    local recipes = GetRecipesForProfession(professionName)
    if not recipes then return {} end

    local minMargin = tonumber(minMarginCopper) or 0
    local out = {}

    for _, recipe in ipairs(recipes) do
        local outputPrice, outputAge, outputStale = GetPriceInfoByItemID(recipe.outputItemID)
        outputPrice = outputPrice or 0
        if outputPrice > 0 then
            local craftCost = 0
            local hasMissing = false
            local hasStaleMat = false
            local matsDetailed = {}
            for _, mat in ipairs(recipe.mats or {}) do
                local matPrice, matAge, matStale = GetPriceInfoByItemID(mat.itemID)
                if not matPrice or matPrice <= 0 then
                    hasMissing = true
                    break
                end
                local qty = tonumber(mat.qty) or 1
                craftCost = craftCost + (matPrice * qty)
                matsDetailed[#matsDetailed + 1] = {
                    itemID = mat.itemID,
                    qty = qty,
                    price = matPrice,
                    age = matAge,
                    stale = matStale,
                }
                if matStale then
                    hasStaleMat = true
                end
            end
            if not hasMissing then
                local outputQty = tonumber(recipe.outputQty) or 1
                local revenue = math.floor(outputPrice * outputQty * 0.95) -- AH cut
                local margin = revenue - craftCost
                local maxCraftCost = math.max(0, revenue - minMargin)
                local matCapScale = (craftCost > 0) and (maxCraftCost / craftCost) or 1
                for _, matInfo in ipairs(matsDetailed) do
                    matInfo.capPrice = math.max(1, math.floor((matInfo.price or 0) * matCapScale))
                end

                table.insert(out, {
                    profession = professionName,
                    recipeName = recipe.name or ("Item " .. tostring(recipe.outputItemID)),
                    outputItemID = recipe.outputItemID,
                    outputName = GetItemName(recipe.outputItemID) or ("Item " .. tostring(recipe.outputItemID)),
                    skillType = recipe.skillType,
                    numSkillUps = recipe.numSkillUps,
                    recipeIndex = recipe.recipeIndex,
                    craftCost = craftCost,
                    revenue = revenue,
                    margin = margin,
                    meetsMargin = (margin >= minMargin),
                    outputAge = outputAge,
                    outputStale = outputStale,
                    hasStaleMat = hasStaleMat,
                    maxCraftCost = maxCraftCost,
                    matCapScale = matCapScale,
                    matsDetailed = matsDetailed,
                    mats = recipe.mats,
                })
            end
        end
    end

    table.sort(out, function(a, b) return (a.margin or 0) > (b.margin or 0) end)
    return out
end

function MarketSync.ExportCraftMatsToAuctionator(craftResults, listName)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return false, "Auctionator API unavailable"
    end
    if not craftResults or #craftResults == 0 then
        return false, "No craft data to export"
    end

    local mats = {}
    for _, c in ipairs(craftResults) do
        local matList = c.matsDetailed or c.mats or {}
        for _, mat in ipairs(matList) do
            if mat.itemID then
                local rec = mats[mat.itemID]
                if not rec then
                    rec = { itemID = mat.itemID, qty = 0, maxPrice = nil }
                    mats[mat.itemID] = rec
                end
                rec.qty = rec.qty + (tonumber(mat.qty) or 1)

                local cap = tonumber(mat.capPrice) or tonumber(mat.price) or GetPriceByItemID(mat.itemID)
                if cap and cap > 0 then
                    if not rec.maxPrice then
                        rec.maxPrice = math.floor(cap)
                    else
                        rec.maxPrice = math.min(rec.maxPrice, math.floor(cap))
                    end
                end
            end
        end
    end

    local searchStrings = {}
    for itemID, matInfo in pairs(mats) do
        local name = GetItemName(itemID)
        if name then
            local searchString = BuildAuctionatorSearchString(name, matInfo.maxPrice, matInfo.qty)
            if searchString then
                table.insert(searchStrings, searchString)
            end
        end
    end

    if #searchStrings == 0 then
        return false, "No materials resolved for export"
    end

    local exportName = listName or ("MarketSync Craft Mats " .. date("%m/%d %H:%M"))
    local okCreate, err = pcall(Auctionator.API.v1.CreateShoppingList, CALLER_ID, exportName, searchStrings)
    if not okCreate then
        return false, tostring(err)
    end

    return true, #searchStrings
end

-- ================================================================
-- TOOLTIP HOOKS (Disenchanting, Milling, Prospecting)
-- ================================================================
local function OnTooltipSetItem(tooltip)
    if not MarketSyncDB or not MarketSyncDB.EnableTooltipProb then return end

    local name, link = tooltip:GetItem()
    if not link then return end
    
    local itemID = MarketSync.ParseItemIDFromDBKey(link)
    if not itemID then return end

    -- 1. Check ProcessingData (Milling/Prospecting)
    if MarketSync.ProcessingData and MarketSync.ProcessingData[itemID] then
        local def = MarketSync.ProcessingData[itemID]
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffffd700MarketSync " .. (def.type or "Processing") .. "|r")
        local evTotal = 0
        local hasStale = false
        for _, y in ipairs(def.yields or {}) do
            local yName = GetItemName(y.itemID) or ("Item " .. y.itemID)
            local expected = ExpectedYield(y)
            local priceInfo = ""
            local price, _, outStale = GetPriceInfoByItemID(y.itemID)
            if price and price > 0 then
                evTotal = evTotal + (price * expected)
                priceInfo = " (" .. MarketSync.FormatMoney(price) .. ")"
                if outStale then hasStale = true end
            end
            
            local probStr = ""
            if y.prob and y.prob < 1.0 then
                probStr = string.format(" %.0f%%", y.prob * 100)
            end
            
            tooltip:AddLine(string.format("- %.1fx %s%s%s", expected, yName, probStr, priceInfo), 0.85, 0.85, 0.85)
        end
        if evTotal > 0 then
            tooltip:AddLine("Expected Value: " .. MarketSync.FormatMoney(evTotal), 0, 1, 0)
            if hasStale then
                tooltip:AddLine("(Based on stale data)", 1, 0.5, 0.5)
            end
        end
    end

    -- Helper to check if another addon already printed breakdown info
    local function HasExternalBreakdown(tooltip, keyword)
        for i = 1, tooltip:NumLines() do
            local line = _G[tooltip:GetName() .. "TextLeft" .. i]
            if line and line:GetText() and line:GetText():find(keyword) then
                return true
            end
        end
        return false
    end

    -- 2. Check Disenchanting
    if MarketSync.EstimateDisenchantEV then
        local _, _, quality, _, _, _, _, _, _, _, _, classID = GetItemInfo(link)
        local ilvl = 0
        if GetDetailedItemLevelInfo then
            ilvl = GetDetailedItemLevelInfo(link)
        end
        if not ilvl or ilvl == 0 then
            ilvl = select(4, GetItemInfo(link)) or 0
        end

        if quality and quality >= 2 and quality <= 4 and (classID == 2 or classID == 4) and ilvl > 0 then
            local isWeapon = (classID == 2)
            local ev, stale, missing = MarketSync.EstimateDisenchantEV(quality, ilvl, isWeapon)
            
            local addedHeader = false
            
            -- Only print full breakdown if Auctionator/TSM hasn't already done it
            if not HasExternalBreakdown(tooltip, "Disenchant") then
                local rows = MarketSync.DisenchantTable[quality]
                if rows then
                    for _, row in ipairs(rows) do
                        if ilvl >= row[1] and ilvl <= row[2] then
                            tooltip:AddLine(" ")
                            tooltip:AddLine("|cffffd700MarketSync Disenchanting|r")
                            addedHeader = true
                            
                            if quality >= 3 then
                                local yName = GetItemName(row[3]) or ("Item " .. row[3])
                                local expected = (row[4] + row[5]) / 2
                                tooltip:AddLine(string.format("- %.1fx %s (100%%)", expected, yName), 0.85, 0.85, 0.85)
                            else
                                local dustID, essID, shardID = row[3], row[6], row[9]
                                local shardProb = shardID and 0.05 or 0
                                local dustProb = isWeapon and 0.20 or (shardID and 0.75 or 0.80)
                                local essProb = isWeapon and (shardID and 0.75 or 0.80) or 0.20
                                
                                if dustID then
                                    local dName = GetItemName(dustID) or ("Item " .. dustID)
                                    local expected = (row[4] + row[5]) / 2
                                    tooltip:AddLine(string.format("- %.1fx %s (%.0f%%)", expected, dName, dustProb*100), 0.85, 0.85, 0.85)
                                end
                                if essID then
                                    local eName = GetItemName(essID) or ("Item " .. essID)
                                    local expected = (row[7] + row[8]) / 2
                                    tooltip:AddLine(string.format("- %.1fx %s (%.0f%%)", expected, eName, essProb*100), 0.85, 0.85, 0.85)
                                end
                                if shardID then
                                    local sName = GetItemName(shardID) or ("Item " .. shardID)
                                    local expected = (row[10] + row[11]) / 2
                                    tooltip:AddLine(string.format("- %.1fx %s (5%%)", expected, sName), 0.85, 0.85, 0.85)
                                end
                            end
                            break
                        end
                    end
                end
            end

            if ev and ev > 0 then
                if not addedHeader then
                    tooltip:AddLine(" ")
                    tooltip:AddLine("|cffffd700MarketSync Disenchanting|r")
                end
                tooltip:AddLine("Expected Value: " .. MarketSync.FormatMoney(ev), 0, 1, 0)
                if stale or missing > 0 then
                    tooltip:AddLine("(Based on incomplete or stale data)", 1, 0.5, 0.5)
                end
            end
        end
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
else
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
end
-- ================================================================
-- ITEM HISTORY DATA EXTRACTION
-- ================================================================
function MarketSync.GetItemHistory(dbKey)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.db then return {} end
    local priceData = Auctionator.Database.db[dbKey]
    if not priceData or not priceData.h then return {} end

    local history = {}
    local meta = MarketSyncDB and MarketSync.GetRealmDB().ItemMetadata and MarketSync.GetRealmDB().ItemMetadata[dbKey]

    for dayStr, highPrice in pairs(priceData.h) do
        local day = tonumber(dayStr)
        if day then
            local lowPrice = priceData.l and priceData.l[dayStr] or highPrice
            local qty = priceData.a and priceData.a[dayStr] or 0

            -- Per-day source attribution
            local source = "Personal"
            if meta and meta.days and meta.days[dayStr] then
                local s = meta.days[dayStr].source
                if s then
                    source = s:match("^([^%-]+)") or s
                end
            elseif day == MarketSync.GetCurrentScanDay() then
                -- Today scan with no metadata = Personal
                source = "Personal"
            end

            table.insert(history, {
                day = day,
                high = highPrice,
                low = lowPrice,
                price = highPrice,
                quantity = qty,
                source = source,
            })
        end
    end

    table.sort(history, function(a, b) return a.day > b.day end)
    return history
end
