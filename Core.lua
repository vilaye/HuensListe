-- Huens Liste: core data model, helpers, events
local ADDON, HL = ...
_G.HuensListe = HL

HL.PREFIX = "HuensListe"
HL.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"
HL.NUM_BUCKETS = 16
HL.FS = "~"   -- field separator
HL.RS = ";"   -- record separator

local DEFAULTS = {
    entries = {},   -- [lowercase "name-realm"] = { n = "Name-Realm", r = reason, b = addedBy, t = serverTime, d = deleted }
    seen = {},      -- [key] = { t = time, z = zone, s = subzone, by = who }
    sightLog = {},  -- recent sightings for the Log tab: { n, t, z, s, by } (local, not synced)
    avoid = {},     -- same format as entries: the Swine List (own faction)
    kills = {},     -- KOS kill credits: { n = victim, b = killer, t = time, r = zone }
    deaths = {},    -- deaths to KOS players: { n = KOS killer, b = victim (one of us), t = time, r = zone }
    info = {},      -- [key] = { c = class file ("SHAMAN"), l = level, t = time } for listed players
    selfIds = {},   -- [character GUID] = our full name as the game sends it ("First-Last")
    peers = {},     -- [key] = { n = name, v = version, t = last heard, via = channel }  (other addon users)
    settings = {
        alerts = true,          -- raid-warning + chat when YOU see a KOS
        sound = true,
        shareSightings = true,  -- tell friends when you spot one
        sightingAlerts = true,  -- show friends' sightings
        syncGuild = true,
        syncGroup = true,
        guildOnly = true,       -- only accept sync from guild members (and your private channel)
        channel = "",           -- optional private sync channel
        channelPassword = "",
        alertCooldown = 60,     -- seconds between alerts for the same player
        plateOffsetY = 0,
        plateScale = 1,
    },
}

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function HL:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do fn(...) end
end)

HL.listeners = {}
function HL:OnChange(fn) table.insert(self.listeners, fn) end
function HL:Fire() for _, fn in ipairs(self.listeners) do fn() end end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function HL:Print(...)
    print("|cffcc2222Huens Liste:|r", ...)
end

-- Midnight-era "secret values": never compare or index with them.
local issecret = _G.issecretvalue
function HL.IsSecret(v)
    return issecret ~= nil and v ~= nil and issecret(v) == true
end

function HL.PlaySoundSafe(id)
    if id then pcall(PlaySound, id, "Master") end
end

function HL.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

function HL.MyRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = (GetRealmName() or ""):gsub("%s", "") end
    return r
end

function HL.Clean(s, maxLen)
    s = tostring(s or "")
    s = s:gsub("[~;|\r\n\t]", " ")
    s = strtrim(s)
    if maxLen and #s > maxLen then
        s = s:sub(1, maxLen):gsub("[\192-\255][\128-\191]*$", "")
    end
    return s
end

-- WoW Forever is realmless and every character has a two-word name ("First Last"),
-- unique per region. We detect that from our own name and then identify players
-- by their full two-word name only, never by realm.
function HL.IsRealmless()
    if HL.realmless == nil then
        local ok, n = pcall(UnitName, "player")
        if ok and n and not HL.IsSecret(n) and n ~= "" and n ~= UNKNOWNOBJECT then
            HL.realmless = n:find(" ", 1, true) ~= nil
        end
    end
    return HL.realmless == true
end

local function capitalizeWords(s)
    return (s:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b:lower() end))
end

-- Forever: "illmindof nepho" / "Illmindof Nepho-Whatever" -> "Illmindof Nepho"
-- Classic-style: "gankboy" / "Gankboy-Some Realm" -> "Gankboy-SomeRealm"
function HL.NormalizeName(input)
    if type(input) ~= "string" or HL.IsSecret(input) then return end
    input = strtrim(input):gsub("%s+", " ")
    if input == "" then return end
    if HL.IsRealmless() then
        -- names come with a space: accept "First-Last" too
        local name, realm = input:match("^(.-)%-([^%-]+)$")
        name = strtrim(name or input)
        if realm and not name:find(" ", 1, true) then name = name .. " " .. strtrim(realm) end
        if not name:find(" ", 1, true) then return end -- Forever names are always two words
        return capitalizeWords(name)
    end
    -- The game hands addons Forever names as "First-Last" (the last name sits where
    -- the realm used to be), so a typed "First Last" means exactly that.
    local typedWithSpace = false
    -- "First Last-Something" (how addon messages name senders) -> "First-Last"
    local f1, l1 = input:match("^(%S+) (%S+)%-[^%-]+$")
    if f1 then input, typedWithSpace = f1 .. "-" .. l1, true end
    if not input:find("-", 1, true) then
        local first, last = input:match("^(%S+) (%S+)$")
        if first then input, typedWithSpace = first .. "-" .. last, true end
    end
    local name, realm = input:match("^(.-)%-([^%-]+)$")
    name = strtrim(name or input)
    name = name:gsub("%s", "")
    realm = realm and realm:gsub("%s", "") or HL.MyRealm()
    if name == "" or realm == "" then return end
    realm = typedWithSpace and capitalizeWords(realm) or (realm:sub(1, 1):upper() .. realm:sub(2))
    return capitalizeWords(name) .. "-" .. realm
