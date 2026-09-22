-- =============================================================
-- MarketSync - Processing Arbitrage Module
-- EV calculator + Auctionator shopping list export
-- =============================================================

local CALLER_ID = "MarketSync"
local STALE_PRICE_DAYS = 3
local MAIN_AH_CUT_PERCENT = 5
local MAIN_AH_NET_MULTIPLIER = (100 - MAIN_AH_CUT_PERCENT) / 100
local CRAFT_RECIPE_CACHE_VERSION = 2
local PROCESS_MIN_EXPANSION = {
    DISENCHANT = 0, -- Vanilla+
    PROSPECT = 1,   -- TBC+
    MILL = 2,       -- Wrath+
}
local PROCESS_TYPE_ORDER = { "PROSPECT", "MILL", "DISENCHANT" }

local function SafeGetItemInfo(item)
    if not item then return nil end
    if MarketSync and MarketSync.GetItemInfo then
        return MarketSync.GetItemInfo(item)
    elseif C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    elseif GetItemInfo then
        return GetItemInfo(item)
    end
    return nil
end

local function SafeGetDetailedItemLevelInfo(item)
    if not item then return 0 end
    if MarketSync and MarketSync.GetDetailedItemLevelInfo then
        return MarketSync.GetDetailedItemLevelInfo(item)
    elseif C_Item and C_Item.GetDetailedItemLevelInfo then
        return C_Item.GetDetailedItemLevelInfo(item)
    elseif GetDetailedItemLevelInfo then
        return GetDetailedItemLevelInfo(item)
    end
    return 0
end

local function NetMainAuctionValue(grossValue)
    return math.max(0, tonumber(grossValue) or 0) * MAIN_AH_NET_MULTIPLIER
end

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

local CLIENT_EXPANSION_LEVEL = GetClientExpansionLevel()

local function IsProcessTypeSupported(processType)
    local processKey = tostring(processType or ""):upper()
    local requiredExpansion = PROCESS_MIN_EXPANSION[processKey]
    if requiredExpansion == nil then
        return false
    end
    if CLIENT_EXPANSION_LEVEL < requiredExpansion then
        return false
    end
    if processKey == "DISENCHANT" then
        return true
    end
    for _, def in pairs(MarketSync.ProcessingData or {}) do
        if tostring(def.type or ""):upper() == processKey then
            return true
        end
    end
    return false
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

-- Auctionator stores P(exactly n drops) at index n. This fallback mirrors
-- Auctionator v329 for Classic/TBC and is used only when that table is absent.
local TBC_PROSPECT_FALLBACK = {
    [2770] = { [818] = { 0.50 }, [774] = { 0.50 }, [1210] = { 0.10 } },
    [2771] = {
        [1210] = { 0.35, 0.02 }, [1705] = { 0.36, 0.02 }, [1206] = { 0.36, 0.02 },
        [3864] = { 0.03 }, [1529] = { 0.03 }, [7909] = { 0.03 },
    },
    [2772] = {
        [3864] = { 0.35, 0.011 }, [1705] = { 0.34, 0.011 }, [1529] = { 0.34, 0.012 },
        [7909] = { 0.05 }, [7910] = { 0.05 },
    },
    [3858] = {
        [7910] = { 0.35, 0.011 }, [7909] = { 0.34, 0.011 }, [3864] = { 0.34, 0.012 },
        [12361] = { 0.03 }, [12799] = { 0.03 }, [12800] = { 0.02 }, [12364] = { 0.02 },
    },
    [10620] = {
        [12800] = { 0.28, 0.02 }, [12361] = { 0.28, 0.02 }, [12364] = { 0.28, 0.02 },
        [12799] = { 0.28, 0.02 }, [7910] = { 0.15, 0.006 },
    },
    [23424] = {
        [23077] = { 0.18, 0.003 }, [23079] = { 0.18, 0.002 }, [21929] = { 0.18, 0.004 },
        [23112] = { 0.18, 0.003 }, [23107] = { 0.18, 0.002 }, [23117] = { 0.17, 0.002 },
        [23439] = { 0.012 }, [23440] = { 0.012 }, [23436] = { 0.012 },
        [23441] = { 0.012 }, [23438] = { 0.012 }, [23437] = { 0.012 },
    },
    [23425] = {
        [24243] = { 1.00 },
        [23077] = { 0.17, 0.002 }, [23079] = { 0.18, 0.003 }, [21929] = { 0.18, 0.003 },
        [23112] = { 0.18, 0.003 }, [23107] = { 0.18, 0.003 }, [23117] = { 0.17, 0.003 },
        [23439] = { 0.04 }, [23440] = { 0.04 }, [23436] = { 0.04 },
        [23441] = { 0.04 }, [23438] = { 0.04 }, [23437] = { 0.04 },
    },
}

local PROSPECT_INPUT_MIN_EXPANSION = {
    [2770] = 1, [2771] = 1, [2772] = 1, [3858] = 1, [10620] = 1,
    [23424] = 1, [23425] = 1,
    [36909] = 2, [36912] = 2, [36910] = 2,
    [52185] = 3, [52183] = 3, [53038] = 3,
    [72092] = 4, [72093] = 4, [72094] = 4, [72103] = 4,
}

local function BuildProspectYield(itemID, distribution)
    local copied = {}
    local chance = 0
    local expected = 0
    local minQty, maxQty = nil, nil
    for quantity, probabilityValue in ipairs(distribution or {}) do
        local probability = math.max(0, tonumber(probabilityValue) or 0)
        copied[quantity] = probability
        if probability > 0 then
            chance = chance + probability
            expected = expected + (quantity * probability)
            minQty = minQty or quantity
            maxQty = quantity
        end
    end
    if expected <= 0 then return nil end
    return {
        itemID = tonumber(itemID),
        distribution = copied,
        prob = chance,
        expected = expected,
        min = minQty or 1,
        max = maxQty or 1,
    }
end

