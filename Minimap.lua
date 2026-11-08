-- Huens Liste: minimap button (no libraries needed) + addon compartment entry
local _, HL = ...
local button

local function updatePosition()
    local angle = math.rad(HL.settings.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    HL.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    updatePosition()
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffcc2222Huens Liste|r")
    GameTooltip:AddLine(HL:Count("kos") .. " on the KOS List, " .. HL:Count("avoid") .. " on the Swine List", 1, 1, 1)
    if HL.newerVersion then
        GameTooltip:AddLine("Update available: " .. HL.newerVersion .. " (you have " .. HL.VERSION .. ")", 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffff00Left-click|r open list", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffff00Right-click|r sync with friends", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffff00Drag|r move button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function onClick(btn)
    if btn == "RightButton" then
        HL:SendHello()
        HL:Print("Sync requested.")
    else
        HL:ToggleMain()
    end
end

local function createButton()
    button = CreateFrame("Button", "HuensListeMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, btn) onClick(btn) end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", onDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function HL:UpdateMinimapButton()
    if not Minimap then return end
    if not button then createButton() end
    if self.settings.minimapHide then
        button:Hide()
    else
        updatePosition()
        button:Show()
    end
end

HL:On("PLAYER_LOGIN", function()
    if HL.settings.minimapHide == nil then HL.settings.minimapHide = false end
    if HL.settings.minimapAngle == nil then HL.settings.minimapAngle = 200 end
    HL:UpdateMinimapButton()
end)

-- Addon compartment (the addon menu button on the minimap), referenced from the .toc
function HuensListe_OnAddonCompartmentClick(_, btn)
    onClick(btn)
end

function HuensListe_OnAddonCompartmentEnter(_, menuButton)
    showTooltip(menuButton)
end

function HuensListe_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
