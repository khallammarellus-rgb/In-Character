InCharacter = InCharacter or {}
InCharacter.Comms = {}

local CTL = ChatThrottleLib
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibDeflate

local addon
local CHANNEL_NAME = InCharacter.CHANNEL_NAME
local PREFIX = InCharacter.PREFIX
local SEP = InCharacter.SEP

local function EncodePayload(tbl)
    local serialized = AceSerializer:Serialize(tbl)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return "Z:" .. LibDeflate:EncodeForPrint(compressed)
end

local function DecodePayload(msg)
    if not msg or msg:sub(1, 2) ~= "Z:" then
        return nil
    end
    local compressed = LibDeflate:DecodeForPrint(msg:sub(3))
    if not compressed then return nil end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, data = AceSerializer:Deserialize(serialized)
    if ok then return data end
    return nil
end

local function EnsureChannel(retries)
    retries = retries or 3
    local channels = { GetChannelList() }
    local generalExists = false
    for i = 2, #channels, 3 do
        if channels[i] == "General" then
            generalExists = true
            break
        end
    end
    if not generalExists then
        C_Timer.After(2, function() EnsureChannel(retries) end)
        return nil
    end

    local channelID
    for i = 1, #channels, 3 do
        if channels[i + 1] and channels[i + 1]:lower() == CHANNEL_NAME:lower() then
            channelID = channels[i]
            local _, name = GetChannelName(channelID)
            if name == CHANNEL_NAME then
                return channelID
            end
            LeaveChannelByName(CHANNEL_NAME)
            break
        end
    end

    JoinTemporaryChannel(CHANNEL_NAME)
    channelID = select(1, GetChannelName(CHANNEL_NAME))
    if channelID and channelID > 0 then
        return channelID
    end
    if retries > 0 then
        C_Timer.After(1, function() EnsureChannel(retries - 1) end)
    end
    return nil
end

local function SendOnChannel(message, prio)
    local channelID = EnsureChannel()
    if not channelID then return false end
    InCharacter.addon:SendCommMessage(PREFIX, message, "CHANNEL", channelID, prio or "NORMAL")
    return true
end

local function SendWhisper(target, message, logged, prio)
    if logged then
        CTL:SendAddonMessageLogged(prio or "NORMAL", PREFIX, message, "WHISPER", target)
    else
        InCharacter.addon:SendCommMessage(PREFIX, message, "WHISPER", target, prio or "NORMAL")
    end
end

local function ZoneMatches(zoneId, subzone)
    local ctx = InCharacter.GetZoneContext()
    if zoneId and zoneId ~= 0 and ctx.zoneId ~= zoneId then
        return false
    end
    if subzone and subzone ~= "" and ctx.subzone ~= "" then
        return ctx.subzone:lower() == subzone:lower()
    end
    return true
end

local function CacheEntry(kind, entry)
    InCharacterDB.cache[kind] = InCharacterDB.cache[kind] or {}
    InCharacterDB.cache[kind][entry.id] = {
        data = entry,
        lastConfirmedAt = time(),
    }
end

local function GetCached(kind, id)
    local bucket = InCharacterDB.cache[kind]
    return bucket and bucket[id] and bucket[id].data or nil
end

function InCharacter.Comms.Init(addonRef)
    addon = addonRef
    addon:RegisterComm(PREFIX, "OnCommReceived")
end

function InCharacter.Comms.Enable()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    frame:SetScript("OnEvent", function(_, _, msg, channelName)
        if msg == "YOU_JOINED" and (channelName == "General" or channelName == "Trade") then
            C_Timer.After(1, EnsureChannel)
            frame:UnregisterAllEvents()
        end
    end)
    C_Timer.NewTicker(3600, EnsureChannel)
end

function InCharacter.Comms.SendPing()
    SendOnChannel("PING")
    InCharacter.Print("Ping sent on " .. CHANNEL_NAME .. ".")
end

function InCharacter.Comms.BroadcastBeacon(beacon)
    local ctx = InCharacter.GetZoneContext()
    local ping = table.concat({
        "BP", beacon.id, beacon.zoneId, beacon.subzone,
        string.format("%.4f", beacon.coords.x),
        string.format("%.4f", beacon.coords.y),
        beacon.shortText,
    }, SEP)
    if #ping > 240 then
        ping = "BP" .. SEP .. beacon.id .. SEP .. beacon.zoneId .. SEP .. beacon.subzone .. SEP .. beacon.shortText
    end
    SendOnChannel(ping)
    CacheEntry("beacon", beacon)
    InCharacterDB.beacons[beacon.id] = beacon
end

function InCharacter.Comms.BroadcastRetract(id, kind)
    SendOnChannel("RT" .. SEP .. kind .. SEP .. id)
end

function InCharacter.Comms.BroadcastBoardQuery(boardId)
    SendOnChannel("BQ" .. SEP .. boardId)
end

function InCharacter.Comms.SendNoticeFull(target, notice)
    local payload = EncodePayload({ opcode = "NF", notice = notice })
    SendWhisper(target, payload, true, "BULK")
end

function InCharacter.Comms.SendBeaconFull(target, beacon)
    local payload = EncodePayload({ opcode = "BF", beacon = beacon })
    SendWhisper(target, payload, false, "NORMAL")
end

function InCharacter.Comms.RequestBeaconFull(sender, beaconId)
    SendWhisper(sender, "FB" .. SEP .. beaconId, false)
