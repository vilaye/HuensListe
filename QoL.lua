-- Huens Liste: quality-of-life features
--   Well Fed reminder: movable on-screen warning while you have no food buff
local _, HL = ...

---------------------------------------------------------------------------
-- Well Fed detection
---------------------------------------------------------------------------
-- Localized names of the food buff. Forever foods also add "Well Fed XP Boost"
-- style variants, so we match the start of the name as well.
local WELL_FED_NAMES = {
    "well fed",        -- enUS
    "satt",            -- deDE
    "bien nourri",     -- frFR
    "bien alimentado", -- esES / esMX
    "bem alimentado",  -- ptBR
    "ben nutrito",     -- itIT
    "сытость",         -- ruRU
    "배부름",          -- koKR
    "进食充分",        -- zhCN
    "進食充分",        -- zhTW
}
local FOOD_ICON = 136000 -- Interface\Icons\Spell_Misc_Food

local function isWellFedAura(name, icon)
    if icon == FOOD_ICON or icon == "Interface\\Icons\\Spell_Misc_Food" then return true end
    if type(name) ~= "string" then return false end
    local n = name:lower()
    for _, wf in ipairs(WELL_FED_NAMES) do
        if n == wf or n:sub(1, #wf) == wf then return true end
    end
    return false
end

-- true / false, or nil if the game hides aura data right now (combat restrictions)
function HL:HasWellFed()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return nil end
        if not aura then return false end
        local name, icon = aura.name, aura.icon
        if HL.IsSecret(name) or HL.IsSecret(icon) then return nil end
        if isWellFedAura(name, icon) then return true end
    end
    return false
end

-- /hl buffs: list your buffs so we can see how the game names them
function HL:PrintBuffs()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    self:Print("Your buffs:")
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        if HL.IsSecret(aura.name) or HL.IsSecret(aura.icon) then
            print("  (hidden by the game right now)")
        else
            print(("  %s  |cff888888icon %s, spell %s%s|r"):format(tostring(aura.name), tostring(aura.icon),
                tostring(aura.spellId), isWellFedAura(aura.name, aura.icon) and ", |cff40ff40= Well Fed|r" or ""))
        end
    end
end

---------------------------------------------------------------------------
-- On-screen reminder
---------------------------------------------------------------------------
local reminder
local unlocked = false

local function savePosition()
    local point, _, relPoint, x, y = reminder:GetPoint()
    HL.settings.wellFedPos = { point, relPoint, x, y }
end

local function applyPosition()
    reminder:ClearAllPoints()
    local p = HL.settings.wellFedPos
    if type(p) == "table" and p[1] then
        reminder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        reminder:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
end

local function createReminder()
    reminder = CreateFrame("Frame", "HuensListeWellFedFrame", UIParent)
    reminder:SetSize(340, 44)
    reminder:SetFrameStrata("HIGH")
    reminder:SetClampedToScreen(true)
    reminder:SetMovable(true)
    reminder:RegisterForDrag("LeftButton")
    reminder:SetScript("OnDragStart", reminder.StartMoving)
    reminder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    reminder.bg = reminder:CreateTexture(nil, "BACKGROUND")
    reminder.bg:SetAllPoints()
    reminder.bg:SetColorTexture(0, 0, 0, 0.55)

    reminder.icon = reminder:CreateTexture(nil, "ARTWORK")
    reminder.icon:SetTexture(FOOD_ICON)
    reminder.icon:SetSize(32, 32)
    reminder.icon:SetPoint("LEFT", 6, 0)

    reminder.text = reminder:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    reminder.text:SetPoint("LEFT", reminder.icon, "RIGHT", 8, 0)
    reminder.text:SetTextColor(1, 0.55, 0.1)
    reminder.text:SetText("You are not Well Fed!")

    reminder.hint = reminder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reminder.hint:SetPoint("TOP", reminder, "BOTTOM", 0, -2)
    reminder.hint:SetText("Drag to move – click \"Lock position\" in /hl when done")

    local ag = reminder.text:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.8)
    reminder.anim = ag

    applyPosition()
    reminder:Hide()
end

local function setVisible(show)
    if show then
        if not reminder:IsShown() then reminder:Show(); reminder.anim:Play() end
    else
        reminder.anim:Stop()
        reminder:Hide()
    end
end

function HL:UpdateWellFed()
    if not reminder or not self.settings then return end

    -- Move mode: always visible, draggable, with background and hint
    reminder:EnableMouse(unlocked)
    reminder.bg:SetShown(unlocked)
    reminder.hint:SetShown(unlocked)
    if unlocked then setVisible(true) return end

    if not self.settings.wellFedReminder then setVisible(false) return end
    local okDead, dead = pcall(UnitIsDeadOrGhost, "player")
    if okDead and not HL.IsSecret(dead) and dead then setVisible(false) return end

    local has = self:HasWellFed()
    if has == nil then return end -- data hidden right now: keep the current state
    setVisible(not has)
end

function HL:IsWellFedUnlocked() return unlocked end

function HL:SetWellFedUnlocked(state)
    unlocked = state and true or false
    self:UpdateWellFed()
end

function HL:ResetWellFedPosition()
    self.settings.wellFedPos = nil
    if reminder then applyPosition() end
end

HL:On("PLAYER_LOGIN", function()
    if HL.settings.wellFedReminder == nil then HL.settings.wellFedReminder = true end
    createReminder()
    HL:UpdateWellFed()
end)

HL:On("UNIT_AURA", function(unit)
    if unit == "player" then HL:UpdateWellFed() end
end)
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    HL:On(ev, function() HL:UpdateWellFed() end)
end
