-- Huens Liste - Map.lua
-- Friends on the world map. Both parts are opt-in (Quality of Life tab):
--   Share my location: sends zone + position every 30 s while you move
--   Show friends on the map: draws a pin for everyone who shares theirs
-- Message: O;mapID;x;y;CLASS  (x, y = 0..10000)   /   O;0 = not available any more
local ADDON, HL = ...
local RS = HL.RS

local CHECK_EVERY = 5      -- seconds between looks at our own position
local SEND_EVERY = 30      -- at most one update per this many seconds while moving
local KEEPALIVE = 120      -- one update per this many seconds while standing still
local EXPIRE = 300         -- forget a friend after this long without an update
local MOVED = 50           -- of 10000: smaller moves are not worth a message

HL.friendLocs = {}         -- [senderId] = { map, x, y, class, t }

---------------------------------------------------------------------------
-- Own position
---------------------------------------------------------------------------
-- mapID, x, y (0..10000); nil where the game gives none (dungeons, raids, battlegrounds)
function HL:MyMapPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID or HL.IsSecret(mapID) then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos or HL.IsSecret(pos) then return nil end
    local ok3, x, y = pcall(pos.GetXY, pos)
    if not ok3 or not x or not y or HL.IsSecret(x) or HL.IsSecret(y) then return nil end
    if x <= 0 and y <= 0 then return nil end
    return mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)
end

local last = { map = nil, x = 0, y = 0, t = 0, gone = true }

local function sendGone()
    if last.gone then return end
    last.gone = true
    last.map = nil
    HL:Broadcast("O" .. RS .. "0", "low")
end

local function shareTick(force)
    if not HL.settings or not HL.me then return end
    if not HL.settings.shareLocation then sendGone() return end
    local mapID, x, y = HL:MyMapPosition()
    if not mapID then sendGone() return end

    local now = GetTime()
    local age = now - last.t
    local newMap = last.map ~= mapID
    local moved = newMap or math.abs(x - last.x) + math.abs(y - last.y) >= MOVED
    local due = force or last.gone
        or (newMap and age >= CHECK_EVERY)
        or (moved and age >= SEND_EVERY)
        or age >= KEEPALIVE
    if not due then return end

    last.map, last.x, last.y, last.t, last.gone = mapID, x, y, now, false
    local okC, _, classFile = pcall(UnitClass, "player")
    if not okC or HL.IsSecret(classFile) or type(classFile) ~= "string" then classFile = "" end
    HL:Broadcast(table.concat({ "O", mapID, x, y, classFile }, RS), "low")
end

function HL:UpdateLocationSharing() shareTick(true) end

---------------------------------------------------------------------------
-- Friends' positions
---------------------------------------------------------------------------
function HL:OnPeerLocation(sender, mapID, x, y, classFile)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not sender then return end
    if not mapID or mapID == 0 or not x or not y then
        HL.friendLocs[sender] = nil
    else
        if x < 0 or x > 10000 or y < 0 or y > 10000 then return end
        HL.friendLocs[sender] = { map = mapID, x = x / 10000, y = y / 10000,
            class = (type(classFile) == "string" and classFile ~= "") and classFile or nil, t = GetTime() }
    end
    if HL.RefreshMapPins then HL:RefreshMapPins() end
end

local function zoneName(mapID)
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
    end
    return "map " .. tostring(mapID)
end

local function ageText(t)
    local s = math.max(0, math.floor(GetTime() - t))
    if s < 60 then return s .. " s ago" end
    return math.floor(s / 60) .. " min ago"
end

local function classColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 0.3, 1, 0.3
end