local function AddProspectDefinitions(target, source, expansion)
    for inputKey, outputTable in pairs(source or {}) do
        local inputItemID = tonumber(inputKey)
        local minExpansion = inputItemID and PROSPECT_INPUT_MIN_EXPANSION[inputItemID]
        if inputItemID and minExpansion and expansion >= minExpansion and type(outputTable) == "table" then
            local yields = {}
            for outputKey, distribution in pairs(outputTable) do
                local yield = BuildProspectYield(outputKey, distribution)
                if yield and yield.itemID then yields[#yields + 1] = yield end
            end
            table.sort(yields, function(a, b) return a.itemID < b.itemID end)
            if #yields > 0 then
                target[inputItemID] = { type = "PROSPECT", stackSize = 5, yields = yields }
            end
        end
    end
end

local function BuildProcessingDataOnce()
    local expansion = CLIENT_EXPANSION_LEVEL
    local out = {}
    local source = Auctionator and Auctionator.Prospect and Auctionator.Prospect.PROSPECT_TABLE
    if type(source) == "table" then
        AddProspectDefinitions(out, source, expansion)
    end
    if expansion >= 1 then
        local fallbackDefinitions = {}
        AddProspectDefinitions(fallbackDefinitions, TBC_PROSPECT_FALLBACK, expansion)
        for inputItemID, def in pairs(fallbackDefinitions) do
            if not out[inputItemID] then out[inputItemID] = def end
        end
    end
    return out
end

-- Build once at load. Auctionator is a required dependency and is loaded first.
MarketSync.ProcessingData = BuildProcessingDataOnce()

-- Flattened probability rows mirror Auctionator v329. Each outcome triple is
-- probability-percent, quantity, itemID. Runtime Auctionator data is preferred.
local TBC_DISENCHANT_FALLBACK = {
    [4] = { -- Armor
        [2] = {
            {5,15,40,1,10940,40,2,10940,10,1,10938,10,2,10938},
            {16,20,37.5,2,10940,37.5,3,10940,10,1,10939,10,2,10939,5,1,10978},
            {21,25,25,4,10940,25,5,10940,25,6,10940,7.5,1,10998,7.5,2,10998,10,1,10978},
            {26,30,37.5,1,11083,37.5,2,11083,10,1,11082,10,2,11082,5,1,11084},
            {31,35,18.75,2,11083,18.75,3,11083,18.75,4,11083,18.75,5,11083,10,1,11134,10,2,11134,5,1,11138},
            {36,40,37.5,1,11137,37.5,2,11137,10,1,11135,10,2,11135,5,1,11139},
            {41,45,18.75,2,11137,18.75,3,11137,18.75,4,11137,18.75,5,11137,10,1,11174,10,2,11174,5,1,11177},
            {46,50,37.5,1,11176,37.5,2,11176,10,1,11175,10,2,11175,5,1,11178},
            {51,55,18.75,2,11176,18.75,3,11176,18.75,4,11176,18.75,5,11176,10,1,16202,10,2,16202,5,1,14343},
            {56,60,37.5,1,16204,37.5,2,16204,10,1,16203,10,2,16203,5,1,14344},
            {61,65,18.75,2,16204,18.75,3,16204,18.75,4,16204,18.75,5,16204,10,2,16203,10,3,16203,5,1,14344},
            {66,80,25,1,22445,25,2,22445,25,3,22445,7.3333333333333,1,22447,7.3333333333333,2,22447,7.3333333333333,3,22447,3,1,22448},
            {81,99,37.5,2,22445,37.5,3,22445,11,2,22447,11,3,22447,3,1,22448},
            {100,164,18.75,2,22445,18.75,3,22445,18.75,4,22445,18.75,5,22445,11,1,22446,11,2,22446,3,1,22449},
        },
        [3] = {
            {11,25,100,1,10978}, {26,30,100,1,11084}, {31,35,100,1,11138},
            {36,40,100,1,11139}, {41,45,100,1,11177}, {46,50,100,1,11178},
            {51,55,100,1,14343}, {56,65,99.5,1,14344,0.5,1,20725},
            {66,99,99.5,1,22448,0.5,1,20725}, {100,164,99.5,1,22449,0.5,1,22450},
        },
        [4] = {
            {40,45,33.333333333333,2,11177,33.333333333333,3,11177,33.333333333333,4,11177},
            {46,50,33.333333333333,2,11178,33.333333333333,3,11178,33.333333333333,4,11178},
            {51,55,33.333333333333,2,14343,33.333333333333,3,14343,33.333333333333,4,14343},
            {56,60,100,1,20725}, {61,80,50,1,20725,50,2,20725},
            {95,100,50,1,22450,50,2,22450}, {105,164,33.3,1,22450,66.6,2,22450},
        },
    },
    [2] = { -- Weapons
        [2] = {
            {6,15,10,1,10940,10,2,10940,40,1,10938,40,2,10938},
            {16,20,10,2,10940,10,3,10940,37.5,1,10939,37.5,2,10939,5,1,10978},
            {21,25,5,4,10940,5,5,10940,5,6,10940,37.5,1,10939,37.5,2,10939,10,1,10978},
            {26,30,10,1,11083,10,2,11083,37.5,1,10939,37.5,2,10939,5,1,11084},
            {31,35,5,2,11083,5,3,11083,5,4,11083,5,5,11083,37.5,1,11134,37.5,2,11134,5,1,11138},
            {36,40,10,1,11137,10,2,11137,37.5,1,11135,37.5,2,11135,5,1,11139},
            {41,45,5,2,11137,5,3,11137,5,4,11137,5,5,11137,37.5,1,11174,37.5,2,11174,5,1,11177},
            {46,50,10,1,11176,10,2,11176,37.5,1,11175,37.5,2,11175,5,1,11178},
            {51,55,5.5,2,11176,5.5,3,11176,5.5,4,11176,5.5,5,11176,37.5,1,16202,37.5,2,16202,5,1,14343},
            {56,60,11,1,16204,11,2,16204,37.5,1,16203,37.5,2,16203,5,1,14344},
            {61,65,5.5,2,16204,5.5,3,16204,5.5,4,16204,5.5,5,16204,37.5,2,16203,37.5,3,16203,5,1,14344},
            {66,99,11,2,22445,11,3,22445,37.5,2,22447,37.5,3,22447,3,1,22448},
            {100,164,5.5,2,22445,5.5,3,22445,5.5,4,22445,5.5,5,22445,37.5,1,22446,37.5,2,22446,3,1,22449},
        },
        [3] = {
            {11,25,100,1,10978}, {26,30,100,1,11084}, {31,35,100,1,11138},
            {36,40,100,1,11139}, {41,45,100,1,11177}, {46,50,100,1,11178},
            {51,55,100,1,14343}, {56,65,99.5,1,14344,0.5,1,20725},
            {66,99,99.5,1,22448,0.5,1,20725}, {100,164,99.5,1,22449,0.5,1,22450},
        },
        [4] = {
            {40,45,33.333333333333,2,11177,33.333333333333,3,11177,33.333333333333,4,11177},
            {46,50,33.333333333333,2,11178,33.333333333333,3,11178,33.333333333333,4,11178},
            {51,55,33.333333333333,2,14343,33.333333333333,3,14343,33.333333333333,4,14343},
            {56,60,100,1,20725}, {61,80,33.3,1,20725,66.6,2,20725},
            {95,100,50,1,22450,50,2,22450}, {105,164,33.3,1,22450,66.6,2,22450},
        },
    },
}

local DISENCHANT_MATERIAL_MIN_EXPANSION = {
    [10938]=0,[10939]=0,[10940]=0,[10978]=0,[10998]=0,[11082]=0,[11083]=0,[11084]=0,
    [11134]=0,[11135]=0,[11137]=0,[11138]=0,[11139]=0,[11174]=0,[11175]=0,[11176]=0,
    [11177]=0,[11178]=0,[14343]=0,[14344]=0,[16202]=0,[16203]=0,[16204]=0,[20725]=0,
    [22445]=1,[22446]=1,[22447]=1,[22448]=1,[22449]=1,[22450]=1,
    [34052]=2,[34053]=2,[34054]=2,[34055]=2,[34056]=2,[34057]=2,
    [52555]=3,[52718]=3,[52719]=3,[52720]=3,[52721]=3,[52722]=3,
    [74247]=4,[74248]=4,[74249]=4,[74250]=4,[74251]=4,[74252]=4,
    [109693]=5,[111245]=5,[113588]=5,[115502]=5,
    [124440]=6,[124441]=6,[124442]=6,
}

local function GetDisenchantRows(classID, quality)
    local fallbackClass = TBC_DISENCHANT_FALLBACK[tonumber(classID)]
    local fallbackRows = fallbackClass and fallbackClass[tonumber(quality)] or nil

    -- Auctionator v329 ships one cross-expansion table. On TBC its 121+
    -- uncommon/rare rows point at Wrath materials, so use the sanitized TBC
    -- fallback whose final Arcane/Planar/Prismatic bracket extends to 164.
    if CLIENT_EXPANSION_LEVEL == 1 then
        return fallbackRows, false
    end

    local source = Auctionator and Auctionator.Constants and Auctionator.Constants.DisenchantingProbability
    local classRows = type(source) == "table" and source[tonumber(classID)] or nil
    local rows = type(classRows) == "table" and classRows[tonumber(quality)] or nil
    if type(rows) == "table" then return rows, true end
    return fallbackRows, false
end

local function ParseDisenchantRow(row)
    local byItemID = {}
    for index = 3, #(row or {}), 3 do
        local probability = math.max(0, tonumber(row[index]) or 0) / 100
        local quantity = math.max(0, tonumber(row[index + 1]) or 0)
        local itemID = tonumber(row[index + 2])
        if itemID and probability > 0 and quantity > 0 then
            local drop = byItemID[itemID]
            if not drop then
                drop = { itemID = itemID, chance = 0, expected = 0, outcomes = {} }
                byItemID[itemID] = drop
            end
            drop.chance = drop.chance + probability
            drop.expected = drop.expected + (probability * quantity)
            drop.outcomes[#drop.outcomes + 1] = { probability = probability, quantity = quantity }
        end
    end
    local drops = {}
    for _, drop in pairs(byItemID) do drops[#drops + 1] = drop end
    table.sort(drops, function(a, b) return a.itemID < b.itemID end)
    return drops
end

local DISENCHANT_DROP_CACHE = {}

local function GetDisenchantDropList(quality, itemLevel, classID)
    local ilvl = tonumber(itemLevel)
    local q = tonumber(quality)
    local class = tonumber(classID)
    if not ilvl or not q or not class then return {} end
    ilvl = math.floor(ilvl)
    local cacheKey = tostring(class) .. ":" .. tostring(q) .. ":" .. tostring(ilvl)
    if DISENCHANT_DROP_CACHE[cacheKey] then
        return DISENCHANT_DROP_CACHE[cacheKey]
    end

    local rows = GetDisenchantRows(classID, quality)
    if type(rows) ~= "table" then
        DISENCHANT_DROP_CACHE[cacheKey] = {}
        return DISENCHANT_DROP_CACHE[cacheKey]
    end
    for _, row in ipairs(rows) do
        if ilvl >= (tonumber(row[1]) or math.huge) and ilvl <= (tonumber(row[2]) or -math.huge) then
            DISENCHANT_DROP_CACHE[cacheKey] = ParseDisenchantRow(row)
            return DISENCHANT_DROP_CACHE[cacheKey]
        end
    end
    DISENCHANT_DROP_CACHE[cacheKey] = {}
    return DISENCHANT_DROP_CACHE[cacheKey]
end

local function GetAllDisenchantOutputIDs()
    local expansion = CLIENT_EXPANSION_LEVEL
    local seen, out = {}, {}
    for _, classID in ipairs({ 2, 4 }) do
        for quality = 2, 4 do
            local rows = GetDisenchantRows(classID, quality)
            for _, row in ipairs(rows or {}) do
                for _, drop in ipairs(ParseDisenchantRow(row)) do
                    local minExpansion = DISENCHANT_MATERIAL_MIN_EXPANSION[drop.itemID]
                    if minExpansion and expansion >= minExpansion and not seen[drop.itemID] then
                        seen[drop.itemID] = true
                        out[#out + 1] = drop.itemID
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- Retain a public data handle, but all calculations consume the helpers above.
MarketSync.DisenchantTable = TBC_DISENCHANT_FALLBACK
MarketSync.GetDisenchantDropList = GetDisenchantDropList

MarketSync.CraftingData = MarketSync.CraftingData or {
    ["First Aid (Health)"] = {
        -- First Aid Bandages
        { name = "Linen Bandage", outputItemID = 1251, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2592, qty = 1 } } }, -- Linen Cloth
        { name = "Heavy Linen Bandage", outputItemID = 2581, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2592, qty = 2 } } },
        { name = "Wool Bandage", outputItemID = 3530, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2589, qty = 1 } } }, -- Wool Cloth
        { name = "Heavy Wool Bandage", outputItemID = 3531, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2589, qty = 2 } } },
        { name = "Silk Bandage", outputItemID = 6450, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 4306, qty = 1 } } }, -- Silk Cloth
        { name = "Heavy Silk Bandage", outputItemID = 6451, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 4306, qty = 2 } } },
        { name = "Mageweave Bandage", outputItemID = 8544, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 4338, qty = 1 } } }, -- Mageweave Cloth
        { name = "Heavy Mageweave Bandage", outputItemID = 8545, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 4338, qty = 2 } } },
        { name = "Runecloth Bandage", outputItemID = 14529, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 14047, qty = 1 } } }, -- Runecloth
        { name = "Heavy Runecloth Bandage", outputItemID = 14530, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 14047, qty = 2 } } },
        { name = "Netherweave Bandage", outputItemID = 21990, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 21877, qty = 1 } } }, -- Netherweave Cloth
        { name = "Heavy Netherweave Bandage", outputItemID = 21991, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 21877, qty = 2 } } },
        { name = "Anti-Venom", outputItemID = 6452, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 1475, qty = 1 } } }, -- Small Venom Sac
        { name = "Strong Anti-Venom", outputItemID = 6453, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 1476, qty = 1 } } }, -- Large Venom Sac
        -- Health & Rejuvenation Potions (secondary health craft support)
        { name = "Minor Healing Potion", outputItemID = 118, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2447, qty = 1 }, { itemID = 765, qty = 1 }, { itemID = 3371, qty = 1 } } }, -- Peacebloom, Silverleaf, Empty Vial
        { name = "Lesser Healing Potion", outputItemID = 858, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 118, qty = 1 }, { itemID = 2450, qty = 1 } } }, -- Minor Healing Potion, Briarthorn
        { name = "Healing Potion", outputItemID = 929, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2453, qty = 1 }, { itemID = 2450, qty = 1 }, { itemID = 3372, qty = 1 } } }, -- Bruiseweed, Briarthorn, Leaded Vial
        { name = "Greater Healing Potion", outputItemID = 1710, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 3355, qty = 1 }, { itemID = 3356, qty = 1 }, { itemID = 3372, qty = 1 } } }, -- Wild Steelbloom, Kingsblood, Leaded Vial
        { name = "Superior Healing Potion", outputItemID = 3928, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 8838, qty = 1 }, { itemID = 3358, qty = 1 }, { itemID = 8925, qty = 1 } } }, -- Sungrass, Khadgar's Whisker, Crystal Vial
        { name = "Major Healing Potion", outputItemID = 13446, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 13464, qty = 2 }, { itemID = 13463, qty = 1 }, { itemID = 8925, qty = 1 } } }, -- Mountain Silversage, Golden Sansam, Crystal Vial
        { name = "Super Healing Potion", outputItemID = 22829, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 22791, qty = 2 }, { itemID = 22785, qty = 1 }, { itemID = 22849, qty = 1 } } }, -- Netherbloom, Felweed, Fel Glass Vial
        { name = "Major Rejuvenation Potion", outputItemID = 18253, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 13466, qty = 4 }, { itemID = 13463, qty = 4 }, { itemID = 8925, qty = 1 } } }, -- Heart of the Wild, Golden Sansam, Crystal Vial
        { name = "Powerful Rejuvenation Potion", outputItemID = 22850, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 22793, qty = 3 }, { itemID = 22794, qty = 1 }, { itemID = 22849, qty = 1 } } }, -- Mana Thistle, Fel Lotus, Fel Glass Vial
    },
    ["First Aid"] = nil, -- points dynamically to First Aid (Health) below
    Cooking = {
        { name = "Herb Baked Eggs", outputItemID = 6888, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 6889, qty = 1 } } }, -- Small Egg
        { name = "Spiced Wolf Meat", outputItemID = 2679, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2672, qty = 1 }, { itemID = 2678, qty = 1 } } }, -- Wolf Meat, Mild Spices
        { name = "Smoked Bear Meat", outputItemID = 2681, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2673, qty = 1 }, { itemID = 2678, qty = 1 } } }, -- Bear Meat, Mild Spices
        { name = "Cooked Crab Claw", outputItemID = 2683, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2674, qty = 1 }, { itemID = 2678, qty = 1 } } }, -- Crawler Claw, Mild Spices
        { name = "Seasoned Wolf Kebab", outputItemID = 1017, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 1015, qty = 2 }, { itemID = 7371, qty = 1 } } }, -- Lean Wolf Flank, Stormwind Seasoning Herbs
        { name = "Curiously Tasty Omelet", outputItemID = 3662, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 3685, qty = 1 }, { itemID = 2692, qty = 1 } } }, -- Raptor Egg, Hot Spices
        { name = "Roast Raptor", outputItemID = 12224, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 12202, qty = 1 }, { itemID = 2692, qty = 1 } } }, -- Raptor Flesh, Hot Spices
        { name = "Monster Omelet", outputItemID = 12218, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 12207, qty = 1 }, { itemID = 3713, qty = 2 } } }, -- Giant Egg, Soothing Spices
        { name = "Spiced Chili Crab", outputItemID = 12217, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 12206, qty = 2 }, { itemID = 2692, qty = 2 } } }, -- Tender Crab Meat, Hot Spices
        { name = "Tender Wolf Steak", outputItemID = 18045, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 12208, qty = 1 }, { itemID = 3713, qty = 1 } } }, -- Tender Wolf Meat, Soothing Spices
        { name = "Ravager Dog", outputItemID = 27655, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 27671, qty = 1 } } }, -- Ravager Flesh
        { name = "Buzzard Bites", outputItemID = 27651, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 27674, qty = 1 } } }, -- Buzzard Meat
        { name = "Talbuk Steak", outputItemID = 27658, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 27677, qty = 1 } } }, -- Talbuk Venison
        { name = "Roasted Clefthoof", outputItemID = 27659, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 27678, qty = 1 } } }, -- Clefthoof Meat
    },
    Alchemy = {
        { name = "Minor Healing Potion", outputItemID = 118, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2447, qty = 1 }, { itemID = 765, qty = 1 }, { itemID = 3371, qty = 1 } } },
        { name = "Lesser Healing Potion", outputItemID = 858, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 118, qty = 1 }, { itemID = 2450, qty = 1 } } },
        { name = "Healing Potion", outputItemID = 929, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 2453, qty = 1 }, { itemID = 2450, qty = 1 }, { itemID = 3372, qty = 1 } } },
        { name = "Greater Healing Potion", outputItemID = 1710, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 3355, qty = 1 }, { itemID = 3356, qty = 1 }, { itemID = 3372, qty = 1 } } },
        { name = "Superior Healing Potion", outputItemID = 3928, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 8838, qty = 1 }, { itemID = 3358, qty = 1 }, { itemID = 8925, qty = 1 } } },
        { name = "Major Healing Potion", outputItemID = 13446, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 13464, qty = 2 }, { itemID = 13463, qty = 1 }, { itemID = 8925, qty = 1 } } },
        { name = "Super Healing Potion", outputItemID = 22829, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 22791, qty = 2 }, { itemID = 22785, qty = 1 }, { itemID = 22849, qty = 1 } } },
        { name = "Minor Mana Potion", outputItemID = 2455, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 785, qty = 1 }, { itemID = 765, qty = 1 }, { itemID = 3371, qty = 1 } } },
        { name = "Mana Potion", outputItemID = 3385, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 3820, qty = 1 }, { itemID = 2450, qty = 1 }, { itemID = 3372, qty = 1 } } },
        { name = "Greater Mana Potion", outputItemID = 3827, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 3355, qty = 1 }, { itemID = 3356, qty = 1 }, { itemID = 3372, qty = 1 } } },
        { name = "Superior Mana Potion", outputItemID = 6149, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 8838, qty = 2 }, { itemID = 8836, qty = 2 }, { itemID = 8925, qty = 1 } } },
        { name = "Major Mana Potion", outputItemID = 13444, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 13465, qty = 3 }, { itemID = 13467, qty = 2 }, { itemID = 8925, qty = 1 } } },
        { name = "Super Mana Potion", outputItemID = 22832, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 22786, qty = 2 }, { itemID = 22785, qty = 1 }, { itemID = 22849, qty = 1 } } },
        { name = "Flask of Blinding Light", outputItemID = 22861, outputQty = 1, outputQtyMin = 1, outputQtyMax = 1, mats = { { itemID = 22791, qty = 7 }, { itemID = 22793, qty = 3 }, { itemID = 22794, qty = 1 } } },
    },
    Enchanting = {
        {
            name = "Large Prismatic Shard (craft proxy)",
            outputItemID = 22449,
            outputQty = 1,
            outputQtyMin = 1,
            outputQtyMax = 1,
            mats = {
                { itemID = 22445, qty = 3 }, -- Arcane Dust
                { itemID = 22446, qty = 1 }, -- Planar Essence
            },
        },
    },
}
MarketSync.CraftingData["First Aid"] = MarketSync.CraftingData["First Aid (Health)"]

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
    local charStore = realmDB.KnownCraftingRecipesByCharacter[charKey]
    if type(charStore) ~= "table" or tonumber(charStore.__cacheVersion) ~= CRAFT_RECIPE_CACHE_VERSION then
        -- Pre-v2 recipes stored only GetTradeSkillNumMade's first return value.
        -- They cannot be repaired safely, so force a fresh profession-window scan.
        charStore = { __cacheVersion = CRAFT_RECIPE_CACHE_VERSION }
        realmDB.KnownCraftingRecipesByCharacter[charKey] = charStore
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

