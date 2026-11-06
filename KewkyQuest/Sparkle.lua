local ADDON_NAME, ns = ...

-- Quest objects sparkle. The game's soft-interact targeting picks the interactable object in front of
-- you and draws its own outline and icon on it; when that object (or a lootable corpse) is one of your
-- open quest objectives, a gold sparkle plays on it and its name flashes on screen.
--
-- Addons can't draw on world objects, so the sparkle hangs on the object's soft-interact nameplate
-- (SoftTargetNameplateInteract); without a nameplate it shows on screen instead. Objects are matched
-- by name against the open objectives in ObjectiveDB ("Use <object>", "<item>: <source>").
-- /kq sparkle turns it on or off; off restores your own soft-target settings.

-- what the gamepad mode sets, plus the nameplate the sparkle rides on
local CVARS = {
    SoftTargetInteract = "3",            -- always, not just with a gamepad
    SoftTargetInteractRange = "20",
    SoftTargetInteractArc = "2",         -- all around you, not just in front
    SoftTargetIconGameObject = "1",
    SoftTargetIconInteract = "1",
    SoftTargetNameplateInteract = "1",
}

local wanted = {}          -- lower-case object/source name -> label of the open objective
local sparkle, banner
local current, lastSound

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Enabled()
    return KewkyQuestSV and KewkyQuestSV.sparkle ~= false
end

local function SetCVars(on)
    KewkyQuestSV.sparkleSaved = KewkyQuestSV.sparkleSaved or {}
    local saved = KewkyQuestSV.sparkleSaved
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

-- names of every object or source still needed by a quest in the log
local liveNames = {}        -- lower-case objective name from the quest log -> label

-- "1/6 Dry Branch" -> "Dry Branch"; nil for kill objectives
local function ObjectiveName(o)
    if o.finished or not o.text or o.type == "monster" or o.type == "event" then return nil end
    local name = o.text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "")
    if name == "" or name:find(" slain$") then return nil end
    return name
end

local function Rebuild()
    wipe(wanted)
    wipe(liveNames)
    if not ns.QuestLogInfo then return end
    for questID in pairs(ns.QuestLogInfo()) do
        if not ns.IsReadyForTurnIn(questID) then
            local rows = ns.Objectives and ns.Objectives[questID]
            for _, row in ipairs(rows and ns.OpenObjectiveRows(questID, rows) or {}) do
                local label = row[1]
                local name = label:match("^Use (.+)$") or label:match("^[^:]+: (.+)$")
                if name then wanted[name:lower()] = label end
            end
            local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
            for _, o in ipairs(objs or {}) do
                local name = ObjectiveName(o)
                if name then liveNames[name:lower()] = o.text end
            end
        end
    end
end

-- an object counts when its name is a wanted source, or contains / is contained in a log objective's
-- name ("Dry Branch" object for "1/6 Dry Branch", "Pile of Dry Branches" too)
local function Match(name)
    local low = name:lower()
    if wanted[low] then return wanted[low] end
    for objName, text in pairs(liveNames) do
        if #objName >= 4 and #low >= 4 and (low:find(objName, 1, true) or objName:find(low, 1, true)) then return text end
    end
    return nil
end

local function BuildSparkle()
    sparkle = CreateFrame("Frame", "KewkyQuestSparkle", UIParent)
    sparkle:SetSize(72, 72)
    sparkle:SetFrameStrata("HIGH")
    sparkle:Hide()

    local function Star(size, alpha)
        local t = sparkle:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Cooldown\\star4")
        t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.85, 0.3, alpha)
        t:SetSize(size, size)
        t:SetPoint("CENTER")
        return t
    end
    local big, small = Star(72, 0.9), Star(40, 1)

    local spin = sparkle:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local r = spin:CreateAnimation("Rotation")
    r:SetTarget(big)
    r:SetDegrees(-360)
    r:SetDuration(4)
    local pulse = sparkle:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetTarget(small)
    a:SetFromAlpha(1)
    a:SetToAlpha(0.3)
    a:SetDuration(0.6)
    sparkle.spin, sparkle.pulse = spin, pulse

    banner = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    banner:SetPoint("TOP", UIParent, "TOP", 0, -150)
    banner:SetTextColor(1, 0.85, 0.3)
    banner:Hide()
end

local function Stop()
    current, lastSound = nil, nil
    if not sparkle then return end
    sparkle.spin:Stop()
    sparkle.pulse:Stop()
    sparkle:Hide()
    banner:Hide()
end

local function Start(label, name)
    if not sparkle then BuildSparkle() end
    current = name
    sparkle:ClearAllPoints()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("softinteract")
    if plate and not IsSecret(plate) then
        sparkle:SetPoint("BOTTOM", plate, "TOP", 0, -8)
    else
        sparkle:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
    sparkle:Show()
    sparkle.spin:Play()
    sparkle.pulse:Play()
    banner:SetText(label)
    banner:Show()
    if name ~= lastSound and SOUNDKIT and SOUNDKIT.MAP_PING then PlaySound(SOUNDKIT.MAP_PING) end
    lastSound = name
end

local function Check()
    if not Enabled() or not UnitExists("softinteract") then return Stop() end
    local name = UnitName("softinteract")
    if not name or IsSecret(name) then return Stop() end
    local label = Match(name)
    if not label then return Stop() end
    if name ~= current then Start(label, name) end
end

ns.ToggleSparkle = function()
    KewkyQuestSV.sparkle = not Enabled()
    SetCVars(Enabled())
    if Enabled() then
        Rebuild()
        print("|cff55ccffKewkyQuest|r quest object sparkle on: soft targeting now picks the nearest object around you (20 yd).")
    else
        Stop()
        print("|cff55ccffKewkyQuest|r quest object sparkle off; your soft-target settings are back.")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
local rebuildPending = false
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if Enabled() then SetCVars(true) end
        C_Timer.After(2, Rebuild)
    elseif event == "QUEST_LOG_UPDATE" then
        if rebuildPending then return end
        rebuildPending = true
        C_Timer.After(0.5, function()
            rebuildPending = false
            Rebuild()
            current = nil
            Check()
        end)
    else
        -- the target changed, or its nameplate just appeared: re-anchor (the sound only plays for a new object)
        current = nil
        Check()
    end
end)
