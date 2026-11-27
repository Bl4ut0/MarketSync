const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');
const addon = path.join(__dirname, '../MarketSync');

for (const flavor of ['legacy', 'forever']) {
  const sim = createAddonSim({ flavor });
  for (const file of ['Config.lua', 'Theme.lua']) sim.loadLuaFile(path.join(addon, file));
  sim.run(String.raw`
    MarketSync.InitializeDB()
    MarketSyncDB.UITheme = 'legacy'
    -- Capture draw layers: a footer on OVERLAY used to obscure panel content.
    local create = CreateFrame
    function CreateFrame(...)
      local frame = create(...)
      local texture = frame.CreateTexture
      function frame:CreateTexture(name, layer, template, sublevel)
        local region = texture(self, name, layer, template, sublevel)
        region.drawLayer, region.drawSublevel = layer, sublevel
        return region
      end
      return frame
    end
    local root = CreateFrame('Frame', 'LegacyAuctionTest', UIParent, 'BackdropTemplate')
    root:SetSize(832, 447)
    root:SetBackdrop({bgFile='fallback'})
    assert(MarketSync.Theme.ApplyLegacyAuctionFrame(root))
    local art = root._marketSyncLegacyAuctionArt
    local p = art.pieces
    local prefix = 'Interface\\AuctionFrame\\UI-AuctionFrame-Browse-'
    for name, suffix in pairs({topLeft='TopLeft', top='Top', topRight='TopRight',
        bottomLeft='BotLeft', bottom='Bot', bottomRight='BotRight'}) do
      assert(p[name]:GetTexture() == prefix..suffix, 'Original archive texture: '..name)
      assert(p[name].drawLayer == 'ARTWORK' and p[name].drawSublevel < 0)
    end
    assert(not root:GetBackdrop(), 'Remove the flat backdrop behind original artwork')
    assert(p.topLeft:GetWidth()==256 and p.topLeft:GetHeight()==256)
    assert(p.top:GetWidth()==320 and p.top:GetHeight()==256)
    assert(p.bottom:GetWidth()==320 and p.bottom:GetHeight()==191)
    assert(p.bottom._texCoord[4]==191/256, 'Crop the padded bottom texture to the archived height')
    assert(not p.fill:IsShown(), 'No extra strip on the original 832x447 frame')
    assert(p.footerCover.drawLayer=='ARTWORK' and p.footerCover.drawSublevel<0)
    local _, relative, _, x, y = p.footerCover:GetPoint()
    assert(relative==root and x==-5 and y==0, 'Keep clean footer patch on the bottom edge')
    local count = #{root:GetRegions()}
    MarketSync.Theme.Register(root)
    root:Hide(); root:Show(); A_Admin.AdvanceTime(0.1)
    MarketSync.Theme.Apply(root)
    assert(not root:GetBackdrop() and p.topLeft:GetTexture()==prefix..'TopLeft', 'Theme walk preserves the shell')
    assert(MarketSync.Theme.ApplyLegacyAuctionFrame(root) and #{root:GetRegions()}==count, 'Reuse artwork on refresh')
    root:SetSize(1060,660); root:GetScript('OnSizeChanged')(root)
    assert(p.topLeft:GetWidth()==256 and p.topLeft:GetHeight()==256, 'Portrait corner must not stretch')
    assert(p.bottomRight:GetHeight()==191 and p.top:GetWidth()==548)
    assert(p.fill:IsShown() and p.fill:GetHeight()==213, 'Extend only the middle on taller windows')
    root:SetSize(400,300); root:GetScript('OnSizeChanged')(root)
    assert(not art.active and not p.topLeft:IsShown() and root:GetBackdrop(), 'Small windows use a complete fallback')
    root:SetSize(832,447); root:GetScript('OnSizeChanged')(root)
    assert(art.active and p.topLeft:IsShown() and not root:GetBackdrop())

    local dialog = MarketSync.CreateModernDialog('LegacyWideDialogTest',680,560,'Test monitor','icon')
    assert(dialog._marketSyncLegacyAuctionArt.active and dialog.portrait and dialog.TitleText:GetText()=='Test monitor')
    assert(not dialog.warcraftTitleBg and not dialog.warcraftRing, 'No second banner or portrait ring over AH art')
    dialog:Show(); MarketSync.Theme.Apply(dialog)
    assert(not dialog:GetBackdrop(), 'Dialog show must not restore the grey background')
    local small = MarketSync.CreateModernDialog('LegacySmallDialogTest',400,300,'Small dialog')
    small:Show()
    assert(not small._marketSyncLegacyAuctionArt and small:GetBackdrop())
    local r,g,b = small:GetBackdropColor()
    assert(r>g and g>b, 'Small dialog keeps the warm textured Classic palette')

    local missing = CreateFrame('Frame',nil,UIParent,'BackdropTemplate')
    missing:SetSize(832,447); missing:SetBackdrop({bgFile='fallback'})
    local original = missing.CreateTexture
    function missing:CreateTexture(...)
      local texture = original(self,...)
      local set = texture.SetTexture
      function texture:SetTexture(file)
        if file==prefix..'BotRight' then return false end
        set(self,file)
      end
      return texture
    end
    assert(not MarketSync.Theme.ApplyLegacyAuctionFrame(missing) and missing:GetBackdrop().bgFile=='fallback')
    for _, texture in pairs(missing._marketSyncLegacyAuctionArt.pieces) do
      assert(not texture:IsShown(), 'Missing art must never leave a partial shell')
    end
    MarketSyncDB.UITheme='forever'
    local modern = MarketSync.CreateModernDialog('ModernThemeIsolationTest',680,560,'Modern')
    modern:Show()
    assert(not modern._marketSyncLegacyAuctionArt and modern.warcraftRing and modern.warcraftTitleBg)
    local mr,mg,mb=modern:GetBackdropColor()
    assert(mr==0.05 and mg==0.045 and mb==0.04, 'Preserve existing Forever dialog styling')
  `, `legacyArtwork_${flavor}`);
}
const windows = createAddonSim({ flavor: 'legacy' });
for (const file of ['Config.lua', 'Theme.lua', 'Favorites.lua', '../MarketSyncLedger/CraftLedger.lua',
  '../MarketSyncLedger/PurchaseList.lua', '../MarketSyncLedger/ItemLedger.lua', '../MarketSyncLedger/UI_CraftManager.lua',
  '../MarketSyncLedger/UI_ItemLedger.lua', 'UI_Main.lua']) windows.loadLuaFile(path.join(addon, file));