-- Sorted list of friends with a fresh position
function HL:FriendLocations()
    local list, now = {}, GetTime()
    for id, loc in pairs(HL.friendLocs) do
        if now - loc.t > EXPIRE then
            HL.friendLocs[id] = nil
        else
            list[#list + 1] = { id = id, name = HL.ShortName(id), loc = loc }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- /hl where
function HL:PrintFriendLocations()
    local list = self:FriendLocations()
    if #list == 0 then
        self:Print("Nobody is sharing a location right now.")
        return
    end
    self:Print("Friends:")
    for _, f in ipairs(list) do
        print(("  %s – %s (%.0f, %.0f), %s"):format(f.name, zoneName(f.loc.map), f.loc.x * 100, f.loc.y * 100,
            ageText(f.loc.t)))
    end
end

---------------------------------------------------------------------------
-- Pins on the world map
---------------------------------------------------------------------------
local pins, watcher = {}, nil

-- Where a position on map `from` lies on map `to` (0..1), or nil if it isn't on it
local function translate(from, x, y, to)
    if from == to then return x, y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, from, CreateVector2D(x, y))
    if not ok or not continent or not world then return nil end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, to)
    if not ok2 or not pos then return nil end
    local ok3, tx, ty = pcall(pos.GetXY, pos)
    if not ok3 or not tx or not ty then return nil end
    if tx < 0 or tx > 1 or ty < 0 or ty > 1 then return nil end
    return tx, ty
end

local function getPin(i, canvas)
    local pin = pins[i]
    if pin then return pin end
    pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(14, 14)
    pin:SetFrameStrata("HIGH")
    pin:EnableMouse(true)
    pin.dot = pin:CreateTexture(nil, "OVERLAY")
    pin.dot:SetAllPoints()
    pin.dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.label:SetPoint("LEFT", pin, "RIGHT", 1, 0)
    local font, size = pin.label:GetFont()
    if font then pin.label:SetFont(font, size or 10, "OUTLINE") end
    pin:SetScript("OnEnter", function(self)
        if not self.friend then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.friend.name, classColor(self.friend.loc.class))
        GameTooltip:AddLine(zoneName(self.friend.loc.map), 1, 1, 1)
        GameTooltip:AddLine("Updated " .. ageText(self.friend.loc.t), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[i] = pin
    return pin
end

function HL:RefreshMapPins()
    local map = WorldMapFrame
    local used = 0
    if map and map:IsShown() and HL.settings and HL.settings.showFriendsOnMap and map.GetMapID and map.GetCanvas then
        local okM, shownMap = pcall(map.GetMapID, map)
        local canvas = map:GetCanvas()
        if okM and shownMap and canvas then
            local w, h = canvas:GetWidth(), canvas:GetHeight()
            -- keep the pins the same size on screen, however far the map is zoomed
            local canvasScale, uiScale = canvas:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local k = (canvasScale and canvasScale > 0) and (uiScale / canvasScale) or 1
            for _, f in ipairs(self:FriendLocations()) do
                local x, y = translate(f.loc.map, f.loc.x, f.loc.y, shownMap)
                if x then
                    used = used + 1
                    local pin = getPin(used, canvas)
                    pin.friend = f
                    pin:SetScale(k)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", x * w / k, -y * h / k)
                    pin.dot:SetVertexColor(classColor(f.loc.class))
                    pin.label:SetText(f.name:match("^(%S+)") or f.name)
                    pin.label:SetTextColor(classColor(f.loc.class))
                    pin:Show()
                end
            end
        end
    end
    for i = used + 1, #pins do pins[i]:Hide() end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
HL:On("PLAYER_LOGIN", function()
    C_Timer.NewTicker(CHECK_EVERY, function() shareTick(false) end)

    -- While the world map is open, keep the pins in place (zoom, map changes, new updates)
    if WorldMapFrame then
        watcher = CreateFrame("Frame", nil, WorldMapFrame)
        local acc = 0
        watcher:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc < 0.5 then return end
            acc = 0
            HL:RefreshMapPins()
        end)
        watcher:SetScript("OnShow", function() HL:RefreshMapPins() end)
    end
end)

HL:On("ZONE_CHANGED_NEW_AREA", function() shareTick(false) end)