end

function InCharacter.Comms.RequestNoticeFull(sender, noticeId)
    SendWhisper(sender, "FN" .. SEP .. noticeId, false)
end

function InCharacter.Comms.AnnounceNotice(notice)
    local summary = table.concat({
        "NS", notice.id, notice.boardId, notice.title, notice.scopeTier,
        tostring(notice.expiresAt),
    }, SEP)
    SendOnChannel(summary)
    CacheEntry("notice", notice)
    InCharacterDB.notices[notice.id] = notice
end

local function HandleBeaconPing(fields, sender)
    local id, zoneId, subzone, x, y, shortText = fields[2], tonumber(fields[3]), fields[4], tonumber(fields[5]), tonumber(fields[6]), fields[7]
    if not id then return end
    if not ZoneMatches(zoneId, subzone) then return end
    if InCharacter.IsMuted(sender) then return end

    local beacon = {
        id = id,
        ownerGUID = UnitGUID(sender) or sender,
        charName = sender,
        shortText = shortText or "Nearby presence",
        zoneId = zoneId,
        subzone = subzone or "",
        coords = { x = x or 0, y = y or 0 },
        status = InCharacter.STATUS.ACTIVE,
        receivedAt = time(),
    }
    CacheEntry("beacon", beacon)
    InCharacter.Flyout.OnBeaconDiscovered(beacon)
end

local function HandleNoticeSummary(fields, sender)
    local id, boardId, title, scopeTier, expiresAt = fields[2], fields[3], fields[4], fields[5], tonumber(fields[6])
    if not id or not boardId then return end
    if expiresAt and expiresAt < time() then return end
    if InCharacter.IsMuted(sender) then return end

    local notice = {
        id = id,
        ownerGUID = UnitGUID(sender) or sender,
        charName = sender,
        title = title or "Notice",
        scopeTier = scopeTier or InCharacter.SCOPE.INDIVIDUAL,
        boardId = boardId,
        expiresAt = expiresAt,
        status = InCharacter.STATUS.ACTIVE,
        receivedAt = time(),
    }
    CacheEntry("notice", notice)
    InCharacter.BoardView.OnNoticeDiscovered(notice)
end

function addon:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PREFIX or not message then return end
    if sender == UnitName("player") then return end
    if C_FriendList.IsIgnored(sender) then return end

    if message == "PING" then
        SendWhisper(sender, "PONG", false)
        InCharacter.Print("Comms pong from " .. sender)
        return
    end
    if message == "PONG" then
        InCharacter.Print("Comms pong from " .. sender)
        return
    end

    local decoded = DecodePayload(message)
    if decoded then
        if decoded.opcode == "BF" and decoded.beacon then
            CacheEntry("beacon", decoded.beacon)
            InCharacter.Flyout.OnBeaconFullReceived(decoded.beacon)
        elseif decoded.opcode == "NF" and decoded.notice then
            CacheEntry("notice", decoded.notice)
            InCharacter.BoardView.OnNoticeFullReceived(decoded.notice)
        end
        return
    end

    local fields = { strsplit(SEP, message) }
    local opcode = fields[1]

    if opcode == "BP" then
        HandleBeaconPing(fields, sender)
    elseif opcode == "RT" then
        local kind, id = fields[2], fields[3]
        if kind and id then
            InCharacter.Lifecycle.HandleRemoteRetract(kind, id)
        end
    elseif opcode == "BQ" then
        local boardId = fields[2]
        InCharacter.Comms.RespondToBoardQuery(sender, boardId)
    elseif opcode == "BR" then
        HandleNoticeSummary(fields, sender)
    elseif opcode == "NS" then
        HandleNoticeSummary(fields, sender)
    elseif opcode == "FB" then
        local beaconId = fields[2]
        local beacon = InCharacterDB.beacons[beaconId] or GetCached("beacon", beaconId)
        if beacon then
            InCharacter.Comms.SendBeaconFull(sender, beacon)
        end
    elseif opcode == "FN" then
        local noticeId = fields[2]
        local notice = InCharacterDB.notices[noticeId] or GetCached("notice", noticeId)
        if notice then
            InCharacter.Comms.SendNoticeFull(sender, notice)
        end
    end
end

function InCharacter.Comms.RespondToBoardQuery(requester, boardId)
    if not boardId then return end
    for id, notice in pairs(InCharacterDB.notices) do
        if notice.boardId == boardId and notice.status == InCharacter.STATUS.ACTIVE then
            if not notice.expiresAt or notice.expiresAt >= time() then
                local summary = table.concat({
                    "BR", notice.id, notice.boardId, notice.title, notice.scopeTier,
                    tostring(notice.expiresAt or 0),
                }, SEP)
                SendWhisper(requester, summary, false)
            end
        end
    end
    local cache = InCharacterDB.cache.notice
    if cache then
        for _, wrapped in pairs(cache) do
            local notice = wrapped.data
            if notice.boardId == boardId and notice.status == InCharacter.STATUS.ACTIVE then
                if not notice.expiresAt or notice.expiresAt >= time() then
                    local summary = table.concat({
                        "BR", notice.id, notice.boardId, notice.title, notice.scopeTier,
                        tostring(notice.expiresAt or 0), tostring(wrapped.lastConfirmedAt or time()),
                    }, SEP)
                    SendWhisper(requester, summary, false)
                end
            end
        end
    end
end