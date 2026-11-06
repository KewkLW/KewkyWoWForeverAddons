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

local function Apply()
    local portrait = Portrait()
    if not portrait then return end
    portrait:SetAlpha(db.hidePortrait and 0 or 1)
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
    elseif msg == "where" then
        Where()
        return
    else
        Print("/kcp: toggle portrait, /kcp level: toggle level badge, /kcp where: portrait pixel position for OBS")
        return
    end
    Apply()
end
