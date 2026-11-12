-- Huens Liste: Maelstrom Weapon alert (Quality of Life, opt-in)
--
-- Shows a big pulsing "MAELSTROM WEAPON 5" in the middle of the screen while you
-- have 5 stacks. Buffs are hidden from addons in combat on the modern client, but
-- Blizzard whitelisted the Maelstrom Weapon aura, so its stacks stay readable.
local _, HL = ...

local THRESHOLD = 5
-- Maelstrom Weapon buff IDs we know of (retail, Wrath-era). Forever's version may
-- use its own ID; we also match the buff by name.
local MW_IDS = { 344179, 187881, 53817 }
local MW_ICON = "Interface\\Icons\\Spell_Shaman_MaelstromWeapon"

local mwNames
local function maelstromNames()
    if mwNames then return mwNames end
    mwNames = { ["maelstrom weapon"] = true, ["waffe des mahlstroms"] = true }
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs(MW_IDS) do
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok and type(n) == "string" and not HL.IsSecret(n) then mwNames[n:lower()] = true end
        end
    end
    return mwNames
end

local function stacksOf(aura)
    local c = aura.applications
    if HL.IsSecret(c) then return nil end
    c = tonumber(c) or 0
    return c > 0 and c or 1
end

-- stacks (0 if you don't have it), or nil if the game hides it right now
function HL:MaelstromStacks()
    if not C_UnitAuras then return nil end
    -- 1) direct lookup by spell ID: whitelisted auras are readable in combat
    if C_UnitAuras.GetPlayerAuraBySpellID then
        for _, id in ipairs(MW_IDS) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and type(aura) == "table" then
                local c = stacksOf(aura)
                if c then return c, "spell id " .. id end
            end
        end
    end
    -- 2) scan your buffs by name
    if not C_UnitAuras.GetAuraDataByIndex then return nil end
    local names, hidden = maelstromNames(), false
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return nil end
        if not aura then break end
        local name = aura.name
        if HL.IsSecret(name) then
            hidden = true
        elseif type(name) == "string" and names[name:lower()] then
            local c = stacksOf(aura)
            if not c then return nil, "stacks hidden" end
            return c, "name, spell id " .. tostring(aura.spellId)
        end
    end
    if hidden then return nil, "buffs hidden" end
    return 0
end

---------------------------------------------------------------------------
-- On-screen alert
---------------------------------------------------------------------------
local frame
local unlocked, wasReady, lastDebug = false, false, nil

local function savePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    HL.settings.maelstromPos = { point, relPoint, x, y }
end

local function applyPosition()
    frame:ClearAllPoints()
    local p = HL.settings.maelstromPos
    if type(p) == "table" and p[1] then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
end

local function createFrame()
    frame = CreateFrame("Frame", "HuensListeMaelstromFrame", UIParent)
    frame:SetSize(360, 56)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.55)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture(MW_ICON)
    frame.icon:SetSize(44, 44)
    frame.icon:SetPoint("LEFT", 6, 0)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
    frame.text:SetTextColor(0.35, 0.75, 1)
    frame.text:SetText("MAELSTROM WEAPON " .. THRESHOLD)

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    frame.hint:SetText("Drag to move – click \"Lock position\" in /hl when done")

    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.5)
    a:SetDuration(0.45)
    frame.anim = ag

    applyPosition()
    frame:Hide()
end

local function setVisible(show)
    if show then
        if not frame:IsShown() then frame:Show(); frame.anim:Play() end
    else
        frame.anim:Stop()
        frame:Hide()
    end
end

function HL:UpdateMaelstrom()
    if not frame or not self.settings then return end
    frame:EnableMouse(unlocked)
    frame.bg:SetShown(unlocked)
    frame.hint:SetShown(unlocked)
    if unlocked then setVisible(true) return end
    if not self.settings.maelstromAlert then
        setVisible(false)
        wasReady = false
        return
    end

    local stacks, how = self:MaelstromStacks()
    if self.debug then
        local line = tostring(stacks) .. " (" .. tostring(how or "not found") .. ")"
        if line ~= lastDebug then
            lastDebug = line
            self:Print("|cff888888[maelstrom] stacks: " .. line .. "|r")
        end
    end
    if stacks == nil then return end -- hidden right now: keep what we show

    local ready = stacks >= THRESHOLD
    if ready and not wasReady and self.settings.maelstromSound then
        HL.PlaySoundSafe(SOUNDKIT and (SOUNDKIT.ALARM_CLOCK_WARNING_2 or SOUNDKIT.RAID_WARNING))
    end
    wasReady = ready
    setVisible(ready)
end

function HL:IsMaelstromUnlocked() return unlocked end

function HL:SetMaelstromUnlocked(state)
    unlocked = state and true or false
    self:UpdateMaelstrom()
end

function HL:ResetMaelstromPosition()
    self.settings.maelstromPos = nil
    if frame then applyPosition() end
end

HL:On("PLAYER_LOGIN", function()
    createFrame()
    HL:UpdateMaelstrom()
end)

HL:On("UNIT_AURA", function(unit)
    if unit == "player" then HL:UpdateMaelstrom() end
end)
HL:On("PLAYER_ENTERING_WORLD", function() HL:UpdateMaelstrom() end)
HL:On("PLAYER_REGEN_ENABLED", function() HL:UpdateMaelstrom() end)
