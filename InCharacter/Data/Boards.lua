InCharacter = InCharacter or {}
InCharacter.Boards = {}

-- Hardcoded landmark registry (extend by adding entries).
local boards = {
    {
        id = "sw_heroes_call",
        zoneId = 84,
        coords = { x = 0.62, y = 0.72 },
        displayName = "Stormwind Hero's Call Board",
        proximityRadius = 0.04,
    },
    {
        id = "sw_trade_board",
        zoneId = 84,
        coords = { x = 0.61, y = 0.74 },
        displayName = "Stormwind Trade District Board",
        proximityRadius = 0.03,
    },
    {
        id = "org_warchief",
        zoneId = 85,
        coords = { x = 0.49, y = 0.76 },
        displayName = "Orgrimmar Warchief's Command Board",
        proximityRadius = 0.04,
    },
    {
        id = "org_valley_board",
        zoneId = 85,
        coords = { x = 0.52, y = 0.88 },
        displayName = "Valley of Strength Board",
        proximityRadius = 0.03,
    },
    {
        id = "dalaran_board",
        zoneId = 627,
        coords = { x = 0.48, y = 0.42 },
        displayName = "Dalaran Commission Board",
        proximityRadius = 0.04,
    },
}

function InCharacter.Boards.GetAll()
    return boards
end

function InCharacter.Boards.GetById(boardId)
    for _, board in ipairs(boards) do
        if board.id == boardId then
            return board
        end
    end
    return nil
end

function InCharacter.Boards.GetNearbyBoard()
    local zone = InCharacter.GetZoneContext()
    if not zone.zoneId or zone.zoneId == 0 then
        return nil
    end
    for _, board in ipairs(boards) do
        if board.zoneId == zone.zoneId then
            local dx = math.abs(zone.coords.x - board.coords.x)
            local dy = math.abs(zone.coords.y - board.coords.y)
            if dx <= board.proximityRadius and dy <= board.proximityRadius then
                return board
            end
        end
    end
    return nil
end