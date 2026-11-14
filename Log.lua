-- Huens Liste: log of recent KOS kills, deaths and sightings ("Log" tab, /hl log)
--
-- Kills and deaths come from the synced records (everyone sees the same ones).
-- Sightings are kept locally: your own plus the ones friends broadcast while
-- you were online.
local _, HL = ...

local MAX_SIGHTINGS = 300            -- stored sightings
local SIGHTING_MAX_AGE = 14 * 86400  -- forget sightings after 14 days
local MERGE_WINDOW = 600             -- same player + zone within 10 min = one line
local MAX_ROWS = 200                 -- lines shown in the tab
local ROW_H = 20

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
function HL:LogSighting(name, zone, sub, by)
    local log = self.db.sightLog
    local now = GetServerTime()
    local key = HL.Key(name)
    zone, sub = zone or "", sub or ""
    -- standing next to someone reports them every minute: keep one line and refresh it
    for i = #log, math.max(1, #log - 40), -1 do
        local s = log[i]
        if HL.Key(s.n) == key and s.z == zone and now - s.t < MERGE_WINDOW then
            table.remove(log, i)
            break
        end
    end
    log[#log + 1] = { n = name, t = now, z = zone, s = sub, by = by or "" }
    while #log > MAX_SIGHTINGS do table.remove(log, 1) end
    self:RefreshLog()
end

function HL:ClearSightingLog()
    self.db.sightLog = {}
    self:RefreshLog()
end

-- Newest first: { kind = "kill" | "death" | "seen", n, t, z, s, by / killers / victim }
function HL:LogItems(showKills, showSightings, showDeaths)
    local items, kills, sightings, deaths = {}, 0, 0, 0
    if showDeaths then
        for _, ev in ipairs(self:DeathEvents()) do
            items[#items + 1] = ev
            deaths = deaths + 1
        end
    end
    if showKills then
        for _, ev in ipairs(self:KillEvents()) do
            items[#items + 1] = ev
            kills = kills + 1
        end
    end
    if showSightings then
        for _, s in ipairs(self.db.sightLog) do
            items[#items + 1] = { kind = "seen", n = s.n, t = s.t, z = s.z, s = s.s, by = s.by }
            sightings = sightings + 1
        end
    end
    table.sort(items, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.kind < b.kind -- a kill and a sighting in the same second: kill first
    end)
    return items, kills, sightings, deaths
end

-- Hotspots: activity per zone over the last `period` seconds, busiest first
function HL:HotZones(period)
    local s = self.settings
    local items = self:LogItems(s.logKills, s.logSightings, s.logDeaths)
    local since = GetServerTime() - period
    local zones, order = {}, {}
    for _, it in ipairs(items) do
        if it.t >= since then
            local name = (it.z and it.z ~= "") and it.z or "Unknown"
            local z = zones[name]
            if not z then
                z = { name = name, seen = 0, kills = 0, deaths = 0, total = 0, last = 0, players = {} }
                zones[name] = z
                order[#order + 1] = z
            end
            if it.kind == "kill" then z.kills = z.kills + 1
            elseif it.kind == "death" then z.deaths = z.deaths + 1
            else z.seen = z.seen + 1 end
            z.total = z.total + 1
            if it.t > z.last then z.last = it.t end
            local p = HL.ShortName(it.n)
            z.players[p] = (z.players[p] or 0) + 1
        end
    end
    table.sort(order, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.last > b.last
    end)
    return order
end

local function playersByCount(z)
    local list = {}
    for name, n in pairs(z.players) do list[#list + 1] = { name = name, n = n } end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return list
end

local function place(zone, sub)
    if not zone or zone == "" then return "" end
    if sub and sub ~= "" and sub ~= zone then return zone .. " – " .. sub end
    return zone
end

local function whenText(t)
    if date("%d.%m.%Y", t) == date("%d.%m.%Y", GetServerTime()) then return date("%H:%M", t) end
    return date("%d.%m. %H:%M", t)
end

HL:On("PLAYER_LOGIN", function()
    if HL.settings.logKills == nil then HL.settings.logKills = true end
    if HL.settings.logSightings == nil then HL.settings.logSightings = true end
    if HL.settings.logDeaths == nil then HL.settings.logDeaths = true end
    local now, fresh = GetServerTime(), {}
    for _, s in ipairs(HL.db.sightLog) do
        if type(s) == "table" and s.n and s.t and now - s.t <= SIGHTING_MAX_AGE then fresh[#fresh + 1] = s end
    end
    HL.db.sightLog = fresh
end)

---------------------------------------------------------------------------
-- Log tab
---------------------------------------------------------------------------
local page, content
local rows = {}

local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(540, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.time = HL.MakeFS(r, 6, 88, "GameFontDisableSmall")
    r.tag = HL.MakeFS(r, 98, 44, "GameFontNormalSmall")
    r.text = HL.MakeFS(r, 146, 390, "GameFontHighlightSmall")
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local z = self.zone
        if z then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(z.name, 1, 0.82, 0)
            GameTooltip:AddLine(("%d sightings, %d kills, %d deaths"):format(z.seen, z.kills, z.deaths), 1, 1, 1)
            GameTooltip:AddLine("Last activity " .. HL.Ago(z.last), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            for i, p in ipairs(playersByCount(z)) do
                if i > 12 then GameTooltip:AddLine("...", 0.7, 0.7, 0.7) break end
                GameTooltip:AddDoubleLine(p.name, p.n .. "x", 1, 0.4, 0.4, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
            return
        end
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if it.kind == "kill" then
            GameTooltip:AddLine("|cffff4040Kill:|r " .. HL.ShortName(it.n))
            GameTooltip:AddLine("Killed by " .. table.concat(it.killers, ", "), 1, 1, 1, true)
        elseif it.kind == "death" then
            GameTooltip:AddLine("|cffc070ffDeath:|r " .. it.victim)
            GameTooltip:AddLine("Killed by " .. HL.ShortName(it.n), 1, 1, 1)
        else
            GameTooltip:AddLine("|cffffd100Sighting:|r " .. HL.ShortName(it.n))
            GameTooltip:AddLine("Spotted by " .. HL.ShortName(it.by), 1, 1, 1)
        end
        local where = place(it.z, it.s)
        if where ~= "" then GameTooltip:AddLine(where, 1, 0.82, 0, true) end
        GameTooltip:AddLine(date("%d.%m.%Y %H:%M:%S", it.t) .. " (" .. HL.Ago(it.t) .. ")", 0.7, 0.7, 0.7)
        local info = HL:InfoText(it.n)
        if info then GameTooltip:AddLine(HL.ShortName(it.n) .. ": " .. info, 0.7, 0.7, 0.7) end
        local e = HL:Get(it.n, "kos")
        if e and e.r ~= "" then GameTooltip:AddLine("Note: " .. e.r, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function refreshZones()
    local period = page.period
    local zones = HL:HotZones(period)
    local shown = math.min(#zones, MAX_ROWS)
    for i = 1, shown do
        local z = zones[i]
        local r = getRow(i)
        r.item, r.zone = nil, z
        r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
        r.time:SetText(HL.Ago(z.last))
        r.tag:SetText("")
        local parts = {}
        if z.seen > 0 then parts[#parts + 1] = "|cffffd100" .. z.seen .. " seen|r" end
        if z.kills > 0 then parts[#parts + 1] = "|cffff4040" .. z.kills .. (z.kills == 1 and " kill" or " kills") .. "|r" end
        if z.deaths > 0 then parts[#parts + 1] = "|cffc070ff" .. z.deaths .. (z.deaths == 1 and " death" or " deaths") .. "|r" end
        local names = {}
        for j, p in ipairs(playersByCount(z)) do
            if j > 3 then names[#names + 1] = "..." break end
            names[#names + 1] = p.name
        end
        r.text:SetText(("|cffffffff%s|r  %s  |cff888888%s|r"):format(z.name, table.concat(parts, ", "), table.concat(names, ", ")))
        r:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, shown * ROW_H))
    page.summary:SetText(("%d zone%s with activity in the last %s"):format(#zones, #zones == 1 and "" or "s",
        period > 86400 and "7 days" or "24 hours"))
    page.empty:SetShown(shown == 0)
end

function HL:RefreshLog()
    if not page or not page:IsVisible() then return end
    local zonesMode = page.mode == "zones"
    page.h1:SetText(zonesMode and "Last" or "When")
    page.h3:SetText(zonesMode and "Zone" or "What")
    page.viewBtn:SetText(zonesMode and "Show timeline" or "Show zones")
    page.periodBtn:SetShown(zonesMode)
    page.periodBtn:SetText(page.period > 86400 and "Last 7 days" or "Last 24 hours")
    if zonesMode then refreshZones() return end
    local items, kills, sightings, deaths = self:LogItems(self.settings.logKills, self.settings.logSightings,
        self.settings.logDeaths)
    local shown = math.min(#items, MAX_ROWS)
    for i = 1, shown do
        local it = items[i]
        local r = getRow(i)
        r.item, r.zone = it, nil
        r.time:SetText(whenText(it.t))
        local where = place(it.z, it.s)
        if it.kind == "kill" then
            r.bg:SetColorTexture(0.7, 0.05, 0.05, 0.30)
            r.tag:SetText("|cffff4040KILL|r")
            r.text:SetText(("|cffff6060%s|r killed by |cffffffff%s|r%s"):format(HL.ShortName(it.n),
                table.concat(it.killers, ", "), where ~= "" and (" – " .. where) or ""))
        elseif it.kind == "death" then
            r.bg:SetColorTexture(0.45, 0.1, 0.65, 0.30)
            r.tag:SetText("|cffc070ffDIED|r")
            r.text:SetText(("|cffffffff%s|r killed by |cffff6060%s|r%s"):format(it.victim, HL.ShortName(it.n),
                where ~= "" and (" – " .. where) or ""))
        else
            r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
            r.tag:SetText("|cffffd100Seen|r")
            r.text:SetText(("|cffffd100%s|r%s |cff888888(by %s)|r"):format(HL.ShortName(it.n),
                where ~= "" and (" in " .. where) or "", HL.ShortName(it.by)))
        end
        r:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, shown * ROW_H))
    page.summary:SetText(("|cffff4040%d kills|r, |cffc070ff%d deaths|r, |cffffd100%d sightings|r%s"):format(kills, deaths, sightings,
        #items > MAX_ROWS and (" – newest " .. MAX_ROWS .. " shown") or ""))
    page.empty:SetShown(shown == 0)
end

function HL:BuildLogPage(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -36)
    header:SetText("Recent activity")

    page.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.summary:SetPoint("TOPRIGHT", -16, -40)

    page.mode, page.period = "timeline", 86400
    page.h1 = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.h1:SetPoint("TOPLEFT", 18, -62)
    page.h3 = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.h3:SetPoint("TOPLEFT", 158, -62)

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -78)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 1)
    scroll:SetScrollChild(content)

    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("CENTER", 0, 10)
    page.empty:SetText("Nothing yet. Kills, deaths and sightings of KOS players show up here.")

    HL.MakeCheck(page, "Kills", "logKills", { "BOTTOMLEFT", 14, 12 }, function() HL:RefreshLog() end)
    HL.MakeCheck(page, "Deaths", "logDeaths", { "BOTTOMLEFT", 84, 12 }, function() HL:RefreshLog() end)
    HL.MakeCheck(page, "Sightings", "logSightings", { "BOTTOMLEFT", 166, 12 }, function() HL:RefreshLog() end)

    -- Timeline <-> hotspots per zone
    page.viewBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.viewBtn:SetSize(100, 22)
    page.viewBtn:SetPoint("BOTTOMLEFT", 258, 12)
    page.viewBtn:SetScript("OnClick", function()
        page.mode = (page.mode == "zones") and "timeline" or "zones"
        HL:RefreshLog()
    end)
    page.periodBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    page.periodBtn:SetSize(100, 22)
    page.periodBtn:SetPoint("LEFT", page.viewBtn, "RIGHT", 4, 0)
    page.periodBtn:SetScript("OnClick", function()
        page.period = (page.period > 86400) and 86400 or 7 * 86400
        HL:RefreshLog()
    end)

    local clear = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    clear:SetSize(110, 22)
    clear:SetPoint("BOTTOMRIGHT", -12, 12)
    clear:SetText("Clear sightings")
    clear:SetScript("OnClick", function() HL:ClearSightingLog() end)
    clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Empties your sighting log.")
        GameTooltip:AddLine("Kills stay: they're shared with your friends.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page:SetScript("OnShow", function() HL:RefreshLog() end)
    return page
end

HL:OnChange(function() HL:RefreshLog() end)
