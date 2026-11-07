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

function HL:OnSighting(full, e, unit)
    local key = HL.Key(full)
    if self:Throttled("seen:" .. key, self.settings.alertCooldown) then return end
    local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
    self.db.seen[key] = { t = GetServerTime(), z = zone, s = sub, by = self.me }

    if self.settings.alerts then
        local name = HL.ShortName(e.n)
        local info = unit and safeUnitInfo(unit) or ""
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, "|cffff2020KILL ON SIGHT: " .. name .. "|r", ChatTypeInfo["RAID_WARNING"])
        end
        self:Print("|cffff4040" .. name .. "|r" .. info .. " is nearby!" .. (e.r ~= "" and (" – " .. e.r) or ""))
        if self.settings.sound then HL.PlaySoundSafe(SOUNDKIT and SOUNDKIT.RAID_WARNING) end
    end

    if self.settings.shareSightings and self.Broadcast then
        self:Broadcast("S" .. HL.RS .. e.n .. HL.RS .. HL.Clean(zone, 60) .. HL.RS .. HL.Clean(sub, 60), "high")
    end
end

function HL:UpdatePlate(unit)
    if not self.db then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plateUsable(plate) then return end
    local full = HL.UnitFullName(unit)
    local e = full and self:Get(full)
    if not e then hideOverlay(plate) return end

    local o = getOverlay(plate)
    o:ClearAllPoints()
    o:SetPoint("BOTTOM", plate.UnitFrame or plate, "TOP", 0, self.settings.plateOffsetY or 0)
    o:SetScale(self.settings.plateScale or 1)
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

local function checkUnit(unit)
    local full = HL.UnitFullName(unit)
    local e = full and HL:Get(full)
    if e then HL:OnSighting(full, e, unit) end
end

HL:On("NAME_PLATE_UNIT_ADDED", function(unit) HL:UpdatePlate(unit) end)
HL:On("NAME_PLATE_UNIT_REMOVED", function(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plateUsable(plate) then hideOverlay(plate) end
end)
HL:On("PLAYER_TARGET_CHANGED", function() checkUnit("target") end)
HL:On("UPDATE_MOUSEOVER_UNIT", function() checkUnit("mouseover") end)
HL:OnChange(function() HL:RefreshPlates() end)

-- Make sure enemy nameplates are on, otherwise there is nothing to mark.
HL:On("PLAYER_LOGIN", function()
    if GetCVar("nameplateShowEnemies") == "0" then
        pcall(SetCVar, "nameplateShowEnemies", "1")
        HL:Print("Turned on enemy nameplates so KOS players can be marked.")
    end
end)

-- Tooltip line
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
        if tt ~= GameTooltip or not HL.db then return end
        local ok, _, unit = pcall(tt.GetUnit, tt)
        if not ok or not unit then return end
        local full = HL.UnitFullName(unit)
        local e = full and HL:Get(full)
        if not e then return end
        tt:AddLine("|cffff2020Huens Liste: KILL ON SIGHT|r")
        if e.r ~= "" then tt:AddLine(e.r, 1, 0.6, 0.6, true) end
        tt:AddLine("added by " .. Ambiguate(e.b ~= "" and e.b or "?", "short") .. " on " .. date("%d.%m.%Y", e.t), 0.6, 0.6, 0.6)
    end)
end
