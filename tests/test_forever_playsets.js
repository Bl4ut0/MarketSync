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
  MarketSync.myRealm = "ClassicBetaPvP"
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
  receive("ADV;ClassicBetaPvP2;1;1;0.9.7-rc1;123;2;READY")
  assert(peer == "Guild Person" and peerStatus == "Ready", "numbered peer must be discovered")
  peer = nil
  receive("ADV;ClassicBetaPvE2;1;1;0.9.7-rc1;123;2;READY")
  assert(peer == nil, "different playsets must remain isolated")
  receive("PULL;ClassicBetaPvP2;Source-ClassicBetaPvP2;1;123;0;2;0.9.7-rc1")
  assert(pull and pull[2] == "Source-ClassicBetaPvP2", "source routing must retain exact realm")
  pull = nil
  receive("PULL;ClassicBetaPvE2;Source-ClassicBetaPvE2;1;123;0;2;0.9.7-rc1")
  assert(pull == nil)
  receive("BEGIN;session;M;ClassicBetaPvP2;0;1;3f;2;0.9.7-rc1", MarketSync.DATA_PREFIXES[1])
  assert(inbound and inbound[3] == "Guild Person-ClassicBetaPvP2", "BEGIN must accept shared playset")
  inbound = nil
  receive("BEGIN;session;M;ClassicBetaPvE2;0;1;3f;2;0.9.7-rc1", MarketSync.DATA_PREFIXES[1])
  assert(inbound == nil)
  interface = 20506
  receive("ADV;ClassicBetaPvP2;1;1;0.9.7-rc1;123;2;READY")
  assert(peer == nil, "legacy clients must retain exact realm checks")
`);
console.log('PASS Forever playset comparison, peer discovery, PULL and BEGIN routing, and other-client isolation');
