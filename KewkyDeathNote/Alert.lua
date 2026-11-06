local ADDON_NAME, ns = ...

-- Enemy alert: a sound and a banner when a player of the other faction shows up near you.
-- Addons only see players the game has loaded around you: enemy nameplates (about 40-60 yd), your
-- target and mouseover. Someone in your Death Note gets the loud raid-warning sound and a red banner.
-- Off in battlegrounds and arenas. /kdn alert turns it on or off.

local REPEAT_AFTER = 120       -- s before the same player alerts again
local SOUND_GAP = 3            -- s between sounds when several show up at once

local CVARS = {                -- enemy nameplates are what make nearby enemies visible
    nameplateShowEnemies = "1",
    nameplateShowAll = "1",    -- not only in combat
}

local lastAlert = {}
local lastSound = -100
local banner

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Readable(v) return v ~= nil and not IsSecret(v) end

local function Enabled()
    return KewkyDeathNoteDB.alert ~= false
end

local function SetCVars(on)
    KewkyDeathNoteDB.alertSaved = KewkyDeathNoteDB.alertSaved or {}
    local saved = KewkyDeathNoteDB.alertSaved
    for name, value in pairs(CVARS) do
        local cur = C_CVar.GetCVar(name)
        if cur ~= nil then
            if on then
                if saved[name] == nil then saved[name] = cur end
                C_CVar.SetCVar(name, value)
            elseif saved[name] ~= nil then
                C_CVar.SetCVar(name, saved[name])
                saved[name] = nil
            end
        end
    end
end

local function InBattle()
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

-- the player's record in the Death Note, if any
local function NoteEntry(guid)
    local me = UnitGUID("player")
    local chars = KewkyDeathNoteDB.chars
    local db = me and chars and chars[me]
    return db and db.players and db.players[guid]
end

local function BuildBanner()
    banner = CreateFrame("Frame", "KewkyDeathNoteAlert", UIParent)
    banner:SetSize(600, 40)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -190)
    banner:SetFrameStrata("HIGH")
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner.text:SetPoint("CENTER")
    banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banner.sub:SetPoint("TOP", banner.text, "BOTTOM", 0, -4)
    local fade = banner:CreateAnimationGroup()
    local hold = fade:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(3)
    local out = fade:CreateAnimation("Alpha")
    out:SetFromAlpha(1)
    out:SetToAlpha(0)
    out:SetDuration(1.5)
    out:SetStartDelay(3)
    fade:SetScript("OnFinished", function() banner:Hide() end)
    banner.fade = fade
    banner:Hide()
end

local function Show(title, sub, r, g, b)
    if not banner then BuildBanner() end
    banner.text:SetText(title)
    banner.text:SetTextColor(r, g, b)
    banner.sub:SetText(sub)
    banner.fade:Stop()
    banner:SetAlpha(1)
    banner:Show()
    banner.fade:Play()
end

local function Sound(key)
    local id = SOUNDKIT and (SOUNDKIT[key] or SOUNDKIT.RAID_WARNING)
    if id then PlaySound(id, "Master") end
end

local function Check(unit)
    if not Enabled() or InBattle() then return end
    if not (UnitExists(unit) and UnitIsPlayer(unit)) then return end
    local faction, mine = UnitFactionGroup(unit), UnitFactionGroup("player")
    if not (Readable(faction) and Readable(mine)) or faction == mine or faction == "Neutral" then return end
    local guid = UnitGUID(unit)
    if not Readable(guid) then return end
    local now = GetTime()
    if lastAlert[guid] and now - lastAlert[guid] < REPEAT_AFTER then
        lastAlert[guid] = now          -- still around: keep it quiet
        return
    end
    lastAlert[guid] = now

    local name, surname = UnitName(unit)
    if not Readable(name) then return end
    if Readable(surname) and surname ~= "" then name = name .. " " .. surname end
    local level = UnitLevel(unit)
    level = (Readable(level) and level > 0) and tostring(level) or "??"
    local race = UnitRace(unit)
    local classLocal, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local cname = color and ("|c" .. color.colorStr .. name .. "|r") or name
    local what = string.format("%s %s %s", level, Readable(race) and race or "", Readable(classLocal) and classLocal or "")

    local note = NoteEntry(guid)
    if note then
        local k, d = #note.kills, #note.deaths
        Show("DEATH NOTE: " .. name, string.format("%s  ·  you %d, them %d", what, k, d), 1, 0.15, 0.15)
        if now - lastSound > SOUND_GAP then Sound("RAID_WARNING") end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffcc3333Death Note|r %s (%s) is near you. You %d, them %d.", cname, what, k, d))
    else
        Show(faction .. " nearby: " .. name, what, 1, 0.55, 0.1)
        if now - lastSound > SOUND_GAP then Sound("UI_RAID_BOSS_WHISPER_WARNING") end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffcc3333Death Note|r %s nearby: %s (%s)", faction, cname, what))
    end
    lastSound = now
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        KewkyDeathNoteDB = KewkyDeathNoteDB or {}
        if Enabled() then SetCVars(true) end
        f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Check(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Check("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Check("mouseover")
    end
end)

-- /kdn alert, from KewkyDeathNote's slash command
ns.ToggleAlert = function()
    KewkyDeathNoteDB.alert = not Enabled()
    SetCVars(Enabled())
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333Death Note|r enemy alert " ..
        (Enabled() and "on (enemy nameplates turned on so nearby enemies can be seen)" or "off; your nameplate settings are back"))
end
