// ============================================================================
// Reusable WoW Addon UI & State Simulator (Node.js + Fengari Lua 5.1)
// Provides the high-value capabilities of wow-ui-sim (layout/anchor solver,
// anchor-cycle detection, A_Admin state/combat/bag/addon-channel controller,
// deterministic timer + OnUpdate clock, and UI interaction helpers) with full
// support for Forever (16001), Classic/Anniversary (20506), Era (11509), and Retail.
// ============================================================================

const fs = require('fs');
const path = require('path');

function resolveNodeModules(baseDir) {
  const candidates = [
    path.resolve(baseDir, 'node_modules'),
    path.resolve(baseDir, '../node_modules'),
    path.resolve(__dirname, '../node_modules'),
  ];
  return candidates.find(p => fs.existsSync(p)) || candidates[0];
}

const deps = resolveNodeModules(__dirname);
const luaparse = require(path.join(deps, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

const SIMULATOR_BOOT_LUA = `
-- ============================================================================
-- WOW UI & ADDON SIMULATOR RUNTIME (Lua 5.1)
-- ============================================================================
_G = _G or {}

A_Admin = {
  flavor = "forever",
  interface = 16001,
  version = "1.60.1",
  build = "70205",
  playerFirst = "Blauto",
  playerSurname = "Theblind",
  realm = "ClassicBetaPvP2",
  faction = "Horde",
  inGuild = true,
  inCombat = false,
  money = 5000000,
  now = 1000,
  unix = 1792550000,
  echoAddonMessages = true,
  bags = { [0] = { slots = 16, items = {} }, [1] = { slots = 16, items = {} }, [2] = { slots = 16, items = {} }, [3] = { slots = 16, items = {} }, [4] = { slots = 16, items = {} } },
  equipped = {},
  itemDB = {
    [555]   = { name = "Bright Ore", quality = 2, iLevel = 20, classID = 7, subClassID = 7, stack = 20, icon = 134566, vendor = 50 },
    [556]   = { name = "Shadow Silk", quality = 2, iLevel = 35, classID = 7, subClassID = 5, stack = 20, icon = 132891, vendor = 125 },
    [13444] = { name = "Major Mana Potion", quality = 1, iLevel = 55, classID = 0, subClassID = 1, stack = 5, icon = 134856, vendor = 300 },
    [13446] = { name = "Major Healing Potion", quality = 1, iLevel = 55, classID = 0, subClassID = 1, stack = 5, icon = 134834, vendor = 250 },
  },
  frames = {},
  namedFrames = {},
  timers = {},
  sentAddonMessages = {},
  lastContextMenu = nil,
  lastStaticPopup = nil,
  taintErrors = {},
}

-- Standard WoW globals & string utilities
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
NUM_BAG_SLOTS = 4
BANK_CONTAINER = -1
ERR_AUCTION_BID_PLACED = "Bid accepted."
ERR_AUCTION_WON_S = "You won an auction for %s"

function strtrim(s)
  return tostring(s or ""):match("^%s*(.-)%s*$")
end

function strsplit(sep, str, pieces)
  sep = tostring(sep or ",")
  str = tostring(str or "")
  local out = {}
  local start = 1
  local sepLen = #sep
  while true do
    if pieces and #out >= pieces - 1 then
      out[#out + 1] = str:sub(start)
      break
    end
    local pos = str:find(sep, start, true)
    if not pos then
      out[#out + 1] = str:sub(start)
      break
    end
    out[#out + 1] = str:sub(start, pos - 1)
    start = pos + sepLen
  end
  return unpack(out)
end

function wipe(tbl)
  if type(tbl) ~= "table" then return {} end
  for k in pairs(tbl) do tbl[k] = nil end
  return tbl
end

function tinsert(t, ...) table.insert(t, ...) end
function tremove(t, ...) return table.remove(t, ...) end
function unpack(t, i, j) return (table.unpack or _G.unpack)(t, i, j) end

function hooksecurefunc(tbl, name, callback)
  if type(tbl) == "string" then
    callback = name
    name = tbl
    tbl = _G
  end
  if type(tbl) ~= "table" or type(callback) ~= "function" then return end
  local orig = tbl[name]
  tbl[name] = function(...)
    local r1, r2, r3, r4 = nil, nil, nil, nil
    if type(orig) == "function" then
      r1, r2, r3, r4 = orig(...)
    end
    callback(...)
    return r1, r2, r3, r4
  end
end

function GetTime() return A_Admin.now end
function time() return A_Admin.unix end
function GetServerTime() return A_Admin.unix end
function date(fmt, ts) return os.date(fmt or "%H:%M:%S", ts or A_Admin.unix) end
function GetBuildInfo() return A_Admin.version, A_Admin.build, "Oct 20 2026", A_Admin.interface end
function GetRealmName() return A_Admin.realm end
function GetNormalizedRealmName() return (A_Admin.realm or ""):gsub("%s+", "") end
function UnitFactionGroup(unit) return A_Admin.faction, A_Admin.faction end
function IsInGuild() return A_Admin.inGuild end
function InCombatLockdown() return A_Admin.inCombat end
function IsLoggedIn() return true end
function GetMoney() return A_Admin.money end
function PlaySound() end
function PlaySoundFile() end

function UnitName(unit)
  if unit == "player" or not unit then
    return A_Admin.playerFirst, nil
  end
  return tostring(unit), nil
end

function UnitFullName(unit)
  if unit == "player" or not unit then
    if A_Admin.flavor == "forever" and A_Admin.playerSurname and A_Admin.playerSurname ~= "" then
      -- On Forever (16001), UnitFullName returns FirstName, Surname!
      return A_Admin.playerFirst, A_Admin.playerSurname
    end
    return A_Admin.playerFirst, GetNormalizedRealmName()
  end
  return tostring(unit), GetNormalizedRealmName()
end

function A_Admin.GetWireSenderIdentity()
  if A_Admin.flavor == "forever" and A_Admin.playerSurname and A_Admin.playerSurname ~= "" then
    return A_Admin.playerFirst .. " " .. A_Admin.playerSurname .. "-" .. GetNormalizedRealmName()
  end
  return A_Admin.playerFirst .. "-" .. GetNormalizedRealmName()
end

-- Protected Function Taint Guard
local function CheckProtectedAction(actionName, frame)
  if A_Admin.inCombat then
    local msg = string.format("ADDON_ACTION_BLOCKED: %s called during InCombatLockdown()", tostring(actionName))
    table.insert(A_Admin.taintErrors, msg)
    error(msg, 2)
  end
end

function ReloadUI()
  CheckProtectedAction("ReloadUI")
end

-- Item & Container APIs
function GetItemInfo(item)
  local id = tonumber(type(item) == "string" and item:match("item:(%d+)") or item)
  local info = id and A_Admin.itemDB[id]
  if not info then return nil end
  local link = string.format("|cff1eff00|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r", id, info.name)
  return info.name, link, info.quality or 1, info.iLevel or 1, 1, "Trade Goods", "Part", info.stack or 20, "", info.icon or 134400, info.vendor or 0, info.classID or 7, info.subClassID or 0
end

function GetItemInfoInstant(item)
  local id = tonumber(type(item) == "string" and item:match("item:(%d+)") or item)
  local info = id and A_Admin.itemDB[id]
  if not id then return nil end
  return id, "Trade Goods", "Part", "", (info and info.icon) or 134400, (info and info.classID) or 7, (info and info.subClassID) or 0
end

C_Item = {
  GetItemInfo = GetItemInfo,
  GetItemInfoInstant = GetItemInfoInstant,
  GetItemIconByID = function(id)
    local info = A_Admin.itemDB[tonumber(id)]
    return (info and info.icon) or 134400
  end,
  RequestLoadItemDataByID = function() end,
}

C_Container = {
  GetContainerNumSlots = function(bag)
    local b = A_Admin.bags[bag]
    return b and b.slots or 0
  end,
  GetContainerItemInfo = function(bag, slot)
    local b = A_Admin.bags[bag]
    local entry = b and b.items and b.items[slot]
    if not entry then return nil end
    local info = A_Admin.itemDB[entry.itemID] or { name = "Item " .. tostring(entry.itemID), quality = 1, icon = 134400 }
    local link = entry.hyperlink or string.format("|cff1eff00|Hitem:%d:0:0:0:0:0:%d:0|h[%s]|h|r", entry.itemID, entry.suffix or 0, info.name)
    return {
      iconFileID = info.icon or 134400,
      stackCount = entry.count or 1,
      isLocked = false,
      quality = info.quality or 1,
      isReadable = false,
      hasLoot = false,
      hyperlink = link,
      isFiltered = false,
      hasNoValue = false,
      itemID = entry.itemID,
      isBound = entry.bound == true,
    }
  end,
  GetContainerItemLink = function(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.hyperlink or nil
  end,
  ContainerIDToInventoryID = function(bag) return 19 + (tonumber(bag) or 1) end,
}

GetContainerNumSlots = C_Container.GetContainerNumSlots
GetContainerItemLink = C_Container.GetContainerItemLink
function GetContainerItemInfo(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info then return nil end
  return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
end

function GetInventoryItemLink(unit, slot)
  local entry = A_Admin.equipped[slot]
  if not entry then return nil end
  local info = A_Admin.itemDB[entry.itemID] or { name = "Item " .. tostring(entry.itemID) }
  return entry.hyperlink or string.format("|cff1eff00|Hitem:%d:0:0:0:0:0:%d:0|h[%s]|h|r", entry.itemID, entry.suffix or 0, info.name)
end

function GetInventoryItemID(unit, slot)
  local entry = A_Admin.equipped[slot]
  return entry and entry.itemID or nil
end

function GetInventoryItemCount(unit, slot)
  local entry = A_Admin.equipped[slot]
  return entry and (entry.count or 1) or 0
end

function GetInventoryItemTexture(unit, slot)
  local entry = A_Admin.equipped[slot]
  local info = entry and A_Admin.itemDB[entry.itemID]
  return (info and info.icon) or 133633
end

-- AddOn Metadata & Chat Channel Bus
C_AddOns = {
  GetAddOnMetadata = function(addon, field)
    if field == "Version" then return A_Admin.addonVersion or "0.9.7-rc4-local10" end
    if field == "Title" then return addon end
    return nil
  end,
}
GetAddOnMetadata = C_AddOns.GetAddOnMetadata

C_ChatInfo = {
  registeredPrefixes = {},
  RegisterAddonMessagePrefix = function(prefix)
    C_ChatInfo.registeredPrefixes[prefix] = true
    return true
  end,
  SendAddonMessage = function(prefix, text, channel, target)
    table.insert(A_Admin.sentAddonMessages, {
      prefix = prefix,
      text = text,
      channel = channel,
      target = target,
      time = A_Admin.now,
    })
    -- Realistic server echo on GUILD / PARTY / RAID / CHANNEL
    if A_Admin.echoAddonMessages and (channel == "GUILD" or channel == "PARTY" or channel == "RAID" or channel == "OFFICER") then
      A_Admin.FireEvent("CHAT_MSG_ADDON", prefix, text, channel, A_Admin.GetWireSenderIdentity())
    end
    return true
  end,
}
RegisterAddonMessagePrefix = C_ChatInfo.RegisterAddonMessagePrefix
SendAddonMessage = C_ChatInfo.SendAddonMessage

-- ============================================================================
-- DETERMINISTIC TIMERS (C_Timer)
-- ============================================================================
C_Timer = {
  After = function(delay, callback)
    local handle = {
      at = A_Admin.now + math.max(0, tonumber(delay) or 0),
      callback = callback,
      cancelled = false,
      Cancel = function(self) self.cancelled = true end,
      IsCancelled = function(self) return self.cancelled end,
    }
    table.insert(A_Admin.timers, handle)
    return handle
  end,
  NewTimer = function(delay, callback)
    return C_Timer.After(delay, callback)
  end,
  NewTicker = function(interval, callback, iterations)
    local step = math.max(0.05, tonumber(interval) or 1)
    local count = 0
    local ticker
    local function scheduleNext()
      C_Timer.After(step, function()
        if ticker.cancelled then return end
        count = count + 1
        callback(ticker)
        if not ticker.cancelled and (not iterations or count < iterations) then
          scheduleNext()
        end
      end)
    end
    ticker = {
      cancelled = false,
      Cancel = function(self) self.cancelled = true end,
      IsCancelled = function(self) return self.cancelled end,
    }
    scheduleNext()
    return ticker
  end,
}

-- ============================================================================
-- LAYOUT ENGINE & WIDGET SYSTEM (With Anchor Cycle Detection & Bounds Solver)
-- ============================================================================
local function DependsOnFrame(source, target, visited)
  if not source or not target then return false end
  if source == target then return true end
  visited = visited or {}
  if visited[source] then return false end
  visited[source] = true
  for _, pt in pairs(source._points or {}) do
    local rel = pt.relativeTo
    if type(rel) == "string" then rel = _G[rel] end
    if rel and DependsOnFrame(rel, target, visited) then
      return true
    end
  end
  return false
end

local function CreateSimWidget(objectType, name, parent, template)
  local w = {
    _type = objectType or "Frame",
    _name = name,
    _parent = parent,
    _template = template,
    _children = {},
    _regions = {},
    _points = {},
    _scripts = {},
    _events = {},
    _attributes = {},
    _width = 0,
    _height = 0,
    _shown = true,
    _enabled = true,
    _checked = false,
    _level = (parent and parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 1,
    _strata = (parent and parent.GetFrameStrata and parent:GetFrameStrata()) or "MEDIUM",
    _text = "",
    _id = 0,
    _alpha = 1,
    _scale = 1,
    _verticalScroll = 0,
    _messages = {},
  }

  if parent and type(parent) == "table" and parent._children then
    if objectType == "Texture" or objectType == "FontString" then
      table.insert(parent._regions, w)
    else
      table.insert(parent._children, w)
    end
  end

  function w:GetObjectType() return self._type end
  function w:IsObjectType(kind)
    if self._type == kind then return true end
    if kind == "Frame" and (self._type == "Button" or self._type == "CheckButton" or self._type == "ScrollFrame" or self._type == "EditBox" or self._type == "Slider" or self._type == "ScrollingMessageFrame") then
      return true
    end
    return false
  end
  function w:GetName() return self._name end
  function w:GetParent() return self._parent end
  function w:SetParent(p) self._parent = p end
  function w:GetChildren() return unpack(self._children) end
  function w:GetRegions() return unpack(self._regions) end

  -- Geometry & Anchor Cycle Guard
  function w:ClearAllPoints()
    self._points = {}
  end
  function w:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
    local rel = relativeTo
    local relPt = relativePoint
    local x, y = xOfs, yOfs
    if type(relativeTo) == "number" then
      x, y = relativeTo, relativePoint
      rel = self._parent or UIParent
      relPt = point
    elseif type(relativePoint) == "number" or relativePoint == nil then
      x, y = relativePoint or 0, xOfs or 0
      relPt = point
      if rel == nil then rel = self._parent or UIParent end
    end
    local resolvedRel = type(rel) == "string" and _G[rel] or rel
    if resolvedRel and DependsOnFrame(resolvedRel, self) then
      error(string.format("Action[SetPoint] failed because[Cannot anchor to a region dependent on it]: %s -> %s",
        tostring(self._name or self._type), tostring(resolvedRel._name or resolvedRel._type)), 2)
    end
    self._points[point or "CENTER"] = {
      point = point or "CENTER",
      relativeTo = resolvedRel or self._parent or UIParent,
      relativePoint = relPt or point or "CENTER",
      x = tonumber(x) or 0,
      y = tonumber(y) or 0,
    }
  end
  function w:SetAllPoints(relativeTo)
    local target = relativeTo or self._parent or UIParent
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
  end
  function w:GetNumPoints()
    local n = 0
    for _ in pairs(self._points) do n = n + 1 end
    return n
  end
  function w:GetPoint(index)
    local i = 0
    for _, pt in pairs(self._points) do
      i = i + 1
      if i == (index or 1) then
        return pt.point, pt.relativeTo, pt.relativePoint, pt.x, pt.y
      end
    end
    return nil
  end
  function w:SetSize(width, height)
    self._width = tonumber(width) or 0
    self._height = tonumber(height) or 0
  end
  function w:SetWidth(width) self._width = tonumber(width) or 0 end
  function w:SetHeight(height) self._height = tonumber(height) or 0 end
  function w:GetWidth()
    if self._width and self._width > 0 then return self._width end
    local tl, br = self._points["TOPLEFT"], self._points["BOTTOMRIGHT"]
    if tl and br and tl.relativeTo and tl.relativeTo == br.relativeTo and tl.relativeTo.GetWidth then
      local pw = tl.relativeTo:GetWidth()
      if pw and pw > 0 then return math.max(0, pw - (tl.x or 0) + (br.x or 0)) end
    end
    return self._width or 0
  end
  function w:GetHeight()
    if self._height and self._height > 0 then return self._height end
    local tl, br = self._points["TOPLEFT"], self._points["BOTTOMRIGHT"]
    if tl and br and tl.relativeTo and tl.relativeTo == br.relativeTo and tl.relativeTo.GetHeight then
      local ph = tl.relativeTo:GetHeight()
      if ph and ph > 0 then return math.max(0, ph + (tl.y or 0) - (br.y or 0)) end
    end
    return self._height or 0
  end
  function w:GetSize() return self:GetWidth(), self:GetHeight() end
  function w:GetLeft() return 0 end
  function w:GetRight() return self:GetWidth() end
  function w:GetTop() return self:GetHeight() end
  function w:GetBottom() return 0 end
  function w:GetCenter() return self:GetWidth() / 2, self:GetHeight() / 2 end
  function w:GetEffectiveScale() return self._scale or 1 end
  function w:SetScale(s) self._scale = tonumber(s) or 1 end
  function w:GetScale() return self._scale or 1 end

  -- Visibility & Lifecycle
  function w:IsShown() return self._shown == true end
  function w:IsVisible()
    if not self._shown then return false end
    local p = self._parent
    while p and p ~= UIParent do
      if p.IsShown and not p:IsShown() then return false end
      p = p._parent
    end
    return true
  end
  function w:SetShown(val)
    local nextState = val and true or false
    local wasShown = self._shown
    self._shown = nextState
    if wasShown ~= nextState then
      local script = self._scripts[nextState and "OnShow" or "OnHide"]
      if script then script(self) end
    end
  end
  function w:Show() self:SetShown(true) end
  function w:Hide() self:SetShown(false) end

  -- Scripts & Events
  function w:SetScript(scriptType, fn)
    if scriptType == "OnKeyDown" then
      self._hasOnKeyDown = fn ~= nil
    end
    self._scripts[scriptType] = fn
  end
  function w:GetScript(scriptType) return self._scripts[scriptType] end
  function w:HookScript(scriptType, fn)
    local prev = self._scripts[scriptType]
    self._scripts[scriptType] = function(...)
      if prev then prev(...) end
      fn(...)
    end
  end
  function w:RegisterEvent(ev) self._events[ev] = true end
  function w:UnregisterEvent(ev) self._events[ev] = nil end
  function w:UnregisterAllEvents() self._events = {} end
  function w:IsEventRegistered(ev) return self._events[ev] == true end

  -- Secure Attributes
  function w:SetAttribute(key, value)
    if self._template and tostring(self._template):find("Secure", 1, true) then
      CheckProtectedAction("SetAttribute", self)
    end
    self._attributes[key] = value
  end
  function w:GetAttribute(key) return self._attributes[key] end

  -- Text, FontStrings & Textures
  function w:CreateFontString(subName, layer, inherits)
    local fs = CreateSimWidget("FontString", subName, self, inherits)
    if subName then _G[subName] = fs end
    return fs
  end
  function w:CreateTexture(subName, layer, inherits)
    local tex = CreateSimWidget("Texture", subName, self, inherits)
    if subName then _G[subName] = tex end
    return tex
  end
  function w:SetText(txt)
    self._text = tostring(txt or "")
    local subText = rawget(self, "Text")
    if type(subText) == "table" and subText ~= self then subText._text = self._text end
    if self._scripts.OnTextChanged then
      self._scripts.OnTextChanged(self, false)
    end
  end
  function w:GetText() return self._text or "" end
  function w:GetStringWidth() return #(tostring(self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end
  function w:GetStringHeight()
    local _, lines = tostring(self._text or ""):gsub("\\n", "")
    return (lines + 1) * 12
  end
  function w:SetTexture(tex) self._texture = tex end
  function w:GetTexture() return self._texture end
  function w:SetColorTexture(r, g, b, a) self._colorTexture = { r, g, b, a } end
  function w:SetVertexColor(r, g, b, a) self._vertexColor = { r, g, b, a } end
  function w:SetTexCoord(...) self._texCoord = { ... } end
  function w:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
  function w:GetNormalTexture()
    if not self._normalTex then self._normalTex = CreateSimWidget("Texture", nil, self) end
    return self._normalTex
  end
  function w:SetNormalTexture(t)
    self:GetNormalTexture():SetTexture(t)
    self._texture = t
  end
  function w:GetHighlightTexture()
    if not self._hlTex then self._hlTex = CreateSimWidget("Texture", nil, self) end
    return self._hlTex
  end
  function w:GetPushedTexture()
    if not self._pushedTex then self._pushedTex = CreateSimWidget("Texture", nil, self) end
    return self._pushedTex
  end

  -- Backdrop
  function w:SetBackdrop(bd) self._backdrop = bd end
  function w:GetBackdrop() return self._backdrop end
  function w:SetBackdropColor(r, g, b, a) self._backdropColor = { r, g, b, a } end
  function w:GetBackdropColor() return unpack(self._backdropColor or { 0, 0, 0, 1 }) end
  function w:SetBackdropBorderColor(r, g, b, a) self._backdropBorderColor = { r, g, b, a } end
  function w:GetBackdropBorderColor() return unpack(self._backdropBorderColor or { 1, 1, 1, 1 }) end

  -- Controls (Button, CheckButton, Slider, ScrollFrame, EditBox, ScrollingMessageFrame)
  function w:SetID(id) self._id = tonumber(id) or 0 end
  function w:GetID() return self._id or 0 end
  function w:SetEnabled(val) self._enabled = val ~= false end
  function w:IsEnabled() return self._enabled ~= false end
  function w:Enable() self._enabled = true end
  function w:Disable() self._enabled = false end
  function w:SetChecked(val) self._checked = val and true or false end
  function w:GetChecked() return self._checked == true end
  function w:Click(btn)
    if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end
  end
  function w:SetFrameLevel(lvl) self._level = tonumber(lvl) or 1 end
  function w:GetFrameLevel() return self._level or 1 end
  function w:SetFrameStrata(st) self._strata = st end
  function w:GetFrameStrata() return self._strata or "MEDIUM" end
  function w:SetAlpha(a) self._alpha = tonumber(a) or 1 end
  function w:GetAlpha() return self._alpha or 1 end

  -- ScrollFrame & ScrollingMessageFrame
  function w:SetScrollChild(child) self._scrollChild = child end
  function w:GetScrollChild() return self._scrollChild end
  function w:SetVerticalScroll(v) self._verticalScroll = tonumber(v) or 0 end
  function w:GetVerticalScroll() return self._verticalScroll or 0 end
  function w:GetVerticalScrollRange()
    local ch = self._scrollChild and self._scrollChild:GetHeight() or 0
    return math.max(0, ch - self:GetHeight())
  end
  function w:UpdateScrollChildRect() end
  function w:AddMessage(msg) table.insert(self._messages, tostring(msg or "")) end
  function w:Clear() self._messages = {} end
  function w:ScrollUp() end
  function w:ScrollDown() end

  -- Slider
  function w:SetMinMaxValues(minV, maxV) self._min, self._max = minV, maxV end
  function w:GetMinMaxValues() return self._min or 0, self._max or 100 end
  function w:SetValue(v)
    self._value = v
    if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
  end
  function w:GetValue() return self._value or 0 end
  function w:SetValueStep(s) self._step = s end
  function w:SetObeyStepOnDrag() end

  -- EditBox
  function w:SetFocus() self._focused = true end
  function w:ClearFocus() self._focused = false end
  function w:HasFocus() return self._focused == true end
  function w:Insert(t) self:SetText(self:GetText() .. tostring(t or "")) end
  function w:HighlightText() end

  -- Template Sub-Widgets (PortraitFrame, OptionsSlider, CheckButton, ScrollBar)
  if template then
    local tmpl = tostring(template)
    if tmpl:find("Portrait", 1, true) or tmpl:find("ButtonFrame", 1, true) then
      w.TitleText = CreateSimWidget("FontString", name and (name .. "TitleText") or nil, w)
      w.TitleContainer = CreateSimWidget("Frame", nil, w)
      w.TitleContainer.TitleText = w.TitleText
      w.CloseButton = CreateSimWidget("Button", name and (name .. "CloseButton") or nil, w)
      w.NineSlice = CreateSimWidget("Frame", nil, w)
      w.portrait = CreateSimWidget("Texture", name and (name .. "Portrait") or nil, w)
      w.PortraitContainer = { portrait = w.portrait }
    end
    if tmpl:find("CheckButton", 1, true) then
      w.text = CreateSimWidget("FontString", name and (name .. "Text") or nil, w)
      w.Text = w.text
    end
    if tmpl:find("Slider", 1, true) then
      w.Low = CreateSimWidget("FontString", name and (name .. "Low") or nil, w)
      w.High = CreateSimWidget("FontString", name and (name .. "High") or nil, w)
      w.Text = CreateSimWidget("FontString", name and (name .. "Text") or nil, w)
    end
    if tmpl:find("ScrollFrame", 1, true) then
      w.ScrollBar = CreateSimWidget("Slider", name and (name .. "ScrollBar") or nil, w)
    end
    if tmpl:find("TabButton", 1, true) or tmpl:find("TabTemplate", 1, true) then
      w.Text = CreateSimWidget("FontString", name and (name .. "Text") or nil, w)
    end
  end

  setmetatable(w, {
    __index = function(self, key)
      if type(key) == "string" and (
        key:match("^Set[A-Z]") or key:match("^Get[A-Z]") or key:match("^Is[A-Z]") or
        key:match("^Has[A-Z]") or key:match("^Can[A-Z]") or key:match("^Enable[A-Z]?") or
        key:match("^Disable[A-Z]?") or key:match("^Register[A-Z]") or key:match("^Unregister[A-Z]") or
        key:match("^Start[A-Z]") or key:match("^Stop[A-Z]") or key:match("^Clear[A-Z]") or
        key:match("^Lock[A-Z]") or key:match("^Unlock[A-Z]")
      ) then
        return function() end
      end
      return nil
    end,
  })

  if name then
    _G[name] = w
    A_Admin.namedFrames[name] = w
  end
  table.insert(A_Admin.frames, w)
  return w
end

UIParent = CreateSimWidget("Frame", "UIParent", nil)
UIParent:SetSize(1920, 1080)

function CreateFrame(kind, name, parent, template)
  return CreateSimWidget(kind, name, parent or UIParent, template)
end

-- GameTooltip Simulator
GameTooltip = CreateSimWidget("Frame", "GameTooltip", UIParent)
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner, anchor)
  self._owner = owner
  self._anchor = anchor
  self.lines = {}
end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:SetText(text, r, g, b)
  self.lines = { { left = tostring(text or ""), r = r, g = g, b = b } }
end
function GameTooltip:AddLine(text, r, g, b, wrap)
  table.insert(self.lines, { left = tostring(text or ""), r = r, g = g, b = b, wrap = wrap })
end
function GameTooltip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
  table.insert(self.lines, { left = tostring(left or ""), right = tostring(right or ""), lr = lr, lg = lg, lb = lb, rr = rr, rg = rg, rb = rb })
end
function GameTooltip:SetItemByID(itemID)
  self.itemID = tonumber(itemID)
  local name, link = GetItemInfo(self.itemID)
  self.itemLink = link
  self:SetText(name or ("Item " .. tostring(itemID)))
end
function GameTooltip:SetHyperlink(link)
  self.itemLink = link
  local id = tonumber(tostring(link or ""):match("item:(%d+)"))
  self.itemID = id
  self:SetText(tostring(link or ""))
end
function GameTooltip:GetItem()
  if not self.itemID then return nil, nil end
  local name, link = GetItemInfo(self.itemID)
  return name, link or self.itemLink or ("item:" .. tostring(self.itemID))
end
function GameTooltip:NumLines() return #self.lines end

-- UIDropDownMenu & EasyMenu Simulator
function UIDropDownMenu_Initialize(frame, initFn, displayMode, level, menuList)
  if not frame then return end
  frame._initFn = initFn
  frame._menuList = menuList
end
function UIDropDownMenu_SetWidth(frame, width) if frame then frame:SetWidth(width) end end
function UIDropDownMenu_SetText(frame, text) if frame then frame._dropdownText = text end end
function UIDropDownMenu_GetText(frame) return frame and frame._dropdownText or "" end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info, level)
  if A_Admin.lastContextMenu then
    table.insert(A_Admin.lastContextMenu, info)
  end
end
function ToggleDropDownMenu(level, value, dropDownFrame)
  A_Admin.lastContextMenu = {}
  if dropDownFrame and dropDownFrame._initFn then
    dropDownFrame._initFn(dropDownFrame, level or 1, dropDownFrame._menuList)
  end
end
function CloseDropDownMenus() end
function EasyMenu(menuList, menuFrame, anchor, x, y, displayMode)
  A_Admin.lastContextMenu = menuList
  if menuFrame then
    UIDropDownMenu_Initialize(menuFrame, function(_, level)
      for _, item in ipairs(menuList or {}) do
        UIDropDownMenu_AddButton(item, level)
      end
    end, displayMode, 1, menuList)
  end
end

-- PanelTemplates & StaticPopup Helpers
function PanelTemplates_SetNumTabs(frame, count) frame.numTabs = count end
function PanelTemplates_SetTab(frame, index) frame.selectedTab = index end
function PanelTemplates_GetSelectedTab(frame) return frame.selectedTab or 1 end
function PanelTemplates_SelectTab(tab) if tab then tab.selected = true end end
function PanelTemplates_DeselectTab(tab) if tab then tab.selected = false end end
function PanelTemplates_TabResize(tab, padding, absoluteSize)
  if tab and absoluteSize then tab:SetWidth(absoluteSize) end
end

function StaticPopup_Show(which, text1, text2, data)
  A_Admin.lastStaticPopup = { which = which, text1 = text1, text2 = text2, data = data, dialog = StaticPopupDialogs[which] }
  return A_Admin.lastStaticPopup
end
function StaticPopup_Hide(which)
  if A_Admin.lastStaticPopup and A_Admin.lastStaticPopup.which == which then
    A_Admin.lastStaticPopup = nil
  end
end

-- ============================================================================
-- A_Admin CONTROL API (State, Combat, Bags, Events, Time & UI Interactions)
-- ============================================================================
function A_Admin.FireEvent(event, ...)
  for _, f in ipairs(A_Admin.frames) do
    if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then
      f._scripts.OnEvent(f, event, ...)
    end
  end
end

function A_Admin.SetInCombat(inCombat)
  local nextState = inCombat and true or false
  if A_Admin.inCombat == nextState then return end
  A_Admin.inCombat = nextState
  A_Admin.FireEvent(nextState and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

function A_Admin.SetBagItem(bag, slot, itemID, count, suffix, bound)
  A_Admin.bags[bag] = A_Admin.bags[bag] or { slots = 16, items = {} }
  if not itemID or (tonumber(count) or 0) <= 0 then
    A_Admin.bags[bag].items[slot] = nil
  else
    A_Admin.bags[bag].items[slot] = {
      itemID = tonumber(itemID),
      count = tonumber(count) or 1,
      suffix = tonumber(suffix) or 0,
      bound = bound == true,
    }
  end
  A_Admin.FireEvent("BAG_UPDATE", bag)
  A_Admin.FireEvent("BAG_UPDATE_DELAYED")
end

function A_Admin.SetEquippedItem(slot, itemID, suffix)
  slot = tonumber(slot)
  if not slot then return end
  if not itemID or tonumber(itemID) <= 0 then
    A_Admin.equipped[slot] = nil
  else
    A_Admin.equipped[slot] = {
      itemID = tonumber(itemID),
      count = 1,
      suffix = tonumber(suffix) or 0,
      bound = true,
    }
  end
  A_Admin.FireEvent("PLAYER_EQUIPMENT_CHANGED", slot, A_Admin.equipped[slot] == nil)
  A_Admin.FireEvent("UNIT_INVENTORY_CHANGED", "player")
end

function A_Admin.CanSwapSlotInCombat(slot)
  slot = tonumber(slot)
  if not A_Admin.inCombat then return true end
  return slot == 16 or slot == 17 or slot == 18
end

function A_Admin.SetMoney(copper)
  A_Admin.money = tonumber(copper) or 0
  A_Admin.FireEvent("PLAYER_MONEY")
end

function A_Admin.AdvanceTime(seconds)
  local delta = math.max(0, tonumber(seconds) or 0)
  local target = A_Admin.now + delta
  local guard = 0
  while true do
    local nextTimer, nextIndex = nil, nil
    for i, t in ipairs(A_Admin.timers) do
      if not t.cancelled and t.at <= target and (not nextTimer or t.at < nextTimer.at) then
        nextTimer, nextIndex = t, i
      end
    end
    if not nextTimer then break end
    table.remove(A_Admin.timers, nextIndex)
    local step = math.max(0, nextTimer.at - A_Admin.now)
    A_Admin.now = nextTimer.at
    A_Admin.unix = A_Admin.unix + math.floor(step)
    guard = guard + 1
    assert(guard < 10000, "A_Admin.AdvanceTime: infinite timer loop detected")
    nextTimer.callback()
  end
  local remaining = math.max(0, target - A_Admin.now)
  A_Admin.now = target
  A_Admin.unix = A_Admin.unix + math.floor(remaining)
  -- Dispatch OnUpdate to visible frames
  for _, f in ipairs(A_Admin.frames) do
    if f._scripts and f._scripts.OnUpdate and f:IsVisible() then
      f._scripts.OnUpdate(f, delta > 0 and delta or 0.016)
    end
  end
end

function A_Admin.Click(frame, button)
  assert(frame, "A_Admin.Click: frame is nil")
  local btn = button or "LeftButton"
  if frame._scripts.OnMouseDown then frame._scripts.OnMouseDown(frame, btn) end
  if frame._scripts.OnMouseUp then frame._scripts.OnMouseUp(frame, btn) end
  if frame._scripts.OnClick then frame._scripts.OnClick(frame, btn) end
end

function A_Admin.RightClick(frame)
  A_Admin.Click(frame, "RightButton")
  return A_Admin.lastContextMenu
end

function A_Admin.Hover(frame)
  assert(frame, "A_Admin.Hover: frame is nil")
  if frame._scripts.OnEnter then frame._scripts.OnEnter(frame) end
  return GameTooltip.lines
end

function A_Admin.PressEscape()
  local closed = 0
  for i = #UISpecialFrames, 1, -1 do
    local name = UISpecialFrames[i]
    local f = name and _G[name]
    if f and f.IsShown and f:IsShown() then
      f:Hide()
      closed = closed + 1
      break
    end
  end
  return closed
end
`;

function createAddonSim(options = {}) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  function run(code, chunkName = 'sim') {
    const status = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(chunkName));
    if (status !== lua.LUA_OK) {
      throw new Error(`Lua syntax error in ${chunkName}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
    }
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      throw new Error(`Lua runtime error in ${chunkName}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
    }
  }

  run(SIMULATOR_BOOT_LUA, 'wow_addon_sim_boot');

  if (options.flavor || options.interface) {
    const flavor = options.flavor || 'forever';
    const iface = options.interface || (flavor === 'forever' ? 16001 : 20506);
    run(`
      A_Admin.flavor = ${JSON.stringify(flavor)}
      A_Admin.interface = ${Number(iface)}
    `, 'sim_options');
  }

  function loadLuaFile(filePath, validateAst = true) {
    const source = fs.readFileSync(filePath, 'utf8');
    if (validateAst) {
      luaparse.parse(source, { luaVersion: '5.1' });
    }
    run(source, path.basename(filePath));
  }

  function loadToc(tocPath, filterFn) {
    const addonDir = path.dirname(tocPath);
    const lines = fs.readFileSync(tocPath, 'utf8').split(/\r?\n/);
    const loaded = [];
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line || line.startsWith('#')) continue;
      if (line.endsWith('.xml')) continue; // Libs.xml handled by lightweight stubs or optional loader
      const normalized = line.replace(/\\/g, '/');
      if (filterFn && !filterFn(normalized)) continue;
      const fullPath = path.join(addonDir, normalized);
      if (fs.existsSync(fullPath)) {
        loadLuaFile(fullPath, true);
        loaded.push(normalized);
      }
    }
    return loaded;
  }

  return { L, run, loadLuaFile, loadToc };
}

module.exports = { createAddonSim };
