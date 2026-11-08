-- Huens Liste: peer-to-peer sync over addon messages
--
-- Message types (fields separated by ";"):
--   A;rec;rec...      live add/remove, broadcast (printed in chat)
--   U;rec;rec...      sync payload, whispered (silent, summarised)
--   H;version;d1,..   hello with 16 bucket digests, broadcast
--   R;0,3,7           "send me your entries in these buckets", whispered
--   S;name;zone;sub   sighting, broadcast
local _, HL = ...
local RS = HL.RS
local MAX_LEN = 250

C_ChatInfo.RegisterAddonMessagePrefix(HL.PREFIX)

---------------------------------------------------------------------------
-- Send queue with simple token bucket (Blizzard throttles addon messages)
---------------------------------------------------------------------------
local high, low = {}, {}
local tokens, MAX_TOKENS = 4, 4
local SUCCESS = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success

local function rawSend(m)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, HL.PREFIX, m.msg, m.chatType, m.target)
    local sent = ok and res ~= false
    if ok and SUCCESS ~= nil and type(res) == "number" then sent = (res == SUCCESS) end
    if HL.debug then
        HL:Print(("|cff888888send %s%s -> %s: %s|r"):format(m.chatType, m.target and (" '" .. tostring(m.target) .. "'") or "",
            sent and "ok" or ("FAILED (" .. tostring(res) .. ")"), m.msg:sub(1, 40)))
    end
    return sent
end

