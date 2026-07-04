InCharacter = InCharacter or {}
InCharacter.SentenceTemplates = {}

local templates = {
    {
        id = "seeking",
        label = "Seeking company",
        slots = { "disposition", "role", "intent" },
        full = "I am a {disposition} {role}, seeking {intent} in these parts.",
        short = "{disposition} {role} — seeking {intent}",
    },
    {
        id = "watching",
        label = "Keeping watch",
        slots = { "disposition", "role", "location" },
        full = "A {disposition} {role} keeps watch near {location}, open to passing conversation.",
        short = "{disposition} {role} near {location}",
    },
    {
        id = "calling",
        label = "Calling out",
        slots = { "role", "intent", "location" },
        full = "This {role} calls quietly for {intent} around {location}.",
        short = "{role} — {intent} ({location})",
    },
}

local slotOptions = {
    disposition = {
        "curious", "friendly", "wary", "seasoned", "quiet", "bold", "weary", "cheerful",
    },
    role = {
        "traveler", "scholar", "merchant", "soldier", "healer", "storyteller",
        "adventurer", "artisan", "scout", "pilgrim",
    },
    intent = {
        "conversation", "companionship", "a shared tale", "aid on the road",
        "trade talk", "quiet company", "training partners", "fellow explorers",
    },
    location = {
        "the crossroads", "the market square", "the tavern door", "the city gates",
        "the harbor", "the temple steps", "the old quarter",
    },
}

function InCharacter.SentenceTemplates.GetTemplates()
    return templates
end

function InCharacter.SentenceTemplates.GetSlotOptions(slotName)
    return slotOptions[slotName] or {}
end

local function fillPattern(pattern, slots)
    return (pattern:gsub("{(%w+)}", function(key)
        return slots[key] or key
    end))
end

function InCharacter.SentenceTemplates.Resolve(templateId, slotValues, locationOverride)
    for _, template in ipairs(templates) do
        if template.id == templateId then
            local slots = {}
            for k, v in pairs(slotValues or {}) do
                slots[k] = v
            end
            if locationOverride and locationOverride ~= "" then
                slots.location = locationOverride
            elseif not slots.location then
                local zone = InCharacter.GetZoneContext()
                slots.location = zone.subzone ~= "" and zone.subzone or zone.zoneName
            end
            return {
                templateId = templateId,
                slots = slots,
                fullText = fillPattern(template.full, slots),
                shortText = fillPattern(template.short, slots),
            }
        end
    end
    return nil
end