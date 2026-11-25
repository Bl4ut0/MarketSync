local addonName, ledger = ...
_G.MarketSyncLedger = ledger

function ledger.GetDB()
    if not ledger.db then
        MarketSyncLedgerDB = MarketSyncLedgerDB or {}
        ledger.db = MarketSyncLedgerDB
        if not ledger.db.migrated then
            local old = MarketSyncDB or {}
            ledger.db.items = ledger.db.items or old.ItemLedger
            ledger.db.crafts = ledger.db.crafts or {}
            for realm, data in pairs(old.RealmData or {}) do
                if type(data) == "table" and type(data.CraftLedger) == "table" and not ledger.db.crafts[realm] then
                    ledger.db.crafts[realm] = data.CraftLedger
                end
            end
            -- Preserve the old records for downgrade and keep future writes independent.
            local function Copy(value)
                if type(value) ~= "table" then return value end
                local result = {}
                for key, entry in pairs(value) do result[key] = Copy(entry) end
                return result
            end
            ledger.db.items = Copy(ledger.db.items)
            ledger.db.crafts = Copy(ledger.db.crafts)
            if ledger.db.enabled == nil then ledger.db.enabled = old.EnableLedgerBeta ~= false end
            if ledger.db.showCraftDemand == nil then ledger.db.showCraftDemand = old.EnableTooltipCraftDemand ~= false end
            if ledger.db.showMinimap == nil then ledger.db.showMinimap = old.EnableLedgerMinimapIcon == true end
            ledger.db.retentionDays = ledger.db.retentionDays or old.LedgerRetentionDays or 30
            ledger.db.minimap = ledger.db.minimap or Copy(old.LedgerMinimapIcon) or { minimapPos = 195 }
            ledger.db.migrated = true
        end
    end
    return ledger.db
end

function MarketSync.CanOpenLedger()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return (not loaded or loaded(addonName))
        and MarketSync.IsLedgerEnabled() and type(MarketSync.ToggleItemLedger) == "function"
end

function MarketSync.OpenLedgerShortcut()
    if not MarketSync.CanOpenLedger() then return false end
    MarketSync.ToggleItemLedger()
    return true
end

function MarketSync.RunLedgerCommand()
    if not MarketSync.OpenLedgerShortcut() then
        print("|cffffbb44[MarketSync Ledger]|r Enable transactional tracking in the MarketSync Ledger addon settings.")
    end
end

local function RefreshMinimapIcon()
    local broker = LibStub and LibStub("LibDataBroker-1.1", true)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not broker or not icon then return end
    local db = ledger.GetDB()
    local visible = db.showMinimap and MarketSync.CanOpenLedger()
    db.minimap.hide = not visible
    if visible and not icon:IsRegistered(addonName) then
        local launcher = broker:NewDataObject(addonName, {
            type = "launcher", text = "MarketSync Ledger", icon = "Interface\\Icons\\INV_Misc_Book_09",
            OnClick = function(_, button)
                if button == "RightButton" then MarketSync.OpenCraftManager()
                else MarketSync.OpenLedgerShortcut() end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("MarketSync Ledger")
                tooltip:AddLine("Left-click for the Item Ledger")
                tooltip:AddLine("Right-click for the Craft Manager")
            end,
        })
        icon:Register(addonName, launcher, db.minimap)
    end
    if icon:IsRegistered(addonName) then
        if visible then icon:Show(addonName) else icon:Hide(addonName) end
    end
end

function MarketSync.UpdateLedgerUIState()
    local main = MarketSync.MainFrame
    if main and main.UpdateLedgerButtonState then main.UpdateLedgerButtonState() end
    if MarketSyncCraftManager and MarketSyncCraftManager.UpdateLedgerButtonState then
        MarketSyncCraftManager.UpdateLedgerButtonState()
    end
    RefreshMinimapIcon()
end

local function CreateSettings()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "MarketSync Ledger"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -24)
    title:SetText(panel.name)
    local db = ledger.GetDB()
    local function Checkbox(label, offset, key, onClick)
        local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", 20, offset)
        local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        text:SetText(label)
        checkbox:SetChecked(db[key])
        checkbox:SetScript("OnClick", function(self)
            db[key] = self:GetChecked() and true or false
            if onClick then onClick(db[key]) end
        end)
    end
    Checkbox("Enable Transactional Item Ledger", -60, "enabled", MarketSync.SetLedgerEnabled)
    Checkbox("Show Pending Craft Demand on Tooltips", -90, "showCraftDemand", MarketSync.RefreshActiveTooltip)
    Checkbox("Show Ledger Minimap Icon", -120, "showMinimap", RefreshMinimapIcon)

    local retention = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    retention:SetPoint("TOPLEFT", 24, -165)
    retention:SetText("Keep detailed records for")
    local dropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", retention, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(dropdown, 108)
    UIDropDownMenu_SetText(dropdown, db.retentionDays .. " days")
    UIDropDownMenu_Initialize(dropdown, function()
        for _, days in ipairs({ 14, 30, 60, 90 }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = days .. " days"
            info.checked = db.retentionDays == days
            info.func = function()
                db.retentionDays = days
                UIDropDownMenu_SetText(dropdown, info.text)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, loadedName)
    if loadedName ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    ledger.GetDB()
    SLASH_MARKETSYNCLEDGER1 = "/msledger"
    SLASH_MARKETSYNCLEDGER2 = "/ledger"
    SlashCmdList.MARKETSYNCLEDGER = MarketSync.RunLedgerCommand
    CreateSettings()
    MarketSync.UpdateLedgerUIState()
    if IsLoggedIn and IsLoggedIn() then MarketSync.LedgerTracking.InstallHooks() end
end)
