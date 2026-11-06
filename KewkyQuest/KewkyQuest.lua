local ADDON_NAME, ns = ...

ns.QuestDB   = ns.QuestDB or {}
ns.NPCS      = ns.NPCs or ns.NPCS or {}  -- QuestDB.lua names it NPCs
ns.ZoneNames = ns.ZoneNames or {}
ns.QF = ns.QF or {NAME=1,LEVEL=2,MIN_LEVEL=3,ZONE=4,GIVERS=5,FINISHERS=6,PREREQS=7,NEXT=8,CLASSES=9}
ns.NF = ns.NF or {NAME=1,ZONE=2,X=3,Y=4}

KewkyQuestSV = KewkyQuestSV or {}

local CQL  = C_QuestLog
local CMap = C_Map
local CST  = C_SuperTrack
local QF = ns.QF
local NF = ns.NF

local PANEL_W       = 360
local ROW_H         = 28
local VISIBLE_ROWS  = 14
local SCROLL_STEP   = ROW_H * 3

local COLOR_GREEN  = { r = 0.2, g = 0.9, b = 0.3 }
local COLOR_YELLOW = { r = 1.0, g = 0.82, b = 0.0 }
local COLOR_GREY   = { r = 0.5, g = 0.5, b = 0.5 }
local COLOR_BLUE   = { r = 0.3, g = 0.7, b = 1.0 }
local COLOR_TURNIN = { r = 0.9, g = 0.6, b = 0.1 }

-- QuestDB zone IDs are AreaTable IDs (14 = Durotar), not uiMapIDs
local ZONE_ADJACENT = {
    [14]   = { 17, 1637 },                     -- Durotar -> Barrens, Orgrimmar
    [17]   = { 14, 215, 406, 331, 400, 15, 1637 }, -- Barrens -> Durotar, Mulgore, Stonetalon, Ashenvale, Thousand Needles, Dustwallow, Orgrimmar
    [215]  = { 17, 1638 },                     -- Mulgore -> Barrens, Thunder Bluff
    [85]   = { 130, 1497 },                    -- Tirisfal -> Silverpine, Undercity
    [130]  = { 85, 267 },                      -- Silverpine -> Tirisfal, Hillsbrad
    [406]  = { 17, 331, 405 },                 -- Stonetalon -> Barrens, Ashenvale, Desolace
    [331]  = { 17, 406, 148, 361, 16 },        -- Ashenvale -> Barrens, Stonetalon, Darkshore, Felwood, Azshara
    [400]  = { 17, 357, 440 },                 -- Thousand Needles -> Barrens, Feralas, Tanaris
    [1637] = { 14, 17 },                       -- Orgrimmar -> Durotar, Barrens
    [1638] = { 215 },                          -- Thunder Bluff -> Mulgore
    [1497] = { 85 },                           -- Undercity -> Tirisfal
}

-- Classic Era uiMapIDs, used when the in-game name lookup finds nothing
local ZONE_UIMAP_FALLBACK = {
    [14] = 1411, [215] = 1412, [17] = 1413, [36] = 1416, [45] = 1417, [3] = 1418,
    [4] = 1419, [85] = 1420, [130] = 1421, [28] = 1422, [139] = 1423, [267] = 1424,
    [47] = 1425, [1] = 1426, [51] = 1427, [46] = 1428, [12] = 1429, [41] = 1430,
    [10] = 1431, [38] = 1432, [44] = 1433, [33] = 1434, [8] = 1435, [40] = 1436,
    [11] = 1437, [141] = 1438, [148] = 1439, [331] = 1440, [400] = 1441, [406] = 1442,
    [405] = 1443, [357] = 1444, [15] = 1445, [440] = 1446, [16] = 1447, [361] = 1448,
    [490] = 1449, [493] = 1450, [1377] = 1451, [618] = 1452, [1519] = 1453, [1637] = 1454,
    [1537] = 1455, [1638] = 1456, [1657] = 1457, [1497] = 1458,
}

local frame, scrollFrame, scrollChild, routeButton
local questRows = {}
local filteredQuests = {}
local currentRoute = {}
local RefreshPanel, UpdateMapPins

-- ── quest accessors ──

local function QName(q) return q[QF.NAME] end
local function QLevel(q) return q[QF.LEVEL] end
local function QMinLevel(q) return q[QF.MIN_LEVEL] end
local function QZone(q) return q[QF.ZONE] end
local function QGivers(q) return q[QF.GIVERS] end
local function QFinishers(q) return q[QF.FINISHERS] end
local function QPrereqs(q) return q[QF.PREREQS] end
local function QClasses(q) return q[QF.CLASSES] end

local function FirstNPC(list)
    local npcID = list and list[1]
    return npcID, npcID and ns.NPCS[npcID]
end

-- ── helpers ──

local function PlayerLevel()
    return UnitLevel("player")
end

-- class bitmask as in QuestDB (1 = warrior, 16 = priest, 1024 = druid)
local function ClassAllowed(quest)
    local mask = QClasses(quest)
    if not mask or mask == 0 then return true end
    local _, _, classID = UnitClass("player")
    if not classID then return true end
    local bit = 2 ^ (classID - 1)
    return mask % (bit * 2) >= bit
end

local function PlayerMapID()
    return CMap.GetBestMapForUnit("player")
end