end

function HL.Key(full) return full and full:lower() end

-- How we show a name: Forever names are "First-Last" internally -> "First Last"
function HL.ShortName(full)
    if type(full) ~= "string" or full == "" then return "?" end
    if HL.IsRealmless() then return full end
    return (full:gsub("%-", " ", 1))
end

-- Full "Name-Realm" of a player unit, or nil (NPCs, secret values, ...)
function HL.UnitFullName(unit)
    if not unit or HL.IsSecret(unit) then return end
    local okE, exists = pcall(UnitExists, unit)
    if not okE or HL.IsSecret(exists) or not exists then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or HL.IsSecret(isPlayer) or not isPlayer then return end
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or not name or HL.IsSecret(name) or HL.IsSecret(realm) then return end
    if HL.IsRealmless() then return HL.NormalizeName(name) end
    if not realm or realm == "" then realm = HL.MyRealm() end
    return name .. "-" .. realm
end

-- Identity of an addon-message sender, in the same form as HL.me
function HL.SenderId(sender)
    return HL.NormalizeName(sender) or sender
end

function HL.Ago(t)
    local d = GetServerTime() - (t or 0)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

local lastFired = {}
function HL:Throttled(key, secs)
    local now = GetTime()
    if lastFired[key] and now - lastFired[key] < secs then return true end
    lastFired[key] = now
    return false
end

---------------------------------------------------------------------------
-- Lists
--   kos   - enemy faction: skull on the nameplate + raid warning
--   avoid - your own faction (toxic players): chat message + sound when they show up
-- A player is on at most one list. Both lists sync separately: KOS uses the
-- original message kinds (A/U/H/R), the Avoid list lowercase ones (a/u/h/r),
-- so older addon versions simply ignore it.
---------------------------------------------------------------------------
HL.LISTS = {
    kos   = { db = "entries", label = "KOS List",   color = "ff4040", export = "HL1:" },
    avoid = { db = "avoid",   label = "Swine List", color = "ffaa00", export = "HL1A:" },
}
HL.LIST_ORDER = { "kos", "avoid" }

-- KOS kill credits: one record per killer per kill (victim, killer, time, zone).
-- Synced like the lists, but append-only, keyed by victim|killer|time.
HL.LISTS.kills = {
    db = "kills", label = "Kills", color = "ff8080",
    key = function(rec) return HL.Key(rec.n) .. "|" .. HL.Key(rec.b or "") .. "|" .. tostring(rec.t) end,
}
-- Deaths to KOS players: same shape, n = the KOS player who killed, b = who died.
HL.LISTS.deaths = { db = "deaths", label = "Deaths", color = "c070ff", key = HL.LISTS.kills.key }
HL.SYNC_ORDER = { "kos", "avoid", "kills", "deaths" }

function HL:Entries(list) return self.db[HL.LISTS[list or "kos"].db] end

function HL.ListLabel(list)
    local L = HL.LISTS[list or "kos"]
    return "|cff" .. L.color .. L.label .. "|r"
end

function HL.ColorName(name, list)
    return "|cff" .. HL.LISTS[list or "kos"].color .. name .. "|r"
end

function HL.OtherList(list) return list == "avoid" and "kos" or "avoid" end

