-- ================================================================
-- MarketSync - Shopping List Import/Export Codec (!MS1!)
-- Pure Lua 5.1 arithmetic implementation (zero bit/bit32/5.2+ ops)
-- ================================================================

MarketSync = MarketSync or {}
MarketSync.ListCodec = MarketSync.ListCodec or {}

local LC = MarketSync.ListCodec

LC.PREFIX = "!MS1!"
LC.VERSION = 1
LC.MAX_COPPER = 99999999999
LC.MAX_LIST_NAME_LENGTH = 64
LC.MAX_REALM_SLUG_LENGTH = 64
LC.MAX_ITEM_NAME_LENGTH = 128
LC.MAX_ITEM_NOTE_LENGTH = 256
LC.MAX_LIST_ITEMS = 1000
LC.VALID_FLAVORS = {
    forever = true,
    classicEra = true,
    anniversary = true,
    classic = true,
    retail = true,
}
LC.VALID_FACTIONS = {
    Alliance = true,
    Horde = true,
    Neutral = true,
    CrossFaction = true,
    Commodities = true,
}

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function IsFiniteInteger(n)
    return type(n) == "number"
        and n == n
        and n > -9007199254740992
        and n < 9007199254740992
        and math.floor(n) == n
end

local function CountUtf8Chars(s)
    local count = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 128 or b >= 192 then
            count = count + 1
        end
    end
    return count
end

local function TruncateUtf8Chars(s, maxChars)
    if type(s) ~= "string" then return "" end
    if maxChars <= 0 then return "" end
    local count = 0
    local i = 1
    local len = #s
    while i <= len do
        local b = string.byte(s, i)
        local charLen = 1
        if b >= 240 then
            charLen = 4
        elseif b >= 224 then
            charLen = 3
        elseif b >= 192 then
            charLen = 2
        end
        if count + 1 > maxChars or i + charLen - 1 > len then
            return s:sub(1, i - 1)
        end
        count = count + 1
        i = i + charLen
    end
    return s
end

-- ================================================================
-- 1. PURE LUA 5.1 ARITHMETIC IEEE 802.3 CRC-32 (0xEDB88320)
-- ================================================================
local XOR4 = {}
for a = 0, 15 do
    XOR4[a] = {}
    for b = 0, 15 do
        local x, y, r, bitVal = a, b, 0, 1
        for _ = 1, 4 do
            local xb = x % 2
            local yb = y % 2
            if xb ~= yb then
                r = r + bitVal
            end
            x = (x - xb) / 2
            y = (y - yb) / 2
            bitVal = bitVal * 2
        end
        XOR4[a][b] = r
    end
end

local function xor8(a, b)
    local al = a % 16
    local bl = b % 16
    return XOR4[math.floor(al)][math.floor(bl)] + 16 * XOR4[math.floor((a - al) / 16)][math.floor((b - bl) / 16)]
end

local function xor32(a, b)
    local a0 = a % 256; a = (a - a0) / 256
    local a1 = a % 256; a = (a - a1) / 256
    local a2 = a % 256; local a3 = (a - a2) / 256
    local b0 = b % 256; b = (b - b0) / 256
    local b1 = b % 256; b = (b - b1) / 256
    local b2 = b % 256; local b3 = (b - b2) / 256
    return xor8(a0, b0) + 256.0 * (xor8(a1, b1) + 256.0 * (xor8(a2, b2) + 256.0 * xor8(a3, b3)))
end

local CRC32_POLY = 3988292384.0 -- 0xEDB88320
local CRC32_TABLE = {}
for i = 0, 255 do
    local c = i + 0.0
    for _ = 1, 8 do
        local lsb = c % 2
        c = (c - lsb) / 2
        if lsb == 1 then
            c = xor32(c, CRC32_POLY)
        end
    end
    CRC32_TABLE[i] = c
end

function LC.CRC32(str)
    if type(str) ~= "string" then return 0 end
    local crc = 4294967295.0
    for i = 1, #str do
        local b = string.byte(str, i)
        local low = crc % 256
        crc = xor32((crc - low) / 256, CRC32_TABLE[math.floor(xor8(low, b))])
    end
    return 4294967295.0 - crc
end

function LC.CRC32Hex(str)
    local crc = LC.CRC32(str)
    return string.format("%04x%04x", math.floor(crc / 65536), crc % 65536)
end

-- ================================================================
-- 2. PURE LUA 5.1 URL-SAFE BASE64 (UNPADDED)
-- ================================================================
local B64_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_ENC = {}
local B64_DEC = {}
for idx = 1, #B64_ALPHA do
    local ch = B64_ALPHA:sub(idx, idx)
    B64_ENC[idx - 1] = ch
    B64_DEC[string.byte(ch)] = idx - 1
end

