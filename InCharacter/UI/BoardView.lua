InCharacter = InCharacter or {}
InCharacter.BoardView = {}

local frame
local rows = {}
local MAX_VISIBLE = 6
local currentBoard
local nearbyNotices = {}

local function GetNoticesForBoard(boardId)
    local list = {}
    for _, notice in pairs(nearbyNotices) do
        if notice.boardId == boardId then
            if not notice.expiresAt or notice.expiresAt >= time() then
                list[#list + 1] = notice
            end
        end
    end
    table.sort(list, function(a, b)
        return (a.receivedAt or 0) > (b.receivedAt or 0)
    end)
    return list
end

function InCharacter.BoardView.Init()
    frame = CreateFrame("Frame", "InCharacterBoardView", UIParent, "BackdropTemplate")
    frame:SetSize(320, 220)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -340)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("Notice board")

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", 12, -26)
    frame.hint:SetText("Known notices at this board")

    for i = 1, MAX_VISIBLE do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(300, 22)
        row:SetPoint("TOPLEFT", 8, -44 - (i - 1) * 24)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetWidth(280)
        row.text:SetJustifyH("LEFT")
        rows[i] = row
    end

    local ticker = CreateFrame("Frame")
    ticker:RegisterEvent("ZONE_CHANGED")
    ticker:RegisterEvent("ZONE_CHANGED_INDOORS")
    ticker:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ticker:SetScript("OnEvent", function()
        InCharacter.BoardView.CheckProximity()
    end)
    C_Timer.NewTicker(10, InCharacter.BoardView.CheckProximity)
end

function InCharacter.BoardView.CheckProximity()
    local board = InCharacter.Boards.GetNearbyBoard()
    if board and board.id ~= (currentBoard and currentBoard.id) then
        currentBoard = board
        wipe(nearbyNotices)
        InCharacter.Comms.BroadcastBoardQuery(board.id)
        if frame then
            frame.title:SetText(board.displayName)
        end
    elseif not board then
        currentBoard = nil
    end
end

function InCharacter.BoardView.Refresh()
    if not frame or not frame:IsShown() or not currentBoard then return end
    InCharacter.BoardView.Populate(currentBoard.id)
end

function InCharacter.BoardView.Populate(boardId)
    local notices = GetNoticesForBoard(boardId)
    local shown = math.min(#notices, MAX_VISIBLE)
    for i = 1, MAX_VISIBLE do
        local row = rows[i]
        if i <= shown then
            local notice = notices[i]
            local seal = notice.scopeTier and ("[" .. notice.scopeTier:sub(1, 1) .. "] ") or ""
            row.text:SetText(seal .. (notice.title or "Notice"))
            row:Show()
            row:SetScript("OnClick", function()
                if notice.charName then
                    InCharacter.Comms.RequestNoticeFull(notice.charName, notice.id)
                end
            end)
        else
            row:Hide()
        end
    end
    frame:SetHeight(60 + shown * 24)
end

function InCharacter.BoardView.Show()
    InCharacter.BoardView.CheckProximity()
    if not currentBoard then
        InCharacter.Print("No notice board nearby.")
        return
    end
    frame.title:SetText(currentBoard.displayName)
    InCharacter.BoardView.Populate(currentBoard.id)
    frame:Show()
end

function InCharacter.BoardView.OnNoticeDiscovered(notice)
    nearbyNotices[notice.id] = notice
    if currentBoard and notice.boardId == currentBoard.id then
        InCharacter.BoardView.Refresh()
        if not frame:IsShown() then
            InCharacter.Print("New notice at " .. (currentBoard.displayName or "nearby board") .. ".")
        end
    end
end

function InCharacter.BoardView.OnNoticeFullReceived(notice)
    if notice then
        InCharacter.Print("|cffffffff" .. (notice.title or "Notice") .. "|r")
        InCharacter.Print(notice.bodyText or "")
        nearbyNotices[notice.id] = notice
        InCharacter.BoardView.Refresh()
    end
end