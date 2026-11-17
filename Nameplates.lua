-- Huens Liste: nameplate marker, alerts, tooltip line
--
-- WoW Forever uses Midnight's addon rules: the combat log is closed to addons,
-- so we detect players the way the player does - nameplates, target, mouseover.
local _, HL = ...
local overlays = {}

local function plateUsable(plate)
    return plate and not (plate.IsForbidden and plate:IsForbidden())
end

local function getOverlay(plate)
    local o = overlays[plate]
    if o then return o end
    o = CreateFrame("Frame", nil, plate)
    o:SetSize(90, 44)
    o:SetFrameLevel((plate:GetFrameLevel() or 0) + 20)

    o.icon = o:CreateTexture(nil, "OVERLAY")
    o.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") -- skull
    o.icon:SetSize(26, 26)
    o.icon:SetPoint("TOP", o, "TOP")

    o.text = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.text:SetPoint("TOP", o.icon, "BOTTOM", 0, -1)
    o.text:SetTextColor(1, 0.15, 0.15)
    o.text:SetShadowOffset(1, -1)
    o.text:SetText("KILL ON SIGHT")

    o.bounty = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.bounty:SetPoint("BOTTOM", o.icon, "TOP", 0, 1)
    o.bounty:SetTextColor(1, 0.82, 0)
    o.bounty:SetShadowOffset(1, -1)

    local ag = o.icon:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.5)
    o.anim = ag

    o:Hide()
    overlays[plate] = o
    return o
end

local function hideOverlay(plate)
    local o = overlays[plate]
    if o then o.anim:Stop(); o:Hide() end
end

local function safeUnitInfo(unit)
    local okL, lvl = pcall(UnitLevel, unit)
    local okC, cls = pcall(UnitClass, unit)
    if not okL or HL.IsSecret(lvl) then lvl = nil end
    if not okC or HL.IsSecret(cls) then cls = nil end
    if lvl == -1 then lvl = "??" end
    if lvl and cls then return " (" .. lvl .. " " .. cls .. ")" end
    if lvl or cls then return " (" .. (lvl or cls) .. ")" end
    return ""
end

-- Quiet zones (Quality of Life, opt-in): no KOS alerts, sharing or log entries in
-- battlegrounds/arenas, or in cities, inns and sanctuaries. The skull still shows.
function HL:InQuietZone()
    local s = self.settings
    if s.quietPvP then
        local ok, _, kind = pcall(IsInInstance)
        if ok and not HL.IsSecret(kind) and (kind == "pvp" or kind == "arena") then return true end
    end
    if s.quietCities then
        local ok, resting = pcall(IsResting)
        if ok and not HL.IsSecret(resting) and resting then return true end
        local zoneInfo = (C_PvP and C_PvP.GetZonePVPInfo) or GetZonePVPInfo
        if zoneInfo then
            local ok2, pvpType = pcall(zoneInfo)
            if ok2 and not HL.IsSecret(pvpType) and pvpType == "sanctuary" then return true end
        end
    end
    return false
end

function HL:OnSighting(full, e, unit)
    local key = HL.Key(full)
    if unit then self:NoteUnitInfo(unit, e.n) end
    if self:InQuietZone() then return end
    if self:Throttled("seen:" .. key, self.settings.alertCooldown) then return end
    local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
    self.db.seen[key] = { t = GetServerTime(), z = zone, s = sub, by = self.me }
    if self.LogSighting then self:LogSighting(e.n, zone, sub, self.me) end

    if self.settings.alerts then
        local name = HL.ShortName(e.n)
        local info = unit and safeUnitInfo(unit) or ""
        -- high priority and revenge targets always get the banner and sound;
        -- normal ones too, unless "chat line only" is set in the Options tab
        local prio, revenge = self:IsPriority(e.n), self:IsRevenge(e.n)
        local loud = prio or revenge or not self.settings.normalQuiet
        if loud and RaidNotice_AddMessage and RaidWarningFrame then
            local label = revenge and "|cffff8000REVENGE: " or (prio and "|cffffd100HIGH PRIORITY KOS: " or "|cffff2020KILL ON SIGHT: ")
            RaidNotice_AddMessage(RaidWarningFrame, label .. name .. "|r", ChatTypeInfo["RAID_WARNING"])
        end
        local bounty = self:Bounty(e.n)
        self:Print((revenge and "|cffff8000[Revenge]|r " or "") .. (prio and "|cffffd100[High priority]|r " or "")
            .. "|cffff4040" .. name .. "|r" .. info .. " is nearby!" .. (e.r ~= "" and (" – " .. e.r) or "")
            .. (bounty and (" – |cffffd100Bounty: " .. bounty.r .. "|r") or ""))
        if self.settings.sound and loud and SOUNDKIT then
            HL.PlaySoundSafe((prio or revenge) and (SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.RAID_WARNING) or SOUNDKIT.RAID_WARNING)
        end
    end

    if self.settings.shareSightings and self.Broadcast then
        local i = self:Info(e.n) or {}
        self:Broadcast(table.concat({ "S", e.n, HL.Clean(zone, 60), HL.Clean(sub, 60), i.c or "", tostring(i.l or "") }, HL.RS), "high")
    end
