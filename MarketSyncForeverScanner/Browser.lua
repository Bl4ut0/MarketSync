-- GPL-3.0-or-later. Shared saved-price browser for the native AH tab and portable window.
local S = MarketSyncForeverScanner
S.MarketBrowsers = {}
local categories = {
  {"All saved", nil}, {"Weapons", "Weapon"}, {"Armor", "Armor"}, {"Containers", "Container"},
  {"Consumables", "Consumable"}, {"Trade Goods", "Tradegoods"}, {"Ammo", "Projectile"},
  {"Quivers", "Quiver"}, {"Recipes", "Recipe"}, {"Quest Items", "Questitem"},
  {"Miscellaneous", "Miscellaneous"}, {"Watched", "watched"},
}

local function Money(amount)
  if not amount then return "--" end
  local value = math.floor(amount + 0.5)
  return string.format("%dg %ds %dc", math.floor(value / 10000), math.floor(value % 10000 / 100), value % 100)
end

local function Age(stamp)
  if not stamp then return "--" end
  local elapsed = math.max(0, time() - stamp)
  if elapsed < 60 then return elapsed .. "s" end
  if elapsed < 3600 then return math.floor(elapsed / 60) .. "m" end
  return math.floor(elapsed / 3600) .. "h"
end

local function Text(parent, x, y, width, value, font)
  local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  text:SetWidth(width)
  text:SetJustifyH("LEFT")
  text:SetText(value)
  return text
end

local function Button(parent, x, y, width, label, action, height)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetSize(width, height or 24)
  button:SetText(label)
  button:SetScript("OnClick", action)
  return button
end

local function Price(record)
  local snapshot = record.latest
  return snapshot and (snapshot.minUnitPrice or snapshot.browseMinPrice)
end

local function MatchingRecords(browser)
  local result = {}
  local needle = browser.search:GetText():lower()
  if not S.Store then return result end
  for id, record in pairs(S.Store.records) do
    local matches = true
    if browser.category == "watched" then
      matches = S.Store.watched[id] == true
    elseif browser.category then
      local classID = select(6, C_Item.GetItemInfoInstant(record.key.itemID))
      matches = Enum.ItemClass[browser.category] ~= nil and classID == Enum.ItemClass[browser.category]
    end
    local name = record.name or tostring(record.key.itemID)
    if matches and (needle == "" or name:lower():find(needle, 1, true) or id:find(needle, 1, true)) then
      table.insert(result, record)
    end
  end
  table.sort(result, function(a, b)
    if browser.sortBy == "price" then
      local aPrice, bPrice = Price(a) or math.huge, Price(b) or math.huge
      if aPrice ~= bPrice then return aPrice < bPrice end
    end
    local aName, bName = a.name or tostring(a.key.itemID), b.name or tostring(b.key.itemID)
    if aName == bName then return a.keyID < b.keyID end
    return aName < bName
  end)
  return result
end

local function DetailLines(record)
  if not record then
    return {"Saved market details", "", "Search and open listings in Blizzard's Buy tab to record observations.", "",
      "Click + to watch an item, then Refresh watched at an auctioneer.", "",
      "Select a saved item for price depth and recent history.", "",
      "Prices remain available in the portable window after leaving the auctioneer."}
  end
  local lines = {record.name or ("Item " .. record.key.itemID), "",
    record.isCommodity and "Commodity" or "Item / variant", ""}
  local snapshot = record.latest
  if snapshot then
    local sources = {['native-browse'] = "Blizzard browse", ['native-item-search'] = "Blizzard item search",
      ['native-commodity-search'] = "Blizzard commodity search"}
    table.insert(lines, snapshot.complete and "Complete for this item key" or "Observed partial result")
    table.insert(lines, sources[snapshot.source] or snapshot.source)
    table.insert(lines, "Seen: " .. Age(snapshot.seenAt) .. " ago")
    table.insert(lines, "Available in result: " .. tostring(snapshot.available))
    table.insert(lines, "Buyout units: " .. tostring(snapshot.pricedQuantity or "unknown"))
    table.insert(lines, "Unit buyout: " .. Money(snapshot.minUnitPrice))
    if snapshot.browseMinPrice then table.insert(lines, "Browse price: " .. Money(snapshot.browseMinPrice)) end
    table.insert(lines, "")
    table.insert(lines, "Price depth")
    for index, level in ipairs(snapshot.priceLevels or {}) do
      if index <= 6 then table.insert(lines, Money(level.unitPrice) .. " x " .. level.quantity) end
    end
  end
  table.insert(lines, "")
  table.insert(lines, "Recent complete observations")
  for index = #record.history, math.max(1, #record.history - 4), -1 do
    local point = record.history[index]
    table.insert(lines, Age(point.seenAt) .. " ago: " .. Money(point.minUnitPrice) .. " / " .. tostring(point.available) .. " units")
  end
  return lines
