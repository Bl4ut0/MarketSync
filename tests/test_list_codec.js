// ============================================================================
// Test Suite: !MS1! Shopping List Codec, FavoriteMeta, Alerts & UI Integration
// Verifies pure Lua 5.1 ListCodec.lua, JS <-> Lua round-trip parity,
// strict validation, conflict modes, uncached itemID fallback/request,
// UI modals/panels (forever & legacy), and /ms import /ms export slash commands.
// ============================================================================

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const { createAddonSim } = require('./wow_addon_sim');

const ROOT = path.resolve(__dirname, '..');
const ADDON_DIR = path.join(ROOT, 'MarketSync');

const VALID_FLAVORS = new Set(['forever', 'classicEra', 'anniversary', 'classic', 'retail']);
const VALID_FACTIONS = new Set(['Alliance', 'Horde', 'Neutral', 'CrossFaction', 'Commodities']);
const MAX_COPPER = 99999999999;
const MAX_LIST_ITEMS = 1000;
const MAX_REALM_SLUG_LENGTH = 64;
const MAX_ITEM_NAME_LENGTH = 128;
const MAX_ITEM_NOTE_LENGTH = 256;

// Standard IEEE 802.3 CRC-32 (polynomial 0xEDB88320) over raw UTF-8 bytes
const CRC32_TABLE = (() => {
  const tbl = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    tbl[i] = c >>> 0;
  }
  return tbl;
})();

function crc32Hex(buf) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    crc = CRC32_TABLE[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
  }
  return ((crc ^ 0xFFFFFFFF) >>> 0).toString(16).padStart(8, '0');
}

function b64UrlEncode(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function b64UrlDecode(str) {
  if (!/^[A-Za-z0-9\-_]+$/.test(str) || str.length % 4 === 1) {
    throw new Error('Invalid base64url characters');
  }
  const pad = (4 - (str.length % 4)) % 4;
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat(pad);
  return Buffer.from(b64, 'base64');
}

function normalizeAndValidatePayload(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('Payload must be object');
  if (raw.v !== 1) throw new Error('Unsupported schema version');
  if (typeof raw.n !== 'string') throw new Error('Invalid list name');
  const trimmedName = raw.n.trim();
  if (trimmedName.length < 1 || [...trimmedName].length > 64) {
    throw new Error('Invalid list name');
  }
  let f;
  if (raw.f !== undefined && raw.f !== null) {
    if (typeof raw.f !== 'string') throw new Error('Invalid flavor');
    const tf = raw.f.trim();
    if (tf.length > 0) {
      if (!VALID_FLAVORS.has(tf)) throw new Error('Invalid flavor');
      f = tf;
    }
  }
  let r;
  if (raw.r !== undefined && raw.r !== null) {
    if (typeof raw.r !== 'string') throw new Error('Invalid ruleset/realm');
    const tr = raw.r.trim();
    if (tr.length > 0) {
      if ([...tr].length > MAX_REALM_SLUG_LENGTH) throw new Error('Ruleset/realm too long');
      r = tr;
    }
  }
  let fa;
  if (raw.fa !== undefined && raw.fa !== null) {
    if (typeof raw.fa !== 'string') throw new Error('Invalid faction');
    const tfa = raw.fa.trim();
    if (tfa.length > 0) {
      if (!VALID_FACTIONS.has(tfa)) throw new Error('Invalid faction');
      fa = tfa;
    }
  }
  if (!Array.isArray(raw.i)) throw new Error('Items must be array');
  if (raw.i.length > MAX_LIST_ITEMS) throw new Error('Too many items');

  const items = raw.i.map((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error('Invalid item entry');
    if (!Number.isInteger(entry.id) || entry.id <= 0) throw new Error('Invalid item id');
    const q = entry.q === undefined ? 1 : entry.q;
    if (!Number.isInteger(q) || q < 1) throw new Error('Invalid item quantity');
    const out = { id: entry.id };
    if (entry.s !== undefined && entry.s !== null) {
      if (!Number.isInteger(entry.s) || entry.s < 0) throw new Error('Invalid suffix');
      if (entry.s > 0) out.s = entry.s;
    }
    out.q = q;
    if (entry.m !== undefined && entry.m !== null) {
      if (!Number.isInteger(entry.m) || entry.m < 0 || entry.m > MAX_COPPER) throw new Error('Invalid maxPrice');
      if (entry.m > 0) out.m = entry.m;
    }
    if (entry.nm !== undefined && entry.nm !== null) {
      if (typeof entry.nm !== 'string') throw new Error('Invalid fallback name');
      const tnm = entry.nm.trim();
      if (tnm.length > 0) {
        if ([...tnm].length > MAX_ITEM_NAME_LENGTH) throw new Error('Fallback name too long');
        out.nm = tnm;
      }
    }
    if (entry.nt !== undefined && entry.nt !== null) {
      if (typeof entry.nt !== 'string') throw new Error('Invalid note');
      if (entry.nt.trim().length > 0) {
        if ([...entry.nt].length > MAX_ITEM_NOTE_LENGTH) throw new Error('Note too long');
        out.nt = entry.nt;
      }
    }
    if (entry.d !== undefined && entry.d !== null) {
      if (entry.d !== 0 && entry.d !== 1) throw new Error('Invalid done flag');
      if (entry.d === 1) out.d = 1;
    }
    if (entry.a !== undefined && entry.a !== null) {
      if (entry.a !== 0 && entry.a !== 1) throw new Error('Invalid alert flag');
      if (entry.a === 1) out.a = 1;
    }
    return out;
  });

  const canonical = { v: 1, n: trimmedName };
  if (f !== undefined) canonical.f = f;
  if (r !== undefined) canonical.r = r;
  if (fa !== undefined) canonical.fa = fa;
  canonical.i = items;
  return canonical;
}

function encodeListJS(payload) {
  const canonical = normalizeAndValidatePayload(payload);
  const jsonBytes = Buffer.from(JSON.stringify(canonical), 'utf8');
  return `!MS1!${b64UrlEncode(jsonBytes)}.${crc32Hex(jsonBytes)}`;
}

function decodeListJS(str) {
  if (typeof str !== 'string') throw new Error('Input must be string');
  const trimmed = str.trim();
  if (!trimmed.startsWith('!MS1!')) throw new Error('Missing !MS1! prefix');
  const body = trimmed.slice(5);
  const dot = body.indexOf('.');
  if (dot <= 0 || dot !== body.lastIndexOf('.')) throw new Error('Invalid !MS1! structure');
  const b64 = body.slice(0, dot);
  const hex = body.slice(dot + 1);
  if (!/^[0-9a-f]{8}$/.test(hex)) throw new Error('Invalid CRC32 hex');
  const jsonBytes = b64UrlDecode(b64);
  if (crc32Hex(jsonBytes) !== hex) throw new Error('CRC32 mismatch');
  const parsed = JSON.parse(jsonBytes.toString('utf8'));
  return normalizeAndValidatePayload(parsed);
}

function runLua(L, code, name = 'chunk') {
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name));
  if (st !== lua.LUA_OK) {
    throw new Error(`Lua syntax error in ${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(`Lua runtime error in ${name}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
  }
}

