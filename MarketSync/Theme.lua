-- Shared styling for MarketSync-owned windows; never walk the native AH root.
MarketSync.Theme = { roots = setmetatable({}, { __mode = "k" }) }
local T = MarketSync.Theme

function T.Button(button)
    -- Preserve authentic Blizzard UIPanelButtonTemplate artwork!
    -- In WoW Forever & Classic, buttons have beveled red/bronze/gold edges with embossed text.
    -- Never strip Blizzard textures and replace them with flat solid WHITE8X8 rectangles.
    if not button or button._marketSyncThemeButton then return end
    button._marketSyncThemeButton = true
end

function T.Apply(root)
    if not root or root._marketSyncApplyingTheme then return end
    root._marketSyncApplyingTheme = true

    local isLegacy = MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme()

    local function Walk(frame, depth)
        if depth > 12 then return end
        local isButton = frame.IsObjectType and frame:IsObjectType("Button")

        if frame == root and frame.SetBackdrop and frame.GetBackdrop and frame:GetBackdrop() then
            -- Root dialog window uses authentic Blizzard dialog textures with stone parchment background
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            if isLegacy then
                frame:SetBackdropColor(0.045, 0.048, 0.055, 0.96)
                frame:SetBackdropBorderColor(0.65, 0.65, 0.70, 0.95)
            else
                frame:SetBackdropColor(0.065, 0.055, 0.045, 0.96)
                frame:SetBackdropBorderColor(0.85, 0.72, 0.45, 0.98) -- Warm bronze/gold
            end
        elseif not isButton and frame.GetBackdrop and frame.SetBackdropColor and frame:GetBackdrop() and not frame.selected then
            local role = frame._marketSyncThemeRole or "inset"
            if role == "inset" and frame.SetBackdrop then
                frame:SetBackdrop({
                    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                if isLegacy then
                    frame:SetBackdropColor(0.04, 0.045, 0.05, 0.90)
                    frame:SetBackdropBorderColor(0.35, 0.38, 0.42, 0.90)
                else
                    frame:SetBackdropColor(0.05, 0.045, 0.04, 0.90)
                    frame:SetBackdropBorderColor(0.50, 0.42, 0.28, 0.95) -- Warm bronze
                end

                if not frame.topHighlight and frame.CreateTexture then
                    local topHighlight = frame:CreateTexture(nil, "BORDER")
                    if topHighlight and topHighlight.SetHeight and topHighlight.SetPoint and topHighlight.SetColorTexture then
                        topHighlight:SetHeight(1)
                        topHighlight:SetPoint("TOPLEFT", 3, -3)
                        topHighlight:SetPoint("TOPRIGHT", -3, -3)
                        topHighlight:SetColorTexture(isLegacy and 0.35 or 0.50, isLegacy and 0.38 or 0.42, isLegacy and 0.42 or 0.28, 0.7)
                        frame.topHighlight = topHighlight
                    end
                end
            else
                frame:SetBackdropColor(MarketSync.GetThemeColor(role))
                frame:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
            end
        end

        if frame.IsObjectType then
            if frame:IsObjectType("Button") then T.Button(frame) end
            if frame:IsObjectType("ScrollFrame") and MarketSync.GetUITheme() == "forever" and not frame._marketSyncThemedScroll then
                frame._marketSyncThemedScroll = true
                if MarketSync.SkinModernScrollBar then MarketSync.SkinModernScrollBar(frame) end
            end
        end

        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
        end
    end

    Walk(root, 0)
    root._marketSyncApplyingTheme = nil
end

-- Decorate a standalone window with a Warcraft portrait emblem ring, centered title banner, and close button
-- matching the authentic WoW Forever / Classic interface framework.
function T.DecorateWarcraftWindow(frame, iconTexture, titleText)
    if not frame then return end

    -- Circular portrait ring hanging off the top-left corner
    if not frame.warcraftRing and frame.CreateTexture then
        local ring = CreateFrame and CreateFrame("Frame", nil, frame) or frame
        if ring and ring.SetSize then
            ring:SetSize(54, 54)
            ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -9, 9)
            local ringLvl = (frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 5
            if ring.SetFrameLevel then ring:SetFrameLevel(ringLvl) end
            frame.warcraftRing = ring

            local ringTex = ring:CreateTexture(nil, "OVERLAY")
            if ringTex and ringTex.SetAllPoints then
                ringTex:SetAllPoints(ring)
                ringTex:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
                frame.warcraftRingTex = ringTex
            end

            local emblem = ring:CreateTexture(nil, "ARTWORK")
            if emblem and emblem.SetSize then
                emblem:SetSize(38, 38)
                emblem:SetPoint("CENTER", ring, "CENTER", 0, 0)
                emblem:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_Coin_01")
                if emblem.SetTexCoord then emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                frame.warcraftEmblem = emblem
            end
        end
    elseif frame.warcraftEmblem and iconTexture then
        frame.warcraftEmblem:SetTexture(iconTexture)
    end

    -- Centered Blizzard header banner plate
    if not frame.warcraftTitleBg and frame.CreateTexture then
        local titleBg = frame:CreateTexture(nil, "ARTWORK")
        if titleBg and titleBg.SetSize then
            titleBg:SetSize(280, 52)
            titleBg:SetPoint("TOP", frame, "TOP", 0, 12)
            titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
            frame.warcraftTitleBg = titleBg
        end
    end

    -- Title text placed in the header banner
    if titleText and frame.CreateFontString and not frame.TitleText then
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", frame, "TOP", 0, 0)
        title:SetText(titleText)
        frame.TitleText = title
    elseif frame.TitleText and titleText then
        frame.TitleText:SetText(titleText)
    end

    -- Close button on top-right
    if not frame.CloseButton and CreateFrame then
        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
        closeBtn:SetScript("OnClick", function() frame:Hide() end)
        frame.CloseButton = closeBtn
    end

    frame._warcraftDecorated = true
end

function T.CreateStandardWindow(name, titleText, width, height, iconTexture)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width or 500, height or 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    T.DecorateWarcraftWindow(frame, iconTexture, titleText)
    if MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(frame) end
    T.Register(frame)
    frame:Hide()
    return frame
end

function T.Register(root)
    if not root or T.roots[root] then return end
    T.roots[root] = true
    if root.HookScript then
        root:HookScript("OnShow", function()
            T.Apply(root)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if root:IsShown() then T.Apply(root) end end)
            end
        end)
    end
end

-- Large related popouts share one workspace when they cannot fit side by side.
-- Their data/selection stays in memory; closing a child restores its source.
function MarketSync.ShowWorkspaceWindow(frame, source)
    local previous = source and source:IsShown() and source or MarketSync.ActiveWorkspaceWindow
    if previous and previous ~= frame and previous:IsShown() and previous.dirty and previous.ConfirmContextSwitch then
        previous.ConfirmContextSwitch(function() MarketSync.ShowWorkspaceWindow(frame, previous) end)
        return
    end
    if previous and previous ~= frame and previous.IsShown and previous:IsShown() then
        if previous._workspacePrevious == frame then previous._workspacePrevious = nil end
        frame._workspacePrevious = previous
        previous._workspaceSuspending = true
        previous:Hide()
        previous._workspaceSuspending = nil
    end
    if not frame._workspaceHooked and frame.HookScript then
        frame._workspaceHooked = true
        frame:HookScript("OnHide", function()
            if frame._workspaceSuspending or frame:IsShown() then return end
            local parent = frame._workspacePrevious
            frame._workspacePrevious = nil
            if parent then
                MarketSync.ActiveWorkspaceWindow = parent
                parent:Show()
                if parent.Refresh then parent:Refresh() end
                T.Apply(parent)
            elseif MarketSync.ActiveWorkspaceWindow == frame then
                MarketSync.ActiveWorkspaceWindow = nil
            end
        end)
    end
    MarketSync.ActiveWorkspaceWindow = frame
    frame:Show()
    T.Apply(frame)
end