local function HasModernTradeSkillAPI()
    return C_TradeSkillUI ~= nil
        and (type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
             or type(C_TradeSkillUI.GetFilteredRecipeIDs) == "function")
end

local function HasLegacyTradeSkillAPI()
    return type(GetTradeSkillLine) == "function"
        and type(GetNumTradeSkills) == "function"
        and type(GetTradeSkillInfo) == "function"
end

local function HasTradeSkillRecipeAPI()
    return HasModernTradeSkillAPI() or HasLegacyTradeSkillAPI()
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
    ["First Aid (Health)"] = true,
}

local function NormalizeProfessionName(name)
    local s = tostring(name or "")
    if s == "" then return nil end
    if s:find("First Aid") or s:find("Health") then
        return "First Aid (Health)"
    end
    for prof in pairs(CRAFTING_PROFESSIONS) do
        if prof ~= "First Aid" and prof ~= "First Aid (Health)" and s:find(prof) then
            return prof
        end
    end
    if CRAFTING_PROFESSIONS[s] then
        return s
    end
    return nil
end

local function IsCraftingProfessionName(name)
    return NormalizeProfessionName(name) ~= nil
end

local function GetOpenTradeSkillProfessionName()
    if C_TradeSkillUI then
        if C_TradeSkillUI.GetBaseProfessionInfo then
            local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            if ok and type(info) == "table" then
                local name = info.professionName or info.parentProfessionName or info.name
                local normalized = NormalizeProfessionName(name)
                if normalized then return normalized end
            end
        end
        if C_TradeSkillUI.GetChildProfessionInfo then
            local ok, info = pcall(C_TradeSkillUI.GetChildProfessionInfo)
            if ok and type(info) == "table" then
                local name = info.professionName or info.parentProfessionName or info.name
                local normalized = NormalizeProfessionName(name)
                if normalized then return normalized end
            end
        end
        if C_TradeSkillUI.GetTradeSkillLine then
            local ok, name = pcall(C_TradeSkillUI.GetTradeSkillLine)
            if ok and type(name) == "string" and name ~= "" and name ~= "UNKNOWN" then
                local normalized = NormalizeProfessionName(name)
                if normalized then return normalized end
            end
        end
    end
    if type(GetTradeSkillLine) == "function" then
        local ok, name = pcall(GetTradeSkillLine)
        if ok and type(name) == "string" and name ~= "" and name ~= "UNKNOWN" then
            local normalized = NormalizeProfessionName(name)
            if normalized then return normalized end
        end
    end
    return nil
end

local function GetPlayerProfessionSet()
    local out = {}
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local count = select("#", GetProfessions())
        for i = 1, count do
            local idx = select(i, GetProfessions())
            if idx then
                local name = GetProfessionInfo(idx)
                local normalized = NormalizeProfessionName(name)
                if normalized then
                    out[normalized] = true
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
            if name and not isHeader then
                local normalized = NormalizeProfessionName(name)
                if normalized then
                    out[normalized] = true
                end
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
            local normalized = NormalizeProfessionName(name)
            if normalized then
                store.professions[normalized] = true
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

    local professionName = GetOpenTradeSkillProfessionName()
    if not professionName then
        return nil, {}
    end

    local recipes = {}
    local seen = {}

    -- 1. Modern C_TradeSkillUI Path
    if HasModernTradeSkillAPI() then
        local recipeIDs = nil
        if C_TradeSkillUI.GetAllRecipeIDs then
            local okIDs, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
            if okIDs and type(ids) == "table" and #ids > 0 then
                recipeIDs = ids
            end
        end
        if (not recipeIDs or #recipeIDs == 0) and C_TradeSkillUI.GetFilteredRecipeIDs then
            local okFiltered, ids = pcall(C_TradeSkillUI.GetFilteredRecipeIDs)
            if okFiltered and type(ids) == "table" and #ids > 0 then
                recipeIDs = ids
            end
        end

        for _, recipeID in ipairs(recipeIDs or {}) do
            local recipeInfo = nil
            if C_TradeSkillUI.GetRecipeInfo then
                local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                if okInfo and type(info) == "table" then
                    recipeInfo = info
                end
            end

            -- Only include learned, non-disabled recipes
            local isLearned = (not recipeInfo) or (recipeInfo.learned == nil) or (recipeInfo.learned == true)
            local isDisabled = recipeInfo and recipeInfo.disabled

            if isLearned and not isDisabled then
                local recipeName = (recipeInfo and recipeInfo.name) or ("Recipe " .. tostring(recipeID))

                -- Output Item
                local outputLink = nil
                if C_TradeSkillUI.GetRecipeItemLink then
                    local okLink, link = pcall(C_TradeSkillUI.GetRecipeItemLink, recipeID)
                    if okLink then outputLink = link end
                end
                local outputItemID = ParseItemIDFromLink(outputLink)
                if not outputItemID and recipeInfo then
                    outputItemID = tonumber(recipeInfo.productID) or tonumber(recipeInfo.outputItemID)
                end

                -- Output Quantity
                local outputQtyMin = 1
                local outputQtyMax = 1
                if recipeInfo and recipeInfo.minMade and recipeInfo.maxMade then
                    outputQtyMin = tonumber(recipeInfo.minMade) or 1
                    outputQtyMax = tonumber(recipeInfo.maxMade) or outputQtyMin
                elseif C_TradeSkillUI.GetRecipeNumMade then
                    local okMade, qMin, qMax = pcall(C_TradeSkillUI.GetRecipeNumMade, recipeID)
                    if okMade and qMin then
                        outputQtyMin = tonumber(qMin) or 1
                        outputQtyMax = tonumber(qMax) or outputQtyMin
                    end
                end

                -- Reagents
                local mats = {}
                -- Try Schematic first
                if C_TradeSkillUI.GetRecipeSchematic then
                    local okSchematic, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
                    if okSchematic and type(schematic) == "table" then
                        if not outputItemID and schematic.outputItemID and tonumber(schematic.outputItemID) > 0 then
                            outputItemID = tonumber(schematic.outputItemID)
                        end
                        if schematic.quantityMin and schematic.quantityMax then
                            outputQtyMin = tonumber(schematic.quantityMin) or outputQtyMin
                            outputQtyMax = tonumber(schematic.quantityMax) or outputQtyMax
                        end
                        if type(schematic.reagentSlotSchematics) == "table" then
                            for _, slot in ipairs(schematic.reagentSlotSchematics) do
                                local reqQty = tonumber(slot.quantityRequired) or 1
                                if type(slot.reagents) == "table" and #slot.reagents > 0 then
                                    local firstReagent = slot.reagents[1]
                                    local rItemID = firstReagent and tonumber(firstReagent.itemID)
                                    if rItemID and rItemID > 0 then
                                        mats[#mats + 1] = {
                                            itemID = rItemID,
                                            qty = math.max(1, math.floor(reqQty)),
                                        }
                                    end
                                end
                            end
                        end
                    end
                end

                -- Fallback to GetRecipeNumReagents / GetRecipeReagentInfo
                if #mats == 0 and C_TradeSkillUI.GetRecipeNumReagents then
                    local okNum, numReagents = pcall(C_TradeSkillUI.GetRecipeNumReagents, recipeID)
                    if okNum and type(numReagents) == "number" and numReagents > 0 then
                        for r = 1, numReagents do
                            local rLink = nil
                            if C_TradeSkillUI.GetRecipeReagentItemLink then
                                local okRLink, link = pcall(C_TradeSkillUI.GetRecipeReagentItemLink, recipeID, r)
                                if okRLink then rLink = link end
                            end
                            local rItemID = ParseItemIDFromLink(rLink)
                            local qty = 1
                            if C_TradeSkillUI.GetRecipeReagentInfo then
                                local okRInfo, _, _, reqCount = pcall(C_TradeSkillUI.GetRecipeReagentInfo, recipeID, r)
                                if okRInfo and reqCount then
                                    qty = tonumber(reqCount) or 1
                                end
                            end
                            if rItemID then
                                mats[#mats + 1] = {
                                    itemID = rItemID,
                                    qty = math.max(1, math.floor(tonumber(qty) or 1)),
                                }
                            end
                        end
                    end
                end

                outputQtyMin = math.max(1, math.floor(tonumber(outputQtyMin) or 1))
                outputQtyMax = math.max(outputQtyMin, math.floor(tonumber(outputQtyMax) or outputQtyMin))
                local outputQty = (outputQtyMin + outputQtyMax) / 2

                if outputItemID and #mats > 0 then
                    local dedupeKey = tostring(outputItemID) .. ":" .. tostring(recipeName)
                    if not seen[dedupeKey] then
                        seen[dedupeKey] = true
                        recipes[#recipes + 1] = {
                            name = recipeName,
                            outputItemID = outputItemID,
                            outputQty = outputQty,
                            outputQtyMin = outputQtyMin,
                            outputQtyMax = outputQtyMax,
                            skillType = tostring(recipeInfo and (recipeInfo.relativeDifficulty or recipeInfo.difficulty) or ""),
                            numSkillUps = tonumber(recipeInfo and recipeInfo.numSkillUps) or 1,
                            mats = mats,
                            recipeIndex = recipeID,
                        }
                    end
                end
            end
        end

    -- 2. Legacy GetTradeSkillInfo Path
    elseif HasLegacyTradeSkillAPI() then
        local numSkillsRaw = (GetNumTradeSkills and GetNumTradeSkills()) or 0
        local numSkills = tonumber(numSkillsRaw) or 0
        for i = 1, numSkills do
            local recipeName, skillType, _, _, _, numSkillUps = GetTradeSkillInfo(i)
            if recipeName and skillType ~= "header" and skillType ~= "subheader" then
                local outputLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil
                local outputItemID = ParseItemIDFromLink(outputLink)
                local outputQtyMinRaw, outputQtyMaxRaw = 1, 1
                if GetTradeSkillNumMade then
                    outputQtyMinRaw, outputQtyMaxRaw = GetTradeSkillNumMade(i)
                end
                local outputQtyMin = math.max(1, math.floor(tonumber(outputQtyMinRaw) or 1))
                local outputQtyMax = math.max(outputQtyMin, math.floor(tonumber(outputQtyMaxRaw) or outputQtyMin))
                local outputQty = (outputQtyMin + outputQtyMax) / 2

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
                            outputQtyMin = outputQtyMin,
                            outputQtyMax = outputQtyMax,
                            skillType = tostring(skillType or ""),
                            numSkillUps = tonumber(numSkillUps),
                            mats = mats,
                            recipeIndex = i,
                        }
                    end
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
        cacheVersion = CRAFT_RECIPE_CACHE_VERSION,
        updatedAt = time(),
        recipes = recipes or {},
    }
    if professionName == "First Aid (Health)" then
        store["First Aid"] = store[professionName]
    end
    return type(recipes) == "table" and #recipes > 0
