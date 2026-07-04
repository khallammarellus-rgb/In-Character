InCharacter = InCharacter or {}
InCharacter.PostEditor = {}

local beaconFrame
local noticeFrame

local function CreateBackdropFrame(name, width, height, point, relPoint, x, y)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint(point, UIParent, relPoint, x, y)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:Hide()
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

local function CreateDropdown(parent, name, items, x, y, width)
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, width or 140)
    dropdown.items = items
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for i, item in ipairs(self.items) do
            info.text = item
            info.value = item
            info.func = function(btn)
                UIDropDownMenu_SetSelectedID(dropdown, btn:GetID())
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedID(dropdown, 1)
    return dropdown
end

local function GetDropdownValue(dropdown)
    local id = UIDropDownMenu_GetSelectedID(dropdown)
    return dropdown.items and dropdown.items[id] or dropdown.items[1]
end

local function BuildBeaconEditor()
    beaconFrame = CreateBackdropFrame("InCharacterBeaconEditor", 420, 280, "CENTER", "CENTER", 0, 40)
    local title = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Broadcast presence")

    local templateLabel = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    templateLabel:SetPoint("TOPLEFT", 16, -40)
    templateLabel:SetText("Phrase template")

    local templates = InCharacter.SentenceTemplates.GetTemplates()
    local templateNames = {}
    for _, t in ipairs(templates) do
        templateNames[#templateNames + 1] = t.label
    end
    beaconFrame.templateDropdown = CreateDropdown(beaconFrame, "ICBeaconTemplate", templateNames, 16, -58, 180)

    beaconFrame.slotDropdowns = {}
    local slotNames = { "disposition", "role", "intent" }
    local y = -100
    for i, slot in ipairs(slotNames) do
        local label = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 16, y)
        label:SetText(slot:sub(1, 1):upper() .. slot:sub(2))
        beaconFrame.slotDropdowns[slot] = CreateDropdown(beaconFrame, "ICBeacon" .. slot, InCharacter.SentenceTemplates.GetSlotOptions(slot), 120, y + 10, 160)
        y = y - 40
    end

    beaconFrame.preview = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    beaconFrame.preview:SetPoint("TOPLEFT", 16, -220)
    beaconFrame.preview:SetWidth(380)
    beaconFrame.preview:SetJustifyH("LEFT")
    beaconFrame.preview:SetText("")

    local broadcast = CreateFrame("Button", nil, beaconFrame, "UIPanelButtonTemplate")
    broadcast:SetSize(120, 24)
    broadcast:SetPoint("BOTTOMRIGHT", -16, 16)
    broadcast:SetText("Broadcast")
    broadcast:SetScript("OnClick", function()
        local templateIndex = UIDropDownMenu_GetSelectedID(beaconFrame.templateDropdown) or 1
        local template = templates[templateIndex]
        if not template then return end
        local slots = {}
        for _, slot in ipairs(template.slots) do
            slots[slot] = GetDropdownValue(beaconFrame.slotDropdowns[slot])
        end
        local beacon = InCharacter.Lifecycle.CreateBeacon(template.id, slots)
        if not beacon then return end
        InCharacter.Lifecycle.PostBeacon(beacon)
        InCharacter.Print("Beacon broadcast.")
        beaconFrame:Hide()
    end)

    local previewBtn = CreateFrame("Button", nil, beaconFrame, "UIPanelButtonTemplate")
    previewBtn:SetSize(80, 24)
    previewBtn:SetPoint("RIGHT", broadcast, "LEFT", -8, 0)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        local templateIndex = UIDropDownMenu_GetSelectedID(beaconFrame.templateDropdown) or 1
        local template = templates[templateIndex]
        local slots = {}
        for _, slot in ipairs(template.slots) do
            slots[slot] = GetDropdownValue(beaconFrame.slotDropdowns[slot])
        end
        local resolved = InCharacter.SentenceTemplates.Resolve(template.id, slots, InCharacter.CharDB.residence)
        beaconFrame.preview:SetText(resolved and resolved.fullText or "")
    end)

    local sayBtn = CreateFrame("Button", nil, beaconFrame, "UIPanelButtonTemplate")
    sayBtn:SetSize(100, 24)
    sayBtn:SetPoint("BOTTOMLEFT", 16, 16)
    sayBtn:SetText("Also /say")
    sayBtn:SetScript("OnClick", function()
        local text = beaconFrame.preview:GetText()
        if text and text ~= "" then
            SendChatMessage(text, "SAY")
        end
    end)
end