function getLuaGlobalString(L, varName) {
  lua.lua_getglobal(L, to_luastring(varName));
  const val = lua.lua_isstring(L, -1) ? to_jsstring(lua.lua_tostring(L, -1)) : null;
  lua.lua_pop(L, 1);
  return val;
}

function setLuaGlobalString(L, varName, str) {
  lua.lua_pushstring(L, to_luastring(str));
  lua.lua_setglobal(L, to_luastring(varName));
}

// ============================================================================
// TEST 1: luaparse Lua 5.1 AST Check on all modified Lua files + TOC entry
// ============================================================================
function test1Lua51AstCheck() {
  const toc = fs.readFileSync(path.join(ADDON_DIR, 'MarketSync.toc'), 'utf8');
  assert(toc.includes('Favorites.lua\nListCodec.lua') || toc.includes('Favorites.lua\r\nListCodec.lua'),
    'MarketSync.toc must register ListCodec.lua immediately after Favorites.lua');

  const files = [
    'ListCodec.lua',
    'Favorites.lua',
    'Config.lua',
    'Notifications.lua',
    'UI_Notifications.lua',
    'UI_AHSidecar.lua',
    'UI_AHScanner.lua',
    'Core.lua',
  ];
  for (const file of files) {
    const src = fs.readFileSync(path.join(ADDON_DIR, file), 'utf8');
    luaparse.parse(src, { luaVersion: '5.1' });
    luaparse.parse(src, { comments: false, scope: true });
  }

  const codecSrc = fs.readFileSync(path.join(ADDON_DIR, 'ListCodec.lua'), 'utf8');
  assert(!/\bbit\s*\./.test(codecSrc) && !/\bbit32\s*\./.test(codecSrc),
    'ListCodec.lua must not use bit or bit32');
  console.log('PASS [Test 1] Lua 5.1 AST syntax & MarketSync.toc registration');
}

// ============================================================================
// TEST 2: Pure Lua 5.1 Isolation (no bit/bit32 globals, no MarketSyncDB)
// ============================================================================
function test2PureLuaIsolation() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const codecSrc = fs.readFileSync(path.join(ADDON_DIR, 'ListCodec.lua'), 'utf8');
  runLua(L, `
    assert(bit == nil and bit32 == nil, "bit/bit32 must not exist")
    assert(MarketSyncDB == nil, "MarketSyncDB must not exist")
  `, 'isolation_precheck');
  runLua(L, codecSrc, 'ListCodec.lua');
  runLua(L, `
    local LC = MarketSync.ListCodec
    assert(type(LC) == "table", "ListCodec missing")
    assert(type(MarketSync.EncodeShoppingList) == "function", "EncodeShoppingList missing")
    assert(type(MarketSync.DecodeShoppingList) == "function", "DecodeShoppingList missing")
    assert(type(MarketSync.ExportShoppingListString) == "function", "ExportShoppingListString missing")
    assert(type(MarketSync.ImportShoppingListString) == "function", "ImportShoppingListString missing")
    assert(LC.CRC32Hex("") == "00000000", "Empty CRC32 mismatch")
    assert(LC.CRC32Hex("123456789") == "cbf43926", "Standard CRC32 vector failed: " .. tostring(LC.CRC32Hex("123456789")))
    assert(LC.Base64UrlEncode("f") == "Zg")
    assert(LC.Base64UrlEncode("fo") == "Zm8")
    assert(LC.Base64UrlEncode("foo") == "Zm9v")
    assert(LC.Base64UrlDecode("Zm9v") == "foo")
    assert(LC.Base64UrlDecode("Zm8") == "fo")
    assert(LC.Base64UrlDecode("Zg") == "f")
  `, 'isolation_vectors');
  console.log('PASS [Test 2] Pure Lua 5.1 standalone load & CRC32/Base64url vectors');
}

