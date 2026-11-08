-- Huens Liste: list window, export/import, right-click menu, slash commands
local _, HL = ...

---------------------------------------------------------------------------
-- "Add with reason" popup
---------------------------------------------------------------------------
local function popupEditBox(p) return p.editBox or p.EditBox or (p.GetEditBox and p:GetEditBox()) end

StaticPopupDialogs["HUENSLISTE_ADD"] = {
    text = "Put |cffff4040%s|r on Huens Liste?\nReason (optional):",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 80,
    OnAccept = function(self, data)
        local eb = popupEditBox(self)
        HL:Add(data, eb and eb:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        HL:Add(p.data, self:GetText())
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function HL:PromptAdd(full)
    full = HL.NormalizeName(full)
    if full then StaticPopup_Show("HUENSLISTE_ADD", HL.ShortName(full), nil, full) end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local ROW_H = 22
local main, content
local rows = {}

local function makeFS(parent, x, w, font)
    local f = parent:CreateFontString(nil, "OVERLAY", font)
    f:SetPoint("LEFT", x, 0)
    f:SetWidth(w)
    f:SetJustifyH("LEFT")
    f:SetWordWrap(false)
    return f
end

local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(540, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
    r.name = makeFS(r, 4, 130, "GameFontNormal")
    r.name:SetTextColor(1, 0.3, 0.3)
    r.reason = makeFS(r, 140, 190, "GameFontHighlightSmall")
    r.by = makeFS(r, 336, 90, "GameFontDisableSmall")
    r.seen = makeFS(r, 430, 85, "GameFontDisableSmall")
    r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
    r.del:SetSize(20, 20)
    r.del:SetPoint("RIGHT", -2, 0)
    r.del:SetScript("OnClick", function(self) HL:Remove(self:GetParent().full) end)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local e, s = self.entry, self.seenData
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.n, 1, 0.3, 0.3)
        if e.r ~= "" then GameTooltip:AddLine(e.r, 1, 1, 1, true) end
        GameTooltip:AddLine("Added by " .. Ambiguate(e.b ~= "" and e.b or "?", "short") .. " on " .. date("%d.%m.%Y %H:%M", e.t), 0.7, 0.7, 0.7)
        if s then
            GameTooltip:AddLine("Last seen " .. HL.Ago(s.t) .. " in " .. (s.z or "?")
                .. ((s.s and s.s ~= "" and s.s ~= s.z) and (" – " .. s.s) or "")
                .. " by " .. Ambiguate(s.by or "?", "short"), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

function HL:RefreshList()
    if not main or not main:IsShown() then return end
    local list = {}
    for _, e in pairs(self.db.entries) do
        if not e.d then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i, e in ipairs(list) do
        local r = getRow(i)
        local s = self.db.seen[HL.Key(e.n)]
        r.full, r.entry, r.seenData = e.n, e, s
        r.name:SetText(HL.ShortName(e.n))
        r.reason:SetText(e.r)
        r.by:SetText(Ambiguate(e.b ~= "" and e.b or "?", "short"))
        r.seen:SetText(s and HL.Ago(s.t) or "-")
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * ROW_H))
    main.count:SetText(#list .. " on the list")
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
    r.name = makeFS(r, 20, 200, "GameFontHighlight")
    r.version = makeFS(r, 230, 130, "GameFontHighlightSmall")
    r.status = makeFS(r, 365, 100, "GameFontDisableSmall")
    r.via = makeFS(r, 470, 70, "GameFontDisableSmall")
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

    local online, outdated = 0, 0
    for i, p in ipairs(list) do
        local r = getUserRow(i)
        local isOnline = p.me or (now - (p.t or 0) < ONLINE_WINDOW)
        if isOnline then online = online + 1 end
        r.dot:SetColorTexture(isOnline and 0.2 or 0.4, isOnline and 0.9 or 0.4, isOnline and 0.2 or 0.4, 1)
        r.name:SetText(Ambiguate(p.n or "?", "short") .. (p.me and " |cff888888(you)|r" or ""))
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
    desc:SetText("Everyone who synced with you in the last 30 days. Players on 1.3.0 or older only show up with their periodic sync (every 5 minutes).")

    local headers = { { "Name", 26 }, { "Version", 236 }, { "Status", 371 }, { "Via", 476 } }
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

    -- Well Fed reminder
    local section = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    section:SetPoint("TOPLEFT", 20, -72)
    section:SetText("Well Fed reminder")

    makeCheck(page, "Show a reminder when I'm not Well Fed", "wellFedReminder", { "TOPLEFT", 16, -90 },
        function() HL:UpdateWellFed() end)

    local desc = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", 44, -116)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText("Shows \"You are not Well Fed!\" on screen while you have no food buff. Hidden while you are dead.")

    local moveBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    moveBtn:SetSize(120, 22)
    moveBtn:SetPoint("TOPLEFT", 44, -138)
    local function refreshMoveText()
        moveBtn:SetText(HL:IsWellFedUnlocked() and "Lock position" or "Move reminder")
    end
    moveBtn:SetScript("OnClick", function()
        HL:SetWellFedUnlocked(not HL:IsWellFedUnlocked())
        refreshMoveText()
    end)

    local resetBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 22)
    resetBtn:SetPoint("LEFT", moveBtn, "RIGHT", 8, 0)
    resetBtn:SetText("Reset position")
    resetBtn:SetScript("OnClick", function() HL:ResetWellFedPosition() end)

    page:SetScript("OnShow", refreshMoveText)
    -- Leaving the window locks the reminder again
    page:SetScript("OnHide", function()
        if HL:IsWellFedUnlocked() then HL:SetWellFedUnlocked(false) end
    end)
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

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("|cffcc2222Huens Liste|r – Kill on Sight")

    -- Tab 1: KOS list
    local kos = CreateFrame("Frame", nil, main)
    kos:SetAllPoints()

    main.count = kos:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    main.count:SetPoint("TOPRIGHT", -16, -32)

    local l1 = kos:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l1:SetPoint("TOPLEFT", 20, -32)
    l1:SetText("Full name (First Last)")
    local l2 = kos:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l2:SetPoint("TOPLEFT", 182, -32)
    l2:SetText("Reason")

    local nameBox = CreateFrame("EditBox", nil, kos, "InputBoxTemplate")
    nameBox:SetSize(150, 20)
    nameBox:SetPoint("TOPLEFT", 22, -46)
    nameBox:SetAutoFocus(false)

    local reasonBox = CreateFrame("EditBox", nil, kos, "InputBoxTemplate")
    reasonBox:SetSize(220, 20)
    reasonBox:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
    reasonBox:SetAutoFocus(false)
    reasonBox:SetMaxLetters(80)

    local addBtn = CreateFrame("Button", nil, kos, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", reasonBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local n = strtrim(nameBox:GetText() or "")
        if n == "" then HL:Print("Enter a name first.") return end
        HL:Add(n, reasonBox:GetText())
        nameBox:SetText(""); reasonBox:SetText("")
        nameBox:ClearFocus(); reasonBox:ClearFocus()
    end)

    local tgtBtn = CreateFrame("Button", nil, kos, "UIPanelButtonTemplate")
    tgtBtn:SetSize(90, 22)
    tgtBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    tgtBtn:SetText("Add Target")
    tgtBtn:SetScript("OnClick", function()
        local full = HL.UnitFullName("target")
        if not full then HL:Print("Target a player first.") return end
        HL:Add(full, reasonBox:GetText())
        reasonBox:SetText(""); reasonBox:ClearFocus()
    end)

    nameBox:SetScript("OnEnterPressed", function() reasonBox:SetFocus() end)
    reasonBox:SetScript("OnEnterPressed", function() addBtn:Click() end)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)
    reasonBox:SetScript("OnEscapePressed", reasonBox.ClearFocus)

    local headers = { { "Name", 16 }, { "Reason", 152 }, { "Added by", 348 }, { "Last seen", 442 } }
    for _, h in ipairs(headers) do
        local fs = kos:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h[2], -78)
        fs:SetText(h[1])
    end

    local scroll = CreateFrame("ScrollFrame", nil, kos, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -94)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 1)
    scroll:SetScrollChild(content)

    makeCheck(kos, "Alerts", "alerts", { "BOTTOMLEFT", 14, 12 })
    makeCheck(kos, "Sound", "sound", { "BOTTOMLEFT", 104, 12 })
    makeCheck(kos, "Share sightings", "shareSightings", { "BOTTOMLEFT", 190, 12 })

    local function bottomBtn(text, x, fn)
        local b = CreateFrame("Button", nil, kos, "UIPanelButtonTemplate")
        b:SetSize(72, 22)
        b:SetPoint("BOTTOMRIGHT", x, 12)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    bottomBtn("Sync", -12, function() HL:SendHello(); HL:Print("Sync requested.") end)
    bottomBtn("Export", -88, function() HL:ShowExport() end)
    bottomBtn("Import", -164, function() HL:ShowImport() end)

    -- Tab 2: Quality of Life, Tab 3: Users
    local qol = HL:BuildQoLPage(main)
    local users = HL:BuildUsersPage(main)

    -- Tabs below the window
    local pages = { kos, qol, users }
    local labels = { "KOS List", "Quality of Life", "Users" }
    main.tabs = {}
    local function selectTab(id)
        for i, page in ipairs(pages) do page:SetShown(i == id) end
        if PanelTemplates_SetTab then PanelTemplates_SetTab(main, id) end
        main.selectedTab = id
    end
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