end

-- The KOS skull only goes on enemy-faction players. If the faction can't be read
-- (rare), we still mark them, so a real enemy is never missed.
HL.kosPlates = {} -- [nameplate unit] = KOS name, for the plates on screen right now

local function kosEntryFor(unit, full)
    local e = full and HL:Get(full, "kos")
    if e and HL.FactionRelation(unit) ~= "friendly" then return e end
end

function HL:UpdatePlate(unit)
    if not self.db then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plateUsable(plate) then return end
    local full = HL.UnitFullName(unit)
    local e = kosEntryFor(unit, full)
    if not HL.IsSecret(unit) then HL.kosPlates[unit] = e and e.n or nil end
    if not e then
        hideOverlay(plate)
        return
    end

    if self.NoteKOSNearby then self:NoteKOSNearby(e.n) end
    local o = getOverlay(plate)
    o:ClearAllPoints()
    o:SetPoint("BOTTOM", plate.UnitFrame or plate, "TOP", 0, self.settings.plateOffsetY or 0)
    o:SetScale(self.settings.plateScale or 1)
    local bounty = self:Bounty(e.n)
    o.bounty:SetText(bounty and ("Bounty: " .. bounty.r) or "")
    local prio = self:IsPriority(e.n)
    if self:IsRevenge(e.n) then
        o.text:SetText("REVENGE")
        o.text:SetTextColor(1, 0.5, 0)
        o.icon:SetVertexColor(1, 0.6, 0.2)
    elseif prio then
        o.text:SetText("HIGH PRIORITY")
        o.text:SetTextColor(1, 0.82, 0)
        o.icon:SetVertexColor(1, 0.85, 0.3)
    else
        o.text:SetText("KILL ON SIGHT")
        o.text:SetTextColor(1, 0.15, 0.15)
        o.icon:SetVertexColor(1, 1, 1)
    end
    if prio then o:SetScale((self.settings.plateScale or 1) * 1.25) end
    o:Show()
    o.anim:Play()
    self:OnSighting(full, e, unit)
end

function HL:RefreshPlates()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        if plateUsable(plate) then
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then self:UpdatePlate(unit) else hideOverlay(plate) end
        end
    end
end

---------------------------------------------------------------------------
-- Avoid List: chat message + sound, no skull
---------------------------------------------------------------------------
function HL:AvoidAlert(full, e, what)
    if not self.settings.avoidAlerts then return end
    local key = HL.Key(full)
    -- joining your group always alerts; whispers at most once per 2 minutes per player
    if what ~= "joined your group" and self:Throttled("avoid:" .. what .. ":" .. key, 120) then return end
    self:Print(("|cffffaa00Swine List:|r %s %s%s"):format(HL.ColorName(HL.ShortName(e.n), "avoid"), what,
        e.r ~= "" and (" – " .. e.r) or ""))
    if self.settings.sound then HL.PlaySoundSafe(SOUNDKIT and (SOUNDKIT.ALARM_CLOCK_WARNING_3 or SOUNDKIT.RAID_WARNING)) end
end

local function checkUnit(unit)
    local full = HL.UnitFullName(unit)
    if not full then return end
    local e = kosEntryFor(unit, full)
    if e then
        if HL.NoteKOSNearby then HL:NoteKOSNearby(e.n) end
        HL:OnSighting(full, e, unit)
        return
    end
    if HL:Get(full, "avoid") then HL:NoteUnitInfo(unit, full) end
end

-- Swine List alerts only for direct contact: they join your group, you join theirs,
-- or they whisper you. Standing next to them doesn't alert.