// ============================================================================
// TEST 3: Cross-Language Round-Trip Parity (JS <-> Lua) & Edge Cases
// ============================================================================
function test3CrossLanguageRoundTrip() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  runLua(L, fs.readFileSync(path.join(ADDON_DIR, 'ListCodec.lua'), 'utf8'), 'ListCodec.lua');

  const payloads = [
    {
      v: 1,
      n: 'Raid Consumables — 日本語 🧪',
      f: 'forever',
      r: 'pvp',
      fa: 'Horde',
      i: [
        { id: 13444, s: 0, q: 20, m: 99999999999, nm: 'Élixir de puissance', nt: 'Line1\nLine2\t"quote" \\ slash/', d: 0, a: 1 },
        { id: 4371, s: 12, q: 5, m: 0, nm: 'Ctrl\u0001\u001fTest', nt: 'Note: 50% off -> buy!', d: 1, a: 0 },
        { id: 2447, q: 5 },
      ],
    },
    {
      v: 1,
      n: 'Empty List',
      f: 'anniversary',
      r: 'nightslayer',
      fa: 'Neutral',
      i: [],
    },
    {
      v: 1,
      n: 'Retail Commodities',
      f: 'retail',
      fa: 'Commodities',
      i: [
        { id: 190316, q: 200, m: 4294967296, a: 1 },
      ],
    },
  ];

  // Ensure at least one payload has CRC32 with MSB set (>= 0x80000000, first hex char 8..f)
  let highBitPayload = null;
  for (let k = 0; k < 40; k++) {
    const candidate = { v: 1, n: `HighBitProbe-${k}`, f: 'classic', fa: 'CrossFaction', i: [{ id: 1000 + k, q: k + 1 }] };
    const encoded = encodeListJS(candidate);
    const hex = encoded.split('.')[1];
    if (parseInt(hex[0], 16) >= 8) {
      highBitPayload = candidate;
      break;
    }
  }
  assert(highBitPayload, 'Should generate a payload whose CRC32 has MSB >= 0x80000000');
  payloads.push(highBitPayload);

  for (const payload of payloads) {
    const jsEncoded = encodeListJS(payload);
    setLuaGlobalString(L, 'JS_STR', jsEncoded);
    runLua(L, `
      local decoded, err = MarketSync.DecodeShoppingList(JS_STR)
      assert(decoded ~= nil, "Lua failed to decode JS string: " .. tostring(err))
      local reencoded, encErr = MarketSync.EncodeShoppingList(decoded)
      assert(reencoded ~= nil, "Lua failed to re-encode: " .. tostring(encErr))
      LUA_STR = reencoded
    `, 'roundtrip_item');
    const luaReencoded = getLuaGlobalString(L, 'LUA_STR');
    assert.strictEqual(luaReencoded, jsEncoded, 'Lua re-encoded !MS1! string must match JS byte-for-byte');
    const jsDecoded = decodeListJS(luaReencoded);
    assert.deepStrictEqual(jsDecoded, normalizeAndValidatePayload(payload));
  }

  // Test omitted `q` defaulting to 1 on Lua decode and JSON \uXXXX + surrogate pair decode
  const omittedQJson = '{"v":1,"n":"Surrogate \\uD83E\\uDDEA","i":[{"id":13444}]}';
  const omittedQB64 = b64UrlEncode(Buffer.from(omittedQJson, 'utf8'));
  const omittedQCrc = crc32Hex(Buffer.from(omittedQJson, 'utf8'));
  setLuaGlobalString(L, 'SURROGATE_STR', `!MS1!${omittedQB64}.${omittedQCrc}`);
  runLua(L, `
    local d, err = MarketSync.DecodeShoppingList(SURROGATE_STR)
    assert(d ~= nil, "Surrogate decode failed: " .. tostring(err))
    assert(d.n == "Surrogate 🧪", "Surrogate UTF-8 mismatch: " .. tostring(d.n))
    assert(d.i[1].q == 1, "Omitted q must default to 1")
  `, 'surrogate_check');

  console.log('PASS [Test 3] Cross-language JS <-> Lua round-trip parity (UTF-8, escapes, 64-bit copper, high-bit CRC32)');
}

// ============================================================================
// TEST 4: Strict Validation & Rejection (both JS and Lua Decode)
// ============================================================================
function test4StrictValidationRejection() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  runLua(L, fs.readFileSync(path.join(ADDON_DIR, 'ListCodec.lua'), 'utf8'), 'ListCodec.lua');

  function wrapRawJson(jsonStr) {
    const buf = Buffer.from(jsonStr, 'utf8');
    return `!MS1!${b64UrlEncode(buf)}.${crc32Hex(buf)}`;
  }

  const validStr = encodeListJS({ v: 1, n: 'Valid', i: [{ id: 13444, q: 2 }] });
  const [validBody, validHex] = validStr.split('.');
  const flippedHex = (validHex[0] === 'a' ? 'b' : 'a') + validHex.slice(1);

  const invalidInputs = [
    '',
    'MS1!' + validBody.slice(5) + '.' + validHex,
    '!MS2!' + validBody.slice(5) + '.' + validHex,
    validBody, // missing .crc
    validStr + '.extra',
    '!MS1!abc=.12345678',
    '!MS1!ab+c.12345678',
    '!MS1!ab/c.12345678',
    '!MS1!ab c.12345678',
    validBody + '.' + validHex.toUpperCase(),
    validBody + '.' + validHex.slice(0, 7),
    validBody + '.' + flippedHex,
    wrapRawJson('not json'),
    wrapRawJson('[1,2,3]'),
    wrapRawJson('{"v":2,"n":"BadVer","i":[]}'),
    wrapRawJson('{"v":0,"n":"BadVer","i":[]}'),
    wrapRawJson('{"v":1,"n":"","i":[]}'),
    wrapRawJson('{"v":1,"n":"   ","i":[]}'),
    wrapRawJson('{"v":1,"n":"' + 'x'.repeat(65) + '","i":[]}'),
    wrapRawJson('{"v":1,"n":"NoItems"}'),
    wrapRawJson('{"v":1,"n":"ObjItems","i":{}}'),
    wrapRawJson('{"v":1,"n":"BadFlavor","f":"wotlk","i":[]}'),
    wrapRawJson('{"v":1,"n":"BadFaction","fa":"Scourge","i":[]}'),
    wrapRawJson('{"v":1,"n":"BadId0","i":[{"id":0,"q":1}]}'),
    wrapRawJson('{"v":1,"n":"BadIdNeg","i":[{"id":-5,"q":1}]}'),
    wrapRawJson('{"v":1,"n":"BadQ0","i":[{"id":100,"q":0}]}'),
    wrapRawJson('{"v":1,"n":"BadMNeg","i":[{"id":100,"q":1,"m":-1}]}'),
    wrapRawJson('{"v":1,"n":"BadMBig","i":[{"id":100,"q":1,"m":100000000000}]}'),
  ];

  for (const bad of invalidInputs) {
    assert.throws(() => decodeListJS(bad), `JS reference should reject: ${bad}`);
    setLuaGlobalString(L, 'BAD_STR', bad);
    runLua(L, `
      local decoded, err = MarketSync.DecodeShoppingList(BAD_STR)
      assert(decoded == nil and type(err) == "string", "Lua Decode should reject invalid input")
    `, 'reject_check');
  }

  runLua(L, `
    local d, err = MarketSync.DecodeShoppingList(12345)
    assert(d == nil and err ~= nil, "Non-string must be rejected")
  `, 'non_string_check');

  console.log('PASS [Test 4] Strict !MS1! validation & rejection (28 adversarial vectors)');
}

