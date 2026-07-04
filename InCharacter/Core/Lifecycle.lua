InCharacter = InCharacter or {}
InCharacter.Lifecycle = {}

local BEACON_TTL = 30 * 60
local MAX_NOTICE_DAYS = 7

function InCharacter.Lifecycle.GetBeaconTTL()
    return BEACON_TTL
end

function InCharacter.Lifecycle.GetNoticeTTLSeconds()
    local days = InCharacter.CharDB.settings.noticeTTLDays or 3
    days = math.min(math.max(days, 1), MAX_NOTICE_DAYS)
    return days * 24 * 60 * 60
end

function InCharacter.Lifecycle.Init()
    C_Timer.NewTicker(60, InCharacter.Lifecycle.Sweep)
end

function InCharacter.Lifecycle.Sweep()
    local now = time()
    for id, beacon in pairs(InCharacterDB.beacons) do
        if beacon.expiresAt and beacon.expiresAt < now and beacon.status == InCharacter.STATUS.ACTIVE then
            InCharacter.Lifecycle.ExpireOwned("beacon", id)
        end
    end
    for id, notice in pairs(InCharacterDB.notices) do
        if notice.expiresAt and notice.expiresAt < now and notice.status == InCharacter.STATUS.ACTIVE then
            InCharacter.Lifecycle.ExpireOwned("notice", id)
        end
    end
    if InCharacterDB.cache then
        for kind, bucket in pairs(InCharacterDB.cache) do
            for id, wrapped in pairs(bucket) do
                local entry = wrapped.data
                if entry.expiresAt and entry.expiresAt < now then
                    bucket[id] = nil
                end
            end
        end
    end
    InCharacter.Flyout.Refresh()
    InCharacter.BoardView.Refresh()
end

function InCharacter.Lifecycle.ExpireOwned(kind, id)
    local store = kind == "beacon" and InCharacterDB.beacons or InCharacterDB.notices
    local entry = store[id]
    if not entry then return end
    entry.status = InCharacter.STATUS.EXPIRED
    store[id] = nil
    InCharacter.History.SaveDraft(kind, entry)
end

function InCharacter.Lifecycle.DeleteOwned(kind, id)
    local store = kind == "beacon" and InCharacterDB.beacons or InCharacterDB.notices
    local entry = store[id]
    if entry then
        entry.status = InCharacter.STATUS.DRAFT
        store[id] = nil
        InCharacter.History.SaveDraft(kind, entry)
    end
    InCharacter.Comms.BroadcastRetract(id, kind)
    if InCharacterDB.cache[kind] then
        InCharacterDB.cache[kind][id] = nil
    end
    InCharacter.Flyout.Refresh()
    InCharacter.BoardView.Refresh()
end

function InCharacter.Lifecycle.HandleRemoteRetract(kind, id)
    if InCharacterDB.cache[kind] then
        InCharacterDB.cache[kind][id] = nil
    end
    if kind == "beacon" then
        InCharacter.Flyout.Refresh()
    else
        InCharacter.BoardView.Refresh()
    end
end

function InCharacter.Lifecycle.CreateBeacon(templateId, slotValues)
    local resolved = InCharacter.SentenceTemplates.Resolve(templateId, slotValues, InCharacter.CharDB.residence)
    if not resolved then return nil end
    local ctx = InCharacter.GetZoneContext()
    local now = time()
    return {
        id = InCharacter.NewID(),
        ownerGUID = UnitGUID("player"),
        charName = InCharacter.GetCharName(),
        templateId = templateId,
        slots = resolved.slots,
        fullText = resolved.fullText,
        shortText = resolved.shortText,
        zoneId = ctx.zoneId,
        subzone = ctx.subzone,
        coords = ctx.coords,
        createdAt = now,
        expiresAt = now + BEACON_TTL,
        status = InCharacter.STATUS.ACTIVE,
    }
end

function InCharacter.Lifecycle.CreateNotice(title, bodyText, boardId, scopeTier)
    local now = time()
    return {
        id = InCharacter.NewID(),
        ownerGUID = UnitGUID("player"),
        charName = InCharacter.GetCharName(),
        title = title,
        bodyText = bodyText,
        scopeTier = scopeTier or InCharacter.SCOPE.INDIVIDUAL,
        boardId = boardId,
        createdAt = now,
        expiresAt = now + InCharacter.Lifecycle.GetNoticeTTLSeconds(),
        editCount = 0,
        status = InCharacter.STATUS.ACTIVE,
    }
end

function InCharacter.Lifecycle.PostBeacon(beacon)
    InCharacterDB.beacons[beacon.id] = beacon
    InCharacter.Comms.BroadcastBeacon(beacon)
    InCharacter.Flyout.Refresh()
    InCharacter.MinimapButton.Notify()
end

function InCharacter.Lifecycle.PostNotice(notice)
    InCharacterDB.notices[notice.id] = notice
    InCharacter.Comms.AnnounceNotice(notice)
    InCharacter.BoardView.Refresh()
end