-- Whispers
HL:On("CHAT_MSG_WHISPER", function(msg, sender)
    if not HL.db or HL.IsSecret(sender) or type(sender) ~= "string" then return end
    local full = HL.SenderId(sender)
    local a = full and HL:Get(full, "avoid")
    if a then HL:AvoidAlert(full, a, "whispered you") end
end)

-- Group: alert when a Swine List player joins, or when you join a group they're in
local groupMembers, wasInGroup = {}, false
local function scanGroup()
    if not HL.db then return end
    local inGroup = IsInGroup()
    local current = {}
    if inGroup then
        local raid = IsInRaid()
        local count = raid and GetNumGroupMembers() or (GetNumGroupMembers() - 1)
        for i = 1, count do
            local unit = (raid and "raid" or "party") .. i
            local full = HL.UnitFullName(unit)
            if full and full ~= HL.me then
                local key = HL.Key(full)
                current[key] = true
                if not groupMembers[key] then
                    local a = HL:Get(full, "avoid")
                    if a then HL:NoteUnitInfo(unit, full) end
                    if a then HL:AvoidAlert(full, a, wasInGroup and "joined your group" or "is in this group") end
                end
            end
        end
    end
    groupMembers, wasInGroup = current, inGroup
end

HL:On("GROUP_ROSTER_UPDATE", scanGroup)
HL:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, scanGroup) end)
HL:On("UNIT_NAME_UPDATE", function(unit)
    if type(unit) == "string" and not HL.IsSecret(unit) and (unit:find("^party") or unit:find("^raid")) then scanGroup() end
end)

HL:On("NAME_PLATE_UNIT_ADDED", function(unit) HL:UpdatePlate(unit) end)
HL:On("NAME_PLATE_UNIT_REMOVED", function(unit)
    if unit and not HL.IsSecret(unit) then HL.kosPlates[unit] = nil end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plateUsable(plate) then hideOverlay(plate) end
end)
HL:On("PLAYER_TARGET_CHANGED", function() checkUnit("target") end)
HL:On("UPDATE_MOUSEOVER_UNIT", function() checkUnit("mouseover") end)
HL:OnChange(function() HL:RefreshPlates() end)

-- Make sure enemy nameplates are on, otherwise there is nothing to mark.
HL:On("PLAYER_LOGIN", function()
    if HL.settings.avoidAlerts == nil then HL.settings.avoidAlerts = true end
    if GetCVar("nameplateShowEnemies") == "0" then
        pcall(SetCVar, "nameplateShowEnemies", "1")
        HL:Print("Turned on enemy nameplates so KOS players can be marked.")
    end
end)

-- Tooltip lines
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip or not HL.db then return end
        local ok, _, unit = pcall(tt.GetUnit, tt)
        if not ok or not unit then return end
        local full = HL.UnitFullName(unit)
        local list, e = HL:Find(full or "")
        if not e then return end
        if list == "kos" then
            if HL.FactionRelation(unit) == "friendly" then
                tt:AddLine("|cffff4040Huens Liste: on the KOS List, but same faction|r")
                tt:AddLine("Move them to the Swine List in /hl", 0.6, 0.6, 0.6)
            else
                tt:AddLine("|cffff2020Huens Liste: KILL ON SIGHT|r")
            end
        else
            tt:AddLine("|cffffaa00Huens Liste: Swine List|r")
        end
        if e.r ~= "" then tt:AddLine(e.r, 1, 0.8, 0.6, true) end
        local bounty = list == "kos" and HL:Bounty(e.n)
        if bounty then tt:AddLine("Bounty: " .. bounty.r .. " (set by " .. HL.ShortName(bounty.b) .. ")", 1, 0.82, 0, true) end
        if list == "kos" then
            local count = HL:KillStats(e.n)
            if count > 0 then tt:AddLine(("Killed %d time%s"):format(count, count == 1 and "" or "s"), 1, 0.5, 0.5) end
            local deaths = HL:DeathStats(e.n)
            if deaths > 0 then tt:AddLine(("Killed you or friends %d time%s"):format(deaths, deaths == 1 and "" or "s"), 0.75, 0.45, 1) end
        end
        tt:AddLine("added by " .. HL.ShortName(e.b) .. " on " .. date("%d.%m.%Y", e.t), 0.6, 0.6, 0.6)
    end)
end