local function enqueue(q, msg, chatType, target)
    q[#q + 1] = { msg = msg, chatType = chatType, target = target, tries = 0 }
end

C_Timer.NewTicker(1, function()
    tokens = math.min(MAX_TOKENS, tokens + 1)
    while tokens >= 1 do
        local q = (#high > 0 and high) or (#low > 0 and low)
        if not q then break end
        local m = table.remove(q, 1)
        tokens = tokens - 1
        if not rawSend(m) then
            -- throttled or restricted context (instances etc.): retry later
            m.tries = m.tries + 1
            if m.tries < 5 then table.insert(q, m) end
            break
        end
    end
end)

local function distributions()
    local s, list = HL.settings, {}
    if s.syncGuild and IsInGuild() then list[#list + 1] = { "GUILD" } end
    if s.syncGroup then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then list[#list + 1] = { "INSTANCE_CHAT" }
        elseif IsInRaid() then list[#list + 1] = { "RAID" }
        elseif IsInGroup() then list[#list + 1] = { "PARTY" } end
    end
    if s.channel ~= "" then
        local id = GetChannelName(s.channel)
        if id and id > 0 then list[#list + 1] = { "CHANNEL", id } end
    end
    return list
end

function HL:Broadcast(msg, prio)
    local q = (prio == "low") and low or high
    for _, d in ipairs(distributions()) do enqueue(q, msg, d[1], d[2]) end
end

function HL:Whisper(msg, target, prio)
    enqueue((prio == "low") and low or high, msg, "WHISPER", target)
end

local function pack(kind, entries, send)
    local buf = kind
    for _, e in ipairs(entries) do
        local rec = HL.Serialize(e)
        if #buf + 1 + #rec > MAX_LEN and buf ~= kind then
            send(buf)
            buf = kind
        end
        buf = buf .. RS .. rec
    end
    if buf ~= kind then send(buf) end
end

function HL:BroadcastEntries(entries)
    pack("A", entries, function(m) HL:Broadcast(m, "high") end)
end

local function whisperEntries(entries, target)
    pack("U", entries, function(m) HL:Whisper(m, target, "low") end)
end

function HL:SendHello(target)
    if not self.db then return end
    local msg = "H" .. RS .. HL.VERSION .. RS .. table.concat(self:Digests(), ",")
    if target then self:Whisper(msg, target, "high") else self:Broadcast(msg, "high") end
end

local helloPending = false
function HL:ScheduleHello(delay)
    if helloPending then return end
    helloPending = true
    C_Timer.After(delay or 5, function()
        helloPending = false
        HL:SendHello()
    end)
end

---------------------------------------------------------------------------
-- Private sync channel (optional, for friends outside your guild)
---------------------------------------------------------------------------
function HL:JoinSyncChannel()
    local name = self.settings.channel
    if not name or name == "" then return end
    if GetChannelName(name) == 0 then
        local pw = self.settings.channelPassword
        if pw == "" then pw = nil end
        JoinTemporaryChannel(name, pw)
    end
    C_Timer.After(3, function()
        local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
        if not remove then return end
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf then pcall(remove, cf, name) end
        end
    end)
end

function HL:LeaveSyncChannel(name)
    if name and name ~= "" and GetChannelName(name) > 0 then LeaveChannelByName(name) end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function versionNumber(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
    return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end
HL.VersionNumber = versionNumber

---------------------------------------------------------------------------
-- Addon users ("Users" tab): everyone we hear from, with their version
---------------------------------------------------------------------------
local PEER_MAX_AGE = 30 * 86400 -- forget users not heard from in 30 days

function HL:NotePeer(sender, version, channel)
    local key = HL.Key(sender)
    local p = self.db.peers[key] or {}
    p.n = sender
    if version and version ~= "" then p.v = HL.Clean(version, 20) end
    p.t = GetServerTime()
    -- whispers are replies; keep the route we first met them on (guild/group/channel)
    if channel and (channel ~= "WHISPER" or not p.via) then p.via = channel end
    self.db.peers[key] = p
    if self.RefreshUsers then self:RefreshUsers() end
end

-- Ask everyone online for their version (new clients answer with "V")
function HL:PingUsers()
    self:Broadcast("P" .. RS .. HL.VERSION, "high")
end

local lastPong = {}
local function answerPing(rawSender, sender)
    local now = GetTime()
    if lastPong[sender] and now - lastPong[sender] < 30 then return end
    lastPong[sender] = now
    -- small random delay so a whole guild doesn't answer in the same second
    C_Timer.After(math.random() * 3, function()
        HL:Whisper("V" .. RS .. HL.VERSION, rawSender, "low")
    end)
end

---------------------------------------------------------------------------
-- Update notice: a friend has a newer version -> popup once per session,
-- remembered across logins until you've updated.
---------------------------------------------------------------------------
StaticPopupDialogs["HUENSLISTE_UPDATE"] = {
    text = "|cffcc2222Huens Liste|r %s is available (you have %s).\n\n"
        .. "Run |cffffff00Update-HuensListe.bat|r (or update it in the\nCurseForge app), then type |cffffff00/reload|r.",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local popupShown, popupPending = false, false

local function showUpdatePopup()
    if popupShown or not HL.newerVersion then return end
    if InCombatLockdown() then popupPending = true return end
    popupShown, popupPending = true, false
    StaticPopup_Show("HUENSLISTE_UPDATE", HL.newerVersion, HL.VERSION)
    HL:Print("Version " .. HL.newerVersion .. " is available (you have " .. HL.VERSION
        .. "). Run Update-HuensListe.bat or update via CurseForge, then /reload.")
end

local function noteNewerVersion(v)
    if HL.newerVersion and versionNumber(HL.newerVersion) >= versionNumber(v) then return end
    HL.newerVersion = v
    HL.db.newestSeenVersion = v
    showUpdatePopup()
end

local function checkVersion(v, sender)
    if not v then return end
    if versionNumber(v) > versionNumber(HL.VERSION) then noteNewerVersion(v) end
end

HL:On("PLAYER_LOGIN", function()
    local seen = HL.db.newestSeenVersion
    if seen and versionNumber(seen) > versionNumber(HL.VERSION) then
        HL.newerVersion = seen
        C_Timer.After(12, showUpdatePopup)
    else
        HL.db.newestSeenVersion = nil -- already up to date
    end
end)

HL:On("PLAYER_REGEN_ENABLED", function()
    if popupPending then showUpdatePopup() end
end)

local syncCount, syncTimer = 0, nil
local function noteSynced(n)
    syncCount = syncCount + n
    if syncTimer then return end
    syncTimer = C_Timer.NewTimer(5, function()
        HL:Print("Synced " .. syncCount .. " entries from friends. " .. HL:Count() .. " players on the list.")
        syncCount, syncTimer = 0, nil
    end)
end

function HL:OnRemoteSighting(full, zone, sub, sender)
    full = HL.NormalizeName(full)
    local e = full and self:Get(full)
    if not e then return end
    zone, sub = HL.Clean(zone, 60), HL.Clean(sub, 60)
    self.db.seen[HL.Key(full)] = { t = GetServerTime(), z = zone, s = sub, by = sender }
    self:Fire()
    if not self.settings.sightingAlerts then return end
    if self:Throttled("remote:" .. HL.Key(full), self.settings.alertCooldown) then return end
    self:Print(("|cffff4040%s|r spotted in |cffffff00%s%s|r by %s"):format(
        HL.ShortName(full), zone, (sub ~= "" and sub ~= zone) and (" – " .. sub) or "", Ambiguate(sender, "short")))
    if self.settings.sound then HL.PlaySoundSafe(SOUNDKIT and SOUNDKIT.TELL_MESSAGE) end
end

HL:On("CHAT_MSG_ADDON", function(prefix, msg, channel, rawSender)
    if HL.IsSecret(prefix) or HL.IsSecret(msg) or HL.IsSecret(rawSender) or HL.IsSecret(channel) then return end
    if prefix ~= HL.PREFIX or not HL.me or not HL.db then return end
    if HL.debug then
        HL:Print(("|cff888888recv %s from '%s': %s|r"):format(tostring(channel), rawSender, msg:sub(1, 60)))
    end
    -- rawSender is exactly what the game gave us: use it for whispers.
    -- sender is our normalized identity: use it for comparisons and display.
    local sender = HL.SenderId(rawSender)
    if sender == HL.me then return end

    local s = HL.settings
    if channel == "GUILD" and not s.syncGuild then return end
    if (channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT") and not s.syncGroup then return end
    if channel == "CHANNEL" and s.channel == "" then return end

    local parts = { strsplit(RS, msg) }
    local kind = parts[1]

    -- Anyone who talks to us has the addon. H, P and V carry the version.
    local carriesVersion = (kind == "H" or kind == "P" or kind == "V")
    HL:NotePeer(sender, carriesVersion and parts[2] or nil, channel)

    if kind == "P" then
        checkVersion(parts[2], sender)
        answerPing(rawSender, sender)
    elseif kind == "V" then
        checkVersion(parts[2], sender)
    elseif kind == "A" or kind == "U" then
        local changed = {}
        for i = 2, #parts do
            local rec = HL.Deserialize(parts[i])
            if rec and HL:Merge(rec) then changed[#changed + 1] = rec end
        end
        if #changed == 0 then return end
        HL:Fire()
        if kind == "A" then
            for _, rec in ipairs(changed) do
                local who = Ambiguate(rec.b ~= "" and rec.b or sender, "short")
                if rec.d then
                    HL:Print(who .. " removed |cffff4040" .. HL.ShortName(rec.n) .. "|r")
                else
                    HL:Print(who .. " added |cffff4040" .. HL.ShortName(rec.n) .. "|r"
                        .. (rec.r ~= "" and (" (" .. rec.r .. ")") or ""))
                end
            end
        else
            noteSynced(#changed)
        end
        HL:ScheduleHello(30) -- help news travel to peers who missed it

    elseif kind == "H" then
        checkVersion(parts[2], sender)
        if not parts[3] then return end
        local theirs = { strsplit(",", parts[3]) }
        local mine = HL:Digests()
        local set, list = {}, {}
        for i = 1, HL.NUM_BUCKETS do
            if theirs[i] ~= mine[i] then
                set[i - 1] = true
                list[#list + 1] = i - 1
            end
        end
        if #list == 0 then return end
        whisperEntries(HL:EntriesInBuckets(set), rawSender)
        HL:Whisper("R" .. RS .. table.concat(list, ","), rawSender, "high")

    elseif kind == "R" then
        local set = {}
        for b in (parts[2] or ""):gmatch("%d+") do set[tonumber(b)] = true end
        whisperEntries(HL:EntriesInBuckets(set), rawSender)

    elseif kind == "S" then
        HL:OnRemoteSighting(parts[2], parts[3], parts[4], sender)
    end
end)

HL:On("PLAYER_LOGIN", function()
    local now = GetServerTime()
    for key, p in pairs(HL.db.peers) do
        if type(p) ~= "table" or not p.t or now - p.t > PEER_MAX_AGE or HL.Key(p.n or "") == HL.Key(HL.me) then
            HL.db.peers[key] = nil
        end
    end
    C_Timer.After(8, function() HL:JoinSyncChannel() end)
    C_Timer.After(15, function() HL:SendHello() end)
    C_Timer.After(20, function() HL:PingUsers() end)
    C_Timer.NewTicker(300, function() HL:SendHello() end)
end)

HL:On("GROUP_JOINED", function() HL:ScheduleHello(5) end)
