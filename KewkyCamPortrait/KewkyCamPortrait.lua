local ADDON_NAME = ...

-- Makes the player frame's portrait see-through so a stream webcam (OBS, circle mask) can sit
-- inside the ring. Only SetAlpha on Blizzard's own textures: no keys written into PlayerFrame,
-- no hooks on its mixins (taint). Alpha survives the game re-setting the portrait texture.

KewkyCamPortraitDB = KewkyCamPortraitDB or {}
local db

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffKewkyCamPortrait|r " .. msg)
end

local function Portrait()
    local c = PlayerFrame and PlayerFrame.PlayerFrameContainer
    return c and c.PlayerPortrait
end

-- level number + its circle sit on the bottom of the ring and would cover the cam
local function LevelParts()
    local main = PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    return PlayerLevelText, main and main.LevelBackgroundCircle
end

-- Key fill: solid magenta in the portrait circle, under the ring. OBS keys the color out of the
-- game capture (Color Key filter) and the cam source placed below the game shows through, so
-- the ring draws over the cam. Our own texture on the container, masked by Blizzard's portrait
-- mask; nothing is stored on the Blizzard frame.
local keyFill
local function KeyFill(portrait)
    if not keyFill then
        keyFill = portrait:GetParent():CreateTexture(nil, "BACKGROUND", nil, 1)
        keyFill:SetAllPoints(portrait)
        keyFill:SetColorTexture(1, 0, 1)
        local mask = PlayerFrame.PlayerFrameContainer.PlayerPortraitMask
        if mask then keyFill:AddMaskTexture(mask) end
    end
    return keyFill
end

local function Apply()
    local portrait = Portrait()
    if not portrait then return end
    portrait:SetAlpha(db.hidePortrait and 0 or 1)
    if db.keyFill and db.hidePortrait then
        KeyFill(portrait):Show()
    elseif keyFill then
        keyFill:Hide()
    end
    local text, circle = LevelParts()
    local levelAlpha = db.hideLevel and 0 or 1
    if text then text:SetAlpha(levelAlpha) end
    if circle then circle:SetAlpha(levelAlpha) end
end

-- screen pixels of the portrait circle, for placing the cam source in OBS
local function Where()
    local portrait = Portrait()
    if not portrait or not portrait:GetLeft() then
        Print("player frame portrait not found")
        return
    end
    -- at effective scale 1 the screen is 768 units tall
    local physW, physH = GetPhysicalScreenSize()
    local px = portrait:GetEffectiveScale() * physH / 768
    local left = portrait:GetLeft() * px
    local top = physH - portrait:GetTop() * px
    local size = portrait:GetWidth() * px
    Print(string.format("portrait at x=%d y=%d, %dx%d px (screen %dx%d, top-left origin)",
        left + 0.5, top + 0.5, size + 0.5, size + 0.5, physW, physH))
end

local function OnOff(v) return v and "|cff20ff20on|r" or "|cff888888off|r" end

-- Minimap button: left-click portrait, right-click key fill, drag around the minimap edge.
local mmButton
local function PlaceButton()
    local rad = math.rad(db.minimapAngle or 200)
    local r = Minimap:GetWidth() / 2 + 5
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("KewkyCamPortrait", 1, 0.82, 0)
    GameTooltip:AddLine("Left-click: hide portrait (" .. OnOff(db.hidePortrait) .. ")", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: magenta key fill (" .. OnOff(db.keyFill) .. ")", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function CreateMinimapButton()
    mmButton = CreateFrame("Button", "KewkyCamPortraitMinimapButton", Minimap)
    mmButton:SetSize(32, 32)
    mmButton:SetFrameStrata("MEDIUM")
    mmButton:SetFrameLevel(8)
    mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmButton:RegisterForDrag("LeftButton")
    mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = mmButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = mmButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    mmButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceButton()
        end)
    end)
    mmButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton:SetScript("OnClick", function(self, btn)
        SlashCmdList.KEWKYCAMPORTRAIT(btn == "RightButton" and "key" or "toggle")
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end)
    mmButton:SetScript("OnEnter", ShowTooltip)
    mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceButton()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_PORTRAIT_UPDATE")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON_NAME then return end
        db = KewkyCamPortraitDB
        if db.hidePortrait == nil then db.hidePortrait = true end
        if db.hideLevel == nil then db.hideLevel = false end
        if db.keyFill == nil then db.keyFill = false end
        CreateMinimapButton()
        return
    end
    if not db then return end
    if event == "UNIT_PORTRAIT_UPDATE" and arg ~= "player" then return end
    Apply()
end)

SLASH_KEWKYCAMPORTRAIT1 = "/kcp"
SlashCmdList.KEWKYCAMPORTRAIT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "toggle" then
        db.hidePortrait = not db.hidePortrait
        Print("portrait " .. (db.hidePortrait and "hidden" or "shown"))
    elseif msg == "level" then
        db.hideLevel = not db.hideLevel
        Print("level badge " .. (db.hideLevel and "hidden" or "shown"))
    elseif msg == "key" then
        db.keyFill = not db.keyFill
        Print("magenta key fill " .. (db.keyFill and "on (OBS Color Key, Custom #FF00FF)" or "off"))
    elseif msg == "where" then
        Where()
        return
    else
        Print("/kcp: toggle portrait, /kcp level: toggle level badge, /kcp key: magenta fill for an OBS cam behind the ring, /kcp where: portrait pixel position for OBS")
        return
    end
    Apply()
end