local function BuildNoticeEditor()
    noticeFrame = CreateBackdropFrame("InCharacterNoticeEditor", 440, 360, "CENTER", "CENTER", 0, -20)
    local title = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Post a notice")

    local defaults = InCharacter.TRP3Bridge.GetProfileDefaults()

    local titleLabel = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleLabel:SetPoint("TOPLEFT", 16, -44)
    titleLabel:SetText("Title")

    noticeFrame.titleEdit = CreateFrame("EditBox", nil, noticeFrame, "InputBoxTemplate")
    noticeFrame.titleEdit:SetSize(380, 24)
    noticeFrame.titleEdit:SetPoint("TOPLEFT", 16, -62)
    noticeFrame.titleEdit:SetAutoFocus(false)

    local bodyLabel = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bodyLabel:SetPoint("TOPLEFT", 16, -96)
    bodyLabel:SetText("Notice text (in-character)")

    noticeFrame.bodyEdit = CreateFrame("EditBox", nil, noticeFrame, "InputBoxTemplate")
    noticeFrame.bodyEdit:SetSize(380, 80)
    noticeFrame.bodyEdit:SetMultiLine(true)
    noticeFrame.bodyEdit:SetPoint("TOPLEFT", 16, -114)
    noticeFrame.bodyEdit:SetAutoFocus(false)

    local guided = string.format(
        "I, %s, of %s, seek %s",
        defaults and defaults.charName or UnitName("player"),
        InCharacter.CharDB.residence ~= "" and InCharacter.CharDB.residence or "[your residence]",
        "[your request]"
    )
    noticeFrame.bodyEdit:SetText(guided)

    local residenceLabel = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    residenceLabel:SetPoint("TOPLEFT", 16, -200)
    residenceLabel:SetText("Residence (remembered per character)")

    noticeFrame.residenceEdit = CreateFrame("EditBox", nil, noticeFrame, "InputBoxTemplate")
    noticeFrame.residenceEdit:SetSize(200, 24)
    noticeFrame.residenceEdit:SetPoint("TOPLEFT", 16, -218)
    noticeFrame.residenceEdit:SetText(InCharacter.CharDB.residence or "")
    noticeFrame.residenceEdit:SetAutoFocus(false)

    local scopeLabel = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scopeLabel:SetPoint("TOPLEFT", 240, -200)
    scopeLabel:SetText("Seal / scope")

    local scopes = { "INDIVIDUAL", "GROUP", "GUILD", "FACTION" }
    noticeFrame.scopeDropdown = CreateDropdown(noticeFrame, "ICNoticeScope", scopes, 240, -212, 120)

    local board = InCharacter.Boards.GetNearbyBoard()
    noticeFrame.boardHint = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noticeFrame.boardHint:SetPoint("TOPLEFT", 16, -248)
    noticeFrame.boardHint:SetWidth(400)
    noticeFrame.boardHint:SetJustifyH("LEFT")

    local post = CreateFrame("Button", nil, noticeFrame, "UIPanelButtonTemplate")
    post:SetSize(100, 24)
    post:SetPoint("BOTTOMRIGHT", -16, 16)
    post:SetText("Post")
    post:SetScript("OnClick", function()
        local nearby = InCharacter.Boards.GetNearbyBoard()
        if not nearby then
            InCharacter.Print("Stand near a notice board to post.")
            return
        end
        local titleText = noticeFrame.titleEdit:GetText() or ""
        local bodyText = noticeFrame.bodyEdit:GetText() or ""
        InCharacter.TRP3Bridge.RememberResidence(noticeFrame.residenceEdit:GetText())

        local function doPost()
            local scopeIndex = UIDropDownMenu_GetSelectedID(noticeFrame.scopeDropdown) or 1
            local notice = InCharacter.Lifecycle.CreateNotice(titleText, bodyText, nearby.id, scopes[scopeIndex])
            InCharacter.Lifecycle.PostNotice(notice)
            InCharacter.Print("Notice posted to " .. nearby.displayName .. ".")
            noticeFrame:Hide()
            InCharacter.BoardView.Show()
        end

        if InCharacter.ProfanityFilter.ValidateNotice(titleText, bodyText, doPost) then
            doPost()
        end
    end)

    local boardBtn = CreateFrame("Button", nil, noticeFrame, "UIPanelButtonTemplate")
    boardBtn:SetSize(120, 24)
    boardBtn:SetPoint("BOTTOMLEFT", 16, 16)
    boardBtn:SetText("View board")
    boardBtn:SetScript("OnClick", function()
        InCharacter.BoardView.Show()
    end)
end

function InCharacter.PostEditor.Init()
    BuildBeaconEditor()
    BuildNoticeEditor()
end

function InCharacter.PostEditor.ShowBeaconEditor()
    if beaconFrame then
        beaconFrame:Show()
    end
end

function InCharacter.PostEditor.ShowNoticeEditor()
    if noticeFrame then
        local board = InCharacter.Boards.GetNearbyBoard()
        if noticeFrame.boardHint then
            if board then
                noticeFrame.boardHint:SetText("Posting to: " .. board.displayName)
            else
                noticeFrame.boardHint:SetText("No board in range — move closer to a Hero's Call board to post.")
            end
        end
        noticeFrame:Show()
    end
end