// ============================================================================
// TEST 5: Conflict Modes (merge/replace/rename), FavoriteMeta, Rename & Alerts
// ============================================================================
function test5ConflictModesMetaAndAlerts() {
  const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
  sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Favorites.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'ListCodec.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Notifications.lua'));

  const str = encodeListJS({
    v: 1,
    n: 'Consumables',
    f: 'forever',
    r: 'pvp',
    fa: 'Horde',
    i: [
      { id: 13444, s: 0, q: 20, m: 50000, nm: 'Major Mana Potion', nt: 'raid', d: 0, a: 1 },
      { id: 2447, q: 5, d: 1, a: 0 },
    ],
  });
  setLuaGlobalString(sim.L, 'IMPORT_STR', str);

  sim.run(`
    MarketSync.InitializeDB()
    assert(MarketSync.GetClientFlavor() == "forever", "Expected forever flavor")
    local F = MarketSync.Favorites
    F.AddToList("Consumables", 2447)
    F.SetQuantity("Consumables", 2447, 10)
    F.SetItemMeta("Consumables", 2447, { note = "old note" })

    -- 1. Merge mode: retains existing items without duplicating 2447, adds 13444, updates meta & qty
    local resMerge, errMerge = MarketSync.ImportShoppingListString(IMPORT_STR, { mode = "merge", createAlerts = true })
    assert(resMerge and resMerge.listName == "Consumables", "Merge failed: " .. tostring(errMerge))
    assert(resMerge.alertsCreated == 1, "Expected 1 alert created (a=1, m=50000), got " .. tostring(resMerge.alertsCreated))

    local rawList = F.GetList("Consumables")
    assert(#rawList == 2, "Merge should have 2 unique itemIDs")
    assert(type(rawList[1]) == "number" and type(rawList[2]) == "number", "Favorites must stay numeric array")
    assert(F.GetQuantity("Consumables", 2447) == 5, "Merge should update quantity for 2447")
    assert(F.GetQuantity("Consumables", 13444) == 20, "Merge should set quantity for 13444")
    local m13444 = F.GetItemMeta("Consumables", 13444)
    assert(m13444 and m13444.maxPrice == 50000 and m13444.note == "raid" and m13444.alert == true and m13444.done == false)
    local m2447 = F.GetItemMeta("Consumables", 2447)
    assert(m2447 and m2447.done == true and m2447.note == nil)

    -- Verify NotificationRequest created and triggers alert evaluation
    local realmDB = MarketSync.GetRealmDB()
    local req = realmDB.NotificationRequests["itemID:13444:main"]
    assert(req ~= nil, "Expected NotificationRequest itemID:13444:main")
    assert(req.thresholdCopper == 50000 and req.quantityHint == 20 and req.importSource == "Consumables")
    local fired = MarketSync.EvaluateNotificationsForRecord(13444, 40000, "main", "TestScan")
    assert(fired == 1, "Expected price drop 40000 <= 50000 to fire alert")

    -- 2. Replace mode: clears previous items not in payload
    F.AddToList("Consumables", 555)
    assert(#F.GetList("Consumables") == 3)
    local resReplace = MarketSync.ImportShoppingListString(IMPORT_STR, { mode = "replace" })
    assert(resReplace and resReplace.listName == "Consumables")
    assert(#F.GetList("Consumables") == 2, "Replace should clear 555")
    assert(F.IsItemInList("Consumables", 555) == false)

    -- Protect default Favorites from replace
    local favStr = MarketSync.EncodeShoppingList({ v = 1, n = "Favorites", i = { { id = 555, q = 1 } } })
    local badFav, badErr = MarketSync.ImportShoppingListString(favStr, { mode = "replace" })
    assert(badFav == nil and badErr:find("Favorites"), "Should block replacing Favorites")

    -- Test GetClientFlavor across client versions & Anniversary realms
    assert(MarketSync.GetClientFlavor() == "forever")
    local origBuildInfo, origNormRealm, origScanner = GetBuildInfo, GetNormalizedRealmName, MarketSyncForeverScanner
    MarketSyncForeverScanner = nil
    GetBuildInfo = function() return "12.0.1", "1", "Jan 1", 120001 end
    assert(MarketSync.GetClientFlavor() == "retail")
    GetBuildInfo = function() return "1.15.8", "1", "Jan 1", 11508 end
    GetNormalizedRealmName = function() return "Nightslayer" end
    assert(MarketSync.GetClientFlavor() == "anniversary")
    GetNormalizedRealmName = function() return "Whitemane" end
    assert(MarketSync.GetClientFlavor() == "classicEra")
    GetBuildInfo = function() return "5.5.3", "1", "Jan 1", 50503 end
    assert(MarketSync.GetClientFlavor() == "classic")
    GetBuildInfo, GetNormalizedRealmName, MarketSyncForeverScanner = origBuildInfo, origNormRealm, origScanner

    -- 3. Rename mode: creates Consumables (2) and Consumables (3)
    local resRen2 = MarketSync.ImportShoppingListString(IMPORT_STR, { mode = "rename" })
    assert(resRen2 and resRen2.listName == "Consumables (2)", "Expected Consumables (2), got " .. tostring(resRen2 and resRen2.listName))
    local resRen3 = MarketSync.ImportShoppingListString(IMPORT_STR, { mode = "rename" })
    assert(resRen3 and resRen3.listName == "Consumables (3)")

    -- 4. RenameList / RemoveFromList / DeleteList cleanup on FavoriteMeta
    local okRen = F.RenameList("Consumables (2)", "Raid Prep")
    assert(okRen == true)
    assert(MarketSyncDB.FavoriteMeta["Consumables (2)"] == nil and MarketSyncDB.FavoriteMeta["Raid Prep"] ~= nil)
    assert(F.RemoveFromList("Raid Prep", 13444) == true)
    assert(MarketSyncDB.FavoriteMeta["Raid Prep"].items[13444] == nil, "RemoveFromList must clean item meta")
    assert(F.DeleteList("Raid Prep") == true)
    assert(MarketSyncDB.FavoriteMeta["Raid Prep"] == nil, "DeleteList must clean list meta")
  `, 'test5_modes_meta_alerts');

  console.log('PASS [Test 5] Conflict modes (merge/replace/rename), FavoriteMeta lifecycle & alert triggers');
}

