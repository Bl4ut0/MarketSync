const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}
function load(file) { run(fs.readFileSync(path.join(__dirname, '../MarketSync', file), 'utf8')); }
run(`
  interface = 16001
  function GetBuildInfo() return "1.60.1", "70291", "", interface end
  C_ChatInfo = { RegisterAddonMessagePrefix = function() return 0 end }
  function CreateFrame()
    chatFrame = { RegisterEvent = function() end,
      SetScript = function(self, name, fn) self[name] = fn end }
    return chatFrame
  end
  function UnitName() return "Local Person" end
  faction = "Horde"
  function UnitFactionGroup() return faction end
  function IsInGuild() return true end
  function strsplit(separator, value)
    local parts = {}
    for part in (value .. separator):gmatch("(.-)" .. separator) do parts[#parts + 1] = part end
    return table.unpack(parts)
  end
`);
load('Config.lua');
run(`
  for _, base in ipairs({"ClassicBetaPvP", "ClassicBetaPvE", "PvP", "PvE", "RP", "HC"}) do
    assert(MarketSync.IsSameSyncRealm(base, base .. "2"))
    assert(MarketSync.IsSameSyncRealm(base .. "2", base .. "123"))
  end
  assert(not MarketSync.IsSameSyncRealm("PvP2", "PvE2"))
  assert(not MarketSync.IsSameSyncRealm("RP", "HC2"))
  assert(not MarketSync.IsSameSyncRealm("ClassicBetaPvP", "PvP2"))
  assert(not MarketSync.IsSameSyncRealm(nil, nil))
  assert(not MarketSync.IsSameSyncRealm("", ""))
  assert(not MarketSync.IsSameSyncRealm("123", "456"))
  interface = 20506
  assert(not MarketSync.IsSameSyncRealm("PvP", "PvP2"))
  assert(MarketSync.IsSameSyncRealm("Realm2", "Realm2"))
  interface = 120001
  assert(not MarketSync.IsSameSyncRealm("Realm", "Realm2"))
  interface = 16001
  function GetNormalizedRealmName() return "ClassicBetaPvP" end
  function GetRealmName() return "Classic Beta PvP" end
  local oldPrices = { ["100"] = { m = 123 } }
  local recipes = { ["Local Person"] = { recipe = true } }
  MarketSyncDB = { RealmData = { ClassicBetaPvP = {
    PersonalData = oldPrices, KnownCraftingRecipesByCharacter = recipes } } }
  local horde = MarketSync.GetRealmDB()
  assert(next(horde.PersonalData) == nil, "unlabelled prices must not be assigned to a faction")
  assert(horde.KnownCraftingRecipesByCharacter == recipes, "saved recipe knowledge must survive")
  horde.PersonalData["100"] = { m = 400 }
  horde.NeutralData["100"] = { m = 500 }
  horde.NotificationState["100"] = { triggered = true }
  faction = "Alliance"
  local alliance = MarketSync.GetRealmDB()
  assert(alliance ~= horde and next(alliance.PersonalData) == nil)
  assert(next(alliance.NeutralData) == nil and next(alliance.NotificationState) == nil,
    "neutral histories and alerts must not alias another faction's tables")
  alliance.PersonalData["100"] = { m = 900 }
  faction = "Horde"
  assert(MarketSync.GetRealmDB().PersonalData["100"].m == 400, "switching back must restore Horde prices")
  assert(MarketSyncDB.RealmData.ClassicBetaPvP.PersonalData == oldPrices,
    "legacy prices must remain preserved as an archive")
  MarketSync.myRealm = "ClassicBetaPvP"
  assert(MarketSync.GetSyncMarketRealm() == "ClassicBetaPvP@Horde")
  faction = nil
  assert(not MarketSync.IsSameSyncMarketRealm("ClassicBetaPvP2@Horde", MarketSync.myRealm),
    "unknown faction must not accept price data")
  faction = "Horde"
  MarketSync.NotePeerSyncVersion = function() return true, 0 end
  MarketSync.IsPeerDataCompatible = function() return true end
  MarketSync.IsBlocked = function() return false end
  MarketSync.CanParticipateInData = function() return true end
  MarketSync.GetMyLatestBucket = function() return 100 end
  MarketSync.GetRealmDB = function() return {} end
  MarketSync.UpdateSwarmUI = function(name, status) peer, peerStatus = name, status end
  MarketSync.ObserveGuildPull = function(...) pull = {...} end
  MarketSync.AcceptInboundTransfer = function(...) inbound = {...}; return false end
`);
load('Chat.lua');
run(`
  local function receive(message, prefix)
    chatFrame:OnEvent("CHAT_MSG_ADDON", prefix or MarketSync.PREFIX, message,
      "GUILD", "Guild Person-ClassicBetaPvP2")
  end
  receive("ADV;ClassicBetaPvP2@Horde;1;1;0.9.7-rc2;123;2;READY")
  assert(peer == "Guild Person" and peerStatus == "Ready", "numbered peer must be discovered")
  peer = nil
  receive("ADV;ClassicBetaPvP2@Alliance;1;1;0.9.7-rc2;123;2;READY")
  assert(peer == nil, "opposite-faction announcements must not enter the local market")
  receive("NADV;ClassicBetaPvP2@Alliance;1;1;0.9.7-rc2;123;2;READY")
  assert(peer == nil, "neutral announcements must also carry the faction boundary")
  receive("ADV;ClassicBetaPvP2;1;1;0.9.7-rc2;123;2;READY")
  assert(peer == nil, "announcements without an explicit faction must fail closed")
  receive("ADV;ClassicBetaPvE2@Horde;1;1;0.9.7-rc2;123;2;READY")
  assert(peer == nil, "different playsets must remain isolated")
  receive("PULL;ClassicBetaPvP2@Horde;Source-ClassicBetaPvP2;1;123;0;2;0.9.7-rc2")
  assert(pull and pull[2] == "Source-ClassicBetaPvP2", "source routing must retain exact realm")
  pull = nil
  receive("PULL;ClassicBetaPvP2@Alliance;Source-ClassicBetaPvP2;1;123;0;2;0.9.7-rc2")
  assert(pull == nil, "opposite-faction requests must not trigger a broadcast")
  receive("PULL;ClassicBetaPvE2@Horde;Source-ClassicBetaPvE2;1;123;0;2;0.9.7-rc2")
  assert(pull == nil)
  receive("BEGIN;session;M;ClassicBetaPvP2@Horde;0;1;3f;2;0.9.7-rc2", MarketSync.DATA_PREFIXES[1])
  assert(inbound and inbound[3] == "Guild Person-ClassicBetaPvP2", "BEGIN must accept shared playset")
  inbound = nil
  receive("BEGIN;session;M;ClassicBetaPvP2@Alliance;0;1;3f;2;0.9.7-rc2", MarketSync.DATA_PREFIXES[1])
  assert(inbound == nil, "opposite-faction BEGIN must never create a receiving session")
  receive("BEGIN;session;M;ClassicBetaPvE2@Horde;0;1;3f;2;0.9.7-rc2", MarketSync.DATA_PREFIXES[1])
  assert(inbound == nil)
  interface = 20506
  receive("ADV;ClassicBetaPvP2@Horde;1;1;0.9.7-rc2;123;2;READY")
  assert(peer == nil, "legacy clients must retain exact realm checks")
`);
console.log('PASS Forever playset comparison, peer discovery, PULL and BEGIN routing, and other-client isolation');
