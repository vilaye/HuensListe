-- Huens Liste - Font.lua
-- Optional font for the addon's own text: Allo by Josh Puckett (SIL Open Font
-- License, see Fonts/OFL.txt). Off by default; Options tab or /hl font.
--
-- How it works: the addon's text doesn't use Blizzard's font objects (GameFontNormal
-- ...) directly but copies of them made here. Switching the font only changes those
-- copies, and every text that uses them follows right away - no /reload needed.
local ADDON, HL = ...

local PATH = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
local ALLO = PATH .. "Allo-Medium.ttf"
local ALLO_BOLD = PATH .. "Allo-Bold.ttf"
local BOLD_FROM = 16 -- this size and up uses the bold weight

local objects = {} -- [key] = { font = Font object, orig = { file, size, flags }, flags = extra flags }

local function useAllo() return HL.settings and HL.settings.font == "allo" end

local function apply(entry)
    local f, o = entry.font, entry.orig
    local flags = entry.flags or o[3] or ""
    if useAllo() then
        local size = o[2] or 12
        f:SetFont(size >= BOLD_FROM and ALLO_BOLD or ALLO, size, flags)
    elseif o[1] then
        f:SetFont(o[1], o[2] or 12, flags)
    end
end

-- Name of the addon's copy of a Blizzard font object, for CreateFontString /
-- SetFontObject. flags (e.g. "OUTLINE") gives a separate copy with those flags.
function HL.Font(template, flags)
    if type(template) ~= "string" then return template end
    if template:find("^HuensListeFont_") then return template end
    local key = template .. (flags and ("_" .. flags) or "")
    local entry = objects[key]
    if not entry then
        local base = _G[template]
        if type(base) ~= "table" or not base.GetFont then return template end
        local name = "HuensListeFont_" .. key
        local f = CreateFont(name)
        f:CopyFontObject(base)
        entry = { font = f, name = name, orig = { base:GetFont() }, flags = flags }
        objects[key] = entry
        apply(entry)
    end
    return entry.name
end

-- Walks a frame and all its children and moves texts that still use a Blizzard font
-- object (from Blizzard templates: buttons, checkboxes, tabs, edit boxes) onto the
-- addon's copies. Cheap and safe to call again; already moved texts are skipped.
local function swap(obj, getter, setter)
    local ok, fo = pcall(obj[getter], obj)
    if not ok or type(fo) ~= "table" or not fo.GetName then return end
    local name = fo:GetName()
    if not name or name:find("^HuensListeFont_") then return end
    local mine = HL.Font(name)
    if mine ~= name then obj[setter](obj, mine) end
end

function HL:AdoptFonts(frame, depth)
    if type(frame) ~= "table" or (depth or 0) > 12 then return end
    if frame.GetFontObject and frame.SetFontObject then swap(frame, "GetFontObject", "SetFontObject") end
    if frame.GetNormalFontObject and frame.SetNormalFontObject then
        swap(frame, "GetNormalFontObject", "SetNormalFontObject")
        swap(frame, "GetHighlightFontObject", "SetHighlightFontObject")
        swap(frame, "GetDisabledFontObject", "SetDisabledFontObject")
    end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then swap(r, "GetFontObject", "SetFontObject") end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do self:AdoptFonts(c, (depth or 0) + 1) end
    end
end

function HL:SetAddonFont(which)
    self.settings.font = (which == "allo") and "allo" or nil
    for _, entry in pairs(objects) do apply(entry) end
end

function HL:AddonFontName() return useAllo() and "Allo" or "game font" end

HL:On("PLAYER_LOGIN", function()
    -- settings are loaded now: fonts made before this point get the right font
    for _, entry in pairs(objects) do apply(entry) end
end)