local function ZoneChain(mapID)
    local ids = {}
    local seen = {}
    while mapID and not seen[mapID] do
        ids[#ids + 1] = mapID
        seen[mapID] = true
        local info = CMap.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return ids
end

-- ── DB zone (AreaTable) <-> uiMapID ──

local areaToUiMap = {}
local uiMapToArea = {}
local zoneMapBuilt = false

local function NormName(s)
    if not s then return nil end
    s = s:lower():gsub("^the ", ""):gsub(" city$", "")
    return (s:gsub("[^%a]", ""))
end

local function BuildZoneMap()
    wipe(areaToUiMap)
    wipe(uiMapToArea)

    -- every map the client knows, by normalized name; zone-type maps win over dungeons etc.
    local byName, byNameType = {}, {}
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local function add(id, name, mapType)
        local n = NormName(name)
        if not n or n == "" then return end
        local rank = (mapType == zoneType) and 0 or 1
        if not byName[n] or rank < byNameType[n] then
            byName[n], byNameType[n] = id, rank
        end
    end
    if CMap.GetMapChildrenInfo then
        local roots = { 946, 947 }
        for _, id in ipairs(ZoneChain(PlayerMapID())) do roots[#roots + 1] = id end
        for _, root in ipairs(roots) do
            local ok, kids = pcall(CMap.GetMapChildrenInfo, root, nil, true)
            if ok and kids then
                for _, m in ipairs(kids) do add(m.mapID, m.name, m.mapType) end
            end
        end
    end

    for areaID, name in pairs(ns.ZoneNames) do
        local n = NormName(name)
        local fb = ZONE_UIMAP_FALLBACK[areaID]
        local fbInfo = fb and CMap.GetMapInfo(fb)
        local uiMap
        if fbInfo and NormName(fbInfo.name) == n then
            uiMap = fb
        elseif byName[n] then
            uiMap = byName[n]
        elseif fbInfo then
            uiMap = fb
        end
        if uiMap then
            areaToUiMap[areaID] = uiMap
            if not uiMapToArea[uiMap] then uiMapToArea[uiMap] = areaID end
        end
    end
    zoneMapBuilt = true
end

local function UiMapFor(areaID)
    if not zoneMapBuilt then BuildZoneMap() end
    return areaID and areaToUiMap[areaID]
end

local function AreaFor(uiMapID)
    if not zoneMapBuilt then BuildZoneMap() end
    return uiMapID and uiMapToArea[uiMapID]
end

-- the DB zone a quest lives in: where its giver stands, else the quest's own zone/sort
local function QuestHomeZone(q)
    local _, npc = FirstNPC(QGivers(q))
    if npc and npc[NF.ZONE] and UiMapFor(npc[NF.ZONE]) then return npc[NF.ZONE] end
    return QZone(q)
end

local function InsideMap(pos)
    return pos and pos.x > 0.001 and pos.x < 0.999 and pos.y > 0.001 and pos.y < 0.999
end

local function FindPlayerDBZones()
    local found = {}
    local mapID = PlayerMapID()
    if not mapID then return found end
    if not zoneMapBuilt then BuildZoneMap() end

    for _, id in ipairs(ZoneChain(mapID)) do
        local area = uiMapToArea[id]
        if area then
            found[area] = true
            break
        end
    end

    -- custom/sub maps with no DB zone: ask each DB zone map whether the player is on it
    if not next(found) then
        for area, uiMap in pairs(areaToUiMap) do
            local ok, pos = pcall(CMap.GetPlayerMapPosition, uiMap, "player")
            if ok and InsideMap(pos) then found[area] = true end
        end
    end

    return found
end

-- world coordinates (yards) for a DB zone position given in percent
local worldCache = {}

local function WorldPos(areaID, x, y)
    if not areaID or not x or x <= 0 then return nil end
    local key = areaID .. ":" .. x .. ":" .. y
    local c = worldCache[key]
    if c then return c[1], c[2], c[3] end
    local uiMap = UiMapFor(areaID)
    if not uiMap or not CMap.GetWorldPosFromMapPos then return nil end
    local ok, cont, world = pcall(CMap.GetWorldPosFromMapPos, uiMap, CreateVector2D(x / 100, y / 100))
    if not ok or not cont or not world then return nil end
    worldCache[key] = { world.x, world.y, cont }
    return world.x, world.y, cont
end

local function PlayerWorldPos()
    local mapID = PlayerMapID()
    if not mapID or not CMap.GetWorldPosFromMapPos then return nil end
    local pos = CMap.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local ok, cont, world = pcall(CMap.GetWorldPosFromMapPos, mapID, pos)
    if not ok or not cont or not world then return nil end
    return world.x, world.y, cont
end

-- percent coords in a DB zone -> 0..1 coords on the map being viewed, nil if off that map
local function ProjectToMap(areaID, x, y, viewMap, unclamped)
    local src = UiMapFor(areaID)
    if not src or not x or x <= 0 then return nil end
    if src == viewMap then return x / 100, y / 100 end
    if not CMap.GetMapPosFromWorldPos then return nil end
    local wx, wy, cont = WorldPos(areaID, x, y)
    if not wx then return nil end
    local ok, _, pos = pcall(CMap.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), viewMap)
    if ok and pos and (unclamped or (pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1)) then
        return pos.x, pos.y
    end
    return nil
end

-- map width/height in yards, measured between corners so no world-axis convention is assumed
local mapSizeCache = {}

local function MapYards(uiMap)
    local c = mapSizeCache[uiMap]
    if c then return c[1], c[2] end
    if not CMap.GetWorldPosFromMapPos then return nil end
    local ok1, _, a = pcall(CMap.GetWorldPosFromMapPos, uiMap, CreateVector2D(0, 0))
    local ok2, _, b = pcall(CMap.GetWorldPosFromMapPos, uiMap, CreateVector2D(1, 0))
    local ok3, _, c2 = pcall(CMap.GetWorldPosFromMapPos, uiMap, CreateVector2D(0, 1))
    if not (ok1 and ok2 and ok3 and a and b and c2) then return nil end
    local w = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    local h = math.sqrt((c2.x - a.x) ^ 2 + (c2.y - a.y) ^ 2)
    if w <= 0 or h <= 0 then return nil end
    mapSizeCache[uiMap] = { w, h }
    return w, h
end

local function Dist2D(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- where a quest entry sends you: giver for pickups, finisher for ready turn-ins
local function NPCStop(npcID, npc)
    if not npc or (npc[NF.X] or 0) <= 0 then return nil end
    local wx, wy = WorldPos(npc[NF.ZONE], npc[NF.X], npc[NF.Y])
    return {
        npcID = npcID, name = npc[NF.NAME] or ("NPC " .. npcID),
        zone = npc[NF.ZONE], x = npc[NF.X], y = npc[NF.Y], wx = wx, wy = wy,
    }
end

local function DistanceTo(stop, px, py)
    if not stop or not stop.wx or not px then return 99999 end
    return Dist2D(px, py, stop.wx, stop.wy)
end

local function GiverName(quest)
    local npcID, npc = FirstNPC(QGivers(quest))
    if not npcID then return "Unknown" end
    return npc and npc[NF.NAME] or "NPC " .. npcID
end

-- server-side completion flags, saved for the web UI as a sorted list
local function SnapshotCompleted()
    local ids = {}
    if CQL.GetAllCompletedQuestIDs then
        local ok, all = pcall(CQL.GetAllCompletedQuestIDs)
        if ok and all then ids = all end
    end
    if #ids == 0 and CQL.IsQuestFlaggedCompleted then
        for qID in pairs(ns.QuestDB) do
            if CQL.IsQuestFlaggedCompleted(qID) then ids[#ids + 1] = qID end
        end
    end
    for qID in pairs(KewkyQuestSV.completed or {}) do
        ids[#ids + 1] = qID
    end
    table.sort(ids)
    local list, prev = {}, nil
    for _, id in ipairs(ids) do
        if id ~= prev then list[#list + 1] = id end
        prev = id
    end
    KewkyQuestSV.serverCompleted = list
    KewkyQuestSV.snapshotAt = time()
    return #list
end

local function IsQuestCompleted(questID)
    if KewkyQuestSV.completed and KewkyQuestSV.completed[questID] then
        return true
    end
    if CQL.IsQuestFlaggedCompleted and CQL.IsQuestFlaggedCompleted(questID) then
        return true
    end
    return false
end

-- questID -> GetInfo row; walked from the log like KewkTracker does, because
-- GetLogIndexForQuestID finds nothing on Forever
local logCache, logCacheTime = {}, -1

local function QuestLogInfo()
    local now = GetTime()
    if now == logCacheTime then return logCache end
    logCache, logCacheTime = {}, now
    local n = CQL.GetNumQuestLogEntries and CQL.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = CQL.GetInfo and CQL.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            logCache[info.questID] = info
        end
    end
    return logCache
end

local function IsQuestInLog(questID)
    if QuestLogInfo()[questID] then return true end
    return CQL.GetLogIndexForQuestID and CQL.GetLogIndexForQuestID(questID) ~= nil or false
end

local function IsReadyForTurnIn(questID)
    local info = QuestLogInfo()[questID]
    if info and info.isComplete and info.isComplete ~= 0 and info.isComplete ~= -1 then return true end
    if CQL.ReadyForTurnIn and CQL.ReadyForTurnIn(questID) then return true end
    if CQL.IsComplete and CQL.IsComplete(questID) then return true end
    return false
end

local function PrereqsMet(quest)
    local prereqs = QPrereqs(quest)
    if not prereqs then return true end
    for _, pqID in ipairs(prereqs) do
        if not IsQuestCompleted(pqID) then
            return false
        end
    end
    return true
end

local function QuestAvailability(questID, quest)
    if IsQuestCompleted(questID) then
        return nil
    end
    if IsQuestInLog(questID) then
        return "inlog", COLOR_BLUE
    end
    if not ClassAllowed(quest) then
        return nil
    end
    local pLevel = PlayerLevel()
    if not PrereqsMet(quest) then
        return "locked", COLOR_GREY
    end
    local minLvl = QMinLevel(quest)
    if minLvl and pLevel < minLvl then
        return "locked", COLOR_GREY
    end
    local lvl = QLevel(quest)
    if lvl and pLevel < lvl - 3 then
        return "hard", COLOR_YELLOW
    end
    -- grey quests: listed, but not worth a route stop
    local grey = (pLevel <= 5) and 0 or (pLevel - math.floor(pLevel / 10) - 5)
    if lvl and lvl <= grey then
        return "trivial", COLOR_GREY
    end
    return "available", COLOR_GREEN
end

local function ZoneName(zoneID)
    if not zoneID then return "Unknown" end
    if ns.ZoneNames[zoneID] then return ns.ZoneNames[zoneID] end
    local info = UiMapFor(zoneID) and CMap.GetMapInfo(UiMapFor(zoneID))
    return info and info.name or tostring(zoneID)
end

-- ── quest scanning ──

local STATUS_ORDER = { inlog = 0, available = 1, hard = 2, trivial = 3, locked = 4 }

local function SortEntries(list)
    table.sort(list, function(a, b)
        if a.status ~= b.status then
            return (STATUS_ORDER[a.status] or 9) < (STATUS_ORDER[b.status] or 9)
        end
        if a.status == "inlog" and a.ready ~= b.ready then
            return a.ready
        end
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return (QLevel(a.quest) or 0) < (QLevel(b.quest) or 0)
    end)
end

local function MakeEntry(qID, q, status, color, px, py)
    local giver = NPCStop(FirstNPC(QGivers(q)))
    local finisher = NPCStop(FirstNPC(QFinishers(q)))
    local entry = {
        questID  = qID,
        quest    = q,
        status   = status,
        color    = color,
        npcName  = GiverName(q),
        giver    = giver,
        finisher = finisher,
    }
    if status == "inlog" then
        entry.ready = IsReadyForTurnIn(qID)
        entry.stop = finisher
    else
        entry.stop = giver
    end
    entry.distance = DistanceTo(entry.stop, px, py)
    return entry
end

local function ScanZoneQuests(match)
    local results = {}
    local px, py = PlayerWorldPos()
    for qID, q in pairs(ns.QuestDB) do
        if match[QuestHomeZone(q)] then
            local status, color = QuestAvailability(qID, q)
            if status then
                results[#results + 1] = MakeEntry(qID, q, status, color, px, py)
            end
        end
    end
    SortEntries(results)
    return results
end

local function ScanInLogQuests()
    local results = {}
    local px, py = PlayerWorldPos()
    for qID in pairs(QuestLogInfo()) do
        local q = ns.QuestDB[qID]
        if q then
            results[#results + 1] = MakeEntry(qID, q, "inlog", COLOR_BLUE, px, py)
        end
    end
    if #results == 0 then
        for qID, q in pairs(ns.QuestDB) do
            if IsQuestInLog(qID) and not IsQuestCompleted(qID) then
                results[#results + 1] = MakeEntry(qID, q, "inlog", COLOR_BLUE, px, py)
            end
        end
    end
    return results
end

local function ScanWithAdjacent()
    if not PlayerMapID() then return {} end

    local seen = {}
    local all = {}

    -- always include in-log quests regardless of zone
    for _, entry in ipairs(ScanInLogQuests()) do
        seen[entry.questID] = true
        all[#all + 1] = entry
    end

    -- current zone quests
    local playerZones = FindPlayerDBZones()
    for _, entry in ipairs(ScanZoneQuests(playerZones)) do
        if not seen[entry.questID] then
            seen[entry.questID] = true
            all[#all + 1] = entry
        end
    end

    -- adjacent zones (only available/hard, skip locked)
    for zID in pairs(playerZones) do
        for _, adjZID in ipairs(ZONE_ADJACENT[zID] or {}) do
            if not playerZones[adjZID] then
                for _, entry in ipairs(ScanZoneQuests({ [adjZID] = true })) do
                    local wanted = entry.status ~= "locked" and entry.status ~= "trivial"
                    if not seen[entry.questID] and wanted then
                        seen[entry.questID] = true
                        entry.otherZone = ZoneName(adjZID)
                        all[#all + 1] = entry
                    end
                end
            end
        end
    end

    SortEntries(all)
    return all
end

-- ── route optimizer (nearest neighbor over pickups and ready turn-ins) ──

local function ComputeRoute(quests)
    local stops = {}
    for _, q in ipairs(quests) do
        local wanted = q.status == "available" or (q.status == "inlog" and q.ready)
        if wanted and q.stop and q.stop.wx then
            stops[#stops + 1] = q
        end
    end
    if #stops == 0 then return {} end

    local px, py = PlayerWorldPos()
    if not px then
        px, py = stops[1].stop.wx, stops[1].stop.wy
    end
    local visited = {}
    local route = {}

    for _ = 1, #stops do
        local bestDist, bestIdx = math.huge, nil
        for j, q in ipairs(stops) do
            if not visited[j] then
                local d = Dist2D(px, py, q.stop.wx, q.stop.wy)
                if d < bestDist then
                    bestDist = d
                    bestIdx = j
                end
            end
        end
        if not bestIdx then break end
        visited[bestIdx] = true
        local pick = stops[bestIdx]
        route[#route + 1] = pick
        px, py = pick.stop.wx, pick.stop.wy
    end

    return route
end

local function PrintRoute(route)
    if #route == 0 then
        print("|cff55ccffKewkyQuest|r: Nothing to pick up or turn in nearby.")
        return
    end
    print("|cff55ccffKewkyQuest|r: Route (" .. #route .. " stops):")
    for i, r in ipairs(route) do
        local zone = r.otherZone or ZoneName(r.stop.zone or 0)
        local verb = (r.status == "inlog") and "turn in to" or "from"
        print(string.format("  |cffffd100%d.|r %s (L%d) %s %s |cff999999(%s)|r",
            i, QName(r.quest) or "?", QLevel(r.quest) or 0, verb, r.stop.name, zone))
    end
end

-- ── waypoints ──

local function SetWaypoint(stop)
    if not stop then return false, "no NPC location in the DB" end
    if not CMap.SetUserWaypoint then return false, "this client has no map waypoints" end
    local uiMap = UiMapFor(stop.zone)
    if not uiMap then return false, "no map for zone " .. tostring(stop.zone) end
    if CMap.CanSetUserWaypointOnMap and not CMap.CanSetUserWaypointOnMap(uiMap) then
        return false, "map " .. uiMap .. " does not allow waypoints"
    end
    local ok, err = pcall(CMap.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(uiMap, stop.x / 100, stop.y / 100))
    if not ok then return false, tostring(err) end
    if CMap.HasUserWaypoint and not CMap.HasUserWaypoint() then
        return false, "client did not keep the waypoint"
    end
    if CST.SetSuperTrackedUserWaypoint then
        CST.SetSuperTrackedUserWaypoint(true)
    end
    return true
end

-- ── arrow: our own on-screen pointer, since the client draws no navigation arrow ──

local arrow
local arrowTarget            -- stop table (name, zone, x, y) plus .label
local arrowQuestID           -- quest the arrow follows (objectives, then turn-in); nil for fixed stops
local QuestTarget            -- questID -> stop, label (defined after the arrow)
local followRoute, followIdx -- route entries being walked by the arrow
local arrivedAt
local ARRIVE_YD = 10

local SetArrow, ClearArrow

-- a stop on the player's map: database stops carry an AreaTable zone, the game's own quest markers a uiMap
local function ProjectStop(stop, viewMap)
    if not stop.uiMap then return ProjectToMap(stop.zone, stop.x, stop.y, viewMap, true) end
    if stop.uiMap == viewMap then return stop.x / 100, stop.y / 100 end
    if not (CMap.GetWorldPosFromMapPos and CMap.GetMapPosFromWorldPos) then return nil end
    local ok, cont, world = pcall(CMap.GetWorldPosFromMapPos, stop.uiMap, CreateVector2D(stop.x / 100, stop.y / 100))
    if not ok or not cont or not world then return nil end
    local ok2, _, pos = pcall(CMap.GetMapPosFromWorldPos, cont, world, viewMap)
    if ok2 and pos then return pos.x, pos.y end
    return nil
end

-- yards and bearing (radians, counter-clockwise from north like GetPlayerFacing)
local function ArrowVector(stop)
    local uiMap = PlayerMapID()
    if not uiMap then return nil end
    local pos = CMap.GetPlayerMapPosition(uiMap, "player")
    if not pos then return nil end
    local tx, ty = ProjectStop(stop, uiMap)
    local w, h = MapYards(uiMap)
    if not tx or not w then return nil end
    local dx = (tx - pos.x) * w   -- east
    local dy = (ty - pos.y) * h   -- south
    local bearing = math.atan2(-dx, -dy)
    return math.sqrt(dx * dx + dy * dy), bearing
end

local function ClockOf(rel)
    local turn = (-rel) % (2 * math.pi)
    local hour = math.floor(turn / (2 * math.pi) * 12 + 0.5) % 12
    return hour == 0 and 12 or hour
end

local function FollowStop(i)
    local e = followRoute and followRoute[i]
    if not e then
        followRoute, followIdx = nil, nil
        ClearArrow()
        print("|cff55ccffKewkyQuest|r: Route finished.")
        return
    end
    followIdx = i
    local verb = (e.status == "inlog") and "Turn in" or "Pick up"
    SetArrow(e.stop, string.format("%d/%d  %s: %s", i, #followRoute, verb, QName(e.quest) or "?"))
end

local function BuildArrow()
    if arrow then return end
    arrow = CreateFrame("Button", "KewkyQuestArrow", UIParent)
    arrow:SetSize(220, 90)
    arrow:SetPoint("TOP", UIParent, "TOP", 0, -120)
    arrow:SetFrameStrata("HIGH")
    arrow:SetMovable(true)
    arrow:SetClampedToScreen(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local tex = arrow:CreateTexture(nil, "ARTWORK")
    tex:SetSize(42, 42)
    tex:SetPoint("TOP", 0, 0)
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow.tex = tex

    local title = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", tex, "BOTTOM", 0, -2)
    title:SetWidth(220)
    arrow.title = title

    local dist = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dist:SetPoint("TOP", title, "BOTTOM", 0, -2)
    arrow.dist = dist

    arrow:SetScript("OnDragStart", arrow.StartMoving)
    arrow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        KewkyQuestSV.arrowPos = { point, relPoint, x, y }
    end)
    arrow:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            followRoute, followIdx = nil, nil
            ClearArrow()
        elseif followRoute then
            FollowStop(followIdx + 1)
        end
    end)
    arrow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("KewkyQuest arrow")
        GameTooltip:AddLine("Drag to move. Right-click to clear.", 1, 1, 1)
        if followRoute then GameTooltip:AddLine("Left-click: skip to next stop.", 1, 1, 1) end
        GameTooltip:Show()
    end)
    arrow:SetScript("OnLeave", GameTooltip_Hide)

    local acc, retarget = 0, 0
    arrow:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.05 or not arrowTarget then return end
        acc = 0
        retarget = retarget + 0.05
        if arrowQuestID and retarget >= 2 then
            retarget = 0
            local stop, label = QuestTarget(arrowQuestID)
            if stop then
                arrowTarget = stop
                self.title:SetText(label)
            end
        end
        local yd, bearing = ArrowVector(arrowTarget)
        if not yd then
            self.tex:SetRotation(0)
            self.dist:SetText("|cff999999no map position|r")
            return
        end
        local facing = GetPlayerFacing and GetPlayerFacing()
        if facing and issecretvalue and issecretvalue(facing) then facing = nil end
        if yd <= ARRIVE_YD then
            self.tex:SetRotation(0)
            self.tex:SetVertexColor(0.2, 1, 0.3)
            self.dist:SetText("|cff33e64dArrived|r")
            if followRoute and not arrivedAt then
                arrivedAt = GetTime()
            elseif followRoute and GetTime() - arrivedAt > 3 then
                -- linger a moment so the quests can be taken or handed in
                FollowStop(followIdx + 1)
            end
            return
        end
        arrivedAt = nil
        self.tex:SetVertexColor(1, 0.82, 0)
        if facing then
            local rel = bearing - facing
            self.tex:SetRotation(rel)
            self.dist:SetText(string.format("%d yd  ·  %d o'clock", yd, ClockOf(rel)))
        else
            self.tex:SetRotation(bearing)
            self.dist:SetText(string.format("%d yd", yd))
        end
    end)

    local p = KewkyQuestSV.arrowPos
    if p then
        arrow:ClearAllPoints()
        arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    arrow:Hide()
end

SetArrow = function(stop, label, questID)
    if not stop then return false end
    BuildArrow()
    arrowTarget = stop
    arrowQuestID = questID
    arrivedAt = nil
    arrow.title:SetText(label or stop.name)
    arrow:Show()
    if not questID then
        -- the client's map waypoint too, where it is supported (shows on the map);
        -- not for quest arrows, it would take super-tracking away from the quest
        SetWaypoint(stop)
    end
    return true
end

ClearArrow = function()
    arrowTarget, arrowQuestID = nil, nil
    if arrow then arrow:Hide() end
end

-- objective rows still worth going to: drop targets whose log objective is already finished
local function BagCount(item)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, item)
    return ok and tonumber(n) or 0
end

-- what an objective asks for: numRequired, else the "x/y" in its text
local function Needed(o)
    if o.numRequired and o.numRequired > 0 then return o.numRequired end
    local need = o.text and o.text:match("%d+/(%d+)")
    return tonumber(need) or 1
end

local function OpenObjectiveRows(questID, rows)
    local objs = CQL.GetQuestObjectives and CQL.GetQuestObjectives(questID) or {}
    local open = {}
    for _, row in ipairs(rows) do
        local label = row[1]
        local item = not label:match("^Kill ") and not label:match("^Use ") and label:match("^([^:]+):")
        local key = label:match("^Kill (.+)$") or label:match("^Use (.+)$") or item or label
        local finished = false
        for _, o in ipairs(objs) do
            if o.text and o.text:find(key, 1, true) then
                -- done when the log says so, or for an item drop once you carry enough of it
                -- (Marla's Last Wish: "0/1 Samuel's Remains Buried" stays open after the kill)
                if o.finished or (item and BagCount(item) >= Needed(o)) then finished = true break end
            end
        end
        if not finished then open[#open + 1] = row end
    end
    -- all of them done: nothing left here (falling back to every row kept the arrow on finished spots)
    return open
end

-- the game's own marker for a quest (the circle on the map): on the player's map or a parent map,
-- else the quest's next waypoint (another zone)
local POI_AREA_YD = 300   -- database spots this close to the game's marker are the same step

local function GamePOI(questID)
    local m, hops = PlayerMapID(), 0
    while m and m > 0 and hops < 6 do
        hops = hops + 1
        local ok, list = pcall(CQL.GetQuestsOnMap, m)
        if ok and type(list) == "table" then
            for _, p in ipairs(list) do
                if p.questID == questID and p.x and p.x > 0 then
                    return { uiMap = m, x = p.x * 100, y = p.y * 100, name = "map marker" }
                end
            end
        end
        local info = CMap.GetMapInfo and CMap.GetMapInfo(m)
        m = info and info.parentMapID
    end
    if CQL.GetNextWaypoint then
        local ok, mapID, x, y = pcall(CQL.GetNextWaypoint, questID)
        if ok and mapID and x and x > 0 then
            return { uiMap = mapID, x = x * 100, y = y * 100, name = "next waypoint" }
        end
    end
    return nil
end

-- for Sparkle.lua
ns.QuestLogInfo, ns.IsReadyForTurnIn, ns.OpenObjectiveRows = QuestLogInfo, IsReadyForTurnIn, OpenObjectiveRows

-- nearest objective spot for a quest in progress, else its turn-in NPC
QuestTarget = function(questID)
    local q = ns.QuestDB[questID]
    local name = q and QName(q) or ("Quest " .. questID)
    local finisher = q and NPCStop(FirstNPC(QFinishers(q)))
    local rows = ns.Objectives and ns.Objectives[questID]
    local ready = IsReadyForTurnIn(questID)
    local poi = GamePOI(questID)
    local poiX, poiY
    if poi and CMap.GetWorldPosFromMapPos then
        local ok, _, w = pcall(CMap.GetWorldPosFromMapPos, poi.uiMap, CreateVector2D(poi.x / 100, poi.y / 100))
        if ok and w then poiX, poiY = w.x, w.y end
    end
    if rows and not ready then
        local px, py = PlayerWorldPos()
        local best, bestD
        for _, row in ipairs(OpenObjectiveRows(questID, rows)) do
            local zone = row[2]
            for i = 3, #row - 1, 2 do
                local wx, wy = WorldPos(zone, row[i], row[i + 1])
                if wx then
                    -- with a game marker, only spots in its area count: the game knows which step you're on
                    local inArea = not poiX or Dist2D(poiX, poiY, wx, wy) <= POI_AREA_YD
                    if inArea then
                        local d = px and Dist2D(px, py, wx, wy) or 0
                        if not bestD or d < bestD then
                            bestD = d
                            best = { name = row[1], zone = zone, x = row[i], y = row[i + 1] }
                        end
                    end
                end
            end
        end
        if best then return best, name .. ": " .. best.name end
    end
    -- no open objective spot we know of near the game's marker: follow the marker for the next step,
    -- and for turn-ins prefer it too (it knows where the NPC really stands on Forever)
    if poi and not ready then return poi, name .. ": next step (" .. poi.name .. ")" end
    if poi and ready then
        return poi, "Turn in: " .. (finisher and finisher.name or name) .. " (" .. poi.name .. ")"
    end
    if finisher then return finisher, "Turn in: " .. finisher.name end
    return nil
end

-- /kq why: where the arrow's target comes from, for the super-tracked quest
local function ExplainTarget()
    local qid = (CST.GetSuperTrackedQuestID and CST.GetSuperTrackedQuestID()) or arrowQuestID or 0
    if not qid or qid == 0 then print("|cff55ccffKewkyQuest|r: no quest is super-tracked.") return end
    local p = function(...) print("|cff55ccffKewkyQuest|r", ...) end
    p("quest", qid, "ready:", tostring(IsReadyForTurnIn(qid)), "player map:", tostring(PlayerMapID()))
    for _, o in ipairs(CQL.GetQuestObjectives and CQL.GetQuestObjectives(qid) or {}) do
        p("  objective:", o.text, o.finished and "(done)" or "", "need", Needed(o))
    end
    local rows = ns.Objectives and ns.Objectives[qid]
    p("  database spots:", rows and #rows or 0, "still open:", rows and #OpenObjectiveRows(qid, rows) or 0)
    for _, r in ipairs(rows or {}) do
        local item = r[1]:match("^([^:]+):")
        p("   ", r[1], item and not r[1]:match("^Kill ") and ("in bags: " .. BagCount(item)) or "")
    end
    local poi = GamePOI(qid)
    p("  game marker:", poi and string.format("map %d %.1f, %.1f (%s)", poi.uiMap, poi.x, poi.y, poi.name) or "none")
    local stop, label = QuestTarget(qid)
    p("  arrow ->", label or "nothing")
end

local function SetQuestArrow(questID)
    local stop, label = QuestTarget(questID)
    if not stop then
        print(string.format("|cff55ccffKewkyQuest|r: No location data for quest %d.", questID))
        return false
    end
    followRoute, followIdx = nil, nil
    return SetArrow(stop, label, questID)
end

-- for QuestInfo.lua
ns.Q = {
    Name = QName, Level = QLevel, MinLevel = QMinLevel, Zone = QZone, Givers = QGivers, Finishers = QFinishers,
    Prereqs = QPrereqs, Classes = QClasses,
}
ns.NPCStop, ns.ZoneName, ns.WorldPos, ns.PlayerWorldPos, ns.Dist2D = NPCStop, ZoneName, WorldPos, PlayerWorldPos, Dist2D
ns.GamePOI, ns.IsQuestCompleted, ns.IsQuestInLog, ns.QuestAvailability = GamePOI, IsQuestCompleted, IsQuestInLog, QuestAvailability
ns.SetArrow, ns.SetQuestArrow, ns.BagCount = function(...) return SetArrow(...) end, SetQuestArrow, BagCount

local function TrackEntry(e)
    if not e then return end
    local name = QName(e.quest) or "?"
    followRoute, followIdx = nil, nil
    if e.status == "inlog" and CST.SetSuperTrackedQuestID then
        CST.SetSuperTrackedQuestID(e.questID)
    end
    if e.status == "inlog" then
        SetQuestArrow(e.questID)
        return
    end
    if not e.stop then
        print(string.format("|cff55ccffKewkyQuest|r: No NPC location for %s.", name))
        return
    end
    SetArrow(e.stop, string.format("Pick up: %s", name))
    print(string.format("|cff55ccffKewkyQuest|r: Arrow → %s (%s %.1f, %.1f)", e.stop.name,
        ZoneName(e.stop.zone), e.stop.x, e.stop.y))
end

local function StartRoute(route)
    if #route == 0 then return end
    followRoute = route
    FollowStop(1)
end

-- ── UI: quest row ──

local function CreateQuestRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(PANEL_W - 30, ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local level = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    level:SetPoint("LEFT", 4, 0)
    level:SetWidth(28)
    level:SetJustifyH("CENTER")
    row.level = level

    local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("LEFT", 34, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local npc = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    npc:SetPoint("RIGHT", -4, 0)
    npc:SetWidth(84)
    npc:SetJustifyH("RIGHT")
    npc:SetTextColor(0.7, 0.7, 0.7)
    row.npc = npc

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("RIGHT", npc, "LEFT", -2, 0)
    icon:SetAtlas("QuestNormal")
    row.icon = icon

    row:SetScript("OnClick", function(self)
        TrackEntry(self.entry)
        UpdateMapPins()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(QName(e.quest) or "Unknown Quest", 1, 0.82, 0)
        GameTooltip:AddLine(string.format("Level %d quest", QLevel(e.quest) or 0), 1, 1, 1)
        if e.status == "inlog" then
            GameTooltip:AddLine(string.format("Turn in: %s", e.finisher and e.finisher.name or "?"), 0.9, 0.6, 0.1)
            if e.ready then
                GameTooltip:AddLine("Ready to turn in", 0.2, 0.9, 0.3)
            end
        else
            GameTooltip:AddLine(string.format("From: %s", e.npcName), 0.7, 0.7, 0.7)
        end
        if e.distance < 99999 then
            GameTooltip:AddLine(string.format("%d yd away", e.distance), 0.7, 0.7, 0.7)
        end
        if e.otherZone then
            GameTooltip:AddLine("Zone: " .. e.otherZone, 0.6, 0.8, 1)
        end
        if e.status == "locked" then
            GameTooltip:AddLine("Prerequisites not met", 1, 0.3, 0.3)
        elseif e.status == "hard" then
            GameTooltip:AddLine("Above your level", 1, 0.82, 0)
        end
        GameTooltip:AddLine("\nClick to set waypoint", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", GameTooltip_Hide)

    return row
end

-- ── UI: main panel ──

local function BuildPanel()
    if frame then return end

    frame = CreateFrame("Frame", "KewkyQuestFrame", UIParent, "TooltipBorderedFrameTemplate")
    frame:SetSize(PANEL_W, 60 + ROW_H * VISIBLE_ROWS)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", 8, -6)
    titleText:SetText("Quest Router")
    titleText:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then self:StartMoving() end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        KewkyQuestSV.pos = { point, relPoint, x, y }
    end)

    tinsert(UISpecialFrames, "KewkyQuestFrame")

    local HEADER_OFFSET = 24

    -- zone header
    local zoneText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    zoneText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -HEADER_OFFSET)
    zoneText:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    zoneText:SetJustifyH("LEFT")
    frame.zoneText = zoneText

    -- scroll area
    scrollFrame = CreateFrame("ScrollFrame", "KewkyQuestScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(HEADER_OFFSET + 18))
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 34)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_W - 34, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- row pool
    for i = 1, VISIBLE_ROWS + 4 do
        questRows[i] = CreateQuestRow(scrollChild, i)
        questRows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    end

    -- route button
    routeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    routeButton:SetSize(120, 22)
    routeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    routeButton:SetText("Stack Route")
    routeButton:SetScript("OnClick", function()
        currentRoute = ComputeRoute(filteredQuests)
        PrintRoute(currentRoute)
        StartRoute(currentRoute)
        UpdateMapPins()
    end)

    -- scan button
    local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanBtn:SetSize(80, 22)
    scanBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6)
    scanBtn:SetText("Refresh")
    scanBtn:SetScript("OnClick", function()
        RefreshPanel()
    end)

    -- restore position
    local p = KewkyQuestSV.pos
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end

    frame:Hide()
end

RefreshPanel = function()
    if not frame then return end

    filteredQuests = ScanWithAdjacent()

    local mapID = PlayerMapID()
    local mapInfo = mapID and CMap.GetMapInfo(mapID)
    frame.zoneText:SetText((mapInfo and mapInfo.name or "Unknown") ..
        " — " .. #filteredQuests .. " quest(s)")

    local totalH = #filteredQuests * ROW_H
    scrollChild:SetHeight(math.max(totalH, 1))

    for i = #questRows + 1, #filteredQuests do
        questRows[i] = CreateQuestRow(scrollChild, i)
        questRows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    end

    for i, row in ipairs(questRows) do
        local entry = filteredQuests[i]
        if entry then
            row.entry = entry
            row.level:SetText(tostring(QLevel(entry.quest) or "?"))
            row.level:SetTextColor(entry.color.r, entry.color.g, entry.color.b)
            if entry.status == "inlog" and entry.ready then
                row.name:SetText("|cff33e64d[Done]|r " .. (QName(entry.quest) or "Unknown"))
            elseif entry.status == "inlog" then
                row.name:SetText("► " .. (QName(entry.quest) or "Unknown"))
            else
                row.name:SetText(QName(entry.quest) or "Unknown")
            end
            row.name:SetTextColor(entry.color.r, entry.color.g, entry.color.b)

            if entry.status == "inlog" then
                row.npc:SetText(entry.finisher and entry.finisher.name or "")
                row.npc:SetTextColor(COLOR_TURNIN.r, COLOR_TURNIN.g, COLOR_TURNIN.b)
                row.icon:SetAtlas("QuestTurnin")
            elseif entry.status == "available" then
                row.npc:SetText(entry.npcName)
                row.npc:SetTextColor(0.7, 0.7, 0.7)
                row.icon:SetAtlas("QuestNormal")
            elseif entry.status == "hard" then
                row.npc:SetText(entry.npcName)
                row.npc:SetTextColor(0.7, 0.7, 0.7)
                row.icon:SetAtlas("QuestRepeatableTurnin")
            elseif entry.status == "trivial" then
                row.npc:SetText(entry.npcName)
                row.npc:SetTextColor(0.5, 0.5, 0.5)
                row.icon:SetAtlas("QuestNormal")
            else
                row.npc:SetText(entry.npcName)
                row.npc:SetTextColor(0.7, 0.7, 0.7)
                row.icon:SetAtlas("QuestSkull")
            end
            row.icon:SetDesaturated(entry.status == "trivial")

            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

local function TogglePanel()
    BuildPanel()
    if frame:IsShown() then
        frame:Hide()
    else
        RefreshPanel()
        frame:Show()
    end
end

-- ── map pins ──

local pinPool = {}

local function GetOrCreatePin(parent, index)
    if pinPool[index] then return pinPool[index] end

    local pin = CreateFrame("Button", "KewkyQuestPin" .. index, parent)
    pin:SetSize(20, 20)
    pin:SetFrameStrata("HIGH")

    local tex = pin:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetAtlas("QuestNormal")
    pin.icon = tex

    local num = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    num:SetPoint("CENTER", 0, 0)
    num:SetTextColor(1, 1, 1)
    pin.number = num

    pin:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(QName(self.entry.quest) or "?", 1, 0.82, 0)
        local verb = self.pinStop == self.entry.finisher and "Turn in to" or "From"
        GameTooltip:AddLine(string.format("L%d  %s %s", QLevel(self.entry.quest) or 0, verb,
            self.pinStop and self.pinStop.name or "?"), 1, 1, 1)
        if self.routeNum then
            GameTooltip:AddLine("Route stop #" .. self.routeNum, 0.5, 1, 0.5)
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", GameTooltip_Hide)

    pin:SetScript("OnClick", function(self)
        TrackEntry(self.entry)
    end)

    pinPool[index] = pin
    return pin
end

local function HideAllPins()
    for _, pin in pairs(pinPool) do
        pin:Hide()
    end
end

local function PlacePin(canvas, idx, entry, stop, viewMap, atlas, size)
    local fx, fy = ProjectToMap(stop.zone, stop.x, stop.y, viewMap)
    if not fx then return idx end
    idx = idx + 1
    local cw, ch = canvas:GetSize()
    local pin = GetOrCreatePin(canvas, idx)
    pin.entry = entry
    pin.pinStop = stop
    pin.routeNum = nil
    pin.number:Hide()
    pin.icon:SetAtlas(atlas)
    pin.icon:SetDesaturated(false)
    pin:SetSize(size, size)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", fx * cw, -fy * ch)
    pin:Show()
    return idx, pin
end

UpdateMapPins = function()
    HideAllPins()

    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end

    local canvas = WorldMapFrame:GetCanvas()
    if not canvas then return end

    local viewMap = WorldMapFrame:GetMapID()
    if not viewMap then return end

    local cw, ch = canvas:GetSize()
    if cw <= 0 or ch <= 0 then return end

    local routing = #currentRoute > 0
    local quests = routing and currentRoute or filteredQuests
    local pinIdx, pin = 0, nil

    for i, entry in ipairs(quests) do
        if entry.status == "inlog" then
            if entry.finisher then
                pinIdx, pin = PlacePin(canvas, pinIdx, entry, entry.finisher, viewMap, "QuestTurnin", 24)
                if pin and not entry.ready then
                    pin.icon:SetDesaturated(true)
                end
                if pin and routing then
                    pin.routeNum = i
                    pin.number:SetText(tostring(i))
                    pin.number:Show()
                end
            end
        elseif entry.giver and (entry.status == "available" or entry.status == "hard") then
            local atlas = (entry.status == "available") and "QuestNormal" or "QuestRepeatableTurnin"
            if routing then atlas = "Waypoint-MapPin-ChatIcon" end
            pinIdx, pin = PlacePin(canvas, pinIdx, entry, entry.giver, viewMap, atlas, 20)
            if pin and routing then
                pin.routeNum = i
                pin.number:SetText(tostring(i))
                pin.number:Show()
            end
        end
        pin = nil
    end
end

-- ── runtime quest discovery ──

local function CaptureQuestFromGossip()
    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then return end
    if ns.QuestDB[questID] then return end

    local title = GetTitleText and GetTitleText() or nil
    local level = CQL.GetQuestDifficultyLevel and CQL.GetQuestDifficultyLevel(questID) or 0

    if title then
        local discovered = KewkyQuestSV.discovered or {}
        -- same array layout as QuestDB rows (see ns.QF)
        discovered[questID] = { title, level, math.max(1, level - 3), (next(FindPlayerDBZones())) }
        KewkyQuestSV.discovered = discovered
        ns.QuestDB[questID] = discovered[questID]
    end
end

-- ── events ──

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("SUPER_TRACKING_CHANGED")

local loginAt = math.huge

local logRefreshPending = false

events:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_LOGIN" then
        KewkyQuestSV = KewkyQuestSV or {}
        KewkyQuestSV.completed  = KewkyQuestSV.completed or {}
        KewkyQuestSV.discovered = KewkyQuestSV.discovered or {}

        for qID, qData in pairs(KewkyQuestSV.discovered) do
            if qData.name then
                -- old keyed format
                qData = { qData.name, qData.level, qData.minLevel }
                KewkyQuestSV.discovered[qID] = qData
            end
            if not ns.QuestDB[qID] then
                ns.QuestDB[qID] = qData
            end
        end

        if WorldMapFrame then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
                C_Timer.After(0.1, UpdateMapPins)
            end)
            hooksecurefunc(WorldMapFrame, "Show", function()
                C_Timer.After(0.2, function()
                    if #currentRoute == 0 then
                        filteredQuests = ScanWithAdjacent()
                    end
                    UpdateMapPins()
                end)
            end)
        end

        C_Timer.After(3, SnapshotCompleted)

        loginAt = GetTime()
        print("|cff55ccffKewkyQuest|r loaded. /kq to open, /kq done for completed quests.")

    elseif event == "SUPER_TRACKING_CHANGED" then
        -- clicking a quest's icon in the objective tracker super-tracks it: point the arrow there.
        -- skip the first seconds after login, when the client restores the old super-track
        if GetTime() - loginAt < 5 then return end
        local qid = CST.GetSuperTrackedQuestID and CST.GetSuperTrackedQuestID() or 0
        if qid and qid > 0 then
            if qid ~= arrowQuestID then SetQuestArrow(qid) end
        elseif arrowQuestID and not (CST.IsSuperTrackingUserWaypoint and CST.IsSuperTrackingUserWaypoint()) then
            ClearArrow()
        end

    elseif event == "QUEST_TURNED_IN" then
        local questID, xp, money = arg1, ...
        if questID and questID == arrowQuestID then ClearArrow() end
        if questID then
            KewkyQuestSV.completed[questID] = true
            KewkyQuestSV.history = KewkyQuestSV.history or {}
            table.insert(KewkyQuestSV.history, {
                id = questID, t = time(), level = PlayerLevel(),
                zone = next(FindPlayerDBZones()), xp = xp or 0, money = money or 0,
            })
        end
        if frame and frame:IsShown() then
            C_Timer.After(0.5, RefreshPanel)
        end

    elseif event == "QUEST_ACCEPTED" then
        if frame and frame:IsShown() then
            C_Timer.After(0.5, RefreshPanel)
        end

    elseif event == "QUEST_DETAIL" or event == "QUEST_GREETING" then
        CaptureQuestFromGossip()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if frame and frame:IsShown() then
            C_Timer.After(1, RefreshPanel)
        end

    elseif event == "QUEST_LOG_UPDATE" then
        -- objectives ticking over can flip a quest to ready; fires often, so debounce
        if frame and frame:IsShown() and not logRefreshPending then
            logRefreshPending = true
            C_Timer.After(1, function()
                logRefreshPending = false
                RefreshPanel()
            end)
        end
    end
end)

-- ── slash commands ──

SLASH_KEWKYQUEST1 = "/kq"
SLASH_KEWKYQUEST2 = "/kewkyquest"
SlashCmdList["KEWKYQUEST"] = function(msg)
    msg = strtrim(msg):lower()

    if msg == "route" then
        filteredQuests = ScanWithAdjacent()
        currentRoute = ComputeRoute(filteredQuests)
        PrintRoute(currentRoute)
        StartRoute(currentRoute)
        UpdateMapPins()

    elseif msg == "next" then
        if followRoute then FollowStop(followIdx + 1) end

    elseif msg == "arrow" or msg == "clear" then
        followRoute, followIdx = nil, nil
        ClearArrow()

    elseif msg == "why" then
        ExplainTarget()

    elseif msg == "sparkle" then
        if ns.ToggleSparkle then ns.ToggleSparkle() end

    elseif msg == "debug" then
        BuildZoneMap()
        local lines = {}
        local function out(fmt, ...)
            local line = string.format(fmt, ...)
            lines[#lines + 1] = line
            print("|cff55ccffKQ|r " .. line)
        end
        local chain = {}
        for _, id in ipairs(ZoneChain(PlayerMapID())) do
            local info = CMap.GetMapInfo(id)
            chain[#chain + 1] = string.format("%d=%s(type %s)", id, info and info.name or "?", info and tostring(info.mapType) or "?")
        end
        out("player chain: %s", table.concat(chain, " > "))
        local zones = {}
        for area in pairs(FindPlayerDBZones()) do zones[#zones + 1] = area .. "=" .. ZoneName(area) end
        out("player DB zones: %s", table.concat(zones, ", "))
        local mapped = 0
        for _ in pairs(areaToUiMap) do mapped = mapped + 1 end
        out("zones mapped: %d", mapped)
        for _, area in ipairs({ 14, 17, 215, 1637, 16606 }) do
            local ui = UiMapFor(area)
            local info = ui and CMap.GetMapInfo(ui)
            out("area %d (%s) -> uiMap %s %s", area, ns.ZoneNames[area] or "?", tostring(ui), info and info.name or "")
        end
        local px, py, cont = PlayerWorldPos()
        local logN = 0
        for _ in pairs(QuestLogInfo()) do logN = logN + 1 end
        out("quest log entries: %d", logN)
        out("player world: %s, %s cont %s", tostring(px), tostring(py), tostring(cont))
        out("api: WorldFromMap=%s MapFromWorld=%s ReadyForTurnIn=%s IsComplete=%s LogIndex=%s",
            tostring(CMap.GetWorldPosFromMapPos ~= nil), tostring(CMap.GetMapPosFromWorldPos ~= nil),
            tostring(CQL.ReadyForTurnIn ~= nil), tostring(CQL.IsComplete ~= nil),
            tostring(CQL.GetLogIndexForQuestID ~= nil))
        local list = ScanWithAdjacent()
        local inlog = 0
        for _, e in ipairs(list) do
            if e.status == "inlog" then
                inlog = inlog + 1
                out("  log %d %s ready=%s -> %s %d yd", e.questID, QName(e.quest) or "?",
                    tostring(e.ready), e.stop and e.stop.name or "?", e.distance)
            end
        end
        out("scan: %d quests (%d in log)", #list, inlog)
        KewkyQuestSV.debug = lines

    elseif msg == "done" then
        local n = SnapshotCompleted()
        local hist = KewkyQuestSV.history or {}
        print(string.format("|cff55ccffKewkyQuest|r: %d quests completed, %d turned in since tracking started.", n, #hist))
        for i = #hist, math.max(1, #hist - 14), -1 do
            local h = hist[i]
            local q = ns.QuestDB[h.id]
            print(string.format("  %s  L%d  %s |cff999999(%s)|r", date("%m/%d %H:%M", h.t), h.level or 0,
                q and QName(q) or ("Quest " .. h.id), ZoneName(h.zone)))
        end

    elseif msg == "reset" then
        KewkyQuestSV.pos = nil
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
        end
        print("|cff55ccffKewkyQuest|r: Position reset.")

    elseif msg == "scan" then
        local results = ScanWithAdjacent()
        print("|cff55ccffKewkyQuest|r: Found " .. #results .. " quests in range.")
        for i, r in ipairs(results) do
            if i > 15 then
                print("  ... and " .. (#results - 15) .. " more. Use /kq to see all.")
                break
            end
            local c = r.color
            print(string.format("  |cff%02x%02x%02x[%d] %s|r from %s",
                math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255),
                QLevel(r.quest) or 0, QName(r.quest) or "?", r.npcName))
        end

    elseif msg == "discovered" then
        local count = 0
        for _ in pairs(KewkyQuestSV.discovered or {}) do count = count + 1 end
        print("|cff55ccffKewkyQuest|r: " .. count .. " quests discovered at runtime.")

    else
        TogglePanel()
    end
end
