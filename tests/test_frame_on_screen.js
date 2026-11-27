// Tests for MarketSync.EnsureFrameOnScreen (MarketSync/UI_Main.lua).
// Loads only that function, so the test does not need the whole addon.
const fs = require('fs');
const path = require('path');
const candidateDeps = [
  path.resolve(__dirname, '../node_modules'),
  path.resolve(__dirname, '../../ItemRack-Forever/node_modules'),
];
const deps = candidateDeps.find(p => fs.existsSync(p)) || candidateDeps[0];
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(deps, 'fengari'));

const source = fs.readFileSync(path.join(__dirname, '../MarketSync/UI_Main.lua'), 'utf8');
const fnStart = source.indexOf('function MarketSync.EnsureFrameOnScreen');
if (fnStart < 0) throw new Error('EnsureFrameOnScreen not found in UI_Main.lua');
const fnEnd = source.indexOf('\nend\n', fnStart) + '\nend\n'.length;
const section = source.slice(fnStart, fnEnd);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const prelude = `
  MarketSync = {}
  UIParent = {
    GetWidth = function() return 1920 end,
    GetHeight = function() return 1080 end,
    GetEffectiveScale = function() return 1 end,
  }
  -- Minimal frame: a rectangle that moves when re-anchored to UIParent.
  function MakeFrame(left, bottom, width, height, scale)
    local f = { l = left, b = bottom, w = width, h = height, s = scale or 1 }
    function f:GetLeft() return self.l end
    function f:GetRight() return self.l + self.w end
    function f:GetBottom() return self.b end
    function f:GetTop() return self.b + self.h end
    function f:GetEffectiveScale() return self.s end
    function f:ClearAllPoints() self.cleared = true end
    function f:SetPoint(point, rel, relPoint, x, y)
      self.point = point
      if point == "BOTTOMLEFT" then self.l, self.b = x, y
      elseif point == "CENTER" then
        local sw, sh = 1920 / self.s, 1080 / self.s
        self.l, self.b = (sw - self.w) / 2 + x, (sh - self.h) / 2 + y
      end
    end
    return f
  end
`;
if (lauxlib.luaL_dostring(L, to_luastring(prelude + section)) !== lua.LUA_OK) {
  throw new Error('Failed to load: ' + to_jsstring(lua.lua_tostring(L, -1)));
}

let passed = 0;
function test(name, code) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
    console.error('FAIL ' + name + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
  }
  console.log('PASS ' + name);
  passed++;
}

test('A window fully on screen is left alone', `
  local f = MakeFrame(100, 100, 832, 447)
  assert(MarketSync.EnsureFrameOnScreen(f) == false)
  assert(not f.cleared, "must not re-anchor")
`);

test('A window past the right edge comes back flush with it', `
  local f = MakeFrame(1800, 300, 832, 447)
  assert(MarketSync.EnsureFrameOnScreen(f) == true)
  assert(f:GetRight() == 1920, "right edge " .. f:GetRight())
  assert(f:GetBottom() == 300, "vertical position kept")
`);

test('A window dragged off the top-left corner comes back inside', `
  local f = MakeFrame(-500, 900, 832, 447)
  assert(MarketSync.EnsureFrameOnScreen(f) == true)
  assert(f:GetLeft() == 0, "left edge " .. f:GetLeft())
  assert(f:GetTop() == 1080, "top edge " .. f:GetTop())
`);

test('A window entirely off screen below comes back', `
  local f = MakeFrame(400, -2000, 832, 447)
  assert(MarketSync.EnsureFrameOnScreen(f) == true)
  assert(f:GetBottom() == 0)
`);

test('Scaled windows use their own coordinate space', `
  -- At scale 2 the screen is 960 x 540 in the frame's units.
  local f = MakeFrame(700, 100, 400, 200, 2)
  assert(MarketSync.EnsureFrameOnScreen(f) == true)
  assert(f:GetRight() == 960, "right edge " .. f:GetRight())
`);

test('A window larger than the screen is centered', `
  local f = MakeFrame(-100, -100, 3000, 447)
  assert(MarketSync.EnsureFrameOnScreen(f) == true)
  assert(f.point == "CENTER")
`);

test('A window with no position yet is ignored', `
  local f = MakeFrame(0, 0, 10, 10)
  f.GetLeft = function() return nil end
  assert(MarketSync.EnsureFrameOnScreen(f) == false)
`);

console.log(`All ${passed} on-screen tests passed.`);
