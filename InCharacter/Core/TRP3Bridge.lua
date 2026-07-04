InCharacter = InCharacter or {}
InCharacter.TRP3Bridge = {}

function InCharacter.TRP3Bridge.IsAvailable()
    return TRP3_API ~= nil and TRP3_API.profile ~= nil
end

function InCharacter.TRP3Bridge.GetProfileDefaults()
    if not InCharacter.TRP3Bridge.IsAvailable() then
        return nil
    end
    local profile = TRP3_API.profile.getPlayerCurrentProfile()
    if not profile or not profile.player then
        return nil
    end
    local chars = profile.player.characteristics or {}
    local info = profile.player.about or {}
    return {
        charName = chars.FN or UnitName("player"),
        race = chars.RA or "",
        class = chars.CL or "",
        title = chars.TI or "",
        residence = InCharacter.CharDB.residence or "",
    }
end

function InCharacter.TRP3Bridge.GetCharacterName()
    local defaults = InCharacter.TRP3Bridge.GetProfileDefaults()
    return defaults and defaults.charName or UnitName("player")
end

function InCharacter.TRP3Bridge.RememberResidence(value)
    if value and value ~= "" then
        InCharacter.CharDB.residence = value
    end
end