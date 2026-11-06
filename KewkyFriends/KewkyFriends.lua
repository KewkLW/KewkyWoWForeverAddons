local ADDON_NAME = ...

-- Forever is realmless: friends can group only on the same region, ruleset and faction.
-- The ruleset is the last word of the server name ("CAMWOW US2 Realm 5 PvE"), which the
-- friends list hides when unique names are on. Shown on each friend card, in its tooltip
-- and in the right-click menu.

local RULESETS = {
    pve = "Normal", normal = "Normal",
    pvp = "PvP",
    rp = "Roleplaying", roleplaying = "Roleplaying",
    rppvp = "RP-PvP",
    hc = "Hardcore", hardcore = "Hardcore",
}

local RED, GREEN, GRAY = "|cffff5050", "|cff60ff60", "|cff9d9d9d"

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffKewkyFriends|r " .. msg)
end

-- "Normal"/"PvP"/... from a server name, nil when the last word isn't a known ruleset
local function RulesetOf(realm)
    if not realm or realm == "" then return nil end
    local last = realm:match("(%a[%a%-]*)%s*$") or realm
    return RULESETS[last:lower():gsub("%-", "")]
        or RULESETS[(realm:match("(%a+)$") or ""):lower()]
end

local function MyRealm()
    return GetRealmName() or ""
end

-- Info about a friend's current WoW Forever character, or nil if they're not on one
local function FriendState(accountInfo)
    local g = accountInfo and accountInfo.gameAccountInfo
    if not (g and g.isOnline and g.clientProgram == BNET_CLIENT_WOW and g.characterName) then return nil end
    if g.wowProjectID and WOW_PROJECT_ID and g.wowProjectID ~= WOW_PROJECT_ID then return nil end

    local realm = g.realmName or g.realmDisplayName
    local ruleset, mine = RulesetOf(realm), RulesetOf(MyRealm())
    local myFaction = UnitFactionGroup("player")
    local s = {
        realm = realm,
        ruleset = ruleset,
        faction = g.factionName,
        sameRegion = g.isInCurrentRegion,
    }
    -- true/false when both sides are known, nil when one isn't
    if ruleset and mine then s.sameRuleset = (ruleset == mine) end
    if g.factionName and myFaction then s.sameFaction = (g.factionName == myFaction) end
    if s.sameRegion == false or s.sameRuleset == false or s.sameFaction == false then
        s.canGroup = false
    elseif s.sameRuleset and s.sameFaction then
        s.canGroup = true
    end
    return s
end

local function ReasonText(s)
    local why = {}
    if s.sameRegion == false then why[#why + 1] = "other region" end
    if s.sameRuleset == false then why[#why + 1] = "different ruleset" end
    if s.sameFaction == false then why[#why + 1] = "other faction" end
    return table.concat(why, ", ")
end

-- short tag for the card: the ruleset, plus the faction when it differs
local function CardTag(s)
    local color = s.sameRuleset == false and RED or (s.sameRuleset and GREEN or GRAY)
    local tag = color .. (s.ruleset or "?") .. "|r"
    if s.sameFaction == false then tag = tag .. " " .. RED .. s.faction .. "|r" end
    return tag
end

local function GroupLine(s)
    if s.canGroup == true then return GREEN .. "Can group with you|r" end
    if s.canGroup == false then return RED .. "Can't group: " .. ReasonText(s) .. "|r" end
    return GRAY .. "Can't tell if you can group (ruleset unknown)|r"
end

-- ── friend cards and their tooltip ──
-- Uses the scroll box's frame callback and HookScript only: writing into Blizzard's card
-- mixin taints every card copied from it, and the friends frame then gets blocked.

local cardsHooked, tooltipHooked = false, setmetatable({}, { __mode = "k" })

local function CardState(card)
    local data = card.elementData
    return FriendState(data and data.accountInfo)
end

local function OnCardEnter(card)
    local s = CardState(card)
    if not s or not GameTooltip:IsOwned(card) then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Ruleset", s.ruleset or "?", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Server", s.realm or "?", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine(GroupLine(s))
    GameTooltip:Show()
end

local function OnCardInitialized(_, card)
    if not card.Location then return end
    if not tooltipHooked[card] then
        tooltipHooked[card] = true
        card:HookScript("OnEnter", OnCardEnter)
    end
    local s = CardState(card)
    if s then card.Location:SetText((card.Location:GetText() or "") .. "  " .. CardTag(s)) end
end

local function HookCards()
    local list = SocialUIFrame and SocialUIFrame.FriendsList
    local box = list and list.ScrollBox
    if cardsHooked or not (box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    cardsHooked = true
    ScrollUtil.AddInitializedFrameCallback(box, OnCardInitialized, ADDON_NAME, true)
end

-- ── right-click menu ──

local function AddMenuInfo(owner, rootDescription, contextData)
    local id = contextData and contextData.bnetIDAccount
    local info = id and C_BattleNet.GetAccountInfoByID(id)
    local s = FriendState(info)
    if not s then return end
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("Ruleset: " .. CardTag(s))
    rootDescription:CreateTitle(GroupLine(s))
end

-- ── /kfr: raw data, to check the server-name format ──

SLASH_KEWKYFRIENDS1 = "/kfr"
SlashCmdList.KEWKYFRIENDS = function()
    Print(string.format("you: %s | ruleset %s | %s", MyRealm(), tostring(RulesetOf(MyRealm())), tostring(UnitFactionGroup("player"))))
    local n = 0
    for i = 1, BNGetNumFriends() do
        local a = C_BattleNet.GetFriendAccountInfo(i)
        local g = a and a.gameAccountInfo
        if g and g.characterName then
            n = n + 1
            local s = FriendState(a)
            Print(string.format("%s: %s | server %s / %s | %s %s | %s",
                a.accountName or "?", g.characterName, tostring(g.realmName), tostring(g.realmDisplayName),
                tostring(g.factionName), tostring(g.raceName), s and GroupLine(s) or "not on Forever"))
        end
    end
    if n == 0 then Print("no Battle.net friends online in WoW") end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        HookCards()
        if Menu and Menu.ModifyMenu then Menu.ModifyMenu("MENU_UNIT_BN_FRIEND", AddMenuInfo) end
    elseif name == "Blizzard_SocialUI" or name == "Blizzard_FriendsFrame" then
        HookCards()
    end
end)