end

function MarketSync.IsProfessionResyncInProgress()
    return false
end

local function BuildProfessionResyncQueue()
    local out = {}
    local seen = {}

    local function Add(name)
        local prof = NormalizeProfessionName(name)
        if not prof or seen[prof] then
            return
        end
        seen[prof] = true
        out[#out + 1] = prof
    end

    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local count = select("#", GetProfessions())
        for i = 1, count do
            local idx = select(i, GetProfessions())
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
        local cached = store[prof] or (prof == "First Aid (Health)" and store["First Aid"])
        if type(cached) == "table"
            and tonumber(cached.cacheVersion) == CRAFT_RECIPE_CACHE_VERSION
            and type(cached.recipes) == "table"
            and #cached.recipes > 0 then
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
    local openProfession = GetOpenTradeSkillProfessionName()
    if openProfession and IsCraftingProfessionName(openProfession) then
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

local HEALTH_POTION_IDS = {
    [118] = true,    -- Minor Healing Potion
    [858] = true,    -- Lesser Healing Potion
    [929] = true,    -- Healing Potion
    [1710] = true,   -- Greater Healing Potion
    [3928] = true,   -- Superior Healing Potion
    [13446] = true,  -- Major Healing Potion
    [22829] = true,  -- Super Healing Potion
    [33447] = true,  -- Runic Healing Potion
    [18253] = true,  -- Major Rejuvenation Potion
    [22850] = true,  -- Powerful Rejuvenation Potion
    [34440] = true,  -- Mad Alchemist's Potion
    [40067] = true,  -- Potion of Nightmares
    [40077] = true,  -- Crazy Alchemist's Potion
}

local function IsHealthConsumableRecipe(recipe)
    if not recipe then return false end
    if recipe.outputItemID and HEALTH_POTION_IDS[recipe.outputItemID] then
        return true
    end
    local name = string.lower(tostring(recipe.name or ""))
    if name:find("healing potion")
        or name:find("health potion")
        or name:find("rejuvenation potion")
        or name:find("restorative potion")
        or name:find("healing draught") then
        return true
    end
    return false
end

local function GetRecipesForProfession(professionName)
    local prof = professionName and tostring(professionName) or nil
    if not prof or prof == "" then return {} end

    local normalized = NormalizeProfessionName(prof) or prof
    local store = GetKnownCraftingStore()
    local out = {}
    local seen = {}

    local function AddRecipe(r)
        if type(r) ~= "table" or not r.outputItemID or not r.mats or #r.mats == 0 then
            return
        end
        local key = tostring(r.outputItemID)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = r
        end
    end

    -- Special secondary consolidation: First Aid (Health) combines First Aid bandages with Health Potions
    if normalized == "First Aid (Health)" or normalized == "First Aid" then
        -- 1. Scanned First Aid recipes from character
        local cachedFA = store["First Aid (Health)"] or store["First Aid"]
        if cachedFA and tonumber(cachedFA.cacheVersion) == CRAFT_RECIPE_CACHE_VERSION and type(cachedFA.recipes) == "table" then
            for _, r in ipairs(cachedFA.recipes) do
                AddRecipe(r)
            end
        end

        -- 2. Scanned health potions from character's Alchemy (if character knows Alchemy)
        local cachedAlch = store["Alchemy"]
        if cachedAlch and tonumber(cachedAlch.cacheVersion) == CRAFT_RECIPE_CACHE_VERSION and type(cachedAlch.recipes) == "table" then
            for _, r in ipairs(cachedAlch.recipes) do
                if IsHealthConsumableRecipe(r) then
                    AddRecipe(r)
                end
            end
        end

        -- 3. Built-in recipes for First Aid bandages & Health Potions (guarantees complete health craft coverage)
        local builtin = (MarketSync.CraftingData and (MarketSync.CraftingData["First Aid (Health)"] or MarketSync.CraftingData["First Aid"])) or {}
        for _, r in ipairs(builtin) do
            AddRecipe(r)
        end

        return out
    end

    -- Standard profession path:
    local cached = store[normalized] or store[prof]
    if cached
        and tonumber(cached.cacheVersion) == CRAFT_RECIPE_CACHE_VERSION
        and type(cached.recipes) == "table"
        and #cached.recipes > 0 then
        return cached.recipes
    end

    -- Fallback recipes
    local fallback = MarketSync.CraftingData and (MarketSync.CraftingData[normalized] or MarketSync.CraftingData[prof])
    if fallback and type(fallback) == "table" and #fallback > 0 then
        return fallback
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
    local name = SafeGetItemInfo(itemID)
    if name and MarketSyncDB and MarketSyncDB.ItemInfoCache then
        MarketSyncDB.ItemInfoCache[itemID] = MarketSyncDB.ItemInfoCache[itemID] or {}
        MarketSyncDB.ItemInfoCache[itemID].n = name
    end
    return name
end

local function GetPriceByItemID(itemID)
    if not itemID then return nil end
    if MarketSync.GetAuctionPrice then
        local p = MarketSync.GetAuctionPrice(itemID)
        if p and p > 0 then return p end
    end
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER_ID, itemID)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