end

function S.RefreshMarketBrowsers()
  for _, browser in ipairs(S.MarketBrowsers) do browser:Refresh() end
end

function S.CreateMarketBrowser(parent, width, height, embedded)
  local browser = CreateFrame("Frame", nil, parent)
  browser:SetSize(width, height)
  browser:SetPoint("TOPLEFT")
  browser.page, browser.sortBy = 1, "price"
  browser.rows, browser.categoryButtons = {}, {}
  local listX = 145
  local detailWidth = width < 850 and 194 or 220
  local detailX = width - detailWidth - 10
  local listWidth = detailX - listX - 12
  local priceX, quantityX, seenX = listWidth - 205, listWidth - 125, listWidth - 85
  local rowCount = math.max(1, math.floor((height - 198) / 27))

  Text(browser, 12, -18, 125, "Saved search", "GameFontNormalSmall")
  browser.search = CreateFrame("EditBox", nil, browser, "InputBoxTemplate")
  browser.search:SetPoint("TOPLEFT", browser, "TOPLEFT", listX + 5, -12)
  browser.search:SetSize(listWidth - 5, 24)
  browser.search:SetAutoFocus(false)
  browser.scanButton = Button(browser, listX, -44, 132, "Refresh watched", S.StartWatched)
  browser.stopButton = Button(browser, listX + 140, -44, 56, "Stop", function() S.Cancel("Watch scan stopped") end)
  browser.marketButton = Button(browser, listX + 204, -44, 116, "Main / Neutral", function()
    S.SetMarket(S.MarketBucket == "main" and "neutral" or "main")
  end)
  if embedded then
    browser.portableButton = Button(browser, detailX, -12, detailWidth, "Portable window", S.ShowWindow)
  else
    Text(browser, detailX, -18, detailWidth, "Saved auction observations", "GameFontNormalSmall")
  end
  Button(browser, detailX, -44, detailWidth, "Diagnostics", S.Report)
  browser.progress = Text(browser, listX, -77, width - listX - 10, "")

  local function Inset(x, insetWidth)
    local inset = CreateFrame("Frame", nil, browser, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", browser, "TOPLEFT", x, -99)
    inset:SetSize(insetWidth, height - 164)
    return inset
  end
  Inset(10, 127)
  Inset(listX - 4, listWidth + 8)
  local detailInset = Inset(detailX, detailWidth)
  for index, entry in ipairs(categories) do
    local target = entry[2]
    local button = Button(browser, 14, -104 - (index - 1) * 25, 119, entry[1], function()
      browser.category, browser.page = target, 1
      browser:Refresh()
    end, 23)
    browser.categoryButtons[index] = {button = button, category = target}
  end
  Button(browser, listX + 51, -106, priceX - 54, "Name", function()
    browser.sortBy, browser.page = "name", 1; browser:Refresh()
  end, 20)
  Button(browser, listX + priceX, -106, 76, "Price", function()
    browser.sortBy, browser.page = "price", 1; browser:Refresh()
  end, 20)
  Text(browser, listX + quantityX, -112, 38, "Qty", "GameFontNormalSmall")
  Text(browser, listX + seenX, -112, 85, "Seen / coverage", "GameFontNormalSmall")
  for index = 1, rowCount do
    local row = CreateFrame("Button", nil, browser)
    row:SetPoint("TOPLEFT", browser, "TOPLEFT", listX, -133 - (index - 1) * 27)
    row:SetSize(listWidth, 26)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:SetColorTexture(1, 0.82, 0, 0.14)
    row.watch = Button(row, 0, -1, 26, "+", function()
      if row.record then S.ToggleWatch(row.record.keyID) end
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 31, -4)
    row.icon:SetSize(18, 18)
    row.name = Text(row, 53, -7, priceX - 57, "")
    row.name:SetWordWrap(false)
    row.price = Text(row, priceX, -7, 78, "")
    row.quantity = Text(row, quantityX, -7, 38, "")
    row.seen = Text(row, seenX, -7, 85, "")
    row:SetScript("OnClick", function()
      if row.record then
        browser.selected = row.record.keyID
        browser.detailScroll:SetVerticalScroll(0)
        browser:Refresh()
      end
    end)
    browser.rows[index] = row
  end
  browser.detailScroll = CreateFrame("ScrollFrame", nil, detailInset, "UIPanelScrollFrameTemplate")
  browser.detailScroll:SetPoint("TOPLEFT", 10, -10)
  browser.detailScroll:SetPoint("BOTTOMRIGHT", -28, 10)
  browser.detailContent = CreateFrame("Frame", nil, browser.detailScroll)
  browser.detailContent:SetSize(detailWidth - 42, height)
  browser.detail = Text(browser.detailContent, 0, 0, detailWidth - 42, "")
  browser.detail:SetJustifyV("TOP")
  browser.detailScroll:SetScrollChild(browser.detailContent)
  browser.previous = Button(browser, listX, -height + 65, 86, "Previous", function()
    browser.page = browser.page - 1; browser:Refresh()
  end)
  browser.nextPage = Button(browser, listX + 94, -height + 65, 86, "Next", function()
    browser.page = browser.page + 1; browser:Refresh()
  end)
  browser.status = Text(browser, 12, -height + 35, width - 24, "")
  browser.status:SetHeight(34)

  function browser:Refresh()
    if not self:IsVisible() then return end
    if self.marketID ~= S.MarketID then
      self.marketID, self.selected, self.page = S.MarketID, nil, 1
      self.detailScroll:SetVerticalScroll(0)
    end
    local data = MatchingRecords(self)
    local totalPages = math.max(1, math.ceil(#data / #self.rows))
    self.page = math.max(1, math.min(self.page, totalPages))
    local bucket = S.MarketBucket == "neutral" and "Neutral AH" or "Main market"
    self.status:SetText(S.Status .. "\n" .. bucket .. " | " .. #data .. " saved keys | page " .. self.page .. "/" .. totalPages)
    local active = S.Active == true
    self.progress:SetText(active and ("Watched refresh: " .. tostring(S.CompletedCount or 0) .. "/" .. #(S.Queue or {}) .. " complete")
      or "Observed prices and quantities - refresh at an auctioneer")
    self.previous:SetEnabled(self.page > 1)
    self.nextPage:SetEnabled(self.page < totalPages)
    self.scanButton:SetEnabled(S.Ready == true and S.IsAuctioneerAvailable() and not active)
    self.stopButton:SetEnabled(active)
    self.marketButton:SetEnabled(S.Ready == true and not active and not S.AuctioneerOpen)
    for _, entry in ipairs(self.categoryButtons) do entry.button:SetEnabled(entry.category ~= self.category) end
    for index, row in ipairs(self.rows) do
      local record = data[(self.page - 1) * #self.rows + index]
      row.record = record
      row:SetShown(record ~= nil)
      if record then
        local snapshot = record.latest
        row.watch:SetText(S.Store.watched[record.keyID] and "*" or "+")
        row.watch:SetEnabled(not active)
        row.icon:SetTexture(record.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(record.name or ("Item " .. record.key.itemID))
        row.price:SetText(Money(Price(record)))
        row.quantity:SetText(snapshot and tostring(snapshot.available) or "--")
        local coverage = snapshot and (snapshot.complete and "Full item" or snapshot.source == "native-browse" and "Browse" or "Partial") or "Unseen"
        row.seen:SetText(Age(snapshot and snapshot.seenAt) .. " / " .. coverage)
        row.selection:SetShown(record.keyID == self.selected)
      end
    end
    local record = S.Store and self.selected and S.Store.records[self.selected]
    self.detail:SetText(table.concat(DetailLines(record), "\n"))
    self.detailContent:SetHeight(math.max(height - 194, (self.detail:GetStringHeight() or 400) + 12))
  end
  browser.search:SetScript("OnTextChanged", function() browser.page = 1; browser:Refresh() end)
  browser.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  browser:SetScript("OnShow", browser.Refresh)
  browser:SetScript("OnUpdate", function(self, elapsed)
    self.ageElapsed = (self.ageElapsed or 0) + elapsed
    if self.ageElapsed >= 5 then self.ageElapsed = 0; self:Refresh() end
  end)
  table.insert(S.MarketBrowsers, browser)
  return browser
end
