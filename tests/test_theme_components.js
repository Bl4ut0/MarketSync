const path = require('path');
const { createAddonSim } = require('./wow_addon_sim');

for (const theme of ['legacy', 'forever']) {
  const sim = createAddonSim({ flavor: theme });
  sim.loadToc(path.resolve(__dirname, '../MarketSync/MarketSync.toc'), file => file !== 'Core.lua');
  sim.run(`
    MarketSync.InitializeDB()
    MarketSyncDB.UITheme='${theme}'
    MarketSync.Favorites.CreateList('Theme test')
    MarketSync.Favorites.AddToList('Theme test',1001)
    host=CreateFrame('Frame',nil,UIParent); host:SetSize(832,500)
    native=CreateFrame('Frame',nil,host,'BackdropTemplate')
    native:SetBackdrop({bgFile='native-client-art'});native:SetBackdropColor(0.8,0.4,0.2,1)
    pages={}
    function Find(frame,predicate)
      if predicate(frame) then return frame end
      for _, child in ipairs({frame:GetChildren()}) do
        local result=Find(child,predicate);if result then return result end
      end
    end
  `);
  for (const fn of ['CreateBrowsePanel', 'CreateAnalyticsPanel', 'CreateProcessingPanel',
    'CreateNotificationsPanel', 'CreateItemHistoryPanel', 'CreateItemDetailPanel',
    'CreateAHScannerPanel', 'CreateLegacySearchPanel', 'CreateAHSidecar']) {
    sim.run(`
      local page=MarketSync.${fn}(host,'personal')
      pages.${fn}=page
      page:Hide();page:Show();if page.OnShow then page:OnShow() end;MarketSync.Theme.Apply(page)
    `, `${theme}_${fn}`);
  }
  sim.run(String.raw`
    local legacy=MarketSync.IsLegacyUITheme()
    local browse = pages.CreateBrowsePanel
    local function HasRowHover(row, native)
      for _, region in ipairs({row:GetRegions()}) do
        if native then
          local color = region._colorTexture
          if color and color[3] > color[1] then return true end
        elseif region.GetTexture and region:GetTexture() == 'Interface\\HelpFrame\\HelpFrameButton-Highlight' then
          return true
        end
      end
    end
    local processingRow = pages.CreateProcessingPanel.resultRows[1]
    assert(HasRowHover(browse.resultRows[1], not legacy))
    assert(HasRowHover(processingRow, not legacy))
    if legacy then
      assert(processingRow.selectedBg:GetTexture() == 'Interface\\QuestFrame\\UI-QuestLogTitleHighlight')
      MarketSyncDB.UITheme = 'forever'
      assert(not MarketSync.CreateForeverAuctionRowHighlight(browse.resultRows[1]),
        'The native highlight is gated on the Forever client')
      MarketSyncDB.UITheme = 'legacy'
    else
      assert(not HasRowHover(browse.resultRows[1], false) and not HasRowHover(processingRow, false))
      assert(processingRow.selectedBg._colorTexture[3] > processingRow.selectedBg._colorTexture[1])
      local savedTextureAPI = C_Texture
      C_Texture = { GetAtlasInfo = function() return {} end }
      local atlasProbe = {
        CreateTexture = function()
          return {
            SetAllPoints = function() end,
            SetAtlas = function(texture, atlas) texture.atlas = atlas end,
            SetBlendMode = function() end,
          }
        end,
      }
      assert(MarketSync.CreateForeverAuctionRowHighlight(atlasProbe).atlas == 'auctionhouse-ui-row-highlight')
      assert(MarketSync.CreateForeverAuctionRowHighlight(atlasProbe, true).atlas == 'auctionhouse-ui-row-select')
      C_Texture = savedTextureAPI
    end
    browse:RebuildFilters()
    local category = browse.filterButtons[1]
    local filter = Find(browse, function(frame)
        return frame:IsObjectType('Button') and frame:GetText() == 'Filter'
    end)
    assert(category.NormalTexture:GetTexture() == 'Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg')
    if legacy then
      assert(browse.searchBox._template == 'InputBoxTemplate' and browse.tableInset:GetBackdrop())
      assert(filter._template == 'UIPanelButtonTemplate')
    else
      local function HasTexture(frame, texture)
        for _, region in ipairs({frame:GetRegions()}) do
          if region.GetTexture and region:GetTexture() == texture then return true end
        end
      end
      assert(browse.searchBox._template == 'SearchBoxTemplate' and filter._template == 'UIMenuButtonStretchTemplate')
      assert(browse.categoryInset._template == 'InsetFrameTemplate'
        and HasTexture(browse.categoryInset, 'Interface\\QuestFrame\\UI-TextBackground-BackdropBackground'))
      assert(browse.tableInset._template == 'InsetFrameTemplate'
        and HasTexture(browse.tableInset, 'Interface\\FrameGeneral\\UI-Background-Marble'))
      assert(browse.headerButtons[1]._template == 'ColumnDisplayButtonShortTemplate'
        and browse.headerButtons[1]:GetScript('OnClick'))
      category:SetSelected(true)
      assert(category.NormalTexture:IsShown() and category.SelectedTexture:IsShown(),
        'Selected native categories keep their button artwork beneath the highlight')
      category:SetSelected(false)
      AuctionHouseFilterButton_SetUp = function(button, info)
        button.NormalTexture = button.NormalTexture or button:CreateTexture()
        button.SelectedTexture = button.SelectedTexture or button:CreateTexture()
        button:SetText(info.name)
        button.SelectedTexture:SetShown(info.selected)
      end
      browse:RebuildFilters()
      local nativeCategory = browse.filterButtons[1]
      assert(nativeCategory._template == 'AuctionCategoryButtonTemplate' and nativeCategory:GetText() == 'Weapons')
      browse:RebuildFilters()
      assert(browse.filterButtons[1] == nativeCategory and nativeCategory:IsShown(), 'Native category buttons are reused')
      AuctionHouseFilterButton_SetUp = nil
      local alerts = pages.CreateNotificationsPanel
      local historyTab = Find(alerts, function(frame)
        return frame:IsObjectType('Button') and frame:GetText() == 'Alert History'
      end)
      assert(historyTab._template == 'PanelTopTabButtonTemplate')
      A_Admin.Click(historyTab)
      assert(alerts.currentView == 'history')
    end
    A_Admin.Click(filter)
    local filterPopup = Find(browse, function(frame)
      local relative = select(2, frame:GetPoint())
      return relative == filter and frame:GetWidth() == 205
    end)
    assert(filterPopup and filterPopup:IsShown(), 'The filter still opens the MarketSync options')
    A_Admin.Click(filter)
    local sidecar = pages.CreateAHSidecar
    local tabs = {}
    for _, child in ipairs({ sidecar:GetChildren() }) do
      if child.label then tabs[MarketSync.StripColorCodes(child.label:GetText())] = child end
    end
    local shopping, craft, bags = tabs.Shopping, tabs.Craft, tabs.Bags
    local _, relative, _, tabLeft, tabY = shopping:GetPoint()
    assert(relative == sidecar and tabLeft >= 62 and tabY > -56, 'Tabs sit beside the portrait, beneath the title')
    assert(shopping:GetWidth() == craft:GetWidth() and craft:GetWidth() == bags:GetWidth())
    assert(tabLeft + shopping:GetWidth() * 3 + 8 <= sidecar:GetWidth() - 10)
    local shoppingContent = MarketSyncSidecarListPicker:GetParent():GetParent()
    local _, contentRelative, _, contentLeft = shoppingContent:GetPoint(1)
    if contentRelative == sidecar and shoppingContent:GetNumPoints() == 2 then
      assert(contentLeft == 8 or contentLeft == -6, 'Shopping content spans the frame under the portrait')
    end
    local bagItem = { itemID = 1001, icon = 134400, stackCount = 3, quality = 2, name = 'Bag item', bag = 0, slot = 1 }
    local scanBags = MarketSync.AHSidecar.ScanBagsForSelling
    MarketSync.AHSidecar.ScanBagsForSelling = function()
      return { { name = 'Backpack', icon = 130716, totalSlots = 16, items = { bagItem } } }
    end
    A_Admin.Click(bags)
    local slot = Find(sidecar, function(widget) return widget.item == bagItem end)
    assert(slot and slot.icon:GetTexture() == bagItem.icon and slot.count:GetText() == '3')
    assert(slot:GetBackdrop().edgeFile, 'Bag slot keeps its item quality border')
    for _, region in ipairs({ slot:GetRegions() }) do
      assert(not region.GetTexture or region:GetTexture() ~= 'Interface\\Buttons\\UI-Quickslot2',
        'The bag icon has no second action-slot overlay')
    end
    MarketSync.AHSidecar.ScanBagsForSelling = scanBags
    A_Admin.Click(shopping)

    local pager=MarketSync.CreateModernTableScrollBar(host,host,function(page) changed=page end)
    pager:Update(1,3)
    A_Admin.Click(pager.downBtn)
    assert(changed==2 and pager:GetValue()==2,'Skinned pager retains page navigation')
    pager:Update(0,3)
    assert(not pager.upBtn:IsEnabled() and pager.downBtn:IsEnabled(),'Range endpoints retain disabled state')
    if legacy then
      assert(pager.thumb:GetTexture()=='Interface\\Buttons\\UI-ScrollBar-Knob')
      assert(pager.upBtn:GetNormalTexture():GetTexture()=='Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up')
      pager:GetScript('OnEnter')(pager)
      assert(pager.thumb:GetTexture()=='Interface\\Buttons\\UI-ScrollBar-Knob','Hover preserves Classic artwork')
      pages.CreateBrowsePanel:RebuildFilters()
      local category=pages.CreateBrowsePanel.filterButtons[1]
      assert(category and category.NormalTexture:GetTexture()=='Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg',
        'Legacy category texture: '..tostring(category and category.NormalTexture:GetTexture()))
      local check=Find(pages.CreateAHScannerPanel,function(frame) return frame.checkTex~=nil end)
      assert(check and check:GetNormalTexture():GetTexture()=='Interface\\Buttons\\UI-CheckBox-Up')
      check:SetCheckedState(false);A_Admin.Click(check)
      assert(check.checked and check.checkTex:IsShown(),'Classic checkbox preserves list selection')
    else
      assert(pager.thumb:GetTexture()=='Interface\\Buttons\\WHITE8X8')
      assert(pager.upBtn:GetNormalTexture():GetTexture()=='Interface\\Buttons\\Arrow-Up-Up')
    end
    local scroll=CreateFrame('ScrollFrame',nil,host,'UIPanelScrollFrameTemplate')
    local bar=scroll.ScrollBar
    bar.ScrollUpButton=CreateFrame('Button',nil,bar)
    bar.ScrollDownButton=CreateFrame('Button',nil,bar)
    local thumb=bar:CreateTexture(nil,'OVERLAY')
    function bar:GetThumbTexture() return thumb end
    MarketSync.SkinModernScrollBar(scroll)
    assert(thumb:GetTexture()==(legacy and 'Interface\\Buttons\\UI-ScrollBar-Knob' or 'Interface\\Buttons\\WHITE8X8'))
    assert(bar:GetWidth()==(legacy and 16 or 8),'Scrolling content uses the selected theme too')
    MarketSync.ShowBulkAlertImportPopup('Theme test',{})
    local popup=MarketSyncBulkAlertImportFrame
    assert(popup:IsShown())
    assert((popup._marketSyncLegacyAuctionArt~=nil)==legacy,'Newer import window follows selected frame design')

    local recipe = {
      name = 'Camp Chair', outputItemID = 13444, outputQty = 1,
      mats = { { itemID = 555, qty = 3 }, { itemID = 556, qty = 2 } },
    }
    MarketSync.OpenCraftingTree(recipe, host, { quantities = { [13444] = 2 } })
    local planner = MarketSyncCraftingTreeFrame
    assert(planner:IsShown() and planner.TitleText:GetText() == 'Materials & Crafting Choices')
    if legacy then
      assert(planner._marketSyncLegacyAuctionArt.active and not planner:GetBackdrop())
    else
      assert(planner._template == 'PortraitFrameTemplate' and not planner.warcraftTitleBg)
    end
    assert(planner.qtyValue:GetText() == '2' and planner.subtitle:GetText():find('Camp Chair'))
    local scroll = planner.scrollFrame
    assert(scroll:GetParent():GetBackdrop() and scroll._marketSyncThemedScroll)
    assert(scroll:GetScrollChild():GetHeight() == planner.rowPool[1]:GetHeight()
      + planner.rowPool[2]:GetHeight() + planner.rowPool[3]:GetHeight(), 'Short plans fit their actual row height')
    local firstMaterial = planner.rowPool[2]
    assert(firstMaterial.itemText:GetNumPoints() == 2 and firstMaterial.detailText:IsShown())
    A_Admin.Click(Find(planner, function(widget) return widget:IsObjectType('Button') and widget:GetText() == '+' end))
    assert(planner.qtyValue:GetText() == '3' and firstMaterial.itemText:GetText():find('x9'))
    firstMaterial.check:SetChecked(false)
    A_Admin.Click(firstMaterial.check)
    assert(firstMaterial.itemText:GetText():find('PROVIDE') and planner.sumSavings:GetText():find('9 units'))
    local exported
    MarketSync.ExportCraftPurchasesToShoppingList = function(request)
      exported = MarketSync.BuildCraftPurchasePlan(request)
      return true, exported.buyCount, 'Camp Chair test'
    end
    A_Admin.Click(Find(planner, function(widget)
      return widget:IsObjectType('Button') and widget:GetText() == 'Export checked to Shopping'
    end))
    assert(exported.buyUnits == 6 and exported.providedUnits == 9)
    A_Admin.Click(planner.CloseButton)
    assert(not planner:IsShown())

    MarketSync.ReviewMarketSyncData()
    local dataReview = MarketSyncDataReviewFrame
    assert(dataReview:IsShown() and dataReview.TitleText:GetText() == 'MarketSyncData Status')
    assert(dataReview.Status:GetParent():GetBackdrop() and dataReview.PackRecords:GetParent():GetBackdrop())
    if legacy then
      assert(dataReview._warcraftDecorated and dataReview:GetBackdrop())
    else
      assert(dataReview._template == 'PortraitFrameTemplate' and not dataReview.warcraftTitleBg)
    end
    A_Admin.Click(dataReview.CloseButton)
    assert(not dataReview:IsShown())

    local cr,cg,cb=MarketSync.GetThemeColor('chart')
    assert(legacy and cr>cg and cg>cb or not legacy and cr==0 and cg==0 and cb==0)
    assert(native:GetBackdrop().bgFile=='native-client-art','Only MarketSync-owned surfaces are themed')

    if not legacy then
      local auction = CreateFrame('Frame', 'AuctionHouseFrame', UIParent)
      auction:SetSize(800, 538)
      auction:Hide()
      auction.MoneyFrameBorder = CreateFrame('Frame', nil, auction)
      auction.MoneyFrameBorder:SetSize(158, 19)
      auction.MoneyFrameBorder:SetPoint('BOTTOMLEFT', auction, 'BOTTOMLEFT', 5, 6)
      auction.AuctionsTab = { displayMode = 'auctions' }
      auction.Tabs = { { displayMode = 'buy' }, { displayMode = 'sell' }, auction.AuctionsTab }
      function auction:GetDisplayMode() return self.displayMode end
      function auction:SetDisplayMode(mode) self.displayMode = mode end
      local AH = MarketSync.AuctionHouse
      assert(AH.Attach())

      local function CheckBottomEdge(tab, expectedInsets)
        local anchored = false
        for i = 1, tab:GetNumPoints() do
          local point, relative, relativePoint, _, y = tab:GetPoint(i)
          if point == 'BOTTOMLEFT' then
            anchored = relative == auction.MoneyFrameBorder and relativePoint == 'TOPLEFT' and y == 2
          end
        end
        assert(anchored, 'MarketSync tab meets the native auction footer')
        local insets = 0
        for _, child in ipairs({tab.Content:GetChildren()}) do
          if child._template == 'InsetFrameTemplate' then
            for i = 1, child:GetNumPoints() do
              local point, relative, relativePoint, _, y = child:GetPoint(i)
              if relative == tab.Content and (point == 'BOTTOMLEFT' or point == 'BOTTOMRIGHT') then
                assert(relativePoint == point and y == 0, 'No per-tab gap above the native auction footer')
                insets = insets + 1
              end
            end
          end
        end
        assert(insets == expectedInsets, 'Every bottom-most inset shares the footer line')
      end

      CheckBottomEdge(AH.ScannerPanel, 2)
      CheckBottomEdge(AH.ProcessingPanel, 2)
      CheckBottomEdge(AH.AlertsPanel, 2)
      CheckBottomEdge(AH.AnalyticsPanel, 2)
      AH.AnalyticsPanel.Content:SetSidebarCollapsed(true)
      CheckBottomEdge(AH.AnalyticsPanel, 2)
      assert(auction:GetWidth() == 800 and auction:GetHeight() == 538, 'The native window keeps its dimensions')
    end
  `, `${theme}_controls`);
}
console.log('PASS complete page construction, themed categories/imports/checkboxes/scrollbars, pager behavior, and native-frame isolation');
