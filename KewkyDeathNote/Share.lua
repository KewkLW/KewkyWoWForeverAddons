local ADDON_NAME, ns = ...

-- Shared sightings: when your enemy alert spots someone, everyone running this addon in the same zone
-- gets the notice too, with a pin on their world map where it was seen. Pins fade out over a minute.
-- Messages go over a hidden chat channel. Your position stands in for the enemy's (they're within
-- nameplate range of you). Sending can be held during combat lockdown; it goes out when that ends.
-- /kdn share, or the "Share sightings" checkbox, turns sending and receiving off.

local PREFIX = "KewkyDN1"
local CHANNEL = "KewkyDeathNote"
local PIN_LIFE = 60            -- s a pin stays on the map, fading
local DEDUPE = 60              -- s: the same enemy reported by several people shows once
local SEP = "~"

local channelID
local pins = {}                -- guid -> pin record
local queue = {}
local driver

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function ShareOn()
    return KewkyDeathNoteDB.share ~= false
end

-- ── where you are ──

local function ZoneOf(mapID)
    local hops = 0
    while mapID and hops < 6 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then return mapID end
        if not info.parentMapID or info.parentMapID == 0 or (info.mapType and info.mapType <= Enum.UIMapType.Zone) then
            return mapID
        end
        mapID, hops = info.parentMapID, hops + 1
    end
    return mapID
end

local function MyPosition()
    local map = C_Map.GetBestMapForUnit("player")
    if not map or IsSecret(map) then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos or IsSecret(pos.x) then return nil end
    return map, pos.x, pos.y
end

-- ── channel ──

local function Join()
    if not ShareOn() then return end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    local id = GetChannelName(CHANNEL)
    if id and id > 0 then channelID = id return end
    pcall(JoinTemporaryChannel, CHANNEL)
    C_Timer.After(2, function()
        local id2 = GetChannelName(CHANNEL)
        if id2 and id2 > 0 then channelID = id2 end
    end)
end

local function Flush()
    if not channelID then return end
    local keep = {}
    for _, item in ipairs(queue) do
        if time() - item.t < PIN_LIFE then
            local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "CHANNEL", tostring(channelID))
            local sent = ok and (result == nil or result == true or result == 0 or
                (Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success))
            if not sent then keep[#keep + 1] = item end
        end
    end
    queue = keep
end

-- ── map pins ──

local function Canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function NewPinFrame()
    local canvas = Canvas()
    if not canvas then return nil end
    local f = CreateFrame("Frame", nil, canvas)
    f:SetSize(28, 28)
    f:SetFrameStrata("HIGH")
    f.star = f:CreateTexture(nil, "OVERLAY")
    f.star:SetTexture("Interface\\Cooldown\\star4")
    f.star:SetBlendMode("ADD")
    f.star:SetVertexColor(1, 0.15, 0.1)
    f.star:SetAllPoints()
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, 2)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local p = self.pin
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
        GameTooltip:SetText(p.name, c and c.r or 1, c and c.g or 0.3, c and c.b or 0.2)
        GameTooltip:AddLine((p.faction or "") .. "  ·  " .. p.what, 1, 1, 1)
        GameTooltip:AddLine(string.format("Seen %s by %s", date("%H:%M:%S", p.t), p.by), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    return f
end

local function UpdatePins()
    local now = time()
    local canvas = Canvas()
    local shownMap = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
    for guid, p in pairs(pins) do
        local age = now - p.t
        if age >= PIN_LIFE then
            if p.frame then p.frame:Hide() end
            pins[guid] = nil
        elseif p.frame then
            local x, y
            if shownMap and canvas and p.world then
                local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, p.cont, p.world, shownMap)
                if ok and pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then x, y = pos.x, pos.y end
            end
            if x then
                local w, h = canvas:GetSize()
                p.frame:ClearAllPoints()
                p.frame:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
                p.frame:SetScale(1 / math.max(canvas:GetScale(), 0.01))
                p.frame:SetAlpha(1 - age / PIN_LIFE)
                p.frame.label:SetText(string.format("%s  %ds", p.short, age))
                p.frame:Show()
            else
                p.frame:Hide()
            end
        end
    end
end

local function AddPin(guid, mapID, x, y, t, name, what, by, faction, class)
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not cont then return end
    local p = pins[guid] or {}
    p.cont, p.world, p.t, p.name, p.what, p.by, p.faction, p.class = cont, world, t, name, what, by, faction, class
    p.short = name:match("^(%S+)") or name
    p.frame = p.frame or NewPinFrame()
    if p.frame then p.frame.pin = p end
    pins[guid] = p
    UpdatePins()
end

-- ── sending and receiving ──

-- called by Alert.lua for each new local sighting
ns.ShareSighting = function(s)
    if not ShareOn() then return end
    local map, x, y = MyPosition()
    if not map then return end
    local by = UnitName("player")
    AddPin(s.guid, map, x, y, time(), s.name, s.what, by, s.faction, s.class)
    local msg = table.concat({ "S", map, math.floor(x * 10000), math.floor(y * 10000), time(), s.guid,
        s.faction, s.level, s.class or "", s.race or "", s.name }, SEP)
    queue[#queue + 1] = { msg = msg:sub(1, 255), t = time() }
    if not channelID then Join() end
    Flush()
end

local function OnMessage(text, sender)
    local f = { strsplit(SEP, text) }
    if f[1] ~= "S" or #f < 11 then return end
    local me = UnitName("player")
    if sender and (sender == me or Ambiguate(sender, "short") == me) then return end
    local map, x, y, t = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    local guid, faction, level, class, race, name = f[6], f[7], f[8], f[9], f[10], f[11]
    if not (map and x and y and t and guid and name) then return end
    if faction == UnitFactionGroup("player") then return end
    if time() - t > PIN_LIFE then return end

    local mine = MyPosition()
    if not mine or ZoneOf(mine) ~= ZoneOf(map) then return end          -- only your zone
    local p = pins[guid]
    if p and time() - p.t < DEDUPE then return end                       -- someone already reported them

    local parts = { level }
    if race ~= "" then parts[#parts + 1] = race end
    local classLocal = class ~= "" and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
    if classLocal ~= "" then parts[#parts + 1] = classLocal end
    local what = table.concat(parts, " ")
    local by = Ambiguate(sender or "?", "short")
    AddPin(guid, map, x / 10000, y / 10000, t, name, what, by, faction, class ~= "" and class or nil)
    if ns.ShowSighting then ns.ShowSighting(guid, name, what, faction, by, t, map, x / 100, y / 100) end
end

ns.ToggleShare = function()
    KewkyDeathNoteDB.share = not ShareOn()
    if ShareOn() then Join() else
        for guid, p in pairs(pins) do if p.frame then p.frame:Hide() end pins[guid] = nil end
        if channelID then pcall(LeaveChannelByName, CHANNEL) channelID = nil end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333Death Note|r sharing sightings " .. (ShareOn() and "on" or "off"))
end
ns.ShareOn = ShareOn

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, prefix, text, _, sender)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(8, Join)                 -- channels aren't ready right at login
        driver = CreateFrame("Frame")
        local acc = 0
        driver:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc < 0.25 then return end
            acc = 0
            if next(pins) then UpdatePins() end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        if prefix == PREFIX and ShareOn() and not IsSecret(text) then OnMessage(text, sender) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if #queue > 0 then Flush() end
    end
end)
