local S = MarketSyncForeverScanner
local window, rows, detail, status, search, previous, nextPage, scanButton
local page, category, selected = 1, nil, nil
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

local function Text(parent, x, y, width, text, font)
  local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  label:SetWidth(width)
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function Button(parent, x, y, width, label, action)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetSize(width, 24)
  button:SetText(label)
  button:SetScript("OnClick", action)
  return button
end

local function MatchingRecords()
  local result = {}
  local needle = search and search:GetText():lower() or ""
  if not S.Store then return result end
  for id, record in pairs(S.Store.records) do
    local matches = true
    if category == "watched" then
      matches = S.Store.watched[id] == true
    elseif category then
      local classID = select(6, C_Item.GetItemInfoInstant(record.key.itemID))
      matches = Enum.ItemClass[category] ~= nil and classID == Enum.ItemClass[category]
    end
    local name = record.name or tostring(record.key.itemID)
    if matches and (needle == "" or name:lower():find(needle, 1, true) or id:find(needle, 1, true)) then
      table.insert(result, record)
    end
  end
  table.sort(result, function(a, b)
    local aName, bName = a.name or tostring(a.key.itemID), b.name or tostring(b.key.itemID)
    if aName == bName then return a.keyID < b.keyID end
    return aName < bName
  end)
  return result
end

