InCharacter = InCharacter or {}
InCharacter.History = {}

function InCharacter.History.Init()
    InCharacterDB.history = InCharacterDB.history or {}
end

function InCharacter.History.SaveDraft(kind, entry)
    InCharacterDB.history[kind] = InCharacterDB.history[kind] or {}
    entry.status = InCharacter.STATUS.DRAFT
    table.insert(InCharacterDB.history[kind], 1, entry)
    while #InCharacterDB.history[kind] > 20 do
        table.remove(InCharacterDB.history[kind])
    end
end

function InCharacter.History.GetDrafts(kind)
    return InCharacterDB.history[kind] or {}
end

function InCharacter.History.RepostDraft(kind, index)
    local drafts = InCharacter.History.GetDrafts(kind)
    local draft = drafts[index]
    if not draft then return end

    if kind == "beacon" then
        local beacon = InCharacter.Lifecycle.CreateBeacon(draft.templateId, draft.slots)
        if beacon then
            beacon.fullText = draft.fullText
            beacon.shortText = draft.shortText
            InCharacter.Lifecycle.PostBeacon(beacon)
            InCharacter.Print("Beacon renewed.")
        end
    else
        local notice = InCharacter.Lifecycle.CreateNotice(draft.title, draft.bodyText, draft.boardId, draft.scopeTier)
        if notice then
            InCharacter.Lifecycle.PostNotice(notice)
            InCharacter.Print("Notice renewed.")
        end
    end
end

function InCharacter.History.Show()
    local beaconCount = #(InCharacter.History.GetDrafts("beacon"))
    local noticeCount = #(InCharacter.History.GetDrafts("notice"))
    InCharacter.Print(string.format("History: %d beacon draft(s), %d notice draft(s). Use editors to repost.", beaconCount, noticeCount))
end