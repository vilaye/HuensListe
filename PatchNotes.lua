-- Huens Liste: patch notes shown in the "Patch Notes" tab.
-- Newest version first. Keep each bullet short; CHANGELOG.md has the details.
local _, HL = ...

HL.PATCH_NOTES = {
    { version = "1.6.1", notes = {
        "Fixed: the X button didn't close the window in combat",
        "Fixed: KOS kills are now counted (Forever's honor messages have no name)",
        "Target nearby KOS: key binding, /hl macro or on-screen button",
    } },
    { version = "1.6.0", notes = {
        "KOS kill counter: kills on KOS players are counted and shared",
        "Users tab shows everyone's KOS kills",
        "Edit notes: click a row, right-click menu or /hl note",
        "New Patch Notes tab (/hl notes)",
        "Fixed: you showed up twice in the Users tab",
        "Names shown as \"First Last\" everywhere",
    } },
    { version = "1.5.1", notes = {
        "Names work with a space or a dash (\"Vila Yeezy\")",
        "Quality of Life options are off until you turn them on",
    } },
    { version = "1.5.0", notes = {
        "New Swine List for toxic players of your own faction",
        "KOS List is for the enemy faction only",
        "Move players between the two lists",
    } },
    { version = "1.4.0", notes = {
        "Users tab: who has the addon, their version and who's online",
    } },
    { version = "1.3.0", notes = {
        "Quality of Life tab with a movable Well Fed reminder",
        "Popup when a friend has a newer version",
    } },
    { version = "1.2.0", notes = {
        "Support for Forever's two-part names",
        "Fixed syncing of names",
    } },
    { version = "1.1.0", notes = {
        "Minimap button",
    } },
    { version = "1.0.0", notes = {
        "Shared KOS list with nameplate skull, alerts and sync",
    } },
}

function HL:PatchNotesText()
    local installed = HL.VersionNumber(HL.VERSION)
    local lines = {}
    for _, entry in ipairs(HL.PATCH_NOTES) do
        local v = HL.VersionNumber(entry.version)
        local tag = ""
        if v == installed then
            tag = "  |cff40ff40(installed)|r"
        elseif v > installed then
            tag = "  |cff888888(coming next)|r"
        end
        lines[#lines + 1] = "|cffffd100Version " .. entry.version .. "|r" .. tag
        for _, note in ipairs(entry.notes) do
            lines[#lines + 1] = "  •  " .. note
        end
        lines[#lines + 1] = " "
    end
    return table.concat(lines, "\n")
end

-- After an update: point to the patch notes once
HL:On("PLAYER_LOGIN", function()
    local last = HL.db.lastVersion
    if last and HL.VersionNumber(HL.VERSION) > HL.VersionNumber(last) then
        C_Timer.After(5, function()
            HL:Print("Updated to " .. HL.VERSION .. " – see what's new with |cffffff00/hl notes|r")
        end)
    end
    HL.db.lastVersion = HL.VERSION
end)