local function GetAgeByItemID(itemID)
    if not itemID then return nil end
    if MarketSync.GetAuctionAge then
        local a = MarketSync.GetAuctionAge(itemID)
        if a and a >= 0 then return a end
    end
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
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
-- Returns expected main-AH proceeds after the sale cut, stale, and missing-price count.
local function GetAuctionatorDisenchantGross(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local fn = api and api.GetDisenchantPriceByItemID
    local probabilityData = Auctionator and Auctionator.Constants and Auctionator.Constants.DisenchantingProbability
    if CLIENT_EXPANSION_LEVEL == 1
        or not itemID
        or type(fn) ~= "function"
        or type(probabilityData) ~= "table" then
        return nil
    end
    local ok, grossValue = pcall(fn, CALLER_ID, tonumber(itemID))
    if ok and type(grossValue) == "number" and grossValue > 0 then
        -- Auctionator v329 returns gross expected material value; it does not
        -- subtract an AH sale cut. NetMainAuctionValue is applied below once.
        return grossValue
    end
    return nil
end

local function EstimateDisenchantEV(quality, itemLevel, classOrWeapon, itemID)
    local classID = tonumber(classOrWeapon)
    if not classID then classID = classOrWeapon and 2 or 4 end
    local drops = GetDisenchantDropList(quality, itemLevel, classID)
    if #drops == 0 then return nil, false, 0, nil, false, drops end

    local directGross = 0
    local hasAnyPrice = false
    local anyStale = false
    local missingCount = 0
    for _, drop in ipairs(drops) do
        local price, _, stale = GetPriceInfoByItemID(drop.itemID)
        if price and price > 0 then
            directGross = directGross + (price * drop.expected)
            hasAnyPrice = true
            if stale then anyStale = true end
        else
            missingCount = missingCount + 1
        end
    end

    local apiGross = GetAuctionatorDisenchantGross(itemID)
    local grossValue = apiGross or (hasAnyPrice and directGross or nil)
    if not grossValue or grossValue <= 0 then
        return nil, anyStale, missingCount, nil, missingCount > 0, drops
    end
    return math.floor(NetMainAuctionValue(grossValue)), anyStale, missingCount,
        grossValue, missingCount > 0, drops
end

-- Public API for UI or other modules; the original boolean third argument is
-- retained, while callers with an item ID can use Auctionator's exact gross EV.
function MarketSync.EstimateDisenchantEV(quality, itemLevel, classOrWeapon, itemID)
    return EstimateDisenchantEV(quality, itemLevel, classOrWeapon, itemID)
end

local function ExpectedYield(y)
    if type(y) == "table" and tonumber(y.expected) then
        return math.max(0, tonumber(y.expected) or 0)
    end
    local minV = tonumber(y.min) or 0
    local maxV = tonumber(y.max) or minV
    local prob = tonumber(y.prob) or 0
    return ((minV + maxV) / 2) * prob
end

local function FormatExpectedQuantity(value)
    local amount = math.max(0, tonumber(value) or 0)
    if amount < 0.1 then return string.format("%.3f", amount) end
    if amount < 1 then return string.format("%.2f", amount) end
    return string.format("%.1f", amount)
end

local function CalculateInputEV(inputItemID, def)
    local grossEV = 0
    local hasAnyPrice = false
    local hasStaleOutput = false
    local missingOutputs = 0
    for _, y in ipairs(def.yields or {}) do
        local outPrice, _, outStale = GetPriceInfoByItemID(y.itemID)
        if outPrice and outPrice > 0 then
            hasAnyPrice = true
            grossEV = grossEV + (ExpectedYield(y) * outPrice)
            if outStale then
                hasStaleOutput = true
            end
        else
            missingOutputs = missingOutputs + 1
        end
    end
    if not hasAnyPrice then
        return nil, hasStaleOutput, missingOutputs, nil, missingOutputs > 0
    end
    return NetMainAuctionValue(grossEV), hasStaleOutput, missingOutputs, grossEV, missingOutputs > 0
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
        for _, id in ipairs(GetAllDisenchantOutputIDs()) do
            if not seen[id] then
                seen[id] = true
                table.insert(out, {
                    itemID = id,
                    name = GetItemName(id) or ("Item " .. tostring(id)),
                })
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
        local normalized = NormalizeProfessionName(name)
        if normalized then
            knownProfessionSet[normalized] = true
        end
    end
    for _, name in ipairs(cachedProfessions or {}) do
        local normalized = NormalizeProfessionName(name)
        if normalized then
            knownProfessionSet[normalized] = true
        end
    end

    if knownProfessionSet["First Aid"] then
        knownProfessionSet["First Aid (Health)"] = true
        knownProfessionSet["First Aid"] = nil
    end

    local hasKnownProfs = next(knownProfessionSet) ~= nil
    local out = {}
    local seen = {}

    local function AddProfessionIfEligible(name)
        local prof = NormalizeProfessionName(name) or tostring(name or "")
        if prof == "" then return end
        if prof == "First Aid" then prof = "First Aid (Health)" end
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

    -- Fallback path if profession APIs are unavailable or no profs scanned.
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
                local grossTargetValuePerAction = targetPrice * expectedTarget
                local netTargetValuePerAction = NetMainAuctionValue(grossTargetValuePerAction)
                local maxBuyPerStack = netTargetValuePerAction * marginMult
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
                    grossEVPerAction = math.floor(grossTargetValuePerAction),
                    evPerAction = math.floor(netTargetValuePerAction),
                    evPerUnit = math.floor(netTargetValuePerAction / math.max(1, stackSize)),
                    ahCutPercent = MAIN_AH_CUT_PERCENT,
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
                        local expectedQty = 0
                        for _, drop in ipairs(GetDisenchantDropList(quality, ilvl, classID)) do
                            if drop.itemID == tid then
                                expectedQty = expectedQty + drop.expected
                            end
                        end
                        if expectedQty > 0 then
                            local grossTargetValue = targetPrice * expectedQty
                            local netTargetValue = NetMainAuctionValue(grossTargetValue)
                            local maxBuy = math.floor(netTargetValue * marginMult)
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
                                    grossEVPerAction = math.floor(grossTargetValue),
                                    evPerAction = math.floor(netTargetValue),
                                    evPerUnit = math.floor(netTargetValue),
                                    ahCutPercent = MAIN_AH_CUT_PERCENT,
                                    maxBuyPerUnit = maxBuy,
                                    maxBuyPerStack = maxBuy,
                                    livePrice = livePrice,
                                    liveAge = liveAge,
                                    liveStale = liveStale,
                                    profitable = (livePrice <= maxBuy),
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
            local evPerAction, evStale, missingOutputs, grossEVPerAction, partialEV = CalculateInputEV(inputItemID, def)
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
                    grossEVPerAction = math.floor(grossEVPerAction or 0),
                    evPerUnit = math.floor(evPerUnit),
                    ahCutPercent = MAIN_AH_CUT_PERCENT,
                    evStale = evStale,
                    missingOutputs = missingOutputs,
                    partialEV = partialEV,
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
                        local deEV, deStale, deMissing, deGross, dePartial =
                            EstimateDisenchantEV(quality, ilvl, classID, tonumber(itemID))

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
                                    grossEVPerAction = math.floor(tonumber(deGross) or 0),
                                    evPerUnit = deEV,
                                    ahCutPercent = MAIN_AH_CUT_PERCENT,
                                    evStale = deStale,
                                    missingOutputs = deMissing,
                                    partialEV = dePartial,
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
                local outputQty = math.max(1, tonumber(recipe.outputQty) or 1)
                local outputQtyMin = math.max(1, tonumber(recipe.outputQtyMin) or outputQty)
                local outputQtyMax = math.max(outputQtyMin, tonumber(recipe.outputQtyMax) or outputQty)
                local revenue = math.floor(NetMainAuctionValue(outputPrice * outputQty))
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
                    outputUnitPrice = outputPrice,
                    outputQty = outputQty,
                    outputQtyMin = outputQtyMin,
                    outputQtyMax = outputQtyMax,
                    ahCutPercent = MAIN_AH_CUT_PERCENT,
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
-- VENDOR REAGENTS & INTERMEDIATE RECIPES
-- ================================================================

-- Static table of common fixed-price vendor reagents (prices in copper)
MarketSync.VendorPrices = {
    -- Vials & Containers
    [3371]  = 40,     -- Empty Vial
    [3372]  = 300,    -- Leaded Vial
    [8925]  = 4000,   -- Crystal Vial
    [22849] = 16000,  -- Fel Glass Vial
    [39684] = 10000,  -- Imbued Vial
    -- Threads
    [2320]  = 10,     -- Coarse Thread
    [2321]  = 100,    -- Fine Thread
    [4291]  = 5000,   -- Silken Thread
    [14341] = 5000,   -- Rune Thread
    [21892] = 30000,  -- Eternium Thread
    [44703] = 50000,  -- Frost Thread
    -- Flux, Coal, Stocks
    [2880]  = 20,     -- Weak Flux
    [3466]  = 2000,   -- Strong Flux
    [3857]  = 500,    -- Coal
    [4371]  = 400,    -- Wooden Stock
    [4372]  = 2000,   -- Heavy Stock
    -- Salts
    [4289]  = 10,     -- Salt
    [3470]  = 100,    -- Coarse Salt
    [3471]  = 500,    -- Heavy Salt
    [20815] = 500,    -- Rock Salt
    -- Spices, Flour & Water
    [2678]  = 10,     -- Mild Spices
    [2692]  = 100,    -- Hot Spices
    [3713]  = 200,    -- Soothing Spices
    [159]   = 25,     -- Refreshing Spring Water
    [3081]  = 25,     -- Simple Flour
    [1179]  = 125,    -- Ice Cold Milk
    -- Parchment (Inscription)
    [39354] = 20,     -- Light Parchment
    [39501] = 100,    -- Common Parchment
    [39502] = 500,    -- Heavy Parchment
    [43145] = 1000,   -- Resilient Parchment
    -- Enchanting
    [38682] = 1000,   -- Enchanting Vellum
}

-- Standard intermediate recipes for multi-tier ground-up resolution
MarketSync.IntermediateRecipes = {
    -- Smelting (Mining)
    [2840]  = { name = "Copper Bar", outputItemID = 2840, outputQty = 1, mats = { { itemID = 2770, qty = 1 } } }, -- Copper Ore
    [3576]  = { name = "Tin Bar", outputItemID = 3576, outputQty = 1, mats = { { itemID = 2771, qty = 1 } } }, -- Tin Ore
    [2841]  = { name = "Bronze Bar", outputItemID = 2841, outputQty = 2, mats = { { itemID = 2840, qty = 1 }, { itemID = 3576, qty = 1 } } }, -- 1 Copper Bar + 1 Tin Bar -> 2 Bronze
    [2842]  = { name = "Silver Bar", outputItemID = 2842, outputQty = 1, mats = { { itemID = 2772, qty = 1 } } }, -- Silver Ore
    [3575]  = { name = "Iron Bar", outputItemID = 3575, outputQty = 1, mats = { { itemID = 2775, qty = 1 } } }, -- Iron Ore
    [3859]  = { name = "Steel Bar", outputItemID = 3859, outputQty = 1, mats = { { itemID = 3575, qty = 1 }, { itemID = 3857, qty = 1 } } }, -- Iron Bar + Coal
    [3577]  = { name = "Gold Bar", outputItemID = 3577, outputQty = 1, mats = { { itemID = 2776, qty = 1 } } }, -- Gold Ore
    [3860]  = { name = "Mithril Bar", outputItemID = 3860, outputQty = 1, mats = { { itemID = 3858, qty = 1 } } }, -- Mithril Ore
    [6037]  = { name = "Truesilver Bar", outputItemID = 6037, outputQty = 1, mats = { { itemID = 7911, qty = 1 } } }, -- Truesilver Ore
    [12359] = { name = "Thorium Bar", outputItemID = 12359, outputQty = 1, mats = { { itemID = 10620, qty = 1 } } }, -- Thorium Ore
    [23445] = { name = "Fel Iron Bar", outputItemID = 23445, outputQty = 1, mats = { { itemID = 23424, qty = 2 } } }, -- Fel Iron Ore x2
    [23446] = { name = "Adamantite Bar", outputItemID = 23446, outputQty = 1, mats = { { itemID = 23425, qty = 2 } } }, -- Adamantite Ore x2
    [23573] = { name = "Hardened Adamantite Bar", outputItemID = 23573, outputQty = 1, mats = { { itemID = 23446, qty = 10 } } }, -- Adamantite Bar x10
    [23571] = { name = "Eternium Bar", outputItemID = 23571, outputQty = 1, mats = { { itemID = 23426, qty = 2 } } }, -- Eternium Ore x2
    [23449] = { name = "Khorium Bar", outputItemID = 23449, outputQty = 1, mats = { { itemID = 23427, qty = 2 } } }, -- Khorium Ore x2
    [23448] = { name = "Felsteel Bar", outputItemID = 23448, outputQty = 1, mats = { { itemID = 23445, qty = 3 }, { itemID = 23571, qty = 2 } } }, -- 3 Fel Iron + 2 Eternium
    [37663] = { name = "Cobalt Bar", outputItemID = 37663, outputQty = 1, mats = { { itemID = 36909, qty = 1 } } }, -- Cobalt Ore
    [37664] = { name = "Saronite Bar", outputItemID = 37664, outputQty = 1, mats = { { itemID = 36912, qty = 2 } } }, -- Saronite Ore x2
    [41163] = { name = "Titanium Bar", outputItemID = 41163, outputQty = 1, mats = { { itemID = 36910, qty = 2 } } }, -- Titanium Ore x2

    -- Tailoring (Bolts of Cloth)
    [2996]  = { name = "Bolt of Linen Cloth", outputItemID = 2996, outputQty = 1, mats = { { itemID = 2592, qty = 2 } } }, -- Linen Cloth x2
    [2997]  = { name = "Bolt of Woolen Cloth", outputItemID = 2997, outputQty = 1, mats = { { itemID = 2589, qty = 3 } } }, -- Wool Cloth x3
    [4305]  = { name = "Bolt of Silk Cloth", outputItemID = 4305, outputQty = 1, mats = { { itemID = 4306, qty = 4 } } }, -- Silk Cloth x4
    [4339]  = { name = "Bolt of Mageweave", outputItemID = 4339, outputQty = 1, mats = { { itemID = 4338, qty = 4 } } }, -- Mageweave Cloth x4
    [10290] = { name = "Bolt of Runecloth", outputItemID = 10290, outputQty = 1, mats = { { itemID = 14047, qty = 5 } } }, -- Runecloth x5
    [21840] = { name = "Bolt of Netherweave", outputItemID = 21840, outputQty = 1, mats = { { itemID = 21877, qty = 5 } } }, -- Netherweave Cloth x5
    [21842] = { name = "Bolt of Imbued Netherweave", outputItemID = 21842, outputQty = 1, mats = { { itemID = 21840, qty = 3 }, { itemID = 22445, qty = 2 } } }, -- 3 Netherweave Bolts + 2 Arcane Dust
    [21844] = { name = "Bolt of Soulcloth", outputItemID = 21844, outputQty = 1, mats = { { itemID = 21840, qty = 1 }, { itemID = 22448, qty = 8 } } }, -- 1 Netherweave Bolt + 8 Soul Essence
    [41510] = { name = "Bolt of Frostweave", outputItemID = 41510, outputQty = 1, mats = { { itemID = 41529, qty = 5 } } }, -- Frostweave Cloth x5
    [41511] = { name = "Bolt of Imbued Frostweave", outputItemID = 41511, outputQty = 1, mats = { { itemID = 41510, qty = 2 }, { itemID = 34054, qty = 2 } } }, -- 2 Frostweave Bolts + 2 Infinite Dust
    [53643] = { name = "Bolt of Embersilk Cloth", outputItemID = 53643, outputQty = 1, mats = { { itemID = 53010, qty = 5 } } }, -- Embersilk Cloth x5

    -- Blacksmithing & Engineering (Stones, Powders, Bolts)
    [2862]  = { name = "Rough Sharpening Stone", outputItemID = 2862, outputQty = 1, mats = { { itemID = 2835, qty = 1 } } }, -- Rough Stone
    [2863]  = { name = "Rough Grinding Stone", outputItemID = 2863, outputQty = 1, mats = { { itemID = 2835, qty = 2 } } }, -- 2 Rough Stone
    [2868]  = { name = "Coarse Sharpening Stone", outputItemID = 2868, outputQty = 1, mats = { { itemID = 2836, qty = 1 } } }, -- Coarse Stone
    [2870]  = { name = "Coarse Grinding Stone", outputItemID = 2870, outputQty = 1, mats = { { itemID = 2836, qty = 2 } } }, -- 2 Coarse Stone
    [2871]  = { name = "Heavy Sharpening Stone", outputItemID = 2871, outputQty = 1, mats = { { itemID = 2838, qty = 1 } } }, -- Heavy Stone
    [3478]  = { name = "Heavy Grinding Stone", outputItemID = 3478, outputQty = 1, mats = { { itemID = 2838, qty = 3 } } }, -- 3 Heavy Stone
    [7964]  = { name = "Solid Sharpening Stone", outputItemID = 7964, outputQty = 1, mats = { { itemID = 7912, qty = 1 } } }, -- Solid Stone
    [7966]  = { name = "Solid Grinding Stone", outputItemID = 7966, outputQty = 1, mats = { { itemID = 7912, qty = 4 } } }, -- 4 Solid Stone
    [12404] = { name = "Dense Sharpening Stone", outputItemID = 12404, outputQty = 1, mats = { { itemID = 12365, qty = 1 } } }, -- Dense Stone
    [12644] = { name = "Dense Grinding Stone", outputItemID = 12644, outputQty = 1, mats = { { itemID = 12365, qty = 4 } } }, -- 4 Dense Stone
    [3239]  = { name = "Rough Weightstone", outputItemID = 3239, outputQty = 1, mats = { { itemID = 2835, qty = 1 } } },
    [3240]  = { name = "Coarse Weightstone", outputItemID = 3240, outputQty = 1, mats = { { itemID = 2836, qty = 1 } } },
    [3241]  = { name = "Heavy Weightstone", outputItemID = 3241, outputQty = 1, mats = { { itemID = 2838, qty = 1 } } },
    [7965]  = { name = "Solid Weightstone", outputItemID = 7965, outputQty = 1, mats = { { itemID = 7912, qty = 1 } } },
    [12643] = { name = "Dense Weightstone", outputItemID = 12643, outputQty = 1, mats = { { itemID = 12365, qty = 1 } } },
    [4357]  = { name = "Rough Blasting Powder", outputItemID = 4357, outputQty = 1, mats = { { itemID = 2835, qty = 1 } } },
    [4364]  = { name = "Coarse Blasting Powder", outputItemID = 4364, outputQty = 1, mats = { { itemID = 2836, qty = 1 } } },
    [4371]  = { name = "Heavy Blasting Powder", outputItemID = 4371, outputQty = 1, mats = { { itemID = 2838, qty = 1 } } },
    [10505] = { name = "Solid Blasting Powder", outputItemID = 10505, outputQty = 1, mats = { { itemID = 7912, qty = 2 } } },
    [18587] = { name = "Dense Blasting Powder", outputItemID = 18587, outputQty = 2, mats = { { itemID = 12365, qty = 2 } } },
    [4359]  = { name = "Handful of Copper Bolts", outputItemID = 4359, outputQty = 1, mats = { { itemID = 2840, qty = 1 } } },
    [23784] = { name = "Handful of Fel Iron Bolts", outputItemID = 23784, outputQty = 1, mats = { { itemID = 23445, qty = 1 } } },
    [23782] = { name = "Fel Iron Casing", outputItemID = 23782, outputQty = 1, mats = { { itemID = 23445, qty = 3 } } },
    [39690] = { name = "Handful of Cobalt Bolts", outputItemID = 39690, outputQty = 2, mats = { { itemID = 37663, qty = 2 } } },

    -- Leatherworking (Upgrades & Scraps)
    [21887] = { name = "Knothide Leather", outputItemID = 21887, outputQty = 1, mats = { { itemID = 21886, qty = 5 } } }, -- 5 Knothide Scraps
    [23793] = { name = "Heavy Knothide Leather", outputItemID = 23793, outputQty = 1, mats = { { itemID = 21887, qty = 5 } } }, -- 5 Knothide Leather
    [33568] = { name = "Borean Leather", outputItemID = 33568, outputQty = 1, mats = { { itemID = 33567, qty = 5 } } }, -- 5 Borean Scraps
    [38425] = { name = "Heavy Borean Leather", outputItemID = 38425, outputQty = 1, mats = { { itemID = 33568, qty = 6 } } }, -- 6 Borean Leather

    -- Inscription (Common Inks from Pigments)
    [39469] = { name = "Moonglow Ink", outputItemID = 39469, outputQty = 1, mats = { { itemID = 39151, qty = 2 } } },
    [39774] = { name = "Midnight Ink", outputItemID = 39774, outputQty = 1, mats = { { itemID = 39334, qty = 2 } } },
    [43116] = { name = "Lion's Ink", outputItemID = 43116, outputQty = 1, mats = { { itemID = 39338, qty = 2 } } },
    [43118] = { name = "Jadefire Ink", outputItemID = 43118, outputQty = 1, mats = { { itemID = 39339, qty = 2 } } },
    [43120] = { name = "Celestial Ink", outputItemID = 43120, outputQty = 1, mats = { { itemID = 39340, qty = 2 } } },
    [43122] = { name = "Shimmering Ink", outputItemID = 43122, outputQty = 1, mats = { { itemID = 39341, qty = 2 } } },
    [43124] = { name = "Ethereal Ink", outputItemID = 43124, outputQty = 1, mats = { { itemID = 39342, qty = 2 } } },
    [43126] = { name = "Ink of the Sea", outputItemID = 43126, outputQty = 1, mats = { { itemID = 39343, qty = 2 } } },
    [43127] = { name = "Snowfall Ink", outputItemID = 43127, outputQty = 1, mats = { { itemID = 39345, qty = 2 } } },
}

function MarketSync.GetVendorPrice(itemID)
    if not itemID then return nil end
    local id = tonumber(itemID)
    if not id then return nil end

    -- 1. Static dictionary
    if MarketSync.VendorPrices and MarketSync.VendorPrices[id] then
        return MarketSync.VendorPrices[id]
    end

    -- 2. RealmDB dynamic cache from MERCHANT_SHOW
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if realmDB and realmDB.VendorPrices and realmDB.VendorPrices[id] then
        return realmDB.VendorPrices[id]
    end

    -- 3. Auctionator API fallback
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetVendorPriceByItemID then
        local ok, price = pcall(Auctionator.API.v1.GetVendorPriceByItemID, CALLER_ID, id)
        if ok and type(price) == "number" and price > 0 then
            return price
        end
    end

    return nil
end

function MarketSync.GetRecipeForOutput(outputItemID)
    if not outputItemID then return nil end
    local id = tonumber(outputItemID)
    if not id then return nil end

    -- 1. Current character's scanned recipes
    local store = GetKnownCraftingStore()
    local charKey = GetCraftingCharacterKey()
    if charKey and store then
        for profName, profData in pairs(store) do
            if type(profData) == "table" and type(profData.recipes) == "table" then
                for _, r in ipairs(profData.recipes) do
                    if tonumber(r.outputItemID) == id then
                        return r, profName
                    end
                end
            end
        end
    end

    -- 2. Realm-wide character recipes
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    if realmDB and type(realmDB.KnownCraftingRecipes) == "table" then
        for cKey, charProfs in pairs(realmDB.KnownCraftingRecipes) do
            if type(charProfs) == "table" then
                for pName, pData in pairs(charProfs) do
                    if type(pData) == "table" and type(pData.recipes) == "table" then
                        for _, r in ipairs(pData.recipes) do
                            if tonumber(r.outputItemID) == id then
                                return r, pName
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. IntermediateRecipes
    if MarketSync.IntermediateRecipes and MarketSync.IntermediateRecipes[id] then
        return MarketSync.IntermediateRecipes[id], "Intermediate"
    end

    -- 4. Built-in CraftingData
    if MarketSync.CraftingData then
        for pName, recipes in pairs(MarketSync.CraftingData) do
            if type(recipes) == "table" then
                for _, r in ipairs(recipes) do
                    if tonumber(r.outputItemID) == id then
                        return r, pName
                    end
                end
            end
        end
    end

    return nil
end

-- ================================================================
-- RECURSIVE GROUND-UP ENGINE
-- ================================================================

local function ResolveReagentNode(itemID, reqQty, visited, depth, userOverrides)
    visited = visited or {}
    depth = depth or 0
    reqQty = math.max(1, tonumber(reqQty) or 1)

    local node = {
        itemID = itemID,
        name = GetItemName(itemID) or ("Item " .. tostring(itemID)),
        qty = reqQty,
        depth = depth,
        isVendor = false,
        directUnitPrice = 0,
        directTotalPrice = 0,
        craftUnitPrice = nil,
        craftTotalPrice = nil,
        subMats = nil,
        canCraft = false,
        chooseCraft = false,
        effectiveUnitPrice = 0,
        effectiveTotalPrice = 0,
        unitSavings = 0,
        totalSavings = 0,
        hasMissing = false,
        hasStale = false,
    }

    -- 1. Direct Purchase Price
    local vendorPrice = MarketSync.GetVendorPrice(itemID)
    local ahPrice, _, ahStale = GetPriceInfoByItemID(itemID)
    if vendorPrice and vendorPrice > 0 then
        node.isVendor = true
        node.directUnitPrice = vendorPrice
    elseif ahPrice and ahPrice > 0 then
        node.directUnitPrice = ahPrice
        if ahStale then node.hasStale = true end
    else
        node.hasMissing = true
    end
    node.directTotalPrice = node.directUnitPrice * reqQty

    -- 2. Sub-Craft Resolution
    if depth < 6 and not visited[itemID] then
        local subRecipe = MarketSync.GetRecipeForOutput(itemID)
        if subRecipe and type(subRecipe.mats) == "table" and #subRecipe.mats > 0 then
            node.canCraft = true
            local newVisited = {}
            for k, v in pairs(visited) do newVisited[k] = v end
            newVisited[itemID] = true

            local subOutputQty = math.max(1, tonumber(subRecipe.outputQty) or 1)
            local subTreeList = {}
            local subUnitCraftCost = 0
            local subHasMissing = false
            local subHasStale = false

            for _, mat in ipairs(subRecipe.mats) do
                local mID = tonumber(mat.itemID)
                local mQtyPerAction = tonumber(mat.qty) or 1
                local totalMatQty = math.max(1, math.ceil(mQtyPerAction * (reqQty / subOutputQty)))
                local subNode = ResolveReagentNode(mID, totalMatQty, newVisited, depth + 1, userOverrides)
                table.insert(subTreeList, subNode)
                if subNode.hasMissing then subHasMissing = true end
                if subNode.hasStale then subHasStale = true end
                subUnitCraftCost = subUnitCraftCost + (subNode.effectiveUnitPrice * mQtyPerAction)
            end

            local unitCostToCraft = math.floor(subUnitCraftCost / subOutputQty)
            node.craftUnitPrice = unitCostToCraft
            node.craftTotalPrice = unitCostToCraft * reqQty
            node.subMats = subTreeList
            node.subRecipe = subRecipe

            if subHasStale then node.hasStale = true end
            if subHasMissing then node.craftMissing = true end
        end
    end

    -- 3. Decision: Craft vs Buy
    local override = userOverrides and userOverrides[itemID]
    if override ~= nil and node.canCraft and not node.craftMissing then
        node.chooseCraft = (override == true)
    elseif node.canCraft and not node.craftMissing then
        if node.directUnitPrice > 0 and node.craftUnitPrice and node.craftUnitPrice > 0 then
            node.chooseCraft = (node.craftUnitPrice < node.directUnitPrice)
        elseif node.directUnitPrice == 0 and node.craftUnitPrice and node.craftUnitPrice > 0 then
            node.chooseCraft = true
        else
            node.chooseCraft = false
        end
    else
        node.chooseCraft = false
    end

    -- 4. Effective Price
    if node.chooseCraft and node.craftUnitPrice and node.craftUnitPrice > 0 then
        node.effectiveUnitPrice = node.craftUnitPrice
        node.effectiveTotalPrice = node.craftTotalPrice
        node.unitSavings = math.max(0, node.directUnitPrice - node.craftUnitPrice)
        node.totalSavings = node.unitSavings * reqQty
        node.isCrafted = true
        node.hasMissing = false
    else
        node.effectiveUnitPrice = node.directUnitPrice
        node.effectiveTotalPrice = node.directTotalPrice
        node.unitSavings = 0
        node.totalSavings = 0
        node.isCrafted = false
    end

    return node
end

function MarketSync.CalculateGroundUpCraftCost(recipeOrOutputItemID, userOverrides, targetMultiplier)
    local recipe = nil
    if type(recipeOrOutputItemID) == "table" and recipeOrOutputItemID.mats then
        recipe = recipeOrOutputItemID
    elseif tonumber(recipeOrOutputItemID) then
        recipe = MarketSync.GetRecipeForOutput(recipeOrOutputItemID)
    end
    if not recipe or type(recipe.mats) ~= "table" or #recipe.mats == 0 then
        return nil
    end

    local mult = math.max(1, tonumber(targetMultiplier) or 1)
    local outputQty = math.max(1, tonumber(recipe.outputQty) or 1) * mult
    local directCost = 0
    local groundUpOptimalCost = 0
    local effectiveCost = 0
    local hasMissingDirect = false
    local hasMissingEffective = false
    local hasStale = false
    local reagentNodes = {}

    for _, mat in ipairs(recipe.mats) do
        local mID = tonumber(mat.itemID)
        local mQty = (tonumber(mat.qty) or 1) * mult

        local optimalNode = ResolveReagentNode(mID, mQty, {}, 0, nil)
        local userNode = userOverrides and ResolveReagentNode(mID, mQty, {}, 0, userOverrides) or optimalNode

        table.insert(reagentNodes, userNode)

        directCost = directCost + userNode.directTotalPrice
        groundUpOptimalCost = groundUpOptimalCost + (optimalNode.effectiveTotalPrice or optimalNode.directTotalPrice)
        effectiveCost = effectiveCost + userNode.effectiveTotalPrice

        if userNode.hasMissing then hasMissingEffective = true end
        if userNode.directUnitPrice == 0 then hasMissingDirect = true end
        if userNode.hasStale then hasStale = true end
    end

    local savings = math.max(0, directCost - effectiveCost)
    local savingsPct = (directCost > 0) and math.floor((savings / directCost) * 100) or 0
    local optimalSavings = math.max(0, directCost - groundUpOptimalCost)
    local optimalSavingsPct = (directCost > 0) and math.floor((optimalSavings / directCost) * 100) or 0

    return {
        recipe = recipe,
        outputItemID = recipe.outputItemID,
        outputName = GetItemName(recipe.outputItemID) or recipe.name,
        outputQty = outputQty,
        directCraftCost = directCost,
        groundUpCost = groundUpOptimalCost,
        effectiveCost = effectiveCost,
        savings = savings,
        savingsPct = savingsPct,
        optimalSavings = optimalSavings,
        optimalSavingsPct = optimalSavingsPct,
        reagentsTree = reagentNodes,
        hasMissingDirect = hasMissingDirect,
        hasMissing = hasMissingEffective,
        hasStale = hasStale,
    }
end

function MarketSync.CalculateRecipeProfit(recipeOrOutputItemID, userOverrides, targetMultiplier)
    local costData = MarketSync.CalculateGroundUpCraftCost(recipeOrOutputItemID, userOverrides, targetMultiplier)
    if not costData then return nil end

    local outputItemID = costData.outputItemID
    local outputPrice, outputAge, outputStale = GetPriceInfoByItemID(outputItemID)
    outputPrice = outputPrice or 0

    local grossRevenue = outputPrice * costData.outputQty
    local netRevenue = math.floor(NetMainAuctionValue(grossRevenue))

    local directProfit = netRevenue - costData.directCraftCost
    local groundUpProfit = netRevenue - costData.groundUpCost
    local effectiveProfit = netRevenue - costData.effectiveCost

    local directMarginPct = (costData.directCraftCost > 0) and math.floor((directProfit / costData.directCraftCost) * 100) or 0
    local groundUpMarginPct = (costData.groundUpCost > 0) and math.floor((groundUpProfit / costData.groundUpCost) * 100) or 0
    local effectiveMarginPct = (costData.effectiveCost > 0) and math.floor((effectiveProfit / costData.effectiveCost) * 100) or 0

    local warnings = {}
    if outputPrice == 0 then
        table.insert(warnings, "No AH price for output item")
    elseif outputStale then
        table.insert(warnings, "Output price is stale (>3 days)")
    end
    if costData.hasMissing then
        table.insert(warnings, "Missing prices for some reagents")
    elseif costData.hasStale then
        table.insert(warnings, "Some reagent prices are stale")
    end

    return {
        costData = costData,
        outputItemID = outputItemID,
        outputPrice = outputPrice,
        outputAge = outputAge,
        outputStale = outputStale,
        grossRevenue = grossRevenue,
        netRevenue = netRevenue,
        ahCutPercent = MAIN_AH_CUT_PERCENT,
        directProfit = directProfit,
        groundUpProfit = groundUpProfit,
        effectiveProfit = effectiveProfit,
        directMarginPct = directMarginPct,
        groundUpMarginPct = groundUpMarginPct,
        effectiveMarginPct = effectiveMarginPct,
        warnings = warnings,
        hasWarnings = (#warnings > 0),
    }
end

function MarketSync.ExportCustomShoppingList(treeData, userOverrides, listName)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return false, "Auctionator API unavailable"
    end
    if not treeData or #treeData == 0 then
        return false, "No reagents in tree to export"
    end

    local itemsToBuy = {}

    local function CollectBuys(nodes)
        for _, node in ipairs(nodes or {}) do
            if node.chooseCraft and node.subMats and #node.subMats > 0 then
                CollectBuys(node.subMats)
            else
                local mID = node.itemID
                if mID then
                    local entry = itemsToBuy[mID]
                    if not entry then
                        entry = {
                            itemID = mID,
                            name = node.name or GetItemName(mID),
                            qty = 0,
                            maxPrice = node.directUnitPrice or 0,
                        }
                        itemsToBuy[mID] = entry
                    end
                    entry.qty = entry.qty + (node.qty or 1)
                    if node.directUnitPrice and node.directUnitPrice > 0 then
                        if entry.maxPrice == 0 or node.directUnitPrice < entry.maxPrice then
                            entry.maxPrice = node.directUnitPrice
                        end
                    end
                end
            end
        end
    end

    CollectBuys(treeData)

    local searchStrings = {}
    for itemID, info in pairs(itemsToBuy) do
        local name = info.name or GetItemName(itemID)
        if name then
            local searchStr = BuildAuctionatorSearchString(name, info.maxPrice, info.qty)
            if searchStr then
                table.insert(searchStrings, searchStr)
            end
        end
    end

    if #searchStrings == 0 then
        return false, "No purchase items resolved for export"
    end

    local exportName = listName or ("MarketSync Mats " .. date("%m/%d %H:%M"))
    local okCreate, err = pcall(Auctionator.API.v1.CreateShoppingList, CALLER_ID, exportName, searchStrings)
    if not okCreate then
        return false, tostring(err)
    end
    return true, #searchStrings
end

-- Caching vendor prices dynamically on MERCHANT_SHOW
if CreateFrame then
    local merchantWatcher = CreateFrame("Frame")
    if merchantWatcher and merchantWatcher.RegisterEvent then
        merchantWatcher:RegisterEvent("MERCHANT_SHOW")
        merchantWatcher:SetScript("OnEvent", function()
        local numItems = (GetMerchantNumItems and GetMerchantNumItems()) or 0
        local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
        if not realmDB then return end
        realmDB.VendorPrices = realmDB.VendorPrices or {}

        for i = 1, numItems do
            local link = GetMerchantItemLink and GetMerchantItemLink(i)
            local itemID = ParseItemIDFromLink(link)
            if not itemID and GetMerchantItemID then
                itemID = GetMerchantItemID(i)
            end
            if itemID then
                local price, stackCount, numAvailable
                if GetMerchantItemInfo then
                    _, _, price, stackCount, numAvailable = GetMerchantItemInfo(i)
                elseif C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                    local info = C_MerchantFrame.GetItemInfo(i)
                    if info then
                        price = info.price
                        stackCount = info.stackCount
                        numAvailable = info.numAvailable
                    end
                end
                stackCount = math.max(1, tonumber(stackCount) or 1)
                if price and price > 0 and (numAvailable == -1 or numAvailable == nil) then
                    realmDB.VendorPrices[itemID] = math.floor(price / stackCount)
                end
            end
        end
    end)
    end
end

-- ================================================================
-- TOOLTIP HOOKS (Disenchanting, Milling, Prospecting, Crafting)
-- ================================================================
local function OnTooltipSetItem(tooltip, data)
    if not MarketSyncDB then return end
    if not MarketSyncDB.EnableTooltipAuctionPrice and not MarketSyncDB.EnableTooltipProb and not MarketSyncDB.EnableTooltipCraftCost then return end
    if not tooltip then return end

    local name, link
    if tooltip.GetItem then
        name, link = tooltip:GetItem()
    end
    
    local itemID = nil
    if link and link:match("item:(%d+)") then
        itemID = tonumber(link:match("item:(%d+)"))
    elseif link then
        itemID = MarketSync.ParseItemIDFromDBKey(link)
    end
    if not itemID and data and data.id then
        itemID = data.id
    end
    if not itemID and name then
        local cleanName = name:match("%[(.-)%]") or name
        if C_Item and C_Item.GetItemInfoInstant then
            local ok, id = pcall(C_Item.GetItemInfoInstant, cleanName)
            if ok and tonumber(id) then itemID = tonumber(id) end
        elseif GetItemInfoInstant then
            local ok, id = pcall(GetItemInfoInstant, cleanName)
            if ok and tonumber(id) then itemID = tonumber(id) end
        end
    end
    if not itemID then return end

    if (not link or not link:match("item:%d+")) and itemID then
        local _, resolvedLink = SafeGetItemInfo(itemID)
        link = resolvedLink or ("item:" .. itemID)
    end

    -- 0. Native MarketSync AH Price & Scan Freshness (for Standalone or unhooked items)
    if MarketSyncDB.EnableTooltipAuctionPrice ~= false then
        local priceInfo = MarketSync.GetItemPriceAndScanInfo and MarketSync.GetItemPriceAndScanInfo(link or itemID)
        if priceInfo and priceInfo.price and priceInfo.price > 0 then
            local hasAuctionatorLine = false
            if Auctionator and Auctionator.API and tooltip.NumLines and tooltip.GetName then
                local tName = tooltip:GetName()
                if tName then
                    for i = 1, tooltip:NumLines() do
                        local leftLine = _G[tName .. "TextLeft" .. i]
                        local text = leftLine and leftLine.GetText and leftLine:GetText()
                        if text and (text:find("Auction:") or text:find("Auctionator:")) then
                            hasAuctionatorLine = true
                            break
                        end
                    end
                end
            end

            if not hasAuctionatorLine then
                local priceStr = MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(priceInfo.price) or MarketSync.FormatMoney(priceInfo.price)
                local ageStr = MarketSync.FormatRelativeTime and MarketSync.FormatRelativeTime(priceInfo.scanTime, priceInfo.ageDays) or "Today"
                local sourceStr = priceInfo.source or "MarketSync"
                
                tooltip:AddDoubleLine("|cffffd700MarketSync AH:|r", priceStr)
                
                local stackCount = nil
                if data and type(data.stackCount) == "number" and data.stackCount > 1 then
                    stackCount = data.stackCount
                elseif tooltip.GetItem then
                    local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
                    if focus then
                        if type(focus.stackCount) == "number" and focus.stackCount > 1 then
                            stackCount = focus.stackCount
                        elseif type(focus.count) == "number" and focus.count > 1 then
                            stackCount = focus.count
                        elseif type(focus.Count) == "number" and focus.Count > 1 then
                            stackCount = focus.Count
                        elseif type(focus.count) == "table" and focus.count.GetText then
                            local n = tonumber(focus.count:GetText())
                            if n and n > 1 then stackCount = n end
                        elseif type(focus.Count) == "table" and focus.Count.GetText then
                            local n = tonumber(focus.Count:GetText())
                            if n and n > 1 then stackCount = n end
                        end
                    end
                end
                if stackCount and stackCount > 1 then
                    local stackPrice = priceInfo.price * stackCount
                    local stackStr = MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(stackPrice) or MarketSync.FormatMoney(stackPrice)
                    tooltip:AddDoubleLine(string.format("|cffffd700Stack (%d):|r", stackCount), stackStr)
                end
                
                tooltip:AddDoubleLine("|cff888888Scanned:|r", string.format("|cffaaaaaa%s (%s)|r", ageStr, sourceStr))
                
                if priceInfo.neutralPrice and priceInfo.neutralPrice > 0 and priceInfo.neutralPrice ~= priceInfo.price then
                    local nPriceStr = MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(priceInfo.neutralPrice) or MarketSync.FormatMoney(priceInfo.neutralPrice)
                    tooltip:AddDoubleLine("|cff00ccffNeutral AH:|r", nPriceStr)
                end
            end
        end
    end

    -- 0.5. Craft Cost & Profit Tooltip (Direct vs Ground-Up)
    if MarketSyncDB.EnableTooltipCraftCost ~= false and itemID then
        local craftRecipe = MarketSync.GetRecipeForOutput and MarketSync.GetRecipeForOutput(itemID)
        if craftRecipe then
            local profitData = MarketSync.CalculateRecipeProfit and MarketSync.CalculateRecipeProfit(craftRecipe)
            if profitData and profitData.costData then
                local cost = profitData.costData
                tooltip:AddLine(" ")
                local yieldStr = (cost.outputQty and cost.outputQty > 1) and string.format(" (x%d)", cost.outputQty) or ""
                tooltip:AddLine("|cffffd700MarketSync Crafting" .. yieldStr .. "|r")

                local costStr = MarketSync.FormatMoneyColored and MarketSync.FormatMoneyColored(cost.effectiveCost) or MarketSync.FormatMoney(cost.effectiveCost)
                if cost.savings and cost.savings > 0 then
                    local saveStr = MarketSync.FormatMoney(cost.savings)
                    tooltip:AddDoubleLine("Ground-Up Cost:", string.format("%s |cff00ff00(Save %s)|r", costStr, saveStr))
                    local dirStr = MarketSync.FormatMoney(cost.directCraftCost)
                    tooltip:AddDoubleLine("|cff888888Direct AH Mats:|r", "|cffaaaaaa" .. dirStr .. "|r")
                else
                    tooltip:AddDoubleLine("To Craft:", costStr)
                end

                if profitData.outputPrice and profitData.outputPrice > 0 then
                    local pVal = profitData.effectiveProfit
                    local pCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
                    local pStr = MarketSync.FormatMoney(math.abs(pVal))
                    local mCol = (pVal >= 0) and "|cff00ff00+" or "|cffff2020"
                    tooltip:AddDoubleLine("Craft Profit:", string.format("%s%s|r (%s%d%%|r)", pCol, pStr, mCol, profitData.effectiveMarginPct))
                end
            end
        end
    end

    if not MarketSyncDB.EnableTooltipProb then return end

    -- 1. Check ProcessingData (Milling/Prospecting)
    if MarketSync.ProcessingData and MarketSync.ProcessingData[itemID] then
        local def = MarketSync.ProcessingData[itemID]
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffffd700MarketSync " .. (def.type or "Processing") .. "|r")
        local evTotal = 0
        local hasStale = false
        local missingOutputs = 0
        for _, y in ipairs(def.yields or {}) do
            local yName = GetItemName(y.itemID) or ("Item " .. y.itemID)
            local expected = ExpectedYield(y)
            local priceInfo = ""
            local price, _, outStale = GetPriceInfoByItemID(y.itemID)
            if price and price > 0 then
                evTotal = evTotal + (price * expected)
                priceInfo = " (" .. MarketSync.FormatMoney(price) .. ")"
                if outStale then hasStale = true end
            else
                missingOutputs = missingOutputs + 1
            end
            
            local probStr = ""
            if y.prob and y.prob < 1.0 then
                probStr = string.format(" %.0f%%", y.prob * 100)
            end
            
            tooltip:AddLine(string.format("- %sx %s%s%s", FormatExpectedQuantity(expected), yName, probStr, priceInfo), 0.85, 0.85, 0.85)
        end
        if evTotal > 0 then
            tooltip:AddLine(string.format("Net AH Value (-%d%%): %s", MAIN_AH_CUT_PERCENT,
                MarketSync.FormatMoney(NetMainAuctionValue(evTotal))), 0, 1, 0)
            if hasStale then
                tooltip:AddLine("(Based on stale data)", 1, 0.5, 0.5)
            end
        end
        if missingOutputs > 0 then
            tooltip:AddLine(string.format("(Partial value: %d output price%s missing)", missingOutputs,
                missingOutputs == 1 and "" or "s"), 1, 0.5, 0.5)
        end
    end

    -- Helper to check if another addon already printed breakdown info
    local function HasExternalBreakdown(tooltipObj, keyword)
        local tName = tooltipObj and tooltipObj.GetName and tooltipObj:GetName()
        if not tName or not tooltipObj.NumLines then return false end
        for i = 1, tooltipObj:NumLines() do
            local line = _G[tName .. "TextLeft" .. i]
            if line and line.GetText and line:GetText() and line:GetText():find(keyword) then
                return true
            end
        end
        return false
    end

    -- 2. Check Disenchanting
    if MarketSync.EstimateDisenchantEV then
        local quality, classID
        if link then
            _, _, quality, _, _, _, _, _, _, _, _, classID = SafeGetItemInfo(link)
        elseif itemID then
            _, _, quality, _, _, _, _, _, _, _, _, classID = SafeGetItemInfo(itemID)
        end

        local ilvl = 0
        if link then
            ilvl = SafeGetDetailedItemLevelInfo(link)
        elseif itemID then
            ilvl = SafeGetDetailedItemLevelInfo(itemID)
        end
        if (not ilvl or ilvl == 0) and link then
            ilvl = select(4, SafeGetItemInfo(link)) or 0
        end
        if (not ilvl or ilvl == 0) and itemID then
            ilvl = select(4, SafeGetItemInfo(itemID)) or 0
        end

        if quality and quality >= 2 and quality <= 4 and (classID == 2 or classID == 4) and ilvl > 0 then
            local ev, stale, missing, _, partial, drops =
                MarketSync.EstimateDisenchantEV(quality, ilvl, classID, itemID)
            
            local addedHeader = false
            
            -- Only print full breakdown if Auctionator/TSM hasn't already done it
            if not HasExternalBreakdown(tooltip, "Disenchant") then
                if type(drops) == "table" and #drops > 0 then
                    tooltip:AddLine(" ")
                    tooltip:AddLine("|cffffd700MarketSync Disenchanting|r")
                    addedHeader = true
                    for _, drop in ipairs(drops) do
                        local yName = GetItemName(drop.itemID) or ("Item " .. tostring(drop.itemID))
                        tooltip:AddLine(string.format("- %sx %s (%.1f%% chance)",
                            FormatExpectedQuantity(drop.expected), yName, drop.chance * 100), 0.85, 0.85, 0.85)
                    end
                end
            end

            if ev and ev > 0 then
                if not addedHeader then
                    tooltip:AddLine(" ")
                    tooltip:AddLine("|cffffd700MarketSync Disenchanting|r")
                end
                tooltip:AddLine(string.format("Net AH Value (-%d%%): %s", MAIN_AH_CUT_PERCENT,
                    MarketSync.FormatMoney(ev)), 0, 1, 0)
                if stale then
                    tooltip:AddLine("(Based on stale data)", 1, 0.5, 0.5)
                end
                if partial or missing > 0 then
                    tooltip:AddLine(string.format("(Partial value: %d output price%s missing)", missing,
                        missing == 1 and "" or "s"), 1, 0.5, 0.5)
                end
            end
        end
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
else
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ItemRefTooltip and ItemRefTooltip.HookScript then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
end
-- ================================================================
-- ITEM HISTORY DATA EXTRACTION
-- ================================================================

-- Convert a bucket offset (0-47) on a given scanDay to a human-readable time string
function MarketSync.BucketOffsetToTime(bucketOffset)
    local hours = math.floor(bucketOffset / 2)
    local mins = (bucketOffset % 2 == 0) and "00" or "30"
    return string.format("%d:%s", hours, mins)
end

-- Returns a flat list of data points for the graph and scan table.
-- When granular PersonalData is available, each 30-min bucket becomes
-- its own data point. Otherwise, falls back to daily Auctionator aggregates.
function MarketSync.GetItemHistory(dbKey)
    local pData = MarketSyncDB and MarketSync.GetRealmDB and MarketSync.GetRealmDB().PersonalData and MarketSync.GetRealmDB().PersonalData[dbKey]
    local priceData = Auctionator and Auctionator.Database and Auctionator.Database.db and Auctionator.Database.db[dbKey]
    if (not priceData or not priceData.h) and (not pData or not pData.h) then return {} end

    local history = {}
    local meta = MarketSyncDB and MarketSync.GetRealmDB and MarketSync.GetRealmDB().ItemMetadata and MarketSync.GetRealmDB().ItemMetadata[dbKey]
    local FromBase36 = MarketSync.FromBase36

    -- Track which days have granular data so we don't double-count
    local granularDays = {}

    -- 1. Unpack granular timeseries strings and compact summaries from PersonalData
    if pData and pData.h then
        for dayStr, histStr in pairs(pData.h) do
            if histStr and histStr ~= "" then
                if MarketSync.IsCompactRecord and MarketSync.IsCompactRecord(histStr) then
                    local parsed = MarketSync.ParseCompactRecord and MarketSync.ParseCompactRecord(histStr)
                    if parsed then
                        local day = tonumber(dayStr)
                        local isWeekly = false
                        if not day and type(dayStr) == "string" and dayStr:sub(1, 2) == "W_" then
                            local weekNum = tonumber(dayStr:sub(3))
                            if weekNum then
                                day = weekNum * 7
                                isWeekly = true
                            end
                        end
                        if day then
                            granularDays[tostring(day)] = true
                            local timeLabel = isWeekly and "Weekly Avg" or "Daily Avg"
                            table.insert(history, {
                                day = day,
                                bucketOffset = nil,
                                sortKey = (day * 100) + 48,
                                high = parsed.max,
                                low = parsed.min,
                                price = parsed.avg,
                                quantity = parsed.volume,
                                source = "Personal",
                                timeLabel = timeLabel,
                                isGranular = false,
                                isCompact = true,
                                isWeekly = isWeekly,
                            })
                        end
                    end
                else
                    local day = tonumber(dayStr)
                    if day then
                        granularDays[dayStr] = true
                        for b_offs, p_b36, q_b36 in string.gmatch(histStr, "(%d+):([%w%-]+):([%w%-]+)") do
                            local bucketOffset = tonumber(b_offs)
                            local price = FromBase36(p_b36)
                            local qty = FromBase36(q_b36)
                            if price and price > 0 then
                                -- Per-day source attribution
                                local source = "Personal"
                                if meta and meta.days and meta.days[dayStr] then
                                    local s = meta.days[dayStr].source
                                    if s then source = s:match("^([^%-]+)") or s end
                                end

                                table.insert(history, {
                                    day = day,
                                    bucketOffset = bucketOffset,
                                    -- sortKey: scanDay * 100 + bucketOffset gives chronological ordering
                                    sortKey = (day * 100) + bucketOffset,
                                    high = price,
                                    low = price,
                                    price = price,
                                    quantity = qty,
                                    source = source,
                                    timeLabel = MarketSync.BucketOffsetToTime and MarketSync.BucketOffsetToTime(bucketOffset) or "",
                                    isGranular = true,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Fill any days that DON'T have granular data with daily aggregate fallback
    if priceData and priceData.h then
        for dayStr, highPrice in pairs(priceData.h) do
            local day = tonumber(dayStr)
            if day and not granularDays[dayStr] then
                local lowPrice = priceData.l and priceData.l[dayStr] or highPrice
                local qty = priceData.a and priceData.a[dayStr] or 0

                local source = "Personal"
                if meta and meta.days and meta.days[dayStr] then
                    local s = meta.days[dayStr].source
                    if s then source = s:match("^([^%-]+)") or s end
                elseif day == (MarketSync.GetCurrentScanDay and MarketSync.GetCurrentScanDay() or 0) then
                    source = "Personal"
                end

                table.insert(history, {
                    day = day,
                    bucketOffset = nil,
                    sortKey = day * 100,
                    high = highPrice,
                    low = lowPrice,
                    price = highPrice,
                    quantity = qty,
                    source = source,
                    isGranular = false,
                })
            end
        end
    end

    -- Sort newest first (highest sortKey first)
    table.sort(history, function(a, b) return a.sortKey > b.sortKey end)
    return history
end

-- Returns ONLY the granular 30-min data points for analytics algorithms.
-- Compact daily/weekly records are skipped to preserve intraday accuracy.
-- Each entry: { day, bucketOffset, price, quantity, timestamp }
function MarketSync.GetGranularHistory(dbKey)
    local realmDB = MarketSync.GetRealmDB and MarketSync.GetRealmDB()
    local pData = realmDB and realmDB.PersonalData and realmDB.PersonalData[dbKey]
    if not pData or not pData.h then return {} end

    local FromBase36 = MarketSync.FromBase36
    local points = {}

    for dayStr, histStr in pairs(pData.h) do
        -- Skip compact summaries (not 30-min bucket points)
        if not (MarketSync.IsCompactRecord and MarketSync.IsCompactRecord(histStr)) and not (type(dayStr) == "string" and dayStr:sub(1, 2) == "W_") then
            local day = tonumber(dayStr)
            if day and histStr and histStr ~= "" then
                for b_offs, p_b36, q_b36 in string.gmatch(histStr, "(%d+):([%w%-]+):([%w%-]+)") do
                    local bucketOffset = tonumber(b_offs)
                    local price = FromBase36(p_b36)
                    local qty = FromBase36(q_b36)
                    if price and price > 0 then
                        -- Reconstruct approximate UNIX timestamp for this data point
                        local dayTimestamp = MarketSync.ScanDayToTimestamp and MarketSync.ScanDayToTimestamp(day)
                        if not dayTimestamp then
                            local scan0 = (Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0)
                                or (MarketSync and MarketSync.SCAN_DAY_0)
                                or 1577836800
                            dayTimestamp = (day > 10000 and (day * 86400)) or (scan0 + (day * 86400))
                        end
                        local pointTimestamp = dayTimestamp + (bucketOffset * 1800)

                        table.insert(points, {
                            day = day,
                            bucketOffset = bucketOffset,
                            price = price,
                            quantity = qty,
                            timestamp = pointTimestamp,
                            timeLabel = MarketSync.BucketOffsetToTime and MarketSync.BucketOffsetToTime(bucketOffset) or "",
                        })
                    end
                end
            end
        end
    end

    table.sort(points, function(a, b) return a.timestamp < b.timestamp end)
    return points
end
