InCharacter = InCharacter or {}
InCharacter.Flyout = {}

local MAX_VISIBLE = 6
local frame
local rows = {}
local pins = {}

local function GetActiveBeacons()
    local list = {}
    local seen = {}
    local function addBeacon(beacon)
        if not beacon or beacon.status == InCharacter.STATUS.REMOVED then return end
        if beacon.expiresAt and beacon.expiresAt < time() then return end
        if not ZoneMatchesBeacon(beacon) then return end
        if seen[beacon.id] then return end
        seen[beacon.id] = true
        list[#list + 1] = beacon
    end
    local cache = InCharacterDB.cache.beacon or {}
    for _, wrapped in pairs(cache) do
        addBeacon(wrapped.data)
    end
    for _, beacon in pairs(InCharacterDB.beacons or {}) do
        addBeacon(beacon)
    end
    table.sort(list, function(a, b)
        return (a.receivedAt or 0) > (b.receivedAt or 0)
    end)
    return list
end

function ZoneMatchesBeacon(beacon)
    local ctx = InCharacter.GetZoneContext()
    if beacon.zoneId and beacon.zoneId ~= 0 and ctx.zoneId ~= beacon.zoneId then
        return false
    end
    if beacon.subzone and beacon.subzone ~= "" and ctx.subzone ~= "" then
        return ctx.subzone:lower() == beacon.subzone:lower()
    end
    return true
end

local function ClearPins()
    for _, pin in pairs(pins) do
        pin:Hide()
        pin:SetParent(nil)
    end
    wipe(pins)
end

local function CreateMapPin(beacon)
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    local scrollContainer = WorldMapFrame.ScrollContainer
    local button = CreateFrame("Button", nil, scrollContainer.Child)
    button:SetSize(24, 24)
    button:SetFrameStrata("DIALOG")
    local texture = button:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
    local cw = scrollContainer.Child:GetWidth()
    local ch = scrollContainer.Child:GetHeight()
    button:SetPoint("CENTER", scrollContainer.Child, "TOPLEFT", beacon.coords.x * cw, -beacon.coords.y * ch)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(beacon.fullText or beacon.shortText, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    pins[beacon.id] = button
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(280, 22)
    row:SetPoint("TOPLEFT", 8, -28 - (index - 1) * 24)
    row:SetNormalFontObject("GameFontHighlightSmall")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetWidth(260)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 0.9, 0.5)
    end)
    row:SetScript("OnLeave", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    return row
end

function InCharacter.Flyout.Init()
    frame = CreateFrame("Frame", "InCharacterFlyout", UIParent, "BackdropTemplate")
    frame:SetSize(300, 200)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -120)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Nearby presence")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 12, -24)
    subtitle:SetText("Showing discovered beacons in this area")
    frame.subtitle = subtitle

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    for i = 1, MAX_VISIBLE do
        rows[i] = CreateRow(frame, i)
    end

    frame.moreText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.moreText:SetPoint("BOTTOMLEFT", 12, 10)
end

function InCharacter.Flyout.Refresh()
    if not frame then return end
    if not frame:IsShown() then return end
    InCharacter.Flyout.Populate()
end

function InCharacter.Flyout.Populate()
    local beacons = GetActiveBeacons()
    local shown = math.min(#beacons, MAX_VISIBLE)
    for i = 1, MAX_VISIBLE do
        local row = rows[i]
        if i <= shown then
            local beacon = beacons[i]
            row.text:SetText(beacon.shortText or beacon.charName or "Unknown")
            row:Show()
            row:SetScript("OnClick", function()
                if beacon.charName then
                    InCharacter.Comms.RequestBeaconFull(beacon.charName, beacon.id)
                end
                ClearPins()
                CreateMapPin(beacon)
                InCharacter.Print(beacon.fullText or beacon.shortText or "Fetching details...")
            end)
        else
            row:Hide()
        end
    end
    if #beacons > MAX_VISIBLE then
        frame.moreText:SetText("+" .. (#beacons - MAX_VISIBLE) .. " more")
        frame.moreText:Show()
    else
        frame.moreText:Hide()
    end
    frame:SetHeight(56 + shown * 24 + 30)
end

function InCharacter.Flyout.Toggle()
    if frame:IsShown() then
        frame:Hide()
    else
        InCharacter.MinimapButton.ClearNotify()
        InCharacter.Flyout.Populate()
        frame:Show()
    end
end

function InCharacter.Flyout.OnBeaconDiscovered(beacon)
    if not InCharacter.CharDB.settings.quietNotifications then
        InCharacter.MinimapButton.Notify()
    end
    InCharacter.Flyout.Refresh()
end

function InCharacter.Flyout.OnBeaconFullReceived(beacon)
    if beacon then
        InCharacter.Print(beacon.fullText or beacon.shortText or "Beacon received.")
        CacheBeaconFull(beacon)
    end
end

function CacheBeaconFull(beacon)
    InCharacterDB.cache.beacon = InCharacterDB.cache.beacon or {}
    InCharacterDB.cache.beacon[beacon.id] = {
        data = beacon,
        lastConfirmedAt = time(),
    }
    InCharacter.Flyout.Refresh()
end