function HL:ShowExport()
    if not ioFrame then createIO() end
    ioFrame.title:SetText("Export – press Ctrl+C to copy")
    ioFrame.btn:Hide()
    ioFrame:Show()
    ioFrame.eb:SetText(self:ExportString())
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
        root:CreateDivider()
        root:CreateTitle("Huens Liste")
        if HL:Get(full) then
            root:CreateButton("Remove from Huens Liste", function() HL:Remove(full) end)
        else
            root:CreateButton("|cffff4040Add to Huens Liste (KOS)|r", function() HL:PromptAdd(full) end)
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
    "|cffffff00/hl add Firstname Lastname [reason]|r – add a player",
    "|cffffff00/hl target [reason]|r – add your current target",
    "|cffffff00/hl del Firstname Lastname|r – remove (no name = target)",
    "|cffffff00/hl debug|r – print sync traffic in chat (for troubleshooting)",
    "|cffffff00/hl list|r – print the list",
    "|cffffff00/hl sync|r – sync with friends now",
    "|cffffff00/hl channel <name> [password]|r – private sync channel for friends outside your guild (|cffffff00/hl channel off|r)",
    "|cffffff00/hl guild, group, alerts, sound, share, remote [on/off]|r – toggles",
    "|cffffff00/hl offset <pixels>|r / |cffffff00/hl scale <0.5-2>|r – move/resize the nameplate skull",
    "|cffffff00/hl minimap [on/off]|r – show/hide the minimap button",
    "|cffffff00/hl wellfed [on/off]|r – Well Fed reminder (move it in the Quality of Life tab)",
    "|cffffff00/hl buffs|r – list your buffs (troubleshooting for the Well Fed check)",
    "|cffffff00/hl export|r / |cffffff00/hl import|r – share via copy & paste",
}

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
    elseif cmd == "add" then
        local name, reason
        if HL.IsRealmless() then
            name, reason = rest:match("^(%S+%s+%S+)%s*(.-)$")
            if not name then HL:Print("Usage: /hl add Firstname Lastname [reason]") return end
        else
            name, reason = rest:match("^(%S+)%s*(.-)$")
            if not name then HL:Print("Usage: /hl add Name[-Realm] [reason]") return end
        end
        HL:Add(name, reason)
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
        HL:Add(full, rest)
    elseif cmd == "del" or cmd == "remove" or cmd == "rm" then
        local who = rest ~= "" and rest or HL.UnitFullName("target")
        if not who then HL:Print("Usage: /hl del Name[-Realm]") return end
        HL:Remove(who)
    elseif cmd == "list" then
        local n = 0
        for _, e in pairs(HL.db.entries) do
            if not e.d then
                n = n + 1
                print(("  |cffff4040%s|r %s |cff888888(%s)|r"):format(HL.ShortName(e.n), e.r, Ambiguate(e.b, "short")))
            end
        end
        HL:Print(n .. " players on the list.")
    elseif cmd == "sync" then
        HL:SendHello()
        HL:Print("Sync requested.")
    elseif cmd == "channel" then
        local name, pw = rest:match("^(%S*)%s*(%S*)$")
        if not name or name == "" then
            HL:Print("Sync channel: " .. (HL.settings.channel ~= "" and HL.settings.channel or "none"))
        elseif name:lower() == "off" then
            HL:LeaveSyncChannel(HL.settings.channel)
            HL.settings.channel, HL.settings.channelPassword = "", ""
            HL:Print("Sync channel disabled.")
        else
            HL:LeaveSyncChannel(HL.settings.channel)
            HL.settings.channel, HL.settings.channelPassword = name, pw or ""
            HL:JoinSyncChannel()
            HL:ScheduleHello(5)
            HL:Print("Syncing via channel |cffffff00" .. name .. "|r. Your friends need the same name and password.")
        end
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
