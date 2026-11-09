-- Huens Liste: KOS kill counter
--
-- Addons can't read the combat log anymore, so kills come from the honor message
-- ("Gank Lord dies, honorable kill ..."). You get that message when you or someone
-- in your group kills an enemy player. If the victim is on the KOS List, we record
-- a credit for ourselves and share it. Several friends in one group each record a
-- credit for the same kill; those count as one kill with several killers.
local _, HL = ...

local EVENT_WINDOW = 60 -- credits for the same victim within 60 s are one kill

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

HL:On("CHAT_MSG_COMBAT_HONOR_GAIN", function(msg)
    if not HL.db or HL.IsSecret(msg) then return end
    if HL.debug then HL:Print("|cff888888honor msg: " .. tostring(msg) .. "|r") end
    local victim = HL.VictimFromHonorMessage(msg)
    if victim then HL:AddKillCredit(victim) end
end)
