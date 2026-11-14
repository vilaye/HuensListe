-- Huens Liste: list window, export/import, right-click menu, slash commands
local _, HL = ...

---------------------------------------------------------------------------
-- "Add with reason" popup
---------------------------------------------------------------------------
local function popupEditBox(p) return p.editBox or p.EditBox or (p.GetEditBox and p:GetEditBox()) end

StaticPopupDialogs["HUENSLISTE_ADD"] = {
    text = "Put %s on the %s?\nReason (optional):",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 80,
    OnAccept = function(self, data)
        local eb = popupEditBox(self)
        HL:Add(data.full, eb and eb:GetText() or "", data.list, data.relation)
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local d = p.data
        HL:Add(d.full, self:GetText(), d.list, d.relation)
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["HUENSLISTE_NOTE"] = {
    text = "Note for %s:",
    button1 = SAVE or ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 80,
    OnShow = function(self, data)
        local eb = popupEditBox(self)
        if eb and data then eb:SetText(data.r or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = popupEditBox(self)
        if eb then HL:EditNote(data.full, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        HL:EditNote(p.data.full, self:GetText())
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["HUENSLISTE_BOUNTY"] = {
    text = "Bounty on %s\n(for example \"50g from Vila\" – leave empty to remove it):",
    button1 = SAVE or ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self, data)
        local eb = popupEditBox(self)
        if eb and data then eb:SetText(data.r or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = popupEditBox(self)
        if eb then HL:SetBounty(data.full, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        HL:SetBounty(p.data.full, self:GetText())
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function HL:PromptBounty(full)
    local e = self:Get(HL.NormalizeName(full or "") or "", "kos")
    if not e then return end
    local cur = self:Bounty(e.n)
    StaticPopup_Show("HUENSLISTE_BOUNTY", HL.ColorName(HL.ShortName(e.n), "kos"), nil, { full = e.n, r = cur and cur.r or "" })
end

-- After a gank by someone who isn't listed yet (Kills.lua decides who)
StaticPopupDialogs["HUENSLISTE_GANK"] = {
    text = "%s was on you when you died.\nAdd to the KOS List? Note:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 80,
    OnShow = function(self, data)
        local eb = popupEditBox(self)
        if eb and data then eb:SetText(data.r or ""); eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = popupEditBox(self)
        HL:Add(data.full, eb and eb:GetText() or "", "kos", "enemy")
    end,
    OnCancel = function(_, data)
        if data then HL.gankDeclined[HL.Key(data.full)] = true end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        HL:Add(p.data.full, self:GetText(), "kos", "enemy")
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        local p = self:GetParent()
        if p.data then HL.gankDeclined[HL.Key(p.data.full)] = true end
        p:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function HL:PromptGank(full)
    local zone = HL.Clean(GetZoneText() or "", 60)
    StaticPopup_Show("HUENSLISTE_GANK", HL.ColorName(HL.ShortName(full), "kos"), nil,
        { full = full, r = "killed me" .. (zone ~= "" and (" in " .. zone) or "") })
end

function HL:PromptNote(full)
    local list, e = self:Find(HL.NormalizeName(full) or "")
    if not e then return end
    StaticPopup_Show("HUENSLISTE_NOTE", HL.ColorName(HL.ShortName(e.n), list), nil, { full = e.n, r = e.r })
end

function HL:PromptAdd(full, list, relation)
    list = list or "kos"
    full = HL.NormalizeName(full)
    if not full then return end
    -- wrong faction for this list: HL:Add explains why instead of asking for a reason first
    if (list == "kos" and relation == "friendly") or (list == "avoid" and relation == "enemy") then
        HL:Add(full, "", list, relation)
        return
    end
    StaticPopup_Show("HUENSLISTE_ADD", HL.ColorName(HL.ShortName(full), list), HL.ListLabel(list),
        { full = full, list = list, relation = relation })
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local ROW_H = 22
local main

-- The template's X button goes through HideUIPanel, which ignores addon frames in
-- combat on Forever ("We no longer allow addons to show or hide UI panels in combat").
-- Our windows aren't UI panels, so the X just hides them directly.
local function closeDirectly(frame)
    local button = frame.CloseButton or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if button then button:SetScript("OnClick", function() frame:Hide() end) end
end
local listPages = {} -- [list] = page

local function makeFS(parent, x, w, font)
    local f = parent:CreateFontString(nil, "OVERLAY", font)
    f:SetPoint("LEFT", x, 0)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
end

local function getRow(page, i)
    if page.rows[i] then return page.rows[i] end
    local list = page.list
    local r = CreateFrame("Frame", nil, page.content)
    r:SetSize(540, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
    r.name = makeFS(r, 4, 126, "GameFontNormal")
    r.level = makeFS(r, 132, 24, "GameFontHighlightSmall")
    r.reason = makeFS(r, 160, 132, "GameFontHighlightSmall")
    r.by = makeFS(r, 296, 88, "GameFontDisableSmall")
    r.kills = makeFS(r, 386, 44, "GameFontHighlightSmall")
    r.when = makeFS(r, 432, 60, "GameFontDisableSmall")

    r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
    r.del:SetSize(20, 20)
    r.del:SetPoint("RIGHT", -2, 0)
    r.del:SetScript("OnClick", function(self) HL:Remove(self:GetParent().full, list) end)

    local other = HL.OtherList(list)
    r.move = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.move:SetSize(24, 18)
    r.move:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
    r.move:SetText(list == "kos" and ">" or "<")
    r.move:SetScript("OnClick", function(self) HL:Move(self:GetParent().full) end)
    r.move:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Move to the " .. HL.ListLabel(other))
        GameTooltip:Show()
    end)
    r.move:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self, button)
        if not self.full then return end
        if IsShiftKeyDown() and list == "kos" then
            HL:SetPriority(self.full)
        elseif button == "LeftButton" then
            HL:PromptNote(self.full)
        elseif button == "RightButton" and list == "kos" then
            HL:PromptBounty(self.full)
        end
    end)
    r:SetScript("OnEnter", function(self)
        local e, s = self.entry, self.seenData
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(HL:ColoredName(e.n, list))
        local info = HL:InfoText(e.n)
        if info then GameTooltip:AddLine("Level " .. info) end
        if list == "kos" and HL:IsPriority(e.n) then GameTooltip:AddLine("High priority", 1, 0.82, 0) end
        if e.r ~= "" then GameTooltip:AddLine(e.r, 1, 1, 1, true) end
        local bounty = list == "kos" and HL:Bounty(e.n)
        if bounty then GameTooltip:AddLine("Bounty: " .. bounty.r .. " (set by " .. HL.ShortName(bounty.b) .. ")", 1, 0.82, 0, true) end
        GameTooltip:AddLine("Added by " .. HL.ShortName(e.b) .. " on " .. date("%d.%m.%Y %H:%M", e.t), 0.7, 0.7, 0.7)
        if list == "kos" then
            local count, killers, last = HL:KillStats(e.n)
            if count > 0 then
                local parts = {}
                for who, n in pairs(killers) do parts[#parts + 1] = who .. " (" .. n .. ")" end
                table.sort(parts)
                GameTooltip:AddLine(("Killed %d time%s – by %s"):format(count, count == 1 and "" or "s", table.concat(parts, ", ")), 1, 0.5, 0.5, true)
                GameTooltip:AddLine("Last kill " .. HL.Ago(last.t) .. (last.r ~= "" and (" in " .. last.r) or ""), 0.7, 0.7, 0.7)
            end
            local deaths, victims = HL:DeathStats(e.n)
            if deaths > 0 then
                local parts = {}
                for who, n in pairs(victims) do parts[#parts + 1] = who .. " (" .. n .. ")" end
                table.sort(parts)
                GameTooltip:AddLine(("Killed us %d time%s – %s"):format(deaths, deaths == 1 and "" or "s", table.concat(parts, ", ")), 0.75, 0.45, 1, true)
            end
        end
        if s then
            GameTooltip:AddLine("Last seen " .. HL.Ago(s.t) .. " in " .. (s.z or "?")
                .. ((s.s and s.s ~= "" and s.s ~= s.z) and (" – " .. s.s) or "")
                .. " by " .. HL.ShortName(s.by), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to edit the note", 0.4, 0.8, 1)
        if list == "kos" then
            GameTooltip:AddLine("Right-click to set a bounty", 0.4, 0.8, 1)
            GameTooltip:AddLine("Shift-click to toggle high priority", 0.4, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.rows[i] = r
    return r
end

local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12:0:0|t " -- high priority

-- Sort keys for the list columns. "added" (newest first) is the default.
local SORTS = {
    added  = function(x) return x.e.t end,
    name   = function(x) return HL.ShortName(x.e.n):lower() end,
    level  = function(x) return x.level end,
    reason = function(x) return x.e.r:lower() end,
    by     = function(x) return HL.ShortName(x.e.b):lower() end,
    kills  = function(x) return x.kills * 1000 + x.deaths end,
    when   = function(x) return x.when end,
}

local function refreshListPage(page)
    local list = page.list
    local filter = page.filter
    local items, total = {}, 0
    for _, e in pairs(HL:Entries(list)) do
        if not e.d then
            total = total + 1
            local match = true
            if filter and filter ~= "" then
                local bounty = list == "kos" and HL:Bounty(e.n)
                local hay = (HL.ShortName(e.n) .. " " .. e.r .. " " .. HL.ShortName(e.b) .. " "
                    .. (HL:InfoText(e.n, true) or "") .. (bounty and (" bounty " .. bounty.r) or "")
                    .. ((list == "kos" and HL:IsPriority(e.n)) and " high priority" or "")):lower()
                match = hay:find(filter, 1, true) ~= nil
            end
            if match then
                local info = HL:Info(e.n)
                local s = (list == "kos") and HL.db.seen[HL.Key(e.n)] or nil
                local x = { e = e, seen = s, level = info and info.l or 0, kills = 0, deaths = 0,
                    prio = list == "kos" and HL:IsPriority(e.n) or false }
                if list == "kos" then
                    x.kills = HL:KillStats(e.n)
                    x.deaths = HL:DeathStats(e.n)
                    x.when = s and s.t or 0
                else
                    x.when = e.t
                end
                items[#items + 1] = x
            end
        end
    end
    local get = SORTS[page.sortKey] or SORTS.added
    local desc = page.sortDesc
    local prioFirst = (page.sortKey or "added") == "added" -- default order: high priority on top
    table.sort(items, function(a, b)
        if prioFirst and a.prio ~= b.prio then return a.prio end
        local va, vb = get(a), get(b)
        if va ~= vb then
            if desc then return va > vb end
            return va < vb
        end
        if a.e.t ~= b.e.t then return a.e.t > b.e.t end
        return a.e.n < b.e.n
    end)
    for i, x in ipairs(items) do
        local e, s = x.e, x.seen
        local r = getRow(page, i)
        r.full, r.entry, r.seenData = e.n, e, s
        r.name:SetText((x.prio and STAR or "") .. HL:ColoredName(e.n, list)
            .. ((list == "kos" and HL:Bounty(e.n)) and " |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t" or ""))
        r.level:SetText(x.level > 0 and tostring(x.level) or "")
        r.reason:SetText(e.r)
        r.by:SetText(HL.ShortName(e.b))
        if list ~= "kos" then
            r.kills:SetText("")
        elseif x.kills == 0 and x.deaths == 0 then
            r.kills:SetText("|cff666666-|r")
        else
            r.kills:SetText(("|cffff6060%d|r |cff888888/|r |cffc070ff%d|r"):format(x.kills, x.deaths))
        end
        if list == "kos" then
            r.when:SetText(s and HL.Ago(s.t) or "-")
        else
            r.when:SetText(HL.Ago(e.t))
        end
        r:Show()
    end
    for i = #items + 1, #page.rows do page.rows[i]:Hide() end
    page.content:SetHeight(math.max(1, #items * ROW_H))
    if #items ~= total then
        page.count:SetText(#items .. " of " .. total .. " on the " .. HL.ListLabel(list))
    else
        page.count:SetText(total .. " on the " .. HL.ListLabel(list))
    end
end

function HL:RefreshList()
    if not main or not main:IsShown() then return end
    for _, page in pairs(listPages) do refreshListPage(page) end
end

local function makeCheck(parent, label, key, anchor, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint(unpack(anchor))
    local t = cb.Text or cb.text
    if t then t:SetText(label) else
        t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        t:SetText(label)
    end
    cb:SetScript("OnShow", function(self) self:SetChecked(HL.settings[key]) end)
    cb:SetScript("OnClick", function(self)
        HL.settings[key] = self:GetChecked() and true or false
        if onChange then onChange(HL.settings[key]) end
    end)
    return cb
end

HL.MakeFS, HL.MakeCheck = makeFS, makeCheck -- used by the Log tab (Log.lua)

---------------------------------------------------------------------------
-- Users tab: who has the addon and which version
---------------------------------------------------------------------------
local VIA_LABEL = { GUILD = "Guild", PARTY = "Group", RAID = "Group", INSTANCE_CHAT = "Group",
    CHANNEL = "Channel", WHISPER = "Whisper" }
local ONLINE_WINDOW = 6 * 60 -- heard from in the last 6 minutes (hello is every 5)

local usersPage, usersContent
local userRows = {}

local function getUserRow(i)
    if userRows[i] then return userRows[i] end
    local r = CreateFrame("Frame", nil, usersContent)
    r:SetSize(540, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("LEFT", 6, 0)
    r.name = makeFS(r, 20, 150, "GameFontHighlight")
    r.version = makeFS(r, 175, 95, "GameFontHighlightSmall")
    r.week = makeFS(r, 275, 45, "GameFontHighlight")
    r.kills = makeFS(r, 325, 45, "GameFontHighlight")
    r.status = makeFS(r, 375, 95, "GameFontDisableSmall")
    r.via = makeFS(r, 475, 65, "GameFontDisableSmall")
    userRows[i] = r
    return r
end

function HL:RefreshUsers()
    if not usersPage or not usersPage:IsVisible() then return end
    local now = GetServerTime()
    local list = { { n = HL.me, v = HL.VERSION, t = now, via = nil, me = true } }
    local newest = HL.VersionNumber(HL.VERSION)
    for _, p in pairs(self.db.peers) do
        list[#list + 1] = p
        if p.v and HL.VersionNumber(p.v) > newest then newest = HL.VersionNumber(p.v) end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me and true or false end
        return (a.t or 0) > (b.t or 0)
    end)

    local scores = self:KillScores()
    local weekScores = self:KillScores(HL.WeekStart())
    local weekBest = 0
    for _, n in pairs(weekScores) do if n > weekBest then weekBest = n end end
    local online, outdated = 0, 0
    for i, p in ipairs(list) do
        local r = getUserRow(i)
        local isOnline = p.me or (now - (p.t or 0) < ONLINE_WINDOW)
        if isOnline then online = online + 1 end
        r.dot:SetColorTexture(isOnline and 0.2 or 0.4, isOnline and 0.9 or 0.4, isOnline and 0.2 or 0.4, 1)
        r.name:SetText(HL.ShortName(p.n) .. (p.me and " |cff888888(you)|r" or ""))
        local kills = scores[HL.Key(p.n or "")] or 0
        r.kills:SetText(kills > 0 and ("|cffff6060" .. kills .. "|r") or "|cff666666-|r")
        local week = weekScores[HL.Key(p.n or "")] or 0
        -- this week's leader in gold
        r.week:SetText(week > 0 and ((week == weekBest and "|cffffd100" or "|cffff6060") .. week .. "|r") or "|cff666666-|r")
        if not p.v then
            r.version:SetText("|cff888888unknown|r")
        elseif HL.VersionNumber(p.v) < newest then
            r.version:SetText("|cffff8020" .. p.v .. " (outdated)|r")
            outdated = outdated + 1
        else
            r.version:SetText("|cff40ff40" .. p.v .. "|r")
        end
        r.status:SetText(p.me and "online" or (isOnline and "|cff40ff40online|r" or HL.Ago(p.t)))
        r.via:SetText(p.via and VIA_LABEL[p.via] or "")
        r:Show()
    end
    for i = #list + 1, #userRows do userRows[i]:Hide() end
    usersContent:SetHeight(math.max(1, #list * ROW_H))
    usersPage.summary:SetText(("%d users, %d online%s"):format(#list, online,
        outdated > 0 and (", |cffff8020" .. outdated .. " outdated|r") or ""))
end

function HL:BuildUsersPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    usersPage = page

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -36)
    header:SetText("Addon users")

    page.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.summary:SetPoint("TOPRIGHT", -16, -40)

    local desc = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", 20, -58)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Everyone who synced with you in the last 30 days. Week / Total = KOS kills this week (resets Monday) and all time; the week's leader is gold.")

    local headers = { { "Name", 26 }, { "Version", 181 }, { "Week", 281 }, { "Total", 331 }, { "Status", 381 }, { "Via", 481 } }
    for _, h in ipairs(headers) do
        local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], -82)
        fs:SetText(h[1])
    end

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -98)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    usersContent = CreateFrame("Frame", nil, scroll)
    usersContent:SetSize(540, 1)
    scroll:SetScrollChild(usersContent)

    makeCheck(page, "Only sync with members of my guild (and my private channel)", "guildOnly", { "BOTTOMLEFT", 14, 12 })

    local refresh = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    refresh:SetSize(110, 22)
    refresh:SetPoint("BOTTOMRIGHT", -12, 12)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function()
        HL:PingUsers()
        HL:Print("Asked everyone online for their version...")
    end)

    page:SetScript("OnShow", function() HL:RefreshUsers() end)
    return page
end

---------------------------------------------------------------------------
-- Quality of Life tab
---------------------------------------------------------------------------
function HL:BuildQoLPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -36)
    header:SetText("Quality of Life")

    -- Buff reminders: Well Fed and campfire
    local section = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    section:SetPoint("TOPLEFT", 20, -72)
    section:SetText("Buff reminders (on-screen text, hidden while you are dead)")

    -- One row: checkbox on the left, Move / Reset buttons on the right
    local refreshers = {}
    local function reminderRow(y, label, key, update, isUnlocked, setUnlocked, resetPos)
        makeCheck(page, label, key, { "TOPLEFT", 16, y }, update)
        local moveBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        moveBtn:SetSize(80, 22)
        moveBtn:SetPoint("TOPLEFT", 400, y - 1)
        local function refresh() moveBtn:SetText(isUnlocked() and "Lock" or "Move") end
        moveBtn:SetScript("OnClick", function()
            setUnlocked(not isUnlocked())
            refresh()
        end)
        local resetBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        resetBtn:SetSize(80, 22)
        resetBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)
        resetBtn:SetText("Reset")
        resetBtn:SetScript("OnClick", resetPos)
        refreshers[#refreshers + 1] = refresh
    end

    reminderRow(-90, "Remind me when I'm not Well Fed", "wellFedReminder",
        function() HL:UpdateWellFed() end,
        function() return HL:IsWellFedUnlocked() end,
        function(v) HL:SetWellFedUnlocked(v) end,
        function() HL:ResetWellFedPosition() end)
    reminderRow(-114, "Remind me when my campfire buff is missing", "campfireReminder",
        function() HL:UpdateCampfire() end,
        function() return HL:IsCampfireUnlocked() end,
        function(v) HL:SetCampfireUnlocked(v) end,
        function() HL:ResetCampfirePosition() end)

    local desc = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", 44, -142)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText("Shows \"You are not Well Fed!\" / \"Campfire buff is missing!\" on screen while the buff is gone.")

    -- KOS target button
    local tsection = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tsection:SetPoint("TOPLEFT", 20, -184)
    tsection:SetText("Target nearby KOS")

    makeCheck(page, "Show the on-screen target button", "targetButton", { "TOPLEFT", 16, -202 },
        function() HL:UpdateTargetButton() end)

    local tdesc = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tdesc:SetPoint("TOPLEFT", 44, -228)
    tdesc:SetWidth(520)
    tdesc:SetJustifyH("LEFT")
    tdesc:SetText("Targets the KOS player you saw most recently (Shift + drag to move the button). "
        .. "Also works without the button: Key Bindings > AddOns > Huens Liste, or a macro.")

    local macroBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    macroBtn:SetSize(120, 22)
    macroBtn:SetPoint("TOPLEFT", 44, -256)
    macroBtn:SetText("Create macro")
    macroBtn:SetScript("OnClick", function() HL:CreateTargetMacro() end)

    local tResetBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    tResetBtn:SetSize(120, 22)
    tResetBtn:SetPoint("LEFT", macroBtn, "RIGHT", 8, 0)
    tResetBtn:SetText("Reset position")
    tResetBtn:SetScript("OnClick", function() HL:ResetTargetButtonPosition() end)

    -- Quiet zones
    local qsection = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qsection:SetPoint("TOPLEFT", 20, -296)
    qsection:SetText("Quiet zones (no KOS alerts, sharing or log entries; the skull still shows)")

    makeCheck(page, "Quiet in battlegrounds and arenas", "quietPvP", { "TOPLEFT", 16, -314 })
    makeCheck(page, "Quiet in cities, inns and sanctuaries", "quietCities", { "TOPLEFT", 16, -338 })

    makeCheck(page, "After a gank: offer to add my killer to the KOS List (not in battlegrounds)", "gankSuggest", { "TOPLEFT", 16, -362 })

    page:SetScript("OnShow", function()
        for _, refresh in ipairs(refreshers) do refresh() end
    end)
    -- Leaving the window locks the reminders again
    page:SetScript("OnHide", function()
        if HL:IsWellFedUnlocked() then HL:SetWellFedUnlocked(false) end
        if HL:IsCampfireUnlocked() then HL:SetCampfireUnlocked(false) end
    end)
    return page
end

---------------------------------------------------------------------------
-- Options tab: everything that used to be slash-command only
---------------------------------------------------------------------------
-- A plain slider built without templates (their names differ between clients)
local function makeSlider(parent, label, key, minV, maxV, step, anchor, fmt, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(210, 16)
    s:SetPoint(unpack(anchor))
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    local bar = s:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("LEFT")
    bar:SetPoint("RIGHT")
    bar:SetHeight(6)
    bar:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(24, 24) end
    local text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    local function show(v) text:SetText(label .. ": |cffffd100" .. fmt:format(v) .. "|r") end
    s:SetScript("OnShow", function(self)
        local v = tonumber(HL.settings[key]) or minV
        self.loading = true
        self:SetValue(v)
        self.loading = false
        show(v)
    end)
    s:SetScript("OnValueChanged", function(self, v)
        if self.loading then return end
        v = math.max(minV, math.min(maxV, math.floor(v / step + 0.5) * step))
        HL.settings[key] = v
        show(v)
        if onChange then onChange(v) end
    end)
    return s
end

function HL:SetSyncChannel(name, password)
    name = strtrim(name or "")
    self:LeaveSyncChannel(self.settings.channel)
    if name == "" or name:lower() == "off" then
        self.settings.channel, self.settings.channelPassword = "", ""
        self:Print("Sync channel disabled.")
        return
    end
    self.settings.channel, self.settings.channelPassword = name, strtrim(password or "")
    self:JoinSyncChannel()
    self:ScheduleHello(5)
    self:Print("Syncing via channel |cffffff00" .. name .. "|r. Your friends need the same name and password.")
end

function HL:BuildOptionsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local function title(text, x, y, font)
        local fs = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end
    title("Options", 20, -36, "GameFontNormalLarge")

    -- left column: alerts
    title("Alerts", 20, -64)
    local y = -80
    local function check(label, key, onChange)
        local cb = makeCheck(page, label, key, { "TOPLEFT", 16, y }, onChange)
        y = y - 22
        return cb
    end
    check("Alert me when I see a KOS player", "alerts")
    check("Play sounds", "sound")
    check("Normal KOS players: chat line only", "normalQuiet")
    check("Show sightings from my friends", "sightingAlerts")
    check("Share my sightings with friends", "shareSightings")
    check("Warn me when I enter a zone with KOS activity", "zoneWarning")
    check("Swine List alerts (group join, whisper)", "avoidAlerts")
    local mm = check("Minimap button", "minimapHide")
    mm:SetScript("OnShow", function(self) self:SetChecked(not HL.settings.minimapHide) end)
    mm:SetScript("OnClick", function(self)
        HL.settings.minimapHide = not self:GetChecked()
        HL:UpdateMinimapButton()
    end)

    -- right column: sliders
    title("Alert timing and the nameplate skull", 320, -64)
    makeSlider(page, "Alert cooldown per player (seconds)", "alertCooldown", 10, 300, 10,
        { "TOPLEFT", 324, -104 }, "%d")
    makeSlider(page, "Skull size", "plateScale", 0.5, 2, 0.1, { "TOPLEFT", 324, -150 }, "%.1f",
        function() HL:RefreshPlates() end)
    makeSlider(page, "Skull height above the nameplate", "plateOffsetY", -40, 80, 2, { "TOPLEFT", 324, -196 }, "%d",
        function() HL:RefreshPlates() end)

    -- sync
    title("Sync", 20, -268)
    y = -284
    check("Sync over guild chat", "syncGuild")
    check("Sync with my party / raid", "syncGroup")
    check("Only accept sync from members of my guild", "guildOnly")

    title("Private sync channel (non-guild friends)", 320, -268)
    local nameLabel = title("Name", 324, -288, "GameFontNormalSmall")
    local pwLabel = title("Password", 452, -288, "GameFontNormalSmall")
    local nameBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    nameBox:SetSize(116, 20)
    nameBox:SetPoint("TOPLEFT", 328, -302)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(30)
    local pwBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    pwBox:SetSize(100, 20)
    pwBox:SetPoint("TOPLEFT", 456, -302)
    pwBox:SetAutoFocus(false)
    pwBox:SetMaxLetters(30)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)
    pwBox:SetScript("OnEscapePressed", pwBox.ClearFocus)
    nameBox:SetScript("OnEnterPressed", function() pwBox:SetFocus() end)

    local function apply()
        local name = (strtrim(nameBox:GetText() or ""):gsub("%s", ""))
        local pw = (strtrim(pwBox:GetText() or ""):gsub("%s", ""))
        HL:SetSyncChannel(name, pw)
        nameBox:ClearFocus(); pwBox:ClearFocus()
    end
    pwBox:SetScript("OnEnterPressed", apply)
    local applyBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    applyBtn:SetSize(80, 22)
    applyBtn:SetPoint("TOPLEFT", 324, -328)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", apply)
    local offBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    offBtn:SetSize(80, 22)
    offBtn:SetPoint("LEFT", applyBtn, "RIGHT", 6, 0)
    offBtn:SetText("Turn off")
    offBtn:SetScript("OnClick", function()
        nameBox:SetText(""); pwBox:SetText("")
        HL:SetSyncChannel("", "")
    end)

    page:SetScript("OnShow", function()
        nameBox:SetText(HL.settings.channel or "")
        pwBox:SetText(HL.settings.channelPassword or "")
    end)
    return page
end

local function buildListPage(parent, list)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page.list, page.rows = list, {}
    listPages[list] = page

    page.count = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    page.count:SetPoint("TOPRIGHT", -16, -32)

    local l1 = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l1:SetPoint("TOPLEFT", 20, -32)
    l1:SetText("Full name (First Last)")
    local l2 = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l2:SetPoint("TOPLEFT", 182, -32)
    l2:SetText(list == "kos" and "Reason (enemy faction only)" or "Reason (your own faction)")

    local nameBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    nameBox:SetSize(150, 20)
    nameBox:SetPoint("TOPLEFT", 22, -46)
    nameBox:SetAutoFocus(false)

    local reasonBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    reasonBox:SetSize(220, 20)
    reasonBox:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
    reasonBox:SetAutoFocus(false)
    reasonBox:SetMaxLetters(80)

    local addBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", reasonBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local n = strtrim(nameBox:GetText() or "")
        if n == "" then HL:Print("Enter a name first.") return end
        HL:Add(n, reasonBox:GetText(), list)
        nameBox:SetText(""); reasonBox:SetText("")
        nameBox:ClearFocus(); reasonBox:ClearFocus()
    end)

    local tgtBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    tgtBtn:SetSize(90, 22)
    tgtBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    tgtBtn:SetText("Add Target")
    tgtBtn:SetScript("OnClick", function()
        local full = HL.UnitFullName("target")
        if not full then HL:Print("Target a player first.") return end
        HL:Add(full, reasonBox:GetText(), list, HL.FactionRelation("target"))
        reasonBox:SetText(""); reasonBox:ClearFocus()
    end)

    nameBox:SetScript("OnEnterPressed", function() reasonBox:SetFocus() end)
    reasonBox:SetScript("OnEnterPressed", function() addBtn:Click() end)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)
    reasonBox:SetScript("OnEscapePressed", reasonBox.ClearFocus)

    -- Search
    local searchLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 20, -77)
    searchLabel:SetText("Search:")
    local searchBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPLEFT", 72, -72)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        page.filter = strtrim(self:GetText() or ""):lower()
        if page:IsVisible() then refreshListPage(page) end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
    local searchHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    searchHint:SetText("name, note, class – click a column to sort")

    -- Column headers: click to sort, click again to reverse
    page.sortKey, page.sortDesc = "added", true
    local arrow = page:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(9, 8)
    arrow:Hide()
    local headers = { { "Name", 16, "name" }, { "Lv", 144, "level" }, { "Reason", 172, "reason" }, { "Added by", 308, "by" } }
    if list == "kos" then
        headers[#headers + 1] = { "K / D", 398, "kills" }
        headers[#headers + 1] = { "Last seen", 444, "when" }
    else
        headers[#headers + 1] = { "Added", 444, "when" }
    end
    -- text columns start A-Z, number and time columns start with the biggest/newest
    local DESC_FIRST = { level = true, kills = true, when = true }
    for _, h in ipairs(headers) do
        local btn = CreateFrame("Button", nil, page)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT")
        fs:SetText(h[1])
        btn:SetSize(math.max(20, fs:GetStringWidth() + 4), 14)
        btn:SetPoint("TOPLEFT", h[2], -98)
        btn:SetScript("OnClick", function(self)
            if page.sortKey == h[3] then
                page.sortDesc = not page.sortDesc
            else
                page.sortKey, page.sortDesc = h[3], DESC_FIRST[h[3]] or false
            end
            arrow:ClearAllPoints()
            arrow:SetPoint("LEFT", fs, "RIGHT", 2, 0)
            if page.sortDesc then arrow:SetTexCoord(0, 0.5625, 0, 1) else arrow:SetTexCoord(0, 0.5625, 1, 0) end
            arrow:Show()
            refreshListPage(page)
        end)
        btn:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function() fs:SetTextColor(1, 0.82, 0) end)
    end

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -114)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    page.content = CreateFrame("Frame", nil, scroll)
    page.content:SetSize(540, 1)
    scroll:SetScrollChild(page.content)

    if list == "kos" then
        makeCheck(page, "Alerts", "alerts", { "BOTTOMLEFT", 14, 12 })
        makeCheck(page, "Sound", "sound", { "BOTTOMLEFT", 104, 12 })
        makeCheck(page, "Share sightings", "shareSightings", { "BOTTOMLEFT", 190, 12 })
    else
        makeCheck(page, "Alerts (joins your group, whispers)", "avoidAlerts", { "BOTTOMLEFT", 14, 12 })
        makeCheck(page, "Sound", "sound", { "BOTTOMLEFT", 220, 12 })
    end

    local function bottomBtn(text, x, fn)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(72, 22)
        b:SetPoint("BOTTOMRIGHT", x, 12)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    bottomBtn("Sync", -12, function() HL:SendHello(); HL:Print("Sync requested.") end)
    bottomBtn("Export", -88, function() HL:ShowExport(list) end)
    bottomBtn("Import", -164, function() HL:ShowImport() end)
    return page
end

local function createMain()
    main = CreateFrame("Frame", "HuensListeFrame", UIParent, "BasicFrameTemplateWithInset")
    main:SetSize(600, 440)
    main:SetPoint("CENTER")
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", main.StopMovingOrSizing)
    main:SetClampedToScreen(true)
    main:SetFrameStrata("HIGH")
    main:Hide()
    tinsert(UISpecialFrames, "HuensListeFrame")
    closeDirectly(main)

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|cffcc2222Huens Liste|r")

    -- Tabs 1 + 2: the two lists
    local kosPage = buildListPage(main, "kos")
    local avoidPage = buildListPage(main, "avoid")

    -- Tab 3: Log, then Quality of Life, Users, Patch Notes
    local log = HL:BuildLogPage(main)
    local qol = HL:BuildQoLPage(main)
    local users = HL:BuildUsersPage(main)
    local options = HL:BuildOptionsPage(main)
    local notes = HL:BuildPatchNotesPage(main)

    -- Tabs below the window
    local pages = { kosPage, avoidPage, log, qol, users, options, notes }
    local labels = { "KOS List", "Swine List", "Log", "QoL", "Users", "Options", "Patch Notes" }
    main.tabs = {}
    local function selectTab(id)
        for i, page in ipairs(pages) do page:SetShown(i == id) end
        if PanelTemplates_SetTab then PanelTemplates_SetTab(main, id) end
        main.selectedTab = id
    end
    main.selectTab = selectTab
    for i, label in ipairs(labels) do
        local tab = CreateFrame("Button", "HuensListeFrameTab" .. i, main, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(label)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
        if i == 1 then
            tab:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 11, 2)
        else
            tab:SetPoint("LEFT", main.tabs[i - 1], "RIGHT", 3, 0)
        end
        tab:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            selectTab(self:GetID())
        end)
        main.tabs[i] = tab
    end
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(main, #labels) end
    selectTab(1)

    main:SetScript("OnShow", function() HL:RefreshList() end)
end

function HL:ToggleMain()
    if not main then createMain() end
    main:SetShown(not main:IsShown())
end

HL.TAB_LOG, HL.TAB_OPTIONS, HL.TAB_PATCH_NOTES = 3, 6, 7
function HL:ShowTab(id)
    if not main then createMain() end
    main:Show()
    main.selectTab(id)
end

---------------------------------------------------------------------------
-- Patch Notes tab
---------------------------------------------------------------------------
function HL:BuildPatchNotesPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -36)
    header:SetText("Patch Notes")

    local installed = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    installed:SetPoint("TOPRIGHT", -16, -40)

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -62)
    scroll:SetPoint("BOTTOMRIGHT", -32, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 1)
    scroll:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 8, -4)
    text:SetWidth(520)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    if text.SetSpacing then text:SetSpacing(3) end

    page:SetScript("OnShow", function()
        installed:SetText("You have version |cff40ff40" .. HL.VERSION .. "|r")
        text:SetText(HL:PatchNotesText())
        content:SetHeight(math.max(1, text:GetStringHeight() + 12))
    end)
    return page
end

HL:OnChange(function() HL:RefreshList() end)

---------------------------------------------------------------------------
-- Export / import window
---------------------------------------------------------------------------
local ioFrame
local function createIO()
    ioFrame = CreateFrame("Frame", "HuensListeIOFrame", UIParent, "BasicFrameTemplateWithInset")
    ioFrame:SetSize(500, 300)
    ioFrame:SetPoint("CENTER", 0, 40)
    ioFrame:SetFrameStrata("DIALOG")
    ioFrame:SetMovable(true)
    ioFrame:EnableMouse(true)
    ioFrame:RegisterForDrag("LeftButton")
    ioFrame:SetScript("OnDragStart", ioFrame.StartMoving)
    ioFrame:SetScript("OnDragStop", ioFrame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "HuensListeIOFrame")
    closeDirectly(ioFrame)

    ioFrame.title = ioFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ioFrame.title:SetPoint("TOP", 0, -5)

    local sf = CreateFrame("ScrollFrame", nil, ioFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -30)
    sf:SetPoint("BOTTOMRIGHT", -32, 40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(450)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() ioFrame:Hide() end)
    sf:SetScrollChild(eb)
    ioFrame.eb = eb

    ioFrame.btn = CreateFrame("Button", nil, ioFrame, "UIPanelButtonTemplate")
    ioFrame.btn:SetSize(90, 22)
    ioFrame.btn:SetPoint("BOTTOMRIGHT", -12, 10)
    ioFrame.btn:SetText("Import")
    ioFrame.btn:SetScript("OnClick", function()
        HL:Import(eb:GetText())
        ioFrame:Hide()
    end)
end

function HL:ShowExport(list)
    list = list or "kos"
    if not ioFrame then createIO() end
    ioFrame.title:SetText("Export " .. HL.ListLabel(list) .. " – press Ctrl+C to copy")
    ioFrame.btn:Hide()
    ioFrame:Show()
    ioFrame.eb:SetText(self:ExportString(list))
    ioFrame.eb:SetFocus()
    ioFrame.eb:HighlightText()
end

function HL:ShowImport()
    if not ioFrame then createIO() end
    ioFrame.title:SetText("Import – paste a Huens Liste string (Ctrl+V)")
    ioFrame.btn:Show()
    ioFrame:Show()
    ioFrame.eb:SetText("")
    ioFrame.eb:SetFocus()
end

---------------------------------------------------------------------------
-- Right-click menu on players
---------------------------------------------------------------------------
if Menu and Menu.ModifyMenu then
    local function extend(_, root, ctx)
        if not ctx or not HL.db then return end
        local full
        if ctx.unit and not HL.IsSecret(ctx.unit) then
            full = HL.UnitFullName(ctx.unit)
            if not full then
                local ok, isPlayer = pcall(UnitIsPlayer, ctx.unit)
                if ok and not HL.IsSecret(isPlayer) and not isPlayer then return end -- NPC
            end
        end
        if not full then
            local name, server = ctx.name, ctx.server
            if not name or HL.IsSecret(name) or HL.IsSecret(server) then return end
            if not name:find("-", 1, true) and server and server ~= "" then name = name .. "-" .. server end
            full = HL.NormalizeName(name)
        end
        if not full or full == HL.me then return end
        local relation = ctx.unit and HL.FactionRelation(ctx.unit) or nil
        local onList = HL:Find(full)
        root:CreateDivider()
        root:CreateTitle("Huens Liste")
        if onList then
            root:CreateButton("Edit note", function() HL:PromptNote(full) end)
            if onList == "kos" then
                root:CreateButton(HL:Bounty(full) and "Edit bounty" or "Set bounty", function() HL:PromptBounty(full) end)
                root:CreateButton(HL:IsPriority(full) and "Back to normal priority" or "Mark as high priority",
                    function() HL:SetPriority(full) end)
            end
            root:CreateButton("Remove from the " .. HL.ListLabel(onList), function() HL:Remove(full, onList) end)
            local other = HL.OtherList(onList)
            if not ((other == "kos" and relation == "friendly") or (other == "avoid" and relation == "enemy")) then
                root:CreateButton("Move to the " .. HL.ListLabel(other), function() HL:Move(full) end)
            end
        else
            if relation ~= "friendly" then
                root:CreateButton("Add to the " .. HL.ListLabel("kos"), function() HL:PromptAdd(full, "kos", relation) end)
            end
            if relation ~= "enemy" then
                root:CreateButton("Add to the " .. HL.ListLabel("avoid"), function() HL:PromptAdd(full, "avoid", relation) end)
            end
        end
    end
    for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FRIEND",
        "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FOCUS" }) do
        pcall(Menu.ModifyMenu, tag, extend)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function toggle(key, arg, label)
    local v
    if arg == "on" then v = true elseif arg == "off" then v = false else v = not HL.settings[key] end
    HL.settings[key] = v
    HL:Print(label .. ": " .. (v and "|cff40ff40on|r" or "|cffff4040off|r"))
end

local HELP = {
    "|cffffff00/hl|r – open the list",
    "|cffffff00/hl add Firstname Lastname [reason]|r – add to the KOS List (enemy faction)",
    "|cffffff00/hl swine Firstname Lastname [reason]|r – add to the Swine List (your faction)",
    "|cffffff00/hl target [reason]|r – add your target (KOS or Swine List, by faction)",
    "|cffffff00/hl move Firstname Lastname|r – move between the two lists",
    "|cffffff00/hl log|r – recent kills, deaths and sightings",
    "|cffffff00/hl macro|r – create a macro that targets the nearby KOS player",
    "|cffffff00/hl notes|r – patch notes: what's new in each version",
    "|cffffff00/hl note Firstname Lastname new note|r – change the note (or click the row in /hl)",
    "|cffffff00/hl options|r – all settings in one tab",
    "|cffffff00/hl prio Firstname Lastname|r – toggle high priority for a KOS player (or Shift-click their row)",
    "|cffffff00/hl bounty Firstname Lastname text|r – set a bounty on a KOS player (no text = remove)",
    "|cffffff00/hl del Firstname Lastname|r – remove from either list (no name = target)",
    "|cffffff00/hl debug|r – print sync traffic in chat (for troubleshooting)",
    "|cffffff00/hl list|r – print both lists",
    "|cffffff00/hl sync|r – sync with friends now",
    "|cffffff00/hl channel <name> [password]|r – private sync channel for friends outside your guild (|cffffff00/hl channel off|r)",
    "|cffffff00/hl guild, group, alerts, sound, share, remote [on/off]|r – toggles",
    "|cffffff00/hl trust [on/off]|r – only accept sync from members of your guild (on by default)",
    "|cffffff00/hl offset <pixels>|r / |cffffff00/hl scale <0.5-2>|r – move/resize the nameplate skull",
    "|cffffff00/hl minimap [on/off]|r – show/hide the minimap button",
    "|cffffff00/hl wellfed [on/off]|r – Well Fed reminder (move it in the Quality of Life tab)",
    "|cffffff00/hl campfire [on/off]|r – campfire buff reminder (move it in the Quality of Life tab)",
    "|cffffff00/hl buffs|r – list your buffs (troubleshooting for the reminders)",
    "|cffffff00/hl export|r / |cffffff00/hl import|r – share via copy & paste",
}

-- "/hl add Vila Yeezy camps XR" and "/hl add Vila-Yeezy camps XR" both work
local function parseNameAndReason(rest)
    local first, after = rest:match("^(%S+)%s*(.-)$")
    if not first then return end
    if first:find("-", 1, true) then return first, after end
    local second, reason = after:match("^(%S+)%s*(.-)$")
    if second then return first .. " " .. second, reason end
    return first, ""
end

SLASH_HUENSLISTE1 = "/hl"
SLASH_HUENSLISTE2 = "/huens"
SLASH_HUENSLISTE3 = "/kos"
SlashCmdList.HUENSLISTE = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local arg = (rest or ""):lower()

    if cmd == "" then
        HL:ToggleMain()
    elseif cmd == "add" or cmd == "swine" or cmd == "avoid" then
        local list = (cmd == "add") and "kos" or "avoid"
        local name, reason = parseNameAndReason(rest)
        if not name then HL:Print("Usage: /hl " .. cmd .. " Firstname Lastname [reason]") return end
        HL:Add(name, reason, list)
    elseif cmd == "log" then
        HL:ShowTab(HL.TAB_LOG)
    elseif cmd == "macro" then
        HL:CreateTargetMacro()
    elseif cmd == "notes" or cmd == "patchnotes" or cmd == "changelog" then
        HL:ShowTab(HL.TAB_PATCH_NOTES)
    elseif cmd == "bounty" then
        local name, text = parseNameAndReason(rest)
        if not name then HL:Print("Usage: /hl bounty Firstname Lastname 50g from me  (no text = remove)") return end
        HL:SetBounty(name, text)
    elseif cmd == "note" then
        local name, note = parseNameAndReason(rest)
        if not name then HL:Print("Usage: /hl note Firstname Lastname new note") return end
        HL:EditNote(name, note)
    elseif cmd == "move" then
        local who = rest ~= "" and rest or HL.UnitFullName("target")
        if not who then HL:Print("Usage: /hl move Firstname Lastname") return end
        if not HL:Find(HL.NormalizeName(who) or "") then HL:Print("Not on a list: " .. who) return end
        HL:Move(who)
    elseif cmd == "debug" then
        HL.debug = not HL.debug
        HL:Print("Debug: " .. (HL.debug and "on – addon traffic is printed in chat" or "off"))
        if HL.debug then
            HL:Print("me = '" .. tostring(HL.me) .. "', realmless = " .. tostring(HL.IsRealmless()))
            local ok, n, r = pcall(UnitName, "target")
            if ok and n and not HL.IsSecret(n) then
                HL:Print("UnitName(target) = '" .. n .. "', '" .. tostring(r) .. "' -> " .. tostring(HL.UnitFullName("target")))
            end
        end
    elseif cmd == "target" or cmd == "t" then
        local full = HL.UnitFullName("target")
        if not full then HL:Print("Target a player first.") return end
        -- enemy faction -> KOS, own faction -> Avoid List
        local relation = HL.FactionRelation("target")
        HL:Add(full, rest, relation == "friendly" and "avoid" or "kos", relation)
    elseif cmd == "del" or cmd == "remove" or cmd == "rm" then
        local who = rest ~= "" and rest or HL.UnitFullName("target")
        if not who then HL:Print("Usage: /hl del Firstname Lastname") return end
        HL:Remove(who)
    elseif cmd == "list" then
        for _, list in ipairs(HL.LIST_ORDER) do
            local n = 0
            for _, e in pairs(HL:Entries(list)) do
                if not e.d then
                    n = n + 1
                    print(("  %s %s |cff888888(%s)|r"):format(HL.ColorName(HL.ShortName(e.n), list), e.r, HL.ShortName(e.b)))
                end
            end
            HL:Print(n .. " on the " .. HL.ListLabel(list))
        end
    elseif cmd == "sync" then
        HL:SendHello()
        HL:Print("Sync requested.")
    elseif cmd == "channel" then
        local name, pw = rest:match("^(%S*)%s*(%S*)$")
        if not name or name == "" then
            HL:Print("Sync channel: " .. (HL.settings.channel ~= "" and HL.settings.channel or "none"))
        else
            HL:SetSyncChannel(name, pw)
        end
    elseif cmd == "prio" or cmd == "priority" then
        local who = rest ~= "" and rest or HL.UnitFullName("target")
        if not who then HL:Print("Usage: /hl prio Firstname Lastname") return end
        HL:SetPriority(who)
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        HL:ShowTab(HL.TAB_OPTIONS)
    elseif cmd == "trust" then toggle("guildOnly", arg, "Only sync with guild members")
    elseif cmd == "guild" then toggle("syncGuild", arg, "Guild sync")
    elseif cmd == "group" then toggle("syncGroup", arg, "Group sync")
    elseif cmd == "alerts" then toggle("alerts", arg, "Alerts")
    elseif cmd == "sound" then toggle("sound", arg, "Sound")
    elseif cmd == "share" then toggle("shareSightings", arg, "Share sightings")
    elseif cmd == "remote" then toggle("sightingAlerts", arg, "Friends' sighting alerts")
    elseif cmd == "offset" then
        HL.settings.plateOffsetY = tonumber(rest) or 0
        HL:RefreshPlates()
        HL:Print("Nameplate offset: " .. HL.settings.plateOffsetY)
    elseif cmd == "scale" then
        local v = tonumber(rest)
        if v then HL.settings.plateScale = math.min(2, math.max(0.5, v)) end
        HL:RefreshPlates()
        HL:Print("Nameplate scale: " .. HL.settings.plateScale)
    elseif cmd == "wellfed" then
        toggle("wellFedReminder", arg, "Well Fed reminder")
        HL:UpdateWellFed()
    elseif cmd == "campfire" or cmd == "camp" then
        local sub, name = (rest or ""):match("^(%S*)%s*(.-)%s*$")
        sub = (sub or ""):lower()
        if sub == "set" and name ~= "" then
            if not HL:IsCampBuff(name) then HL:ToggleCampBuff(name) end
            HL:Print("Campfire buff: " .. HL:CampBuffText())
        elseif sub == "clear" then
            HL:ClearCampBuffs()
            HL:Print("Campfire buff: " .. HL:CampBuffText())
        else
            toggle("campfireReminder", arg, "Campfire reminder")
            HL:UpdateCampfire()
        end
    elseif cmd == "buffs" then
        HL:PrintBuffs()
    elseif cmd == "minimap" then
        if arg == "on" then HL.settings.minimapHide = false
        elseif arg == "off" then HL.settings.minimapHide = true
        else HL.settings.minimapHide = not HL.settings.minimapHide end
        HL:UpdateMinimapButton()
        HL:Print("Minimap button: " .. (HL.settings.minimapHide and "|cffff4040hidden|r" or "|cff40ff40shown|r"))
    elseif cmd == "export" then
        HL:ShowExport()
    elseif cmd == "import" then
        HL:ShowImport()
    else
        HL:Print("commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end
