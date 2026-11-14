-- Huens Liste: quality-of-life features
--   Well Fed reminder: movable on-screen warning while you have no food buff
--   Campfire reminder: the same for the campfire buff / Boosted Rest debuff
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

---------------------------------------------------------------------------
-- Campfire buff detection
---------------------------------------------------------------------------
-- The campfire buff is spell 1229741, so the reminder works without any setup.
-- Extra buffs can be added by name with /hl campfire set Buff Name:
-- settings.campBuffs = { { n = name, id = spellId, icon = icon }, ... }
-- Taking the tent's extra rested XP gives no buff but the "Boosted Rest" debuff
-- (spell 1229451); that counts as being covered too.
local CAMP_SPELL_ID = 1229741
local BOOSTED_REST_ID = 1229451

-- true / false, nil while the game hides aura data
local function hasBoostedRest()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
        if not ok then return nil end
        if not aura then return false end
        local id = aura.spellId
        if HL.IsSecret(id) then return nil end
        if id == BOOSTED_REST_ID then return true end
    end
    return false
end
local CAMP_ICON = "Interface\\Icons\\Spell_Fire_Fire"

local function campIcon()
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, CAMP_SPELL_ID)
        if ok and tex and not HL.IsSecret(tex) then return tex end
    end
    return CAMP_ICON
end

-- List of the player's buffs { name, icon, spellId }, or nil while the game hides them
function HL:PlayerBuffs()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local list = {}
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return nil end
        if not aura then break end
        local name, icon, id = aura.name, aura.icon, aura.spellId
        if HL.IsSecret(name) or HL.IsSecret(icon) or HL.IsSecret(id) then return nil end
        if type(name) == "string" then
            list[#list + 1] = { name = name, icon = icon, spellId = id }
        end
    end
    return list
end

function HL:CampBuffs()
    local s = self.settings
    if type(s.campBuffs) ~= "table" then s.campBuffs = {} end
    return s.campBuffs
end

local function campIndex(name, id)
    if type(name) ~= "string" then return nil end
    local lower = name:lower()
    for i, b in ipairs(HL:CampBuffs()) do
        if (id and b.id and b.id == id) or (type(b.n) == "string" and b.n:lower() == lower) then return i end
    end
end

function HL:IsCampBuff(name, id) return id == CAMP_SPELL_ID or campIndex(name, id) ~= nil end

-- Add the buff to the watched ones, or remove it if it's already there
function HL:ToggleCampBuff(name, id, icon)
    if type(name) ~= "string" or name == "" then return end
    local list = self:CampBuffs()
    local i = campIndex(name, id)
    if i then table.remove(list, i) else list[#list + 1] = { n = name, id = id, icon = icon } end
    self:UpdateCampfire()
    return not i
end

function HL:ClearCampBuffs()
    self.settings.campBuffs = {}
    self:UpdateCampfire()
end

function HL:CampBuffText()
    local names = {}
    for _, b in ipairs(self:CampBuffs()) do names[#names + 1] = b.n end
    if #names == 0 then return "spell " .. CAMP_SPELL_ID end
    return "spell " .. CAMP_SPELL_ID .. ", " .. table.concat(names, ", ")
end

-- true / false (the campfire buff, the Boosted Rest debuff or any extra watched buff),
-- nil if aura data is hidden
function HL:HasCampBuff()
    local buffs = self:PlayerBuffs()
    if buffs then
        for _, a in ipairs(buffs) do
            if self:IsCampBuff(a.name, a.spellId) then return true end
        end
    end
    local rest = hasBoostedRest()
    if rest then return true end
    if not buffs or rest == nil then return nil end
    return false
end

-- /hl buffs: list your buffs so we can see how the game names them
function HL:PrintBuffs()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    self:Print("Your buffs:")
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        if HL.IsSecret(aura.name) or HL.IsSecret(aura.icon) or HL.IsSecret(aura.spellId) then
            print("  (hidden by the game right now)")
        else
            print(("  %s  |cff888888icon %s, spell %s%s%s|r"):format(tostring(aura.name), tostring(aura.icon),
                tostring(aura.spellId), isWellFedAura(aura.name, aura.icon) and ", |cff40ff40= Well Fed|r" or "",
                self:IsCampBuff(aura.name, aura.spellId) and ", |cff40ff40= campfire buff|r" or ""))
        end
    end
    local rest = hasBoostedRest()
    print("  Boosted Rest debuff: " .. (rest == nil and "(hidden by the game right now)" or rest and "|cff40ff40yes|r" or "no"))
end

---------------------------------------------------------------------------
-- On-screen reminders (one movable frame each)
---------------------------------------------------------------------------
-- opts: frameName, posKey, enabledKey, defaultY, text, icon(), has()
local function newReminder(opts)
    local r = { unlocked = false }
    local frame

    local function applyPosition()
        frame:ClearAllPoints()
        local p = HL.settings[opts.posKey]
        if type(p) == "table" and p[1] then
            frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, opts.defaultY)
        end
    end

    function r.create()
        frame = CreateFrame("Frame", opts.frameName, UIParent)
        frame:SetSize(opts.width or 340, 44)
        frame:SetFrameStrata("MEDIUM") -- below windows like /hl, above the game world
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            HL.settings[opts.posKey] = { point, relPoint, x, y }
        end)

        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints()
        frame.bg:SetColorTexture(0, 0, 0, 0.55)

        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetTexture(opts.icon())
        frame.icon:SetSize(32, 32)
        frame.icon:SetPoint("LEFT", 6, 0)

        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
        frame.text:SetTextColor(1, 0.55, 0.1)
        frame.text:SetText(opts.text)

        frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.hint:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        frame.hint:SetText("Drag to move – click \"Lock\" in /hl when done")

        local ag = frame.text:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.45)
        a:SetDuration(0.8)
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

    function r.update()
        if not frame or not HL.settings then return end
        frame.icon:SetTexture(opts.icon())

        -- Move mode: always visible, draggable, with background and hint
        frame:EnableMouse(r.unlocked)
        frame.bg:SetShown(r.unlocked)
        frame.hint:SetShown(r.unlocked)
        if r.unlocked then setVisible(true) return end

        if not HL.settings[opts.enabledKey] then setVisible(false) return end
        local okDead, dead = pcall(UnitIsDeadOrGhost, "player")
        if okDead and not HL.IsSecret(dead) and dead then setVisible(false) return end

        local has = opts.has()
        if has == nil then return end -- data hidden right now: keep the current state
        setVisible(not has)
    end

    function r.setUnlocked(state)
        r.unlocked = state and true or false
        r.update()
    end

    function r.resetPosition()
        HL.settings[opts.posKey] = nil
        if frame then applyPosition() end
    end

    return r
