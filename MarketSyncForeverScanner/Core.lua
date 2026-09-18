local addonName = ...
local S = MarketSyncForeverScanner
S.AddonName = addonName or "MarketSyncForeverScanner"
S.RequiredAPI = {
  "GetBrowseResults", "GetItemKeyInfo", "SendSearchQuery", "IsThrottledMessageSystemReady",
  "GetNumItemSearchResults", "GetItemSearchResultInfo", "HasFullItemSearchResults",
  "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo", "HasFullCommoditySearchResults",
  "RequestMoreItemSearchResults", "RequestMoreCommoditySearchResults",
}

function S.CheckClient()
  local version, build = GetBuildInfo()
  if version ~= "1.60.1" or tostring(build) ~= "69893" then
    return false, "Prototype targets Forever 1.60.1 (69893); capture held on this client"
  end
  for _, name in ipairs(S.RequiredAPI) do
    if not C_AuctionHouse or type(C_AuctionHouse[name]) ~= "function" then
      return false, "Missing native API: " .. name
    end
  end
  return true
end

function S.Report()
  local version, build, date, interface = GetBuildInfo()
  local ok, reason = S.CheckClient()
  local count, watched = 0, 0
  if S.Store then
    for _ in pairs(S.Store.records) do count = count + 1 end
    for _ in pairs(S.Store.watched) do watched = watched + 1 end
  end
  local report = {
    adapter = S.Version, version = version, build = tostring(build), date = date,
    interface = interface, projectID = WOW_PROJECT_ID, clientSupported = ok,
    reason = reason, marketID = S.MarketID, marketBucketIsManual = true,
    auctioneerOpen = S.AuctioneerOpen == true, modernFrame = AuctionHouseFrame ~= nil,
    records = count, watched = watched, active = S.Active, status = S.Status,
    replicateAPI = C_AuctionHouse and type(C_AuctionHouse.ReplicateItems) == "function" or false,
    fullMarketScanImplemented = false, guildSyncEnabled = false,
    auctionHouseEntryAttached = S.AuctionHouseEntry ~= nil,
    auctionHouseEntryMode = "portable-launcher", embeddedAuctionHousePanel = false,
    alertsEnabled = false,
  }
  if MarketSyncForeverScanDB then MarketSyncForeverScanDB.diagnostics = report end
  print("MarketSync Forever " .. S.Version .. ": " .. tostring(version) .. " (" .. tostring(build)
    .. "), Interface=" .. tostring(interface) .. ", project=" .. tostring(WOW_PROJECT_ID))
  print("Market=" .. tostring(S.MarketID) .. "; records=" .. count .. ", watched=" .. watched
    .. ", auctioneer=" .. tostring(report.auctioneerOpen) .. ", modernFrame=" .. tostring(report.modernFrame))
  print(S.Status)
  if reason then print(reason) end
  return report
end

local function StartClient()
  local ok, reason = S.CheckClient()
  S.Ready = ok
  if not ok then S.Status = reason; return end
  if not S.InitializeStore() then S.Ready = false; return end
  S.Status = "Ready: native searches are captured while an auctioneer is open"
  if not S.HooksInstalled and hooksecurefunc then
    for _, name in ipairs({"SendSearchQuery", "SendSellSearchQuery", "SendBrowseQuery", "SearchForItemKeys", "SearchForFavorites"}) do
      if type(C_AuctionHouse[name]) == "function" then
        hooksecurefunc(C_AuctionHouse, name, S.ExternalQuery)
      end
    end
    S.HooksInstalled = true
  end
  S.AttachAuctionHouseEntry()
end

local frame = CreateFrame("Frame")
S.EventFrame = frame
for _, event in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
  "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED",
  "COMMODITY_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
}) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, arg)
  local ok, err = pcall(function()
    if event == "PLAYER_LOGIN" then
      StartClient()
    elseif event == "ADDON_LOADED" and arg == S.AddonName and IsLoggedIn() then
      StartClient()
    elseif event == "PLAYER_LOGOUT" then
      S.Cancel("Offline browsing")
      S.Report()
    elseif not S.Ready then
      return
    elseif event == "ADDON_LOADED" and arg == "Blizzard_AuctionHouseUI" then
      S.AttachAuctionHouseEntry()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg == Enum.PlayerInteractionType.Auctioneer then
      S.AuctioneerOpen = true
      S.Status = "Recording native searches; watch items to refresh them"
      S.AttachAuctionHouseEntry()
      S.Notify()
    elseif event == "AUCTION_HOUSE_CLOSED"
      or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg == Enum.PlayerInteractionType.Auctioneer then
      S.AuctioneerOpen = false
      S.Cancel("Auctioneer closed; saved prices remain available")
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
      S.CaptureBrowse()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
      S.CaptureSearch(arg, false)
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
      S.CaptureSearch(S.CommodityKey(arg), true)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
      S.Schedule()
    end
  end)
  if not ok then
    S.Cancel("Native capture failed: " .. tostring(err))
    print("MarketSync Forever: " .. S.Status)
  end
end)

SLASH_MarketSyncForeverScanner1 = "/msf"
SLASH_MarketSyncForeverScanner2 = "/msforever"
SlashCmdList.MarketSyncForeverScanner = function(input)
  input = (input or ""):lower()
  if input == "report" then S.Report()
  elseif input == "scan" then S.StartWatched()
  elseif input == "stop" then S.Cancel("Watch scan stopped")
  elseif S.ToggleWindow then S.ToggleWindow()
  end
end
