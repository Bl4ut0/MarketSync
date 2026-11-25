-- Shared styling for MarketSync-owned windows; never walk the native AH root.
MarketSync.Theme = { roots = setmetatable({}, { __mode = "k" }) }
local T = MarketSync.Theme

-- Original MarketSync 0.4-0.7 Auction House artwork. Keep the 256px top
-- corners and 191px footer intact; extend only the middle on larger windows.
-- All pieces stay behind controls (the archived OVERLAY footer hid content).
function T.ApplyLegacyAuctionFrame(frame)
    if not frame or not (MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme())
        or not frame.CreateTexture or not frame.GetWidth or not frame.GetHeight then return false end
    local width, height = frame:GetWidth(), frame:GetHeight()
    local art = frame._marketSyncLegacyAuctionArt
    if width < 600 or height < 447 then
        if art and art.active then
            for _, texture in pairs(art.pieces) do texture:Hide() end
            if art.portraitOverlay then art.portraitOverlay:Hide() end
            art.active = false
            if frame.SetBackdrop then
                frame:SetBackdrop({ bgFile = "Interface\\AddOns\\MarketSync\\Media\\LegacyStoneCanvas",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 64, edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 } })
                frame:SetBackdropColor(0.95, 0.92, 0.88, 0.98)
                frame:SetBackdropBorderColor(0.85, 0.72, 0.45, 0.98)
            end
        end
        return false
    end
    if art and art.failed then return false end
    if not art then
        art = { pieces = {} }
        frame._marketSyncLegacyAuctionArt = art
        local pieces = {
            { "topLeft", "TopLeft" }, { "top", "Top" }, { "topRight", "TopRight" },
            { "bottomLeft", "BotLeft" }, { "bottom", "Bot" }, { "bottomRight", "BotRight" },
            { "fillLeft", "TopLeft", true }, { "fill", "Top", true }, { "fillRight", "TopRight", true },
            { "footerCover", "Bot" },
        }
        for _, piece in ipairs(pieces) do
            local texture = frame:CreateTexture(nil, "ARTWORK", nil, piece[1] == "footerCover" and -7 or -8)
            art.pieces[piece[1]] = texture
            local ok, result = pcall(texture.SetTexture, texture, "Interface\\AuctionFrame\\UI-AuctionFrame-Browse-" .. piece[2])
            if not ok or result == false then art.failed = true end
            texture:SetTexCoord(0, piece[1] == "footerCover" and 0.75 or 1,
                piece[3] and 0.5 or 0, piece[3] and 0.75 or (piece[2]:find("Bot") and 191 / 256 or 1))
        end
        if art.failed then
            -- Some client builds omit the Classic assets. Leave the textured
            -- dialog fallback intact instead of showing an incomplete shell.
            for _, texture in pairs(art.pieces) do texture:Hide() end
            return false
        end

        -- Seamless dark stone interior & footer fill so baked-in Classic Browse
        -- lines (search trough, x=180 divider wall, money cutout) never bleed
        -- behind custom layouts or text while keeping the outer Classic frame.
        local canvasTex = "Interface\\AddOns\\MarketSync\\Media\\LegacyStoneCanvas"
        local interiorCanvas = frame:CreateTexture(nil, "ARTWORK", nil, -6)
        interiorCanvas:SetTexture(canvasTex, "REPEAT", "REPEAT")
        if interiorCanvas.SetHorizTile then interiorCanvas:SetHorizTile(true) end
        if interiorCanvas.SetVertTile then interiorCanvas:SetVertTile(true) end
        art.pieces.interiorCanvas = interiorCanvas

        local footerCanvas = frame:CreateTexture(nil, "ARTWORK", nil, -6)
        footerCanvas:SetTexture(canvasTex, "REPEAT", "REPEAT")
        if footerCanvas.SetHorizTile then footerCanvas:SetHorizTile(true) end
        if footerCanvas.SetVertTile then footerCanvas:SetVertTile(true) end
        if footerCanvas.SetVertexColor then footerCanvas:SetVertexColor(0.82, 0.80, 0.78, 1) end
        art.pieces.footerCanvas = footerCanvas

        local footerDivider = frame:CreateTexture(nil, "ARTWORK", nil, -5)
        footerDivider:SetColorTexture(0.32, 0.28, 0.20, 0.85)
        art.pieces.footerDivider = footerDivider

        -- Keep the circular top-left portrait and its Classic stone bezel
        -- cleanly above the seamless interior stone canvas.
        if CreateFrame then
            local pOverlay = CreateFrame("Frame", nil, frame)
            if pOverlay then
                if pOverlay.SetAllPoints then pOverlay:SetAllPoints(frame) end
                if pOverlay.EnableMouse then pOverlay:EnableMouse(false) end
                local baseLvl = frame.GetFrameLevel and frame:GetFrameLevel() or 1
                if pOverlay.SetFrameLevel then pOverlay:SetFrameLevel(baseLvl + 5) end
                if pOverlay.CreateMaskTexture and pOverlay.CreateTexture then
                    local bezel = pOverlay:CreateTexture(nil, "OVERLAY")
                    bezel:SetSize(72, 72)
                    bezel:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, 0)
                    bezel:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft")
                    bezel:SetTexCoord(1 / 256, 73 / 256, 0, 72 / 256)
                    local bMask = pOverlay:CreateMaskTexture()
                    if bMask and bMask.SetTexture then
                        bMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                        if bMask.SetAllPoints then
                            bMask:SetAllPoints(bezel)
                        else
                            if bMask.SetSize then bMask:SetSize(72, 72) end
                            if bMask.SetPoint then bMask:SetPoint("CENTER", bezel, "CENTER", 0, 0) end
                        end
                        if bezel.AddMaskTexture then bezel:AddMaskTexture(bMask) end
                    end
                    art.portraitBezel = bezel
                end
                art.portraitOverlay = pOverlay
            end
        end

        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function() T.ApplyLegacyAuctionFrame(frame) end)
        end
    end
    local function Place(name, w, h, point, x, y)
        local texture = art.pieces[name]
        texture:ClearAllPoints()
        texture:SetSize(w, math.max(1, h))
        texture:SetPoint(point, frame, point, x, y)
        if h > 0 then texture:Show() else texture:Hide() end
    end
    Place("topLeft", 256, 256, "TOPLEFT", 0, 0)
    Place("top", width - 512, 256, "TOPLEFT", 256, 0)
    Place("topRight", 256, 256, "TOPRIGHT", 0, 0)
    Place("bottomLeft", 256, 191, "BOTTOMLEFT", 0, 0)
    Place("bottom", width - 512, 191, "BOTTOMLEFT", 256, 0)
    Place("bottomRight", 256, 191, "BOTTOMRIGHT", 0, 0)
    Place("fillLeft", 256, height - 447, "TOPLEFT", 0, -256)
    Place("fill", width - 512, height - 447, "TOPLEFT", 256, -256)
    Place("fillRight", 256, height - 447, "TOPRIGHT", 0, -256)
    -- The original clean footer patch covers unused auction money wells.
    Place("footerCover", 260, 191, "BOTTOMRIGHT", -5, 0)

    -- Exact measured inner lip of UI-AuctionFrame-Browse-* (832x447):
    -- Left outer grey/silver rim spans x=12..15 (inner edge x=16); right rim starts at -4;
    -- Top title-bar silver lip ends at y=-36; bottom outer silver rim ends at y=14.
    local canvasW = math.max(1, width - 20)
    local canvasH = math.max(1, height - 74)
    Place("interiorCanvas", canvasW, canvasH, "TOPLEFT", 16, -36)
    if not art.pieces.interiorCanvas.SetHorizTile then
        art.pieces.interiorCanvas:SetTexCoord(0, canvasW / 64, 0, canvasH / 64)
    end
    Place("footerCanvas", canvasW, 23, "BOTTOMLEFT", 16, 14)
    if not art.pieces.footerCanvas.SetHorizTile then
        art.pieces.footerCanvas:SetTexCoord(0, canvasW / 64, 0, 23 / 64)
    end
    Place("footerDivider", canvasW, 1, "BOTTOMLEFT", 16, 37)
    if frame._marketSyncHideLegacyCanvas then
        art.pieces.interiorCanvas:Hide()
        art.pieces.footerCanvas:Hide()
        art.pieces.footerDivider:Hide()
    end
    if art.portraitOverlay then
        local baseLvl = frame.GetFrameLevel and frame:GetFrameLevel() or 1
        if art.portraitOverlay.SetFrameLevel then art.portraitOverlay:SetFrameLevel(baseLvl + 5) end
        art.portraitOverlay:Show()
    end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    art.active = true
    return true
