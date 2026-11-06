local ADDON_NAME = ...

-- Death Note: every enemy player who killed you, and every player you killed or helped kill,
-- with their level and yours at the time. A red glow and the K/D go on your target frame
-- when you target someone in the note.
--
-- Sources (the combat log is restricted on Forever):
--   kills    PARTY_KILL with you (or your pet) as the attacker and a player as the victim
--   assists  PARTY_KILL by a group member, confirmed after combat from the damage meter's
--            per-target breakdown of your damage (only readable out of combat)
--   deaths   the death recap's killing blow, matched by name to players seen recently
-- Levels come from players seen on target, mouseover and nameplates.

KewkyDeathNoteDB = KewkyDeathNoteDB or {}

local SEEN_TTL = 3600          -- forget seen players after an hour
local KILLER_WINDOW = 300      -- a killer must have been seen in the last 5 minutes
local ASSIST_WINDOW = 20       -- fallback: victim was your target this recently
local PENDING_TTL = 600

local myGUID, db
local seen, seenByName = {}, {}
local lastTargeted = {}
local pendingAssists = {}
local lastDeathAt = -100
local recentKills = {}
local expanded = {}
local frame, glow

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333Death Note|r " .. msg)
end

local function Debug(msg)
    if KewkyDeathNoteDB.debug then Print("|cff999999" .. msg .. "|r") end
end

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Readable(v) return v ~= nil and not IsSecret(v) end

-- ── names and seen players ──

local function FullName(name, surname)
    if surname and surname ~= "" then return name .. " " .. surname end
    return name
end

-- "Name Surname" / "Name-Surname" / "Name" -> full key, first-name key
local function NameKeys(s)
    s = s:gsub("%-", " "):lower()
    return s, s:match("^(%S+)") or s
end

local function NamesMatch(a, b)
    if not (a and b) then return false end
    local af, a1 = NameKeys(a)
    local bf, b1 = NameKeys(b)
    return af == bf or a1 == b1
end

