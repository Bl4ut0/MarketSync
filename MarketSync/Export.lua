-- Read-only, chunked text export for external price analysis.
local MS = MarketSync
local MAX_PART_BYTES = 12000

local function Escape(value)
    return (tostring(value or ""):gsub("[^%w%-%._~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function Number(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return "" end
    return tostring(math.floor(n))
end

function MS.BuildDatabaseExportParts(onComplete)
    if type(onComplete) ~= "function" then return false end
    if MS._exportBuilding then return false end
    local realmDB = MS.GetRealmDB and MS.GetRealmDB()
    if not realmDB then return false end
    MS._exportBuilding = true

    local parts, lines, size, recordCount = {}, {}, 0, 0
    local function Flush()
        if size > 0 then
            parts[#parts + 1] = table.concat(lines)
            lines, size = {}, 0
        end
    end
    local function Add(fields)
        local line = table.concat(fields, "\t") .. "\n"
        if size > 0 and size + #line > MAX_PART_BYTES then Flush() end
        lines[#lines + 1] = line
        size = size + #line
        recordCount = recordCount + 1
    end

    local co = coroutine.create(function()
        local processed = 0
        for _, source in ipairs({
            { scope = "M", data = realmDB.PersonalData or {} },
            { scope = "N", data = realmDB.NeutralData or {} },
        }) do
            for key, entry in pairs(source.data) do
                if type(entry) == "table" then
                    local escapedKey = Escape(key)
                    Add({ "I", source.scope, escapedKey, Number(entry.m), Number(entry.d),
                        Number(entry.observedAt), Number(entry.q), Number(entry.latestBucket),
                        Number(entry.vm), Number(entry.vd), Number(entry.vq) })
                    for _, history in ipairs({
                        { kind = "h", data = entry.h },
                        { kind = "vh", data = entry.vh },
                        { kind = "l", data = entry.l },
                        { kind = "a", data = entry.a },
                    }) do
                        if type(history.data) == "table" then
                            for day, value in pairs(history.data) do
                                if value ~= nil then
                                    Add({ "H", source.scope, escapedKey, Escape(day), history.kind, Escape(value) })
                                end
                                processed = processed + 1
                                if processed >= 200 then processed = 0; coroutine.yield() end
                            end
                        end
                    end
                end
                processed = processed + 1
                if processed >= 200 then processed = 0; coroutine.yield() end
            end
        end
        Flush()
        local marketID = MS.Provider and MS.Provider.GetMarketID and MS.Provider.GetMarketID() or "unknown"
        local exportedAt = time()
        local total = #parts
        for i = 1, total do
            parts[i] = table.concat({ "MSX", "1", tostring(i), tostring(total), Escape(marketID),
                tostring(exportedAt), tostring(recordCount) }, "\t") .. "\n" .. parts[i]
        end
        return parts, recordCount
    end)

    local function Step()
        local ok, result, count = coroutine.resume(co)
        if not ok then
            MS._exportBuilding = false
            onComplete(nil, result)
            return
        end
        if coroutine.status(co) == "dead" then
            MS._exportBuilding = false
            onComplete(result, nil, count)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, Step)
        else
            Step()
        end
    end
    Step()
    return true
end

function MS.OpenDatabaseExport()
    if not CreateFrame then return end
    local frame = MS.ExportFrame
    if not frame then
        frame = CreateFrame("Frame", "MarketSyncExportFrame", UIParent, "BackdropTemplate")
        frame:SetSize(620, 400)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("MarketSync Database Export")
        frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.status:SetPoint("TOPLEFT", 22, -45)
        frame.status:SetWidth(575)
        frame.status:SetJustifyH("LEFT")
        local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("BOTTOMLEFT", 22, 48)
        help:SetText("Select All, then Ctrl+C. Paste every numbered part into your importer.")
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 22, -68)
        scroll:SetPoint("BOTTOMRIGHT", -42, 80)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(535)
        edit:SetHeight(275)
        edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        frame.edit = edit
        frame.scroll = scroll
        local function Button(label, x, action)
            local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            button:SetSize(105, 23)
            button:SetPoint("BOTTOMLEFT", x, 18)
            button:SetText(label)
            button:SetScript("OnClick", action)
            return button
        end
        Button("Previous", 22, function() frame:ShowPart((frame.partIndex or 1) - 1) end)
        Button("Next", 135, function() frame:ShowPart((frame.partIndex or 1) + 1) end)
        Button("Select All", 248, function() frame.edit:SetFocus(); frame.edit:HighlightText() end)
        Button("Close", 491, function() frame:Hide() end)
        function frame:ShowPart(index)
            if not self.parts or not self.parts[index] then return end
            self.partIndex = index
            self.edit:SetText(self.parts[index])
            self.edit:SetHeight(math.max(275, self.edit:GetStringHeight() + 16))
            self.scroll:SetVerticalScroll(0)
            self.status:SetText(string.format("Part %d / %d — %d records. Copy each part in order.",
                index, #self.parts, self.recordCount or 0))
        end
        MS.ExportFrame = frame
    end
    frame:Show()
    frame.status:SetText("Preparing export in small batches...")
    frame.edit:SetText("")
    frame.parts = nil
    if not MS.BuildDatabaseExportParts(function(parts, err, count)
        if not parts then
            frame.status:SetText("Export failed: " .. tostring(err))
            return
        end
        frame.parts, frame.recordCount = parts, count
        if #parts == 0 then frame.status:SetText("No main or neutral price records to export.")
        else frame:ShowPart(1) end
    end) then
        frame.status:SetText("An export is already being prepared.")
    end
end