end

function T.SetLegacyCanvasVisible(frame, visible)
    if not frame then return end
    frame._marketSyncHideLegacyCanvas = not visible
    local art = frame._marketSyncLegacyAuctionArt
    if not art or not art.active or not art.pieces then return end
    local show = visible and true or false
    if art.pieces.interiorCanvas then art.pieces.interiorCanvas:SetShown(show) end
    if art.pieces.footerCanvas then art.pieces.footerCanvas:SetShown(show) end
    if art.pieces.footerDivider then art.pieces.footerDivider:SetShown(show) end
end

function T.ApplyLegacyCompactFrame(frame)
    if not frame or not frame._marketSyncCompactLegacyShell
        or not (MarketSync.IsLegacyUITheme and MarketSync.IsLegacyUITheme())
        or not frame.CreateTexture then return false end
    local rawW = frame.GetWidth and frame:GetWidth() or 0
    local rawH = frame.GetHeight and frame:GetHeight() or 0
    local width = rawW >= 220 and rawW or 330
    local height = rawH >= 180 and rawH or 390
    local art = frame._marketSyncCompactLegacyArt
    if art and art.failed then return false end
    if not art then
        art = { pieces = {} }
        frame._marketSyncCompactLegacyArt = art
        local defs = {
            { "topLeft", "TopLeft" }, { "top", "Top" }, { "topRight", "TopRight" },
            { "bottomLeft", "BotLeft" }, { "bottom", "Bot" }, { "bottomRight", "BotRight" },
        }
        for _, def in ipairs(defs) do
            local tex = frame:CreateTexture(nil, "ARTWORK", nil, -8)
            art.pieces[def[1]] = tex
            local ok, res = pcall(tex.SetTexture, tex, "Interface\\AuctionFrame\\UI-AuctionFrame-Browse-" .. def[2])
            if not ok or res == false then art.failed = true end
        end
        if art.failed then
            for _, tex in pairs(art.pieces) do tex:Hide() end
            return false
        end
        local canvasTex = "Interface\\AddOns\\MarketSync\\Media\\LegacyStoneCanvas"
        local interior = frame:CreateTexture(nil, "ARTWORK", nil, -6)
        interior:SetTexture(canvasTex, "REPEAT", "REPEAT")
        if interior.SetHorizTile then interior:SetHorizTile(true) end
        if interior.SetVertTile then interior:SetVertTile(true) end
        art.pieces.interiorCanvas = interior

        if CreateFrame then
            local pOverlay = CreateFrame("Frame", nil, frame)
            if pOverlay then
                if pOverlay.SetAllPoints then pOverlay:SetAllPoints(frame) end
                if pOverlay.EnableMouse then pOverlay:EnableMouse(false) end
                local baseLvl = frame.GetFrameLevel and frame:GetFrameLevel() or 1
                if pOverlay.SetFrameLevel then pOverlay:SetFrameLevel(baseLvl + 5) end
                if pOverlay.CreateMaskTexture and pOverlay.CreateTexture then
                    local bezel = pOverlay:CreateTexture(nil, "OVERLAY")
                    bezel:SetSize(58, 58)
                    bezel:SetPoint("TOPLEFT", frame, "TOPLEFT", -7, 2)
                    bezel:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft")
                    bezel:SetTexCoord(1 / 256, 73 / 256, 0, 72 / 256)
                    local bMask = pOverlay:CreateMaskTexture()
                    if bMask and bMask.SetTexture then
                        bMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                        if bMask.SetAllPoints then
                            bMask:SetAllPoints(bezel)
                        else
                            if bMask.SetSize then bMask:SetSize(58, 58) end
                            if bMask.SetPoint then bMask:SetPoint("CENTER", bezel, "CENTER", 0, 0) end
                        end
                        if bezel.AddMaskTexture then bezel:AddMaskTexture(bMask) end
                    end
                    art.portraitBezel = bezel
                end
                art.portraitOverlay = pOverlay
            end
        end
        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function() T.ApplyLegacyCompactFrame(frame) end)
        end
    end

    local cornerW = math.min(145, math.floor(width * 0.45))
    local midW = math.max(1, width - cornerW * 2)
    local hTop = math.min(240, math.max(96, math.floor(height * 0.56)))
    local hBot = math.max(60, height - hTop)
    local botCropH = math.min(169, hBot)

    local function SetPiece(name, w, h, point, x, y, u1, u2, v1, v2)
        local tex = art.pieces[name]
        tex:ClearAllPoints()
        tex:SetSize(math.max(1, w), math.max(1, h))
        tex:SetPoint(point, frame, point, x, y)
        tex:SetTexCoord(u1, u2, v1, v2)
        tex:Show()
    end

    -- Crop the 11px transparent left/bottom overhang off Browse pieces so the
    -- silver/iron border sits flush with compact windows (e.g. Sidecar).
    SetPiece("topLeft", cornerW, hTop, "TOPLEFT", 0, 0, 11 / 256, (11 + cornerW) / 256, 0, hTop / 256)
    SetPiece("top", midW, hTop, "TOPLEFT", cornerW, 0, 0, 1, 0, hTop / 256)
    SetPiece("topRight", cornerW, hTop, "TOPRIGHT", 0, 0, (256 - cornerW) / 256, 1, 0, hTop / 256)
    SetPiece("bottomLeft", cornerW, hBot, "BOTTOMLEFT", 0, 0, 11 / 256, (11 + cornerW) / 256, (180 - botCropH) / 256, 180 / 256)
    SetPiece("bottom", midW, hBot, "BOTTOMLEFT", cornerW, 0, 0, 1, (180 - botCropH) / 256, 180 / 256)
    SetPiece("bottomRight", cornerW, hBot, "BOTTOMRIGHT", 0, 0, (256 - cornerW) / 256, 1, (180 - botCropH) / 256, 180 / 256)

    -- Exact measured inner lip of cropped compact Browse pieces (u1=11/256, v2=180/256):
    -- Left grey/silver rim spans x=1..4 (inner edge x=5); right silver rim starts at -4;
    -- Top title-bar silver lip ends at y=-36; bottom silver rim ends at y=4.
    local inner = art.pieces.interiorCanvas
    inner:ClearAllPoints()
    inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -36)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    if not inner.SetHorizTile then
        inner:SetTexCoord(0, math.max(1, width - 9) / 64, 0, math.max(1, height - 40) / 64)
    end
    inner:Show()

    if art.portraitOverlay then
        local baseLvl = frame.GetFrameLevel and frame:GetFrameLevel() or 1
        if art.portraitOverlay.SetFrameLevel then art.portraitOverlay:SetFrameLevel(baseLvl + 5) end
        art.portraitOverlay:Show()
    end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    art.active = true
    return true