local function Remember(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not Readable(guid) or guid == myGUID then return end
    local name, surname = UnitName(unit)
    if not Readable(name) then return end
    if IsSecret(surname) then surname = nil end
    local _, class = UnitClass(unit)
    local level = UnitLevel(unit)

    local s = seen[guid] or {}
    s.name = FullName(name, surname)
    if Readable(class) then s.class = class end
    if Readable(level) then s.level = level end
    s.t = GetTime()
    seen[guid] = s

    local full, first = NameKeys(s.name)
    seenByName[full] = guid
    seenByName[first] = guid
end

local function Prune()
    local now = GetTime()
    for guid, s in pairs(seen) do
        if now - s.t > SEEN_TTL then seen[guid] = nil end
    end
    for key, guid in pairs(seenByName) do
        if not seen[guid] then seenByName[key] = nil end
    end
end

local SCAN_UNITS = { "target", "mouseover", "focus" }
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "nameplate" .. i end

-- name, class and current level for a player GUID
local function Info(guid)
    for _, unit in ipairs(SCAN_UNITS) do
        if UnitExists(unit) then
            local g = UnitGUID(unit)
            if Readable(g) and g == guid then Remember(unit) break end
        end
    end
    local s = seen[guid]
    local info = { name = s and s.name, class = s and s.class, level = s and s.level }
    if not (info.name and info.class) and GetPlayerInfoByGUID then
        local ok, _, class, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok and Readable(name) and name ~= "" then
            info.name = info.name or FullName(name, Readable(realm) and realm or nil)
            if Readable(class) then info.class = info.class or class end
        end
    end
    return info
end

local function InGroup(guid)
    local prefix, n = "party", 4
    if IsInRaid() then prefix, n = "raid", 40 end
    for i = 1, n do
        local g = UnitGUID(prefix .. i)
        if Readable(g) and g == guid then return true end
    end
    return false
end

local function IsPlayerGUID(guid)
    return Readable(guid) and guid:match("^Player%-") ~= nil
end

-- ── the note ──

local RefreshUI, UpdateGlow

local function LevelText(level)
    if level == nil then return "?" end
    if level < 0 then return "??" end
    return tostring(level)
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr and ("|c" .. c.colorStr) or "|cffffffff"
end

local function ClassName(class)
    return class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class or "Unknown"
end

local function Counts(p)
    return #p.kills, #p.assists, #p.deaths
end

local function KD(kills, deaths)
    return string.format("%.2f", kills / math.max(deaths, 1))
end

local KIND_TEXT = { kills = "You killed them", assists = "Assist", deaths = "Killed you" }

local function Record(guid, kind, info, via)
    local p = db.players[guid]
    if not p then
        p = { kills = {}, assists = {}, deaths = {} }
        db.players[guid] = p
    end
    p.name = info.name or p.name or "Unknown"
    p.class = info.class or p.class
    local entry = {
        t = time(),
        theirs = info.level,
        mine = UnitLevel("player"),
        zone = GetRealZoneText and GetRealZoneText() or nil,
        via = via,
    }
    table.insert(p[kind], entry)
    p.last = entry.t

    local k, a, d = Counts(p)
    Print(string.format("%s: %s%s|r (level %s, you %s). K %d  A %d  D %d",
        KIND_TEXT[kind], ClassColor(p.class), p.name, LevelText(entry.theirs), LevelText(entry.mine), k, a, d))
    if RefreshUI then RefreshUI() end
    if UpdateGlow then UpdateGlow() end
end

-- ── kills, assists, deaths ──

local function RecordDeath(killerGUID)
    if GetTime() - lastDeathAt < 5 then return end
    lastDeathAt = GetTime()
    Record(killerGUID, "deaths", Info(killerGUID), "recap")
end

local function OnPartyKill(attackerGUID, targetGUID)
    if not (Readable(attackerGUID) and Readable(targetGUID)) then
        Debug("PARTY_KILL with hidden values")
        return
    end
    Debug("PARTY_KILL " .. attackerGUID .. " -> " .. targetGUID)

    if targetGUID == myGUID then
        if IsPlayerGUID(attackerGUID) then RecordDeath(attackerGUID) end
        return
    end
    if not IsPlayerGUID(targetGUID) then return end
    if recentKills[targetGUID] and GetTime() - recentKills[targetGUID] < 3 then return end

    local petGUID = UnitGUID("pet")
    if attackerGUID == myGUID or (Readable(petGUID) and attackerGUID == petGUID) then
        recentKills[targetGUID] = GetTime()
        Record(targetGUID, "kills", Info(targetGUID), "killing blow")
    elseif InGroup(attackerGUID) then
        recentKills[targetGUID] = GetTime()
        local info = Info(targetGUID)
        table.insert(pendingAssists, { guid = targetGUID, info = info, t = GetTime() })
        Debug("pending assist on " .. tostring(info.name))
    end
end

-- true / false from the damage meter, nil when it can't tell
local function DamagedByMe(victimName)
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and Enum and Enum.DamageMeterType) then return nil end
    local okAvail, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
    if okAvail and available == false then
        Debug("damage meter unavailable: " .. tostring(reason))
        return nil
    end

    local sources = {}
    local ok, current = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone, myGUID)
    if ok and current then sources[#sources + 1] = current end
    local okList, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if okList and sessions then
        table.sort(sessions, function(a, b) return a.sessionID > b.sessionID end)
        for i = 1, math.min(2, #sessions) do
            local okS, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
                sessions[i].sessionID, Enum.DamageMeterType.DamageDone, myGUID)
            if okS and src then sources[#sources + 1] = src end
        end
    end
    if #sources == 0 then return nil end

    local names = {}
    for _, src in ipairs(sources) do
        for _, spell in ipairs(src.combatSpells or {}) do
            local d = spell.combatSpellDetails
            local n = d and d.unitName
            if Readable(n) and n ~= "" then
                names[#names + 1] = n
                if NamesMatch(n, victimName) then
                    Debug("meter: you damaged " .. n)
                    return true
                end
            end
        end
    end
    Debug("meter targets: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    return false
end

local function ResolveAssists()
    if #pendingAssists == 0 or InCombatLockdown() then return end
    local now = GetTime()
    local keep = {}
    for _, a in ipairs(pendingAssists) do
        local damaged = a.info.name and DamagedByMe(a.info.name)
        if damaged then
            Record(a.guid, "assists", a.info, "damage meter")
        elseif damaged == nil and lastTargeted[a.guid] and a.t - lastTargeted[a.guid] < ASSIST_WINDOW then
            Record(a.guid, "assists", a.info, "your target")
        elseif damaged == nil and now - a.t < PENDING_TTL then
            Debug("assist on " .. tostring(a.info.name) .. " unconfirmed, checking again after the next fight")
            keep[#keep + 1] = a
        end
    end
    pendingAssists = keep
end

local function ResolveDeath(triesLeft)
    if GetTime() - lastDeathAt < 5 then return end
    if not (C_DeathRecap and C_DeathRecap.HasRecapEvents and C_DeathRecap.HasRecapEvents()) then
        if triesLeft > 0 then C_Timer.After(0.5, function() ResolveDeath(triesLeft - 1) end) end
        return
    end
    local events = C_DeathRecap.GetRecapEvents() or {}
    local blow
    for _, e in ipairs(events) do
        if e.causedDeath then blow = e end
    end
    if not blow then
        for _, e in ipairs(events) do
            if not blow or (Readable(e.timestamp) and Readable(blow.timestamp) and e.timestamp > blow.timestamp) then blow = e end
        end
    end
    local name = blow and not blow.hideCaster and blow.sourceName
    if not Readable(name) or name == "" then
        Debug("death: no killer in the recap")
        return
    end
    local full, first = NameKeys(name)
    local guid = seenByName[full] or seenByName[first]
    local s = guid and seen[guid]
    if s and GetTime() - s.t < KILLER_WINDOW then
        RecordDeath(guid)
    else
        Debug("death: " .. name .. " wasn't a player seen recently")
    end
end

-- ── window ──

local ROW_H, DETAIL_H = 22, 16
local rows = {}

local function FormatTime(t)
    return t and date("%m/%d %H:%M", t) or ""
end

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, frame.content)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.left:SetPoint("LEFT", 4, 0)
    row.left:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self)
        if self.guid then
            expanded[self.guid] = not expanded[self.guid]
            RefreshUI()
        end
    end)
    rows[i] = row
    return row
end

local function SortedPlayers()
    local list = {}
    for guid, p in pairs(db.players) do list[#list + 1] = { guid = guid, p = p } end
    table.sort(list, function(a, b) return (a.p.last or 0) > (b.p.last or 0) end)
    return list
end

local function Events(p)
    local list = {}
    for _, kind in ipairs({ "kills", "assists", "deaths" }) do
        for _, e in ipairs(p[kind]) do list[#list + 1] = { kind = kind, e = e } end
    end
    table.sort(list, function(a, b) return a.e.t > b.e.t end)
    return list
end

RefreshUI = function()
    if not frame or not frame:IsShown() then return end
    local tk, ta, td = 0, 0, 0
    local n, y = 0, 0
    local width = frame.scroll:GetWidth()

    for _, item in ipairs(SortedPlayers()) do
        local p = item.p
        local k, a, d = Counts(p)
        tk, ta, td = tk + k, ta + a, td + d

        n = n + 1
        local row = GetRow(n)
        row.guid = item.guid
        row:SetSize(width, ROW_H)
        row:SetPoint("TOPLEFT", 0, -y)
        row.left:SetFontObject("GameFontHighlight")
        row.left:SetText(string.format("%s %s%s|r  |cff9d9d9d%s|r",
            expanded[item.guid] and "-" or "+", ClassColor(p.class), p.name, ClassName(p.class)))
        row.right:SetText(string.format("K %d  A %d  D %d", k, a, d))
        row:Show()
        y = y + ROW_H

        if expanded[item.guid] then
            for _, ev in ipairs(Events(p)) do
                n = n + 1
                local line = GetRow(n)
                line.guid = item.guid
                line:SetSize(width, DETAIL_H)
                line:SetPoint("TOPLEFT", 0, -y)
                line.left:SetFontObject("GameFontHighlightSmall")
                local color = ev.kind == "deaths" and "|cffff6060" or (ev.kind == "kills" and "|cff60ff60" or "|cffffd060")
                line.left:SetText(string.format("     %s%s|r  them %s, you %s",
                    color, KIND_TEXT[ev.kind], LevelText(ev.e.theirs), LevelText(ev.e.mine)))
                line.right:SetText("|cff9d9d9d" .. (ev.e.zone or "") .. "  " .. FormatTime(ev.e.t) .. "|r")
                line:Show()
                y = y + DETAIL_H
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end

    frame.content:SetSize(width, math.max(y, 1))
    frame.empty:SetShown(n == 0)
    frame.summary:SetText(string.format("Kills %d   Assists %d   Deaths %d   K/D %s", tk, ta, td, KD(tk, td)))
end

local function BuildFrame()
    frame = CreateFrame("Frame", "KewkyDeathNoteFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(440, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function() RefreshUI() end)
    tinsert(UISpecialFrames, "KewkyDeathNoteFrame")

    local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetText("Death Note")
    if not frame.TitleText then title:SetPoint("TOP", 0, -5) end

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.summary:SetPoint("TOPLEFT", 14, -32)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 10, -52)
    frame.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(1, 1)
    frame.scroll:SetScrollChild(frame.content)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER")
    frame.empty:SetText("No PvP kills or deaths yet.")

    frame:Hide()
end

-- ── target glow ──

local function Border(parent, thickness, outset, r, g, b, a)
    local function Tex()
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local top, bottom, left, right = Tex(), Tex(), Tex(), Tex()
    top:SetPoint("TOPLEFT", -outset, outset)
    top:SetPoint("TOPRIGHT", outset, outset)
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", -outset, -outset)
    bottom:SetPoint("BOTTOMRIGHT", outset, -outset)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", -outset, outset)
    left:SetPoint("BOTTOMLEFT", -outset, -outset)
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", outset, outset)
    right:SetPoint("BOTTOMRIGHT", outset, -outset)
    right:SetWidth(thickness)
end

local function BuildGlow()
    if not TargetFrame then return end
    -- our own frame anchored to the target frame; nothing is written into TargetFrame itself
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetPoint("TOPLEFT", TargetFrame, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", TargetFrame, "BOTTOMRIGHT", 0, 0)
    glow:SetFrameStrata(TargetFrame:GetFrameStrata())
    glow:SetFrameLevel(TargetFrame:GetFrameLevel() + 10)
    Border(glow, 2, 0, 1, 0.1, 0.1, 0.9)
    Border(glow, 4, 4, 1, 0, 0, 0.35)
    Border(glow, 4, 8, 1, 0, 0, 0.15)

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.8)
    glow.pulse = pulse

    glow.text = glow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    glow.text:SetPoint("BOTTOM", glow, "TOP", 0, 10)
    glow:Hide()
end

UpdateGlow = function()
    if not glow then return end
    local guid = UnitExists("target") and UnitGUID("target")
    local p = Readable(guid) and db.players[guid]
    if not p or not TargetFrame:IsShown() then
        glow.pulse:Stop()
        glow:Hide()
        return
    end
    local k, a, d = Counts(p)
    glow.text:SetText(string.format("|cffff3030Death Note|r  K %d  A %d  D %d  K/D %s", k, a, d, KD(k, d)))
    glow:Show()
    glow.pulse:Play()
end

-- ── events ──

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        myGUID = UnitGUID("player")
        KewkyDeathNoteDB.chars = KewkyDeathNoteDB.chars or {}
        db = KewkyDeathNoteDB.chars[myGUID] or { players = {} }
        db.name = UnitName("player")
        KewkyDeathNoteDB.chars[myGUID] = db

        BuildFrame()
        BuildGlow()
        for _, e in ipairs({ "PARTY_KILL", "PLAYER_DEAD", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
            "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "UNIT_LEVEL", "PLAYER_PVP_KILLS_CHANGED" }) do
            pcall(f.RegisterEvent, f, e)
        end
        C_Timer.NewTicker(300, Prune)
    elseif event == "PARTY_KILL" then
        OnPartyKill(...)
    elseif event == "PLAYER_DEAD" then
        C_Timer.After(0.3, function() ResolveDeath(6) end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(1, ResolveAssists)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
        local guid = UnitGUID("target")
        if Readable(guid) then lastTargeted[guid] = GetTime() end
        UpdateGlow()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_LEVEL" then
        local unit = ...
        if unit then Remember(unit) end
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        Debug("PLAYER_PVP_KILLS_CHANGED")
    end
end)

SLASH_KEWKYDEATHNOTE1 = "/kdn"
SLASH_KEWKYDEATHNOTE2 = "/deathnote"
SlashCmdList.KEWKYDEATHNOTE = function(msg)
    msg = (msg or ""):lower()
    if msg == "debug" then
        KewkyDeathNoteDB.debug = not KewkyDeathNoteDB.debug
        Print("debug " .. (KewkyDeathNoteDB.debug and "on" or "off"))
    elseif msg == "reset yes" then
        db.players = {}
        RefreshUI()
        UpdateGlow()
        Print("cleared for this character.")
    elseif msg == "reset" then
        Print("type /kdn reset yes to clear this character's note.")
    elseif frame then
        frame:SetShown(not frame:IsShown())
    end
end