function LC.Base64UrlEncode(bytes)
    if type(bytes) ~= "string" then return "" end
    local len = #bytes
    if len == 0 then return "" end
    local out = {}
    local i = 1
    while i <= len do
        local b1 = string.byte(bytes, i)
        local b2 = string.byte(bytes, i + 1)
        local b3 = string.byte(bytes, i + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64_ENC[c1]
        out[#out + 1] = B64_ENC[c2]
        if b2 ~= nil then
            out[#out + 1] = B64_ENC[c3]
        end
        if b3 ~= nil then
            out[#out + 1] = B64_ENC[c4]
        end
        i = i + 3
    end
    return table.concat(out)
end

function LC.Base64UrlDecode(b64)
    if type(b64) ~= "string" or b64 == "" then
        return nil, "Empty base64url payload"
    end
    if not b64:match("^[A-Za-z0-9%-_]+$") then
        return nil, "Invalid base64url characters"
    end
    local len = #b64
    if len < 2 or (len % 4) == 1 then
        return nil, "Invalid base64url length"
    end
    local out = {}
    local i = 1
    while i <= len do
        local rem = len - i + 1
        if rem >= 4 then
            local v1 = B64_DEC[string.byte(b64, i)]
            local v2 = B64_DEC[string.byte(b64, i + 1)]
            local v3 = B64_DEC[string.byte(b64, i + 2)]
            local v4 = B64_DEC[string.byte(b64, i + 3)]
            local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
            out[#out + 1] = string.char(math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
            i = i + 4
        elseif rem == 3 then
            local v1 = B64_DEC[string.byte(b64, i)]
            local v2 = B64_DEC[string.byte(b64, i + 1)]
            local v3 = B64_DEC[string.byte(b64, i + 2)]
            if (v3 % 4) ~= 0 then
                return nil, "Non-zero trailing bits in base64url payload"
            end
            local n = v1 * 262144 + v2 * 4096 + v3 * 64
            out[#out + 1] = string.char(math.floor(n / 65536), math.floor(n / 256) % 256)
            break
        elseif rem == 2 then
            local v1 = B64_DEC[string.byte(b64, i)]
            local v2 = B64_DEC[string.byte(b64, i + 1)]
            if (v2 % 16) ~= 0 then
                return nil, "Non-zero trailing bits in base64url payload"
            end
            local n = v1 * 262144 + v2 * 4096
            out[#out + 1] = string.char(math.floor(n / 65536))
            break
        end
    end
    return table.concat(out)
end

-- ================================================================
-- 3. CANONICAL JSON ENCODER & RFC 8259 DECODER
-- ================================================================
local JSON_NULL = {}

local function EncodeJsonString(str)
    local out = { '"' }
    for i = 1, #str do
        local b = string.byte(str, i)
        if b == 34 then
            out[#out + 1] = '\\"'
        elseif b == 92 then
            out[#out + 1] = '\\\\'
        elseif b == 8 then
            out[#out + 1] = '\\b'
        elseif b == 12 then
            out[#out + 1] = '\\f'
        elseif b == 10 then
            out[#out + 1] = '\\n'
        elseif b == 13 then
            out[#out + 1] = '\\r'
        elseif b == 9 then
            out[#out + 1] = '\\t'
        elseif b < 32 then
            out[#out + 1] = string.format("\\u%04x", b)
        else
            out[#out + 1] = string.char(b)
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function CodepointToUtf8(cp)
    if cp < 0 or cp > 1114111 then
        return nil
    elseif cp <= 127 then
        return string.char(cp)
    elseif cp <= 2047 then
        return string.char(192 + math.floor(cp / 64), 128 + (cp % 64))
    elseif cp <= 65535 then
        return string.char(
            224 + math.floor(cp / 4096),
            128 + (math.floor(cp / 64) % 64),
            128 + (cp % 64)
        )
    else
        return string.char(
            240 + math.floor(cp / 262144),
            128 + (math.floor(cp / 4096) % 64),
            128 + (math.floor(cp / 64) % 64),
            128 + (cp % 64)
        )
    end
end

function LC.JsonDecode(str)
    if type(str) ~= "string" then
        return nil, "JSON input must be a string"
    end
    local len = #str
    local pos = 1
    local arrayRefs = {}
    local maxDepth = 32

    local function SkipWs()
        while pos <= len do
            local b = string.byte(str, pos)
            if b == 32 or b == 9 or b == 10 or b == 13 then
                pos = pos + 1
            else
                break
            end
        end
    end

    local ParseValue

    local function ParseHex4()
        if pos + 3 > len then return nil end
        local hex = str:sub(pos, pos + 3)
        if not hex:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
            return nil
        end
        pos = pos + 4
        return tonumber(hex, 16)
    end

    local function ParseString()
        pos = pos + 1 -- skip opening "
        local out = {}
        while pos <= len do
            local b = string.byte(str, pos)
            if b == 34 then
                pos = pos + 1
                return table.concat(out)
            elseif b == 92 then
                pos = pos + 1
                if pos > len then return nil, "Unterminated escape sequence" end
                local esc = string.byte(str, pos)
                pos = pos + 1
                if esc == 34 then out[#out + 1] = '"'
                elseif esc == 92 then out[#out + 1] = '\\'
                elseif esc == 47 then out[#out + 1] = '/'
                elseif esc == 98 then out[#out + 1] = string.char(8)
                elseif esc == 102 then out[#out + 1] = string.char(12)
                elseif esc == 110 then out[#out + 1] = '\n'
                elseif esc == 114 then out[#out + 1] = '\r'
                elseif esc == 116 then out[#out + 1] = '\t'
                elseif esc == 117 then
                    local code = ParseHex4()
                    if not code then return nil, "Invalid unicode escape" end
                    if code >= 55296 and code <= 56319 then
                        -- High surrogate: must be followed by \uDC00..\uDFFF
                        if str:sub(pos, pos + 1) ~= "\\u" then
                            return nil, "Unpaired high surrogate"
                        end
                        pos = pos + 2
                        local low = ParseHex4()
                        if not low or low < 56320 or low > 57343 then
                            return nil, "Invalid low surrogate"
                        end
                        local cp = 65536 + (code - 55296) * 1024 + (low - 56320)
                        out[#out + 1] = CodepointToUtf8(cp)
                    elseif code >= 56320 and code <= 57343 then
                        return nil, "Unexpected low surrogate"
                    else
                        local utf8 = CodepointToUtf8(code)
                        if not utf8 then return nil, "Invalid codepoint" end
                        out[#out + 1] = utf8
                    end
                else
                    return nil, "Invalid JSON escape"
                end
            elseif b < 32 then
                return nil, "Unescaped control character in JSON string"
            else
                out[#out + 1] = string.char(b)
                pos = pos + 1
            end
        end
        return nil, "Unterminated JSON string"
    end

    local function ParseNumber()
        local startPos = pos
        local ch = string.byte(str, pos)
        if ch == 45 then pos = pos + 1 end
        if pos > len then return nil, "Invalid number" end
        local first = string.byte(str, pos)
        if first == 48 then
            pos = pos + 1
            local nxt = string.byte(str, pos)
            if nxt and nxt >= 48 and nxt <= 57 then
                return nil, "Leading zero in number"
            end
        elseif first >= 49 and first <= 57 then
            while pos <= len do
                local d = string.byte(str, pos)
                if d >= 48 and d <= 57 then
                    pos = pos + 1
                else
                    break
                end
            end
        else
            return nil, "Invalid number"
        end
        if pos <= len and string.byte(str, pos) == 46 then
            pos = pos + 1
            local fracStart = pos
            while pos <= len do
                local d = string.byte(str, pos)
                if d >= 48 and d <= 57 then
                    pos = pos + 1
                else
                    break
                end
            end
            if pos == fracStart then return nil, "Invalid number fraction" end
        end
        if pos <= len and (string.byte(str, pos) == 101 or string.byte(str, pos) == 69) then
            pos = pos + 1
            if pos <= len and (string.byte(str, pos) == 43 or string.byte(str, pos) == 45) then
                pos = pos + 1
            end
            local expStart = pos
            while pos <= len do
                local d = string.byte(str, pos)
                if d >= 48 and d <= 57 then
                    pos = pos + 1
                else
                    break
                end
            end
            if pos == expStart then return nil, "Invalid number exponent" end
        end
        local num = tonumber(str:sub(startPos, pos - 1))
        if not num or num ~= num or num == math.huge or num == -math.huge then
            return nil, "Non-finite number"
        end
        return num
    end

    local function ParseArray(depth)
        if depth > maxDepth then return nil, "JSON nesting too deep" end
        pos = pos + 1 -- skip [
        SkipWs()
        local arr = {}
        arrayRefs[arr] = true
        if pos <= len and string.byte(str, pos) == 93 then
            pos = pos + 1
            return arr
        end
        while true do
            local val, err = ParseValue(depth + 1)
            if err then return nil, err end
            arr[#arr + 1] = val
            SkipWs()
            if pos > len then return nil, "Unterminated array" end
            local sep = string.byte(str, pos)
            if sep == 93 then
                pos = pos + 1
                return arr
            elseif sep == 44 then
                pos = pos + 1
                SkipWs()
            else
                return nil, "Expected ',' or ']' in array"
            end
        end
    end

    local function ParseObject(depth)
        if depth > maxDepth then return nil, "JSON nesting too deep" end
        pos = pos + 1 -- skip {
        SkipWs()
        local obj = {}
        if pos <= len and string.byte(str, pos) == 125 then
            pos = pos + 1
            return obj
        end
        while true do
            SkipWs()
            if pos > len or string.byte(str, pos) ~= 34 then
                return nil, "Expected object key string"
            end
            local key, kerr = ParseString()
            if kerr then return nil, kerr end
            SkipWs()
            if pos > len or string.byte(str, pos) ~= 58 then
                return nil, "Expected ':' after object key"
            end
            pos = pos + 1
            SkipWs()
            local val, verr = ParseValue(depth + 1)
            if verr then return nil, verr end
            obj[key] = val
            SkipWs()
            if pos > len then return nil, "Unterminated object" end
            local sep = string.byte(str, pos)
            if sep == 125 then
                pos = pos + 1
                return obj
            elseif sep == 44 then
                pos = pos + 1
                SkipWs()
            else
                return nil, "Expected ',' or '}' in object"
            end
        end
    end

    ParseValue = function(depth)
        SkipWs()
        if pos > len then return nil, "Unexpected end of JSON" end
        local b = string.byte(str, pos)
        if b == 123 then
            return ParseObject(depth)
        elseif b == 91 then
            return ParseArray(depth)
        elseif b == 34 then
            return ParseString()
        elseif b == 116 and str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif b == 102 and str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif b == 110 and str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return JSON_NULL
        elseif b == 45 or (b >= 48 and b <= 57) then
            return ParseNumber()
        end
        return nil, "Unexpected token in JSON"
    end

    local root, err = ParseValue(1)
    if err then return nil, err end
    SkipWs()
    if pos <= len then
        return nil, "Trailing data after JSON root"
    end
    return root, nil, arrayRefs
end

local function CleanNull(v)
    if v == JSON_NULL then return nil end
    return v
end

local function IsLuaArray(tbl, arrayRefs)
    if type(tbl) ~= "table" then return false end
    if arrayRefs then
        return arrayRefs[tbl] == true
    end
    local count = #tbl
    for k in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k > count or math.floor(k) ~= k then
            return false
        end
    end
    return true
end

function LC.ValidatePayload(tbl, arrayRefs)
    if type(tbl) ~= "table" or (arrayRefs and arrayRefs[tbl]) then
        return nil, "Payload must be an object"
    end
    if tbl.v ~= LC.VERSION then
        return nil, "Unsupported schema version"
    end
    local rawN = CleanNull(tbl.n)
    if type(rawN) ~= "string" then
        return nil, "List name must be non-empty"
    end
    local n = Trim(rawN)
    if n == "" then
        return nil, "List name must be non-empty"
    end
    if CountUtf8Chars(n) > LC.MAX_LIST_NAME_LENGTH then
        return nil, "List name exceeds 64 characters"
    end

    local f = CleanNull(tbl.f)
    if f ~= nil then
        if type(f) ~= "string" then
            return nil, "Invalid client flavor"
        end
        f = Trim(f)
        if f == "" then
            f = nil
        elseif not LC.VALID_FLAVORS[f] then
            return nil, "Invalid client flavor"
        end
    end

    local r = CleanNull(tbl.r)
    if r ~= nil then
        if type(r) ~= "string" then
            return nil, "Invalid ruleset or realm"
        end
        r = Trim(r)
        if r == "" then
            r = nil
        elseif CountUtf8Chars(r) > LC.MAX_REALM_SLUG_LENGTH then
            return nil, "Ruleset or realm exceeds 64 characters"
        end
    end

    local fa = CleanNull(tbl.fa)
    if fa ~= nil then
        if type(fa) ~= "string" then
            return nil, "Invalid faction"
        end
        fa = Trim(fa)
        if fa == "" then
            fa = nil
        elseif not LC.VALID_FACTIONS[fa] then
            return nil, "Invalid faction"
        end
    end

    local rawItems = CleanNull(tbl.i)
    if not IsLuaArray(rawItems, arrayRefs) then
        return nil, "Items field must be an array"
    end
    if #rawItems > LC.MAX_LIST_ITEMS then
        return nil, "Shopping list exceeds maximum of 1000 items"
    end

    local items = {}
    for idx = 1, #rawItems do
        local entry = rawItems[idx]
        if type(entry) ~= "table" or (arrayRefs and arrayRefs[entry]) then
            return nil, "Invalid item entry at index " .. idx
        end
        local id = CleanNull(entry.id)
        if not IsFiniteInteger(id) or id < 1 then
            return nil, "Invalid item id at index " .. idx
        end

        local q = CleanNull(entry.q)
        if q == nil then
            q = 1
        elseif not IsFiniteInteger(q) or q < 1 then
            return nil, "Invalid item quantity at index " .. idx
        end

        local s = CleanNull(entry.s)
        if s ~= nil and (not IsFiniteInteger(s) or s < 0) then
            return nil, "Invalid item suffix at index " .. idx
        end
        if s == 0 then s = nil end

        local m = CleanNull(entry.m)
        if m ~= nil and (not IsFiniteInteger(m) or m < 0 or m > LC.MAX_COPPER) then
            return nil, "Invalid maxPrice at index " .. idx
        end
        if m == 0 then m = nil end

        local nm = CleanNull(entry.nm)
        if nm ~= nil then
            if type(nm) ~= "string" then
                return nil, "Invalid fallback name at index " .. idx
            end
            nm = Trim(nm)
            if nm == "" then
                nm = nil
            elseif CountUtf8Chars(nm) > LC.MAX_ITEM_NAME_LENGTH then
                return nil, "Fallback name exceeds 128 characters at index " .. idx
            end
        end

        local nt = CleanNull(entry.nt)
        if nt ~= nil then
            if type(nt) ~= "string" then
                return nil, "Invalid note at index " .. idx
            end
            if Trim(nt) == "" then
                nt = nil
            elseif CountUtf8Chars(nt) > LC.MAX_ITEM_NOTE_LENGTH then
                return nil, "Note exceeds 256 characters at index " .. idx
            end
        end

        local d = CleanNull(entry.d)
        if d ~= nil then
            if type(d) == "boolean" then d = d and 1 or 0 end
            if d ~= 0 and d ~= 1 then
                return nil, "Invalid done flag at index " .. idx
            end
            if d == 0 then d = nil end
        end

        local a = CleanNull(entry.a)
        if a ~= nil then
            if type(a) == "boolean" then a = a and 1 or 0 end
            if a ~= 0 and a ~= 1 then
                return nil, "Invalid alert flag at index " .. idx
            end
            if a == 0 then a = nil end
        end

        local cleanItem = { id = id, q = q }
        if s ~= nil then cleanItem.s = s end
        if m ~= nil then cleanItem.m = m end
        if nm ~= nil then cleanItem.nm = nm end
        if nt ~= nil then cleanItem.nt = nt end
        if d == 1 then cleanItem.d = 1 end
        if a == 1 then cleanItem.a = 1 end
        items[#items + 1] = cleanItem
    end

    local out = {
        v = 1,
        n = n,
        i = items,
    }
    if f ~= nil then out.f = f end
    if r ~= nil then out.r = r end
    if fa ~= nil then out.fa = fa end
    return out
end

function LC.JsonEncode(payload)
    local canonical, err = LC.ValidatePayload(payload)
    if not canonical then return nil, err end

    local parts = { '{"v":1,"n":', EncodeJsonString(canonical.n) }
    if canonical.f ~= nil then
        parts[#parts + 1] = ',"f":'
        parts[#parts + 1] = EncodeJsonString(canonical.f)
    end
    if canonical.r ~= nil then
        parts[#parts + 1] = ',"r":'
        parts[#parts + 1] = EncodeJsonString(canonical.r)
    end
    if canonical.fa ~= nil then
        parts[#parts + 1] = ',"fa":'
        parts[#parts + 1] = EncodeJsonString(canonical.fa)
    end
    parts[#parts + 1] = ',"i":['
    for idx, item in ipairs(canonical.i) do
        if idx > 1 then parts[#parts + 1] = ',' end
        parts[#parts + 1] = '{"id":'
        parts[#parts + 1] = string.format("%.0f", item.id)
        if item.s ~= nil then
            parts[#parts + 1] = ',"s":'
            parts[#parts + 1] = string.format("%.0f", item.s)
        end
        parts[#parts + 1] = ',"q":'
        parts[#parts + 1] = string.format("%.0f", item.q)
        if item.m ~= nil then
            parts[#parts + 1] = ',"m":'
            parts[#parts + 1] = string.format("%.0f", item.m)
        end
        if item.nm ~= nil then
            parts[#parts + 1] = ',"nm":'
            parts[#parts + 1] = EncodeJsonString(item.nm)
        end
        if item.nt ~= nil then
            parts[#parts + 1] = ',"nt":'
            parts[#parts + 1] = EncodeJsonString(item.nt)
        end
        if item.d ~= nil then
            parts[#parts + 1] = ',"d":'
            parts[#parts + 1] = string.format("%.0f", item.d)
        end
        if item.a ~= nil then
            parts[#parts + 1] = ',"a":'
            parts[#parts + 1] = string.format("%.0f", item.a)
        end
        parts[#parts + 1] = '}'
    end
    parts[#parts + 1] = ']}'
    return table.concat(parts)
end

-- ================================================================
-- 4. PUBLIC !MS1! ENCODE / DECODE API
-- ================================================================
function LC.Encode(listData)
    local jsonBytes, err = LC.JsonEncode(listData)
    if not jsonBytes then return nil, err end
    local crcHex = LC.CRC32Hex(jsonBytes)
    local b64 = LC.Base64UrlEncode(jsonBytes)
    return LC.PREFIX .. b64 .. "." .. crcHex
end

function LC.Decode(str)
    if type(str) ~= "string" then
        return nil, "Import string must be a string"
    end
    local trimmed = Trim(str)
    if trimmed:sub(1, #LC.PREFIX) ~= LC.PREFIX then
        return nil, "Missing !MS1! prefix"
    end
    local body = trimmed:sub(#LC.PREFIX + 1)
    local b64, crcHex = body:match("^([^%.]+)%.([^%.]+)$")
    if not b64 or not crcHex then
        return nil, "Malformed !MS1! envelope"
    end
    if not crcHex:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") then
        return nil, "Invalid CRC32 checksum format"
    end
    local jsonBytes, b64Err = LC.Base64UrlDecode(b64)
    if not jsonBytes then
        return nil, b64Err
    end
    if LC.CRC32Hex(jsonBytes) ~= crcHex then
        return nil, "Checksum mismatch"
    end
    local parsed, jsonErr, arrayRefs = LC.JsonDecode(jsonBytes)
    if not parsed then
        return nil, jsonErr
    end
    return LC.ValidatePayload(parsed, arrayRefs)
end

-- ================================================================
-- 5. FAVORITES & NOTIFICATIONS BRIDGE
-- ================================================================
local function RequestItemDataSafe(itemID)
    if MarketSync and MarketSync.RequestItemData then
        pcall(MarketSync.RequestItemData, itemID)
    elseif C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    elseif GetItemInfo then
        pcall(GetItemInfo, itemID)
    end
end

local function ResolveCachedOrLiveName(itemID, itemMeta)
    local name
    if MarketSync and MarketSync.GetItemInfo then
        name = MarketSync.GetItemInfo(itemID)
    elseif C_Item and C_Item.GetItemInfo then
        name = C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        name = GetItemInfo(itemID)
    end
    if (not name or name == "") and MarketSyncDB and MarketSyncDB.ItemInfoCache and MarketSyncDB.ItemInfoCache[itemID] then
        name = MarketSyncDB.ItemInfoCache[itemID].n
    end
    if (not name or name == "") and type(itemMeta) == "table" and type(itemMeta.name) == "string" and itemMeta.name ~= "" then
        name = itemMeta.name
    end
    return name
end

local function IsCraftOwnedList(listName)
    return MarketSync.CraftLedger and MarketSync.CraftLedger.FindShoppingList
        and MarketSync.CraftLedger.FindShoppingList(listName) ~= nil
end

local function FindUniqueRenameTarget(baseName)
    local stem = Trim(baseName)
    if stem == "" then stem = "Imported List" end
    stem = TruncateUtf8Chars(stem, 56)
    local idx = 2
    while true do
        local candidate = stem .. " (" .. idx .. ")"
        local exists = MarketSyncDB and MarketSyncDB.Favorites and MarketSyncDB.Favorites[candidate] ~= nil
        if not exists and not IsCraftOwnedList(candidate) then
            return candidate
        end
        idx = idx + 1
    end
end

local function ParseListEntryRef(rawEntry)
    if type(rawEntry) == "number" then
        return rawEntry, nil
    end
    if type(rawEntry) == "string" then
        local pid, ps = rawEntry:match("^p:(%d+):(%-?%d+)$")
        if pid then
            local sid = tonumber(ps)
            return tonumber(pid), (sid and sid >= 0) and sid or nil
        end
        local num = tonumber(rawEntry)
        if num then
            return num, nil
        end
    end
    return nil, nil
end

function LC.ExportList(listName, options)
    options = options or {}
    listName = Trim(listName or "")
    if listName == "" then
        return nil, "List name is required"
    end
    if not MarketSyncDB or not MarketSyncDB.Favorites or not MarketSyncDB.Favorites[listName] then
        return nil, "Shopping list not found: " .. listName
    end

    local F = MarketSync.Favorites
    local listMeta = (F and F.GetListMeta and F.GetListMeta(listName))
        or (MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName])
        or {}

    local flavor = options.flavor or listMeta.flavor or (MarketSync.GetClientFlavor and MarketSync.GetClientFlavor()) or nil
    if flavor and not LC.VALID_FLAVORS[flavor] then flavor = nil end

    local realm = options.realm or listMeta.realm
        or (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName())
        or nil
    if type(realm) == "string" then
        realm = Trim(realm)
        if realm == "" then
            realm = nil
        elseif CountUtf8Chars(realm) > LC.MAX_REALM_SLUG_LENGTH then
            realm = TruncateUtf8Chars(realm, LC.MAX_REALM_SLUG_LENGTH)
        end
    else
        realm = nil
    end

    local faction = options.faction or listMeta.faction
        or (MarketSync.GetPlayerMarketFaction and MarketSync.GetPlayerMarketFaction())
        or nil
    if faction and not LC.VALID_FACTIONS[faction] then faction = nil end

    local exportName = TruncateUtf8Chars(listName, LC.MAX_LIST_NAME_LENGTH)

    local rawIDs = MarketSyncDB.Favorites[listName]
    local items = {}
    for _, rawEntry in ipairs(rawIDs) do
        local itemID, entrySuffix = ParseListEntryRef(rawEntry)
        if itemID then
            local qty = (MarketSyncDB.FavoriteQuantities and MarketSyncDB.FavoriteQuantities[listName] and MarketSyncDB.FavoriteQuantities[listName][rawEntry])
                or (F and F.GetQuantity and F.GetQuantity(listName, rawEntry))
                or 1
            local im = (MarketSyncDB.FavoriteMeta and MarketSyncDB.FavoriteMeta[listName] and MarketSyncDB.FavoriteMeta[listName].items and MarketSyncDB.FavoriteMeta[listName].items[rawEntry])
                or (F and F.GetItemMeta and F.GetItemMeta(listName, rawEntry))
                or nil
            local nm = ResolveCachedOrLiveName(itemID, im)
            local entry = {
                id = itemID,
                q = math.max(1, math.floor(tonumber(qty) or 1)),
            }
            local s = tonumber((im and im.suffix) or entrySuffix)
            if s and IsFiniteInteger(s) and s > 0 then
                entry.s = s
            end
            if im then
                local m = tonumber(im.maxPrice)
                if m and IsFiniteInteger(m) and m > 0 and m <= LC.MAX_COPPER then
                    entry.m = m
                end
                if type(im.note) == "string" and Trim(im.note) ~= "" then
                    entry.nt = TruncateUtf8Chars(im.note, LC.MAX_ITEM_NOTE_LENGTH)
                end
                if im.done then
                    entry.d = 1
                end
                if im.alert then
                    entry.a = 1
                end
            end
            if type(nm) == "string" then
                nm = Trim(nm)
                if nm ~= "" then
                    entry.nm = TruncateUtf8Chars(nm, LC.MAX_ITEM_NAME_LENGTH)
                end
            end
            items[#items + 1] = entry
        end
    end

    local payload = {
        v = 1,
        n = exportName,
        f = flavor,
        r = realm,
        fa = faction,
        i = items,
    }
    return LC.Encode(payload)
end

function LC.ImportList(str, options)
    options = options or {}
    local decoded, err = LC.Decode(str)
    if not decoded then
        return nil, err
    end
    if not MarketSyncDB then
        return nil, "MarketSyncDB is not initialized"
    end

    local F = MarketSync.Favorites
    if F and F.Initialize then
        F.Initialize()
    else
        MarketSyncDB.Favorites = MarketSyncDB.Favorites or {}
        MarketSyncDB.FavoriteQuantities = MarketSyncDB.FavoriteQuantities or {}
        MarketSyncDB.FavoriteMeta = MarketSyncDB.FavoriteMeta or {}
    end

    local mode = options.mode or "merge"
    if mode ~= "merge" and mode ~= "replace" and mode ~= "rename" then
        return nil, "Invalid import mode: " .. tostring(mode)
    end

    local baseName = Trim(options.targetListName or "")
    if baseName == "" then
        baseName = Trim(decoded.n)
    end
    if baseName == "" then
        return nil, "List name cannot be empty"
    end

    local targetName = baseName
    local exists = MarketSyncDB.Favorites[targetName] ~= nil

    if mode == "rename" then
        if exists or IsCraftOwnedList(targetName) then
            targetName = FindUniqueRenameTarget(baseName)
        end
        if F and F.CreateList then
            local ok, createErr = F.CreateList(targetName)
            if not ok then return nil, createErr end
        else
            MarketSyncDB.Favorites[targetName] = {}
        end
    elseif mode == "replace" then
        if targetName == "Favorites" then
            return nil, "Cannot replace the default Favorites list"
        end
        if IsCraftOwnedList(targetName) then
            return nil, "Cannot replace a craft-linked shopping list"
        end
        if exists then
            MarketSyncDB.Favorites[targetName] = {}
            if MarketSyncDB.FavoriteQuantities then
                MarketSyncDB.FavoriteQuantities[targetName] = nil
            end
            if MarketSyncDB.FavoriteMeta then
                MarketSyncDB.FavoriteMeta[targetName] = nil
            end
        elseif F and F.CreateList then
            local ok, createErr = F.CreateList(targetName)
            if not ok then return nil, createErr end
        else
            MarketSyncDB.Favorites[targetName] = {}
        end
    else -- merge
        if IsCraftOwnedList(targetName) then
            return nil, "Cannot modify a craft-linked shopping list"
        end
        if not exists then
            if F and F.CreateList then
                local ok, createErr = F.CreateList(targetName)
                if not ok then return nil, createErr end
            else
                MarketSyncDB.Favorites[targetName] = {}
            end
        end
    end

    if F and F.SetListMeta then
        F.SetListMeta(targetName, {
            flavor = decoded.f or false,
            realm = decoded.r or false,
            faction = decoded.fa or false,
        })
    end

    local seenInPayload = {}
    local importedCount = 0
    for _, item in ipairs(decoded.i) do
        local id = item.id
        local suffix = tonumber(item.s) or 0
        local qty = math.max(1, math.floor(tonumber(item.q) or 1))
        local payloadKey = tostring(id) .. ":" .. tostring(suffix)
        local prev = seenInPayload[payloadKey]

        if not prev then
            importedCount = importedCount + 1

            local patch = {
                suffix = suffix,
                maxPrice = (item.m ~= nil) and item.m or false,
                note = (type(item.nt) == "string" and item.nt ~= "") and item.nt or false,
                done = (item.d == 1),
                alert = (item.a == 1),
                name = (type(item.nm) == "string" and item.nm ~= "") and item.nm or false,
                quantity = qty,
            }

            local storedKey = id
            if F and F.AddToList then
                local entryRef = (suffix > 0) and string.format("p:%d:%d", id, suffix) or id
                local okAdd, resolvedKey = F.AddToList(targetName, entryRef, patch)
                if okAdd and resolvedKey ~= nil then
                    storedKey = resolvedKey
                end
            else
                local list = MarketSyncDB.Favorites[targetName]
                local numericExists = false
                for _, eid in ipairs(list) do
                    if eid == id then numericExists = true; break end
                end
                if numericExists then
                    storedKey = string.format("p:%d:%d", id, suffix)
                end
                local found = false
                for _, eid in ipairs(list) do
                    if eid == storedKey then found = true; break end
                end
                if not found then list[#list + 1] = storedKey end
                MarketSyncDB.FavoriteQuantities = MarketSyncDB.FavoriteQuantities or {}
                MarketSyncDB.FavoriteQuantities[targetName] = MarketSyncDB.FavoriteQuantities[targetName] or {}
                MarketSyncDB.FavoriteQuantities[targetName][storedKey] = qty
            end

            seenInPayload[payloadKey] = { suffix = suffix, qty = qty, storedKey = storedKey }

            -- Queue uncached item data resolution without polluting ItemInfoCache
            local liveName = ResolveCachedOrLiveName(id, nil)
            if not liveName or liveName == "" then
                RequestItemDataSafe(id)
            end
        else
            prev.qty = prev.qty + qty
            local targetKey = prev.storedKey or id
            if F and F.SetQuantity then
                F.SetQuantity(targetName, targetKey, prev.qty)
            elseif MarketSyncDB.FavoriteQuantities and MarketSyncDB.FavoriteQuantities[targetName] then
                MarketSyncDB.FavoriteQuantities[targetName][targetKey] = prev.qty
            end
        end
    end

    local alertsCreated, alertsSkipped = 0, 0
    if options.createAlerts == true and MarketSync.ImportNotificationRequestsFromDecodedList then
        alertsCreated, alertsSkipped = MarketSync.ImportNotificationRequestsFromDecodedList(decoded, {
            listName = targetName,
            scope = options.scope,
            discountPct = options.discountPct,
            includeDisabledAlerts = options.includeDisabledAlerts,
        })
    end

    return {
        listName = targetName,
        itemCount = importedCount,
        totalEntries = #decoded.i,
        alertsCreated = alertsCreated or 0,
        alertsSkipped = alertsSkipped or 0,
        payload = decoded,
    }
end

MarketSync.EncodeShoppingList = LC.Encode
MarketSync.DecodeShoppingList = LC.Decode
MarketSync.DecodeShoppingListString = LC.Decode
MarketSync.ExportShoppingListString = LC.ExportList
MarketSync.ImportShoppingListString = LC.ImportList

-- ================================================================
-- 6. SHARED IMPORT / EXPORT DIALOG (LAZILY CONSTRUCTED)
-- ================================================================
local listModalFrame

local function SetCheckButtonLabel(cb, text)
    local label = cb.text or cb.Text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.text = label
    end
    label:SetText(text)
end

local function EnsureListModalFrame()
    if listModalFrame then return listModalFrame end
    if type(CreateFrame) ~= "function" or not MarketSync.Theme then return nil end

    local width, height, margin = 620, 460, 18
    local frame = MarketSync.Theme.CreateStandardWindow(
        "MarketSyncListImportExportFrame", "Shopping List", width, height,
        "Interface\\Icons\\INV_Misc_Note_01")

    local headerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -44)
    headerLabel:SetPoint("RIGHT", frame, "RIGHT", -margin, 0)
    headerLabel:SetJustifyH("LEFT")
    frame.headerLabel = headerLabel

    local inset = MarketSync.CreateModernInset(frame)
    frame.inset = inset

    local scroll = CreateFrame("ScrollFrame", "MarketSyncListModalScroll", inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -24, 6)
    frame.scroll = scroll

    local eb = CreateFrame("EditBox", "MarketSyncListModalEditBox", scroll)
    if eb.SetFontObject then eb:SetFontObject("GameFontHighlightSmall") end
    if eb.SetMultiLine then eb:SetMultiLine(true) end
    if eb.SetAutoFocus then eb:SetAutoFocus(false) end
    if eb.SetMaxLetters then eb:SetMaxLetters(0) end
    eb:SetWidth(width - (2 * margin) - 30)
    eb:SetHeight(230)
    eb:SetText("")
    scroll:SetScrollChild(eb)
    frame.editBox = eb

    scroll:HookScript("OnSizeChanged", function(_, w, h)
        if w and w > 0 then eb:SetWidth(w) end
        if h and h > 0 then eb:SetHeight(h) end
    end)

    local function FocusEditBox()
        if eb.SetFocus then eb:SetFocus() end
    end
    if inset.EnableMouse then inset:EnableMouse(true) end
    inset:SetScript("OnMouseDown", FocusEditBox)
    if scroll.EnableMouse then scroll:EnableMouse(true) end
    scroll:SetScript("OnMouseDown", FocusEditBox)

    eb:SetScript("OnEscapePressed", function(self)
        if self.ClearFocus then self:ClearFocus() end
    end)
    frame:HookScript("OnHide", function() eb:ClearFocus() end)

    local optionsBar = MarketSync.CreateModernInset(frame, nil, nil, width - 2 * margin, 66)
    optionsBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", margin, 64)
    function frame.LayoutEditor(showOptions)
        optionsBar:SetShown(showOptions)
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", frame, "TOPLEFT", margin, -69)
        inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -margin, showOptions and 138 or 64)
    end

    local modeLabel = optionsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT", 12, -12)
    modeLabel:SetText("Existing list")

    local selectedMode = "merge"
    local modeChecks = {}
    local modeSpecs = {
        { key = "merge", label = "Merge", x = 104 },
        { key = "replace", label = "Replace", x = 196 },
        { key = "rename", label = "Rename", x = 292 },
    }
    local function SyncModeChecks(newMode)
        selectedMode = newMode
        frame.conflictMode = newMode
        for _, spec in ipairs(modeSpecs) do
            local cb = modeChecks[spec.key]
            if cb and cb.SetChecked then
                cb:SetChecked(spec.key == newMode)
            end
        end
    end
    for _, spec in ipairs(modeSpecs) do
        local cb = CreateFrame("CheckButton", nil, optionsBar, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", spec.x, -8)
        SetCheckButtonLabel(cb, spec.label)
        cb:SetScript("OnClick", function()
            SyncModeChecks(spec.key)
        end)
        modeChecks[spec.key] = cb
    end
    frame.modeChecks = modeChecks
    frame.SetConflictMode = SyncModeChecks
    SyncModeChecks("merge")

    local createAlertsCheck = CreateFrame("CheckButton", nil, optionsBar, "UICheckButtonTemplate")
    createAlertsCheck:SetSize(20, 20)
    createAlertsCheck:SetPoint("TOPLEFT", 10, -35)
    SetCheckButtonLabel(createAlertsCheck, "Create alerts for items with a target price or alert flag")
    if createAlertsCheck.SetChecked then createAlertsCheck:SetChecked(false) end
    frame.createAlertsCheck = createAlertsCheck

    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 44)
    statusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 44)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")
    frame.statusText = statusText

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -margin, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.closeBtn = closeBtn

    local primaryBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    primaryBtn:SetSize(134, 26)
    primaryBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    primaryBtn:SetText("Import List")
    frame.primaryBtn = primaryBtn

    eb:SetScript("OnTextChanged", function(self, userInput)
        if frame._mode == "export" then
            if userInput and frame._exportText ~= nil then
                self:SetText(frame._exportText)
                if self.HighlightText then self:HighlightText() end
            end
            return
        end
        local txt = self:GetText() or ""
        if Trim(txt) == "" then
            statusText:SetText("|cffaaaaaaPaste a !MS1!... shopping list string above.|r")
            return
        end
        local decoded, err = LC.Decode(txt)
        if decoded then
            statusText:SetText(string.format("|cff66ff66Ready: %s (%d item(s))|r", decoded.n, #decoded.i))
        else
            statusText:SetText("|cffff6666" .. tostring(err) .. "|r")
        end
    end)

    primaryBtn:SetScript("OnClick", function()
        if frame._mode == "export" then
            if eb.SetFocus then eb:SetFocus() end
            if eb.HighlightText then eb:HighlightText() end
            statusText:SetText("|cff66ff66Selected all text. Press Ctrl+C to copy.|r")
            return
        end

        local text = eb:GetText() or ""
        if frame._mode == "alerts" then
            local decoded, err = LC.Decode(text)
            if not decoded then
                statusText:SetText("|cffff6666" .. tostring(err) .. "|r")
                return
            end
            frame:Hide()
            if frame._onImportAlerts then
                frame._onImportAlerts(decoded)
            elseif MarketSync.BuildNotificationCandidatesFromDecodedList and MarketSync.ShowBulkAlertImportPopup then
                local candidates = MarketSync.BuildNotificationCandidatesFromDecodedList(decoded)
                MarketSync.ShowBulkAlertImportPopup(decoded.n, candidates, function(count)
                    if frame._onSuccess then frame._onSuccess({ listName = decoded.n, alertsCreated = count }) end
                end)
            end
            return
        end

        local createAlerts = createAlertsCheck.GetChecked and (createAlertsCheck:GetChecked() and true or false) or false
        local res, err = LC.ImportList(text, {
            mode = frame.conflictMode or selectedMode or "merge",
            createAlerts = createAlerts,
        })
        if not res then
            statusText:SetText("|cffff6666" .. tostring(err) .. "|r")
            return
        end
        frame:Hide()
        if frame._onSuccess then
            frame._onSuccess(res)
        end
    end)

    listModalFrame = frame
    return frame
end

function MarketSync.ShowListExportDialog(listName)
    local targetList = Trim(listName or "")
    if targetList == "" then targetList = "Favorites" end
    local encoded, err = LC.ExportList(targetList)
    if not encoded then
        if type(print) == "function" then
            print("|cffff4444[MarketSync]|r Cannot export list '" .. targetList .. "': " .. tostring(err))
        end
        return nil, err
    end

    local frame = EnsureListModalFrame()
    if not frame then return encoded end

    local itemCount = (MarketSyncDB and MarketSyncDB.Favorites and MarketSyncDB.Favorites[targetList] and #MarketSyncDB.Favorites[targetList]) or 0
    frame._mode = "export"
    frame._exportText = encoded
    frame._onSuccess = nil
    frame._onImportAlerts = nil
    if frame.TitleText then frame.TitleText:SetText("Export Shopping List") end
    frame.headerLabel:SetText(string.format("Exporting: |cffffd700%s|r (%d item(s))", targetList, itemCount))
    frame.LayoutEditor(false)
    frame.primaryBtn:SetText("Select All")
    frame.closeBtn:SetText("Close")
    frame.statusText:SetText("|cff66ff66Press Ctrl+C to copy this !MS1! string.|r")
    frame:Show()
    frame.editBox:SetText(encoded)
    if frame.editBox.SetFocus then frame.editBox:SetFocus() end
    if frame.editBox.SetCursorPosition then frame.editBox:SetCursorPosition(0) end
    if frame.editBox.HighlightText then frame.editBox:HighlightText() end
    return frame
end

function MarketSync.ShowListImportDialog(options)
    options = options or {}
    local frame = EnsureListModalFrame()
    if not frame then return nil end

    local mode = options.mode or "import"
    frame._mode = (mode == "alerts") and "alerts" or "import"
    frame._exportText = nil
    frame._onSuccess = options.onSuccess
    frame._onImportAlerts = options.onImportAlerts
    frame.SetConflictMode(options.conflictMode or "merge")

    if frame._mode == "alerts" then
        if frame.TitleText then frame.TitleText:SetText("Import !MS1! Price Alerts") end
        frame.headerLabel:SetText("Paste a |cffffd700!MS1!|r shopping list string to review and create price alerts:")
        frame.LayoutEditor(false)
        frame.primaryBtn:SetText("Review Alerts...")
    else
        if frame.TitleText then frame.TitleText:SetText("Import Shopping List") end
        frame.headerLabel:SetText("Paste a |cffffd700!MS1!|r shopping list string below:")
        frame.LayoutEditor(true)
        if frame.createAlertsCheck and frame.createAlertsCheck.SetChecked then
            frame.createAlertsCheck:SetChecked(options.createAlerts == true)
        end
        frame.primaryBtn:SetText("Import List")
    end

    frame.closeBtn:SetText("Cancel")
    frame.editBox:SetText(options.initialText or "")
    frame:Show()
    if frame.editBox.SetFocus then frame.editBox:SetFocus() end
    if Trim(options.initialText or "") == "" then
        frame.statusText:SetText("|cffaaaaaaPaste a !MS1!... shopping list string above.|r")
    end
    return frame
end
