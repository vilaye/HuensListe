-- Huens Liste - Mount.lua
-- Riding trinket (Quality of Life, opt-in): equips a trinket such as the Carrot on a
-- Stick while you are mounted and puts your normal trinket back when you dismount.
-- Gear can't be swapped in combat, so a swap that comes up in a fight happens right after it.
local ADDON, HL = ...

local CARROT = { id = 11122, name = "Carrot on a Stick" }
local TRINKET_SLOTS = { 13, 14 }      -- upper, lower
local DEFAULT_SLOT = 14
local RETRY = 1.0                     -- seconds between swap attempts

-- settings.mountTrinketItem = { id, name, icon }   the riding trinket
-- settings.mountTrinketSlot = 13 | 14              the slot it goes into
-- settings.mountTrinketPrev = itemID               what was in that slot before

function HL:MountTrinket()
    local it = self.settings.mountTrinketItem
    if type(it) ~= "table" or not it.id then
        it = { id = CARROT.id, name = CARROT.name }
        self.settings.mountTrinketItem = it
    end
    return it
end

function HL:MountTrinketSlot()
    local slot = self.settings.mountTrinketSlot
    if slot ~= 13 and slot ~= 14 then slot = DEFAULT_SLOT; self.settings.mountTrinketSlot = slot end
    return slot
end

local function slotItem(slot)
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    if ok and id and not HL.IsSecret(id) then return id end
end

local function countOf(id)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not get or not id then return 0 end
    local ok, n = pcall(get, id)
    return (ok and type(n) == "number") and n or 0
end

local function itemName(id)
    local get = (C_Item and C_Item.GetItemNameByID) or function(i) return (GetItemInfo(i)) end
    local ok, name = pcall(get, id)
    return (ok and type(name) == "string") and name or nil
end

local function equip(id, slot)
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if not fn then return false end
    return (pcall(fn, id, slot))
end

-- true / false, nil if the game doesn't say
local function mounted()
    if not IsMounted then return nil end
    local ok, m = pcall(IsMounted)
    if not ok or HL.IsSecret(m) then return nil end
    if m and UnitOnTaxi then
        local ok2, taxi = pcall(UnitOnTaxi, "player")
        if ok2 and not HL.IsSecret(taxi) and taxi then return false end -- flight path, not riding
    end
    return m and true or false
end

local function inPvPInstance()
    local ok, _, kind = pcall(IsInInstance)
    return ok and not HL.IsSecret(kind) and (kind == "pvp" or kind == "arena")
end

local lastTry = 0

-- Looks at mount state and trinket slot and swaps if needed. Safe to call any time.
function HL:CheckMountTrinket()
    local s = self.settings
    if not s then return end
    local slot = self:MountTrinketSlot()
    local ride = self:MountTrinket()
    local worn = slotItem(slot)

    if InCombatLockdown and InCombatLockdown() then return end -- retried after the fight
    local okD, dead = pcall(UnitIsDeadOrGhost, "player")
    if okD and not HL.IsSecret(dead) and dead then return end
    if CursorHasItem and CursorHasItem() then return end
    local now = GetTime()
    if now - lastTry < RETRY then return end

    local isMounted = mounted()
    if isMounted == nil then return end

    if isMounted and s.mountTrinket then
        if worn == ride.id then return end
        local other = slotItem(slot == 13 and 14 or 13)
        if other == ride.id then return end              -- already worn in the other slot
        if countOf(ride.id) == 0 then return end         -- not in the bags
        if inPvPInstance() then return end
        if worn then s.mountTrinketPrev = worn end
        lastTry = now
        equip(ride.id, slot)
    elseif not isMounted then
        -- put the normal trinket back (also after the option was switched off while mounted)
        local prev = s.mountTrinketPrev
        if not prev then return end
        if worn ~= ride.id then s.mountTrinketPrev = nil return end -- swapped by hand meanwhile
        if prev == ride.id or countOf(prev) == 0 then s.mountTrinketPrev = nil return end
        lastTry = now
        equip(prev, slot)
    end
end

function HL:SetMountTrinket(id, name, icon)
    if not id then return end
    self.settings.mountTrinketItem = { id = id, name = name or itemName(id) or ("item " .. id), icon = icon }
    self:CheckMountTrinket()
end

function HL:SetMountTrinketSlot(slot)
    if slot ~= 13 and slot ~= 14 then return end
    self.settings.mountTrinketSlot = slot
    self.settings.mountTrinketPrev = nil
    self:CheckMountTrinket()
end

-- Trinkets you own: equipped ones and those in the bags; the chosen one and the carrot first
function HL:TrinketCandidates()
    local list, seen = {}, {}
    local function add(id, icon)
        if not id or seen[id] then return end
        seen[id] = true
        list[#list + 1] = { id = id, name = itemName(id) or ("item " .. id), icon = icon }
    end
    local ride = self:MountTrinket()
    add(ride.id, ride.icon)
    add(CARROT.id)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local function isTrinket(id)
        local ok, _, _, _, equipLoc, icon = pcall(getInstant, id)
        return ok and equipLoc == "INVTYPE_TRINKET", icon
    end
    for _, slot in ipairs(TRINKET_SLOTS) do
        local id = slotItem(slot)
        if id then local _, icon = isTrinket(id); add(id, icon) end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
            for i = 1, (okN and tonumber(slots)) or 0 do
                local okI, info = pcall(C_Container.GetContainerItemInfo, bag, i)
                local id = okI and type(info) == "table" and info.itemID
                if id and not seen[id] then
                    local yes, icon = isTrinket(id)
                    if yes then add(id, info.iconFileID or icon) end
                end
            end
        end
    end
    return list
end

function HL:MountTrinketText()
    return ("%s in the %s trinket slot"):format(self:MountTrinket().name,
        self:MountTrinketSlot() == 13 and "upper" or "lower")
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function check() HL:CheckMountTrinket() end

HL:On("PLAYER_LOGIN", function()
    if HL.settings.mountTrinket == nil then HL.settings.mountTrinket = false end
    -- Backup for clients that don't fire the mount event; a few cheap checks, nothing more
    C_Timer.NewTicker(2, function()
        if HL.settings.mountTrinket or HL.settings.mountTrinketPrev then check() end
    end)
end)

for _, ev in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    HL:On(ev, check)
end