// ============================================================================
// TEST 6: Uncached itemID Queuing & Fallback Name Storage (No ItemInfoCache pollution)
// ============================================================================
function test6UncachedItemFallbackAndQueuing() {
  const sim = createAddonSim({ flavor: 'forever', interface: 16001 });
  sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Favorites.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'ListCodec.lua'));

  const str = encodeListJS({
    v: 1,
    n: 'Uncached Test',
    i: [
      { id: 99999, s: 7, q: 3, m: 12345, nm: 'Web Fallback Elixir', nt: 'Buy before raid', d: 0, a: 1 },
    ],
  });
  setLuaGlobalString(sim.L, 'UNCACHED_STR', str);

  sim.run(`
    MarketSync.InitializeDB()
    local requested = {}
    local origReq = C_Item.RequestLoadItemDataByID
    C_Item.RequestLoadItemDataByID = function(id)
      requested[#requested + 1] = id
      if origReq then origReq(id) end
    end

    local res, err = MarketSync.ImportShoppingListString(UNCACHED_STR, { mode = "merge" })
    assert(res and res.listName == "Uncached Test", "Import failed: " .. tostring(err))
    assert(#requested >= 1 and requested[1] == 99999, "Uncached item 99999 must be queued via RequestLoadItemDataByID")
    assert(MarketSyncDB.ItemInfoCache[99999] == nil, "Must NEVER write partial fallback entry into ItemInfoCache")
    assert(MarketSyncDB.FavoriteMeta["Uncached Test"].items[99999].name == "Web Fallback Elixir")

    local items = MarketSync.Favorites.GetListItems("Uncached Test")
    assert(#items == 1)
    assert(items[1].name == "Web Fallback Elixir", "GetListItems should use meta.name fallback, got " .. tostring(items[1].name))
    assert(items[1].suffix == 7 and items[1].dbKey == "p:99999:7")
    assert(items[1].maxPrice == 12345 and items[1].note == "Buy before raid")

    -- Export back and verify suffix & fallback name survive
    local exported = MarketSync.ExportShoppingListString("Uncached Test")
    LUA_EXPORTED = exported
  `, 'test6_uncached');

  const exported = getLuaGlobalString(sim.L, 'LUA_EXPORTED');
  const decoded = decodeListJS(exported);
  assert.strictEqual(decoded.n, 'Uncached Test');
  assert.strictEqual(decoded.i[0].id, 99999);
  assert.strictEqual(decoded.i[0].s, 7);
  assert.strictEqual(decoded.i[0].q, 3);
  assert.strictEqual(decoded.i[0].m, 12345);
  assert.strictEqual(decoded.i[0].nm, 'Web Fallback Elixir');
  assert.strictEqual(decoded.i[0].nt, 'Buy before raid');
  assert.strictEqual(decoded.i[0].a, 1);

  console.log('PASS [Test 6] Uncached itemID queuing, FavoriteMeta fallback name & ItemInfoCache safety');
}

