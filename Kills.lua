-- Huens Liste: KOS kill counter
--
-- Addons can't read the combat log anymore, so kills come from the honor message
-- ("Gank Lord dies, honorable kill ..."). You get that message when you or someone
-- in your group kills an enemy player. If the victim is on the KOS List, we record
-- a credit for ourselves and share it. Several friends in one group each record a
-- credit for the same kill; those count as one kill with several killers.
local _, HL = ...

local EVENT_WINDOW = 20 -- credits for the same victim within 20 s are one kill (group members credit at once)

---------------------------------------------------------------------------
-- Honor message -> victim name
---------------------------------------------------------------------------
-- Turn a localized format string ("%s dies, honorable kill Rank: %s ...") into a
-- Lua pattern that captures the first %s.
local function patternFromFormat(fmt)
    if type(fmt) ~= "string" or fmt == "" then return end
    fmt = fmt:gsub("%%%d+%$", "%%")                         -- "%1$s" -> "%s"
    local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")  -- escape magic characters
    p = p:gsub("%%s", "(.-)"):gsub("%%d", "%%d+")
    return "^" .. p .. "$"
end

local patterns
local function honorPatterns()
    if patterns then return patterns end
    patterns = {}
    for _, g in ipairs({ "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORGAIN_EXHAUSTION1" }) do
        local p = patternFromFormat(_G[g])
        if p then patterns[#patterns + 1] = p end
    end
    -- fallback if the client doesn't define the strings (English)
    patterns[#patterns + 1] = "^(.-) dies, honorable kill"
    return patterns
end
HL.HonorPatterns = honorPatterns -- for testing

function HL.VictimFromHonorMessage(msg)
    if type(msg) ~= "string" or HL.IsSecret(msg) then return end
    for _, p in ipairs(honorPatterns()) do
        local victim = msg:match(p)
        if victim and victim ~= "" then return victim end
    end
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
local function creditsFor(full)
    local key = HL.Key(HL.NormalizeName(full) or full)
    local list = {}
    for _, c in pairs(HL:Entries("kills")) do
        if HL.Key(c.n) == key then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

-- count, killers { [display name] = kills }, last credit
function HL:KillStats(full)
    local credits = creditsFor(full)
    local count, eventStart = 0, nil
    local killers, seenInEvent = {}, {}
    for _, c in ipairs(credits) do
        if not eventStart or c.t - eventStart > EVENT_WINDOW then
            count = count + 1
            eventStart = c.t
            seenInEvent = {}
        end
        local who = HL.ShortName(c.b)
        if not seenInEvent[who] then
            seenInEvent[who] = true
            killers[who] = (killers[who] or 0) + 1
        end
    end
    return count, killers, credits[#credits]
end

-- [killer key] = KOS kills
function HL:KillScores()
    local scores, lastFor = {}, {}
    local credits = {}
    for _, c in pairs(self:Entries("kills")) do credits[#credits + 1] = c end
    table.sort(credits, function(a, b) return a.t < b.t end)
    for _, c in ipairs(credits) do
        local k = HL.Key(c.b or "") .. "|" .. HL.Key(c.n)
        if not lastFor[k] or c.t - lastFor[k] > EVENT_WINDOW then
            local killer = HL.Key(c.b or "")
            scores[killer] = (scores[killer] or 0) + 1
        end
        lastFor[k] = c.t
    end
    return scores
end

---------------------------------------------------------------------------
-- Recording a kill
---------------------------------------------------------------------------
function HL:AddKillCredit(victimName)
    local victim = HL.NormalizeName(victimName)
    local e = victim and self:Get(victim, "kos")
    if not e then return end
    if self:Throttled("killcredit:" .. HL.Key(e.n), 10) then return end
    local rec = { n = e.n, b = self.me or "", t = GetServerTime(), r = HL.Clean(GetZoneText() or "", 60) }
    if not self:Merge(rec, "kills") then return end
    self:Fire()
    if self.BroadcastEntries then self:BroadcastEntries({ rec }, "kills") end
    local count = self:KillStats(e.n)
    self:Print(("You killed %s – KOS kill #%d"):format(HL.ColorName(HL.ShortName(e.n), "kos"), count))
end

local function debugLog(text)
    if HL.debug then HL:Print("|cff888888[kills] " .. text .. "|r") end
end

-- Source 1: the honor message names the victim
HL:On("CHAT_MSG_COMBAT_HONOR_GAIN", function(msg)
    if not HL.db then return end
    if HL.IsSecret(msg) then debugLog("honor message is hidden from addons by the game") return end
    debugLog("honor message: " .. tostring(msg))
    local victim = HL.VictimFromHonorMessage(msg)
    if not victim then debugLog("could not read a name from it") return end
    if not HL:Get(victim, "kos") then debugLog(victim .. " is not on the KOS List") return end
    HL:AddKillCredit(victim)
end)

-- Sources 2 + 3: we watch KOS players die (target, focus, mouseover, nameplates).
--   * if our honorable-kill counter goes up within a few seconds -> our kill
--   * if they die as our target while we're fighting -> our kill
local recentDeaths = {}          -- [key] = { t, n, target }
local lastTargetKey, lastTargetTime = nil, 0
local lastHKTime, lastCombatTime = 0, 0
local MATCH_WINDOW = 5

local function inCombatRecently()
    local ok, c = pcall(UnitAffectingCombat, "player")
    if ok and not HL.IsSecret(c) and c then return true end
    return GetTime() - lastCombatTime < MATCH_WINDOW
end

local function honorKills()
    local ok, hk = pcall(GetPVPSessionStats)
    if ok and type(hk) == "number" and not HL.IsSecret(hk) then return hk end
end

local function creditDeath(key, why)
    local d = recentDeaths[key]
    if not d or d.credited then return end
    d.credited = true
    debugLog(HL.ShortName(d.n) .. " counted (" .. why .. ")")
    HL:AddKillCredit(d.n)
end

local function checkDeath(unit)
    if not HL.db or not unit or HL.IsSecret(unit) then return end
    local ok, dead = pcall(UnitIsDeadOrGhost, unit) -- cheap check first, UNIT_HEALTH fires a lot
    if not ok or HL.IsSecret(dead) or not dead then return end
    local full = HL.UnitFullName(unit)
    local e = full and HL:Get(full, "kos")
    if not e or HL.FactionRelation(unit) == "friendly" then return end
    local key = HL.Key(e.n)
    local now = GetTime()
    if recentDeaths[key] and now - recentDeaths[key].t < 30 then return end
    local okT, isTarget = pcall(UnitIsUnit, unit, "target")
    isTarget = (okT and not HL.IsSecret(isTarget) and isTarget) or (lastTargetKey == key and now - lastTargetTime < 10)
    recentDeaths[key] = { t = now, n = e.n, target = isTarget and true or false }
    debugLog(("%s (KOS) died – your target: %s, in combat: %s, honorable kill %.1fs ago"):format(
        HL.ShortName(e.n), tostring(isTarget and true or false), tostring(inCombatRecently()), now - lastHKTime))

    if now - lastHKTime < MATCH_WINDOW then
        creditDeath(key, "honorable kill")
    elseif isTarget and inCombatRecently() then
        creditDeath(key, "died as your target in combat")
    end
end

HL:On("PLAYER_PVP_KILLS_CHANGED", function()
    lastHKTime = GetTime()
    debugLog("honorable kill counter changed (now " .. tostring(honorKills()) .. ")")
    for key, d in pairs(recentDeaths) do
        if lastHKTime - d.t < MATCH_WINDOW then creditDeath(key, "honorable kill") end
    end
end)

HL:On("PLAYER_TARGET_CHANGED", function()
    local full = HL.UnitFullName("target")
    if full and HL:Get(full, "kos") then
        lastTargetKey, lastTargetTime = HL.Key(HL:Get(full, "kos").n), GetTime()
    end
end)

HL:On("PLAYER_REGEN_DISABLED", function() lastCombatTime = GetTime() end)
HL:On("PLAYER_REGEN_ENABLED", function() lastCombatTime = GetTime() end)

local WATCHED = { target = true, focus = true, mouseover = true }
local function watched(unit)
    return unit and not HL.IsSecret(unit) and (WATCHED[unit] or unit:find("^nameplate"))
end
HL:On("UNIT_HEALTH", function(unit) if watched(unit) then checkDeath(unit) end end)
HL:On("UNIT_FLAGS", function(unit) if watched(unit) then checkDeath(unit) end end)
HL:On("NAME_PLATE_UNIT_REMOVED", function(unit) checkDeath(unit) end)
