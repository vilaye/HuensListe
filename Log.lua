-- Huens Liste: log of recent KOS kills and sightings ("Log" tab, /hl log)
--
-- Kills come from the synced kill credits (everyone sees the same kills).
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

-- Newest first: { kind = "kill" | "seen", n, t, z, s, by / killers }
function HL:LogItems(showKills, showSightings)
    local items, kills, sightings = {}, 0, 0
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
    return items, kills, sightings
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
        local it = self.item
        if not it then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if it.kind == "kill" then
            GameTooltip:AddLine("|cffff4040Kill:|r " .. HL.ShortName(it.n))
            GameTooltip:AddLine("Killed by " .. table.concat(it.killers, ", "), 1, 1, 1, true)
        else
            GameTooltip:AddLine("|cffffd100Sighting:|r " .. HL.ShortName(it.n))
            GameTooltip:AddLine("Spotted by " .. HL.ShortName(it.by), 1, 1, 1)
        end
        local where = place(it.z, it.s)
        if where ~= "" then GameTooltip:AddLine(where, 1, 0.82, 0, true) end
        GameTooltip:AddLine(date("%d.%m.%Y %H:%M:%S", it.t) .. " (" .. HL.Ago(it.t) .. ")", 0.7, 0.7, 0.7)
        local e = HL:Get(it.n, "kos")
        if e and e.r ~= "" then GameTooltip:AddLine("Note: " .. e.r, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

function HL:RefreshLog()
    if not page or not page:IsVisible() then return end
    local items, kills, sightings = self:LogItems(self.settings.logKills, self.settings.logSightings)
    local shown = math.min(#items, MAX_ROWS)
    for i = 1, shown do
        local it = items[i]
        local r = getRow(i)
        r.item = it
        r.time:SetText(whenText(it.t))
        local where = place(it.z, it.s)
        if it.kind == "kill" then
            r.bg:SetColorTexture(0.7, 0.05, 0.05, 0.30)
            r.tag:SetText("|cffff4040KILL|r")
            r.text:SetText(("|cffff6060%s|r killed by |cffffffff%s|r%s"):format(HL.ShortName(it.n),
                table.concat(it.killers, ", "), where ~= "" and (" – " .. where) or ""))
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
    page.summary:SetText(("|cffff4040%d kills|r, |cffffd100%d sightings|r%s"):format(kills, sightings,
        #items > MAX_ROWS and (" – newest " .. MAX_ROWS .. " shown") or ""))
    page.empty:SetShown(shown == 0)
end

function HL:BuildLogPage(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -36)
    header:SetText("Recent kills and sightings")

    page.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.summary:SetPoint("TOPRIGHT", -16, -40)

    local headers = { { "When", 18 }, { "", 110 }, { "What", 158 } }
    for _, h in ipairs(headers) do
        local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], -62)
        fs:SetText(h[1])
    end

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -78)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 1)
    scroll:SetScrollChild(content)

    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.empty:SetPoint("CENTER", 0, 10)
    page.empty:SetText("Nothing yet. Kills and sightings of KOS players show up here.")

    HL.MakeCheck(page, "Kills", "logKills", { "BOTTOMLEFT", 14, 12 }, function() HL:RefreshLog() end)
    HL.MakeCheck(page, "Sightings", "logSightings", { "BOTTOMLEFT", 104, 12 }, function() HL:RefreshLog() end)

    local clear = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    clear:SetSize(120, 22)
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
