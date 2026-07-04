InCharacter = InCharacter or {}
InCharacter.ProfanityFilter = {}

local LEET = {
    ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s",
    ["7"] = "t", ["@"] = "a", ["$"] = "s",
}

local OOC_PATTERNS = {
    "ooc:",
    "lfg", "irl", "brb", "afk", "gtg",
}

local function normalize(text)
    text = string.lower(text or "")
    text = text:gsub("[%p%s]", "")
    local out = {}
    for i = 1, #text do
        local ch = text:sub(i, i)
        out[#out + 1] = LEET[ch] or ch
    end
    return table.concat(out)
end

function InCharacter.ProfanityFilter.IsBlocked(text)
    local norm = normalize(text)
    for _, term in ipairs(InCharacter.Blocklist) do
        local termNorm = normalize(term)
        if termNorm ~= "" and norm:find(termNorm, 1, true) then
            return true, "Content blocked by In Character safety filter."
        end
    end
    return false
end

function InCharacter.ProfanityFilter.GetOOCWarnings(text)
    local lower = string.lower(text or "")
    local warnings = {}
    for _, pattern in ipairs(OOC_PATTERNS) do
        if lower:find(pattern, 1, true) then
            warnings[#warnings + 1] = pattern
        end
    end
    if text and text:find("%(") then
        warnings[#warnings + 1] = "parenthetical aside"
    end
    return warnings
end

function InCharacter.ProfanityFilter.ValidateNotice(title, body, onProceed)
    local blocked, reason = InCharacter.ProfanityFilter.IsBlocked(title)
    if blocked then
        InCharacter.Print(reason)
        return false
    end
    blocked, reason = InCharacter.ProfanityFilter.IsBlocked(body)
    if blocked then
        InCharacter.Print(reason)
        return false
    end

    local warnings = InCharacter.ProfanityFilter.GetOOCWarnings(body)
    if #warnings > 0 and onProceed then
        StaticPopup_Show("INCHARACTER_OOC_WARNING", nil, nil, { onProceed = onProceed })
        return false
    end
    return true
end

StaticPopupDialogs["INCHARACTER_OOC_WARNING"] = {
    text = "This notice might read as out-of-character. Post anyway?",
    button1 = "Post anyway",
    button2 = "Edit",
    OnAccept = function(self)
        local data = self.data
        if data and data.onProceed then
            data.onProceed()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}