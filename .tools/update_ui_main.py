path = r"C:\Users\bl4ut\Documents\Codex\2026-09-16\ok-x20\MarketSync-Forever\MarketSync\UI_Main.lua"
with open(path, "r", encoding="utf-8") as f:
    code = f.read()

old_tab_names = 'local tabNames = {"Personal Scan", "Guild Sync", "Neutral AH", "Processing", "Notifications", "Settings"}'
new_tab_names = 'local tabNames = {"Scanner", "Personal Scan", "Guild Sync", "Neutral AH", "Processing", "Notifications", "Settings"}'
assert old_tab_names in code, "tabNames not found"
code = code.replace(old_tab_names, new_tab_names, 1)

old_ondemand = """        if MarketSyncDB and MarketSyncDB.LowRamMode then
            if id == 1 and MarketSyncDB.OnDemandPersonal and MarketSync.LoadPersonalCache then
                MarketSync.LoadPersonalCache()
            elseif id == 2 and MarketSyncDB.OnDemandGuild and MarketSync.LoadGuildCache then
                MarketSync.LoadGuildCache()
            elseif id == 3 and MarketSyncDB.OnDemandNeutral and MarketSync.LoadNeutralCache then
                MarketSync.LoadNeutralCache()
            end
        end"""
new_ondemand = """        if MarketSyncDB and MarketSyncDB.LowRamMode then
            if id == 2 and MarketSyncDB.OnDemandPersonal and MarketSync.LoadPersonalCache then
                MarketSync.LoadPersonalCache()
            elseif id == 3 and MarketSyncDB.OnDemandGuild and MarketSync.LoadGuildCache then
                MarketSync.LoadGuildCache()
            elseif id == 4 and MarketSyncDB.OnDemandNeutral and MarketSync.LoadNeutralCache then
                MarketSync.LoadNeutralCache()
            end
        end"""
assert old_ondemand in code, "old_ondemand not found"
code = code.replace(old_ondemand, new_ondemand, 1)

old_titles = """        local titles = {
            "Personal Scan",
            "Guild Sync",
            "Neutral AH",
            "Processing",
            "Notifications",
            "Settings"
        }
        
        local tooltips = {
            "Browse your natively scanned Auction House data.",
            "Browse composite Auction House data synced from guild members.",
            "Browse data from the Neutral Auction House.",
            "Organized controls on the left, auction-style arbitrage and crafting results on the right.",
            "Track targets by threshold and import from Auctionator shopping lists.",
            "Configure MarketSync background settings, caches, and UI behaviors.",
        }"""
new_titles = """        local titles = {
            "Scanner",
            "Personal Scan",
            "Guild Sync",
            "Neutral AH",
            "Processing",
            "Notifications",
            "Settings"
        }
        
        local tooltips = {
            "Native Auction House scanner and preferred lists manager.",
            "Browse your natively scanned Auction House data.",
            "Browse composite Auction House data synced from guild members.",
            "Browse data from the Neutral Auction House.",
            "Organized controls on the left, auction-style arbitrage and crafting results on the right.",
            "Track targets by threshold and watch lists.",
            "Configure MarketSync background settings, caches, and UI behaviors.",
        }"""
assert old_titles in code, "old_titles not found"
code = code.replace(old_titles, new_titles, 1)

old_hide = """        local isHidden = false
        if i == 2 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
            isHidden = true
        elseif i == 3 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
            isHidden = true
        end"""
new_hide = """        local isHidden = false
        if i == 3 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
            isHidden = true
        elseif i == 4 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
            isHidden = true
        end"""
assert old_hide in code, "old_hide not found"
code = code.replace(old_hide, new_hide, 1)

old_refresh_hide = """            local shouldHide = false
            if i == 2 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
                shouldHide = true
            elseif i == 3 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
                shouldHide = true
            end"""
new_refresh_hide = """            local shouldHide = false
            if i == 3 and MarketSyncDB and MarketSyncDB.PassiveSync == false then
                shouldHide = true
            elseif i == 4 and MarketSyncDB and MarketSyncDB.EnableNeutralSync == false then
                shouldHide = true
            end"""
assert old_refresh_hide in code, "old_refresh_hide not found"
code = code.replace(old_refresh_hide, new_refresh_hide, 1)

old_browse_start = """    -- ================================================================
    -- TAB 1 & 2: BROWSE PANELS (Personal / Guild)
    -- ================================================================
    BrowseContent = MarketSync.CreateBrowsePanel(MainFrame, "personal")
    table.insert(contentFrames, BrowseContent)"""
new_browse_start = """    -- ================================================================
    -- TAB 1: SCANNER & QUICK LISTS
    -- ================================================================
    local ScannerContent = MarketSync.CreateAHScannerPanel and MarketSync.CreateAHScannerPanel(MainFrame) or CreateFrame("Frame", nil, MainFrame)
    ScannerContent:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 18, -72)
    ScannerContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -18, 40)
    table.insert(contentFrames, ScannerContent)

    -- ================================================================
    -- TAB 2, 3, 4: BROWSE PANELS (Personal / Guild / Neutral)
    -- ================================================================
    BrowseContent = MarketSync.CreateBrowsePanel(MainFrame, "personal")
    BrowseContent:Hide()
    table.insert(contentFrames, BrowseContent)"""
assert old_browse_start in code, "old_browse_start not found"
code = code.replace(old_browse_start, new_browse_start, 1)

old_back = """        if activeBrowseTab == 1 then
            BrowseContent:Show()
        elseif activeBrowseTab == 2 then
            SyncContent:Show()
        end"""
new_back = """        if activeBrowseTab == 2 then
            BrowseContent:Show()
        elseif activeBrowseTab == 3 then
            SyncContent:Show()
        elseif activeBrowseTab == 4 then
            NeutralContent:Show()
        end"""
assert old_back in code, "old_back not found"
code = code.replace(old_back, new_back, 1)

old_src_tab = """        if not sourceTab then
            if activeBrowseTab == 1 then
                sourceTab = "personal"
            elseif activeBrowseTab == 2 then
                sourceTab = "guild"
            elseif activeBrowseTab == 3 then
                sourceTab = "neutral"
            end
        end"""
new_src_tab = """        if not sourceTab then
            if activeBrowseTab == 2 then
                sourceTab = "personal"
            elseif activeBrowseTab == 3 then
                sourceTab = "guild"
            elseif activeBrowseTab == 4 then
                sourceTab = "neutral"
            end
        end"""
assert old_src_tab in code, "old_src_tab not found"
code = code.replace(old_src_tab, new_src_tab, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(code)

print("UI_Main.lua successfully updated!")