-- "enemy", "friendly", or nil if we can't tell
function HL.FactionRelation(unit)
    if not unit or HL.IsSecret(unit) then return end
    local ok1, theirs = pcall(UnitFactionGroup, unit)
    local ok2, mine = pcall(UnitFactionGroup, "player")
    if not ok1 or not ok2 or HL.IsSecret(theirs) or HL.IsSecret(mine) or not theirs or not mine then return end
    if theirs == "Neutral" or mine == "Neutral" then return end
    return (theirs == mine) and "friendly" or "enemy"
end

---------------------------------------------------------------------------
-- Class and level of listed players (seen in game, shared with sightings)
---------------------------------------------------------------------------
function HL:NoteInfo(name, classFile, level)
    local full = HL.NormalizeName(name)
    if not full or not self.db then return end
    local key = HL.Key(full)
    local cur = self.db.info[key] or {}
    local changed = false
    if type(classFile) == "string" and classFile:match("^%a+$") and #classFile <= 20 then
        classFile = classFile:upper()
        if cur.c ~= classFile then cur.c = classFile; changed = true end
    end
    level = tonumber(level)
    if level and level > 0 and level < 200 and cur.l ~= level then cur.l = level; changed = true end
    if not changed then return end
    cur.t = GetServerTime()
    self.db.info[key] = cur
    if self.RefreshList then self:RefreshList() end
end

function HL:NoteUnitInfo(unit, name)
    local okC, _, classFile = pcall(UnitClass, unit)
    local okL, level = pcall(UnitLevel, unit)
    if not okC or HL.IsSecret(classFile) then classFile = nil end
    if not okL or HL.IsSecret(level) then level = nil end
    if classFile or level then self:NoteInfo(name, classFile, level) end
end

function HL:Info(name)
    local full = HL.NormalizeName(name or "")
    return full and self.db and self.db.info[HL.Key(full)] or nil
end

