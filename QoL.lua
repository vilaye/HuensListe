-- Huens Liste: quality-of-life features
--   Well Fed reminder: movable on-screen warning while you have no food buff
--   Campfire reminder: the same for the campfire buff / Boosted Rest debuff
--   Weapon imbue reminder: Windfury Weapon, poisons etc. (temporary weapon enchants),
--     with click-to-apply for the imbue / poison chosen per hand
--   Own buff reminder: the same for buffs the player picked (e.g. Find Minerals),
--     with click-to-cast when the buff is a spell you know
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

---------------------------------------------------------------------------
-- Own buff reminders: buffs the player picked (e.g. "Find Minerals")
---------------------------------------------------------------------------
-- settings.watchBuffs = { { n = name, id = spellId, icon = icon }, ... }
-- Unlike the campfire check, every watched buff has to be up.
function HL:WatchBuffs()
    local s = self.settings
    if type(s.watchBuffs) ~= "table" then s.watchBuffs = {} end
    return s.watchBuffs
end

local function watchIndex(name, id)
    local lower = type(name) == "string" and name:lower() or nil
    for i, b in ipairs(HL:WatchBuffs()) do
        if (id and b.id and b.id == id) or (lower and type(b.n) == "string" and b.n:lower() == lower) then return i end
    end
end

function HL:IsWatchedBuff(name, id) return watchIndex(name, id) ~= nil end

