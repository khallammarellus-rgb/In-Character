local AceAddon = LibStub("AceAddon-3.0")
local AceEvent = LibStub("AceEvent-3.0")

InCharacter = InCharacter or {}
InCharacter.VERSION = "0.1.0"
InCharacter.PREFIX = "IC_RP"
InCharacter.CHANNEL_NAME = "IC_Channel"
InCharacter.SEP = "\031"

InCharacter.STATUS = {
    ACTIVE = "ACTIVE",
    EXPIRED = "EXPIRED",
    DRAFT = "DRAFT",
    REMOVED = "REMOVED",
}

InCharacter.SCOPE = {
    INDIVIDUAL = "INDIVIDUAL",
    GROUP = "GROUP",
    GUILD = "GUILD",
    FACTION = "FACTION",
}

InCharacterDB = InCharacterDB or {
    beacons = {},
    notices = {},
    cache = {},
    mutes = {},
    history = {},
}

InCharacterCharDB = InCharacterCharDB or {
    residence = "",
    filters = { hardExclude = {}, softPriority = {} },
    settings = { noticeTTLDays = 3, quietNotifications = false },
}

local addon = AceAddon:NewAddon("InCharacter", "AceEvent-3.0", "AceComm-3.0")
InCharacter.addon = addon

function InCharacter.NewID()
    return string.format("%08x%04x", time(), math.random(0, 0xFFFF))
end

function InCharacter.GetZoneContext()
    local mapID = C_Map.GetBestMapForUnit("player")
    local subzone = GetSubZoneText() or ""
    local zoneName = ""
    if mapID then
        local info = C_Map.GetMapInfo(mapID)
        zoneName = info and info.name or ""
    end
    local x, y = 0, 0
    if mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            x, y = pos:GetXY()
        end
    end
    return {
        zoneId = mapID or 0,
        subzone = subzone,
        zoneName = zoneName,
        coords = { x = x, y = y },
    }
end

function InCharacter.IsMuted(ownerGUID)
    return InCharacterDB.mutes[ownerGUID] == true
end

function InCharacter.GetCharName()
    if InCharacter.TRP3Bridge then
        local trpName = InCharacter.TRP3Bridge.GetCharacterName()
        if trpName and trpName ~= "" then
            return trpName
        end
    end
    return UnitName("player")
end

function InCharacter.Print(msg)
    print("|cffc9a227In Character:|r " .. msg)
end

function addon:OnInitialize()
    InCharacter.DB = InCharacterDB
    InCharacter.CharDB = InCharacterCharDB
    InCharacter.Comms.Init(self)
    InCharacter.Lifecycle.Init()
    InCharacter.History.Init()
    InCharacter.MinimapButton.Init()
    InCharacter.Flyout.Init()
    InCharacter.BoardView.Init()
    InCharacter.PostEditor.Init()
end

function addon:OnEnable()
    InCharacter.Comms.Enable()
end

SLASH_INCHARACTER1 = "/ic"
SlashCmdList["INCHARACTER"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "ping" then
        InCharacter.Comms.SendPing()
    elseif msg == "beacon" then
        InCharacter.PostEditor.ShowBeaconEditor()
    elseif msg == "notice" then
        InCharacter.PostEditor.ShowNoticeEditor()
    elseif msg == "history" then
        InCharacter.History.Show()
    elseif msg == "" then
        InCharacter.Flyout.Toggle()
    else
        InCharacter.Print("Commands: /ic, /ic beacon, /ic notice, /ic history, /ic ping")
    end
end