local ADDON_NAME, ns = ...

-- Quest info tab: a side tab on the right edge of the Map & Quest Log window (where retail keeps its
-- quest log tabs; Forever hides them) that opens a panel beside the window with what KewkyQuest knows
-- about the quest on screen: giver, turn-in, objective spots, the game's own marker, the chain,
-- class limits and your turn-in history. Arrow buttons point the KewkyQuest arrow there.
--
-- Our own frames only, anchored to QuestMapFrame: nothing is added to Blizzard's tab or content
-- lists, which would taint the quest log.

local Q = ns.Q
local QF = ns.QF

local tab, panel
local rows, nRows = {}, 0
local shownQuest

local ROW_GAP = 2
local PANEL_W = 300

-- ── which quest ──

local function DetailQuestID()
    local id = QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
    if id and id > 0 then return id end
    id = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if id and id > 0 then return id end
    return nil
end

-- ── rows: a line of text with an optional button ──

local function ResetRows()
    for i = 1, nRows do rows[i]:Hide() end
    nRows = 0
end

local function Row()
    nRows = nRows + 1
    local r = rows[nRows]
    if not r then
        r = CreateFrame("Frame", nil, panel.content)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("TOPLEFT", 0, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(true)
        r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.btn:SetSize(52, 18)
        r.btn:SetPoint("TOPRIGHT", 0, 1)
        r.btn:SetScript("OnClick", function(self) if self.action then self.action() end end)
        rows[nRows] = r
    end
    r:Show()
    return r
end

local function Add(text, font, button, action)
    local r = Row()
    local width = panel.content:GetWidth()
    r.text:SetFontObject(font or "GameFontHighlightSmall")
    r.text:SetWidth(button and width - 58 or width)
    r.text:SetText(text)
    r.btn:SetShown(button ~= nil)
    if button then
        r.btn:SetText(button)
        r.btn.action = action
    end
    r:SetSize(width, math.max(r.text:GetStringHeight(), button and 18 or 0))
    return r
end

local function Header(text)
    local r = Add(text, "GameFontNormal")
    r.isHeader = true
end

local function Layout()
    local y = 0
    for i = 1, nRows do
        local r = rows[i]
        if r.isHeader and i > 1 then y = y + 8 end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
        y = y + r:GetHeight() + ROW_GAP
    end
    panel.content:SetHeight(math.max(y, 1))
end

-- ── facts ──

local function Coords(zone, x, y)
    return string.format("%s (%.1f, %.1f)", ns.ZoneName(zone), x or 0, y or 0)
end

local function Yards(wx, wy)
    local px, py = ns.PlayerWorldPos()
    if not (px and wx) then return "" end
    return string.format("  |cff9d9d9d%d yd|r", ns.Dist2D(px, py, wx, wy))
end

local function QuestTitle(id)
    local q = ns.QuestDB[id]
    if q and Q.Name(q) then return Q.Name(q) end
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return t or ("Quest " .. id)
end

local function Done(id)
    return ns.IsQuestCompleted(id) and "|cff33e64d(done)|r" or (ns.IsQuestInLog(id) and "|cff55aaff(in log)|r" or "|cffff7070(not done)|r")
end

local function NPCLines(list, verb)
    if not list or #list == 0 then
        Add("|cff9d9d9dnot in the database|r")
        return
    end
    for _, npcID in ipairs(list) do
        local npc = ns.NPCS[npcID]
        if npc then
            local stop = ns.NPCStop(npcID, npc)
            Add(string.format("%s\n|cff9d9d9d%s|r%s", npc[ns.NF.NAME] or ("NPC " .. npcID),
                    Coords(npc[ns.NF.ZONE], npc[ns.NF.X], npc[ns.NF.Y]), stop and Yards(stop.wx, stop.wy) or ""),
                nil, stop and "Arrow" or nil,
                stop and function() ns.SetArrow(stop, verb .. ": " .. (npc[ns.NF.NAME] or "?")) end)
        else
            Add("NPC " .. npcID .. " |cff9d9d9d(no location)|r")
        end
    end
end

-- objective spots grouped by target, with the nearest spot and whether it's still needed
local function ObjectiveLines(id)
    local all = ns.Objectives and ns.Objectives[id]
    if not all then
        Add("|cff9d9d9dno objective locations in the database|r")
        return
    end
    local open = {}
    for _, r in ipairs(ns.OpenObjectiveRows(id, all)) do open[r] = true end
    local px, py = ns.PlayerWorldPos()
    local groups, order = {}, {}
    for _, r in ipairs(all) do
        local g = groups[r[1]]
        if not g then
            g = { label = r[1], spots = 0, open = false }
            groups[r[1]] = g
            order[#order + 1] = g
        end
        g.open = g.open or open[r] or false
        for i = 3, #r - 1, 2 do
            g.spots = g.spots + 1
            local wx, wy = ns.WorldPos(r[2], r[i], r[i + 1])
            local d = (px and wx) and ns.Dist2D(px, py, wx, wy) or nil
            if d and (not g.d or d < g.d) then
                g.d, g.stop = d, { name = r[1], zone = r[2], x = r[i], y = r[i + 1] }
            end
        end
    end
    for _, g in ipairs(order) do
        local item = not g.label:match("^Kill ") and not g.label:match("^Use ") and g.label:match("^([^:]+):")
        local held = item and ns.BagCount(item) or 0
        local state = g.open and "" or " |cff33e64d(done)|r"
        local extra = string.format("|cff9d9d9d%d spot%s%s%s|r", g.spots, g.spots == 1 and "" or "s",
            g.d and string.format(", nearest %d yd", g.d) or "", held > 0 and (", " .. held .. " in bags") or "")
        Add(g.label .. state .. "\n" .. extra, nil, g.stop and "Arrow" or nil,
            g.stop and function() ns.SetArrow(g.stop, QuestTitle(id) .. ": " .. g.label) end)
    end
end

local function ClassNames(mask)
    if not mask or mask == 0 then return nil end
    local names = {}
    for classID = 1, 13 do
        local bit = 2 ^ (classID - 1)
        if mask % (bit * 2) >= bit then
            local name = GetClassInfo and GetClassInfo(classID)
            names[#names + 1] = name or ("class " .. classID)
        end
    end
    return table.concat(names, ", ")
end

local function Render()
    if not panel or not panel:IsShown() then return end
    ResetRows()
    local id = DetailQuestID()
    shownQuest = id
    if not id then
        panel.title:SetText("Quest Info")
        Add("Open a quest in the log, or track one, to see what KewkyQuest knows about it.")
        Layout()
        return
    end

    local q = ns.QuestDB[id]
    panel.title:SetText(QuestTitle(id))

    Header("Quest")
    local status
    if ns.IsQuestCompleted(id) then status = "|cff33e64dCompleted|r"
    elseif ns.IsQuestInLog(id) then status = ns.IsReadyForTurnIn(id) and "|cff33e64dReady to turn in|r" or "|cff55aaffIn your log|r"
    else status = "Not started" end
    Add(string.format("ID %d   ·   %s", id, status))
    if q then
        Add(string.format("Level %s   ·   requires %s   ·   %s", tostring(Q.Level(q) or "?"),
            tostring(Q.MinLevel(q) or "?"), ns.ZoneName(Q.Zone(q))))
        local classes = ClassNames(Q.Classes(q))
        if classes then Add("Classes: " .. classes) end
    else
        Add("|cffff7070Not in KewkyQuest's database|r (a Forever-only quest, probably).")
    end
    Add("Follow this quest with the arrow", nil, "Follow", function() ns.SetQuestArrow(id) end)

    if q then
        Header("Quest giver")
        NPCLines(Q.Givers(q), "Pick up")
        Header("Turn in")
        NPCLines(Q.Finishers(q), "Turn in")
    end

    Header("Objectives")
    ObjectiveLines(id)

    Header("Game's map marker")
    local poi = ns.GamePOI(id)
    if poi then
        Add(string.format("%s at %.1f, %.1f\n|cff9d9d9d%s|r", poi.name, poi.x, poi.y,
            (C_Map.GetMapInfo(poi.uiMap) or {}).name or ("map " .. poi.uiMap)),
            nil, "Arrow", function() ns.SetArrow(poi, QuestTitle(id) .. ": " .. poi.name, id) end)
    else
        Add("|cff9d9d9dnone right now (the game only marks quests in your log)|r")
    end

    if q then
        local pre, nxt = Q.Prereqs(q), q[QF.NEXT]
        if (pre and #pre > 0) or nxt then
            Header("Chain")
            for _, p in ipairs(pre or {}) do Add("Requires: " .. QuestTitle(p) .. " " .. Done(p)) end
            if nxt then Add("Leads to: " .. QuestTitle(nxt) .. " " .. Done(nxt)) end
        end
    end

    local hist = {}
    for _, h in ipairs(KewkyQuestSV and KewkyQuestSV.history or {}) do
        if h.id == id then hist[#hist + 1] = h end
    end
    if #hist > 0 then
        Header("Your history")
        for _, h in ipairs(hist) do
            Add(string.format("Turned in %s at level %s, +%d XP", date("%b %d %H:%M", h.t), tostring(h.level), h.xp or 0))
        end
    end

    Header("About this data")
    Add("|cff9d9d9dQuest, NPC and spawn data comes from the Classic quest database; Forever may have moved things. The map marker comes from the game.|r")
    Layout()
end

-- ── frames ──

local function BuildPanel()
    panel = CreateFrame("Frame", "KewkyQuestInfoPanel", QuestMapFrame, "BasicFrameTemplateWithInset")
    panel:SetWidth(PANEL_W)
    panel:SetPoint("TOPLEFT", tab, "TOPRIGHT", 2, 28)
    panel:SetPoint("BOTTOM", QuestMapFrame, "BOTTOM", 0, -6)
    panel:SetFrameStrata(QuestMapFrame:GetFrameStrata())
    panel.title = panel.TitleText or panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not panel.TitleText then panel.title:SetPoint("TOP", 0, -5) end
    panel.title:SetWidth(PANEL_W - 40)

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 10, -30)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(PANEL_W - 44, 1)
    panel.scroll:SetScrollChild(panel.content)

    panel:SetScript("OnShow", function() tab:SetChecked(true) Render() end)
    panel:SetScript("OnHide", function() tab:SetChecked(false) end)
    panel:Hide()
end

local function BuildTab()
    if tab or not QuestMapFrame then return end
    tab = CreateFrame("Frame", "KewkyQuestInfoTab", QuestMapFrame, "LargeSideTabButtonTemplate")
    -- where Blizzard's quests tab sits on Forever (QuestMapFrameOverrides.GetQuestsTabAnchorOffset)
    tab:SetPoint("TOPLEFT", QuestMapFrame, "TOPRIGHT", 5, -28)
    tab.Icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    tab:SetFillToInterior(true, 26)
    tab:EnableMouse(true)
    tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
        if button == "LeftButton" and upInside then
            KewkyQuestSV.infoOpen = not panel:IsShown()
            panel:SetShown(KewkyQuestSV.infoOpen)
        end
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Quest Info")
        GameTooltip:AddLine("What KewkyQuest knows about the open quest: NPCs, objective spots, chain.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    tab:SetChecked(false)
    BuildPanel()
    -- open by default, so M brings up the map, the log and this panel together; the tab closes it (remembered)
    if KewkyQuestSV.infoOpen ~= false then panel:Show() end

    -- follow the quest the log shows
    if QuestMapFrame_ShowQuestDetails then hooksecurefunc("QuestMapFrame_ShowQuestDetails", function() C_Timer.After(0, Render) end) end
    if QuestMapFrame_CloseQuestDetails then hooksecurefunc("QuestMapFrame_CloseQuestDetails", function() C_Timer.After(0, Render) end) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("SUPER_TRACKING_CHANGED")
f:RegisterEvent("ADDON_LOADED")
local pending = false
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and name == "Blizzard_WorldMap") then
        BuildTab()
    elseif panel and panel:IsShown() and not pending then
        pending = true
        C_Timer.After(0.5, function() pending = false Render() end)
    end
end)