-- Add the buff to the watched ones, or remove it if it's already there.
-- Returns true if it is watched afterwards.
function HL:ToggleWatchBuff(name, id, icon)
    if type(name) ~= "string" or name == "" then return end
    local list = self:WatchBuffs()
    local i = watchIndex(name, id)
    if i then table.remove(list, i) else list[#list + 1] = { n = name, id = id, icon = icon } end
    self:UpdateBuffWatch()
    return not i
end

function HL:ClearWatchBuffs()
    self.settings.watchBuffs = {}
    self:UpdateBuffWatch()
end

function HL:WatchBuffText()
    local names = {}
    for _, b in ipairs(self:WatchBuffs()) do names[#names + 1] = b.n end
    if #names == 0 then return "none chosen yet" end
    return table.concat(names, ", ")
end

-- List of watched buffs that are not up right now; nil if aura data is hidden
function HL:MissingWatchBuffs()
    local watched = self:WatchBuffs()
    if #watched == 0 then return {} end
    local buffs = self:PlayerBuffs()
    if not buffs then return nil end
    local missing = {}
    for _, b in ipairs(watched) do
        local found = false
        local lower = type(b.n) == "string" and b.n:lower() or nil
        for _, a in ipairs(buffs) do
            if (b.id and a.spellId == b.id) or (lower and a.name:lower() == lower) then
                found = true
                -- learn spell ID and icon for buffs that were added by name
                if not b.id then b.id = a.spellId end
                if not b.icon then b.icon = a.icon end
                break
            end
        end
        if not found then missing[#missing + 1] = b end
    end
    return missing
end

---------------------------------------------------------------------------
-- Weapon imbues: Windfury Weapon, poisons, sharpening stones, oils ...
---------------------------------------------------------------------------
-- These are temporary weapon enchants, not buffs, so they never show up in the
-- aura list. The game reports them through GetWeaponEnchantInfo().
local SLOT_MAINHAND, SLOT_OFFHAND = 16, 17
local WEAPON_CLASS = 2 -- Enum.ItemClass.Weapon
local FISHING_POLE = 20 -- weapon subclass

-- true if that slot holds a real weapon (not a shield, an off-hand item or a fishing pole)
local function slotHasWeapon(slot)
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    if not ok or not id or HL.IsSecret(id) then return false end
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInfo then return true end
    local ok2, _, _, _, _, _, classID, subclassID = pcall(getInfo, id)
    if not ok2 then return true end
    return classID == WEAPON_CLASS and subclassID ~= FISHING_POLE
end

-- List of hands without an imbue ({ "main hand", "off hand" }); nil if the game hides it
function HL:MissingWeaponImbues()
    if not GetWeaponEnchantInfo then return nil end
    local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
    if not ok or HL.IsSecret(hasMain) or HL.IsSecret(hasOff) then return nil end
    local missing = {}
    if not hasMain and slotHasWeapon(SLOT_MAINHAND) then missing[#missing + 1] = "main hand" end
    if not hasOff and slotHasWeapon(SLOT_OFFHAND) then missing[#missing + 1] = "off hand" end
    return missing
end

---------------------------------------------------------------------------
-- Click to apply: the imbue / poison chosen for each hand
---------------------------------------------------------------------------
-- settings.imbue = { main = { kind = "item" | "spell", name, id, icon }, off = {...} }
local SHAMAN_IMBUES = { "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon", "Frostbrand Weapon",
    "Earthliving Weapon" }
-- words that mark an item as something you put on a weapon (sorted first in the picker)
local IMBUE_WORDS = { "poison", "stone", "oil", "gift", "wetzstein", "öl" }
local CONSUMABLE_CLASS = 0

function HL:ImbueConfig()
    local s = self.settings
    if type(s.imbue) ~= "table" then s.imbue = {} end
    return s.imbue
end

local function spellInfo(nameOrId)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, nameOrId)
        if ok and type(info) == "table" and info.name then
            return { kind = "spell", name = info.name, id = info.spellID, icon = info.iconID }
        end
    end
end

local function itemCount(id)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not get or not id then return 0 end
    local ok, n = pcall(get, id)
    return (ok and type(n) == "number") and n or 0
end

-- Everything that could go on a weapon: known shaman imbues, then usable consumables
-- from the bags (poisons, stones and oils first)
function HL:ImbueCandidates()
    local list, seen = {}, {}
    for _, name in ipairs(SHAMAN_IMBUES) do
        local sp = spellInfo(name)
        if sp and not seen["s" .. tostring(sp.id)] then
            seen["s" .. tostring(sp.id)] = true
            list[#list + 1] = sp
        end
    end
    local likely, others = {}, {}
    if C_Container and C_Container.GetContainerNumSlots then
        local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
        local getName = (C_Item and C_Item.GetItemNameByID) or function(id) return (GetItemInfo(id)) end
        for bag = 0, 5 do
            local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
            for slot = 1, (okN and tonumber(slots)) or 0 do
                local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                local id = okI and type(info) == "table" and info.itemID
                if id and not seen["i" .. id] then
                    seen["i" .. id] = true
                    local okC, _, _, _, _, icon, classID = pcall(getInstant, id)
                    local okS, useSpell = pcall(getSpell, id)
                    local okNm, name = pcall(getName, id)
                    if okC and classID == CONSUMABLE_CLASS and okS and useSpell and okNm and type(name) == "string" then
                        local entry = { kind = "item", name = name, id = id, icon = info.iconFileID or icon }
                        local lower, hit = name:lower(), false
                        for _, w in ipairs(IMBUE_WORDS) do
                            if lower:find(w, 1, true) then hit = true break end
                        end
                        if hit then likely[#likely + 1] = entry else others[#others + 1] = entry end
                    end
                end
            end
        end
    end
    for _, e in ipairs(likely) do list[#list + 1] = e end
    for _, e in ipairs(others) do list[#list + 1] = e end
    return list
end

local function sameImbue(a, b)
    return a and b and a.kind == b.kind and (a.id == b.id or (a.name and b.name and a.name:lower() == b.name:lower()))
end

function HL:IsImbueFor(hand, entry) return sameImbue(self:ImbueConfig()[hand], entry) and true or false end

-- Set the imbue for "main" / "off"; the same entry again clears it. Returns true if set.
function HL:SetImbue(hand, entry)
    if hand ~= "main" and hand ~= "off" then return end
    local cfg = self:ImbueConfig()
    if not entry or sameImbue(cfg[hand], entry) then
        cfg[hand] = nil
    else
        cfg[hand] = { kind = entry.kind, name = entry.name, id = entry.id, icon = entry.icon }
    end
    self:UpdateWeaponImbue()
    return cfg[hand] ~= nil
end

-- /hl imbue main Instant Poison: a known spell with that name, else an item
function HL:SetImbueByName(hand, name)
    if type(name) ~= "string" or name == "" then return self:SetImbue(hand, nil) end
    local entry = spellInfo(name)
    if not entry then
        for _, c in ipairs(self:ImbueCandidates()) do
            if c.name:lower() == name:lower() then entry = c break end
        end
    end
    entry = entry or { kind = "item", name = name }
    self:ImbueConfig()[hand] = nil
    return self:SetImbue(hand, entry)
end

function HL:ImbueText()
    local cfg = self:ImbueConfig()
    return ("main hand: %s, off hand: %s"):format(cfg.main and cfg.main.name or "nothing chosen",
        cfg.off and cfg.off.name or "nothing chosen")
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
                (self:IsCampBuff(aura.name, aura.spellId) and ", |cff40ff40= campfire buff|r" or "")
                .. (self:IsWatchedBuff(aura.name, aura.spellId) and ", |cff40ff40= watched|r" or "")))
        end
    end
    if GetWeaponEnchantInfo then
        local ok, hasMain, _, _, mainId, hasOff, _, _, offId = pcall(GetWeaponEnchantInfo)
        if not ok or HL.IsSecret(hasMain) or HL.IsSecret(hasOff) then
            print("  Weapon imbues: (hidden by the game right now)")
        else
            print(("  Weapon imbues: main hand %s, off hand %s"):format(
                hasMain and ("|cff40ff40yes|r (enchant " .. tostring(mainId) .. ")") or "no",
                hasOff and ("|cff40ff40yes|r (enchant " .. tostring(offId) .. ")") or "no"))
        end
    end
    local rest = hasBoostedRest()
    print("  Boosted Rest debuff: " .. (rest == nil and "(hidden by the game right now)" or rest and "|cff40ff40yes|r" or "no"))
end

---------------------------------------------------------------------------
-- On-screen reminders (one movable frame each)
---------------------------------------------------------------------------
-- opts: frameName, posKey, enabledKey, defaultY, text (string or function), icon(), has()
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
            if opts.after then opts.after() end
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
        frame.text:SetText(type(opts.text) == "function" and opts.text() or opts.text)

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
        if opts.onCreate then opts.onCreate(frame) end
    end

    function r.frame() return frame end
    function r.shown() return frame and frame:IsShown() and not r.unlocked or false end

    local function setVisible(show)
        if show then
            if not frame:IsShown() then frame:Show(); frame.anim:Play() end
        else
            frame.anim:Stop()
            frame:Hide()
        end
    end

    local function updateInner()
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
        if not has and type(opts.text) == "function" then
            frame.text:SetText(opts.text())
            frame.icon:SetTexture(opts.icon())
        end
        setVisible(not has)
    end

    function r.update()
        updateInner()
        if frame and opts.after then opts.after() end
    end

    function r.setUnlocked(state)
        r.unlocked = state and true or false
        r.update()
    end

    function r.resetPosition()
        HL.settings[opts.posKey] = nil
        if frame then applyPosition() end
        if frame and opts.after then opts.after() end
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

-- Click part of a reminder: a secure button laid over the text. The game doesn't let
-- addons show, hide, move or change such a button in combat, so it lives in a holder
-- that the game itself hides in combat, and everything else is done out of combat only.
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function newClicker(buttonName)
    local c = {}
    local holder = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    holder:SetAllPoints(UIParent)
    if RegisterStateDriver then RegisterStateDriver(holder, "visibility", "[combat] hide; show") end
    local button = CreateFrame("Button", buttonName, holder, "SecureActionButtonTemplate")
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(20)
    button:RegisterForClicks("AnyUp", "AnyDown")
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)
    button:Hide()

    local function setClick(n, click)
        local sfx = tostring(n)
        if not click then
            button:SetAttribute("type" .. sfx, nil)
            return
        end
        button:SetAttribute("type" .. sfx, click.kind)
        if click.kind == "spell" then
            button:SetAttribute("spell" .. sfx, click.name)
            button:SetAttribute("target-slot" .. sfx, nil)
        else
            button:SetAttribute("item" .. sfx, click.name)
            button:SetAttribute("target-slot" .. sfx, click.slot)
        end
    end

    -- clicks: up to two of { kind = "spell" | "item", name, slot }: left and right click.
    -- Does nothing in combat (the game hides the button there anyway).
    function c.set(frame, clicks)
        if inCombat() then return end
        if not frame or #clicks == 0 then button:Hide() return end
        local x, y = frame:GetCenter()
        if not x or not y then button:Hide() return end
        button:ClearAllPoints()
        button:SetSize(frame:GetWidth(), frame:GetHeight())
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        setClick(1, clicks[1])
        setClick(2, clicks[2])
        button:Show()
    end
    return c
end

local MOVE_HINT = "Drag to move – click \"Lock\" in /hl when done"

-- Own buffs: one frame that names what is missing
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local missingNow = {}
local buffWatch, buffClicker

-- Left / right click cast the first two missing buffs that are spells you know
local function updateBuffClicker()
    if not buffClicker or not buffWatch then return end
    local frame = buffWatch.frame()
    if not frame then return end
    local clicks = {}
    if buffWatch.shown() then
        for _, b in ipairs(missingNow) do
            local sp = spellInfo(b.n)
            if sp and #clicks < 2 then clicks[#clicks + 1] = { kind = "spell", name = sp.name } end
        end
    end
    local hint
    if buffWatch.unlocked then
        hint = MOVE_HINT
    elseif #clicks > 0 then
        hint = "Left-click: " .. clicks[1].name
        if clicks[2] then hint = hint .. "  ·  Right-click: " .. clicks[2].name end
        if inCombat() then hint = "Click to cast after combat" end
    end
    frame.hint:SetText(hint or "")
    frame.hint:SetShown(hint ~= nil)
    buffClicker.set(frame, clicks)
end

buffWatch = newReminder({
    frameName = "HuensListeBuffWatchFrame", posKey = "buffWatchPos", enabledKey = "buffWatchReminder",
    defaultY = 80, width = 480,
    text = function()
        local names = {}
        for _, b in ipairs(missingNow) do names[#names + 1] = b.n end
        if #names == 0 then return "Missing: your buff" end -- move mode
        return "Missing: " .. table.concat(names, ", ")
    end,
    icon = function() return (missingNow[1] and missingNow[1].icon) or QUESTION_ICON end,
    has = function()
        local missing = HL:MissingWatchBuffs()
        if not missing then return nil end
        missingNow = missing
        return #missing == 0
    end,
    onCreate = function() buffClicker = newClicker("HuensListeBuffButton") end,
    after = updateBuffClicker,
})

-- Weapon imbues: names the hand(s) without one
local WEAPON_ICON = "Interface\\Icons\\INV_Sword_04"
local missingHands = {}
local weaponImbue

local imbueClicker
local HAND_SLOT = { ["main hand"] = SLOT_MAINHAND, ["off hand"] = SLOT_OFFHAND }
local HAND_KEY = { ["main hand"] = "main", ["off hand"] = "off" }

-- what a click would do for that hand: entry, or nil plus the reason
local function imbueAction(hand)
    local entry = HL:ImbueConfig()[HAND_KEY[hand]]
    if not entry then return nil end
    if entry.kind == "item" and entry.id and itemCount(entry.id) == 0 then
        return nil, "no " .. entry.name .. " in your bags"
    end
    return entry
end

-- Left click: first missing hand with a chosen imbue. Right click: the second one.
local function updateImbueButton()
    if not imbueClicker or not weaponImbue then return end
    local frame = weaponImbue.frame()
    if not frame then return end

    local clicks, problems = {}, {}
    if weaponImbue.shown() then
        for _, hand in ipairs(missingHands) do
            local entry, why = imbueAction(hand)
            if entry then clicks[#clicks + 1] = { hand = hand, entry = entry }
            elseif why then problems[#problems + 1] = why end
        end
    end

    -- hint under the text (plain text, fine in combat)
    local hint
    if weaponImbue.unlocked then
        hint = MOVE_HINT
    elseif #clicks > 0 then
        hint = "Left-click: " .. clicks[1].entry.name .. " (" .. clicks[1].hand .. ")"
        if clicks[2] then hint = hint .. "  ·  Right-click: " .. clicks[2].entry.name .. " (" .. clicks[2].hand .. ")" end
        if inCombat() then hint = "Click to apply after combat" end
    elseif #problems > 0 then
        hint = problems[1]:sub(1, 1):upper() .. problems[1]:sub(2)
    end
    frame.hint:SetText(hint or "")
    frame.hint:SetShown(hint ~= nil and (weaponImbue.unlocked or weaponImbue.shown()))

    local list = {}
    for i, c in ipairs(clicks) do
        list[i] = { kind = c.entry.kind, slot = HAND_SLOT[c.hand],
            name = c.entry.name or ("item:" .. tostring(c.entry.id)) }
    end
    imbueClicker.set(frame, list)
end

weaponImbue = newReminder({
    frameName = "HuensListeWeaponFrame", posKey = "weaponPos", enabledKey = "weaponReminder",
    defaultY = 30, width = 480,
    text = function()
        if #missingHands == 0 then return "No weapon imbue!" end -- move mode
        return "No weapon imbue: " .. table.concat(missingHands, " + ")
    end,
    icon = function()
        local slot = (missingHands[1] == "off hand") and SLOT_OFFHAND or SLOT_MAINHAND
        local ok, tex = pcall(GetInventoryItemTexture, "player", slot)
        if ok and tex and not HL.IsSecret(tex) then return tex end
        return WEAPON_ICON
    end,
    has = function()
        local missing = HL:MissingWeaponImbues()
        if not missing then return nil end
        missingHands = missing
        return #missing == 0
    end,
    onCreate = function() imbueClicker = newClicker("HuensListeImbueButton") end,
    after = updateImbueButton,
})

function HL:UpdateWeaponImbue() weaponImbue.update() end
function HL:IsWeaponImbueUnlocked() return weaponImbue.unlocked end
function HL:SetWeaponImbueUnlocked(state) weaponImbue.setUnlocked(state) end
function HL:ResetWeaponImbuePosition() weaponImbue.resetPosition() end

function HL:UpdateBuffWatch() buffWatch.update() end
function HL:IsBuffWatchUnlocked() return buffWatch.unlocked end
function HL:SetBuffWatchUnlocked(state) buffWatch.setUnlocked(state) end
function HL:ResetBuffWatchPosition() buffWatch.resetPosition() end

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
    buffWatchReminder = false,
    weaponReminder = false,
    targetButton = false,
    quietPvP = false,
    quietCities = false,
    gankSuggest = false,
    shareLocation = false,
    showFriendsOnMap = false,
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
    buffWatch.create()
    weaponImbue.create()
    wellFed.update()
    campfire.update()
    buffWatch.update()
    weaponImbue.update()
end)

HL:On("UNIT_AURA", function(unit)
    if unit == "player" then wellFed.update(); campfire.update(); buffWatch.update() end
end)
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    HL:On(ev, function() wellFed.update(); campfire.update(); buffWatch.update(); weaponImbue.update() end)
end

-- Weapon imbues change with UNIT_INVENTORY_CHANGED; swapping weapons also matters
HL:On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then weaponImbue.update() end
end)
HL:On("PLAYER_EQUIPMENT_CHANGED", function() weaponImbue.update() end)
-- bought or used up the poison; combat started (the click part is hidden by the game)
HL:On("BAG_UPDATE_DELAYED", function() weaponImbue.update() end)
HL:On("PLAYER_REGEN_DISABLED", function() weaponImbue.update(); buffWatch.update() end)