windows.run(String.raw`
  MarketSync.InitializeDB()
  MarketSyncDB.UITheme='legacy'
  MarketSyncDB.EnableLedgerBeta=true
  local create=CreateFrame
  function CreateFrame(...)
    local frame=create(...)
    frame.CreateMaskTexture=frame.CreateTexture
    local texture=frame.CreateTexture
    function frame:CreateTexture(...)
      local region=texture(self,...)
      function region:AddMaskTexture(mask) self.mask=mask end
      return region
    end
    return frame
  end
  SetPortraitTexture=function(texture,unit) texture:SetTexture('portrait:'..unit) end
  -- Content is outside this shell test; use a minimal browse-panel fixture.
  MarketSync.CreateBrowsePanel=function(parent) return CreateFrame('Frame',nil,parent) end
  local main=MarketSync.CreateMainFrame()
  MarketSync.OpenCraftManager()
  local craft=MarketSyncCraftManager
  local ledger=MarketSync.OpenItemLedger()
  for _, frame in ipairs({main,craft,ledger}) do
    assert(frame._marketSyncLegacyAuctionArt and frame._marketSyncLegacyAuctionArt.active,
      'Real window constructor must opt into original Auction House artwork: '..frame:GetName())
    MarketSync.Theme.Apply(frame)
    assert(not frame:GetBackdrop(), 'Shared styling preserves real window art')
  end
  assert(main.tabs[1]._template=='CharacterFrameTabButtonTemplate', 'Preserve archived bottom tabs')
`, 'legacyWindowConstructors');
console.log('PASS original Auction House artwork, safe layers, adaptive sizing, missing-asset fallback, and theme isolation');