end

local wellFed = newReminder({
    frameName = "HuensListeWellFedFrame", posKey = "wellFedPos", enabledKey = "wellFedReminder",
    defaultY = 180, text = "You are not Well Fed!",
    icon = function() return FOOD_ICON end,
    has = function() return HL:HasWellFed() end,
})

local campfire = newReminder({
    frameName = "HuensListeCampfireFrame", posKey = "campfirePos", enabledKey = "campfireReminder",
    defaultY = 130, width = 480, text = "No campfire or Boosted Rest buff!",
    icon = campIcon,
    has = function() return HL:HasCampBuff() end,
})

function HL:UpdateWellFed() wellFed.update() end
function HL:IsWellFedUnlocked() return wellFed.unlocked end
function HL:SetWellFedUnlocked(state) wellFed.setUnlocked(state) end
function HL:ResetWellFedPosition() wellFed.resetPosition() end

function HL:UpdateCampfire() campfire.update() end
function HL:IsCampfireUnlocked() return campfire.unlocked end
function HL:SetCampfireUnlocked(state) campfire.setUnlocked(state) end
function HL:ResetCampfirePosition() campfire.resetPosition() end

-- Every Quality of Life option is opt-in: off until the player ticks it in the
-- Quality of Life tab. Add new options here with false.
local QOL_DEFAULTS = {
    wellFedReminder = false,
    campfireReminder = false,
    targetButton = false,
    quietPvP = false,
    quietCities = false,
    gankSuggest = false,
}

HL:On("PLAYER_LOGIN", function()
    for key, value in pairs(QOL_DEFAULTS) do
        if HL.settings[key] == nil then HL.settings[key] = value end
    end
    -- 1.3.0 to 1.5.0 switched the Well Fed reminder on automatically. Turn it off
    -- once, so it's only on for players who choose it.
    if not HL.settings.qolOptInDone then
        HL.settings.qolOptInDone = true
        HL.settings.wellFedReminder = false
    end
    wellFed.create()
    campfire.create()
    wellFed.update()
    campfire.update()
end)

HL:On("UNIT_AURA", function(unit)
    if unit == "player" then wellFed.update(); campfire.update() end
end)
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    HL:On(ev, function() wellFed.update(); campfire.update() end)
end