// ============================================================================
// TEST 7: UI Modal, Sidecar/Scanner/Notifications Buttons & /ms import/export
// ============================================================================
function test7UIAndSlashCommands() {
  for (const flavor of ['forever', 'legacy']) {
    const iface = flavor === 'forever' ? 16001 : 20506;
    const sim = createAddonSim({ flavor, interface: iface });

    sim.run(`
      LibStub = function(name)
        if name == "LibDataBroker-1.1" then
          return { NewDataObject = function(_, _, obj) return obj end }
        elseif name == "LibDBIcon-1.0" then
          return {
            Register = function() end,
            Hide = function() end,
            Show = function() end,
            IsRegistered = function() return false end,
            GetMinimapButton = function()
              return {
                CreateTexture = function()
                  return {
                    SetAllPoints = function() end,
                    SetTexture = function() end,
                    SetBlendMode = function() end,
                    SetAlpha = function() end,
                    Hide = function() end,
                    Show = function() end,
                    IsShown = function() return false end,
                    CreateAnimationGroup = function()
                      return {
                        SetLooping = function() end,
                        CreateAnimation = function()
                          return {
                            SetFromAlpha = function() end,
                            SetToAlpha = function() end,
                            SetDuration = function() end,
                            SetOrder = function() end,
                          }
                        end,
                        Play = function() end,
                        Stop = function() end,
                      }
                    end,
                  }
                end,
              }
            end,
          }
        end
        return {}
      end
      Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
          return { ID = 1, GetID = function() return 1 end }
        end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
      }
      GetGameTime = function() return 12, 0 end
      GetExpansionLevel = function() return 0 end
      IsShiftKeyDown = function() return false end
      IsInInstance = function() return false, "none" end
      GetCursorInfo = function() return nil end
      ClearCursor = function() end
      ITEM_QUALITY_COLORS = {
        [0] = { hex = "|cff9d9d9d" },
        [1] = { hex = "|cffffffff" },
        [2] = { hex = "|cff1eff00" },
        [3] = { hex = "|cff0070dd" },
        [4] = { hex = "|cffa335ee" },
      }
      AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent)
      AuctionFrame:SetSize(832, 447)
    `, 'ui_stubs_' + flavor);

    sim.loadToc(path.join(ADDON_DIR, 'MarketSync.toc'));

    const importStr = encodeListJS({
      v: 1,
      n: 'UI Imported List',
      f: 'forever',
      fa: 'Horde',
      i: [
        { id: 13444, q: 12, m: 60000, nm: 'Major Mana Potion', nt: 'UI test', d: 1, a: 1 },
      ],
    });
    setLuaGlobalString(sim.L, 'UI_IMPORT_STR', importStr);

    sim.run(`
      A_Admin.FireEvent("ADDON_LOADED", "MarketSync")
      MarketSync.InitializeDB()
      MarketSyncDB.UITheme = "${flavor}"

      -- Build UI Panels & verify zero anchor cycles
      local host = CreateFrame("Frame", "TestUIHost_" .. A_Admin.flavor, UIParent)
      host:SetSize(808, 377)
      local scannerPanel = MarketSync.CreateAHScannerPanel(host)
      assert(scannerPanel ~= nil, "Scanner panel failed")
      local notifPanel = MarketSync.CreateNotificationsPanel(host)
      assert(notifPanel ~= nil, "Notifications panel failed")
      local sidecar = MarketSync.CreateAHSidecar(AuctionFrame)
      assert(sidecar ~= nil, "Sidecar failed")

      -- Scanner keeps its existing buttons. The Shopping breakout uses its actions menu.
      local foundImportList, foundExportList, foundNotifImportStr = 0, 0, 0
      for _, f in ipairs(A_Admin.frames) do
        if f._type == "Button" and f._text == "Import..." then foundImportList = foundImportList + 1 end
        if f._type == "Button" and f._text == "Export..." then foundExportList = foundExportList + 1 end
        if f._type == "Button" and f._text == "Import String..." then foundNotifImportStr = foundNotifImportStr + 1 end
      end
      assert(foundImportList == 1 and foundExportList == 1, "Only Scanner should have separate import/export buttons")
      assert(foundNotifImportStr == 1, "Expected Import String... in UI_Notifications, got " .. foundNotifImportStr)

      local ListPicker = MarketSyncSidecarListPicker
      local ScanButton = MarketSyncSidecarListScan
      local ActionsButton = MarketSyncSidecarListActions
      assert(ListPicker and ScanButton and ActionsButton)
      assert(ListPicker:GetParent() == ScanButton:GetParent() and ScanButton:GetParent() == ActionsButton:GetParent())
      assert(ScanButton:GetText() == "Scan" and ListPicker:GetText():find("Favorites"))
      local function FindMenuItem(label)
        for _, entry in ipairs(A_Admin.lastContextMenu) do
          if entry.text == label then return entry end
        end
        error("Missing menu item " .. label)
      end
      local function ListAction(label, value)
        ActionsButton:Click()
        local action = FindMenuItem(label)
        assert(not action.disabled, "Action unexpectedly disabled: " .. label)
        action.func()
        if value then
          local prompt = A_Admin.lastStaticPopup
          prompt.dialog.OnAccept({ editBox = { GetText = function() return value end } })
        end
      end
      ActionsButton:Click()
      assert(FindMenuItem("Delete List").disabled and FindMenuItem("Remove Item...").disabled)
      ListAction("New List...", "Menu list")
      ListAction("Add Item...", "13444")
      assert(MarketSync.AHSidecar.GetSelectedShoppingListName() == "Menu list")
      assert(MarketSync.Favorites.IsItemInList("Menu list", 13444))

      local scanner = MarketSync.Scanner
      local originalScan, originalCancel, originalSearch = scanner.ScanList, scanner.Cancel, MarketSync.OpenLegacySearch
      local calledScan, stopped
      scanner.ScanList = function(name) calledScan = name; scanner.Active = true; scanner.Notify() end
      MarketSync.OpenLegacySearch = function(items)
        assert(items[1].itemID == 13444); calledScan = "Menu list"; scanner.Active = true; scanner.Notify()
      end
      scanner.Cancel = function() stopped = true; scanner.Active = false; scanner.Notify() end
      sidecar:Show()
      ScanButton:Click()
      assert(calledScan == "Menu list" and ScanButton:GetText() == "Stop")
      ScanButton:Click()
      assert(stopped and ScanButton:GetText() == "Scan")
      scanner.ScanList, scanner.Cancel, MarketSync.OpenLegacySearch = originalScan, originalCancel, originalSearch

      ListAction("Export List...")
      local menuExport = MarketSyncListImportExportFrame
      assert(menuExport:IsShown() and menuExport.TitleText:GetText() == "Export Shopping List")
      assert(MarketSync.DecodeShoppingList(menuExport.editBox:GetText()).n == "Menu list")
      local exportHeight = menuExport.inset:GetHeight()
      if MarketSync.IsLegacyUITheme() then
        assert(sidecar._warcraftDecorated and menuExport._marketSyncLegacyAuctionArt.active)
      else
        assert(sidecar._template == "PortraitFrameTemplate" and menuExport._template == "PortraitFrameTemplate")
      end
      menuExport:Hide()
      ListAction("Remove Item...", "13444")
      assert(not MarketSync.Favorites.IsItemInList("Menu list", 13444))
      ListAction("Delete List")
      assert(not MarketSyncDB.Favorites["Menu list"] and MarketSync.AHSidecar.GetSelectedShoppingListName() == "Favorites")

      -- Test /ms export Favorites -> opens modal & populates valid !MS1! string
      MarketSync.Favorites.AddToList("Favorites", 13444)
      SlashCmdList["MarketSync"]("export Favorites")
      local modal = _G["MarketSyncListImportExportFrame"]
      assert(modal and modal:IsShown(), "Modal should open on /ms export")
      assert(not modal._hasOnKeyDown, "Modal must not attach OnKeyDown (taint rule)")
      EXPORTED_BY_SLASH = modal.editBox:GetText()

      -- Test Escape closes modal cleanly even under combat lockdown with 0 taint
      A_Admin.inCombat = true
      local closed = A_Admin.PressEscape()
      assert(closed == 1 and not modal:IsShown(), "UISpecialFrames Escape should close modal")
      assert(#A_Admin.taintErrors == 0, "Expected 0 taint errors")
      A_Admin.inCombat = false

      -- Test Import via modal
      ListAction("Import List...")
      assert(modal:IsShown() and modal.TitleText:GetText() == "Import Shopping List")
      assert(modal.inset:GetHeight() < exportHeight, "Import reserves room for its list options")
      modal.SetConflictMode("merge")
      modal.createAlertsCheck:SetChecked(true)
      modal.editBox:SetText(UI_IMPORT_STR)
      modal.primaryBtn:Click()
      assert(not modal:IsShown(), "Modal should hide after successful import")
      assert(MarketSyncDB.Favorites["UI Imported List"] ~= nil, "Imported list should exist")
      assert(MarketSync.AHSidecar.GetSelectedShoppingListName() == "UI Imported List")

      -- Test /ms import <string> directly
      local directStr = MarketSync.EncodeShoppingList({ v = 1, n = "Slash Direct", i = { { id = 13446, q = 4 } } })
      SlashCmdList["MarketSync"]("  import  " .. directStr .. "  ")
      assert(MarketSyncDB.Favorites["Slash Direct"] ~= nil, "/ms import <str> should create list")
      assert(MarketSync.Favorites.GetQuantity("Slash Direct", 13446) == 4)

      -- Test /ms import (no args) opens modal
      SlashCmdList["MarketSync"]("import")
      assert(modal:IsShown(), "/ms import without args should open import modal")
      modal:Hide()

      -- Test UI_Notifications "Import String..." -> BulkAlertImportFrame with exact_key suffix
      local notifImportBtn
      for _, f in ipairs(A_Admin.frames) do
        if f._type == "Button" and f._text == "Import String..." then notifImportBtn = f; break end
      end
      assert(notifImportBtn ~= nil)
      notifImportBtn:Click()
      assert(modal:IsShown() and modal._mode == "alerts", "Import String... should open modal in alerts mode")
      local suffixAlertStr = MarketSync.EncodeShoppingList({
        v = 1,
        n = "Suffix Alerts",
        fa = "Horde",
        i = { { id = 4471, s = 12, q = 1, m = 95000, nm = "Flintweed Band", a = 1 } },
      })
      modal.editBox:SetText(suffixAlertStr)
      modal.primaryBtn:Click()
      local bulkPopup = _G["MarketSyncBulkAlertImportFrame"]
      assert(bulkPopup and bulkPopup:IsShown(), "Review Alerts... should open MarketSyncBulkAlertImportFrame")
      assert(bulkPopup.items and bulkPopup.items[1].matchType == "dbKey" and bulkPopup.items[1].variantMode == "exact_key")
      -- Click "Import Selected" on bulkPopup and verify exact_key persists
      for _, f in ipairs(A_Admin.frames) do
        if f._parent == bulkPopup and f._type == "Button" and f._text == "Import Selected" then
          f:Click()
          break
        end
      end
      assert(not bulkPopup:IsShown())
      local savedExact = MarketSync.GetRealmDB().NotificationRequests["dbKey:p:4471:12:main"]
      assert(savedExact and savedExact.variantMode == "exact_key" and savedExact.thresholdCopper == 95000)

      -- Test Sidecar UpdateListsView & tooltip hover with metadata (done/maxPrice/note)
      MarketSync.AHSidecar.SelectShoppingList("UI Imported List")
      assert(sidecar ~= nil)
      local hoverRow
      for _, f in ipairs(A_Admin.frames) do
        if f._type == "Button" and f._scripts and f._scripts.OnEnter and f.name and f.name._text
          and f.name._text:find("Major Mana Potion", 1, true) then
          hoverRow = f
          break
        end
      end
      assert(hoverRow ~= nil, "Sidecar list row for the imported item must exist")
      hoverRow._scripts.OnEnter(hoverRow)
      local tipLines = {}
      for _, line in ipairs(GameTooltip.lines) do tipLines[#tipLines + 1] = line.left or "" end
      local tip = table.concat(tipLines, " | ")
      assert(tip:find("Target Max: ", 1, true), "Row tooltip must show the target max price")
      assert(tip:find("Note: UI test", 1, true), "Row tooltip must show the item note")
      assert(tip:find("Status: Done", 1, true), "Row tooltip must show the done status")
    `, 'test7_ui_' + flavor);

    const exportedBySlash = getLuaGlobalString(sim.L, 'EXPORTED_BY_SLASH');
    const decodedSlash = decodeListJS(exportedBySlash);
    assert.strictEqual(decodedSlash.n, 'Favorites');
    assert(decodedSlash.i.some((entry) => entry.id === 13444), 'Exported Favorites must include 13444');
  }

  console.log('PASS [Test 7] Shared modal, UI_AHSidecar, UI_AHScanner, UI_Notifications & /ms import/export (forever + legacy)');
}