end

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

        local hasNativeBorder = (type(frame.PortraitContainer) == "table")
            or (type(frame.TitleContainer) == "table" and (not isLegacy or frame.TitleContainer ~= frame))
            or (type(frame.NineSlice) == "table")
        if frame == root and not hasNativeBorder and frame.SetBackdrop and frame.GetBackdrop and frame:GetBackdrop() then
            -- Root dialog window uses authentic Blizzard dialog textures with sleek dark stone background
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            frame:SetBackdropColor(0.065, 0.055, 0.045, 0.96)
            frame:SetBackdropBorderColor(0.85, 0.72, 0.45, 0.98) -- Warm bronze/gold
        elseif not isButton and not frame._marketSyncSkipTheme and frame.GetBackdrop and frame.SetBackdropColor and frame:GetBackdrop() and not frame.selected then
            local role = frame._marketSyncThemeRole or "inset"
            if role == "inset" and frame.SetBackdrop then
                frame:SetBackdrop({
                    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 },
                })
                frame:SetBackdropColor(0.05, 0.045, 0.04, isLegacy and 0.96 or 0.90)
                frame:SetBackdropBorderColor(0.50, 0.42, 0.28, 0.95) -- Warm bronze

                if not frame.topHighlight and frame.CreateTexture then
                    local topHighlight = frame:CreateTexture(nil, "BORDER")
                    if topHighlight and topHighlight.SetHeight and topHighlight.SetPoint and topHighlight.SetColorTexture then
                        topHighlight:SetHeight(1)
                        topHighlight:SetPoint("TOPLEFT", 3, -3)
                        topHighlight:SetPoint("TOPRIGHT", -3, -3)
                        topHighlight:SetColorTexture(0.50, 0.42, 0.28, 0.7)
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
            if frame:IsObjectType("ScrollFrame") and not frame._marketSyncThemedScroll then
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

    if (type(frame.PortraitContainer) == "table") or (type(frame.TitleContainer) == "table") or (type(frame.NineSlice) == "table") then
        -- Native PortraitFrameTemplate: set portrait texture and title directly
        local portrait = (frame.GetPortrait and frame:GetPortrait())
            or (type(frame.PortraitContainer) == "table" and frame.PortraitContainer.portrait)
            or frame.portrait or _G[(frame.GetName and frame:GetName() or "") .. "Portrait"]
        if portrait then
            if SetPortraitToAsset then
                SetPortraitToAsset(portrait, iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
            elseif portrait.SetTexture then
                portrait:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                if portrait.SetTexCoord then portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            end
        end
        local title = (frame.GetTitleText and frame:GetTitleText())
            or (type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText)
            or frame.TitleText or frame.titleText or _G[(frame.GetName and frame:GetName() or "") .. "TitleText"]
        if title and titleText and title.SetText then
            title:SetText(titleText)
            frame.TitleText = title
        end
        return
    end

    if T.ApplyLegacyAuctionFrame(frame) then
        local art = frame._marketSyncLegacyAuctionArt
        local pHost = (art and art.portraitOverlay) or frame
        local portrait = frame.portrait or pHost:CreateTexture(nil, "ARTWORK")
        if portrait.SetParent and art and art.portraitOverlay then
            portrait:SetParent(art.portraitOverlay)
        end
        portrait:SetSize(58, 58)
        portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
        local texPath = iconTexture or "Interface\\Icons\\INV_Misc_Coin_01"
        if SetPortraitToAsset then
            SetPortraitToAsset(portrait, texPath)
        elseif SetPortraitToTexture then
            SetPortraitToTexture(portrait, texPath)
        else
            portrait:SetTexture(texPath)
        end
        if not portrait._circleMask and frame.CreateMaskTexture and portrait.AddMaskTexture then
            local mask = frame:CreateMaskTexture()
            if mask and mask.SetTexture then
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                if mask.SetAllPoints then
                    mask:SetAllPoints(portrait)
                else
                    if mask.SetSize then mask:SetSize(58, 58) end
                    if mask.SetPoint then mask:SetPoint("CENTER", portrait, "CENTER", 0, 0) end
                end
                portrait:AddMaskTexture(mask)
                portrait._circleMask = mask
            end
        end
        frame.portrait = portrait
        local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:ClearAllPoints()
        title:SetPoint("TOP", frame, "TOP", 0, -19)
        title:SetText(titleText or "MarketSync")
        frame.TitleText = title
        local close = frame.CloseButton or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 3, -8)
        close:SetScript("OnClick", function() frame:Hide() end)
        frame.CloseButton = close
        frame._warcraftDecorated = true
        return
    end

    if T.ApplyLegacyCompactFrame(frame) then
        local art = frame._marketSyncCompactLegacyArt
        local pHost = (art and art.portraitOverlay) or frame
        local portrait = frame.portrait or pHost:CreateTexture(nil, "ARTWORK")
        if portrait.SetParent and art and art.portraitOverlay then
            portrait:SetParent(art.portraitOverlay)
        end
        portrait:SetSize(46, 46)
        portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, -4)
        local texPath = iconTexture or "Interface\\Icons\\INV_Misc_Coin_01"
        if SetPortraitToAsset then
            SetPortraitToAsset(portrait, texPath)
        elseif SetPortraitToTexture then
            SetPortraitToTexture(portrait, texPath)
        else
            portrait:SetTexture(texPath)
        end
        if not portrait._circleMask and pHost.CreateMaskTexture and portrait.AddMaskTexture then
            local mask = pHost:CreateMaskTexture()
            if mask and mask.SetTexture then
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                if mask.SetAllPoints then
                    mask:SetAllPoints(portrait)
                else
                    if mask.SetSize then mask:SetSize(46, 46) end
                    if mask.SetPoint then mask:SetPoint("CENTER", portrait, "CENTER", 0, 0) end
                end
                portrait:AddMaskTexture(mask)
                portrait._circleMask = mask
            end
        end
        frame.portrait = portrait
        local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:ClearAllPoints()
        title:SetPoint("TOP", frame, "TOP", 12, -20)
        title:SetText(titleText or "MarketSync")
        frame.TitleText = title
        local close = frame.CloseButton or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 3, -7)
        close:SetScript("OnClick", function() frame:Hide() end)
        frame.CloseButton = close
        frame._warcraftDecorated = true
        return
    end

    -- Circular portrait ring hanging off the top-left corner
    if not frame.warcraftRing and frame.CreateTexture then
        local ring = CreateFrame and CreateFrame("Frame", nil, frame) or frame
        if ring and ring.SetSize then
            ring:SetSize(52, 52)
            ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 8)
            local ringLvl = (frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 5
            if ring.SetFrameLevel then ring:SetFrameLevel(ringLvl) end
            frame.warcraftRing = ring

            local ringTex = ring:CreateTexture(nil, "OVERLAY")
            if ringTex and ringTex.SetAllPoints then
                ringTex:SetAllPoints(ring)
                ringTex:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
                if ringTex.SetTexCoord then ringTex:SetTexCoord(0, 0.59375, 0, 0.59375) end
                frame.warcraftRingTex = ringTex
            end

            local emblem = ring:CreateTexture(nil, "ARTWORK")
            if emblem and emblem.SetSize then
                local texPath = iconTexture or "Interface\\Icons\\INV_Misc_Coin_01"
                emblem:SetSize(36, 36)
                emblem:SetPoint("CENTER", ring, "CENTER", 0, 0)
                if SetPortraitToTexture then
                    SetPortraitToTexture(emblem, texPath)
                else
                    emblem:SetTexture(texPath)
                    if emblem.SetTexCoord then emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                end
                if ring.CreateMaskTexture and emblem.AddMaskTexture then
                    local mask = ring:CreateMaskTexture()
                    if mask and mask.SetTexture then
                        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                        if mask.SetAllPoints then
                            mask:SetAllPoints(emblem)
                        else
                            if mask.SetSize then mask:SetSize(36, 36) end
                            if mask.SetPoint then mask:SetPoint("CENTER", emblem, "CENTER", 0, 0) end
                        end
                        emblem:AddMaskTexture(mask)
                    end
                end
                frame.warcraftEmblem = emblem
            end
        end
    elseif frame.warcraftEmblem and iconTexture then
        if SetPortraitToTexture then
            SetPortraitToTexture(frame.warcraftEmblem, iconTexture)
        else
            frame.warcraftEmblem:SetTexture(iconTexture)
        end
    end

    -- Centered Blizzard header banner plate
    if not frame.warcraftTitleBg and frame.CreateTexture then
        local titleBg = frame:CreateTexture(nil, "ARTWORK")
        if titleBg and titleBg.SetSize then
            local frameW = frame.GetWidth and frame:GetWidth() or 400
            local bannerW = (frameW > 0 and frameW < 360) and 236 or 280
            titleBg:SetSize(bannerW, 48)
            titleBg:SetPoint("TOP", frame, "TOP", (frameW > 0 and frameW < 360) and 10 or 0, 11)
            titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
            frame.warcraftTitleBg = titleBg
        end
    end

    -- Title text placed in the header banner
    if titleText and frame.CreateFontString and not frame.TitleText then
        local frameW = frame.GetWidth and frame:GetWidth() or 400
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", frame, "TOP", (frameW > 0 and frameW < 360) and 10 or 0, -1)
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

function T.CreateStandardWindow(name, titleText, width, height, iconTexture, docked)
    local frame
    if not MarketSync.IsLegacyUITheme() then
        local ok, portraitFrame = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
        if ok then frame = portraitFrame end
    end
    if not frame then
        frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(MarketSync.GetThemeColor("dialog"))
        frame:SetBackdropBorderColor(MarketSync.GetThemeColor("border"))
    end
    frame:SetSize(width or 500, height or 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    if docked or name == "MarketSyncSmartRulesFrame" or name == "MarketSyncUserMgmt" then
        frame._marketSyncCompactLegacyShell = true
    end

    T.DecorateWarcraftWindow(frame, iconTexture, titleText)
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end
    if not docked and MarketSync.RegisterEscapeFrame then MarketSync.RegisterEscapeFrame(frame) end
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