function S.RefreshWindow()
  if not window or not window:IsShown() then return end
  local data = MatchingRecords()
  local totalPages = math.max(1, math.ceil(#data / #rows))
  page = math.max(1, math.min(page, totalPages))
  status:SetText(S.Status .. "\n" .. (S.MarketID or "Waiting for supported client login")
    .. " | " .. #data .. " saved keys | page " .. page .. "/" .. totalPages)
  previous:SetEnabled(page > 1)
  nextPage:SetEnabled(page < totalPages)
  scanButton:SetEnabled(S.Ready == true and S.IsAuctioneerAvailable() and not S.Active)
  for index, row in ipairs(rows) do
    local record = data[(page - 1) * #rows + index]
    row.record = record
    row:SetShown(record ~= nil)
    if record then
      local snapshot = record.latest
      local price = snapshot and (snapshot.minUnitPrice or snapshot.browseMinPrice)
      row.watch:SetText(S.Store.watched[record.keyID] and "*" or "+")
      row.name:SetText(record.name or ("Item " .. record.key.itemID))
      row.price:SetText(Money(price))
      row.quantity:SetText(snapshot and tostring(snapshot.available) or "--")
      local coverage = snapshot and (snapshot.complete and "Full item" or snapshot.source == "native-browse" and "Browse" or "Partial") or "Unseen"
      row.seen:SetText(Age(snapshot and snapshot.seenAt) .. " / " .. coverage)
    end
  end
  local record = S.Store and selected and S.Store.records[selected]
  if not record then
    detail:SetText("Saved market details\n\nSearch in Blizzard's auction house to record observations.\n\nClick + to watch an item. Refresh watched uses a small, sequential query queue at an auctioneer.\n\nSaved observations remain available in this window after the auctioneer closes.")
    return
  end
  local snapshot = record.latest
  local lines = {
    record.name or ("Item " .. record.key.itemID), "",
    "Native key: " .. record.keyID,
    "Kind: " .. (record.isCommodity and "Commodity" or "Item / variant"), "",
  }
  if snapshot then
    table.insert(lines, "Coverage: " .. (snapshot.complete and "Complete for this key" or "Observed partial result"))
    table.insert(lines, "Source: " .. snapshot.source)
    table.insert(lines, "Seen: " .. Age(snapshot.seenAt) .. " ago")
    table.insert(lines, "Available in result: " .. tostring(snapshot.available))
    table.insert(lines, "Buyout units: " .. tostring(snapshot.pricedQuantity or "unknown"))
    table.insert(lines, "Unit buyout: " .. Money(snapshot.minUnitPrice))
    if snapshot.browseMinPrice then table.insert(lines, "Advertised browse price: " .. Money(snapshot.browseMinPrice)) end
    table.insert(lines, "")
    table.insert(lines, "Price depth (up to 20 levels)")
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
  detail:SetText(table.concat(lines, "\n"))
end

local function CreateWindow()
  window = CreateFrame("Frame", "MarketSyncForeverScannerWindow", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(980, 585)
  window:SetPoint("CENTER")
  window:SetFrameStrata("DIALOG")
  window:SetClampedToScreen(true)
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window.TitleText:SetText("MarketSync Forever - Saved Auction Data")
  table.insert(UISpecialFrames, "MarketSyncForeverScannerWindow")
  Text(window, 20, -35, 930, "Saved prices and availability | Watch up to 50 keys | Refresh at an auctioneer", "GameFontNormal")
  search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
  search:SetPoint("TOPLEFT", window, "TOPLEFT", 180, -62)
  search:SetSize(265, 22)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function() page = 1; S.RefreshWindow() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  Text(window, 20, -68, 150, "Search saved listings")
  scanButton = Button(window, 455, -60, 155, "Refresh watched", S.StartWatched)
  Button(window, 620, -60, 65, "Stop", function() S.Cancel("Watch scan stopped") end)
  Button(window, 695, -60, 110, "Main / Neutral", function()
    if S.SetMarket(S.MarketBucket == "main" and "neutral" or "main") then selected = nil; page = 1; S.RefreshWindow() end
  end)
  Button(window, 815, -60, 140, "Diagnostics", S.Report)
  for index, entry in ipairs(categories) do
    local name, target = entry[1], entry[2]
    Button(window, 18, -104 - (index - 1) * 29, 142, name, function()
      category, page = target, 1
      S.RefreshWindow()
    end)
  end
  Text(window, 180, -103, 270, "Item", "GameFontNormalSmall")
  Text(window, 445, -103, 110, "Price", "GameFontNormalSmall")
  Text(window, 550, -103, 55, "Qty", "GameFontNormalSmall")
  Text(window, 605, -103, 105, "Age / coverage", "GameFontNormalSmall")
  rows = {}
  for index = 1, 11 do
    local row = CreateFrame("Button", nil, window)
    row:SetPoint("TOPLEFT", window, "TOPLEFT", 180, -127 - (index - 1) * 31)
    row:SetSize(530, 30)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.watch = Button(row, 0, -2, 26, "+", function()
      if row.record then S.ToggleWatch(row.record.keyID) end
    end)
    row.name = Text(row, 32, -7, 230, "")
    row.price = Text(row, 265, -7, 105, "")
    row.quantity = Text(row, 370, -7, 55, "")
    row.seen = Text(row, 425, -7, 105, "")
    row:SetScript("OnClick", function()
      if row.record then selected = row.record.keyID; S.RefreshWindow() end
    end)
    rows[index] = row
  end
  detail = Text(window, 730, -106, 225, "", "GameFontHighlightSmall")
  detail:SetJustifyV("TOP")
  detail:SetHeight(425)
  previous = Button(window, 180, -480, 95, "Previous", function() page = page - 1; S.RefreshWindow() end)
  nextPage = Button(window, 280, -480, 95, "Next", function() page = page + 1; S.RefreshWindow() end)
  status = Text(window, 180, -520, 775, "")
  status:SetHeight(50)
  window:SetScript("OnShow", S.RefreshWindow)
  window:SetScript("OnUpdate", function(self, elapsed)
    self.ageElapsed = (self.ageElapsed or 0) + elapsed
    if self.ageElapsed >= 5 then self.ageElapsed = 0; S.RefreshWindow() end
  end)
end

function S.ShowWindow()
  if not window then CreateWindow() end
  window:Show()
  S.RefreshWindow()
end

function S.ToggleWindow()
  if not window then S.ShowWindow()
  else window:SetShown(not window:IsShown()) end
end
