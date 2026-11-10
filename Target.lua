-- Huens Liste: "target nearby KOS" button, key binding and macro
--
-- Addons can't target by themselves: it has to be a secure button the player
-- presses (key binding, /click macro or the on-screen button). The button runs a
-- macro of /targetexact lines; the last line that finds someone wins, so the most
-- recently seen KOS player goes last. The macro can't change during combat, so it
-- also lists other KOS players (the whole list if it's small) to catch people who
-- only show up mid-fight.
local _, HL = ...

local BUTTON_NAME = "HuensListeTargetButton"
local MAX_NAMES = 10
local NEARBY_FOR = 120 -- seconds a sighting counts as "nearby"

_G.BINDING_HEADER_HUENSLISTE = "Huens Liste"
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Target nearby KOS player"

local nearby = {}   -- [key] = { n = name, t = GetTime() }
local button, pending

local function targetLines(name)
    -- the game knows Forever characters as "First-Last"; also try "First Last"
    local spaced = HL.ShortName(name)
    if spaced ~= name then
        return "/targetexact " .. spaced .. "\n/targetexact " .. name
    end
    return "/targetexact " .. name
end

-- KOS names for the macro, least important first (the last match wins)
function HL:TargetCandidates()
    local now = GetTime()
    local recent, seenKey = {}, {}
    for key, s in pairs(nearby) do
        if now - s.t <= NEARBY_FOR and self:Get(s.n, "kos") then
            recent[#recent + 1] = s
        end
    end
    table.sort(recent, function(a, b) return a.t < b.t end) -- most recent last
    while #recent > MAX_NAMES do table.remove(recent, 1) end
    for _, s in ipairs(recent) do seenKey[HL.Key(s.n)] = true end

    -- fill up with the rest of the KOS list (newest entries closest to the end)
    local others = {}
    for _, e in pairs(self:Entries("kos")) do
        if not e.d and not seenKey[HL.Key(e.n)] then others[#others + 1] = e end
    end
    table.sort(others, function(a, b) return a.t < b.t end)
    local room = MAX_NAMES - #recent
    local filler = {}
    for i = math.max(1, #others - room + 1), #others do filler[#filler + 1] = others[i].n end

    local names = {}
    for _, n in ipairs(filler) do names[#names + 1] = n end
    for _, s in ipairs(recent) do names[#names + 1] = s.n end
    return names, recent[#recent] and recent[#recent].n or nil
end

function HL:TargetMacroText()
    local names = self:TargetCandidates()
    local lines = {}
    for _, n in ipairs(names) do lines[#lines + 1] = targetLines(n) end
    return table.concat(lines, "\n")
end

local function applyVisibility()
    if not button then return end
    if HL.settings.targetButton then button:Show() else button:Hide() end
end

-- Push the current names into the secure button (only possible out of combat)
function HL:UpdateTargetButton()
    if not button then return end
    local _, latest = self:TargetCandidates()
    button.label:SetText(latest and HL.ShortName(latest) or "|cff888888no KOS nearby|r")
    if InCombatLockdown() then pending = true return end
    pending = false
    button:SetAttribute("macrotext", self:TargetMacroText())
    applyVisibility()
end

function HL:NoteKOSNearby(name)
    local key = HL.Key(name)
    local isNew = not nearby[key] or GetTime() - nearby[key].t > NEARBY_FOR
    nearby[key] = { n = name, t = GetTime() }
    if isNew then self:UpdateTargetButton() end
end

local function savePosition()
    local point, _, relPoint, x, y = button:GetPoint()
    HL.settings.targetButtonPos = { point, relPoint, x, y }
end

local function createButton()
    button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    button:SetSize(170, 30)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    if button.SetBackdrop then
        button:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        button:SetBackdropColor(0.1, 0, 0, 0.85)
        button:SetBackdropBorderColor(0.8, 0.15, 0.15)
    end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    button.label:SetPoint("RIGHT", -6, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetTextColor(1, 0.3, 0.3)

    -- Shift + drag moves it (out of combat only, it's a secure button)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("|cffcc2222Huens Liste|r – target nearby KOS")
        local names = HL:TargetCandidates()
        if #names == 0 then
            GameTooltip:AddLine("Nobody on the KOS List yet", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Tries, in this order (last found wins):", 0.7, 0.7, 0.7)
            for _, n in ipairs(names) do GameTooltip:AddLine("  " .. HL.ShortName(n), 1, 0.4, 0.4) end
        end
        GameTooltip:AddLine("Shift + drag to move", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- /hl debug: show that the button fired and what it tried
    button:SetScript("PreClick", function(_, mouseButton, down)
        if not HL.debug then return end
        local text = button:GetAttribute("macrotext") or ""
        local n = select(2, text:gsub("/targetexact", ""))
        HL:Print(("|cff888888[target] button fired (%s, %s) – %d /targetexact lines:|r"):format(
            tostring(mouseButton), down and "down" or "up", n))
        for line in text:gmatch("[^\n]+") do HL:Print("|cff888888  " .. line .. "|r") end
    end)
    button:SetScript("PostClick", function()
        if not HL.debug then return end
        local full = HL.UnitFullName("target")
        HL:Print("|cff888888[target] your target now: " .. tostring(full and HL.ShortName(full) or "nobody") .. "|r")
    end)

    button:ClearAllPoints()
    local p = HL.settings.targetButtonPos
    if type(p) == "table" and p[1] then
        button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
    button:Hide()
end

function HL:ResetTargetButtonPosition()
    self.settings.targetButtonPos = nil
    if button and not InCombatLockdown() then
        button:ClearAllPoints()
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

-- /hl macro: create a "KOS Target" macro and put it on the cursor
function HL:CreateTargetMacro()
    if InCombatLockdown() then self:Print("Can't create macros in combat.") return end
    local name = "KOS Target"
    local body = "/click " .. BUTTON_NAME
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        EditMacro(index, name, "INV_Misc_Bone_HumanSkull_01", body)
    else
        local ok, result = pcall(CreateMacro, name, "INV_Misc_Bone_HumanSkull_01", body, false)
        if not ok or not result then
            self:Print("Couldn't create the macro" .. (not ok and (": " .. tostring(result)) or " (your account macros may be full)")
                .. ". Make one yourself with: " .. body)
            return
        end
        index = result
    end
    PickupMacro(index)
    self:Print("Macro \"KOS Target\" is on your cursor – drop it on an action bar.")
end

HL:On("PLAYER_LOGIN", function()
    createButton()
    HL:UpdateTargetButton()
    -- forget old sightings and refresh the names every 10 s (out of combat)
    C_Timer.NewTicker(10, function()
        local now, changed = GetTime(), false
        for key, s in pairs(nearby) do
            if now - s.t > NEARBY_FOR then nearby[key] = nil; changed = true end
        end
        if changed or pending then HL:UpdateTargetButton() end
    end)
end)

HL:On("PLAYER_REGEN_ENABLED", function()
    if pending then HL:UpdateTargetButton() end
end)

HL:OnChange(function() HL:UpdateTargetButton() end)
