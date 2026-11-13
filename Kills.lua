-- Huens Liste: KOS kill counter
--
-- Addons can't read the combat log anymore, and Forever's honor message has no name
-- ("You have been awarded 4 Honor."). So a kill is: a KOS player dies in front of us
-- (target or nameplate) and we get honor within a few seconds, or they die as our
-- target while we're fighting. We record a credit for ourselves and share it. Several
-- friends in one group each record a credit; those count as one kill with several killers.
local _, HL = ...

local EVENT_WINDOW = 20 -- credits for the same victim within 20 s are one kill (group members credit at once)
HL.KILL_EVENT_WINDOW = EVENT_WINDOW

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

-- All kills, oldest first, group kills merged into one event:
-- { kind = "kill", n = victim, t = time, z = zone, killers = { "First Last", ... } }
function HL:KillEvents()
    local credits = {}
    for _, c in pairs(self:Entries("kills")) do credits[#credits + 1] = c end
    table.sort(credits, function(a, b) return a.t < b.t end)
    local events, open = {}, {}
    for _, c in ipairs(credits) do
        local key = HL.Key(c.n)
        local ev = open[key]
        if not ev or c.t - ev.t > EVENT_WINDOW then
            ev = { kind = "kill", n = c.n, t = c.t, z = c.r or "", killers = {}, has = {} }
            open[key] = ev
            events[#events + 1] = ev
        end
        local who = HL.ShortName(c.b)
        if not ev.has[who] then
            ev.has[who] = true
            ev.killers[#ev.killers + 1] = who
        end
    end
    return events
end

-- Deaths to a KOS player: count, victims { [display name] = deaths }, last record
function HL:DeathStats(full)
    local key = HL.Key(HL.NormalizeName(full) or full)
    local count, victims, last = 0, {}, nil
    for _, c in pairs(self:Entries("deaths")) do
        if HL.Key(c.n) == key then
            count = count + 1
            local who = HL.ShortName(c.b)
            victims[who] = (victims[who] or 0) + 1
            if not last or c.t > last.t then last = c end
        end
    end
    return count, victims, last
end

-- { kind = "death", n = KOS killer, t = time, z = zone, victim = "First Last" }
function HL:DeathEvents()
    local events = {}
    for _, c in pairs(self:Entries("deaths")) do
        events[#events + 1] = { kind = "death", n = c.n, t = c.t, z = c.r or "", victim = HL.ShortName(c.b) }
    end
    return events
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

function HL:AddDeathCredit(killerName)
    local e = self:Get(killerName, "kos")
    if not e then return end
    if self:Throttled("deathcredit:" .. HL.Key(e.n), 10) then return end
    local rec = { n = e.n, b = self.me or "", t = GetServerTime(), r = HL.Clean(GetZoneText() or "", 60) }
    if not self:Merge(rec, "deaths") then return end
    self:Fire()
    if self.BroadcastEntries then self:BroadcastEntries({ rec }, "deaths") end
    local count = self:DeathStats(e.n)
    self:Print(("|cffc070ffYou were killed by|r %s – they have killed you or your friends %d time%s"):format(
        HL.ColorName(HL.ShortName(e.n), "kos"), count, count == 1 and "" or "s"))
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
    if victim then
        if not HL:Get(victim, "kos") then debugLog(victim .. " is not on the KOS List") return end
        HL:AddKillCredit(victim)
        return
    end
    -- Forever just says "You have been awarded 4 Honor." (no name): use it as the
    -- "we got a kill" signal and match it with a KOS player we saw die
    HL:OnHonorAward("honor message")
end)

-- Sources 2 + 3: we watch KOS players die (target, focus, mouseover, nameplates).
--   * if our honorable-kill counter goes up within a few seconds -> our kill
--   * if they die as our target while we're fighting -> our kill
local recentDeaths = {}          -- [key] = { t, n, target }
local lastTargetKey, lastTargetTime = nil, 0
local lastHKTime, lastCombatTime = 0, 0
local MATCH_WINDOW = 8

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
    debugLog(("%s (KOS) died – your target: %s, in combat: %s, last honor %.1fs ago"):format(
        HL.ShortName(e.n), tostring(isTarget and true or false), tostring(inCombatRecently()), now - lastHKTime))

    if now - lastHKTime < MATCH_WINDOW then
        creditDeath(key, "honor")
    elseif isTarget and inCombatRecently() then
        creditDeath(key, "died as your target in combat")
    end
end

-- We got honor / an honorable kill: credit KOS players who died just before
function HL:OnHonorAward(source)
    lastHKTime = GetTime()
    debugLog(source .. " (honorable kills this session: " .. tostring(honorKills()) .. ")")
    local any = false
    for key, d in pairs(recentDeaths) do
        if lastHKTime - d.t < MATCH_WINDOW then creditDeath(key, "honor"); any = true end
    end
    if not any then debugLog("no KOS player died in the last " .. MATCH_WINDOW .. "s (waiting a moment in case the death comes next)") end
end

HL:On("PLAYER_PVP_KILLS_CHANGED", function() HL:OnHonorAward("honorable kill counter changed") end)

HL:On("PLAYER_TARGET_CHANGED", function()
    local full = HL.UnitFullName("target")
    if full and HL:Get(full, "kos") then
        lastTargetKey, lastTargetTime = HL.Key(HL:Get(full, "kos").n), GetTime()
    end
end)

local fighting, lastFightEnd = false, 0
HL:On("PLAYER_REGEN_DISABLED", function() lastCombatTime = GetTime(); fighting = true end)
HL:On("PLAYER_REGEN_ENABLED", function() lastCombatTime = GetTime(); fighting = false; lastFightEnd = GetTime() end)

-- You died. Addons can't see who dealt the blow, so we look at the KOS players on
-- screen (nameplates and your target):
--   1. KOS players who were targeting you get the credit
--   2. if their target can't be read: your own target, if it's a KOS player
--   3. otherwise, if exactly one KOS player is around, that one
-- Dying out of combat (falling, drowning) never counts.
HL:On("PLAYER_DEAD", function()
    if not HL.db then return end
    if not fighting and GetTime() - lastFightEnd > MATCH_WINDOW then
        debugLog("you died out of combat – not counted")
        return
    end
    local cands, order = {}, {}
    local function consider(unit, isMyTarget)
        local full = HL.UnitFullName(unit)
        local e = full and HL:Get(full, "kos")
        if not e or HL.FactionRelation(unit) == "friendly" then return end
        local okD, dead = pcall(UnitIsDeadOrGhost, unit)
        if okD and not HL.IsSecret(dead) and dead then return end
        local key = HL.Key(e.n)
        local c = cands[key]
        if not c then
            c = { n = e.n }
            cands[key] = c
            order[#order + 1] = c
        end
        local okT, onMe = pcall(UnitIsUnit, unit .. "target", "player")
        if okT and not HL.IsSecret(onMe) then
            c.readable = true
            if onMe then c.onMe = true end
        end
        if isMyTarget then c.myTarget = true end
    end
    for unit in pairs(HL.kosPlates or {}) do consider(unit) end
    consider("target", true)
    if #order == 0 then return end

    local killers, why = {}, "was targeting you"
    for _, c in ipairs(order) do if c.onMe then killers[#killers + 1] = c end end
    if #killers == 0 then
        why = "was your target"
        for _, c in ipairs(order) do
            if c.myTarget and not c.readable then killers[#killers + 1] = c end
        end
    end
    if #killers == 0 and #order == 1 and not order[1].readable then
        why = "the only KOS player around"
        killers[1] = order[1]
    end
    if #killers == 0 then debugLog("you died with KOS players around, but none was on you – not counted") end
    for _, c in ipairs(killers) do
        debugLog("death counted for " .. HL.ShortName(c.n) .. " (" .. why .. ")")
        HL:AddDeathCredit(c.n)
    end
end)

local WATCHED = { target = true, focus = true, mouseover = true }
local function watched(unit)
    return unit and not HL.IsSecret(unit) and (WATCHED[unit] or unit:find("^nameplate"))
end
HL:On("UNIT_HEALTH", function(unit) if watched(unit) then checkDeath(unit) end end)
HL:On("UNIT_FLAGS", function(unit) if watched(unit) then checkDeath(unit) end end)
HL:On("NAME_PLATE_UNIT_REMOVED", function(unit) checkDeath(unit) end)