test1Lua51AstCheck();
test2PureLuaIsolation();
test3CrossLanguageRoundTrip();
test4StrictValidationRejection();
test5ConflictModesMetaAndAlerts();
test6UncachedItemFallbackAndQueuing();
test7UIAndSlashCommands();

// ============================================================================
// TEST 8: Tier 5 Regressions (UTF-8 truncation, dual Pet Cages, !MS1! parity)
// ============================================================================
function test8Tier5Regressions() {
  const sim = createAddonSim({ flavor: 'classic', interface: 50503 });
  sim.loadLuaFile(path.join(ADDON_DIR, 'Config.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'Favorites.lua'));
  sim.loadLuaFile(path.join(ADDON_DIR, 'ListCodec.lua'));

  // 1. UTF-8 safe truncation on ExportList (>64 chars) and rename (>56 chars)
  const longExportName = 'a'.repeat(63) + 'éé';
  const longRenameBase = 'a'.repeat(55) + 'éé';
  setLuaGlobalString(sim.L, 'LONG_EXPORT_NAME', longExportName);
  setLuaGlobalString(sim.L, 'LONG_RENAME_BASE', longRenameBase);

  const renameWire = encodeListJS({
    v: 1,
    n: longRenameBase,
    i: [{ id: 13464, q: 1 }],
  });
  setLuaGlobalString(sim.L, 'RENAME_WIRE', renameWire);

  // 2. Dual Pet Cages (82800:48212 + 82800:48213 + duplicate 82800:48212)
  const petCageWire = encodeListJS({
    v: 1,
    n: 'Pet Cage Watch',
    f: 'classic',
    r: 'pagle',
    fa: 'CrossFaction',
    i: [
      { id: 82800, s: 48212, q: 1, m: 50000, nm: 'Anubisath Idol' },
      { id: 82800, s: 48213, q: 2, m: 75000, nm: 'Direhorn Runt' },
      { id: 82800, s: 48212, q: 3 },
    ],
  });
  setLuaGlobalString(sim.L, 'PET_CAGE_WIRE', petCageWire);

  // 3. Canonical m=0/s=0/d=0/a=0 & whitespace normalization parity
  const nonCanonicalBuf = Buffer.from(
    JSON.stringify({
      v: 1,
      n: '  Pad  ',
      r: '   ',
      i: [{ id: 13464, s: 0, q: 1, m: 0, nm: '  ', nt: '   ', d: 0, a: 0 }],
    }),
    'utf8',
  );
  const nonCanonicalWire = `!MS1!${b64UrlEncode(nonCanonicalBuf)}.${crc32Hex(nonCanonicalBuf)}`;
  setLuaGlobalString(sim.L, 'NON_CANONICAL_WIRE', nonCanonicalWire);

  // 4. 1001 items & length limits & non-zero base64url trailing bits
  const over1000Buf = Buffer.from(
    JSON.stringify({
      v: 1,
      n: 'TooMany',
      i: Array.from({ length: 1001 }, (_, idx) => ({ id: 1000 + idx, q: 1 })),
    }),
    'utf8',
  );
  const over1000Wire = `!MS1!${b64UrlEncode(over1000Buf)}.${crc32Hex(over1000Buf)}`;
  setLuaGlobalString(sim.L, 'OVER_1000_WIRE', over1000Wire);

  const longRealmBuf = Buffer.from(
    JSON.stringify({ v: 1, n: 'BadRealm', r: 'r'.repeat(65), i: [] }),
    'utf8',
  );
  setLuaGlobalString(sim.L, 'LONG_REALM_WIRE', `!MS1!${b64UrlEncode(longRealmBuf)}.${crc32Hex(longRealmBuf)}`);

  const longNmBuf = Buffer.from(
    JSON.stringify({ v: 1, n: 'BadNm', i: [{ id: 13464, q: 1, nm: 'x'.repeat(129) }] }),
    'utf8',
  );
  setLuaGlobalString(sim.L, 'LONG_NM_WIRE', `!MS1!${b64UrlEncode(longNmBuf)}.${crc32Hex(longNmBuf)}`);

  const longNtBuf = Buffer.from(
    JSON.stringify({ v: 1, n: 'BadNt', i: [{ id: 13464, q: 1, nt: 'y'.repeat(257) }] }),
    'utf8',
  );
  setLuaGlobalString(sim.L, 'LONG_NT_WIRE', `!MS1!${b64UrlEncode(longNtBuf)}.${crc32Hex(longNtBuf)}`);

  sim.run(`
    MarketSync.InitializeDB()
    local F = MarketSync.Favorites
    local LC = MarketSync.ListCodec

    -- Export >64 UTF-8 chars without splitting multibyte sequence
    F.CreateList(LONG_EXPORT_NAME)
    F.AddToList(LONG_EXPORT_NAME, 13464)
    local utf8Exported, utf8Err = LC.ExportList(LONG_EXPORT_NAME)
    assert(utf8Exported ~= nil, "UTF-8 export failed: " .. tostring(utf8Err))
    UTF8_EXPORTED = utf8Exported

    -- Rename >56 UTF-8 chars without splitting multibyte sequence
    local r1 = LC.ImportList(RENAME_WIRE, { mode = "merge" })
    assert(r1 ~= nil)
    local r2, r2Err = LC.ImportList(RENAME_WIRE, { mode = "rename" })
    assert(r2 ~= nil, "UTF-8 rename failed: " .. tostring(r2Err))
    UTF8_RENAMED_NAME = r2.listName

    -- Dual Pet Cages import + quantity merge + export round-trip
    local petRes, petErr = LC.ImportList(PET_CAGE_WIRE, { mode = "replace" })
    assert(petRes ~= nil, "Pet cage import failed: " .. tostring(petErr))
    assert(petRes.itemCount == 2, "Expected 2 distinct pet cages, got " .. tostring(petRes.itemCount))
    assert(#MarketSyncDB.Favorites["Pet Cage Watch"] == 2, "Expected 2 entries in Favorites")
    local petItems = F.GetListItems("Pet Cage Watch")
    assert(#petItems == 2, "Expected 2 items from GetListItems")
    local bySuffix = {}
    for _, it in ipairs(petItems) do bySuffix[it.suffix] = it end
    assert(bySuffix[48212] and bySuffix[48212].quantity == 4, "48212 qty should merge 1 + 3 = 4")
    assert(bySuffix[48213] and bySuffix[48213].quantity == 2, "48213 qty should be 2")
    PET_EXPORTED = LC.ExportList("Pet Cage Watch")

    -- Canonical parity on m:0/s:0/d:0/a:0 & whitespace
    local decNorm = LC.Decode(NON_CANONICAL_WIRE)
    assert(decNorm ~= nil and decNorm.n == "Pad" and decNorm.r == nil)
    assert(decNorm.i[1].s == nil and decNorm.i[1].m == nil and decNorm.i[1].nm == nil and decNorm.i[1].nt == nil and decNorm.i[1].d == nil and decNorm.i[1].a == nil)
    CANONICAL_LUA_WIRE = LC.Encode(decNorm)

    -- Trailing base64url bits, 1001 items, and field length limits rejected
    local b64Bad, b64Err = LC.Decode("!MS1!ab.00000000")
    assert(b64Bad == nil and b64Err ~= nil, "Non-zero trailing base64url bits must be rejected")
    local d1001 = LC.Decode(OVER_1000_WIRE)
    assert(d1001 == nil, "1001 items must be rejected")
    assert(LC.Decode(LONG_REALM_WIRE) == nil, ">64 char realm must be rejected")
    assert(LC.Decode(LONG_NM_WIRE) == nil, ">128 char item name must be rejected")
    assert(LC.Decode(LONG_NT_WIRE) == nil, ">256 char note must be rejected")
  `, 'test8_tier5');

  const utf8Exported = getLuaGlobalString(sim.L, 'UTF8_EXPORTED');
  const decodedUtf8 = decodeListJS(utf8Exported);
  assert.strictEqual(decodedUtf8.n, 'a'.repeat(63) + 'é');

  const renamedName = getLuaGlobalString(sim.L, 'UTF8_RENAMED_NAME');
  assert.strictEqual(renamedName, 'a'.repeat(55) + 'é (2)');

  const petExported = getLuaGlobalString(sim.L, 'PET_EXPORTED');
  const decodedPets = decodeListJS(petExported);
  assert.strictEqual(decodedPets.i.length, 2);
  assert.deepStrictEqual(
    decodedPets.i.map((x) => [x.id, x.s, x.q]).sort((a, b) => a[1] - b[1]),
    [
      [82800, 48212, 4],
      [82800, 48213, 2],
    ],
  );

  const canonicalLuaWire = getLuaGlobalString(sim.L, 'CANONICAL_LUA_WIRE');
  assert.strictEqual(
    canonicalLuaWire,
    encodeListJS({ v: 1, n: 'Pad', i: [{ id: 13464, q: 1 }] }),
  );

  console.log('PASS [Test 8] Tier 5 regressions (UTF-8 truncation, dual Pet Cages, !MS1! parity & limits)');
}

test8Tier5Regressions();
console.log('\nAll 8 ListCodec & Shopping List Import/Export test groups passed!');