local function classHex(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c or not c.r then return end
    return ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function className(classFile)
    local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
    return n or (classFile:sub(1, 1) .. classFile:sub(2):lower())
end

-- "36 Shaman" (class-colored unless plain), or nil if nothing is known
function HL:InfoText(name, plain)
    local i = self:Info(name)
    if not i or not (i.c or i.l) then return end
    local text = (i.l and tostring(i.l) or "") .. ((i.l and i.c) and " " or "") .. (i.c and className(i.c) or "")
    local hex = not plain and classHex(i.c)
    return hex and ("|c" .. hex .. text .. "|r") or text
end

-- display name in the class color if we know the class, else in the list color
function HL:ColoredName(name, list)
    local i = self:Info(name)
    local hex = i and classHex(i.c)
    if hex then return "|c" .. hex .. HL.ShortName(name) .. "|r" end
    return HL.ColorName(HL.ShortName(name), list)
end

---------------------------------------------------------------------------
-- Data model (last-write-wins per player, tombstones for removals)
---------------------------------------------------------------------------
function HL:Get(full, list)
    if not full or not self.db then return end
    local e = self:Entries(list)[HL.Key(HL.NormalizeName(full) or full)]
    if e and not e.d then return e end
end

-- Which list a player is on (or nil)
function HL:Find(full)
    for _, list in ipairs(HL.LIST_ORDER) do
        local e = self:Get(full, list)
        if e then return list, e end
    end
end

function HL:Count(list)
    local n = 0
    for _, e in pairs(self:Entries(list)) do if not e.d then n = n + 1 end end
    return n
end

local function isNewer(a, b)
    if not b then return true end
    if a.t ~= b.t then return a.t > b.t end
    local ad, bd = a.d and 1 or 0, b.d and 1 or 0
    if ad ~= bd then return ad > bd end
    return (a.b or "") > (b.b or "")
end

function HL:Merge(rec, list)
    local entries = self:Entries(list)
    local L = HL.LISTS[list or "kos"]
    local key = L.key and L.key(rec) or HL.Key(rec.n)
    if isNewer(rec, entries[key]) then
        entries[key] = { n = rec.n, r = rec.r or "", b = rec.b or "", t = rec.t, d = rec.d or nil }
        self.digestCache = nil
        return true
    end
    return false
end

function HL:SetEntry(full, reason, deleted, list)
    local entries = self:Entries(list)
    local key = HL.Key(full)
    local cur = entries[key]
    local ts = GetServerTime()
    if cur and cur.t >= ts then ts = cur.t + 1 end
    local e = { n = full, r = HL.Clean(reason, 80), b = HL.me or "", t = ts, d = deleted or nil }
    entries[key] = e
    self.digestCache = nil
    self:Fire()
    if self.BroadcastEntries then self:BroadcastEntries({ e }, list or "kos") end
    return e
end

-- relation: what we know about the player's faction ("enemy"/"friendly"/nil)
function HL:Add(full, reason, list, relation)
    list = list or "kos"
    full = HL.NormalizeName(full)
    if not full then self:Print("Invalid name.") return end
    if full == HL.me then self:Print("You can't put yourself on a list.") return end
    if list == "kos" and relation == "friendly" then
        self:Print(HL.ShortName(full) .. " is on your faction – KOS is for the enemy faction. Use the "
            .. HL.ListLabel("avoid") .. " instead (|cffffff00/hl swine|r).")
        return
    elseif list == "avoid" and relation == "enemy" then
        self:Print(HL.ShortName(full) .. " is on the enemy faction – put them on the " .. HL.ListLabel("kos") .. " instead.")
        return
    end
    reason = HL.Clean(reason, 80)
    local other = HL.OtherList(list)
    local moved = self:Get(full, other)
    if moved then self:SetEntry(moved.n, moved.r, true, other) end
    local existed = self:Get(full, list)
    self:SetEntry(full, reason, nil, list)
    local verb = moved and "Moved" or (existed and "Updated" or "Added")
    self:Print(("%s %s %s the %s%s"):format(verb, HL.ColorName(HL.ShortName(full), list), existed and not moved and "on" or "to",
        HL.ListLabel(list), reason ~= "" and (" (" .. reason .. ")") or ""))
end

-- list = nil removes the player from whichever list they're on
function HL:Remove(full, list)
    full = HL.NormalizeName(full)
    local e
    if list then e = full and self:Get(full, list) else list, e = self:Find(full or "") end
    if not e then self:Print("Not on a list: " .. tostring(full)) return end
    self:SetEntry(e.n, e.r, true, list)
    self:Print("Removed " .. HL.ColorName(HL.ShortName(e.n), list) .. " from the " .. HL.ListLabel(list))
end

-- Change the note (reason) of a player who's already on a list
function HL:EditNote(full, newReason)
    local list, e = self:Find(HL.NormalizeName(full) or "")
    if not e then self:Print("Not on a list: " .. tostring(full)) return end
    newReason = HL.Clean(newReason, 80)
    if newReason == e.r then return end
    self:SetEntry(e.n, newReason, nil, list)
    self:Print(("Note for %s: %s"):format(HL.ColorName(HL.ShortName(e.n), list),
        newReason ~= "" and newReason or "|cff888888(removed)|r"))
end

-- Move a player to the other list, keeping the reason
function HL:Move(full)
    local list, e = self:Find(HL.NormalizeName(full) or "")
    if not e then return end
    self:Add(e.n, e.r, HL.OtherList(list))
end

function HL.Serialize(e)
    return table.concat({ e.n, e.r or "", e.b or "", tostring(e.t), e.d and "1" or "0" }, HL.FS)
end

function HL.Deserialize(s)
    if not s or s == "" then return end
    local n, r, b, t, d = strsplit(HL.FS, s)
    t = tonumber(t)
    n = HL.NormalizeName(n)
    if not n or not t then return end
    return { n = n, r = HL.Clean(r, 80), b = HL.Clean(b, 60), t = t, d = (d == "1") or nil }
end

-- Per-bucket digests let two clients find out cheaply which parts differ.
function HL:BucketOf(key) return HL.Hash(key) % HL.NUM_BUCKETS end

function HL:Digests(list)
    list = list or "kos"
    self.digestCache = self.digestCache or {}
    if self.digestCache[list] then return self.digestCache[list] end
    local buckets = {}
    for i = 0, HL.NUM_BUCKETS - 1 do buckets[i] = {} end
    for key, e in pairs(self:Entries(list)) do
        local b = buckets[self:BucketOf(key)]
        b[#b + 1] = key .. ":" .. e.t .. ":" .. (e.d and 1 or 0)
    end
    local out = {}
    for i = 0, HL.NUM_BUCKETS - 1 do
        table.sort(buckets[i])
        out[#out + 1] = string.format("%08x", HL.Hash(table.concat(buckets[i], ",")))
    end
    self.digestCache[list] = out
    return out
end

function HL:EntriesInBuckets(set, list)
    local out = {}
    for key, e in pairs(self:Entries(list)) do
        if set[self:BucketOf(key)] then out[#out + 1] = e end
    end
    return out
end

---------------------------------------------------------------------------
-- Export / import (for sharing via Discord etc.)
---------------------------------------------------------------------------
function HL:ExportString(list)
    list = list or "kos"
    local recs = {}
    for _, e in pairs(self:Entries(list)) do
        if not e.d then recs[#recs + 1] = HL.Serialize(e) end
    end
    table.sort(recs)
    return HL.LISTS[list].export .. table.concat(recs, HL.RS)
end

function HL:Import(text)
    text = strtrim(text or "")
    local list, body = "avoid", text:match("^HL1A:(.*)$")
    if not body then list, body = "kos", text:match("^HL1:(.*)$") end
    if not body then self:Print("That doesn't look like a Huens Liste export string.") return end
    local changed = 0
    for rec in body:gmatch("[^;]+") do
        local r = HL.Deserialize(strtrim(rec))
        if r and self:Merge(r, list) then changed = changed + 1 end
    end
    self:Fire()
    if self.ScheduleHello then self:ScheduleHello(2) end
    self:Print("Import into the " .. HL.ListLabel(list) .. " done: " .. changed .. " new/updated entries.")
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

HL:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    HuensListeDB = HuensListeDB or {}
    copyDefaults(DEFAULTS, HuensListeDB)
    HL.db = HuensListeDB
    HL.settings = HL.db.settings
end)

-- Our own full name. UnitName("player") only gives the first name in Forever, so we
-- remember the full name once we've seen it come back on one of our own messages.
function HL:GuessOwnName()
    local okG, guid = pcall(UnitGUID, "player")
    if okG and guid and not HL.IsSecret(guid) and self.db.selfIds[guid] then
        return self.db.selfIds[guid]
    end
    local ok, n, r = pcall(UnitFullName, "player")
    if ok and n and not HL.IsSecret(n) and not HL.IsSecret(r) and r and r ~= "" then
        local full = HL.NormalizeName(n .. "-" .. r)
        if full then return full end
    end
    if HL.IsRealmless() then return HL.NormalizeName(UnitName("player")) end
    return UnitName("player") .. "-" .. HL.MyRealm()
end

function HL:LearnOwnName(full)
    if not full or full == self.me then return end
    local okG, guid = pcall(UnitGUID, "player")
    local hasGuid = okG and guid and not HL.IsSecret(guid)
    if hasGuid and self.db.selfIds[guid] then return end -- learned once per character, never overwritten
    local old = self.me
    self.me = full
    if hasGuid then self.db.selfIds[guid] = full end
    -- we were listed as "another user" under this name: drop that row
    self.db.peers[HL.Key(full)] = nil
    if old then self.db.peers[HL.Key(old)] = nil end
    if self.RefreshUsers then self:RefreshUsers() end
end

-- Re-key stored entries with the current name rules. Entries written by
-- v1.0/1.1 under Forever lost the space in the name ("Illmindofnepho") and can't
-- match anyone, so they are dropped.
local function migrate()
    local dropped = 0
    for _, list in ipairs(HL.LIST_ORDER) do
        local key = HL.LISTS[list].db
        local fresh = {}
        for _, e in pairs(HL.db[key]) do
            local n = type(e) == "table" and HL.NormalizeName(e.n)
            if n and type(e.t) == "number" then
                e.n = n
                local k = HL.Key(n)
                if not fresh[k] or e.t > fresh[k].t then fresh[k] = e end
            else
                dropped = dropped + 1
            end
        end
        HL.db[key] = fresh
    end
    for k in pairs(HL.db.seen) do
        if not HL.db.entries[k] then HL.db.seen[k] = nil end
    end
    for k in pairs(HL.db.info) do
        if not HL.db.entries[k] and not HL.db.avoid[k] then HL.db.info[k] = nil end
    end
    HL.digestCache = nil
    if dropped > 0 then
        HL:Print("Cleaned up " .. dropped .. " broken entries from an older version (names without surname). Re-add them if needed.")
    end
end

HL:On("PLAYER_LOGIN", function()
    HL.realmless = nil
    HL.me = HL:GuessOwnName()
    migrate()
    HL:Print(("loaded – %d on the %s, %d on the %s. Type |cffffff00/hl|r to open."):format(
        HL:Count("kos"), HL.ListLabel("kos"), HL:Count("avoid"), HL.ListLabel("avoid")))
end)
